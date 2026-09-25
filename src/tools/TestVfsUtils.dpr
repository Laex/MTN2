program TestVfsUtils;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  uVfsUtils in '..\Core\uVfsUtils.pas';

procedure TestCompareNaturalText;
begin
  Assert(CompareNaturalText('file2', 'file10') < 0, 'file2 < file10');
  Assert(CompareNaturalText('file10', 'file2') > 0, 'file10 > file2');
  Assert(CompareNaturalText('file2', 'file2') = 0, 'file2 = file2');
  Assert(CompareNaturalText('File2', 'file2') = 0, 'case-insensitive');
  Assert(CompareNaturalText('img9.png', 'img10.png') < 0, 'img9 < img10');
  Assert(CompareNaturalText('2', '10') < 0, '2 < 10');
  Assert(CompareNaturalText('a2b', 'a10b') < 0, 'a2b < a10b');
  Assert(CompareNaturalText('', 'a') < 0, 'empty < a');
  Assert(CompareNaturalText('a', 'a1') < 0, 'a < a1');
  Assert(CompareNaturalText('folder2', 'folder10') < 0, 'folder2 < folder10');
  Assert(CompareNaturalText('file2', 'file02') < 0, 'file2 < file02 (fewer zeros first)');
  Assert(CompareNaturalText('abc', 'abd') < 0, 'lexicographic fallback');
  Writeln('OK: TestCompareNaturalText passed');
end;

// Non-ASCII names: case-insensitive, alphabet order of the locale (the
// digit rule still applies). Was: ordinal char codes -- 'Я' < 'а', 'а' <> 'А'.
procedure TestCompareNaturalTextUnicode;
begin
  Assert(CompareNaturalText('абрикос', 'Яблоко') < 0, 'абрикос < Яблоко (not by char code)');
  Assert(CompareNaturalText('Яблоко', 'абрикос') > 0, 'Яблоко > абрикос');
  Assert(CompareNaturalText('а', 'А') = 0, 'Cyrillic case-insensitive');
  Assert(CompareNaturalText('ОТЧЁТ', 'отчёт') = 0, 'Cyrillic case-insensitive word');
  Assert(CompareNaturalText('ёж', 'жа') < 0, 'ё sorts next to е, before ж');
  Assert(CompareNaturalText('ёлка', 'ель') < 0, 'ё compares as е (dictionary order): ёлка < ель');
  Assert(CompareNaturalText('Отчёт 2', 'отчёт 10') < 0, 'digit runs inside Cyrillic names');
  Assert(CompareNaturalText('a-b', 'ab') <> 0, 'hyphen stays significant');
  Writeln('OK: TestCompareNaturalTextUnicode passed');
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
    Assert(CompareNaturalText(A[I], A[I + 1]) <= 0, 'sorted neighbours: ' + A[I] + ' / ' + A[I + 1]);
  for I := 0 to High(A) do
    Assert(A[I] = B[I], 'same order from reversed input at ' + IntToStr(I));
  Joined := string.Join(',', A);
  Assert(Pos('file2,', Joined) < Pos('file10', Joined), 'file2 before file10');
  Assert(Pos('Alpha 2', Joined) < Pos('alpha 10', Joined), 'Alpha 2 before alpha 10');
  Assert(Pos('абрикос', Joined) < Pos('Жук', Joined), 'абрикос before Жук');
  Assert(Pos('Жук', Joined) < Pos('Яблоко', Joined), 'Жук before Яблоко');
  Assert(Pos('ёлка', Joined) < Pos('ель', Joined), 'ёлка before ель');
  Assert(Pos('ель', Joined) < Pos('Жук', Joined), 'ель before Жук');
  Writeln('OK: TestNaturalSortOrder passed');
end;

procedure TestVfsUtilsFunctions;
var
  LFormatted: string;
  LScheme: string;
begin
  Assert(TVfsUtils.MatchesMask('document.pdf', '*.pdf'), 'Should match *.pdf mask');
  Assert(not TVfsUtils.MatchesMask('document.txt', '*.pdf'), 'Should not match *.pdf mask for txt file');

  LFormatted := TVfsUtils.FormatFileSize(2048);
  Assert(LFormatted.Contains('KB'), '2048 bytes should format as KB');

  LScheme := TVfsUtils.ExtractScheme('zip://C:/test.zip');
  Assert(LScheme = 'zip', 'Scheme should be "zip"');

  Assert(TVfsUtils.IsFileUri('file:///C:/Folder'), 'Should be file URI');

  Writeln('OK: TestVfsUtilsFunctions passed');
end;

begin
  try
    TestCompareNaturalText;
    TestCompareNaturalTextUnicode;
    TestNaturalSortOrder;
    TestVfsUtilsFunctions;
    Writeln('All VfsUtils tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
