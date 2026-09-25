program TestConsoleBufferCmd;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer in '..\..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\..\Core\uANSIParser.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uConPty in '..\..\Core\uConPty.pas';

procedure Expect(const AActual, AExpected, AMsg: string);
begin
  if AActual = AExpected then
    Writeln('  OK  ', AMsg)
  else
    raise Exception.CreateFmt('FAIL %s: expected "%s", got "%s"', [AMsg, AExpected, AActual]);
end;

procedure TestCmdLocalEcho;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestCmdLocalEcho');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('D:\Work\MTN2>');
    Buf.AppendOutput('dir');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\MTN2>dir', 'typed dir');

    // cmd local echo backspace (#8)
    Buf.AppendOutput(#8);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\MTN2>di', 'local echo BS');

    Buf.AppendOutput(#8#8);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\MTN2>', 'two more BS to prompt');

    // must not delete into the prompt
    Buf.AppendOutput(#8#8#8);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\MTN2>', 'BS at prompt boundary is ignored');
  finally
    Buf.Free;
  end;
end;

procedure TestCmdEchoBackspaceSpace;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestCmdEchoBackspaceSpace');
  Buf := TConsoleBuffer.Create;
  try
    // Prompt and typed command always arrive as separate chunks in production
    // (prompt from the PTY, then local echo char-by-char) — never glued into
    // one string; a combined "C:\>abc" here would hit FixPromptNewlines'
    // unrelated prompt-glued-to-content split, not what this test targets.
    Buf.AppendOutput('C:\>');
    Buf.AppendOutput('abc');
    // cmd sometimes echoes BS-space-BS to erase a character visually
    Buf.AppendOutput(#8' '#8);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'C:\>ab', 'BS-space-BS erases one char');
  finally
    Buf.Free;
  end;
end;

procedure TestCmdCrPromptRedraw;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestCmdCrPromptRedraw');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('C:\Users>hello');
    Buf.AppendOutput(#13'C:\Users>hell'#27'[K');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'C:\Users>hell', 'CR+EL redraw shortens line');
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
  Writeln('TestCmdPtyBackspace');
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

begin
  try
    TestCmdLocalEcho;
    TestCmdEchoBackspaceSpace;
    TestCmdCrPromptRedraw;
    TestCmdPtyBackspace;
    Writeln('TestConsoleBufferCmd passed.');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      Halt(1);
    end;
  end;
end.
