# Puts lua55.dll next to the macro plugin (-Dest = the plugin folder in the build output).
#
# Source, first that exists:
#   1. the file named by MTN2_LUA_DLL,
#   2. tools\lua\lua55.dll (fetch-lua.ps1; with -Fetch it is downloaded when missing).
# Without either the plugin still loads and says the library is missing.
param(
    [Parameter(Mandatory)][string]$Dest,
    [switch]$Fetch
)
$ErrorActionPreference = 'Stop'
$Own = Join-Path $PSScriptRoot 'lua'
$Source = $null
if ($env:MTN2_LUA_DLL -and (Test-Path $env:MTN2_LUA_DLL)) {
    $Source = $env:MTN2_LUA_DLL
} else {
    if (-not (Test-Path (Join-Path $Own 'lua55.dll'))) {
        try { & (Join-Path $PSScriptRoot 'fetch-lua.ps1') | Out-Null }
        catch { Write-Host "WARN: Lua download failed: $_" }
    }
    if (Test-Path (Join-Path $Own 'lua55.dll')) { $Source = Join-Path $Own 'lua55.dll' }
}
if (-not $Source) {
    Write-Host "WARN: lua55.dll not found; macros stay off (run src/tools/fetch-lua.ps1)"
    exit 0
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item $Source (Join-Path $Dest 'lua55.dll') -Force
$License = Join-Path (Split-Path $Source -Parent) 'LICENSE-lua.txt'
if (Test-Path $License) { Copy-Item $License (Join-Path $Dest 'LICENSE-lua.txt') -Force }
Write-Host "OK: staged lua55.dll from $Source"
