unit uStrings;

{ Runtime UI string translation.

  Design:
  - Locale 'en' (the default) is special-cased to skip lookup entirely and
    always return the call site's own literal text -- so landing this unit
    with zero translation files changes nothing about today's English UI,
    and English can never break from a missing/stale resource.
  - A non-'en' locale's key->text map loads once (lazily, on first use after
    SetLocale) from, in priority order:
      1. an RCDATA resource named STRINGS_<LOCALE> (uppercased), embedded at
         build time from strings/<locale>.json (see MTN2Resource.rc) --
         mirrors uDialogResources.pas's TryLoadDialogResourceJson;
      2. a loose <exedir>\strings\<locale>.json override, so a
         community-contributed locale can be dropped in without a recompile
         -- mirrors TTopMenuController.BuildMenuStructure's menu.json
         fallback. Search starts at <exedir>\strings, then the same name
         on each parent directory and that parent's src\strings, so a
         tool whose exe sits in bin\ still finds src\strings. (Unlike the 42 built-in dialogs\*.json layouts, whose
         disk loading is deliberately disabled, a strings file can only ever
         substitute text, never control structure/geometry, so the same
         risk does not apply here -- worth a second look if that stops
         being true.)
  - Any lookup miss (key absent from the map, whole file missing or
    unparsable, a locale never switched to) falls back to the caller's own
    ADefault -- a partial or absent translation degrades to English, never
    to a raw key or a blank string.
  - Two call shapes, matching where text lives today:
      T(key, default[, args])         -- Pascal string-literal call sites
                                          (menu captions, function-bar
                                          labels, status/error messages).
      TDialog(namespace, id, default) -- static dialog-JSON captions
                                          (labels/buttons/checkboxes/...),
                                          called only from
                                          uDialogResources.pas so the 42
                                          dialogs\*.json layouts themselves
                                          never need per-locale forks.
  - strings/en.json is not embedded or loaded at runtime at all: it exists
    purely as the authoring template a translator copies (every key that
    exists in code should be listed there against its English text) and,
    later, as input to a coverage-audit tool. The real English fallback is
    always the inline ADefault at each call site, which can never drift out
    of sync with itself the way a checked-in en.json could. }

interface

/// <summary>'en' unless SetLocale switched to something else.</summary>
function CurrentLocale: string;
/// <summary>Switches the active locale and (re)loads its string map from
/// scratch. '' is treated as 'en' (the zero-cost passthrough). Does not
/// retranslate anything already drawn -- like any other live setting
/// change, the caller is responsible for rebuilding/reopening whatever
/// should reflect it.</summary>
procedure SetLocale(const ALocale: string);
/// <summary>Every locale with an embedded STRINGS_* resource or a
/// strings\*.json file found next to the exe, deduplicated, 'en' always
/// first. For populating a language picker.</summary>
function AvailableLocales: TArray<string>;

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
  System.Generics.Collections, Winapi.Windows;

var
  GLocale: string = 'en';
  GMap: TDictionary<string, string>; // nil whenever GLocale = 'en'

procedure ForEachStringsDir(const AVisit: TProc<string>);
var
  Dir, Candidate: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  while Dir <> '' do
  begin
    Candidate := TPath.Combine(Dir, 'strings');
    if TDirectory.Exists(Candidate) then
      AVisit(Candidate);
    Candidate := TPath.Combine(TPath.Combine(Dir, 'src'), 'strings');
    if TDirectory.Exists(Candidate) then
      AVisit(Candidate);
    if SameText(ExpandFileName(TPath.Combine(Dir, '..')), ExpandFileName(Dir)) then
      Break;
    Dir := ExpandFileName(TPath.Combine(Dir, '..'));
  end;
end;

function FindStringsFile(const ALocale: string): string;
var
  Name, Found: string;
begin
  Found := '';
  Name := LowerCase(Trim(ALocale)) + '.json';
  ForEachStringsDir(
    procedure(ADir: string)
    var
      Candidate: string;
    begin
      if Found <> '' then
        Exit;
      Candidate := TPath.Combine(ADir, Name);
      if TFile.Exists(Candidate) then
        Found := Candidate;
    end);
  Result := Found;
end;

function TryLoadLocaleJsonText(const ALocale: string; out AJson: string): Boolean;
var
  ResName, FilePath: string;
  RS: TResourceStream;
  Bytes: TBytes;
  ResHandle: HRSRC;
begin
  AJson := '';
  ResName := 'STRINGS_' + UpperCase(ALocale);

  // RCDATA first -- same HInstance-then-MainInstance probe as
  // uDialogResources.TryLoadDialogResourceJson.
  ResHandle := FindResource(HInstance, PChar(ResName), RT_RCDATA);
  if ResHandle = 0 then
    ResHandle := FindResource(MainInstance, PChar(ResName), RT_RCDATA);
  if ResHandle <> 0 then
  begin
    try
      RS := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
      try
        SetLength(Bytes, RS.Size);
        if RS.Size > 0 then
          RS.ReadBuffer(Bytes[0], RS.Size);
        AJson := TEncoding.UTF8.GetString(Bytes);
        if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
          Delete(AJson, 1, 1);
      finally
        RS.Free;
      end;
      if Trim(AJson) <> '' then
        Exit(True);
    except
      AJson := '';
    end;
  end;

  // Loose-file override / a locale added without a recompile.
  FilePath := FindStringsFile(ALocale);
  if FilePath = '' then
    Exit(False);
  try
    AJson := TFile.ReadAllText(FilePath, TEncoding.UTF8);
    if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
      Delete(AJson, 1, 1);
    Result := Trim(AJson) <> '';
  except
    AJson := '';
    Result := False;
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

procedure EnsureLoaded;
var
  Json: string;
  Val: TJSONValue;
begin
  if SameText(GLocale, 'en') then
  begin
    FreeAndNil(GMap);
    Exit;
  end;
  if Assigned(GMap) then
    Exit; // already loaded for the current locale

  GMap := TDictionary<string, string>.Create;
  if not TryLoadLocaleJsonText(GLocale, Json) then
    Exit; // empty map: every lookup below falls back to ADefault
  Val := TJSONObject.ParseJSONValue(Json);
  if not Assigned(Val) then
    Exit;
  try
    if Val is TJSONObject then
      FlattenInto(GMap, '', TJSONObject(Val));
  finally
    Val.Free;
  end;
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
  if SameText(NewLocale, GLocale) then
    Exit;
  GLocale := NewLocale;
  FreeAndNil(GMap);
  EnsureLoaded;
end;

function EnumStringsResNameProc(AModule: HMODULE; AType, AName: PChar;
  AParam: NativeInt): BOOL; stdcall;
var
  List: TStringList;
  NameStr: string;
begin
  // Named (string) RT_RCDATA resources only -- an integer resource id
  // arrives with its low word as the "pointer" per the Win32 convention,
  // and dialogs\*.json's own DIALOG_* resources are named too, so this
  // check alone is what keeps this loop from wanting the huge dialog list.
  if (NativeUInt(AName) shr 16) <> 0 then
  begin
    NameStr := UpperCase(AName);
    if NameStr.StartsWith('STRINGS_') then
    begin
      List := TStringList(AParam);
      NameStr := LowerCase(Copy(NameStr, Length('STRINGS_') + 1, MaxInt));
      if List.IndexOf(NameStr) < 0 then
        List.Add(NameStr);
    end;
  end;
  Result := True;
end;

function AvailableLocales: TArray<string>;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.CaseSensitive := False;
    List.Add('en');
    EnumResourceNames(HInstance, RT_RCDATA, @EnumStringsResNameProc, NativeInt(List));
    ForEachStringsDir(
      procedure(ADir: string)
      var
        FileName, LocaleName: string;
      begin
        for FileName in TDirectory.GetFiles(ADir, '*.json') do
        begin
          LocaleName := LowerCase(TPath.GetFileNameWithoutExtension(FileName));
          if List.IndexOf(LocaleName) < 0 then
            List.Add(LocaleName);
        end;
      end);
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function T(const AKey, ADefault: string): string;
begin
  EnsureLoaded;
  if (not Assigned(GMap)) or not GMap.TryGetValue(AKey, Result) then
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
  FreeAndNil(GMap);

end.
