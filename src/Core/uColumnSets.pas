unit uColumnSets;

// Named sets of the optional columns of the Custom column mode. The Column modes
// menu lists them under Custom; the Custom columns dialog saves the current
// choice under a name. Sets live in columnsets.json, for example:
//   { "sets": { "Dates": { "size": true, "modified": true, "created": true } } }
// Built-in sets can be replaced by a set of the same name from the file.

interface

uses
  uPanelColumns;

type
  TColumnSet = record
    Name: string;
    Config: TCustomColumnsConfig;
  end;

/// <summary>All sets, built-in ones and those from the file, in alphabetical order.</summary>
function ColumnSets: TArray<TColumnSet>;

/// <summary>The set of this name (matched without regard to case).</summary>
function ColumnSetFind(const AName: string; out ASet: TColumnSet): Boolean;

/// <summary>True when both configs show the same columns.</summary>
function SameColumnsConfig(const A, B: TCustomColumnsConfig): Boolean;

/// <summary>Saves the config under AName in the file, replacing a set of that name.
/// False for a blank name or when the file cannot be written.</summary>
function ColumnSetSave(const AName: string; const AConfig: TCustomColumnsConfig): Boolean;

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
  const AConfig: TCustomColumnsConfig);
var
  I: Integer;
  S: TColumnSet;
begin
  S.Name := AName;
  S.Config := AConfig;
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
  begin
    Result := (AObj.GetValue(AKey) is TJSONBool) and
      TJSONBool(AObj.GetValue(AKey)).AsBoolean;
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
          ConfigFromJson(TJSONObject(Pair.JsonValue)));
  finally
    Root.Free;
  end;
end;

function LoadAll: TList<TColumnSet>;
begin
  Result := TList<TColumnSet>.Create;
  PutSet(Result, 'Minimal', MakeConfig(False, True, False, False, False, False, False));
  PutSet(Result, 'Dates', MakeConfig(False, True, True, True, True, False, False));
  PutSet(Result, 'Technical', MakeConfig(True, True, True, False, False, True, True));
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

function ColumnSetSave(const AName: string; const AConfig: TCustomColumnsConfig): Boolean;
var
  Root, Sets: TJSONObject;
  Parsed: TJSONValue;
  Name: string;
  I: Integer;
begin
  Result := False;
  Name := Trim(AName);
  if Name = '' then
    Exit;
  Root := nil;
  if TFile.Exists(FilePath) then
  begin
    try
      Parsed := TJSONObject.ParseJSONValue(TFile.ReadAllText(FilePath, TEncoding.UTF8));
    except
      Parsed := nil;
    end;
    if Parsed is TJSONObject then
      Root := TJSONObject(Parsed)
    else
      Parsed.Free;
  end;
  if Root = nil then
    Root := TJSONObject.Create;
  try
    if not (Root.GetValue('sets') is TJSONObject) then
    begin
      Root.RemovePair('sets').Free;
      Root.AddPair('sets', TJSONObject.Create);
    end;
    Sets := TJSONObject(Root.GetValue('sets'));
    // A set whose name differs only in case is replaced, not duplicated.
    for I := Sets.Count - 1 downto 0 do
      if SameText(Sets.Pairs[I].JsonString.Value, Name) then
        Sets.RemovePair(Sets.Pairs[I].JsonString.Value).Free;
    Sets.AddPair(Name, ConfigToJson(AConfig));
    try
      ForceDirectories(ExtractFilePath(FilePath));
      TFile.WriteAllText(FilePath, Root.Format(2), TEncoding.UTF8);
      Result := True;
    except
      Result := False;
    end;
  finally
    Root.Free;
  end;
end;

procedure ColumnSetsUsePath(const APath: string);
begin
  GPath := APath;
end;

end.
