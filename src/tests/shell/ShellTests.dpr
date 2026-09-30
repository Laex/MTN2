program ShellTests;

{ DUnitX runner for the tests that start real shells through ConPTY and wait
  on their output. They take most of the time of the console tests, so they
  run as a group of their own, at the same time as the rest; run them with
  ..\run-tests.ps1. A new Test*.pas fixture unit in this folder must be added
  to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestCdDirQuote in 'TestCdDirQuote.pas',
  TestPsTwoCommands in 'TestPsTwoCommands.pas',
  TestPtyLifecycle in 'TestPtyLifecycle.pas';

begin
  RunRegisteredTests;
end.
