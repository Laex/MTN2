unit uPluginServiceHost;

{ Host side of the plugin services (docs/PLUGIN_SERVICES.md): the single
  registry, the cdecl entry points of the ABI 11 function group and the two
  things the registry leaves to its owner - waking the main thread to deliver
  queued messages and ticking the time limits.

  Register, call, cancel and status run on the main thread. Reply and Notify
  may come from any thread: they queue the message and post one pump to the
  main thread. A watchdog thread exists only while a call with a time limit
  is open. }

interface

uses
  uServiceRegistry, uPluginHostAbi;

/// <summary>The one registry of the process (main thread).</summary>
function ServiceRegistry: TServiceRegistry;

function HostRegisterService(APluginId, AName: PAnsiChar; AVersion: Int64;
  ADescribeJson: PAnsiChar; AHandler: TServiceHandlerFn; AUserData: Pointer;
  APriority: Int64): Int64; cdecl;
function HostServiceReply(ACall: Int64; AResponseJson: PAnsiChar): Int64; cdecl;
function HostServiceNotify(ACall: Int64; ANotificationJson: PAnsiChar): Int64; cdecl;
function HostCallService(APluginId, AName, ARequestJson: PAnsiChar; ATimeoutMs: Int64;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
function HostCallServiceAsync(APluginId, AName, ARequestJson: PAnsiChar; ATimeoutMs: Int64;
  AOnMessage: TServiceMessageFn; AUserData: Pointer; out AJobId: Int64): Int64; cdecl;
function HostServiceStatus(AJobId: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
function HostCancelService(AJobId: Int64): Int64; cdecl;

/// <summary>Starts a call from host code (main thread): the registry's Call plus
/// the wake-up and watchdog that make the messages arrive. 0 = started.</summary>
function ServiceCallAsync(const AName, APluginId, ARequestJson: string; ATimeoutMs: Integer;
  AOnMessage: TServiceMessageProc; out AJobId: Int64): Integer;
/// <summary>Cancels an open call from host code (main thread).</summary>
function ServiceCancel(AJobId: Int64): Boolean;

/// <summary>Drops the services of a plugin that is being unloaded; its open
/// calls end with an error.</summary>
procedure PluginServicesUnregister(const APluginId: string);

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON, uJsonRpc;

const
  cWatchdogStepMs = 50;
  cSyncWaitStepMs = 1;

var
  GRegistry: TServiceRegistry;
  GPumpPending: Integer;
  GWatchdogRunning: Integer;
  GShutdown: Boolean;

function Utf8Out(const AText: string; ABuf: PAnsiChar; ABufSize: Int64): Int64;
var
  U: UTF8String;
begin
  U := UTF8String(AText);
  Result := Length(U);
  if (ABuf <> nil) and (ABufSize > Result) then
    Move(PAnsiChar(U)^, ABuf^, Result + 1);
end;

function ServiceRegistry: TServiceRegistry;
begin
  if GRegistry = nil then
    GRegistry := TServiceRegistry.Create;
  Result := GRegistry;
end;

procedure PumpNow;
begin
  TInterlocked.Exchange(GPumpPending, 0);
  if GRegistry <> nil then
  begin
    GRegistry.Tick;
    GRegistry.Pump;
  end;
end;

// One queued pump covers every message that arrives before it runs.
procedure SchedulePump;
begin
  if TInterlocked.Exchange(GPumpPending, 1) = 0 then
    TThread.ForceQueue(nil, PumpNow);
end;

procedure WatchdogLoop;
begin
  while not GShutdown do
  begin
    Sleep(cWatchdogStepMs);
    if GShutdown then
      Break;
    if (GRegistry <> nil) and (GRegistry.TimedCalls > 0) then
    begin
      SchedulePump;
      Continue;
    end;
    // Nothing timed is open: stop, then look again so a call that opened in
    // between is not left without a watchdog.
    TInterlocked.Exchange(GWatchdogRunning, 0);
    if (GRegistry = nil) or (GRegistry.TimedCalls = 0) then
      Break;
    if TInterlocked.CompareExchange(GWatchdogRunning, 1, 0) <> 0 then
      Break;
  end;
end;

procedure EnsureWatchdog;
var
  T: TThread;
begin
  if TInterlocked.CompareExchange(GWatchdogRunning, 1, 0) <> 0 then
    Exit;
  T := TThread.CreateAnonymousThread(WatchdogLoop);
  T.FreeOnTerminate := True;
  T.Start;
end;

function ServiceCallAsync(const AName, APluginId, ARequestJson: string; ATimeoutMs: Integer;
  AOnMessage: TServiceMessageProc; out AJobId: Int64): Integer;
begin
  Result := ServiceRegistry.Call(AName, APluginId, ARequestJson, ATimeoutMs, AOnMessage, AJobId);
  if (Result = 0) and (ATimeoutMs > 0) then
    EnsureWatchdog;
end;

function ServiceCancel(AJobId: Int64): Boolean;
begin
  Result := ServiceRegistry.Cancel(AJobId);
  if Result then
    SchedulePump;
end;

function HostRegisterService(APluginId, AName: PAnsiChar; AVersion: Int64;
  ADescribeJson: PAnsiChar; AHandler: TServiceHandlerFn; AUserData: Pointer;
  APriority: Int64): Int64; cdecl;
var
  Fn: TServiceHandlerFn;
  Data: Pointer;
  Describe: string;
begin
  try
    if (APluginId = nil) or (AName = nil) or not Assigned(AHandler) or
       (AVersion < 1) or (AVersion > High(Integer)) or
       (APriority < Low(Integer)) or (APriority > High(Integer)) then
      Exit(cRpcInvalidParams);
    if ADescribeJson = nil then
      Describe := ''
    else
      Describe := UTF8ToString(ADescribeJson);
    Fn := AHandler;
    Data := AUserData;
    Result := ServiceRegistry.RegisterService(UTF8ToString(APluginId), UTF8ToString(AName),
      Integer(AVersion), Describe,
      function(ACall: Int64; const AMessageJson: string): Boolean
      var
        U: UTF8String;
      begin
        U := UTF8String(AMessageJson);
        Result := Fn(Data, ACall, PAnsiChar(U)) = 0;
      end,
      Integer(APriority));
  except
    Result := cRpcInternalError;
  end;
end;

function HostServiceReply(ACall: Int64; AResponseJson: PAnsiChar): Int64; cdecl;
begin
  try
    if (ACall <= 0) or (AResponseJson = nil) then
      Exit(-1);
    ServiceRegistry.Reply(ACall, UTF8ToString(AResponseJson));
    SchedulePump;
    Result := 0;
  except
    Result := -1;
  end;
end;

function HostServiceNotify(ACall: Int64; ANotificationJson: PAnsiChar): Int64; cdecl;
begin
  try
    if (ACall <= 0) or (ANotificationJson = nil) then
      Exit(-1);
    ServiceRegistry.Notify(ACall, UTF8ToString(ANotificationJson));
    SchedulePump;
    Result := 0;
  except
    Result := -1;
  end;
end;

function HostCallService(APluginId, AName, ARequestJson: PAnsiChar; ATimeoutMs: Int64;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  Reg: TServiceRegistry;
  Job: Int64;
  Done: Boolean;
  Response: string;
  Plugin: string;
begin
  ANegotiatedSize := 0;
  try
    if (AName = nil) or (ARequestJson = nil) or (ATimeoutMs < 1) or
       (ATimeoutMs > cServiceMaxTimeoutMs) then
      Exit(cRpcInvalidParams);
    if APluginId = nil then
      Plugin := ''
    else
      Plugin := UTF8ToString(APluginId);
    Reg := ServiceRegistry;
    Done := False;
    Response := '';
    Result := Reg.Call(UTF8ToString(AName), Plugin, UTF8ToString(ARequestJson),
      Integer(ATimeoutMs),
      procedure(AJobId: Int64; const AMessageJson: string)
      var
        Msg: TRpcMessage;
        Err: Integer;
      begin
        if TryParseRpcMessage(AMessageJson, Msg, Err) and (Msg.Kind = rkResponse) then
        begin
          Response := AMessageJson;
          Done := True;
        end;
      end, Job);
    if Result <> 0 then
      Exit;
    // The silence limit of the call ends the wait: Tick turns it into a response.
    while not Done do
    begin
      Reg.Tick;
      if Reg.Pump = 0 then
        Sleep(cSyncWaitStepMs);
    end;
    ANegotiatedSize := Utf8Out(Response, ABuf, ABufSize);
    if (ABuf = nil) or (ABufSize <= ANegotiatedSize) then
      Result := -2
    else
      Result := 0;
  except
    Result := cRpcInternalError;
  end;
end;

function HostCallServiceAsync(APluginId, AName, ARequestJson: PAnsiChar; ATimeoutMs: Int64;
  AOnMessage: TServiceMessageFn; AUserData: Pointer; out AJobId: Int64): Int64; cdecl;
var
  Fn: TServiceMessageFn;
  Data: Pointer;
  Plugin: string;
begin
  AJobId := 0;
  try
    if (AName = nil) or (ARequestJson = nil) or not Assigned(AOnMessage) or
       (ATimeoutMs < 0) or (ATimeoutMs > cServiceMaxTimeoutMs) then
      Exit(cRpcInvalidParams);
    if APluginId = nil then
      Plugin := ''
    else
      Plugin := UTF8ToString(APluginId);
    Fn := AOnMessage;
    Data := AUserData;
    Result := ServiceCallAsync(UTF8ToString(AName), Plugin, UTF8ToString(ARequestJson),
      Integer(ATimeoutMs),
      procedure(AId: Int64; const AMessageJson: string)
      var
        U: UTF8String;
      begin
        U := UTF8String(AMessageJson);
        Fn(Data, AId, PAnsiChar(U));
      end, AJobId);
  except
    Result := cRpcInternalError;
  end;
end;

function StateName(AState: TServiceJobState): string;
begin
  case AState of
    sjsRunning: Result := 'running';
    sjsDone: Result := 'done';
    sjsCancelled: Result := 'cancelled';
  else
    Result := 'failed';
  end;
end;

function HostServiceStatus(AJobId: Int64; ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  Status: TServiceJobStatus;
  Obj: TJSONObject;
begin
  try
    if not ServiceRegistry.Status(AJobId, Status) then
      Exit(-1);
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('state', StateName(Status.State));
      Obj.AddPair('progress', TJSONNumber.Create(Status.Progress));
      Obj.AddPair('total', TJSONNumber.Create(Status.Total));
      Obj.AddPair('message', Status.Message);
      Result := Utf8Out(Obj.ToJSON, ABuf, ABufSize);
    finally
      Obj.Free;
    end;
  except
    Result := -1;
  end;
end;

function HostCancelService(AJobId: Int64): Int64; cdecl;
begin
  try
    if ServiceCancel(AJobId) then
      Result := 0
    else
      Result := -1;
  except
    Result := -1;
  end;
end;

procedure PluginServicesUnregister(const APluginId: string);
begin
  if GRegistry = nil then
    Exit;
  GRegistry.UnregisterPlugin(APluginId);
  SchedulePump;
end;

initialization

finalization
  GShutdown := True;
  FreeAndNil(GRegistry);

end.
