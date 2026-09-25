# Optional Wasmtime C API runtime for stage 30 (not committed; Apache-2.0).
# Downloads wasmtime.dll into this folder so TestWasmHost / MTN2 can LoadLibrary it.
param(
    [string]$Version = 'v26.0.1'
)
$ErrorActionPreference = 'Stop'
$OutDir = $PSScriptRoot + '\wasmtime'
$Dll = Join-Path $OutDir 'wasmtime.dll'
if (Test-Path $Dll) {
    Write-Host "OK: $Dll"
    exit 0
}
$ZipName = "wasmtime-$Version-x86_64-windows-c-api.zip"
$Url = "https://github.com/bytecodealliance/wasmtime/releases/download/$Version/$ZipName"
$Tmp = Join-Path $env:TEMP $ZipName
Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
$Extract = Join-Path $env:TEMP ("wasmtime-" + $Version + "-c-api")
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
Expand-Archive -Path $Tmp -DestinationPath $Extract -Force
$Found = Get-ChildItem -Path $Extract -Filter 'wasmtime.dll' -Recurse | Select-Object -First 1
if (-not $Found) { throw "wasmtime.dll missing from $ZipName" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Dll -Force
Write-Host "OK: $Dll"
