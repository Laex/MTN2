unit TestPluginHighlight;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginHighlight = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestExtensionsPickTheHighlighter;
    [Test] procedure TestSpansAreCachedPerLine;
    [Test] procedure TestAPluginHasOneHighlighter;
    [Test] procedure TestUnloadedPluginColorsNothing;
    [Test] procedure TestFaultyHighlighterLeavesTheLinePlain;
    [Test] procedure TestColorsFollowTheBackground;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uPluginHighlight;

procedure TTestPluginHighlight.TearDown;
begin
  UnregisterHighlighter('t.hl');
  UnregisterHighlighter('t.other');
end;

procedure TTestPluginHighlight.TestExtensionsPickTheHighlighter;
begin
  RegisterHighlighter('t.hl', '.json; INI ,.cfg',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      ASpans := [Default(THighlightSpan)];
      Result := True;
    end);
  Assert.IsTrue(HighlighterFor('.json') <> 0, 'listed extension');
  Assert.IsTrue(HighlighterFor('.INI') <> 0, 'a missing dot and the case do not matter');
  Assert.IsTrue(HighlighterFor('.cfg') <> 0, 'comma and semicolon both separate');
  Assert.AreEqual(0, HighlighterFor('.txt'), 'another extension');
  Assert.AreEqual(0, HighlighterFor(''), 'no extension');
end;

procedure TTestPluginHighlight.TestSpansAreCachedPerLine;
var
  Calls, Id: Integer;
  Spans: THighlightSpans;
begin
  Calls := 0;
  RegisterHighlighter('t.hl', '.txt',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      Inc(Calls);
      SetLength(ASpans, 1);
      ASpans[0].Start := 1;
      ASpans[0].Len := 2;
      ASpans[0].Kind := cHighlightKeyword;
      Result := True;
    end);
  Id := HighlighterFor('.txt');
  Assert.IsTrue(HighlightLine(Id, 'if x', Spans), 'colored');
  Assert.IsTrue((Length(Spans) = 1) and (Spans[0].Kind = cHighlightKeyword), 'the span');
  HighlightLine(Id, 'if x', Spans);
  HighlightLine(Id, 'if x', Spans);
  Assert.AreEqual(1, Calls, 'a line seen again is not asked again');
  HighlightLine(Id, 'else', Spans);
  Assert.AreEqual(2, Calls, 'a new line is');
  Assert.IsFalse(HighlightLine(Id, '', Spans), 'an empty line is left alone');
  Assert.IsFalse(HighlightLine(0, 'if x', Spans), 'no highlighter');
end;

procedure TTestPluginHighlight.TestAPluginHasOneHighlighter;
var
  First, Second: Integer;
begin
  RegisterHighlighter('t.hl', '.aaa', function(const ALine: string; out ASpans: THighlightSpans): Boolean begin Result := False; end);
  First := HighlighterFor('.aaa');
  RegisterHighlighter('T.HL', '.bbb', function(const ALine: string; out ASpans: THighlightSpans): Boolean begin Result := False; end);
  Second := HighlighterFor('.bbb');
  Assert.AreEqual(0, HighlighterFor('.aaa'), 'the second registration replaces the first');
  Assert.IsTrue((First <> 0) and (Second <> 0) and (First <> Second), 'with a new id');
  Assert.IsTrue(Length(DescribeHighlighters('t.hl')) = 1, 'one line for the information dialog');
end;

procedure TTestPluginHighlight.TestUnloadedPluginColorsNothing;
var
  Id: Integer;
  Spans: THighlightSpans;
begin
  RegisterHighlighter('t.hl', '.zzz',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      SetLength(ASpans, 1);
      Result := True;
    end);
  Id := HighlighterFor('.zzz');
  UnregisterHighlighter('t.hl');
  Assert.AreEqual(0, HighlighterFor('.zzz'), 'not offered any more');
  Assert.IsFalse(HighlightLine(Id, 'x', Spans), 'an id kept from before colors nothing');
end;

procedure TTestPluginHighlight.TestFaultyHighlighterLeavesTheLinePlain;
var
  Spans: THighlightSpans;
begin
  RegisterHighlighter('t.hl', '.bad',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      raise Exception.Create('boom');
    end);
  Assert.IsFalse(HighlightLine(HighlighterFor('.bad'), 'x', Spans), 'the exception is contained');
end;

procedure TTestPluginHighlight.TestColorsFollowTheBackground;
begin
  Assert.AreNotEqual(HighlightColor(cHighlightComment, $FF000080), HighlightColor(cHighlightComment, $FFFFFFFF),
    'a dark and a light background get different colors');
  Assert.IsTrue(HighlightColor(cHighlightPlain, $FF000000) = HighlightColor(99, $FF000000), 'an unknown class is plain');
end;

end.
