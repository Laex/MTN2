program ConsoleTests;

{ DUnitX runner for the console tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestANSIParser in 'TestANSIParser.pas',
  TestCdDirQuote in 'TestCdDirQuote.pas',
  TestCmdBackspaceFlow in 'TestCmdBackspaceFlow.pas',
  TestCmdBatch in 'TestCmdBatch.pas',
  TestCmdBsEcho in 'TestCmdBsEcho.pas',
  TestCmdCharEcho in 'TestCmdCharEcho.pas',
  TestCmdRepeatedDirNoLineLoss in 'TestCmdRepeatedDirNoLineLoss.pas',
  TestConPtyEncoding in 'TestConPtyEncoding.pas',
  TestConsoleBuffer in 'TestConsoleBuffer.pas',
  TestConsoleBufferCmd in 'TestConsoleBufferCmd.pas',
  TestFindEncoding in 'TestFindEncoding.pas',
  TestInspectLxss in 'TestInspectLxss.pas',
  TestLineBufferedBackspace in 'TestLineBufferedBackspace.pas',
  TestPrimaryScreenGrid in 'TestPrimaryScreenGrid.pas',
  TestPsBackspaceFlow in 'TestPsBackspaceFlow.pas',
  TestPsBatch in 'TestPsBatch.pas',
  TestPsCharByChar in 'TestPsCharByChar.pas',
  TestPsCmds in 'TestPsCmds.pas',
  TestPsCommands in 'TestPsCommands.pas',
  TestPsDirBetween in 'TestPsDirBetween.pas',
  TestPsDirOnly in 'TestPsDirOnly.pas',
  TestPsDirOnly2 in 'TestPsDirOnly2.pas',
  TestPsDirTiming in 'TestPsDirTiming.pas',
  TestPsEchoThenLs in 'TestPsEchoThenLs.pas',
  TestPsImmediate in 'TestPsImmediate.pas',
  TestPsLineBuffered in 'TestPsLineBuffered.pas',
  TestPsPersistent in 'TestPsPersistent.pas',
  TestPsPipeSafeCommand in 'TestPsPipeSafeCommand.pas',
  TestPsRawDump in 'TestPsRawDump.pas',
  TestPsSequence in 'TestPsSequence.pas',
  TestPsTwoCommands in 'TestPsTwoCommands.pas',
  TestPsTwoEcho in 'TestPsTwoEcho.pas',
  TestPsWhich in 'TestPsWhich.pas',
  TestPtyLifecycle in 'TestPtyLifecycle.pas',
  TestPtySession in 'TestPtySession.pas',
  TestShellBackspaceOutput in 'TestShellBackspaceOutput.pas',
  TestShellProfiles in 'TestShellProfiles.pas',
  TestWorkspaceLibrary in 'TestWorkspaceLibrary.pas';

begin
  RunRegisteredTests;
end.
