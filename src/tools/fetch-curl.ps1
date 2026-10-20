# Optional libcurl for the network plugin (plugins\mtn.net), curl license (MIT style).
# Downloads the official Windows build from curl.se into this folder's curl\
# subfolder: libcurl-x64.dll (OpenSSL, libssh2, nghttp2 and zlib built in), its
# license and the CA bundle. stage-curl.ps1 copies it next to the plugin.
param(
    [string]$Url = 'https://curl.se/windows/latest.cgi?p=win64-mingw.zip'
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot 'curl'
$Dll = Join-Path $OutDir 'libcurl-x64.dll'
if (Test-Path $Dll) {
    Write-Host "OK: $Dll"
    exit 0
}
$Cache = & (Join-Path $PSScriptRoot 'cache-dir.ps1')
$CachedDir = if ($Cache) { Join-Path $Cache 'curl' }
if ($CachedDir -and (Test-Path (Join-Path $CachedDir 'libcurl-x64.dll'))) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item (Join-Path $CachedDir '*') $OutDir -Force
    Write-Host "OK: $Dll (from $CachedDir)"
    exit 0
}
$Tmp = Join-Path $env:TEMP 'mtn2-curl-win64-mingw.zip'
# Retried: a dropped connection must not leave a package without the library.
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
Write-Host ("SHA-256 of the download: " + (Get-FileHash $Tmp -Algorithm SHA256).Hash)
$Extract = Join-Path $env:TEMP 'mtn2-curl-win64-mingw'
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
Expand-Archive -Path $Tmp -DestinationPath $Extract -Force
$Found = Get-ChildItem -Path $Extract -Filter 'libcurl-x64.dll' -Recurse | Select-Object -First 1
if (-not $Found) { throw 'libcurl-x64.dll is missing from the curl package' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Dll -Force
$Root = Split-Path (Split-Path $Found.FullName -Parent) -Parent
$License = Get-ChildItem -Path $Root -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'COPYING', 'COPYING.txt' } | Select-Object -First 1
if ($License) { Copy-Item $License.FullName (Join-Path $OutDir 'COPYING.txt') -Force }
$Bundle = Get-ChildItem -Path $Root -Filter 'curl-ca-bundle.crt' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Bundle) { Copy-Item $Bundle.FullName (Join-Path $OutDir 'curl-ca-bundle.crt') -Force }
if ($CachedDir) {
    New-Item -ItemType Directory -Force -Path $CachedDir | Out-Null
    Copy-Item (Join-Path $OutDir '*') $CachedDir -Force
}
Write-Host "OK: $Dll"
