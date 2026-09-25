program TestConsoleBuffer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uConsoleBuffer in '..\..\Core\uConsoleBuffer.pas',
  uANSIParser in '..\..\Core\uANSIParser.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas';

procedure Expect(const AActual, AExpected, AMsg: string);
begin
  if AActual = AExpected then
    Writeln('  OK  ', AMsg)
  else
    raise Exception.CreateFmt('FAIL %s: expected "%s", got "%s"', [AMsg, AExpected, AActual]);
end;

procedure TestReadlineBackspace;
var
  Buf: TConsoleBuffer;
  Line: string;
begin
  Writeln('TestReadlineBackspace');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('user@host:~$ ');
    Buf.AppendOutput('ls');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'user@host:~$ ls', 'typed command');

    // readline redraw after backspace: CR + shorter line + EL
    Buf.AppendOutput(#13'user@host:~$ l'#27'[K');
    Line := Buf.GetLine(Buf.LineCount - 1);
    Expect(Line, 'user@host:~$ l', 'readline backspace redraw');

    Buf.AppendOutput(#13'user@host:~$ '#27'[K');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'user@host:~$ ', 'backspace to prompt');
  finally
    Buf.Free;
  end;
end;

procedure TestEchoBackspace;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestEchoBackspace');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('abc');
    Buf.AppendOutput(#8);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'ab', 'BS deletes one char');
    Buf.AppendOutput(#127);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'a', 'DEL deletes one char');
  finally
    Buf.Free;
  end;
end;

procedure TestTabExpansion;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestTabExpansion');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('ab'#9'x');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'ab      x', 'tab expands to 8-col stop');
    Buf.AppendOutput(#13#10'1234567'#9'z');
    Expect(Buf.GetLine(Buf.LineCount - 1), '1234567 z', 'tab from col 7 advances one cell');
  finally
    Buf.Free;
  end;
end;

procedure TestLocalInputAfterCmdPrompt;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestLocalInputAfterCmdPrompt');
  Buf := TConsoleBuffer.Create;
  try
    // Prompt with trailing newline (typical cmd pipe output).
    Buf.AppendOutput('D:\Work\Delphi>'#13#10);
    Buf.AppendOutput('d');
    Buf.AppendOutput('i');
    Buf.AppendOutput('r');
    Expect(Buf.GetInputAfterPrompt, 'dir', 'command after prompt on next line');

    Buf.Clear;
    // Prompt without trailing newline — local echo stays on the prompt line.
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('d');
    Buf.AppendOutput('i');
    Buf.AppendOutput('r');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\Delphi>dir', 'typed on prompt line');
    Expect(Buf.GetInputAfterPrompt, 'dir', 'command on same line as prompt');
  finally
    Buf.Free;
  end;
end;

procedure TestSubmitOutputOnNextLine;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestSubmitOutputOnNextLine');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('dir');
    Buf.CommitInputLine;
    Buf.AppendOutput(' Volume in drive D is Work');
    Expect(Buf.GetLine(Buf.LineCount - 2), 'D:\Work\Delphi>dir', 'command line preserved');
    Expect(Buf.GetLine(Buf.LineCount - 1), ' Volume in drive D is Work', 'output on next line');
  finally
    Buf.Free;
  end;
end;

procedure TestPasteOntoPromptLine;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestPasteOntoPromptLine');
  Buf := TConsoleBuffer.Create;
  try
    // Pasting a "X:\..." path via the local-input path must land on the same
    // prompt line, not be mistaken for an incoming shell prompt (regression:
    // Shift+Insert paste used to jump to a new line below the prompt).
    Buf.AppendOutput('C:\Users\laex\AppData\Roaming\MTN2>');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2\ARCHITECTURE.md');
    Expect(Buf.GetLine(Buf.LineCount - 1),
      'C:\Users\laex\AppData\Roaming\MTN2>D:\Work\Delphi\MTN2\ARCHITECTURE.md',
      'pasted path stays on prompt line');

    Buf.Clear;
    // Pasting more text onto an already-started command must also extend the
    // same line (e.g. typed "cd " then pasted a path).
    Buf.AppendOutput('C:\Users\laex>');
    Buf.AppendLocalInput('cd ');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'C:\Users\laex>cd D:\Work\Delphi\MTN2',
      'paste onto an already-started command stays on the same line');

    Buf.Clear;
    // Real PTY output that looks like a fresh prompt must still split onto a
    // new line — the fix must not weaken this for genuine PTY chunks.
    // FixPromptNewlines also splits the glued-on command off the new prompt,
    // so "D:\Other>ls" itself lands on two rows (pre-existing, unrelated to
    // the local-input fix).
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('D:\Other>ls');
    Expect(Buf.GetLine(Buf.LineCount - 3), 'D:\Work\Delphi>', 'old prompt line untouched');
    Expect(Buf.GetLine(Buf.LineCount - 2), 'D:\Other>', 'PTY-echoed prompt still splits onto a new line');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'ls', 'glued-on command split off the new prompt');
  finally
    Buf.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Фаза D, Этап 2: grid-mode duplicates of the scenarios above, driven via
// AppendOutputEx(text, cols, rows) with real geometry -- that's what latches
// TConsoleBuffer's grid mode (EnableGridModeLocked). A 1-row grid is used for
// the single-line editing scenarios so "the current line" (row 0) is always
// also the *last* logical line (Buf.LineCount - 1), letting the exact same
// GetLine(Buf.LineCount - 1)-style assertions carry over unchanged from the
// legacy versions above -- the point of these tests is that behavior is
// unchanged, not that the addressing trick is exercised.
// ---------------------------------------------------------------------------

procedure TestReadlineBackspaceGrid;
var
  Buf: TConsoleBuffer;
  Line: string;
begin
  Writeln('TestReadlineBackspaceGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('user@host:~$ ', 80, 1);
    Buf.AppendOutputEx('ls', 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'user@host:~$ ls', 'typed command (grid)');

    Buf.AppendOutputEx(#13'user@host:~$ l'#27'[K', 80, 1);
    Line := Buf.GetLine(Buf.LineCount - 1);
    Expect(Line, 'user@host:~$ l', 'readline backspace redraw (grid)');

    Buf.AppendOutputEx(#13'user@host:~$ '#27'[K', 80, 1);
    // Unlike the legacy version of this assertion, the trailing space is not
    // expected here: GetLine's grid-row conversion must TrimRight (a fixed-
    // width row's unused cells are indistinguishable from a real trailing
    // space otherwise -- and NOT trimming would leak ~70 padding spaces into
    // GetInputAfterPrompt's extracted command text once real input exists on
    // the row, a materially worse problem than losing one cosmetic trailing
    // space on an as-yet-untyped prompt line).
    Expect(Buf.GetLine(Buf.LineCount - 1), 'user@host:~$', 'backspace to prompt (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestEchoBackspaceGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestEchoBackspaceGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('abc', 80, 1);
    // Real shells (WSL/bash) erase via the standard "\b <space> \b" idiom,
    // not a bare BS -- grid mode's Backspace is intentionally a
    // non-destructive cursor-only move for exactly that idiom (a bare BS
    // alone just moves the cursor, matching a real terminal; see
    // BackspaceEraseLocked). A bare-BS legacy-style duplicate of this test
    // would not apply: legacy's string model has no "cell past the cursor"
    // to leave stale, so a lone BS can be destructive there without harm.
    Buf.AppendOutputEx(#8' '#8, 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'ab', 'BS-space-BS erase idiom deletes one char (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestTabExpansionGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestTabExpansionGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('ab'#9'x', 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'ab      x', 'tab expands to 8-col stop (grid)');
    Buf.AppendOutputEx(#13#10'1234567'#9'z', 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 1), '1234567 z', 'tab from col 7 advances one cell (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestLocalInputAfterCmdPromptGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestLocalInputAfterCmdPromptGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('D:\Work\Delphi>'#13#10, 80, 1);
    Buf.AppendOutputEx('d', 80, 1);
    Buf.AppendOutputEx('i', 80, 1);
    Buf.AppendOutputEx('r', 80, 1);
    Expect(Buf.GetInputAfterPrompt, 'dir', 'command after prompt on next line (grid)');

    Buf.Clear;
    Buf.AppendOutputEx('D:\Work\Delphi>', 80, 1);
    Buf.AppendOutputEx('d', 80, 1);
    Buf.AppendOutputEx('i', 80, 1);
    Buf.AppendOutputEx('r', 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 1), 'D:\Work\Delphi>dir', 'typed on prompt line (grid)');
    Expect(Buf.GetInputAfterPrompt, 'dir', 'command on same line as prompt (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestSubmitOutputOnNextLineGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestSubmitOutputOnNextLineGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('D:\Work\Delphi>', 80, 1);
    Buf.AppendOutputEx('dir', 80, 1);
    Buf.CommitInputLine;
    Buf.AppendOutputEx(' Volume in drive D is Work', 80, 1);
    Expect(Buf.GetLine(Buf.LineCount - 2), 'D:\Work\Delphi>dir', 'command line preserved (grid)');
    Expect(Buf.GetLine(Buf.LineCount - 1), ' Volume in drive D is Work', 'output on next line (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestPasteOntoPromptLineGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestPasteOntoPromptLineGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('C:\Users\laex\AppData\Roaming\MTN2>', 80, 1);
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2\ARCHITECTURE.md');
    Expect(Buf.GetLine(Buf.LineCount - 1),
      'C:\Users\laex\AppData\Roaming\MTN2>D:\Work\Delphi\MTN2\ARCHITECTURE.md',
      'pasted path stays on prompt line (grid)');

    Buf.Clear;
    Buf.AppendOutputEx('C:\Users\laex>', 80, 1);
    Buf.AppendLocalInput('cd ');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2');
    Expect(Buf.GetLine(Buf.LineCount - 1), 'C:\Users\laex>cd D:\Work\Delphi\MTN2',
      'paste onto an already-started command stays on the same line (grid)');

    // Note: the legacy suite's third sub-scenario (a bare PTY chunk that
    // *looks* like a fresh prompt forcing a line split) is intentionally not
    // duplicated here -- that heuristic is legacy-only by design (see
    // AppendOutputEx's "(not FGridEnabled) and" guards); grid mode instead
    // relies on the real byte stream's own CR/LF/CUP to separate lines.
  finally
    Buf.Free;
  end;
end;

procedure TestGridModeNoPhantomBlankLine;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestGridModeNoPhantomBlankLine');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('hello', 80, 5);
    Expect(Buf.GetLine(0), 'hello',
      'first real grid-mode output lands at logical line 0 -- no phantom blank line ahead of it');
  finally
    Buf.Free;
  end;
end;

procedure TestEraseDisplayGridStaysEnabled;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestEraseDisplayGridStaysEnabled');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('before clear', 80, 5);
    Expect(Buf.GetLine(0), 'before clear', 'content present before ED');

    Buf.AppendOutputEx(#27'[2J', 80, 5);
    Expect(IntToStr(Buf.LineCount), IntToStr(5),
      'ED in grid mode resets to a fresh grid-only LineCount (archive emptied, grid re-alloc''d same size)');
    Expect(Buf.GetLine(0), '', 'content cleared by ED');

    // Session continues in grid mode after ED (Фаза D's explicit decision:
    // full-history-reset behavior is kept, but grid mode itself stays live).
    Buf.AppendOutputEx('after clear', 80, 5);
    Expect(Buf.GetLine(0), 'after clear', 'grid mode still live and writable after ED (not torn down)');
  finally
    Buf.Free;
  end;
end;

procedure TestResizePrimaryScreenGrid;
var
  Buf: TConsoleBuffer;
begin
  Writeln('TestResizePrimaryScreenGrid');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('line1', 10, 3);
    Buf.AppendOutputEx(#13#10'line2', 10, 3);
    Buf.AppendOutputEx(#13#10'line3', 10, 3);
    Expect(Buf.GetLine(0), 'line1', 'line1 before resize');
    Expect(Buf.GetLine(1), 'line2', 'line2 before resize');
    Expect(Buf.GetLine(2), 'line3', 'line3 before resize');

    // Shrink to 1 row: rows scrolled off the top must be archived, not lost.
    Buf.ResizePrimaryScreen(10, 1);
    Expect(Buf.GetLine(0), 'line1', 'line1 preserved in archive after shrink');
    Expect(Buf.GetLine(1), 'line2', 'line2 preserved in archive after shrink');
    Expect(Buf.GetLine(2), 'line3', 'line3 still visible in shrunk grid');

    // Grow back: existing content must survive uncorrupted.
    Buf.ResizePrimaryScreen(10, 5);
    Expect(Buf.GetLine(2), 'line3', 'content survives growth uncorrupted');
    Expect(Buf.GetLine(Buf.LineCount - 1), '', 'new bottom rows from growth are blank');
  finally
    Buf.Free;
  end;
end;

procedure TestGridAutoReflowOnSizeMismatch;
var
  Buf: TConsoleBuffer;
begin
  // Regression test: live testing found the grid still narrow (from an
  // earlier resize) when a chunk of real PTY output already claiming a
  // WIDER size arrived first -- PTY output lands on the reader thread while
  // ResizePrimaryScreen is called separately from the UI thread's
  // SyncPtySize, and the two can race. A prompt longer than the stale
  // width wrapped mid-string onto a bogus extra row (confirmed via a
  // byte-level trace: a 35-char prompt's cursor ended at row+1 col0
  // instead of row col35). AppendOutputEx must reflow itself against the
  // size each chunk claims, not rely solely on the separate resize call.
  Writeln('TestGridAutoReflowOnSizeMismatch');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('warmup', 10, 5);
    Expect(Buf.GetLine(0), 'warmup', 'warmup at narrow (10-col) width');

    Buf.AppendOutputEx(#13#10'0123456789ABCDEFGHIJ', 30, 5);
    // Row 1, not LineCount-1: the 5-row grid never fills up here (no rows
    // ever get archived), so the freshly-written line stays exactly where
    // the single CR+LF put it -- the bottom grid row (LineCount-1) is a
    // separate, still-blank row further down.
    Expect(Buf.GetLine(1), '0123456789ABCDEFGHIJ',
      'a 20-char line right after a claimed resize to 30 cols must not wrap at the stale 10-col width');
  finally
    Buf.Free;
  end;
end;

procedure TestGridModePromptNotSplitByOscTitle;
var
  Buf: TConsoleBuffer;
  LineIdx, Col: Integer;
begin
  // Regression test: real conhost always follows a freshly-drawn prompt with
  // an OSC window-title sequence (ESC ]0;...BEL). FixPromptNewlines (a
  // legacy-only workaround, mutating the raw byte stream before it even
  // reaches the parser) used to run unconditionally and mistake that OSC
  // sequence for "real command text glued onto the prompt", injecting a
  // synthetic CRLF there -- confirmed via a byte-level trace: the cursor
  // ended one row below the prompt's actual end even though the grid was
  // already wide enough that no auto-wrap could explain it. Grid mode must
  // trust the real byte stream's own CR/LF/CUP, not a legacy heuristic's
  // rewrite of it.
  Writeln('TestGridModePromptNotSplitByOscTitle');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx(#27'[2J'#27'[HC:\Users\laex\AppData\Roaming\MTN2>'#27']0;C:\WINDOWS\SYSTEM32\cmd.exe'#7, 80, 5);
    Expect(Buf.GetLine(0), 'C:\Users\laex\AppData\Roaming\MTN2>', 'prompt text stays on row 0');
    Buf.GetInputCursor(LineIdx, Col);
    Expect(IntToStr(LineIdx), IntToStr(0), 'cursor stays on row 0 after the prompt + OSC title, not pushed to row 1');
    Expect(IntToStr(Col), IntToStr(35), 'cursor sits right after the prompt text, not reset to column 0');
  finally
    Buf.Free;
  end;
end;

procedure TestGetInputCursorAfterUnfollow;
var
  Buf: TConsoleBuffer;
  LineIdx, Col: Integer;
begin
  // Mouse-down on the console unpins FollowTail so scrollback selection can
  // start. The PTY write cursor must still be reported — otherwise the
  // insert caret vanishes on click even when the prompt is still on screen.
  Writeln('TestGetInputCursorAfterUnfollow');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx(#27'[2J'#27'[HC:\Users\laex\AppData\Roaming\MTN2>'#27']0;C:\WINDOWS\SYSTEM32\cmd.exe'#7, 80, 5);
    Buf.FollowTail := False;
    Expect(BoolToStr(Buf.GetInputCursor(LineIdx, Col), True), 'True',
      'GetInputCursor succeeds after FollowTail is cleared');
    Expect(IntToStr(LineIdx), IntToStr(0), 'cursor row unchanged after unfollow');
    Expect(IntToStr(Col), IntToStr(35), 'cursor col unchanged after unfollow');
  finally
    Buf.Free;
  end;
end;

begin
  try
    TestEchoBackspace;
    TestTabExpansion;
    TestReadlineBackspace;
    TestLocalInputAfterCmdPrompt;
    TestSubmitOutputOnNextLine;
    TestPasteOntoPromptLine;
    TestReadlineBackspaceGrid;
    TestEchoBackspaceGrid;
    TestTabExpansionGrid;
    TestLocalInputAfterCmdPromptGrid;
    TestSubmitOutputOnNextLineGrid;
    TestPasteOntoPromptLineGrid;
    TestGridModeNoPhantomBlankLine;
    TestEraseDisplayGridStaysEnabled;
    TestResizePrimaryScreenGrid;
    TestGridAutoReflowOnSizeMismatch;
    TestGridModePromptNotSplitByOscTitle;
    TestGetInputCursorAfterUnfollow;
    Writeln('TestConsoleBuffer passed.');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      Halt(1);
    end;
  end;
end.
