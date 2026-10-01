unit TestVfsUtils;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVfsUtils = class
  public
    [Test] procedure TestCompareNaturalText;
    [Test] procedure TestCompareNaturalTextUnicode;
    [Test] procedure TestNaturalSortOrder;
    [Test] procedure TestVfsUtilsFunctions;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  uVfsUtils;

procedure TestCompareNaturalText;
begin
  Assert.IsTrue(CompareNaturalText('file2', 'file10') < 0, 'file2 < file10');
  Assert.IsTrue(CompareNaturalText('file10', 'file2') > 0, 'file10 > file2');
  Assert.IsTrue(CompareNaturalText('file2', 'file2') = 0, 'file2 = file2');
  Assert.IsTrue(CompareNaturalText('File2', 'file2') = 0, 'case-insensitive');
  Assert.IsTrue(CompareNaturalText('img9.png', 'img10.png') < 0, 'img9 < img10');
  Assert.IsTrue(CompareNaturalText('2', '10') < 0, '2 < 10');
  Assert.IsTrue(CompareNaturalText('a2b', 'a10b') < 0, 'a2b < a10b');
  Assert.IsTrue(CompareNaturalText('', 'a') < 0, 'empty < a');
  Assert.IsTrue(CompareNaturalText('a', 'a1') < 0, 'a < a1');
  Assert.IsTrue(CompareNaturalText('folder2', 'folder10') < 0, 'folder2 < folder10');
  Assert.IsTrue(CompareNaturalText('file2', 'file02') < 0, 'file2 < file02 (fewer zeros first)');
  Assert.IsTrue(CompareNaturalText('abc', 'abd') < 0, 'lexicographic fallback');
end;

// Non-ASCII names: case-insensitive, alphabet order of the locale (the
// digit rule still applies). Was: ordinal char codes -- 'Я' < 'а', 'а' <> 'А'.
procedure TestCompareNaturalTextUnicode;
begin
  Assert.IsTrue(CompareNaturalText('абрикос', 'Яблоко') < 0, 'абрикос < Яблоко (not by char code)');
  Assert.IsTrue(CompareNaturalText('Яблоко', 'абрикос') > 0, 'Яблоко > абрикос');
  Assert.IsTrue(CompareNaturalText('а', 'А') = 0, 'Cyrillic case-insensitive');
  Assert.IsTrue(CompareNaturalText('ОТЧЁТ', 'отчёт') = 0, 'Cyrillic case-insensitive word');
  Assert.IsTrue(CompareNaturalText('ёж', 'жа') < 0, 'ё sorts next to е, before ж');
  Assert.IsTrue(CompareNaturalText('ёлка', 'ель') < 0, 'ё compares as е (dictionary order): ёлка < ель');
  Assert.IsTrue(CompareNaturalText('Отчёт 2', 'отчёт 10') < 0, 'digit runs inside Cyrillic names');
  Assert.IsTrue(CompareNaturalText('a-b', 'ab') <> 0, 'hyphen stays significant');
end;

// A consistent (transitive) order: sorting the list and its reversed copy
// must give the same result, and sorted neighbours must compare <= 0.
procedure TestNaturalSortOrder;
const
  Names: array[0..13] of string = ('Яблоко', 'абрикос', 'file10', 'file2',
    '_build', 'A', '—dash', 'ёлка', 'ель', 'Жук', 'zeta', 'Alpha 2',
    'alpha 10', '№1');
var
  A, B: TArray<string>;
  I: Integer;
  T, Joined: string;
  Cmp: IComparer<string>;
begin
  Cmp := TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result := CompareNaturalText(L, R);
    end);
  SetLength(A, Length(Names));
  for I := 0 to High(Names) do
    A[I] := Names[I];
  B := Copy(A);
  for I := 0 to High(B) div 2 do
  begin
    T := B[I];
    B[I] := B[High(B) - I];
    B[High(B) - I] := T;
  end;
  TArray.Sort<string>(A, Cmp);
  TArray.Sort<string>(B, Cmp);
  for I := 0 to High(A) - 1 do
    Assert.IsTrue(CompareNaturalText(A[I], A[I + 1]) <= 0, 'sorted neighbours: ' + A[I] + ' / ' + A[I + 1]);
  for I := 0 to High(A) do
    Assert.IsTrue(A[I] = B[I], 'same order from reversed input at ' + IntToStr(I));
  Joined := string.Join(',', A);
  Assert.IsTrue(Pos('file2,', Joined) < Pos('file10', Joined), 'file2 before file10');
  Assert.IsTrue(Pos('Alpha 2', Joined) < Pos('alpha 10', Joined), 'Alpha 2 before alpha 10');
  Assert.IsTrue(Pos('абрикос', Joined) < Pos('Жук', Joined), 'абрикос before Жук');
  Assert.IsTrue(Pos('Жук', Joined) < Pos('Яблоко', Joined), 'Жук before Яблоко');
  Assert.IsTrue(Pos('ёлка', Joined) < Pos('ель', Joined), 'ёлка before ель');
  Assert.IsTrue(Pos('ель', Joined) < Pos('Жук', Joined), 'ель before Жук');
end;

procedure TestVfsUtilsFunctions;
var
  LFormatted: string;
  LScheme: string;
begin
  Assert.IsTrue(TVfsUtils.MatchesMask('document.pdf', '*.pdf'), 'Should match *.pdf mask');
  Assert.IsTrue(not TVfsUtils.MatchesMask('document.txt', '*.pdf'), 'Should not match *.pdf mask for txt file');

  LFormatted := TVfsUtils.FormatFileSize(2048);
  Assert.IsTrue(LFormatted.Contains('KB'), '2048 bytes should format as KB');

  LScheme := TVfsUtils.ExtractScheme('zip://C:/test.zip');
  Assert.IsTrue(LScheme = 'zip', 'Scheme should be "zip"');

  Assert.IsTrue(TVfsUtils.IsFileUri('file:///C:/Folder'), 'Should be file URI');

end;

{ TTestVfsUtils }

procedure TTestVfsUtils.TestCompareNaturalText;
begin
  TestVfsUtils.TestCompareNaturalText;
end;

procedure TTestVfsUtils.TestCompareNaturalTextUnicode;
begin
  TestVfsUtils.TestCompareNaturalTextUnicode;
end;

procedure TTestVfsUtils.TestNaturalSortOrder;
begin
  TestVfsUtils.TestNaturalSortOrder;
end;

procedure TTestVfsUtils.TestVfsUtilsFunctions;
begin
  TestVfsUtils.TestVfsUtilsFunctions;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVfsUtils);

end.
