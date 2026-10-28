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
    [Test] procedure CheckedRadioOfAGroupIsEmittedOnce;
    [Test] procedure ListMirrorOverridesSelectedIndex;
  end;

  [TestFixture]
  TTestDialogV2Layout = class
  public
    [Test] procedure FocusChangeScrollsAndSameFocusKeepsTheWheel;
    [Test] procedure ListAndRadioGroupAreCutAndOtherControlsDrop;
  end;

  [TestFixture]
  TTestDialogListDraw = class
  public
    [Test] procedure SingleRowShowsSelectionAndArrow;
    [Test] procedure MultiRowReservesTheRightColumn;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uDialogTypes, uDialogValues, uDialogV2Layout, uDialogListDraw, uDialogHost,
  uTerminalTypes, uThemeTypes;

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

end.
