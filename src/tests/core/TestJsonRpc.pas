unit TestJsonRpc;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestJsonRpc = class
  public
    [Test] procedure TestParsesRequestWithIntegerAndStringIds;
    [Test] procedure TestParsesNotificationWithoutId;
    [Test] procedure TestParsesResultResponse;
    [Test] procedure TestParsesErrorResponseWithData;
    [Test] procedure TestNullIdIsAcceptedOnlyInErrorResponses;
    [Test] procedure TestRejectsTextThatIsNotJson;
    [Test] procedure TestRejectsObjectsThatAreNotMessages;
    [Test] procedure TestRejectsBadParamsAndIds;
    [Test] procedure TestBuildersRoundTripThroughTheParser;
    [Test] procedure TestQuoteEscapesSpecialCharacters;
  end;

implementation

uses
  System.SysUtils, uJsonRpc;

function Parse(const AText: string; out AMsg: TRpcMessage): Integer;
begin
  if TryParseRpcMessage(AText, AMsg, Result) then
    Result := 0;
end;

procedure TTestJsonRpc.TestParsesRequestWithIntegerAndStringIds;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":7,"method":"search.files","params":{"mask":"*.pas"}}', Msg));
  Assert.IsTrue(Msg.Kind = rkRequest, 'request');
  Assert.IsTrue(Msg.Id.Kind = ikInteger, 'integer id');
  Assert.AreEqual<Int64>(7, Msg.Id.IntValue);
  Assert.AreEqual('search.files', Msg.Method);
  Assert.AreEqual('{"mask":"*.pas"}', Msg.ParamsJson);
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":"a-1","method":"service.ping"}', Msg));
  Assert.IsTrue(Msg.Id.Kind = ikString, 'string id');
  Assert.AreEqual('a-1', Msg.Id.StrValue);
  Assert.AreEqual('', Msg.ParamsJson, 'params are optional');
end;

procedure TTestJsonRpc.TestParsesNotificationWithoutId;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","method":"notifications/progress","params":[1,2]}', Msg));
  Assert.IsTrue(Msg.Kind = rkNotification, 'notification');
  Assert.IsTrue(Msg.Id.Kind = ikNone, 'no id');
  Assert.AreEqual('[1,2]', Msg.ParamsJson);
end;

procedure TTestJsonRpc.TestParsesResultResponse;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":3,"result":{"isError":false}}', Msg));
  Assert.IsTrue(Msg.Kind = rkResponse, 'response');
  Assert.IsFalse(Msg.IsError, 'not an error');
  Assert.AreEqual('{"isError":false}', Msg.ResultJson);
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":3,"result":null}', Msg));
  Assert.AreEqual('null', Msg.ResultJson, 'a null result is a result');
end;

procedure TTestJsonRpc.TestParsesErrorResponseWithData;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":3,"error":{"code":-32602,"message":"bad","data":{"field":"mask"}}}', Msg));
  Assert.IsTrue(Msg.IsError, 'error');
  Assert.AreEqual(cRpcInvalidParams, Msg.ErrorCode);
  Assert.AreEqual('bad', Msg.ErrorMessage);
  Assert.AreEqual('{"field":"mask"}', Msg.ErrorDataJson);
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":3,"error":{"code":-32001}}', Msg));
  Assert.AreEqual('', Msg.ErrorMessage, 'the message may be absent');
  Assert.AreEqual('', Msg.ErrorDataJson);
end;

procedure TTestJsonRpc.TestNullIdIsAcceptedOnlyInErrorResponses;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse('{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"x"}}', Msg));
  Assert.IsTrue(Msg.Id.Kind = ikNone, 'null id');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":null,"result":{}}', Msg));
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":null,"method":"a.b"}', Msg));
end;

procedure TTestJsonRpc.TestRejectsTextThatIsNotJson;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(cRpcParseError, Parse('', Msg));
  Assert.AreEqual(cRpcParseError, Parse('{"jsonrpc":', Msg));
  Assert.AreEqual(cRpcParseError, Parse('not json', Msg));
end;

procedure TTestJsonRpc.TestRejectsObjectsThatAreNotMessages;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(cRpcInvalidRequest, Parse('[]', Msg), 'batches are not supported');
  Assert.AreEqual(cRpcInvalidRequest, Parse('42', Msg));
  Assert.AreEqual(cRpcInvalidRequest, Parse('{}', Msg));
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"id":1,"method":"a.b"}', Msg), 'no version');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"1.0","id":1,"method":"a.b"}', Msg), 'wrong version');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1}', Msg), 'neither method nor response');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1,"result":1,"error":{"code":1}}', Msg),
    'result and error together');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1,"method":""}', Msg), 'empty method');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","method":"a.b","result":1}', Msg),
    'method with a result');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1,"error":{"message":"x"}}', Msg),
    'error without a code');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","result":1}', Msg), 'response without an id');
end;

procedure TTestJsonRpc.TestRejectsBadParamsAndIds;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1,"method":"a.b","params":5}', Msg),
    'params must be an object or an array');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":1.5,"method":"a.b"}', Msg),
    'a fractional id');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":true,"method":"a.b"}', Msg), 'a boolean id');
  Assert.AreEqual(cRpcInvalidRequest, Parse('{"jsonrpc":"2.0","id":{},"method":"a.b"}', Msg), 'an object id');
end;

procedure TTestJsonRpc.TestBuildersRoundTripThroughTheParser;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse(BuildRpcRequest(RpcIntId(5), 'search.files', '{"mask":"a\"b"}'), Msg));
  Assert.IsTrue(Msg.Kind = rkRequest, 'request');
  Assert.AreEqual<Int64>(5, Msg.Id.IntValue);
  Assert.AreEqual('{"mask":"a\"b"}', Msg.ParamsJson);
  Assert.AreEqual(0, Parse(BuildRpcRequest(RpcStrId('x"y'), 'service.ping', ''), Msg));
  Assert.AreEqual('x"y', Msg.Id.StrValue);
  Assert.AreEqual(0, Parse(BuildRpcNotification('notifications/cancelled', '{"requestId":5}'), Msg));
  Assert.IsTrue(Msg.Kind = rkNotification, 'notification');
  Assert.AreEqual(0, Parse(BuildRpcResult(RpcIntId(5), '{"content":[]}'), Msg));
  Assert.AreEqual('{"content":[]}', Msg.ResultJson);
  Assert.AreEqual(0, Parse(BuildRpcError(RpcIntId(5), cRpcTimeout, 'late', '{"ms":60}'), Msg));
  Assert.AreEqual(cRpcTimeout, Msg.ErrorCode);
  Assert.AreEqual('late', Msg.ErrorMessage);
  Assert.AreEqual('{"ms":60}', Msg.ErrorDataJson);
  Assert.AreEqual(0, Parse(BuildRpcError(Default(TRpcId), cRpcParseError, 'bad'), Msg));
  Assert.IsTrue(Msg.Id.Kind = ikNone, 'an error without a known id');
end;

procedure TTestJsonRpc.TestQuoteEscapesSpecialCharacters;
var
  Msg: TRpcMessage;
begin
  Assert.AreEqual(0, Parse(BuildRpcRequest(RpcIntId(1), 'a.b', '{"p":' + RpcQuote('line'#10'tab'#9'q"\') + '}'), Msg));
  Assert.AreEqual('{"p":' + RpcQuote('line'#10'tab'#9'q"\') + '}', Msg.ParamsJson);
  Assert.IsFalse(Pos(#10, RpcQuote('a'#10'b')) > 0, 'a control character is escaped');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestJsonRpc);

end.
