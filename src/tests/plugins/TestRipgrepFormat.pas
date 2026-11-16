unit TestRipgrepFormat;

{ The argument list of an rg run and the reading of its JSON lines. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRipgrepFormat = class
  public
    [Test] procedure TestPlainTextIsAFixedStringUnderTheRoot;
    [Test] procedure TestSwitchesFollowTheRequest;
    [Test] procedure TestMasksBecomeGlobsAndAllNamesNone;
    [Test] procedure TestTextAndRootAreSeparateArguments;
    [Test] procedure TestMatchEventGivesPathLineAndSnippet;
    [Test] procedure TestOtherEventsAreNotMatches;
    [Test] procedure TestOutputKeepsMatchesAndSkipsMessages;
  end;

implementation

uses
  System.SysUtils, uSearchRequest, uSearchHitsJson, uRipgrepFormat;

function Req(const AJson: string): TSearchRequest;
begin
  Assert.IsTrue(ParseSearchRequest(AJson, Result), 'request parsed');
end;

function Has(const AArgs: TArray<string>; const AArg: string): Boolean;
var
  A: string;
begin
  Result := False;
  for A in AArgs do
    if A = AArg then
      Exit(True);
end;

procedure TTestRipgrepFormat.TestPlainTextIsAFixedStringUnderTheRoot;
var
  Args: TArray<string>;
begin
  Args := BuildRgArguments(Req('{"params":{"root":"C:\\Work","mask":"*.*","text":"needle"}}'));
  Assert.IsTrue(Has(Args, '--json'));
  Assert.IsTrue(Has(Args, '--fixed-strings'));
  Assert.IsTrue(Has(Args, '--ignore-case'));
  Assert.IsTrue(Has(Args, '--max-count=1'), 'one hit per file');
  Assert.IsTrue(Has(Args, '--hidden'), 'hidden files are searched unless switched off');
  Assert.AreEqual('C:\Work', Args[High(Args)]);
  Assert.AreEqual('--', Args[High(Args) - 1]);
end;

procedure TTestRipgrepFormat.TestSwitchesFollowTheRequest;
var
  Args: TArray<string>;
begin
  Args := BuildRgArguments(Req('{"params":{"root":"C:\\Work","text":"a.b","regex":true,' +
    '"caseSensitive":true,"wholeWords":true,"subdirs":false,"hidden":false,"encoding":"windows-1251"}}'));
  Assert.IsFalse(Has(Args, '--fixed-strings'), 'a regex is not fixed');
  Assert.IsTrue(Has(Args, '--case-sensitive'));
  Assert.IsFalse(Has(Args, '--ignore-case'));
  Assert.IsTrue(Has(Args, '--word-regexp'));
  Assert.IsTrue(Has(Args, '--max-depth=1'));
  Assert.IsFalse(Has(Args, '--hidden'));
  Assert.IsTrue(Has(Args, '--encoding=windows-1251'));
end;

procedure TTestRipgrepFormat.TestMasksBecomeGlobsAndAllNamesNone;
var
  Args: TArray<string>;
begin
  Args := BuildRgArguments(Req('{"params":{"root":"C:\\Work","mask":"*.pas;*.dfm, *.inc","text":"x"}}'));
  Assert.IsTrue(Has(Args, '--glob=*.pas'));
  Assert.IsTrue(Has(Args, '--glob=*.dfm'));
  Assert.IsTrue(Has(Args, '--glob=*.inc'));
  Args := BuildRgArguments(Req('{"params":{"root":"C:\\Work","mask":"*.*","text":"x"}}'));
  Assert.IsFalse(Has(Args, '--glob=*.*'), 'every name needs no glob');
end;

procedure TTestRipgrepFormat.TestTextAndRootAreSeparateArguments;
var
  Args: TArray<string>;
begin
  Args := BuildRgArguments(Req('{"params":{"root":"C:\\My Work","text":"-x \"quoted\" & more"}}'));
  Assert.IsTrue(Has(Args, '--regexp=-x "quoted" & more'), 'the text is one argument, as is');
  Assert.AreEqual('C:\My Work', Args[High(Args)], 'the root is one argument, as is');
end;

procedure TTestRipgrepFormat.TestMatchEventGivesPathLineAndSnippet;
var
  Hit: TSearchHit;
begin
  Assert.IsTrue(TryParseRgMatch(
    '{"type":"match","data":{"path":{"text":"C:\\Work\\a.txt"},"lines":{"text":"  the needle here\n"},' +
    '"line_number":12,"absolute_offset":0,"submatches":[]}}', Hit));
  Assert.AreEqual('C:\Work\a.txt', Hit.Path);
  Assert.AreEqual(12, Hit.Line);
  Assert.AreEqual('the needle here', Hit.Snippet);
  Assert.IsFalse(Hit.IsDir);
end;

procedure TTestRipgrepFormat.TestOtherEventsAreNotMatches;
var
  Hit: TSearchHit;
begin
  Assert.IsFalse(TryParseRgMatch('{"type":"begin","data":{"path":{"text":"C:\\a.txt"}}}', Hit));
  Assert.IsFalse(TryParseRgMatch('{"type":"summary","data":{}}', Hit));
  Assert.IsFalse(TryParseRgMatch('{"type":"match","data":{"path":{"bytes":"AAEC"},"line_number":1}}', Hit),
    'a path that is not text');
  Assert.IsFalse(TryParseRgMatch('rg: some message', Hit));
  Assert.IsFalse(TryParseRgMatch('', Hit));
end;

procedure TTestRipgrepFormat.TestOutputKeepsMatchesAndSkipsMessages;
var
  Hits: TArray<TSearchHit>;
begin
  Hits := ParseRgOutput(
    '{"type":"begin","data":{"path":{"text":"C:\\a.txt"}}}'#13#10 +
    '{"type":"match","data":{"path":{"text":"C:\\a.txt"},"lines":{"text":"x\n"},"line_number":3}}'#13#10 +
    '{"type":"end","data":{}}'#13#10 +
    'rg: C:\locked: access denied'#13#10 +
    '{"type":"match","data":{"path":{"text":"C:\\b.txt"},"lines":{"text":"y\n"},"line_number":5}}'#13#10);
  Assert.AreEqual(2, Integer(Length(Hits)));
  Assert.AreEqual('C:\a.txt', Hits[0].Path);
  Assert.AreEqual('C:\b.txt', Hits[1].Path);
  Assert.AreEqual(5, Hits[1].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRipgrepFormat);

end.
