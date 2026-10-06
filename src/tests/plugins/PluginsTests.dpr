program PluginsTests;

{ DUnitX runner for the plugins tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestCommandRegistry in 'TestCommandRegistry.pas',
  TestDocumentProviders in 'TestDocumentProviders.pas',
  TestPanelPluginRegistry in 'TestPanelPluginRegistry.pas',
  TestPluginHostAbi in 'TestPluginHostAbi.pas',
  TestPluginChrome in 'TestPluginChrome.pas',
  TestPluginInfo in 'TestPluginInfo.pas',
  TestPluginSurface in 'TestPluginSurface.pas',
  TestPluginServices in 'TestPluginServices.pas',
  TestPluginHighlight in 'TestPluginHighlight.pas',
  TestPluginVfs in 'TestPluginVfs.pas',
  TestPluginLoader in 'TestPluginLoader.pas',
  TestPluginSettings in 'TestPluginSettings.pas',
  TestPluginUi in 'TestPluginUi.pas',
  TestSamplePlugins in 'TestSamplePlugins.pas',
  TestSevenZipDllWarning in 'TestSevenZipDllWarning.pas',
  TestPluginManifest in 'TestPluginManifest.pas',
  TestSevenZipPlugin in 'TestSevenZipPlugin.pas',
  TestSevenZipOpen in 'TestSevenZipOpen.pas',
  TestTmpPanelPlugin in 'TestTmpPanelPlugin.pas',
  TestWasmHost in 'TestWasmHost.pas',
  TestWorkspacePlugin in 'TestWorkspacePlugin.pas';

begin
  RunRegisteredTests;
end.
