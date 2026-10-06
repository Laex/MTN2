# Builds the demo plugins in samples\plugins and, with -Install, copies them to
# bin\plugins (next to MTN2.exe), where the host loads them at startup.
#
#   ./samples/build-samples.ps1                 # build every sample whose toolchain is found
#   ./samples/build-samples.ps1 -Install        # ... and install the results
#   ./samples/build-samples.ps1 -Only mtn.demo.go,mtn.demo.rs
#
# Each sample is built into samples\.build\<id>\ (ignored by git). A sample
# whose toolchain is missing is skipped with a note, not a failure.
#
#   mtn.demo.cpp     C++     MSVC (cl) from a Visual Studio installation
#   mtn.demo.video   C++     MSVC (cl), Media Foundation (source reader, waveOut)
#   mtn.demo.texttools C++   MSVC (cl)
#   mtn.demo.panelkit Rust   cargo (serde_json)
#   mtn.demo.highlight Rust  cargo
#   mtn.demo.wc      Go      go (GOOS=wasip1, needs "wasi": true in plugin.json)
#   mtn.demo.img     Rust    cargo (image crate + GDI window)
#   mtn.demo.rs      Rust    cargo, x86_64-pc-windows-msvc
#   mtn.demo.go      Go      go + a 64-bit gcc (cgo, -buildmode=c-shared)
#   mtn.demo.go.wasm Go      go (GOOS=wasip1, needs "wasi": true in plugin.json)
#   mtn.demo.pas     Delphi  dcc64 from RAD Studio
#   mtn.demo.wat     WAT     nothing: the host assembles the text at load time
param(
    [string[]]$Only,
    [switch]$Install
)
$ErrorActionPreference = 'Stop'
$Samples = Join-Path $PSScriptRoot 'plugins'
$Include = Join-Path $PSScriptRoot 'include'
$BuildRoot = Join-Path $PSScriptRoot '.build'
$Repo = Split-Path $PSScriptRoot -Parent
$PluginsOut = Join-Path $Repo 'bin\plugins'
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

function Find-Tool([string]$Name, [string[]]$Candidates) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($pattern in $Candidates) {
        $hit = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$Go = Find-Tool 'go' @('C:\Program Files\Go\bin\go.exe')
# A 64-bit gcc for cgo: not the 32-bit one that ships with Free Pascal.
$Gcc = $null
foreach ($candidate in @(
        (Get-Command gcc -ErrorAction SilentlyContinue).Source,
        (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*WinLibs*\mingw64\bin\gcc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName,
        'C:\msys64\ucrt64\bin\gcc.exe', 'C:\msys64\mingw64\bin\gcc.exe')) {
    if ($candidate -and (Test-Path $candidate) -and ((& $candidate -dumpmachine) -match '^x86_64')) {
        $Gcc = $candidate
        break
    }
}
$VcVars = Find-Tool 'vcvars64.bat' @('C:\Program Files\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat',
    'C:\Program Files (x86)\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat')
$Cargo = Find-Tool 'cargo' @("$env:USERPROFILE\.cargo\bin\cargo.exe")
$RsVars = Find-Tool 'rsvars.bat' @('C:\Program Files (x86)\Embarcadero\Studio\*\bin\rsvars.bat')

function Want([string]$Id) { return (-not $Only) -or ($Only -contains $Id) }

function Stage-Common([string]$Id, [string]$Out) {
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    Copy-Item (Join-Path $Samples "$Id\plugin.json") $Out -Force
    # The help pages named by "help" in plugin.json (help.md, help.ru.md).
    Get-ChildItem (Join-Path $Samples $Id) -Filter 'help*.md' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $Out -Force
}

function Build-Cpp {
    $id = 'mtn.demo.cpp'
    if (-not $VcVars) { Write-Host "skip $id : Visual Studio (vcvars64.bat) not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $src = Join-Path $Samples "$id\plugin.cpp"
    $cmd = "call `"$VcVars`" >nul && cl /nologo /LD /EHsc /O2 /std:c++17 /I`"$Include`" `"$src`" /Fo`"$out\\`" /Fe`"$out\mtn_demo_cpp.dll`""
    cmd /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    Get-ChildItem $out -Include *.exp, *.lib, *.obj -Recurse | Remove-Item -Force
    return $true
}

function Build-Video {
    $id = 'mtn.demo.video'
    if (-not $VcVars) { Write-Host "skip $id : Visual Studio (vcvars64.bat) not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $src = Join-Path $Samples "$id\plugin.cpp"
    $cmd = "call `"$VcVars`" >nul && cl /nologo /LD /EHsc /O2 /std:c++17 /I`"$Include`" `"$src`" /Fo`"$out\\`" /Fe`"$out\mtn_demo_video.dll`""
    cmd /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    Get-ChildItem $out -Include *.exp, *.lib, *.obj -Recurse | Remove-Item -Force
    return $true
}

function Build-TextTools {
    $id = 'mtn.demo.texttools'
    if (-not $VcVars) { Write-Host "skip $id : Visual Studio (vcvars64.bat) not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $src = Join-Path $Samples "$id\plugin.cpp"
    $cmd = "call `"$VcVars`" >nul && cl /nologo /LD /EHsc /O2 /std:c++17 /I`"$Include`" `"$src`" /Fo`"$out\\`" /Fe`"$out\mtn_demo_texttools.dll`""
    cmd /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    Get-ChildItem $out -Include *.exp, *.lib, *.obj -Recurse | Remove-Item -Force
    return $true
}

function Build-NativeView {
    $id = 'mtn.demo.nativeview'
    if (-not $VcVars) { Write-Host "skip $id : Visual Studio (vcvars64.bat) not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $src = Join-Path $Samples "$id\plugin.cpp"
    $cmd = "call `"$VcVars`" >nul && cl /nologo /LD /EHsc /O2 /std:c++17 /I`"$Include`" `"$src`" /Fo`"$out\\`" /Fe`"$out\mtn_demo_nativeview.dll`""
    cmd /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    Get-ChildItem $out -Include *.exp, *.lib, *.obj -Recurse | Remove-Item -Force
    return $true
}

function Build-PanelKit {
    $id = 'mtn.demo.panelkit'
    if (-not $Cargo) { Write-Host "skip $id : cargo not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:CARGO_TARGET_DIR = Join-Path $BuildRoot "cargo\$id"
    Push-Location (Join-Path $Samples $id)
    try {
        & $Cargo build --release
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally { Pop-Location }
    Copy-Item (Join-Path $env:CARGO_TARGET_DIR 'release\mtn_demo_panelkit.dll') $out -Force
    return $true
}

function Build-WordCount {
    $id = 'mtn.demo.wc'
    if (-not $Go) { Write-Host "skip $id : go not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:GOOS = 'wasip1'
    $env:GOARCH = 'wasm'
    Push-Location (Join-Path $Samples $id)
    try {
        & $Go build -buildmode=c-shared -o (Join-Path $out 'plugin.wasm') .
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally {
        Pop-Location
        $env:GOOS = $null
        $env:GOARCH = $null
    }
    return $true
}

function Build-Highlight {
    $id = 'mtn.demo.highlight'
    if (-not $Cargo) { Write-Host "skip $id : cargo not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:CARGO_TARGET_DIR = Join-Path $BuildRoot "cargo\$id"
    Push-Location (Join-Path $Samples $id)
    try {
        & $Cargo build --release
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally { Pop-Location }
    Copy-Item (Join-Path $env:CARGO_TARGET_DIR 'release\mtn_demo_highlight.dll') $out -Force
    return $true
}

function Build-Rust {
    $id = 'mtn.demo.rs'
    if (-not $Cargo) { Write-Host "skip $id : cargo not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:CARGO_TARGET_DIR = Join-Path $BuildRoot "cargo\$id"
    Push-Location (Join-Path $Samples $id)
    try {
        & $Cargo build --release
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally { Pop-Location }
    Copy-Item (Join-Path $env:CARGO_TARGET_DIR 'release\mtn_demo_rs.dll') $out -Force
    return $true
}

function Build-Image {
    $id = 'mtn.demo.img'
    if (-not $Cargo) { Write-Host "skip $id : cargo not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:CARGO_TARGET_DIR = Join-Path $BuildRoot "cargo\$id"
    Push-Location (Join-Path $Samples $id)
    try {
        & $Cargo build --release
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally { Pop-Location }
    Copy-Item (Join-Path $env:CARGO_TARGET_DIR 'release\mtn_demo_img.dll') $out -Force
    return $true
}

function Build-Go {
    $id = 'mtn.demo.go'
    if (-not $Go) { Write-Host "skip $id : go not found"; return $false }
    if (-not $Gcc) { Write-Host "skip $id : a 64-bit gcc is needed for cgo (install WinLibs or MSYS2)"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:CGO_ENABLED = '1'
    $env:CC = $Gcc
    Push-Location (Join-Path $Samples $id)
    try {
        & $Go build -buildmode=c-shared -o (Join-Path $out 'mtn_demo_go.dll') .
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally { Pop-Location }
    Remove-Item (Join-Path $out 'mtn_demo_go.h') -ErrorAction SilentlyContinue
    return $true
}

function Build-GoWasm {
    $id = 'mtn.demo.go.wasm'
    if (-not $Go) { Write-Host "skip $id : go not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $env:GOOS = 'wasip1'
    $env:GOARCH = 'wasm'
    Push-Location (Join-Path $Samples $id)
    try {
        & $Go build -buildmode=c-shared -o (Join-Path $out 'plugin.wasm') .
        if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    } finally {
        Pop-Location
        $env:GOOS = $null
        $env:GOARCH = $null
    }
    return $true
}

function Build-Delphi {
    $id = 'mtn.demo.pas'
    if (-not $RsVars) { Write-Host "skip $id : RAD Studio (rsvars.bat) not found"; return $false }
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    $dcu = Join-Path $BuildRoot 'dcu'
    New-Item -ItemType Directory -Force -Path $dcu | Out-Null
    $core = Join-Path $Repo 'src\Core'
    $src = Join-Path $Samples "$id\NotesPlugin.dpr"
    $cmd = "call `"$RsVars`" && dcc64 -B -`$O+ -`$D- -U`"$core`" -N`"$dcu`" -E`"$out`" -NSSystem;System.Win;Winapi;System.IOUtils `"$src`""
    cmd /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$id build failed" }
    return $true
}

function Build-Wat {
    $id = 'mtn.demo.wat'
    $out = Join-Path $BuildRoot $id
    Stage-Common $id $out
    Copy-Item (Join-Path $Samples "$id\plugin.wat") $out -Force
    return $true
}

$built = @()
foreach ($step in @(
        @{ Id = 'mtn.demo.cpp'; Run = { Build-Cpp } },
        @{ Id = 'mtn.demo.video'; Run = { Build-Video } },
        @{ Id = 'mtn.demo.img'; Run = { Build-Image } },
        @{ Id = 'mtn.demo.texttools'; Run = { Build-TextTools } },
        @{ Id = 'mtn.demo.nativeview'; Run = { Build-NativeView } },
        @{ Id = 'mtn.demo.panelkit'; Run = { Build-PanelKit } },
        @{ Id = 'mtn.demo.wc'; Run = { Build-WordCount } },
        @{ Id = 'mtn.demo.highlight'; Run = { Build-Highlight } },
        @{ Id = 'mtn.demo.rs'; Run = { Build-Rust } },
        @{ Id = 'mtn.demo.go'; Run = { Build-Go } },
        @{ Id = 'mtn.demo.go.wasm'; Run = { Build-GoWasm } },
        @{ Id = 'mtn.demo.pas'; Run = { Build-Delphi } },
        @{ Id = 'mtn.demo.wat'; Run = { Build-Wat } })) {
    if (-not (Want $step.Id)) { continue }
    if (& $step.Run) {
        Write-Host "OK: built $($step.Id)"
        $built += $step.Id
    }
}

if ($Install) {
    foreach ($id in $built) {
        $dest = Join-Path $PluginsOut $id
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $BuildRoot "$id\*") $dest -Force
        Write-Host "OK: installed $id -> $dest"
    }
}
