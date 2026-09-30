unit uColorPickerControl;

{ State, drawing and input of the color picker dialog control (dckColorPicker,
  TDialogHost). One control holds the whole picker:

    lines 0..8   a swatch grid: 24 hues across, 9 lightness levels down, at
                 the saturation of the grid (GridSat)
    line  9      a gray ramp, black to white
    lines 10..15 sliders H, S, L, R, G, B (the bar shows the color along the
                 channel)
    line  16     a hex input, with the original ("was") and current ("now")
                 swatches

  Up / Down move between the lines, Left / Right move the grid cursor or
  change the slider (Shift or PgUp / PgDn by 10, Home / End to the ends).
  The grid and the sliders keep the color in step; H, S and L are kept as
  entered so a hue does not jump at black, white or gray. A mouse click picks
  a grid cell, sets a slider, edits the hex field, or restores the original
  color from the "was" swatch. }

interface

uses
  System.Classes, System.UITypes,
  uTerminalTypes, uInputLine;

const
  /// <summary>Where a picker starts when the field it edits has no color yet.</summary>
  cPickerNoColor: TAlphaColor = $FF808080;
  cPickerWidth = 50;
  cPickerHeight = 17;
  cPickerHues = 24;
  cPickerLightRows = 9;
  cPickerGrayLine = 9;
  cPickerLineH = 10;
  cPickerLineS = 11;
  cPickerLineL = 12;
  cPickerLineR = 13;
  cPickerLineG = 14;
  cPickerLineB = 15;
  cPickerLineHex = 16;

type
  TColorPickerState = record
    Color: TAlphaColor;
    Orig: TAlphaColor;
    H, S, L: Integer;
    GridSat: Integer;
    Line: Integer;
    GridCol: Integer;
    HexEdit: TInputLine;
  end;

function ColorPickerEmpty: TColorPickerState;
/// <summary>AColor is the color being edited, AOrig what "was" shows.</summary>
procedure ColorPickerInit(var S: TColorPickerState; AColor, AOrig: TAlphaColor);
procedure ColorPickerSetColor(var S: TColorPickerState; AColor: TAlphaColor);
/// <summary>"#RRGGBB" of the current color.</summary>
function ColorPickerHex(const S: TColorPickerState): string;
/// <summary>The color of grid cell (ACol, ARow) at saturation ASat; row 9 is the gray ramp.</summary>
function ColorPickerGridColor(ACol, ARow, ASat: Integer): TAlphaColor;
procedure ColorToHsl(AColor: TAlphaColor; out H, S, L: Integer);
function HslToColor(H, S, L: Integer): TAlphaColor;

/// <summary>Draws the control into the AW x AH cells at (ALeft, ATop).</summary>
procedure ColorPickerDraw(const AGrid: TTerminalGrid; ALeft, ATop: Integer;
  var S: TColorPickerState; AFocused, ACursorVisible: Boolean;
  ALabelFg, ALabelBg: TAlphaColor);
/// <summary>True when the key was used (Tab and the dialog keys are not).</summary>
function ColorPickerHandleKey(var S: TColorPickerState; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
/// <summary>ARelCol / ARelRow are relative to the control's top-left cell.</summary>
function ColorPickerClick(var S: TColorPickerState; ARelCol, ARelRow,
  AClickCount: Integer): Boolean;

implementation

uses
  System.SysUtils, System.Math, uColorCoding;

const
  cBarLeft = 2;
  cBarWidth = 32;
  cValueLeft = 35;
  cHexLabelW = 4;
  cHexInputW = 9;
  cWasLabelLeft = 14;
  cWasLeft = 18;
  cNowLabelLeft = 24;
  cNowLeft = 28;
  cSwatchW = 4;
  cSliderLines = 6;

function ColorPickerEmpty: TColorPickerState;
begin
  Result := Default(TColorPickerState);
  Result.HexEdit := InputLineEmpty;
  Result.GridSat := 100;
end;

function Clamp255(V: Integer): Integer;
begin
  Result := EnsureRange(V, 0, 255);
end;

function RgbColor(R, G, B: Integer): TAlphaColor;
begin
  Result := TAlphaColor($FF000000 or (Cardinal(Clamp255(R)) shl 16) or
    (Cardinal(Clamp255(G)) shl 8) or Cardinal(Clamp255(B)));
end;

procedure ColorToHsl(AColor: TAlphaColor; out H, S, L: Integer);
var
  R, G, B, Mx, Mn, D, Hf, Sf, Lf: Double;
begin
  R := TAlphaColorRec(AColor).R / 255;
  G := TAlphaColorRec(AColor).G / 255;
  B := TAlphaColorRec(AColor).B / 255;
  Mx := Max(R, Max(G, B));
  Mn := Min(R, Min(G, B));
  D := Mx - Mn;
  Lf := (Mx + Mn) / 2;
  if D = 0 then
  begin
    Hf := 0;
    Sf := 0;
  end
  else
  begin
    Sf := D / (1 - Abs(2 * Lf - 1));
    if Mx = R then
      Hf := 60 * ((G - B) / D - 6 * Floor((G - B) / D / 6))
    else if Mx = G then
      Hf := 60 * ((B - R) / D + 2)
    else
      Hf := 60 * ((R - G) / D + 4);
  end;
  H := Round(Hf) mod 360;
  S := EnsureRange(Round(Sf * 100), 0, 100);
  L := EnsureRange(Round(Lf * 100), 0, 100);
end;

function HslToColor(H, S, L: Integer): TAlphaColor;
var
  C, X, M, R, G, B, Sf, Lf: Double;
  Hh: Integer;
begin
  Hh := ((H mod 360) + 360) mod 360;
  Sf := EnsureRange(S, 0, 100) / 100;
  Lf := EnsureRange(L, 0, 100) / 100;
  C := (1 - Abs(2 * Lf - 1)) * Sf;
  X := C * (1 - Abs(Frac(Hh / 120) * 2 - 1));
  M := Lf - C / 2;
  case Hh div 60 of
    0: begin R := C; G := X; B := 0; end;
    1: begin R := X; G := C; B := 0; end;
    2: begin R := 0; G := C; B := X; end;
    3: begin R := 0; G := X; B := C; end;
    4: begin R := X; G := 0; B := C; end;
  else
    begin R := C; G := 0; B := X; end;
  end;
  Result := RgbColor(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

function ColorPickerGridColor(ACol, ARow, ASat: Integer): TAlphaColor;
begin
  if ARow >= cPickerGrayLine then
    Result := HslToColor(0, 0, Round(ACol * 100 / (cPickerHues - 1)))
  else
    Result := HslToColor(ACol * (360 div cPickerHues), ASat, 90 - ARow * 10);
end;

function ColorPickerHex(const S: TColorPickerState): string;
begin
  Result := ColorToHex(S.Color);
end;

// Puts the grid cursor on the cell nearest to the current color.
procedure PlaceGridCursor(var S: TColorPickerState);
begin
  S.GridCol := Round(S.H / (360 / cPickerHues)) mod cPickerHues;
end;

procedure SyncHexText(var S: TColorPickerState);
begin
  InputLineSetText(S.HexEdit, ColorToHex(S.Color));
end;

procedure SetFromRgb(var S: TColorPickerState; AColor: TAlphaColor; ASyncHex: Boolean);
begin
  S.Color := TAlphaColor($FF000000 or (AColor and $FFFFFF));
  ColorToHsl(S.Color, S.H, S.S, S.L);
  if S.S >= 15 then
    S.GridSat := S.S;
  PlaceGridCursor(S);
  if ASyncHex then
    SyncHexText(S);
end;

procedure ColorPickerSetColor(var S: TColorPickerState; AColor: TAlphaColor);
begin
  SetFromRgb(S, AColor, True);
end;

procedure ColorPickerInit(var S: TColorPickerState; AColor, AOrig: TAlphaColor);
begin
  S := ColorPickerEmpty;
  S.Orig := TAlphaColor($FF000000 or (AOrig and $FFFFFF));
  SetFromRgb(S, AColor, True);
  InputLineSelectAll(S.HexEdit);
  if S.L > 85 then
    S.Line := 1
  else if S.L < 15 then
    S.Line := 7
  else
    S.Line := EnsureRange(Round((90 - S.L) / 10), 0, cPickerLightRows - 1);
  if S.S < 10 then
    S.Line := cPickerGrayLine;
end;

// Makes grid cell (ACol, ARow) the color; the cursor stays on that cell.
procedure PickGridCell(var S: TColorPickerState; ACol, ARow: Integer);
begin
  SetFromRgb(S, ColorPickerGridColor(ACol, ARow, S.GridSat), True);
  S.GridCol := ACol;
end;

procedure SetFromHsl(var S: TColorPickerState; AHue, ASat, ALight: Integer);
begin
  S.H := ((AHue mod 360) + 360) mod 360;
  S.S := EnsureRange(ASat, 0, 100);
  S.L := EnsureRange(ALight, 0, 100);
  if S.S >= 15 then
    S.GridSat := S.S;
  S.Color := HslToColor(S.H, S.S, S.L);
  PlaceGridCursor(S);
  SyncHexText(S);
end;

function Channel(const S: TColorPickerState; ALine: Integer): Integer;
begin
  case ALine of
    cPickerLineH: Result := S.H;
    cPickerLineS: Result := S.S;
    cPickerLineL: Result := S.L;
    cPickerLineR: Result := TAlphaColorRec(S.Color).R;
    cPickerLineG: Result := TAlphaColorRec(S.Color).G;
  else
    Result := TAlphaColorRec(S.Color).B;
  end;
end;

function ChannelMax(ALine: Integer): Integer;
begin
  case ALine of
    cPickerLineH: Result := 359;
    cPickerLineS, cPickerLineL: Result := 100;
  else
    Result := 255;
  end;
end;

procedure SetChannel(var S: TColorPickerState; ALine, AValue: Integer);
var
  V: Integer;
  C: TAlphaColorRec;
begin
  V := EnsureRange(AValue, 0, ChannelMax(ALine));
  case ALine of
    cPickerLineH: SetFromHsl(S, V, S.S, S.L);
    cPickerLineS: SetFromHsl(S, S.H, V, S.L);
    cPickerLineL: SetFromHsl(S, S.H, S.S, V);
  else
    begin
      C.Color := S.Color;
      case ALine of
        cPickerLineR: C.R := V;
        cPickerLineG: C.G := V;
      else
        C.B := V;
      end;
      SetFromRgb(S, C.Color, True);
    end;
  end;
end;

// The color shown in bar cell ACell (0..cBarWidth-1) of a slider line.
function BarColor(const S: TColorPickerState; ALine, ACell: Integer): TAlphaColor;
var
  V: Integer;
  C: TAlphaColorRec;
begin
  V := Round(ACell * ChannelMax(ALine) / (cBarWidth - 1));
  case ALine of
    cPickerLineH: Result := HslToColor(V, Max(S.S, 60), 50);
    cPickerLineS: Result := HslToColor(S.H, V, S.L);
    cPickerLineL: Result := HslToColor(S.H, S.S, V);
  else
    begin
      C.Color := S.Color;
      case ALine of
        cPickerLineR: C.R := V;
        cPickerLineG: C.G := V;
      else
        C.B := V;
      end;
      Result := C.Color;
    end;
  end;
end;

// Black or white, whichever reads on AColor.
function ContrastColor(AColor: TAlphaColor): TAlphaColor;
begin
  if (TAlphaColorRec(AColor).R * 299 + TAlphaColorRec(AColor).G * 587 +
      TAlphaColorRec(AColor).B * 114) > 140000 then
    Result := TAlphaColor($FF000000)
  else
    Result := TAlphaColor($FFFFFFFF);
end;

procedure ColorPickerDraw(const AGrid: TTerminalGrid; ALeft, ATop: Integer;
  var S: TColorPickerState; AFocused, ACursorVisible: Boolean;
  ALabelFg, ALabelBg: TAlphaColor);
const
  cLabels: array[0..cSliderLines - 1] of string = ('H', 'S', 'L', 'R', 'G', 'B');
var
  Row, Col, I, Line, V, Thumb: Integer;
  Cell, Mark: TAlphaColor;
  Colors: TInputLineColors;
  LabelFg, LabelBg: TAlphaColor;
  Text: string;
begin
  // Swatch grid (9 lightness rows) and the gray ramp.
  for Row := 0 to cPickerGrayLine do
    for Col := 0 to cPickerHues - 1 do
    begin
      Cell := ColorPickerGridColor(Col, Row, S.GridSat);
      Mark := ContrastColor(Cell);
      if AFocused and (Row = S.Line) and (Col = S.GridCol) then
        PutGridText(AGrid, ALeft + Col * 2, ATop + Row, '[]', Mark, Cell)
      else if (Row = S.Line) and (Col = S.GridCol) and not AFocused then
        PutGridText(AGrid, ALeft + Col * 2, ATop + Row, '::', Mark, Cell)
      else
        PutGridText(AGrid, ALeft + Col * 2, ATop + Row, '  ', Mark, Cell);
    end;

  // Sliders: the bar is the color along the channel; | marks the value.
  for I := 0 to cSliderLines - 1 do
  begin
    Line := cPickerLineH + I;
    Row := ATop + Line;
    if AFocused and (S.Line = Line) then
    begin
      LabelFg := ALabelBg;
      LabelBg := ALabelFg;
    end
    else
    begin
      LabelFg := ALabelFg;
      LabelBg := ALabelBg;
    end;
    FillGridRect(AGrid, ALeft, Row, ALeft + cPickerWidth - 1, Row, ' ', ALabelFg, ALabelBg);
    PutGridText(AGrid, ALeft, Row, cLabels[I], LabelFg, LabelBg);
    V := Channel(S, Line);
    Thumb := Round(V * (cBarWidth - 1) / ChannelMax(Line));
    for Col := 0 to cBarWidth - 1 do
    begin
      Cell := BarColor(S, Line, Col);
      if Col = Thumb then
        PutGridText(AGrid, ALeft + cBarLeft + Col, Row, '|', ContrastColor(Cell), Cell)
      else
        PutGridText(AGrid, ALeft + cBarLeft + Col, Row, ' ', ALabelFg, Cell);
    end;
    Text := IntToStr(V);
    PutGridText(AGrid, ALeft + cValueLeft, Row, StringOfChar(' ', 3 - Length(Text)) + Text,
      ALabelFg, ALabelBg);
  end;

  // Hex input with the original and the current color.
  Row := ATop + cPickerLineHex;
  FillGridRect(AGrid, ALeft, Row, ALeft + cPickerWidth - 1, Row, ' ', ALabelFg, ALabelBg);
  if AFocused and (S.Line = cPickerLineHex) then
    PutGridText(AGrid, ALeft, Row, 'Hex', ALabelBg, ALabelFg)
  else
    PutGridText(AGrid, ALeft, Row, 'Hex', ALabelFg, ALabelBg);
  Colors := InputLineDialogColors(AFocused and (S.Line = cPickerLineHex));
  InputLineDraw(AGrid, ALeft + cHexLabelW, Row, cHexInputW, S.HexEdit,
    AFocused and (S.Line = cPickerLineHex), Colors, ACursorVisible, False);
  PutGridText(AGrid, ALeft + cWasLabelLeft, Row, 'was', ALabelFg, ALabelBg);
  FillGridRect(AGrid, ALeft + cWasLeft, Row, ALeft + cWasLeft + cSwatchW - 1, Row, ' ',
    ALabelFg, S.Orig);
  PutGridText(AGrid, ALeft + cNowLabelLeft, Row, 'now', ALabelFg, ALabelBg);
  FillGridRect(AGrid, ALeft + cNowLeft, Row, ALeft + cNowLeft + cSwatchW - 1, Row, ' ',
    ALabelFg, S.Color);
end;

// A hex edit that parses becomes the current color (the text is left alone).
procedure ApplyHexEdit(var S: TColorPickerState);
var
  C: TAlphaColor;
begin
  if HexToColor(S.HexEdit.Text, C) then
    SetFromRgb(S, C, False);
end;

function ColorPickerHandleKey(var S: TColorPickerState; var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Step, Col: Integer;
  Res: TInputLineResult;
  Moved: Boolean;
begin
  Result := False;
  if AKey = vkTab then
    Exit;

  if (AKey = vkUp) or (AKey = vkDown) then
  begin
    Moved := False;
    if (AKey = vkUp) and (S.Line > 0) then
    begin
      Dec(S.Line);
      Moved := True;
    end
    else if (AKey = vkDown) and (S.Line < cPickerLineHex) then
    begin
      Inc(S.Line);
      Moved := True;
    end;
    // Stepping between grid rows picks the cell; entering the grid does not.
    if Moved and (S.Line <= cPickerGrayLine) and
       (((AKey = vkUp) and (S.Line < cPickerGrayLine)) or
        ((AKey = vkDown) and (S.Line >= 1))) then
      PickGridCell(S, S.GridCol, S.Line);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  if S.Line = cPickerLineHex then
  begin
    Res := InputLineHandleInput(S.HexEdit, AKey, AShift, AKeyChar);
    ApplyHexEdit(S);
    Exit(Res <> ilrPassThrough);
  end;

  if S.Line < cPickerLineH then
  begin
    if (AKey = vkLeft) or (AKey = vkRight) or (AKey = vkHome) or (AKey = vkEnd) then
    begin
      case AKey of
        vkLeft: Col := Max(S.GridCol - 1, 0);
        vkRight: Col := Min(S.GridCol + 1, cPickerHues - 1);
        vkHome: Col := 0;
      else
        Col := cPickerHues - 1;
      end;
      PickGridCell(S, Col, S.Line);
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    Exit;
  end;

  // Slider lines.
  if ssShift in AShift then
    Step := 10
  else
    Step := 1;
  case AKey of
    vkLeft: SetChannel(S, S.Line, Channel(S, S.Line) - Step);
    vkRight: SetChannel(S, S.Line, Channel(S, S.Line) + Step);
    vkPrior: SetChannel(S, S.Line, Channel(S, S.Line) + 10);
    vkNext: SetChannel(S, S.Line, Channel(S, S.Line) - 10);
    vkHome: SetChannel(S, S.Line, 0);
    vkEnd: SetChannel(S, S.Line, ChannelMax(S.Line));
  else
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function ColorPickerClick(var S: TColorPickerState; ARelCol, ARelRow,
  AClickCount: Integer): Boolean;
var
  Col: Integer;
begin
  Result := False;
  if (ARelRow < 0) or (ARelRow >= cPickerHeight) or (ARelCol < 0) then
    Exit;
  S.Line := ARelRow;
  if ARelRow <= cPickerGrayLine then
  begin
    Col := ARelCol div 2;
    if Col >= cPickerHues then
      Exit(True);
    PickGridCell(S, Col, ARelRow);
    Exit(True);
  end;
  if ARelRow = cPickerLineHex then
  begin
    if (ARelCol >= cWasLeft) and (ARelCol < cWasLeft + cSwatchW) then
      SetFromRgb(S, S.Orig, True)
    else if (ARelCol >= cHexLabelW) and (ARelCol < cHexLabelW + cHexInputW) then
      InputLineMouseClick(S.HexEdit, ARelCol - cHexLabelW, AClickCount);
    Exit(True);
  end;
  if (ARelCol >= cBarLeft) and (ARelCol < cBarLeft + cBarWidth) then
    SetChannel(S, ARelRow, Round((ARelCol - cBarLeft) * ChannelMax(ARelRow) / (cBarWidth - 1)));
  Result := True;
end;

end.
