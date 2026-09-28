unit TestTerminalRenderer;

{ uTerminalRenderer glyph cache: glyph bitmaps in device pixels (no stretch at
  125% / 150% scaling) and cell metrics that keep descenders inside the cell
  (Ubuntu Mono lost a pixel of g/j/p/q/y/[/]/_). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTerminalRenderer = class
  public
    [Test] procedure TestFitKeepsRoundedLineHeight;
    [Test] procedure TestFitGrowsForInk;
    [Test] procedure TestFitSnapsTopToDevicePixel;
    [Test] procedure TestGlyphBitmapIsDeviceSized;
    [Test] procedure TestDescendersInsideCell;
    [Test] procedure TestLineSpacing;
  end;

implementation

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Graphics,
  uTerminalRenderer, uDisplaySettings;

function SameF(A, B: Single): Boolean;
begin
  Result := Abs(A - B) < 0.001;
end;

function InkRows(ABmp: TBitmap): Integer;
var
  Data: TBitmapData;
  X, Y, T, B: Integer;
begin
  T := MaxInt;
  B := -1;
  if ABmp.Map(TMapAccess.Read, Data) then
  try
    for Y := 0 to ABmp.Height - 1 do
      for X := 0 to ABmp.Width - 1 do
        if TAlphaColorRec(Data.GetPixel(X, Y)).A > 40 then
        begin
          T := Min(T, Y);
          B := Max(B, Y);
        end;
  finally
    ABmp.Unmap(Data);
  end;
  if B < 0 then
    Result := 0
  else
    Result := B - T + 1;
end;

// The same glyph with nothing to clip it: its full ink height.
function FreeInkRows(const AFont: string; ASize, AScale: Single; ACh: Char): Integer;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create(Round(80 * AScale), Round(160 * AScale));
  try
    Bmp.BitmapScale := AScale;
    if Bmp.Canvas.BeginScene then
    try
      Bmp.Canvas.Clear($00000000);
      Bmp.Canvas.Font.Family := AFont;
      Bmp.Canvas.Font.Size := ASize;
      Bmp.Canvas.Fill.Kind := TBrushKind.Solid;
      Bmp.Canvas.Fill.Color := TAlphaColorRec.White;
      Bmp.Canvas.FillText(RectF(0, 40, 80, 160), string(ACh), False, 1, [],
        TTextAlign.Center, TTextAlign.Leading);
    finally
      Bmp.Canvas.EndScene;
    end;
    Result := InkRows(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TTestTerminalRenderer.TestFitKeepsRoundedLineHeight;
var
  H, Top: Single;
begin
  // Consolas 14: line 16.39, ink well inside it -> 16 px as before, centred.
  H := FitGlyphLine(16.39, 2, 15, 1.0, Top);
  Assert.IsTrue(SameF(H, 16), Format('cell height %g, want 16', [H]));
  Assert.IsTrue((Top + 2 >= 0) and (Top + 15 <= H), 'ink inside the cell');
  // Same at 125%: 16.39 * 1.25 = 20.49 -> 20 device px.
  H := FitGlyphLine(16.39, 2, 15, 1.25, Top);
  Assert.IsTrue(SameF(H * 1.25, 20), Format('device height %g, want 20', [H * 1.25]));
  // Float noise on an exact metric must not add a row.
  H := FitGlyphLine(16.0000019, 1, 15, 1.25, Top);
  Assert.IsTrue(SameF(H * 1.25, 20), Format('device height %g, want 20', [H * 1.25]));
end;

procedure TTestTerminalRenderer.TestFitGrowsForInk;
var
  H, Top: Single;
begin
  // Ubuntu Mono 12: line 13.45 rounds to 13, ink spans 1..14 (13.9 px).
  H := FitGlyphLine(13.45, 1, 14.9, 1.0, Top);
  Assert.IsTrue(SameF(H, 14), Format('cell height %g, want 14', [H]));
  Assert.IsTrue(Top + 1 >= -0.001, Format('top ink cut: top %g', [Top]));
  Assert.IsTrue(Top + 14.9 <= H + 0.001, Format('bottom ink cut: top %g', [Top]));
  // Ink above the line top (accent) pulls the line down.
  H := FitGlyphLine(16, -1.5, 15, 1.0, Top);
  Assert.IsTrue(SameF(H, 17), Format('cell height %g, want 17', [H]));
  Assert.IsTrue(Top >= 1.5 - 0.001, Format('accent cut: top %g', [Top]));
end;

procedure TTestTerminalRenderer.TestFitSnapsTopToDevicePixel;
var
  H, Top, Dev: Single;
  Scale: Single;
begin
  for Scale in [1.0, 1.25, 1.5, 1.75, 2.0] do
  begin
    H := FitGlyphLine(16.39, 0.7, 15.3, Scale, Top);
    Dev := Top * Scale;
    Assert.IsTrue(Abs(Dev - Round(Dev)) < 0.01,
      Format('scale %g: top %g is not on a device pixel', [Scale, Top]));
    Dev := H * Scale;
    Assert.IsTrue(Abs(Dev - Round(Dev)) < 0.01,
      Format('scale %g: height %g is not whole device pixels', [Scale, H]));
    Assert.IsTrue((Top + 0.7 >= -0.001) and (Top + 15.3 <= H + 0.001),
      Format('scale %g: ink outside the cell', [Scale]));
  end;
end;

procedure TTestTerminalRenderer.TestGlyphBitmapIsDeviceSized;
var
  R: TTerminalRenderer;
  Cache: TGlyphCache;
  Measure, Glyph: TBitmap;
  Scale: Single;
begin
  for Scale in [1.0, 1.25, 1.5, 2.0] do
  begin
    Measure := TBitmap.Create(16, 16);
    R := TTerminalRenderer.Create;
    Cache := TGlyphCache.Create;
    try
      R.SetSceneScale(Scale, 500, 150, Measure.Canvas);
      R.SetFont('Consolas', 14, 500, 150, Measure.Canvas);
      Glyph := Cache.GetGlyph('g', TAlphaColorRec.White, [], R.CellWidth, R.CellHeight,
        Scale, R.GlyphTop, R.FontName, 14);
      // Exactly the cell's size on the frame: blitted 1:1, never stretched.
      Assert.IsTrue(Round(R.CellWidth * Scale) = Glyph.Width,
        Format('scale %g: glyph width', [Scale]));
      Assert.IsTrue(Round(R.CellHeight * Scale) = Glyph.Height,
        Format('scale %g: glyph height', [Scale]));
      Assert.IsTrue(SameF(Glyph.BitmapScale, Scale), Format('scale %g: bitmap scale', [Scale]));
      Assert.IsTrue(InkRows(Glyph) > 0, Format('scale %g: glyph drawn', [Scale]));
    finally
      Cache.Free;
      R.Free;
      Measure.Free;
    end;
  end;
end;

procedure TTestTerminalRenderer.TestDescendersInsideCell;
const
  cFont = 'Ubuntu Mono';
  cDescenders = 'gjpqy[]|_';
var
  R: TTerminalRenderer;
  Cache: TGlyphCache;
  Measure, Glyph: TBitmap;
  Size: Single;
  Ch: Char;
  Clipped: string;
begin
  if not FontFamilyInstalled(cFont) then
  begin
    Assert.Pass(cFont + ' not installed');
    Exit;
  end;
  Clipped := '';
  // The sizes that used to lose the bottom pixel row.
  for Size in [12.0, 18.0, 20.0] do
  begin
    Measure := TBitmap.Create(16, 16);
    R := TTerminalRenderer.Create;
    Cache := TGlyphCache.Create;
    try
      R.SetFont(cFont, Size, 500, 150, Measure.Canvas);
      for Ch in cDescenders do
      begin
        Glyph := Cache.GetGlyph(Ch, TAlphaColorRec.White, [], R.CellWidth, R.CellHeight,
          1.0, R.GlyphTop, R.FontName, Size);
        if InkRows(Glyph) < FreeInkRows(cFont, Size, 1.0, Ch) then
          Clipped := Clipped + Format(' %s@%g', [Ch, Size]);
      end;
    finally
      Cache.Free;
      R.Free;
      Measure.Free;
    end;
  end;
  Assert.IsTrue(Clipped = '', 'clipped:' + Clipped);
end;

procedure TTestTerminalRenderer.TestLineSpacing;
const
  cFont = 'Cascadia Mono';
var
  R: TTerminalRenderer;
  Measure: TBitmap;
  H, Top, Plain, Spaced, TopPlain, TopSpaced: Single;
begin
  // Extra height is added and split: the line stays centred.
  H := FitGlyphLine(17.04, 1, 17, 1.0, Top, 2.2);
  Assert.IsTrue(SameF(H, 19), Format('17.04 + 2.2 -> 19 rows of pixels, got %g', [H]));
  Assert.IsTrue(Top >= 0.99, Format('gap above the text too, top %g', [Top]));

  if not FontFamilyInstalled(cFont) then
  begin
    Assert.Pass(cFont + ' not installed');
    Exit;
  end;
  Measure := TBitmap.Create(16, 16);
  R := TTerminalRenderer.Create;
  try
    // 11 pt as Windows Terminal (and Far in it) uses by default.
    R.SetFont(cFont, 11 * 96 / 72, 500, 150, Measure.Canvas);
    Plain := R.CellHeight;
    TopPlain := R.GlyphTop;
    R.SetLineSpacing(True, 500, 150, Measure.Canvas);
    Spaced := R.CellHeight;
    TopSpaced := R.GlyphTop;
    Assert.IsTrue(SameF(Plain, 17), Format('off: %g, want 17', [Plain]));
    Assert.IsTrue(SameF(Spaced, 19), Format('on: %g, want 19 (Windows Terminal)', [Spaced]));
    Assert.IsTrue(TopSpaced > TopPlain, 'text moved down into the middle');
    R.SetLineSpacing(False, 500, 150, Measure.Canvas);
    Assert.IsTrue(SameF(R.CellHeight, Plain), 'off again: back to the plain height');
  finally
    R.Free;
    Measure.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTerminalRenderer);

end.
