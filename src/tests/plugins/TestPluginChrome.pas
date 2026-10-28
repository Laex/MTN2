unit TestPluginChrome;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginChrome = class
  public
    [Test] procedure TestStatusSegmentsKeepFirstSetOrder;
    [Test] procedure TestEmptyTextRemovesAndInvalidArgsAreIgnored;
    [Test] procedure TestTextIsOneShortLine;
    [Test] procedure TestChangeNotificationOnlyOnRealChanges;
    [Test] procedure TestUnregisterDropsThePluginSegments;
    [Test] procedure TestCommandCaptionShowsOnItsFunctionKey;
    [Test] procedure TestSchemeFBarLabelsFollowRootAndInside;
    [Test] procedure TestStyledSegmentKeepsTextAndColoredParts;
    [Test] procedure TestStyledSegmentWithoutTextIsRemoved;
    [Test] procedure TestStyledSegmentChangesOnlyWhenPartsChange;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uPluginChrome,
  uCommandRegistry;

procedure Clean;
begin
  PluginChrome.UnregisterPlugin('t.a');
  PluginChrome.UnregisterPlugin('t.b');
  SetPluginChromeChanged(nil);
end;

procedure TestStatusSegmentsKeepFirstSetOrder;
var
  S: TArray<string>;
begin
  try
    PluginChrome.SetStatusSegment('t.a', 'one', 'A1');
    PluginChrome.SetStatusSegment('t.b', 'one', 'B1');
    PluginChrome.SetStatusSegment('t.a', 'two', 'A2');
    PluginChrome.SetStatusSegment('t.a', 'one', 'A1b');
    S := PluginChrome.StatusSegments;
    Assert.IsTrue(string.Join(',', S) = 'A1b,B1,A2',
      'order is first-set, a changed text keeps its place: ' + string.Join(',', S));
    PluginChrome.SetStatusSegment('T.A', 'ONE', 'A1c');
    Assert.IsTrue(PluginChrome.StatusSegments[0] = 'A1c', 'ids are case-insensitive');
  finally
    Clean;
  end;
end;

procedure TestEmptyTextRemovesAndInvalidArgsAreIgnored;
begin
  try
    PluginChrome.SetStatusSegment('t.a', 'one', 'A1');
    PluginChrome.SetStatusSegment('', 'one', 'x');
    PluginChrome.SetStatusSegment('t.a', '', 'x');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 1, 'empty ids are ignored');
    PluginChrome.SetStatusSegment('t.a', 'one', '');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'empty text removes the segment');
    PluginChrome.SetStatusSegment('t.a', 'one', '   ');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'blank text is empty');
    PluginChrome.SetStatusSegment('t.a', 'never-set', '');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0,
      'removing an unknown segment is harmless');
  finally
    Clean;
  end;
end;

procedure TestTextIsOneShortLine;
var
  T: string;
begin
  try
    PluginChrome.SetStatusSegment('t.a', 'one', 'line1'#13#10'line2');
    T := PluginChrome.StatusSegments[0];
    Assert.IsTrue((Pos(#10, T) = 0) and (Pos(#13, T) = 0), 'line breaks are flattened');
    PluginChrome.SetStatusSegment('t.a', 'two', StringOfChar('x', 500));
    Assert.IsTrue(Length(PluginChrome.StatusSegments[1]) <= 80,
      'long text is cut to status size');
  finally
    Clean;
  end;
end;

procedure TestChangeNotificationOnlyOnRealChanges;
var
  Calls: Integer;
begin
  Calls := 0;
  try
    SetPluginChromeChanged(procedure begin Inc(Calls); end);
    PluginChrome.SetStatusSegment('t.a', 'one', 'A');
    Assert.IsTrue(Calls = 1, 'new segment');
    PluginChrome.SetStatusSegment('t.a', 'one', 'A');
    Assert.IsTrue(Calls = 1, 'same text is no change');
    PluginChrome.SetStatusSegment('t.a', 'one', 'B');
    Assert.IsTrue(Calls = 2, 'changed text');
    PluginChrome.SetStatusSegment('t.a', 'one', '');
    Assert.IsTrue(Calls = 3, 'removed');
    PluginChrome.SetStatusSegment('t.a', 'one', '');
    Assert.IsTrue(Calls = 3, 'removing nothing is no change');
  finally
    Clean;
  end;
end;

procedure TestUnregisterDropsThePluginSegments;
begin
  try
    PluginChrome.SetStatusSegment('t.a', 'one', 'A1');
    PluginChrome.SetStatusSegment('t.a', 'two', 'A2');
    PluginChrome.SetStatusSegment('t.b', 'one', 'B1');
    PluginChrome.UnregisterPlugin('t.a');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'B1',
      'only the other plugin stays');
  finally
    Clean;
  end;
end;

procedure TestCommandCaptionShowsOnItsFunctionKey;
begin
  try
    CommandRegistry.RegisterCommand('t.cap', 't.cap.run', procedure begin end);
    CommandRegistry.SetCommandCaption('t.cap', 't.cap.run', 'Plugin');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = '', 'not bound yet');
    CommandRegistry.RegisterCommandBinding('t.cap', 't.cap.run', 'Ctrl+Alt+F10');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = 'Plugin', 'label of the bound chord');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl]) = '', 'other modifiers');
    CommandRegistry.SetCommandCaption('t.other', 't.cap.run', 'Hijack');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = 'Plugin', 'only the owner sets it');
    CommandRegistry.SetCommandCaption('t.cap', 't.cap.run', '');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = '', 'empty caption clears it');
    CommandRegistry.SetCommandCaption('t.cap', 't.cap.run', 'Again');
    CommandRegistry.UnregisterPlugin('t.cap');
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = '', 'unregistering drops the label');
  finally
    CommandRegistry.UnregisterPlugin('t.cap');
  end;
end;

{ TTestPluginChrome }

procedure TTestPluginChrome.TestStatusSegmentsKeepFirstSetOrder;
begin
  TestPluginChrome.TestStatusSegmentsKeepFirstSetOrder;
end;

procedure TTestPluginChrome.TestEmptyTextRemovesAndInvalidArgsAreIgnored;
begin
  TestPluginChrome.TestEmptyTextRemovesAndInvalidArgsAreIgnored;
end;

procedure TTestPluginChrome.TestTextIsOneShortLine;
begin
  TestPluginChrome.TestTextIsOneShortLine;
end;

procedure TTestPluginChrome.TestChangeNotificationOnlyOnRealChanges;
begin
  TestPluginChrome.TestChangeNotificationOnlyOnRealChanges;
end;

procedure TTestPluginChrome.TestUnregisterDropsThePluginSegments;
begin
  TestPluginChrome.TestUnregisterDropsThePluginSegments;
end;

procedure TTestPluginChrome.TestCommandCaptionShowsOnItsFunctionKey;
begin
  TestPluginChrome.TestCommandCaptionShowsOnItsFunctionKey;
end;

procedure TTestPluginChrome.TestSchemeFBarLabelsFollowRootAndInside;
var
  L: string;
begin
  try
    PluginChrome.SetSchemeFBar('t.a', 'tnet',
      '{"root":{"F7":"New","Shift+F4":""},"inside":{"F7":"Dir"},"bad":{"F1":"x"}}');
    Assert.IsTrue(PluginChrome.TryGetSchemeFBarLabel('tnet:///', $76, [], L));
    Assert.AreEqual('New', L);
    Assert.IsTrue(PluginChrome.TryGetSchemeFBarLabel('tnet:///', $73, [ssShift], L));
    Assert.AreEqual('', L);
    Assert.IsTrue(PluginChrome.TryGetSchemeFBarLabel('tnet://h/a', $76, [], L));
    Assert.AreEqual('Dir', L);
    Assert.IsFalse(PluginChrome.TryGetSchemeFBarLabel('tnet:///', $70, [], L), 'unknown section ignored');
    Assert.IsFalse(PluginChrome.TryGetSchemeFBarLabel('other:///', $76, [], L), 'other scheme');
    PluginChrome.UnregisterPlugin('t.a');
    Assert.IsFalse(PluginChrome.TryGetSchemeFBarLabel('tnet:///', $76, [], L), 'gone with the plugin');
  finally
    Clean;
  end;
end;

procedure TTestPluginChrome.TestStyledSegmentKeepsTextAndColoredParts;
var
  Spans: TArray<TStatusSpans>;
begin
  try
    PluginChrome.SetStatusSegmentStyled('t.a', 'git',
      '[{"t":" main ","role":"ok","b":true},{"t":" "},' +
      '{"t":" ~2 ","role":"warn","fg":"#112233"},{"t":"x","bg":"#445566"},{"nope":1}]');
    Assert.AreEqual(' main   ~2 x', PluginChrome.StatusSegments[0]);
    Spans := PluginChrome.StatusSegmentSpans;
    Assert.IsTrue(Length(Spans[0]) = 4, 'a part without text is dropped');
    Assert.IsTrue(Spans[0][0].HasFg and Spans[0][0].HasBg and Spans[0][0].Bold, 'role + bold');
    Assert.IsTrue(Spans[0][0].Bg = TAlphaColor($FF2E7D32), 'ok role background');
    Assert.IsFalse(Spans[0][1].HasFg or Spans[0][1].HasBg, 'plain part keeps the theme colors');
    Assert.IsTrue(Spans[0][2].Fg = TAlphaColor($FF112233), 'explicit fg overrides the role');
    Assert.IsTrue(Spans[0][2].Bg = TAlphaColor($FFE0B000), 'role background stays');
    Assert.IsTrue(Spans[0][3].HasBg and not Spans[0][3].HasFg, 'bg only');
    PluginChrome.SetStatusSegment('t.a', 'git', 'plain');
    Assert.IsTrue(Length(PluginChrome.StatusSegmentSpans[0]) = 0, 'plain text drops the parts');
  finally
    Clean;
  end;
end;

procedure TTestPluginChrome.TestStyledSegmentWithoutTextIsRemoved;
begin
  try
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '[{"t":"a","role":"ok"}]');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 1);
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', 'not json');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'bad json removes');
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '[{"t":"a"}]');
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'empty json removes');
    PluginChrome.SetStatusSegmentStyled('', 'git', '[{"t":"a"}]');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'empty plugin id ignored');
  finally
    Clean;
  end;
end;

procedure TTestPluginChrome.TestStyledSegmentChangesOnlyWhenPartsChange;
var
  Calls: Integer;
begin
  Calls := 0;
  try
    SetPluginChromeChanged(procedure begin Inc(Calls); end);
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '[{"t":"a","role":"ok"}]');
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '[{"t":"a","role":"ok"}]');
    Assert.AreEqual(1, Calls, 'same parts are no change');
    PluginChrome.SetStatusSegmentStyled('t.a', 'git', '[{"t":"a","role":"error"}]');
    Assert.AreEqual(2, Calls, 'same text, other colors is a change');
  finally
    Clean;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginChrome);

end.
