unit uDualPanelWindow;

{ Dual Panel Host: menu + clock, Dual Panel Tabs, two panel frames
  (double-line = active), Panel Tabs, scrollbars, command line, F-bar, status.
  Default colours via Theme = classic FAR palette. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.DateUtils,
  System.IOUtils, System.Generics.Collections, System.JSON,
  uTerminalTypes, uThemeTypes, uThemeSpec, uColorCoding, uMarkdownColors, uThemeDrawing, uTerminalWindow, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelCmd, uVfsTypes, uVfsRegistry, uDriveInfo, uAssociations, uUserAssociations,
  uKeymap, uFileFind, uFindSession, uEditorWindow, uHelpViewer, uHelpContext, uQuickTextView,
  uHistoryPopup,
  uInputLine, uFunctionBar, uPanelModel, uPanelColumns, uDirWatch, uDialogTypes, uDialogJson,
  uDialogHost, uShellAssoc, uShellIcons, uDualPanelOverlays,
  uDualPanelDrivePopup, uDualPanelFolderTree, uDualPanelHistoryPopup, uDualPanelJobs, uDualPanelJobList,
  uDualPanelJobRules, uDualPanelJobChips, uWindowChrome, uDescriptIon, uDualPanelSearch, uDualPanelMenus,
  uFolderSize, uDualPanelFolderSize, uDualPanelSelection, uDualPanelCmdLine,
  uDualPanelDrawUtils, uDualPanelInfoPanel, uDualPanelPanelDraw, uDualPanelOperations, uTopMenuBar, uMenuRegistry, uCommandRegistry, uDocumentProviders, uPanelPluginRegistry, uPluginHost, uPluginInfo, uPluginServices, uPluginSurface,
  uFolderHistory, uANSIParser,
  uLinkUtils, uWinFileAttr, uFileCompare, uRecycleBinVfs, uWorkspaceVfs,
  uDualPanelSync, uDualPanelTabs, uShellProfiles, uTerminalWorkspace, uOverlayRenderer,
  uColorCodingEditHelpers, uDualPanelColorCoding, uDualPanelKeymapDialog, uDualPanelFolderHotlist,
  uDualPanelWorkspaceLibrary, uWorkspaceLibrary,
  uDualPanelSshConnections, uSshConnections, uDualPanelUserAssociations,
  uUserMenu, uUserMenuController, uDualPanelUserMenu,
  uDualPanelHistoryDialogs, uDualPanelSettingsDialogs, uDualPanelThemeDialogs, uDualPanelFileDialogs,
  uDualPanelJobDialogs, uDualPanelFindDialogs, uDualPanelStatus, uElevatedVfs, uElevation,
  uDualPanelInput, uDualPanelTopMenu, uDualPanelClick, uDualPanelDrag, uPanelUriLabels,
  uMessageBus, uDisplaySettings, uConPty, uNotice, uToast, uHiddenDialogs;

type
  THandleInputMethod = function(var AKey: Word; AShift: TShiftState;
    var AKeyChar: Char): Boolean of object;

  /// <summary>One row of TDualPanelWindow.FInputOverlays: IsActive is
  /// re-evaluated on every keypress (no persisted push/pop state - see the
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
    /// <summary>The masks behind the entries of the open filter dialog's list.</summary>
    FFilterPresets: TArray<string>;
    /// <summary>The panel filter in force (Ctrl+I): hides non-matching rows via
    /// IPanelModel.SetFilterMask; '' when there is none.</summary>
    FFilterMask: string;
    /// <summary>Descript.ion of the active folder, for the status line: the folder,
    /// its file's timestamp and when it was last looked at.</summary>
    FDescDir: string;
    FDescStamp: TDateTime;
    FDescCheckedAt: UInt64;
    FDescMap: TDictionary<string, string>;
    /// <summary>The folder and file names of the open Describe dialog.</summary>
    FDescribeDir: string;
    FDescribeNames: TArray<string>;
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
    /// <summary>File operations through the administrator helper: the job
    /// error prompts, new folder and rename offer them after "access denied".</summary>
    FElevatedVfs: TElevatedFileVfs;
    FElevatedIntf: IVirtualFileSystem;
    FHelperActive: Boolean;
    FOnHelperActiveChanged: TNotifyEvent;
    FAlive: Boolean;
    // Plugin picture shown in the Quick View panel (0 = none).
    FSurfacePanelHandle: Integer;
    FSurfacePanelGen: Cardinal;
    // Folder and cursor row last reported to the plugins (panel.dir / panel.cursor).
    FPanelEventUri, FPanelEventCursor: array[TPanelSide] of string;
    FHostWindowId: Int64;
    FOnContentChanged: TNotifyEvent;
    FOnOpenViewer: TOpenViewerEvent;
    FOnOpenEditor: TOpenEditorEvent;
    FOnShowProperties: TShowPropertiesEvent;
    FOnShellContextMenu: TShellContextMenuEvent;
    FOnLaunchConsoleFile: TLaunchConsoleFileEvent;
    FOnQuitRequest: TQuitRequestEvent;
    FOnOpenUpdates: TQuitRequestEvent;
    /// <summary>Row of the Plugins list to come back to when the settings dialog of
    /// that plugin is closed; -1 = none.</summary>
    FPluginListReturnRow: Integer;
    /// <summary>The plugin information dialog: the list row it came from and the help
    /// page of that plugin ('' when it has none).</summary>
    FPluginInfoRow: Integer;
    FPluginInfoHelp: string;
    FPluginPermsRow: Integer;
    FPluginPermsCount: Integer;
    FPluginPermsHasOverride: Boolean;
    /// <summary>hdkHost: where ShowHostDialog's command (control id, values
    /// JSON) goes once the dialog has closed.</summary>
    FHostDialogCommand: TProc<string, string>;
    FDrivePopupCtrl: TDrivePopupController;
    FFolderTreeCtrl: TFolderTreeController;
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
    FStopAccept: TProc;
    FStopReject: TProc;
    FSyncingJobProgress: Boolean;
    FSearchUi: TSearchController;
    FMenus: TMenuStubController;
    FPendingSelectName: string;
    /// <summary>Temp folders holding archive entries opened with the shell;
    /// removed when the window goes away.</summary>
    FOpenTempDirs: TStringList;
    FPendingSelectSide: TPanelSide;
    /// <summary>Helper for Gray+/Gray? select dialogs (FAR).</summary>
    FSelHelper: TDualPanelSelectionHelper;
    FOnRunCommand: TRunCommandEvent;
    FOnReturnWhenDone: TNotifyEvent;
    FOnRunInBackground: TNotifyEvent;
    FOnShellCwdSync: TShellCwdSyncEvent;
    FOnSaveConsoleOutput: TSaveConsoleOutputEvent;
    FOnClearConsoleBuffer: TNotifyEvent;
    FOnExportSettings: TSettingsFileEvent;
    FOnImportSettings: TSettingsFileEvent;
    FOnToggleConsole: TQuitRequestEvent;
    FOnOpenTerminal: TOpenTerminalEvent;
    FOnQueryConsoleKeyCapture: TFunc<Boolean>;
    FOnSetConsoleProfile: TSetConsoleProfileEvent;
    FOnGetConsoleProfile: TGetConsoleProfileEvent;
    FOnGetConsoleStartOnLaunch: TGetConsoleStartOnLaunchEvent;
    FOnSetConsoleStartOnLaunch: TSetConsoleStartOnLaunchEvent;
    FOnGetConsoleCwdToPanels: TGetConsoleStartOnLaunchEvent;
    FOnSetConsoleCwdToPanels: TSetConsoleStartOnLaunchEvent;
    FOnThemeSelect: TThemeSelectEvent;
    FOnThemePreview: TThemePreviewEvent;
    FOnGetActiveThemeId: TGetThemeIdEvent;
    FOnApplyDisplaySettings: TDisplaySettingsEvent;
    FOnGetDisplaySettings: TGetDisplaySettingsEvent;
    FConsoleMode: Boolean;
    FWindowMaximized: Boolean;
    FWindowTitleParts: TWindowTitleParts;
    /// <summary>0 none, 1..3 a window button, 4 the [+] button.</summary>
    FChromeHover: Integer;
    /// <summary>Window button (1..3) the mouse went down on; it acts on release.</summary>
    FChromePressed: Integer;
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
    /// <summary>Transient bottom-right notice (clipboard copies etc.).</summary>
    FToast: TToast;
    /// <summary>Workspace tab id while hdkWorkspaceTabRename is open.</summary>
    FRenameWorkspaceId: Cardinal;
    FSkipArchivePasswordUri: string;
    FArchivePasswordUri: string;
    FArchivePasswordSide: TPanelSide;
    FArchivePasswordRetry: Boolean;
    /// <summary>Archives (lower-case paths) whose password was checked in
    /// this session: F3 / F5 on their encrypted files asks no more.</summary>
    FArchivesUnlocked: TDictionary<string, Boolean>;
    /// <summary>What F3 / F4 / F5 / Enter do once the password of the
    /// archive they read from is checked; nil when the password dialog asks
    /// for a listing instead.</summary>
    FArchiveAction: TProc;
    FArchiveActionPath: string;
    FArchiveProbeUri: string;
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
    FThemeDlg: TThemeDialogController;
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
    /// consulted by HandleInput - see TInputOverlayEntry. Recomputed from
    /// live state on every keypress rather than push/pop: FDialog routinely
    /// opens on top of an already-active FJobs (e.g. hdkJobConfirm), and a
    /// persisted stack would need a Pop at every one of FDialog.Open's many
    /// call sites to avoid leaving a stale entry that swallows all future
    /// input - this table can't desync because it has no state to desync.
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
    procedure RequestStopConfirm(const AQuestion: string; const AOnAccept, AOnReject: TProc);
    procedure AnswerStopConfirm(AAccepted: Boolean);
    procedure RequestJobListCancel(AIndex: Integer; AAll: Boolean);
    procedure HostRequestJobStop;
    procedure HostRequestSearchStop;
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
    procedure HostPreviewTheme(const ASpec: TThemeSpec);
    function HostGetDisplaySettings: TDisplaySettings;
    procedure HostApplyDisplaySettings(const ASettings: TDisplaySettings);
    procedure HostOpenTerminal(const AProfileId, ACwd: string);
    procedure HostSetConsoleProfile(const AProfileId: string);
    function HostGetConsoleProfile: string;
    function HostGetConsoleStartOnLaunch: Boolean;
    procedure HostSetConsoleStartOnLaunch(AValue: Boolean);
    function HostGetConsoleCwdToPanels: Boolean;
    procedure HostSetConsoleCwdToPanels(AValue: Boolean);
    function HostActivePanelUri: string;
    function HostInPanelsWorkspace: Boolean;
    function HostLastSelectMask: string;
    function HostSelectFolders: Boolean;
    function GetSelectFolders: Boolean;
    procedure SetSelectFolders(AValue: Boolean);
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
    /// <summary>Folder tree navigation: moves ASide without taking the focus
    /// from the side that has it.</summary>
    procedure HostTreeNavigate(ASide: TPanelSide; const AURI: string);
    procedure DrawHostFilesHeaders(const ABounds: TRectI; const APanel: TPanelState);
    procedure DrawHostFilesList(const AListBounds: TRectI; const ATab: TTab;
      AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide);
    procedure DrawHostFilesScroll(AX, ATop, ABottom, APos, ACount, AViewH: Integer);
    procedure PreviewCycleActiveDrive(ADelta: Integer);
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
    /// - used by Create to seed the two initial workspaces.</summary>
    function MakePanelState(const AUris: array of string): TPanelState;
    procedure ModelInvalidated(AWindowId: Integer);
    procedure MaybeAskArchivePassword(ASide: TPanelSide);
    procedure HandlePluginNavigate(const ATopic: string; const APayload: TObject);
    procedure HandlePluginReload(const ATopic: string; const APayload: TObject);
    procedure ReloadSidesShowing(const AUri: string);
    procedure HandleArchivePasswordCommand(const AControlId, APassword: string);
    /// <summary>The smallest encrypted file among AURIs in the 7z archive the
    /// active panel shows, when that archive has no checked password yet.
    /// With AIncludeZip an encrypted entry of a local ZIP counts too; it is
    /// probed through the 7z backend, since the built-in ZIP layer cannot
    /// decrypt.</summary>
    function FindLockedArchiveFile(const AURIs: TArray<string>;
      out AArchivePath, AProbeUri: string; AIncludeZip: Boolean = False): Boolean;
    /// <summary>The URI to read ARow from: the 7z:// twin of an encrypted ZIP
    /// entry (when 7z.dll is there), otherwise the row's own URI.</summary>
    function ReadableRowUri(const ARow: TPanelRow): string;
    /// <summary>Runs AAction at once, or - when AURIs include an encrypted
    /// file of a 7z archive with no checked password - after the password is
    /// entered and checked on the smallest such file. Esc drops AAction.</summary>
    procedure RunWithArchivePassword(const AURIs: TArray<string>; const AAction: TProc;
      AIncludeZip: Boolean = False);
    procedure OpenArchiveActionPrompt(AWrong: Boolean);
    procedure CheckArchiveActionPassword;
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
    procedure GoHistoryBack(AShowPopup: Boolean);
    procedure HistoryForward;
    procedure ActivateCurrent;
    /// <summary>Enter on ARow of ATab's listing: open, enter, run, go back.</summary>
    procedure ActivateRow(const ATab: TTab; const ARow: TPanelRow);
    /// <summary>Up one level: activates the ".." row of the active panel.</summary>
    procedure GoToParent;
    procedure RefreshActive;
    function HandleQuickSearchInput(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    procedure ClearQuickSearch;
    procedure DrawQuickSearchField(const ABounds: TRectI);
    procedure OpenPanelFilter;
    function HandlePanelFilterCommand(const AControlId: string): Boolean;
    procedure ApplyPanelFilter(const AMask: string);
    procedure ClearPanelFilter;
    procedure RestoreSelection;
    procedure DescribeItems;
    function HandleDescribeCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    function DescriptionOf(const ADirUri, AName: string): string;
    procedure ToggleInsertSelect;
    /// <summary>Shift+Up/Down/Left/Right/Home/End/Pg*: invert mark on rows, then
    /// move. Unit steps: leaving row only. AExcludeLanding (Brief Left/Right):
    /// invert [From..To) - includes the row before landing, not the landing.</summary>
    procedure MoveCursorWithSelect(ADelta: Integer;
      AExcludeLanding: Boolean = False);
    /// <summary>Selected items (or the cursor item) to the clipboard, one per
    /// line: full paths, or bare names when ANameOnly. '..' stands for the
    /// current folder.</summary>
    procedure CopyItemsToClipboard(ANameOnly: Boolean);
    procedure CopyFullPathToClipboard;
    procedure CopyItemNameToClipboard;
    procedure SelectAllActive;
    procedure UnselectAllActive;
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
    /// <summary>Toast when a mask (de)selection left the selection as it
    /// was -- the only case where nothing on screen answers the key.</summary>
    procedure NoteSelectionUnchanged(ABefore: Integer; const ATab: TTab;
      const AMask: string);
    procedure SubmitCommandLine;
    procedure RunConsoleCommand(const ACommand: string);
    /// <summary>Clears the command line and hands ACommand to the console;
    /// False when there is nothing to run.</summary>
    function SendConsoleCommand(const ACommand: string): Boolean;
    /// <summary>FAR Shift+Enter: cmdline or cursor file as a separate OS process.</summary>
    procedure RunDetachedFromCmdLine(const AText, ACwd: string);
    procedure RunDetachedOpenFolder(const AUri: string; const ATab: TTab;
      AIsParent: Boolean);
    procedure RunDetachedFile(const AUri: string);
    procedure RunDetached;
    /// <summary>The command line runs in the console, which shows it for a
    /// moment (OnRunInBackground, Options > Console...) and gives the panels back.</summary>
    procedure RunInBackground;
    /// <summary>The command line runs in a new terminal tab, in the shell of the
    /// background console.</summary>
    procedure RunInNewTab;
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
    /// <summary>The tree is open over a panel of this workspace, focused or not.</summary>
    function FolderTreeShown: Boolean;
    /// <summary>The tree is open and its side is the active one.</summary>
    function OverlayFolderTreeVisible: Boolean;
    function HandleFolderTreeInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleFolderTreeClick(ALocalCol, ALocalRow: Integer): Boolean;
    procedure DrawFolderTree;
    /// <summary>Alt+F10: the folder tree of the active panel's drive, or
    /// closes it.</summary>
    procedure ToggleFolderTree;
    procedure CloseFolderTree;
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
    procedure BeginDeleteCursor;
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
    procedure HostRunUserMenuCommand(const ACommand: string; AReturnToPanels: Boolean);
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
    /// command line - the shared "make way for a dialog" step run before
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
    /// <summary>Shift+F10 / Menu: the Windows context menu for the selection
    /// (else the cursor item, or the folder itself on ".."), at the cursor
    /// row; local files and folders only.</summary>
    procedure ShowShellContextMenu;
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
    /// <summary>DialogCommand's `case FDialogKind of` - one branch per
    /// THostDialogKind. Returns False from the (rare) branches that must
    /// skip DialogCommand's trailing NotifyChanged/FlushDirWatchPending
    /// (matches those branches' original bare `Exit;`).</summary>
    function DispatchDialogCommand(AKind: THostDialogKind;
      const AControlId, AValuesJson: string;
      const AFields: TDialogCommandFields): Boolean;
    procedure RequestFreeSpace(const APath: string);
    procedure ResolveRelativeCommandAsync(const AText, ABaseDir, ACommand: string);
    /// <summary>A path typed into the command line: an existing file runs
    /// (ShellOpenPath), anything else is navigated to.</summary>
    procedure OpenOrNavigateAsync(const AURI: string);
    procedure ExecuteTopMenuAction(AAction: TTopMenuAction);
    procedure OpenAboutDialog;
    /// <summary>Help > Updates: forwarded to OnOpenUpdates (the updater lives
    /// in the form, not in the panel window).</summary>
    procedure OpenUpdates;
    /// <summary>Options > Restore hidden dialogs.</summary>
    procedure RestoreHiddenDialogsNow;
    procedure HelperActiveChanged(AActive: Boolean);
    procedure RunMkDir(const AVfs: IVirtualFileSystem; const AURI, ASelectName: string;
      AMayElevate: Boolean);
    procedure RunRename(const AVfs: IVirtualFileSystem; const AFromURI, AToURI,
      ANewName: string; AMayElevate: Boolean);
    function CanElevateLocal(const AURI: string): Boolean;
    /// <summary>Asks whether to repeat a failed operation with administrator
    /// rights; AAction runs after a yes (the UAC prompt follows).</summary>
    procedure OfferElevated(const AAction: TProc);
    procedure OpenPluginListDialog;
    procedure ShowPluginList(ASelectedIndex: Integer);
    procedure ShowPluginInfo(ARow: Integer);
    procedure ShowPluginPermissions(ARow: Integer);
    function HandlePluginPermsCommand(const AControlId: string): Boolean;
    function HandlePluginInfoCommand(const AControlId: string): Boolean;
    function HandlePluginListCommand(const AControlId: string): Boolean;
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
    procedure OpenConsoleOptionsDialog;
    procedure BeginSaveConsoleOutput;
    procedure ClearConsoleBuffer;
    procedure BeginExportSettings;
    procedure BeginImportSettings;
    /// <summary>mtn2-settings.zip in the folder of the active panel (the
    /// documents folder when that is not a plain folder).</summary>
    function SettingsFileDefaultPath: string;
    function HandleSettingsFileCommand(AKind: THostDialogKind;
      const AControlId: string; const AFields: TDialogCommandFields): Boolean;
    function HandleConsoleSaveCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    procedure OpenMarkdownColorsDialog;
    procedure BeginChecksums;
    procedure StartChecksumJob(AAlgoIndex: Integer; AVerify: Boolean);
    procedure ShowChecksumResult(const ATitle, AStatus: string;
      const ALines: TArray<string>; AVerify: Boolean);
    procedure DispatchChecksumCommand(AKind: THostDialogKind; const AControlId: string);
    /// <summary>Ctrl+Q: NC/NDN/FAR/TC convention - puts the opposite panel
    /// into pvkQuickView for any cursor row (file or directory), same toggle
    /// shape as ToggleAdjacentInfoPanel/pvkInfo. Image overlay vs placeholder
    /// is decided later in DrawQuickViewContent as the cursor moves.</summary>
    procedure ToggleQuickView;
    /// <summary>Ctrl+PgDn (FAR): enters the folder under the cursor, like
    /// Enter; a local file it enters as an archive whatever its extension -
    /// a ZIP signature (docx, xlsx, odt) in the built-in ZIP, anything else
    /// through the 7z plugin, which finds the format by content.</summary>
    procedure FolderDown;
    procedure CloseQuickView;
    procedure CancelFolderSize;
    procedure CalculateFolderSizeUnderCursor;
    function FolderSizeStubTitle: string;
    procedure InsertPanelItemToCmdLine(AFullPath: Boolean);
    /// <summary>A local file by the Windows shell, or as a console program
    /// (OnLaunchConsoleFile) when it is one.</summary>
    procedure ShellOpenPath(const APath: string);
    procedure ShellOpenArchiveEntry(const AURI, AName: string);
    procedure ShellOpenSevenZipEntry(const ASevenUri, ADst: string; ARetried: Boolean);
    procedure RunUserCommandCurrent(const AURI, ACommandTemplate: string);
    procedure SetCmdFocused(AValue: Boolean);
    function ClickCmdLine(ACol, ARow: Integer; AShift: TShiftState): Boolean;
    /// <summary>Ctrl+Down / Alt+Down in the command line: its history as a
    /// drop-down above the line.</summary>
    procedure OpenCmdHistoryPopup;
    /// <summary>A click while the command-line history list is open: True
    /// when it landed on the list.</summary>
    function ClickCmdHistoryPopup(ACol, ARow: Integer): Boolean;
    procedure SetPanelFilterMask(const AText: string);
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
    /// <summary>Ctrl+Shift+T for an explicitly named side - used by the
    /// double-click-on-empty-panel-tab-row path, where the panel that was
    /// clicked is not necessarily the active one yet.</summary>
    procedure NewPanelTabOnSide(ASide: TPanelSide);
    procedure SelectPanelTab(ASide: TPanelSide; AIndex: Integer);
    procedure ClosePanelTab(ASide: TPanelSide; AIndex: Integer);
    function SelectPanelTabAtCol(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer): Boolean;
    function HitWorkspaceTabAtCol(ACol: Integer; out AIndex: Integer;
      out AIsClose: Boolean): Boolean;
    function HitPanelPlusAtCol(ASide: TPanelSide; const ABounds: TRectI;
      ACol: Integer): Boolean;
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
    function ButtonsInTabRow: Boolean;
    function ChromeDrawn: Boolean;
    function TabBarChrome(AWidth: Integer): TTabBarChrome;
    procedure DrawTabBarChrome(AWidth: Integer);
    function ConsoleBarShown: Boolean;
    procedure DrawWindowButtons(const AGrid: TTerminalGrid; AWidth: Integer;
      AOnMenuBar: Boolean);
    function ChromeHoverAt(ALocalCol, ALocalRow: Integer): Integer;
    function ClickJobStrip(ACol: Integer): Boolean;
    function ClickChrome(ALocalCol, ALocalRow: Integer): Boolean;
    function SelectWorkspaceAtCol(ACol: Integer): Boolean;
    function BeginRenameWorkspaceAtCol(ACol: Integer): Boolean;
    procedure ApplyWorkspaceTabTitle(const AName: string);
    procedure DrawPanel(const ABounds: TRectI; const APanel: TPanelState;
      ASide: TPanelSide; AActive: Boolean);
    procedure DrawPanelFiles(const ABounds: TRectI; const APanel: TPanelState;
      ASide: TPanelSide; AActive: Boolean; AFrame, ABodyBg: TAlphaColor);
    procedure DrawPanelInfoContent(const ABounds: TRectI; ASide: TPanelSide;
      AFrame, ABodyBg: TAlphaColor);
    /// <summary>Live preview of the active side's cursor row
    /// (NC/NDN/FAR/TC Ctrl+Q - opposite panel, follows the cursor without
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
    /// <summary>The F-key bar and the status line, those that are shown.</summary>
    procedure DrawBottomChrome(W, H: Integer);
  protected
    procedure DrawDocumentContent(W, H: Integer);
    procedure DrawTerminalContent(W, H: Integer);
    procedure DrawPanelsContent(W, H: Integer);
    procedure DrawContent; override;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal);
    destructor Destroy; override;
    /// <summary>Opens ADecl for a caller outside the panel window. False (and
    /// nothing opens) while another dialog is up. AOnCommand runs after the
    /// dialog has closed, so it may open the next one.</summary>
    /// <summary>Shows an informational message box.</summary>
    procedure ShowInfo(const ATitle, ADetail: string);
    /// <summary>Opens a viewer tab for plugin picture AHandle (uPluginSurface).</summary>
    function OpenSurfaceTab(AHandle: Integer): Boolean;
    /// <summary>The cells a visible plugin surface covers (compositor-absolute, inclusive):
    /// False for one that is not on screen or is covered by a dialog or the menu.</summary>
    function SurfaceViewport(AHandle: Integer; out ABounds: TRectI): Boolean;
    /// <summary>The surface whose area is under the mouse, if the plugin wants the mouse.</summary>
    function VisibleSurfaces: TArray<Integer>;
    /// <summary>Closes the Quick View surface when Quick View has been switched off.</summary>
    procedure SyncSurfacePanel;
    /// <summary>The plugin API (uPluginServices): the text document on screen and
    /// the file panels. The document calls fail while no text document is the
    /// active tab.</summary>
    function PluginDocInfoJson: string;
    function PluginDocGetText(AWhat: Integer; out AText: string): Boolean;
    function PluginDocReplace(AWhat: Integer; const AText: string): Boolean;
    function PluginDocSetCursor(ARow, ACol: Integer): Boolean;
    function PluginPanelInfoJson: string;
    function PluginPanelGoto(ASide: Integer; const AURI: string): Boolean;
    procedure PluginPanelRefresh;
    procedure PublishPanelEvents;
    procedure DrawSurfacePanel(const ABounds: TRectI; ABodyBg: TAlphaColor);
    function PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2: Integer): Boolean;
    function PluginDocLine(AIndex: Integer; out AText: string): Boolean;
    function PluginPanelListJson(ASide: Integer): string;
    function PluginPanelSetCursor(ASide: Integer; const AURI: string): Boolean;
    function PluginPanelSelect(ASide, AMode: Integer; const AArg: string): Boolean;
    function ShowHostDialog(const ADecl: TDialogDeclaration;
      const AOnCommand: TProc<string, string>): Boolean;
    /// <summary>A copy/move/delete job is running or waiting on the user.</summary>
    function HasBusyJob: Boolean;
    procedure RebuildBuffer; override;
    function SetKeyModifiers(AShift: TShiftState): Boolean; override;
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean; override;
    /// <summary>Free (non-modal) keymap bindings shared by most of the app -
    /// see HandleInput's first `case MatchActiveAction(...)` block. Returns
    /// True (and has already reset AKey/AKeyChar) if AAction was handled;
    /// False if the caller should keep looking.</summary>
    function HandleKeymapActionPrimary(AAction: TKeymapAction;
      var AKey: Word; var AKeyChar: Char): Boolean;
    /// <summary>Function-key/panel-operation keymap bindings - see
    /// HandleInput's second `case MatchActiveAction(...)` block. Same
    /// True/False contract as HandleKeymapActionPrimary.</summary>
    function HandleKeymapActionFunctionKeys(AAction: TKeymapAction;
      var AKey: Word; var AKeyChar: Char): Boolean;
    /// <summary>HandleInput's modal-dialog-open branch - in-place list
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
    /// <summary>Whether the window is maximized: picks the maximize button's glyph.</summary>
    property WindowMaximized: Boolean read FWindowMaximized write FWindowMaximized;
    /// <summary>Shown in the free part of the tab bar while the native title bar is hidden.</summary>
    property WindowTitleParts: TWindowTitleParts read FWindowTitleParts
      write FWindowTitleParts;
    /// <summary>True where dragging moves the window: the free part of the
    /// menu bar and tab bar rows while the native title bar is hidden.</summary>
    /// <summary>Ctrl+Tab / Ctrl+Shift+Tab, which the main form intercepts before
    /// FMX moves the focus.</summary>
    procedure CycleTab(AReverse: Boolean);
    function IsWindowDragZone(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>Tracks the button under the mouse (-1, -1 when it left the
    /// window); True when the highlight changed and the screen needs a repaint.</summary>
    function UpdateChromeHover(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>Right click on the free part of the tab or menu row while the
    /// native title bar is hidden: opens or closes the top menu like F9.
    /// False when the click is not for the menu (the system menu may follow).</summary>
    function ToggleTopMenuFromTitle: Boolean;
    /// <summary>Left mouse button released (-1, -1 when outside the window).
    /// True when a window button was pressed and the release is consumed;
    /// AActs says the mouse is still over that button, so its command is to be
    /// run (after the button has been drawn released).</summary>
    function ReleaseChromeButton(ALocalCol, ALocalRow: Integer;
      out AButton: TWindowButton; out AActs: Boolean): Boolean;
    /// <summary>With the native title bar hidden, paints the window buttons over
    /// the top border of the console frame into AGrid (the composed scene, after
    /// the console has been painted).</summary>
    procedure PaintConsoleWindowButtons(const AGrid: TTerminalGrid; AWidth: Integer);
    /// <summary>A click on those buttons; True when it hit one and acted.</summary>
    function HandleConsoleFrameClick(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>The key a click on the function bar stands for (Esc for
    /// "Esc:Panels"), False when the click is not on a bar item. Lets the main
    /// form send it down the keyboard path while the console covers the panels.</summary>
    function FunctionBarClickKey(ALocalCol, ALocalRow: Integer; AShift: TShiftState;
      out AKey: Word; out AKeyChar: Char; out AKeyShift: TShiftState): Boolean;
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
    /// <summary>The F9 menu is open.</summary>
    function TopMenuOpen: Boolean;
    /// <summary>A dialog is on screen over the panels.</summary>
    function HasOpenDialog: Boolean;
    /// <summary>The left button went up (cell in this window's coordinates, -1 when
    /// outside): a press that began on a menu title and ends over an item runs it.</summary>
    function HandleMenuMouseUp(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>Map cell > local filesystem path for a list row (file:// only).</summary>
    function HitTestListItemLocalPath(ALocalCol, ALocalRow: Integer;
      out ALocalPath: string): Boolean;
    procedure SetDropHighlight(AActive: Boolean; ASide: TPanelSide = psLeft;
      const ADestURI: string = ''; AHighlightRow: Integer = -1);
    /// <summary>Accept dropped local paths into DestURI (Copy or Move).</summary>
    procedure AcceptDroppedFiles(const APaths: TArray<string>; const ADestDirURI: string;
      AMove: Boolean);
    /// <summary>After OleDragLocalFiles returns - reload if shell moved files out.</summary>
    procedure FinishOleFileDrag(AEffect: LongInt);
    /// <summary>Opens AURI in the viewer (AViewOnly) or the editor. A plugin
    /// provider registered for the file type (uDocumentProviders) is asked
    /// first: it may open the file itself or name another URI for the built-in
    /// window.</summary>
    procedure OpenDocument(const AURI: string; AViewOnly: Boolean);
    /// <summary>The built-in viewer / editor tab for AURI, without asking the
    /// document providers.</summary>
    procedure OpenBuiltInDocument(const AURI: string; AViewOnly: Boolean);
    /// <summary>New terminal tab with AProfileId's shell in ACwd; ACommand,
    /// when given, is typed into that shell.</summary>
    procedure OpenTerminal(const AProfileId, ACwd: string; const ACommand: string = '');
    /// <summary>Opens APath (file or directory) in a new tab on
    /// the active side - the single entry point single-instance IPC and the
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
    property OnShellContextMenu: TShellContextMenuEvent read FOnShellContextMenu
      write FOnShellContextMenu;
    property OnLaunchConsoleFile: TLaunchConsoleFileEvent read FOnLaunchConsoleFile
      write FOnLaunchConsoleFile;
    property OnQuitRequest: TQuitRequestEvent read FOnQuitRequest write FOnQuitRequest;
    property OnOpenUpdates: TQuitRequestEvent read FOnOpenUpdates write FOnOpenUpdates;
    property OnRunCommand: TRunCommandEvent read FOnRunCommand write FOnRunCommand;
    /// <summary>Asks the host to go back to the panels once the command it
    /// was just given has finished.</summary>
    property OnReturnWhenDone: TNotifyEvent read FOnReturnWhenDone write FOnReturnWhenDone;
    property OnRunInBackground: TNotifyEvent read FOnRunInBackground write FOnRunInBackground;
    property OnShellCwdSync: TShellCwdSyncEvent read FOnShellCwdSync write FOnShellCwdSync;
    /// <summary>Commands > Save console output: the form writes the console's scrollback.</summary>
    property OnSaveConsoleOutput: TSaveConsoleOutputEvent
      read FOnSaveConsoleOutput write FOnSaveConsoleOutput;
    /// <summary>Commands > Clear console buffer.</summary>
    property OnClearConsoleBuffer: TNotifyEvent
      read FOnClearConsoleBuffer write FOnClearConsoleBuffer;
    /// <summary>Options > Export / Import settings: the form saves its session
    /// first (export) and keeps it from overwriting an import at exit.</summary>
    /// <summary>True while the administrator helper runs; the title shows it.</summary>
    property HelperActive: Boolean read FHelperActive;
    property OnHelperActiveChanged: TNotifyEvent
      read FOnHelperActiveChanged write FOnHelperActiveChanged;
    property OnExportSettings: TSettingsFileEvent
      read FOnExportSettings write FOnExportSettings;
    property OnImportSettings: TSettingsFileEvent
      read FOnImportSettings write FOnImportSettings;
    property OnToggleConsole: TQuitRequestEvent read FOnToggleConsole write FOnToggleConsole;
    property OnOpenTerminal: TOpenTerminalEvent read FOnOpenTerminal write FOnOpenTerminal;
    /// <summary>True while the Ctrl+O console hands the keys to its program
    /// (see TBaseConsoleWindow.KeysToProgram).</summary>
    property OnQueryConsoleKeyCapture: TFunc<Boolean>
      read FOnQueryConsoleKeyCapture write FOnQueryConsoleKeyCapture;
    /// <summary>The active terminal tab or the console hands the keys the
    /// host also binds (F1, F9, Alt+letter, ...) to its program; the keys that
    /// leave the console (IsKeyboardCaptureExitAction) are not among them.</summary>
    function ProgramCapturesKeys: Boolean;
    property OnSetConsoleProfile: TSetConsoleProfileEvent
      read FOnSetConsoleProfile write FOnSetConsoleProfile;
    property OnGetConsoleProfile: TGetConsoleProfileEvent
      read FOnGetConsoleProfile write FOnGetConsoleProfile;
    property OnGetConsoleStartOnLaunch: TGetConsoleStartOnLaunchEvent
      read FOnGetConsoleStartOnLaunch write FOnGetConsoleStartOnLaunch;
    property OnSetConsoleStartOnLaunch: TSetConsoleStartOnLaunchEvent
      read FOnSetConsoleStartOnLaunch write FOnSetConsoleStartOnLaunch;
    property OnGetConsoleCwdToPanels: TGetConsoleStartOnLaunchEvent
      read FOnGetConsoleCwdToPanels write FOnGetConsoleCwdToPanels;
    property OnSetConsoleCwdToPanels: TSetConsoleStartOnLaunchEvent
      read FOnSetConsoleCwdToPanels write FOnSetConsoleCwdToPanels;
    property OnThemeSelect: TThemeSelectEvent read FOnThemeSelect write FOnThemeSelect;
    property OnThemePreview: TThemePreviewEvent read FOnThemePreview write FOnThemePreview;
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
    /// <summary>Select all / Deselect all and select by extension also take folders.</summary>
    property SelectFolders: Boolean read GetSelectFolders write SetSelectFolders;
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
    /// Dual Panel Tab is a Viewer/Editor/Terminal (wkDocument/wkTerminal) -
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
    /// <summary>True while a plugin picture covers the whole window; ABackground is the color
    /// to paint around it.</summary>
    function SurfaceFullscreenBackground(out ABackground: TAlphaColor): Boolean;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX,
  uWinFileDragDrop, uStrings, uFileHistory, uPanelCompare, uChromeRows,
  uExternalTools, uDialogHistory, uChecksums, uKeyChord, uConsoleSettings, uZipVfs;

const
  cLiveFilterHistory = 'livefilter';

/// <summary>Last segment of a path or URI ("C:\a\b\" -> "b", "a.zip!\d\f"
/// -> "f"); '' for a drive root.</summary>
function PathLastSegment(const APath: string): string;
begin
  Result := APath;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['\', '/']) do
    Delete(Result, Length(Result), 1);
  Result := Copy(Result, LastDelimiter('\/:', Result) + 1, MaxInt);
end;

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
    goes through IThemeRenderer - do not add new c* uses on Theme paths. }
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
  cJobErrorFg  = TAlphaColor($FFFFFFFF);
  cJobErrorBg  = TAlphaColor($FFCC0000);
  cJobAskFg    = TAlphaColor($FF000000);
  cJobAskBg    = TAlphaColor($FFFFFF55);
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
  FArchivesUnlocked := TDictionary<string, Boolean>.Create;
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
  // NotifyChanged, not Invalidate: the hide comes from a timer, outside any
  // input/paint pass, so the host must be told to repaint.
  FToast := TToast.Create(
    procedure
    begin
      if FAlive then
        NotifyChanged;
    end);
  // Notices from anywhere (editor, command line, terminal, dialogs). Not
  // over the Ctrl+O console: the toast is not painted there and would pop
  // up stale on return to the panels.
  SetNoticeHandler(
    procedure(const ARequest: TNoticeRequest)
    begin
      if FAlive and not FConsoleMode and Assigned(FToast) then
        FToast.ShowRequest(ARequest);
    end,
    procedure(const ATag: string)
    begin
      if FAlive and Assigned(FToast) then
        FToast.HideTag(ATag);
    end);
  FVfs := CreateDefaultVfs;
  FElevatedVfs := TElevatedFileVfs.Create(FVfs);
  FElevatedIntf := FElevatedVfs;
  FElevatedVfs.OnActiveChanged := HelperActiveChanged;
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
  FPluginListReturnRow := -1;
  FPluginInfoRow := -1;
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
var
  Dir: string;
begin
  FAlive := False;
  if Assigned(FOpenTempDirs) then
  begin
    for Dir in FOpenTempDirs do
      try
        if TDirectory.Exists(Dir) then
          TDirectory.Delete(Dir, True);
      except
        // a copy still open in another program stays; the age purge gets it
      end;
    FreeAndNil(FOpenTempDirs);
  end;
  FreeAndNil(FDescMap);
  FreeAndNil(FArchivesUnlocked);
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
  FreeAndNil(FFolderTreeCtrl);
  FreeAndNil(FHistoryPopupCtrl);
  FreeAndNil(FDirSync);
  FreeAndNil(FSearchDlg);
  FreeAndNil(FJobDialogs);
  FreeAndNil(FJobs);
  FreeAndNil(FSearchUi);
  FreeAndNil(FFileOps);
  FreeAndNil(FSettings);
  FreeAndNil(FThemeDlg);
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
  SetNoticeHandler(nil);
  FreeAndNil(FToast);
  if Assigned(FChecksumToken) then
    FChecksumToken.Cancel;
  if Assigned(FQuickText) then
  begin
    FQuickText.OnChanged := nil;
    FreeAndNil(FQuickText);
  end;
  FLeftModel := nil;
  FRightModel := nil;
  if Assigned(FElevatedVfs) then
  begin
    FElevatedVfs.OnActiveChanged := nil;
    FElevatedVfs.Shutdown;
  end;
  FElevatedVfs := nil;
  FElevatedIntf := nil;
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
  // No outer MDI frame - Host fills desktop; Theme owns Dual Panel chrome.
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
  FKeymapHost.CopyItemNameToClipboard := CopyItemNameToClipboard;
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
  FKeymapHost.OpenPanelFilter := OpenPanelFilter;
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
  FKeymapHost.FolderDown := FolderDown;
  FKeymapHost.GoToParent := GoToParent;
  FKeymapHost.ToggleFolderTree := ToggleFolderTree;
  FKeymapHost.SwapPanels := SwapPanels;
  FKeymapHost.EqualizeOtherPanelToActive := EqualizeOtherPanelToActive;
  FKeymapHost.EqualizeActivePanelFromOther := EqualizeActivePanelFromOther;
  FKeymapHost.FocusCommandLine := FocusCommandLine;
  FKeymapHost.RunDetached := RunDetached;
  FKeymapHost.RunInBackground := RunInBackground;
  FKeymapHost.RunInNewTab := RunInNewTab;
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
  FKeymapHost.BeginDeleteCursor := BeginDeleteCursor;
  FKeymapHost.BeginRename := BeginRename;
  FKeymapHost.BeginCopyInPlace := BeginCopyInPlace;
  FKeymapHost.BeginMkDir := BeginMkDir;
  FKeymapHost.BeginCreateLink := BeginCreateLink;
  FKeymapHost.BeginSetAttributes := BeginSetAttributes;
  FKeymapHost.ShowProperties := ShowProperties;
  FKeymapHost.ShellContextMenu := ShowShellContextMenu;
  FKeymapHost.ExternalView := ExternalView;
  FKeymapHost.ExternalEdit := ExternalEdit;
  FKeymapHost.BeginCompareFiles := BeginCompareFiles;
  FKeymapHost.CompareFolders := CompareFolders;
  FKeymapHost.OpenExternalToolsDialog := OpenExternalToolsDialog;
  FKeymapHost.OpenConsoleOptionsDialog := OpenConsoleOptionsDialog;
  FKeymapHost.BeginSaveConsoleOutput := BeginSaveConsoleOutput;
  FKeymapHost.BeginExportSettings := BeginExportSettings;
  FKeymapHost.BeginImportSettings := BeginImportSettings;
  FKeymapHost.ClearConsoleBuffer := ClearConsoleBuffer;
  FKeymapHost.OpenMarkdownColorsDialog := OpenMarkdownColorsDialog;
  FKeymapHost.BeginChecksums := BeginChecksums;
  FKeymapHost.NavigateToRecycleBin := NavigateToRecycleBin;
  FKeymapHost.RestoreCursorItemFromRecycleBin := RestoreCursorItemFromRecycleBin;
  FKeymapHost.ActivateSide := ActivateSide;
  FKeymapHost.NewPanelTab := NewPanelTab;
  FKeymapHost.NextPanelTab := NextPanelTab;
  FKeymapHost.PrevPanelTab := PrevPanelTab;
  FKeymapHost.RestoreSelection := RestoreSelection;
  FKeymapHost.DescribeItems := DescribeItems;
  FKeymapHost.NewWorkspace := NewWorkspace;
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
  FKeymapHost.OpenUpdates := OpenUpdates;
  FKeymapHost.RestoreHiddenDialogs := RestoreHiddenDialogsNow;
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
  FKeymapHost.UnselectAllActive := UnselectAllActive;
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
  FClickHost.JobStripClick := ClickJobStrip;
  FClickHost.HandleDocumentClick := ClickHandleDocument;
  FClickHost.HandleTerminalClick := ClickHandleTerminal;
  FClickHost.HandleFunctionBarClick := HandleFunctionBarClick;
  FClickHost.HandleDialogClick := ClickHandleDialog;
  FClickHost.LayoutSearchUi := ClickLayoutSearch;
  FClickHost.SearchBounds := ClickSearchBounds;
  FClickHost.CloseSearchUi := CloseSearchUi;
  FClickHost.CloseStub := CloseStub;
  FClickHost.HandleUserMenuClick := FMenus.HandleUserMenuClick;
  FClickHost.HandleSortMenuClick := FMenus.HandleSortMenuClick;
  FClickHost.HandleColumnModeMenuClick := FMenus.HandleColumnModeMenuClick;
  FClickHost.HandleDrivePopupClick := HandleDrivePopupClick;
  FClickHost.HandleFolderTreeClick := HandleFolderTreeClick;
  FClickHost.LayoutJobPopup := ClickLayoutJob;
  FClickHost.JobBounds := ClickJobBounds;
  FClickHost.RequestJobCancel := FJobs.RequestCancel;
  FClickHost.BackgroundJob := FJobs.BackgroundJob;
  FClickHost.CloseJobUi := CloseJobUi;
  FClickHost.CancelOverwriteAsk := ClickCancelOverwrite;
  FClickHost.CancelDeleteAsk := ClickCancelDelete;
  FClickHost.CancelIOErrorAsk := ClickCancelIOError;
  FClickHost.ReloadActiveRows := ReloadActiveRows;
  FClickHost.SetCmdFocused := SetCmdFocused;
  FClickHost.ClickCmdLine := ClickCmdLine;
  FClickHost.ChromeClick := ClickChrome;
  FClickHost.ActivateSide := ActivateSide;
  FClickHost.SelectPanelTabAtCol := SelectPanelTabAtCol;
  FClickHost.NewPanelTabOnSide := NewPanelTabOnSide;
  FClickHost.NavigatePanelToDrive := NavigatePanelToDrive;
  FClickHost.ApplyHeaderSort := ApplyHeaderSort;
end;

procedure TDualPanelWindow.BindDrawHost;
begin
  FDrawHost.DrawDrivePopup := DrawDrivePopup;
  FDrawHost.DrawFolderTree := DrawFolderTree;
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
  FFreeInputHost.DispatchKeymapPrimary := HandleKeymapActionPrimary;
  FFreeInputHost.PreviewCycleDrive := PreviewCycleActiveDrive;
  FFreeInputHost.NavigateActiveToDriveRoot := NavigateActiveToDriveRoot;
  FFreeInputHost.TryPasteClipboard := TryPasteClipboardToCmdLine;
  FFreeInputHost.RestoreGrayOpKey := HostRestoreGrayOpKey;
  FFreeInputHost.BeginSelectByMask := BeginSelectByMask;
  FFreeInputHost.ApplySelectByExtension := ApplySelectByExtension;
  FFreeInputHost.ApplySelectByName := ApplySelectByName;
  FFreeInputHost.HandleQuickSearchInput := HandleQuickSearchInput;
  FFreeInputHost.HandleCmdLineInput := HandleCmdLineInput;
  FFreeInputHost.FocusCommandLine := FocusCommandLine;
  FFreeInputHost.SwitchSide := SwitchSide;
  FFreeInputHost.GoToParent := GoToParent;
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
  FModalInputHost.HandleTerminalProfileList := FSettings.HandleTerminalProfileInput;
  FModalInputHost.HandleAssociationsList := FUserAssociations.HandleListInput;
  FModalInputHost.HandleColorList := FColorCoding.HandleListInput;
  FModalInputHost.HandleColorEdit := FColorCoding.HandleEditInput;
  FModalInputHost.HandleKeymapList := FKeymapDlg.HandleListInput;
  FModalInputHost.HandleCmdHistoryFilter := FCmdHistory.HandleFilterInput;
  FModalInputHost.HandleFileHistoryList := FFileHistory.HandleListInput;
  FModalInputHost.HandleDialogWidget := FDialog.HandleInput;
  FModalInputHost.DialogDropDownOpen := FDialog.DropDownOpen;
  FModalInputHost.RecordDialogHistory := FDialog.RecordInputHistory;
  FModalInputHost.PressDialogButton := FDialog.PressButtonThen;
  FModalInputHost.HandleMarkdownColors := FSettings.HandleMarkdownColorsInput;
  FModalInputHost.HandleThemeColor := FThemeDlg.HandleColorInput;
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
  // While the command line has the focus neither panel is being driven, so
  // both draw the cursor row like an inactive panel.
  uDualPanelDrawUtils.DrawPanelList(
    Buffer, AListBounds, ATab, AActive and not CmdFocused, AMode,
    ModelForSide(ASide), Theme);
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

procedure TDualPanelWindow.ShowInfo(const ATitle, ADetail: string);
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

procedure TDualPanelWindow.HostPreviewTheme(const ASpec: TThemeSpec);
begin
  if Assigned(FOnThemePreview) then
    FOnThemePreview(ASpec);
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

function TDualPanelWindow.HostGetConsoleStartOnLaunch: Boolean;
begin
  if Assigned(FOnGetConsoleStartOnLaunch) then
    Result := FOnGetConsoleStartOnLaunch()
  else
    Result := False;
end;

procedure TDualPanelWindow.HostSetConsoleStartOnLaunch(AValue: Boolean);
begin
  if Assigned(FOnSetConsoleStartOnLaunch) then
    FOnSetConsoleStartOnLaunch(AValue);
end;

function TDualPanelWindow.HostGetConsoleCwdToPanels: Boolean;
begin
  if Assigned(FOnGetConsoleCwdToPanels) then
    Result := FOnGetConsoleCwdToPanels()
  else
    Result := True;
end;

procedure TDualPanelWindow.HostSetConsoleCwdToPanels(AValue: Boolean);
begin
  if Assigned(FOnSetConsoleCwdToPanels) then
    FOnSetConsoleCwdToPanels(AValue);
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

function TDualPanelWindow.GetSelectFolders: Boolean;
begin
  Result := Assigned(FSelHelper) and FSelHelper.SelectFolders;
end;

procedure TDualPanelWindow.SetSelectFolders(AValue: Boolean);
begin
  if Assigned(FSelHelper) then
    FSelHelper.SelectFolders := AValue;
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
  DestPath, OkText, Prefix, ItemName, Suffix: string;
  Recycle: Boolean;
begin
  FDialogKind := hdkJobConfirm;
  if Assigned(FJobs) and (FJobs.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack]) then
  begin
    DestPath := JobConfirmDestText(FJobs.Kind, FJobs.State.DestDirURI);
    FDialog.Open(BuildCopyMoveDialog(ATitle, AMessage, DestPath), DialogCommand);
  end
  else if Assigned(FJobs) and (FJobs.Kind = pjkDelete) then
  begin
    Recycle := FJobs.State.DeleteToRecycleBin;
    if Recycle then
      OkText := T('ui.delete.okRecycle', 'Recycle')
    else
      OkText := T('ui.delete.okWipe', 'Delete');
    if (Length(FJobs.State.Sources) = 1) and
       JobDeleteOneParts(FJobs.State.Sources[0], Recycle, Prefix, ItemName, Suffix) then
      FDialog.Open(BuildDeleteNameDialog(ATitle, Prefix, ItemName, Suffix, OkText, not Recycle),
        DialogCommand)
    else
      FDialog.Open(BuildDeleteDialog(ATitle, AMessage, OkText, not Recycle), DialogCommand);
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
    AOfferPermanent, FJobs.State.AskOfferElevate), DialogCommand);
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
  FDialog.Open(BuildIOErrorDialog(AHeadline, APath, AErrorLine,
    FJobs.State.AskOfferElevate), DialogCommand);
end;

procedure TDualPanelWindow.HostJobFinished(ASuccess: Boolean);
begin
  if FDialogKind = hdkJobProgress then
    CloseJobProgressForReplacement;
  // A stop question left open after the job ended has nothing left to stop.
  if (FDialogKind = hdkStopConfirm) and Assigned(FDialog) and FDialog.Visible then
  begin
    FDialog.Close;
    FDialogKind := hdkNone;
    FStopAccept := nil;
    FStopReject := nil;
  end;
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

procedure TDualPanelWindow.RequestStopConfirm(const AQuestion: string;
  const AOnAccept, AOnReject: TProc);
begin
  if not Assigned(FDialog) then
    Exit;
  // The question replaces whatever dialog is open rather than stacking on it.
  // The progress dialog is closed here; the worker's updates are ignored while
  // FDialogKind is hdkStopConfirm, and the accept/reject callbacks bring it back.
  CloseJobProgressForReplacement;
  if FDialog.Visible then
    FDialog.Close;
  FStopAccept := AOnAccept;
  FStopReject := AOnReject;
  FDialogKind := hdkStopConfirm;
  FDialog.Open(BuildStopConfirmDialog(AQuestion), DialogCommand);
end;

procedure TDualPanelWindow.AnswerStopConfirm(AAccepted: Boolean);
var
  OnAccept, OnReject: TProc;
begin
  OnAccept := FStopAccept;
  OnReject := FStopReject;
  FStopAccept := nil;
  FStopReject := nil;
  FDialogKind := hdkNone;
  if FDialog.Visible then
    FDialog.Close;
  if AAccepted then
  begin
    if Assigned(OnAccept) then
      OnAccept();
  end
  else if Assigned(OnReject) then
    OnReject();
end;

procedure TDualPanelWindow.RequestJobListCancel(AIndex: Integer; AAll: Boolean);
begin
  // The job list closes while the question is up; "Continue" reopens it.
  if AAll then
    RequestStopConfirm(T('ui.stop.all', 'Cancel all operations?'),
      procedure begin FJobs.CancelAll; end,
      procedure begin OpenJobList; end)
  else
    RequestStopConfirm(T('ui.stop.selected', 'Cancel the selected operation?'),
      procedure begin FJobs.CancelJobByIndex(AIndex); end,
      procedure begin OpenJobList; end);
end;

procedure TDualPanelWindow.HostRequestJobStop;
var
  Job: TPanelJobState;
begin
  // Already told to stop and waiting for the worker: nothing left to ask.
  if Assigned(FJobs) and FJobs.TryProgressDialogState(Job) and
     Assigned(Job.Cancel) and Job.Cancel.IsCancellationRequested then
    Exit;
  RequestStopConfirm(T('ui.stop.progress', 'Cancel the current operation?'),
    procedure
    begin
      // The worker stops at its next cancellation check; the progress dialog
      // does not wait for it. The job finishes out of sight, as a background job.
      FJobs.RequestCancel;
      FJobs.BackgroundJob;
    end,
    procedure begin SyncJobProgressDialog; end);
end;

procedure TDualPanelWindow.HostRequestSearchStop;
begin
  RequestStopConfirm(T('ui.stop.search', 'Stop the search?'),
    procedure begin FSearchUi.CancelSearch; end, nil);
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
  CloseFolderTree;
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

procedure TDualPanelWindow.HostTreeNavigate(ASide: TPanelSide; const AURI: string);
var
  Ws: TDualPanelWorkspaceTab;
  Active: TPanelSide;
begin
  // NavigateSideTo activates the side it moves; the other panel following
  // the tree cursor must leave the focus where it is.
  Active := ActiveWorkspace.State.ActiveSide;
  NavigateSideTo(ASide, AURI);
  Ws := ActiveWorkspace;
  if Ws.State.ActiveSide <> Active then
  begin
    Ws.State.ActiveSide := Active;
    SaveActiveWorkspace(Ws);
  end;
  NotifyChanged;
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
    CloseTransientUiBeforeDialog,
    ActiveLocalPath, HostOpenTerminal, HostSetConsoleProfile, HostGetConsoleProfile,
    HostShowShellStub,
    HostGetDisplaySettings, HostApplyDisplaySettings);
  FSettings.OnGetConsoleStartOnLaunch := HostGetConsoleStartOnLaunch;
  FSettings.OnSetConsoleStartOnLaunch := HostSetConsoleStartOnLaunch;
  FSettings.OnGetConsoleCwdToPanels := HostGetConsoleCwdToPanels;
  FSettings.OnSetConsoleCwdToPanels := HostSetConsoleCwdToPanels;
  FThemeDlg := TThemeDialogController.Create(FDialog,
    DialogCommand, HostSetDialogKind, NotifyChanged, CanStartOperation,
    CloseTransientUiBeforeDialog, HostGetActiveThemeId, HostSelectTheme,
    HostPreviewTheme, HostShowShellStub);
  FSettings.OnGetMarkdown :=
    function: TMdColorSet
    begin
      Result := FThemeDlg.ActiveMarkdownSet;
    end;
  FSettings.OnSaveMarkdown :=
    procedure(AInitial, AEdited: TMdColorSet)
    begin
      FThemeDlg.SaveMarkdown(AInitial, AEdited);
    end;
  FColorCoding.OnSave :=
    procedure(AGroups: TArray<TColorCodingGroup>)
    begin
      FThemeDlg.SaveColoring(AGroups);
    end;
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
  // NotifyChanged, not Invalidate: listings land from a background thread
  // with no key press to repaint the screen after them.
  FFolderTreeCtrl := TFolderTreeController.Create(Theme, NotifyChanged,
    HostPanelBounds, HostPanelPath, HostTreeNavigate);
  FJobs := TPanelJobList.Create(Theme, FVfs, NotifyChanged,
    HostOpenJobConfirm, HostOpenOverwriteAsk, HostOpenDeleteError,
    HostOpenIOErrorAsk, HostJobFinished, HostReloadJobPanels, HostClearJobSelection,
    HostJobUiClosed, PauseDirWatchesForJob);
  FJobs.SetElevatedVfs(FElevatedIntf);
  FJobAskDeferred := False;
  FJobs.OnStopRequest := HostRequestJobStop;
  FJobDialogs := TJobDialogController.Create(FDialog, FJobs, DialogCommand,
    HostSetDialogKind);
  FSearchUi := TSearchController.Create(Theme, NotifyChanged, GotoFileLocation,
    HostApplyFindResults, FlushDirWatchPending);
  FSearchUi.OnStopRequest := HostRequestSearchStop;
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
    TInputOverlayEntry.Make(OverlayDrivePopupVisible, HandleDrivePopupInput),
    TInputOverlayEntry.Make(OverlayFolderTreeVisible, HandleFolderTreeInput)
  ];
  FTopMenu := TTopMenuController.Create(Theme, Invalidate, ExecuteTopMenuAction);
  FTopMenu.OnIsRightPanelActive :=
    function: Boolean
    begin
      Result := ActiveWorkspace.State.ActiveSide = psRight;
    end;
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
  Result.FolderTreeVisible := FolderTreeShown;
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
  // First open of the menu is when plugin menu items have to exist.
  if Assigned(FTopMenu) and not FTopMenu.Active then
    HostEnsureAllPlugins;
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
  // blanks DrawContent (dckConsole = F-keys + status) - a black screen.
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
    ActiveDocument.OpenFindDialog;
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
  Name: string;
begin
  Uris := CollectActiveSources;
  if Length(Uris) = 0 then
  begin
    FToast.Show(T('ui.toast.nothingToCopy', 'Nothing to copy'), '', tkWarning);
    Exit;
  end;
  Paths := FileUrisToLocalPaths(Uris);
  FFileClipUris := Uris;
  FFileClipCut := ACut;
  ClipboardSetPanelItems(Paths, Uris, ACut);
  FFileClipSeq := GetClipboardSequenceNumber;
  if Length(Uris) > 1 then
  begin
    if ACut then
      FToast.Show(T('ui.toast.cutItems',
        'Cut to the clipboard: %d items (Ctrl+V moves them)', [Length(Uris)]))
    else
      FToast.Show(T('ui.toast.copiedItems',
        'Copied to the clipboard: %d items', [Length(Uris)]));
    Exit;
  end;
  Name := '';
  if (Length(Paths) > 0) and (Paths[0] <> '') then
    Name := PathLastSegment(Paths[0]);
  if Name = '' then
    Name := PathLastSegment(Uris[0]);
  if ACut then
    FToast.Show(T('ui.toast.cutItem', '"%s" cut to the clipboard (Ctrl+V moves it)'), Name)
  else
    FToast.Show(T('ui.toast.copiedItem', '"%s" copied to the clipboard'), Name);
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
  SyncSurfacePanel;
  PublishPanelEvents;
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
  // Wait for the target side's list to finish - Open() first notifies with
  // LoadingRows, and applying then would clear FPendingSelectName too early.
  if FPendingSelectName <> '' then
  begin
    M := ModelForSide(FPendingSelectSide);
    if Assigned(M) and not M.IsLoading then
      ApplyPendingSelect(FPendingSelectSide, RowsForSide(FPendingSelectSide));
  end
  else
  begin
    // After delete/move CursorIndex may be past EOF - without clamp the
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
    begin
      // Listed with the password just entered: its files open without asking.
      if FArchivePasswordRetry and (M.GetLastError.Code = vecOk) then
        FArchivesUnlocked.AddOrSetValue(LowerCase(ArchiveBasePath(URI)), True);
      FArchivePasswordRetry := False;
    end;
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
  if Assigned(FArchiveAction) then
  begin
    if not DialogCmdIsAccept(AControlId) then
    begin
      FArchiveAction := nil;
      Exit;
    end;
    if not HostSetPluginSecret('mtn.7z', FArchiveActionPath, APassword) then
    begin
      FArchiveAction := nil;
      OpenStub(skShellInfo, 'Archive password', 'Cannot pass password to plugin');
      Exit;
    end;
    CheckArchiveActionPassword;
    Exit;
  end;
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

// An encrypted file at or under one of AURIs, entries of the local ZIP the
// panel at ATabUri shows. The built-in ZIP layer cannot decrypt, so the file
// is addressed through the 7z backend (AProbeUri).
function ZipEncryptedProbe(const ATabUri: string; const AURIs: TArray<string>;
  out AArchivePath, AProbeUri: string): Boolean;
var
  S, Base, Probe: string;
  Segs: TArray<string>;
  Backend: IVirtualFileSystem;
begin
  Result := False;
  AArchivePath := '';
  AProbeUri := '';
  if not IsZipArchiveUri(ATabUri) or HostSevenZipDllMissing then
    Exit;
  AArchivePath := ArchiveBasePath(ATabUri);
  if (AArchivePath = '') or
     not GlobalVfsRegistry.TryResolve(PathToSevenZipRootUri(AArchivePath), Backend) then
    Exit;
  for S in AURIs do
    if SplitArchiveUri(S, Base, Segs) and (Length(Segs) = 1) and
       ZipFindEncryptedEntry(ArchiveBaseLocalPath(Base), Segs[0], Probe) then
    begin
      AProbeUri := JoinVfsUri(PathToSevenZipRootUri(AArchivePath), Probe);
      Exit(True);
    end;
end;

function TDualPanelWindow.ReadableRowUri(const ARow: TPanelRow): string;
var
  Backend: IVirtualFileSystem;
begin
  Result := ARow.URI;
  if ARow.IsEncrypted and not ARow.IsDirectory and IsZipArchiveUri(ARow.URI) and
     not HostSevenZipDllMissing and
     GlobalVfsRegistry.TryResolve(ZipEntryToSevenZipUri(ARow.URI), Backend) then
    Result := ZipEntryToSevenZipUri(ARow.URI);
end;

function TDualPanelWindow.FindLockedArchiveFile(const AURIs: TArray<string>;
  out AArchivePath, AProbeUri: string; AIncludeZip: Boolean): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  S: string;
  R: TPanelRow;
  Best: Int64;
begin
  Result := False;
  AArchivePath := '';
  AProbeUri := '';
  if not GetActiveRowContext(Ws, Panel, Tab, Rows) then
    Exit;
  if AIncludeZip and IsZipArchiveUri(Tab.CurrentURI) then
  begin
    Result := ZipEncryptedProbe(Tab.CurrentURI, AURIs, AArchivePath, AProbeUri) and
      not FArchivesUnlocked.ContainsKey(LowerCase(AArchivePath));
    Exit;
  end;
  if not IsSevenZipUri(Tab.CurrentURI) then
    Exit;
  AArchivePath := ArchiveBasePath(Tab.CurrentURI);
  if (AArchivePath = '') or FArchivesUnlocked.ContainsKey(LowerCase(AArchivePath)) then
    Exit;
  Best := -1;
  for S in AURIs do
    for R in Rows do
      if R.IsEncrypted and not R.IsDirectory and not R.IsParent and
         SameVfsUri(R.URI, S) and ((Best < 0) or (R.Size < Best)) then
      begin
        Best := R.Size;
        AProbeUri := R.URI;
      end;
  Result := Best >= 0;
end;

procedure TDualPanelWindow.RunWithArchivePassword(const AURIs: TArray<string>;
  const AAction: TProc; AIncludeZip: Boolean);
var
  ArchPath, Probe: string;
begin
  if not FindLockedArchiveFile(AURIs, ArchPath, Probe, AIncludeZip) then
  begin
    AAction();
    Exit;
  end;
  FArchiveAction := AAction;
  FArchiveActionPath := ArchPath;
  FArchiveProbeUri := Probe;
  OpenArchiveActionPrompt(False);
end;

procedure TDualPanelWindow.OpenArchiveActionPrompt(AWrong: Boolean);
var
  Prompt, ArchName: string;
begin
  CloseTransientUiBeforeDialog;
  if AWrong then
    Prompt := 'Wrong password:'
  else
    Prompt := 'Password:';
  ArchName := TPath.GetFileName(FArchiveActionPath);
  FDialogKind := hdkArchivePassword;
  FDialog.Open(BuildArchivePasswordDialog(ArchName, Prompt), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.CheckArchiveActionPassword;
const
  // A wrong key breaks decoding within the first bytes, so the start of the
  // smallest encrypted file is enough to check the password.
  cProbeBytes = 64 * 1024;
var
  Backend: IVirtualFileSystem;
begin
  if not GlobalVfsRegistry.TryResolve(FArchiveProbeUri, Backend) then
  begin
    FArchiveAction := nil;
    Exit;
  end;
  Backend.ReadBytesAsync(FArchiveProbeUri, cProbeBytes, nil,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Action: TProc;
    begin
      if not FAlive or not Assigned(FArchiveAction) then
        Exit;
      if AError.Code = vecAccessDenied then
      begin
        OpenArchiveActionPrompt(True);
        Exit;
      end;
      FArchivesUnlocked.AddOrSetValue(LowerCase(FArchiveActionPath), True);
      Action := FArchiveAction;
      FArchiveAction := nil;
      Action();
      NotifyChanged;
    end);
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
  // Must write back to ASide - SetActivePanel follows ActiveSide and would
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
  // find:// is an in-memory snapshot - disk-watch SoftReload races with a
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
  // Only THIS tab's workspace-enter marker, not a global dir-link lookup -
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
      // find:// parent is session root file URI - match via FindSessionParentFileUri
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
begin
  GoHistoryBack(True);
end;

procedure TDualPanelWindow.GoHistoryBack(AShowPopup: Boolean);
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
    if AShowPopup then
      ShowHistoryPopup(Side, Tab)
    else
      // ".." out of a virtual folder with nothing to go back to: the home folder.
      NavigateActiveTo(PathToFileUri(TPath.GetHomePath));
    Exit;
  end;
  Dec(Tab.HistoryIndex);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  NavigateSideTo(Side, Tab.History[Tab.HistoryIndex], False);
  if AShowPopup then
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
begin
  CopyItemsToClipboard(False);
end;

procedure TDualPanelWindow.CopyItemNameToClipboard;
begin
  CopyItemsToClipboard(True);
end;

procedure TDualPanelWindow.CopyItemsToClipboard(ANameOnly: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  R: TPanelRow;
  Paths, Keys: TArray<string>;
  Path, Text: string;
  I: Integer;

  function ItemText(const ARow: TPanelRow): string;
  begin
    Result := PanelItemFullPath(ARow.URI, Tab.CurrentURI, ARow.IsParent);
    if not ANameOnly or (Result = '') then
      Exit;
    // Archive members ("a.zip!\dir\f") split the same way; a drive root
    // has no name and yields ''.
    Result := PathLastSegment(Result);
  end;

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
        Path := ItemText(R);
        if Path <> '' then
          Paths := Paths + [Path];
      end;
  end
  else if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
  begin
    R := Rows[Tab.CursorIndex];
    Path := ItemText(R);
    if Path <> '' then
      Paths := [Path];
  end;

  if Length(Paths) = 0 then
  begin
    FToast.Show(T('ui.toast.nothingToCopy', 'Nothing to copy'), '', tkWarning);
    Exit;
  end;
  Text := Paths[0];
  for I := 1 to High(Paths) do
    Text := Text + sLineBreak + Paths[I];
  ClipboardSet(Text);
  if Length(Paths) > 1 then
  begin
    if ANameOnly then
      FToast.Show(T('ui.toast.copiedNames', 'Names copied to the clipboard: %d',
        [Length(Paths)]))
    else
      FToast.Show(T('ui.toast.copiedPaths', 'Full paths copied to the clipboard: %d',
        [Length(Paths)]));
  end
  else if ANameOnly then
    FToast.Show(T('ui.toast.copiedName', 'Name "%s" copied to the clipboard'), Paths[0])
  else
    FToast.Show(T('ui.toast.copiedPath', 'Full path "%s" copied to the clipboard'), Paths[0]);
end;

procedure TDualPanelWindow.SelectAllActive;
begin
  ApplySelectAllFiles(False);
end;

procedure TDualPanelWindow.UnselectAllActive;
begin
  ApplySelectAllFiles(True);
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
  Before: Integer;
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
  Before := Length(Tab.SelectedURIs);
  if AUnselect then
    TabUnselectByMask(Tab, RowsForSide(Ws.State.ActiveSide), Mask, ASelectFolders)
  else
    TabSelectByMask(Tab, RowsForSide(Ws.State.ActiveSide), Mask, ASelectFolders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
  NoteSelectionUnchanged(Before, Tab, Mask);
end;

procedure TDualPanelWindow.ApplySelectAllFiles(AUnselect: Boolean);
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Folders: Boolean;
  Before: Integer;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Folders := Assigned(FSelHelper) and FSelHelper.SelectFolders;
  Before := Length(Tab.SelectedURIs);
  if AUnselect then
    TabUnselectByMask(Tab, RowsForSide(Ws.State.ActiveSide), '*', Folders)
  else
    TabSelectByMask(Tab, RowsForSide(Ws.State.ActiveSide), '*', Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
  NoteSelectionUnchanged(Before, Tab, '*');
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
  Before: Integer;
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
  Before := Length(Tab.SelectedURIs);
  if AUnselect then
    TabUnselectByMask(Tab, Rows, Mask, Folders)
  else
    TabSelectByMask(Tab, Rows, Mask, Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
  NoteSelectionUnchanged(Before, Tab, Mask);
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
  Before: Integer;
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
  Before := Length(Tab.SelectedURIs);
  TabSelectByNameStem(Tab, Rows, FileNameStem(Name), AUnselect, Folders);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
  NoteSelectionUnchanged(Before, Tab, FileNameStem(Name) + '.*');
end;

procedure TDualPanelWindow.NoteSelectionUnchanged(ABefore: Integer;
  const ATab: TTab; const AMask: string);
begin
  if Length(ATab.SelectedURIs) = ABefore then
    FToast.Show(T('ui.toast.selectionUnchanged', 'Selection unchanged (mask "%s")'),
      AMask, tkWarning);
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
  URI, Text, Token, Base, LowerText: string;
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

  // A whole-line quoted name ("my file.txt", as Ctrl+Enter inserts one with
  // spaces) is a path like an unquoted one.
  Token := UnquoteSingleToken(Text);
  if TryResolveCommandPath(Token, URI) then
  begin
    FCmdLineMgr.Clear;
    OpenOrNavigateAsync(URI);
  end
  else if ((Pos(' ', Token) = 0) and (Pos(#9, Token) = 0)) or (Token <> Text) then
  begin
    // Bare token - async Exists, then open / navigate or shell (no UI-thread
    // disk I/O).
    Ws := ActiveWorkspace;
    Base := FileUriToPath(ActiveTab(ActivePanel(Ws)).CurrentURI);
    ResolveRelativeCommandAsync(Token, Base, Text);
  end
  else
    RunConsoleCommand(Text);
end;

procedure TDualPanelWindow.OpenOrNavigateAsync(const AURI: string);
begin
  if not AURI.StartsWith('file:', True) then
  begin
    NavigateActiveTo(AURI);
    Exit;
  end;
  FVfs.ExistsAsync(AURI, nil,
    procedure(const AExists: Boolean; const AIsDirectory: Boolean;
      const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if AExists and (AError.Code = vecOk) and not AIsDirectory then
        ShellOpenPath(FileUriToPath(AURI))
      else
        NavigateActiveTo(AURI);
    end);
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
var
  Ws: TDualPanelWorkspaceTab;
  URI, Path: string;
begin
  Ws := ActiveWorkspace;
  if not Assigned(FOnShellCwdSync) or (Ws.Kind <> wkPanels) then
    Exit;
  // Same rules as PushShellCwdSync, which stays silent: it also runs on
  // every panel navigation when auto-sync is on.
  URI := ActiveTab(ActivePanel(Ws)).CurrentURI;
  if HasArchiveChain(URI) or IsFindUri(URI) then
    Path := ''
  else
    Path := FileUriToPath(URI);
  if Path = '' then
  begin
    FToast.Show(T('ui.toast.consoleDirUnavailable',
      'The console cannot go into this folder'), '', tkWarning);
    Exit;
  end;
  PushShellCwdSync;
  FToast.Show(T('ui.toast.consoleDir', 'Console folder: %s'), Path);
end;

procedure TDualPanelWindow.RunConsoleCommand(const ACommand: string);
begin
  if SendConsoleCommand(ACommand) then
    // Only a command typed under the panels sends the program back to them;
    // one typed in the background console stays in the console.
    if GConsoleSettings.ReturnToPanels and Assigned(FOnReturnWhenDone) then
      FOnReturnWhenDone(Self);
end;

procedure TDualPanelWindow.RunInNewTab;
var
  Cmd, Profile: string;
begin
  if not Assigned(FCmdLineMgr) then
    Exit;
  Cmd := Trim(FCmdLineMgr.Text);
  if Cmd = '' then
    Exit;
  FCmdLineMgr.RememberCommand(Cmd);
  FCmdLineMgr.Clear;
  Profile := HostGetConsoleProfile;
  if Profile = '' then
    Profile := cShellProfileCmd;
  OpenTerminal(Profile, PanelCommandCwd, Cmd);
end;

procedure TDualPanelWindow.RunInBackground;
begin
  if not Assigned(FCmdLineMgr) or (Trim(FCmdLineMgr.Text) = '') then
    Exit;
  FCmdLineMgr.RememberCommand(FCmdLineMgr.Text);
  if SendConsoleCommand(FCmdLineMgr.Text) and Assigned(FOnRunInBackground) then
    FOnRunInBackground(Self);
end;

function TDualPanelWindow.SendConsoleCommand(const ACommand: string): Boolean;
var
  Cmd, Cwd: string;
begin
  Result := False;
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
  Result := True;
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

function TDualPanelWindow.FolderTreeShown: Boolean;
begin
  // Only over panels: another workspace or the console leaves it closed.
  Result := Assigned(FFolderTreeCtrl) and FFolderTreeCtrl.Visible and
    not FConsoleMode and (ActiveWorkspace.Kind = wkPanels);
end;

function TDualPanelWindow.OverlayFolderTreeVisible: Boolean;
begin
  // The tree owns the keys only while its side is the active one.
  Result := FolderTreeShown and
    (ActiveWorkspace.State.ActiveSide = FFolderTreeCtrl.Side);
end;

function TDualPanelWindow.HandleFolderTreeInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  // Tab hands the focus to the other panel; the tree stays.
  if (AKey = vkTab) and (AShift * [ssCtrl, ssAlt, ssShift] = []) then
  begin
    FFolderTreeCtrl.StopFollow;
    SwitchSide;
    AKey := 0;
    AKeyChar := #0;
    NotifyChanged;
    Exit(True);
  end;
  // Ctrl+U swaps the panels with the tree too.
  if MatchActiveAction(AKey, AShift) = kaSwapPanels then
  begin
    SwapPanels;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  Result := FFolderTreeCtrl.HandleInput(AKey, AShift, AKeyChar);
end;

function TDualPanelWindow.HandleFolderTreeClick(ALocalCol, ALocalRow: Integer): Boolean;
begin
  if not FolderTreeShown then
    Exit(False);
  case FFolderTreeCtrl.HandleClick(ALocalCol, ALocalRow) of
    ftcOutside:
      Exit(False);
    ftcFocusTree:
      ActivateSide(FFolderTreeCtrl.Side);
    ftcFocusFiles:
      ActivateSide(OppositeSide(FFolderTreeCtrl.Side));
  end;
  NotifyChanged;
  Result := True;
end;

procedure TDualPanelWindow.DrawFolderTree;
begin
  if not Assigned(FFolderTreeCtrl) or not FFolderTreeCtrl.Visible then
    Exit;
  if not FolderTreeShown then
  begin
    FFolderTreeCtrl.Close;
    Exit;
  end;
  FFolderTreeCtrl.Draw(Buffer, OverlayFolderTreeVisible);
end;

procedure TDualPanelWindow.ToggleFolderTree;
begin
  if not Assigned(FFolderTreeCtrl) or (ActiveWorkspace.Kind <> wkPanels) then
    Exit;
  if not FFolderTreeCtrl.Visible then
  begin
    CloseDrivePopup;
    SetCmdFocused(False);
  end;
  FFolderTreeCtrl.Toggle(ActiveWorkspace.State.ActiveSide);
  NotifyChanged;
end;

procedure TDualPanelWindow.CloseFolderTree;
begin
  if Assigned(FFolderTreeCtrl) then
    FFolderTreeCtrl.Close;
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
  // strip it anyway so ExtractFilePath yields the parent either way rather
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
begin
  if GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    ActivateRow(Tab, Row);
end;

procedure TDualPanelWindow.GoToParent;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  I: Integer;
begin
  // Whatever Enter on ".." does here (a folder up, out of an archive, back
  // from search results / the Recycle Bin); nothing at a drive root.
  if not GetActiveRowContext(Ws, Panel, Tab, Rows) then
    Exit;
  for I := 0 to High(Rows) do
    if Rows[I].IsParent then
    begin
      ActivateRow(Tab, Rows[I]);
      Exit;
    end;
end;

procedure TDualPanelWindow.ActivateRow(const ATab: TTab; const ARow: TPanelRow);
var
  ArchiveKind: TArchiveExtensionKind;
  IsArchiveFile: Boolean;
  UserCommand, Uri, ArchiveScheme: string;
begin
  Uri := ARow.URI;
  // A plugin that serves this panel's scheme may take the activation itself.
  if (not ARow.IsParent) and (ARow.URI <> '') and
     PanelPluginRegistry.TryActivate(ATab.CurrentURI, ARow.URI, ARow.IsDirectory) then
    Exit;
  // Ask the registry which extensions currently navigate as an archive
  // (built-in zip/jar/apk plus whatever a loaded plugin's manifest declared
  // - see uVfsRegistry.RegisterArchiveExtension) instead of hardcoding the
  // extension list here.
  IsArchiveFile := (ARow.URI <> '') and
    GlobalVfsRegistry.TryResolveArchive(ARow.Text, ArchiveKind, ArchiveScheme);
  case ClassifyActivateCurrent(
    IsFindUri(ATab.CurrentURI) and (not ARow.IsParent) and (ARow.URI <> ''),
    ARow.IsParent and (IsSystemFoldersUri(ATab.CurrentURI) or
      IsRecycleBinUri(ATab.CurrentURI)),
    ARow.IsDirectory or ARow.IsParent,
    IsArchiveFile,
    ResolveAssociationWithUserRules(ARow.Text, False, UserCommand)) of
    ackFindGoto:
      GotoFileLocation(FileUriToPath(ARow.URI));
    ackHistoryBack:
      GoHistoryBack(False);
    ackNavigate:
      if ARow.URI <> '' then
        NavigateActiveTo(ARow.URI);
    ackZipNavigate:
      if (ArchiveKind = akPluginScheme) and (not HasArchiveChain(ARow.URI)) then
      begin
        FSkipArchivePasswordUri := '';
        FArchivePasswordRetry := False;
        NavigateActiveTo(PathToArchiveRootUri(ArchiveScheme, FileUriToPath(ARow.URI)))
      end
      else
        NavigateActiveTo(EnsureArchiveRootUri(ARow.URI));
    ackView:
      RunWithArchivePassword([Uri],
        procedure
        begin
          RequestOpenViewer(ReadableRowUri(ARow));
        end, True);
    ackEdit:
      RunWithArchivePassword([Uri],
        procedure
        begin
          RequestOpenEditor(ReadableRowUri(ARow));
        end, True);
    ackShell:
      if HasArchiveChain(Uri) or IsSevenZipUri(Uri) then
        RunWithArchivePassword([Uri],
          procedure
          begin
            ShellOpenArchiveEntry(Uri, ARow.Text);
          end)
      else
        ShellOpenPath(FileUriToPath(ARow.URI));
    ackCommand:
      RunUserCommandCurrent(ARow.URI, UserCommand);
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
  // The list opens above the command line (CmdLineRow).
  Ws := ActiveWorkspace;
  EditX := DualPanelCmdLineEditX(ActiveTab(ActivePanel(Ws)).CurrentURI, Area.Width);
  FCmdLineMgr.HistoryPopup.Open(FCmdLineMgr.GetHistoryItems, FCmdLineMgr.Text,
    CmdLineRow(Area.Height), EditX, Area.Width - 1, Area.Width, Area.Height);
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
  // The command line takes every Enter chord as Enter itself; the runs that
  // have a binding of their own are looked up first.
  if AKey = vkReturn then
    case MatchActiveAction(AKey, AShift) of
      kaRunInBackground:
        begin
          RunInBackground;
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
      kaRunInNewTab:
        begin
          RunInNewTab;
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
    end;
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
  CloseFolderTree;
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
  // Every user-initiated stop asks first; the operation is interrupted only
  // from the question's Stop button.
  if (Kind = hdkJobProgress) and DialogCmdIsReject(AControlId) and
     Assigned(FJobs) and (FJobs.Phase = pjpRunning) then
  begin
    HostRequestJobStop;
    NotifyChanged;
    Exit;
  end;
  if (Kind = hdkJobList) and Assigned(FJobs) and
     (DialogCmdIs(AControlId, cDlgCmdCancelJob) or DialogCmdIs(AControlId, cDlgCmdCancelAll)) then
  begin
    RequestJobListCancel(FDialog.GetListSelectedIndex('jobs'),
      DialogCmdIs(AControlId, cDlgCmdCancelAll));
    NotifyChanged;
    Exit;
  end;
  if Kind = hdkStopConfirm then
  begin
    AnswerStopConfirm(DialogCmdIsAccept(AControlId));
    NotifyChanged;
    FlushDirWatchPending;
    FlushPendingJobAsk;
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
var
  HostCmd: TProc<string, string>;
  ReturnRow: Integer;
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
    hdkPluginList:
      Result := HandlePluginListCommand(AControlId);
    hdkPluginInfo:
      Result := HandlePluginInfoCommand(AControlId);
    hdkPluginPerms:
      Result := HandlePluginPermsCommand(AControlId);
    hdkFolderHistory:
      Result := FFolderHistory.DispatchCommand(AControlId);
    hdkPanelFilter:
      Result := HandlePanelFilterCommand(AControlId);
    hdkDescribe:
      Result := HandleDescribeCommand(AControlId, AFields);
    hdkConsoleSave:
      Result := HandleConsoleSaveCommand(AControlId, AFields);
    hdkSettingsExport, hdkSettingsImport:
      Result := HandleSettingsFileCommand(AKind, AControlId, AFields);
    hdkTheme, hdkThemeNew, hdkThemeName, hdkThemeDelete, hdkThemeEditor,
    hdkThemeItems, hdkThemeColors, hdkThemeText, hdkThemeChoice, hdkThemePicker:
      Result := FThemeDlg.DispatchCommand(AKind, AControlId);
    hdkColumnsConfig, hdkDisplay, hdkTerminalProfile, hdkConsoleProfile,
    hdkExternalTools, hdkMarkdownColors, hdkMarkdownImport, hdkMarkdownPicker,
    hdkConsoleOptions:
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
    hdkHost:
      begin
        FDialog.Close;
        HostCmd := FHostDialogCommand;
        FHostDialogCommand := nil;
        if Assigned(HostCmd) then
          HostCmd(AControlId, AValuesJson);
        // A plugin's settings dialog is over: back to the Plugins list, unless the
        // plugin chained another dialog (the list waits for that one).
        if (FPluginListReturnRow >= 0) and not FDialog.Visible then
        begin
          ReturnRow := FPluginListReturnRow;
          FPluginListReturnRow := -1;
          ShowPluginList(ReturnRow);
        end;
      end;
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
  RunMkDir(FVfs, URI, SelectName, True);
end;

procedure TDualPanelWindow.RunMkDir(const AVfs: IVirtualFileSystem;
  const AURI, ASelectName: string; AMayElevate: Boolean);
begin
  AVfs.CreateDirectoryAsync(AURI, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if ASuccess then
      begin
        ReloadActiveRows;
        NotifyChanged;
        Exit;
      end;
      FPendingSelectName := '';
      if AMayElevate and (AError.Code = vecAccessDenied) and CanElevateLocal(AURI) then
        OfferElevated(
          procedure
          begin
            FPendingSelectName := ASelectName;
            RunMkDir(FElevatedIntf, AURI, ASelectName, False);
          end)
      else if AError.Message <> '' then
        OpenStub(skShellInfo, 'MkDir failed', AError.Message)
      else
        OpenStub(skShellInfo, 'MkDir failed', 'Unknown error');
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

procedure TDualPanelWindow.ShowShellContextMenu;
var
  Ws: TDualPanelWorkspaceTab;
  Side: TPanelSide;
  Tab: TTab;
  Uris, Paths: TArray<string>;
  Col, Row: Integer;
begin
  if not HostInPanelsWorkspace then
    Exit;
  Ws := ActiveWorkspace;
  Side := Ws.State.ActiveSide;
  Tab := ActiveTab(ActivePanel(Ws));
  Uris := CollectActiveSources;
  // ".." with nothing selected: the menu of the folder being shown.
  if Length(Uris) = 0 then
    Uris := [Tab.CurrentURI];
  Paths := FileUrisToLocalPaths(Uris);
  if Length(Paths) = 0 then
  begin
    OpenStub(skShellInfo, T('ui.shellMenu.title', 'Context menu'),
      T('ui.properties.unavailable', 'Only for files and folders on disk'));
    Exit;
  end;
  // Anchor: the start of the cursor row; the panel's top-left corner when
  // the cursor is scrolled out of view.
  if not PanelListIndexCell(PanelListBounds(HostPanelBounds(Side)),
    ActivePanel(Ws).ColumnMode, Tab.ScrollOffset, Tab.CursorIndex, Col, Row) then
  begin
    Col := HostPanelBounds(Side).Left + 1;
    Row := HostPanelBounds(Side).Top + 1;
  end;
  if Assigned(FOnShellContextMenu) then
    FOnShellContextMenu(Paths, Col, Row);
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
  // Link creation is a single fast filesystem-metadata call - not routed
  // through IVirtualFileSystem (local-disk only, no VFS scheme needs it) -
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
  // The new selection replaces the previous one on both sides, as in FAR.
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
  URI, Name: string;
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
  Name := PathLastSegment(Row.Text);
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
            FToast.Show(T('ui.toast.restored', '"%s" restored from the Recycle Bin'), Name);
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
  RunRename(FVfs, FromURI, ToURI, CleanName, True);
end;

procedure TDualPanelWindow.RunRename(const AVfs: IVirtualFileSystem;
  const AFromURI, AToURI, ANewName: string; AMayElevate: Boolean);
begin
  AVfs.MoveAsync(AFromURI, AToURI, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if ASuccess then
      begin
        ReloadActiveRows;
        NotifyChanged;
        Exit;
      end;
      FPendingSelectName := '';
      if AMayElevate and (AError.Code = vecAccessDenied) and
         CanElevateLocal(AFromURI) and CanElevateLocal(AToURI) then
        OfferElevated(
          procedure
          begin
            FPendingSelectName := ANewName;
            RunRename(FElevatedIntf, AFromURI, AToURI, ANewName, False);
          end)
      else
        OpenStub(skShellInfo, 'Rename failed', AError.Message);
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
  if not CanBeginAnotherJob then
    Exit;
  Side := ActiveWorkspace.State.ActiveSide;
  FPendingSelectName := CleanName;
  FPendingSelectSide := Side;
  // A job like F5: progress, the job list, Esc to cancel, and the usual
  // question when a file inside fails.
  FJobs.BeginJobPairs([FromURI], [ToURI], pjkCopy);
  NotifyChanged;
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

procedure TDualPanelWindow.ResolveRelativeCommandAsync(const AText, ABaseDir,
  ACommand: string);
var
  Combined, URI, Cmd: string;
begin
  Cmd := Trim(ACommand);
  if (Trim(AText) = '') or (ABaseDir = '') then
    Exit;
  Combined := TPath.Combine(ABaseDir, Trim(AText));
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
        // A folder is entered; a file runs as a command would: a console
        // program in the built-in console, anything else with its Windows
        // program. The panel's own associations (viewer, editor) are F3 / F4
        // and Enter on the file itself.
        if AIsDirectory then
          NavigateActiveTo(URI)
        else
          ShellOpenPath(Combined);
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
  case ClassifyNeedleBoxKey(AKey, AKeyChar, Ch) of
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

procedure TDualPanelWindow.OpenPanelFilter;
const
  cPresets: array[0..3] of string = (
    '*.txt;*.md;*.log',
    '*.exe;*.dll;*.bat;*.cmd',
    '*.jpg;*.jpeg;*.png;*.gif;*.bmp',
    '*.zip;*.7z;*.rar;*.tar;*.gz');
var
  Items: TArray<string>;
  Recent: TArray<string>;
  Mask: string;
  I: Integer;

  procedure Add(const AMask: string);
  var
    J: Integer;
  begin
    if Trim(AMask) = '' then
      Exit;
    for J := 1 to High(FFilterPresets) do
      if SameText(FFilterPresets[J], AMask) then
        Exit;
    FFilterPresets := FFilterPresets + [AMask];
    Items := Items + [AMask];
  end;

begin
  if ActiveWorkspace.Kind <> wkPanels then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  CloseTransientUiBeforeDialog;
  // Entry 0 clears the filter; then the masks used before, then the stock ones.
  FFilterPresets := [''];
  Items := [T('ui.panelFilter.none', '(no filter)')];
  Recent := DialogHistoryItems(cLiveFilterHistory);
  for I := 0 to Min(High(Recent), 7) do
    Add(Recent[I]);
  for Mask in cPresets do
    Add(Mask);
  FDialogKind := hdkPanelFilter;
  FDialog.Open(BuildPanelFilterDialog(Items, FFilterMask), DialogCommand);
end;

procedure TDualPanelWindow.ApplyPanelFilter(const AMask: string);
begin
  if AMask = '' then
    ClearPanelFilter
  else
  begin
    SetPanelFilterMask(AMask);
    DialogHistoryAdd(cLiveFilterHistory, AMask);
  end;
end;

function TDualPanelWindow.HandlePanelFilterCommand(const AControlId: string): Boolean;
var
  Idx: Integer;
  Mask: string;
  Apply: Boolean;
begin
  Result := True;
  Apply := False;
  Mask := '';
  if DialogCmdIsListAccept(AControlId, 'presets') and not DialogCmdIsAccept(AControlId) then
  begin
    // Enter or a double click on the list picks that entry as it is.
    Idx := FDialog.GetListSelectedIndex('presets');
    if (Idx >= 0) and (Idx <= High(FFilterPresets)) then
    begin
      Mask := FFilterPresets[Idx];
      Apply := True;
    end;
  end
  else if DialogCmdIsAccept(AControlId) then
  begin
    Mask := Trim(FDialog.GetInputValue('mask'));
    Apply := True;
  end
  else if DialogCmdIs(AControlId, cDlgCmdClearFilter) then
    Apply := True;
  FDialog.Close;
  SetLength(FFilterPresets, 0);
  if Apply then
    ApplyPanelFilter(Mask);
end;

procedure TDualPanelWindow.RestoreSelection;
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
  TabRestoreSelection(Tab);
  SetActiveTab(Panel, Tab);
  SetActivePanel(Ws, Panel);
  SaveActiveWorkspace(Ws);
  Invalidate;
end;

function TDualPanelWindow.DescriptionOf(const ADirUri, AName: string): string;
var
  Dir, Path: string;
  Stamp: TDateTime;
  Tick: UInt64;
begin
  Result := '';
  Dir := FileUriToPath(ADirUri);
  if (Dir = '') or (AName = '') then
    Exit;
  Tick := GetTickCount64;
  if (not SameText(Dir, FDescDir)) or (FDescMap = nil) or (Tick - FDescCheckedAt > 1500) then
  begin
    // The timestamp is looked at every second or so, not on every frame.
    Path := DescriptionsFilePath(Dir);
    if not FileAge(Path, Stamp) then
      Stamp := 0;
    if (not SameText(Dir, FDescDir)) or (FDescMap = nil) or (Stamp <> FDescStamp) then
    begin
      FreeAndNil(FDescMap);
      FDescMap := LoadDescriptions(Dir);
      FDescDir := Dir;
      FDescStamp := Stamp;
    end;
    FDescCheckedAt := Tick;
  end;
  if not FDescMap.TryGetValue(AName, Result) then
    Result := '';
end;

procedure TDualPanelWindow.DescribeItems;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  R: TPanelRow;
  Keys, Names: TArray<string>;
  Dir, Value, Prompt: string;
  Map: TDictionary<string, string>;

  procedure AddName(const ARow: TPanelRow);
  var
    Full: string;
  begin
    if ARow.IsParent or (ARow.URI = '') then
      Exit;
    Full := PanelItemFullPath(ARow.URI, Tab.CurrentURI, False);
    if Full <> '' then
      Names := Names + [PathLastSegment(Full)];
  end;

begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  Panel := ActivePanel(Ws);
  Tab := ActiveTab(Panel);
  Dir := FileUriToPath(Tab.CurrentURI);
  if (Dir = '') or not TDirectory.Exists(Dir) then
  begin
    FToast.Show(T('ui.toast.describeLocal', 'Descriptions need a folder on a local disk'));
    Exit;
  end;
  Rows := RowsForSide(Ws.State.ActiveSide);
  Names := nil;
  if Length(Tab.SelectedURIs) > 0 then
  begin
    Keys := TabSelectionKeys(Tab);
    for R in Rows do
      if SelectionKeysHas(Keys, R.URI) then
        AddName(R);
  end
  else if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) then
    AddName(Rows[Tab.CursorIndex]);
  if Length(Names) = 0 then
  begin
    FToast.Show(T('ui.toast.describeNothing', 'Nothing to describe'));
    Exit;
  end;
  Value := '';
  if Length(Names) = 1 then
  begin
    Prompt := Names[0];
    Map := LoadDescriptions(Dir);
    try
      if not Map.TryGetValue(Names[0], Value) then
        Value := '';
    finally
      Map.Free;
    end;
  end
  else
    Prompt := T('ui.describe.many', '%d items', [Length(Names)]);
  FDescribeDir := Dir;
  FDescribeNames := Names;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkDescribe;
  FDialog.Open(BuildInputDialog(T('ui.describe.title', 'Describe'), Prompt, Value),
    DialogCommand);
end;

function TDualPanelWindow.HandleDescribeCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  Name, Text: string;
  Ok: Boolean;
begin
  Result := True;
  if DialogCmdIsAccept(AControlId) then
  begin
    Text := Trim(AFields.Name);
    Ok := True;
    for Name in FDescribeNames do
      Ok := StoreDescription(FDescribeDir, Name, Text) and Ok;
    FDescCheckedAt := 0;
    FDescStamp := -1;
    if not Ok then
      FToast.Show(T('ui.toast.describeFailed', 'Cannot write Descript.ion here'));
  end;
  FDialog.Close;
  SetLength(FDescribeNames, 0);
end;

procedure TDualPanelWindow.ClearPanelFilter;
var
  M: IPanelModel;
begin
  if FFilterMask = '' then
    Exit;
  FFilterMask := '';
  M := ModelForSide(ActiveWorkspace.State.ActiveSide);
  if Assigned(M) then
    M.SetFilterMask('');
  NotifyChanged;
end;

procedure TDualPanelWindow.SetPanelFilterMask(const AText: string);
var
  M: IPanelModel;
begin
  FFilterMask := AText;
  M := ModelForSide(ActiveWorkspace.State.ActiveSide);
  if Assigned(M) then
    M.SetFilterMask(FFilterMask);
  NotifyChanged;
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
    // Only clamp indices - do not pull ScrollOffset to CursorIndex with ViewH=1.
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
    RunWithArchivePassword([Row.URI],
      procedure
      begin
        RequestOpenEditor(ReadableRowUri(Row));
      end, True)
  else
    RunWithArchivePassword([Row.URI],
      procedure
      begin
        RequestOpenViewer(ReadableRowUri(Row));
      end, True);
end;

procedure TDualPanelWindow.FolderDown;
var
  Ws: TDualPanelWorkspaceTab;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Row: TPanelRow;
  Idx: Integer;
  FileUri, ArcUri: string;
  Backend: IVirtualFileSystem;
begin
  // A file that is not an archive gets no reaction at all (FAR).
  if not GetActiveRow(Ws, Panel, Tab, Rows, Row, Idx) then
    Exit;
  if Row.IsParent or (Row.URI = '') then
    Exit;
  if Row.IsDirectory then
  begin
    ActivateRow(Tab, Row);
    Exit;
  end;
  if not Row.URI.StartsWith('file:', True) or HasArchiveChain(Row.URI) then
    Exit;
  if FileHasZipSignature(FileUriToPath(Row.URI)) then
  begin
    NavigateActiveTo(EnsureArchiveRootUri(Row.URI));
    Exit;
  end;
  // The 7z plugin finds the format by content; enter only once it lists
  // the file (or asks for its password).
  FileUri := Row.URI;
  ArcUri := PathToSevenZipRootUri(FileUriToPath(FileUri));
  if not GlobalVfsRegistry.TryResolve(ArcUri, Backend) then
    Exit;
  Backend.ListDirectoryAsync(ArcUri, nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    var
      W: TDualPanelWorkspaceTab;
      P: TPanelState;
      Tb: TTab;
      Rs: TPanelRows;
      Cur: TPanelRow;
      I: Integer;
    begin
      if not (AError.Code in [vecOk, vecAccessDenied]) then
        Exit;
      // The cursor moved on while the plugin was reading: stay put.
      if not GetActiveRow(W, P, Tb, Rs, Cur, I) or not SameVfsUri(Cur.URI, FileUri) then
        Exit;
      FSkipArchivePasswordUri := '';
      FArchivePasswordRetry := False;
      NavigateActiveTo(ArcUri);
    end);
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
  // Over the folder tree the wheel scrolls it; the cursor and the focus stay.
  if FolderTreeShown and not (Assigned(FDialog) and FDialog.Visible) and
     FFolderTreeCtrl.Bounds.Contains(ALocalCol, ALocalRow) then
  begin
    if AWheelDelta > 0 then
      FFolderTreeCtrl.ScrollBy(-3)
    else
      FFolderTreeCtrl.ScrollBy(3);
    Exit(True);
  end;
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

function TDualPanelWindow.SurfaceFullscreenBackground(out ABackground: TAlphaColor): Boolean;
var
  Doc: TEditorWindow;
begin
  ABackground := 0;
  Doc := ActiveDocument;
  Result := FAlive and not FConsoleMode and not HelpVisible and Assigned(Doc) and
    (ActiveWorkspace.Kind = wkDocument) and Doc.IsSurfaceFullscreen and
    not (Assigned(FDialog) and FDialog.Visible);
  if Result then
    ABackground := Doc.SurfaceBackground;
end;

function TDualPanelWindow.MarkdownImageOverlayVisible: Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  // Host dialogs and the top menu drop-down are cells too; the image Overlay
  // would paint over them.
  Result := (not FConsoleMode) and (not HelpVisible) and Assigned(Doc) and
    not (Assigned(FDialog) and FDialog.Visible) and
    not (Assigned(FTopMenu) and FTopMenu.Active) and
    Doc.MarkdownImageOverlayVisible;
end;

procedure TDualPanelWindow.ShellOpenPath(const APath: string);
begin
  if APath = '' then
    Exit;
  // A console program runs in the built-in console or a terminal tab, so
  // its output stays on screen; anything else is the Windows shell's.
  if Assigned(FOnLaunchConsoleFile) and FOnLaunchConsoleFile(APath) then
  begin
    NotifyChanged;
    Exit;
  end;
  // Platform shell open (Windows ShellExecute today; xdg-open / open later).
  if not ShellOpenFile(APath) then
    OpenStub(skShellInfo, 'Shell open failed', APath)
  else
    NotifyChanged;
end;


// A file inside an archive has no path the Windows shell can open: unpack it
// into a fresh temp folder and open the copy. The folders are removed when the
// window is destroyed; any left over (a copy still open elsewhere, a crash)
// are purged after a day.
procedure TDualPanelWindow.ShellOpenArchiveEntry(const AURI, AName: string);
var
  Root, Dir, Dst, LeafName: string;
  Old: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-open');
  try
    if TDirectory.Exists(Root) then
      for Old in TDirectory.GetDirectories(Root) do
        if TDirectory.GetCreationTime(Old) < Now - 1 then
          TDirectory.Delete(Old, True);
  except
    // a folder still in use by the program it was opened in stays
  end;
  LeafName := TPath.GetFileName(StringReplace(AName, '/', PathDelim, [rfReplaceAll]));
  if LeafName = '' then
    Exit;
  Dir := TPath.Combine(Root, TGUID.NewGuid.ToString.Trim(['{', '}']));
  Dst := TPath.Combine(Dir, LeafName);
  try
    ForceDirectories(Dir);
  except
    OpenStub(skShellInfo, 'Shell open failed', Dir);
    Exit;
  end;
  if not Assigned(FOpenTempDirs) then
    FOpenTempDirs := TStringList.Create;
  FOpenTempDirs.Add(Dir);
  FVfs.CopyAsync(AURI, PathToFileUri(Dst), nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if ASuccess then
        ShellOpenPath(Dst)
      else if IsZipArchiveUri(AURI) and (ZipEntryToSevenZipUri(AURI) <> '') then
      begin
        // The built-in ZIP layer cannot decrypt AES or unpack every method;
        // 7z.dll can.
        if HostSevenZipDllMissing then
          OpenStub(skShellInfo, 'Shell open failed',
            AError.Message + '. Put 7z.dll into plugins\mtn.7z\ to open such files.')
        else
          ShellOpenSevenZipEntry(ZipEntryToSevenZipUri(AURI), Dst, False);
      end
      else
        OpenStub(skShellInfo, 'Shell open failed', AError.Message);
    end, True);
end;

// Unpacks an entry through the 7z:// backend and opens the copy. A password
// request is answered through the archive password dialog, then the unpack
// is repeated once.
procedure TDualPanelWindow.ShellOpenSevenZipEntry(const ASevenUri, ADst: string;
  ARetried: Boolean);
begin
  FVfs.CopyAsync(ASevenUri, PathToFileUri(ADst), nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if ASuccess then
      begin
        ShellOpenPath(ADst);
        Exit;
      end;
      if (AError.Code = vecAccessDenied) and not ARetried then
      begin
        FArchiveActionPath := ArchiveBasePath(ASevenUri);
        FArchiveProbeUri := ASevenUri;
        FArchiveAction :=
          procedure
          begin
            ShellOpenSevenZipEntry(ASevenUri, ADst, True);
          end;
        OpenArchiveActionPrompt(False);
        NotifyChanged;
      end
      else
        OpenStub(skShellInfo, 'Shell open failed', AError.Message);
    end, True);
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

procedure TDualPanelWindow.OpenUpdates;
begin
  if Assigned(FOnOpenUpdates) then
    FOnOpenUpdates(Self);
end;

procedure TDualPanelWindow.RestoreHiddenDialogsNow;
var
  Count: Integer;
begin
  Count := uHiddenDialogs.RestoreHiddenDialogs;
  if Count = 0 then
    Notice(T('ui.toast.noHiddenDialogs', 'No dialogs are hidden'))
  else
    Notice(T('ui.toast.hiddenDialogsRestored', 'Hidden dialogs will be shown again: %s'),
      IntToStr(Count));
end;

procedure TDualPanelWindow.HelperActiveChanged(AActive: Boolean);
begin
  if not FAlive then
    Exit;
  FHelperActive := AActive;
  if AActive then
    FToast.Show(T('ui.toast.adminHelperOn',
      'Administrator helper started: file operations run with administrator rights'),
      '', tkWarning)
  else
    FToast.Show(T('ui.toast.adminHelperOff', 'Administrator helper stopped'));
  if Assigned(FOnHelperActiveChanged) then
    FOnHelperActiveChanged(Self);
  NotifyChanged;
end;

function TDualPanelWindow.CanElevateLocal(const AURI: string): Boolean;
begin
  Result := Assigned(FElevatedIntf) and not IsProcessElevated and
    not HasArchiveChain(AURI) and (FileUriToPath(AURI) <> '');
end;

procedure TDualPanelWindow.OfferElevated(const AAction: TProc);
begin
  if not ShowHostDialog(BuildConfirmDialog(
       T('ui.admin.title', 'Administrator rights'),
       T('ui.admin.confirm', 'Access denied. Repeat as administrator?')),
     procedure(ACmd, AValues: string)
     begin
       if FAlive and DialogCmdIsAccept(ACmd) then
         AAction();
     end) then
    Exit;
  NotifyChanged;
end;

function TDualPanelWindow.ShowHostDialog(const ADecl: TDialogDeclaration;
  const AOnCommand: TProc<string, string>): Boolean;
begin
  Result := Assigned(FDialog) and not FDialog.Visible;
  if not Result then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkHost;
  FHostDialogCommand := AOnCommand;
  FDialog.Open(ADecl, DialogCommand);
  NotifyChanged;
end;

function TDualPanelWindow.HasBusyJob: Boolean;
begin
  Result := Assigned(FJobs) and FJobs.HasBusyJob;
end;

procedure TDualPanelWindow.OpenPluginListDialog;
begin
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  CloseTransientUiBeforeDialog;
  HostEnsureAllPlugins;
  HostPluginsBegin;
  ShowPluginList(0);
end;

procedure TDualPanelWindow.ShowPluginList(ASelectedIndex: Integer);
begin
  FDialogKind := hdkPluginList;
  FDialog.Open(BuildPluginListDialog(HostPluginRows, ASelectedIndex), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.ShowPluginInfo(ARow: Integer);
var
  Info: TPluginInfo;
begin
  if not HostPluginInfo(ARow, Info) then
  begin
    ShowPluginList(ARow);
    Exit;
  end;
  FPluginInfoRow := ARow;
  FPluginInfoHelp := Info.HelpFile;
  FDialogKind := hdkPluginInfo;
  FDialog.Open(BuildPluginInfoDialog(Info.Name, PluginInfoLines(Info, 72),
    Info.HelpFile <> ''), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.ShowPluginPermissions(ARow: Integer);
var
  Name, Intro: string;
  Over, Perms, Texts: TArray<string>;
  OverOn: Boolean;
  Granted: TArray<Boolean>;
  I: Integer;
begin
  if not HostPluginPermissions(ARow, Name, Over, OverOn, Perms, Granted) then
  begin
    ShowPluginList(ARow);
    Exit;
  end;
  SetLength(Texts, Length(Perms));
  for I := 0 to High(Perms) do
    Texts[I] := PermissionDescription(Perms[I]);
  FPluginPermsRow := ARow;
  FPluginPermsCount := Length(Perms);
  FPluginPermsHasOverride := Length(Over) > 0;
  FDialogKind := hdkPluginPerms;
  if (Length(Over) > 0) or (Length(Perms) > 0) then
    Intro := T('ui.plugins.permsIntro', 'The plugin asks to be allowed to:')
  else
    Intro := T('ui.plugins.permsNone', 'The plugin asks for no permissions.');
  FDialog.Open(BuildPluginPermissionsDialog(Name, Intro,
    Format(T('ui.plugins.permsOverride', 'replace the built-in handlers: %s'),
      [string.Join(' ', Over)]),
    Length(Over) > 0, OverOn, Texts, Granted), DialogCommand);
  NotifyChanged;
end;

function TDualPanelWindow.HandlePluginPermsCommand(const AControlId: string): Boolean;
var
  Row, I: Integer;
  Granted: TArray<Boolean>;
  OverOn: Boolean;
begin
  Result := True;
  Row := FPluginPermsRow;
  if DialogCmdIsAccept(AControlId) then
  begin
    SetLength(Granted, FPluginPermsCount);
    for I := 0 to High(Granted) do
      Granted[I] := FDialog.GetCheckbox('perm_' + IntToStr(I));
    OverOn := FPluginPermsHasOverride and FDialog.GetCheckbox('perm_override');
    FDialog.Close;
    HostApplyPluginPermissions(Row, OverOn, Granted);
  end
  else
    FDialog.Close;
  ShowPluginList(Row);
end;

function TDualPanelWindow.HandlePluginInfoCommand(const AControlId: string): Boolean;
var
  Row: Integer;
  HelpFile: string;
begin
  Result := True;
  Row := FPluginInfoRow;
  HelpFile := FPluginInfoHelp;
  FDialog.Close;
  if (AControlId = 'help') and (HelpFile <> '') then
  begin
    // The help page opens in the viewer; the Plugins list is not brought back.
    RequestOpenViewer(PathToFileUri(HelpFile));
    Exit;
  end;
  ShowPluginList(Row);
end;

function TDualPanelWindow.HandlePluginListCommand(const AControlId: string): Boolean;
var
  Row, Delta: Integer;
begin
  Result := True;
  if (AControlId <> 'toggle') and (AControlId <> 'permissions') and
     (AControlId <> 'settings') and (AControlId <> 'info') and (AControlId <> 'up') and
     (AControlId <> 'down') then
  begin
    // OK applies the pending on/off choices; Cancel, Esc and the close box drop them.
    FDialog.Close;
    if DialogCmdIsAccept(AControlId) then
      HostPluginsCommit
    else
      HostPluginsCancel;
    NotifyChanged;
    Exit;
  end;
  Row := FDialog.GetListSelectedIndex('plugins');
  FDialog.Close;
  if (AControlId = 'up') or (AControlId = 'down') then
  begin
    // The selection follows the plugin to its new place.
    if AControlId = 'up' then
      Delta := -1
    else
      Delta := 1;
    if HostMovePlugin(Row, Delta) then
      Inc(Row, Delta);
    ShowPluginList(Row);
    Exit;
  end;
  if AControlId = 'info' then
  begin
    ShowPluginInfo(Row);
    Exit;
  end;
  if AControlId = 'settings' then
  begin
    // The plugin shows its own dialog and the list comes back when it is closed;
    // one without settings gets a message.
    FPluginListReturnRow := Row;
    if HostConfigurePlugin(Row) then
    begin
      if Assigned(FDialog) and FDialog.Visible then
        Exit;
      FPluginListReturnRow := -1;
    end
    else
    begin
      // A message dialog; closing it brings the list back (hdkHost branch).
      if not ShowHostDialog(BuildConfirmDialog(T('ui.plugins.noSettingsTitle', 'Plugin settings'),
           Format(T('ui.plugins.noSettings', 'The plugin %s has no settings.'),
             [HostPluginIdAt(Row)])), nil) then
      begin
        FPluginListReturnRow := -1;
        ShowPluginList(Row);
      end;
      Exit;
    end;
  end
  else if AControlId = 'permissions' then
  begin
    ShowPluginPermissions(Row);
    Exit;
  end
  else
    HostTogglePlugin(Row);
  // The list is rebuilt so the marks show the new state; the menu is rebuilt
  // too, since a plugin that left or arrived takes its items with it.
  ShowPluginList(Row);
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
  FThemeDlg.OpenPicker;
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

procedure TDualPanelWindow.OpenConsoleOptionsDialog;
begin
  FSettings.OpenConsoleOptions;
end;

procedure TDualPanelWindow.BeginSaveConsoleOutput;
begin
  if not Assigned(FOnSaveConsoleOutput) or not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkConsoleSave;
  FDialog.Open(BuildInputDialog(T('ui.console.saveTitle', 'Save console output'),
    T('ui.console.savePrompt', 'File:'),
    TPath.Combine(TPath.GetDocumentsPath, 'console-output.txt')), DialogCommand);
  NotifyChanged;
end;

function TDualPanelWindow.HandleConsoleSaveCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  Path, Err: string;
begin
  Result := True;
  Path := Trim(AFields.Name);
  if DialogCmdIsAccept(AControlId) and (Path <> '') and Assigned(FOnSaveConsoleOutput) then
  begin
    FDialog.Close;
    if FOnSaveConsoleOutput(Path, Err) then
      FToast.Show(T('ui.toast.consoleSaved', 'Console output saved: %s'), Path)
    else
      FToast.Show(T('ui.toast.consoleSaveFailed', 'Could not save the console output') +
        ': ' + Err, '', tkWarning);
    Exit;
  end;
  FDialog.Close;
end;

function TDualPanelWindow.SettingsFileDefaultPath: string;
var
  Dir: string;
begin
  Dir := PanelCommandCwd;
  if (Dir = '') or not TDirectory.Exists(Dir) then
    Dir := TPath.GetDocumentsPath;
  Result := TPath.Combine(Dir, 'mtn2-settings.zip');
end;

procedure TDualPanelWindow.BeginExportSettings;
begin
  if not Assigned(FOnExportSettings) or not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkSettingsExport;
  FDialog.Open(BuildSettingsFileDialog(T('ui.settings.exportTitle', 'Export settings'),
    T('ui.settings.exportPrompt', 'Write the settings to the file:'),
    SettingsFileDefaultPath), DialogCommand);
  NotifyChanged;
end;

procedure TDualPanelWindow.BeginImportSettings;
begin
  if not Assigned(FOnImportSettings) or not CanStartOperation then
    Exit;
  CloseTransientUiBeforeDialog;
  FDialogKind := hdkSettingsImport;
  FDialog.Open(BuildSettingsFileDialog(T('ui.settings.importTitle', 'Import settings'),
    T('ui.settings.importPrompt', 'Read the settings from the file:'),
    SettingsFileDefaultPath), DialogCommand);
  NotifyChanged;
end;

function TDualPanelWindow.HandleSettingsFileCommand(AKind: THostDialogKind;
  const AControlId: string; const AFields: TDialogCommandFields): Boolean;
var
  Path, Err: string;
  Done: Boolean;
begin
  Result := True;
  Path := Trim(AFields.Name);
  if not (DialogCmdIsAccept(AControlId) and (Path <> '')) then
  begin
    FDialog.Close;
    Exit;
  end;
  FDialog.Close;
  if AKind = hdkSettingsExport then
  begin
    if not Assigned(FOnExportSettings) then
      Exit;
    Done := FOnExportSettings(Path, Err);
    if Done then
      FToast.Show(T('ui.toast.settingsExported', 'Settings written: %s'), Path)
    else
      FToast.Show(T('ui.toast.settingsExportFailed', 'Could not export the settings') +
        ': ' + Err, '', tkWarning);
  end
  else
  begin
    if not Assigned(FOnImportSettings) then
      Exit;
    Done := FOnImportSettings(Path, Err);
    if Done then
      FToast.Show(T('ui.toast.settingsImported',
        'Settings imported. Restart MTN2 to apply them.'))
    else
      FToast.Show(T('ui.toast.settingsImportFailed', 'Could not import the settings') +
        ': ' + Err, '', tkWarning);
  end;
end;

procedure TDualPanelWindow.ClearConsoleBuffer;
begin
  if Assigned(FOnClearConsoleBuffer) then
    FOnClearConsoleBuffer(Self);
end;

procedure TDualPanelWindow.OpenMarkdownColorsDialog;
begin
  FSettings.OpenMarkdownColors;
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
  // No live progress UI for v1 - the walk is off-thread and the panel just
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

procedure TDualPanelWindow.HostRunUserMenuCommand(const ACommand: string;
  AReturnToPanels: Boolean);
begin
  // Like a typed command, minus clearing the command line: whatever the
  // user was typing there stays.
  SetCmdFocused(False);
  NotifyChanged;
  if Assigned(FOnRunCommand) then
    FOnRunCommand(ACommand, PanelCommandCwd);
  if AReturnToPanels and Assigned(FOnReturnWhenDone) then
    FOnReturnWhenDone(Self);
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
  if Ws.Kind = wkPanels then
    FToast.Show(T('ui.toast.refreshed', 'Panel refreshed'));
end;

function TDualPanelWindow.ListViewHeight: Integer;
begin
  // FListTop/Bottom stay 0,0 until LayoutPanels - treating that as ViewH=1 would
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
  // Tabbing into the panel currently showing a live Quick View exits it -
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
  TmpPending, TreeFocused: Boolean;
begin
  Ws := ActiveWorkspace;
  if not CanStartPanelLayoutChange(Ws) then
    Exit;

  TreeFocused := OverlayFolderTreeVisible;
  TmpPanel := Ws.State.LeftPanel;
  Ws.State.LeftPanel := Ws.State.RightPanel;
  Ws.State.RightPanel := TmpPanel;
  // ActiveSide stays on the same physical panel (FAR Ctrl+U); a focused
  // folder tree keeps the focus on its new side.
  if TreeFocused then
    Ws.State.ActiveSide := OppositeSide(Ws.State.ActiveSide);

  TmpPending := FWatchPending[psLeft];
  FWatchPending[psLeft] := FWatchPending[psRight];
  FWatchPending[psRight] := TmpPending;
  if FPendingSelectSide = psLeft then
    FPendingSelectSide := psRight
  else if FPendingSelectSide = psRight then
    FPendingSelectSide := psLeft;

  InvalidatePlainTotals;
  SaveActiveWorkspace(Ws);
  // The tree moves with its panel once the swap is saved.
  if Assigned(FFolderTreeCtrl) then
    FFolderTreeCtrl.SwapSide;
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
  // NavigateSideTo focuses the destination side - keep focus on the active panel.
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
  Redirect: string;
begin
  if AURI = '' then
    Exit;
  case DocumentProviders.TryOpen(AURI, AViewOnly, Redirect) of
    dokHandled:
      begin
        FileHistoryPush(AURI, not AViewOnly);
        Exit;
      end;
    // The redirect target is not offered to the providers again.
    dokRedirect:
      begin
        FileHistoryPush(AURI, not AViewOnly);
        OpenBuiltInDocument(Redirect, AViewOnly);
        Exit;
      end;
  end;
  OpenBuiltInDocument(AURI, AViewOnly);
end;

procedure TDualPanelWindow.OpenBuiltInDocument(const AURI: string; AViewOnly: Boolean);
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

function TDualPanelWindow.VisibleSurfaces: TArray<Integer>;
var
  H: Integer;
  B: TRectI;
begin
  Result := [];
  for H in SurfaceHandles do
    if SurfaceViewport(H, B) then
      Result := Result + [H];
end;

function TDualPanelWindow.SurfaceViewport(AHandle: Integer; out ABounds: TRectI): Boolean;
var
  Doc: TEditorWindow;
  Side: TPanelSide;
  PanelBounds: TRectI;
begin
  Result := False;
  ABounds := TRectI.Make(0, 0, -1, -1);
  if not FAlive or FConsoleMode or HelpVisible or (Assigned(FDialog) and FDialog.Visible) or
     (Assigned(FTopMenu) and FTopMenu.Active) then
    Exit;
  if SurfaceMode(AHandle) = cSurfaceModePanel then
  begin
    if (AHandle <> FSurfacePanelHandle) or not QuickViewVisible then
      Exit;
    Side := OppositeSide(ActiveWorkspace.State.ActiveSide);
    if PanelViewKind(Side) <> pvkQuickView then
      Exit;
    if Side = psLeft then
      PanelBounds := FLeftBounds
    else
      PanelBounds := FRightBounds;
    ABounds := QuickViewInteriorAbsBounds(PanelBounds, Area);
    Exit(ABounds.Right >= ABounds.Left);
  end;
  if ActiveWorkspace.Kind <> wkDocument then
    Exit;
  Doc := ActiveDocument;
  Result := Assigned(Doc) and (Doc.SurfaceHandle = AHandle) and Doc.SurfaceBounds(ABounds);
end;

procedure TDualPanelWindow.SyncSurfacePanel;
var
  H: Integer;
begin
  if FSurfacePanelHandle = 0 then
    Exit;
  if (PanelViewKind(psLeft) = pvkQuickView) or (PanelViewKind(psRight) = pvkQuickView) then
    Exit;
  // Quick View was switched off: the plugin hears it like a closed tab.
  H := FSurfacePanelHandle;
  FSurfacePanelHandle := 0;
  SurfaceTabClosed(H);
end;

function TDualPanelWindow.OpenSurfaceTab(AHandle: Integer): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Ed: TEditorWindow;
  Uri: string;
  Other: TPanelSide;
begin
  Result := False;
  if not FAlive then
    Exit;
  if SurfaceMode(AHandle) = cSurfaceModePanel then
  begin
    // Shown where Quick View shows a file: the panel opposite the active one.
    Ws := ActiveWorkspace;
    if (Ws.Kind <> wkPanels) or (FSurfacePanelHandle <> 0) then
      Exit;
    Other := OppositeSide(Ws.State.ActiveSide);
    if PanelViewKind(Other) <> pvkQuickView then
      ToggleQuickView;
    if PanelViewKind(Other) <> pvkQuickView then
      Exit;
    FSurfacePanelHandle := AHandle;
    SurfaceAttach(AHandle,
      procedure
      begin
        Invalidate;
      end,
      procedure
      begin
        if FSurfacePanelHandle = AHandle then
        begin
          FSurfacePanelHandle := 0;
          SurfaceTabClosed(AHandle);
          CloseQuickView;
        end;
      end);
    NotifyChanged;
    Exit(True);
  end;
  Uri := 'plugin-surface:' + IntToStr(AHandle);
  Ed := TEditorWindow.Create(Theme, FNextTabId);
  Ed.Embedded := True;
  Ed.OnContentChanged := DocumentContentChanged;
  Ed.OnCloseRequest := DocumentCloseRequest;
  Ed.OpenSurface(AHandle);

  Ws := TDualPanelTabManager.MakeEmbeddedWorkspaceTab(
    FNextTabId, TDualPanelTabManager.EmbeddedDocumentTitle(Ed.TabCaption, 'Picture'),
    wkDocument, ActiveWorkspace.Id);
  Inc(FNextTabId);
  Ws.DocURI := Uri;
  Ws.ViewOnly := True;

  FDocuments.AddOrSetValue(Ws.Id, Ed);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);
  SyncWindowTitle;
  NotifyChanged;
  Result := True;
end;

function TDualPanelWindow.PluginDocInfoJson: string;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  if (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) then
    Result := Doc.PluginDocInfoJson
  else
    Result := '';
end;

function TDualPanelWindow.PluginDocGetText(AWhat: Integer; out AText: string): Boolean;
var
  Doc: TEditorWindow;
begin
  AText := '';
  Doc := ActiveDocument;
  Result := (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) and
    Doc.PluginDocGetText(AWhat, AText);
end;

function TDualPanelWindow.PluginDocReplace(AWhat: Integer; const AText: string): Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  Result := (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) and
    Doc.PluginDocReplace(AWhat, AText);
end;

function TDualPanelWindow.PluginDocSetCursor(ARow, ACol: Integer): Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  Result := (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) and
    Doc.PluginDocSetCursor(ARow, ACol);
end;

function TDualPanelWindow.PluginPanelInfoJson: string;
var
  Ws: TDualPanelWorkspaceTab;
  Root, SideObj: TJSONObject;
  Sel: TJSONArray;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Idx: Integer;
  U: string;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit('');
  Root := TJSONObject.Create;
  try
    if Ws.State.ActiveSide = psLeft then
      Root.AddPair('active', 'left')
    else
      Root.AddPair('active', 'right');
    for Side := psLeft to psRight do
    begin
      if Side = psLeft then
        Panel := Ws.State.LeftPanel
      else
        Panel := Ws.State.RightPanel;
      Tab := ActiveTab(Panel);
      SideObj := TJSONObject.Create;
      SideObj.AddPair('uri', Tab.CurrentURI);
      Rows := RowsForSide(Side);
      Idx := Tab.CursorIndex;
      if (Idx >= 0) and (Idx <= High(Rows)) and not Rows[Idx].IsParent then
      begin
        SideObj.AddPair('cursor', Rows[Idx].URI);
        SideObj.AddPair('cursorIsDirectory', TJSONBool.Create(Rows[Idx].IsDirectory));
      end;
      Sel := TJSONArray.Create;
      for U in Tab.SelectedURIs do
        Sel.Add(U);
      SideObj.AddPair('selected', Sel);
      if Side = psLeft then
        Root.AddPair('left', SideObj)
      else
        Root.AddPair('right', SideObj);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TDualPanelWindow.PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2: Integer): Boolean;
var
  Doc: TEditorWindow;
begin
  Doc := ActiveDocument;
  Result := (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) and
    Doc.PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2);
end;

function TDualPanelWindow.PluginDocLine(AIndex: Integer; out AText: string): Boolean;
var
  Doc: TEditorWindow;
begin
  AText := '';
  Doc := ActiveDocument;
  Result := (ActiveWorkspace.Kind = wkDocument) and Assigned(Doc) and
    Doc.PluginDocLine(AIndex, AText);
end;

function TDualPanelWindow.PluginPanelListJson(ASide: Integer): string;
const
  cMaxRows = 10000;
var
  Ws: TDualPanelWorkspaceTab;
  Root, RowObj: TJSONObject;
  RowsArr: TJSONArray;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  I, N: Integer;
begin
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit('');
  case ASide of
    0: Side := psLeft;
    1: Side := psRight;
  else
    Side := Ws.State.ActiveSide;
  end;
  if Side = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Side);
  Root := TJSONObject.Create;
  try
    Root.AddPair('uri', Tab.CurrentURI);
    RowsArr := TJSONArray.Create;
    N := 0;
    for I := 0 to High(Rows) do
    begin
      if Rows[I].IsParent then
        Continue;
      if N >= cMaxRows then
      begin
        Root.AddPair('truncated', TJSONBool.Create(True));
        Break;
      end;
      RowObj := TJSONObject.Create;
      RowObj.AddPair('uri', Rows[I].URI);
      RowObj.AddPair('name', Rows[I].Text);
      RowObj.AddPair('dir', TJSONBool.Create(Rows[I].IsDirectory));
      RowObj.AddPair('size', TJSONNumber.Create(Rows[I].Size));
      RowsArr.Add(RowObj);
      // The cursor is reported as an index into this list (the ".." row is not in it).
      if I = Tab.CursorIndex then
        Root.AddPair('cursor', TJSONNumber.Create(N));
      Inc(N);
    end;
    Root.AddPair('rows', RowsArr);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TDualPanelWindow.PluginPanelSetCursor(ASide: Integer; const AURI: string): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  I, Found: Integer;
  Parent: string;
begin
  Result := False;
  Ws := ActiveWorkspace;
  if (Ws.Kind <> wkPanels) or (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  case ASide of
    0: Side := psLeft;
    1: Side := psRight;
  else
    Side := Ws.State.ActiveSide;
  end;
  Rows := RowsForSide(Side);
  Found := -1;
  for I := 0 to High(Rows) do
    if not Rows[I].IsParent and SameVfsUri(Rows[I].URI, AURI) then
    begin
      Found := I;
      Break;
    end;
  if Found < 0 then
  begin
    // A row of another folder: go there, the cursor follows when it is listed.
    Parent := ParentVfsUri(AURI);
    if Parent = '' then
      Exit;
    FPendingSelectName := VfsUriTitle(AURI);
    FPendingSelectSide := Side;
    NavigateSideTo(Side, Parent, True);
    Exit(True);
  end;
  if Side = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Tab.CursorIndex := Found;
  SetActiveTab(Panel, Tab);
  if Side = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  ClampCursorSide(Side);
  NotifyChanged;
  Result := True;
end;

function TDualPanelWindow.PluginPanelSelect(ASide, AMode: Integer; const AArg: string): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
begin
  Ws := ActiveWorkspace;
  Result := (Ws.Kind = wkPanels) and not (Assigned(FDialog) and FDialog.Visible);
  if not Result then
    Exit;
  case ASide of
    0: Side := psLeft;
    1: Side := psRight;
  else
    Side := Ws.State.ActiveSide;
  end;
  if Side = psLeft then
    Panel := Ws.State.LeftPanel
  else
    Panel := Ws.State.RightPanel;
  Tab := ActiveTab(Panel);
  Rows := RowsForSide(Side);
  case AMode of
    0: TabSelectByMask(Tab, Rows, AArg, False);
    1: TabUnselectByMask(Tab, Rows, AArg, False);
    2: TabClearSelection(Tab);
    3: TabSetSelected(Tab, AArg, True);
    4: TabSetSelected(Tab, AArg, False);
  else
    Exit(False);
  end;
  SetActiveTab(Panel, Tab);
  if Side = psLeft then
    Ws.State.LeftPanel := Panel
  else
    Ws.State.RightPanel := Panel;
  SaveActiveWorkspace(Ws);
  NotifyChanged;
end;

procedure TDualPanelWindow.PublishPanelEvents;
var
  Ws: TDualPanelWorkspaceTab;
  Side: TPanelSide;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  Obj: TJSONObject;
  Cur: string;
  DirChanged: Boolean;
begin
  if not PluginHasSubscribers then
    Exit;
  Ws := ActiveWorkspace;
  if Ws.Kind <> wkPanels then
    Exit;
  for Side := psLeft to psRight do
  begin
    if Side = psLeft then
      Panel := Ws.State.LeftPanel
    else
      Panel := Ws.State.RightPanel;
    Tab := ActiveTab(Panel);
    Rows := RowsForSide(Side);
    // A folder that is still being listed has no cursor row to report yet.
    if Length(Rows) = 0 then
      Continue;
    Cur := '';
    if (Tab.CursorIndex >= 0) and (Tab.CursorIndex <= High(Rows)) and
       not Rows[Tab.CursorIndex].IsParent then
      Cur := Rows[Tab.CursorIndex].URI;
    DirChanged := Tab.CurrentURI <> FPanelEventUri[Side];
    if not DirChanged and (Cur = FPanelEventCursor[Side]) then
      Continue;
    FPanelEventUri[Side] := Tab.CurrentURI;
    FPanelEventCursor[Side] := Cur;
    Obj := TJSONObject.Create;
    try
      if Side = psLeft then
        Obj.AddPair('side', 'left')
      else
        Obj.AddPair('side', 'right');
      Obj.AddPair('uri', Tab.CurrentURI);
      Obj.AddPair('cursor', Cur);
      if DirChanged then
        PluginPublishEvent('panel.dir', Obj.ToJSON)
      else
        PluginPublishEvent('panel.cursor', Obj.ToJSON);
    finally
      Obj.Free;
    end;
  end;
end;

function TDualPanelWindow.PluginPanelGoto(ASide: Integer; const AURI: string): Boolean;
var
  Side, Previous: TPanelSide;
begin
  Result := (ActiveWorkspace.Kind = wkPanels) and not (Assigned(FDialog) and FDialog.Visible);
  if not Result then
    Exit;
  Previous := ActiveWorkspace.State.ActiveSide;
  case ASide of
    0: Side := psLeft;
    1: Side := psRight;
  else
    Side := Previous;
  end;
  NavigateSideTo(Side, AURI, True);
  // Showing a folder in the other panel does not move the focus there.
  if Side <> Previous then
    ActivateSide(Previous);
  NotifyChanged;
end;

procedure TDualPanelWindow.PluginPanelRefresh;
begin
  if ActiveWorkspace.Kind = wkPanels then
    RefreshActive;
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

procedure TDualPanelWindow.OpenTerminal(const AProfileId, ACwd: string;
  const ACommand: string);
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

  // Register the tab/dictionary entry before Start: unlike Ed.Open, PTY
  // Start can fail synchronously and fire ProcessExited -> DoCloseWorkspace
  // -> OnCloseRequest -> TerminalCloseRequest before control returns here,
  // and that handler needs to find this tab to clean it up correctly.
  FTerminals.AddOrSetValue(Ws.Id, Term);
  TDualPanelTabManager.InsertWorkspaceAfterActive(
    FState.WorkspaceTabs, FState.ActiveWorkspaceIndex, Ws);

  Term.Start(AProfileId, ACwd);
  // Start() may fail synchronously and already have torn the tab down via
  // TerminalCloseRequest (which picks its own fallback active tab) - don't
  // touch ActiveWorkspaceIndex again if that happened.
  if not FTerminals.ContainsKey(Ws.Id) then
    Exit;
  // The shell buffers what is typed before its first prompt.
  if ACommand <> '' then
    Term.SendCommand(ACommand);

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
    SelectWorkspace(Next);
end;

procedure TDualPanelWindow.PrevWorkspace;
var
  Prev: Integer;
begin
  Prev := TDualPanelTabManager.PrevWorkspaceIndex(
    FState.ActiveWorkspaceIndex, Length(FState.WorkspaceTabs));
  if Prev <> FState.ActiveWorkspaceIndex then
    SelectWorkspace(Prev);
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

procedure TDualPanelWindow.CycleTab(AReverse: Boolean);
begin
  // Ctrl+Tab: the tabs of the active panel; on a document or terminal
  // workspace, which has no panel tabs, the workspaces.
  if ActiveWorkspace.Kind = wkPanels then
  begin
    if AReverse then
      PrevPanelTab
    else
      NextPanelTab;
  end
  else if AReverse then
    PrevWorkspace
  else
    NextWorkspace;
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
  // Creating a tab on a side also makes that side active - matches what
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

function TDualPanelWindow.HitPanelPlusAtCol(ASide: TPanelSide;
  const ABounds: TRectI; ACol: Integer): Boolean;
var
  Ws: TDualPanelWorkspaceTab;
begin
  Ws := ActiveWorkspace;
  if ASide = psLeft then
    Result := uDualPanelTabs.HitPanelPlusAtCol(Ws.State.LeftPanel, ABounds, ACol)
  else
    Result := uDualPanelTabs.HitPanelPlusAtCol(Ws.State.RightPanel, ABounds, ACol);
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
  if HitPanelPlusAtCol(ASide, ABounds, ACol) then
  begin
    NewPanelTabOnSide(ASide);
    Exit(True);
  end;
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
  // Dual Panel Tabs directly under the menu (the top row without it).
  Theme.DrawTabBar(Buffer, TRectI.Make(0, TabBarRow, AWidth - 1, TabBarRow), Names,
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
      PutGridText(Buffer, X, TabBarRow, Cap, TabFg, TabBg);
    if ShowClose then
    begin
      CloseCol := TabCaptionCloseCol(X, Cap, True, False);
      PaintTabCloseMark(Buffer, CloseCol, TabBarRow,
        ContrastingGlyphFg(TabBg, CloseFg, TabFg), TabBg);
    end;
    Inc(X, Length(Cap) + 1);
  end;
  DrawTabBarChrome(AWidth);
end;

function TDualPanelWindow.ButtonsInTabRow: Boolean;
begin
  Result := (not GShowTitleBar) and (not GShowMenuBar);
end;

function TDualPanelWindow.ChromeDrawn: Boolean;
begin
  Result := ClassifyDrawContent(Area.Width, Area.Height, FConsoleMode,
    ActiveWorkspace.Kind) in [dckPanels, dckDocument, dckTerminal];
end;

function TDualPanelWindow.TabBarChrome(AWidth: Integer): TTabBarChrome;
var
  Jobs: TArray<TPanelJobState>;
begin
  Jobs := nil;
  if Assigned(FJobs) then
    Jobs := FJobs.States;
  Result := LayoutTabBarChrome(WorkspaceTabsEndCol(FState.WorkspaceTabs), AWidth,
    ButtonsInTabRow, Jobs);
end;

procedure TDualPanelWindow.DrawTabBarChrome(AWidth: Integer);
var
  Chrome: TTabBarChrome;
  Chip: TJobChip;
  Fg, Bg, ChipFg, ChipBg, ActFg, ActBg: TAlphaColor;
  TitleW: Integer;
begin
  Chrome := TabBarChrome(AWidth);
  ResolveChrome(pcpWorkspaceTabIdle, False, Fg, Bg);
  ResolveChrome(pcpWorkspaceTabActive, True, ActFg, ActBg);

  if Chrome.PlusLeft >= 0 then
  begin
    // A filled block, like the chips: the active-tab colours, swapped under the mouse.
    if FChromeHover = 4 then
      PutGridText(Buffer, Chrome.PlusLeft, TabBarRow, cPlusCaption, ActBg, ActFg)
    else
      PutGridText(Buffer, Chrome.PlusLeft, TabBarRow, cPlusCaption, ActFg, ActBg);
  end;

  TitleW := Chrome.FreeRight - Chrome.FreeLeft;
  if (not GShowTitleBar) and (TitleW >= cMinTitleWidth) then
    PutGridText(Buffer, Chrome.FreeLeft, TabBarRow,
      ComposeTitle(FWindowTitleParts, TitleW),
      Fg, Bg);

  if Chrome.Strip.ListWidth = 0 then
    Exit;
  // Chips are filled blocks against the idle bar: the active-tab colours, or
  // black on yellow for a question and white on red for a failure.
  for Chip in Chrome.Strip.Chips do
  begin
    case Chip.Tone of
      jctError:
        begin
          ChipFg := cJobErrorFg;
          ChipBg := cJobErrorBg;
        end;
      jctAsk:
        begin
          ChipFg := cJobAskFg;
          ChipBg := cJobAskBg;
        end;
    else
      ChipFg := ActFg;
      ChipBg := ActBg;
    end;
    PutGridText(Buffer, Chip.Left, TabBarRow, Chip.Caption, ChipFg, ChipBg);
  end;
  PutGridText(Buffer, Chrome.Strip.ListLeft, TabBarRow, Chrome.Strip.ListCaption,
    Fg, Bg);
end;

function TDualPanelWindow.ConsoleBarShown: Boolean;
begin
  Result := (not GShowTitleBar) and (ClassifyDrawContent(Area.Width, Area.Height,
    FConsoleMode, ActiveWorkspace.Kind) = dckConsole);
end;

procedure TDualPanelWindow.DrawWindowButtons(const AGrid: TTerminalGrid;
  AWidth: Integer; AOnMenuBar: Boolean);
var
  Left: Integer;
  Button: TWindowButton;
  Fg, Bg, BtnFg, BtnBg: TAlphaColor;
begin
  Left := WindowButtonsLeft(AWidth);
  if GShowTitleBar or (Left < 0) then
    Exit;
  // Filled blocks against the bar they sit on: the menu bar's colours
  // inverted (also while a hidden menu is open), or the active-tab colours
  // on the tab bar. Under the mouse they swap, and the close button turns red.
  if AOnMenuBar then
    ResolveChrome(pcpPanelTabActive, True, Bg, Fg)
  else
    ResolveChrome(pcpWorkspaceTabActive, True, Fg, Bg);
  FillGridRect(AGrid, Left, 0, AWidth - 1, 0, ' ', Fg, Bg);
  for Button := Low(TWindowButton) to High(TWindowButton) do
  begin
    BtnFg := Fg;
    BtnBg := Bg;
    if FChromeHover = Ord(Button) + 1 then
      if Button = wbClose then
      begin
        BtnFg := cJobErrorFg;
        BtnBg := cJobErrorBg;
      end
      else
      begin
        BtnFg := Bg;
        BtnBg := Fg;
      end;
    PutGridText(AGrid, Left + Ord(Button) * 3, 0,
      WindowButtonCaption(Button, FWindowMaximized), BtnFg, BtnBg);
  end;
end;

procedure TDualPanelWindow.PaintConsoleWindowButtons(const AGrid: TTerminalGrid;
  AWidth: Integer);
begin
  if ConsoleBarShown then
    DrawWindowButtons(AGrid, AWidth, False);
end;

function TDualPanelWindow.HandleConsoleFrameClick(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := ConsoleBarShown and ClickChrome(ALocalCol, ALocalRow);
end;

function TDualPanelWindow.FunctionBarClickKey(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState; out AKey: Word; out AKeyChar: Char;
  out AKeyShift: TShiftState): Boolean;
var
  Items, Letters: TArray<string>;
  Hit: TFunctionBarHit;
begin
  AKey := 0;
  AKeyChar := #0;
  AKeyShift := [];
  Result := False;
  if ALocalRow <> KeyBarRow(Area.Height) then
    Exit;
  FunctionBarGetItems(ChromeContext, AShift, Items, Letters);
  Hit := FunctionBarHitTest(ALocalCol, Area.Width, Items, Letters, AShift,
    Assigned(Theme));
  Result := FunctionBarHitToInput(Hit, AShift, AKey, AKeyChar, AKeyShift);
end;

function TDualPanelWindow.ReleaseChromeButton(ALocalCol, ALocalRow: Integer;
  out AButton: TWindowButton; out AActs: Boolean): Boolean;
var
  Pressed: Integer;
begin
  Pressed := FChromePressed;
  FChromePressed := 0;
  AButton := wbMinimize;
  AActs := False;
  Result := Pressed <> 0;
  if not Result then
    Exit;
  AButton := TWindowButton(Pressed - 1);
  AActs := ChromeHoverAt(ALocalCol, ALocalRow) = Pressed;
  // Drawn released until the mouse moves again.
  FChromeHover := 0;
end;

function TDualPanelWindow.ToggleTopMenuFromTitle: Boolean;
begin
  Result := False;
  if GShowTitleBar or not ChromeDrawn or not Assigned(FTopMenu) then
    Exit;
  if Assigned(FDialog) and FDialog.Visible then
    Exit;
  FTopMenu.ToggleMenu;
  NotifyChanged;
  Result := True;
end;

function TDualPanelWindow.ChromeHoverAt(ALocalCol, ALocalRow: Integer): Integer;
var
  Button: TWindowButton;
begin
  Result := 0;
  if (not GShowTitleBar) and (ALocalRow = 0) and (ChromeDrawn or ConsoleBarShown) and
     HitWindowButton(Area.Width, ALocalCol, Button) then
    Exit(Ord(Button) + 1);
  if ChromeDrawn and (ALocalRow = TabBarRow) and
     HitPlusButton(TabBarChrome(Area.Width), ALocalCol) then
    Result := 4;
end;

function TDualPanelWindow.UpdateChromeHover(ALocalCol, ALocalRow: Integer): Boolean;
var
  Hover: Integer;
begin
  Hover := ChromeHoverAt(ALocalCol, ALocalRow);
  Result := Hover <> FChromeHover;
  FChromeHover := Hover;
end;

function TDualPanelWindow.IsWindowDragZone(ALocalCol, ALocalRow: Integer): Boolean;
var
  MenuEnd: Integer;
begin
  Result := False;
  if GShowTitleBar then
    Exit;
  if ConsoleBarShown then
    Exit((ALocalRow = 0) and InMenuBarFreeZone(0, Area.Width, ALocalCol));
  if not ChromeDrawn then
    Exit;
  // A hidden menu bar opened with F9 covers the top row, which is the tab
  // bar row then: the menu titles must get the clicks there.
  if (ALocalRow = 0) and (GShowMenuBar or (Assigned(FTopMenu) and FTopMenu.Active)) then
  begin
    MenuEnd := 0;
    if Assigned(FTopMenu) then
      MenuEnd := FTopMenu.LabelsEndCol;
    Exit(InMenuBarFreeZone(MenuEnd, Area.Width, ALocalCol));
  end;
  if ALocalRow = TabBarRow then
    Result := InTabBarFreeZone(TabBarChrome(Area.Width), ALocalCol);
end;

function TDualPanelWindow.ClickJobStrip(ACol: Integer): Boolean;
var
  JobId: Integer;
begin
  Result := True;
  case HitJobStrip(TabBarChrome(Area.Width).Strip, ACol, JobId) of
    jshChip:
      begin
        FJobs.RestoreJobById(JobId);
        NotifyChanged;
      end;
    jshList:
      OpenJobList;
  else
    Result := False;
  end;
end;

function TDualPanelWindow.ClickChrome(ALocalCol, ALocalRow: Integer): Boolean;
var
  Button: TWindowButton;
begin
  Result := False;
  if (not GShowTitleBar) and (ALocalRow = 0) and (ChromeDrawn or ConsoleBarShown) and
     HitWindowButton(Area.Width, ALocalCol, Button) then
  begin
    // A button counts as pressed only when the mouse is released over it.
    FChromePressed := Ord(Button) + 1;
    Exit(True);
  end;
  if ChromeDrawn and (ALocalRow = TabBarRow) and
     HitPlusButton(TabBarChrome(Area.Width), ALocalCol) then
  begin
    NewWorkspace;
    Result := True;
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
var
  BarWidth: Integer;
begin
  // A hidden menu bar shows over the top row while the menu is open (F9).
  if not GShowMenuBar and not (Assigned(FTopMenu) and FTopMenu.Active) then
    Exit;
  // The window buttons own the right end of the row.
  BarWidth := AWidth;
  if (not GShowTitleBar) and (WindowButtonsLeft(AWidth) >= 0) then
    BarWidth := WindowButtonsLeft(AWidth);
  if Assigned(FTopMenu) then
    FTopMenu.DrawTopBar(Buffer, BarWidth)
  else
    FillGridRect(Buffer, 0, 0, BarWidth - 1, 0, ' ', cMenuFg, cMenuBg);
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

procedure TDualPanelWindow.DrawSurfacePanel(const ABounds: TRectI; ABodyBg: TAlphaColor);
var
  W, H: Integer;
  Gen: Cardinal;
  Pixels: PByte;
  AbsBounds: TRectI;
  Uri: string;
begin
  SurfaceSeen(FSurfacePanelHandle);
  if SurfaceIsNative(FSurfacePanelHandle) then
    Exit;
  if not SurfaceFrame(FSurfacePanelHandle, W, H, Gen, Pixels) then
    Exit;
  AbsBounds := QuickViewInteriorAbsBounds(ABounds, Area);
  Uri := 'plugin-surface:' + IntToStr(FSurfacePanelHandle);
  if (OverlayCurrentURI <> Uri) or (Gen <> FSurfacePanelGen) then
  begin
    SetOverlayPixels(Uri, W, H, Pixels, AbsBounds, AbsBounds);
    FSurfacePanelGen := Gen;
  end
  else
    UpdateOverlayBounds(AbsBounds);
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

  // A plugin shows its own picture here instead of the file under the cursor.
  if (FSurfacePanelHandle <> 0) and SurfaceExists(FSurfacePanelHandle) then
  begin
    DrawSurfacePanel(ABounds, ABodyBg);
    Exit;
  end;

  // The active side always drives what's previewed, regardless of which
  // side is physically drawing this panel - only reached when ASide isn't
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

  // Interior only (Left+1/Right-1/Top+1/Bottom-1) - same inset as the
  // FillGridRect above - so the image doesn't paint over the frame
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
  // Quick View (NC/NDN/FAR/TC convention): only the
  // currently non-active side may show it. If ASide is somehow also the
  // active side (e.g. a menu action force-focused it - see SwitchSide's
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
  SelFg, SelBg: TAlphaColor;
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
  Snap.FooterFg := AFrame;
  if Length(Tab.SelectedURIs) > 0 then
  begin
    Rows := RowsForSide(ASide);
    PanelSelectionTotals(Tab, Rows, Bytes, Files, Folders);
    Snap.Footer := FormatPanelTotalsFooter(True, Bytes, Files, Folders,
      ABounds.Width - 2);
    // "Selected: ..." takes the marked-file foreground so the totals read
    // as belonging to the highlighted rows; the background stays the rule's.
    if Assigned(Theme) then
      Theme.ResolveFileRowColors(False, False, False, '', True, False, AActive,
        SelFg, SelBg)
    else
      SelFg := cSelectedFg;
    Snap.FooterFg := SelFg;
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
  S.FolderTreeVisible := OverlayFolderTreeVisible;
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
  // Themed F-key bar colours - DrawFunctionBar already forwards to
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
  Path, SelText, CursorText, Desc: string;
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
  if (not HasSel) and HasCursor and (CursorText <> '') then
  begin
    Desc := DescriptionOf(Tab.CurrentURI, ExcludeTrailingPathDelimiter(CursorText));
    if Desc <> '' then
      Snap.ItemText := Snap.ItemText + ' - ' + TruncateStatusItem(Desc, 40);
  end;
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
  DestURI, Reason, ArchPath, Probe: string;
  Panel: TPanelState;
  Tab: TTab;
  Rows: TPanelRows;
  I: Integer;
begin
  if not CanBeginAnotherJob then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;

  Sources := CollectActiveSources;
  if Length(Sources) = 0 then
    Exit;

  // Copying out of an archive reads its encrypted files: password first.
  if (AKind in [pjkCopy, pjkMove]) and
     FindLockedArchiveFile(Sources, ArchPath, Probe, True) then
  begin
    RunWithArchivePassword(Sources,
      procedure
      begin
        BeginJob(AKind, ADeleteToRecycleBin);
      end, True);
    Exit;
  end;
  // Encrypted ZIP entries are read through the 7z backend, which decrypts.
  if (AKind in [pjkCopy, pjkMove]) and GetActiveRowContext(Ws, Panel, Tab, Rows) and
     ZipEncryptedProbe(Tab.CurrentURI, Sources, ArchPath, Probe) then
    for I := 0 to High(Sources) do
      if ZipEntryToSevenZipUri(Sources[I]) <> '' then
        Sources[I] := ZipEntryToSevenZipUri(Sources[I]);

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

procedure TDualPanelWindow.BeginDeleteCursor;
var
  Name, Uri, TargetUri: string;
  IsParent: Boolean;
begin
  if not CanBeginAnotherJob then
    Exit;
  if Assigned(FDrivePopupCtrl) and FDrivePopupCtrl.Visible then
    CloseDrivePopup;
  // Workspace panels keep their own "unlink selected" semantics.
  if ActivePanelIsWorkspace then
  begin
    BeginJob(pjkDelete, True);
    Exit;
  end;
  if (not HostTryGetCursorItem(Name, Uri, TargetUri, IsParent)) or IsParent or (Uri = '') then
    Exit;
  FJobs.BeginJob([Uri], '', pjkDelete, True);
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
  Doc := ActiveDocument;
  // A plugin picture in full screen covers the menu, the tabs and the key bar too.
  if Assigned(Doc) and Doc.IsSurfaceFullscreen then
  begin
    Doc.PaintEmbedded(Buffer, 0, 0, W, H, Area.Left, Area.Top);
    Exit;
  end;
  DrawWorkspaceTabBar(W);
  if Assigned(Doc) then
  begin
    DocH := EmbeddedDocumentPaintHeight(H);
    if CanPaintEmbeddedContent(DocH) then
      Doc.PaintEmbedded(Buffer, 0, ContentTopRow, W, DocH, Area.Left,
        Area.Top + ContentTopRow);
  end;
  DrawMenuBar(W);
end;

procedure TDualPanelWindow.DrawTerminalContent(W, H: Integer);
var
  Term: TTerminalWorkspaceWindow;
  DocH: Integer;
begin
  LayoutPanels(W, H);
  SyncPanelScrollAfterLayout;
  DrawWorkspaceTabBar(W);
  Term := ActiveTerminal;
  if Assigned(Term) then
  begin
    DocH := EmbeddedTerminalPaintHeight(H);
    if CanPaintEmbeddedContent(DocH) then
    begin
      Term.Area := TRectI.Make(0, ContentTopRow, W - 1, ContentTopRow + DocH - 1);
      Term.IsFocused := True;
      Term.Paint(Buffer);
    end;
  end;
  DrawBottomChrome(W, H);
  DrawMenuBar(W);
end;

procedure TDualPanelWindow.DrawPanelsContent(W, H: Integer);
var
  Ws: TDualPanelWorkspaceTab;
begin
  LayoutPanels(W, H);
  SyncPanelScrollAfterLayout;
  DrawWorkspaceTabBar(W);
  Ws := ActiveWorkspace;
  if Ws.State.LeftVisible then
    DrawPanel(FLeftBounds, Ws.State.LeftPanel, psLeft,
      Ws.State.ActiveSide = psLeft);
  if Ws.State.RightVisible then
    DrawPanel(FRightBounds, Ws.State.RightPanel, psRight,
      Ws.State.ActiveSide = psRight);
  DrawCommandLine(CmdLineRow(H), W);
  DrawBottomChrome(W, H);
  DrawMenuBar(W);
end;

procedure TDualPanelWindow.DrawBottomChrome(W, H: Integer);
begin
  if GShowKeyBar then
    DrawFunctionKeys(KeyBarRow(H), W);
  if GShowStatusLine then
    DrawAppStatusLine(StatusLineRow(H), W);
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
      DrawBottomChrome(W, H);
    dckDocument:
      DrawDocumentContent(W, H);
    dckTerminal:
      DrawTerminalContent(W, H);
  else
    DrawPanelsContent(W, H);
  end;
  if Kind in [dckDocument, dckTerminal, dckPanels] then
    DrawWindowButtons(Buffer, W, GShowMenuBar or (Assigned(FTopMenu) and FTopMenu.Active));
  // Submenu / dialogs sit on top of panels, Viewer/Editor, and Terminal:
  // painted after PaintEmbedded / Term.Paint, or F9 dropdowns (including
  // Edit) would open in state but be painted over.
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
    if HelpVisible then
      FHelp.Paint(Buffer, W, H, Area.Left, Area.Top);
    // Last and only over a screen without a dialog / Help: a notice must
    // not cover the buttons of whatever the user is answering.
    if Assigned(FToast) and not Snap.DialogVisible and not HelpVisible then
      FToast.Draw(Buffer, Theme, W, H);
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
  // Alt Quick Search lives only while Alt is held - clear needle on release.
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

function TDualPanelWindow.ProgramCapturesKeys: Boolean;
var
  Term: TTerminalWorkspaceWindow;
begin
  Result := False;
  if (Assigned(FDialog) and FDialog.Visible) or HelpVisible then
    Exit;
  if ActiveWorkspace.Kind = wkTerminal then
  begin
    Term := TerminalForWorkspace(FState.ActiveWorkspaceIndex);
    Result := Assigned(Term) and Term.KeysToProgram;
  end
  else if FConsoleMode then
    Result := Assigned(FOnQueryConsoleKeyCapture) and FOnQueryConsoleKeyCapture();
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
  Chain: TArray<TKeymapContext>;
  GlobalAct: TKeymapAction;
  ProgramKeys: Boolean;
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

  // Global keymap actions (uKeymap kcGlobal: F1, F9, Ctrl+Tab, Ctrl+O,
  // Alt+X, ...) work in every workspace, so they are looked up before the
  // document / terminal early-exit below -- but along the active window's
  // own contexts first: a key the document binds (F10, Esc) stays its own.
  case ActiveWorkspace.Kind of
    wkDocument:
      begin
        Doc := DocumentForWorkspace(FState.ActiveWorkspaceIndex);
        if Doc <> nil then
          Chain := Doc.KeymapChain
        else
          Chain := [kcDocument];
      end;
    wkTerminal:
      Chain := [kcTerminal, kcShell];
  else
    if FConsoleMode then
      Chain := [kcConsole, kcShell]
    else
      Chain := [kcPanels];
  end;
  GlobalAct := GlobalKeymapAction(ActiveKeymap, Chain, AKey, AKeyChar, AShift, DialogVis);
  // A console in program-keys mode: the host keeps only the keys that leave
  // the console; its menu, help and the rest of the global keys go to the
  // program (an open top menu still takes its keys).
  ProgramKeys := ProgramCapturesKeys and not (Assigned(FTopMenu) and FTopMenu.Active);
  if ProgramKeys and not IsKeyboardCaptureExitAction(GlobalAct) then
    GlobalAct := kaNone;

  // Top menu: its key (F9) opens and closes the bar, so does an Alt
  // release; an open bar takes every key, and Alt+letter hotkeys that match
  // none of its items fall through to Quick Search. Same offer on
  // Viewer/Editor tabs as on panels: a row 0 click reaches the menu via
  // DispatchClickOverlays. Not while a modal dialog is open, or F9 would win
  // over dialog bindings (hdkColorCodingEdit's "pick a color").
  if Assigned(FTopMenu) and not ProgramKeys and
     ShouldOfferTopMenu(ActiveWorkspace.Kind, DialogVis) then
  begin
    if FTopMenu.Active and (MatchActiveActionIn([kcGlobal],
      KeymapLookupKey(AKey, AKeyChar), AShift) = kaTopMenu) then
    begin
      FTopMenu.DeactivateMenu;
      AKey := 0;
      AKeyChar := #0;
      Invalidate;
      Exit(True);
    end;
    // Opening: load plugins first so their items are already in the menu;
    // any other key must not pay that cost.
    if not FTopMenu.Active and (GlobalAct = kaTopMenu) then
    begin
      HostEnsureAllPlugins;
      FTopMenu.ActivateMenu(FTopMenu.PanelCategory, True);
      AKey := 0;
      AKeyChar := #0;
      Invalidate;
      Exit(True);
    end;
    if not FTopMenu.Active and (ssAlt in AShift) and (AKey = 0) and (AKeyChar = #0) then
      HostEnsureAllPlugins;
    if FTopMenu.HandleInput(AKey, AShift, AKeyChar) then
    begin
      Invalidate;
      Exit(True);
    end;
  end;

  if InterceptKeymapAction(GlobalAct, 'key') then
  begin
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if DispatchGlobalAction(FKeymapHost, GlobalAct, AKey, AKeyChar) then
    Exit;

  // Embedded Viewer/Editor: document input (and its dialogs) before Dual Panel
  // host dialogs - matches HandleClick order so Enter reaches Editor Code page.
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

  // Alt+F1/F2 drive list is included below - before Esc>Console so Esc
  // closes the popup - via the same FInputOverlays table as the dialog/
  // search/job/menu overlays above it, in that priority order.
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
  Snap.CmdFocused := CmdFocused;
  Snap.ViewH := ViewH;
  Snap.Cols := Cols;
  Snap.PageSize := PageSize;
  if ActiveWorkspace.State.ActiveSide = psLeft then
    Snap.Brief := ActiveWorkspace.State.LeftPanel.ColumnMode = pcmBrief
  else
    Snap.Brief := ActiveWorkspace.State.RightPanel.ColumnMode = pcmBrief;
  // Panel-only chords below; a focused command line takes every key
  // (DispatchPanelFreeInput).
  if ActivePanelIsTmp and not Snap.CmdFocused then
  begin
    if TKeyChord.Make(AKey, AKeyChar, AShift).Matches(vkPrior, [ssCtrl]) then
    begin
      TmpGotoCursorFile;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([ssAlt, ssShift]) then
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
  if TKeyChord.Make(AKey, AKeyChar, AShift).Matches(vkReturn, [ssCtrl, ssAlt]) and not Snap.CmdFocused then
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
  end
  else if HitPanelListEmptyArea(ListBounds, Panel.ColumnMode, Tab.ScrollOffset,
    ALocalCol, ALocalRow, Length(Rows)) then
  begin
    // The empty space after the last item puts the cursor on that item. It
    // is not a hit on a row, so a double-click there opens nothing.
    Tab.CursorIndex := High(Rows);
    EnsureCursorVisible(Tab, Length(Rows), ViewH, Cols);
    SetActiveTab(Panel, Tab);
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
    Exit(Term.HandleMouseDown(ALocalCol, ALocalRow - ContentTopRow, AShift));
  end;
  Doc := ActiveDocument;
  if not Assigned(Doc) or (ALocalRow < 2) then
    Exit(True);
  Result := Doc.HandleMouseDown(ALocalCol, ALocalRow - ContentTopRow, AShift);
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

function TDualPanelWindow.HasOpenDialog: Boolean;
begin
  Result := Assigned(FDialog) and FDialog.Visible;
end;

function TDualPanelWindow.TopMenuOpen: Boolean;
begin
  Result := Assigned(FTopMenu) and FTopMenu.Active;
end;

function TDualPanelWindow.HandleMenuMouseUp(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := Assigned(FTopMenu) and FTopMenu.HandleMouseUp(ALocalCol, ALocalRow);
  if Result then
    NotifyChanged;
end;

function TDualPanelWindow.HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Doc: TEditorWindow;
  Term: TTerminalWorkspaceWindow;
begin
  if HelpVisible then
    Exit(FHelp.HandleMouseMove(ALocalCol, ALocalRow));
  // Dragging through an open menu only moves its selection.
  if Assigned(FTopMenu) and FTopMenu.Active then
    Exit(FTopMenu.HandleMouseMove(ALocalCol, ALocalRow));
  if TabDragBusy(FTabDragArmed, FTabDragActive) then
    Exit(UpdateTabDrag(ALocalCol, ALocalRow));
  Result := False;
  if ActiveWorkspace.Kind = wkTerminal then
  begin
    Term := ActiveTerminal;
    if not Assigned(Term) or (ALocalRow < 2) then
      Exit;
    Exit(Term.HandleMouseMove(ALocalCol, ALocalRow - ContentTopRow));
  end;
  if ActiveWorkspace.Kind <> wkDocument then
    Exit;
  Doc := ActiveDocument;
  if not Assigned(Doc) or (ALocalRow < 2) then
    Exit;
  Result := Doc.HandleMouseMove(ALocalCol, ALocalRow - ContentTopRow);
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
