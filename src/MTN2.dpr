program MTN2;

// Skia: project DCC_Define SKIA in MTN2.dproj (+ GlobalUseSkia below).
// Rollback: remove SKIA from DCC_Define and the FMX.Skia / GlobalUseSkia bits.
// Runtime: --no-skia leaves the Skia-linked binary on the GDI/FMX canvas.

// RAD Studio 13 (Delphi 13, CompilerVersion 37) or later. Older compilers
// fail deep inside the units with confusing errors, so stop here with a
// clear message instead.
{$IF CompilerVersion < 37.0}
  {$MESSAGE FATAL 'MTN2 requires RAD Studio 13 (Delphi 13, Studio\37.0) or later. See docs/BUILDING.md.'}
{$IFEND}

uses
  {$IFDEF SKIA}
  FMX.Skia,
  {$ENDIF}
  System.StartUpCopy,
  Winapi.Windows,
  FMX.Forms,
  uCharWidth in 'Core\uCharWidth.pas',
  uPlatformProcess in 'Platform\Windows\uPlatformProcess.pas',
  uFileAttrTypes in 'Core\uFileAttrTypes.pas',
  uPlatformFileAttr in 'Platform\Windows\uPlatformFileAttr.pas',
  uPlatformHostInfo in 'Platform\Windows\uPlatformHostInfo.pas',
  uPlatformFolders in 'Platform\Windows\uPlatformFolders.pas',
  uPlatformFileOps in 'Platform\Windows\uPlatformFileOps.pas',
  uDriveTypes in 'Core\uDriveTypes.pas',
  uPlatformDrives in 'Platform\Windows\uPlatformDrives.pas',
  uPlatformUpdate in 'Platform\Windows\uPlatformUpdate.pas',
  uPlatformPaths in 'Platform\Windows\uPlatformPaths.pas',
  uPlatformInfo in 'Platform\Windows\uPlatformInfo.pas',
  uPlatformFonts in 'Platform\Windows\uPlatformFonts.pas',
  uClipboardService in 'Core\uClipboardService.pas',
  uFmxClipboard in 'Hosts\Fmx\uFmxClipboard.pas',
  uResourceAccess in 'Platform\Windows\uResourceAccess.pas',
  uTerminalTypes in 'Core\uTerminalTypes.pas',
  uConfigLocation in 'Core\uConfigLocation.pas',
  uFolderHistory in 'Core\uFolderHistory.pas',
  uFileHistory in 'Core\uFileHistory.pas',
  uHelpContext in 'Core\uHelpContext.pas',
  uPanelCompare in 'Core\uPanelCompare.pas',
  uExternalTools in 'Core\uExternalTools.pas',
  uMarkdownColors in 'Core\uMarkdownColors.pas',
  uDialogHistory in 'Core\uDialogHistory.pas',
  uHistoryPopup in 'Core\uHistoryPopup.pas',
  uChecksums in 'Core\uChecksums.pas',
  uThemeTypes in 'Core\uThemeTypes.pas',
  uMessageBus in 'Core\uMessageBus.pas',
  uDualPanelInput in 'Core\uDualPanelInput.pas',
  uDualPanelTopMenu in 'Core\uDualPanelTopMenu.pas',
  uDualPanelClick in 'Core\uDualPanelClick.pas',
  uDualPanelDrag in 'Core\uDualPanelDrag.pas',
  uDualPanelTabs in 'Core\uDualPanelTabs.pas',
  uDualPanelCommands in 'Core\uDualPanelCommands.pas',
  uEditorSearch in 'Core\uEditorSearch.pas',
  uEditorUndo in 'Core\uEditorUndo.pas',
  uEditorLineOps in 'Core\uEditorLineOps.pas',
  uMultiRename in 'Core\uMultiRename.pas',
  uDualPanelMultiRename in 'Core\uDualPanelMultiRename.pas',
  uEditorLayout in 'Core\uEditorLayout.pas',
  uEditorDialogs in 'Core\uEditorDialogs.pas',
  uEditorInput in 'Core\uEditorInput.pas',
  uKeyChord in 'Core\uKeyChord.pas',
  uKeyRouting in 'Core\uKeyRouting.pas',
  uVfsUtils in 'Core\uVfsUtils.pas',
  uDialogRenderer in 'Core\uDialogRenderer.pas',
  uDualPanelCmdLine in 'Core\uDualPanelCmdLine.pas',
  uFileVfsScanner in 'Core\uFileVfsScanner.pas',
  uPanelPluginRegistry in 'Core\uPanelPluginRegistry.pas',
  uPluginHostAbi in 'Core\uPluginHostAbi.pas',
  uTerminalWindow in 'Core\uTerminalWindow.pas',
  uDualPanelTypes in 'Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in 'Core\uDualPanelUiTypes.pas',
  uDualPanelCmd in 'Core\uDualPanelCmd.pas',
  uInputLine in 'Core\uInputLine.pas',
  uFunctionBar in 'Core\uFunctionBar.pas',
  uPanelModel in 'Core\uPanelModel.pas',
  uPanelColumns in 'Core\uPanelColumns.pas',
  uListExport in 'Core\uListExport.pas',
  uDisplaySettings in 'Core\uDisplaySettings.pas',
  uChromeRows in 'Core\uChromeRows.pas',
  uStatusSegments in 'Core\uStatusSegments.pas',
  uDirWatch in 'Platform\Windows\uDirWatch.pas',
  uDialogTypes in 'Core\uDialogTypes.pas',
  uDialogJson in 'Core\uDialogJson.pas',
  uDialogResources in 'Core\uDialogResources.pas',
  uDialogHost in 'Core\uDialogHost.pas',
  uDualPanelOverlays in 'Core\uDualPanelOverlays.pas',
  uDualPanelDrivePopup in 'Core\uDualPanelDrivePopup.pas',
  uDualPanelFolderTree in 'Core\uDualPanelFolderTree.pas',
  uDualPanelHistoryPopup in 'Core\uDualPanelHistoryPopup.pas',
  uDualPanelJobs in 'Core\uDualPanelJobs.pas',
  uDualPanelJobRules in 'Core\uDualPanelJobRules.pas',
  uDualPanelJobChips in 'Core\uDualPanelJobChips.pas',
  uWindowChrome in 'Core\uWindowChrome.pas',
  uDescriptIon in 'Core\uDescriptIon.pas',
  uDualPanelJobList in 'Core\uDualPanelJobList.pas',
  uDualPanelSync in 'Core\uDualPanelSync.pas',
  uDualPanelSearch in 'Core\uDualPanelSearch.pas',
  uDualPanelMenus in 'Core\uDualPanelMenus.pas',
  uTopMenuBar in 'Core\uTopMenuBar.pas',
  uDualPanelFolderSize in 'Core\uDualPanelFolderSize.pas',
  uDualPanelSelection in 'Core\uDualPanelSelection.pas',
  uDualPanelDrawUtils in 'Core\uDualPanelDrawUtils.pas',
  uColorCodingEditHelpers in 'Core\uColorCodingEditHelpers.pas',
  uDualPanelColorCoding in 'Core\uDualPanelColorCoding.pas',
  uDualPanelKeymapDialog in 'Core\uDualPanelKeymapDialog.pas',
  uDualPanelFolderHotlist in 'Core\uDualPanelFolderHotlist.pas',
  uDualPanelHistoryDialogs in 'Core\uDualPanelHistoryDialogs.pas',
  uDualPanelPaletteDialog in 'Core\uDualPanelPaletteDialog.pas',
  uCommandPalette in 'Core\uCommandPalette.pas',
  uDualPanelSettingsDialogs in 'Core\uDualPanelSettingsDialogs.pas',
  uDualPanelThemeDialogs in 'Core\uDualPanelThemeDialogs.pas',
  uDualPanelFileDialogs in 'Core\uDualPanelFileDialogs.pas',
  uDualPanelJobDialogs in 'Core\uDualPanelJobDialogs.pas',
  uDualPanelFindDialogs in 'Core\uDualPanelFindDialogs.pas',
  uDualPanelInfoPanel in 'Core\uDualPanelInfoPanel.pas',
  uDualPanelPanelDraw in 'Core\uDualPanelPanelDraw.pas',
  uDualPanelStatus in 'Core\uDualPanelStatus.pas',
  uPanelUriLabels in 'Core\uPanelUriLabels.pas',
  uDualPanelWindow in 'Core\uDualPanelWindow.pas',
  uVfsTypes in 'Core\uVfsTypes.pas',
  uTextEncoding in 'Core\uTextEncoding.pas',
  uFileVfs in 'Core\uFileVfs.pas',
  uZipVfs in 'Core\uZipVfs.pas',
  uZipNames in 'Core\uZipNames.pas',
  uZipArchiveCache in 'Core\uZipArchiveCache.pas',
  uFindSession in 'Core\uFindSession.pas',
  uFindVfs in 'Core\uFindVfs.pas',
  uSysFoldersVfs in 'Core\uSysFoldersVfs.pas',
  uWorkspaceVfs in 'Core\uWorkspaceVfs.pas',
  uWorkspaceLibrary in 'Core\uWorkspaceLibrary.pas',
  uDualPanelWorkspaceLibrary in 'Core\uDualPanelWorkspaceLibrary.pas',
  uVfsRegistry in 'Core\uVfsRegistry.pas',
  uVfsRouter in 'Core\uVfsRouter.pas',
  uDriveInfo in 'Core\uDriveInfo.pas',
  uShellAssoc in 'Platform\Windows\uShellAssoc.pas',
  uConsoleLaunch in 'Core\uConsoleLaunch.pas',
  uShellIcons in 'Platform\Windows\uShellIcons.pas',
  uColorCoding in 'Core\uColorCoding.pas',
  uImageInfo in 'Core\uImageInfo.pas',
  uOverlayRenderer in 'Platform\Windows\uOverlayRenderer.pas',
  uAssociations in 'Core\uAssociations.pas',
  uKeymap in 'Core\uKeymap.pas',
  uEditorDoc in 'Core\uEditorDoc.pas',
  uEditorHexView in 'Core\uEditorHexView.pas',
  uEditorPainter in 'Core\uEditorPainter.pas',
  uEditorWindow in 'Core\uEditorWindow.pas',
  uHelpViewer in 'Core\uHelpViewer.pas',
  uQuickTextView in 'Core\uQuickTextView.pas',
  uFileFind in 'Core\uFileFind.pas',
  uFileCompare in 'Core\uFileCompare.pas',
  uFolderSize in 'Core\uFolderSize.pas',
  uDualPanelOperations in 'Core\uDualPanelOperations.pas',
  uConsoleBuffer in 'Core\uConsoleBuffer.pas',
  uANSIParser in 'Core\uANSIParser.pas',
  uConPty in 'Platform\Windows\uConPty.pas',
  uShellProfiles in 'Platform\Windows\uShellProfiles.pas',
  uBaseConsoleWindow in 'Core\uBaseConsoleWindow.pas',
  uConsoleWindow in 'Core\uConsoleWindow.pas',
  uTerminalWorkspace in 'Core\uTerminalWorkspace.pas',
  uSession in 'Core\uSession.pas',
  uMdiCompositor in 'Core\uMdiCompositor.pas',
  uThemeSpec in 'Core\uThemeSpec.pas',
  uThemeNames in 'Core\uThemeNames.pas',
  uDataTheme in 'Core\uDataTheme.pas',
  uThemeRegistry in 'Core\uThemeRegistry.pas',
  uThemeController in 'Core\uThemeController.pas',
  uThemeProxy in 'Core\uThemeProxy.pas',
  uTerminalRenderer in 'Core\uTerminalRenderer.pas',
  uFileClip in 'Core\uFileClip.pas',
  uCoreTimer in 'Core\uCoreTimer.pas',
  uFmxTimer in 'Hosts\Fmx\uFmxTimer.pas',
  uFmxRenderProfile in 'Hosts\Fmx\uFmxRenderProfile.pas',
  uWinFileDragDrop in 'Platform\Windows\uWinFileDragDrop.pas',
  uWinFileAttr in 'Core\uWinFileAttr.pas',
  uSingleInstance in 'Platform\Windows\uSingleInstance.pas',
  uTaskbarProgress in 'Platform\Windows\uTaskbarProgress.pas',
  uStartupTargets in 'Core\uStartupTargets.pas',
  uUpdateCli in 'Core\uUpdateCli.pas',
  uUpdater in 'Core\uUpdater.pas',
  uSelfCheck in 'Core\uSelfCheck.pas',
  uElevatedHelper in 'Platform\Windows\uElevatedHelper.pas',
  uUpdateController in 'Core\uUpdateController.pas',
  uNotice in 'Core\uNotice.pas',
  uHiddenDialogs in 'Core\uHiddenDialogs.pas',
  uToast in 'Core\uToast.pas',
  uFrameStats in 'Core\uFrameStats.pas',
  uMainForm in 'Forms\uMainForm.pas' {MainForm};

{$R *.res}
{$R *.dres}

var
  AlreadyRunning: Boolean;
  ExistingHwnd: HWND;
  UpdateChannel: string;
begin
  // --self-check: report missing run-time files and exit (release smoke
  // test, src\tools\check-release.ps1) -- no window, no instance handshake.
  if SelfCheckRequested then
  begin
    ExitCode := RunSelfCheckToStdOut;
    Exit;
  end;

  // --update [stable|nightly]: install the latest version without a window.
  if UpdateRequested(UpdateChannel) then
  begin
    ExitCode := RunUpdateCommand(UpdateChannel,
      procedure(const ALine: string)
      begin
        PlatformWriteStdOut(ALine + #13#10);
      end);
    Exit;
  end;

  // --elevated-helper: the administrator helper of a running program (UAC
  // prompt, no window); it serves file operations over pipes and exits.
  if ElevatedHelperRequested then
  begin
    ExitCode := RunElevatedHelper;
    Exit;
  end;

  // Restarted by the updater (--wait-pid): let the previous process finish exiting
  // first, or the single-instance check below would hand off to it and quit.
  WaitForPreviousInstanceFromCommandLine;

  // Mtn2 <path> with another instance already running forwards the
  // path via WM_COPYDATA and exits here -- before Application.Initialize, so
  // the delegating second process never touches FMX/the platform layer.
  if TryAcquireSingleInstance(AlreadyRunning) and AlreadyRunning then
  begin
    if TryFindExistingInstanceWindow(ExistingHwnd) then
    begin
      SendActivateRequest(ExistingHwnd, EncodeStartupTargets(StartupTargetsArgument));
      Exit;
    end;
    // Existing window not found (narrow startup race) -- fall through to a
    // normal start rather than silently dropping the user's path.
  end;

  {$IFDEF SKIA}
  GlobalUseSkia := not NoSkiaRequested;
  {$ENDIF}
  InstallFmxRenderProfile;
  Application.Initialize;
  // The taskbar button shows this until the main window gets its own caption.
  Application.Title := 'Modern Terminal Navigator 2';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
