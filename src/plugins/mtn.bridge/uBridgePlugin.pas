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

{ Consent: the whole command line or address is shown before anything runs or is contacted. }

const
  cConsentWrap = 70;

// Cuts every line to pieces of at most AWidth characters, so a long address is shown whole.
function WrapLines(const ALines: TArray<string>; AWidth: Integer): TArray<string>;
var
  Line: string;
  P: Integer;
begin
  SetLength(Result, 0);
  for Line in ALines do
  begin
    P := 1;
    repeat
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(Line, P, AWidth);
      Inc(P, AWidth);
    until P > Length(Line);
  end;
end;

procedure ShowConsent(const AServer: TBridgeServerConfig; AOnAnswer: THostDialogCommandCallback);
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Lines: TArray<string>;
  Row, I: Integer;
  Title, Text: string;
begin
  Lines := WrapLines(BridgeCommandText(AServer).Split([sLineBreak, #10]), cConsentWrap);
  if AServer.Transport = btHttp then
  begin
    Title := Translated('bridge.consent.titleHttp', 'Contact this address?');
    Text := Translated('bridge.consent.textHttp',
      'The plugin is about to send requests to this address for server "');
  end
  else
  begin
    Title := Translated('bridge.consent.title', 'Run this program?');
    Text := Translated('bridge.consent.text',
      'The plugin is about to start this program for server "');
  end;
  Decl := DialogHead(Title, 76, 9 + Length(Lines), Kids);
  try
    Kids.AddElement(Ctl('label', '', Text + AServer.Name + '":', 2, 1, 72, False, False));
    Row := 3;
    for I := 0 to High(Lines) do
    begin
      Kids.AddElement(Ctl('label', '', Lines[I], 4, Row, 70, False, False));
      Inc(Row);
    end;
    Kids.AddElement(Ctl('button', 'ok', Translated('bridge.consent.allow', 'Allow'), 22, Row + 1, 14, False, False));
    Kids.AddElement(Ctl('button', 'cancel', Translated('bridge.consent.deny', 'Do not allow'), 38, Row + 1, 16, True, True));
    ShowJson(Decl.ToJSON, AOnAnswer, nil);
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

// Asks about the first server of the queue.
procedure NextConsent;
begin
  if (GPendingConsent = nil) or (GPendingConsent.Count = 0) then
    Exit;
  ShowConsent(GPendingConsent[0], OnConsentAnswer);
end;

{ The server list: one row per server with its number, name, transport, target and state. The
  list is edited as a draft; OK writes it to the settings, Cancel drops it. Every command
  closes the dialog, so the dialog is shown again, from the main thread's queue, with the
  draft changed. }

const
  cListWidth = 95;
  cListRows = 8;
  cColNo = 2;
  cColName = 14;
  cColType = 5;
  cColTarget = 46;
  cColState = 23;
  cStatusWidth = 96;

var
  GDraft: TList<TBridgeServerConfig>;
  GDraftProvider: Boolean;
  GSel: Integer;
  GStatus: string;
  // The outcome of the last check, by "name|consent key": a changed server is unchecked again.
  GChecks: TDictionary<string, string>;
  GEdit: TBridgeServerConfig;
  GEditIndex: Integer;
  GEditError: string;
  GCheckIndex: Integer;

procedure OnListAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl; forward;
procedure ShowList; forward;
procedure ShowEdit; forward;

// The text cut to AWidth characters or padded with blanks to it.
function Cell(const AText: string; AWidth: Integer): string;
begin
  if Length(AText) > AWidth then
    Result := Copy(AText, 1, AWidth - 3) + '...'
  else
    Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

function CheckKey(const AServer: TBridgeServerConfig): string;
begin
  Result := AServer.Name + '|' + BridgeConsentKey(AServer);
end;

function TransportText(const AServer: TBridgeServerConfig): string;
begin
  if AServer.Transport = btHttp then
    Result := 'http'
  else
    Result := 'stdio';
end;

function StateText(const AServer: TBridgeServerConfig; const AApprovals: string): string;
begin
  if (GChecks <> nil) and GChecks.TryGetValue(CheckKey(AServer), Result) then
    Exit;
  if BridgeIsApproved(AApprovals, AServer) then
    Result := Translated('bridge.state.approved', 'approved')
  else
    Result := Translated('bridge.state.pending', 'not approved');
end;

function RowText(AIndex: Integer; const AServer: TBridgeServerConfig; const AApprovals: string): string;
begin
  Result := Cell(IntToStr(AIndex + 1), cColNo) + ' ' + Cell(AServer.Name, cColName) + ' ' +
    Cell(TransportText(AServer), cColType) + ' ' + Cell(BridgeTargetText(AServer), cColTarget) + ' ' +
    Cell(StateText(AServer, AApprovals), cColState);
end;

procedure AddRule(AKids: TJSONArray; ARow: Integer);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', 'separator');
  O.AddPair('col', TJSONNumber.Create(0));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(98));
  O.AddPair('height', TJSONNumber.Create(1));
  AKids.AddElement(O);
end;

// The next dialog is shown from inside the answer of the previous one: the host has closed
// the answered dialog by then, and returns to the Plugins list when no dialog is open as
// the answer ends.
procedure ContinueWith(AProc: THostMainCallback);
begin
  AProc(nil);
end;

procedure ReopenList(AUserData: Pointer); cdecl;
begin
  try
    ShowList;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure ReopenEdit(AUserData: Pointer); cdecl;
begin
  try
    ShowEdit;
  except
    // Never let an exception cross into the host.
  end;
end;

procedure FreeDraft;
begin
  FreeAndNil(GDraft);
  FreeAndNil(GChecks);
  GStatus := '';
  GEditError := '';
end;

procedure ShowList;
var
  Decl, ListCtl, Check: TJSONObject;
  Kids: TJSONArray;
  Items: TJSONArray;
  I: Integer;
  Approvals: string;
begin
  if GDraft = nil then
    Exit;
  if GSel >= GDraft.Count then
    GSel := GDraft.Count - 1;
  if GSel < 0 then
    GSel := 0;
  Approvals := ReadSetting(cSettingApprovals);
  Items := TJSONArray.Create;
  for I := 0 to GDraft.Count - 1 do
    Items.Add(RowText(I, GDraft[I], Approvals));
  if GDraft.Count = 0 then
    Items.Add(Translated('bridge.list.empty', '(no servers: press Add)'));
  Decl := DialogHead(Translated('bridge.title', 'Service bridge'), 100, 21, Kids);
  try
    Kids.AddElement(Ctl('label', '', Translated('bridge.list.hint',
      'Servers (their order is the order of the list):'), 2, 0, cListWidth, False, False));
    Kids.AddElement(Ctl('label', '',
      Cell('#', cColNo) + ' ' + Cell(Translated('bridge.col.name', 'Name'), cColName) + ' ' +
      Cell(Translated('bridge.col.type', 'Type'), cColType) + ' ' +
      Cell(Translated('bridge.col.target', 'Program or address'), cColTarget) + ' ' +
      Cell(Translated('bridge.col.state', 'State'), cColState), 2, 1, cListWidth, False, False));
    ListCtl := Ctl('list', 'servers', '', 2, 2, cListWidth, False, False);
    ListCtl.RemovePair('height').Free;
    ListCtl.AddPair('height', TJSONNumber.Create(cListRows));
    ListCtl.AddPair('items', Items);
    ListCtl.AddPair('selected', TJSONNumber.Create(GSel));
    ListCtl.AddPair('keycommands', TJSONBool.Create(True));
    Kids.AddElement(ListCtl);
    AddRule(Kids, 10);
    Kids.AddElement(Ctl('label', '', Copy(GStatus, 1, cStatusWidth), 2, 11, cStatusWidth, False, False));
    Kids.AddElement(Ctl('label', '', Translated('bridge.list.keys',
      'F2 edit   Del delete   Ctrl+Up / Ctrl+Down move   F5 check'), 2, 12, cListWidth, False, False));
    Check := Ctl('checkbox', cSettingProvider, Translated('bridge.provider',
      'Offer the servers as providers of JSON-RPC services (needs a restart)'), 2, 13, cListWidth, False, False);
    Check.AddPair('checked', TJSONBool.Create(GDraftProvider));
    Kids.AddElement(Check);
    Kids.AddElement(Ctl('button', 'add', Translated('bridge.add', 'Add'), 2, 15, 12, False, False));
    Kids.AddElement(Ctl('button', 'edit', Translated('bridge.edit', 'Edit'), 17, 15, 12, True, False));
    Kids.AddElement(Ctl('button', 'delete', Translated('bridge.delete', 'Delete'), 32, 15, 12, False, False));
    Kids.AddElement(Ctl('button', 'up', Translated('bridge.up', 'Up'), 47, 15, 12, False, False));
    Kids.AddElement(Ctl('button', 'down', Translated('bridge.down', 'Down'), 62, 15, 12, False, False));
    Kids.AddElement(Ctl('button', 'check', Translated('bridge.check', 'Check'), 77, 15, 12, False, False));
    Kids.AddElement(Ctl('button', 'ok', Translated('bridge.ok', 'OK'), 36, 17, 12, False, False));
    Kids.AddElement(Ctl('button', 'cancel', Translated('bridge.cancel', 'Cancel'), 52, 17, 12, False, True));
    ShowJson(Decl.ToJSON, OnListAnswer, nil);
  finally
    Decl.Free;
  end;
end;

{ The edit dialog of one server }

function SelectedType(const AValuesJson: string): TBridgeTransport;
var
  Root: TJSONValue;
begin
  Result := btStdio;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if (Root is TJSONObject) and
       (TJSONObject(Root).GetValue<string>('type', '') = Translated('bridge.type.http', 'HTTP address')) then
      Result := btHttp;
  finally
    Root.Free;
  end;
end;

function ValueOf(const AValuesJson, AName: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if Root is TJSONObject then
      Result := TJSONObject(Root).GetValue<string>(AName, '');
  finally
    Root.Free;
  end;
end;

function BoolValueOf(const AValuesJson, AName: string; ADefault: Boolean): Boolean;
var
  Root: TJSONValue;
begin
  Result := ADefault;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if Root is TJSONObject then
      Result := TJSONObject(Root).GetValue<Boolean>(AName, ADefault);
  finally
    Root.Free;
  end;
end;

// Builds the server from the fields of the edit dialog; the fields of the other transport
// are left out.
function ServerFromFields(const AValuesJson: string): TBridgeServerConfig;
var
  Timeout: Integer;
begin
  Result := Default(TBridgeServerConfig);
  Result.Name := Trim(ValueOf(AValuesJson, 'name'));
  Result.Transport := SelectedType(AValuesJson);
  if Result.Transport = btHttp then
  begin
    Result.Url := Trim(ValueOf(AValuesJson, 'url'));
    Result.Headers := BridgeSplitWords(ValueOf(AValuesJson, 'headers'));
  end
  else
  begin
    Result.Command := Trim(ValueOf(AValuesJson, 'command'));
    Result.Args := BridgeSplitWords(ValueOf(AValuesJson, 'args'));
    Result.Dir := Trim(ValueOf(AValuesJson, 'cwd'));
    Result.Env := BridgeSplitWords(ValueOf(AValuesJson, 'env'));
  end;
  if not TryStrToInt(Trim(ValueOf(AValuesJson, 'timeout')), Timeout) then
    Timeout := cDefaultStartTimeoutMs;
  Result.StartTimeoutMs := Timeout;
  if Result.StartTimeoutMs < cMinStartTimeoutMs then
    Result.StartTimeoutMs := cMinStartTimeoutMs;
  if Result.StartTimeoutMs > cMaxStartTimeoutMs then
    Result.StartTimeoutMs := cMaxStartTimeoutMs;
  Result.Allow := BridgeSplitWords(ValueOf(AValuesJson, 'allow'));
end;

function NameTaken(const AName: string; AExceptIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to GDraft.Count - 1 do
    if (I <> AExceptIndex) and (GDraft[I].Name = AName) then
      Exit(True);
end;

procedure OnEditAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Err: string;
begin
  try
    if GDraft = nil then
      Exit;
    if not SameText(string(AControlId), 'ok') then
    begin
      ContinueWith(ReopenList);
      Exit;
    end;
    GEdit := ServerFromFields(UTF8ToString(AValuesJson));
    if not ValidateBridgeServer(GEdit, Err) then
      GEditError := Err
    else if NameTaken(GEdit.Name, GEditIndex) then
      GEditError := 'server name "' + GEdit.Name + '" is used twice'
    else if (GEditIndex < 0) and (GDraft.Count >= cMaxServers) then
      GEditError := 'too many servers'
    else
      GEditError := '';
    if GEditError <> '' then
    begin
      ContinueWith(ReopenEdit);
      Exit;
    end;
    if GEditIndex >= 0 then
      GDraft[GEditIndex] := GEdit
    else
    begin
      GDraft.Add(GEdit);
      GEditIndex := GDraft.Count - 1;
    end;
    GSel := GEditIndex;
    GStatus := '';
    ContinueWith(ReopenList);
  except
    // Never let an exception cross into the host.
  end;
end;

function InputCtl(const AId, AValue: string; ARow: Integer): TJSONObject;
begin
  Result := Ctl('input', AId, '', 21, ARow, 60, False, False);
  Result.AddPair('value', AValue);
end;

procedure ShowEdit;
var
  Decl, Kind: TJSONObject;
  Kids: TJSONArray;
  Items: TJSONArray;
  Row: Integer;
begin
  Decl := DialogHead(Translated('bridge.field.title', 'Server'), 84, 22, Kids);
  try
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.name', 'Name:'), 2, 1, 18, False, False));
    Kids.AddElement(InputCtl('name', GEdit.Name, 1));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.type', 'Type:'), 2, 2, 18, False, False));
    Items := TJSONArray.Create;
    Items.Add(Translated('bridge.type.stdio', 'Program (stdin/stdout)'));
    Items.Add(Translated('bridge.type.http', 'HTTP address'));
    Kind := Ctl('dropdown', 'type', '', 21, 2, 60, False, False);
    Kind.AddPair('items', Items);
    Kind.AddPair('selected', TJSONNumber.Create(Ord(GEdit.Transport)));
    Kids.AddElement(Kind);
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.program', 'Program:'), 2, 4, 18, False, False));
    Kids.AddElement(InputCtl('command', GEdit.Command, 4));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.args', 'Arguments:'), 2, 5, 18, False, False));
    Kids.AddElement(InputCtl('args', BridgeJoinWords(GEdit.Args), 5));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.cwd', 'Folder:'), 2, 6, 18, False, False));
    Kids.AddElement(InputCtl('cwd', GEdit.Dir, 6));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.env', 'Environment:'), 2, 7, 18, False, False));
    Kids.AddElement(InputCtl('env', BridgeJoinWords(GEdit.Env), 7));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.url', 'Address:'), 2, 9, 18, False, False));
    Kids.AddElement(InputCtl('url', GEdit.Url, 9));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.headers', 'Headers:'), 2, 10, 18, False, False));
    Kids.AddElement(InputCtl('headers', BridgeJoinWords(GEdit.Headers), 10));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.timeout', 'Start timeout, ms:'), 2, 12, 18, False, False));
    if GEdit.StartTimeoutMs = 0 then
      GEdit.StartTimeoutMs := cDefaultStartTimeoutMs;
    Kids.AddElement(InputCtl('timeout', IntToStr(GEdit.StartTimeoutMs), 12));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.allow', 'Allowed tools:'), 2, 13, 18, False, False));
    Kids.AddElement(InputCtl('allow', BridgeJoinWords(GEdit.Allow), 13));
    Kids.AddElement(Ctl('label', '', Translated('bridge.field.hint',
      'Words are separated by blanks, "double quotes" group them; environment and headers are NAME=VALUE.'),
      2, 15, 78, False, False));
    Row := 16;
    if GEditError <> '' then
      Kids.AddElement(Ctl('label', '', Copy(GEditError, 1, 78), 2, Row, 78, False, False));
    Kids.AddElement(Ctl('button', 'ok', Translated('bridge.ok', 'OK'), 28, 18, 12, True, False));
    Kids.AddElement(Ctl('button', 'cancel', Translated('bridge.cancel', 'Cancel'), 44, 18, 12, False, True));
    ShowJson(Decl.ToJSON, OnEditAnswer, nil);
  finally
    Decl.Free;
  end;
end;

{ Check: the server is started the way a call would start it, asked for its tools and ended. }

procedure ReportCheck(const AServer: TBridgeServerConfig);
var
  Count: Integer;
  Err, Text: string;
begin
  if ProbeBridgeServer(AServer, RealBridgeChildFactory(), Count, Err) then
    Text := Format(Translated('bridge.state.ok', 'OK, tools: %d'), [Count])
  else
    Text := Translated('bridge.state.fail', 'not available') + ': ' + Err;
  GChecks.AddOrSetValue(CheckKey(AServer), Text);
  GStatus := AServer.Name + ' - ' + Text;
end;

procedure OnCheckConsent(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Server: TBridgeServerConfig;
begin
  try
    if (GDraft <> nil) and (GCheckIndex >= 0) and (GCheckIndex < GDraft.Count) then
    begin
      Server := GDraft[GCheckIndex];
      if SameText(string(AControlId), 'ok') then
      begin
        WriteSetting(cSettingApprovals, BridgeWithApproval(ReadSetting(cSettingApprovals), Server));
        ReportCheck(Server);
      end
      else
        GStatus := Server.Name + ' - ' + Translated('bridge.state.pending', 'not approved');
    end;
    ContinueWith(ReopenList);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure CheckSelected;
var
  Server: TBridgeServerConfig;
begin
  Server := GDraft[GSel];
  // A program or an address the user has not approved is never started or contacted: the
  // check asks first, like the first start would.
  if not BridgeIsApproved(ReadSetting(cSettingApprovals), Server) then
  begin
    GCheckIndex := GSel;
    ShowConsent(Server, OnCheckConsent);
    Exit;
  end;
  ReportCheck(Server);
  ContinueWith(ReopenList);
end;

{ Answers of the list }

// The row the text of the list stands for: the number in its first column.
function RowIndexOf(const AText: string): Integer;
var
  P: Integer;
begin
  Result := -1;
  P := Pos(' ', AText);
  if P > 1 then
    if TryStrToInt(Copy(AText, 1, P - 1), Result) then
      Dec(Result)
    else
      Result := -1;
  if (GDraft = nil) or (Result >= GDraft.Count) then
    Result := -1;
end;

procedure SwapRows(AFrom, ATo: Integer);
var
  Tmp: TBridgeServerConfig;
begin
  if (ATo < 0) or (ATo >= GDraft.Count) then
    Exit;
  Tmp := GDraft[AFrom];
  GDraft[AFrom] := GDraft[ATo];
  GDraft[ATo] := Tmp;
  GSel := ATo;
end;

// Writes the draft to the settings and asks about every server not approved yet.
procedure SaveDraft;
var
  Old, Servers: TArray<TBridgeServerConfig>;
  S: TBridgeServerConfig;
  Err, Approvals: string;
begin
  Servers := GDraft.ToArray;
  if ParseBridgeServers(ReadSetting(cSettingServers), Old, Err) then
    for S in Old do
      WriteSetting(cToolsPrefix + S.Name, '');
  WriteSetting(cSettingServers, BridgeServersToJson(Servers));
  if GDraftProvider then
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
  FreeDraft;
  NextConsent;
end;

procedure OnListAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Cmd, Values: string;
  Row: Integer;
begin
  try
    if GDraft = nil then
      Exit;
    Cmd := LowerCase(string(AControlId));
    if Cmd = 'cancel' then
    begin
      FreeDraft;
      Exit;
    end;
    Values := UTF8ToString(AValuesJson);
    GDraftProvider := BoolValueOf(Values, cSettingProvider, GDraftProvider);
    Row := RowIndexOf(ValueOf(Values, 'servers'));
    if Row >= 0 then
      GSel := Row
    else
      Row := GSel;
    if Cmd = 'ok' then
    begin
      SaveDraft;
      Exit;
    end;
    GStatus := '';
    if Cmd = 'add' then
    begin
      GEdit := Default(TBridgeServerConfig);
      GEdit.StartTimeoutMs := cDefaultStartTimeoutMs;
      GEditIndex := -1;
      GEditError := '';
      ContinueWith(ReopenEdit);
      Exit;
    end;
    if (Row < 0) or (Row >= GDraft.Count) then
    begin
      ContinueWith(ReopenList);
      Exit;
    end;
    if (Cmd = 'edit') or (Cmd = 'f2') or (Cmd = 'f4') then
    begin
      GEdit := GDraft[Row];
      GEditIndex := Row;
      GEditError := '';
      ContinueWith(ReopenEdit);
      Exit;
    end
    else if Cmd = 'delete' then
    begin
      GDraft.Delete(Row);
      if GSel >= GDraft.Count then
        GSel := GDraft.Count - 1;
    end
    else if Cmd = 'up' then
      SwapRows(Row, Row - 1)
    else if Cmd = 'down' then
      SwapRows(Row, Row + 1)
    else if (Cmd = 'check') or (Cmd = 'f5') then
    begin
      CheckSelected;
      Exit;
    end;
    ContinueWith(ReopenList);
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Servers: TArray<TBridgeServerConfig>;
  Err: string;
begin
  try
    FreeDraft;
    GDraft := TList<TBridgeServerConfig>.Create;
    GChecks := TDictionary<string, string>.Create;
    if ParseBridgeServers(ReadSetting(cSettingServers), Servers, Err) then
      GDraft.AddRange(Servers)
    else
      GStatus := Err;
    GDraftProvider := ServiceProviderEnabled(GHost, GPluginId);
    GSel := 0;
    ShowList;
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
