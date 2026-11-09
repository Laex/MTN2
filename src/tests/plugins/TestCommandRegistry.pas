unit TestCommandRegistry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandRegistry = class
  public
    [Test] procedure TestHookInterceptsBuiltInCommand;
    [Test] procedure TestHooksRunInPriorityOrderUntilHandled;
    [Test] procedure TestInvalidHookRegistrationsAreIgnored;
    [Test] procedure TestFaultyHookDoesNotBlockTheChain;
    [Test] procedure TestHookIsNotReentered;
    [Test] procedure TestPluginCommandLifecycle;
    [Test] procedure TestCommandBindingMatchesChord;
    [Test] procedure TestCommandBindingYieldsToCoreAndEarlierPlugin;
    [Test] procedure TestCommandBindingRefusesKeysHandledInCode;
    [Test] procedure TestKeymapRegistryRefusesKeyOfAnotherAction;
    [Test] procedure TestInterceptKeymapAction;
    [Test] procedure TestDeclaredCommandLoadsPluginOnUse;
    [Test] procedure TestDeclaredCommandFailsWhenPluginDoesNotLoad;
    [Test] procedure TestDeclaredBindingIsIdempotent;
    [Test] procedure TestDeclaredMenuItemsAreReconciled;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap, uKeymapRegistry,
  uCommandRegistry, uMenuRegistry;

procedure TestHookInterceptsBuiltInCommand;
var
  Seen, Origin: string;
begin
  try
    CommandRegistry.RegisterHook('t.hook', 'copy',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Seen := ACommand;
        Origin := AOrigin;
        Result := True;
      end);
    Assert.IsTrue(CommandRegistry.TryIntercept('Copy', 'menu'), 'hook handles Copy');
    Assert.IsTrue(Seen = 'Copy', 'hook gets the canonical command name');
    Assert.IsTrue(Origin = 'menu', 'hook gets the origin');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Move', 'key'), 'other commands are untouched');
    CommandRegistry.UnregisterPlugin('t.hook');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Copy', 'key'),
      'unregistering the plugin removes its hooks');
  finally
    CommandRegistry.UnregisterPlugin('t.hook');
  end;
end;

procedure TestHooksRunInPriorityOrderUntilHandled;
var
  Order: string;
begin
  try
    CommandRegistry.RegisterHook('t.late', 'Delete',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Order := Order + 'late;';
        Result := True;
      end, 200);
    CommandRegistry.RegisterHook('t.pass', 'Delete',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Order := Order + 'pass;';
        Result := False;
      end, 10);
    CommandRegistry.RegisterHook('t.first', 'Delete',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Order := Order + 'first;';
        Result := True;
      end, 50);
    Assert.IsTrue(CommandRegistry.TryIntercept('Delete', 'key'), 'chain handled');
    Assert.IsTrue(Order = 'pass;first;', 'ascending priority, stops at the first handler: ' + Order);
  finally
    CommandRegistry.UnregisterPlugin('t.late');
    CommandRegistry.UnregisterPlugin('t.pass');
    CommandRegistry.UnregisterPlugin('t.first');
  end;
end;

procedure TestInvalidHookRegistrationsAreIgnored;
var
  Ran: Boolean;
  Hook: TCommandHook;
begin
  Ran := False;
  Hook :=
    function(const ACommand, AOrigin: string): Boolean
    begin
      Ran := True;
      Result := True;
    end;
  try
    CommandRegistry.RegisterHook('t.bad', 'NoSuchCommand', Hook);
    CommandRegistry.RegisterHook('', 'Copy', Hook);
    CommandRegistry.RegisterHook('t.bad', 'Copy', nil);
    Assert.IsTrue(not CommandRegistry.TryIntercept('NoSuchCommand', 'key'), 'unknown name');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Copy', 'key'), 'no plugin id / no hook');
    Assert.IsTrue(not Ran, 'no ignored hook ran');
  finally
    CommandRegistry.UnregisterPlugin('t.bad');
  end;
end;

procedure TestFaultyHookDoesNotBlockTheChain;
begin
  try
    CommandRegistry.RegisterHook('t.boom', 'Move',
      function(const ACommand, AOrigin: string): Boolean
      begin
        raise Exception.Create('plugin failure');
      end, 1);
    Assert.IsTrue(not CommandRegistry.TryIntercept('Move', 'key'),
      'a hook that raises counts as not handled');
    CommandRegistry.RegisterHook('t.ok', 'Move',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Result := True;
      end, 2);
    Assert.IsTrue(CommandRegistry.TryIntercept('Move', 'key'),
      'the next hook still runs after one raised');
  finally
    CommandRegistry.UnregisterPlugin('t.boom');
    CommandRegistry.UnregisterPlugin('t.ok');
  end;
end;

procedure TestHookIsNotReentered;
var
  Calls: Integer;
  InnerResult: Boolean;
begin
  Calls := 0;
  InnerResult := True;
  try
    CommandRegistry.RegisterHook('t.re', 'Rename',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Inc(Calls);
        InnerResult := CommandRegistry.TryIntercept('Rename', 'key');
        Result := False;
      end);
    Assert.IsTrue(not CommandRegistry.TryIntercept('Rename', 'key'), 'outer call passes through');
    Assert.IsTrue(Calls = 1, 'hook ran once, not recursively');
    Assert.IsTrue(not InnerResult, 'a nested intercept of the running command is skipped');
    CommandRegistry.TryIntercept('Rename', 'key');
    Assert.IsTrue(Calls = 2, 'the guard is released after the call');
  finally
    CommandRegistry.UnregisterPlugin('t.re');
  end;
end;

procedure TestPluginCommandLifecycle;
var
  Ran: Integer;
begin
  Ran := 0;
  try
    CommandRegistry.RegisterCommand('t.a', 'Copy', procedure begin Inc(Ran); end);
    Assert.IsTrue(not CommandRegistry.HasCommand('Copy'), 'a built-in name is refused');
    CommandRegistry.RegisterCommand('t.a', '', procedure begin Inc(Ran); end);
    CommandRegistry.RegisterCommand('', 't.cmd', procedure begin Inc(Ran); end);
    CommandRegistry.RegisterCommand('t.a', 't.cmd', nil);
    Assert.IsTrue(not CommandRegistry.HasCommand('t.cmd'), 'empty id, empty plugin, nil handler');

    CommandRegistry.RegisterCommand('t.a', 't.cmd', procedure begin Inc(Ran); end);
    Assert.IsTrue(CommandRegistry.HasCommand('T.CMD'), 'ids are case-insensitive');
    Assert.IsTrue(CommandRegistry.TryExecute('t.cmd') and (Ran = 1), 'command runs');

    CommandRegistry.RegisterCommand('t.b', 't.cmd', procedure begin Inc(Ran, 100); end);
    CommandRegistry.TryExecute('t.cmd');
    Assert.IsTrue(Ran = 2, 'another plugin cannot take an id that is owned');
    CommandRegistry.RegisterCommand('t.a', 't.cmd', procedure begin Inc(Ran, 10); end);
    CommandRegistry.TryExecute('t.cmd');
    Assert.IsTrue(Ran = 12, 'the owner can replace its handler');

    CommandRegistry.RegisterCommand('t.a', 't.fail',
      procedure begin raise Exception.Create('plugin failure'); end);
    Assert.IsTrue(not CommandRegistry.TryExecute('t.fail'), 'a handler that raises reports failure');
    Assert.IsTrue(not CommandRegistry.TryExecute('t.none'), 'unknown id');

    CommandRegistry.UnregisterPlugin('t.a');
    Assert.IsTrue(not CommandRegistry.HasCommand('t.cmd'), 'unregistering drops the commands');
  finally
    CommandRegistry.UnregisterPlugin('t.a');
    CommandRegistry.UnregisterPlugin('t.b');
  end;
end;

procedure TestCommandBindingMatchesChord;
var
  Ran: Integer;
  Id: string;
begin
  Ran := 0;
  try
    CommandRegistry.RegisterCommandBinding('t.k', 't.key', 'Ctrl+Shift+F9');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift], Id),
      'a binding needs a registered command');
    CommandRegistry.RegisterCommand('t.k', 't.key', procedure begin Inc(Ran); end);
    CommandRegistry.RegisterCommandBinding('t.other', 't.key', 'Ctrl+Shift+F8');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF8, [ssCtrl, ssShift], Id),
      'only the owner binds its command');
    CommandRegistry.RegisterCommandBinding('t.k', 't.key', 'not-a-key');
    CommandRegistry.RegisterCommandBinding('t.k', 't.key', 'Ctrl+Shift+F9');

    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift], Id) and
      (Id = 't.key'), 'chord matches');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF9, [ssCtrl], Id), 'modifiers must match');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift, ssAlt], Id),
      'extra modifier does not match');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF8, [ssCtrl, ssShift], Id), 'key must match');

    Assert.IsTrue(TryRunBoundCommand(vkF9, [ssCtrl, ssShift]) and (Ran = 1), 'chord runs the command');
    Assert.IsTrue(not TryRunBoundCommand(vkF9, []), 'unbound chord runs nothing');

    CommandRegistry.UnregisterPlugin('t.k');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift], Id),
      'unregistering drops the bindings');
  finally
    CommandRegistry.UnregisterPlugin('t.k');
    CommandRegistry.UnregisterPlugin('t.other');
  end;
end;

procedure TestCommandBindingYieldsToCoreAndEarlierPlugin;
var
  Id: string;
  Info: TArray<string>;
  Line: string;
  Reported: Boolean;
begin
  try
    CommandRegistry.RegisterCommand('t.core', 't.core.run', procedure begin end);
    CommandRegistry.RegisterCommand('t.first', 't.first.run', procedure begin end);
    CommandRegistry.RegisterCommand('t.second', 't.second.run', procedure begin end);

    CommandRegistry.RegisterCommandBinding('t.core', 't.core.run', 'F5');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF5, [], Id),
      'a chord of a built-in action is refused');
    Info := CommandRegistry.DescribePlugin('t.core');
    Reported := False;
    for Line in Info do
      if Line.Contains('F5') and Line.Contains(KeymapActionDisplayName(kaCopy)) then
        Reported := True;
    Assert.IsTrue(Reported, 'the plugin information names the action that owns the chord');

    CommandRegistry.RegisterCommandBinding('t.first', 't.first.run', 'Ctrl+Shift+F9');
    CommandRegistry.RegisterCommandBinding('t.second', 't.second.run', 'Ctrl+Shift+F9');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift], Id) and
      (Id = 't.first.run'), 'the earlier plugin keeps the chord');

    CommandRegistry.UnregisterPlugin('t.first');
    CommandRegistry.RegisterCommand('t.first', 't.first.run', procedure begin end);
    CommandRegistry.RegisterCommandBinding('t.first', 't.first.run', 'Ctrl+Shift+F9');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF9, [ssCtrl, ssShift], Id) and
      (Id = 't.first.run'), 'the same plugin rebinds its chord after a reload');
  finally
    CommandRegistry.UnregisterPlugin('t.core');
    CommandRegistry.UnregisterPlugin('t.first');
    CommandRegistry.UnregisterPlugin('t.second');
  end;
end;

procedure TestCommandBindingRefusesKeysHandledInCode;
var
  Id: string;
  Reported: Boolean;
  Line: string;
begin
  try
    CommandRegistry.RegisterCommand('t.reserved', 't.reserved.run', procedure begin end);
    CommandRegistry.RegisterCommandBinding('t.reserved', 't.reserved.run', 'Ctrl+Right');
    CommandRegistry.RegisterCommandBinding('t.reserved', 't.reserved.run', 'Shift+Insert');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkRight, [ssCtrl], Id),
      'a word jump handled in code is refused');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkInsert, [ssShift], Id),
      'a clipboard key handled in code is refused');
    Reported := False;
    for Line in CommandRegistry.DescribePlugin('t.reserved') do
      if Line.Contains('Ctrl+Right') then
        Reported := True;
    Assert.IsTrue(Reported, 'the plugin information lists the refused key');
    CommandRegistry.RegisterCommandBinding('t.reserved', 't.reserved.run', 'Ctrl+Alt+F11');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF11, [ssCtrl, ssAlt], Id),
      'a free chord is bound');
  finally
    CommandRegistry.UnregisterPlugin('t.reserved');
  end;
end;

procedure TestKeymapRegistryRefusesKeyOfAnotherAction;
var
  Profile: TKeymapProfile;
  Act: TKeymapAction;
  Reported: Boolean;
  Line: string;
begin
  try
    KeymapRegistry.RegisterBinding('t.keys', 'Move', 'F5');
    KeymapRegistry.RegisterBinding('t.keys', 'Move', 'Ctrl+Left');
    KeymapRegistry.RegisterBinding('t.keys', 'Copy', 'F5');
    KeymapRegistry.RegisterBinding('t.keys', 'Copy', 'Ctrl+Alt+F11');
    Profile := ActiveKeymap;
    Act := MatchActiveAction(vkF5, []);
    Assert.IsTrue(Act = kaCopy, 'F5 stays with Copy');
    Assert.IsTrue(MatchActiveAction(vkF11, [ssCtrl, ssAlt]) = kaCopy,
      'a free key is added to the action');
    Assert.IsTrue(MatchActiveAction(vkLeft, [ssCtrl]) <> kaMove,
      'a key handled in code is not given to an action');
    Reported := False;
    for Line in KeymapRegistry.DescribePlugin('t.keys') do
      if Line.Contains('Ctrl+Left') then
        Reported := True;
    Assert.IsTrue(Reported, 'the plugin information lists the refused key');
  finally
    KeymapRegistry.UnregisterPlugin('t.keys');
  end;
end;

procedure TestDeclaredCommandLoadsPluginOnUse;
var
  Id: string;
  Ran, Loads: Integer;
  Info: TPluginCommandInfo;
  Found, Reported: Boolean;
  Line: string;
begin
  Ran := 0;
  Loads := 0;
  try
    CommandRegistry.DeclarePlugin('t.decl',
      function: Boolean
      begin
        Inc(Loads);
        CommandRegistry.RegisterCommand('t.decl', 't.decl.run', procedure begin Inc(Ran); end);
        CommandRegistry.RegisterCommandBinding('t.decl', 't.decl.run', 'Ctrl+Alt+F11');
        CommandRegistry.RegisterCommand('t.decl', 't.decl.extra', procedure begin end);
        CommandRegistry.RegisterCommandBinding('t.decl', 't.decl.run', 'Ctrl+Alt+F10');
        Result := True;
      end);
    CommandRegistry.DeclareCommand('t.decl', 't.decl.run', 'Run', 'Ctrl+Alt+F11');
    CommandRegistry.DeclareCommand('t.decl', 't.decl.gone', 'Gone', '');
    Found := False;
    for Info in CommandRegistry.ListCommands do
      if Info.CommandId = 't.decl.run' then
        Found := True;
    Assert.IsTrue(Found, 'a declared command is listed before the plugin loads');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF11, [ssCtrl, ssAlt], Id) and
      (Id = 't.decl.run'), 'its chord works before the plugin loads');
    Assert.AreEqual(0, Loads, 'declaring does not load');

    Assert.IsTrue(CommandRegistry.TryExecute('t.decl.run'), 'running the stub runs the command');
    Assert.AreEqual(1, Loads, 'the first use loads the plugin');
    Assert.AreEqual(1, Ran, 'the real handler runs after the load');
    Assert.IsTrue(CommandRegistry.TryExecute('t.decl.run'));
    Assert.AreEqual(1, Loads, 'the plugin loads once');
    Assert.AreEqual(2, Ran);

    Assert.IsTrue(not CommandRegistry.HasCommand('t.decl.extra'),
      'a command the manifest does not list is refused');
    Assert.IsTrue(not CommandRegistry.TryMatchBinding(vkF10, [ssCtrl, ssAlt], Id),
      'a chord the manifest does not list is refused');
    Assert.IsTrue(not CommandRegistry.HasCommand('t.decl.gone'),
      'a declared command the plugin did not register is dropped');
    Reported := False;
    for Line in CommandRegistry.DescribePlugin('t.decl') do
      if Line.Contains('t.decl.extra') or Line.Contains('t.decl.gone') then
        Reported := True;
    Assert.IsTrue(Reported, 'the plugin information lists the differences');
  finally
    CommandRegistry.UnregisterPlugin('t.decl');
    CommandRegistry.ForgetDeclared('t.decl');
  end;
end;

procedure TestDeclaredCommandFailsWhenPluginDoesNotLoad;
begin
  try
    CommandRegistry.DeclarePlugin('t.broken', function: Boolean begin Result := False; end);
    CommandRegistry.DeclareCommand('t.broken', 't.broken.run', 'Run', '');
    Assert.IsTrue(CommandRegistry.HasCommand('t.broken.run'));
    Assert.IsTrue(not CommandRegistry.TryExecute('t.broken.run'), 'a failed load runs nothing');
    Assert.IsTrue(not CommandRegistry.HasCommand('t.broken.run'), 'the stub is dropped');
  finally
    CommandRegistry.UnregisterPlugin('t.broken');
    CommandRegistry.ForgetDeclared('t.broken');
  end;
end;

procedure TestDeclaredBindingIsIdempotent;
var
  Id: string;
begin
  try
    CommandRegistry.DeclarePlugin('t.idem', function: Boolean begin Result := True; end);
    CommandRegistry.DeclareCommand('t.idem', 't.idem.run', '', 'Ctrl+Alt+F11');
    CommandRegistry.RegisterCommand('t.idem', 't.idem.run', procedure begin end);
    CommandRegistry.RegisterCommandBinding('t.idem', 't.idem.run', 'Ctrl+Alt+F11');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF11, [ssCtrl, ssAlt], Id), 'bound');
    Assert.AreEqual('Ctrl+Alt+F11', CommandRegistry.CommandChordText('t.idem.run'));
    Assert.IsTrue(Length(CommandRegistry.DescribePlugin('t.idem')) = 1,
      'one line for the command, nothing refused');
  finally
    CommandRegistry.UnregisterPlugin('t.idem');
    CommandRegistry.ForgetDeclared('t.idem');
  end;
end;

procedure TestDeclaredMenuItemsAreReconciled;
var
  Lines: TArray<string>;
  Line: string;
  Gone, Extra: Boolean;
begin
  try
    MenuRegistry.DeclarePlugin('t.menu');
    MenuRegistry.DeclareMenuItem('t.menu', 'Plugins', 't.menu.run', 'Run', 10);
    MenuRegistry.DeclareMenuItem('t.menu', 'Plugins', 't.menu.gone', 'Gone', 20);
    MenuRegistry.RegisterMenuItem('t.menu', 'Plugins', 't.menu.run', 'Run it', procedure begin end, 5);
    MenuRegistry.RegisterMenuItem('t.menu', 'Plugins', 't.menu.extra', 'Extra', procedure begin end);
    MenuRegistry.ReconcilePlugin('t.menu');
    Lines := MenuRegistry.DescribePlugin('t.menu');
    Gone := False;
    Extra := False;
    for Line in Lines do
    begin
      if Line.Contains('t.menu.gone') then
        Gone := True;
      if Line.Contains('t.menu.extra') then
        Extra := True;
    end;
    Assert.IsTrue(Gone, 'the dropped declared item is reported');
    Assert.IsTrue(Extra, 'the undeclared item is reported');
    Assert.IsTrue(Length(Lines) = 3, 'one item and two notes');
  finally
    MenuRegistry.UnregisterPlugin('t.menu');
    MenuRegistry.ForgetDeclared('t.menu');
  end;
end;

procedure TestInterceptKeymapAction;
var
  Seen: string;
begin
  try
    CommandRegistry.RegisterHook('t.ka', 'View',
      function(const ACommand, AOrigin: string): Boolean
      begin
        Seen := ACommand + '/' + AOrigin;
        Result := True;
      end);
    Assert.IsTrue(InterceptKeymapAction(kaView, 'key'), 'kaView is the View command');
    Assert.IsTrue(Seen = 'View/key', 'keymap action maps to its command name');
    Assert.IsTrue(not InterceptKeymapAction(kaEdit, 'key'), 'other action');
    Assert.IsTrue(not InterceptKeymapAction(kaNone, 'key'), 'kaNone never intercepts');
  finally
    CommandRegistry.UnregisterPlugin('t.ka');
  end;
end;

{ TTestCommandRegistry }

procedure TTestCommandRegistry.TestHookInterceptsBuiltInCommand;
begin
  TestCommandRegistry.TestHookInterceptsBuiltInCommand;
end;

procedure TTestCommandRegistry.TestHooksRunInPriorityOrderUntilHandled;
begin
  TestCommandRegistry.TestHooksRunInPriorityOrderUntilHandled;
end;

procedure TTestCommandRegistry.TestInvalidHookRegistrationsAreIgnored;
begin
  TestCommandRegistry.TestInvalidHookRegistrationsAreIgnored;
end;

procedure TTestCommandRegistry.TestFaultyHookDoesNotBlockTheChain;
begin
  TestCommandRegistry.TestFaultyHookDoesNotBlockTheChain;
end;

procedure TTestCommandRegistry.TestHookIsNotReentered;
begin
  TestCommandRegistry.TestHookIsNotReentered;
end;

procedure TTestCommandRegistry.TestPluginCommandLifecycle;
begin
  TestCommandRegistry.TestPluginCommandLifecycle;
end;

procedure TTestCommandRegistry.TestCommandBindingMatchesChord;
begin
  TestCommandRegistry.TestCommandBindingMatchesChord;
end;

procedure TTestCommandRegistry.TestCommandBindingYieldsToCoreAndEarlierPlugin;
begin
  TestCommandRegistry.TestCommandBindingYieldsToCoreAndEarlierPlugin;
end;

procedure TTestCommandRegistry.TestCommandBindingRefusesKeysHandledInCode;
begin
  TestCommandRegistry.TestCommandBindingRefusesKeysHandledInCode;
end;

procedure TTestCommandRegistry.TestKeymapRegistryRefusesKeyOfAnotherAction;
begin
  TestCommandRegistry.TestKeymapRegistryRefusesKeyOfAnotherAction;
end;

procedure TTestCommandRegistry.TestInterceptKeymapAction;
begin
  TestCommandRegistry.TestInterceptKeymapAction;
end;

procedure TTestCommandRegistry.TestDeclaredCommandLoadsPluginOnUse;
begin
  TestCommandRegistry.TestDeclaredCommandLoadsPluginOnUse;
end;

procedure TTestCommandRegistry.TestDeclaredCommandFailsWhenPluginDoesNotLoad;
begin
  TestCommandRegistry.TestDeclaredCommandFailsWhenPluginDoesNotLoad;
end;

procedure TTestCommandRegistry.TestDeclaredBindingIsIdempotent;
begin
  TestCommandRegistry.TestDeclaredBindingIsIdempotent;
end;

procedure TTestCommandRegistry.TestDeclaredMenuItemsAreReconciled;
begin
  TestCommandRegistry.TestDeclaredMenuItemsAreReconciled;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandRegistry);

end.
