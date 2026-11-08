library RclonePlugin;

{ Native MTN2 plugin: the remotes configured in rclone (Google Drive, OneDrive,
  Dropbox, S3 and dozens of other storages) as folders of the panels
  (rclone:///). Adds Rclone to the Change Drive list (Alt+F1 / Alt+F2). }

uses
  System.SysUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uRcloneFormat in 'uRcloneFormat.pas',
  uRcloneVfs in 'uRcloneVfs.pas';

const
  cPluginId = 'mtn.rclone';
  cScheme: UTF8String = 'rclone';
  cDrivePriority = 125;
  // The list of remotes holds only the configured remotes: nothing to view, edit,
  // copy, move, create or delete there.
  cFBarJson =
    '{"root":{"F3":"","F4":"","F5":"","F6":"","F7":"","F8":"",' +
    '"Shift+F4":"","Shift+F5":"","Shift+F6":""}}';

var
  GHost: PHostApiTable;
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
    Id := UTF8String(cPluginId);
    GCallbacks := RcloneVfsCallbacks;
    AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(cScheme), @GCallbacks, nil, 60);
    if Assigned(AHostApi.RegisterPanelPlugin) then
      AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(cScheme), 60);
    if Assigned(AHostApi.SetPanelFBar) then
      AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(cScheme), PAnsiChar(UTF8String(cFBarJson)));
    if Assigned(AHostApi.RegisterDriveItem) then
    begin
      Item := 'rclone';
      Caption := UTF8String(Tr('ui.drive.rclone', 'Rclone'));
      Uri := 'rclone:///';
      AHostApi.RegisterDriveItem(PAnsiChar(Id), PAnsiChar(Item), PAnsiChar(Caption), PAnsiChar(Uri),
        cDrivePriority);
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  GHost := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
