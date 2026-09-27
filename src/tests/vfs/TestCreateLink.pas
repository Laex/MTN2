unit TestCreateLink;

{ Spike/regression for uLinkUtils: exercises symlink (file + dir), hardlink,
  and junction creation against real Win32 APIs in a scratch temp directory.
  Symlink creation without Developer Mode/elevation is expected to fail with
  a clean error (not a crash) — that path is reported, not treated as a
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uTextEncoding,
  uVfsTypes,
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
  Assert.IsTrue(Ok, 'CreateFileLink(lkJunction) succeeds');
  if Ok then
    Assert.IsTrue(TFile.Exists(TPath.Combine(LinkDir, 'inside.txt')), 'junction resolves to contents')
  else
    Writeln('    error: ', Err.Message);
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

initialization
  TDUnitX.RegisterTestFixture(TTestCreateLink);

end.
