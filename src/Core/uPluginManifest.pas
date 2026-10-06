unit uPluginManifest;

{ Optional plugins\<id>\plugin.json - host-side filter before LoadLibrary.
  Missing file is not an error (ABI is still checked via
  mtn_plugin_get_abi_version). A present file with abi <> cPluginAbiVersion
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
    /// <summary>Optional "archiveExtensions": ["7z","rar",...] - file name
    /// extensions this plugin's VFS scheme should navigate into on Enter
    /// (see uVfsRegistry.RegisterArchiveExtension / TArchiveExtensionKind).
    /// Empty for plugins that are not archive backends.</summary>
    ArchiveExtensions: TArray<string>;
    /// <summary>Optional "schemes": ["7z","tmp",...] - URI schemes this
    /// plugin registers in mtn_plugin_init. The host uses them to load the
    /// DLL the first time that scheme is resolved, instead of at startup.</summary>
    Schemes: TArray<string>;
    /// <summary>Optional "overrides": ["sftp", ".zip"] - built-in handlers
    /// this plugin asks to replace: a scheme, or a file name extension with
    /// the leading dot. Takes effect only when the user lists the plugin id
    /// in plugins\overrides.json (see TryReadOverrideAllowList). Reserved
    /// schemes (IsReservedVfsScheme) are never replaceable.</summary>
    Overrides: TArray<string>;
    /// <summary>Optional "startup": true - load the plugin when the host
    /// starts instead of on first use. Needed by a plugin whose work is
    /// hooks on built-in commands or command key chords, since nothing else
    /// would ever trigger its lazy load.</summary>
    Startup: Boolean;
    /// <summary>Optional "wasi": true - the WASM module is built for WASI (a Go or
    /// Rust runtime). The host gives it an empty WASI preview1: no files, no
    /// environment, no arguments, and a larger memory limit. Ignored for a
    /// native DLL.</summary>
    Wasi: Boolean;
    /// <summary>Optional "keepLoaded": true - the native DLL stays mapped after
    /// the plugin is unloaded or switched off (its registrations are removed and
    /// mtn_plugin_shutdown runs, FreeLibrary does not). Needed by a DLL that
    /// carries a runtime which cannot be torn down, such as Go's.</summary>
    KeepLoaded: Boolean;
    /// <summary>Optional "description": one line of what the plugin does, as a
    /// string or as an object per language ({"en": "...", "ru": "..."}). Shown in
    /// the plugin's information dialog. DescriptionLocales / DescriptionTexts are
    /// parallel; a plain string is stored under the locale ''.</summary>
    DescriptionLocales: TArray<string>;
    DescriptionTexts: TArray<string>;
    /// <summary>Optional "author" and "homepage" (shown as given).</summary>
    Author: string;
    Homepage: string;
    /// <summary>Optional "help": file name of a Markdown page in the plugin's
    /// folder ("help.md"). For the language "ru" the host looks for
    /// "help.ru.md" first, then the name as given.</summary>
    Help: string;
    /// <summary>Optional "permissions": ["vfs.read"] - what the plugin asks the
    /// user to allow (see uPluginPermissions). Names are lower-cased; unknown
    /// ones are kept here and ignored by the permission check.</summary>
    Permissions: TArray<string>;
  end;

function TryParsePluginManifestJson(const AJson: string;
  out AManifest: TPluginManifest): Boolean;
/// <summary>Reads plugins\overrides.json: {"allow": ["plugin-id", ...]} - the
/// plugins the user trusts to replace built-in handlers. Missing or invalid
/// file gives an empty list (no plugin may override).</summary>
function TryReadOverrideAllowList(const APluginsDir: string;
  out AIds: TArray<string>): Boolean;
/// <summary>The description in ALocale ("ru"), else English, else the plain
/// string, else the first one given; '' when the manifest has none.</summary>
function ManifestDescription(const AManifest: TPluginManifest; const ALocale: string): string;
/// <summary>Full path of the plugin's help page for ALocale, or '' when the
/// manifest names none or the file is missing. APluginDir is the plugin's folder.</summary>
function ManifestHelpFile(const AManifest: TPluginManifest; const APluginDir,
  ALocale: string): string;
/// <summary>Writes plugins\overrides.json; an empty list removes the file.</summary>
procedure WriteOverrideAllowList(const APluginsDir: string; const AIds: TArray<string>);
/// <summary>Reads the file with the plugins the user switched off:
/// {"disabled": ["plugin-id", ...]}. Missing or invalid file gives an empty list.</summary>
function TryReadDisabledPlugins(const AFileName: string;
  out AIds: TArray<string>): Boolean;
/// <summary>Reads the plugin load order the user set: plugin ids, first loaded first.
/// False when the file is missing or malformed.</summary>
function TryReadPluginOrder(const AFileName: string; out AIds: TArray<string>): Boolean;
/// <summary>Writes the load order file; an empty list removes it.</summary>
procedure WritePluginOrder(const AFileName: string; const AIds: TArray<string>);
/// <summary>Writes the disabled-plugins file; an empty list removes it.</summary>
procedure WriteDisabledPlugins(const AFileName: string; const AIds: TArray<string>);
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
  SetLength(AManifest.Schemes, 0);
  SetLength(AManifest.Overrides, 0);
  AManifest.Startup := False;
  AManifest.Wasi := False;
  AManifest.KeepLoaded := False;
  SetLength(AManifest.DescriptionLocales, 0);
  SetLength(AManifest.DescriptionTexts, 0);
  AManifest.Author := '';
  AManifest.Homepage := '';
  AManifest.Help := '';
  SetLength(AManifest.Permissions, 0);
end;

function ReadTrimmedStrings(AValue: TJSONValue; ALower: Boolean): TArray<string>;
var
  Arr: TJSONArray;
  I: Integer;
  S: string;
begin
  SetLength(Result, 0);
  if not (AValue is TJSONArray) then
    Exit;
  Arr := TJSONArray(AValue);
  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONString then
    begin
      S := Trim(TJSONString(Arr.Items[I]).Value);
      if ALower then
        S := LowerCase(S);
      if S = '' then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
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
  Pair: TJSONPair;
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
    N := Obj.Values['schemes'];
    if N is TJSONArray then
    begin
      Arr := TJSONArray(N);
      SetLength(Exts, 0);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONString then
        begin
          SetLength(Exts, Length(Exts) + 1);
          Exts[High(Exts)] := LowerCase(Trim(TJSONString(Arr.Items[I]).Value));
        end;
      AManifest.Schemes := Exts;
    end;
    AManifest.Overrides := ReadTrimmedStrings(Obj.Values['overrides'], True);
    N := Obj.Values['startup'];
    AManifest.Startup := (N is TJSONBool) and TJSONBool(N).AsBoolean;
    N := Obj.Values['wasi'];
    AManifest.Wasi := (N is TJSONBool) and TJSONBool(N).AsBoolean;
    N := Obj.Values['keepLoaded'];
    AManifest.KeepLoaded := (N is TJSONBool) and TJSONBool(N).AsBoolean;
    N := Obj.Values['description'];
    if N is TJSONString then
    begin
      SetLength(AManifest.DescriptionLocales, 1);
      SetLength(AManifest.DescriptionTexts, 1);
      AManifest.DescriptionLocales[0] := '';
      AManifest.DescriptionTexts[0] := Trim(TJSONString(N).Value);
    end
    else if N is TJSONObject then
      for Pair in TJSONObject(N) do
        if Pair.JsonValue is TJSONString then
        begin
          SetLength(AManifest.DescriptionLocales, Length(AManifest.DescriptionLocales) + 1);
          SetLength(AManifest.DescriptionTexts, Length(AManifest.DescriptionTexts) + 1);
          AManifest.DescriptionLocales[High(AManifest.DescriptionLocales)] :=
            LowerCase(Trim(Pair.JsonString.Value));
          AManifest.DescriptionTexts[High(AManifest.DescriptionTexts)] :=
            Trim(TJSONString(Pair.JsonValue).Value);
        end;
    N := Obj.Values['author'];
    if N is TJSONString then
      AManifest.Author := Trim(TJSONString(N).Value);
    N := Obj.Values['homepage'];
    if N is TJSONString then
      AManifest.Homepage := Trim(TJSONString(N).Value);
    N := Obj.Values['help'];
    if N is TJSONString then
      AManifest.Help := Trim(TJSONString(N).Value);
    AManifest.Permissions := ReadTrimmedStrings(Obj.Values['permissions'], True);
    Result := AManifest.Id <> '';
  finally
    Obj.Free;
  end;
end;

function TryReadOverrideAllowList(const APluginsDir: string;
  out AIds: TArray<string>): Boolean;
var
  Path, Json: string;
  Val: TJSONValue;
begin
  SetLength(AIds, 0);
  Result := False;
  if APluginsDir = '' then
    Exit;
  Path := TPath.Combine(APluginsDir, 'overrides.json');
  if not TFile.Exists(Path) then
    Exit;
  try
    Json := TFile.ReadAllText(Path, TEncoding.UTF8);
  except
    Exit;
  end;
  Val := TJSONObject.ParseJSONValue(Json);
  try
    if Val is TJSONObject then
    begin
      AIds := ReadTrimmedStrings(TJSONObject(Val).Values['allow'], False);
      Result := True;
    end;
  finally
    Val.Free;
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

function ManifestDescription(const AManifest: TPluginManifest; const ALocale: string): string;
var
  I: Integer;

  function Find(const ALoc: string): string;
  var
    J: Integer;
  begin
    for J := 0 to High(AManifest.DescriptionLocales) do
      if AManifest.DescriptionLocales[J] = ALoc then
        Exit(AManifest.DescriptionTexts[J]);
    Result := '';
  end;

begin
  Result := Find(LowerCase(Trim(ALocale)));
  if Result = '' then
    Result := Find('en');
  if Result = '' then
    Result := Find('');
  if Result = '' then
    for I := 0 to High(AManifest.DescriptionTexts) do
      if AManifest.DescriptionTexts[I] <> '' then
        Exit(AManifest.DescriptionTexts[I]);
end;

function ManifestHelpFile(const AManifest: TPluginManifest; const APluginDir,
  ALocale: string): string;
var
  Name, Localized: string;
begin
  Result := '';
  Name := Trim(AManifest.Help);
  // A plugin cannot point the host at a file outside its own folder.
  if (Name = '') or (APluginDir = '') or (Name <> ExtractFileName(Name)) then
    Exit;
  if Trim(ALocale) <> '' then
  begin
    Localized := TPath.Combine(APluginDir, ChangeFileExt(Name, '') + '.' +
      LowerCase(Trim(ALocale)) + ExtractFileExt(Name));
    if TFile.Exists(Localized) then
      Exit(Localized);
  end;
  if TFile.Exists(TPath.Combine(APluginDir, Name)) then
    Result := TPath.Combine(APluginDir, Name);
end;

procedure WriteOverrideAllowList(const APluginsDir: string; const AIds: TArray<string>);
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Id: string;
  Path: string;
begin
  if APluginsDir = '' then
    Exit;
  Path := TPath.Combine(APluginsDir, 'overrides.json');
  try
    if Length(AIds) = 0 then
    begin
      if TFile.Exists(Path) then
        TFile.Delete(Path);
      Exit;
    end;
    Root := TJSONObject.Create;
    try
      Arr := TJSONArray.Create;
      for Id in AIds do
        Arr.Add(Id);
      Root.AddPair('allow', Arr);
      TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  except
    // A plugins folder that cannot be written leaves the choice for this run only.
  end;
end;

function TryReadPluginOrder(const AFileName: string; out AIds: TArray<string>): Boolean;
var
  Val: TJSONValue;
begin
  SetLength(AIds, 0);
  Result := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if Val is TJSONObject then
    begin
      AIds := ReadTrimmedStrings(TJSONObject(Val).Values['order'], False);
      Result := True;
    end;
  finally
    Val.Free;
  end;
end;

procedure WritePluginOrder(const AFileName: string; const AIds: TArray<string>);
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Id: string;
begin
  if AFileName = '' then
    Exit;
  try
    if Length(AIds) = 0 then
    begin
      if TFile.Exists(AFileName) then
        TFile.Delete(AFileName);
      Exit;
    end;
    Root := TJSONObject.Create;
    try
      Arr := TJSONArray.Create;
      for Id in AIds do
        Arr.Add(Id);
      Root.AddPair('order', Arr);
      TDirectory.CreateDirectory(ExtractFilePath(AFileName));
      TFile.WriteAllText(AFileName, Root.ToJSON, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  except
    // A settings file that cannot be written leaves the order for this run only.
  end;
end;

function TryReadDisabledPlugins(const AFileName: string;
  out AIds: TArray<string>): Boolean;
var
  Val: TJSONValue;
begin
  SetLength(AIds, 0);
  Result := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if Val is TJSONObject then
    begin
      AIds := ReadTrimmedStrings(TJSONObject(Val).Values['disabled'], False);
      Result := True;
    end;
  finally
    Val.Free;
  end;
end;

procedure WriteDisabledPlugins(const AFileName: string; const AIds: TArray<string>);
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Id: string;
begin
  if AFileName = '' then
    Exit;
  try
    if Length(AIds) = 0 then
    begin
      if TFile.Exists(AFileName) then
        TFile.Delete(AFileName);
      Exit;
    end;
    Root := TJSONObject.Create;
    try
      Arr := TJSONArray.Create;
      for Id in AIds do
        Arr.Add(Id);
      Root.AddPair('disabled', Arr);
      TDirectory.CreateDirectory(ExtractFilePath(AFileName));
      TFile.WriteAllText(AFileName, Root.ToJSON, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  except
    // A settings file that cannot be written leaves the choice for this run only.
  end;
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
