unit TestLogFilter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLogFilter = class
  public
    [Test] procedure TestKeepsLinesContainingTheText;
    [Test] procedure TestIgnoresCaseUnlessAsked;
    [Test] procedure TestInvertKeepsTheOtherLines;
    [Test] procedure TestRegexMatchesAPattern;
    [Test] procedure TestBadRegexIsReported;
    [Test] procedure TestEmptyPatternIsRejected;
    [Test] procedure TestLineNumbersAreAligned;
    [Test] procedure TestCrlfInputAndTrailingBreakAreHandled;
  end;

implementation

uses
  System.SysUtils, uLogFilter;

function Opt(const APattern: string): TLogFilterOptions;
begin
  Result := Default(TLogFilterOptions);
  Result.Pattern := APattern;
end;

procedure TTestLogFilter.TestKeepsLinesContainingTheText;
var
  Matched, Total: Integer;
  Err: string;
begin
  Assert.AreEqual('b error' + #13#10 + 'error d' + #13#10,
    FilterLines('a' + #10 + 'b error' + #10 + 'c' + #10 + 'error d', Opt('error'), Matched, Total, Err));
  Assert.AreEqual(2, Matched);
  Assert.AreEqual(4, Total);
  Assert.AreEqual('', Err);
end;

procedure TTestLogFilter.TestIgnoresCaseUnlessAsked;
var
  O: TLogFilterOptions;
  Matched, Total: Integer;
  Err: string;
begin
  O := Opt('ERROR');
  FilterLines('an Error here', O, Matched, Total, Err);
  Assert.AreEqual(1, Matched);
  O.MatchCase := True;
  FilterLines('an Error here', O, Matched, Total, Err);
  Assert.AreEqual(0, Matched);
end;

procedure TTestLogFilter.TestInvertKeepsTheOtherLines;
var
  O: TLogFilterOptions;
  Matched, Total: Integer;
  Err: string;
begin
  O := Opt('debug');
  O.Invert := True;
  Assert.AreEqual('info' + #13#10,
    FilterLines('debug one' + #10 + 'info' + #10 + 'DEBUG two', O, Matched, Total, Err));
  Assert.AreEqual(1, Matched);
end;

procedure TTestLogFilter.TestRegexMatchesAPattern;
var
  O: TLogFilterOptions;
  Matched, Total: Integer;
  Err: string;
begin
  O := Opt('^\d{2}:\d{2} (WARN|ERR)');
  O.Regex := True;
  Assert.AreEqual('12:30 WARN disk' + #13#10,
    FilterLines('12:30 WARN disk' + #10 + '12:31 INFO ok' + #10 + 'x 12:32 ERR', O, Matched, Total, Err));
end;

procedure TTestLogFilter.TestBadRegexIsReported;
var
  O: TLogFilterOptions;
  Matched, Total: Integer;
  Err: string;
begin
  O := Opt('([');
  O.Regex := True;
  Assert.AreEqual('', FilterLines('x', O, Matched, Total, Err));
  Assert.AreNotEqual('', Err);
end;

procedure TTestLogFilter.TestEmptyPatternIsRejected;
var
  Matched, Total: Integer;
  Err: string;
begin
  Assert.AreEqual('', FilterLines('x', Opt(''), Matched, Total, Err));
  Assert.AreNotEqual('', Err);
end;

procedure TTestLogFilter.TestLineNumbersAreAligned;
var
  O: TLogFilterOptions;
  Text: string;
  I, Matched, Total: Integer;
  Err: string;
begin
  O := Opt('x');
  O.LineNumbers := True;
  Text := 'x first';
  for I := 2 to 11 do
    Text := Text + #10 + 'skip';
  Text := Text + #10 + 'x last';
  Assert.AreEqual(' 1: x first' + #13#10 + '12: x last' + #13#10,
    FilterLines(Text, O, Matched, Total, Err));
end;

procedure TTestLogFilter.TestCrlfInputAndTrailingBreakAreHandled;
var
  Matched, Total: Integer;
  Err: string;
begin
  Assert.AreEqual('a1' + #13#10 + 'a2' + #13#10,
    FilterLines('a1' + #13#10 + 'b' + #13#10 + 'a2' + #13#10, Opt('a'), Matched, Total, Err));
  Assert.AreEqual(3, Total, 'a trailing line break does not add a line');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLogFilter);

end.
