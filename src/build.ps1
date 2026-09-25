# Build MTN2 (Stage 0+) via RAD Studio MSBuild
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug',
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform = 'Win64'
)

$ErrorActionPreference = 'Stop'
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$RsVars = Join-Path $Studio 'bin\rsvars.bat'
$Project = Join-Path $PSScriptRoot 'MTN2.dproj'
$Rc = Join-Path $PSScriptRoot 'MTN2.rc'

if (-not (Test-Path $RsVars)) {
    throw "rsvars.bat not found: $RsVars"
}

$Brcc = Join-Path $Studio 'bin\brcc32.exe'
if (Test-Path $Brcc) {
    & $Brcc -fo(Join-Path $PSScriptRoot 'MTN2.res') $Rc
    & $Brcc -fo(Join-Path $PSScriptRoot 'MTN2.dres') (Join-Path $PSScriptRoot 'MTN2Resource.rc')
    if ($LASTEXITCODE -ne 0) { throw "brcc32 failed with $LASTEXITCODE" }
}

$Cmd = @"
call "$RsVars" && msbuild "$Project" /p:Config=$Config /p:Platform=$Platform /t:Build /v:m
"@
cmd /c $Cmd
if ($LASTEXITCODE -ne 0) { throw "msbuild failed with $LASTEXITCODE" }

$ExeCandidates = @(
    (Join-Path $PSScriptRoot "..\bin\MTN2.exe"),
    (Join-Path $PSScriptRoot "$Platform\$Config\MTN2.exe")
)
$Exe = $ExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Exe) {
    throw "Output not found. Tried: $($ExeCandidates -join ', ')"
}

# TPluginLoader scans <ExeDir>\plugins\<id>\ on startup.
$PluginsOut = Join-Path (Split-Path $Exe -Parent) 'plugins'
$PluginsSrc = Join-Path $PSScriptRoot 'plugins'
$PluginDcu = Join-Path $PSScriptRoot 'dcu'
$CoreDir = Join-Path $PSScriptRoot 'Core'
New-Item -ItemType Directory -Force -Path $PluginsOut | Out-Null
New-Item -ItemType Directory -Force -Path $PluginDcu | Out-Null

Get-ChildItem -Path $PluginsSrc -Directory | ForEach-Object {
    $Name = $_.Name
    $Src = $_.FullName
    $Dest = Join-Path $PluginsOut $Name
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    Get-ChildItem -Path $Src -Filter '*.dpr' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $PluginCmd = @"
call "$RsVars" && dcc64 -B -U"$CoreDir;$Src" -N"$PluginDcu" -E"$Dest" -NSSystem;System.Win;Winapi;System.IOUtils "$($_.FullName)"
"@
        cmd /c $PluginCmd
        if ($LASTEXITCODE -ne 0) { throw "$Name compile failed: $LASTEXITCODE ($($_.Name))" }
        Write-Host "OK: compiled $($_.Name) -> $Dest"
    }

    if (Test-Path (Join-Path $Src 'Cargo.toml')) {
        $Cargo = Get-Command cargo -ErrorAction SilentlyContinue
        if ($Cargo) {
            Push-Location $Src
            try {
                $env:CARGO_TARGET_DIR = Join-Path $Src 'target'
                rustup target add wasm32-unknown-unknown | Out-Null
                cargo build --target wasm32-unknown-unknown --release
                if ($LASTEXITCODE -ne 0) { throw "$Name cargo build failed: $LASTEXITCODE" }
                $RelWasm = Join-Path $Src 'target\wasm32-unknown-unknown\release'
                $Built = Get-ChildItem $RelWasm -Filter '*.wasm' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '*.d.wasm' } |
                    Select-Object -First 1
                if ($Built) {
                    Copy-Item $Built.FullName (Join-Path $Src 'plugin.wasm') -Force
                }
                Write-Host "OK: built $Name plugin.wasm"
            } finally {
                Pop-Location
            }
        } elseif (-not (Test-Path (Join-Path $Src 'plugin.wasm'))) {
            Write-Host "WARN: cargo not found and $Name\plugin.wasm missing"
        }
    }

    Get-ChildItem -Path $Src -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.json', '.wat', '.wasm' } |
        ForEach-Object {
            Copy-Item $_.FullName (Join-Path $Dest $_.Name) -Force
        }
    Write-Host "OK: staged $Name -> $Dest"
}

# Native 7z:// needs a replaceable x64 7z.dll (LGPL, gitignored).
$Dest7z = Join-Path $PluginsOut 'mtn.7z\7z.dll'
$7zCandidates = @($env:MTN2_7Z_DLL,
    'C:\Program Files\7-Zip\7z.dll',
    'C:\Program Files\Far Manager\Plugins\ArcLite\7z.dll')
$7zSrc = $7zCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($7zSrc) {
    Copy-Item $7zSrc $Dest7z -Force
    Write-Host "OK: staged 7z.dll from $7zSrc"
} elseif (-not (Test-Path $Dest7z)) {
    Write-Host "WARN: 7z.dll not found; drop an x64 copy into $(Split-Path $Dest7z) for 7z:// to work"
}

# MTN2 renders through Skia (FMX.Skia, GlobalUseSkia): the exe does not start
# without sk4d.dll next to it. The IDE deploys it; a command-line build must.
$SkiaArch = if ($Platform -eq 'Win64') { 'win64' } else { 'win32' }
$SkiaBin = if ($Platform -eq 'Win64') { 'bin64' } else { 'bin' }
$SkiaDll = @((Join-Path $Studio "Redist\$SkiaArch\sk4d.dll"), (Join-Path $Studio "$SkiaBin\sk4d.dll")) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $SkiaDll) { throw "sk4d.dll not found under $Studio (Redist\$SkiaArch or $SkiaBin)" }
Copy-Item $SkiaDll (Join-Path (Split-Path $Exe -Parent) 'sk4d.dll') -Force
Write-Host "OK: staged sk4d.dll from $SkiaDll"

$WasmtimeDll = $env:MTN2_WASMTIME_DLL
if (-not $WasmtimeDll) {
    $WasmtimeDll = Join-Path $PSScriptRoot 'tools\wasmtime\wasmtime.dll'
    if (-not (Test-Path $WasmtimeDll)) {
        try { & (Join-Path $PSScriptRoot 'tools\fetch-wasmtime.ps1') | Out-Null }
        catch { Write-Host "WARN: wasmtime.dll download failed: $_" }
    }
}
if ($WasmtimeDll -and (Test-Path $WasmtimeDll)) {
    Copy-Item $WasmtimeDll (Join-Path (Split-Path $Exe -Parent) 'wasmtime.dll') -Force
    Write-Host "OK: staged wasmtime.dll"
} else {
    Write-Host "WARN: wasmtime.dll not found; WASM plugins skipped (run src/tools/fetch-wasmtime.ps1)"
}

Write-Host "OK: $Exe"
