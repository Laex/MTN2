program EditorTests;

{ DUnitX runner for the editor tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestEditorDialogs in 'TestEditorDialogs.pas',
  TestFilePositions in 'TestFilePositions.pas',
  TestEditorInput in 'TestEditorInput.pas',
  TestEditorLayout in 'TestEditorLayout.pas',
  TestEditorPainter in 'TestEditorPainter.pas',
  TestEditorSearchUndo in 'TestEditorSearchUndo.pas',
  TestEditorSearchEngine in 'TestEditorSearchEngine.pas',
  TestEditorFind in 'TestEditorFind.pas',
  TestMarkdownCursor in 'TestMarkdownCursor.pas',
  TestMarkdownParser in 'TestMarkdownParser.pas',
  TestMarkdownColors in 'TestMarkdownColors.pas',
  TestEditorTyping in 'TestEditorTyping.pas',
  TestMarkdownLinks in 'TestMarkdownLinks.pas',
  TestQuickTextView in 'TestQuickTextView.pas',
  TestStreamingArchiveViewer in 'TestStreamingArchiveViewer.pas',
  TestStreamingViewer in 'TestStreamingViewer.pas';

begin
  RunRegisteredTests;
end.
