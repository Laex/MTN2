unit TestPlatformChild;

{ A child process that stays alive and is driven over pipes. The programs are an
  stdin echo (findstr or cat) and a shell, present on both platforms. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPlatformChild = class
  public
    [Test] procedure TestStdinToStdoutRoundTrip;
    [Test] procedure TestMissingProgramFailsToStart;
    [Test] procedure TestKillEndsAChildThatWaitsForInput;
    [Test] procedure TestExtraEnvironmentReachesTheChild;
    [Test] procedure TestStderrIsSeparate;
  end;

implementation

uses
  System.SysUtils, uPlatformChild;

function ReadAll(AChild: IChildProcess; AErr: Boolean): string;
var
  Buf: array[0..1023] of Byte;
  N: Integer;
  B: TBytes;
begin
  SetLength(B, 0);
  repeat
    if AErr then
      N := AChild.ReadErr(Buf, SizeOf(Buf))
    else
      N := AChild.ReadOut(Buf, SizeOf(Buf));
    if N > 0 then
    begin
      SetLength(B, Length(B) + N);
      Move(Buf[0], B[Length(B) - N], N);
    end;
  until N = 0;
  Result := TEncoding.UTF8.GetString(B);
end;

function StartEcho(out AChild: IChildProcess): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := PlatformStartChild('findstr.exe', ['^'], '', [], AChild);
{$ELSE}
  Result := PlatformStartChild('cat', [], '', [], AChild);
{$ENDIF}
end;

function Shell(const ACommand: string; const AEnv: TArray<string>; out AChild: IChildProcess): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := PlatformStartChild('cmd.exe', ['/c', ACommand], '', AEnv, AChild);
{$ELSE}
  Result := PlatformStartChild('/bin/sh', ['-c', ACommand], '', AEnv, AChild);
{$ENDIF}
end;

procedure TTestPlatformChild.TestStdinToStdoutRoundTrip;
var
  Child: IChildProcess;
  Data: TBytes;
  Text: string;
begin
  Assert.IsTrue(StartEcho(Child), 'the echo program starts');
  Data := TEncoding.UTF8.GetBytes('b'#10'a'#10);
  Assert.IsTrue(Child.Write(Data[0], Length(Data)));
  Child.CloseInput;
  Text := StringReplace(ReadAll(Child, False), #13, '', [rfReplaceAll]);
  Assert.AreEqual('b'#10'a'#10, Text);
  Assert.IsTrue(Child.WaitExit(5000), 'the child ends after its input');
  Assert.AreEqual<Cardinal>(0, Child.ExitCode);
end;

procedure TTestPlatformChild.TestMissingProgramFailsToStart;
var
  Child: IChildProcess;
begin
  Assert.IsFalse(PlatformStartChild('mtn2-no-such-program-xyz', [], '', [], Child));
  Assert.IsNull(Child);
end;

procedure TTestPlatformChild.TestKillEndsAChildThatWaitsForInput;
var
  Child: IChildProcess;
  Buf: array[0..15] of Byte;
begin
  Assert.IsTrue(StartEcho(Child));
  Assert.IsFalse(Child.WaitExit(100), 'still waiting for input');
  Child.Kill;
  Assert.AreEqual(0, Child.ReadOut(Buf, SizeOf(Buf)), 'the output ends');
  Assert.IsTrue(Child.WaitExit(5000), 'the child is gone');
  Child.Kill;
end;

procedure TTestPlatformChild.TestExtraEnvironmentReachesTheChild;
var
  Child: IChildProcess;
  Text: string;
begin
{$IFDEF MSWINDOWS}
  Assert.IsTrue(Shell('echo %MTN2_CHILD_TEST%', ['MTN2_CHILD_TEST=hello'], Child));
{$ELSE}
  Assert.IsTrue(Shell('echo $MTN2_CHILD_TEST', ['MTN2_CHILD_TEST=hello'], Child));
{$ENDIF}
  Text := Trim(ReadAll(Child, False));
  Assert.AreEqual('hello', Text);
end;

procedure TTestPlatformChild.TestStderrIsSeparate;
var
  Child: IChildProcess;
begin
  Assert.IsTrue(Shell('echo oops 1>&2', [], Child));
  Assert.AreEqual('oops', Trim(ReadAll(Child, True)));
  Assert.AreEqual('', Trim(ReadAll(Child, False)));
end;

end.
