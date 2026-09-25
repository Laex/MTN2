unit uDirWatch;

{ Watches a local directory via FindFirstChangeNotification and notifies the
  main thread (debounced) when contents change.

  CROSS-PLATFORM (Этап 23): FindFirstChangeNotification is Windows-only;
  POSIX needs inotify (Linux) or kqueue (macOS/BSD) instead -- different
  mechanisms per OS, no single portable primitive. The public surface here
  (Create / SetPath / OnChanged callback) is already implementation-agnostic,
  so a port only needs a new StartWatcher/StopWatcher body per platform,
  not a caller-facing change. }

interface

uses
  System.SysUtils, System.Classes;

type
  TDirWatchNotify = reference to procedure;

  TDirectoryWatcher = class
  private
    FPath: string;
    FOnChanged: TDirWatchNotify;
    FThread: TThread;
    FStopEvent: THandle;
    FChangeHandle: THandle;
    FGen: Integer;
    /// <summary>False from the start of Close/Destroy on -- an orphaned
    /// setup thread's queued closures (see StartWatcher) must not touch this
    /// instance's fields once it may have been freed. Mirrors
    /// uPanelModel.TFilePanelModel.FAlive's established pattern in this
    /// codebase for the same class of background-thread-outlives-the-object
    /// situation.</summary>
    FAlive: Boolean;
    procedure StopWatcher;
    procedure StartWatcher(const APath: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Empty path stops the watcher. Same path is a no-op.</summary>
    procedure SetPath(const APath: string);
    procedure Close;
    property OnChanged: TDirWatchNotify read FOnChanged write FOnChanged;
    property Path: string read FPath;
  end;

implementation

uses
  Winapi.Windows, uVfsTypes;

constructor TDirectoryWatcher.Create;
begin
  inherited Create;
  FStopEvent := 0;
  FChangeHandle := INVALID_HANDLE_VALUE;
  FThread := nil;
  FPath := '';
  FGen := 0;
  FAlive := True;
end;

destructor TDirectoryWatcher.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TDirectoryWatcher.Close;
begin
  FAlive := False;
  StopWatcher;
  FPath := '';
end;

procedure TDirectoryWatcher.StopWatcher;
begin
  Inc(FGen);
  // Wakes a thread that has already published real handles below (past
  // setup, sitting in WaitForMultipleObjects) -- a no-op if FStopEvent is
  // still 0 because setup hasn't finished yet; the Gen bump above is what
  // that case relies on instead (see StartWatcher's published-handles
  // closure and the wait loop's own "while LocalGen = FGen" check).
  if FStopEvent <> 0 then
    SetEvent(FStopEvent);
  // No Th.WaitFor/Th.Free here on purpose: if the thread is still inside
  // DirectoryExists/FindFirstChangeNotification (an unresponsive network
  // drive), waiting for it would block the caller exactly like that
  // synchronous call used to when it ran inline. FreeOnTerminate lets the
  // TThread wrapper clean itself up whenever the underlying thread actually
  // finishes -- possibly never, harmlessly, if the drive never answers.
  FThread := nil;
  if (FChangeHandle <> 0) and (FChangeHandle <> INVALID_HANDLE_VALUE) then
  begin
    FindCloseChangeNotification(FChangeHandle);
    FChangeHandle := INVALID_HANDLE_VALUE;
  end;
  if FStopEvent <> 0 then
  begin
    CloseHandle(FStopEvent);
    FStopEvent := 0;
  end;
end;

procedure TDirectoryWatcher.StartWatcher(const APath: string);
var
  Path: string;
  Gen: Integer;
begin
  Path := ExcludeTrailingPathDelimiter(APath);
  if Path = '' then
  begin
    FPath := '';
    Exit;
  end;

  FPath := Path; // optimistic -- SetPath's same-path dedup check relies on it
  Inc(FGen);
  Gen := FGen;

  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      StopEv, ChangeH: THandle;
      Flags: DWORD;
      Handles: array[0..1] of THandle;
      WaitRes: DWORD;
      Notify: TDirWatchNotify;
      LocalGen: Integer;

      procedure QueueGiveUp;
      begin
        TThread.Queue(nil,
          procedure
          begin
            // FThread must be cleared here too (not just FPath) -- with
            // FreeOnTerminate, this TThread object is about to free itself
            // as this anonymous procedure returns, and SetPath's "already
            // watching this path" dedup check tests Assigned(FThread).
            // Guarded by Gen so a newer SetPath's own (different) thread
            // reference is never clobbered.
            if FAlive and (LocalGen = FGen) then
            begin
              FPath := '';
              FThread := nil;
            end;
          end);
      end;

    begin
      LocalGen := Gen;

      // The slow part: DirectoryExists/FindFirstChangeNotification touch the
      // actual filesystem and can block for a long time on an unresponsive
      // network drive. This used to run inline in StartWatcher, on whatever
      // thread called SetPath -- TDualPanelWindow.SyncDirWatches, on every
      // single navigation (called from NavigateSideTo/LoadSide), which is
      // the UI thread. Runs here instead; setup completion/failure is
      // published back to the main thread below, matching
      // uPanelModel.TFilePanelModel's async pattern -- FPath/FStopEvent/
      // FChangeHandle/FGen are only ever written on the main thread, so
      // there's no cross-thread field race despite the setup itself running
      // in the background.
      if not DirectoryExists(WinApiPath(Path)) then
      begin
        QueueGiveUp;
        Exit;
      end;

      Flags := FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
        FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE or
        FILE_NOTIFY_CHANGE_ATTRIBUTES;
      ChangeH := FindFirstChangeNotification(PChar(WinApiPath(Path)), False, Flags);
      if ChangeH = INVALID_HANDLE_VALUE then
      begin
        QueueGiveUp;
        Exit;
      end;

      StopEv := CreateEvent(nil, True, False, nil);
      if StopEv = 0 then
      begin
        FindCloseChangeNotification(ChangeH);
        QueueGiveUp;
        Exit;
      end;

      // Publish (or, if a newer SetPath/Close already superseded this
      // attempt while we were blocked in setup, tear down instead of
      // publishing stale handles). Fire-and-forget: the wait loop below
      // uses its own local Handles[], it does not need this to have run yet.
      TThread.Queue(nil,
        procedure
        begin
          if FAlive and (LocalGen = FGen) then
          begin
            FStopEvent := StopEv;
            FChangeHandle := ChangeH;
          end
          else
          begin
            FindCloseChangeNotification(ChangeH);
            CloseHandle(StopEv);
          end;
        end);

      Handles[0] := StopEv;
      Handles[1] := ChangeH;
      while LocalGen = FGen do
      begin
        WaitRes := WaitForMultipleObjects(2, @Handles[0], False, INFINITE);
        if WaitRes = WAIT_OBJECT_0 then
          Break;
        if WaitRes <> WAIT_OBJECT_0 + 1 then
          Break;

        // Drain + debounce bursty FS events (~300 ms quiet window).
        repeat
          FindNextChangeNotification(ChangeH);
          WaitRes := WaitForMultipleObjects(2, @Handles[0], False, 300);
          if WaitRes = WAIT_OBJECT_0 then
            Exit;
        until WaitRes <> WAIT_OBJECT_0 + 1;

        if LocalGen <> FGen then
          Exit;
        Notify := FOnChanged;
        if Assigned(Notify) then
          TThread.Queue(nil,
            procedure
            begin
              if not FAlive or (LocalGen <> FGen) then
                Exit;
              if Assigned(Notify) then
                Notify();
            end);
      end;
    end);
  FThread.FreeOnTerminate := True;
  FThread.Start;
end;

procedure TDirectoryWatcher.SetPath(const APath: string);
var
  Path: string;
begin
  // NormalizeLocalPath (uVfsTypes.pas), not System.SysUtils.ExpandFileName:
  // ExpandFileName on a bare drive letter ("P:", which is what's left after
  // ExcludeTrailingPathDelimiter turns "P:\" into "P:") calls
  // GetFullPathName, which resolves relative to that drive's own
  // per-process current-directory -- and on an unresponsive network drive
  // that lookup itself can block for a very long time, even though
  // GetFullPathName never touches an ordinary (non-drive-root) path's
  // target filesystem. NormalizeLocalPath already special-cases bare
  // drive letters and drive roots to skip that call entirely (see its own
  // comment in uVfsTypes.pas); this is the exact same class of bug as
  // ResolveLocalDirPath's GetFileAttributes reorder, just hiding behind a
  // different Win32 call.
  Path := NormalizeLocalPath(APath);
  if Path <> '' then
    Path := ExcludeTrailingPathDelimiter(Path);
  if SameText(Path, FPath) and Assigned(FThread) then
    Exit;
  StopWatcher;
  if Path = '' then
  begin
    FPath := '';
    Exit;
  end;
  StartWatcher(Path);
end;

end.
