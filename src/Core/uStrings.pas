unit uStrings;

{ Runtime UI string translation.

  Design:
  - Locale 'en' (the default) is special-cased to skip lookup entirely and
    always return the call site's own literal text -- so landing this unit
    with zero translation files changes nothing about today's English UI,
    and English can never break from a missing/stale resource.
  - A non-'en' locale's key->text map loads once (lazily, on first use after
    SetLocale) as two layers:
      1. the base: an RCDATA resource named STRINGS_<LOCALE> (uppercased),
         embedded at build time from strings/<locale>.json (see
         MTN2Resource.rc) -- mirrors uDialogResources.pas's
         TryLoadDialogResourceJson;
      2. on top of it, a loose <exedir>\strings\<locale>.json: its keys win,
         keys it lacks keep the embedded text. So a community locale can be
         dropped in without a recompile, a shipped translation can be fixed
         in place, and a stale file left over from an older version only
         shadows the keys it still has instead of dropping the rest to
         English. Only the exe's own folder is searched -- a portable copy
         must not pick up whatever strings\ happens to sit higher up on the
         drive. Dev tools that run without the embedded resources point at
         src\strings explicitly via AddStringsSearchDir. (Unlike the built-in
         dialogs\*.json layouts, whose disk loading is deliberately disabled,
         a strings file can only ever substitute text, never control
         structure/geometry, so the same risk does not apply here -- worth a
         second look if that stops being true.)
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
/// <summary>Adds ADir to the folders searched for loose <locale>.json files,
/// after <exedir>\strings. For dev tools that link no STRINGS_* resources
/// and run from bin\ (DialogDesigner -> src\strings); the app itself never
/// calls it. Takes effect on the next SetLocale/AvailableLocales.</summary>
procedure AddStringsSearchDir(const ADir: string);

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
  GExtraDirs: TArray<string>;        // AddStringsSearchDir, dev tools only

procedure AddStringsSearchDir(const ADir: string);
var
  Dir, Existing: string;
begin
  if Trim(ADir) = '' then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
  for Existing in GExtraDirs do
    if SameText(Existing, Dir) then
      Exit;
  GExtraDirs := GExtraDirs + [Dir];
end;

procedure ForEachStringsDir(const AVisit: TProc<string>);
var
  Dir: string;
begin
  Dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'strings');
  if TDirectory.Exists(Dir) then
    AVisit(Dir);
  for Dir in GExtraDirs do
    if TDirectory.Exists(Dir) then
      AVisit(Dir);
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

function StripBom(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) > 0) and (Ord(Result[1]) = $FEFF) then
    Delete(Result, 1, 1);
end;

function TryLoadLocaleResource(const ALocale: string; out AJson: string): Boolean;
var
  ResName: string;
  Module: HMODULE;
  RS: TResourceStream;
  Bytes: TBytes;
begin
  AJson := '';
  ResName := 'STRINGS_' + UpperCase(ALocale);

  // Same HInstance-then-MainInstance probe as
  // uDialogResources.TryLoadDialogResourceJson; the stream is opened on
  // whichever module has it.
  Module := HInstance;
  if FindResource(Module, PChar(ResName), RT_RCDATA) = 0 then
  begin
    Module := MainInstance;
    if FindResource(Module, PChar(ResName), RT_RCDATA) = 0 then
      Exit(False);
  end;
  try
    RS := TResourceStream.Create(Module, ResName, RT_RCDATA);
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      AJson := StripBom(TEncoding.UTF8.GetString(Bytes));
    finally
      RS.Free;
    end;
  except
    AJson := '';
  end;
  Result := Trim(AJson) <> '';
end;

function TryLoadLocaleFile(const ALocale: string; out AJson: string): Boolean;
var
  FilePath: string;
begin
  AJson := '';
  FilePath := FindStringsFile(ALocale);
  if FilePath = '' then
    Exit(False);
  try
    AJson := StripBom(TFile.ReadAllText(FilePath, TEncoding.UTF8));
  except
    AJson := '';
  end;
  Result := Trim(AJson) <> '';
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

procedure MergeJsonInto(AMap: TDictionary<string, string>; const AJson: string);
var
  Val: TJSONValue;
begin
  Val := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(Val) then
    Exit; // unparsable layer: whatever the other layer gave stays
  try
    if Val is TJSONObject then
      FlattenInto(AMap, '', TJSONObject(Val));
  finally
    Val.Free;
  end;
end;

procedure EnsureLoaded;
var
  Json: string;
begin
  if SameText(GLocale, 'en') then
  begin
    FreeAndNil(GMap);
    Exit;
  end;
  if Assigned(GMap) then
    Exit; // already loaded for the current locale

  // Embedded base first, loose file on top (AddOrSetValue: its keys win).
  // Neither present leaves an empty map: every lookup falls back to ADefault.
  GMap := TDictionary<string, string>.Create;
  if TryLoadLocaleResource(GLocale, Json) then
    MergeJsonInto(GMap, Json);
  if TryLoadLocaleFile(GLocale, Json) then
    MergeJsonInto(GMap, Json);
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
