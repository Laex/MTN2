unit TestThumbsLayout;

{ Thumbnail sheet: selection movement and paging, hit testing, fitting and
  shrinking of pictures, and the painted frame. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestThumbsLayout = class
  public
    [Test] procedure TestGridSizeFollowsArea;
    [Test] procedure TestArrowKeysMoveAndClamp;
    [Test] procedure TestPageKeysMoveByPage;
    [Test] procedure TestHitTestMapsPixelsToCells;
    [Test] procedure TestFitInBoxNeverEnlarges;
    [Test] procedure TestShrinkAveragesPixels;
    [Test] procedure TestPaintSheetDrawsPictureAndSelection;
    [Test] procedure TestPaintSheetMarksFailedPicture;
  end;

implementation

uses
  System.SysUtils, uThumbsLayout;

procedure TTestThumbsLayout.TestGridSizeFollowsArea;
var
  M: TThumbsModel;
begin
  M := TThumbsModel.Create(100);
  try
    M.SetArea(cCellW * 5 + 7, cCellH * 2 + 3);
    Assert.AreEqual(5, M.Cols);
    Assert.AreEqual(2, M.Rows);
    Assert.AreEqual(10, M.PerPage);
  finally
    M.Free;
  end;
end;

procedure TTestThumbsLayout.TestArrowKeysMoveAndClamp;
var
  M: TThumbsModel;
begin
  M := TThumbsModel.Create(7);
  try
    M.SetArea(cCellW * 3, cCellH * 2);
    Assert.IsTrue(M.HandleKey('Right'));
    Assert.AreEqual(1, M.Selected);
    Assert.IsTrue(M.HandleKey('Down'));
    Assert.AreEqual(4, M.Selected);
    M.HandleKey('Down');
    Assert.AreEqual(6, M.Selected, 'Down past the last row stays inside the list');
    M.HandleKey('Home');
    M.HandleKey('Left');
    Assert.AreEqual(0, M.Selected);
    M.HandleKey('End');
    Assert.AreEqual(6, M.Selected);
    Assert.IsFalse(M.HandleKey('F5'));
  finally
    M.Free;
  end;
end;

procedure TTestThumbsLayout.TestPageKeysMoveByPage;
var
  M: TThumbsModel;
begin
  M := TThumbsModel.Create(20);
  try
    M.SetArea(cCellW * 2, cCellH * 2);
    M.HandleKey('PageDown');
    Assert.AreEqual(4, M.Selected);
    Assert.AreEqual(4, M.First);
    M.HandleKey('PageUp');
    Assert.AreEqual(0, M.Selected);
    Assert.AreEqual(0, M.First);
  finally
    M.Free;
  end;
end;

procedure TTestThumbsLayout.TestHitTestMapsPixelsToCells;
var
  M: TThumbsModel;
  L, T: Integer;
begin
  M := TThumbsModel.Create(5);
  try
    M.SetArea(cCellW * 3, cCellH * 2);
    Assert.IsTrue(M.CellRect(4, L, T));
    Assert.AreEqual(4, M.HitTest(L + 5, T + 5));
    Assert.AreEqual(-1, M.HitTest(M.AreaWidth - 1, M.AreaHeight - 1),
      'the cell after the last picture is empty');
    Assert.AreEqual(-1, M.HitTest(-1, 0));
  finally
    M.Free;
  end;
end;

procedure TTestThumbsLayout.TestFitInBoxNeverEnlarges;
var
  W, H: Integer;
begin
  FitInBox(400, 200, 100, 100, W, H);
  Assert.AreEqual(100, W);
  Assert.AreEqual(50, H);
  FitInBox(30, 20, 100, 100, W, H);
  Assert.AreEqual(30, W);
  Assert.AreEqual(20, H);
end;

procedure TTestThumbsLayout.TestShrinkAveragesPixels;
var
  Src, Dst: TBytes;
  I: Integer;
begin
  SetLength(Src, 2 * 2 * 4);
  for I := 0 to 3 do
  begin
    Src[I * 4] := Byte((I mod 2) * 200);
    Src[I * 4 + 1] := 0;
    Src[I * 4 + 2] := 0;
    Src[I * 4 + 3] := 255;
  end;
  Dst := ShrinkPixels(Src, 2, 2, 1, 1);
  Assert.IsTrue(Length(Dst) = 4);
  Assert.AreEqual(100, Integer(Dst[0]));
  Assert.AreEqual(255, Integer(Dst[3]));
end;

function PixelAt(const AFrame: TBytes; AWidth, AX, AY: Integer): Cardinal;
begin
  Result := PCardinal(@AFrame[(AY * AWidth + AX) * 4])^;
end;

procedure TTestThumbsLayout.TestPaintSheetDrawsPictureAndSelection;
var
  M: TThumbsModel;
  Images: TArray<TThumbImage>;
  Frame: TBytes;
  L, T, I: Integer;
begin
  M := TThumbsModel.Create(2);
  try
    M.SetArea(cCellW * 2, cCellH);
    SetLength(Images, 2);
    Images[0].Width := 10;
    Images[0].Height := 10;
    SetLength(Images[0].Pixels, 400);
    for I := 0 to 99 do
    begin
      Images[0].Pixels[I * 4] := 0;
      Images[0].Pixels[I * 4 + 1] := 255;
      Images[0].Pixels[I * 4 + 2] := 0;
      Images[0].Pixels[I * 4 + 3] := 255;
    end;
    Frame := PaintSheet(M, Images);
    Assert.IsTrue(Length(Frame) = M.AreaWidth * M.AreaHeight * 4);
    Assert.IsTrue(M.CellRect(0, L, T));
    Assert.IsTrue(PixelAt(Frame, M.AreaWidth, L + cCellW div 2, T + cCellH div 2) = Cardinal($FF00FF00),
      'the picture is painted in the middle of its cell');
    Assert.IsTrue(PixelAt(Frame, M.AreaWidth, L + 1, T + 1) <>
      PixelAt(Frame, M.AreaWidth, M.AreaWidth - 2, 1),
      'the selected cell has a frame the other one lacks');
  finally
    M.Free;
  end;
end;

procedure TTestThumbsLayout.TestPaintSheetMarksFailedPicture;
var
  M: TThumbsModel;
  Images: TArray<TThumbImage>;
  Plain, Marked: TBytes;
  L, T: Integer;
begin
  M := TThumbsModel.Create(1);
  try
    M.SetArea(cCellW, cCellH);
    SetLength(Images, 1);
    Plain := PaintSheet(M, Images);
    Images[0].Failed := True;
    Marked := PaintSheet(M, Images);
    M.CellRect(0, L, T);
    Assert.IsTrue(PixelAt(Plain, M.AreaWidth, L + cCellW div 2, T + cCellH div 2) <>
      PixelAt(Marked, M.AreaWidth, L + cCellW div 2, T + cCellH div 2));
  finally
    M.Free;
  end;
end;

end.
