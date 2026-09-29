unit TestDirWatchSlowDrive;

{ Covers uDirWatch.TDirectoryWatcher.SetPath's non-blocking setup: it used
  to call DirectoryExists + FindFirstChangeNotification synchronously,
  inline, on whatever thread called SetPath -- TDualPanelWindow.
  SyncDirWatches, called from LoadSide on EVERY navigation (including
  Change Drive / Ctrl+Left+Right, which always land on a drive root).
  On an unresponsive network drive (P: on the dev machine) that froze the
  whole UI thread the instant a navigation landed, even after the earlier
  ResolveLocalDirPath/ResolvePanelDriveUri fixes removed the other
  synchronous filesystem touches on that same path -- SyncDirWatches runs
  right after LoadSide's own async Open() kicks off, still on the UI
  thread. See TestLiveReload.pas for the normal-path behavior (reload
  notifications, debounce, dirty-doc protection) -- unaffected by this
  change, already re-verified there. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDirWatchSlowDrive = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestSetPathOnUnresponsiveDriveReturnsInstantly;
    [Test] procedure TestNavigateAwayFromUnresponsiveDriveIsStable;
    [Test] procedure TestNormalDirectoryStillWatches;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uDirWatch;

function WaitUntil(const APredicate: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  Deadline: UInt64;
begin
  Deadline := TThread.GetTickCount64 + ATimeoutMs;
  repeat
    CheckSynchronize(20);
    if APredicate() then
      Exit(True);
  until TThread.GetTickCount64 >= Deadline;
  Result := APredicate();
end;

procedure TestSetPathOnUnresponsiveDriveReturnsInstantly;
var
  Watcher: TDirectoryWatcher;
  Start, ElapsedMs: UInt64;
begin
  Watcher := TDirectoryWatcher.Create;
  try
    Start := TThread.GetTickCount64;
    Watcher.SetPath('P:\');
    ElapsedMs := TThread.GetTickCount64 - Start;
    Assert.IsTrue(ElapsedMs < 500, Format(
      'SetPath(''P:\'') returned in %dms -- DirectoryExists/FindFirstChangeNotification ' +
      'now run off the caller''s thread', [ElapsedMs]));
  finally
    Start := TThread.GetTickCount64;
    Watcher.Free; // Close -> StopWatcher must not block either, even mid-setup.
    ElapsedMs := TThread.GetTickCount64 - Start;
    Assert.IsTrue(ElapsedMs < 500, Format(
      'Free (Close/StopWatcher) returned in %dms -- no Th.WaitFor on a possibly-stuck setup thread',
      [ElapsedMs]));
  end;
end;

procedure TestNavigateAwayFromUnresponsiveDriveIsStable;
var
  Watcher: TDirectoryWatcher;
  Start, ElapsedMs: UInt64;
begin
  // Mirrors the real scenario: the user lands on P: (its setup thread is now
  // stuck in DirectoryExists, orphaned), then navigates to a normal folder
  // right after -- exactly what TDualPanelWindow.SyncDirWatches does on
  // every navigation. Deliberately NOT a tight loop hammering P: with many
  // concurrent setup attempts (unrealistic, and on a flaky share it can
  // itself make the drive even slower to answer) -- one
  // abandoned P: attempt plus one real transition is what a user's Ctrl+Left/
  // Right or Change Drive pick produces.
  Writeln('Navigating away from an unresponsive drive right after landing on it stays fast');
  Watcher := TDirectoryWatcher.Create;
  try
    Start := TThread.GetTickCount64;
    Watcher.SetPath('P:\');
    Watcher.SetPath(TPath.GetTempPath);
    ElapsedMs := TThread.GetTickCount64 - Start;
    Assert.IsTrue(ElapsedMs < 500, Format(
      'SetPath(P:\) immediately followed by SetPath(a real dir) took %dms total', [ElapsedMs]));
  finally
    Watcher.Free;
  end;
end;

procedure TestNormalDirectoryStillWatches;
var
  Watcher: TDirectoryWatcher;
  TempDir: string;
  Changed: Boolean;
  Start: UInt64;
begin
  TempDir := TPath.Combine(TPath.GetTempPath,
    'mtn2-dirwatch-test-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(TempDir);
  Watcher := TDirectoryWatcher.Create;
  try
    Changed := False;
    Watcher.OnChanged :=
      procedure
      begin
        Changed := True;
      end;
    Watcher.SetPath(TempDir);

    // Setup itself is now async even for a fast local dir -- give it a
    // moment to publish FStopEvent/FChangeHandle before poking the
    // filesystem, matching how a real caller (TDualPanelWindow) would just
    // let events arrive whenever they do.
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Watcher.Path <> '';
      end, 2000), 'watcher settles on the requested path');

    // Path is published optimistically, before the setup thread has armed
    // FindFirstChangeNotification -- a write before that would be missed.
    Start := TThread.GetTickCount64;
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Watcher.Active;
      end, 5000), 'watcher arms its change notification');
    Writeln('        armed after ', TThread.GetTickCount64 - Start, 'ms');

    TFile.WriteAllText(TPath.Combine(TempDir, 'x.txt'), 'hello');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Changed;
      end, 5000), 'a real file-system change still fires OnChanged');
  finally
    Watcher.Free;
    try
      TDirectory.Delete(TempDir, True);
    except
      { best-effort cleanup }
    end;
  end;
end;

{ TTestDirWatchSlowDrive }

procedure TTestDirWatchSlowDrive.SetupFixture;
begin
  Randomize;
end;

procedure TTestDirWatchSlowDrive.TestSetPathOnUnresponsiveDriveReturnsInstantly;
begin
  TestDirWatchSlowDrive.TestSetPathOnUnresponsiveDriveReturnsInstantly;
end;

procedure TTestDirWatchSlowDrive.TestNavigateAwayFromUnresponsiveDriveIsStable;
begin
  TestDirWatchSlowDrive.TestNavigateAwayFromUnresponsiveDriveIsStable;
end;

procedure TTestDirWatchSlowDrive.TestNormalDirectoryStillWatches;
begin
  TestDirWatchSlowDrive.TestNormalDirectoryStillWatches;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDirWatchSlowDrive);

end.
