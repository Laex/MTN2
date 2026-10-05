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
    [Test] procedure TestInterceptKeymapAction;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap,
  uCommandRegistry;

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

procedure TTestCommandRegistry.TestInterceptKeymapAction;
begin
  TestCommandRegistry.TestInterceptKeymapAction;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandRegistry);

end.
