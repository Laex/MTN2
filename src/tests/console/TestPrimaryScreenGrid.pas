unit TestPrimaryScreenGrid;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPrimaryScreenGrid = class
  public
    [Test] procedure TestPutCellAndWrap;
    [Test] procedure TestNewLineScrollArchives;
    [Test] procedure TestCarriageReturnAndBackspace;
    [Test] procedure TestDeleteCharBeforeCursor;
    [Test] procedure TestMoveAbsClamp;
    [Test] procedure TestSaveRestoreCursor;
    [Test] procedure TestEraseLineAndDisplay;
    [Test] procedure TestReflowGrowth;
    [Test] procedure TestReflowShrinkArchives;
    [Test] procedure TestInsertCaretColor;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Generics.Collections,
  uTerminalTypes, uPrimaryScreenGrid;

const
  Fg: TAlphaColor = $FFE0E0E0;
  Bg: TAlphaColor = $FF000000;

function RowText(const ARow: TTerminalRow): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ARow) do
    Result := Result + ARow[I].CharValue;
end;

procedure PutStr(AGrid: TPrimaryScreenGrid; const AText: string);
var
  I: Integer;
begin
  for I := 1 to Length(AText) do
    AGrid.PutCell(AText[I], Fg, Bg, []);
end;

procedure TestPutCellAndWrap;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(5, 3, Fg, Bg);
    PutStr(Grid, 'ABCDE');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'ABCDE', 'Row 0 should hold all 5 chars');
    Assert.IsTrue(Grid.CursorRow = 1, 'Cursor should wrap to row 1');
    Assert.IsTrue(Grid.CursorCol = 0, 'Cursor col should reset to 0 after wrap');
  finally
    Grid.Free;
  end;
  Writeln('  OK: PutCell auto-wrap passed.');
end;

procedure TestNewLineScrollArchives;
var
  Grid: TPrimaryScreenGrid;
  Archived: TList<string>;
begin
  Grid := TPrimaryScreenGrid.Create;
  Archived := TList<string>.Create;
  try
    Grid.OnArchiveRow := procedure(const ARow: TTerminalRow)
      begin
        Archived.Add(RowText(ARow));
      end;
    Grid.Alloc(5, 3, Fg, Bg);
    PutStr(Grid, 'ABCDE'); // row0, wraps to row1
    PutStr(Grid, 'FGHIJ'); // row1, wraps to row2
    Assert.IsTrue(Archived.Count = 0, 'No archive yet before 3rd row fills');
    PutStr(Grid, 'KLMNO'); // row2, fills last row -> scroll, archives row0
    Assert.IsTrue(Archived.Count = 1, 'Exactly one row should be archived');
    Assert.IsTrue(Archived[0] = 'ABCDE', 'Archived row should be the oldest (row0) content');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'FGHIJ', 'Row 0 should now hold former row1');
    Assert.IsTrue(RowText(Grid.Grid[1]) = 'KLMNO', 'Row 1 should now hold former row2');
    Assert.IsTrue(Trim(RowText(Grid.Grid[2])) = '', 'Row 2 should be blank after scroll');
    Assert.IsTrue(Grid.CursorRow = 2, 'Cursor should stay on last row after scroll');
    Assert.IsTrue(Grid.CursorCol = 0, 'Cursor col should be 0 after scroll-wrap');
  finally
    Archived.Free;
    Grid.Free;
  end;
  Writeln('  OK: NewLine scroll-with-archive passed.');
end;

procedure TestCarriageReturnAndBackspace;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(10, 3, Fg, Bg);
    PutStr(Grid, 'ABC');
    Assert.IsTrue(Grid.CursorCol = 3, 'Cursor should advance to col 3');
    Grid.CarriageReturn;
    Assert.IsTrue(Grid.CursorCol = 0, 'CarriageReturn should reset col to 0');
    Assert.IsTrue(Grid.CursorRow = 0, 'CarriageReturn should not change row');

    Grid.MoveAbs(0, 3);
    Grid.Backspace;
    Assert.IsTrue(Grid.CursorCol = 2, 'Backspace should move cursor left by 1');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'ABC' + StringOfChar(' ', 7),
      'Non-destructive Backspace must not erase content');

    Grid.MoveAbs(0, 0);
    Grid.Backspace;
    Assert.IsTrue(Grid.CursorCol = 0, 'Backspace at col 0 should be a no-op');
  finally
    Grid.Free;
  end;
  Writeln('  OK: CarriageReturn and Backspace passed.');
end;

procedure TestDeleteCharBeforeCursor;
var
  Grid: TPrimaryScreenGrid;
  Ok: Boolean;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(10, 2, Fg, Bg);
    PutStr(Grid, 'ABCDE');
    Assert.IsTrue(Grid.CursorCol = 5, 'Cursor should sit right after E');

    // No guard: delete should shift left and shorten visible content.
    Ok := Grid.DeleteCharBeforeCursor(0, Fg, Bg);
    Assert.IsTrue(Ok, 'DeleteCharBeforeCursor should succeed with no guard');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'ABCD' + StringOfChar(' ', 6),
      'Deleting the last char should shift-left and blank the vacated cell');
    Assert.IsTrue(Grid.CursorCol = 4, 'Cursor should move back by 1 after delete');

    // Guarded: cursor sitting at/before the guard column must refuse.
    Grid.MoveAbs(0, 2);
    Ok := Grid.DeleteCharBeforeCursor(3, Fg, Bg);
    Assert.IsTrue(not Ok, 'DeleteCharBeforeCursor must refuse at/before guard column');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'ABCD' + StringOfChar(' ', 6),
      'Guarded refusal must not modify row content');
    Assert.IsTrue(Grid.CursorCol = 2, 'Guarded refusal must not move the cursor');

    // Past the guard: should succeed.
    Grid.MoveAbs(0, 4);
    Ok := Grid.DeleteCharBeforeCursor(3, Fg, Bg);
    Assert.IsTrue(Ok, 'DeleteCharBeforeCursor should succeed past the guard column');
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'ABC' + StringOfChar(' ', 7),
      'Delete past guard should shift-left correctly');
  finally
    Grid.Free;
  end;
  Writeln('  OK: DeleteCharBeforeCursor passed.');
end;

procedure TestMoveAbsClamp;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(5, 3, Fg, Bg);
    Grid.MoveAbs(1, 2);
    Assert.IsTrue((Grid.CursorRow = 1) and (Grid.CursorCol = 2), 'MoveAbs should set exact position');
    Grid.MoveAbs(99, 99);
    Assert.IsTrue((Grid.CursorRow = 2) and (Grid.CursorCol = 4), 'MoveAbs should clamp to bottom-right');
    Grid.MoveAbs(-5, -5);
    Assert.IsTrue((Grid.CursorRow = 0) and (Grid.CursorCol = 0), 'MoveAbs should clamp to top-left');
  finally
    Grid.Free;
  end;
  Writeln('  OK: MoveAbs clamping passed.');
end;

procedure TestSaveRestoreCursor;
var
  Grid: TPrimaryScreenGrid;
begin
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(5, 3, Fg, Bg);
    Grid.MoveAbs(1, 3);
    Grid.SaveCursor;
    Grid.MoveAbs(2, 0);
    Assert.IsTrue((Grid.CursorRow = 2) and (Grid.CursorCol = 0), 'Cursor should have moved');
    Grid.RestoreCursor;
    Assert.IsTrue((Grid.CursorRow = 1) and (Grid.CursorCol = 3), 'RestoreCursor should return to saved position');
    // No prior save: must be a no-op, not a crash/reset-to-zero.
    Grid.Free;
    Grid := TPrimaryScreenGrid.Create;
    Grid.Alloc(5, 3, Fg, Bg);
    Grid.MoveAbs(1, 1);
    Grid.RestoreCursor;
    Assert.IsTrue((Grid.CursorRow = 1) and (Grid.CursorCol = 1), 'RestoreCursor with no prior save must be a no-op');
  finally
    Grid.Free;
  end;
  Writeln('  OK: SaveCursor/RestoreCursor passed.');
end;

procedure TestEraseLineAndDisplay;
var
  Grid: TPrimaryScreenGrid;
begin
  // Grid is 6 cols wide but rows are only ever filled with 5 chars, so
  // PutCell's own auto-wrap (which would otherwise trigger a scroll exactly
  // at the row boundary and shuffle rows via OnArchiveRow) never fires here
  // -- row transitions are explicit (NewLine+CarriageReturn) so row content
  // stays exactly where each sub-test expects it.
  Writeln('[7/9] Testing EraseLine / EraseDisplay modes...');
  Grid := TPrimaryScreenGrid.Create;
  try
    Grid.Alloc(6, 3, Fg, Bg);
    PutStr(Grid, 'AAAAA');
    Grid.NewLine(Fg, Bg);
    Grid.CarriageReturn;
    PutStr(Grid, 'BBBBB');
    Grid.NewLine(Fg, Bg);
    Grid.CarriageReturn;
    PutStr(Grid, 'CCCCC');

    // EL mode 0: cursor (col 2 on row 1) to end of line.
    Grid.MoveAbs(1, 2);
    Grid.EraseLine(0, Fg, Bg);
    Assert.IsTrue(RowText(Grid.Grid[1]) = 'BB' + StringOfChar(' ', 4), 'EL 0 should erase from cursor to EOL');

    // EL mode 1: start of line to cursor (inclusive).
    Grid.Alloc(6, 3, Fg, Bg);
    PutStr(Grid, 'AAAAA');
    Grid.MoveAbs(0, 2);
    Grid.EraseLine(1, Fg, Bg);
    Assert.IsTrue(RowText(Grid.Grid[0]) = StringOfChar(' ', 3) + 'AA' + ' ',
      'EL 1 should erase from start to cursor inclusive');

    // EL mode 2: whole line.
    Grid.Alloc(6, 3, Fg, Bg);
    PutStr(Grid, 'AAAAA');
    Grid.EraseLine(2, Fg, Bg);
    Assert.IsTrue(Trim(RowText(Grid.Grid[0])) = '', 'EL 2 should erase the whole line');

    // ED mode 0: cursor to end of screen.
    Grid.Alloc(6, 3, Fg, Bg);
    PutStr(Grid, 'AAAAA');
    Grid.NewLine(Fg, Bg);
    Grid.CarriageReturn;
    Grid.MoveAbs(1, 2);
    PutStr(Grid, 'BBB');
    Grid.MoveAbs(1, 2);
    Grid.EraseDisplay(0, Fg, Bg);
    Assert.IsTrue(RowText(Grid.Grid[0]) = 'AAAAA' + ' ', 'ED 0 must not touch rows above cursor');
    Assert.IsTrue(Trim(RowText(Grid.Grid[1])) = '', 'ED 0 should erase from cursor to EOL on cursor row');
    Assert.IsTrue(Trim(RowText(Grid.Grid[2])) = '', 'ED 0 should erase all rows below cursor');

    // ED mode 2: entire screen.
    Grid.Alloc(6, 3, Fg, Bg);
    PutStr(Grid, 'AAAAA');
    Grid.EraseDisplay(2, Fg, Bg);
    Assert.IsTrue(Trim(RowText(Grid.Grid[0])) = '', 'ED 2 should clear the entire grid');
  finally
    Grid.Free;
  end;
  Writeln('  OK: EraseLine/EraseDisplay passed.');
end;

procedure TestReflowGrowth;
var
  Grid: TPrimaryScreenGrid;
  Archived: TList<string>;
begin
  Grid := TPrimaryScreenGrid.Create;
  Archived := TList<string>.Create;
  try
    Grid.OnArchiveRow := procedure(const ARow: TTerminalRow)
      begin
        Archived.Add(RowText(ARow));
      end;
    Grid.Alloc(4, 2, Fg, Bg);
    Grid.Grid[0][0] := TCharCell.Make('0', Fg, Bg);
    Grid.Grid[1][0] := TCharCell.Make('1', Fg, Bg);
    Grid.MoveAbs(1, 0);

    Grid.Reflow(6, 5, Fg, Bg);
    Assert.IsTrue(Archived.Count = 0, 'Growth must not archive any rows');
    Assert.IsTrue(Grid.Cols = 6, 'Cols should grow to 6');
    Assert.IsTrue(Grid.Rows = 5, 'Rows should grow to 5');
    Assert.IsTrue(Grid.Grid[0][0].CharValue = '0', 'Old row 0 content must be preserved');
    Assert.IsTrue(Grid.Grid[1][0].CharValue = '1', 'Old row 1 content must be preserved');
    Assert.IsTrue(Trim(RowText(Grid.Grid[4])) = '', 'New bottom rows must be blank');
    Assert.IsTrue(Grid.CursorRow = 1, 'Cursor row unaffected by growth');
  finally
    Archived.Free;
    Grid.Free;
  end;
  Writeln('  OK: Reflow growth passed.');
end;

procedure TestReflowShrinkArchives;
var
  Grid: TPrimaryScreenGrid;
  Archived: TList<string>;
begin
  Grid := TPrimaryScreenGrid.Create;
  Archived := TList<string>.Create;
  try
    Grid.OnArchiveRow := procedure(const ARow: TTerminalRow)
      begin
        Archived.Add(RowText(ARow));
      end;
    Grid.Alloc(4, 4, Fg, Bg);
    Grid.Grid[0][0] := TCharCell.Make('0', Fg, Bg);
    Grid.Grid[1][0] := TCharCell.Make('1', Fg, Bg);
    Grid.Grid[2][0] := TCharCell.Make('2', Fg, Bg);
    Grid.Grid[3][0] := TCharCell.Make('3', Fg, Bg);
    Grid.MoveAbs(3, 0);

    Grid.Reflow(4, 2, Fg, Bg);
    Assert.IsTrue(Archived.Count = 2, 'Shrinking by 2 rows should archive exactly 2 rows');
    Assert.IsTrue(Archived[0] = '0' + StringOfChar(' ', 3), 'Oldest row (0) archived first');
    Assert.IsTrue(Archived[1] = '1' + StringOfChar(' ', 3), 'Second-oldest row (1) archived second');
    Assert.IsTrue(Grid.Rows = 2, 'Rows should shrink to 2');
    Assert.IsTrue(Grid.Grid[0][0].CharValue = '2', 'Surviving row 0 should be former row 2');
    Assert.IsTrue(Grid.Grid[1][0].CharValue = '3', 'Surviving row 1 should be former row 3');
    Assert.IsTrue(Grid.CursorRow = 1, 'Cursor row should shift down by archived-row count');
  finally
    Archived.Free;
    Grid.Free;
  end;
  Writeln('  OK: Reflow shrink-with-archive passed.');
end;

procedure TestInsertCaretColor;
begin
  Assert.IsTrue(InsertCaretColor($FF0000AA) = cInsertCaretCyan,
    'dark NDN body uses cyan, not white');
  Assert.IsTrue(InsertCaretColor($FF000000) = cInsertCaretCyan,
    'black body uses cyan');
  Assert.IsTrue(InsertCaretColor($FF1E1E2E) = cInsertCaretCyan,
    'dark editor body uses cyan');
  Assert.IsTrue(InsertCaretColor(TAlphaColors.White) = TAlphaColors.Black,
    'light cell uses black caret');
  Assert.IsTrue(InsertCaretColor($FFF5F5F5) = TAlphaColors.Black,
    'near-white cell uses black caret');
  Writeln('  OK: Insert caret color passed.');
end;

{ TTestPrimaryScreenGrid }

procedure TTestPrimaryScreenGrid.TestPutCellAndWrap;
begin
  TestPrimaryScreenGrid.TestPutCellAndWrap;
end;

procedure TTestPrimaryScreenGrid.TestNewLineScrollArchives;
begin
  TestPrimaryScreenGrid.TestNewLineScrollArchives;
end;

procedure TTestPrimaryScreenGrid.TestCarriageReturnAndBackspace;
begin
  TestPrimaryScreenGrid.TestCarriageReturnAndBackspace;
end;

procedure TTestPrimaryScreenGrid.TestDeleteCharBeforeCursor;
begin
  TestPrimaryScreenGrid.TestDeleteCharBeforeCursor;
end;

procedure TTestPrimaryScreenGrid.TestMoveAbsClamp;
begin
  TestPrimaryScreenGrid.TestMoveAbsClamp;
end;

procedure TTestPrimaryScreenGrid.TestSaveRestoreCursor;
begin
  TestPrimaryScreenGrid.TestSaveRestoreCursor;
end;

procedure TTestPrimaryScreenGrid.TestEraseLineAndDisplay;
begin
  TestPrimaryScreenGrid.TestEraseLineAndDisplay;
end;

procedure TTestPrimaryScreenGrid.TestReflowGrowth;
begin
  TestPrimaryScreenGrid.TestReflowGrowth;
end;

procedure TTestPrimaryScreenGrid.TestReflowShrinkArchives;
begin
  TestPrimaryScreenGrid.TestReflowShrinkArchives;
end;

procedure TTestPrimaryScreenGrid.TestInsertCaretColor;
begin
  TestPrimaryScreenGrid.TestInsertCaretColor;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPrimaryScreenGrid);

end.
