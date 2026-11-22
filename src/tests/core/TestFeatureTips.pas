unit TestFeatureTips;

{ The tips about features the user has not tried (uFeatureTips): when the
  first one is due, one tip per run, none for a feature already used, each tip
  once, and the state kept across runs. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFeatureTips = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNoTipInTheFirstRuns;
    [Test] procedure TestOneTipPerRun;
    [Test] procedure TestUsedFeatureIsSkipped;
    [Test] procedure TestEveryTipIsOfferedOnce;
    [Test] procedure TestAlternativeActionCountsAsUse;
    [Test] procedure TestDisabledTrackerGivesNothing;
    [Test] procedure TestStateSurvivesARestart;
    [Test] procedure TestResetOffersTheTipsAgain;
    [Test] procedure TestTipsKeepTheirBitsAcrossVersions;
    [Test] procedure TestEveryTipHasKeysAndFitsAToast;
    [Test] procedure TestSessionWithoutTipStateGetsNoTips;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, uDualPanelTypes, uListExport, uStrings, uKeymap, uKeyHints, uFeatureTips, uSession;

procedure TTestFeatureTips.Setup;
begin
  SetLocale('en');
end;

procedure TTestFeatureTips.TearDown;
begin
  SetLocale('en');
end;

// A tracker that has begun AN runs.
function TrackerOnRun(AN: Integer): TFeatureTipTracker;
var
  I: Integer;
begin
  Result := TFeatureTipTracker.Create(True);
  for I := 1 to AN do
    Result.BeginSession;
end;

procedure TTestFeatureTips.TestNoTipInTheFirstRuns;
var
  T: TFeatureTipTracker;
begin
  T := TrackerOnRun(cFirstTipRun - 1);
  try
    Assert.AreEqual('', T.NextTip(GetDefaultNDNProfile), 'a new user is left alone');
  finally
    T.Free;
  end;
  T := TrackerOnRun(cFirstTipRun);
  try
    Assert.AreNotEqual('', T.NextTip(GetDefaultNDNProfile), 'the first tip is due');
  finally
    T.Free;
  end;
end;

procedure TTestFeatureTips.TestOneTipPerRun;
var
  T: TFeatureTipTracker;
  First, Second: string;
begin
  T := TrackerOnRun(cFirstTipRun);
  try
    First := T.NextTip(GetDefaultNDNProfile);
    Assert.AreNotEqual('', First);
    Assert.AreEqual('', T.NextTip(GetDefaultNDNProfile), 'a second ask in the same run gives nothing');
    T.BeginSession;
    Second := T.NextTip(GetDefaultNDNProfile);
    Assert.AreNotEqual('', Second, 'the next run offers the next tip');
    Assert.AreNotEqual(First, Second, 'a different tip');
  finally
    T.Free;
  end;
end;

procedure TTestFeatureTips.TestUsedFeatureIsSkipped;
var
  T, Fresh: TFeatureTipTracker;
begin
  Fresh := TrackerOnRun(cFirstTipRun);
  T := TrackerOnRun(cFirstTipRun);
  try
    // The feature of the first tip is used: the tracker moves on.
    T.NoteAction(kaCommandPalette);
    Assert.AreNotEqual(Fresh.NextTip(GetDefaultNDNProfile), T.NextTip(GetDefaultNDNProfile),
      'the used feature is not advertised');
  finally
    T.Free;
    Fresh.Free;
  end;
end;

procedure TTestFeatureTips.TestEveryTipIsOfferedOnce;
var
  T: TFeatureTipTracker;
  Seen: TArray<string>;
  Text: string;
  I, Runs: Integer;
begin
  T := TrackerOnRun(cFirstTipRun - 1);
  try
    for Runs := 1 to Ord(High(TFeatureTip)) + 5 do
    begin
      T.BeginSession;
      Text := T.NextTip(GetDefaultNDNProfile);
      if Text = '' then
        Break;
      for I := 0 to High(Seen) do
        Assert.AreNotEqual(Seen[I], Text, 'a tip is never repeated');
      SetLength(Seen, Length(Seen) + 1);
      Seen[High(Seen)] := Text;
    end;
    Assert.AreEqual(Integer(Ord(High(TFeatureTip))), Integer(Length(Seen)), 'every tip came once');
    T.BeginSession;
    Assert.AreEqual('', T.NextTip(GetDefaultNDNProfile), 'then no more');
  finally
    T.Free;
  end;
end;

procedure TTestFeatureTips.TestAlternativeActionCountsAsUse;
begin
  Assert.AreEqual(Ord(ftFolderHotlist), Ord(FeatureTipOfAction(kaFolderHotlist)));
  Assert.AreEqual(Ord(ftFolderHotlist), Ord(FeatureTipOfAction(kaFolderFrecent)),
    'the frequent folders list counts for the hotlist tip');
  Assert.AreEqual(Ord(ftCompareFolders), Ord(FeatureTipOfAction(kaCompareFiles)));
  Assert.AreEqual(Ord(ftNone), Ord(FeatureTipOfAction(kaHelp)), 'a common action has no tip');
end;

procedure TTestFeatureTips.TestDisabledTrackerGivesNothing;
var
  T: TFeatureTipTracker;
begin
  T := TrackerOnRun(cFirstTipRun);
  try
    T.Enabled := False;
    Assert.AreEqual('', T.NextTip(GetDefaultNDNProfile));
  finally
    T.Free;
  end;
end;

procedure TTestFeatureTips.TestStateSurvivesARestart;
var
  A, B: TFeatureTipTracker;
  First, Next: string;
begin
  A := TrackerOnRun(cFirstTipRun);
  B := TFeatureTipTracker.Create(True);
  try
    First := A.NextTip(GetDefaultNDNProfile);
    A.NoteAction(kaMultiRename);
    B.State := A.State;
    B.BeginSession;
    Next := B.NextTip(GetDefaultNDNProfile);
    Assert.AreNotEqual('', Next);
    Assert.AreNotEqual(First, Next, 'the shown tip is remembered');
    Assert.AreEqual(A.State.Launches + 1, B.State.Launches, 'the run count carries on');
    Assert.IsTrue(B.State.Used and (1 shl Ord(ftMultiRename)) <> 0, 'the used feature is remembered');
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TTestFeatureTips.TestResetOffersTheTipsAgain;
var
  T: TFeatureTipTracker;
  First: string;
begin
  T := TrackerOnRun(cFirstTipRun);
  try
    First := T.NextTip(GetDefaultNDNProfile);
    T.ResetShown;
    T.BeginSession;
    Assert.AreEqual(First, T.NextTip(GetDefaultNDNProfile), 'after a reset the first tip is due again');
  finally
    T.Free;
  end;
end;

procedure TTestFeatureTips.TestTipsKeepTheirBitsAcrossVersions;
begin
  // The state stores tips as a bit set of these ordinals; moving one would
  // make a stored bit mean another tip.
  Assert.AreEqual(1, Ord(ftCommandPalette));
  Assert.AreEqual(2, Ord(ftMultiRename));
  Assert.AreEqual(11, Ord(ftNewWorkspace));
  Assert.IsTrue(Ord(High(TFeatureTip)) <= 30, 'the set fits an Integer');
end;

procedure TTestFeatureTips.TestEveryTipHasKeysAndFitsAToast;
var
  Tip: TFeatureTip;
  Text, L1, L2: string;
begin
  for Tip := Succ(ftNone) to High(TFeatureTip) do
  begin
    Text := FeatureTipText(Tip, GetDefaultNDNProfile);
    Assert.AreNotEqual('', Text, 'text of tip ' + IntToStr(Ord(Tip)));
    Assert.AreEqual(0, Pos('?', Text), 'every key of tip ' + IntToStr(Ord(Tip)) + ' is bound: ' + Text);
    Assert.AreEqual(0, Pos('{', Text), 'no placeholder is left: ' + Text);
    WrapKeyHint(Text, 60, L1, L2);
    Assert.IsTrue(Length(L1) <= 60, 'first line of tip ' + IntToStr(Ord(Tip)));
    Assert.IsTrue(Length(L2) <= 60, 'second line of tip ' + IntToStr(Ord(Tip)));
  end;
end;

procedure TTestFeatureTips.TestSessionWithoutTipStateGetsNoTips;
var
  Path, Text: string;
  Saved, Old: TMtnSession;
  Root: TJSONObject;
  Tab: TTab;
  T: TFeatureTipTracker;
  State: TFeatureTipState;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-tips-session.json');
  Tab := Default(TTab);
  Tab.CurrentURI := 'file:///C:/';
  Saved := Default(TMtnSession);
  Saved.Version := cSessionVersion;
  Saved.Zoom := 1;
  Saved.ListExport := DefaultListExportConfig;
  SetLength(Saved.Panels.WorkspaceTabs, 1);
  Saved.Panels.WorkspaceTabs[0].Kind := wkPanels;
  SetLength(Saved.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs, 1);
  Saved.Panels.WorkspaceTabs[0].State.LeftPanel.Tabs[0] := Tab;
  SetLength(Saved.Panels.WorkspaceTabs[0].State.RightPanel.Tabs, 1);
  Saved.Panels.WorkspaceTabs[0].State.RightPanel.Tabs[0] := Tab;
  Saved.FeatureTipRuns := 5;
  Saved.FeatureTipShown := 2;
  try
    Assert.IsTrue(SaveSession(Path, Saved), 'save session');
    Assert.IsTrue(TryLoadSession(Path, Old), 'load a current session');
    Assert.AreEqual(2, Old.FeatureTipShown, 'a current session keeps its tips');
    // The same file as an older version wrote it: without the tip state.
    Root := TJSONObject(TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)));
    try
      Root.RemovePair('featureTipRuns').Free;
      Root.RemovePair('featureTipUsed').Free;
      Root.RemovePair('featureTipShown').Free;
      Text := Root.ToJSON;
    finally
      Root.Free;
    end;
    TFile.WriteAllText(Path, Text, TEncoding.UTF8);
    Assert.IsTrue(TryLoadSession(Path, Old), 'load an old session');
    Assert.AreEqual(AllFeatureTipsMask, Old.FeatureTipShown, 'every tip counts as shown');
    T := TrackerOnRun(cFirstTipRun);
    try
      State := T.State;
      State.Shown := Old.FeatureTipShown;
      T.State := State;
      Assert.AreEqual('', T.NextTip(GetDefaultNDNProfile), 'no tip for an upgraded user');
    finally
      T.Free;
    end;
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

end.
