unit TestPsDirOnly2;

interface

uses
  DUnitX.TestFramework;

type
  // slow live shell session (~17s)
  [TestFixture, Category('Manual')]
  TTestPsDirOnly2 = class
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
  CmdLine, Wd: string;

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

{ TTestPsDirOnly2 }

procedure TTestPsDirOnly2.Run;
begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert.IsTrue(ResolveShellCmdLine(cShellProfilePowerShell, GetCurrentDir, CmdLine, Wd), 'resolve');
    System.Writeln('cmdline=', Copy(CmdLine, 1, 120));
    Assert.IsTrue(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);
    WriteInput('ls'#10);
    Pump(15000);
    System.Writeln('len=', Length(GOutput), ' Mode=', Pos('Mode', GOutput) > 0, ' err=', LastError);
    System.Writeln(Copy(GOutput, 1, 200));
    Terminate;
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsDirOnly2);

end.
