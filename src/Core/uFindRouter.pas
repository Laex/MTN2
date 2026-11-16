unit uFindRouter;

{ Alt+F7 search through a service provider (docs/PLUGIN_SERVICES.md, section
  "search.files") with the built-in walk of uFileFind as the fallback.

  FindFilesRouted has the signature of FindFilesAsync and is called on the main
  thread. When a provider of search.files lists every capability the options
  need, the search runs there: the hits go to AOnHits as they arrive and
  the hits outside the size and date bounds are dropped. A provider that fails
  before its first hit hands the search to the walk; one that fails later ends
  the search with the hits found so far. Without a provider, or for options a
  provider cannot serve, the walk runs at once. }

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
  System.Classes, System.SyncObjs, System.Generics.Collections, uJsonRpc, uFindService,
  uServiceRegistry, uPluginServiceHost;

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

function PickSearchProvider(const AOptions: TFindOptions; out APluginId: string): Boolean;
var
  Needs: TArray<string>;
begin
  Needs := FindServiceNeeds(AOptions);
  Result := ServiceRegistry.PickProvider(cSearchFilesService, Needs, APluginId);
  if not Result and Assigned(GLazyLoad) and GLazyLoad(cSearchFilesService) then
    Result := ServiceRegistry.PickProvider(cSearchFilesService, Needs, APluginId);
end;

procedure FindFilesRouted(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback;
  AOnHits: TFindHitsCallback);
var
  Opts: TFindOptions;
  Plugin: string;
  Hits: TList<TFindHit>;
  Limit, Finished: Integer;
  Job: Int64;
  LimitHit: Boolean;
  Code: Integer;
begin
  Opts := AOptions;
  if Trim(Opts.Mask) = '' then
    Opts.Mask := '*.*';
  if not FindOptionsServable(Opts) or not PickSearchProvider(Opts, Plugin) then
  begin
    FindFilesAsync(AOptions, ACancel, AOnProgress, AOnDone, AOnHits);
    Exit;
  end;

  Hits := TList<TFindHit>.Create;
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
      Outcome: TSearchFilesResult;
      Err: TVfsError;
      Msg: TRpcMessage;
      ParseCode: Integer;
      Cancelled: Boolean;
    begin
      if not TryParseRpcMessage(AMessageJson, Msg, ParseCode) then
        Exit;
      if Msg.Kind = rkNotification then
      begin
        if not TryParseSearchHits(AMessageJson, Fresh) then
          Exit;
        SetLength(Kept, 0);
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
          SetLength(Kept, Length(Kept) + 1);
          Kept[High(Kept)] := Hit;
        end;
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
      try
        if Cancelled then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath)
        else if Outcome.Failed and (Hits.Count = 0) then
        begin
          FindFilesAsync(AOptions, ACancel, AOnProgress, AOnDone, AOnHits);
          Exit;
        end
        else if Outcome.Failed then
          Err := TVfsError.Make(vecIOError, Outcome.ErrorText, Opts.RootPath)
        else
          Err := TVfsError.Ok;
        if Assigned(AOnDone) then
          AOnDone(Hits.ToArray, Err, LimitHit or Outcome.Truncated);
      finally
        Hits.Free;
      end;
    end, Job);

  if Code <> 0 then
  begin
    Hits.Free;
    FindFilesAsync(AOptions, ACancel, AOnProgress, AOnDone, AOnHits);
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
