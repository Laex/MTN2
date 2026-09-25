program TestLineBufferedBackspace;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math, Winapi.Windows,
  uConsoleBuffer in '..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\Core\uANSIParser.pas',
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas';

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

procedure Expect(const AActual, AExpected, AMsg: string);
begin
  if AActual = AExpected then
    Writeln('  OK  ', AMsg)
  else
    raise Exception.CreateFmt('FAIL %s: expected "%s", got "%s"', [AMsg, AExpected, AActual]);
end;

// Under real ConPTY, cmd.exe detects a genuine console and goes through a
// real console-mode startup: it prints its full banner (suppressed under the
// old fake-pipe backend) and appears to emit a clear-display sequence shortly
// after the first prompt is drawn, which our current (pre-alt-screen) erase
// handling treats as "wipe everything" regardless of ED mode. A short fixed
// wait can catch the prompt right before that clear wipes it out. Poll until
// the last line looks like a finished prompt AND stays unchanged for a short
// settle window, so a delayed clear doesn't race past this wait.
procedure WaitForPromptReady(Buf: TConsoleBuffer; ATimeoutMs: Integer);
const
  cSettleMs = 400;
var
  UntilTick, QuietDeadline: UInt64;
  LastLine, StableLine: string;
begin
  UntilTick := GetTickCount64 + UInt64(ATimeoutMs);
  StableLine := '';
  QuietDeadline := 0;
  while GetTickCount64 < UntilTick do
  begin
    Pump(100);
    LastLine := '';
    if Buf.LineCount > 0 then
      LastLine := Trim(Buf.GetLine(Buf.LineCount - 1));
    if (LastLine <> '') and LastLine.EndsWith('>') then
    begin
      if LastLine <> StableLine then
      begin
        StableLine := LastLine;
        QuietDeadline := GetTickCount64 + cSettleMs;
      end
      else if GetTickCount64 >= QuietDeadline then
        Exit;
    end
    else
    begin
      StableLine := '';
      QuietDeadline := 0;
    end;
  end;
end;

procedure TestBufferBackspaceAfterDir;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestBufferBackspaceAfterDir');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('C:\>');
    Buf.AppendOutputEx('dir');
    Expect(Buf.GetInputAfterPrompt, 'dir', 'typed dir');
    Buf.AppendOutputEx(#8);
    Expect(Buf.GetInputAfterPrompt, 'di', 'one backspace');
    Buf.AppendOutputEx(#8#8);
    Expect(Buf.GetInputAfterPrompt, '', 'backspace to prompt');
  finally
    Buf.Free;
  end;
end;

// Matches the marker only on a line that is NOT the echoed "echo <marker>"
// input line itself -- a real console echoes typed characters immediately,
// so a naive substring search across all recent lines matches that echo
// long before the command has actually executed and printed real output.
procedure WaitForMarker(Buf: TConsoleBuffer; const AMarker: string; ATimeoutMs: Integer);
var
  UntilTick: UInt64;
  LineText: string;
begin
  UntilTick := GetTickCount64 + UInt64(ATimeoutMs);
  while GetTickCount64 < UntilTick do
  begin
    Pump(100);
    if Buf.LineCount > 0 then
    begin
      var Li: Integer;
      for Li := Max(0, Buf.LineCount - 5) to Buf.LineCount - 1 do
      begin
        LineText := Buf.GetLine(Li);
        if (Pos(AMarker, LineText) > 0) and (Pos('echo ' + AMarker, LineText) = 0) then
          Exit;
      end;
    end;
  end;
  var Dump: string := '';
  var Lj: Integer;
  for Lj := Max(0, Buf.LineCount - 8) to Buf.LineCount - 1 do
    Dump := Dump + Format('  line[%d]=[%s]'#10, [Lj, Buf.GetLine(Lj)]);
  raise Exception.CreateFmt('Timeout waiting for marker "%s" (LineCount=%d)'#10'%s',
    [AMarker, Buf.LineCount, Dump]);
end;

// Stage 22: real ConPTY gives cmd a genuine console with real line-editing
// and echo from conhost itself, so the app no longer buffers keystrokes
// locally and constructs a line to submit on Enter (that used to be tested
// here as "line-buffered submit after edit"). Keeping that local simulation
// running on top of real echo double-echoed typed commands and corrupted the
// primary buffer's prompt-tracking heuristics (confirmed by manual testing:
// "dir" appearing twice, garbled `dir` output). cmd now uses the same raw
// char-by-char passthrough WSL always used successfully; this test verifies
// that still executes commands correctly end-to-end.
procedure TestCmdRawPassthroughSmoke;
var
  Buf: TConsoleBuffer;
  Pty: TConPtySession;
  OutText, PrimeMarker, DoneMarker, CmdText: string;
  Ci: Integer;
begin
  Writeln('TestCmdRawPassthroughSmoke');
  OutText := '';
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.OnOutput := procedure(const AText: string)
      begin
        OutText := OutText + AText;
        Buf.AppendOutputEx(AText);
      end;
    if not Pty.StartShell('cmd', GetCurrentDir, 80, 25) then
      raise Exception.Create(Pty.LastError);
    // ConPTY/conhost appears to hold the initial prompt draw until cmd is
    // forced through a real WriteConsole call with actual text -- confirmed
    // by TestPtyLifecycle, which primes with "echo <marker>" and reliably
    // sees real text; a bare Enter (no text output) was NOT enough to flush
    // it (confirmed empirically -- still zero prompt text after 5s).
    PrimeMarker := 'MTN2_PRIME_' + IntToStr(GetTickCount64);
    Pty.WriteInput('echo ' + PrimeMarker + #13#10);
    WaitForMarker(Buf, PrimeMarker, 15000);
    WaitForPromptReady(Buf, 15000);

    // Type "echo <marker>" one character at a time -- exactly what SendRaw
    // does per keystroke now that cmd is on the same raw-passthrough path
    // as WSL; no local buffering happens on the app side anymore.
    DoneMarker := 'MTN2_DONE_' + IntToStr(GetTickCount64);
    CmdText := 'echo ' + DoneMarker;
    for Ci := 1 to Length(CmdText) do
      Pty.WriteInput(CmdText[Ci]);
    Pty.WriteInput(#13#10);

    WaitForMarker(Buf, DoneMarker, 15000);
    Writeln('  OK  raw char-by-char passthrough executes command');

    Pty.Terminate;
    Pump(200);
  finally
    Pty.Free;
    Buf.Free;
  end;
end;

begin
  try
    Assert(not ProfileUsesLineBufferedInput('cmd'),
      'cmd must use raw passthrough now (real ConPTY gives it a genuine console)');
    TestBufferBackspaceAfterDir;
    TestCmdRawPassthroughSmoke;
    Writeln('TestLineBufferedBackspace passed.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
