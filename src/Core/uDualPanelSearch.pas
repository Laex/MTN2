unit uDualPanelSearch;

{ Find-file overlay (Alt+F7). Extracted from TDualPanelWindow. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uDualPanelUiTypes, uDualPanelOverlays,
  uVfsTypes, uFileFind, uFindSession;

type
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
    procedure JobCancel(AId: Integer);
    procedure JobOpen(AId: Integer);
    procedure JobForeground(AId: Integer; AForeground: Boolean);
    procedure JobAttach(AId: Integer);
    function JobIdOf(const AKey: string): Integer;
    procedure HandleSearchInputDialog(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char);
    procedure HandleSearchInputRunning(var AKey: Word; var AKeyChar: Char);
    procedure HandleSearchInputResults(var AKey: Word; var AKeyChar: Char);
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

implementation

uses
  uStrings, uKeyChord, uTextEncoding, uFindArchive, uPluginServices;

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

procedure TSearchController.StartSearch;
var
  Mask, Root, RegexError, FilterError: string;
  HexPattern: TArray<Integer>;
  ByBytes: Boolean;
  Token: IJobCancelToken;
  Opts: TFindOptions;
  Life: ILifeFlag;
  RunId: Integer;
  Bg: TBackgroundSearch;
begin
  Mask := Trim(FSearch.Mask);
  if Mask = '' then
    Mask := '*.*';
  FSearch.Mask := Mask;
  Root := Trim(FSearch.RootPath);
  if (Root <> '') and (Length(Root) = 2) and (Root[2] = ':') then
    Root := Root + PathDelim;
  FSearch.RootPath := Root;
  if Root = '' then
  begin
    FSearch.Message := 'No search path';
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

  // Validate the regex once up front - a bad pattern is reported instantly
  // instead of silently matching nothing on every file in the walk.
  ByBytes := FSearch.HexMode and (Trim(FSearch.HexText) <> '');
  if ByBytes and
     not TryParseHexPattern(FSearch.HexText, HexPattern, RegexError) then
  begin
    FSearch.Message := 'Invalid hex: ' + RegexError;
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;
  if not ByBytes and FSearch.UseRegex and (Trim(FSearch.ContainingText) <> '') and
     not ValidateRegexPattern(FSearch.ContainingText, RegexError) then
  begin
    FSearch.Message := 'Invalid regex: ' + RegexError;
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

  Opts := DefaultFindOptions(Root, Mask, FSearch.Subdirs);
  Opts.ContainingText := FSearch.ContainingText;
  Opts.CaseSensitive := FSearch.CaseSensitive;
  Opts.WholeWords := FSearch.WholeWords;
  Opts.SearchFolders := FSearch.SearchFolders;
  Opts.UseRegex := FSearch.UseRegex;
  Opts.SearchArchives := FSearch.SearchArchives;
  Opts.ForceEncoding := (FSearch.EncodingIdx > 0) and
    TryTextEncodingFromListIndex(FSearch.EncodingIdx - 1, Opts.Encoding);
  if ByBytes then
  begin
    Opts.ContainingText := '';
    Opts.HexBytes := FSearch.HexText;
  end;
  // A rejected size stops here. Past this point the overlay says the search
  // is running, and Esc only cancels a walk that has already started.
  if not ApplyFindFilterText(Opts, FSearch.Filters, FilterError) then
  begin
    FSearch.Message := FilterError;
    FSearch.Phase := spResults;
    SetLength(FSearch.Results, 0);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;

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
  FFgJobKey := 'find:' + IntToStr(RunId);
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
  PluginJobUpdate(cJobOwner, FFgJobKey,
    T('ui.search.found', 'Found: %d', [0]) + #10 + Root, -1);
  PluginJobSetForeground(JobIdOf(FFgJobKey), True);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;

  FindFilesAsync(Opts, Token,
    procedure(AFoundCount: Integer; const ACurrentDir: string)
    begin
      if not Life.Alive then
        Exit;
      Bg := FindBackground(RunId);
      if Bg <> nil then
      begin
        Bg.CurrentDir := ACurrentDir;
        PluginJobUpdate(cJobOwner, Bg.JobKey,
          T('ui.search.found', 'Found: %d', [AFoundCount]) + #10 + ACurrentDir, -1);
        PluginJobSetBadge(cJobOwner, Bg.JobKey, IntToStr(AFoundCount));
        Exit;
      end;
      if (RunId <> FRunId) or (FSearch.Phase <> spRunning) then
        Exit;
      FSearch.FoundCount := AFoundCount;
      FSearch.CurrentDir := ACurrentDir;
      PluginJobUpdate(cJobOwner, 'find:' + IntToStr(RunId),
        T('ui.search.found', 'Found: %d', [AFoundCount]) + #10 + ACurrentDir, -1);
      PluginJobSetBadge(cJobOwner, 'find:' + IntToStr(RunId), IntToStr(AFoundCount));
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError;
      ATruncated: Boolean)
    begin
      if not Life.Alive then
        Exit;
      Bg := FindBackground(RunId);
      if Bg <> nil then
      begin
        Bg.Done := True;
        Bg.Token := nil;
        Bg.Hits := AHits;
        if Length(AHits) = 0 then
        begin
          // Nothing to open: the job ends with a note unless the user stopped it.
          if (AError.Code <> vecCancelled) and Assigned(FOnBackgroundDone) then
            FOnBackgroundDone(0);
          DropBackground(RunId);
          Exit;
        end;
        if Bg.Opened then
        begin
          if Assigned(FOnUpdateSession) then
            FOnUpdateSession(Bg.SessionId, Bg.Root, Bg.Mask, AHits);
        end
        else if AError.Code = vecCancelled then
          // A search the user stopped shows what it found right away.
          OpenBackground(RunId)
        else if Assigned(FOnBackgroundDone) then
          FOnBackgroundDone(Length(AHits));
        if FindBackground(RunId) <> nil then
        begin
          RefreshBackgroundJob(Bg);
          // A finished search has no progress dialog to keep up.
          PluginJobSetForeground(JobIdOf(Bg.JobKey), False);
        end;
        Exit;
      end;
      if (RunId <> FRunId) or (FSearch.Phase <> spRunning) then
        Exit;
      FSearch.Cancel := nil;
      EndForegroundJob;
      // Queued so the notice opens after this callback has closed or
      // rebuilt the search UI.
      if (AError.Code = vecOk) and ATruncated and Assigned(FOnLimitReached) then
        TThread.Queue(nil,
          procedure
          begin
            if Life.Alive then
              FOnLimitReached;
          end);
      // The panel keeps whatever was found, also after a stop or an error.
      if FResultsShown then
      begin
        if Length(AHits) > 0 then
          FOnNavigateFindResults(Root, Mask, AHits, True);
        CloseSearchUi;
        Exit;
      end;
      if AError.Code = vecCancelled then
      begin
        FSearch.Phase := spNone;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        Exit;
      end;
      if (AError.Code = vecOk) and (Length(AHits) > 0) then
      begin
        CloseSearchUi;
        if Assigned(FOnNavigateFindResults) and
           FOnNavigateFindResults(Root, Mask, AHits, False) then
          Exit;
      end;
      FSearch.Results := AHits;
      FSearch.FoundCount := Length(AHits);
      FSearch.Cursor := 0;
      FSearch.Scroll := 0;
      if AError.Code <> vecOk then
        FSearch.Message := AError.Message
      else
        FSearch.Message := T('ui.search.none', 'No files found');
      FSearch.Phase := spResults;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end,
    procedure(const ANewHits: TArray<TFindHit>)
    begin
      if not Life.Alive then
        Exit;
      Bg := FindBackground(RunId);
      if Bg <> nil then
      begin
        Bg.Hits := Bg.Hits + ANewHits;
        if (Bg.SessionId <> '') and Assigned(FOnUpdateSession) then
          FOnUpdateSession(Bg.SessionId, Bg.Root, Bg.Mask, Bg.Hits);
        Exit;
      end;
      if (RunId <> FRunId) or (FSearch.Phase <> spRunning) or
         not Assigned(FOnNavigateFindResults) then
        Exit;
      FSearch.Results := FSearch.Results + ANewHits;
      FSearch.FoundCount := Length(FSearch.Results);
      if FOnNavigateFindResults(Root, Mask, FSearch.Results, FResultsShown) then
        FResultsShown := True;
    end);
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
  Y, ViewH, Idx, MaxW: Integer;
  Line, Path, Rel, InnerPath: string;
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

  case FSearch.Phase of
    spRunning:
      Title := T('ui.search.running', 'Searching') + cEllipsis;
    spResults:
      Title := T('ui.search.results', 'Results: %d', [Length(FSearch.Results)]);
  else
    Title := T('ui.search.title', 'Find');
  end;
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
        if FSearch.Cursor < FSearch.Scroll then
          FSearch.Scroll := FSearch.Cursor;
        if FSearch.Cursor >= FSearch.Scroll + ViewH then
          FSearch.Scroll := FSearch.Cursor - ViewH + 1;
        if FSearch.Scroll < 0 then
          FSearch.Scroll := 0;

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
          Path := FSearch.Results[Idx].Path;
          Rel := Path;
          InnerPath := '';
          if SplitArchiveHit(Path, Rel, InnerPath) then
            InnerPath := ' : ' + InnerPath;
          if FSearch.RootPath <> '' then
          begin
            if Rel.StartsWith(IncludeTrailingPathDelimiter(FSearch.RootPath), True) then
              Rel := Copy(Rel, Length(IncludeTrailingPathDelimiter(FSearch.RootPath)) + 1,
                MaxInt)
            else if SameLocalPath(Rel, FSearch.RootPath) then
              Rel := ExtractFileName(Rel);
          end;
          Rel := Rel + InnerPath;
          if Length(Rel) > R.Width - 2 then
            Rel := Copy(Rel, 1, R.Width - 3) + '~';
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
  if AKey = vkEscape then
  begin
    CloseSearchUi;
    AKey := 0;
    Exit;
  end;
  if AKey = vkTab then
  begin
    FSearch.FocusField := 1 - FSearch.FocusField;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkReturn then
  begin
    StartSearch;
    AKey := 0;
    Exit;
  end;
  if FSearch.FocusField = 1 then
  begin
    if (AKey = vkSpace) or (AKeyChar = ' ') then
    begin
      FSearch.Subdirs := not FSearch.Subdirs;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkBack then
  begin
    if FSearch.Mask <> '' then
    begin
      Delete(FSearch.Mask, Length(FSearch.Mask), 1);
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end;
    AKey := 0;
    Exit;
  end;
  if TKeyChord.Make(AKey, AKeyChar, AShift).IsPrintable and TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([], [ssShift]) then
  begin
    FSearch.Mask := FSearch.Mask + AKeyChar;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
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
