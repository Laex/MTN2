program CoreTests;

{ DUnitX runner for the core tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestConfigLocation in 'TestConfigLocation.pas',
  TestFrameStats in 'TestFrameStats.pas',
  TestHelpContext in 'TestHelpContext.pas',
  TestKeymap in 'TestKeymap.pas',
  TestLiveReload in 'TestLiveReload.pas',
  TestMessageBus in 'TestMessageBus.pas',
  TestSelfCheck in 'TestSelfCheck.pas',
  TestStrings in 'TestStrings.pas',
  TestToast in 'TestToast.pas',
  TestUpdater in 'TestUpdater.pas';

begin
  RunRegisteredTests;
end.
