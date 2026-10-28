unit TestMenuScroll;

{ A menu taller than the window scrolls: the selection stays in view, the
  marks on the right border show that more items are hidden, and the mouse and
  the wheel work on the items that are shown. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMenuScroll = class
  public
    [Test] procedure TestTallSubmenuIsCutAndMarked;
    [Test] procedure TestBorderMarksShowHiddenItems;
    [Test] procedure TestSelectionStaysInView;
    [Test] procedure TestMouseHitsTheItemThatIsShown;
    [Test] procedure TestWheelMovesTheSelection;
    [Test] procedure TestShortSubmenuHasNoMarks;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uTerminalTypes, uThemeRegistry, uTopMenuBar;

function MenuJson(ACount: Integer): string;
var
  I: Integer;
begin
  Result := '{"categories":[{"title":"X","hotChar":"X","items":[';
  for I := 1 to ACount do
  begin
    if I > 1 then
      Result := Result + ',';
    Result := Result + Format('{"caption":"Item %.2d","action":"tmaFileCopy"}', [I]);
  end;
  Result := Result + ']}]}';
end;

function MakeMenu(ACount: Integer): TTopMenuController;
begin
  Result := TTopMenuController.Create(CreateThemeByName('NDN'), nil, nil);
  Assert.IsTrue(Result.LoadMenuFromJson(MenuJson(ACount)), 'menu JSON parses');
  Result.ActivateMenu(0, True);
end;

procedure DrawFresh(AMenu: TTopMenuController; var AGrid: TTerminalGrid;
  ARows, ACols: Integer);
var
  Y, X: Integer;
begin
  SetLength(AGrid, ARows);
  for Y := 0 to ARows - 1 do
  begin
    SetLength(AGrid[Y], ACols);
    for X := 0 to ACols - 1 do
      AGrid[Y][X] := TCharCell.Make(' ', 0, 0);
  end;
  AMenu.DrawSubmenu(AGrid, ACols);
end;

function RowText(const AGrid: TTerminalGrid; ARow: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to High(AGrid[ARow]) do
    Result := Result + AGrid[ARow][X].CharValue;
end;

function RowOfText(const AGrid: TTerminalGrid; const AText: string): Integer;
var
  Y: Integer;
begin
  for Y := 0 to High(AGrid) do
    if Pos(AText, RowText(AGrid, Y)) > 0 then
      Exit(Y);
  Result := -1;
end;

procedure Press(AMenu: TTopMenuController; AKey: Word; ATimes: Integer = 1);
var
  I: Integer;
  K: Word;
  Ch: Char;
begin
  for I := 1 to ATimes do
  begin
    K := AKey;
    Ch := #0;
    AMenu.HandleInput(K, [], Ch);
  end;
end;

procedure TTestMenuScroll.TestTallSubmenuIsCutAndMarked;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
begin
  C := MakeMenu(30);
  try
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(RowOfText(Grid, 'Item 01') = 2, 'the first item is on the first row');
    Assert.IsTrue(RowOfText(Grid, 'Item 08') = 9, 'the box ends above the function bar row');
    Assert.IsTrue(RowOfText(Grid, 'Item 09') < 0, 'the rest is not drawn');
    Assert.IsTrue(Pos(#$25BC, RowText(Grid, 9)) > 0, 'a down mark says there is more');
    Assert.IsTrue(Pos(#$25B2, RowText(Grid, 2)) > 0, 'the bar starts at the first item row');
  finally
    C.Free;
  end;
end;

procedure TTestMenuScroll.TestBorderMarksShowHiddenItems;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
begin
  C := MakeMenu(30);
  try
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(Pos(#$25BC, RowText(Grid, 10)) > 0, 'a mark on the bottom border: more below');
    Assert.IsTrue(Pos(#$25B2, RowText(Grid, 1)) = 0, 'no mark on the top border at the start');
    Press(C, vkDown, 20);
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(Pos(#$25B2, RowText(Grid, 1)) > 0, 'a mark on the top border: more above');
    Assert.IsTrue(Pos(#$25BC, RowText(Grid, 10)) > 0, 'still more below');
    Press(C, vkEnd);
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(Pos(#$25BC, RowText(Grid, 10)) = 0, 'no mark on the bottom border at the end');
  finally
    C.Free;
  end;
end;

procedure TTestMenuScroll.TestSelectionStaysInView;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
begin
  C := MakeMenu(30);
  try
    DrawFresh(C, Grid, 12, 60);
    Press(C, vkDown, 20);
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(RowOfText(Grid, 'Item 21') = 9, 'the selected item is the last row shown');
    Assert.IsTrue(RowOfText(Grid, 'Item 01') < 0, 'the top scrolled away');
    Press(C, vkEnd);
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(RowOfText(Grid, 'Item 30') = 9, 'End shows the last item');
    Press(C, vkHome);
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(RowOfText(Grid, 'Item 01') = 2, 'Home returns to the first item');
  finally
    C.Free;
  end;
end;

procedure TTestMenuScroll.TestMouseHitsTheItemThatIsShown;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
  Row: Integer;
begin
  C := MakeMenu(30);
  try
    DrawFresh(C, Grid, 12, 60);
    Press(C, vkDown, 20);
    DrawFresh(C, Grid, 12, 60);
    Row := RowOfText(Grid, 'Item 18');
    Assert.IsTrue(Row > 0, 'Item 18 is shown');
    C.HandleClick(8, Row);
    Assert.AreEqual<Integer>(17, C.SubmenuIndex, 'a click selects the item under the pointer');
  finally
    C.Free;
  end;
end;

procedure TTestMenuScroll.TestWheelMovesTheSelection;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
begin
  C := MakeMenu(30);
  try
    DrawFresh(C, Grid, 12, 60);
    Assert.IsTrue(C.HandleMouseWheel(-120), 'an open submenu takes the wheel');
    Assert.AreEqual<Integer>(3, C.SubmenuIndex, 'down by three items');
    C.HandleMouseWheel(120);
    C.HandleMouseWheel(120);
    Assert.AreEqual<Integer>(0, C.SubmenuIndex, 'up stops at the first item');
    C.DeactivateMenu;
    Assert.IsFalse(C.HandleMouseWheel(-120), 'a closed menu leaves the wheel alone');
  finally
    C.Free;
  end;
end;

procedure TTestMenuScroll.TestShortSubmenuHasNoMarks;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
  Y: Integer;
begin
  C := MakeMenu(5);
  try
    DrawFresh(C, Grid, 12, 60);
    for Y := 0 to High(Grid) do
      Assert.IsTrue((Pos(#$25B2, RowText(Grid, Y)) = 0) and (Pos(#$25BC, RowText(Grid, Y)) = 0),
        'no scroll marks when every item fits');
  finally
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMenuScroll);

end.
