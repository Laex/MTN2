# Build and run the DUnitX test runners, one per src\tests\<group>\ folder.
#
#   ./src/tests/run-tests.ps1                    # every group, Manual fixtures skipped
#   ./src/tests/run-tests.ps1 -Group vfs,panels  # some groups
#   ./src/tests/run-tests.ps1 -Test TestPty*     # fixture units by name (wildcards)
#   ./src/tests/run-tests.ps1 -All               # include [Category('Manual')] fixtures
#   ./src/tests/run-tests.ps1 -List              # show what would run
#   ./src/tests/run-tests.ps1 -Jobs 1            # one group at a time (default: all at once)
#
# Each group folder holds Test*.pas fixture units and a <Group>Tests.dpr that
# lists them. The runner is compiled with dcc64 into src\tests\dcu and run with
# its group folder as the current directory; its NUnit XML report lands next to
# it as <Group>Tests.xml. A runner that outlives -TimeoutSec is killed and
# counted as failed, so CI never hangs on e.g. an unreachable network drive.
# The groups are independent (each has its own .dcu folder, settings folder and
# exe), so they are built and run at the same time; the results are listed in
# group order when they are all in.
# -Test names a fixture explicitly, so it runs even when tagged Manual.
param(
    [string[]]$Group,
    [string[]]$Test,
    [switch]$All,
    [switch]$List,
    [int]$TimeoutSec = 900,
    # Groups built and run at the same time; 0 = all of them.
    [int]$Jobs = 0
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

# Fixtures built into $Dcu before the group whose tests load them from the exe dir.
$Fixtures = @{
    plugins = @(
        (Join-Path $Tests 'plugins\SamplePlugin.dpr'),
        (Join-Path $Src 'plugins\mtn.7z\SevenZipPlugin.dpr'),
        (Join-Path $Src 'plugins\mtn.tmp\TmpPanelPlugin.dpr'))
}

function Get-RunnerName([string]$GroupName) {
    (Get-Culture).TextInfo.ToTitleCase($GroupName) + 'Tests'
}

$Groups = foreach ($Dir in Get-ChildItem $Tests -Directory) {
    $Dpr = Join-Path $Dir.FullName "$(Get-RunnerName $Dir.Name).dpr"
    if (-not (Test-Path $Dpr)) { continue }
    if ($Group -and $Group -notcontains $Dir.Name) { continue }
    $Units = Get-ChildItem $Dir.FullName -Filter 'Test*.pas' -File | Sort-Object Name
    # A fixture unit missing from the runner's uses clause would silently never run.
    $DprText = Get-Content $Dpr -Raw
    $Missing = @($Units | Where-Object { $DprText -notmatch "\b$([regex]::Escape($_.BaseName))\s+in\s+'" })
    if ($Missing) {
        throw "$(Split-Path $Dpr -Leaf) does not list: $(($Missing | ForEach-Object BaseName) -join ', ')"
    }
    $Fx = foreach ($U in $Units) {
        $Name = $U.BaseName
        if ($Test -and -not ($Test | Where-Object { $Name -like $_ })) { continue }
        [pscustomobject]@{
            Name   = $Name
            Manual = [bool](Select-String -Path $U.FullName -Pattern "Category\('Manual'\)" -Quiet)
        }
    }
    if (-not $Fx) { continue }
    [pscustomobject]@{ Name = $Dir.Name; Runner = (Get-RunnerName $Dir.Name); Dir = $Dir.FullName; Dpr = $Dpr; Fixtures = @($Fx) }
}

if ($List) {
    foreach ($G in $Groups) {
        foreach ($F in $G.Fixtures) {
            $Mark = if ($F.Manual -and -not ($All -or $Test)) { ' (manual, skipped)' } elseif ($F.Manual) { ' (manual)' } else { '' }
            '{0,-8} {1}{2}' -f $G.Name, $F.Name, $Mark
        }
    }
    return
}
if (-not $Groups) { throw 'No tests selected' }

if (-not (Test-Path $RsVars)) { throw "rsvars.bat not found: $RsVars" }
foreach ($Line in (cmd /c "call `"$RsVars`" >nul && set")) {
    if ($Line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
New-Item -ItemType Directory -Force -Path $Dcu | Out-Null

# MTN2.dres (dialogs, strings, keymap, menu as RCDATA) is a build product, not
# in git; the runners link it with {$R '..\..\MTN2.dres'}. Rebuild it here so a
# fresh clone runs without build.ps1 and a test never sees stale resources.
& (Join-Path $Studio 'bin\brcc32.exe') "-fo$(Join-Path $Src 'MTN2.dres')" (Join-Path $Src 'MTN2Resource.rc') | Out-Null
if ($LASTEXITCODE -ne 0) { throw "brcc32 failed with $LASTEXITCODE (MTN2Resource.rc)" }

# Runtime pieces some plugin tests need; they SKIP themselves when absent.
if ($Groups | Where-Object Name -eq 'plugins') {
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
            $BuildCache = & (Join-Path $Src 'tools\cache-dir.ps1')
            $CargoTarget = if ($BuildCache) { Join-Path $BuildCache 'cargo-target\mtn.ws' } else { Join-Path $WsSrc 'target' }
            $env:CARGO_TARGET_DIR = $CargoTarget
            rustup target add wasm32-unknown-unknown 2>&1 | Out-Null
            cargo build --target wasm32-unknown-unknown --release 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item (Join-Path $CargoTarget 'wasm32-unknown-unknown\release\mtn_ws.wasm') `
                    (Join-Path $WsSrc 'plugin.wasm') -Force
            } else { Write-Host 'WARN: mtn.ws cargo build failed; TestWorkspacePlugin may SKIP' }
        } finally { Pop-Location }
    }
}

$UnitPath = @('Core', 'Themes', 'plugins\mtn.7z', 'plugins\mtn.tmp', 'tests\common' |
    ForEach-Object { Join-Path $Src $_ }) -join ';'

$Throttle = if ($Jobs -gt 0) { $Jobs } else { $Groups.Count }
$Indexed = for ($I = 0; $I -lt $Groups.Count; $I++) {
    [pscustomobject]@{ Order = $I; Group = $Groups[$I] }
}

$Results = $Indexed | ForEach-Object -ThrottleLimit $Throttle -Parallel {
    $G = $_.Group
    $Dcu = $using:Dcu
    $UnitPath = $using:UnitPath
    $Fixtures = $using:Fixtures
    $All = $using:All
    $Test = $using:Test
    $TimeoutSec = $using:TimeoutSec
    $Runner = $G.Runner
    # Compiled units stay per group: runners compiling into one folder at the
    # same time would overwrite each other's .dcu files.
    $Obj = Join-Path $Dcu "obj\$($G.Name)"
    New-Item -ItemType Directory -Force -Path $Obj | Out-Null

    function Invoke-Dcc([string]$Dpr) {
        $Out = & dcc64 -B -Q "-U$UnitPath" "-N$Obj" "-E$Dcu" `
            '-NSSystem;System.Win;Winapi;System.IOUtils' $Dpr 2>&1
        if ($LASTEXITCODE -ne 0) {
            return ($Out | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 10) -join "`n"
        }
        return $null
    }

    $Sw = [Diagnostics.Stopwatch]::StartNew()
    $Status = 'PASS'
    $Detail = ''
    $Counts = ''

    $Err = $null
    foreach ($Fix in @($Fixtures[$G.Name])) {
        if ($Fix -and -not $Err) { $Err = Invoke-Dcc $Fix }
    }
    if (-not $Err) { $Err = Invoke-Dcc $G.Dpr }

    if ($Err) {
        $Status = 'BUILD'
        $Detail = $Err
    } else {
        $Log = Join-Path $Dcu "$Runner.log"
        $Xml = Join-Path $Dcu "$Runner.xml"
        Remove-Item $Xml -ErrorAction SilentlyContinue
        $RunArgs = @('--hidebanner', '--consolemode:Quiet', '--exitbehavior:Continue', "--xmlfile:$Xml")
        if (-not ($All -or $Test)) { $RunArgs += '--exclude:Manual' }
        if ($Test) { $RunArgs += '--run:' + (($G.Fixtures | ForEach-Object { "$($_.Name).T$($_.Name)" }) -join ',') }
        $P = Start-Process (Join-Path $Dcu "$Runner.exe") -ArgumentList $RunArgs -WorkingDirectory $G.Dir `
            -NoNewWindow -PassThru -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
        if (-not $P.WaitForExit($TimeoutSec * 1000)) {
            $P.Kill($true)
            $Status = 'TIMEOUT'
        } elseif ($P.ExitCode -ne 0) {
            $Status = 'FAIL'
        }
        if (Test-Path $Xml) {
            $R = ([xml](Get-Content $Xml -Raw)).'test-results'
            $Counts = "$($R.total) tests, $([int]$R.failures + [int]$R.errors) failed, $($R.'not-run') not run"
        }
        if ($Status -ne 'PASS') {
            $Text = @(Get-Content $Log, "$Log.err" -ErrorAction SilentlyContinue)
            $At = [Array]::FindIndex([string[]]$Text, [Predicate[string]] { param($l) $l -match '^Failing Tests' })
            $Detail = if ($At -ge 0) { ($Text[$At..($Text.Count - 1)] | Where-Object { $_.Trim() }) -join "`n" }
                      else { ($Text | Select-Object -Last 12) -join "`n" }
            if ($Status -eq 'FAIL') { $Detail = "exit $($P.ExitCode)`n$Detail" }
        }
    }

    $Secs = [Math]::Round($Sw.Elapsed.TotalSeconds, 1)
    [pscustomobject]@{
        Order  = $_.Order
        Name   = $G.Name
        Status = $Status
        Line   = ('{0,-7} {1,-8} {2} ({3}s)' -f $Status, $G.Name, $Counts, $Secs)
        Detail = $Detail
    }
}

$Results = @($Results | Sort-Object Order)
foreach ($R in $Results) {
    Write-Host $R.Line
    if ($R.Detail) { $R.Detail -split "`n" | ForEach-Object { Write-Host "        $_" } }
}

$Failed = @($Results | Where-Object Status -ne 'PASS')
Write-Host ''
Write-Host "$($Results.Count - $Failed.Count)/$($Results.Count) groups passed (reports: $Dcu\*Tests.xml)"
if ($Failed) {
    Write-Host "Failed: $(($Failed | ForEach-Object { "$($_.Name) [$($_.Status)]" }) -join ', ')"
    exit 1
}
