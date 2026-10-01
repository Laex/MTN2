unit uThemeRegistry;

{ Catalog of themes: the built-in ones, shipped inside the exe as RCDATA
  (Assets\themes\<Id>.theme.json, resource THEME_<ID>), and the user's own,
  files in <config dir>\themes\<name>.theme.json. A theme is identified by a
  stable Id persisted in session.json (TMtnSession.ThemeName): the built-in
  id, or the file name of a user theme without ".theme.json".

  Built-in themes are read-only: saving a customized theme always writes a
  new user file (SaveUserTheme), never a built-in one. This is independent
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
    BuiltIn: Boolean;
    /// <summary>Id of the theme this one extends ('' for the default theme).</summary>
    Extends: string;
    /// <summary>Full path of a user theme's file; '' for a built-in theme.</summary>
    FileName: string;
  end;

/// <summary>Built-in themes in picker order, then the user's themes by name.</summary>
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
  Winapi.Windows,
  uConfigLocation, uDataTheme, uColorCoding, uMarkdownColors;

const
  cDefaultThemeId = 'NDN';
  cMaxChainDepth = 8;
  cThemesDirName = 'themes';
  cBuiltInIds: array[0..7] of string = (
    'NDN', 'ModernUnicode', 'ASCII', 'TotalCommander', 'SolarizedDark',
    'Dracula', 'Nord', 'HighContrast');

var
  GBuiltInDocs: TArray<TThemeDoc>;
  GBuiltInLoaded: Boolean = False;

function DefaultThemeId: string;
begin
  Result := cDefaultThemeId;
end;

function IsBuiltInId(const AId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(cBuiltInIds) do
    if SameText(cBuiltInIds[I], AId) then
      Exit(True);
  Result := False;
end;

function UserThemesDirectory: string;
begin
  Result := TPath.Combine(GetConfigDirectory, cThemesDirName);
end;

function TryLoadResourceText(const AResName: string; out AText: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
begin
  AText := '';
  Result := False;
  if FindResource(HInstance, PChar(AResName), RT_RCDATA) = 0 then
    Exit;
  try
    RS := TResourceStream.Create(HInstance, AResName, RT_RCDATA);
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

function LoadBuiltInDoc(const AId: string; out ADoc: TThemeDoc): Boolean;
var
  Text, Err: string;
begin
  Result := TryLoadResourceText('THEME_' + UpperCase(AId), Text);
  // Next to the exe for programs that do not link the resources.
  if not Result then
    Result := TryReadFileText(TPath.Combine(TPath.Combine(
      ExtractFilePath(ParamStr(0)), cThemesDirName), AId + cThemeFileExt), Text);
  Result := Result and TryParseThemeDoc(Text, ADoc, Err);
  if Result then
    ADoc.Id := AId;
end;

procedure EnsureBuiltIns;
var
  I: Integer;
  Doc: TThemeDoc;
begin
  if GBuiltInLoaded then
    Exit;
  SetLength(GBuiltInDocs, 0);
  for I := 0 to High(cBuiltInIds) do
    if LoadBuiltInDoc(cBuiltInIds[I], Doc) then
    begin
      if Doc.Name = '' then
        Doc.Name := cBuiltInIds[I];
      GBuiltInDocs := GBuiltInDocs + [Doc];
    end;
  GBuiltInLoaded := True;
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
  if IsBuiltInId(AId) then
  begin
    EnsureBuiltIns;
    for I := 0 to High(GBuiltInDocs) do
      if SameText(GBuiltInDocs[I].Id, AId) then
      begin
        ADoc := GBuiltInDocs[I];
        Exit(True);
      end;
    Exit;
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
  EnsureBuiltIns;
  SetLength(Result, 0);
  for I := 0 to High(GBuiltInDocs) do
    Result := Result + [InfoOf(GBuiltInDocs[I], True, '')];

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
        Id := ExtractFileName(Files[I]);
        Id := Copy(Id, 1, Length(Id) - Length(cThemeFileExt));
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
    // The old file was merged over the default groups by name, as a theme is.
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
