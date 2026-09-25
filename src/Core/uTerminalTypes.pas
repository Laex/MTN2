unit uTerminalTypes;

interface

uses
  System.UITypes;

type
  TCharCellAttribute = (ccaBold, ccaItalic, ccaUnderline, ccaBlink, ccaReverse,
    ccaInsertCaret);
  TCharCellAttributes = set of TCharCellAttribute;

  TCharCell = record
    CharValue: Char;
    FgColor: TAlphaColor;
    BgColor: TAlphaColor;
    Attributes: TCharCellAttributes;
    /// <summary>Shell icon cache id (0 = none). Drawn by TTerminalRenderer.</summary>
    IconId: Integer;
    class function Make(const AChar: Char; AFg, ABg: TAlphaColor;
      AAttributes: TCharCellAttributes = []): TCharCell; static;
  end;

  TTerminalRow = TArray<TCharCell>;
  TTerminalGrid = TArray<TTerminalRow>;

const
  // Box-drawing glyphs (rendered as vector strokes by the terminal renderer,
  // see TTerminalRenderer.DrawBoxGlyph). #$XXXX is a WideChar constant.
  chBoxH  = #$2500; // ─
  chBoxV  = #$2502; // │
  chBoxTL = #$250C; // ┌
  chBoxTR = #$2510; // ┐
  chBoxBL = #$2514; // └
  chBoxBR = #$2518; // ┘
  chBoxVR = #$251C; // ├
  chBoxVL = #$2524; // ┤
  chBoxHD = #$252C; // ┬
  chBoxHU = #$2534; // ┴
  chBoxX  = #$253C; // ┼

  chDblH  = #$2550; // ═
  chDblV  = #$2551; // ║
  chDblTL = #$2554; // ╔
  chDblTR = #$2557; // ╗
  chDblBL = #$255A; // ╚
  chDblBR = #$255D; // ╝
  chDblVR = #$2560; // ╠
  chDblVL = #$2563; // ╣
  chDblHD = #$2566; // ╦
  chDblHU = #$2569; // ╩
  chDblX  = #$256C; // ╬
  // Mixed: double vertical + single horizontal (T-junction into ─)
  chDblVSingleHR = #$255F; // ╟
  chDblVSingleHL = #$2562; // ╢

  chShadeLight = #$2591; // ░
  chBlock      = #$2588; // █
  chLowerHalf  = #$2584; // ▄  (button shadow, right of face)
  chUpperHalf  = #$2580; // ▀  (button shadow, below face)

  /// Insert-caret bar on dark cells. White on dark body sits on light glyphs.
  cInsertCaretCyan = TAlphaColor($FF3CE0E0);

procedure AllocTerminalGrid(var AGrid: TTerminalGrid; ACols, ARows: Integer);
procedure ClearTerminalGrid(var AGrid: TTerminalGrid; AFg, ABg: TAlphaColor;
  AFillChar: Char = ' ');
procedure PutTerminalText(var AGrid: TTerminalGrid; AX, AY: Integer;
  const AText: string; AFg, ABg: TAlphaColor;
  AAttributes: TCharCellAttributes = []);

// Element-level helpers that accept a `const` grid: dynamic arrays are
// references, so cell assignment is allowed while the array itself stays fixed.
// These are used by IThemeRenderer implementations and TTerminalWindow.
procedure DrawGridChar(const AGrid: TTerminalGrid; AX, AY: Integer;
  const ACh: Char; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes = []);
/// <summary>Place a shell-icon cell (fallback glyph if renderer has no bitmap).</summary>
procedure DrawGridIcon(const AGrid: TTerminalGrid; AX, AY, AIconId: Integer;
  const AFallback: Char; AFg, ABg: TAlphaColor);
procedure FillGridRect(const AGrid: TTerminalGrid;
  ALeft, ATop, ARight, ABottom: Integer; const ACh: Char; AFg, ABg: TAlphaColor);
procedure PutGridText(const AGrid: TTerminalGrid; AX, AY: Integer;
  const AText: string; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes = []);
/// <summary>Like PutGridText, but stops at AMaxX (inclusive) instead of writing
/// past it -- for fixed-width widgets (e.g. a button box) whose caption may
/// run longer than the box in a locale other than the one the box was sized
/// for, so the overflow can't bleed into whatever sits to the right of it.</summary>
procedure PutGridTextClipped(const AGrid: TTerminalGrid; AX, AY, AMaxX: Integer;
  const AText: string; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes = []);
/// <summary>Mark a cell for a 2-px insert caret at its left edge (drawn after glyphs).</summary>
procedure MarkGridInsertCaret(const AGrid: TTerminalGrid; AX, AY: Integer);
/// <summary>Bar color that stays visible on ACellBg (cyan on dark, black on light).</summary>
function InsertCaretColor(ACellBg: TAlphaColor): TAlphaColor;
function SameCharCell(const C1, C2: TCharCell): Boolean; inline;

implementation

function SameCharCell(const C1, C2: TCharCell): Boolean;
begin
  Result := (C1.CharValue = C2.CharValue) and
            (C1.FgColor = C2.FgColor) and
            (C1.BgColor = C2.BgColor) and
            (C1.Attributes = C2.Attributes) and
            (C1.IconId = C2.IconId);
end;

class function TCharCell.Make(const AChar: Char; AFg, ABg: TAlphaColor;
  AAttributes: TCharCellAttributes): TCharCell;
begin
  Result.CharValue := AChar;
  Result.FgColor := AFg;
  Result.BgColor := ABg;
  Result.Attributes := AAttributes;
  Result.IconId := 0;
end;

procedure AllocTerminalGrid(var AGrid: TTerminalGrid; ACols, ARows: Integer);
var
  Y: Integer;
begin
  if ACols < 1 then
    ACols := 1;
  if ARows < 1 then
    ARows := 1;
  SetLength(AGrid, ARows);
  for Y := 0 to ARows - 1 do
    SetLength(AGrid[Y], ACols);
end;

procedure ClearTerminalGrid(var AGrid: TTerminalGrid; AFg, ABg: TAlphaColor;
  AFillChar: Char);
var
  X, Y, Cols: Integer;
  BlankCell: TCharCell;
begin
  BlankCell := TCharCell.Make(AFillChar, AFg, ABg);
  for Y := 0 to High(AGrid) do
  begin
    Cols := Length(AGrid[Y]);
    if Cols > 0 then
    begin
      AGrid[Y][0] := BlankCell;
      for X := 1 to Cols - 1 do
        AGrid[Y][X] := BlankCell;
    end;
  end;
end;

procedure PutTerminalText(var AGrid: TTerminalGrid; AX, AY: Integer;
  const AText: string; AFg, ABg: TAlphaColor;
  AAttributes: TCharCellAttributes);
var
  I, X, Cols, Rows: Integer;
begin
  Rows := Length(AGrid);
  if (Rows = 0) or (AY < 0) or (AY >= Rows) then
    Exit;
  Cols := Length(AGrid[AY]);
  for I := 1 to Length(AText) do
  begin
    X := AX + I - 1;
    if (X < 0) or (X >= Cols) then
      Continue;
    AGrid[AY][X] := TCharCell.Make(AText[I], AFg, ABg, AAttributes);
  end;
end;

procedure DrawGridChar(const AGrid: TTerminalGrid; AX, AY: Integer;
  const ACh: Char; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes);
begin
  if (AY < 0) or (AY > High(AGrid)) then
    Exit;
  if (AX < 0) or (AX > High(AGrid[AY])) then
    Exit;
  AGrid[AY][AX] := TCharCell.Make(ACh, AFg, ABg, AAttr);
end;

procedure DrawGridIcon(const AGrid: TTerminalGrid; AX, AY, AIconId: Integer;
  const AFallback: Char; AFg, ABg: TAlphaColor);
var
  Cell: TCharCell;
begin
  if (AY < 0) or (AY > High(AGrid)) then
    Exit;
  if (AX < 0) or (AX > High(AGrid[AY])) then
    Exit;
  Cell := TCharCell.Make(AFallback, AFg, ABg);
  Cell.IconId := AIconId;
  AGrid[AY][AX] := Cell;
end;

procedure FillGridRect(const AGrid: TTerminalGrid;
  ALeft, ATop, ARight, ABottom: Integer; const ACh: Char; AFg, ABg: TAlphaColor);
var
  X, Y: Integer;
begin
  for Y := ATop to ABottom do
    for X := ALeft to ARight do
      DrawGridChar(AGrid, X, Y, ACh, AFg, ABg);
end;

procedure PutGridText(const AGrid: TTerminalGrid; AX, AY: Integer;
  const AText: string; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes);
var
  I: Integer;
begin
  for I := 1 to Length(AText) do
    DrawGridChar(AGrid, AX + I - 1, AY, AText[I], AFg, ABg, AAttr);
end;

procedure PutGridTextClipped(const AGrid: TTerminalGrid; AX, AY, AMaxX: Integer;
  const AText: string; AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes);
var
  I, X: Integer;
begin
  for I := 1 to Length(AText) do
  begin
    X := AX + I - 1;
    if X > AMaxX then
      Break;
    DrawGridChar(AGrid, X, AY, AText[I], AFg, ABg, AAttr);
  end;
end;

procedure MarkGridInsertCaret(const AGrid: TTerminalGrid; AX, AY: Integer);
begin
  if (AY < 0) or (AY > High(AGrid)) then
    Exit;
  if (AX < 0) or (AX > High(AGrid[AY])) then
    Exit;
  Include(AGrid[AY][AX].Attributes, ccaInsertCaret);
end;

function InsertCaretColor(ACellBg: TAlphaColor): TAlphaColor;
var
  Rec: TAlphaColorRec;
  Lum: Integer;
begin
  Rec.Color := ACellBg;
  Lum := (Integer(Rec.R) * 299 + Integer(Rec.G) * 587 + Integer(Rec.B) * 114) div 1000;
  if Lum < 140 then
    Result := cInsertCaretCyan
  else
    Result := TAlphaColors.Black;
end;

end.
