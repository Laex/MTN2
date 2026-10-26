unit TestKeyHints;

{ The key hints of uKeyHints: which state shows which hint, the keys read from
  the live keymap, and each hint offered once. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestKeyHints = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestUriSelectsTheSituation;
    [Test] procedure TestKeysComeFromTheKeymap;
    [Test] procedure TestUnboundActionShowsAQuestionMark;
    [Test] procedure TestEveryHintHasAText;
    [Test] procedure TestHintIsTakenOnce;
    [Test] procedure TestDisabledTrackerGivesNothing;
    [Test] procedure TestHintFitsAToast;
    [Test] procedure TestSeenSetSurvivesARestart;
  end;

implementation

uses
  System.SysUtils, uStrings, uKeymap, uKeyHints;

procedure TTestKeyHints.Setup;
begin
  SetLocale('en');
end;

procedure TTestKeyHints.TearDown;
begin
  SetLocale('en');
end;

procedure TTestKeyHints.TestUriSelectsTheSituation;
begin
  Assert.AreEqual(Ord(hsNone), Ord(HintSituationOfUri('file:///C:/Work')), 'a plain folder');
  Assert.AreEqual(Ord(hsNone), Ord(HintSituationOfUri('')), 'no folder');
  Assert.AreEqual(Ord(hsTempPanel), Ord(HintSituationOfUri('tmp:///')), 'temporary panel');
  Assert.AreEqual(Ord(hsWorkspace), Ord(HintSituationOfUri('ws:///')), 'workspace');
end;

procedure TTestKeyHints.TestKeysComeFromTheKeymap;
var
  Text: string;
begin
  Text := ExpandKeyHint('run {RunInBackground} or {RunInNewTab}', GetDefaultNDNProfile);
  Assert.IsTrue(Pos('Alt+Shift+Enter', Text) > 0, 'default keys of the background run: ' + Text);
  Assert.IsTrue(Pos('Ctrl+Alt+Enter', Text) > 0, 'default keys of the run in a new tab: ' + Text);
  Assert.IsTrue(Pos('{', Text) = 0, 'no placeholder is left');
end;

procedure TTestKeyHints.TestUnboundActionShowsAQuestionMark;
begin
  Assert.AreEqual('x ?', ExpandKeyHint('x {NoSuchAction}', GetDefaultNDNProfile));
  Assert.AreEqual('plain text', ExpandKeyHint('plain text', GetDefaultNDNProfile));
end;

procedure TTestKeyHints.TestEveryHintHasAText;
var
  S: THintSituation;
begin
  for S := Succ(hsNone) to High(THintSituation) do
  begin
    Assert.IsTrue(KeyHintText(S, GetDefaultNDNProfile) <> '', 'hint ' + IntToStr(Ord(S)));
    Assert.IsTrue(Pos('?', KeyHintText(S, GetDefaultNDNProfile)) = 0,
      'every key of hint ' + IntToStr(Ord(S)) + ' is bound by default');
  end;
  Assert.AreEqual('', KeyHintText(hsNone, GetDefaultNDNProfile));
end;

procedure TTestKeyHints.TestHintIsTakenOnce;
var
  T: TKeyHintTracker;
begin
  T := TKeyHintTracker.Create(True);
  try
    Assert.IsTrue(T.Take(hsArchive, GetDefaultNDNProfile) <> '', 'first time');
    Assert.AreEqual('', T.Take(hsArchive, GetDefaultNDNProfile), 'second time');
    Assert.IsTrue(T.Take(hsSftp, GetDefaultNDNProfile) <> '', 'another situation');
    Assert.AreEqual('', T.Take(hsNone, GetDefaultNDNProfile), 'no situation');
  finally
    T.Free;
  end;
end;

procedure TTestKeyHints.TestDisabledTrackerGivesNothing;
var
  T: TKeyHintTracker;
begin
  T := TKeyHintTracker.Create(False);
  try
    Assert.AreEqual('', T.Take(hsFindResults, GetDefaultNDNProfile));
    T.Enabled := True;
    Assert.IsTrue(T.Take(hsFindResults, GetDefaultNDNProfile) <> '', 'offered once enabled');
  finally
    T.Free;
  end;
end;

procedure TTestKeyHints.TestHintFitsAToast;
var
  S: THintSituation;
begin
  // A toast is one line and is cut to the window width; a hint stays short
  // enough for a 100-column window.
  for S := Succ(hsNone) to High(THintSituation) do
    Assert.IsTrue(Length(KeyHintText(S, GetDefaultNDNProfile)) <= 90,
      'hint ' + IntToStr(Ord(S)) + ' is short: ' + KeyHintText(S, GetDefaultNDNProfile));
end;

procedure TTestKeyHints.TestSeenSetSurvivesARestart;
var
  First, Second: TKeyHintTracker;
  Saved: Integer;
begin
  First := TKeyHintTracker.Create(True);
  Second := TKeyHintTracker.Create(True);
  try
    First.Take(hsArchive, GetDefaultNDNProfile);
    First.Take(hsSftp, GetDefaultNDNProfile);
    Saved := First.Seen;
    Assert.IsTrue(Saved <> 0, 'shown hints are recorded');
    Second.Seen := Saved;
    Assert.AreEqual('', Second.Take(hsArchive, GetDefaultNDNProfile), 'seen before the restart');
    Assert.IsTrue(Second.Take(hsFindResults, GetDefaultNDNProfile) <> '', 'not seen yet');
    Second.Seen := 0;
    Assert.IsTrue(Second.Take(hsArchive, GetDefaultNDNProfile) <> '', 'reset makes it due again');
  finally
    Second.Free;
    First.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeyHints);

end.
