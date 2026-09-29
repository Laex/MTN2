unit TestANSIParser;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestANSIParser = class
  public
    [Test] procedure TestStandardColorsAndAttributes;
    [Test] procedure TestTrueColorAnd256Color;
    [Test] procedure TestConsoleBufferRichOutput;
    [Test] procedure TestScrollbackScaling10k;
    [Test] procedure TestEraseCommands;
    [Test] procedure TestCursorAddressingAndAltScreen;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Diagnostics,
  uTerminalTypes, uANSIParser, uConsoleBuffer;

procedure TestStandardColorsAndAttributes;
var
  Parser: TANSIParser;
  CharCount: Integer;
  LastFg, LastBg: TAlphaColor;
  LastAttrs: TCharCellAttributes;
begin
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

    Assert.IsTrue(CharCount = 5, 'Char count should be 5');
    Assert.IsTrue(ccaBold in LastAttrs, 'Bold attribute should be set');
    Assert.IsTrue(LastFg = TANSIParser.StandardAnsiColor(1, True), 'Fg should be Red (Bright with bold)');
    Assert.IsTrue(LastBg = TANSIParser.StandardAnsiColor(2), 'Bg should be Green');

    // SGR 0 (Reset)
    Parser.ParseText(#27'[0mWorld',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
        LastAttrs := Attrs;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    Assert.IsTrue(LastAttrs = [], 'Attributes should be reset');
    Assert.IsTrue(LastFg = TAlphaColor($FFE0E0E0), 'Fg should reset to default');
    Assert.IsTrue(LastBg = TAlphaColor($FF000000), 'Bg should reset to default');
  finally
    Parser.Free;
  end;
end;

procedure TestTrueColorAnd256Color;
var
  Parser: TANSIParser;
  LastFg, LastBg: TAlphaColor;
begin
  Parser := TANSIParser.Create;
  try
    // 256-color: Fg = 200, Bg = 50
    Parser.ParseText(#27'[38;5;200;48;5;50mX',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    Assert.IsTrue(LastFg = TANSIParser.Ansi256ToAlphaColor(200), 'Fg 256-color mismatch');
    Assert.IsTrue(LastBg = TANSIParser.Ansi256ToAlphaColor(50), 'Bg 256-color mismatch');

    // 24-bit TrueColor: Fg = RGB(255, 128, 64), Bg = RGB(10, 20, 30)
    Parser.ParseText(#27'[38;2;255;128;64;48;2;10;20;30mY',
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        LastFg := Fg;
        LastBg := Bg;
      end, nil, nil, nil, nil, nil, nil, nil, nil, nil);

    Assert.IsTrue(LastFg = TAlphaColor(($FF shl 24) or (255 shl 16) or (128 shl 8) or 64), 'TrueColor Fg RGB(255,128,64) mismatch');
    Assert.IsTrue(LastBg = TAlphaColor(($FF shl 24) or (10 shl 16) or (20 shl 8) or 30), 'TrueColor Bg RGB(10,20,30) mismatch');
  finally
    Parser.Free;
  end;
end;

procedure TestConsoleBufferRichOutput;
var
  Buffer: TConsoleBuffer;
  Rows: TArray<TConsoleRow>;
  Total, Top: Integer;
begin
  Buffer := TConsoleBuffer.Create(500);
  try
    Buffer.AppendOutput('Line 1'#13#10);
    Buffer.AppendOutput(#27'[31mRed Line'#27'[0m'#13#10);
    Buffer.AppendCommand('> dir');
    Buffer.AppendOutput(#27'[38;2;0;255;0mGreen Text'#13#10);

    Rows := Buffer.GetVisibleRows(10, Total, Top);
    Assert.IsTrue(Total >= 3, 'Total visible lines should be at least 3');
    Assert.IsTrue(Length(Rows) > 0, 'Visible rows should not be empty');

    Assert.IsTrue(Buffer.GetLine(0) = 'Line 1', 'Line 0 plain text mismatch');
    Assert.IsTrue(Buffer.GetLine(1) = 'Red Line', 'Line 1 plain text mismatch (CSI stripped in plain line)');
  finally
    Buffer.Free;
  end;
end;

procedure TestScrollbackScaling10k;
var
  Buffer: TConsoleBuffer;
  I: Integer;
  Sw: TStopwatch;
  Rows: TArray<TConsoleRow>;
  Total, Top: Integer;
begin
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
    Assert.IsTrue(Buffer.LineCount <= 10000, 'Buffer capacity must be trimmed to 10,000 lines');

    Rows := Buffer.GetVisibleRows(50, Total, Top);
    Assert.IsTrue(Length(Rows) = 50, 'Should return 50 visible rows');
    // Cap is on storage (incl. trailing blank working line); visible total excludes blank.
    Assert.IsTrue(Buffer.LineCount = 10000, 'Storage LineCount must equal MaxLines');
    Assert.IsTrue(Total = 9999, 'Visible Total excludes trailing blank working line');
    Assert.IsTrue(Top = Total - 50, 'FollowTail should pin view to bottom');

    Buffer.FollowTail := False;
    Buffer.ScrollToStart;
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    Assert.IsTrue(Top = 0, 'ScrollToStart must show head of scrollback');
    Buffer.ScrollBy(100, 50);
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    Assert.IsTrue(Top = 100, 'ScrollBy must advance viewport');
    Buffer.ScrollToEnd;
    Rows := Buffer.GetVisibleRows(50, Total, Top);
    Assert.IsTrue(Top = Total - 50, 'ScrollToEnd must return to tail');
  finally
    Buffer.Free;
  end;
end;

procedure TestEraseCommands;
var
  Buffer: TConsoleBuffer;
begin
  Buffer := TConsoleBuffer.Create(100);
  try
    Buffer.AppendOutput('First line'#13#10);
    Buffer.AppendOutput('Second line to be erased'#27'[2K'#13#10);
    Assert.IsTrue(Trim(Buffer.GetLine(1)) = '', 'Second line should be erased by CSI 2K');

    Buffer.AppendOutput('Third line'#13#10);
    Buffer.AppendOutput(#27'[2J'); // Clear screen
    Assert.IsTrue(Buffer.LineCount = 1, 'Clear screen CSI 2J should reset buffer lines');
  finally
    Buffer.Free;
  end;
end;

procedure TestCursorAddressingAndAltScreen;
var
  Parser: TANSIParser;
  Buffer: TConsoleBuffer;
  CapturedRow, CapturedCol, MoveCount, SetModeMode, EdMode: Integer;
  MoveDir: Char;
  SetModeSet, GotCursorPos, GotCursorMove, GotSetMode, GotEraseDisplay: Boolean;
begin
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
    Assert.IsTrue(GotCursorPos, 'CUP callback should fire for ESC[5;10H');
    Assert.IsTrue(CapturedRow = 4, 'CUP row should be 0-based 4');
    Assert.IsTrue(CapturedCol = 9, 'CUP col should be 0-based 9');

    GotCursorMove := False;
    Parser.ParseText(#27'[3A', nil, nil, nil, nil, nil, nil, nil,
      procedure(ADir: Char; ACount: Integer)
      begin
        GotCursorMove := True;
        MoveDir := ADir;
        MoveCount := ACount;
      end, nil, nil);
    Assert.IsTrue(GotCursorMove, 'Cursor move callback should fire for ESC[3A');
    Assert.IsTrue(MoveDir = 'A', 'Move direction should be A');
    Assert.IsTrue(MoveCount = 3, 'Move count should be 3');

    GotSetMode := False;
    Parser.ParseText(#27'[?1049h', nil, nil, nil, nil, nil, nil, nil, nil, nil,
      procedure(AMode: Integer; ASet: Boolean)
      begin
        GotSetMode := True;
        SetModeMode := AMode;
        SetModeSet := ASet;
      end);
    Assert.IsTrue(GotSetMode, 'SetMode callback should fire for ESC[?1049h');
    Assert.IsTrue(SetModeMode = 1049, 'Mode should be 1049');
    Assert.IsTrue(SetModeSet, 'Set should be True for ''h''');

    GotEraseDisplay := False;
    Parser.ParseText(#27'[2J', nil, nil, nil, nil, nil,
      procedure(AMode: Integer)
      begin
        GotEraseDisplay := True;
        EdMode := AMode;
      end, nil, nil, nil, nil);
    Assert.IsTrue(GotEraseDisplay, 'Erase display callback should fire for ESC[2J');
    Assert.IsTrue(EdMode = 2, 'Erase display mode should be 2');
  finally
    Parser.Free;
  end;

  // TConsoleBuffer end-to-end: enter/exit alt screen, CUP-addressed write,
  // primary scrollback untouched by the round trip.
  Buffer := TConsoleBuffer.Create(100);
  try
    Buffer.AppendOutput('primary line'#13#10);
    Assert.IsTrue(not Buffer.AltScreenActive, 'Alt screen should start inactive');

    Buffer.AppendOutputEx(#27'[?1049h', 20, 5);
    Assert.IsTrue(Buffer.AltScreenActive, 'Alt screen should activate on ESC[?1049h with real geometry');
    Assert.IsTrue(Buffer.AltScreen.Cols = 20, 'Alt grid cols should match');
    Assert.IsTrue(Buffer.AltScreen.Rows = 5, 'Alt grid rows should match');

    Buffer.AppendOutputEx(#27'[3;3HX', 20, 5);
    Assert.IsTrue(Buffer.AltScreen.Grid[2][2].CharValue = 'X', 'CUP-addressed write should land at row 2, col 2');

    Buffer.AppendOutputEx(#27'[?1049l', 20, 5);
    Assert.IsTrue(not Buffer.AltScreenActive, 'Alt screen should deactivate on ESC[?1049l');
    Assert.IsTrue(Buffer.GetLine(0) = 'primary line', 'Primary scrollback must survive alt-screen round trip');
  finally
    Buffer.Free;
  end;

end;

{ TTestANSIParser }

procedure TTestANSIParser.TestStandardColorsAndAttributes;
begin
  TestANSIParser.TestStandardColorsAndAttributes;
end;

procedure TTestANSIParser.TestTrueColorAnd256Color;
begin
  TestANSIParser.TestTrueColorAnd256Color;
end;

procedure TTestANSIParser.TestConsoleBufferRichOutput;
begin
  TestANSIParser.TestConsoleBufferRichOutput;
end;

procedure TTestANSIParser.TestScrollbackScaling10k;
begin
  TestANSIParser.TestScrollbackScaling10k;
end;

procedure TTestANSIParser.TestEraseCommands;
begin
  TestANSIParser.TestEraseCommands;
end;

procedure TTestANSIParser.TestCursorAddressingAndAltScreen;
begin
  TestANSIParser.TestCursorAddressingAndAltScreen;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestANSIParser);

end.
