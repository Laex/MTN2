unit uRowDecorations;

{ Name colors that plugins put on the rows of a folder (git status of the files,
  for one). A plugin hands over the colors of one folder as JSON; the panel list
  asks for the color of a row by folder and name while it draws. Main thread
  only. }

interface

uses
  System.UITypes;

/// <summary>Replaces the colors a plugin set for AFolderUri. AJson maps a row name
/// to a role ("ok", "warn", "error", "info", "accent", "neutral") or to "#RRGGBB";
/// an empty object or '' forgets the folder. Returns False for bad arguments.</summary>
function RowDecorationsSet(const APluginId, AFolderUri, AJson: string): Boolean;

/// <summary>Forgets everything the plugin set.</summary>
procedure RowDecorationsClearPlugin(const APluginId: string);

/// <summary>The name color for the row AName of AFolderUri; False when no plugin
/// colors it.</summary>
function RowDecorationColor(const AFolderUri, AName: string; out AColor: TAlphaColor): Boolean;

/// <summary>True when any folder has colors (a cheap check before per-row lookups).</summary>
function RowDecorationsAny: Boolean;

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections;

type
  TFolderMarks = class
    PluginId: string;
    Key: string;
    Names: TDictionary<string, TAlphaColor>;
    constructor Create;
    destructor Destroy; override;
  end;

const
  cMaxFolders = 8;
  cMaxNames = 20000;

var
  GFolders: TObjectList<TFolderMarks>;

constructor TFolderMarks.Create;
begin
  inherited Create;
  Names := TDictionary<string, TAlphaColor>.Create;
end;

destructor TFolderMarks.Destroy;
begin
  Names.Free;
  inherited;
end;

function FolderKey(const AUri: string): string;
begin
  Result := LowerCase(AUri);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function RoleColor(const AValue: string; out AColor: TAlphaColor): Boolean;
var
  V: Integer;
begin
  Result := True;
  if SameText(AValue, 'ok') then
    AColor := $FF43A047
  else if SameText(AValue, 'warn') then
    AColor := $FFE0A000
  else if SameText(AValue, 'error') then
    AColor := $FFE53935
  else if SameText(AValue, 'info') then
    AColor := $FF42A5F5
  else if SameText(AValue, 'accent') then
    AColor := $FFAB47BC
  else if SameText(AValue, 'neutral') then
    AColor := $FF9E9E9E
  else if (Length(AValue) = 7) and (AValue[1] = '#') and TryStrToInt('$' + Copy(AValue, 2, 6), V) then
    AColor := TAlphaColor($FF000000 or Cardinal(V))
  else
  begin
    AColor := 0;
    Result := False;
  end;
end;

function IndexOfFolder(const APluginId, AKey: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GFolders.Count - 1 do
    if (GFolders[I].Key = AKey) and (GFolders[I].PluginId = APluginId) then
      Exit(I);
  Result := -1;
end;

function RowDecorationsSet(const APluginId, AFolderUri, AJson: string): Boolean;
var
  Root: TJSONValue;
  Marks: TFolderMarks;
  Pair: TJSONPair;
  Color: TAlphaColor;
  Key: string;
  I: Integer;
begin
  Result := (APluginId <> '') and (AFolderUri <> '');
  if not Result then
    Exit;
  Key := FolderKey(AFolderUri);
  I := IndexOfFolder(APluginId, Key);
  Root := nil;
  if Trim(AJson) <> '' then
    Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) or (TJSONObject(Root).Count = 0) then
    begin
      if I >= 0 then
        GFolders.Delete(I);
      Exit;
    end;
    Marks := TFolderMarks.Create;
    try
      Marks.PluginId := APluginId;
      Marks.Key := Key;
      for Pair in TJSONObject(Root) do
      begin
        if Marks.Names.Count >= cMaxNames then
          Break;
        if (Pair.JsonValue is TJSONString) and RoleColor(Pair.JsonValue.Value, Color) then
          Marks.Names.AddOrSetValue(LowerCase(Pair.JsonString.Value), Color);
      end;
    except
      Marks.Free;
      raise;
    end;
    if I >= 0 then
      GFolders.Delete(I)
    else if GFolders.Count >= cMaxFolders then
      GFolders.Delete(0);
    GFolders.Add(Marks);
  finally
    Root.Free;
  end;
end;

procedure RowDecorationsClearPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := GFolders.Count - 1 downto 0 do
    if GFolders[I].PluginId = APluginId then
      GFolders.Delete(I);
end;

function RowDecorationsAny: Boolean;
begin
  Result := GFolders.Count > 0;
end;

function RowDecorationColor(const AFolderUri, AName: string; out AColor: TAlphaColor): Boolean;
var
  Key, Name: string;
  I: Integer;
begin
  AColor := 0;
  Result := False;
  if (GFolders.Count = 0) or (AName = '') then
    Exit;
  Key := FolderKey(AFolderUri);
  Name := LowerCase(AName);
  for I := GFolders.Count - 1 downto 0 do
    if (GFolders[I].Key = Key) and GFolders[I].Names.TryGetValue(Name, AColor) then
      Exit(True);
end;

initialization
  GFolders := TObjectList<TFolderMarks>.Create(True);

finalization
  FreeAndNil(GFolders);

end.
