unit TestBridgeProtocol;

{ The messages of mtn.bridge: line framing, handshake, tool list, tool calls. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBridgeProtocol = class
  public
    [Test] procedure TestSplitterCutsLines;
    [Test] procedure TestSplitterJoinsPiecesOfOneLine;
    [Test] procedure TestSplitterKeepsMultiByteCharactersAcrossChunks;
    [Test] procedure TestSplitterDropsTooLongLineOnce;
    [Test] procedure TestSplitterRecoversAfterLongLine;
    [Test] procedure TestInitializeRequestCarriesVersion;
    [Test] procedure TestInitializeResultAcceptsKnownVersionsOnly;
    [Test] procedure TestToolsListPageAndCursor;
    [Test] procedure TestServiceNameIsSanitized;
    [Test] procedure TestToolCallRequest;
    [Test] procedure TestProgressNotificationIsParsed;
    [Test] procedure TestToolResultPassesThrough;
    [Test] procedure TestToolErrorBecomesServiceError;
    [Test] procedure TestProtocolErrorKeepsItsCode;
  end;

implementation

uses
  System.SysUtils, System.JSON, uJsonRpc, uBridgeProtocol;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function FeedText(ASplitter: TLineSplitter; const AText: string): TArray<string>;
var
  B: TBytes;
begin
  B := Bytes(AText);
  Result := ASplitter.Feed(B, Length(B));
end;

procedure TTestBridgeProtocol.TestSplitterCutsLines;
var
  S: TLineSplitter;
  L: TArray<string>;
begin
  S := TLineSplitter.Create;
  try
    L := FeedText(S, 'one'#10'two'#13#10#10'three'#10);
    Assert.AreEqual<Integer>(3, Length(L), 'blank lines are skipped');
    Assert.AreEqual('one', L[0]);
    Assert.AreEqual('two', L[1], 'the CR of CRLF is dropped');
    Assert.AreEqual('three', L[2]);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeProtocol.TestSplitterJoinsPiecesOfOneLine;
var
  S: TLineSplitter;
  L: TArray<string>;
begin
  S := TLineSplitter.Create;
  try
    Assert.AreEqual<Integer>(0, Length(FeedText(S, '{"a"')));
    Assert.AreEqual<Integer>(0, Length(FeedText(S, ':1}')));
    L := FeedText(S, #10);
    Assert.AreEqual<Integer>(1, Length(L));
    Assert.AreEqual('{"a":1}', L[0]);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeProtocol.TestSplitterKeepsMultiByteCharactersAcrossChunks;
var
  S: TLineSplitter;
  B: TBytes;
  L: TArray<string>;
begin
  S := TLineSplitter.Create;
  try
    B := Bytes(#$0416#10); // a two-byte character
    Assert.AreEqual<Integer>(0, Length(S.Feed(B, 1)));
    L := S.Feed(Copy(B, 1, 2), 2);
    Assert.AreEqual<Integer>(1, Length(L));
    Assert.AreEqual(#$0416, L[0]);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeProtocol.TestSplitterDropsTooLongLineOnce;
var
  S: TLineSplitter;
begin
  S := TLineSplitter.Create(10);
  try
    Assert.AreEqual<Integer>(0, Length(FeedText(S, '0123456789ABCDEF'#10)));
    Assert.IsTrue(S.TakeOverflow, 'the drop is reported');
    Assert.IsFalse(S.TakeOverflow, 'only once');
  finally
    S.Free;
  end;
end;

procedure TTestBridgeProtocol.TestSplitterRecoversAfterLongLine;
var
  S: TLineSplitter;
  L: TArray<string>;
begin
  S := TLineSplitter.Create(10);
  try
    // The long line arrives in pieces; the line after it is read normally.
    FeedText(S, '0123456');
    FeedText(S, '789ABCDEF');
    L := FeedText(S, 'GHI'#10'ok'#10);
    Assert.AreEqual<Integer>(1, Length(L));
    Assert.AreEqual('ok', L[0]);
    Assert.IsTrue(S.TakeOverflow);
  finally
    S.Free;
  end;
end;

procedure TTestBridgeProtocol.TestInitializeRequestCarriesVersion;
var
  Root: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(BuildInitializeRequest(1));
  try
    Assert.AreEqual('initialize', TJSONObject(Root).GetValue<string>('method'));
    Assert.AreEqual(cBridgeProtocolVersion,
      TJSONObject(Root).GetValue('params').GetValue<string>('protocolVersion'));
  finally
    Root.Free;
  end;
  Assert.IsTrue(Pos('notifications/initialized', BuildInitializedNotification) > 0);
  Assert.IsFalse(Pos('"id"', BuildInitializedNotification) > 0, 'a notification has no id');
end;

procedure TTestBridgeProtocol.TestInitializeResultAcceptsKnownVersionsOnly;
var
  V: string;
begin
  Assert.IsTrue(ParseInitializeResult(
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"' + cBridgeProtocolVersion + '"}}', V));
  Assert.AreEqual(cBridgeProtocolVersion, V);
  Assert.IsFalse(ParseInitializeResult(
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1999-01-01"}}', V), 'unknown version');
  Assert.IsFalse(ParseInitializeResult(
    '{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"no"}}', V));
  Assert.IsFalse(ParseInitializeResult('{"jsonrpc":"2.0","id":1,"result":{}}', V));
end;

procedure TTestBridgeProtocol.TestToolsListPageAndCursor;
var
  Tools: TArray<TBridgeTool>;
  Cursor: string;
begin
  Assert.IsTrue(ParseToolsList(
    '{"jsonrpc":"2.0","id":2,"result":{"tools":[' +
    '{"name":"find","description":"Finds","inputSchema":{"type":"object"}},' +
    '{"description":"no name"},7,{"name":"other"}],"nextCursor":"p2"}}', Tools, Cursor));
  Assert.AreEqual<Integer>(2, Length(Tools), 'entries without a name are left out');
  Assert.AreEqual('find', Tools[0].Name);
  Assert.AreEqual('Finds', Tools[0].Description);
  Assert.IsTrue(Pos('object', Tools[0].InputSchemaJson) > 0);
  Assert.AreEqual('', Tools[1].InputSchemaJson);
  Assert.AreEqual('p2', Cursor);
  Assert.IsTrue(Pos('"cursor":"p2"', BuildToolsListRequest(3, 'p2')) > 0);
  Assert.IsFalse(Pos('cursor', BuildToolsListRequest(3, '')) > 0);
  Assert.IsFalse(ParseToolsList('{"jsonrpc":"2.0","id":2,"result":{}}', Tools, Cursor));
end;

procedure TTestBridgeProtocol.TestServiceNameIsSanitized;
begin
  Assert.AreEqual('bridge.py_tools.find-files', BridgeServiceName('Py Tools', 'Find-Files'));
  Assert.AreEqual('bridge.a_b.x_y', BridgeServiceName('a.b', 'x/y'));
  Assert.AreEqual('', BridgeServiceName('', 'tool'));
  Assert.AreEqual('', BridgeServiceName('srv', '  '));
end;

procedure TTestBridgeProtocol.TestToolCallRequest;
var
  Root: TJSONValue;
begin
  Root := TJSONObject.ParseJSONValue(BuildToolCallRequest(5, 'find', '{"text":"a"}'));
  try
    Assert.AreEqual('tools/call', TJSONObject(Root).GetValue<string>('method'));
    Assert.AreEqual('find', TJSONObject(Root).GetValue('params').GetValue<string>('name'));
    Assert.AreEqual('a', TJSONObject(TJSONObject(TJSONObject(Root).GetValue('params')).GetValue('arguments')).GetValue<string>('text'));
  finally
    Root.Free;
  end;
  Assert.IsTrue(Pos('"arguments":{}', BuildToolCallRequest(6, 'x', '')) > 0, 'missing arguments become an object');
  Assert.IsTrue(Pos('"requestId":9', BuildCancelNotification(9, 'stop')) > 0);
end;

procedure TTestBridgeProtocol.TestProgressNotificationIsParsed;
var
  Token: Integer;
  Text: string;
begin
  Assert.IsTrue(ParseProgressNotification(
    '{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":5,"progress":3,"message":"half"}}',
    Token, Text));
  Assert.AreEqual(5, Token);
  Assert.AreEqual('half', Text);
  Assert.IsFalse(ParseProgressNotification('{"jsonrpc":"2.0","method":"other","params":{}}', Token, Text));
  Assert.IsFalse(ParseProgressNotification(
    '{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"x"}}', Token, Text),
    'only the integer ids of the bridge');
  Assert.IsTrue(Pos('"progressToken":5', BuildToolCallRequest(5, 'f', '')) > 0, 'the call asks for progress');
end;

procedure TTestBridgeProtocol.TestToolResultPassesThrough;
var
  R: TBridgeReply;
begin
  R := MapToolResponse('{"jsonrpc":"2.0","id":5,"result":{"content":[],"structuredContent":{"count":2}}}');
  Assert.IsFalse(R.Failed);
  Assert.IsTrue(Pos('"count":2', R.ResultJson) > 0);
end;

procedure TTestBridgeProtocol.TestToolErrorBecomesServiceError;
var
  R: TBridgeReply;
begin
  R := MapToolResponse('{"jsonrpc":"2.0","id":5,"result":{"isError":true,' +
    '"content":[{"type":"text","text":"disk full"},{"type":"image"},{"type":"text","text":"retry"}]}}');
  Assert.IsTrue(R.Failed);
  Assert.AreEqual(cRpcInternalError, R.ErrorCode);
  Assert.AreEqual('disk full'#10'retry', R.ErrorText);
  R := MapToolResponse('{"jsonrpc":"2.0","id":5,"result":{"isError":true}}');
  Assert.IsTrue(R.Failed);
  Assert.AreEqual('the tool failed', R.ErrorText);
end;

procedure TTestBridgeProtocol.TestProtocolErrorKeepsItsCode;
var
  R: TBridgeReply;
begin
  R := MapToolResponse('{"jsonrpc":"2.0","id":5,"error":{"code":-32602,"message":"bad"}}');
  Assert.IsTrue(R.Failed);
  Assert.AreEqual(-32602, R.ErrorCode);
  Assert.AreEqual('bad', R.ErrorText);
  R := MapToolResponse('not json');
  Assert.IsTrue(R.Failed);
  Assert.AreEqual(cRpcInternalError, R.ErrorCode);
end;

end.
