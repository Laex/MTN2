program TestCmdRepeatedDirNoLineLoss;

{$APPTYPE CONSOLE}

{ Фаза D regression test: manual testing during Stage 22 found that running
  `dir` twice in the same real cmd/ConPTY session could lose an output line
  on the second run. Root cause: real conhost uses CUP (absolute cursor
  positioning) for ordinary line-transitions, not just full-screen TUI apps;
  the legacy primary scrollback had no row-cursor to interpret CUP against,
  so two narrower heuristics (treat CUP's column as the cursor column; treat
  a CUP row change as "start a new line") were each tried and reverted --
  the second one fixed the first `dir`'s glued output but silently dropped a
  real line on the *second* `dir` in the same session, because conhost's row
  numbers wrap once its fixed viewport scrolls, which a row-change heuristic
  alone can't distinguish from a genuine new line.

  TPrimaryScreenGrid (uPrimaryScreenGrid.pas) fixes this by keeping a grid
  that scrolls on the exact same LF events conhost's own viewport does, so
  "row N" from a CUP and "row N" in the grid are the same visual line by
  construction, not by heuristic -- this test drives two `dir` runs in one
  real cmd session (via TConsoleBuffer.AppendOutputEx with real PtyCols/
  PtyRows, which is what latches grid mode) and asserts every per-file
  listing line from the first run also survives, verbatim, in the second. }

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  Winapi.Windows,
  uConPty in '..\Core\uConPty.pas',
  uShellProfiles in '..\Core\uShellProfiles.pas',
  uConsoleBuffer in '..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\Core\uANSIParser.pas',
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uPrimaryScreenGrid in '..\Core\uPrimaryScreenGrid.pas';

const
  cCols = 80;
  cRows = 25;

var
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

// Poll until the buffer's current line looks like a settled, finished
// prompt (ends with '>' and stays unchanged for a short window) -- same
// pattern as TestLineBufferedBackspace.dpr's WaitForPromptReady, needed
// because real conhost's prompt redraw/clear timing is not instantaneous.
function WaitForPromptReady(ATimeoutMs: Integer): Boolean;
const
  cSettleMs = 400;
var
  UntilTick, QuietDeadline: UInt64;
  LastLine, StableLine: string;
begin
  Result := False;
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
        Exit(True);
    end
    else
    begin
      StableLine := '';
      QuietDeadline := 0;
    end;
  end;
end;

// All non-blank buffer lines in [AFrom, Buf.LineCount) whose text matches one
// of the real per-file listing lines `dir` printed for AFileNames -- i.e. the
// part of `dir`'s output that must be byte-identical between two runs against
// an unchanged directory (unlike the volume/free-space summary lines, which
// legitimately can vary run to run).
function CapturePerFileLines(AFrom: Integer; const AFileNames: TArray<string>): TArray<string>;
var
  I: Integer;
  Line, Name: string;
  Found: TList<string>;
begin
  Found := TList<string>.Create;
  try
    for I := AFrom to Buf.LineCount - 1 do
    begin
      Line := Buf.GetLine(I);
      for Name in AFileNames do
        if Pos(Name, Line) > 0 then
        begin
          Found.Add(Line);
          Break;
        end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

begin
  Buf := TConsoleBuffer.Create;
  Pty := TConPtySession.Create;
  try
   try
    // Real per-file listing lines are keyed off the actual .dpr files in this
    // very directory (self-updating -- no hardcoded filename list to rot).
    var FileNames := TDirectory.GetFiles(GetCurrentDir, '*.dpr');
    var I: Integer;
    for I := 0 to High(FileNames) do
      FileNames[I] := ExtractFileName(FileNames[I]);
    Expect(Length(FileNames) >= 5, 'enough .dpr files in cwd to make a meaningful dir listing');

    Pty.OnOutput := procedure(const AText: string)
      begin
        // Real PtyCols/PtyRows -- exactly what latches TConsoleBuffer's grid
        // mode (EnableGridModeLocked), the mechanism under test.
        Buf.AppendOutputEx(AText, cCols, cRows);
      end;
    Assert(Pty.StartShell('cmd', GetCurrentDir, cCols, cRows), Pty.LastError);

    // Prime: conhost holds the initial prompt draw until forced through a
    // real WriteConsole call with actual text (see TestLineBufferedBackspace.dpr).
    var PrimeMarker := 'MTN2_PRIME_' + IntToStr(GetTickCount64);
    Pty.WriteInput('echo ' + PrimeMarker + #13#10);
    Expect(WaitForPromptReady(15000), 'prompt ready after priming');

    // --- Round 1: dir ------------------------------------------------------
    var Round1Start := Buf.LineCount;
    Pty.WriteInput('dir' + #13#10);
    Expect(WaitForPromptReady(15000), 'prompt ready after round 1 dir');
    var Round1Lines := CapturePerFileLines(Round1Start, FileNames);
    Writeln(Format('  round 1: %d per-file listing lines captured', [Length(Round1Lines)]));
    Expect(Length(Round1Lines) >= 5, 'round 1 dir produced real per-file output lines');

    // --- Round 2: dir again, same session -----------------------------------
    // This is exactly the scenario that lost a line before Фаза D: a second
    // CUP-driven prompt-to-output transition in the same conhost viewport.
    var Round2Start := Buf.LineCount;
    Pty.WriteInput('dir' + #13#10);
    Expect(WaitForPromptReady(15000), 'prompt ready after round 2 dir');
    var Round2Lines := CapturePerFileLines(Round2Start, FileNames);
    Writeln(Format('  round 2: %d per-file listing lines captured', [Length(Round2Lines)]));
    Expect(Length(Round2Lines) >= 5, 'round 2 dir produced real per-file output lines');

    // The actual regression check: every per-file line round 1 saw must
    // survive, verbatim, in round 2 -- against an unchanged directory these
    // are byte-identical if (and only if) no line was silently dropped.
    var Missing := 0;
    var Ln: string;
    for Ln in Round1Lines do
      if not TArray.Contains<string>(Round2Lines, Ln) then
      begin
        Inc(Missing);
        Writeln('  MISSING in round 2: [', Ln, ']');
      end;
    Expect(Missing = 0, Format('all %d round-1 lines survive in round 2 (0 missing)', [Length(Round1Lines)]));

    Pty.Terminate;
    Pump(200);
    Writeln('TestCmdRepeatedDirNoLineLoss passed.');
   except
     on E: Exception do
     begin
       Writeln('FAIL: ', E.Message);
       Halt(1);
     end;
   end;
  finally
    Pty.Free;
    Buf.Free;
  end;
end.
