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
    Assert.IsTrue(Length(PluginChrome.StatusSegments[1]) <= 40,
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

initialization
  TDUnitX.RegisterTestFixture(TTestPluginChrome);

end.
