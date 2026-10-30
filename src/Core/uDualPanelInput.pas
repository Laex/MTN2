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
  TKeymapCharFn = function(AKeyChar: Char; AShift: TShiftState): Boolean of object;

  /// <summary>Method-pointer sink for HandleKeymapAction* dispatch. Bound once
  /// by TDualPanelWindow so the case tables can live here without pulling the
  /// window unit back in.</summary>
  TDualPanelKeymapHost = record
    ActiveSide: TKeymapSideFn;
    CopyFullPathToClipboard: TKeymapProc;
    CopyItemNameToClipboard: TKeymapProc;
    ExportItemList: TKeymapProc;
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
    OpenCommandPalette: TKeymapProc;
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
    CursorToSameNameInOtherPanel: TKeymapProc;
    FocusCommandLine: TKeymapProc;
    ClearCommandLine: TKeymapProc;
    RunDetached: TKeymapProc;
    RunInBackground: TKeymapProc;
    RunInNewTab: TKeymapProc;
    InsertPanelItemToCmdLine: TKeymapBoolProc;
    InsertPanelPathToCmdLine: TKeymapBoolProc;
    BeginSelectByMask: TKeymapBoolProc;
    ApplySelectByExtension: TKeymapBoolProc;
    OpenHelp: TKeymapProc;
    OpenUserMenu: TKeymapProc;
    BeginPackZip: TKeymapProc;
    BeginUnpackZip: TKeymapProc;
    OpenViewOrEdit: TKeymapBoolProc;
    BeginNewFile: TKeymapProc;
    BeginJob: TKeymapJobProc;
    BeginDeleteCursor: TKeymapProc;
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
    OpenConsoleOptionsDialog: TKeymapProc;
    BeginSaveConsoleOutput: TKeymapProc;
    SaveSettings: TKeymapProc;
    BeginExportSettings: TKeymapProc;
    BeginImportSettings: TKeymapProc;
    BeginConfigLocation: TKeymapProc;
    OpenEnvironmentProfiles: TKeymapProc;
    ClearConsoleBuffer: TKeymapProc;
    OpenMarkdownColorsDialog: TKeymapProc;
    BeginChecksums: TKeymapProc;
    BeginMultiRename: TKeymapProc;
    NavigateToRecycleBin: TKeymapProc;
    RestoreCursorItemFromRecycleBin: TKeymapProc;
    ActivateSide: TKeymapSideProc;
    NewPanelTab: TKeymapProc;
    NextPanelTab: TKeymapProc;
    PrevPanelTab: TKeymapProc;
    RestoreSelection: TKeymapProc;
    DescribeItems: TKeymapProc;
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
    OpenInterfaceDialog: TKeymapProc;
    OpenAboutDialog: TKeymapProc;
    OpenUpdates: TKeymapProc;
    RestoreHiddenDialogs: TKeymapProc;
    EditGotoLine: TKeymapProc;
    EditFind: TKeymapProc;
    EditFindReplace: TKeymapProc;
    EditEncoding: TKeymapProc;
    EditUndo: TKeymapProc;
    EditRedo: TKeymapProc;
    EditHexToggle: TKeymapProc;
    EditSortLines: TKeymapProc;
    EditSortLinesDesc: TKeymapProc;
    EditUniqueLines: TKeymapProc;
    EditReflow: TKeymapProc;
    EditShiftRight: TKeymapProc;
    EditShiftLeft: TKeymapProc;
    EditBookmarkToggle: TKeymapProc;
    EditBookmarkNext: TKeymapProc;
    EditBookmarkPrev: TKeymapProc;
    EditBookmarkList: TKeymapProc;
    EditAutoIndent: TKeymapProc;
    EditCopy: TKeymapProc;
    EditCut: TKeymapProc;
    EditPaste: TKeymapProc;
    NavigateActiveToDriveRoot: TKeymapProc;
    RefreshActive: TKeymapProc;
    SelectAllActive: TKeymapProc;
    UnselectAllActive: TKeymapProc;
    InvertSelectionActive: TKeymapProc;
    MoveCursor: TKeymapDeltaProc;
    MoveCursorWithSelect: TKeymapSelectDeltaProc;
    ToggleInsertSelect: TKeymapProc;
    SubmitCommandLine: TKeymapProc;
    /// <summary>Space selects the file under the cursor (when enabled and the
    /// command line is empty); True = the key was used.</summary>
    TrySpaceSelect: TKeymapCharFn;
    /// <summary>True = typing on the panel goes into the command line without
    /// moving the focus there (Ctrl+Down and a click still do). Nil = the
    /// focus moves.</summary>
    KeepPanelFocus: TFunc<Boolean>;
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
    ApplySelectByExtension: TKeymapBoolProc;
    ApplySelectByName: TKeymapBoolProc;
    HandleQuickSearchInput: TKeymapInputFn;
    HandleCmdLineInput: TKeymapInputFn;
    FocusCommandLine: TKeymapProc;
    /// <summary>Esc on the panel with text left in the command line.</summary>
    ClearCommandLine: TKeymapProc;
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
    HandleTerminalProfileList: TKeymapInputFn;
    HandleAssociationsList: TKeymapInputFn;
    HandleColorList: TKeymapInputFn;
    HandleColorEdit: TKeymapInputFn;
    HandleSearchEdit: TKeymapInputFn;
    HandleKeymapList: TKeymapInputFn;
    HandleCmdHistoryFilter: TKeymapInputFn;
    HandleCommandPaletteFilter: TKeymapInputFn;
    HandleFileHistoryList: TKeymapInputFn;
    HandleFolderHistoryList: TKeymapInputFn;
    HandleDialogWidget: TKeymapInputFn;
    HandleMarkdownColors: TKeymapInputFn;
    HandleThemeColor: TKeymapInputFn;
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

type
  /// <summary>What the host does with a key before an open top menu sees it.</summary>
  TTopMenuKeyKind = (tmkSkip, tmkClose, tmkOpen, tmkPalette, tmkForward);

  TTopMenuKeyOffer = record
    Kind: TTopMenuKeyKind;
    /// <summary>tmkForward only: Alt was released, so plugin items must be
    /// loaded before the menu handles the key.</summary>
    PreloadPlugins: Boolean;
  end;

/// <summary>F9 toggles the bar, Shift+F9 opens the command palette, and an
/// Alt release on a closed menu loads plugin items first. Anything else is
/// forwarded to the open bar. AProgramKeys or not AShouldOffer skips the
/// menu, so a modal dialog keeps its own F9.</summary>
function ClassifyTopMenuKey(AHasMenu, AProgramKeys, AShouldOffer, AMenuActive: Boolean;
  AChordAction, AGlobalAct: TKeymapAction; AShift: TShiftState;
  AKey: Word; AKeyChar: Char): TTopMenuKeyOffer;
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

type
  /// <summary>A panel chord handled before free input.</summary>
  TPanelLocalChord = (plcNone, plcTmpGotoFile, plcTmpSave, plcTmpOpposite,
    plcWorkspaceOpposite);

/// <summary>Chords the panels take while the command line is not focused.
/// A temporary panel: Ctrl+PageUp jumps to the cursor file, Alt+Shift+F2
/// saves the list, Alt+Shift+F3 shows it on the opposite panel. Any other
/// panel: Alt+Shift+F3 reveals the cursor item opposite, including after
/// entering a workspace dir-link (its URI is then a plain file URI). A
/// focused command line takes none of these.</summary>
function ClassifyPanelLocalChord(ATmpPanel, ACmdFocused: Boolean;
  AKey: Word; AKeyChar: Char; AShift: TShiftState): TPanelLocalChord;
/// <summary>Contexts searched before kcGlobal. A document uses its own chain,
/// or kcDocument when it has none yet. A terminal is terminal then shell.
/// Panels in console mode are console then shell; otherwise the file panels.
/// Console mode does not change a document or a terminal.</summary>
function GlobalLookupChain(AKind: TWorkspaceKind; AConsoleMode, AHasDocument: Boolean;
  const ADocumentChain: TArray<TKeymapContext>): TArray<TKeymapContext>;
/// <summary>While the console or terminal has the keys, the host keeps only
/// the actions that leave it (IsKeyboardCaptureExitAction). The rest,
/// including the menu and help, go to the program.</summary>
function ApplyProgramKeyCapture(AAction: TKeymapAction; AProgramKeys: Boolean): TKeymapAction;
function IsPasteChord(AKey: Word; AShift: TShiftState; AKeyChar: Char): Boolean;

var
  /// <summary>Set by the text terminal host: switches the terminal's mouse
  /// reporting off and on, so that the terminal itself can select text.
  /// nil in the other hosts, where the key and the menu item do nothing.</summary>
  GToggleMouseCapture: TProc = nil;

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
  uKeyChord, uCommandRegistry;

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
    kaDelete, kaWipe, kaDeletePermanent: Exit(iaDelete);
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

function SortColumnOf(AAction: TKeymapAction; out AColumn: TPanelSortColumn): Boolean;
begin
  Result := True;
  case AAction of
    kaSortByName: AColumn := pscName;
    kaSortByExt: AColumn := pscExt;
    kaSortByDate: AColumn := pscModified;
    kaSortBySize: AColumn := pscSize;
    kaSortUnsorted: AColumn := pscNone;
    kaSortByCreated: AColumn := pscCreated;
    kaSortByAccessed: AColumn := pscAccessed;
  else
    begin
      AColumn := pscNone;
      Result := False;
    end;
  end;
end;

function ColumnModeOf(AAction: TKeymapAction; out AMode: TPanelColumnMode): Boolean;
begin
  // kaColumnMode opens the menu; it is not one of these modes.
  Result := True;
  case AAction of
    kaColumnBrief: AMode := pcmBrief;
    kaColumnSize: AMode := pcmSize;
    kaColumnDate: AMode := pcmDate;
    kaColumnFull: AMode := pcmFull;
    kaColumnCreated: AMode := pcmCreated;
    kaColumnTypes: AMode := pcmTypes;
    kaColumnCustom: AMode := pcmCustom;
  else
    begin
      AMode := pcmBrief;
      Result := False;
    end;
  end;
end;

function ToggledPanelSide(AAction: TKeymapAction; out ASide: TPanelSide): Boolean;
begin
  Result := True;
  case AAction of
    kaTogglePanelLeft: ASide := psLeft;
    kaTogglePanelRight: ASide := psRight;
  else
    begin
      ASide := psLeft;
      Result := False;
    end;
  end;
end;

function DrivePopupSide(AAction: TKeymapAction; out ASide: TPanelSide): Boolean;
begin
  Result := True;
  case AAction of
    kaDriveLeft: ASide := psLeft;
    kaDriveRight: ASide := psRight;
  else
    begin
      ASide := psLeft;
      Result := False;
    end;
  end;
end;

function ApplyCmdInsert(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaInsertItemName: AHost.InsertPanelItemToCmdLine(False);
    kaInsertItemPath: AHost.InsertPanelItemToCmdLine(True);
    kaInsertPanelPath: AHost.InsertPanelPathToCmdLine(False);
    kaInsertOtherPanelPath: AHost.InsertPanelPathToCmdLine(True);
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function MaskSelectOf(AAction: TKeymapAction; out AUnselect: Boolean): Boolean;
begin
  Result := True;
  case AAction of
    kaSelectByMask: AUnselect := False;
    kaUnselectByMask: AUnselect := True;
  else
    begin
      AUnselect := False;
      Result := False;
    end;
  end;
end;

function ApplyHistoryStep(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaHistoryBack: AHost.HistoryBack();
    kaHistoryForward: AHost.HistoryForward();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function ApplyPanelTab(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaNewTab: AHost.NewPanelTab();
    kaNextPanelTab: AHost.NextPanelTab();
    kaPrevPanelTab: AHost.PrevPanelTab();
    kaCloseTab: AHost.ClosePanelTabOnSide(AHost.ActiveSide());
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplySelection(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaSelectAll: AHost.SelectAllActive();
    kaUnselectAll: AHost.UnselectAllActive();
    kaInvertSelection: AHost.InvertSelectionActive();
    kaRestoreSelection: AHost.RestoreSelection();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyRun(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaRunDetached: AHost.RunDetached();
    kaRunInBackground: AHost.RunInBackground();
    kaRunInNewTab: AHost.RunInNewTab();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyEditClip(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaEditCopy: AHost.EditCopy();
    kaEditCut: AHost.EditCut();
    kaEditPaste: AHost.EditPaste();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function TryOptionalShellAction(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction): Boolean;
begin
  // Primary, not function-key dispatch: that runs after Alt quick search,
  // which takes any other Alt+key (Alt+Enter included) as a search letter.
  // Alt+F3 / Alt+F4 are the same.
  Result := True;
  case AAction of
    kaProperties:
      if Assigned(AHost.ShowProperties) then
        AHost.ShowProperties();
    kaShellContextMenu:
      if Assigned(AHost.ShellContextMenu) then
        AHost.ShellContextMenu();
    kaExternalView:
      if Assigned(AHost.ExternalView) then
        AHost.ExternalView();
    kaExternalEdit:
      if Assigned(AHost.ExternalEdit) then
        AHost.ExternalEdit();
  else
    Result := False;
  end;
end;

function ApplyHistoryDialog(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaFolderHistory: AHost.OpenFolderHistoryDialog();
    kaFileHistory: AHost.OpenFileHistoryDialog();
    kaCmdHistory: AHost.OpenCmdHistoryDialog();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyHotlist(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaFolderHotlist: AHost.OpenFolderHotlistDialog();
    kaFolderHotlistAdd: AHost.BeginFolderHotlistAdd();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyWorkspace(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaWorkspaceLibrary: AHost.OpenWorkspaceLibraryDialog();
    kaWorkspaceSave: AHost.BeginWorkspaceLibrarySave();
    kaNewWorkspace: AHost.NewWorkspace();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyFolderNav(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaFolderUp: AHost.GoToParent();
    kaFolderDown: AHost.FolderDown();
    kaFolderTree: AHost.ToggleFolderTree();
    kaToggleHidden: AHost.ToggleShowHidden(AHost.ActiveSide());
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyPanelLayout(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaInfoPanel: AHost.ToggleAdjacentInfoPanel();
    kaQuickView: AHost.ToggleQuickView();
    kaSwapPanels: AHost.SwapPanels();
    kaEqualizeOtherPanel: AHost.EqualizeOtherPanelToActive();
    kaEqualizeActivePanel: AHost.EqualizeActivePanelFromOther();
    kaCursorToSameName: AHost.CursorToSameNameInOtherPanel();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyClipboardCopy(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaCopyFullPath:
      AHost.CopyFullPathToClipboard();
    kaCopyItemName:
      if Assigned(AHost.CopyItemNameToClipboard) then
        AHost.CopyItemNameToClipboard();
    kaExportList:
      if Assigned(AHost.ExportItemList) then
        AHost.ExportItemList();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyPanelTool(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaDescribe: AHost.DescribeItems();
    kaSshConnections: AHost.OpenSshConnectionsDialog();
    kaAssociations: AHost.OpenUserAssociationsDialog();
    kaBranchView: AHost.BeginBranchView();
    kaLiveFilter: AHost.OpenPanelFilter();
    kaDirSync: AHost.OpenDirSync();
    kaJobList: AHost.OpenJobList();
    kaSyncConsoleDir: AHost.SyncConsoleDirNow();
    kaColumnMode: AHost.OpenColumnModeMenu();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, True);
end;

function ApplyCmdLine(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  // Focusing the line leaves the character. Clearing it removes the character.
  Result := True;
  case AAction of
    kaFocusCmdLine:
      begin
        AHost.FocusCommandLine();
        ConsumeKey(AKey, AKeyChar, False);
      end;
    kaClearCmdLine:
      begin
        AHost.ClearCommandLine();
        ConsumeKey(AKey, AKeyChar, True);
      end;
  else
    Result := False;
  end;
end;

function ApplySession(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  // The console toggle clears the character. Quit leaves it.
  Result := True;
  case AAction of
    kaConsoleToggle:
      begin
        AHost.ToggleConsole();
        ConsumeKey(AKey, AKeyChar, True);
      end;
    kaQuit:
      begin
        AHost.RequestQuit();
        ConsumeKey(AKey, AKeyChar, False);
      end;
  else
    Result := False;
  end;
end;

function DispatchKeymapActionPrimary(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
var
  SortColumn: TPanelSortColumn;
  ColumnMode: TPanelColumnMode;
  Side: TPanelSide;
  Unselect: Boolean;
begin
  // The panels look keys up in Panels, then Global: the Global ones run as
  // they do from any window.
  if DispatchGlobalAction(AHost, AAction, AKey, AKeyChar) then
    Exit(True);
  Result := True;
  if SortColumnOf(AAction, SortColumn) then
  begin
    AHost.ApplySortMode(AHost.ActiveSide(), SortColumn);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if ColumnModeOf(AAction, ColumnMode) then
  begin
    AHost.ApplyColumnMode(AHost.ActiveSide(), ColumnMode);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if ToggledPanelSide(AAction, Side) then
  begin
    AHost.TogglePanelVisible(Side);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if DrivePopupSide(AAction, Side) then
  begin
    AHost.ToggleDrivePopup(Side);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if ApplyCmdInsert(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if MaskSelectOf(AAction, Unselect) then
  begin
    AHost.BeginSelectByMask(Unselect);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if ApplyHistoryStep(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyPanelTab(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplySelection(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyRun(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyEditClip(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if TryOptionalShellAction(AHost, AAction) then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if ApplyClipboardCopy(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyHistoryDialog(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyHotlist(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyWorkspace(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyFolderNav(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyPanelLayout(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyPanelTool(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyCmdLine(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplySession(AHost, AAction, AKey, AKeyChar) then
    Exit;
  case AAction of
    kaSortMenu:
      begin
        AHost.OpenSortMenu();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
    kaTogglePassivePanel:
      begin
        if AHost.ActiveSide() = psLeft then
          AHost.TogglePanelVisible(psRight)
        else
          AHost.TogglePanelVisible(psLeft);
        ConsumeKey(AKey, AKeyChar, True);
        Exit;
      end;
    kaFind:
      begin
        AHost.OpenSearchDialog();
        ConsumeKey(AKey, AKeyChar, False);
        Exit;
      end;
  end;
  Result := False;
end;

function ViewOrEditOf(AAction: TKeymapAction; out AEdit, AClearChar: Boolean): Boolean;
begin
  // View clears the typed character. Edit leaves it.
  Result := True;
  case AAction of
    kaView:
      begin
        AEdit := False;
        AClearChar := True;
      end;
    kaEdit:
      begin
        AEdit := True;
        AClearChar := False;
      end;
  else
    begin
      AEdit := False;
      AClearChar := False;
      Result := False;
    end;
  end;
end;

function TransferJobOf(AAction: TKeymapAction; out AKind: TPanelJobKind): Boolean;
begin
  Result := True;
  case AAction of
    kaCopy: AKind := pjkCopy;
    kaMove: AKind := pjkMove;
  else
    begin
      AKind := pjkCopy;
      Result := False;
    end;
  end;
end;

function ApplyArchive(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaPack: AHost.BeginPackZip();
    kaUnpack: AHost.BeginUnpackZip();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function ApplyFileBegin(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaNewFile: AHost.BeginNewFile();
    kaRename: AHost.BeginRename();
    kaCopyInPlace: AHost.BeginCopyInPlace();
    kaMkDir: AHost.BeginMkDir();
    kaCreateLink: AHost.BeginCreateLink();
    kaSetAttributes: AHost.BeginSetAttributes();
    kaCompareFiles: AHost.BeginCompareFiles();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function TryOptionalTool(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction): Boolean;
begin
  Result := True;
  case AAction of
    kaCompareFolders:
      if Assigned(AHost.CompareFolders) then
        AHost.CompareFolders();
    kaChecksums:
      if Assigned(AHost.BeginChecksums) then
        AHost.BeginChecksums();
    kaMultiRename:
      if Assigned(AHost.BeginMultiRename) then
        AHost.BeginMultiRename();
  else
    Result := False;
  end;
end;

function ApplyHelpOrUserMenu(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaHelp: AHost.OpenHelp();
    kaUserMenu: AHost.OpenUserMenu();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function ApplyRecycleBin(const AHost: TDualPanelKeymapHost; AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := True;
  case AAction of
    kaRecycleBin: AHost.NavigateToRecycleBin();
    kaRestore: AHost.RestoreCursorItemFromRecycleBin();
  else
    Exit(False);
  end;
  ConsumeKey(AKey, AKeyChar, False);
end;

function DeleteJobOf(AAction: TKeymapAction; out ARecycle: Boolean): Boolean;
begin
  Result := True;
  case AAction of
    kaDelete: ARecycle := True;
    kaDeletePermanent: ARecycle := False;
  else
    begin
      ARecycle := True;
      Result := False;
    end;
  end;
end;

function DispatchKeymapActionFunctionKeys(const AHost: TDualPanelKeymapHost;
  AAction: TKeymapAction; var AKey: Word; var AKeyChar: Char): Boolean;
var
  Edit, ClearChar, Recycle: Boolean;
  Job: TPanelJobKind;
begin
  Result := True;
  if ViewOrEditOf(AAction, Edit, ClearChar) then
  begin
    AHost.OpenViewOrEdit(Edit);
    ConsumeKey(AKey, AKeyChar, ClearChar);
    Exit;
  end;
  if TransferJobOf(AAction, Job) then
  begin
    AHost.BeginJob(Job, True);
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  if DeleteJobOf(AAction, Recycle) then
  begin
    AHost.BeginJob(pjkDelete, Recycle);
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if ApplyArchive(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyFileBegin(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if TryOptionalTool(AHost, AAction) then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if ApplyHelpOrUserMenu(AHost, AAction, AKey, AKeyChar) then
    Exit;
  if ApplyRecycleBin(AHost, AAction, AKey, AKeyChar) then
    Exit;
  case AAction of
    kaWipe:
      begin
        if Assigned(AHost.BeginDeleteCursor) then
          AHost.BeginDeleteCursor();
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
        if not (Assigned(AHost.KeepPanelFocus) and AHost.KeepPanelFocus()) then
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
      // Selecting with Space must not move the focus to the command line.
      if Assigned(AHost.TrySpaceSelect) and AHost.TrySpaceSelect(AKeyChar, AShift) then
      begin
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
      if not (Assigned(AHost.KeepPanelFocus) and AHost.KeepPanelFocus()) then
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

function ClassifyTopMenuKey(AHasMenu, AProgramKeys, AShouldOffer, AMenuActive: Boolean;
  AChordAction, AGlobalAct: TKeymapAction; AShift: TShiftState;
  AKey: Word; AKeyChar: Char): TTopMenuKeyOffer;
begin
  Result.Kind := tmkSkip;
  Result.PreloadPlugins := False;
  if not (AHasMenu and not AProgramKeys and AShouldOffer) then
    Exit;
  // F9 closes the bar before it can be read as "open".
  if AMenuActive and (AChordAction = kaTopMenu) then
  begin
    Result.Kind := tmkClose;
    Exit;
  end;
  if not AMenuActive and (AGlobalAct = kaTopMenu) then
  begin
    Result.Kind := tmkOpen;
    Exit;
  end;
  if not AMenuActive and (AGlobalAct = kaCommandPalette) then
  begin
    Result.Kind := tmkPalette;
    Exit;
  end;
  Result.Kind := tmkForward;
  Result.PreloadPlugins := not AMenuActive and (ssAlt in AShift) and
    (AKey = 0) and (AKeyChar = #0);
end;

function GlobalKeymapAction(const AProfile: TKeymapProfile;
  const AChain: TArray<TKeymapContext>; AKey: Word; AKeyChar: Char;
  AShift: TShiftState; ADialogVisible: Boolean): TKeymapAction;
begin
  // A dialog owns every key: cycling the workspace or opening the console
  // under Rename / Search params would leave it on a panel it does not
  // match.
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
    kaToggleMouse:
      begin
        if not Assigned(GToggleMouseCapture) then
          Exit(False);
        GToggleMouseCapture();
      end;
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

function ClassifyPanelLocalChord(ATmpPanel, ACmdFocused: Boolean;
  AKey: Word; AKeyChar: Char; AShift: TShiftState): TPanelLocalChord;
var
  K: TKeyChord;
begin
  Result := plcNone;
  if ACmdFocused then
    Exit;
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  if ATmpPanel then
  begin
    if K.Matches(vkPrior, [ssCtrl]) then
      Exit(plcTmpGotoFile);
    if K.HasMods([ssAlt, ssShift]) then
    begin
      if AKey = vkF2 then
        Exit(plcTmpSave);
      if AKey = vkF3 then
        Exit(plcTmpOpposite);
    end;
    Exit;
  end;
  if K.Matches(vkF3, [ssAlt, ssShift]) then
    Result := plcWorkspaceOpposite;
end;

function GlobalLookupChain(AKind: TWorkspaceKind; AConsoleMode, AHasDocument: Boolean;
  const ADocumentChain: TArray<TKeymapContext>): TArray<TKeymapContext>;
begin
  case AKind of
    wkDocument:
      if AHasDocument then
        Result := ADocumentChain
      else
        Result := [kcDocument];
    wkTerminal:
      Result := [kcTerminal, kcShell];
  else
    if AConsoleMode then
      Result := [kcConsole, kcShell]
    else
      Result := [kcPanels];
  end;
end;

function ApplyProgramKeyCapture(AAction: TKeymapAction; AProgramKeys: Boolean): TKeymapAction;
begin
  if AProgramKeys and not IsKeyboardCaptureExitAction(AAction) then
    Result := kaNone
  else
    Result := AAction;
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

function FreeInputPrefix(const AHost: TDualPanelFreeInputHost;
  const ASnap: TPanelFreeInputSnap; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; out AAct: TKeymapAction; out AResult: Boolean): Boolean;
begin
  AAct := kaNone;
  AResult := True;
  Result := True;
  // Command line focused (typing, Ctrl+Down): every key is the command
  // line's, the panel bindings included (- + * deselect / select / invert,
  // F-keys, ...). Esc there clears the text, and on an empty line gives the
  // focus back to the panel; Ctrl+Up does that at once. Esc on the panel is
  // the keymap's (ConsoleToggle by default), text or not. Enter with a
  // modifier (insert name / path, detached / background / new-tab run,
  // properties) is the panel's chord, handled as on the panel.
  if ASnap.CmdFocused and not ((AKey = vkReturn) and (AShift * cKeyMods <> [])) then
  begin
    AResult := AHost.HandleCmdLineInput(AKey, AShift, AKeyChar);
    Exit;
  end;
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
  // Esc on the panel: text left in the command line goes first; the next Esc
  // is the keymap's (the console).
  if (AKey = vkEscape) and (AShift * cKeyMods = []) and ASnap.CmdLineHasText and
     Assigned(AHost.ClearCommandLine) then
  begin
    AHost.ClearCommandLine();
    ConsumeKey(AKey, AKeyChar, False);
    Exit;
  end;
  // Plugin hooks on built-in commands, and plugin commands bound to a chord no
  // built-in action owns, come before the built-in handlers.
  AAct := MatchActiveAction(AKey, AShift);
  if (AAct <> kaNone) and InterceptKeymapAction(AAct, 'key') then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if (AAct = kaNone) and TryRunBoundCommand(KeymapLookupKey(AKey, AKeyChar), AShift) then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  Result := False;
end;

function OfferDriveChords(const AHost: TDualPanelFreeInputHost;
  const ASnap: TPanelFreeInputSnap; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; out AResult: Boolean): Boolean;
var
  Chord: TKeyChord;
begin
  AResult := True;
  Result := True;
  Chord := TKeyChord.Make(AKey, AKeyChar, AShift);
  // Ctrl+Shift+Left/Right with text in the command line select word parts
  // there instead of cycling the drive preview.
  if (Chord.Matches(vkLeft, [ssCtrl, ssShift]) or Chord.Matches(vkRight, [ssCtrl, ssShift])) and
     (ASnap.CmdFocused or ASnap.CmdLineHasText) then
  begin
    if not ASnap.CmdFocused and Assigned(AHost.FocusCommandLine) then
      AHost.FocusCommandLine();
    AResult := AHost.HandleCmdLineInput(AKey, AShift, AKeyChar);
    Exit;
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
  Result := False;
end;

function OfferSelectChords(const AHost: TDualPanelFreeInputHost;
  var AKey: Word; AShift: TShiftState; var AKeyChar: Char;
  const AMods: TShiftState): Boolean;
var
  Chord: TKeyChord;
begin
  Result := True;
  Chord := TKeyChord.Make(AKey, AKeyChar, AShift);
  if AMods = [] then
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
  if AMods = [ssAlt] then
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
  Result := False;
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
  Act: TKeymapAction;
  Step: Boolean;
begin
  Result := True;
  Mods := AShift * cKeyMods;
  if FreeInputPrefix(AHost, ASnap, AKey, AShift, AKeyChar, Act, Step) then
    Exit(Step);
  if AHost.DispatchKeymapPrimary(Act, AKey, AKeyChar) then
    Exit;
  // Backspace with an empty command line: up one level, like Enter on "..".
  // With text in it, Backspace edits the command line (DispatchPanelNavKeys).
  if Chord.Matches(vkBack) and not ASnap.CmdLineHasText and Assigned(AHost.GoToParent) then
  begin
    AHost.GoToParent();
    ConsumeKey(AKey, AKeyChar, True);
    Exit;
  end;
  if OfferDriveChords(AHost, ASnap, AKey, AShift, AKeyChar, Step) then
    Exit(Step);
  if IsPasteChord(AKey, AShift, AKeyChar) then
  begin
    if AHost.TryPasteClipboard() then
    begin
      ConsumeKey(AKey, AKeyChar, True);
      Exit(True);
    end;
  end;
  AHost.RestoreGrayOpKey(AKey, AKeyChar);
  if OfferSelectChords(AHost, AKey, AShift, AKeyChar, Mods) then
    Exit;
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

function JobProgressEnterSwallowed(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; AKey: Word): Boolean;
begin
  // Enter presses the focused Background or Cancel like a click (Cancel only
  // asks whether to stop). With no such button focused it is swallowed, so
  // it never acts on the job by accident.
  Result := (AKey = vkReturn) and (AKind = hdkJobProgress) and
    not (Assigned(AHost.FocusedOrDefaultButtonId) and
         (DialogCmdIs(AHost.FocusedOrDefaultButtonId(), cDlgCmdBackground) or
          DialogCmdIsCancel(AHost.FocusedOrDefaultButtonId())));
end;

function ModalKindTookKey(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  case AKind of
    hdkFileHistory:
      Result := Assigned(AHost.HandleFileHistoryList) and
        AHost.HandleFileHistoryList(AKey, AShift, AKeyChar);
    hdkFolderHistory:
      Result := Assigned(AHost.HandleFolderHistoryList) and
        AHost.HandleFolderHistoryList(AKey, AShift, AKeyChar);
    hdkFolderHotlist:
      Result := Assigned(AHost.HandleHotlistList) and
        AHost.HandleHotlistList(AKey, AShift, AKeyChar);
    hdkWorkspaceLibrary:
      Result := Assigned(AHost.HandleWorkspaceList) and
        AHost.HandleWorkspaceList(AKey, AShift, AKeyChar);
    hdkTerminalProfile:
      Result := Assigned(AHost.HandleTerminalProfileList) and
        AHost.HandleTerminalProfileList(AKey, AShift, AKeyChar);
    hdkSshConnections:
      Result := Assigned(AHost.HandleSshConnectionsList) and
        AHost.HandleSshConnectionsList(AKey, AShift, AKeyChar);
    hdkAssociations:
      Result := Assigned(AHost.HandleAssociationsList) and
        AHost.HandleAssociationsList(AKey, AShift, AKeyChar);
    hdkColorCoding:
      Result := AHost.HandleColorList(AKey, AShift, AKeyChar);
    hdkColorCodingEdit:
      Result := AHost.HandleColorEdit(AKey, AShift, AKeyChar);
    hdkSearch:
      Result := Assigned(AHost.HandleSearchEdit) and
        AHost.HandleSearchEdit(AKey, AShift, AKeyChar);
    hdkMarkdownColors:
      Result := AHost.HandleMarkdownColors(AKey, AShift, AKeyChar);
    hdkThemeColors:
      Result := Assigned(AHost.HandleThemeColor) and
        AHost.HandleThemeColor(AKey, AShift, AKeyChar);
    hdkKeymap:
      Result := AHost.HandleKeymapList(AKey, AShift, AKeyChar);
    hdkCmdHistory:
      Result := AHost.HandleCmdHistoryFilter(AKey, AShift, AKeyChar);
    hdkCommandPalette:
      Result := AHost.HandleCommandPaletteFilter(AKey, AShift, AKeyChar);
  else
    Result := False;
  end;
end;

function PressFocusedOrOk(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; var AKey: Word; var AKeyChar: Char): Boolean;
var
  DialogCmdId: string;
  Record_: TDialogIdProc;
  Command: TDialogCmdProc;
  Run: TProc;
begin
  Result := False;
  if (AKey <> vkReturn) or (AKind = hdkNone) then
    Exit;
  if Assigned(AHost.DialogDropDownOpen) and AHost.DialogDropDownOpen() then
    Exit;
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
  Result := True;
end;

function DispatchModalDialogInput(const AHost: TDualPanelModalInputHost;
  AKind: THostDialogKind; var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  // Before the generic Enter: Ctrl+Enter in a history list is "show in
  // panel", not OK. A miss is not asked again below.
  if (AKind in [hdkFileHistory, hdkFolderHistory]) and
     ModalKindTookKey(AHost, AKind, AKey, AShift, AKeyChar) then
    Exit(True);
  if JobProgressEnterSwallowed(AHost, AKind, AKey) then
  begin
    ConsumeKey(AKey, AKeyChar, True);
    Exit(True);
  end;
  if PressFocusedOrOk(AHost, AKind, AKey, AKeyChar) then
    Exit(True);
  if not (AKind in [hdkFileHistory, hdkFolderHistory]) and
     ModalKindTookKey(AHost, AKind, AKey, AShift, AKeyChar) then
    Exit(True);
  Result := AHost.HandleDialogWidget(AKey, AShift, AKeyChar);
end;

end.
