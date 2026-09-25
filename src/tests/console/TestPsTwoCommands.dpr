program TestPsTwoCommands;

{$APPTYPE CONSOLE}

{ Regression test for two reported PS console bugs, both traced to
  FixPromptNewlines inserting a synthetic CRLF right after the prompt's own
  harmless trailing space ("PS D:\path> "), which then let the bare-CR
  callback reset the write cursor to column 0 and let the next character
  overwrite the prompt's first letter:
  1. Cursor jumping to a fresh line below the prompt as soon as typing starts.
  2. Second and later commands not executing (the corrupted prompt line no
     longer matches FindPromptEndIndex, so GetInputAfterPrompt can't find it).
  Drives the real TConsoleBuffer exactly the way TConsoleWindow's
  line-buffered input path does: local-echo one character at a time, then on
  "Enter" extract + rewrite + send the whole line, twice in a row. }

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  uConPty in '..\..\Core\uConPty.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas',
  uConsoleBuffer in '..\..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\..\Core\uANSIParser.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas';

var
  GOutput: string;
  Buf: TConsoleBuffer;
  Pty: TConPtySession;

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

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
    raise Exception.CreateFmt('FAIL: %s', [AMsg]);
end;

// Type ACmd one character at a time into Buf, exactly like
// TBaseConsoleWindow.HandleLineBufferedPtyInput's else-branch does.
procedure TypeLocally(const ACmd: string);
var
  C: Char;
begin
  for C in ACmd do
    Buf.AppendOutput(C);
end;

// Extract + PsPipeSafeCommand-rewrite + submit, exactly like
// HandleLineBufferedPtyInput's vkReturn case, then close the input line.
procedure SubmitLine;
var
  Cmd: string;
begin
  Cmd := Trim(Buf.GetInputAfterPrompt);
  Writeln('  extracted="', Cmd, '"');
  if Cmd <> '' then
  begin
    Cmd := PsPipeSafeCommand(Cmd);
    Pty.WriteInput(Cmd + ProfileReturnSeq(cShellProfilePowerShell));
  end
  else
    Pty.WriteInput(ProfileReturnSeq(cShellProfilePowerShell));
  Buf.CommitInputLine;
end;

begin
  GOutput := '';
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
    Pty.ProfileId := cShellProfilePowerShell;
    Pty.OnOutput := procedure(const AText: string)
      begin
        GOutput := GOutput + AText;
        Buf.AppendOutputEx(AText);
      end;
    Assert(Pty.StartShell(cShellProfilePowerShell, GetCurrentDir, 80, 25), Pty.LastError);
    Pump(2000);
    Writeln('prompt after startup: "', Buf.GetLine(Buf.LineCount - 1), '"');

    // --- Round 1: ls -----------------------------------------------------
    Writeln('--- round 1: ls ---');
    Expect(Trim(Buf.GetInputAfterPrompt) = '', 'nothing pending before typing round 1');
    TypeLocally('ls');
    Expect(Trim(Buf.GetInputAfterPrompt) = 'ls', 'round 1 local echo reads back as "ls"');
    SubmitLine;
    Pump(4000);
    Expect(Pos('TestPsTwoCommands.dpr', GOutput) > 0, 'round 1 ls produced real output');

    // --- Round 2: echo hello2 ---------------------------------------------
    Writeln('--- round 2: echo hello2 ---');
    Writeln('prompt after round 1: "', Buf.GetLine(Buf.LineCount - 1), '"');
    Expect(Trim(Buf.GetInputAfterPrompt) = '',
      'nothing pending before typing round 2 (prompt not corrupted by round 1)');
    TypeLocally('echo hello2');
    Expect(Trim(Buf.GetInputAfterPrompt) = 'echo hello2',
      'round 2 local echo reads back as "echo hello2" (this is what fails without the fix)');
    SubmitLine;
    Pump(4000);
    Expect(Pos('hello2', GOutput) > 0, 'round 2 echo actually ran');

    Pty.Terminate;
    Writeln('TestPsTwoCommands passed.');
  finally
    Pty.Free;
    Buf.Free;
  end;
end.
