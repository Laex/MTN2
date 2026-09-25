unit uDualPanelTopMenu;

{ TUI top-menu action table extracted from TDualPanelWindow.ExecuteTopMenuAction.
  Reuses TDualPanelKeymapHost so BindKeymapHost stays the single sink. }

interface

uses
  uDualPanelInput, uTopMenuBar, uDualPanelTypes, uDualPanelUiTypes;

type
  TTopMenuEnableContext = record
    Kind: TWorkspaceKind;
    DocReady: Boolean;
    CanEdit: Boolean;
    HexBinaryLocked: Boolean;
    CanUndo: Boolean;
    CanRedo: Boolean;
    CmdFocused: Boolean;
  end;

function DispatchTopMenuAction(const AHost: TDualPanelKeymapHost;
  AAction: TTopMenuAction): Boolean;
function TopMenuActionEnabled(AAction: TTopMenuAction;
  const ACtx: TTopMenuEnableContext): Boolean;

implementation

procedure CallProc(const AProc: TKeymapProc);
begin
  if Assigned(AProc) then
    AProc();
end;

procedure CallSide(const AProc: TKeymapSideProc; ASide: TPanelSide);
begin
  if Assigned(AProc) then
    AProc(ASide);
end;

procedure CallBool(const AProc: TKeymapBoolProc; AValue: Boolean);
begin
  if Assigned(AProc) then
    AProc(AValue);
end;

procedure CallJob(const AProc: TKeymapJobProc; AKind: TPanelJobKind;
  ADeleteToRecycleBin: Boolean);
begin
  if Assigned(AProc) then
    AProc(AKind, ADeleteToRecycleBin);
end;

procedure ActivateThen(const AHost: TDualPanelKeymapHost; ASide: TPanelSide;
  const AThen: TKeymapProc);
begin
  CallSide(AHost.ActivateSide, ASide);
  CallProc(AThen);
end;

function DispatchTopMenuAction(const AHost: TDualPanelKeymapHost;
  AAction: TTopMenuAction): Boolean;
begin
  Result := True;
  case AAction of
    tmaNone:
      Result := False;

    tmaLeftDrive: CallSide(AHost.ToggleDrivePopup, psLeft);
    tmaLeftSort: ActivateThen(AHost, psLeft, AHost.OpenSortMenu);
    tmaLeftColumnModes: ActivateThen(AHost, psLeft, AHost.OpenColumnModeMenu);
    tmaLeftInfo: ActivateThen(AHost, psLeft, AHost.ToggleAdjacentInfoPanel);
    tmaLeftNewTab: ActivateThen(AHost, psLeft, AHost.NewPanelTab);
    tmaLeftCloseTab: CallSide(AHost.ClosePanelTabOnSide, psLeft);
    tmaLeftShowHidden: CallSide(AHost.ToggleShowHidden, psLeft);
    tmaLeftToggle: CallSide(AHost.TogglePanelVisible, psLeft);

    tmaRightDrive: CallSide(AHost.ToggleDrivePopup, psRight);
    tmaRightSort: ActivateThen(AHost, psRight, AHost.OpenSortMenu);
    tmaRightColumnModes: ActivateThen(AHost, psRight, AHost.OpenColumnModeMenu);
    tmaRightInfo: ActivateThen(AHost, psRight, AHost.ToggleAdjacentInfoPanel);
    tmaRightNewTab: ActivateThen(AHost, psRight, AHost.NewPanelTab);
    tmaRightCloseTab: CallSide(AHost.ClosePanelTabOnSide, psRight);
    tmaRightShowHidden: CallSide(AHost.ToggleShowHidden, psRight);
    tmaRightToggle: CallSide(AHost.TogglePanelVisible, psRight);

    tmaFileView: CallBool(AHost.OpenViewOrEdit, False);
    tmaFileEdit: CallBool(AHost.OpenViewOrEdit, True);
    tmaFileExternalView: CallProc(AHost.ExternalView);
    tmaFileExternalEdit: CallProc(AHost.ExternalEdit);
    tmaFileCopy: CallJob(AHost.BeginJob, pjkCopy, True);
    tmaFileMove: CallJob(AHost.BeginJob, pjkMove, True);
    tmaFileRename: CallProc(AHost.BeginRename);
    tmaFileMkDir: CallProc(AHost.BeginMkDir);
    tmaFileCreateLink: CallProc(AHost.BeginCreateLink);
    tmaFileSetAttributes: CallProc(AHost.BeginSetAttributes);
    tmaFileProperties: CallProc(AHost.ShowProperties);
    tmaFileCompare: CallProc(AHost.BeginCompareFiles);
    tmaFileChecksums: CallProc(AHost.BeginChecksums);
    tmaFileRestore: CallProc(AHost.RestoreCursorItemFromRecycleBin);
    tmaFileDelete: CallJob(AHost.BeginJob, pjkDelete, True);
    tmaFileWipe: CallJob(AHost.BeginJob, pjkDelete, False);
    tmaFilePack: CallProc(AHost.BeginPackZip);
    tmaFileUnpack: CallProc(AHost.BeginUnpackZip);
    tmaFileJobList: CallProc(AHost.OpenJobList);
    tmaFileSelectMask: CallBool(AHost.BeginSelectByMask, False);
    tmaFileUnselectMask: CallBool(AHost.BeginSelectByMask, True);
    tmaFileSelectByExt: CallBool(AHost.ApplySelectByExtension, False);
    tmaFileUnselectByExt: CallBool(AHost.ApplySelectByExtension, True);
    tmaFileSelectAll: CallProc(AHost.SelectAllActive);
    tmaFileInvertSelect: CallProc(AHost.InvertSelectionActive);
    tmaFileCalcSize: CallProc(AHost.CalculateFolderSize);
    tmaFileCopyPath: CallProc(AHost.CopyFullPathToClipboard);
    tmaFileRunDetached: CallProc(AHost.RunDetached);
    tmaFileNew: CallProc(AHost.BeginNewFile);
    tmaCmdQuickView: CallProc(AHost.ToggleQuickView);

    tmaCmdFind: CallProc(AHost.OpenSearchDialog);
    tmaCmdDirSync: CallProc(AHost.OpenDirSync);
    tmaCmdCompareFolders: CallProc(AHost.CompareFolders);
    tmaCmdJobList: CallProc(AHost.OpenJobList);
    tmaCmdUserMenu: CallProc(AHost.OpenUserMenu);
    tmaCmdHistoryBack: CallProc(AHost.HistoryBack);
    tmaCmdHistoryForward: CallProc(AHost.HistoryForward);
    tmaCmdDriveRoot: CallProc(AHost.NavigateActiveToDriveRoot);
    tmaCmdRefresh: CallProc(AHost.RefreshActive);
    tmaCmdSwapPanels: CallProc(AHost.SwapPanels);
    tmaCmdEqualizeOther: CallProc(AHost.EqualizeOtherPanelToActive);
    tmaCmdEqualizeActive: CallProc(AHost.EqualizeActivePanelFromOther);
    tmaCmdInsertName: CallBool(AHost.InsertPanelItemToCmdLine, False);
    tmaCmdInsertPath: CallBool(AHost.InsertPanelItemToCmdLine, True);
    tmaCmdFocusCmdLine: CallProc(AHost.FocusCommandLine);
    tmaCmdConsoleToggle: CallProc(AHost.ToggleConsole);
    tmaCmdNewTerminal: CallProc(AHost.OpenTerminalProfileDialog);
    tmaCmdConsoleProfile: CallProc(AHost.OpenConsoleProfileDialog);
    tmaCmdSyncConsoleDir: CallProc(AHost.SyncConsoleDirNow);
    tmaCmdFolderHistory: CallProc(AHost.OpenFolderHistoryDialog);
    tmaCmdFileHistory: CallProc(AHost.OpenFileHistoryDialog);
    tmaCmdCmdHistory: CallProc(AHost.OpenCmdHistoryDialog);
    tmaCmdFolderHotlist: CallProc(AHost.OpenFolderHotlistDialog);
    tmaCmdFolderHotlistAdd: CallProc(AHost.BeginFolderHotlistAdd);
    tmaCmdWorkspaceLibrary: CallProc(AHost.OpenWorkspaceLibraryDialog);
    tmaCmdWorkspaceSave: CallProc(AHost.BeginWorkspaceLibrarySave);
    tmaCmdSshConnections: CallProc(AHost.OpenSshConnectionsDialog);
    tmaCmdAssociations: CallProc(AHost.OpenUserAssociationsDialog);
    tmaCmdBranchView: CallProc(AHost.BeginBranchView);
    tmaCmdLiveFilter: CallProc(AHost.BeginLiveFilter);
    tmaCmdRecycleBin: CallProc(AHost.NavigateToRecycleBin);
    tmaCmdNextTab: CallProc(AHost.NextWorkspace);

    tmaEditCopy: CallProc(AHost.EditCopy);
    tmaEditCut: CallProc(AHost.EditCut);
    tmaEditPaste: CallProc(AHost.EditPaste);
    tmaEditGotoLine: CallProc(AHost.EditGotoLine);
    tmaEditFind: CallProc(AHost.EditFind);
    tmaEditFindReplace: CallProc(AHost.EditFindReplace);
    tmaEditEncoding: CallProc(AHost.EditEncoding);
    tmaEditUndo: CallProc(AHost.EditUndo);
    tmaEditRedo: CallProc(AHost.EditRedo);
    tmaEditHexToggle: CallProc(AHost.EditHexToggle);

    tmaOptReloadKeymap: CallProc(AHost.ReloadKeymapProfile);
    tmaOptShowPlugins: CallProc(AHost.OpenPluginListDialog);
    tmaOptColorCoding: CallProc(AHost.OpenColorCodingDialog);
    tmaOptKeymap: CallProc(AHost.OpenKeymapDialog);
    tmaOptTheme: CallProc(AHost.OpenThemeDialog);
    tmaOptColumnsConfig: CallProc(AHost.OpenColumnsConfigDialog);
    tmaOptDisplay: CallProc(AHost.OpenDisplayDialog);
    tmaOptExternalTools: CallProc(AHost.OpenExternalToolsDialog);
    tmaOptZoomIn, tmaOptZoomOut, tmaOptResetZoom: ;

    tmaHelpContents: CallProc(AHost.OpenHelp);
    tmaHelpAbout: CallProc(AHost.OpenAboutDialog);
    tmaHelpUpdates: CallProc(AHost.OpenUpdates);
    tmaQuit: CallProc(AHost.RequestQuit);
  else
    Result := False;
  end;
end;

function TopMenuActionEnabled(AAction: TTopMenuAction;
  const ACtx: TTopMenuEnableContext): Boolean;
begin
  case AAction of
    tmaNone:
      Exit(False);

    tmaHelpContents, tmaHelpAbout, tmaHelpUpdates, tmaQuit,
    tmaOptReloadKeymap, tmaOptShowPlugins, tmaOptColorCoding, tmaOptKeymap,
    tmaOptTheme,
    tmaOptColumnsConfig, tmaOptDisplay, tmaOptExternalTools, tmaOptZoomIn, tmaOptZoomOut, tmaOptResetZoom,
    tmaCmdNextTab, tmaCmdNewTerminal, tmaCmdConsoleToggle, tmaCmdConsoleProfile:
      Exit(True);

    tmaEditCopy:
      Exit(ACtx.CmdFocused or
        ((ACtx.Kind = wkDocument) and ACtx.DocReady) or
        (ACtx.Kind = wkPanels));
    tmaEditCut, tmaEditPaste:
      Exit(ACtx.CmdFocused or
        ((ACtx.Kind = wkDocument) and ACtx.DocReady and ACtx.CanEdit) or
        (ACtx.Kind = wkPanels));
    tmaEditGotoLine, tmaEditFind, tmaEditEncoding:
      Exit((ACtx.Kind = wkDocument) and ACtx.DocReady);
    tmaEditFindReplace:
      Exit((ACtx.Kind = wkDocument) and ACtx.DocReady and ACtx.CanEdit);
    tmaEditUndo:
      Exit((ACtx.Kind = wkDocument) and ACtx.DocReady and ACtx.CanUndo);
    tmaEditRedo:
      Exit((ACtx.Kind = wkDocument) and ACtx.DocReady and ACtx.CanRedo);
    tmaEditHexToggle:
      Exit((ACtx.Kind = wkDocument) and ACtx.DocReady);
  else
    // Left / Right / Files / remaining Commands need a file list.
    Result := ACtx.Kind = wkPanels;
  end;
end;

end.
