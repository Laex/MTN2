unit TestCreateLink;

{ Spike/regression for uLinkUtils: exercises symlink (file + dir), hardlink,
  and junction creation against real Win32 APIs in a scratch temp directory.
  Symlink creation without Developer Mode/elevation is expected to fail with
  a clean error (not a crash) - that path is reported, not treated as a
  hard failure of the run. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCreateLink = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestHardlink;
    [Test] procedure TestSymlinkFile;
    [Test] procedure TestSymlinkDir;
    [Test] procedure TestJunction;
    [Test] procedure TestSuggestedLinkType;
    [Test] procedure TestCopyLinkNode;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uTextEncoding,
  uVfsTypes,
  uPlatformPaths,
  uLinkUtils;

var
  GRoot: string;

procedure ReportOptional(ASucceeded: Boolean; const AWhat: string; const AError: TVfsError);
begin
  if ASucceeded then
    Writeln('  [PASS] ', AWhat)
  else
    Writeln('  [SKIP] ', AWhat, ' — ', AError.Message,
      ' (expected without Developer Mode/elevation on some systems)');
end;

procedure TestHardlink;
var
  SrcFile, LinkFile: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  SrcFile := TPath.Combine(GRoot, 'source.txt');
  LinkFile := TPath.Combine(GRoot, 'hardlink.txt');
  TFile.WriteAllText(SrcFile, 'hello');
  Ok := CreateFileLink(LinkFile, SrcFile, lkHardlink, Err);
  Assert.IsTrue(Ok, 'CreateFileLink(lkHardlink) succeeds');
  if Ok then
  begin
    Assert.IsTrue(TFile.Exists(LinkFile), 'hardlink target file exists');
    Assert.IsTrue(TFile.ReadAllText(LinkFile) = 'hello', 'hardlink content matches source');
  end
  else
    Writeln('    error: ', Err.Message);
end;

procedure TestSymlinkFile;
var
  SrcFile, LinkFile: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  SrcFile := TPath.Combine(GRoot, 'source.txt');
  LinkFile := TPath.Combine(GRoot, 'symlink.txt');
  Ok := CreateFileLink(LinkFile, SrcFile, lkSymlinkFile, Err);
  ReportOptional(Ok, 'CreateFileLink(lkSymlinkFile)', Err);
  if Ok then
    Assert.IsTrue(TFile.Exists(LinkFile), 'symlink target resolves');
end;

procedure TestSymlinkDir;
var
  SrcDir, LinkDir: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  SrcDir := TPath.Combine(GRoot, 'srcdir');
  LinkDir := TPath.Combine(GRoot, 'symlinkdir');
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'inside.txt'), 'x');
  Ok := CreateFileLink(LinkDir, SrcDir, lkSymlinkDir, Err);
  ReportOptional(Ok, 'CreateFileLink(lkSymlinkDir)', Err);
  if Ok then
    Assert.IsTrue(TFile.Exists(TPath.Combine(LinkDir, 'inside.txt')), 'symlink dir resolves to contents');
end;

procedure TestJunction;
var
  SrcDir, LinkDir: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  SrcDir := TPath.Combine(GRoot, 'srcdir');
  LinkDir := TPath.Combine(GRoot, 'junctiondir');
  Ok := CreateFileLink(LinkDir, SrcDir, lkJunction, Err);
  if PlatformPosixPaths then
  begin
    // Junctions exist only on Windows.
    Assert.IsFalse(Ok, 'a junction is refused');
    Assert.AreEqual(Ord(vecNotSupported), Ord(Err.Code), 'as not supported');
    Exit;
  end;
  Assert.IsTrue(Ok, 'CreateFileLink(lkJunction) succeeds');
  if Ok then
    Assert.IsTrue(TFile.Exists(TPath.Combine(LinkDir, 'inside.txt')), 'junction resolves to contents')
  else
    Writeln('    error: ', Err.Message);
end;

procedure TestCopyLinkNode;
var
  SrcDir, LinkDir, CopyDir, NotLink: string;
  Err: TVfsError;
  Kind: TLinkKind;
begin
  if PlatformPosixPaths then
    Kind := lkSymlinkDir
  else
    Kind := lkJunction;
  SrcDir := TPath.Combine(GRoot, 'copylink_target');
  LinkDir := TPath.Combine(GRoot, 'copylink_src');
  CopyDir := TPath.Combine(GRoot, 'copylink_dst');
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'inside.txt'), 'x');
  Assert.IsTrue(CreateFileLink(LinkDir, SrcDir, Kind, Err), 'link is created');
  Assert.IsTrue(IsRecreatableLink(LinkDir), 'a link is recognised');
  Assert.IsFalse(IsRecreatableLink(SrcDir), 'a plain folder is not a link');

  Assert.IsTrue(CopyLinkNode(LinkDir, CopyDir, False, Err), 'link is recreated');
  Assert.IsTrue(IsRecreatableLink(CopyDir), 'the copy is a link, not a folder copy');
  Assert.IsTrue(TFile.Exists(TPath.Combine(CopyDir, 'inside.txt')), 'the copy points at the same target');

  Assert.IsFalse(CopyLinkNode(LinkDir, CopyDir, False, Err), 'an existing destination is refused');
  Assert.AreEqual(Ord(vecAlreadyExists), Ord(Err.Code), 'as already exists');
  Assert.IsTrue(CopyLinkNode(LinkDir, CopyDir, True, Err), 'an existing destination is replaced');
  Assert.IsTrue(IsRecreatableLink(CopyDir), 'the replacement is a link');

  Assert.IsTrue(DeleteLinkNode(CopyDir, Err), 'the link is removed');
  Assert.IsFalse(IsRecreatableLink(CopyDir) or TDirectory.Exists(CopyDir), 'the link is gone');
  Assert.IsTrue(TFile.Exists(TPath.Combine(SrcDir, 'inside.txt')), 'removing the link keeps its target');

  NotLink := TPath.Combine(GRoot, 'copylink_plain.txt');
  TFile.WriteAllText(NotLink, 'x');
  Assert.IsFalse(CopyLinkNode(NotLink, TPath.Combine(GRoot, 'copylink_none'), False, Err),
    'a plain file is not copied as a link');
  Assert.IsTrue(TFile.Exists(TPath.Combine(SrcDir, 'inside.txt')), 'the target is untouched');
end;

procedure TestSuggestedLinkType;
var
  Dir, Src: string;
  Can: Boolean;
begin
  Dir := TPath.Combine(GRoot, 'suggestdir');
  Src := TPath.Combine(GRoot, 'suggest.txt');
  TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(Src, 'x');
  Can := CanCreateSymlinks;
  if Can then
  begin
    Assert.AreEqual(Ord(lkSymlinkDir), SuggestLinkTypeIndex(Dir, GRoot), 'folder -> directory symlink');
    Assert.AreEqual(Ord(lkSymlinkFile), SuggestLinkTypeIndex(Src, GRoot), 'file -> file symlink');
  end
  else
  begin
    Assert.AreEqual(Ord(lkJunction), SuggestLinkTypeIndex(Dir, GRoot), 'folder -> junction');
    Assert.AreEqual(Ord(lkHardlink), SuggestLinkTypeIndex(Src, GRoot), 'file on same drive -> hard link');
  end;
end;

{ TTestCreateLink }

procedure TTestCreateLink.SetupFixture;
begin
  Randomize;
  GRoot := TPath.Combine(TPath.GetTempPath, 'mtn2_testcreatelink_' + IntToStr(Random(100000)));
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestCreateLink.TearDownFixture;
begin
  try
    TDirectory.Delete(GRoot, True);
  except
  end;
end;

procedure TTestCreateLink.TestHardlink;
begin
  TestCreateLink.TestHardlink;
end;

procedure TTestCreateLink.TestSymlinkFile;
begin
  TestCreateLink.TestSymlinkFile;
end;

procedure TTestCreateLink.TestSymlinkDir;
begin
  TestCreateLink.TestSymlinkDir;
end;

procedure TTestCreateLink.TestJunction;
begin
  TestCreateLink.TestJunction;
end;

procedure TTestCreateLink.TestSuggestedLinkType;
begin
  TestCreateLink.TestSuggestedLinkType;
end;

procedure TTestCreateLink.TestCopyLinkNode;
begin
  TestCreateLink.TestCopyLinkNode;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCreateLink);

end.
