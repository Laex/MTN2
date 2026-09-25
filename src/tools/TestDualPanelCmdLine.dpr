program TestDualPanelCmdLine;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.UITypes, System.Classes,
  uDualPanelCmdLine in '..\Core\uDualPanelCmdLine.pas',
  uDualPanelCmd in '..\Core\uDualPanelCmd.pas',
  uInputLine in '..\Core\uInputLine.pas',
  uConfigLocation in '..\Core\uConfigLocation.pas',
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas';

type
  TCmdLineColorSpy = class
  public
    StripCalls, AccentCalls: Integer;
    StripFg, StripBg, AccFg, AccBg: TAlphaColor;
    procedure Strip(out AFg, ABg: TAlphaColor);
    procedure Accent(out AFg, ABg: TAlphaColor);
  end;

procedure AssertTrue(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
  begin
    Writeln('FAIL: ', AMsg);
    Halt(1);
  end;
end;

procedure TestPathResolve;
var
  URI: string;
  Resolved: Boolean;
begin
  Resolved := TryResolvePanelCommandPath('cd %APPDATA%', 'C:\', URI);
  AssertTrue(Resolved, 'cd %APPDATA% should resolve to navigable URI');
  AssertTrue(Pos('AppData', URI) > 0, 'URI should contain AppData');

  Resolved := TryResolvePanelCommandPath('dir /o', 'D:\Work', URI);
  AssertTrue(not Resolved, 'dir /o must NOT be resolved as a directory path');

  Resolved := TryResolvePanelCommandPath('dir /w /p', 'D:\Work', URI);
  AssertTrue(not Resolved, 'dir /w /p must NOT be resolved as a directory path');

  Resolved := TryResolvePanelCommandPath('git checkout feature/bar', 'D:\Work', URI);
  AssertTrue(not Resolved, 'git command with slash and spaces must NOT be resolved as a directory path');
end;

procedure TestCompletionHelpers;
var
  Names, Matches: TArray<string>;
  NewText: string;
  NewCur: Integer;
  LongPath, Prefix: string;
begin
  AssertTrue(CmdLineQuoteIfNeeded('readme.md') = 'readme.md', 'no quote plain');
  AssertTrue(CmdLineQuoteIfNeeded('my file.txt') = '"my file.txt"', 'quote space');

  AssertTrue(CmdLineExtractToken('dir re', 6) = 're', 'token at end');
  AssertTrue(CmdLineExtractToken('dir "my fi', 10) = 'my fi', 'token in quote');

  Names := TArray<string>.Create('..', 'readme.md', 'Release', 'src');
  Matches := FilterCompletions(Names, 're');
  AssertTrue(Length(Matches) = 2, 'filter re → readme + Release');
  AssertTrue(SameText(Matches[0], 'readme.md') or SameText(Matches[0], 'Release'),
    'first match');

  AssertTrue(CmdLineApplyCompletion('dir re', 6, 'readme.md', NewText, NewCur),
    'apply');
  AssertTrue(NewText = 'dir readme.md', 'applied text');
  AssertTrue(NewCur = Length(NewText), 'cursor at end of token');

  AssertTrue(CmdLineApplyCompletion('dir ', 4, 'my file.txt', NewText, NewCur),
    'apply quoted');
  AssertTrue(NewText = 'dir "my file.txt"', 'quoted apply');

  LongPath := 'D:\Work\Delphi\MTN2\src\tools\TestDualPanelCmdLine.dpr';
  Prefix := FormatCmdLinePrefix(LongPath, 30);
  AssertTrue(Length(Prefix) <= 30, 'prefix within budget');
  AssertTrue(Prefix.EndsWith('>'), 'prompt suffix');
  AssertTrue(Pos('...', Prefix) > 0, 'long path compacted');

  Prefix := FormatCmdLinePrefix('C:\Work', 30);
  AssertTrue(Prefix = 'C:\Work>', 'short path unchanged');
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
  AssertTrue(CmdLinePrefixMaxCells(80) = 26, 'width div 3');
  AssertTrue(CmdLinePrefixMaxCells(3) = 3, 'min prompt budget');
  AssertTrue(CmdLinePathLabel('recycle://C:/') = 'Recycle Bin', 'recycle title');
  AssertTrue(CmdLinePathLabel('file:///C:/Work') = FileUriToPath('file:///C:/Work'),
    'file URI becomes path');

  ResolveCmdLineInputColors(False, $FF111111, $FF222222, $FF333333, $FF444444, Colors);
  AssertTrue((Colors.Fg = $FF111111) and (Colors.SelFg = $FF111111) and
    (Colors.CaretBg = $FF222222), 'idle uses strip for caret');
  ResolveCmdLineInputColors(True, $FF111111, $FF222222, $FF333333, $FF444444, Colors);
  AssertTrue((Colors.SelFg = $FF333333) and (Colors.CaretBg = $FF444444),
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
    AssertTrue(Spy.StripCalls = 1, 'idle asks strip');
    AssertTrue(Spy.AccentCalls = 0, 'idle skips accent');
    Prefix := FormatCmdLinePrefix(CmdLinePathLabel('file:///C:/Work'),
      CmdLinePrefixMaxCells(40));
    AssertTrue(Grid[1][0].CharValue = Prefix[1], 'prefix starts the row');
    AssertTrue(Grid[1][Length(Prefix)].CharValue = 'd', 'edit starts after prefix');

    Spy.StripCalls := 0;
    DrawDualPanelCommandLine(Host, Grid, 1, 40, 'file:///C:/Work', Cmd, True, True);
    AssertTrue(Spy.AccentCalls = 1, 'focus asks accent');
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
    AssertTrue(Mgr.HandleInput(Key, [], Ch), 'Tab handled');
    AssertTrue(Mgr.Text = 'type alpha.txt', 'Tab completes first match alpha.txt');

    Key := vkTab;
    Ch := #0;
    AssertTrue(Mgr.HandleInput(Key, [], Ch), 'Tab cycle');
    AssertTrue(Mgr.Text = 'type about.md', 'Tab cycles to about.md');

    Key := vkReturn;
    Ch := #0;
    AssertTrue(Mgr.HandleInput(Key, [], Ch), 'Enter submit');
    AssertTrue(Submitted = 'type about.md', 'submitted command');
    AssertTrue(Mgr.HistoryCount >= 1, 'history pushed');

    Mgr.Clear;
    Key := vkUp;
    Ch := #0;
    AssertTrue(Mgr.HandleInput(Key, [], Ch), 'history up');
    AssertTrue(Mgr.Text = 'type about.md', 'Up recalls last command');
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
    AssertTrue(Mgr.Focused, 'Ctrl+Down equivalent focuses cmdline');
    Key := vkUp;
    Ch := #0;
    AssertTrue(Mgr.HandleInput(Key, [ssCtrl], Ch), 'Ctrl+Up handled');
    AssertTrue(not Mgr.Focused, 'Ctrl+Up returns focus to the file panel');
    AssertTrue(Mgr.Text = 'dir', 'Ctrl+Up keeps the command text');
    AssertTrue(Key = 0, 'Ctrl+Up consumes AKey');
    AssertTrue(Ch = #0, 'Ctrl+Up consumes AKeyChar');
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
  AssertTrue(Line.Text = '', 'cut selection clears the line');

  Line := InputLineEmpty;
  InputLineSetText(Line, 'hello', True);
  Line.SelAnchor := 0;
  Line.Cursor := 5;
  Key := vkDelete;
  Ch := #0;
  AssertTrue(InputLineHandleInput(Line, Key, [ssCtrl], Ch) = ilrHandled,
    'Ctrl+Del handled');
  AssertTrue(Line.Text = '', 'Ctrl+Del cuts selection');
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
  AssertTrue(Grid[0][0].CharValue = 'a', 'glyph at cursor kept');
  AssertTrue(Grid[0][0].FgColor = Colors.Fg, 'caret does not invert fg');
  AssertTrue(Grid[0][0].BgColor = Colors.Bg, 'caret does not invert bg');
  AssertTrue(ccaInsertCaret in Grid[0][0].Attributes, 'caret at left of first char');
  AssertTrue(not (ccaInsertCaret in Grid[0][1].Attributes), 'next char has no caret');

  Line.Cursor := 1;
  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, True);
  AssertTrue(ccaInsertCaret in Grid[0][1].Attributes, 'caret between a and b');
  AssertTrue(not (ccaInsertCaret in Grid[0][0].Attributes), 'previous cell cleared');
  AssertTrue(Grid[0][1].CharValue = 'b', 'b glyph kept');
  AssertTrue(Grid[0][1].FgColor = Colors.Fg, 'b not inverted');

  Line.Cursor := 2;
  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, True);
  AssertTrue(ccaInsertCaret in Grid[0][2].Attributes, 'caret after last char');
  AssertTrue(Grid[0][2].CharValue = ' ', 'end cell is space');
  AssertTrue(Grid[0][2].FgColor = Colors.Fg, 'end cell not inverted');

  InputLineDraw(Grid, 0, 0, 10, Line, True, Colors, False);
  AssertTrue(not (ccaInsertCaret in Grid[0][2].Attributes), 'blink off clears caret');

  InputLineDraw(Grid, 0, 0, 10, Line, False, Colors, True);
  AssertTrue(not (ccaInsertCaret in Grid[0][2].Attributes), 'unfocused has no caret');
end;

procedure TestInputLineWordsAndClicks;
var
  Line: TInputLine;
  Key: Word;
  Ch: Char;
  S, E: Integer;
begin
  // Delimiters: everything but letters (any script), digits and '_'.
  AssertTrue(TextWordStepRight('C:\Work\file_1.txt', 0) = 1, 'Ctrl+Right stops at ":"');
  AssertTrue(TextWordStepRight('C:\Work\file_1.txt', 1) = 7, 'Ctrl+Right skips "\" then word');
  AssertTrue(TextWordStepRight('C:\Work\file_1.txt', 7) = 14, '"_" is part of a word');
  AssertTrue(TextWordStepLeft('C:\Work\file_1.txt', 18) = 15, 'Ctrl+Left to word start');
  AssertTrue(TextWordStepRight('abc файл', 3) = 8, 'Cyrillic is a word');

  // Ctrl+Shift+Right grows the selection, Ctrl+Shift+Left shrinks it back.
  Line := InputLineEmpty;
  InputLineSetText(Line, 'dir /s foo.txt', False);
  Key := vkRight; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  AssertTrue(InputLineSelectedText(Line) = 'dir', 'Ctrl+Shift+Right selects "dir"');
  Key := vkRight; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  AssertTrue(InputLineSelectedText(Line) = 'dir /s', 'second step to next delimiter');
  Key := vkLeft; Ch := #0;
  InputLineHandleInput(Line, Key, [ssCtrl, ssShift], Ch);
  AssertTrue(InputLineSelectedText(Line) = 'dir /', 'Ctrl+Shift+Left releases the part');

  // Mouse: 1 = caret, 2 = word, 3 = whole line.
  InputLineMouseClick(Line, 8, 1);
  AssertTrue((Line.Cursor = 8) and not InputLineHasSelection(Line), 'click places caret');
  InputLineMouseClick(Line, 8, 2);
  AssertTrue(InputLineSelectedText(Line) = 'foo', 'double click selects word');
  InputLineMouseClick(Line, 8, 3);
  AssertTrue(InputLineSelectedText(Line) = 'dir /s foo.txt', 'triple click selects line');
  InputLineMouseClick(Line, 4, 1);
  InputLineMouseClick(Line, 10, 1, True);
  AssertTrue(InputLineSelectedText(Line) = '/s foo', 'Shift+click extends from the caret');
  InputLineMouseClick(Line, 7, 1, True);
  AssertTrue(InputLineSelectedText(Line) = '/s ', 'Shift+click shrinks, anchor stays');
  TextWordRangeAt('a  b', 1, S, E);
  AssertTrue((S = 1) and (E = 3), 'double click on spaces selects the run');
end;

begin
  try
    Writeln('TestDualPanelCmdLine (stage 18)...');
    TestPathResolve;
    Writeln('  OK: path resolve');
    TestCompletionHelpers;
    Writeln('  OK: completion helpers');
    TestTabAndHistory;
    Writeln('  OK: Tab + history');
    TestCtrlUpReturnsToPanel;
    Writeln('  OK: Ctrl+Up unfocus');
    TestCommandLineDraw;
    Writeln('  OK: command line draw');
    TestInputLineInsertCaret;
    Writeln('  OK: insert caret');
    TestInputLineCutClearsText;
    Writeln('  OK: input line cut');
    TestInputLineWordsAndClicks;
    Writeln('  OK: word steps + clicks');
    Writeln('All DualPanelCmdLine tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
