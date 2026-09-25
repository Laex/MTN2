program TestVfsRegistry;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas';

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

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
end;

procedure TestClassify;
var
  Reason: string;
begin
  Expect(ClassifyVfsTransfer('file:///C:/a', 'file:///C:/b', False,
    False, False, False, Reason) = vtrFile, 'file copy');
  Expect(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'file:///C:/b', False,
    False, False, False, Reason) = vtrZip, 'archive copy');
  Expect(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'file:///C:/b', True,
    False, False, False, Reason) = vtrNotSupported, 'archive move');
  Expect(ClassifyVfsTransfer('find://session/1/', 'file:///C:/b', False,
    False, False, False, Reason) = vtrNotSupported, 'find copy');
  Expect(ClassifyVfsTransfer('sample://a', 'sample://b', False,
    True, True, True, Reason) = vtrPluginBackend, 'same-plugin copy');
  Expect(ClassifyVfsTransfer('sample://a', 'file:///C:/b', False,
    True, False, False, Reason) = vtrPluginExtract, 'plugin to file');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'sample://b', False,
    False, True, False, Reason) = vtrPluginDest, 'file to plugin dest');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'sample://b', True,
    False, True, False, Reason) = vtrNotSupported, 'move to plugin dest');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'ws:///', False,
    False, False, False, Reason) = vtrPluginDest, 'file to workspace');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'ws:///', True,
    False, False, False, Reason) = vtrNotSupported, 'move to workspace');
  Expect(ClassifyVfsTransfer('7z:///C:/a.7z!/x', 'file:///C:/b', False,
    False, False, False, Reason) = vtrNotSupported, '7z without plugin');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrSftp, 'file to sftp copy');
  Expect(ClassifyVfsTransfer('sftp://u@h/a', 'file:///C:/b', False,
    False, False, False, Reason) = vtrSftp, 'sftp to file copy');
  Expect(ClassifyVfsTransfer('sftp://u@h/a', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrSftp, 'sftp to sftp copy');
  Expect(ClassifyVfsTransfer('file:///C:/a', 'sftp://u@h/b', True,
    False, False, False, Reason) = vtrSftp, 'file to sftp move');
  Expect(ClassifyVfsTransfer('file:///C:/a.zip!/x', 'sftp://u@h/b', False,
    False, False, False, Reason) = vtrNotSupported, 'archive to sftp');
  Writeln('OK: TestClassify');
end;

procedure TestPluginOwnedAndUnload;
var
  Reg: TVfsRegistry;
  Stub: IVirtualFileSystem;
  Backend: IVirtualFileSystem;
begin
  Expect(GlobalVfsRegistry.TryResolve('ws:///', Backend), 'built-in ws scheme');
  Expect(not GlobalVfsRegistry.IsPluginOwned('ws:///'), 'built-in ws is not plugin-owned');
  Reg := TVfsRegistry.Create;
  Stub := TStubVfs.Create;
  try
    Expect(not Reg.IsPluginOwned('sample://x'), 'empty registry');
    Reg.RegisterPluginScheme('demo', 'sample', Stub, 50);
    Expect(Reg.IsPluginOwned('sample://x'), 'sample is plugin-owned');
    Expect(not Reg.IsPluginOwned('file:///C:/'), 'file is not plugin-owned');
    Reg.UnregisterPlugin('demo');
    Expect(not Reg.IsPluginOwned('sample://x'), 'unregistered');
    Reg.UnregisterPlugin('demo'); // idempotent
  finally
    Reg.Free;
  end;
  Writeln('OK: TestPluginOwnedAndUnload');
end;

procedure TestArchiveExtensions;
var
  Reg: TVfsRegistry;
  Kind: TArchiveExtensionKind;
begin
  // Built-ins on the process-wide registry: always present, never plugin-owned.
  Expect(GlobalVfsRegistry.TryResolveArchiveKind('pack.zip', Kind) and (Kind = akZipChain),
    'built-in .zip resolves to akZipChain');
  Expect(GlobalVfsRegistry.TryResolveArchiveKind('App.jar', Kind) and (Kind = akZipChain),
    'built-in .jar is case-insensitive');
  Expect(not GlobalVfsRegistry.TryResolveArchiveKind('readme.txt', Kind),
    'unregistered extension does not resolve');
  Expect(not GlobalVfsRegistry.TryResolveArchiveKind('noext', Kind),
    'extension-less name does not resolve');

  Reg := TVfsRegistry.Create;
  try
    Expect(not Reg.TryResolveArchiveKind('pack.7z', Kind), 'fresh registry has no .7z');
    Reg.RegisterArchiveExtension('mtn.7z', '7z', akSevenZip, 100);
    Expect(Reg.TryResolveArchiveKind('pack.7z', Kind) and (Kind = akSevenZip),
      'plugin-declared .7z resolves to akSevenZip');
    Reg.UnregisterPlugin('mtn.7z');
    Expect(not Reg.TryResolveArchiveKind('pack.7z', Kind),
      'unloading the plugin drops its archive extensions');
    Reg.UnregisterPlugin('mtn.7z'); // idempotent
  finally
    Reg.Free;
  end;
  Writeln('OK: TestArchiveExtensions');
end;

begin
  try
    TestClassify;
    TestPluginOwnedAndUnload;
    TestArchiveExtensions;
    Writeln('All VfsRegistry tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
