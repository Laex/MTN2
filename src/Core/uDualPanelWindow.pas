unit uDualPanelWindow;

{ Dual Panel Host: menu + clock, Dual Panel Tabs, two panel frames
  (double-line = active), Panel Tabs, scrollbars, command line, F-bar, status.
  Default colours via Theme = classic FAR palette. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.DateUtils,
  System.IOUtils, System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uTerminalWindow, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelCmd, uVfsTypes, uVfsRegistry, uDriveInfo, uAssociations, uUserAssociations,
  uKeymap, uFileFind, uFindSession, uEditorWindow, uHelpViewer, uHelpContext, uQuickTextView,
  uHistoryPopup,
  uInputLine, uFunctionBar, uPanelModel, uPanelColumns, uDirWatch, uDialogTypes, uDialogJson,
  uDialogHost, uShellAssoc, uShellIcons, uDualPanelOverlays,
  uDualPanelDrivePopup, uDualPanelHistoryPopup, uDualPanelJobs, uDualPanelJobList,
  uDualPanelJobRules, uDualPanelSearch, uDualPanelMenus,
  uFolderSize, uDualPanelFolderSize, uDualPanelSelection, uDualPanelCmdLine,
  uDualPanelDrawUtils, uDualPanelInfoPanel, uDualPanelPanelDraw, uDualPanelOperations, uTopMenuBar, uMenuRegistry, uPluginHost,
  uFolderHistory, uANSIParser,
  uLinkUtils, uWinFileAttr, uFileCompare, uRecycleBinVfs, uWorkspaceVfs,
  uDualPanelSync, uDualPanelTabs, uShellProfiles, uTerminalWorkspace, uOverlayRenderer,
  uColorCodingEditHelpers, uDualPanelColorCoding, uDualPanelKeymapDialog, uDualPanelFolderHotlist,
  uDualPanelWorkspaceLibrary, uWorkspaceLibrary,
  uDualPanelSshConnections, uSshConnections, uDualPanelUserAssociations,
  uUserMenu, uUserMenuController, uDualPanelUserMenu,
  uDualPanelHistoryDialogs, uDualPanelSettingsDialogs, uDualPanelFileDialogs,
  uDualPanelJobDialogs, uDualPanelFindDialogs, uDualPanelStatus,
  uDualPanelInput, uDualPanelTopMenu, uDualPanelClick, uDualPanelDrag, uPanelUriLabels,
  uMessageBus, uDisplaySettings, uConPty;

type
  THandleInputMethod = function(var AKey: Word; AShift: TShiftState;
    var AKeyChar: Char): Boolean of object;

  /// <summary>One row of TDualPanelWindow.FInputOverlays: IsActive is
  /// re-evaluated on every keypress (no persisted push/pop state ? see the
  /// FInputOverlays field comment for why), and the first row whose
  /// IsActive returns True gets to fully own that keypress via Handle.</summary>
  TInputOverlayEntry = record
    IsActive: TFunc<Boolean>;
    Handle: THandleInputMethod;
    class function Make(AIsActive: TFunc<Boolean>; AHandle: THandleInputMethod): TInputOverlayEntry; static;
  end;

  TDualPanelWindow = class(TTerminalWindow)
  private
    FTopMenu: TTopMenuController;
    FState: TDualPanelWindowState;
    FLeftModel: IPanelModel;
    FRightModel: IPanelModel;
    FLeftWatch: TDirectoryWatcher;
    FRightWatch: TDirectoryWatcher;
    FWatchPending: array[TPanelSide] of Boolean;
    FQuickSearchActive: Boolean;
    FQuickSearchText: string;
    /// <summary>Ctrl+F live filter box ? distinct from Alt Quick Search
    /// (FQuickSearchActive): this hides non-matching rows via
    /// IPanelModel.SetFilterMask instead of just moving the cursor.</summary>
    FFilterBoxActive: Boolean;
    FFilterBoxText: string;
    /// <summary>Ctrl+F history drop-down (uDialogHistory key 'livefilter')
    /// and where the filter field was last drawn (it opens above it).</summary>
    FFilterPopup: THistoryPopup;
    FFilterFieldBounds: TRectI;
    /// <summary>Checksums (Ctrl+Alt+H): the job's input, its cancel token
    /// while it runs, and the last result (Copy / Save in the result dialog).</summary>
    FChecksumPaths: TArray<string>;
    FChecksumBaseDir: string;
    FChecksumAlgoIndex: Integer;
    FChecksumToken: IJobCancelToken;
    FChecksumLines: TArray<string>;
    FChecksumSaveName: string;
    FNextTabId: Cardinal;
    FDocuments: TObjectDictionary<Cardinal, TEditorWindow>;
    FTerminals: TObjectDictionary<Cardinal, TTerminalWorkspaceWindow>;
    FLeftBounds: TRectI;   // outer panel frame (local)
    FRightBounds: TRectI;
    FListTop: Integer;
    FListBottom: Integer;
    FVfs: IVirtualFileSystem;
    FAlive: Boolean;
    FHostWindowId: Int64;
    FOnContentChanged: TNotifyEvent;
    FOnOpenViewer: TOpenViewerEvent;
    FOnOpenEditor: TOpenEditorEvent;
    FOnShowProperties: TShowPropertiesEvent;
    FOnQuitRequest: TQuitRequestEvent;
    FDrivePopupCtrl: TDrivePopupController;
    /// <summary>Ctrl+Left/Right preview: highlight only; navigate on Ctrl release.</summary>
    FDrivePreviewActive: Boolean;
    FDrivePreviewSide: TPanelSide;
    FDrivePreviewLetter: Char;
    /// <summary>Alt+Left/Right directory-history popup: shown on first press,
    /// updated on every further press while Alt is held, closed on release
    /// (see SetKeyModifiers).</summary>
    FHistoryPopupCtrl: THistoryPopupController;
    FCmdLineMgr: TDualPanelCmdLineManager;
    /// <summary>Fallback file clipboard when OLE SetClipboard fails; valid
    /// only while GetClipboardSequenceNumber equals FFileClipSeq.</summary>
    FFileClipUris: TArray<string>;
    FFileClipCut: Boolean;
    FFileClipSeq: Cardinal;
    FJobs: TPanelJobList;
    FJobAskDeferred: Boolean;
    FJobProgressRes: string;
    FSyncingJobProgress: Boolean;
    FSearchUi: TSearchController;
    FMenus: TMenuStubController;
    FPendingSelectName: string;
    FPendingSelectSide: TPanelSide;
    /// <summary>Helper for Gray+/Gray? select dialogs (FAR).</summary>
    FSelHelper: TDualPanelSelectionHelper;
    FOnRunCommand: TRunCommandEvent;
    FOnShellCwdSync: TShellCwdSyncEvent;
    FOnToggleConsole: TQuitRequestEvent;
    FOnOpenTerminal: TOpenTerminalEvent;
    FOnSetConsoleProfile: TSetConsoleProfileEvent;
    FOnGetConsoleProfile: TGetConsoleProfileEvent;
    FOnThemeSelect: TThemeSelectEvent;
    FOnGetActiveThemeId: TGetThemeIdEvent;
    FOnApplyDisplaySettings: TDisplaySettingsEvent;
    FOnGetDisplaySettings: TGetDisplaySettingsEvent;
    FConsoleMode: Boolean;
    FTerminalCloseOnExit: Boolean;
    FAutoSyncConsoleCwd: Boolean;
    /// <summary>Blinking cursor phase: True = cursor shown, False = cursor hidden.</summary>
    FCursorVisible: Boolean;
    FDialog: TDialogHost;
    FDialogKind: THostDialogKind;
    /// <summary>F1 Help window (created on first F1); modal over everything.</summary>
    FHelp: THelpViewer;
    /// <summary>Ctrl+Q text preview (created on first use).</summary>
    FQuickText: TQuickTextView;
    /// <summary>Workspace tab id while hdkWorkspaceTabRename is open.</summary>
    FRenameWorkspaceId: Cardinal;
    FSkipArchivePasswordUri: string;
    FArchivePasswordUri: string;
    FArchivePasswordSide: TPanelSide;
    FArchivePasswordRetry: Boolean;
    FNavigateSub: ISubscription;
    FReloadSub: ISubscription;
    FColorCoding: TColorCodingDialogController;
    FKeymapDlg: TKeymapDialogController;
    FFolderHotlist: TFolderHotlistDialogController;
    FWorkspaceLibrary: TWorkspaceLibraryDialogController;
    FSshConnections: TSshConnectionsDialogController;
    FUserAssociations: TUserAssociationsDialogController;
    FUserMenuHost: TUserMenuDialogController;
    FFolderHistory: TFolderHistoryDialogController;
    FCmdHistory: TCmdHistoryDialogController;
    FFileHistory: TFileHistoryDialogController;
    FSettings: TSettingsDialogController;
    FFileOps: TFileOpDialogController;
    FJobDialogs: TJobDialogController;
    FSearchDlg: TSearchDialogController;
    FDirSync: TDirSyncDialogController;
    FKeymapHost: TDualPanelKeymapHost;
    FClickHost: TDualPanelClickHost;
    FDrawHost: TDualPanelDrawHost;
    FPanelHost: TDualPanelPanelHost;
    FDragHost: TDualPanelDragHost;
    FEmbeddedHost: TDualPanelEmbeddedHost;
    FCmdLineDrawHost: TDualPanelCmdLineDrawHost;
    FStatusHost: TDualPanelStatusHost;
    FFreeInputHost: TDualPanelFreeInputHost;
    FModalInputHost: TDualPanelModalInputHost;
    FFilesDrawHost: TDualPanelFilesDrawHost;
    /// <summary>Ordered "which overlay currently owns keyboard input" table
    /// consulted by HandleInput ? see TInputOverlayEntry. Recomputed from
    /// live state on every keypress rather than push/pop: FDialog routinely
    /// opens on top of an already-active FJobs (e.g. hdkJobConfirm), and a
    /// persisted stack would need a Pop at every one of FDialog.Open's many
    /// call sites to avoid leaving a stale entry that swallows all future
    /// input ? this table can't desync because it has no state to desync.
    /// Built once in Create, after the overlay objects it closes over exist.</summary>
    FInputOverlays: TArray<TInputOverlayEntry>;
    FFreeText: string;
    FFreeRoot: string;
    FFreeGen: Cardinal;
    FLastClickCol: Integer;
    FLastClickRow: Integer;
    FLastClickTick: Cardinal;
    /// <summary>Potential OLE / panel file drag after list MouseDown.</summary>
    FDragArmed: Boolean;
    FDragStartCol: Integer;
    FDragStartRow: Integer;
    FDragUris: TArray<string>;
    /// <summary>Mouse reorder for workspace / panel tabs.</summary>
    FTabDragKind: Integer; // 0=none, 1=workspace, 2=panel left, 3=panel right
    FTabDragFrom: Integer;
    FTabDragHover: Integer;
    FTabDragArmed: Boolean;
    FTabDragActive: Boolean;
    FTabDragStartCol: Integer;
    FTabDragStartRow: Integer;
    FDropHighlightActive: Boolean;
    FDropHighlightSide: TPanelSide;
    FDropHighlightURI: string;
    FDropHighlightRow: Integer;
    FPlainTotals: array[TPanelSide] of record
      Valid: Boolean;
      Bytes: Int64;
      Files, Folders: Integer;
    end;
    FFolderSizeMgr: TFolderSizeCalculationManager;
    function ActiveWorkspace: TDualPanelWorkspaceTab;
    procedure SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
    function ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
    procedure SetActivePanel(var AWs: TDualPanelWorkspaceTab; const APanel: TPanelState);
    function ModelForSide(ASide: TPanelSide): IPanelModel;
    function RowsForSide(ASide: TPanelSide): TPanelRows;
    /// <summary>Active workspace/panel/tab/rows for the active side. Returns False
    /// (nothing else populated meaningfully) when the active side has no rows.</summary>
    function GetActiveRowContext(out AWs: TDualPanelWorkspaceTab;
      out APanel: TPanelState; out ATab: TTab; out ARows: TPanelRows): Boolean;
    /// <summary>GetActiveRowContext plus the row under the cursor. Returns False
    /// when the active side has no rows.</summary>
    function GetActiveRow(out AWs: TDualPanelWorkspaceTab; out APanel: TPanelState;
      out ATab: TTab; out ARows: TPanelRows; out ARow: TPanelRow;
      out AIdx: Integer): Boolean;
    /// <summary>False while a modal dialog, search UI, foreground job, or
    /// ask-phase job owns the UI. Background running jobs do not block.</summary>
    function CanStartOperation: Boolean;
    /// <summary>Guard shared by SwapPanels / EqualizeOtherPanelToActive /
    /// EqualizeActivePanelFromOther: only a panels workspace, with no modal
    /// UI (menus, drive popup) in the way, can have its layout rearranged.
    /// Also cancels any in-flight drive preview, as all three callers do.</summary>
    function CanStartPanelLayoutChange(const Ws: TDualPanelWorkspaceTab): Boolean;
    procedure FlushPendingJobAsk;
    procedure SyncJobProgressDialog;
    procedure OpenJobProgress(const AJob: TPanelJobState);
    function CloseJobProgressForReplacement: Boolean;
    procedure OpenJobList;
    function KeymapActiveSide: TPanelSide;
    procedure KeymapToggleConsole;
    procedure KeymapRequestQuit;
    procedure BindKeymapHost;
    procedure BindClickHost;
    procedure BindDrawHost;
    procedure BindPanelHost;
    procedure BindDragHost;
    procedure BindEmbeddedHost;
    procedure BindCmdLineDrawHost;
    procedure BindStatusHost;
    procedure BindFreeInputHost;
    procedure BindModalInputHost;
    procedure BindFilesDrawHost;
    procedure BindDialogControllers;
    procedure BindRuntimeControllers;
    procedure SeedDefaultWorkspaces;
    procedure HostSetDialogKind(AKind: THostDialogKind);
    procedure HostUnfocusCmd;
    procedure HostShowShellStub(const ATitle, ADetail: string);
    procedure HostWorkspaceEmptySave;
    function HostTryGetHotlistUri(out AUri: string): Boolean;
    function HostTryGetCmdHistory(out AItems: TArray<string>): Boolean;
    procedure HostApplyCmdHistory(const ACommand: string);
    function HostGetActiveThemeId: string;
    procedure HostSelectTheme(const AThemeId: string);
    function HostGetDisplaySettings: TDisplaySettings;
    procedure HostApplyDisplaySettings(const ASettings: TDisplaySettings);
    procedure HostOpenTerminal(const AProfileId, ACwd: string);
    procedure HostSetConsoleProfile(const AProfileId: string);
    function HostGetConsoleProfile: string;
    function HostActivePanelUri: string;
    function HostInPanelsWorkspace: Boolean;
    function HostLastSelectMask: string;
    function HostSelectFolders: Boolean;
    function HostTryGetCursorItem(out AName, AUri, ATargetUri: string;
      out AIsParent: Boolean): Boolean;
    procedure HostRememberStubUri(const AUri: string);
    procedure HostCmdLineSubmit(const ACommand: string);
    function HostCmdLineNames: TArray<string>;
    procedure HostFolderSizeProgress(ASide: TPanelSide; ACompleted, APending: Integer;
      AFolderBytes: Int64; const AFolderURI: string);
    function HostPanelBounds(ASide: TPanelSide): TRectI;
    function HostPanelPath(ASide: TPanelSide): string;
    function HostPanelDriveDirs(ASide: TPanelSide): TPanelDriveDirs;
    procedure HostOpenJobConfirm(const ATitle, AMessage: string);
    procedure HostOpenOverwriteAsk(const APath, ANewLine, AExistingLine: string);
    procedure HostOpenDeleteError(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean);
    procedure HostOpenIOErrorAsk(const AHeadline, APath, AErrorLine: string);
    procedure HostJobFinished(ASuccess: Boolean);
    procedure HostClearJobSelection(const AOriginSrc: string);
    procedure HostReloadJobPanels(const AOriginSrc, AOriginDst: string);
    function HostApplyFindResults(const ARoot, AMask: string;
      const AHits: TArray<TFindHit>): Boolean;
    function HostSearchBlocked: Boolean;
    procedure HostPrepareSearchUi;
    function HostIsAlive: Boolean;
    procedure HostMenuSortSelect(AColumn: TPanelSortColumn);
    procedure HostMenuColumnModeSelect(AMode: TPanelColumnMode);
    function OverlayDialogVisible: Boolean;
    function OverlaySearchActive: Boolean;
    function OverlayJobActive: Boolean;
    function OverlayStubVisible: Boolean;
    function OverlayUserMenuVisible: Boolean;
    function OverlaySortMenuVisible: Boolean;
    function OverlayColumnModeMenuVisible: Boolean;
    function OverlayDrivePopupVisible: Boolean;
    procedure HostLeftDirWatch;
    procedure HostRightDirWatch;
    procedure HostNavigateSide(ASide: TPanelSide; const AURI: string);
    procedure DrawHostFilesHeaders(const ABounds: TRectI; const APanel: TPanelState);
    procedure DrawHostFilesList(const AListBounds: TRectI; const ATab: TTab;
      AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide);
    procedure DrawHostFilesScroll(AX, ATop, ABottom, APos, ACount, AViewH: Integer);
    procedure PreviewCycleActiveDrive(ADelta: Integer);
    procedure ClearCmdLineOnEsc;
    function TryPasteClipboardToCmdLine: Boolean;
    procedure HostRestoreGrayOpKey(var AKey: Word; var AKeyChar: Char);
    procedure CmdLineStripColors(out AFg, ABg: TAlphaColor);
    procedure CmdLineFocusAccent(out AFg, ABg: TAlphaColor);
    procedure CloseHostDocument(AIndex: Integer);
    procedure CloseHostTerminal(AIndex: Integer);
    procedure DrawHostDialog(AWidth, AHeight: Integer);
    procedure DrawHostSubmenu(AWidth: Integer);
    function ClickOverlaySnapshot: TClickOverlaySnapshot;
    function ClickHandleTopMenu(ACol, ARow: Integer): Boolean;
    function ClickHandleDocument(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    function ClickHandleTerminal(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    function ClickHandleDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    procedure ClickSyncColorPicker;
    procedure ClickLayoutSearch(AWidth, AHeight: Integer);
    function ClickSearchBounds: TRectI;
    procedure ClickLayoutJob(AWidth, AHeight: Integer);
    function ClickJobBounds: TRectI;
    procedure ClickCancelOverwrite;
    procedure ClickCancelDelete;
    procedure ClickCancelIOError;
    procedure ActivateSide(ASide: TPanelSide);
    procedure ClosePanelTabOnSide(ASide: TPanelSide);
    procedure TogglePanelConsoleMode;
    procedure ReloadKeymapProfile;
    procedure EditGotoLine;
    procedure EditFind;
    procedure EditFindReplace;
    procedure EditEncoding;
    procedure EditUndo;
    procedure EditRedo;
    procedure EditHexToggle;
    procedure EditCopy;
    procedure EditCut;
    procedure EditPaste;
    procedure ClipboardCopyFiles(ACut: Boolean);
    procedure ClipboardPasteFiles;
    function FileClipStillOurs: Boolean;
    function TopMenuActionIsEnabled(AAction: TTopMenuAction): Boolean;
    /// <summary>Builds a fresh single-tab-per-URI panel with this app's
    /// default view settings (full columns, unsorted, hidden files shown)
    /// ? used by Create to seed the two initial workspaces.</summary>
    function MakePanelState(const AUris: array of string): TPanelState;
    procedure ModelInvalidated(AWindowId: Integer);
    procedure MaybeAskArchivePassword(ASide: TPanelSide);
    procedure HandlePluginNavigate(const ATopic: string; const APayload: TObject);
    procedure HandlePluginReload(const ATopic: string; const APayload: TObject);
    procedure ReloadSidesShowing(const AUri: string);
    procedure HandleArchivePasswordCommand(const AControlId, APassword: string);
    procedure LoadSide(ASide: TPanelSide);
    procedure ReloadActiveRows;
    procedure SyncDirWatches;
    procedure PauseDirWatchesForJob;
    procedure HostJobUiClosed;
    procedure SoftReloadSide(ASide: TPanelSide; AForce: Boolean = False);
    procedure HandleDirWatch(ASide: TPanelSide);
    procedure FlushDirWatchPending;
    procedure NavigateSideTo(ASide: TPanelSide; const AURI: string;
      AAddToHistory: Boolean = True);
    procedure NavigateActiveTo(const AURI: string);
    procedure NavigateActiveToDriveRoot;
    /// <summary>"Go to file": navigate the active panel to the folder holding
    /// APath and land the cursor on the item itself. Shared by the Alt+F7
    /// results dialog (its Goto button) and by Enter inside a find:// panel.</summary>
    procedure GotoFileLocation(const AFilePath: string);
    procedure HistoryBack;
    procedure HistoryForward;
    procedure ActivateCurrent;
    procedure RefreshActive;
    function HandleQuickSearchInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    procedure ClearQuickSearch;
    procedure DrawQuickSearchField(const ABounds: TRectI);
    procedure BeginLiveFilter;
    procedure ClearLiveFilter;
    function HandleFilterInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    procedure DrawFilterField(const ABounds: TRectI);
    procedure ToggleInsertSelect;
    /// <summary>Shift+Up/Down/Left/Right/Home/End/Pg*: invert mark on rows, then
    /// move. Unit steps: leaving row only. AExcludeLanding (Brief Left/Right):
    /// invert [From..To) ? includes the row before landing, not the landing.</summary>
    procedure MoveCursorWithSelect(ADelta: Integer;
      AExcludeLanding: Boolean = False);
    procedure CopyFullPathToClipboard;
    procedure SelectAllActive;
    procedure InvertSelectionActive;
    procedure BeginSelectByMask(AUnselect: Boolean);
    procedure ApplySelectMask(const AMask: string; AUnselect: Boolean;
      ASelectFolders: Boolean);
    /// <summary>FAR Shift+Gray+/Gray?: select/deselect all files (no folders), instantly.</summary>
    procedure ApplySelectAllFiles(AUnselect: Boolean);
    /// <summary>FAR Ctrl+Gray+/Gray?: select/deselect files sharing the cursor
    /// file's extension, instantly (no dialog).</summary>
    procedure ApplySelectByExtension(AUnselect: Boolean);
    /// <summary>FAR Alt+Gray+/Gray?: select/deselect files sharing the cursor
    /// file's name stem (no extension).</summary>
    procedure ApplySelectByName(AUnselect: Boolean);
    procedure SubmitCommandLine;
    procedure RunConsoleCommand(const ACommand: string);
    /// <summary>FAR Shift+Enter: cmdline or cursor file as a separate OS process.</summary>
    procedure RunDetachedFromCmdLine(const AText, ACwd: string);
    procedure RunDetachedOpenFolder(const AUri: string; const ATab: TTab;
      AIsParent: Boolean);
    procedure RunDetachedFile(const AUri: string);
    procedure RunDetached;
    function PanelCommandCwd: string;
    /// <summary>Shared active-panel-dir -> console push, used by both the
    /// gated auto-sync (NotifyShellCwdSync) and the unconditional hotkey
    /// (SyncConsoleDirNow).</summary>
    procedure PushShellCwdSync;
    procedure NotifyShellCwdSync;
    /// <summary>kaSyncConsoleDir (Ctrl+Shift+O) while Dual Panel is active:
    /// force-push the active panel's dir into the console, ignoring
    /// AutoSyncConsoleCwd (that setting only gates the automatic push).</summary>
    procedure SyncConsoleDirNow;
    function TryResolveCommandPath(const AText: string; out AURI: string): Boolean;
    procedure NotifyChanged;
    procedure CloseDrivePopup;
    procedure ToggleDrivePopup(ASide: TPanelSide);
    function HandleDrivePopupInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleDrivePopupClick(ALocalCol, ALocalRow: Integer): Boolean;
    procedure DrawDrivePopup;
    procedure ShowHistoryPopup(ASide: TPanelSide; const ATab: TTab);
    procedure CloseHistoryPopup;
    procedure DrawHistoryPopup;
    procedure CloseJobUi;
    function CanBeginAnotherJob: Boolean;
    procedure BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean = True);
    procedure BeginTransferJob(const ASources: TArray<string>; const ADestDirURI: string;
      AKind: TPanelJobKind);
    procedure BeginPackZip;
    procedure BeginUnpackZip;
    function CollectActiveSources: TArray<string>;
    function OppositeSide(ASide: TPanelSide): TPanelSide;
    procedure DrawJobPopup;
    function HandleJobInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure OpenUserMenu;
    procedure CloseUserMenu;
    procedure OpenSortMenu;
    procedure CloseSortMenu;
    procedure OpenColumnModeMenu;
    procedure CloseColumnModeMenu;
    procedure OpenHelp;
    /// <summary>Context F1: THelpScreen from what is on screen now.</summary>
    function CurrentHelpScreen: THelpScreen;
    procedure HelpChanged(Sender: TObject);
    procedure QuickTextChanged(Sender: TObject);
    function HelpVisible: Boolean;
    procedure HostUserMenuAction(AAction: TUserMenuAction; AParent: TUserMenuItem;
      AIndex: Integer);
    function HostUserMenuContext: TUserMenuContext;
    procedure HostRunUserMenuCommand(const ACommand: string);
    procedure DrawUserMenu;
    procedure DrawSortMenu;
    procedure DrawColumnModeMenu;
    function HandleUserMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleSortMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleColumnModeMenuInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure OpenStub(AKind: TStubKind; const ATitle, ADetail: string);
    procedure CloseStub;
    /// <summary>Closes the drive popup and any open top-menu-bar overlay
    /// (user menu, sort menu, column-mode menu, stub) and unfocuses the
    /// command line ? the shared "make way for a dialog" step run before
    /// most Open*Dialog handlers.</summary>
    procedure CloseTransientUiBeforeDialog;
    procedure DrawStub;
    function HandleStubInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure BeginMkDir;
    procedure ConfirmMkDir(const AName: string);
    procedure BeginCreateLink;
    procedure ConfirmCreateLink(const ALinkName, ATarget: string; AKind: TLinkKind);
    procedure BeginSetAttributes;
    procedure ShowProperties;
    procedure ApplySetAttributes(const APaths: TArray<string>; const APlan: TFileAttrPlan);
    procedure BeginCompareFiles;
    /// <summary>Ctrl+Shift+C: select what differs between the two panels.</summary>
    procedure CompareFolders;
    procedure ShowCompareResult(const ATitle, AMessage: string);
    procedure ShowFileDiff(const ALeftName, ARightName, AStatus: string;
      const ALines: TArray<string>);
    procedure NavigateToRecycleBin;
    procedure RestoreCursorItemFromRecycleBin;
    function ActivePanelIsTmp: Boolean;
    function ActivePanelIsWorkspace: Boolean;
    procedure TmpRemoveSelected;
    procedure WorkspaceUnlinkSelected;
    procedure TmpGotoCursorFile;
    procedure TmpGotoOpposite;
    procedure WorkspaceGotoOpposite;
    procedure TmpSaveList;
    procedure ConfirmTmpSaveList(const AFileName: string);
    procedure BeginNewFile;
    procedure ConfirmNewFile(const AName: string);
    procedure BeginRename;
    procedure ConfirmRename(const AName: string);
    procedure BeginCopyInPlace;
    procedure ConfirmCopyInPlace(const AName: string);
    procedure DialogChanged(Sender: TObject);
    procedure DialogCommand(const AControlId, AValuesJson: string);
    /// <summary>DialogCommand's `case FDialogKind of` ? one branch per
    /// THostDialogKind. Returns False from the (rare) branches that must
    /// skip DialogCommand's trailing NotifyChanged/FlushDirWatchPending
    /// (matches those branches' original bare `Exit;`).</summary>
    function DispatchDialogCommand(AKind: THostDialogKind;
      const AControlId, AValuesJson: string;
      const AFields: TDialogCommandFields): Boolean;
    procedure RequestFreeSpace(const APath: string);
    procedure ResolveRelativeCommandAsync(const AText, ABaseDir: string);
    procedure ExecuteTopMenuAction(AAction: TTopMenuAction);
    procedure OpenAboutDialog;
    procedure OpenPluginListDialog;
    procedure OpenFolderHistoryDialog;
    procedure OpenFileHistoryDialog;
    procedure HostOpenHistoryFile(const AURI: string; AEdit: Boolean);
    procedure HostGotoHistoryFile(const AURI: string);
    procedure OpenCmdHistoryDialog;
    procedure OpenFolderHotlistDialog;
    procedure BeginFolderHotlistAdd;
    procedure OpenWorkspaceLibraryDialog;
    procedure BeginWorkspaceLibrarySave;
    procedure OpenSshConnectionsDialog;
    procedure OpenSshTerminal(const AConnectionId: string);
    procedure OpenUserAssociationsDialog;
    procedure OpenThemeDialog;
    procedure OpenColumnsConfigDialog;
    procedure OpenDisplayDialog;
    procedure OpenColorCodingDialog;
    procedure OpenKeymapDialog;
    procedure BeginBranchView;
    procedure OpenTerminalProfileDialog;
    procedure OpenConsoleProfileDialog;
    procedure OpenDirSync;
    procedure OpenSearchDialog;
    procedure CloseSearchUi;
    procedure ApplyPendingSelect(ASide: TPanelSide; const ARows: TPanelRows);
    procedure ClampCursorSide(ASide: TPanelSide);
    procedure DrawSearchUi;
    function HandleSearchInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure RequestOpenViewer(const AURI: string);
    procedure RequestOpenEditor(const AURI: string);
    procedure OpenViewOrEdit(AEdit: Boolean);
    /// <summary>Alt+F3 / Alt+F4: the cursor file in the external viewer /
    /// editor (uExternalTools).</summary>
    procedure LaunchExternal(AEdit: Boolean);
    procedure ExternalView;
    procedure ExternalEdit;
    procedure OpenExternalToolsDialog;
    procedure BeginChecksums;
    procedure StartChecksumJob(AAlgoIndex: Integer; AVerify: Boolean);
    procedure ShowChecksumResult(const ATitle, AStatus: string;
      const ALines: TArray<string>; AVerify: Boolean);
    procedure DispatchChecksumCommand(AKind: THostDialogKind; const AControlId: string);
    /// <summary>Ctrl+Q: NC/NDN/FAR/TC convention ? puts the opposite panel
    /// into pvkQuickView for any cursor row (file or directory), same toggle
    /// shape as ToggleAdjacentInfoPanel/pvkInfo. Image overlay vs placeholder
    /// is decided later in DrawQuickViewContent as the cursor moves.</summary>
    procedure ToggleQuickView;
    procedure CloseQuickView;
    procedure CancelFolderSize;
    procedure CalculateFolderSizeUnderCursor;
    function FolderSizeStubTitle: string;
    procedure InsertPanelItemToCmdLine(AFullPath: Boolean);
    procedure ShellOpenCurrent;
    procedure RunUserCommandCurrent(const AURI, ACommandTemplate: string);
    procedure SetCmdFocused(AValue: Boolean);
    function ClickCmdLine(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    /// <summary>Ctrl+Down / Alt+Down in the command line: its history as a
    /// drop-down above the line.</summary>
    procedure OpenCmdHistoryPopup;
    /// <summary>A click while the command-line history list is open: True
    /// when it landed on the list.</summary>
    function ClickCmdHistoryPopup(ACol, ARow: Integer): Boolean;
    function ClickFilterHistoryPopup(ACol, ARow: Integer): Boolean;
    procedure SetLiveFilterText(const AText: string);
    function HandleCmdLineInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure SetConsoleMode(AValue: Boolean);
    procedure EnsureCursorVisible(var ATab: TTab; ARowCount, AViewH: Integer;
      AColCount: Integer = 1);
    function ListViewHeight: Integer;
    function ListWidthForSide(ASide: TPanelSide): Integer;
    function ListColCountForSide(ASide: TPanelSide): Integer;
    procedure SyncPanelScrollAfterLayout;
    procedure MoveCursor(ADelta: Integer);
    procedure SwitchSide;
    procedure SwapPanels;
    procedure EqualizeOtherPanelToActive;
    procedure EqualizeActivePanelFromOther;
    procedure TogglePanelVisible(ASide: TPanelSide);
    function IsPanelVisible(ASide: TPanelSide): Boolean;
    procedure ToggleAdjacentInfoPanel;
    function PanelViewKind(ASide: TPanelSide): TPanelViewKind;
    procedure SetPanelViewKind(ASide: TPanelSide; AKind: TPanelViewKind);
    procedure NextWorkspace;
    procedure PrevWorkspace;
    procedure SelectWorkspace(AIndex: Integer);
    procedure NewWorkspace;
    procedure NextPanelTab;
    procedure PrevPanelTab;
    procedure NewPanelTab;
    /// <summary>Ctrl+Shift+T for an explicitly named side ? used by the
    /// double-click-on-empty-panel-tab-row path, where the panel that was
    /// clicked is not necessarily the active one yet.</summary>
    procedure NewPanelTabOnSide(ASide: TPanelSide);
    procedure SelectPanelTab(ASide: TPanelSide; AIndex: Integer);
    procedure ClosePanelTab(ASide: TPanelSide; AIndex: Integer);
    function SelectPanelTabAtCol(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer): Boolean;
    function HitWorkspaceTabAtCol(ACol: Integer; out AIndex: Integer;
      out AIsClose: Boolean): Boolean;
    function HitPanelTabAtCol(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer; out AIndex: Integer; out AIsClose: Boolean): Boolean;
    procedure ArmTabDrag(AKind, AFrom, ACol, ARow: Integer);
    procedure CancelTabDrag;
    function UpdateTabDrag(ALocalCol, ALocalRow: Integer): Boolean;
    procedure CommitWorkspaceTabDrag(AFromIdx, AToIdx: Integer);
    procedure CommitPanelTabDrag(AFromIdx, AToIdx: Integer);
    procedure CommitTabDrag;
    procedure CloseWorkspace(AIndex: Integer);
    procedure RemoveWorkspaceTabAt(AIndex: Integer);
    function DocumentForWorkspace(AIndex: Integer): TEditorWindow;
    procedure DocumentContentChanged(Sender: TObject);
    procedure DocumentCloseRequest(Sender: TObject);
    procedure ClearAllDocuments;
    function TerminalForWorkspace(AIndex: Integer): TTerminalWorkspaceWindow;
    procedure TerminalContentChanged(Sender: TObject);
    procedure TerminalCloseRequest(Sender: TObject);
    procedure ClearAllTerminals;
    procedure SyncWindowTitle;
    procedure LayoutPanels(AWidth, AHeight: Integer);
    procedure DrawMenuBar(AWidth: Integer);
    procedure DrawWorkspaceTabBar(AWidth: Integer);
    function SelectWorkspaceAtCol(ACol: Integer): Boolean;
    function BeginRenameWorkspaceAtCol(ACol: Integer): Boolean;
    procedure ApplyWorkspaceTabTitle(const AName: string);
    procedure DrawPanel(const ABounds: TRectI; const APanel: TPanelState;
      ASide: TPanelSide; AActive: Boolean);
    procedure DrawPanelFiles(const ABounds: TRectI; const APanel: TPanelState;
      ASide: TPanelSide; AActive: Boolean; AFrame, ABodyBg: TAlphaColor);
    procedure DrawPanelInfoContent(const ABounds: TRectI; ASide: TPanelSide;
      AFrame, ABodyBg: TAlphaColor);
    /// <summary>Stage 24 redo: live preview of the active side's cursor row
    /// (NC/NDN/FAR/TC Ctrl+Q ? opposite panel, follows the cursor without
    /// re-pressing Ctrl+Q). Only reissues the async decode when the row's
    /// URI changes; every redraw still refreshes the stored bounds so a
    /// resize doesn't leave the image scaled/positioned against stale
    /// geometry (see uOverlayRenderer.UpdateOverlayBounds).</summary>
    procedure DrawQuickViewContent(const ABounds: TRectI; ASide: TPanelSide;
      AFrame, ABodyBg: TAlphaColor);
    procedure DrawPanelDriveLetters(const ABounds: TRectI; const ATab: TTab;
      ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
    procedure NavigatePanelToDrive(ASide: TPanelSide; ALetter: Char);
    procedure PreviewCyclePanelDrive(ASide: TPanelSide; ADelta: Integer);
    procedure CommitDrivePreview;
    procedure CancelDrivePreview;
    procedure ApplyColumnMode(ASide: TPanelSide; AMode: TPanelColumnMode);
    procedure SyncSideSort(ASide: TPanelSide);
    procedure ApplyHeaderSort(ASide: TPanelSide; ACol: TPanelSortColumn);
    procedure ApplySortMode(ASide: TPanelSide; ACol: TPanelSortColumn);
    procedure CommitSortAndRestoreCursor(ASide: TPanelSide;
      var AWs: TDualPanelWorkspaceTab; var APanel: TPanelState; var ATab: TTab;
      const ACurURI: string);
    procedure SyncSideShowHidden(ASide: TPanelSide);
    procedure ToggleShowHidden(ASide: TPanelSide);

    procedure ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure InvalidatePlainTotals;
    procedure EnsurePlainTotals(ASide: TPanelSide; out ABytes: Int64;
      out AFiles, AFolders: Integer);
    function BuildTerminalStatusSegments: TArray<string>;
    procedure PopulatePanelStatusSnap(var Snap: TPanelStatusSnapshot;
      var Ws: TDualPanelWorkspaceTab);
    function BuildStatusOverlaySnap(const APath: string): TStatusOverlaySnapshot;
    function BuildPanelStatusSegments: TArray<string>;
    procedure DrawScrollBar(AX, ATop, ABottom, APos, ACount, AViewH: Integer;
      ADialogStyle: Boolean = False);
    procedure DrawCommandLine(AY, AWidth: Integer);
    function ChromeContext: TFunctionBarContext;
    procedure DrawFunctionKeys(AY, AWidth: Integer);
    procedure DrawAppStatusLine(AY, AWidth: Integer);
  protected
    procedure DrawDocumentContent(W, H: Integer);
    procedure DrawTerminalContent(W, H: Integer);
    procedure DrawPanelsContent(W, H: Integer);
    procedure DrawContent; override;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal);
    destructor Destroy; override;
    procedure RebuildBuffer; override;
    function SetKeyModifiers(AShift: TShiftState): Boolean; override;
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean; override;
    /// <summary>Free (non-modal) keymap bindings shared by most of the app ?
    /// see HandleInput's first `case MatchActiveAction(...)` block. Returns
    /// True (and has already reset AKey/AKeyChar) if AAction was handled;
    /// False if the caller should keep looking.</summary>
    function HandleKeymapActionPrimary(AAction: TKeymapAction;
      var AKey: Word; var AKeyChar: Char): Boolean;
    /// <summary>Function-key/panel-operation keymap bindings ? see
    /// HandleInput's second `case MatchActiveAction(...)` block. Same
    /// True/False contract as HandleKeymapActionPrimary.</summary>
    function HandleKeymapActionFunctionKeys(AAction: TKeymapAction;
      var AKey: Word; var AKeyChar: Char): Boolean;
    /// <summary>HandleInput's modal-dialog-open branch ? in-place list
    /// shortcuts for the directory hotlist / color-coding dialogs, F9 color
    /// picker, Enter-activates-default-button, then falls through to
    /// FDialog.HandleInput. Caller must already know FDialog.Visible.</summary>
    function HandleModalDialogInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleFunctionBarClick(ALocalCol: Integer;
      AShift: TShiftState): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer;
      ADoubleClick: Boolean = False; AShift: TShiftState = [];
      AAllowOpenOnDouble: Boolean = True): Boolean;
    function HandleEmbeddedMouseDown(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState): Boolean;
    function HandleMouseDown(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState): Boolean;
    function HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
    function HandleMouseUp: Boolean;
    /// <summary>Arm drag after a list click (call from form after HandleClick).</summary>
    procedure ArmFileDragFromCursor;
    /// <summary>If moved past threshold, returns local paths and clears arm.</summary>
    function TryStartFileDrag(ALocalCol, ALocalRow: Integer;
      out APaths: TArray<string>): Boolean;
    procedure CancelFileDrag;
    /// <summary>Shared first half of HitTestDropTarget/HitTestListItemLocalPath:
    /// resolves which panel a click landed in and its bounds/state, or
    /// returns False (info panels and misses excluded) for the caller to
    /// Exit on.</summary>
    function ResolvePanelHitContext(ALocalCol, ALocalRow: Integer;
      out ASide: TPanelSide; out ABounds: TRectI; out APanel: TPanelState): Boolean;
    /// <summary>Map cell > drop directory URI (panel list / folder under cursor).</summary>
    function HitTestDropTarget(ALocalCol, ALocalRow: Integer;
      out ADestURI: string; out ASide: TPanelSide; out AHighlightRow: Integer): Boolean;
    /// <summary>Map cell > local filesystem path for a list row (file:// only).</summary>
    function HitTestListItemLocalPath(ALocalCol, ALocalRow: Integer;
      out ALocalPath: string): Boolean;
    procedure SetDropHighlight(AActive: Boolean; ASide: TPanelSide = psLeft;
      const ADestURI: string = ''; AHighlightRow: Integer = -1);
    /// <summary>Accept dropped local paths into DestURI (Copy or Move).</summary>
    procedure AcceptDroppedFiles(const APaths: TArray<string>; const ADestDirURI: string;
      AMove: Boolean);
    /// <summary>After OleDragLocalFiles returns ? reload if shell moved files out.</summary>
    procedure FinishOleFileDrag(AEffect: LongInt);
    procedure OpenDocument(const AURI: string; AViewOnly: Boolean);
    procedure OpenTerminal(const AProfileId, ACwd: string);
    /// <summary>Stage 28: opens APath (file or directory) in a new tab on
    /// the active side ? the single entry point single-instance IPC and the
    /// startup CLI-arg path both call. No-op for '' or a path that doesn't
    /// exist.</summary>
    procedure OpenPathAsNewTab(const APath: string);
    function ExportSessionState: TDualPanelWindowState;
    procedure ApplySessionState(const AState: TDualPanelWindowState);
    /// <summary>Rebuilds the top menu bar's categories/captions from
    /// MENU_MAIN -- call after uStrings.SetLocale so an already-open window
    /// picks up a language switch without a restart.</summary>
    procedure ReloadMenuStructure;
    procedure RestoreWorkspaceLibrary(const AId: string);
    function WorkspaceLibraryId: string;
    property State: TDualPanelWindowState read FState;
    property OnContentChanged: TNotifyEvent read FOnContentChanged write FOnContentChanged;
    property OnOpenViewer: TOpenViewerEvent read FOnOpenViewer write FOnOpenViewer;
    property OnOpenEditor: TOpenEditorEvent read FOnOpenEditor write FOnOpenEditor;
    property OnShowProperties: TShowPropertiesEvent read FOnShowProperties write FOnShowProperties;
    property OnQuitRequest: TQuitRequestEvent read FOnQuitRequest write FOnQuitRequest;
    property OnRunCommand: TRunCommandEvent read FOnRunCommand write FOnRunCommand;
    property OnShellCwdSync: TShellCwdSyncEvent read FOnShellCwdSync write FOnShellCwdSync;
    property OnToggleConsole: TQuitRequestEvent read FOnToggleConsole write FOnToggleConsole;
    property OnOpenTerminal: TOpenTerminalEvent read FOnOpenTerminal write FOnOpenTerminal;
    property OnSetConsoleProfile: TSetConsoleProfileEvent
      read FOnSetConsoleProfile write FOnSetConsoleProfile;
    property OnGetConsoleProfile: TGetConsoleProfileEvent
      read FOnGetConsoleProfile write FOnGetConsoleProfile;
    property OnThemeSelect: TThemeSelectEvent read FOnThemeSelect write FOnThemeSelect;
    property OnGetActiveThemeId: TGetThemeIdEvent read FOnGetActiveThemeId write FOnGetActiveThemeId;
    property OnApplyDisplaySettings: TDisplaySettingsEvent read FOnApplyDisplaySettings write FOnApplyDisplaySettings;
    property OnGetDisplaySettings: TGetDisplaySettingsEvent read FOnGetDisplaySettings write FOnGetDisplaySettings;
    function GetCmdFocused: Boolean;
    property CmdFocused: Boolean read GetCmdFocused write SetCmdFocused;
    property ConsoleMode: Boolean read FConsoleMode write SetConsoleMode;
    /// <summary>When True (default), a Ctrl+Shift+N terminal tab's shell
    /// exiting closes the tab. Applied to each tab at OpenTerminal time.</summary>
    property TerminalCloseOnExit: Boolean read FTerminalCloseOnExit write FTerminalCloseOnExit;
    /// <summary>When True, the active panel navigating automatically pushes
    /// its directory into the background console (Ctrl+O). Off by default:
    /// the console and the active panel then keep independent directories,
    /// synced only on demand via Ctrl+Shift+O (SyncConsoleDirNow).</summary>
    property AutoSyncConsoleCwd: Boolean read FAutoSyncConsoleCwd write FAutoSyncConsoleCwd;
    /// <summary>Active panel's local filesystem path ('' for archive/find/non-panel
    /// workspaces). Used by the host to seed the background console's cwd.</summary>
    function ActiveLocalPath: string;
    /// <summary>Console-side Ctrl+Shift+O (reverse of SyncConsoleDirNow):
    /// navigate the active panel to a plain local filesystem path.</summary>
    procedure SetActivePanelDir(const APath: string);
    /// <summary>Shared command history (Alt+F8), newest first -- same store
    /// as the cmdline's own history. Used by the background console (via the
    /// host) and by terminal tabs (wired directly at OpenTerminal time).</summary>
    function GetCommandHistoryItems: TArray<string>;
    /// <summary>Records a command run directly at a console/terminal shell
    /// prompt into the shared history.</summary>
    procedure RecordConsoleCommand(const ACommand: string);
    function DialogVisible: Boolean;
    property Dialog: TDialogHost read FDialog;
    function ActiveDocument: TEditorWindow;
    function ActiveTerminal: TTerminalWorkspaceWindow;
    procedure FocusCommandLine;
    /// <summary>Called by the blink timer to toggle cursor visibility and redraw.</summary>
    procedure SetCursorVisible(AVisible: Boolean);
    property CursorVisible: Boolean read FCursorVisible;
    /// <summary>Dismiss overlays/jobs so Windows shutdown is not blocked.</summary>
    procedure PrepareForSystemShutdown;
    /// <summary>False while Console is shown over the panels, or the active
    /// Dual Panel Tab is a Viewer/Editor/Terminal (wkDocument/wkTerminal) ?
    /// the overlay's stored bounds are only meaningful for the wkPanels
    /// list layout that requested them, and it's a plain Canvas pass drawn
    /// unconditionally from FormPaint, so Host must gate it here rather
    /// than the overlay renderer guessing what's currently on screen.</summary>
    function QuickViewVisible: Boolean;
    /// <summary>Mouse wheel over the text Quick View scrolls the preview
    /// instead of moving the active panel's cursor. ALocalCol/Row: cell
    /// under the mouse in this window. False if the wheel is not over it.</summary>
    function HandleMouseWheelAt(ALocalCol, ALocalRow, AWheelDelta: Integer): Boolean;
    /// <summary>True while the active Dual Panel document tab is a Markdown
    /// Viewer with an image Overlay in the viewport. Host FormPaint uses
    /// this because FMdi.Active is DualPanel, not the nested TEditorWindow.</summary>
    function MarkdownImageOverlayVisible: Boolean;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX,
  uWinFileDragDrop, uStrings, uFileHistory, uPanelCompare,
  uExternalTools, uDialogHistory, uChecksums;

const
  cLiveFilterHistory = 'livefilter';

class function TInputOverlayEntry.Make(AIsActive: TFunc<Boolean>;
  AHandle: THandleInputMethod): TInputOverlayEntry;
begin
  Result.IsActive := AIsActive;
  Result.Handle := AHandle;
end;

function TDualPanelWindow.GetCmdFocused: Boolean;
begin
  Result := Assigned(FCmdLineMgr) and FCmdLineMgr.Focused;
end;

const
  { Fallback FAR VGA palette when Theme is nil. With Theme assigned, chrome
    goes through IThemeRenderer ? do not add new c* uses on Theme paths. }
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cDirFg    = TAlphaColor($FFFFFFFF);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cInactiveCursorBg = TAlphaColor($FF1A3A6A);
  cFrameActive = TAlphaColor($FF55FFFF);
  cFrameIdle   = TAlphaColor($FFAAAAAA);
  cPanelBg     = TAlphaColor($FF0000AA);
  cDesktopBg   = TAlphaColor($FF000000);
  cMenuFg      = TAlphaColor($FF000000);
  cMenuBg      = TAlphaColor($FF00AAAA);
  cMenuHot     = TAlphaColor($FFFFFF55);
  cScrollFg    = TAlphaColor($FFAAAAAA);
  cScrollThumb = TAlphaColor($FF00AAAA);
  cCmdFg       = TAlphaColor($FFAAAAAA);
  cCmdBg       = TAlphaColor($FF000000);
  cRuleFg      = TAlphaColor($FF00AAAA);
  cSelectedFg  = TAlphaColor($FFFFFF55); // FAR marked: yellow on blue
  cSelectedBg  = TAlphaColor($FF0000AA);
  cHeaderFg    = TAlphaColor($FF55FFFF);

constructor TDualPanelWindow.Create(const ATheme: IThemeRenderer; AId: Cardinal);
begin
  inherited Create(ATheme, AId);
  FAlive := True;
  ShellIconsSetOnReady(
    procedure
    begin
      if FAlive then
        NotifyChanged;
    end);
  FHostWindowId := BindHostInvalidate(
    procedure
    begin
      if FAlive then
        Invalidate;
    end);
  FVfs := CreateDefaultVfs;
  FLeftModel := TFilePanelModel.Create(FVfs, cPanelWindowIdLeft);
  FRightModel := TFilePanelModel.Create(FVfs, cPanelWindowIdRight);
  FLeftModel.SetOnInvalidate(ModelInvalidated);
  FRightModel.SetOnInvalidate(ModelInvalidated);
  FNavigateSub := MessageBus.Subscribe(cTopicPanelNavigate, HandlePluginNavigate);
  FReloadSub := MessageBus.Subscribe(cTopicPanelReload, HandlePluginReload);
  FLeftWatch := TDirectoryWatcher.Create;
  FRightWatch := TDirectoryWatcher.Create;
  FLeftWatch.OnChanged := HostLeftDirWatch;
  FRightWatch.OnChanged := HostRightDirWatch;
  FWatchPending[psLeft] := False;
  FWatchPending[psRight] := False;
  FDocuments := TObjectDictionary<Cardinal, TEditorWindow>.Create([]);
  FTerminals := TObjectDictionary<Cardinal, TTerminalWorkspaceWindow>.Create([]);
  FDialog := TDialogHost.Create(ATheme);
  FDialog.OnChanged := DialogChanged;
  FDialogKind := hdkNone;
  BindDialogControllers;
  FFreeText := '';
  FFreeRoot := '';
  FFreeGen := 0;
  FLastClickCol := -1;
  FLastClickRow := -1;
  FLastClickTick := 0;
  FDragArmed := False;
  FDragStartCol := -1;
  FDragStartRow := -1;
  SetLength(FDragUris, 0);
  FTabDragKind := 0;
  FTabDragFrom := -1;
  FTabDragHover := -1;
  FTabDragArmed := False;
  FTabDragActive := False;
  FTabDragStartCol := -1;
  FTabDragStartRow := -1;
  FDropHighlightActive := False;
  FDropHighlightRow := -1;
  FNextTabId := 1;
  FDrivePreviewActive := False;
  FDrivePreviewSide := psLeft;
  FDrivePreviewLetter := #0;
  BindRuntimeControllers;
  SeedDefaultWorkspaces;
  SyncWindowTitle;
  ReloadActiveRows;
  BindKeymapHost;
  BindClickHost;
  BindDrawHost;
  BindPanelHost;
  BindDragHost;
  BindEmbeddedHost;
  BindCmdLineDrawHost;
  BindStatusHost;
  BindFreeInputHost;
  BindModalInputHost;
  BindFilesDrawHost;
end;

function TDualPanelWindow.ExportSessionState: TDualPanelWindowState;
begin
  Result := TDualPanelTabManager.ExportPanelsSession(FState);
end;

procedure TDualPanelWindow.ApplySessionState(const AState: TDualPanelWindowState);
var
  W: Integer;
  Panel: TPanelState;
  Filtered: TDualPanelWindowState;
begin
  if Length(AState.WorkspaceTabs) = 0 then
    Exit;
  ClearAllDocuments;
  ClearAllTerminals;
  Filtered := TDualPanelTabManager.FilterImportedSession(AState);
  if Length(Filtered.WorkspaceTabs) = 0 then
    Exit;

  CloseSearchUi;
  CloseJobUi;
  CloseDrivePopup;
  CloseUserMenu;
  CloseSortMenu;
  CloseColumnModeMenu;
  CloseStub;
  if Assigned(FLeftModel) then
    FLeftModel.Close;
  if Assigned(FRightModel) then
    FRightModel.Close;
  FState := Filtered;
  if (FState.ActiveWorkspaceIndex < 0) or
     (FState.ActiveWorkspaceIndex > High(FState.WorkspaceTabs)) then
    FState.ActiveWorkspaceIndex := 0;
  for W := 0 to High(FState.WorkspaceTabs) do
  begin
    TDualPanelTabManager.RestoreBothVisibleIfHidden(FState.WorkspaceTabs[W]);
    Panel := FState.WorkspaceTabs[W].State.LeftPanel;
    SeedPanelDriveDirs(Panel);
    FState.WorkspaceTabs[W].State.LeftPanel := Panel;
    Panel := FState.WorkspaceTabs[W].State.RightPanel;
    SeedPanelDriveDirs(Panel);
    FState.WorkspaceTabs[W].State.RightPanel := Panel;
  end;
  FNextTabId := TDualPanelTabManager.NextIdAfterSession(FState);
  SetCmdFocused(False);
  FPendingSelectName := '';
  SyncWindowTitle;
  ReloadActiveRows;
  NotifyChanged;
end;

destructor TDualPanelWindow.Destroy;
begin
  FAlive := False;
  ShellIconsSetOnReady(nil);
  if Assigned(FNavigateSub) then
  begin
    FNavigateSub.Unsubscribe;
    FNavigateSub := nil;
  end;
  if Assigned(FReloadSub) then
  begin
    FReloadSub.Unsubscribe;
    FReloadSub := nil;
  end;
  UnbindHostInvalidate(FHostWindowId);
  FHostWindowId := 0;
  CancelFolderSize;
  ClearAllDocuments;
  FreeAndNil(FDocuments);
  ClearAllTerminals;
  FreeAndNil(FTerminals);
  if Assigned(FLeftWatch) then
  begin
    FLeftWatch.OnChanged := nil;
    FLeftWatch.Close;
    FreeAndNil(FLeftWatch);
  end;
  if Assigned(FRightWatch) then
  begin
    FRightWatch.OnChanged := nil;
    FRightWatch.Close;
    FreeAndNil(FRightWatch);
  end;
  CloseSearchUi;
  CloseJobUi;
  CloseDrivePopup;
  FreeAndNil(FFolderSizeMgr);
  FreeAndNil(FSelHelper);
  FreeAndNil(FCmdLineMgr);
  FreeAndNil(FDrivePopupCtrl);
  FreeAndNil(FHistoryPopupCtrl);
  FreeAndNil(FDirSync);
  FreeAndNil(FSearchDlg);
  FreeAndNil(FJobDialogs);
  FreeAndNil(FJobs);
  FreeAndNil(FSearchUi);
  FreeAndNil(FFileOps);
  FreeAndNil(FSettings);
  FreeAndNil(FCmdHistory);
  FreeAndNil(FFileHistory);
  FreeAndNil(FFolderHistory);
  FreeAndNil(FFolderHotlist);
  FreeAndNil(FWorkspaceLibrary);
  FreeAndNil(FSshConnections);
  FreeAndNil(FUserAssociations);
  FreeAndNil(FColorCoding);
  FreeAndNil(FKeymapDlg);
  FreeAndNil(FMenus);
  // After FMenus: the popup only points into this tree.
  FreeAndNil(FUserMenuHost);
  FreeAndNil(FTopMenu);
  if Assigned(FLeftModel) then
  begin
    FLeftModel.SetOnInvalidate(nil);
    FLeftModel.Close;
  end;
  if Assigned(FRightModel) then
  begin
    FRightModel.SetOnInvalidate(nil);
    FRightModel.Close;
  end;
  if Assigned(FDialog) then
  begin
    FDialog.OnChanged := nil;
    FDialog.Close;
    FreeAndNil(FDialog);
  end;
  if Assigned(FHelp) then
  begin
    FHelp.OnChanged := nil;
    FreeAndNil(FHelp);
  end;
  FreeAndNil(FFilterPopup);
  if Assigned(FChecksumToken) then
    FChecksumToken.Cancel;
  if Assigned(FQuickText) then
  begin
    FQuickText.OnChanged := nil;
    FreeAndNil(FQuickText);
  end;
  FLeftModel := nil;
  FRightModel := nil;
  FVfs := nil;
  inherited Destroy;
end;

procedure TDualPanelWindow.RebuildBuffer;
var
  Desk: TAlphaColor;
begin
  if (Area.Width < 2) or (Area.Height < 2) then
  begin
    FNeedRebuild := False;
    Exit;
  end;
  if Assigned(Theme) then
    Desk := Theme.DesktopColor
  else
    Desk := cDesktopBg;
  // No outer MDI frame ? Host fills desktop; Theme owns Dual Panel chrome.
  FillGridRect(Buffer, 0, 0, Area.Width - 1, Area.Height - 1, ' ', cFileFg, Desk);
  DrawContent;
  FNeedRebuild := False;
end;

function TDualPanelWindow.ActiveWorkspace: TDualPanelWorkspaceTab;
begin
  if (Length(FState.WorkspaceTabs) = 0) or
     (FState.ActiveWorkspaceIndex < 0) or
     (FState.ActiveWorkspaceIndex > High(FState.WorkspaceTabs)) then
  begin
    Result.Id := 0;
    Result.Title := '';
    Result.State.ActiveSide := psLeft;
    Result.State.LeftVisible := True;
    Result.State.RightVisible := True;
    Result.State.LeftPanel.ActiveTabIndex := 0;
    SetLength(Result.State.LeftPanel.Tabs, 0);
    Result.State.RightPanel.ActiveTabIndex := 0;
    SetLength(Result.State.RightPanel.Tabs, 0);
    Exit;
  end;
  Result := FState.WorkspaceTabs[FState.ActiveWorkspaceIndex];
end;

procedure TDualPanelWindow.SaveActiveWorkspace(const AWs: TDualPanelWorkspaceTab);
begin
  if (FState.ActiveWorkspaceIndex < 0) or
     (FState.ActiveWorkspaceIndex > High(FState.WorkspaceTabs)) then
    Exit;
  FState.WorkspaceTabs[FState.ActiveWorkspaceIndex] := AWs;
end;

function TDualPanelWindow.ActivePanel(var AWs: TDualPanelWorkspaceTab): TPanelState;
begin
  if AWs.State.ActiveSide = psLeft then
    Result := AWs.State.LeftPanel
  else
    Result := AWs.State.RightPanel;
end;

procedure TDualPanelWindow.SetActivePanel(var AWs: TDualPanelWorkspaceTab;
  const APanel: TPanelState);
begin
  if AWs.State.ActiveSide = psLeft then
    AWs.State.LeftPanel := APanel
  else
    AWs.State.RightPanel := APanel;
end;

function TDualPanelWindow.ModelForSide(ASide: TPanelSide): IPanelModel;
begin
  if ASide = psLeft then
    Result := FLeftModel
  else
    Result := FRightModel;
end;

function TDualPanelWindow.RowsForSide(ASide: TPanelSide): TPanelRows;
var
  M: IPanelModel;
  I, N: Integer;
begin
  M := ModelForSide(ASide);
  if not Assigned(M) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  N := M.ItemCount;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := M.GetRow(I);
end;

function TDualPanelWindow.GetActiveRowContext(out AWs: TDualPanelWorkspaceTab;
  out APanel: TPanelState; out ATab: TTab; out ARows: TPanelRows): Boolean;
begin
  AWs := ActiveWorkspace;
  APanel := ActivePanel(AWs);
  ATab := ActiveTab(APanel);
  ARows := RowsForSide(AWs.State.ActiveSide);
  Result := Length(ARows) > 0;
end;

function TDualPanelWindow.GetActiveRow(out AWs: TDualPanelWorkspaceTab;
  out APanel: TPanelState; out ATab: TTab; out ARows: TPanelRows;
  out ARow: TPanelRow; out AIdx: Integer): Boolean;
begin
  Result := GetActiveRowContext(AWs, APanel, ATab, ARows);
  if not Result then
    Exit;
  AIdx := EnsureRange(ATab.CursorIndex, 0, High(ARows));
  ARow := ARows[AIdx];
end;

function TDualPanelWindow.CanStartOperation: Boolean;
begin
  Result := not (Assigned(FDialog) and FDialog.Visible)
    and not (Assigned(FSearchUi) and (FSearchUi.Phase <> spNone))
    and not (Assigned(FJobs) and FJobs.BlocksNewOperation);
end;

function TDualPanelWindow.KeymapActiveSide: TPanelSide;
begin
  Result := ActiveWorkspace.State.ActiveSide;
end;

procedure TDualPanelWindow.KeymapToggleConsole;
begin
  if Assigned(FOnToggleConsole) then
    FOnToggleConsole(Self);
end;

procedure TDualPanelWindow.KeymapRequestQuit;
begin
  if Assigned(FOnQuitRequest) then
    FOnQuitRequest(Self);
end;

procedure TDualPanelWindow.BindKeymapHost;
begin
  FKeymapHost.ActiveSide := KeymapActiveSide;
  FKeymapHost.CopyFullPathToClipboard := CopyFullPathToClipboard;
  FKeymapHost.ToggleConsole := KeymapToggleConsole;
  FKeymapHost.RequestQuit := KeymapRequestQuit;
  FKeymapHost.TogglePanelVisible := TogglePanelVisible;
  FKeymapHost.ApplySortMode := ApplySortMode;
  FKeymapHost.OpenSortMenu := OpenSortMenu;
  FKeymapHost.ToggleDrivePopup := ToggleDrivePopup;
  FKeymapHost.HistoryBack := HistoryBack;
  FKeymapHost.HistoryForward := HistoryForward;
  FKeymapHost.OpenFolderHistoryDialog := OpenFolderHistoryDialog;
  FKeymapHost.OpenFileHistoryDialog := OpenFileHistoryDialog;
  FKeymapHost.OpenCmdHistoryDialog := OpenCmdHistoryDialog;
  FKeymapHost.OpenFolderHotlistDialog := OpenFolderHotlistDialog;
  FKeymapHost.BeginFolderHotlistAdd := BeginFolderHotlistAdd;
  FKeymapHost.OpenWorkspaceLibraryDialog := OpenWorkspaceLibraryDialog;
  FKeymapHost.BeginWorkspaceLibrarySave := BeginWorkspaceLibrarySave;
  FKeymapHost.OpenSshConnectionsDialog := OpenSshConnectionsDialog;
  FKeymapHost.OpenUserAssociationsDialog := OpenUserAssociationsDialog;
  FKeymapHost.BeginBranchView := BeginBranchView;
  FKeymapHost.BeginLiveFilter := BeginLiveFilter;
  FKeymapHost.OpenSearchDialog := OpenSearchDialog;
  FKeymapHost.OpenDirSync := OpenDirSync;
  FKeymapHost.OpenJobList := OpenJobList;
  FKeymapHost.OpenTerminalProfileDialog := OpenTerminalProfileDialog;
  FKeymapHost.OpenConsoleProfileDialog := OpenConsoleProfileDialog;
  FKeymapHost.SyncConsoleDirNow := SyncConsoleDirNow;
  FKeymapHost.ToggleShowHidden := ToggleShowHidden;
  FKeymapHost.OpenColumnModeMenu := OpenColumnModeMenu;
  FKeymapHost.ApplyColumnMode := ApplyColumnMode;
  FKeymapHost.ToggleAdjacentInfoPanel := ToggleAdjacentInfoPanel;
  FKeymapHost.ToggleQuickView := ToggleQuickView;
  FKeymapHost.SwapPanels := SwapPanels;
  FKeymapHost.EqualizeOtherPanelToActive := EqualizeOtherPanelToActive;
  FKeymapHost.EqualizeActivePanelFromOther := EqualizeActivePanelFromOther;
  FKeymapHost.FocusCommandLine := FocusCommandLine;
  FKeymapHost.RunDetached := RunDetached;
  FKeymapHost.InsertPanelItemToCmdLine := InsertPanelItemToCmdLine;
  FKeymapHost.BeginSelectByMask := BeginSelectByMask;
  FKeymapHost.ApplySelectByExtension := ApplySelectByExtension;
  FKeymapHost.OpenHelp := OpenHelp;
  FKeymapHost.OpenUserMenu := OpenUserMenu;
  FKeymapHost.BeginPackZip := BeginPackZip;
  FKeymapHost.BeginUnpackZip := BeginUnpackZip;
  FKeymapHost.OpenViewOrEdit := OpenViewOrEdit;
  FKeymapHost.BeginNewFile := BeginNewFile;
  FKeymapHost.BeginJob := BeginJob;
  FKeymapHost.BeginRename := BeginRename;
  FKeymapHost.BeginCopyInPlace := BeginCopyInPlace;
  FKeymapHost.BeginMkDir := BeginMkDir;
  FKeymapHost.BeginCreateLink := BeginCreateLink;
  FKeymapHost.BeginSetAttributes := BeginSetAttributes;
  FKeymapHost.ShowProperties := ShowProperties;
  FKeymapHost.ExternalView := ExternalView;
  FKeymapHost.ExternalEdit := ExternalEdit;
  FKeymapHost.BeginCompareFiles := BeginCompareFiles;
  FKeymapHost.CompareFolders := CompareFolders;
  FKeymapHost.OpenExternalToolsDialog := OpenExternalToolsDialog;
  FKeymapHost.BeginChecksums := BeginChecksums;
  FKeymapHost.NavigateToRecycleBin := NavigateToRecycleBin;
  FKeymapHost.RestoreCursorItemFromRecycleBin := RestoreCursorItemFromRecycleBin;
  FKeymapHost.ActivateSide := ActivateSide;
  FKeymapHost.NewPanelTab := NewPanelTab;
  FKeymapHost.ClosePanelTabOnSide := ClosePanelTabOnSide;
  FKeymapHost.CalculateFolderSize := CalculateFolderSizeUnderCursor;
  FKeymapHost.TogglePanelConsoleMode := TogglePanelConsoleMode;
  FKeymapHost.NextWorkspace := NextWorkspace;
  FKeymapHost.PrevWorkspace := PrevWorkspace;
  FKeymapHost.ReloadKeymapProfile := ReloadKeymapProfile;
  FKeymapHost.OpenPluginListDialog := OpenPluginListDialog;
  FKeymapHost.OpenColorCodingDialog := OpenColorCodingDialog;
  FKeymapHost.OpenKeymapDialog := OpenKeymapDialog;
  FKeymapHost.OpenThemeDialog := OpenThemeDialog;
  FKeymapHost.OpenColumnsConfigDialog := OpenColumnsConfigDialog;
  FKeymapHost.OpenDisplayDialog := OpenDisplayDialog;
  FKeymapHost.OpenAboutDialog := OpenAboutDialog;
  FKeymapHost.EditGotoLine := EditGotoLine;
  FKeymapHost.EditFind := EditFind;
  FKeymapHost.EditFindReplace := EditFindReplace;
  FKeymapHost.EditEncoding := EditEncoding;
  FKeymapHost.EditUndo := EditUndo;
  FKeymapHost.EditRedo := EditRedo;
  FKeymapHost.EditHexToggle := EditHexToggle;
  FKeymapHost.EditCopy := EditCopy;
  FKeymapHost.EditCut := EditCut;
  FKeymapHost.EditPaste := EditPaste;
  FKeymapHost.NavigateActiveToDriveRoot := NavigateActiveToDriveRoot;
  FKeymapHost.RefreshActive := RefreshActive;
  FKeymapHost.SelectAllActive := SelectAllActive;
  FKeymapHost.InvertSelectionActive := InvertSelectionActive;
  FKeymapHost.MoveCursor := MoveCursor;
  FKeymapHost.MoveCursorWithSelect := MoveCursorWithSelect;
  FKeymapHost.ToggleInsertSelect := ToggleInsertSelect;
  FKeymapHost.SubmitCommandLine := SubmitCommandLine;
  FKeymapHost.HandleCmdLineInput := HandleCmdLineInput;
end;

procedure TDualPanelWindow.BindClickHost;
begin
  FClickHost.Invalidate := Invalidate;
  FClickHost.NotifyChanged := NotifyChanged;
  FClickHost.HandleTopMenuClick := ClickHandleTopMenu;
  FClickHost.SelectWorkspaceAtCol := SelectWorkspaceAtCol;
  FClickHost.BeginRenameWorkspaceAtCol := BeginRenameWorkspaceAtCol;
  FClickHost.HandleDocumentClick := ClickHandleDocument;
  FClickHost.HandleTerminalClick := ClickHandleTerminal;
  FClickHost.HandleFunctionBarClick := HandleFunctionBarClick;
  FClickHost.HandleDialogClick := ClickHandleDialog;
  FClickHost.SyncColorPickerHex := ClickSyncColorPicker;
  FClickHost.LayoutSearchUi := ClickLayoutSearch;
  FClickHost.SearchBounds := ClickSearchBounds;
  FClickHost.CloseSearchUi := CloseSearchUi;
  FClickHost.CloseStub := CloseStub;
  FClickHost.HandleUserMenuClick := FMenus.HandleUserMenuClick;
  FClickHost.HandleSortMenuClick := FMenus.HandleSortMenuClick;
  FClickHost.HandleColumnModeMenuClick := FMenus.HandleColumnModeMenuClick;
  FClickHost.HandleDrivePopupClick := HandleDrivePopupClick;
  FClickHost.LayoutJobPopup := ClickLayoutJob;
  FClickHost.JobBounds := ClickJobBounds;
  FClickHost.RequestJobCancel := FJobs.RequestCancel;
  FClickHost.BackgroundJob := FJobs.BackgroundJob;
  FClickHost.CloseJobUi := CloseJobUi;
  FClickHost.CancelOverwriteAsk := ClickCancelOverwrite;
  FClickHost.CancelDeleteAsk := ClickCancelDelete;
  FClickHost.CancelIOErrorAsk := ClickCancelIOError;
  FClickHost.ReloadActiveRows := ReloadActiveRows;
  FClickHost.OpenJobList := OpenJobList;
  FClickHost.SetCmdFocused := SetCmdFocused;
  FClickHost.ClickCmdLine := ClickCmdLine;
  FClickHost.NewWorkspace := NewWorkspace;
  FClickHost.ActivateSide := ActivateSide;
  FClickHost.SelectPanelTabAtCol := SelectPanelTabAtCol;
  FClickHost.NewPanelTabOnSide := NewPanelTabOnSide;
  FClickHost.NavigatePanelToDrive := NavigatePanelToDrive;
  FClickHost.ApplyHeaderSort := ApplyHeaderSort;
end;

procedure TDualPanelWindow.BindDrawHost;
begin
  FDrawHost.DrawDrivePopup := DrawDrivePopup;
  FDrawHost.DrawHistoryPopup := DrawHistoryPopup;
  FDrawHost.DrawJobPopup := DrawJobPopup;
  FDrawHost.DrawUserMenu := DrawUserMenu;
  FDrawHost.DrawSortMenu := DrawSortMenu;
  FDrawHost.DrawColumnModeMenu := DrawColumnModeMenu;
  FDrawHost.DrawStub := DrawStub;
  FDrawHost.DrawSearchUi := DrawSearchUi;
  FDrawHost.DrawDialog := DrawHostDialog;
  FDrawHost.DrawSubmenu := DrawHostSubmenu;
end;

procedure TDualPanelWindow.BindPanelHost;
begin
  FPanelHost.DrawInfo := DrawPanelInfoContent;
  FPanelHost.DrawQuickView := DrawQuickViewContent;
  FPanelHost.DrawDriveLetters := DrawPanelDriveLetters;
  FPanelHost.DrawFiles := DrawPanelFiles;
end;

procedure TDualPanelWindow.BindDragHost;
begin
  FDragHost.HitWorkspaceTab := HitWorkspaceTabAtCol;
  FDragHost.HitPanelTab := HitPanelTabAtCol;
  FDragHost.NotifyChanged := NotifyChanged;
  FDragHost.CancelFileDrag := CancelFileDrag;
end;

procedure TDualPanelWindow.BindEmbeddedHost;
begin
  FEmbeddedHost.CloseDocument := CloseHostDocument;
  FEmbeddedHost.CloseTerminal := CloseHostTerminal;
  FEmbeddedHost.RemoveWorkspace := RemoveWorkspaceTabAt;
end;

procedure TDualPanelWindow.BindCmdLineDrawHost;
begin
  FCmdLineDrawHost.ResolveStripColors := CmdLineStripColors;
  FCmdLineDrawHost.ResolveFocusAccent := CmdLineFocusAccent;
end;

procedure TDualPanelWindow.BindStatusHost;
begin
  FStatusHost.ChromeContext := ChromeContext;
end;

procedure TDualPanelWindow.PreviewCycleActiveDrive(ADelta: Integer);
begin
  PreviewCyclePanelDrive(ActiveWorkspace.State.ActiveSide, ADelta);
end;

procedure TDualPanelWindow.ClearCmdLineOnEsc;
begin
  FCmdLineMgr.Clear;
  SetCmdFocused(False);
  NotifyChanged;
end;

function TDualPanelWindow.TryPasteClipboardToCmdLine: Boolean;
begin
  Result := Assigned(FCmdLineMgr);
  if Result then
  begin
    FCmdLineMgr.InsertText(ClipboardGet);
    NotifyChanged;
  end;
end;

procedure TDualPanelWindow.HostRestoreGrayOpKey(var AKey: Word; var AKeyChar: Char);
begin
  RestoreGrayOpKey(AKey, AKeyChar);
end;

procedure TDualPanelWindow.BindFreeInputHost;
begin
  FFreeInputHost.CancelDrivePreview := CancelDrivePreview;
  FFreeInputHost.CloseQuickView := CloseQuickView;
  FFreeInputHost.ClearCmdLineOnEsc := ClearCmdLineOnEsc;
  FFreeInputHost.HandleFilterInput := HandleFilterInput;
  FFreeInputHost.DispatchKeymapPrimary := HandleKeymapActionPrimary;
  FFreeInputHost.PreviewCycleDrive := PreviewCycleActiveDrive;
  FFreeInputHost.NavigateActiveToDriveRoot := NavigateActiveToDriveRoot;
  FFreeInputHost.TryPasteClipboard := TryPasteClipboardToCmdLine;
  FFreeInputHost.RestoreGrayOpKey := HostRestoreGrayOpKey;
  FFreeInputHost.BeginSelectByMask := BeginSelectByMask;
  FFreeInputHost.InvertSelectionActive := InvertSelectionActive;
  FFreeInputHost.ApplySelectByExtension := ApplySelectByExtension;
  FFreeInputHost.ApplySelectAllFiles := ApplySelectAllFiles;
  FFreeInputHost.ApplySelectByName := ApplySelectByName;
  FFreeInputHost.HandleQuickSearchInput := HandleQuickSearchInput;
  FFreeInputHost.HandleCmdLineInput := HandleCmdLineInput;
  FFreeInputHost.FocusCommandLine := FocusCommandLine;
  FFreeInputHost.SwitchSide := SwitchSide;
  FFreeInputHost.NewPanelTab := NewPanelTab;
  FFreeInputHost.NewWorkspace := NewWorkspace;
  FFreeInputHost.NextPanelTab := NextPanelTab;
  FFreeInputHost.RefreshActive := RefreshActive;
  FFreeInputHost.SelectAllActive := SelectAllActive;
  FFreeInputHost.TryHotlistJump := FFolderHotlist.TryHandleHotkeyJump;
  FFreeInputHost.DispatchKeymapFunctionKeys := HandleKeymapActionFunctionKeys;
  FFreeInputHost.OpenViewOrEdit := OpenViewOrEdit;
end;

procedure TDualPanelWindow.BindModalInputHost;
begin
  FModalInputHost.FocusedOrDefaultButtonId := FDialog.FocusedOrDefaultButtonId;
  FModalInputHost.DialogCommand := DialogCommand;
  FModalInputHost.HandleHotlistList := FFolderHotlist.HandleListInput;
  FModalInputHost.HandleWorkspaceList := FWorkspaceLibrary.HandleListInput;
  FModalInputHost.HandleSshConnectionsList := FSshConnections.HandleListInput;
  FModalInputHost.HandleAssociationsList := FUserAssociations.HandleListInput;
  FModalInputHost.HandleColorList := FColorCoding.HandleListInput;
  FModalInputHost.HandleColorEdit := FColorCoding.HandleEditInput;
  FModalInputHost.HandleKeymapList := FKeymapDlg.HandleListInput;
  FModalInputHost.HandleCmdHistoryFilter := FCmdHistory.HandleFilterInput;
  FModalInputHost.HandleFileHistoryList := FFileHistory.HandleListInput;
  FModalInputHost.HandleDialogWidget := FDialog.HandleInput;
  FModalInputHost.DialogDropDownOpen := FDialog.DropDownOpen;
  FModalInputHost.RecordDialogHistory := FDialog.RecordInputHistory;
  FModalInputHost.SyncColorPickerHex := FColorCoding.SyncHexFromPreset;
end;

procedure TDualPanelWindow.DrawHostFilesHeaders(const ABounds: TRectI;
  const APanel: TPanelState);
begin
  uDualPanelDrawUtils.DrawPanelColumnHeaders(
    Buffer, ABounds, APanel.ColumnMode, APanel.SortColumn, APanel.SortDescending,
    Theme);
end;

procedure TDualPanelWindow.DrawHostFilesList(const AListBounds: TRectI;
  const ATab: TTab; AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide);
begin
  uDualPanelDrawUtils.DrawPanelList(
    Buffer, AListBounds, ATab, AActive, AMode, ModelForSide(ASide), Theme);
end;

procedure TDualPanelWindow.DrawHostFilesScroll(AX, ATop, ABottom, APos, ACount,
  AViewH: Integer);
begin
  DrawScrollBar(AX, ATop, ABottom, APos, ACount, AViewH, False);
end;

procedure TDualPanelWindow.BindFilesDrawHost;
begin
  FFilesDrawHost.ResolveChrome := ResolveChrome;
  FFilesDrawHost.DrawDriveLetters := DrawPanelDriveLetters;
  FFilesDrawHost.DrawHeaders := DrawHostFilesHeaders;
  FFilesDrawHost.DrawList := DrawHostFilesList;
  FFilesDrawHost.DrawScrollBar := DrawHostFilesScroll;
  FFilesDrawHost.DrawQuickSearch := DrawQuickSearchField;
  FFilesDrawHost.DrawFilter := DrawFilterField;
end;

procedure TDualPanelWindow.HostSetDialogKind(AKind: THostDialogKind);
begin
  FDialogKind := AKind;
end;

procedure TDualPanelWindow.HostUnfocusCmd;
begin
  SetCmdFocused(False);
end;

procedure TDualPanelWindow.HostShowShellStub(const ATitle, ADetail: string);
begin
  OpenStub(skShellInfo, ATitle, ADetail);
end;

procedure TDualPanelWindow.HostWorkspaceEmptySave;
begin
  OpenStub(skShellInfo, 'Workspace', 'Nothing to save');
end;

function TDualPanelWindow.HostTryGetHotlistUri(out AUri: string): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  AUri := '';
  Ws := ActiveWorkspace;
  Result := Ws.Kind = wkPanels;
  if Result then
    AUri := ActiveTab(ActivePanel(Ws)).CurrentURI;
end;

function TDualPanelWindow.HostTryGetCmdHistory(out AItems: TArray<string>): Boolean;
begin
  Result := Assigned(FCmdLineMgr);
  if Result then
    AItems := FCmdLineMgr.GetHistoryItems
  else
    SetLength(AItems, 0);
end;

procedure TDualPanelWindow.HostApplyCmdHistory(const ACommand: string);
begin
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.SetText(ACommand);
end;

function TDualPanelWindow.HostGetActiveThemeId: string;
begin
  if Assigned(FOnGetActiveThemeId) then
    Result := FOnGetActiveThemeId
  else
    Result := '';
end;

procedure TDualPanelWindow.HostSelectTheme(const AThemeId: string);
begin
  if Assigned(FOnThemeSelect) then
    FOnThemeSelect(AThemeId);
end;

function TDualPanelWindow.HostGetDisplaySettings: TDisplaySettings;
begin
  if Assigned(FOnGetDisplaySettings) then
    Result := FOnGetDisplaySettings
  else
    Result := DefaultDisplaySettings;
end;

procedure TDualPanelWindow.HostApplyDisplaySettings(const ASettings: TDisplaySettings);
begin
  if Assigned(FOnApplyDisplaySettings) then
    FOnApplyDisplaySettings(ASettings);
end;

procedure TDualPanelWindow.HostOpenTerminal(const AProfileId, ACwd: string);
begin
  if Assigned(FOnOpenTerminal) then
    FOnOpenTerminal(AProfileId, ACwd);
end;

procedure TDualPanelWindow.HostSetConsoleProfile(const AProfileId: string);
begin
  if Assigned(FOnSetConsoleProfile) then
    FOnSetConsoleProfile(AProfileId);
end;

function TDualPanelWindow.HostGetConsoleProfile: string;
begin
  if Assigned(FOnGetConsoleProfile) then
    Result := FOnGetConsoleProfile()
  else
    Result := '';
end;

function TDualPanelWindow.HostActivePanelUri: string;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Result := ActiveTab(ActivePanel(Ws)).CurrentURI;
end;

function TDualPanelWindow.HostInPanelsWorkspace: Boolean;
begin
  Result := ActiveWorkspace.Kind = wkPanels;
end;

function TDualPanelWindow.HostLastSelectMask: string;
begin
  Result := '*.*';
  if Assigned(FSelHelper) then
    Result := FSelHelper.LastSelectMask;
end;

function TDualPanelWindow.HostSelectFolders: Boolean;
begin
  Result := False;
  if Assigned(FSelHelper) then
    Result := FSelHelper.SelectFolders;
end;

function TDualPanelWindow.HostTryGetCursorItem(out AName, AUri, ATargetUri: string;
  out AIsParent: Boolean): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
begin
  AName := '';
  AUri := '';
  ATargetUri := '';
  AIsParent := False;
  Result := False;
  Ws := ActiveWorkspace;
  Tab := ActiveTab(ActivePanel(Ws));
  Rows := RowsForSide(Ws.State.ActiveSide);
  if (Tab.CursorIndex < 0) or (Tab.CursorIndex > High(Rows)) then
    Exit;
  Row := Rows[Tab.CursorIndex];
  AName := Row.Text;
  AUri := Row.URI;
  ATargetUri := Row.TargetURI;
  AIsParent := Row.IsParent;
  Result := True;
end;

procedure TDualPanelWindow.HostRememberStubUri(const AUri: string);
begin
  if Assigned(FMenus) then
    FMenus.StubDetail := AUri;
end;

procedure TDualPanelWindow.HostCmdLineSubmit(const ACommand: string);
begin
  SubmitCommandLine;
end;

function TDualPanelWindow.HostCmdLineNames: TArray<string>;
begin
  if not HostInPanelsWorkspace then
    Exit(nil);
  Result := CollectVisibleRowNames(RowsForSide(ActiveWorkspace.State.ActiveSide));
end;

procedure TDualPanelWindow.HostFolderSizeProgress(ASide: TPanelSide;
  ACompleted, APending: Integer; AFolderBytes: Int64; const AFolderURI: string);
var
  M: IPanelModel;
begin
  M := ModelForSide(ASide);
  if Assigned(M) and (AFolderURI <> '') and (AFolderBytes >= 0) then
    M.SetRowSize(AFolderURI, AFolderBytes, FormatSizeShort(AFolderBytes));
  if Assigned(FMenus) and FMenus.StubVisible then
  begin
    FMenus.StubText := FolderSizeStubTitle;
    FMenus.StubDetail := Format('Selected folders: %s',
      [FormatSizeShort(FFolderSizeMgr.SumBytes)]);
    NotifyChanged;
  end;
  if (APending <= 0) and Assigned(FMenus) then
    FMenus.CloseStub;
end;

function TDualPanelWindow.HostPanelBounds(ASide: TPanelSide): TRectI;
begin
  if ASide = psLeft then
    Result := FLeftBounds
  else
    Result := FRightBounds;
end;

function TDualPanelWindow.HostPanelPath(ASide: TPanelSide): string;
var
  Ws: TDualPanelWorkspaceTab;
  P: TPanelState;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    P := Ws.State.LeftPanel
  else
    P := Ws.State.RightPanel;
  Result := ActiveTab(P).CurrentURI;
end;

function TDualPanelWindow.HostPanelDriveDirs(ASide: TPanelSide): TPanelDriveDirs;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Result := Ws.State.LeftPanel.DriveDirs
  else
    Result := Ws.State.RightPanel.DriveDirs;
end;

procedure TDualPanelWindow.HostOpenJobConfirm(const ATitle, AMessage: string);
var
  DestPath: string;
begin
  FDialogKind := hdkJobConfirm;
  if Assigned(FJobs) and (FJobs.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack]) then
  begin
    DestPath := FileUriToPath(FJobs.State.DestDirURI);
    if DestPath <> '' then
    begin
      if FJobs.Kind <> pjkPack then
        DestPath := IncludeTrailingPathDelimiter(DestPath);
    end
    else
      DestPath := FJobs.State.DestDirURI;
    FDialog.Open(BuildCopyMoveDialog(ATitle, AMessage, DestPath), DialogCommand);
  end
  else if Assigned(FJobs) and (FJobs.Kind = pjkDelete) then
  begin
    if FJobs.State.DeleteToRecycleBin then
      FDialog.Open(BuildDeleteDialog(ATitle, AMessage, T('ui.delete.okRecycle', 'Recycle'), False),
        DialogCommand)
    else
      FDialog.Open(BuildDeleteDialog(ATitle, AMessage, T('ui.delete.okWipe', 'Wipe'), True),
        DialogCommand);
  end
  else
    FDialog.Open(BuildConfirmDialog(ATitle, AMessage), DialogCommand);
end;

procedure TDualPanelWindow.HostOpenOverwriteAsk(const APath, ANewLine,
  AExistingLine: string);
begin
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if not CloseJobProgressForReplacement then
    begin
      FJobAskDeferred := True;
      Exit;
    end;
  end;
  FJobAskDeferred := False;
  FDialogKind := hdkOverwriteAsk;
  FDialog.Open(BuildOverwriteAskDialog(APath, ANewLine, AExistingLine), DialogCommand);
end;

procedure TDualPanelWindow.HostOpenDeleteError(const APath, AHeadline, AQuestion,
  AErrorLine: string; AOfferPermanent: Boolean);
begin
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if not CloseJobProgressForReplacement then
    begin
      FJobAskDeferred := True;
      Exit;
    end;
  end;
  FJobAskDeferred := False;
  FDialogKind := hdkDeleteError;
  FDialog.Open(BuildDeleteErrorDialog(AHeadline, APath, AQuestion, AErrorLine,
    AOfferPermanent), DialogCommand);
end;

procedure TDualPanelWindow.HostOpenIOErrorAsk(const AHeadline, APath,
  AErrorLine: string);
begin
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if not CloseJobProgressForReplacement then
    begin
      FJobAskDeferred := True;
      Exit;
    end;
  end;
  FJobAskDeferred := False;
  FDialogKind := hdkIOError;
  FDialog.Open(BuildIOErrorDialog(AHeadline, APath, AErrorLine), DialogCommand);
end;

procedure TDualPanelWindow.HostJobFinished(ASuccess: Boolean);
begin
  if FDialogKind = hdkJobProgress then
    CloseJobProgressForReplacement;
  if (FDialogKind in [hdkJobConfirm, hdkOverwriteAsk, hdkOverwriteRename,
      hdkDeleteError, hdkIOError]) and
     not (Assigned(FDialog) and FDialog.Visible) then
    FDialogKind := hdkNone;
  if Assigned(FDirSync) then
    FDirSync.NotifyJobFinished(ASuccess);
  // Same as pre-background-job FJobs.OnReloadPanels: always re-list both
  // panels. Origin matching is a hint only and must not skip this.
  ReloadActiveRows;
  if ASuccess then
    NotifyChanged;
end;

procedure TDualPanelWindow.HostClearJobSelection(const AOriginSrc: string);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Name: string;
  Side: TPanelSide;
begin
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  if (AOriginSrc <> '') and (not SameVfsUri(Tab.CurrentURI, AOriginSrc)) then
    Exit;
  Rows := RowsForSide(Side);
  Name := PendingSelectNameAtCursor(Rows, Tab.CursorIndex);
  if Name <> '' then
  begin
    FPendingSelectName := Name;
    FPendingSelectSide := Side;
  end;
  TabClearSelection(Tab);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.HostReloadJobPanels(const AOriginSrc, AOriginDst: string);
begin
  ReloadActiveRows;
end;

function TDualPanelWindow.CloseJobProgressForReplacement: Boolean;
begin
  Result := FDialogKind = hdkJobProgress;
  if not Result then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    FDialog.Close;
  FDialogKind := hdkNone;
  FJobProgressRes := '';
end;

procedure TDualPanelWindow.OpenJobProgress(const AJob: TPanelJobState);
begin
  if not Assigned(FDialog) then
    Exit;
  FDialogKind := hdkJobProgress;
  FJobProgressRes := JobProgressResourceName(AJob);
  FDialog.Open(BuildJobProgressDialog(AJob), DialogCommand);
end;

procedure TDualPanelWindow.SyncJobProgressDialog;
var
  Job: TPanelJobState;
  ResName: string;
  DialogOpen: Boolean;
begin
  if FSyncingJobProgress then
    Exit;
  FSyncingJobProgress := True;
  try
    if not Assigned(FJobs) or not FJobs.TryProgressDialogState(Job) then
    begin
      if FDialogKind = hdkJobProgress then
        CloseJobProgressForReplacement;
      Exit;
    end;
    DialogOpen := Assigned(FDialog) and FDialog.Visible;
    if DialogOpen and (FDialogKind <> hdkJobProgress) then
      Exit;
    ResName := JobProgressResourceName(Job);
    if DialogOpen and (FJobProgressRes = ResName) then
      ApplyJobProgressToDialog(FDialog, Job)
    else
      OpenJobProgress(Job);
  finally
    FSyncingJobProgress := False;
  end;
end;

procedure TDualPanelWindow.FlushPendingJobAsk;
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  if not Assigned(FJobs) then
    Exit;
  if FJobAskDeferred then
  begin
    FJobAskDeferred := False;
    FJobs.ReplayCurrentAsk;
    Exit;
  end;
  FJobs.TryOpenNextAsk;
end;

procedure TDualPanelWindow.OpenJobList;
var
  Lines: TArray<string>;
begin
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if not CloseJobProgressForReplacement then
      Exit;
  end;
  if not Assigned(FJobs) then
    Exit;
  FDialogKind := hdkJobList;
  Lines := FJobs.ListLines;
  FDialog.Open(BuildJobListDialog(Lines, 0), DialogCommand);
end;

function TDualPanelWindow.HostApplyFindResults(const ARoot, AMask: string;
  const AHits: TArray<TFindHit>): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  ActiveURI, Sid: string;
begin
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  ActiveURI := Tab.CurrentURI;
  if IsFindUri(ActiveURI) and
     UpdateFindSession(FindSessionIdFromUri(ActiveURI), ARoot, AMask, AHits) then
  begin
    Tab.Title := FindSessionTitle(ActiveURI);
    Tab.CursorIndex := 0;
    Tab.ScrollOffset := 0;
    TabClearSelection(Tab);
    SetActiveTab(Panel, Tab);
    SetActivePanel(Ws, Panel);
    SaveActiveWorkspace(Ws);
    LoadSide(Side);
    Exit(True);
  end;
  Sid := RegisterFindSession(ARoot, AMask, AHits);
  NavigateActiveTo(MakeFindSessionUri(Sid));
  Result := True;
end;

function TDualPanelWindow.HostSearchBlocked: Boolean;
begin
  Result := (Assigned(FJobs) and FJobs.BlocksNewOperation) or
    (Assigned(FDialog) and FDialog.Visible);
end;

procedure TDualPanelWindow.HostPrepareSearchUi;
begin
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;
  if Assigned(FMenus) and FMenus.UserMenuVisible then
    CloseUserMenu;
  if Assigned(FMenus) and FMenus.StubVisible then
    CloseStub;
  SetCmdFocused(False);
end;

function TDualPanelWindow.HostIsAlive: Boolean;
begin
  Result := FAlive;
end;

procedure TDualPanelWindow.HostMenuSortSelect(AColumn: TPanelSortColumn);
begin
  ApplySortMode(ActiveWorkspace.State.ActiveSide, AColumn);
end;

procedure TDualPanelWindow.HostMenuColumnModeSelect(AMode: TPanelColumnMode);
begin
  ApplyColumnMode(ActiveWorkspace.State.ActiveSide, AMode);
end;

function TDualPanelWindow.OverlayDialogVisible: Boolean;
begin
  Result := Assigned(FDialog) and FDialog.Visible;
end;

function TDualPanelWindow.OverlaySearchActive: Boolean;
begin
  Result := Assigned(FSearchUi) and (FSearchUi.Phase <> spNone);
end;

function TDualPanelWindow.OverlayJobActive: Boolean;
begin
  Result := Assigned(FJobs) and FJobs.ShowsOverlay;
end;

function TDualPanelWindow.OverlayStubVisible: Boolean;
begin
  Result := Assigned(FMenus) and FMenus.StubVisible;
end;

function TDualPanelWindow.OverlayUserMenuVisible: Boolean;
begin
  Result := Assigned(FMenus) and FMenus.UserMenuVisible;
end;

function TDualPanelWindow.OverlaySortMenuVisible: Boolean;
begin
  Result := Assigned(FMenus) and FMenus.SortMenuVisible;
end;

function TDualPanelWindow.OverlayColumnModeMenuVisible: Boolean;
begin
  Result := Assigned(FMenus) and FMenus.ColumnModeMenuVisible;
end;

function TDualPanelWindow.OverlayDrivePopupVisible: Boolean;
begin
  Result := Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible;
end;

procedure TDualPanelWindow.HostLeftDirWatch;
begin
  HandleDirWatch(psLeft);
end;

procedure TDualPanelWindow.HostRightDirWatch;
begin
  HandleDirWatch(psRight);
end;

procedure TDualPanelWindow.HostNavigateSide(ASide: TPanelSide; const AURI: string);
begin
  NavigateSideTo(ASide, AURI);
end;

procedure TDualPanelWindow.BindDialogControllers;
begin
  FColorCoding := TColorCodingDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog);
  FKeymapDlg := TKeymapDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog);
  FFolderHotlist := TFolderHotlistDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostTryGetHotlistUri, NavigateActiveTo,
    HostUnfocusCmd);
  FWorkspaceLibrary := TWorkspaceLibraryDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, NavigateActiveTo, HostUnfocusCmd,
    HostWorkspaceEmptySave);
  FSshConnections := TSshConnectionsDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, NavigateActiveTo, OpenSshTerminal,
    HostUnfocusCmd);
  FUserAssociations := TUserAssociationsDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostUnfocusCmd);
  FUserMenuHost := TUserMenuDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, HostUserMenuContext,
    HostRunUserMenuCommand,
    procedure(ARoot: TUserMenuItem; const ATitle: string)
    begin
      if Assigned(FMenus) then
        FMenus.OpenUserMenu(ARoot, ATitle);
    end,
    procedure(ASelectIndex: Integer)
    begin
      if Assigned(FMenus) then
        FMenus.UserMenuItemsChanged(ASelectIndex);
    end,
    ActiveLocalPath);
  FFolderHistory := TFolderHistoryDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, NavigateActiveTo);
  FCmdHistory := TCmdHistoryDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostTryGetCmdHistory, HostApplyCmdHistory);
  FFileHistory := TFileHistoryDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostOpenHistoryFile, HostGotoHistoryFile);
  FSettings := TSettingsDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostGetActiveThemeId, HostSelectTheme,
    ActiveLocalPath, HostOpenTerminal, HostSetConsoleProfile, HostGetConsoleProfile,
    HostShowShellStub,
    HostGetDisplaySettings, HostApplyDisplaySettings);
  FFileOps := TFileOpDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    HostUnfocusCmd, HostActivePanelUri, HostInPanelsWorkspace,
    HostShowShellStub, HostLastSelectMask, HostSelectFolders, HostTryGetCursorItem,
    HostRememberStubUri, ConfirmMkDir, ConfirmNewFile, ConfirmRename,
    ConfirmCopyInPlace, ApplySelectMask, ConfirmCreateLink, ApplySetAttributes);
end;

procedure TDualPanelWindow.BindRuntimeControllers;
begin
  FCmdLineMgr := TDualPanelCmdLineManager.Create(HostCmdLineSubmit, NotifyChanged);
  FCmdLineMgr.OnGetNames := HostCmdLineNames;
  FChecksumAlgoIndex := Ord(caSHA256);
  FFilterPopup := THistoryPopup.Create;
  FFilterPopup.OnRemove :=
    procedure(AMask: string)
    begin
      DialogHistoryRemove(cLiveFilterHistory, AMask);
    end;
  FCmdLineMgr.OnGetBaseDir := ActiveLocalPath;
  FCmdLineMgr.OnOpenHistoryPopup := OpenCmdHistoryPopup;
  FPendingSelectName := '';
  FPendingSelectSide := psLeft;
  FSelHelper := TDualPanelSelectionHelper.Create;
  FConsoleMode := False;
  FTerminalCloseOnExit := True;
  FAutoSyncConsoleCwd := False;
  FCursorVisible := True;
  FFolderSizeMgr := TFolderSizeCalculationManager.Create(
    HostFolderSizeProgress, NotifyChanged);
  FDrivePopupCtrl := TDrivePopupController.Create(Theme, Invalidate,
    HostPanelBounds, HostPanelPath, HostPanelDriveDirs, HostNavigateSide);
  FHistoryPopupCtrl := THistoryPopupController.Create(Theme, Invalidate,
    HostPanelBounds);
  FJobs := TPanelJobList.Create(Theme, FVfs, NotifyChanged,
    HostOpenJobConfirm, HostOpenOverwriteAsk, HostOpenDeleteError,
    HostOpenIOErrorAsk, HostJobFinished, HostReloadJobPanels, HostClearJobSelection,
    HostJobUiClosed, PauseDirWatchesForJob);
  FJobAskDeferred := False;
  FJobDialogs := TJobDialogController.Create(FDialog, FJobs, DialogCommand,
    HostSetDialogKind);
  FSearchUi := TSearchController.Create(Theme, NotifyChanged, GotoFileLocation,
    HostApplyFindResults, FlushDirWatchPending);
  FSearchDlg := TSearchDialogController.Create(FDialog, FSearchUi, DialogCommand,
    HostSetDialogKind, HostSearchBlocked, HostPrepareSearchUi,
    HostActivePanelUri, NotifyChanged);
  FDirSync := TDirSyncDialogController.Create(FDialog, FJobs, DialogCommand,
    HostSetDialogKind, CloseTransientUiBeforeDialog, HostShowShellStub,
    CloseStub, NotifyChanged, HostIsAlive);
  FMenus := TMenuStubController.Create(Theme, NotifyChanged,
    HostUserMenuAction, HostPanelBounds, KeymapActiveSide);
  FMenus.SetOnSortSelect(HostMenuSortSelect);
  FMenus.SetOnColumnModeSelect(HostMenuColumnModeSelect);
  FInputOverlays := [
    TInputOverlayEntry.Make(OverlayStubVisible, HandleStubInput),
    TInputOverlayEntry.Make(OverlayDialogVisible, HandleModalDialogInput),
    TInputOverlayEntry.Make(OverlaySearchActive, HandleSearchInput),
    TInputOverlayEntry.Make(OverlayJobActive, HandleJobInput),
    TInputOverlayEntry.Make(OverlayUserMenuVisible, HandleUserMenuInput),
    TInputOverlayEntry.Make(OverlaySortMenuVisible, HandleSortMenuInput),
    TInputOverlayEntry.Make(OverlayColumnModeMenuVisible, HandleColumnModeMenuInput),
    TInputOverlayEntry.Make(OverlayDrivePopupVisible, HandleDrivePopupInput)
  ];
  FTopMenu := TTopMenuController.Create(Theme, Invalidate, ExecuteTopMenuAction);
  FTopMenu.OnIsActionEnabled :=
    function(AAction: TTopMenuAction): Boolean
    begin
      Result := TopMenuActionIsEnabled(AAction);
    end;
  MenuRegistry.AttachController(FTopMenu);
end;

procedure TDualPanelWindow.SeedDefaultWorkspaces;
var
  Ws: TDualPanelWorkspaceTab;
  Home, Docs, Proj: string;
begin
  Home := HomeUri;
  Docs := DocumentsUri;
  Proj := ProjectsUri;

  Ws.Id := 1;
  Ws.Title := T('ui.workspace.home', 'Home');
  Ws.Kind := wkPanels;
  Ws.DocURI := '';
  Ws.ViewOnly := False;
  Ws.OriginWorkspaceId := 0;
  Ws.State.LeftPanel := MakePanelState([Home, Docs]);
  Ws.State.RightPanel := MakePanelState([Proj, Home]);
  Ws.State.ActiveSide := psLeft;
  Ws.State.LeftVisible := True;
  Ws.State.RightVisible := True;

  SetLength(FState.WorkspaceTabs, 2);
  FState.WorkspaceTabs[0] := Ws;
  FState.ActiveWorkspaceIndex := 0;

  Ws.Id := 2;
  Ws.Title := T('ui.workspace.work', 'Work');
  Ws.Kind := wkPanels;
  Ws.DocURI := '';
  Ws.ViewOnly := False;
  Ws.OriginWorkspaceId := 0;
  Ws.State.LeftPanel := MakePanelState([Proj]);
  Ws.State.RightPanel := MakePanelState([Docs]);
  Ws.State.ActiveSide := psRight;
  Ws.State.LeftVisible := True;
  Ws.State.RightVisible := True;
  FState.WorkspaceTabs[1] := Ws;
end;

procedure TDualPanelWindow.CmdLineStripColors(out AFg, ABg: TAlphaColor);
begin
  // FAR-style prompt: always light text on black, independent of the
  // panel palette (pcpInfoStrip follows WindowBg, which is blue/grey/etc.).
  AFg := cCmdFg;
  ABg := cCmdBg;
end;

procedure TDualPanelWindow.CmdLineFocusAccent(out AFg, ABg: TAlphaColor);
begin
  if Assigned(Theme) then
    Theme.ResolveDialogRowColors(True, AFg, ABg)
  else
  begin
    AFg := cCursorFg;
    ABg := cCursorBg;
  end;
end;

procedure TDualPanelWindow.DrawHostDialog(AWidth, AHeight: Integer);
begin
  FDialog.Draw(Buffer, AWidth, AHeight);
end;

procedure TDualPanelWindow.DrawHostSubmenu(AWidth: Integer);
begin
  FTopMenu.DrawSubmenu(Buffer, AWidth);
end;

function TDualPanelWindow.ClickOverlaySnapshot: TClickOverlaySnapshot;
begin
  Result := Default(TClickOverlaySnapshot);
  Result.WorkspaceKind := ActiveWorkspace.Kind;
  Result.DialogVisible := Assigned(FDialog) and FDialog.Visible;
  Result.DialogKind := FDialogKind;
  Result.AreaWidth := Area.Width;
  Result.AreaHeight := Area.Height;
  Result.ConsoleMode := FConsoleMode;
  Result.CmdFocused := CmdFocused;
  Result.TopMenuAssigned := Assigned(FTopMenu);
  Result.TopMenuActive := Assigned(FTopMenu) and FTopMenu.Active;
  if Assigned(FSearchUi) then
    Result.SearchPhase := FSearchUi.Phase
  else
    Result.SearchPhase := spNone;
  Result.StubVisible := Assigned(FMenus) and FMenus.StubVisible;
  Result.UserMenuVisible := Assigned(FMenus) and FMenus.UserMenuVisible;
  Result.SortMenuVisible := Assigned(FMenus) and FMenus.SortMenuVisible;
  Result.ColumnModeMenuVisible := Assigned(FMenus) and FMenus.ColumnModeMenuVisible;
  Result.DrivePopupVisible := Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible;
  if Assigned(FJobs) then
  begin
    Result.JobsPhase := FJobs.Phase;
    Result.JobsKind := FJobs.Kind;
    Result.JobsShowsOverlay := FJobs.ShowsOverlay;
  end
  else
  begin
    Result.JobsPhase := pjpNone;
    Result.JobsKind := pjkNone;
    Result.JobsShowsOverlay := False;
  end;
end;

function TDualPanelWindow.ClickHandleTopMenu(ACol, ARow: Integer): Boolean;
begin
  Result := FTopMenu.HandleClick(ACol, ARow);
end;

function TDualPanelWindow.ClickHandleDocument(ACol, ARow: Integer;
  AShift: TShiftState): Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  if Assigned(Doc) then
    Result := Doc.HandleClick(ACol, ARow, AShift)
  else
    Result := True;
end;

function TDualPanelWindow.ClickHandleTerminal(ACol, ARow: Integer;
  AShift: TShiftState): Boolean;
var
  Term: TTerminalWorkspaceWindow;
begin
  Term := ActiveTerminal;
  if Assigned(Term) then
    Result := Term.HandleClick(ACol, ARow, AShift)
  else
    Result := True;
end;

function TDualPanelWindow.ClickHandleDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
begin
  Result := FDialog.HandleClick(ACol, ARow, AShift);
end;

procedure TDualPanelWindow.ClickSyncColorPicker;
begin
  FColorCoding.SyncHexFromPreset;
end;

procedure TDualPanelWindow.ClickLayoutSearch(AWidth, AHeight: Integer);
begin
  FSearchUi.LayoutSearchUi(AWidth, AHeight);
end;

function TDualPanelWindow.ClickSearchBounds: TRectI;
begin
  Result := FSearchUi.Bounds;
end;

procedure TDualPanelWindow.ClickLayoutJob(AWidth, AHeight: Integer);
begin
  FJobs.LayoutJobPopup(AWidth, AHeight);
end;

function TDualPanelWindow.ClickJobBounds: TRectI;
begin
  Result := FJobs.Bounds;
end;

procedure TDualPanelWindow.ClickCancelOverwrite;
begin
  FJobs.ResolveOverwriteAsk(jcaCancel, False);
end;

procedure TDualPanelWindow.ClickCancelDelete;
begin
  FJobs.ResolveDeleteAsk(jdaCancel);
end;

procedure TDualPanelWindow.ClickCancelIOError;
begin
  FJobs.ResolveIOErrorAsk(jioCancel);
end;

procedure TDualPanelWindow.ActivateSide(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Ws.State.ActiveSide := ASide;
  SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.ClosePanelTabOnSide(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  ClosePanelTab(ASide, Panel.ActiveTabIndex);
end;

procedure TDualPanelWindow.TogglePanelConsoleMode;
begin
  // Same FAR Ctrl+O path as the keymap: MainForm.ShowConsoleMode paints
  // TConsoleWindow over Dual Panel. Flipping FConsoleMode alone only
  // blanks DrawContent (dckConsole = F-keys + status) — a black screen.
  KeymapToggleConsole;
end;

procedure TDualPanelWindow.ReloadKeymapProfile;
begin
  ReloadKeymap('');
  NotifyChanged;
end;

procedure TDualPanelWindow.ReloadMenuStructure;
begin
  if Assigned(FTopMenu) then
    FTopMenu.BuildMenuStructure;
  NotifyChanged;
end;

procedure TDualPanelWindow.EditGotoLine;
begin
  if ActiveDocument <> nil then
    ActiveDocument.OpenGotoDialog;
end;

procedure TDualPanelWindow.EditFind;
begin
  if ActiveDocument <> nil then
    ActiveDocument.OpenFindPrompt;
end;

procedure TDualPanelWindow.EditFindReplace;
begin
  if ActiveDocument <> nil then
    ActiveDocument.OpenReplaceDialog;
end;

procedure TDualPanelWindow.EditEncoding;
begin
  if ActiveDocument <> nil then
    ActiveDocument.OpenEncodingDialog;
end;

procedure TDualPanelWindow.EditUndo;
begin
  if ActiveDocument <> nil then
    ActiveDocument.UndoEdit;
end;

procedure TDualPanelWindow.EditRedo;
begin
  if ActiveDocument <> nil then
    ActiveDocument.RedoEdit;
end;

procedure TDualPanelWindow.EditHexToggle;
begin
  if ActiveDocument <> nil then
    ActiveDocument.ToggleHexMode;
end;

procedure TDualPanelWindow.ClipboardCopyFiles(ACut: Boolean);
var
  Uris, Paths: TArray<string>;
begin
  Uris := CollectActiveSources;
  if Length(Uris) = 0 then
    Exit;
  Paths := FileUrisToLocalPaths(Uris);
  FFileClipUris := Uris;
  FFileClipCut := ACut;
  ClipboardSetPanelItems(Paths, Uris, ACut);
  FFileClipSeq := GetClipboardSequenceNumber;
end;

function TDualPanelWindow.FileClipStillOurs: Boolean;
begin
  Result := (Length(FFileClipUris) > 0) and
    (GetClipboardSequenceNumber = FFileClipSeq);
end;

procedure TDualPanelWindow.ClipboardPasteFiles;
var
  Ws: TDualPanelWorkspaceTab;
  DestURI, Reason: string;
  Paths, Uris: TArray<string>;
  Cut: Boolean;
  Kind: TPanelJobKind;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  DestURI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  Cut := False;
  if not ClipboardGetPanelItems(Paths, Uris, Cut) then
  begin
    if not FileClipStillOurs then
      Exit;
    Uris := FFileClipUris;
    Cut := FFileClipCut;
  end
  else if Length(Uris) = 0 then
    Uris := LocalPathsToFileUris(Paths);
  if Length(Uris) = 0 then
    Exit;
  if Cut then
    Kind := pjkMove
  else
    Kind := pjkCopy;
  Reason := JobDestRejectedReason(Kind, DestURI);
  if Reason <> '' then
  begin
    OpenStub(skShellInfo, JobDestFailTitle(Kind),
      'Current panel must be a local folder');
    Exit;
  end;
  BeginTransferJob(Uris, DestURI, Kind);
  if Cut then
  begin
    ClipboardClearPanelItems;
    SetLength(FFileClipUris, 0);
    FFileClipCut := False;
    FFileClipSeq := GetClipboardSequenceNumber;
  end;
end;

procedure TDualPanelWindow.EditCopy;
var
  Kind: TWorkspaceKind;
begin
  if CmdFocused then
  begin
    if Assigned(FCmdLineMgr) then
      FCmdLineMgr.CopyToClipboard;
    Exit;
  end;
  Kind := ActiveWorkspace.Kind;
  case Kind of
    wkPanels:
      ClipboardCopyFiles(False);
    wkDocument:
      if ActiveDocument <> nil then
        ActiveDocument.CopySelectionOrLine;
    wkTerminal:
      ;
  end;
end;

procedure TDualPanelWindow.EditCut;
var
  Kind: TWorkspaceKind;
begin
  if CmdFocused then
  begin
    if Assigned(FCmdLineMgr) then
      FCmdLineMgr.CutToClipboard;
    Exit;
  end;
  Kind := ActiveWorkspace.Kind;
  case Kind of
    wkPanels:
      ClipboardCopyFiles(True);
    wkDocument:
      if ActiveDocument <> nil then
        ActiveDocument.CutSelectionOrLine;
    wkTerminal:
      ;
  end;
end;

procedure TDualPanelWindow.EditPaste;
var
  Kind: TWorkspaceKind;
begin
  if CmdFocused then
  begin
    if Assigned(FCmdLineMgr) then
      FCmdLineMgr.PasteFromClipboard;
    Exit;
  end;
  Kind := ActiveWorkspace.Kind;
  case Kind of
    wkPanels:
      if ClipboardHasPanelItems or FileClipStillOurs then
        ClipboardPasteFiles
      else
        TryPasteClipboardToCmdLine;
    wkDocument:
      if ActiveDocument <> nil then
        ActiveDocument.PasteText;
    wkTerminal:
      ;
  end;
end;

function TDualPanelWindow.TopMenuActionIsEnabled(AAction: TTopMenuAction): Boolean;
var
  Ctx: TTopMenuEnableContext;
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  Ctx.Kind := ActiveWorkspace.Kind;
  Ctx.DocReady := Assigned(Doc) and Doc.MenuDocReady;
  Ctx.CanEdit := Assigned(Doc) and Doc.MenuCanEdit;
  Ctx.HexBinaryLocked := Assigned(Doc) and Doc.MenuHexBinaryLocked;
  Ctx.CanUndo := Assigned(Doc) and Doc.MenuCanUndo;
  Ctx.CanRedo := Assigned(Doc) and Doc.MenuCanRedo;
  Ctx.CmdFocused := CmdFocused;
  Result := TopMenuActionEnabled(AAction, Ctx);
end;

function TDualPanelWindow.MakePanelState(const AUris: array of string): TPanelState;
var
  I: Integer;
begin
  Result.ActiveTabIndex := 0;
  SetLength(Result.Tabs, Length(AUris));
  ClearPanelDriveDirs(Result.DriveDirs);
  Result.ColumnMode := pcmFull;
  Result.SortColumn := pscNone;
  Result.SortDescending := False;
  Result.ViewKind := pvkFiles;
  Result.ShowHiddenFiles := True;
  for I := 0 to High(AUris) do
  begin
    Result.Tabs[I] := MakeTab(FNextTabId, FileUriTitle(AUris[I]), AUris[I]);
    Inc(FNextTabId);
  end;
  SeedPanelDriveDirs(Result);
end;

procedure TDualPanelWindow.NotifyChanged;
begin
  SyncJobProgressDialog;
  Invalidate;
  if Assigned(FOnContentChanged) then
    FOnContentChanged(Self);
end;

procedure TDualPanelWindow.ModelInvalidated(AWindowId: Integer);
var
  M: IPanelModel;
  BothModelsIdle: Boolean;
begin
  if not FAlive then
    Exit;
  // Side-scoped invalidate (PANEL_PLUGIN WindowId): left=1, right=2.
  case AWindowId of
    cPanelWindowIdLeft:
      FPlainTotals[psLeft].Valid := False;
    cPanelWindowIdRight:
      FPlainTotals[psRight].Valid := False;
  else
    InvalidatePlainTotals;
  end;
  // Wait for the target side's list to finish ? Open() first notifies with
  // LoadingRows, and applying then would clear FPendingSelectName too early.
  if FPendingSelectName <> '' then
  begin
    M := ModelForSide(FPendingSelectSide);
    if Assigned(M) and not M.IsLoading then
      ApplyPendingSelect(FPendingSelectSide, RowsForSide(FPendingSelectSide));
  end
  else
  begin
    // After delete/move CursorIndex may be past EOF ? without clamp the
    // cursor highlight disappears (no row matches Idx = CursorIndex).
    case AWindowId of
      cPanelWindowIdLeft:
        begin
          M := ModelForSide(psLeft);
          if Assigned(M) and not M.IsLoading then
            ClampCursorSide(psLeft);
        end;
      cPanelWindowIdRight:
        begin
          M := ModelForSide(psRight);
          if Assigned(M) and not M.IsLoading then
            ClampCursorSide(psRight);
        end;
    else
      begin
        M := ModelForSide(psLeft);
        if Assigned(M) and not M.IsLoading then
          ClampCursorSide(psLeft);
        M := ModelForSide(psRight);
        if Assigned(M) and not M.IsLoading then
          ClampCursorSide(psRight);
      end;
    end;
  end;
  // A deferred watch may have arrived while a list load was in flight.
  BothModelsIdle := Assigned(FLeftModel) and not FLeftModel.IsLoading and
    Assigned(FRightModel) and not FRightModel.IsLoading;
  if (FWatchPending[psLeft] or FWatchPending[psRight]) and BothModelsIdle then
    FlushDirWatchPending;
  case AWindowId of
    cPanelWindowIdLeft:
      MaybeAskArchivePassword(psLeft);
    cPanelWindowIdRight:
      MaybeAskArchivePassword(psRight);
  else
    begin
      MaybeAskArchivePassword(psLeft);
      MaybeAskArchivePassword(psRight);
    end;
  end;
  NotifyChanged;
end;

procedure TDualPanelWindow.HandlePluginNavigate(const ATopic: string;
  const APayload: TObject);
var
  Uri: string;
  Clear: Boolean;
begin
  if not FAlive then
    Exit;
  if not TryHostNavigatePayload(APayload, Uri, Clear) then
    Exit;
  if Clear and IsWorkspaceUri(Uri) then
    ClearWorkspaceLinks;
  NavigateActiveTo(Uri);
end;

procedure TDualPanelWindow.HandlePluginReload(const ATopic: string;
  const APayload: TObject);
var
  Uri: string;
begin
  if not FAlive then
    Exit;
  if TryHostNavigateUri(APayload, Uri) then
    ReloadSidesShowing(Uri);
end;

procedure TDualPanelWindow.ReloadSidesShowing(const AUri: string);
var
  Ws: TDualPanelWorkspaceTab;
begin
  if AUri = '' then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if SameVfsUri(ActiveTab(Ws.State.LeftPanel).CurrentURI, AUri) then
    LoadSide(psLeft);
  if SameVfsUri(ActiveTab(Ws.State.RightPanel).CurrentURI, AUri) then
    LoadSide(psRight);
end;

procedure TDualPanelWindow.MaybeAskArchivePassword(ASide: TPanelSide);
var
  M: IPanelModel;
  URI, Prompt, ArchName: string;
begin
  if DialogVisible then
    Exit;
  M := ModelForSide(ASide);
  if not Assigned(M) or M.IsLoading then
    Exit;
  URI := M.GetURI;
  if not IsSevenZipUri(URI) then
    Exit;
  if SameVfsUri(URI, FSkipArchivePasswordUri) then
    Exit;
  if M.GetLastError.Code <> vecAccessDenied then
  begin
    if SameVfsUri(URI, FArchivePasswordUri) then
      FArchivePasswordRetry := False;
    Exit;
  end;
  CloseTransientUiBeforeDialog;
  FArchivePasswordUri := URI;
  FArchivePasswordSide := ASide;
  if FArchivePasswordRetry then
    Prompt := 'Wrong password:'
  else
    Prompt := 'Password:';
  ArchName := TPath.GetFileName(ArchiveBasePath(URI));
  if ArchName = '' then
    ArchName := ArchiveBasePath(URI);
  FDialogKind := hdkArchivePassword;
  FDialog.Open(BuildArchivePasswordDialog(ArchName, Prompt), DialogCommand);
end;

procedure TDualPanelWindow.HandleArchivePasswordCommand(const AControlId,
  APassword: string);
var
  Parent, ArchPath: string;
  M: IPanelModel;
begin
  FDialog.Close;
  ArchPath := ArchiveBasePath(FArchivePasswordUri);
  if DialogCmdIsReject(AControlId) then
  begin
    FSkipArchivePasswordUri := FArchivePasswordUri;
    FArchivePasswordRetry := False;
    if ArchPath <> '' then
    begin
      FPendingSelectName := TPath.GetFileName(ArchPath);
      FPendingSelectSide := FArchivePasswordSide;
    end;
    Parent := ArchiveBaseDirUri(FArchivePasswordUri);
    if Parent <> '' then
      NavigateSideTo(FArchivePasswordSide, Parent, True);
    Exit;
  end;
  if not DialogCmdIsAccept(AControlId) then
    Exit;
  if not HostSetPluginSecret('mtn.7z', ArchPath, APassword) then
  begin
    OpenStub(skShellInfo, 'Archive password', 'Cannot pass password to plugin');
    Exit;
  end;
  FArchivePasswordRetry := True;
  M := ModelForSide(FArchivePasswordSide);
  if Assigned(M) then
    M.Refresh;
end;

procedure TDualPanelWindow.InvalidatePlainTotals;
begin
  FPlainTotals[psLeft].Valid := False;
  FPlainTotals[psRight].Valid := False;
end;

procedure TDualPanelWindow.EnsurePlainTotals(ASide: TPanelSide; out ABytes: Int64;
  out AFiles, AFolders: Integer);
var
  M: IPanelModel;
  I, Count: Integer;
  Row: TPanelRow;
begin
  if FPlainTotals[ASide].Valid then
  begin
    ABytes := FPlainTotals[ASide].Bytes;
    AFiles := FPlainTotals[ASide].Files;
    AFolders := FPlainTotals[ASide].Folders;
    Exit;
  end;
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  M := ModelForSide(ASide);
  if Assigned(M) then
    Count := M.ItemCount
  else
    Count := 0;
  for I := 0 to Count - 1 do
  begin
    Row := M.GetRow(I);
    if Row.IsParent then
      Continue;
    if Row.IsDirectory then
    begin
      Inc(AFolders);
      if Row.Size > 0 then
        Inc(ABytes, Row.Size);
    end
    else
    begin
      Inc(AFiles);
      if Row.Size > 0 then
        Inc(ABytes, Row.Size);
    end;
  end;
  FPlainTotals[ASide].Bytes := ABytes;
  FPlainTotals[ASide].Files := AFiles;
  FPlainTotals[ASide].Folders := AFolders;
  FPlainTotals[ASide].Valid := True;
end;

procedure TDualPanelWindow.ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor);
var
  FallbackPal: TPanelChromePalette;
begin
  if Assigned(Theme) then
  begin
    Theme.ResolvePanelChromeColors(APart, AActive, AFg, ABg);
    Exit;
  end;
  FallbackPal.TextFg := cFileFg;
  FallbackPal.WindowBg := cPanelBg;
  FallbackPal.HeaderFg := cHeaderFg;
  FallbackPal.HeaderBg := cPanelBg;
  FallbackPal.PanelTabActiveFg := cCursorFg;
  FallbackPal.PanelTabActiveBg := cCursorBg;
  FallbackPal.BorderFocusFg := cFrameActive;
  FallbackPal.BorderNormalFg := cFrameIdle;
  FallbackPal.WorkspaceTabActiveFg := cCursorFg;
  FallbackPal.WorkspaceTabActiveBg := cCursorBg;
  FallbackPal.WorkspaceTabIdleFg := cFileFg;
  FallbackPal.WorkspaceTabIdleBg := cInactiveCursorBg;
  FallbackPal.HotMarkFg := cMenuHot;
  FallbackPal.CloseMarkFg := TAlphaColor($FFFF55FF);
  ResolveStandardPanelChromeColors(APart, AActive, FallbackPal, AFg, ABg);
end;

procedure TDualPanelWindow.LoadSide(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  M: IPanelModel;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  M := ModelForSide(ASide);
  if not Assigned(M) or (Tab.CurrentURI = '') then
    Exit;
  if (Tab.WorkspaceBackUri <> '') and
     SameVfsUri(Tab.CurrentURI, Tab.WorkspaceBackTarget) then
    M.SetWorkspaceReturnUri(Tab.WorkspaceBackUri)
  else
    M.SetWorkspaceReturnUri('');
  RememberPanelDriveDir(Panel.DriveDirs, Tab.CurrentURI);
  // Must write back to ASide ? SetActivePanel follows ActiveSide and would
  // corrupt the other panel when reloading the inactive side (dir-watch).
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  SyncSideSort(ASide);
  SyncSideShowHidden(ASide);
  M.Open(Tab.CurrentURI);
  FWatchPending[ASide] := False;
  SyncDirWatches;
end;

procedure TDualPanelWindow.ReloadActiveRows;
begin
  LoadSide(psLeft);
  LoadSide(psRight);
end;

// True for panel URI kinds that are virtual views with no real directory to
// watch (archives, find results, the temp panel, workspace links).
function IsVirtualDirWatchUri(const AURI: string): Boolean;
begin
  Result := HasArchiveChain(AURI) or IsFindUri(AURI) or IsTmpPanelUri(AURI) or
    IsWorkspaceUri(AURI);
end;

procedure TDualPanelWindow.SyncDirWatches;
var
  Ws: TDualPanelWorkspaceTab;
  URI, Path: string;
begin
  if not FAlive then
    Exit;
  Ws := ActiveWorkspace;
  if Assigned(FLeftWatch) then
  begin
    if Ws.State.LeftVisible then
    begin
      URI := ActiveTab(Ws.State.LeftPanel).CurrentURI;
      if IsVirtualDirWatchUri(URI) then
        Path := '' // virtual views: no dir-watch
      else
        Path := FileUriToPath(URI);
      FLeftWatch.SetPath(Path);
    end
    else
      FLeftWatch.SetPath('');
  end;
  if Assigned(FRightWatch) then
  begin
    if Ws.State.RightVisible then
    begin
      URI := ActiveTab(Ws.State.RightPanel).CurrentURI;
      if IsVirtualDirWatchUri(URI) then
        Path := ''
      else
        Path := FileUriToPath(URI);
      FRightWatch.SetPath(Path);
    end
    else
      FRightWatch.SetPath('');
  end;
end;

procedure TDualPanelWindow.PauseDirWatchesForJob;
begin
  if Assigned(FLeftWatch) then
    FLeftWatch.SetPath('');
  if Assigned(FRightWatch) then
    FRightWatch.SetPath('');
end;

procedure TDualPanelWindow.HostJobUiClosed;
begin
  FlushDirWatchPending;
  SyncDirWatches;
  FlushPendingJobAsk;
end;

procedure TDualPanelWindow.SoftReloadSide(ASide: TPanelSide; AForce: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  M: IPanelModel;
  Name: string;
begin
  if not FAlive then
    Exit;
  M := ModelForSide(ASide);
  if (not AForce) and Assigned(M) and M.IsLoading then
  begin
    FWatchPending[ASide] := True;
    Exit;
  end;

  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  // find:// is an in-memory snapshot ? disk-watch SoftReload races with a
  // second Alt+F7 (CloseSearchUi flush > Open(old) > Navigate(new)).
  if IsFindUri(Tab.CurrentURI) then
  begin
    FWatchPending[ASide] := False;
    Exit;
  end;
  Rows := RowsForSide(ASide);
  if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) and
     (not Rows[Tab.CursorIndex].IsParent) then
  begin
    // Do not overwrite a pending select aimed at the other panel (e.g. active
    // side after delete while FlushDirWatch SoftReloads the inactive side).
    if (FPendingSelectName = '') or (FPendingSelectSide = ASide) then
    begin
      Name := Rows[Tab.CursorIndex].Text;
      if (Name <> '') and (Name[Length(Name)] = '/') then
        Delete(Name, Length(Name), 1);
      FPendingSelectName := Name;
      FPendingSelectSide := ASide;
    end;
  end;

  FWatchPending[ASide] := False;
  LoadSide(ASide);
end;

procedure TDualPanelWindow.HandleDirWatch(ASide: TPanelSide);
var
  UiOwnedByModalWork: Boolean;
begin
  if not FAlive then
    Exit;
  // Defer while modal job/dialog/search owns the UI; flush later.
  UiOwnedByModalWork := (Assigned(FDialog) and FDialog.Visible) or
    (Assigned(FJobs) and FJobs.OwnsInput) or
    (Assigned(FSearchUi) and (FSearchUi.Phase in [spDialog, spRunning]));
  if UiOwnedByModalWork then
  begin
    FWatchPending[ASide] := True;
    Exit;
  end;
  SoftReloadSide(ASide);
end;

procedure TDualPanelWindow.FlushDirWatchPending;
var
  Side: TPanelSide;
begin
  if not FAlive then
    Exit;
  for Side := Low(TPanelSide) to High(TPanelSide) do
    if FWatchPending[Side] then
      HandleDirWatch(Side);
end;

procedure TDualPanelWindow.NavigateSideTo(ASide: TPanelSide; const AURI: string;
  AAddToHistory: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Canon, OldPath, NewPath, ParentPath: string;
  OldIsArch, NewIsArch, EitherSideIsVirtualView: Boolean;
begin
  if AURI = '' then
    Exit;
  Canon := ResolveVfsUri(AURI);
  Ws := ActiveWorkspace;
  Ws.State.ActiveSide := ASide;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  OldIsArch := HasArchiveChain(Tab.CurrentURI);
  NewIsArch := HasArchiveChain(Canon);
  EitherSideIsVirtualView := OldIsArch or NewIsArch or
    IsFindUri(Tab.CurrentURI) or IsFindUri(Canon);
  if SameVfsUri(Tab.CurrentURI, Canon) then
  begin
    if (not NewIsArch) and (not IsFindUri(Canon)) then
      RememberPanelDriveDir(Panel.DriveDirs, FileUriToPath(Canon));
    SetActivePanel(Ws, Panel);
    SaveActiveWorkspace(Ws);
    LoadSide(ASide);
    Exit;
  end;

  // Leaving a folder via "..": place cursor on that folder in the parent list.
  // Only THIS tab's workspace-enter marker, not a global dir-link lookup —
  // the other panel at the same disk path must `..` to the disk parent.
  if (Tab.WorkspaceBackUri <> '') and
     SameVfsUri(Tab.CurrentURI, Tab.WorkspaceBackTarget) and
     SameVfsUri(Canon, Tab.WorkspaceBackUri) then
  begin
    FPendingSelectName := WorkspaceLinkNameForTarget(Tab.CurrentURI);
    FPendingSelectSide := ASide;
  end
  else if EitherSideIsVirtualView then
  begin
    if SameVfsUri(Canon, ParentVfsUri(Tab.CurrentURI)) then
    begin
      // find:// parent is session root file URI ? match via FindSessionParentFileUri
      if IsFindUri(Tab.CurrentURI) then
      begin
        if SameVfsUri(Canon, FindSessionParentFileUri(Tab.CurrentURI)) then
        begin
          FPendingSelectName := '';
          FPendingSelectSide := ASide;
        end;
      end
      else
      begin
        FPendingSelectName := VfsUriTitle(Tab.CurrentURI);
        FPendingSelectSide := ASide;
      end;
    end
    else if IsFindUri(Tab.CurrentURI) and
            SameVfsUri(Canon, FindSessionParentFileUri(Tab.CurrentURI)) then
    begin
      FPendingSelectName := '';
      FPendingSelectSide := ASide;
    end;
  end
  else
  begin
    OldPath := FileUriToPath(Tab.CurrentURI);
    NewPath := FileUriToPath(Canon);
    RememberPanelDriveDir(Panel.DriveDirs, OldPath);
    ParentPath := FileUriToPath(ResolveFileUri(ParentFileUri(Tab.CurrentURI)));
    if (OldPath <> '') and SameText(NewPath, ParentPath) then
    begin
      FPendingSelectName := FileUriTitle(Tab.CurrentURI);
      FPendingSelectSide := ASide;
    end;
  end;

  UpdateWorkspaceBackMarker(Tab.WorkspaceBackUri, Tab.WorkspaceBackTarget,
    Tab.CurrentURI, Canon);
  Tab.CurrentURI := Canon;
  if IsFindUri(Canon) then
    Tab.Title := FindSessionTitle(Canon)
  else
    Tab.Title := VfsUriTitle(Canon);
  Tab.CursorIndex := 0;
  Tab.ScrollOffset := 0;
  TabClearSelection(Tab);
  FolderHistoryPush(Canon);
  if AAddToHistory then
  begin
    if (Tab.HistoryIndex >= 0) and (Tab.HistoryIndex < High(Tab.History)) then
      SetLength(Tab.History, Tab.HistoryIndex + 1);
    if (Length(Tab.History) = 0) or
       not SameVfsUri(Tab.History[High(Tab.History)], Canon) then
    begin
      SetLength(Tab.History, Length(Tab.History) + 1);
      Tab.History[High(Tab.History)] := Canon;
    end;
    Tab.HistoryIndex := High(Tab.History);
  end;
  if (not NewIsArch) and (not IsFindUri(Canon)) then
    RememberPanelDriveDir(Panel.DriveDirs, FileUriToPath(Canon));
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  LoadSide(ASide);
  NotifyShellCwdSync;
end;

procedure TDualPanelWindow.NavigateActiveTo(const AURI: string);
begin
  NavigateSideTo(ActiveWorkspace.State.ActiveSide, AURI, True);
end;

procedure TDualPanelWindow.SetActivePanelDir(const APath: string);
var
  Path: string;
begin
  Path := Trim(APath);
  if (Path = '') or not TDirectory.Exists(Path) then
    Exit;
  if ActiveWorkspace.Kind <> wkPanels then
    Exit;
  NavigateActiveTo(PathToFileUri(Path));
  NotifyChanged;
end;

function TDualPanelWindow.GetCommandHistoryItems: TArray<string>;
begin
  if Assigned(FCmdLineMgr) then
    Result := FCmdLineMgr.GetHistoryItems
  else
    SetLength(Result, 0);
end;

procedure TDualPanelWindow.RecordConsoleCommand(const ACommand: string);
begin
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.RecordExternalCommand(ACommand);
end;

procedure TDualPanelWindow.NavigateActiveToDriveRoot;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Path, Root, ArchPath, ArchDirURI: string;
  Letter: Char;
  FindData: TFindSessionData;
  Side: TPanelSide;
begin
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);

  // Inside an archive: leave it completely > folder that contains the archive.
  if HasArchiveChain(Tab.CurrentURI) then
  begin
    ArchPath := ArchiveBasePath(Tab.CurrentURI);
    ArchDirURI := ArchiveBaseDirUri(Tab.CurrentURI);
    if ArchDirURI = '' then
      Exit;
    if ArchPath <> '' then
    begin
      FPendingSelectName := TPath.GetFileName(ArchPath);
      FPendingSelectSide := Side;
    end;
    NavigateActiveTo(ArchDirURI);
    Exit;
  end;

  if IsFindUri(Tab.CurrentURI) then
  begin
    if TryGetFindSessionFromUri(Tab.CurrentURI, FindData) then
      Path := FindData.RootPath
    else
      Exit;
  end
  else
    Path := FileUriToPath(Tab.CurrentURI);
  if Path = '' then
    Exit;
  Root := ExtractFileDrive(Path);
  if Root = '' then
    Exit;
  // "D:" > "D:\"; UNC share root already usable with trailing delim.
  if (Length(Root) = 2) and (Root[2] = ':') then
  begin
    Letter := Root[1];
    Root := UpCase(Letter) + ':' + PathDelim;
  end
  else
    Root := IncludeTrailingPathDelimiter(Root);
  NavigateActiveTo(PathToFileUri(Root));
end;

procedure TDualPanelWindow.HistoryBack;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Side: TPanelSide;
begin
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  if Tab.HistoryIndex <= 0 then
  begin
    ShowHistoryPopup(Side, Tab);
    Exit;
  end;
  Dec(Tab.HistoryIndex);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  NavigateSideTo(Side, Tab.History[Tab.HistoryIndex], False);
  ShowHistoryPopup(Side, Tab);
end;

procedure TDualPanelWindow.HistoryForward;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Side: TPanelSide;
begin
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  if Tab.HistoryIndex >= High(Tab.History) then
  begin
    ShowHistoryPopup(Side, Tab);
    Exit;
  end;
  Inc(Tab.HistoryIndex);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  NavigateSideTo(Side, Tab.History[Tab.HistoryIndex], False);
  ShowHistoryPopup(Side, Tab);
end;

procedure TDualPanelWindow.ToggleInsertSelect;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if (not Row.IsParent) and (Row.URI <> '') then
    TabToggleSelected(Tab, Row.URI);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  MoveCursor(1);
end;

procedure TDualPanelWindow.MoveCursorWithSelect(ADelta: Integer;
  AExcludeLanding: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Side: TPanelSide;
  FromIdx, ToIdx, Lo, Hi, ViewH, Cols: Integer;
begin
  if not GetActiveRowContext(Ws, Panel, Tab, Rows) then
    Exit;
  Side := Ws.State.ActiveSide;
  FromIdx := EnsureRange(Tab.CursorIndex, 0, High(Rows));
  ToIdx := EnsureRange(FromIdx + ADelta, 0, High(Rows));
  if ShiftNavInvertRange(FromIdx, ToIdx, ADelta, AExcludeLanding, Lo, Hi) then
    TabToggleSelectedRange(Tab, Rows, Lo, Hi);
  Tab.CursorIndex := ToIdx;
  ViewH := ListViewHeight;
  if ViewH < 1 then
    ViewH := 1;
  Cols := ListColCountForSide(Side);
  EnsureCursorVisible(Tab, Length(Rows), ViewH, Cols);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.CopyFullPathToClipboard;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  R: TPanelRow;
  Paths, Keys: TArray<string>;
  Path, Text: string;
  I: Integer;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Ws.State.ActiveSide);
  SetLength(Paths, 0);

  if Length(Tab.SelectedURIs) > 0 then
  begin
    Keys := TabSelectionKeys(Tab);
    for R in Rows do
      if (not R.IsParent) and (R.URI <> '') and SelectionKeysHas(Keys, R.URI) then
      begin
        Path := PanelItemFullPath(R.URI, Tab.CurrentURI, False);
        if Path <> '' then
          Paths := Paths + [Path];
      end;
  end
  else if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
  begin
    R := Rows[Tab.CursorIndex];
    Path := PanelItemFullPath(R.URI, Tab.CurrentURI, R.IsParent);
    if Path <> '' then
      Paths := [Path];
  end;

  if Length(Paths) = 0 then
    Exit;
  Text := Paths[0];
  for I := 1 to High(Paths) do
    Text := Text + sLineBreak + Paths[I];
  ClipboardSet(Text);
end;

procedure TDualPanelWindow.SelectAllActive;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
begin
  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  TabSelectAllVisible(Tab, RowsForSide(Ws.State.ActiveSide));
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.InvertSelectionActive;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  TabInvertSelection(Tab, RowsForSide(Ws.State.ActiveSide));
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.BeginSelectByMask(AUnselect: Boolean);
begin
  FFileOps.BeginSelectByMask(AUnselect);
end;

procedure TDualPanelWindow.ApplySelectMask(const AMask: string; AUnselect: Boolean;
  ASelectFolders: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Mask: string;
begin
  Mask := Trim(AMask);
  if Mask = '' then
    Mask := '*.*';
  if Assigned(FSelHelper) then
  begin
    FSelHelper.LastSelectMask := Mask;
    FSelHelper.SelectFolders := ASelectFolders;
  end;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  if AUnselect then
    TabUnselectByMask(Tab, RowsForSide(Ws.State.ActiveSide), Mask, ASelectFolders)
  else
    TabSelectByMask(Tab, RowsForSide(Ws.State.ActiveSide), Mask, ASelectFolders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.ApplySelectAllFiles(AUnselect: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Folders: Boolean;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Folders := Assigned(FSelHelper) and FSelHelper.SelectFolders;
  if AUnselect then
    TabUnselectByMask(Tab, RowsForSide(Ws.State.ActiveSide), '*', Folders)
  else
    TabSelectByMask(Tab, RowsForSide(Ws.State.ActiveSide), '*', Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.ApplySelectByExtension(AUnselect: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Name, Ext, Mask: string;
  Folders: Boolean;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Ws.State.ActiveSide);
  if (Tab.CursorIndex < 0) or (Tab.CursorIndex > High(Rows)) then
    Exit;
  Row := Rows[Tab.CursorIndex];
  if Row.IsParent or Row.IsDirectory or (Row.URI = '') then
    Exit;
  Name := Row.Text;
  if (Name <> '') and (Name[Length(Name)] = '/') then
    Delete(Name, Length(Name), 1);
  Ext := ExtractFileExt(Name);
  if Ext = '' then
    Mask := '*.'
  else
    Mask := '*' + Ext;
  Folders := Assigned(FSelHelper) and FSelHelper.SelectFolders;
  if AUnselect then
    TabUnselectByMask(Tab, Rows, Mask, Folders)
  else
    TabSelectByMask(Tab, Rows, Mask, Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.ApplySelectByName(AUnselect: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Name: string;
  Folders: Boolean;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Ws.State.ActiveSide);
  if (Tab.CursorIndex < 0) or (Tab.CursorIndex > High(Rows)) then
    Exit;
  Row := Rows[Tab.CursorIndex];
  if Row.IsParent or (Row.URI = '') then
    Exit;
  Name := PanelRowMaskName(Row);
  if Name = '' then
    Exit;
  Folders := Assigned(FSelHelper) and FSelHelper.SelectFolders;
  TabSelectByNameStem(Tab, Rows, FileNameStem(Name), AUnselect, Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

function TDualPanelWindow.TryResolveCommandPath(const AText: string;
  out AURI: string): Boolean;
var
  Base: string;
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Base := FileUriToPath(ActiveTab(ActivePanel(Ws)).CurrentURI);
  Result := TryResolvePanelCommandPath(AText, Base, AURI);
end;

procedure TDualPanelWindow.SubmitCommandLine;
var
  URI, Text, Base, LowerText: string;
  Ws: TDualPanelWorkspaceTab;
begin
  if not Assigned(FCmdLineMgr) then
    Exit;
  Text := Trim(FCmdLineMgr.Text);
  if Text = '' then
  begin
    ActivateCurrent;
    Exit;
  end;

  LowerText := LowerCase(Text);
  if IsWslCommandString(LowerText) then
  begin
    FCmdLineMgr.Clear;
    SetCmdFocused(False);
    NotifyChanged;
    if Assigned(FOnOpenTerminal) then
      FOnOpenTerminal(Text, ActiveLocalPath);
    Exit;
  end;

  if TryResolveCommandPath(Text, URI) then
  begin
    FCmdLineMgr.Clear;
    NavigateActiveTo(URI);
  end
  else if (Pos(' ', Text) = 0) and (Pos(#9, Text) = 0) then
  begin
    // Bare token ? async Exists, then navigate or shell (no UI-thread disk I/O).
    Ws := ActiveWorkspace;
    Base := FileUriToPath(ActiveTab(ActivePanel(Ws)).CurrentURI);
    ResolveRelativeCommandAsync(Text, Base);
  end
  else
    RunConsoleCommand(Text);
end;

function TDualPanelWindow.PanelCommandCwd: string;
var
  Ws: TDualPanelWorkspaceTab;
  URI: string;
  FindData: TFindSessionData;
begin
  Ws := ActiveWorkspace;
  URI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  Result := FileUriToPath(URI);
  if HasArchiveChain(URI) then
    Result := TPath.GetDirectoryName(ArchiveBasePath(URI))
  else if IsFindUri(URI) then
  begin
    if TryGetFindSessionFromUri(URI, FindData) then
      Result := FindData.RootPath;
  end;
end;

procedure TDualPanelWindow.PushShellCwdSync;
var
  Ws: TDualPanelWorkspaceTab;
  URI, Path: string;
begin
  if not Assigned(FOnShellCwdSync) then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  URI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  // Archive / find: leave shell cwd at last local path (no silent cd).
  if HasArchiveChain(URI) or IsFindUri(URI) then
    Exit;
  Path := FileUriToPath(URI);
  if Path = '' then
    Exit;
  FOnShellCwdSync(Path);
end;

procedure TDualPanelWindow.NotifyShellCwdSync;
begin
  // By default the console and the active panel keep their own directory;
  // this only fires the automatic push when the user opted in.
  if FAutoSyncConsoleCwd then
    PushShellCwdSync;
end;

procedure TDualPanelWindow.SyncConsoleDirNow;
begin
  PushShellCwdSync;
end;

procedure TDualPanelWindow.RunConsoleCommand(const ACommand: string);
var
  Cmd, Cwd: string;
begin
  Cmd := Trim(ACommand);
  if Cmd = '' then
    Exit;
  Cwd := PanelCommandCwd;
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.Clear;
  // Leave cmdline unfocused so scroll/typing reach the Console buffer.
  SetCmdFocused(False);
  NotifyChanged;
  if Assigned(FOnRunCommand) then
    FOnRunCommand(Cmd, Cwd);
end;

procedure TDualPanelWindow.RunDetachedFromCmdLine(const AText, ACwd: string);
begin
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.Clear;
  SetCmdFocused(False);
  if not ShellRunDetached(AText, ACwd) then
    OpenStub(skShellInfo, 'Run failed', AText)
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.RunDetachedOpenFolder(const AUri: string;
  const ATab: TTab; AIsParent: Boolean);
var
  Path: string;
begin
  Path := PanelItemFullPath(AUri, ATab.CurrentURI, AIsParent);
  if (Path = '') or (not TDirectory.Exists(Path)) then
    Exit;
  if not ShellOpenFile(Path) then
    OpenStub(skShellInfo, 'Explorer failed', Path)
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.RunDetachedFile(const AUri: string);
var
  Path, Cmd, Cwd: string;
begin
  Path := FileUriToPath(AUri);
  if (Path = '') or (not TFile.Exists(Path)) then
    Exit;
  if Pos(' ', Path) > 0 then
    Cmd := '"' + Path + '"'
  else
    Cmd := Path;
  Cwd := TPath.GetDirectoryName(Path);
  if not ShellRunDetached(Cmd, Cwd) then
    OpenStub(skShellInfo, 'Run failed', Path)
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.RunDetached;
var
  Text, Cwd: string;
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
begin
  Text := '';
  if Assigned(FCmdLineMgr) then
    Text := Trim(FCmdLineMgr.Text);
  Cwd := PanelCommandCwd;

  if Text <> '' then
  begin
    RunDetachedFromCmdLine(Text, Cwd);
    Exit;
  end;

  // Empty cmdline > file/folder under cursor (separate process, not ConPTY).
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.URI = '' then
    Exit;

  // Directories and ".." > open in Explorer (shell folder open).
  // ".." opens the current panel folder, not the parent (FAR Shift+Enter semantics).
  if Row.IsDirectory or Row.IsParent then
  begin
    RunDetachedOpenFolder(Row.URI, Tab, Row.IsParent);
    Exit;
  end;

  RunDetachedFile(Row.URI);
end;

procedure TDualPanelWindow.CloseDrivePopup;
begin
  if Assigned(FDrivePopupCtrl) then
    FDrivePopupCtrl.Close;
end;

procedure TDualPanelWindow.ToggleDrivePopup(ASide: TPanelSide);
begin
  if Assigned(FDrivePopupCtrl) then
    FDrivePopupCtrl.Toggle(ASide);
end;

procedure TDualPanelWindow.DrawDrivePopup;
begin
  if Assigned(FDrivePopupCtrl) then
    FDrivePopupCtrl.Draw(Buffer);
end;

function TDualPanelWindow.HandleDrivePopupInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FDrivePopupCtrl) then
    Result := FDrivePopupCtrl.HandleInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

function TDualPanelWindow.HandleDrivePopupClick(ALocalCol, ALocalRow: Integer): Boolean;
begin
  if Assigned(FDrivePopupCtrl) then
    Result := FDrivePopupCtrl.HandleClick(ALocalCol, ALocalRow)
  else
    Result := False;
end;

procedure TDualPanelWindow.ShowHistoryPopup(ASide: TPanelSide; const ATab: TTab);
var
  Labels: TArray<string>;
  I: Integer;
begin
  if not Assigned(FHistoryPopupCtrl) then
    Exit;
  SetLength(Labels, Length(ATab.History));
  for I := 0 to High(ATab.History) do
    Labels[I] := FolderHistoryDisplayLabel(ATab.History[I]);
  FHistoryPopupCtrl.Show(ASide, Labels, ATab.HistoryIndex);
end;

procedure TDualPanelWindow.CloseHistoryPopup;
begin
  if Assigned(FHistoryPopupCtrl) then
    FHistoryPopupCtrl.Close;
end;

procedure TDualPanelWindow.DrawHistoryPopup;
begin
  if Assigned(FHistoryPopupCtrl) then
    FHistoryPopupCtrl.Draw(Buffer);
end;

procedure TDualPanelWindow.GotoFileLocation(const AFilePath: string);
var
  Path, Dir, Name: string;
begin
  // A found directory arrives with no trailing separator from uFindVfs, but
  // strip it anyway so ExtractFilePath yields the *parent* either way rather
  // than the directory itself.
  Path := ExcludeTrailingPathDelimiter(Trim(AFilePath));
  if Path = '' then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Path));
  Name := ExtractFileName(Path);
  if (Dir = '') or (Name = '') then
    Exit;
  FPendingSelectName := Name;
  FPendingSelectSide := ActiveWorkspace.State.ActiveSide;
  NavigateActiveTo(PathToFileUri(Dir));
end;

procedure TDualPanelWindow.ActivateCurrent;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  ArchiveKind: TArchiveExtensionKind;
  IsArchiveFile: Boolean;
  UserCommand: string;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  // Ask the registry which extensions currently navigate as an archive
  // (built-in zip/jar/apk plus whatever a loaded plugin's manifest declared
  // — see uVfsRegistry.RegisterArchiveExtension) instead of hardcoding the
  // extension list here.
  IsArchiveFile := (Row.URI <> '') and
    GlobalVfsRegistry.TryResolveArchiveKind(Row.Text, ArchiveKind);
  case ClassifyActivateCurrent(
    IsFindUri(Tab.CurrentURI) and (not Row.IsParent) and (Row.URI <> ''),
    Row.IsParent and (IsSystemFoldersUri(Tab.CurrentURI) or
      IsRecycleBinUri(Tab.CurrentURI)),
    Row.IsDirectory or Row.IsParent,
    IsArchiveFile,
    ResolveAssociationWithUserRules(Row.Text, False, UserCommand)) of
    ackFindGoto:
      GotoFileLocation(FileUriToPath(Row.URI));
    ackHistoryBack:
      HistoryBack;
    ackNavigate:
      if Row.URI <> '' then
        NavigateActiveTo(Row.URI);
    ackZipNavigate:
      if (ArchiveKind = akSevenZip) and (not HasArchiveChain(Row.URI)) then
      begin
        FSkipArchivePasswordUri := '';
        FArchivePasswordRetry := False;
        NavigateActiveTo(PathToSevenZipRootUri(FileUriToPath(Row.URI)))
      end
      else
        NavigateActiveTo(EnsureArchiveRootUri(Row.URI));
    ackView:
      RequestOpenViewer(Row.URI);
    ackEdit:
      RequestOpenEditor(Row.URI);
    ackShell:
      ShellOpenCurrent;
    ackCommand:
      RunUserCommandCurrent(Row.URI, UserCommand);
  end;
end;

procedure TDualPanelWindow.SetCmdFocused(AValue: Boolean);
begin
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.Focused := AValue;
end;

function TDualPanelWindow.ClickCmdLine(ACol, ARow: Integer; AShift: TShiftState): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  EditX: Integer;
begin
  Result := False;
  if not Assigned(FCmdLineMgr) then
    Exit;
  // Same prompt width DrawCommandLine lays out (full window width).
  Ws := ActiveWorkspace;
  EditX := DualPanelCmdLineEditX(ActiveTab(ActivePanel(Ws)).CurrentURI, Area.Width);
  if ACol < EditX then
    Exit;
  FCmdLineMgr.HandleClick(ACol - EditX, ssShift in AShift);
  Result := True;
end;

procedure TDualPanelWindow.OpenCmdHistoryPopup;
var
  Ws: TDualPanelWorkspaceTab;
  EditX: Integer;
begin
  if not Assigned(FCmdLineMgr) or FConsoleMode then
    Exit;
  // The line is drawn at H - 3 (DrawContent); the list opens above it.
  Ws := ActiveWorkspace;
  EditX := DualPanelCmdLineEditX(ActiveTab(ActivePanel(Ws)).CurrentURI, Area.Width);
  FCmdLineMgr.HistoryPopup.Open(FCmdLineMgr.GetHistoryItems, FCmdLineMgr.Text,
    Area.Height - 3, EditX, Area.Width - 1, Area.Width, Area.Height);
  NotifyChanged;
end;

function TDualPanelWindow.ClickFilterHistoryPopup(ACol, ARow: Integer): Boolean;
var
  Picked: string;
  Valid: Boolean;
begin
  Result := False;
  if not FFilterPopup.Visible then
    Exit;
  Result := FFilterPopup.HandleClick(ACol, ARow, Picked, Valid);
  if Valid then
    SetLiveFilterText(Picked);
  NotifyChanged;
end;

function TDualPanelWindow.ClickCmdHistoryPopup(ACol, ARow: Integer): Boolean;
var
  Picked: string;
  Valid: Boolean;
begin
  Result := False;
  if not Assigned(FCmdLineMgr) or not FCmdLineMgr.HistoryPopup.Visible then
    Exit;
  Result := FCmdLineMgr.HistoryPopup.HandleClick(ACol, ARow, Picked, Valid);
  if Valid then
    FCmdLineMgr.PickFromHistory(Picked);
  NotifyChanged;
end;

function TDualPanelWindow.HandleCmdLineInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FCmdLineMgr) then
    Result := FCmdLineMgr.HandleInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

procedure TDualPanelWindow.FocusCommandLine;
begin
  if FConsoleMode then
    Exit;
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.Focus;
end;

procedure TDualPanelWindow.SetCursorVisible(AVisible: Boolean);
begin
  if FCursorVisible = AVisible then
    Exit;
  FCursorVisible := AVisible;
  Invalidate;
  if Assigned(FOnContentChanged) then
    FOnContentChanged(Self);
end;

procedure TDualPanelWindow.SetConsoleMode(AValue: Boolean);
begin
  if FConsoleMode = AValue then
    Exit;
  FConsoleMode := AValue;
  if Assigned(FCmdLineMgr) then
    FCmdLineMgr.ConsoleMode := AValue;
  if AValue then
    SetCmdFocused(False);
  NotifyChanged;
end;

procedure TDualPanelWindow.OpenStub(AKind: TStubKind; const ATitle, ADetail: string);
begin
  if Assigned(FMenus) then
    FMenus.OpenStub(AKind, ATitle, ADetail);
end;

procedure TDualPanelWindow.CloseStub;
begin
  // Only cancel an in-flight folder-size job; other stubs must not bump Gen.
  if Assigned(FFolderSizeMgr) and FFolderSizeMgr.IsActive then
    CancelFolderSize;
  // The checksum progress stub: closing it (Esc) cancels the job.
  if Assigned(FChecksumToken) then
  begin
    FChecksumToken.Cancel;
    FChecksumToken := nil;
  end;
  if Assigned(FMenus) then
    FMenus.CloseStub;
end;

procedure TDualPanelWindow.CloseTransientUiBeforeDialog;
begin
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;
  if Assigned(FMenus) and FMenus.UserMenuVisible then
    CloseUserMenu;
  if Assigned(FMenus) and FMenus.SortMenuVisible then
    CloseSortMenu;
  if Assigned(FMenus) and FMenus.ColumnModeMenuVisible then
    CloseColumnModeMenu;
  if Assigned(FMenus) and FMenus.StubVisible then
    CloseStub;
  SetCmdFocused(False);
end;

procedure TDualPanelWindow.DrawStub;
begin
  if Assigned(FMenus) then
    FMenus.DrawStub(Buffer, Area.Width, Area.Height);
end;

function TDualPanelWindow.HandleStubInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if not Assigned(FMenus) or not FMenus.StubVisible then
    Exit(False);
  // Esc/Enter must go through CloseStub (CancelFolderSize), same as click-away.
  if (AKey = vkEscape) or (AKey = vkReturn) then
  begin
    CloseStub;
    NotifyChanged;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  Result := FMenus.HandleStubInput(AKey, AShift, AKeyChar);
end;

procedure TDualPanelWindow.DialogChanged(Sender: TObject);
begin
  if (FDialogKind = hdkDirSync) and Assigned(FDirSync) then
    FDirSync.NotifyDialogChanged;
  NotifyChanged;
end;

procedure TDualPanelWindow.DialogCommand(const AControlId, AValuesJson: string);
var
  Kind: THostDialogKind;
  Fields: TDialogCommandFields;
begin
  Kind := FDialogKind;
  Fields.Name := FDialog.GetInputValue('name');
  Fields.Password := FDialog.GetInputValue('password');
  Fields.Mask := FDialog.GetInputValue('search_mask');
  Fields.Containing := FDialog.GetInputValue('search_text');
  Fields.DestPath := FDialog.GetInputValue('job_dest');
  Fields.ExistingIdx := FDialog.GetListSelectedIndex('job_existing');
  Fields.RetryIdx := FDialog.GetListSelectedIndex('job_retry');
  Fields.PreserveTs := FDialog.GetCheckbox('job_timestamps');
  Fields.OnlyNewer := FDialog.GetCheckbox('job_only_newer');
  Fields.FollowSymlinks := FDialog.GetCheckbox('job_symlinks');
  Fields.UseExclude := FDialog.GetCheckbox('job_filter');
  Fields.ExcludeMask := FDialog.GetInputValue('job_exclude');
  Fields.DryRun := FDialog.GetCheckbox('dry_run');
  Fields.Remember := FDialog.GetCheckbox('remember');
  Fields.Subdirs := FDialog.GetCheckbox('search_subdirs');
  Fields.CaseSens := FDialog.GetCheckbox('search_case');
  Fields.WholeWords := FDialog.GetCheckbox('search_words');
  Fields.SearchFolders := FDialog.GetCheckbox('search_folders');
  Fields.UseRegex := FDialog.GetCheckbox('search_regex');
  Fields.SyncTwoWay := SameText(FDialog.GetRadio('sync_mode'), 'twoway');
  Fields.SyncByContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
  // Rename from overwrite-ask: keep pending conflict; open name dialog.
  if (Kind = hdkOverwriteAsk) and Assigned(FJobDialogs) and
     FJobDialogs.TryHandleOverwriteRename(AControlId) then
    Exit;
  // Cancel on a running progress dialog keeps the window open until the
  // worker actually stops; do not clear FDialogKind or the next Sync would
  // treat the leftover frame as a foreign modal.
  if (Kind = hdkJobProgress) and DialogCmdIsReject(AControlId) and
     Assigned(FJobs) and (FJobs.Phase = pjpRunning) then
  begin
    FJobs.RequestCancel;
    NotifyChanged;
    Exit;
  end;
  // Close after reading fields, but run job confirm before Close's Notify
  // re-enters paint with Phase still at pjpConfirm and dialog gone.
  FDialogKind := hdkNone;
  if not DispatchDialogCommand(Kind, AControlId, AValuesJson, Fields) then
    Exit;
  NotifyChanged;
  FlushDirWatchPending;
  FlushPendingJobAsk;
end;

function TDualPanelWindow.DispatchDialogCommand(AKind: THostDialogKind;
  const AControlId, AValuesJson: string; const AFields: TDialogCommandFields): Boolean;
begin
  Result := True;
  case AKind of
    hdkMkDir, hdkNewFile, hdkRename, hdkCopyInPlace, hdkSelectMask,
    hdkUnselectMask, hdkCreateLink, hdkSetAttributes:
      Result := FFileOps.DispatchCommand(AKind, AControlId);
    hdkOverwriteRename, hdkOverwriteAsk, hdkDeleteError, hdkIOError, hdkJobConfirm,
    hdkJobList, hdkJobProgress:
      Result := FJobDialogs.DispatchCommand(AKind, AControlId, AFields);
    hdkSearch:
      Result := FSearchDlg.DispatchCommand(AControlId, AFields);
    hdkHelp:
      FDialog.Close;
    hdkFolderHistory:
      Result := FFolderHistory.DispatchCommand(AControlId);
    hdkTheme, hdkColumnsConfig, hdkDisplay, hdkTerminalProfile, hdkConsoleProfile,
    hdkExternalTools:
      Result := FSettings.DispatchCommand(AKind, AControlId);
    hdkCmdHistory:
      Result := FCmdHistory.DispatchCommand(AControlId);
    hdkFileHistory:
      Result := FFileHistory.DispatchCommand(AControlId);
    hdkFolderHotlist, hdkFolderHotlistAdd, hdkFolderHotlistRename:
      Result := FFolderHotlist.DispatchCommand(AKind, AControlId);
    hdkWorkspaceLibrary, hdkWorkspaceSave, hdkWorkspaceRename, hdkWorkspaceConfirm:
      Result := FWorkspaceLibrary.DispatchCommand(AKind, AControlId);
    hdkSshConnections, hdkSshConnectionEdit, hdkSshConnectionConfirm:
      Result := FSshConnections.DispatchCommand(AKind, AControlId);
    hdkAssociations, hdkAssociationEdit, hdkAssociationConfirm:
      Result := FUserAssociations.DispatchCommand(AKind, AControlId);
    hdkUserMenuEdit, hdkUserMenuConfirm, hdkUserMenuPrompt:
      Result := FUserMenuHost.DispatchCommand(AKind, AControlId);
    hdkColorCoding, hdkColorCodingEdit, hdkColorPicker:
      Result := FColorCoding.DispatchCommand(AKind, AControlId);
    hdkKeymap, hdkKeymapEdit:
      Result := FKeymapDlg.DispatchCommand(AKind, AControlId);
    hdkCompareResult:
      FDialog.Close;
    hdkDirSync:
      Result := FDirSync.DispatchCommand(AControlId, AFields);
    hdkArchivePassword:
      begin
        HandleArchivePasswordCommand(AControlId, AFields.Password);
        Result := True;
      end;
    hdkTmpSaveList:
      begin
        FDialog.Close;
        if not DialogCmdIsReject(AControlId) then
          ConfirmTmpSaveList(AFields.Name);
      end;
    hdkWorkspaceTabRename:
      begin
        FDialog.Close;
        if not DialogCmdIsReject(AControlId) then
          ApplyWorkspaceTabTitle(AFields.Name);
      end;
    hdkChecksumOptions, hdkChecksumResult:
      DispatchChecksumCommand(AKind, AControlId);
  else
    FDialog.Close;
  end;
end;

procedure TDualPanelWindow.BeginMkDir;
begin
  if ActivePanelIsTmp then
    TmpRemoveSelected
  else
    FFileOps.BeginMkDir;
end;

procedure TDualPanelWindow.BeginNewFile;
begin
  FFileOps.BeginNewFile;
end;

procedure TDualPanelWindow.ConfirmNewFile(const AName: string);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  URI, CleanName, SelectName, ErrorMsg, Path: string;
begin
  if not TDualPanelOperationsController.ValidateFolderSegments(AName, CleanName, SelectName, ErrorMsg) then
  begin
    OpenStub(skShellInfo, 'New file failed', ErrorMsg);
    Exit;
  end;

  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  URI := ActiveTab(Panel).CurrentURI;
  if HasArchiveChain(URI) or IsFindUri(URI) then
  begin
    OpenStub(skShellInfo, 'New file failed', 'Cannot create file here');
    Exit;
  end;
  URI := JoinFileUri(URI, CleanName);
  Path := FileUriToPath(URI);
  // Do not touch the disk here. Writing an empty file (and TEncoding.UTF8's
  // BOM) made Discard from AskSave leave the file behind. The editor opens
  // a not-yet-created path as an empty buffer; SaveAsync creates it.
  if Path <> '' then
    FPendingSelectName := ExtractFileName(Path)
  else
    FPendingSelectName := SelectName;
  FPendingSelectSide := Ws.State.ActiveSide;
  RequestOpenEditor(URI);
  NotifyChanged;
end;

function TDualPanelWindow.DialogVisible: Boolean;
begin
  Result := Assigned(FDialog) and FDialog.Visible;
end;

procedure TDualPanelWindow.ConfirmMkDir(const AName: string);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  URI, CleanName, SelectName, ErrorMsg: string;
begin
  if not TDualPanelOperationsController.ValidateFolderSegments(AName, CleanName, SelectName, ErrorMsg) then
  begin
    OpenStub(skShellInfo, 'MkDir failed', ErrorMsg);
    Exit;
  end;

  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  URI := ActiveTab(Panel).CurrentURI;
  if HasArchiveChain(URI) or IsFindUri(URI) then
  begin
    OpenStub(skShellInfo, 'MkDir failed', 'Cannot create folder here');
    Exit;
  end;
  URI := JoinFileUri(URI, CleanName);
  FPendingSelectName := SelectName;
  FPendingSelectSide := Ws.State.ActiveSide;
  FVfs.CreateDirectoryAsync(URI, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if not ASuccess then
      begin
        FPendingSelectName := '';
        if AError.Message <> '' then
          OpenStub(skShellInfo, 'MkDir failed', AError.Message)
        else
          OpenStub(skShellInfo, 'MkDir failed', 'Unknown error');
      end
      else
      begin
        ReloadActiveRows;
        NotifyChanged;
      end;
    end);
end;

procedure TDualPanelWindow.BeginCreateLink;
begin
  FFileOps.BeginCreateLink;
end;

procedure TDualPanelWindow.BeginSetAttributes;
var
  Uris, Paths: TArray<string>;
  URI, Path: string;
  N: Integer;
begin
  if not CanStartOperation then
    Exit;
  if not HostInPanelsWorkspace then
    Exit;
  Uris := CollectActiveSources;
  SetLength(Paths, 0);
  for URI in Uris do
  begin
    if IsVirtualDirWatchUri(URI) or IsRecycleBinUri(URI) or IsSystemFoldersUri(URI) then
      Continue;
    Path := FileUriToPath(URI);
    if Path = '' then
      Continue;
    N := Length(Paths);
    SetLength(Paths, N + 1);
    Paths[N] := Path;
  end;
  if Length(Paths) = 0 then
  begin
    OpenStub(skShellInfo, 'Set attributes', 'Not available here');
    Exit;
  end;
  FFileOps.BeginSetAttributes(Paths);
end;

procedure TDualPanelWindow.ShowProperties;
var
  Uris, Paths: TArray<string>;
begin
  if not HostInPanelsWorkspace then
    Exit;
  Uris := CollectActiveSources;
  if Length(Uris) = 0 then
    Exit; // ".." with nothing selected
  // Selection, else the cursor item; only real local / network paths --
  // archives, SFTP, Recycle Bin, System folders and find results have no
  // shell item to show.
  Paths := FileUrisToLocalPaths(Uris);
  if Length(Paths) = 0 then
  begin
    OpenStub(skShellInfo, T('ui.properties.title', 'Properties'),
      T('ui.properties.unavailable', 'Only for files and folders on disk'));
    Exit;
  end;
  if Assigned(FOnShowProperties) then
    FOnShowProperties(Paths);
end;

procedure TDualPanelWindow.ApplySetAttributes(const APaths: TArray<string>;
  const APlan: TFileAttrPlan);
var
  CapturedPaths: TArray<string>;
  CapturedPlan: TFileAttrPlan;
begin
  CapturedPaths := Copy(APaths);
  CapturedPlan := APlan;
  TThread.CreateAnonymousThread(
    procedure
    var
      Ok, Fail: Integer;
      FirstPath, FirstErr, Stub: string;
    begin
      ApplyFileAttrRoots(CapturedPaths, CapturedPlan, Ok, Fail, FirstPath, FirstErr);
      TThread.Queue(nil,
        procedure
        begin
          if not FAlive then
            Exit;
          ReloadActiveRows;
          NotifyChanged;
          if Fail > 0 then
          begin
            Stub := Format('%d ok, %d failed. %s: %s',
              [Ok, Fail, ExtractFileName(FirstPath), FirstErr]);
            OpenStub(skShellInfo, 'Set attributes', Stub);
          end;
        end);
    end).Start;
end;

procedure TDualPanelWindow.ConfirmCreateLink(const ALinkName, ATarget: string;
  AKind: TLinkKind);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  URI, LinkPath, TargetPath, CleanName, SelectName, ErrorMsg: string;
begin
  if not TDualPanelOperationsController.ValidateFolderSegments(ALinkName, CleanName,
     SelectName, ErrorMsg) then
  begin
    OpenStub(skShellInfo, 'Create link failed', ErrorMsg);
    Exit;
  end;
  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  URI := ActiveTab(Panel).CurrentURI;
  if HasArchiveChain(URI) or IsFindUri(URI) then
  begin
    OpenStub(skShellInfo, 'Create link failed', 'Cannot create a link here');
    Exit;
  end;
  LinkPath := FileUriToPath(JoinFileUri(URI, CleanName));
  TargetPath := Trim(ATarget);
  if (LinkPath = '') or (TargetPath = '') then
  begin
    OpenStub(skShellInfo, 'Create link failed', 'Name and target are required');
    Exit;
  end;
  FPendingSelectName := SelectName;
  FPendingSelectSide := Ws.State.ActiveSide;
  // Link creation is a single fast filesystem-metadata call ? not routed
  // through IVirtualFileSystem (local-disk only, no VFS scheme needs it) ?
  // but still off the UI thread per the "no blocking I/O on the UI thread"
  // invariant, same as CreateDirectoryAsync above.
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Ok: Boolean;
    begin
      Ok := CreateFileLink(LinkPath, TargetPath, AKind, Err);
      TThread.Queue(nil,
        procedure
        begin
          if not FAlive then
            Exit;
          if not Ok then
          begin
            FPendingSelectName := '';
            if Err.Message <> '' then
              OpenStub(skShellInfo, 'Create link failed', Err.Message)
            else
              OpenStub(skShellInfo, 'Create link failed', 'Unknown error');
          end
          else
          begin
            ReloadActiveRows;
            NotifyChanged;
          end;
        end);
    end).Start;
end;

procedure TDualPanelWindow.ShowCompareResult(const ATitle, AMessage: string);
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  SetCmdFocused(False);
  FDialogKind := hdkCompareResult;
  FDialog.Open(BuildConfirmDialog(ATitle, AMessage), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.ShowFileDiff(const ALeftName, ARightName,
  AStatus: string; const ALines: TArray<string>);
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  SetCmdFocused(False);
  FDialogKind := hdkCompareResult;
  FDialog.Open(BuildFileDiffDialog(ALeftName, ARightName, AStatus, ALines),
    DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.CompareFolders;
var
  Ws: TDualPanelWorkspaceTab;
  LeftTab, RightTab: TTab;
  Diff: TPanelCompareResult;
  Title: string;
begin
  if not CanStartOperation then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Title := T('ui.compareFolders.title', 'Compare folders');
  if not (Ws.State.LeftVisible and Ws.State.RightVisible) or
     (PanelViewKind(psLeft) <> pvkFiles) or (PanelViewKind(psRight) <> pvkFiles) then
  begin
    ShowCompareResult(Title, T('ui.compareFolders.needPanels',
      'Both panels must show file lists.'));
    Exit;
  end;
  Diff := ComparePanelRows(RowsForSide(psLeft), RowsForSide(psRight));
  // The new selection replaces the old one on both sides, as in FAR.
  LeftTab := ActiveTab(Ws.State.LeftPanel);
  LeftTab.SelectedURIs := Diff.LeftUris;
  SetActiveTab(Ws.State.LeftPanel, LeftTab);
  RightTab := ActiveTab(Ws.State.RightPanel);
  RightTab.SelectedURIs := Diff.RightUris;
  SetActiveTab(Ws.State.RightPanel, RightTab);
  SaveActiveWorkspace(Ws);
  Invalidate;
  // Differences speak for themselves (the selection and its totals in the
  // panel footer); only "nothing differs" needs saying, as in FAR.
  if (Length(Diff.LeftUris) = 0) and (Length(Diff.RightUris) = 0) then
    ShowCompareResult(Title, T('ui.compareFolders.same', 'The folders are identical.'));
end;

procedure TDualPanelWindow.BeginCompareFiles;
var
  Ws: TDualPanelWorkspaceTab;
  LeftRows, RightRows: TPanelRows;
  LeftTab, RightTab: TTab;
  LeftIdx, RightIdx: Integer;
  LeftRow, RightRow: TPanelRow;
  Token: IJobCancelToken;
  LeftName, RightName: string;
  EitherSideNotAPlainFile: Boolean;
begin
  if not CanStartOperation then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  LeftRows := RowsForSide(psLeft);
  RightRows := RowsForSide(psRight);
  if (Length(LeftRows) = 0) or (Length(RightRows) = 0) then
    Exit;
  LeftTab := ActiveTab(Ws.State.LeftPanel);
  RightTab := ActiveTab(Ws.State.RightPanel);
  LeftIdx := EnsureRange(LeftTab.CursorIndex, 0, High(LeftRows));
  RightIdx := EnsureRange(RightTab.CursorIndex, 0, High(RightRows));
  LeftRow := LeftRows[LeftIdx];
  RightRow := RightRows[RightIdx];
  EitherSideNotAPlainFile := LeftRow.IsParent or RightRow.IsParent or
    LeftRow.IsDirectory or RightRow.IsDirectory;
  if EitherSideNotAPlainFile then
  begin
    ShowCompareResult('Compare files', 'Select a file (not a folder) on each panel.');
    Exit;
  end;

  LeftName := LeftRow.Text;
  RightName := RightRow.Text;
  Token := TJobCancelToken.Create;
  DiffFilesAsync(LeftRow.URI, RightRow.URI, FVfs, Token,
    procedure(AResult: TCompareResult; ADiffOffset: Int64; const AError: TVfsError;
      const ADiffLines: TArray<string>; AChangedLines: Integer)
    var
      Msg, Status: string;
    begin
      if not FAlive then
        Exit;
      case AResult of
        crEqual:
          ShowCompareResult('Compare files', 'Files are identical.');
        crReadError:
          ShowCompareResult('Compare files', 'Compare failed: ' + AError.Message);
      else
        if (Length(ADiffLines) > 0) and (AChangedLines > 0) then
        begin
          Status := Format('%d line(s) differ', [AChangedLines]);
          ShowFileDiff('L: ' + LeftName, 'R: ' + RightName, Status, ADiffLines);
        end
        else
        begin
          if AResult = crDifferSize then
            Msg := 'Files differ in size (binary).'
          else
            Msg := Format('Files differ at byte offset %d (binary).', [ADiffOffset]);
          ShowCompareResult('Compare files', Msg);
        end;
      end;
    end);
end;

procedure TDualPanelWindow.NavigateToRecycleBin;
begin
  if not CanStartOperation then
    Exit;
  NavigateActiveTo(cRecycleBinRootUri);
end;

procedure TDualPanelWindow.RestoreCursorItemFromRecycleBin;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  URI: string;
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  if Assigned(FJobs) and FJobs.BlocksNewOperation then
    Exit;
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent or not IsRecycleBinUri(Row.URI) then
    Exit;
  URI := Row.URI;
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Ok: Boolean;
    begin
      Ok := RestoreRecycleBinItem(URI, Err);
      TThread.Queue(nil,
        procedure
        begin
          if not FAlive then
            Exit;
          if not Ok then
            OpenStub(skShellInfo, 'Restore failed', Err.Message)
          else
          begin
            ReloadActiveRows;
            NotifyChanged;
          end;
        end);
    end).Start;
end;

function TDualPanelWindow.ActivePanelIsTmp: Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Result := (Ws.Kind = wkPanels) and
    IsTmpPanelUri(ActiveTab(ActivePanel(Ws)).CurrentURI);
end;

function TDualPanelWindow.ActivePanelIsWorkspace: Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Result := (Ws.Kind = wkPanels) and
    IsWorkspaceUri(ActiveTab(ActivePanel(Ws)).CurrentURI);
end;

procedure TDualPanelWindow.TmpRemoveSelected;
var
  Sources: TArray<string>;
  Backend: IVirtualFileSystem;
  Remaining: Integer;
  I: Integer;
begin
  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;
  if not GlobalVfsRegistry.TryResolve('tmp:///', Backend) then
    Exit;
  Remaining := Length(Sources);
  for I := 0 to High(Sources) do
    Backend.DeleteAsync(Sources[I], vdmPermanent, nil, nil,
      procedure(const ASuccess: Boolean; const AError: TVfsError)
      begin
        Dec(Remaining);
        if Remaining <> 0 then
          Exit;
        if not FAlive then
          Exit;
        ReloadSidesShowing('tmp:///');
        NotifyChanged;
      end);
end;

procedure TDualPanelWindow.WorkspaceUnlinkSelected;
var
  Sources: TArray<string>;
  Backend: IVirtualFileSystem;
  Remaining: Integer;
  I: Integer;
  CurrentURI: string;
  Ws: TDualPanelWorkspaceTab;
begin
  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;
  Ws := ActiveWorkspace;
  CurrentURI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  if not GlobalVfsRegistry.TryResolve('ws:///', Backend) then
    Exit;
  Remaining := Length(Sources);
  for I := 0 to High(Sources) do
    Backend.DeleteAsync(Sources[I], vdmPermanent, nil, nil,
      procedure(const ASuccess: Boolean; const AError: TVfsError)
      begin
        Dec(Remaining);
        if Remaining <> 0 then
          Exit;
        if not FAlive then
          Exit;
        ReloadSidesShowing(CurrentURI);
        NotifyChanged;
      end);
end;

procedure TDualPanelWindow.TmpGotoCursorFile;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Path: string;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent then
    Exit;
  Path := FileUriToPath(Row.URI);
  if Path = '' then
    Path := FileUriToPath(Row.TargetURI);
  if Path <> '' then
    GotoFileLocation(Path);
end;

procedure TDualPanelWindow.TmpGotoOpposite;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Path, Dir: string;
  Saved, Opp: TPanelSide;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent then
    Exit;
  Path := FileUriToPath(Row.URI);
  if Path = '' then
    Path := FileUriToPath(Row.TargetURI);
  Path := ExcludeTrailingPathDelimiter(Trim(Path));
  if Path = '' then
    Exit;
  Saved := Ws.State.ActiveSide;
  Opp := OppositeSide(Saved);
  if TDirectory.Exists(Path) then
    NavigateSideTo(Opp, PathToFileUri(Path))
  else
  begin
    Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Path));
    if Dir = '' then
      Exit;
    FPendingSelectName := ExtractFileName(Path);
    FPendingSelectSide := Opp;
    NavigateSideTo(Opp, PathToFileUri(Dir));
  end;
  Ws := ActiveWorkspace;
  Ws.State.ActiveSide := Saved;
  SaveActiveWorkspace(Ws);
  NotifyChanged;
end;

procedure TDualPanelWindow.WorkspaceGotoOpposite;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Path, Dir, SelectName: string;
  Saved, Opp: TPanelSide;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent then
    Exit;
  Path := FileUriToPath(Row.URI);
  if Path = '' then
    Path := FileUriToPath(Row.TargetURI);
  Path := ExcludeTrailingPathDelimiter(Trim(Path));
  if Path = '' then
    Exit;
  Saved := Ws.State.ActiveSide;
  Opp := OppositeSide(Saved);
  if TDirectory.Exists(Path) then
  begin
    Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Path));
    SelectName := ExtractFileName(Path);
    if (Dir = '') or (SelectName = '') then
    begin
      NavigateSideTo(Opp, PathToFileUri(Path));
      Ws := ActiveWorkspace;
      Ws.State.ActiveSide := Saved;
      SaveActiveWorkspace(Ws);
      NotifyChanged;
      Exit;
    end;
  end
  else
  begin
    Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Path));
    SelectName := ExtractFileName(Path);
    if Dir = '' then
      Exit;
  end;
  FPendingSelectName := SelectName;
  FPendingSelectSide := Opp;
  NavigateSideTo(Opp, PathToFileUri(Dir));
  Ws := ActiveWorkspace;
  Ws.State.ActiveSide := Saved;
  SaveActiveWorkspace(Ws);
  NotifyChanged;
end;

procedure TDualPanelWindow.TmpSaveList;
var
  Ws: TDualPanelWorkspaceTab;
  OppURI, Suggest, Dir: string;
begin
  Ws := ActiveWorkspace;
  OppURI := ActiveTab(Ws.State.LeftPanel).CurrentURI;
  if Ws.State.ActiveSide = psLeft then
    OppURI := ActiveTab(Ws.State.RightPanel).CurrentURI;
  Dir := FileUriToPath(OppURI);
  if Dir = '' then
    Dir := TPath.GetDocumentsPath;
  Suggest := TPath.Combine(Dir, 'tmppanel.temp');
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkTmpSaveList;
  FDialog.Open(BuildInputDialog(T('ui.tmpSaveList.title', 'Save file list as'),
    T('ui.tmpSaveList.prompt', 'File name:'), Suggest),
    DialogCommand);
end;

procedure TDualPanelWindow.ConfirmTmpSaveList(const AFileName: string);
var
  Path, Line: string;
  Rows: TPanelRows;
  R: TPanelRow;
  Lines: TStringList;
  Ws: TDualPanelWorkspaceTab;
begin
  Path := Trim(AFileName);
  if Path = '' then
    Exit;
  if ExtractFileDrive(Path) = '' then
  begin
    Ws := ActiveWorkspace;
    Line := FileUriToPath(ActiveTab(ActivePanel(Ws)).CurrentURI);
    if Line = '' then
      Line := TPath.GetDocumentsPath;
    Path := TPath.Combine(Line, Path);
  end;
  Lines := TStringList.Create;
  try
    Rows := RowsForSide(ActiveWorkspace.State.ActiveSide);
    for R in Rows do
    begin
      if R.IsParent then
        Continue;
      Line := FileUriToPath(R.URI);
      if Line = '' then
        Line := FileUriToPath(R.TargetURI);
      if Line <> '' then
        Lines.Add(Line);
    end;
    try
      TFile.WriteAllText(Path, Lines.Text, TEncoding.UTF8);
    except
      on E: Exception do
        OpenStub(skShellInfo, 'Save list failed', E.Message);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TDualPanelWindow.BeginRename;
begin
  FFileOps.BeginRename;
end;

procedure TDualPanelWindow.ConfirmRename(const AName: string);
var
  FromURI, ToURI, CleanName, DirURI, ErrorMsg: string;
  Side: TPanelSide;
begin
  FromURI := FMenus.StubDetail;
  if FromURI = '' then
    Exit;
  if not TDualPanelOperationsController.ValidateRenameName(AName, ErrorMsg) then
  begin
    OpenStub(skShellInfo, 'Rename failed', ErrorMsg);
    Exit;
  end;
  CleanName := Trim(AName);
  DirURI := ParentFileUri(FromURI);
  ToURI := JoinFileUri(DirURI, CleanName);
  if SameText(FromURI, ToURI) then
  begin
    NotifyChanged;
    Exit;
  end;
  Side := ActiveWorkspace.State.ActiveSide;
  FPendingSelectName := CleanName;
  FPendingSelectSide := Side;
  FVfs.MoveAsync(FromURI, ToURI, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if not ASuccess then
      begin
        FPendingSelectName := '';
        OpenStub(skShellInfo, 'Rename failed', AError.Message)
      end
      else
      begin
        ReloadActiveRows;
        NotifyChanged;
      end;
    end);
end;

procedure TDualPanelWindow.BeginCopyInPlace;
begin
  FFileOps.BeginCopyInPlace;
end;

procedure TDualPanelWindow.ConfirmCopyInPlace(const AName: string);
var
  FromURI, ToURI, CleanName, DirURI, ErrorMsg: string;
  Side: TPanelSide;
begin
  FromURI := FMenus.StubDetail;
  if FromURI = '' then
    Exit;
  if not TDualPanelOperationsController.ValidateRenameName(AName, ErrorMsg) then
  begin
    OpenStub(skShellInfo, 'Copy failed', ErrorMsg);
    Exit;
  end;
  CleanName := Trim(AName);
  DirURI := ParentFileUri(FromURI);
  ToURI := JoinFileUri(DirURI, CleanName);
  if SameText(FromURI, ToURI) then
  begin
    OpenStub(skShellInfo, 'Copy failed', 'Choose a different name to copy into the same folder');
    Exit;
  end;
  Side := ActiveWorkspace.State.ActiveSide;
  FPendingSelectName := CleanName;
  FPendingSelectSide := Side;
  FVfs.CopyAsync(FromURI, ToURI, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if not ASuccess then
      begin
        FPendingSelectName := '';
        OpenStub(skShellInfo, 'Copy failed', AError.Message)
      end
      else
      begin
        ReloadActiveRows;
        NotifyChanged;
      end;
    end);
end;

procedure TDualPanelWindow.RequestFreeSpace(const APath: string);
var
  Root, RootURI: string;
  Gen: Cardinal;
begin
  Root := ExtractFileDrive(APath);
  if Root = '' then
  begin
    FFreeText := '';
    FFreeRoot := '';
    Exit;
  end;
  Root := IncludeTrailingPathDelimiter(Root);
  if SameText(Root, FFreeRoot) then
    Exit;
  FFreeRoot := Root;
  FFreeText := '';
  RootURI := PathToFileUri(Root);
  Inc(FFreeGen);
  Gen := FFreeGen;
  FVfs.GetFreeSpaceAsync(RootURI, nil,
    procedure(const AFree, ATotal: Int64; const AError: TVfsError)
    begin
      if not FAlive or (Gen <> FFreeGen) then
        Exit;
      if (AError.Code = vecOk) and (ATotal > 0) then
        FFreeText := T('status.free', 'Free %s', [FormatSizeShort(AFree)])
      else
        FFreeText := '';
      NotifyChanged;
    end);
end;

procedure TDualPanelWindow.ResolveRelativeCommandAsync(const AText, ABaseDir: string);
var
  Combined, URI, Cmd: string;
begin
  Cmd := Trim(AText);
  if (Cmd = '') or (ABaseDir = '') then
    Exit;
  Combined := TPath.Combine(ABaseDir, Cmd);
  URI := PathToFileUri(Combined);
  FVfs.ExistsAsync(URI, nil,
    procedure(const AExists: Boolean; const AIsDirectory: Boolean;
      const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if AExists and (AError.Code = vecOk) then
      begin
        if Assigned(FCmdLineMgr) then
          FCmdLineMgr.Clear;
        if AIsDirectory then
          NavigateActiveTo(URI)
        else
          NavigateActiveTo(PathToFileUri(TPath.GetDirectoryName(Combined)));
      end
      else
        RunConsoleCommand(Cmd);
    end);
end;

procedure TDualPanelWindow.ClearQuickSearch;
begin
  if not FQuickSearchActive and (FQuickSearchText = '') then
    Exit;
  FQuickSearchActive := False;
  FQuickSearchText := '';
  NotifyChanged;
end;

procedure TDualPanelWindow.DrawQuickSearchField(const ABounds: TRectI);
begin
  // FAR-style Alt search box inside the panel that owns the search.
  DrawSearchInfoBox(Buffer, ABounds, ' Search: ', FQuickSearchText, FCursorVisible);
end;

function TDualPanelWindow.HandleQuickSearchInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Ch: Char;
begin
  Result := True;
  case ClassifyNeedleBoxKey(AKey, AKeyChar, True, Ch) of
    nbaClear:
      begin
        ClearQuickSearch;
        AKey := 0;
        AKeyChar := #0;
      end;
    nbaBackspace:
      begin
        NeedleBackspace(FQuickSearchText);
        if FQuickSearchText = '' then
          FQuickSearchActive := False;
        AKey := 0;
        AKeyChar := #0;
        NotifyChanged;
      end;
    nbaAppend:
      begin
        FQuickSearchActive := True;
        FQuickSearchText := FQuickSearchText + Ch;
        Ws := ActiveWorkspace;
        Panel := ActivePanel(Ws);
        Tab := ActiveTab(Panel);
        Rows := RowsForSide(Ws.State.ActiveSide);
        if ApplyQuickSearchMatch(Tab, Rows, FQuickSearchText, ListViewHeight,
          ListColCountForSide(Ws.State.ActiveSide)) then
        begin
          SetActiveTab(Panel, Tab);
          SetActivePanel(Ws, Panel);
          SaveActiveWorkspace(Ws);
        end;
        AKey := 0;
        AKeyChar := #0;
        NotifyChanged;
      end;
  else
    Result := False;
  end;
end;

procedure TDualPanelWindow.BeginLiveFilter;
begin
  if FFilterBoxActive then
    Exit;
  FFilterBoxActive := True;
  FFilterBoxText := '';
  NotifyChanged;
end;

procedure TDualPanelWindow.ClearLiveFilter;
var
  M: IPanelModel;
begin
  if not FFilterBoxActive and (FFilterBoxText = '') then
    Exit;
  FFilterBoxActive := False;
  FFilterBoxText := '';
  FFilterPopup.Close;
  M := ModelForSide(ActiveWorkspace.State.ActiveSide);
  if Assigned(M) then
    M.SetFilterMask('');
  NotifyChanged;
end;

procedure TDualPanelWindow.SetLiveFilterText(const AText: string);
var
  M: IPanelModel;
begin
  FFilterBoxText := AText;
  M := ModelForSide(ActiveWorkspace.State.ActiveSide);
  if Assigned(M) then
    M.SetFilterMask(FFilterBoxText);
  NotifyChanged;
end;

procedure TDualPanelWindow.DrawFilterField(const ABounds: TRectI);
const
  cFilterPrefix = ' Filter: ';
begin
  // ABounds is the panel; the field is its info strip (DrawSearchInfoBox).
  FFilterFieldBounds := TRectI.Make(ABounds.Left + 1 + Length(cFilterPrefix),
    ABounds.Bottom - 1, ABounds.Right - 2, ABounds.Bottom - 1);
  // Same FAR-style info-strip box as DrawQuickSearchField, different label.
  DrawSearchInfoBox(Buffer, ABounds, ' Filter: ', FFilterBoxText, FCursorVisible);
end;

function TDualPanelWindow.HandleFilterInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  M: IPanelModel;
  Ch: Char;
  Picked: string;
begin
  Result := True;
  // Open history list owns the arrows, Enter, Del and Esc.
  case FFilterPopup.HandleKey(AKey, AShift, AKeyChar, Picked) of
    hpkHandled:
      begin
        NotifyChanged;
        Exit;
      end;
    hpkPicked:
      begin
        SetLiveFilterText(Picked);
        Exit;
      end;
  end;
  // Ctrl+Down / Alt+Down: earlier masks as a drop-down above the field.
  if (AKey = vkDown) and ((ssCtrl in AShift) or (ssAlt in AShift)) and
     not (ssShift in AShift) then
  begin
    FFilterPopup.Open(DialogHistoryItems(cLiveFilterHistory), FFilterBoxText,
      FFilterFieldBounds.Top, FFilterFieldBounds.Left, FFilterFieldBounds.Right,
      Area.Width, Area.Height);
    AKey := 0;
    AKeyChar := #0;
    NotifyChanged;
    Exit;
  end;
  case ClassifyNeedleBoxKey(AKey, AKeyChar, False, Ch) of
    nbaClear:
      begin
        ClearLiveFilter;
        AKey := 0;
        AKeyChar := #0;
      end;
    nbaConfirm:
      begin
        FFilterBoxActive := False;
        DialogHistoryAdd(cLiveFilterHistory, FFilterBoxText);
        AKey := 0;
        AKeyChar := #0;
        NotifyChanged;
      end;
    nbaBackspace:
      begin
        NeedleBackspace(FFilterBoxText);
        M := ModelForSide(ActiveWorkspace.State.ActiveSide);
        if Assigned(M) then
          M.SetFilterMask(FFilterBoxText);
        AKey := 0;
        AKeyChar := #0;
        NotifyChanged;
      end;
    nbaAppend:
      begin
        FFilterBoxText := FFilterBoxText + Ch;
        M := ModelForSide(ActiveWorkspace.State.ActiveSide);
        if Assigned(M) then
          M.SetFilterMask(FFilterBoxText);
        AKey := 0;
        AKeyChar := #0;
        NotifyChanged;
      end;
  else
    Result := False;
  end;
end;

procedure TDualPanelWindow.ApplyPendingSelect(ASide: TPanelSide;
  const ARows: TPanelRows);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  I, ViewH: Integer;
begin
  if (FPendingSelectName = '') or (ASide <> FPendingSelectSide) then
    Exit;
  I := PendingSelectMatchIndex(ARows, FPendingSelectName);
  FPendingSelectName := '';
  if I < 0 then
  begin
    ClampCursorSide(ASide);
    Exit;
  end;
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Tab.CursorIndex := I;
  ViewH := ListViewHeight;
  if ViewH > 0 then
    EnsureCursorVisible(Tab, Length(ARows), ViewH, ListColCountForSide(ASide));
  SetActiveTab(Panel, Tab);
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  // Do not change ActiveSide: SoftReload of the inactive panel (dir-watch /
  // post-delete flush) must restore its cursor without stealing focus.
  SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.ClampCursorSide(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  M: IPanelModel;
  ViewH, MaxOff: Integer;
begin
  M := ModelForSide(ASide);
  if Assigned(M) and M.IsLoading then
    Exit;
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(ASide);
  ViewH := ListViewHeight;
  if ViewH < 1 then
  begin
    // Layout not ready yet (startup / session restore before first paint).
    // Only clamp indices ? do not pull ScrollOffset to CursorIndex with ViewH=1.
    if Length(Rows) <= 0 then
    begin
      Tab.CursorIndex := 0;
      Tab.ScrollOffset := 0;
    end
    else
    begin
      Tab.CursorIndex := EnsureRange(Tab.CursorIndex, 0, High(Rows));
      MaxOff := High(Rows);
      if Tab.ScrollOffset < 0 then
        Tab.ScrollOffset := 0;
      if Tab.ScrollOffset > MaxOff then
        Tab.ScrollOffset := MaxOff;
    end;
  end
  else
    EnsureCursorVisible(Tab, Length(Rows), ViewH, ListColCountForSide(ASide));
  SetActiveTab(Panel, Tab);
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.CloseSearchUi;
begin
  if Assigned(FSearchUi) then
    FSearchUi.CloseSearchUi;
end;

procedure TDualPanelWindow.OpenSearchDialog;
begin
  if Assigned(FSearchDlg) then
    FSearchDlg.Open;
end;

procedure TDualPanelWindow.DrawSearchUi;
begin
  if Assigned(FSearchUi) then
    FSearchUi.DrawSearchUi(Buffer, Area.Width, Area.Height);
end;

function TDualPanelWindow.HandleSearchInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FSearchUi) then
    Result := FSearchUi.HandleSearchInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

procedure TDualPanelWindow.RequestOpenViewer(const AURI: string);
begin
  if AURI = '' then
    Exit;
  OpenDocument(AURI, True);
end;

procedure TDualPanelWindow.RequestOpenEditor(const AURI: string);
begin
  if AURI = '' then
    Exit;
  OpenDocument(AURI, False);
end;

procedure TDualPanelWindow.CancelFolderSize;
begin
  if Assigned(FFolderSizeMgr) then
    FFolderSizeMgr.Cancel;
end;

function TDualPanelWindow.FolderSizeStubTitle: string;
var
  Total: Integer;
begin
  if Assigned(FFolderSizeMgr) then
  begin
    Total := FFolderSizeMgr.PendingCount + FFolderSizeMgr.CompletedCount;
    if Total > 1 then
      Exit(Format('Folder size (%d/%d)', [FFolderSizeMgr.CompletedCount, Total]));
  end;
  Result := 'Folder size';
end;

procedure TDualPanelWindow.CalculateFolderSizeUnderCursor;
var
  Ws: TDualPanelWorkspaceTab;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Panel: TPanelState;
  Side: TPanelSide;
  Targets: TArray<string>;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  Side := Ws.State.ActiveSide;

  Targets := CollectSelectedDirectoryUris(Tab, Rows);
  if Length(Targets) = 0 then
  begin
    Row := Rows[Idx];
    if (not PanelRowIsDirectory(Row)) or Row.IsParent or (Row.URI = '') then
      Exit;
    SetLength(Targets, 1);
    Targets[0] := Row.URI;
  end;

  if Assigned(FFolderSizeMgr) then
  begin
    OpenStub(skShellInfo, FolderSizeStubTitle, 'Calculating... Esc=Cancel');
    FFolderSizeMgr.StartCalculation(Side, Targets[0], Targets);
  end;
end;

procedure TDualPanelWindow.InsertPanelItemToCmdLine(AFullPath: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Piece, Name: string;
begin
  if FConsoleMode then
    Exit;
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Ws.Kind <> wkPanels then
    Exit;
  if Row.IsParent then
    Exit;
  if AFullPath then
  begin
    Piece := PanelItemFullPath(Row.URI, Tab.CurrentURI, Row.IsParent);
    if Piece = '' then
      Exit;
  end
  else
  begin
    Name := Row.Text;
    while (Name <> '') and ((Name[Length(Name)] = '/') or
      (Name[Length(Name)] = '\')) do
      Delete(Name, Length(Name), 1);
    if Name = '' then
      Exit;
    Piece := Name;
  end;
  Piece := CmdLineQuoteIfNeeded(Piece);
  if Assigned(FCmdLineMgr) then
  begin
    if (FCmdLineMgr.Text <> '') and (FCmdLineMgr.Cmd.Cursor > 0) and
       (FCmdLineMgr.Text[FCmdLineMgr.Cmd.Cursor] <> ' ') then
      Piece := ' ' + Piece;
    FCmdLineMgr.InsertText(Piece);
  end;
end;

procedure TDualPanelWindow.OpenViewOrEdit(AEdit: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Panel: TPanelState;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent or (Row.URI = '') then
    Exit;
  if (not AEdit) and TabHasSelectedDirectories(Tab, Rows) then
  begin
    CalculateFolderSizeUnderCursor;
    Exit;
  end;
  if PanelRowIsDirectory(Row) then
  begin
    if not AEdit then
      CalculateFolderSizeUnderCursor;
    Exit;
  end;
  if AEdit then
    RequestOpenEditor(Row.URI)
  else
    RequestOpenViewer(Row.URI);
end;

procedure TDualPanelWindow.ToggleQuickView;
var
  Ws: TDualPanelWorkspaceTab;
  Other: TPanelSide;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Other := OppositeSide(Ws.State.ActiveSide);

  if PanelViewKind(Other) = pvkQuickView then
  begin
    CloseQuickView;
    Exit;
  end;

  if not IsPanelVisible(Other) then
  begin
    if Other = psLeft then
      Ws.State.LeftVisible := True
    else
      Ws.State.RightVisible := True;
    SaveActiveWorkspace(Ws);
    SyncDirWatches;
  end;
  // One "special" adjacent panel at a time (mirrors ToggleAdjacentInfoPanel).
  if PanelViewKind(Other) = pvkInfo then
    SetPanelViewKind(Other, pvkFiles);
  SetPanelViewKind(Other, pvkQuickView);
  NotifyChanged;
end;

procedure TDualPanelWindow.CloseQuickView;
begin
  if PanelViewKind(psLeft) = pvkQuickView then
    SetPanelViewKind(psLeft, pvkFiles);
  if PanelViewKind(psRight) = pvkQuickView then
    SetPanelViewKind(psRight, pvkFiles);
  ClearOverlayPreview;
  if Assigned(FQuickText) then
    FQuickText.Clear;
  NotifyChanged;
end;

procedure TDualPanelWindow.QuickTextChanged(Sender: TObject);
begin
  if FAlive then
    NotifyChanged;
end;

function TDualPanelWindow.HandleMouseWheelAt(ALocalCol, ALocalRow,
  AWheelDelta: Integer): Boolean;
var
  Side: TPanelSide;
  Bounds: TRectI;
begin
  Result := False;
  if not QuickViewVisible or not Assigned(FQuickText) or (FQuickText.Uri = '') then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  // Quick View is always the side opposite the active one.
  Side := OppositeSide(ActiveWorkspace.State.ActiveSide);
  if PanelViewKind(Side) <> pvkQuickView then
    Exit;
  if Side = psLeft then
    Bounds := FLeftBounds
  else
    Bounds := FRightBounds;
  if not Bounds.Contains(ALocalCol, ALocalRow) then
    Exit;
  if AWheelDelta > 0 then
    FQuickText.ScrollBy(-3)
  else
    FQuickText.ScrollBy(3);
  Result := True;
end;

function TDualPanelWindow.QuickViewVisible: Boolean;
begin
  // The Help window covers the panels; the image Overlay would paint over it.
  Result := (not FConsoleMode) and (not HelpVisible) and (ActiveWorkspace.Kind = wkPanels) and
    ((PanelViewKind(psLeft) = pvkQuickView) or (PanelViewKind(psRight) = pvkQuickView));
end;

function TDualPanelWindow.MarkdownImageOverlayVisible: Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  Result := (not FConsoleMode) and (not HelpVisible) and Assigned(Doc) and
    Doc.MarkdownImageOverlayVisible;
end;

procedure TDualPanelWindow.ShellOpenCurrent;
var
  Ws: TDualPanelWorkspaceTab;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Panel: TPanelState;
  Path: string;
begin
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsDirectory or Row.IsParent or (Row.URI = '') then
    Exit;
  Path := FileUriToPath(Row.URI);
  if Path = '' then
    Exit;
  // Platform shell open (Windows ShellExecute today; xdg-open / open later).
  if not ShellOpenFile(Path) then
    OpenStub(skShellInfo, 'Shell open failed', Path)
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.LaunchExternal(AEdit: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Uri, Path, Title: string;
  Paths: TArray<string>;
  Launch: TExternalLaunch;
  Ok: Boolean;
begin
  if not CanStartOperation then
    Exit;
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsDirectory or Row.IsParent or (Row.URI = '') then
    Exit;
  if AEdit then
    Title := T('ui.externalTools.editTitle', 'External editor')
  else
    Title := T('ui.externalTools.viewTitle', 'External viewer');
  // Search results point at the real file through TargetURI.
  Uri := Row.TargetURI;
  if Uri = '' then
    Uri := Row.URI;
  Paths := FileUrisToLocalPaths([Uri]);
  if Length(Paths) = 0 then
  begin
    OpenStub(skShellInfo, Title,
      T('ui.externalTools.localOnly', 'Only for files on disk'));
    Exit;
  end;
  Path := Paths[0];
  Launch := ResolveExternalLaunch(GlobalExternalTools, AEdit, Path);
  case Launch.Kind of
    elkShellOpen:
      Ok := ShellOpenFile(Path);
    elkShellEdit:
      Ok := ShellEditFile(Path);
  else
    Ok := ShellRunDetached(Launch.CommandLine, ExtractFilePath(Path));
  end;
  if not Ok then
  begin
    if Launch.Kind = elkCommand then
      OpenStub(skShellInfo, Title, Launch.CommandLine)
    else
      OpenStub(skShellInfo, Title, Path);
  end
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.BeginChecksums;
var
  Uris, Paths: TArray<string>;
  Algo: TChecksumAlgo;
begin
  if not HostInPanelsWorkspace or not CanStartOperation or Assigned(FChecksumToken) then
    Exit;
  Uris := CollectActiveSources;
  if Length(Uris) = 0 then
    Exit; // ".." with nothing selected
  Paths := FileUrisToLocalPaths(Uris);
  if Length(Paths) = 0 then
  begin
    OpenStub(skShellInfo, T('ui.checksum.title', 'Checksums'),
      T('ui.checksum.localOnly', 'Only for files and folders on disk'));
    Exit;
  end;
  FChecksumPaths := Paths;
  FChecksumBaseDir := ActiveLocalPath;
  // A checksum file on its own: verify it instead of hashing it.
  if (Length(Paths) = 1) and TFile.Exists(Paths[0]) and
     ChecksumAlgoFromExt(Paths[0], Algo) then
  begin
    StartChecksumJob(Ord(Algo), True);
    Exit;
  end;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkChecksumOptions;
  FDialog.Open(BuildChecksumOptionsDialog(FChecksumAlgoIndex), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.StartChecksumJob(AAlgoIndex: Integer; AVerify: Boolean);
var
  Token: IJobCancelToken;
  Paths: TArray<string>;
  Base, Title: string;
  Algo: TChecksumAlgo;
begin
  Algo := TChecksumAlgo(EnsureRange(AAlgoIndex, 0, Ord(High(TChecksumAlgo))));
  Token := TJobCancelToken.Create;
  FChecksumToken := Token;
  Paths := Copy(FChecksumPaths);
  Base := FChecksumBaseDir;
  Title := T('ui.checksum.title', 'Checksums') + ' ' + cChecksumAlgoNames[Algo];
  OpenStub(skShellInfo, Title, T('ui.checksum.working', 'Calculating... Esc=Cancel'));
  TThread.CreateAnonymousThread(
    procedure
    var
      Files: TArray<TChecksumFile>;
      Items: TArray<TChecksumVerifyItem>;
      Lines: TArray<string>;
      I, Bad: Integer;
      Hash, Err, SaveName, Status: string;
      Done: Boolean;
      Cancelled: TChecksumCancelled;
    begin
      Cancelled :=
        function: Boolean
        begin
          Result := Token.IsCancellationRequested;
        end;
      SetLength(Lines, 0);
      Err := '';
      SaveName := '';
      Bad := 0;
      Done := True;
      try
        if AVerify then
        begin
          Done := VerifyChecksumFile(Paths[0], Algo, Items, Cancelled);
          for I := 0 to High(Items) do
          begin
            Lines := Lines + [Format('%-8s %s',
              [ChecksumVerifyStatusText(Items[I].Status), Items[I].RelName])];
            if Items[I].Status <> cvsOk then
              Inc(Bad);
          end;
          Status := Format(T('ui.checksum.verified', '%d checked, %d not OK: %s'),
            [Length(Items), Bad, ExtractFileName(Paths[0])]);
        end
        else
        begin
          Files := CollectChecksumFiles(Paths, Base);
          for I := 0 to High(Files) do
          begin
            if Cancelled() then
            begin
              Done := False;
              Break;
            end;
            try
              Hash := HashFileHex(Files[I].Path, Algo, Cancelled);
            except
              on E: Exception do
              begin
                Hash := 'ERROR: ' + E.Message;
                Inc(Bad);
              end;
            end;
            if (Hash = '') and Cancelled() then
            begin
              Done := False;
              Break;
            end;
            Lines := Lines + [FormatChecksumLine(Hash, Files[I].RelName)];
          end;
          SaveName := ChecksumSaveFileName(Files, Base, Algo);
          Status := Format(T('ui.checksum.done', '%d files'), [Length(Files)]);
          if Bad > 0 then
            Status := Status + Format(T('ui.checksum.errors', ', %d not read'), [Bad]);
        end;
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          // Cancelled (Esc on the stub, or the window is going away).
          if Token.IsCancellationRequested or not FAlive then
            Exit;
          FChecksumToken := nil;
          CloseStub;
          if not Done then
            Exit;
          if Err <> '' then
          begin
            OpenStub(skShellInfo, Title, Err);
            Exit;
          end;
          FChecksumSaveName := SaveName;
          ShowChecksumResult(Title, Status, Lines, AVerify);
        end);
    end).Start;
end;

procedure TDualPanelWindow.ShowChecksumResult(const ATitle, AStatus: string;
  const ALines: TArray<string>; AVerify: Boolean);
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  FChecksumLines := Copy(ALines);
  FDialogKind := hdkChecksumResult;
  FDialog.Open(BuildChecksumResultDialog(ATitle, AStatus, ALines, AVerify), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.DispatchChecksumCommand(AKind: THostDialogKind;
  const AControlId: string);
var
  Idx: Integer;
begin
  if AKind = hdkChecksumOptions then
  begin
    Idx := FDialog.GetListSelectedIndex('algo');
    FDialog.Close;
    if DialogCmdIsAccept(AControlId) then
    begin
      FChecksumAlgoIndex := EnsureRange(Idx, 0, Ord(High(TChecksumAlgo)));
      StartChecksumJob(FChecksumAlgoIndex, False);
    end;
    NotifyChanged;
    Exit;
  end;
  // Result list: Copy and Save keep it open.
  if SameText(AControlId, 'copy') then
  begin
    ClipboardSet(string.Join(sLineBreak, FChecksumLines));
    FDialog.SetLabelText('status', T('ui.checksum.copied', 'Copied to the clipboard'));
    Exit;
  end;
  if SameText(AControlId, 'save') then
  begin
    try
      TFile.WriteAllText(FChecksumSaveName,
        string.Join(sLineBreak, FChecksumLines) + sLineBreak, TEncoding.UTF8);
      FDialog.SetLabelText('status', T('ui.checksum.saved', 'Saved: ') + FChecksumSaveName);
      ReloadActiveRows;
    except
      on E: Exception do
        FDialog.SetLabelText('status', E.Message);
    end;
    Exit;
  end;
  FDialog.Close;
  SetLength(FChecksumLines, 0);
  NotifyChanged;
end;

procedure TDualPanelWindow.ExternalView;
begin
  LaunchExternal(False);
end;

procedure TDualPanelWindow.ExternalEdit;
begin
  LaunchExternal(True);
end;

procedure TDualPanelWindow.RunUserCommandCurrent(const AURI, ACommandTemplate: string);
var
  Path, CmdLine, WorkDir: string;
begin
  if (AURI = '') or (Trim(ACommandTemplate) = '') then
    Exit;
  Path := FileUriToPath(AURI);
  if Path = '' then
    Exit;
  CmdLine := BuildAssocCommandLine(ACommandTemplate, Path);
  WorkDir := ExtractFilePath(Path);
  if not ShellRunDetached(CmdLine, WorkDir) then
    OpenStub(skShellInfo, 'Command failed', CmdLine)
  else
    NotifyChanged;
end;

procedure TDualPanelWindow.OpenUserMenu;
begin
  if (ActiveWorkspace.Kind <> wkPanels) or not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  if Assigned(FUserMenuHost) then
    FUserMenuHost.OpenMenu;
end;

procedure TDualPanelWindow.OpenSortMenu;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  if ActiveWorkspace.Kind <> wkPanels then
    Exit;
  if not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  if Assigned(FMenus) then
    FMenus.OpenSortMenu(Panel.SortColumn, Panel.SortDescending);
end;

procedure TDualPanelWindow.OpenColumnModeMenu;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  if ActiveWorkspace.Kind <> wkPanels then
    Exit;
  if not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  Ws := ActiveWorkspace;
  Panel := ActivePanel(Ws);
  if Assigned(FMenus) then
    FMenus.OpenColumnModeMenu(Panel.ColumnMode);
end;

procedure TDualPanelWindow.OpenAboutDialog;
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkHelp;
  FDialog.Open(BuildAboutDialog, DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.OpenPluginListDialog;
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  CloseTransientUiBeforeDialog;

  FDialogKind := hdkHelp;
  FDialog.Open(BuildPluginListDialog(HostPluginListDisplayLabels), DialogCommand);
  NotifyChanged;
end;

function TDualPanelWindow.CurrentHelpScreen: THelpScreen;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Result := Default(THelpScreen);
  Result.ConsoleMode := FConsoleMode;
  Result.TopMenuActive := Assigned(FTopMenu) and FTopMenu.Active;
  if OverlayDialogVisible then
    Result.DialogKind := FDialogKind
  else
    Result.DialogKind := hdkNone;
  Result.SearchActive := OverlaySearchActive;
  Result.JobOverlay := OverlayJobActive;
  Result.UserMenu := OverlayUserMenuVisible;
  Result.SortMenu := OverlaySortMenuVisible;
  Result.ColumnModeMenu := OverlayColumnModeMenuVisible;
  Result.DrivePopup := OverlayDrivePopupVisible;
  Ws := ActiveWorkspace;
  Result.WorkspaceKind := Ws.Kind;
  Result.CmdFocused := CmdFocused;
  if Ws.Kind = wkPanels then
    Result.PanelURI := ActiveTab(ActivePanel(Ws)).CurrentURI;
end;

procedure TDualPanelWindow.OpenHelp;
var
  Screen: THelpScreen;
begin
  if HelpVisible then
    Exit;
  Screen := CurrentHelpScreen;
  // Console mode shows no panels to paint the help over: go back to them.
  if FConsoleMode then
  begin
    KeymapToggleConsole;
    if FConsoleMode then
      Exit;
  end;
  if not Assigned(FHelp) then
  begin
    FHelp := THelpViewer.Create(Theme);
    FHelp.OnChanged := HelpChanged;
  end;
  // The help window is modal over menus and dialogs alike, so they stay
  // open underneath: Esc returns to where F1 was pressed.
  if FHelp.Open(HelpTopicForScreen(Screen)) then
  begin
    NotifyChanged;
    Exit;
  end;
  // No help\<language>\index.md next to the exe: the built-in key summary.
  if not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkHelp;
  FDialog.Open(BuildHelpDialog, DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.HelpChanged(Sender: TObject);
begin
  if FAlive then
    NotifyChanged;
end;

function TDualPanelWindow.HelpVisible: Boolean;
begin
  Result := Assigned(FHelp) and FHelp.Visible;
end;

procedure TDualPanelWindow.OpenFolderHistoryDialog;
begin
  FFolderHistory.OpenList;
end;

procedure TDualPanelWindow.OpenCmdHistoryDialog;
begin
  FCmdHistory.OpenList;
end;

procedure TDualPanelWindow.OpenFileHistoryDialog;
begin
  FFileHistory.OpenList;
end;

procedure TDualPanelWindow.HostOpenHistoryFile(const AURI: string; AEdit: Boolean);
var
  Path: string;
begin
  // A local file that is gone would open as a new empty buffer in F4 (the
  // editor creates files on save) -- say so instead; Del removes the entry.
  Path := FileUriToPath(AURI);
  if (Path <> '') and not TFile.Exists(Path) then
  begin
    OpenStub(skShellInfo, T('ui.fileHistory.missingTitle', 'File not found'), Path);
    Exit;
  end;
  if AEdit then
    RequestOpenEditor(AURI)
  else
    RequestOpenViewer(AURI);
end;

procedure TDualPanelWindow.HostGotoHistoryFile(const AURI: string);
var
  Path, Parent: string;
begin
  Path := FileUriToPath(AURI);
  if Path <> '' then
  begin
    if not TDirectory.Exists(ExtractFileDir(Path)) then
    begin
      OpenStub(skShellInfo, T('ui.fileHistory.missingTitle', 'File not found'), Path);
      Exit;
    end;
    GotoFileLocation(Path);
    Exit;
  end;
  // Archive / SFTP: parent in the same VFS, cursor on the name.
  Parent := ParentVfsUri(AURI);
  if Parent = '' then
    Exit;
  FPendingSelectName := VfsUriTitle(AURI);
  FPendingSelectSide := ActiveWorkspace.State.ActiveSide;
  NavigateActiveTo(Parent);
end;

procedure TDualPanelWindow.OpenFolderHotlistDialog;
begin
  FFolderHotlist.OpenList;
end;

procedure TDualPanelWindow.BeginFolderHotlistAdd;
begin
  FFolderHotlist.BeginAdd;
end;

procedure TDualPanelWindow.OpenWorkspaceLibraryDialog;
begin
  FWorkspaceLibrary.OpenList;
end;

procedure TDualPanelWindow.BeginWorkspaceLibrarySave;
begin
  FWorkspaceLibrary.BeginSave;
end;

procedure TDualPanelWindow.OpenSshConnectionsDialog;
begin
  FSshConnections.OpenList;
end;

procedure TDualPanelWindow.OpenUserAssociationsDialog;
begin
  FUserAssociations.OpenList;
end;

procedure TDualPanelWindow.OpenSshTerminal(const AConnectionId: string);
begin
  OpenTerminal(cShellProfileSshPrefix + AConnectionId, ActiveLocalPath);
end;

function TDualPanelWindow.WorkspaceLibraryId: string;
begin
  Result := WorkspaceLiveId;
end;

procedure TDualPanelWindow.RestoreWorkspaceLibrary(const AId: string);
var
  Ws: TDualPanelWorkspaceTab;
begin
  if AId = '' then
    Exit;
  if not WorkspaceLibraryRestore(AId) then
    Exit;
  if not FAlive then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if IsWorkspaceUri(ActiveTab(Ws.State.LeftPanel).CurrentURI) then
    LoadSide(psLeft);
  if IsWorkspaceUri(ActiveTab(Ws.State.RightPanel).CurrentURI) then
    LoadSide(psRight);
end;

procedure TDualPanelWindow.OpenThemeDialog;
begin
  FSettings.OpenTheme;
end;

procedure TDualPanelWindow.OpenColumnsConfigDialog;
begin
  FSettings.OpenColumns;
end;

procedure TDualPanelWindow.OpenDisplayDialog;
begin
  FSettings.OpenDisplay;
end;

procedure TDualPanelWindow.OpenExternalToolsDialog;
begin
  FSettings.OpenExternalTools;
end;

procedure TDualPanelWindow.OpenColorCodingDialog;
begin
  FColorCoding.OpenList;
end;

procedure TDualPanelWindow.OpenKeymapDialog;
begin
  FKeymapDlg.OpenList;
end;

function TDualPanelWindow.ActiveLocalPath: string;
var
  Ws: TDualPanelWorkspaceTab;
  URI: string;
begin
  Result := '';
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  URI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  Result := FileUriToPath(URI);
end;

procedure TDualPanelWindow.BeginBranchView;
var
  RootPath: string;
  Opts: TFindOptions;
  Token: IJobCancelToken;
begin
  if not CanStartOperation then
    Exit;
  RootPath := ActiveLocalPath;
  if RootPath = '' then
  begin
    OpenStub(skShellInfo, 'Branch view', 'Not available for this location');
    Exit;
  end;

  Opts := DefaultFindOptions(RootPath, '*.*', True);
  Token := TJobCancelToken.Create;
  // No live progress UI for v1 ? the walk is off-thread and the panel just
  // navigates to the flat result list once it finishes, same as Find without
  // its dialog/overlay (see FSearchUi's AOnNavigateFindResults callback,
  // which this mirrors: RegisterFindSession + NavigateActiveTo the session
  // URI, reusing the exact same find:// panel plumbing).
  FindFilesAsync(Opts, Token,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError)
    var
      Sid: string;
    begin
      if not FAlive then
        Exit;
      Sid := RegisterFindSession(RootPath, '*.*', AHits);
      NavigateActiveTo(MakeFindSessionUri(Sid));
    end);
end;

procedure TDualPanelWindow.OpenTerminalProfileDialog;
begin
  FSettings.OpenTerminalProfiles;
end;

procedure TDualPanelWindow.OpenConsoleProfileDialog;
begin
  FSettings.OpenConsoleProfiles;
end;

procedure TDualPanelWindow.OpenDirSync;
var
  Ws: TDualPanelWorkspaceTab;
  SrcURI, DstURI: string;
  DestSide: TPanelSide;
begin
  if not Assigned(FDirSync) then
    Exit;
  Ws := ActiveWorkspace;
  SrcURI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  DestSide := OppositeSide(Ws.State.ActiveSide);
  if DestSide = psLeft then
    DstURI := ActiveTab(Ws.State.LeftPanel).CurrentURI
  else
    DstURI := ActiveTab(Ws.State.RightPanel).CurrentURI;
  FDirSync.Open(SrcURI, DstURI);
end;

procedure TDualPanelWindow.CloseUserMenu;
begin
  if Assigned(FMenus) then
    FMenus.CloseUserMenu;
end;

procedure TDualPanelWindow.CloseSortMenu;
begin
  if Assigned(FMenus) then
    FMenus.CloseSortMenu;
end;

procedure TDualPanelWindow.CloseColumnModeMenu;
begin
  if Assigned(FMenus) then
    FMenus.CloseColumnModeMenu;
end;

procedure TDualPanelWindow.HostUserMenuAction(AAction: TUserMenuAction;
  AParent: TUserMenuItem; AIndex: Integer);
begin
  if Assigned(FUserMenuHost) then
    FUserMenuHost.HandleMenuAction(AAction, AParent, AIndex);
end;

function TDualPanelWindow.HostUserMenuContext: TUserMenuContext;

  function PanelInfo(ASide: TPanelSide): TUserMenuPanelInfo;
  var
    Ws: TDualPanelWorkspaceTab;
    Tab: TTab;
    Rows: TPanelRows;
    Row: TPanelRow;
    Names, Keys: TArray<string>;

    function RowName(const ARow: TPanelRow): string;
    begin
      Result := ARow.Text;
      // Folders are listed as "name/".
      while (Result <> '') and CharInSet(Result[Length(Result)], ['/', '\']) do
        Delete(Result, Length(Result), 1);
    end;

  begin
    Result := Default(TUserMenuPanelInfo);
    Ws := ActiveWorkspace;
    if ASide = psLeft then
      Tab := ActiveTab(Ws.State.LeftPanel)
    else
      Tab := ActiveTab(Ws.State.RightPanel);
    Result.Path := FileUriToPath(Tab.CurrentURI);
    Rows := RowsForSide(ASide);
    if Length(Rows) > 0 then
    begin
      Row := Rows[EnsureRange(Tab.CursorIndex, 0, High(Rows))];
      if not Row.IsParent then
        Result.CurrentName := RowName(Row);
    end;
    Keys := TabSelectionKeys(Tab);
    for Row in Rows do
      if not Row.IsParent and SelectionKeysHas(Keys, Row.URI) then
        Names := Names + [RowName(Row)];
    if (Length(Names) = 0) and (Result.CurrentName <> '') then
      Names := [Result.CurrentName];
    Result.SelectedNames := Names;
  end;

var
  Active: TPanelSide;
begin
  Active := ActiveWorkspace.State.ActiveSide;
  Result.Active := PanelInfo(Active);
  if Active = psLeft then
    Result.Passive := PanelInfo(psRight)
  else
    Result.Passive := PanelInfo(psLeft);
end;

procedure TDualPanelWindow.HostRunUserMenuCommand(const ACommand: string);
begin
  // Like a typed command, minus clearing the command line: whatever the
  // user was typing there stays.
  SetCmdFocused(False);
  NotifyChanged;
  if Assigned(FOnRunCommand) then
    FOnRunCommand(ACommand, PanelCommandCwd);
end;

procedure TDualPanelWindow.DrawUserMenu;
begin
  if Assigned(FMenus) then
    FMenus.DrawUserMenu(Buffer);
end;

procedure TDualPanelWindow.DrawSortMenu;
begin
  if Assigned(FMenus) then
    FMenus.DrawSortMenu(Buffer);
end;

procedure TDualPanelWindow.DrawColumnModeMenu;
begin
  if Assigned(FMenus) then
    FMenus.DrawColumnModeMenu(Buffer);
end;

function TDualPanelWindow.HandleUserMenuInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FMenus) then
    Result := FMenus.HandleUserMenuInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

function TDualPanelWindow.HandleSortMenuInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FMenus) then
    Result := FMenus.HandleSortMenuInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

function TDualPanelWindow.HandleColumnModeMenuInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  if Assigned(FMenus) then
    Result := FMenus.HandleColumnModeMenuInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

procedure TDualPanelWindow.RefreshActive;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  LoadSide(Ws.State.ActiveSide);
end;

function TDualPanelWindow.ListViewHeight: Integer;
begin
  // FListTop/Bottom stay 0,0 until LayoutPanels ? treating that as ViewH=1 would
  // force ScrollOffset := CursorIndex on async list load and hide all rows above.
  if (Area.Height < 6) or (FListBottom <= FListTop) then
    Exit(0);
  Result := FListBottom - FListTop + 1;
  if Result < 1 then
    Result := 0;
end;

function TDualPanelWindow.ListWidthForSide(ASide: TPanelSide): Integer;
var
  B: TRectI;
begin
  if ASide = psLeft then
    B := FLeftBounds
  else
    B := FRightBounds;
  // List area: inner width minus scrollbar column.
  Result := B.Width - 3;
  if Result < 1 then
    Result := 0;
end;

function TDualPanelWindow.ListColCountForSide(ASide: TPanelSide): Integer;
var
  Ws: TDualPanelWorkspaceTab;
  Mode: TPanelColumnMode;
  W: Integer;
begin
  W := ListWidthForSide(ASide);
  if W < 1 then
    Exit(1);
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Mode := Ws.State.LeftPanel.ColumnMode
  else
    Mode := Ws.State.RightPanel.ColumnMode;
  Result := PanelListColumnCount(Mode, W);
end;

procedure TDualPanelWindow.SyncPanelScrollAfterLayout;
var
  Ws: TDualPanelWorkspaceTab;
  ViewH, Cols: Integer;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  OldScroll, OldCursor: Integer;
  Changed: Boolean;
begin
  ViewH := ListViewHeight;
  if ViewH < 1 then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Changed := False;
  for Side := Low(TPanelSide) to High(TPanelSide) do
  begin
    if Side = psLeft then
      Panel := Ws.State.LeftPanel
    else
      Panel := Ws.State.RightPanel;
    Tab := ActiveTab(Panel);
    OldScroll := Tab.ScrollOffset;
    OldCursor := Tab.CursorIndex;
    Rows := RowsForSide(Side);
    Cols := ListColCountForSide(Side);
    EnsureCursorVisible(Tab, Length(Rows), ViewH, Cols);
    if (Tab.ScrollOffset <> OldScroll) or (Tab.CursorIndex <> OldCursor) then
    begin
      SetActiveTab(Panel, Tab);
      if Side = psLeft then
        Ws.State.LeftPanel := Panel
      else
        Ws.State.RightPanel := Panel;
      Changed := True;
    end;
  end;
  if Changed then
    SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.EnsureCursorVisible(var ATab: TTab;
  ARowCount, AViewH: Integer; AColCount: Integer);
begin
  EnsurePanelCursorVisible(ATab, ARowCount, AViewH, AColCount);
end;

procedure TDualPanelWindow.MoveCursor(ADelta: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  ViewH, Cols: Integer;
  Side: TPanelSide;
begin
  if not GetActiveRowContext(Ws, Panel, Tab, Rows) then
    Exit;
  Side := Ws.State.ActiveSide;
  Inc(Tab.CursorIndex, ADelta);
  ViewH := ListViewHeight;
  if ViewH < 1 then
    ViewH := 1;
  Cols := ListColCountForSide(Side);
  EnsureCursorVisible(Tab, Length(Rows), ViewH, Cols);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.SwitchSide;
var
  Ws: TDualPanelWorkspaceTab;
  Other: TPanelSide;
begin
  Ws := ActiveWorkspace;
  Other := OppositeSide(Ws.State.ActiveSide);
  if not IsPanelVisible(Other) then
    Exit;
  Ws.State.ActiveSide := Other;
  SaveActiveWorkspace(Ws);
  // Tabbing into the panel currently showing a live Quick View exits it ?
  // that panel becomes the one you navigate, matching FAR's Ctrl+Q/Tab
  // interplay (a panel can't simultaneously drive the cursor and mirror
  // it). DrawPanel's IsQuickViewTarget guard would also self-heal this
  // visually next frame, but closing it explicitly here also releases the
  // decoded bitmap/cancels any in-flight decode right away.
  if PanelViewKind(Other) = pvkQuickView then
    CloseQuickView;
  NotifyShellCwdSync;
  Invalidate;
end;

function TDualPanelWindow.CanStartPanelLayoutChange(
  const Ws: TDualPanelWorkspaceTab): Boolean;
begin
  Result := False;
  if Ws.Kind <> wkPanels then
    Exit;
  if not CanStartOperation then
    Exit;
  if Assigned(FMenus) and (FMenus.UserMenuVisible or FMenus.SortMenuVisible or
     FMenus.ColumnModeMenuVisible or FMenus.StubVisible) then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    Exit;
  if FDrivePreviewActive then
    CancelDrivePreview;
  CancelFolderSize;
  Result := True;
end;

procedure TDualPanelWindow.SwapPanels;
var
  Ws: TDualPanelWorkspaceTab;
  TmpPanel: TPanelState;
  TmpPending: Boolean;
begin
  Ws := ActiveWorkspace;
  if not CanStartPanelLayoutChange(Ws) then
    Exit;

  TmpPanel := Ws.State.LeftPanel;
  Ws.State.LeftPanel := Ws.State.RightPanel;
  Ws.State.RightPanel := TmpPanel;
  // ActiveSide stays on the same physical panel (FAR Ctrl+U).

  TmpPending := FWatchPending[psLeft];
  FWatchPending[psLeft] := FWatchPending[psRight];
  FWatchPending[psRight] := TmpPending;
  if FPendingSelectSide = psLeft then
    FPendingSelectSide := psRight
  else if FPendingSelectSide = psRight then
    FPendingSelectSide := psLeft;

  InvalidatePlainTotals;
  SaveActiveWorkspace(Ws);
  LoadSide(psLeft);
  LoadSide(psRight);
  NotifyShellCwdSync;
  NotifyChanged;
end;

procedure TDualPanelWindow.EqualizeOtherPanelToActive;
var
  Ws: TDualPanelWorkspaceTab;
  Active, Other: TPanelSide;
  URI: string;
  OtherPanel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if not CanStartPanelLayoutChange(Ws) then
    Exit;

  Active := Ws.State.ActiveSide;
  Other := OppositeSide(Active);
  if not IsPanelVisible(Other) then
    Exit;
  URI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  if URI = '' then
    Exit;
  if Other = psLeft then
    OtherPanel := Ws.State.LeftPanel
  else
    OtherPanel := Ws.State.RightPanel;
  if SameVfsUri(URI, ActiveTab(OtherPanel).CurrentURI) then
    Exit;

  NavigateSideTo(Other, URI, True);
  // NavigateSideTo focuses the destination side ? keep focus on the active panel.
  Ws := ActiveWorkspace;
  Ws.State.ActiveSide := Active;
  SaveActiveWorkspace(Ws);
  NotifyShellCwdSync;
  NotifyChanged;
end;

procedure TDualPanelWindow.EqualizeActivePanelFromOther;
var
  Ws: TDualPanelWorkspaceTab;
  Active, Other: TPanelSide;
  URI: string;
  OtherPanel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if not CanStartPanelLayoutChange(Ws) then
    Exit;

  Active := Ws.State.ActiveSide;
  Other := OppositeSide(Active);
  if Other = psLeft then
    OtherPanel := Ws.State.LeftPanel
  else
    OtherPanel := Ws.State.RightPanel;
  URI := ActiveTab(OtherPanel).CurrentURI;
  if URI = '' then
    Exit;
  if SameVfsUri(URI, ActiveTab(ActivePanel(Ws)).CurrentURI) then
    Exit;

  NavigateSideTo(Active, URI, True);
  NotifyChanged;
end;

function TDualPanelWindow.IsPanelVisible(ASide: TPanelSide): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Result := Ws.State.LeftVisible
  else
    Result := Ws.State.RightVisible;
end;

procedure TDualPanelWindow.TogglePanelVisible(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  WillHide: Boolean;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    WillHide := Ws.State.LeftVisible
  else
    WillHide := Ws.State.RightVisible;

  // FAR: at least one panel stays visible.
  if WillHide then
  begin
    if ASide = psLeft then
    begin
      if not Ws.State.RightVisible then
        Exit;
      Ws.State.LeftVisible := False;
      if Ws.State.ActiveSide = psLeft then
        Ws.State.ActiveSide := psRight;
    end
    else
    begin
      if not Ws.State.LeftVisible then
        Exit;
      Ws.State.RightVisible := False;
      if Ws.State.ActiveSide = psRight then
        Ws.State.ActiveSide := psLeft;
    end;
  end
  else if ASide = psLeft then
    Ws.State.LeftVisible := True
  else
    Ws.State.RightVisible := True;

  SaveActiveWorkspace(Ws);
  SyncDirWatches;
  NotifyChanged;
end;

function TDualPanelWindow.PanelViewKind(ASide: TPanelSide): TPanelViewKind;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Result := Ws.State.LeftPanel.ViewKind
  else
    Result := Ws.State.RightPanel.ViewKind;
end;

procedure TDualPanelWindow.SetPanelViewKind(ASide: TPanelSide; AKind: TPanelViewKind);
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Ws.State.LeftPanel.ViewKind := AKind
  else
    Ws.State.RightPanel.ViewKind := AKind;
  SaveActiveWorkspace(Ws);
end;

procedure TDualPanelWindow.ToggleAdjacentInfoPanel;
var
  Ws: TDualPanelWorkspaceTab;
  Other: TPanelSide;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Other := OppositeSide(Ws.State.ActiveSide);
  if not IsPanelVisible(Other) then
  begin
    if Other = psLeft then
      Ws.State.LeftVisible := True
    else
      Ws.State.RightVisible := True;
    SaveActiveWorkspace(Ws);
    SyncDirWatches;
  end;
  if PanelViewKind(Other) = pvkInfo then
    SetPanelViewKind(Other, pvkFiles)
  else
  begin
    // One info panel at a time.
    if PanelViewKind(Ws.State.ActiveSide) = pvkInfo then
      SetPanelViewKind(Ws.State.ActiveSide, pvkFiles);
    SetPanelViewKind(Other, pvkInfo);
  end;
  NotifyChanged;
end;

procedure TDualPanelWindow.SyncWindowTitle;
begin
  Title := ActiveWorkspace.Title;
end;

procedure TDualPanelWindow.SelectWorkspace(AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
begin
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  if AIndex = FState.ActiveWorkspaceIndex then
    Exit;
  FState.ActiveWorkspaceIndex := AIndex;
  SyncWindowTitle;
  Ws := ActiveWorkspace;
  if Ws.Kind = wkPanels then
    ReloadActiveRows
  else
    SyncDirWatches;
  Invalidate;
end;

procedure TDualPanelWindow.RemoveWorkspaceTabAt(AIndex: Integer);
var
  ReturnIdx: Integer;
  Id, OriginId: Cardinal;
  Ed: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
  WasDocument, WasTerminal: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  Id := FState.WorkspaceTabs[AIndex].Id;
  OriginId := FState.WorkspaceTabs[AIndex].OriginWorkspaceId;
  WasDocument := FState.WorkspaceTabs[AIndex].Kind = wkDocument;
  WasTerminal := FState.WorkspaceTabs[AIndex].Kind = wkTerminal;
  if WasDocument and Assigned(FDocuments) and
     FDocuments.TryGetValue(Id, Ed) then
  begin
    Ed.OnCloseRequest := nil;
    Ed.OnContentChanged := nil;
    FDocuments.Remove(Id);
    TThread.ForceQueue(nil,
      procedure
      begin
        Ed.Free;
      end);
  end;
  if WasTerminal and Assigned(FTerminals) and
     FTerminals.TryGetValue(Id, Term) then
  begin
    Term.OnCloseRequest := nil;
    Term.OnContentChanged := nil;
    FTerminals.Remove(Id);
    TThread.ForceQueue(nil,
      procedure
      begin
        Term.Free;
      end);
  end;
  TDualPanelTabManager.RemoveWorkspaceAt(FState.WorkspaceTabs, AIndex);
  ReturnIdx := -1;
  if (WasDocument or WasTerminal) and (OriginId <> 0) then
    ReturnIdx := TDualPanelTabManager.FindWorkspaceIndexById(
      FState.WorkspaceTabs, OriginId);
  FState.ActiveWorkspaceIndex := TDualPanelTabManager.ActiveIndexAfterRemove(
    FState.ActiveWorkspaceIndex, AIndex, Length(FState.WorkspaceTabs), ReturnIdx);
  SyncWindowTitle;
  if ActiveWorkspace.Kind = wkPanels then
    ReloadActiveRows
  else
    SyncDirWatches;
  Invalidate;
end;

procedure TDualPanelWindow.CloseHostDocument(AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
begin
  Ws := FState.WorkspaceTabs[AIndex];
  if Assigned(FDocuments) and FDocuments.TryGetValue(Ws.Id, Ed) then
  begin
    // Activate so AskSave dialog paints on the document tab.
    if AIndex <> FState.ActiveWorkspaceIndex then
      SelectWorkspace(AIndex);
    Ed.BeginClose;
  end
  else
    RemoveWorkspaceTabAt(AIndex);
end;

procedure TDualPanelWindow.CloseHostTerminal(AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
begin
  Ws := FState.WorkspaceTabs[AIndex];
  // No ask-to-close flow: CloseWorkspace fires OnCloseRequest synchronously
  // (TBaseConsoleWindow.DoClose), which TerminalCloseRequest turns into
  // RemoveWorkspaceTabAt for us.
  if Assigned(FTerminals) and FTerminals.TryGetValue(Ws.Id, Term) then
    Term.CloseWorkspace
  else
    RemoveWorkspaceTabAt(AIndex);
end;

procedure TDualPanelWindow.CloseWorkspace(AIndex: Integer);
begin
  TDualPanelTabManager.DispatchCloseWorkspace(FEmbeddedHost,
    TDualPanelTabManager.ClassifyCloseWorkspace(AIndex, FState.WorkspaceTabs),
    AIndex);
end;

function TDualPanelWindow.DocumentForWorkspace(AIndex: Integer): TEditorWindow;
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  Ws := FState.WorkspaceTabs[AIndex];
  if Ws.Kind <> wkDocument then
    Exit;
  if not Assigned(FDocuments) then
    Exit;
  if FDocuments.TryGetValue(Ws.Id, Ed) then
    Result := Ed;
end;

function TDualPanelWindow.ActiveDocument: TEditorWindow;
begin
  Result := DocumentForWorkspace(FState.ActiveWorkspaceIndex);
end;

procedure TDualPanelWindow.ClearAllDocuments;
var
  Pair: TPair<Cardinal, TEditorWindow>;
  Ed: TEditorWindow;
  Ids: TArray<Cardinal>;
  I, N: Integer;
begin
  if not Assigned(FDocuments) then
    Exit;
  N := 0;
  SetLength(Ids, FDocuments.Count);
  for Pair in FDocuments do
  begin
    Ids[N] := Pair.Key;
    Inc(N);
  end;
  for I := 0 to N - 1 do
  begin
    if FDocuments.TryGetValue(Ids[I], Ed) then
    begin
      Ed.OnCloseRequest := nil;
      Ed.OnContentChanged := nil;
      FDocuments.Remove(Ids[I]);
      Ed.Free;
    end;
  end;
  FDocuments.Clear;
end;

procedure TDualPanelWindow.DocumentContentChanged(Sender: TObject);
var
  Ed: TEditorWindow;
  I: Integer;
begin
  if not FAlive or not (Sender is TEditorWindow) then
    Exit;
  Ed := TEditorWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkDocument, Ed.Id);
  if I >= 0 then
  begin
    if not FState.WorkspaceTabs[I].TitleCustom then
      FState.WorkspaceTabs[I].Title := Ed.TabCaption;
    FState.WorkspaceTabs[I].ViewOnly := Ed.ViewOnly;
    if I = FState.ActiveWorkspaceIndex then
      SyncWindowTitle;
  end;
  NotifyChanged;
end;

procedure TDualPanelWindow.DocumentCloseRequest(Sender: TObject);
var
  Ed, Found: TEditorWindow;
  I: Integer;
  IsStillRegistered: Boolean;
begin
  if not (Sender is TEditorWindow) then
    Exit;
  Ed := TEditorWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkDocument, Ed.Id);
  IsStillRegistered := (I >= 0) and Assigned(FDocuments) and
    FDocuments.TryGetValue(Ed.Id, Found) and (Found = Ed);
  if IsStillRegistered then
  begin
    RemoveWorkspaceTabAt(I);
    NotifyChanged;
  end;
end;

procedure TDualPanelWindow.OpenDocument(const AURI: string; AViewOnly: Boolean);
var
  I: Integer;
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
  Cap: string;
begin
  if AURI = '' then
    Exit;
  // Alt+F11 history: every F3/F4, re-activating an already open tab included.
  FileHistoryPush(AURI, not AViewOnly);
  // Re-activate existing tab for the same URI / mode.
  I := TDualPanelTabManager.FindDocumentWorkspaceIndex(
    FState.WorkspaceTabs, AURI, AViewOnly);
  if I >= 0 then
  begin
    SelectWorkspace(I);
    NotifyChanged;
    Exit;
  end;

  Cap := FileUriTitle(AURI);
  if Cap = '' then
    Cap := 'Document';
  Ed := TEditorWindow.Create(Theme, FNextTabId);
  Ed.Embedded := True;
  Ed.OnContentChanged := DocumentContentChanged;
  Ed.OnCloseRequest := DocumentCloseRequest;
  Ed.Open(AURI, AViewOnly);

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextTabId, TDualPanelTabManager.EmbeddedDocumentTitle(Ed.TabCaption, Cap),
    wkDocument, ActiveWorkspace.Id);
  Inc(FNextTabId);
  Ws.DocURI := AURI;
  Ws.ViewOnly := AViewOnly;

  FDocuments.AddOrSetValue(Ws.Id, Ed);
  // Insert after the current session tab (not always at the end).
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);
  SyncWindowTitle;
  SyncDirWatches;
  NotifyChanged;
end;

function TDualPanelWindow.TerminalForWorkspace(AIndex: Integer): TTerminalWorkspaceWindow;
var
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(FState.WorkspaceTabs)) then
    Exit;
  Ws := FState.WorkspaceTabs[AIndex];
  if Ws.Kind <> wkTerminal then
    Exit;
  if not Assigned(FTerminals) then
    Exit;
  if FTerminals.TryGetValue(Ws.Id, Term) then
    Result := Term;
end;

function TDualPanelWindow.ActiveTerminal: TTerminalWorkspaceWindow;
begin
  Result := TerminalForWorkspace(FState.ActiveWorkspaceIndex);
end;

procedure TDualPanelWindow.ClearAllTerminals;
var
  Pair: TPair<Cardinal, TTerminalWorkspaceWindow>;
  Term: TTerminalWorkspaceWindow;
  Ids: TArray<Cardinal>;
  I, N: Integer;
begin
  if not Assigned(FTerminals) then
    Exit;
  N := 0;
  SetLength(Ids, FTerminals.Count);
  for Pair in FTerminals do
  begin
    Ids[N] := Pair.Key;
    Inc(N);
  end;
  for I := 0 to N - 1 do
  begin
    if FTerminals.TryGetValue(Ids[I], Term) then
    begin
      Term.OnCloseRequest := nil;
      Term.OnContentChanged := nil;
      FTerminals.Remove(Ids[I]);
      Term.Free;
    end;
  end;
  FTerminals.Clear;
end;

procedure TDualPanelWindow.TerminalContentChanged(Sender: TObject);
var
  Term, Found: TTerminalWorkspaceWindow;
  I: Integer;
  IsActiveTerminalTab: Boolean;
begin
  if not FAlive or not (Sender is TTerminalWorkspaceWindow) then
    Exit;
  Term := TTerminalWorkspaceWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkTerminal, Term.Id);
  IsActiveTerminalTab := (I >= 0) and Assigned(FTerminals) and
    FTerminals.TryGetValue(Term.Id, Found) and (Found = Term) and
    (I = FState.ActiveWorkspaceIndex);
  if IsActiveTerminalTab then
    SyncWindowTitle;
  NotifyChanged;
end;

procedure TDualPanelWindow.TerminalCloseRequest(Sender: TObject);
var
  Term, Found: TTerminalWorkspaceWindow;
  I: Integer;
  IsStillRegistered: Boolean;
begin
  if not (Sender is TTerminalWorkspaceWindow) then
    Exit;
  Term := TTerminalWorkspaceWindow(Sender);
  I := TDualPanelTabManager.FindWorkspaceIndexByKindAndId(
    FState.WorkspaceTabs, wkTerminal, Term.Id);
  IsStillRegistered := (I >= 0) and Assigned(FTerminals) and
    FTerminals.TryGetValue(Term.Id, Found) and (Found = Term);
  if IsStillRegistered then
  begin
    RemoveWorkspaceTabAt(I);
    NotifyChanged;
  end;
end;

procedure TDualPanelWindow.OpenTerminal(const AProfileId, ACwd: string);
var
  I: Integer;
  Ws: TDualPanelWorkspaceTab;
  Term: TTerminalWorkspaceWindow;
  Profiles: TShellProfileArray;
  ProfTitle: string;
begin
  if AProfileId = '' then
    Exit;
  SetCmdFocused(False);

  ProfTitle := AProfileId;
  Profiles := EnumerateShellProfiles;
  for I := 0 to High(Profiles) do
    if Profiles[I].Id = AProfileId then
    begin
      ProfTitle := Profiles[I].Title;
      Break;
    end;

  Term := TTerminalWorkspaceWindow.Create(Theme, FNextTabId);
  Term.CloseOnExit := FTerminalCloseOnExit;
  Term.OnContentChanged := TerminalContentChanged;
  Term.OnCloseRequest := TerminalCloseRequest;
  Term.OnCommandExecuted := RecordConsoleCommand;
  Term.OnGetCmdHistory := GetCommandHistoryItems;

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextTabId, ProfTitle, wkTerminal, ActiveWorkspace.Id);
  Inc(FNextTabId);
  Ws.TermProfileId := AProfileId;

  // Register the tab/dictionary entry *before* Start: unlike Ed.Open, PTY
  // Start can fail synchronously and fire ProcessExited -> DoCloseWorkspace
  // -> OnCloseRequest -> TerminalCloseRequest before control returns here,
  // and that handler needs to find this tab to clean it up correctly.
  FTerminals.AddOrSetValue(Ws.Id, Term);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);

  Term.Start(AProfileId, ACwd);
  // Start() may fail synchronously and already have torn the tab down via
  // TerminalCloseRequest (which picks its own fallback active tab) ? don't
  // touch ActiveWorkspaceIndex again if that happened.
  if not FTerminals.ContainsKey(Ws.Id) then
    Exit;

  SyncWindowTitle;
  SyncDirWatches;
  NotifyChanged;
end;

procedure TDualPanelWindow.NextWorkspace;
var
  Next: Integer;
begin
  Next := TDualPanelTabManager.NextWorkspaceIndex(
    FState.ActiveWorkspaceIndex, Length(FState.WorkspaceTabs));
  if Next <> FState.ActiveWorkspaceIndex then
    SelectWorkspace(Next)
  else
    NextPanelTab;
end;

procedure TDualPanelWindow.PrevWorkspace;
var
  Prev: Integer;
begin
  Prev := TDualPanelTabManager.PrevWorkspaceIndex(
    FState.ActiveWorkspaceIndex, Length(FState.WorkspaceTabs));
  if Prev <> FState.ActiveWorkspaceIndex then
    SelectWorkspace(Prev)
  else
    PrevPanelTab;
end;

procedure TDualPanelWindow.NewWorkspace;
var
  Src, Dst: TDualPanelWorkspaceTab;
  N, I: Integer;
begin
  Src := ActiveWorkspace;
  if Src.Kind <> wkPanels then
  begin
    I := TDualPanelTabManager.FindFirstPanelsWorkspaceIndex(FState.WorkspaceTabs);
    if I < 0 then
      Exit;
    Src := FState.WorkspaceTabs[I];
  end;
  N := Length(FState.WorkspaceTabs);
  Dst := TDualPanelTabManager.ClonePanelsWorkspaceFrom(Src, FNextTabId, N);
  SetLength(FState.WorkspaceTabs, N + 1);
  FState.WorkspaceTabs[N] := Dst;
  FState.ActiveWorkspaceIndex := N;
  SyncWindowTitle;
  ReloadActiveRows;
  Invalidate;
end;

procedure TDualPanelWindow.NextPanelTab;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  if Length(Panel.Tabs) = 0 then
    Exit;
  SelectPanelTab(Ws.State.ActiveSide,
    (Panel.ActiveTabIndex + 1) mod Length(Panel.Tabs));
end;

procedure TDualPanelWindow.PrevPanelTab;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  N, Idx: Integer;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  N := Length(Panel.Tabs);
  if N = 0 then
    Exit;
  Idx := Panel.ActiveTabIndex - 1;
  if Idx < 0 then
    Idx := N - 1;
  SelectPanelTab(Ws.State.ActiveSide, Idx);
end;

procedure TDualPanelWindow.NewPanelTab;
begin
  NewPanelTabOnSide(ActiveWorkspace.State.ActiveSide);
end;

procedure TDualPanelWindow.NewPanelTabOnSide(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  URI: string;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  URI := ActiveTab(Panel).CurrentURI;
  if URI = '' then
    URI := HomeUri;
  SetLength(Panel.Tabs, Length(Panel.Tabs) + 1);
  Panel.Tabs[High(Panel.Tabs)] :=
    MakeTab(FNextTabId, FileUriTitle(URI), URI);
  Inc(FNextTabId);
  Panel.ActiveTabIndex := High(Panel.Tabs);
  // Creating a tab on a side also makes that side active ? matches what
  // clicking its tab row already does, and keeps LoadSide/cursor consistent.
  Ws.State.ActiveSide := ASide;
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  LoadSide(ASide);
  Invalidate;
end;

procedure TDualPanelWindow.OpenPathAsNewTab(const APath: string);
var
  Side: TPanelSide;
begin
  if APath = '' then
    Exit;
  if not (TDirectory.Exists(APath) or TFile.Exists(APath)) then
    Exit;
  Side := ActiveWorkspace.State.ActiveSide;
  NewPanelTabOnSide(Side);
  if TDirectory.Exists(APath) then
    NavigateActiveTo(PathToFileUri(APath))
  else
    GotoFileLocation(APath);
end;

procedure TDualPanelWindow.SelectPanelTab(ASide: TPanelSide; AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  if (AIndex < 0) or (AIndex > High(Panel.Tabs)) then
    Exit;
  Ws.State.ActiveSide := ASide;
  if Panel.ActiveTabIndex <> AIndex then
  begin
    Panel.ActiveTabIndex := AIndex;
    if ASide = psLeft then
      Ws.State.LeftPanel := Panel
    else
      Ws.State.RightPanel := Panel;
    SaveActiveWorkspace(Ws);
    LoadSide(ASide);
  end
  else
    SaveActiveWorkspace(Ws);
  Invalidate;
end;

procedure TDualPanelWindow.ClosePanelTab(ASide: TPanelSide; AIndex: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  I: Integer;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  if Length(Panel.Tabs) <= 1 then
    Exit;
  if (AIndex < 0) or (AIndex > High(Panel.Tabs)) then
    Exit;
  for I := AIndex to High(Panel.Tabs) - 1 do
    Panel.Tabs[I] := Panel.Tabs[I + 1];
  SetLength(Panel.Tabs, Length(Panel.Tabs) - 1);
  if Panel.ActiveTabIndex > AIndex then
    Dec(Panel.ActiveTabIndex)
  else if Panel.ActiveTabIndex >= Length(Panel.Tabs) then
    Panel.ActiveTabIndex := High(Panel.Tabs);
  Ws.State.ActiveSide := ASide;
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  LoadSide(ASide);
  Invalidate;
end;

function TDualPanelWindow.HitPanelTabAtCol(ASide: TPanelSide;
  const ABounds: TRectI; ACol: Integer; out AIndex: Integer;
  out AIsClose: Boolean): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Result := uDualPanelTabs.HitPanelTabAtCol(Panel, ABounds, ACol, AIndex, AIsClose);
end;

function TDualPanelWindow.SelectPanelTabAtCol(ASide: TPanelSide;
  const ABounds: TRectI; ACol: Integer): Boolean;
var
  Idx: Integer;
  IsClose: Boolean;
  Ws: TDualPanelWorkspaceTab;
  TabCount: Integer;
begin
  Result := HitPanelTabAtCol(ASide, ABounds, ACol, Idx, IsClose);
  if not Result then
    Exit;
  if IsClose then
    ClosePanelTab(ASide, Idx)
  else
  begin
    SelectPanelTab(ASide, Idx);
    Ws := ActiveWorkspace;
    if ASide = psLeft then
      TabCount := Length(Ws.State.LeftPanel.Tabs)
    else
      TabCount := Length(Ws.State.RightPanel.Tabs);
    if TabCount > 1 then
    begin
      if ASide = psLeft then
        ArmTabDrag(cTabDragPanelLeft, Idx, ACol, ABounds.Top)
      else
        ArmTabDrag(cTabDragPanelRight, Idx, ACol, ABounds.Top);
    end;
  end;
end;

function TDualPanelWindow.HitWorkspaceTabAtCol(ACol: Integer; out AIndex: Integer;
  out AIsClose: Boolean): Boolean;
begin
  Result := uDualPanelTabs.HitWorkspaceTabAtCol(FState.WorkspaceTabs,
    ACol, AIndex, AIsClose);
end;

procedure TDualPanelWindow.ArmTabDrag(AKind, AFrom, ACol, ARow: Integer);
begin
  CancelFileDrag;
  CancelTabDrag;
  if not CanArmTabDrag(AKind, AFrom, Length(FState.WorkspaceTabs)) then
    Exit;
  FTabDragKind := AKind;
  FTabDragFrom := AFrom;
  FTabDragHover := AFrom;
  FTabDragArmed := True;
  FTabDragActive := False;
  FTabDragStartCol := ACol;
  FTabDragStartRow := ARow;
end;

procedure TDualPanelWindow.CancelTabDrag;
begin
  if ResetTabDrag(FTabDragKind, FTabDragFrom, FTabDragHover,
     FTabDragArmed, FTabDragActive) then
    NotifyChanged;
end;

function TDualPanelWindow.UpdateTabDrag(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := StepTabDrag(FDragHost, FTabDragArmed, FTabDragActive, FTabDragKind,
    FTabDragHover, FTabDragStartCol, FTabDragStartRow, ALocalCol, ALocalRow,
    FLeftBounds, FRightBounds);
end;

procedure TDualPanelWindow.CommitWorkspaceTabDrag(AFromIdx, AToIdx: Integer);
begin
  if TDualPanelTabManager.ReorderWorkspace(FState.WorkspaceTabs,
    FState.ActiveWorkspaceIndex, AFromIdx, AToIdx) then
  begin
    SyncWindowTitle;
    if ActiveWorkspace.Kind = wkPanels then
      ReloadActiveRows
    else
      SyncDirWatches;
  end;
end;

procedure TDualPanelWindow.CommitPanelTabDrag(AFromIdx, AToIdx: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Side: TPanelSide;
begin
  if not TabDragPanelSide(FTabDragKind, Side) then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if Side = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  if not TDualPanelTabManager.ReorderTab(Panel.Tabs, Panel.ActiveTabIndex,
    AFromIdx, AToIdx) then
    Exit;
  if Side = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  LoadSide(Side);
end;

procedure TDualPanelWindow.CommitTabDrag;
begin
  case ClassifyTabDragCommit(FTabDragActive, FTabDragKind) of
    tdcCancel:
      begin
        CancelTabDrag;
        Exit;
      end;
    tdcWorkspace:
      CommitWorkspaceTabDrag(FTabDragFrom, FTabDragHover);
  else
    CommitPanelTabDrag(FTabDragFrom, FTabDragHover);
  end;
  ResetTabDrag(FTabDragKind, FTabDragFrom, FTabDragHover,
    FTabDragArmed, FTabDragActive);
  NotifyChanged;
end;

function TDualPanelWindow.SelectWorkspaceAtCol(ACol: Integer): Boolean;
var
  Idx: Integer;
  IsClose: Boolean;
begin
  Result := HitWorkspaceTabAtCol(ACol, Idx, IsClose);
  if not Result then
    Exit;
  if IsClose then
    CloseWorkspace(Idx)
  else
  begin
    SelectWorkspace(Idx);
    ArmTabDrag(cTabDragWorkspace, Idx, ACol, 1);
  end;
end;

function TDualPanelWindow.BeginRenameWorkspaceAtCol(ACol: Integer): Boolean;
var
  Idx: Integer;
  IsClose: Boolean;
begin
  Result := False;
  if DialogVisible or not HitWorkspaceTabAtCol(ACol, Idx, IsClose) or IsClose then
    Exit;
  Result := True;
  CancelTabDrag;
  SelectWorkspace(Idx);
  FRenameWorkspaceId := FState.WorkspaceTabs[Idx].Id;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkWorkspaceTabRename;
  FDialog.Open(BuildInputDialog(
    T('ui.workspace.tabRenameTitle', 'Rename tab'),
    T('ui.workspace.namePrompt', 'Name:'),
    FState.WorkspaceTabs[Idx].Title), DialogCommand);
end;

procedure TDualPanelWindow.ApplyWorkspaceTabTitle(const AName: string);
var
  Idx: Integer;
  Name: string;
begin
  Name := Trim(AName);
  if Name = '' then
    Exit;
  Idx := TDualPanelTabManager.FindWorkspaceIndexById(
    FState.WorkspaceTabs, FRenameWorkspaceId);
  if Idx < 0 then
    Exit;
  FState.WorkspaceTabs[Idx].Title := Name;
  FState.WorkspaceTabs[Idx].TitleCustom := True;
  if Idx = FState.ActiveWorkspaceIndex then
    SyncWindowTitle;
end;

procedure TDualPanelWindow.DrawWorkspaceTabBar(AWidth: Integer);
var
  Names: TArray<string>;
  I, X, CloseCol: Integer;
  ShowClose: Boolean;
  Cap: string;
  TabFg, TabBg, CloseFg, Discard: TAlphaColor;
  DragHover: Boolean;
begin
  if not Assigned(Theme) then
    Exit;
  ShowClose := Length(FState.WorkspaceTabs) > 1;
  SetLength(Names, Length(FState.WorkspaceTabs));
  for I := 0 to High(FState.WorkspaceTabs) do
    if ShowClose then
      Names[I] := FState.WorkspaceTabs[I].Title + ' ' + cTabCloseChar
    else
      Names[I] := FState.WorkspaceTabs[I].Title;
  // Row 1: Dual Panel Tabs directly under the menu.
  Theme.DrawTabBar(Buffer, TRectI.Make(0, 1, AWidth - 1, 1), Names,
    FState.ActiveWorkspaceIndex, WidgetState, tbkWorkspace);
  if ShowClose then
    ResolveChrome(pcpCloseMark, True, CloseFg, Discard);
  // Repaint close marks + drag hover highlight.
  X := 0;
  for I := 0 to High(FState.WorkspaceTabs) do
  begin
    Cap := WorkspaceTabCaption(FState.WorkspaceTabs[I].Title, ShowClose);
    DragHover := FTabDragActive and (FTabDragKind = cTabDragWorkspace) and
      (I = FTabDragHover) and (I <> FState.ActiveWorkspaceIndex);
    if I = FState.ActiveWorkspaceIndex then
      ResolveChrome(pcpWorkspaceTabActive, True, TabFg, TabBg)
    else if DragHover then
      ResolveChrome(pcpWorkspaceTabActive, True, TabFg, TabBg)
    else
      ResolveChrome(pcpWorkspaceTabIdle, False, TabFg, TabBg);
    if DragHover then
      PutGridText(Buffer, X, 1, Cap, TabFg, TabBg);
    if ShowClose then
    begin
      CloseCol := TabCaptionCloseCol(X, Cap, True, False);
      PaintTabCloseMark(Buffer, CloseCol, 1,
        ContrastingGlyphFg(TabBg, CloseFg, TabFg), TabBg);
    end;
    Inc(X, Length(Cap) + 1);
  end;
end;

procedure TDualPanelWindow.LayoutPanels(AWidth, AHeight: Integer);
begin
  ComputePanelLayout(AWidth, AHeight, IsPanelVisible(psLeft),
    IsPanelVisible(psRight), FLeftBounds, FRightBounds, FListTop, FListBottom);
end;

procedure TDualPanelWindow.ExecuteTopMenuAction(AAction: TTopMenuAction);
begin
  DispatchTopMenuAction(FKeymapHost, AAction);
end;

procedure TDualPanelWindow.DrawMenuBar(AWidth: Integer);
begin
  if Assigned(FTopMenu) then
    FTopMenu.DrawTopBar(Buffer, AWidth)
  else
    FillGridRect(Buffer, 0, 0, AWidth - 1, 0, ' ', cMenuFg, cMenuBg);
end;

procedure TDualPanelWindow.DrawScrollBar(AX, ATop, ABottom, APos, ACount,
  AViewH: Integer; ADialogStyle: Boolean);
begin
  uDualPanelDrawUtils.DrawPanelScrollBar(
    Buffer, AX, ATop, ABottom, APos, ACount, AViewH, Theme, ADialogStyle);
end;

procedure TDualPanelWindow.ApplyColumnMode(ASide: TPanelSide; AMode: TPanelColumnMode);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  if Panel.ColumnMode = AMode then
    Exit;
  Panel.ColumnMode := AMode;
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  NotifyChanged;
end;

procedure TDualPanelWindow.SyncSideSort(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  M: IPanelModel;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  M := ModelForSide(ASide);
  if Assigned(M) then
    M.SetSort(Panel.SortColumn, Panel.SortDescending);
end;

procedure TDualPanelWindow.SyncSideShowHidden(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  M: IPanelModel;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  M := ModelForSide(ASide);
  if Assigned(M) then
    M.SetShowHidden(Panel.ShowHiddenFiles);
end;

procedure TDualPanelWindow.ToggleShowHidden(ASide: TPanelSide);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Panel.ShowHiddenFiles := not Panel.ShowHiddenFiles;
  if ASide = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  SyncSideShowHidden(ASide);
  NotifyChanged;
end;

procedure TDualPanelWindow.CommitSortAndRestoreCursor(ASide: TPanelSide;
  var AWs: TDualPanelWorkspaceTab; var APanel: TPanelState; var ATab: TTab;
  const ACurURI: string);
var
  Rows: TPanelRows;
  I: Integer;
  M: IPanelModel;
begin
  if ASide = psLeft then
    AWs.State.LeftPanel := APanel
  else
    AWs.State.RightPanel := APanel;
  AWs.State.ActiveSide := ASide;
  SaveActiveWorkspace(AWs);

  M := ModelForSide(ASide);
  if Assigned(M) then
    M.SetSort(APanel.SortColumn, APanel.SortDescending);

  Rows := RowsForSide(ASide);
  if ACurURI <> '' then
    for I := 0 to High(Rows) do
      if Rows[I].URI = ACurURI then
      begin
        ATab.CursorIndex := I;
        Break;
      end;
  EnsureCursorVisible(ATab, Length(Rows), Max(ListViewHeight, 1),
    ListColCountForSide(ASide));
  SetActiveTab(APanel, ATab);
  if ASide = psLeft then
    AWs.State.LeftPanel := APanel
  else
    AWs.State.RightPanel := APanel;
  SaveActiveWorkspace(AWs);
  Invalidate;
end;

procedure TDualPanelWindow.ApplyHeaderSort(ASide: TPanelSide; ACol: TPanelSortColumn);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  CurURI: string;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(ASide);
  CurURI := '';
  if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
    CurURI := Rows[Tab.CursorIndex].URI;

  CycleHeaderSort(Panel.SortColumn, Panel.SortDescending, ACol);
  CommitSortAndRestoreCursor(ASide, Ws, Panel, Tab, CurURI);
end;

procedure TDualPanelWindow.ApplySortMode(ASide: TPanelSide; ACol: TPanelSortColumn);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  CurURI: string;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if ASide = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(ASide);
  CurURI := '';
  if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
    CurURI := Rows[Tab.CursorIndex].URI;

  CycleMenuSort(Panel.SortColumn, Panel.SortDescending, ACol);
  CommitSortAndRestoreCursor(ASide, Ws, Panel, Tab, CurURI);
end;



procedure TDualPanelWindow.DrawPanelDriveLetters(const ABounds: TRectI;
  const ATab: TTab; ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
begin
  uDualPanelDrawUtils.DrawPanelDriveLetterBar(
    Buffer, ABounds, ATab, ASide, AFrame, ABodyBg,
    FDrivePreviewActive, FDrivePreviewSide, FDrivePreviewLetter);
end;

procedure TDualPanelWindow.NavigatePanelToDrive(ASide: TPanelSide; ALetter: Char);
var
  Drives: TDriveInfoArray;
  I: Integer;
  Panel: TPanelState;
  SpecialUri: string;
begin
  if FDrivePreviewActive then
  begin
    FDrivePreviewActive := False;
    FDrivePreviewLetter := #0;
  end;
  ALetter := UpCase(ALetter);
  if TryChangeDriveSpecialUri(ALetter, SpecialUri) then
  begin
    NavigateSideTo(ASide, SpecialUri);
    Exit;
  end;
  if (ALetter < 'A') or (ALetter > 'Z') then
    Exit;
  // Only RootPath is needed here -- fast (letters-only) avoids the
  // GetVolumeInformation/GetDiskFreeSpaceEx hang risk on every drive letter.
  Drives := EnumLogicalDrivesFast;
  I := IndexOfDriveLetter(Drives, ALetter);
  if I < 0 then
    Exit;
  if ASide = psLeft then
    Panel := ActiveWorkspace.State.LeftPanel
  else
    Panel := ActiveWorkspace.State.RightPanel;
  NavigateSideTo(ASide,
    ResolvePanelDriveUri(Panel.DriveDirs, ALetter, Drives[I].RootPath));
end;

procedure TDualPanelWindow.CancelDrivePreview;
begin
  if not FDrivePreviewActive then
    Exit;
  FDrivePreviewActive := False;
  FDrivePreviewLetter := #0;
  NotifyChanged;
end;

procedure TDualPanelWindow.CommitDrivePreview;
var
  Side: TPanelSide;
  Letter: Char;
  CurGlyph: Char;
  Panel: TPanelState;
begin
  if not FDrivePreviewActive then
    Exit;
  Side := FDrivePreviewSide;
  Letter := FDrivePreviewLetter;
  FDrivePreviewActive := False;
  FDrivePreviewLetter := #0;

  if Letter = #0 then
  begin
    NotifyChanged;
    Exit;
  end;

  if Side = psLeft then
    Panel := ActiveWorkspace.State.LeftPanel
  else
    Panel := ActiveWorkspace.State.RightPanel;
  CurGlyph := DriveBarGlyphFromUri(ActiveTab(Panel).CurrentURI);

  if Letter = CurGlyph then
  begin
    NotifyChanged; // clear preview highlight
    Exit;
  end;
  NavigatePanelToDrive(Side, Letter);
end;

procedure TDualPanelWindow.PreviewCyclePanelDrive(ASide: TPanelSide; ADelta: Integer);
var
  Glyphs: TArray<Char>;
  Idx, N: Integer;
  CurGlyph: Char;
  Panel: TPanelState;
begin
  if ADelta = 0 then
    Exit;
  Glyphs := EnumDriveBarGlyphs;
  N := Length(Glyphs);
  if N = 0 then
    Exit;

  if ASide = psLeft then
    Panel := ActiveWorkspace.State.LeftPanel
  else
    Panel := ActiveWorkspace.State.RightPanel;

  CurGlyph := HighlightDriveLetter(FDrivePreviewActive, FDrivePreviewSide, ASide,
    FDrivePreviewLetter, DriveBarGlyphFromUri(ActiveTab(Panel).CurrentURI));
  Idx := CycleDriveIndex(N, IndexOfDriveBarGlyph(Glyphs, CurGlyph), ADelta);

  FDrivePreviewActive := True;
  FDrivePreviewSide := ASide;
  FDrivePreviewLetter := Glyphs[Idx];
  NotifyChanged;
end;

procedure TDualPanelWindow.DrawPanelInfoContent(const ABounds: TRectI;
  ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
var
  Ws: TDualPanelWorkspaceTab;
  SrcSide: TPanelSide;
  SrcPanel: TPanelState;
  SrcTab: TTab;
  Path: string;
  Bytes: Int64;
  Files, Folders: Integer;
begin
  Ws := ActiveWorkspace;
  SrcSide := OppositeSide(ASide);
  if SrcSide = psLeft then
    SrcPanel := Ws.State.LeftPanel
  else
    SrcPanel := Ws.State.RightPanel;
  SrcTab := ActiveTab(SrcPanel);
  Path := FileUriToPath(SrcTab.CurrentURI);
  if Path = '' then
    Path := SrcTab.CurrentURI;
  EnsurePlainTotals(SrcSide, Bytes, Files, Folders);
  uDualPanelInfoPanel.DrawPanelInfoContent(Buffer, Theme, ABounds, AFrame, ABodyBg,
    Path, Bytes, Files, Folders);
end;

procedure TDualPanelWindow.DrawQuickViewContent(const ABounds: TRectI;
  ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
var
  Ws: TDualPanelWorkspaceTab;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  Panel: TPanelState;
  AbsBounds: TRectI;
  HasRow, Previewable: Boolean;
begin
  FillGridRect(Buffer, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', cFileFg, ABodyBg);

  // The active side always drives what's previewed, regardless of which
  // side is physically drawing this panel ? only reached when ASide isn't
  // the active side (IsQuickViewTarget guards that in DrawPanel).
  HasRow := GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx);
  Previewable := IsQuickViewPreviewable(HasRow,
    IsOverlayImageExtension(Row.Extension), Row);

  if not Previewable then
  begin
    ClearOverlayPreview;
    // Not a picture: text / Markdown / hex through the embedded Viewer.
    case TQuickTextView.PreviewKind(HasRow, Row) of
      qtpText:
        begin
          if not Assigned(FQuickText) then
          begin
            FQuickText := TQuickTextView.Create(Theme);
            FQuickText.OnChanged := QuickTextChanged;
          end;
          FQuickText.ShowFile(Row.URI);
          FQuickText.Paint(Buffer, ABounds, Area.Left, Area.Top);
          Exit;
        end;
      qtpAskF3:
        begin
          if Assigned(FQuickText) then
            FQuickText.Clear;
          DrawCenteredPlaceholder(Buffer, ABounds,
            T('ui.quickView.pressF3', '(press F3 to view)'), AFrame, ABodyBg);
          Exit;
        end;
    end;
    if Assigned(FQuickText) then
      FQuickText.Clear;
    DrawCenteredPlaceholder(Buffer, ABounds,
      FormatQuickViewPlaceholder(HasRow, Row), AFrame, ABodyBg);
    Exit;
  end;
  if Assigned(FQuickText) then
    FQuickText.Clear;

  // Interior only (Left+1/Right-1/Top+1/Bottom-1) ? same inset as the
  // FillGridRect above ? so the image doesn't paint over the frame
  // characters at ABounds.Left/Right/Top/Bottom. Cell bounds here are
  // window-local (like all DrawPanel geometry); the overlay Canvas pass in
  // uMainForm.FormPaint works in absolute grid cells, so offset by this
  // window's own placement before handing off.
  AbsBounds := QuickViewInteriorAbsBounds(ABounds, Area);
  if OverlayCurrentURI <> Row.URI then
    RequestOverlayPreview(Row.URI, AbsBounds)
  else
    UpdateOverlayBounds(AbsBounds);
end;

procedure TDualPanelWindow.DrawPanel(const ABounds: TRectI; const APanel: TPanelState;
  ASide: TPanelSide; AActive: Boolean);
var
  Frame, BodyBg: TAlphaColor;
  Snap: TDrawPanelSnapshot;
  IsQV: Boolean;
begin
  // Quick View (Stage 24 redo, NC/NDN/FAR/TC convention): only the
  // currently non-active side may show it. If ASide is somehow also the
  // active side (e.g. a menu action force-focused it ? see SwitchSide's
  // comment for the common path), self-heal by drawing it as a normal file
  // panel instead of a broken/self-referential preview.
  IsQV := uDualPanelPanelDraw.IsQuickViewTarget(APanel.ViewKind,
    ASide, ActiveWorkspace.State.ActiveSide);
  if AActive then
    ResolveChrome(pcpFrameActive, True, Frame, BodyBg)
  else
    ResolveChrome(pcpFrameIdle, False, Frame, BodyBg);
  DrawPanelShell(Buffer, Theme, ABounds, APanel, AActive, IsQV,
    Frame, BodyBg, cFileFg,
    PanelTabDragHoverIndex(ASide, FTabDragActive, FTabDragKind,
      cTabDragPanelLeft, cTabDragPanelRight, FTabDragHover),
    ResolveChrome);
  Snap := Default(TDrawPanelSnapshot);
  Snap.Bounds := ABounds;
  Snap.Panel := APanel;
  Snap.Tab := ActiveTab(APanel);
  Snap.Side := ASide;
  Snap.Active := AActive;
  Snap.Frame := Frame;
  Snap.BodyBg := BodyBg;
  Snap.ViewKind := APanel.ViewKind;
  Snap.IsQuickViewTarget := IsQV;
  DispatchDrawPanelBody(FPanelHost, Snap);
end;

procedure TDualPanelWindow.DrawPanelFiles(const ABounds: TRectI;
  const APanel: TPanelState; ASide: TPanelSide; AActive: Boolean;
  AFrame, ABodyBg: TAlphaColor);
var
  Files, Folders, Count, ViewH: Integer;
  Bytes: Int64;
  Tab: TTab;
  M: IPanelModel;
  Rows: TPanelRows;
  Snap: TDrawFilesSnapshot;
begin
  Tab := ActiveTab(APanel);
  M := ModelForSide(ASide);
  if Assigned(M) then
    Count := M.ItemCount
  else
    Count := 0;

  Snap := Default(TDrawFilesSnapshot);
  Snap.Bounds := ABounds;
  Snap.ListBounds := PanelListBounds(ABounds);
  Snap.Panel := APanel;
  Snap.Tab := Tab;
  Snap.Side := ASide;
  Snap.ActiveSide := ActiveWorkspace.State.ActiveSide;
  Snap.Active := AActive;
  Snap.Frame := AFrame;
  Snap.BodyBg := ABodyBg;
  Snap.DropFg := cCursorFg;
  Snap.DropBg := cMenuHot;
  Snap.Count := Count;
  if Length(Tab.SelectedURIs) > 0 then
  begin
    Rows := RowsForSide(ASide);
    PanelSelectionTotals(Tab, Rows, Bytes, Files, Folders);
    Snap.Footer := FormatPanelTotalsFooter(True, Bytes, Files, Folders,
      ABounds.Width - 2);
  end
  else
  begin
    EnsurePlainTotals(ASide, Bytes, Files, Folders);
    Snap.Footer := FormatPanelTotalsFooter(False, Bytes, Files, Folders,
      ABounds.Width - 2);
  end;
  if (Tab.CursorIndex >= 0) and (Tab.CursorIndex < Count) then
    Snap.InfoLine := FormatPanelCursorInfoLine(M.GetRow(Tab.CursorIndex),
      PanelInfoStripBounds(ABounds).Width)
  else
    Snap.InfoLine := '';
  Snap.HasTheme := Assigned(Theme);
  Snap.ThemeDouble := Assigned(Theme) and Theme.UsesDoubleLineForActivePanel;
  Snap.DropHighlight := FDropHighlightActive and (FDropHighlightSide = ASide);
  Snap.QuickSearch := FQuickSearchActive;
  Snap.Filter := FFilterBoxActive;
  ViewH := Snap.ListBounds.Height;
  Snap.PageSize := BriefPageSize(Max(ViewH, 1),
    PanelListColumnCount(APanel.ColumnMode, Snap.ListBounds.Width));
  DispatchDrawPanelFiles(Buffer, Theme, FFilesDrawHost, Snap);
end;

procedure TDualPanelWindow.DrawCommandLine(AY, AWidth: Integer);
var
  Ws: TDualPanelWorkspaceTab;
  CmdCopy: TInputLine;
begin
  if not Assigned(FCmdLineMgr) then
    Exit;
  Ws := ActiveWorkspace;
  CmdCopy := FCmdLineMgr.Cmd;
  DrawDualPanelCommandLine(FCmdLineDrawHost, Buffer, AY, AWidth,
    ActiveTab(ActivePanel(Ws)).CurrentURI, CmdCopy,
    FCmdLineMgr.Focused, FCursorVisible);
  FCmdLineMgr.Cmd := CmdCopy;
end;

function TDualPanelWindow.ChromeContext: TFunctionBarContext;
var
  S: TChromeOverlayState;
  Ws: TDualPanelWorkspaceTab;
begin
  S := Default(TChromeOverlayState);
  S.DialogVisible := Assigned(FDialog) and FDialog.Visible;
  S.DialogKind := FDialogKind;
  if S.DialogVisible then
    S.DialogChrome := FDialog.ChromeContext;
  S.DrivePopupVisible := Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible;
  S.UserMenuVisible := Assigned(FMenus) and FMenus.UserMenuVisible;
  S.SortMenuVisible := Assigned(FMenus) and FMenus.SortMenuVisible;
  S.ColumnModeMenuVisible := Assigned(FMenus) and FMenus.ColumnModeMenuVisible;
  if Assigned(FJobs) then
  begin
    S.JobPhase := FJobs.Phase;
    S.JobPresentation := FJobs.State.Presentation;
    S.JobShowsOverlay := FJobs.ShowsOverlay;
  end
  else
  begin
    S.JobPhase := pjpNone;
    S.JobPresentation := jpForeground;
    S.JobShowsOverlay := False;
  end;
  if Assigned(FSearchUi) then
    S.SearchPhase := FSearchUi.Phase
  else
    S.SearchPhase := spNone;
  S.StubVisible := Assigned(FMenus) and FMenus.StubVisible;
  S.ConsoleMode := FConsoleMode;
  Ws := ActiveWorkspace;
  S.WorkspaceKind := Ws.Kind;
  S.CurrentURI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  Result := ResolveChromeContext(S);
end;

procedure TDualPanelWindow.DrawFunctionKeys(AY, AWidth: Integer);
var
  Items, Letters: TArray<string>;
  Colors: TFunctionBarColors;
  Discard: TAlphaColor;
begin
  FunctionBarGetItems(ChromeContext, KeyModifiers, Items, Letters);
  // Themed F-key bar colours ? DrawFunctionBar already forwards to
  // Theme.DrawToolBar for the numbered tool-item segment on the right; these
  // cover the mnemonic-hint segment on the left and the base row fill (there
  // is no bare "toolbar colour" getter on IThemeRenderer, only the full
  // DrawToolBar call, so pcpListBody/pcpHotMark/pcpColumnHeader are reused
  // as the closest existing roles).
  ResolveChrome(pcpListBody, True, Colors.Fg, Colors.Bg);
  ResolveChrome(pcpHotMark, True, Colors.HotFg, Discard);
  ResolveChrome(pcpColumnHeader, True, Colors.RuleFg, Discard);
  DrawFunctionBar(Buffer, AY, AWidth, Items, Letters, KeyModifiers, Colors, Theme);
end;

function TDualPanelWindow.BuildTerminalStatusSegments: TArray<string>;
var
  Term: TTerminalWorkspaceWindow;
  Snap: TPanelStatusSnapshot;
begin
  Snap := Default(TPanelStatusSnapshot);
  Snap.Kind := wkTerminal;
  Snap.CmdFocused := CmdFocused;
  Term := ActiveTerminal;
  Snap.TermAssigned := Assigned(Term);
  if Assigned(Term) then
  begin
    Snap.TermRunning := Term.Running;
    Snap.TermTitle := ShellProfileTitle(Term.ProfileId);
  end;
  Result := AssembleStatusSegments(FStatusHost, Snap);
end;

procedure TDualPanelWindow.PopulatePanelStatusSnap(var Snap: TPanelStatusSnapshot;
  var Ws: TDualPanelWorkspaceTab);
var
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Count: Integer;
  Path, SelText, CursorText: string;
  Bytes: Int64;
  Files, Folders: Integer;
  M: IPanelModel;
  HasSel, HasCursor: Boolean;
begin
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  M := ModelForSide(Ws.State.ActiveSide);
  if Assigned(M) then
    Count := M.ItemCount
  else
    Count := 0;

  Snap.SideLabel := PanelSideStatusLabel(Ws.State.ActiveSide);
  Path := StatusPathLabel(Tab.CurrentURI);
  Snap.PosText := FormatPanelPosText(Count, Tab.CursorIndex);

  HasSel := Length(Tab.SelectedURIs) > 0;
  HasCursor := (Count > 0) and Assigned(M) and (Tab.CursorIndex >= 0) and
    (Tab.CursorIndex < Count);
  if HasSel then
  begin
    Rows := RowsForSide(Ws.State.ActiveSide);
    PanelSelectionTotals(Tab, Rows, Bytes, Files, Folders);
    SelText := FormatStatusSelText(Bytes, Files, Folders);
  end
  else
    SelText := '';
  if (not HasSel) and HasCursor then
    CursorText := M.GetRow(Tab.CursorIndex).Text
  else
    CursorText := '';
  Snap.ItemText := StatusItemText(HasSel, SelText, HasCursor, CursorText);
  if Assigned(FJobs) and FJobs.HasBusyJob and not FJobs.ShowsOverlay then
    Snap.JobStatus := FJobs.FormatStatus;

  RequestFreeSpace(Path);
  Snap.FreeText := FFreeText;
  Snap.Path := TruncateStatusPath(Path);

  if Ws.Kind = wkPanels then
  begin
    if Ws.State.ActiveSide = psLeft then
      Snap.ColMode := PanelColumnModeTitle(Ws.State.LeftPanel.ColumnMode)
    else
      Snap.ColMode := PanelColumnModeTitle(Ws.State.RightPanel.ColumnMode);
  end;
end;

function TDualPanelWindow.BuildStatusOverlaySnap(
  const APath: string): TStatusOverlaySnapshot;
begin
  Result := Default(TStatusOverlaySnapshot);
  Result.DialogKind := FDialogKind;
  if Assigned(FJobs) then
  begin
    Result.JobTitle := FJobs.Title;
    Result.JobMessage := FJobs.State.Message;
    Result.JobCurrent := FJobs.State.CurrentName;
    Result.JobStatus := FJobs.FormatStatus;
  end;
  if Assigned(FSearchUi) then
  begin
    Result.SearchMask := FSearchUi.Mask;
    Result.SearchDir := FSearchUi.CurrentDir;
    Result.SearchFound := FSearchUi.FoundCount;
    Result.SearchResultCount := Length(FSearchUi.State.Results);
  end;
  if Assigned(FMenus) then
  begin
    Result.StubText := FMenus.StubText;
    Result.StubDetail := FMenus.StubDetail;
  end;
end;

function TDualPanelWindow.BuildPanelStatusSegments: TArray<string>;
var
  Ws: TDualPanelWorkspaceTab;
  Snap: TPanelStatusSnapshot;
  Overlay: TStatusOverlaySnapshot;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind = wkTerminal then
    Exit(BuildTerminalStatusSegments);

  Snap := Default(TPanelStatusSnapshot);
  Snap.Kind := Ws.Kind;
  Snap.CmdFocused := CmdFocused;
  PopulatePanelStatusSnap(Snap, Ws);
  Overlay := BuildStatusOverlaySnap(Snap.Path);
  Snap.Chrome := MakeChromeStatus(Snap.Path, Overlay);
  Result := AssembleStatusSegments(FStatusHost, Snap);
end;

procedure TDualPanelWindow.DrawAppStatusLine(AY, AWidth: Integer);
begin
  DrawAppStatusLineRow(Buffer, Theme, AY, AWidth, BuildPanelStatusSegments,
    cMenuFg, cMenuBg);
end;

function TDualPanelWindow.OppositeSide(ASide: TPanelSide): TPanelSide;
begin
  if ASide = psLeft then
    Result := psRight
  else
    Result := psLeft;
end;

function TDualPanelWindow.CollectActiveSources: TArray<string>;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Result := CollectPanelJobSources(ActiveTab(ActivePanel(Ws)),
    RowsForSide(Ws.State.ActiveSide));
end;

procedure TDualPanelWindow.CloseJobUi;
begin
  if Assigned(FJobs) then
    FJobs.CloseJobUi;
end;

procedure TDualPanelWindow.PrepareForSystemShutdown;
var
  Term: TTerminalWorkspaceWindow;
begin
  if not FAlive then
    Exit;
  if Assigned(FTerminals) then
    for Term in FTerminals.Values do
      if Assigned(Term) then
        Term.ShutdownForSessionEnd;
  CloseSearchUi;
  if Assigned(FJobs) and FJobs.HasBusyJob then
  begin
    FJobs.CancelAll;
    FJobs.CloseAll;
  end;
  CloseDrivePopup;
  CloseUserMenu;
  CloseSortMenu;
  CloseColumnModeMenu;
  CloseStub;
  if Assigned(FDialog) then
  begin
    FDialog.OnChanged := nil;
    FDialog.Close;
  end;
  if Assigned(FLeftWatch) then
    FLeftWatch.Close;
  if Assigned(FRightWatch) then
    FRightWatch.Close;
end;

procedure TDualPanelWindow.DrawJobPopup;
begin
  if Assigned(FJobs) then
    FJobs.DrawJobPopup(Buffer, Area.Width, Area.Height);
end;

function TDualPanelWindow.CanBeginAnotherJob: Boolean;
begin
  Result := Assigned(FJobs) and FJobs.CanStartAnother;
  if Assigned(FJobs) and not FJobs.CanStartAnother then
    OpenStub(skShellInfo, 'Jobs',
      Format('At most %d jobs can run at once', [cMaxPanelJobs]));
end;

procedure TDualPanelWindow.BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  DestSide: TPanelSide;
  Sources: TArray<string>;
  DestURI, Reason: string;
begin
  if not CanBeginAnotherJob then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;

  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;

  if (AKind = pjkDelete) and ActivePanelIsWorkspace then
  begin
    WorkspaceUnlinkSelected;
    Exit;
  end;

  Ws := ActiveWorkspace;
  if AKind = pjkDelete then
    DestURI := ''
  else
  begin
    DestSide := OppositeSide(Ws.State.ActiveSide);
    if DestSide = psLeft then
      DestURI := ActiveTab(Ws.State.LeftPanel).CurrentURI
    else
      DestURI := ActiveTab(Ws.State.RightPanel).CurrentURI;
    Reason := JobDestRejectedReason(AKind, DestURI);
    if Reason <> '' then
    begin
      OpenStub(skShellInfo, JobDestFailTitle(AKind), Reason);
      Exit;
    end;
  end;

  FJobs.BeginJob(Sources, DestURI, AKind, ADeleteToRecycleBin);
end;

procedure TDualPanelWindow.BeginTransferJob(const ASources: TArray<string>;
  const ADestDirURI: string; AKind: TPanelJobKind);
begin
  if not CanBeginAnotherJob then
    Exit;
  if Length(ASources) = 0 then
    Exit;
  if (AKind <> pjkDelete) and (ADestDirURI = '') then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;
  FJobs.BeginJob(ASources, ADestDirURI, AKind, True);
end;

procedure TDualPanelWindow.BeginPackZip;
var
  Ws: TDualPanelWorkspaceTab;
  DestSide: TPanelSide;
  Sources: TArray<string>;
  DestURI, DestDir, DestZip: string;
begin
  if not CanBeginAnotherJob then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;

  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;
  if SourcesContainArchive(Sources) then
  begin
    OpenStub(skShellInfo, 'Pack failed', 'Cannot pack items from inside an archive');
    Exit;
  end;

  Ws := ActiveWorkspace;
  DestSide := OppositeSide(Ws.State.ActiveSide);
  if DestSide = psLeft then
    DestURI := ActiveTab(Ws.State.LeftPanel).CurrentURI
  else
    DestURI := ActiveTab(Ws.State.RightPanel).CurrentURI;
  if JobDestRejectedReason(pjkPack, DestURI) <> '' then
  begin
    OpenStub(skShellInfo, JobDestFailTitle(pjkPack), JobDestRejectedReason(pjkPack, DestURI));
    Exit;
  end;
  if IsSevenZipUri(DestURI) then
    FJobs.BeginJob(Sources, DestURI, pjkPack, True)
  else
  begin
    DestDir := FileUriToPath(DestURI);
    DestZip := TPath.Combine(DestDir, SuggestPackZipName(Sources));
    FJobs.BeginJob(Sources, PathToFileUri(DestZip), pjkPack, True);
  end;
end;

procedure TDualPanelWindow.BeginUnpackZip;
var
  Ws: TDualPanelWorkspaceTab;
  DestSide: TPanelSide;
  Sources: TArray<string>;
  DestURI, UnpackErr: string;
begin
  if not CanBeginAnotherJob then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;

  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;
  if not UnpackSourcesAreValid(Sources, UnpackErr) then
  begin
    if UnpackErr <> '' then
      OpenStub(skShellInfo, 'Unpack failed', UnpackErr);
    Exit;
  end;

  Ws := ActiveWorkspace;
  DestSide := OppositeSide(Ws.State.ActiveSide);
  if DestSide = psLeft then
    DestURI := ActiveTab(Ws.State.LeftPanel).CurrentURI
  else
    DestURI := ActiveTab(Ws.State.RightPanel).CurrentURI;
  if JobDestRejectedReason(pjkUnpack, DestURI) <> '' then
  begin
    OpenStub(skShellInfo, JobDestFailTitle(pjkUnpack),
      JobDestRejectedReason(pjkUnpack, DestURI));
    Exit;
  end;

  FJobs.BeginJob(Sources, DestURI, pjkUnpack, True);
end;

function TDualPanelWindow.HandleJobInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if Assigned(FJobs) then
    Result := FJobs.HandleJobInput(AKey, AShift, AKeyChar)
  else
    Result := False;
end;

procedure TDualPanelWindow.DrawDocumentContent(W, H: Integer);
var
  Doc: TEditorWindow;
  DocH: Integer;
begin
  LayoutPanels(W, H);
  SyncPanelScrollAfterLayout;
  DrawMenuBar(W);
  DrawWorkspaceTabBar(W);
  Doc := ActiveDocument;
  if not Assigned(Doc) then
    Exit;
  DocH := EmbeddedDocumentPaintHeight(H);
  if CanPaintEmbeddedContent(DocH) then
    Doc.PaintEmbedded(Buffer, 0, 2, W, DocH, Area.Left, Area.Top + 2);
end;

procedure TDualPanelWindow.DrawTerminalContent(W, H: Integer);
var
  Term: TTerminalWorkspaceWindow;
  DocH: Integer;
begin
  LayoutPanels(W, H);
  SyncPanelScrollAfterLayout;
  DrawMenuBar(W);
  DrawWorkspaceTabBar(W);
  Term := ActiveTerminal;
  if Assigned(Term) then
  begin
    DocH := EmbeddedTerminalPaintHeight(H);
    if CanPaintEmbeddedContent(DocH) then
    begin
      Term.Area := TRectI.Make(0, 2, W - 1, 2 + DocH - 1);
      Term.IsFocused := True;
      Term.Paint(Buffer);
    end;
  end;
  DrawFunctionKeys(H - 2, W);
  DrawAppStatusLine(H - 1, W);
end;

procedure TDualPanelWindow.DrawPanelsContent(W, H: Integer);
var
  Ws: TDualPanelWorkspaceTab;
begin
  LayoutPanels(W, H);
  SyncPanelScrollAfterLayout;
  DrawMenuBar(W);
  DrawWorkspaceTabBar(W);
  Ws := ActiveWorkspace;
  if Ws.State.LeftVisible then
    DrawPanel(FLeftBounds, Ws.State.LeftPanel, psLeft,
      Ws.State.ActiveSide = psLeft);
  if Ws.State.RightVisible then
    DrawPanel(FRightBounds, Ws.State.RightPanel, psRight,
      Ws.State.ActiveSide = psRight);
  DrawCommandLine(H - 3, W);
  DrawFunctionKeys(H - 2, W);
  DrawAppStatusLine(H - 1, W);
end;

procedure TDualPanelWindow.DrawContent;
var
  W, H: Integer;
  Kind: TDrawContentKind;
  Snap: TDrawOverlaySnapshot;
begin
  W := Area.Width;
  H := Area.Height;
  Kind := ClassifyDrawContent(W, H, FConsoleMode, ActiveWorkspace.Kind);
  // Quick View off screen (another workspace, console, closed): stop reading
  // and watching the previewed file.
  if Assigned(FQuickText) and not QuickViewVisible then
    FQuickText.Clear;
  case Kind of
    dckTooSmall:
      Exit;
    dckConsole:
      begin
        DrawFunctionKeys(H - 2, W);
        DrawAppStatusLine(H - 1, W);
      end;
    dckDocument:
      DrawDocumentContent(W, H);
    dckTerminal:
      DrawTerminalContent(W, H);
  else
    DrawPanelsContent(W, H);
  end;
  // Submenu / dialogs sit on top of panels, Viewer/Editor, and Terminal.
  // Document and Terminal used to skip this, so F9 dropdowns (including Edit)
  // opened in state but were painted over by PaintEmbedded / Term.Paint.
  if Kind in [dckDocument, dckTerminal, dckPanels] then
  begin
    Snap := Default(TDrawOverlaySnapshot);
    Snap.DialogVisible := Assigned(FDialog) and FDialog.Visible;
    Snap.SubmenuOpen := Assigned(FTopMenu) and FTopMenu.SubmenuOpen;
    Snap.AreaWidth := W;
    Snap.AreaHeight := H;
    DispatchDrawOverlays(FDrawHost, Snap);
    if (Kind = dckPanels) and Assigned(FCmdLineMgr) then
      FCmdLineMgr.HistoryPopup.Draw(Buffer, Theme);
    if (Kind = dckPanels) and FFilterBoxActive then
      FFilterPopup.Draw(Buffer, Theme);
    if HelpVisible then
      FHelp.Paint(Buffer, W, H, Area.Left, Area.Top);
  end;
end;

function TDualPanelWindow.SetKeyModifiers(AShift: TShiftState): Boolean;
var
  Doc: TEditorWindow;
  WasCtrl, WasAlt, CtrlJustReleased, AltJustReleased: Boolean;
begin
  // Embedded Viewer/Editor draws its own F-bar from Doc.KeyModifiers.
  WasCtrl := ssCtrl in KeyModifiers;
  WasAlt := ssAlt in KeyModifiers;
  Result := inherited SetKeyModifiers(AShift);
  // Help draws its own F-bar from the modifiers, like an embedded document.
  if HelpVisible and FHelp.SetKeyModifiers(AShift) then
  begin
    Result := True;
    Invalidate;
  end;
  Doc := ActiveDocument;
  if Assigned(Doc) and Doc.SetKeyModifiers(AShift) then
  begin
    Result := True;
    Invalidate; // Doc.Invalidate alone does not rebuild Dual Panel chrome
  end;
  CtrlJustReleased := WasCtrl and not (ssCtrl in KeyModifiers);
  AltJustReleased := WasAlt and not (ssAlt in KeyModifiers);
  // FAR: commit Ctrl+Left/Right drive preview when Ctrl is released.
  if CtrlJustReleased then
    CommitDrivePreview;
  // Alt Quick Search lives only while Alt is held ? clear needle on release.
  if AltJustReleased and (FQuickSearchActive or (FQuickSearchText <> '')) then
  begin
    FQuickSearchActive := False;
    FQuickSearchText := '';
    Result := True;
    Invalidate;
  end;
  // Alt+Left/Right directory-history popup lives only while Alt is held.
  if AltJustReleased and Assigned(FHistoryPopupCtrl) and FHistoryPopupCtrl.Visible then
  begin
    CloseHistoryPopup;
    Result := True;
  end;
end;

function TDualPanelWindow.HandleKeymapActionPrimary(AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := DispatchKeymapActionPrimary(FKeymapHost, AAction, AKey, AKeyChar);
end;

function TDualPanelWindow.HandleKeymapActionFunctionKeys(AAction: TKeymapAction;
  var AKey: Word; var AKeyChar: Char): Boolean;
begin
  Result := DispatchKeymapActionFunctionKeys(FKeymapHost, AAction, AKey, AKeyChar);
end;

function TDualPanelWindow.HandleModalDialogInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  // Enter activates FocusedOrDefaultButtonId (not a bare 'ok'). Hotlist /
  // color-coding list keys stay in-place; color-picker hex syncs after the
  // widget sees Up/Down. Dispatch lives in uDualPanelInput.
  Result := DispatchModalDialogInput(FModalInputHost, FDialogKind, AKey, AShift,
    AKeyChar);
end;

function TDualPanelWindow.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  ViewH, Cols, PageSize: Integer;
  Doc: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
  OverlayIdx: Integer;
  Snap: TPanelFreeInputSnap;
  DialogVis: Boolean;
begin
  Result := True;
  SetKeyModifiers(AShift);
  // Any key press resets blink phase so cursor is immediately visible.
  if not FCursorVisible then
  begin
    FCursorVisible := True;
    Invalidate;
  end;
  NormalizePanelInputKey(AKey, AKeyChar);
  RestoreGrayOpKey(AKey, AKeyChar);
  // F1 Help is modal over the menu, workspaces and dialogs alike.
  if HelpVisible then
    Exit(FHelp.HandleInput(AKey, AShift, AKeyChar));
  DialogVis := Assigned(FDialog) and FDialog.Visible;

  // Context F1 first: the open top menu takes every key, and a dialog would
  // get it next. The keymap editor's key field records F1 as a key.
  if IsContextHelpChord(AKey, AShift, Assigned(FTopMenu) and FTopMenu.Active,
    DialogVis and not DialogKindTakesF1(FDialogKind)) then
  begin
    OpenHelp;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  // F9, Alt hotkeys or active TUI Top Menu (non-matching Alt keys fall through to Quick Search).
  // Same offer on Viewer/Editor tabs as on panels: row 0 click reaches the
  // menu via DispatchClickOverlays, so keyboard F9 must match. Disabled
  // whenever a modal dialog is open — this check runs first, and without
  // the guard F9 would win over dialog-specific bindings (e.g.
  // hdkColorCodingEdit's "pick a color for the focused field").
  if Assigned(FTopMenu) and ShouldOfferTopMenu(ActiveWorkspace.Kind, DialogVis) then
  begin
    if FTopMenu.HandleInput(AKey, AShift, AKeyChar) then
    begin
      Invalidate;
      Exit(True);
    end;
  end;

  // Ctrl+Tab / Ctrl+Shift+Tab ? cycle Dual Panel Tabs (panels + documents).
  // Must run before the document early-exit, or Editor/Viewer swallows Tab.
  // Disabled while a modal dialog is open ? cycling the workspace underneath
  // an open dialog (Rename, Search params, ...) would leave it operating on
  // a panel/tab it no longer matches.
  if IsWorkspaceCycleChord(AKey, AShift, DialogVis) then
  begin
    if ssShift in AShift then
      PrevWorkspace
    else
      NextWorkspace;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  // Ctrl+O is Dual Panel FAR-toggle (ShowConsoleMode), not an editor chord.
  // Must run before the document/terminal early-exit or Viewer/Editor
  // swallows it. Esc stays with the document (close tab).
  if IsConsoleToggleChord(AKey, AShift, DialogVis) then
  begin
    KeymapToggleConsole;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if IsHelpChord(AKey, AShift, DialogVis) then
  begin
    OpenHelp;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if IsNewTerminalChord(AKey, AShift, DialogVis) then
  begin
    OpenTerminalProfileDialog;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if IsSelectConsoleProfileChord(AKey, AShift, DialogVis) then
  begin
    OpenConsoleProfileDialog;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if IsAppQuitChord(AKey, AShift, DialogVis) then
  begin
    KeymapRequestQuit;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  // Embedded Viewer/Editor: document input (and its dialogs) before Dual Panel
  // host dialogs ? matches HandleClick order so Enter reaches Editor Code page.
  // Still yields to a host-level dialog if one is open (e.g. Help/About/Theme
  // opened via the top menu while a document tab is active).
  case ClassifyEmbeddedInputOwner(ActiveWorkspace.Kind, DialogVis, FConsoleMode) of
    eioDocument:
      begin
        Doc := DocumentForWorkspace(FState.ActiveWorkspaceIndex);
        if Doc <> nil then
          Result := Doc.HandleInput(AKey, AShift, AKeyChar)
        else
          Result := True;
        Exit;
      end;
    eioTerminal:
      begin
        Term := TerminalForWorkspace(FState.ActiveWorkspaceIndex);
        if Term <> nil then
          Result := Term.HandleInput(AKey, AShift, AKeyChar)
        else
          Result := True;
        Exit;
      end;
    eioConsoleYield:
      Exit(False);
  end;

  // Alt+F1/F2 drive list is included below ? before Esc>Console so Esc
  // closes the popup ? via the same FInputOverlays table as the dialog/
  // search/job/menu overlays above it (same priority order they used to
  // be checked in as a chain of ifs).
  for OverlayIdx := 0 to High(FInputOverlays) do
    if FInputOverlays[OverlayIdx].IsActive() then
      Exit(FInputOverlays[OverlayIdx].Handle(AKey, AShift, AKeyChar));

  ViewH := ListViewHeight;
  if ViewH < 1 then
    ViewH := 1;
  Cols := ListColCountForSide(ActiveWorkspace.State.ActiveSide);
  PageSize := BriefPageSize(ViewH, Cols);
  Snap := Default(TPanelFreeInputSnap);
  Snap.DrivePreviewActive := FDrivePreviewActive;
  Snap.QuickViewVisible := QuickViewVisible;
  Snap.CmdLineHasText := Assigned(FCmdLineMgr) and (FCmdLineMgr.Text <> '');
  Snap.FilterBoxActive := FFilterBoxActive;
  Snap.CmdFocused := CmdFocused;
  Snap.ViewH := ViewH;
  Snap.Cols := Cols;
  Snap.PageSize := PageSize;
  // Panel-only chords below; a focused command line takes every key
  // (DispatchPanelFreeInput).
  if ActivePanelIsTmp and not Snap.CmdFocused then
  begin
    if (ssCtrl in AShift) and not (ssAlt in AShift) and not (ssShift in AShift) and
       (AKey = vkPrior) then
    begin
      TmpGotoCursorFile;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if (ssAlt in AShift) and (ssShift in AShift) and not (ssCtrl in AShift) then
    begin
      if AKey = vkF2 then
      begin
        TmpSaveList;
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
      if AKey = vkF3 then
      begin
        TmpGotoOpposite;
        AKey := 0;
        AKeyChar := #0;
        Exit(True);
      end;
    end;
  end;
  // Ctrl+Alt+Enter: reveal the cursor item on the opposite panel. Must run
  // even after Enter on a workspace dir-link (CurrentURI is then file://),
  // otherwise DispatchPanelNavKeys treats Return as ActivateCurrent and
  // opens the file.
  if (ssCtrl in AShift) and (ssAlt in AShift) and not (ssShift in AShift)
    and (AKey = vkReturn) and not Snap.CmdFocused then
  begin
    WorkspaceGotoOpposite;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  Result := DispatchPanelFreeInput(FFreeInputHost, FKeymapHost, Snap, AKey, AShift,
    AKeyChar);
end;

function TDualPanelWindow.HandleFunctionBarClick(ALocalCol: Integer;
  AShift: TShiftState): Boolean;
var
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
begin
  Result := False;
  FunctionBarGetItems(ChromeContext, AShift, Items, Letters);
  Hit := FunctionBarHitTest(ALocalCol, Area.Width, Items, Letters, AShift,
    Assigned(Theme));
  if not FunctionBarHitToInput(Hit, AShift, Key, KeyChar, Shift) then
    Exit;
  Result := HandleInput(Key, Shift, KeyChar);
end;

function TDualPanelWindow.HandleClick(ALocalCol, ALocalRow: Integer;
  ADoubleClick: Boolean; AShift: TShiftState; AAllowOpenOnDouble: Boolean): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Side: TPanelSide;
  Rows: TPanelRows;
  Bounds, ListBounds: TRectI;
  Idx, ViewH, Cols: Integer;
  HitList: Boolean;
  ColMode: TPanelColumnMode;
begin
  Result := False;
  if HelpVisible then
    Exit(True); // Help got it in HandleMouseDown (right button lands here)
  // Open command-line history list: a click on it picks; elsewhere it
  // closes and the click goes on as usual.
  if ClickCmdHistoryPopup(ALocalCol, ALocalRow) then
    Exit(True);
  if ClickFilterHistoryPopup(ALocalCol, ALocalRow) then
    Exit(True);

  if DispatchClickOverlays(FClickHost, ClickOverlaySnapshot, ALocalCol, ALocalRow,
     AShift, ADoubleClick, Result) then
    Exit;

  Ws := ActiveWorkspace;

  if not HitPanelSide(IsPanelVisible(psLeft), FLeftBounds,
     IsPanelVisible(psRight), FRightBounds, ALocalCol, ALocalRow, Side) then
    Exit;

  if Side = psLeft then
  begin
    Bounds := FLeftBounds;
    ColMode := Ws.State.LeftPanel.ColumnMode;
  end
  else
  begin
    Bounds := FRightBounds;
    ColMode := Ws.State.RightPanel.ColumnMode;
  end;

  if DispatchPanelChromeClick(FClickHost, Side, Bounds, PanelViewKind(Side),
     ColMode, ALocalCol, ALocalRow, ADoubleClick) then
    Exit(True);

  Ws.State.ActiveSide := Side;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Side);
  ListBounds := PanelListBounds(Bounds);
  ViewH := ListBounds.Height;
  HitList := False;
  Cols := PanelListColumnCount(Panel.ColumnMode, ListBounds.Width);

  if HitPanelListIndex(ListBounds, Panel.ColumnMode, Tab.ScrollOffset,
     ALocalCol, ALocalRow, Length(Rows), Idx) then
  begin
    Tab.CursorIndex := Idx;
    EnsureCursorVisible(Tab, Length(Rows), ViewH, Cols);
    SetActiveTab(Panel, Tab);
    HitList := True;
  end;

  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);

  if UpdateListClickPair(HitList, AAllowOpenOnDouble, ADoubleClick,
     ALocalCol, ALocalRow, FLastClickCol, FLastClickRow, FLastClickTick,
     GetTickCount, GetDoubleClickTime) then
    ActivateCurrent;

  Invalidate;
  Result := True;
end;

function TDualPanelWindow.HandleEmbeddedMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  Doc: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
begin
  if ActiveWorkspace.Kind = wkTerminal then
  begin
    Term := ActiveTerminal;
    if not Assigned(Term) or (ALocalRow < 2) then
      Exit(True);
    Exit(Term.HandleMouseDown(ALocalCol, ALocalRow - 2, AShift));
  end;
  Doc := ActiveDocument;
  if not Assigned(Doc) or (ALocalRow < 2) then
    Exit(True);
  Result := Doc.HandleMouseDown(ALocalCol, ALocalRow - 2, AShift);
end;

function TDualPanelWindow.HandleMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
begin
  Result := False;
  if HelpVisible then
    Exit(FHelp.HandleMouseDown(ALocalCol, ALocalRow, AShift));
  // An open F9 submenu is drawn over the Viewer/Editor/Terminal body. If
  // mouse-down is swallowed as embedded content, HandleClick never runs and
  // the dropdown cannot be used. Same fall-through as row 0.
  if Assigned(FTopMenu) and FTopMenu.Active then
    Exit;
  // Row 0 (menu) and row 1 (workspace tabs) fall through so HandleClick sees
  // the double-click: a tab caption opens the rename dialog, empty space
  // still creates a workspace.
  case ClassifyMouseDown(ALocalRow, ActiveWorkspace.Kind) of
    mdtTopMenu, mdtWorkspaceTab:
      Exit;
    mdtEmbedded:
      Result := HandleEmbeddedMouseDown(ALocalCol, ALocalRow, AShift);
  end;
end;

procedure TDualPanelWindow.ArmFileDragFromCursor;
var
  Sources: TArray<string>;
  Paths: TArray<string>;
begin
  if TabDragBusy(FTabDragArmed, FTabDragActive) then
    Exit;
  CancelFileDrag;
  if not CanArmFileDragSources(ActiveWorkspace.Kind = wkPanels,
    Assigned(FDialog) and FDialog.Visible,
    Assigned(FJobs) and FJobs.OwnsInput) then
    Exit;
  Sources := CollectActiveSources;
  Paths := FileUrisToLocalPaths(Sources);
  if Length(Paths) = 0 then
    Exit;
  FDragUris := Sources;
  FDragArmed := True;
  FDragStartCol := FLastClickCol;
  FDragStartRow := FLastClickRow;
end;

function TDualPanelWindow.TryStartFileDrag(ALocalCol, ALocalRow: Integer;
  out APaths: TArray<string>): Boolean;
begin
  Result := False;
  SetLength(APaths, 0);
  if not ShouldStartFileDrag(TabDragBusy(FTabDragArmed, FTabDragActive),
    FDragArmed, ALocalCol, ALocalRow, FDragStartCol, FDragStartRow) then
    Exit;
  APaths := FileUrisToLocalPaths(FDragUris);
  FDragArmed := False;
  Result := Length(APaths) > 0;
end;

procedure TDualPanelWindow.CancelFileDrag;
begin
  FDragArmed := False;
  SetLength(FDragUris, 0);
  if FDropHighlightActive then
  begin
    FDropHighlightActive := False;
    NotifyChanged;
  end;
end;

function TDualPanelWindow.ResolvePanelHitContext(ALocalCol, ALocalRow: Integer;
  out ASide: TPanelSide; out ABounds: TRectI; out APanel: TPanelState): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  Result := ResolvePanelHitBounds(
    IsPanelVisible(psLeft), FLeftBounds, Ws.State.LeftPanel.ViewKind,
    IsPanelVisible(psRight), FRightBounds, Ws.State.RightPanel.ViewKind,
    ALocalCol, ALocalRow, ASide, ABounds);
  if not Result then
    Exit;
  if ASide = psLeft then
    APanel := Ws.State.LeftPanel
  else
    APanel := Ws.State.RightPanel;
end;

function TDualPanelWindow.HitTestDropTarget(ALocalCol, ALocalRow: Integer;
  out ADestURI: string; out ASide: TPanelSide; out AHighlightRow: Integer): Boolean;
var
  Bounds: TRectI;
  Panel: TPanelState;
  Tab: TTab;
begin
  Result := False;
  ADestURI := '';
  AHighlightRow := -1;
  ASide := psLeft;
  if not CanHitTestPanelDrag(ActiveWorkspace.Kind,
    Assigned(FDialog) and FDialog.Visible,
    Assigned(FJobs) and FJobs.OwnsInput) then
    Exit;
  if not ResolvePanelHitContext(ALocalCol, ALocalRow, ASide, Bounds, Panel) then
    Exit;
  Tab := ActiveTab(Panel);
  Result := ResolveDropDest(Tab.CurrentURI, Bounds, Panel.ColumnMode,
    Tab.ScrollOffset, ALocalCol, ALocalRow, RowsForSide(ASide),
    ADestURI, AHighlightRow);
end;

function TDualPanelWindow.HitTestListItemLocalPath(ALocalCol, ALocalRow: Integer;
  out ALocalPath: string): Boolean;
var
  Bounds: TRectI;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Idx: Integer;
  Side: TPanelSide;
  DialogVisible, JobsOwnInput, AnyMenuVisible, DrivePopupVisible,
    SearchActive: Boolean;
begin
  Result := False;
  ALocalPath := '';
  if HelpVisible then
    Exit;
  DialogVisible := Assigned(FDialog) and FDialog.Visible;
  JobsOwnInput := Assigned(FJobs) and FJobs.OwnsInput;
  AnyMenuVisible := Assigned(FMenus) and (FMenus.StubVisible or FMenus.UserMenuVisible or
    FMenus.SortMenuVisible or FMenus.ColumnModeMenuVisible);
  DrivePopupVisible := Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible;
  SearchActive := Assigned(FSearchUi) and (FSearchUi.Phase <> spNone);
  if not CanHitTestListItem(ActiveWorkspace.Kind, DialogVisible, JobsOwnInput,
    AnyMenuVisible, DrivePopupVisible, SearchActive) then
    Exit;
  if not ResolvePanelHitContext(ALocalCol, ALocalRow, Side, Bounds, Panel) then
    Exit;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Side);
  if not HitPanelListIndex(PanelListBounds(Bounds), Panel.ColumnMode,
    Tab.ScrollOffset, ALocalCol, ALocalRow, Length(Rows), Idx) then
    Exit;
  ALocalPath := ListItemLocalPath(Rows[Idx]);
  Result := ALocalPath <> '';
end;

procedure TDualPanelWindow.SetDropHighlight(AActive: Boolean; ASide: TPanelSide;
  const ADestURI: string; AHighlightRow: Integer);
var
  Changed: Boolean;
begin
  Changed := (FDropHighlightActive <> AActive) or
    (AActive and ((FDropHighlightSide <> ASide) or
      (FDropHighlightURI <> ADestURI) or (FDropHighlightRow <> AHighlightRow)));
  FDropHighlightActive := AActive;
  FDropHighlightSide := ASide;
  FDropHighlightURI := ADestURI;
  FDropHighlightRow := AHighlightRow;
  if Changed then
    NotifyChanged;
end;

procedure TDualPanelWindow.AcceptDroppedFiles(const APaths: TArray<string>;
  const ADestDirURI: string; AMove: Boolean);
var
  Uris: TArray<string>;
  Kind: TPanelJobKind;
begin
  Uris := LocalPathsToFileUris(APaths);
  if Length(Uris) = 0 then
    Exit;
  if AMove then
    Kind := pjkMove
  else
    Kind := pjkCopy;
  BeginTransferJob(Uris, ADestDirURI, Kind);
end;

procedure TDualPanelWindow.FinishOleFileDrag(AEffect: LongInt);
begin
  CancelFileDrag;
  SetDropHighlight(False);
  // Shell consumed files (move to Explorer / another app).
  if (AEffect and DROPEFFECT_MOVE) <> 0 then
    ReloadActiveRows;
  NotifyChanged;
end;

function TDualPanelWindow.HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Doc: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
begin
  if HelpVisible then
    Exit(FHelp.HandleMouseMove(ALocalCol, ALocalRow));
  if TabDragBusy(FTabDragArmed, FTabDragActive) then
    Exit(UpdateTabDrag(ALocalCol, ALocalRow));
  Result := False;
  if ActiveWorkspace.Kind = wkTerminal then
  begin
    Term := ActiveTerminal;
    if not Assigned(Term) or (ALocalRow < 2) then
      Exit;
    Exit(Term.HandleMouseMove(ALocalCol, ALocalRow - 2));
  end;
  if ActiveWorkspace.Kind <> wkDocument then
    Exit;
  Doc := ActiveDocument;
  if not Assigned(Doc) or (ALocalRow < 2) then
    Exit;
  Result := Doc.HandleMouseMove(ALocalCol, ALocalRow - 2);
end;

function TDualPanelWindow.HandleMouseUp: Boolean;
var
  Doc: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
begin
  Result := False;
  if HelpVisible then
    Exit(FHelp.HandleMouseUp);
  if TabDragBusy(FTabDragArmed, FTabDragActive) then
  begin
    CommitTabDrag;
    Result := True;
  end;
  if FDragArmed then
  begin
    CancelFileDrag;
    Result := True;
  end;
  if ActiveWorkspace.Kind = wkTerminal then
  begin
    Term := ActiveTerminal;
    if not Assigned(Term) then
      Exit;
    Exit(Term.HandleMouseUp or Result);
  end;
  if ActiveWorkspace.Kind <> wkDocument then
    Exit;
  Doc := ActiveDocument;
  if not Assigned(Doc) then
    Exit;
  Result := Doc.HandleMouseUp or Result;
end;

end.
