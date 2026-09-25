unit uPluginHostAbi;

{ Cross-Platform x64 C-Compatible Host ABI Layer for MTN2 Plugins.
  All exported functions use cdecl calling convention, 64-bit data structures,
  and UTF-8 string encoding (PAnsiChar) for binary compatibility on Win64, Linux x64, macOS x64.

  Plugin-side contract (exported by the plugin DLL, see uPluginLoader.pas):
    function mtn_plugin_get_abi_version: Int64; cdecl;
    function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;   // 0 = success
    procedure mtn_plugin_shutdown; cdecl;
    function mtn_plugin_set_secret(AKeyUtf8, AValueUtf8: PAnsiChar): Int64; cdecl;
      // optional: archive password. Missing export is not a load failure.
      // AValueUtf8 = nil clears; empty string is a valid password.

  Host-side contract (this unit): a THostApiTable of cdecl function pointers
  is handed to the plugin's mtn_plugin_init. The pointer remains valid until
  mtn_plugin_shutdown (uPluginLoader keeps a heap copy per plugin). Plugins
  that stash AHostApi must not use it after shutdown; copying the record by
  value is also valid because the function pointers themselves are stable.
  The plugin calls back into the host through it — publish/invalidate for
  cross-cutting notifications, Register* to extend VFS/panels/keymap/menu/
  dialogs. Every host-side function wraps its Pascal body in try/except so
  an exception raised while servicing a plugin call can never unwind across
  the cdecl boundary into the plugin (which would corrupt the plugin's C
  runtime stack). }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uMessageBus;

{$ALIGN 8} // 64-bit 8-byte structure alignment

const
  /// <summary>Bumped whenever THostApiTable's layout changes. Plugins must
  /// check this via mtn_plugin_get_abi_version before trusting the table
  /// (see uPluginLoader.TPluginLoader.LoadPluginsFrom).</summary>
  cPluginAbiVersion: Int64 = 1;

type
  /// <summary>C-compatible VFS callbacks table (cdecl calling convention).
  /// Mirrors IVirtualFileSystem (uVfsTypes.pas) one-to-one, but synchronous:
  /// the host-side adapter (uVfsCdeclAdapter.TCdeclVfsBackend) runs each call
  /// on a background thread and turns it back into the async IVirtualFileSystem
  /// shape expected by the rest of the app.
  ///
  /// Buffer-fill functions (ListDirectory/ReadText/ReadBytes) write into a
  /// caller-supplied buffer of ABufSize bytes. On success (result = 0), the
  /// plugin MUST set ANegotiatedSize to the number of bytes actually written.
  /// If the encoded result doesn't fit, the plugin must not write partial
  /// data, set ANegotiatedSize to the required size, and return
  /// verNeedsBiggerBuffer (see TVfsCdeclResult). The host adapter currently
  /// treats that as a hard failure (no retry) — plugins should keep
  /// listings/reads within a practical single-shot size
  /// (uVfsCdeclAdapter.cCdeclVfsBufferSize, 4 MB by default).
  ///
  /// ListDirectory's ABuf receives a UTF-8 JSON array; see
  /// uVfsCdeclAdapter.EntriesFromJson for the exact per-entry field names.</summary>
  TVfsCallbacksCdecl = record
    ListDirectory: function(AURI: PAnsiChar; AUserData: Pointer;
      ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    Delete: function(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer): Int64; cdecl;
    CreateDirectory: function(AURI: PAnsiChar; AUserData: Pointer): Int64; cdecl;
    CopyItem: function(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
      AUserData: Pointer): Int64; cdecl;
    MoveItem: function(AFromURI, AToURI: PAnsiChar; AOverwrite: Int64;
      AUserData: Pointer): Int64; cdecl;
    ReadText: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    ReadBytes: function(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer;
      ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
    WriteText: function(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer): Int64; cdecl;
    Exists: function(AURI: PAnsiChar; AUserData: Pointer; out AIsDirectory: Int64): Int64; cdecl;
    GetFreeSpace: function(ARootURI: PAnsiChar; AUserData: Pointer;
      out AFree, ATotal: Int64): Int64; cdecl;
  end;
  PVfsCallbacksCdecl = ^TVfsCallbacksCdecl;

  /// <summary>Result codes returned by TVfsCallbacksCdecl methods (0 = ok).</summary>
  TVfsCdeclResult = (
    verOk = 0,
    verNotFound = 1,
    verAccessDenied = 2,
    verAlreadyExists = 3,
    verNotSupported = 4,
    verIOError = 5,
    verInvalidURI = 6,
    verNeedsBiggerBuffer = 7
  );

  { C-ABI Host Function Pointers — handed to the plugin at init time. }
  THostPublishFn = function(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
  THostInvalidateFn = function(AWindowId: Int64): Int64; cdecl;
  THostRegisterVfsSchemeFn = function(APluginId, AScheme: PAnsiChar;
    ACallbacks: PVfsCallbacksCdecl; AUserData: Pointer; APriority: Int64): Int64; cdecl;
  THostRegisterPanelPluginFn = function(APluginId, AScheme: PAnsiChar;
    APriority: Int64): Int64; cdecl;
  THostRegisterKeyBindingFn = function(APluginId, AAction, AKeyCombo: PAnsiChar): Int64; cdecl;
  THostRegisterMenuItemCallback = procedure(AUserData: Pointer); cdecl;
  THostRegisterMenuItemFn = function(APluginId, AParentPath, AItemId, ACaption: PAnsiChar;
    AOnClick: THostRegisterMenuItemCallback; AUserData: Pointer; APriority: Int64): Int64; cdecl;

  /// <summary>Table of host-exported functions passed to mtn_plugin_init.
  /// Field order/types are the ABI — see cPluginAbiVersion.</summary>
  THostApiTable = record
    AbiVersion: Int64;
    HostPublish: THostPublishFn;
    HostInvalidate: THostInvalidateFn;
    RegisterVfsScheme: THostRegisterVfsSchemeFn;
    RegisterPanelPlugin: THostRegisterPanelPluginFn;
    RegisterKeyBinding: THostRegisterKeyBindingFn;
    RegisterMenuItem: THostRegisterMenuItemFn;
  end;
  PHostApiTable = ^THostApiTable;

  /// <summary>Plugin-side entry points a DLL must export (see uPluginLoader.pas).</summary>
  TPluginGetAbiVersionFn = function: Int64; cdecl;
  TPluginInitFn = function(AHostApi: PHostApiTable): Int64; cdecl;
  TPluginShutdownProc = procedure; cdecl;
  TPluginSetSecretFn = function(AKeyUtf8, AValueUtf8: PAnsiChar): Int64; cdecl;

/// <summary>Wraps a JSON payload as a TObject so it survives the cdecl
/// boundary and reaches MessageBus subscribers (uMessageBus.TMessageListener
/// takes a TObject payload). Subscribers should free-cast to TPluginPayload.</summary>
type
  TPluginPayload = class(TObject)
  public
    PluginId: string;
    Json: string;
    constructor Create(const APluginId, AJson: string);
  end;

function mtn_host_publish(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
function mtn_host_invalidate(AWindowId: Int64): Int64; cdecl;

/// <summary>Registers a window (by an opaque host-assigned Int64 id) so a
/// plugin can later request a repaint via mtn_host_invalidate. Returns the
/// assigned id. Called from host code (e.g. uMainForm), not by plugins.</summary>
function RegisterInvalidatableWindow(AInvalidateProc: TProc): Int64;
procedure UnregisterInvalidatableWindow(AWindowId: Int64);

/// <summary>Fills in the fixed fields (AbiVersion + Host*) of a THostApiTable.
/// uPluginLoader.pas adds the Register* function pointers.</summary>
procedure InitHostApiTableCore(var ATable: THostApiTable);

implementation

var
  GWindows: TDictionary<Int64, TProc>;
  GNextWindowId: Int64 = 1;

constructor TPluginPayload.Create(const APluginId, AJson: string);
begin
  inherited Create;
  PluginId := APluginId;
  Json := AJson;
end;

function RegisterInvalidatableWindow(AInvalidateProc: TProc): Int64;
begin
  Result := TInterlocked.Increment(GNextWindowId);
  GWindows.AddOrSetValue(Result, AInvalidateProc);
end;

procedure UnregisterInvalidatableWindow(AWindowId: Int64);
begin
  GWindows.Remove(AWindowId);
end;

function mtn_host_publish(APluginId, ATopicUtf8, APayloadJsonUtf8: PAnsiChar): Int64; cdecl;
var
  LTopic, LPluginId, LPayloadJson: string;
  LPayload: TPluginPayload;
begin
  try
    if ATopicUtf8 = nil then
      Exit(-1);
    LTopic := UTF8ToString(ATopicUtf8);
    if APluginId <> nil then
      LPluginId := UTF8ToString(APluginId)
    else
      LPluginId := '';
    if APayloadJsonUtf8 <> nil then
      LPayloadJson := UTF8ToString(APayloadJsonUtf8)
    else
      LPayloadJson := '';

    LPayload := TPluginPayload.Create(LPluginId, LPayloadJson);
    try
      MessageBus.Publish(LTopic, LPayload);
    finally
      LPayload.Free;
    end;
    Result := 0;
  except
    Result := -1;
  end;
end;

function mtn_host_invalidate(AWindowId: Int64): Int64; cdecl;
var
  Proc: TProc;
begin
  try
    if not Assigned(GWindows) or not GWindows.TryGetValue(AWindowId, Proc) then
      Exit(-1);
    if Assigned(Proc) then
      TThread.Queue(nil, procedure begin Proc(); end);
    Result := 0;
  except
    Result := -1;
  end;
end;

procedure InitHostApiTableCore(var ATable: THostApiTable);
begin
  FillChar(ATable, SizeOf(ATable), 0);
  ATable.AbiVersion := cPluginAbiVersion;
  ATable.HostPublish := @mtn_host_publish;
  ATable.HostInvalidate := @mtn_host_invalidate;
end;

initialization
  GWindows := TDictionary<Int64, TProc>.Create;

finalization
  FreeAndNil(GWindows);

end.
