unit TestAnsiFrame;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAnsiFrame = class
  public
    [Test] procedure TestFirstFrameWritesEveryCell;
    [Test] procedure TestUnchangedFrameWritesNothing;
    [Test] procedure TestOnlyChangedCellsAreWritten;
    [Test] procedure TestColorsAreTrueColor;
    [Test] procedure TestColorModes;
    [Test] procedure TestCaretBecomesCursor;
    [Test] procedure TestWideCharacterIsWrittenOnce;
    [Test] procedure TestResizeForcesFullFrame;
    [Test] procedure TestLeaveSequenceUndoesEveryEnterMode;
    [Test] procedure TestLeaveSequenceEndsOnPrimaryScreen;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uTerminalTypes, uAnsiFrame;

const
  cFg = TAlphaColor($FFC0C0C0);
  cBg = TAlphaColor($FF0000A8);

function NewGrid(ACols, ARows: Integer): TTerminalGrid;
begin
  AllocTerminalGrid(Result, ACols, ARows);
  ClearTerminalGrid(Result, cFg, cBg);
end;

function Text(const ABytes: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(ABytes);
end;

procedure TTestAnsiFrame.TestFirstFrameWritesEveryCell;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
  S: string;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(4, 2);
    PutGridText(G, 0, 0, 'abcd', cFg, cBg);
    PutGridText(G, 0, 1, 'wxyz', cFg, cBg);
    S := Text(W.Render(G));
    Assert.IsTrue(S.Contains('abcd'), 'first row');
    Assert.IsTrue(S.Contains('wxyz'), 'second row');
    Assert.IsTrue(S.Contains(#27'[1;1H'), 'cursor placed at the start');
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestUnchangedFrameWritesNothing;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(10, 3);
    W.Render(G);
    Assert.AreEqual(0, Integer(Length(W.Render(G))), 'nothing changed');
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestOnlyChangedCellsAreWritten;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
  S: string;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(40, 5);
    PutGridText(G, 0, 0, 'unchanged text', cFg, cBg);
    W.Render(G);
    PutGridText(G, 30, 3, 'X', cFg, cBg);
    S := Text(W.Render(G));
    Assert.IsFalse(S.Contains('unchanged'), 'the other cells are not rewritten');
    Assert.IsTrue(S.Contains(#27'[4;31H'), 'cursor moved to the changed cell');
    Assert.IsTrue(S.Contains('X'));
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestColorsAreTrueColor;
var
  S: string;
begin
  S := AnsiSgrFor(TAlphaColor($FF102030), TAlphaColor($FFA0B0C0), [ccaBold, ccaUnderline]);
  Assert.IsTrue(S.Contains(';1'), 'bold');
  Assert.IsTrue(S.Contains(';4'), 'underline');
  Assert.IsTrue(S.Contains('38;2;16;32;48'), 'foreground');
  Assert.IsTrue(S.Contains('48;2;160;176;192'), 'background');
end;

procedure TTestAnsiFrame.TestColorModes;
begin
  Assert.AreEqual(Ord(acmTrueColor), Ord(DetectColorMode('truecolor', 'xterm-256color')));
  Assert.AreEqual(Ord(acm256), Ord(DetectColorMode('', 'xterm-256color')));
  Assert.AreEqual(Ord(acm16), Ord(DetectColorMode('', 'linux')));
  // Pure red, a mid gray and white in the 256-color palette.
  Assert.IsTrue(AnsiSgrFor(TAlphaColor($FFFF0000), TAlphaColor($FF808080), [],
    acm256).Contains('38;5;196;48;5;244'), '256 colors');
  Assert.IsTrue(AnsiSgrFor(TAlphaColor($FFFF5555), TAlphaColor($FF0000AA), [],
    acm16).Contains(';91;44m'), '16 colors');
end;

procedure TTestAnsiFrame.TestCaretBecomesCursor;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
  S: string;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(10, 3);
    Include(G[1][4].Attributes, ccaInsertCaret);
    S := Text(W.Render(G));
    Assert.IsTrue(S.Contains(#27'[2;5H'#27'[6 q'#27'[?25h'), 'cursor shown at the caret');
    // Unchanged screen, same caret: nothing to send.
    Assert.AreEqual(0, Integer(Length(W.Render(G))));
    Exclude(G[1][4].Attributes, ccaInsertCaret);
    S := Text(W.Render(G));
    Assert.IsTrue(S.Contains(#27'[?25l'), 'cursor hidden again');
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestWideCharacterIsWrittenOnce;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
  S: string;
  P: Integer;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(6, 1);
    PutGridText(G, 0, 0, #$4E2D'a', cFg, cBg);
    S := Text(W.Render(G));
    P := Pos(#$4E2D, S);
    Assert.IsTrue(P > 0, 'the wide character is written');
    Assert.AreEqual(0, Pos(#$4E2D, S, P + 1), 'once');
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestResizeForcesFullFrame;
var
  W: TAnsiFrameWriter;
  G: TTerminalGrid;
begin
  W := TAnsiFrameWriter.Create;
  try
    G := NewGrid(10, 3);
    W.Render(G);
    G := NewGrid(12, 4);
    Assert.IsTrue(Length(W.Render(G)) > 0, 'a new size is redrawn whole');
  finally
    W.Free;
  end;
end;

procedure TTestAnsiFrame.TestLeaveSequenceUndoesEveryEnterMode;
const
  cModes: array[0..5] of string = ('1049', '25', '7', '2004', '1000', '1006');
var
  Enter, Leave: string;
  I: Integer;
begin
  Enter := AnsiEnterSequence(True);
  Leave := AnsiLeaveSequence;
  for I := Low(cModes) to High(cModes) do
    if Pos(#27'[?' + cModes[I] + 'h', Enter) > 0 then
      Assert.IsTrue(Pos(#27'[?' + cModes[I] + 'l', Leave) > 0,
        'mode ' + cModes[I] + ' is reset on leave')
    else
    begin
      Assert.IsTrue(Pos(#27'[?' + cModes[I] + 'l', Enter) > 0,
        'mode ' + cModes[I] + ' is cleared on enter');
      Assert.IsTrue(Pos(#27'[?' + cModes[I] + 'h', Leave) > 0,
        'mode ' + cModes[I] + ' is restored on leave');
    end;
  Assert.IsTrue(Pos(#27'[<u', Leave) > 0, 'kitty keyboard flags are popped');
  Assert.IsTrue(Pos(#27'[>4;0m', Leave) > 0, 'modifyOtherKeys is switched off');
end;

procedure TTestAnsiFrame.TestLeaveSequenceEndsOnPrimaryScreen;
var
  Leave: string;
begin
  Leave := AnsiLeaveSequence;
  Assert.IsTrue(Pos(#27'[?1049l', Leave) > 0, 'alternate screen is left');
  Assert.IsTrue(Pos(#27'[?25h', Leave) > 0, 'cursor is shown again');
  Assert.IsTrue(Pos(#27'[?1049l', Leave) > Pos(#27'[?25h', Leave),
    'the primary screen is restored last');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAnsiFrame);

end.
