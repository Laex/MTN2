unit uWasmtimeApi;

{ Dynamic cdecl bindings to the Wasmtime C API (wasmtime.dll). The DLL is an
  optional runtime — the core exe must start without it (SDS: WASM plugins are
  extensions, not a required dependency). Pinned to the v26 C ABI:

    wasmtime-v26.0.1-x86_64-windows-c-api.zip
    https://github.com/bytecodealliance/wasmtime/releases

  Layout of TWasmtimeVal / TWasmtimeExtern matches the C structs on Win64
  (kind byte + 7 pad + 16-byte union = 24). WASI is never linked: a module
  that imports wasi_snapshot_preview1 fails instantiation instead of seeing
  the host filesystem. }

interface

uses
  System.SysUtils, Winapi.Windows;

const
  WASM_I32 = 0;
  WASM_I64 = 1;

  WASMTIME_I32 = 0;
  WASMTIME_I64 = 1;

  WASMTIME_EXTERN_FUNC = 0;
  WASMTIME_EXTERN_MEMORY = 3;

  cWasmtimeValSize = 24;
  cWasmtimeExternSize = 24;

type
  PWasmEngine = Pointer;
  PWasmConfig = Pointer;
  PWasmFunctype = Pointer;
  PWasmValtype = Pointer;
  PWasmtimeStore = Pointer;
  PWasmtimeContext = Pointer;
  PWasmtimeModule = Pointer;
  PWasmtimeLinker = Pointer;
  PWasmtimeError = Pointer;
  PWasmtimeCaller = Pointer;
  PWasmTrap = Pointer;

  TWasmByteVec = record
    Size: NativeUInt;
    Data: Pointer;
  end;
  PWasmByteVec = ^TWasmByteVec;

  TWasmValtypeVec = record
    Size: NativeUInt;
    Data: Pointer;
  end;
  PWasmValtypeVec = ^TWasmValtypeVec;

  TWasmtimeValUnion = packed record
    case Integer of
      0: (I32: Integer);
      1: (I64: Int64);
      2: (F32: Single);
      3: (F64: Double);
      4: (Pad: array[0..15] of Byte);
  end;

  TWasmtimeVal = packed record
    Kind: Byte;
    _Pad: array[0..6] of Byte;
    Of_: TWasmtimeValUnion;
  end;
  PWasmtimeVal = ^TWasmtimeVal;

  TWasmtimeFunc = packed record
    StoreId: UInt64;
    Private_: NativeUInt;
  end;

  TWasmtimeMemory = TWasmtimeFunc;

  TWasmtimeExternUnion = packed record
    case Integer of
      0: (Func: TWasmtimeFunc);
      1: (Memory: TWasmtimeMemory);
      2: (Pad: array[0..15] of Byte);
  end;

  TWasmtimeExtern = packed record
    Kind: Byte;
    _Pad: array[0..6] of Byte;
    Of_: TWasmtimeExternUnion;
  end;
  PWasmtimeExtern = ^TWasmtimeExtern;

  TWasmtimeInstance = packed record
    StoreId: UInt64;
    Index: NativeUInt;
  end;
  PWasmtimeInstance = ^TWasmtimeInstance;

  TWasmtimeFuncCallback = function(Env: Pointer; Caller: PWasmtimeCaller;
    Args: PWasmtimeVal; NArgs: NativeUInt;
    Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;

  TWasmtimeFns = record
    ConfigNew: function: PWasmConfig; cdecl;
    ConfigDelete: procedure(C: PWasmConfig); cdecl;
    ConfigConsumeFuelSet: procedure(C: PWasmConfig; Enable: Byte); cdecl;
    EngineNewWithConfig: function(C: PWasmConfig): PWasmEngine; cdecl;
    EngineDelete: procedure(E: PWasmEngine); cdecl;
    StoreNew: function(E: PWasmEngine; Data: Pointer; Finalizer: Pointer): PWasmtimeStore; cdecl;
    StoreDelete: procedure(S: PWasmtimeStore); cdecl;
    StoreContext: function(S: PWasmtimeStore): PWasmtimeContext; cdecl;
    StoreLimiter: procedure(S: PWasmtimeStore; MemorySize, TableElements, Instances,
      Tables, Memories: Int64); cdecl;
    ContextGetData: function(Ctx: PWasmtimeContext): Pointer; cdecl;
    ContextSetFuel: function(Ctx: PWasmtimeContext; Fuel: UInt64): PWasmtimeError; cdecl;
    Wat2Wasm: function(Wat: PAnsiChar; WatLen: NativeUInt; Ret: PWasmByteVec): PWasmtimeError; cdecl;
    ModuleNew: function(E: PWasmEngine; Wasm: Pointer; WasmLen: NativeUInt;
      Ret: PPointer): PWasmtimeError; cdecl;
    ModuleDelete: procedure(M: PWasmtimeModule); cdecl;
    LinkerNew: function(E: PWasmEngine): PWasmtimeLinker; cdecl;
    LinkerDelete: procedure(L: PWasmtimeLinker); cdecl;
    LinkerDefineFunc: function(L: PWasmtimeLinker; ModuleName: PAnsiChar; ModuleLen: NativeUInt;
      Name: PAnsiChar; NameLen: NativeUInt; Ty: PWasmFunctype; Cb: TWasmtimeFuncCallback;
      Data: Pointer; Finalizer: Pointer): PWasmtimeError; cdecl;
    LinkerInstantiate: function(L: PWasmtimeLinker; Ctx: PWasmtimeContext; M: PWasmtimeModule;
      Instance: PWasmtimeInstance; Trap: PPointer): PWasmtimeError; cdecl;
    InstanceExportGet: function(Ctx: PWasmtimeContext; Instance: PWasmtimeInstance;
      Name: PAnsiChar; NameLen: NativeUInt; Item: PWasmtimeExtern): Boolean; cdecl;
    FuncCall: function(Ctx: PWasmtimeContext; Func: Pointer; Args: PWasmtimeVal;
      NArgs: NativeUInt; Results: PWasmtimeVal; NResults: NativeUInt;
      Trap: PPointer): PWasmtimeError; cdecl;
    MemoryData: function(Ctx: PWasmtimeContext; Mem: Pointer): PByte; cdecl;
    MemoryDataSize: function(Ctx: PWasmtimeContext; Mem: Pointer): NativeUInt; cdecl;
    CallerContext: function(Caller: PWasmtimeCaller): PWasmtimeContext; cdecl;
    CallerExportGet: function(Caller: PWasmtimeCaller; Name: PAnsiChar; NameLen: NativeUInt;
      Item: PWasmtimeExtern): Boolean; cdecl;
    ErrorMessage: procedure(Err: PWasmtimeError; Msg: PWasmByteVec); cdecl;
    ErrorDelete: procedure(Err: PWasmtimeError); cdecl;
    TrapMessage: procedure(Trap: PWasmTrap; Msg: PWasmByteVec); cdecl;
    TrapDelete: procedure(Trap: PWasmTrap); cdecl;
    ByteVecDelete: procedure(V: PWasmByteVec); cdecl;
    ValtypeNew: function(Kind: Byte): PWasmValtype; cdecl;
    ValtypeVecNewEmpty: procedure(OutVec: PWasmValtypeVec); cdecl;
    ValtypeVecNewUninitialized: procedure(OutVec: PWasmValtypeVec; Size: NativeUInt); cdecl;
    FunctypeNew: function(Params, Results: PWasmValtypeVec): PWasmFunctype; cdecl;
    FunctypeDelete: procedure(T: PWasmFunctype); cdecl;
    ExternDelete: procedure(E: PWasmtimeExtern); cdecl;
  end;

function WasmtimeLoaded: Boolean;
function FindWasmtimeDll: string;
function TryLoadWasmtime(out AError: string): Boolean;
function Wasmtime: TWasmtimeFns;
function WasmtimeErrorMessage(AErr: PWasmtimeError): string;
function WasmtimeTrapMessage(ATrap: PWasmTrap): string;
procedure WasmtimeClearError(var AErr: PWasmtimeError);
procedure WasmtimeClearTrap(var ATrap: PWasmTrap);

implementation

uses
  System.IOUtils;

var
  GLib: HMODULE = 0;
  GFns: TWasmtimeFns;
  GLoaded: Boolean = False;

function Need(const AName: AnsiString; out AProc): Boolean;
begin
  Pointer(AProc) := GetProcAddress(GLib, PAnsiChar(AName));
  Result := Assigned(Pointer(AProc));
end;

function FindWasmtimeDll: string;
var
  Env, ExeDir, ToolsDir: string;
begin
  Env := GetEnvironmentVariable('MTN2_WASMTIME_DLL');
  if (Env <> '') and TFile.Exists(Env) then
    Exit(Env);
  ExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Result := TPath.Combine(ExeDir, 'wasmtime.dll');
  if TFile.Exists(Result) then
    Exit;
  Result := TPath.Combine(TPath.Combine(ExeDir, 'wasmtime'), 'wasmtime.dll');
  if TFile.Exists(Result) then
    Exit;
  ToolsDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(ExeDir)));
  Result := TPath.Combine(TPath.Combine(ToolsDir, 'wasmtime'), 'wasmtime.dll');
  if TFile.Exists(Result) then
    Exit;
  Result := '';
end;

// One guard clause per required C API export, instead of one 34-operand
// boolean expression — same all-or-nothing check, easier to scan/diff.
function AllWasmtimeExportsPresent: Boolean;
begin
  Result := False;
  if not Need('wasm_config_new', GFns.ConfigNew) then Exit;
  if not Need('wasm_config_delete', GFns.ConfigDelete) then Exit;
  if not Need('wasmtime_config_consume_fuel_set', GFns.ConfigConsumeFuelSet) then Exit;
  if not Need('wasm_engine_new_with_config', GFns.EngineNewWithConfig) then Exit;
  if not Need('wasm_engine_delete', GFns.EngineDelete) then Exit;
  if not Need('wasmtime_store_new', GFns.StoreNew) then Exit;
  if not Need('wasmtime_store_delete', GFns.StoreDelete) then Exit;
  if not Need('wasmtime_store_context', GFns.StoreContext) then Exit;
  if not Need('wasmtime_store_limiter', GFns.StoreLimiter) then Exit;
  if not Need('wasmtime_context_get_data', GFns.ContextGetData) then Exit;
  if not Need('wasmtime_context_set_fuel', GFns.ContextSetFuel) then Exit;
  if not Need('wasmtime_wat2wasm', GFns.Wat2Wasm) then Exit;
  if not Need('wasmtime_module_new', GFns.ModuleNew) then Exit;
  if not Need('wasmtime_module_delete', GFns.ModuleDelete) then Exit;
  if not Need('wasmtime_linker_new', GFns.LinkerNew) then Exit;
  if not Need('wasmtime_linker_delete', GFns.LinkerDelete) then Exit;
  if not Need('wasmtime_linker_define_func', GFns.LinkerDefineFunc) then Exit;
  if not Need('wasmtime_linker_instantiate', GFns.LinkerInstantiate) then Exit;
  if not Need('wasmtime_instance_export_get', GFns.InstanceExportGet) then Exit;
  if not Need('wasmtime_func_call', GFns.FuncCall) then Exit;
  if not Need('wasmtime_memory_data', GFns.MemoryData) then Exit;
  if not Need('wasmtime_memory_data_size', GFns.MemoryDataSize) then Exit;
  if not Need('wasmtime_caller_context', GFns.CallerContext) then Exit;
  if not Need('wasmtime_caller_export_get', GFns.CallerExportGet) then Exit;
  if not Need('wasmtime_error_message', GFns.ErrorMessage) then Exit;
  if not Need('wasmtime_error_delete', GFns.ErrorDelete) then Exit;
  if not Need('wasm_trap_message', GFns.TrapMessage) then Exit;
  if not Need('wasm_trap_delete', GFns.TrapDelete) then Exit;
  if not Need('wasm_byte_vec_delete', GFns.ByteVecDelete) then Exit;
  if not Need('wasm_valtype_new', GFns.ValtypeNew) then Exit;
  if not Need('wasm_valtype_vec_new_empty', GFns.ValtypeVecNewEmpty) then Exit;
  if not Need('wasm_valtype_vec_new_uninitialized', GFns.ValtypeVecNewUninitialized) then Exit;
  if not Need('wasm_functype_new', GFns.FunctypeNew) then Exit;
  if not Need('wasm_functype_delete', GFns.FunctypeDelete) then Exit;
  if not Need('wasmtime_extern_delete', GFns.ExternDelete) then Exit;
  Result := True;
end;

function TryLoadWasmtime(out AError: string): Boolean;
var
  Path: string;
begin
  AError := '';
  if GLoaded then
    Exit(True);
  if SizeOf(TWasmtimeVal) <> cWasmtimeValSize then
  begin
    AError := Format('TWasmtimeVal size %d != %d', [SizeOf(TWasmtimeVal), cWasmtimeValSize]);
    Exit(False);
  end;
  if SizeOf(TWasmtimeExtern) <> cWasmtimeExternSize then
  begin
    AError := Format('TWasmtimeExtern size %d != %d', [SizeOf(TWasmtimeExtern), cWasmtimeExternSize]);
    Exit(False);
  end;
  Path := FindWasmtimeDll;
  if Path = '' then
  begin
    AError := 'wasmtime.dll not found (set MTN2_WASMTIME_DLL)';
    Exit(False);
  end;
  GLib := LoadLibrary(PChar(Path));
  if GLib = 0 then
  begin
    AError := Format('LoadLibrary(%s) failed (GetLastError=%d)', [Path, GetLastError]);
    Exit(False);
  end;
  if not AllWasmtimeExportsPresent then
  begin
    AError := 'wasmtime.dll is missing a required C API export (need v26 c-api)';
    FreeLibrary(GLib);
    GLib := 0;
    FillChar(GFns, SizeOf(GFns), 0);
    Exit(False);
  end;
  GLoaded := True;
  Result := True;
end;

function WasmtimeLoaded: Boolean;
begin
  Result := GLoaded;
end;

function Wasmtime: TWasmtimeFns;
begin
  Result := GFns;
end;

function VecToString(const AVec: TWasmByteVec): string;
var
  Bytes: TBytes;
  N: Integer;
begin
  if (AVec.Data = nil) or (AVec.Size = 0) then
    Exit('');
  N := Integer(AVec.Size);
  if PByte(AVec.Data)[N - 1] = 0 then
    Dec(N);
  if N <= 0 then
    Exit('');
  SetLength(Bytes, N);
  Move(AVec.Data^, Bytes[0], N);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function WasmtimeErrorMessage(AErr: PWasmtimeError): string;
var
  Msg: TWasmByteVec;
begin
  Result := '';
  if AErr = nil then
    Exit;
  FillChar(Msg, SizeOf(Msg), 0);
  GFns.ErrorMessage(AErr, @Msg);
  Result := VecToString(Msg);
  GFns.ByteVecDelete(@Msg);
end;

function WasmtimeTrapMessage(ATrap: PWasmTrap): string;
var
  Msg: TWasmByteVec;
begin
  Result := '';
  if ATrap = nil then
    Exit;
  FillChar(Msg, SizeOf(Msg), 0);
  GFns.TrapMessage(ATrap, @Msg);
  Result := VecToString(Msg);
  GFns.ByteVecDelete(@Msg);
end;

procedure WasmtimeClearError(var AErr: PWasmtimeError);
begin
  if AErr <> nil then
  begin
    GFns.ErrorDelete(AErr);
    AErr := nil;
  end;
end;

procedure WasmtimeClearTrap(var ATrap: PWasmTrap);
begin
  if ATrap <> nil then
  begin
    GFns.TrapDelete(ATrap);
    ATrap := nil;
  end;
end;

end.
