unit uPluginLoader;

{ Plugin loader. Layout: each plugin lives in its own subdirectory of the
  plugins root (<ExeDir>\plugins\<plugin-id>\ — the plugin-id used for
  registration and for uDialogResources.TryLoadPluginDialogJson's
  plugins\<id>\dialogs\ lookup is the subdirectory name). Bare files
  directly under the plugins root are NOT loaded.

  Native DLLs: every *.dll inside a plugin subdirectory (no recursion) is
  probed for mtn_plugin_* exports (uPluginHostAbi.pas). DLLs that do not
  export the plugin ABI (helper libraries such as 7z.dll sitting next to
  the plugin) are skipped without failing the load. Matching DLLs have
  their ABI version checked, and mtn_plugin_init is called with a
  THostApiTable whose Register* functions delegate into the app's existing
  registries (uVfsRegistry.GlobalVfsRegistry,
  uPanelPluginRegistry.PanelPluginRegistry, uKeymapRegistry.KeymapRegistry,
  uMenuRegistry.MenuRegistry).

  WASM (stage 30): every *.wat / *.wasm in the same subdirectory is loaded
  through uWasmPluginHost (optional wasmtime.dll). Guest code talks JSON /
  UTF-8 copies in linear memory — not THostApiTable pointers. Missing
  wasmtime.dll skips WASM modules without failing the host (same idea as
  a missing 7z.dll). A trap inside the guest is logged and isolated; it
  does not unwind into the Delphi process.

  Stability note: LoadLibrary/GetProcAddress failures and ABI mismatches are
  handled without crashing the host (skip + log). Once mtn_plugin_init is
  called, a genuinely misbehaving *native* plugin (e.g. an access violation
  inside its own code) can still crash the process — Win32/Delphi structured
  exception handling cannot fully sandbox a loaded native DLL. WASM guests
  are the in-process sandbox for untrusted native-contract plugins.

  Lazy load: CatalogPlugins only reads plugin.json and remembers module
  paths. The DLL/WASM is loaded the first time its scheme or archive
  extension is needed (EnsureScheme / EnsureArchiveExtension), or when the
  user opens the top menu or the plugin list (EnsureAll). LoadPluginsFrom
  stays eager for tests and tools that want every plugin immediately. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  Winapi.Windows,
  uVfsTypes, uPluginHostAbi, uVfsCdeclAdapter, uVfsRegistry, uPanelPluginRegistry,
  uKeymapRegistry, uMenuRegistry, uPluginManifest, uWasmPluginHost;

type
  TPluginLoadKind = (lpkNative, lpkWasm);

  TPluginLoadResult = (
    plrLoaded,
    plrLoadLibraryFailed,
    plrMissingExports,
    plrAbiMismatch,
    plrInitFailed,
    plrSkippedHelperDll,
    plrSkippedNoRuntime
  );

  TPluginLoadLogEvent = reference to procedure(const AFileName: string;
    AResult: TPluginLoadResult; const AMessage: string);

  TPluginLoader = class
  private
    type
      TLoadedPlugin = record
        PluginId: string;
        Kind: TPluginLoadKind;
        ModuleHandle: HMODULE;
        WasmInst: TWasmPluginInstance;
        Shutdown: TPluginShutdownProc;
        SetSecret: TPluginSetSecretFn;
        /// <summary>Heap copy of the table passed to mtn_plugin_init. The
        /// plugin may stash this pointer until mtn_plugin_shutdown.</summary>
        HostApi: PHostApiTable;
      end;
    type
      TCatalogedPlugin = record
        PluginId: string;
        Schemes: TArray<string>;
        ArchiveExtensions: TArray<string>;
        Files: TArray<string>;
        Attempted: Boolean;
      end;
    var
      FLoaded: TList<TLoadedPlugin>;
      FCatalog: TList<TCatalogedPlugin>;
      FOnLog: TPluginLoadLogEvent;
      FEnsuring: Boolean;
      FAllEnsured: Boolean;
    function BuildHostApiTable: THostApiTable;
    function TryLoadOne(const AFileName, APluginId: string): Boolean;
    function TryLoadOneWasm(const AFileName, APluginId: string): Boolean;
    function PluginIsLoaded(const APluginId: string): Boolean;
    function EnsureIndex(AIndex: Integer): Boolean;
    procedure Log(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Loads every plugin found under ADir\<plugin-id>\*.dll — one
    /// subdirectory per plugin, plugin-id = subdirectory name (see unit
    /// comment). A bare *.dll/*.wat/*.wasm directly under ADir is ignored.
    /// Missing ADir is not an error (no plugins to load). Failures on
    /// individual modules are logged (see OnLog) and skipped — one bad
    /// plugin never stops the others or the host.</summary>
    procedure LoadPluginsFrom(const ADir: string);
    /// <summary>Scans ADir the same way as LoadPluginsFrom but does not
    /// call LoadLibrary. Schemes and archive extensions come from
    /// plugin.json so a later Ensure* can load just that plugin.</summary>
    procedure CatalogPlugins(const ADir: string);
    /// <summary>Loads the catalogued plugin that declared AScheme, if it
    /// is not loaded yet. False when nothing in the catalog owns it, or
    /// a load was already attempted.</summary>
    function EnsureScheme(const AScheme: string): Boolean;
    /// <summary>Loads the catalogued plugin whose plugin.json lists this
    /// file's extension in archiveExtensions.</summary>
    function EnsureArchiveExtension(const AFileName: string): Boolean;
    /// <summary>Loads every catalogued plugin that has not been attempted
    /// yet. Used when the UI needs registrations that are not in
    /// plugin.json (menu items, key rebinds).</summary>
    procedure EnsureAll;
    function CatalogPluginIds: TArray<string>;
    /// <summary>Calls mtn_plugin_shutdown then FreeLibrary for every loaded
    /// plugin, in reverse load order. Safe to call multiple times.</summary>
    procedure UnloadAll;
    /// <summary>Ids (plugin subdirectory name) of every currently loaded
    /// plugin, in load order.</summary>
    function LoadedPluginIds: TArray<string>;
    /// <summary>Calls optional mtn_plugin_set_secret. Empty AValue is a valid
    /// secret. Returns False if the plugin is not loaded or has no export.</summary>
    function TrySetSecret(const APluginId, AKey, AValue: string): Boolean;
    /// <summary>Clears a previously set secret (AValueUtf8 = nil).</summary>
    function TryClearSecret(const APluginId, AKey: string): Boolean;
    property OnLog: TPluginLoadLogEvent read FOnLog write FOnLog;
  end;

function PluginLoader: TPluginLoader;

implementation

{ Register* thunks — each becomes a THostApiTable function pointer.
  AUserData for RegisterVfsScheme carries the plugin's own VFS callback
  AUserData through unchanged; the plugin id is passed explicitly per call
  since a single cdecl function pointer is shared by every loaded plugin. }

{ A manifest's archiveExtensions (mtn.7z's plugin.json etc.) become
  akSevenZip entries in GlobalVfsRegistry — the only pluggable archive
  kind today (see TArchiveExtensionKind in uVfsRegistry.pas); the built-in
  zip/jar/apk entries are registered once in GlobalVfsRegistry itself, not
  here. Tagging with APluginId means UnloadAll's UnregisterPlugin call
  drops these along with the plugin's VFS scheme. }
procedure RegisterManifestArchiveExtensions(const APluginId: string;
  const AManifest: TPluginManifest);
var
  Ext: string;
begin
  for Ext in AManifest.ArchiveExtensions do
    GlobalVfsRegistry.RegisterArchiveExtension(APluginId, Ext, akSevenZip);
end;

function ThunkRegisterVfsScheme(APluginId, AScheme: PAnsiChar;
  ACallbacks: PVfsCallbacksCdecl; AUserData: Pointer; APriority: Int64): Int64; cdecl;
var
  Backend: IVirtualFileSystem;
begin
  try
    if (APluginId = nil) or (AScheme = nil) or (ACallbacks = nil) then
      Exit(-1);
    Backend := TCdeclVfsBackend.Create(ACallbacks^, AUserData);
    GlobalVfsRegistry.RegisterPluginScheme(UTF8ToString(APluginId),
      UTF8ToString(AScheme), Backend, Integer(APriority));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterPanelPlugin(APluginId, AScheme: PAnsiChar; APriority: Int64): Int64; cdecl;
begin
  try
    if (APluginId = nil) or (AScheme = nil) then
      Exit(-1);
    PanelPluginRegistry.RegisterPlugin(UTF8ToString(APluginId), UTF8ToString(AScheme), APriority);
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterKeyBinding(APluginId, AAction, AKeyCombo: PAnsiChar): Int64; cdecl;
begin
  try
    if (APluginId = nil) or (AAction = nil) or (AKeyCombo = nil) then
      Exit(-1);
    KeymapRegistry.RegisterBinding(UTF8ToString(APluginId), UTF8ToString(AAction),
      UTF8ToString(AKeyCombo));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterMenuItem(APluginId, AParentPath, AItemId, ACaption: PAnsiChar;
  AOnClick: THostRegisterMenuItemCallback; AUserData: Pointer; APriority: Int64): Int64; cdecl;
var
  PluginId, ItemId: string;
  Callback: THostRegisterMenuItemCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or (AParentPath = nil) or (AItemId = nil) or
       (ACaption = nil) or not Assigned(AOnClick) then
      Exit(-1);
    PluginId := UTF8ToString(APluginId);
    ItemId := UTF8ToString(AItemId);
    Callback := AOnClick;
    UserData := AUserData;
    MenuRegistry.RegisterMenuItem(PluginId, UTF8ToString(AParentPath), ItemId,
      UTF8ToString(ACaption),
      procedure
      begin
        // Re-enters the plugin DLL on the main thread, same as a direct
        // menu click would for a built-in TTopMenuAction.
        Callback(UserData);
      end, Integer(APriority));
    Result := 0;
  except
    Result := -1;
  end;
end;

function CollectPluginModules(const APluginDir: string): TArray<string>;
var
  DirFiles: TArray<string>;
  FileName: string;
  Dlls, Wats, Wasms: TList<string>;
  I: Integer;
begin
  Dlls := TList<string>.Create;
  Wats := TList<string>.Create;
  Wasms := TList<string>.Create;
  try
    DirFiles := TDirectory.GetFiles(APluginDir, '*', TSearchOption.soTopDirectoryOnly);
    for FileName in DirFiles do
      if SameText(TPath.GetExtension(FileName), '.dll') then
        Dlls.Add(FileName)
      else if SameText(TPath.GetExtension(FileName), '.wat') then
        Wats.Add(FileName)
      else if SameText(TPath.GetExtension(FileName), '.wasm') then
        Wasms.Add(FileName);
    SetLength(Result, Dlls.Count + Wats.Count + Wasms.Count);
    I := 0;
    for FileName in Dlls do
    begin
      Result[I] := FileName;
      Inc(I);
    end;
    for FileName in Wats do
    begin
      Result[I] := FileName;
      Inc(I);
    end;
    for FileName in Wasms do
    begin
      Result[I] := FileName;
      Inc(I);
    end;
  finally
    Dlls.Free;
    Wats.Free;
    Wasms.Free;
  end;
end;

function ExtensionKey(const AFileName: string): string;
begin
  Result := LowerCase(TPath.GetExtension(AFileName));
  if (Result <> '') and (Result[1] = '.') then
    Result := Copy(Result, 2, MaxInt);
end;

function ListHasExt(const AExts: TArray<string>; const AKey: string): Boolean;
var
  One, Key: string;
begin
  Result := False;
  if AKey = '' then
    Exit;
  for One in AExts do
  begin
    Key := LowerCase(Trim(One));
    if (Key <> '') and (Key[1] = '.') then
      Key := Copy(Key, 2, MaxInt);
    if Key = AKey then
      Exit(True);
  end;
end;

constructor TPluginLoader.Create;
begin
  inherited Create;
  FLoaded := TList<TLoadedPlugin>.Create;
  FCatalog := TList<TCatalogedPlugin>.Create;
end;

destructor TPluginLoader.Destroy;
begin
  UnloadAll;
  FCatalog.Free;
  FLoaded.Free;
  inherited Destroy;
end;

procedure TPluginLoader.Log(const AFileName: string; AResult: TPluginLoadResult;
  const AMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AFileName, AResult, AMessage);
end;

function TPluginLoader.BuildHostApiTable: THostApiTable;
begin
  InitHostApiTableCore(Result);
  Result.RegisterVfsScheme := @ThunkRegisterVfsScheme;
  Result.RegisterPanelPlugin := @ThunkRegisterPanelPlugin;
  Result.RegisterKeyBinding := @ThunkRegisterKeyBinding;
  Result.RegisterMenuItem := @ThunkRegisterMenuItem;
end;

function TPluginLoader.TryLoadOne(const AFileName, APluginId: string): Boolean;
var
  Module: HMODULE;
  GetAbiVersion: TPluginGetAbiVersionFn;
  InitFn: TPluginInitFn;
  ShutdownFn: TPluginShutdownProc;
  AbiVersion: Int64;
  HostApi: PHostApiTable;
  InitResult: Int64;
  Loaded: TLoadedPlugin;
  Manifest: TPluginManifest;
begin
  Result := False;

  if TryReadPluginManifest(ExtractFileDir(AFileName), Manifest) then
  begin
    if Manifest.HasAbi and (Manifest.AbiVersion <> cPluginAbiVersion) then
    begin
      Log(AFileName, plrAbiMismatch,
        Format('plugin.json abi %d != host %d', [Manifest.AbiVersion, cPluginAbiVersion]));
      Exit;
    end;
  end;

  Module := LoadLibrary(PChar(AFileName));
  if Module = 0 then
  begin
    Log(AFileName, plrLoadLibraryFailed,
      Format('LoadLibrary failed (GetLastError=%d)', [GetLastError]));
    Exit;
  end;

  GetAbiVersion := TPluginGetAbiVersionFn(GetProcAddress(Module, 'mtn_plugin_get_abi_version'));
  InitFn := TPluginInitFn(GetProcAddress(Module, 'mtn_plugin_init'));
  ShutdownFn := TPluginShutdownProc(GetProcAddress(Module, 'mtn_plugin_shutdown'));
  if not Assigned(GetAbiVersion) or not Assigned(InitFn) or not Assigned(ShutdownFn) then
  begin
    Log(AFileName, plrSkippedHelperDll,
      'No mtn_plugin_* exports (helper DLL)');
    FreeLibrary(Module);
    Exit;
  end;

  try
    AbiVersion := GetAbiVersion();
  except
    on E: Exception do
    begin
      Log(AFileName, plrAbiMismatch, 'mtn_plugin_get_abi_version raised: ' + E.Message);
      FreeLibrary(Module);
      Exit;
    end;
  end;

  if AbiVersion <> cPluginAbiVersion then
  begin
    Log(AFileName, plrAbiMismatch,
      Format('Plugin ABI version %d != host %d', [AbiVersion, cPluginAbiVersion]));
    FreeLibrary(Module);
    Exit;
  end;

  New(HostApi);
  HostApi^ := BuildHostApiTable;
  try
    InitResult := InitFn(HostApi);
  except
    on E: Exception do
    begin
      Dispose(HostApi);
      Log(AFileName, plrInitFailed, 'mtn_plugin_init raised: ' + E.Message);
      FreeLibrary(Module);
      Exit;
    end;
  end;

  if InitResult <> 0 then
  begin
    Dispose(HostApi);
    Log(AFileName, plrInitFailed, Format('mtn_plugin_init returned %d', [InitResult]));
    FreeLibrary(Module);
    Exit;
  end;

  Loaded.PluginId := APluginId;
  Loaded.Kind := lpkNative;
  Loaded.ModuleHandle := Module;
  Loaded.WasmInst := nil;
  Loaded.Shutdown := ShutdownFn;
  Loaded.SetSecret := TPluginSetSecretFn(GetProcAddress(Module, 'mtn_plugin_set_secret'));
  Loaded.HostApi := HostApi;
  FLoaded.Add(Loaded);
  RegisterManifestArchiveExtensions(APluginId, Manifest);
  Log(AFileName, plrLoaded, 'OK');
  Result := True;
end;

function TPluginLoader.TryLoadOneWasm(const AFileName, APluginId: string): Boolean;
var
  Inst: TWasmPluginInstance;
  EngineErr, Err: string;
  Loaded: TLoadedPlugin;
  Manifest: TPluginManifest;
begin
  Result := False;

  if TryReadPluginManifest(ExtractFileDir(AFileName), Manifest) then
  begin
    if Manifest.HasAbi and (Manifest.AbiVersion <> cPluginAbiVersion) then
    begin
      Log(AFileName, plrAbiMismatch,
        Format('plugin.json abi %d != host %d', [Manifest.AbiVersion, cPluginAbiVersion]));
      Exit;
    end;
  end;

  if not EnsureWasmEngine(EngineErr) then
  begin
    Log(AFileName, plrSkippedNoRuntime, EngineErr);
    Exit;
  end;

  Inst := TWasmPluginInstance.Create(APluginId);
  if not Inst.LoadFromFile(AFileName, Err) then
  begin
    Inst.Free;
    Log(AFileName, plrInitFailed, Err);
    Exit;
  end;
  if not Inst.InitPlugin(Err) then
  begin
    Inst.Free;
    if Pos('export missing', Err) > 0 then
      Log(AFileName, plrMissingExports, Err)
    else if Pos('ABI version', Err) > 0 then
      Log(AFileName, plrAbiMismatch, Err)
    else
      Log(AFileName, plrInitFailed, Err);
    Exit;
  end;

  Loaded.PluginId := APluginId;
  Loaded.Kind := lpkWasm;
  Loaded.ModuleHandle := 0;
  Loaded.WasmInst := Inst;
  Loaded.Shutdown := nil;
  Loaded.SetSecret := nil;
  Loaded.HostApi := nil;
  FLoaded.Add(Loaded);
  RegisterManifestArchiveExtensions(APluginId, Manifest);
  Log(AFileName, plrLoaded, 'OK (wasm)');
  Result := True;
end;

function TPluginLoader.LoadedPluginIds: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FLoaded.Count);
  for I := 0 to FLoaded.Count - 1 do
    Result[I] := FLoaded[I].PluginId;
end;

function TPluginLoader.TrySetSecret(const APluginId, AKey, AValue: string): Boolean;
var
  I: Integer;
  KeyU, ValU: UTF8String;
  EmptyZ: AnsiChar;
  ValPtr: PAnsiChar;
begin
  Result := False;
  if (APluginId = '') or (AKey = '') then
    Exit;
  EmptyZ := #0;
  KeyU := UTF8String(AKey);
  if AValue = '' then
    ValPtr := @EmptyZ
  else
  begin
    ValU := UTF8String(AValue);
    ValPtr := PAnsiChar(ValU);
  end;
  for I := 0 to FLoaded.Count - 1 do
    if SameText(FLoaded[I].PluginId, APluginId) and Assigned(FLoaded[I].SetSecret) then
      Exit(FLoaded[I].SetSecret(PAnsiChar(KeyU), ValPtr) = 0);
end;

function TPluginLoader.TryClearSecret(const APluginId, AKey: string): Boolean;
var
  I: Integer;
  KeyU: UTF8String;
begin
  Result := False;
  if (APluginId = '') or (AKey = '') then
    Exit;
  KeyU := UTF8String(AKey);
  for I := 0 to FLoaded.Count - 1 do
    if SameText(FLoaded[I].PluginId, APluginId) and Assigned(FLoaded[I].SetSecret) then
      Exit(FLoaded[I].SetSecret(PAnsiChar(KeyU), nil) = 0);
end;

function TPluginLoader.PluginIsLoaded(const APluginId: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FLoaded.Count - 1 do
    if SameText(FLoaded[I].PluginId, APluginId) then
      Exit(True);
end;

function TPluginLoader.EnsureIndex(AIndex: Integer): Boolean;
var
  E: TCatalogedPlugin;
  FileName: string;
begin
  if (AIndex < 0) or (AIndex >= FCatalog.Count) then
    Exit(False);
  E := FCatalog[AIndex];
  if PluginIsLoaded(E.PluginId) then
    Exit(True);
  // A nested resolve from inside mtn_plugin_init must not start a second load.
  if E.Attempted or FEnsuring then
    Exit(False);
  E.Attempted := True;
  FCatalog[AIndex] := E;
  FEnsuring := True;
  try
    for FileName in E.Files do
      if SameText(TPath.GetExtension(FileName), '.dll') then
        TryLoadOne(FileName, E.PluginId)
      else
        TryLoadOneWasm(FileName, E.PluginId);
  finally
    FEnsuring := False;
  end;
  Result := PluginIsLoaded(E.PluginId);
end;

procedure TPluginLoader.CatalogPlugins(const ADir: string);
var
  PluginDir, PluginId: string;
  E: TCatalogedPlugin;
  Manifest: TPluginManifest;
begin
  FCatalog.Clear;
  FAllEnsured := False;
  if not TDirectory.Exists(ADir) then
    Exit;
  for PluginDir in TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly) do
  begin
    PluginId := TPath.GetFileName(PluginDir);
    E.PluginId := PluginId;
    E.Files := CollectPluginModules(PluginDir);
    E.Attempted := PluginIsLoaded(PluginId);
    if TryReadPluginManifest(PluginDir, Manifest) then
    begin
      E.Schemes := Manifest.Schemes;
      E.ArchiveExtensions := Manifest.ArchiveExtensions;
    end
    else
    begin
      SetLength(E.Schemes, 0);
      SetLength(E.ArchiveExtensions, 0);
    end;
    FCatalog.Add(E);
  end;
end;

function TPluginLoader.EnsureScheme(const AScheme: string): Boolean;
var
  I, J: Integer;
  Scheme: string;
begin
  Result := False;
  if FEnsuring then
    Exit;
  Scheme := LowerCase(Trim(AScheme));
  if Scheme = '' then
    Exit;
  for I := 0 to FCatalog.Count - 1 do
    for J := 0 to High(FCatalog[I].Schemes) do
      if FCatalog[I].Schemes[J] = Scheme then
        Exit(EnsureIndex(I));
end;

function TPluginLoader.EnsureArchiveExtension(const AFileName: string): Boolean;
var
  I: Integer;
  Key: string;
begin
  Result := False;
  if FEnsuring then
    Exit;
  Key := ExtensionKey(AFileName);
  if Key = '' then
    Exit;
  for I := 0 to FCatalog.Count - 1 do
    if ListHasExt(FCatalog[I].ArchiveExtensions, Key) then
      Exit(EnsureIndex(I));
end;

procedure TPluginLoader.EnsureAll;
var
  I: Integer;
begin
  if FAllEnsured or FEnsuring then
    Exit;
  for I := 0 to FCatalog.Count - 1 do
    EnsureIndex(I);
  FAllEnsured := True;
end;

function TPluginLoader.CatalogPluginIds: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FCatalog.Count);
  for I := 0 to FCatalog.Count - 1 do
    Result[I] := FCatalog[I].PluginId;
end;

procedure TPluginLoader.LoadPluginsFrom(const ADir: string);
var
  PluginDir, FileName, PluginId: string;
  Modules: TArray<string>;
begin
  if not TDirectory.Exists(ADir) then
    Exit;
  for PluginDir in TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly) do
  begin
    PluginId := TPath.GetFileName(PluginDir);
    // dll, then wat, then wasm — same order as before the single scan.
    Modules := CollectPluginModules(PluginDir);
    for FileName in Modules do
      if SameText(TPath.GetExtension(FileName), '.dll') then
        TryLoadOne(FileName, PluginId)
      else
        TryLoadOneWasm(FileName, PluginId);
  end;
end;

procedure TPluginLoader.UnloadAll;
var
  I: Integer;
  E: TCatalogedPlugin;
begin
  for I := FLoaded.Count - 1 downto 0 do
  begin
    // Drop registry entries before FreeLibrary so new resolves cannot call
    // into a module that is about to disappear.
    KeymapRegistry.UnregisterPlugin(FLoaded[I].PluginId);
    MenuRegistry.UnregisterPlugin(FLoaded[I].PluginId);
    GlobalVfsRegistry.UnregisterPlugin(FLoaded[I].PluginId);
    PanelPluginRegistry.UnregisterPlugin(FLoaded[I].PluginId);
    try
      if FLoaded[I].Kind = lpkWasm then
      begin
        if FLoaded[I].WasmInst <> nil then
        begin
          FLoaded[I].WasmInst.ShutdownPlugin;
          FLoaded[I].WasmInst.Free;
        end;
      end
      else if Assigned(FLoaded[I].Shutdown) then
        FLoaded[I].Shutdown();
    except
      // A misbehaving plugin's shutdown must not block unloading the rest.
    end;
    if FLoaded[I].HostApi <> nil then
      Dispose(FLoaded[I].HostApi);
    if FLoaded[I].ModuleHandle <> 0 then
      FreeLibrary(FLoaded[I].ModuleHandle);
  end;
  FLoaded.Clear;
  for I := 0 to FCatalog.Count - 1 do
  begin
    E := FCatalog[I];
    E.Attempted := False;
    FCatalog[I] := E;
  end;
  FAllEnsured := False;
end;

var
  GPluginLoader: TPluginLoader;

function PluginLoader: TPluginLoader;
begin
  if GPluginLoader = nil then
    GPluginLoader := TPluginLoader.Create;
  Result := GPluginLoader;
end;

initialization

finalization
  FreeAndNil(GPluginLoader);

end.
