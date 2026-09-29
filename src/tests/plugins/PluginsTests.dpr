program PluginsTests;

{ DUnitX runner for the plugins tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestPanelPluginRegistry in 'TestPanelPluginRegistry.pas',
  TestPluginHostAbi in 'TestPluginHostAbi.pas',
  TestPluginLoader in 'TestPluginLoader.pas',
  TestPluginManifest in 'TestPluginManifest.pas',
  TestSevenZipPlugin in 'TestSevenZipPlugin.pas',
  TestSevenZipEncrypted in 'TestSevenZipEncrypted.pas',
  TestTmpPanelPlugin in 'TestTmpPanelPlugin.pas',
  TestWasmHost in 'TestWasmHost.pas',
  TestWorkspacePlugin in 'TestWorkspacePlugin.pas';

begin
  RunRegisteredTests;
end.
