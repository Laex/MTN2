# Prints the version of a development build: the version stamped in
# MTN2.dproj (the last release) plus the number of commits since that
# release's tag, e.g. v0.3.12.3. Above the release it branches from, below
# the next one; local and CI builds of the same commit get the same number.
# Needs the release tag in the clone (CI: fetch-depth 0).
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Dproj = Get-Content (Join-Path $Root 'src\MTN2.dproj') -Raw
$Nums = foreach ($Key in 'MajorVer', 'MinorVer', 'Release') {
    if ($Dproj -notmatch "<VerInfo_$Key>(\d+)</VerInfo_$Key>") {
        throw "VerInfo_$Key not found in MTN2.dproj"
    }
    $Matches[1]
}
$Base = "v$($Nums -join '.')"
& git -C $Root rev-parse --verify --quiet "refs/tags/$Base" *> $null
if ($LASTEXITCODE -ne 0) {
    throw "tag $Base not found: fetch tags (git fetch --tags) to number a development build"
}
$Count = & git -C $Root rev-list --count "$Base..HEAD"
if ($LASTEXITCODE -ne 0) { throw "git rev-list failed: $LASTEXITCODE" }
if ([int]$Count -gt 65535) { throw "$Count commits since $Base do not fit the version resource (max 65535)" }
"$Base.$Count"
