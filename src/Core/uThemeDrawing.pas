unit uThemeDrawing;

{ Concrete Host-side drawing helpers shared across dialogs/overlays/windows:
  FAR-style warning frame, drop shadows, backdrop dimming, and the frame
  close-hit test. Not part of IThemeRenderer — themes decide colors, this
  unit paints fixed FAR/NDN chrome that every theme shares. See uThemeTypes
  for the type/interface contracts these operate on. }

interface

uses
  System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes;

/// <summary>
/// FAR Warning dialog chrome: red body, white double frame, cyan title bar.
/// </summary>
procedure DrawWarningDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string);
/// <summary>
/// FAR/NDN-style dialog drop shadow (1 cell right + below). Darkens cells
/// already painted under the dialog — does not clear them to blank spaces.
/// </summary>
procedure DrawDialogShadow(const AGrid: TTerminalGrid; const ABounds: TRectI);
/// <summary>
/// Dim everything except AExcept (modal backdrop). Call before painting the
/// dialog frame so chrome stays crisp on top of a darkened scene.
/// </summary>
procedure DimGridExcept(const AGrid: TTerminalGrid; const AExcept: TRectI;
  ACover: Byte = 96);
/// <summary>
/// Button drop shadow: black ▄ to the right of the face, black ▀ below
/// (FAR/NDN half-block cast). Host paints this after button faces.
/// </summary>
procedure DrawButtonShadow(const AGrid: TTerminalGrid; const ABounds: TRectI);

/// <summary>
/// True if (AX,AY) hits the frame close mark '[x]' drawn by DrawWindowFrame
/// (top row, three cells ending just before the top-right corner).
/// </summary>
function WindowFrameCloseHit(const ABounds: TRectI; AX, AY: Integer): Boolean;

/// <summary>Blends AColor toward black; ACover = how much black to mix in
/// (0 = unchanged, 255 = pure black).</summary>
function BlendTowardBlack(AColor: TAlphaColor; ACover: Byte): TAlphaColor;
/// <summary>Pick a glyph foreground that stays readable on ABg. Uses
/// APreferred when its luma is far enough from the background (window/dialog
/// close accent, tab close), otherwise AFallback (usually the tab's own text
/// colour), otherwise white or black.</summary>
function ContrastingGlyphFg(ABg, APreferred, AFallback: TAlphaColor): TAlphaColor;

/// <summary>
/// Vertical "dialog-style" scrollbar: black ▲/▼ arrows, track and thumb on
/// a fixed white/black/cyan palette (not theme-dependent) — every plain
/// declarative dialog list (TDialogHost.DrawListScrollBar) and the
/// ADialogStyle overlays in uDualPanelDrawUtils.DrawPanelScrollBar (Change
/// Drive / Sort / Column popups) share this exact chrome.
/// </summary>
procedure DrawDialogScrollBar(const AGrid: TTerminalGrid; AX, ATop, ABottom, APos,
  ACount, AViewH: Integer);

implementation

procedure DrawWarningDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string);
var
  X, Y, W: Integer;
  Cap: string;
  StartX, BtnX: Integer;
const
  cWarnFg     = TAlphaColor($FFFFFFFF);
  cWarnBg     = TAlphaColor($FFAA0000);
  cWarnBorder = TAlphaColor($FFFFFFFF);
  cTitleFg    = TAlphaColor($FF000000);
  cTitleBg    = TAlphaColor($FF00AAAA);
  cCloseHot   = TAlphaColor($FFFF55FF);
begin
  W := ABounds.Width;
  if (W < 2) or (ABounds.Height < 2) then
    Exit;
  FillGridRect(AGrid, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', cWarnFg, cWarnBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chDblTL, cWarnBorder, cWarnBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chDblTR, cWarnBorder, cWarnBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chDblBL, cWarnBorder, cWarnBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chDblBR, cWarnBorder, cWarnBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chDblH, cWarnBorder, cWarnBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chDblH, cWarnBorder, cWarnBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chDblV, cWarnBorder, cWarnBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chDblV, cWarnBorder, cWarnBg);
  end;
  BtnX := ABounds.Right - 3;
  if BtnX > ABounds.Left + 2 then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, '[x]', cWarnBorder, cWarnBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cCloseHot, cWarnBg);
  end;
  if ATitle <> '' then
  begin
    Cap := ' ' + ATitle + ' ';
    if Length(Cap) > W - 5 then
      Cap := Copy(Cap, 1, Max(W - 5, 1));
    StartX := ABounds.Left + (W - Length(Cap)) div 2;
    if StartX < ABounds.Left + 1 then
      StartX := ABounds.Left + 1;
    PutGridText(AGrid, StartX, ABounds.Top, Cap, cTitleFg, cTitleBg);
  end;
end;

function BlendTowardBlack(AColor: TAlphaColor; ACover: Byte): TAlphaColor;
var
  Src: TAlphaColorRec absolute AColor;
  Dst: TAlphaColorRec absolute Result;
  Keep: Integer;
begin
  // ACover = how much black to mix in (0 = unchanged, 255 = pure black).
  Keep := 255 - Integer(ACover);
  Dst.A := Src.A;
  Dst.R := Byte((Integer(Src.R) * Keep) div 255);
  Dst.G := Byte((Integer(Src.G) * Keep) div 255);
  Dst.B := Byte((Integer(Src.B) * Keep) div 255);
end;

function GlyphLuma(AColor: TAlphaColor): Integer;
var
  C: TAlphaColorRec absolute AColor;
begin
  Result := (299 * Integer(C.R) + 587 * Integer(C.G) + 114 * Integer(C.B)) div 1000;
end;

function ContrastingGlyphFg(ABg, APreferred, AFallback: TAlphaColor): TAlphaColor;
const
  cMinDelta = 80;
  cWhite = TAlphaColor($FFFFFFFF);
  cBlack = TAlphaColor($FF000000);
var
  BgL: Integer;

  function Delta(AFg: TAlphaColor): Integer;
  var
    D: Integer;
  begin
    D := GlyphLuma(AFg) - BgL;
    if D < 0 then
      D := -D;
    Result := D;
  end;

begin
  BgL := GlyphLuma(ABg);
  if Delta(APreferred) >= cMinDelta then
    Exit(APreferred);
  if Delta(AFallback) >= cMinDelta then
    Exit(AFallback);
  if BgL < 140 then
    Result := cWhite
  else
    Result := cBlack;
end;

procedure DrawDialogScrollBar(const AGrid: TTerminalGrid; AX, ATop, ABottom, APos,
  ACount, AViewH: Integer);
var
  Span, ThumbAt, I: Integer;
  TrackFg, TrackBg, ThumbFg: TAlphaColor;
begin
  Span := ABottom - ATop + 1;
  if Span < 2 then
    Exit;
  TrackFg := TAlphaColor($FF000000);
  TrackBg := TAlphaColor($FFFFFFFF);
  ThumbFg := TAlphaColor($FF00AAAA);
  DrawGridChar(AGrid, AX, ATop, #$25B2, TrackFg, TrackBg); // ▲
  DrawGridChar(AGrid, AX, ABottom, #$25BC, TrackFg, TrackBg); // ▼
  for I := ATop + 1 to ABottom - 1 do
    DrawGridChar(AGrid, AX, I, chShadeLight, TrackFg, TrackBg);
  ThumbAt := ATop + 1;
  if (ACount > AViewH) and (Span > 3) then
    Inc(ThumbAt, EnsureRange(Round(APos * (Span - 3) / Max(ACount - AViewH, 1)),
      0, Span - 3));
  DrawGridChar(AGrid, AX, ThumbAt, chBlock, ThumbFg, TrackBg);
end;

const
  // Single shadow strength shared by DrawDialogShadow and DrawButtonShadow
  // (was two separate constants, each with its own Skia/non-Skia split, and
  // DrawButtonShadow additionally graded a "near"/"far" pair — that second,
  // lighter tone plus Skia's own glyph-edge antialiasing read as a shadow
  // cast on top of a shadow. One strength, used the same way in both places,
  // fixes that. Stronger under Skia where subpixel AA makes a softer strip
  // read better than flat gray replacement.
  {$IFDEF SKIA}
  cShadowCover = 168;
  {$ELSE}
  cShadowCover = 200;
  {$ENDIF}

procedure DrawDialogShadow(const AGrid: TTerminalGrid; const ABounds: TRectI);
var
  X, Y: Integer;
  Cell: TCharCell;

  procedure ShadeCell(AX, AY: Integer);
  var
    Next: TCharCell;
  begin
    if (AY < 0) or (AY > High(AGrid)) then
      Exit;
    if (AX < 0) or (AX > High(AGrid[AY])) then
      Exit;
    Cell := AGrid[AY][AX];
    Next := TCharCell.Make(Cell.CharValue,
      BlendTowardBlack(Cell.FgColor, cShadowCover),
      BlendTowardBlack(Cell.BgColor, cShadowCover),
      Cell.Attributes);
    Next.IconId := Cell.IconId;
    AGrid[AY][AX] := Next;
  end;

begin
  if (ABounds.Width < 2) or (ABounds.Height < 2) then
    Exit;
  // Right strip (starts one row below the top corner — classic FAR look).
  for Y := ABounds.Top + 1 to ABounds.Bottom + 1 do
    ShadeCell(ABounds.Right + 1, Y);
  // Bottom strip (Left+1 .. Right inclusive; corner already shaded above).
  for X := ABounds.Left + 1 to ABounds.Right do
    ShadeCell(X, ABounds.Bottom + 1);
end;

procedure DimGridExcept(const AGrid: TTerminalGrid; const AExcept: TRectI;
  ACover: Byte);
var
  X, Y: Integer;
  Cell, Next: TCharCell;
begin
  if ACover = 0 then
    Exit;
  for Y := 0 to High(AGrid) do
    for X := 0 to High(AGrid[Y]) do
    begin
      if AExcept.Contains(X, Y) then
        Continue;
      Cell := AGrid[Y][X];
      Next := TCharCell.Make(Cell.CharValue,
        BlendTowardBlack(Cell.FgColor, ACover),
        BlendTowardBlack(Cell.BgColor, ACover),
        Cell.Attributes);
      Next.IconId := Cell.IconId;
      AGrid[Y][X] := Next;
    end;
end;

procedure DrawButtonShadow(const AGrid: TTerminalGrid; const ABounds: TRectI);
var
  X, Y: Integer;
  Bg: TAlphaColor;

  function CellBg(AX, AY: Integer): TAlphaColor;
  begin
    if (AY >= 0) and (AY <= High(AGrid)) and
       (AX >= 0) and (AX <= High(AGrid[AY])) then
      Result := AGrid[AY][AX].BgColor
    else
      Result := TAlphaColor($FFFFFFFF);
  end;

begin
  if (ABounds.Width < 1) or (ABounds.Height < 1) then
    Exit;
  // Half-block glyph (▄/▀), single darkened tone (cShadowCover, same one
  // DrawDialogShadow uses) — the glyph's own half of the cell is the shadow;
  // the other half keeps the panel color under it exactly as-is (not a
  // second, lighter darken pass), so there's one shadow edge, not two.
  // Right of face: ▄ (lower half block).
  for Y := ABounds.Top to ABounds.Bottom do
  begin
    Bg := CellBg(ABounds.Right + 1, Y);
    DrawGridChar(AGrid, ABounds.Right + 1, Y, chLowerHalf, BlendTowardBlack(Bg, cShadowCover), Bg);
  end;
  // Below face: ▀ (upper half block), Left+1 .. Right+1 (corner included).
  for X := ABounds.Left + 1 to ABounds.Right + 1 do
  begin
    Bg := CellBg(X, ABounds.Bottom + 1);
    DrawGridChar(AGrid, X, ABounds.Bottom + 1, chUpperHalf, BlendTowardBlack(Bg, cShadowCover), Bg);
  end;
end;

function WindowFrameCloseHit(const ABounds: TRectI; AX, AY: Integer): Boolean;
var
  BtnX: Integer;
const
  cCloseW = 3; // '[x]'
begin
  Result := False;
  if AY <> ABounds.Top then
    Exit;
  // Match TNDNTheme.DrawWindowFrame: BtnX := Right - Length('[x]').
  BtnX := ABounds.Right - cCloseW;
  if BtnX <= ABounds.Left + 2 then
    Exit; // no room — theme skips the mark
  Result := (AX >= BtnX) and (AX < BtnX + cCloseW);
end;

end.
