unit TestPsPipeSafeCommand;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPsPipeSafeCommand = class
  public
    [Test] procedure TestKnownAliases;
    [Test] procedure TestGenericWrap;
    [Test] procedure TestNeverWrapped;
    [Test] procedure TestAlreadyFormatted;
  end;

implementation

uses
  System.SysUtils,
  uShellProfiles;

procedure TestKnownAliases;
begin
  Assert.AreEqual('(Get-ChildItem).Name', PsPipeSafeCommand('ls'), 'ls rewritten');
  Assert.AreEqual('(Get-ChildItem).Name', PsPipeSafeCommand('dir'), 'dir rewritten');
  Assert.AreEqual('(Get-ChildItem).Name', PsPipeSafeCommand('gci'), 'gci rewritten');
  Assert.AreEqual('(Get-ChildItem).Name', PsPipeSafeCommand('Get-ChildItem'), 'Get-ChildItem rewritten');
end;

procedure TestGenericWrap;
begin
  Assert.AreEqual('Get-Date | % {"$_"}', PsPipeSafeCommand('Get-Date'), 'bare cmdlet wrapped');
  Assert.AreEqual('Get-Process -Id 123 | % {"$_"}', PsPipeSafeCommand('Get-Process -Id 123'), 'cmdlet with args wrapped');
  Assert.AreEqual('1+1 | % {"$_"}', PsPipeSafeCommand('1+1'), 'arithmetic wrapped');
  Assert.AreEqual('$x | % {"$_"}', PsPipeSafeCommand('$x'), 'bare variable wrapped');
  Assert.AreEqual('sdfsdf | % {"$_"}', PsPipeSafeCommand('sdfsdf'), 'unknown command wrapped (no hang either way)');
end;

procedure TestNeverWrapped;
begin
  Assert.AreEqual('$x = 5', PsPipeSafeCommand('$x = 5'), 'assignment left untouched (type-corruption risk)');
  Assert.AreEqual('$x += 1', PsPipeSafeCommand('$x += 1'), 'compound assignment left untouched');
  Assert.AreEqual('Get-Process; Get-Date', PsPipeSafeCommand('Get-Process; Get-Date'), 'multi-statement left untouched');
  Assert.AreEqual('Get-Process | Where-Object {$_.CPU -gt 10}', PsPipeSafeCommand('Get-Process | Where-Object {$_.CPU -gt 10}'), 'script block left untouched');
  Assert.AreEqual('if ($true) { "yes" }', PsPipeSafeCommand('if ($true) { "yes" }'), 'if statement left untouched');
  Assert.AreEqual('function foo { "hi" }', PsPipeSafeCommand('function foo { "hi" }'), 'function definition left untouched');
  Assert.AreEqual('foreach ($i in 1..3) { $i }', PsPipeSafeCommand('foreach ($i in 1..3) { $i }'), 'foreach left untouched');
  Assert.AreEqual('', PsPipeSafeCommand(''), 'empty command left untouched');
end;

procedure TestAlreadyFormatted;
begin
  Assert.AreEqual('Get-Process | Format-Table', PsPipeSafeCommand('Get-Process | Format-Table'), 'explicit Format-Table left untouched (no double-wrap)');
  Assert.AreEqual('Get-Date | Out-String', PsPipeSafeCommand('Get-Date | Out-String'), 'explicit Out-String left untouched (no double-wrap)');
  Assert.AreEqual('Get-Process | ft', PsPipeSafeCommand('Get-Process | ft'), 'explicit ft alias left untouched (no double-wrap)');
end;

{ TTestPsPipeSafeCommand }

procedure TTestPsPipeSafeCommand.TestKnownAliases;
begin
  TestPsPipeSafeCommand.TestKnownAliases;
end;

procedure TTestPsPipeSafeCommand.TestGenericWrap;
begin
  TestPsPipeSafeCommand.TestGenericWrap;
end;

procedure TTestPsPipeSafeCommand.TestNeverWrapped;
begin
  TestPsPipeSafeCommand.TestNeverWrapped;
end;

procedure TTestPsPipeSafeCommand.TestAlreadyFormatted;
begin
  TestPsPipeSafeCommand.TestAlreadyFormatted;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPsPipeSafeCommand);

end.
