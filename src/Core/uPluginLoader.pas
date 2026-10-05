unit uPluginLoader;

{ Plugin loader. Layout: each plugin lives in its own subdirectory of the
  plugins root (<ExeDir>\plugins\<plugin-id>\ - the plugin-id used for
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

  WASM: every *.wat / *.wasm in the same subdirectory is loaded
  through uWasmPluginHost (optional wasmtime.dll). Guest code talks JSON /
  UTF-8 copies in linear memory - not THostApiTable pointers. Missing
  wasmtime.dll skips WASM modules without failing the host (same idea as
  a missing 7z.dll). A trap inside the guest is logged and isolated; it
  does not unwind into the Delphi process.

  Stability note: LoadLibrary/GetProcAddress failures and ABI mismatches are
  handled without crashing the host (skip + log). Once mtn_plugin_init is
  called, a misbehaving *native* plugin (e.g. an access violation
  inside its own code) can still crash the process - Win32/Delphi structured
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
  uKeymap, uKeymapRegistry, uMenuRegistry, uCommandRegistry, uDocumentProviders, uPluginUi,
  uPluginChrome, uPluginSettings,
  uPluginManifest,
  uWasmPluginHost;

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
        /// <summary>The manifest says "keepLoaded": FreeLibrary is skipped.</summary>
        KeepLoaded: Boolean;
      end;
    type
      TCatalogedPlugin = record
        PluginId: string;
        Schemes: TArray<string>;
        ArchiveExtensions: TArray<string>;
        Files: TArray<string>;
        Attempted: Boolean;
        /// <summary>Loaded at CatalogPlugins: the manifest asks for "startup",
        /// or asks to override built-ins and the user allowed it.</summary>
        LoadAtStart: Boolean;
        /// <summary>The user switched the plugin off: it is neither loaded nor
        /// offered to the lazy triggers.</summary>
        Disabled: Boolean;
        /// <summary>The manifest's "overrides" (built-ins the plugin asks to replace).</summary>
        Overrides: TArray<string>;
      end;
    var
      FLoaded: TList<TLoadedPlugin>;
      FCatalog: TList<TCatalogedPlugin>;
      FOnLog: TPluginLoadLogEvent;
      FEnsuring: Boolean;
      FAllEnsured: Boolean;
      FOverrideAllow: TArray<string>;
      FDisabled: TArray<string>;
    function BuildHostApiTable: THostApiTable;
    function IsOverrideAllowed(const APluginId: string): Boolean;
    function IsDisabled(const APluginId: string): Boolean;
    procedure UnloadAt(AIndex: Integer);
    procedure GrantManifestOverrides(const APluginId: string;
      const AManifest: TPluginManifest);
    function TryLoadOne(const AFileName, APluginId: string): Boolean;
    function TryLoadOneWasm(const AFileName, APluginId: string): Boolean;
    function PluginIsLoaded(const APluginId: string): Boolean;
    function EnsureIndex(AIndex: Integer): Boolean;
    procedure Log(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Loads every plugin found under ADir\<plugin-id>\*.dll - one
    /// subdirectory per plugin, plugin-id = subdirectory name (see unit
    /// comment). A bare *.dll/*.wat/*.wasm directly under ADir is ignored.
    /// Missing ADir is not an error (no plugins to load). Failures on
    /// individual modules are logged (see OnLog) and skipped - one bad
    /// plugin never stops the others or the host.</summary>
    procedure LoadPluginsFrom(const ADir: string);
    /// <summary>Plugin ids the user trusts to replace built-in schemes and
    /// archive extensions. Applies to plugins loaded afterwards; a plugin
    /// outside the list keeps its "overrides" manifest entry inert.</summary>
    procedure SetOverrideAllowList(const AIds: TArray<string>);
    /// <summary>Plugin ids the user switched off. Applies to plugins catalogued
    /// or loaded afterwards; SetPluginEnabled changes it on the fly.</summary>
    procedure SetDisabledPlugins(const AIds: TArray<string>);
    function DisabledPlugins: TArray<string>;
    /// <summary>Switches a plugin off (it is unloaded now) or on (it is loaded
    /// now). False when nothing in the catalog has that id.</summary>
    function SetPluginEnabled(const APluginId: string; AEnabled: Boolean): Boolean;
    /// <summary>Unloads every loaded module of APluginId, dropping its
    /// registrations first. The catalog entry stays.</summary>
    procedure UnloadPlugin(const APluginId: string);
    function IsPluginLoaded(const APluginId: string): Boolean;
    function IsPluginDisabled(const APluginId: string): Boolean;
    /// <summary>Built-ins the catalogued plugin asks to replace (its manifest
    /// "overrides"); empty when it asks for none.</summary>
    function PluginOverrides(const APluginId: string): TArray<string>;
    function IsOverrideGranted(const APluginId: string): Boolean;
    function OverrideAllowList: TArray<string>;
    /// <summary>Lets the plugin replace the built-ins its manifest names (or takes
    /// that back). A loaded plugin is reloaded at once, since the priority of its
    /// registrations is decided when it registers. False when the catalog has no
    /// such plugin or it asks for no replacement.</summary>
    function SetPluginOverrideAllowed(const APluginId: string; AAllowed: Boolean): Boolean;
    /// <summary>Scans ADir the same way as LoadPluginsFrom but does not
    /// call LoadLibrary. Schemes and archive extensions come from
    /// plugin.json so a later Ensure* can load just that plugin. A plugin
    /// whose manifest says "startup": true, or that is allowed to override
    /// built-ins, is loaded right away: the lazy triggers never fire for a
    /// scheme or extension a built-in handler already answers, nor for a
    /// plugin that only hooks commands.</summary>
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
    /// <summary>Clears a secret set earlier (AValueUtf8 = nil).</summary>
    function TryClearSecret(const APluginId, AKey: string): Boolean;
    property OnLog: TPluginLoadLogEvent read FOnLog write FOnLog;
  end;

function PluginLoader: TPluginLoader;

implementation

{ Register* thunks - each becomes a THostApiTable function pointer.
  AUserData for RegisterVfsScheme carries the plugin's own VFS callback
  AUserData through unchanged; the plugin id is passed explicitly per call
  since a single cdecl function pointer is shared by every loaded plugin. }

{ A manifest's archiveExtensions (mtn.7z's plugin.json etc.) become
  akPluginScheme entries in GlobalVfsRegistry that navigate into the plugin's
  first declared scheme ("7z" when the manifest declares none); the built-in
  zip/jar/apk entries are registered once in GlobalVfsRegistry itself, not
  here. Tagging with APluginId means UnloadAll's UnregisterPlugin call
  drops these along with the plugin's VFS scheme. }
procedure RegisterManifestArchiveExtensions(const APluginId: string;
  const AManifest: TPluginManifest);
var
  Ext, Scheme: string;
begin
  if Length(AManifest.Schemes) > 0 then
    Scheme := AManifest.Schemes[0]
  else
    Scheme := '7z';
  for Ext in AManifest.ArchiveExtensions do
    GlobalVfsRegistry.RegisterArchiveExtension(APluginId, Ext, akPluginScheme,
      100, Scheme);
end;

{ A plugin may replace a built-in scheme or extension only when its manifest
  asks for it ("overrides") and the user trusts it (plugins\overrides.json).
  The grant is made before mtn_plugin_init because the registry decides the
  priority of an entry when it is registered (see
  TPluginLoader.GrantManifestOverrides). }

function ThunkRegisterVfsScheme(APluginId, AScheme: PAnsiChar;
  ACallbacks: PVfsCallbacksCdecl; AUserData: Pointer; APriority: Int64): Int64; cdecl;
var
  Backend: IVirtualFileSystem;
begin
  try
    if (APluginId = nil) or (AScheme = nil) or (ACallbacks = nil) then
      Exit(-1);
    if IsReservedVfsScheme(UTF8ToString(AScheme)) then
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

{ AAction names either a built-in keymap action (rebind) or a command the
  plugin registered with RegisterCommand (a chord that runs it). }
function ThunkRegisterKeyBinding(APluginId, AAction, AKeyCombo: PAnsiChar): Int64; cdecl;
var
  PluginId, Action, Combo: string;
begin
  try
    if (APluginId = nil) or (AAction = nil) or (AKeyCombo = nil) then
      Exit(-1);
    PluginId := UTF8ToString(APluginId);
    Action := UTF8ToString(AAction);
    Combo := UTF8ToString(AKeyCombo);
    if CommandRegistry.HasCommand(Action) then
      CommandRegistry.RegisterCommandBinding(PluginId, Action, Combo)
    else
      KeymapRegistry.RegisterBinding(PluginId, Action, Combo);
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterCommand(APluginId, ACommandId: PAnsiChar;
  AOnRun: THostCommandCallback; AUserData: Pointer): Int64; cdecl;
var
  PluginId, CommandId: string;
  Callback: THostCommandCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or (ACommandId = nil) or not Assigned(AOnRun) then
      Exit(-1);
    PluginId := UTF8ToString(APluginId);
    CommandId := UTF8ToString(ACommandId);
    Callback := AOnRun;
    UserData := AUserData;
    CommandRegistry.RegisterCommand(PluginId, CommandId,
      procedure
      begin
        Callback(UserData);
      end);
    if CommandRegistry.HasCommand(CommandId) then
      Result := 0
    else
      Result := -1;
  except
    Result := -1;
  end;
end;

function ThunkRegisterCommandHook(APluginId, ACommand: PAnsiChar;
  AHook: THostCommandHookCallback; AUserData: Pointer; APriority: Int64): Int64; cdecl;
var
  PluginId: string;
  Callback: THostCommandHookCallback;
  UserData: Pointer;
  Act: TKeymapAction;
begin
  try
    if (APluginId = nil) or (ACommand = nil) or not Assigned(AHook) then
      Exit(-1);
    if not TryKeymapActionByName(UTF8ToString(ACommand), Act) then
      Exit(-1);
    PluginId := UTF8ToString(APluginId);
    Callback := AHook;
    UserData := AUserData;
    CommandRegistry.RegisterHook(PluginId, UTF8ToString(ACommand),
      function(const ACommandName, AOrigin: string): Boolean
      var
        CommandU, OriginU: UTF8String;
      begin
        CommandU := UTF8String(ACommandName);
        OriginU := UTF8String(AOrigin);
        Result := Callback(UserData, PAnsiChar(CommandU), PAnsiChar(OriginU)) = 1;
      end, Integer(APriority));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterDocumentProvider(APluginId, AExtensions: PAnsiChar;
  AModes: Int64; AHandler: THostDocumentProviderCallback; AUserData: Pointer;
  APriority: Int64): Int64; cdecl;
var
  PluginId: string;
  Modes: TDocumentModes;
  Callback: THostDocumentProviderCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or (AExtensions = nil) or not Assigned(AHandler) then
      Exit(-1);
    Modes := [];
    if (AModes and 1) <> 0 then
      Include(Modes, dmView);
    if (AModes and 2) <> 0 then
      Include(Modes, dmEdit);
    if Modes = [] then
      Exit(-1);
    PluginId := UTF8ToString(APluginId);
    Callback := AHandler;
    UserData := AUserData;
    DocumentProviders.RegisterProvider(PluginId, 'native', UTF8ToString(AExtensions), Modes,
      function(const AURI: string; AViewOnly: Boolean; out ARedirectURI: string): TDocumentOpenKind
      var
        UriU, ModeU: UTF8String;
        Buf: array[0..4095] of AnsiChar;
        Answer: Int64;
      begin
        ARedirectURI := '';
        UriU := UTF8String(AURI);
        if AViewOnly then
          ModeU := 'view'
        else
          ModeU := 'edit';
        Buf[0] := #0;
        Answer := Callback(UserData, PAnsiChar(UriU), PAnsiChar(ModeU), @Buf[0], SizeOf(Buf));
        Buf[High(Buf)] := #0;
        case Answer of
          1: Result := dokHandled;
          2:
            begin
              ARedirectURI := UTF8ToString(PAnsiChar(@Buf[0]));
              Result := dokRedirect;
            end;
        else
          Result := dokPass;
        end;
      end, Integer(APriority));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkShowDialog(APluginId, ADeclJson: PAnsiChar;
  AOnCommand: THostDialogCommandCallback; AUserData: Pointer): Int64; cdecl;
var
  Callback: THostDialogCommandCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or (ADeclJson = nil) or not Assigned(AOnCommand) then
      Exit(-1);
    Callback := AOnCommand;
    UserData := AUserData;
    if PluginShowDialog(UTF8ToString(APluginId), UTF8ToString(ADeclJson),
      procedure(const AControlId, AValuesJson: string)
      var
        IdU, ValuesU: UTF8String;
      begin
        IdU := UTF8String(AControlId);
        ValuesU := UTF8String(AValuesJson);
        Callback(UserData, PAnsiChar(IdU), PAnsiChar(ValuesU));
      end) then
      Result := 0
    else
      Result := -1;
  except
    Result := -1;
  end;
end;

function ThunkRegisterPanelActivate(APluginId, AScheme: PAnsiChar;
  AHandler: THostPanelActivateCallback; AUserData: Pointer): Int64; cdecl;
var
  Callback: THostPanelActivateCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or (AScheme = nil) or not Assigned(AHandler) then
      Exit(-1);
    Callback := AHandler;
    UserData := AUserData;
    PanelPluginRegistry.RegisterActivateHandler(UTF8ToString(APluginId),
      UTF8ToString(AScheme),
      function(const APanelURI, ARowURI: string; AIsDirectory: Boolean): Boolean
      var
        PanelU, RowU: UTF8String;
      begin
        PanelU := UTF8String(APanelURI);
        RowU := UTF8String(ARowURI);
        Result := Callback(UserData, PAnsiChar(PanelU), PAnsiChar(RowU),
          Ord(AIsDirectory)) = 1;
      end);
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkSetCommandCaption(APluginId, ACommandId, ACaption: PAnsiChar): Int64; cdecl;
begin
  try
    if (APluginId = nil) or (ACommandId = nil) then
      Exit(-1);
    if ACaption = nil then
      CommandRegistry.SetCommandCaption(UTF8ToString(APluginId), UTF8ToString(ACommandId), '')
    else
      CommandRegistry.SetCommandCaption(UTF8ToString(APluginId), UTF8ToString(ACommandId),
        UTF8ToString(ACaption));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkSetStatusSegment(APluginId, ASegmentId, AText: PAnsiChar): Int64; cdecl;
begin
  try
    if (APluginId = nil) or (ASegmentId = nil) then
      Exit(-1);
    if AText = nil then
      PluginChrome.SetStatusSegment(UTF8ToString(APluginId), UTF8ToString(ASegmentId), '')
    else
      PluginChrome.SetStatusSegment(UTF8ToString(APluginId), UTF8ToString(ASegmentId),
        UTF8ToString(AText));
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkRegisterSettings(APluginId: PAnsiChar; AOnConfigure: THostCommandCallback;
  AUserData: Pointer): Int64; cdecl;
var
  Callback: THostCommandCallback;
  UserData: Pointer;
begin
  try
    if (APluginId = nil) or not Assigned(AOnConfigure) then
      Exit(-1);
    Callback := AOnConfigure;
    UserData := AUserData;
    PluginSettings.RegisterConfigure(UTF8ToString(APluginId),
      procedure
      begin
        Callback(UserData);
      end);
    Result := 0;
  except
    Result := -1;
  end;
end;

function ThunkGetSetting(APluginId, AKey: PAnsiChar; ABuf: PAnsiChar;
  ABufSize: Int64): Int64; cdecl;
var
  Value: string;
  Bytes: UTF8String;
begin
  try
    if (APluginId = nil) or (AKey = nil) then
      Exit(-1);
    if not PluginSettings.TryGetValue(UTF8ToString(APluginId), UTF8ToString(AKey), Value) then
      Exit(-1);
    Bytes := UTF8String(Value);
    if (ABuf = nil) or (Int64(Length(Bytes)) + 1 > ABufSize) then
      Exit(-2);
    if Length(Bytes) > 0 then
      Move(Bytes[1], ABuf^, Length(Bytes));
    PByte(ABuf)[Length(Bytes)] := 0;
    Result := Length(Bytes);
  except
    Result := -1;
  end;
end;

function ThunkSetSetting(APluginId, AKey, AValue: PAnsiChar): Int64; cdecl;
var
  Value: string;
begin
  try
    if (APluginId = nil) or (AKey = nil) then
      Exit(-1);
    if AValue = nil then
      Value := ''
    else
      Value := UTF8ToString(AValue);
    if PluginSettings.SetValue(UTF8ToString(APluginId), UTF8ToString(AKey), Value) then
      Result := 0
    else
      Result := -1;
  except
    Result := -1;
  end;
end;

function ThunkOpenExternal(AURI: PAnsiChar): Int64; cdecl;
begin
  try
    if (AURI <> nil) and OpenUriWithSystem(UTF8ToString(AURI)) then
      Result := 0
    else
      Result := -1;
  except
    Result := -1;
  end;
end;

function ThunkExecuteCommand(ACommandId: PAnsiChar): Int64; cdecl;
begin
  try
    if ACommandId = nil then
      Exit(-1);
    if CommandRegistry.TryExecute(UTF8ToString(ACommandId)) then
      Result := 0
    else
      Result := -1;
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

function TPluginLoader.IsDisabled(const APluginId: string): Boolean;
var
  Id: string;
begin
  for Id in FDisabled do
    if SameText(Id, APluginId) then
      Exit(True);
  Result := False;
end;

procedure TPluginLoader.SetDisabledPlugins(const AIds: TArray<string>);
var
  I: Integer;
  E: TCatalogedPlugin;
begin
  FDisabled := Copy(AIds);
  for I := 0 to FCatalog.Count - 1 do
  begin
    E := FCatalog[I];
    E.Disabled := IsDisabled(E.PluginId);
    FCatalog[I] := E;
  end;
end;

function TPluginLoader.DisabledPlugins: TArray<string>;
begin
  Result := Copy(FDisabled);
end;

function TPluginLoader.PluginOverrides(const APluginId: string): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FCatalog.Count - 1 do
    if SameText(FCatalog[I].PluginId, APluginId) then
      Exit(Copy(FCatalog[I].Overrides));
end;

function TPluginLoader.IsOverrideGranted(const APluginId: string): Boolean;
begin
  Result := IsOverrideAllowed(APluginId);
end;

function TPluginLoader.OverrideAllowList: TArray<string>;
begin
  Result := Copy(FOverrideAllow);
end;

function TPluginLoader.SetPluginOverrideAllowed(const APluginId: string;
  AAllowed: Boolean): Boolean;
var
  I, J: Integer;
  List: TList<string>;
  E: TCatalogedPlugin;
  WasLoaded: Boolean;
begin
  Result := False;
  for I := 0 to FCatalog.Count - 1 do
    if SameText(FCatalog[I].PluginId, APluginId) then
    begin
      if Length(FCatalog[I].Overrides) = 0 then
        Exit;
      List := TList<string>.Create;
      try
        for J := 0 to High(FOverrideAllow) do
          if not SameText(FOverrideAllow[J], APluginId) then
            List.Add(FOverrideAllow[J]);
        if AAllowed then
          List.Add(FCatalog[I].PluginId);
        FOverrideAllow := List.ToArray;
      finally
        List.Free;
      end;
      WasLoaded := PluginIsLoaded(FCatalog[I].PluginId);
      if WasLoaded then
      begin
        UnloadPlugin(FCatalog[I].PluginId);
        E := FCatalog[I];
        E.Attempted := False;
        FCatalog[I] := E;
        if not FCatalog[I].Disabled then
          EnsureIndex(I);
      end;
      Exit(True);
    end;
end;

function TPluginLoader.IsPluginDisabled(const APluginId: string): Boolean;
begin
  Result := IsDisabled(APluginId);
end;

function TPluginLoader.IsPluginLoaded(const APluginId: string): Boolean;
begin
  Result := PluginIsLoaded(APluginId);
end;

function TPluginLoader.SetPluginEnabled(const APluginId: string; AEnabled: Boolean): Boolean;
var
  I, J: Integer;
  E: TCatalogedPlugin;
  List: TList<string>;
begin
  Result := False;
  for I := 0 to FCatalog.Count - 1 do
    if SameText(FCatalog[I].PluginId, APluginId) then
    begin
      List := TList<string>.Create;
      try
        for J := 0 to High(FDisabled) do
          if not SameText(FDisabled[J], APluginId) then
            List.Add(FDisabled[J]);
        if not AEnabled then
          List.Add(FCatalog[I].PluginId);
        FDisabled := List.ToArray;
      finally
        List.Free;
      end;
      E := FCatalog[I];
      E.Disabled := not AEnabled;
      E.Attempted := False;
      FCatalog[I] := E;
      if AEnabled then
        EnsureIndex(I)
      else
        UnloadPlugin(E.PluginId);
      Exit(True);
    end;
end;

procedure TPluginLoader.SetOverrideAllowList(const AIds: TArray<string>);
begin
  FOverrideAllow := Copy(AIds);
end;

function TPluginLoader.IsOverrideAllowed(const APluginId: string): Boolean;
var
  Id: string;
begin
  for Id in FOverrideAllow do
    if SameText(Id, APluginId) then
      Exit(True);
  Result := False;
end;

procedure TPluginLoader.GrantManifestOverrides(const APluginId: string;
  const AManifest: TPluginManifest);
begin
  if (Length(AManifest.Overrides) > 0) and IsOverrideAllowed(APluginId) then
    GlobalVfsRegistry.GrantOverrides(APluginId, AManifest.Overrides);
end;

function TPluginLoader.BuildHostApiTable: THostApiTable;
begin
  InitHostApiTableCore(Result);
  Result.RegisterVfsScheme := @ThunkRegisterVfsScheme;
  Result.RegisterPanelPlugin := @ThunkRegisterPanelPlugin;
  Result.RegisterKeyBinding := @ThunkRegisterKeyBinding;
  Result.RegisterMenuItem := @ThunkRegisterMenuItem;
  Result.RegisterCommand := @ThunkRegisterCommand;
  Result.RegisterCommandHook := @ThunkRegisterCommandHook;
  Result.ExecuteCommand := @ThunkExecuteCommand;
  Result.RegisterDocumentProvider := @ThunkRegisterDocumentProvider;
  Result.OpenExternal := @ThunkOpenExternal;
  Result.ShowDialog := @ThunkShowDialog;
  Result.RegisterPanelActivate := @ThunkRegisterPanelActivate;
  Result.SetCommandCaption := @ThunkSetCommandCaption;
  Result.SetStatusSegment := @ThunkSetStatusSegment;
  Result.RegisterSettings := @ThunkRegisterSettings;
  Result.GetSetting := @ThunkGetSetting;
  Result.SetSetting := @ThunkSetSetting;
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
    if Manifest.HasAbi and not IsSupportedPluginAbi(Manifest.AbiVersion) then
    begin
      Log(AFileName, plrAbiMismatch,
        Format('plugin.json abi %d is outside host range %d..%d', [Manifest.AbiVersion, cPluginMinAbiVersion, cPluginAbiVersion]));
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

  if not IsSupportedPluginAbi(AbiVersion) then
  begin
    Log(AFileName, plrAbiMismatch,
      Format('Plugin ABI version %d is outside host range %d..%d', [AbiVersion, cPluginMinAbiVersion, cPluginAbiVersion]));
    FreeLibrary(Module);
    Exit;
  end;

  GrantManifestOverrides(APluginId, Manifest);
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
  Loaded.KeepLoaded := Manifest.KeepLoaded;
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
    if Manifest.HasAbi and not IsSupportedPluginAbi(Manifest.AbiVersion) then
    begin
      Log(AFileName, plrAbiMismatch,
        Format('plugin.json abi %d is outside host range %d..%d', [Manifest.AbiVersion, cPluginMinAbiVersion, cPluginAbiVersion]));
      Exit;
    end;
  end;

  if not EnsureWasmEngine(EngineErr) then
  begin
    Log(AFileName, plrSkippedNoRuntime, EngineErr);
    Exit;
  end;

  GrantManifestOverrides(APluginId, Manifest);
  Inst := TWasmPluginInstance.Create(APluginId);
  Inst.Wasi := Manifest.Wasi;
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
  Loaded.KeepLoaded := False;
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
  if E.Disabled then
    Exit(False);
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
  I: Integer;
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
    E.Disabled := IsDisabled(PluginId);
    E.LoadAtStart := False;
    SetLength(E.Overrides, 0);
    if TryReadPluginManifest(PluginDir, Manifest) then
    begin
      E.Schemes := Manifest.Schemes;
      E.ArchiveExtensions := Manifest.ArchiveExtensions;
      E.Overrides := Manifest.Overrides;
      E.LoadAtStart := Manifest.Startup or
        ((Length(Manifest.Overrides) > 0) and IsOverrideAllowed(PluginId));
    end
    else
    begin
      SetLength(E.Schemes, 0);
      SetLength(E.ArchiveExtensions, 0);
    end;
    FCatalog.Add(E);
  end;
  for I := 0 to FCatalog.Count - 1 do
    if FCatalog[I].LoadAtStart and not FCatalog[I].Disabled then
      EnsureIndex(I);
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
    if IsDisabled(PluginId) then
      Continue;
    // dll, then wat, then wasm - same order as before the single scan.
    Modules := CollectPluginModules(PluginDir);
    for FileName in Modules do
      if SameText(TPath.GetExtension(FileName), '.dll') then
        TryLoadOne(FileName, PluginId)
      else
        TryLoadOneWasm(FileName, PluginId);
  end;
end;

procedure TPluginLoader.UnloadAt(AIndex: Integer);
begin
  // Drop registry entries before FreeLibrary so new resolves cannot call
  // into a module that is about to disappear.
  KeymapRegistry.UnregisterPlugin(FLoaded[AIndex].PluginId);
  CommandRegistry.UnregisterPlugin(FLoaded[AIndex].PluginId);
  DocumentProviders.UnregisterPlugin(FLoaded[AIndex].PluginId);
  PluginUiUnregister(FLoaded[AIndex].PluginId);
  PluginChrome.UnregisterPlugin(FLoaded[AIndex].PluginId);
  PluginSettings.UnregisterPlugin(FLoaded[AIndex].PluginId);
  MenuRegistry.UnregisterPlugin(FLoaded[AIndex].PluginId);
  GlobalVfsRegistry.UnregisterPlugin(FLoaded[AIndex].PluginId);
  PanelPluginRegistry.UnregisterPlugin(FLoaded[AIndex].PluginId);
  try
    if FLoaded[AIndex].Kind = lpkWasm then
    begin
      if FLoaded[AIndex].WasmInst <> nil then
      begin
        FLoaded[AIndex].WasmInst.ShutdownPlugin;
        FLoaded[AIndex].WasmInst.Free;
      end;
    end
    else if Assigned(FLoaded[AIndex].Shutdown) then
      FLoaded[AIndex].Shutdown();
  except
    // A misbehaving plugin's shutdown must not block unloading the rest.
  end;
  if FLoaded[AIndex].HostApi <> nil then
    Dispose(FLoaded[AIndex].HostApi);
  if (FLoaded[AIndex].ModuleHandle <> 0) and not FLoaded[AIndex].KeepLoaded then
    FreeLibrary(FLoaded[AIndex].ModuleHandle);
end;

procedure TPluginLoader.UnloadPlugin(const APluginId: string);
var
  I: Integer;
begin
  for I := FLoaded.Count - 1 downto 0 do
    if SameText(FLoaded[I].PluginId, APluginId) then
    begin
      UnloadAt(I);
      FLoaded.Delete(I);
    end;
end;

procedure TPluginLoader.UnloadAll;
var
  I: Integer;
  E: TCatalogedPlugin;
begin
  for I := FLoaded.Count - 1 downto 0 do
    UnloadAt(I);
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
