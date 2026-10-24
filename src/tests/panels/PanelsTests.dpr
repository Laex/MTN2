program PanelsTests;

{ DUnitX runner for the panels tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestButtonTextClip in 'TestButtonTextClip.pas',
  TestMultiRename in 'TestMultiRename.pas',
  TestMultiRenameKey in 'TestMultiRenameKey.pas',
  TestChromeRows in 'TestChromeRows.pas',
  TestFolderTree in 'TestFolderTree.pas',
  TestInfoPanelBar in 'TestInfoPanelBar.pas',
  TestColorCodingMerge in 'TestColorCodingMerge.pas',
  TestColorSampleRender in 'TestColorSampleRender.pas',
  TestDialogButtonPress in 'TestDialogButtonPress.pas',
  TestDialogHotKeyDraw in 'TestDialogHotKeyDraw.pas',
  TestDialogSeparator in 'TestDialogSeparator.pas',
  TestDirHistoryPopup in 'TestDirHistoryPopup.pas',
  TestColumnModeMenuController in 'TestColumnModeMenuController.pas',
  TestDrivePopup in 'TestDrivePopup.pas',
  TestDriveDisconnect in 'TestDriveDisconnect.pas',
  TestDualPanelClick in 'TestDualPanelClick.pas',
  TestDualPanelCmdLine in 'TestDualPanelCmdLine.pas',
  TestDualPanelCommands in 'TestDualPanelCommands.pas',
  TestDualPanelDrag in 'TestDualPanelDrag.pas',
  TestDualPanelInput in 'TestDualPanelInput.pas',
  TestDualPanelJobChips in 'TestDualPanelJobChips.pas',
  TestDualPanelJobDialogs in 'TestDualPanelJobDialogs.pas',
  TestDualPanelJobRules in 'TestDualPanelJobRules.pas',
  TestDualPanelJobsManager in 'TestDualPanelJobsManager.pas',
  TestDualPanelOperations in 'TestDualPanelOperations.pas',
  TestDualPanelPanelDraw in 'TestDualPanelPanelDraw.pas',
  TestDualPanelStatus in 'TestDualPanelStatus.pas',
  TestDualPanelSync in 'TestDualPanelSync.pas',
  TestDualPanelTabs in 'TestDualPanelTabs.pas',
  TestDualPanelTopMenu in 'TestDualPanelTopMenu.pas',
  TestCommandPalette in 'TestCommandPalette.pas',
  TestMenuScroll in 'TestMenuScroll.pas',
  TestWindowChrome in 'TestWindowChrome.pas',
  TestHistoryPopup in 'TestHistoryPopup.pas',
  TestCmdLinePlatformPaths in 'TestCmdLinePlatformPaths.pas',
  TestJobPopupLayout in 'TestJobPopupLayout.pas',
  TestMarkedRowColors in 'TestMarkedRowColors.pas',
  TestPanelColumns in 'TestPanelColumns.pas',
  TestWidePanelText in 'TestWidePanelText.pas',
  TestPanelCompare in 'TestPanelCompare.pas',
  TestPanelModel in 'TestPanelModel.pas',
  TestPanelSelect in 'TestPanelSelect.pas',
  TestPanelViewController in 'TestPanelViewController.pas',
  TestSearchController in 'TestSearchController.pas',
  TestShellIcons in 'TestShellIcons.pas',
  TestSortMenuController in 'TestSortMenuController.pas',
  TestStatusSegments in 'TestStatusSegments.pas',
  TestStubController in 'TestStubController.pas',
  TestTopMenuBar in 'TestTopMenuBar.pas',
  TestPicturePreview in 'TestPicturePreview.pas',
  TestHostShell in 'TestHostShell.pas',
  TestKeyRouting in 'TestKeyRouting.pas',
  TestThemeController in 'TestThemeController.pas',
  TestUserMenuController in 'TestUserMenuController.pas';

begin
  RunRegisteredTests;
end.
