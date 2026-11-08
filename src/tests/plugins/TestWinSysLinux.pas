unit TestWinSysLinux;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWinSysLinux = class
  public
    [Test] procedure TestProcStatReadsParentThreadsStartAndMemory;
    [Test] procedure TestProcStatKeepsParenthesesInTheName;
    [Test] procedure TestProcStatRejectsShortOrBrokenText;
    [Test] procedure TestUnitListSplitsFieldsAndDescription;
    [Test] procedure TestUnitListSkipsBulletAndBlankLines;
    [Test] procedure TestActiveStateMapsToServiceState;
    [Test] procedure TestShowValueFindsTheKeyLine;
    [Test] procedure TestMainPidsKeepOnlyUnitsWithAProcess;
  end;

implementation

uses
  System.SysUtils, uWinSysLinux;

const
  // pid (name) state ppid pgrp session tty tpgid flags minflt cminflt majflt
  // cmajflt utime stime cutime cstime priority nice threads itrealvalue
  // starttime vsize rss
  cStatTail = ' S 1 1 1 0 -1 4194560 100 0 0 0 5 6 0 0 20 0 7 0 12345 1000000 321';

procedure TTestWinSysLinux.TestProcStatReadsParentThreadsStartAndMemory;
var
  S: TProcStat;
begin
  S := ParseProcStat('42 (bash)' + cStatTail);
  Assert.IsTrue(S.Ok);
  Assert.AreEqual('bash', S.Comm);
  Assert.AreEqual('S', string(S.State));
  Assert.AreEqual(Cardinal(1), S.ParentPid);
  Assert.AreEqual(Cardinal(7), S.Threads);
  Assert.AreEqual(Int64(12345), S.StartTicks);
  Assert.AreEqual(Int64(321), S.RssPages);
end;

procedure TTestWinSysLinux.TestProcStatKeepsParenthesesInTheName;
var
  S: TProcStat;
begin
  S := ParseProcStat('7 (my (odd) prog)' + cStatTail);
  Assert.IsTrue(S.Ok);
  Assert.AreEqual('my (odd) prog', S.Comm);
  Assert.AreEqual(Int64(321), S.RssPages);
end;

procedure TTestWinSysLinux.TestProcStatRejectsShortOrBrokenText;
begin
  Assert.IsFalse(ParseProcStat('').Ok);
  Assert.IsFalse(ParseProcStat('42 bash S 1').Ok);
  Assert.IsFalse(ParseProcStat('42 (bash) S 1 2').Ok);
end;

procedure TTestWinSysLinux.TestUnitListSplitsFieldsAndDescription;
var
  Rows: TArray<TUnitRow>;
begin
  Rows := ParseUnitList('ssh.service loaded active running OpenBSD Secure Shell server'#10 +
    'cron.service loaded inactive dead Regular background program processing daemon'#10);
  Assert.AreEqual(NativeInt(2), NativeInt(Length(Rows)));
  Assert.AreEqual('ssh.service', Rows[0].Name);
  Assert.AreEqual('loaded', Rows[0].Load);
  Assert.AreEqual('active', Rows[0].Active);
  Assert.AreEqual('running', Rows[0].Sub);
  Assert.AreEqual('OpenBSD Secure Shell server', Rows[0].Description);
  Assert.AreEqual('inactive', Rows[1].Active);
end;

procedure TTestWinSysLinux.TestUnitListSkipsBulletAndBlankLines;
var
  Rows: TArray<TUnitRow>;
begin
  Rows := ParseUnitList(#10'* bad.service loaded failed failed Broken thing'#10'   '#10 +
    'short.service loaded'#10);
  Assert.AreEqual(NativeInt(1), NativeInt(Length(Rows)));
  Assert.AreEqual('bad.service', Rows[0].Name);
  Assert.AreEqual('failed', Rows[0].Active);
end;

procedure TTestWinSysLinux.TestActiveStateMapsToServiceState;
begin
  Assert.AreEqual(Cardinal(cSvcRunning), ServiceStateOfActive('active'));
  Assert.AreEqual(Cardinal(cSvcStartPending), ServiceStateOfActive('activating'));
  Assert.AreEqual(Cardinal(cSvcStopPending), ServiceStateOfActive('deactivating'));
  Assert.AreEqual(Cardinal(cSvcContinuePending), ServiceStateOfActive('reloading'));
  Assert.AreEqual(Cardinal(cSvcFailed), ServiceStateOfActive('failed'));
  Assert.AreEqual(Cardinal(cSvcStopped), ServiceStateOfActive('inactive'));
end;

procedure TTestWinSysLinux.TestShowValueFindsTheKeyLine;
const
  Text = 'Id=ssh.service'#10'Description=Secure Shell'#10'MainPID=0'#10;
begin
  Assert.AreEqual('Secure Shell', ShowValue(Text, 'Description'));
  Assert.AreEqual('0', ShowValue(Text, 'MainPID'));
  Assert.AreEqual('', ShowValue(Text, 'User'));
end;

procedure TTestWinSysLinux.TestMainPidsKeepOnlyUnitsWithAProcess;
var
  Pids: TArray<TUnitPid>;
begin
  Pids := ParseMainPids('MainPID=812'#10'Id=ssh.service'#10#10 +
    'Id=idle.service'#10'MainPID=0'#10#10 +
    'Id=cron.service'#13#10'MainPID=77'#13#10);
  Assert.AreEqual(2, Integer(Length(Pids)));
  Assert.AreEqual('ssh.service', Pids[0].Name);
  Assert.AreEqual(Cardinal(812), Pids[0].Pid);
  Assert.AreEqual('cron.service', Pids[1].Name);
  Assert.AreEqual(Cardinal(77), Pids[1].Pid);
  Assert.AreEqual(0, Integer(Length(ParseMainPids(''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinSysLinux);

end.
