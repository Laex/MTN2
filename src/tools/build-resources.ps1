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

$RcName = Split-Path -Leaf $Rc

$Files = @(foreach ($Line in (Get-Content $Rc)) {
    if ($Line -match '^\s*[A-Za-z0-9_]+\s+(RCDATA|ICON|BITMAP|CURSOR)\s+"([^"]+)"') {
        $Matches[2] -replace '\\\\', '\'
    }
})
$Missing = @($Files | Where-Object { -not (Test-Path (Join-Path $RcDir $_)) })
if ($Missing.Count -gt 0) {
    throw "$RcName names files that do not exist: $($Missing -join ', ')"
}

# brcc32 cuts an input path at a folder whose name starts with a dot, then
# writes an empty resource file and still exits with 0. Such a source folder is
# compiled through a temporary junction that has a plain path.
$WorkDir = $RcDir
$Link = $null
if ($RcDir -match '\\\.') {
    $Link = Join-Path ([IO.Path]::GetTempPath()) "rc-$([Guid]::NewGuid().ToString('N'))"
    if ($Link -match '\\\.') {
        throw "brcc32 cannot read from $RcDir, and the temporary folder has a dot folder too: $Link"
    }
    New-Item -ItemType Junction -Path $Link -Target $RcDir | Out-Null
    $WorkDir = $Link
}

# A result left from an earlier run must not pass for this one.
if (Test-Path $Out) { Remove-Item $Out -Force }
try {
    Push-Location $WorkDir
    try {
        & $Brcc "-fo$Out" $RcName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "brcc32 failed with $LASTEXITCODE ($RcName)" }
    } finally {
        Pop-Location
    }
} finally {
    # Non-recursive: removes the junction and leaves the folder it points to.
    if ($Link) { [IO.Directory]::Delete($Link) }
}

# An empty .res is its 32-byte header alone.
$Size = if (Test-Path $Out) { (Get-Item $Out).Length } else { 0 }
if ($Files.Count -gt 0 -and $Size -le 32) {
    throw "brcc32 produced no resources from $Rc ($($Files.Count) listed, $Out is $Size bytes)"
}
