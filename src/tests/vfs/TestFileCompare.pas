unit TestFileCompare;

{ Line-based text diff for Compare Files. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileCompare = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestReplaceLine;
    [Test] procedure TestInsertAndDelete;
    [Test] procedure TestIdenticalText;
    [Test] procedure TestOffsetHelper;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uTextEncoding,
  uFileCompare;

function HasLine(const ALines: TArray<string>; const ANeedle: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(ALines) do
    if Pos(ANeedle, ALines[I]) > 0 then
      Exit(True);
  Result := False;
end;

procedure TestReplaceLine;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Lines := BuildTextDiff(
    'keep' + sLineBreak + 'old' + sLineBreak + 'tail',
    'keep' + sLineBreak + 'new' + sLineBreak + 'tail', Changed);
  Assert.IsTrue(Changed = 2, 'replace counts delete+insert');
  Assert.IsTrue(HasLine(Lines, '- old'), 'diff shows the left line');
  Assert.IsTrue(HasLine(Lines, '+ new'), 'diff shows the right line');
  Assert.IsTrue(HasLine(Lines, '  keep'), 'diff keeps unchanged context');
end;

procedure TestInsertAndDelete;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Lines := BuildTextDiff(
    'a' + sLineBreak + 'gone' + sLineBreak + 'c',
    'a' + sLineBreak + 'c' + sLineBreak + 'added', Changed);
  Assert.IsTrue(HasLine(Lines, '- gone'), 'deleted line is marked');
  Assert.IsTrue(HasLine(Lines, '+ added'), 'inserted line is marked');
  Assert.IsTrue(Changed >= 2, 'at least two changed lines');
end;

procedure TestIdenticalText;
var
  Lines: TArray<string>;
  Changed: Integer;
begin
  Lines := BuildTextDiff('same' + sLineBreak + 'file', 'same' + sLineBreak + 'file',
    Changed);
  Assert.IsTrue(Changed = 0, 'identical text has 0 changed lines');
end;

procedure TestOffsetHelper;
var
  A, B: TBytes;
begin
  SetLength(A, 3);
  SetLength(B, 3);
  A[0] := 1; A[1] := 2; A[2] := 3;
  B[0] := 1; B[1] := 9; B[2] := 3;
  Assert.IsTrue(FirstByteDiffOffset(A, B) = 1, 'first differing byte is offset 1');
  B[1] := 2;
  Assert.IsTrue(FirstByteDiffOffset(A, B) = -1, 'equal buffers report -1');
end;

{ TTestFileCompare }

procedure TTestFileCompare.SetupFixture;
begin
end;

procedure TTestFileCompare.TestReplaceLine;
begin
  TestFileCompare.TestReplaceLine;
end;

procedure TTestFileCompare.TestInsertAndDelete;
begin
  TestFileCompare.TestInsertAndDelete;
end;

procedure TTestFileCompare.TestIdenticalText;
begin
  TestFileCompare.TestIdenticalText;
end;

procedure TTestFileCompare.TestOffsetHelper;
begin
  TestFileCompare.TestOffsetHelper;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileCompare);

end.
