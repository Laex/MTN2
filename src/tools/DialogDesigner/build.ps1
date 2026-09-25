# Build MTN2 Dialog Designer (DIALOG_PLUGIN JSON editor + live preview).
# Compiles DialogDesigner.dpr and writes DialogDesigner.exe to the repo bin.
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug',
    [ValidateSet('Win32', 'Win64')]
    [string]$Platform = 'Win64'
)

$ErrorActionPreference = 'Stop'
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$RsVars = Join-Path $Studio 'bin\rsvars.bat'
$Dpr = Join-Path $PSScriptRoot 'DialogDesigner.dpr'
$Project = Join-Path $PSScriptRoot 'DialogDesigner.dproj'
$Bin = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\bin'))

if (-not (Test-Path $RsVars)) {
    throw "rsvars.bat not found: $RsVars"
}
if (-not (Test-Path $Dpr)) {
    throw "Project not found: $Dpr"
}
New-Item -ItemType Directory -Force -Path $Bin | Out-Null

# DCC_ExeOutput overrides the dproj folder so the exe lands in the repo bin.
# DCU stay next to the tool (dproj DCC_DcuOutput).
$Cmd = @"
call "$RsVars" && msbuild "$Project" /p:Config=$Config /p:Platform=$Platform /p:DCC_ExeOutput="$Bin" /t:Build /v:m
"@
cmd /c $Cmd
if ($LASTEXITCODE -ne 0) { throw "msbuild failed with $LASTEXITCODE" }

$Exe = Join-Path $Bin 'DialogDesigner.exe'
if (-not (Test-Path $Exe)) { throw "Output not found: $Exe" }
Write-Host "OK: $Exe"
