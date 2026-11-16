unit uBridgeProtocol;

{ The pure part of mtn.bridge: the messages exchanged with an external service process
  over stdio (one JSON message per line), and their translation to and from the services
  of the host (docs/PLUGIN_SERVICES.md). No process, thread or host call lives here. }

interface

uses
  System.SysUtils, uJsonRpc;

const
  cBridgeProtocolVersion = '2025-03-26';
  cBridgeMaxLine = 4 * 1024 * 1024;
  cBridgeServicePrefix = 'bridge.';

type
  /// <summary>Cuts a byte stream into lines. A line longer than the limit is dropped as a
  /// whole, and the splitter reports it once so the caller can log it.</summary>
  TLineSplitter = class
  private
    FPending: TBytes;
    FMax: Integer;
    FSkipping: Boolean;
    FOverflowed: Boolean;
  public
    constructor Create(AMaxLine: Integer = cBridgeMaxLine);
    /// <summary>Adds bytes; the complete lines (UTF-8, without the line break) are returned.</summary>
    function Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
    /// <summary>True once after a line was dropped for its length.</summary>
    function TakeOverflow: Boolean;
  end;

  TBridgeTool = record
    Name: string;
    Description: string;
    /// <summary>The input schema as JSON; '' when the server gave none.</summary>
    InputSchemaJson: string;
  end;

function BuildInitializeRequest(AId: Integer): string;
function BuildInitializedNotification: string;

/// <summary>False when the server answered with an error or with a protocol version the
/// bridge does not speak.</summary>
function ParseInitializeResult(const AMessageJson: string; out AVersion: string): Boolean;

function BuildToolsListRequest(AId: Integer; const ACursor: string): string;

/// <summary>The tools of one page and the cursor of the next ('' for the last page).</summary>
function ParseToolsList(const AMessageJson: string; out ATools: TArray<TBridgeTool>;
  out ANextCursor: string): Boolean;

/// <summary>"bridge.&lt;server&gt;.&lt;tool&gt;" with every character outside a-z, 0-9, "_" and "-"
/// in the two names replaced by "_"; '' when a name is empty.</summary>
function BridgeServiceName(const AServer, ATool: string): string;

/// <summary>The call asks for progress notifications tagged with the request id.</summary>
function BuildToolCallRequest(AId: Integer; const ATool, AArgumentsJson: string): string;

/// <summary>The request id and the text of a progress notification; False for any other message.</summary>
function ParseProgressNotification(const AMessageJson: string; out AToken: Integer;
  out AText: string): Boolean;

function BuildCancelNotification(AId: Integer; const AReason: string): string;

type
  TBridgeReply = record
    Failed: Boolean;
    /// <summary>The result of the service when not failed.</summary>
    ResultJson: string;
    ErrorCode: Integer;
    ErrorText: string;
  end;

/// <summary>Turns the response to a tool call into the reply of the service: a result
/// passes through, an error result of the tool (isError) becomes error -32603 with its text.</summary>
function MapToolResponse(const AMessageJson: string): TBridgeReply;

implementation

uses
  System.JSON;

constructor TLineSplitter.Create(AMaxLine: Integer);
begin
  inherited Create;
  FMax := AMaxLine;
end;

function TLineSplitter.Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
var
  I, Start: Integer;
  Line: TBytes;

  procedure Emit;
  var
    Text: string;
  begin
    if (Length(Line) > 0) and (Line[High(Line)] = 13) then
      SetLength(Line, Length(Line) - 1);
    if Length(Line) = 0 then
      Exit;
    Text := TEncoding.UTF8.GetString(Line);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Text;
  end;

begin
  SetLength(Result, 0);
  Start := 0;
  for I := 0 to ACount - 1 do
    if ABytes[I] = 10 then
    begin
      if FSkipping then
        FSkipping := False
      else
      begin
        Line := FPending;
        SetLength(Line, Length(Line) + I - Start);
        if I > Start then
          Move(ABytes[Start], Line[Length(FPending)], I - Start);
        if Length(Line) > FMax then
          FOverflowed := True
        else
          Emit;
      end;
      SetLength(FPending, 0);
      Start := I + 1;
    end;
  if Start < ACount then
    if not FSkipping then
    begin
      if Length(FPending) + ACount - Start > FMax then
      begin
        FSkipping := True;
        FOverflowed := True;
        SetLength(FPending, 0);
      end
      else
      begin
        SetLength(FPending, Length(FPending) + ACount - Start);
        Move(ABytes[Start], FPending[Length(FPending) - (ACount - Start)], ACount - Start);
      end;
    end;
end;

function TLineSplitter.TakeOverflow: Boolean;
begin
  Result := FOverflowed;
  FOverflowed := False;
end;

function BuildInitializeRequest(AId: Integer): string;
begin
  Result := BuildRpcRequest(RpcIntId(AId), 'initialize',
    '{"protocolVersion":"' + cBridgeProtocolVersion + '","capabilities":{},' +
    '"clientInfo":{"name":"mtn2","version":"1"}}');
end;

function BuildInitializedNotification: string;
begin
  Result := BuildRpcNotification('notifications/initialized', '');
end;

function ParseInitializeResult(const AMessageJson: string; out AVersion: string): Boolean;
var
  Msg: TRpcMessage;
  Code: Integer;
  Root: TJSONValue;
begin
  Result := False;
  AVersion := '';
  if not TryParseRpcMessage(AMessageJson, Msg, Code) or (Msg.Kind <> rkResponse) or Msg.IsError then
    Exit;
  Root := TJSONObject.ParseJSONValue(Msg.ResultJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    AVersion := TJSONObject(Root).GetValue<string>('protocolVersion', '');
    // The server answers with the version it speaks; the bridge accepts the dated
    // versions it knows of, which share the message shapes it uses.
    Result := (AVersion = cBridgeProtocolVersion) or (AVersion = '2024-11-05');
  finally
    Root.Free;
  end;
end;

function BuildToolsListRequest(AId: Integer; const ACursor: string): string;
begin
  if ACursor = '' then
    Result := BuildRpcRequest(RpcIntId(AId), 'tools/list', '{}')
  else
    Result := BuildRpcRequest(RpcIntId(AId), 'tools/list', '{"cursor":' + RpcQuote(ACursor) + '}');
end;

function ParseToolsList(const AMessageJson: string; out ATools: TArray<TBridgeTool>;
  out ANextCursor: string): Boolean;
var
  Msg: TRpcMessage;
  Code, I: Integer;
  Root: TJSONValue;
  List: TJSONArray;
  Item: TJSONValue;
  Tool: TBridgeTool;
  Schema: TJSONValue;
begin
  Result := False;
  SetLength(ATools, 0);
  ANextCursor := '';
  if not TryParseRpcMessage(AMessageJson, Msg, Code) or (Msg.Kind <> rkResponse) or Msg.IsError then
    Exit;
  Root := TJSONObject.ParseJSONValue(Msg.ResultJson);
  try
    if not (Root is TJSONObject) or not (TJSONObject(Root).GetValue('tools') is TJSONArray) then
      Exit;
    List := TJSONObject(Root).GetValue('tools') as TJSONArray;
    for I := 0 to List.Count - 1 do
    begin
      Item := List.Items[I];
      if not (Item is TJSONObject) then
        Continue;
      Tool.Name := TJSONObject(Item).GetValue<string>('name', '');
      if Tool.Name = '' then
        Continue;
      Tool.Description := TJSONObject(Item).GetValue<string>('description', '');
      Schema := TJSONObject(Item).GetValue('inputSchema');
      if Schema is TJSONObject then
        Tool.InputSchemaJson := Schema.ToJSON
      else
        Tool.InputSchemaJson := '';
      SetLength(ATools, Length(ATools) + 1);
      ATools[High(ATools)] := Tool;
    end;
    ANextCursor := TJSONObject(Root).GetValue<string>('nextCursor', '');
    Result := True;
  finally
    Root.Free;
  end;
end;

function SafeName(const AText: string): string;
var
  C: Char;
begin
  Result := '';
  for C in LowerCase(AText) do
    if CharInSet(C, ['a'..'z', '0'..'9', '_', '-']) then
      Result := Result + C
    else
      Result := Result + '_';
end;

function BridgeServiceName(const AServer, ATool: string): string;
begin
  if (Trim(AServer) = '') or (Trim(ATool) = '') then
    Exit('');
  Result := cBridgeServicePrefix + SafeName(Trim(AServer)) + '.' + SafeName(Trim(ATool));
end;

function BuildToolCallRequest(AId: Integer; const ATool, AArgumentsJson: string): string;
var
  Args: string;
begin
  Args := AArgumentsJson;
  if Args = '' then
    Args := '{}';
  Result := BuildRpcRequest(RpcIntId(AId), 'tools/call',
    '{"name":' + RpcQuote(ATool) + ',"arguments":' + Args +
    ',"_meta":{"progressToken":' + IntToStr(AId) + '}}');
end;

function ParseProgressNotification(const AMessageJson: string; out AToken: Integer;
  out AText: string): Boolean;
var
  Msg: TRpcMessage;
  Code: Integer;
  Root: TJSONValue;
  Tok: TJSONValue;
begin
  Result := False;
  AToken := 0;
  AText := '';
  if not TryParseRpcMessage(AMessageJson, Msg, Code) or (Msg.Kind <> rkNotification) or
     (Msg.Method <> 'notifications/progress') then
    Exit;
  Root := TJSONObject.ParseJSONValue(Msg.ParamsJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Tok := TJSONObject(Root).GetValue('progressToken');
    if not (Tok is TJSONNumber) then
      Exit;
    AToken := TJSONNumber(Tok).AsInt;
    AText := TJSONObject(Root).GetValue<string>('message', '');
    Result := True;
  finally
    Root.Free;
  end;
end;

function BuildCancelNotification(AId: Integer; const AReason: string): string;
begin
  Result := BuildRpcNotification('notifications/cancelled',
    '{"requestId":' + IntToStr(AId) + ',"reason":' + RpcQuote(AReason) + '}');
end;

function ToolErrorText(AResult: TJSONObject): string;
var
  Content: TJSONValue;
  I: Integer;
  Item: TJSONValue;
begin
  Result := '';
  Content := AResult.GetValue('content');
  if Content is TJSONArray then
    for I := 0 to TJSONArray(Content).Count - 1 do
    begin
      Item := TJSONArray(Content).Items[I];
      if (Item is TJSONObject) and (TJSONObject(Item).GetValue<string>('type', '') = 'text') then
      begin
        if Result <> '' then
          Result := Result + #10;
        Result := Result + TJSONObject(Item).GetValue<string>('text', '');
      end;
    end;
  if Result = '' then
    Result := 'the tool failed';
end;

function MapToolResponse(const AMessageJson: string): TBridgeReply;
var
  Msg: TRpcMessage;
  Code: Integer;
  Root: TJSONValue;
begin
  Result := Default(TBridgeReply);
  if not TryParseRpcMessage(AMessageJson, Msg, Code) or (Msg.Kind <> rkResponse) then
  begin
    Result.Failed := True;
    Result.ErrorCode := cRpcInternalError;
    Result.ErrorText := 'bad answer of the service process';
    Exit;
  end;
  if Msg.IsError then
  begin
    Result.Failed := True;
    Result.ErrorCode := Msg.ErrorCode;
    Result.ErrorText := Msg.ErrorMessage;
    Exit;
  end;
  Root := TJSONObject.ParseJSONValue(Msg.ResultJson);
  try
    if (Root is TJSONObject) and TJSONObject(Root).GetValue<Boolean>('isError', False) then
    begin
      Result.Failed := True;
      Result.ErrorCode := cRpcInternalError;
      Result.ErrorText := ToolErrorText(TJSONObject(Root));
      Exit;
    end;
  finally
    Root.Free;
  end;
  Result.ResultJson := Msg.ResultJson;
end;

end.
