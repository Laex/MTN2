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
    [Test] procedure TestNavigationEitherSideIsVirtualView;
    [Test] procedure TestDecideNavigatePendingSelect;
    [Test] procedure TestShouldRememberWorkspaceOrigin;
    [Test] procedure TestApplyNavigateTabBackMarkers;
    [Test] procedure TestAppendTabHistoryNavigate;
    [Test] procedure PanelSidesAndModelInvalidateGates;
    [Test] procedure PluginListCommandClassification;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uAssociations,
  uDualPanelTypes,
  uPanelModel,
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
const
{$IFDEF MSWINDOWS}
  CWorkDir = 'C:\Work';
  CRootDir = 'C:\';
  CWorkUri = 'file:///C:/Work';
{$ELSE}
  CWorkDir = '/work';
  CRootDir = '/';
  CWorkUri = 'file:///work';
{$ENDIF}
var
  Existing: TArray<string>;
  Found: string;
  Exists: TDirectoryExistsFn;
begin
  Existing := TArray<string>.Create(CWorkDir, CRootDir);
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
  Found := FindExistingParentFileUri(CWorkUri + '/gone/deep', Exists);
  Assert.IsTrue(SameVfsUri(Found, CWorkUri), 'nearest existing parent');

  Exists :=
    function(const APath: string): Boolean
    begin
      Result := False;
    end;
  Found := FindExistingParentFileUri(CWorkUri + '/gone', Exists);
  Assert.AreEqual('', Found, 'no ancestor exists');

  Found := FindExistingParentFileUri(CWorkUri + '/gone', nil);
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

procedure TestNavigationEitherSideIsVirtualView;
begin
  Assert.IsFalse(NavigationEitherSideIsVirtualView(
    'file:///C:/Work', 'file:///C:/Work/child'), 'local disk');
  Assert.IsTrue(NavigationEitherSideIsVirtualView(
    'file:///C:/a.zip!/inner', 'file:///C:/a.zip!/'), 'archive from');
  Assert.IsTrue(NavigationEitherSideIsVirtualView(
    'file:///C:/Work', 'find://1'), 'find to');
  Assert.IsTrue(NavigationEitherSideIsVirtualView(
    'sftp://h/a', 'file:///C:/Work'), 'sftp from');
end;

procedure TestDecideNavigatePendingSelect;
var
  D: TNavigatePendingSelect;
const
  CChild = 'file:///C:/Work/child';
  CParent = 'file:///C:/Work';
  CArchInner = 'file:///C:/a.zip!/inner';
  CArchRoot = 'file:///C:/a.zip!/';
begin
  D := DecideNavigatePendingSelect(CChild, CParent,
    CParent, CChild, 'junction', '', '', False, False, 0, 3, 1);
  Assert.IsTrue(D.Kind = npskSelect, 'workspace back with junction name');
  Assert.AreEqual('junction', D.Name, 'junction name wins');
  Assert.IsFalse(D.RememberDriveDir, 'workspace back is not local drive');

  D := DecideNavigatePendingSelect(CChild, CParent,
    CParent, CChild, '', 'link-name', '', False, False, 0, 0, 0);
  Assert.IsTrue(D.Kind = npskSelect, 'workspace back uses link name');
  Assert.AreEqual('link-name', D.Name, 'workspace link name');

  D := DecideNavigatePendingSelect(CArchInner, CArchRoot,
    '', '', '', '', '', True, False, 0, 0, 0);
  Assert.IsTrue(D.Kind = npskSelect, 'virtual parent selects archive title');
  Assert.AreEqual(VfsUriTitle(CArchInner), D.Name, 'archive title');
  Assert.IsFalse(D.RememberDriveDir, 'virtual has no drive dir');

  D := DecideNavigatePendingSelect('find://1', CParent,
    '', '', '', '', CParent, True, False, 0, 0, 0);
  Assert.IsTrue(D.Kind = npskSelect, 'find parent selects empty name');
  Assert.AreEqual('', D.Name, 'find empty name');

  D := DecideNavigatePendingSelect(CChild, CParent,
    '', '', '', '', '', False, True, 7, 5, 2);
  Assert.IsTrue(D.Kind = npskSelect, 'local .. selects child title');
  Assert.AreEqual(FileUriTitle(CChild), D.Name, 'local child title');
  Assert.IsTrue(D.ApplyViewPos, 'local .. applies view pos');
  Assert.AreEqual(7, D.ViewPos, 'stored view pos');
  Assert.IsTrue(D.RememberDriveDir, 'local remembers drive dir');

  D := DecideNavigatePendingSelect(CChild, CParent,
    '', '', '', '', '', False, False, 0, 5, 2);
  Assert.IsTrue(D.ApplyViewPos, 'missing stored view still applies');
  Assert.AreEqual(-1, D.ViewPos, 'missing stored view is -1');

  D := DecideNavigatePendingSelect(CParent, CChild,
    '', '', '', '', '', False, False, 0, 9, 3);
  Assert.IsTrue(D.Kind = npskRememberEnterView, 'enter child remembers view');
  Assert.AreEqual(LowerCase(CParent), D.EnterViewKey, 'enter view key');
  Assert.AreEqual(6, D.EnterViewValue, 'cursor minus scroll');
  Assert.IsTrue(D.RememberDriveDir, 'enter child is local');

  D := DecideNavigatePendingSelect(CParent, 'file:///D:/Other',
    '', '', '', '', '', False, False, 0, 0, 0);
  Assert.IsTrue(D.Kind = npskNone, 'unrelated local move');
  Assert.IsTrue(D.RememberDriveDir, 'unrelated local still remembers drive');
end;

procedure TestShouldRememberWorkspaceOrigin;
begin
  Assert.IsTrue(ShouldRememberWorkspaceOrigin('ws:///', 'file:///C:/Work', ''),
    'enter workspace from folder');
  Assert.IsFalse(ShouldRememberWorkspaceOrigin('ws:///', 'ws:///', ''),
    'already in workspace');
  Assert.IsFalse(ShouldRememberWorkspaceOrigin('ws:///', '', ''),
    'empty from');
  Assert.IsFalse(ShouldRememberWorkspaceOrigin('ws:///', 'find://1', ''),
    'from find');
  Assert.IsFalse(ShouldRememberWorkspaceOrigin('ws:///', 'file:///C:/Work',
    'ws:///'), 'back already points into workspace');
  Assert.IsFalse(ShouldRememberWorkspaceOrigin('file:///C:/Work', 'file:///C:/a',
    ''), 'not entering workspace');
end;

procedure TestApplyNavigateTabBackMarkers;
const
{$IFDEF MSWINDOWS}
  CRootUri = 'file:///C:/';
  CLinkUri = 'file:///C:/link';
{$ELSE}
  CRootUri = 'file:///';
  CLinkUri = 'file:///link';
{$ENDIF}
var
  Tab: TTab;
begin
  Tab := Default(TTab);
  Tab.CurrentURI := 'file:///C:/Work';
  ApplyNavigateTabBackMarkers(Tab, 'tmp:///', 'tmp:///', 'file:///C:/Work',
    False);
  Assert.AreEqual('file:///C:/Work', Tab.WorkspaceBackUri, 'tmp back uri');
  Assert.AreEqual('tmp:///', Tab.WorkspaceBackTarget, 'tmp back target');
  Assert.AreEqual('', Tab.JunctionBackName, 'tmp clears junction name');

  Tab := Default(TTab);
  Tab.CurrentURI := 'file:///C:/Work';
  ApplyNavigateTabBackMarkers(Tab, 'sftp://host/', 'sftp://host/',
    'file:///C:/Work', False);
  Assert.AreEqual('file:///C:/Work', Tab.WorkspaceBackUri, 'sftp root back');
  Assert.AreEqual('sftp://host/', Tab.WorkspaceBackTarget, 'sftp root target');

  Tab := Default(TTab);
  Tab.CurrentURI := 'file:///C:/Work';
  ApplyNavigateTabBackMarkers(Tab, CLinkUri, 'file:///D:/target',
    'file:///C:/Work', False);
  Assert.AreEqual(CRootUri, Tab.WorkspaceBackUri, 'junction parent');
  Assert.AreEqual('file:///D:/target', Tab.WorkspaceBackTarget,
    'junction target');
  Assert.AreEqual(FileUriTitle(CLinkUri), Tab.JunctionBackName,
    'junction name');

  Tab := Default(TTab);
  Tab.CurrentURI := 'file:///C:/Work';
  ApplyNavigateTabBackMarkers(Tab, CLinkUri, 'file:///D:/target',
    'file:///C:/Work', True);
  Assert.AreEqual('', Tab.WorkspaceBackUri, 'virtual skips junction');
  Assert.AreEqual('', Tab.JunctionBackName, 'virtual skips junction name');
end;

procedure TestAppendTabHistoryNavigate;
var
  Tab: TTab;
begin
  Tab := Default(TTab);
  AppendTabHistoryNavigate(Tab, 'file:///C:/A', False);
  Assert.IsTrue(Length(Tab.History) = 0, 'no add when disabled');

  AppendTabHistoryNavigate(Tab, 'file:///C:/A', True);
  Assert.IsTrue(Length(Tab.History) = 1, 'first append');
  Assert.IsTrue(Tab.HistoryIndex = 0, 'index at tip');
  Assert.AreEqual('file:///C:/A', Tab.History[0], 'first uri');

  AppendTabHistoryNavigate(Tab, 'file:///C:/A', True);
  Assert.IsTrue(Length(Tab.History) = 1, 'duplicate tip skipped');

  AppendTabHistoryNavigate(Tab, 'file:///C:/B', True);
  AppendTabHistoryNavigate(Tab, 'file:///C:/C', True);
  Assert.IsTrue(Length(Tab.History) = 3, 'three entries');
  Tab.HistoryIndex := 0;
  AppendTabHistoryNavigate(Tab, 'file:///C:/D', True);
  Assert.IsTrue(Length(Tab.History) = 2, 'forward truncated');
  Assert.AreEqual('file:///C:/A', Tab.History[0], 'kept past');
  Assert.AreEqual('file:///C:/D', Tab.History[1], 'new tip');
  Assert.IsTrue(Tab.HistoryIndex = 1, 'index at new tip');
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

procedure TTestDualPanelOperations.TestNavigationEitherSideIsVirtualView;
begin
  TestDualPanelOperations.TestNavigationEitherSideIsVirtualView;
end;

procedure TTestDualPanelOperations.TestDecideNavigatePendingSelect;
begin
  TestDualPanelOperations.TestDecideNavigatePendingSelect;
end;

procedure TTestDualPanelOperations.TestShouldRememberWorkspaceOrigin;
begin
  TestDualPanelOperations.TestShouldRememberWorkspaceOrigin;
end;

procedure TTestDualPanelOperations.TestApplyNavigateTabBackMarkers;
begin
  TestDualPanelOperations.TestApplyNavigateTabBackMarkers;
end;

procedure TTestDualPanelOperations.TestAppendTabHistoryNavigate;
begin
  TestDualPanelOperations.TestAppendTabHistoryNavigate;
end;

procedure TTestDualPanelOperations.PanelSidesAndModelInvalidateGates;
var
  Sides: TArray<TPanelSide>;
begin
  Sides := PanelSidesForWindowId(cPanelWindowIdLeft);
  Assert.IsTrue(Length(Sides) = 1, 'left count');
  Assert.IsTrue(Sides[0] = psLeft, 'left');
  Sides := PanelSidesForWindowId(cPanelWindowIdRight);
  Assert.IsTrue(Length(Sides) = 1, 'right count');
  Assert.IsTrue(Sides[0] = psRight, 'right');
  Sides := PanelSidesForWindowId(cPanelWindowIdNone);
  Assert.IsTrue(Length(Sides) = 2, 'both');
  Assert.IsTrue(ModelInvalidatedShouldApplyPending('x', True, False), 'apply');
  Assert.IsTrue(not ModelInvalidatedShouldApplyPending('', True, False), 'empty');
  Assert.IsTrue(not ModelInvalidatedShouldApplyPending('x', True, True), 'loading');
  Assert.IsTrue(ModelInvalidatedShouldFlushWatch(True, False, True), 'flush');
  Assert.IsTrue(not ModelInvalidatedShouldFlushWatch(True, False, False), 'busy');
end;

procedure TTestDualPanelOperations.PluginListCommandClassification;
begin
  Assert.AreEqual(Ord(plcDismiss), Ord(ClassifyPluginListCommand('ok')), 'ok');
  Assert.AreEqual(Ord(plcDismiss), Ord(ClassifyPluginListCommand('cancel')), 'cancel');
  Assert.AreEqual(Ord(plcUp), Ord(ClassifyPluginListCommand('up')), 'up');
  Assert.AreEqual(Ord(plcDown), Ord(ClassifyPluginListCommand('down')), 'down');
  Assert.AreEqual(Ord(plcInfo), Ord(ClassifyPluginListCommand('info')), 'info');
  Assert.AreEqual(Ord(plcAdd), Ord(ClassifyPluginListCommand('add')), 'add');
  Assert.AreEqual(Ord(plcRemove), Ord(ClassifyPluginListCommand('remove')), 'remove');
  Assert.AreEqual(Ord(plcSettings), Ord(ClassifyPluginListCommand('settings')), 'settings');
  Assert.AreEqual(Ord(plcPermissions), Ord(ClassifyPluginListCommand('permissions')), 'perm');
  Assert.AreEqual(Ord(plcToggle), Ord(ClassifyPluginListCommand('toggle')), 'toggle');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelOperations);

end.
