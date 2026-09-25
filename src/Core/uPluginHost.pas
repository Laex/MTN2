unit uPluginHost;

{ Process-wide facade for native plugin lifecycle. UI code talks to this
  unit instead of uPluginLoader / uPluginHostAbi / uWasmPluginHost directly. }

interface

uses
  System.SysUtils;

procedure StartPluginHost(const APluginsDir: string);
procedure StopPluginHost;
function HostLoadedPluginIds: TArray<string>;
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
  uPluginLoader, uPluginHostAbi, uPluginManifest;

var
  GPluginsDir: string;

procedure StartPluginHost(const APluginsDir: string);
begin
  GPluginsDir := ExcludeTrailingPathDelimiter(APluginsDir);
  PluginLoader.LoadPluginsFrom(APluginsDir);
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

end.
