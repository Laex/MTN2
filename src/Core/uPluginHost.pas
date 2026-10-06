unit uPluginHost;

{ Process-wide facade for native plugin lifecycle. UI code talks to this
  unit instead of uPluginLoader / uPluginHostAbi / uWasmPluginHost directly. }

interface

uses
  System.SysUtils, uPluginInfo;

procedure StartPluginHost(const APluginsDir: string);
procedure StopPluginHost;
/// <summary>True when the mtn.7z plugin is installed but has no 7z.dll next to
/// it, so 7z / RAR / encrypted archives cannot be opened.</summary>
function HostSevenZipDllMissing: Boolean;
/// <summary>True when there are plugins and every one of them is switched off.</summary>
function HostAllPluginsOff: Boolean;
function HostLoadedPluginIds: TArray<string>;
/// <summary>Rows of the Plugins dialog, one per catalogued plugin: "[x]" when it
/// is switched on, "[ ]" when the user switched it off, then the manifest label.</summary>
function HostPluginRows: TArray<string>;
/// <summary>Starts a round of choices in the Plugins dialog: switching plugins on and
/// off (HostTogglePlugin) only marks them until HostPluginsCommit.</summary>
procedure HostPluginsBegin;
/// <summary>Switches the plugin of row AIndex (HostPluginRows order) on or off in the
/// pending choices; nothing happens to the plugin until HostPluginsCommit.</summary>
function HostTogglePlugin(AIndex: Integer): Boolean;
/// <summary>Applies the pending choices: a plugin switched off is unloaded now, one
/// switched on is loaded now, and the choice is remembered. Drops the pending state.</summary>
procedure HostPluginsCommit;
/// <summary>Drops the pending choices.</summary>
procedure HostPluginsCancel;
/// <summary>What the plugin of row AIndex may be allowed: the built-ins its manifest asks
/// to replace (AOverrides, AOverrideOn tells whether the user allowed it) and the
/// permissions it names (APermissions, AGranted parallel). False for a missing row.</summary>
function HostPluginPermissions(AIndex: Integer; out AName: string;
  out AOverrides: TArray<string>; out AOverrideOn: Boolean;
  out APermissions: TArray<string>; out AGranted: TArray<Boolean>): Boolean;
/// <summary>Stores the user's answer from the permissions dialog (AGranted parallel to
/// the APermissions HostPluginPermissions returned). Allowing or taking back the
/// replacement reloads the plugin at once; both are remembered.</summary>
procedure HostApplyPluginPermissions(AIndex: Integer; AOverrideOn: Boolean;
  const AGranted: TArray<Boolean>);
/// <summary>Moves the plugin of row AIndex ADelta places up (negative) or down in
/// the load order and remembers it (plugin-order.json in the settings folder).
/// Plugins loaded later follow the new order; the ones already loaded keep theirs
/// until the next start. False when the row or the target place does not exist.</summary>
function HostMovePlugin(AIndex, ADelta: Integer): Boolean;
/// <summary>Runs the settings handler of the plugin of row AIndex: the plugin shows
/// its own settings dialog. False when it has none (or is not loaded).</summary>
function HostConfigurePlugin(AIndex: Integer): Boolean;
/// <summary>What the plugin of row AIndex says about itself (manifest) and what the
/// host saw it register. False for a row that does not exist.</summary>
function HostPluginInfo(AIndex: Integer; out AInfo: TPluginInfo): Boolean;
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
  System.JSON, System.IOUtils, System.Math,
  uPluginLoader, uPluginHostAbi, uPluginManifest, uPluginPermissions, uVfsRegistry,
  uConfigLocation, uPluginSettings;

const
  cDisabledPluginsFile = 'disabled-plugins.json';
  cPluginOrderFile = 'plugin-order.json';
  cPermissionsFile = 'plugin-permissions.json';
  cSessionFile = 'session.json';

var
  GPluginsDir: string;
  GPendingActive: Boolean;
  // Ids switched off in the pending choices.
  GPendingDisabled: TArray<string>;

function PendingIsOff(const AId: string): Boolean;
var
  S: string;
begin
  for S in GPendingDisabled do
    if SameText(S, AId) then
      Exit(True);
  Result := False;
end;

function PluginShownOff(const AId: string): Boolean;
begin
  if GPendingActive then
    Result := PendingIsOff(AId)
  else
    Result := PluginLoader.IsPluginDisabled(AId);
end;

/// <summary>True on the first run: neither the list of switched-off plugins nor the
/// session file exists in the settings folder, so the program has never been used
/// with these settings.</summary>
function IsFirstPluginRun: Boolean;
begin
  Result := not TFile.Exists(GetConfigFilePath(cDisabledPluginsFile)) and
    not TFile.Exists(GetConfigFilePath(cSessionFile));
end;

procedure StartPluginHost(const APluginsDir: string);
var
  Allowed, Disabled, Order: TArray<string>;
  Dir: string;
begin
  GPluginsDir := ExcludeTrailingPathDelimiter(APluginsDir);
  // Plugins the user trusts to replace built-in handlers; must be set
  // before cataloguing, which loads those plugins right away.
  TryReadOverrideAllowList(GPluginsDir, Allowed);
  // A fresh install starts with every plugin switched off; the user turns on the
  // ones wanted in Options - Plugins. The list is written at once, so it is the
  // marker that the next start is not a first run.
  if IsFirstPluginRun then
  begin
    SetLength(Disabled, 0);
    if TDirectory.Exists(GPluginsDir) then
      for Dir in TDirectory.GetDirectories(GPluginsDir, '*', TSearchOption.soTopDirectoryOnly) do
        Disabled := Disabled + [TPath.GetFileName(Dir)];
    WriteDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), Disabled);
  end
  else
    TryReadDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), Disabled);
  PluginLoader.SetDisabledPlugins(Disabled);
  TryReadPluginOrder(GetConfigFilePath(cPluginOrderFile), Order);
  PluginLoader.SetPluginOrder(Order);
  PluginLoader.SetOverrideAllowList(Allowed);
  LoadPermissionGrants(GetConfigFilePath(cPermissionsFile));
  // Catalog only. DLLs load on the first scheme/archive use, or when the
  // menu / plugin list needs the rest of the registrations.
  PluginLoader.CatalogPlugins(APluginsDir);
end;

function HostSevenZipDllMissing: Boolean;
var
  Dir: string;
begin
  Dir := TPath.Combine(GPluginsDir, 'mtn.7z');
  // A switched-off plugin needs no 7z.dll.
  Result := (GPluginsDir <> '') and TDirectory.Exists(Dir) and
    not TFile.Exists(TPath.Combine(Dir, '7z.dll')) and
    not PluginLoader.IsPluginDisabled('mtn.7z');
end;

function HostAllPluginsOff: Boolean;
var
  Id: string;
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  Result := Length(Ids) > 0;
  for Id in Ids do
    if not PluginLoader.IsPluginDisabled(Id) then
      Exit(False);
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
  Over, Needs: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  SetLength(Result, Length(Ids));
  for I := 0 to High(Ids) do
  begin
    if PluginShownOff(Ids[I]) then
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
    Needs := PluginPermissionsDeclared(Ids[I]);
    if Length(Needs) > 0 then
    begin
      if PluginPermissionsAllGranted(Ids[I]) then
        Mark := 'on'
      else
        Mark := 'off';
      Result[I] := Result[I] + '  [needs ' + string.Join(' ', Needs) + ': ' + Mark + ']';
    end;
  end;
end;

procedure HostPluginsBegin;
begin
  GPendingActive := True;
  GPendingDisabled := PluginLoader.DisabledPlugins;
end;

function HostTogglePlugin(AIndex: Integer): Boolean;
var
  Ids: TArray<string>;
  Id: string;
  I: Integer;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  if not GPendingActive then
    HostPluginsBegin;
  Id := Ids[AIndex];
  if PendingIsOff(Id) then
  begin
    for I := High(GPendingDisabled) downto 0 do
      if SameText(GPendingDisabled[I], Id) then
        Delete(GPendingDisabled, I, 1);
  end
  else
    GPendingDisabled := GPendingDisabled + [Id];
  Result := True;
end;

procedure HostPluginsCommit;
var
  Id: string;
  Changed: Boolean;
begin
  if not GPendingActive then
    Exit;
  GPendingActive := False;
  Changed := False;
  for Id in PluginLoader.CatalogPluginIds do
    if PendingIsOff(Id) <> PluginLoader.IsPluginDisabled(Id) then
    begin
      PluginLoader.SetPluginEnabled(Id, PluginLoader.IsPluginDisabled(Id));
      Changed := True;
    end;
  if Changed then
    WriteDisabledPlugins(GetConfigFilePath(cDisabledPluginsFile), PluginLoader.DisabledPlugins);
  SetLength(GPendingDisabled, 0);
end;

procedure HostPluginsCancel;
begin
  GPendingActive := False;
  SetLength(GPendingDisabled, 0);
end;

function HostMovePlugin(AIndex, ADelta: Integer): Boolean;
var
  Ids: TArray<string>;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  Result := PluginLoader.MovePlugin(Ids[AIndex], ADelta);
  if Result then
    WritePluginOrder(GetConfigFilePath(cPluginOrderFile), PluginLoader.CatalogPluginIds);
end;

function HostPluginPermissions(AIndex: Integer; out AName: string;
  out AOverrides: TArray<string>; out AOverrideOn: Boolean;
  out APermissions: TArray<string>; out AGranted: TArray<Boolean>): Boolean;
var
  Ids: TArray<string>;
  I: Integer;
begin
  Ids := PluginLoader.CatalogPluginIds;
  AName := '';
  SetLength(AOverrides, 0);
  AOverrideOn := False;
  SetLength(APermissions, 0);
  SetLength(AGranted, 0);
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  AName := Ids[AIndex];
  AOverrides := PluginLoader.PluginOverrides(AName);
  AOverrideOn := PluginLoader.IsOverrideGranted(AName);
  APermissions := PluginPermissionsDeclared(AName);
  SetLength(AGranted, Length(APermissions));
  for I := 0 to High(APermissions) do
    AGranted[I] := PluginPermissionGranted(AName, APermissions[I]);
  Result := True;
end;

procedure HostApplyPluginPermissions(AIndex: Integer; AOverrideOn: Boolean;
  const AGranted: TArray<Boolean>);
var
  Ids: TArray<string>;
  Perms: TArray<string>;
  I: Integer;
begin
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit;
  Perms := PluginPermissionsDeclared(Ids[AIndex]);
  for I := 0 to Min(High(Perms), High(AGranted)) do
    PluginPermissionGrant(Ids[AIndex], Perms[I], AGranted[I]);
  SavePermissionGrants(GetConfigFilePath(cPermissionsFile));
  if (Length(PluginLoader.PluginOverrides(Ids[AIndex])) > 0) and
     (PluginLoader.IsOverrideGranted(Ids[AIndex]) <> AOverrideOn) then
  begin
    PluginLoader.SetPluginOverrideAllowed(Ids[AIndex], AOverrideOn);
    WriteOverrideAllowList(GPluginsDir, PluginLoader.OverrideAllowList);
  end;
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

function HostPluginInfo(AIndex: Integer; out AInfo: TPluginInfo): Boolean;
var
  Ids: TArray<string>;
begin
  AInfo := Default(TPluginInfo);
  Ids := PluginLoader.CatalogPluginIds;
  if (AIndex < 0) or (AIndex > High(Ids)) then
    Exit(False);
  AInfo := BuildPluginInfo(Ids[AIndex], TPath.Combine(GPluginsDir, Ids[AIndex]));
  Result := True;
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
