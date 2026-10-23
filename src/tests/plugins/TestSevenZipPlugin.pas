unit TestSevenZipPlugin;

{ Loads the SevenZipPlugin library and its archive engine, packs a tiny archive,
  then lists and reads it via the host VFS registry. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipPlugin = class
  public
    [Test] procedure Run;
    [Test] procedure TestZipOverrideOnlyWhenAllowed;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, System.TypInfo,
  uPlatformInfo, uPlatformPaths, uPlatformProcess,
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
  uPluginLoader,
  uSevenZipApi,
  System.Zip;

function Find7zDll: string;
const
  Candidates: array[0..2] of string = (
    'C:\Program Files\7-Zip\7z.dll',
    'C:\Program Files\Far Manager\Plugins\ArcLite\7z.dll',
    'C:\Program Files (x86)\7-Zip\7z.dll'
  );
var
  Env, NextTo: string;
  I: Integer;
begin
  if PlatformPosixPaths then
    Exit(PlatformSevenZipEngine(''));
  Env := GetEnvironmentVariable('MTN2_7Z_DLL');
  if (Env <> '') and TFile.Exists(Env) then
    Exit(Env);
  NextTo := TPath.Combine(ExtractFilePath(ParamStr(0)), '7z.dll');
  if TFile.Exists(NextTo) then
    Exit(NextTo);
  for I := Low(Candidates) to High(Candidates) do
    if TFile.Exists(Candidates[I]) then
      Exit(Candidates[I]);
  Result := '';
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
    Tick := TThread.GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if TThread.GetTickCount - Tick > 15000 then
        raise Exception.Create('ListDirectoryAsync timed out');
    end;
    CheckSynchronize;
    AItems := Items;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitBytes(const AVfs: IVirtualFileSystem; const AURI: string;
  out ABytes: TBytes; out AErr: TVfsError);
var
  Ev: TEvent;
  Data: TBytes;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.ReadBytesAsync(AURI, 1024, nil,
      procedure(const AData: TBytes; const AReadErr: TVfsError)
      begin
        Data := AData;
        Err := AReadErr;
        Ev.SetEvent;
      end);
    Tick := TThread.GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if TThread.GetTickCount - Tick > 15000 then
        raise Exception.Create('ReadBytesAsync timed out');
    end;
    CheckSynchronize;
    ABytes := Data;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitCopy(const AVfs: IVirtualFileSystem; const AFrom, ATo: string;
  AOverwrite: Boolean; out AErr: TVfsError);
var
  Ev: TEvent;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.CopyAsync(AFrom, ATo, nil, nil,
      procedure(const AOk: Boolean; const ACopyErr: TVfsError)
      begin
        Err := ACopyErr;
        if AOk and (Err.Code = vecOk) then
          Err := TVfsError.Ok;
        Ev.SetEvent;
      end, AOverwrite);
    Tick := TThread.GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if TThread.GetTickCount - Tick > 15000 then
        raise Exception.Create('CopyAsync timed out');
    end;
    CheckSynchronize;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

procedure WaitDelete(const AVfs: IVirtualFileSystem; const AURI: string;
  out AErr: TVfsError);
var
  Ev: TEvent;
  Err: TVfsError;
  Tick: Cardinal;
begin
  Ev := TEvent.Create(nil, True, False, '');
  try
    AVfs.DeleteAsync(AURI, vdmPermanent, nil, nil,
      procedure(const AOk: Boolean; const ADelErr: TVfsError)
      begin
        Err := ADelErr;
        if AOk and (Err.Code = vecOk) then
          Err := TVfsError.Ok;
        Ev.SetEvent;
      end);
    Tick := TThread.GetTickCount;
    while Ev.WaitFor(50) <> wrSignaled do
    begin
      CheckSynchronize;
      if TThread.GetTickCount - Tick > 15000 then
        raise Exception.Create('DeleteAsync timed out');
    end;
    CheckSynchronize;
    AErr := Err;
  finally
    Ev.Free;
  end;
end;

function ListHas(const AItems: TArray<TVfsEntry>; const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(AItems) do
    if SameText(AItems[I].Name, AName) then
      Exit(True);
end;

// 7z.dll sits next to the plugin; a 7-Zip program is found in the search path.
procedure StageEngine(const ADestDir, AEngine: string);
begin
  if SameText(ExtractFileExt(AEngine), '.dll') then
    TFile.Copy(AEngine, TPath.Combine(ADestDir, '7z.dll'), True);
end;

procedure StagePlugin(const APluginsRoot, A7zDll, APluginDll: string);
var
  DestDir: string;
begin
  DestDir := TPath.Combine(APluginsRoot, 'mtn.7z');
  TDirectory.CreateDirectory(DestDir);
  TFile.Copy(APluginDll, TPath.Combine(DestDir, PlatformSharedLibName('SevenZipPlugin')), True);
  StageEngine(DestDir, A7zDll);
  TFile.WriteAllText(TPath.Combine(DestDir, 'plugin.json'),
    '{"id":"mtn.7z","name":"7-Zip archives","version":"0.1.0","abi":1}', TEncoding.UTF8);
end;

var
  Dll7z, PluginDll, PluginsRoot, WorkDir, SrcTxt, ArcPath, Uri, Err, OutFile,
  PackedSrc, PackedArc, RenamedArc, DelDir, DelArc, DelRoot, DelName: string;
  Loaded, Failed: Integer;
  Backend, HostVfs: IVirtualFileSystem;
  Items: TArray<TVfsEntry>;
  VErr: TVfsError;
  Data: TBytes;
  Listed: TArray<T7zItem>;
  I: Integer;
  Found: Boolean;

{ TTestSevenZipPlugin }

procedure TTestSevenZipPlugin.Run;
begin
  Dll7z := Find7zDll;
  if Dll7z = '' then
    Assert.Pass('SKIP: no 7-Zip engine (7z.dll: set MTN2_7Z_DLL or install 7-Zip; POSIX: install 7zip or p7zip-full)');
  PluginDll := TPath.Combine(ExtractFilePath(ParamStr(0)), PlatformSharedLibName('SevenZipPlugin'));
  if not TFile.Exists(PluginDll) then
    raise Exception.Create('The SevenZipPlugin library is not next to the test exe: ' + PluginDll);

  WorkDir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-plugin');
  TDirectory.CreateDirectory(WorkDir);
  SrcTxt := TPath.Combine(WorkDir, 'hello.txt');
  ArcPath := TPath.Combine(WorkDir, 'hello.7z');
  TFile.WriteAllText(SrcTxt, 'hello-mtn2', TEncoding.UTF8);
  Assert.IsTrue(SevenZipLoadEngine(Dll7z), 'load the engine for the fixture');
  Assert.IsTrue(SevenZipCreateSimpleArchive(ArcPath, SrcTxt, Err), 'create fixture: ' + Err);
  Found := False;
  Assert.IsTrue(SevenZipListArchive(ArcPath, Listed, Err), 'in-process list: ' + Err);
  for I := 0 to High(Listed) do
    if SameText(ExtractFileName(Listed[I].Path), 'hello.txt') then
      Found := True;
  Assert.IsTrue(Found, 'in-process listing contains hello.txt');
  SevenZipUnloadEngine;

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

  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-7z-test');
  if TDirectory.Exists(PluginsRoot) then
    TDirectory.Delete(PluginsRoot, True);
  StagePlugin(PluginsRoot, Dll7z, PluginDll);
  PluginLoader.LoadPluginsFrom(PluginsRoot);
  Assert.IsTrue(Loaded >= 1, 'SevenZipPlugin should load');
  Assert.IsTrue(Failed = 0, 'the engine must not fail the loader');
  Assert.IsTrue(GlobalVfsRegistry.IsPluginOwned('7z:///C:/x.7z!/'), '7z:// is plugin-owned');
  Assert.IsTrue(PluginLoader.TrySetSecret('mtn.7z', ArcPath, ''), 'set_secret export');
  Assert.IsTrue(PluginLoader.TryClearSecret('mtn.7z', ArcPath), 'clear secret');

  Uri := PathToSevenZipRootUri(ArcPath);
  Assert.IsTrue(GlobalVfsRegistry.TryResolve(Uri, Backend), 'resolve 7z URI');
  WaitList(Backend, Uri, Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list ok: ' + VErr.Message);
  Found := False;
  for I := 0 to High(Items) do
    if SameText(Items[I].Name, 'hello.txt') then
      Found := True;
  Assert.IsTrue(Found, 'listing contains hello.txt');

  WaitBytes(Backend, JoinVfsUri(Uri, 'hello.txt'), Data, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'read ok: ' + VErr.Message);
  Assert.IsTrue(TEncoding.UTF8.GetString(Data).Contains('hello-mtn2'), 'payload');

  OutFile := TPath.Combine(WorkDir, 'extracted-hello.txt');
  if TFile.Exists(OutFile) then
    TFile.Delete(OutFile);
  HostVfs := CreateDefaultVfs;
  WaitCopy(HostVfs, JoinVfsUri(Uri, 'hello.txt'), PathToFileUri(OutFile),
    False, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'F5 extract 7z→file: ' + VErr.Message);
  Assert.IsTrue(TFile.Exists(OutFile), 'extracted file exists');
  Assert.IsTrue(TFile.ReadAllText(OutFile, TEncoding.UTF8).Contains('hello-mtn2'),
    'extracted payload');
  WaitCopy(HostVfs, JoinVfsUri(Uri, 'hello.txt'), PathToFileUri(OutFile),
    False, VErr);
  Assert.IsTrue(VErr.Code = vecAlreadyExists, 'extract without overwrite keeps dest');
  WaitCopy(HostVfs, JoinVfsUri(Uri, 'hello.txt'), PathToFileUri(OutFile),
    True, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'extract overwrite: ' + VErr.Message);

  PackedSrc := TPath.Combine(WorkDir, 'pack-me.txt');
  PackedArc := TPath.Combine(WorkDir, 'packed.7z');
  TFile.WriteAllText(PackedSrc, 'packed-payload', TEncoding.UTF8);
  if TFile.Exists(PackedArc) then
    TFile.Delete(PackedArc);
  WaitCopy(HostVfs, PathToFileUri(PackedSrc),
    JoinVfsUri(PathToSevenZipRootUri(PackedArc), 'pack-me.txt'), False, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'pack file→7z://: ' + VErr.Message);
  WaitList(HostVfs, PathToSevenZipRootUri(PackedArc), Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list packed archive: ' + VErr.Message);
  Found := False;
  for I := 0 to High(Items) do
    if SameText(Items[I].Name, 'pack-me.txt') then
      Found := True;
  Assert.IsTrue(Found, 'packed archive contains pack-me.txt');
  WaitCopy(HostVfs, PathToFileUri(PackedSrc),
    JoinVfsUri(PathToSevenZipRootUri(PackedArc), 'pack-me.txt'), False, VErr);
  Assert.IsTrue(VErr.Code = vecAlreadyExists, 'pack without overwrite keeps dest');
  WaitCopy(HostVfs, PathToFileUri(PackedSrc),
    JoinVfsUri(PathToSevenZipRootUri(PackedArc), 'pack-me.txt'), True, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'pack overwrite: ' + VErr.Message);

  // An archive whose extension is not .7z is still updated in place.
  RenamedArc := TPath.Combine(WorkDir, 'renamed.7z2');
  TFile.Copy(PackedArc, RenamedArc, True);
  WaitCopy(HostVfs, PathToFileUri(SrcTxt),
    JoinVfsUri(PathToSevenZipRootUri(RenamedArc), 'added.txt'), False, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'pack into an archive with another extension: ' + VErr.Message);
  WaitList(HostVfs, PathToSevenZipRootUri(RenamedArc), Items, VErr);
  Assert.IsTrue(ListHas(Items, 'added.txt') and ListHas(Items, 'pack-me.txt'),
    'the old and the new entry are both there');

  // Delete from an existing archive: a file, then a packed folder; the rest
  // of the archive stays readable.
  DelDir := TPath.Combine(WorkDir, 'del-src');
  TDirectory.CreateDirectory(TPath.Combine(DelDir, 'sub'));
  TFile.WriteAllText(TPath.Combine(DelDir, 'keep.txt'), 'keep-payload', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(DelDir, 'drop.txt'), 'drop-payload', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(DelDir, 'sub', 'inner.txt'), 'inner-payload', TEncoding.UTF8);
  DelArc := TPath.Combine(WorkDir, 'delete.7z');
  if TFile.Exists(DelArc) then
    TFile.Delete(DelArc);
  DelRoot := PathToSevenZipRootUri(DelArc);
  for DelName in ['keep.txt', 'drop.txt'] do
  begin
    WaitCopy(HostVfs, PathToFileUri(TPath.Combine(DelDir, DelName)),
      JoinVfsUri(DelRoot, DelName), True, VErr);
    Assert.IsTrue(VErr.Code = vecOk, 'pack ' + DelName + ': ' + VErr.Message);
  end;
  WaitCopy(HostVfs, PathToFileUri(TPath.Combine(DelDir, 'sub')),
    JoinVfsUri(DelRoot, 'sub'), True, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'pack folder: ' + VErr.Message);

  WaitDelete(HostVfs, JoinVfsUri(DelRoot, 'drop.txt'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'delete file from 7z: ' + VErr.Message);
  WaitList(HostVfs, DelRoot, Items, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'list after delete: ' + VErr.Message);
  Assert.IsFalse(ListHas(Items, 'drop.txt'), 'deleted file is gone');
  Assert.IsTrue(ListHas(Items, 'keep.txt'), 'other file stays');
  Assert.IsTrue(ListHas(Items, 'sub'), 'folder stays');
  WaitBytes(HostVfs, JoinVfsUri(DelRoot, 'keep.txt'), Data, VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'read kept file: ' + VErr.Message);
  Assert.IsTrue(TEncoding.UTF8.GetString(Data).Contains('keep-payload'), 'kept payload intact');

  WaitDelete(HostVfs, JoinVfsUri(DelRoot, 'sub'), VErr);
  Assert.IsTrue(VErr.Code = vecOk, 'delete folder from 7z: ' + VErr.Message);
  WaitList(HostVfs, DelRoot, Items, VErr);
  Assert.IsFalse(ListHas(Items, 'sub'), 'deleted folder is gone');
  Assert.IsTrue(ListHas(Items, 'keep.txt'), 'file stays after folder delete');

  WaitDelete(HostVfs, JoinVfsUri(DelRoot, 'missing.txt'), VErr);
  Assert.IsTrue(VErr.Code = vecNotFound, 'deleting a missing entry reports not found');

  PluginLoader.UnloadAll;
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('7z:///C:/x.7z!/'),
    '7z:// not plugin-owned after unload');
end;

procedure TTestSevenZipPlugin.TestZipOverrideOnlyWhenAllowed;
var
  Dll, DllPath, Root, Work, ZipPath, ZipScheme: string;
  Kind: TArchiveExtensionKind;
  ZipBackend: IVirtualFileSystem;
  Entries: TArray<TVfsEntry>;
  ListErr: TVfsError;
  Zip: TZipFile;
  HasInside: Boolean;
  N: Integer;
begin
  Dll := Find7zDll;
  if Dll = '' then
    Assert.Pass('SKIP: no 7-Zip engine (7z.dll: set MTN2_7Z_DLL or install 7-Zip; POSIX: install 7zip or p7zip-full)');
  DllPath := TPath.Combine(ExtractFilePath(ParamStr(0)), PlatformSharedLibName('SevenZipPlugin'));
  if not TFile.Exists(DllPath) then
    raise Exception.Create('The SevenZipPlugin library is not next to the test exe: ' + DllPath);

  Work := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-zip-override');
  TDirectory.CreateDirectory(Work);
  ZipPath := TPath.Combine(Work, 'sample.zip');
  if TFile.Exists(ZipPath) then
    TFile.Delete(ZipPath);
  TFile.WriteAllText(TPath.Combine(Work, 'inside.txt'), 'zip-payload', TEncoding.UTF8);
  Zip := TZipFile.Create;
  try
    Zip.Open(ZipPath, zmWrite);
    Zip.Add(TPath.Combine(Work, 'inside.txt'), 'inside.txt');
    Zip.Close;
  finally
    Zip.Free;
  end;

  // The manifest that ships with the plugin: it asks to replace .zip.
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-7z-override');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  TDirectory.CreateDirectory(TPath.Combine(Root, 'mtn.7z'));
  TFile.Copy(DllPath, TPath.Combine(Root, NativePath('mtn.7z/' + PlatformSharedLibName('SevenZipPlugin'))), True);
  StageEngine(TPath.Combine(Root, 'mtn.7z'), Dll);
  TFile.Copy(ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../plugins/mtn.7z/plugin.json'))), TPath.Combine(Root, NativePath('mtn.7z/plugin.json')), True);
  try
    PluginLoader.SetOverrideAllowList([]);
    PluginLoader.LoadPluginsFrom(Root);
    Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 1, 'mtn.7z loads');
    Assert.IsTrue(GlobalVfsRegistry.TryResolveArchive('sample.zip', Kind, ZipScheme) and
      (Kind = akZipChain), 'without the user''s permission .zip stays with the built-in module');
    Assert.IsTrue(GlobalVfsRegistry.TryResolveArchive('sample.7z', Kind, ZipScheme) and
      (Kind = akPluginScheme) and (ZipScheme = '7z'), '.7z goes to the plugin');
    PluginLoader.UnloadAll;

    PluginLoader.SetOverrideAllowList(['mtn.7z']);
    PluginLoader.LoadPluginsFrom(Root);
    Assert.IsTrue(GlobalVfsRegistry.TryResolveArchive('sample.zip', Kind, ZipScheme) and
      (Kind = akPluginScheme) and (ZipScheme = '7z'), 'with permission .zip goes to the plugin');
    Assert.IsTrue(GlobalVfsRegistry.TryResolve(PathToArchiveRootUri(ZipScheme, ZipPath), ZipBackend),
      'the plugin serves the archive root URI');
    WaitList(ZipBackend, PathToArchiveRootUri(ZipScheme, ZipPath), Entries, ListErr);
    Assert.IsTrue(ListErr.Code = vecOk, 'list the zip through the plugin: ' + ListErr.Message);
    HasInside := False;
    for N := 0 to High(Entries) do
      if SameText(Entries[N].Name, 'inside.txt') then
        HasInside := True;
    Assert.IsTrue(HasInside, 'the plugin lists the content of the zip');
    PluginLoader.UnloadAll;
    Assert.IsTrue(GlobalVfsRegistry.TryResolveArchive('sample.zip', Kind, ZipScheme) and
      (Kind = akZipChain), 'unloading the plugin gives .zip back to the built-in module');
  finally
    PluginLoader.UnloadAll;
    PluginLoader.SetOverrideAllowList([]);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSevenZipPlugin);

end.
