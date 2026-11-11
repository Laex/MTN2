library ScreenSaverPlugin;

{ Native MTN2 plugin: the screensaver pictures that live in the plugin's
  savers folder. Each library there is one picture (see uSaverModules for the
  contract); the plugin registers every one with the host, which shows the
  chosen picture after the idle time. The plugin loads the libraries at
  start and keeps them until it is unloaded. }

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
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

function CbDraw(AUserData: Pointer; ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
var
  Slot: TSaverSlot;
begin
  Result := -1;
  Slot := TSaverSlot(AUserData);
  if Slot.Instance = 0 then
  begin
    Slot.Instance := Slot.Module.Open(ACols, ARows, Slot.Seed);
    if Slot.Instance = 0 then
      Exit;
    Slot.Cols := ACols;
    Slot.Rows := ARows;
  end
  else if (ACols <> Slot.Cols) or (ARows <> Slot.Rows) then
  begin
    Slot.Module.Resize(Slot.Instance, ACols, ARows);
    Slot.Cols := ACols;
    Slot.Rows := ARows;
  end;
  if Slot.Module.DrawText(Slot.Instance, ACols, ARows, ACells) then
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
  GCallbacks.Finish := CbFinish;
  PluginId := UTF8String(cPluginId);
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
