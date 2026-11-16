library RipgrepPlugin;

{ Native MTN2 plugin: serves the text search of Alt+F7 (the search.files service) with
  ripgrep. Without rg the service answers "not supported" and the built-in search runs. }

uses
  System.SysUtils,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uRipgrepFormat in 'uRipgrepFormat.pas',
  uRipgrepService in 'uRipgrepService.pas';

const
  cPluginId = 'mtn.ripgrep';

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  Result := -1;
  try
    if RegisterRipgrepService(AHostApi, cPluginId) then
      Result := 0;
  except
    Result := -1;
  end;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  StopRipgrepService;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
