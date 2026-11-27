library AdbPlugin;

{ Native MTN2 plugin: Android devices connected through adb as folders of the
  panels (adb:///). Adds Android to the Change Drive list (Alt+F1 / Alt+F2);
  the root lists the devices, colored by their state, and each device is a
  folder with its files. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginSdk in '..\..\Core\uPluginSdk.pas',
  uAdbFormat in 'uAdbFormat.pas',
  uAdbVfs in 'uAdbVfs.pas';

const
  cPluginId = 'mtn.adb';
  cScheme: UTF8String = 'adb';
  cRowDecorationsAbi = 6;
  cPanelColumnsAbi = 9;
  cPanelColumnsJson =
    '{"builtin":[],"columns":[{"id":"state","title":"State","title_key":"ui.col.state","width":14,"default":true,"sortable":true},' +
    '{"id":"model","title":"Model","title_key":"ui.col.model","width":22,"default":true,"sortable":true},' +
    '{"id":"product","title":"Product","title_key":"ui.col.product","width":20,"default":false,"sortable":true}]}';
  cDrivePriority = 125;

var
  GLock: TCriticalSection;
  GColorsUri: string;
  GColorsJson: string;
  GCallbacks: TVfsCallbacksCdeclV2;

{ row colors of the device list }

procedure MainApplyColors(AUserData: Pointer); cdecl;
var
  Uri, Json: string;
  UriU, JsonU, Id: UTF8String;
begin
  if not Assigned(GHostApi.SetRowDecorations) then
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
  GHostApi.SetRowDecorations(PAnsiChar(Id), PAnsiChar(UriU), PAnsiChar(JsonU));
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
  SdkPostToMain(MainApplyColors);
end;

procedure TranslateTexts;
begin
  GAdbText.NoProgram := Tr('ui.error.noAdb', GAdbText.NoProgram);
  GAdbText.Timeout := Tr('ui.error.timeout', GAdbText.Timeout);
  GAdbText.Unauthorized := Tr('ui.error.unauthorized', GAdbText.Unauthorized);
  GAdbText.Offline := Tr('ui.error.offline', GAdbText.Offline);
  GAdbText.NotConnected := Tr('ui.error.notConnected', GAdbText.NotConnected);
  GAdbText.NoPermissions := Tr('ui.error.noPermissions', GAdbText.NoPermissions);
end;

// The device list holds nothing to view, copy or delete.
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
    SdkAttach(AHostApi, cPluginId);
    GLock := TCriticalSection.Create;
    TranslateTexts;
    Id := UTF8String(cPluginId);
    GCallbacks := AdbVfsCallbacks;
    AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(cScheme), @GCallbacks, nil, 60);
    if Assigned(AHostApi.RegisterPanelPlugin) then
      AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(cScheme), 60);
    if Assigned(AHostApi.RegisterDriveItem) then
    begin
      Item := 'adb';
      Caption := UTF8String(Tr('ui.drive.adb', 'Android'));
      Uri := 'adb:///';
      AHostApi.RegisterDriveItem(PAnsiChar(Id), PAnsiChar(Item), PAnsiChar(Caption), PAnsiChar(Uri),
        cDrivePriority);
    end;
    if Assigned(AHostApi.SetPanelFBar) then
      AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(cScheme), PAnsiChar(UTF8String(FBarJson)));
    if (AHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(AHostApi.RegisterPanelColumns) then
      AHostApi.RegisterPanelColumns(PAnsiChar(Id), PAnsiChar(cScheme),
        PAnsiChar(UTF8String(cPanelColumnsJson)));
    if (AHostApi.AbiVersion >= cRowDecorationsAbi) and Assigned(AHostApi.SetRowDecorations) and
       Assigned(AHostApi.PostToMain) then
      GOnRowColors := OnRowColors;
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GOnRowColors := nil;
  SdkDetach;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
