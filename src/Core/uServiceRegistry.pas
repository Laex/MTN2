unit uServiceRegistry;

{ Registry and router of the plugin services (docs/PLUGIN_SERVICES.md).

  A provider registers a service name with a handler. A caller sends a
  JSON-RPC request with Call; the registry picks the provider, hands it the
  request and tracks the call as a job until the final response. The provider
  answers from any thread with Reply and Notify; both only queue the message.
  Pump, called on the thread that owns the callers (the main thread), delivers
  the queued messages in the order they were sent, so a caller's callback never
  runs on a provider's thread and the response is the last message of a job.

  Messages that break the rules are replaced, never passed on: a response with
  the wrong id or one that is not a response becomes the error -32603, a
  message over the size limit is dropped (a response becomes -32603). A job
  that sees no message from its provider for its time limit ends with -32005;
  Cancel ends a job with -32001 at once, and whatever the provider sends later
  is dropped. A provider that raises or refuses a call ends it with -32603.

  The time source is a parameter, so the tests step it by hand. }

interface

uses
  System.SysUtils, System.Generics.Collections, System.SyncObjs, uJsonRpc, uServiceSchema;

const
  /// <summary>The longest message either side may send, in UTF-8 bytes.</summary>
  cServiceMaxMessageBytes = 4 * 1024 * 1024;
  /// <summary>Open calls of one service name at a time.</summary>
  cServiceMaxOpenCalls = 8;
  /// <summary>The longest silence a call may have, in milliseconds.</summary>
  cServiceMaxTimeoutMs = 60000;
  /// <summary>Finished calls whose last status can still be read.</summary>
  cServiceKeepFinished = 64;
  cServiceDefaultPriority = 100;

type
  /// <summary>The provider's entry point. ACall is the job id for a request
  /// and 0 for a notification. True = the message was accepted.</summary>
  TServiceHandler = reference to function(ACall: Int64; const AMessageJson: string): Boolean;

  /// <summary>Receives the notifications of a job and then its response, on
  /// the thread that calls Pump.</summary>
  TServiceMessageProc = reference to procedure(AJobId: Int64; const AMessageJson: string);

  TServiceJobState = (sjsRunning, sjsDone, sjsCancelled, sjsFailed);

  TServiceJobStatus = record
    State: TServiceJobState;
    Progress, Total: Int64;
    /// <summary>The text of the last progress notification.</summary>
    Message: string;
  end;

  TServiceProviderInfo = record
    PluginId: string;
    Name: string;
    Version: Integer;
    Priority: Integer;
    Capabilities: TArray<string>;
    /// <summary>The "inputSchema" of the description as JSON; '' = none.</summary>
    InputSchema: string;
  end;

  TServiceRegistry = class
  strict private
    type
      TProvider = class
        Info: TServiceProviderInfo;
        Handler: TServiceHandler;
      end;
      TJob = class
        Id: Int64;
        Name: string;
        PluginId: string;
        RequestId: TRpcId;
        Handler: TServiceHandler;
        OnMessage: TServiceMessageProc;
        Status: TServiceJobStatus;
        TimeoutMs: Integer;
        Deadline: UInt64;
      end;
      TEntryKind = (ekReply, ekNotify, ekFinal);
      TEntry = record
        JobId: Int64;
        Kind: TEntryKind;
        Json: string;
        Oversize: Boolean;
        Callback: TServiceMessageProc;
      end;
    var
      FClock: TFunc<UInt64>;
      FProviders: TObjectList<TProvider>;
      FJobs: TDictionary<Int64, TJob>;
      FFinished: TDictionary<Int64, TServiceJobStatus>;
      FFinishedOrder: TQueue<Int64>;
      FNextJob: Int64;
      FTimedOpen: Integer;
      FInboxLock: TCriticalSection;
      FInbox: TList<TEntry>;
    function FindProvider(const AName, APluginId: string): TProvider;
    function CountOpen(const AName: string): Integer;
    procedure Enqueue(const AEntry: TEntry);
    /// <summary>Takes the job out of the open set, records its last status and
    /// queues the final message for its caller. The caller frees AJob.</summary>
    procedure Finish(AJob: TJob; AState: TServiceJobState; const AFinalJson: string);
    procedure Abort(AJob: TJob; ACode: Integer; const AText: string;
      AState: TServiceJobState; ATellProvider: Boolean);
    procedure RememberFinished(AId: Int64; const AStatus: TServiceJobStatus);
    procedure ApplyProgress(AJob: TJob; const AParamsJson: string);
    procedure Touch(AJob: TJob);
    function HandleEntry(const AEntry: TEntry): Boolean;
  public
    /// <summary>AClock returns milliseconds from any fixed start; nil = the
    /// system clock.</summary>
    constructor Create(AClock: TFunc<UInt64> = nil);
    destructor Destroy; override;

    /// <summary>Offers the service AName from plugin APluginId. 0 = accepted;
    /// otherwise the JSON-RPC error code: cRpcNotAllowed for a reserved name,
    /// cRpcInvalidParams for a bad name, version, description or handler. The
    /// same plugin registering the same name again replaces its registration.</summary>
    function RegisterService(const APluginId, AName: string; AVersion: Integer;
      const ADescribeJson: string; AHandler: TServiceHandler;
      APriority: Integer = cServiceDefaultPriority): Integer;
    /// <summary>Drops the services of APluginId; its open calls end with -32603.</summary>
    procedure UnregisterPlugin(const APluginId: string);
    /// <summary>Whether AName is a name a plugin may register.</summary>
    class function IsValidName(const AName: string): Boolean; static;
    class function IsReservedName(const AName: string): Boolean; static;

    /// <summary>The providers of AName in ascending priority order.</summary>
    function Providers(const AName: string): TArray<TServiceProviderInfo>;
    /// <summary>The first provider of AName that lists every word of ANeeds in
    /// its capabilities.</summary>
    function PickProvider(const AName: string; const ANeeds: TArray<string>;
      out APluginId: string): Boolean;
    /// <summary>Whether APluginId provides AName with every word of ANeeds.</summary>
    function ProviderServes(const AName, APluginId: string;
      const ANeeds: TArray<string>): Boolean;

    /// <summary>Starts a call. ARequestJson is a JSON-RPC request whose method
    /// is AName; APluginId '' = the first provider. Returns 0 and the job id
    /// when the job runs (its callback then gets the response, even a failure),
    /// otherwise the error code and no job; AWhy then says what is wrong. The
    /// params are checked against the provider's inputSchema first: a mismatch
    /// is cRpcInvalidParams, a broken schema cRpcInternalError. ATimeoutMs is
    /// the longest silence of the provider, 0 = no limit.</summary>
    function Call(const AName, APluginId, ARequestJson: string; ATimeoutMs: Integer;
      AOnMessage: TServiceMessageProc; out AJobId: Int64; out AWhy: string): Integer; overload;
    function Call(const AName, APluginId, ARequestJson: string; ATimeoutMs: Integer;
      AOnMessage: TServiceMessageProc; out AJobId: Int64): Integer; overload;
    /// <summary>The provider's response to a call. Any thread.</summary>
    procedure Reply(ACall: Int64; const AResponseJson: string);
    /// <summary>The provider's notification of a call. Any thread.</summary>
    procedure Notify(ACall: Int64; const ANotificationJson: string);
    /// <summary>Ends an open call with -32001 and tells its provider. False
    /// when the call is not open.</summary>
    function Cancel(AJobId: Int64): Boolean;
    /// <summary>The state of an open call, or of one of the last finished ones.</summary>
    function Status(AJobId: Int64; out AStatus: TServiceJobStatus): Boolean;
    function OpenCalls(const AName: string): Integer;
    /// <summary>How many open calls have a time limit. Readable from any thread:
    /// a timer thread uses it to know whether Tick has work.</summary>
    function TimedCalls: Integer;

    /// <summary>Delivers the queued messages to the callers. Returns how many
    /// went out.</summary>
    function Pump: Integer;
    /// <summary>Ends the calls whose provider was silent for its limit with
    /// -32005. Returns how many ended.</summary>
    function Tick: Integer;
  end;

implementation

uses
  System.Classes, System.JSON, System.Diagnostics;

function SystemClock: UInt64;
var
  Stamp, Freq: Int64;
begin
  Stamp := TStopwatch.GetTimeStamp;
  Freq := TStopwatch.Frequency;
  Result := UInt64((Stamp div Freq) * 1000 + (Stamp mod Freq) * 1000 div Freq);
end;

function MessageBytes(const AText: string): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(AText);
end;

{ TServiceRegistry }

constructor TServiceRegistry.Create(AClock: TFunc<UInt64>);
begin
  inherited Create;
  if Assigned(AClock) then
    FClock := AClock
  else
    FClock := SystemClock;
  FProviders := TObjectList<TProvider>.Create(True);
  FJobs := TDictionary<Int64, TJob>.Create;
  FFinished := TDictionary<Int64, TServiceJobStatus>.Create;
  FFinishedOrder := TQueue<Int64>.Create;
  FInboxLock := TCriticalSection.Create;
  FInbox := TList<TEntry>.Create;
end;

destructor TServiceRegistry.Destroy;
var
  Job: TJob;
begin
  for Job in FJobs.Values do
    Job.Free;
  FJobs.Free;
  FFinished.Free;
  FFinishedOrder.Free;
  FProviders.Free;
  FInbox.Free;
  FInboxLock.Free;
  inherited;
end;

class function TServiceRegistry.IsValidName(const AName: string): Boolean;
var
  I: Integer;
  AtStart: Boolean;
  C: Char;
begin
  if AName = '' then
    Exit(False);
  AtStart := True;
  for I := 1 to Length(AName) do
  begin
    C := AName[I];
    if C = '.' then
    begin
      if AtStart then
        Exit(False);
      AtStart := True;
    end
    else if AtStart then
    begin
      if not CharInSet(C, ['a'..'z']) then
        Exit(False);
      AtStart := False;
    end
    else if not CharInSet(C, ['a'..'z', '0'..'9', '_']) then
      Exit(False);
  end;
  Result := not AtStart;
end;

class function TServiceRegistry.IsReservedName(const AName: string): Boolean;
begin
  Result := AName.StartsWith('host.') or AName.StartsWith('service.') or
    (AName = 'file') or (AName = 'recycle') or (AName = 'sys') or (AName = 'find') or
    (AName = 'ws') or (AName = 'host') or (AName = 'service');
end;

function TServiceRegistry.FindProvider(const AName, APluginId: string): TProvider;
var
  P: TProvider;
begin
  for P in FProviders do
    if (P.Info.Name = AName) and ((APluginId = '') or (P.Info.PluginId = APluginId)) then
      Exit(P);
  Result := nil;
end;

function TServiceRegistry.RegisterService(const APluginId, AName: string;
  AVersion: Integer; const ADescribeJson: string; AHandler: TServiceHandler;
  APriority: Integer): Integer;
var
  Root: TJSONValue;
  Caps: TJSONValue;
  Info: TServiceProviderInfo;
  Existing, Provider: TProvider;
  I, InsertAt: Integer;
begin
  if (APluginId = '') or not IsValidName(AName) or (AVersion < 1) or not Assigned(AHandler) then
    Exit(cRpcInvalidParams);
  if IsReservedName(AName) then
    Exit(cRpcNotAllowed);
  Info := Default(TServiceProviderInfo);
  Info.PluginId := APluginId;
  Info.Name := AName;
  Info.Version := AVersion;
  Info.Priority := APriority;
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(ADescribeJson, True, False);
    except
      Root := nil;
    end;
    if not (Root is TJSONObject) then
      Exit(cRpcInvalidParams);
    Caps := TJSONObject(Root).GetValue('inputSchema');
    if Caps <> nil then
    begin
      if not (Caps is TJSONObject) then
        Exit(cRpcInvalidParams);
      Info.InputSchema := Caps.ToJSON;
    end;
    Caps := TJSONObject(Root).GetValue('capabilities');
    if Caps <> nil then
    begin
      if not (Caps is TJSONArray) then
        Exit(cRpcInvalidParams);
      SetLength(Info.Capabilities, TJSONArray(Caps).Count);
      for I := 0 to TJSONArray(Caps).Count - 1 do
      begin
        if not (TJSONArray(Caps).Items[I] is TJSONString) then
          Exit(cRpcInvalidParams);
        Info.Capabilities[I] := LowerCase(TJSONString(TJSONArray(Caps).Items[I]).Value);
      end;
    end;
  finally
    Root.Free;
  end;

  Existing := FindProvider(AName, APluginId);
  if Existing <> nil then
    FProviders.Remove(Existing);
  Provider := TProvider.Create;
  Provider.Info := Info;
  Provider.Handler := AHandler;
  // Ascending priority; among equal priorities the earlier registration stays first.
  InsertAt := FProviders.Count;
  for I := 0 to FProviders.Count - 1 do
    if FProviders[I].Info.Priority > APriority then
    begin
      InsertAt := I;
      Break;
    end;
  FProviders.Insert(InsertAt, Provider);
  Result := 0;
end;

procedure TServiceRegistry.UnregisterPlugin(const APluginId: string);
var
  Doomed: TList<TJob>;
  Job: TJob;
  I: Integer;
begin
  Doomed := TList<TJob>.Create;
  try
    for Job in FJobs.Values do
      if Job.PluginId = APluginId then
        Doomed.Add(Job);
    for Job in Doomed do
    begin
      Abort(Job, cRpcInternalError, 'the provider was unloaded', sjsFailed, False);
      Job.Free;
    end;
  finally
    Doomed.Free;
  end;
  for I := FProviders.Count - 1 downto 0 do
    if FProviders[I].Info.PluginId = APluginId then
      FProviders.Delete(I);
end;

function TServiceRegistry.Providers(const AName: string): TArray<TServiceProviderInfo>;
var
  P: TProvider;
  List: TList<TServiceProviderInfo>;
begin
  List := TList<TServiceProviderInfo>.Create;
  try
    for P in FProviders do
      if P.Info.Name = AName then
        List.Add(P.Info);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ProviderHasAll(AProvider: TServiceProviderInfo; const ANeeds: TArray<string>): Boolean;
var
  Need, Cap: string;
  Found: Boolean;
begin
  for Need in ANeeds do
  begin
    Found := False;
    for Cap in AProvider.Capabilities do
      if Cap = LowerCase(Need) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Exit(False);
  end;
  Result := True;
end;

function TServiceRegistry.PickProvider(const AName: string; const ANeeds: TArray<string>;
  out APluginId: string): Boolean;
var
  P: TProvider;
begin
  APluginId := '';
  for P in FProviders do
    if (P.Info.Name = AName) and ProviderHasAll(P.Info, ANeeds) then
    begin
      APluginId := P.Info.PluginId;
      Exit(True);
    end;
  Result := False;
end;

function TServiceRegistry.ProviderServes(const AName, APluginId: string;
  const ANeeds: TArray<string>): Boolean;
var
  P: TProvider;
begin
  for P in FProviders do
    if (P.Info.Name = AName) and SameText(P.Info.PluginId, APluginId) then
      Exit(ProviderHasAll(P.Info, ANeeds));
  Result := False;
end;

function TServiceRegistry.CountOpen(const AName: string): Integer;
var
  Job: TJob;
begin
  Result := 0;
  for Job in FJobs.Values do
    if Job.Name = AName then
      Inc(Result);
end;

function TServiceRegistry.OpenCalls(const AName: string): Integer;
begin
  Result := CountOpen(AName);
end;

function TServiceRegistry.TimedCalls: Integer;
begin
  Result := TInterlocked.CompareExchange(FTimedOpen, 0, 0);
end;

procedure TServiceRegistry.Enqueue(const AEntry: TEntry);
begin
  FInboxLock.Enter;
  try
    FInbox.Add(AEntry);
  finally
    FInboxLock.Leave;
  end;
end;

procedure TServiceRegistry.RememberFinished(AId: Int64; const AStatus: TServiceJobStatus);
begin
  FFinished.AddOrSetValue(AId, AStatus);
  FFinishedOrder.Enqueue(AId);
  while FFinishedOrder.Count > cServiceKeepFinished do
    FFinished.Remove(FFinishedOrder.Dequeue);
end;

procedure TServiceRegistry.Finish(AJob: TJob; AState: TServiceJobState;
  const AFinalJson: string);
var
  Entry: TEntry;
begin
  FJobs.Remove(AJob.Id);
  if AJob.TimeoutMs > 0 then
    TInterlocked.Decrement(FTimedOpen);
  AJob.Status.State := AState;
  RememberFinished(AJob.Id, AJob.Status);
  Entry := Default(TEntry);
  Entry.JobId := AJob.Id;
  Entry.Kind := ekFinal;
  Entry.Json := AFinalJson;
  Entry.Callback := AJob.OnMessage;
  Enqueue(Entry);
end;

procedure TServiceRegistry.Abort(AJob: TJob; ACode: Integer; const AText: string;
  AState: TServiceJobState; ATellProvider: Boolean);
var
  Cancelled: string;
begin
  Finish(AJob, AState, BuildRpcError(AJob.RequestId, ACode, AText));
  if ATellProvider and Assigned(AJob.Handler) then
  begin
    Cancelled := BuildRpcNotification('notifications/cancelled',
      '{"requestId":' + AJob.RequestId.ToJson + ',"reason":' + RpcQuote(AText) + '}');
    try
      AJob.Handler(0, Cancelled);
    except
      // A provider that raises while it is told to stop has nothing left to say.
    end;
  end;
end;

procedure TServiceRegistry.Touch(AJob: TJob);
begin
  if AJob.TimeoutMs > 0 then
    AJob.Deadline := FClock() + UInt64(AJob.TimeoutMs);
end;

function TServiceRegistry.Call(const AName, APluginId, ARequestJson: string;
  ATimeoutMs: Integer; AOnMessage: TServiceMessageProc; out AJobId: Int64): Integer;
var
  Why: string;
begin
  Result := Call(AName, APluginId, ARequestJson, ATimeoutMs, AOnMessage, AJobId, Why);
end;

function TServiceRegistry.Call(const AName, APluginId, ARequestJson: string;
  ATimeoutMs: Integer; AOnMessage: TServiceMessageProc; out AJobId: Int64;
  out AWhy: string): Integer;
var
  Msg: TRpcMessage;
  Err: Integer;
  Provider: TProvider;
  Job: TJob;
  Accepted: Boolean;
begin
  AJobId := 0;
  AWhy := '';
  if not Assigned(AOnMessage) then
    Exit(cRpcInvalidParams);
  if MessageBytes(ARequestJson) > cServiceMaxMessageBytes then
    Exit(cRpcInvalidRequest);
  if not TryParseRpcMessage(ARequestJson, Msg, Err) then
    Exit(Err);
  if (Msg.Kind <> rkRequest) or (Msg.Method <> AName) then
    Exit(cRpcInvalidRequest);
  Provider := FindProvider(AName, APluginId);
  if Provider = nil then
    Exit(cRpcMethodNotFound);
  case CheckServiceParams(Provider.Info.InputSchema, Msg.ParamsJson, AWhy) of
    scBadParams: Exit(cRpcInvalidParams);
    scBadSchema: Exit(cRpcInternalError);
  end;
  if CountOpen(AName) >= cServiceMaxOpenCalls then
    Exit(cRpcTooManyCalls);

  Inc(FNextJob);
  Job := TJob.Create;
  Job.Id := FNextJob;
  Job.Name := AName;
  Job.PluginId := Provider.Info.PluginId;
  Job.RequestId := Msg.Id;
  Job.Handler := Provider.Handler;
  Job.OnMessage := AOnMessage;
  Job.Status.State := sjsRunning;
  if ATimeoutMs > cServiceMaxTimeoutMs then
    ATimeoutMs := cServiceMaxTimeoutMs;
  if ATimeoutMs < 0 then
    ATimeoutMs := 0;
  Job.TimeoutMs := ATimeoutMs;
  if ATimeoutMs > 0 then
    TInterlocked.Increment(FTimedOpen);
  Touch(Job);
  // Open before the handler runs: a provider may answer from inside it.
  FJobs.Add(Job.Id, Job);
  AJobId := Job.Id;

  try
    Accepted := Job.Handler(Job.Id, ARequestJson);
  except
    Accepted := False;
  end;
  // The handler may have ended the call itself (Cancel); Job is then freed.
  if not Accepted and FJobs.TryGetValue(AJobId, Job) then
  begin
    Finish(Job, sjsFailed, BuildRpcError(Job.RequestId, cRpcInternalError,
      'the provider did not accept the call'));
    Job.Free;
  end;
  Result := 0;
end;

procedure TServiceRegistry.Reply(ACall: Int64; const AResponseJson: string);
var
  Entry: TEntry;
begin
  Entry := Default(TEntry);
  Entry.JobId := ACall;
  Entry.Kind := ekReply;
  Entry.Oversize := MessageBytes(AResponseJson) > cServiceMaxMessageBytes;
  if not Entry.Oversize then
    Entry.Json := AResponseJson;
  Enqueue(Entry);
end;

procedure TServiceRegistry.Notify(ACall: Int64; const ANotificationJson: string);
var
  Entry: TEntry;
begin
  if MessageBytes(ANotificationJson) > cServiceMaxMessageBytes then
    Exit;
  Entry := Default(TEntry);
  Entry.JobId := ACall;
  Entry.Kind := ekNotify;
  Entry.Json := ANotificationJson;
  Enqueue(Entry);
end;

function TServiceRegistry.Cancel(AJobId: Int64): Boolean;
var
  Job: TJob;
begin
  Result := FJobs.TryGetValue(AJobId, Job);
  if not Result then
    Exit;
  Abort(Job, cRpcCancelled, 'cancelled', sjsCancelled, True);
  Job.Free;
end;

function TServiceRegistry.Status(AJobId: Int64; out AStatus: TServiceJobStatus): Boolean;
var
  Job: TJob;
begin
  if FJobs.TryGetValue(AJobId, Job) then
  begin
    AStatus := Job.Status;
    Exit(True);
  end;
  Result := FFinished.TryGetValue(AJobId, AStatus);
end;

procedure TServiceRegistry.ApplyProgress(AJob: TJob; const AParamsJson: string);
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Value: TJSONValue;
  Int: Int64;
begin
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(AParamsJson, True, False);
    except
      Root := nil;
    end;
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    Value := Obj.GetValue('progress');
    if (Value is TJSONNumber) and TryStrToInt64(TJSONNumber(Value).Value, Int) then
      AJob.Status.Progress := Int;
    Value := Obj.GetValue('total');
    if (Value is TJSONNumber) and TryStrToInt64(TJSONNumber(Value).Value, Int) then
      AJob.Status.Total := Int;
    Value := Obj.GetValue('message');
    if Value is TJSONString then
      AJob.Status.Message := TJSONString(Value).Value;
  finally
    Root.Free;
  end;
end;

function TServiceRegistry.HandleEntry(const AEntry: TEntry): Boolean;
var
  Job: TJob;
  Msg: TRpcMessage;
  Err: Integer;
  Json: string;
  State: TServiceJobState;
begin
  Result := False;
  if AEntry.Kind = ekFinal then
  begin
    try
      AEntry.Callback(AEntry.JobId, AEntry.Json);
    except
      // A caller's callback that raises must not stop the other callers' messages.
    end;
    Exit(True);
  end;
  // A late message of a cancelled, timed out or finished job has no job left.
  if not FJobs.TryGetValue(AEntry.JobId, Job) then
    Exit;
  Touch(Job);
  if AEntry.Kind = ekNotify then
  begin
    if not TryParseRpcMessage(AEntry.Json, Msg, Err) or (Msg.Kind <> rkNotification) then
      Exit;
    if Msg.Method = 'notifications/progress' then
      ApplyProgress(Job, Msg.ParamsJson);
    try
      Job.OnMessage(Job.Id, AEntry.Json);
    except
      // See above.
    end;
    Exit(True);
  end;

  Json := AEntry.Json;
  State := sjsDone;
  if AEntry.Oversize then
  begin
    Json := BuildRpcError(Job.RequestId, cRpcInternalError, 'the response is too large');
    State := sjsFailed;
  end
  else if not TryParseRpcMessage(AEntry.Json, Msg, Err) or (Msg.Kind <> rkResponse) or
    not Msg.Id.SameAs(Job.RequestId) then
  begin
    Json := BuildRpcError(Job.RequestId, cRpcInternalError, 'the provider sent an invalid response');
    State := sjsFailed;
  end
  else if Msg.IsError then
  begin
    if Msg.ErrorCode = cRpcCancelled then
      State := sjsCancelled
    else
      State := sjsFailed;
  end;
  // The final message goes out in the next round of Pump and is counted there.
  Finish(Job, State, Json);
  Job.Free;
end;

function TServiceRegistry.Pump: Integer;
var
  Batch: TArray<TEntry>;
  Entry: TEntry;
begin
  Result := 0;
  repeat
    FInboxLock.Enter;
    try
      Batch := FInbox.ToArray;
      FInbox.Clear;
    finally
      FInboxLock.Leave;
    end;
    for Entry in Batch do
      if HandleEntry(Entry) then
        Inc(Result);
    // A reply handled above queues its final message for the next round.
  until Length(Batch) = 0;
end;

function TServiceRegistry.Tick: Integer;
var
  Stamp: UInt64;
  Late: TList<TJob>;
  Job: TJob;
begin
  Result := 0;
  Stamp := FClock();
  Late := TList<TJob>.Create;
  try
    for Job in FJobs.Values do
      if (Job.TimeoutMs > 0) and (Job.Deadline <= Stamp) then
        Late.Add(Job);
    for Job in Late do
    begin
      Abort(Job, cRpcTimeout, 'the provider did not answer in time', sjsFailed, True);
      Job.Free;
      Inc(Result);
    end;
  finally
    Late.Free;
  end;
end;

end.
