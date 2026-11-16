unit TestTopMenuBar;

{ Tests for StringToTopMenuAction (uTopMenuBar.pas), which is RTTI-driven
  (GetEnumValue + an exact-case GetEnumName round-trip). This test exercises
  every TTopMenuAction member by name via RTTI itself, so it stays correct
  as menu actions are added. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTopMenuBar = class
  public
    [Test] procedure TestEveryEnumMemberRoundTrips;
    [Test] procedure TestUnknownAndMalformedNames;
    [Test] procedure TestASampleOfKnownMappings;
    [Test] procedure TestHandleClickRouting;
    [Test] procedure TestF9OpensTheMenuOfTheActivePanel;
    [Test] procedure TestItemLettersActOnlyInTheOpenSubmenu;
    [Test] procedure TestMenuLettersAreUniquePerDropdown;
    [Test] procedure TestHomeEndPageKeysMoveInsideTheMenu;
    [Test] procedure TestReleaseOutsideAnItemRunsNothing;
    [Test] procedure TestAnItemRunsOnReleaseNotOnPress;
    [Test] procedure TestWideCaptionsKeepTheHotLetterOnItsCell;
    [Test] procedure TopMenuAltReleaseAndDismissChords;
    [Test] procedure SubmenuSeparatorAndItemLines;
    [Test] procedure SubmenuLayoutColorsAndScrollMarks;
    [Test] procedure PluginMenuInsertAndGroupGates;
    [Test] procedure PluginAndMenuJsonItemBuilders;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.TypInfo, System.UITypes, System.IOUtils,
  System.JSON, System.Generics.Collections,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uDualPanelTypes,
  uDualPanelOverlays,
  uThemeRegistry,
  uTopMenuBar;

procedure TestEveryEnumMemberRoundTrips;
var
  A: TTopMenuAction;
  Name: string;
  N: Integer;
begin
  N := 0;
  for A := Low(TTopMenuAction) to High(TTopMenuAction) do
  begin
    Name := GetEnumName(TypeInfo(TTopMenuAction), Ord(A));
    Assert.IsTrue(StringToTopMenuAction(Name) = A,
      Format('%s (ordinal %d) round-trips', [Name, Ord(A)]));
    Inc(N);
  end;
  Writeln('  (', N, ' enum members checked)');
end;

procedure TestUnknownAndMalformedNames;
begin
  Assert.IsTrue(StringToTopMenuAction('') = tmaNone, 'empty string');
  Assert.IsTrue(StringToTopMenuAction('tmaDoesNotExist') = tmaNone, 'a plausible but nonexistent name');
  Assert.IsTrue(StringToTopMenuAction('FileCopy') = tmaNone, 'missing the "tma" prefix');
  Assert.IsTrue(StringToTopMenuAction('tmafilecopy') = tmaNone,
    'wrong case is rejected (exact-case match, not GetEnumValue''s case-insensitive default)');
  Assert.IsTrue(StringToTopMenuAction('TMAFILECOPY') = tmaNone, 'all-caps is rejected');
  Assert.IsTrue(StringToTopMenuAction('tmaFileCopy ') = tmaNone, 'trailing space is rejected');
  Assert.IsTrue(StringToTopMenuAction(' tmaFileCopy') = tmaNone, 'leading space is rejected');
end;

procedure TestASampleOfKnownMappings;
begin
  // Spot-check a few concrete mappings, as a readable cross-check independent of the exhaustive RTTI loop above.
  Writeln('Spot-check known name -> action mappings');
  Assert.IsTrue(StringToTopMenuAction('tmaLeftDrive') = tmaLeftDrive, 'tmaLeftDrive');
  Assert.IsTrue(StringToTopMenuAction('tmaFileMkDir') = tmaFileMkDir, 'tmaFileMkDir');
  Assert.IsTrue(StringToTopMenuAction('tmaCmdSyncConsoleDir') = tmaCmdSyncConsoleDir, 'tmaCmdSyncConsoleDir');
  Assert.IsTrue(StringToTopMenuAction('tmaEditHexToggle') = tmaEditHexToggle, 'tmaEditHexToggle');
  Assert.IsTrue(StringToTopMenuAction('tmaOptResetZoom') = tmaOptResetZoom, 'tmaOptResetZoom');
  Assert.IsTrue(StringToTopMenuAction('tmaQuit') = tmaQuit, 'tmaQuit');
end;

var
  GInvalidateCount: Integer;
  GExecutedAction: TTopMenuAction;
  GExecutedCount: Integer;

function MakeController: TTopMenuController;
begin
  GInvalidateCount := 0;
  GExecutedAction := tmaNone;
  GExecutedCount := 0;
  Result := TTopMenuController.Create(nil,
    procedure
    begin
      Inc(GInvalidateCount);
    end,
    procedure(AAction: TTopMenuAction)
    begin
      GExecutedAction := AAction;
      Inc(GExecutedCount);
    end);
end;

procedure TestHandleClickRouting;
var
  C: TTopMenuController;
begin
  C := MakeController;
  try
    // Row 0, column 1 always lands in the first category's leading space,
    // regardless of that category's actual title text.
    Assert.IsTrue(C.HandleClick(1, 0), 'clicking the first category on the top bar is handled');
    Assert.IsTrue(C.Active, 'that click activates the menu');
    Assert.IsTrue(C.CategoryIndex = 0, 'and selects category 0');
    Assert.IsTrue(C.SubmenuOpen, 'opening a top-bar category also opens its submenu');
    Assert.IsTrue(GInvalidateCount > 0, 'activating invalidates the view');

    // Clicking the same already-open category again toggles it closed
    // (see HandleTopBarClick: FActive and FCategoryIndex=I and FSubmenuOpen).
    Assert.IsTrue(C.HandleClick(1, 0), 'clicking the open category again is handled');
    Assert.IsTrue(not C.Active, 'and closes the menu');

    // A column past every category''s title falls through the whole loop.
    C.ActivateMenu(0, True);
    Assert.IsTrue(C.HandleClick(100000, 0), 'clicking past the last category on the top bar is handled');
    Assert.IsTrue(not C.Active, 'and closes the menu (no category matched)');

    // A click on a submenu row while no menu is active/open is unhandled.
    C.DeactivateMenu;
    Assert.IsTrue(not C.HandleClick(5, 3), 'a non-top-bar click while inactive is unhandled');

    // Once open, a click outside the (never-laid-out, empty) submenu bounds
    // closes the menu -- HandleSubmenuClick's "outside" branch.
    C.ActivateMenu(0, True);
    Assert.IsTrue(C.HandleClick(5, 3), 'a submenu-row click while open is handled');
    Assert.IsTrue(not C.Active, 'clicking outside the submenu''s bounds closes it');
  finally
    C.Free;
  end;
end;

procedure TestF9OpensTheMenuOfTheActivePanel;
var
  C: TTopMenuController;
  RightActive: Boolean;
begin
  C := MakeController;
  try
    RightActive := False;
    C.OnIsRightPanelActive :=
      function: Boolean
      begin
        Result := RightActive;
      end;
    Assert.IsTrue(C.PanelCategory = 1, 'the left panel is active: Left');
    C.ToggleMenu;
    Assert.IsTrue(C.CategoryIndex = 1, 'F9 selects Left');
    Assert.IsFalse(C.SubmenuOpen, 'F9 does not drop the submenu down');
    C.ToggleMenu;
    RightActive := True;
    Assert.IsTrue(C.PanelCategory = 7, 'the right panel is active: Right, the last category');
    C.ToggleMenu;
    Assert.IsTrue(C.Active and (C.CategoryIndex = 7), 'F9 selects Right');
    Assert.IsFalse(C.SubmenuOpen, 'and leaves its submenu closed');
  finally
    C.Free;
  end;
end;

procedure TestItemLettersActOnlyInTheOpenSubmenu;
const
  cJson =
    '{"categories":[' +
    '{"title":"Alpha","hotChar":"A","items":[' +
    '{"caption":"Run","hotChar":"R","shortcut":"","action":"tmaFileCopy"}]},' +
    '{"title":"Beta","hotChar":"B","items":[' +
    '{"caption":"Save","hotChar":"S","shortcut":"","action":"tmaFileMove"}]}]}';
var
  C: TTopMenuController;
  Key: Word;
  Ch: Char;

  procedure Press(AChar: Char);
  begin
    Key := 0;
    Ch := AChar;
    C.HandleInput(Key, [], Ch);
  end;

begin
  C := MakeController;
  try
    Assert.IsTrue(C.LoadMenuFromJson(cJson), 'menu JSON parses');

    C.ActivateMenu(0, False);
    Press('R');
    Assert.AreEqual(0, GExecutedCount, 'an item letter does nothing while its submenu is closed');
    Assert.IsTrue(C.Active and not C.SubmenuOpen, 'and the menu stays as it was');

    Press('B');
    Assert.AreEqual(1, C.CategoryIndex, 'a category letter selects that category');
    Assert.IsTrue(C.SubmenuOpen, 'and opens its submenu');
    Assert.AreEqual(0, GExecutedCount, 'without running anything');

    Press('S');
    Assert.AreEqual(1, GExecutedCount, 'an item letter runs the item of the open submenu');
    Assert.IsTrue(GExecutedAction = tmaFileMove, 'the one shown in that submenu');
  finally
    C.Free;
  end;
end;

procedure TestMenuLettersAreUniquePerDropdown;
var
  Root, Cat, Item: TJSONObject;
  Cats, Items: TJSONArray;
  Seen: TDictionary<Char, string>;
  Dups: string;
  Cap: string;
  Hot: Char;
  Pos, I, J: Integer;
begin
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(
    ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
      '..' + PathDelim + '..' + PathDelim + 'config' + PathDelim + 'menu.json')),
    TEncoding.UTF8)) as TJSONObject;
  try
    Cats := Root.GetValue('categories') as TJSONArray;
    Dups := '';
    for I := 0 to Cats.Count - 1 do
    begin
      Cat := Cats.Items[I] as TJSONObject;
      Seen := TDictionary<Char, string>.Create;
      try
        Items := Cat.GetValue('items') as TJSONArray;
        for J := 0 to Items.Count - 1 do
        begin
          Item := Items.Items[J] as TJSONObject;
          if Item.GetValue<Boolean>('isSeparator', False) then
            Continue;
          Cap := Item.GetValue<string>('caption', '');
          Hot := #0;
          if Item.GetValue<string>('hotChar', '') <> '' then
            Hot := UpperCase(Item.GetValue<string>('hotChar', ''))[1];
          MenuResolveMnemonic(Cap, Hot, Pos);
          if Hot = #0 then
            Continue;
          if Seen.ContainsKey(Hot) then
            Dups := Dups + Format(' %s/%s: "%s" and "%s";', [
              Cat.GetValue<string>('title', ''), Hot, Seen[Hot], Cap])
          else
            Seen.Add(Hot, Cap);
        end;
      finally
        Seen.Free;
      end;
    end;
  finally
    Root.Free;
  end;
  Assert.AreEqual('', Dups, 'a letter is shown on two items of one dropdown, so the second never runs');
end;

procedure TestHomeEndPageKeysMoveInsideTheMenu;
var
  C: TTopMenuController;
  Key: Word;
  Ch: Char;
  Last: Integer;

  procedure Press(AKey: Word);
  begin
    Key := AKey;
    Ch := #0;
    C.HandleInput(Key, [], Ch);
  end;

begin
  C := MakeController;
  try
    C.ActivateMenu(2, True);
    Press(vkEnd);
    Last := C.SubmenuIndex;
    Assert.IsTrue(Last > 0, 'End goes to the last item');
    Press(vkHome);
    Assert.IsTrue(C.SubmenuIndex < Last, 'Home goes to the first');
    Press(vkNext);
    Assert.IsTrue(C.SubmenuIndex = Last, 'PgDn goes to the last item too');
    Press(vkPrior);
    Assert.IsTrue(C.SubmenuIndex < Last, 'PgUp to the first');
    Assert.IsTrue(C.Active and C.SubmenuOpen, 'the menu stays open');
  finally
    C.Free;
  end;
end;

procedure TestReleaseOutsideAnItemRunsNothing;
var
  C: TTopMenuController;
begin
  C := MakeController;
  try
    C.HandleClick(1, 0);
    Assert.IsFalse(C.HandleMouseUp(-1, -1), 'letting go outside the menu does nothing');
    Assert.IsTrue(C.Active, 'and leaves it open');
    Assert.IsFalse(C.HandleMouseUp(1, 0), 'a second release has no press to finish');
    Assert.IsTrue(GExecutedCount = 0, 'no action ran');
  finally
    C.Free;
  end;
end;

procedure TestAnItemRunsOnReleaseNotOnPress;
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
  Y: Integer;
begin
  GInvalidateCount := 0;
  GExecutedAction := tmaNone;
  GExecutedCount := 0;
  C := TTopMenuController.Create(CreateThemeByName('NDN'),
    procedure
    begin
      Inc(GInvalidateCount);
    end,
    procedure(AAction: TTopMenuAction)
    begin
      GExecutedAction := AAction;
      Inc(GExecutedCount);
    end);
  try
    SetLength(Grid, 30);
    for Y := 0 to High(Grid) do
      SetLength(Grid[Y], 100);
    C.ActivateMenu(1, True);
    C.DrawSubmenu(Grid, 100);
    // The first item of the open dropdown sits on row 2, inside its box.
    Assert.IsTrue(C.HandleClick(10, 2), 'the press is handled');
    Assert.IsTrue(GExecutedCount = 0, 'a press runs nothing');
    Assert.IsTrue(C.Active, 'and the menu stays open');
    Assert.IsTrue(C.HandleMouseUp(10, 2), 'releasing over the item runs it');
    Assert.IsTrue(GExecutedCount = 1, 'exactly once');

    C.ActivateMenu(1, True);
    C.DrawSubmenu(Grid, 100);
    C.HandleClick(10, 2);
    Assert.IsFalse(C.HandleMouseUp(-1, -1), 'releasing outside runs nothing');
    Assert.IsTrue(GExecutedCount = 1, 'still one run');
  finally
    C.Free;
  end;
end;

procedure TestWideCaptionsKeepTheHotLetterOnItsCell;
const
  cJson =
    '{"categories":[{"title":"X","hotChar":"X","items":[' +
    '{"caption":"复制(&C)","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"}' +
    ']}]}';
var
  C: TTopMenuController;
  Grid: TTerminalGrid;
  X, Y, Hot, HotX: Integer;
begin
  C := TTopMenuController.Create(CreateThemeByName('NDN'), nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cJson), 'menu JSON parses');
    SetLength(Grid, 10);
    for Y := 0 to High(Grid) do
      SetLength(Grid[Y], 60);
    C.ActivateMenu(0, True);
    C.DrawSubmenu(Grid, 60);
    Hot := 0;
    HotX := -1;
    for X := 0 to High(Grid[2]) do
      if Grid[2][X].FgColor = cMenuHotKeyFg then
      begin
        Inc(Hot);
        HotX := X;
      end;
    Assert.AreEqual(1, Hot, 'one highlighted cell in the item row');
    Assert.AreEqual('C', string(Grid[2][HotX].CharValue), 'it is the letter in the "(&C)" marker');
  finally
    C.Free;
  end;
end;

{ TTestTopMenuBar }

procedure TTestTopMenuBar.TestEveryEnumMemberRoundTrips;
begin
  TestTopMenuBar.TestEveryEnumMemberRoundTrips;
end;

procedure TTestTopMenuBar.TestUnknownAndMalformedNames;
begin
  TestTopMenuBar.TestUnknownAndMalformedNames;
end;

procedure TTestTopMenuBar.TestASampleOfKnownMappings;
begin
  TestTopMenuBar.TestASampleOfKnownMappings;
end;

procedure TTestTopMenuBar.TestHandleClickRouting;
begin
  TestTopMenuBar.TestHandleClickRouting;
end;

procedure TTestTopMenuBar.TestF9OpensTheMenuOfTheActivePanel;
begin
  TestTopMenuBar.TestF9OpensTheMenuOfTheActivePanel;
end;

procedure TTestTopMenuBar.TestItemLettersActOnlyInTheOpenSubmenu;
begin
  TestTopMenuBar.TestItemLettersActOnlyInTheOpenSubmenu;
end;

procedure TTestTopMenuBar.TestMenuLettersAreUniquePerDropdown;
begin
  TestTopMenuBar.TestMenuLettersAreUniquePerDropdown;
end;

procedure TTestTopMenuBar.TestHomeEndPageKeysMoveInsideTheMenu;
begin
  TestTopMenuBar.TestHomeEndPageKeysMoveInsideTheMenu;
end;

procedure TTestTopMenuBar.TestAnItemRunsOnReleaseNotOnPress;
begin
  TestTopMenuBar.TestAnItemRunsOnReleaseNotOnPress;
end;

procedure TTestTopMenuBar.TestWideCaptionsKeepTheHotLetterOnItsCell;
begin
  TestTopMenuBar.TestWideCaptionsKeepTheHotLetterOnItsCell;
end;

procedure TTestTopMenuBar.TestReleaseOutsideAnItemRunsNothing;
begin
  TestTopMenuBar.TestReleaseOutsideAnItemRunsNothing;
end;

procedure TTestTopMenuBar.TopMenuAltReleaseAndDismissChords;
begin
  Assert.IsTrue(TopMenuAltReleaseActivates(0, #0, [ssAlt]), 'alt release');
  Assert.IsTrue(not TopMenuAltReleaseActivates(0, 'F', [ssAlt]), 'alt+letter');
  Assert.IsTrue(not TopMenuAltReleaseActivates(vkF9, #0, []), 'f9 alone');
  Assert.IsTrue(TopMenuActiveDismisses(vkEscape, #0, []), 'esc');
  Assert.IsTrue(TopMenuActiveDismisses(0, #0, [ssAlt]), 'second alt');
  Assert.IsTrue(not TopMenuActiveDismisses(vkReturn, #0, []), 'enter');
end;

procedure TTestTopMenuBar.SubmenuSeparatorAndItemLines;
var
  Line: string;
begin
  Line := SubmenuSeparatorLine('', 5);
  Assert.AreEqual(StringOfChar(#$2500, 5), Line, 'plain');
  Line := SubmenuSeparatorLine('Name', 12);
  Assert.IsTrue(Pos(' Name ', Line) > 0, 'title gap');
  Assert.IsTrue(Length(Line) >= 12, 'width');
  Line := SubmenuItemLine('Copy', 'F5', 12);
  Assert.IsTrue(Pos('Copy', Line) > 0, 'caption');
  Assert.IsTrue(Pos('F5', Line) > 0, 'shortcut');
  Assert.AreEqual('', SubmenuItemLine('x', '', 0), 'empty width');
end;

procedure TTestTopMenuBar.SubmenuLayoutColorsAndScrollMarks;
var
  Bounds: TRectI;
  ItemX, InnerW: Integer;
  Fg, Bg: TAlphaColor;
begin
  Bounds := TRectI.Make(10, 2, 29, 12);
  SubmenuContentLayout(False, Bounds, ItemX, InnerW);
  Assert.AreEqual(11, ItemX, 'inset x');
  Assert.AreEqual(18, InnerW, 'inset width');
  SubmenuContentLayout(True, Bounds, ItemX, InnerW);
  Assert.AreEqual(10, ItemX, 'edge x');
  Assert.AreEqual(20, InnerW, 'edge width');

  ResolveSubmenuRowColors(False, True, $FF111111, $FF222222, $FF333333,
    $FF444444, $FF555555, Fg, Bg);
  Assert.IsTrue((Fg = $FF555555) and (Bg = $FF222222), 'disabled');
  ResolveSubmenuRowColors(True, True, $FF111111, $FF222222, $FF333333,
    $FF444444, $FF555555, Fg, Bg);
  Assert.IsTrue((Fg = $FF333333) and (Bg = $FF444444), 'selected');
  ResolveSubmenuRowColors(True, False, $FF111111, $FF222222, $FF333333,
    $FF444444, $FF555555, Fg, Bg);
  Assert.IsTrue((Fg = $FF111111) and (Bg = $FF222222), 'idle');

  Assert.IsTrue(not SubmenuScrollUpMarkNeeded(0), 'top');
  Assert.IsTrue(SubmenuScrollUpMarkNeeded(2), 'scrolled');
  Assert.IsTrue(SubmenuScrollDownMarkNeeded(0, 5, 10), 'more below');
  Assert.IsTrue(not SubmenuScrollDownMarkNeeded(5, 5, 10), 'at end');

  Assert.IsTrue(SubmenuHotCharVisible('C', 1, 'Copy', True), 'hot');
  Assert.IsTrue(not SubmenuHotCharVisible('C', 1, 'Copy', False), 'disabled hot');
  Assert.AreEqual(11, SubmenuHotCharCol(10, 'Copy', 1), 'hot col');
end;

procedure TTestTopMenuBar.PluginMenuInsertAndGroupGates;
var
  Cats: TArray<TTopMenuCategory>;
  Items: TArray<TSubmenuItem>;
begin
  Assert.IsTrue(IsMacrosMenuParent(cMacrosMenuPath), 'macros path');
  Assert.IsTrue(not IsMacrosMenuParent('Plugins'), 'other');
  Assert.IsTrue(ShouldOpenPluginGroup(0, '', 'p1'), 'first group');
  Assert.IsTrue(ShouldOpenPluginGroup(1, 'p1', 'p2'), 'new plugin');
  Assert.IsTrue(not ShouldOpenPluginGroup(1, 'p1', 'p1'), 'same plugin');

  SetLength(Items, 1);
  Items[0] := Default(TSubmenuItem);
  Items[0].PluginPriority := 10;
  Assert.IsTrue(ShouldInsertMacroPrioritySeparator(100, Items), 'sep');
  Items[0].IsSeparator := True;
  Assert.IsTrue(not ShouldInsertMacroPrioritySeparator(100, Items), 'after sep');

  SetLength(Cats, 2);
  Cats[0].Key := 'Commands';
  Cats[0].Title := 'Commands';
  Cats[1].Key := 'Options';
  Cats[1].Title := 'Options';
  Assert.AreEqual(1, PluginsMenuInsertIndex(Cats), 'before options');
  Cats[1].Key := 'Right';
  Cats[1].Title := 'Right';
  Assert.AreEqual(1, PluginsMenuInsertIndex(Cats), 'last when no options');
end;

procedure TTestTopMenuBar.PluginAndMenuJsonItemBuilders;
var
  Desc: TPluginMenuItemDesc;
  Item: TSubmenuItem;
  Obj: TJSONObject;
begin
  Item := MakeSubmenuSeparatorItem('SevenZip', 2);
  Assert.IsTrue(Item.IsSeparator, 'sep');
  Assert.AreEqual('SevenZip', Item.SeparatorTitle, 'sep title');
  Assert.AreEqual(2, Item.PluginGroup, 'sep group');

  Desc := Default(TPluginMenuItemDesc);
  Desc.Caption := 'Pack';
  Desc.PluginId := 'mtn.7z';
  Desc.ItemId := 'pack';
  Desc.Shortcut := 'Alt+F5';
  Item := MakePluginActionItem(Desc, 3);
  Assert.IsTrue(Item.IsPluginItem, 'plugin');
  Assert.AreEqual('Pack', Item.Caption, 'caption');
  Assert.AreEqual(3, Item.PluginGroup, 'group');
  Assert.AreEqual('Alt+F5', Item.Shortcut, 'shortcut');

  Desc.Priority := 150;
  Desc.Caption := '&Macro';
  Item := MakeMacroActionItem(Desc);
  Assert.AreEqual(150, Item.PluginPriority, 'priority');
  Assert.IsTrue(Item.HotChar <> #0, 'macro hot');

  Item := ParseMenuJsonSeparatorItem;
  Assert.IsTrue(Item.IsSeparator, 'json sep');
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('caption', 'Copy');
    Obj.AddPair('hotChar', 'C');
    Obj.AddPair('shortcut', 'F5');
    Obj.AddPair('action', 'tmaFileCopy');
    Item := ParseMenuJsonActionItem(Obj);
    Assert.IsTrue(not Item.IsSeparator, 'json action');
    Assert.AreEqual(tmaFileCopy, Item.Action, 'action');
    Assert.IsTrue(Pos('Copy', Item.Caption) > 0, 'json caption');
  finally
    Obj.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTopMenuBar);

end.
