# Compiles the resources of the Linux programs and the Linux tests into
# src\MTN2Tui.dres: everything MTN2Resource.rc embeds, plus RESOURCE_INDEX, a
# list of the resource names, because the Linux runtime cannot enumerate them.
$ErrorActionPreference = 'Stop'
$Src = Split-Path -Parent $PSScriptRoot
$Names = Get-Content (Join-Path $Src 'MTN2Resource.rc') |
    Where-Object { $_ -match '^\s*([A-Z0-9_]+)\s+RCDATA\s' } |
    ForEach-Object { $Matches[1] }
# The menu icon the Linux programs write into ~/.local/share (uDesktopEntry).
$Names = @($Names) + 'APP_ICON'
[IO.File]::WriteAllText((Join-Path $Src 'MTN2Tui.index.txt'), ($Names -join "`n") + "`n",
    (New-Object Text.UTF8Encoding $false))
$RcText = (Get-Content (Join-Path $Src 'MTN2Resource.rc') -Raw) +
    "`r`nAPP_ICON RCDATA `"Assets\\mtn2-icon-256.png`"" +
    "`r`nRESOURCE_INDEX RCDATA `"MTN2Tui.index.txt`"`r`n"
$Rc = Join-Path $Src 'MTN2Tui.rc'
[IO.File]::WriteAllText($Rc, $RcText, (New-Object Text.UTF8Encoding $false))
& (Join-Path $PSScriptRoot 'build-resources.ps1') -Rc $Rc -Out (Join-Path $Src 'MTN2Tui.dres')
