unit TestDialogHostExtracts;

{ Values JSON, protocol-2 layout and list drawing pulled out of the dialog
  host. Each check calls that code directly. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogValues = class
  public
    [Test] procedure EmptyIdIsLeftOut;
    [Test] procedure BackslashesAndControlCharsSurviveTheRoundTrip;
    [Test] procedure CheckedRadioOfAGroupIsEmittedOnce;
    [Test] procedure ListMirrorOverridesSelectedIndex;
  end;

  [TestFixture]
  TTestDialogV2Layout = class
  public
    [Test] procedure FocusChangeScrollsAndSameFocusKeepsTheWheel;
    [Test] procedure ListAndRadioGroupAreCutAndOtherControlsDrop;
    [Test] procedure TextControlsLeaveACellBeforeTheBorder;
  end;

  [TestFixture]
  TTestDialogFlowLayout = class
  public
    [Test] procedure ButtonsShareARowUntilTheyWrap;
    [Test] procedure ListTakesItsItemRows;
  end;

  [TestFixture]
  TTestDialogListDraw = class
  public
    [Test] procedure SingleRowShowsSelectionAndArrow;
    [Test] procedure MultiRowReservesTheRightColumn;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.JSON,
  uDialogTypes, uDialogValues, uDialogV2Layout, uDialogLayout, uDialogListDraw,
  uDialogHost, uTerminalTypes, uThemeTypes;

procedure TTestDialogValues.EmptyIdIsLeftOut;
var
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Controls: TArray<TDialogControl>;
  Json: string;
begin
  SetLength(Controls, 2);
  Controls[0] := MakeInput('', 'secret');
  Controls[1] := MakeInput('name', 'visible');
  Json := DialogValuesJson(Controls, '', 0);
  Assert.IsTrue(Pos('secret', Json) = 0, 'an input with no id is omitted');
  Assert.IsTrue(Pos('"name":"visible"', Json) > 0, 'a named input is kept');

  Decl := Default(TDialogDeclaration);
  Decl.Width := 40;
  Decl.Height := 10;
  Decl.Controls := Controls;
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, nil);
    Json := Host.GetValuesJson;
    Assert.IsTrue(Pos('secret', Json) = 0, 'the host omits an input with no id');
    Assert.IsTrue(Pos('"name":"visible"', Json) > 0, 'the host keeps a named input');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogValues.BackslashesAndControlCharsSurviveTheRoundTrip;
const
  cValue = 'C:\nonexistent\key "x"' + #9 + 'end\';
var
  Controls: TArray<TDialogControl>;
  Root: TJSONValue;
begin
  SetLength(Controls, 1);
  Controls[0] := MakeInput('path', cValue);
  Root := TJSONObject.ParseJSONValue(DialogValuesJson(Controls, '', 0));
  try
    Assert.IsTrue(Root is TJSONObject, 'the values form a JSON object');
    Assert.AreEqual(cValue, TJSONObject(Root).GetValue<string>('path'),
      'an input value comes back unchanged');
  finally
    Root.Free;
  end;
end;

procedure TTestDialogValues.CheckedRadioOfAGroupIsEmittedOnce;
var
  Controls: TArray<TDialogControl>;
  Json: string;
begin
  SetLength(Controls, 2);
  Controls[0] := MakeRadio('first', 'mode', 'One', True);
  Controls[1] := MakeRadio('second', 'mode', 'Two', True);
  Json := DialogValuesJson(Controls, '', 0);
  Assert.IsTrue(Pos('"mode":"first"', Json) > 0, 'the first checked button is the group value');
  Assert.IsTrue(Pos('"mode":"second"', Json) = 0, 'a later button of the same group is omitted');
  Assert.IsTrue(Pos('"second"', Json) = 0, 'the later button id is not a field of its own');
end;

procedure TTestDialogValues.ListMirrorOverridesSelectedIndex;
var
  Controls: TArray<TDialogControl>;
  Json: string;
begin
  SetLength(Controls, 1);
  Controls[0] := MakeList('files', ['one', 'two'], 0);
  SetLength(Controls[0].ItemIds, 2);
  Controls[0].ItemIds[0] := 'id-one';
  Controls[0].ItemIds[1] := 'id-two';
  Json := DialogValuesJson(Controls, 'files', 1);
  Assert.IsTrue(Pos('"files":"id-two"', Json) > 0,
    'the host selection mirror wins over the stored index');
  Assert.IsTrue(Pos('id-one', Json) = 0, 'the stored index is not reported');
end;

function AtRow(AKind: TDialogControlKind; const AId: string; ARow, ABoxH: Integer;
  const AItems: TArray<string>; const ACaption: string): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := ACaption;
  Result.Row := ARow;
  Result.Col := 0;
  Result.BoxH := ABoxH;
  Result.Items := AItems;
end;

function EmptyBox(const R: TRectI): Boolean;
begin
  Result := R.Right < R.Left;
end;

procedure TTestDialogV2Layout.FocusChangeScrollsAndSameFocusKeepsTheWheel;
var
  Controls: TArray<TDialogControl>;
  Frame: TRectI;
  Lay: TDialogV2Layout;
begin
  SetLength(Controls, 2);
  Controls[0] := AtRow(dckLabel, 'top', 0, 1, nil, 'Top');
  Controls[1] := AtRow(dckLabel, 'low', 20, 1, nil, 'Low');
  Frame := TRectI.Make(0, 0, 21, 11);

  Lay := LayoutDialogV2(Controls, Frame, 0, 0, -1);
  Assert.IsTrue(Lay.ScrollY = 0, 'a focused row already in view is not scrolled');
  Assert.IsTrue(Lay.ScrollFollow = 0, 'the follow marker records that focus');

  Lay := LayoutDialogV2(Controls, Frame, 0, 4, 0);
  Assert.IsTrue(Lay.ScrollY = 4, 'the same focus keeps a wheel drag');
  Assert.IsTrue(Lay.ScrollFollow = 0, 'the follow marker stays on that focus');

  Lay := LayoutDialogV2(Controls, Frame, 1, 4, 0);
  Assert.IsTrue(Lay.ScrollY = 11, 'moving the focus scrolls that row into view');
  Assert.IsTrue(Lay.ScrollFollow = 1, 'the follow marker moves with the focus');
end;

procedure TTestDialogV2Layout.ListAndRadioGroupAreCutAndOtherControlsDrop;
var
  Controls: TArray<TDialogControl>;
  Items: TArray<string>;
  Frame: TRectI;
  Lay: TDialogV2Layout;
  I: Integer;
begin
  SetLength(Items, 15);
  for I := 0 to High(Items) do
    Items[I] := 'row';
  SetLength(Controls, 3);
  Controls[0] := AtRow(dckList, 'items', 2, 0, Items, '');
  Controls[1] := AtRow(dckRadioGroup, 'pick', 8, 0, ['a', 'b', 'c', 'd', 'e'], 'Pick');
  Controls[2] := AtRow(dckLabel, 'low', 20, 1, nil, 'Low');
  Frame := TRectI.Make(0, 0, 21, 11);

  Lay := LayoutDialogV2(Controls, Frame, 0, 0, 0);
  Assert.IsTrue(not EmptyBox(Lay.Bounds[0]), 'a list that crosses the view is kept');
  Assert.IsTrue(Lay.Bounds[0].Bottom = 10, 'the list is cut to the client bottom');
  Assert.IsTrue(not EmptyBox(Lay.Bounds[1]), 'a radio group that crosses the view is kept');
  Assert.IsTrue(Lay.Bounds[1].Bottom = 10, 'the radio group is cut to the client bottom');
  Assert.IsTrue(EmptyBox(Lay.Bounds[2]), 'a label wholly outside the view is dropped');
end;

procedure TTestDialogV2Layout.TextControlsLeaveACellBeforeTheBorder;
var
  Controls: TArray<TDialogControl>;
  Frame: TRectI;
  Lay: TDialogV2Layout;
begin
  SetLength(Controls, 4);
  Controls[3] := AtRow(dckLabel, 'rule', 3, 1, nil, StringOfChar(#$2500, 40));
  Controls[0] := AtRow(dckCheckbox, 'wide', 0, 1, nil, 'A checkbox caption much longer than the box');
  Controls[1] := AtRow(dckLabel, 'note', 1, 1, nil, 'A label caption much longer than the box');
  Controls[2] := AtRow(dckInput, 'edit', 2, 1, nil, '');
  Frame := TRectI.Make(0, 0, 21, 11);

  Lay := LayoutDialogV2(Controls, Frame, 0, 0, -1);
  Assert.AreEqual(19, Lay.Bounds[0].Right, 'a checkbox keeps a blank cell before the border');
  Assert.AreEqual(19, Lay.Bounds[1].Right, 'a label keeps a blank cell before the border');
  Assert.AreEqual(20, Lay.Bounds[2].Right, 'an input still reaches the client edge');
  Assert.AreEqual(20, Lay.Bounds[3].Right, 'a separator line still joins the frame');
end;

procedure TTestDialogFlowLayout.ButtonsShareARowUntilTheyWrap;
var
  Controls: TArray<TDialogControl>;
  Frame: TRectI;
  Lay: TDialogFlowLayout;
begin
  SetLength(Controls, 3);
  Controls[0] := MakeButton('ok', '&OK', True, False);
  Controls[1] := MakeButton('skip', '&Skip', False, False);
  Controls[2] := MakeButton('cancel', '&Cancel', False, True);
  // Inner width fits two 10-cell buttons with a gap, but not a third.
  Frame := TRectI.Make(0, 0, 30, 8);

  Lay := LayoutDialogFlow(Controls, Frame);
  Assert.AreEqual(Lay.Bounds[0].Top, Lay.Bounds[1].Top,
    'the first two buttons share a row');
  Assert.IsTrue(Lay.Bounds[1].Left > Lay.Bounds[0].Right,
    'the second button sits to the right of the first');
  Assert.IsTrue(Lay.Bounds[2].Top > Lay.Bounds[0].Top,
    'a button that would pass the right edge wraps');
end;

procedure TTestDialogFlowLayout.ListTakesItsItemRows;
var
  Controls: TArray<TDialogControl>;
  Frame: TRectI;
  Lay: TDialogFlowLayout;
begin
  SetLength(Controls, 2);
  Controls[0] := MakeList('files', ['a', 'b', 'c'], 0);
  Controls[1] := MakeButton('ok', 'OK', True, False);
  Frame := TRectI.Make(0, 0, 30, 12);

  Lay := LayoutDialogFlow(Controls, Frame);
  Assert.AreEqual(3, Lay.Bounds[0].Bottom - Lay.Bounds[0].Top + 1,
    'a three-item list occupies three rows');
  Assert.IsTrue(Lay.Bounds[1].Top = Lay.Bounds[0].Bottom + 1,
    'the button starts on the row after the list');
end;

function BlankGrid(AWidth, AHeight: Integer): TTerminalGrid;
var
  X, Y: Integer;
begin
  SetLength(Result, AHeight);
  for Y := 0 to AHeight - 1 do
  begin
    SetLength(Result[Y], AWidth);
    for X := 0 to AWidth - 1 do
      Result[Y][X] := TCharCell.Make(' ', TAlphaColor($FFAAAAAA), TAlphaColor($FF000000));
  end;
end;

procedure TTestDialogListDraw.SingleRowShowsSelectionAndArrow;
var
  Grid: TTerminalGrid;
  C: TDialogControl;
  R: TRectI;
begin
  C := MakeList('files', ['Alpha', 'Beta'], 1);
  R := TRectI.Make(1, 1, 8, 1);
  Grid := BlankGrid(12, 4);
  DrawDialogSingleRowList(Grid, R, C, nil, 1);
  Assert.IsTrue(Grid[1][1].CharValue = 'B', 'the selected item is shown');
  Assert.IsTrue(Grid[1][8].CharValue = #$2193, 'the last cell is the down arrow');
end;

procedure TTestDialogListDraw.MultiRowReservesTheRightColumn;
var
  Grid: TTerminalGrid;
  C: TDialogControl;
  R: TRectI;
begin
  C := MakeList('files', ['ABCDEFGH'], 0);
  R := TRectI.Make(1, 1, 8, 4);
  Grid := BlankGrid(12, 8);
  DrawDialogMultiRowList(Grid, R, C, nil, TAlphaColor($FF000000), TAlphaColor($FFFFFFFF),
    4, 0, 0, 20);
  Assert.IsTrue(Grid[1][1].CharValue = 'A', 'item text starts at the left');
  Assert.IsTrue(Grid[1][7].CharValue = 'G', 'text stops one cell short of the bar');
  Assert.IsTrue(Grid[1][8].CharValue = #$25B2, 'the right column is the scrollbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogValues);
  TDUnitX.RegisterTestFixture(TTestDialogV2Layout);
  TDUnitX.RegisterTestFixture(TTestDialogFlowLayout);
  TDUnitX.RegisterTestFixture(TTestDialogListDraw);

end.
