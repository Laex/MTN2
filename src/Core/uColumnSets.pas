unit uColumnSets;

// Named sets of the optional columns of the Custom column mode. The Column modes
// menu lists them under Custom; the Custom columns dialog saves the current
// choice under a name. Sets live in columnsets.json, for example:
//   { "sets": { "Dates": { "size": true, "modified": true, "created": true,
//     "plugins": { "file": ["camera", "year"] } } } }
// "plugins" lists, per folder scheme, the plugin columns the set shows; a set
// without it leaves the plugin columns as they are.
// The file is the only source (no sets exist while it is missing) and every set
// in it can be edited, renamed or deleted.

interface

uses
  uDualPanelTypes;

type
  /// <summary>The plugin columns (ids) a set shows in the folders of one scheme.</summary>
  TSetPluginColumns = record
    Scheme: string;
    Ids: TArray<string>;
  end;

  TColumnSet = record
    Name: string;
    Config: TCustomColumnsConfig;
    /// <summary>Empty when the set says nothing about plugin columns.</summary>
    Plugins: TArray<TSetPluginColumns>;
  end;

/// <summary>The plugin columns the set shows for AScheme; False when the set
/// says nothing about that scheme.</summary>
function ColumnSetPluginIds(const ASet: TColumnSet; const AScheme: string;
  out AIds: TArray<string>): Boolean;

/// <summary>The columns a preset mode (Size, Date, Full, Created, Types) shows;
/// False for Brief and Custom.</summary>
function PresetColumnsConfig(AMode: TPanelColumnMode;
  out AConfig: TCustomColumnsConfig): Boolean;

/// <summary>All sets of the file, in alphabetical order.</summary>
function ColumnSets: TArray<TColumnSet>;

/// <summary>The set of this name (matched without regard to case).</summary>
function ColumnSetFind(const AName: string; out ASet: TColumnSet): Boolean;

/// <summary>True when both configs show the same columns.</summary>
function SameColumnsConfig(const A, B: TCustomColumnsConfig): Boolean;

/// <summary>Saves the config under AName in the file, replacing a set of that name.
/// APlugins replaces the plugin columns of its schemes; the other schemes of an
/// existing set keep theirs. False for a blank name or when the file cannot be written.</summary>
function ColumnSetSave(const AName: string; const AConfig: TCustomColumnsConfig;
  const APlugins: TArray<TSetPluginColumns> = nil): Boolean;

/// <summary>True when the file holds a set of this name.</summary>
function ColumnSetIsStored(const AName: string): Boolean;

/// <summary>Removes the set from the file. False when the file holds no such set
/// or cannot be written.</summary>
function ColumnSetDelete(const AName: string): Boolean;

/// <summary>Gives a set another name, keeping its columns. False for
/// a set not in the file, a blank new name, a name taken by another set
/// (a change of case only is fine), or when the file cannot be written.</summary>
function ColumnSetRename(const AOldName, ANewName: string): Boolean;

/// <summary>Reads and writes this file instead of the one in the settings folder.
/// An empty path goes back to the settings folder.</summary>
procedure ColumnSetsUsePath(const APath: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Generics.Collections, System.Generics.Defaults,
  uConfigLocation;

const
  cFileName = 'columnsets.json';

var
  GPath: string;

function FilePath: string;
begin
  if GPath <> '' then
    Result := GPath
  else
    Result := GetConfigFilePath(cFileName);
end;

function MakeConfig(AExt, ASize, AModified, ACreated, AAccessed, AType,
  AAttr: Boolean): TCustomColumnsConfig;
begin
  Result.ShowExt := AExt;
  Result.ShowSize := ASize;
  Result.ShowModified := AModified;
  Result.ShowCreated := ACreated;
  Result.ShowAccessed := AAccessed;
  Result.ShowType := AType;
  Result.ShowAttr := AAttr;
end;

procedure PutSet(AList: TList<TColumnSet>; const AName: string;
  const AConfig: TCustomColumnsConfig;
  const APlugins: TArray<TSetPluginColumns> = nil);
var
  I: Integer;
  S: TColumnSet;
begin
  S.Name := AName;
  S.Config := AConfig;
  S.Plugins := APlugins;
  for I := 0 to AList.Count - 1 do
    if SameText(AList[I].Name, AName) then
    begin
      AList[I] := S;
      Exit;
    end;
  AList.Add(S);
end;

function ConfigFromJson(AObj: TJSONObject): TCustomColumnsConfig;

  function Flag(const AKey: string): Boolean;
  var
    Value: TJSONValue;
  begin
    Value := AObj.GetValue(AKey);
    Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
  end;

begin
  Result := MakeConfig(Flag('ext'), Flag('size'), Flag('modified'), Flag('created'),
    Flag('accessed'), Flag('type'), Flag('attr'));
end;

function ConfigToJson(const AConfig: TCustomColumnsConfig): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ext', TJSONBool.Create(AConfig.ShowExt));
  Result.AddPair('size', TJSONBool.Create(AConfig.ShowSize));
  Result.AddPair('modified', TJSONBool.Create(AConfig.ShowModified));
  Result.AddPair('created', TJSONBool.Create(AConfig.ShowCreated));
  Result.AddPair('accessed', TJSONBool.Create(AConfig.ShowAccessed));
  Result.AddPair('type', TJSONBool.Create(AConfig.ShowType));
  Result.AddPair('attr', TJSONBool.Create(AConfig.ShowAttr));
end;

function PluginsFromJson(AObj: TJSONObject): TArray<TSetPluginColumns>;
var
  Node: TJSONValue;
  Pair: TJSONPair;
  Arr: TJSONArray;
  I, N: Integer;
begin
  SetLength(Result, 0);
  Node := AObj.GetValue('plugins');
  if not (Node is TJSONObject) then
    Exit;
  for Pair in TJSONObject(Node) do
    if Pair.JsonValue is TJSONArray then
    begin
      Arr := TJSONArray(Pair.JsonValue);
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Scheme := LowerCase(Pair.JsonString.Value);
      SetLength(Result[N].Ids, 0);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONString then
        begin
          SetLength(Result[N].Ids, Length(Result[N].Ids) + 1);
          Result[N].Ids[High(Result[N].Ids)] := Arr.Items[I].Value;
        end;
    end;
end;

function IdsToJson(const AIds: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result := TJSONArray.Create;
  for S in AIds do
    Result.Add(S);
end;

function ColumnSetPluginIds(const ASet: TColumnSet; const AScheme: string;
  out AIds: TArray<string>): Boolean;
var
  P: TSetPluginColumns;
begin
  for P in ASet.Plugins do
    if SameText(P.Scheme, AScheme) then
    begin
      AIds := P.Ids;
      Exit(True);
    end;
  AIds := nil;
  Result := False;
end;

function PresetColumnsConfig(AMode: TPanelColumnMode;
  out AConfig: TCustomColumnsConfig): Boolean;
begin
  Result := True;
  case AMode of
    pcmSize: AConfig := MakeConfig(False, True, False, False, False, False, False);
    pcmDate: AConfig := MakeConfig(False, True, True, False, False, False, False);
    pcmFull: AConfig := MakeConfig(False, True, True, False, False, False, True);
    pcmCreated: AConfig := MakeConfig(False, True, False, True, False, False, True);
    pcmTypes: AConfig := MakeConfig(True, True, False, False, False, True, True);
  else
    begin
      AConfig := MakeConfig(False, False, False, False, False, False, False);
      Result := False;
    end;
  end;
end;

procedure LoadFileSets(AList: TList<TColumnSet>);
var
  Root: TJSONValue;
  Sets: TJSONObject;
  Pair: TJSONPair;
begin
  if not TFile.Exists(FilePath) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(FilePath, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not (TJSONObject(Root).GetValue('sets') is TJSONObject) then
      Exit;
    Sets := TJSONObject(TJSONObject(Root).GetValue('sets'));
    for Pair in Sets do
      if (Trim(Pair.JsonString.Value) <> '') and (Pair.JsonValue is TJSONObject) then
        PutSet(AList, Trim(Pair.JsonString.Value),
          ConfigFromJson(TJSONObject(Pair.JsonValue)),
          PluginsFromJson(TJSONObject(Pair.JsonValue)));
  finally
    Root.Free;
  end;
end;

function LoadAll: TList<TColumnSet>;
begin
  Result := TList<TColumnSet>.Create;
  LoadFileSets(Result);
end;

function ColumnSets: TArray<TColumnSet>;
var
  List: TList<TColumnSet>;
begin
  List := LoadAll;
  try
    List.Sort(TComparer<TColumnSet>.Construct(
      function(const A, B: TColumnSet): Integer
      begin
        Result := CompareText(A.Name, B.Name);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ColumnSetFind(const AName: string; out ASet: TColumnSet): Boolean;
var
  S: TColumnSet;
begin
  for S in ColumnSets do
    if SameText(S.Name, Trim(AName)) then
    begin
      ASet := S;
      Exit(True);
    end;
  Result := False;
end;

function SameColumnsConfig(const A, B: TCustomColumnsConfig): Boolean;
begin
  Result := (A.ShowExt = B.ShowExt) and (A.ShowSize = B.ShowSize) and
    (A.ShowModified = B.ShowModified) and (A.ShowCreated = B.ShowCreated) and
    (A.ShowAccessed = B.ShowAccessed) and (A.ShowType = B.ShowType) and
    (A.ShowAttr = B.ShowAttr);
end;

// The file's JSON with a "sets" object in place, or a fresh one when the file is
// missing or unreadable. The caller frees it.
function LoadRoot(out ASets: TJSONObject): TJSONObject;
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
  if not (Result.GetValue('sets') is TJSONObject) then
  begin
    Result.RemovePair('sets').Free;
    Result.AddPair('sets', TJSONObject.Create);
  end;
  ASets := TJSONObject(Result.GetValue('sets'));
end;

function StoreRoot(ARoot: TJSONObject): Boolean;
begin
  try
    ForceDirectories(ExtractFilePath(FilePath));
    TFile.WriteAllText(FilePath, ARoot.Format(2), TEncoding.UTF8);
    Result := True;
  except
    Result := False;
  end;
end;

// Removes every pair whose name matches without regard to case.
procedure RemoveSetPairs(ASets: TJSONObject; const AName: string);
var
  I: Integer;
begin
  for I := ASets.Count - 1 downto 0 do
    if SameText(ASets.Pairs[I].JsonString.Value, AName) then
      ASets.RemovePair(ASets.Pairs[I].JsonString.Value).Free;
end;

function SchemeListed(const APlugins: TArray<TSetPluginColumns>;
  const AScheme: string): Boolean;
var
  P: TSetPluginColumns;
begin
  for P in APlugins do
    if SameText(P.Scheme, AScheme) then
      Exit(True);
  Result := False;
end;

function ColumnSetSave(const AName: string; const AConfig: TCustomColumnsConfig;
  const APlugins: TArray<TSetPluginColumns>): Boolean;
var
  Root, Sets, Obj, Plugins: TJSONObject;
  Name: string;
  Kept: TArray<TSetPluginColumns>;
  P: TSetPluginColumns;
  I: Integer;
begin
  Name := Trim(AName);
  if Name = '' then
    Exit(False);
  Root := LoadRoot(Sets);
  try
    // A set whose name differs only in case is replaced, not duplicated.
    Kept := nil;
    for I := 0 to Sets.Count - 1 do
      if SameText(Sets.Pairs[I].JsonString.Value, Name) and
         (Sets.Pairs[I].JsonValue is TJSONObject) then
        Kept := PluginsFromJson(TJSONObject(Sets.Pairs[I].JsonValue));
    RemoveSetPairs(Sets, Name);
    Obj := ConfigToJson(AConfig);
    Plugins := TJSONObject.Create;
    for P in Kept do
      if not SchemeListed(APlugins, P.Scheme) then
        Plugins.AddPair(P.Scheme, IdsToJson(P.Ids));
    for P in APlugins do
      Plugins.AddPair(P.Scheme, IdsToJson(P.Ids));
    if Plugins.Count > 0 then
      Obj.AddPair('plugins', Plugins)
    else
      Plugins.Free;
    Sets.AddPair(Name, Obj);
    Result := StoreRoot(Root);
  finally
    Root.Free;
  end;
end;

function ColumnSetIsStored(const AName: string): Boolean;
var
  Root, Sets: TJSONObject;
  I: Integer;
begin
  Result := False;
  Root := LoadRoot(Sets);
  try
    for I := 0 to Sets.Count - 1 do
      if SameText(Sets.Pairs[I].JsonString.Value, Trim(AName)) and
         (Sets.Pairs[I].JsonValue is TJSONObject) then
        Exit(True);
  finally
    Root.Free;
  end;
end;

function ColumnSetDelete(const AName: string): Boolean;
var
  Root, Sets: TJSONObject;
begin
  if not ColumnSetIsStored(AName) then
    Exit(False);
  Root := LoadRoot(Sets);
  try
    RemoveSetPairs(Sets, Trim(AName));
    Result := StoreRoot(Root);
  finally
    Root.Free;
  end;
end;

function ColumnSetRename(const AOldName, ANewName: string): Boolean;
var
  Root, Sets: TJSONObject;
  NewName, OldName: string;
  Moved: TJSONValue;
  Other: TColumnSet;
  I: Integer;
begin
  Result := False;
  OldName := Trim(AOldName);
  NewName := Trim(ANewName);
  if (NewName = '') or not ColumnSetIsStored(OldName) then
    Exit;
  if not SameText(OldName, NewName) and ColumnSetFind(NewName, Other) then
    Exit;
  Root := LoadRoot(Sets);
  try
    Moved := nil;
    for I := 0 to Sets.Count - 1 do
      if SameText(Sets.Pairs[I].JsonString.Value, OldName) then
      begin
        Moved := Sets.Pairs[I].JsonValue.Clone as TJSONValue;
        Break;
      end;
    if Moved = nil then
      Exit;
    RemoveSetPairs(Sets, OldName);
    Sets.AddPair(NewName, Moved);
    Result := StoreRoot(Root);
  finally
    Root.Free;
  end;
end;

procedure ColumnSetsUsePath(const APath: string);
begin
  GPath := APath;
end;

end.
