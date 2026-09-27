unit TestPsTwoEcho;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPsTwoEcho = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty,
  uShellProfiles;

var
  GAll: string;

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

{ TTestPsTwoEcho }

procedure TTestPsTwoEcho.Run;
begin
  GAll := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GAll := GAll + AText; end;
    Assert.IsTrue(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);

    WriteInput('echo hello1'#13#10);
    Pump(3000);
    System.Writeln('after1 tail=', Copy(GAll, 1, 80));

    WriteInput('echo hello2'#13#10);
    Pump(3000);
    System.Writeln('after2 len=', Length(GAll), ' err=', LastError, ' hello2=', Pos('hello2', GAll) > 0);

    WriteInput('echo hello3'#13#10);
    Pump(3000);
    System.Writeln('after3 len=', Length(GAll), ' hello3=', Pos('hello3', GAll) > 0);

    Terminate;
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsTwoEcho);

end.
