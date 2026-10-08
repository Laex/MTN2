unit uPrimaryScreenGrid;

{ Fixed-size PtyCols x PtyRows "active screen" grid with a real row/col
  cursor, synchronized with real conhost's own fixed viewport. Windows
  conhost (under ConPTY) uses VT cursor positioning (CUP) even for ordinary,
  non-TUI shell interaction -- prompt redraws between commands, in-place
  line editing -- not just for full-screen TUI apps, and an append-only
  scrollback without a row cursor cannot represent CUP.

  This grid is an equivalent model of conhost's viewport for the primary
  buffer: it scrolls on the same LF events, so "row N" here and "row N" from
  conhost's CUP always mean the same visual line by construction, not by
  heuristic. When a line scrolls off the top, TConsoleBuffer.ArchiveRowLocked
  (via OnArchiveRow) files it into the permanent FPlainLines/FCellLines
  archive, which is never edited in place again -- only the active grid is.

  Deliberately a separate class from TAltScreenGrid (not shared/reused),
  even though the two are structurally close: the primary and alt-screen
  buffers stay independent, so a change to one cannot break vim/htop/less
  in the other. }

interface

uses
  System.UITypes, System.Math, uTerminalTypes, uCharWidth;

type
  TArchiveRowEvent = reference to procedure(const ARow: TTerminalRow);

  TPrimaryScreenGrid = class
  private
    FGrid: TTerminalGrid;
    FCols, FRows: Integer;
    FCursorRow, FCursorCol: Integer;
    FSavedRow, FSavedCol: Integer;
    FHasSaved: Boolean;
    FOnArchiveRow: TArchiveRowEvent;
    procedure ScrollUpOne(AFg, ABg: TAlphaColor);
    procedure ClampCursor;
  public
    /// <summary>Unlike TAltScreenGrid.Alloc, clears to spaces internally
    /// (not left to a separate paired ClearAll call) -- an unfilled cell's
    /// CharValue is #0, not ' ', which corrupts TrimRight-based plain-string
    /// conversion used by TConsoleBuffer.GetLine/GetInputAfterPrompt.</summary>
    procedure Alloc(ACols, ARows: Integer; AFg, ABg: TAlphaColor);
    /// <summary>Shrinking rows archives the rows that fall off the top
    /// (oldest first, same order as normal scroll) via OnArchiveRow before
    /// discarding them -- unlike TAltScreenGrid.Reflow, which has no
    /// scrollback to preserve into.</summary>
    procedure Reflow(ACols, ARows: Integer; AFg, ABg: TAlphaColor);
    procedure ClearAll(AFg, ABg: TAlphaColor);
    procedure PutCell(ACh: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure NewLine(AFg, ABg: TAlphaColor);
    procedure CarriageReturn;
    /// <summary>Non-destructive cursor-only move (real terminal BS
    /// semantics). NOT used by the existing local backspace-erase
    /// workaround (FSuppressingBackspaceEcho) -- that calls
    /// DeleteCharBeforeCursor instead, matching TConsoleBuffer's legacy
    /// DeleteCharBeforeCursorLocked destructive behavior.</summary>
    procedure Backspace;
    /// <summary>Destructive delete-and-shift-left within the current row,
    /// matching TConsoleBuffer.DeleteCharBeforeCursorLocked's semantics
    /// exactly (same prompt-boundary guard, passed in since this grid has
    /// no knowledge of prompt-detection heuristics). Returns False if
    /// blocked by APromptGuardCol or out of range.</summary>
    function DeleteCharBeforeCursor(APromptGuardCol: Integer; AFg, ABg: TAlphaColor): Boolean;
    procedure MoveAbs(ARow, ACol: Integer);
    procedure MoveRel(ADir: Char; ACount: Integer);
    procedure SaveCursor;
    procedure RestoreCursor;
    procedure EraseDisplay(AMode: Integer; AFg, ABg: TAlphaColor);
    procedure EraseLine(AMode: Integer; AFg, ABg: TAlphaColor);
    /// <summary>ECH: blanks ACount cells from the cursor; the cursor stays.</summary>
    procedure EraseChars(ACount: Integer; AFg, ABg: TAlphaColor);
    property Grid: TTerminalGrid read FGrid;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property CursorRow: Integer read FCursorRow;
    property CursorCol: Integer read FCursorCol;
    property OnArchiveRow: TArchiveRowEvent read FOnArchiveRow write FOnArchiveRow;
  end;

implementation

procedure TPrimaryScreenGrid.ClampCursor;
begin
  FCursorRow := EnsureRange(FCursorRow, 0, Max(FRows - 1, 0));
  FCursorCol := EnsureRange(FCursorCol, 0, Max(FCols - 1, 0));
end;

procedure TPrimaryScreenGrid.Alloc(ACols, ARows: Integer; AFg, ABg: TAlphaColor);
begin
  FCols := Max(ACols, 1);
  FRows := Max(ARows, 1);
  AllocTerminalGrid(FGrid, FCols, FRows);
  ClearTerminalGrid(FGrid, AFg, ABg);
  FCursorRow := 0;
  FCursorCol := 0;
  FHasSaved := False;
end;

procedure TPrimaryScreenGrid.Reflow(ACols, ARows: Integer; AFg, ABg: TAlphaColor);
var
  NewGrid: TTerminalGrid;
  NewCols, NewRows, Y, X, CopyCols, CopyRows, ArchiveCount, SrcTop: Integer;
begin
  NewCols := Max(ACols, 1);
  NewRows := Max(ARows, 1);
  if (NewCols = FCols) and (NewRows = FRows) then
    Exit;

  ArchiveCount := 0;
  if NewRows < FRows then
    ArchiveCount := FRows - NewRows;
  if (ArchiveCount > 0) and Assigned(FOnArchiveRow) then
    for Y := 0 to ArchiveCount - 1 do
      FOnArchiveRow(FGrid[Y]);

  AllocTerminalGrid(NewGrid, NewCols, NewRows);
  ClearTerminalGrid(NewGrid, AFg, ABg);
  SrcTop := ArchiveCount;
  CopyCols := Min(NewCols, FCols);
  CopyRows := Min(NewRows, FRows - SrcTop);
  for Y := 0 to CopyRows - 1 do
    for X := 0 to CopyCols - 1 do
      NewGrid[Y][X] := FGrid[SrcTop + Y][X];
  FGrid := NewGrid;
  FCols := NewCols;
  FRows := NewRows;
  Dec(FCursorRow, ArchiveCount);
  ClampCursor;
end;

procedure TPrimaryScreenGrid.ClearAll(AFg, ABg: TAlphaColor);
begin
  ClearTerminalGrid(FGrid, AFg, ABg);
  FCursorRow := 0;
  FCursorCol := 0;
end;

procedure TPrimaryScreenGrid.ScrollUpOne(AFg, ABg: TAlphaColor);
var
  Y: Integer;
  BlankCell: TCharCell;
begin
  if Assigned(FOnArchiveRow) then
    FOnArchiveRow(FGrid[0]);
  if FRows <= 1 then
  begin
    ClearTerminalGrid(FGrid, AFg, ABg);
    Exit;
  end;
  for Y := 0 to FRows - 2 do
    FGrid[Y] := FGrid[Y + 1];
  SetLength(FGrid[FRows - 1], FCols);
  BlankCell := TCharCell.Make(' ', AFg, ABg);
  for Y := 0 to FCols - 1 do
    FGrid[FRows - 1][Y] := BlankCell;
end;

procedure TPrimaryScreenGrid.PutCell(ACh: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
var
  W: Integer;
begin
  if (FCols <= 0) or (FRows <= 0) then
    Exit;
  W := CharDisplayWidth(ACh);
  // A wide character that does not fit the last column moves to the next line.
  if (W = 2) and (FCursorCol >= FCols - 1) and (FCols > 1) then
  begin
    DrawGridChar(FGrid, FCursorCol, FCursorRow, ' ', AFg, ABg, AAttrs);
    FCursorCol := 0;
    NewLine(AFg, ABg);
  end;
  DrawGridChar(FGrid, FCursorCol, FCursorRow, ACh, AFg, ABg, AAttrs);
  Inc(FCursorCol, W);
  if FCursorCol >= FCols then
  begin
    FCursorCol := 0;
    NewLine(AFg, ABg);
  end;
end;

procedure TPrimaryScreenGrid.NewLine(AFg, ABg: TAlphaColor);
begin
  if FCursorRow < FRows - 1 then
    Inc(FCursorRow)
  else
    ScrollUpOne(AFg, ABg);
end;

procedure TPrimaryScreenGrid.CarriageReturn;
begin
  FCursorCol := 0;
end;

procedure TPrimaryScreenGrid.Backspace;
begin
  if FCursorCol > 0 then
    Dec(FCursorCol);
end;

function TPrimaryScreenGrid.DeleteCharBeforeCursor(APromptGuardCol: Integer;
  AFg, ABg: TAlphaColor): Boolean;
var
  X, Count: Integer;
  Row: TTerminalRow;
begin
  Result := False;
  if (FCursorCol <= 0) or (FCursorCol > FCols) then
    Exit;
  if (FCursorRow < 0) or (FCursorRow >= FRows) then
    Exit;
  // Mirrors TConsoleBuffer.DeleteCharBeforeCursorLocked's prompt-boundary
  // check exactly: FCursorCol sitting at or before the prompt's own end
  // means there is no typed input left to delete.
  if (APromptGuardCol > 0) and (FCursorCol <= APromptGuardCol) then
    Exit;
  Row := FGrid[FCursorRow];
  // The filler of a wide character goes together with its first half.
  Count := 1;
  if (ccaWideTail in Row[FCursorCol - 1].Attributes) and (FCursorCol >= 2) then
    Count := 2;
  for X := FCursorCol - Count to FCols - 1 - Count do
    Row[X] := Row[X + Count];
  for X := FCols - Count to FCols - 1 do
    Row[X] := TCharCell.Make(' ', AFg, ABg);
  FGrid[FCursorRow] := Row;
  Dec(FCursorCol, Count);
  Result := True;
end;

procedure TPrimaryScreenGrid.MoveAbs(ARow, ACol: Integer);
begin
  FCursorRow := ARow;
  FCursorCol := ACol;
  ClampCursor;
end;

procedure TPrimaryScreenGrid.MoveRel(ADir: Char; ACount: Integer);
begin
  case ADir of
    'A': Dec(FCursorRow, ACount);
    'B': Inc(FCursorRow, ACount);
    'C': Inc(FCursorCol, ACount);
    'D': Dec(FCursorCol, ACount);
  end;
  ClampCursor;
end;

procedure TPrimaryScreenGrid.SaveCursor;
begin
  FSavedRow := FCursorRow;
  FSavedCol := FCursorCol;
  FHasSaved := True;
end;

procedure TPrimaryScreenGrid.RestoreCursor;
begin
  if not FHasSaved then
    Exit;
  FCursorRow := FSavedRow;
  FCursorCol := FSavedCol;
  ClampCursor;
end;

procedure TPrimaryScreenGrid.EraseDisplay(AMode: Integer; AFg, ABg: TAlphaColor);
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
    2, 3: // entire visible screen
      ClearTerminalGrid(FGrid, AFg, ABg);
  else // 0: cursor to end of screen
    begin
      FillGridRect(FGrid, FCursorCol, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
      for Y := FCursorRow + 1 to FRows - 1 do
        FillGridRect(FGrid, 0, Y, FCols - 1, Y, ' ', AFg, ABg);
    end;
  end;
end;

procedure TPrimaryScreenGrid.EraseLine(AMode: Integer; AFg, ABg: TAlphaColor);
begin
  case AMode of
    1: FillGridRect(FGrid, 0, FCursorRow, FCursorCol, FCursorRow, ' ', AFg, ABg);
    2: FillGridRect(FGrid, 0, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
  else // 0: cursor to end of line
    FillGridRect(FGrid, FCursorCol, FCursorRow, FCols - 1, FCursorRow, ' ', AFg, ABg);
  end;
end;

procedure TPrimaryScreenGrid.EraseChars(ACount: Integer; AFg, ABg: TAlphaColor);
begin
  if ACount < 1 then
    ACount := 1;
  FillGridRect(FGrid, FCursorCol, FCursorRow, Min(FCursorCol + ACount - 1, FCols - 1),
    FCursorRow, ' ', AFg, ABg);
end;

end.
