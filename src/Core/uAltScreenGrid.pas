unit uAltScreenGrid;

{ Fixed-size cursor-addressable screen buffer for the alternate screen
  (DECSET/DECRST 1049/47), used by TConsoleBuffer while a TUI app (vim,
  htop, less) is running. Deliberately separate from the primary scrollback:
  CUP/cursor addressing only needs to work here, not in the append-only
  primary buffer. }

interface

uses
  System.UITypes, System.Math, uTerminalTypes, uCharWidth;

type
  TAltScreenGrid = class
  private
    FGrid: TTerminalGrid;
    FCols, FRows: Integer;
    FCursorRow, FCursorCol: Integer;
    FSavedRow, FSavedCol: Integer;
    FHasSaved: Boolean;
    // Last column written: the wrap to the next line happens on the next
    // printable character, not on this one (xterm semantics).
    FWrapPending: Boolean;
    // Scroll region (DECSTBM), inclusive row indexes.
    FRegionTop, FRegionBottom: Integer;
    procedure ScrollUpOne(AFg, ABg: TAlphaColor);
    procedure ClampCursor;
    procedure BlankRow(ARow: Integer; AFg, ABg: TAlphaColor);
    procedure ScrollRegion(ATop, ABottom, ACount: Integer; AFg, ABg: TAlphaColor);
  public
    procedure Alloc(ACols, ARows: Integer);
    procedure Reflow(ACols, ARows: Integer);
    procedure ClearAll(AFg, ABg: TAlphaColor);
    procedure PutCell(ACh: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure NewLine(AFg, ABg: TAlphaColor);
    procedure CarriageReturn;
    procedure Backspace;
    procedure MoveAbs(ARow, ACol: Integer);
    procedure MoveRel(ADir: Char; ACount: Integer);
    procedure SaveCursor;
    procedure RestoreCursor;
    procedure EraseDisplay(AMode: Integer; AFg, ABg: TAlphaColor);
    procedure EraseLine(AMode: Integer; AFg, ABg: TAlphaColor);
    /// <summary>ECH: blanks ACount cells from the cursor; the cursor stays.</summary>
    procedure EraseChars(ACount: Integer; AFg, ABg: TAlphaColor);
    /// <summary>ICH: shifts the rest of the row right, opening blank cells.</summary>
    procedure InsertChars(ACount: Integer; AFg, ABg: TAlphaColor);
    /// <summary>DCH: removes cells at the cursor, pulling the rest of the row left.</summary>
    procedure DeleteChars(ACount: Integer; AFg, ABg: TAlphaColor);
    /// <summary>IL / DL: inside the scroll region only.</summary>
    procedure InsertLines(ACount: Integer; AFg, ABg: TAlphaColor);
    procedure DeleteLines(ACount: Integer; AFg, ABg: TAlphaColor);
    /// <summary>SU / SD: scrolls the region; positive counts move content up.</summary>
    procedure ScrollLines(ACount: Integer; AFg, ABg: TAlphaColor);
    /// <summary>DECSTBM with 1-based rows; 0 means the screen edge.</summary>
    procedure SetScrollRegion(ATop, ABottom: Integer);
    /// <summary>RI: up one row, scrolling the region down at its top.</summary>
    procedure ReverseIndex(AFg, ABg: TAlphaColor);
    procedure MoveCol(ACol: Integer);
    procedure MoveRow(ARow: Integer);
    property Grid: TTerminalGrid read FGrid;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property CursorRow: Integer read FCursorRow;
    property CursorCol: Integer read FCursorCol;
  end;

implementation

procedure TAltScreenGrid.ClampCursor;
begin
  FCursorRow := EnsureRange(FCursorRow, 0, Max(FRows - 1, 0));
  FCursorCol := EnsureRange(FCursorCol, 0, Max(FCols - 1, 0));
end;

procedure TAltScreenGrid.Alloc(ACols, ARows: Integer);
begin
  FCols := Max(ACols, 1);
  FRows := Max(ARows, 1);
  AllocTerminalGrid(FGrid, FCols, FRows);
  FCursorRow := 0;
  FCursorCol := 0;
  FHasSaved := False;
  FWrapPending := False;
  FRegionTop := 0;
  FRegionBottom := FRows - 1;
end;

procedure TAltScreenGrid.Reflow(ACols, ARows: Integer);
var
  NewGrid: TTerminalGrid;
  NewCols, NewRows, Y, X, CopyCols, CopyRows: Integer;
begin
  NewCols := Max(ACols, 1);
  NewRows := Max(ARows, 1);
  if (NewCols = FCols) and (NewRows = FRows) then
    Exit;
  AllocTerminalGrid(NewGrid, NewCols, NewRows);
  CopyCols := Min(NewCols, FCols);
  CopyRows := Min(NewRows, FRows);
  for Y := 0 to CopyRows - 1 do
    for X := 0 to CopyCols - 1 do
      NewGrid[Y][X] := FGrid[Y][X];
  FGrid := NewGrid;
  FCols := NewCols;
  FRows := NewRows;
  FWrapPending := False;
  FRegionTop := 0;
  FRegionBottom := FRows - 1;
  ClampCursor;
end;

procedure TAltScreenGrid.ClearAll(AFg, ABg: TAlphaColor);
begin
  ClearTerminalGrid(FGrid, AFg, ABg);
  FCursorRow := 0;
  FCursorCol := 0;
  FWrapPending := False;
end;

procedure TAltScreenGrid.BlankRow(ARow: Integer; AFg, ABg: TAlphaColor);
var
  X: Integer;
  BlankCell: TCharCell;
begin
  SetLength(FGrid[ARow], FCols);
  BlankCell := TCharCell.Make(' ', AFg, ABg);
  for X := 0 to FCols - 1 do
    FGrid[ARow][X] := BlankCell;
end;

// Positive ACount moves the rows ATop..ABottom up (blank rows enter at the
// bottom), negative moves them down.
procedure TAltScreenGrid.ScrollRegion(ATop, ABottom, ACount: Integer; AFg, ABg: TAlphaColor);
var
  Y, N: Integer;
begin
  if (ATop < 0) or (ABottom >= FRows) or (ATop > ABottom) or (ACount = 0) then
    Exit;
  N := Min(Abs(ACount), ABottom - ATop + 1);
  if ACount > 0 then
  begin
    for Y := ATop to ABottom - N do
      FGrid[Y] := FGrid[Y + N];
    for Y := ABottom - N + 1 to ABottom do
      BlankRow(Y, AFg, ABg);
  end
  else
  begin
    for Y := ABottom downto ATop + N do
      FGrid[Y] := FGrid[Y - N];
    for Y := ATop to ATop + N - 1 do
      BlankRow(Y, AFg, ABg);
  end;
end;

procedure TAltScreenGrid.ScrollUpOne(AFg, ABg: TAlphaColor);
begin
  ScrollRegion(FRegionTop, FRegionBottom, 1, AFg, ABg);
end;

procedure TAltScreenGrid.PutCell(ACh: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
var
  W: Integer;
begin
  if (FCols <= 0) or (FRows <= 0) then
    Exit;
  if FWrapPending then
  begin
    FCursorCol := 0;
    NewLine(AFg, ABg);
  end;
  W := CharDisplayWidth(ACh);
  // A wide character that does not fit the last column moves to the next line.
  if (W = 2) and (FCursorCol >= FCols - 1) and (FCols > 1) then
  begin
    DrawGridChar(FGrid, FCursorCol, FCursorRow, ' ', AFg, ABg, AAttrs);
    FCursorCol := 0;
    NewLine(AFg, ABg);
  end;
  DrawGridChar(FGrid, FCursorCol, FCursorRow, ACh, AFg, ABg, AAttrs);
  if FCursorCol + W >= FCols then
  begin
    FCursorCol := FCols - 1;
    FWrapPending := True;
  end
  else
    Inc(FCursorCol, W);
end;

procedure TAltScreenGrid.NewLine(AFg, ABg: TAlphaColor);
begin
  FWrapPending := False;
  if FCursorRow = FRegionBottom then
    ScrollUpOne(AFg, ABg)
  else if FCursorRow < FRows - 1 then
    Inc(FCursorRow);
end;

procedure TAltScreenGrid.CarriageReturn;
begin
  FWrapPending := False;
  FCursorCol := 0;
end;

procedure TAltScreenGrid.Backspace;
begin
  FWrapPending := False;
  if FCursorCol > 0 then
    Dec(FCursorCol);
end;

procedure TAltScreenGrid.MoveAbs(ARow, ACol: Integer);
begin
  FWrapPending := False;
  FCursorRow := ARow;
  FCursorCol := ACol;
  ClampCursor;
end;

procedure TAltScreenGrid.MoveRel(ADir: Char; ACount: Integer);
begin
  FWrapPending := False;
  case ADir of
    'A': Dec(FCursorRow, ACount);
    'B': Inc(FCursorRow, ACount);
    'C': Inc(FCursorCol, ACount);
    'D': Dec(FCursorCol, ACount);
  end;
  ClampCursor;
end;

procedure TAltScreenGrid.SaveCursor;
begin
  FSavedRow := FCursorRow;
  FSavedCol := FCursorCol;
  FHasSaved := True;
end;

procedure TAltScreenGrid.RestoreCursor;
begin
  if not FHasSaved then
    Exit;
  FWrapPending := False;
  FCursorRow := FSavedRow;
  FCursorCol := FSavedCol;
  ClampCursor;
end;

procedure TAltScreenGrid.EraseDisplay(AMode: Integer; AFg, ABg: TAlphaColor);
var
  Y: Integer;
begin
  case AMode of
    1: // start of screen to cursor (inclusive)
      begin
        for Y := 0 to FCursorRow - 1 do
          FillGridRect(FGrid, 0, Y, FCols - 1, Y, ' ', AFg, ABg);
        FillGridRect(FGrid, 0, FCursorRow, FCursorCol, FCursorRow, ' ', AFg, ABg);
      end;
    2, 3: // entire screen (3 also clears scrollback, which the alt grid has none of)
      ClearTerminalGrid(FGrid, AFg, ABg);
  else // 0: cursor to end of screen
    begin
      FillGridRect(FGrid, FCursorCol, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
      for Y := FCursorRow + 1 to FRows - 1 do
        FillGridRect(FGrid, 0, Y, FCols - 1, Y, ' ', AFg, ABg);
    end;
  end;
end;

procedure TAltScreenGrid.EraseLine(AMode: Integer; AFg, ABg: TAlphaColor);
begin
  case AMode of
    1: FillGridRect(FGrid, 0, FCursorRow, FCursorCol, FCursorRow, ' ', AFg, ABg);
    2: FillGridRect(FGrid, 0, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
  else // 0: cursor to end of line
    FillGridRect(FGrid, FCursorCol, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
  end;
end;

procedure TAltScreenGrid.EraseChars(ACount: Integer; AFg, ABg: TAlphaColor);
begin
  if ACount < 1 then
    ACount := 1;
  FillGridRect(FGrid, FCursorCol, FCursorRow, Min(FCursorCol + ACount - 1, FCols - 1),
    FCursorRow, ' ', AFg, ABg);
end;

procedure TAltScreenGrid.InsertChars(ACount: Integer; AFg, ABg: TAlphaColor);
var
  X, N: Integer;
  Row: TTerminalRow;
begin
  FWrapPending := False;
  N := EnsureRange(ACount, 1, FCols - FCursorCol);
  Row := FGrid[FCursorRow];
  for X := FCols - 1 downto FCursorCol + N do
    Row[X] := Row[X - N];
  for X := FCursorCol to FCursorCol + N - 1 do
    Row[X] := TCharCell.Make(' ', AFg, ABg);
  FGrid[FCursorRow] := Row;
end;

procedure TAltScreenGrid.DeleteChars(ACount: Integer; AFg, ABg: TAlphaColor);
var
  X, N: Integer;
  Row: TTerminalRow;
begin
  FWrapPending := False;
  N := EnsureRange(ACount, 1, FCols - FCursorCol);
  Row := FGrid[FCursorRow];
  for X := FCursorCol to FCols - 1 - N do
    Row[X] := Row[X + N];
  for X := FCols - N to FCols - 1 do
    Row[X] := TCharCell.Make(' ', AFg, ABg);
  FGrid[FCursorRow] := Row;
end;

procedure TAltScreenGrid.InsertLines(ACount: Integer; AFg, ABg: TAlphaColor);
begin
  if (FCursorRow < FRegionTop) or (FCursorRow > FRegionBottom) then
    Exit;
  FWrapPending := False;
  FCursorCol := 0;
  ScrollRegion(FCursorRow, FRegionBottom, -Max(ACount, 1), AFg, ABg);
end;

procedure TAltScreenGrid.DeleteLines(ACount: Integer; AFg, ABg: TAlphaColor);
begin
  if (FCursorRow < FRegionTop) or (FCursorRow > FRegionBottom) then
    Exit;
  FWrapPending := False;
  FCursorCol := 0;
  ScrollRegion(FCursorRow, FRegionBottom, Max(ACount, 1), AFg, ABg);
end;

procedure TAltScreenGrid.ScrollLines(ACount: Integer; AFg, ABg: TAlphaColor);
begin
  ScrollRegion(FRegionTop, FRegionBottom, ACount, AFg, ABg);
end;

procedure TAltScreenGrid.SetScrollRegion(ATop, ABottom: Integer);
begin
  if ATop < 1 then
    ATop := 1;
  if (ABottom < 1) or (ABottom > FRows) then
    ABottom := FRows;
  if ATop >= ABottom then
  begin
    ATop := 1;
    ABottom := FRows;
  end;
  FRegionTop := ATop - 1;
  FRegionBottom := ABottom - 1;
  MoveAbs(0, 0);
end;

procedure TAltScreenGrid.ReverseIndex(AFg, ABg: TAlphaColor);
begin
  FWrapPending := False;
  if FCursorRow = FRegionTop then
    ScrollRegion(FRegionTop, FRegionBottom, -1, AFg, ABg)
  else if FCursorRow > 0 then
    Dec(FCursorRow);
end;

procedure TAltScreenGrid.MoveCol(ACol: Integer);
begin
  MoveAbs(FCursorRow, ACol);
end;

procedure TAltScreenGrid.MoveRow(ARow: Integer);
begin
  MoveAbs(ARow, FCursorCol);
end;

end.
