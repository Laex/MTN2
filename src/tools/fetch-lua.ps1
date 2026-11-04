# Optional Lua 5.5 library for the macro plugin (plugins\mtn.lua), MIT license.
# Downloads the LuaBinaries Windows build into this folder's lua\ subfolder:
# lua55.dll and its license text. stage-lua.ps1 copies it next to the plugin.
param(
    [string]$Url = 'https://sourceforge.net/projects/luabinaries/files/5.5.0/Tools%20Executables/lua-5.5.0_Win64_bin.zip/download'
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot 'lua'
$Dll = Join-Path $OutDir 'lua55.dll'
if (Test-Path $Dll) {
    Write-Host "OK: $Dll"
    exit 0
}
$Cache = & (Join-Path $PSScriptRoot 'cache-dir.ps1')
$CachedDir = if ($Cache) { Join-Path $Cache 'lua' }
if ($CachedDir -and (Test-Path (Join-Path $CachedDir 'lua55.dll'))) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item (Join-Path $CachedDir '*') $OutDir -Force
    Write-Host "OK: $Dll (from $CachedDir)"
    exit 0
}
$Tmp = Join-Path $env:TEMP 'mtn2-lua-win64.zip'
for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
    Write-Host "Downloading $Url (attempt $Attempt)"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing -UserAgent 'Mozilla/5.0'
        break
    } catch {
        if ($Attempt -eq 4) { throw }
        Write-Host "WARN: download failed: $_"
        Start-Sleep -Seconds (5 * $Attempt)
    }
}
Write-Host ("SHA-256 of the download: " + (Get-FileHash $Tmp -Algorithm SHA256).Hash)
$Extract = Join-Path $env:TEMP 'mtn2-lua-win64'
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
Expand-Archive -Path $Tmp -DestinationPath $Extract -Force
$Found = Get-ChildItem -Path $Extract -Filter 'lua55.dll' -Recurse | Select-Object -First 1
if (-not $Found) { throw "lua55.dll not found in the archive" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Dll -Force
$License = Get-ChildItem -Path $Extract -Include 'COPYRIGHT*', 'LICENSE*' -Recurse -File | Select-Object -First 1
if ($License) { Copy-Item $License.FullName (Join-Path $OutDir 'LICENSE-lua.txt') -Force }
if ($CachedDir) {
    New-Item -ItemType Directory -Force -Path $CachedDir | Out-Null
    Copy-Item (Join-Path $OutDir '*') $CachedDir -Force
}
Write-Host "OK: $Dll"
