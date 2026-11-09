unit TestCellEdges;

{ Edge lines of a character cell: the rectangles they cover, how a cell with
  them differs from one without, and that a drop shadow keeps them. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCellEdges = class
  public
    [Test] procedure RectsHugTheOuterSidesOfTheCell;
    [Test] procedure RectsStayInsideAThinCell;
    [Test] procedure NoEdgesGiveNoRects;
    [Test] procedure HalfSpanMeetsTheMiddleLine;
    [Test] procedure EdgesMakeCellsDiffer;
    [Test] procedure DrawingIntoACellReplacesItsEdges;
    [Test] procedure EdgesOutsideTheGridAreIgnored;
    [Test] procedure ShadowKeepsEdgesAndDarkensTheirColor;
    [Test] procedure OutlineNeedsPreferenceAndHostSupport;
  end;

implementation

uses
  System.Types, System.UITypes,
  uThemeTypes, uTerminalTypes, uDisplaySettings, uThemeDrawing;

procedure TTestCellEdges.RectsHugTheOuterSidesOfTheCell;
var
  R: TArray<TRect>;
begin
  R := CellEdgeRects([ceLeft, ceBottom], 10, 20, 18, 36, 2);
  Assert.AreEqual(2, Integer(Length(R)), 'one rectangle per side');
  Assert.IsTrue(R[0] = TRect.Create(10, 20, 12, 36), 'left side: full height, 2 px wide');
  Assert.IsTrue(R[1] = TRect.Create(10, 34, 18, 36), 'bottom side: full width, 2 px high');
  R := CellEdgeRects([ceRight, ceTop], 10, 20, 18, 36, 1);
  Assert.IsTrue(R[0] = TRect.Create(17, 20, 18, 36), 'right side');
  Assert.IsTrue(R[1] = TRect.Create(10, 20, 18, 21), 'top side');
end;

procedure TTestCellEdges.RectsStayInsideAThinCell;
var
  R: TArray<TRect>;
begin
  R := CellEdgeRects([ceLeft, ceTop], 0, 0, 3, 5, 9);
  Assert.AreEqual(3, R[0].Width, 'a line never gets wider than the cell');
  Assert.AreEqual(3, R[1].Height, 'a line never gets taller than the cell');
  R := CellEdgeRects([ceLeft], 0, 0, 8, 16, 0);
  Assert.AreEqual(1, R[0].Width, 'zero thickness still draws one pixel');
end;

procedure TTestCellEdges.NoEdgesGiveNoRects;
begin
  Assert.AreEqual(0, Integer(Length(CellEdgeRects([], 0, 0, 8, 16, 1))), 'no sides, no rectangles');
  Assert.AreEqual(0, Integer(Length(CellEdgeRects([ceLeft], 4, 4, 4, 16, 1))), 'an empty cell has no edges');
end;

procedure TTestCellEdges.HalfSpanMeetsTheMiddleLine;
var
  R: TArray<TRect>;
begin
  R := CellEdgeRects([ceLeft, ceRight], 10, 20, 18, 36, 2, esLower);
  Assert.AreEqual(28 - 1, R[0].Top, 'a lower half starts at the middle line');
  Assert.AreEqual(36, R[0].Bottom, 'and runs to the bottom of the cell');
  Assert.AreEqual(R[0].Top, R[1].Top, 'on both sides');
  R := CellEdgeRects([ceLeft], 10, 20, 18, 36, 2, esUpper);
  Assert.AreEqual(20, R[0].Top, 'an upper half starts at the top of the cell');
  Assert.AreEqual(28 + 1, R[0].Bottom, 'and ends past the middle line');
  R := CellEdgeRects([ceTop, ceBottom], 10, 20, 18, 36, 1, esLower);
  Assert.IsTrue(R[0] = TRect.Create(10, 20, 18, 21), 'the span leaves horizontal sides alone');
end;

procedure TTestCellEdges.EdgesMakeCellsDiffer;
var
  A, B: TCharCell;
begin
  A := TCharCell.Make('x', $FFFFFFFF, $FF000000);
  B := A;
  Assert.IsTrue(SameCharCell(A, B), 'copies are the same');
  B.Edges := [ceLeft];
  B.EdgeColor := $FFFF0000;
  B.EdgeThick := 1;
  Assert.IsFalse(SameCharCell(A, B), 'an edge is a difference');
  A := B;
  A.EdgeColor := $FF00FF00;
  Assert.IsFalse(SameCharCell(A, B), 'so is the color of an edge');
  A.EdgeColor := B.EdgeColor;
  A.EdgeThick := 2;
  Assert.IsFalse(SameCharCell(A, B), 'and its thickness');
  A.EdgeThick := B.EdgeThick;
  A.EdgeSpan := esUpper;
  Assert.IsFalse(SameCharCell(A, B), 'and its span');
end;

procedure TTestCellEdges.DrawingIntoACellReplacesItsEdges;
var
  Grid: TTerminalGrid;
begin
  AllocTerminalGrid(Grid, 4, 2);
  AddGridEdges(Grid, 1, 0, [ceLeft], $FFFFFFFF);
  AddGridEdges(Grid, 1, 0, [ceBottom], $FFFFFFFF);
  Assert.IsTrue(Grid[0][1].Edges = [ceLeft, ceBottom], 'sides add up');
  DrawGridChar(Grid, 1, 0, 'a', $FFFFFFFF, $FF000000);
  Assert.IsTrue(Grid[0][1].Edges = [], 'a fresh draw starts without edges');
end;

procedure TTestCellEdges.EdgesOutsideTheGridAreIgnored;
var
  Grid: TTerminalGrid;
begin
  AllocTerminalGrid(Grid, 2, 2);
  AddGridEdges(Grid, -1, 0, [ceLeft], $FFFFFFFF);
  AddGridEdges(Grid, 0, 5, [ceLeft], $FFFFFFFF);
  AddGridEdges(Grid, 2, 0, [ceLeft], $FFFFFFFF);
  Assert.IsTrue(Grid[0][0].Edges = [], 'nothing was written inside the grid');
end;

procedure TTestCellEdges.ShadowKeepsEdgesAndDarkensTheirColor;
var
  Grid: TTerminalGrid;
  Saved: TShadowStyle;
begin
  Saved := GShadowStyle;
  try
    GShadowStyle := ssClassic;
    AllocTerminalGrid(Grid, 8, 6);
    ClearTerminalGrid(Grid, $FFFFFFFF, $FF808080);
    AddGridEdges(Grid, 3, 1, [ceLeft], $FFFFFFFF, 2);
    DrawDialogShadow(Grid, TRectI.Make(0, 0, 2, 2));
    Assert.IsTrue(Grid[1][3].Edges = [ceLeft], 'the shaded cell keeps its edge');
    Assert.AreEqual(Byte(2), Grid[1][3].EdgeThick, 'and its thickness');
    Assert.IsTrue(Grid[1][3].EdgeColor <> $FFFFFFFF, 'the line is darkened with the cell');
  finally
    GShadowStyle := Saved;
  end;
end;

procedure TTestCellEdges.OutlineNeedsPreferenceAndHostSupport;
var
  Pref, Drawn: Boolean;
begin
  Pref := GEdgeBorders;
  Drawn := GEdgeBordersDrawn;
  try
    GEdgeBorders := True;
    GEdgeBordersDrawn := True;
    Assert.IsTrue(EdgeBordersActive, 'wanted and supported');
    GEdgeBorders := False;
    Assert.IsFalse(EdgeBordersActive, 'switched off by the user: the framed look');
    GEdgeBorders := True;
    GEdgeBordersDrawn := False;
    Assert.IsFalse(EdgeBordersActive, 'a text-mode host keeps the frame');
  finally
    GEdgeBorders := Pref;
    GEdgeBordersDrawn := Drawn;
  end;
end;

end.
