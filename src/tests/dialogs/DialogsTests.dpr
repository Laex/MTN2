program DialogsTests;

{ DUnitX runner for the dialogs tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestAskSaveRoundTrip in 'TestAskSaveRoundTrip.pas',
  TestDialogHistory in 'TestDialogHistory.pas',
  TestDialogMnemonics in 'TestDialogMnemonics.pas',
  TestDialogCaptionFit in 'TestDialogCaptionFit.pas',
  TestDialogJson in 'TestDialogJson.pas',
  TestDialogRenderer in 'TestDialogRenderer.pas',
  TestDisplaySettings in 'TestDisplaySettings.pas',
  TestHistoryDialogs in 'TestHistoryDialogs.pas',
  TestIOErrorAskDialog in 'TestIOErrorAskDialog.pas',
  TestSetAttrDialog in 'TestSetAttrDialog.pas',
  TestSshConnectionsDialog in 'TestSshConnectionsDialog.pas';

begin
  RunRegisteredTests;
end.
