unit uDualPanelInput;

{ Dual Panel Input Handler: Key mapping & input routing logic.
  Extracted from uDualPanelWindow.pas to separate key translation & shortcuts
  from UI rendering and window management. Reads bindings dynamically via uKeymap. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap, uDialogTypes, uDualPanelTypes, uDualPanelUiTypes, uPanelColumns;

type
  TDualPanelInputAction = (
    iaNone,
    iaActivateCurrent,
    iaCopy,
    iaMove,
    iaMakeDir,
    iaDelete,
    iaView,
    iaEdit,
    iaNewFile,
    iaSearch,
    iaQuit,
    iaToggleConsole,
    iaRefresh,
    iaSelectAll,
    iaInvertSelection,
    iaHistoryBack,
    iaHistoryForward
  );

  /// <summary>Decoupled Keymap & Shortcut translator for Dual Panel UI.</summary>
  TDualPanelInputHandler = class
  public
    class function TranslateShortcut(AKey: Word; AShift: TShiftState; AKeyChar: Char;
      const AKeymap: TKeymapProfile): TDualPanelInputAction; overload;
    class function TranslateShortcut(AKey: Word; AShift: TShiftState; AKeyChar: Char): TDualPanelInputAction; overload;
    class function IsNavigationKey(AKey: Word): Boolean;
    class function IsCommandExecutionKey(AKey: Word; AShift: TShiftState): Boolean;
  end;

  TKeymapProc = procedure of object;
  TKeymapBoolProc = procedure(AValue: Boolean) of object;
  TKeymapSideProc = procedure(ASide: TPanelSide) of object;
  TKeymapSortProc = procedure(ASide: TPanelSide; ACol: TPanelSortColumn) of object;
  TKeymapColumnProc = procedure(ASide: TPanelSide; AMode: TPanelColumnMode) of object;
  TKeymapJobProc = procedure(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean) of object;
  TKeymapSideFn = function: TPanelSide of object;
  TKeymapDeltaProc = procedure(ADelta: Integer) of object;
  TKeymapSelectDeltaProc = procedure(ADelta: Integer; AExcludeLanding: Boolean) of object;
  TKeymapInputFn = function(var AKey: Word; AShift: TShiftState;
    var AKeyChar: Char): Boolean of object;

  /// <summary>Method-pointer sink for HandleKeymapAction* dispatch. Bound once
  /// by TDualPanelWindow so the case tables can live here without pulling the
  /// window unit back in.</summary>
  TDualPanelKeymapHost = record
    ActiveSide: TKeymapSideFn;
    CopyFullPathToClipboard: TKeymapProc;
    CopyItemNameToClipboard: TKeymapProc;
    ToggleConsole: TKeymapProc;
    RequestQuit: TKeymapProc;
    TogglePanelVisible: TKeymapSideProc;
    ApplySortMode: TKeymapSortProc;
    OpenSortMenu: TKeymapProc;
    ToggleDrivePopup: TKeymapSideProc;
    HistoryBack: TKeymapProc;
    HistoryForward: TKeymapProc;
    OpenFolderHistoryDialog: TKeymapProc;
    OpenFileHistoryDialog: TKeymapProc;
    OpenCmdHistoryDialog: TKeymapProc;
    OpenFolderHotlistDialog: TKeymapProc;
    BeginFolderHotlistAdd: TKeymapProc;
    OpenWorkspaceLibraryDialog: TKeymapProc;
    BeginWorkspaceLibrarySave: TKeymapProc;
    OpenSshConnectionsDialog: TKeymapProc;
    OpenUserAssociationsDialog: TKeymapProc;
    BeginBranchView: TKeymapProc;
    OpenPanelFilter: TKeymapProc;
    OpenSearchDialog: TKeymapProc;
    OpenDirSync: TKeymapProc;
    OpenJobList: TKeymapProc;
    OpenTerminalProfileDialog: TKeymapProc;
    OpenConsoleProfileDialog: TKeymapProc;
    SyncConsoleDirNow: TKeymapProc;
    FolderDown: TKeymapProc;
    GoToParent: TKeymapProc;
    ToggleFolderTree: TKeymapProc;
    ToggleShowHidden: TKeymapSideProc;
    OpenColumnModeMenu: TKeymapProc;
    ApplyColumnMode: TKeymapColumnProc;
    ToggleAdjacentInfoPanel: TKeymapProc;
    ToggleQuickView: TKeymapProc;
    SwapPanels: TKeymapProc;
    EqualizeOtherPanelToActive: TKeymapProc;
    EqualizeActivePanelFromOther: TKeymapProc;
    FocusCommandLine: TKeymapProc;
    RunDetached: TKeymapProc;
    InsertPanelItemToCmdLine: TKeymapBoolProc;
    BeginSelectByMask: TKeymapBoolProc;
    ApplySelectByExtension: TKeymapBoolProc;
    OpenHelp: TKeymapProc;
    OpenUserMenu: TKeymapProc;
    BeginPackZip: TKeymapProc;
    BeginUnpackZip: TKeymapProc;
    OpenViewOrEdit: TKeymapBoolProc;
    BeginNewFile: TKeymapProc;
    BeginJob: TKeymapJobProc;
    BeginRename: TKeymapProc;
    BeginCopyInPlace: TKeymapProc;
    BeginMkDir: TKeymapProc;
    BeginCreateLink: TKeymapProc;
    BeginSetAttributes: TKeymapProc;
    ShowProperties: TKeymapProc;
    ShellContextMenu: TKeymapProc;
    ExternalView: TKeymapProc;
    ExternalEdit: TKeymapProc;
    BeginCompareFiles: TKeymapProc;
    CompareFolders: TKeymapProc;
    OpenExternalToolsDialog: TKeymapProc;
    BeginChecksums: TKeymapProc;
    NavigateToRecycleBin: TKeymapProc;
    RestoreCursorItemFromRecycleBin: TKeymapProc;
    ActivateSide: TKeymapSideProc;
    NewPanelTab: TKeymapProc;
    NextPanelTab: TKeymapProc;
    PrevPanelTab: TKeymapProc;
    NewWorkspace: TKeymapProc;
    ClosePanelTabOnSide: TKeymapSideProc;
    CalculateFolderSize: TKeymapProc;
    TogglePanelConsoleMode: TKeymapProc;
    NextWorkspace: TKeymapProc;
    PrevWorkspace: TKeymapProc;
    ReloadKeymapProfile: TKeymapProc;
    OpenPluginListDialog: TKeymapProc;
    OpenColorCodingDialog: TKeymapProc;
    OpenKeymapDialog: TKeymapProc;
    OpenThemeDialog: TKeymapProc;
    OpenColumnsConfigDialog: TKeymapProc;
    OpenDisplayDialog: TKeymapProc;
    OpenAboutDialog: TKeymapProc;
    OpenUpdates: TKeymapProc;
    EditGotoLine: TKeymapProc;
    EditFind: TKeymapProc;
    EditFindReplace: TKeymapProc;
    EditEncoding: TKeymapProc;
    EditUndo: TKeymapProc;
    EditRedo: TKeymapProc;
    EditHexToggle: TKeymapProc;
    EditCopy: TKeymapProc;
    EditCut: TKeymapProc;
    EditPaste: TKeymapProc;
    NavigateActiveToDriveRoot: TKeymapProc;
    RefreshActive: TKeymapProc;
    SelectAllActive: TKeymapProc;
    InvertSelectionActive: TKeymapProc;
    MoveCursor: TKeymapDeltaProc;
    MoveCursorWithSelect: TKeymapSelectDeltaProc;
    ToggleInsertSelect: TKeymapProc;
    SubmitCommandLine: TKeymapProc;
    HandleCmdLineInput: TKeymapInputFn;
  end;

function DispatchKeymapActionPrimary(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
function DispatchKeymapActionFunctionKeys(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
function DispatchPanelNavKeys(const AHost: TDualPanelKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer; ABrief: Boolean;
  APageSize: Integer): Boolean;

type
  TEmbeddedInputOwner = (eioNone, eioDocument, eioTerminal, eioConsoleYield);

  TKeymapActionDispatchFn = function(AAction: TKeymapAction; var AKey: Word;
    var AKeyChar: Char): Boolean of object;
  TKeymapRestoreGrayProc = procedure(var AKey: Word; var AKeyChar: Char) of object;
  TKeymapTryFn = function: Boolean of object;
  TDialogCmdProc = procedure(const AControlId, AValuesJson: string) of object;
  TDialogIdFn = function: string of object;
  TDialogIdProc = procedure(const AId: string) of object;
  TDialogPressProc = procedure(const AId: string; const AAction: TProc) of object;

  TPanelFreeInputSnap = record
    DrivePreviewActive: Boolean;
    QuickViewVisible: Boolean;
    CmdLineHasText: Boolean;
    CmdFocused: Boolean;
    ViewH, Cols, PageSize: Integer;
    /// <summary>Active panel is in Brief mode: Left/Right move between its
    /// columns; every other mode sends them to the first / last item.</summary>
    Brief: Boolean;
  end;

  TDualPanelFreeInputHost = record
    CancelDrivePreview: TKeymapProc;
    CloseQuickView: TKeymapProc;
    DispatchKeymapPrimary: TKeymapActionDispatchFn;
    PreviewCycleDrive: TKeymapDeltaProc;
    NavigateActiveToDriveRoot: TKeymapProc;
    TryPasteClipboard: TKeymapTryFn;
    RestoreGrayOpKey: TKeymapRestoreGrayProc;
    BeginSelectByMask: TKeymapBoolProc;
    InvertSelectionActive: TKeymapProc;
    ApplySelectByExtension: TKeymapBoolProc;
    ApplySelectAllFiles: TKeymapBoolProc;
    ApplySelectByName: TKeymapBoolProc;
    HandleQuickSearchInput: TKeymapInputFn;
    HandleCmdLineInput: TKeymapInputFn;
    FocusCommandLine: TKeymapProc;
    SwitchSide: TKeymapProc;
    /// <summary>Up one level (Enter on ".."): Backspace with an empty
    /// command line.</summary>
    GoToParent: TKeymapProc;
    TryHotlistJump: TKeymapInputFn;
    DispatchKeymapFunctionKeys: TKeymapActionDispatchFn;
    OpenViewOrEdit: TKeymapBoolProc;
  end;

  TDualPanelModalInputHost = record
    FocusedOrDefaultButtonId: TDialogIdFn;
    DialogCommand: TDialogCmdProc;
    HandleHotlistList: TKeymapInputFn;
    HandleWorkspaceList: TKeymapInputFn;
    HandleSshConnectionsList: TKeymapInputFn;
    HandleAssociationsList: TKeymapInputFn;
    HandleColorList: TKeymapInputFn;
    HandleColorEdit: TKeymapInputFn;
    HandleKeymapList: TKeymapInputFn;
    HandleCmdHistoryFilter: TKeymapInputFn;
    HandleFileHistoryList: TKeymapInputFn;
    HandleDialogWidget: TKeymapInputFn;
    SyncColorPickerHex: TKeymapProc;
    /// <summary>A dialog DropDown / history list is open: Enter picks from it.</summary>
    DialogDropDownOpen: TKeymapTryFn;
    /// <summary>TDialogHost.RecordInputHistory for the Enter shortcut below.</summary>
    RecordDialogHistory: TDialogIdProc;
    /// <summary>TDialogHost.PressButtonThen: the Enter shortcut shows its
    /// button pressed before the command. Unset runs the command at once.</summary>
    PressDialogButton: TDialogPressProc;
  end;

procedure NormalizePanelInputKey(var AKey: Word; var AKeyChar: Char);
function ShouldOfferTopMenu(AWorkspaceKind: TWorkspaceKind;
  ADialogVisible: Boolean): Boolean;
/// <summary>The Global keymap action (kcGlobal) for this keystroke in a
/// window whose own contexts are AChain, or kaNone: the window's contexts
/// come first, so a key they bind is theirs (F10 closes a document rather
/// than quitting). Nothing while a modal dialog is open.</summary>
function GlobalKeymapAction(const AProfile: TKeymapProfile;
  const AChain: TArray<TKeymapContext>; AKey: Word; AKeyChar: Char;
  AShift: TShiftState; ADialogVisible: Boolean): TKeymapAction;
/// <summary>Runs a Global action on AHost; False for kaNone and for the ones
/// the window or form runs itself (TopMenu, ZoomReset, ReloadKeymap).</summary>
function DispatchGlobalAction(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
/// <summary>The Help key (kaHelp) over the open top menu or a dialog that has
/// no F1 of its own (ADialogWantsHelp): both would otherwise take the key
/// first.</summary>
function IsContextHelpChord(AKey: Word; AShift: TShiftState;
  ATopMenuActive, ADialogWantsHelp: Boolean): Boolean;
function ClassifyEmbeddedInputOwner(AKind: TWorkspaceKind;
  ADialogVisible, AConsoleMode: Boolean): TEmbeddedInputOwner;
function IsPasteChord(AKey: Word; AShift: TShiftState; AKeyChar: Char): Boolean;
function IsAltQuickSearchChord(AKey: Word; AShift: TShiftState): Boolean;
function QuickSearchMatchIndex(const ARows: TPanelRows; const ANeedle: string): Integer;
function ApplyQuickSearchMatch(var ATab: TTab; const ARows: TPanelRows;
  const ANeedle: string; AViewH, ACols: Integer): Boolean;
function RecoverPrintableKeyChar(AKey: Word; AKeyChar: Char): Char;

type
  TNeedleBoxAction = (nbaUnhandled, nbaClear, nbaBackspace, nbaAppend);

/// <summary>Esc and Enter close the box; Backspace and printable keys edit it.</summary>
function ClassifyNeedleBoxKey(AKey: Word; AKeyChar: Char;
  out AChar: Char): TNeedleBoxAction;
function NeedleBackspace(var AText: string): Boolean;
function DispatchPanelFreeInput(const AHost: TDualPanelFreeInputHost;
  const AKeymap: TDualPanelKeymapHost; const ASnap: TPanelFreeInputSnap;
  var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
function DispatchModalDialogInput(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;

implementation

uses
  uKeyChord;

procedure ConsumeKey(var AKey: Word; var AKeyChar: Char; AClearChar: Boolean);
begin
  AKey := 0;
  if AClearChar then
    AKeyChar := #0;
end;

class function TDualPanelInputHandler.TranslateShortcut(AKey: Word; AShift: TShiftState;
  AKeyChar: Char; const AKeymap: TKeymapProfile): TDualPanelInputAction;
var
  Act: TKeymapAction;
begin
  Result := iaNone;
  Act := MatchAction(AKeymap, AKey, AShift);
  case Act of
    kaView: Exit(iaView);
    kaEdit: Exit(iaEdit);
    kaNewFile: Exit(iaNewFile);
    kaCopy: Exit(iaCopy);
    kaMove: Exit(iaMove);
    kaMkDir: Exit(iaMakeDir);
    kaDelete, kaWipe: Exit(iaDelete);
    kaFind: Exit(iaSearch);
    kaQuit: Exit(iaQuit);
    kaConsoleToggle: Exit(iaToggleConsole);
    kaRefresh: Exit(iaRefresh);
    kaSelectAll: Exit(iaSelectAll);
    kaInvertSelection: Exit(iaInvertSelection);
    kaHistoryBack: Exit(iaHistoryBack);
    kaHistoryForward: Exit(iaHistoryForward);
  end;
end;

class function TDualPanelInputHandler.TranslateShortcut(AKey: Word; AShift: TShiftState;
  AKeyChar: Char): TDualPanelInputAction;
begin
  Result := TranslateShortcut(AKey, AShift, AKeyChar, ActiveKeymap);
end;

class function TDualPanelInputHandler.IsNavigationKey(AKey: Word): Boolean;
begin
  Result := AKey in [vkUp, vkDown, vkLeft, vkRight, vkPrior, vkNext, vkHome, vkEnd];
end;

class function TDualPanelInputHandler.IsCommandExecutionKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AKey = vkReturn) and (AShift = []);
end;

function DispatchKeymapActionPrimary(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
begin
  // The panels look keys up in Panels, then Global: the Global ones run as
  // they do from any window.
  if DispatchGlobalAction(AHost, AAction, AKey, AKeyChar) then
    Exit(True);
  Result := True;
  case AAction of
    kaCopyFullPath:
      begin
        AHost.CopyFullPathToClipboard();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaCopyItemName:
      begin
        if Assigned(AHost.CopyItemNameToClipboard) then
          AHost.CopyItemNameToClipboard();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaConsoleToggle:
      begin
        AHost.ToggleConsole();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaQuit:
      begin
        AHost.RequestQuit();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaTogglePanelLeft:
      begin
        AHost.TogglePanelVisible(psLeft);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaTogglePanelRight:
      begin
        AHost.TogglePanelVisible(psRight);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortByName:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscName);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortByExt:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscExt);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortByDate:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscModified);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortBySize:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscSize);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortUnsorted:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscNone);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortByCreated:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscCreated);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortByAccessed:
      begin
        AHost.ApplySortMode(AHost.ActiveSide(), pscAccessed);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSortMenu:
      begin
        AHost.OpenSortMenu();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaDriveLeft:
      begin
        AHost.ToggleDrivePopup(psLeft);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaDriveRight:
      begin
        AHost.ToggleDrivePopup(psRight);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaHistoryBack:
      begin
        AHost.HistoryBack();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaHistoryForward:
      begin
        AHost.HistoryForward();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaFolderHistory:
      begin
        AHost.OpenFolderHistoryDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFileHistory:
      begin
        AHost.OpenFileHistoryDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaCmdHistory:
      begin
        AHost.OpenCmdHistoryDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFolderHotlist:
      begin
        AHost.OpenFolderHotlistDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFolderHotlistAdd:
      begin
        AHost.BeginFolderHotlistAdd();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaWorkspaceLibrary:
      begin
        AHost.OpenWorkspaceLibraryDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaWorkspaceSave:
      begin
        AHost.BeginWorkspaceLibrarySave();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaNewWorkspace:
      begin
        AHost.NewWorkspace();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaNewTab:
      begin
        AHost.NewPanelTab();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaNextPanelTab:
      begin
        AHost.NextPanelTab();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaPrevPanelTab:
      begin
        AHost.PrevPanelTab();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaCloseTab:
      begin
        AHost.ClosePanelTabOnSide(AHost.ActiveSide());
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaSshConnections:
      begin
        AHost.OpenSshConnectionsDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaAssociations:
      begin
        AHost.OpenUserAssociationsDialog();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    // Primary, not function-key dispatch: that runs after Alt quick search,
    // which takes any other Alt+key (Alt+Enter included) as a search letter.
    kaProperties:
      begin
        if Assigned(AHost.ShowProperties) then
          AHost.ShowProperties();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaShellContextMenu:
      begin
        if Assigned(AHost.ShellContextMenu) then
          AHost.ShellContextMenu();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    // Alt+F3 / Alt+F4: same reason as kaProperties.
    kaExternalView:
      begin
        if Assigned(AHost.ExternalView) then
          AHost.ExternalView();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaExternalEdit:
      begin
        if Assigned(AHost.ExternalEdit) then
          AHost.ExternalEdit();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaBranchView:
      begin
        AHost.BeginBranchView();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaLiveFilter:
      begin
        AHost.OpenPanelFilter();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFind:
      begin
        AHost.OpenSearchDialog();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaDirSync:
      begin
        AHost.OpenDirSync();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaJobList:
      begin
        AHost.OpenJobList();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaSyncConsoleDir:
      begin
        AHost.SyncConsoleDirNow();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFolderUp:
      begin
        AHost.GoToParent();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFolderDown:
      begin
        AHost.FolderDown();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFolderTree:
      begin
        AHost.ToggleFolderTree();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaToggleHidden:
      begin
        AHost.ToggleShowHidden(AHost.ActiveSide());
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaColumnMode:
      begin
        AHost.OpenColumnModeMenu();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaColumnBrief:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmBrief);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnSize:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmSize);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnDate:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmDate);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnFull:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmFull);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnCreated:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmCreated);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnTypes:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmTypes);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaColumnCustom:
      begin
        AHost.ApplyColumnMode(AHost.ActiveSide(), pcmCustom);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaInfoPanel:
      begin
        AHost.ToggleAdjacentInfoPanel();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaQuickView:
      begin
        AHost.ToggleQuickView();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaSwapPanels:
      begin
        AHost.SwapPanels();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaEqualizeOtherPanel:
      begin
        AHost.EqualizeOtherPanelToActive();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaEqualizeActivePanel:
      begin
        AHost.EqualizeActivePanelFromOther();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFocusCmdLine:
      begin
        AHost.FocusCommandLine();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaRunDetached:
      begin
        AHost.RunDetached();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaInsertItemName:
      begin
        AHost.InsertPanelItemToCmdLine(False);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaInsertItemPath:
      begin
        AHost.InsertPanelItemToCmdLine(True);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaSelectByMask:
      begin
        AHost.BeginSelectByMask(False);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaUnselectByMask:
      begin
        AHost.BeginSelectByMask(True);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaEditCopy:
      begin
        AHost.EditCopy();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaEditCut:
      begin
        AHost.EditCut();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaEditPaste:
      begin
        AHost.EditPaste();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
  end;
  Result := False;
end;

function DispatchKeymapActionFunctionKeys(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaHelp:
      begin
        AHost.OpenHelp();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaUserMenu:
      begin
        AHost.OpenUserMenu();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaPack:
      begin
        AHost.BeginPackZip();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaUnpack:
      begin
        AHost.BeginUnpackZip();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaView:
      begin
        AHost.OpenViewOrEdit(False);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaEdit:
      begin
        AHost.OpenViewOrEdit(True);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaNewFile:
      begin
        AHost.BeginNewFile();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaCopy:
      begin
        AHost.BeginJob(pjkCopy, True);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaMove:
      begin
        AHost.BeginJob(pjkMove, True);
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaRename:
      begin
        AHost.BeginRename();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaCopyInPlace:
      begin
        AHost.BeginCopyInPlace();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaMkDir:
      begin
        AHost.BeginMkDir();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaCreateLink:
      begin
        AHost.BeginCreateLink();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaSetAttributes:
      begin
        AHost.BeginSetAttributes();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaCompareFiles:
      begin
        AHost.BeginCompareFiles();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaCompareFolders:
      begin
        if Assigned(AHost.CompareFolders) then
          AHost.CompareFolders();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaChecksums:
      begin
        if Assigned(AHost.BeginChecksums) then
          AHost.BeginChecksums();
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaRecycleBin:
      begin
        AHost.NavigateToRecycleBin();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaRestore:
      begin
        AHost.RestoreCursorItemFromRecycleBin();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaDelete:
      begin
        AHost.BeginJob(pjkDelete, True);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaWipe:
      begin
        AHost.BeginJob(pjkDelete, False);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
  end;
  Result := False;
end;

function DispatchPanelNavKeys(const AHost: TDualPanelKeymapHost; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char; AViewH: Integer; ABrief: Boolean;
  APageSize: Integer): Boolean;
var
  K: TKeyChord;
  ShiftNav: Boolean;
begin
  Result := True;
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  // Shift alone extends the selection; any other modifier is not navigation.
  ShiftNav := K.Mods = [ssShift];
  case AKey of
    vkUp:
      if ShiftNav then
        AHost.MoveCursorWithSelect(-1, False)
      else
        AHost.MoveCursor(-1);
    vkDown:
      if ShiftNav then
        AHost.MoveCursorWithSelect(1, False)
      else
        AHost.MoveCursor(1);
    // Brief: one column left / right. Other modes have one column, so Left /
    // Right go to the first / last item, exactly like Home / End (Shift
    // selects up to there).
    vkLeft:
      if not K.HasMods([], [ssShift]) then
        Result := False
      else if ABrief then
      begin
        if ShiftNav then
          AHost.MoveCursorWithSelect(-AViewH, True)
        else
          AHost.MoveCursor(-AViewH);
      end
      else if ShiftNav then
        AHost.MoveCursorWithSelect(-100000, False)
      else
        AHost.MoveCursor(-100000);
    vkRight:
      if not K.HasMods([], [ssShift]) then
        Result := False
      else if ABrief then
      begin
        if ShiftNav then
          AHost.MoveCursorWithSelect(AViewH, True)
        else
          AHost.MoveCursor(AViewH);
      end
      else if ShiftNav then
        AHost.MoveCursorWithSelect(100000, False)
      else
        AHost.MoveCursor(100000);
    vkPrior:
      if ShiftNav then
        AHost.MoveCursorWithSelect(-APageSize, False)
      else
        AHost.MoveCursor(-APageSize);
    vkNext:
      if ShiftNav then
        AHost.MoveCursorWithSelect(APageSize, False)
      else
        AHost.MoveCursor(APageSize);
    vkHome:
      if ShiftNav then
        AHost.MoveCursorWithSelect(-100000, False)
      else
        AHost.MoveCursor(-100000);
    vkEnd:
      if ShiftNav then
        AHost.MoveCursorWithSelect(100000, False)
      else
        AHost.MoveCursor(100000);
    vkInsert:
      begin
        if not K.HasMods([], [ssShift]) then
        begin
          Result := False;
          Exit;
        end;
        AHost.ToggleInsertSelect();
        AKey := 0;
        Exit;
      end;
    vkBack:
      begin
        AHost.FocusCommandLine();
        Result := AHost.HandleCmdLineInput(AKey, AShift, AKeyChar);
        Exit;
      end;
    vkReturn:
      begin
        if K.Mods <> [] then
        begin
          Result := False;
          Exit;
        end;
        AHost.SubmitCommandLine();
        AKey := 0;
        Exit;
      end;
  else
    if K.IsPrintable and K.HasMods([], [ssShift]) then
    begin
      AHost.FocusCommandLine();
      Result := AHost.HandleCmdLineInput(AKey, AShift, AKeyChar);
      Exit;
    end;
    Result := False;
  end;
  if Result then
    AKey := 0;
end;

procedure NormalizePanelInputKey(var AKey: Word; var AKeyChar: Char);
begin
  if (AKey = 0) and (AKeyChar = #9) then
    AKey := vkTab;
  NormalizeEnterKey(AKey, AKeyChar);
end;

function ShouldOfferTopMenu(AWorkspaceKind: TWorkspaceKind;
  ADialogVisible: Boolean): Boolean;
begin
  // Panels, Viewer/Editor, and Terminal share the Dual Panel F9 / row-0 menu.
  // A modal dialog still wins so host F9 cannot steal e.g. color-picker F9.
  Result := (AWorkspaceKind in [wkPanels, wkDocument, wkTerminal]) and
    not ADialogVisible;
end;

function GlobalKeymapAction(const AProfile: TKeymapProfile;
  const AChain: TArray<TKeymapContext>; AKey: Word; AKeyChar: Char;
  AShift: TShiftState; ADialogVisible: Boolean): TKeymapAction;
begin
  // A dialog owns every key: cycling the workspace or opening the console
  // under Rename / Search params would leave it on a panel it no longer
  // matches.
  if ADialogVisible then
    Exit(kaNone);
  Result := MatchGlobalActionIn(AProfile, AChain, AKey, AKeyChar, AShift);
end;

function DispatchGlobalAction(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaHelp:
      AHost.OpenHelp();
    kaNextTab:
      AHost.NextWorkspace();
    kaPrevTab:
      AHost.PrevWorkspace();
    kaNewTerminal:
      AHost.OpenTerminalProfileDialog();
    kaSelectConsoleProfile:
      AHost.OpenConsoleProfileDialog();
    kaAppQuit:
      AHost.RequestQuit();
    kaAppConsoleToggle:
      AHost.ToggleConsole();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function IsContextHelpChord(AKey: Word; AShift: TShiftState;
  ATopMenuActive, ADialogWantsHelp: Boolean): Boolean;
begin
  Result := (ATopMenuActive or ADialogWantsHelp) and
    (MatchActiveActionIn([kcGlobal], AKey, AShift) = kaHelp);
end;

function ClassifyEmbeddedInputOwner(AKind: TWorkspaceKind;
  ADialogVisible, AConsoleMode: Boolean): TEmbeddedInputOwner;
begin
  if (AKind = wkDocument) and not ADialogVisible then
    Exit(eioDocument);
  if (AKind = wkTerminal) and not ADialogVisible then
    Exit(eioTerminal);
  if AConsoleMode and not ADialogVisible then
    Exit(eioConsoleYield);
  Result := eioNone;
end;

function IsPasteChord(AKey: Word; AShift: TShiftState; AKeyChar: Char): Boolean;
var
  K: TKeyChord;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  Result := K.MatchesAny(vkInsert, [ssShift], [ssCtrl]) or
    K.MatchesLetter('V', [ssCtrl], [ssShift]);
end;

function IsAltQuickSearchChord(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := TKeyChord.Make(AKey, #0, AShift).HasMods([ssAlt], [ssShift]) and
    (AKey <> vkF1) and (AKey <> vkF2) and (AKey <> vkF7) and (AKey <> vkF10) and
    (AKey <> vkF12) and (AKey <> vkLeft) and (AKey <> vkRight) and
    (AKey <> vkAdd) and (AKey <> vkSubtract) and (AKey <> vkMultiply) and
    (AKey <> vkEqual) and (AKey <> vkMinus); // OEM +/-
  // Alt+Gray +/-/* arriving as AKey=0 + KeyChar is already vkAdd etc. here
  // (RestoreGrayOpKey runs first).
end;

function QuickSearchMatchIndex(const ARows: TPanelRows; const ANeedle: string): Integer;
var
  I: Integer;
  RowName: string;
  Needle: string;
begin
  Result := -1;
  Needle := AnsiLowerCase(ANeedle);
  if Needle = '' then
    Exit;
  for I := 0 to High(ARows) do
  begin
    if ARows[I].IsParent then
      Continue;
    RowName := ARows[I].Text;
    while (RowName <> '') and ((RowName[Length(RowName)] = '/') or
      (RowName[Length(RowName)] = '\')) do
      Delete(RowName, Length(RowName), 1);
    if (RowName <> '') and (Pos(Needle, AnsiLowerCase(RowName)) = 1) then
      Exit(I);
  end;
end;

function ApplyQuickSearchMatch(var ATab: TTab; const ARows: TPanelRows;
  const ANeedle: string; AViewH, ACols: Integer): Boolean;
var
  MatchIdx: Integer;
begin
  MatchIdx := QuickSearchMatchIndex(ARows, ANeedle);
  Result := MatchIdx >= 0;
  if not Result then
    Exit;
  ATab.CursorIndex := MatchIdx;
  if AViewH < 1 then
    AViewH := 1;
  EnsurePanelCursorVisible(ATab, Length(ARows), AViewH, ACols);
end;

function RecoverPrintableKeyChar(AKey: Word; AKeyChar: Char): Char;
begin
  Result := AKeyChar;
  if (Result < ' ') or (Ord(Result) = 127) then
  begin
    // Letter virtual keys are uppercase only: 'a'..'z' codes are the
    // numpad and F1..F11 keys, not letters.
    case AKey of
      Ord('A')..Ord('Z'),
      Ord('0')..Ord('9'):
        Result := Char(AKey);
    else
      Result := #0;
    end;
  end;
end;

function ClassifyNeedleBoxKey(AKey: Word; AKeyChar: Char;
  out AChar: Char): TNeedleBoxAction;
begin
  AChar := #0;
  if (AKey = vkEscape) or (AKey = vkReturn) then
    Exit(nbaClear);
  if AKey = vkBack then
    Exit(nbaBackspace);
  AChar := RecoverPrintableKeyChar(AKey, AKeyChar);
  if (AChar >= ' ') and (Ord(AChar) <> 127) then
    Exit(nbaAppend);
  Result := nbaUnhandled;
end;

function NeedleBackspace(var AText: string): Boolean;
begin
  Result := Length(AText) > 0;
  if Result then
    Delete(AText, Length(AText), 1);
end;

function KeyCharIsLetter(AKeyChar: Char): Boolean;
begin
  Result := ((AKeyChar >= 'A') and (AKeyChar <= 'Z')) or
    ((AKeyChar >= 'a') and (AKeyChar <= 'z'));
end;

function IsPlusSelectKey(AKey: Word; AKeyChar: Char): Boolean;
begin
  if KeyCharIsLetter(AKeyChar) then
    Exit(False);
  Result := (AKey = vkAdd) or (AKey = vkEqual) or
    (AKeyChar = '+') or (AKeyChar = '=');
end;

function IsMinusSelectKey(AKey: Word; AKeyChar: Char): Boolean;
begin
  if KeyCharIsLetter(AKeyChar) then
    Exit(False);
  Result := (AKey = vkSubtract) or (AKey = vkMinus) or (AKeyChar = '-');
end;

function DispatchPanelFreeInput(const AHost: TDualPanelFreeInputHost;
  const AKeymap: TDualPanelKeymapHost; const ASnap: TPanelFreeInputSnap;
  var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;

  // The keystroke as it is now: RestoreGrayOpKey and the host input handlers
  // may rewrite AKey / AKeyChar on the way down.
  function Chord: TKeyChord;
  begin
    Result := TKeyChord.Make(AKey, AKeyChar, AShift);
  end;

var
  Mods: TShiftState;
begin
  Result := True;
  Mods := AShift * cKeyMods;
  // Command line focused (typing, Ctrl+Down): every key is the command
  // line's, the panel bindings included (- + * deselect / select / invert,
  // F-keys, ...). Esc there clears the text, and on an empty line gives the
  // focus back to the panel; Ctrl+Up does that at once. Esc on the panel is
  // the keymap's (ConsoleToggle by default), text or not.
  if ASnap.CmdFocused then
    Exit(AHost.HandleCmdLineInput(AKey, AShift, AKeyChar));
  if ASnap.DrivePreviewActive and (AKey = vkEscape) then
  begin
    AHost.CancelDrivePreview();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if ASnap.QuickViewVisible and (AKey = vkEscape) then
  begin
    AHost.CloseQuickView();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if AHost.DispatchKeymapPrimary(MatchActiveAction(AKey, AShift), AKey, AKeyChar) then
    Exit;
  // Backspace with an empty command line: up one level, like Enter on "..".
  // With text in it, Backspace edits the command line (DispatchPanelNavKeys).
  if Chord.Matches(vkBack) and not ASnap.CmdLineHasText and Assigned(AHost.GoToParent) then
  begin
    AHost.GoToParent();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  // Ctrl+Shift+Left/Right with text in the command line select word parts
  // there instead of cycling the drive preview.
  if (Chord.Matches(vkLeft, [ssCtrl, ssShift]) or Chord.Matches(vkRight, [ssCtrl, ssShift])) and
     (ASnap.CmdFocused or ASnap.CmdLineHasText) then
  begin
    if not ASnap.CmdFocused and Assigned(AHost.FocusCommandLine) then
      AHost.FocusCommandLine();
    Exit(AHost.HandleCmdLineInput(AKey, AShift, AKeyChar));
  end;
  if Chord.HasMods([ssCtrl], [ssShift]) then
  begin
    if AKey = vkLeft then
    begin
      AHost.PreviewCycleDrive(-1);
      ConsumeKey(AKey, AKeyChar, False);
      Exit;
    end;
    if AKey = vkRight then
    begin
      AHost.PreviewCycleDrive(+1);
      ConsumeKey(AKey, AKeyChar, False);
      Exit;
    end;
    if (AKey = vkBackslash) or (AKeyChar = '\') then
    begin
      AHost.NavigateActiveToDriveRoot();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if IsPasteChord(AKey, AShift, AKeyChar) then
  begin
    if AHost.TryPasteClipboard() then
    begin
      ConsumeKey(AKey, AKeyChar, True);
      Exit(True);
    end;
  end;
  AHost.RestoreGrayOpKey(AKey, AKeyChar);
  if Mods = [] then
  begin
    if AKey = vkAdd then
    begin
      AHost.BeginSelectByMask(False);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if AKey = vkSubtract then
    begin
      AHost.BeginSelectByMask(True);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if AKey = vkMultiply then
    begin
      AHost.InvertSelectionActive();
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if Chord.HasMods([ssCtrl], [ssShift]) then
  begin
    if IsPlusSelectKey(AKey, AKeyChar) then
    begin
      AHost.ApplySelectByExtension(False);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if IsMinusSelectKey(AKey, AKeyChar) then
    begin
      AHost.ApplySelectByExtension(True);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if Mods = [ssShift] then
  begin
    if AKey = vkAdd then
    begin
      AHost.ApplySelectAllFiles(False);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if AKey = vkSubtract then
    begin
      AHost.ApplySelectAllFiles(True);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if Mods = [ssAlt] then
  begin
    if (AKey = vkAdd) or (AKeyChar = '+') then
    begin
      if Assigned(AHost.ApplySelectByName) then
        AHost.ApplySelectByName(False);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
    if (AKey = vkSubtract) or (AKeyChar = '-') then
    begin
      if Assigned(AHost.ApplySelectByName) then
        AHost.ApplySelectByName(True);
      ConsumeKey(AKey, AKeyChar, True);
      Exit;
    end;
  end;
  if IsAltQuickSearchChord(AKey, AShift) then
  begin
    if AHost.HandleQuickSearchInput(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKey = vkTab then
  begin
    if Mods <> [] then
    begin
      Result := False;
      Exit;
    end;
    AHost.SwitchSide();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if AHost.TryHotlistJump(AKey, AShift, AKeyChar) then
    Exit;
  if AHost.DispatchKeymapFunctionKeys(MatchActiveAction(AKey, AShift), AKey, AKeyChar) then
    Exit;
  if Chord.Matches(vkNumpad5) or Chord.Matches(vkClear) then
  begin
    AHost.OpenViewOrEdit(False);
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  Result := DispatchPanelNavKeys(AKeymap, AKey, AShift, AKeyChar, ASnap.ViewH,
    ASnap.Brief, ASnap.PageSize);
end;

function DispatchModalDialogInput(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  DialogCmdId: string;
  Record_: TDialogIdProc;
  Command: TDialogCmdProc;
  Run: TProc;
begin
  // Before the generic Enter: Ctrl+Enter there is "show in panel", not OK.
  if (AKind = hdkFileHistory) and Assigned(AHost.HandleFileHistoryList) and
     AHost.HandleFileHistoryList(AKey, AShift, AKeyChar) then
    Exit(True);
  if (AKey = vkReturn) and (AKind = hdkJobProgress) then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit(True);
  end;
  if (AKey = vkReturn) and (AKind <> hdkNone) and
     not (Assigned(AHost.DialogDropDownOpen) and AHost.DialogDropDownOpen()) then
  begin
    DialogCmdId := AHost.FocusedOrDefaultButtonId();
    if DialogCmdId = '' then
      DialogCmdId := cDlgCmdOk;
    // Bypasses TDialogHost.FireCommand, which would record the history.
    Record_ := AHost.RecordDialogHistory;
    Command := AHost.DialogCommand;
    Run :=
      procedure
      begin
        if Assigned(Record_) then
          Record_(DialogCmdId);
        Command(DialogCmdId, '');
      end;
    if Assigned(AHost.PressDialogButton) then
      AHost.PressDialogButton(DialogCmdId, Run)
    else
      Run();
    ConsumeKey(AKey, AKeyChar, True);
    Exit(True);
  end;
  if AKind = hdkFolderHotlist then
  begin
    if Assigned(AHost.HandleHotlistList) and
       AHost.HandleHotlistList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkWorkspaceLibrary then
  begin
    if Assigned(AHost.HandleWorkspaceList) and
       AHost.HandleWorkspaceList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkSshConnections then
  begin
    if Assigned(AHost.HandleSshConnectionsList) and
       AHost.HandleSshConnectionsList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkAssociations then
  begin
    if Assigned(AHost.HandleAssociationsList) and
       AHost.HandleAssociationsList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkColorCoding then
  begin
    if AHost.HandleColorList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkColorCodingEdit then
  begin
    if AHost.HandleColorEdit(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if AKind = hdkKeymap then
  begin
    if AHost.HandleKeymapList(AKey, AShift, AKeyChar) then
      Exit(True);
  end;
  if (AKind = hdkCmdHistory) and
     AHost.HandleCmdHistoryFilter(AKey, AShift, AKeyChar) then
    Exit(True);
  Result := AHost.HandleDialogWidget(AKey, AShift, AKeyChar);
  if AKind = hdkColorPicker then
    AHost.SyncColorPickerHex();
end;

end.
