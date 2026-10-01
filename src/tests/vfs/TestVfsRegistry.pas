unit TestVfsRegistry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVfsRegistry = class
  public
    [Test] procedure TestClassify;
    [Test] procedure TestPluginOwnedAndUnload;
    [Test] procedure TestArchiveExtensions;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uTextEncoding,
  uVfsRegistry;

type
  TStubVfs = class(TInterfacedObject, IVirtualFileSystem)
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

procedure TStubVfs.ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsListCallback);
begin
end;

procedure TStubVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TStubVfs.CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TStubVfs.CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
end;

procedure TStubVfs.MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
end;

procedure TStubVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
end;

procedure TStubVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
end;

procedure TStubVfs.WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
end;

procedure TStubVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
end;

procedure TStubVfs.GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsFreeSpaceCallback);
begin
end;

procedure TestClassify;
var
  Reason: string;
begin
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'file:///C:/b', False,
    False, False, False, Reason) = vtrFile, 'file copy');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'file:///C:/b', False,
    False, False, False, Reason) = vtrZip, 'archive copy');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'file:///C:/b', True,
    False, False, False, Reason) = vtrNotSupported, 'archive move');
  Assert.IsTrue(ClassifyVfsTransfer('find://session/1/', 'file:///C:/b', False,
    False, False, False, Reason) = vtrNotSupported, 'find copy');
  Assert.IsTrue(ClassifyVfsTransfer('sample://a', 'sample://b', False,
    True, True, True, Reason) = vtrPluginBackend, 'same-plugin copy');
  Assert.IsTrue(ClassifyVfsTransfer('sample://a', 'file:///C:/b', False,
    True, False, False, Reason) = vtrPluginExtract, 'plugin to file');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'sample://b', False,
    False, True, False, Reason) = vtrPluginDest, 'file to plugin dest');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'sample://b', True,
    False, True, False, Reason) = vtrNotSupported, 'move to plugin dest');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'ws:///', False,
    False, False, False, Reason) = vtrPluginDest, 'file to workspace');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'ws:///', True,
    False, False, False, Reason) = vtrNotSupported, 'move to workspace');
  Assert.IsTrue(ClassifyVfsTransfer('7z:///C:/a.7z!/x', 'file:///C:/b', False,
    False, False, False, Reason) = vtrNotSupported, '7z without plugin');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrSftp, 'file to sftp copy');
  Assert.IsTrue(ClassifyVfsTransfer('sftp://u@h/a', 'file:///C:/b', False,
    False, False, False, Reason) = vtrSftp, 'sftp to file copy');
  Assert.IsTrue(ClassifyVfsTransfer('sftp://u@h/a', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrSftp, 'sftp to sftp copy');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a', 'sftp://u@h/b', True,
    False, False, False, Reason) = vtrSftp, 'file to sftp move');
  Assert.IsTrue(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrNotSupported, 'archive to sftp');
end;

procedure TestPluginOwnedAndUnload;
var
  Reg: TVfsRegistry;
  Stub: IVirtualFileSystem;
  Backend: IVirtualFileSystem;
begin
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('ws:///', Backend), 'built-in ws scheme');
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('ws:///'), 'built-in ws is not plugin-owned');
  Reg := TVfsRegistry.Create;
  Stub := TStubVfs.Create;
  try
    Assert.IsTrue(not Reg.IsPluginOwned('sample://x'), 'empty registry');
    Reg.RegisterPluginScheme('demo', 'sample', Stub, 50);
    Assert.IsTrue(Reg.IsPluginOwned('sample://x'), 'sample is plugin-owned');
    Assert.IsTrue(not Reg.IsPluginOwned('file:///C:/'), 'file is not plugin-owned');
    Reg.UnregisterPlugin('demo');
    Assert.IsTrue(not Reg.IsPluginOwned('sample://x'), 'unregistered');
    Reg.UnregisterPlugin('demo'); // idempotent
  finally
    Reg.Free;
  end;
end;

procedure TestArchiveExtensions;
var
  Reg: TVfsRegistry;
  Kind: TArchiveExtensionKind;
begin
  // Built-ins on the process-wide registry: always present, never plugin-owned.
  Assert.IsTrue(GlobalVfsRegistry.TryResolveArchiveKind('pack.zip', Kind) and (Kind = akZipChain),
    'built-in .zip resolves to akZipChain');
  Assert.IsTrue(GlobalVfsRegistry.TryResolveArchiveKind('App.jar', Kind) and (Kind = akZipChain),
    'built-in .jar is case-insensitive');
  Assert.IsTrue(not GlobalVfsRegistry.TryResolveArchiveKind('readme.txt', Kind),
    'unregistered extension does not resolve');
  Assert.IsTrue(not GlobalVfsRegistry.TryResolveArchiveKind('noext', Kind),
    'extension-less name does not resolve');

  Reg := TVfsRegistry.Create;
  try
    Assert.IsTrue(not Reg.TryResolveArchiveKind('pack.7z', Kind), 'fresh registry has no .7z');
    Reg.RegisterArchiveExtension('mtn.7z', '7z', akSevenZip, 100);
    Assert.IsTrue(Reg.TryResolveArchiveKind('pack.7z', Kind) and (Kind = akSevenZip),
      'plugin-declared .7z resolves to akSevenZip');
    Reg.UnregisterPlugin('mtn.7z');
    Assert.IsTrue(not Reg.TryResolveArchiveKind('pack.7z', Kind),
      'unloading the plugin drops its archive extensions');
    Reg.UnregisterPlugin('mtn.7z'); // idempotent
  finally
    Reg.Free;
  end;
end;

{ TTestVfsRegistry }

procedure TTestVfsRegistry.TestClassify;
begin
  TestVfsRegistry.TestClassify;
end;

procedure TTestVfsRegistry.TestPluginOwnedAndUnload;
begin
  TestVfsRegistry.TestPluginOwnedAndUnload;
end;

procedure TTestVfsRegistry.TestArchiveExtensions;
begin
  TestVfsRegistry.TestArchiveExtensions;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVfsRegistry);

end.
