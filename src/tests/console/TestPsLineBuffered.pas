unit TestPsLineBuffered;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPsLineBuffered = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConPty,
  uShellProfiles,
  uConsoleBuffer,
  uANSIParser,
  uTerminalTypes;

var
  GOutput: string;
  Cmd: string;
  Buf: TConsoleBuffer;

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

{ TTestPsLineBuffered }

procedure TTestPsLineBuffered.Run;
begin
  GOutput := '';
  with TConPtySession.Create do
  try
    ProfileId := cShellProfilePowerShell;
    OnOutput := procedure(const AText: string) begin GOutput := GOutput + AText; end;
    Assert.IsTrue(StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), LastError);
    // Stage 22: real ConPTY gives PowerShell a genuine console with real
    // line-editing/echo from conhost, so the app no longer buffers
    // keystrokes locally -- PowerShell now uses the same raw passthrough
    // WSL always used. PsPipeSafeCommand's format-engine-hang mitigation
    // (tested below) is unrelated to that and still applies regardless.
    Assert.IsTrue(not ProfileUsesLineBufferedInput(cShellProfilePowerShell),
      'PowerShell must use raw passthrough now (real ConPTY gives it a genuine console)');
    Pump(2000);

    Buf := TConsoleBuffer.Create;
    try
      Buf.AppendOutput(GOutput);
      Buf.AppendOutput('l');
      Buf.AppendOutput('s');
      Cmd := PsPipeSafeCommand(Trim(Buf.GetInputAfterPrompt));
    finally
      Buf.Free;
    end;
    Assert.IsTrue(Cmd = '(Get-ChildItem).Name', 'PsPipeSafeCommand for ls');

    WriteInput(Cmd + ProfileReturnSeq(cShellProfilePowerShell));
    Pump(8000);

    if Pos('TestPsLineBuffered.pas', GOutput) = 0 then
      raise Exception.Create('ls did not execute with line-buffered PS input');
    Terminate;
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsLineBuffered);

end.
