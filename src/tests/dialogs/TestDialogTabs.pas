unit TestDialogTabs;

{ A dialog with a tab strip shows the controls of one page at a time: the other
  pages have no box and no focus, Ctrl+PgUp / Ctrl+PgDn / Ctrl+Tab and a click
  turn the pages, and the Interface and Markdown colors dialogs fit an 80x24 screen. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogTabs = class
  private
    procedure CheckFitsEightyByTwentyFour(const AResource: string);
  public
    [Test] procedure TestControlsOfOtherPagesHaveNoBox;
    [Test] procedure TestHiddenPagesDoNotCountForScrolling;
    [Test] procedure TestJsonRoundTripKeepsPages;
    [Test] procedure TestTabKeyStaysOnTheShownPage;
    [Test] procedure TestCtrlPageKeysTurnPagesAndWrap;
    [Test] procedure TestCtrlTabTurnsPages;
    [Test] procedure TestArrowsOnFocusedStripTurnPages;
    [Test] procedure TestFocusLeavesAPageThatGoesAway;
    [Test] procedure TestClickOnCaptionSelectsPage;
    [Test] procedure TestMnemonicOfAnotherPageOpensIt;
    [Test] procedure TestFocusByIdOpensItsPage;
    [Test] procedure TestStripDrawsMarkedCaption;
    [Test] procedure TestRuleOpensUnderTheShownTab;
    [Test] procedure TestEveryDialogFitsEightyColumns;
    [Test] procedure TestInterfaceDialogFitsEightyByTwentyFour;
    [Test] procedure TestMarkdownColorsDialogFitsEightyByTwentyFour;
    [Test] procedure TestSearchDialogFitsEightyByTwentyFour;
    [Test] procedure TestSetAttributesDialogFitsEightyByTwentyFour;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, uTerminalTypes, uThemeTypes, uDialogTypes,
  uDialogJson, uDialogJsonSerialize, uDialogTabs, uDialogV2Layout, uDialogHost,
  uDialogResources, uStrings, System.IOUtils;

const
  cTabsJson =
    '{"type":"dialog","version":"2.0","title":"t","width":50,"height":14,"children":[' +
    '{"type":"tabs","id":"tabs","items":["One","Two","Three"],"col":1,"row":0,"width":40,"height":1},' +
    '{"type":"checkbox","id":"a1","text":"&Alpha","col":1,"row":2,"width":20,"height":1,"tab":0},' +
    '{"type":"checkbox","id":"a2","text":"A&nother","col":1,"row":3,"width":20,"height":1,"tab":0},' +
    '{"type":"checkbox","id":"b1","text":"&Beta","col":1,"row":2,"width":20,"height":1,"tab":1},' +
    '{"type":"checkbox","id":"c1","text":"&Gamma","col":1,"row":2,"width":20,"height":1,"tab":2},' +
    '{"type":"button","id":"ok","text":"OK","default":true,"col":10,"row":11,"width":8,"height":1}]}';

function OpenHost: TDialogHost;
begin
  Result := TDialogHost.Create(nil);
  Assert.IsTrue(Result.OpenJson(cTabsJson, nil), 'dialog opens');
end;

procedure DrawIn(AHost: TDialogHost; var AGrid: TTerminalGrid);
var
  Y, X: Integer;
begin
  SetLength(AGrid, 24);
  for Y := 0 to 23 do
  begin
    SetLength(AGrid[Y], 80);
    for X := 0 to 79 do
      AGrid[Y][X] := TCharCell.Make(' ', 0, 0);
  end;
  AHost.Draw(AGrid, 80, 24);
end;

function IndexOf(AHost: TDialogHost; const AId: string): Integer;
begin
  for Result := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(Result).Id = AId then
      Exit;
  Result := -1;
  Assert.Fail('control ' + AId + ' exists');
end;

function IsShown(AHost: TDialogHost; const AId: string): Boolean;
var
  R: TRectI;
begin
  R := AHost.ControlBoundsAt(IndexOf(AHost, AId));
  Result := (R.Right >= R.Left) and (R.Left >= 0);
end;

function ActivePage(AHost: TDialogHost): Integer;
var
  I: Integer;
  Controls: TArray<TDialogControl>;
begin
  SetLength(Controls, AHost.ControlCount);
  for I := 0 to High(Controls) do
    Controls[I] := AHost.GetControl(I);
  Result := DialogActiveTabPage(Controls) - 1;
end;

procedure Press(AHost: TDialogHost; AKey: Word; AShift: TShiftState);
var
  Ch: Char;
begin
  Ch := #0;
  Assert.IsTrue(AHost.HandleInput(AKey, AShift, Ch), 'key is taken');
end;

procedure TTestDialogTabs.TestControlsOfOtherPagesHaveNoBox;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Assert.IsTrue(IsShown(Host, 'tabs'), 'strip');
    Assert.IsTrue(IsShown(Host, 'a1'), 'first page control');
    Assert.IsTrue(IsShown(Host, 'ok'), 'control on every page');
    Assert.IsFalse(IsShown(Host, 'b1'), 'second page control');
    Assert.IsFalse(IsShown(Host, 'c1'), 'third page control');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestHiddenPagesDoNotCountForScrolling;
var
  Decl: TDialogDeclaration;
  L: TDialogV2Layout;
  Frame: TRectI;
begin
  Assert.IsTrue(TryParseDialogJson(
    '{"type":"dialog","version":"2.0","title":"t","width":30,"height":8,"children":[' +
    '{"type":"tabs","id":"t","items":["A","B"],"col":0,"row":0,"width":20,"height":1},' +
    '{"type":"checkbox","id":"x","text":"x","col":0,"row":1,"width":10,"height":1,"tab":0},' +
    '{"type":"checkbox","id":"y","text":"y","col":0,"row":40,"width":10,"height":1,"tab":1}]}',
    Decl), 'parses');
  Frame := TRectI.Make(0, 0, 29, 7);
  L := LayoutDialogV2(Decl.Controls, Frame, 0, 0, -1);
  Assert.AreEqual(2, L.ContentH, 'only the shown page and the strip count');
  Decl.Controls[0].SelectedIndex := 1;
  L := LayoutDialogV2(Decl.Controls, Frame, 0, 0, -1);
  Assert.AreEqual(41, L.ContentH, 'the second page is tall');
  Assert.IsTrue(L.Bounds[1].Right < L.Bounds[1].Left, 'first page control has no box');
end;

procedure TTestDialogTabs.TestJsonRoundTripKeepsPages;
var
  Decl, Back: TDialogDeclaration;
begin
  Assert.IsTrue(TryParseDialogJson(cTabsJson, Decl), 'parses');
  Assert.AreEqual<Integer>(Ord(dckTab), Ord(Decl.Controls[0].Kind), 'strip kind');
  Assert.AreEqual<Integer>(3, Length(Decl.Controls[0].Items), 'captions');
  Assert.AreEqual(1, Decl.Controls[1].TabPage, 'first page is 1');
  Assert.AreEqual(3, Decl.Controls[4].TabPage, 'third page is 3');
  Assert.AreEqual(0, Decl.Controls[5].TabPage, 'no tab = every page');
  Assert.IsTrue(TryParseDialogJson(DeclarationToJson(Decl), Back), 'reparses');
  Assert.AreEqual<Integer>(Length(Decl.Controls), Length(Back.Controls), 'same count');
  Assert.AreEqual(Decl.Controls[3].TabPage, Back.Controls[3].TabPage, 'page kept');
  Assert.AreEqual(Decl.Controls[0].Items[2], Back.Controls[0].Items[2], 'caption kept');
end;

procedure TTestDialogTabs.TestTabKeyStaysOnTheShownPage;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  I: Integer;
  Seen: string;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Seen := '';
    for I := 1 to 8 do
    begin
      Press(Host, vkTab, []);
      DrawIn(Host, Grid);
      Seen := Seen + '|' + Host.FocusedControlId;
    end;
    Assert.IsTrue(Pos('|a1', Seen) > 0, 'visits a1: ' + Seen);
    Assert.IsTrue(Pos('|tabs', Seen) > 0, 'visits the strip: ' + Seen);
    Assert.IsTrue(Pos('|ok', Seen) > 0, 'visits ok: ' + Seen);
    Assert.AreEqual(0, Pos('b1', Seen), 'never b1: ' + Seen);
    Assert.AreEqual(0, Pos('c1', Seen), 'never c1: ' + Seen);
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestCtrlPageKeysTurnPagesAndWrap;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Press(Host, vkNext, [ssCtrl]);
    Assert.AreEqual(1, ActivePage(Host), 'Ctrl+PgDn: second page');
    DrawIn(Host, Grid);
    Assert.IsTrue(IsShown(Host, 'b1'), 'second page shown');
    Assert.IsFalse(IsShown(Host, 'a1'), 'first page gone');
    Press(Host, vkNext, [ssCtrl]);
    Press(Host, vkNext, [ssCtrl]);
    Assert.AreEqual(0, ActivePage(Host), 'wraps past the last page');
    Press(Host, vkPrior, [ssCtrl]);
    Assert.AreEqual(2, ActivePage(Host), 'Ctrl+PgUp wraps to the last page');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestCtrlTabTurnsPages;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Press(Host, vkTab, [ssCtrl]);
    Assert.AreEqual(1, ActivePage(Host), 'Ctrl+Tab forward');
    Press(Host, vkTab, [ssCtrl, ssShift]);
    Assert.AreEqual(0, ActivePage(Host), 'Ctrl+Shift+Tab back');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestArrowsOnFocusedStripTurnPages;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Host.FocusControlById('tabs');
    Press(Host, vkRight, []);
    Assert.AreEqual(1, ActivePage(Host), 'Right');
    Press(Host, vkLeft, []);
    Assert.AreEqual(0, ActivePage(Host), 'Left');
    Assert.AreEqual('tabs', Host.FocusedControlId, 'focus stays on the strip');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestFocusLeavesAPageThatGoesAway;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Host.FocusControlById('a2');
    Press(Host, vkNext, [ssCtrl]);
    Assert.AreEqual('tabs', Host.FocusedControlId, 'focus moves to the strip');
    Host.FocusControlById('ok');
    Press(Host, vkNext, [ssCtrl]);
    Assert.AreEqual('ok', Host.FocusedControlId, 'a control of every page keeps focus');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestClickOnCaptionSelectsPage;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  R: TRectI;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    R := Host.ControlBoundsAt(IndexOf(Host, 'tabs'));
    // "[ One ]" is 7 cells, "  Two  " follows.
    Assert.IsTrue(Host.HandleClick(R.Left + 9, R.Top, []), 'click taken');
    Assert.AreEqual(1, ActivePage(Host), 'second caption');
    Assert.AreEqual('tabs', Host.FocusedControlId, 'strip focused');
    DrawIn(Host, Grid);
    Host.HandleClick(R.Left + 39, R.Top, []);
    Assert.AreEqual(1, ActivePage(Host), 'a click past the captions keeps the page');
    R := Host.ControlBoundsAt(IndexOf(Host, 'b1'));
    Host.HandleClick(R.Left + 1, R.Top, []);
    Assert.IsTrue(Host.GetControl(IndexOf(Host, 'b1')).Checked, 'control of the new page works');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestMnemonicOfAnotherPageOpensIt;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Key: Word;
  Ch: Char;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Key := Ord('G');
    Ch := 'g';
    Host.HandleInput(Key, [ssAlt], Ch);
    Assert.AreEqual(2, ActivePage(Host), 'its page opens');
    Assert.IsTrue(Host.GetControl(IndexOf(Host, 'c1')).Checked, 'it is toggled');
    Assert.AreEqual('c1', Host.FocusedControlId, 'it is focused');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestFocusByIdOpensItsPage;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    Host.FocusControlById('b1');
    Assert.AreEqual(1, ActivePage(Host), 'page of the control');
    DrawIn(Host, Grid);
    Assert.IsTrue(IsShown(Host, 'b1'), 'control shown');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestStripDrawsMarkedCaption;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  R: TRectI;
  S: string;
  X: Integer;
begin
  Host := OpenHost;
  try
    DrawIn(Host, Grid);
    R := Host.ControlBoundsAt(IndexOf(Host, 'tabs'));
    S := '';
    for X := R.Left to R.Right do
      S := S + Grid[R.Top][X].CharValue;
    Assert.AreEqual(1, Pos('[ One ]', S), 'shown page in brackets: ' + S);
    Assert.IsTrue(Pos('Two', S) > 0, 'other captions: ' + S);
    Assert.AreEqual(0, Pos('[ Two ]', S), 'only the shown page is bracketed');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestRuleOpensUnderTheShownTab;
const
  cJson =
    '{"type":"dialog","version":"2.0","title":"t","width":50,"height":10,"children":[' +
    '{"type":"tabs","id":"tabs","items":["One","Two"],"col":1,"row":1,"width":40,"height":1},' +
    '{"type":"separator","col":0,"row":2,"width":48,"height":1},' +
    '{"type":"checkbox","id":"a1","text":"&Alpha","col":1,"row":3,"width":20,"height":1,"tab":0},' +
    '{"type":"button","id":"ok","text":"OK","default":true,"col":10,"row":7,"width":8,"height":1}]}';
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  R: TRectI;
  S: string;
  X: Integer;
begin
  Host := TDialogHost.Create(nil);
  try
    Assert.IsTrue(Host.OpenJson(cJson, nil), 'dialog opens');
    DrawIn(Host, Grid);
    R := Host.ControlBoundsAt(IndexOf(Host, 'tabs'));
    S := '';
    for X := R.Left - 1 to R.Left + 10 do
      S := S + Grid[R.Top + 1][X].CharValue;
    // The caption "[ One ]" is 7 cells wide: corner, 7 blanks, corner.
    Assert.AreEqual(chBoxBR + '       ' + chBoxBL, Copy(S, 1, 9), 'rule opens under the shown tab: ' + S);
    Assert.AreEqual(chBoxH, S[10], 'and goes on after it');
  finally
    Host.Free;
  end;
end;

procedure TTestDialogTabs.TestEveryDialogFitsEightyColumns;
var
  F, Loc, ResName, Bad: string;
  Decl: TDialogDeclaration;
  Host: TDialogHost;
  Grid: TTerminalGrid;
  I, N: Integer;
  R: TRectI;
begin
  Bad := '';
  N := 0;
  // Runner working dir is src	ests\dialogs.
  for F in TDirectory.GetFiles(TPath.GetFullPath('../../dialogs'), '*.json') do
  begin
    ResName := 'DIALOG_' + UpperCase(TPath.GetFileNameWithoutExtension(F));
    for Loc in ['', 'ru', 'de', 'zh'] do
    begin
      SetLocale(Loc);
      try
        if not TryLoadDialogResource(ResName, Decl) then
          Continue;
      finally
        SetLocale('');
      end;
      Inc(N);
      Host := TDialogHost.Create(nil);
      try
        Host.Open(Decl, nil);
        DrawIn(Host, Grid);
        if (Host.Bounds.Width > 78) or (Host.Bounds.Right > 79) then
          Bad := Bad + ' ' + ResName + '/' + Loc + ':frame=' + IntToStr(Host.Bounds.Width);
        for I := 0 to Host.ControlCount - 1 do
        begin
          R := Host.ControlBoundsAt(I);
          if (R.Right >= R.Left) and (R.Left >= 0) and (R.Right >= Host.Bounds.Right) then
            Bad := Bad + ' ' + ResName + '/' + Loc + ':' + Host.GetControl(I).Id;
        end;
      finally
        Host.Free;
      end;
    end;
  end;
  Assert.IsTrue(N > 100, 'dialogs checked: ' + IntToStr(N));
  Assert.AreEqual('', Bad, 'dialogs wider than 78 columns or with a control past the frame');
end;

procedure TTestDialogTabs.TestInterfaceDialogFitsEightyByTwentyFour;
begin
  CheckFitsEightyByTwentyFour(cResDialogInterface);
end;

procedure TTestDialogTabs.TestSearchDialogFitsEightyByTwentyFour;
begin
  CheckFitsEightyByTwentyFour(cResDialogSearch);
end;

procedure TTestDialogTabs.TestSetAttributesDialogFitsEightyByTwentyFour;
begin
  CheckFitsEightyByTwentyFour(cResDialogSetAttr);
end;

procedure TTestDialogTabs.TestMarkdownColorsDialogFitsEightyByTwentyFour;
begin
  CheckFitsEightyByTwentyFour(cResDialogMarkdownColors);
end;

procedure TTestDialogTabs.CheckFitsEightyByTwentyFour(const AResource: string);
var
  Decl: TDialogDeclaration;
  Loc: string;
  I, Page, Strip: Integer;
  L: TDialogV2Layout;
  Frame: TRectI;
begin
  for Loc in ['', 'ru', 'de', 'zh'] do
  begin
    SetLocale(Loc);
    try
      Assert.IsTrue(TryLoadDialogResource(AResource, Decl), 'loads ' + Loc);
    finally
      SetLocale('');
    end;
    Assert.IsTrue(Decl.Width <= 78, 'width fits 80 columns: ' + Loc + ' ' + IntToStr(Decl.Width));
    Assert.IsTrue(Decl.Height <= 22, 'height fits 24 rows: ' + Loc + ' ' + IntToStr(Decl.Height));
    Frame := TRectI.Make(0, 0, Decl.Width - 1, Decl.Height - 1);
    Strip := DialogTabStripIndex(Decl.Controls);
    Assert.IsTrue(Strip >= 0, 'has a tab strip');
    for Page := 0 to High(Decl.Controls[Strip].Items) do
    begin
      Decl.Controls[Strip].SelectedIndex := Page;
      L := LayoutDialogV2(Decl.Controls, Frame, 0, 0, -1);
      Assert.IsTrue(L.ContentH <= Decl.Height - 2,
        'no scrolling on page ' + IntToStr(Page) + ' ' + Loc);
      for I := 0 to High(Decl.Controls) do
        if not DialogControlHiddenByTab(Decl.Controls, I) then
          Assert.IsTrue(L.Bounds[I].Right >= L.Bounds[I].Left,
            Decl.Controls[I].Id + ' has a box on page ' + IntToStr(Page) + ' ' + Loc);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogTabs);
end.
