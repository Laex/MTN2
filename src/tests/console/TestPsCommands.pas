unit TestPsCommands;

interface

uses
  DUnitX.TestFramework;

type
  // slow live shell session (~22s)
  [TestFixture, Category('Manual')]
  TTestPsCommands = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty,
  uShellProfiles;

var
  GOutput: string;
  Pty: TConPtySession;

procedure Pump(AMs: Integer);
var
  UntilTick: UInt64;
  Msg: TMsg;
begin
  UntilTick := GetTickCount64 + UInt64(AMs);
  while GetTickCount64 < UntilTick do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    CheckSynchronize;
    Sleep(5);
  end;
end;

procedure RunCmd(Pty: TConPtySession; const AName, ACmd: string);
var
  BeforeLen: Integer;
begin
  BeforeLen := Length(GOutput);
  GOutput := GOutput + Format('--- %s ---'#13#10, [AName]);
  Pty.WriteInput(ACmd + #13#10);
  Pump(5000);
  Writeln(AName, ': delta=', Length(GOutput) - BeforeLen,
    ' Mode=', Pos('Mode', GOutput) > BeforeLen);
end;

{ TTestPsCommands }

procedure TTestPsCommands.Run;
begin
  GOutput := '';
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Pty.OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert.IsTrue(Pty.StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), Pty.LastError);
    Pump(2000);
    RunCmd(Pty, 'echo', 'echo hello');
    RunCmd(Pty, 'dir', 'dir');
    RunCmd(Pty, 'gci', 'Get-ChildItem');
    RunCmd(Pty, 'pwd', 'pwd');
    System.Writeln('--- full ---');
    System.Writeln(GOutput);
    Pty.Terminate;
  finally
    Pty.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsCommands);

end.
