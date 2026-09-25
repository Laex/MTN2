# Pack the runtime part of bin\ (after src\build.ps1) into dist\MTN2-<Version>-win64.zip.
param(
    [Parameter(Mandatory)]
    [string]$Version
)
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Bin = Join-Path $Root 'bin'
$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $Dist 'MTN2'

foreach ($Required in 'MTN2.exe', 'sk4d.dll') {
    # sk4d.dll: MTN2 renders through Skia and does not start without it.
    if (-not (Test-Path (Join-Path $Bin $Required))) {
        throw "bin\$Required not found; run src\build.ps1 first"
    }
}
if (-not (Test-Path (Join-Path $Bin 'wasmtime.dll'))) {
    Write-Host 'WARN: bin\wasmtime.dll missing -- WASM plugins will not load from this package'
}
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

# Debug/IDE by-products (*.map, *.rsm, *.drc) and dev tools stay out.
# 7z.dll is not ours to ship (LGPL + unRAR terms): users drop their own x64
# copy into plugins\mtn.7z\, as build.ps1 does from a local 7-Zip install.
foreach ($Name in 'MTN2.exe', 'sk4d.dll', 'wasmtime.dll', 'keymap.json') {
    $Src = Join-Path $Bin $Name
    if (Test-Path $Src) { Copy-Item $Src $Stage }
}
foreach ($Dir in 'help', 'plugins', 'Assets') {
    $Src = Join-Path $Bin $Dir
    if (Test-Path $Src) { Copy-Item $Src (Join-Path $Stage $Dir) -Recurse }
}
Get-ChildItem $Stage -Recurse -File -Filter '7z.dll' | Remove-Item -Force
Copy-Item (Join-Path $Root 'LICENSE') $Stage

$Safe = $Version -replace '[^\w.\-]', '_'
$Zip = Join-Path $Dist "MTN2-$Safe-win64.zip"
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip
Remove-Item $Stage -Recurse -Force
Write-Host "OK: $Zip"
