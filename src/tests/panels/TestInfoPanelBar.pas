unit TestInfoPanelBar;

{ Ctrl+L information panel: a line with a percentage (free / used disk
  space, memory load) shows a bar between the caption and the value, one
  blank cell away from each, filled in proportion to the percentage. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInfoPanelBar = class
  public
    [Test] procedure TestBarText;
    [Test] procedure TestPercentOfTotal;
    [Test] procedure TestMemoryLoadLine;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uThemeTypes, uDriveInfo, uDualPanelInfoPanel;

const
  cFull = #$2588;
  cEmpty = #$2591;

procedure TTestInfoPanelBar.TestBarText;
begin
  Assert.AreEqual(StringOfChar(cEmpty, 10), InfoPercentBar(0, 10), '0%');
  Assert.AreEqual(StringOfChar(cFull, 10), InfoPercentBar(100, 10), '100%');
  Assert.AreEqual(StringOfChar(cFull, 5) + StringOfChar(cEmpty, 5),
    InfoPercentBar(50, 10), '50%');
  Assert.AreEqual(StringOfChar(cFull, 1) + StringOfChar(cEmpty, 9),
    InfoPercentBar(9, 10), '9% rounds to one cell');
  Assert.AreEqual(StringOfChar(cFull, 10), InfoPercentBar(150, 10), 'clamped');
  Assert.AreEqual('', InfoPercentBar(50, 0), 'no room');
end;

procedure TTestInfoPanelBar.TestPercentOfTotal;
begin
  Assert.AreEqual(98, PercentOfTotal(1820, 1860), 'rounded');
  Assert.AreEqual(0, PercentOfTotal(0, 100), 'empty');
  Assert.AreEqual(-1, PercentOfTotal(5, 0), 'no total');
  Assert.AreEqual('98%, ', Copy(FormatPctSize(1820, 1860), 1, 5), 'same as the text');
end;

procedure TTestInfoPanelBar.TestMemoryLoadLine;
const
  W = 70;
  H = 40;
var
  Grid: TTerminalGrid;
  Y, X, KeyEnd, ValStart, BarStart, BarEnd: Integer;
  Line: string;
begin
  AllocTerminalGrid(Grid, W, H);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Navy, ' ');
  DrawPanelInfoContent(Grid, nil, TRectI.Make(0, 0, W - 1, H - 1),
    TAlphaColors.Silver, TAlphaColors.Navy, 'C:\', 0, 0, 0);
  for Y := 0 to H - 1 do
  begin
    Line := '';
    for X := 0 to W - 1 do
      Line := Line + Grid[Y][X].CharValue;
    if Pos('Memory load:', Line) <> 2 then
      Continue;
    KeyEnd := 1 + Length('Memory load:');            // last cell of the caption
    ValStart := Pos('%', Line);
    while (ValStart > 1) and CharInSet(Line[ValStart - 1], ['0'..'9']) do
      Dec(ValStart);
    BarStart := KeyEnd + 2;
    BarEnd := ValStart - 2;
    Assert.AreEqual(' ', Line[KeyEnd + 1], 'blank after the caption');
    Assert.AreEqual(' ', Line[ValStart - 1], 'blank before the value');
    Assert.IsTrue(BarEnd - BarStart + 1 >= 4, 'room for a bar');
    for X := BarStart to BarEnd do
      Assert.IsTrue((Line[X] = cFull) or (Line[X] = cEmpty),
        Format('bar cell %d is "%s"', [X, Line[X]]));
    Exit;
  end;
  Assert.Fail('no Memory load line');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInfoPanelBar);

end.
