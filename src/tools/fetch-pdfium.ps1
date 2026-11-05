# PDFium for the PDF viewer plugin (not committed; BSD-3-Clause / Apache-2.0).
# Downloads the prebuilt library from bblanchon/pdfium-binaries into
# src\tools\pdfium (pdfium.dll; with -Linux, libpdfium.so into pdfium\linux64)
# together with its license files.
param(
    [string]$Version = 'chromium/8138',
    [switch]$Linux
)
$ErrorActionPreference = 'Stop'
$LibName = if ($Linux) { 'libpdfium.so' } else { 'pdfium.dll' }
$OutDir = $PSScriptRoot + '\pdfium' + $(if ($Linux) { '\linux64' } else { '' })
$Lib = Join-Path $OutDir $LibName
if (Test-Path $Lib) {
    Write-Host "OK: $Lib"
    exit 0
}
$Tag = $Version -replace '/', '-'
$Cache = & (Join-Path $PSScriptRoot 'cache-dir.ps1')
$CachedDir = if ($Cache) { Join-Path $Cache "pdfium-$Tag$(if ($Linux) { '-linux' })" }
if ($CachedDir -and (Test-Path (Join-Path $CachedDir $LibName))) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item (Join-Path $CachedDir '*') $OutDir -Force
    Write-Host "OK: $Lib (from $CachedDir)"
    exit 0
}
$Pack = if ($Linux) { 'pdfium-linux-x64.tgz' } else { 'pdfium-win-x64.tgz' }
$Url = "https://github.com/bblanchon/pdfium-binaries/releases/download/$Version/$Pack"
$Tmp = Join-Path $env:TEMP "$Tag-$Pack"
for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
    Write-Host "Downloading $Url (attempt $Attempt)"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
        break
    } catch {
        if ($Attempt -eq 4) { throw }
        Write-Host "WARN: download failed: $_"
        Start-Sleep -Seconds (5 * $Attempt)
    }
}
$Extract = Join-Path $env:TEMP "pdfium-$Tag-unpacked"
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Extract | Out-Null
tar -xzf $Tmp -C $Extract
if ($LASTEXITCODE -ne 0) { throw "cannot unpack $Pack" }
$Found = Get-ChildItem -Path $Extract -Filter $LibName -Recurse | Select-Object -First 1
if (-not $Found) { throw "$LibName missing from $Pack" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Lib -Force
$Licenses = Get-ChildItem -Path (Join-Path $Extract 'LICENSE*') -File -ErrorAction SilentlyContinue
if (Test-Path (Join-Path $Extract 'LICENSE')) { Copy-Item (Join-Path $Extract 'LICENSE') (Join-Path $OutDir 'LICENSE') -Force }
if (Test-Path (Join-Path $Extract 'licenses')) { Copy-Item (Join-Path $Extract 'licenses') $OutDir -Recurse -Force }
if ($CachedDir) {
    New-Item -ItemType Directory -Force -Path $CachedDir | Out-Null
    Copy-Item (Join-Path $OutDir '*') $CachedDir -Recurse -Force
}
Write-Host "OK: $Lib"
