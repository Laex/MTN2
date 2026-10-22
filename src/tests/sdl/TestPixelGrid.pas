unit TestPixelGrid;

{ The pixel renderer draws a character grid into a bitmap of 32-bit pixels:
  background, glyphs, attributes, wide characters, and only the cells that
  changed since the previous frame. The glyph source is a fixed pattern
  (uFakeGlyphs) with 8 x 16 cells. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPixelGrid = class
  public
    [Test] procedure SizeFollowsGridAndCell;
    [Test] procedure BackgroundFillsTheCell;
    [Test] procedure GlyphIsDrawnInTheForegroundColor;
    [Test] procedure HalfCoverageMixesWithTheBackground;
    [Test] procedure ReverseSwapsTheColors;
    [Test] procedure UnderlineAndStrikeAreLines;
    [Test] procedure GlyphIsClippedToItsCell;
    [Test] procedure WideCharacterCoversTwoCells;
    [Test] procedure BoxCharacterIsDrawnWithoutAGlyph;
    [Test] procedure OnlyChangedCellsAreRepainted;
    [Test] procedure UnchangedFrameChangesNothing;
    [Test] procedure BlinkingTextHidesWithThePhase;
    [Test] procedure BoldAsksForTheBoldGlyph;
    [Test] procedure InsertCaretIsABarAtTheLeftEdge;
    [Test] procedure CellAtMapsPixelsToCells;
    [Test] procedure ResizedGridIsPaintedCompletely;
    [Test] procedure IconCoversItsCellAndTheFillerAfterIt;
    [Test] procedure FillerIsClearedWhenTheIconGoesAway;
    [Test] procedure CellWithoutAnIconPictureKeepsItsGlyph;
  end;

implementation

uses
  System.SysUtils, System.Types, System.UITypes, uTerminalTypes, uGlyphSource,
  uPixelGrid, uFakeGlyphs;

const
  cWhite = TAlphaColor($FFFFFFFF);
  cBlue = TAlphaColor($FF0000AA);
  cRed = TAlphaColor($FFAA0000);
  cBlack = TAlphaColor($FF000000);

function NewGrid(ACols, ARows: Integer): TTerminalGrid;
begin
  AllocTerminalGrid(Result, ACols, ARows);
  ClearTerminalGrid(Result, cWhite, cBlue);
end;

procedure TTestPixelGrid.SizeFollowsGridAndCell;
var
  R: TPixelGridRenderer;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.Render(NewGrid(5, 3));
    Assert.AreEqual(40, R.Width);
    Assert.AreEqual(48, R.Height);
    Assert.AreEqual(160, R.Stride);
    Assert.AreEqual(5, R.Cols);
    Assert.AreEqual(3, R.Rows);
    Assert.AreEqual(80, Integer(R.PixelSizeOf(10, 5).cx));
    Assert.AreEqual(2, Integer(R.GridSizeOf(20, 33).cy));
    Assert.AreEqual(1, Integer(R.GridSizeOf(3, 3).cx), 'a window smaller than a cell still has one');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.BackgroundFillsTheCell;
var
  R: TPixelGridRenderer;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.Render(NewGrid(2, 1));
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(0, 0));
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(15, 15));
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.GlyphIsDrawnInTheForegroundColor;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(2, 1);
    PutTerminalText(Grid, 1, 0, 'A', cRed, cWhite);
    R.Render(Grid);
    // The box sits at columns 1..6 of the cell and rows 2..11.
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(8 + 1, 2));
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(8 + 6, 11));
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(8 + 0, 2), 'left of the box');
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(8 + 1, 12), 'below the box');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(1, 2), 'the other cell is untouched');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.HalfCoverageMixesWithTheBackground;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(1, 1);
    PutTerminalText(Grid, 0, 0, 'B', cWhite, cBlack);
    R.Render(Grid);
    // 128 of 255 white over black.
    Assert.AreEqual(Cardinal($FF808080), R.PixelAt(3, 5));
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.ReverseSwapsTheColors;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(1, 1);
    PutTerminalText(Grid, 0, 0, 'A', cWhite, cBlue, [ccaReverse]);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(0, 0), 'the foreground is the background');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(3, 5), 'the background is the glyph');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.UnderlineAndStrikeAreLines;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(2, 1);
    PutTerminalText(Grid, 0, 0, ' ', cRed, cBlue, [ccaUnderline]);
    PutTerminalText(Grid, 1, 0, ' ', cRed, cBlue, [ccaStrike]);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(0, 13), 'one row below the baseline');
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(7, 13));
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(0, 12));
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(8, 8), 'two thirds up the baseline');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(8, 13));
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.GlyphIsClippedToItsCell;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(2, 1);
    PutTerminalText(Grid, 0, 0, 'I', cRed, cWhite);
    PutTerminalText(Grid, 1, 0, ' ', cWhite, cBlue);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(7, 5), 'last column of the cell');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(8, 5), 'the neighbor keeps its background');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.WideCharacterCoversTwoCells;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(3, 1);
    Grid[0][0] := TCharCell.Make('I', cRed, cWhite, [ccaWide]);
    Grid[0][1] := TCharCell.Make(' ', cBlack, cWhite, [ccaWideTail]);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(10, 5), 'the glyph runs into the second cell');
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(14, 5), 'and the second cell has the same background');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(16, 5), 'the third cell is separate');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.BoxCharacterIsDrawnWithoutAGlyph;
var
  R: TPixelGridRenderer;
  F: TFakeGlyphs;
  Grid: TTerminalGrid;
begin
  F := TFakeGlyphs.Create;
  R := TPixelGridRenderer.Create(F);
  try
    Grid := NewGrid(1, 1);
    PutTerminalText(Grid, 0, 0, #$2502, cWhite, cBlue);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(4, 0), 'the vertical line reaches the top edge');
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(4, 15), 'and the bottom edge');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(3, 7));
    Assert.AreEqual(0, F.Requests, 'the font is not asked');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.OnlyChangedCellsAreRepainted;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
  Dirty: TRect;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(4, 2);
    R.Render(Grid);
    R.ClearDirty;
    Assert.IsTrue(R.DirtyRect.IsEmpty);
    PutTerminalText(Grid, 2, 1, 'A', cWhite, cBlue);
    Assert.IsTrue(R.Render(Grid), 'a change is reported');
    Dirty := R.DirtyRect;
    Assert.AreEqual(16, Dirty.Left);
    Assert.AreEqual(16, Dirty.Top);
    Assert.AreEqual(24, Dirty.Right);
    Assert.AreEqual(32, Dirty.Bottom);
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.UnchangedFrameChangesNothing;
var
  R: TPixelGridRenderer;
  F: TFakeGlyphs;
  Grid: TTerminalGrid;
  Requests: Integer;
begin
  F := TFakeGlyphs.Create;
  R := TPixelGridRenderer.Create(F);
  try
    Grid := NewGrid(4, 2);
    PutTerminalText(Grid, 0, 0, 'A', cWhite, cBlue);
    R.Render(Grid);
    R.ClearDirty;
    Requests := F.Requests;
    Assert.IsFalse(R.Render(Grid), 'nothing changed');
    Assert.IsTrue(R.DirtyRect.IsEmpty);
    Assert.AreEqual(Requests, F.Requests, 'no glyph is looked up again');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.BlinkingTextHidesWithThePhase;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(1, 1);
    PutTerminalText(Grid, 0, 0, 'A', cRed, cWhite, [ccaBlink]);
    R.Render(Grid, True);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(3, 5));
    Assert.IsTrue(R.Render(Grid, False), 'the phase change repaints the cell');
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(3, 5), 'the glyph is hidden');
    Assert.IsTrue(R.Render(Grid, True));
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(3, 5));
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.BoldAsksForTheBoldGlyph;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(1, 1);
    PutTerminalText(Grid, 0, 0, 'A', cRed, cWhite, [ccaBold]);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(7, 5), 'the bold box is one pixel wider');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.InsertCaretIsABarAtTheLeftEdge;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    Grid := NewGrid(1, 1);
    MarkGridInsertCaret(Grid, 0, 0);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(2, 8), 'two pixels wide');
    Assert.IsFalse(R.PixelAt(0, 0) = Cardinal($FF0000AA));
    Assert.IsFalse(R.PixelAt(1, 15) = Cardinal($FF0000AA));
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.CellAtMapsPixelsToCells;
var
  R: TPixelGridRenderer;
  Col, Row: Integer;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.Render(NewGrid(10, 4));
    R.CellAt(17, 33, Col, Row);
    Assert.AreEqual(2, Col);
    Assert.AreEqual(2, Row);
    R.CellAt(5000, 5000, Col, Row);
    Assert.AreEqual(9, Col, 'clamped to the last column');
    Assert.AreEqual(3, Row);
    R.CellAt(-4, -4, Col, Row);
    Assert.AreEqual(0, Col);
    Assert.AreEqual(0, Row);
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.ResizedGridIsPaintedCompletely;
var
  R: TPixelGridRenderer;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.Render(NewGrid(2, 2));
    R.ClearDirty;
    Assert.IsTrue(R.Render(NewGrid(3, 2)));
    Assert.AreEqual(24, R.Width);
    Assert.AreEqual(24, R.DirtyRect.Right, 'the whole bitmap is new');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(23, 31));
  finally
    R.Free;
  end;
end;

function SolidRedIcon: TPixelIconSource;
begin
  Result :=
    function(AId: Integer; out AWidth, AHeight: Integer; out APixels: TBytes): Boolean
    var
      I: Integer;
    begin
      AWidth := 4;
      AHeight := 4;
      SetLength(APixels, 4 * 4 * 4);
      for I := 0 to 15 do
      begin
        APixels[I * 4] := 0;
        APixels[I * 4 + 1] := 0;
        APixels[I * 4 + 2] := $FF;
        APixels[I * 4 + 3] := $FF;
      end;
      Result := AId = 1;
    end;
end;

procedure TTestPixelGrid.IconCoversItsCellAndTheFillerAfterIt;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.SetIconSource(SolidRedIcon());
    Grid := NewGrid(3, 1);
    DrawGridIcon(Grid, 0, 0, 1, '*', cWhite, cBlue);
    R.Render(Grid);
    // Two cells are 16 x 16 pixels; the picture is 14 square, centered in them.
    Assert.AreEqual(Cardinal($FFFF0000), R.PixelAt(4, 8), 'in the icon cell');
    Assert.AreEqual(Cardinal($FFFF0000), R.PixelAt(12, 8), 'in the filler cell');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(0, 0), 'the margin keeps the background');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(20, 8), 'the cell after the filler is untouched');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.FillerIsClearedWhenTheIconGoesAway;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.SetIconSource(SolidRedIcon());
    Grid := NewGrid(3, 1);
    DrawGridIcon(Grid, 0, 0, 1, '*', cWhite, cBlue);
    R.Render(Grid);
    Grid := NewGrid(3, 1);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(12, 8), 'the right half is blank again');
    Assert.AreEqual(Cardinal($FF0000AA), R.PixelAt(4, 8), 'the left half is blank again');
  finally
    R.Free;
  end;
end;

procedure TTestPixelGrid.CellWithoutAnIconPictureKeepsItsGlyph;
var
  R: TPixelGridRenderer;
  Grid: TTerminalGrid;
begin
  R := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  try
    R.SetIconSource(SolidRedIcon());
    Grid := NewGrid(2, 1);
    // Id 2 has no picture: the fallback glyph is drawn as for any character.
    DrawGridIcon(Grid, 0, 0, 2, 'A', cRed, cWhite);
    R.Render(Grid);
    Assert.AreEqual(Cardinal($FFAA0000), R.PixelAt(1, 2), 'glyph box in the foreground color');
    Assert.AreEqual(Cardinal($FFFFFFFF), R.PixelAt(0, 0), 'background of the cell');
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPixelGrid);

end.
