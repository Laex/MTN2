unit TestServiceRegistry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestServiceRegistry = class
  public
    [Test] procedure TestNameRules;
    [Test] procedure TestRegistrationIsValidated;
    [Test] procedure TestProvidersAreOrderedByPriority;
    [Test] procedure TestSamePluginRegisteringAgainReplacesItself;
    [Test] procedure TestPickProviderMatchesCapabilities;
    [Test] procedure TestCallRejectsBadRequests;
    [Test] procedure TestNotificationsPrecedeTheResponse;
    [Test] procedure TestProgressUpdatesTheStatus;
    [Test] procedure TestInvalidResponseBecomesAnInternalError;
    [Test] procedure TestOversizeResponseBecomesAnInternalError;
    [Test] procedure TestRefusingOrRaisingProviderFailsTheCall;
    [Test] procedure TestAnswerFromInsideTheHandlerIsDelivered;
    [Test] procedure TestOpenCallsAreLimitedPerService;
    [Test] procedure TestCancelEndsTheCallAndTellsTheProvider;
    [Test] procedure TestLateMessagesOfAnEndedCallAreDropped;
    [Test] procedure TestSilentProviderTimesOut;
    [Test] procedure TestProviderMessagesKeepTheCallAlive;
    [Test] procedure TestUnregisterPluginEndsItsCalls;
    [Test] procedure TestReplyFromAnotherThreadIsDeliveredByPump;
    [Test] procedure TestFinishedStatusIsKeptForTheLastCalls;
    [Test] procedure TestRaisingCallbackDoesNotStopOtherMessages;
    [Test] procedure TestParamsAreCheckedAgainstTheInputSchema;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uJsonRpc, uServiceRegistry;

const
  cDescribe = '{"protocolVersion":1,"name":"search.files","capabilities":["name","mask"]}';

type
  /// <summary>A provider that records what it is handed and answers on demand.</summary>
  TFakeProvider = class
  public
    Registry: TServiceRegistry;
    Calls: TList<Int64>;
    Requests: TList<string>;
    Notices: TList<string>;
    Accept: Boolean;
    constructor Create(ARegistry: TServiceRegistry);
    destructor Destroy; override;
    function Handle(ACall: Int64; const AMessageJson: string): Boolean;
    function AsHandler: TServiceHandler;
  end;

  /// <summary>The messages a caller received.</summary>
  TCaller = class
  public
    Messages: TList<string>;
    constructor Create;
    destructor Destroy; override;
    function AsProc: TServiceMessageProc;
    function Last: string;
  end;

constructor TFakeProvider.Create(ARegistry: TServiceRegistry);
begin
  inherited Create;
  Registry := ARegistry;
  Calls := TList<Int64>.Create;
  Requests := TList<string>.Create;
  Notices := TList<string>.Create;
  Accept := True;
end;

destructor TFakeProvider.Destroy;
begin
  Calls.Free;
  Requests.Free;
  Notices.Free;
  inherited;
end;

function TFakeProvider.Handle(ACall: Int64; const AMessageJson: string): Boolean;
begin
  if ACall = 0 then
    Notices.Add(AMessageJson)
  else
  begin
    Calls.Add(ACall);
    Requests.Add(AMessageJson);
  end;
  Result := Accept;
end;

function TFakeProvider.AsHandler: TServiceHandler;
begin
  Result := function(ACall: Int64; const AMessageJson: string): Boolean
    begin
      Result := Handle(ACall, AMessageJson);
    end;
end;

constructor TCaller.Create;
begin
  inherited Create;
  Messages := TList<string>.Create;
end;

destructor TCaller.Destroy;
begin
  Messages.Free;
  inherited;
end;

function TCaller.AsProc: TServiceMessageProc;
begin
  Result := procedure(AJobId: Int64; const AMessageJson: string)
    begin
      Messages.Add(AMessageJson);
    end;
end;

function TCaller.Last: string;
begin
  if Messages.Count = 0 then
    Result := ''
  else
    Result := Messages[Messages.Count - 1];
end;

function Request(AId: Integer; const AName: string): string;
begin
  Result := BuildRpcRequest(RpcIntId(AId), AName, '{"root":"C:\\Work"}');
end;

function Response(AId: Integer): string;
begin
  Result := BuildRpcResult(RpcIntId(AId), '{"isError":false}');
end;

function ErrorCodeOf(const AJson: string): Integer;
var
  Msg: TRpcMessage;
  Err: Integer;
begin
  Assert.IsTrue(TryParseRpcMessage(AJson, Msg, Err), 'a valid message: ' + AJson);
  Assert.IsTrue(Msg.IsError, 'an error response: ' + AJson);
  Result := Msg.ErrorCode;
end;

procedure TTestServiceRegistry.TestNameRules;
begin
  Assert.IsTrue(TServiceRegistry.IsValidName('search.files'));
  Assert.IsTrue(TServiceRegistry.IsValidName('text.extract_2'));
  Assert.IsTrue(TServiceRegistry.IsValidName('a'));
  Assert.IsFalse(TServiceRegistry.IsValidName(''));
  Assert.IsFalse(TServiceRegistry.IsValidName('Search.files'), 'lower case only');
  Assert.IsFalse(TServiceRegistry.IsValidName('search..files'));
  Assert.IsFalse(TServiceRegistry.IsValidName('.search'));
  Assert.IsFalse(TServiceRegistry.IsValidName('search.'));
  Assert.IsFalse(TServiceRegistry.IsValidName('1search'));
  Assert.IsFalse(TServiceRegistry.IsValidName('search files'));
  Assert.IsTrue(TServiceRegistry.IsReservedName('host.anything'));
  Assert.IsTrue(TServiceRegistry.IsReservedName('service.describe'));
  Assert.IsTrue(TServiceRegistry.IsReservedName('file'));
  Assert.IsTrue(TServiceRegistry.IsReservedName('ws'));
  Assert.IsFalse(TServiceRegistry.IsReservedName('search.files'));
  Assert.IsFalse(TServiceRegistry.IsReservedName('files'), 'only the exact scheme names');
end;

procedure TTestServiceRegistry.TestRegistrationIsValidated;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  try
    Assert.AreEqual(0, Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler()));
    Assert.AreEqual(cRpcNotAllowed, Reg.RegisterService('a', 'host.x', 1, cDescribe, P.AsHandler()), 'reserved');
    Assert.AreEqual(cRpcNotAllowed, Reg.RegisterService('a', 'service.ping', 1, cDescribe, P.AsHandler()), 'reserved');
    Assert.AreEqual(cRpcNotAllowed, Reg.RegisterService('a', 'recycle', 1, cDescribe, P.AsHandler()), 'core scheme');
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'Bad Name', 1, cDescribe, P.AsHandler()));
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 0, cDescribe, P.AsHandler()), 'version');
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('', 'x.y', 1, cDescribe, P.AsHandler()), 'plugin id');
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 1, cDescribe, nil), 'handler');
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 1, 'not json', P.AsHandler()));
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 1, '[]', P.AsHandler()), 'object expected');
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 1, '{"capabilities":"name"}', P.AsHandler()));
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'x.y', 1, '{"capabilities":[1]}', P.AsHandler()));
    Assert.AreEqual<Integer>(1, Length(Reg.Providers('search.files')), 'only the valid one is kept');
    Assert.AreEqual<Integer>(0, Length(Reg.Providers('x.y')));
  finally
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestProvidersAreOrderedByPriority;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  List: TArray<TServiceProviderInfo>;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  try
    Reg.RegisterService('c', 'search.files', 1, cDescribe, P.AsHandler(), 200);
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler(), 50);
    Reg.RegisterService('b', 'search.files', 1, cDescribe, P.AsHandler(), 100);
    Reg.RegisterService('d', 'search.files', 1, cDescribe, P.AsHandler(), 100);
    List := Reg.Providers('search.files');
    Assert.AreEqual<Integer>(4, Length(List));
    Assert.AreEqual('a', List[0].PluginId);
    Assert.AreEqual('b', List[1].PluginId, 'equal priorities keep the registration order');
    Assert.AreEqual('d', List[2].PluginId);
    Assert.AreEqual('c', List[3].PluginId);
  finally
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestSamePluginRegisteringAgainReplacesItself;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  List: TArray<TServiceProviderInfo>;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler(), 100);
    Reg.RegisterService('a', 'search.files', 2, '{"capabilities":["content"]}', P.AsHandler(), 10);
    List := Reg.Providers('search.files');
    Assert.AreEqual<Integer>(1, Length(List));
    Assert.AreEqual(2, List[0].Version);
    Assert.AreEqual(10, List[0].Priority);
    Assert.AreEqual<Integer>(1, Length(List[0].Capabilities));
    Assert.AreEqual('content', List[0].Capabilities[0]);
  finally
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestPickProviderMatchesCapabilities;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  Id: string;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  try
    Reg.RegisterService('names', 'search.files', 1, '{"capabilities":["Name","mask","size"]}', P.AsHandler(), 10);
    Reg.RegisterService('content', 'search.files', 1, '{"capabilities":["name","mask","content"]}', P.AsHandler(), 20);
    Assert.IsTrue(Reg.PickProvider('search.files', ['name', 'mask'], Id));
    Assert.AreEqual('names', Id, 'the first one that fits');
    Assert.IsTrue(Reg.PickProvider('search.files', ['name', 'content'], Id));
    Assert.AreEqual('content', Id, 'the first one that lists every word');
    Assert.IsTrue(Reg.PickProvider('search.files', ['NAME'], Id), 'case does not matter');
    Assert.IsFalse(Reg.PickProvider('search.files', ['name', 'hex'], Id), 'no provider honors hex');
    Assert.AreEqual('', Id);
    Assert.IsFalse(Reg.PickProvider('other.service', [], Id));
    Assert.IsTrue(Reg.PickProvider('search.files', [], Id), 'no needs: the first provider');
  finally
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestCallRejectsBadRequests;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Assert.AreEqual(cRpcMethodNotFound, Reg.Call('other.service', '', Request(1, 'other.service'), 0, C.AsProc(), Job));
    Assert.AreEqual(cRpcParseError, Reg.Call('search.files', '', 'not json', 0, C.AsProc(), Job));
    Assert.AreEqual(cRpcInvalidRequest, Reg.Call('search.files', '', Request(1, 'search.other'), 0, C.AsProc(), Job),
      'the method must name the service');
    Assert.AreEqual(cRpcInvalidRequest, Reg.Call('search.files', '',
      BuildRpcNotification('search.files', '{}'), 0, C.AsProc(), Job), 'a notification is not a call');
    Assert.AreEqual(cRpcMethodNotFound, Reg.Call('search.files', 'nobody', Request(1, 'search.files'), 0, C.AsProc(), Job),
      'a named provider that is not registered');
    Assert.AreEqual(cRpcInvalidParams, Reg.Call('search.files', '', Request(1, 'search.files'), 0, nil, Job));
    Assert.AreEqual(cRpcInvalidRequest, Reg.Call('search.files', '',
      BuildRpcRequest(RpcIntId(1), 'search.files', '"' + StringOfChar('x', cServiceMaxMessageBytes) + '"'),
      0, C.AsProc(), Job), 'an oversize request');
    Assert.AreEqual<Int64>(0, Job);
    Assert.AreEqual<Integer>(0, P.Calls.Count, 'the provider saw none of them');
    Assert.AreEqual(0, Reg.OpenCalls('search.files'));
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestNotificationsPrecedeTheResponse;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Msg: TRpcMessage;
  Err: Integer;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Assert.AreEqual(0, Reg.Call('search.files', '', Request(7, 'search.files'), 0, C.AsProc(), Job));
    Assert.IsTrue(Job > 0, 'a job id');
    Assert.AreEqual<Integer>(1, P.Requests.Count);
    Assert.AreEqual<Int64>(Job, P.Calls[0], 'the provider gets the job id as the call');
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"hits":[]}'));
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"hits":[1]}'));
    Reg.Reply(Job, Response(7));
    Assert.AreEqual<Integer>(0, C.Messages.Count, 'nothing is delivered before Pump');
    Assert.AreEqual(3, Reg.Pump);
    Assert.AreEqual<Integer>(3, C.Messages.Count);
    Assert.IsTrue(TryParseRpcMessage(C.Messages[0], Msg, Err) and (Msg.Method = 'search.hits'));
    Assert.IsTrue(TryParseRpcMessage(C.Messages[1], Msg, Err) and (Msg.Method = 'search.hits'));
    Assert.IsTrue(TryParseRpcMessage(C.Messages[2], Msg, Err) and (Msg.Kind = rkResponse), 'the response is last');
    Assert.AreEqual(0, Reg.OpenCalls('search.files'), 'the call is closed');
    Assert.AreEqual(0, Reg.Pump, 'nothing is delivered twice');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestProgressUpdatesTheStatus;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Status: TServiceJobStatus;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(1, 'search.files'), 0, C.AsProc(), Job);
    Assert.IsTrue(Reg.Status(Job, Status));
    Assert.IsTrue(Status.State = sjsRunning, 'running');
    Reg.Notify(Job, BuildRpcNotification('notifications/progress',
      '{"progressToken":"1","progress":120,"total":500,"message":"C:\\Work"}'));
    Reg.Pump;
    Assert.IsTrue(Reg.Status(Job, Status));
    Assert.AreEqual<Int64>(120, Status.Progress);
    Assert.AreEqual<Int64>(500, Status.Total);
    Assert.AreEqual('C:\Work', Status.Message);
    Reg.Reply(Job, Response(1));
    Reg.Pump;
    Assert.IsTrue(Reg.Status(Job, Status));
    Assert.IsTrue(Status.State = sjsDone, 'done');
    Assert.AreEqual<Int64>(120, Status.Progress, 'the last progress stays');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestInvalidResponseBecomesAnInternalError;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Status: TServiceJobStatus;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(7, 'search.files'), 0, C.AsProc(), Job);
    Reg.Reply(Job, Response(8));
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last), 'a response with another id');
    Assert.IsTrue(Reg.Status(Job, Status) and (Status.State = sjsFailed), 'failed');

    C.Messages.Clear;
    Reg.Call('search.files', '', Request(9, 'search.files'), 0, C.AsProc(), Job);
    Reg.Reply(Job, 'garbage');
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last), 'a response that is not JSON');

    C.Messages.Clear;
    Reg.Call('search.files', '', Request(10, 'search.files'), 0, C.AsProc(), Job);
    Reg.Reply(Job, BuildRpcNotification('search.hits', '{}'));
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last), 'a notification sent as a response');
    Assert.AreEqual<Integer>(1, C.Messages.Count);

    C.Messages.Clear;
    Reg.Call('search.files', '', Request(11, 'search.files'), 0, C.AsProc(), Job);
    Reg.Notify(Job, Response(11));
    Reg.Pump;
    Assert.AreEqual<Integer>(0, C.Messages.Count, 'a response sent as a notification is dropped');
    Assert.AreEqual(1, Reg.OpenCalls('search.files'), 'and the call stays open');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestOversizeResponseBecomesAnInternalError;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(1, 'search.files'), 0, C.AsProc(), Job);
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"p":"' + StringOfChar('x', cServiceMaxMessageBytes) + '"}'));
    Reg.Reply(Job, BuildRpcResult(RpcIntId(1), '"' + StringOfChar('x', cServiceMaxMessageBytes) + '"'));
    Reg.Pump;
    Assert.AreEqual<Integer>(1, C.Messages.Count, 'the oversize notification is dropped');
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last), 'the oversize response is replaced');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestRefusingOrRaisingProviderFailsTheCall;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Status: TServiceJobStatus;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    P.Accept := False;
    Assert.AreEqual(0, Reg.Call('search.files', '', Request(1, 'search.files'), 0, C.AsProc(), Job),
      'the call itself is made; its response reports the refusal');
    Assert.AreEqual(0, Reg.OpenCalls('search.files'));
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last));
    Assert.IsTrue(Reg.Status(Job, Status) and (Status.State = sjsFailed), 'failed');

    C.Messages.Clear;
    Reg.RegisterService('b', 'text.extract', 1, '{}',
      function(ACall: Int64; const AMessageJson: string): Boolean
      begin
        raise Exception.Create('provider broke');
      end);
    Assert.AreEqual(0, Reg.Call('text.extract', '', Request(2, 'text.extract'), 0, C.AsProc(), Job));
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C.Last), 'an exception in the handler');
    Assert.AreEqual<Integer>(1, C.Messages.Count);
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestAnswerFromInsideTheHandlerIsDelivered;
var
  Reg: TServiceRegistry;
  C: TCaller;
  Job: Int64;
  Msg: TRpcMessage;
  Err: Integer;
begin
  Reg := TServiceRegistry.Create;
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe,
      function(ACall: Int64; const AMessageJson: string): Boolean
      begin
        if ACall <> 0 then
          Reg.Reply(ACall, Response(3));
        Result := True;
      end);
    Assert.AreEqual(0, Reg.Call('search.files', '', Request(3, 'search.files'), 0, C.AsProc(), Job));
    Assert.AreEqual(1, Reg.Pump);
    Assert.IsTrue(TryParseRpcMessage(C.Last, Msg, Err) and (Msg.Kind = rkResponse) and not Msg.IsError);
  finally
    C.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestOpenCallsAreLimitedPerService;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  I: Integer;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.RegisterService('a', 'text.extract', 1, '{}', P.AsHandler());
    for I := 1 to cServiceMaxOpenCalls do
      Assert.AreEqual(0, Reg.Call('search.files', '', Request(I, 'search.files'), 0, C.AsProc(), Job));
    Assert.AreEqual(cRpcTooManyCalls, Reg.Call('search.files', '', Request(99, 'search.files'), 0, C.AsProc(), Job));
    Assert.AreEqual(0, Reg.Call('text.extract', '', Request(1, 'text.extract'), 0, C.AsProc(), Job),
      'another service has its own limit');
    Reg.Reply(P.Calls[0], Response(1));
    Reg.Pump;
    Assert.AreEqual(0, Reg.Call('search.files', '', Request(100, 'search.files'), 0, C.AsProc(), Job),
      'a finished call frees a place');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestCancelEndsTheCallAndTellsTheProvider;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Status: TServiceJobStatus;
  Msg: TRpcMessage;
  Err: Integer;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(4, 'search.files'), 0, C.AsProc(), Job);
    Assert.IsTrue(Reg.Cancel(Job));
    Assert.AreEqual(0, Reg.OpenCalls('search.files'), 'the place is free at once');
    Assert.AreEqual<Integer>(1, P.Notices.Count, 'the provider is told');
    Assert.IsTrue(TryParseRpcMessage(P.Notices[0], Msg, Err));
    Assert.AreEqual('notifications/cancelled', Msg.Method);
    Assert.IsTrue(Pos('"requestId":4', Msg.ParamsJson) > 0, 'it names the request');
    Reg.Pump;
    Assert.AreEqual(cRpcCancelled, ErrorCodeOf(C.Last));
    Assert.IsTrue(Reg.Status(Job, Status) and (Status.State = sjsCancelled), 'cancelled');
    Assert.IsFalse(Reg.Cancel(Job), 'a second cancel finds nothing open');
    Assert.IsFalse(Reg.Cancel(12345), 'an unknown job');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestLateMessagesOfAnEndedCallAreDropped;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(4, 'search.files'), 0, C.AsProc(), Job);
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"hits":[]}'));
    Reg.Cancel(Job);
    Reg.Reply(Job, Response(4));
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"hits":[]}'));
    Reg.Pump;
    Assert.AreEqual<Integer>(1, C.Messages.Count, 'only the cancellation reaches the caller');
    Assert.AreEqual(cRpcCancelled, ErrorCodeOf(C.Messages[0]));
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestSilentProviderTimesOut;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Clock: UInt64;
  Status: TServiceJobStatus;
begin
  Clock := 1000;
  Reg := TServiceRegistry.Create(function: UInt64 begin Result := Clock; end);
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(1, 'search.files'), 500, C.AsProc(), Job);
    Clock := 1499;
    Assert.AreEqual(0, Reg.Tick, 'not yet');
    Clock := 1500;
    Assert.AreEqual(1, Reg.Tick);
    Assert.AreEqual(0, Reg.OpenCalls('search.files'));
    Assert.AreEqual<Integer>(1, P.Notices.Count, 'the provider is told to stop');
    Reg.Pump;
    Assert.AreEqual(cRpcTimeout, ErrorCodeOf(C.Last));
    Assert.IsTrue(Reg.Status(Job, Status) and (Status.State = sjsFailed), 'failed');
    Assert.AreEqual(0, Reg.Tick, 'nothing left to end');

    Reg.Call('search.files', '', Request(2, 'search.files'), 0, C.AsProc(), Job);
    Clock := Clock + 10 * 60000;
    Assert.AreEqual(0, Reg.Tick, 'no limit when the time is 0');
    Reg.Call('search.files', '', Request(3, 'search.files'), 10 * 60000, C.AsProc(), Job);
    Clock := Clock + cServiceMaxTimeoutMs;
    Assert.AreEqual(1, Reg.Tick, 'a longer limit is cut to the maximum');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestProviderMessagesKeepTheCallAlive;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Clock: UInt64;
begin
  Clock := 0;
  Reg := TServiceRegistry.Create(function: UInt64 begin Result := Clock; end);
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(1, 'search.files'), 1000, C.AsProc(), Job);
    Clock := 900;
    Reg.Notify(Job, BuildRpcNotification('search.hits', '{"hits":[]}'));
    Reg.Pump;
    Clock := 1800;
    Assert.AreEqual(0, Reg.Tick, 'the limit counts from the last message');
    Clock := 1900;
    Assert.AreEqual(1, Reg.Tick);
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestUnregisterPluginEndsItsCalls;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C1, C2: TCaller;
  Job: Int64;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C1 := TCaller.Create;
  C2 := TCaller.Create;
  try
    Reg.RegisterService('gone', 'search.files', 1, cDescribe, P.AsHandler(), 10);
    Reg.RegisterService('stay', 'search.files', 1, cDescribe, P.AsHandler(), 20);
    Reg.Call('search.files', 'gone', Request(1, 'search.files'), 0, C1.AsProc(), Job);
    Reg.Call('search.files', 'stay', Request(2, 'search.files'), 0, C2.AsProc(), Job);
    Reg.UnregisterPlugin('gone');
    Reg.Pump;
    Assert.AreEqual(cRpcInternalError, ErrorCodeOf(C1.Last));
    Assert.AreEqual<Integer>(0, C2.Messages.Count, 'the other plugin is not touched');
    Assert.AreEqual(1, Reg.OpenCalls('search.files'));
    Assert.AreEqual<Integer>(1, Length(Reg.Providers('search.files')));
    Assert.AreEqual('stay', Reg.Providers('search.files')[0].PluginId);
  finally
    C2.Free;
    C1.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestReplyFromAnotherThreadIsDeliveredByPump;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Worker: TThread;
  Done: TEvent;
  I: Integer;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  Done := TEvent.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(5, 'search.files'), 0, C.AsProc(), Job);
    Worker := TThread.CreateAnonymousThread(
      procedure
      var
        N: Integer;
      begin
        for N := 1 to 50 do
          Reg.Notify(Job, BuildRpcNotification('search.hits', '{"n":' + IntToStr(N) + '}'));
        Reg.Reply(Job, Response(5));
        Done.SetEvent;
      end);
    Worker.FreeOnTerminate := True;
    Worker.Start;
    Assert.IsTrue(Done.WaitFor(10000) = wrSignaled, 'the worker finished');
    Assert.AreEqual<Integer>(0, C.Messages.Count, 'nothing arrives on the provider thread');
    Assert.AreEqual(51, Reg.Pump);
    Assert.AreEqual<Integer>(51, C.Messages.Count);
    for I := 0 to 49 do
      Assert.AreEqual('{"jsonrpc":"2.0","method":"search.hits","params":{"n":' + IntToStr(I + 1) + '}}',
        C.Messages[I], 'in the order sent');
  finally
    Done.Free;
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestFinishedStatusIsKeptForTheLastCalls;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job, First: Int64;
  I: Integer;
  Status: TServiceJobStatus;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    First := 0;
    for I := 1 to cServiceKeepFinished + 5 do
    begin
      Reg.Call('search.files', '', Request(I, 'search.files'), 0, C.AsProc(), Job);
      if I = 1 then
        First := Job;
      Reg.Reply(Job, Response(I));
      Reg.Pump;
    end;
    Assert.IsFalse(Reg.Status(First, Status), 'the oldest status is forgotten');
    Assert.IsTrue(Reg.Status(Job, Status), 'the newest is kept');
    Assert.IsTrue(Status.State = sjsDone, 'done');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestRaisingCallbackDoesNotStopOtherMessages;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  Good: TCaller;
  Job1, Job2: Int64;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  Good := TCaller.Create;
  try
    Reg.RegisterService('a', 'search.files', 1, cDescribe, P.AsHandler());
    Reg.Call('search.files', '', Request(1, 'search.files'),  0,
      procedure(AJobId: Int64; const AMessageJson: string)
      begin
        raise Exception.Create('caller broke');
      end, Job1);
    Reg.Call('search.files', '', Request(2, 'search.files'), 0, Good.AsProc(), Job2);
    Reg.Reply(Job1, Response(1));
    Reg.Reply(Job2, Response(2));
    Reg.Pump;
    Assert.AreEqual<Integer>(1, Good.Messages.Count, 'the second caller still gets its response');
    Assert.AreEqual(0, Reg.OpenCalls('search.files'));
  finally
    Good.Free;
    P.Free;
    Reg.Free;
  end;
end;

procedure TTestServiceRegistry.TestParamsAreCheckedAgainstTheInputSchema;
var
  Reg: TServiceRegistry;
  P: TFakeProvider;
  C: TCaller;
  Job: Int64;
  Why: string;
begin
  Reg := TServiceRegistry.Create;
  P := TFakeProvider.Create(Reg);
  C := TCaller.Create;
  try
    Assert.AreEqual(cRpcInvalidParams, Reg.RegisterService('a', 'search.files', 1,
      '{"inputSchema":[]}', P.AsHandler()), 'a schema must be an object');
    Assert.AreEqual(0, Reg.RegisterService('a', 'search.files', 1,
      '{"inputSchema":{"type":"object","required":["root"],"properties":{"root":{"type":"string"}}}}',
      P.AsHandler()));
    Assert.AreEqual(0, Reg.Call('search.files', '', BuildRpcRequest(RpcIntId(1), 'search.files',
      '{"root":"C:\\Work"}'), 0, C.AsProc(), Job, Why));
    Assert.AreEqual(cRpcInvalidParams, Reg.Call('search.files', '', BuildRpcRequest(RpcIntId(2),
      'search.files', '{"root":5}'), 0, C.AsProc(), Job, Why));
    Assert.IsTrue(Pos('params.root', Why) > 0, 'the reason names the field: ' + Why);
    Assert.AreEqual<Int64>(0, Job);
    Assert.AreEqual(cRpcInvalidParams, Reg.Call('search.files', '', BuildRpcRequest(RpcIntId(3),
      'search.files', ''), 0, C.AsProc(), Job), 'missing params lack the required field');
    Assert.AreEqual<Integer>(1, P.Calls.Count, 'the provider saw only the valid call');

    Reg.RegisterService('b', 'text.extract', 1, '{"inputSchema":{"type":"blob"}}', P.AsHandler());
    Assert.AreEqual(cRpcInternalError, Reg.Call('text.extract', '', BuildRpcRequest(RpcIntId(4),
      'text.extract', '{}'), 0, C.AsProc(), Job), 'a broken schema is the provider''s fault');
  finally
    C.Free;
    P.Free;
    Reg.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestServiceRegistry);

end.
