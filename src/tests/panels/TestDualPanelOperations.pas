unit TestDualPanelOperations;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelOperations = class
  public
    [Test] [Category('WindowsOnly')] procedure TestFolderSegments;
    [Test] procedure TestRenameName;
    [Test] procedure TestClassifyActivateCurrent;
    [Test] procedure TestShouldLeaveRemovedFolder;
    [Test] procedure TestFindExistingParentFileUri;
    [Test] procedure TestZipNamedFileIsOtherArchiveEarlyExit;
    [Test] procedure TestZipEncryptedProbeEarlyExit;
    [Test] procedure TestReadableArchiveRowUriPlain;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uAssociations,
  uDualPanelTypes,
  uDualPanelOperations;

procedure TestFolderSegments;
var
  Clean, Select, Err: string;
begin
  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('', Clean, Select, Err),
    'empty name rejected');
  Assert.IsTrue(Err = 'Name is empty', 'empty name message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('   ///', Clean, Select, Err),
    'slash-only name rejected');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('C:\abs', Clean, Select, Err),
    'rooted path rejected');
  Assert.IsTrue(Pos('relative', Err) > 0, 'rooted path says relative');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('foo\..', Clean, Select, Err),
    '.. segment rejected');
  Assert.IsTrue(Err = 'Invalid folder name', '.. message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('bad:name', Clean, Select, Err),
    'colon rejected');
  Assert.IsTrue(Err = 'Name contains invalid characters', 'invalid-char message');

  Assert.IsTrue(TDualPanelOperationsController.ValidateFolderSegments('a/b\c', Clean, Select, Err),
    'nested relative accepted');
  Assert.IsTrue(Clean = 'a' + PathDelim + 'b' + PathDelim + 'c', 'nested name joined');
  Assert.IsTrue(Select = 'a', 'select first segment');
  Assert.IsTrue(Err = '', 'no error on success');
end;

procedure TestRenameName;
var
  Err: string;
begin
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('  ', Err), 'empty rename rejected');
  Assert.IsTrue(Err = 'Name is empty', 'empty rename message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a\b', Err), 'backslash rejected');
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a/b', Err), 'slash rejected');
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a:b', Err), 'colon rejected');
  Assert.IsTrue(Pos('separators', Err) > 0, 'separator message');

  Assert.IsTrue(TDualPanelOperationsController.ValidateRenameName('  new.txt  ', Err), 'plain name accepted');
  Assert.IsTrue(Err = '', 'no error on rename success');
{$IFDEF MSWINDOWS}
  Assert.IsFalse(TDualPanelOperationsController.ValidateRenameName('a?b', Err), 'question mark rejected');
  Assert.IsTrue(Pos('Invalid name', Err) > 0, 'invalid name message');
  Assert.IsFalse(TDualPanelOperationsController.ValidateRenameName('con', Err), 'reserved name rejected');
{$ENDIF}
  Assert.IsFalse(TDualPanelOperationsController.ValidateRenameName('..', Err), 'two dots rejected');
end;

procedure TestClassifyActivateCurrent;
begin
  Assert.IsTrue(ClassifyActivateCurrent(True, True, True, True, aaEdit) = ackFindGoto,
    'find hit wins');
  Assert.IsTrue(ClassifyActivateCurrent(False, True, True, False, aaView) = ackHistoryBack,
    'recycle/sys parent goes back');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, True, True, aaView) = ackNavigate,
    'dir wins over zip');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, True, aaView) = ackZipNavigate,
    'zip file navigates archive');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaEdit) = ackEdit,
    'assoc edit');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaShell) = ackShell,
    'assoc shell');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaView) = ackView,
    'assoc view');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaNone) = ackView,
    'unknown assoc views');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaNavigate) = ackNavigate,
    'assoc navigate');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaCommand) = ackCommand,
    'assoc command (user-defined rule)');
end;

procedure TestShouldLeaveRemovedFolder;
const
  CGone = 'file:///C:/Work/gone';
begin
  Assert.IsTrue(ShouldLeaveRemovedFolder(vecNotFound, CGone, CGone),
    'listed-ok local folder that vanished');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecOk, CGone, CGone), 'ok listing stays');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecAccessDenied, CGone, CGone),
    'other errors stay');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound, '', CGone), 'empty uri');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound, CGone, 'file:///C:/Other'),
    'never listed here');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound, 'tmp:///', 'tmp:///'),
    'non-file scheme');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound,
    'file:///C:/a.zip!/inner', 'file:///C:/a.zip!/inner'), 'archive chain');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound, 'find://1', 'find://1'),
    'find uri');
  Assert.IsFalse(ShouldLeaveRemovedFolder(vecNotFound, 'ws:///', 'ws:///'),
    'workspace uri');
end;

procedure TestFindExistingParentFileUri;
var
  Existing: TArray<string>;
  Found: string;
  Exists: TDirectoryExistsFn;
begin
  Existing := TArray<string>.Create('C:\Work', 'C:\');
  Exists :=
    function(const APath: string): Boolean
    var
      P: string;
    begin
      Result := False;
      for P in Existing do
        if SameText(ExcludeTrailingPathDelimiter(APath),
           ExcludeTrailingPathDelimiter(P)) then
          Exit(True);
    end;
  Found := FindExistingParentFileUri('file:///C:/Work/gone/deep', Exists);
  Assert.IsTrue(SameVfsUri(Found, 'file:///C:/Work'), 'nearest existing parent');

  Exists :=
    function(const APath: string): Boolean
    begin
      Result := False;
    end;
  Found := FindExistingParentFileUri('file:///C:/Work/gone', Exists);
  Assert.AreEqual('', Found, 'no ancestor exists');

  Found := FindExistingParentFileUri('file:///C:/Work/gone', nil);
  Assert.AreEqual('', Found, 'nil probe yields empty');
end;

procedure TestZipNamedFileIsOtherArchiveEarlyExit;
begin
  Assert.IsFalse(ZipNamedFileIsOtherArchive('tmp:///a.zip'), 'non-file scheme');
  Assert.IsFalse(ZipNamedFileIsOtherArchive('file:///C:/a.zip!/inner'),
    'archive chain');
  Assert.IsFalse(ZipNamedFileIsOtherArchive('file:///C:/no-such-mtn2-zip-probe.zip'),
    'missing file');
end;

procedure TestZipEncryptedProbeEarlyExit;
var
  Arch, Probe: string;
begin
  Assert.IsFalse(ZipEncryptedProbe('file:///C:/plain',
    TArray<string>.Create('file:///C:/plain/a.txt'), Arch, Probe),
    'plain folder is not a zip panel');
  Assert.AreEqual('', Arch, 'archive path cleared');
  Assert.AreEqual('', Probe, 'probe uri cleared');
  Assert.IsFalse(ZipEncryptedProbe('tmp:///', nil, Arch, Probe), 'tmp is not zip');
end;

procedure TestReadableArchiveRowUriPlain;
var
  Row: TPanelRow;
begin
  Row := MakePanelRow('a.txt', False, 1, '1', '', 'file:///C:/Work/a.txt');
  Assert.AreEqual(Row.URI, ReadableArchiveRowUri(Row), 'plain file keeps its uri');
  Row.IsEncrypted := True;
  Assert.AreEqual(Row.URI, ReadableArchiveRowUri(Row),
    'encrypted outside a zip entry keeps its uri');
end;

{ TTestDualPanelOperations }

procedure TTestDualPanelOperations.TestFolderSegments;
begin
  TestDualPanelOperations.TestFolderSegments;
end;

procedure TTestDualPanelOperations.TestRenameName;
begin
  TestDualPanelOperations.TestRenameName;
end;

procedure TTestDualPanelOperations.TestClassifyActivateCurrent;
begin
  TestDualPanelOperations.TestClassifyActivateCurrent;
end;

procedure TTestDualPanelOperations.TestShouldLeaveRemovedFolder;
begin
  TestDualPanelOperations.TestShouldLeaveRemovedFolder;
end;

procedure TTestDualPanelOperations.TestFindExistingParentFileUri;
begin
  TestDualPanelOperations.TestFindExistingParentFileUri;
end;

procedure TTestDualPanelOperations.TestZipNamedFileIsOtherArchiveEarlyExit;
begin
  TestDualPanelOperations.TestZipNamedFileIsOtherArchiveEarlyExit;
end;

procedure TTestDualPanelOperations.TestZipEncryptedProbeEarlyExit;
begin
  TestDualPanelOperations.TestZipEncryptedProbeEarlyExit;
end;

procedure TTestDualPanelOperations.TestReadableArchiveRowUriPlain;
begin
  TestDualPanelOperations.TestReadableArchiveRowUriPlain;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelOperations);

end.
