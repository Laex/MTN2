library JTreePlugin;

{ Native MTN2 plugin: a JSON or YAML file as a tree of folders (jtree:///). Enter on a
  .json, .yaml or .yml file opens it; objects and arrays are folders, values are files
  (F3 shows one). The panel columns give the type and the value of each row. }

uses
  System.SysUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uYamlLite in 'uYamlLite.pas',
  uJsonTree in 'uJsonTree.pas',
  uJsonTreeVfs in 'uJsonTreeVfs.pas';

const
  cPluginId = 'mtn.jtree';
  cScheme: UTF8String = 'jtree';
  cPanelColumnsAbi = 9;
  // A tree is read-only: values can be viewed and copied out, nothing is edited,
  // moved, created or deleted.
  cFBarJson =
    '{"root":{"F4":"","F6":"","F7":"","F8":"","Shift+F4":"","Shift+F5":"","Shift+F6":""},' +
    '"inside":{"F4":"","F6":"","F7":"","F8":"","Shift+F4":"","Shift+F5":"","Shift+F6":""}}';
  cPanelColumnsJson =
    '{"builtin":[],"columns":[{"id":"value","title":"Value","title_key":"ui.col.value","width":40,"default":true,"sortable":true},' +
    '{"id":"type","title":"Type","title_key":"ui.col.type","width":8,"default":true,"sortable":true}]}';

var
  GCallbacks: TVfsCallbacksCdeclV2;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Id: UTF8String;
begin
  Result := -1;
  try
    if (AHostApi = nil) or (AHostApi.AbiVersion < 4) or
       not Assigned(AHostApi.RegisterVfsSchemeV2) then
      Exit;
    Id := UTF8String(cPluginId);
    GCallbacks := JsonTreeVfsCallbacks;
    AHostApi.RegisterVfsSchemeV2(PAnsiChar(Id), PAnsiChar(cScheme), @GCallbacks, nil, 60);
    if Assigned(AHostApi.RegisterPanelPlugin) then
      AHostApi.RegisterPanelPlugin(PAnsiChar(Id), PAnsiChar(cScheme), 60);
    if Assigned(AHostApi.SetPanelFBar) then
      AHostApi.SetPanelFBar(PAnsiChar(Id), PAnsiChar(cScheme), PAnsiChar(UTF8String(cFBarJson)));
    if (AHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(AHostApi.RegisterPanelColumns) then
      AHostApi.RegisterPanelColumns(PAnsiChar(Id), PAnsiChar(cScheme),
        PAnsiChar(UTF8String(cPanelColumnsJson)));
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
