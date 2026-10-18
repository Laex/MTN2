unit TestMultiRename;

{ Batch rename rules: masks, counter, search and replace, letter case, and
  the checks that keep a batch from clobbering names. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMultiRename = class
  public
    [Test] procedure TestDefaultRulesKeepNames;
    [Test] procedure TestMaskKeepsOldNameAndExtension;
    [Test] procedure TestCounterStartStepAndDigits;
    [Test] procedure TestSearchReplaceIgnoresCaseUnlessAsked;
    [Test] procedure TestSearchReplaceReachesExtension;
    [Test] procedure TestLetterCases;
    [Test] procedure TestFoldersHaveNoExtension;
    [Test] procedure TestDotFilesKeepTheirName;
    [Test] procedure TestUnknownBracketsStayLiteral;
    [Test] procedure TestPlanMarksUnchangedAndEmpty;
    [Test] procedure TestPlanRejectsInvalidCharacters;
    [Test] procedure TestPlanRejectsDuplicatesInBatch;
    [Test] procedure TestPlanRejectsNamesOfOtherItems;
    [Test] procedure TestCaseOnlyChangeIsAllowed;
    [Test] procedure TestPlanCounts;
  end;

implementation

uses
  System.SysUtils, uMultiRename, uPlatformPaths;

function Rules(const AName, AExt: string): TMultiRenameRules;
begin
  Result := DefaultMultiRenameRules;
  Result.NameMask := AName;
  Result.ExtMask := AExt;
end;

procedure TTestMultiRename.TestDefaultRulesKeepNames;
begin
  Assert.AreEqual('photo.jpg', MultiRenameName('photo.jpg', False, 0, DefaultMultiRenameRules));
  Assert.AreEqual('archive.tar.gz',
    MultiRenameName('archive.tar.gz', False, 3, DefaultMultiRenameRules),
    'only the last dot starts the extension');
end;

procedure TTestMultiRename.TestMaskKeepsOldNameAndExtension;
begin
  Assert.AreEqual('new_photo.txt', MultiRenameName('photo.jpg', False, 0, Rules('new_[N]', 'txt')));
  Assert.AreEqual('photo.JPG.jpg', MultiRenameName('photo.jpg', False, 0, Rules('[N].JPG', '[E]')));
  Assert.AreEqual('photo', MultiRenameName('photo.jpg', False, 0, Rules('[N]', '')),
    'an empty extension mask drops the extension');
end;

procedure TTestMultiRename.TestCounterStartStepAndDigits;
var
  R: TMultiRenameRules;
begin
  R := Rules('img[C]', '[E]');
  R.CounterStart := 5;
  R.CounterStep := 10;
  R.CounterDigits := 3;
  Assert.AreEqual('img005.png', MultiRenameName('a.png', False, 0, R));
  Assert.AreEqual('img015.png', MultiRenameName('b.png', False, 1, R));
  Assert.AreEqual('img105.png', MultiRenameName('c.png', False, 10, R));
  R.CounterDigits := 1;
  R.CounterStart := 9;
  R.CounterStep := 1;
  Assert.AreEqual('img10.png', MultiRenameName('b.png', False, 1, R));
end;

procedure TTestMultiRename.TestSearchReplaceIgnoresCaseUnlessAsked;
var
  R: TMultiRenameRules;
begin
  R := DefaultMultiRenameRules;
  R.Search := 'old';
  R.Replace := 'new';
  Assert.AreEqual('new new new.txt', MultiRenameName('old OLD Old.txt', False, 0, R));
  R.MatchCase := True;
  Assert.AreEqual('new OLD Old.txt', MultiRenameName('old OLD Old.txt', False, 0, R));
end;

procedure TTestMultiRename.TestSearchReplaceReachesExtension;
var
  R: TMultiRenameRules;
begin
  R := DefaultMultiRenameRules;
  R.Search := 'jpeg';
  R.Replace := 'jpg';
  Assert.AreEqual('a.jpg', MultiRenameName('a.jpeg', False, 0, R));
end;

procedure TTestMultiRename.TestLetterCases;
var
  R: TMultiRenameRules;
begin
  R := DefaultMultiRenameRules;
  R.CaseMode := rcLower;
  Assert.AreEqual('my file.txt', MultiRenameName('My FILE.TXT', False, 0, R));
  R.CaseMode := rcUpper;
  Assert.AreEqual('MY FILE.TXT', MultiRenameName('My file.txt', False, 0, R));
  R.CaseMode := rcFirstUpper;
  Assert.AreEqual('My file_two.txt', MultiRenameName('my FILE_two.txt', False, 0, R),
    'only the first letter of the name is raised; the extension stays');
  R.CaseMode := rcWordsUpper;
  Assert.AreEqual('My File_Two-Part.txt', MultiRenameName('my FILE_two-part.txt', False, 0, R));
end;

procedure TTestMultiRename.TestFoldersHaveNoExtension;
begin
  Assert.AreEqual('v1.2_old', MultiRenameName('v1.2', True, 0, Rules('[N]_old', '[E]')),
    'a folder name is all [N], with no extension');
end;

procedure TTestMultiRename.TestDotFilesKeepTheirName;
begin
  Assert.AreEqual('.gitignore', MultiRenameName('.gitignore', False, 0, DefaultMultiRenameRules));
  Assert.AreEqual('x.gitignore', MultiRenameName('.gitignore', False, 0, Rules('x[N]', '[E]')));
end;

procedure TTestMultiRename.TestUnknownBracketsStayLiteral;
begin
  Assert.AreEqual('[X]a.txt', MultiRenameName('a.txt', False, 0, Rules('[X][N]', '[E]')));
  Assert.AreEqual('a[.txt', MultiRenameName('a.txt', False, 0, Rules('[N][', '[E]')));
end;

procedure TTestMultiRename.TestPlanMarksUnchangedAndEmpty;
var
  Plan: TRenamePlan;
begin
  Plan := PlanMultiRename(['a.txt', 'b.txt'], [False, False], ['a.txt', 'b.txt'],
    Rules('', ''));
  Assert.AreEqual(Ord(rpEmpty), Ord(Plan[0].Problem));
  Plan := PlanMultiRename(['a.txt'], [False], ['a.txt'], DefaultMultiRenameRules);
  Assert.AreEqual(Ord(rpUnchanged), Ord(Plan[0].Problem));
  Assert.IsFalse(RenamePlanBlocked(Plan), 'unchanged names do not block the batch');
  Assert.AreEqual(0, RenamePlanChangeCount(Plan));
end;

procedure TTestMultiRename.TestPlanRejectsInvalidCharacters;
var
  Plan: TRenamePlan;
begin
  Plan := PlanMultiRename(['a.txt'], [False], ['a.txt'], Rules('x/[N]', '[E]'));
  Assert.AreEqual(Ord(rpInvalid), Ord(Plan[0].Problem));
  Assert.IsTrue(RenamePlanBlocked(Plan));
end;

procedure TTestMultiRename.TestPlanRejectsDuplicatesInBatch;
var
  Plan: TRenamePlan;
begin
  Plan := PlanMultiRename(['a.txt', 'b.txt'], [False, False], ['a.txt', 'b.txt'],
    Rules('same', '[E]'));
  Assert.AreEqual(Ord(rpDuplicate), Ord(Plan[0].Problem));
  Assert.AreEqual(Ord(rpDuplicate), Ord(Plan[1].Problem));
  Assert.IsTrue(RenamePlanBlocked(Plan));
end;

procedure TTestMultiRename.TestPlanRejectsNamesOfOtherItems;
var
  R: TMultiRenameRules;
  Plan: TRenamePlan;
begin
  // Folder item that is not in the batch.
  R := Rules('keep', '[E]');
  Plan := PlanMultiRename(['a.txt'], [False], ['a.txt', 'keep.txt'], R);
  Assert.AreEqual(Ord(rpExists), Ord(Plan[0].Problem));
  // Another item of the batch: renaming a->b while b is also renamed is not
  // applied, since the order of the moves would decide the outcome.
  R := Rules('[C]', '[E]');
  R.CounterStart := 2;
  Plan := PlanMultiRename(['1.txt', '2.txt'], [False, False], ['1.txt', '2.txt'], R);
  Assert.AreEqual(Ord(rpExists), Ord(Plan[0].Problem));
end;

procedure TTestMultiRename.TestCaseOnlyChangeIsAllowed;
var
  R: TMultiRenameRules;
  Plan: TRenamePlan;
begin
  if PlatformPosixPaths then
    Exit; // names that differ in case are different files there
  R := DefaultMultiRenameRules;
  R.CaseMode := rcUpper;
  Plan := PlanMultiRename(['a.txt'], [False], ['a.txt'], R);
  Assert.AreEqual(Ord(rpNone), Ord(Plan[0].Problem));
  Assert.AreEqual('A.TXT', Plan[0].NewName);
end;

procedure TTestMultiRename.TestPlanCounts;
var
  R: TMultiRenameRules;
  Plan: TRenamePlan;
begin
  R := Rules('f[C]', '[E]');
  Plan := PlanMultiRename(['a.txt', 'f2.txt', 'c.txt'], [False, False, False],
    ['a.txt', 'f2.txt', 'c.txt'], R);
  Assert.AreEqual('f1.txt', Plan[0].NewName);
  Assert.AreEqual(Ord(rpUnchanged), Ord(Plan[1].Problem));
  Assert.AreEqual('f3.txt', Plan[2].NewName);
  Assert.AreEqual(2, RenamePlanChangeCount(Plan));
  Assert.IsFalse(RenamePlanBlocked(Plan));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMultiRename);

end.
