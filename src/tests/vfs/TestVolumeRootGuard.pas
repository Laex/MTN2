unit TestVolumeRootGuard;

{ A delete never targets the root of a volume: IsVolumeRootPath names those
  paths, and DeleteAsync refuses them before touching anything. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVolumeRootGuard = class
  public
    [Test] procedure TestRootsAreRecognised;
    [Test] procedure TestOrdinaryPathsAreNot;
  end;

implementation

uses
  uVfsUtils,
  uPlatformPaths;

procedure TTestVolumeRootGuard.TestRootsAreRecognised;
begin
  if PlatformPosixPaths then
  begin
    Assert.IsTrue(IsVolumeRootPath('/'), 'slash is the root');
    Exit;
  end;
  Assert.IsTrue(IsVolumeRootPath('C:\'), 'drive root with slash');
  Assert.IsTrue(IsVolumeRootPath('C:'), 'drive root without slash');
  Assert.IsTrue(IsVolumeRootPath('d:\'), 'lower-case drive root');
  Assert.IsTrue(IsVolumeRootPath('\\server\share'), 'share root');
  Assert.IsTrue(IsVolumeRootPath('\\server\share\'), 'share root with slash');
end;

procedure TTestVolumeRootGuard.TestOrdinaryPathsAreNot;
begin
  if PlatformPosixPaths then
  begin
    Assert.IsFalse(IsVolumeRootPath('/tmp'), 'a top-level folder is not the root');
    Assert.IsFalse(IsVolumeRootPath('/tmp/a'), 'a nested folder is not the root');
    Exit;
  end;
  Assert.IsFalse(IsVolumeRootPath('C:\Temp'), 'a top-level folder');
  Assert.IsFalse(IsVolumeRootPath('C:\Temp\'), 'a top-level folder with slash');
  Assert.IsFalse(IsVolumeRootPath('\\server\share\dir'), 'a folder on a share');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVolumeRootGuard);

end.
