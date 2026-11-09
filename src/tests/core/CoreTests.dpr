program CoreTests;

{ DUnitX runner for the core tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestAnsiFrame in 'TestAnsiFrame.pas',
  TestOpenWith in 'TestOpenWith.pas',
  TestCharWidth in 'TestCharWidth.pas',
  TestChineseStrings in 'TestChineseStrings.pas',
  TestGermanStrings in 'TestGermanStrings.pas',
  TestConfigLocation in 'TestConfigLocation.pas',
  TestDiffMerge in 'TestDiffMerge.pas',
  TestConfigMode in 'TestConfigMode.pas',
  TestDescriptIon in 'TestDescriptIon.pas',
  TestElevatedProtocol in 'TestElevatedProtocol.pas',
  TestFdoIcons in 'TestFdoIcons.pas',
  TestFrameStats in 'TestFrameStats.pas',
  TestHelpContext in 'TestHelpContext.pas',
  TestFolderHotlist in 'TestFolderHotlist.pas',
  TestFolderFrecent in 'TestFolderFrecent.pas',
  TestRowDecorations in 'TestRowDecorations.pas',
  TestFunctionBarHints in 'TestFunctionBarHints.pas',
  TestHiddenDialogs in 'TestHiddenDialogs.pas',
  TestKeymap in 'TestKeymap.pas',
  TestKeyChord in 'TestKeyChord.pas',
  TestKeyHints in 'TestKeyHints.pas',
  TestLiveReload in 'TestLiveReload.pas',
  TestLocalePacks in 'TestLocalePacks.pas',
  TestColumnSets in 'TestColumnSets.pas',
  TestMaskGroups in 'TestMaskGroups.pas',
  TestPluginInputChord in 'TestPluginInputChord.pas',
  TestResourceScripts in 'TestResourceScripts.pas',
  TestMessageBus in 'TestMessageBus.pas',
  TestCellEdges in 'TestCellEdges.pas',
  TestMenuNavigation in 'TestMenuNavigation.pas',
  TestPluginMenu in 'TestPluginMenu.pas',
  TestSelfCheck in 'TestSelfCheck.pas',
  TestCliInfo in 'TestCliInfo.pas',
  TestSettingsTransfer in 'TestSettingsTransfer.pas',
  TestStrings in 'TestStrings.pas',
  TestConsoleLaunch in 'TestConsoleLaunch.pas',
  TestTerminalRenderer in 'TestTerminalRenderer.pas',
  TestCommandLineQuoting in 'TestCommandLineQuoting.pas',
  TestSafePath in 'TestSafePath.pas',
  TestTermInput in 'TestTermInput.pas',
  TestThemeSpec in 'TestThemeSpec.pas',
  TestToast in 'TestToast.pas',
  TestUpdater in 'TestUpdater.pas',
  TestUpdateCli in 'TestUpdateCli.pas',
  TestStartupTargets in 'TestStartupTargets.pas',
  TestEnvProfiles in 'TestEnvProfiles.pas',
  TestAsciiSharks in 'TestAsciiSharks.pas',
  TestDesktopEntry in 'TestDesktopEntry.pas';

begin
  RunRegisteredTests;
end.
