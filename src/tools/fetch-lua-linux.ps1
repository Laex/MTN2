# Lua 5.4 library for the macro plugin on Linux (MIT license). Takes liblua5.4.so.0 and its
# copyright file from the Debian 12 package (old glibc, so it runs on current distributions),
# into this folder's lua-linux\ subfolder. package-linux.ps1 puts it next to the plugin.
param(
    [string]$Url = 'https://deb.debian.org/debian/pool/main/l/lua5.4/liblua5.4-0_5.4.4-3+deb12u1_amd64.deb',
    [string]$Distro = 'Ubuntu-24.04',
    [string]$ExpectedSha256 = 'B042E78D02DD8457CF7DE253AE89992E50050F450D9BEC66843FFB1A14AB23C7'
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot 'lua-linux'
$Lib = Join-Path $OutDir 'liblua5.4.so.0'
if (Test-Path $Lib) {
    Write-Host "OK: $Lib"
    exit 0
}
$Cache = & (Join-Path $PSScriptRoot 'cache-dir.ps1')
$CachedDir = if ($Cache) { Join-Path $Cache 'lua-linux' }
if ($CachedDir -and (Test-Path (Join-Path $CachedDir 'liblua5.4.so.0'))) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item (Join-Path $CachedDir '*') $OutDir -Force
    Write-Host "OK: $Lib (from $CachedDir)"
    exit 0
}
$Work = Join-Path $env:TEMP 'mtn2-lua-linux'
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Deb = Join-Path $Work 'liblua.deb'
for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
    Write-Host "Downloading $Url (attempt $Attempt)"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Deb -UseBasicParsing
        break
    } catch {
        if ($Attempt -eq 4) { throw }
        Write-Host "WARN: download failed: $_"
        Start-Sleep -Seconds (5 * $Attempt)
    }
}
$Hash = (Get-FileHash $Deb -Algorithm SHA256).Hash
Write-Host "SHA-256 of the download: $Hash"
if ($Hash -ne $ExpectedSha256) { throw "SHA-256 mismatch: expected $ExpectedSha256" }
$Unpacked = Join-Path $Work 'x'
New-Item -ItemType Directory -Force -Path $Unpacked | Out-Null
$WslDeb = (wsl -d $Distro -- wslpath -a $Deb.Replace([string][char]92, '/')).Trim()
$WslOut = (wsl -d $Distro -- wslpath -a $Unpacked.Replace([string][char]92, '/')).Trim()
wsl -d $Distro -- dpkg-deb -x $WslDeb $WslOut
if ($LASTEXITCODE -ne 0) { throw "dpkg-deb failed with $LASTEXITCODE" }
$Found = Get-ChildItem -Path $Unpacked -Filter 'liblua5.4.so.0*' -Recurse -File | Where-Object { $_.Length -gt 10000 } | Select-Object -First 1
if (-not $Found) { throw 'liblua5.4.so.0 not found in the package' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Lib -Force
$License = Get-ChildItem -Path $Unpacked -Filter 'copyright' -Recurse -File | Select-Object -First 1
if ($License) { Copy-Item $License.FullName (Join-Path $OutDir 'LICENSE-lua.txt') -Force }
if ($CachedDir) {
    New-Item -ItemType Directory -Force -Path $CachedDir | Out-Null
    Copy-Item (Join-Path $OutDir '*') $CachedDir -Force
}
Write-Host "OK: $Lib"
