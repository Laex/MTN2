unit uPluginHost;

{ Process-wide facade for native plugin lifecycle. UI code talks to this
  unit instead of uPluginLoader / uPluginHostAbi / uWasmPluginHost directly. }

interface

uses
  System.SysUtils;

procedure StartPluginHost(const APluginsDir: string);
procedure StopPluginHost;
/// <summary>True when the mtn.7z plugin is installed but has no 7z.dll next to
/// it, so 7z / RAR / encrypted archives cannot be opened.</summary>
function HostSevenZipDllMissing: Boolean;
function HostLoadedPluginIds: TArray<string>;
/// <summary>Rows of the Plugins dialog, one per catalogued plugin: "[x]" when it
/// is switched on, "[ ]" when the user switched it off, then the manifest label.</summary>
function HostPluginRows: TArray<string>;
/// <summary>Switches the plugin of row AIndex (HostPluginRows order) on or off
/// and remembers the choice. Off unloads it now, on loads it now.</summary>
function HostTogglePlugin(AIndex: Integer): Boolean;
/// <summary>Lets the plugin of row AIndex replace the built-ins its manifest names
/// (or takes that back) and remembers it in plugins\overrides.json; the plugin
/// is reloaded at once. False for a plugin that asks for no replacement.</summary>
function HostTogglePluginOverride(AIndex: Integer): Boolean;
/// <summary>Runs the settings handler of the plugin of row AIndex: the plugin shows
/// its own settings dialog. False when it has none (or is not loaded).</summary>
function HostConfigurePlugin(AIndex: Integer): Boolean;
/// <summary>Id of the plugin of row AIndex, '' for a row that does not exist.</summary>
function HostPluginIdAt(AIndex: Integer): string;
/// <summary>Load the catalogued plugin that owns AScheme, if any.
/// No-op when that plugin is already loaded. Used from VFS resolve.</summary>
function HostEnsurePluginScheme(const AScheme: string): Boolean;
/// <summary>Load the catalogued plugin whose manifest lists this file's
/// archive extension. No-op when already loaded.</summary>
function HostEnsureArchiveExtension(const AFileName: string): Boolean;
/// <summary>Load every catalogued plugin so menu items and key rebinds
/// exist. Cheap after the first call.</summary>
procedure HostEnsureAllPlugins;
/// <summary>Display labels for the Loaded plugins dialog, parallel to
/// HostLoadedPluginIds. Each row is FormatPluginListLabel from
/// uPluginManifest (id, plugin.json name/version).</summary>
function HostPluginListDisplayLabels: TArray<string>;
function HostSetPluginSecret(const APluginId, AKey, AValue: string): Boolean;
function HostClearPluginSecret(const APluginId, AKey: string): Boolean;
function TryHostNavigateUri(APayload: TObject; out AUri: string): Boolean;
function TryHostNavigatePayload(APayload: TObject; out AUri: string;
  out AClear: Boolean): Boolean;
function BindHostInvalidate(AInvalidate: TProc): Int64;
procedure UnbindHostInvalidate(AWindowId: Int64);

implementation

uses
  System.JSON, System.IOUtils,
  uPluginLoader, uPluginHostAbi, uPluginManifest, uVfsRegistry, uConfigLocation, uPluginSettings;

const
  cDisabledPluginsFile = 'disabled-plugins.json';

var
  GPluginsDir: string;

procedure StartPluginHost(const APluginsDir: string);
var
  Allowed, Disabled: TArray<string>;
begin
  GPluginsDir := ExcludeTrailingPathDelimiter(APluginsDir);
  // Plugins the user trusts to replace built-in handlers; must be set
  // before cataloguing, which loads those plugins right away.
  TryReadOverrideAllowList(GPluginsDir, Allowed);
  TryReadDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), Disabled);
  PluginLoader.SetDisabledPlugins(Disabled);
  PluginLoader.SetOverrideAllowList(Allowed);
  // Catalog only. DLLs load on the first scheme/archive use, or when the
  // menu / plugin list needs the rest of the registrations.
  PluginLoader.CatalogPlugins(APluginsDir);
end;

function HostSevenZipDllMissing: Boolean;
var
  Dir: string;
begin
  Dir := TPath.Combine(GPluginsDir, 'mtn.7z');
  Result := (GPluginsDir <> '') and TDirectory.Exists(Dir) and
    not TFile.Exists(TPath.Combine(Dir, '7z.dll'));
end;

function HostEnsurePluginScheme(const AScheme: string): Boolean;
begin
  Result := PluginLoader.EnsureScheme(AScheme);
end;

function HostEnsureArchiveExtension(const AFileName: string): Boolean;
begin
  Result := PluginLoader.EnsureArchiveExtension(AFileName);
end;

procedure HostEnsureAllPlugins;
begin
  PluginLoader.EnsureAll;
end;

procedure StopPluginHost;
begin
  PluginLoader.UnloadAll;
  GPluginsDir := '';
end;

function HostLoadedPluginIds: TArray<string>;
begin
  Result := PluginLoader.LoadedPluginIds;
end;

function HostPluginRows: TArray<string>;
var
  Ids: TArray<string>;
  I: Integer;
  Dir, Mark: string;
  Over: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  SetLength(Result, Length(Ids));
  for I := 0 to High(Ids) do
  begin
    if PluginLoader.IsPluginDisabled(Ids[I]) then
      Mark := '[ ] '
    else
      Mark := '[x] ';
    if GPluginsDir <> '' then
      Dir := TPath.Combine(GPluginsDir, Ids[I])
    else
      Dir := '';
    Result[I] := Mark + PluginListDisplayLabel(Ids[I], Dir);
    if PluginSettings.HasConfigure(Ids[I]) then
      Result[I] := Result[I] + '  [settings]';
    Over := PluginLoader.PluginOverrides(Ids[I]);
    if Length(Over) > 0 then
    begin
      if PluginLoader.IsOverrideGranted(Ids[I]) then
        Mark := 'on'
      else
        Mark := 'off';
      Result[I] := Result[I] + '  [replaces ' + string.Join(' ', Over) + ': ' + Mark + ']';
    end;
  end;
end;

function HostTogglePlugin(AIndex: Integer): Boolean;
var
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  Result := PluginLoader.SetPluginEnabled(Ids[AIndex], PluginLoader.IsPluginDisabled(Ids[AIndex]));
  if Result then
    WriteDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), PluginLoader.DisabledPlugins);
end;

function HostTogglePluginOverride(AIndex: Integer): Boolean;
var
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  Result := PluginLoader.SetPluginOverrideAllowed(Ids[AIndex],
    not PluginLoader.IsOverrideGranted(Ids[AIndex]));
  if Result then
    WriteOverrideAllowList(GPluginsDir, PluginLoader.OverrideAllowList);
end;

function HostConfigurePlugin(AIndex: Integer): Boolean;
var
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  Result := PluginSettings.TryConfigure(Ids[AIndex]);
end;

function HostPluginIdAt(AIndex: Integer): string;
var
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Result := ''
  else
    Result := Ids[AIndex];
end;

function HostPluginListDisplayLabels: TArray<string>;
var
  Ids: TArray<string>;
  I: Integer;
  Dir: string;
begin
  Ids := HostLoadedPluginIds;
  SetLength(Result, Length(Ids));
  for I := 0 to High(Ids) do
  begin
    if GPluginsDir <> '' then
      Dir := TPath.Combine(GPluginsDir, Ids[I])
    else
      Dir := '';
    Result[I] := PluginListDisplayLabel(Ids[I], Dir);
  end;
end;

function HostSetPluginSecret(const APluginId, AKey, AValue: string): Boolean;
begin
  Result := PluginLoader.TrySetSecret(APluginId, AKey, AValue);
end;

function HostClearPluginSecret(const APluginId, AKey: string): Boolean;
begin
  Result := PluginLoader.TryClearSecret(APluginId, AKey);
end;

function TryHostNavigatePayload(APayload: TObject; out AUri: string;
  out AClear: Boolean): Boolean;
var
  P: TPluginPayload;
  V: TJSONValue;
  Field: TJSONValue;
begin
  Result := False;
  AUri := '';
  AClear := False;
  if not (APayload is TPluginPayload) then
    Exit;
  P := TPluginPayload(APayload);
  if Trim(P.Json) = '' then
    Exit;
  V := TJSONObject.ParseJSONValue(P.Json);
  if V = nil then
    Exit;
  try
    if V is TJSONObject then
    begin
      Field := TJSONObject(V).Values['uri'];
      if Field is TJSONString then
        AUri := TJSONString(Field).Value;
      Field := TJSONObject(V).Values['clear'];
      if Field is TJSONBool then
        AClear := TJSONBool(Field).AsBoolean;
    end;
    Result := AUri <> '';
  finally
    V.Free;
  end;
end;

function TryHostNavigateUri(APayload: TObject; out AUri: string): Boolean;
var
  Clear: Boolean;
begin
  Result := TryHostNavigatePayload(APayload, AUri, Clear);
end;

function BindHostInvalidate(AInvalidate: TProc): Int64;
begin
  Result := RegisterInvalidatableWindow(AInvalidate);
end;

procedure UnbindHostInvalidate(AWindowId: Int64);
begin
  UnregisterInvalidatableWindow(AWindowId);
end;

initialization
  SetVfsLazyLoad(HostEnsurePluginScheme, HostEnsureArchiveExtension);

end.
