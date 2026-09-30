# Pack the runtime part of bin\ (after src\build.ps1) into
#   dist\MTN2-<Version>-win64.zip           -- settings in %APPDATA%\MTN2
#   dist\MTN2-<Version>-win64-portable.zip  -- the same files + portable.dat,
#                                              settings next to MTN2.exe
# The updater downloads only the first one (exact name, uUpdater.pas); unpacked
# over a portable copy it leaves portable.dat and the user's files alone, so
# both kinds of install update from the same package. Keep the portable name
# ending in anything but "-win64.zip".
param(
    [Parameter(Mandatory)]
    [string]$Version,
    # Published packages (release, dev build) must carry wasmtime.dll; a
    # missing one stops the packaging instead of shipping without WASM plugins.
    [switch]$RequireWasmtime
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
    if ($RequireWasmtime) { throw 'bin\wasmtime.dll not found; run src\tools\fetch-wasmtime.ps1 and build again' }
    Write-Host 'WARN: bin\wasmtime.dll missing -- WASM plugins will not load from this package'
}
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

# Only what MTN2.exe reads at run time and does not carry itself: menu,
# keymap, theme, dialogs, strings and icons are embedded resources
# (MTN2Resource.rc). Debug/IDE by-products (*.map, *.rsm, *.drc) and dev
# tools stay out.
# 7z.dll is not ours to ship (LGPL + unRAR terms): users drop their own x64
# copy into plugins\mtn.7z\, as build.ps1 does from a local 7-Zip install.
# No keymap.json or other settings: they are the user's overrides (and in
# portable mode live in this very folder), so a package -- and the updater,
# which replaces whatever the package contains -- must never carry one.
foreach ($Name in 'MTN2.exe', 'sk4d.dll', 'wasmtime.dll') {
    $Src = Join-Path $Bin $Name
    if (Test-Path $Src) { Copy-Item $Src $Stage }
}
foreach ($Dir in 'help', 'plugins') {
    $Src = Join-Path $Bin $Dir
    if (Test-Path $Src) { Copy-Item $Src (Join-Path $Stage $Dir) -Recurse }
}
Get-ChildItem $Stage -Recurse -File -Filter '7z.dll' | Remove-Item -Force
Copy-Item (Join-Path $Root 'LICENSE') $Stage
# What's new for the user, version by version (also linked from the release page).
Copy-Item (Join-Path $Root 'CHANGELOG.md') $Stage

$Safe = $Version -replace '[^\w.\-]', '_'
$Zip = Join-Path $Dist "MTN2-$Safe-win64.zip"
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip
Write-Host "OK: $Zip"

# Portable: the presence of portable.dat is the whole switch (uConfigLocation).
Set-Content -Path (Join-Path $Stage 'portable.dat') -Encoding ascii -Value @(
    'MTN2 portable mode: settings, history and the keymap are kept in this folder.'
    'Delete this file to keep them in %APPDATA%\MTN2 instead.'
)
$PortableZip = Join-Path $Dist "MTN2-$Safe-win64-portable.zip"
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $PortableZip
Write-Host "OK: $PortableZip"

Remove-Item $Stage -Recurse -Force
