program TestResolveLocalDirPath;

{$APPTYPE CONSOLE}

{ Covers uVfsTypes.ResolveLocalDirPath's drive-root fast path: it used to
  call LocalPathIsDirectory (GetFileAttributes) unconditionally before even
  checking whether the path was a drive root, and this function is the
  first thing NavigateSideTo does (via ResolveVfsUri/ResolveFileUri) on
  EVERY navigation -- including Change Drive and Ctrl+Left/Right, which
  always target a drive root. On an unresponsive network drive (P: on the
  dev machine) that made the whole app freeze the instant you picked the
  drive, before the async listing (and its own watchdog) ever started. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestDriveRootIsInstant;
var
  Start: UInt64;
  ElapsedMs: UInt64;
  Result_: string;
begin
  Writeln('ResolveLocalDirPath on a drive root never touches the filesystem');
  // C: is always fast on this machine; P: is the flaky network drive that
  // exposed the bug. Either way, a drive root must resolve in effectively
  // zero time -- IsWindowsDriveRoot is checked (pure string logic) before
  // any Win32 call, not after.
  Start := TThread.GetTickCount64;
  Result_ := ResolveLocalDirPath('P:\');
  ElapsedMs := TThread.GetTickCount64 - Start;
  Expect(Result_ = 'P:\', 'drive root path returned unchanged');
  Expect(ElapsedMs < 500, Format(
    'P:\ resolved in %dms -- no GetFileAttributes/CreateFile round trip to the drive', [ElapsedMs]));

  Start := TThread.GetTickCount64;
  Result_ := ResolveLocalDirPath('C:');
  ElapsedMs := TThread.GetTickCount64 - Start;
  Expect(Result_ = 'C:\',
    'bare drive letter is normalized to a true root, then also short-circuits');
  Expect(ElapsedMs < 500, Format('C: resolved in %dms', [ElapsedMs]));
end;

procedure TestNonDriveRootBehaviorUnchanged;
var
  TempDir, Result_: string;
begin
  Writeln('ResolveLocalDirPath on ordinary paths (regression, unchanged behavior)');
  Expect(ResolveLocalDirPath('') = '', 'empty path stays empty');

  TempDir := TPath.Combine(TPath.GetTempPath,
    'mtn2-resolve-test-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(TempDir);
  try
    Result_ := ResolveLocalDirPath(TempDir);
    Expect(SameText(ExcludeTrailingPathDelimiter(Result_), ExcludeTrailingPathDelimiter(TempDir)),
      'a real, non-drive-root directory still resolves (no regression from the reorder)');
  finally
    TDirectory.Delete(TempDir, False);
  end;

  Result_ := ResolveLocalDirPath('C:\this\path\does\not\exist\mtn2-test');
  Expect(Result_ = 'C:\this\path\does\not\exist\mtn2-test',
    'a nonexistent non-drive-root path is returned unchanged (LocalPathIsDirectory=False path)');
end;

begin
  Randomize;
  try
    TestDriveRootIsInstant;
    TestNonDriveRootBehaviorUnchanged;
    Writeln('All ResolveLocalDirPath tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
