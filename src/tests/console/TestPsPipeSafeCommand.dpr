program TestPsPipeSafeCommand;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uShellProfiles in '..\..\Core\uShellProfiles.pas';

procedure Expect(const AActual, AExpected, AMsg: string);
begin
  if AActual = AExpected then
    Writeln('  OK  ', AMsg)
  else
    raise Exception.CreateFmt('FAIL %s: expected "%s", got "%s"', [AMsg, AExpected, AActual]);
end;

procedure TestKnownAliases;
begin
  Writeln('TestKnownAliases');
  Expect(PsPipeSafeCommand('ls'), '(Get-ChildItem).Name', 'ls rewritten');
  Expect(PsPipeSafeCommand('dir'), '(Get-ChildItem).Name', 'dir rewritten');
  Expect(PsPipeSafeCommand('gci'), '(Get-ChildItem).Name', 'gci rewritten');
  Expect(PsPipeSafeCommand('Get-ChildItem'), '(Get-ChildItem).Name', 'Get-ChildItem rewritten');
end;

procedure TestGenericWrap;
begin
  Writeln('TestGenericWrap');
  Expect(PsPipeSafeCommand('Get-Date'), 'Get-Date | % {"$_"}', 'bare cmdlet wrapped');
  Expect(PsPipeSafeCommand('Get-Process -Id 123'), 'Get-Process -Id 123 | % {"$_"}',
    'cmdlet with args wrapped');
  Expect(PsPipeSafeCommand('1+1'), '1+1 | % {"$_"}', 'arithmetic wrapped');
  Expect(PsPipeSafeCommand('$x'), '$x | % {"$_"}', 'bare variable wrapped');
  Expect(PsPipeSafeCommand('sdfsdf'), 'sdfsdf | % {"$_"}', 'unknown command wrapped (no hang either way)');
end;

procedure TestNeverWrapped;
begin
  Writeln('TestNeverWrapped');
  Expect(PsPipeSafeCommand('$x = 5'), '$x = 5', 'assignment left untouched (type-corruption risk)');
  Expect(PsPipeSafeCommand('$x += 1'), '$x += 1', 'compound assignment left untouched');
  Expect(PsPipeSafeCommand('Get-Process; Get-Date'), 'Get-Process; Get-Date',
    'multi-statement left untouched');
  Expect(PsPipeSafeCommand('Get-Process | Where-Object {$_.CPU -gt 10}'),
    'Get-Process | Where-Object {$_.CPU -gt 10}', 'script block left untouched');
  Expect(PsPipeSafeCommand('if ($true) { "yes" }'), 'if ($true) { "yes" }',
    'if statement left untouched');
  Expect(PsPipeSafeCommand('function foo { "hi" }'), 'function foo { "hi" }',
    'function definition left untouched');
  Expect(PsPipeSafeCommand('foreach ($i in 1..3) { $i }'), 'foreach ($i in 1..3) { $i }',
    'foreach left untouched');
  Expect(PsPipeSafeCommand(''), '', 'empty command left untouched');
end;

procedure TestAlreadyFormatted;
begin
  Writeln('TestAlreadyFormatted');
  Expect(PsPipeSafeCommand('Get-Process | Format-Table'), 'Get-Process | Format-Table',
    'explicit Format-Table left untouched (no double-wrap)');
  Expect(PsPipeSafeCommand('Get-Date | Out-String'), 'Get-Date | Out-String',
    'explicit Out-String left untouched (no double-wrap)');
  Expect(PsPipeSafeCommand('Get-Process | ft'), 'Get-Process | ft',
    'explicit ft alias left untouched (no double-wrap)');
end;

begin
  try
    TestKnownAliases;
    TestGenericWrap;
    TestNeverWrapped;
    TestAlreadyFormatted;
    Writeln('TestPsPipeSafeCommand passed.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
