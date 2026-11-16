unit TestPluginServiceHost;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginServiceHost = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRegisterRejectsBadArguments;
    [Test] procedure TestSyncCallThroughProvider;
    [Test] procedure TestSyncCallReportsSmallBuffer;
    [Test] procedure TestSyncCallWithoutProvider;
    [Test] procedure TestAsyncCallDeliversNotificationThenResponse;
    [Test] procedure TestStatusAndCancel;
    [Test] procedure TestUnregisterEndsOpenCalls;
    [Test] procedure TestSilentProviderTimesOut;
  end;

implementation

uses
  System.SysUtils, uPluginHostAbi, uPluginServiceHost, uServiceRegistry, uJsonRpc;

const
  cPlugin = 'test.provider';
  cRequest = '{"jsonrpc":"2.0","id":1,"method":"test.echo"}';
  cOkResponse = '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}';

var
  GResponses: array of string;
  GStayOpen: Boolean;

function EchoHandler(AUserData: Pointer; ACall: Int64; AMessageJson: PAnsiChar): Int64; cdecl;
begin
  if not GStayOpen then
  begin
    HostServiceNotify(ACall,
      '{"jsonrpc":"2.0","method":"service.progress","params":{"progress":1,"total":2,"message":"half"}}');
    HostServiceReply(ACall, cOkResponse);
  end;
  Result := 0;
end;

procedure Collect(AUserData: Pointer; AJobId: Int64; AMessageJson: PAnsiChar); cdecl;
begin
  SetLength(GResponses, Length(GResponses) + 1);
  GResponses[High(GResponses)] := UTF8ToString(AMessageJson);
end;

function RegisterEcho: Int64;
begin
  Result := HostRegisterService(cPlugin, 'test.echo', 1, '{}', EchoHandler, nil, 100);
end;

procedure Drain;
var
  I: Integer;
begin
  for I := 1 to 3 do
    ServiceRegistry.Pump;
end;

procedure TTestPluginServiceHost.Setup;
begin
  PluginServicesUnregister(cPlugin);
  Drain;
  SetLength(GResponses, 0);
  GStayOpen := False;
end;

procedure TTestPluginServiceHost.TearDown;
begin
  PluginServicesUnregister(cPlugin);
  Drain;
end;

procedure TTestPluginServiceHost.TestRegisterRejectsBadArguments;
begin
  Assert.AreEqual<Int64>(cRpcInvalidParams, HostRegisterService(nil, 'test.echo', 1, '{}', EchoHandler, nil, 100));
  Assert.AreEqual<Int64>(cRpcInvalidParams, HostRegisterService(cPlugin, 'test.echo', 0, '{}', EchoHandler, nil, 100),
    'version below 1');
  Assert.AreEqual<Int64>(cRpcInvalidParams, HostRegisterService(cPlugin, 'test.echo', 1, '{}', nil, nil, 100),
    'no handler');
  Assert.AreEqual<Int64>(cRpcNotAllowed, HostRegisterService(cPlugin, 'host.anything', 1, '{}', EchoHandler, nil, 100),
    'reserved name');
  Assert.AreEqual<Int64>(0, RegisterEcho);
end;

procedure TTestPluginServiceHost.TestSyncCallThroughProvider;
var
  Buf: array[0..511] of AnsiChar;
  Need: Int64;
begin
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(0, HostCallService(nil, 'test.echo', cRequest, 1000, @Buf[0], SizeOf(Buf), Need));
  Assert.AreEqual(cOkResponse, UTF8ToString(PAnsiChar(@Buf[0])));
  Assert.AreEqual<Int64>(Length(cOkResponse), Need);
end;

procedure TTestPluginServiceHost.TestSyncCallReportsSmallBuffer;
var
  Buf: array[0..3] of AnsiChar;
  Need: Int64;
begin
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(-2, HostCallService(nil, 'test.echo', cRequest, 1000, @Buf[0], SizeOf(Buf), Need));
  Assert.AreEqual<Int64>(Length(cOkResponse), Need, 'the size needed is reported');
end;

procedure TTestPluginServiceHost.TestSyncCallWithoutProvider;
var
  Buf: array[0..63] of AnsiChar;
  Need: Int64;
begin
  Assert.AreEqual<Int64>(cRpcMethodNotFound, HostCallService(nil, 'test.echo', cRequest, 1000,
    @Buf[0], SizeOf(Buf), Need));
  Assert.AreEqual<Int64>(cRpcInvalidParams, HostCallService(nil, 'test.echo', cRequest, 0,
    @Buf[0], SizeOf(Buf), Need), 'a sync call needs a time limit');
end;

procedure TTestPluginServiceHost.TestAsyncCallDeliversNotificationThenResponse;
var
  Job: Int64;
begin
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(0, HostCallServiceAsync(nil, 'test.echo', cRequest, 0, Collect, nil, Job));
  Assert.IsTrue(Job > 0);
  Drain;
  Assert.AreEqual<Integer>(2, Length(GResponses), 'a notification and the response');
  Assert.IsTrue(Pos('service.progress', GResponses[0]) > 0, 'the notification first');
  Assert.IsTrue(Pos('"result"', GResponses[1]) > 0, 'the response last');
end;

procedure TTestPluginServiceHost.TestStatusAndCancel;
var
  Job: Int64;
  Buf: array[0..255] of AnsiChar;
begin
  GStayOpen := True;
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(0, HostCallServiceAsync(nil, 'test.echo', cRequest, 0, Collect, nil, Job));
  Assert.IsTrue(HostServiceStatus(Job, @Buf[0], SizeOf(Buf)) > 0);
  Assert.IsTrue(Pos('"running"', UTF8ToString(PAnsiChar(@Buf[0]))) > 0);
  Assert.AreEqual<Int64>(0, HostCancelService(Job));
  Assert.AreEqual<Int64>(-1, HostCancelService(Job), 'already ended');
  Drain;
  Assert.AreEqual<Integer>(1, Length(GResponses));
  Assert.IsTrue(Pos('-32001', GResponses[0]) > 0, 'cancelled: ' + GResponses[0]);
  Assert.IsTrue(HostServiceStatus(Job, @Buf[0], SizeOf(Buf)) > 0);
  Assert.IsTrue(Pos('"cancelled"', UTF8ToString(PAnsiChar(@Buf[0]))) > 0);
  Assert.AreEqual<Int64>(-1, HostServiceStatus(Job + 1000, @Buf[0], SizeOf(Buf)), 'unknown call');
end;

procedure TTestPluginServiceHost.TestUnregisterEndsOpenCalls;
var
  Job: Int64;
begin
  GStayOpen := True;
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(0, HostCallServiceAsync(nil, 'test.echo', cRequest, 0, Collect, nil, Job));
  PluginServicesUnregister(cPlugin);
  Drain;
  Assert.AreEqual<Integer>(1, Length(GResponses));
  Assert.IsTrue(Pos('-32603', GResponses[0]) > 0, 'the call ends with an error: ' + GResponses[0]);
  Assert.AreEqual<Int64>(cRpcMethodNotFound, HostCallServiceAsync(nil, 'test.echo', cRequest, 0,
    Collect, nil, Job), 'the service is gone');
end;

procedure TTestPluginServiceHost.TestSilentProviderTimesOut;
var
  Buf: array[0..255] of AnsiChar;
  Need: Int64;
begin
  GStayOpen := True;
  Assert.AreEqual<Int64>(0, RegisterEcho);
  Assert.AreEqual<Int64>(0, HostCallService(nil, 'test.echo', cRequest, 50, @Buf[0], SizeOf(Buf), Need),
    'the response is the timeout error');
  Assert.IsTrue(Pos('-32005', UTF8ToString(PAnsiChar(@Buf[0]))) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginServiceHost);

end.
