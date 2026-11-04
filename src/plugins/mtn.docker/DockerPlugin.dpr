library DockerPlugin;

{ Native MTN2 plugin: Docker containers and images and Kubernetes pods as
  folders of the panels (docker:///). Adds Docker to the Change Drive list
  (Alt+F1 / Alt+F2). Containers and pods are colored by state; the Plugins menu
  starts, stops, restarts, pauses and unpauses the container under the cursor. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uDockerFormat in 'uDockerFormat.pas',
  uDockerVfs in 'uDockerVfs.pas';

const
  cPluginId = 'mtn.docker';
  cScheme: UTF8String = 'docker';
  cRowDecorationsAbi = 6;
  cDrivePriority = 120;

type
  /// <summary>The outcome of a container command, handed from the worker thread to the main thread.</summary>
  TControlResult = class
    Name: string;
    Error: string;
  end;

var
  GHost: PHostApiTable;
  GLock: TCriticalSection;
  GColorsUri: string;
  GColorsJson: string;
  GCallbacks: TVfsCallbacksCdeclV2;

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

{ row colors of the container and pod lists }

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

procedure OnRowColors(const AFolderUri, AJson: string);
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

{ container commands }

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
    if R.Error = '' then
      Notice(Format(Tr('ui.msg.done', 'Container %s: done.'), [R.Name]), 0)
    else
      Notice(Format(Tr('ui.msg.failed', 'Container %s: %s'), [R.Name, R.Error]), 1);
    if Assigned(GHost.PanelRefresh) then
      GHost.PanelRefresh;
  finally
    R.Free;
  end;
end;

procedure RunContainerCommand(const AVerb: string);
var
  Addr: TDockerAddr;
  Name: string;
begin
  if not ParseDockerUri(ActiveCursorUri(ReadPanelInfo), Addr) or (Addr.Backend <> dbDocker) or
     (Addr.Node <> dnItem) then
  begin
    Notice(Tr('ui.msg.notContainer', 'Put the cursor on a container in docker:///containers.'), 1);
    Exit;
  end;
  Name := Addr.Name;
  // Starting and stopping wait for the container, so the work runs off the main thread.
  TThread.CreateAnonymousThread(
    procedure
    var
      R: TControlResult;
    begin
      R := TControlResult.Create;
      R.Name := Name;
      try
        R.Error := ControlContainer(AVerb, Name);
      except
        on E: Exception do
          R.Error := E.Message;
      end;
      PostToMain(MainControlDone, R);
    end).Start;
end;

procedure CmdContainer(AUserData: Pointer); cdecl;
const
  cVerbs: array[0..4] of string = ('start', 'stop', 'restart', 'pause', 'unpause');
begin
  try
    RunContainerCommand(cVerbs[NativeInt(AUserData)]);
  except
    // A failing command must not reach the host.
  end;
end;

procedure AddMenu(const AId, AKey, ADefault: string; AVerb: Integer; APriority: Int64);
var
  Id, Item, Caption: UTF8String;
begin
  Id := UTF8String(cPluginId);
  Item := UTF8String(AId);
  Caption := UTF8String(Tr(AKey, ADefault));
  GHost.RegisterMenuItem(PAnsiChar(Id), 'Plugins', PAnsiChar(Item), PAnsiChar(Caption),
    @CmdContainer, Pointer(NativeInt(AVerb)), APriority);
end;

function FBarJson: string;
var
  Root, Section: TJSONObject;
  K: string;
begin
  Root := TJSONObject.Create;
  try
    Section := TJSONObject.Create;
    for K in ['F3', 'F4', 'F5', 'F6', 'F7', 'F8'] do
      Section.AddPair(K, '');
    Root.AddPair('root', Section);
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
  Id, Item, Caption, Uri: UTF8String;
begin
  Result := -1;
  try
    if (AHostApi = nil) or (AHostApi.AbiVersion < 4) or
       not Assigned(AHostApi.RegisterVfsSchemeV2) then
      Exit;
    GHost := AHostApi;
    GLock := TCriticalSection.Create;
    Id := UTF8String(cPluginId);
    GCallbacks := DockerVfsCallbacks;
    AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(cScheme), @GCallbacks, nil, 60);
    if Assigned(AHostApi.RegisterPanelPlugin) then
      AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(cScheme), 60);
    if Assigned(AHostApi.RegisterDriveItem) then
    begin
      Item := 'docker';
      Caption := UTF8String(Tr('ui.drive.docker', 'Docker'));
      Uri := 'docker:///';
      AHostApi.RegisterDriveItem(PAnsiChar(Id), PAnsiChar(Item), PAnsiChar(Caption), PAnsiChar(Uri),
        cDrivePriority);
    end;
    if Assigned(AHostApi.SetPanelFBar) then
      AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(cScheme), PAnsiChar(UTF8String(FBarJson)));
    if (AHostApi.AbiVersion >= cRowDecorationsAbi) and Assigned(AHostApi.SetRowDecorations) and
       Assigned(AHostApi.PostToMain) then
      GOnRowColors := OnRowColors;
    if Assigned(AHostApi.RegisterMenuItem) and Assigned(AHostApi.PanelInfo) and
       Assigned(AHostApi.PostToMain) then
    begin
      AddMenu('ctr_start', 'ui.menu.start', 'Docker: start container', 0, 80);
      AddMenu('ctr_stop', 'ui.menu.stop', 'Docker: stop container', 1, 81);
      AddMenu('ctr_restart', 'ui.menu.restart', 'Docker: restart container', 2, 82);
      AddMenu('ctr_pause', 'ui.menu.pause', 'Docker: pause container', 3, 83);
      AddMenu('ctr_unpause', 'ui.menu.unpause', 'Docker: unpause container', 4, 84);
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GOnRowColors := nil;
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
