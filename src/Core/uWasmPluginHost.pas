unit uWasmPluginHost;

{ WASM plugin runtime on top of optional Wasmtime (uWasmtimeApi.pas).

  Isolation contract:
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

  Guest ABI (not the cdecl THostApiTable - those pointers would be a shared
  address space). Imports on module "mtn_host":
    register_vfs_scheme(ptr, len, priority) -> i32
    register_panel_plugin(ptr, len, priority) -> i32
    register_menu_item(parent_ptr, parent_len, id_ptr, id_len,
      caption_ptr, caption_len, export_ptr, export_len, priority) -> i32
    publish(topic_ptr, topic_len, json_ptr, json_len) -> i32
    register_command(id_ptr, id_len, export_ptr, export_len) -> i32
      // plugin command; the guest export "export" takes no arguments
    register_command_hook(cmd_ptr, cmd_len, export_ptr, export_len, priority) -> i32
      // hook on a built-in command ("Copy", "View", ...); the guest export
      // takes no arguments and returns i32: 1 = handled (built-in skipped)
    execute_command(id_ptr, id_len) -> i32            // plugin command by id
    register_panel_activate(scheme_ptr, scheme_len, export_ptr, export_len) -> i32
      // Enter on a row of a panel with that scheme; the guest export takes
      // (row_uri_ptr, row_uri_len) -> i64: 1 = the plugin dealt with the row
    set_command_caption(id_ptr, id_len, caption_ptr, caption_len) -> i32
      // function bar label of a plugin command bound to an F-key chord
    set_status_segment(id_ptr, id_len, text_ptr, text_len) -> i32
      // named text segment of the panels' status line; empty text removes it
    register_settings(export_ptr, export_len) -> i32
      // the guest export takes no arguments; the Plugins dialog calls it for Settings
    get_setting(key_ptr, key_len, out_ptr, out_cap) -> i32
      // the value's length in bytes (no NUL written); -1 = never set, -2 = out_cap too small
    set_setting(key_ptr, key_len, value_ptr, value_len) -> i32   // 0 = stored
    register_key_binding(action_ptr, action_len, combo_ptr, combo_len) -> i32
      // "Ctrl+Alt+F7" for a plugin command or for a built-in action name
    show_dialog(json_ptr, json_len, export_ptr, export_len) -> i32
      // dialog declaration JSON; the guest export takes
      // (id_ptr, id_len, values_ptr, values_len) with the control id and the
      // values JSON of the answer (values over 2 KiB arrive empty)
    surface_open(title_ptr, title_len, key_ptr, key_len, tick_ptr, tick_len,
      closed_ptr, closed_len) -> i32
      // opens a viewer tab for a picture the guest supplies; returns the
      // handle (above 0) or -1. The guest exports named by key / tick /
      // closed (empty name = none): key takes (key_ptr, key_len) with a name
      // like "Left", "Space", "Ctrl+C" and returns i64 (1 = the key was used);
      // tick and closed take no arguments (closed is not called when the
      // guest closed the tab itself). Esc and F10 always close the tab.
    surface_set_frame(handle, width, height, pixels_ptr, pixels_len) -> i32
      // width x height pixels of 4 bytes in B, G, R, A order, rows top to
      // bottom without padding; the host copies them. 0 = shown
    surface_set_info(handle, title_ptr, title_len, status_ptr, status_len) -> i32
      // tab title and status line text
    surface_set_timer(handle, interval_ms) -> i32
      // tick every interval_ms milliseconds while the tab is on screen; 0 stops
    surface_close(handle) -> i32
    surface_open_ex(title_ptr, title_len, mode, key_ptr, key_len, tick_ptr, tick_len,
      closed_ptr, closed_len, mouse_ptr, mouse_len) -> i32
      // as surface_open with a place (mode 0 tab, 1 full screen, 2 the panel opposite the
      // active one; no native windows for guests) and a mouse export taking
      // (kind, x, y, width, height, button, extra, shift) and returning i64 (1 = used);
      // kinds: 0 down, 1 up, 2 move while a button is held, 3 wheel, 4 double click
    surface_set_fullscreen(handle, on) -> i32
    surface_get_fullscreen(handle) -> i32         // 1 full screen, 0 not, -1 unknown handle
    panel_list(side, out_ptr, out_cap) -> i32     // JSON rows of a panel
    panel_set_cursor(side, uri_ptr, uri_len) -> i32
    panel_select(side, mode, arg_ptr, arg_len) -> i32 // 0 select mask, 1 unselect mask,
      // 2 clear, 3 select URI, 4 unselect URI
    doc_set_selection(row1, col1, row2, col2) -> i32
    doc_line(index, out_ptr, out_cap) -> i32
    progress_set(id_ptr, id_len, text_ptr, text_len, percent) -> i32 // percent < 0: none
    progress_end(id_ptr, id_len) -> i32
    register_highlighter(ext_ptr, ext_len, export_ptr, export_len) -> i32
      // colors lines of files with those extensions: the guest export takes
      // (line_ptr, line_len, out_ptr, out_cap) with out_cap spans of three 32-bit
      // integers (start byte, byte length, class 0..11) and returns the number written
    vfs_list(uri_ptr, uri_len, export_ptr, export_len) -> i32
    vfs_exists(uri_ptr, uri_len, export_ptr, export_len) -> i32
    vfs_read(uri_ptr, uri_len, max_bytes, export_ptr, export_len) -> i32
      // need the permission "vfs.read" (manifest + the user's grant). Each starts the job and
      // returns a handle (above 0), -1 for bad arguments or -2 without the permission. Later,
      // on the main thread, the guest export takes (handle, status) and returns nothing;
      // status 0 = ok, 1 not found, 2 denied, 3 not supported or too large, 4 cancelled,
      // 5 I/O error, 6 invalid URI
    vfs_result(handle, out_ptr, out_cap) -> i32
      // the result of a finished job (JSON for vfs_list and vfs_exists, the bytes for
      // vfs_read): its length; copied only when length <= out_cap (a longer result stays
      // for another call with a bigger buffer), and then the handle is released; -1 = no such result
    vfs_open(uri_ptr, uri_len, export_ptr, export_len) -> i32
      // reads a file of any size in pieces (permission "vfs.read"). Returns a job handle (above
      // 0), -1 for bad arguments, -2 without the permission or -3 when 16 files are already
      // open or opening. Later, on the main thread, the guest export takes (job, status, file)
      // and returns nothing; status as for vfs_read, file is the handle for the calls below
      // (above 0 when the status is 0). A local file is opened in place; any other URI is
      // first copied to a temporary file, and the host shows a progress notice meanwhile
    vfs_cancel(job) -> i32
      // cancels a vfs_open that has not finished: its export still follows once, with status 4.
      // 0 = cancelled, -1 = no such job
    vfs_size(file) -> i64                         // bytes; -1 = unknown handle
    vfs_read_at(file, offset_i64, out_ptr, out_cap) -> i64
      // reads up to out_cap bytes (at most 16 MiB per call) from offset; returns the number
      // read, 0 at the end of the file, a negative number on an error
    vfs_close(file) -> i32                        // 0 = closed, -1 = unknown handle; a
      // plugin's open files are closed when it is unloaded
    host_info(out_ptr, out_cap) -> i32            // JSON with "version" and "language"
    doc_info(out_ptr, out_cap) -> i32             // JSON about the active text document
    doc_get_text(what, out_ptr, out_cap) -> i32   // 0 selection, 1 whole document (LF), 2 cursor line
    doc_replace(what, text_ptr, text_len) -> i32  // as doc_get_text; one undo step; 0 = done
    doc_set_cursor(row, col) -> i32
    panel_info(out_ptr, out_cap) -> i32           // JSON about both file panels
    panel_goto(side, uri_ptr, uri_len) -> i32     // side 0 left, 1 right, -1 active; 0 = done
    panel_refresh() -> i32
    clipboard_get(out_ptr, out_cap) -> i32
    clipboard_set(text_ptr, text_len) -> i32
    show_message(text_ptr, text_len, kind) -> i32 // kind 0 information, 1 warning
      // Text results: the length in bytes (no NUL written); the text is written only
      // when length <= out_cap, so a longer result means "call again with a bigger
      // buffer"; -1 = not available.
    subscribe(topic_ptr, topic_len, export_ptr, export_len) -> i32
      // host events "doc.opened", "doc.saved", "doc.closed" ("*" = all); the guest
      // export takes (topic_ptr, topic_len, payload_ptr, payload_len) with the
      // payload JSON holding the document "uri" (payloads over 2 KiB arrive empty)
    register_document_provider(ext_ptr, ext_len, export_ptr, export_len,
      modes, priority) -> i32
      // extensions ".md,.markdown" or "*"; modes bit 0 = view, bit 1 = edit;
      // the guest export takes (uri_ptr, uri_len) -> i64: 0 = not mine,
      // 1 = the plugin handled the file. A guest cannot redirect or launch
      // programs (no open_external import): that stays native-only.
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
  System.SysUtils, System.SyncObjs, System.Generics.Collections,
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
    FWasi: Boolean;
    FScratchBase: Integer;
    FUriOff: Integer;
    FUriSlot: Integer;
    FOutOff: Integer;
    FOutCap: Integer;
    FVfsResults: TDictionary<Integer, TBytes>;
    FVfsNext: Integer;
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
    /// <summary>Calls a guest export taking 32-bit integers and returning i64.</summary>
    function CallIntsExport(const AExport: string; const AArgs: array of Integer;
      out AStatus: Int64; out AError: string): Boolean;
    /// <summary>Asks a highlighter export (line_ptr, line_len, out_ptr, out_cap) for the
    /// spans of ALine: 12 bytes each, ACount of them.</summary>
    function CallHighlightExport(const AExport, ALine: string; out ASpans: TBytes;
      out ACount: Integer; out AError: string): Boolean;
    /// <summary>Calls a guest export taking 32-bit integers and returning nothing.</summary>
    function CallIntsVoidExport(const AExport: string; const AArgs: array of Integer;
      out AError: string): Boolean;
    /// <summary>Handle for a file system job whose result the guest will fetch later.</summary>
    function ReserveVfsHandle: Integer;
    procedure StoreVfsResult(AHandle: Integer; const AData: TBytes);
    /// <summary>The result stays for another try when it does not fit ACap.</summary>
    function TakeVfsResult(AHandle, ACap: Integer; out AData: TBytes): Integer;
    function InvokeVoidExport(const AName: string; out AError: string): Boolean;
    function InvokeI32Export(const AName: string; out AValue: Integer;
      out AError: string): Boolean;
    /// <summary>Calls a guest export (ptr_a, len_a, ptr_b, len_b) with no
    /// result, the two strings copied into the guest scratch area (each must
    /// stay under 2 KiB).</summary>
    function InvokeTwoStringExport(const AName, A, B: string; out AError: string): Boolean;
    property PluginId: string read FPluginId;
    property Dead: Boolean read FDead;
    /// <summary>The module may import WASI preview1 (empty: no files, no
    /// environment). Set before LoadFromFile.</summary>
    property Wasi: Boolean read FWasi write FWasi;
  end;

function EnsureWasmEngine(out AError: string): Boolean;
function WasmEngineAvailable: Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.Math,
  uVfsTypes, uTextEncoding, uVfsCdeclAdapter, uVfsRegistry, uPanelPluginRegistry,
  uMenuRegistry, uCommandRegistry, uDocumentProviders, uPluginUi, uPluginChrome, uKeymap,
  uKeymapRegistry, uPluginSettings, uPluginSurface, uPluginServices, uPluginHighlight,
  uPluginVfs;

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
  cRegCommand: AnsiString = 'register_command';
  cRegCommandHook: AnsiString = 'register_command_hook';
  cExecCommand: AnsiString = 'execute_command';
  cRegDocProvider: AnsiString = 'register_document_provider';
  cShowDialog: AnsiString = 'show_dialog';
  cSurfaceOpen: AnsiString = 'surface_open';
  cSurfaceSetFrame: AnsiString = 'surface_set_frame';
  cSurfaceSetInfo: AnsiString = 'surface_set_info';
  cSurfaceSetTimer: AnsiString = 'surface_set_timer';
  cSurfaceClose: AnsiString = 'surface_close';
  cSurfaceOpenEx: AnsiString = 'surface_open_ex';
  cSurfaceSetFullscreen: AnsiString = 'surface_set_fullscreen';
  cPanelList: AnsiString = 'panel_list';
  cPanelSetCursor: AnsiString = 'panel_set_cursor';
  cPanelSelect: AnsiString = 'panel_select';
  cDocSetSelection: AnsiString = 'doc_set_selection';
  cDocLine: AnsiString = 'doc_line';
  cProgressSet: AnsiString = 'progress_set';
  cProgressEnd: AnsiString = 'progress_end';
  cRegHighlighter: AnsiString = 'register_highlighter';
  cVfsList: AnsiString = 'vfs_list';
  cVfsExists: AnsiString = 'vfs_exists';
  cVfsRead: AnsiString = 'vfs_read';
  cVfsResult: AnsiString = 'vfs_result';
  cVfsOpen: AnsiString = 'vfs_open';
  cVfsSize: AnsiString = 'vfs_size';
  cVfsReadAt: AnsiString = 'vfs_read_at';
  cVfsClose: AnsiString = 'vfs_close';
  cVfsCancel: AnsiString = 'vfs_cancel';
  cSurfaceGetFullscreen: AnsiString = 'surface_get_fullscreen';
  cHostInfo: AnsiString = 'host_info';
  cDocInfo: AnsiString = 'doc_info';
  cDocGetText: AnsiString = 'doc_get_text';
  cDocReplace: AnsiString = 'doc_replace';
  cDocSetCursor: AnsiString = 'doc_set_cursor';
  cPanelInfo: AnsiString = 'panel_info';
  cPanelGoto: AnsiString = 'panel_goto';
  cPanelRefresh: AnsiString = 'panel_refresh';
  cClipboardGet: AnsiString = 'clipboard_get';
  cClipboardSet: AnsiString = 'clipboard_set';
  cShowMessage: AnsiString = 'show_message';
  cSubscribe: AnsiString = 'subscribe';
  cRegPanelActivate: AnsiString = 'register_panel_activate';
  cRegKeyBinding: AnsiString = 'register_key_binding';
  cRegSettings: AnsiString = 'register_settings';
  cGetSetting: AnsiString = 'get_setting';
  cSetSetting: AnsiString = 'set_setting';
  cSetCaption: AnsiString = 'set_command_caption';
  cSetStatusSegment: AnsiString = 'set_status_segment';

var
  GEngine: PWasmEngine = nil;
  GLinker: PWasmtimeLinker = nil;
  /// <summary>Linker for plugins whose manifest asks for WASI: the same host
  /// imports plus an empty WASI (no files, no environment, no arguments).</summary>
  GWasiLinker: PWasmtimeLinker = nil;
  GDefineLinker: PWasmtimeLinker = nil;

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

procedure SetI64Result(Results: PWasmtimeVal; NResults: NativeUInt; AValue: Int64);
begin
  if (Results = nil) or (NResults = 0) then
    Exit;
  FillChar(Results^, SizeOf(TWasmtimeVal), 0);
  Results^.Kind := WASMTIME_I64;
  Results^.Of_.I64 := AValue;
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

/// <summary>Copies ALen bytes of guest memory at APtr into ABytes.</summary>
function ReadGuestBytes(Caller: PWasmtimeCaller; APtr, ALen: Integer;
  out ABytes: TBytes): Boolean;
var
  Ctx: PWasmtimeContext;
  Ext: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
begin
  Result := False;
  ABytes := nil;
  if (Caller = nil) or (APtr < 0) or (ALen <= 0) then
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
    if (Data = nil) or (NativeUInt(APtr) + NativeUInt(ALen) > Size) then
      Exit;
    SetLength(ABytes, ALen);
    Move(Data[APtr], ABytes[0], ALen);
    Result := True;
  finally
    Wasmtime.ExternDelete(@Ext);
  end;
end;

/// <summary>Copies ABytes into guest memory at APtr (at most ACap bytes).</summary>
function WriteGuestBytes(Caller: PWasmtimeCaller; APtr, ACap: Integer;
  const ABytes: TBytes): Boolean;
var
  Ctx: PWasmtimeContext;
  Ext: TWasmtimeExtern;
  Data: PByte;
  Size: NativeUInt;
begin
  Result := False;
  if (Caller = nil) or (APtr < 0) or (ACap < 0) or (Length(ABytes) > ACap) then
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
    if (Data = nil) or (NativeUInt(APtr) + NativeUInt(Length(ABytes)) > Size) then
      Exit;
    if Length(ABytes) > 0 then
      Move(ABytes[0], Data[APtr], Length(ABytes));
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
  // Drive-bar schemes (ws, recycle, ...) are built-in. A WASM module may still
  // call register_vfs_scheme; ignore it so File VFS / the core backend stay
  // in charge and an empty panel does not become "Invalid path".
  if IsReservedVfsScheme(Scheme) then
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

function HostRegCommand(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  CommandId, ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, CommandId) or
     (CommandId = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  CommandRegistry.RegisterCommand(Inst.PluginId, CommandId,
    procedure
    var
      Err: string;
    begin
      if (Inst = nil) or Inst.Dead then
        Exit;
      Inst.InvokeVoidExport(ExportName, Err);
    end);
  if CommandRegistry.HasCommand(CommandId) then
    SetI32Result(Results, NResults, 0);
end;

function HostRegCommandHook(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Command, ExportName: string;
  Prio: Integer;
  Act: TKeymapAction;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 5 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Command) or
     not TryKeymapActionByName(Command, Act) then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  Prio := Vals^[4].Of_.I32;
  CommandRegistry.RegisterHook(Inst.PluginId, Command,
    function(const ACommand, AOrigin: string): Boolean
    var
      Handled: Integer;
      Err: string;
    begin
      Result := False;
      if (Inst = nil) or Inst.Dead then
        Exit;
      Result := Inst.InvokeI32Export(ExportName, Handled, Err) and (Handled = 1);
    end, Prio);
  SetI32Result(Results, NResults, 0);
end;

function HostExecCommand(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  CommandId: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, CommandId) or
     (CommandId = '') then
    Exit;
  if CommandRegistry.TryExecute(CommandId) then
    SetI32Result(Results, NResults, 0);
end;

function HostRegDocProvider(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Extensions, ExportName: string;
  ModeBits, Prio: Integer;
  Modes: TDocumentModes;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 6 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Extensions) or
     (Extensions = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  ModeBits := Vals^[4].Of_.I32;
  Prio := Vals^[5].Of_.I32;
  Modes := [];
  if (ModeBits and 1) <> 0 then
    Include(Modes, dmView);
  if (ModeBits and 2) <> 0 then
    Include(Modes, dmEdit);
  if Modes = [] then
    Exit;
  DocumentProviders.RegisterProvider(Inst.PluginId, 'wasm:' + ExportName, Extensions, Modes,
    function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
    var
      Status: Int64;
      Err: string;
    begin
      ARedirectURI := '';
      Result := dokPass;
      if (Inst = nil) or Inst.Dead then
        Exit;
      if Inst.CallStatusExport(ExportName, AURI, Status, Err) and (Status = 1) then
        Result := dokHandled;
    end, Prio);
  SetI32Result(Results, NResults, 0);
end;

function HostShowDialog(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Json, ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Json) or (Json = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  if PluginShowDialog(Inst.PluginId, Json,
    procedure(const AControlId, AValuesJson: string)
    var
      Err, Values: string;
    begin
      if (Inst = nil) or Inst.Dead then
        Exit;
      Values := AValuesJson;
      if Length(UTF8String(Values)) >= 2047 then
        Values := '';
      Inst.InvokeTwoStringExport(ExportName, AControlId, Values, Err);
    end) then
    SetI32Result(Results, NResults, 0);
end;

/// <summary>Result of a text-returning import: its length; the text itself is
/// written to the guest only when it fits.</summary>
procedure ReturnGuestText(Caller: PWasmtimeCaller; APtr, ACap: Integer; const AText: string;
  Results: PWasmtimeVal; NResults: NativeUInt);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > ACap then
  begin
    SetI32Result(Results, NResults, Length(Bytes));
    Exit;
  end;
  if (Length(Bytes) = 0) or WriteGuestBytes(Caller, APtr, ACap, Bytes) then
    SetI32Result(Results, NResults, Length(Bytes));
end;

function HostHostInfo(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  ReturnGuestText(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, PluginHostInfoJson, Results, NResults);
end;

function HostDocInfo(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Json: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginDocInfo(Json) then
    ReturnGuestText(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Json, Results, NResults);
end;

function HostDocGetText(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if PluginDocGetText(Vals^[0].Of_.I32, Text) then
    ReturnGuestText(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Text, Results, NResults);
end;

function HostDocReplace(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Text) and
     PluginDocReplace(Vals^[0].Of_.I32, Text) then
    SetI32Result(Results, NResults, 0);
end;

function HostDocSetCursor(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginDocSetCursor(Vals^[0].Of_.I32, Vals^[1].Of_.I32) then
    SetI32Result(Results, NResults, 0);
end;

function HostPanelInfo(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Json: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginPanelInfo(Json) then
    ReturnGuestText(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Json, Results, NResults);
end;

function HostPanelGoto(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Uri: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Uri) and
     PluginPanelGoto(Vals^[0].Of_.I32, Uri) then
    SetI32Result(Results, NResults, 0);
end;

function HostPanelRefresh(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if PluginPanelRefresh then
    SetI32Result(Results, NResults, 0);
end;

function HostClipboardGet(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginClipboardGet(Text) then
    ReturnGuestText(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Text, Results, NResults);
end;

function HostClipboardSet(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Text) and
     PluginClipboardSet(Text) then
    SetI32Result(Results, NResults, 0);
end;

function HostShowMessage(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Text) then
  begin
    PluginShowMessage(Text, Vals^[2].Of_.I32);
    SetI32Result(Results, NResults, 0);
  end;
end;

function HostSubscribe(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Topic, ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Topic) or (Topic = '') or
     not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  PluginSubscribe(Inst.PluginId, Topic,
    procedure(const ATopic, APayloadJson: string)
    var
      Err, Payload: string;
    begin
      if (Inst = nil) or Inst.Dead then
        Exit;
      Payload := APayloadJson;
      if Length(UTF8String(Payload)) >= 2047 then
        Payload := '';
      Inst.InvokeTwoStringExport(ExportName, ATopic, Payload, Err);
    end);
  SetI32Result(Results, NResults, 0);
end;

function HostSurfaceOpenEx(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Title, KeyExport, TickExport, ClosedExport, MouseExport: string;
  Mode: Integer;
  OnKey: TSurfaceKeyCallback;
  OnTick, OnClosed: TProc;
  OnMouse: TSurfaceMouseCallback;
  Handle: Integer;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 11 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  Mode := Vals^[2].Of_.I32;
  // Native windows belong to native plugins.
  if (Mode and cSurfaceNativeFlag) <> 0 then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Title) or
     not ReadGuestUtf8(Caller, Vals^[3].Of_.I32, Vals^[4].Of_.I32, KeyExport) or
     not ReadGuestUtf8(Caller, Vals^[5].Of_.I32, Vals^[6].Of_.I32, TickExport) or
     not ReadGuestUtf8(Caller, Vals^[7].Of_.I32, Vals^[8].Of_.I32, ClosedExport) or
     not ReadGuestUtf8(Caller, Vals^[9].Of_.I32, Vals^[10].Of_.I32, MouseExport) then
    Exit;
  OnKey := nil;
  OnTick := nil;
  OnClosed := nil;
  OnMouse := nil;
  if KeyExport <> '' then
    OnKey := function(const AKey: string): Boolean
      var
        Status: Int64;
        Err: string;
      begin
        Result := (Inst <> nil) and not Inst.Dead and
          Inst.CallStatusExport(KeyExport, AKey, Status, Err) and (Status = 1);
      end;
  if TickExport <> '' then
    OnTick := procedure
      var
        Err: string;
      begin
        if (Inst <> nil) and not Inst.Dead then
          Inst.InvokeVoidExport(TickExport, Err);
      end;
  if ClosedExport <> '' then
    OnClosed := procedure
      var
        Err: string;
      begin
        if (Inst <> nil) and not Inst.Dead then
          Inst.InvokeVoidExport(ClosedExport, Err);
      end;
  if MouseExport <> '' then
    OnMouse := function(AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift: Integer): Boolean
      var
        Status: Int64;
        Err: string;
      begin
        Result := (Inst <> nil) and not Inst.Dead and
          Inst.CallIntsExport(MouseExport, [AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift],
            Status, Err) and (Status = 1);
      end;
  Handle := PluginSurfaceOpenEx(Inst.PluginId, Title, Mode, OnKey, OnTick, OnClosed, OnMouse);
  if Handle > 0 then
    SetI32Result(Results, NResults, Handle);
end;

function HostSurfaceSetFullscreen(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginSurfaceSetFullscreen(Vals^[0].Of_.I32, Vals^[1].Of_.I32 <> 0) then
    SetI32Result(Results, NResults, 0);
end;

function HostPanelList(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Json: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if PluginPanelList(Vals^[0].Of_.I32, Json) then
    ReturnGuestText(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Json, Results, NResults);
end;

function HostPanelSetCursor(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Uri: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Uri) and
     PluginPanelSetCursor(Vals^[0].Of_.I32, Uri) then
    SetI32Result(Results, NResults, 0);
end;

function HostPanelSelect(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Arg: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Arg) and
     PluginPanelSelect(Vals^[0].Of_.I32, Vals^[1].Of_.I32, Arg) then
    SetI32Result(Results, NResults, 0);
end;

function HostDocSetSelection(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Vals := Pointer(Args);
  if PluginDocSetSelection(Vals^[0].Of_.I32, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Vals^[3].Of_.I32) then
    SetI32Result(Results, NResults, 0);
end;

function HostDocLine(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Vals := Pointer(Args);
  if PluginDocLine(Vals^[0].Of_.I32, Text) then
    ReturnGuestText(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Text, Results, NResults);
end;

function HostProgressSet(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Id, Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 5 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Id) and
     ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Text) then
  begin
    PluginProgressSet(Inst.PluginId, Id, Text, Vals^[4].Of_.I32);
    SetI32Result(Results, NResults, 0);
  end;
end;

function HostProgressEnd(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Id: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Id) then
  begin
    PluginProgressEnd(Inst.PluginId, Id);
    SetI32Result(Results, NResults, 0);
  end;
end;

/// <summary>Starts a file system job for the guest: AKind 0 list, 1 exists, 2 read. The
/// guest export named by the last two arguments hears (handle, status) when it is done.</summary>
function StartGuestVfs(Caller: PWasmtimeCaller; Args: PWasmtimeVal; NArgs: NativeUInt;
  AKind: Integer): Integer;
var
  Inst: TWasmPluginInstance;
  Uri, ExportName: string;
  Vals: ^TValBuf;
  ExpIdx, Handle, Rc: Integer;
  MaxBytes: Int64;
  Finish: TPluginVfsDataDone;
begin
  Result := -1;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if AKind = 2 then
  begin
    if NArgs < 5 then
      Exit;
    ExpIdx := 3;
    MaxBytes := Vals^[2].Of_.I32;
  end
  else
  begin
    if NArgs < 4 then
      Exit;
    ExpIdx := 2;
    MaxBytes := 0;
  end;
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Uri) or (Uri = '') or
     not ReadGuestUtf8(Caller, Vals^[ExpIdx].Of_.I32, Vals^[ExpIdx + 1].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  Handle := Inst.ReserveVfsHandle;
  Finish :=
    procedure(AStatus: Integer; const AData: TBytes)
    var
      Err: string;
    begin
      if Inst.Dead then
        Exit;
      if AStatus = 0 then
        Inst.StoreVfsResult(Handle, AData);
      Inst.CallIntsVoidExport(ExportName, [Handle, AStatus], Err);
    end;
  case AKind of
    0:
      Rc := PluginVfsList(Inst.PluginId, Uri,
        procedure(AStatus: Integer; const AText: string)
        begin
          Finish(AStatus, TEncoding.UTF8.GetBytes(AText));
        end);
    1:
      Rc := PluginVfsExists(Inst.PluginId, Uri,
        procedure(AStatus: Integer; const AText: string)
        begin
          Finish(AStatus, TEncoding.UTF8.GetBytes(AText));
        end);
  else
    Rc := PluginVfsRead(Inst.PluginId, Uri, MaxBytes,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        Finish(AStatus, AData);
      end);
  end;
  if Rc = 0 then
    Result := Handle
  else
    Result := Rc;
end;

function HostVfsList(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
begin
  Result := nil;
  SetI32Result(Results, NResults, StartGuestVfs(Caller, Args, NArgs, 0));
end;

function HostVfsExists(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
begin
  Result := nil;
  SetI32Result(Results, NResults, StartGuestVfs(Caller, Args, NArgs, 1));
end;

function HostVfsRead(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
begin
  Result := nil;
  SetI32Result(Results, NResults, StartGuestVfs(Caller, Args, NArgs, 2));
end;

function HostVfsResult(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Data: TBytes;
  Vals: ^TValBuf;
  Len: Integer;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 3 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  Len := Inst.TakeVfsResult(Vals^[0].Of_.I32, Vals^[2].Of_.I32, Data);
  if Len < 0 then
    Exit;
  if Len <= Vals^[2].Of_.I32 then
  begin
    if (Len > 0) and not WriteGuestBytes(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Data) then
      Exit;
  end;
  SetI32Result(Results, NResults, Len);
end;

function HostVfsOpen(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Uri, ExportName: string;
  Vals: ^TValBuf;
  Job: Int64;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Uri) or (Uri = '') or
     not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  // The callback runs after this call returned, so Job is set by then.
  Job := PluginVfsOpen(Inst.PluginId, Uri,
    procedure(AStatus: Integer; AHandle: Int64)
    var
      Err: string;
    begin
      if Inst.Dead then
      begin
        if AHandle > 0 then
          PluginVfsClose(Inst.PluginId, AHandle);
        Exit;
      end;
      Inst.CallIntsVoidExport(ExportName, [Integer(Job), AStatus, Integer(AHandle)], Err);
    end);
  SetI32Result(Results, NResults, Integer(Job));
end;

function HostVfsCancel(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 1 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  SetI32Result(Results, NResults, Integer(PluginVfsCancel(Inst.PluginId, Vals^[0].Of_.I32)));
end;

function HostSurfaceGetFullscreen(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 1 then
    Exit;
  Vals := Pointer(Args);
  if not SurfaceExists(Vals^[0].Of_.I32) then
    Exit;
  if SurfaceFullscreen(Vals^[0].Of_.I32) then
    SetI32Result(Results, NResults, 1)
  else
    SetI32Result(Results, NResults, 0);
end;

function HostVfsSize(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI64Result(Results, NResults, -1);
  if NArgs < 1 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  SetI64Result(Results, NResults, PluginVfsSize(Inst.PluginId, Vals^[0].Of_.I32));
end;

function HostVfsReadAt(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
const
  cMaxChunk = 16 * 1024 * 1024;
var
  Inst: TWasmPluginInstance;
  Vals: ^TValBuf;
  Buf: TBytes;
  Cap: Integer;
  N: Int64;
begin
  Result := nil;
  SetI64Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  Cap := Vals^[3].Of_.I32;
  if Cap < 0 then
    Exit;
  if Cap > cMaxChunk then
    Cap := cMaxChunk;
  SetLength(Buf, Cap);
  if Cap > 0 then
    N := PluginVfsReadAt(Inst.PluginId, Vals^[0].Of_.I32, Vals^[1].Of_.I64, @Buf[0], Cap)
  else
    N := PluginVfsReadAt(Inst.PluginId, Vals^[0].Of_.I32, Vals^[1].Of_.I64, @Cap, 0);
  if N <= 0 then
  begin
    SetI64Result(Results, NResults, N);
    Exit;
  end;
  SetLength(Buf, N);
  if WriteGuestBytes(Caller, Vals^[2].Of_.I32, Cap, Buf) then
    SetI64Result(Results, NResults, N);
end;

function HostVfsClose(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 1 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  SetI32Result(Results, NResults, Integer(PluginVfsClose(Inst.PluginId, Vals^[0].Of_.I32)));
end;

function HostRegHighlighter(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Extensions, ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Extensions) or (Extensions = '') or
     not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or (ExportName = '') then
    Exit;
  RegisterHighlighter(Inst.PluginId, Extensions,
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    var
      Bytes: TBytes;
      Count, I, B, Units: Integer;
      U: UTF8String;
      Map: TArray<Integer>;
      Start, Stop, Len, Kind: Integer;
      Err: string;
    begin
      ASpans := nil;
      Result := False;
      if (Inst = nil) or Inst.Dead or
         not Inst.CallHighlightExport(ExportName, ALine, Bytes, Count, Err) or (Count <= 0) then
        Exit;
      // The guest counts bytes; the program counts UTF-16 characters.
      U := UTF8String(ALine);
      SetLength(Map, Length(U) + 1);
      Units := 0;
      for B := 0 to Length(U) - 1 do
      begin
        Map[B] := Units;
        if (Byte(U[B + 1]) and $C0) <> $80 then
        begin
          if Byte(U[B + 1]) >= $F0 then
            Inc(Units, 2)
          else
            Inc(Units);
        end;
      end;
      Map[Length(U)] := Units;
      for I := 0 to Count - 1 do
      begin
        B := PInteger(@Bytes[I * 12])^;
        Len := PInteger(@Bytes[I * 12 + 4])^;
        Kind := PInteger(@Bytes[I * 12 + 8])^;
        if (B < 0) or (B >= Length(U)) or (Len <= 0) then
          Continue;
        Start := Map[B];
        Stop := Map[Min(B + Len, Length(U))];
        if Stop <= Start then
          Continue;
        SetLength(ASpans, Length(ASpans) + 1);
        ASpans[High(ASpans)].Start := Start;
        ASpans[High(ASpans)].Len := Stop - Start;
        ASpans[High(ASpans)].Kind := Kind;
      end;
      Result := Length(ASpans) > 0;
    end);
  SetI32Result(Results, NResults, 0);
end;

function HostSurfaceOpen(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Title, KeyExport, TickExport, ClosedExport: string;
  OnKey: TSurfaceKeyCallback;
  OnTick, OnClosed: TProc;
  Handle: Integer;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 8 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Title) or
     not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, KeyExport) or
     not ReadGuestUtf8(Caller, Vals^[4].Of_.I32, Vals^[5].Of_.I32, TickExport) or
     not ReadGuestUtf8(Caller, Vals^[6].Of_.I32, Vals^[7].Of_.I32, ClosedExport) then
    Exit;
  OnKey := nil;
  OnTick := nil;
  OnClosed := nil;
  if KeyExport <> '' then
    OnKey := function(const AKey: string): Boolean
      var
        Status: Int64;
        Err: string;
      begin
        Result := (Inst <> nil) and not Inst.Dead and
          Inst.CallStatusExport(KeyExport, AKey, Status, Err) and (Status = 1);
      end;
  if TickExport <> '' then
    OnTick := procedure
      var
        Err: string;
      begin
        if (Inst <> nil) and not Inst.Dead then
          Inst.InvokeVoidExport(TickExport, Err);
      end;
  if ClosedExport <> '' then
    OnClosed := procedure
      var
        Err: string;
      begin
        if (Inst <> nil) and not Inst.Dead then
          Inst.InvokeVoidExport(ClosedExport, Err);
      end;
  Handle := PluginSurfaceOpen(Inst.PluginId, Title, OnKey, OnTick, OnClosed);
  if Handle > 0 then
    SetI32Result(Results, NResults, Handle);
end;

function HostSurfaceSetFrame(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Pixels: TBytes;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 5 then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestBytes(Caller, Vals^[3].Of_.I32, Vals^[4].Of_.I32, Pixels) then
    Exit;
  if PluginSurfaceSetFrame(Vals^[0].Of_.I32, Vals^[1].Of_.I32, Vals^[2].Of_.I32, @Pixels[0],
    Length(Pixels)) then
    SetI32Result(Results, NResults, 0);
end;

function HostSurfaceSetInfo(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Title, Status: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 5 then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[1].Of_.I32, Vals^[2].Of_.I32, Title) or
     not ReadGuestUtf8(Caller, Vals^[3].Of_.I32, Vals^[4].Of_.I32, Status) then
    Exit;
  if PluginSurfaceSetInfo(Vals^[0].Of_.I32, Title, Status) then
    SetI32Result(Results, NResults, 0);
end;

function HostSurfaceSetTimer(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Vals := Pointer(Args);
  if PluginSurfaceSetTimer(Vals^[0].Of_.I32, Vals^[1].Of_.I32) then
    SetI32Result(Results, NResults, 0);
end;

function HostSurfaceClose(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 1 then
    Exit;
  Vals := Pointer(Args);
  if PluginSurfaceClose(Vals^[0].Of_.I32) then
    SetI32Result(Results, NResults, 0);
end;

function HostRegSettings(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 2 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  PluginSettings.RegisterConfigure(Inst.PluginId,
    procedure
    var
      Err: string;
    begin
      if (Inst = nil) or Inst.Dead then
        Exit;
      Inst.InvokeVoidExport(ExportName, Err);
    end);
  SetI32Result(Results, NResults, 0);
end;

function HostGetSetting(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Key, Value: string;
  Bytes: TBytes;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Key) or (Key = '') then
    Exit;
  if not PluginSettings.TryGetValue(Inst.PluginId, Key, Value) then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(Value);
  if WriteGuestBytes(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Bytes) then
    SetI32Result(Results, NResults, Length(Bytes))
  else
    SetI32Result(Results, NResults, -2);
end;

function HostSetSetting(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Key, Value: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Key) or (Key = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Value) then
    Exit;
  if PluginSettings.SetValue(Inst.PluginId, Key, Value) then
    SetI32Result(Results, NResults, 0);
end;

function HostRegKeyBinding(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Action, Combo: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Action) or (Action = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Combo) or (Combo = '') then
    Exit;
  if CommandRegistry.HasCommand(Action) then
    CommandRegistry.RegisterCommandBinding(Inst.PluginId, Action, Combo)
  else
    KeymapRegistry.RegisterBinding(Inst.PluginId, Action, Combo);
  SetI32Result(Results, NResults, 0);
end;

function HostRegPanelActivate(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  Scheme, ExportName: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, Scheme) or (Scheme = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, ExportName) or
     (ExportName = '') then
    Exit;
  PanelPluginRegistry.RegisterActivateHandler(Inst.PluginId, Scheme,
    function(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean
    var
      Status: Int64;
      Err: string;
    begin
      Result := False;
      if (Inst = nil) or Inst.Dead then
        Exit;
      Result := Inst.CallStatusExport(ExportName, ARowURI, Status, Err) and (Status = 1);
    end);
  SetI32Result(Results, NResults, 0);
end;

function HostSetCommandCaption(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  CommandId, Caption: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, CommandId) or
     (CommandId = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Caption) then
    Caption := '';
  CommandRegistry.SetCommandCaption(Inst.PluginId, CommandId, Caption);
  SetI32Result(Results, NResults, 0);
end;

function HostSetStatusSegment(Env: Pointer; Caller: PWasmtimeCaller;
  Args: PWasmtimeVal; NArgs: NativeUInt;
  Results: PWasmtimeVal; NResults: NativeUInt): PWasmTrap; cdecl;
var
  Inst: TWasmPluginInstance;
  SegmentId, Text: string;
  Vals: ^TValBuf;
begin
  Result := nil;
  SetI32Result(Results, NResults, -1);
  if NArgs < 4 then
    Exit;
  Inst := InstanceFromCaller(Caller);
  if Inst = nil then
    Exit;
  Vals := Pointer(Args);
  if not ReadGuestUtf8(Caller, Vals^[0].Of_.I32, Vals^[1].Of_.I32, SegmentId) or
     (SegmentId = '') then
    Exit;
  if not ReadGuestUtf8(Caller, Vals^[2].Of_.I32, Vals^[3].Of_.I32, Text) then
    Text := '';
  PluginChrome.SetStatusSegment(Inst.PluginId, SegmentId, Text);
  SetI32Result(Results, NResults, 0);
end;

function DefineHostImport(const AName: AnsiString; Ty: PWasmFunctype; ACb: Pointer;
  out AError: string): Boolean;
var
  Err: PWasmtimeError;
begin
  Err := Wasmtime.LinkerDefineFunc(GDefineLinker, PAnsiChar(cHostModule), Length(cHostModule),
    PAnsiChar(AName), Length(AName), Ty, ACb, nil, nil);
  if Err <> nil then
  begin
    AError := 'define ' + string(AName) + ': ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit(False);
  end;
  Result := True;
end;

/// <summary>Defines every mtn_host import on ALinker.</summary>
function DefineAllHostImports(ALinker: PWasmtimeLinker; out AError: string): Boolean;
var
  Ty0, Ty1, Ty2, Ty3, Ty4, Ty5, Ty6, Ty8, Ty9, Ty11, TySize, TyReadAt: PWasmFunctype;
begin
  Result := False;
  AError := '';
  GDefineLinker := ALinker;
  Ty0 := MakeFuncType([], [WASM_I32]);
  Ty1 := MakeFuncType([WASM_I32], [WASM_I32]);
  Ty2 := MakeFuncType([WASM_I32, WASM_I32], [WASM_I32]);
  Ty3 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty4 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty5 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty6 := MakeFuncType([WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty8 := MakeFuncType(
    [WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32], [WASM_I32]);
  Ty11 := MakeFuncType(
    [WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32,
     WASM_I32, WASM_I32], [WASM_I32]);
  Ty9 := MakeFuncType(
    [WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32, WASM_I32],
    [WASM_I32]);
  if (Ty11 = nil) or (Ty0 = nil) or (Ty1 = nil) or (Ty8 = nil) or (Ty2 = nil) or (Ty3 = nil) or (Ty4 = nil) or (Ty5 = nil) or (Ty6 = nil) or
     (Ty9 = nil) then
  begin
    if Ty6 <> nil then
      Wasmtime.FunctypeDelete(Ty6);
    if Ty11 <> nil then
      Wasmtime.FunctypeDelete(Ty11);
    if Ty0 <> nil then
      Wasmtime.FunctypeDelete(Ty0);
    if Ty1 <> nil then
      Wasmtime.FunctypeDelete(Ty1);
    if Ty8 <> nil then
      Wasmtime.FunctypeDelete(Ty8);
    if Ty2 <> nil then
      Wasmtime.FunctypeDelete(Ty2);
    if Ty3 <> nil then
      Wasmtime.FunctypeDelete(Ty3);
    if Ty4 <> nil then
      Wasmtime.FunctypeDelete(Ty4);
    if Ty5 <> nil then
      Wasmtime.FunctypeDelete(Ty5);
    if Ty9 <> nil then
      Wasmtime.FunctypeDelete(Ty9);
    AError := 'wasm_functype_new failed';
    Exit(False);
  end;
  TySize := MakeFuncType([WASM_I32], [WASM_I64]);
  TyReadAt := MakeFuncType([WASM_I32, WASM_I64, WASM_I32, WASM_I32], [WASM_I64]);
  try
    if (TySize = nil) or (TyReadAt = nil) then
    begin
      AError := 'wasm_functype_new failed';
      Exit(False);
    end;
    if not DefineHostImport(cVfsOpen, Ty4, @HostVfsOpen, AError) then
      Exit(False);
    if not DefineHostImport(cVfsSize, TySize, @HostVfsSize, AError) then
      Exit(False);
    if not DefineHostImport(cVfsReadAt, TyReadAt, @HostVfsReadAt, AError) then
      Exit(False);
    if not DefineHostImport(cVfsClose, Ty1, @HostVfsClose, AError) then
      Exit(False);
    if not DefineHostImport(cVfsCancel, Ty1, @HostVfsCancel, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceGetFullscreen, Ty1, @HostSurfaceGetFullscreen, AError) then
      Exit(False);
    if not DefineHostImport(cRegCommand, Ty4, @HostRegCommand, AError) then
      Exit(False);
    if not DefineHostImport(cRegCommandHook, Ty5, @HostRegCommandHook, AError) then
      Exit(False);
    if not DefineHostImport(cExecCommand, Ty2, @HostExecCommand, AError) then
      Exit(False);
    if not DefineHostImport(cRegDocProvider, Ty6, @HostRegDocProvider, AError) then
      Exit(False);
    if not DefineHostImport(cShowDialog, Ty4, @HostShowDialog, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceOpenEx, Ty11, @HostSurfaceOpenEx, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceSetFullscreen, Ty2, @HostSurfaceSetFullscreen, AError) then
      Exit(False);
    if not DefineHostImport(cPanelList, Ty3, @HostPanelList, AError) then
      Exit(False);
    if not DefineHostImport(cPanelSetCursor, Ty3, @HostPanelSetCursor, AError) then
      Exit(False);
    if not DefineHostImport(cPanelSelect, Ty4, @HostPanelSelect, AError) then
      Exit(False);
    if not DefineHostImport(cDocSetSelection, Ty4, @HostDocSetSelection, AError) then
      Exit(False);
    if not DefineHostImport(cDocLine, Ty3, @HostDocLine, AError) then
      Exit(False);
    if not DefineHostImport(cProgressSet, Ty5, @HostProgressSet, AError) then
      Exit(False);
    if not DefineHostImport(cProgressEnd, Ty2, @HostProgressEnd, AError) then
      Exit(False);
    if not DefineHostImport(cRegHighlighter, Ty4, @HostRegHighlighter, AError) then
      Exit(False);
    if not DefineHostImport(cVfsList, Ty4, @HostVfsList, AError) then
      Exit(False);
    if not DefineHostImport(cVfsExists, Ty4, @HostVfsExists, AError) then
      Exit(False);
    if not DefineHostImport(cVfsRead, Ty5, @HostVfsRead, AError) then
      Exit(False);
    if not DefineHostImport(cVfsResult, Ty3, @HostVfsResult, AError) then
      Exit(False);
    if not DefineHostImport(cHostInfo, Ty2, @HostHostInfo, AError) then
      Exit(False);
    if not DefineHostImport(cDocInfo, Ty2, @HostDocInfo, AError) then
      Exit(False);
    if not DefineHostImport(cDocGetText, Ty3, @HostDocGetText, AError) then
      Exit(False);
    if not DefineHostImport(cDocReplace, Ty3, @HostDocReplace, AError) then
      Exit(False);
    if not DefineHostImport(cDocSetCursor, Ty2, @HostDocSetCursor, AError) then
      Exit(False);
    if not DefineHostImport(cPanelInfo, Ty2, @HostPanelInfo, AError) then
      Exit(False);
    if not DefineHostImport(cPanelGoto, Ty3, @HostPanelGoto, AError) then
      Exit(False);
    if not DefineHostImport(cPanelRefresh, Ty0, @HostPanelRefresh, AError) then
      Exit(False);
    if not DefineHostImport(cClipboardGet, Ty2, @HostClipboardGet, AError) then
      Exit(False);
    if not DefineHostImport(cClipboardSet, Ty2, @HostClipboardSet, AError) then
      Exit(False);
    if not DefineHostImport(cShowMessage, Ty3, @HostShowMessage, AError) then
      Exit(False);
    if not DefineHostImport(cSubscribe, Ty4, @HostSubscribe, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceOpen, Ty8, @HostSurfaceOpen, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceSetFrame, Ty5, @HostSurfaceSetFrame, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceSetInfo, Ty5, @HostSurfaceSetInfo, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceSetTimer, Ty2, @HostSurfaceSetTimer, AError) then
      Exit(False);
    if not DefineHostImport(cSurfaceClose, Ty1, @HostSurfaceClose, AError) then
      Exit(False);
    if not DefineHostImport(cRegPanelActivate, Ty4, @HostRegPanelActivate, AError) then
      Exit(False);
    if not DefineHostImport(cRegKeyBinding, Ty4, @HostRegKeyBinding, AError) then
      Exit(False);
    if not DefineHostImport(cRegSettings, Ty2, @HostRegSettings, AError) then
      Exit(False);
    if not DefineHostImport(cGetSetting, Ty4, @HostGetSetting, AError) then
      Exit(False);
    if not DefineHostImport(cSetSetting, Ty4, @HostSetSetting, AError) then
      Exit(False);
    if not DefineHostImport(cSetCaption, Ty4, @HostSetCommandCaption, AError) then
      Exit(False);
    if not DefineHostImport(cSetStatusSegment, Ty4, @HostSetStatusSegment, AError) then
      Exit(False);
    if not DefineHostImport(cRegVfs, Ty3, @HostRegVfs, AError) then
      Exit(False);
    if not DefineHostImport(cRegPanel, Ty3, @HostRegPanel, AError) then
      Exit(False);
    if not DefineHostImport(cPublish, Ty4, @HostPublish, AError) then
      Exit(False);
    if not DefineHostImport(cRegMenu, Ty9, @HostRegMenu, AError) then
      Exit(False);
  finally
    if TySize <> nil then
      Wasmtime.FunctypeDelete(TySize);
    if TyReadAt <> nil then
      Wasmtime.FunctypeDelete(TyReadAt);
    Wasmtime.FunctypeDelete(Ty11);
    Wasmtime.FunctypeDelete(Ty0);
    Wasmtime.FunctypeDelete(Ty1);
    Wasmtime.FunctypeDelete(Ty8);
    Wasmtime.FunctypeDelete(Ty2);
    Wasmtime.FunctypeDelete(Ty3);
    Wasmtime.FunctypeDelete(Ty4);
    Wasmtime.FunctypeDelete(Ty5);
    Wasmtime.FunctypeDelete(Ty6);
    Wasmtime.FunctypeDelete(Ty9);
  end;
  Result := True;
end;

function EnsureWasmEngine(out AError: string): Boolean;
var
  Cfg: PWasmConfig;
  CacheErr: PWasmtimeError;
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
  // Parallel compilation spins up a thread pool as wide as the CPU (32
  // threads, ~9 MB on a 32-thread machine) that then idles for the whole
  // session -- pointless for a couple of small plugin modules.
  if Assigned(Wasmtime.ConfigParallelCompilationSet) then
    Wasmtime.ConfigParallelCompilationSet(Cfg, 0);
  // Compiled modules are kept on disk, so a large module (a Go build, for
  // one) is compiled on the first start only and loaded from the cache after.
  // A failure to set the cache up only costs the speed-up.
  if Assigned(Wasmtime.ConfigCacheConfigLoad) then
  begin
    CacheErr := Wasmtime.ConfigCacheConfigLoad(Cfg, nil);
    if CacheErr <> nil then
      Wasmtime.ErrorDelete(CacheErr);
  end;
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
  Result := DefineAllHostImports(GLinker, AError);
end;

/// <summary>The linker of plugins that ask for WASI (plugin.json "wasi": true):
/// the host imports plus an empty WASI preview1. A module cannot reach files,
/// environment, arguments or the network through it: the WASI context of each
/// store is created without any of them.</summary>
function EnsureWasiLinker(out AError: string): Boolean;
var
  Err: PWasmtimeError;
begin
  if not EnsureWasmEngine(AError) then
    Exit(False);
  if GWasiLinker <> nil then
    Exit(True);
  if not Assigned(Wasmtime.WasiConfigNew) or not Assigned(Wasmtime.ContextSetWasi) or
     not Assigned(Wasmtime.LinkerDefineWasi) then
  begin
    AError := 'this wasmtime.dll has no WASI support';
    Exit(False);
  end;
  GWasiLinker := Wasmtime.LinkerNew(GEngine);
  if GWasiLinker = nil then
  begin
    AError := 'wasmtime_linker_new failed';
    Exit(False);
  end;
  if not DefineAllHostImports(GWasiLinker, AError) then
    Exit(False);
  Err := Wasmtime.LinkerDefineWasi(GWasiLinker);
  if Err <> nil then
  begin
    AError := 'define wasi: ' + WasmtimeErrorMessage(Err);
    WasmtimeClearError(Err);
    Exit(False);
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
  FVfsResults := TDictionary<Integer, TBytes>.Create;
end;

destructor TWasmPluginInstance.Destroy;
begin
  ShutdownPlugin;
  FVfsResults.Free;
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
  Func: TWasmtimeFunc;
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
    // A guest whose runtime uses all of its linear memory (Go) exports
    // mtn_scratch_ptr: the address of a 32 KiB buffer it keeps for the host.
    if GetExportFunc('mtn_scratch_ptr', Func) then
    begin
      if FScratchBase = 0 then
        if not CallNoArgsI32('mtn_scratch_ptr', FScratchBase, AError) then
          Exit;
      if (FScratchBase <= 0) or (NativeUInt(FScratchBase) + NativeUInt(cScratchTail) > Size) then
      begin
        AError := 'mtn_scratch_ptr is outside guest memory';
        Exit;
      end;
      FOutOff := FScratchBase;
      FOutCap := cScratchOutBytes;
      FUriOff := FScratchBase + cScratchOutBytes;
      FUriSlot := cScratchUriSlot;
      Result := True;
      Exit;
    end;
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

  if FWasi and not EnsureWasiLinker(AError) then
    Exit;
  FStore := Wasmtime.StoreNew(GEngine, Self, nil);
  if FStore = nil then
  begin
    AError := 'wasmtime_store_new failed';
    Exit;
  end;
  FContext := Wasmtime.StoreContext(FStore);
  if FWasi then
  begin
    // A Go or Rust runtime needs room: tens of MiB of memory and a table with
    // thousands of entries; the module count stays at one.
    Wasmtime.StoreLimiter(FStore, 128 * 1024 * 1024, 200000, 1, 1, 1);
    // Default WASI config: no preopened directories, no environment, no
    // arguments, no inherited stdio.
    Err := Wasmtime.ContextSetWasi(FContext, Wasmtime.WasiConfigNew());
    if Err <> nil then
    begin
      AError := 'set wasi: ' + WasmtimeErrorMessage(Err);
      WasmtimeClearError(Err);
      ReleaseEngineObjects;
      Exit;
    end;
  end
  else
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
  if FWasi then
    Err := Wasmtime.LinkerInstantiate(GWasiLinker, FContext, FModule, @FInstance, @Trap)
  else
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
  // A reactor module (Go, Rust with a C ABI) wants its runtime started once
  // before any other export runs.
  if FWasi and not CallNoArgsVoid('_initialize', AError) then
  begin
    if Pos('export missing', AError) = 0 then
    begin
      ReleaseEngineObjects;
      Exit;
    end;
    AError := '';
  end;
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
    if not IsSupportedPluginAbi(Abi) then
    begin
      AError := Format('Plugin ABI version %d is outside host range %d..%d', [Abi, cPluginMinAbiVersion, cPluginAbiVersion]);
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

function TWasmPluginInstance.CallIntsExport(const AExport: string; const AArgs: array of Integer;
  out AStatus: Int64; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  I: Integer;
begin
  Result := False;
  AStatus := 0;
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if (Length(AArgs) > 12) or not GetExportFunc(AExport, Func) then
    begin
      AError := AExport + ' export missing';
      Exit;
    end;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    for I := 0 to High(AArgs) do
    begin
      Args[I].Kind := WASMTIME_I32;
      Args[I].Of_.I32 := AArgs[I];
    end;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], Length(AArgs), @Rets[0], 1, @Trap);
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

function TWasmPluginInstance.CallIntsVoidExport(const AExport: string;
  const AArgs: array of Integer; out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  I: Integer;
begin
  Result := False;
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if (Length(AArgs) > 12) or not GetExportFunc(AExport, Func) then
    begin
      AError := AExport + ' export missing';
      Exit;
    end;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    for I := 0 to High(AArgs) do
    begin
      Args[I].Kind := WASMTIME_I32;
      Args[I].Of_.I32 := AArgs[I];
    end;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], Length(AArgs), nil, 0, @Trap);
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
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.ReserveVfsHandle: Integer;
begin
  Inc(FVfsNext);
  if FVfsNext <= 0 then
    FVfsNext := 1;
  Result := FVfsNext;
end;

procedure TWasmPluginInstance.StoreVfsResult(AHandle: Integer; const AData: TBytes);
begin
  FVfsResults.AddOrSetValue(AHandle, AData);
end;

function TWasmPluginInstance.TakeVfsResult(AHandle, ACap: Integer; out AData: TBytes): Integer;
begin
  AData := nil;
  if not FVfsResults.TryGetValue(AHandle, AData) then
    Exit(-1);
  Result := Length(AData);
  if Result <= ACap then
    FVfsResults.Remove(AHandle);
end;

function TWasmPluginInstance.CallHighlightExport(const AExport, ALine: string;
  out ASpans: TBytes; out ACount: Integer; out AError: string): Boolean;
const
  cSpanBytes = 12;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Rets: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  LinePtr, LineLen, Cap: Integer;
begin
  Result := False;
  ACount := 0;
  SetLength(ASpans, 0);
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
      AError := AExport + ' export missing';
      Exit;
    end;
    if not WriteUriScratch(ALine, LinePtr, LineLen, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    Cap := FOutCap div cSpanBytes;
    if Cap > 256 then
      Cap := 256;
    FillChar(Args, SizeOf(Args), 0);
    FillChar(Rets, SizeOf(Rets), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := LinePtr;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := LineLen;
    Args[2].Kind := WASMTIME_I32;
    Args[2].Of_.I32 := FOutOff;
    Args[3].Kind := WASMTIME_I32;
    Args[3].Of_.I32 := Cap;
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
    ACount := Integer(WasmResultI64(Rets[0]));
    if ACount > Cap then
      ACount := Cap;
    if ACount <= 0 then
      Exit(True);
    Result := ReadScratchOut(Int64(ACount) * cSpanBytes, ASpans, AError);
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

function TWasmPluginInstance.InvokeTwoStringExport(const AName, A, B: string;
  out AError: string): Boolean;
var
  Func: TWasmtimeFunc;
  Args: TValBuf;
  Err: PWasmtimeError;
  Trap: PWasmTrap;
  PtrA, LenA, PtrB, LenB: Integer;
begin
  Result := False;
  AError := '';
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit;
    end;
    if not GetExportFunc(AName, Func) then
    begin
      AError := AName + ' export missing';
      Exit;
    end;
    if not WriteTwoUris(A, B, PtrA, LenA, PtrB, LenB, AError) then
      Exit;
    if not Refuel(AError) then
      Exit;
    FillChar(Args, SizeOf(Args), 0);
    Args[0].Kind := WASMTIME_I32;
    Args[0].Of_.I32 := PtrA;
    Args[1].Kind := WASMTIME_I32;
    Args[1].Of_.I32 := LenA;
    Args[2].Kind := WASMTIME_I32;
    Args[2].Of_.I32 := PtrB;
    Args[3].Kind := WASMTIME_I32;
    Args[3].Of_.I32 := LenB;
    Trap := nil;
    Err := Wasmtime.FuncCall(FContext, @Func, @Args[0], 4, nil, 0, @Trap);
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
  finally
    FLock.Release;
  end;
end;

function TWasmPluginInstance.InvokeI32Export(const AName: string; out AValue: Integer;
  out AError: string): Boolean;
begin
  AError := '';
  AValue := -1;
  FLock.Acquire;
  try
    if FDead or not FHasInstance then
    begin
      AError := 'WASM instance is not live';
      Exit(False);
    end;
    Result := CallNoArgsI32(AName, AValue, AError);
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
