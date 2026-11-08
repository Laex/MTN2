# Writes the files that describe a release's packages (run after the packages
# are in dist\):
#   dist\SHA256SUMS                      -- sha256sum format ("<hash>  <name>"),
#                                           one line per package; verify with
#                                           `sha256sum -c SHA256SUMS`
#   dist\MTN2-<Version>-sbom.cdx.json    -- CycloneDX 1.5 list of the bundled
#                                           third-party components (the ones in
#                                           THIRD-PARTY.md), read from the
#                                           files of the Windows package
# Versions come from the files' own version resources; a library without one is
# listed without a version.
param(
    [Parameter(Mandatory)]
    [string]$Version,
    [string]$Dist
)
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
if (-not $Dist) { $Dist = Join-Path $Root 'dist' }

# --- SHA256SUMS -----------------------------------------------------------
$Packages = @(Get-ChildItem $Dist -File |
    Where-Object { $_.Name -match '\.(zip|tar\.gz|deb|rpm)$' } |
    Sort-Object Name)
if ($Packages.Count -eq 0) { throw "no packages in $Dist" }
$Sums = foreach ($P in $Packages) {
    $Hash = (Get-FileHash $P.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $($P.Name)"
}
$SumsFile = Join-Path $Dist 'SHA256SUMS'
[System.IO.File]::WriteAllText($SumsFile, (($Sums -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "wrote $SumsFile ($($Packages.Count) packages)"

# --- SBOM -----------------------------------------------------------------
# Path inside the package, name, SPDX license expression, home page, whether
# the package must carry it. Licenses are those THIRD-PARTY.md states.
$Components = @(
    @{ Path = 'plugins\mtn.7z\7z.dll'; Name = '7-Zip'; License = 'LGPL-2.1-or-later AND BSD-3-Clause AND BSD-2-Clause'
       Url = 'https://www.7-zip.org'; Required = $true },
    @{ Path = 'plugins\mtn.net\libcurl-x64.dll'; Name = 'curl'; License = 'curl'
       Url = 'https://curl.se'; Required = $true },
    @{ Path = 'plugins\mtn.lua\lua55.dll'; Name = 'Lua'; License = 'MIT'
       Url = 'https://www.lua.org'; Required = $true },
    @{ Path = 'plugins\mtn.pdf\pdfium.dll'; Name = 'PDFium'; License = 'BSD-3-Clause AND Apache-2.0'
       Url = 'https://pdfium.googlesource.com/pdfium/'; Required = $false },
    @{ Path = 'plugins\mtn.highlight'; Name = 'syntect (mtn.highlight)'; License = 'MIT'
       Url = 'https://github.com/trishume/syntect'; Required = $false }
)

$Zip = Join-Path $Dist "MTN2-$Version-win64.zip"
if (-not (Test-Path $Zip)) { throw "$Zip not found" }
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("mtn2-sbom-" + [guid]::NewGuid())
try {
    Expand-Archive -Path $Zip -DestinationPath $Temp
    $Items = foreach ($C in $Components) {
        $File = Join-Path $Temp $C.Path
        if (-not (Test-Path $File)) {
            if ($C.Required) { throw "$($C.Path) is not in $Zip" }
            Write-Host "WARN: $($C.Path) is not in the package; left out of the SBOM"
            continue
        }
        $Item = [ordered]@{
            type = 'library'
            'bom-ref' = $C.Name
            name = $C.Name
        }
        if (Test-Path $File -PathType Leaf) {
            $Product = ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($File).ProductVersion + '').Trim()
            if ($Product) { $Item.version = $Product }
            $Item.hashes = @(@{ alg = 'SHA-256'; content = (Get-FileHash $File -Algorithm SHA256).Hash.ToLowerInvariant() })
        }
        $Item.licenses = @(@{ expression = $C.License })
        $Item.externalReferences = @(@{ type = 'website'; url = $C.Url })
        $Item
    }
}
finally {
    if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force }
}

$Tag = $Version.TrimStart('v')
$Bom = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    serialNumber = 'urn:uuid:' + [guid]::NewGuid()
    version = 1
    metadata = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        component = [ordered]@{ type = 'application'; 'bom-ref' = 'MTN2'; name = 'MTN2'; version = $Tag }
    }
    components = @($Items)
    dependencies = @(@{ ref = 'MTN2'; dependsOn = @($Items | ForEach-Object { $_['bom-ref'] }) })
}
$SbomFile = Join-Path $Dist "MTN2-$Version-sbom.cdx.json"
[System.IO.File]::WriteAllText($SbomFile, ($Bom | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-Host "wrote $SbomFile ($(@($Items).Count) components)"

# --- verify what was written ---------------------------------------------
foreach ($Line in Get-Content $SumsFile) {
    $Hash, $Name = $Line -split '  ', 2
    $Actual = (Get-FileHash (Join-Path $Dist $Name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Hash) { throw "SHA256SUMS does not match $Name" }
}
$null = Get-Content $SbomFile -Raw | ConvertFrom-Json
