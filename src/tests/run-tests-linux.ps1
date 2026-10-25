# Builds the fixtures of each test group for Linux64 and runs them in WSL.
#
#   ./src/tests/run-tests-linux.ps1                  # every group
#   ./src/tests/run-tests-linux.ps1 -Group core,vfs  # some groups
#   ./src/tests/run-tests-linux.ps1 -Test TestVfs*   # fixture units by name (wildcards)
#
# The fixtures are the Test*.pas units of src\tests\<group>, except those listed
# in linux-excluded.txt (they test Windows-only code). For every group a runner
# program is generated into dcu\linux64-tests, compiled with dcclinux64 against
# the POSIX platform units and run with the group folder as its current
# directory.
param(
    [string[]]$Group,
    [string[]]$Test,
    [string]$Distro = 'Ubuntu-24.04',
    [string]$Sdk = '',
    [int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'
$Group = @($Group | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Test = @($Test | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$Tests = $PSScriptRoot
$Src = Split-Path $Tests -Parent
$Root = Split-Path $Src -Parent
if (-not $Sdk) { $Sdk = Join-Path $env:USERPROFILE 'Documents\Embarcadero\Studio\37.0\PlatformSDKs\Linux64.sdk' }
if (-not (Test-Path $Sdk)) { throw "Linux SDK not found: $Sdk" }
$Out = Join-Path $Root 'dcu\linux64-tests'
# The runners sit next to the Windows ones: fixtures find the repository from the exe folder.
$Exe = Join-Path $Tests 'dcu'
New-Item -ItemType Directory -Force $Out, $Exe | Out-Null

& (Join-Path $Src 'tools\make-linux-resources.ps1')

$Excluded = @{}
foreach ($Line in Get-Content (Join-Path $Tests 'linux-excluded.txt')) {
    $Text = ($Line -replace '#.*$', '').Trim()
    if ($Text) { $Excluded[$Text] = $true }
}

$Libs = "$(Join-Path $Studio 'lib\linux64\release');$Sdk\usr\lib\x86_64-linux-gnu;$Sdk\lib\x86_64-linux-gnu;$Sdk\usr\lib\gcc\x86_64-linux-gnu\13"
$Failed = @()

# Native plugin libraries the plugin tests load from the runner's folder.
function Build-PluginLibrary([string]$Dpr, [string]$Units) {
    $Dcu = Join-Path $Out 'obj\plugin-libs'
    New-Item -ItemType Directory -Force $Dcu | Out-Null
    $Result = & (Join-Path $Studio 'bin\dcclinux64.exe') "--syslibroot:$Sdk" "--libpath:$Libs" '--linker-option:-lstdc++' `
        "-U$Units" "-N0$Dcu" "-E$Exe" $Dpr 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Result | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 8 | ForEach-Object { Write-Host "        $_" }
        throw "cannot build $Dpr"
    }
}
if (-not $Group -or $Group -contains 'plugins') {
    Build-PluginLibrary (Join-Path $Tests 'plugins\SamplePlugin.dpr') "$Src\Core;$Src\Platform\Posix"
    Build-PluginLibrary (Join-Path $Src 'plugins\mtn.7z\SevenZipPlugin.dpr') "$Src\Core;$Src\Platform\Posix;$Src\plugins\mtn.7z;$Src\plugins\mtn.7z\Posix"
    Build-PluginLibrary (Join-Path $Src 'plugins\mtn.tmp\TmpPanelPlugin.dpr') "$Src\Core;$Src\Platform\Posix;$Src\plugins\mtn.tmp"
    & (Join-Path $Src 'tools\fetch-wasmtime.ps1') -Linux | Out-Null
}
$WasmtimeLib = Join-Path $Src 'tools\wasmtime\linux64\libwasmtime.so'

foreach ($Dir in Get-ChildItem $Tests -Directory) {
    if ($Dir.Name -in 'common', 'dcu') { continue }
    if ($Group -and $Group -notcontains $Dir.Name) { continue }
    $Fixtures = foreach ($F in Get-ChildItem $Dir.FullName -Filter 'Test*.pas' -File | Sort-Object Name) {
        if ($Excluded["$($Dir.Name)/$($F.BaseName)"]) { continue }
        if ($Test -and -not ($Test | Where-Object { $F.BaseName -like $_ })) { continue }
        $F.BaseName
    }
    # The fixtures of the screensaver subsystem live with its code.
    $SubsystemTests = Join-Path $Src 'ascii-sharks\tests'
    $ExtraUnits = ''
    if ($Dir.Name -eq 'core' -and (Test-Path $SubsystemTests)) {
        $Fixtures = @($Fixtures) + @(Get-ChildItem $SubsystemTests -Filter 'Test*.pas' -File | Sort-Object Name | ForEach-Object { $_.BaseName })
        $ExtraUnits = ";$SubsystemTests"
    }
    if (-not $Fixtures) { continue }
    $Name = (Get-Culture).TextInfo.ToTitleCase($Dir.Name) + 'TestsLinux'
    $Dpr = Join-Path $Out "$Name.dpr"
    @("program $Name;", '', '{$APPTYPE CONSOLE}', '{$STRONGLINKTYPES ON}',
        "{`$R '$Src\MTN2Tui.dres'}", '', 'uses', '  uTestRunner,',
        (($Fixtures | ForEach-Object { "  $_" }) -join ",`n") + ';', '', 'begin', '  RunRegisteredTests;', 'end.') |
        Set-Content $Dpr -Encoding UTF8
    $Units = "$Src\Core;$Src\ascii-sharks;$Src\Platform\Posix;$Src\Hosts\Ansi;$Src\Hosts\Common;$Src\Hosts\Sdl;$Src\plugins\mtn.7z;$Src\plugins\mtn.7z\Posix;$Src\plugins\mtn.tmp;$Src\plugins\mtn.net;$Src\tests\common;$($Dir.FullName)$ExtraUnits;$Studio\source\DunitX"
    $Dcu = Join-Path $Out "obj\$($Dir.Name)"
    New-Item -ItemType Directory -Force $Dcu | Out-Null
    $Result = & (Join-Path $Studio 'bin\dcclinux64.exe') "--syslibroot:$Sdk" "--libpath:$Libs" '--linker-option:-lstdc++' `
        "-U$Units" "-N0$Dcu" "-E$Exe" $Dpr 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("BUILD   {0}" -f $Dir.Name)
        $Result | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 8 | ForEach-Object { Write-Host "        $_" }
        $Failed += $Dir.Name
        continue
    }
    $WslOut = '/mnt/' + $Exe.Substring(0, 1).ToLower() + $Exe.Substring(2).Replace('\', '/')
    $WslDir = '/mnt/' + $Dir.FullName.Substring(0, 1).ToLower() + $Dir.FullName.Substring(2).Replace('\', '/')
    $Xml = "$Exe\$Name.xml"
    Remove-Item $Xml -ErrorAction SilentlyContinue
    $WslWasmtime = if (Test-Path $WasmtimeLib) { '/mnt/' + $WasmtimeLib.Substring(0, 1).ToLower() + $WasmtimeLib.Substring(2).Replace('\', '/') } else { '' }
    $Log = & wsl -d $Distro -- bash -c "cd '$WslDir' && MTN2_WASMTIME_DLL='$WslWasmtime' timeout $TimeoutSec '$WslOut/$Name' --hidebanner --consolemode:Quiet --exitbehavior:Continue --exclude:Manual,WindowsOnly --xmlfile:'$WslOut/$Name.xml' 2>&1"
    $Code = $LASTEXITCODE
    $Counts = ''
    if (Test-Path $Xml) {
        $R = ([xml](Get-Content $Xml -Raw)).'test-results'
        $Counts = "$($R.total) tests, $([int]$R.failures + [int]$R.errors) failed, $($R.'not-run') not run"
    }
    if ($Code -eq 0) {
        Write-Host ("PASS    {0,-8} {1}" -f $Dir.Name, $Counts)
    } else {
        Write-Host ("FAIL    {0,-8} {1} (exit {2})" -f $Dir.Name, $Counts, $Code)
        $At = [Array]::FindIndex([string[]]$Log, [Predicate[string]] { param($l) $l -match '^Failing Tests' })
        $Shown = if ($At -ge 0) { $Log[$At..([Math]::Min($Log.Count - 1, $At + 40))] } else { $Log | Select-Object -Last 15 }
        $Shown | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "        $_" }
        $Failed += $Dir.Name
    }
}
if ($Failed) { Write-Host "Failed: $($Failed -join ', ')"; exit 1 }
