# CHANGELOG.md -- what changes for the user from one release tag to the next.
# New entries go under "## Не выпущено" (Новое / Исправлено / Изменено)
# as the work lands; a release turns that section into its own.
#
#   ./src/tools/changelog.ps1 -Stamp v0.3.8
#       Before tagging (with the "Stamp 0.3.8." commit): "## Не выпущено"
#       becomes "## v0.3.8 – <today>" and a new empty "## Не выпущено" goes
#       above it, and src/MTN2.dproj's version info becomes 0.3.8 (local
#       builds without build.ps1 -Version report it; the updater compares it).
#       Refuses when there is nothing unreleased to stamp.
#   ./src/tools/changelog.ps1 -DevStamp v0.4.0.5
#       With the commit that becomes development build v0.4.0.5 (the number
#       src/tools/dev-version.ps1 gives it): "## Не выпущено" entries move under
#       "## Dev v0.4.0.5 – <today>". Does nothing when there are none. A later
#       -Stamp folds all Dev sections above the previous release into the
#       release section, merging their Новое / Изменено / Исправлено lists.
#   ./src/tools/changelog.ps1 -ProjectVersion v0.3.8
#       Only the MTN2.dproj part of -Stamp.
#   ./src/tools/changelog.ps1 -Section v0.3.8 -OutFile notes.md
#       release.yml: that version's section for the release page, with a link
#       to the whole CHANGELOG.md at the tag. Refuses when the version has no
#       section or it is empty, so a release never goes out without one.
param(
    [Parameter(Mandatory, ParameterSetName = 'Stamp')]
    [string]$Stamp,
    [Parameter(Mandatory, ParameterSetName = 'Dev')]
    [string]$DevStamp,
    [Parameter(ParameterSetName = 'Stamp')]
    [Parameter(ParameterSetName = 'Dev')]
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

# The "### " subsections of Lines[Start+1 .. End-1] as name -> entry lines
# (blank lines dropped), in order of appearance.
function Read-Subsections([int]$Start, [int]$End, $Into) {
    $Name = $null
    for ($I = $Start + 1; $I -lt $End; $I++) {
        if ($Lines[$I].StartsWith('### ')) {
            $Name = $Lines[$I].Substring(4).Trim()
            if (-not $Into.Contains($Name)) { $Into[$Name] = [Collections.Generic.List[string]]::new() }
        } elseif ($Name -and $Lines[$I].Trim()) {
            $Into[$Name].Add($Lines[$I])
        }
    }
}
function Format-Subsections($Subs) {
    $Out = [Collections.Generic.List[string]]::new()
    foreach ($Name in $Subs.Keys) {
        if ($Subs[$Name].Count -eq 0) { continue }
        $Out.Add("### $Name"); $Out.Add('')
        foreach ($Line in $Subs[$Name]) { $Out.Add($Line) }
        $Out.Add('')
    }
    $Out
}
# Subsections in the order the changelog uses; others follow.
function Sort-Subsections($Subs) {
    $Sorted = [ordered]@{}
    foreach ($Name in 'Новое', 'Изменено', 'Исправлено') {
        if ($Subs.Contains($Name)) { $Sorted[$Name] = $Subs[$Name] }
    }
    foreach ($Name in $Subs.Keys) { if (-not $Sorted.Contains($Name)) { $Sorted[$Name] = $Subs[$Name] } }
    $Sorted
}
function Write-Changelog($Before, $Middle, $After) {
    [IO.File]::WriteAllText($File, ((@($Before) + @($Middle) + @($After)) -join "`n"), $Utf8)
}

if ($PSCmdlet.ParameterSetName -eq 'Dev') {
    # A development build: what is unreleased moves under its own
    # "## Dev <version> - <date>" heading; nothing to move means nothing to do.
    if ($DevStamp -notmatch '^v?(\d+\.\d+\.\d+\.\d+)$') { throw "Dev version must look like v1.2.3.4, got '$DevStamp'" }
    $Ver = "v$($Matches[1])"
    if ((Find-Heading "^## Dev $([regex]::Escape($Ver))\b") -ge 0) { throw "CHANGELOG.md already has a Dev $Ver section" }
    $Start = Find-Heading "^$Unreleased\s*$"
    if ($Start -lt 0) { throw "CHANGELOG.md has no '$Unreleased' section" }
    $End = Section-End $Start
    if (-not (Has-Entries $Start $End)) { Write-Host "CHANGELOG.md: nothing unreleased, no Dev $Ver section"; return }
    $Subs = [ordered]@{}
    Read-Subsections $Start $End $Subs
    $Before = if ($Start -gt 0) { @($Lines[0..($Start - 1)]) } else { @() }
    $After = if ($End -lt $Lines.Count) { @($Lines[$End..($Lines.Count - 1)]) } else { @() }
    Write-Changelog $Before (@($Unreleased, '', "## Dev $Ver – $Date", '') + @(Format-Subsections (Sort-Subsections $Subs))) $After
    Write-Host "CHANGELOG.md: unreleased entries are now '## Dev $Ver – $Date'"
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Stamp') {
    # A release: the unreleased entries and every Dev section above the
    # previous release become the one section of the new version.
    $Tag = Normalize-Tag $Stamp
    if ((Find-Heading "^## $([regex]::Escape($Tag))\b") -ge 0) { throw "CHANGELOG.md already has a $Tag section" }
    $Start = Find-Heading "^$Unreleased\s*$"
    if ($Start -lt 0) { throw "CHANGELOG.md has no '$Unreleased' section" }
    $End = Section-End $Start
    $Pending = [Collections.Generic.List[object]]::new()
    $Pending.Add(@($Start, $End))
    while ($End -lt $Lines.Count -and $Lines[$End] -match '^## Dev ') {
        $Next = Section-End $End
        $Pending.Add(@($End, $Next))
        $End = $Next
    }
    $Any = $false
    foreach ($Range in $Pending) { if (Has-Entries $Range[0] $Range[1]) { $Any = $true } }
    if (-not $Any) { throw "'$Unreleased' is empty: describe the changes for users first" }
    $Subs = [ordered]@{}
    foreach ($Range in $Pending) { Read-Subsections $Range[0] $Range[1] $Subs }
    $Before = if ($Start -gt 0) { @($Lines[0..($Start - 1)]) } else { @() }
    $After = if ($End -lt $Lines.Count) { @($Lines[$End..($Lines.Count - 1)]) } else { @() }
    Write-Changelog $Before (@($Unreleased, '', "## $Tag – $Date", '') + @(Format-Subsections (Sort-Subsections $Subs))) $After
    Write-Host "CHANGELOG.md: '$Unreleased' and $($Pending.Count - 1) Dev section(s) are now '## $Tag – $Date'"
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
