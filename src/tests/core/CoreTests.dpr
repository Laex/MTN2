program CoreTests;

{ DUnitX runner for the core tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestCharWidth in 'TestCharWidth.pas',
  TestGermanStrings in 'TestGermanStrings.pas',
  TestConfigLocation in 'TestConfigLocation.pas',
  TestDescriptIon in 'TestDescriptIon.pas',
  TestElevatedProtocol in 'TestElevatedProtocol.pas',
  TestFrameStats in 'TestFrameStats.pas',
  TestHelpContext in 'TestHelpContext.pas',
  TestFolderHotlist in 'TestFolderHotlist.pas',
  TestHiddenDialogs in 'TestHiddenDialogs.pas',
  TestKeymap in 'TestKeymap.pas',
  TestKeyChord in 'TestKeyChord.pas',
  TestLiveReload in 'TestLiveReload.pas',
  TestMessageBus in 'TestMessageBus.pas',
  TestSelfCheck in 'TestSelfCheck.pas',
  TestSettingsTransfer in 'TestSettingsTransfer.pas',
  TestStrings in 'TestStrings.pas',
  TestConsoleLaunch in 'TestConsoleLaunch.pas',
  TestTerminalRenderer in 'TestTerminalRenderer.pas',
  TestThemeSpec in 'TestThemeSpec.pas',
  TestToast in 'TestToast.pas',
  TestUpdater in 'TestUpdater.pas';

begin
  RunRegisteredTests;
end.
