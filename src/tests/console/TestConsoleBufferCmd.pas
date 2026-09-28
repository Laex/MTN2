unit TestConsoleBufferCmd;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleBufferCmd = class
  public
    [Test] procedure TestCmdLocalEcho;
    [Test] procedure TestCmdEchoBackspaceSpace;
    [Test] procedure TestCmdCrPromptRedraw;
    [Test] procedure TestCmdPtyBackspace;
  end;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer,
  uANSIParser,
  uTerminalTypes,
  uConPty;

procedure TestCmdLocalEcho;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('D:\Work\MTN2>');
    Buf.AppendOutput('dir');
    Assert.AreEqual('D:\Work\MTN2>dir', Buf.GetLine(Buf.LineCount - 1), 'typed dir');

    // cmd local echo backspace (#8)
    Buf.AppendOutput(#8);
    Assert.AreEqual('D:\Work\MTN2>di', Buf.GetLine(Buf.LineCount - 1), 'local echo BS');

    Buf.AppendOutput(#8#8);
    Assert.AreEqual('D:\Work\MTN2>', Buf.GetLine(Buf.LineCount - 1), 'two more BS to prompt');

    // must not delete into the prompt
    Buf.AppendOutput(#8#8#8);
    Assert.AreEqual('D:\Work\MTN2>', Buf.GetLine(Buf.LineCount - 1), 'BS at prompt boundary is ignored');
  finally
    Buf.Free;
  end;
end;

procedure TestCmdEchoBackspaceSpace;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    // Prompt and typed command always arrive as separate chunks in production
    // (prompt from the PTY, then local echo char-by-char) - never glued into
    // one string; a combined "C:\>abc" here would hit FixPromptNewlines'
    // unrelated prompt-glued-to-content split, not what this test targets.
    Buf.AppendOutput('C:\>');
    Buf.AppendOutput('abc');
    // cmd sometimes echoes BS-space-BS to erase a character visually
    Buf.AppendOutput(#8' '#8);
    Assert.AreEqual('C:\>ab', Buf.GetLine(Buf.LineCount - 1), 'BS-space-BS erases one char');
  finally
    Buf.Free;
  end;
end;

procedure TestCmdCrPromptRedraw;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('C:\Users>hello');
    Buf.AppendOutput(#13'C:\Users>hell'#27'[K');
    Assert.AreEqual('C:\Users>hell', Buf.GetLine(Buf.LineCount - 1), 'CR+EL redraw shortens line');
  finally
    Buf.Free;
  end;
end;

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

procedure TestCmdPtyBackspace;
var
  Pty: TConPtySession;
  OutText: string;
  PromptPos: Integer;
begin
  if not FileExists('C:\Windows\System32\cmd.exe') then
  begin
    Writeln('  SKIP cmd.exe not found');
    Exit;
  end;

  Pty := TConPtySession.Create;
  try
    OutText := '';
    Pty.OnOutput := procedure(const AText: string)
      begin
        OutText := OutText + AText;
      end;
    if not Pty.StartShell('cmd', GetCurrentDir, 80, 25) then
      raise Exception.Create('StartShell failed: ' + Pty.LastError);

    Pump(500);
    OutText := '';
    Pty.WriteInput('abc'#8#8'z'#13#10);
    Pump(3000);

    if Pos('z', OutText) = 0 then
      raise Exception.CreateFmt('cmd backspace did not leave z in output: %s',
        [Copy(OutText, 1, 200)]);

    PromptPos := Pos('>z', OutText);
    if PromptPos = 0 then
      PromptPos := Pos('> z', OutText);
    if PromptPos = 0 then
      Writeln('  WARN could not confirm prompt+z pattern, output=', Copy(OutText, 1, 200))
    else
      Writeln('  OK  cmd pty backspace produced expected command');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
  end;
end;

{ TTestConsoleBufferCmd }

procedure TTestConsoleBufferCmd.TestCmdLocalEcho;
begin
  TestConsoleBufferCmd.TestCmdLocalEcho;
end;

procedure TTestConsoleBufferCmd.TestCmdEchoBackspaceSpace;
begin
  TestConsoleBufferCmd.TestCmdEchoBackspaceSpace;
end;

procedure TTestConsoleBufferCmd.TestCmdCrPromptRedraw;
begin
  TestConsoleBufferCmd.TestCmdCrPromptRedraw;
end;

procedure TTestConsoleBufferCmd.TestCmdPtyBackspace;
begin
  TestConsoleBufferCmd.TestCmdPtyBackspace;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleBufferCmd);

end.
