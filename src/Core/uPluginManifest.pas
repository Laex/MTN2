unit uPluginManifest;

{ Optional plugins\<id>\plugin.json — host-side filter before LoadLibrary.
  Missing file is not an error (ABI is still checked via
  mtn_plugin_get_abi_version). A present file with abi ≠ cPluginAbiVersion
  skips the DLL. }

interface

uses
  System.SysUtils;

type
  TPluginManifest = record
    Id: string;
    Name: string;
    Version: string;
    AbiVersion: Int64;
    HasAbi: Boolean;
    /// <summary>Optional "archiveExtensions": ["7z","rar",...] — file name
    /// extensions this plugin's VFS scheme should navigate into on Enter
    /// (see uVfsRegistry.RegisterArchiveExtension / TArchiveExtensionKind).
    /// Empty for plugins that are not archive backends.</summary>
    ArchiveExtensions: TArray<string>;
  end;

function TryParsePluginManifestJson(const AJson: string;
  out AManifest: TPluginManifest): Boolean;
function TryReadPluginManifest(const APluginDir: string;
  out AManifest: TPluginManifest): Boolean;
/// <summary>ASCII-safe Loaded-plugins list row: padded id, name (or
/// "loaded"), version. No box-drawing or "?" placeholders.</summary>
function FormatPluginListLabel(const APluginId, AName, AVersion: string): string;
/// <summary>Reads plugins\&lt;id&gt;\plugin.json when present, then formats
/// via FormatPluginListLabel. Missing manifest still yields "id  loaded".</summary>
function PluginListDisplayLabel(const APluginId, APluginDir: string): string;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections;

procedure ClearManifest(out AManifest: TPluginManifest);
begin
  AManifest.Id := '';
  AManifest.Name := '';
  AManifest.Version := '';
  AManifest.AbiVersion := 0;
  AManifest.HasAbi := False;
  SetLength(AManifest.ArchiveExtensions, 0);
end;

function TryParsePluginManifestJson(const AJson: string;
  out AManifest: TPluginManifest): Boolean;
var
  Val: TJSONValue;
  Obj: TJSONObject;
  N: TJSONValue;
  Arr: TJSONArray;
  Exts: TArray<string>;
  I: Integer;
begin
  ClearManifest(AManifest);
  Result := False;
  if Trim(AJson) = '' then
    Exit;
  Val := TJSONObject.ParseJSONValue(AJson);
  if not (Val is TJSONObject) then
  begin
    Val.Free;
    Exit;
  end;
  Obj := TJSONObject(Val);
  try
    N := Obj.Values['id'];
    if N is TJSONString then
      AManifest.Id := TJSONString(N).Value;
    N := Obj.Values['name'];
    if N is TJSONString then
      AManifest.Name := TJSONString(N).Value;
    N := Obj.Values['version'];
    if N is TJSONString then
      AManifest.Version := TJSONString(N).Value;
    N := Obj.Values['abi'];
    if N is TJSONNumber then
    begin
      AManifest.AbiVersion := TJSONNumber(N).AsInt64;
      AManifest.HasAbi := True;
    end;
    N := Obj.Values['archiveExtensions'];
    if N is TJSONArray then
    begin
      Arr := TJSONArray(N);
      SetLength(Exts, 0);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONString then
        begin
          SetLength(Exts, Length(Exts) + 1);
          Exts[High(Exts)] := TJSONString(Arr.Items[I]).Value;
        end;
      AManifest.ArchiveExtensions := Exts;
    end;
    Result := AManifest.Id <> '';
  finally
    Obj.Free;
  end;
end;

function TryReadPluginManifest(const APluginDir: string;
  out AManifest: TPluginManifest): Boolean;
var
  Path, Json: string;
begin
  ClearManifest(AManifest);
  Result := False;
  if APluginDir = '' then
    Exit;
  Path := TPath.Combine(APluginDir, 'plugin.json');
  if not TFile.Exists(Path) then
    Exit;
  try
    Json := TFile.ReadAllText(Path, TEncoding.UTF8);
  except
    Exit;
  end;
  Result := TryParsePluginManifestJson(Json, AManifest);
end;

function FitCell(const S: string; AWidth: Integer): string;
begin
  if AWidth <= 0 then
    Exit('');
  if Length(S) >= AWidth then
    Result := Copy(S, 1, AWidth)
  else
    Result := S + StringOfChar(' ', AWidth - Length(S));
end;

function FormatPluginListLabel(const APluginId, AName, AVersion: string): string;
const
  cIdW = 16;
  cNameW = 28;
  cVerW = 10;
var
  Name: string;
begin
  if AName <> '' then
    Name := AName
  else
    Name := 'loaded';
  Result := FitCell(APluginId, cIdW) + ' ' + FitCell(Name, cNameW);
  if AVersion <> '' then
    Result := Result + ' ' + FitCell(AVersion, cVerW);
end;

function PluginListDisplayLabel(const APluginId, APluginDir: string): string;
var
  Man: TPluginManifest;
begin
  if TryReadPluginManifest(APluginDir, Man) then
    Result := FormatPluginListLabel(APluginId, Man.Name, Man.Version)
  else
    Result := FormatPluginListLabel(APluginId, '', '');
end;

end.
