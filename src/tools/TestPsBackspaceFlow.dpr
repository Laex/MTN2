program TestPsBackspaceFlow;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConsoleBuffer in '..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\Core\uANSIParser.pas',
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uConPty in '..\Core\uConPty.pas';

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
  Writeln('SimulatePsSession');
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
    Expect(Buf.GetLine(Buf.LineCount - 1), ExpectedPrompt, 'backspace stops at prompt');

    Pty.WriteInput(#8#8#8);
    Pump(400);
    DumpLine(Buf, 'after BSx3 again');
    Expect(Buf.GetLine(Buf.LineCount - 1), ExpectedPrompt, 'prompt still intact');

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

begin
  try
    SimulatePsSession;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
