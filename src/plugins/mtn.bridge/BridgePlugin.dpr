library BridgePlugin;

{ Native MTN2 plugin: connects external service processes (stdio, one JSON message per
  line) as providers of JSON-RPC services named bridge.<server>.<tool>. A server runs only
  after the user approved its command line in the plugin settings. }

uses
  System.SysUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uPluginServiceSettings in '..\..\Core\uPluginServiceSettings.pas',
  uBridgeProtocol in 'uBridgeProtocol.pas',
  uBridgeConfig in 'uBridgeConfig.pas',
  uBridgeServer in 'uBridgeServer.pas',
  uBridgePlugin in 'uBridgePlugin.pas';

const
  cPluginId = 'mtn.bridge';

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  Result := -1;
  try
    if RegisterBridge(AHostApi, cPluginId) then
      Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  StopBridge;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
