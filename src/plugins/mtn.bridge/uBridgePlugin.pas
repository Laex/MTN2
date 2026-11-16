unit uBridgePlugin;

{ The glue of mtn.bridge: reads the server list from the plugin settings, registers one
  service per tool of every approved server, and answers service calls by passing them to the
  server process. The registry is used on the main thread only, so services are registered
  while the plugin initialises, from the tool lists cached in the settings; a server without
  a cached list is started once, there, to read it. A server is started for a call when it is
  not running, and given up on after a few failures in a row.

  Settings of the plugin: "servers" (the JSON list), "approvals" (the consent record),
  "tools.<server>" (the cached tool list), "jsonrpc_provider" (the option shared by every
  plugin that offers services). A server whose command line is not approved is never
  started; the settings dialog asks for the approval. }

interface

uses
  uPluginHostAbi;

function RegisterBridge(AHost: PHostApiTable; const APluginId: string): Boolean;

/// <summary>Ends the server processes; call before the library is released.</summary>
procedure StopBridge;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON, System.Generics.Collections,
  uJsonRpc, uPluginServiceProvider, uPluginServiceSettings, uBridgeConfig, uBridgeProtocol,
  uBridgeServer;

const
  cSettingServers = 'servers';
  cSettingApprovals = 'approvals';
  cToolsPrefix = 'tools.';
  cMaxFailures = 3;
  cPriority = 10;
  cWaitSliceMs = 50;

type
  // Shared by the worker and the reply callback, which may run after the worker left.
  IBridgeWait = interface
    function Event: TEvent;
    function Reply: TBridgeReply;
    procedure SetReply(const AReply: TBridgeReply);
  end;

  TBridgeWait = class(TInterfacedObject, IBridgeWait)
  private
    FEvent: TEvent;
    FReply: TBridgeReply;
  public
    constructor Create;
    destructor Destroy; override;
    function Event: TEvent;
    function Reply: TBridgeReply;
    procedure SetReply(const AReply: TBridgeReply);
  end;

  TEntry = class
    Config: TBridgeServerConfig;
    Server: TBridgeServer;
    Lock: TCriticalSection;
    Failures: Integer;
    constructor Create(const AConfig: TBridgeServerConfig);
    destructor Destroy; override;
  end;

  TRoute = record
    Entry: TEntry;
    Tool: string;
  end;

var
  GHost: PHostApiTable;
  GPluginId: string;
  GProvider: TServiceProvider;
  GEntries: TObjectList<TEntry>;
  GRoutes: TDictionary<string, TRoute>;
  GPendingConsent: TList<TBridgeServerConfig>;

constructor TBridgeWait.Create;
begin
  inherited Create;
  FEvent := TEvent.Create(nil, True, False, '');
end;

destructor TBridgeWait.Destroy;
begin
  FEvent.Free;
  inherited;
end;

function TBridgeWait.Event: TEvent;
begin
  Result := FEvent;
end;

function TBridgeWait.Reply: TBridgeReply;
begin
  Result := FReply;
end;

procedure TBridgeWait.SetReply(const AReply: TBridgeReply);
begin
  FReply := AReply;
  FEvent.SetEvent;
end;

constructor TEntry.Create(const AConfig: TBridgeServerConfig);
begin
  inherited Create;
  Config := AConfig;
  Lock := TCriticalSection.Create;
end;

destructor TEntry.Destroy;
begin
  Server.Free;
  Lock.Free;
  inherited;
end;

{ Settings }

function ReadSetting(const AKey: string): string;
var
  Id, Key: UTF8String;
  Buf: TBytes;
  Size, Got: Int64;
begin
  Result := '';
  if (GHost = nil) or not Assigned(GHost.GetSetting) then
    Exit;
  Id := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  Size := 4096;
  repeat
    SetLength(Buf, Size);
    Got := GHost.GetSetting(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(@Buf[0]), Size);
    if Got = -2 then
      Size := Size * 4
    else
      Break;
  until Size > 16 * 1024 * 1024;
  if Got >= 0 then
    Result := TEncoding.UTF8.GetString(Buf, 0, Got);
end;

procedure WriteSetting(const AKey, AValue: string);
var
  Id, Key, Value: UTF8String;
begin
  if (GHost = nil) or not Assigned(GHost.SetSetting) then
    Exit;
  Id := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHost.SetSetting(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Value));
end;

function Translated(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..511] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if (GHost = nil) or not Assigned(GHost.Translate) then
    Exit;
  Id := UTF8String(GPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHost.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

{ Tool cache: the tools of a server as the settings keep them, valid for one consent key. }

function ToolsToJson(const AServer: TBridgeServerConfig; const ATools: TArray<TBridgeTool>): string;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Item: TJSONObject;
  Tool: TBridgeTool;
  Schema: TJSONValue;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('key', BridgeConsentKey(AServer));
    Arr := TJSONArray.Create;
    Root.AddPair('tools', Arr);
    for Tool in ATools do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Tool.Name);
      Item.AddPair('description', Tool.Description);
      if Tool.InputSchemaJson <> '' then
      begin
        Schema := TJSONObject.ParseJSONValue(Tool.InputSchemaJson);
        if Schema <> nil then
          Item.AddPair('inputSchema', Schema);
      end;
      Arr.AddElement(Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function ToolsFromJson(const AServer: TBridgeServerConfig; const AJson: string;
  out ATools: TArray<TBridgeTool>): Boolean;
var
  Root: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item: TJSONValue;
  Tool: TBridgeTool;
  Schema: TJSONValue;
begin
  Result := False;
  SetLength(ATools, 0);
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) or
       (TJSONObject(Root).GetValue<string>('key', '') <> BridgeConsentKey(AServer)) or
       not (TJSONObject(Root).GetValue('tools') is TJSONArray) then
      Exit;
    Arr := TJSONObject(Root).GetValue('tools') as TJSONArray;
    for I := 0 to Arr.Count - 1 do
    begin
      Item := Arr.Items[I];
      if not (Item is TJSONObject) then
        Continue;
      Tool.Name := TJSONObject(Item).GetValue<string>('name', '');
      if (Tool.Name = '') or not BridgeToolAllowed(AServer, Tool.Name) then
        Continue;
      Tool.Description := TJSONObject(Item).GetValue<string>('description', '');
      Schema := TJSONObject(Item).GetValue('inputSchema');
      if Schema <> nil then
        Tool.InputSchemaJson := Schema.ToJSON
      else
        Tool.InputSchemaJson := '';
      SetLength(ATools, Length(ATools) + 1);
      ATools[High(ATools)] := Tool;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

{ Service descriptions and calls }

function DescribeJson(const AServiceName: string; const ATool: TBridgeTool): string;
var
  Obj: TJSONObject;
  Caps: TJSONArray;
  Schema: TJSONValue;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('protocolVersion', TJSONNumber.Create(1));
    Obj.AddPair('name', AServiceName);
    Obj.AddPair('version', TJSONNumber.Create(1));
    Obj.AddPair('title', ATool.Name);
    Obj.AddPair('description', ATool.Description);
    if ATool.InputSchemaJson <> '' then
    begin
      Schema := TJSONObject.ParseJSONValue(ATool.InputSchemaJson);
      if Schema <> nil then
        Obj.AddPair('inputSchema', Schema);
    end;
    Caps := TJSONArray.Create;
    Caps.Add('tool');
    Obj.AddPair('capabilities', Caps);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// Makes the server run; False with the reason when it cannot.
function EnsureRunning(AEntry: TEntry; out AError: string): Boolean;
begin
  AError := '';
  AEntry.Lock.Enter;
  try
    if (AEntry.Server <> nil) and AEntry.Server.Running then
      Exit(True);
    if AEntry.Failures >= cMaxFailures then
    begin
      AError := 'the service process keeps failing';
      Exit(False);
    end;
    if AEntry.Server = nil then
    begin
      AEntry.Server := TBridgeServer.Create(AEntry.Config, RealBridgeChildFactory());
      AEntry.Server.OnLog := procedure(const ALine: string)
        begin
          // The process writes its diagnostics to stderr; they are not shown anywhere yet.
        end;
    end;
    Result := AEntry.Server.Start(AError);
    if Result then
      AEntry.Failures := 0
    else
      Inc(AEntry.Failures);
  finally
    AEntry.Lock.Leave;
  end;
end;

procedure Answer(AJob: TServiceJob; const ARequestJson: string);
var
  Msg: TRpcMessage;
  Code, CallId: Integer;
  Route: TRoute;
  Err: string;
  Wait: IBridgeWait;
  Got: TBridgeReply;
begin
  if not TryParseRpcMessage(ARequestJson, Msg, Code) or (Msg.Kind <> rkRequest) then
  begin
    AJob.ReplyError(cRpcInvalidParams, 'bad request');
    Exit;
  end;
  if not GRoutes.TryGetValue(Msg.Method, Route) then
  begin
    AJob.ReplyError(cRpcMethodNotFound, 'unknown service');
    Exit;
  end;
  if not EnsureRunning(Route.Entry, Err) then
  begin
    AJob.ReplyError(cRpcNotSupported, Err);
    Exit;
  end;
  Wait := TBridgeWait.Create;
  if not Route.Entry.Server.Call(Route.Tool, Msg.ParamsJson, 0,
    procedure(const AReply: TBridgeReply)
    begin
      Wait.SetReply(AReply);
    end,
    procedure(const AText: string)
    begin
      AJob.Progress(AText);
    end, CallId) then
  begin
    AJob.ReplyError(cRpcInternalError, 'the service process is busy or not running');
    Exit;
  end;
  while Wait.Event.WaitFor(cWaitSliceMs) = wrTimeout do
    if AJob.IsCancelled then
    begin
      Route.Entry.Server.Cancel(CallId);
      Exit;
    end;
  Got := Wait.Reply;
  if Got.Failed then
    AJob.ReplyError(Got.ErrorCode, Got.ErrorText)
  else
    AJob.ReplyResult(Got.ResultJson);
end;

procedure AddRoutes(AEntry: TEntry; const ATools: TArray<TBridgeTool>);
var
  Tool: TBridgeTool;
  Name: string;
  Route: TRoute;
begin
  for Tool in ATools do
  begin
    Name := BridgeServiceName(AEntry.Config.Name, Tool.Name);
    if (Name = '') or GRoutes.ContainsKey(Name) then
      Continue;
    if GProvider.Register(GPluginId, Name, DescribeJson(Name, Tool), cPriority) then
    begin
      Route.Entry := AEntry;
      Route.Tool := Tool.Name;
      GRoutes.Add(Name, Route);
    end;
  end;
end;

procedure RegisterEntry(AEntry: TEntry);
var
  Tools: TArray<TBridgeTool>;
  Err: string;
begin
  if ToolsFromJson(AEntry.Config, ReadSetting(cToolsPrefix + AEntry.Config.Name), Tools) then
  begin
    AddRoutes(AEntry, Tools);
    Exit;
  end;
  // No list yet: start the server once to read it, and keep what it offers.
  if EnsureRunning(AEntry, Err) then
  begin
    WriteSetting(cToolsPrefix + AEntry.Config.Name, ToolsToJson(AEntry.Config, AEntry.Server.Tools));
    AddRoutes(AEntry, AEntry.Server.Tools);
  end;
end;

{ Settings dialogs }

function Ctl(const AType, AId, AText: string; ACol, ARow, AWidth: Integer;
  ADefault, ACancel: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  if AId <> '' then
    Result.AddPair('id', AId);
  if AText <> '' then
    Result.AddPair('text', AText);
  if ADefault then
    Result.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    Result.AddPair('cancel', TJSONBool.Create(True));
  Result.AddPair('col', TJSONNumber.Create(ACol));
  Result.AddPair('row', TJSONNumber.Create(ARow));
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(1));
end;

function DialogHead(const ATitle: string; AWidth, AHeight: Integer; out AKids: TJSONArray): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'dialog');
  Result.AddPair('version', '2.0');
  Result.AddPair('title', ATitle);
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(AHeight));
  AKids := TJSONArray.Create;
  Result.AddPair('children', AKids);
end;

procedure ShowJson(const AJson: string; AOnAnswer: THostDialogCommandCallback; AData: Pointer);
var
  Id, Json: UTF8String;
begin
  if not Assigned(GHost.ShowDialog) then
    Exit;
  Id := UTF8String(GPluginId);
  Json := UTF8String(AJson);
  GHost.ShowDialog(PAnsiChar(Id), PAnsiChar(Json), AOnAnswer, AData);
end;

procedure OnMessageAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
end;

procedure ShowMessage(const AText: string);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  Decl := DialogHead(Translated('bridge.title', 'Service bridge'), 80, 7, Kids);
  try
    Kids.AddElement(Ctl('label', '', Copy(AText, 1, 76), 2, 1, 76, False, False));
    Kids.AddElement(Ctl('button', 'ok', Translated('bridge.ok', 'OK'), 34, 4, 12, True, True));
    ShowJson(Decl.ToJSON, OnMessageAnswer, nil);
  finally
    Decl.Free;
  end;
end;

procedure NextConsent; forward;

procedure OnConsentAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
begin
  try
    if (GPendingConsent <> nil) and (GPendingConsent.Count > 0) then
    begin
      if SameText(string(AControlId), 'ok') then
        WriteSetting(cSettingApprovals,
          BridgeWithApproval(ReadSetting(cSettingApprovals), GPendingConsent[0]));
      GPendingConsent.Delete(0);
    end;
    NextConsent;
  except
    // Never let an exception cross into the host.
  end;
end;

// Asks about the first server of the queue: the whole command line is shown.
procedure NextConsent;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Lines: TArray<string>;
  Row, I: Integer;
  Server: TBridgeServerConfig;
begin
  if (GPendingConsent = nil) or (GPendingConsent.Count = 0) then
    Exit;
  Server := GPendingConsent[0];
  Lines := BridgeCommandText(Server).Split([sLineBreak, #10]);
  Decl := DialogHead(Translated('bridge.consent.title', 'Run this program?'), 76, 9 + Length(Lines), Kids);
  try
    Kids.AddElement(Ctl('label', '', Translated('bridge.consent.text',
      'The plugin is about to start this program for server "') + Server.Name + '":',
      2, 1, 72, False, False));
    Row := 3;
    for I := 0 to High(Lines) do
    begin
      Kids.AddElement(Ctl('label', '', Copy(Lines[I], 1, 72), 4, Row, 70, False, False));
      Inc(Row);
    end;
    Kids.AddElement(Ctl('button', 'ok', Translated('bridge.consent.allow', 'Allow'), 22, Row + 1, 14, False, False));
    Kids.AddElement(Ctl('button', 'cancel', Translated('bridge.consent.deny', 'Do not allow'), 38, Row + 1, 16, True, True));
    ShowJson(Decl.ToJSON, OnConsentAnswer, nil);
  finally
    Decl.Free;
  end;
end;

procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  Json, Err, Approvals: string;
  Servers: TArray<TBridgeServerConfig>;
  S: TBridgeServerConfig;
  Id, Key, Value: UTF8String;
  Enabled: Boolean;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      Json := TJSONObject(Root).GetValue<string>(cSettingServers, '');
      Enabled := TJSONObject(Root).GetValue<Boolean>(cSettingProvider, True);
    finally
      Root.Free;
    end;
    if not ParseBridgeServers(Json, Servers, Err) then
    begin
      // The list stays as it was.
      ShowMessage(Err);
      Exit;
    end;
    WriteSetting(cSettingServers, Json);
    if Enabled then
      WriteSetting(cSettingProvider, '1')
    else
      WriteSetting(cSettingProvider, '0');
    // Another command line means another tool list: it is read at the next start.
    for S in Servers do
      WriteSetting(cToolsPrefix + S.Name, '');
    Approvals := ReadSetting(cSettingApprovals);
    if GPendingConsent = nil then
      GPendingConsent := TList<TBridgeServerConfig>.Create;
    GPendingConsent.Clear;
    for S in Servers do
      if not BridgeIsApproved(Approvals, S) then
        GPendingConsent.Add(S);
    NextConsent;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Input: TJSONObject;
  Check: TJSONObject;
  Err: string;
  Servers: TArray<TBridgeServerConfig>;
begin
  try
    Decl := DialogHead(Translated('bridge.title', 'Service bridge'), 80, 14, Kids);
    try
      Kids.AddElement(Ctl('label', '', Translated('bridge.servers',
        'Servers (a JSON list, see the documentation):'), 2, 1, 76, False, False));
      Input := Ctl('input', cSettingServers, '', 2, 2, 76, False, False);
      Input.AddPair('value', ReadSetting(cSettingServers));
      Kids.AddElement(Input);
      if not ParseBridgeServers(ReadSetting(cSettingServers), Servers, Err) then
        Kids.AddElement(Ctl('label', '', Copy(Err, 1, 76), 2, 4, 76, False, False));
      Check := Ctl('checkbox', cSettingProvider, Translated('bridge.provider',
        'Offer the servers as providers of JSON-RPC services (needs a restart)'), 2, 6, 76, False, False);
      Check.AddPair('checked', TJSONBool.Create(ServiceProviderEnabled(GHost, GPluginId)));
      Kids.AddElement(Check);
      Kids.AddElement(Ctl('button', 'ok', Translated('bridge.ok', 'OK'), 26, 9, 12, True, False));
      Kids.AddElement(Ctl('button', 'cancel', Translated('bridge.cancel', 'Cancel'), 42, 9, 12, False, True));
      ShowJson(Decl.ToJSON, OnSettingsAnswer, nil);
    finally
      Decl.Free;
    end;
  except
    // Never let an exception cross into the host.
  end;
end;

{ Entry points }

function RegisterBridge(AHost: PHostApiTable; const APluginId: string): Boolean;
var
  Servers: TArray<TBridgeServerConfig>;
  Err, Approvals: string;
  S: TBridgeServerConfig;
  Entry: TEntry;
  Id: UTF8String;
begin
  Result := False;
  GHost := AHost;
  GPluginId := APluginId;
  if (AHost = nil) or not Assigned(AHost.RegisterSettings) then
    Exit;
  Id := UTF8String(APluginId);
  AHost.RegisterSettings(PAnsiChar(Id), @OnConfigure, nil);
  Result := True;
  // With the provider option cleared the plugin loads and offers nothing.
  if not ServiceProviderEnabled(AHost, APluginId) then
    Exit;
  if not ParseBridgeServers(ReadSetting(cSettingServers), Servers, Err) then
    Exit;
  FreeAndNil(GProvider);
  GProvider := TServiceProvider.Create(AHost, Answer);
  GEntries := TObjectList<TEntry>.Create(True);
  GRoutes := TDictionary<string, TRoute>.Create;
  Approvals := ReadSetting(cSettingApprovals);
  for S in Servers do
  begin
    // Only a server whose exact command line the user approved is ever started.
    if not BridgeIsApproved(Approvals, S) then
      Continue;
    Entry := TEntry.Create(S);
    GEntries.Add(Entry);
    RegisterEntry(Entry);
  end;
end;

procedure StopBridge;
var
  Entry: TEntry;
begin
  if GEntries <> nil then
    for Entry in GEntries do
      if Entry.Server <> nil then
        Entry.Server.Stop;
  FreeAndNil(GProvider);
  FreeAndNil(GRoutes);
  FreeAndNil(GEntries);
  FreeAndNil(GPendingConsent);
end;

end.
