unit TestBridgeServer;

{ One service process of mtn.bridge, driven through a fake process that answers from a
  script: handshake, tool list, calls, progress, cancel, timeout and the end of the process. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBridgeServer = class
  public
    [Test] procedure TestStartReadsTheTools;
    [Test] procedure TestToolListPagesAreJoined;
    [Test] procedure TestAllowListFiltersTheTools;
    [Test] procedure TestUnknownProtocolVersionStopsTheServer;
    [Test] procedure TestSilentServerFailsTheHandshake;
    [Test] procedure TestProgramThatCannotStartFails;
    [Test] procedure TestCallReturnsTheResult;
    [Test] procedure TestToolErrorIsReported;
    [Test] procedure TestProgressReachesTheCaller;
    [Test] procedure TestCancelSendsNoticeAndDropsTheReply;
    [Test] procedure TestUnansweredCallTimesOut;
    [Test] procedure TestEndOfTheProcessFailsWaitingCalls;
    [Test] procedure TestTooManyWaitingCallsAreRefused;
    [Test] procedure TestGarbageLinesAreIgnored;
    [Test] procedure TestPingOfTheServerIsAnswered;
    [Test] procedure TestStoppedServerRefusesCalls;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  uPlatformChild, uJsonRpc, uBridgeConfig, uBridgeProtocol, uBridgeServer;

type
  /// <summary>Answers each line the server writes with the lines the script returns.</summary>
  TScript = reference to function(const ALine: string): TArray<string>;

  TFakeChild = class(TInterfacedObject, IChildProcess)
  private
    FScript: TScript;
    FLock: TCriticalSection;
    FOut: TQueue<TBytes>;
    FAvail: TEvent;
    FClosed: Boolean;
    FReceived: TStringList;
    FPartial: string;
  public
    constructor Create(AScript: TScript);
    destructor Destroy; override;
    function Write(const ABuf; ACount: Integer): Boolean;
    function ReadOut(var ABuf; ACount: Integer): Integer;
    function ReadErr(var ABuf; ACount: Integer): Integer;
    procedure CloseInput;
    procedure Kill;
    function WaitExit(ATimeoutMs: Cardinal): Boolean;
    function ExitCode: Cardinal;
    /// <summary>Lines from the process, as if it wrote them on its own.</summary>
    procedure Push(const ALine: string);
    /// <summary>The process ends.</summary>
    procedure Die;
    function Received: TArray<string>;
    function ReceivedCount(const AMethod: string): Integer;
  end;

constructor TFakeChild.Create(AScript: TScript);
begin
  inherited Create;
  FScript := AScript;
  FLock := TCriticalSection.Create;
  FOut := TQueue<TBytes>.Create;
  FAvail := TEvent.Create(nil, True, False, '');
  FReceived := TStringList.Create;
end;

destructor TFakeChild.Destroy;
begin
  FReceived.Free;
  FAvail.Free;
  FOut.Free;
  FLock.Free;
  inherited;
end;

procedure TFakeChild.Push(const ALine: string);
begin
  FLock.Enter;
  try
    FOut.Enqueue(TEncoding.UTF8.GetBytes(ALine + #10));
    FAvail.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TFakeChild.Die;
begin
  FLock.Enter;
  try
    FClosed := True;
    FAvail.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TFakeChild.Write(const ABuf; ACount: Integer): Boolean;
var
  B: TBytes;
  Text, Line: string;
  P: Integer;
  Replies: TArray<string>;
  R: string;
begin
  SetLength(B, ACount);
  Move(ABuf, B[0], ACount);
  FLock.Enter;
  try
    if FClosed then
      Exit(False);
    FPartial := FPartial + TEncoding.UTF8.GetString(B);
    P := Pos(#10, FPartial);
    while P > 0 do
    begin
      Line := Copy(FPartial, 1, P - 1);
      Delete(FPartial, 1, P);
      FReceived.Add(Line);
      Text := Line;
      FLock.Leave;
      try
        Replies := FScript(Text);
      finally
        FLock.Enter;
      end;
      for R in Replies do
      begin
        FOut.Enqueue(TEncoding.UTF8.GetBytes(R + #10));
        FAvail.SetEvent;
      end;
      P := Pos(#10, FPartial);
    end;
  finally
    FLock.Leave;
  end;
  Result := True;
end;

function TFakeChild.ReadOut(var ABuf; ACount: Integer): Integer;
var
  B: TBytes;
begin
  Result := 0;
  while True do
  begin
    FLock.Enter;
    try
      if FOut.Count > 0 then
      begin
        B := FOut.Dequeue;
        if Length(B) > ACount then
          raise Exception.Create('the fake sends short lines');
        Move(B[0], ABuf, Length(B));
        Exit(Length(B));
      end;
      if FClosed then
        Exit(0);
      FAvail.ResetEvent;
    finally
      FLock.Leave;
    end;
    FAvail.WaitFor(INFINITE);
  end;
end;

function TFakeChild.ReadErr(var ABuf; ACount: Integer): Integer;
begin
  FAvail.WaitFor(0);
  // No stderr; ends with the process.
  while not FClosed do
    Sleep(5);
  Result := 0;
end;

procedure TFakeChild.CloseInput;
begin
end;

procedure TFakeChild.Kill;
begin
  Die;
end;

function TFakeChild.WaitExit(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FClosed;
end;

function TFakeChild.ExitCode: Cardinal;
begin
  Result := 0;
end;

function TFakeChild.Received: TArray<string>;
var
  I: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FReceived.Count);
    for I := 0 to FReceived.Count - 1 do
      Result[I] := FReceived[I];
  finally
    FLock.Leave;
  end;
end;

function TFakeChild.ReceivedCount(const AMethod: string): Integer;
var
  Line: string;
begin
  Result := 0;
  for Line in Received do
    if Pos('"method":"' + AMethod + '"', Line) > 0 then
      Inc(Result);
end;

function IdOf(const ALine: string): string;
var
  Msg: TRpcMessage;
  Code: Integer;
begin
  Result := 'null';
  if TryParseRpcMessage(ALine, Msg, Code) then
    Result := Msg.Id.ToJson;
end;

function MethodOf(const ALine: string): string;
var
  Msg: TRpcMessage;
  Code: Integer;
begin
  Result := '';
  if TryParseRpcMessage(ALine, Msg, Code) then
    Result := Msg.Method;
end;

function Reply(const AId, AResultJson: string): string;
begin
  Result := '{"jsonrpc":"2.0","id":' + AId + ',"result":' + AResultJson + '}';
end;

function DefaultServer(const ALine: string): TArray<string>;
var
  M: string;
begin
  M := MethodOf(ALine);
  if M = 'initialize' then
    Result := [Reply(IdOf(ALine), '{"protocolVersion":"' + cBridgeProtocolVersion + '"}')]
  else if M = 'tools/list' then
    Result := [Reply(IdOf(ALine),
      '{"tools":[{"name":"find","description":"Finds"},{"name":"count"}]}')]
  else if M = 'tools/call' then
    Result := [Reply(IdOf(ALine), '{"content":[],"structuredContent":{"ok":true}}')]
  else
    Result := [];
end;

function Config(const AName: string): TBridgeServerConfig;
begin
  Result := Default(TBridgeServerConfig);
  Result.Name := AName;
  Result.Command := 'fake';
  Result.StartTimeoutMs := 1000;
end;

function MakeServer(const AConfig: TBridgeServerConfig; AScript: TScript;
  out AChild: TFakeChild): TBridgeServer;
var
  Child: TFakeChild;
  Hold: IChildProcess;
begin
  Child := TFakeChild.Create(AScript);
  // The factory keeps the process alive for the whole life of the server, as the test
  // reads it after the server ended it.
  Hold := Child;
  AChild := Child;
  Result := TBridgeServer.Create(AConfig,
    function(const AServer: TBridgeServerConfig; out AProcess: IChildProcess): Boolean
    begin
      AProcess := Hold;
      Result := True;
    end);
end;

function WaitFor(const AFlag: TEvent; AMs: Cardinal = 5000): Boolean;
begin
  Result := AFlag.WaitFor(AMs) = wrSignaled;
end;

procedure TTestBridgeServer.TestStartReadsTheTools;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
begin
  S := MakeServer(Config('s'), DefaultServer, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Assert.IsTrue(S.Running);
    Assert.AreEqual<Integer>(2, Length(S.Tools));
    Assert.AreEqual('find', S.Tools[0].Name);
    Assert.AreEqual<Integer>(1, Child.ReceivedCount('notifications/initialized'), 'the handshake is completed');
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestToolListPagesAreJoined;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
begin
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) <> 'tools/list' then
        Exit(DefaultServer(ALine));
      if Pos('"cursor":"p2"', ALine) > 0 then
        Result := [Reply(IdOf(ALine), '{"tools":[{"name":"second"}]}')]
      else
        Result := [Reply(IdOf(ALine), '{"tools":[{"name":"first"}],"nextCursor":"p2"}')];
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Assert.AreEqual<Integer>(2, Length(S.Tools));
    Assert.AreEqual('second', S.Tools[1].Name);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestAllowListFiltersTheTools;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Cfg: TBridgeServerConfig;
  Err: string;
begin
  Cfg := Config('s');
  Cfg.Allow := ['count'];
  S := MakeServer(Cfg, DefaultServer, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Assert.AreEqual<Integer>(1, Length(S.Tools));
    Assert.AreEqual('count', S.Tools[0].Name);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestUnknownProtocolVersionStopsTheServer;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
begin
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'initialize' then
        Result := [Reply(IdOf(ALine), '{"protocolVersion":"1999-01-01"}')]
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsFalse(S.Start(Err));
    Assert.IsFalse(S.Running, 'the process is ended');
    Assert.IsTrue(Pos('protocol', Err) > 0, Err);
    Assert.AreEqual<Integer>(0, Child.ReceivedCount('tools/list'), 'nothing is asked after a failed handshake');
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestSilentServerFailsTheHandshake;
var
  Child: TFakeChild;
  Cfg: TBridgeServerConfig;
  S: TBridgeServer;
  Err: string;
begin
  Cfg := Config('s');
  Cfg.StartTimeoutMs := 300;
  S := MakeServer(Cfg,
    function(const ALine: string): TArray<string>
    begin
      Result := [];
    end, Child);
  try
    Assert.IsFalse(S.Start(Err));
    Assert.IsFalse(S.Running);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestProgramThatCannotStartFails;
var
  S: TBridgeServer;
  Err: string;
begin
  S := TBridgeServer.Create(Config('s'),
    function(const AServer: TBridgeServerConfig; out AProcess: IChildProcess): Boolean
    begin
      AProcess := nil;
      Result := False;
    end);
  try
    Assert.IsFalse(S.Start(Err));
    Assert.IsTrue(Pos('cannot start', Err) > 0, Err);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestCallReturnsTheResult;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Got: TBridgeReply;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'), DefaultServer, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Assert.IsTrue(S.Call('find', '{"text":"a"}', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Got := AReply;
        Done.SetEvent;
      end, nil, Id));
    Assert.IsTrue(WaitFor(Done), 'the reply arrives');
    Assert.IsFalse(Got.Failed);
    Assert.IsTrue(Pos('"ok":true', Got.ResultJson) > 0);
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestToolErrorIsReported;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Got: TBridgeReply;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := [Reply(IdOf(ALine), '{"isError":true,"content":[{"type":"text","text":"no disk"}]}')]
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Call('find', '', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Got := AReply;
        Done.SetEvent;
      end, nil, Id);
    Assert.IsTrue(WaitFor(Done));
    Assert.IsTrue(Got.Failed);
    Assert.AreEqual('no disk', Got.ErrorText);
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestProgressReachesTheCaller;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Seen: string;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := ['{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":' +
          IdOf(ALine) + ',"progress":1,"message":"working"}}',
          Reply(IdOf(ALine), '{"content":[]}')]
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Call('find', '', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Done.SetEvent;
      end,
      procedure(const AText: string)
      begin
        Seen := AText;
      end, Id);
    Assert.IsTrue(WaitFor(Done));
    Assert.AreEqual('working', Seen);
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestCancelSendsNoticeAndDropsTheReply;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Replied: Boolean;
  Id: Integer;
begin
  Replied := False;
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := []
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Assert.IsTrue(S.Call('find', '', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Replied := True;
      end, nil, Id));
    S.Cancel(Id);
    Assert.AreEqual<Integer>(1, Child.ReceivedCount('notifications/cancelled'));
    Child.Push(Reply(IntToStr(Id), '{"content":[]}'));
    Sleep(100);
    Assert.IsFalse(Replied, 'a call that was cancelled gets no reply');
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestUnansweredCallTimesOut;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Got: TBridgeReply;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := []
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Call('find', '', 200,
      procedure(const AReply: TBridgeReply)
      begin
        Got := AReply;
        Done.SetEvent;
      end, nil, Id);
    Assert.IsTrue(WaitFor(Done), 'the watchdog ends the wait');
    Assert.IsTrue(Got.Failed);
    Assert.AreEqual(cRpcTimeout, Got.ErrorCode);
    Assert.AreEqual<Integer>(1, Child.ReceivedCount('notifications/cancelled'), 'the server is told');
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestEndOfTheProcessFailsWaitingCalls;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Got: TBridgeReply;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := []
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Call('find', '', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Got := AReply;
        Done.SetEvent;
      end, nil, Id);
    Child.Die;
    Assert.IsTrue(WaitFor(Done), 'the waiting call is failed');
    Assert.IsTrue(Got.Failed);
    Assert.IsTrue(Pos('ended', Got.ErrorText) > 0, Got.ErrorText);
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestTooManyWaitingCallsAreRefused;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  I, Id, Accepted: Integer;
begin
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := []
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Accepted := 0;
    for I := 1 to cBridgeMaxPending + 4 do
      if S.Call('find', '', 0, procedure(const AReply: TBridgeReply) begin end, nil, Id) then
        Inc(Accepted);
    Assert.AreEqual(cBridgeMaxPending, Accepted);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestGarbageLinesAreIgnored;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Done: TEvent;
  Got: TBridgeReply;
  Id: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  S := MakeServer(Config('s'),
    function(const ALine: string): TArray<string>
    begin
      if MethodOf(ALine) = 'tools/call' then
        Result := ['starting up...', '{"half":', Reply('999', '{}'), Reply(IdOf(ALine), '{"content":[]}')]
      else
        Result := DefaultServer(ALine);
    end, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Call('find', '', 0,
      procedure(const AReply: TBridgeReply)
      begin
        Got := AReply;
        Done.SetEvent;
      end, nil, Id);
    Assert.IsTrue(WaitFor(Done));
    Assert.IsFalse(Got.Failed, 'noise and answers to other ids do not disturb the call');
  finally
    S.Free;
    Done.Free;
  end;
end;

procedure TTestBridgeServer.TestPingOfTheServerIsAnswered;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Tick: UInt64;
  Line: string;
  Found: Boolean;
begin
  S := MakeServer(Config('s'), DefaultServer, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    Child.Push('{"jsonrpc":"2.0","id":77,"method":"ping"}');
    Child.Push('{"jsonrpc":"2.0","id":78,"method":"sampling/createMessage"}');
    Found := False;
    Tick := TThread.GetTickCount64;
    while not Found and (TThread.GetTickCount64 - Tick < 3000) do
    begin
      for Line in Child.Received do
        if (Pos('"id":78', Line) > 0) and (Pos('-32601', Line) > 0) then
          Found := True;
      Sleep(10);
    end;
    Assert.IsTrue(Found, 'a request the bridge does not offer is refused');
    Found := False;
    for Line in Child.Received do
      if (Pos('"id":77', Line) > 0) and (Pos('"result"', Line) > 0) then
        Found := True;
    Assert.IsTrue(Found, 'ping is answered');
  finally
    S.Free;
  end;
end;

procedure TTestBridgeServer.TestStoppedServerRefusesCalls;
var
  Child: TFakeChild;
  S: TBridgeServer;
  Err: string;
  Id: Integer;
begin
  S := MakeServer(Config('s'), DefaultServer, Child);
  try
    Assert.IsTrue(S.Start(Err), Err);
    S.Stop;
    Assert.IsFalse(S.Running);
    Assert.IsFalse(S.Call('find', '', 0, procedure(const AReply: TBridgeReply) begin end, nil, Id));
  finally
    S.Free;
  end;
end;

end.
