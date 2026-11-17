unit TestBridgeHttp;

{ The HTTP channel of mtn.bridge: the event-stream parser, the sink that cuts an answer into
  messages, and the transport that turns one POST per message into the line stream a server
  process would give. The network is replaced by a scripted client. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBridgeHttp = class
  public
    [Test] procedure TestEventsAreCutAtBlankLines;
    [Test] procedure TestEventsSurviveAnySplitOfTheBytes;
    [Test] procedure TestMultiLineDataIsJoined;
    [Test] procedure TestOtherEventNamesAndCommentsAreDropped;
    [Test] procedure TestUnfinishedEventIsFlushedAtTheEnd;
    [Test] procedure TestOversizedEventIsReportedAndSkipped;
    [Test] procedure TestSinkDeliversOneJsonObject;
    [Test] procedure TestSinkDeliversEachObjectOfAnArray;
    [Test] procedure TestSinkReadsAnEventStream;
    [Test] procedure TestSinkSkipsTheByteOrderMark;
    [Test] procedure TestRequestIsAnsweredFromThePostedReply;
    [Test] procedure TestSessionIdIsSentOnTheNextPost;
    [Test] procedure TestFailedPostAnswersTheRequestWithAnError;
    [Test] procedure TestHttpStatusWithoutBodyAnswersWithAnError;
    [Test] procedure TestNotificationNeedsNoAnswer;
    [Test] procedure TestKilledTransportEndsTheReader;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  uPlatformChild, uBridgeConfig, uBridgeHttp;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function FeedAll(AParser: TSseParser; const AText: string): TArray<string>;
var
  B: TBytes;
begin
  B := Bytes(AText);
  Result := AParser.Feed(B, Length(B));
end;

procedure TTestBridgeHttp.TestEventsAreCutAtBlankLines;
var
  P: TSseParser;
  R: TArray<string>;
begin
  P := TSseParser.Create(1024);
  try
    R := FeedAll(P, 'data: {"a":1}'#13#10#13#10'data: {"b":2}'#10#10);
    Assert.AreEqual<Integer>(2, Length(R));
    Assert.AreEqual('{"a":1}', R[0]);
    Assert.AreEqual('{"b":2}', R[1]);
  finally
    P.Free;
  end;
end;

procedure TTestBridgeHttp.TestEventsSurviveAnySplitOfTheBytes;
var
  P: TSseParser;
  Text: string;
  B: TBytes;
  I: Integer;
  All, Got: TArray<string>;
begin
  Text := 'event: message'#13#10'data: {"x":"' + #$0434 + '"}'#13#10#13#10'data: {"y":2}'#13#10#13#10;
  B := Bytes(Text);
  P := TSseParser.Create(1024);
  try
    All := nil;
    for I := 0 to High(B) do
    begin
      Got := P.Feed(Copy(B, I, 1), 1);
      All := All + Got;
    end;
    Assert.AreEqual<Integer>(2, Length(All));
    Assert.AreEqual('{"x":"' + #$0434 + '"}', All[0]);
    Assert.AreEqual('{"y":2}', All[1]);
  finally
    P.Free;
  end;
end;

procedure TTestBridgeHttp.TestMultiLineDataIsJoined;
var
  P: TSseParser;
  R: TArray<string>;
begin
  P := TSseParser.Create(1024);
  try
    R := FeedAll(P, 'data: {"a":'#10'data: 1}'#10#10);
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"a":'#10'1}', R[0]);
  finally
    P.Free;
  end;
end;

procedure TTestBridgeHttp.TestOtherEventNamesAndCommentsAreDropped;
var
  P: TSseParser;
  R: TArray<string>;
begin
  P := TSseParser.Create(1024);
  try
    R := FeedAll(P, ': keep-alive'#10#10'event: ping'#10'data: {"no":1}'#10#10 +
      'id: 7'#10'data: {"yes":1}'#10#10);
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"yes":1}', R[0]);
  finally
    P.Free;
  end;
end;

procedure TTestBridgeHttp.TestUnfinishedEventIsFlushedAtTheEnd;
var
  P: TSseParser;
  R: TArray<string>;
begin
  P := TSseParser.Create(1024);
  try
    R := FeedAll(P, 'data: {"a":1}');
    Assert.AreEqual<Integer>(0, Length(R));
    R := P.Flush;
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"a":1}', R[0]);
  finally
    P.Free;
  end;
end;

procedure TTestBridgeHttp.TestOversizedEventIsReportedAndSkipped;
var
  P: TSseParser;
  R: TArray<string>;
begin
  P := TSseParser.Create(16);
  try
    R := FeedAll(P, 'data: ' + StringOfChar('x', 100) + #10#10'data: {"ok":1}'#10#10);
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"ok":1}', R[0]);
    Assert.IsTrue(P.TakeOverflow);
    Assert.IsFalse(P.TakeOverflow, 'the overflow is reported once');
  finally
    P.Free;
  end;
end;

// Runs the body through a sink and returns the messages it delivered.
function Sunk(const AChunks: array of string; out ASink: TBridgeResponseSink): TArray<string>;
var
  Got: TList<string>;
  Chunk: string;
  B: TBytes;
begin
  Got := TList<string>.Create;
  try
    ASink := TBridgeResponseSink.Create(procedure(AMessage: string) begin Got.Add(AMessage); end);
    for Chunk in AChunks do
    begin
      B := Bytes(Chunk);
      if Length(B) > 0 then
        ASink.Write(B[0], Length(B));
    end;
    ASink.Finish;
    Result := Got.ToArray;
  finally
    Got.Free;
  end;
end;

procedure TTestBridgeHttp.TestSinkDeliversOneJsonObject;
var
  S: TBridgeResponseSink;
  R: TArray<string>;
begin
  R := Sunk(['{"jsonrpc":"2.0",', ' "id":1, "result":{}}'], S);
  try
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"jsonrpc":"2.0","id":1,"result":{}}', R[0], 'compacted to one line');
    Assert.AreEqual<Integer>(1, S.Delivered);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeHttp.TestSinkDeliversEachObjectOfAnArray;
var
  S: TBridgeResponseSink;
  R: TArray<string>;
begin
  R := Sunk(['[{"id":1},', '{"id":2}]'], S);
  try
    Assert.AreEqual<Integer>(2, Length(R));
    Assert.AreEqual('{"id":2}', R[1]);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeHttp.TestSinkReadsAnEventStream;
var
  S: TBridgeResponseSink;
  R: TArray<string>;
begin
  R := Sunk(['event: message'#10'data: {"id":1}'#10#10, 'data: {"id":2}'#10#10], S);
  try
    Assert.AreEqual<Integer>(2, Length(R));
    Assert.AreEqual('{"id":1}', R[0]);
    Assert.AreEqual<Integer>(2, S.Delivered);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeHttp.TestSinkSkipsTheByteOrderMark;
var
  S: TBridgeResponseSink;
  R: TArray<string>;
begin
  R := Sunk([#$FEFF + '{"id":1}'], S);
  try
    Assert.AreEqual<Integer>(1, Length(R));
    Assert.AreEqual('{"id":1}', R[0]);
  finally
    S.Free;
  end;
end;

{ The transport over a scripted client }

type
  TPostScript = reference to function(const ABody, ASession: string; ASink: TStream;
    out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;

  TFakeClient = class(TInterfacedObject, IBridgeHttpClient)
  private
    FScript: TPostScript;
    FLock: TCriticalSection;
    FSessions: TList<string>;
    FBodies: TList<string>;
  public
    constructor Create(AScript: TPostScript);
    destructor Destroy; override;
    function Post(const AServer: TBridgeServerConfig; const ABody, ASessionId: string;
      ASink: TStream; out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;
    procedure Abort;
    function SessionCount: Integer;
    function SessionAt(AIndex: Integer): string;
  end;

constructor TFakeClient.Create(AScript: TPostScript);
begin
  inherited Create;
  FScript := AScript;
  FLock := TCriticalSection.Create;
  FSessions := TList<string>.Create;
  FBodies := TList<string>.Create;
end;

destructor TFakeClient.Destroy;
begin
  FBodies.Free;
  FSessions.Free;
  FLock.Free;
  inherited;
end;

function TFakeClient.Post(const AServer: TBridgeServerConfig; const ABody, ASessionId: string;
  ASink: TStream; out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;
begin
  FLock.Enter;
  try
    FSessions.Add(ASessionId);
    FBodies.Add(ABody);
  finally
    FLock.Leave;
  end;
  AAnswer := Default(TBridgeHttpAnswer);
  AError := '';
  Result := FScript(ABody, ASessionId, ASink, AAnswer, AError);
end;

procedure TFakeClient.Abort;
begin
end;

function TFakeClient.SessionCount: Integer;
begin
  FLock.Enter;
  try
    Result := FSessions.Count;
  finally
    FLock.Leave;
  end;
end;

function TFakeClient.SessionAt(AIndex: Integer): string;
begin
  FLock.Enter;
  try
    Result := FSessions[AIndex];
  finally
    FLock.Leave;
  end;
end;

procedure Send(const AChild: IChildProcess; const ALine: string);
var
  B: TBytes;
begin
  B := Bytes(ALine + #10);
  Assert.IsTrue(AChild.Write(B[0], Length(B)));
end;

// The next line of the transport. A watchdog ends the transport so that a missing answer
// fails the test instead of hanging it.
function ReadLine(const AChild: IChildProcess): string;
var
  Done: TEvent;
  Ch: Byte;
  Acc: TBytes;
begin
  Done := TEvent.Create(nil, True, False, '');
  try
    TThread.CreateAnonymousThread(
      procedure
      begin
        if Done.WaitFor(5000) = wrTimeout then
          AChild.Kill;
      end).Start;
    SetLength(Acc, 0);
    while AChild.ReadOut(Ch, 1) = 1 do
    begin
      if Ch = 10 then
        Break;
      SetLength(Acc, Length(Acc) + 1);
      Acc[High(Acc)] := Ch;
    end;
    Done.SetEvent;
    Result := TEncoding.UTF8.GetString(Acc);
  finally
    // The watchdog may still hold the event for a moment; it only waits on it.
    Sleep(10);
    Done.Free;
  end;
end;

function HttpConfig: TBridgeServerConfig;
begin
  Result := Default(TBridgeServerConfig);
  Result.Name := 'web';
  Result.Transport := btHttp;
  Result.Url := 'http://localhost:9/rpc';
  Result.StartTimeoutMs := 1000;
end;

procedure WriteBody(ASink: TStream; const AText: string);
var
  B: TBytes;
begin
  B := Bytes(AText);
  ASink.Write(B[0], Length(B));
end;

procedure TTestBridgeHttp.TestRequestIsAnsweredFromThePostedReply;
var
  Client: TFakeClient;
  Child: IChildProcess;
begin
  Client := TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      AAnswer.Status := 200;
      WriteBody(ASink, '{"jsonrpc":"2.0","id":5,"result":{"ok":true}}');
      Result := True;
    end);
  Child := TBridgeHttpChild.Create(HttpConfig, Client);
  try
    Send(Child, '{"jsonrpc":"2.0","id":5,"method":"initialize"}');
    Assert.AreEqual('{"jsonrpc":"2.0","id":5,"result":{"ok":true}}', ReadLine(Child));
  finally
    Child.Kill;
  end;
end;

procedure TTestBridgeHttp.TestSessionIdIsSentOnTheNextPost;
var
  Client: TFakeClient;
  Child: IChildProcess;
begin
  Client := TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      AAnswer.Status := 200;
      AAnswer.SessionId := 'abc123';
      if Pos('"id":1', ABody) > 0 then
        WriteBody(ASink, '{"jsonrpc":"2.0","id":1,"result":{}}')
      else
        WriteBody(ASink, '{"jsonrpc":"2.0","id":2,"result":{}}');
      Result := True;
    end);
  Child := TBridgeHttpChild.Create(HttpConfig, Client);
  try
    Send(Child, '{"jsonrpc":"2.0","id":1,"method":"initialize"}');
    ReadLine(Child);
    Send(Child, '{"jsonrpc":"2.0","id":2,"method":"tools/list"}');
    ReadLine(Child);
    Assert.AreEqual<Integer>(2, Client.SessionCount);
    Assert.AreEqual('', Client.SessionAt(0), 'the first post has no session');
    Assert.AreEqual('abc123', Client.SessionAt(1), 'the id the server gave is sent back');
  finally
    Child.Kill;
  end;
end;

procedure TTestBridgeHttp.TestFailedPostAnswersTheRequestWithAnError;
var
  Child: IChildProcess;
  Line: string;
begin
  Child := TBridgeHttpChild.Create(HttpConfig, TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      AError := 'connection refused';
      Result := False;
    end));
  try
    Send(Child, '{"jsonrpc":"2.0","id":9,"method":"tools/call"}');
    Line := ReadLine(Child);
    Assert.IsTrue(Pos('"id":9', Line) > 0, Line);
    Assert.IsTrue(Pos('"error"', Line) > 0, Line);
    Assert.IsTrue(Pos('connection refused', Line) > 0, Line);
  finally
    Child.Kill;
  end;
end;

procedure TTestBridgeHttp.TestHttpStatusWithoutBodyAnswersWithAnError;
var
  Child: IChildProcess;
  Line: string;
begin
  Child := TBridgeHttpChild.Create(HttpConfig, TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      AAnswer.Status := 503;
      Result := True;
    end));
  try
    Send(Child, '{"jsonrpc":"2.0","id":3,"method":"tools/list"}');
    Line := ReadLine(Child);
    Assert.IsTrue(Pos('"id":3', Line) > 0, Line);
    Assert.IsTrue(Pos('HTTP 503', Line) > 0, Line);
  finally
    Child.Kill;
  end;
end;

procedure TTestBridgeHttp.TestNotificationNeedsNoAnswer;
var
  Client: TFakeClient;
  Child: IChildProcess;
  Line: string;
begin
  Client := TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      if Pos('"method"', ABody) > 0 then
      begin
        // 202 without a body: a notification has no answer.
        AAnswer.Status := 202;
        Result := True;
      end
      else
        Result := False;
    end);
  Child := TBridgeHttpChild.Create(HttpConfig, Client);
  try
    Send(Child, '{"jsonrpc":"2.0","method":"notifications/initialized"}');
    Send(Child, '{"jsonrpc":"2.0","id":4,"method":"ping"}');
    // The ping is answered with 202 and no body, which is an error line for that request
    // only: nothing came for the notification.
    Line := ReadLine(Child);
    Assert.IsTrue(Pos('"id":4', Line) > 0, Line);
  finally
    Child.Kill;
  end;
end;

procedure TTestBridgeHttp.TestKilledTransportEndsTheReader;
var
  Child: IChildProcess;
  Ch: Byte;
  Reader: TThread;
  Ended: TEvent;
begin
  Child := TBridgeHttpChild.Create(HttpConfig, TFakeClient.Create(
    function(const ABody, ASession: string; ASink: TStream; out AAnswer: TBridgeHttpAnswer;
      out AError: string): Boolean
    begin
      Result := False;
    end));
  Ended := TEvent.Create(nil, True, False, '');
  try
    Reader := TThread.CreateAnonymousThread(
      procedure
      begin
        Child.ReadOut(Ch, 1);
        Ended.SetEvent;
      end);
    Reader.FreeOnTerminate := False;
    Reader.Start;
    Sleep(50);
    Child.Kill;
    Assert.IsTrue(Ended.WaitFor(3000) = wrSignaled, 'a blocked read ends with the transport');
    Reader.WaitFor;
    Reader.Free;
  finally
    Ended.Free;
  end;
end;

end.
