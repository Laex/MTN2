unit uDialogPresets;

{ Named sets of dialog settings kept in one JSON file: a preset is a name and
  a list of key/value pairs (control id and its text). The dialogs decide which
  keys they store; this unit only keeps them. }

interface

type
  TPresetValue = record
    Key: string;
    Value: string;
  end;
  TPresetValues = TArray<TPresetValue>;

  TDialogPresets = class
  private
    FPath: string;
    FNames: TArray<string>;
    FValues: TArray<TPresetValues>;
    function IndexOf(const AName: string): Integer;
    procedure Load;
    function Save: Boolean;
  public
    constructor Create(const APath: string);
    /// <summary>Preset names in the order they were first saved.</summary>
    function Names: TArray<string>;
    function Find(const AName: string; out AValues: TPresetValues): Boolean;
    /// <summary>Stores AValues under AName (replacing a preset of the same name,
    /// case ignored) and writes the file. False for a blank name or when the
    /// file cannot be written.</summary>
    function Put(const AName: string; const AValues: TPresetValues): Boolean;
    function Delete(const AName: string): Boolean;
  end;

procedure PresetAdd(var AValues: TPresetValues; const AKey, AValue: string);
function PresetGet(const AValues: TPresetValues; const AKey, ADefault: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON;

procedure PresetAdd(var AValues: TPresetValues; const AKey, AValue: string);
var
  N: Integer;
begin
  N := Length(AValues);
  SetLength(AValues, N + 1);
  AValues[N].Key := AKey;
  AValues[N].Value := AValue;
end;

function PresetGet(const AValues: TPresetValues; const AKey, ADefault: string): string;
var
  I: Integer;
begin
  for I := 0 to High(AValues) do
    if SameText(AValues[I].Key, AKey) then
      Exit(AValues[I].Value);
  Result := ADefault;
end;

constructor TDialogPresets.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  Load;
end;

function TDialogPresets.IndexOf(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNames) do
    if SameText(FNames[I], AName) then
      Exit(I);
  Result := -1;
end;

procedure TDialogPresets.Load;
var
  Root, Item, Vals: TJSONValue;
  Obj: TJSONObject;
  Arr: TJSONArray;
  N: Integer;
  Name: string;
  Pair: TJSONPair;
  Values: TPresetValues;
begin
  SetLength(FNames, 0);
  SetLength(FValues, 0);
  if not TFile.Exists(FPath) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(FPath, TEncoding.UTF8));
  except
    Exit;
  end;
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    Arr := TJSONObject(Root).GetValue('presets') as TJSONArray;
    if Arr = nil then
      Exit;
    for Item in Arr do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Obj := TJSONObject(Item);
      Name := Trim(Obj.GetValue<string>('name', ''));
      if (Name = '') or (IndexOf(Name) >= 0) then
        Continue;
      SetLength(Values, 0);
      Vals := Obj.GetValue('values');
      if Vals is TJSONObject then
        for Pair in TJSONObject(Vals) do
          PresetAdd(Values, Pair.JsonString.Value, Pair.JsonValue.Value);
      N := Length(FNames);
      SetLength(FNames, N + 1);
      SetLength(FValues, N + 1);
      FNames[N] := Name;
      FValues[N] := Values;
    end;
  finally
    Root.Free;
  end;
end;

function TDialogPresets.Save: Boolean;
var
  Root, Item, Vals: TJSONObject;
  Arr: TJSONArray;
  I, J: Integer;
begin
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Root.AddPair('presets', Arr);
    for I := 0 to High(FNames) do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', FNames[I]);
      Vals := TJSONObject.Create;
      for J := 0 to High(FValues[I]) do
        Vals.AddPair(FValues[I][J].Key, FValues[I][J].Value);
      Item.AddPair('values', Vals);
      Arr.AddElement(Item);
    end;
    try
      ForceDirectories(ExtractFilePath(FPath));
      TFile.WriteAllText(FPath, Root.ToJSON, TEncoding.UTF8);
      Result := True;
    except
      Result := False;
    end;
  finally
    Root.Free;
  end;
end;

function TDialogPresets.Names: TArray<string>;
begin
  Result := Copy(FNames);
end;

function TDialogPresets.Find(const AName: string; out AValues: TPresetValues): Boolean;
var
  I: Integer;
begin
  I := IndexOf(Trim(AName));
  Result := I >= 0;
  if Result then
    AValues := Copy(FValues[I])
  else
    SetLength(AValues, 0);
end;

function TDialogPresets.Put(const AName: string; const AValues: TPresetValues): Boolean;
var
  I, N: Integer;
  Name: string;
begin
  Name := Trim(AName);
  if Name = '' then
    Exit(False);
  I := IndexOf(Name);
  if I < 0 then
  begin
    N := Length(FNames);
    SetLength(FNames, N + 1);
    SetLength(FValues, N + 1);
    I := N;
  end;
  FNames[I] := Name;
  FValues[I] := Copy(AValues);
  Result := Save;
end;

function TDialogPresets.Delete(const AName: string): Boolean;
var
  I: Integer;
begin
  I := IndexOf(Trim(AName));
  if I < 0 then
    Exit(False);
  System.Delete(FNames, I, 1);
  System.Delete(FValues, I, 1);
  Result := Save;
end;

end.
