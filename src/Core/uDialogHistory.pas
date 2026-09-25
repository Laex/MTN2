unit uDialogHistory;

{ Per-field input history for dialog inputs (FAR-style: masks, search text,
  copy destination, ...). A dckInput with a History key shows ↓ at its right
  edge; Ctrl+Down / Alt+Down or a click on ↓ drops the list down (the same
  popup as dckDropDown, TDialogHost). TDialogHost fills the list from here on
  Open and adds every non-empty history field when the dialog is accepted.

  Newest first, no duplicates (case-insensitive, like Windows names and
  masks), cDialogHistoryMax entries per key. Stored as one JSON object,
  "<key>": ["newest", ...], in <config>\dialoghistory.json; a
  missing or corrupt file means empty history, never a startup error. }

interface

const
  cDialogHistoryMax = 20;

function DialogHistoryItems(const AKey: string): TArray<string>;
/// <summary>Moves AValue to the top of AKey's list (blank values ignored)
/// and saves the file.</summary>
procedure DialogHistoryAdd(const AKey, AValue: string);
procedure DialogHistoryRemove(const AKey, AValue: string);
/// <summary>Tests: use APath instead of the config folder file and reload
/// from it ('' = back to the default file).</summary>
procedure DialogHistoryUseFile(const APath: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.Generics.Collections,
  uConfigLocation;

var
  GLoaded: Boolean;
  GPath: string;
  GLists: TDictionary<string, TArray<string>>;

function HistoryPath: string;
begin
  if GPath <> '' then
    Result := GPath
  else
    Result := GetConfigFilePath('dialoghistory.json');
end;

procedure Load;
var
  RootVal: TJSONValue;
  Pair: TJSONPair;
  Arr: TJSONArray;
  Items: TArray<string>;
  I: Integer;
  Path: string;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  if GLists = nil then
    GLists := TDictionary<string, TArray<string>>.Create
  else
    GLists.Clear;
  Path := HistoryPath;
  if not TFile.Exists(Path) then
    Exit;
  try
    RootVal := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if not (RootVal is TJSONObject) then
      Exit;
    for Pair in TJSONObject(RootVal) do
    begin
      if not (Pair.JsonValue is TJSONArray) then
        Continue;
      Arr := TJSONArray(Pair.JsonValue);
      SetLength(Items, 0);
      for I := 0 to Arr.Count - 1 do
        if (Arr.Items[I] is TJSONString) and (Length(Items) < cDialogHistoryMax) then
          Items := Items + [TJSONString(Arr.Items[I]).Value];
      GLists.AddOrSetValue(LowerCase(Pair.JsonString.Value), Items);
    end;
  finally
    RootVal.Free;
  end;
end;

procedure Save;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Key, S, Path: string;
begin
  Root := TJSONObject.Create;
  try
    try
      for Key in GLists.Keys do
      begin
        Arr := TJSONArray.Create;
        for S in GLists[Key] do
          Arr.Add(S);
        Root.AddPair(Key, Arr);
      end;
      Path := HistoryPath;
      if ExtractFilePath(Path) <> '' then
        ForceDirectories(ExtractFilePath(Path));
      TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
    except
      { history is a convenience: a failed write is not an error }
    end;
  finally
    Root.Free;
  end;
end;

function Without(const AItems: TArray<string>; const AValue: string): TArray<string>;
var
  S: string;
begin
  SetLength(Result, 0);
  for S in AItems do
    if not SameText(S, AValue) then
      Result := Result + [S];
end;

function DialogHistoryItems(const AKey: string): TArray<string>;
begin
  Load;
  if (AKey = '') or not GLists.TryGetValue(LowerCase(AKey), Result) then
    SetLength(Result, 0);
end;

procedure DialogHistoryAdd(const AKey, AValue: string);
var
  Items: TArray<string>;
begin
  if (AKey = '') or (Trim(AValue) = '') then
    Exit;
  Items := [AValue] + Without(DialogHistoryItems(AKey), AValue);
  if Length(Items) > cDialogHistoryMax then
    SetLength(Items, cDialogHistoryMax);
  GLists.AddOrSetValue(LowerCase(AKey), Items);
  Save;
end;

procedure DialogHistoryRemove(const AKey, AValue: string);
begin
  if AKey = '' then
    Exit;
  GLists.AddOrSetValue(LowerCase(AKey), Without(DialogHistoryItems(AKey), AValue));
  Save;
end;

procedure DialogHistoryUseFile(const APath: string);
begin
  GPath := APath;
  GLoaded := False;
  Load;
end;

initialization

finalization
  GLists.Free;

end.
