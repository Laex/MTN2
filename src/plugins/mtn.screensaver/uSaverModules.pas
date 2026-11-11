unit uSaverModules;

{ Screensaver modules: the libraries in the plugin's savers folder, each one a
  picture for the screensaver. A module is reached through ISaverModule, so the
  plugin does not care how the code behind it is loaded.

  Native library contract (all cdecl, UTF-8, no pointers except the cell buffer
  the plugin owns for the duration of one call):
    function mtn_saver_get_abi_version: Int64;
    function mtn_saver_info(ABuf: PAnsiChar; ABufSize: Int64): Int64;
      // writes a JSON object with "id", "name", "tickMs" and "modes" (for
      // example "modes": ["text"]) and returns its byte length,
      // -1 when it does not fit
    function mtn_saver_create(ACols, ARows, ASeed: Int64): Int64;   // handle > 0, 0 = failed
    procedure mtn_saver_resize(AHandle, ACols, ARows: Int64);
    procedure mtn_saver_advance(AHandle, ADeltaMs: Int64);
    function mtn_saver_draw_text(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Int64;
      // fills ACols x ARows cells (row by row), 0 = drawn
    procedure mtn_saver_destroy(AHandle: Int64);
  A module may run several instances; instances are told apart by the handle. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  uPluginHostAbi;

const
  cSaverModuleAbiVersion = 1;
  cSaverModulesFolder = 'savers';
  cSaverInfoBufferSize = 4096;
  {$IFDEF MSWINDOWS}
  cSaverLibraryMask = '*.dll';
  {$ELSE}
  cSaverLibraryMask = '*.so';
  {$ENDIF}

type
  TSaverModuleInfo = record
    Id: string;
    Name: string;
    TickMs: Integer;
    /// <summary>Bit set of the cSaverMode* values the module draws in.</summary>
    Modes: Int64;
  end;

  ISaverModule = interface
    ['{2F8E5C1A-94B7-4D36-A0E2-7C61B3D9F058}']
    function Info: TSaverModuleInfo;
    /// <summary>A new instance for a ACols x ARows window; 0 = failed.</summary>
    function Open(ACols, ARows, ASeed: Int64): Int64;
    procedure Resize(AHandle, ACols, ARows: Int64);
    procedure Advance(AHandle, ADeltaMs: Int64);
    /// <summary>False when the module failed to draw the frame.</summary>
    function DrawText(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Boolean;
    procedure Close(AHandle: Int64);
  end;

/// <summary>Reads the info JSON of a module. False when it has no id, or the text
/// is not an object. The tick interval is kept within 10..1000 ms and the modes
/// default to text.</summary>
function ParseSaverInfo(const AJson: string; out AInfo: TSaverModuleInfo): Boolean;

/// <summary>Loads the native library APath as a module. False (with nothing kept
/// loaded) when it does not export the contract, its ABI differs, or its info is
/// unusable.</summary>
function LoadNativeSaverModule(const APath: string; out AModule: ISaverModule): Boolean;

/// <summary>Loads every module found in AFolder (not below it). Libraries that are
/// not modules are skipped.</summary>
function ScanSaverModules(const AFolder: string): TArray<ISaverModule>;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

type
  TNativeSaverModule = class(TInterfacedObject, ISaverModule)
  private
    FHandle: HMODULE;
    FInfo: TSaverModuleInfo;
    FCreate: function(ACols, ARows, ASeed: Int64): Int64; cdecl;
    FResize: procedure(AHandle, ACols, ARows: Int64); cdecl;
    FAdvance: procedure(AHandle, ADeltaMs: Int64); cdecl;
    FDraw: function(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
    FDestroy: procedure(AHandle: Int64); cdecl;
  public
    constructor Create(AHandle: HMODULE; const AInfo: TSaverModuleInfo);
    destructor Destroy; override;
    function Bind: Boolean;
    function Info: TSaverModuleInfo;
    function Open(ACols, ARows, ASeed: Int64): Int64;
    procedure Resize(AHandle, ACols, ARows: Int64);
    procedure Advance(AHandle, ADeltaMs: Int64);
    function DrawText(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Boolean;
    procedure Close(AHandle: Int64);
  end;

function ParseSaverInfo(const AJson: string; out AInfo: TSaverModuleInfo): Boolean;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  AInfo := Default(TSaverModuleInfo);
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    if not Obj.TryGetValue<string>('id', AInfo.Id) then
      Exit;
    AInfo.Id := Trim(AInfo.Id);
    if AInfo.Id = '' then
      Exit;
    if not Obj.TryGetValue<string>('name', AInfo.Name) or (Trim(AInfo.Name) = '') then
      AInfo.Name := AInfo.Id;
    if not Obj.TryGetValue<Integer>('tickMs', AInfo.TickMs) then
      AInfo.TickMs := 90;
    if AInfo.TickMs < 10 then
      AInfo.TickMs := 10;
    if AInfo.TickMs > 1000 then
      AInfo.TickMs := 1000;
    AInfo.Modes := 0;
    V := Obj.GetValue('modes');
    if V is TJSONArray then
    begin
      Arr := TJSONArray(V);
      for I := 0 to Arr.Count - 1 do
        if SameText(Arr.Items[I].Value, 'text') then
          AInfo.Modes := AInfo.Modes or cSaverModeText;
    end
    else
      AInfo.Modes := cSaverModeText;
    Result := AInfo.Modes <> 0;
  finally
    Root.Free;
  end;
end;

{ TNativeSaverModule }

constructor TNativeSaverModule.Create(AHandle: HMODULE; const AInfo: TSaverModuleInfo);
begin
  inherited Create;
  FHandle := AHandle;
  FInfo := AInfo;
end;

destructor TNativeSaverModule.Destroy;
begin
  if FHandle <> 0 then
    FreeLibrary(FHandle);
  inherited Destroy;
end;

function TNativeSaverModule.Bind: Boolean;
begin
  @FCreate := GetProcAddress(FHandle, 'mtn_saver_create');
  @FResize := GetProcAddress(FHandle, 'mtn_saver_resize');
  @FAdvance := GetProcAddress(FHandle, 'mtn_saver_advance');
  @FDraw := GetProcAddress(FHandle, 'mtn_saver_draw_text');
  @FDestroy := GetProcAddress(FHandle, 'mtn_saver_destroy');
  Result := Assigned(FCreate) and Assigned(FResize) and Assigned(FAdvance) and
    Assigned(FDraw) and Assigned(FDestroy);
end;

function TNativeSaverModule.Info: TSaverModuleInfo;
begin
  Result := FInfo;
end;

function TNativeSaverModule.Open(ACols, ARows, ASeed: Int64): Int64;
begin
  try
    Result := FCreate(ACols, ARows, ASeed);
  except
    Result := 0;
  end;
end;

procedure TNativeSaverModule.Resize(AHandle, ACols, ARows: Int64);
begin
  try
    FResize(AHandle, ACols, ARows);
  except
    // A failing module draws a blank frame next time.
  end;
end;

procedure TNativeSaverModule.Advance(AHandle, ADeltaMs: Int64);
begin
  try
    FAdvance(AHandle, ADeltaMs);
  except
    // A failing module draws a blank frame next time.
  end;
end;

function TNativeSaverModule.DrawText(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Boolean;
begin
  try
    Result := FDraw(AHandle, ACols, ARows, ACells) = 0;
  except
    Result := False;
  end;
end;

procedure TNativeSaverModule.Close(AHandle: Int64);
begin
  try
    FDestroy(AHandle);
  except
    // The instance is gone either way.
  end;
end;

function LoadNativeSaverModule(const APath: string; out AModule: ISaverModule): Boolean;
type
  TGetAbi = function: Int64; cdecl;
  TGetInfo = function(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  Lib: HMODULE;
  GetAbi: TGetAbi;
  GetInfo: TGetInfo;
  Buf: UTF8String;
  Len: Int64;
  Info: TSaverModuleInfo;
  Module: TNativeSaverModule;
begin
  AModule := nil;
  Result := False;
  Lib := LoadLibrary(PChar(APath));
  if Lib = 0 then
    Exit;
  @GetAbi := GetProcAddress(Lib, 'mtn_saver_get_abi_version');
  @GetInfo := GetProcAddress(Lib, 'mtn_saver_info');
  if not (Assigned(GetAbi) and Assigned(GetInfo)) then
  begin
    FreeLibrary(Lib);
    Exit;
  end;
  try
    if GetAbi() <> cSaverModuleAbiVersion then
      raise Exception.Create('saver ABI');
    SetLength(Buf, cSaverInfoBufferSize);
    Len := GetInfo(PAnsiChar(Buf), cSaverInfoBufferSize);
    if (Len <= 0) or (Len >= cSaverInfoBufferSize) then
      raise Exception.Create('saver info');
    SetLength(Buf, Len);
    if not ParseSaverInfo(UTF8ToString(Buf), Info) then
      raise Exception.Create('saver info');
  except
    FreeLibrary(Lib);
    Exit;
  end;
  Module := TNativeSaverModule.Create(Lib, Info);
  if not Module.Bind then
  begin
    // Destroying the object frees the library.
    Module.Free;
    Exit;
  end;
  AModule := Module;
  Result := True;
end;

function ScanSaverModules(const AFolder: string): TArray<ISaverModule>;
var
  List: TList<ISaverModule>;
  Files: TArray<string>;
  F: string;
  Module: ISaverModule;
  I: Integer;
begin
  List := TList<ISaverModule>.Create;
  try
    if TDirectory.Exists(AFolder) then
    begin
      Files := TDirectory.GetFiles(AFolder, cSaverLibraryMask);
      TArray.Sort<string>(Files);
      for F in Files do
        if LoadNativeSaverModule(F, Module) then
        begin
          // The first module with an id wins; a repeat is dropped.
          for I := 0 to List.Count - 1 do
            if SameText(List[I].Info.Id, Module.Info.Id) then
            begin
              Module := nil;
              Break;
            end;
          if Module <> nil then
            List.Add(Module);
        end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
