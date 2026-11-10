unit uPluginManifest;

{ Optional plugins\<id>\plugin.json - host-side filter before LoadLibrary.
  Missing file is not an error (ABI is still checked via
  mtn_plugin_get_abi_version). A present file with abi <> cPluginAbiVersion
  skips the DLL. }

interface

uses
  System.SysUtils;

type
  /// <summary>"when" of a declared entry: the entry exists only where every given
  /// condition holds. Os: "windows", "linux" or "macos" (any of the listed); Exe: a
  /// program found on PATH; FileName: an existing file or folder; Env: an environment
  /// variable that is not empty. An empty condition always holds.</summary>
  TManifestCondition = record
    Os: TArray<string>;
    Exe: string;
    FileName: string;
    Env: string;
  end;

  /// <summary>A command the plugin declares: its id, the key chord bound to it ('' for
  /// none) and the label the command palette and the function bar show until the
  /// plugin is loaded.</summary>
  TManifestCommand = record
    Id: string;
    Key: string;
    LabelLocales: TArray<string>;
    LabelTexts: TArray<string>;
    When: TManifestCondition;
  end;

  /// <summary>A menu item the plugin declares, in the Plugins menu unless Parent names
  /// another menu path.</summary>
  TManifestMenuItem = record
    Id: string;
    Parent: string;
    CaptionLocales: TArray<string>;
    CaptionTexts: TArray<string>;
    Priority: Integer;
    When: TManifestCondition;
  end;

  /// <summary>An item of the Change Drive list the plugin declares.</summary>
  TManifestDriveItem = record
    Id: string;
    CaptionLocales: TArray<string>;
    CaptionTexts: TArray<string>;
    Uri: string;
    Priority: Integer;
    When: TManifestCondition;
  end;

  /// <summary>An event that loads an unloaded plugin; see ActivateOn.</summary>
  TManifestTrigger = record
    Event: string;
    DirHas: string;
  end;

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
    /// <summary>Optional "highlightExtensions": ["rs", "makefile", ...] - the file
    /// extensions and whole file names the plugin colors (lower case, no dot). The host
    /// loads the plugin the first time the viewer or the editor opens such a file,
    /// so a plugin that only colors text needs no "startup". The list must match what
    /// the plugin registers; the host reports a difference in the plugin's information.</summary>
    HighlightExtensions: TArray<string>;
    /// <summary>Optional "declarative": true - everything the plugin registers for the
    /// menu, the command palette and key chords is listed in "commands" and "menuItems".
    /// The host builds those from the manifest and loads the plugin when one is used,
    /// so it needs no "startup". At load the plugin's own registrations are checked
    /// against the lists: one that is not declared is refused, one that is declared and
    /// not registered is dropped, and the plugin's information dialog says so.</summary>
    Declarative: Boolean;
    /// <summary>Optional "commands": [{"id": "x.run", "key": "Ctrl+Alt+J", "label": ...}];
    /// "label" is a string or an object per language like "description".</summary>
    Commands: TArray<TManifestCommand>;
    /// <summary>Optional "menuItems": [{"id": "x.run", "caption": ..., "priority": 50}].</summary>
    MenuItems: TArray<TManifestMenuItem>;
    /// <summary>Optional "driveItems": [{"id": "x", "caption": ..., "uri": "x:///", "priority": 60}].</summary>
    DriveItems: TArray<TManifestDriveItem>;
    /// <summary>Optional "documentExtensions": ["csv", "tsv"] - the file extensions the
    /// plugin registers a document provider for (lower case, no dot). The host loads the
    /// plugin the first time a file with such an extension is opened in the viewer, the
    /// editor or Quick View.</summary>
    DocumentExtensions: TArray<string>;
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
    /// <summary>Optional "startupWhen": a condition (the same keys as "when"); with
    /// "startup" the plugin loads at start only while it holds, for example while
    /// the folder of the user's macros has files. Without it "startup" is
    /// unconditional.</summary>
    StartupWhen: TManifestCondition;
    HasStartupWhen: Boolean;
    /// <summary>Optional "activateOn": events that load the plugin when it is still
    /// unloaded, for a plugin that works on what the panels show: [{"event":
    /// "panel.dir", "dirHas": ".git"}] loads it once a panel enters a local folder
    /// that has an entry of that name in it or in a parent folder.</summary>
    ActivateOn: TArray<TManifestTrigger>;
    /// <summary>Optional "openRegistrations": true - with "declarative", the plugin may
    /// also register commands, keys, menu items and drive entries the manifest does not
    /// list (macros, for example). The listed ones still exist before the load.</summary>
    OpenRegistrations: Boolean;
    /// <summary>Optional "wasi": true - the WASM module is built for WASI (a Go or
    /// Rust runtime). The host gives it an empty WASI preview1: no files, no
    /// environment, no arguments, and a larger memory limit. Ignored for a
    /// native DLL.</summary>
    Wasi: Boolean;
    /// <summary>Optional "memoryMib": N - memory limit of a WASM module that is not built for
    /// WASI, in MiB (at most 256). 0 = the small default; a module that carries big tables (a
    /// syntax library) asks for more.</summary>
    MemoryMib: Integer;
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
    /// <summary>Optional "help": file name of a Markdown page ("help.md"). The
    /// host looks for it in the plugin's resource\<locale>\help\ for the
    /// current language, then in resource\en\help\.</summary>
    Help: string;
    /// <summary>Optional "resources": the revision of the plugin's key set and
    /// pack layout, compared with the "version" in each
    /// resource\<locale>\locale.json (see uStrings.TStringPack). 0 = the plugin
    /// declares none and any pack is accepted.</summary>
    ResourceVersion: Integer;
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
/// <summary>True when every condition of ACondition holds on the running system.</summary>
function ManifestConditionHolds(const ACondition: TManifestCondition): Boolean;
/// <summary>"windows", "linux" or "macos".</summary>
function CurrentOsName: string;
/// <summary>The label / caption in ALocale of a declared command or menu item.</summary>
function LocalizedText(const ALocales, ATexts: TArray<string>; const ALocale: string): string;
/// <summary><APluginDir>\resource\<ALocale>: the plugin's pack for one language
/// (locale.json, strings.json, help\).</summary>
function PluginResourceDir(const APluginDir, ALocale: string): string;
/// <summary>Full path of the plugin's help page for ALocale, falling back to
/// English, or '' when the manifest names none or no file exists.
/// APluginDir is the plugin's folder.</summary>
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
  System.IOUtils, System.JSON, System.Math, System.Generics.Collections, uConfigLocation;

procedure ClearManifest(out AManifest: TPluginManifest);
begin
  AManifest.Id := '';
  AManifest.Name := '';
  AManifest.Version := '';
  AManifest.AbiVersion := 0;
  AManifest.HasAbi := False;
  SetLength(AManifest.ArchiveExtensions, 0);
  SetLength(AManifest.Schemes, 0);
  SetLength(AManifest.HighlightExtensions, 0);
  AManifest.Declarative := False;
  SetLength(AManifest.Commands, 0);
  SetLength(AManifest.MenuItems, 0);
  SetLength(AManifest.DriveItems, 0);
  SetLength(AManifest.DocumentExtensions, 0);
  SetLength(AManifest.Overrides, 0);
  AManifest.Startup := False;
  AManifest.StartupWhen := Default(TManifestCondition);
  AManifest.HasStartupWhen := False;
  AManifest.ActivateOn := nil;
  AManifest.OpenRegistrations := False;
  AManifest.Wasi := False;
  AManifest.MemoryMib := 0;
  AManifest.KeepLoaded := False;
  SetLength(AManifest.DescriptionLocales, 0);
  SetLength(AManifest.DescriptionTexts, 0);
  AManifest.Author := '';
  AManifest.Homepage := '';
  AManifest.Help := '';
  AManifest.ResourceVersion := 0;
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

/// <summary>Text in ALocale from a "label"/"caption" value: a string, or an object per
/// language; falls back to English, then to the first entry.</summary>
function LocalizedText(const ALocales, ATexts: TArray<string>; const ALocale: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ALocales) do
    if SameText(ALocales[I], ALocale) then
      Exit(ATexts[I]);
  for I := 0 to High(ALocales) do
    if SameText(ALocales[I], 'en') or (ALocales[I] = '') then
      Exit(ATexts[I]);
  if Length(ATexts) > 0 then
    Result := ATexts[0];
end;

function CurrentOsName: string;
begin
{$IF Defined(MSWINDOWS)}
  Result := 'windows';
{$ELSEIF Defined(MACOS)}
  Result := 'macos';
{$ELSE}
  Result := 'linux';
{$ENDIF}
end;

function ExecutableOnPath(const AName: string): Boolean;
var
  Dir, Ext: string;
  Exts: TArray<string>;
begin
{$IFDEF MSWINDOWS}
  Exts := ['', '.exe', '.cmd', '.bat', '.com'];
{$ELSE}
  Exts := [''];
{$ENDIF}
  for Dir in GetEnvironmentVariable('PATH').Split([TPath.PathSeparator]) do
    if Dir <> '' then
      for Ext in Exts do
        if TFile.Exists(TPath.Combine(Dir, AName + Ext)) then
          Exit(True);
  Result := False;
end;

function ConditionFileExists(const AName: string): Boolean;
var
  Path: string;
begin
  Path := StringReplace(AName, '%config%', GetConfigDirectory, [rfIgnoreCase]);
  Path := StringReplace(StringReplace(Path, '\', PathDelim, [rfReplaceAll]), '/', PathDelim, [rfReplaceAll]);
  if (Pos('*', ExtractFileName(Path)) = 0) and (Pos('?', ExtractFileName(Path)) = 0) then
    Exit(TFile.Exists(Path) or TDirectory.Exists(Path));
  Result := TDirectory.Exists(ExtractFilePath(Path)) and
    (Length(TDirectory.GetFiles(ExtractFilePath(Path), ExtractFileName(Path))) > 0);
end;

function ManifestConditionHolds(const ACondition: TManifestCondition): Boolean;
var
  S: string;
  Found: Boolean;
begin
  Result := False;
  if Length(ACondition.Os) > 0 then
  begin
    Found := False;
    for S in ACondition.Os do
      if S = CurrentOsName then
        Found := True;
    if not Found then
      Exit;
  end;
  if (ACondition.Exe <> '') and not ExecutableOnPath(ACondition.Exe) then
    Exit;
  if (ACondition.FileName <> '') and not ConditionFileExists(ACondition.FileName) then
    Exit;
  if (ACondition.Env <> '') and (GetEnvironmentVariable(ACondition.Env) = '') then
    Exit;
  Result := True;
end;

function ReadCondition(AValue: TJSONValue): TManifestCondition;
var
  N: TJSONValue;
begin
  Result := Default(TManifestCondition);
  if not (AValue is TJSONObject) then
    Exit;
  N := TJSONObject(AValue).Values['os'];
  if N is TJSONString then
    Result.Os := [LowerCase(Trim(TJSONString(N).Value))]
  else
    Result.Os := ReadTrimmedStrings(N, True);
  N := TJSONObject(AValue).Values['exe'];
  if N is TJSONString then
    Result.Exe := Trim(TJSONString(N).Value);
  N := TJSONObject(AValue).Values['file'];
  if N is TJSONString then
    Result.FileName := Trim(TJSONString(N).Value);
  N := TJSONObject(AValue).Values['env'];
  if N is TJSONString then
    Result.Env := Trim(TJSONString(N).Value);
end;

procedure ReadLocalized(AValue: TJSONValue; out ALocales, ATexts: TArray<string>);
var
  Pair: TJSONPair;
begin
  SetLength(ALocales, 0);
  SetLength(ATexts, 0);
  if AValue is TJSONString then
  begin
    SetLength(ALocales, 1);
    SetLength(ATexts, 1);
    ALocales[0] := '';
    ATexts[0] := Trim(TJSONString(AValue).Value);
  end
  else if AValue is TJSONObject then
    for Pair in TJSONObject(AValue) do
      if Pair.JsonValue is TJSONString then
      begin
        SetLength(ALocales, Length(ALocales) + 1);
        SetLength(ATexts, Length(ATexts) + 1);
        ALocales[High(ALocales)] := LowerCase(Trim(Pair.JsonString.Value));
        ATexts[High(ATexts)] := Trim(TJSONString(Pair.JsonValue).Value);
      end;
end;

/// <summary>String member AName of AObj; '' when it is absent or not a string.</summary>
function JsonText(AObj: TJSONObject; const AName: string; ATrim: Boolean = True): string;
var
  N: TJSONValue;
begin
  Result := '';
  N := AObj.Values[AName];
  if not (N is TJSONString) then
    Exit;
  Result := TJSONString(N).Value;
  if ATrim then
    Result := Trim(Result);
end;

function JsonFlag(AObj: TJSONObject; const AName: string): Boolean;
var
  N: TJSONValue;
begin
  N := AObj.Values[AName];
  Result := (N is TJSONBool) and TJSONBool(N).AsBoolean;
end;

function JsonInt(AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  N: TJSONValue;
begin
  N := AObj.Values[AName];
  if N is TJSONNumber then
    Result := TJSONNumber(N).AsInt
  else
    Result := ADefault;
end;

/// <summary>Every string of a JSON array, empty ones included; ANormalize trims and
/// lower-cases each.</summary>
function ReadStringItems(AValue: TJSONValue; ANormalize: Boolean): TArray<string>;
var
  V: TJSONValue;
  S: string;
begin
  SetLength(Result, 0);
  if not (AValue is TJSONArray) then
    Exit;
  for V in TJSONArray(AValue) do
    if V is TJSONString then
    begin
      S := TJSONString(V).Value;
      if ANormalize then
        S := LowerCase(Trim(S));
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
end;

/// <summary>File extensions, lower-case and without the leading dot.</summary>
function ReadExtensions(AValue: TJSONValue): TArray<string>;
var
  I: Integer;
begin
  Result := ReadTrimmedStrings(AValue, True);
  for I := 0 to High(Result) do
    Result[I] := Result[I].TrimLeft(['.']);
end;

function ReadManifestCommands(AValue: TJSONValue): TArray<TManifestCommand>;
var
  V: TJSONValue;
  Item: TJSONObject;
  Cmd: TManifestCommand;
begin
  SetLength(Result, 0);
  if not (AValue is TJSONArray) then
    Exit;
  for V in TJSONArray(AValue) do
  begin
    if not (V is TJSONObject) then
      Continue;
    Item := TJSONObject(V);
    Cmd := Default(TManifestCommand);
    Cmd.Id := JsonText(Item, 'id');
    if Cmd.Id = '' then
      Continue;
    Cmd.Key := JsonText(Item, 'key');
    ReadLocalized(Item.Values['label'], Cmd.LabelLocales, Cmd.LabelTexts);
    Cmd.When := ReadCondition(Item.Values['when']);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Cmd;
  end;
end;

function ReadManifestMenuItems(AValue: TJSONValue): TArray<TManifestMenuItem>;
var
  V: TJSONValue;
  Item: TJSONObject;
  MItem: TManifestMenuItem;
begin
  SetLength(Result, 0);
  if not (AValue is TJSONArray) then
    Exit;
  for V in TJSONArray(AValue) do
  begin
    if not (V is TJSONObject) then
      Continue;
    Item := TJSONObject(V);
    MItem := Default(TManifestMenuItem);
    MItem.Id := JsonText(Item, 'id');
    if MItem.Id = '' then
      Continue;
    MItem.Parent := JsonText(Item, 'parent');
    if MItem.Parent = '' then
      MItem.Parent := 'Plugins';
    MItem.Priority := JsonInt(Item, 'priority', 100);
    ReadLocalized(Item.Values['caption'], MItem.CaptionLocales, MItem.CaptionTexts);
    MItem.When := ReadCondition(Item.Values['when']);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := MItem;
  end;
end;

function ReadManifestDriveItems(AValue: TJSONValue): TArray<TManifestDriveItem>;
var
  V: TJSONValue;
  Item: TJSONObject;
  DItem: TManifestDriveItem;
begin
  SetLength(Result, 0);
  if not (AValue is TJSONArray) then
    Exit;
  for V in TJSONArray(AValue) do
  begin
    if not (V is TJSONObject) then
      Continue;
    Item := TJSONObject(V);
    DItem := Default(TManifestDriveItem);
    DItem.Id := JsonText(Item, 'id');
    if (DItem.Id = '') or not (Item.Values['uri'] is TJSONString) then
      Continue;
    DItem.Uri := JsonText(Item, 'uri');
    DItem.Priority := JsonInt(Item, 'priority', 100);
    ReadLocalized(Item.Values['caption'], DItem.CaptionLocales, DItem.CaptionTexts);
    DItem.When := ReadCondition(Item.Values['when']);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := DItem;
  end;
end;

function ReadManifestTriggers(AValue: TJSONValue): TArray<TManifestTrigger>;
var
  V: TJSONValue;
  Trigger: TManifestTrigger;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for V in TJSONArray(AValue) do
  begin
    if not (V is TJSONObject) then
      Continue;
    Trigger := Default(TManifestTrigger);
    Trigger.Event := LowerCase(JsonText(TJSONObject(V), 'event'));
    if Trigger.Event = '' then
      Continue;
    Trigger.DirHas := JsonText(TJSONObject(V), 'dirHas');
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Trigger;
  end;
end;

procedure ReadManifestIdentity(AObj: TJSONObject; var AManifest: TPluginManifest);
var
  N: TJSONValue;
begin
  AManifest.Id := JsonText(AObj, 'id', False);
  AManifest.Name := JsonText(AObj, 'name', False);
  AManifest.Version := JsonText(AObj, 'version', False);
  N := AObj.Values['abi'];
  if N is TJSONNumber then
  begin
    AManifest.AbiVersion := TJSONNumber(N).AsInt64;
    AManifest.HasAbi := True;
  end;
  ReadLocalized(AObj.Values['description'], AManifest.DescriptionLocales,
    AManifest.DescriptionTexts);
  AManifest.Author := JsonText(AObj, 'author');
  AManifest.Homepage := JsonText(AObj, 'homepage');
  AManifest.Help := JsonText(AObj, 'help');
end;

procedure ReadManifestContributions(AObj: TJSONObject; var AManifest: TPluginManifest);
begin
  AManifest.ArchiveExtensions := ReadStringItems(AObj.Values['archiveExtensions'], False);
  AManifest.Schemes := ReadStringItems(AObj.Values['schemes'], True);
  AManifest.HighlightExtensions := ReadExtensions(AObj.Values['highlightExtensions']);
  AManifest.DocumentExtensions := ReadExtensions(AObj.Values['documentExtensions']);
  AManifest.Commands := ReadManifestCommands(AObj.Values['commands']);
  AManifest.MenuItems := ReadManifestMenuItems(AObj.Values['menuItems']);
  AManifest.DriveItems := ReadManifestDriveItems(AObj.Values['driveItems']);
  AManifest.Overrides := ReadTrimmedStrings(AObj.Values['overrides'], True);
end;

procedure ReadManifestRuntime(AObj: TJSONObject; var AManifest: TPluginManifest);
var
  N: TJSONValue;
begin
  AManifest.Declarative := JsonFlag(AObj, 'declarative');
  AManifest.Startup := JsonFlag(AObj, 'startup');
  N := AObj.Values['startupWhen'];
  if N is TJSONObject then
  begin
    AManifest.StartupWhen := ReadCondition(N);
    AManifest.HasStartupWhen := True;
  end;
  AManifest.OpenRegistrations := JsonFlag(AObj, 'openRegistrations');
  AManifest.ActivateOn := ReadManifestTriggers(AObj.Values['activateOn']);
  AManifest.Wasi := JsonFlag(AObj, 'wasi');
  AManifest.MemoryMib := Max(0, Min(256, JsonInt(AObj, 'memoryMib', 0)));
  AManifest.KeepLoaded := JsonFlag(AObj, 'keepLoaded');
  AManifest.ResourceVersion := JsonInt(AObj, 'resources', 0);
  AManifest.Permissions := ReadTrimmedStrings(AObj.Values['permissions'], True);
end;

function TryParsePluginManifestJson(const AJson: string;
  out AManifest: TPluginManifest): Boolean;
var
  Val: TJSONValue;
begin
  ClearManifest(AManifest);
  Result := False;
  if Trim(AJson) = '' then
    Exit;
  Val := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Val is TJSONObject) then
      Exit;
    ReadManifestIdentity(TJSONObject(Val), AManifest);
    ReadManifestContributions(TJSONObject(Val), AManifest);
    ReadManifestRuntime(TJSONObject(Val), AManifest);
    Result := AManifest.Id <> '';
  finally
    Val.Free;
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
  Name, Lang, Candidate: string;
begin
  Result := '';
  Name := Trim(AManifest.Help);
  // A plugin cannot point the host at a file outside its own folder.
  if (Name = '') or (APluginDir = '') or (Name <> ExtractFileName(Name)) then
    Exit;
  for Lang in TArray<string>.Create(LowerCase(Trim(ALocale)), 'en') do
  begin
    if Lang = '' then
      Continue;
    Candidate := TPath.Combine(PluginResourceDir(APluginDir, Lang), 'help');
    Candidate := TPath.Combine(Candidate, Name);
    if TFile.Exists(Candidate) then
      Exit(Candidate);
  end;
end;

function PluginResourceDir(const APluginDir, ALocale: string): string;
begin
  Result := TPath.Combine(TPath.Combine(APluginDir, 'resource'), LowerCase(Trim(ALocale)));
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
