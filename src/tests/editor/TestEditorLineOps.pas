unit TestEditorLineOps;

{ The whole-line editor commands: sort, remove repeated lines, shift and
  reflow. Each works on an inclusive line range and leaves the rest alone. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorLineOps = class
  public
    [Test] procedure TestSortAscendingIgnoresCase;
    [Test] procedure TestSortDescending;
    [Test] procedure TestSortKeepsEqualLinesInOrder;
    [Test] procedure TestSortWorksOnRangeOnly;
    [Test] procedure TestUniqueKeepsFirstCopy;
    [Test] procedure TestUniqueIsExactMatch;
    [Test] procedure TestShiftRightSkipsBlankLines;
    [Test] procedure TestShiftLeftRemovesSpacesOrOneTab;
    [Test] procedure TestReflowFillsToWidth;
    [Test] procedure TestReflowKeepsParagraphsAndIndent;
    [Test] procedure TestReflowKeepsLongWordWhole;
    [Test] procedure TestRangeIsClampedToDocument;
  end;

implementation

uses
  System.SysUtils, uEditorLineOps;

function Join(const ALines: TArray<string>): string;
var
  S: string;
begin
  Result := '';
  for S in ALines do
    Result := Result + '[' + S + ']';
end;

procedure TTestEditorLineOps.TestSortAscendingIgnoresCase;
begin
  Assert.AreEqual('[apple][Banana][cherry]',
    Join(SortedLines(['cherry', 'Banana', 'apple'], 0, 2, False)));
end;

procedure TTestEditorLineOps.TestSortDescending;
begin
  Assert.AreEqual('[cherry][Banana][apple]',
    Join(SortedLines(['apple', 'cherry', 'Banana'], 0, 2, True)));
end;

procedure TTestEditorLineOps.TestSortKeepsEqualLinesInOrder;
begin
  // Same text up to case: the original order decides, also when descending.
  Assert.AreEqual('[a][A][b]', Join(SortedLines(['b', 'a', 'A'], 0, 2, False)));
  Assert.AreEqual('[b][a][A]', Join(SortedLines(['a', 'A', 'b'], 0, 2, True)));
end;

procedure TTestEditorLineOps.TestSortWorksOnRangeOnly;
begin
  Assert.AreEqual('[b][c]', Join(SortedLines(['z', 'c', 'b', 'a'], 1, 2, False)));
end;

procedure TTestEditorLineOps.TestUniqueKeepsFirstCopy;
begin
  Assert.AreEqual('[b][a][c]', Join(UniqueLines(['b', 'a', 'b', 'c', 'a'], 0, 4)));
end;

procedure TTestEditorLineOps.TestUniqueIsExactMatch;
begin
  Assert.AreEqual('[a][A][a ]', Join(UniqueLines(['a', 'A', 'a ', 'a'], 0, 3)),
    'case and trailing spaces make lines different');
end;

procedure TTestEditorLineOps.TestShiftRightSkipsBlankLines;
begin
  Assert.AreEqual('[    a][][    ' + #9 + 'b]',
    Join(ShiftedLines(['a', '', #9 + 'b'], 0, 2, True)));
end;

procedure TTestEditorLineOps.TestShiftLeftRemovesSpacesOrOneTab;
begin
  Assert.AreEqual('[a][b][  c][d][e]',
    Join(ShiftedLines(['    a', '  b', '      c', #9 + 'd', 'e'], 0, 4, False)));
end;

procedure TTestEditorLineOps.TestReflowFillsToWidth;
begin
  Assert.AreEqual('[aaa bbb][ccc ddd][eee]',
    Join(ReflowedLines(['aaa bbb ccc', 'ddd eee'], 0, 1, 8)));
  Assert.AreEqual('[aaa bbb ccc ddd eee]',
    Join(ReflowedLines(['aaa bbb', 'ccc', 'ddd   eee'], 0, 2, 80)));
end;

procedure TTestEditorLineOps.TestReflowKeepsParagraphsAndIndent;
begin
  Assert.AreEqual('[  aa bb][  cc][][xx yy]',
    Join(ReflowedLines(['  aa', 'bb cc', '', 'xx', 'yy'], 0, 4, 8)));
end;

procedure TTestEditorLineOps.TestReflowKeepsLongWordWhole;
begin
  Assert.AreEqual('[ab][abcdefghij][cd]',
    Join(ReflowedLines(['ab abcdefghij cd'], 0, 0, 5)));
end;

procedure TTestEditorLineOps.TestRangeIsClampedToDocument;
begin
  Assert.AreEqual('[a][b]', Join(SortedLines(['b', 'a'], -3, 99, False)));
  Assert.AreEqual('', Join(SortedLines(['b', 'a'], 1, 0, False)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorLineOps);

end.
