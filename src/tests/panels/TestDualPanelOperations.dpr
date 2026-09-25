program TestDualPanelOperations;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uAssociations in '..\..\Core\uAssociations.pas',
  uDualPanelOperations in '..\..\Core\uDualPanelOperations.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestFolderSegments;
var
  Clean, Select, Err: string;
begin
  Writeln('ValidateFolderSegments');
  Expect(not TDualPanelOperationsController.ValidateFolderSegments('', Clean, Select, Err),
    'empty name rejected');
  Expect(Err = 'Name is empty', 'empty name message');

  Expect(not TDualPanelOperationsController.ValidateFolderSegments('   ///', Clean, Select, Err),
    'slash-only name rejected');

  Expect(not TDualPanelOperationsController.ValidateFolderSegments('C:\abs', Clean, Select, Err),
    'rooted path rejected');
  Expect(Pos('relative', Err) > 0, 'rooted path says relative');

  Expect(not TDualPanelOperationsController.ValidateFolderSegments('foo\..', Clean, Select, Err),
    '.. segment rejected');
  Expect(Err = 'Invalid folder name', '.. message');

  Expect(not TDualPanelOperationsController.ValidateFolderSegments('bad:name', Clean, Select, Err),
    'colon rejected');
  Expect(Err = 'Name contains invalid characters', 'invalid-char message');

  Expect(TDualPanelOperationsController.ValidateFolderSegments('a/b\c', Clean, Select, Err),
    'nested relative accepted');
  Expect(Clean = 'a' + PathDelim + 'b' + PathDelim + 'c', 'nested name joined');
  Expect(Select = 'a', 'select first segment');
  Expect(Err = '', 'no error on success');
end;

procedure TestRenameName;
var
  Err: string;
begin
  Writeln('ValidateRenameName');
  Expect(not TDualPanelOperationsController.ValidateRenameName('  ', Err), 'empty rename rejected');
  Expect(Err = 'Name is empty', 'empty rename message');

  Expect(not TDualPanelOperationsController.ValidateRenameName('a\b', Err), 'backslash rejected');
  Expect(not TDualPanelOperationsController.ValidateRenameName('a/b', Err), 'slash rejected');
  Expect(not TDualPanelOperationsController.ValidateRenameName('a:b', Err), 'colon rejected');
  Expect(Pos('separators', Err) > 0, 'separator message');

  Expect(TDualPanelOperationsController.ValidateRenameName('  new.txt  ', Err), 'plain name accepted');
  Expect(Err = '', 'no error on rename success');
end;

procedure TestClassifyActivateCurrent;
begin
  Writeln('ClassifyActivateCurrent');
  Expect(ClassifyActivateCurrent(True, True, True, True, aaEdit) = ackFindGoto,
    'find hit wins');
  Expect(ClassifyActivateCurrent(False, True, True, False, aaView) = ackHistoryBack,
    'recycle/sys parent goes back');
  Expect(ClassifyActivateCurrent(False, False, True, True, aaView) = ackNavigate,
    'dir wins over zip');
  Expect(ClassifyActivateCurrent(False, False, False, True, aaView) = ackZipNavigate,
    'zip file navigates archive');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaEdit) = ackEdit,
    'assoc edit');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaShell) = ackShell,
    'assoc shell');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaView) = ackView,
    'assoc view');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaNone) = ackView,
    'unknown assoc views');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaNavigate) = ackNavigate,
    'assoc navigate');
  Expect(ClassifyActivateCurrent(False, False, False, False, aaCommand) = ackCommand,
    'assoc command (user-defined rule)');
end;

begin
  try
    TestFolderSegments;
    TestRenameName;
    TestClassifyActivateCurrent;
    Writeln('All DualPanelOperations tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
