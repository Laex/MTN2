unit TestPluginMenu;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginMenu = class
  public
    [Test] procedure PluginsMenuHoldsTheManagerWithoutPluginItems;
    [Test] procedure PluginsMenuSitsBeforeOptions;
    [Test] procedure MacrosParentGetsItsOwnMenuAfterPlugins;
    [Test] procedure DisabledPluginItemCannotBeRun;
    [Test] procedure OnlyTheGreyedRegistryItemIsDisabled;
    [Test] procedure PluginGroupsFollowThePluginListOrder;
    [Test] procedure ItemsAreGroupedByPluginWithNamedLines;
    [Test] procedure PluginWithoutNameIsShownById;
    [Test] procedure ParentNameOfTheItemDoesNotMatter;
    [Test] procedure PluginsMenuIsTranslated;
  end;

implementation

uses
  System.SysUtils,
  uStrings, uTopMenuBar, uMenuRegistry;

const
  cMenuJson =
    '{"categories":[' +
    '{"title":"Commands","hotChar":"C","items":[]},' +
    '{"title":"Options","hotChar":"O","items":[]},' +
    '{"title":"Right","hotChar":"R","items":[]}]}';

function Desc(const APlugin, AParent, ACaption: string; APriority: Integer): TPluginMenuItemDesc;
begin
  Result.PluginId := APlugin;
  Result.PluginTitle := 'Plugin ' + APlugin;
  Result.ParentTitle := AParent;
  Result.Caption := ACaption;
  Result.OnClick := nil;
  Result.Priority := APriority;
  Result.Disabled := False;
end;

function Titles(AMenu: TTopMenuController): string;
var
  I: Integer;
begin
  Result := '';
  I := 0;
  while AMenu.CategoryTitle(I) <> '' do
  begin
    Result := Result + AMenu.CategoryTitle(I) + '|';
    Inc(I);
  end;
end;

function Items(AMenu: TTopMenuController; ACategory: Integer): string;
var
  J: Integer;
begin
  Result := '';
  J := 0;
  while AMenu.CategoryItemCaption(ACategory, J) <> '' do
  begin
    Result := Result + AMenu.CategoryItemCaption(ACategory, J) + '|';
    Inc(J);
  end;
end;

procedure TTestPluginMenu.PluginsMenuHoldsTheManagerWithoutPluginItems;
var
  C: TTopMenuController;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems(nil);
    Assert.AreEqual('Commands|Plugins|Options|Right|', Titles(C));
    Assert.AreEqual('Plugins...|', Items(C, 1), 'the plugin manager stays reachable');
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.PluginsMenuSitsBeforeOptions;
var
  C: TTopMenuController;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems([Desc('a', 'Plugins', 'A1', 10)]);
    Assert.AreEqual('Commands|Plugins|Options|Right|', Titles(C));
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.MacrosParentGetsItsOwnMenuAfterPlugins;
var
  C: TTopMenuController;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems([Desc('a', 'Plugins', 'A1', 10), Desc('m', 'Macros', 'M2', 20),
      Desc('m', 'Macros', 'M1', 10)]);
    Assert.AreEqual('Commands|Plugins|Macros|Options|Right|', Titles(C));
    Assert.AreEqual('Plugins...|-|A1|', Items(C, 1), 'macro items stay out of the Plugins menu');
    Assert.AreEqual('M1|M2|', Items(C, 2), 'the Macros menu has no plugin group lines');
    C.SetPluginMenuItems([Desc('m', 'Macros', 'M1', 10), Desc('m', 'Macros', 'X', 100)]);
    Assert.AreEqual('M1|-|X|', Items(C, 2), 'a line sets the menu commands apart from the macros');
    C.SetPluginMenuItems([Desc('a', 'Plugins', 'A1', 10)]);
    Assert.AreEqual('Commands|Plugins|Options|Right|', Titles(C), 'no macro items, no Macros menu');
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.DisabledPluginItemCannotBeRun;
var
  C: TTopMenuController;
  D: TPluginMenuItemDesc;
  Ran, Runnable: Integer;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    Ran := 0;
    D := Desc('m', 'Macros', 'Pause', 10);
    D.OnClick := procedure begin Inc(Ran); end;
    D.Disabled := True;
    C.SetPluginMenuItems([D]);
    Runnable := 0;
    C.ListItems(procedure(ATitle: string; AItem: TSubmenuItem)
      begin
        if AItem.IsPluginItem then
        begin
          Assert.IsFalse(C.CanRunItem(AItem), 'a greyed item cannot be chosen');
          Assert.IsFalse(C.RunItem(AItem));
          Inc(Runnable);
        end;
      end);
    Assert.AreEqual(1, Runnable, 'the greyed item is still listed');
    Assert.AreEqual(0, Ran);
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.PluginGroupsFollowThePluginListOrder;
var
  C: TTopMenuController;
  Seen: string;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    MenuRegistry.AttachController(C);
    try
      MenuRegistry.SetOrderResolver(
        function(APluginId: string): Integer
        begin
          if APluginId = 't.first' then
            Result := 0
          else if APluginId = 't.second' then
            Result := 1
          else
            Result := -1;
        end);
      // Registered in the opposite order to the plugin list.
      MenuRegistry.RegisterMenuItem('t.second', 'Plugins', 'b', 'B1', procedure begin end);
      MenuRegistry.RegisterMenuItem('t.first', 'Plugins', 'a', 'A1', procedure begin end);
      Seen := '';
      C.ListItems(procedure(ATitle: string; AItem: TSubmenuItem)
        begin
          if (AItem.PluginId = 't.first') or (AItem.PluginId = 't.second') then
            Seen := Seen + AItem.PluginId + '|';
        end);
      Assert.AreEqual('t.first|t.second|', Seen);
    finally
      MenuRegistry.SetOrderResolver(nil);
      MenuRegistry.UnregisterPlugin('t.first');
      MenuRegistry.UnregisterPlugin('t.second');
      MenuRegistry.AttachController(nil);
    end;
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.OnlyTheGreyedRegistryItemIsDisabled;
var
  C: TTopMenuController;
  Off, On_: Integer;
  I: Integer;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    MenuRegistry.AttachController(C);
    try
      for I := 1 to 3 do
        MenuRegistry.RegisterMenuItem('t.reg', 'Macros', 'item' + IntToStr(I), 'Item' + IntToStr(I),
          procedure begin end, I * 10);
      Assert.IsTrue(MenuRegistry.SetMenuItemEnabled('t.reg', 'item2', False));
      Off := 0;
      On_ := 0;
      C.ListItems(procedure(ATitle: string; AItem: TSubmenuItem)
        begin
          if AItem.PluginId <> 't.reg' then
            Exit;
          if C.CanRunItem(AItem) then
            Inc(On_)
          else
            Inc(Off);
        end);
      Assert.AreEqual(1, Off, 'only the greyed item is disabled');
      Assert.AreEqual(2, On_);
    finally
      MenuRegistry.UnregisterPlugin('t.reg');
      MenuRegistry.AttachController(nil);
    end;
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.ItemsAreGroupedByPluginWithNamedLines;
var
  C: TTopMenuController;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems([
      Desc('a', 'Plugins', 'A2', 20), Desc('b', 'Plugins', 'B1', 5),
      Desc('a', 'Plugins', 'A1', 10), Desc('c', 'Plugins', 'C1', 1)]);
    Assert.AreEqual('Plugins...|-|A1|A2|-|B1|-|C1|', Items(C, 1),
      'groups follow registration order, priority orders a group');
    Assert.AreEqual('Plugin a', C.CategorySeparatorTitle(1, 1), 'a line names the plugin that follows');
    Assert.AreEqual('Plugin b', C.CategorySeparatorTitle(1, 4));
    Assert.AreEqual('Plugin c', C.CategorySeparatorTitle(1, 6));
    Assert.AreEqual('', C.CategorySeparatorTitle(1, 2), 'a command row has no line title');
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.PluginWithoutNameIsShownById;
var
  C: TTopMenuController;
  D: TPluginMenuItemDesc;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    D := Desc('some.id', 'Plugins', 'X', 1);
    D.PluginTitle := '';
    C.SetPluginMenuItems([D]);
    Assert.AreEqual('some.id', C.CategorySeparatorTitle(1, 1));
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.ParentNameOfTheItemDoesNotMatter;
var
  C: TTopMenuController;
begin
  SetLocale('en');
  C := TTopMenuController.Create(nil, nil, nil);
  try
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems([Desc('a', 'Commands', 'A1', 10)]);
    Assert.AreEqual('', Items(C, 0), 'nothing lands in the named category');
    Assert.AreEqual('Plugins...|-|A1|', Items(C, 1));
  finally
    C.Free;
  end;
end;

procedure TTestPluginMenu.PluginsMenuIsTranslated;
var
  C: TTopMenuController;
begin
  C := TTopMenuController.Create(nil, nil, nil);
  try
    SetLocale('ru');
    Assert.IsTrue(C.LoadMenuFromJson(cMenuJson));
    C.SetPluginMenuItems([Desc('a', 'Plugins', 'A1', 10)]);
    Assert.AreEqual('Плагины', C.CategoryTitle(1));
    Assert.AreEqual('Плагины...', C.CategoryItemCaption(1, 0));
  finally
    C.Free;
    SetLocale('en');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginMenu);

end.
