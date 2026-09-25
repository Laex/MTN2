# Build and run the Test*.dpr regression programs under src\tests\<group>\.
#
#   ./src/tests/run-tests.ps1                    # every group, manual.txt skipped
#   ./src/tests/run-tests.ps1 -Group vfs,panels  # some groups
#   ./src/tests/run-tests.ps1 -Test TestPty*     # by name (wildcards)
#   ./src/tests/run-tests.ps1 -All               # include manual.txt tests
#   ./src/tests/run-tests.ps1 -List              # show what would run
#
# Each test is compiled with dcc64 into src\tests\dcu and run with its group
# folder as the current directory. A test that outlives -TimeoutSec is killed
# and counted as failed, so CI never hangs on e.g. an unreachable network drive.
param(
    [string[]]$Group,
    [string[]]$Test,
    [switch]$All,
    [switch]$List,
    [int]$TimeoutSec = 300
)
$ErrorActionPreference = 'Stop'
# `pwsh -File run-tests.ps1 -Test A,B` passes "A,B" as one string.
$Group = @($Group | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Test = @($Test | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$RsVars = Join-Path $Studio 'bin\rsvars.bat'
$Tests = $PSScriptRoot
$Src = Split-Path $Tests -Parent
$Dcu = Join-Path $Tests 'dcu'

# Fixtures built into $Dcu before the test that loads them from its exe dir.
$Fixtures = @{
    TestPluginLoader   = @(Join-Path $Tests 'plugins\SamplePlugin.dpr')
    TestSevenZipPlugin = @(Join-Path $Src 'plugins\mtn.7z\SevenZipPlugin.dpr')
    TestTmpPanelPlugin = @(Join-Path $Src 'plugins\mtn.tmp\TmpPanelPlugin.dpr')
}

$Manual = @{}
Get-Content (Join-Path $Tests 'manual.txt') | ForEach-Object {
    $Line = ($_ -replace '#.*$', '').Trim()
    if ($Line) { $Manual[$Line] = $true }
}

$Selected = Get-ChildItem $Tests -Directory | Where-Object { $_.Name -ne 'dcu' } |
    Where-Object { -not $Group -or $Group -contains $_.Name } |
    ForEach-Object { Get-ChildItem $_.FullName -Filter 'Test*.dpr' -File } |
    Where-Object { $Name = $_.BaseName; -not $Test -or ($Test | Where-Object { $Name -like $_ }) } |
    Where-Object { $All -or $Test -or -not $Manual[$_.BaseName] } |
    Sort-Object { $_.Directory.Name }, Name

if ($List) {
    $Selected | ForEach-Object { '{0,-8} {1}' -f $_.Directory.Name, $_.BaseName }
    return
}
if (-not $Selected) { throw 'No tests selected' }

if (-not (Test-Path $RsVars)) { throw "rsvars.bat not found: $RsVars" }
foreach ($Line in (cmd /c "call `"$RsVars`" >nul && set")) {
    if ($Line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
New-Item -ItemType Directory -Force -Path $Dcu | Out-Null

# Runtime pieces some plugin tests need; they SKIP themselves when absent.
if ($Selected | Where-Object { $_.Directory.Name -eq 'plugins' }) {
    try { & (Join-Path $Src 'tools\fetch-wasmtime.ps1') | Out-Null }
    catch { Write-Host "WARN: wasmtime.dll fetch failed; TestWasmHost will SKIP" }
    # FindWasmtimeDll probes next to the exe's parent folder, which for
    # src\tests\dcu is src\tests -- point it at the fetched copy explicitly.
    $WasmtimeDll = Join-Path $Src 'tools\wasmtime\wasmtime.dll'
    if (Test-Path $WasmtimeDll) { $env:MTN2_WASMTIME_DLL = $WasmtimeDll }
    $WsSrc = Join-Path $Src 'plugins\mtn.ws'
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Push-Location $WsSrc
        try {
            $env:CARGO_TARGET_DIR = Join-Path $WsSrc 'target'
            rustup target add wasm32-unknown-unknown 2>&1 | Out-Null
            cargo build --target wasm32-unknown-unknown --release 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item (Join-Path $WsSrc 'target\wasm32-unknown-unknown\release\mtn_ws.wasm') `
                    (Join-Path $WsSrc 'plugin.wasm') -Force
            } else { Write-Host 'WARN: mtn.ws cargo build failed; TestWorkspacePlugin may SKIP' }
        } finally { Pop-Location }
    }
}

$UnitPath = @('Core', 'Themes', 'plugins\mtn.7z', 'plugins\mtn.tmp' |
    ForEach-Object { Join-Path $Src $_ }) -join ';'

function Invoke-Dcc([string]$Dpr) {
    $Out = & dcc64 -B -Q "-U$UnitPath" "-N$Dcu" "-E$Dcu" `
        '-NSSystem;System.Win;Winapi;System.IOUtils' $Dpr 2>&1
    if ($LASTEXITCODE -ne 0) {
        return ($Out | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 5) -join "`n"
    }
    return $null
}

$Results = foreach ($Dpr in $Selected) {
    $Name = $Dpr.BaseName
    $Sw = [Diagnostics.Stopwatch]::StartNew()
    $Status = 'PASS'
    $Detail = ''

    $Err = $null
    foreach ($Fix in @($Fixtures[$Name])) {
        if ($Fix -and -not $Err) { $Err = Invoke-Dcc $Fix }
    }
    if (-not $Err) { $Err = Invoke-Dcc $Dpr.FullName }

    if ($Err) {
        $Status = 'BUILD'
        $Detail = $Err
    } else {
        $Log = Join-Path $Dcu "$Name.log"
        $P = Start-Process (Join-Path $Dcu "$Name.exe") -WorkingDirectory $Dpr.DirectoryName `
            -NoNewWindow -PassThru -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
        if (-not $P.WaitForExit($TimeoutSec * 1000)) {
            $P.Kill($true)
            $Status = 'TIMEOUT'
        } elseif ($P.ExitCode -ne 0) {
            $Status = 'FAIL'
        }
        if ($Status -ne 'PASS') {
            $Detail = ((Get-Content $Log, "$Log.err" -ErrorAction SilentlyContinue) |
                Select-Object -Last 8) -join "`n"
            if ($Status -eq 'FAIL') { $Detail = "exit $($P.ExitCode)`n$Detail" }
        }
    }

    $Secs = [Math]::Round($Sw.Elapsed.TotalSeconds, 1)
    Write-Host ('{0,-7} {1,-8} {2} ({3}s)' -f $Status, $Dpr.Directory.Name, $Name, $Secs)
    if ($Detail) { $Detail -split "`n" | ForEach-Object { Write-Host "        $_" } }
    [pscustomobject]@{ Name = $Name; Status = $Status }
}

$Failed = @($Results | Where-Object Status -ne 'PASS')
Write-Host ''
Write-Host "$($Results.Count - $Failed.Count)/$($Results.Count) passed"
if ($Failed) {
    Write-Host "Failed: $(($Failed | ForEach-Object { "$($_.Name) [$($_.Status)]" }) -join ', ')"
    exit 1
}
