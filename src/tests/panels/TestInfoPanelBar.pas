unit TestInfoPanelBar;

{ Ctrl+L information panel: a line with a usage percentage (used disk
  space, memory load) shows a bar between the caption and the value, one
  blank cell away from each, filled in proportion to the percentage; all
  such bars start in one column and have one width. }

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
  cEmpty = #$2592;

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
  Y, X, Found: Integer;
  Line: string;
  First, Last: array[0..1] of Integer;

  function IsBar(ACh: Char): Boolean;
  begin
    Result := (ACh = cFull) or (ACh = cEmpty);
  end;

  procedure CheckLine(AIndex: Integer; const ACaption: string);
  var
    I: Integer;
  begin
    First[AIndex] := 0;
    Last[AIndex] := 0;
    for I := 1 to Length(Line) do
      if IsBar(Line[I]) then
      begin
        if First[AIndex] = 0 then
          First[AIndex] := I;
        Last[AIndex] := I;
      end;
    Assert.IsTrue(First[AIndex] > Length(ACaption) + 2, ACaption + ' bar after the caption');
    Assert.AreEqual(' ', Line[First[AIndex] - 1], ACaption + ' blank before the bar');
    Assert.AreEqual(' ', Line[Last[AIndex] + 1], ACaption + ' blank after the bar');
    for I := First[AIndex] to Last[AIndex] do
      Assert.IsTrue(IsBar(Line[I]), ACaption + ' bar is one piece');
    Assert.IsTrue(Pos('%', Copy(Line, Last[AIndex] + 1, MaxInt)) > 0,
      ACaption + ' value after the bar');
  end;

begin
  AllocTerminalGrid(Grid, W, H);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Navy, ' ');
  DrawPanelInfoContent(Grid, nil, TRectI.Make(0, 0, W - 1, H - 1),
    TAlphaColors.Silver, TAlphaColors.Navy, 'C:', 0, 0, 0);
  Found := 0;
  for Y := 0 to H - 1 do
  begin
    Line := '';
    for X := 0 to W - 1 do
      Line := Line + Grid[Y][X].CharValue;
    // Disk figures come from a background refresh and may not be there
    // yet: the used line has a bar only once it shows a percentage.
    if (Pos('Space, used:', Line) = 2) and (Pos('%', Line) > 0) then
    begin
      CheckLine(0, 'Space, used:');
      Inc(Found);
    end
    else if Pos('Memory load:', Line) = 2 then
    begin
      CheckLine(1, 'Memory load:');
      Inc(Found, 2);
    end;
  end;
  Assert.IsTrue(Found >= 2, 'memory load line with a bar');
  Assert.IsTrue(Last[1] - First[1] + 1 >= 4, 'room for a bar');
  if Found = 3 then
  begin
    Assert.AreEqual(First[0], First[1], 'bars start in one column');
    Assert.AreEqual(Last[0], Last[1], 'bars have one width');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInfoPanelBar);

end.
