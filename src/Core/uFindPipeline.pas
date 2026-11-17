unit uFindPipeline;

{ Alt+F7 search in two stages (docs/PLUGIN_SERVICES.md, section "search.files").

  The first stage lists the files by name, mask, size and date: a provider that lists the
  "list" capability (Everything), or the built-in walk. Its hits are fed to the second stage
  in batches while the listing goes on: a provider that lists the "files" capability (ripgrep)
  is given the paths and looks for the text in those files only, or the built-in code reads
  them. Files of a kind the text extractor serves always go to the built-in code, as a
  provider reads files as they are. A hit of the search is a file that passed both stages.

  A first-stage provider that fails before its first hit hands the listing to the walk; a
  second-stage provider that fails before the first hit of a batch hands that batch and the
  following ones to the built-in code. Everything runs on the main thread except the
  built-in content checks, which run on a worker and report back to the main thread. }

interface

uses
  System.SysUtils, uVfsTypes, uFileFind;

type
  TFindPipelinePlan = record
    /// <summary>Plugin id of the provider that lists the files; '' = the built-in walk.</summary>
    NameProvider: string;
    /// <summary>Plugin id of the provider that looks for the text; '' = the built-in code.</summary>
    ContentProvider: string;
  end;

/// <summary>Starts the pipeline; the result goes to AOnDone like a FindFilesAsync search.
/// Called on the main thread. AOptions carry the text extractor, AWalkOptions are the options
/// of the whole built-in walk, used when the first stage cannot start.</summary>
procedure RunFindPipeline(const AOptions, AWalkOptions: TFindOptions;
  const APlan: TFindPipelinePlan; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback;
  AOnHits: TFindHitsCallback);

implementation

uses
  System.Classes, System.SyncObjs, System.Generics.Collections, uJsonRpc, uFindService,
  uPluginServiceHost;

const
  /// <summary>The longest silence of a provider.</summary>
  cProviderSilenceMs = 30000;
  cCancelPollMs = 100;
  /// <summary>The most characters of paths in one batch of the second stage; a command line
  /// holds some 32000 on Windows.</summary>
  cBatchChars = 16000;
  cFlushMs = 300;

type
  /// <summary>Stops the stages of one pipeline; also stops when the caller's token does.</summary>
  TStageToken = class(TInterfacedObject, IJobCancelToken)
  private
    FParent: IJobCancelToken;
    FStopped: Boolean;
  public
    constructor Create(AParent: IJobCancelToken);
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

  IFindPipelineRun = interface
    ['{5E0B7A52-8C1D-4F5E-9A47-2B6C3D9E1F08}']
  end;

  TFindPipeline = class(TInterfacedObject, IFindPipelineRun)
  private
    FOpts, FWalkOpts, FNameOpts: TFindOptions;
    FPlan: TFindPipelinePlan;
    FCancel: IJobCancelToken;
    FToken: IJobCancelToken;
    FOnProgress: TFindProgressCallback;
    FOnDone: TFindDoneCallback;
    FOnHits: TFindHitsCallback;
    FPending: TList<TFindHit>;
    FPendingChars: Integer;
    FHits: TList<TFindHit>;
    FLimit: Integer;
    FStage1Done, FStopped, FFinished, FTruncated: Boolean;
    FStage1Seen: Integer;
    FStage1Err: TVfsError;
    FInFlight: Integer;
    FJob1, FJob2: Int64;
    FJob1Active, FJob2Active: Boolean;
    FWatchDone: Integer;
    procedure StartWatcher;
    procedure StartWalkStage1;
    procedure StartProviderStage1;
    procedure Stage1Finished(const AErr: TVfsError; ATruncated: Boolean);
    procedure Feed(const AHits: TArray<TFindHit>);
    procedure AddFinal(const AHits: TArray<TFindHit>);
    procedure StopStages;
    procedure DispatchBatch;
    procedure RunProviderPart(const AFiles: TArray<TFindHit>);
    procedure RunBuiltInPart(const AFiles: TArray<TFindHit>);
    procedure PartDone;
    procedure Pump;
    procedure Finish;
  public
    constructor Create(const AOptions, AWalkOptions: TFindOptions; const APlan: TFindPipelinePlan;
      ACancel: IJobCancelToken; AOnProgress: TFindProgressCallback;
      AOnDone: TFindDoneCallback; AOnHits: TFindHitsCallback);
    destructor Destroy; override;
    procedure Start;
  end;

constructor TStageToken.Create(AParent: IJobCancelToken);
begin
  inherited Create;
  FParent := AParent;
end;

function TStageToken.IsCancellationRequested: Boolean;
begin
  Result := FStopped or JobCancelRequested(FParent);
end;

procedure TStageToken.Cancel;
begin
  FStopped := True;
end;

constructor TFindPipeline.Create(const AOptions, AWalkOptions: TFindOptions;
  const APlan: TFindPipelinePlan; ACancel: IJobCancelToken; AOnProgress: TFindProgressCallback;
  AOnDone: TFindDoneCallback; AOnHits: TFindHitsCallback);
begin
  inherited Create;
  FOpts := AOptions;
  FWalkOpts := AWalkOptions;
  FPlan := APlan;
  FCancel := ACancel;
  FOnProgress := AOnProgress;
  FOnDone := AOnDone;
  FOnHits := AOnHits;
  FPending := TList<TFindHit>.Create;
  FHits := TList<TFindHit>.Create;
  FToken := TStageToken.Create(ACancel);
  FStage1Err := TVfsError.Ok;
  FLimit := FOpts.MaxResults;
  if FLimit <= 0 then
    FLimit := cFindMaxResults;
  // The first stage lists names only: no text, no folders, as many as the index holds.
  FNameOpts := FOpts;
  FNameOpts.ContainingText := '';
  FNameOpts.TextExtract := nil;
  FNameOpts.OnlyExtractable := False;
  FNameOpts.SearchFolders := False;
  FNameOpts.MaxResults := cFindMaxResults;
end;

destructor TFindPipeline.Destroy;
begin
  FHits.Free;
  FPending.Free;
  inherited;
end;

procedure TFindPipeline.StartWatcher;
var
  Keep: IFindPipelineRun;
  Me: TFindPipeline;
begin
  if FCancel = nil then
    Exit;
  Keep := Self;
  Me := Self;
  TThread.CreateAnonymousThread(
    procedure
    begin
      // Keep is captured here: the pipeline lives while the watcher polls.
      if Keep = nil then
        Exit;
      while TInterlocked.CompareExchange(Me.FWatchDone, 0, 0) = 0 do
      begin
        if Me.FCancel.IsCancellationRequested then
        begin
          TThread.Queue(nil,
            procedure
            begin
              Me.Pump;
            end);
          Break;
        end;
        Sleep(cCancelPollMs);
      end;
    end).Start;
end;

procedure TFindPipeline.Start;
begin
  StartWatcher;
  if FPlan.NameProvider = '' then
    StartWalkStage1
  else
    StartProviderStage1;
end;

procedure TFindPipeline.StartWalkStage1;
var
  Keep: IFindPipelineRun;
  Me: TFindPipeline;
begin
  Keep := Self;
  Me := Self;
  FindFilesAsync(FNameOpts, FToken,
    procedure(AFound: Integer; const ADir: string)
    begin
      if Assigned(Me.FOnProgress) and not Me.FFinished then
        Me.FOnProgress(Me.FHits.Count, ADir);
    end,
    procedure(const AHits: TArray<TFindHit>; const AError: TVfsError; ATruncated: Boolean)
    begin
      Me.Stage1Finished(AError, ATruncated);
      Keep := nil;
    end,
    procedure(const ANew: TArray<TFindHit>)
    begin
      Me.Feed(ANew);
    end);
end;

procedure TFindPipeline.StartProviderStage1;
var
  Keep: IFindPipelineRun;
  Me: TFindPipeline;
  Code: Integer;
begin
  Keep := Self;
  Me := Self;
  FJob1Active := True;
  Code := ServiceCallAsync(cSearchFilesService, FPlan.NameProvider,
    BuildSearchFilesRequest(FNameOpts, 1), cProviderSilenceMs,
    procedure(AJobId: Int64; const AMessageJson: string)
    var
      Msg: TRpcMessage;
      ParseCode: Integer;
      Fresh: TArray<TFindHit>;
      Outcome: TSearchFilesResult;
      Err: TVfsError;
    begin
      if not TryParseRpcMessage(AMessageJson, Msg, ParseCode) then
        Exit;
      if Msg.Kind = rkNotification then
      begin
        if TryParseSearchHits(AMessageJson, Fresh) then
        begin
          Inc(Me.FStage1Seen, Length(Fresh));
          Me.Feed(Fresh);
        end;
        Exit;
      end;
      if Msg.Kind <> rkResponse then
        Exit;
      Me.FJob1Active := False;
      Outcome := ParseSearchFilesResult(AMessageJson);
      if Outcome.Failed and (Me.FStage1Seen = 0) and not Me.FStopped and
         not JobCancelRequested(Me.FCancel) then
      begin
        // The provider could not list: the walk does.
        Me.StartWalkStage1;
      end
      else
      begin
        if Outcome.Failed and (Outcome.ErrorCode <> cRpcCancelled) then
          Err := TVfsError.Make(vecIOError, Outcome.ErrorText, Me.FOpts.RootPath)
        else
          Err := TVfsError.Ok;
        Me.Stage1Finished(Err, Outcome.Truncated);
      end;
      Keep := nil;
    end, FJob1);
  if Code <> 0 then
  begin
    FJob1Active := False;
    StartWalkStage1;
    Keep := nil;
  end;
end;

procedure TFindPipeline.Stage1Finished(const AErr: TVfsError; ATruncated: Boolean);
begin
  FStage1Done := True;
  FStage1Err := AErr;
  if ATruncated then
    FTruncated := True;
  Pump;
end;

procedure TFindPipeline.Feed(const AHits: TArray<TFindHit>);
var
  Hit: TFindHit;
begin
  if FStopped or FFinished then
    Exit;
  for Hit in AHits do
  begin
    // The text is looked for in files; the bounds of a provider that ignores them are applied here.
    if Hit.HasEntry and Hit.Entry.IsDirectory then
      Continue;
    if FindHitNeedsBoundCheck(FOpts) and not FindHitWithinBounds(FOpts, Hit) then
      Continue;
    FPending.Add(Hit);
    Inc(FPendingChars, Length(Hit.Path) + 3);
  end;
  Pump;
end;

procedure TFindPipeline.AddFinal(const AHits: TArray<TFindHit>);
var
  Hit: TFindHit;
  Fresh: TList<TFindHit>;
begin
  if FFinished then
    Exit;
  Fresh := TList<TFindHit>.Create;
  try
    for Hit in AHits do
    begin
      if FHits.Count >= FLimit then
      begin
        FTruncated := True;
        StopStages;
        Break;
      end;
      FHits.Add(Hit);
      Fresh.Add(Hit);
    end;
    if Fresh.Count > 0 then
    begin
      if Assigned(FOnHits) then
        FOnHits(Fresh.ToArray);
      if Assigned(FOnProgress) then
        FOnProgress(FHits.Count, FOpts.RootPath);
    end;
  finally
    Fresh.Free;
  end;
end;

procedure TFindPipeline.StopStages;
begin
  if FStopped then
    Exit;
  FStopped := True;
  FToken.Cancel;
  if FJob1Active then
    ServiceCancel(FJob1);
  if FJob2Active then
    ServiceCancel(FJob2);
end;

procedure TFindPipeline.DispatchBatch;
var
  Batch, ByProvider, ByCode: TList<TFindHit>;
  Chars, Taken: Integer;
  Hit: TFindHit;
begin
  Batch := TList<TFindHit>.Create;
  ByProvider := TList<TFindHit>.Create;
  ByCode := TList<TFindHit>.Create;
  try
    Chars := 0;
    Taken := 0;
    while (Taken < FPending.Count) and (Chars < cBatchChars) do
    begin
      Batch.Add(FPending[Taken]);
      Inc(Chars, Length(FPending[Taken].Path) + 3);
      Inc(Taken);
    end;
    FPending.DeleteRange(0, Taken);
    Dec(FPendingChars, Chars);
    for Hit in Batch do
      if (FPlan.ContentProvider <> '') and not ((FOpts.TextExtract <> nil) and
         FOpts.TextExtract.Serves(ExtractFileExt(Hit.Path))) then
        ByProvider.Add(Hit)
      else
        ByCode.Add(Hit);
    // Both parts are counted before either starts: one may end at once.
    if ByProvider.Count > 0 then
      Inc(FInFlight);
    if ByCode.Count > 0 then
      Inc(FInFlight);
    if ByProvider.Count > 0 then
      RunProviderPart(ByProvider.ToArray);
    if ByCode.Count > 0 then
      RunBuiltInPart(ByCode.ToArray);
  finally
    ByCode.Free;
    ByProvider.Free;
    Batch.Free;
  end;
end;

procedure TFindPipeline.RunProviderPart(const AFiles: TArray<TFindHit>);
var
  Keep: IFindPipelineRun;
  Me: TFindPipeline;
  Paths: TArray<string>;
  Files: TArray<TFindHit>;
  Got: Integer;
  ContentOpts: TFindOptions;
  Code: Integer;
  I: Integer;
begin
  Keep := Self;
  Me := Self;
  Files := AFiles;
  SetLength(Paths, Length(Files));
  for I := 0 to High(Files) do
    Paths[I] := Files[I].Path;
  ContentOpts := FOpts;
  ContentOpts.Mask := '*.*';
  ContentOpts.Subdirs := True;
  ContentOpts.MinSize := -1;
  ContentOpts.MaxSize := -1;
  ContentOpts.ModifiedFrom := 0;
  ContentOpts.ModifiedTo := 0;
  Got := 0;
  FJob2Active := True;
  Code := ServiceCallAsync(cSearchFilesService, FPlan.ContentProvider,
    BuildSearchFilesRequest(ContentOpts, 1, Paths), cProviderSilenceMs,
    procedure(AJobId: Int64; const AMessageJson: string)
    var
      Msg: TRpcMessage;
      ParseCode: Integer;
      Fresh: TArray<TFindHit>;
      Outcome: TSearchFilesResult;
    begin
      if not TryParseRpcMessage(AMessageJson, Msg, ParseCode) then
        Exit;
      if Msg.Kind = rkNotification then
      begin
        if TryParseSearchHits(AMessageJson, Fresh) then
        begin
          Inc(Got, Length(Fresh));
          Me.AddFinal(Fresh);
        end;
        Exit;
      end;
      if Msg.Kind <> rkResponse then
        Exit;
      Me.FJob2Active := False;
      Outcome := ParseSearchFilesResult(AMessageJson);
      if Outcome.Failed and (Got = 0) and not Me.FStopped and
         not JobCancelRequested(Me.FCancel) then
      begin
        // The provider could not read the files: the built-in code does, from here on too.
        Me.FPlan.ContentProvider := '';
        Me.RunBuiltInPart(Files);
      end
      else
        Me.PartDone;
      Keep := nil;
    end, FJob2);
  if Code <> 0 then
  begin
    FJob2Active := False;
    FPlan.ContentProvider := '';
    RunBuiltInPart(Files);
    Keep := nil;
  end;
end;

procedure TFindPipeline.RunBuiltInPart(const AFiles: TArray<TFindHit>);
var
  Keep: IFindPipelineRun;
  Me: TFindPipeline;
  Files: TArray<TFindHit>;
  Opts: TFindOptions;
  Token: IJobCancelToken;
begin
  Keep := Self;
  Me := Self;
  Files := AFiles;
  Opts := FOpts;
  Token := FToken;
  TThread.CreateAnonymousThread(
    procedure
    var
      Found: TList<TFindHit>;
      Hit, Kept: TFindHit;
      Line: Integer;
      Snippet: string;
      Tick: UInt64;

      procedure Flush;
      var
        Batch: TArray<TFindHit>;
      begin
        if Found.Count = 0 then
          Exit;
        Batch := Found.ToArray;
        Found.Clear;
        TThread.Queue(nil,
          procedure
          begin
            Me.AddFinal(Batch);
          end);
      end;

    begin
      Found := TList<TFindHit>.Create;
      try
        Tick := TThread.GetTickCount64;
        for Hit in Files do
        begin
          if JobCancelRequested(Token) then
            Break;
          if FindContentMatch(Hit.Path, Opts, Line, Snippet) then
          begin
            Kept := Hit;
            Kept.Line := Line;
            Kept.Snippet := Snippet;
            Found.Add(Kept);
          end;
          if TThread.GetTickCount64 - Tick >= cFlushMs then
          begin
            Flush;
            Tick := TThread.GetTickCount64;
          end;
        end;
        Flush;
      finally
        Found.Free;
      end;
      // Queued after the hits, so the hits are in before the part ends.
      TThread.Queue(nil,
        procedure
        begin
          Me.PartDone;
          Keep := nil;
        end);
    end).Start;
end;

procedure TFindPipeline.PartDone;
begin
  if FInFlight > 0 then
    Dec(FInFlight);
  Pump;
end;

procedure TFindPipeline.Pump;
begin
  if FFinished then
    Exit;
  if not FStopped and JobCancelRequested(FCancel) then
    StopStages;
  while not FStopped and (FInFlight = 0) and (FPending.Count > 0) do
    DispatchBatch;
  if FStage1Done and (FInFlight = 0) and (FStopped or (FPending.Count = 0)) then
    Finish;
end;

procedure TFindPipeline.Finish;
var
  Err: TVfsError;
begin
  if FFinished then
    Exit;
  FFinished := True;
  TInterlocked.Exchange(FWatchDone, 1);
  if JobCancelRequested(FCancel) then
    Err := TVfsError.Make(vecCancelled, 'Cancelled', FOpts.RootPath)
  else
    Err := FStage1Err;
  if Assigned(FOnDone) then
    FOnDone(FHits.ToArray, Err, FTruncated);
end;

procedure RunFindPipeline(const AOptions, AWalkOptions: TFindOptions;
  const APlan: TFindPipelinePlan; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback;
  AOnHits: TFindHitsCallback);
var
  Run: TFindPipeline;
  Keep: IFindPipelineRun;
begin
  Run := TFindPipeline.Create(AOptions, AWalkOptions, APlan, ACancel, AOnProgress,
    AOnDone, AOnHits);
  Keep := Run;
  Run.Start;
end;

end.
