unit uPluginServiceSettings;

{ The settings of a plugin that offers JSON-RPC services (docs/PLUGIN_SERVICES.md): one
  checkbox that lets the user stop the plugin from registering its services. A plugin
  with the option cleared registers no service, so the host never calls it for one.
  The option is the plugin setting "jsonrpc_provider"; a missing value means on.

  The dialog texts come from the plugin's own language pack, keys svc.title,
  svc.enabled, svc.ok and svc.cancel. }

interface

uses
  uPluginHostAbi;

const
  cSettingProvider = 'jsonrpc_provider';

/// <summary>False when the user cleared the option of this plugin.</summary>
function ServiceProviderEnabled(AHost: PHostApiTable; const APluginId: string): Boolean;

/// <summary>Adds the "Settings" button of the plugin that opens the option dialog; True
/// when the host can show it.</summary>
function RegisterServiceSettings(AHost: PHostApiTable; const APluginId: string): Boolean;

/// <summary>The dialog declaration (JSON) with the checkbox in the given state.</summary>
function ServiceSettingsDialogJson(const ATitle, AEnabledText, AOkText, ACancelText: string;
  AEnabled: Boolean): string;

/// <summary>True when the answer is the OK button; AEnabled is then the checkbox.</summary>
function ServiceSettingsAnswerEnabled(const AControlId, AValuesJson: string;
  out AEnabled: Boolean): Boolean;

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections;

type
  TSettingsContext = class
    Host: PHostApiTable;
    PluginId: string;
  end;

var
  GContexts: TObjectList<TSettingsContext>;

function ReadSetting(AHost: PHostApiTable; const APluginId, AKey: string): string;
var
  Id, Key: UTF8String;
  Buf: array[0..63] of AnsiChar;
begin
  Result := '';
  if (AHost = nil) or not Assigned(AHost.GetSetting) then
    Exit;
  Id := UTF8String(APluginId);
  Key := UTF8String(AKey);
  Buf[0] := #0;
  if AHost.GetSetting(PAnsiChar(Id), PAnsiChar(Key), @Buf[0], SizeOf(Buf)) >= 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function ServiceProviderEnabled(AHost: PHostApiTable; const APluginId: string): Boolean;
begin
  Result := ReadSetting(AHost, APluginId, cSettingProvider) <> '0';
end;

function Translated(AHost: PHostApiTable; const APluginId, AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(AHost.Translate) then
    Exit;
  Id := UTF8String(APluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := AHost.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function ControlJson(const AType, AId, AText: string; ACol, ARow, AWidth: Integer;
  AChecked, ADefault, ACancel: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', AType);
  if AId <> '' then
    Result.AddPair('id', AId);
  if AText <> '' then
    Result.AddPair('text', AText);
  if AType = 'checkbox' then
    Result.AddPair('checked', TJSONBool.Create(AChecked));
  if ADefault then
    Result.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    Result.AddPair('cancel', TJSONBool.Create(True));
  Result.AddPair('col', TJSONNumber.Create(ACol));
  Result.AddPair('row', TJSONNumber.Create(ARow));
  Result.AddPair('width', TJSONNumber.Create(AWidth));
  Result.AddPair('height', TJSONNumber.Create(1));
end;

function ServiceSettingsDialogJson(const ATitle, AEnabledText, AOkText, ACancelText: string;
  AEnabled: Boolean): string;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
begin
  Decl := TJSONObject.Create;
  try
    Decl.AddPair('type', 'dialog');
    Decl.AddPair('version', '2.0');
    Decl.AddPair('title', ATitle);
    Decl.AddPair('width', TJSONNumber.Create(72));
    Decl.AddPair('height', TJSONNumber.Create(9));
    Kids := TJSONArray.Create;
    Decl.AddPair('children', Kids);
    Kids.AddElement(ControlJson('checkbox', cSettingProvider, AEnabledText, 3, 2, 66,
      AEnabled, False, False));
    Kids.AddElement(ControlJson('button', 'ok', AOkText, 22, 5, 12, False, True, False));
    Kids.AddElement(ControlJson('button', 'cancel', ACancelText, 37, 5, 12, False, False, True));
    Result := Decl.ToJSON;
  finally
    Decl.Free;
  end;
end;

function ServiceSettingsAnswerEnabled(const AControlId, AValuesJson: string;
  out AEnabled: Boolean): Boolean;
var
  Root, V: TJSONValue;
begin
  Result := False;
  AEnabled := True;
  if not SameText(AControlId, 'ok') then
    Exit;
  Root := TJSONObject.ParseJSONValue(AValuesJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    V := TJSONObject(Root).GetValue(cSettingProvider);
    if V is TJSONBool then
      AEnabled := TJSONBool(V).AsBoolean
    else
      AEnabled := (V <> nil) and (SameText(V.Value, 'true') or (V.Value = '1'));
    Result := True;
  finally
    Root.Free;
  end;
end;

procedure OnAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Ctx: TSettingsContext;
  Enabled: Boolean;
  Id, Key, Value: UTF8String;
begin
  try
    Ctx := TSettingsContext(AUserData);
    if not ServiceSettingsAnswerEnabled(string(AControlId), UTF8ToString(AValuesJson), Enabled) or
       not Assigned(Ctx.Host.SetSetting) then
      Exit;
    Id := UTF8String(Ctx.PluginId);
    Key := UTF8String(cSettingProvider);
    if Enabled then
      Value := '1'
    else
      Value := '0';
    Ctx.Host.SetSetting(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Value));
  except
    // Never let an exception cross into the host.
  end;
end;

procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Ctx: TSettingsContext;
  Json, Id: UTF8String;
begin
  try
    Ctx := TSettingsContext(AUserData);
    if not Assigned(Ctx.Host.ShowDialog) then
      Exit;
    Json := UTF8String(ServiceSettingsDialogJson(
      Translated(Ctx.Host, Ctx.PluginId, 'svc.title', 'Services'),
      Translated(Ctx.Host, Ctx.PluginId, 'svc.enabled',
        'Offer this plugin as a &provider of JSON-RPC services (needs a restart)'),
      Translated(Ctx.Host, Ctx.PluginId, 'svc.ok', 'OK'),
      Translated(Ctx.Host, Ctx.PluginId, 'svc.cancel', 'Cancel'),
      ServiceProviderEnabled(Ctx.Host, Ctx.PluginId)));
    Id := UTF8String(Ctx.PluginId);
    Ctx.Host.ShowDialog(PAnsiChar(Id), PAnsiChar(Json), @OnAnswer, Ctx);
  except
    // Never let an exception cross into the host.
  end;
end;

function RegisterServiceSettings(AHost: PHostApiTable; const APluginId: string): Boolean;
var
  Ctx: TSettingsContext;
  Id: UTF8String;
begin
  Result := False;
  if (AHost = nil) or not Assigned(AHost.RegisterSettings) or not Assigned(AHost.ShowDialog) then
    Exit;
  if GContexts = nil then
    GContexts := TObjectList<TSettingsContext>.Create(True);
  Ctx := TSettingsContext.Create;
  Ctx.Host := AHost;
  Ctx.PluginId := APluginId;
  GContexts.Add(Ctx);
  Id := UTF8String(APluginId);
  AHost.RegisterSettings(PAnsiChar(Id), @OnConfigure, Ctx);
  Result := True;
end;

initialization

finalization
  GContexts.Free;

end.
