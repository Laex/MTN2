unit TestDialogScroll;

{ A dialog taller than the window scrolls with the focus: the controls that are
  out of view are neither drawn nor hit, a bar on the right border shows the
  position, and a dialog that fits has no bar. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogScroll = class
  public
    [Test] procedure TestTallDialogShowsABarAndHidesFarControls;
    [Test] procedure TestFocusingAFarControlScrollsItIntoView;
    [Test] procedure TestTabReachesTheLastButton;
    [Test] procedure TestDialogThatFitsHasNoBar;
    [Test] procedure TestReopenedListKeepsItsScrollPosition;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uTerminalTypes, uThemeTypes, uDialogHost;

function DialogJson: string;
var
  I: Integer;
begin
  Result := '{"type":"dialog","version":"2.0","title":"t","width":40,"height":40,"children":[';
  for I := 0 to 9 do
    Result := Result + Format(
      '{"type":"checkbox","id":"c%d","text":"option %d","checked":false,"col":1,"row":%d,"width":20,"height":1},',
      [I, I, 1 + I * 3]);
  Result := Result +
    '{"type":"button","id":"ok","text":"OK","default":true,"col":10,"row":34,"width":8,"height":1}]}';
end;

function OpenHost: TDialogHost;
begin
  Result := TDialogHost.Create(nil);
  Assert.IsTrue(Result.OpenJson(DialogJson, nil), 'dialog opens');
end;

procedure DrawIn(AHost: TDialogHost; AAreaH: Integer; var AGrid: TTerminalGrid);
var
  Y, X: Integer;
begin
  SetLength(AGrid, AAreaH);
  for Y := 0 to AAreaH - 1 do
  begin
    SetLength(AGrid[Y], 80);
    for X := 0 to 79 do
      AGrid[Y][X] := TCharCell.Make(' ', 0, 0);
  end;
  AHost.Draw(AGrid, 80, AAreaH);
end;

function InView(AHost: TDialogHost; const AId: string): Boolean;
var
  I, Found: Integer;
  R: TRectI;
begin
  Found := -1;
  for I := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(I).Id = AId then
      Found := I;
  Assert.IsTrue(Found >= 0, 'control ' + AId + ' exists');
  R := AHost.ControlBoundsAt(Found);
  Result := (R.Bottom >= R.Top) and (R.Top > AHost.Bounds.Top) and
    (R.Bottom < AHost.Bounds.Bottom);
end;

procedure TTestDialogScroll.TestTallDialogShowsABarAndHidesFarControls;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, 16, Grid);
    Assert.IsTrue(InView(Host, 'c0'), 'the first control is shown');
    Assert.IsFalse(InView(Host, 'c9'), 'a control far down is not shown');
    Assert.IsFalse(InView(Host, 'ok'), 'the button is not shown');
    Assert.AreEqual<Integer>(Ord(#$25B2),
      Ord(Grid[Host.Bounds.Top + 1][Host.Bounds.Right].CharValue), 'up mark of the bar');
    Assert.AreEqual<Integer>(Ord(#$25BC),
      Ord(Grid[Host.Bounds.Bottom - 1][Host.Bounds.Right].CharValue), 'down mark of the bar');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogScroll.TestFocusingAFarControlScrollsItIntoView;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, 16, Grid);
    Host.FocusControlById('ok');
    DrawIn(Host, 16, Grid);
    Assert.IsTrue(InView(Host, 'ok'), 'the focused button is brought into view');
    Assert.IsFalse(InView(Host, 'c0'), 'the top scrolled away');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogScroll.TestTabReachesTheLastButton;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  I: Integer;
  K: Word;
  Ch: Char;
begin
  Host := OpenHost;
  try
    for I := 1 to 10 do
    begin
      DrawIn(Host, 16, Grid);
      K := vkTab;
      Ch := #0;
      Host.HandleInput(K, [], Ch);
    end;
    DrawIn(Host, 16, Grid);
    Assert.IsTrue(InView(Host, 'ok'), 'ten Tabs from the first option land on the button');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogScroll.TestDialogThatFitsHasNoBar;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, 44, Grid);
    Assert.IsTrue(InView(Host, 'ok'), 'everything is shown when the window is tall enough');
    Assert.AreNotEqual<Integer>(Ord(#$25B2),
      Ord(Grid[Host.Bounds.Top + 1][Host.Bounds.Right].CharValue), 'no bar');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogScroll.TestReopenedListKeepsItsScrollPosition;
var
  Host: TDialogHost;
  Json: string;
  Grid: TTerminalGrid;
  I, Top: Integer;
begin
  Json := '{"type":"dialog","version":"2.0","title":"t","width":40,"height":12,"children":[' +
    '{"type":"list","id":"l","selected":3,"items":[';
  for I := 0 to 29 do
  begin
    if I > 0 then
      Json := Json + ',';
    Json := Json + Format('"item %d"', [I]);
  end;
  Json := Json + '],"col":1,"row":0,"width":36,"height":7}]}';
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(Json, nil));
    DrawIn(Host, 24, Grid);
    Assert.IsTrue(Host.GetListScrollTop = 0, 'the selected row near the top: no scroll');
    Host.SetListScrollTop(12);
    DrawIn(Host, 24, Grid);
    Top := Host.GetListScrollTop;
    Assert.IsTrue(Top >= 3, 'the selected row stays in view: ' + IntToStr(Top));
    Assert.IsTrue(Top <= 3, 'the list is not scrolled past the selected row');
    // A rebuilt dialog starts at the top; the restored position holds.
    Host.Close;
    Assert.IsTrue(Host.OpenJson(Json.Replace('"selected":3', '"selected":10'), nil));
    Host.SetListScrollTop(5);
    DrawIn(Host, 24, Grid);
    Assert.IsTrue(Host.GetListScrollTop = 5, 'a position that keeps the selection in view is kept');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogScroll);

end.
