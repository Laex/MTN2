unit uMaskGroups;

// Named groups of file masks. A mask written as @Name stands for the masks of the
// group Name wherever masks are accepted (select, filter, search, colour rules).
// Built-in groups can be replaced or extended in maskgroups.json, for example:
//   { "groups": { "Images": "*.jpg;*.png", "Logs": "*.log;*.log.*" } }

interface

/// <summary>Masks of the group (separated by ';'), or '' when there is no such group.
/// The name is matched without regard to case.</summary>
function MaskGroupMasks(const AName: string): string;

/// <summary>Names of all groups, built-in and from the file, in alphabetical order.</summary>
function MaskGroupNames: TArray<string>;

/// <summary>True when the name can follow '@' in a mask: not blank, no whitespace
/// and none of ';' '@' '*' '?' '\' '/' ':'.</summary>
function MaskGroupNameValid(const AName: string): Boolean;

/// <summary>True when the file defines the group (it may also replace a built-in one).</summary>
function MaskGroupInFile(const AName: string): Boolean;

/// <summary>True when the group is one of the built-in ones and the file does not replace it.</summary>
function MaskGroupIsBuiltIn(const AName: string): Boolean;

/// <summary>Saves the group to the file, replacing a group of that name. False for an
/// invalid name, blank masks or when the file cannot be written.</summary>
function MaskGroupSave(const AName, AMasks: string): Boolean;

/// <summary>A free group name for the masks: built from the first mask (the
/// extension of *.log;*.out gives log), numbered when taken.</summary>
function MaskGroupSuggestName(const AMasks: string): string;

/// <summary>Saves the masks under a name from MaskGroupSuggestName and returns the
/// name; '' when the masks are blank or already just one group reference, or
/// when the file cannot be written.</summary>
function MaskGroupSaveAuto(const AMasks: string): string;

/// <summary>Removes the group from the file; a built-in group of that name comes back
/// as it was. False when the file does not define it or cannot be written.</summary>
function MaskGroupDelete(const AName: string): Boolean;

/// <summary>Reads the groups from this file instead of the settings folder and
/// forgets what was loaded. An empty path goes back to the settings folder.</summary>
procedure MaskGroupsUsePath(const APath: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Character,
  System.Generics.Collections, System.Generics.Defaults,
  uConfigLocation;

const
  cFileName = 'maskgroups.json';
  cRecheckMs = 2000;

var
  GPath: string;
  GGroups: TDictionary<string, string>;
  GNames: TDictionary<string, string>;
  GStamp: TDateTime;
  GLoadedAt: UInt64;
  GLoaded: Boolean;

function FilePath: string;
begin
  if GPath <> '' then
    Result := GPath
  else
    Result := GetConfigFilePath(cFileName);
end;

procedure AddGroup(const AName, AMasks: string);
begin
  if (Trim(AName) = '') or (Trim(AMasks) = '') then
    Exit;
  GGroups.AddOrSetValue(LowerCase(Trim(AName)), Trim(AMasks));
  GNames.AddOrSetValue(LowerCase(Trim(AName)), Trim(AName));
end;

procedure AddBuiltIn;
begin
  AddGroup('Images', '*.jpg;*.jpeg;*.png;*.gif;*.bmp;*.webp;*.tif;*.tiff;*.svg;*.ico');
  AddGroup('Audio', '*.mp3;*.flac;*.wav;*.ogg;*.m4a;*.aac;*.wma;*.opus');
  AddGroup('Video', '*.mp4;*.mkv;*.avi;*.mov;*.wmv;*.webm;*.flv;*.m4v');
  AddGroup('Documents', '*.txt;*.md;*.pdf;*.doc;*.docx;*.xls;*.xlsx;*.ppt;*.pptx;*.odt;*.ods;*.rtf');
  AddGroup('Archives', '*.zip;*.7z;*.rar;*.tar;*.gz;*.tgz;*.bz2;*.xz;*.zst;*.cab;*.iso');
  AddGroup('Sources', '*.pas;*.dpr;*.c;*.h;*.cpp;*.hpp;*.cs;*.java;*.py;*.js;*.ts;*.go;*.rs;*.lua');
end;

procedure LoadFile(const APath: string);
var
  Root: TJSONValue;
  Groups: TJSONObject;
  Pair: TJSONPair;
begin
  if not TFile.Exists(APath) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not (TJSONObject(Root).GetValue('groups') is TJSONObject) then
      Exit;
    Groups := TJSONObject(TJSONObject(Root).GetValue('groups'));
    for Pair in Groups do
      if Pair.JsonValue is TJSONString then
        AddGroup(Pair.JsonString.Value, Pair.JsonValue.Value);
  finally
    Root.Free;
  end;
end;

procedure Reload;
var
  Path: string;
begin
  GGroups.Clear;
  GNames.Clear;
  AddBuiltIn;
  Path := FilePath;
  LoadFile(Path);
  GLoaded := True;
  GLoadedAt := TThread.GetTickCount64;
  if TFile.Exists(Path) then
    GStamp := TFile.GetLastWriteTime(Path)
  else
    GStamp := 0;
end;

procedure EnsureFresh;
var
  Path: string;
  Stamp: TDateTime;
begin
  if not GLoaded then
  begin
    Reload;
    Exit;
  end;
  if TThread.GetTickCount64 - GLoadedAt < cRecheckMs then
    Exit;
  GLoadedAt := TThread.GetTickCount64;
  Path := FilePath;
  if TFile.Exists(Path) then
    Stamp := TFile.GetLastWriteTime(Path)
  else
    Stamp := 0;
  if Stamp <> GStamp then
    Reload;
end;

function MaskGroupMasks(const AName: string): string;
begin
  EnsureFresh;
  if not GGroups.TryGetValue(LowerCase(Trim(AName)), Result) then
    Result := '';
end;

function MaskGroupNames: TArray<string>;
var
  Name: string;
  List: TList<string>;
begin
  EnsureFresh;
  List := TList<string>.Create;
  try
    for Name in GNames.Values do
      List.Add(Name);
    List.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(A, B);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function MaskGroupNameValid(const AName: string): Boolean;
var
  C: Char;
begin
  Result := Trim(AName) <> '';
  for C in Trim(AName) do
    if (C <= ' ') or CharInSet(C, [';', '@', '*', '?', '\', '/', ':']) then
      Exit(False);
end;

// Reads the file's root object, or a fresh one when the file is missing or broken.
function ReadRoot: TJSONObject;
var
  Parsed: TJSONValue;
begin
  Result := nil;
  if TFile.Exists(FilePath) then
  begin
    try
      Parsed := TJSONObject.ParseJSONValue(TFile.ReadAllText(FilePath, TEncoding.UTF8));
    except
      Parsed := nil;
    end;
    if Parsed is TJSONObject then
      Result := TJSONObject(Parsed)
    else
      Parsed.Free;
  end;
  if Result = nil then
    Result := TJSONObject.Create;
end;

function GroupsOf(ARoot: TJSONObject): TJSONObject;
begin
  if not (ARoot.GetValue('groups') is TJSONObject) then
  begin
    ARoot.RemovePair('groups').Free;
    ARoot.AddPair('groups', TJSONObject.Create);
  end;
  Result := TJSONObject(ARoot.GetValue('groups'));
end;

procedure RemoveByName(AGroups: TJSONObject; const AName: string);
var
  I: Integer;
begin
  for I := AGroups.Count - 1 downto 0 do
    if SameText(AGroups.Pairs[I].JsonString.Value, Trim(AName)) then
      AGroups.RemovePair(AGroups.Pairs[I].JsonString.Value).Free;
end;

function WriteRoot(ARoot: TJSONObject): Boolean;
begin
  try
    ForceDirectories(ExtractFilePath(FilePath));
    TFile.WriteAllText(FilePath, ARoot.Format(2), TEncoding.UTF8);
    Result := True;
  except
    Result := False;
  end;
  GLoaded := False;
end;

function MaskGroupInFile(const AName: string): Boolean;
var
  Root: TJSONObject;
  I: Integer;
  Groups: TJSONObject;
begin
  Result := False;
  Root := ReadRoot;
  try
    if not (Root.GetValue('groups') is TJSONObject) then
      Exit;
    Groups := TJSONObject(Root.GetValue('groups'));
    for I := 0 to Groups.Count - 1 do
      if SameText(Groups.Pairs[I].JsonString.Value, Trim(AName)) then
        Exit(True);
  finally
    Root.Free;
  end;
end;

function MaskGroupIsBuiltIn(const AName: string): Boolean;
const
  cBuiltIn: array[0..5] of string =
    ('Images', 'Audio', 'Video', 'Documents', 'Archives', 'Sources');
var
  S: string;
begin
  Result := False;
  if MaskGroupInFile(AName) then
    Exit;
  for S in cBuiltIn do
    if SameText(S, Trim(AName)) then
      Exit(True);
end;

function MaskGroupSave(const AName, AMasks: string): Boolean;
var
  Root: TJSONObject;
  Groups: TJSONObject;
begin
  Result := False;
  if not MaskGroupNameValid(AName) or (Trim(AMasks) = '') then
    Exit;
  Root := ReadRoot;
  try
    Groups := GroupsOf(Root);
    RemoveByName(Groups, AName);
    Groups.AddPair(Trim(AName), Trim(AMasks));
    Result := WriteRoot(Root);
  finally
    Root.Free;
  end;
end;

function MaskGroupSuggestName(const AMasks: string): string;
var
  First, Base: string;
  C: Char;
  N: Integer;
begin
  First := Trim(AMasks);
  if Pos(';', First) > 0 then
    First := Trim(Copy(First, 1, Pos(';', First) - 1));
  Base := '';
  for C in First do
    if C.IsLetterOrDigit or (C = '_') then
      Base := Base + C;
  if Base = '' then
    Base := 'Masks';
  Base := Copy(Base, 1, 16);
  Result := Base;
  N := 1;
  while MaskGroupMasks(Result) <> '' do
  begin
    Inc(N);
    Result := Base + IntToStr(N);
  end;
end;

function MaskGroupSaveAuto(const AMasks: string): string;
var
  Masks: string;
begin
  Result := '';
  Masks := Trim(AMasks);
  if (Masks = '') or ((Masks[1] = '@') and (Pos(';', Masks) = 0)) then
    Exit;
  Result := MaskGroupSuggestName(Masks);
  if not MaskGroupSave(Result, Masks) then
    Result := '';
end;

function MaskGroupDelete(const AName: string): Boolean;
var
  Root: TJSONObject;
begin
  Result := False;
  if not MaskGroupInFile(AName) then
    Exit;
  Root := ReadRoot;
  try
    RemoveByName(GroupsOf(Root), AName);
    Result := WriteRoot(Root);
  finally
    Root.Free;
  end;
end;

procedure MaskGroupsUsePath(const APath: string);
begin
  GPath := APath;
  GLoaded := False;
end;

initialization
  GGroups := TDictionary<string, string>.Create;
  GNames := TDictionary<string, string>.Create;

finalization
  GNames.Free;
  GGroups.Free;

end.
