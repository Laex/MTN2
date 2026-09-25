program MTN2;

// Skia: project DCC_Define SKIA in MTN2.dproj (+ GlobalUseSkia below).
// Rollback: remove SKIA from DCC_Define and the FMX.Skia / GlobalUseSkia bits.

uses
  {$IFDEF SKIA}
  FMX.Skia,
  {$ENDIF}
  System.StartUpCopy,
  Winapi.Windows,
  FMX.Forms,
  uTerminalTypes in 'Core\uTerminalTypes.pas',
  uConfigLocation in 'Core\uConfigLocation.pas',
  uFolderHistory in 'Core\uFolderHistory.pas',
  uFileHistory in 'Core\uFileHistory.pas',
  uHelpContext in 'Core\uHelpContext.pas',
  uPanelCompare in 'Core\uPanelCompare.pas',
  uExternalTools in 'Core\uExternalTools.pas',
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
  uEditorLayout in 'Core\uEditorLayout.pas',
  uEditorDialogs in 'Core\uEditorDialogs.pas',
  uEditorInput in 'Core\uEditorInput.pas',
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
  uDisplaySettings in 'Core\uDisplaySettings.pas',
  uDirWatch in 'Core\uDirWatch.pas',
  uDialogTypes in 'Core\uDialogTypes.pas',
  uDialogJson in 'Core\uDialogJson.pas',
  uDialogResources in 'Core\uDialogResources.pas',
  uDialogHost in 'Core\uDialogHost.pas',
  uDualPanelOverlays in 'Core\uDualPanelOverlays.pas',
  uDualPanelDrivePopup in 'Core\uDualPanelDrivePopup.pas',
  uDualPanelHistoryPopup in 'Core\uDualPanelHistoryPopup.pas',
  uDualPanelJobs in 'Core\uDualPanelJobs.pas',
  uDualPanelJobRules in 'Core\uDualPanelJobRules.pas',
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
  uDualPanelSettingsDialogs in 'Core\uDualPanelSettingsDialogs.pas',
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
  uShellAssoc in 'Core\uShellAssoc.pas',
  uShellIcons in 'Core\uShellIcons.pas',
  uColorCoding in 'Core\uColorCoding.pas',
  uOverlayRenderer in 'Core\uOverlayRenderer.pas',
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
  uConPty in 'Core\uConPty.pas',
  uShellProfiles in 'Core\uShellProfiles.pas',
  uBaseConsoleWindow in 'Core\uBaseConsoleWindow.pas',
  uConsoleWindow in 'Core\uConsoleWindow.pas',
  uTerminalWorkspace in 'Core\uTerminalWorkspace.pas',
  uSession in 'Core\uSession.pas',
  uMdiCompositor in 'Core\uMdiCompositor.pas',
  uNDNTheme in 'Themes\uNDNTheme.pas',
  uModernUnicodeTheme in 'Themes\uModernUnicodeTheme.pas',
  uASCIITheme in 'Themes\uASCIITheme.pas',
  uTotalCommanderTheme in 'Themes\uTotalCommanderTheme.pas',
  uSolarizedDarkTheme in 'Themes\uSolarizedDarkTheme.pas',
  uDraculaTheme in 'Themes\uDraculaTheme.pas',
  uNordTheme in 'Themes\uNordTheme.pas',
  uHighContrastTheme in 'Themes\uHighContrastTheme.pas',
  uThemeRegistry in 'Core\uThemeRegistry.pas',
  uThemeProxy in 'Core\uThemeProxy.pas',
  uTerminalRenderer in 'Core\uTerminalRenderer.pas',
  uWinFileDragDrop in 'Core\uWinFileDragDrop.pas',
  uWinFileAttr in 'Core\uWinFileAttr.pas',
  uSingleInstance in 'Core\uSingleInstance.pas',
  uUpdater in 'Core\uUpdater.pas',
  uUpdateController in 'Core\uUpdateController.pas',
  uMainForm in 'Forms\uMainForm.pas' {MainForm};

{$R *.res}
{$R *.dres}

var
  AlreadyRunning: Boolean;
  ExistingHwnd: HWND;
begin
  // Restarted by the updater (--wait-pid): let the old process finish exiting
  // first, or the single-instance check below would hand off to it and quit.
  WaitForPreviousInstanceFromCommandLine;

  // Stage 28: mtn2 <path> with another instance already running forwards the
  // path via WM_COPYDATA and exits here -- before Application.Initialize, so
  // the delegating second process never touches FMX/the platform layer.
  if TryAcquireSingleInstance(AlreadyRunning) and AlreadyRunning then
  begin
    if TryFindExistingInstanceWindow(ExistingHwnd) then
    begin
      SendActivateRequest(ExistingHwnd, StartupPathArgument);
      Exit;
    end;
    // Existing window not found (narrow startup race) -- fall through to a
    // normal start rather than silently dropping the user's path.
  end;

  {$IFDEF SKIA}
  GlobalUseSkia := True;
  {$ENDIF}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
