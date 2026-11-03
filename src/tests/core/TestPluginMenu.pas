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
    [Test] procedure ItemsAreGroupedByPluginWithNamedLines;
    [Test] procedure PluginWithoutNameIsShownById;
    [Test] procedure ParentNameOfTheItemDoesNotMatter;
    [Test] procedure PluginsMenuIsTranslated;
  end;

implementation

uses
  System.SysUtils,
  uStrings, uTopMenuBar;

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
