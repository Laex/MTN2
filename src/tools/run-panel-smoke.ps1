param()
$ErrorActionPreference = 'Stop'
$Studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$RsVars = Join-Path $Studio 'bin\rsvars.bat'
$Tools = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    & (Join-Path $Tools 'fetch-wasmtime.ps1')
} catch {
    Write-Host "WARN: wasmtime.dll fetch failed; TestWasmHost will SKIP if the DLL is absent"
}
$WsSrc = Join-Path (Split-Path $Tools -Parent) 'plugins\mtn.ws'
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    try {
        rustup target add wasm32-unknown-unknown | Out-Null
        Push-Location $WsSrc
        try {
            $env:CARGO_TARGET_DIR = Join-Path $WsSrc 'target'
            cargo build --target wasm32-unknown-unknown --release
            if ($LASTEXITCODE -ne 0) { throw "mtn.ws cargo build failed" }
            Copy-Item (Join-Path $WsSrc 'target\wasm32-unknown-unknown\release\mtn_ws.wasm') (Join-Path $WsSrc 'plugin.wasm') -Force
        } finally {
            Pop-Location
        }
    } catch {
        Write-Host "WARN: mtn.ws cargo build failed; TestWorkspacePlugin will SKIP if plugin.wasm is absent"
    }
} else {
    Write-Host "WARN: cargo not found; TestWorkspacePlugin will SKIP if plugin.wasm is absent"
}
$Cmd = @"
call "$RsVars" && cd /d "$Tools" && (if not exist dcu mkdir dcu) && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestANSIParser.dpr && .\dcu\TestANSIParser.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestConfigLocation.dpr && .\dcu\TestConfigLocation.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestKeymap.dpr && .\dcu\TestKeymap.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPtySession.dpr && .\dcu\TestPtySession.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorPainter.dpr && .\dcu\TestEditorPainter.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorLayout.dpr && .\dcu\TestEditorLayout.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorDialogs.dpr && .\dcu\TestEditorDialogs.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorInput.dpr && .\dcu\TestEditorInput.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestZipNames.dpr && .\dcu\TestZipNames.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorSearchUndo.dpr && .\dcu\TestEditorSearchUndo.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPanelViewController.dpr && .\dcu\TestPanelViewController.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPanelModel.dpr && .\dcu\TestPanelModel.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestMessageBus.dpr && .\dcu\TestMessageBus.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelInput.dpr && .\dcu\TestDualPanelInput.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelTopMenu.dpr && .\dcu\TestDualPanelTopMenu.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestWinFileClipboard.dpr && .\dcu\TestWinFileClipboard.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelOperations.dpr && .\dcu\TestDualPanelOperations.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestUserAssociations.dpr && .\dcu\TestUserAssociations.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelJobDialogs.dpr && .\dcu\TestDualPanelJobDialogs.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelJobRules.dpr && .\dcu\TestDualPanelJobRules.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelPanelDraw.dpr && .\dcu\TestDualPanelPanelDraw.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDriveInfo.dpr && .\dcu\TestDriveInfo.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelStatus.dpr && .\dcu\TestDualPanelStatus.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelClick.dpr && .\dcu\TestDualPanelClick.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelDrag.dpr && .\dcu\TestDualPanelDrag.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelTabs.dpr && .\dcu\TestDualPanelTabs.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelCommands.dpr && .\dcu\TestDualPanelCommands.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDialogJson.dpr && .\dcu\TestDialogJson.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestEditorSearchUndo.dpr && .\dcu\TestEditorSearchUndo.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestVfsUtils.dpr && .\dcu\TestVfsUtils.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestResolveLocalDirPath.dpr && .\dcu\TestResolveLocalDirPath.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestVfsRegistry.dpr && .\dcu\TestVfsRegistry.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestSftpVfs.dpr && .\dcu\TestSftpVfs.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPluginManifest.dpr && .\dcu\TestPluginManifest.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelMenuManager.dpr && .\dcu\TestDualPanelMenuManager.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDialogRenderer.dpr && .\dcu\TestDialogRenderer.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelJobsManager.dpr && .\dcu\TestDualPanelJobsManager.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelCmdLine.dpr && .\dcu\TestDualPanelCmdLine.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestFileVfsScanner.dpr && .\dcu\TestFileVfsScanner.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPanelPluginRegistry.dpr && .\dcu\TestPanelPluginRegistry.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPluginHostAbi.dpr && .\dcu\TestPluginHostAbi.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils SamplePlugin.dpr && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPluginLoader.dpr && .\dcu\TestPluginLoader.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestSevenZipUri.dpr && .\dcu\TestSevenZipUri.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils ..\plugins\mtn.7z\SevenZipPlugin.dpr && dcc64 -B -U..\Core;..\plugins\mtn.7z -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestSevenZipPlugin.dpr && .\dcu\TestSevenZipPlugin.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils ..\plugins\mtn.tmp\TmpPanelPlugin.dpr && dcc64 -B -U..\Core;..\plugins\mtn.tmp -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestTmpPanelPlugin.dpr && .\dcu\TestTmpPanelPlugin.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestShellProfiles.dpr && .\dcu\TestShellProfiles.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestPanelSelect.dpr && .\dcu\TestPanelSelect.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestLongPaths.dpr && .\dcu\TestLongPaths.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestWinFileAttr.dpr && .\dcu\TestWinFileAttr.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi TestPanelColumns.dpr && .\dcu\TestPanelColumns.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDisplaySettings.dpr && .\dcu\TestDisplaySettings.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestWasmHost.dpr && .\dcu\TestWasmHost.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestWorkspacePlugin.dpr && .\dcu\TestWorkspacePlugin.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestWorkspaceLibrary.dpr && .\dcu\TestWorkspaceLibrary.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDualPanelSync.dpr && .\dcu\TestDualPanelSync.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestFileCompare.dpr && .\dcu\TestFileCompare.exe && dcc64 -B -U..\Core -N".\dcu" -E".\dcu" -NSSystem;System.Win;Winapi;System.IOUtils TestDirWatchSlowDrive.dpr && .\dcu\TestDirWatchSlowDrive.exe
"@
# The whole chain as one `cmd /c` line outgrew cmd's 8191-char limit ("The
# command line is too long" — nothing ran). Import rsvars' environment once,
# then run the steps one at a time, stopping at the first failure.
$Steps = $Cmd -split ' && '
$EnvDump = cmd /c "$($Steps[0]) >nul && set"
if ($LASTEXITCODE -ne 0) { throw "rsvars failed: $LASTEXITCODE" }
foreach ($Line in $EnvDump) {
    if ($Line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
Push-Location $Tools
try {
    foreach ($Step in $Steps | Select-Object -Skip 1) {
        if ($Step -match '^cd /d ') { continue }
        cmd /c $Step
        if ($LASTEXITCODE -ne 0) { throw "tests failed: $LASTEXITCODE ($Step)" }
    }
} finally {
    Pop-Location
}
Write-Host 'OK: smoke tests'
