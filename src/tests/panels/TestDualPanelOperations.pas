unit TestDualPanelOperations;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelOperations = class
  public
    [Test] procedure TestFolderSegments;
    [Test] procedure TestRenameName;
    [Test] procedure TestClassifyActivateCurrent;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uAssociations,
  uDualPanelOperations;

procedure TestFolderSegments;
var
  Clean, Select, Err: string;
begin
  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('', Clean, Select, Err),
    'empty name rejected');
  Assert.IsTrue(Err = 'Name is empty', 'empty name message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('   ///', Clean, Select, Err),
    'slash-only name rejected');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('C:\abs', Clean, Select, Err),
    'rooted path rejected');
  Assert.IsTrue(Pos('relative', Err) > 0, 'rooted path says relative');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('foo\..', Clean, Select, Err),
    '.. segment rejected');
  Assert.IsTrue(Err = 'Invalid folder name', '.. message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateFolderSegments('bad:name', Clean, Select, Err),
    'colon rejected');
  Assert.IsTrue(Err = 'Name contains invalid characters', 'invalid-char message');

  Assert.IsTrue(TDualPanelOperationsController.ValidateFolderSegments('a/b\c', Clean, Select, Err),
    'nested relative accepted');
  Assert.IsTrue(Clean = 'a' + PathDelim + 'b' + PathDelim + 'c', 'nested name joined');
  Assert.IsTrue(Select = 'a', 'select first segment');
  Assert.IsTrue(Err = '', 'no error on success');
end;

procedure TestRenameName;
var
  Err: string;
begin
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('  ', Err), 'empty rename rejected');
  Assert.IsTrue(Err = 'Name is empty', 'empty rename message');

  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a\b', Err), 'backslash rejected');
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a/b', Err), 'slash rejected');
  Assert.IsTrue(not TDualPanelOperationsController.ValidateRenameName('a:b', Err), 'colon rejected');
  Assert.IsTrue(Pos('separators', Err) > 0, 'separator message');

  Assert.IsTrue(TDualPanelOperationsController.ValidateRenameName('  new.txt  ', Err), 'plain name accepted');
  Assert.IsTrue(Err = '', 'no error on rename success');
end;

procedure TestClassifyActivateCurrent;
begin
  Assert.IsTrue(ClassifyActivateCurrent(True, True, True, True, aaEdit) = ackFindGoto,
    'find hit wins');
  Assert.IsTrue(ClassifyActivateCurrent(False, True, True, False, aaView) = ackHistoryBack,
    'recycle/sys parent goes back');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, True, True, aaView) = ackNavigate,
    'dir wins over zip');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, True, aaView) = ackZipNavigate,
    'zip file navigates archive');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaEdit) = ackEdit,
    'assoc edit');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaShell) = ackShell,
    'assoc shell');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaView) = ackView,
    'assoc view');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaNone) = ackView,
    'unknown assoc views');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaNavigate) = ackNavigate,
    'assoc navigate');
  Assert.IsTrue(ClassifyActivateCurrent(False, False, False, False, aaCommand) = ackCommand,
    'assoc command (user-defined rule)');
end;

{ TTestDualPanelOperations }

procedure TTestDualPanelOperations.TestFolderSegments;
begin
  TestDualPanelOperations.TestFolderSegments;
end;

procedure TTestDualPanelOperations.TestRenameName;
begin
  TestDualPanelOperations.TestRenameName;
end;

procedure TTestDualPanelOperations.TestClassifyActivateCurrent;
begin
  TestDualPanelOperations.TestClassifyActivateCurrent;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelOperations);

end.
