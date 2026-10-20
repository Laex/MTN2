# Puts libcurl next to the network plugin (-Dest = the plugin folder in the build output).
#
# Source, first that exists:
#   1. the folder named by MTN2_CURL_DIR (a libcurl-x64.dll or libcurl-4.dll with what it needs),
#   2. tools\curl\ (fetch-curl.ps1: the official curl build, one self-contained DLL; with
#      -Fetch it is downloaded when missing),
#   3. the curl of Git for Windows (OpenSSL build and its DLLs) - for development machines.
# Without any of them the plugin still loads and says the library is missing.
param(
    [Parameter(Mandatory)][string]$Dest,
    # Download the official build (fetch-curl.ps1) when none is at hand.
    [switch]$Fetch
)
$ErrorActionPreference = 'Stop'
$Own = Join-Path $PSScriptRoot 'curl'
$GitBin = 'C:\Program Files\Git\mingw64\bin'

function Copy-Set([string]$Dir, [string]$Main, [string[]]$Extra) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    Copy-Item (Join-Path $Dir $Main) (Join-Path $Dest 'libcurl-x64.dll') -Force
    foreach ($Name in $Extra) {
        $F = Join-Path $Dir $Name
        if (Test-Path $F) { Copy-Item $F (Join-Path $Dest $Name) -Force }
    }
}

if ($env:MTN2_CURL_DIR -and (Test-Path $env:MTN2_CURL_DIR)) {
    $Main = @('libcurl-x64.dll', 'libcurl-4.dll', 'libcurl.dll') |
        Where-Object { Test-Path (Join-Path $env:MTN2_CURL_DIR $_) } | Select-Object -First 1
    if ($Main) {
        $Others = Get-ChildItem $env:MTN2_CURL_DIR -Filter '*.dll' | ForEach-Object Name
        Copy-Set $env:MTN2_CURL_DIR $Main $Others
        Write-Host "OK: staged libcurl from $env:MTN2_CURL_DIR"
        exit 0
    }
}
if ($Fetch -and -not (Test-Path (Join-Path $Own 'libcurl-x64.dll'))) {
    try { & (Join-Path $PSScriptRoot 'fetch-curl.ps1') | Out-Null }
    catch { Write-Host "WARN: libcurl download failed: $_" }
}
if (Test-Path (Join-Path $Own 'libcurl-x64.dll')) {
    Copy-Set $Own 'libcurl-x64.dll' @('COPYING.txt', 'curl-ca-bundle.crt')
    Write-Host "OK: staged libcurl from $Own"
    exit 0
}
if (Test-Path (Join-Path $GitBin 'libcurl-openssl-4.dll')) {
    Copy-Set $GitBin 'libcurl-openssl-4.dll' @(
        'libbrotlicommon.dll', 'libbrotlidec.dll', 'libcrypto-3-x64.dll', 'libiconv-2.dll',
        'libidn2-0.dll', 'libintl-8.dll', 'libnghttp2-14.dll', 'libpsl-5.dll', 'libssh2-1.dll',
        'libssl-3-x64.dll', 'libunistring-5.dll', 'libzstd.dll', 'zlib1.dll')
    Write-Host "OK: staged libcurl of Git for Windows (development only)"
    exit 0
}
Write-Host "WARN: libcurl not found; run src\tools\fetch-curl.ps1 for the network plugin"
