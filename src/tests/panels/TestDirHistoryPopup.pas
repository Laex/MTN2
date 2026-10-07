unit TestDirHistoryPopup;

{ The Alt+Left/Right directory-history popup: its width follows the panel. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDirHistoryPopup = class
  public
    [Test] procedure WidthIsPanelLessThreeCellsEachSide;
    [Test] procedure NarrowPanelKeepsUsableWidth;
    [Test] procedure LongLabelIsShortenedToTheRow;
    [Test] procedure TextLeavesOneCellBeforeScrollBar;
  end;

implementation

uses
  System.SysUtils, uTerminalTypes, uThemeTypes, uDualPanelTypes, uDualPanelHistoryPopup;

function NewPopup(const APanel: TRectI): THistoryPopupController;
begin
  Result := THistoryPopupController.Create(nil, nil,
    function(ASide: TPanelSide): TRectI
    begin
      Result := APanel;
    end);
end;

function IsDrawn(const AGrid: TTerminalGrid; ARow, ACol: Integer): Boolean;
begin
  Result := AGrid[ARow][ACol].CharValue > ' ';
end;

function RowText(const AGrid: TTerminalGrid; ARow, AFrom, ATo: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := AFrom to ATo do
    Result := Result + AGrid[ARow][X].CharValue;
end;

procedure TTestDirHistoryPopup.WidthIsPanelLessThreeCellsEachSide;
var
  P: THistoryPopupController;
  Grid: TTerminalGrid;
  Y, Top: Integer;
begin
  P := NewPopup(TRectI.Make(0, 0, 59, 29));
  try
    AllocTerminalGrid(Grid, 60, 30);
    P.Show(psLeft, ['C:\one', 'C:\two'], 1);
    P.Draw(Grid);
    Top := -1;
    for Y := 0 to 29 do
      if IsDrawn(Grid, Y, 3) then
      begin
        Top := Y;
        Break;
      end;
    Assert.IsTrue(Top >= 0, 'the frame starts at column 3');
    Assert.IsFalse(IsDrawn(Grid, Top, 2));
    Assert.IsTrue(IsDrawn(Grid, Top, 56), 'and ends at column 56');
    Assert.IsFalse(IsDrawn(Grid, Top, 57));
  finally
    P.Free;
  end;
end;

procedure TTestDirHistoryPopup.NarrowPanelKeepsUsableWidth;
var
  P: THistoryPopupController;
  Grid: TTerminalGrid;
  X, Y, First, Last: Integer;
begin
  P := NewPopup(TRectI.Make(0, 0, 23, 29)); // 24 wide: 3 + 3 would leave 18
  try
    AllocTerminalGrid(Grid, 24, 30);
    P.Show(psLeft, ['C:\one'], 0);
    P.Draw(Grid);
    First := -1;
    Last := -1;
    for Y := 0 to 29 do
      if First < 0 then
        for X := 0 to 23 do
          if IsDrawn(Grid, Y, X) then
          begin
            if First < 0 then
              First := X;
            Last := X;
          end;
    Assert.IsTrue(Last - First + 1 >= 20, 'at least the minimum width is drawn');
  finally
    P.Free;
  end;
end;

procedure TTestDirHistoryPopup.LongLabelIsShortenedToTheRow;
var
  P: THistoryPopupController;
  Grid: TTerminalGrid;
  Y: Integer;
  Row: string;
  Found: Boolean;
begin
  P := NewPopup(TRectI.Make(0, 0, 39, 29));
  try
    AllocTerminalGrid(Grid, 40, 30);
    P.Show(psLeft, ['C:\very\long\folder\name\that\does\not\fit\anywhere\deep'], 0);
    P.Draw(Grid);
    Found := False;
    for Y := 0 to 29 do
    begin
      Row := RowText(Grid, Y, 4, 35);
      if Pos('...', Row) > 0 then
      begin
        Found := True;
        Assert.IsTrue(Pos('deep', Row) > 0, 'the end of the path stays');
        Assert.IsTrue(Pos('C:', Row) > 0, 'the drive stays');
      end;
    end;
    Assert.IsTrue(Found, 'the label is shortened with an ellipsis');
  finally
    P.Free;
  end;
end;

procedure TTestDirHistoryPopup.TextLeavesOneCellBeforeScrollBar;
var
  P: THistoryPopupController;
  Grid: TTerminalGrid;
  Y, Row: Integer;
begin
  P := NewPopup(TRectI.Make(0, 0, 39, 29));
  try
    AllocTerminalGrid(Grid, 40, 30);
    P.Show(psLeft, ['C:\very\long\folder\name\that\does\not\fit\anywhere\deep'], 0);
    P.Draw(Grid);
    Row := -1;
    for Y := 0 to 29 do
      if Pos('deep', RowText(Grid, Y, 3, 36)) > 0 then
        Row := Y;
    Assert.IsTrue(Row >= 0, 'the label is drawn');
    // The popup spans columns 3..36; its scroll bar column is 35.
    Assert.IsFalse(IsDrawn(Grid, Row, 34), 'a blank cell stays before the scroll bar');
    Assert.IsTrue(IsDrawn(Grid, Row, 33), 'the text ends right before it');
  finally
    P.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDirHistoryPopup);

end.
