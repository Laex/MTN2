unit uDiskMapRaster;

{$POINTERMATH ON}

{ A BGRA pixel buffer with the few drawing operations the treemap needs:
  filled and framed rectangles and a line of text. On Windows the text comes
  from GDI (any language); elsewhere, and when GDI is not available, from a small
  built-in 5x7 font (Latin capitals, digits and a few marks - other characters
  are left out). Colors are $RRGGBB. }

interface

type
  TRaster = class
  strict private
    FWidth, FHeight: Integer;
    FPixels: TArray<Byte>;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Clear(AColor: Cardinal);
    procedure FillRect(AX1, AY1, AX2, AY2: Integer; AColor: Cardinal);
    procedure FrameRect(AX1, AY1, AX2, AY2: Integer; AColor: Cardinal; AThick: Integer = 1);
    procedure BlendPixel(AX, AY: Integer; AColor: Cardinal; ACoverage: Integer);
    function PixelAt(AX, AY: Integer): Cardinal;
    /// <summary>Draws the text with its top-left corner at (AX, AY), cut at
    /// AClipRight (exclusive). Returns the width drawn.</summary>
    function DrawText(AX, AY: Integer; const AText: string; AColor: Cardinal;
      AClipRight: Integer): Integer;
    function TextWidth(const AText: string): Integer;
    /// <summary>The text shortened with "..." until it fits AWidth pixels;
    /// '' when not even that fits.</summary>
    function FitText(const AText: string; AWidth: Integer): string;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Pixels: TArray<Byte> read FPixels;
  end;

const
  cTextHeight = 14;

/// <summary>Switches the Windows text path off, so the built-in font is used
/// (for tests and for hosts without GDI).</summary>
procedure SetBitmapFontOnly(AValue: Boolean);

implementation

uses
  System.SysUtils, System.Math
{$IFDEF MSWINDOWS}
  , Winapi.Windows
{$ENDIF}
  ;

var
  GBitmapOnly: Boolean;

procedure SetBitmapFontOnly(AValue: Boolean);
begin
  GBitmapOnly := AValue;
end;

const
  // Columns of a 5x7 glyph, bit 0 = top row.
  cGlyphChars = ' !%()+,-./0123456789:?ABCDEFGHIJKLMNOPQRSTUVWXYZ_';
  cGlyphs: array[0..48, 0..4] of Byte = (
    ($00, $00, $00, $00, $00), // space
    ($00, $00, $5F, $00, $00), // !
    ($23, $13, $08, $64, $62), // %
    ($00, $1C, $22, $41, $00), // (
    ($00, $41, $22, $1C, $00), // )
    ($08, $08, $3E, $08, $08), // +
    ($00, $50, $30, $00, $00), // ,
    ($08, $08, $08, $08, $08), // -
    ($00, $60, $60, $00, $00), // .
    ($20, $10, $08, $04, $02), // /
    ($3E, $51, $49, $45, $3E), // 0
    ($00, $42, $7F, $40, $00), // 1
    ($42, $61, $51, $49, $46), // 2
    ($21, $41, $45, $4B, $31), // 3
    ($18, $14, $12, $7F, $10), // 4
    ($27, $45, $45, $45, $39), // 5
    ($3C, $4A, $49, $49, $30), // 6
    ($01, $71, $09, $05, $03), // 7
    ($36, $49, $49, $49, $36), // 8
    ($06, $49, $49, $29, $1E), // 9
    ($00, $36, $36, $00, $00), // :
    ($02, $01, $51, $09, $06), // ?
    ($7E, $11, $11, $11, $7E), // A
    ($7F, $49, $49, $49, $36), // B
    ($3E, $41, $41, $41, $22), // C
    ($7F, $41, $41, $22, $1C), // D
    ($7F, $49, $49, $49, $41), // E
    ($7F, $09, $09, $09, $01), // F
    ($3E, $41, $49, $49, $7A), // G
    ($7F, $08, $08, $08, $7F), // H
    ($00, $41, $7F, $41, $00), // I
    ($20, $40, $41, $3F, $01), // J
    ($7F, $08, $14, $22, $41), // K
    ($7F, $40, $40, $40, $40), // L
    ($7F, $02, $0C, $02, $7F), // M
    ($7F, $04, $08, $10, $7F), // N
    ($3E, $41, $41, $41, $3E), // O
    ($7F, $09, $09, $09, $06), // P
    ($3E, $41, $51, $21, $5E), // Q
    ($7F, $09, $19, $29, $46), // R
    ($46, $49, $49, $49, $31), // S
    ($01, $01, $7F, $01, $01), // T
    ($3F, $40, $40, $40, $3F), // U
    ($1F, $20, $40, $20, $1F), // V
    ($3F, $40, $38, $40, $3F), // W
    ($63, $14, $08, $14, $63), // X
    ($07, $08, $70, $08, $07), // Y
    ($61, $51, $49, $45, $43), // Z
    ($40, $40, $40, $40, $40)  // _
  );
  cGlyphAdvance = 6;

{ TRaster }

constructor TRaster.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := Max(AWidth, 0);
  FHeight := Max(AHeight, 0);
  SetLength(FPixels, FWidth * FHeight * 4);
end;

procedure TRaster.Clear(AColor: Cardinal);
begin
  FillRect(0, 0, FWidth, FHeight, AColor);
end;

procedure TRaster.FillRect(AX1, AY1, AX2, AY2: Integer; AColor: Cardinal);
var
  X, Y, P: Integer;
  R, G, B: Byte;
begin
  AX1 := Max(AX1, 0);
  AY1 := Max(AY1, 0);
  AX2 := Min(AX2, FWidth);
  AY2 := Min(AY2, FHeight);
  R := (AColor shr 16) and $FF;
  G := (AColor shr 8) and $FF;
  B := AColor and $FF;
  for Y := AY1 to AY2 - 1 do
  begin
    P := (Y * FWidth + AX1) * 4;
    for X := AX1 to AX2 - 1 do
    begin
      FPixels[P] := B;
      FPixels[P + 1] := G;
      FPixels[P + 2] := R;
      FPixels[P + 3] := 255;
      Inc(P, 4);
    end;
  end;
end;

procedure TRaster.FrameRect(AX1, AY1, AX2, AY2: Integer; AColor: Cardinal; AThick: Integer);
begin
  if (AX2 <= AX1) or (AY2 <= AY1) then
    Exit;
  AThick := Min(AThick, Min(AX2 - AX1, AY2 - AY1));
  FillRect(AX1, AY1, AX2, AY1 + AThick, AColor);
  FillRect(AX1, AY2 - AThick, AX2, AY2, AColor);
  FillRect(AX1, AY1 + AThick, AX1 + AThick, AY2 - AThick, AColor);
  FillRect(AX2 - AThick, AY1 + AThick, AX2, AY2 - AThick, AColor);
end;

procedure TRaster.BlendPixel(AX, AY: Integer; AColor: Cardinal; ACoverage: Integer);
var
  P, Inv: Integer;
begin
  if (AX < 0) or (AY < 0) or (AX >= FWidth) or (AY >= FHeight) or (ACoverage <= 0) then
    Exit;
  if ACoverage > 255 then
    ACoverage := 255;
  Inv := 255 - ACoverage;
  P := (AY * FWidth + AX) * 4;
  FPixels[P] := (FPixels[P] * Inv + Integer((AColor and $FF)) * ACoverage) div 255;
  FPixels[P + 1] := (FPixels[P + 1] * Inv + (Integer((AColor shr 8) and $FF)) * ACoverage) div 255;
  FPixels[P + 2] := (FPixels[P + 2] * Inv + (Integer((AColor shr 16) and $FF)) * ACoverage) div 255;
  FPixels[P + 3] := 255;
end;

function TRaster.PixelAt(AX, AY: Integer): Cardinal;
var
  P: Integer;
begin
  if (AX < 0) or (AY < 0) or (AX >= FWidth) or (AY >= FHeight) then
    Exit(0);
  P := (AY * FWidth + AX) * 4;
  Result := (Cardinal(FPixels[P + 2]) shl 16) or (Cardinal(FPixels[P + 1]) shl 8) or FPixels[P];
end;

{ Text through the built-in font. }

function GlyphIndex(AChar: Char): Integer;
var
  C: Char;
begin
  C := UpCase(AChar);
  Result := Pos(C, cGlyphChars) - 1;
end;

function BitmapTextWidth(const AText: string): Integer;
var
  C: Char;
  N: Integer;
begin
  N := 0;
  for C in AText do
    if (C >= ' ') and (GlyphIndex(C) >= 0) then
      Inc(N);
  Result := N * cGlyphAdvance;
end;

function DrawBitmapText(ARaster: TRaster; AX, AY: Integer; const AText: string;
  AColor: Cardinal; AClipRight: Integer): Integer;
var
  C: Char;
  G, Col, Row, X: Integer;
begin
  X := AX;
  for C in AText do
  begin
    G := GlyphIndex(C);
    if G < 0 then
      Continue;
    if X + 5 > AClipRight then
      Break;
    for Col := 0 to 4 do
      for Row := 0 to 6 do
        if (cGlyphs[G, Col] shr Row) and 1 <> 0 then
          ARaster.BlendPixel(X + Col, AY + 3 + Row, AColor, 255);
    Inc(X, cGlyphAdvance);
  end;
  Result := X - AX;
end;

{$IFDEF MSWINDOWS}
type
  TGdiText = class
  strict private
    FDC: HDC;
    FFont: HFONT;
    FBitmap: HBITMAP;
    FOldBitmap: HGDIOBJ;
    FOldFont: HGDIOBJ;
    FBits: Pointer;
    FBitsWidth: Integer;
    function Ensure(AWidth: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Width(const AText: string): Integer;
    function Draw(ARaster: TRaster; AX, AY: Integer; const AText: string; AColor: Cardinal;
      AClipRight: Integer): Integer;
  end;

var
  GGdi: TGdiText;
  GGdiFailed: Boolean;

constructor TGdiText.Create;
var
  LF: TLogFont;
begin
  inherited Create;
  FDC := CreateCompatibleDC(0);
  FillChar(LF, SizeOf(LF), 0);
  LF.lfHeight := -12;
  LF.lfWeight := FW_NORMAL;
  LF.lfCharSet := DEFAULT_CHARSET;
  LF.lfQuality := ANTIALIASED_QUALITY;
  StrPCopy(LF.lfFaceName, 'Segoe UI');
  FFont := CreateFontIndirect(LF);
  if (FDC <> 0) and (FFont <> 0) then
    FOldFont := SelectObject(FDC, FFont);
end;

destructor TGdiText.Destroy;
begin
  if FDC <> 0 then
  begin
    if FOldFont <> 0 then
      SelectObject(FDC, FOldFont);
    if FOldBitmap <> 0 then
      SelectObject(FDC, FOldBitmap);
    DeleteDC(FDC);
  end;
  if FFont <> 0 then
    DeleteObject(FFont);
  if FBitmap <> 0 then
    DeleteObject(FBitmap);
  inherited;
end;

function TGdiText.Ensure(AWidth: Integer): Boolean;
var
  BI: TBitmapInfo;
begin
  Result := False;
  if (FDC = 0) or (FFont = 0) then
    Exit;
  if (FBitmap <> 0) and (FBitsWidth >= AWidth) then
    Exit(True);
  if FBitmap <> 0 then
  begin
    SelectObject(FDC, FOldBitmap);
    DeleteObject(FBitmap);
    FBitmap := 0;
  end;
  FBitsWidth := Max(AWidth, 256);
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := FBitsWidth;
  BI.bmiHeader.biHeight := -cTextHeight;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  FBits := nil;
  FBitmap := CreateDIBSection(FDC, BI, DIB_RGB_COLORS, FBits, 0, 0);
  if (FBitmap = 0) or (FBits = nil) then
    Exit;
  FOldBitmap := SelectObject(FDC, FBitmap);
  Result := True;
end;

function TGdiText.Width(const AText: string): Integer;
var
  Size: TSize;
begin
  Result := 0;
  if (AText = '') or (FDC = 0) or (FFont = 0) then
    Exit;
  if GetTextExtentPoint32W(FDC, PWideChar(AText), Length(AText), Size) then
    Result := Size.cx;
end;

function TGdiText.Draw(ARaster: TRaster; AX, AY: Integer; const AText: string;
  AColor: Cardinal; AClipRight: Integer): Integer;
var
  W, X, Y, Cov: Integer;
  Row: PByte;
begin
  Result := 0;
  W := Width(AText);
  if (W <= 0) or not Ensure(W + 2) then
    Exit;
  FillChar(PByte(FBits)^, FBitsWidth * cTextHeight * 4, 0);
  SetBkMode(FDC, TRANSPARENT);
  SetTextColor(FDC, $FFFFFF);
  TextOutW(FDC, 0, 0, PWideChar(AText), Length(AText));
  GdiFlush;
  for Y := 0 to cTextHeight - 1 do
  begin
    Row := PByte(FBits) + Y * FBitsWidth * 4;
    for X := 0 to Min(W, FBitsWidth) - 1 do
    begin
      if AX + X >= AClipRight then
        Break;
      // Gray anti-aliasing: any channel is the coverage.
      Cov := Row[X * 4 + 1];
      if Cov > 0 then
        ARaster.BlendPixel(AX + X, AY + Y, AColor, Cov);
    end;
  end;
  Result := Min(W, Max(AClipRight - AX, 0));
end;

function GdiText: TGdiText;
begin
  if GGdiFailed or GBitmapOnly then
    Exit(nil);
  if GGdi = nil then
  begin
    GGdi := TGdiText.Create;
    if GGdi.Width('A') <= 0 then
    begin
      FreeAndNil(GGdi);
      GGdiFailed := True;
    end;
  end;
  Result := GGdi;
end;
{$ENDIF}

function TRaster.TextWidth(const AText: string): Integer;
begin
{$IFDEF MSWINDOWS}
  if GdiText <> nil then
    Exit(GdiText.Width(AText));
{$ENDIF}
  Result := BitmapTextWidth(AText);
end;

function TRaster.DrawText(AX, AY: Integer; const AText: string; AColor: Cardinal;
  AClipRight: Integer): Integer;
begin
  if (AText = '') or (AY + cTextHeight <= 0) or (AY >= FHeight) then
    Exit(0);
  AClipRight := Min(AClipRight, FWidth);
{$IFDEF MSWINDOWS}
  if GdiText <> nil then
    Exit(GdiText.Draw(Self, AX, AY, AText, AColor, AClipRight));
{$ENDIF}
  Result := DrawBitmapText(Self, AX, AY, AText, AColor, AClipRight);
end;

function TRaster.FitText(const AText: string; AWidth: Integer): string;
var
  N: Integer;
begin
  if (AText = '') or (AWidth <= 0) then
    Exit('');
  if TextWidth(AText) <= AWidth then
    Exit(AText);
  N := Length(AText);
  while N > 1 do
  begin
    Dec(N);
    Result := Copy(AText, 1, N) + '...';
    if TextWidth(Result) <= AWidth then
      Exit;
  end;
  Result := '';
end;

initialization

finalization
{$IFDEF MSWINDOWS}
  GGdi.Free;
{$ENDIF}

end.
