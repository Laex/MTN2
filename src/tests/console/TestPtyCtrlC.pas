unit TestPtyCtrlC;

{ Ctrl+C (ETX written to the pseudo console) stops the running command and
  leaves the shell alive; at an idle prompt it does nothing. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPtyCtrlC = class
  public
    [Test] procedure CtrlCStopsCommandAndKeepsShell;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows, uConPty;

var
  GOutput: string;
  GExited: Boolean;

procedure Pump(AMs: Integer);
var
  UntilTick: UInt64;
begin
  UntilTick := GetTickCount64 + UInt64(AMs);
  while GetTickCount64 < UntilTick do
  begin
    CheckSynchronize;
    Sleep(5);
  end;
end;

function WaitFor(const AMarker: string; ATimeoutMs: Integer): Boolean;
var
  UntilTick: UInt64;
begin
  UntilTick := GetTickCount64 + UInt64(ATimeoutMs);
  repeat
    Pump(50);
    if Pos(AMarker, GOutput) > 0 then
      Exit(True);
  until GetTickCount64 >= UntilTick;
  Result := False;
end;

procedure TTestPtyCtrlC.CtrlCStopsCommandAndKeepsShell;
var
  Pty: TConPtySession;
begin
  Pty := TConPtySession.Create;
  try
    GOutput := '';
    GExited := False;
    Pty.OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
      end;
    Pty.OnExit := procedure(ACode: DWORD)
      begin
        GExited := True;
      end;
    Assert.IsTrue(Pty.StartShell('cmd', GetCurrentDir, 80, 25), 'StartShell: ' + Pty.LastError);
    Pump(1500);

    Pty.WriteInput(#3);
    Pump(1000);
    Assert.IsFalse(GExited, 'Ctrl+C at an idle prompt leaves the shell running');

    Pty.WriteInput('ping -n 60 127.0.0.1' + #13);
    Pump(1500);
    Pty.WriteInput(#3);
    Pump(500);
    Pty.WriteInput('echo CTRLC_ALIVE_' + IntToStr(GetTickCount64) + #13);
    Assert.IsTrue(WaitFor('CTRLC_ALIVE_', 8000), 'the prompt returns after Ctrl+C stopped the command');
    Assert.IsFalse(GExited, 'Ctrl+C on a running command leaves the shell running');
  finally
    Pty.Terminate;
    Pty.Free;
  end;
end;

end.
