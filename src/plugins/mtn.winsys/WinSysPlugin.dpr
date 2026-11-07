library WinSysPlugin;

{ Native MTN2 plugin: the running processes and the services as folders of the
  panels (proc://, svc://), and on Windows the registry (reg://). Adds them to
  the Change Drive list (Alt+F1 / Alt+F2). Services are colored by their state;
  the Plugins menu starts, stops and restarts the service under the cursor, and
  on Windows also pauses and resumes it. Processes and services come from the
  system APIs on Windows and from /proc and systemctl on Linux. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ELSE}
  uWinSysCodes,
{$ENDIF}
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uWinSysFormat in 'uWinSysFormat.pas',
  uWinSysRegistry,
  uWinSysProcess,
  uWinSysServices,
  uWinSysVfs in 'uWinSysVfs.pas';

const
  cPluginId = 'mtn.winsys';
{$IFDEF MSWINDOWS}
  cSchemes: array[0..2] of UTF8String = ('reg', 'proc', 'svc');
{$ELSE}
  cSchemes: array[0..1] of UTF8String = ('proc', 'svc');
{$ENDIF}
  cRowDecorationsAbi = 6;
  cPanelColumnsAbi = 9;
  cProcColumnsJson =
    '{"builtin":[],"columns":[{"id":"pid","title":"PID","width":7,"align":"right","default":true,"sortable":true},' +
    '{"id":"ppid","title":"PPID","width":7,"align":"right","default":false,"sortable":true},' +
    '{"id":"threads","title":"Thr","title_key":"ui.col.threads","width":5,"align":"right","default":false,"sortable":true}]}';
  cSvcColumnsJson =
    '{"builtin":[],"columns":[{"id":"state","title":"State","title_key":"ui.col.state","width":10,"default":true,"sortable":true},' +
    '{"id":"pid","title":"PID","width":7,"align":"right","default":false,"sortable":true},' +
    '{"id":"display","title":"Display name","title_key":"ui.col.display","width":30,"default":true,"sortable":true}]}';
  cControlTimeoutMs = 30000;
  cDrivePriority = 110;

type
  /// <summary>The outcome of a service operation, handed from the worker thread to the main thread.</summary>
  TControlResult = class
    Name: string;
    Err: Cardinal;
  end;

var
  GHost: PHostApiTable;
  GLock: TCriticalSection;
  GColorsUri: string;
  GColorsJson: string;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..511] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if (GHost = nil) or not Assigned(GHost.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHost.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure Notice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if (GHost = nil) or not Assigned(GHost.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHost.ShowMessage(PAnsiChar(Text), AKind);
end;

procedure PostToMain(ACallback: THostMainCallback; AData: Pointer);
var
  Id: UTF8String;
begin
  if (GHost = nil) or not Assigned(GHost.PostToMain) then
    Exit;
  Id := UTF8String(cPluginId);
  GHost.PostToMain(PAnsiChar(Id), ACallback, AData);
end;

{ row colors of svc:/// }

procedure MainApplyColors(AUserData: Pointer); cdecl;
var
  Uri, Json: string;
  UriU, JsonU, Id: UTF8String;
begin
  if (GHost = nil) or not Assigned(GHost.SetRowDecorations) then
    Exit;
  GLock.Enter;
  try
    Uri := GColorsUri;
    Json := GColorsJson;
  finally
    GLock.Leave;
  end;
  if Uri = '' then
    Exit;
  Id := UTF8String(cPluginId);
  UriU := UTF8String(Uri);
  JsonU := UTF8String(Json);
  GHost.SetRowDecorations(PAnsiChar(Id), PAnsiChar(UriU), PAnsiChar(JsonU));
end;

procedure OnServiceColors(const AFolderUri, AJson: string);
begin
  GLock.Enter;
  try
    GColorsUri := AFolderUri;
    GColorsJson := AJson;
  finally
    GLock.Leave;
  end;
  PostToMain(MainApplyColors, nil);
end;

{ service commands }

function ReadPanelInfo: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if (GHost = nil) or not Assigned(GHost.PanelInfo) then
    Exit;
  Len := GHost.PanelInfo(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHost.PanelInfo(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

// The address of the row under the cursor in the active panel.
function ActiveCursorUri(const APanelInfo: string): string;
var
  Root, Side: TJSONValue;
  Active: string;
begin
  Result := '';
  if APanelInfo = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(APanelInfo);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if Side is TJSONObject then
      Side.TryGetValue<string>('cursor', Result);
  finally
    Root.Free;
  end;
end;

procedure MainControlDone(AUserData: Pointer); cdecl;
var
  R: TControlResult;
begin
  R := TControlResult(AUserData);
  try
    if R.Err = 0 then
      Notice(Format(Tr('ui.msg.done', 'Service %s: done.'), [R.Name]), 0)
    else
      Notice(Format(Tr('ui.msg.failed', 'Service %s: %s'),
        [R.Name, WinSysErrorText(R.Err)]), 1);
    if Assigned(GHost.PanelRefresh) then
      GHost.PanelRefresh;
  finally
    R.Free;
  end;
end;

procedure RunServiceAction(AAction: TSvcAction);
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
  Name: string;
begin
  if not ParseWinSysUri(ActiveCursorUri(ReadPanelInfo), Kind, Segs) or (Kind <> wkSvc) or
     (Length(Segs) <> 1) then
  begin
    Notice(Tr('ui.msg.notService', 'Put the cursor on a service in svc:///.'), 1);
    Exit;
  end;
  Name := Segs[0];
  // Starting and stopping wait for the service, so the work runs off the main thread.
  TThread.CreateAnonymousThread(
    procedure
    var
      R: TControlResult;
    begin
      R := TControlResult.Create;
      R.Name := Name;
      try
        R.Err := ControlServiceByName(Name, AAction, cControlTimeoutMs);
      except
        R.Err := ERROR_INVALID_FUNCTION;
      end;
      PostToMain(MainControlDone, R);
    end).Start;
end;

procedure CmdService(AUserData: Pointer); cdecl;
begin
  try
    RunServiceAction(TSvcAction(NativeInt(AUserData)));
  except
    // A failing command must not reach the host.
  end;
end;

procedure AddMenu(const AId, AKey, ADefault: string; AAction: TSvcAction; APriority: Int64);
var
  Id, Item, Caption: UTF8String;
begin
  Id := UTF8String(cPluginId);
  Item := UTF8String(AId);
  Caption := UTF8String(Tr(AKey, ADefault));
  GHost.RegisterMenuItem(PAnsiChar(Id), 'Plugins', PAnsiChar(Item), PAnsiChar(Caption),
    @CmdService, Pointer(NativeInt(Ord(AAction))), APriority);
end;

procedure AddDrive(const AId, AKey, ADefault, AUri: string; APriority: Int64);
var
  Id, Item, Caption, Uri: UTF8String;
begin
  Id := UTF8String(cPluginId);
  Item := UTF8String(AId);
  Caption := UTF8String(Tr(AKey, ADefault));
  Uri := UTF8String(AUri);
  GHost.RegisterDriveItem(PAnsiChar(Id), PAnsiChar(Item), PAnsiChar(Caption), PAnsiChar(Uri), APriority);
end;

var
  GCallbacks: TVfsCallbacksCdeclV2;

function FBarJson(const AScheme: string): string;
var
  Root, Root1, Inside: TJSONObject;
  K: string;
begin
  Root := TJSONObject.Create;
  try
    Root1 := TJSONObject.Create;
    for K in ['F3', 'F4', 'F5', 'F6', 'F7', 'F8'] do
      Root1.AddPair(K, '');
    Root.AddPair('root', Root1);
    if AScheme <> 'reg' then
    begin
      // Processes and services are read-only listings except for F8.
      Inside := TJSONObject.Create;
      for K in ['F4', 'F5', 'F6', 'F7'] do
        Inside.AddPair(K, '');
      Root.AddPair('inside', Inside);
    end
    else
    begin
      Inside := TJSONObject.Create;
      Inside.AddPair('F6', '');
      Root.AddPair('inside', Inside);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  S: UTF8String;
  Id: UTF8String;
begin
  Result := -1;
  try
    if (AHostApi = nil) or (AHostApi.AbiVersion < 4) or
       not Assigned(AHostApi.RegisterVfsSchemeV2) then
      Exit;
    GHost := AHostApi;
    GLock := TCriticalSection.Create;
    Id := UTF8String(cPluginId);
    GCallbacks := WinSysVfsCallbacks;
    for S in cSchemes do
    begin
      AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(S), @GCallbacks, nil, 60);
      if Assigned(AHostApi.RegisterPanelPlugin) then
        AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(S), 60);
      if Assigned(AHostApi.SetPanelFBar) then
        AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(S), PAnsiChar(UTF8String(FBarJson(string(S)))));
    end;
    if (AHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(AHostApi.RegisterPanelColumns) then
    begin
      AHostApi.RegisterPanelColumns(PAnsiChar(Id), 'proc', PAnsiChar(UTF8String(cProcColumnsJson)));
      AHostApi.RegisterPanelColumns(PAnsiChar(Id), 'svc', PAnsiChar(UTF8String(cSvcColumnsJson)));
    end;
    if Assigned(AHostApi.RegisterDriveItem) then
    begin
{$IFDEF MSWINDOWS}
      AddDrive('reg', 'ui.drive.reg', 'Registry', 'reg:///', cDrivePriority);
{$ENDIF}
      AddDrive('proc', 'ui.drive.proc', 'Processes', 'proc:///', cDrivePriority + 1);
      AddDrive('svc', 'ui.drive.svc', 'Services', 'svc:///', cDrivePriority + 2);
    end;
    if (AHostApi.AbiVersion >= cRowDecorationsAbi) and Assigned(AHostApi.SetRowDecorations) and
       Assigned(AHostApi.PostToMain) then
      GOnServiceColors := OnServiceColors;
    if Assigned(AHostApi.RegisterMenuItem) and Assigned(AHostApi.PanelInfo) and
       Assigned(AHostApi.PostToMain) then
    begin
      AddMenu('svc_start', 'ui.menu.start', 'Services: start', saStart, 70);
      AddMenu('svc_stop', 'ui.menu.stop', 'Services: stop', saStop, 71);
      AddMenu('svc_restart', 'ui.menu.restart', 'Services: restart', saRestart, 72);
{$IFDEF MSWINDOWS}
      AddMenu('svc_pause', 'ui.menu.pause', 'Services: pause', saPause, 73);
      AddMenu('svc_resume', 'ui.menu.resume', 'Services: resume', saResume, 74);
{$ENDIF}
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GOnServiceColors := nil;
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
