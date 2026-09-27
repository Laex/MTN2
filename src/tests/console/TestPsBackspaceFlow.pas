unit TestPsBackspaceFlow;

interface

uses
  DUnitX.TestFramework;

type
  // fails: prompt not captured, backspace check sees "abc   "
  [TestFixture, Category('Manual')]
  TTestPsBackspaceFlow = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer,
  uANSIParser,
  uTerminalTypes,
  uConPty;

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

procedure DumpLine(const ABuf: TConsoleBuffer; const ALabel: string);
begin
  Writeln(ALabel, ': "', ABuf.GetLine(ABuf.LineCount - 1), '"');
end;

procedure SimulatePsSession;
var
  Buf: TConsoleBuffer;
  Pty: TConPtySession;
  ExpectedPrompt: string;
begin
  // The prompt reflects wherever this .exe actually runs from — do not
  // hardcode the repo root; that only matches if launched from there.
  ExpectedPrompt := 'PS ' + ExcludeTrailingPathDelimiter(GetCurrentDir) + '> ';
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        Buf.AppendOutputEx(AText);
      end;
    if not Pty.StartShell('powershell', GetCurrentDir, 80, 25) then
      raise Exception.Create(Pty.LastError);

    Pump(1200);
    DumpLine(Buf, 'prompt');

    // emulate keypress: send to shell, shell echoes back via OnOutput above
    Pty.WriteInput('abc');
    Pump(400);
    DumpLine(Buf, 'typed abc');

    Pty.WriteInput(#8#8#8);
    Pump(400);
    DumpLine(Buf, 'after BSx3');
    Assert.AreEqual(ExpectedPrompt, Buf.GetLine(Buf.LineCount - 1), 'backspace stops at prompt');

    Pty.WriteInput(#8#8#8);
    Pump(400);
    DumpLine(Buf, 'after BSx3 again');
    Assert.AreEqual(ExpectedPrompt, Buf.GetLine(Buf.LineCount - 1), 'prompt still intact');

    Pty.WriteInput(#8#8#8#8#8);
    Pump(600);
    DumpLine(Buf, 'after BSx5 more');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
    Buf.Free;
  end;
end;

{ TTestPsBackspaceFlow }

procedure TTestPsBackspaceFlow.Run;
begin
  SimulatePsSession;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsBackspaceFlow);

end.
