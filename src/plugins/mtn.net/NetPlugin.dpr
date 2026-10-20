library NetPlugin;

{ Native MTN2 plugin: network connections. Adds an item to the Change Drive
  list (Alt+F1 / Alt+F2) that opens the list of saved connections, and serves
  FTP, FTPS, SFTP, SCP, WebDAV and S3 as folders of the panels (net://,
  ftp://, ftps://, nsftp://, scp://, dav://, davs://, s3://). The protocols are
  spoken by libcurl, loaded from this folder. }

uses
  System.SysUtils, System.Classes,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uNetTypes,
  uNetCurlApi,
  uNetManager,
  uNetVfs,
  uNetUi;

const
  cSchemes: array[0..7] of UTF8String =
    ('net', 'ftp', 'ftps', 'nsftp', 'scp', 'dav', 'davs', 's3');
  cDrivePriority = 100;

var
  GHost: PHostApiTable;
  GManager: TNetManager;
  GCallbacks: TVfsCallbacksCdeclV2;

procedure CmdOpenList(AUserData: Pointer); cdecl;
begin
  try
    OpenSessionList;
  except
    // A failing command must not reach the host.
  end;
end;

procedure CmdNewSession(AUserData: Pointer); cdecl;
begin
  try
    EditSession('');
  except
  end;
end;

procedure CmdSettings(AUserData: Pointer); cdecl;
begin
  try
    ShowSettings;
  except
  end;
end;

procedure CmdOpenAddress(AUserData: Pointer); cdecl;
begin
  try
    ShowOpenAddress;
  except
  end;
end;

procedure CmdPermissions(AUserData: Pointer); cdecl;
begin
  try
    ShowChangePermissions;
  except
  end;
end;

// F4 on a connection of the list edits it; everywhere else the built-in editor runs.
function HookEdit(AUserData: Pointer; ACommand, AOrigin: PAnsiChar): Int64; cdecl;
var
  Name: string;
begin
  Result := 0;
  try
    if ActivePanelIsSessionList(Name) and (Name <> '') then
    begin
      EditSession(Name);
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

// F7 in the list of connections makes a new connection.
function HookMkDir(AUserData: Pointer; ACommand, AOrigin: PAnsiChar): Int64; cdecl;
var
  Name: string;
begin
  Result := 0;
  try
    if ActivePanelIsSessionList(Name) then
    begin
      EditSession('');
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Folder, Err, Scheme: string;
  S: UTF8String;
  Caption, Labels: UTF8String;
begin
  Result := -1;
  try
    if (AHostApi = nil) or (AHostApi.AbiVersion < 4) or
       not Assigned(AHostApi.RegisterVfsSchemeV2) or not Assigned(AHostApi.RegisterDriveItem) then
      Exit;
    GHost := AHostApi;
    Folder := ExtractFilePath(GetModuleName(HInstance));
    // Without libcurl the plugin still loads: every operation then says why it fails.
    LoadCurl(Folder, Err);

    GManager := TNetManager.Create;
    NetUiAttach(GHost, GManager);
    GManager.SetPrompter(TNetUiPrompter.Create);
    GManager.LoadSessions(LoadSessionsFromHost);
    GManager.OnStoreChanged := SaveSessionsToHost;
    NetVfsAttach(GManager);

    GCallbacks := NetVfsCallbacks;
    for S in cSchemes do
    begin
      AHostApi.RegisterVfsSchemeV2(PAnsiChar(cPluginId), PAnsiChar(S), @GCallbacks, nil, 60);
      if Assigned(AHostApi.RegisterPanelPlugin) then
        AHostApi.RegisterPanelPlugin(PAnsiChar(cPluginId), PAnsiChar(S), 60);
    end;

    Caption := UTF8String(Tr('ui.drive', 'Network connections'));
    AHostApi.RegisterDriveItem(PAnsiChar(cPluginId), 'net', PAnsiChar(Caption), 'net:///', cDrivePriority);

    if Assigned(AHostApi.RegisterCommand) then
    begin
      AHostApi.RegisterCommand(PAnsiChar(cPluginId), 'net.open', @CmdOpenList, nil);
      AHostApi.RegisterKeyBinding(PAnsiChar(cPluginId), 'net.open', 'Ctrl+Shift+B');
      AHostApi.SetCommandCaption(PAnsiChar(cPluginId), 'net.open', PAnsiChar(UTF8String(Tr('ui.captionOpen', 'Net'))));
    end;
    if Assigned(AHostApi.RegisterCommandHook) then
    begin
      AHostApi.RegisterCommandHook(PAnsiChar(cPluginId), 'Edit', @HookEdit, nil, 50);
      AHostApi.RegisterCommandHook(PAnsiChar(cPluginId), 'MkDir', @HookMkDir, nil, 50);
    end;
    if Assigned(AHostApi.RegisterMenuItem) then
    begin
      AHostApi.RegisterMenuItem(PAnsiChar(cPluginId), 'Commands', 'net_open',
        PAnsiChar(UTF8String(Tr('ui.menu.open', 'Network connections'))), @CmdOpenList, nil, 60);
      AHostApi.RegisterMenuItem(PAnsiChar(cPluginId), 'Commands', 'net_new',
        PAnsiChar(UTF8String(Tr('ui.menu.new', 'New network connection...'))), @CmdNewSession, nil, 61);
      AHostApi.RegisterMenuItem(PAnsiChar(cPluginId), 'Commands', 'net_address',
        PAnsiChar(UTF8String(Tr('ui.menu.address', 'Open network address...'))), @CmdOpenAddress, nil, 62);
      AHostApi.RegisterMenuItem(PAnsiChar(cPluginId), 'Commands', 'net_chmod',
        PAnsiChar(UTF8String(Tr('ui.menu.chmod', 'Permissions on the server...'))), @CmdPermissions, nil, 63);
    end;
    if Assigned(AHostApi.RegisterSettings) then
      AHostApi.RegisterSettings(PAnsiChar(cPluginId), @CmdSettings, nil);
    if Assigned(AHostApi.Subscribe) then
      AHostApi.Subscribe(PAnsiChar(cPluginId), 'panel.dir', @PanelDirChanged, nil);
    if Assigned(AHostApi.SetPanelFBar) then
    begin
      Labels := UTF8String(SessionListFBarJson);
      for S in cSchemes do
        AHostApi.SetPanelFBar(PAnsiChar(cPluginId), PAnsiChar(S), PAnsiChar(Labels));
    end;
    Scheme := '';
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  // The library stays loaded (keepLoaded in plugin.json), so a transfer still
  // running on a worker thread finishes safely; new calls find nothing attached.
  NetVfsAttach(nil);
  NetUiDetach;
  if GManager <> nil then
  begin
    GManager.SetPrompter(nil);
    GManager.OnStoreChanged := nil;
    GManager.Disconnect;
  end;
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
