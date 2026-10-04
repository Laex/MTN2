unit TestWindowChrome;

{ Window chrome in the character grid: window buttons, the [+] button, the
  window title and the drag zones of the menu and tab bar rows. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWindowChrome = class
  public
    [Test] procedure ButtonsFillTheRightEdge;
    [Test] procedure ButtonsNeedRoom;
    [Test] procedure MaximizeGlyphFollowsWindowState;
    [Test] procedure TitleIsCutWithAnEllipsis;
    [Test] procedure PlusFollowsTheLastTab;
    [Test] procedure ButtonsInTabRowMakeRoomForChips;
    [Test] procedure ChipsMoveLeftOfTheButtons;
    [Test] procedure FreeZoneSitsBetweenPlusAndChips;
    [Test] procedure PlusDisappearsWhenTabsFillTheRow;
    [Test] procedure MenuRowFreeZoneStopsAtTheButtons;
    [Test] procedure TitleNeverOverlapsOtherChrome;
    [Test] procedure TitleWithoutRoomIsNotDrawn;
    [Test] procedure TitleLosesPartsInOrder;
    [Test] procedure TitleSkipsEmptyParts;
    [Test] procedure TitleShowsAdministratorRights;
    [Test] procedure ClientSnapsToWholeCells;
    [Test] procedure FractionalCellsKeepEveryColumn;
    [Test] procedure ResizeKeepsTheEdgeNotDragged;
  end;

implementation

uses
  System.SysUtils, System.Types, System.Math,
  uDualPanelUiTypes,
  uDualPanelJobChips,
  uWindowChrome;

function BackgroundJob(AId: Integer): TPanelJobState;
begin
  Result := Default(TPanelJobState);
  Result.Id := AId;
  Result.Kind := pjkCopy;
  Result.Phase := pjpRunning;
  Result.Presentation := jpBackground;
  Result.FilesTotal := 10;
end;

function SampleTitle: TWindowTitleParts;
begin
  Result := Default(TWindowTitleParts);
  Result.FullName := 'Modern Terminal Navigator 2';
  Result.ShortName := 'MTN2';
  Result.Version := 'v0.3.10';
  Result.SizeText := '120x30';
  Result.ZoomText := 'zoom 100%';
  Result.TabText := '[Docs]';
  Result.FpsText := '60 fps';
end;

procedure TTestWindowChrome.ButtonsFillTheRightEdge;
var
  Button: TWindowButton;
begin
  Assert.AreEqual(71, WindowButtonsLeft(80), 'nine columns at the right edge');
  Assert.IsTrue(HitWindowButton(80, 71, Button) and (Button = wbMinimize), 'first column');
  Assert.IsTrue(HitWindowButton(80, 73, Button) and (Button = wbMinimize), 'third column');
  Assert.IsTrue(HitWindowButton(80, 74, Button) and (Button = wbMaximize), 'maximize');
  Assert.IsTrue(HitWindowButton(80, 79, Button) and (Button = wbClose), 'last column closes');
  Assert.IsFalse(HitWindowButton(80, 70, Button), 'left of the buttons');
  Assert.IsFalse(HitWindowButton(80, 80, Button), 'past the edge');
end;

procedure TTestWindowChrome.ButtonsNeedRoom;
var
  Button: TWindowButton;
begin
  Assert.AreEqual(-1, WindowButtonsLeft(cMinWidthForButtons - 1), 'too narrow');
  Assert.IsFalse(HitWindowButton(cMinWidthForButtons - 1, 25, Button), 'no hit when too narrow');
end;

procedure TTestWindowChrome.MaximizeGlyphFollowsWindowState;
begin
  Assert.IsTrue(WindowButtonCaption(wbMaximize, False) <> WindowButtonCaption(wbMaximize, True),
    'maximize and restore look different');
  Assert.AreEqual('[_]', WindowButtonCaption(wbMinimize, False));
  Assert.AreEqual('[x]', WindowButtonCaption(wbClose, True));
  Assert.AreEqual(cWindowButtonsWidth, Length(WindowButtonCaption(wbMinimize, False)) * 3,
    'three three-column buttons');
end;

procedure TTestWindowChrome.TitleIsCutWithAnEllipsis;
begin
  Assert.AreEqual('MTN2', FitTitle('MTN2', 10), 'fits as is');
  Assert.AreEqual('MTN2 - ' + #$2026, FitTitle('MTN2 - v0.3.10', 8), 'cut to the room');
  Assert.AreEqual(8, Integer(Length(FitTitle('MTN2 - v0.3.10', 8))), 'exactly the room');
  Assert.AreEqual(#$2026, FitTitle('MTN2', 1), 'one column left');
  Assert.AreEqual('', FitTitle('MTN2', 0), 'no room');
end;

procedure TTestWindowChrome.PlusFollowsTheLastTab;
var
  Chrome: TTabBarChrome;
begin
  Chrome := LayoutTabBarChrome(7, 80, False, nil);
  Assert.AreEqual(7, Chrome.PlusLeft, 'right after the last tab and its gap');
  Assert.IsTrue(HitPlusButton(Chrome, 7) and HitPlusButton(Chrome, 9), 'three columns');
  Assert.IsFalse(HitPlusButton(Chrome, 6) or HitPlusButton(Chrome, 10), 'edges');
  Assert.AreEqual(11, Chrome.FreeLeft, 'free part starts after a gap');
  Assert.AreEqual(80, Chrome.FreeRight, 'and runs to the right edge');
end;

procedure TTestWindowChrome.ButtonsInTabRowMakeRoomForChips;
var
  Chrome: TTabBarChrome;
begin
  Chrome := LayoutTabBarChrome(7, 80, True, nil);
  Assert.AreEqual(70, Chrome.FreeRight, 'a gap column before the window buttons');
  Chrome := LayoutTabBarChrome(7, 80, False, nil);
  Assert.AreEqual(80, Chrome.FreeRight, 'no buttons in this row');
end;

procedure TTestWindowChrome.ChipsMoveLeftOfTheButtons;
var
  Chrome: TTabBarChrome;
begin
  Chrome := LayoutTabBarChrome(7, 80, True, [BackgroundJob(1)]);
  Assert.IsTrue(Chrome.Strip.ListWidth > 0, 'strip is shown');
  Assert.AreEqual(70, Chrome.Strip.ListLeft + Chrome.Strip.ListWidth,
    'the list button ends before the window buttons and their gap');
  Chrome := LayoutTabBarChrome(7, 80, False, [BackgroundJob(1)]);
  Assert.AreEqual(80, Chrome.Strip.ListLeft + Chrome.Strip.ListWidth,
    'without buttons the strip reaches the right edge');
end;

procedure TTestWindowChrome.FreeZoneSitsBetweenPlusAndChips;
var
  Chrome: TTabBarChrome;
begin
  Chrome := LayoutTabBarChrome(7, 80, False, [BackgroundJob(1)]);
  Assert.IsTrue(InTabBarFreeZone(Chrome, Chrome.FreeLeft), 'first free column');
  Assert.IsFalse(InTabBarFreeZone(Chrome, Chrome.PlusLeft), 'the [+] is not a drag zone');
  Assert.IsFalse(InTabBarFreeZone(Chrome, Chrome.Strip.Chips[0].Left), 'a chip is not a drag zone');
  Assert.IsFalse(InTabBarFreeZone(Chrome, 3), 'a tab is not a drag zone');
  Assert.AreEqual(Chrome.Strip.Chips[0].Left - 1, Chrome.FreeRight,
    'the zone stops one column before the chips');
end;

procedure TTestWindowChrome.PlusDisappearsWhenTabsFillTheRow;
var
  Chrome: TTabBarChrome;
begin
  Chrome := LayoutTabBarChrome(78, 80, False, nil);
  Assert.AreEqual(-1, Chrome.PlusLeft, 'no room for [+]');
  Assert.IsFalse(HitPlusButton(Chrome, 78), 'and nothing to click');
  Chrome := LayoutTabBarChrome(75, 80, True, nil);
  Assert.AreEqual(-1, Chrome.PlusLeft, 'the window buttons come first');
end;

procedure TTestWindowChrome.MenuRowFreeZoneStopsAtTheButtons;
begin
  Assert.IsFalse(InMenuBarFreeZone(40, 80, 39), 'a menu title');
  Assert.IsTrue(InMenuBarFreeZone(40, 80, 40), 'right of the titles');
  Assert.IsTrue(InMenuBarFreeZone(40, 80, 70), 'up to the buttons');
  Assert.IsFalse(InMenuBarFreeZone(40, 80, 71), 'a window button');
end;

procedure TTestWindowChrome.TitleNeverOverlapsOtherChrome;
var
  W, TabsEnd, Room, TitleEnd, ButtonsLeft, I, Variant: Integer;
  Chrome: TTabBarChrome;
  Jobs: TArray<TPanelJobState>;
  InRow: Boolean;
  Title: string;
begin
  for W := cMinWidthForButtons to 140 do
    for TabsEnd in [7, 20, 45, W - 8] do
      for Variant := 0 to 3 do
      begin
        InRow := Odd(Variant);
        Jobs := nil;
        if Variant >= 2 then
          Jobs := [BackgroundJob(1), BackgroundJob(2)];
        Chrome := LayoutTabBarChrome(TabsEnd, W, InRow, Jobs);
        Room := Chrome.FreeRight - Chrome.FreeLeft;
        if Room < cMinTitleWidth then
          Continue;
        Title := ComposeTitle(SampleTitle, Room);
        Assert.IsTrue(Length(Title) <= Room,
          Format('title fits the free room (w=%d tabs=%d variant=%d)', [W, TabsEnd, Variant]));
        Assert.IsTrue((Pos('MTN2', Title) = 1) or (Pos('Modern Terminal Navigator 2 - MTN2', Title) = 1),
          'the short name always stays, the full one only when it all fits');
        TitleEnd := Chrome.FreeLeft + Length(Title);
        Assert.IsTrue(Chrome.FreeLeft >= TabsEnd, 'title starts after the tabs');
        Assert.IsTrue((Chrome.PlusLeft < 0) or (Chrome.FreeLeft > Chrome.PlusLeft + Length(cPlusCaption)),
          'title starts after [+]');
        for I := 0 to High(Chrome.Strip.Chips) do
          Assert.IsTrue(TitleEnd < Chrome.Strip.Chips[I].Left,
            Format('title ends before a chip (w=%d tabs=%d variant=%d)', [W, TabsEnd, Variant]));
        if Chrome.Strip.ListWidth > 0 then
          Assert.IsTrue(TitleEnd < Chrome.Strip.ListLeft, 'title ends before the list button');
        if InRow then
        begin
          ButtonsLeft := WindowButtonsLeft(W);
          Assert.IsTrue(TitleEnd < ButtonsLeft, 'title ends before the window buttons');
        end;
        Assert.IsTrue(TitleEnd <= W, 'title stays inside the row');
      end;
end;

procedure TTestWindowChrome.TitleWithoutRoomIsNotDrawn;
var
  Chrome: TTabBarChrome;
begin
  // Tabs, [+] and the window buttons leave less than the minimum for a title.
  Chrome := LayoutTabBarChrome(64, 80, True, nil);
  Assert.IsTrue(Chrome.FreeRight - Chrome.FreeLeft < cMinTitleWidth,
    'no room: ' + IntToStr(Chrome.FreeRight - Chrome.FreeLeft));
end;

procedure TTestWindowChrome.TitleLosesPartsInOrder;
const
  cFull = 'Modern Terminal Navigator 2 - MTN2 v0.3.10  [120x30  zoom 100%  [Docs]]  [60 fps]';
var
  P: TWindowTitleParts;
begin
  P := SampleTitle;
  Assert.AreEqual(cFull, ComposeTitle(P, 200), 'everything when there is room');
  Assert.AreEqual(cFull, ComposeTitle(P, Length(cFull)), 'exactly the room');
  Assert.AreEqual('MTN2 v0.3.10  [120x30  zoom 100%  [Docs]]  [60 fps]',
    ComposeTitle(P, Length(cFull) - 1), 'the full program name goes first');
  Assert.AreEqual('MTN2 v0.3.10  [120x30  zoom 100%]  [60 fps]',
    ComposeTitle(P, 46), 'then the tab name');
  Assert.AreEqual('MTN2 v0.3.10  [120x30]  [60 fps]', ComposeTitle(P, 33), 'then the zoom');
  Assert.AreEqual('MTN2 v0.3.10  [60 fps]', ComposeTitle(P, 22), 'then the window size');
  Assert.AreEqual('MTN2  [60 fps]', ComposeTitle(P, 14), 'then the version');
  Assert.AreEqual('MTN2', ComposeTitle(P, 13), 'then the frame rate');
  Assert.AreEqual('MTN2', ComposeTitle(P, 4), 'the short name stays');
  Assert.AreEqual('MT' + #$2026, ComposeTitle(P, 3), 'and is cut only below that');
end;

procedure TTestWindowChrome.TitleShowsAdministratorRights;
var
  P: TWindowTitleParts;
begin
  P := SampleTitle;
  P.RightsText := 'Administrator';
  Assert.AreEqual('Modern Terminal Navigator 2 - MTN2 v0.3.10  ' +
    '[120x30  zoom 100%  [Docs]]  [Administrator]  [60 fps]', ComposeTitle(P, 200),
    'the rights come before the frame rate');
  P.FpsText := '';
  Assert.AreEqual('MTN2 v0.3.10  [Administrator]', ComposeTitle(P, 30),
    'the rights stay when the size, zoom and tab name are dropped');
  P.RightsText := '';
  Assert.AreEqual('MTN2 v0.3.10  [120x30]', ComposeTitle(P, 30), 'nothing for an ordinary user');
end;

procedure TTestWindowChrome.TitleSkipsEmptyParts;
var
  P: TWindowTitleParts;
begin
  P := Default(TWindowTitleParts);
  P.FullName := 'Modern Terminal Navigator 2';
  P.ShortName := 'MTN2';
  P.Version := 'v0.3.10';
  Assert.AreEqual('Modern Terminal Navigator 2 - MTN2 v0.3.10', ComposeTitle(P, 100),
    'no brackets without size, zoom or tab');
  Assert.AreEqual('MTN2 v0.3.10', ComposeTitle(P, 30), 'without the full name');
end;

procedure TTestWindowChrome.ClientSnapsToWholeCells;
begin
  Assert.AreEqual(504, GridClientExtent(500, 9, 40, True), 'nearest: 56 cells');
  Assert.AreEqual(495, GridClientExtent(500, 9, 40, False), 'largest that fits: 55 cells');
  Assert.AreEqual(360, GridClientExtent(100, 9, 40, True), 'not below the minimum');
  Assert.AreEqual(360, GridClientExtent(100, 9, 40, False), 'not below the minimum either');
  Assert.AreEqual(500, GridClientExtent(500, 0, 40, True), 'unknown cell size: unchanged');
end;

procedure TTestWindowChrome.FractionalCellsKeepEveryColumn;
var
  Px: Integer;
  Nearest: Boolean;
begin
  // The grid holds Trunc(width / cell) columns, so a snapped width must not
  // fall a hair short of the cell boundary.
  for Nearest in [True, False] do
    for Px := 300 to 1200 do
    begin
      Assert.AreEqual(Trunc(GridClientExtent(Px, 8.6, 10, Nearest) / 8.6 + 0.00001),
        Round(GridClientExtent(Px, 8.6, 10, Nearest) / 8.6),
        'snapped width is a whole number of 8.6 px cells: ' + IntToStr(Px));
    end;
end;

procedure TTestWindowChrome.ResizeKeepsTheEdgeNotDragged;
var
  R: TRect;
begin
  // Client 494 x 400 (a frame of 16 x 39): 55 cells of 9 px, 22 of 18 px.
  R := TRect.Create(100, 100, 610, 539);
  SnapSizingRect(cSizingRight, R, 16, 39, 9, 18);
  Assert.AreEqual(100, R.Left, 'left edge stays');
  Assert.AreEqual(100 + 495 + 16, R.Right, 'right edge snaps to whole cells');
  Assert.AreEqual(539, R.Bottom, 'vertical size is not touched by a horizontal drag');

  R := TRect.Create(100, 100, 610, 539);
  SnapSizingRect(cSizingLeft, R, 16, 39, 9, 18);
  Assert.AreEqual(610, R.Right, 'right edge stays');
  Assert.AreEqual(610 - 495 - 16, R.Left, 'the dragged left edge snaps');

  R := TRect.Create(100, 100, 610, 539);
  SnapSizingRect(cSizingTopLeft, R, 16, 39, 9, 18);
  Assert.AreEqual(539, R.Bottom, 'bottom edge stays');
  Assert.AreEqual(610, R.Right, 'right edge stays');
  Assert.AreEqual(0, (539 - R.Top - 39) mod 18, 'height is whole rows');
  Assert.AreEqual(0, (610 - R.Left - 16) mod 9, 'width is whole columns');

  R := TRect.Create(100, 100, 610, 539);
  SnapSizingRect(cSizingBottom, R, 16, 39, 9, 18);
  Assert.AreEqual(610, R.Right, 'width is not touched by a vertical drag');
  Assert.AreEqual(0, (R.Bottom - 100 - 39) mod 18, 'height is whole rows');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWindowChrome);

end.
