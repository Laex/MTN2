program TestANSIParser;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.UITypes, System.Diagnostics,
  uTerminalTypes, uANSIParser, uConsoleBuffer;

procedure AssertTrue(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
  begin
    Writeln('FAIL: ', AMsg);
    Halt(1);
  end;
end;

procedure TestStandardColorsAndAttributes;
var
  Parser: TANSIParser;
  CharCount: Integer;
  LastFg, LastBg: TAlphaColor;
  LastAttrs: TCharCellAttributes;
begin
  Writeln('[1/6] Testing Standard ANSI Colors & Attributes...');
  Parser := TANSIParser.Create;
  try
    CharCount := 0;
    // SGR 1 (Bold), SGR 31 (Red Fg), SGR 42 (Green Bg)
    Parser.ParseText(#27'[1;31;42mHello',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        Inc(CharCount);
        LastFg := Fg;
        LastBg := Bg;
        LastAttrs := Attrs;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    AssertTrue(CharCount = 5, 'Char count should be 5');
    AssertTrue(ccaBold in LastAttrs, 'Bold attribute should be set');
    AssertTrue(LastFg = TANSIParser.StandardAnsiColor(1, True), 'Fg should be Red (Bright with bold)');
    AssertTrue(LastBg = TANSIParser.StandardAnsiColor(2), 'Bg should be Green');

    // SGR 0 (Reset)
    Parser.ParseText(#27'[0mWorld',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
        LastAttrs := Attrs;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    AssertTrue(LastAttrs = [], 'Attributes should be reset');
    AssertTrue(LastFg = TAlphaColor($FFE0E0E0), 'Fg should reset to default');
    AssertTrue(LastBg = TAlphaColor($FF000000), 'Bg should reset to default');
  finally
    Parser.Free;
  end;
  Writeln('  OK: Standard colors and attributes passed.');
end;

procedure TestTrueColorAnd256Color;
var
  Parser: TANSIParser;
  LastFg, LastBg: TAlphaColor;
begin
  Writeln('[2/6] Testing 256-Color & 24-bit TrueColor...');
  Parser := TANSIParser.Create;
  try
    // 256-color: Fg = 200, Bg = 50
    Parser.ParseText(#27'[38;5;200;48;5;50mX',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    AssertTrue(LastFg = TANSIParser.Ansi256ToAlphaColor(200), 'Fg 256-color mismatch');
    AssertTrue(LastBg = TANSIParser.Ansi256ToAlphaColor(50), 'Bg 256-color mismatch');

    // 24-bit TrueColor: Fg = RGB(255, 128, 64), Bg = RGB(10, 20, 30)
    Parser.ParseText(#27'[38;2;255;128;64;48;2;10;20;30mY',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    AssertTrue(LastFg = TAlphaColor(($FF shl 24) or (255 shl 16) or (128 shl 8) or 64), 'TrueColor Fg RGB(255,128,64) mismatch');
    AssertTrue(LastBg = TAlphaColor(($FF shl 24) or (10 shl 16) or (20 shl 8) or 30), 'TrueColor Bg RGB(10,20,30) mismatch');
  finally
    Parser.Free;
  end;
  Writeln('  OK: TrueColor and 256-color passed.');
end;

procedure TestConsoleBufferRichOutput;
var
  Buffer: TConsoleBuffer;
  Rows: TArray<TConsoleRow>;
  Total, Top: Integer;
begin
  Writeln('[3/6] Testing TConsoleBuffer Rich Output...');
  Buffer := TConsoleBuffer.Create(500);
  try
    Buffer.AppendOutput('Line 1'#13#10);
    Buffer.AppendOutput(#27'[31mRed Line'#27'[0m'#13#10);
    Buffer.AppendCommand('> dir');
    Buffer.AppendOutput(#27'[38;2;0;255;0mGreen Text'#13#10);

    Rows := Buffer.GetVisibleRows(10, Total, Top);
    AssertTrue(Total >= 3, 'Total visible lines should be at least 3');
    AssertTrue(Length(Rows) > 0, 'Visible rows should not be empty');

    AssertTrue(Buffer.GetLine(0) = 'Line 1', 'Line 0 plain text mismatch');
    AssertTrue(Buffer.GetLine(1) = 'Red Line', 'Line 1 plain text mismatch (CSI stripped in plain line)');
  finally
    Buffer.Free;
  end;
  Writeln('  OK: TConsoleBuffer rich output passed.');
end;

procedure TestScrollbackScaling10k;
var
  Buffer: TConsoleBuffer;
  I: Integer;
  Sw: TStopwatch;
  Rows: TArray<TConsoleRow>;
  Total, Top: Integer;
begin
  Writeln('[4/6] Testing 10,000 Line Scrollback Scaling...');
  Buffer := TConsoleBuffer.Create(10000);
  try
    Sw := TStopwatch.StartNew;
    for I := 1 to 12000 do
    begin
      Buffer.AppendOutput(Format(#27'[38;2;%d;%d;%dmLine %d: ANSI streaming output'#13#10,
        [I mod 256, (I * 2) mod 256, (I * 3) mod 256, I]));
    end;
    Sw.Stop;

    Writeln(Format('  Appended 12,000 lines in %d ms (limit 10,000)', [Sw.ElapsedMilliseconds]));
    AssertTrue(Buffer.LineCount <= 10000, 'Buffer capacity must be trimmed to 10,000 lines');

    Rows := Buffer.GetVisibleRows(50, Total, Top);
    AssertTrue(Length(Rows) = 50, 'Should return 50 visible rows');
    // Cap is on storage (incl. trailing blank working line); visible total excludes blank.
    AssertTrue(Buffer.LineCount = 10000, 'Storage LineCount must equal MaxLines');
    AssertTrue(Total = 9999, 'Visible Total excludes trailing blank working line');
    AssertTrue(Top = Total - 50, 'FollowTail should pin view to bottom');

    Buffer.FollowTail := False;
    Buffer.ScrollToStart;
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    AssertTrue(Top = 0, 'ScrollToStart must show head of scrollback');
    Buffer.ScrollBy(100, 50);
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    AssertTrue(Top = 100, 'ScrollBy must advance viewport');
    Buffer.ScrollToEnd;
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    AssertTrue(Top = Total - 50, 'ScrollToEnd must return to tail');
  finally
    Buffer.Free;
  end;
  Writeln('  OK: 10,000 line scrollback scaling passed.');
end;

procedure TestEraseCommands;
var
  Buffer: TConsoleBuffer;
begin
  Writeln('[5/6] Testing Erase Commands (EL / ED)...');
  Buffer := TConsoleBuffer.Create(100);
  try
    Buffer.AppendOutput('First line'#13#10);
    Buffer.AppendOutput('Second line to be erased'#27'[2K'#13#10);
    AssertTrue(Trim(Buffer.GetLine(1)) = '', 'Second line should be erased by CSI 2K');

    Buffer.AppendOutput('Third line'#13#10);
    Buffer.AppendOutput(#27'[2J'); // Clear screen
    AssertTrue(Buffer.LineCount = 1, 'Clear screen CSI 2J should reset buffer lines');
  finally
    Buffer.Free;
  end;
  Writeln('  OK: Erase commands passed.');
end;

procedure TestCursorAddressingAndAltScreen;
var
  Parser: TANSIParser;
  Buffer: TConsoleBuffer;
  CapturedRow, CapturedCol, MoveCount, SetModeMode, EdMode: Integer;
  MoveDir: Char;
  SetModeSet, GotCursorPos, GotCursorMove, GotSetMode, GotEraseDisplay: Boolean;
begin
  Writeln('[6/6] Testing Cursor Addressing & Alt-Screen...');
  Parser := TANSIParser.Create;
  try
    GotCursorPos := False;
    Parser.ParseText(#27'[5;10H', nil, nil, nil, nil, nil, nil,
      procedure(ARow, ACol: Integer)
      begin
        GotCursorPos := True;
        CapturedRow := ARow;
        CapturedCol := ACol;
      end, nil, nil, nil);
    AssertTrue(GotCursorPos, 'CUP callback should fire for ESC[5;10H');
    AssertTrue(CapturedRow = 4, 'CUP row should be 0-based 4');
    AssertTrue(CapturedCol = 9, 'CUP col should be 0-based 9');

    GotCursorMove := False;
    Parser.ParseText(#27'[3A', nil, nil, nil, nil, nil, nil, nil,
      procedure(ADir: Char; ACount: Integer)
      begin
        GotCursorMove := True;
        MoveDir := ADir;
        MoveCount := ACount;
      end, nil, nil);
    AssertTrue(GotCursorMove, 'Cursor move callback should fire for ESC[3A');
    AssertTrue(MoveDir = 'A', 'Move direction should be A');
    AssertTrue(MoveCount = 3, 'Move count should be 3');

    GotSetMode := False;
    Parser.ParseText(#27'[?1049h', nil, nil, nil, nil, nil, nil, nil, nil, nil,
      procedure(AMode: Integer; ASet: Boolean)
      begin
        GotSetMode := True;
        SetModeMode := AMode;
        SetModeSet := ASet;
      end);
    AssertTrue(GotSetMode, 'SetMode callback should fire for ESC[?1049h');
    AssertTrue(SetModeMode = 1049, 'Mode should be 1049');
    AssertTrue(SetModeSet, 'Set should be True for ''h''');

    GotEraseDisplay := False;
    Parser.ParseText(#27'[2J', nil, nil, nil, nil, nil,
      procedure(AMode: Integer)
      begin
        GotEraseDisplay := True;
        EdMode := AMode;
      end, nil, nil, nil, nil);
    AssertTrue(GotEraseDisplay, 'Erase display callback should fire for ESC[2J');
    AssertTrue(EdMode = 2, 'Erase display mode should be 2');
  finally
    Parser.Free;
  end;

  // TConsoleBuffer end-to-end: enter/exit alt screen, CUP-addressed write,
  // primary scrollback untouched by the round trip.
  Buffer := TConsoleBuffer.Create(100);
  try
    Buffer.AppendOutput('primary line'#13#10);
    AssertTrue(not Buffer.AltScreenActive, 'Alt screen should start inactive');

    Buffer.AppendOutputEx(#27'[?1049h', 20, 5);
    AssertTrue(Buffer.AltScreenActive, 'Alt screen should activate on ESC[?1049h with real geometry');
    AssertTrue(Buffer.AltScreen.Cols = 20, 'Alt grid cols should match');
    AssertTrue(Buffer.AltScreen.Rows = 5, 'Alt grid rows should match');

    Buffer.AppendOutputEx(#27'[3;3HX', 20, 5);
    AssertTrue(Buffer.AltScreen.Grid[2][2].CharValue = 'X', 'CUP-addressed write should land at row 2, col 2');

    Buffer.AppendOutputEx(#27'[?1049l', 20, 5);
    AssertTrue(not Buffer.AltScreenActive, 'Alt screen should deactivate on ESC[?1049l');
    AssertTrue(Buffer.GetLine(0) = 'primary line', 'Primary scrollback must survive alt-screen round trip');
  finally
    Buffer.Free;
  end;

  Writeln('  OK: Cursor addressing and alt-screen passed.');
end;

begin
  try
    Writeln('========================================');
    Writeln('   MTN2 Stage 17 ANSI Parser Test Suite');
    Writeln('========================================');
    TestStandardColorsAndAttributes;
    TestTrueColorAnd256Color;
    TestConsoleBufferRichOutput;
    TestScrollbackScaling10k;
    TestEraseCommands;
    TestCursorAddressingAndAltScreen;
    Writeln('========================================');
    Writeln('ALL STAGE 17 ANSI PARSER TESTS PASSED!');
    Writeln('========================================');
  except
    on E: Exception do
    begin
      Writeln('FATAL EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
