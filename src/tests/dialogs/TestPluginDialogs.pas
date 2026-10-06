unit TestPluginDialogs;

{ The Plugins list (Space and Ctrl+Up / Ctrl+Down on the list fire commands, no
  buttons for them) and the permissions dialog of one plugin (checkboxes of what
  the plugin may be allowed, packed from the top). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginDialogs = class
  public
    [Test] procedure TestListHasNoButtonsForToggleAndOrder;
    [Test] procedure TestKeysOnTheListFireCommands;
    [Test] procedure TestDoubleClickOnARowIsEnter;
    [Test] procedure TestDelInAListPressesTheDeleteButton;
    [Test] procedure TestPermissionsOfAPluginWithEverything;
    [Test] procedure TestPermissionsAreRepackedWithoutReplacement;
    [Test] procedure TestPluginWithNothingToAllowHasOnlyButtons;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes, uThemeTypes, uDialogTypes, uDialogResources, uDialogHost;

function IndexOf(AHost: TDialogHost; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to AHost.ControlCount - 1 do
    if AHost.GetControl(I).Id = AId then
      Exit(I);
  Result := -1;
end;

procedure TTestPluginDialogs.TestListHasNoButtonsForToggleAndOrder;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginListDialog(['[x] a', '[ ] b'], 0),
      procedure(const AId, AValues: string)
      begin
      end);
    Assert.IsTrue(IndexOf(Host, 'toggle') < 0, 'no Toggle button');
    Assert.IsTrue(IndexOf(Host, 'up') < 0, 'no Up button');
    Assert.IsTrue(IndexOf(Host, 'down') < 0, 'no Down button');
    Assert.IsTrue(IndexOf(Host, 'override') < 0, 'no Replace button');
    Assert.IsTrue(IndexOf(Host, 'permissions') >= 0, 'Permissions');
    Assert.IsTrue(IndexOf(Host, 'cancel') >= 0, 'OK and Cancel are separate buttons');
    Assert.IsTrue(IndexOf(Host, 'ok') >= 0, 'OK');
  finally
    Host.Free;
  end;
end;

procedure TTestPluginDialogs.TestKeysOnTheListFireCommands;
var
  Host: TDialogHost;
  Fired: string;
  Key: Word;
  Ch: Char;
begin
  Fired := '';
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginListDialog(['[x] a', '[ ] b'], 0),
      procedure(const AId, AValues: string)
      begin
        Fired := Fired + AId + ',';
      end);
    Host.FocusControlById('plugins');
    Key := vkSpace;
    Ch := ' ';
    Host.HandleInput(Key, [], Ch);
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [ssCtrl], Ch);
    Key := vkUp;
    Ch := #0;
    Host.HandleInput(Key, [ssCtrl], Ch);
    Assert.AreEqual('toggle,down,up,', Fired, 'Space, Ctrl+Down and Ctrl+Up reach the owner');
    Fired := '';
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Assert.AreEqual('', Fired, 'a plain arrow only moves the selection');
    Assert.AreEqual(1, Host.GetListSelectedIndex('plugins'));
  finally
    Host.Free;
  end;
end;

procedure DrawOnce(AHost: TDialogHost);
var
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  SetLength(Grid, 40);
  for Y := 0 to 39 do
  begin
    SetLength(Grid[Y], 120);
    for X := 0 to 119 do
      Grid[Y][X] := TCharCell.Make(' ', TAlphaColor($FFAAAAAA), TAlphaColor($FF000000));
  end;
  AHost.Draw(Grid, 120, 40);
end;

procedure TTestPluginDialogs.TestDoubleClickOnARowIsEnter;
var
  Host: TDialogHost;
  Fired: string;
  R: TRectI;
begin
  Fired := '';
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginListDialog(['[x] a', '[ ] b', '[x] c'], 0),
      procedure(const AId, AValues: string)
      begin
        Fired := Fired + AId + ',';
      end);
    DrawOnce(Host);
    R := Host.ControlBoundsAt(IndexOf(Host, 'plugins'));
    Host.HandleClick(R.Left + 2, R.Top + 1);
    Assert.AreEqual('', Fired, 'one click only selects the row');
    Assert.AreEqual(1, Host.GetListSelectedIndex('plugins'), 'the row is selected');
    Host.HandleClick(R.Left + 2, R.Top + 1);
    Assert.AreEqual('ok,', Fired, 'the second quick click on it is Enter: the default button');
  finally
    Host.Free;
  end;
end;

procedure TTestPluginDialogs.TestDelInAListPressesTheDeleteButton;
var
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Fired: string;
  Key: Word;
  Ch: Char;
begin
  Fired := '';
  Host := TDialogHost.Create(nil);
  try
    // The Theme dialog is a list with a Delete button.
    RequireDialogResource(cResDialogTheme, Decl);
    DialogSetListItems(Decl, 'themes', ['A', 'B'], 0);
    Host.Open(Decl,
      procedure(const AId, AValues: string)
      begin
        Fired := Fired + AId + ',';
      end);
    Host.FocusControlById('themes');
    Key := vkDelete;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Assert.AreEqual('delete,', Fired, 'Del in the list acts as the Delete button');
  finally
    Host.Free;
  end;
end;

procedure TTestPluginDialogs.TestPermissionsOfAPluginWithEverything;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginPermissionsDialog('mtn.x', 'Asks:', 'replace .zip', True, True,
      ['read files'], [False]),
      procedure(const AId, AValues: string)
      begin
      end);
    Assert.AreEqual('replace .zip', Host.GetControl(IndexOf(Host, 'perm_override')).Text);
    Assert.IsTrue(Host.GetCheckbox('perm_override'), 'replacement is on');
    Assert.AreEqual(3, Host.GetControl(IndexOf(Host, 'perm_override')).Row, 'first row');
    Assert.AreEqual('read files', Host.GetControl(IndexOf(Host, 'perm_0')).Text);
    Assert.IsFalse(Host.GetCheckbox('perm_0'), 'the permission is off');
    Assert.AreEqual(4, Host.GetControl(IndexOf(Host, 'perm_0')).Row, 'second row');
    Assert.IsTrue(IndexOf(Host, 'perm_1') < 0, 'no second permission, no checkbox');
    Assert.IsTrue(IndexOf(Host, 'hint') >= 0, 'the note about replacement');
  finally
    Host.Free;
  end;
end;

procedure TTestPluginDialogs.TestPermissionsAreRepackedWithoutReplacement;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginPermissionsDialog('mtn.x', 'Asks:', 'replace .zip', False, False,
      ['read files'], [True]),
      procedure(const AId, AValues: string)
      begin
      end);
    Assert.IsTrue(IndexOf(Host, 'perm_override') < 0, 'no replacement checkbox');
    Assert.AreEqual(3, Host.GetControl(IndexOf(Host, 'perm_0')).Row, 'the permission moved up');
    Assert.IsTrue(Host.GetCheckbox('perm_0'), 'and is on');
    Assert.IsTrue(IndexOf(Host, 'hint') < 0, 'no note about replacement');
  finally
    Host.Free;
  end;
end;

procedure TTestPluginDialogs.TestPluginWithNothingToAllowHasOnlyButtons;
var
  Host: TDialogHost;
begin
  Host := TDialogHost.Create(nil);
  try
    Host.Open(BuildPluginPermissionsDialog('mtn.x', 'Nothing.', '', False, False, nil, nil),
      procedure(const AId, AValues: string)
      begin
      end);
    Assert.IsTrue((IndexOf(Host, 'perm_override') < 0) and (IndexOf(Host, 'perm_0') < 0) and
      (IndexOf(Host, 'perm_1') < 0), 'no checkboxes');
    Assert.IsTrue((IndexOf(Host, 'ok') >= 0) and (IndexOf(Host, 'cancel') >= 0), 'OK and Cancel');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginDialogs);

end.
