unit uDualPanelSearch;

{ Find-file overlay (Alt+F7). Extracted from TDualPanelWindow. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uDualPanelUiTypes, uDualPanelOverlays,
  uVfsTypes, uFileFind, uFindSession;

type
  /// <summary>What StartSearch's FindFilesAsync done-callback does next.
  /// Background empty paths drop the job; other background paths still refresh
  /// the job chip when the entry remains.</summary>
  TFindWalkDoneAction = (
    fdaIgnore,
    fdaBgEmptyNotifyAndDrop,
    fdaBgEmptyDropOnly,
    fdaBgUpdateOpenedSession,
    fdaBgOpenCancelledHits,
    fdaBgNotifyFound,
    fdaFgMergeShownHits,
    fdaFgCancelClear,
    fdaFgNavigateHits,
    fdaFgShowResultsOverlay);

  TSearchGotoEvent = reference to procedure(const AFilePath: string);
  /// <summary>Shows AHits as the find panel; True when it did. AUpdate is True
  /// once an earlier call showed it: the list only grew, so the panel keeps its
  /// cursor and selection.</summary>
  TSearchFindNavigateEvent = reference to function(const ARoot, AMask: string;
    const AHits: TArray<TFindHit>; AUpdate: Boolean): Boolean;

  /// <summary>A search that runs in the background has ended; AFound is the
  /// number of files it found.</summary>
  TSearchBackgroundDoneEvent = reference to procedure(AFound: Integer);
  /// <summary>Shows the hits of a background search as a find panel on the
  /// session ASessionId (empty: a new one, whose id comes back).</summary>
  TSearchSessionOpenEvent = reference to function(var ASessionId: string;
    const ARoot, AMask: string; const AHits: TArray<TFindHit>): Boolean;
  /// <summary>Replaces the hits of the open find session and redraws the
  /// panels that show it.</summary>
  TSearchSessionUpdateEvent = reference to procedure(const ASessionId, ARoot,
    AMask: string; const AHits: TArray<TFindHit>);
  /// <summary>True while some panel tab still shows the find session.</summary>
  TSearchSessionShownFunc = reference to function(const ASessionId: string): Boolean;
  /// <summary>The id of the find session the active panel shows; empty when
  /// it shows none.</summary>
  TSearchCurrentSessionFunc = reference to function: string;

  /// <summary>A search sent to the background: it has its own job-list entry
  /// and chip, and lives until its results are closed.</summary>
  TBackgroundSearch = class
  public
    Id: Integer;
    Root: string;
    Mask: string;
    Token: IJobCancelToken;
    Hits: TArray<TFindHit>;
    Done: Boolean;
    CurrentDir: string;
    /// <summary>Find session that shows the hits; empty until the user opens it.</summary>
    SessionId: string;
    /// <summary>A panel shows the session now; it is hidden again when the
    /// search goes back to the background.</summary>
    Opened: Boolean;
    /// <summary>The user chose to keep the results in the panel without the
    /// progress dialog; hiding the dialog then leaves the panel alone.</summary>
    Attached: Boolean;
    JobKey: string;
  end;

  TSearchController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FOnGoto: TSearchGotoEvent;
    FOnNavigateFindResults: TSearchFindNavigateEvent;
    FOnAfterClose: TProc;
    FOnStopRequest: TProc;
    FOnLimitReached: TProc;
    FSearch: TSearchState;
    FLife: ILifeFlag;
    // The panel already lists the hits of the running search.
    FResultsShown: Boolean;
    // Bumped by every StartSearch. The walk of the current number belongs to
    // the overlay; a number found in FBackgrounds belongs to that search.
    FRunId: Integer;
    FBackgrounds: TObjectList<TBackgroundSearch>;
    FOpening: Boolean;
    // Job of the search the progress dialog shows; empty when none runs there.
    FFgJobKey: string;
    FOnHideResults: TProc;
    FOnBackgroundDone: TSearchBackgroundDoneEvent;
    FOnOpenSession: TSearchSessionOpenEvent;
    FOnUpdateSession: TSearchSessionUpdateEvent;
    FOnSessionShown: TSearchSessionShownFunc;
    FOnCurrentSession: TSearchCurrentSessionFunc;
    function GetBackgroundCount: Integer;
    function FindBackground(AId: Integer): TBackgroundSearch;
    procedure OpenBackground(AId: Integer);
    procedure DropBackground(AId: Integer);
    procedure RefreshBackgroundJob(ASearch: TBackgroundSearch);
    procedure HideBackground(ASearch: TBackgroundSearch);
    procedure EndForegroundJob;
    procedure ShowSearchError(const AMessage: string);
    procedure JobCancel(AId: Integer);
    procedure JobOpen(AId: Integer);
    procedure JobForeground(AId: Integer; AForeground: Boolean);
    procedure JobAttach(AId: Integer);
    function JobIdOf(const AKey: string): Integer;
    procedure HandleSearchInputDialog(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char);
    procedure HandleSearchInputRunning(var AKey: Word; var AKeyChar: Char);
    procedure HandleSearchInputResults(var AKey: Word; var AKeyChar: Char);
    procedure QueueFindLimitNotice(AErrorCode: TVfsErrorCode; ATruncated: Boolean;
      const ALife: ILifeFlag);
    procedure ApplyFindWalkDone(AAction: TFindWalkDoneAction; ARunId: Integer;
      ABg: TBackgroundSearch; const AHits: TArray<TFindHit>;
      const AError: TVfsError; ATruncated: Boolean; const ARoot, AMask: string;
      const ALife: ILifeFlag);
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AOnGoto: TSearchGotoEvent;
      const AOnNavigateFindResults: TSearchFindNavigateEvent;
      const AOnAfterClose: TProc = nil);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure CloseSearchUi;
    procedure LayoutSearchUi(AClientWidth, AClientHeight: Integer);
    procedure DrawSearchUi(const AGrid: TTerminalGrid;
      AClientWidth, AClientHeight: Integer);
    procedure StartSearch;
    procedure CancelSearch;
    /// <summary>Starts the search the dialog describes and sends it to the
    /// background at once.</summary>
    procedure StartSearchInBackground;
    /// <summary>Hides the overlay of the running search and lets it go on as a
    /// background search with a job of its own; the job opens its results.
    /// AKeepPanel leaves the live results in the panel, where they go on growing.</summary>
    procedure SendToBackground(AKeepPanel: Boolean = False);
    /// <summary>Ends the finished background searches whose results no panel
    /// shows any more, with their jobs; a search still running only stops
    /// feeding a panel and goes on. Called whenever the panels change.</summary>
    procedure SweepBackgrounds;
    procedure GotoSearchResult;
    function HandleSearchInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function GetActive: Boolean;
    property Phase: TSearchPhase read FSearch.Phase write FSearch.Phase;
    property Mask: string read FSearch.Mask write FSearch.Mask;
    property ContainingText: string read FSearch.ContainingText write FSearch.ContainingText;
    property Subdirs: Boolean read FSearch.Subdirs write FSearch.Subdirs;
    property CaseSensitive: Boolean read FSearch.CaseSensitive write FSearch.CaseSensitive;
    property WholeWords: Boolean read FSearch.WholeWords write FSearch.WholeWords;
    property SearchFolders: Boolean read FSearch.SearchFolders write FSearch.SearchFolders;
    property UseRegex: Boolean read FSearch.UseRegex write FSearch.UseRegex;
    property SearchArchives: Boolean read FSearch.SearchArchives write FSearch.SearchArchives;
    property UsePlugins: Boolean read FSearch.UsePlugins write FSearch.UsePlugins;
    property EncodingIdx: Integer read FSearch.EncodingIdx write FSearch.EncodingIdx;
    property HexText: string read FSearch.HexText write FSearch.HexText;
    property HexMode: Boolean read FSearch.HexMode write FSearch.HexMode;
    property Filters: TFindFilterText read FSearch.Filters write FSearch.Filters;
    property RootPath: string read FSearch.RootPath write FSearch.RootPath;
    property FocusField: Integer read FSearch.FocusField write FSearch.FocusField;
    property Message: string read FSearch.Message;
    property FoundCount: Integer read FSearch.FoundCount;
    property CurrentDir: string read FSearch.CurrentDir;
    property Bounds: TRectI read FSearch.Bounds;
    property Active: Boolean read GetActive;
    property State: TSearchState read FSearch;
    /// <summary>Called on Esc while a search runs. When assigned, the owner
    /// decides whether to call CancelSearch (the window asks for confirmation).</summary>
    property OnStopRequest: TProc read FOnStopRequest write FOnStopRequest;
    /// <summary>Called after a search that ended because it hit the result
    /// limit (cFindMaxResults).</summary>
    property OnLimitReached: TProc read FOnLimitReached write FOnLimitReached;
    property BackgroundCount: Integer read GetBackgroundCount;
    property OnBackgroundDone: TSearchBackgroundDoneEvent read FOnBackgroundDone
      write FOnBackgroundDone;
    /// <summary>Takes the live results out of the panel when the search goes to
    /// the background.</summary>
    property OnHideResults: TProc read FOnHideResults write FOnHideResults;
    property OnOpenSession: TSearchSessionOpenEvent read FOnOpenSession
      write FOnOpenSession;
    property OnUpdateSession: TSearchSessionUpdateEvent read FOnUpdateSession
      write FOnUpdateSession;
    property OnSessionShown: TSearchSessionShownFunc read FOnSessionShown
      write FOnSessionShown;
    property OnCurrentSession: TSearchCurrentSessionFunc read FOnCurrentSession
      write FOnCurrentSession;
  end;

/// <summary>True while a progress tick still belongs to a live walk (bg chip
/// or the foreground overlay of the current run).</summary>
function FindWalkProgressApplies(AAlive, AIsBackground, ARunCurrent,
  APhaseRunning: Boolean): Boolean;

/// <summary>True when the walk hit cFindMaxResults and finished cleanly.</summary>
function ShouldQueueFindLimitNotice(AErrorCode: TVfsErrorCode;
  ATruncated: Boolean): Boolean;

/// <summary>Done-callback disposition for a find walk. AIsBackground means the
/// run already left the overlay; ARunCurrent/APhaseRunning gate the foreground
/// path only.</summary>
function ClassifyFindWalkDone(AAlive, AIsBackground, ABgOpened,
  AResultsShown, ARunCurrent, APhaseRunning: Boolean;
  AErrorCode: TVfsErrorCode; AHitCount: Integer): TFindWalkDoneAction;

type
  /// <summary>What the find overlay dialog does with a key while FocusField is
  /// mask (0) or subdirs checkbox (1).</summary>
  TSearchDialogKeyAction = (sdaClose, sdaToggleFocus, sdaStart, sdaToggleSubdirs,
    sdaBackspace, sdaAppendChar, sdaSwallow);

/// <summary>Dialog-phase key disposition for Alt+F7 before the walk starts.</summary>
function ClassifySearchDialogKey(AFocusField: Integer; AKey: Word;
  AKeyChar: Char; AShift: TShiftState): TSearchDialogKeyAction;

/// <summary>Overlay dialog fields copied into a walk-prep criteria record.</summary>
function FindWalkCriteriaFromSearch(const ASearch: TSearchState): TFindWalkCriteria;

/// <summary>Scroll top that keeps ACursor visible in a view of AViewH rows.</summary>
function SearchResultsScrollForCursor(AScroll, ACursor, AViewH: Integer): Integer;

/// <summary>Hit path relative to ARootPath, with archive inner suffix and a
/// trailing '~' when longer than AMaxWidth.</summary>
function FormatSearchHitDisplayPath(const APath, ARootPath: string;
  AMaxWidth: Integer): string;

/// <summary>Job-list key of a find walk: find:&lt;run id&gt;.</summary>
function FindWalkJobKey(ARunId: Integer): string;

/// <summary>Progress chip text: Found: N plus the current directory.</summary>
function FormatFindProgressJobText(AFoundCount: Integer;
  const ACurrentDir: string): string;

/// <summary>Marks a background search finished and stores its hits.</summary>
procedure MarkBackgroundSearchFinished(ABg: TBackgroundSearch;
  const AHits: TArray<TFindHit>);

/// <summary>Message for the foreground results overlay when the walk ends
/// without navigating to a panel.</summary>
function FindFgResultsMessage(AErrorCode: TVfsErrorCode;
  const AErrorMessage: string): string;

/// <summary>Title of the find overlay for a phase (result count for spResults).</summary>
function SearchOverlayTitleForPhase(APhase: TSearchPhase;
  AResultCount: Integer): string;

implementation

uses
  uStrings, uKeyChord, uTextEncoding, uFindArchive, uPluginServices, uFindRouter;

const
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cMenuHot  = TAlphaColor($FFFFFF55);
  cDirFg    = TAlphaColor($FFFFFFFF);
  // U+2026 by codepoint rather than a pasted '...'. The file carries a UTF-8 BOM
  // now, so a literal would compile correctly too - but it did not when this
  // truncation was written, and the compiler then read the ellipsis as 3 ANSI
  // chars, making the clipped path 2 cells wider than the frame's inner span
  // and spilling it past the right border. Stated by codepoint the width math
  // cannot regress if the encoding is ever lost again. (chBoxH in
  // uTerminalTypes.pas uses the same convention.)
  cEllipsis = #$2026;
  // The job-list entry of a search that runs in the background.
  cJobOwner = 'host';

function FindWalkProgressApplies(AAlive, AIsBackground, ARunCurrent,
  APhaseRunning: Boolean): Boolean;
begin
  if not AAlive then
    Exit(False);
  if AIsBackground then
    Exit(True);
  Result := ARunCurrent and APhaseRunning;
end;

function ShouldQueueFindLimitNotice(AErrorCode: TVfsErrorCode;
  ATruncated: Boolean): Boolean;
begin
  Result := (AErrorCode = vecOk) and ATruncated;
end;

function ClassifyFindWalkDone(AAlive, AIsBackground, ABgOpened,
  AResultsShown, ARunCurrent, APhaseRunning: Boolean;
  AErrorCode: TVfsErrorCode; AHitCount: Integer): TFindWalkDoneAction;
begin
  if not AAlive then
    Exit(fdaIgnore);
  if AIsBackground then
  begin
    if AHitCount = 0 then
    begin
      if AErrorCode <> vecCancelled then
        Exit(fdaBgEmptyNotifyAndDrop);
      Exit(fdaBgEmptyDropOnly);
    end;
    if ABgOpened then
      Exit(fdaBgUpdateOpenedSession);
    if AErrorCode = vecCancelled then
      Exit(fdaBgOpenCancelledHits);
    Exit(fdaBgNotifyFound);
  end;
  if not (ARunCurrent and APhaseRunning) then
    Exit(fdaIgnore);
  if AResultsShown then
    Exit(fdaFgMergeShownHits);
  if AErrorCode = vecCancelled then
    Exit(fdaFgCancelClear);
  if (AErrorCode = vecOk) and (AHitCount > 0) then
    Exit(fdaFgNavigateHits);
  Result := fdaFgShowResultsOverlay;
end;

function ClassifySearchDialogKey(AFocusField: Integer; AKey: Word;
  AKeyChar: Char; AShift: TShiftState): TSearchDialogKeyAction;
var
  K: TKeyChord;
begin
  if AKey = vkEscape then
    Exit(sdaClose);
  if AKey = vkTab then
    Exit(sdaToggleFocus);
  if AKey = vkReturn then
    Exit(sdaStart);
  if AFocusField = 1 then
  begin
    if (AKey = vkSpace) or (AKeyChar = ' ') then
      Exit(sdaToggleSubdirs);
    Exit(sdaSwallow);
  end;
  if AKey = vkBack then
    Exit(sdaBackspace);
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  if K.IsPrintable and K.HasMods([], [ssShift]) then
    Exit(sdaAppendChar);
  Result := sdaSwallow;
end;

function FindWalkCriteriaFromSearch(const ASearch: TSearchState): TFindWalkCriteria;
begin
  Result := Default(TFindWalkCriteria);
  Result.Mask := ASearch.Mask;
  Result.RootPath := ASearch.RootPath;
  Result.ContainingText := ASearch.ContainingText;
  Result.HexText := ASearch.HexText;
  Result.Filters := ASearch.Filters;
  Result.Subdirs := ASearch.Subdirs;
  Result.CaseSensitive := ASearch.CaseSensitive;
  Result.WholeWords := ASearch.WholeWords;
  Result.SearchFolders := ASearch.SearchFolders;
  Result.UseRegex := ASearch.UseRegex;
  Result.SearchArchives := ASearch.SearchArchives;
  Result.BuiltInOnly := not ASearch.UsePlugins;
  Result.HexMode := ASearch.HexMode;
  Result.EncodingIdx := ASearch.EncodingIdx;
end;

function SearchResultsScrollForCursor(AScroll, ACursor, AViewH: Integer): Integer;
begin
  Result := AScroll;
  if ACursor < Result then
    Result := ACursor;
  if ACursor >= Result + AViewH then
    Result := ACursor - AViewH + 1;
  if Result < 0 then
    Result := 0;
end;

function FormatSearchHitDisplayPath(const APath, ARootPath: string;
  AMaxWidth: Integer): string;
var
  Rel, ArchivePath, InnerPath: string;
begin
  // SplitArchiveHit clears its outs on a miss; keep APath until it succeeds.
  Rel := APath;
  InnerPath := '';
  if SplitArchiveHit(APath, ArchivePath, InnerPath) then
  begin
    Rel := ArchivePath;
    InnerPath := ' : ' + InnerPath;
  end;
  if ARootPath <> '' then
  begin
    if Rel.StartsWith(IncludeTrailingPathDelimiter(ARootPath), True) then
      Rel := Copy(Rel, Length(IncludeTrailingPathDelimiter(ARootPath)) + 1, MaxInt)
    else if SameLocalPath(Rel, ARootPath) then
      Rel := ExtractFileName(Rel);
  end;
  Result := Rel + InnerPath;
  if (AMaxWidth > 0) and (Length(Result) > AMaxWidth) then
    Result := Copy(Result, 1, AMaxWidth - 1) + '~';
end;

function FindWalkJobKey(ARunId: Integer): string;
begin
  Result := 'find:' + IntToStr(ARunId);
end;

function FormatFindProgressJobText(AFoundCount: Integer;
  const ACurrentDir: string): string;
begin
  Result := T('ui.search.found', 'Found: %d', [AFoundCount]) + #10 + ACurrentDir;
end;

procedure MarkBackgroundSearchFinished(ABg: TBackgroundSearch;
  const AHits: TArray<TFindHit>);
begin
  if ABg = nil then
    Exit;
  ABg.Done := True;
  ABg.Token := nil;
  ABg.Hits := AHits;
end;

function FindFgResultsMessage(AErrorCode: TVfsErrorCode;
  const AErrorMessage: string): string;
begin
  if AErrorCode <> vecOk then
    Result := AErrorMessage
  else
    Result := T('ui.search.none', 'No files found');
end;

function SearchOverlayTitleForPhase(APhase: TSearchPhase;
  AResultCount: Integer): string;
begin
  case APhase of
    spRunning:
      Result := T('ui.search.running', 'Searching') + cEllipsis;
    spResults:
      Result := T('ui.search.results', 'Results: %d', [AResultCount]);
  else
    Result := T('ui.search.title', 'Find');
  end;
end;

constructor TSearchController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AOnGoto: TSearchGotoEvent;
  const AOnNavigateFindResults: TSearchFindNavigateEvent;
  const AOnAfterClose: TProc);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FOnGoto := AOnGoto;
  FOnNavigateFindResults := AOnNavigateFindResults;
  FOnAfterClose := AOnAfterClose;
  FLife := NewLifeFlag;
  FBackgrounds := TObjectList<TBackgroundSearch>.Create(True);
  FSearch.Phase := spNone;
  FSearch.Mask := '*.*';
  FSearch.ContainingText := '';
  FSearch.Subdirs := True;
  FSearch.CaseSensitive := False;
  FSearch.WholeWords := False;
  FSearch.SearchFolders := False;
  FSearch.UseRegex := False;
  FSearch.SearchArchives := False;
  FSearch.UsePlugins := True;
  FSearch.EncodingIdx := 0;
  FSearch.HexText := '';
  FSearch.HexMode := False;
  FSearch.Filters := Default(TFindFilterText);
  FSearch.FocusField := 0;
end;

destructor TSearchController.Destroy;
begin
  FLife.Alive := False;
  if Assigned(FSearch.Cancel) then
    FSearch.Cancel.Cancel;
  EndForegroundJob;
  while FBackgrounds.Count > 0 do
    DropBackground(FBackgrounds[0].Id);
  FBackgrounds.Free;
  inherited;
end;

procedure TSearchController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

function TSearchController.GetActive: Boolean;
begin
  Result := FSearch.Phase <> spNone;
end;

procedure TSearchController.CloseSearchUi;
begin
  if Assigned(FSearch.Cancel) then
    FSearch.Cancel.Cancel;
  FSearch.Cancel := nil;
  EndForegroundJob;
  FSearch.Phase := spNone;
  SetLength(FSearch.Results, 0);
  FSearch.FoundCount := 0;
  FSearch.CurrentDir := '';
  FSearch.Message := '';
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  if Assigned(FOnAfterClose) then
    FOnAfterClose;
end;

procedure TSearchController.LayoutSearchUi(AClientWidth, AClientHeight: Integer);
var
  W, H, PanelW, Left, Top: Integer;
begin
  PanelW := AClientWidth;
  case FSearch.Phase of
    spDialog:
      begin
        W := Min(52, Max(PanelW - 2, 32));
        H := 9;
      end;
    spRunning:
      begin
        W := Min(76, Max(PanelW - 2, 32));
        H := 7;
      end;
    spResults:
      begin
        W := Min(70, Max(PanelW - 2, 36));
        H := Min(Max(AClientHeight - 6, 10), 20);
      end;
  else
    Exit;
  end;
  Left := (PanelW - W) div 2;
  Top := Max(AClientHeight div 2 - H div 2, 3);
  if Left + W > PanelW then
    Left := Max(PanelW - W, 0);
  if Top + H > AClientHeight then
    Top := Max(AClientHeight - H, 1);
  FSearch.Bounds := TRectI.Make(Left, Top, Left + W - 1, Top + H - 1);
end;

// Shows a search that could not start as an empty results page carrying the
// reason.
procedure TSearchController.ShowSearchError(const AMessage: string);
begin
  FSearch.Message := AMessage;
  FSearch.Phase := spResults;
  SetLength(FSearch.Results, 0);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TSearchController.StartSearch;
var
  Mask, Root, ErrorText: string;
  Token: IJobCancelToken;
  Opts: TFindOptions;
  Life: ILifeFlag;
  RunId: Integer;
  Bg: TBackgroundSearch;
  Criteria: TFindWalkCriteria;
begin
  // A bad pattern or size is reported before the walk starts instead of
  // silently matching nothing on every file; past this point the overlay says
  // the search is running, and Esc only cancels a walk that has already started.
  Criteria := FindWalkCriteriaFromSearch(FSearch);
  if not TryPrepareFindWalk(Criteria, Root, Mask, Opts, ErrorText) then
  begin
    FSearch.Mask := Mask;
    FSearch.RootPath := Root;
    ShowSearchError(ErrorText);
    Exit;
  end;
  FSearch.Mask := Mask;
  FSearch.RootPath := Root;

  Life := FLife;
  Inc(FRunId);
  RunId := FRunId;
  Token := TJobCancelToken.Create;
  FSearch.Cancel := Token;
  FSearch.Phase := spRunning;
  FSearch.FoundCount := 0;
  FSearch.CurrentDir := Root;
  FSearch.Message := '';
  FResultsShown := False;
  SetLength(FSearch.Results, 0);
  // The progress dialog is the dialog of this job; the Background button of
  // that dialog hides it, which sends the search to the background.
  EndForegroundJob;
  FFgJobKey := FindWalkJobKey(RunId);
  PluginJobBegin(cJobOwner, FFgJobKey, T('ui.search.jobTitle', 'Search: %s', [Mask]),
    procedure
    begin
      JobCancel(RunId);
    end,
    procedure
    begin
      JobOpen(RunId);
    end,
    procedure(AForeground: Boolean)
    begin
      JobForeground(RunId, AForeground);
    end,
    False,
    procedure
    begin
      JobAttach(RunId);
    end);
  PluginJobUpdate(cJobOwner, FFgJobKey, FormatFindProgressJobText(0, Root), -1);
  PluginJobSetForeground(JobIdOf(FFgJobKey), True);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;

  FindFilesRouted(Opts, Token,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
      Bg := FindBackground(RunId);
      if not FindWalkProgressApplies(Life.Alive, Bg <> nil, RunId = FRunId,
        FSearch.Phase = spRunning) then
        Exit;
      if Bg <> nil then
      begin
        Bg.CurrentDir := ACurrentDir;
        PluginJobUpdate(cJobOwner, Bg.JobKey,
          FormatFindProgressJobText(AFoundCount, ACurrentDir), -1);
        PluginJobSetBadge(cJobOwner, Bg.JobKey, IntToStr(AFoundCount));
        Exit;
      end;
      FSearch.FoundCount := AFoundCount;
      FSearch.CurrentDir := ACurrentDir;
      PluginJobUpdate(cJobOwner, FindWalkJobKey(RunId),
        FormatFindProgressJobText(AFoundCount, ACurrentDir), -1);
      PluginJobSetBadge(cJobOwner, FindWalkJobKey(RunId), IntToStr(AFoundCount));
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError;
      ATruncated: Boolean)
    begin
      Bg := FindBackground(RunId);
      ApplyFindWalkDone(
        ClassifyFindWalkDone(Life.Alive, Bg <> nil,
          (Bg <> nil) and Bg.Opened, FResultsShown, RunId = FRunId,
          FSearch.Phase = spRunning, AError.Code, Length(AHits)),
        RunId, Bg, AHits, AError, ATruncated, Root, Mask, Life);
    end,
    procedure(const ANewHits: TArray<TFindHit>)
    begin
      Bg := FindBackground(RunId);
      if not FindWalkProgressApplies(Life.Alive, Bg <> nil, RunId = FRunId,
        FSearch.Phase = spRunning) then
        Exit;
      if Bg <> nil then
      begin
        Bg.Hits := Bg.Hits + ANewHits;
        if (Bg.SessionId <> '') and Assigned(FOnUpdateSession) then
          FOnUpdateSession(Bg.SessionId, Bg.Root, Bg.Mask, Bg.Hits);
        Exit;
      end;
      if not Assigned(FOnNavigateFindResults) then
        Exit;
      FSearch.Results := FSearch.Results + ANewHits;
      FSearch.FoundCount := Length(FSearch.Results);
      if FOnNavigateFindResults(Root, Mask, FSearch.Results, FResultsShown) then
        FResultsShown := True;
    end);
end;

procedure TSearchController.QueueFindLimitNotice(AErrorCode: TVfsErrorCode;
  ATruncated: Boolean; const ALife: ILifeFlag);
begin
  // Queued so the notice opens after this callback has closed or rebuilt UI.
  if ShouldQueueFindLimitNotice(AErrorCode, ATruncated) and
     Assigned(FOnLimitReached) then
    TThread.Queue(nil,
      procedure
      begin
        if ALife.Alive then
          FOnLimitReached;
      end);
end;

procedure TSearchController.ApplyFindWalkDone(AAction: TFindWalkDoneAction;
  ARunId: Integer; ABg: TBackgroundSearch; const AHits: TArray<TFindHit>;
  const AError: TVfsError; ATruncated: Boolean; const ARoot, AMask: string;
  const ALife: ILifeFlag);
begin
  case AAction of
    fdaIgnore:
      Exit;
    fdaBgEmptyNotifyAndDrop:
      begin
        MarkBackgroundSearchFinished(ABg, AHits);
        if Assigned(FOnBackgroundDone) then
          FOnBackgroundDone(0);
        DropBackground(ARunId);
      end;
    fdaBgEmptyDropOnly:
      begin
        MarkBackgroundSearchFinished(ABg, AHits);
        DropBackground(ARunId);
      end;
    fdaBgUpdateOpenedSession:
      begin
        MarkBackgroundSearchFinished(ABg, AHits);
        if Assigned(FOnUpdateSession) then
          FOnUpdateSession(ABg.SessionId, ABg.Root, ABg.Mask, AHits);
        if FindBackground(ARunId) <> nil then
        begin
          RefreshBackgroundJob(ABg);
          PluginJobSetForeground(JobIdOf(ABg.JobKey), False);
        end;
      end;
    fdaBgOpenCancelledHits:
      begin
        MarkBackgroundSearchFinished(ABg, AHits);
        // A search the user stopped shows what it found right away.
        OpenBackground(ARunId);
        if FindBackground(ARunId) <> nil then
        begin
          RefreshBackgroundJob(ABg);
          PluginJobSetForeground(JobIdOf(ABg.JobKey), False);
        end;
      end;
    fdaBgNotifyFound:
      begin
        MarkBackgroundSearchFinished(ABg, AHits);
        if Assigned(FOnBackgroundDone) then
          FOnBackgroundDone(Length(AHits));
        if FindBackground(ARunId) <> nil then
        begin
          RefreshBackgroundJob(ABg);
          PluginJobSetForeground(JobIdOf(ABg.JobKey), False);
        end;
      end;
    fdaFgMergeShownHits:
      begin
        FSearch.Cancel := nil;
        EndForegroundJob;
        QueueFindLimitNotice(AError.Code, ATruncated, ALife);
        if Length(AHits) > 0 then
          FOnNavigateFindResults(ARoot, AMask, AHits, True);
        CloseSearchUi;
      end;
    fdaFgCancelClear:
      begin
        FSearch.Cancel := nil;
        EndForegroundJob;
        QueueFindLimitNotice(AError.Code, ATruncated, ALife);
        FSearch.Phase := spNone;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
      end;
    fdaFgNavigateHits:
      begin
        FSearch.Cancel := nil;
        EndForegroundJob;
        QueueFindLimitNotice(AError.Code, ATruncated, ALife);
        CloseSearchUi;
        if Assigned(FOnNavigateFindResults) and
           FOnNavigateFindResults(ARoot, AMask, AHits, False) then
          Exit;
        FSearch.Results := AHits;
        FSearch.FoundCount := Length(AHits);
        FSearch.Cursor := 0;
        FSearch.Scroll := 0;
        FSearch.Message := FindFgResultsMessage(vecOk, '');
        FSearch.Phase := spResults;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
      end;
    fdaFgShowResultsOverlay:
      begin
        FSearch.Cancel := nil;
        EndForegroundJob;
        QueueFindLimitNotice(AError.Code, ATruncated, ALife);
        FSearch.Results := AHits;
        FSearch.FoundCount := Length(AHits);
        FSearch.Cursor := 0;
        FSearch.Scroll := 0;
        FSearch.Message := FindFgResultsMessage(AError.Code, AError.Message);
        FSearch.Phase := spResults;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
      end;
  end;
end;

procedure TSearchController.CancelSearch;
begin
  if FSearch.Phase = spRunning then
  begin
    if Assigned(FSearch.Cancel) then
      FSearch.Cancel.Cancel;
  end
  else
    CloseSearchUi;
end;

function TSearchController.GetBackgroundCount: Integer;
begin
  Result := FBackgrounds.Count;
end;

function TSearchController.FindBackground(AId: Integer): TBackgroundSearch;
var
  S: TBackgroundSearch;
begin
  for S in FBackgrounds do
    if S.Id = AId then
      Exit(S);
  Result := nil;
end;

procedure TSearchController.RefreshBackgroundJob(ASearch: TBackgroundSearch);
var
  Text: string;
begin
  Text := T('ui.search.found', 'Found: %d', [Length(ASearch.Hits)]);
  if ASearch.Done then
    PluginJobUpdate(cJobOwner, ASearch.JobKey, Text, 100)
  else
    PluginJobUpdate(cJobOwner, ASearch.JobKey, Text + #10 + ASearch.CurrentDir, -1);
  PluginJobSetBadge(cJobOwner, ASearch.JobKey, IntToStr(Length(ASearch.Hits)));
end;

function TSearchController.JobIdOf(const AKey: string): Integer;
begin
  Result := PluginJobIdByKey(cJobOwner, AKey);
end;

procedure TSearchController.DropBackground(AId: Integer);
var
  S: TBackgroundSearch;
  Key: string;
begin
  S := FindBackground(AId);
  if S = nil then
    Exit;
  if Assigned(S.Token) then
    S.Token.Cancel;
  Key := S.JobKey;
  // Out of the list first: ending the job repaints, and the repaint sweeps.
  FBackgrounds.Remove(S);
  PluginJobEnd(cJobOwner, Key);
end;

procedure TSearchController.EndForegroundJob;
var
  Key: string;
begin
  Key := FFgJobKey;
  FFgJobKey := '';
  if Key <> '' then
    PluginJobEnd(cJobOwner, Key);
end;

procedure TSearchController.OpenBackground(AId: Integer);
var
  S: TBackgroundSearch;
begin
  S := FindBackground(AId);
  if (S = nil) or not Assigned(FOnOpenSession) then
    Exit;
  // The panels change while it opens; the sweep must not mistake that for a
  // panel that was left.
  FOpening := True;
  try
    S.Opened := FOnOpenSession(S.SessionId, S.Root, S.Mask, S.Hits);
    if not S.Opened then
      S.SessionId := '';
  finally
    FOpening := False;
  end;
end;

procedure TSearchController.HideBackground(ASearch: TBackgroundSearch);
begin
  if not ASearch.Opened then
    Exit;
  ASearch.Opened := False;
  if Assigned(FOnHideResults) then
  begin
    FOpening := True;
    try
      FOnHideResults;
    finally
      FOpening := False;
    end;
  end;
end;

procedure TSearchController.JobCancel(AId: Integer);
var
  B: TBackgroundSearch;
begin
  B := FindBackground(AId);
  if B = nil then
  begin
    // The search of the progress dialog: it ends through its own callback.
    if (AId = FRunId) and (FSearch.Phase = spRunning) and Assigned(FSearch.Cancel) then
      FSearch.Cancel.Cancel;
    Exit;
  end;
  // Stopping a running search keeps what it found; a finished one that
  // nobody opened is discarded.
  if B.Done then
    DropBackground(AId)
  else if Assigned(B.Token) then
    B.Token.Cancel;
end;

procedure TSearchController.JobOpen(AId: Integer);
var
  B: TBackgroundSearch;
  JobId: Integer;
begin
  B := FindBackground(AId);
  if B = nil then
  begin
    if (AId = FRunId) and (FSearch.Phase = spRunning) then
      PluginJobSetForeground(JobIdOf('find:' + IntToStr(AId)), True);
    Exit;
  end;
  // A running search comes back with its progress dialog; the panel shows
  // its results only while that dialog (or the finished search) is open.
  B.Attached := False;
  if not B.Done then
  begin
    JobId := JobIdOf(B.JobKey);
    if JobId > 0 then
      PluginJobSetForeground(JobId, True);
  end;
  // Results the panel already shows stay where they are.
  if B.Opened and Assigned(FOnSessionShown) and FOnSessionShown(B.SessionId) then
    Exit;
  OpenBackground(AId);
end;

procedure TSearchController.JobAttach(AId: Integer);
var
  B: TBackgroundSearch;
  JobId: Integer;
begin
  B := FindBackground(AId);
  if B = nil then
  begin
    // The search of the progress dialog becomes a background search whose
    // results stay in the panel.
    if (AId = FRunId) and (FSearch.Phase = spRunning) and Assigned(FSearch.Cancel) and
       not FSearch.Cancel.IsCancellationRequested then
    begin
      SendToBackground(True);
      B := FindBackground(AId);
    end;
    if B = nil then
      Exit;
  end
  else
  begin
    // A background search that came back with its dialog: the panel it opened
    // stays, the dialog goes.
    B.Attached := True;
    JobId := JobIdOf(B.JobKey);
    if JobId > 0 then
      PluginJobSetForeground(JobId, False);
  end;
  if not B.Opened then
    OpenBackground(AId);
end;

procedure TSearchController.JobForeground(AId: Integer; AForeground: Boolean);
var
  B: TBackgroundSearch;
begin
  if AForeground then
    Exit;
  B := FindBackground(AId);
  if B <> nil then
  begin
    // Hiding the dialog of a search that still runs puts it away again.
    if not B.Done and not B.Attached and Assigned(B.Token) and
       not B.Token.IsCancellationRequested then
      HideBackground(B);
    Exit;
  end;
  if (AId = FRunId) and (FSearch.Phase = spRunning) and Assigned(FSearch.Cancel) and
     not FSearch.Cancel.IsCancellationRequested then
    SendToBackground;
end;

procedure TSearchController.SendToBackground(AKeepPanel: Boolean);
var
  S: TBackgroundSearch;
  Id, JobId: Integer;
  KeepSession: string;
begin
  if FSearch.Phase <> spRunning then
    Exit;
  S := TBackgroundSearch.Create;
  S.Id := FRunId;
  Id := S.Id;
  S.Root := FSearch.RootPath;
  S.Mask := FSearch.Mask;
  S.Token := FSearch.Cancel;
  S.Hits := FSearch.Results;
  S.CurrentDir := FSearch.CurrentDir;
  S.JobKey := FFgJobKey;
  if S.JobKey = '' then
    S.JobKey := 'find:' + IntToStr(Id);
  FFgJobKey := '';
  FBackgrounds.Add(S);
  // The overlay lets go of the walk; its callbacks now find the search by number.
  FSearch.Cancel := nil;
  FSearch.Phase := spNone;
  // The panel keeps the live results only when it shows a session this search
  // can go on feeding.
  KeepSession := '';
  if AKeepPanel and FResultsShown and Assigned(FOnCurrentSession) then
    KeepSession := FOnCurrentSession;
  S.Attached := AKeepPanel;
  if KeepSession <> '' then
  begin
    S.SessionId := KeepSession;
    S.Opened := True;
  end
  else if FResultsShown and Assigned(FOnHideResults) then
  begin
    FOpening := True;
    try
      FOnHideResults;
    finally
      FOpening := False;
    end;
  end;
  FResultsShown := False;
  SetLength(FSearch.Results, 0);
  Inc(FRunId);
  JobId := JobIdOf(S.JobKey);
  if JobId = 0 then
    PluginJobBegin(cJobOwner, S.JobKey, T('ui.search.jobTitle', 'Search: %s', [S.Mask]),
      procedure
      begin
        JobCancel(Id);
      end,
      procedure
      begin
        JobOpen(Id);
      end,
      procedure(AForeground: Boolean)
      begin
        JobForeground(Id, AForeground);
      end,
      True,
      procedure
      begin
        JobAttach(Id);
      end)
  else
  begin
    PluginJobSetForeground(JobId, False);
    PluginJobAnnounce(cJobOwner, S.JobKey);
  end;
  RefreshBackgroundJob(S);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  if Assigned(FOnAfterClose) then
    FOnAfterClose;
end;

procedure TSearchController.SweepBackgrounds;
var
  I: Integer;
  S: TBackgroundSearch;
begin
  if FOpening or not Assigned(FOnSessionShown) then
    Exit;
  for I := FBackgrounds.Count - 1 downto 0 do
  begin
    S := FBackgrounds[I];
    if S.Opened and not FOnSessionShown(S.SessionId) then
    begin
      if S.Done then
        DropBackground(S.Id)
      else
      begin
        // The user left the list: the search goes on without a panel.
        S.Opened := False;
        S.Attached := False;
      end;
    end;
  end;
end;

procedure TSearchController.StartSearchInBackground;
begin
  StartSearch;
  if FSearch.Phase = spRunning then
    SendToBackground;
end;

procedure TSearchController.GotoSearchResult;
var
  Path: string;
begin
  if (FSearch.Phase <> spResults) or (Length(FSearch.Results) = 0) then
    Exit;
  FSearch.Cursor := EnsureRange(FSearch.Cursor, 0, High(FSearch.Results));
  Path := FSearch.Results[FSearch.Cursor].Path;
  CloseSearchUi;
  if Assigned(FOnGoto) then
    FOnGoto(Path);
end;

procedure TSearchController.DrawSearchUi(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
var
  R: TRectI;
  Y, ViewH, Idx: Integer;
  Rel: string;
  Title: string;
  Fg, Bg: TAlphaColor;
begin
  if FSearch.Phase = spNone then
    Exit;
  if FSearch.Phase in [spDialog, spRunning] then
    Exit;
  LayoutSearchUi(AClientWidth, AClientHeight);
  R := FSearch.Bounds;
  if (R.Width < 12) or (R.Height < 5) then
    Exit;

  Title := SearchOverlayTitleForPhase(FSearch.Phase, Length(FSearch.Results));
  DrawHostOverlayFrame(AGrid, FTheme, R, Title,
    cFileFg, cPanelBg, cFrameActive, cCursorFg);

  case FSearch.Phase of
    spResults:
      begin
        if FSearch.Message <> '' then
          PutOverlayText(AGrid, FTheme, R.Left + 2, R.Top + 1, FSearch.Message,
            True, False, False, cMenuHot, cPanelBg)
        else
          PutOverlayText(AGrid, FTheme, R.Left + 2, R.Top + 1,
            T('ui.search.goHint', 'Enter=Go to  Esc=Close'), True, False, False, cMenuHot, cPanelBg);

        ViewH := Max(R.Height - 4, 1);
        FSearch.Scroll := SearchResultsScrollForCursor(FSearch.Scroll,
          FSearch.Cursor, ViewH);

        for Y := 0 to ViewH - 1 do
        begin
          Idx := FSearch.Scroll + Y;
          if Idx > High(FSearch.Results) then
          begin
            ResolveOverlayTextColors(FTheme, False, False, False,
              cFileFg, cPanelBg, Fg, Bg);
            FillGridRect(AGrid, R.Left + 1, R.Top + 2 + Y,
              R.Right - 1, R.Top + 2 + Y, ' ', Fg, Bg);
            Continue;
          end;
          Rel := FormatSearchHitDisplayPath(FSearch.Results[Idx].Path,
            FSearch.RootPath, R.Width - 2);
          if Idx = FSearch.Cursor then
            PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 2 + Y, Rel,
              False, False, True, cCursorFg, cCursorBg)
          else
            PutOverlayText(AGrid, FTheme, R.Left + 1, R.Top + 2 + Y, Rel,
              False, False, False, cFileFg, cPanelBg);
        end;
      end;
  end;
end;

procedure TSearchController.HandleSearchInputDialog(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char);
begin
  case ClassifySearchDialogKey(FSearch.FocusField, AKey, AKeyChar, AShift) of
    sdaClose:
      begin
        CloseSearchUi;
        AKey := 0;
      end;
    sdaToggleFocus:
      begin
        FSearch.FocusField := 1 - FSearch.FocusField;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    sdaStart:
      begin
        StartSearch;
        AKey := 0;
      end;
    sdaToggleSubdirs:
      begin
        FSearch.Subdirs := not FSearch.Subdirs;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
        AKeyChar := #0;
      end;
    sdaBackspace:
      begin
        if FSearch.Mask <> '' then
        begin
          Delete(FSearch.Mask, Length(FSearch.Mask), 1);
          if Assigned(FOnInvalidate) then
            FOnInvalidate;
        end;
        AKey := 0;
      end;
    sdaAppendChar:
      begin
        FSearch.Mask := FSearch.Mask + AKeyChar;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
        AKeyChar := #0;
      end;
  else
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TSearchController.HandleSearchInputRunning(var AKey: Word;
  var AKeyChar: Char);
begin
  if AKey = vkTab then
  begin
    SendToBackground;
    AKey := 0;
    AKeyChar := #0;
  end
  else if AKey = vkEscape then
  begin
    if Assigned(FOnStopRequest) then
      FOnStopRequest
    else
      CancelSearch;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TSearchController.HandleSearchInputResults(var AKey: Word;
  var AKeyChar: Char);
var
  ViewH: Integer;
begin
  ViewH := Max(FSearch.Bounds.Height - 4, 1);
  case AKey of
    vkEscape:
      begin
        CloseSearchUi;
        AKey := 0;
      end;
    vkReturn:
      begin
        GotoSearchResult;
        AKey := 0;
      end;
    vkUp:
      begin
        if FSearch.Cursor > 0 then
          Dec(FSearch.Cursor);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkDown:
      begin
        if FSearch.Cursor < High(FSearch.Results) then
          Inc(FSearch.Cursor);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkPrior:
      begin
        Dec(FSearch.Cursor, ViewH);
        if FSearch.Cursor < 0 then
          FSearch.Cursor := 0;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkNext:
      begin
        Inc(FSearch.Cursor, ViewH);
        if FSearch.Cursor > High(FSearch.Results) then
          FSearch.Cursor := Max(High(FSearch.Results), 0);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkHome:
      begin
        FSearch.Cursor := 0;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
    vkEnd:
      begin
        FSearch.Cursor := Max(High(FSearch.Results), 0);
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        AKey := 0;
      end;
  else
    AKey := 0;
    AKeyChar := #0;
  end;
end;

function TSearchController.HandleSearchInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := True;
  case FSearch.Phase of
    spDialog: HandleSearchInputDialog(AKey, AShift, AKeyChar);
    spRunning: HandleSearchInputRunning(AKey, AKeyChar);
    spResults: HandleSearchInputResults(AKey, AKeyChar);
  else
    Result := False;
  end;
end;

end.
