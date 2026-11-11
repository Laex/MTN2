library ScreenSaverPlugin;

{ Native MTN2 plugin: the screensaver pictures that live in the plugin's
  savers folder. Each library there is one picture (see uSaverModules for the
  contract); the plugin registers every one with the host, which shows the
  chosen picture after the idle time. The plugin loads the libraries at
  start and keeps them until it is unloaded. }

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uSaverModules in 'uSaverModules.pas';

const
  cPluginId = 'mtn.screensaver';
  cMinHostAbi = 10;

type
  /// <summary>One registered picture and the instance it runs while the saver is on.</summary>
  TSaverSlot = class
  public
    Module: ISaverModule;
    Info: TSaverModuleInfo;
    Instance: Int64;
    Cols, Rows: Int64;
    Seed: Int64;
  end;

var
  GHostApi: THostApiTable;
  GSlots: TObjectList<TSaverSlot>;
  GCallbacks: TSaverCallbacks;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function CbTickMs(AUserData: Pointer): Int64; cdecl;
begin
  Result := TSaverSlot(AUserData).Info.TickMs;
end;

function CbPrepare(AUserData: Pointer): Int64; cdecl;
var
  Slot: TSaverSlot;
begin
  Slot := TSaverSlot(AUserData);
  // The window size is not known yet: the first Draw opens the instance.
  Slot.Instance := 0;
  Slot.Cols := 0;
  Slot.Rows := 0;
  Slot.Seed := Int64(TThread.GetTickCount and $7FFFFFFF);
  Result := 0;
end;

procedure CbAdvance(AUserData: Pointer; ADeltaMs: Int64); cdecl;
var
  Slot: TSaverSlot;
begin
  Slot := TSaverSlot(AUserData);
  if Slot.Instance <> 0 then
    Slot.Module.Advance(Slot.Instance, ADeltaMs);
end;

/// <summary>Opens the instance on the first frame and tells it when the size
/// changes. The size is in cells for a text frame and in pixels for a pixel
/// frame; a host draws in one of the two for as long as the saver runs.</summary>
function EnsureInstance(ASlot: TSaverSlot; ACols, ARows: Int64): Boolean;
begin
  if ASlot.Instance = 0 then
  begin
    ASlot.Instance := ASlot.Module.Open(ACols, ARows, ASlot.Seed);
    if ASlot.Instance = 0 then
      Exit(False);
    ASlot.Cols := ACols;
    ASlot.Rows := ARows;
  end
  else if (ACols <> ASlot.Cols) or (ARows <> ASlot.Rows) then
  begin
    ASlot.Module.Resize(ASlot.Instance, ACols, ARows);
    ASlot.Cols := ACols;
    ASlot.Rows := ARows;
  end;
  Result := True;
end;

function CbDraw(AUserData: Pointer; ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
var
  Slot: TSaverSlot;
begin
  Result := -1;
  Slot := TSaverSlot(AUserData);
  if EnsureInstance(Slot, ACols, ARows) and
     Slot.Module.DrawText(Slot.Instance, ACols, ARows, ACells) then
    Result := 0;
end;

function CbDrawPixels(AUserData: Pointer; AWidth, AHeight: Int64; APixels: PByte): Int64; cdecl;
var
  Slot: TSaverSlot;
begin
  Result := -1;
  Slot := TSaverSlot(AUserData);
  if EnsureInstance(Slot, AWidth, AHeight) and
     Slot.Module.DrawPixels(Slot.Instance, AWidth, AHeight, APixels) then
    Result := 0;
end;

procedure CbFinish(AUserData: Pointer); cdecl;
var
  Slot: TSaverSlot;
begin
  Slot := TSaverSlot(AUserData);
  if Slot.Instance <> 0 then
  begin
    Slot.Module.Close(Slot.Instance);
    Slot.Instance := 0;
  end;
end;

function ModulesFolder: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(GetModuleName(HInstance))) +
    cSaverModulesFolder;
end;

/// <summary>The host's screensaver choice as a JSON object, or nil.</summary>
function ReadHostChoice: TJSONObject;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := nil;
  if not Assigned(GHostApi.SaverGetSettings) then
    Exit;
  SetLength(Buf, 16384);
  Len := GHostApi.SaverGetSettings(PAnsiChar(Buf), Length(Buf));
  if Len < 0 then
    Exit;
  SetLength(Buf, Len);
  Result := TJSONObject.ParseJSONValue(UTF8ToString(Buf)) as TJSONObject;
end;

function MinutesCaption(AMinutes: Integer): string;
begin
  if AMinutes = 0 then
    Result := Tr('dlg.never', 'Never')
  else
    Result := IntToStr(AMinutes);
end;

function JsonText(AObj: TJSONObject; const AKey: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AKey);
  if V = nil then
    Result := ''
  else
    Result := V.Value;
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth: Integer; ADefault: Boolean = False; ACancel: Boolean = False;
  AChecked: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if AType = 'checkbox' then
    O.AddPair('checked', TJSONBool.Create(AChecked));
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

procedure AddDropDown(AChildren: TJSONArray; const AId: string; AItems: TStrings;
  ASelected, ACol, ARow, AWidth: Integer);
var
  O: TJSONObject;
  Items: TJSONArray;
  I: Integer;
begin
  Items := TJSONArray.Create;
  for I := 0 to AItems.Count - 1 do
    Items.Add(AItems[I]);
  O := TJSONObject.Create;
  O.AddPair('type', 'dropdown');
  O.AddPair('id', AId);
  O.AddPair('items', Items);
  O.AddPair('selected', TJSONNumber.Create(ASelected));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

/// <summary>Applies the choices of the settings dialog; the captions of the
/// drop-downs are matched against the host's current lists.</summary>
procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Answer: TJSONValue;
  Host: TJSONObject;
  List, Choices: TJSONArray;
  I: Integer;
  PickedCaption, PickedMinutes, Id: string;
  Minutes, RandomFlag: Int64;
  IdUtf8: UTF8String;
begin
  try
    if not SameText(string(AControlId), 'ok') or not Assigned(GHostApi.SaverSetSettings) then
      Exit;
    Answer := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    Host := ReadHostChoice;
    try
      if not (Answer is TJSONObject) or (Host = nil) then
        Exit;
      PickedCaption := JsonText(TJSONObject(Answer), 'saver');
      PickedMinutes := JsonText(TJSONObject(Answer), 'minutes');
      if SameText(JsonText(TJSONObject(Answer), 'random'), 'true') or
         (JsonText(TJSONObject(Answer), 'random') = '1') then
        RandomFlag := 1
      else
        RandomFlag := 0;
      Id := '';
      List := Host.GetValue('savers') as TJSONArray;
      if List <> nil then
        for I := 0 to List.Count - 1 do
          if JsonText(List.Items[I] as TJSONObject, 'caption') = PickedCaption then
            Id := JsonText(List.Items[I] as TJSONObject, 'id');
      Minutes := -1;
      Choices := Host.GetValue('minuteChoices') as TJSONArray;
      if Choices <> nil then
        for I := 0 to Choices.Count - 1 do
          if MinutesCaption(StrToIntDef(Choices.Items[I].Value, -1)) = PickedMinutes then
            Minutes := StrToIntDef(Choices.Items[I].Value, -1);
      IdUtf8 := UTF8String(Id);
      GHostApi.SaverSetSettings(PAnsiChar(IdUtf8), Minutes, RandomFlag);
    finally
      Host.Free;
      Answer.Free;
    end;
  except
    // Never let an exception cross into the host.
  end;
end;

/// <summary>The "Settings" button of the plugins dialog: the picture and the idle time.</summary>
procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Decl, Host: TJSONObject;
  Kids, List, Choices: TJSONArray;
  Captions, Times: TStringList;
  I, SelSaver, SelTime: Integer;
  CurId, CurMinutes: string;
  CurRandom: Boolean;
  Json, Plugin: UTF8String;
begin
  try
    if not Assigned(GHostApi.ShowDialog) then
      Exit;
    Host := ReadHostChoice;
    if Host = nil then
      Exit;
    Captions := TStringList.Create;
    Times := TStringList.Create;
    Decl := TJSONObject.Create;
    try
      CurId := JsonText(Host, 'saverId');
      CurMinutes := JsonText(Host, 'minutes');
      CurRandom := SameText(JsonText(Host, 'random'), 'true');
      SelSaver := 0;
      SelTime := 0;
      List := Host.GetValue('savers') as TJSONArray;
      if List <> nil then
        for I := 0 to List.Count - 1 do
        begin
          Captions.Add(JsonText(List.Items[I] as TJSONObject, 'caption'));
          if SameText(JsonText(List.Items[I] as TJSONObject, 'id'), CurId) then
            SelSaver := I;
        end;
      Choices := Host.GetValue('minuteChoices') as TJSONArray;
      if Choices <> nil then
        for I := 0 to Choices.Count - 1 do
        begin
          Times.Add(MinutesCaption(StrToIntDef(Choices.Items[I].Value, 0)));
          if Choices.Items[I].Value = CurMinutes then
            SelTime := I;
        end;
      Decl.AddPair('type', 'dialog');
      Decl.AddPair('version', '2.0');
      Decl.AddPair('title', Tr('dlg.title', 'Screensaver'));
      Decl.AddPair('width', TJSONNumber.Create(60));
      Decl.AddPair('height', TJSONNumber.Create(12));
      Kids := TJSONArray.Create;
      Decl.AddPair('children', Kids);
      AddControl(Kids, 'checkbox', 'random', Tr('dlg.random', 'Random screensaver (&R)'),
        2, 1, 40, False, False, CurRandom);
      AddControl(Kids, 'label', '', Tr('dlg.saver', 'Picture:'), 2, 3, 20);
      AddDropDown(Kids, 'saver', Captions, SelSaver, 24, 3, 32);
      AddControl(Kids, 'label', '', Tr('dlg.minutes', 'Start after (minutes):'), 2, 5, 21);
      AddDropDown(Kids, 'minutes', Times, SelTime, 24, 5, 14);
      AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), 16, 8, 12, True);
      AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 31, 8, 12, False, True);
      Json := UTF8String(Decl.ToJSON);
    finally
      Decl.Free;
      Times.Free;
      Captions.Free;
      Host.Free;
    end;
    Plugin := UTF8String(cPluginId);
    GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnSettingsAnswer, nil);
  except
    // Never let an exception cross into the host.
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  Modules: TArray<ISaverModule>;
  Module: ISaverModule;
  Slot: TSaverSlot;
  PluginId, Id, Caption: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < cMinHostAbi) or
     not Assigned(AHostApi.RegisterSaver) then
    Exit(-1);
  GHostApi := AHostApi^;
  GSlots := TObjectList<TSaverSlot>.Create(True);
  GCallbacks.TickMs := CbTickMs;
  GCallbacks.Prepare := CbPrepare;
  GCallbacks.Advance := CbAdvance;
  GCallbacks.Draw := CbDraw;
  GCallbacks.DrawPixels := CbDrawPixels;
  GCallbacks.Finish := CbFinish;
  PluginId := UTF8String(cPluginId);
  if Assigned(GHostApi.RegisterSettings) then
    GHostApi.RegisterSettings(PAnsiChar(PluginId), @OnConfigure, nil);
  Modules := ScanSaverModules(ModulesFolder);
  for Module in Modules do
  begin
    Slot := TSaverSlot.Create;
    Slot.Module := Module;
    Slot.Info := Module.Info;
    GSlots.Add(Slot);
    Id := UTF8String(Slot.Info.Id);
    Caption := UTF8String(Tr('saver.' + Slot.Info.Id, Slot.Info.Name));
    // A refused picture stays in the list, unused, until the plugin unloads.
    GHostApi.RegisterSaver(PAnsiChar(PluginId), PAnsiChar(Id), PAnsiChar(Caption),
      Slot.Info.Modes, @GCallbacks, Slot);
  end;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  FreeAndNil(GSlots);
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
