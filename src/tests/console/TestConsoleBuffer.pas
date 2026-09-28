unit TestConsoleBuffer;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleBuffer = class
  public
    [Test] procedure TestEchoBackspace;
    [Test] procedure TestTabExpansion;
    [Test] procedure TestReadlineBackspace;
    [Test] procedure TestLocalInputAfterCmdPrompt;
    [Test] procedure TestSubmitOutputOnNextLine;
    [Test] procedure TestPasteOntoPromptLine;
    [Test] procedure TestReadlineBackspaceGrid;
    [Test] procedure TestEchoBackspaceGrid;
    [Test] procedure TestTabExpansionGrid;
    [Test] procedure TestLocalInputAfterCmdPromptGrid;
    [Test] procedure TestSubmitOutputOnNextLineGrid;
    [Test] procedure TestPasteOntoPromptLineGrid;
    [Test] procedure TestGridModeNoPhantomBlankLine;
    [Test] procedure TestEraseDisplayGridStaysEnabled;
    [Test] procedure TestResizePrimaryScreenGrid;
    [Test] procedure TestGridAutoReflowOnSizeMismatch;
    [Test] procedure TestGridModePromptNotSplitByOscTitle;
    [Test] procedure TestGetInputCursorAfterUnfollow;
  end;

implementation

uses
  System.SysUtils,
  uConsoleBuffer,
  uANSIParser,
  uTerminalTypes;

procedure TestReadlineBackspace;
var
  Buf: TConsoleBuffer;
  Line: string;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('user@host:~$ ');
    Buf.AppendOutput('ls');
    Assert.AreEqual('user@host:~$ ls', Buf.GetLine(Buf.LineCount - 1), 'typed command');

    // readline redraw after backspace: CR + shorter line + EL
    Buf.AppendOutput(#13'user@host:~$ l'#27'[K');
    Line := Buf.GetLine(Buf.LineCount - 1);
    Assert.AreEqual('user@host:~$ l', Line, 'readline backspace redraw');

    Buf.AppendOutput(#13'user@host:~$ '#27'[K');
    Assert.AreEqual('user@host:~$ ', Buf.GetLine(Buf.LineCount - 1), 'backspace to prompt');
  finally
    Buf.Free;
  end;
end;

procedure TestEchoBackspace;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('abc');
    Buf.AppendOutput(#8);
    Assert.AreEqual('ab', Buf.GetLine(Buf.LineCount - 1), 'BS deletes one char');
    Buf.AppendOutput(#127);
    Assert.AreEqual('a', Buf.GetLine(Buf.LineCount - 1), 'DEL deletes one char');
  finally
    Buf.Free;
  end;
end;

procedure TestTabExpansion;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('ab'#9'x');
    Assert.AreEqual('ab      x', Buf.GetLine(Buf.LineCount - 1), 'tab expands to 8-col stop');
    Buf.AppendOutput(#13#10'1234567'#9'z');
    Assert.AreEqual('1234567 z', Buf.GetLine(Buf.LineCount - 1), 'tab from col 7 advances one cell');
  finally
    Buf.Free;
  end;
end;

procedure TestLocalInputAfterCmdPrompt;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    // Prompt with trailing newline (typical cmd pipe output).
    Buf.AppendOutput('D:\Work\Delphi>'#13#10);
    Buf.AppendOutput('d');
    Buf.AppendOutput('i');
    Buf.AppendOutput('r');
    Assert.AreEqual('dir', Buf.GetInputAfterPrompt, 'command after prompt on next line');

    Buf.Clear;
    // Prompt without trailing newline - local echo stays on the prompt line.
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('d');
    Buf.AppendOutput('i');
    Buf.AppendOutput('r');
    Assert.AreEqual('D:\Work\Delphi>dir', Buf.GetLine(Buf.LineCount - 1), 'typed on prompt line');
    Assert.AreEqual('dir', Buf.GetInputAfterPrompt, 'command on same line as prompt');
  finally
    Buf.Free;
  end;
end;

procedure TestSubmitOutputOnNextLine;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('dir');
    Buf.CommitInputLine;
    Buf.AppendOutput(' Volume in drive D is Work');
    Assert.AreEqual('D:\Work\Delphi>dir', Buf.GetLine(Buf.LineCount - 2), 'command line preserved');
    Assert.AreEqual(' Volume in drive D is Work', Buf.GetLine(Buf.LineCount - 1), 'output on next line');
  finally
    Buf.Free;
  end;
end;

procedure TestPasteOntoPromptLine;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    // Pasting a "X:\..." path via the local-input path must land on the same
    // prompt line, not be mistaken for an incoming shell prompt (regression:
    // Shift+Insert paste used to jump to a new line below the prompt).
    Buf.AppendOutput('C:\Users\user\AppData\Roaming\MTN2>');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2\ARCHITECTURE.md');
    Assert.AreEqual('C:\Users\user\AppData\Roaming\MTN2>D:\Work\Delphi\MTN2\ARCHITECTURE.md', Buf.GetLine(Buf.LineCount - 1), 'pasted path stays on prompt line');

    Buf.Clear;
    // Pasting more text onto an already-started command must also extend the
    // same line (e.g. typed "cd " then pasted a path).
    Buf.AppendOutput('C:\Users\user>');
    Buf.AppendLocalInput('cd ');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2');
    Assert.AreEqual('C:\Users\user>cd D:\Work\Delphi\MTN2', Buf.GetLine(Buf.LineCount - 1), 'paste onto an already-started command stays on the same line');

    Buf.Clear;
    // Real PTY output that looks like a fresh prompt must still split onto a
    // new line - the fix must not weaken this for genuine PTY chunks.
    // FixPromptNewlines also splits the glued-on command off the new prompt,
    // so "D:\Other>ls" itself lands on two rows (pre-existing, unrelated to
    // the local-input fix).
    Buf.AppendOutput('D:\Work\Delphi>');
    Buf.AppendOutput('D:\Other>ls');
    Assert.AreEqual('D:\Work\Delphi>', Buf.GetLine(Buf.LineCount - 3), 'old prompt line untouched');
    Assert.AreEqual('D:\Other>', Buf.GetLine(Buf.LineCount - 2), 'PTY-echoed prompt still splits onto a new line');
    Assert.AreEqual('ls', Buf.GetLine(Buf.LineCount - 1), 'glued-on command split off the new prompt');
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
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('user@host:~$ ', 80, 1);
    Buf.AppendOutputEx('ls', 80, 1);
    Assert.AreEqual('user@host:~$ ls', Buf.GetLine(Buf.LineCount - 1), 'typed command (grid)');

    Buf.AppendOutputEx(#13'user@host:~$ l'#27'[K', 80, 1);
    Line := Buf.GetLine(Buf.LineCount - 1);
    Assert.AreEqual('user@host:~$ l', Line, 'readline backspace redraw (grid)');

    Buf.AppendOutputEx(#13'user@host:~$ '#27'[K', 80, 1);
    // Unlike the legacy version of this assertion, the trailing space is not
    // expected here: GetLine's grid-row conversion must TrimRight (a fixed-
    // width row's unused cells are indistinguishable from a real trailing
    // space otherwise -- and NOT trimming would leak ~70 padding spaces into
    // GetInputAfterPrompt's extracted command text once real input exists on
    // the row, a materially worse problem than losing one cosmetic trailing
    // space on an as-yet-untyped prompt line).
    Assert.AreEqual('user@host:~$', Buf.GetLine(Buf.LineCount - 1), 'backspace to prompt (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestEchoBackspaceGrid;
var
  Buf: TConsoleBuffer;
begin
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
    Assert.AreEqual('ab', Buf.GetLine(Buf.LineCount - 1), 'BS-space-BS erase idiom deletes one char (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestTabExpansionGrid;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('ab'#9'x', 80, 1);
    Assert.AreEqual('ab      x', Buf.GetLine(Buf.LineCount - 1), 'tab expands to 8-col stop (grid)');
    Buf.AppendOutputEx(#13#10'1234567'#9'z', 80, 1);
    Assert.AreEqual('1234567 z', Buf.GetLine(Buf.LineCount - 1), 'tab from col 7 advances one cell (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestLocalInputAfterCmdPromptGrid;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('D:\Work\Delphi>'#13#10, 80, 1);
    Buf.AppendOutputEx('d', 80, 1);
    Buf.AppendOutputEx('i', 80, 1);
    Buf.AppendOutputEx('r', 80, 1);
    Assert.AreEqual('dir', Buf.GetInputAfterPrompt, 'command after prompt on next line (grid)');

    Buf.Clear;
    Buf.AppendOutputEx('D:\Work\Delphi>', 80, 1);
    Buf.AppendOutputEx('d', 80, 1);
    Buf.AppendOutputEx('i', 80, 1);
    Buf.AppendOutputEx('r', 80, 1);
    Assert.AreEqual('D:\Work\Delphi>dir', Buf.GetLine(Buf.LineCount - 1), 'typed on prompt line (grid)');
    Assert.AreEqual('dir', Buf.GetInputAfterPrompt, 'command on same line as prompt (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestSubmitOutputOnNextLineGrid;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('D:\Work\Delphi>', 80, 1);
    Buf.AppendOutputEx('dir', 80, 1);
    Buf.CommitInputLine;
    Buf.AppendOutputEx(' Volume in drive D is Work', 80, 1);
    Assert.AreEqual('D:\Work\Delphi>dir', Buf.GetLine(Buf.LineCount - 2), 'command line preserved (grid)');
    Assert.AreEqual(' Volume in drive D is Work', Buf.GetLine(Buf.LineCount - 1), 'output on next line (grid)');
  finally
    Buf.Free;
  end;
end;

procedure TestPasteOntoPromptLineGrid;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('C:\Users\user\AppData\Roaming\MTN2>', 80, 1);
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2\ARCHITECTURE.md');
    Assert.AreEqual('C:\Users\user\AppData\Roaming\MTN2>D:\Work\Delphi\MTN2\ARCHITECTURE.md', Buf.GetLine(Buf.LineCount - 1), 'pasted path stays on prompt line (grid)');

    Buf.Clear;
    Buf.AppendOutputEx('C:\Users\user>', 80, 1);
    Buf.AppendLocalInput('cd ');
    Buf.AppendLocalInput('D:\Work\Delphi\MTN2');
    Assert.AreEqual('C:\Users\user>cd D:\Work\Delphi\MTN2', Buf.GetLine(Buf.LineCount - 1), 'paste onto an already-started command stays on the same line (grid)');

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
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('hello', 80, 5);
    Assert.AreEqual('hello', Buf.GetLine(0), 'first real grid-mode output lands at logical line 0 -- no phantom blank line ahead of it');
  finally
    Buf.Free;
  end;
end;

procedure TestEraseDisplayGridStaysEnabled;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('before clear', 80, 5);
    Assert.AreEqual('before clear', Buf.GetLine(0), 'content present before ED');

    Buf.AppendOutputEx(#27'[2J', 80, 5);
    Assert.AreEqual(IntToStr(5), IntToStr(Buf.LineCount), 'ED in grid mode resets to a fresh grid-only LineCount (archive emptied, grid re-alloc''d same size)');
    Assert.AreEqual('', Buf.GetLine(0), 'content cleared by ED');

    // Session continues in grid mode after ED (Фаза D's explicit decision:
    // full-history-reset behavior is kept, but grid mode itself stays live).
    Buf.AppendOutputEx('after clear', 80, 5);
    Assert.AreEqual('after clear', Buf.GetLine(0), 'grid mode still live and writable after ED (not torn down)');
  finally
    Buf.Free;
  end;
end;

procedure TestResizePrimaryScreenGrid;
var
  Buf: TConsoleBuffer;
begin
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx('line1', 10, 3);
    Buf.AppendOutputEx(#13#10'line2', 10, 3);
    Buf.AppendOutputEx(#13#10'line3', 10, 3);
    Assert.AreEqual('line1', Buf.GetLine(0), 'line1 before resize');
    Assert.AreEqual('line2', Buf.GetLine(1), 'line2 before resize');
    Assert.AreEqual('line3', Buf.GetLine(2), 'line3 before resize');

    // Shrink to 1 row: rows scrolled off the top must be archived, not lost.
    Buf.ResizePrimaryScreen(10, 1);
    Assert.AreEqual('line1', Buf.GetLine(0), 'line1 preserved in archive after shrink');
    Assert.AreEqual('line2', Buf.GetLine(1), 'line2 preserved in archive after shrink');
    Assert.AreEqual('line3', Buf.GetLine(2), 'line3 still visible in shrunk grid');

    // Grow back: existing content must survive uncorrupted.
    Buf.ResizePrimaryScreen(10, 5);
    Assert.AreEqual('line3', Buf.GetLine(2), 'content survives growth uncorrupted');
    Assert.AreEqual('', Buf.GetLine(Buf.LineCount - 1), 'new bottom rows from growth are blank');
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
    Assert.AreEqual('warmup', Buf.GetLine(0), 'warmup at narrow (10-col) width');

    Buf.AppendOutputEx(#13#10'0123456789ABCDEFGHIJ', 30, 5);
    // Row 1, not LineCount-1: the 5-row grid never fills up here (no rows
    // ever get archived), so the freshly-written line stays exactly where
    // the single CR+LF put it -- the bottom grid row (LineCount-1) is a
    // separate, still-blank row further down.
    Assert.AreEqual('0123456789ABCDEFGHIJ', Buf.GetLine(1), 'a 20-char line right after a claimed resize to 30 cols must not wrap at the stale 10-col width');
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
    Buf.AppendOutputEx(#27'[2J'#27'[HC:\Users\user\AppData\Roaming\MTN2>'#27']0;C:\WINDOWS\SYSTEM32\cmd.exe'#7, 80, 5);
    Assert.AreEqual('C:\Users\user\AppData\Roaming\MTN2>', Buf.GetLine(0), 'prompt text stays on row 0');
    Buf.GetInputCursor(LineIdx, Col);
    Assert.AreEqual(IntToStr(0), IntToStr(LineIdx), 'cursor stays on row 0 after the prompt + OSC title, not pushed to row 1');
    Assert.AreEqual(IntToStr(35), IntToStr(Col), 'cursor sits right after the prompt text, not reset to column 0');
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
  // start. The PTY write cursor must still be reported - otherwise the
  // insert caret vanishes on click even when the prompt is still on screen.
  Writeln('TestGetInputCursorAfterUnfollow');
  Buf := TConsoleBuffer.Create;
  try
    Buf.AppendOutputEx(#27'[2J'#27'[HC:\Users\user\AppData\Roaming\MTN2>'#27']0;C:\WINDOWS\SYSTEM32\cmd.exe'#7, 80, 5);
    Buf.FollowTail := False;
    Assert.AreEqual('True', BoolToStr(Buf.GetInputCursor(LineIdx, Col), True), 'GetInputCursor succeeds after FollowTail is cleared');
    Assert.AreEqual(IntToStr(0), IntToStr(LineIdx), 'cursor row unchanged after unfollow');
    Assert.AreEqual(IntToStr(35), IntToStr(Col), 'cursor col unchanged after unfollow');
  finally
    Buf.Free;
  end;
end;

{ TTestConsoleBuffer }

procedure TTestConsoleBuffer.TestEchoBackspace;
begin
  TestConsoleBuffer.TestEchoBackspace;
end;

procedure TTestConsoleBuffer.TestTabExpansion;
begin
  TestConsoleBuffer.TestTabExpansion;
end;

procedure TTestConsoleBuffer.TestReadlineBackspace;
begin
  TestConsoleBuffer.TestReadlineBackspace;
end;

procedure TTestConsoleBuffer.TestLocalInputAfterCmdPrompt;
begin
  TestConsoleBuffer.TestLocalInputAfterCmdPrompt;
end;

procedure TTestConsoleBuffer.TestSubmitOutputOnNextLine;
begin
  TestConsoleBuffer.TestSubmitOutputOnNextLine;
end;

procedure TTestConsoleBuffer.TestPasteOntoPromptLine;
begin
  TestConsoleBuffer.TestPasteOntoPromptLine;
end;

procedure TTestConsoleBuffer.TestReadlineBackspaceGrid;
begin
  TestConsoleBuffer.TestReadlineBackspaceGrid;
end;

procedure TTestConsoleBuffer.TestEchoBackspaceGrid;
begin
  TestConsoleBuffer.TestEchoBackspaceGrid;
end;

procedure TTestConsoleBuffer.TestTabExpansionGrid;
begin
  TestConsoleBuffer.TestTabExpansionGrid;
end;

procedure TTestConsoleBuffer.TestLocalInputAfterCmdPromptGrid;
begin
  TestConsoleBuffer.TestLocalInputAfterCmdPromptGrid;
end;

procedure TTestConsoleBuffer.TestSubmitOutputOnNextLineGrid;
begin
  TestConsoleBuffer.TestSubmitOutputOnNextLineGrid;
end;

procedure TTestConsoleBuffer.TestPasteOntoPromptLineGrid;
begin
  TestConsoleBuffer.TestPasteOntoPromptLineGrid;
end;

procedure TTestConsoleBuffer.TestGridModeNoPhantomBlankLine;
begin
  TestConsoleBuffer.TestGridModeNoPhantomBlankLine;
end;

procedure TTestConsoleBuffer.TestEraseDisplayGridStaysEnabled;
begin
  TestConsoleBuffer.TestEraseDisplayGridStaysEnabled;
end;

procedure TTestConsoleBuffer.TestResizePrimaryScreenGrid;
begin
  TestConsoleBuffer.TestResizePrimaryScreenGrid;
end;

procedure TTestConsoleBuffer.TestGridAutoReflowOnSizeMismatch;
begin
  TestConsoleBuffer.TestGridAutoReflowOnSizeMismatch;
end;

procedure TTestConsoleBuffer.TestGridModePromptNotSplitByOscTitle;
begin
  TestConsoleBuffer.TestGridModePromptNotSplitByOscTitle;
end;

procedure TTestConsoleBuffer.TestGetInputCursorAfterUnfollow;
begin
  TestConsoleBuffer.TestGetInputCursorAfterUnfollow;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleBuffer);

end.
