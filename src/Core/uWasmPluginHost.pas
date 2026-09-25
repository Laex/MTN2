unit uWasmPluginHost;

{ WASM plugin runtime on top of optional Wasmtime (uWasmtimeApi.pas).

  Isolation contract (stage 30):
  - Each plugin gets its own store. Linear memory is the only guest-visible
    RAM; host never hands out process pointers, only i32 offsets into that
    memory, and copies UTF-8 in and out after a bounds check.
  - WASI is not defined on the linker. A module that imports it cannot
    instantiate, so it cannot see the host filesystem / sockets.
  - Fuel + store limiter bound runaway guests. A trap (unreachable, OOB,
    out-of-fuel) becomes a logged load/VFS error; it does not unwind into
    the Delphi process.
  - Guest plugin-id is assigned by the host from the plugins\<id>\ folder
    name. The module only supplies a scheme string.

  Guest ABI (not the cdecl THostApiTable — those pointers would be a shared
  address space). Imports on module "mtn_host":
    register_vfs_scheme(ptr, len, priority) -> i32
    register_panel_plugin(ptr, len, priority) -> i32
    register_menu_item(parent_ptr, parent_len, id_ptr, id_len,
      caption_ptr, caption_len, export_ptr, export_len, priority) -> i32
    publish(topic_ptr, topic_len, json_ptr, json_len) -> i32
  Exports:
    mtn_plugin_get_abi_version() -> i64
    mtn_plugin_init() -> i32
    mtn_plugin_shutdown()
    mtn_last_size() -> i64
    mtn_vfs_list(uri_ptr, uri_len, out_ptr, out_cap) -> i64   // status; size in mtn_last_size
    mtn_vfs_exists(uri_ptr, uri_len) -> i64                   // status; isDir in mtn_last_size
    mtn_vfs_read_text(uri_ptr, uri_len, out_ptr, out_cap) -> i64
    mtn_vfs_mkdir(uri_ptr, uri_len) -> i64
    mtn_vfs_delete(uri_ptr, uri_len) -> i64
    mtn_vfs_copy(from_ptr, from_len, to_ptr, to_len, is_dir, overwrite) -> i64
  Host scratch sits in the last 32 KiB of guest memory (URI 4 KiB, output 28 KiB). }

interface

uses
  System.SysUtils, System.SyncObjs,
  uWasmtimeApi, uPluginHostAbi;

type
  TWasmPluginInstance = class
  private
    FPluginId: string;
    FLock: TCriticalSection;
    FDead: Boolean;
    FStore: PWasmtimeStore;
    FContext: PWasmtimeContext;
    FModule: PWasmtimeModule;
    FInstance: TWasmtimeInstance;
    FHasInstance: Boolean;
    FUriOff: Integer;
    FUriSlot: Integer;
    FOutOff: Integer;
    FOutCap: Integer;
    procedure ReleaseEngineObjects;
    function Refuel(out AError: string): Boolean;
    function GetExportFunc(const AName: string; out AFunc: TWasmtimeFunc): Boolean;
    function CallNoArgsI64(const AName: string; out AValue: Int64; out AError: string): Boolean;
    function CallNoArgsI32(const AName: string; out AValue: Integer; out AError: string): Boolean;
    function CallNoArgsVoid(const AName: string; out AError: string): Boolean;
    function RefreshScratch(out AError: string): Boolean;
    function WriteUriScratch(const AURI: string; out APtr, ALen: Integer;
      out AError: string): Boolean;
    function WriteTwoUris(const A, B: string; out APtrA, ALenA, APtrB, ALenB: Integer;
      out AError: string): Boolean;
    function ReadScratchOut(ASize: Int64; out ABytes: TBytes; out AError: string): Boolean;
    function CallLastSize(out ASize: Int64; out AError: string): Boolean;
  public
    constructor Create(const APluginId: string);
    destructor Destroy; override;
    function LoadFromFile(const AFileName: string; out AError: string): Boolean;
    function InitPlugin(out AError: string): Boolean;
    procedure ShutdownPlugin;
    function CallBufferExport(const AExport, AURI: string; out ABytes: TBytes;
      out AStatus: Int64; out AError: string): Boolean;
    function CallExistsExport(const AURI: string; out AStatus, AIsDir: Int64;
      out AError: string): Boolean;
    function CallStatusExport(const AExport, AURI: string; out AStatus: Int64;
      out AError: string): Boolean;
    function CallCopyExport(const AFromURI, AToURI: string; AIsDir, AOverwrite: Boolean;
      out AStatus: Int64; out AError: string): Boolean;
    function InvokeVoidExport(const AName: string; out AError: string): Boolean;
    property PluginId: string read FPluginId;
    property Dead: Boolean read FDead;
  end;

function EnsureWasmEngine(out AError: string): Boolean;
function WasmEngineAvailable: Boolean;

implementation

uses
  System.Classes, System.IOUtils,
  uVfsTypes, uTextEncoding, uVfsCdeclAdapter, uVfsRegistry, uPanelPluginRegistry,
  uMenuRegistry;

const
  cFuelPerCall: UInt64 = 50000000;
  cScratchTail = 32768;
  cScratchUriBytes = 4096;
  cScratchUriSlot = 2048;
  cScratchOutBytes = 28672;
  cHostModule: AnsiString = 'mtn_host';
  cRegVfs: AnsiString = 'register_vfs_scheme';
  cRegPanel: AnsiString = 'register_panel_plugin';
  cRegMenu: AnsiString = 'register_menu_item';
  cPublish: AnsiString = 'publish';

var
  GEngine: PWasmEngine = nil;
  GLinker: PWasmtimeLinker = nil;

type
  TValBuf = array[0..8] of TWasmtimeVal;

  TWasmVfsBackend = class(TInterfacedObject, IVirtualFileSystem)
  private
    FInst: TWasmPluginInstance;
    function ErrorFromStatus(AStatus: Int64; const AURI, ADetail: string): TVfsError;
  public
    constructor Create(AInst: TWasmPluginInstance);
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

function MakeFuncType(const AParams, AResults: array of Byte): PWasmFunctype;
var
  Params, Results: TWasmValtypeVec;
  I: Integer;
  Slot: PPointer;
begin
  FillChar(Params, SizeOf(Params), 0);
  FillChar(Results, SizeOf(Results), 0);
  if Length(AParams) = 0 then
    Wasmtime.ValtypeVecNewEmpty(@Params)
  else
  begin
    Wasmtime.ValtypeVecNewUninitialized(@Params, Length(AParams));
    Slot := Params.Data;
    for I := 0 to High(AParams) do
    begin
      Slot^ := Wasmtime.ValtypeNew(AParams[I]);
      Inc(Slot);
    end;
  end;
  if Length(AResults) = 0 then
    Wasmtime.ValtypeVecNewEmpty(@Results)
  else
  begin
    Wasmtime.ValtypeVecNewUninitialized(@Results, Length(AResults));
    Slot := Results.Data;
    for I := 0 to High(AResults) do
    begin
      Slot^ := Wasmtime.ValtypeNew(AResults[I]);
      Inc(Slot);
    end;
  end;
  Result := Wasmtime.FunctypeNew(@Params, @Results);
end;

procedure SetI32Result(Results: PWasmtimeVal; NResults: NativeUInt; AValue: Integer);
begin
  if (Results = nil) or (NResults = 0) then
    Exit;
  FillChar(Results^, SizeOf(TWasmtimeVal), 0);
  Results^.Kind := WASMTIME_I32;
  Results^.Of_.I32 := AValue;
end;

function WasmResultI64(const AVal: TWasmtimeVal): Int64;
begin
  if AVal.Kind = WASMTIME_I32 then
    Result := AVal.Of_.I32
  else
    Result := AVal.Of_.I64;
end;

function InstanceFromCaller(Caller: PWasmtimeCaller): TWasmPluginInstance;
var
  Ctx: PWasmtimeContext;
begin
  Result := nil;
  if Caller = nil then
    Exit;
  Ctx := Wasmtime.CallerContext(Caller);
  if Ctx = nil then
    Exit;
  Result := TWasmPluginInstance(Wasmtime.ContextGetData(Ctx));
end;

function ReadGuestUtf8(Caller: PWasmtimeCaller; APtr, ALen: Integer;
  out AText: string): Boolean;
var
  Ctx: PWasmtimeContext;
  Ext: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
  Bytes: TBytes;
begin
  Result := False;
  AText := '';
  if (Caller = nil) or (APtr < 0) or (ALen < 0) then
    Exit;
  Ctx := Wasmtime.CallerContext(Caller);
  FillChar(Ext, SizeOf(Ext), 0);
  if not Wasmtime.CallerExportGet(Caller, 'memory', 6, @Ext) then
    Exit;
  try
    if Ext.Kind <> WASMTIME_EXTERN_MEMORY then
      Exit;
    Data := Wasmtime.MemoryData(Ctx, @Ext.Of_.Memory);
    Size := Wasmtime.MemoryDataSize(Ctx, @Ext.Of_.Memory);
    if Data = nil then
      Exit;
    if NativeUInt(APtr) + NativeUInt(ALen) > Size then
      Exit;
    if ALen = 0 then
      Exit(True);
    SetLength(Bytes, ALen);
    Move(Data[APtr], Bytes[0], ALen);
    AText := TEncoding.UTF8.GetString(Bytes);
    Result := True;
  finally
    Wasmtime.ExternDelete(@Ext);
  end;
end;

function HostRegVfs(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Scheme: string;
  Ptr, Len, Prio: Integer;
  Backend: IVirtualFileSystem;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  Ptr := Vals^[0].Of_.I32;
  Len := Vals^[1].Of_.I32;
  Prio := Vals^[2].Of_.I32;
  if not ReadGuestUtf8(Caller, Ptr, Len, Scheme) or (Scheme = '') then
    Exit;
  // Drive-bar schemes (ws, recycle, …) are built-in. A WASM module may still
  // call register_vfs_scheme; ignore it so File VFS / the core backend stay
  // in charge and an empty panel does not become "Invalid path".
  if SameText(Scheme, 'file') or SameText(Scheme, 'recycle') or
     SameText(Scheme, 'sys') or SameText(Scheme, 'find') or
     SameText(Scheme, 'ws') then
  begin
    SetI32Result(Results, NResults, 0);
    Exit;
  end;
  Backend := TWasmVfsBackend.Create(Inst);
  GlobalVfsRegistry.RegisterPluginScheme(Inst.PluginId, Scheme, Backend, Prio);
  SetI32Result(Results, NResults, 0);
end;

function HostRegPanel(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Scheme: string;
  Ptr, Len, Prio: Integer;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  Ptr := Vals^[0].Of_.I32;
  Len := Vals^[1].Of_.I32;
  Prio := Vals^[2].Of_.I32;
  if not ReadGuestUtf8(Caller, Ptr, Len, Scheme) or (Scheme = '') then
    Exit;
  PanelPluginRegistry.RegisterPlugin(Inst.PluginId, Scheme, Prio);
  SetI32Result(Results, NResults, 0);
end;

function HostPublish(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Topic, Json: string;
  Vals: ^TValBuf;
  PluginU, TopicU, JsonU: UTF8String;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Topic) or (Topic = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Json) then
    Json := '';
  PluginU := UTF8String(Inst.PluginId);
  TopicU := UTF8String(Topic);
  JsonU := UTF8String(Json);
  if mtn_host_publish(PAnsiChar(PluginU), PAnsiChar(TopicU), PAnsiChar(JsonU)) = 0 then
    SetI32Result(Results, NResults, 0);
end;

function HostRegMenu(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Parent, ItemId, Caption, ExportName: string;
  Prio: Integer;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 9 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Parent) then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ItemId) or (ItemId = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[4].Of_.I32, Vals^[5].Of_.I32, Caption) or (Caption = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[6].Of_.I32, Vals^[7].Of_.I32, ExportName) or (ExportName = '') then
    Exit;
  Prio := Vals^[8].Of_.I32;
  MenuRegistry.RegisterMenuItem(Inst.PluginId, Parent, ItemId, Caption,
    procedure
    var
      Err: string;
    begin
      if (Inst = nil) or Inst.Dead then
        Exit;
      Inst.InvokeVoidExport(ExportName, Err);
    end, Prio);
  SetI32Result(Results, NResults, 0);
end;

function DefineHostImport(const AName: AnsiString; Ty: PWasmFunctype; ACb: Pointer;
  out AError: string): Boolean;
var
  Err: PWasmtimeError;
begin
  Err := Wasmtime.LinkerDefineFunc(GLinker, PAnsiChar(cHostModule), Length(cHostModule),
    PAnsiChar(AName), Length(AName), Ty, ACb, nil, nil);
  if Err <> nil then
  begin
    AError := 'define ' + string(AName) + ': ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit(False);
  end;
  Result := True;
end;

function EnsureWasmEngine(out AError: string): Boolean;
var
  Cfg: PWasmConfig;
  Ty3, Ty4, Ty9: PWasmFunctype;
begin
  AError := '';
  if (GEngine <> nil) and (GLinker <> nil) then
    Exit(True);
  if not TryLoadWasmtime(AError) then
    Exit(False);
  Cfg := Wasmtime.ConfigNew();
  if Cfg = nil then
  begin
    AError := 'wasm_config_new failed';
    Exit(False);
  end;
  Wasmtime.ConfigConsumeFuelSet(Cfg, 1);
  GEngine := Wasmtime.EngineNewWithConfig(Cfg);
  if GEngine = nil then
  begin
    AError := 'wasm_engine_new_with_config failed';
    Exit(False);
  end;
  GLinker := Wasmtime.LinkerNew(GEngine);
  if GLinker = nil then
  begin
    AError := 'wasmtime_linker_new failed';
    Exit(False);
  end;
  Ty3 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty4 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty9 := MakeFuncType(
    [WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32],
    [WASM_I32]);
  if (Ty3 = nil) or (Ty4 = nil) or (Ty9 = nil) then
  begin
    if Ty3 <> nil then
      Wasmtime.FunctypeDelete(Ty3);
    if Ty4 <> nil then
      Wasmtime.FunctypeDelete(Ty4);
    if Ty9 <> nil then
      Wasmtime.FunctypeDelete(Ty9);
    AError := 'wasm_functype_new failed';
    Exit(False);
  end;
  try
    if not DefineHostImport(cRegVfs, Ty3, @HostRegVfs, AError) then
      Exit(False);
    if not DefineHostImport(cRegPanel, Ty3, @HostRegPanel, AError) then
      Exit(False);
    if not DefineHostImport(cPublish, Ty4, @HostPublish, AError) then
      Exit(False);
    if not DefineHostImport(cRegMenu, Ty9, @HostRegMenu, AError) then
      Exit(False);
  finally
    Wasmtime.FunctypeDelete(Ty3);
    Wasmtime.FunctypeDelete(Ty4);
    Wasmtime.FunctypeDelete(Ty9);
  end;
  Result := True;
end;

function WasmEngineAvailable: Boolean;
var
  Err: string;
begin
  Result := EnsureWasmEngine(Err);
end;

constructor TWasmPluginInstance.Create(const APluginId: string);
begin
  inherited Create;
  FPluginId := APluginId;
  FLock := TCriticalSection.Create;
end;

destructor TWasmPluginInstance.Destroy;
begin
  ShutdownPlugin;
  FLock.Free;
  inherited Destroy;
end;

procedure TWasmPluginInstance.ReleaseEngineObjects;
begin
  FHasInstance := False;
  FContext := nil;
  if FModule <> nil then
  begin
    Wasmtime.ModuleDelete(FModule);
    FModule := nil;
  end;
  if FStore <> nil then
  begin
    Wasmtime.StoreDelete(FStore);
    FStore := nil;
  end;
end;

procedure TWasmPluginInstance.ShutdownPlugin;
var
  Dummy: string;
begin
  FLock.Acquire;
  try
    if FDead then
      Exit;
    FDead := True;
    if FHasInstance then
      CallNoArgsVoid('mtn_plugin_shutdown', Dummy);
    ReleaseEngineObjects;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.Refuel(out AError: string): Boolean;
var
  Err: PWasmtimeError;
begin
  AError := '';
  Err := Wasmtime.ContextSetFuel(FContext, cFuelPerCall);
  if Err <> nil then
  begin
    AError := 'set_fuel: ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit(False);
  end;
  Result := True;
end;

function TWasmPluginInstance.GetExportFunc(const AName: string;
  out AFunc: TWasmtimeFunc): Boolean;
var
  Ext: TWasmtimeExtern;
  NameU: UTF8String;
begin
  Result := False;
  FillChar(AFunc, SizeOf(AFunc), 0);
  FillChar(Ext, SizeOf(Ext), 0);
  NameU := UTF8String(AName);
  if not Wasmtime.InstanceExportGet(FContext, @FInstance, PAnsiChar(NameU),
    Length(NameU), @Ext) then
    Exit;
  try
    if Ext.Kind <> WASMTIME_EXTERN_FUNC then
      Exit;
    AFunc := Ext.Of_.Func;
    Result := True;
  finally
    Wasmtime.ExternDelete(@Ext);
  end;
end;

function TWasmPluginInstance.CallNoArgsI64(const AName: string; out AValue: Int64;
  out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Ret: TWasmtimeVal;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
begin
  Result := False;
  AValue := 0;
  AError := '';
  if not GetExportFunc(AName, Func) then
  begin
    AError := AName + ' export missing';
    Exit;
  end;
  if not Refuel(AError) then
    Exit;
  FillChar(Ret, SizeOf(Ret), 0);
  Trap := nil;
  Err := Wasmtime.FuncCall(FContext, @Func, nil, 0, @Ret, 1, @Trap);
  if Err <> nil then
  begin
    AError := AName + ': ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit;
  end;
  if Trap <> nil then
  begin
    AError := AName + ' trap: ' + WasmtimeTrapMessage(Trap);
    WasmtimeClearTrap(Trap);
    Exit;
  end;
  AValue := Ret.Of_.I64;
  Result := True;
end;

function TWasmPluginInstance.CallNoArgsI32(const AName: string; out AValue: Integer;
  out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Ret: TWasmtimeVal;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
begin
  Result := False;
  AValue := -1;
  AError := '';
  if not GetExportFunc(AName, Func) then
  begin
    AError := AName + ' export missing';
    Exit;
  end;
  if not Refuel(AError) then
    Exit;
  FillChar(Ret, SizeOf(Ret), 0);
  Trap := nil;
  Err := Wasmtime.FuncCall(FContext, @Func, nil, 0, @Ret, 1, @Trap);
  if Err <> nil then
  begin
    AError := AName + ': ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit;
  end;
  if Trap <> nil then
  begin
    AError := AName + ' trap: ' + WasmtimeTrapMessage(Trap);
    WasmtimeClearTrap(Trap);
    Exit;
  end;
  AValue := Ret.Of_.I32;
  Result := True;
end;

function TWasmPluginInstance.CallNoArgsVoid(const AName: string;
  out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
begin
  Result := False;
  AError := '';
  if not GetExportFunc(AName, Func) then
  begin
    AError := AName + ' export missing';
    Exit;
  end;
  if not Refuel(AError) then
    Exit;
  Trap := nil;
  Err := Wasmtime.FuncCall(FContext, @Func, nil, 0, nil, 0, @Trap);
  if Err <> nil then
  begin
    AError := AName + ': ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit;
  end;
  if Trap <> nil then
  begin
    AError := AName + ' trap: ' + WasmtimeTrapMessage(Trap);
    WasmtimeClearTrap(Trap);
    Exit;
  end;
  Result := True;
end;

function TWasmPluginInstance.RefreshScratch(out AError: string): Boolean;
var
  MemExt: TWasmtimeExtern;
  Size: NativeUInt;
begin
  Result := False;
  AError := '';
  FillChar(MemExt, SizeOf(MemExt), 0);
  if not Wasmtime.InstanceExportGet(FContext, @FInstance, 'memory', 6, @MemExt) then
  begin
    AError := 'memory export missing';
    Exit;
  end;
  try
    if MemExt.Kind <> WASMTIME_EXTERN_MEMORY then
    begin
      AError := 'memory export is not a memory';
      Exit;
    end;
    Size := Wasmtime.MemoryDataSize(FContext, @MemExt.Of_.Memory);
    if Size < NativeUInt(cScratchTail) then
    begin
      AError := 'guest memory too small for host scratch';
      Exit;
    end;
    FUriOff := Integer(Size) - cScratchUriBytes;
    FUriSlot := cScratchUriSlot;
    FOutCap := cScratchOutBytes;
    FOutOff := FUriOff - FOutCap;
    if FOutOff < 0 then
    begin
      AError := 'guest memory too small for host scratch';
      Exit;
    end;
    Result := True;
  finally
    Wasmtime.ExternDelete(@MemExt);
  end;
end;

function TWasmPluginInstance.WriteUriScratch(const AURI: string; out APtr, ALen: Integer;
  out AError: string): Boolean;
var
  MemExt: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
  U: UTF8String;
begin
  Result := False;
  APtr := 0;
  ALen := 0;
  AError := '';
  if not RefreshScratch(AError) then
    Exit;
  U := UTF8String(AURI);
  if Length(U) >= FUriSlot then
  begin
    AError := 'URI exceeds WASM scratch';
    Exit;
  end;
  FillChar(MemExt, SizeOf(MemExt), 0);
  if not Wasmtime.InstanceExportGet(FContext, @FInstance, 'memory', 6, @MemExt) then
  begin
    AError := 'memory export missing';
    Exit;
  end;
  try
    if MemExt.Kind <> WASMTIME_EXTERN_MEMORY then
    begin
      AError := 'memory export is not a memory';
      Exit;
    end;
    Data := Wasmtime.MemoryData(FContext, @MemExt.Of_.Memory);
    Size := Wasmtime.MemoryDataSize(FContext, @MemExt.Of_.Memory);
    if (Data = nil) or (NativeUInt(FUriOff) + NativeUInt(Length(U)) > Size) then
    begin
      AError := 'guest memory too small for host scratch';
      Exit;
    end;
    APtr := FUriOff;
    ALen := Length(U);
    if ALen > 0 then
      Move(PAnsiChar(U)^, Data[FUriOff], ALen);
    Result := True;
  finally
    Wasmtime.ExternDelete(@MemExt);
  end;
end;

function TWasmPluginInstance.WriteTwoUris(const A, B: string; out APtrA, ALenA, APtrB, ALenB: Integer;
  out AError: string): Boolean;
var
  MemExt: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
  Ua, Ub: UTF8String;
begin
  Result := False;
  APtrA := 0;
  ALenA := 0;
  APtrB := 0;
  ALenB := 0;
  AError := '';
  if not RefreshScratch(AError) then
    Exit;
  Ua := UTF8String(A);
  Ub := UTF8String(B);
  if (Length(Ua) >= FUriSlot) or (Length(Ub) >= FUriSlot) then
  begin
    AError := 'URI exceeds WASM scratch';
    Exit;
  end;
  FillChar(MemExt, SizeOf(MemExt), 0);
  if not Wasmtime.InstanceExportGet(FContext, @FInstance, 'memory', 6, @MemExt) then
  begin
    AError := 'memory export missing';
    Exit;
  end;
  try
    if MemExt.Kind <> WASMTIME_EXTERN_MEMORY then
    begin
      AError := 'memory export is not a memory';
      Exit;
    end;
    Data := Wasmtime.MemoryData(FContext, @MemExt.Of_.Memory);
    Size := Wasmtime.MemoryDataSize(FContext, @MemExt.Of_.Memory);
    if (Data = nil) or (NativeUInt(FUriOff + FUriSlot) + NativeUInt(Length(Ub)) > Size) then
    begin
      AError := 'guest memory too small for host scratch';
      Exit;
    end;
    APtrA := FUriOff;
    ALenA := Length(Ua);
    APtrB := FUriOff + FUriSlot;
    ALenB := Length(Ub);
    if ALenA > 0 then
      Move(PAnsiChar(Ua)^, Data[APtrA], ALenA);
    if ALenB > 0 then
      Move(PAnsiChar(Ub)^, Data[APtrB], ALenB);
    Result := True;
  finally
    Wasmtime.ExternDelete(@MemExt);
  end;
end;

function TWasmPluginInstance.ReadScratchOut(ASize: Int64; out ABytes: TBytes;
  out AError: string): Boolean;
var
  MemExt: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
  N: Integer;
begin
  Result := False;
  SetLength(ABytes, 0);
  AError := '';
  if ASize < 0 then
  begin
    AError := 'negative guest size';
    Exit;
  end;
  if ASize > FOutCap then
  begin
    AError := 'guest size exceeds scratch';
    Exit;
  end;
  FillChar(MemExt, SizeOf(MemExt), 0);
  if not Wasmtime.InstanceExportGet(FContext, @FInstance, 'memory', 6, @MemExt) then
  begin
    AError := 'memory export missing';
    Exit;
  end;
  try
    Data := Wasmtime.MemoryData(FContext, @MemExt.Of_.Memory);
    Size := Wasmtime.MemoryDataSize(FContext, @MemExt.Of_.Memory);
    if (Data = nil) or (NativeUInt(FOutOff) + NativeUInt(ASize) > Size) then
    begin
      AError := 'guest out-pointer failed bounds check';
      Exit;
    end;
    N := Integer(ASize);
    SetLength(ABytes, N);
    if N > 0 then
      Move(Data[FOutOff], ABytes[0], N);
    Result := True;
  finally
    Wasmtime.ExternDelete(@MemExt);
  end;
end;

function TWasmPluginInstance.LoadFromFile(const AFileName: string;
  out AError: string): Boolean;
var
  Raw: TBytes;
  Text: UTF8String;
  Wasm: TWasmByteVec;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  WasmPtr: Pointer;
  WasmLen: NativeUInt;
  Ext: string;
  IsWat: Boolean;
begin
  Result := False;
  AError := '';
  if not EnsureWasmEngine(AError) then
    Exit;
  try
    Raw := TFile.ReadAllBytes(AFileName);
  except
    on E: Exception do
    begin
      AError := 'read failed: ' + E.Message;
      Exit;
    end;
  end;
  if Length(Raw) = 0 then
  begin
    AError := 'empty module';
    Exit;
  end;

  FStore := Wasmtime.StoreNew(GEngine, Self, nil);
  if FStore = nil then
  begin
    AError := 'wasmtime_store_new failed';
    Exit;
  end;
  FContext := Wasmtime.StoreContext(FStore);
  Wasmtime.StoreLimiter(FStore, 1024 * 1024, 64, 1, 1, 1);

  FillChar(Wasm, SizeOf(Wasm), 0);
  Ext := LowerCase(ExtractFileExt(AFileName));
  IsWat := (Ext = '.wat') or ((Length(Raw) >= 1) and (Raw[0] <> $00));
  if IsWat and (Ext <> '.wasm') then
  begin
    SetLength(Text, Length(Raw));
    Move(Raw[0], Text[1], Length(Raw));
    Err := Wasmtime.Wat2Wasm(PAnsiChar(Text), Length(Text), @Wasm);
    if Err <> nil then
    begin
      AError := 'wat2wasm: ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      ReleaseEngineObjects;
      Exit;
    end;
    WasmPtr := Wasm.Data;
    WasmLen := Wasm.Size;
  end
  else
  begin
    WasmPtr := @Raw[0];
    WasmLen := Length(Raw);
  end;

  Err := Wasmtime.ModuleNew(GEngine, WasmPtr, WasmLen, @FModule);
  if Wasm.Data <> nil then
    Wasmtime.ByteVecDelete(@Wasm);
  if Err <> nil then
  begin
    AError := 'module_new: ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    ReleaseEngineObjects;
    Exit;
  end;

  Trap := nil;
  Err := Wasmtime.LinkerInstantiate(GLinker, FContext, FModule, @FInstance, @Trap);
  if Err <> nil then
  begin
    AError := 'instantiate: ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    WasmtimeClearTrap(Trap);
    ReleaseEngineObjects;
    Exit;
  end;
  if Trap <> nil then
  begin
    AError := 'instantiate trap: ' + WasmtimeTrapMessage(Trap);
    WasmtimeClearTrap(Trap);
    ReleaseEngineObjects;
    Exit;
  end;
  FHasInstance := True;
  Result := True;
end;

function TWasmPluginInstance.InitPlugin(out AError: string): Boolean;
var
  Abi: Int64;
  InitRes: Integer;
begin
  Result := False;
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not CallNoArgsI64('mtn_plugin_get_abi_version', Abi, AError) then
      Exit;
    if Abi <> cPluginAbiVersion then
    begin
      AError := Format('Plugin ABI version %d != host %d', [Abi, cPluginAbiVersion]);
      Exit;
    end;
    if not CallNoArgsI32('mtn_plugin_init', InitRes, AError) then
      Exit;
    if InitRes <> 0 then
    begin
      AError := Format('mtn_plugin_init returned %d', [InitRes]);
      Exit;
    end;
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.CallLastSize(out ASize: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
begin
  ASize := 0;
  AError := '';
  if not GetExportFunc('mtn_last_size', Func) then
    Exit(True);
  Result := CallNoArgsI64('mtn_last_size', ASize, AError);
end;

function TWasmPluginInstance.CallBufferExport(const AExport, AURI: string;
  out ABytes: TBytes; out AStatus: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  UriPtr, UriLen: Integer;
  GotSize: Int64;
begin
  Result := False;
  AStatus := Int64(verIOError);
  SetLength(ABytes, 0);
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not GetExportFunc(AExport, Func) then
    begin
      AStatus := Int64(verNotSupported);
      AError := AExport + ' export missing';
      Exit;
    end;
    if not WriteUriScratch(AURI, UriPtr, UriLen, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := UriPtr;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := UriLen;
    Args[2].Kind := WASMTIME_I32;
    Args[2].Of_.I32 := FOutOff;
    Args[3].Kind := WASMTIME_I32;
    Args[3].Of_.I32 := FOutCap;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], 4, @Rets[0], 1, @Trap);
    if Err <> nil then
    begin
      AError := AExport + ': ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      Exit;
    end;
    if Trap <> nil then
    begin
      AError := AExport + ' trap: ' + WasmtimeTrapMessage(Trap);
      WasmtimeClearTrap(Trap);
      Exit;
    end;
    AStatus := WasmResultI64(Rets[0]);
    if not CallLastSize(GotSize, AError) then
      Exit;
    if AStatus = Int64(verOk) then
    begin
      if not ReadScratchOut(GotSize, ABytes, AError) then
      begin
        AStatus := Int64(verIOError);
        Exit;
      end;
    end;
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.CallExistsExport(const AURI: string;
  out AStatus, AIsDir: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  UriPtr, UriLen: Integer;
begin
  Result := False;
  AStatus := Int64(verIOError);
  AIsDir := 0;
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not GetExportFunc('mtn_vfs_exists', Func) then
    begin
      AStatus := Int64(verNotSupported);
      AError := 'mtn_vfs_exists export missing';
      Exit;
    end;
    if not WriteUriScratch(AURI, UriPtr, UriLen, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := UriPtr;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := UriLen;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], 2, @Rets[0], 1, @Trap);
    if Err <> nil then
    begin
      AError := 'mtn_vfs_exists: ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      Exit;
    end;
    if Trap <> nil then
    begin
      AError := 'mtn_vfs_exists trap: ' + WasmtimeTrapMessage(Trap);
      WasmtimeClearTrap(Trap);
      Exit;
    end;
    AStatus := WasmResultI64(Rets[0]);
    if not CallLastSize(AIsDir, AError) then
      Exit;
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.CallStatusExport(const AExport, AURI: string;
  out AStatus: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  UriPtr, UriLen: Integer;
begin
  Result := False;
  AStatus := Int64(verIOError);
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not GetExportFunc(AExport, Func) then
    begin
      AStatus := Int64(verNotSupported);
      AError := AExport + ' export missing';
      Exit;
    end;
    if not WriteUriScratch(AURI, UriPtr, UriLen, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := UriPtr;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := UriLen;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], 2, @Rets[0], 1, @Trap);
    if Err <> nil then
    begin
      AError := AExport + ': ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      Exit;
    end;
    if Trap <> nil then
    begin
      AError := AExport + ' trap: ' + WasmtimeTrapMessage(Trap);
      WasmtimeClearTrap(Trap);
      Exit;
    end;
    AStatus := WasmResultI64(Rets[0]);
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.CallCopyExport(const AFromURI, AToURI: string;
  AIsDir, AOverwrite: Boolean; out AStatus: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  PtrA, LenA, PtrB, LenB: Integer;
begin
  Result := False;
  AStatus := Int64(verIOError);
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not GetExportFunc('mtn_vfs_copy', Func) then
    begin
      AStatus := Int64(verNotSupported);
      AError := 'mtn_vfs_copy export missing';
      Exit;
    end;
    if not WriteTwoUris(AFromURI, AToURI, PtrA, LenA, PtrB, LenB, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := PtrA;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := LenA;
    Args[2].Kind := WASMTIME_I32;
    Args[2].Of_.I32 := PtrB;
    Args[3].Kind := WASMTIME_I32;
    Args[3].Of_.I32 := LenB;
    Args[4].Kind := WASMTIME_I32;
    Args[4].Of_.I32 := Ord(AIsDir);
    Args[5].Kind := WASMTIME_I32;
    Args[5].Of_.I32 := Ord(AOverwrite);
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], 6, @Rets[0], 1, @Trap);
    if Err <> nil then
    begin
      AError := 'mtn_vfs_copy: ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      Exit;
    end;
    if Trap <> nil then
    begin
      AError := 'mtn_vfs_copy trap: ' + WasmtimeTrapMessage(Trap);
      WasmtimeClearTrap(Trap);
      Exit;
    end;
    AStatus := WasmResultI64(Rets[0]);
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.InvokeVoidExport(const AName: string; out AError: string): Boolean;
begin
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit(False);
    end;
    Result := CallNoArgsVoid(AName, AError);
  finally
    FLock.Release;
  end;
end;

constructor TWasmVfsBackend.Create(AInst: TWasmPluginInstance);
begin
  inherited Create;
  FInst := AInst;
end;

function TWasmVfsBackend.ErrorFromStatus(AStatus: Int64; const AURI, ADetail: string): TVfsError;
begin
  case TVfsCdeclResult(AStatus) of
    verOk: Result := TVfsError.Ok;
    verNotFound: Result := TVfsError.Make(vecNotFound, 'Not found', AURI);
    verAccessDenied: Result := TVfsError.Make(vecAccessDenied, 'Access denied', AURI);
    verAlreadyExists: Result := TVfsError.Make(vecAlreadyExists, 'Already exists', AURI);
    verNotSupported: Result := TVfsError.Make(vecNotSupported, 'Not supported by WASM plugin', AURI);
    verInvalidURI: Result := TVfsError.Make(vecInvalidURI, 'Invalid URI', AURI);
    verNeedsBiggerBuffer: Result := TVfsError.Make(vecIOError,
      'Plugin result exceeded the WASM scratch buffer', AURI);
  else
    if ADetail <> '' then
      Result := TVfsError.Make(vecIOError, ADetail, AURI)
    else
      Result := TVfsError.Make(vecIOError, 'WASM VFS error', AURI);
  end;
end;

procedure TWasmVfsBackend.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  OnDone: TVfsListCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Bytes: TBytes;
      Status: Int64;
      ErrText: string;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
    begin
      SetLength(Items, 0);
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallBufferExport('mtn_vfs_list', URI, Bytes, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else if Status = Int64(verOk) then
      begin
        try
          Items := EntriesFromJson(TEncoding.UTF8.GetString(Bytes));
          Err := TVfsError.Ok;
        except
          on E: Exception do
            Err := TVfsError.Make(vecIOError, 'Bad JSON from WASM plugin: ' + E.Message, URI);
        end;
      end
      else
        Err := ErrorFromStatus(Status, URI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Items, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  OnDone: TVfsExistsCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Status, IsDir: Int64;
      ErrText: string;
      Err: TVfsError;
      Exists: Boolean;
    begin
      Exists := False;
      IsDir := 0;
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallExistsExport(URI, Status, IsDir, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else
      begin
        Exists := Status = Int64(verOk);
        Err := ErrorFromStatus(Status, URI, ErrText);
        if Status = Int64(verNotFound) then
          Err := TVfsError.Ok;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Exists, IsDir <> 0, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  OnDone: TVfsTextCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Bytes: TBytes;
      Status: Int64;
      ErrText, Text: string;
      Err: TVfsError;
    begin
      Text := '';
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallBufferExport('mtn_vfs_read_text', URI, Bytes, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else if Status = Int64(verOk) then
      begin
        Text := TEncoding.UTF8.GetString(Bytes);
        Err := TVfsError.Ok;
      end
      else
        Err := ErrorFromStatus(Status, URI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Text, tfeUtf8, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  OnDone: TVfsBytesCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Bytes: TBytes;
      Status: Int64;
      ErrText: string;
      Err: TVfsError;
    begin
      SetLength(Bytes, 0);
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallBufferExport('mtn_vfs_read_text', URI, Bytes, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else if Status = Int64(verOk) then
        Err := TVfsError.Ok
      else
        Err := ErrorFromStatus(Status, URI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Bytes, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Status: Int64;
      ErrText: string;
      Err: TVfsError;
    begin
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallStatusExport('mtn_vfs_delete', URI, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else
        Err := ErrorFromStatus(Status, URI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
  Inst: TWasmPluginInstance;
begin
  URI := AURI;
  OnDone := AOnDone;
  Inst := FInst;
  TThread.CreateAnonymousThread(
    procedure
    var
      Status: Int64;
      ErrText: string;
      Err: TVfsError;
    begin
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', URI)
      else if not Inst.CallStatusExport('mtn_vfs_mkdir', URI, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, URI)
      else
        Err := ErrorFromStatus(Status, URI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  OnDone: TVfsBoolCallback;
  Inst: TWasmPluginInstance;
  Overwrite: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  OnDone := AOnDone;
  Inst := FInst;
  Overwrite := AOverwrite;
  TThread.CreateAnonymousThread(
    procedure
    var
      Status: Int64;
      ErrText: string;
      Err: TVfsError;
      Path: string;
      IsDir: Boolean;
    begin
      IsDir := False;
      Path := FileUriToPath(FromURI);
      if Path <> '' then
        IsDir := LocalPathIsDirectory(Path);
      if (Inst = nil) or Inst.Dead then
        Err := TVfsError.Make(vecIOError, 'WASM plugin unloaded', FromURI)
      else if not Inst.CallCopyExport(FromURI, ToURI, IsDir, Overwrite, Status, ErrText) then
        Err := TVfsError.Make(vecIOError, ErrText, FromURI)
      else
        Err := ErrorFromStatus(Status, FromURI, ErrText);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Err.Code = vecOk, Err);
        end);
    end).Start;
end;

procedure TWasmVfsBackend.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  if Assigned(AOnDone) then
    TThread.Queue(nil,
      procedure
      begin
        AOnDone(False, TVfsError.Make(vecNotSupported, 'Not supported by WASM plugin', AFromURI));
      end);
end;

procedure TWasmVfsBackend.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  if Assigned(AOnDone) then
    TThread.Queue(nil,
      procedure
      begin
        AOnDone(False, TVfsError.Make(vecNotSupported, 'Not supported by WASM plugin', AURI));
      end);
end;

procedure TWasmVfsBackend.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
begin
  if Assigned(AOnDone) then
    TThread.Queue(nil,
      procedure
      begin
        AOnDone(-1, -1, TVfsError.Make(vecNotSupported, 'Not supported by WASM plugin', ARootURI));
      end);
end;

end.
