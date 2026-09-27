unit TestWorkspacePlugin;

{ WASM workspace panel: links (not copies) on ws:///. Passes as skipped when
  wasmtime.dll or plugin.wasm is missing. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWorkspacePlugin = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.TypInfo,
  Winapi.Windows,
  uVfsTypes,
  uTextEncoding,
  uVfsRegistry,
  uPanelModel,
  uPanelPluginRegistry,
  uKeymap,
  uKeymapRegistry,
  uTerminalTypes,
  uThemeTypes,
  uDualPanelTypes,
  uWorkspaceVfs,
  uDualPanelOverlays,
  uTopMenuBar,
  uMenuRegistry,
  uMessageBus,
  uPluginHostAbi,
  uVfsCdeclAdapter,
  uWasmtimeApi,
  uWasmPluginHost,
  uPluginManifest,
  uPluginLoader;

function PluginSrcDir: string;
begin
  Result := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\plugins\mtn.ws'));
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

procedure WaitCopy(const AVfs: IVirtualFileSystem; const AFrom, ATo: string;
  out AErr: TVfsError);
var
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.CopyAsync(AFrom, ATo, nil, nil,
      procedure(const ASuccess: Boolean; const ACopyErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := ACopyErr;
        Ev.SetEvent;
      end);
    Tick := GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if GetTickCount - Tick > 15000 then
        raise Exception.Create('CopyAsync timed out');
    end;
    CheckSynchronize;
    if not Ok and (Err.Code = vecOk) then
      Err := TVfsError.Make(vecIOError, 'copy failed', AFrom);
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitDelete(const AVfs: IVirtualFileSystem; const AURI: string;
  out AErr: TVfsError);
var
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.DeleteAsync(AURI, vdmPermanent, nil, nil,
      procedure(const ASuccess: Boolean; const ADelErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := ADelErr;
        Ev.SetEvent;
      end);
    Tick := GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if GetTickCount - Tick > 15000 then
        raise Exception.Create('DeleteAsync timed out');
    end;
    CheckSynchronize;
    if not Ok and (Err.Code = vecOk) then
      Err := TVfsError.Make(vecIOError, 'delete failed', AURI);
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitMkdir(const AVfs: IVirtualFileSystem; const AURI: string;
  out AErr: TVfsError);
var
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.CreateDirectoryAsync(AURI, nil,
      procedure(const ASuccess: Boolean; const AMkErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AMkErr;
        Ev.SetEvent;
      end);
    Tick := GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if GetTickCount - Tick > 15000 then
        raise Exception.Create('CreateDirectoryAsync timed out');
    end;
    CheckSynchronize;
    if not Ok and (Err.Code = vecOk) then
      Err := TVfsError.Make(vecIOError, 'mkdir failed', AURI);
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

function FindNamed(const AItems: TArray<TVfsEntry>; const AName: string;
  out AEntry: TVfsEntry): Boolean;
var
  I: Integer;
begin
  Result := False;
  AEntry := Default(TVfsEntry);
  for I := 0 to High(AItems) do
    if SameText(AItems[I].Name, AName) then
    begin
      AEntry := AItems[I];
      Exit(True);
    end;
end;

procedure StagePlugin(const APluginsRoot, AWasm, AJson: string);
var
  Dest: string;
begin
  Dest := TPath.Combine(APluginsRoot, 'mtn.ws');
  TDirectory.CreateDirectory(Dest);
  TFile.Copy(AWasm, TPath.Combine(Dest, 'plugin.wasm'), True);
  TFile.Copy(AJson, TPath.Combine(Dest, 'plugin.json'), True);
end;

var
  WasmPath, JsonPath, PluginsRoot, WorkDir, SrcTxt, SrcDir, SrcUri: string;
  Loaded, Failed, Skipped: Integer;
  Backend: IVirtualFileSystem;
  Items: TArray<TVfsEntry>;
  Entry: TVfsEntry;
  VErr: TVfsError;
  Rows: TPanelRows;
  ExtraDir, BackUri, BackTarget, ChildUri: string;

{ TTestWorkspacePlugin }

procedure TTestWorkspacePlugin.Run;
begin
  Assert.IsTrue(JoinVfsUri('ws:///', 'x.txt') = 'ws:///x.txt', 'ws join');
  Assert.IsTrue(ParentVfsUri('ws:///a/b') = 'ws:///a', 'ws parent');
  Assert.IsTrue(IsVfsUriNavigationRoot('ws:///'), 'ws root hides ..');
  Assert.IsTrue(not IsVfsUriNavigationRoot('ws:///a'), 'ws nested shows ..');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('ws:///', Backend), 'ws is a built-in scheme');
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('ws:///'), 'ws is not plugin-owned');

  WorkDir := TPath.Combine(TPath.GetTempPath, 'mtn2-ws-plugin');
  TDirectory.CreateDirectory(WorkDir);
  SrcTxt := TPath.Combine(WorkDir, 'hello-ws.txt');
  TFile.WriteAllText(SrcTxt, 'workspace-link', TEncoding.UTF8);
  SrcDir := TPath.Combine(WorkDir, 'ws-folder');
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'inside.txt'), 'nested', TEncoding.UTF8);
  SrcUri := PathToFileUri(SrcTxt);

  WaitList(CreateDefaultVfs, 'ws:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'CreateDefaultVfs empty list ok: ' + VErr.Message);
  Assert.IsTrue(Length(Items) = 0, 'CreateDefaultVfs workspace starts empty');

  WaitList(Backend, 'ws:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'empty list ok: ' + VErr.Message);
  Assert.IsTrue(Length(Items) = 0, 'workspace starts empty');

  WaitCopy(CreateDefaultVfs, SrcUri, JoinVfsUri('ws:///', 'hello-ws.txt'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'link file onto ws: ' + VErr.Message);
  WaitList(Backend, 'ws:///', Items, VErr);
  Assert.IsTrue(FindNamed(Items, 'hello-ws.txt', Entry), 'listing contains hello-ws.txt');
  Assert.IsTrue(not Entry.IsDirectory, 'file link is not a dir');
  Assert.IsTrue(Entry.IsLink, 'file entry is a link');
  Assert.IsTrue(SameVfsUri(Entry.TargetURI, SrcUri), 'targetUri points at original file');
  Assert.IsTrue(TFile.Exists(SrcTxt), 'original file still on disk after link');

  WaitCopy(Backend, PathToFileUri(SrcDir), JoinVfsUri('ws:///', 'ws-folder'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'link dir onto ws: ' + VErr.Message);
  WaitList(Backend, 'ws:///', Items, VErr);
  Assert.IsTrue(FindNamed(Items, 'ws-folder', Entry), 'listing contains dir link');
  Assert.IsTrue(Entry.IsDirectory, 'dir link is a directory');
  Assert.IsTrue(Entry.IsLink, 'dir entry is a link');
  Assert.IsTrue(Entry.TargetURI <> '', 'dir targetUri set');
  Assert.IsTrue(SameVfsUri(WorkspaceParentUriForTarget(PathToFileUri(SrcDir)), 'ws:///'),
    'leaving linked dir returns to workspace root');
  Assert.IsTrue(WorkspaceLinkNameForTarget(PathToFileUri(SrcDir)) = 'ws-folder',
    'return cursor name is the link');
  Rows := RowsFromVfsItems(PathToFileUri(SrcDir), []);
  Assert.IsTrue((Length(Rows) > 0) and Rows[0].IsParent, '.. row in linked dir');
  Assert.IsTrue(SameVfsUri(Rows[0].URI, ParentFileUri(PathToFileUri(SrcDir))),
    '.. without enter-from-ws is disk parent');
  Rows := RowsFromVfsItems(PathToFileUri(SrcDir), [], 'ws:///');
  Assert.IsTrue(SameVfsUri(Rows[0].URI, 'ws:///'),
    '.. after enter-from-ws is workspace');

  BackUri := '';
  BackTarget := '';
  UpdateWorkspaceBackMarker(BackUri, BackTarget, 'ws:///', PathToFileUri(SrcDir));
  Assert.IsTrue(SameVfsUri(BackUri, 'ws:///'), 'enter dir-link remembers workspace');
  Assert.IsTrue(SameVfsUri(BackTarget, PathToFileUri(SrcDir)),
    'enter dir-link remembers target');
  ChildUri := PathToFileUri(TPath.Combine(SrcDir, 'deeper'));
  UpdateWorkspaceBackMarker(BackUri, BackTarget, PathToFileUri(SrcDir), ChildUri);
  Assert.IsTrue(SameVfsUri(BackUri, 'ws:///'), 'deeper folder keeps workspace back');
  UpdateWorkspaceBackMarker(BackUri, BackTarget, ChildUri, PathToFileUri(SrcDir));
  Assert.IsTrue(SameVfsUri(BackUri, 'ws:///'), 'return to link root keeps workspace back');
  UpdateWorkspaceBackMarker(BackUri, BackTarget, PathToFileUri(SrcDir),
    ParentFileUri(PathToFileUri(SrcDir)));
  Assert.IsTrue(BackUri = '', 'disk parent from link root clears marker');
  BackUri := '';
  BackTarget := '';
  UpdateWorkspaceBackMarker(BackUri, BackTarget, PathToFileUri(SrcDir),
    ParentFileUri(PathToFileUri(SrcDir)));
  Assert.IsTrue(BackUri = '', 'other panel never entered from ws');
  UpdateWorkspaceBackMarker(BackUri, BackTarget, 'ws:///', PathToFileUri(SrcDir));
  UpdateWorkspaceBackMarker(BackUri, BackTarget, PathToFileUri(SrcDir), 'ws:///');
  Assert.IsTrue(BackUri = '', 'return to workspace clears marker');

  WaitMkdir(Backend, 'ws:///group', VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'mkdir virtual folder: ' + VErr.Message);
  ExtraDir := TPath.Combine(WorkDir, 'nested-dir');
  TDirectory.CreateDirectory(ExtraDir);
  WaitCopy(Backend, PathToFileUri(ExtraDir), JoinVfsUri('ws:///group', 'nested-dir'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'link dir into virtual folder: ' + VErr.Message);
  Assert.IsTrue(SameVfsUri(WorkspaceParentUriForTarget(PathToFileUri(ExtraDir)), 'ws:///group'),
    'leaving nested linked dir returns to virtual folder');
  Rows := RowsFromVfsItems(PathToFileUri(ExtraDir), []);
  Assert.IsTrue(SameVfsUri(Rows[0].URI, ParentFileUri(PathToFileUri(ExtraDir))),
    '.. without enter-from-ws nested is disk parent');
  Rows := RowsFromVfsItems(PathToFileUri(ExtraDir), [], 'ws:///group');
  Assert.IsTrue(SameVfsUri(Rows[0].URI, 'ws:///group'),
    '.. after enter-from-ws nested is group');

  WaitCopy(Backend, SrcUri, JoinVfsUri('ws:///group', 'hello-ws.txt'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'link into virtual folder: ' + VErr.Message);
  WaitList(Backend, 'ws:///group', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list virtual folder: ' + VErr.Message);
  Assert.IsTrue(FindNamed(Items, 'hello-ws.txt', Entry), 'virtual folder contains the link');
  Assert.IsTrue(SameVfsUri(Entry.TargetURI, SrcUri), 'nested link still points at original');

  WaitDelete(Backend, SrcUri, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'unlink by targetUri: ' + VErr.Message);
  Assert.IsTrue(TFile.Exists(SrcTxt), 'unlink does not delete the real file');
  WaitList(Backend, 'ws:///', Items, VErr);
  Assert.IsTrue(not FindNamed(Items, 'hello-ws.txt', Entry), 'root file link removed');
  Assert.IsTrue(FindNamed(Items, 'ws-folder', Entry), 'dir link remains');
  WaitList(Backend, 'ws:///group', Items, VErr);
  Assert.IsTrue(not FindNamed(Items, 'hello-ws.txt', Entry),
    'nested link with same target is also removed');

  WaitDelete(Backend, 'ws:///', VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'clear workspace: ' + VErr.Message);
  WaitList(Backend, 'ws:///', Items, VErr);
  Assert.IsTrue(Length(Items) = 0, 'clear leaves an empty workspace');
  Assert.IsTrue(TDirectory.Exists(SrcDir), 'clear does not delete the real folder');
  Assert.IsTrue(TFile.Exists(TPath.Combine(SrcDir, 'inside.txt')),
    'real folder contents untouched');
  System.Writeln('OK: core workspace VFS');

  WasmPath := TPath.Combine(PluginSrcDir, 'plugin.wasm');
  JsonPath := TPath.Combine(PluginSrcDir, 'plugin.json');
  if FindWasmtimeDll = '' then
    Assert.Pass('SKIP: wasmtime.dll not found');
  if not TFile.Exists(WasmPath) then
    Assert.Pass('SKIP: plugin.wasm missing (cargo build --target wasm32-unknown-unknown --release)');
  Assert.IsTrue(TFile.Exists(JsonPath), 'plugin.json missing: ' + JsonPath);

  Loaded := 0;
  Failed := 0;
  Skipped := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      if AResult = plrLoaded then
        Inc(Loaded)
      else if AResult = plrSkippedNoRuntime then
        Inc(Skipped)
      else if AResult <> plrSkippedHelperDll then
        Inc(Failed);
      System.Writeln(Format('  [plugin] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
    end;

  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-ws-test');
  if TDirectory.Exists(PluginsRoot) then
    TDirectory.Delete(PluginsRoot, True);
  StagePlugin(PluginsRoot, WasmPath, JsonPath);
  PluginLoader.LoadPluginsFrom(PluginsRoot);
  Assert.IsTrue(Skipped = 0, 'workspace should not skip when wasmtime is loaded');
  Assert.IsTrue(Failed = 0, 'workspace WASM must load: see log');
  Assert.IsTrue(Loaded >= 1, 'workspace WASM should load');
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('ws:///'),
    'WASM must not steal the built-in ws:// scheme');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('ws:///', Backend), 'resolve ws URI after plugin');

  PluginLoader.UnloadAll;
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('ws:///'),
    'ws:// not plugin-owned after unload');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('ws:///', Backend),
    'built-in ws:// remains after plugin unload');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWorkspacePlugin);

end.
