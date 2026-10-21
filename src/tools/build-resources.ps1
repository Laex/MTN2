# Compiles a resource script (.rc) into a .res / .dres with brcc32.
#
#   ./src/tools/build-resources.ps1 -Rc src\MTN2Resource.rc -Out src\MTN2.dres
#
# The one place that runs brcc32, shared by build.ps1, tests\run-tests.ps1 and
# tools\make-linux-resources.ps1, so every build embeds the same way and fails
# the same way. Every file the script names must exist: brcc32 reports a
# missing one only as a bare exit code.
param(
    [Parameter(Mandatory)][string]$Rc,
    [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$Brcc = Join-Path $Studio 'bin\brcc32.exe'
if (-not (Test-Path $Brcc)) { throw "brcc32.exe not found: $Brcc" }
$Rc = (Resolve-Path $Rc).Path
$RcDir = Split-Path -Parent $Rc
$Out = [IO.Path]::GetFullPath($Out)

$Missing = @()
foreach ($Line in (Get-Content $Rc)) {
    if ($Line -match '^\s*[A-Za-z0-9_]+\s+(RCDATA|ICON|BITMAP|CURSOR)\s+"([^"]+)"') {
        $Path = $Matches[2] -replace '\\\\', '\'
        if (-not (Test-Path (Join-Path $RcDir $Path))) { $Missing += $Path }
    }
}
if ($Missing.Count -gt 0) {
    throw "$(Split-Path -Leaf $Rc) names files that do not exist: $($Missing -join ', ')"
}

Push-Location $RcDir
try {
    & $Brcc "-fo$Out" $Rc | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "brcc32 failed with $LASTEXITCODE ($(Split-Path -Leaf $Rc))" }
} finally {
    Pop-Location
}
