unit TestPdfView;

{ View state of the PDF viewer plugin: fit modes, zoom, scrolling and page turning. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPdfView = class
  public
    [Test] procedure TestFitWidthScalesPageToTheAreaWidth;
    [Test] procedure TestFitPageKeepsWholePageInTheArea;
    [Test] procedure TestFrameIsClippedToTheArea;
    [Test] procedure TestPageDownScrollsThenTurnsThePage;
    [Test] procedure TestPageUpFromTopLandsAtTheBottomOfThePreviousPage;
    [Test] procedure TestZoomKeysChangePercentAndStayInRange;
    [Test] procedure TestWheelScrollsAndCtrlWheelZooms;
    [Test] procedure TestHomeAndEndJumpToFirstAndLastPage;
    [Test] procedure TestUnknownKeyIsNotHandled;
    [Test] procedure TestStatusTextShowsPageAndPercent;
    [Test] procedure TestOffsetsStayInsideThePage;
    [Test] procedure TestBmpHasHeaderPaddedRowsAndBottomUpOrder;
    [Test] procedure TestBmpRejectsMismatchedSize;
  end;

implementation

uses
  System.SysUtils, uPdfView;

function MakeView(APages: Integer): TPdfView;
begin
  Result := TPdfView.Create(APages);
  Result.SetArea(600, 400);
  Result.SetPageSize(600, 800);
end;

procedure TTestPdfView.TestFitWidthScalesPageToTheAreaWidth;
var
  V: TPdfView;
  L: TPdfLayout;
begin
  V := MakeView(1);
  try
    L := V.Layout;
    Assert.AreEqual(600, L.ScaledW);
    Assert.AreEqual(800, L.ScaledH);
    Assert.AreEqual(600, L.FrameW);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestFitPageKeepsWholePageInTheArea;
var
  V: TPdfView;
  L: TPdfLayout;
begin
  V := MakeView(1);
  try
    Assert.IsTrue(V.HandleKey('0'));
    L := V.Layout;
    Assert.AreEqual(400, L.ScaledH);
    Assert.AreEqual(300, L.ScaledW);
    Assert.AreEqual(300, L.FrameW, 'a page narrower than the area is not padded');
    Assert.AreEqual(400, L.FrameH);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestFrameIsClippedToTheArea;
var
  V: TPdfView;
  L: TPdfLayout;
begin
  V := MakeView(1);
  try
    L := V.Layout;
    Assert.AreEqual(400, L.FrameH, 'only the visible part is drawn');
    Assert.AreEqual(0, L.StartY);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestPageDownScrollsThenTurnsThePage;
var
  V: TPdfView;
begin
  V := MakeView(3);
  try
    V.HandleKey('PageDown');
    Assert.AreEqual(0, V.Page);
    Assert.AreEqual(-360, V.Layout.StartY);
    V.HandleKey('PageDown');
    Assert.AreEqual(-400, V.Layout.StartY, 'the scroll stops at the bottom edge');
    V.HandleKey('PageDown');
    Assert.AreEqual(1, V.Page);
    Assert.IsTrue(V.TakePageChanged);
    Assert.IsFalse(V.TakePageChanged, 'the flag is read once');
    V.SetPageSize(600, 800);
    Assert.AreEqual(0, V.Layout.StartY);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestPageUpFromTopLandsAtTheBottomOfThePreviousPage;
var
  V: TPdfView;
begin
  V := MakeView(3);
  try
    V.HandleKey('End');
    Assert.AreEqual(2, V.Page);
    V.TakePageChanged;
    V.SetPageSize(600, 800);
    V.HandleKey('PageUp');
    Assert.AreEqual(1, V.Page);
    V.TakePageChanged;
    V.SetPageSize(600, 800);
    Assert.AreEqual(-400, V.Layout.StartY);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestZoomKeysChangePercentAndStayInRange;
var
  V: TPdfView;
  I: Integer;
begin
  V := MakeView(1);
  try
    Assert.IsTrue(V.HandleKey('1'));
    Assert.AreEqual(100, V.Percent);
    V.HandleKey('+');
    Assert.AreEqual(125, V.Percent);
    V.HandleKey('-');
    V.HandleKey('-');
    Assert.AreEqual(80, V.Percent);
    for I := 1 to 40 do
      V.HandleKey('+');
    Assert.IsTrue(V.Percent <= 800, 'upper limit');
    for I := 1 to 80 do
      V.HandleKey('-');
    Assert.IsTrue(V.Percent >= 10, 'lower limit');
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestWheelScrollsAndCtrlWheelZooms;
var
  V: TPdfView;
begin
  V := MakeView(1);
  try
    V.Wheel(-1, False);
    Assert.AreEqual(-50, V.Layout.StartY, 'wheel towards the user scrolls down');
    V.Wheel(1, False);
    Assert.AreEqual(0, V.Layout.StartY);
    V.HandleKey('1');
    V.Wheel(1, True);
    Assert.IsTrue(V.Fit = pfZoom);
    Assert.AreEqual(125, V.Percent);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestHomeAndEndJumpToFirstAndLastPage;
var
  V: TPdfView;
begin
  V := MakeView(5);
  try
    V.HandleKey('End');
    Assert.AreEqual(4, V.Page);
    V.HandleKey('Home');
    Assert.AreEqual(0, V.Page);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestUnknownKeyIsNotHandled;
var
  V: TPdfView;
begin
  V := MakeView(1);
  try
    Assert.IsFalse(V.HandleKey('F7'));
    Assert.IsFalse(V.HandleKey('Ctrl+Q'));
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestStatusTextShowsPageAndPercent;
var
  V: TPdfView;
begin
  V := MakeView(12);
  try
    V.HandleKey('1');
    Assert.AreEqual('Page 1 / 12, 100%', V.StatusText('Page %d / %d, %d%%'));
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestOffsetsStayInsideThePage;
var
  V: TPdfView;
  I: Integer;
  L: TPdfLayout;
begin
  V := MakeView(1);
  try
    V.HandleKey('+');
    for I := 1 to 30 do
    begin
      V.HandleKey('Right');
      V.HandleKey('Down');
    end;
    L := V.Layout;
    Assert.IsTrue(L.StartX >= L.FrameW - L.ScaledW, 'not past the right edge');
    Assert.IsTrue(L.StartY >= L.FrameH - L.ScaledH, 'not past the bottom edge');
    for I := 1 to 60 do
    begin
      V.HandleKey('Left');
      V.HandleKey('Up');
    end;
    Assert.AreEqual(0, V.Layout.StartX);
    Assert.AreEqual(0, V.Layout.StartY);
  finally
    V.Free;
  end;
end;

procedure TTestPdfView.TestBmpHasHeaderPaddedRowsAndBottomUpOrder;
var
  Bgra, Bmp: TBytes;
begin
  // 1 x 2 pixels: top is blue (B=1), bottom is red (R=3).
  Bgra := TBytes.Create(1, 2, 3, 255, 10, 20, 30, 255);
  Bmp := BgraToBmp(Bgra, 1, 2);
  Assert.AreEqual(54 + 4 * 2, Integer(Length(Bmp)), 'rows are padded to 4 bytes');
  Assert.AreEqual(Integer(Ord('B')), Integer(Bmp[0]));
  Assert.AreEqual(Integer(Ord('M')), Integer(Bmp[1]));
  Assert.AreEqual(1, Integer(Bmp[18]), 'width');
  Assert.AreEqual(2, Integer(Bmp[22]), 'height');
  Assert.AreEqual(24, Integer(Bmp[28]), 'bits per pixel');
  Assert.AreEqual(10, Integer(Bmp[54]), 'the first stored row is the bottom one');
  Assert.AreEqual(1, Integer(Bmp[58]));
end;

procedure TTestPdfView.TestBmpRejectsMismatchedSize;
begin
  Assert.AreEqual(0, Integer(Length(BgraToBmp(TBytes.Create(1, 2, 3), 1, 1))));
  Assert.AreEqual(0, Integer(Length(BgraToBmp(nil, 0, 0))));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPdfView);

end.
