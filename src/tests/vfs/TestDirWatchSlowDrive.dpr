program TestDirWatchSlowDrive;

{$APPTYPE CONSOLE}

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
  thread. See TestLiveReload.dpr for the normal-path behavior (reload
  notifications, debounce, dirty-doc protection) -- unaffected by this
  change, already re-verified there. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uDirWatch in '..\..\Core\uDirWatch.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

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
  Writeln('SetPath on the flaky network drive (P:) never blocks the caller');
  Watcher := TDirectoryWatcher.Create;
  try
    Start := TThread.GetTickCount64;
    Watcher.SetPath('P:\');
    ElapsedMs := TThread.GetTickCount64 - Start;
    Expect(ElapsedMs < 500, Format(
      'SetPath(''P:\'') returned in %dms -- DirectoryExists/FindFirstChangeNotification ' +
      'now run off the caller''s thread', [ElapsedMs]));
  finally
    Start := TThread.GetTickCount64;
    Watcher.Free; // Close -> StopWatcher must not block either, even mid-setup.
    ElapsedMs := TThread.GetTickCount64 - Start;
    Expect(ElapsedMs < 500, Format(
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
  // concurrent setup attempts (unrealistic and, on this machine's actual
  // flaky share, can itself make the drive even slower to answer) -- one
  // abandoned P: attempt plus one real transition is what a user's Ctrl+Left/
  // Right or Change Drive pick actually produces.
  Writeln('Navigating away from an unresponsive drive right after landing on it stays fast');
  Watcher := TDirectoryWatcher.Create;
  try
    Start := TThread.GetTickCount64;
    Watcher.SetPath('P:\');
    Watcher.SetPath(TPath.GetTempPath);
    ElapsedMs := TThread.GetTickCount64 - Start;
    Expect(ElapsedMs < 500, Format(
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
  Writeln('A normal, responsive directory still gets watched (setup completes async)');
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
    // moment to actually publish FStopEvent/FChangeHandle before poking the
    // filesystem, matching how a real caller (TDualPanelWindow) would just
    // let events arrive whenever they do.
    Expect(WaitUntil(
      function: Boolean
      begin
        Result := Watcher.Path <> '';
      end, 2000), 'watcher settles on the requested path');

    // Path is published optimistically, before the setup thread has armed
    // FindFirstChangeNotification -- a write before that would be missed.
    Start := TThread.GetTickCount64;
    Expect(WaitUntil(
      function: Boolean
      begin
        Result := Watcher.Active;
      end, 5000), 'watcher arms its change notification');
    Writeln('        armed after ', TThread.GetTickCount64 - Start, 'ms');

    TFile.WriteAllText(TPath.Combine(TempDir, 'x.txt'), 'hello');
    Expect(WaitUntil(
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

begin
  Randomize;
  try
    TestSetPathOnUnresponsiveDriveReturnsInstantly;
    TestNavigateAwayFromUnresponsiveDriveIsStable;
    TestNormalDirectoryStillWatches;
    Writeln('All DirWatchSlowDrive tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
