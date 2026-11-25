unit TestSettingsPages;

{ The settings window merges the pages of the Font / Display and Interface
  declarations into one dialog with a list of sections; a search narrows the
  list to the sections whose caption or field captions match. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsPages = class
  public
    [Test] procedure TestSectionsFollowTheSourcePages;
    [Test] procedure TestEachControlIdAppearsOnce;
    [Test] procedure TestContentMovesRightOfTheSidebar;
    [Test] procedure TestMergedDialogFitsEightyByTwentyFour;
    [Test] procedure TestButtonsKeepTheCaptionsOfTheSources;
    [Test] procedure TestDividerJoinsFrameAndRuleOnDoubleFrame;
    [Test] procedure TestDividerJoinsFrameAndRuleOnAsciiFrame;
    [Test] procedure TestEveryFieldHasAHint;
    [Test] procedure TestFieldsCarryCaptionHintAndSection;
    [Test] procedure TestHintAreaShowsTheFocusedFieldHint;
    [Test] procedure TestHintFollowsPointerAndFocusSwitches;
    [Test] procedure TestHintSurvivesJsonRoundTrip;
    [Test] procedure TestEmptyQueryKeepsEverySection;
    [Test] procedure TestQueryMatchesSectionCaption;
    [Test] procedure TestQueryMatchesFieldCaptionIgnoringMnemonicAndCase;
    [Test] procedure TestQueryWithoutMatchGivesNoSections;
  end;

implementation

uses
  System.SysUtils, uDialogTypes, uDialogResources, uDialogTabs, uSettingsPages, uDialogJson, uDialogJsonSerialize,
  System.UITypes, uTerminalTypes, uThemeTypes, uDialogHost, uThemeRegistry;

function Merge(out APages: TSettingsPages): TDialogDeclaration;
var
  Sources: TArray<TDialogDeclaration>;
begin
  SetLength(Sources, 2);
  Assert.IsTrue(TryLoadDialogResource(cResDialogDisplay, Sources[0]), 'display loads');
  Assert.IsTrue(TryLoadDialogResource(cResDialogInterface, Sources[1]), 'interface loads');
  Result := MergeSettingsPages(Sources, [], 'Settings', APages);
end;

function IndexOfId(const ADecl: TDialogDeclaration; const AId: string): Integer;
begin
  for Result := 0 to High(ADecl.Controls) do
    if ADecl.Controls[Result].Id = AId then
      Exit;
  Result := -1;
end;

procedure TTestSettingsPages.TestSectionsFollowTheSourcePages;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  Strip: Integer;
begin
  Decl := Merge(Pages);
  Assert.AreEqual<Integer>(10, Length(Pages.Captions),
    'Font, Text, Display, Window, Panels, Behavior, Keyboard, Editor, Console, Notices');
  Assert.AreEqual('Font', Pages.Captions[0], 'first');
  Assert.AreEqual('Notices', Pages.Captions[9], 'last');
  Assert.AreEqual<Integer>(10, Pages.Pages[9], 'pages count on');
  Strip := DialogTabStripIndex(Decl.Controls);
  Assert.IsTrue(Strip >= 0, 'strip');
  Assert.IsTrue(Decl.Controls[Strip].Vertical, 'vertical strip');
  Assert.AreEqual<Integer>(10, Length(Decl.Controls[Strip].Items), 'strip captions');
  Assert.AreEqual<Integer>(4, Decl.Controls[IndexOfId(Decl, 'show_title_bar')].TabPage,
    'the Window page of Interface comes after the three of Display');
end;

procedure TTestSettingsPages.TestEachControlIdAppearsOnce;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  I, J: Integer;
begin
  Decl := Merge(Pages);
  for I := 0 to High(Decl.Controls) do
    if Decl.Controls[I].Id <> '' then
      for J := I + 1 to High(Decl.Controls) do
        Assert.AreNotEqual(Decl.Controls[I].Id, Decl.Controls[J].Id, 'duplicate id');
  Assert.IsTrue(IndexOfId(Decl, cDlgCmdOk) >= 0, 'OK');
  Assert.IsTrue(IndexOfId(Decl, cDlgCmdCancel) >= 0, 'one Cancel');
end;

procedure TTestSettingsPages.TestContentMovesRightOfTheSidebar;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  I: Integer;
begin
  Decl := Merge(Pages);
  for I := 0 to High(Decl.Controls) do
    if Decl.Controls[I].TabPage > 0 then
    begin
      Assert.IsTrue(Decl.Controls[I].Col >= cSettingsSidebarWidth,
        Decl.Controls[I].Id + ' is right of the sidebar');
      Assert.IsTrue(Decl.Controls[I].Row >= 0, Decl.Controls[I].Id + ' starts at the top');
    end;
end;

procedure TTestSettingsPages.TestMergedDialogFitsEightyByTwentyFour;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
begin
  Decl := Merge(Pages);
  Assert.IsTrue(Decl.Width <= 78, 'width ' + IntToStr(Decl.Width));
  Assert.IsTrue(Decl.Height <= 22, 'height ' + IntToStr(Decl.Height));
end;

procedure TTestSettingsPages.TestButtonsKeepTheCaptionsOfTheSources;
var
  Sources: TArray<TDialogDeclaration>;
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  I: Integer;
begin
  SetLength(Sources, 1);
  Assert.IsTrue(TryLoadDialogResource(cResDialogInterface, Sources[0]), 'interface loads');
  for I := 0 to High(Sources[0].Controls) do
    if Sources[0].Controls[I].Kind = dckButton then
    begin
      if Sources[0].Controls[I].IsCancel then
        Sources[0].Controls[I].Text := 'Otmena'
      else if Sources[0].Controls[I].IsDefault then
        Sources[0].Controls[I].Text := 'Khorosho';
    end;
  Decl := MergeSettingsPages(Sources, [], 'Settings', Pages);
  Assert.AreEqual('Khorosho', Decl.Controls[IndexOfId(Decl, cDlgCmdOk)].Text, 'OK caption');
  Assert.AreEqual('Otmena', Decl.Controls[IndexOfId(Decl, cDlgCmdCancel)].Text, 'Cancel caption');
end;

procedure NoopCommand(const AControlId, AValuesJson: string);
begin
end;

// Draws the merged dialog and returns the column of the divider and its three
// glyphs: on the frame's top edge, in the middle, on the rule under it.
procedure DrawDivider(const AThemeName: string; out ATop, AMid, ABottom: Char);
var
  Decl: TDialogDeclaration;
  Pages: TSettingsPages;
  Host: TDialogHost;
  Grid: TTerminalGrid;
  X, Y, Col, Top: Integer;
begin
  Decl := Merge(Pages);
  AllocTerminalGrid(Grid, 100, 40);
  ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
  Host := TDialogHost.Create(CreateThemeByName(AThemeName));
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, 100, 40);
  finally
    Host.Free;
  end;
  // The dialog's top-left corner is the first non-blank cell; the divider is
  // the column the sidebar width to its right.
  Top := -1;
  Col := -1;
  for Y := 0 to High(Grid) do
    for X := 0 to High(Grid[Y]) do
      if (Top < 0) and (Grid[Y][X].CharValue <> ' ') then
      begin
        Top := Y;
        Col := X + cSettingsSidebarWidth;
      end;
  Assert.IsTrue(Top >= 0, 'dialog drawn');
  ATop := Grid[Top][Col].CharValue;
  AMid := Grid[Top + 3][Col].CharValue;
  ABottom := #0;
  for Y := Top + 4 to High(Grid) do
    if (Grid[Y][Col].CharValue <> AMid) then
    begin
      ABottom := Grid[Y][Col].CharValue;
      Break;
    end;
end;

procedure TTestSettingsPages.TestDividerJoinsFrameAndRuleOnDoubleFrame;
var
  T, M, B: Char;
begin
  DrawDivider('NDN', T, M, B);
  Assert.IsTrue(T = chDblHSingleHD, 'tee into the double top edge');
  Assert.IsTrue(M = chBoxV, 'single vertical line');
  Assert.IsTrue(B = chBoxHU, 'tee into the rule under it');
end;

procedure TTestSettingsPages.TestDividerJoinsFrameAndRuleOnAsciiFrame;
var
  T, M, B: Char;
begin
  DrawDivider('ASCII', T, M, B);
  Assert.IsTrue(T = '+', 'tee into the top edge');
  Assert.IsTrue(M = '|', 'vertical line');
  Assert.IsTrue(B = '+', 'tee into the rule under it');
end;

procedure TTestSettingsPages.TestEveryFieldHasAHint;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  I: Integer;
  Bad: string;
begin
  Decl := Merge(Pages);
  Bad := '';
  for I := 0 to High(Decl.Controls) do
    if (Decl.Controls[I].Kind in [dckCheckbox, dckDropDown, dckList, dckInput]) or
       ((Decl.Controls[I].Kind = dckButton) and (Decl.Controls[I].TabPage > 0)) then
      if Decl.Controls[I].Hint = '' then
        Bad := Bad + ' ' + Decl.Controls[I].Id;
  Assert.AreEqual('', Bad, 'fields without a hint');
end;

procedure TTestSettingsPages.TestFieldsCarryCaptionHintAndSection;

  function Find(const AFields: TArray<TSettingField>; const AId: string): TSettingField;
  var
    F: TSettingField;
  begin
    for F in AFields do
      if F.Id = AId then
        Exit(F);
    Result := Default(TSettingField);
  end;

var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  Fields: TArray<TSettingField>;
  F: TSettingField;
begin
  Decl := Merge(Pages);
  Fields := SettingsFields(Decl, Pages);
  F := Find(Fields, 'editor_autowrap');
  Assert.AreEqual('Editor', F.Section, 'section of a check box');
  Assert.AreEqual('Auto-wrap long lines while typing', F.Caption, 'caption of a check box');
  Assert.IsTrue(F.Hint <> '', 'hint carried');
  F := Find(Fields, 'reflow_width');
  Assert.AreEqual('Wrap width', F.Caption, 'caption of an input is the label on its row');
  F := Find(Fields, 'scrollback');
  Assert.AreEqual('Console', F.Section, 'section of a drop-down');
  Assert.AreEqual('Scrollback', F.Caption, 'caption of a drop-down');
  F := Find(Fields, 'ok');
  Assert.AreEqual('', F.Id, 'buttons are not fields');
  for F in Fields do
    Assert.IsTrue((F.Caption <> '') and (F.Section <> '') and (F.Hint <> ''), 'complete: ' + F.Id);
end;

procedure TTestSettingsPages.TestHintAreaShowsTheFocusedFieldHint;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  Host: TDialogHost;
  Grid: TTerminalGrid;
  X, Y: Integer;
  Text, Want: string;
begin
  Decl := Merge(Pages);
  Want := Decl.Controls[IndexOfId(Decl, 'show_title_bar')].Hint;
  Assert.IsTrue(Want <> '', 'hint authored');
  AllocTerminalGrid(Grid, 100, 40);
  ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
  Host := TDialogHost.Create(CreateThemeByName('NDN'));
  try
    Host.Open(Decl, NoopCommand);
    Host.FocusControlById('show_title_bar');
    Host.Draw(Grid, 100, 40);
  finally
    Host.Free;
  end;
  Text := '';
  for Y := 0 to High(Grid) do
  begin
    for X := 0 to High(Grid[Y]) do
      Text := Text + Grid[Y][X].CharValue;
    Text := Text + #10;
  end;
  Assert.IsTrue(Pos(Copy(Want, 1, 20), Text) > 0, 'hint of the focused field is drawn');
end;

procedure TTestSettingsPages.TestHintFollowsPointerAndFocusSwitches;
var
  Pages: TSettingsPages;
  Decl: TDialogDeclaration;
  Host: TDialogHost;
  Grid: TTerminalGrid;
  Col, Row, Y, P: Integer;
  Line: string;
  SavedFocus, SavedHover: Boolean;

  function DrawnText: string;
  var
    X, YY: Integer;
  begin
    AllocTerminalGrid(Grid, 100, 40);
    ClearTerminalGrid(Grid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
    Host.Draw(Grid, 100, 40);
    Result := '';
    for YY := 0 to High(Grid) do
    begin
      for X := 0 to High(Grid[YY]) do
        Result := Result + Grid[YY][X].CharValue;
      Result := Result + #10;
    end;
  end;

begin
  SavedFocus := GHintsOnFocus;
  SavedHover := GHintsOnHover;
  Decl := Merge(Pages);
  Decl.Controls[DialogTabStripIndex(Decl.Controls)].SelectedIndex := Length(Pages.Captions) - 1;
  Host := TDialogHost.Create(CreateThemeByName('NDN'));
  try
    Host.Open(Decl, NoopCommand);
    Host.FocusControlById('notifications');
    GHintsOnFocus := True;
    GHintsOnHover := True;
    DrawnText;
    Col := -1;
    Row := -1;
    for Y := 0 to High(Grid) do
    begin
      Line := '';
      for P := 0 to High(Grid[Y]) do
        Line := Line + Grid[Y][P].CharValue;
      P := Pos('Under the mouse pointer', Line);
      if P > 0 then
      begin
        Col := P - 1;
        Row := Y;
      end;
    end;
    Assert.IsTrue(Col >= 0, 'pointer switch drawn');
    Assert.IsTrue(Host.HoverAt(Col, Row), 'pointer on a field with a hint changes the hover');
    Assert.IsTrue(Pos('field under the mouse', DrawnText) > 0, 'hint of the field under the pointer');
    Assert.IsFalse(Host.HoverAt(Col, Row), 'same field: no change');
    GHintsOnHover := False;
    Assert.IsTrue(Pos('field under the mouse', DrawnText) = 0, 'pointer switch off hides it');
    GHintsOnHover := True;
    Assert.IsTrue(Host.HoverAt(0, 0), 'pointer leaves the field');
    Assert.IsTrue(Pos('field under the mouse', DrawnText) = 0, 'no hover: hint of the focused field');
    GHintsOnFocus := False;
    Assert.IsTrue(Pos('Shows', DrawnText) = 0, 'focus switch off: no hint without a pointer');
  finally
    GHintsOnFocus := SavedFocus;
    GHintsOnHover := SavedHover;
    Host.Free;
  end;
end;

procedure TTestSettingsPages.TestHintSurvivesJsonRoundTrip;
var
  Pages: TSettingsPages;
  Decl, Back: TDialogDeclaration;
  Idx: Integer;
begin
  Decl := Merge(Pages);
  Assert.IsTrue(TryParseDialogJson(DeclarationToJson(Decl), Back), 're-parse');
  Idx := IndexOfId(Back, 'show_title_bar');
  Assert.IsTrue(Idx >= 0, 'field present');
  Assert.AreEqual(Decl.Controls[IndexOfId(Decl, 'show_title_bar')].Hint,
    Back.Controls[Idx].Hint, 'hint kept');
  Assert.IsTrue(Back.Controls[IndexOfId(Back, 'hint_area')].HintArea, 'hint area kept');
end;

procedure TTestSettingsPages.TestEmptyQueryKeepsEverySection;
var
  Pages, Found: TSettingsPages;
  Decl: TDialogDeclaration;
begin
  Decl := Merge(Pages);
  Assert.IsTrue(SettingsSectionsMatching(Decl, Pages, '', Found), 'matches');
  Assert.AreEqual<Integer>(10, Length(Found.Captions), 'all sections');
  Assert.IsTrue(SettingsSectionsMatching(Decl, Pages, '  ', Found), 'blanks are no query');
  Assert.AreEqual<Integer>(10, Length(Found.Captions), 'all sections for blanks');
end;

procedure TTestSettingsPages.TestQueryMatchesSectionCaption;
var
  Pages, Found: TSettingsPages;
  Decl: TDialogDeclaration;
begin
  Decl := Merge(Pages);
  Assert.IsTrue(SettingsSectionsMatching(Decl, Pages, 'BEHAV', Found), 'matches');
  Assert.AreEqual<Integer>(1, Length(Found.Captions), 'only the section named so');
  Assert.AreEqual('Behavior', Found.Captions[0], 'caption match ignores case');
end;

procedure TTestSettingsPages.TestQueryMatchesFieldCaptionIgnoringMnemonicAndCase;
var
  Pages, Found: TSettingsPages;
  Decl: TDialogDeclaration;
begin
  Decl := Merge(Pages);
  // "Show &menu bar" sits on the Window page.
  Assert.IsTrue(SettingsSectionsMatching(Decl, Pages, 'MENU BAR', Found), 'matches');
  Assert.AreEqual<Integer>(1, Length(Found.Captions), 'only the page with the field');
  Assert.AreEqual('Window', Found.Captions[0], 'Window');
  Assert.AreEqual<Integer>(4, Found.Pages[0], 'page of the section is kept');
end;

procedure TTestSettingsPages.TestQueryWithoutMatchGivesNoSections;
var
  Pages, Found: TSettingsPages;
  Decl: TDialogDeclaration;
begin
  Decl := Merge(Pages);
  Assert.IsFalse(SettingsSectionsMatching(Decl, Pages, 'zzzzqqq', Found), 'no match');
  Assert.AreEqual<Integer>(0, Length(Found.Captions), 'empty');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsPages);
end.
