unit TestDiffMerge;

{ The line model of the compare-and-merge window: rows and hunks, copying a hunk in
  either direction, undo, and splitting/joining that keep line breaks. }

interface

uses
  DUnitX.TestFramework, System.SysUtils, uDiffMerge;

type
  [TestFixture]
  TTestDiffMerge = class
  private
    function Lines(const AItems: array of string): TArray<string>;
    function Joined(const ALines: TArray<string>): string;
  public
    [Test] procedure TestIdenticalTextsHaveNoHunks;
    [Test] procedure TestChangedLineIsOneRowWithBothSides;
    [Test] procedure TestAddedLineIsRightOnly;
    [Test] procedure TestRemovedLineIsLeftOnly;
    [Test] procedure TestNeighbouringChangesFormOneHunk;
    [Test] procedure TestSimilarLinePairsWithItsCounterpartNotItsNeighbour;
    [Test] procedure TestUnrelatedLinesStillPairInPlace;
    [Test] procedure TestExtraLinesBeforeAndAfterThePairKeepOrder;
    [Test] procedure TestCopyToRightMakesRightEqualLeft;
    [Test] procedure TestCopyToLeftMakesLeftEqualRight;
    [Test] procedure TestCopyingOneHunkLeavesTheOthers;
    [Test] procedure TestCopyMarksOnlyTheChangedSideDirty;
    [Test] procedure TestUndoRestoresLinesAndFlags;
    [Test] procedure TestMarkSavedClearsFlagButUndoStaysDirty;
    [Test] procedure TestNextAndPrevHunkRows;
    [Test] procedure TestSplitKeepsDominantLineBreakAndFinalBreak;
    [Test] procedure TestJoinRestoresTheSplitText;
    [Test] procedure TestInnerSpanCoversOnlyTheChangedMiddle;
    [Test] procedure TestInnerSpanOfDisjointLinesIsTheWholeLine;
    [Test] procedure TestInnerSpanOfRepeatedCharactersDoesNotOverlap;
  end;

implementation

function TTestDiffMerge.Lines(const AItems: array of string): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(AItems));
  for I := 0 to High(AItems) do
    Result[I] := AItems[I];
end;

function TTestDiffMerge.Joined(const ALines: TArray<string>): string;
begin
  Result := JoinTextLines(ALines, '|', False);
end;

procedure TTestDiffMerge.TestIdenticalTextsHaveNoHunks;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b']), Lines(['a', 'b']));
  try
    Assert.AreEqual(0, M.HunkCount);
    Assert.AreEqual<Integer>(2, Length(M.Rows));
    Assert.AreEqual(Ord(drEqual), Ord(M.Rows[0].Kind));
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestChangedLineIsOneRowWithBothSides;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c']), Lines(['a', 'X', 'c']));
  try
    Assert.AreEqual(1, M.HunkCount);
    Assert.AreEqual<Integer>(3, Length(M.Rows));
    Assert.AreEqual(Ord(drChanged), Ord(M.Rows[1].Kind));
    Assert.AreEqual('b', M.Rows[1].Left);
    Assert.AreEqual('X', M.Rows[1].Right);
    Assert.AreEqual(2, M.Rows[1].LeftNo);
    Assert.AreEqual(2, M.Rows[1].RightNo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestAddedLineIsRightOnly;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'c']), Lines(['a', 'b', 'c']));
  try
    Assert.AreEqual(1, M.HunkCount);
    Assert.AreEqual(Ord(drRightOnly), Ord(M.Rows[1].Kind));
    Assert.AreEqual(0, M.Rows[1].LeftNo);
    Assert.AreEqual(2, M.Rows[1].RightNo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestRemovedLineIsLeftOnly;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c']), Lines(['a', 'c']));
  try
    Assert.AreEqual(Ord(drLeftOnly), Ord(M.Rows[1].Kind));
    Assert.AreEqual(0, M.Rows[1].RightNo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestNeighbouringChangesFormOneHunk;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c', 'd']), Lines(['a', 'X', 'Y', 'Z', 'd']));
  try
    Assert.AreEqual(1, M.HunkCount);
    Assert.AreEqual(2, M.Hunks[0].LeftCount);
    Assert.AreEqual(3, M.Hunks[0].RightCount);
    Assert.AreEqual<Integer>(3, Length(M.Rows) - 2);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestSimilarLinePairsWithItsCounterpartNotItsNeighbour;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(
    Lines(['x = 1;', 'console.log(totalValue());']),
    Lines(['x = 1;', 'addItem("Pen", 10, 0.9);', 'console.log("total", totalValue());']));
  try
    Assert.AreEqual(1, M.HunkCount);
    Assert.AreEqual<Integer>(3, Length(M.Rows));
    Assert.AreEqual(Ord(drRightOnly), Ord(M.Rows[1].Kind));
    Assert.AreEqual('addItem("Pen", 10, 0.9);', M.Rows[1].Right);
    Assert.AreEqual(0, M.Rows[1].LeftNo);
    Assert.AreEqual(2, M.Rows[1].RightNo);
    Assert.AreEqual(Ord(drChanged), Ord(M.Rows[2].Kind));
    Assert.AreEqual('console.log(totalValue());', M.Rows[2].Left);
    Assert.AreEqual('console.log("total", totalValue());', M.Rows[2].Right);
    Assert.AreEqual(2, M.Rows[2].LeftNo);
    Assert.AreEqual(3, M.Rows[2].RightNo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestUnrelatedLinesStillPairInPlace;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'qqqq', 'c']), Lines(['a', 'zzzz', 'yyyy', 'c']));
  try
    Assert.AreEqual<Integer>(4, Length(M.Rows));
    Assert.AreEqual(Ord(drChanged), Ord(M.Rows[1].Kind));
    Assert.AreEqual('qqqq', M.Rows[1].Left);
    Assert.AreEqual('zzzz', M.Rows[1].Right);
    Assert.AreEqual(Ord(drRightOnly), Ord(M.Rows[2].Kind));
    Assert.AreEqual('yyyy', M.Rows[2].Right);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestExtraLinesBeforeAndAfterThePairKeepOrder;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(
    Lines(['s', 'return total(items);', 'e']),
    Lines(['s', 'first', 'return total(items, tax);', 'last', 'e']));
  try
    Assert.AreEqual<Integer>(5, Length(M.Rows));
    Assert.AreEqual(Ord(drRightOnly), Ord(M.Rows[1].Kind));
    Assert.AreEqual(Ord(drChanged), Ord(M.Rows[2].Kind));
    Assert.AreEqual(Ord(drRightOnly), Ord(M.Rows[3].Kind));
    Assert.AreEqual('last', M.Rows[3].Right);
    Assert.AreEqual(4, M.Rows[3].RightNo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestCopyToRightMakesRightEqualLeft;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c']), Lines(['a', 'X', 'Y', 'c']));
  try
    Assert.IsTrue(M.CopyHunk(0, True));
    Assert.AreEqual('a|b|c', Joined(M.RightLines));
    Assert.AreEqual('a|b|c', Joined(M.LeftLines));
    Assert.AreEqual(0, M.HunkCount);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestCopyToLeftMakesLeftEqualRight;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'c']), Lines(['a', 'b', 'c']));
  try
    Assert.IsTrue(M.CopyHunk(0, False));
    Assert.AreEqual('a|b|c', Joined(M.LeftLines));
    Assert.AreEqual(0, M.HunkCount);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestCopyingOneHunkLeavesTheOthers;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c', 'd', 'e']),
    Lines(['a', 'B', 'c', 'D', 'e']));
  try
    Assert.AreEqual(2, M.HunkCount);
    Assert.IsTrue(M.CopyHunk(0, True));
    Assert.AreEqual(1, M.HunkCount);
    Assert.AreEqual('a|b|c|D|e', Joined(M.RightLines));
    Assert.AreEqual('a|b|c|d|e', Joined(M.LeftLines));
    Assert.IsFalse(M.CopyHunk(5, True));
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestCopyMarksOnlyTheChangedSideDirty;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a']), Lines(['b']));
  try
    M.CopyHunk(0, True);
    Assert.IsTrue(M.RightDirty);
    Assert.IsFalse(M.LeftDirty);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestUndoRestoresLinesAndFlags;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b']), Lines(['a', 'X']));
  try
    Assert.IsFalse(M.CanUndo);
    M.CopyHunk(0, True);
    Assert.IsTrue(M.CanUndo);
    M.Undo;
    Assert.AreEqual('a|X', Joined(M.RightLines));
    Assert.IsFalse(M.RightDirty);
    Assert.AreEqual(1, M.HunkCount);
    Assert.IsFalse(M.CanUndo);
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestMarkSavedClearsFlagButUndoStaysDirty;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a']), Lines(['b']));
  try
    M.CopyHunk(0, True);
    M.MarkSaved(False, True);
    Assert.IsFalse(M.RightDirty);
    M.Undo;
    Assert.IsTrue(M.RightDirty, 'the file on disk no longer matches the screen');
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestNextAndPrevHunkRows;
var
  M: TDiffMerge;
begin
  M := TDiffMerge.Create(Lines(['a', 'b', 'c', 'd', 'e']),
    Lines(['a', 'B', 'c', 'D', 'e']));
  try
    Assert.AreEqual(1, M.Hunks[0].FirstRow);
    Assert.AreEqual(3, M.Hunks[1].FirstRow);
    Assert.AreEqual(1, M.NextHunkRow(0));
    Assert.AreEqual(3, M.NextHunkRow(1));
    Assert.AreEqual(-1, M.NextHunkRow(3));
    Assert.AreEqual(1, M.PrevHunkRow(3));
    Assert.AreEqual(-1, M.PrevHunkRow(1));
    Assert.AreEqual(3, M.PrevHunkRow(4));
  finally
    M.Free;
  end;
end;

procedure TTestDiffMerge.TestSplitKeepsDominantLineBreakAndFinalBreak;
var
  Eol: string;
  Final: Boolean;
  L: TArray<string>;
begin
  L := SplitTextLines('a'#13#10'b'#13#10'c', Eol, Final);
  Assert.AreEqual<Integer>(3, Length(L));
  Assert.AreEqual(#13#10, Eol);
  Assert.IsFalse(Final);
  L := SplitTextLines('a'#10'b'#10, Eol, Final);
  Assert.AreEqual<Integer>(2, Length(L));
  Assert.AreEqual(#10, Eol);
  Assert.IsTrue(Final);
  L := SplitTextLines('a'#10#10'b', Eol, Final);
  Assert.AreEqual<Integer>(3, Length(L));
  Assert.AreEqual('', L[1]);
  L := SplitTextLines('', Eol, Final);
  Assert.AreEqual<Integer>(0, Length(L));
end;

procedure TTestDiffMerge.TestJoinRestoresTheSplitText;
var
  Eol, Text: string;
  Final: Boolean;
begin
  for Text in ['a'#13#10'b'#13#10, 'a'#10'b', 'x'#10#10#10, 'single'] do
    Assert.AreEqual(Text, JoinTextLines(SplitTextLines(Text, Eol, Final), Eol, Final), Text);
end;

procedure TTestDiffMerge.TestInnerSpanCoversOnlyTheChangedMiddle;
var
  Start, LL, RL: Integer;
begin
  DiffInnerSpan('print(total)', 'print("t", total)', Start, LL, RL);
  Assert.AreEqual(6, Start);
  Assert.AreEqual(0, LL);
  Assert.AreEqual(5, RL);
  DiffInnerSpan('abcXdef', 'abcYYdef', Start, LL, RL);
  Assert.AreEqual(3, Start);
  Assert.AreEqual(1, LL);
  Assert.AreEqual(2, RL);
end;

procedure TTestDiffMerge.TestInnerSpanOfDisjointLinesIsTheWholeLine;
var
  Start, LL, RL: Integer;
begin
  DiffInnerSpan('abc', 'xyz', Start, LL, RL);
  Assert.AreEqual(0, Start);
  Assert.AreEqual(3, LL);
  Assert.AreEqual(3, RL);
end;

procedure TTestDiffMerge.TestInnerSpanOfRepeatedCharactersDoesNotOverlap;
var
  Start, LL, RL: Integer;
begin
  DiffInnerSpan('aa', 'aaa', Start, LL, RL);
  Assert.AreEqual(2, Start);
  Assert.AreEqual(0, LL);
  Assert.AreEqual(1, RL);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDiffMerge);

end.
