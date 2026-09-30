# Optional Wasmtime C API runtime for WASM plugins (not committed; Apache-2.0).
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
# The download is retried: a dropped connection must not leave a package
# without the runtime.
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
$Extract = Join-Path $env:TEMP ("wasmtime-" + $Version + "-c-api")
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
Expand-Archive -Path $Tmp -DestinationPath $Extract -Force
$Found = Get-ChildItem -Path $Extract -Filter 'wasmtime.dll' -Recurse | Select-Object -First 1
if (-not $Found) { throw "wasmtime.dll missing from $ZipName" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $Found.FullName $Dll -Force
Write-Host "OK: $Dll"
