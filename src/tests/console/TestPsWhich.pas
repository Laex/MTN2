unit TestPsWhich;

interface

uses
  DUnitX.TestFramework;

type
  // slow live shell session (~38s)
  [TestFixture, Category('Manual')]
  TTestPsWhich = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConPty,
  uShellProfiles;

var
  Pty: TConPtySession;
  OutText: string;

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

procedure RunCmd(const ACmd: string);
begin
  OutText := '';
  Pty.OnOutput := procedure(const AText: string) begin OutText := OutText + AText; end;
  Pty.WriteInput(ACmd + #13#10);
  Pump(6000);
end;

{ TTestPsWhich }

procedure TTestPsWhich.Run;
begin
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Assert.IsTrue(Pty.StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), Pty.LastError);
    Pump(2000);

    RunCmd('echo hello');
    System.Writeln('echo: ', Pos('hello', OutText) > 0);

    RunCmd('dir');
    System.Writeln('dir len=', Length(OutText), ' Mode=', Pos('Mode', OutText) > 0);
    System.Writeln('dir tail=', Copy(OutText, Max(Length(OutText) - 60, 1), 60));

    RunCmd('Get-ChildItem');
    System.Writeln('gci len=', Length(OutText), ' Mode=', Pos('Mode', OutText) > 0);

    RunCmd('ls');
    System.Writeln('ls len=', Length(OutText), ' Mode=', Pos('Mode', OutText) > 0);

    RunCmd('cmd /c dir');
    System.Writeln('cmd dir len=', Length(OutText), ' Volume=', Pos('Volume', OutText) > 0);

    RunCmd('(Get-ChildItem).Count');
    System.Writeln('count: ', Trim(OutText));

    Pty.Terminate;
  finally
    Pty.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsWhich);

end.
