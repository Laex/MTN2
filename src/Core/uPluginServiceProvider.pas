unit uPluginServiceProvider;

{ The plugin side of a service (docs/PLUGIN_SERVICES.md): a provider registers one
  service name, each request runs on a worker thread of its own, a
  notifications/cancelled message flags the job, and Stop waits for the workers before
  the library is released. The plugin supplies only the procedure that answers one
  request. }

interface

uses
  System.SyncObjs, System.Generics.Collections, uPluginHostAbi, uVfsTypes;

type
  /// <summary>One request being answered.</summary>
  TServiceJob = class
  private
    FProvider: TObject;
    FCall: Int64;
    FRequestId: string;
    FCancelled: Boolean;
  public
    function IsCancelled: Boolean;
    /// <summary>A token that reports the cancel flag of this job.</summary>
    function Token: IJobCancelToken;
    /// <summary>Sends a message that is not the response (search.hits, progress).</summary>
    procedure Notify(const AJson: string);
    /// <summary>Sends a progress message; the host takes any message as a sign that the
    /// call is alive.</summary>
    procedure Progress(const AText: string);
    /// <summary>Sends the response; the last message of the call.</summary>
    procedure Reply(const AJson: string);
    procedure ReplyError(ACode: Integer; const AText: string);
    procedure ReplyResult(const AResultJson: string);
  end;

  /// <summary>Answers one request: ARequestJson is the whole message. It sends its
  /// messages through AJob and ends with Reply, ReplyError or ReplyResult, unless the
  /// job was cancelled (then it may end without a response).</summary>
  TServiceRun = reference to procedure(AJob: TServiceJob; const ARequestJson: string);

  TServiceProvider = class
  private
    FHost: PHostApiTable;
    FRun: TServiceRun;
    FLock: TCriticalSection;
    FJobs: TObjectList<TServiceJob>;
    FWorkers: Integer;
    FIdle: TEvent;
    procedure CancelRequest(const AMessageJson: string);
    procedure Accept(ACall: Int64; const AMessageJson: string);
    procedure Forget(AJob: TServiceJob);
  public
    constructor Create(AHost: PHostApiTable; const ARun: TServiceRun);
    destructor Destroy; override;
    /// <summary>False when the host is too old for services or refuses the name.</summary>
    function Register(const APluginId, AName, ADescribeJson: string; APriority: Integer): Boolean;
    /// <summary>Waits for the running workers; call before the library is released.</summary>
    procedure Stop;
  end;

/// <summary>The id member of a request message as JSON text; 'null' when there is none.</summary>
function RequestIdJson(const AMessageJson: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON;

const
  cStopWaitMs = 20000;

type
  TJobToken = class(TInterfacedObject, IJobCancelToken)
  private
    FJob: TServiceJob;
  public
    constructor Create(AJob: TServiceJob);
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

function RequestIdJson(const AMessageJson: string): string;
var
  Root, Id: TJSONValue;
begin
  Result := 'null';
  Root := TJSONObject.ParseJSONValue(AMessageJson);
  try
    if Root is TJSONObject then
    begin
      Id := TJSONObject(Root).GetValue('id');
      if Id <> nil then
        Result := Id.ToJSON;
    end;
  finally
    Root.Free;
  end;
end;

constructor TJobToken.Create(AJob: TServiceJob);
begin
  inherited Create;
  FJob := AJob;
end;

function TJobToken.IsCancellationRequested: Boolean;
begin
  Result := FJob.IsCancelled;
end;

procedure TJobToken.Cancel;
var
  P: TServiceProvider;
begin
  P := TServiceProvider(FJob.FProvider);
  P.FLock.Enter;
  try
    FJob.FCancelled := True;
  finally
    P.FLock.Leave;
  end;
end;

{ TServiceJob }

function TServiceJob.IsCancelled: Boolean;
var
  P: TServiceProvider;
begin
  P := TServiceProvider(FProvider);
  P.FLock.Enter;
  try
    Result := FCancelled;
  finally
    P.FLock.Leave;
  end;
end;

function TServiceJob.Token: IJobCancelToken;
begin
  Result := TJobToken.Create(Self);
end;

procedure TServiceJob.Notify(const AJson: string);
var
  U: UTF8String;
begin
  U := UTF8String(AJson);
  TServiceProvider(FProvider).FHost.ServiceNotify(FCall, PAnsiChar(U));
end;

procedure TServiceJob.Progress(const AText: string);
begin
  Notify('{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":' +
    FRequestId + ',"progress":0,"total":0,"message":' + TJSONString.Create(AText).ToJSON + '}}');
end;

procedure TServiceJob.Reply(const AJson: string);
var
  U: UTF8String;
begin
  U := UTF8String(AJson);
  TServiceProvider(FProvider).FHost.ServiceReply(FCall, PAnsiChar(U));
end;

procedure TServiceJob.ReplyError(ACode: Integer; const AText: string);
begin
  Reply('{"jsonrpc":"2.0","id":' + FRequestId + ',"error":{"code":' + IntToStr(ACode) +
    ',"message":' + TJSONString.Create(AText).ToJSON + '}}');
end;

procedure TServiceJob.ReplyResult(const AResultJson: string);
begin
  Reply('{"jsonrpc":"2.0","id":' + FRequestId + ',"result":' + AResultJson + '}');
end;

{ TServiceProvider }

constructor TServiceProvider.Create(AHost: PHostApiTable; const ARun: TServiceRun);
begin
  inherited Create;
  FHost := AHost;
  FRun := ARun;
  FLock := TCriticalSection.Create;
  FJobs := TObjectList<TServiceJob>.Create(True);
  FIdle := TEvent.Create(nil, True, True, '');
end;

destructor TServiceProvider.Destroy;
begin
  Stop;
  FIdle.Free;
  FJobs.Free;
  FLock.Free;
  inherited;
end;

procedure TServiceProvider.CancelRequest(const AMessageJson: string);
var
  Root, Params, Id: TJSONValue;
  Wanted: string;
  Job: TServiceJob;
begin
  Wanted := '';
  Root := TJSONObject.ParseJSONValue(AMessageJson);
  try
    if (Root is TJSONObject) and
       (TJSONObject(Root).GetValue<string>('method', '') = 'notifications/cancelled') then
    begin
      Params := TJSONObject(Root).GetValue('params');
      if Params is TJSONObject then
      begin
        Id := TJSONObject(Params).GetValue('requestId');
        if Id <> nil then
          Wanted := Id.ToJSON;
      end;
    end;
  finally
    Root.Free;
  end;
  if Wanted = '' then
    Exit;
  FLock.Enter;
  try
    for Job in FJobs do
      if Job.FRequestId = Wanted then
        Job.FCancelled := True;
  finally
    FLock.Leave;
  end;
end;

procedure TServiceProvider.Forget(AJob: TServiceJob);
begin
  FLock.Enter;
  try
    FJobs.Remove(AJob);
  finally
    FLock.Leave;
  end;
  if TInterlocked.Decrement(FWorkers) = 0 then
    FIdle.SetEvent;
end;

procedure TServiceProvider.Accept(ACall: Int64; const AMessageJson: string);
var
  Job: TServiceJob;
begin
  Job := TServiceJob.Create;
  Job.FProvider := Self;
  Job.FCall := ACall;
  Job.FRequestId := RequestIdJson(AMessageJson);
  FLock.Enter;
  try
    FJobs.Add(Job);
    if TInterlocked.Increment(FWorkers) = 1 then
      FIdle.ResetEvent;
  finally
    FLock.Leave;
  end;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        try
          FRun(Job, AMessageJson);
        except
          on E: Exception do
            Job.ReplyError(-32603, E.Message);
        end;
      finally
        Forget(Job);
      end;
    end).Start;
end;

function ServiceHandler(AUserData: Pointer; ACall: Int64; AMessageJson: PAnsiChar): Int64; cdecl;
var
  Msg: string;
begin
  Result := 0;
  try
    Msg := UTF8ToString(AMessageJson);
    if ACall = 0 then
      TServiceProvider(AUserData).CancelRequest(Msg)
    else
      TServiceProvider(AUserData).Accept(ACall, Msg);
  except
    Result := -1;
  end;
end;

function TServiceProvider.Register(const APluginId, AName, ADescribeJson: string;
  APriority: Integer): Boolean;
var
  Id, Name, Describe: UTF8String;
begin
  Result := False;
  if (FHost = nil) or (FHost.AbiVersion < 11) or not Assigned(FHost.RegisterService) or
     not Assigned(FHost.ServiceReply) or not Assigned(FHost.ServiceNotify) then
    Exit;
  Id := UTF8String(APluginId);
  Name := UTF8String(AName);
  Describe := UTF8String(ADescribeJson);
  Result := FHost.RegisterService(PAnsiChar(Id), PAnsiChar(Name), 1, PAnsiChar(Describe),
    ServiceHandler, Self, APriority) = 0;
end;

procedure TServiceProvider.Stop;
begin
  FIdle.WaitFor(cStopWaitMs);
end;

end.
