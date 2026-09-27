unit TestPsCmds;

interface

uses
  DUnitX.TestFramework;

type
  // slow live shell session (~50s)
  [TestFixture, Category('Manual')]
  TTestPsCmds = class
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

procedure TryOne(const ACmd: string);
begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert.IsTrue(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    Pump(2000);
    WriteInput(ACmd + #13#10);
    Pump(8000);
    System.Writeln(ACmd, ' -> len=', Length(GOutput), ' text=', Copy(StringReplace(GOutput, #13, '|', [rfReplaceAll]), 1, 120));
    Terminate;
  finally
    Free;
  end;
end;

{ TTestPsCmds }

procedure TTestPsCmds.Run;
begin
  TryOne('echo hello');
  TryOne('(Get-ChildItem).Count');
  TryOne('Get-ChildItem | Out-String -Width 200');
  TryOne('cmd /c dir');
  TryOne('Get-ChildItem');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsCmds);

end.
