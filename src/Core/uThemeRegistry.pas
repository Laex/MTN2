unit uThemeRegistry;

{ Catalog of themes from three places: the default theme NDN, embedded in the
  exe as RCDATA (Assets\themes\NDN.theme.json, resource THEME_NDN) so the
  program always has a look; the shipped themes, files in
  resource\themes\<Id>.theme.json next to the exe (the same folder tree as the
  language packs); and the user's own, files in <config dir>\themes\<name>.theme.json
  (the exe's folder in portable mode). A theme is identified by a stable Id
  persisted in session.json (TMtnSession.ThemeName): the default or shipped
  id, or the file name of a user theme without ".theme.json".

  The default and shipped themes are read-only: saving a customized theme
  always writes a new user file (SaveUserTheme), never one of those. A user
  file named like a shipped theme is ignored (ShadowedUserThemes lists them).
  A shipped file that does not parse is skipped. This is independent
  of uColorCoding's per-file-type coloring rules, which are part of the
  theme (TThemeSpec.FileColoring) and handed to uColorCoding on activation.

  Every theme extends another (the default theme when its file names none);
  LoadThemeChain walks that chain, root first, and ResolveThemeSpec
  (uThemeSpec) flattens it. }

interface

uses
  uThemeTypes, uThemeSpec;

type
  TThemeInfo = record
    Id: string;
    DisplayName: string;
    /// <summary>True for the default and the shipped themes: read-only.</summary>
    BuiltIn: Boolean;
    /// <summary>Id of the theme this one extends ('' for the default theme).</summary>
    Extends: string;
    /// <summary>Full path of the theme's file; '' for the embedded default theme.</summary>
    FileName: string;
  end;

/// <summary>The default theme, the shipped themes in picker order, then the
/// user's themes by name.</summary>
function GetAvailableThemes: TArray<TThemeInfo>;
/// <summary>Id of the classic Far theme: the fallback for everything.</summary>
function DefaultThemeId: string;
function FindThemeInfo(const AId: string; out AInfo: TThemeInfo): Boolean;
function ThemeExists(const AId: string): Boolean;

/// <summary>The theme's file as written (without its base themes).</summary>
function TryLoadThemeDoc(const AId: string; out ADoc: TThemeDoc): Boolean;
/// <summary>The themes ADoc builds on, in the order they are applied (later
/// ones override earlier ones); ADoc itself is not in the list. A base that is
/// also a base of another base appears once, at its first position. AWarning
/// names a base that could not be found or that closes a cycle (the default
/// theme stands in for it).</summary>
function LoadBaseChain(const ADoc: TThemeDoc; out AWarning: string): TArray<TThemeDoc>;
/// <summary>The spec of ADoc's bases alone - what ADoc inherits.</summary>
function ResolveBaseSpec(const ADoc: TThemeDoc): TThemeSpec;
/// <summary>The fully resolved theme AId; False when it does not exist or
/// its file is unreadable.</summary>
function TryLoadThemeSpec(const AId: string; out ASpec: TThemeSpec): Boolean;
/// <summary>ADoc resolved on top of its bases (for a theme being edited).</summary>
function ResolveDocSpec(const ADoc: TThemeDoc): TThemeSpec;

/// <summary>The theme AId as a renderer; the default theme when AId is blank
/// or unknown - never fails.</summary>
function CreateThemeByName(const AId: string): IThemeRenderer;
/// <summary>A renderer drawing ASpec.</summary>
function CreateThemeFromSpec(const ASpec: TThemeSpec): IThemeRenderer;

function UserThemesDirectory: string;
/// <summary>The folder of the shipped themes: resource\themes under
/// uStrings.ResourceRoot.</summary>
function ShippedThemesDirectory: string;
/// <summary>Ids of user theme files that carry the id of a default or shipped
/// theme and are therefore never listed or loaded.</summary>
function ShadowedUserThemes: TArray<string>;
/// <summary>Files in the shipped folder that are not valid theme files.</summary>
function InvalidShippedThemes: TArray<string>;
/// <summary>File-name-safe id for a theme name typed by the user; '' when
/// nothing usable is left.</summary>
function ThemeIdFromName(const AName: string): string;
/// <summary>Writes ADoc as the user theme ADoc.Id (derived from ADoc.Name
/// when Id is blank). Fails, with AError, for a built-in id, an unusable
/// name or an I/O error.</summary>
function SaveUserTheme(var ADoc: TThemeDoc; out AError: string): Boolean;
function DeleteUserTheme(const AId: string): Boolean;

/// <summary>Turns the settings files of earlier versions into a user theme
/// extending ABaseThemeId: the file coloring file (ALegacyColoringFile in the
/// config dir, NDNtheme.json when blank) and markdown-colors.json. The files
/// are set aside as "<name>.migrated". False when neither holds anything.</summary>
function ImportLegacyFiles(const ABaseThemeId, ALegacyColoringFile: string;
  out ANewId: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults,
  uResourceAccess, uConfigLocation, uStrings, uDataTheme, uColorCoding,
  uMarkdownColors;

type
  TReadOnlyTheme = record
    Doc: TThemeDoc;
    FileName: string;
  end;

const
  cDefaultThemeId = 'NDN';
  cMaxChainDepth = 8;
  cThemesDirName = 'themes';
  // Shipped themes the picker lists first, in this order; any other shipped
  // theme follows by name.
  cPickerOrder: array[0..18] of string = (
    'NortonCommander', 'MidnightCommander', 'ModernUnicode', 'ASCII',
    'TotalCommander', 'Monochrome', 'HighContrast', 'SolarizedDark',
    'SolarizedLight', 'Dracula', 'Nord', 'GruvboxDark', 'Monokai', 'TokyoNight',
    'OneDark', 'DarkPlus', 'Light', 'GreenPhosphor', 'AmberPhosphor');

var
  // The default theme first, then the shipped ones in picker order.
  GReadOnly: TArray<TReadOnlyTheme>;
  GReadOnlyLoaded: Boolean = False;
  GInvalidShipped: TArray<string>;

function DefaultThemeId: string;
begin
  Result := cDefaultThemeId;
end;

procedure EnsureReadOnly; forward;

function IsBuiltInId(const AId: string): Boolean;
var
  I: Integer;
begin
  EnsureReadOnly;
  for I := 0 to High(GReadOnly) do
    if SameText(GReadOnly[I].Doc.Id, AId) then
      Exit(True);
  Result := False;
end;

function UserThemesDirectory: string;
begin
  Result := TPath.Combine(GetConfigDirectory, cThemesDirName);
end;

function ShippedThemesDirectory: string;
begin
  Result := TPath.Combine(ResourceRoot, cThemesDirName);
end;

function TryLoadResourceText(const AResName: string; out AText: string): Boolean;
var
  RS: TStream;
  Bytes: TBytes;
begin
  AText := '';
  Result := False;
  RS := OpenRcData(AResName);
  if RS = nil then
    Exit;
  try
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      AText := TEncoding.UTF8.GetString(Bytes);
      if (Length(AText) > 0) and (Ord(AText[1]) = $FEFF) then
        Delete(AText, 1, 1);
      Result := Trim(AText) <> '';
    finally
      RS.Free;
    end;
  except
    AText := '';
    Result := False;
  end;
end;

function TryReadFileText(const APath: string; out AText: string): Boolean;
begin
  AText := '';
  try
    AText := TFile.ReadAllText(APath, TEncoding.UTF8);
    if (Length(AText) > 0) and (Ord(AText[1]) = $FEFF) then
      Delete(AText, 1, 1);
    Result := Trim(AText) <> '';
  except
    Result := False;
  end;
end;

function UserThemePath(const AId: string): string;
begin
  Result := TPath.Combine(UserThemesDirectory, AId + cThemeFileExt);
end;

function IdOfThemeFile(const AFile: string): string;
begin
  Result := ExtractFileName(AFile);
  Result := Copy(Result, 1, Length(Result) - Length(cThemeFileExt));
end;

function PickerRank(const AId: string): Integer;
begin
  for Result := 0 to High(cPickerOrder) do
    if SameText(cPickerOrder[Result], AId) then
      Exit;
  Result := Length(cPickerOrder);
end;

procedure EnsureReadOnly;
var
  Text, Err, Id, Dir: string;
  Entry: TReadOnlyTheme;
  Files: TArray<string>;
  Shipped: TList<TReadOnlyTheme>;
  I: Integer;
begin
  if GReadOnlyLoaded then
    Exit;
  GReadOnlyLoaded := True;
  SetLength(GReadOnly, 0);
  SetLength(GInvalidShipped, 0);
  if TryLoadResourceText('THEME_' + UpperCase(cDefaultThemeId), Text) and
     TryParseThemeDoc(Text, Entry.Doc, Err) then
  begin
    Entry.Doc.Id := cDefaultThemeId;
    if Entry.Doc.Name = '' then
      Entry.Doc.Name := cDefaultThemeId;
    Entry.FileName := '';
    GReadOnly := [Entry];
  end;

  Dir := ShippedThemesDirectory;
  SetLength(Files, 0);
  if TDirectory.Exists(Dir) then
    try
      Files := TDirectory.GetFiles(Dir, '*' + cThemeFileExt);
    except
      SetLength(Files, 0);
    end;
  Shipped := TList<TReadOnlyTheme>.Create;
  try
    for I := 0 to High(Files) do
    begin
      Id := IdOfThemeFile(Files[I]);
      if SameText(Id, cDefaultThemeId) then
        Continue;
      if not (TryReadFileText(Files[I], Text) and
              TryParseThemeDoc(Text, Entry.Doc, Err)) then
      begin
        GInvalidShipped := GInvalidShipped + [Id];
        Continue;
      end;
      Entry.Doc.Id := Id;
      if Entry.Doc.Name = '' then
        Entry.Doc.Name := Id;
      Entry.FileName := Files[I];
      Shipped.Add(Entry);
    end;
    Shipped.Sort(TComparer<TReadOnlyTheme>.Construct(
      function(const A, B: TReadOnlyTheme): Integer
      begin
        Result := PickerRank(A.Doc.Id) - PickerRank(B.Doc.Id);
        if Result = 0 then
          Result := CompareText(A.Doc.Name, B.Doc.Name);
      end));
    for Entry in Shipped do
      GReadOnly := GReadOnly + [Entry];
  finally
    Shipped.Free;
  end;
end;

function InvalidShippedThemes: TArray<string>;
begin
  EnsureReadOnly;
  Result := GInvalidShipped;
end;

function TryLoadThemeDoc(const AId: string; out ADoc: TThemeDoc): Boolean;
var
  I: Integer;
  Text, Err: string;
begin
  ADoc := Default(TThemeDoc);
  Result := False;
  if Trim(AId) = '' then
    Exit;
  EnsureReadOnly;
  for I := 0 to High(GReadOnly) do
    if SameText(GReadOnly[I].Doc.Id, AId) then
    begin
      ADoc := GReadOnly[I].Doc;
      Exit(True);
    end;
  if not TryReadFileText(UserThemePath(AId), Text) then
    Exit;
  if not TryParseThemeDoc(Text, ADoc, Err) then
    Exit;
  ADoc.Id := AId;
  if ADoc.Name = '' then
    ADoc.Name := AId;
  Result := True;
end;

function ContainsId(const AIds: TArray<string>; const AId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AIds) do
    if SameText(AIds[I], AId) then
      Exit(True);
  Result := False;
end;

function BaseIdsOf(const ADoc: TThemeDoc): TArray<string>;
begin
  Result := ADoc.Extends;
  if (Length(Result) = 0) and not SameText(ADoc.Id, cDefaultThemeId) then
    Result := [cDefaultThemeId];
end;

// Appends AId's chain (its bases first, then the theme) to AList.
procedure AddChain(const AId: string; var AList: TArray<TThemeDoc>;
  const APath: TArray<string>; var AWarning: string);
var
  Doc: TThemeDoc;
  Base: string;
begin
  if (Length(APath) >= cMaxChainDepth) or ContainsId(APath, AId) or
     not TryLoadThemeDoc(AId, Doc) then
  begin
    if AWarning = '' then
      AWarning := AId;
    // The default theme stands in for a missing or circular base.
    if not SameText(AId, cDefaultThemeId) and not ContainsId(APath, cDefaultThemeId) then
      AddChain(cDefaultThemeId, AList, APath, AWarning);
    Exit;
  end;
  for Base in BaseIdsOf(Doc) do
    AddChain(Base, AList, APath + [AId], AWarning);
  AList := AList + [Doc];
end;

function LoadBaseChain(const ADoc: TThemeDoc; out AWarning: string): TArray<TThemeDoc>;
var
  Raw: TArray<TThemeDoc>;
  Base: string;
  I, J: Integer;
  Path: TArray<string>;
  Earlier: Boolean;
begin
  SetLength(Raw, 0);
  AWarning := '';
  if ADoc.Id <> '' then
    Path := [ADoc.Id]
  else
    SetLength(Path, 0);
  for Base in BaseIdsOf(ADoc) do
    AddChain(Base, Raw, Path, AWarning);
  // A theme reached twice (a base shared by two bases) counts where it came
  // first, so it stays below everything built on it.
  SetLength(Result, 0);
  for I := 0 to High(Raw) do
  begin
    Earlier := False;
    for J := 0 to I - 1 do
      if SameText(Raw[J].Id, Raw[I].Id) then
      begin
        Earlier := True;
        Break;
      end;
    if not Earlier then
      Result := Result + [Raw[I]];
  end;
end;

function ResolveBaseSpec(const ADoc: TThemeDoc): TThemeSpec;
var
  Warning: string;
begin
  Result := ResolveThemeSpec(LoadBaseChain(ADoc, Warning));
end;

function ResolveDocSpec(const ADoc: TThemeDoc): TThemeSpec;
var
  Warning: string;
  Chain: TArray<TThemeDoc>;
begin
  Chain := LoadBaseChain(ADoc, Warning) + [ADoc];
  Result := ResolveThemeSpec(Chain);
  Result.Id := ADoc.Id;
  Result.Name := ADoc.Name;
  Result.BuiltIn := IsBuiltInId(ADoc.Id);
end;

function TryLoadThemeSpec(const AId: string; out ASpec: TThemeSpec): Boolean;
var
  Doc: TThemeDoc;
begin
  Result := TryLoadThemeDoc(AId, Doc);
  if Result then
    ASpec := ResolveDocSpec(Doc)
  else
    ASpec := Default(TThemeSpec);
end;

function CreateThemeFromSpec(const ASpec: TThemeSpec): IThemeRenderer;
begin
  Result := TDataTheme.Create(ASpec);
end;

function CreateThemeByName(const AId: string): IThemeRenderer;
var
  Spec: TThemeSpec;
begin
  if not TryLoadThemeSpec(AId, Spec) and not TryLoadThemeSpec(cDefaultThemeId, Spec) then
    Spec := ResolveThemeSpec(nil);
  Result := TDataTheme.Create(Spec);
end;

function InfoOf(const ADoc: TThemeDoc; ABuiltIn: Boolean; const AFile: string): TThemeInfo;
begin
  Result.Id := ADoc.Id;
  Result.DisplayName := ADoc.Name;
  Result.BuiltIn := ABuiltIn;
  Result.Extends := ThemeExtendsText(ADoc.Extends);
  Result.FileName := AFile;
end;

function GetAvailableThemes: TArray<TThemeInfo>;
var
  I: Integer;
  Files: TArray<string>;
  Doc: TThemeDoc;
  Id: string;
  User: TList<TThemeInfo>;
  Info: TThemeInfo;
begin
  EnsureReadOnly;
  SetLength(Result, 0);
  for I := 0 to High(GReadOnly) do
    Result := Result + [InfoOf(GReadOnly[I].Doc, True, GReadOnly[I].FileName)];

  User := TList<TThemeInfo>.Create;
  try
    if TDirectory.Exists(UserThemesDirectory) then
    begin
      try
        Files := TDirectory.GetFiles(UserThemesDirectory, '*' + cThemeFileExt);
      except
        SetLength(Files, 0);
      end;
      for I := 0 to High(Files) do
      begin
        Id := IdOfThemeFile(Files[I]);
        if IsBuiltInId(Id) or not TryLoadThemeDoc(Id, Doc) then
          Continue;
        User.Add(InfoOf(Doc, False, Files[I]));
      end;
    end;
    User.Sort(TComparer<TThemeInfo>.Construct(
      function(const A, B: TThemeInfo): Integer
      begin
        Result := CompareText(A.DisplayName, B.DisplayName);
      end));
    for Info in User do
      Result := Result + [Info];
  finally
    User.Free;
  end;
end;

function ShadowedUserThemes: TArray<string>;
var
  Files: TArray<string>;
  I: Integer;
  Id: string;
begin
  SetLength(Result, 0);
  if not TDirectory.Exists(UserThemesDirectory) then
    Exit;
  try
    Files := TDirectory.GetFiles(UserThemesDirectory, '*' + cThemeFileExt);
  except
    Exit;
  end;
  for I := 0 to High(Files) do
  begin
    Id := IdOfThemeFile(Files[I]);
    if IsBuiltInId(Id) then
      Result := Result + [Id];
  end;
end;

function FindThemeInfo(const AId: string; out AInfo: TThemeInfo): Boolean;
var
  Info: TThemeInfo;
begin
  for Info in GetAvailableThemes do
    if SameText(Info.Id, AId) then
    begin
      AInfo := Info;
      Exit(True);
    end;
  AInfo := Default(TThemeInfo);
  Result := False;
end;

function ThemeExists(const AId: string): Boolean;
var
  Doc: TThemeDoc;
begin
  Result := TryLoadThemeDoc(AId, Doc);
end;

function ThemeIdFromName(const AName: string): string;
const
  cBadChars = '\/:*?"<>|';
  cReserved: array[0..21] of string = ('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2',
    'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2',
    'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9');
var
  I: Integer;
  S: string;
begin
  S := Trim(AName);
  Result := '';
  for I := 1 to Length(S) do
    if (Ord(S[I]) < 32) or (Pos(S[I], cBadChars) > 0) then
      Result := Result + '_'
    else
      Result := Result + S[I];
  Result := Trim(Result);
  while (Result <> '') and (Result[Length(Result)] = '.') do
    Delete(Result, Length(Result), 1);
  if Length(Result) > 64 then
    Result := Trim(Copy(Result, 1, 64));
  for I := 0 to High(cReserved) do
    if SameText(Result, cReserved[I]) then
      Exit('');
end;

function SaveUserTheme(var ADoc: TThemeDoc; out AError: string): Boolean;
var
  Id: string;
begin
  Result := False;
  AError := '';
  ADoc.Name := Trim(ADoc.Name);
  Id := ADoc.Id;
  if Id = '' then
    Id := ThemeIdFromName(ADoc.Name);
  if (ADoc.Name = '') or (Id = '') then
  begin
    AError := 'name';
    Exit;
  end;
  if IsBuiltInId(Id) then
  begin
    AError := 'builtin';
    Exit;
  end;
  try
    TDirectory.CreateDirectory(UserThemesDirectory);
    TFile.WriteAllText(UserThemePath(Id), ThemeDocToJson(ADoc), TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit;
    end;
  end;
  ADoc.Id := Id;
  Result := True;
end;

function DeleteUserTheme(const AId: string): Boolean;
begin
  Result := False;
  if IsBuiltInId(AId) or (Trim(AId) = '') then
    Exit;
  try
    if TFile.Exists(UserThemePath(AId)) then
      TFile.Delete(UserThemePath(AId));
    Result := True;
  except
    Result := False;
  end;
end;

procedure SetAsideLegacyFile(const APath: string);
begin
  if not TFile.Exists(APath) then
    Exit;
  try
    if TFile.Exists(APath + '.migrated') then
      TFile.Delete(APath + '.migrated');
    TFile.Move(APath, APath + '.migrated');
  except
    // Left in place: the import then runs again on the next start.
  end;
end;

function ImportLegacyFiles(const ABaseThemeId, ALegacyColoringFile: string;
  out ANewId: string): Boolean;
const
  cLegacyDefault = 'NDNtheme.json';
var
  ColoringPath, MarkdownPath, Json, Base, Err: string;
  Groups: TArray<TColorCodingGroup>;
  MdSet, NoSet: TMdColorSet;
  HasColoring, HasMarkdown: Boolean;
  BaseDoc, Doc: TThemeDoc;
  Kind: TMdSpanKind;
  N: Integer;
begin
  Result := False;
  ANewId := '';
  if Trim(ALegacyColoringFile) = '' then
    ColoringPath := GetConfigFilePath(cLegacyDefault)
  else
    ColoringPath := GetConfigFilePath(ALegacyColoringFile);
  MarkdownPath := DefaultMarkdownColorsFilePath;
  HasColoring := TFile.Exists(ColoringPath);
  HasMarkdown := TFile.Exists(MarkdownPath);
  if not (HasColoring or HasMarkdown) then
    Exit;
  MdColorSetClear(MdSet);
  MdColorSetClear(NoSet);
  SetLength(Groups, 0);
  if HasColoring then
    HasColoring := TryReadFileText(ColoringPath, Json) and
      ParseColorCodingJson(Json, Groups, 'fileColoring') and (Length(Groups) > 0);
  if HasMarkdown then
  begin
    HasMarkdown := False;
    if TryReadFileText(MarkdownPath, Json) and MdColorSetFromJson(Json, MdSet) then
      for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
        if MdSet[Kind].HasFg or MdSet[Kind].HasBg or MdSet[Kind].HasStyle then
          HasMarkdown := True;
  end;
  if not (HasColoring or HasMarkdown) then
  begin
    SetAsideLegacyFile(ColoringPath);
    SetAsideLegacyFile(MarkdownPath);
    Exit;
  end;
  Base := ABaseThemeId;
  if not TryLoadThemeDoc(Base, BaseDoc) then
  begin
    Base := cDefaultThemeId;
    if not TryLoadThemeDoc(Base, BaseDoc) then
      Exit;
  end;
  Doc := Default(TThemeDoc);
  Doc.Name := BaseDoc.Name + ' (imported)';
  N := 1;
  while ThemeExists(ThemeIdFromName(Doc.Name)) do
  begin
    Inc(N);
    Doc.Name := Format('%s (imported %d)', [BaseDoc.Name, N]);
  end;
  Doc.Extends := [Base];
  if HasColoring then
  begin
    // A file in the earlier format is merged over the default groups by name, as a theme is.
    Doc.HasFileColoring := True;
    Doc.FileColoring := Groups;
  end;
  if HasMarkdown then
    ThemeDocApplyMdSet(Doc, NoSet, MdSet);
  if not SaveUserTheme(Doc, Err) then
    Exit;
  SetAsideLegacyFile(ColoringPath);
  SetAsideLegacyFile(MarkdownPath);
  ANewId := Doc.Id;
  Result := True;
end;

function DefaultThemeGroups: TArray<TColorCodingGroup>;
var
  Spec: TThemeSpec;
begin
  if TryLoadThemeSpec(cDefaultThemeId, Spec) then
    Result := Spec.FileColoring
  else
    SetLength(Result, 0);
end;

initialization
  SetColorCodingDefaultsProvider(DefaultThemeGroups);

end.
