program VfsTests;

{ DUnitX runner for the vfs tests; run them with ..\run-tests.ps1. A new
  Test*.pas fixture unit in this folder must be added to the uses clause. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
{$R '..\..\MTN2.dres'}

uses
  uTestRunner in '..\common\uTestRunner.pas',
  TestChecksums in 'TestChecksums.pas',
  TestCopyIntoSelf in 'TestCopyIntoSelf.pas',
  TestCopyLockedSource in 'TestCopyLockedSource.pas',
  TestCopySkipMerge in 'TestCopySkipMerge.pas',
  TestCreateLink in 'TestCreateLink.pas',
  TestDeleteProgress in 'TestDeleteProgress.pas',
  TestDirWatchSlowDrive in 'TestDirWatchSlowDrive.pas',
  TestDriveInfo in 'TestDriveInfo.pas',
  TestExternalTools in 'TestExternalTools.pas',
  TestFileCompare in 'TestFileCompare.pas',
  TestFileFind in 'TestFileFind.pas',
  TestFileVfsScanner in 'TestFileVfsScanner.pas',
  TestLongPaths in 'TestLongPaths.pas',
  TestRecycleBin in 'TestRecycleBin.pas',
  TestRecycleBinFailure in 'TestRecycleBinFailure.pas',
  TestResolveLocalDirPath in 'TestResolveLocalDirPath.pas',
  TestSevenZipUri in 'TestSevenZipUri.pas',
  TestOpenAsArchive in 'TestOpenAsArchive.pas',
  TestSftpVfs in 'TestSftpVfs.pas',
  TestSshConnections in 'TestSshConnections.pas',
  TestUserAssociations in 'TestUserAssociations.pas',
  TestVfsDelete in 'TestVfsDelete.pas',
  TestVfsRegistry in 'TestVfsRegistry.pas',
  TestVfsUtils in 'TestVfsUtils.pas',
  TestWinFileAttr in 'TestWinFileAttr.pas',
  TestWinFileClipboard in 'TestWinFileClipboard.pas',
  TestZipNames in 'TestZipNames.pas';

begin
  RunRegisteredTests;
end.
