program ConsoleTests;

{ DUnitX runner for the console tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestANSIParser in 'TestANSIParser.pas',
  TestCmdBackspaceFlow in 'TestCmdBackspaceFlow.pas',
  TestCmdRepeatedDirNoLineLoss in 'TestCmdRepeatedDirNoLineLoss.pas',
  TestConPtyEncoding in 'TestConPtyEncoding.pas',
  TestConsoleBuffer in 'TestConsoleBuffer.pas',
  TestConsoleBufferCmd in 'TestConsoleBufferCmd.pas',
  TestFindEncoding in 'TestFindEncoding.pas',
  TestLineBufferedBackspace in 'TestLineBufferedBackspace.pas',
  TestPrimaryScreenGrid in 'TestPrimaryScreenGrid.pas',
  TestPsBackspaceFlow in 'TestPsBackspaceFlow.pas',
  TestPsCharByChar in 'TestPsCharByChar.pas',
  TestPsLineBuffered in 'TestPsLineBuffered.pas',
  TestPsPersistent in 'TestPsPersistent.pas',
  TestPsPipeSafeCommand in 'TestPsPipeSafeCommand.pas',
  TestPtySession in 'TestPtySession.pas',
  TestPtyCtrlC in 'TestPtyCtrlC.pas',
  TestPtyPromptCount in 'TestPtyPromptCount.pas',
  TestShellProfileOptions in 'TestShellProfileOptions.pas',
  TestShellProfiles in 'TestShellProfiles.pas',
  TestShellSessions in 'TestShellSessions.pas',
  TestWorkspaceLibrary in 'TestWorkspaceLibrary.pas';

begin
  RunRegisteredTests;
end.
