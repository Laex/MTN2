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
    [Test] procedure TestReservedSchemesCannotBePlugged;
    [Test] procedure TestPluginCannotTakeBuiltInSchemeWithoutGrant;
    [Test] procedure TestGrantedOverrideReplacesBuiltInScheme;
    [Test] procedure TestArchiveExtensionOverride;
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
    Reg.RegisterArchiveExtension('mtn.7z', '7z', akPluginScheme, 100);
    Assert.IsTrue(Reg.TryResolveArchiveKind('pack.7z', Kind) and (Kind = akPluginScheme),
      'plugin-declared .7z resolves to akPluginScheme');
    Reg.UnregisterPlugin('mtn.7z');
    Assert.IsTrue(not Reg.TryResolveArchiveKind('pack.7z', Kind),
      'unloading the plugin drops its archive extensions');
    Reg.UnregisterPlugin('mtn.7z'); // idempotent
  finally
    Reg.Free;
  end;
end;

procedure TestReservedSchemesCannotBePlugged;
var
  Reg: TVfsRegistry;
  Scheme: string;
begin
  Reg := TVfsRegistry.Create;
  try
    for Scheme in ['file', 'sys', 'recycle', 'find', 'ws', 'FILE'] do
    begin
      Reg.GrantOverrides('p', [Scheme]);
      Reg.RegisterPluginScheme('p', Scheme, TStubVfs.Create, 1);
      Assert.IsTrue(not Reg.IsPluginOwned(Scheme + '://x'),
        Scheme + ' stays with the host even with a grant');
      Assert.IsTrue(not Reg.IsOverrideGranted('p', Scheme),
        Scheme + ' cannot be granted');
    end;
  finally
    Reg.Free;
  end;
end;

procedure TestPluginCannotTakeBuiltInSchemeWithoutGrant;
var
  Reg: TVfsRegistry;
  Builtin, Hijack, Resolved: IVirtualFileSystem;
begin
  Reg := TVfsRegistry.Create;
  Builtin := TStubVfs.Create;
  Hijack := TStubVfs.Create;
  try
    Reg.RegisterScheme('sftp', Builtin, 15);
    Reg.RegisterPluginScheme('p', 'sftp', Hijack, 1);
    Assert.IsTrue(Reg.TryResolve('sftp://h/x', Resolved) and (Resolved = Builtin),
      'built-in sftp wins over an ungranted plugin asking for priority 1');
    Assert.IsTrue(not Reg.IsPluginOwned('sftp://h/x'), 'sftp is not plugin-owned');
  finally
    Reg.Free;
  end;
end;

procedure TestGrantedOverrideReplacesBuiltInScheme;
var
  Reg: TVfsRegistry;
  Builtin, Replacement, Resolved: IVirtualFileSystem;
begin
  Reg := TVfsRegistry.Create;
  Builtin := TStubVfs.Create;
  Replacement := TStubVfs.Create;
  try
    Reg.RegisterScheme('sftp', Builtin, 15);
    Reg.GrantOverrides('p', ['SFTP']);
    Assert.IsTrue(Reg.IsOverrideGranted('p', 'sftp'), 'grant is case-insensitive');
    Assert.IsTrue(not Reg.IsOverrideGranted('other', 'sftp'), 'grant is per plugin');
    Reg.RegisterPluginScheme('p', 'sftp', Replacement, 100);
    Assert.IsTrue(Reg.TryResolve('sftp://h/x', Resolved) and (Resolved = Replacement),
      'granted plugin replaces the built-in scheme');
    Assert.IsTrue(Reg.IsPluginOwned('sftp://h/x'), 'sftp is plugin-owned while granted');
    Reg.UnregisterPlugin('p');
    Assert.IsTrue(Reg.TryResolve('sftp://h/x', Resolved) and (Resolved = Builtin),
      'unloading the plugin restores the built-in scheme');
    Assert.IsTrue(not Reg.IsOverrideGranted('p', 'sftp'), 'unload drops the grant');
    Reg.RegisterPluginScheme('p', 'sftp', Replacement, 1);
    Assert.IsTrue(Reg.TryResolve('sftp://h/x', Resolved) and (Resolved = Builtin),
      'a reloaded plugin needs a new grant');
  finally
    Reg.Free;
  end;
end;

procedure TestArchiveExtensionOverride;
var
  Reg: TVfsRegistry;
  Kind: TArchiveExtensionKind;
  Scheme: string;
begin
  Reg := TVfsRegistry.Create;
  try
    Reg.RegisterArchiveExtension('', '.zip', akZipChain, 50);
    Reg.RegisterArchiveExtension('p', '.zip', akPluginScheme, 1, 'zipx');
    Assert.IsTrue(Reg.TryResolveArchive('a.zip', Kind, Scheme) and (Kind = akZipChain),
      'ungranted plugin does not take .zip');
    Reg.UnregisterPlugin('p');
    Reg.GrantOverrides('p', ['.zip']);
    Reg.RegisterArchiveExtension('p', 'zip', akPluginScheme, 100, 'ZipX');
    Assert.IsTrue(Reg.TryResolveArchive('a.ZIP', Kind, Scheme) and
      (Kind = akPluginScheme) and (Scheme = 'zipx'),
      'granted plugin takes .zip and navigates into its scheme');
    Reg.UnregisterPlugin('p');
    Assert.IsTrue(Reg.TryResolveArchive('a.zip', Kind, Scheme) and (Kind = akZipChain)
      and (Scheme = ''), 'built-in .zip is back after unload');
    Reg.RegisterArchiveExtension('q', '.7z', akPluginScheme);
    Assert.IsTrue(Reg.TryResolveArchive('a.7z', Kind, Scheme) and (Scheme = '7z'),
      'plugin scheme defaults to 7z');
  finally
    Reg.Free;
  end;
end;

{ TTestVfsRegistry }

procedure TTestVfsRegistry.TestReservedSchemesCannotBePlugged;
begin
  TestVfsRegistry.TestReservedSchemesCannotBePlugged;
end;

procedure TTestVfsRegistry.TestPluginCannotTakeBuiltInSchemeWithoutGrant;
begin
  TestVfsRegistry.TestPluginCannotTakeBuiltInSchemeWithoutGrant;
end;

procedure TTestVfsRegistry.TestGrantedOverrideReplacesBuiltInScheme;
begin
  TestVfsRegistry.TestGrantedOverrideReplacesBuiltInScheme;
end;

procedure TTestVfsRegistry.TestArchiveExtensionOverride;
begin
  TestVfsRegistry.TestArchiveExtensionOverride;
end;

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
