unit TestDriveInfo;

{ Covers the non-blocking layer on top of uDriveInfo.pas's synchronous
  EnumLogicalDrives: EnumLogicalDrivesFast (letters/kind only, no
  GetVolumeInformation/GetDiskFreeSpaceEx) and CachedDriveInfo /
  TryCachedPathVolume (instant, background-refreshed). The drive bar is
  repainted often; calling the slow EnumLogicalDrives there would freeze
  the UI thread for as long as an unresponsive network drive takes to
  answer. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDriveInfo = class
  public
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestFastEnumeration;
    [Test] procedure TestFullEnumerationStillWorks;
    [Test] procedure TestCachedDriveInfoWarmsUp;
    [Test] procedure TestNoRedundantRefreshOnceWarm;
    [Test] procedure TestSlowDriveDoesNotBlockOthers;
    [Test] procedure TestForceRefresh;
    [Test] procedure TestCachedPathVolume;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uTerminalTypes,
  uVfsTypes,
  uDriveInfo,
  uTestRunner;

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
  Drives := EnumLogicalDrivesFast;
  Assert.IsTrue(Length(Drives) > 0, 'at least one drive');
  HasC := False;
  for I := 0 to High(Drives) do
  begin
    Assert.IsTrue(Drives[I].KindLabel <> '', 'kind label filled without a slow query');
    Assert.IsTrue(Drives[I].TotalBytes = 0, 'fast path never touches GetDiskFreeSpaceEx');
    Assert.IsTrue(Drives[I].FreeBytes = 0, 'fast path never touches GetDiskFreeSpaceEx');
    if Drives[I].Letter = 'C' then
      HasC := True;
  end;
  Assert.IsTrue(HasC, 'C: is present');
end;

var
  /// <summary>False while TestFullEnumerationStillWorks' worker is still
  /// blocked in EnumLogicalDrives -- see TTestDriveInfo.TearDownFixture.</summary>
  GFullEnumDone: Boolean = True;

procedure TestFullEnumerationStillWorks;
const
  // The synchronous full pass waits on every mapped drive in turn; an
  // unreachable SMB/WebDAV mapping can hold each call for minutes. Run it off
  // the main thread and skip (not fail) when such a drive eats the budget.
  cWaitMs = 30000;
var
  Drives: TDriveInfoArray;
  I, Idx: Integer;
begin
  GFullEnumDone := False;
  TThread.CreateAnonymousThread(
    procedure
    var
      Res: TDriveInfoArray;
    begin
      Res := EnumLogicalDrives;
      TThread.Synchronize(nil,
        procedure
        begin
          Drives := Res;
          GFullEnumDone := True;
        end);
    end).Start;
  if not WaitUntil(
    function: Boolean
    begin
      Result := GFullEnumDone;
    end, cWaitMs) then
  begin
    Writeln('  SKIP  full enumeration still blocked on an unresponsive drive after ',
      cWaitMs div 1000, 's');
    Exit;
  end;
  Idx := -1;
  for I := 0 to High(Drives) do
    if Drives[I].Letter = 'C' then
      Idx := I;
  Assert.IsTrue(Idx >= 0, 'C: found');
  Assert.IsTrue(Drives[Idx].TotalBytes > 0, 'full path fills TotalBytes for a real fixed disk');
  Assert.IsTrue(Drives[Idx].FsName <> '', 'full path fills FsName for a real fixed disk');
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
  RefreshedFlag := False;
  First := CachedDriveInfo(
    procedure
    begin
      RefreshedFlag := True;
    end);
  Assert.IsTrue(Length(First) > 0, 'first call returns instantly with a non-empty list');

  Assert.IsTrue(WaitUntil(
    function: Boolean
    begin
      Result := RefreshedFlag;
    end, cWaitMs), 'background refresh callback eventually fires');

  Assert.IsTrue(WaitUntil(
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
  // Regression test for two failure modes of the cache:
  //  1. Kicking a new background EnumLogicalDrives on EVERY call (including
  //     from a just-finished refresh's own completion callback re-reading
  //     the cache) piles up threads that never settle while a drive is
  //     unresponsive.
  //  2. Querying every drive on a single thread lets one unresponsive drive
  //     (say P:) keep C:/D:/... on "letters only" forever.
  // Guarded by per-drive workers (a stuck P: cannot block C:'s result) plus
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
  Assert.IsTrue(CTotalBytes > 0, 'precondition: C: already filled by TestCachedDriveInfoWarmsUp');

  Start := TThread.GetTickCount64;
  for I := 1 to cCalls do
    CachedDriveInfo(nil);
  ElapsedMs := TThread.GetTickCount64 - Start;
  Assert.IsTrue(ElapsedMs < 2000, Format(
    '%d rapid calls return instantly (%dms), not blocked piling up work', [cCalls, ElapsedMs]));

  D := CachedDriveInfo(nil);
  CTotalBytes := 0;
  for J := 0 to High(D) do
    if D[J].Letter = 'C' then
      CTotalBytes := D[J].TotalBytes;
  Assert.IsTrue(CTotalBytes > 0, 'C: is still filled after the rapid-call burst');
end;

procedure TestSlowDriveDoesNotBlockOthers;
const
  // Deliberately much shorter than the 120s given to the stuck P: elsewhere
  // in this file: with one shared
  // background thread looping over drives in enumeration order (C, D, E, F,
  // O, P, X), a stuck P: meant every drive after it (X: here) never got
  // its data either, forever. Per-drive workers must let X: answer on its
  // own regardless of what P: is doing.
  cWaitMs = 20000;
var
  Found: Boolean;
  Fast: TDriveInfoArray;
  K: Integer;
begin
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
  Assert.IsTrue(WaitUntil(
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
  Ok := TryCachedPathVolume('C:\Windows', Info);
  Assert.IsTrue(Ok, 'resolves a real drive-letter path');
  Assert.IsTrue(Info.Letter = 'C', 'letter matches');

  Ok := TryCachedPathVolume('\\server\share\x', Info);
  Assert.IsTrue(not Ok, 'UNC path has no drive letter to resolve');
end;

procedure TestForceRefresh;
var
  Fired: Boolean;
begin
  Fired := False;
  ForceRefreshDriveInfo(
    procedure
    begin
      Fired := True;
    end);
  Assert.IsTrue(WaitUntil(
    function: Boolean
    begin
      Result := Fired;
    end, 120000), 'forced refresh completes even though the cache was already warm');
end;

{ TTestDriveInfo }

procedure TTestDriveInfo.TearDownFixture;
begin
  // An abandoned EnumLogicalDrives worker that wakes during RTL shutdown
  // would allocate on a torn-down heap and crash the exit.
  if not GFullEnumDone then
    SkipFinalizationOnExit;
end;

procedure TTestDriveInfo.TestFastEnumeration;
begin
  TestDriveInfo.TestFastEnumeration;
end;

procedure TTestDriveInfo.TestFullEnumerationStillWorks;
begin
  TestDriveInfo.TestFullEnumerationStillWorks;
end;

procedure TTestDriveInfo.TestCachedDriveInfoWarmsUp;
begin
  TestDriveInfo.TestCachedDriveInfoWarmsUp;
end;

procedure TTestDriveInfo.TestNoRedundantRefreshOnceWarm;
begin
  TestDriveInfo.TestNoRedundantRefreshOnceWarm;
end;

procedure TTestDriveInfo.TestSlowDriveDoesNotBlockOthers;
begin
  TestDriveInfo.TestSlowDriveDoesNotBlockOthers;
end;

procedure TTestDriveInfo.TestForceRefresh;
begin
  TestDriveInfo.TestForceRefresh;
end;

procedure TTestDriveInfo.TestCachedPathVolume;
begin
  TestDriveInfo.TestCachedPathVolume;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDriveInfo);

end.
