unit uFindRouter;

{ Alt+F7 search through a service provider (docs/PLUGIN_SERVICES.md, section
  "search.files") with the built-in walk of uFileFind as the fallback.

  FindFilesRouted has the signature of FindFilesAsync and is called on the main
  thread. When a provider of search.files lists every capability the options
  need, the search runs there: the hits go to AOnHits as they arrive and
  the hits outside the size and date bounds are dropped. A provider that fails
  before its first hit hands the search to the walk; one that fails later ends
  the search with the hits found so far. Without a provider, or for options a
  provider cannot serve, the walk runs at once. When the options name a provider
  (Engine, ContentEngine), only that one is asked; if it cannot serve them, the walk runs.

  A search with a text and a mask or bounds that leave files out runs as a pipeline
  (uFindPipeline): the first stage lists the names, the second looks for the text in the
  files found. A text with an open mask goes to one provider. }

interface

uses
  System.SysUtils, uVfsTypes, uFileFind;

type
  /// <summary>Loads the plugins that list a service name in their manifest; True
  /// when one was loaded.</summary>
  TServiceLazyLoad = reference to function(const AName: string): Boolean;

procedure SetServiceLazyLoad(ALoad: TServiceLazyLoad);

procedure FindFilesRouted(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback;
  AOnHits: TFindHitsCallback = nil);

implementation

uses
  System.Classes, System.SyncObjs, System.Generics.Collections, uJsonRpc, uFindService, uFindPipeline,
  uServiceRegistry, uPluginServiceHost, uTextExtractService;

const
  /// <summary>The longest silence of a search provider.</summary>
  cFindProviderSilenceMs = 30000;
  cCancelPollMs = 100;

var
  GLazyLoad: TServiceLazyLoad;

procedure SetServiceLazyLoad(ALoad: TServiceLazyLoad);
begin
  GLazyLoad := ALoad;
end;

/// <summary>The provider that serves the capability words: the one the user chose (AEngine),
/// which serves them or no provider does, or the best one.</summary>
function ResolveProvider(const AEngine: string; const ANeeds: TArray<string>;
  out APluginId: string): Boolean;
begin
  if AEngine <> '' then
  begin
    APluginId := AEngine;
    Result := ServiceRegistry.ProviderServes(cSearchFilesService, APluginId, ANeeds);
    if not Result and Assigned(GLazyLoad) and GLazyLoad(cSearchFilesService) then
      Result := ServiceRegistry.ProviderServes(cSearchFilesService, APluginId, ANeeds);
    Exit;
  end;
  Result := ServiceRegistry.PickProvider(cSearchFilesService, ANeeds, APluginId);
  if not Result and Assigned(GLazyLoad) and GLazyLoad(cSearchFilesService) then
    Result := ServiceRegistry.PickProvider(cSearchFilesService, ANeeds, APluginId);
end;

/// <summary>The providers of the two stages for a search with a text, or False when the search
/// is served as a whole. A pipeline needs a first stage that lists the names (a provider, or
/// the walk when the user chose it) and runs when the user named a first-stage provider or
/// when the mask or bounds leave out files: otherwise one provider reading the whole tree is
/// quicker than listing every file first.</summary>
function PlanPipeline(const AOptions: TFindOptions; out APlan: TFindPipelinePlan): Boolean;
var
  NameNeeds, ContentNeeds: TArray<string>;
  Named: Boolean;
begin
  Result := False;
  APlan := Default(TFindPipelinePlan);
  if (AOptions.ContainingText = '') or AOptions.ContentBuiltIn and AOptions.NameBuiltIn then
    Exit;
  Named := AOptions.Engine <> '';
  if not (Named or FindOptionsSelective(AOptions)) then
    Exit;
  NameNeeds := FindNameNeeds(AOptions);
  ContentNeeds := FindContentNeeds(AOptions);
  if not AOptions.NameBuiltIn then
    if not ResolveProvider(AOptions.Engine, NameNeeds, APlan.NameProvider) then
      Exit;
  if not AOptions.ContentBuiltIn then
    if not ResolveProvider(AOptions.ContentEngine, ContentNeeds, APlan.ContentProvider) then
      APlan.ContentProvider := '';
  // Names by the walk and text by the built-in code is the plain walk.
  Result := (APlan.NameProvider <> '') or (APlan.ContentProvider <> '');
end;

procedure FindFilesRouted(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback;
  AOnHits: TFindHitsCallback);
var
  Opts, WalkOpts: TFindOptions;
  Seen: TDictionary<string, Boolean>;
  Plugin: string;
  Hits: TList<TFindHit>;
  Limit, Finished: Integer;
  Job: Int64;
  LimitHit: Boolean;
  Code: Integer;
  Plan: TFindPipelinePlan;
  AllBuiltIn: Boolean;
  Engine: string;
begin
  Opts := AOptions;
  if Trim(Opts.Mask) = '' then
    Opts.Mask := '*.*';
  AllBuiltIn := Opts.BuiltInOnly or
    (Opts.NameBuiltIn and (Opts.ContentBuiltIn or (Opts.ContainingText = '')));
  // Documents are searched by their text when a plugin extracts it.
  WalkOpts := AOptions;
  if (Opts.ContainingText <> '') and not Opts.BuiltInOnly and (Opts.TextExtract = nil) then
  begin
    if Assigned(GLazyLoad) then
      GLazyLoad(cTextExtractService);
    WalkOpts.TextExtract := CreateServiceTextExtractor(ACancel);
    Opts.TextExtract := WalkOpts.TextExtract;
  end;
  if AllBuiltIn or not FindOptionsServable(Opts) then
  begin
    FindFilesAsync(WalkOpts, ACancel, AOnProgress, AOnDone, AOnHits);
    Exit;
  end;
  if PlanPipeline(Opts, Plan) then
  begin
    RunFindPipeline(Opts, WalkOpts, Plan, ACancel, AOnProgress, AOnDone, AOnHits);
    Exit;
  end;
  // One provider serves the whole search: the first-stage choice for a search by name, the
  // second-stage choice for a search with a text.
  if Opts.ContainingText <> '' then
  begin
    Engine := Opts.ContentEngine;
    if Opts.ContentBuiltIn then
    begin
      FindFilesAsync(WalkOpts, ACancel, AOnProgress, AOnDone, AOnHits);
      Exit;
    end;
  end
  else
    Engine := Opts.Engine;
  if not ResolveProvider(Engine, FindServiceNeeds(Opts), Plugin) then
  begin
    FindFilesAsync(WalkOpts, ACancel, AOnProgress, AOnDone, AOnHits);
    Exit;
  end;

  Hits := TList<TFindHit>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Limit := Opts.MaxResults;
  if Limit <= 0 then
    Limit := cFindMaxResults;
  LimitHit := False;
  Finished := 0;
  Job := 0;

  Code := ServiceCallAsync(cSearchFilesService, Plugin, BuildSearchFilesRequest(Opts, 1),
    cFindProviderSilenceMs,
    procedure(AJobId: Int64; const AMessageJson: string)
    var
      Fresh, Kept: TArray<TFindHit>;
      Hit: TFindHit;
      N: Integer;
      Outcome: TSearchFilesResult;
      Err: TVfsError;
      Msg: TRpcMessage;
      ParseCode: Integer;
      Cancelled, Supplement, ProviderTruncated: Boolean;
      Extra: TFindOptions;
    begin
      if not TryParseRpcMessage(AMessageJson, Msg, ParseCode) then
        Exit;
      if Msg.Kind = rkNotification then
      begin
        if not TryParseSearchHits(AMessageJson, Fresh) then
          Exit;
        SetLength(Kept, Length(Fresh));
        N := 0;
        for Hit in Fresh do
        begin
          if FindHitNeedsBoundCheck(Opts) and not FindHitWithinBounds(Opts, Hit) then
            Continue;
          if Hits.Count >= Limit then
          begin
            LimitHit := True;
            Break;
          end;
          Hits.Add(Hit);
          Seen.AddOrSetValue(LowerCase(Hit.Path), True);
          Kept[N] := Hit;
          Inc(N);
        end;
        SetLength(Kept, N);
        if Length(Kept) > 0 then
        begin
          if Assigned(AOnHits) then
            AOnHits(Kept);
          if Assigned(AOnProgress) then
            AOnProgress(Hits.Count, Opts.RootPath);
        end;
        Exit;
      end;
      if Msg.Kind <> rkResponse then
        Exit;

      TInterlocked.Exchange(Finished, 1);
      Outcome := ParseSearchFilesResult(AMessageJson);
      Cancelled := JobCancelRequested(ACancel) or (Outcome.ErrorCode = cRpcCancelled);
      Supplement := False;
      try
        if Cancelled then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath)
        else if Outcome.Failed and (Hits.Count = 0) then
        begin
          FindFilesAsync(WalkOpts, ACancel, AOnProgress, AOnDone, AOnHits);
          Exit;
        end
        else if Outcome.Failed then
          Err := TVfsError.Make(vecIOError, Outcome.ErrorText, Opts.RootPath)
        else
          Err := TVfsError.Ok;
        if not Cancelled and not Outcome.Failed and Assigned(Opts.TextExtract) and
           (Hits.Count < Limit) then
        begin
          // The provider reads files as they are; the documents are searched here by
          // their text, and the files it found already are not listed twice.
          Supplement := True;
          ProviderTruncated := LimitHit or Outcome.Truncated;
          Extra := WalkOpts;
          Extra.OnlyExtractable := True;
          Extra.MaxResults := Limit - Hits.Count;
          FindFilesAsync(Extra, ACancel, AOnProgress,
            procedure(const AFound: TArray<TFindHit>; const AError: TVfsError;
              ATruncated: Boolean)
            var
              H: TFindHit;
            begin
              try
                for H in AFound do
                  if not Seen.ContainsKey(LowerCase(H.Path)) then
                  begin
                    Seen.Add(LowerCase(H.Path), True);
                    Hits.Add(H);
                  end;
                if Assigned(AOnDone) then
                  AOnDone(Hits.ToArray, AError, ProviderTruncated or ATruncated);
              finally
                Seen.Free;
                Hits.Free;
              end;
            end,
            procedure(const ANew: TArray<TFindHit>)
            var
              Fresh: TArray<TFindHit>;
              H: TFindHit;
            begin
              SetLength(Fresh, 0);
              for H in ANew do
                if not Seen.ContainsKey(LowerCase(H.Path)) then
                begin
                  Seen.Add(LowerCase(H.Path), True);
                  Hits.Add(H);
                  SetLength(Fresh, Length(Fresh) + 1);
                  Fresh[High(Fresh)] := H;
                end;
              if (Length(Fresh) > 0) and Assigned(AOnHits) then
                AOnHits(Fresh);
            end);
          Exit;
        end;
        if Assigned(AOnDone) then
          AOnDone(Hits.ToArray, Err, LimitHit or Outcome.Truncated);
      finally
        if not Supplement then
        begin
          Seen.Free;
          Hits.Free;
        end;
      end;
    end, Job);

  if Code <> 0 then
  begin
    Seen.Free;
    Hits.Free;
    FindFilesAsync(WalkOpts, ACancel, AOnProgress, AOnDone, AOnHits);
    Exit;
  end;

  // The provider is told to stop when the caller's token is cancelled; the
  // thread ends with the call.
  if Assigned(ACancel) then
    TThread.CreateAnonymousThread(
      procedure
      begin
        while TInterlocked.CompareExchange(Finished, 0, 0) = 0 do
        begin
          if ACancel.IsCancellationRequested then
          begin
            TThread.Queue(nil,
              procedure
              begin
                ServiceCancel(Job);
              end);
            Break;
          end;
          Sleep(cCancelPollMs);
        end;
      end).Start;
end;

end.
