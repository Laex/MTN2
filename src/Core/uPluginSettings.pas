unit uPluginSettings;

{ Settings of plugins: where a plugin keeps its values and how the user reaches
  its settings dialog.

  Storage: each plugin has a small key/value store (string -> string) that the
  host keeps in plugin-settings-<id>.json in the settings folder, so the values
  travel with the other settings (export / import, portable mode) and survive
  an update of the plugin. A plugin reads and writes it through the host API;
  it never needs a path of its own.

  Settings dialog: a plugin that has settings registers a configure handler.
  The Plugins dialog (Options > Plugins) then offers "Settings" for it and
  calls the handler, which shows the plugin's dialog (ShowDialog, see
  uPluginUi.pas) and stores what the user chose. Main thread only. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  IPluginSettings = interface
    ['{6D3A9E52-1B7C-4F80-A5D4-2C8E0F7B9A13}']
    /// <summary>Registers the handler that shows the settings dialog of APluginId.</summary>
    procedure RegisterConfigure(const APluginId: string; AHandler: TProc);
    function HasConfigure(const APluginId: string): Boolean;
    /// <summary>Runs the handler of APluginId. False when it has none or it raised.</summary>
    function TryConfigure(const APluginId: string): Boolean;
    /// <summary>Value of AKey; False when the key was never set.</summary>
    function TryGetValue(const APluginId, AKey: string; out AValue: string): Boolean;
    /// <summary>Stores AValue under AKey and writes the plugin's file. An empty
    /// key is ignored. False when the file could not be written (the value
    /// still holds for this run).</summary>
    function SetValue(const APluginId, AKey, AValue: string): Boolean;
    /// <summary>Drops the configure handler of APluginId (not its stored values).</summary>
    procedure UnregisterPlugin(const APluginId: string);
  end;

function PluginSettings: IPluginSettings;

/// <summary>Folder of the plugin settings files; '' (the default) is the
/// settings folder of the program. The tests point it at a scratch folder.</summary>
procedure SetPluginSettingsDirectory(const ADir: string);

implementation

uses
  System.Classes, System.IOUtils, System.JSON, uConfigLocation;

type
  TConfigureEntry = record
    PluginId: string;
    Handler: TProc;
  end;

  TPluginSettings = class(TInterfacedObject, IPluginSettings)
  private
    FConfigure: TList<TConfigureEntry>;
    FValues: TObjectDictionary<string, TDictionary<string, string>>;
    function ValuesOf(const APluginId: string; ACreate: Boolean): TDictionary<string, string>;
    function FileOf(const APluginId: string): string;
    procedure Load(const APluginId: string; AInto: TDictionary<string, string>);
    function Save(const APluginId: string; AFrom: TDictionary<string, string>): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterConfigure(const APluginId: string; AHandler: TProc);
    function HasConfigure(const APluginId: string): Boolean;
    function TryConfigure(const APluginId: string): Boolean;
    function TryGetValue(const APluginId, AKey: string; out AValue: string): Boolean;
    function SetValue(const APluginId, AKey, AValue: string): Boolean;
    procedure UnregisterPlugin(const APluginId: string);
  end;

var
  GSettings: IPluginSettings;
  GDirectory: string;

procedure SetPluginSettingsDirectory(const ADir: string);
begin
  GDirectory := ADir;
  // Values read from the previous folder do not apply to the new one.
  GSettings := nil;
end;

function SafeFileId(const APluginId: string): string;
var
  C: Char;
begin
  Result := '';
  for C in LowerCase(Trim(APluginId)) do
    if CharInSet(C, ['a'..'z', '0'..'9', '.', '_', '-']) then
      Result := Result + C
    else
      Result := Result + '_';
end;

constructor TPluginSettings.Create;
begin
  inherited Create;
  FConfigure := TList<TConfigureEntry>.Create;
  FValues := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
end;

destructor TPluginSettings.Destroy;
begin
  FValues.Free;
  FConfigure.Free;
  inherited Destroy;
end;

function TPluginSettings.FileOf(const APluginId: string): string;
var
  Name: string;
begin
  Name := 'plugin-settings-' + SafeFileId(APluginId) + '.json';
  if GDirectory <> '' then
    Result := TPath.Combine(GDirectory, Name)
  else
    Result := GetConfigFilePath(Name);
end;

procedure TPluginSettings.Load(const APluginId: string; AInto: TDictionary<string, string>);
var
  Root: TJSONValue;
  Pair: TJSONPair;
  Path: string;
begin
  Path := FileOf(APluginId);
  if not TFile.Exists(Path) then
    Exit;
  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
  except
    Exit;
  end;
  try
    if Root is TJSONObject then
      for Pair in TJSONObject(Root) do
        if Pair.JsonValue is TJSONString then
          AInto.AddOrSetValue(Pair.JsonString.Value, TJSONString(Pair.JsonValue).Value);
  finally
    Root.Free;
  end;
end;

function TPluginSettings.Save(const APluginId: string; AFrom: TDictionary<string, string>): Boolean;
var
  Root: TJSONObject;
  Pair: TPair<string, string>;
  Path: string;
begin
  Result := False;
  Path := FileOf(APluginId);
  Root := TJSONObject.Create;
  try
    for Pair in AFrom do
      Root.AddPair(Pair.Key, Pair.Value);
    try
      TDirectory.CreateDirectory(ExtractFilePath(Path));
      TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
      Result := True;
    except
      // An unwritable settings folder leaves the value for this run only.
    end;
  finally
    Root.Free;
  end;
end;

function TPluginSettings.ValuesOf(const APluginId: string;
  ACreate: Boolean): TDictionary<string, string>;
var
  Key: string;
begin
  Key := LowerCase(Trim(APluginId));
  if FValues.TryGetValue(Key, Result) then
    Exit;
  Result := nil;
  if not ACreate and not TFile.Exists(FileOf(APluginId)) then
    Exit;
  Result := TDictionary<string, string>.Create;
  Load(APluginId, Result);
  FValues.Add(Key, Result);
end;

procedure TPluginSettings.RegisterConfigure(const APluginId: string; AHandler: TProc);
var
  E: TConfigureEntry;
  I: Integer;
begin
  E.PluginId := Trim(APluginId);
  E.Handler := AHandler;
  if (E.PluginId = '') or not Assigned(AHandler) then
    Exit;
  for I := 0 to FConfigure.Count - 1 do
    if SameText(FConfigure[I].PluginId, E.PluginId) then
    begin
      FConfigure[I] := E;
      Exit;
    end;
  FConfigure.Add(E);
end;

function TPluginSettings.HasConfigure(const APluginId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to FConfigure.Count - 1 do
    if SameText(FConfigure[I].PluginId, Trim(APluginId)) then
      Exit(True);
  Result := False;
end;

function TPluginSettings.TryConfigure(const APluginId: string): Boolean;
var
  I: Integer;
  Handler: TProc;
begin
  for I := 0 to FConfigure.Count - 1 do
    if SameText(FConfigure[I].PluginId, Trim(APluginId)) then
    begin
      Handler := FConfigure[I].Handler;
      try
        Handler();
        Exit(True);
      except
        Exit(False);
      end;
    end;
  Result := False;
end;

function TPluginSettings.TryGetValue(const APluginId, AKey: string; out AValue: string): Boolean;
var
  Values: TDictionary<string, string>;
begin
  AValue := '';
  Values := ValuesOf(APluginId, False);
  Result := (Values <> nil) and Values.TryGetValue(AKey, AValue);
end;

function TPluginSettings.SetValue(const APluginId, AKey, AValue: string): Boolean;
var
  Values: TDictionary<string, string>;
begin
  Result := False;
  if (Trim(APluginId) = '') or (AKey = '') then
    Exit;
  Values := ValuesOf(APluginId, True);
  Values.AddOrSetValue(AKey, AValue);
  Result := Save(APluginId, Values);
end;

procedure TPluginSettings.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FConfigure.Count - 1 downto 0 do
    if SameText(FConfigure[I].PluginId, Trim(APluginId)) then
      FConfigure.Delete(I);
end;

function PluginSettings: IPluginSettings;
begin
  if GSettings = nil then
    GSettings := TPluginSettings.Create;
  Result := GSettings;
end;

initialization

finalization
  GSettings := nil;

end.
