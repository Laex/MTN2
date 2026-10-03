unit TestDualPanelCmdLine;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelCmdLine = class
  public
    [Test] procedure TestPathResolve;
    [Test] procedure TestCompletionHelpers;
    [Test] procedure TestTabAndHistory;
    [Test] procedure TestHistoryKeepsCurrentLine;
    [Test] procedure TestCtrlUpReturnsToPanel;
    [Test] procedure TestEnterReturnsFocusToPanel;
    [Test] procedure TestEscClearsThenReturnsToPanel;
    [Test] procedure TestCommandLineDraw;
    [Test] procedure TestInputLineInsertCaret;
    [Test] procedure TestInputLineCutClearsText;
    [Test] procedure TestInputLineWordsAndClicks;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Classes,
  uDualPanelCmdLine,
  uDualPanelCmd,
  uInputLine,
  uConfigLocation,
  uTerminalTypes,
  uVfsTypes,
  uTextEncoding;

type
  TCmdLineColorSpy = class
  public
    StripCalls, AccentCalls: Integer;
    StripFg, StripBg, AccFg, AccBg: TAlphaColor;
    procedure Strip(out AFg, ABg: TAlphaColor);
    procedure Accent(out AFg, ABg: TAlphaColor);
  end;

procedure TestPathResolve;
var
  URI: string;
  Resolved: Boolean;
begin
  Resolved := TryResolvePanelCommandPath('cd %APPDATA%', 'C:\', URI);
  Assert.IsTrue(Resolved, 'cd %APPDATA% should resolve to navigable URI');
  Assert.IsTrue(Pos('AppData', URI) > 0, 'URI should contain AppData');

  Resolved := TryResolvePanelCommandPath('dir /o', 'D:\Work', URI);
  Assert.IsTrue(not Resolved, 'dir /o must NOT be resolved as a directory path');

  Resolved := TryResolvePanelCommandPath('dir /w /p', 'D:\Work', URI);
  Assert.IsTrue(not Resolved, 'dir /w /p must NOT be resolved as a directory path');

  Resolved := TryResolvePanelCommandPath('git checkout feature/bar', 'D:\Work', URI);
  Assert.IsTrue(not Resolved, 'git command with slash and spaces must NOT be resolved as a directory path');

  // A name inserted by Ctrl+Enter: quoted when it has spaces.
  Assert.AreEqual('my file.txt', UnquoteSingleToken('"my file.txt"'), 'one quoted token unquoted');
  Assert.AreEqual('readme.md', UnquoteSingleToken('readme.md'), 'unquoted name unchanged');
  Assert.AreEqual('"a b" "c"', UnquoteSingleToken('"a b" "c"'), 'two quoted tokens stay a command');
  Resolved := TryResolvePanelCommandPath(UnquoteSingleToken('"D:\My Dir\a.txt"'), 'C:\', URI);
  Assert.IsTrue(Resolved, 'a quoted full path resolves like an unquoted one');
end;

procedure TestCompletionHelpers;
var
  Names, Matches: TArray<string>;
  NewText: string;
  NewCur: Integer;
  LongPath, Prefix: string;
begin
  Assert.IsTrue(CmdLineQuoteIfNeeded('readme.md') = 'readme.md', 'no quote plain');
  Assert.IsTrue(CmdLineQuoteIfNeeded('my file.txt') = '"my file.txt"', 'quote space');

  Assert.IsTrue(CmdLineExtractToken('dir re', 6) = 're', 'token at end');
  Assert.IsTrue(CmdLineExtractToken('dir "my fi', 10) = 'my fi', 'token in quote');

  Names := TArray<string>.Create('..', 'readme.md', 'Release', 'src');
  Matches := FilterCompletions(Names, 're');
  Assert.IsTrue(Length(Matches) = 2, 'filter re → readme + Release');
  Assert.IsTrue(SameText(Matches[0], 'readme.md') or SameText(Matches[0], 'Release'),
    'first match');

  Assert.IsTrue(CmdLineApplyCompletion('dir re', 6, 'readme.md', NewText, NewCur),
    'apply');
  Assert.IsTrue(NewText = 'dir readme.md', 'applied text');
  Assert.IsTrue(NewCur = Length(NewText), 'cursor at end of token');

  Assert.IsTrue(CmdLineApplyCompletion('dir ', 4, 'my file.txt', NewText, NewCur),
    'apply quoted');
  Assert.IsTrue(NewText = 'dir "my file.txt"', 'quoted apply');

  LongPath := 'D:\Work\Delphi\MTN2\src\tests\panels\TestDualPanelCmdLine.pas';
  Prefix := FormatCmdLinePrefix(LongPath, 30);
  Assert.IsTrue(Length(Prefix) <= 30, 'prefix within budget');
  Assert.IsTrue(Prefix.EndsWith('>'), 'prompt suffix');
  Assert.IsTrue(Pos('...', Prefix) > 0, 'long path compacted');

  Prefix := FormatCmdLinePrefix('C:\Work', 30);
  Assert.IsTrue(Prefix = 'C:\Work>', 'short path unchanged');
end;

procedure TCmdLineColorSpy.Strip(out AFg, ABg: TAlphaColor);
begin
  Inc(StripCalls);
  AFg := StripFg;
  ABg := StripBg;
end;

procedure TCmdLineColorSpy.Accent(out AFg, ABg: TAlphaColor);
begin
  Inc(AccentCalls);
  AFg := AccFg;
  ABg := AccBg;
end;

procedure TestCommandLineDraw;
var
  Colors: TInputLineColors;
  Spy: TCmdLineColorSpy;
  Host: TDualPanelCmdLineDrawHost;
  Grid: TTerminalGrid;
  Cmd: TInputLine;
  Prefix: string;
begin
  Assert.IsTrue(CmdLinePrefixMaxCells(80) = 26, 'width div 3');
  Assert.IsTrue(CmdLinePrefixMaxCells(3) = 3, 'min prompt budget');
  Assert.IsTrue(CmdLinePathLabel('recycle://C:/') = 'Recycle Bin', 'recycle title');
  Assert.IsTrue(CmdLinePathLabel('file:///C:/Work') = FileUriToPath('file:///C:/Work'),
    'file URI becomes path');

  ResolveCmdLineInputColors(False, $FF111111, $FF222222, $FF333333, $FF444444, Colors);
  Assert.IsTrue((Colors.Fg = $FF111111) and (Colors.SelFg = $FF111111) and
    (Colors.CaretBg = $FF222222), 'idle uses strip for caret');
  ResolveCmdLineInputColors(True, $FF111111, $FF222222, $FF333333, $FF444444, Colors);
  Assert.IsTrue((Colors.SelFg = $FF333333) and (Colors.CaretBg = $FF444444),
    'focused uses accent');

  Spy := TCmdLineColorSpy.Create;
  try
    Spy.StripFg := TAlphaColors.White;
    Spy.StripBg := TAlphaColors.Blue;
    Spy.AccFg := TAlphaColors.Black;
    Spy.AccBg := TAlphaColors.Aqua;
    Host := Default(TDualPanelCmdLineDrawHost);
    Host.ResolveStripColors := Spy.Strip;
    Host.ResolveFocusAccent := Spy.Accent;
    AllocTerminalGrid(Grid, 40, 3);
    ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
    Cmd := Default(TInputLine);
    Cmd.Text := 'dir';
    DrawDualPanelCommandLine(Host, Grid, 1, 40, 'file:///C:/Work', Cmd, False, True);
    Assert.IsTrue(Spy.StripCalls = 1, 'idle asks strip');
    Assert.IsTrue(Spy.AccentCalls = 0, 'idle skips accent');
    Prefix := FormatCmdLinePrefix(CmdLinePathLabel('file:///C:/Work'),
      CmdLinePrefixMaxCells(40));
    Assert.IsTrue(Grid[1][0].CharValue = Prefix[1], 'prefix starts the row');
    Assert.IsTrue(Grid[1][Length(Prefix)].CharValue = 'd', 'edit starts after prefix');

    Spy.StripCalls := 0;
    DrawDualPanelCommandLine(Host, Grid, 1, 40, 'file:///C:/Work', Cmd, True, True);
    Assert.IsTrue(Spy.AccentCalls = 1, 'focus asks accent');
  finally
    Spy.Free;
  end;
end;

procedure TestTabAndHistory;
var
  Mgr: TDualPanelCmdLineManager;
  Key: Word;
  Ch: Char;
  Submitted: string;
begin
  Submitted := '';
  Mgr := TDualPanelCmdLineManager.Create(
    procedure(const ACommand: string)
    begin
      Submitted := ACommand;
    end,
    nil);
  try
    Mgr.OnGetNames :=
      function: TArray<string>
      begin
        Result := TArray<string>.Create('alpha.txt', 'about.md', 'beta.txt');
      end;

    Mgr.InsertText('type a');
    Key := vkTab;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'Tab handled');
    Assert.IsTrue(Mgr.Text = 'type alpha.txt', 'Tab completes first match alpha.txt');

    Key := vkTab;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'Tab cycle');
    Assert.IsTrue(Mgr.Text = 'type about.md', 'Tab cycles to about.md');

    Key := vkReturn;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'Enter submit');
    Assert.IsTrue(Submitted = 'type about.md', 'submitted command');
    Assert.IsTrue(Mgr.HistoryCount >= 1, 'history pushed');

    Mgr.Clear;
    Key := vkUp;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'history up');
    Assert.IsTrue(Mgr.Text = 'type about.md', 'Up recalls last command');
  finally
    Mgr.Free;
  end;
end;

// Any command run from the command line (cd, a console command, a file)
// leaves the arrows to the panel: the line loses the focus on Enter.
procedure TestEnterReturnsFocusToPanel;
var
  Mgr: TDualPanelCmdLineManager;
  Key: Word;
  Ch: Char;
  FocusedInSubmit: Boolean;
begin
  FocusedInSubmit := True;
  Mgr := nil;
  Mgr := TDualPanelCmdLineManager.Create(
    procedure(const ACommand: string)
    begin
      FocusedInSubmit := Mgr.Focused;
    end,
    nil);
  try
    Mgr.InsertText('cd ..');
    Mgr.Focus;
    Key := vkReturn;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'Enter handled');
    Assert.IsFalse(Mgr.Focused, 'the panel has the focus after the command');
    Assert.IsFalse(FocusedInSubmit, 'already unfocused while the command runs');
  finally
    Mgr.Free;
  end;
end;

// Esc in the focused command line: clears the text first, then (empty line)
// gives the focus back to the panel.
procedure TestEscClearsThenReturnsToPanel;
var
  Mgr: TDualPanelCmdLineManager;
  Key: Word;
  Ch: Char;
begin
  Mgr := TDualPanelCmdLineManager.Create(nil, nil);
  try
    Mgr.InsertText('dir');
    Mgr.Focus;
    Key := vkEscape;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'first Esc handled');
    Assert.IsTrue(Mgr.Text = '', 'first Esc clears the line');
    Assert.IsTrue(Mgr.Focused, 'the line keeps the focus');
    Key := vkEscape;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [], Ch), 'second Esc handled');
    Assert.IsFalse(Mgr.Focused, 'second Esc gives the focus to the panel');
  finally
    Mgr.Free;
  end;
end;

// Up and Down walk the history with the line being typed as its newest
// entry: up-up-down-down comes back to it, or to an empty line.
procedure TestHistoryKeepsCurrentLine;
var
  Mgr: TDualPanelCmdLineManager;

  procedure Press(AKey: Word);
  var
    Key: Word;
    Ch: Char;
  begin
    Key := AKey;
    Ch := #0;
    Mgr.HandleInput(Key, [], Ch);
  end;

begin
  Mgr := TDualPanelCmdLineManager.Create(procedure(const ACommand: string) begin end, nil);
  try
    Mgr.InsertText('first');
    Press(vkReturn);
    Mgr.Clear;
    Mgr.InsertText('second');
    Press(vkReturn);
    Mgr.Clear;
    Press(vkUp);
    Press(vkUp);
    Assert.AreEqual('first', Mgr.Text, 'two Up reach the older command');
    Press(vkDown);
    Press(vkDown);
    Assert.AreEqual('', Mgr.Text, 'two Down return to the empty line');

    Mgr.InsertText('draft');
    Press(vkUp);
    Press(vkUp);
    Press(vkDown);
    Press(vkDown);
    Assert.AreEqual('draft', Mgr.Text, 'two Down return to what was being typed');
  finally
    Mgr.Free;
  end;
end;

procedure TestCtrlUpReturnsToPanel;
var
  Mgr: TDualPanelCmdLineManager;
  Key: Word;
  Ch: Char;
begin
  Mgr := TDualPanelCmdLineManager.Create(nil, nil);
  try
    Mgr.InsertText('dir');
    Mgr.Focus;
    Assert.IsTrue(Mgr.Focused, 'Ctrl+Down equivalent focuses cmdline');
    Key := vkUp;
    Ch := #0;
    Assert.IsTrue(Mgr.HandleInput(Key, [ssCtrl], Ch), 'Ctrl+Up handled');
    Assert.IsTrue(not Mgr.Focused, 'Ctrl+Up returns focus to the file panel');
    Assert.IsTrue(Mgr.Text = 'dir', 'Ctrl+Up keeps the command text');
    Assert.IsTrue(Key = 0, 'Ctrl+Up consumes AKey');
    Assert.IsTrue(Ch = #0, 'Ctrl+Up consumes AKeyChar');
  finally
    Mgr.Free;
  end;
end;

procedure TestInputLineCutClearsText;
var
  Line: TInputLine;
  Key: Word;
  Ch: Char;
begin
  Line := InputLineEmpty;
  InputLineSetText(Line, 'hello', True);
  Line.SelAnchor := 0;
  Line.Cursor := 5;
  InputLineCut(Line);
  Assert.IsTrue(Line.Text = '', 'cut selection clears the line');

  Line := InputLineEmpty;
  InputLineSetText(Line, 'hello', True);
  Line.SelAnchor := 0;
  Line.Cursor := 5;
  Key := vkDelete;
  Ch := #0;
  Assert.IsTrue(InputLineHandleInput(Line, Key, [ssCtrl], Ch) = ilrHandled,
    'Ctrl+Del handled');
  Assert.IsTrue(Line.Text = '', 'Ctrl+Del cuts selection');
end;

procedure TestInputLineInsertCaret;
var
  Grid: TTerminalGrid;
  Line: TInputLine;
  Colors: TInputLineColors;
begin
  AllocTerminalGrid(Grid, 20, 1);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
  Line := InputLineEmpty;
  InputLineSetText(Line, 'ab', False);
  Colors := InputLineDefaultColors(True);

  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, True);
  Assert.IsTrue(Grid[0][0].CharValue = 'a', 'glyph at cursor kept');
  Assert.IsTrue(Grid[0][0].FgColor = Colors.Fg, 'caret does not invert fg');
  Assert.IsTrue(Grid[0][0].BgColor = Colors.Bg, 'caret does not invert bg');
  Assert.IsTrue(ccaInsertCaret in Grid[0][0].Attributes, 'caret at left of first char');
  Assert.IsTrue(not (ccaInsertCaret in Grid[0][1].Attributes), 'next char has no caret');

  Line.Cursor := 1;
  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, True);
  Assert.IsTrue(ccaInsertCaret in Grid[0][1].Attributes, 'caret between a and b');
  Assert.IsTrue(not (ccaInsertCaret in Grid[0][0].Attributes), 'previous cell cleared');
  Assert.IsTrue(Grid[0][1].CharValue = 'b', 'b glyph kept');
  Assert.IsTrue(Grid[0][1].FgColor = Colors.Fg, 'b not inverted');

  Line.Cursor := 2;
  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, True);
  Assert.IsTrue(ccaInsertCaret in Grid[0][2].Attributes, 'caret after last char');
  Assert.IsTrue(Grid[0][2].CharValue = ' ', 'end cell is space');
  Assert.IsTrue(Grid[0][2].FgColor = Colors.Fg, 'end cell not inverted');

  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, False);
  Assert.IsTrue(not (ccaInsertCaret in Grid[0][2].Attributes), 'blink off clears caret');

  InputLineDraw(Grid, 0, 0, 10, Line, False, Colors, True);
  Assert.IsTrue(not (ccaInsertCaret in Grid[0][2].Attributes), 'unfocused has no caret');
end;

procedure TestInputLineWordsAndClicks;
var
  Line: TInputLine;
  Key: Word;
  Ch: Char;
  S, E: Integer;
begin
  // Delimiters: everything but letters (any script), digits and '_'.
  Assert.IsTrue(TextWordStepRight('C:\Work\file_1.txt', 0) = 1, 'Ctrl+Right stops at ":"');
  Assert.IsTrue(TextWordStepRight('C:\Work\file_1.txt', 1) = 7, 'Ctrl+Right skips "\" then word');
  Assert.IsTrue(TextWordStepRight('C:\Work\file_1.txt', 7) = 14, '"_" is part of a word');
  Assert.IsTrue(TextWordStepLeft('C:\Work\file_1.txt', 18) = 15, 'Ctrl+Left to word start');
  Assert.IsTrue(TextWordStepRight('abc файл', 3) = 8, 'Cyrillic is a word');

  // Ctrl+Shift+Right grows the selection, Ctrl+Shift+Left shrinks it back.
  Line := InputLineEmpty;
  InputLineSetText(Line, 'dir /s foo.txt', False);
  Key := vkRight; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  Assert.IsTrue(InputLineSelectedText(Line) = 'dir', 'Ctrl+Shift+Right selects "dir"');
  Key := vkRight; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  Assert.IsTrue(InputLineSelectedText(Line) = 'dir /s', 'second step to next delimiter');
  Key := vkLeft; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  Assert.IsTrue(InputLineSelectedText(Line) = 'dir /', 'Ctrl+Shift+Left releases the part');

  // Mouse: 1 = caret, 2 = word, 3 = whole line.
  InputLineMouseClick(Line, 8, 1);
  Assert.IsTrue((Line.Cursor = 8) and not InputLineHasSelection(Line), 'click places caret');
  InputLineMouseClick(Line, 8, 2);
  Assert.IsTrue(InputLineSelectedText(Line) = 'foo', 'double click selects word');
  InputLineMouseClick(Line, 8, 3);
  Assert.IsTrue(InputLineSelectedText(Line) = 'dir /s foo.txt', 'triple click selects line');
  InputLineMouseClick(Line, 4, 1);
  InputLineMouseClick(Line, 10, 1, True);
  Assert.IsTrue(InputLineSelectedText(Line) = '/s foo', 'Shift+click extends from the caret');
  InputLineMouseClick(Line, 7, 1, True);
  Assert.IsTrue(InputLineSelectedText(Line) = '/s ', 'Shift+click shrinks, anchor stays');
  TextWordRangeAt('a  b', 1, S, E);
  Assert.IsTrue((S = 1) and (E = 3), 'double click on spaces selects the run');
end;

{ TTestDualPanelCmdLine }

procedure TTestDualPanelCmdLine.TestPathResolve;
begin
  TestDualPanelCmdLine.TestPathResolve;
end;

procedure TTestDualPanelCmdLine.TestCompletionHelpers;
begin
  TestDualPanelCmdLine.TestCompletionHelpers;
end;

procedure TTestDualPanelCmdLine.TestTabAndHistory;
begin
  TestDualPanelCmdLine.TestTabAndHistory;
end;

procedure TTestDualPanelCmdLine.TestHistoryKeepsCurrentLine;
begin
  TestDualPanelCmdLine.TestHistoryKeepsCurrentLine;
end;

procedure TTestDualPanelCmdLine.TestCtrlUpReturnsToPanel;
begin
  TestDualPanelCmdLine.TestCtrlUpReturnsToPanel;
end;

procedure TTestDualPanelCmdLine.TestEnterReturnsFocusToPanel;
begin
  TestDualPanelCmdLine.TestEnterReturnsFocusToPanel;
end;

procedure TTestDualPanelCmdLine.TestEscClearsThenReturnsToPanel;
begin
  TestDualPanelCmdLine.TestEscClearsThenReturnsToPanel;
end;

procedure TTestDualPanelCmdLine.TestCommandLineDraw;
begin
  TestDualPanelCmdLine.TestCommandLineDraw;
end;

procedure TTestDualPanelCmdLine.TestInputLineInsertCaret;
begin
  TestDualPanelCmdLine.TestInputLineInsertCaret;
end;

procedure TTestDualPanelCmdLine.TestInputLineCutClearsText;
begin
  TestDualPanelCmdLine.TestInputLineCutClearsText;
end;

procedure TTestDualPanelCmdLine.TestInputLineWordsAndClicks;
begin
  TestDualPanelCmdLine.TestInputLineWordsAndClicks;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelCmdLine);

end.
