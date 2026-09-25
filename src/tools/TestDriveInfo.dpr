program TestDriveInfo;

{$APPTYPE CONSOLE}

{ Covers the non-blocking layer added on top of uDriveInfo.pas's original
  synchronous EnumLogicalDrives: EnumLogicalDrivesFast (letters/kind only,
  no GetVolumeInformation/GetDiskFreeSpaceEx) and CachedDriveInfo /
  TryCachedPathVolume (instant, background-refreshed). See the drive-bar
  hang this was written to fix: DrawPanelDriveLetterBar used to call the
  slow EnumLogicalDrives on every repaint, which could freeze the whole UI
  thread for as long as an unresponsive network drive took to answer. }

uses
  System.SysUtils, System.Classes,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDriveInfo in '..\Core\uDriveInfo.pas';

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

procedure TestFastEnumeration;
var
  Drives: TDriveInfoArray;
  I: Integer;
  HasC: Boolean;
begin
  Writeln('EnumLogicalDrivesFast');
  Drives := EnumLogicalDrivesFast;
  Expect(Length(Drives) > 0, 'at least one drive');
  HasC := False;
  for I := 0 to High(Drives) do
  begin
    Expect(Drives[I].KindLabel <> '', 'kind label filled without a slow query');
    Expect(Drives[I].TotalBytes = 0, 'fast path never touches GetDiskFreeSpaceEx');
    Expect(Drives[I].FreeBytes = 0, 'fast path never touches GetDiskFreeSpaceEx');
    if Drives[I].Letter = 'C' then
      HasC := True;
  end;
  Expect(HasC, 'C: is present');
end;

procedure TestFullEnumerationStillWorks;
var
  Drives: TDriveInfoArray;
  I, Idx: Integer;
begin
  Writeln('EnumLogicalDrives (full, unchanged)');
  Drives := EnumLogicalDrives;
  Idx := -1;
  for I := 0 to High(Drives) do
    if Drives[I].Letter = 'C' then
      Idx := I;
  Expect(Idx >= 0, 'C: found');
  Expect(Drives[Idx].TotalBytes > 0, 'full path fills TotalBytes for a real fixed disk');
  Expect(Drives[Idx].FsName <> '', 'full path fills FsName for a real fixed disk');
end;

procedure TestCachedDriveInfoWarmsUp;
const
  // Real per-drive GetVolumeInformation/GetDiskFreeSpaceEx calls, run on a
  // background thread, can legitimately take tens of seconds if any mounted
  // drive is slow/unresponsive (that slowness is exactly what this whole
  // caching layer exists to keep off the UI thread) -- so this deliberately
  // waits much longer than a "normal" test timeout instead of flaking.
  cWaitMs = 120000;
var
  First: TDriveInfoArray;
  RefreshedFlag: Boolean;
begin
  Writeln('CachedDriveInfo');
  RefreshedFlag := False;
  First := CachedDriveInfo(
    procedure
    begin
      RefreshedFlag := True;
    end);
  Expect(Length(First) > 0, 'first call returns instantly with a non-empty list');

  Expect(WaitUntil(
    function: Boolean
    begin
      Result := RefreshedFlag;
    end, cWaitMs), 'background refresh callback eventually fires');

  Expect(WaitUntil(
    function: Boolean
    var
      D: TDriveInfoArray;
      J: Integer;
    begin
      D := CachedDriveInfo(nil);
      Result := False;
      for J := 0 to High(D) do
        if (D[J].Letter = 'C') and (D[J].TotalBytes > 0) then
          Exit(True);
    end, cWaitMs), 'cache carries full detail (TotalBytes) for C: after refresh');
end;

procedure TestNoRedundantRefreshOnceWarm;
const
  cCalls = 50;
var
  I: Integer;
  Start: UInt64;
  ElapsedMs: UInt64;
  D: TDriveInfoArray;
  J: Integer;
  CTotalBytes: Int64;
begin
  // Regression test for two bugs reported in the field after this cache
  // shipped:
  //  1. CachedDriveInfo used to kick a brand-new background EnumLogicalDrives
  //     on EVERY call, including from within a just-finished refresh's own
  //     completion callback re-reading the cache -- an unresponsive drive
  //     (this machine has a flaky network P:) never let the pile of
  //     concurrent background threads settle.
  //  2. That one background pass queried every drive on a single thread, so
  //     an unresponsive P: also meant C:/D:/... never got their real data
  //     either -- the popup stayed on "letters only" forever.
  // Fixed by per-drive workers (a stuck P: cannot block C:'s result) plus
  // per-drive dedup (a drive that already answered, or is still being
  // asked, is never re-queried) -- both asserted here: many rapid repeat
  // calls must return instantly (no accidental synchronous work / pile-up)
  // and must not disturb an already-filled drive's data.
  Writeln('CachedDriveInfo: rapid repeat calls do not pile up or disturb filled data');
  D := CachedDriveInfo(nil);
  CTotalBytes := 0;
  for J := 0 to High(D) do
    if D[J].Letter = 'C' then
      CTotalBytes := D[J].TotalBytes;
  Expect(CTotalBytes > 0, 'precondition: C: already filled by TestCachedDriveInfoWarmsUp');

  Start := TThread.GetTickCount64;
  for I := 1 to cCalls do
    CachedDriveInfo(nil);
  ElapsedMs := TThread.GetTickCount64 - Start;
  Expect(ElapsedMs < 2000, Format(
    '%d rapid calls return instantly (%dms), not blocked piling up work', [cCalls, ElapsedMs]));

  D := CachedDriveInfo(nil);
  CTotalBytes := 0;
  for J := 0 to High(D) do
    if D[J].Letter = 'C' then
      CTotalBytes := D[J].TotalBytes;
  Expect(CTotalBytes > 0, 'C: is still filled after the rapid-call burst');
end;

procedure TestSlowDriveDoesNotBlockOthers;
const
  // Deliberately much shorter than the 120s given to the flaky P: elsewhere
  // in this file -- this is the actual bug report: with one shared
  // background thread looping over drives in enumeration order (C, D, E, F,
  // O, P, X), a stuck P: meant every drive *after* it (X: here) never got
  // its data either, forever. Per-drive workers must let X: answer on its
  // own regardless of what P: is doing.
  cWaitMs = 20000;
var
  Found: Boolean;
  Fast: TDriveInfoArray;
  K: Integer;
begin
  Writeln('A drive after the unresponsive one in enumeration order is not blocked by it');
  Found := False;
  Fast := EnumLogicalDrivesFast;
  for K := 0 to High(Fast) do
    if Fast[K].Letter = 'X' then
      Found := True;
  if not Found then
  begin
    Writeln('  SKIP  no X: drive on this machine to exercise the ordering case');
    Exit;
  end;
  Expect(WaitUntil(
    function: Boolean
    var
      Drives: TDriveInfoArray;
      J: Integer;
    begin
      Drives := CachedDriveInfo(nil);
      Result := False;
      for J := 0 to High(Drives) do
        if (Drives[J].Letter = 'X') and
           ((Drives[J].FsName <> '') or (Drives[J].TotalBytes <> 0)) then
          Exit(True);
    end, cWaitMs), 'X: (after P: in enumeration order) fills in well within 20s');
end;

procedure TestCachedPathVolume;
var
  Info: TDriveInfo;
  Ok: Boolean;
begin
  Writeln('TryCachedPathVolume');
  Ok := TryCachedPathVolume('C:\Windows', Info);
  Expect(Ok, 'resolves a real drive-letter path');
  Expect(Info.Letter = 'C', 'letter matches');

  Ok := TryCachedPathVolume('\\server\share\x', Info);
  Expect(not Ok, 'UNC path has no drive letter to resolve');
end;

procedure TestForceRefresh;
var
  Fired: Boolean;
begin
  Writeln('ForceRefreshDriveInfo');
  Fired := False;
  ForceRefreshDriveInfo(
    procedure
    begin
      Fired := True;
    end);
  Expect(WaitUntil(
    function: Boolean
    begin
      Result := Fired;
    end, 120000), 'forced refresh completes even though the cache was already warm');
end;

begin
  try
    TestFastEnumeration;
    TestFullEnumerationStillWorks;
    TestCachedDriveInfoWarmsUp;
    TestNoRedundantRefreshOnceWarm;
    TestSlowDriveDoesNotBlockOthers;
    TestForceRefresh;
    TestCachedPathVolume;
    Writeln('All DriveInfo tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
