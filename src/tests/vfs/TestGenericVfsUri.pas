unit TestGenericVfsUri;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGenericVfsUri = class
  public
    [Test] procedure TestPluginSchemeUrisAreGeneric;
    [Test] procedure TestBuiltInAndArchiveUrisAreNotGeneric;
    [Test] procedure TestSplitAndMakeRoundTrip;
    [Test] procedure TestJoinAppendsOneSegment;
    [Test] procedure TestParentWalksUpToTheSchemeRoot;
    [Test] procedure TestSchemeRootIsTheNavigationRoot;
    [Test] procedure TestSameUriAndKeyIgnoreCaseAndTrailingSlash;
    [Test] procedure TestTitleIsTheLastSegmentOrAuthority;
    [Test] procedure VirtualDirWatchSkipsFoldersThatAreNotOnDisk;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes;

procedure TTestGenericVfsUri.TestPluginSchemeUrisAreGeneric;
begin
  Assert.IsTrue(IsGenericVfsUri('net:///'));
  Assert.IsTrue(IsGenericVfsUri('net://work/dir/a.txt'));
  Assert.IsTrue(IsGenericVfsUri('ftps://user@host:21/pub'));
  Assert.IsTrue(IsGenericVfsUri('s3://bucket/key'));
  Assert.IsFalse(IsGenericVfsUri('no-scheme'));
  Assert.IsFalse(IsGenericVfsUri('://x'));
end;

procedure TTestGenericVfsUri.TestBuiltInAndArchiveUrisAreNotGeneric;
begin
  Assert.IsFalse(IsGenericVfsUri('file:///C:/a'));
  Assert.IsFalse(IsGenericVfsUri('sftp://host/a'));
  Assert.IsFalse(IsGenericVfsUri('ws:///'));
  Assert.IsFalse(IsGenericVfsUri('tmp:///'));
  Assert.IsFalse(IsGenericVfsUri('sys://folders'));
  Assert.IsFalse(IsGenericVfsUri('recycle:///'));
  Assert.IsFalse(IsGenericVfsUri('7z:///C:/a.7z!/dir'), 'an archive chain keeps the archive rules');
end;

procedure TTestGenericVfsUri.TestSplitAndMakeRoundTrip;
begin
  Assert.AreEqual('net', GenericVfsSchemeOf('NET://Work/a/b'));
  Assert.AreEqual('Work', GenericVfsAuthorityOf('net://Work/a/b'));
  Assert.AreEqual('/a/b', GenericVfsPathOf('net://Work/a/b/'));
  Assert.AreEqual('/', GenericVfsPathOf('net://Work'));
  Assert.AreEqual('', GenericVfsAuthorityOf('net:///a'));
  Assert.AreEqual('net://Work/a/b', MakeGenericVfsUri('net', 'Work', '/a/b'));
  Assert.AreEqual('net:///', MakeGenericVfsUri('NET', '', ''));
end;

procedure TTestGenericVfsUri.TestJoinAppendsOneSegment;
begin
  Assert.AreEqual('net://w/a', JoinVfsUri('net://w/', 'a'));
  Assert.AreEqual('net://w/a/b c', JoinVfsUri('net://w/a', 'b c'));
  Assert.AreEqual('net://w/a/b', JoinVfsUri('net://w/a/', '/b'));
  Assert.AreEqual('net:///work', JoinVfsUri('net:///', 'work'));
end;

procedure TTestGenericVfsUri.TestParentWalksUpToTheSchemeRoot;
begin
  Assert.AreEqual('net://w/a', ParentVfsUri('net://w/a/b'));
  Assert.AreEqual('net://w/', ParentVfsUri('net://w/a'));
  Assert.AreEqual('net:///', ParentVfsUri('net://w/'));
  Assert.AreEqual('net:///', ParentVfsUri('net:///'));
end;

procedure TTestGenericVfsUri.TestSchemeRootIsTheNavigationRoot;
begin
  Assert.IsTrue(IsVfsUriNavigationRoot('net:///'));
  Assert.IsFalse(IsVfsUriNavigationRoot('net://w/'));
  Assert.IsFalse(IsVfsUriNavigationRoot('net://w/a'));
end;

procedure TTestGenericVfsUri.TestSameUriAndKeyIgnoreCaseAndTrailingSlash;
begin
  Assert.IsTrue(SameVfsUri('net://W/a/b', 'NET://w/a/b/'));
  Assert.IsFalse(SameVfsUri('net://w/a', 'net://w/b'));
  Assert.IsFalse(SameVfsUri('net://w/a', 'net://x/a'));
  Assert.IsFalse(SameVfsUri('net://w/a', 'file:///C:/a'));
  Assert.AreEqual(VfsUriKey('net://W/a'), VfsUriKey('net://w/a/'));
  Assert.AreNotEqual(VfsUriKey('net://w/a'), VfsUriKey('net://w/b'));
end;

procedure TTestGenericVfsUri.TestTitleIsTheLastSegmentOrAuthority;
begin
  Assert.AreEqual('b', VfsUriTitle('net://w/a/b'));
  Assert.AreEqual('w', VfsUriTitle('net://w/'));
  Assert.AreEqual('net:', VfsUriTitle('net:///'));
  Assert.AreEqual('b', VfsUriDirTabTitle('net://w/a/b', 20));
end;

procedure TTestGenericVfsUri.VirtualDirWatchSkipsFoldersThatAreNotOnDisk;
begin
  Assert.IsTrue(IsVirtualDirWatchUri('file:///C:/a.zip!/dir'), 'an archive chain is not a disk folder');
  Assert.IsTrue(IsVirtualDirWatchUri('find://session'), 'find results are not a disk folder');
  Assert.IsTrue(IsVirtualDirWatchUri('tmp:///'), 'the temporary panel is not a disk folder');
  Assert.IsTrue(IsVirtualDirWatchUri('ws:///'), 'a workspace is not a disk folder');
  Assert.IsFalse(IsVirtualDirWatchUri('file:///C:/Work'), 'a file folder is watched');
  Assert.IsFalse(IsVirtualDirWatchUri('recycle:'), 'the recycle bin is a separate check');
  Assert.IsFalse(IsVirtualDirWatchUri('sys://folders'), 'system folders are a separate check');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGenericVfsUri);

end.
