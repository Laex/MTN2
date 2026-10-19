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
    [Test] procedure TestStatefulHighlighterCarriesTheState;
    [Test] procedure TestTrackerDropsStatesAfterAnEdit;
    [Test] procedure TestTrackerStartsOverWhenThePluginForgetsStates;
    [Test] procedure TestTrackerWorksWithinItsBudget;
    [Test] procedure TestFileNameSelectsTheHighlighter;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uPluginHighlight;

procedure TTestPluginHighlight.TearDown;
begin
  UnregisterHighlighter('t.hl');
  UnregisterHighlighter('t.other');
end;

// A fake language: a line with "/*" opens a block (state 1), a line with "*/" closes it. The
// colored span is the whole line while the block is open.
function BlockStep(const ALine: string; AStateIn: Integer; out ASpans: THighlightSpans;
  out AStateOut: Integer): Boolean;
begin
  AStateOut := AStateIn;
  if (AStateIn = 0) and (Pos('/*', ALine) > 0) and (Pos('*/', ALine) = 0) then
    AStateOut := 1
  else if (AStateIn = 1) and (Pos('*/', ALine) > 0) then
    AStateOut := 0;
  SetLength(ASpans, 0);
  if (AStateIn = 1) or (AStateOut = 1) then
  begin
    SetLength(ASpans, 1);
    ASpans[0].Start := 0;
    ASpans[0].Len := Length(ALine);
    ASpans[0].Kind := cHighlightComment;
  end;
  Result := Length(ASpans) > 0;
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
  Assert.AreEqual<Integer>(0, HighlighterFor('.txt'), 'another extension');
  Assert.AreEqual<Integer>(0, HighlighterFor(''), 'no extension');
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
  Assert.AreEqual<Integer>(1, Calls, 'a line seen again is not asked again');
  HighlightLine(Id, 'else', Spans);
  Assert.AreEqual<Integer>(2, Calls, 'a new line is');
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
  Assert.AreEqual<Integer>(0, HighlighterFor('.aaa'), 'the second registration replaces the first');
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
  Assert.AreEqual<Integer>(0, HighlighterFor('.zzz'), 'not offered any more');
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

procedure TTestPluginHighlight.TestStatefulHighlighterCarriesTheState;
var
  Id, State: Integer;
  Spans: THighlightSpans;
begin
  RegisterStatefulHighlighter('t.hl', '.blk', BlockStep);
  Id := HighlighterForFile('a.blk');
  Assert.IsTrue(Id <> 0, 'registered');
  Assert.IsTrue(HighlighterIsStateful(Id), 'stateful');
  Assert.IsTrue(HighlightLineState(Id, 'x /* open', 0, Spans, State), 'opening line');
  Assert.AreEqual<Integer>(1, State, 'the block is open');
  Assert.IsTrue(HighlightLineState(Id, 'inside', State, Spans, State), 'inside line');
  Assert.AreEqual<Integer>(1, State, 'still open');
  Assert.IsFalse(HighlightLineState(Id, 'plain', 0, Spans, State), 'outside the block');
  Assert.AreEqual<Integer>(0, State, 'no block');
  Assert.IsFalse(HighlightLine(Id, 'inside', Spans), 'the stateless call does not serve it');
end;

procedure TTestPluginHighlight.TestTrackerDropsStatesAfterAnEdit;
var
  Lines: TArray<string>;
  Tracker: THighlightTracker;
  Get: TFunc<Integer, string>;
begin
  RegisterStatefulHighlighter('t.hl', '.blk', BlockStep);
  Lines := ['a', '/* open', 'b', 'c */', 'd'];
  Get := function(AIndex: Integer): string
    begin
      Result := Lines[AIndex];
    end;
  Tracker := THighlightTracker.Create(HighlighterForFile('a.blk'));
  try
    Assert.IsTrue(Tracker.Reach(4, Get, 1000), 'reached the last line');
    Assert.AreEqual<Integer>(1, Tracker.StateAt(2), 'inside the block');
    Assert.AreEqual<Integer>(0, Tracker.StateAt(4), 'after the block');
    Lines[1] := 'no block';
    Tracker.InvalidateFrom(1);
    Assert.IsTrue(Tracker.Reach(4, Get, 1000), 'reached again');
    Assert.AreEqual<Integer>(0, Tracker.StateAt(2), 'the edit closed the block');
    Assert.AreEqual<Integer>(0, Tracker.StateAt(4), 'and the end stays closed');
  finally
    Tracker.Free;
  end;
end;

procedure TTestPluginHighlight.TestTrackerStartsOverWhenThePluginForgetsStates;
var
  Tracker: THighlightTracker;
  Get: TFunc<Integer, string>;
  Forget: Boolean;
begin
  Forget := False;
  RegisterStatefulHighlighter('t.hl', '.blk',
    function(const ALine: string; AStateIn: Integer; out ASpans: THighlightSpans;
      out AStateOut: Integer): Boolean
    begin
      ASpans := nil;
      if Forget and (AStateIn <> 0) then
      begin
        AStateOut := -1;
        Exit(False);
      end;
      AStateOut := AStateIn + 1;
      Result := False;
    end);
  Get := function(AIndex: Integer): string
    begin
      Result := 'line';
    end;
  Tracker := THighlightTracker.Create(HighlighterForFile('a.blk'));
  try
    Assert.IsTrue(Tracker.Reach(3, Get, 1000), 'states known');
    Forget := True;
    Tracker.InvalidateFrom(1);
    Assert.IsFalse(Tracker.Reach(5, Get, 1000), 'the walk stops when a state is lost');
    Forget := False;
    Assert.IsTrue(Tracker.Reach(5, Get, 1000), 'and starts over from the top on the next try');
    Assert.AreEqual<Integer>(5, Tracker.StateAt(5), 'with the right states');
  finally
    Tracker.Free;
  end;
end;

procedure TTestPluginHighlight.TestTrackerWorksWithinItsBudget;
var
  Tracker: THighlightTracker;
  Get: TFunc<Integer, string>;
begin
  RegisterStatefulHighlighter('t.hl', '.blk',
    function(const ALine: string; AStateIn: Integer; out ASpans: THighlightSpans;
      out AStateOut: Integer): Boolean
    begin
      ASpans := nil;
      AStateOut := AStateIn;
      Sleep(2);
      Result := False;
    end);
  Get := function(AIndex: Integer): string
    begin
      Result := 'line ' + IntToStr(AIndex);
    end;
  Tracker := THighlightTracker.Create(HighlighterForFile('a.blk'));
  try
    Assert.IsFalse(Tracker.Reach(100000, Get, 20), 'a long walk does not finish within the budget');
    Assert.IsFalse(Tracker.Reach(100000, Get, 0), 'no budget, no progress');
    Assert.IsTrue(Tracker.Reach(0, Get, 0), 'the start of the file is always known');
  finally
    Tracker.Free;
  end;
end;

procedure TTestPluginHighlight.TestFileNameSelectsTheHighlighter;
begin
  RegisterHighlighter('t.hl', '.json;Makefile',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      ASpans := nil;
      Result := False;
    end);
  Assert.IsTrue(HighlighterForFile('data.JSON') <> 0, 'by extension');
  Assert.IsTrue(HighlighterForFile('makefile') <> 0, 'by the whole name, any case');
  Assert.AreEqual<Integer>(0, HighlighterForFile('Makefile.bak'), 'a different name');
  Assert.AreEqual<Integer>(0, HighlighterForFile(''), 'no name');
end;

end.
