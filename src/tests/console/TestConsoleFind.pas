unit TestConsoleFind;

{ The search over the console output: which row and column the next or the
  previous match is, and which cells of a row are marked. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConsoleFind = class
  public
    [Test] procedure TestForwardWalksMatchesInOrderAndWraps;
    [Test] procedure TestBackwardWalksMatchesNewestFirstAndWraps;
    [Test] procedure TestCaseIsIgnoredAndRepeatsOnOneRowAreFound;
    [Test] procedure TestNoMatchAndEmptyNeedle;
    [Test] procedure TestMatchColumnsMarkEveryOccurrence;
  end;

implementation

uses
  System.SysUtils, uConsoleBuffer;

function Lines(const ALines: array of string): TConsoleLineGetter;
var
  Copy: TArray<string>;
  I: Integer;
begin
  SetLength(Copy, Length(ALines));
  for I := 0 to High(ALines) do
    Copy[I] := ALines[I];
  Result :=
    function(AIndex: Integer): string
    begin
      Result := Copy[AIndex];
    end;
end;

procedure TTestConsoleFind.TestForwardWalksMatchesInOrderAndWraps;
var
  Get: TConsoleLineGetter;
  Row, Col: Integer;
begin
  Get := Lines(['one', 'two error', 'three', 'error again']);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', True, 0, -1, Row, Col));
  Assert.AreEqual(1, Row);
  Assert.AreEqual(4, Col);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', True, Row, Col, Row, Col));
  Assert.AreEqual(3, Row);
  Assert.AreEqual(0, Col);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', True, Row, Col, Row, Col));
  Assert.AreEqual(1, Row, 'after the last match the search wraps to the first');
  Assert.AreEqual(4, Col);
end;

procedure TTestConsoleFind.TestBackwardWalksMatchesNewestFirstAndWraps;
var
  Get: TConsoleLineGetter;
  Row, Col: Integer;
begin
  Get := Lines(['one', 'two error', 'three', 'error again']);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', False, 3, MaxInt, Row, Col));
  Assert.AreEqual(3, Row, 'the newest match comes first');
  Assert.AreEqual(0, Col);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', False, Row, Col, Row, Col));
  Assert.AreEqual(1, Row);
  Assert.AreEqual(4, Col);
  Assert.IsTrue(ConsoleFindMatch(4, Get, 'error', False, Row, Col, Row, Col));
  Assert.AreEqual(3, Row, 'before the first match the search wraps to the last');
end;

procedure TTestConsoleFind.TestCaseIsIgnoredAndRepeatsOnOneRowAreFound;
var
  Get: TConsoleLineGetter;
  Row, Col: Integer;
begin
  Get := Lines(['aXa xa Xa']);
  Assert.IsTrue(ConsoleFindMatch(1, Get, 'xa', True, 0, -1, Row, Col));
  Assert.AreEqual(1, Col);
  Assert.IsTrue(ConsoleFindMatch(1, Get, 'xa', True, 0, Col, Row, Col));
  Assert.AreEqual(4, Col);
  Assert.IsTrue(ConsoleFindMatch(1, Get, 'xa', True, 0, Col, Row, Col));
  Assert.AreEqual(7, Col);
  Assert.IsTrue(ConsoleFindMatch(1, Get, 'xa', False, 0, Col, Row, Col));
  Assert.AreEqual(4, Col, 'backward from the last match on the row');
end;

procedure TTestConsoleFind.TestNoMatchAndEmptyNeedle;
var
  Get: TConsoleLineGetter;
  Row, Col: Integer;
begin
  Get := Lines(['alpha', 'beta']);
  Assert.IsFalse(ConsoleFindMatch(2, Get, 'zzz', True, 0, -1, Row, Col));
  Assert.IsFalse(ConsoleFindMatch(2, Get, '', True, 0, -1, Row, Col));
  Assert.IsFalse(ConsoleFindMatch(0, Get, 'a', True, 0, -1, Row, Col));
end;

procedure TTestConsoleFind.TestMatchColumnsMarkEveryOccurrence;
var
  Cols: TArray<Boolean>;
  I: Integer;
  Marked: string;
begin
  Cols := ConsoleMatchColumns('abcAB ab', 'ab', 10);
  Marked := '';
  for I := 0 to High(Cols) do
    if Cols[I] then
      Marked := Marked + IntToStr(I);
  Assert.AreEqual('013467', Marked);
  Assert.AreEqual<Integer>(0, Length(ConsoleMatchColumns('xyz', 'ab', 10)), 'no match: empty');
  Cols := ConsoleMatchColumns('abcab', 'ab', 4);
  Assert.AreEqual<Integer>(4, Length(Cols));
  Assert.IsTrue(Cols[3], 'a match running past the width is cut at the width');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConsoleFind);

end.
