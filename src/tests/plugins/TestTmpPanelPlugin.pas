unit TestTmpPanelPlugin;

{ Loads TmpPanelPlugin.dll, copies a real file onto tmp:///, lists it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTmpPanelPlugin = class
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
  uDualPanelOverlays,
  uTopMenuBar,
  uMenuRegistry,
  uMessageBus,
  uPluginHostAbi,
  uVfsCdeclAdapter,
  uPluginLoader;

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

procedure StagePlugin(const APluginsRoot, APluginDll: string);
var
  DestDir: string;
begin
  DestDir := TPath.Combine(APluginsRoot, 'mtn.tmp');
  TDirectory.CreateDirectory(DestDir);
  TFile.Copy(APluginDll, TPath.Combine(DestDir, 'TmpPanelPlugin.dll'), True);
  TFile.WriteAllText(TPath.Combine(DestDir, 'plugin.json'),
    '{"id":"mtn.tmp","name":"Temporary panel","version":"0.1.0","abi":1}', TEncoding.UTF8);
end;

var
  PluginDll, PluginsRoot, WorkDir, SrcTxt, SrcUri: string;
  Loaded, Failed, I: Integer;
  Backend: IVirtualFileSystem;
  Items: TArray<TVfsEntry>;
  VErr: TVfsError;
  Found: Boolean;

{ TTestTmpPanelPlugin }

procedure TTestTmpPanelPlugin.Run;
begin
  PluginDll := TPath.Combine(ExtractFilePath(ParamStr(0)), 'TmpPanelPlugin.dll');
  if not TFile.Exists(PluginDll) then
    raise Exception.Create('TmpPanelPlugin.dll not found: ' + PluginDll);

  WorkDir := TPath.Combine(TPath.GetTempPath, 'mtn2-tmp-plugin');
  TDirectory.CreateDirectory(WorkDir);
  SrcTxt := TPath.Combine(WorkDir, 'hello-tmp.txt');
  TFile.WriteAllText(SrcTxt, 'tmp-panel', TEncoding.UTF8);
  SrcUri := PathToFileUri(SrcTxt);

  Loaded := 0;
  Failed := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      if AResult = plrLoaded then
        Inc(Loaded)
      else if AResult <> plrSkippedHelperDll then
        Inc(Failed);
      System.Writeln(Format('  [plugin] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
    end;

  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-tmp-test');
  if TDirectory.Exists(PluginsRoot) then
    TDirectory.Delete(PluginsRoot, True);
  StagePlugin(PluginsRoot, PluginDll);
  PluginLoader.LoadPluginsFrom(PluginsRoot);
  Assert.IsTrue(Loaded >= 1, 'TmpPanelPlugin should load');
  Assert.IsTrue(Failed = 0, 'tmp plugin must not fail the loader');
  Assert.IsTrue(IsTmpPanelUri('tmp:///'), 'tmp:/// is tmp panel');
  Assert.IsTrue(not IsTmpPanelUri('file:///C:/'), 'file is not tmp');
  Assert.IsTrue(FileUriToPath('tmp:///') = '', 'tmp URI has no local path');
  Assert.IsTrue(JoinVfsUri('tmp:///', 'x.txt') = 'tmp:///', 'tmp join is flat');
  Assert.IsTrue(VfsUriTitle('tmp:///') = 'Temporary', 'tmp title');
  Assert.IsTrue(SameVfsUri('tmp:///', 'tmp://foo'), 'tmp URIs compare as one root');
  Assert.IsTrue(GlobalVfsRegistry.IsPluginOwned('tmp:///'), 'tmp:// is plugin-owned');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('tmp:///', Backend), 'resolve tmp URI');

  WaitList(Backend, 'tmp:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'empty list ok: ' + VErr.Message);

  WaitCopy(Backend, SrcUri, 'tmp:///', VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'copy onto tmp: ' + VErr.Message);

  WaitList(Backend, 'tmp:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list after copy: ' + VErr.Message);
  Found := False;
  for I := 0 to High(Items) do
    if SameText(Items[I].Name, 'hello-tmp.txt') then
    begin
      Found := True;
      Assert.IsTrue(Items[I].TargetURI <> '', 'targetUri points at real file');
    end;
  Assert.IsTrue(Found, 'listing contains hello-tmp.txt');

  SrcTxt := TPath.Combine(WorkDir, 'second-tmp.txt');
  TFile.WriteAllText(SrcTxt, 'tmp-2', TEncoding.UTF8);
  WaitCopy(Backend, PathToFileUri(SrcTxt), 'tmp:///', VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'copy second file: ' + VErr.Message);
  WaitDelete(Backend, SrcUri, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'F7-remove one ref: ' + VErr.Message);
  WaitList(Backend, 'tmp:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list after remove: ' + VErr.Message);
  Assert.IsTrue(Length(Items) = 1, 'one ref remains after remove');
  Assert.IsTrue(SameText(Items[0].Name, 'second-tmp.txt'), 'remaining ref is second file');
  Assert.IsTrue(TFile.Exists(TPath.Combine(WorkDir, 'hello-tmp.txt')),
    'F7-remove does not delete the real file');

  WaitDelete(Backend, 'tmp:///', VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'clear tmp list: ' + VErr.Message);
  WaitList(Backend, 'tmp:///', Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list after clear: ' + VErr.Message);
  Assert.IsTrue(Length(Items) = 0, 'clear leaves an empty tmp panel');

  PluginLoader.UnloadAll;
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('tmp:///'),
    'tmp:// not plugin-owned after unload');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTmpPanelPlugin);

end.
