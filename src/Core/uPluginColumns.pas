unit uPluginColumns;

{ Columns a plugin adds to the file panel for the folders of its VFS scheme.
  A plugin declares them once per scheme (RegisterPanelColumns: id, title,
  width, alignment, sortable); the listing then carries a value for each id in
  every row ("extra" in the VFS listing JSON). The plugin also says which of the
  built-in columns (ext, size, modified, created, accessed, type, attr) make
  sense for its folders. Together they are the list the Columns... dialog
  offers; which of them are shown is the user's choice, kept per scheme, and a
  scheme that was never configured shows the columns declared as default.
  Main thread only. }

interface

uses
  System.SysUtils, System.Generics.Collections;

const
  cPluginColumnMinWidth = 3;
  cPluginColumnMaxWidth = 40;
  cMaxPluginColumnsPerScheme = 16;

type
  TPluginColumn = record
    Id: string;
    Title: string;
    /// <summary>Key of the title in the plugin's resource\<language>\strings.json;
    /// Title is the English text used when there is no key or no translation.</summary>
    TitleKey: string;
    /// <summary>The plugin that declared the column.</summary>
    PluginId: string;
    Width: Integer;
    AlignRight: Boolean;
    Sortable: Boolean;
    /// <summary>Shown while the user has not chosen the columns of the scheme.</summary>
    Default: Boolean;
  end;
  TPluginColumns = TArray<TPluginColumn>;

/// <summary>Declares the columns of AScheme for APluginId. AJson is either an
/// array of {"id", "title", "title_key", "width", "align": "left"|"right", "sortable",
/// "default"}, or an object {"columns": [that array], "builtin": ["size", ...]}
/// where "builtin" lists the built-in columns that apply to the scheme (absent =
/// all of them). An empty or unparsable AJson removes the declaration of the
/// scheme. Entries without an id, with a repeated id, or past the limit are skipped.</summary>
procedure SetSchemePluginColumns(const APluginId, AScheme, AJson: string);
/// <summary>Removes every column APluginId declared.</summary>
procedure RemovePluginColumns(const APluginId: string);
/// <summary>The columns declared for AScheme, in declaration order.</summary>
function SchemePluginColumns(const AScheme: string): TPluginColumns;
/// <summary>False when the plugin that declared AScheme excluded the built-in
/// column AId (ext, size, modified, created, accessed, type, attr); True for
/// every column of a scheme with no declaration.</summary>
function BuiltinColumnAvailable(const AScheme, AId: string): Boolean;
/// <summary>The title of AColumn in the program language: the plugin's
/// translation of its TitleKey, else Title.</summary>
function PluginColumnTitle(const AColumn: TPluginColumn): string;
/// <summary>The declared column AId of AScheme.</summary>
function TryFindPluginColumn(const AScheme, AId: string; out AColumn: TPluginColumn): Boolean;

/// <summary>Sets which columns of AScheme are shown (ids; unknown ids are kept
/// but ignored while no plugin declares them).</summary>
procedure SetSchemeColumnSelection(const AScheme: string; const AIds: TArray<string>);
/// <summary>True when AColumn is shown for AScheme: the user's selection, or its
/// Default flag while the scheme has no selection.</summary>
function IsPluginColumnShown(const AScheme: string; const AColumn: TPluginColumn): Boolean;
/// <summary>The shown columns of AScheme, in declaration order.</summary>
function ShownPluginColumns(const AScheme: string): TPluginColumns;

/// <summary>The selections of all schemes as {"scheme": ["id", ...]}.</summary>
function SchemeColumnSelectionsToJson: string;
procedure LoadSchemeColumnSelectionsFromJson(const AJson: string);
procedure ClearSchemeColumnSelections;

/// <summary>Scheme of AUri in lower case ('' when it has none).</summary>
function PluginColumnSchemeOf(const AUri: string): string;

/// <summary>Cell texts a plugin computes for a folder whose listing it does not
/// produce (the local file system): AJson is {"name": {"columnId": "text"}}. They
/// fill the rows the listing left without a value for that column. The cells of
/// one plugin and folder are replaced by each call; an empty AJson drops them.
/// A few folders are kept, the oldest is forgotten first.</summary>
procedure SetFolderCells(const APluginId, AFolderUri, AJson: string);
procedure RemovePluginFolderCells(const APluginId: string);
function FolderCellText(const AFolderUri, AName, AColumnId: string; out AText: string): Boolean;

implementation

uses
  System.JSON, System.Math, uVfsTypes, uPluginServices;

type
  TSchemeEntry = record
    PluginId: string;
    Scheme: string;
    Columns: TPluginColumns;
    /// <summary>False: only the ids in Builtin are available.</summary>
    BuiltinAll: Boolean;
    Builtin: TArray<string>;
  end;

var
  GSchemes: TList<TSchemeEntry>;
  GSelections: TDictionary<string, TArray<string>>;

function Schemes: TList<TSchemeEntry>;
begin
  if GSchemes = nil then
    GSchemes := TList<TSchemeEntry>.Create;
  Result := GSchemes;
end;

function Selections: TDictionary<string, TArray<string>>;
begin
  if GSelections = nil then
    GSelections := TDictionary<string, TArray<string>>.Create;
  Result := GSelections;
end;

function PluginColumnSchemeOf(const AUri: string): string;
begin
  // file:// is a built-in scheme, but plugins may add columns to local folders.
  if Copy(TrimLeft(AUri), 1, 7).ToLower = 'file://' then
    Exit('file');
  Result := LowerCase(Trim(GenericVfsSchemeOf(AUri)));
end;

function ParseColumns(const ARoot: TJSONValue): TPluginColumns;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, J, N: Integer;
  Col: TPluginColumn;
  V: TJSONValue;
  Dup: Boolean;
begin
  SetLength(Result, 0);
  if not (ARoot is TJSONArray) then
    Exit;
  Arr := TJSONArray(ARoot);
  begin
    for I := 0 to Arr.Count - 1 do
    begin
      if Length(Result) >= cMaxPluginColumnsPerScheme then
        Break;
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      Obj := TJSONObject(Arr.Items[I]);
      Col := Default(TPluginColumn);
      V := Obj.GetValue('id');
      if V is TJSONString then
        Col.Id := Trim(TJSONString(V).Value);
      if Col.Id = '' then
        Continue;
      Dup := False;
      for J := 0 to High(Result) do
        if SameText(Result[J].Id, Col.Id) then
          Dup := True;
      if Dup then
        Continue;
      V := Obj.GetValue('title');
      if V is TJSONString then
        Col.Title := TJSONString(V).Value;
      if Col.Title = '' then
        Col.Title := Col.Id;
      V := Obj.GetValue('title_key');
      if V is TJSONString then
        Col.TitleKey := Trim(TJSONString(V).Value);
      V := Obj.GetValue('width');
      if V is TJSONNumber then
        Col.Width := TJSONNumber(V).AsInt
      else
        Col.Width := 10;
      Col.Width := EnsureRange(Col.Width, cPluginColumnMinWidth, cPluginColumnMaxWidth);
      V := Obj.GetValue('align');
      Col.AlignRight := (V is TJSONString) and SameText(TJSONString(V).Value, 'right');
      V := Obj.GetValue('sortable');
      Col.Sortable := not (V is TJSONBool) or TJSONBool(V).AsBoolean;
      V := Obj.GetValue('default');
      Col.Default := not (V is TJSONBool) or TJSONBool(V).AsBoolean;
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Col;
    end;
  end;
end;

procedure ParseDeclaration(const AJson: string; out AEntry: TSchemeEntry);
var
  Root, V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  AEntry := Default(TSchemeEntry);
  AEntry.BuiltinAll := True;
  if Trim(AJson) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if Root is TJSONArray then
      AEntry.Columns := ParseColumns(Root)
    else if Root is TJSONObject then
    begin
      AEntry.Columns := ParseColumns(TJSONObject(Root).GetValue('columns'));
      V := TJSONObject(Root).GetValue('builtin');
      if V is TJSONArray then
      begin
        Arr := TJSONArray(V);
        AEntry.BuiltinAll := False;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONString then
          begin
            SetLength(AEntry.Builtin, Length(AEntry.Builtin) + 1);
            AEntry.Builtin[High(AEntry.Builtin)] := LowerCase(Trim(TJSONString(Arr.Items[I]).Value));
          end;
      end;
    end;
  finally
    Root.Free;
  end;
end;

procedure SetSchemePluginColumns(const APluginId, AScheme, AJson: string);
var
  L: TList<TSchemeEntry>;
  I: Integer;
  Entry: TSchemeEntry;
  Scheme: string;
begin
  Scheme := LowerCase(Trim(AScheme));
  if (Trim(APluginId) = '') or (Scheme = '') then
    Exit;
  L := Schemes;
  for I := L.Count - 1 downto 0 do
    if SameText(L[I].PluginId, APluginId) and (L[I].Scheme = Scheme) then
      L.Delete(I);
  ParseDeclaration(AJson, Entry);
  for I := 0 to High(Entry.Columns) do
    Entry.Columns[I].PluginId := Trim(APluginId);
  Entry.PluginId := Trim(APluginId);
  Entry.Scheme := Scheme;
  if (Length(Entry.Columns) > 0) or not Entry.BuiltinAll then
    L.Add(Entry);
end;

procedure RemovePluginColumns(const APluginId: string);
var
  L: TList<TSchemeEntry>;
  I: Integer;
begin
  L := Schemes;
  for I := L.Count - 1 downto 0 do
    if SameText(L[I].PluginId, APluginId) then
      L.Delete(I);
  RemovePluginFolderCells(APluginId);
end;

function SchemePluginColumns(const AScheme: string): TPluginColumns;
var
  I: Integer;
  Scheme: string;
begin
  SetLength(Result, 0);
  if GSchemes = nil then
    Exit;
  Scheme := LowerCase(Trim(AScheme));
  for I := 0 to GSchemes.Count - 1 do
    if GSchemes[I].Scheme = Scheme then
      Exit(GSchemes[I].Columns);
end;

function BuiltinColumnAvailable(const AScheme, AId: string): Boolean;
var
  I, J: Integer;
  Scheme: string;
begin
  Result := True;
  if GSchemes = nil then
    Exit;
  Scheme := LowerCase(Trim(AScheme));
  for I := 0 to GSchemes.Count - 1 do
    if (GSchemes[I].Scheme = Scheme) and not GSchemes[I].BuiltinAll then
    begin
      for J := 0 to High(GSchemes[I].Builtin) do
        if SameText(GSchemes[I].Builtin[J], AId) then
          Exit(True);
      Exit(False);
    end;
end;

function PluginColumnTitle(const AColumn: TPluginColumn): string;
begin
  Result := AColumn.Title;
  if (AColumn.TitleKey <> '') and (AColumn.PluginId <> '') then
    Result := PluginTranslate(AColumn.PluginId, AColumn.TitleKey, AColumn.Title);
end;

function TryFindPluginColumn(const AScheme, AId: string; out AColumn: TPluginColumn): Boolean;
var
  Cols: TPluginColumns;
  I: Integer;
begin
  Cols := SchemePluginColumns(AScheme);
  for I := 0 to High(Cols) do
    if SameText(Cols[I].Id, AId) then
    begin
      AColumn := Cols[I];
      Exit(True);
    end;
  AColumn := Default(TPluginColumn);
  Result := False;
end;

procedure SetSchemeColumnSelection(const AScheme: string; const AIds: TArray<string>);
begin
  Selections.AddOrSetValue(LowerCase(Trim(AScheme)), Copy(AIds));
end;

function IsPluginColumnShown(const AScheme: string; const AColumn: TPluginColumn): Boolean;
var
  Ids: TArray<string>;
  I: Integer;
begin
  if (GSelections = nil) or not GSelections.TryGetValue(LowerCase(Trim(AScheme)), Ids) then
    Exit(AColumn.Default);
  for I := 0 to High(Ids) do
    if SameText(Ids[I], AColumn.Id) then
      Exit(True);
  Result := False;
end;

function ShownPluginColumns(const AScheme: string): TPluginColumns;
var
  Cols: TPluginColumns;
  I, N: Integer;
begin
  SetLength(Result, 0);
  Cols := SchemePluginColumns(AScheme);
  for I := 0 to High(Cols) do
    if IsPluginColumnShown(AScheme, Cols[I]) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Cols[I];
    end;
end;

function SchemeColumnSelectionsToJson: string;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Pair: TPair<string, TArray<string>>;
  S: string;
begin
  Obj := TJSONObject.Create;
  try
    if GSelections <> nil then
      for Pair in GSelections do
      begin
        Arr := TJSONArray.Create;
        for S in Pair.Value do
          Arr.Add(S);
        Obj.AddPair(Pair.Key, Arr);
      end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure ClearSchemeColumnSelections;
begin
  if GSelections <> nil then
    GSelections.Clear;
end;

procedure LoadSchemeColumnSelectionsFromJson(const AJson: string);
var
  Root: TJSONValue;
  Pair: TJSONPair;
  Arr: TJSONArray;
  Ids: TArray<string>;
  I: Integer;
begin
  ClearSchemeColumnSelections;
  if Trim(AJson) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Root) do
    begin
      if not (Pair.JsonValue is TJSONArray) then
        Continue;
      Arr := TJSONArray(Pair.JsonValue);
      SetLength(Ids, 0);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONString then
        begin
          SetLength(Ids, Length(Ids) + 1);
          Ids[High(Ids)] := TJSONString(Arr.Items[I]).Value;
        end;
      SetSchemeColumnSelection(Pair.JsonString.Value, Ids);
    end;
  finally
    Root.Free;
  end;
end;

const
  cMaxCellFolders = 8;
  cMaxCellNames = 20000;

type
  TFolderCells = class
    PluginId: string;
    Key: string;
    // name -> (column id -> text)
    Names: TDictionary<string, TDictionary<string, string>>;
    constructor Create;
    destructor Destroy; override;
  end;

var
  GCells: TObjectList<TFolderCells>;

constructor TFolderCells.Create;
begin
  inherited Create;
  Names := TDictionary<string, TDictionary<string, string>>.Create;
end;

destructor TFolderCells.Destroy;
var
  D: TDictionary<string, string>;
begin
  for D in Names.Values do
    D.Free;
  Names.Free;
  inherited;
end;

function CellFolderKey(const AUri: string): string;
begin
  Result := LowerCase(AUri);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function CellName(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 0) and (Result[Length(Result)] = '/') then
    SetLength(Result, Length(Result) - 1);
end;

procedure SetFolderCells(const APluginId, AFolderUri, AJson: string);
var
  Key: string;
  I: Integer;
  Root: TJSONValue;
  Folder: TFolderCells;
  Pair, CellPair: TJSONPair;
  Cells: TDictionary<string, string>;
begin
  Key := CellFolderKey(AFolderUri);
  if (Trim(APluginId) = '') or (Key = '') then
    Exit;
  if GCells = nil then
    GCells := TObjectList<TFolderCells>.Create(True);
  for I := GCells.Count - 1 downto 0 do
    if (GCells[I].Key = Key) and (GCells[I].PluginId = APluginId) then
      GCells.Delete(I);
  if Trim(AJson) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Folder := TFolderCells.Create;
    Folder.PluginId := APluginId;
    Folder.Key := Key;
    for Pair in TJSONObject(Root) do
    begin
      if (Folder.Names.Count >= cMaxCellNames) or not (Pair.JsonValue is TJSONObject) then
        Continue;
      Cells := TDictionary<string, string>.Create;
      for CellPair in TJSONObject(Pair.JsonValue) do
        if CellPair.JsonValue is TJSONString then
          Cells.AddOrSetValue(CellPair.JsonString.Value, TJSONString(CellPair.JsonValue).Value);
      Folder.Names.AddOrSetValue(CellName(Pair.JsonString.Value), Cells);
    end;
    GCells.Add(Folder);
    while GCells.Count > cMaxCellFolders do
      GCells.Delete(0);
  finally
    Root.Free;
  end;
end;

procedure RemovePluginFolderCells(const APluginId: string);
var
  I: Integer;
begin
  if GCells = nil then
    Exit;
  for I := GCells.Count - 1 downto 0 do
    if GCells[I].PluginId = APluginId then
      GCells.Delete(I);
end;

function FolderCellText(const AFolderUri, AName, AColumnId: string; out AText: string): Boolean;
var
  Key: string;
  I: Integer;
  Cells: TDictionary<string, string>;
begin
  Result := False;
  AText := '';
  if (GCells = nil) or (GCells.Count = 0) then
    Exit;
  Key := CellFolderKey(AFolderUri);
  for I := GCells.Count - 1 downto 0 do
    if (GCells[I].Key = Key) and GCells[I].Names.TryGetValue(CellName(AName), Cells) and
       Cells.TryGetValue(AColumnId, AText) then
      Exit(True);
end;

initialization

finalization
  GCells.Free;
  GSchemes.Free;
  GSelections.Free;

end.
