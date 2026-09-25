program TestWasmHost;

{$APPTYPE CONSOLE}

{ Stage 30: Wasmtime host + demo WASM VFS. Skips with exit 0 when wasmtime.dll
  is not present (same pattern as TestSevenZipPlugin / 7z.dll). }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.TypInfo,
  Winapi.Windows,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uVfsRegistry in '..\..\Core\uVfsRegistry.pas',
  uPanelModel in '..\..\Core\uPanelModel.pas',
  uPanelPluginRegistry in '..\..\Core\uPanelPluginRegistry.pas',
  uKeymap in '..\..\Core\uKeymap.pas',
  uKeymapRegistry in '..\..\Core\uKeymapRegistry.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelOverlays in '..\..\Core\uDualPanelOverlays.pas',
  uTopMenuBar in '..\..\Core\uTopMenuBar.pas',
  uMenuRegistry in '..\..\Core\uMenuRegistry.pas',
  uMessageBus in '..\..\Core\uMessageBus.pas',
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsCdeclAdapter in '..\..\Core\uVfsCdeclAdapter.pas',
  uWasmtimeApi in '..\..\Core\uWasmtimeApi.pas',
  uWasmPluginHost in '..\..\Core\uWasmPluginHost.pas',
  uPluginManifest in '..\..\Core\uPluginManifest.pas',
  uPluginLoader in '..\..\Core\uPluginLoader.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
end;

function DemoPluginDir: string;
begin
  Result := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\plugins\mtn.wasm.demo'));
end;

procedure WaitList(const AVfs: IVirtualFileSystem; const AURI: string;
  out AItems: TArray<TVfsEntry>; out AErr: TVfsError);
var
  Ev: TEvent;
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.ListDirectoryAsync(AURI, nil,
      procedure(const AList: TArray<TVfsEntry>; const AListErr: TVfsError)
      begin
        Items := AList;
        Err := AListErr;
        Ev.SetEvent;
      end);
    Tick := GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if GetTickCount - Tick > 15000 then
        raise Exception.Create('ListDirectoryAsync timed out');
    end;
    CheckSynchronize;
    AItems := Items;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitText(const AVfs: IVirtualFileSystem; const AURI: string;
  out AText: string; out AErr: TVfsError);
var
  Ev: TEvent;
  Text: string;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.ReadTextAsync(AURI, 4096, nil,
      procedure(const AGot: string; AEnc: TTextFileEncoding; const AReadErr: TVfsError)
      begin
        Text := AGot;
        Err := AReadErr;
        Ev.SetEvent;
      end);
    Tick := GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if GetTickCount - Tick > 15000 then
        raise Exception.Create('ReadTextAsync timed out');
    end;
    CheckSynchronize;
    AText := Text;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WriteUtf8NoBom(const APath, AText: string);
var
  Enc: TUTF8Encoding;
begin
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllBytes(APath, Enc.GetBytes(AText));
  finally
    Enc.Free;
  end;
end;

procedure StageDir(const ARoot, APluginId, AWat: string);
var
  Dest: string;
begin
  Dest := TPath.Combine(ARoot, APluginId);
  if TDirectory.Exists(Dest) then
    TDirectory.Delete(Dest, True);
  TDirectory.CreateDirectory(Dest);
  WriteUtf8NoBom(TPath.Combine(Dest, 'plugin.json'),
    Format('{"id":"%s","name":"%s","version":"0.1.0","abi":1}', [APluginId, APluginId]));
  WriteUtf8NoBom(TPath.Combine(Dest, 'plugin.wat'), AWat);
end;

procedure TestDemoPull;
var
  PluginsRoot, DemoSrc, Dest, Wat: string;
  Loaded, Failed, Skipped: Integer;
  Backend: IVirtualFileSystem;
  Items: TArray<TVfsEntry>;
  VErr: TVfsError;
  Text: string;
  I: Integer;
  FoundHello, FoundDocs: Boolean;
begin
  DemoSrc := TPath.Combine(DemoPluginDir, 'plugin.wat');
  Expect(TFile.Exists(DemoSrc), 'demo plugin.wat missing: ' + DemoSrc);
  Wat := TFile.ReadAllText(DemoSrc, TEncoding.UTF8);

  Loaded := 0;
  Failed := 0;
  Skipped := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      Writeln(Format('  [plugin] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
      case AResult of
        plrLoaded: Inc(Loaded);
        plrSkippedNoRuntime, plrSkippedHelperDll: Inc(Skipped);
      else
        Inc(Failed);
      end;
    end;

  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-wasm-test');
  if TDirectory.Exists(PluginsRoot) then
    TDirectory.Delete(PluginsRoot, True);
  Dest := TPath.Combine(PluginsRoot, 'mtn.wasm.demo');
  TDirectory.CreateDirectory(Dest);
  TFile.Copy(DemoSrc, TPath.Combine(Dest, 'plugin.wat'), True);
  TFile.Copy(TPath.Combine(DemoPluginDir, 'plugin.json'),
    TPath.Combine(Dest, 'plugin.json'), True);

  PluginLoader.LoadPluginsFrom(PluginsRoot);
  Expect(Skipped = 0, 'demo should not skip when wasmtime is loaded');
  Expect(Failed = 0, 'demo WASM must load');
  Expect(Loaded >= 1, 'demo WASM should load');
  Expect(GlobalVfsRegistry.IsPluginOwned('wasmdemo:///'),
    'wasmdemo:// is plugin-owned');
  Expect(GlobalVfsRegistry.TryResolve('wasmdemo:///', Backend),
    'resolve wasmdemo URI');

  WaitList(Backend, 'wasmdemo:///', Items, VErr);
  Expect(VErr.Code = vecOk, 'list ok: ' + VErr.Message);
  FoundHello := False;
  FoundDocs := False;
  for I := 0 to High(Items) do
  begin
    if SameText(Items[I].Name, 'hello.txt') then
      FoundHello := True;
    if SameText(Items[I].Name, 'docs') and Items[I].IsDirectory then
      FoundDocs := True;
  end;
  Expect(FoundHello, 'listing contains hello.txt');
  Expect(FoundDocs, 'listing contains docs/');

  WaitText(Backend, 'wasmdemo:///hello.txt', Text, VErr);
  Expect(VErr.Code = vecOk, 'read ok: ' + VErr.Message);
  Expect(Pos('hello, wasm', Text) > 0, 'payload from WASM linear memory');

  PluginLoader.UnloadAll;
  Expect(not GlobalVfsRegistry.IsPluginOwned('wasmdemo:///'),
    'wasmdemo:// not plugin-owned after unload');
  Writeln('OK: TestDemoPull');
end;

procedure TestTrapIsolated;
var
  Root: string;
  FailedInit: Boolean;
  Msg: string;
begin
  FailedInit := False;
  Msg := '';
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      Writeln(Format('  [trap] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
      if AResult = plrInitFailed then
      begin
        FailedInit := True;
        Msg := AMessage;
      end;
    end;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-wasm-trap');
  StageDir(Root, 'mtn.wasm.trap',
    '(module' + sLineBreak +
    '  (memory (export "memory") 1)' + sLineBreak +
    '  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 1))' + sLineBreak +
    '  (func (export "mtn_plugin_init") (result i32) unreachable)' + sLineBreak +
    '  (func (export "mtn_plugin_shutdown")))');
  PluginLoader.LoadPluginsFrom(Root);
  Expect(FailedInit, 'unreachable in init must be reported as init failure');
  Expect((Pos('trap', LowerCase(Msg)) > 0) or (Pos('unreachable', LowerCase(Msg)) > 0),
    'failure must be a guest trap, not a parse error: ' + Msg);
  Expect(Length(PluginLoader.LoadedPluginIds) = 0, 'trapped module must not stay loaded');
  PluginLoader.UnloadAll;
  Writeln('OK: TestTrapIsolated (process still alive)');
end;

procedure TestNoWasi;
var
  Root: string;
  InstantiationFailed: Boolean;
  Msg: string;
begin
  InstantiationFailed := False;
  Msg := '';
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      Writeln(Format('  [wasi] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
      if AResult = plrInitFailed then
      begin
        InstantiationFailed := True;
        Msg := AMessage;
      end;
    end;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-wasm-wasi');
  StageDir(Root, 'mtn.wasm.wasi',
    '(module' + sLineBreak +
    '  (import "wasi_snapshot_preview1" "proc_exit" (func (param i32)))' + sLineBreak +
    '  (memory (export "memory") 1)' + sLineBreak +
    '  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 1))' + sLineBreak +
    '  (func (export "mtn_plugin_init") (result i32) (i32.const 0))' + sLineBreak +
    '  (func (export "mtn_plugin_shutdown")))');
  PluginLoader.LoadPluginsFrom(Root);
  Expect(InstantiationFailed, 'WASI import must fail instantiate (no host FS)');
  Expect((Pos('wasi', LowerCase(Msg)) > 0) or (Pos('import', LowerCase(Msg)) > 0) or
    (Pos('instantiate', LowerCase(Msg)) > 0),
    'failure must be a missing WASI import: ' + Msg);
  Expect(Length(PluginLoader.LoadedPluginIds) = 0, 'WASI module must not load');
  PluginLoader.UnloadAll;
  Writeln('OK: TestNoWasi');
end;

procedure TestOobRegisterIsolated;
var
  Root: string;
  Loaded: Boolean;
begin
  Loaded := False;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      Writeln(Format('  [oob] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
      if AResult = plrLoaded then
        Loaded := True;
    end;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-wasm-oob');
  StageDir(Root, 'mtn.wasm.oob',
    '(module' + sLineBreak +
    '  (import "mtn_host" "register_vfs_scheme"' + sLineBreak +
    '    (func $reg (param i32 i32 i32) (result i32)))' + sLineBreak +
    '  (memory (export "memory") 1)' + sLineBreak +
    '  (func (export "mtn_plugin_get_abi_version") (result i64) (i64.const 1))' + sLineBreak +
    '  (func (export "mtn_plugin_init") (result i32)' + sLineBreak +
    '    (drop (call $reg (i32.const 2147483647) (i32.const 16) (i32.const 1)))' + sLineBreak +
    '    (i32.const 0))' + sLineBreak +
    '  (func (export "mtn_plugin_shutdown")))');
  PluginLoader.LoadPluginsFrom(Root);
  Expect(Loaded, 'OOB register is a failed host call, not a crash; init still 0');
  Expect(not GlobalVfsRegistry.IsPluginOwned('wasmdemo:///'),
    'OOB scheme pointer must not register a host object');
  PluginLoader.UnloadAll;
  Writeln('OK: TestOobRegisterIsolated');
end;

begin
  try
    Expect(SizeOf(TWasmtimeVal) = cWasmtimeValSize, 'TWasmtimeVal layout');
    Expect(SizeOf(TWasmtimeExtern) = cWasmtimeExternSize, 'TWasmtimeExtern layout');
    if FindWasmtimeDll = '' then
    begin
      Writeln('SKIP: wasmtime.dll not found (run src/tools/fetch-wasmtime.ps1 or set MTN2_WASMTIME_DLL)');
      Halt(0);
    end;
    TestDemoPull;
    TestTrapIsolated;
    TestNoWasi;
    TestOobRegisterIsolated;
    Writeln('All WasmHost tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
