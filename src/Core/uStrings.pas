unit uStrings;

{ Runtime UI string translation.

  Design:
  - Locale 'en' (the default) is special-cased to skip lookup entirely and
    always return the call site's own literal text, so English can never
    break from a missing or stale resource. It is the only language built
    into the exe.
  - Every other language is a pack folder <exedir>\resource\<locale>\:
        locale.json   the "version" and "name" fields (required)
        strings.json  key -> text map (nested objects flatten to dotted keys)
        help\         Markdown topics for F1 (see uHelpViewer)
    A new language is added by copying such a folder; nothing is recompiled.
    Only the exe's own folder is searched, so a portable copy never picks up
    whatever resource\ sits higher up on the drive.
  - Pack version control. The exe carries RESOURCE_VERSION (an RCDATA
    resource), the revision of the key set and file layout it was built for.
    locale.json "version" says which revision a pack was written for:
      equal   - applied;
      older   - applied, keys the pack lacks fall back to English, and the
                pack is reported as outdated (self-check warning);
      newer   - ignored (the exe cannot know what it means);
      missing or unreadable locale.json - ignored.
    An ignored pack is not offered in the language picker.
  - Any lookup miss (key absent, pack ignored or absent, a locale never
    switched to) falls back to the caller's own ADefault - a partial or
    absent translation degrades to English, never to a raw key or a blank.
  - Two call shapes, matching where text lives:
      T(key, default[, args])         -- Pascal string-literal call sites
                                          (menu captions, function-bar
                                          labels, status/error messages).
      TDialog(namespace, id, default) -- static dialog-JSON captions
                                          (labels/buttons/checkboxes/...),
                                          called only from
                                          uDialogResources.pas so the
                                          dialogs\*.json layouts never need
                                          per-locale forks.
  - TStringPack is the same map for one plugin: the host owns the locale and
    hands each plugin a pack rooted at plugins\<id>\resource.
  - strings/en.json is not loaded at runtime: it is the authoring template a
    translator copies (every key that exists in code, against its English
    text). The real English fallback is the inline ADefault at each call
    site, which cannot drift out of sync with itself. }

interface

uses
  System.Generics.Collections;

type
  /// <summary>How a locale pack relates to the exe that reads it.</summary>
  TLocalePackStatus = (
    lpsMissing,   // no locale.json
    lpsInvalid,   // locale.json unreadable or without a numeric version
    lpsOlder,     // written for an older revision: applied, reported
    lpsCurrent,   // matches the exe
    lpsNewer);    // written for a newer revision: ignored

  TLocalePackInfo = record
    Locale: string;
    Dir: string;           // <root>\<locale>
    Name: string;          // display name from locale.json, '' when absent
    Version: Integer;
    Status: TLocalePackStatus;
    /// <summary>True when the pack's strings and help are used.</summary>
    function Usable: Boolean;
  end;

  /// <summary>The key -> text map of one locale pack. Owned by the caller;
  /// nothing is cached globally, so one instance per plugin is fine.</summary>
  TStringPack = class
  private
    FMap: TDictionary<string, string>;
    FInfo: TLocalePackInfo;
  public
    /// <summary>Loads ARootDir\ALocale\strings.json. AExpectedVersion = 0
    /// accepts any pack version (no version control).</summary>
    constructor Create(const ARootDir, ALocale: string; AExpectedVersion: Integer);
    destructor Destroy; override;
    /// <summary>The translation of AKey, or ADefault when there is none.</summary>
    function Lookup(const AKey, ADefault: string): string;
    property Info: TLocalePackInfo read FInfo;
  end;

/// <summary>Revision of the key set and pack layout this exe was built for
/// (the RESOURCE_VERSION resource); 0 when the module has none.</summary>
function ResourceVersion: Integer;
/// <summary>Folder holding the locale packs: <exedir>\resource unless
/// SetResourceRoot says otherwise.</summary>
function ResourceRoot: string;
/// <summary>Points the packs at ADir instead of <exedir>\resource ('' restores
/// the default). For tests and dev tools that run from another folder; the
/// app itself never calls it. Takes effect on the next SetLocale.</summary>
procedure SetResourceRoot(const ADir: string);
/// <summary>Reads ARootDir\ALocale\locale.json and compares its version with
/// AExpectedVersion (0 accepts any version).</summary>
function InspectLocalePack(const ARootDir, ALocale: string;
  AExpectedVersion: Integer): TLocalePackInfo;
/// <summary>Every locale folder under ResourceRoot, usable or not, sorted.</summary>
function LocalePackFolders: TArray<string>;

/// <summary>'en' unless SetLocale switched to something else.</summary>
function CurrentLocale: string;
/// <summary>Switches the active locale and (re)loads its string map from
/// scratch. '' is treated as 'en' (the zero-cost passthrough). Does not
/// retranslate anything already drawn -- like any other live setting
/// change, the caller is responsible for rebuilding/reopening whatever
/// should reflect it.</summary>
procedure SetLocale(const ALocale: string);
/// <summary>'en' plus every usable pack under ResourceRoot, deduplicated,
/// 'en' always first. For populating a language picker.</summary>
function AvailableLocales: TArray<string>;
/// <summary>The first of APreferred (BCP 47 style tags, best first) that has an
/// entry in AAvailable, tried as the whole tag, then with trailing subtags
/// dropped ("zh-Hans-CN", "zh-Hans", "zh"); 'en' when none has.</summary>
function PickLocale(const APreferred, AAvailable: TArray<string>): string;
/// <summary>The locale for a first start: the OS interface language when a
/// translation for it exists, English otherwise.</summary>
function SystemDefaultLocale: string;
/// <summary>The pack state of ALocale under ResourceRoot (self-check, help).</summary>
function LocalePackInfo(const ALocale: string): TLocalePackInfo;

/// <summary>Plain-text lookup for Pascal string-literal call sites. ADefault
/// is both the English baseline (what ships until AKey is translated) and
/// the result whenever the current locale has no entry for AKey.</summary>
function T(const AKey, ADefault: string): string; overload;
/// <summary>Same lookup, then Format()s the winning string with AArgs. Falls
/// back to formatting ADefault itself if the translated string's
/// placeholders don't match AArgs (a bad translation must degrade to
/// English, never crash the caller).</summary>
function T(const AKey, ADefault: string; const AArgs: array of const): string; overload;
/// <summary>Static dialog-JSON caption lookup -- ANamespace is the dialog's
/// own RCDATA resource name (e.g. cResDialogConfirm), AControlId its control
/// id, or '' for the dialog's own Title. Called only from
/// uDialogResources.pas.</summary>
function TDialog(const ANamespace, AControlId, ADefault: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uResourceAccess, uPlatformInfo;

const
  cLocaleFile = 'locale.json';
  cStringsFile = 'strings.json';
  cVersionResource = 'RESOURCE_VERSION';

var
  GLocale: string = 'en';
  GPack: TStringPack;        // nil whenever GLocale = 'en'
  GRootOverride: string;

function TLocalePackInfo.Usable: Boolean;
begin
  Result := Status in [lpsOlder, lpsCurrent];
end;

function StripBom(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) > 0) and (Ord(Result[1]) = $FEFF) then
    Delete(Result, 1, 1);
end;

function TryReadText(const APath: string; out AText: string): Boolean;
begin
  AText := '';
  if not TFile.Exists(APath) then
    Exit(False);
  try
    AText := StripBom(TFile.ReadAllText(APath, TEncoding.UTF8));
  except
    AText := '';
  end;
  Result := Trim(AText) <> '';
end;

function ResourceVersion: Integer;
var
  RS: TStream;
  Bytes: TBytes;
begin
  Result := 0;
  RS := OpenRcData(cVersionResource);
  if RS = nil then
    Exit;
  try
    SetLength(Bytes, RS.Size);
    if RS.Size > 0 then
      RS.ReadBuffer(Bytes[0], RS.Size);
  finally
    RS.Free;
  end;
  Result := StrToIntDef(Trim(StripBom(TEncoding.UTF8.GetString(Bytes))), 0);
end;

function ResourceRoot: string;
begin
  if GRootOverride <> '' then
    Result := GRootOverride
  else
    Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'resource');
end;

procedure SetResourceRoot(const ADir: string);
begin
  if Trim(ADir) = '' then
    GRootOverride := ''
  else
    GRootOverride := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
end;

function InspectLocalePack(const ARootDir, ALocale: string;
  AExpectedVersion: Integer): TLocalePackInfo;
var
  Text: string;
  Val: TJSONValue;
  Obj: TJSONObject;
  Node: TJSONValue;
begin
  Result := Default(TLocalePackInfo);
  Result.Locale := LowerCase(Trim(ALocale));
  Result.Dir := TPath.Combine(ARootDir, Result.Locale);
  if not TryReadText(TPath.Combine(Result.Dir, cLocaleFile), Text) then
  begin
    Result.Status := lpsMissing;
    Exit;
  end;
  Result.Status := lpsInvalid;
  Val := TJSONObject.ParseJSONValue(Text);
  try
    if not (Val is TJSONObject) then
      Exit;
    Obj := TJSONObject(Val);
    Node := Obj.GetValue('version');
    if not (Node is TJSONNumber) then
      Exit;
    Result.Version := TJSONNumber(Node).AsInt;
    Node := Obj.GetValue('name');
    if Node is TJSONString then
      Result.Name := TJSONString(Node).Value;
  finally
    Val.Free;
  end;
  if (AExpectedVersion = 0) or (Result.Version = AExpectedVersion) then
    Result.Status := lpsCurrent
  else if Result.Version < AExpectedVersion then
    Result.Status := lpsOlder
  else
    Result.Status := lpsNewer;
end;

function LocalePackInfo(const ALocale: string): TLocalePackInfo;
begin
  Result := InspectLocalePack(ResourceRoot, ALocale, ResourceVersion);
end;

function LocalePackFolders: TArray<string>;
var
  Root, Dir: string;
  List: TStringList;
begin
  Root := ResourceRoot;
  if not TDirectory.Exists(Root) then
    Exit(nil);
  List := TStringList.Create;
  try
    for Dir in TDirectory.GetDirectories(Root) do
      List.Add(LowerCase(ExtractFileName(Dir)));
    List.Sort;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

// Recursively flattens nested JSON objects into dotted keys, e.g.
// {"dialogs":{"DIALOG_CONFIRM":{"ok":"OK"}}} -> "dialogs.DIALOG_CONFIRM.ok".
// A leaf that isn't a JSON string (a stray number/bool/array/null) is
// skipped rather than raising -- one malformed entry must not take down an
// otherwise-usable locale file.
procedure FlattenInto(AMap: TDictionary<string, string>; const APrefix: string;
  AObj: TJSONObject);
var
  Pair: TJSONPair;
  Key: string;
begin
  for Pair in AObj do
  begin
    if APrefix = '' then
      Key := Pair.JsonString.Value
    else
      Key := APrefix + '.' + Pair.JsonString.Value;
    if Pair.JsonValue is TJSONObject then
      FlattenInto(AMap, Key, TJSONObject(Pair.JsonValue))
    else if Pair.JsonValue is TJSONString then
      AMap.AddOrSetValue(Key, TJSONString(Pair.JsonValue).Value);
  end;
end;

{ TStringPack }

constructor TStringPack.Create(const ARootDir, ALocale: string; AExpectedVersion: Integer);
var
  Text: string;
  Val: TJSONValue;
begin
  inherited Create;
  FMap := TDictionary<string, string>.Create;
  FInfo := InspectLocalePack(ARootDir, ALocale, AExpectedVersion);
  if not FInfo.Usable then
    Exit;
  // An unreadable strings file leaves the map empty: every lookup falls back
  // to the caller's default.
  if not TryReadText(TPath.Combine(FInfo.Dir, cStringsFile), Text) then
    Exit;
  Val := TJSONObject.ParseJSONValue(Text);
  try
    if Val is TJSONObject then
      FlattenInto(FMap, '', TJSONObject(Val));
  finally
    Val.Free;
  end;
end;

destructor TStringPack.Destroy;
begin
  FMap.Free;
  inherited;
end;

function TStringPack.Lookup(const AKey, ADefault: string): string;
begin
  if not FMap.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

procedure EnsureLoaded;
begin
  if SameText(GLocale, 'en') then
  begin
    FreeAndNil(GPack);
    Exit;
  end;
  if not Assigned(GPack) then
    GPack := TStringPack.Create(ResourceRoot, GLocale, ResourceVersion);
end;

function CurrentLocale: string;
begin
  Result := GLocale;
end;

procedure SetLocale(const ALocale: string);
var
  NewLocale: string;
begin
  NewLocale := Trim(ALocale);
  if NewLocale = '' then
    NewLocale := 'en';
  // The same locale is reloaded too: the packs or the root may have changed
  // since it was last read.
  GLocale := NewLocale;
  FreeAndNil(GPack);
  EnsureLoaded;
end;

function AvailableLocales: TArray<string>;
var
  Name: string;
begin
  Result := ['en'];
  for Name in LocalePackFolders do
    if (Name <> 'en') and LocalePackInfo(Name).Usable then
      Result := Result + [Name];
end;

function PickLocale(const APreferred, AAvailable: TArray<string>): string;
var
  Pref, Tag, Have: string;
  Parts: TArray<string>;
  N, I: Integer;
begin
  for Pref in APreferred do
  begin
    Parts := LowerCase(StringReplace(Trim(Pref), '_', '-', [rfReplaceAll])).Split(['-']);
    for N := Length(Parts) downto 1 do
    begin
      Tag := Parts[0];
      for I := 1 to N - 1 do
        Tag := Tag + '-' + Parts[I];
      if Tag = '' then
        Continue;
      for Have in AAvailable do
        if SameText(Have, Tag) then
          Exit(LowerCase(Have));
    end;
  end;
  Result := 'en';
end;

function SystemDefaultLocale: string;
begin
  Result := PickLocale(PlatformPreferredUiLanguages, AvailableLocales);
end;

function T(const AKey, ADefault: string): string;
begin
  EnsureLoaded;
  if Assigned(GPack) then
    Result := GPack.Lookup(AKey, ADefault)
  else
    Result := ADefault;
end;

function T(const AKey, ADefault: string; const AArgs: array of const): string;
var
  Translated: string;
begin
  Translated := T(AKey, ADefault);
  try
    Result := Format(Translated, AArgs);
  except
    Result := Format(ADefault, AArgs);
  end;
end;

function TDialog(const ANamespace, AControlId, ADefault: string): string;
var
  Key: string;
begin
  if AControlId = '' then
    Key := 'dialogs.' + ANamespace + '.$title'
  else
    Key := 'dialogs.' + ANamespace + '.' + AControlId;
  Result := T(Key, ADefault);
end;

initialization

finalization
  FreeAndNil(GPack);

end.
