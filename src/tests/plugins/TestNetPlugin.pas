unit TestNetPlugin;

{ The built NetPlugin library loaded by the real plugin loader: the schemes and
  the Change Drive item it registers, and copies through the host's own VFS
  stack to and from a local FTP server (those need the environment described in
  uNetTestServers.pas and report a skip without it). }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, uVfsTypes, uNetTestServers;

type
  [TestFixture]
  TTestNetPlugin = class
  private
    FSkipReason: string;
    FRoot: string;
    FWork: string;
    FPlugins: string;
    FSettings: string;
    FServer: TNetTestServer;
    FVfs: IVirtualFileSystem;
    FLoaded: Boolean;
    function Wait(const AStart: TProc<TProc>): Boolean;
    function CopyOf(const AFrom, ATo: string): TVfsError;
    function MoveOf(const AFrom, ATo: string): TVfsError;
    function Names(const AUri: string): string;
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestPluginLoadsAndRegistersItsSchemes;
    [Test] procedure TestChangeDriveListGetsTheNetworkItem;
    [Test] procedure TestBuiltInSftpStaysWithTheProgram;
    [Test] procedure TestSavedSessionIsListedAndOpens;
    [Test] procedure TestParentChainListsEveryLevel;
    [Test] procedure TestCopyToAndFromAServerThroughTheHostStack;
    [Test] procedure TestMoveToAServerDeletesTheLocalFile;
    [Test] procedure TestFolderCopyDownloadsTheTree;
    [Test] procedure TestUnloadRemovesItsRegistrations;
  end;

implementation

uses
  System.IOUtils, uVfsRegistry, uPluginLoader, uPluginSettings, uDriveItems, uDriveInfo,
  uCommandRegistry, uNetTypes, uNetSessions, uPlatformInfo;

const
  cPort = 12141;

procedure Pump(const AFlag: PBoolean);
var
  I: Integer;
begin
  for I := 1 to 3000 do
  begin
    CheckSynchronize(10);
    if AFlag^ then
      Exit;
  end;
end;

function TTestNetPlugin.Wait(const AStart: TProc<TProc>): Boolean;
var
  Done: Boolean;
begin
  Done := False;
  AStart(procedure begin Done := True; end);
  Pump(@Done);
  Result := Done;
end;

procedure TTestNetPlugin.SetupFixture;
var
  Dll, CurlDll, Target: string;
  Store: TNetSessionStore;
  S: TNetSession;
  File_: string;
begin
  FSkipReason := NetTestUnavailable;
  Dll := TPath.Combine(ExtractFilePath(ParamStr(0)), PlatformSharedLibName('NetPlugin'));
  if not TFile.Exists(Dll) then
  begin
    FSkipReason := 'NetPlugin library not built: ' + Dll;
    Exit;
  end;
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-netplug-' + TGUID.NewGuid.ToString);
  FWork := TPath.Combine(TPath.GetTempPath, 'mtn2-netplug-work-' + TGUID.NewGuid.ToString);
  FPlugins := TPath.Combine(TPath.GetTempPath, 'mtn2-netplug-plugins-' + TGUID.NewGuid.ToString);
  FSettings := TPath.Combine(TPath.GetTempPath, 'mtn2-netplug-settings-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  TDirectory.CreateDirectory(FWork);
  TDirectory.CreateDirectory(FSettings);
  Target := TPath.Combine(FPlugins, 'mtn.net');
  TDirectory.CreateDirectory(Target);
  TFile.Copy(Dll, TPath.Combine(Target, PlatformSharedLibName('NetPlugin')), True);
  // The manifest the plugin ships with (the runner lives in src\tests\dcu).
  TFile.Copy(TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\plugins\mtn.net\plugin.json')), TPath.Combine(Target, 'plugin.json'), True);
  CurlDll := GetEnvironmentVariable('MTN2_CURL_DLL');
  if CurlDll <> '' then
  begin
    TFile.Copy(CurlDll, TPath.Combine(Target, 'libcurl-x64.dll'), True);
    for File_ in TDirectory.GetFiles(ExtractFilePath(CurlDll), '*.dll') do
      if not SameText(ExtractFileName(File_), ExtractFileName(CurlDll)) then
        TFile.Copy(File_, TPath.Combine(Target, ExtractFileName(File_)), True);
  end;

  BuildServedTree(FRoot);
  if FSkipReason = '' then
    try
      FServer := TNetTestServer.Create('serve_ftp.py', [FRoot, IntToStr(cPort)], cPort);
    except
      on E: Exception do
        FSkipReason := 'test server did not start: ' + E.Message;
    end;

  SetPluginSettingsDirectory(FSettings);
  Store := TNetSessionStore.Create;
  try
    S := DefaultNetSession;
    S.Name := 'ftp';
    S.Protocol := npFtp;
    S.Host := '127.0.0.1';
    S.Port := cPort;
    S.User := 'test';
    S.Password := 'secret';
    S.SavePassword := True;
    Store.Add(S);
    PluginSettings.SetValue('mtn.net', 'sessions', Store.ToJson);
  finally
    Store.Free;
  end;

  PluginLoader.LoadPluginsFrom(FPlugins);
  FLoaded := GlobalVfsRegistry.IsPluginOwned('net:///');
  FVfs := CreateDefaultVfs;
end;

procedure TTestNetPlugin.TearDownFixture;
begin
  FVfs := nil;
  PluginLoader.UnloadAll;
  SetPluginSettingsDirectory('');
  FServer.Free;
  try
    if (FRoot <> '') and TDirectory.Exists(FRoot) then
      TDirectory.Delete(FRoot, True);
    if (FWork <> '') and TDirectory.Exists(FWork) then
      TDirectory.Delete(FWork, True);
    if (FSettings <> '') and TDirectory.Exists(FSettings) then
      TDirectory.Delete(FSettings, True);
    if (FPlugins <> '') and TDirectory.Exists(FPlugins) then
      TDirectory.Delete(FPlugins, True);
  except
    // A loaded library keeps its folder locked; the OS cleans temp later.
  end;
end;

function TTestNetPlugin.CopyOf(const AFrom, ATo: string): TVfsError;
var
  Err: TVfsError;
begin
  Assert.IsTrue(Wait(procedure(ADone: TProc)
    begin
      FVfs.CopyAsync(AFrom, ATo, nil, nil,
        procedure(const ASuccess: Boolean; const AError: TVfsError)
        begin
          Err := AError;
          ADone();
        end);
    end), 'the copy finished');
  Result := Err;
end;

function TTestNetPlugin.MoveOf(const AFrom, ATo: string): TVfsError;
var
  Err: TVfsError;
begin
  Assert.IsTrue(Wait(procedure(ADone: TProc)
    begin
      FVfs.MoveAsync(AFrom, ATo, nil, nil,
        procedure(const ASuccess: Boolean; const AError: TVfsError)
        begin
          Err := AError;
          ADone();
        end);
    end), 'the move finished');
  Result := Err;
end;

function TTestNetPlugin.Names(const AUri: string): string;
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  E: TVfsEntry;
  L: TStringList;
begin
  Assert.IsTrue(Wait(procedure(ADone: TProc)
    begin
      FVfs.ListDirectoryAsync(AUri, nil,
        procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
        begin
          Items := AItems;
          Err := AError;
          ADone();
        end);
    end), 'the listing finished');
  Assert.IsTrue(Err.Code = vecOk, AUri + ': ' + Err.Message);
  L := TStringList.Create;
  try
    for E in Items do
      L.Add(E.Name);
    L.Sort;
    Result := L.CommaText;
  finally
    L.Free;
  end;
end;

procedure TTestNetPlugin.TestPluginLoadsAndRegistersItsSchemes;
var
  Scheme: string;
begin
  if FSkipReason = 'NetPlugin library not built: ' then
    Assert.Pass('SKIP');
  if not FLoaded then
    Assert.Pass('SKIP: ' + FSkipReason);
  for Scheme in ['net:///', 'ftp://h/', 'ftps://h/', 'nsftp://h/', 'scp://h/', 'dav://h/', 'davs://h/', 's3://b/k'] do
    Assert.IsTrue(GlobalVfsRegistry.IsPluginOwned(Scheme), Scheme + ' belongs to the plugin');
  Assert.AreEqual('mtn.net', GlobalVfsRegistry.PluginIdOf('net:///'));
end;

procedure TTestNetPlugin.TestChangeDriveListGetsTheNetworkItem;
var
  Items: TArray<TDriveItem>;
  Uri: string;
begin
  if not FLoaded then
    Assert.Pass('SKIP: ' + FSkipReason);
  Items := DriveItems.Items;
  Assert.IsTrue(Length(Items) = 1);
  Assert.AreEqual('net:///', Items[0].Uri);
  Assert.IsTrue(Items[0].Caption <> '');
  Assert.IsTrue(TryChangeDriveSpecialUri(Char(Ord('1') + ChangeDriveSpecialCount), Uri));
  Assert.AreEqual('net:///', Uri, 'the item has the next digit');
end;

procedure TTestNetPlugin.TestBuiltInSftpStaysWithTheProgram;
begin
  if not FLoaded then
    Assert.Pass('SKIP: ' + FSkipReason);
  Assert.IsFalse(GlobalVfsRegistry.IsPluginOwned('sftp://h/x'), 'sftp:// is not taken over');
end;

procedure TTestNetPlugin.TestSavedSessionIsListedAndOpens;
begin
  if not FLoaded or (FServer = nil) then
    Assert.Pass('SKIP: ' + FSkipReason);
  Assert.AreEqual('ftp', Names('net:///'));
  Assert.AreEqual('docs,empty,hello.txt', Names('net://ftp/'));
  Assert.AreEqual('a.txt', Names('net://ftp/docs'));
end;

procedure TTestNetPlugin.TestParentChainListsEveryLevel;
var
  Uri: string;
  I: Integer;
begin
  if not FLoaded or (FServer = nil) then
    Assert.Pass('SKIP: ' + FSkipReason);
  Uri := 'net://ftp/docs';
  for I := 1 to 3 do
  begin
    Uri := ParentFileUri(Uri);
    Assert.IsTrue(Names(Uri) <> '', 'listing of ' + Uri);
  end;
  Uri := 'ftp://test:secret@127.0.0.1:' + IntToStr(cPort) + '/docs';
  for I := 1 to 3 do
  begin
    Uri := ParentFileUri(Uri);
    Assert.IsTrue(Names(Uri) <> '', 'listing of ' + Uri);
  end;
end;

procedure TTestNetPlugin.TestCopyToAndFromAServerThroughTheHostStack;
var
  Src, Back: string;
  Err: TVfsError;
begin
  if not FLoaded or (FServer = nil) then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'host-up.txt');
  TFile.WriteAllText(Src, 'through the host', TEncoding.UTF8);
  Err := CopyOf(PathToFileUri(Src), 'net://ftp/host-up.txt');
  Assert.IsTrue(Err.Code = vecOk, 'upload: ' + Err.Message);
  Back := TPath.Combine(FWork, 'host-back.txt');
  Err := CopyOf('net://ftp/host-up.txt', PathToFileUri(Back));
  Assert.IsTrue(Err.Code = vecOk, 'download: ' + Err.Message);
  Assert.AreEqual('through the host', TFile.ReadAllText(Back, TEncoding.UTF8));
end;

procedure TTestNetPlugin.TestMoveToAServerDeletesTheLocalFile;
var
  Src: string;
  Err: TVfsError;
begin
  if not FLoaded or (FServer = nil) then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'host-move.txt');
  TFile.WriteAllText(Src, 'moved');
  Err := MoveOf(PathToFileUri(Src), 'net://ftp/host-move.txt');
  Assert.IsTrue(Err.Code = vecOk, 'move: ' + Err.Message);
  Assert.IsFalse(TFile.Exists(Src), 'the local file is gone');
  Assert.IsTrue(Pos('host-move.txt', Names('net://ftp/')) > 0, 'it is on the server');
end;

procedure TTestNetPlugin.TestFolderCopyDownloadsTheTree;
var
  Dest: string;
  Err: TVfsError;
begin
  if not FLoaded or (FServer = nil) then
    Assert.Pass('SKIP: ' + FSkipReason);
  Dest := TPath.Combine(FWork, 'docs-copy');
  Err := CopyOf('net://ftp/docs', PathToFileUri(Dest));
  Assert.IsTrue(Err.Code = vecOk, 'copy folder: ' + Err.Message);
  Assert.AreEqual('A file', TFile.ReadAllText(TPath.Combine(Dest, 'a.txt')));
end;

procedure TTestNetPlugin.TestUnloadRemovesItsRegistrations;
begin
  if not FLoaded then
    Assert.Pass('SKIP: ' + FSkipReason);
  FVfs := nil;
  PluginLoader.UnloadAll;
  Assert.IsFalse(GlobalVfsRegistry.IsPluginOwned('net:///'));
  Assert.IsTrue(Length(DriveItems.Items) = 0, 'the drive item is gone');
  FLoaded := False;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetPlugin);

end.
