unit uAltScreenGrid;

{ Fixed-size cursor-addressable screen buffer for the alternate screen
  (DECSET/DECRST 1049/47), used by TConsoleBuffer while a TUI app (vim,
  htop, less) is running. Deliberately separate from the primary scrollback:
  CUP/cursor addressing only needs to work here, not in the append-only
  primary buffer. }

interface

uses
  System.UITypes, System.Math, uTerminalTypes;

type
  TAltScreenGrid = class
  private
    FGrid: TTerminalGrid;
    FCols, FRows: Integer;
    FCursorRow, FCursorCol: Integer;
    FSavedRow, FSavedCol: Integer;
    FHasSaved: Boolean;
    procedure ScrollUpOne(AFg, ABg: TAlphaColor);
    procedure ClampCursor;
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
  ClampCursor;
end;

procedure TAltScreenGrid.ClearAll(AFg, ABg: TAlphaColor);
begin
  ClearTerminalGrid(FGrid, AFg, ABg);
  FCursorRow := 0;
  FCursorCol := 0;
end;

procedure TAltScreenGrid.ScrollUpOne(AFg, ABg: TAlphaColor);
var
  Y: Integer;
  BlankCell: TCharCell;
begin
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

procedure TAltScreenGrid.PutCell(ACh: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
begin
  if (FCols <= 0) or (FRows <= 0) then
    Exit;
  DrawGridChar(FGrid, FCursorCol, FCursorRow, ACh, AFg, ABg, AAttrs);
  Inc(FCursorCol);
  if FCursorCol >= FCols then
  begin
    FCursorCol := 0;
    NewLine(AFg, ABg);
  end;
end;

procedure TAltScreenGrid.NewLine(AFg, ABg: TAlphaColor);
begin
  if FCursorRow < FRows - 1 then
    Inc(FCursorRow)
  else
    ScrollUpOne(AFg, ABg);
end;

procedure TAltScreenGrid.CarriageReturn;
begin
  FCursorCol := 0;
end;

procedure TAltScreenGrid.Backspace;
begin
  if FCursorCol > 0 then
    Dec(FCursorCol);
end;

procedure TAltScreenGrid.MoveAbs(ARow, ACol: Integer);
begin
  FCursorRow := ARow;
  FCursorCol := ACol;
  ClampCursor;
end;

procedure TAltScreenGrid.MoveRel(ADir: Char; ACount: Integer);
begin
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

end.
