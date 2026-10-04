unit TestEditorSearchEngine;

{ uEditorSearch: plain, whole-word and regular-expression matches in a line and
  in a buffer, forward and backward, and the replacements built on them. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorSearchEngine = class
  public
    [Test] procedure TestDefaultOptions;
    [Test] procedure TestPlainCaseRules;
    [Test] procedure TestWholeWord;
    [Test] procedure TestRegexForwardLength;
    [Test] procedure TestRegexWholeWord;
    [Test] procedure TestRegexCaseRules;
    [Test] procedure TestRegexEmptyMatchIsSkipped;
    [Test] procedure TestInvalidRegex;
    [Test] procedure TestBackwardEndsBeforeStart;
    [Test] procedure TestBackwardRegexAndWrap;
    [Test] procedure TestReplaceMatchGroups;
    [Test] procedure TestReplaceAllCountsAndDoesNotRescan;
    [Test] procedure TestReplaceAllRegexAndDollar;
  end;

implementation

uses
  System.SysUtils, uEditorSearch;

function Opts(AMatchCase, AWholeWord, ARegex: Boolean): TSearchOptions;
begin
  Result := DefaultSearchOptions;
  Result.MatchCase := AMatchCase;
  Result.WholeWord := AWholeWord;
  Result.UseRegex := ARegex;
end;

procedure TTestEditorSearchEngine.TestDefaultOptions;
var
  O: TSearchOptions;
begin
  O := DefaultSearchOptions;
  Assert.IsFalse(O.MatchCase or O.WholeWord or O.SearchBackwards or O.UseRegex,
    'everything off');
  Assert.IsFalse(GEditorSearchOptions.UseRegex, 'the shared options start plain');
end;

procedure TTestEditorSearchEngine.TestPlainCaseRules;
var
  C, L: Integer;
begin
  Assert.IsTrue(TEditorSearchEngine.FindInLine('Say HELLO', 'hello', 0, Opts(False, False, False), C, L));
  Assert.AreEqual(4, C, 'case-insensitive column');
  Assert.AreEqual(5, L, 'match length');
  Assert.IsFalse(TEditorSearchEngine.FindInLine('Say HELLO', 'hello', 0, Opts(True, False, False), C, L),
    'case-sensitive miss');
  Assert.IsFalse(TEditorSearchEngine.FindInLine('abc', 'c', 3, Opts(False, False, False), C, L),
    'a start past the last character finds nothing');
end;

procedure TTestEditorSearchEngine.TestWholeWord;
var
  C, L: Integer;
  O: TSearchOptions;
begin
  O := Opts(False, True, False);
  Assert.IsTrue(TEditorSearchEngine.FindInLine('concat cat cats', 'cat', 0, O, C, L));
  Assert.AreEqual(7, C, 'skips the cat inside concat');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('concat cat cats', 'cat', 8, O, C, L) = False,
    'cats is not the word cat');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('a_cat', 'cat', 0, O, C, L) = False,
    'the underscore is a word character');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('(cat)', 'cat', 0, O, C, L));
  Assert.AreEqual(1, C, 'punctuation bounds a word');
end;

procedure TTestEditorSearchEngine.TestRegexForwardLength;
var
  C, L: Integer;
begin
  Assert.IsTrue(TEditorSearchEngine.FindInLine('ab 12345 cd 67', '\d+', 0, Opts(False, False, True), C, L));
  Assert.AreEqual(3, C, 'first number');
  Assert.AreEqual(5, L, 'its length, not the length of the pattern');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('ab 12345 cd 67', '\d+', 8, Opts(False, False, True), C, L));
  Assert.AreEqual(12, C, 'next number');
  Assert.AreEqual(2, L);
  Assert.IsTrue(TEditorSearchEngine.FindInLine('abc', '^b', 1, Opts(False, False, True), C, L) = False,
    'the start anchor means the start of the line, not of the search');
end;

procedure TTestEditorSearchEngine.TestRegexWholeWord;
var
  C, L: Integer;
begin
  Assert.IsTrue(TEditorSearchEngine.FindInLine('foobar foo', 'fo+', 0, Opts(False, True, True), C, L));
  Assert.AreEqual(7, C, 'a whole word only');
end;

procedure TTestEditorSearchEngine.TestRegexCaseRules;
var
  C, L: Integer;
begin
  Assert.IsTrue(TEditorSearchEngine.FindInLine('xx ABC', 'abc', 0, Opts(False, False, True), C, L));
  Assert.IsFalse(TEditorSearchEngine.FindInLine('xx ABC', 'abc', 0, Opts(True, False, True), C, L));
end;

procedure TTestEditorSearchEngine.TestRegexEmptyMatchIsSkipped;
var
  C, L: Integer;
begin
  Assert.IsFalse(TEditorSearchEngine.FindInLine('abc', 'x*', 0, Opts(False, False, True), C, L),
    'a pattern that only matches nothing finds nothing');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('abxxc', 'x*', 0, Opts(False, False, True), C, L));
  Assert.AreEqual(2, C, 'the first non-empty match');
  Assert.AreEqual(2, L);
end;

procedure TTestEditorSearchEngine.TestInvalidRegex;
var
  C, L: Integer;
begin
  Assert.AreNotEqual('', TEditorSearchEngine.QueryError('(', Opts(False, False, True)),
    'an unbalanced group is reported');
  Assert.AreEqual('', TEditorSearchEngine.QueryError('(', Opts(False, False, False)),
    'the same text is fine as plain text');
  Assert.AreEqual('', TEditorSearchEngine.QueryError('a+', Opts(False, False, True)));
  Assert.IsFalse(TEditorSearchEngine.FindInLine('a(b', '(', 0, Opts(False, False, True), C, L),
    'a bad pattern finds nothing');
  Assert.IsTrue(TEditorSearchEngine.FindInLine('a(b', '(', 0, Opts(False, False, False), C, L));
  Assert.AreEqual(1, C, 'plain text, a parenthesis is just a character');
end;

procedure TTestEditorSearchEngine.TestBackwardEndsBeforeStart;
var
  C, L: Integer;
  O: TSearchOptions;
begin
  O := Opts(False, False, False);
  Assert.IsTrue(TEditorSearchEngine.FindLastInLine('foo foo foo', 'foo', 8, O, C, L));
  Assert.AreEqual(4, C, 'the match must end at or before the limit');
  Assert.IsFalse(TEditorSearchEngine.FindLastInLine('foo foo', 'foo', 2, O, C, L));
  Assert.IsTrue(TEditorSearchEngine.FindLastInLine('Foo cat Cat', 'cat', 11, Opts(False, True, False), C, L));
  Assert.AreEqual(8, C, 'whole word, last one');
end;

procedure TTestEditorSearchEngine.TestBackwardRegexAndWrap;
var
  Lines: TArray<string>;
  R: TSearchResult;
  O: TSearchOptions;
begin
  Lines := TArray<string>.Create('a1 b22', 'c333 d', 'e');
  O := Opts(False, False, True);
  R := TEditorSearchEngine.FindPrevWrapped(Lines, '\d+', 1, 4, O, False);
  Assert.IsTrue(R.Found and (R.LineIndex = 1) and (R.ColIndex = 1) and (R.Length = 3),
    'the number before the limit on the start line');
  R := TEditorSearchEngine.FindPrevWrapped(Lines, '\d+', 1, 1, O, False);
  Assert.IsTrue(R.Found and (R.LineIndex = 0) and (R.ColIndex = 4) and (R.Length = 2),
    'goes up to the previous line');
  R := TEditorSearchEngine.FindPrevWrapped(Lines, '\d+', 0, 1, O, False);
  Assert.IsFalse(R.Found, 'nothing before the start, no wrap');
  R := TEditorSearchEngine.FindPrevWrapped(Lines, '\d+', 0, 1, O, True);
  Assert.IsTrue(R.Found and (R.LineIndex = 1) and (R.ColIndex = 1),
    'with wrap, the last match in the buffer');
end;

procedure TTestEditorSearchEngine.TestReplaceMatchGroups;
var
  S: string;
  N: Integer;
begin
  S := TEditorSearchEngine.ReplaceMatch('mail bob@site now', '(\w+)@(\w+)', '$2 at $1',
    5, 8, Opts(False, False, True), N);
  Assert.AreEqual('mail site at bob now', S, 'groups in the replacement');
  Assert.AreEqual(11, N, 'length of what was put in');
  S := TEditorSearchEngine.ReplaceMatch('a.b', '.', '$1', 1, 1, Opts(False, False, False), N);
  Assert.AreEqual('a$1b', S, 'a plain replacement is taken literally');
  S := TEditorSearchEngine.ReplaceMatch('x12', '\d+', '[$0]', 1, 2, Opts(False, False, True), N);
  Assert.AreEqual('x[12]', S, '$0 is the whole match');
  S := TEditorSearchEngine.ReplaceMatch('x12', '(\d)(\d)', '$3|$9', 1, 2, Opts(False, False, True), N);
  Assert.AreEqual('x|', S, 'a group that does not exist is empty');
end;

procedure TTestEditorSearchEngine.TestReplaceAllCountsAndDoesNotRescan;
var
  S: string;
  N: Integer;
begin
  S := TEditorSearchEngine.ReplaceAllInLine('a a a', 'a', 'bb', Opts(False, False, False), N);
  Assert.AreEqual('bb bb bb', S);
  Assert.AreEqual(3, N, 'three replacements');
  S := TEditorSearchEngine.ReplaceAllInLine('Foo foo', 'foo', 'x', Opts(False, False, False), N);
  Assert.AreEqual('x x', S, 'case-insensitive');
  Assert.AreEqual(2, N);
  S := TEditorSearchEngine.ReplaceAllInLine('aa', 'a', 'aa', Opts(False, False, False), N);
  Assert.AreEqual('aaaa', S, 'the replacement is not searched again');
  Assert.AreEqual(2, N);
  S := TEditorSearchEngine.ReplaceAllInLine('none', 'x', 'y', Opts(False, False, False), N);
  Assert.AreEqual('none', S);
  Assert.AreEqual(0, N);
end;

procedure TTestEditorSearchEngine.TestReplaceAllRegexAndDollar;
var
  S: string;
  N: Integer;
begin
  S := TEditorSearchEngine.ReplaceAllInLine('a1 b22 c', '(\w)(\d+)', '$2$1', Opts(False, False, True), N);
  Assert.AreEqual('1a 22b c', S, 'groups swapped');
  Assert.AreEqual(2, N);
  S := TEditorSearchEngine.ReplaceAllInLine('cost 5', '\d', '$$$0', Opts(False, False, True), N);
  Assert.AreEqual('cost $5', S, 'a doubled dollar is one dollar');
  S := TEditorSearchEngine.ReplaceAllInLine('foobar foo', 'foo', 'X', Opts(False, True, False), N);
  Assert.AreEqual('foobar X', S, 'whole words only');
  Assert.AreEqual(1, N);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorSearchEngine);

end.
