# CHANGELOG.md -- what changes for the user from one release tag to the next.
# New entries go under "## Не выпущено" (Новое / Исправлено / Изменено)
# as the work lands; a release turns that section into its own.
#
#   ./src/tools/changelog.ps1 -Stamp v0.3.8
#       Before tagging (with the "Stamp 0.3.8." commit): "## Не выпущено"
#       becomes "## v0.3.8 — <today>" and a new empty "## Не выпущено" goes
#       above it, and src/MTN2.dproj's version info becomes 0.3.8 (local
#       builds without build.ps1 -Version report it; the updater compares it).
#       Refuses when there is nothing unreleased to stamp.
#   ./src/tools/changelog.ps1 -ProjectVersion v0.3.8
#       Only the MTN2.dproj part of -Stamp.
#   ./src/tools/changelog.ps1 -Section v0.3.8 -OutFile notes.md
#       release.yml: that version's section for the release page, with a link
#       to the whole CHANGELOG.md at the tag. Refuses when the version has no
#       section or it is empty, so a release never goes out without one.
param(
    [Parameter(Mandatory, ParameterSetName = 'Stamp')]
    [string]$Stamp,
    [Parameter(ParameterSetName = 'Stamp')]
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
    [Parameter(Mandatory, ParameterSetName = 'Section')]
    [string]$Section,
    [Parameter(Mandatory, ParameterSetName = 'ProjectVersion')]
    [string]$ProjectVersion,
    [Parameter(Mandatory, ParameterSetName = 'Section')]
    [string]$OutFile,
    # owner/name for the link; defaults to GITHUB_REPOSITORY, then origin's URL.
    [Parameter(ParameterSetName = 'Section')]
    [string]$Repo = ''
)
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$File = Join-Path $Root 'CHANGELOG.md'
$Utf8 = [Text.UTF8Encoding]::new($false)
$Unreleased = '## Не выпущено'

function Normalize-Tag([string]$Tag) {
    if ($Tag -notmatch '^v?(\d+\.\d+\.\d+)$') { throw "Version must look like 1.2.3 or v1.2.3, got '$Tag'" }
    "v$($Matches[1])"
}

# MTN2.dproj version info (the fallback build.ps1 uses without -Version):
# VerInfo_MajorVer / MinorVer / Release and FileVersion / ProductVersion /
# Comments in VerInfo_Keys, in every configuration that sets them.
function Set-ProjectVersion([string]$Tag) {
    $null = $Tag -match '^v(\d+)\.(\d+)\.(\d+)$'
    $Major, $Minor, $Patch = $Matches[1], $Matches[2], $Matches[3]
    $Plain = "$Major.$Minor.$Patch"
    $Proj = Join-Path $Root 'src\MTN2.dproj'
    $Text = [IO.File]::ReadAllText($Proj)
    $Old = $Text
    $Text = $Text -replace '<VerInfo_MajorVer>\d+</VerInfo_MajorVer>', "<VerInfo_MajorVer>$Major</VerInfo_MajorVer>"
    $Text = $Text -replace '<VerInfo_MinorVer>\d+</VerInfo_MinorVer>', "<VerInfo_MinorVer>$Minor</VerInfo_MinorVer>"
    $Text = $Text -replace '<VerInfo_Release>\d+</VerInfo_Release>', "<VerInfo_Release>$Patch</VerInfo_Release>"
    $Text = $Text -replace '(?<=[>;])FileVersion=\d+\.\d+\.\d+\.\d+', "FileVersion=$Plain.0"
    $Text = $Text -replace '(?<=[>;])ProductVersion=\d+\.\d+\.\d+', "ProductVersion=$Plain"
    $Text = $Text -replace '(?<=[>;])Comments=v\d+\.\d+\.\d+', "Comments=v$Plain"
    if ($Text -notmatch "<VerInfo_Release>$Patch</VerInfo_Release>" -or $Text -notmatch "ProductVersion=$([regex]::Escape($Plain))") {
        throw "MTN2.dproj: version fields not found"
    }
    if ($Text -ne $Old) {
        # MTN2.dproj is UTF-8 with a BOM, as the IDE writes it.
        [IO.File]::WriteAllText($Proj, $Text, [Text.UTF8Encoding]::new($true))
    }
    Write-Host "MTN2.dproj: version $Plain"
}

if ($PSCmdlet.ParameterSetName -eq 'ProjectVersion') {
    Set-ProjectVersion (Normalize-Tag $ProjectVersion)
    return
}

# The lines of CHANGELOG.md split into sections: each starts at a "## " line.
$Lines = [IO.File]::ReadAllText($File, $Utf8).Replace("`r`n", "`n").Split("`n")
function Find-Heading([string]$Pattern) {
    for ($I = 0; $I -lt $Lines.Count; $I++) {
        if ($Lines[$I] -match $Pattern) { return $I }
    }
    -1
}
function Section-End([int]$Start) {
    for ($I = $Start + 1; $I -lt $Lines.Count; $I++) {
        if ($Lines[$I].StartsWith('## ')) { return $I }
    }
    $Lines.Count
}
function Has-Entries([int]$Start, [int]$End) {
    for ($I = $Start + 1; $I -lt $End; $I++) {
        if ($Lines[$I] -match '^\s*[-*] \S') { return $true }
    }
    $false
}

if ($PSCmdlet.ParameterSetName -eq 'Stamp') {
    $Tag = Normalize-Tag $Stamp
    if ((Find-Heading "^## $([regex]::Escape($Tag))\b") -ge 0) { throw "CHANGELOG.md already has a $Tag section" }
    $Start = Find-Heading "^$Unreleased\s*$"
    if ($Start -lt 0) { throw "CHANGELOG.md has no '$Unreleased' section" }
    $End = Section-End $Start
    if (-not (Has-Entries $Start $End)) { throw "'$Unreleased' is empty: describe the changes for users first" }
    # Drop the empty subsections ("### Новое" with nothing under it).
    $Body = [Collections.Generic.List[string]]::new()
    for ($I = $Start + 1; $I -lt $End; $I++) {
        if ($Lines[$I].StartsWith('### ')) {
            $J = $I + 1
            while ($J -lt $End -and -not $Lines[$J].StartsWith('### ')) { $J++ }
            if (Has-Entries ($I) $J) {
                for ($K = $I; $K -lt $J; $K++) { $Body.Add($Lines[$K]) }
            }
            $I = $J - 1
        } else {
            $Body.Add($Lines[$I])
        }
    }
    # (a..b with b < a counts down in PowerShell: slice only non-empty ranges)
    $Before = if ($Start -gt 0) { @($Lines[0..($Start - 1)]) } else { @() }
    $After = if ($End -lt $Lines.Count) { @($Lines[$End..($Lines.Count - 1)]) } else { @() }
    $New = $Before + @($Unreleased, '', "## $Tag — $Date") + $Body + $After
    [IO.File]::WriteAllText($File, ($New -join "`n"), $Utf8)
    Write-Host "CHANGELOG.md: '$Unreleased' is now '## $Tag — $Date'"
    Set-ProjectVersion $Tag
    return
}

$Tag = Normalize-Tag $Section
$Start = Find-Heading "^## $([regex]::Escape($Tag))\b"
if ($Start -lt 0) { throw "CHANGELOG.md has no '## $Tag' section; run changelog.ps1 -Stamp $Tag before tagging" }
$End = Section-End $Start
$Body = if ($End - 1 -ge $Start + 1) { @($Lines[($Start + 1)..($End - 1)]) } else { @() }
if (-not (Has-Entries $Start $End) -and -not ($Body -join '').Trim()) {
    throw "CHANGELOG.md's $Tag section is empty"
}

if (-not $Repo) { $Repo = $env:GITHUB_REPOSITORY }
if (-not $Repo) {
    $Url = git -C $Root remote get-url origin
    if ($Url -notmatch 'github\.com[:/](?<slug>[^/]+/[^/]+?)(\.git)?$') {
        throw "cannot tell owner/name from origin '$Url'; pass -Repo"
    }
    $Repo = $Matches.slug
}

$Last = $Body.Count - 1
while ($Last -ge 0 -and -not $Body[$Last].Trim()) { $Last-- }
$Body = if ($Last -ge 0) { @($Body[0..$Last]) } else { @() }
$Notes = @("## Что нового в $Tag") + $Body +
    @('', "Все изменения по версиям: [CHANGELOG.md](https://github.com/$Repo/blob/$Tag/CHANGELOG.md)", '')
$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
[IO.File]::WriteAllText($Path, (($Notes -join "`n").Trim() + "`n`n"), $Utf8)
Write-Host "Release notes for $Tag -> $OutFile"
