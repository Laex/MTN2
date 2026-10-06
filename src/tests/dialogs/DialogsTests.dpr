program DialogsTests;

{ DUnitX runner for the dialogs tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestAskSaveRoundTrip in 'TestAskSaveRoundTrip.pas',
  TestColorPickerControl in 'TestColorPickerControl.pas',
  TestConsoleSettings in 'TestConsoleSettings.pas',
  TestDialogHistory in 'TestDialogHistory.pas',
  TestDialogMnemonics in 'TestDialogMnemonics.pas',
  TestDialogAlignment in 'TestDialogAlignment.pas',
  TestDialogButtonLayout in 'TestDialogButtonLayout.pas',
  TestDialogTranslatedFit in 'TestDialogTranslatedFit.pas',
  TestDialogCaptionFit in 'TestDialogCaptionFit.pas',
  TestDialogTranslation in 'TestDialogTranslation.pas',
  TestDialogJson in 'TestDialogJson.pas',
  TestDialogRenderer in 'TestDialogRenderer.pas',
  TestDisplaySettings in 'TestDisplaySettings.pas',
  TestReplaceAskDialog in 'TestReplaceAskDialog.pas',
  TestFolderHotlistDialog in 'TestFolderHotlistDialog.pas',
  TestHistoryDialogs in 'TestHistoryDialogs.pas',
  TestIOErrorAskDialog in 'TestIOErrorAskDialog.pas',
  TestPanelFilterDialog in 'TestPanelFilterDialog.pas',
  TestSetAttrDialog in 'TestSetAttrDialog.pas',
  TestThemeDialogs in 'TestThemeDialogs.pas',
  TestSshConnectionsDialog in 'TestSshConnectionsDialog.pas',
  TestPluginDialogs in 'TestPluginDialogs.pas';

begin
  RunRegisteredTests;
end.
