unit TestResolveLocalDirPath;

{ Covers uVfsTypes.ResolveLocalDirPath's drive-root fast path: a drive root
  resolves without calling LocalPathIsDirectory (GetFileAttributes). This
  function is the first thing NavigateSideTo does (via ResolveVfsUri /
  ResolveFileUri) on EVERY navigation -- including Change Drive and
  Ctrl+Left/Right, which always target a drive root -- so a disk call here
  on an unresponsive network drive would freeze the whole app the instant
  the drive is picked, before the async listing (and its own watchdog)
  ever starts. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResolveLocalDirPath = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestDriveRootIsInstant;
    [Test] procedure TestNonDriveRootBehaviorUnchanged;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uTerminalTypes,
  uVfsTypes;

procedure TestDriveRootIsInstant;
var
  Start: UInt64;
  ElapsedMs: UInt64;
  Result_: string;
begin
  // Whether the drive is local or an unresponsive network share, a drive
  // root must resolve in effectively zero time -- IsWindowsDriveRoot is checked (pure string logic) before
  // any Win32 call, not after.
  Start := TThread.GetTickCount64;
  Result_ := ResolveLocalDirPath('P:\');
  ElapsedMs := TThread.GetTickCount64 - Start;
  Assert.IsTrue(Result_ = 'P:\', 'drive root path returned unchanged');
  Assert.IsTrue(ElapsedMs < 500, Format(
    'P:\ resolved in %dms -- no GetFileAttributes/CreateFile round trip to the drive', [ElapsedMs]));

  Start := TThread.GetTickCount64;
  Result_ := ResolveLocalDirPath('C:');
  ElapsedMs := TThread.GetTickCount64 - Start;
  Assert.IsTrue(Result_ = 'C:\',
    'bare drive letter is normalized to a true root, then also short-circuits');
  Assert.IsTrue(ElapsedMs < 500, Format('C: resolved in %dms', [ElapsedMs]));
end;

procedure TestNonDriveRootBehaviorUnchanged;
var
  TempDir, Result_: string;
begin
  Assert.IsTrue(ResolveLocalDirPath('') = '', 'empty path stays empty');

  TempDir := TPath.Combine(TPath.GetTempPath,
    'mtn2-resolve-test-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(TempDir);
  try
    Result_ := ResolveLocalDirPath(TempDir);
    Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(Result_), ExcludeTrailingPathDelimiter(TempDir)),
      'a real, non-drive-root directory still resolves (no regression from the reorder)');
  finally
    TDirectory.Delete(TempDir, False);
  end;

  Result_ := ResolveLocalDirPath('C:\this\path\does\not\exist\mtn2-test');
  Assert.IsTrue(Result_ = 'C:\this\path\does\not\exist\mtn2-test',
    'a nonexistent non-drive-root path is returned unchanged (LocalPathIsDirectory=False path)');
end;

{ TTestResolveLocalDirPath }

procedure TTestResolveLocalDirPath.SetupFixture;
begin
  Randomize;
end;

procedure TTestResolveLocalDirPath.TestDriveRootIsInstant;
begin
  TestResolveLocalDirPath.TestDriveRootIsInstant;
end;

procedure TTestResolveLocalDirPath.TestNonDriveRootBehaviorUnchanged;
begin
  TestResolveLocalDirPath.TestNonDriveRootBehaviorUnchanged;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResolveLocalDirPath);

end.
