unit uJsonRpc;

{ JSON-RPC 2.0 messages of the plugin services (docs/PLUGIN_SERVICES.md):
  one function parses a message into a record, the Build* functions make
  requests, notifications, results and errors. Pure functions, no state.

  A message the services accept is one object with "jsonrpc": "2.0". A request
  has a method and an id (an integer or a string), a notification has a method
  and no id, a response has an id and exactly one of result / error. A null id
  is accepted only in an error response. Batches are not supported. }

interface

const
  cRpcParseError = -32700;
  cRpcInvalidRequest = -32600;
  cRpcMethodNotFound = -32601;
  cRpcInvalidParams = -32602;
  cRpcInternalError = -32603;
  /// <summary>The call was cancelled.</summary>
  cRpcCancelled = -32001;
  /// <summary>The provider cannot serve this request; the caller falls back.</summary>
  cRpcNotSupported = -32002;
  /// <summary>Not allowed: a reserved name, a refused permission.</summary>
  cRpcNotAllowed = -32003;
  /// <summary>Too many open calls for the service.</summary>
  cRpcTooManyCalls = -32004;
  /// <summary>The provider did not answer within the time limit.</summary>
  cRpcTimeout = -32005;

type
  TRpcIdKind = (ikNone, ikInteger, ikString);

  TRpcId = record
    Kind: TRpcIdKind;
    IntValue: Int64;
    StrValue: string;
    /// <summary>The id as JSON text; "null" for ikNone.</summary>
    function ToJson: string;
    function SameAs(const AOther: TRpcId): Boolean;
  end;

  TRpcKind = (rkRequest, rkNotification, rkResponse);

  TRpcMessage = record
    Kind: TRpcKind;
    /// <summary>Request and response; ikNone for a notification.</summary>
    Id: TRpcId;
    Method: string;
    /// <summary>The params object or array as JSON; '' when absent.</summary>
    ParamsJson: string;
    /// <summary>The result of a successful response as JSON.</summary>
    ResultJson: string;
    IsError: Boolean;
    ErrorCode: Integer;
    ErrorMessage: string;
    /// <summary>The error data as JSON; '' when absent.</summary>
    ErrorDataJson: string;
  end;

function RpcIntId(AValue: Int64): TRpcId;
function RpcStrId(const AValue: string): TRpcId;

/// <summary>Parses one message. False with AErrorCode set to cRpcParseError
/// (not JSON) or cRpcInvalidRequest (JSON, but not a valid message).</summary>
function TryParseRpcMessage(const AText: string; out AMsg: TRpcMessage;
  out AErrorCode: Integer): Boolean;

/// <summary>AParamsJson is an object or an array as JSON text; '' omits it.</summary>
function BuildRpcRequest(const AId: TRpcId; const AMethod, AParamsJson: string): string;
function BuildRpcNotification(const AMethod, AParamsJson: string): string;
function BuildRpcResult(const AId: TRpcId; const AResultJson: string): string;
/// <summary>ADataJson is any JSON value as text; '' omits it.</summary>
function BuildRpcError(const AId: TRpcId; ACode: Integer; const AMessage: string;
  const ADataJson: string = ''): string;

/// <summary>The JSON string literal of AText, quoted and escaped.</summary>
function RpcQuote(const AText: string): string;

implementation

uses
  System.SysUtils, System.JSON;

function TRpcId.ToJson: string;
begin
  case Kind of
    ikInteger: Result := IntToStr(IntValue);
    ikString: Result := RpcQuote(StrValue);
  else
    Result := 'null';
  end;
end;

function TRpcId.SameAs(const AOther: TRpcId): Boolean;
begin
  if Kind <> AOther.Kind then
    Exit(False);
  case Kind of
    ikInteger: Result := IntValue = AOther.IntValue;
    ikString: Result := StrValue = AOther.StrValue;
  else
    Result := True;
  end;
end;

function RpcIntId(AValue: Int64): TRpcId;
begin
  Result.Kind := ikInteger;
  Result.IntValue := AValue;
  Result.StrValue := '';
end;

function RpcStrId(const AValue: string): TRpcId;
begin
  Result.Kind := ikString;
  Result.IntValue := 0;
  Result.StrValue := AValue;
end;

function RpcQuote(const AText: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AText);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

function IsIntegerNumber(AValue: TJSONValue; out AInt: Int64): Boolean;
begin
  Result := (AValue is TJSONNumber) and TryStrToInt64(TJSONNumber(AValue).Value, AInt);
end;

function TryReadId(AValue: TJSONValue; out AId: TRpcId): Boolean;
var
  Int: Int64;
begin
  AId := Default(TRpcId);
  if AValue is TJSONString then
  begin
    AId := RpcStrId(TJSONString(AValue).Value);
    Exit(True);
  end;
  Result := IsIntegerNumber(AValue, Int);
  if Result then
    AId := RpcIntId(Int);
end;

function TryReadError(AValue: TJSONValue; var AMsg: TRpcMessage): Boolean;
var
  Obj: TJSONObject;
  Code: Int64;
  Data: TJSONValue;
begin
  Result := False;
  if not (AValue is TJSONObject) then
    Exit;
  Obj := TJSONObject(AValue);
  if not IsIntegerNumber(Obj.GetValue('code'), Code) then
    Exit;
  if (Code < Low(Integer)) or (Code > High(Integer)) then
    Exit;
  if (Obj.GetValue('message') <> nil) and not (Obj.GetValue('message') is TJSONString) then
    Exit;
  AMsg.IsError := True;
  AMsg.ErrorCode := Integer(Code);
  if Obj.GetValue('message') <> nil then
    AMsg.ErrorMessage := TJSONString(Obj.GetValue('message')).Value;
  Data := Obj.GetValue('data');
  if Data <> nil then
    AMsg.ErrorDataJson := Data.ToJSON;
  Result := True;
end;

function TryParseRpcMessage(const AText: string; out AMsg: TRpcMessage;
  out AErrorCode: Integer): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Version, MethodValue, ParamsValue, IdValue, ResultValue, ErrorValue: TJSONValue;
begin
  AMsg := Default(TRpcMessage);
  AErrorCode := cRpcParseError;
  Result := False;
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(AText, True, False);
    except
      Root := nil;
    end;
    if Root = nil then
      Exit;
    AErrorCode := cRpcInvalidRequest;
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    Version := Obj.GetValue('jsonrpc');
    if not ((Version is TJSONString) and (TJSONString(Version).Value = '2.0')) then
      Exit;
    MethodValue := Obj.GetValue('method');
    IdValue := Obj.GetValue('id');
    if MethodValue <> nil then
    begin
      if not ((MethodValue is TJSONString) and (TJSONString(MethodValue).Value <> '')) then
        Exit;
      if (Obj.GetValue('result') <> nil) or (Obj.GetValue('error') <> nil) then
        Exit;
      AMsg.Method := TJSONString(MethodValue).Value;
      ParamsValue := Obj.GetValue('params');
      if ParamsValue <> nil then
      begin
        if not ((ParamsValue is TJSONObject) or (ParamsValue is TJSONArray)) then
          Exit;
        AMsg.ParamsJson := ParamsValue.ToJSON;
      end;
      if IdValue = nil then
        AMsg.Kind := rkNotification
      else
      begin
        if not TryReadId(IdValue, AMsg.Id) then
          Exit;
        AMsg.Kind := rkRequest;
      end;
      Exit(True);
    end;
    ResultValue := Obj.GetValue('result');
    ErrorValue := Obj.GetValue('error');
    if (ResultValue = nil) = (ErrorValue = nil) then
      Exit;
    if IdValue = nil then
      Exit;
    AMsg.Kind := rkResponse;
    if ErrorValue <> nil then
    begin
      if not (IdValue is TJSONNull) and not TryReadId(IdValue, AMsg.Id) then
        Exit;
      if not TryReadError(ErrorValue, AMsg) then
        Exit;
    end
    else
    begin
      if not TryReadId(IdValue, AMsg.Id) then
        Exit;
      AMsg.ResultJson := ResultValue.ToJSON;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function WithParams(const AHead, AParamsJson: string): string;
begin
  if AParamsJson = '' then
    Result := AHead + '}'
  else
    Result := AHead + ',"params":' + AParamsJson + '}';
end;

function BuildRpcRequest(const AId: TRpcId; const AMethod, AParamsJson: string): string;
begin
  Result := WithParams('{"jsonrpc":"2.0","id":' + AId.ToJson + ',"method":' + RpcQuote(AMethod),
    AParamsJson);
end;

function BuildRpcNotification(const AMethod, AParamsJson: string): string;
begin
  Result := WithParams('{"jsonrpc":"2.0","method":' + RpcQuote(AMethod), AParamsJson);
end;

function BuildRpcResult(const AId: TRpcId; const AResultJson: string): string;
begin
  Result := '{"jsonrpc":"2.0","id":' + AId.ToJson + ',"result":' + AResultJson + '}';
end;

function BuildRpcError(const AId: TRpcId; ACode: Integer; const AMessage: string;
  const ADataJson: string): string;
begin
  Result := '{"jsonrpc":"2.0","id":' + AId.ToJson + ',"error":{"code":' + IntToStr(ACode) +
    ',"message":' + RpcQuote(AMessage);
  if ADataJson <> '' then
    Result := Result + ',"data":' + ADataJson;
  Result := Result + '}}';
end;

end.
