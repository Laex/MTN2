unit TestSearchController;

{ Characterization tests for TSearchController (Alt+F7 Find-file overlay,
  uDualPanelSearch.pas). Exercises StartSearch's
  synchronous validation guards directly, then runs one real (async)
  filesystem search against a temp fixture to characterize the spResults
  cursor/navigation behavior in HandleSearchInput, and the spDialog field
  editing. Draw is not exercised (needs a real TTerminalGrid). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSearchController = class
  public
    [Test] procedure TestStartSearchGuards;
    [Test] procedure TestDialogFieldEditing;
    [Test] procedure TestRealSearchAndResultsNavigation;
    [Test] procedure TestCancelRunningSearch;
    [Test] procedure TestRunningSearchEscAsksOwnerFirst;
    [Test] procedure TestLiveResultsKeepPanelWhenDone;
    [Test] procedure TestCancelKeepsFoundHitsInPanel;
    [Test] procedure TestBackgroundSearchesRunAsSeparateJobs;
    [Test] procedure TestOpeningTheJobShowsItsOwnHits;
    [Test] procedure TestLeavingTheResultsEndsTheSearch;
    [Test] procedure TestProgressDialogJobMovesTheSearchBetweenForegroundAndBackground;
    [Test] procedure TestStartSearchInBackgroundSkipsTheOverlay;
    [Test] procedure TestPanelButtonKeepsTheResultsInThePanel;
    [Test] procedure TestOpeningAnAttachedSearchKeepsItsPanel;
    [Test] procedure TestFinishedSearchWithoutHitsLeavesNoJob;
    [Test] procedure TestCancellingAFinishedSearchDiscardsIt;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.UITypes, System.Classes, System.IOUtils,
  System.Generics.Collections, uPlatformInfo,
  uVfsTypes,
  uTerminalTypes,
  uThemeTypes,
  uDualPanelUiTypes,
  uDualPanelOverlays,
  uFileFind,
  uFindSession,
  uPluginServices,
  uDualPanelSearch;

procedure WaitWhile(AFunc: TFunc<Boolean>; ATimeoutMs: Cardinal = 20000);
var
  Tick: UInt64;
begin
  Tick := PlatformTickCount64;
  while AFunc() do
  begin
    CheckSynchronize(20);
    if PlatformTickCount64 - Tick > ATimeoutMs then
      raise Exception.Create('timeout waiting for the async search to finish');
  end;
  CheckSynchronize;
end;

var
  GGotoCalled: Boolean;
  GGotoPath: string;
  GNavigateCalled: Boolean;
  GNavigateHitCount: Integer;
  GInvalidateCount: Integer;
  GAcceptResults: Boolean;
  GFirstCallIsUpdate: Boolean;
  GLastCallIsUpdate: Boolean;
  GNavigateCalls: Integer;
  GStopOnFirstHits: TProc;

function MakeController: TSearchController;
begin
  GGotoCalled := False;
  GGotoPath := '';
  GNavigateCalled := False;
  GNavigateHitCount := 0;
  GInvalidateCount := 0;
  GAcceptResults := False;
  GFirstCallIsUpdate := False;
  GLastCallIsUpdate := False;
  GNavigateCalls := 0;
  GStopOnFirstHits := nil;
  Result := TSearchController.Create(nil,
    procedure
    begin
      Inc(GInvalidateCount);
    end,
    procedure(const AFilePath: string)
    begin
      GGotoCalled := True;
      GGotoPath := AFilePath;
    end,
    function(const ARoot, AMask: string; const AHits: TArray<TFindHit>;
      AUpdate: Boolean): Boolean
    begin
      // Declines unless a test sets GAcceptResults -- the controller then shows
      // its own spResults UI instead of handing the hits off elsewhere, so
      // HandleSearchInput's results-navigation branch is what gets exercised.
      GNavigateCalled := True;
      Inc(GNavigateCalls);
      if GNavigateCalls = 1 then
        GFirstCallIsUpdate := AUpdate;
      GLastCallIsUpdate := AUpdate;
      GNavigateHitCount := Length(AHits);
      Result := GAcceptResults;
      if Assigned(GStopOnFirstHits) and (GNavigateCalls = 1) then
        GStopOnFirstHits();
    end);
end;

procedure TestStartSearchGuards;
var
  C: TSearchController;
  Key: Word;
  KeyChar: Char;
  Filters: TFindFilterText;
begin
  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := '';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spResults, 'empty root path goes straight to spResults');
    Assert.IsTrue(C.Message = 'No search path', 'empty root path message');
  finally
    C.Free;
  end;

  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := 'X'; // any non-empty string bypasses the empty-path guard
    C.UseRegex := True;
    C.ContainingText := '[invalid(';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spResults, 'invalid regex goes straight to spResults');
    Assert.IsTrue(Pos('Invalid regex', C.Message) = 1, 'invalid regex message');
  finally
    C.Free;
  end;

  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := 'C:\';
    Filters := Default(TFindFilterText);
    Filters.SizeMin := '1e20';
    C.Filters := Filters;
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spResults, 'a size past the file-size range stays on the result page');
    Assert.IsTrue(Pos('Invalid size', C.Message) = 1, 'the huge size is named as invalid');
  finally
    C.Free;
  end;
end;

procedure TestDialogFieldEditing;
var
  C: TSearchController;
  Key: Word;
  KeyChar: Char;
begin
  C := MakeController;
  try
    C.Phase := spDialog;
    Assert.IsTrue(C.FocusField = 0, 'starts focused on the mask field');

    Key := vkTab;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.FocusField = 1, 'Tab moves focus to the Subdirs field');
    Key := vkTab; // HandleSearchInput zeroes AKey on the way out -- reset it
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.FocusField = 0, 'Tab again moves focus back');

    C.Mask := '*.*';
    Key := 0;
    KeyChar := 'p';
    C.HandleSearchInput(Key, [], KeyChar);
    KeyChar := 'a';
    C.HandleSearchInput(Key, [], KeyChar);
    KeyChar := 's';
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Mask = '*.*pas', 'typed characters append to the mask field');

    Key := vkBack;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Mask = '*.*pa', 'Backspace removes the last mask character');

    // FocusField=1: only Space toggles Subdirs; other keys are swallowed.
    Key := vkTab;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.FocusField = 1, 'focus moved to the Subdirs field');
    Assert.IsTrue(C.Subdirs, 'Subdirs starts True (constructor default)');
    Key := vkSpace;
    KeyChar := ' ';
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(not C.Subdirs, 'Space toggles Subdirs off');
    Key := Ord('X');
    KeyChar := 'x';
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(not C.Subdirs, 'a non-Space key on the Subdirs field changes nothing');

    Key := vkEscape;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spNone, 'Escape closes the dialog');
  finally
    C.Free;
  end;
end;

procedure TestRealSearchAndResultsNavigation;
var
  C: TSearchController;
  TempDir: string;
  Key: Word;
  KeyChar: Char;
  FoundPaths: TArray<string>;
  I: Integer;
  HasAll3: Boolean;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchController');
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
  TDirectory.CreateDirectory(TempDir);
  TDirectory.CreateDirectory(TPath.Combine(TempDir, 'sub'));
  TFile.WriteAllText(TPath.Combine(TempDir, 'a.txt'), 'hello');
  TFile.WriteAllText(TPath.Combine(TempDir, 'b.txt'), 'world');
  TFile.WriteAllText(TPath.Combine(TempDir, NativePath('sub/c.txt')), 'nested');
  TFile.WriteAllText(TPath.Combine(TempDir, 'skip.dat'), 'not a match');

  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := TempDir;
    C.Mask := '*.txt';
    C.Subdirs := True;
    C.ContainingText := '';
    C.UseRegex := False;

    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spRunning, 'Enter in the dialog starts the search');

    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);

    Assert.IsTrue(GNavigateCalled, 'the navigate-to-find-results callback ran');
    Assert.IsTrue(GNavigateHitCount = 3, 'exactly the 3 .txt files were found (skip.dat excluded)');
    Assert.IsTrue(C.Phase = spResults, 'declining navigation falls back to the results UI');
    Assert.IsTrue(C.FoundCount = 3, 'FoundCount matches the hits');

    SetLength(FoundPaths, Length(C.State.Results));
    for I := 0 to High(C.State.Results) do
      FoundPaths[I] := C.State.Results[I].Path;
    HasAll3 :=
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, 'a.txt')) >= 0) and
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, 'b.txt')) >= 0) and
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, NativePath('sub/c.txt'))) >= 0);
    Assert.IsTrue(HasAll3, 'all 3 expected files are present in Results');
    Assert.IsTrue(C.State.Cursor = 0, 'cursor starts at the first result');

    C.LayoutSearchUi(120, 40);

    Key := vkDown;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.State.Cursor = 1, 'Down moves the cursor to the next result');
    Key := vkEnd;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.State.Cursor = 2, 'End moves to the last result');
    Key := vkHome;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.State.Cursor = 0, 'Home moves back to the first result');
    Key := vkUp;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.State.Cursor = 0, 'Up at the first result stays put (no wraparound here)');

    Key := Ord('Q');
    KeyChar := 'q';
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(Key = 0, 'an unrelated key is consumed (AKey zeroed)');
    Assert.IsTrue(KeyChar = #0, 'an unrelated key is consumed (AKeyChar zeroed)');
    Assert.IsTrue(C.State.Cursor = 0, 'an unrelated key does not move the cursor');

    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(GGotoCalled, 'Enter on a result triggers the goto callback');
    Assert.IsTrue(GGotoPath = FoundPaths[0], 'goto receives the path at the cursor');
    Assert.IsTrue(C.Phase = spNone, 'goto closes the search UI');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

procedure TestCancelRunningSearch;
var
  C: TSearchController;
  TempDir: string;
  Key: Word;
  KeyChar: Char;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchControllerCancel');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);
  TFile.WriteAllText(TPath.Combine(TempDir, 'x.txt'), 'x');

  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := TempDir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spRunning, 'search started');

    Key := vkEscape;
    C.HandleSearchInput(Key, [], KeyChar);
    // CancelSearch only requests cancellation on the in-flight token; the
    // actual phase change happens once the worker thread's cancelled
    // completion reaches the main thread -- it does not happen synchronously.
    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);
    Assert.IsTrue(C.Phase = spNone, 'a cancelled search ends up back at spNone');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

procedure TestRunningSearchEscAsksOwnerFirst;
var
  C: TSearchController;
  TempDir: string;
  Key: Word;
  KeyChar: Char;
  Asked: Integer;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchControllerStopAsk');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);
  TFile.WriteAllText(TPath.Combine(TempDir, 'x.txt'), 'x');

  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := TempDir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spRunning, 'search started');

    Asked := 0;
    C.OnStopRequest :=
      procedure
      begin
        Inc(Asked);
      end;
    Key := vkEscape;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(Asked = 1, 'Escape hands the stop decision to the owner');
    Assert.IsTrue(C.Phase = spRunning, 'the search keeps running until the owner cancels it');

    C.CancelSearch;
    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);
    Assert.IsTrue(C.Phase = spNone, 'an owner-confirmed cancel ends the search');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

procedure TestLiveResultsKeepPanelWhenDone;
var
  C: TSearchController;
  TempDir: string;
  Key: Word;
  KeyChar: Char;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchControllerLive');
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
  TDirectory.CreateDirectory(TempDir);
  TFile.WriteAllText(TPath.Combine(TempDir, 'a.txt'), 'a');
  TFile.WriteAllText(TPath.Combine(TempDir, 'b.txt'), 'b');

  C := MakeController;
  try
    GAcceptResults := True;
    C.Phase := spDialog;
    C.RootPath := TempDir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);

    Assert.IsTrue(C.Phase = spNone, 'the panel took the hits, so the overlay closes');
    Assert.IsTrue(GNavigateCalls >= 2, 'a live call plus the final call');
    Assert.IsFalse(GFirstCallIsUpdate, 'the first call opens the panel');
    Assert.IsTrue(GLastCallIsUpdate, 'later calls only update the open panel');
    Assert.AreEqual(2, GNavigateHitCount, 'the final call carries every hit');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

procedure TestCancelKeepsFoundHitsInPanel;
var
  C: TSearchController;
  TempDir: string;
  Key: Word;
  KeyChar: Char;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchControllerLiveCancel');
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
  TDirectory.CreateDirectory(TempDir);
  TFile.WriteAllText(TPath.Combine(TempDir, 'a.txt'), 'a');

  C := MakeController;
  try
    GAcceptResults := True;
    GStopOnFirstHits :=
      procedure
      begin
        C.CancelSearch;
      end;
    C.Phase := spDialog;
    C.RootPath := TempDir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);

    Assert.IsTrue(C.Phase = spNone, 'the overlay closes after the stop');
    Assert.IsTrue(GNavigateHitCount >= 1,
      'the panel was handed the hit found before the stop');
    Assert.IsTrue(GLastCallIsUpdate, 'the stop updates the open panel instead of closing it');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

{ TTestSearchController }

function MakeTree(const AName: string; const AFiles: array of string): string;
var
  F: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
  for F in AFiles do
    TFile.WriteAllText(TPath.Combine(Result, F), 'x');
end;

// Starts a search over ADir and sends it to the background.
procedure StartInBackground(C: TSearchController; const ADir, AMask: string);
var
  Key: Word;
  KeyChar: Char;
begin
  C.Phase := spDialog;
  C.RootPath := ADir;
  C.Mask := AMask;
  Key := vkReturn;
  KeyChar := #0;
  C.HandleSearchInput(Key, [], KeyChar);
  Key := vkTab;
  C.HandleSearchInput(Key, [], KeyChar);
end;

function JobsDone: Boolean;
var
  Info: TPluginJobInfo;
begin
  for Info in PluginJobSnapshot do
    if Info.Percent < 100 then
      Exit(False);
  Result := True;
end;

procedure TestBackgroundSearchesRunAsSeparateJobs;
var
  C: TSearchController;
  DirA, DirB: string;
  Jobs: TArray<TPluginJobInfo>;
begin
  DirA := MakeTree('MTN2_TestBgA', ['a1.txt', 'a2.txt']);
  DirB := MakeTree('MTN2_TestBgB', ['b1.log']);
  C := MakeController;
  try
    StartInBackground(C, DirA, '*.txt');
    Assert.IsTrue(C.Phase = spNone, 'the overlay is gone');
    StartInBackground(C, DirB, '*.log');
    Assert.AreEqual(2, C.BackgroundCount, 'both searches run');
    Jobs := PluginJobSnapshot;
    Assert.AreEqual(2, Integer(Length(Jobs)), 'each has a job of its own');
    Assert.IsTrue(Pos('*.txt', Jobs[0].Title) > 0, 'the first is named after its mask');
    Assert.IsTrue(Pos('*.log', Jobs[1].Title) > 0, 'the second is named after its mask');

    WaitWhile(
      function: Boolean
      begin
        Result := not JobsDone;
      end);
    Assert.AreEqual(2, Integer(Length(PluginJobSnapshot)),
      'finished searches stay until their results are closed');
    Jobs := PluginJobSnapshot;
    Assert.AreEqual('2', Jobs[0].Badge, 'the chip counts the hits of the first search');
    Assert.AreEqual('1', Jobs[1].Badge, 'the chip counts the hits of the second search');
    Assert.AreEqual(0, GNavigateCalls, 'no panel is touched while they run');
  finally
    C.Free;
    TDirectory.Delete(DirA, True);
    TDirectory.Delete(DirB, True);
  end;
  Assert.AreEqual(0, Integer(Length(PluginJobSnapshot)), 'closing the controller ends them');
end;

procedure TestOpeningTheJobShowsItsOwnHits;
var
  C: TSearchController;
  DirA, DirB: string;
  Jobs: TArray<TPluginJobInfo>;
  OpenedHits, OpenCalls: Integer;
  OpenedMask: string;
begin
  DirA := MakeTree('MTN2_TestBgOpenA', ['a1.txt', 'a2.txt']);
  DirB := MakeTree('MTN2_TestBgOpenB', ['b1.log']);
  C := MakeController;
  try
    OpenedHits := -1;
    OpenCalls := 0;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        Inc(OpenCalls);
        OpenedHits := Length(AHits);
        OpenedMask := AMask;
        ASessionId := 'S1';
        Result := True;
      end;
    StartInBackground(C, DirA, '*.txt');
    StartInBackground(C, DirB, '*.log');
    WaitWhile(
      function: Boolean
      begin
        Result := not JobsDone;
      end);

    Jobs := PluginJobSnapshot;
    Assert.IsTrue(PluginJobOpen(Jobs[1].Id), 'the job has an open handler');
    Assert.AreEqual(1, OpenCalls);
    Assert.AreEqual(1, OpenedHits, 'the second job opens the second search');
    Assert.AreEqual('*.log', OpenedMask);
    Assert.IsTrue(PluginJobOpen(Jobs[0].Id));
    Assert.AreEqual(2, OpenedHits, 'the first job opens the first search');
  finally
    C.Free;
    TDirectory.Delete(DirA, True);
    TDirectory.Delete(DirB, True);
  end;
end;

procedure TestProgressDialogJobMovesTheSearchBetweenForegroundAndBackground;
var
  C: TSearchController;
  Dir: string;
  Key: Word;
  KeyChar: Char;
  Jobs: TArray<TPluginJobInfo>;
  Opened, Hidden: Integer;
begin
  Dir := MakeTree('MTN2_TestBgDialogJob', ['a.txt']);
  C := MakeController;
  try
    Opened := 0;
    Hidden := 0;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        Inc(Opened);
        ASessionId := 'S1';
        Result := True;
      end;
    C.OnHideResults :=
      procedure
      begin
        Inc(Hidden);
      end;
    C.Phase := spDialog;
    C.RootPath := Dir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Assert.IsTrue(C.Phase = spRunning, 'search started');
    Jobs := PluginJobSnapshot;
    Assert.AreEqual(1, Integer(Length(Jobs)), 'the running search is a job');
    Assert.IsTrue(Jobs[0].Foreground, 'its progress dialog is up');

    PluginJobSetForeground(Jobs[0].Id, False);
    Assert.IsTrue(C.Phase = spNone, 'hiding the dialog sends the search to the background');
    Assert.AreEqual(1, C.BackgroundCount);
    Assert.AreEqual(1, Integer(Length(PluginJobSnapshot)), 'the same job goes on');
    Assert.IsFalse(PluginJobSnapshot[0].Foreground);

    Assert.IsTrue(PluginJobOpen(Jobs[0].Id), 'the job opens');
    Assert.AreEqual(1, Opened, 'its results come into the panel');
    Assert.IsTrue(PluginJobSnapshot[0].Foreground, 'with its progress dialog');

    PluginJobSetForeground(Jobs[0].Id, False);
    Assert.AreEqual(1, Hidden, 'hiding the dialog takes the results out of the panel again');
    Assert.AreEqual(1, C.BackgroundCount, 'the search is not ended by that');
    C.SweepBackgrounds;
    Assert.AreEqual(1, C.BackgroundCount, 'a hidden search is not swept');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestStartSearchInBackgroundSkipsTheOverlay;
var
  C: TSearchController;
  Dir: string;
begin
  Dir := MakeTree('MTN2_TestBgDirect', ['a.txt']);
  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := Dir;
    C.Mask := '*.txt';
    C.StartSearchInBackground;
    Assert.IsTrue(C.Phase = spNone, 'no overlay appears');
    Assert.AreEqual(1, C.BackgroundCount, 'the search runs as a background job');
    Assert.AreEqual(1, Integer(Length(PluginJobSnapshot)), 'with a job of its own');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestLeavingTheResultsEndsTheSearch;
var
  C: TSearchController;
  Dir: string;
  Shown: Boolean;
begin
  Dir := MakeTree('MTN2_TestBgLeave', ['a.txt']);
  C := MakeController;
  try
    Shown := True;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        ASessionId := 'S1';
        Result := True;
      end;
    C.OnSessionShown :=
      function(const ASessionId: string): Boolean
      begin
        Result := Shown;
      end;
    StartInBackground(C, Dir, '*.txt');
    WaitWhile(
      function: Boolean
      begin
        Result := not JobsDone;
      end);
    C.SweepBackgrounds;
    Assert.AreEqual(1, C.BackgroundCount, 'an unopened search is not swept');

    PluginJobOpen(PluginJobSnapshot[0].Id);
    C.SweepBackgrounds;
    Assert.AreEqual(1, C.BackgroundCount, 'it stays while the panel shows it');

    Shown := False;
    C.SweepBackgrounds;
    Assert.AreEqual(0, C.BackgroundCount, 'it ends when the panel leaves the results');
    Assert.AreEqual(0, Integer(Length(PluginJobSnapshot)), 'and its job goes with it');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestPanelButtonKeepsTheResultsInThePanel;
var
  C: TSearchController;
  Dir: string;
  Key: Word;
  KeyChar: Char;
  Jobs: TArray<TPluginJobInfo>;
  Opened, Hidden, Reported: Integer;
  Shown: Boolean;
begin
  Dir := MakeTree('MTN2_TestBgPanel', ['a.txt', 'b.txt']);
  C := MakeController;
  try
    Opened := 0;
    Hidden := 0;
    Reported := -1;
    Shown := True;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        Inc(Opened);
        ASessionId := 'S1';
        Result := True;
      end;
    C.OnHideResults :=
      procedure
      begin
        Inc(Hidden);
      end;
    C.OnSessionShown :=
      function(const ASessionId: string): Boolean
      begin
        Result := Shown;
      end;
    C.OnBackgroundDone :=
      procedure(AFound: Integer)
      begin
        Reported := AFound;
      end;
    C.Phase := spDialog;
    C.RootPath := Dir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Jobs := PluginJobSnapshot;
    Assert.IsTrue(Jobs[0].CanAttach, 'the search dialog offers the Panel button');

    Assert.IsTrue(PluginJobAttach(Jobs[0].Id), 'the job has an attach handler');
    Assert.IsTrue(C.Phase = spNone, 'the progress dialog is gone');
    Assert.AreEqual(1, C.BackgroundCount, 'the search goes on in the background');
    Assert.AreEqual(1, Opened, 'the panel shows its results');
    Assert.AreEqual(0, Hidden, 'and keeps them');
    Assert.IsFalse(PluginJobSnapshot[0].Foreground, 'no dialog is up');

    C.SweepBackgrounds;
    Assert.AreEqual(1, C.BackgroundCount, 'a shown search is not swept');

    Shown := False;
    C.SweepBackgrounds;
    Assert.AreEqual(1, C.BackgroundCount, 'leaving the list does not end a running search');
    Assert.AreEqual(1, Integer(Length(PluginJobSnapshot)), 'its job stays');

    Assert.IsTrue(PluginJobOpen(Jobs[0].Id), 'the job opens again');
    Assert.AreEqual(2, Opened, 'the panel is back on the results');
    Assert.IsTrue(PluginJobSnapshot[0].Foreground, 'with the progress dialog');
    PluginJobSetForeground(Jobs[0].Id, False);
    Assert.AreEqual(1, Hidden, 'hiding that dialog takes the results out of the panel');

    WaitWhile(
      function: Boolean
      begin
        Result := not JobsDone;
      end);
    Assert.AreEqual(2, Reported, 'a finished search nobody watches is reported');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestOpeningAnAttachedSearchKeepsItsPanel;
var
  C: TSearchController;
  Dir: string;
  Key: Word;
  KeyChar: Char;
  Jobs: TArray<TPluginJobInfo>;
  Opened, Hidden: Integer;
begin
  Dir := MakeTree('MTN2_TestBgPanelReopen', ['a.txt']);
  C := MakeController;
  try
    Opened := 0;
    Hidden := 0;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        Inc(Opened);
        ASessionId := 'S1';
        Result := True;
      end;
    C.OnHideResults :=
      procedure
      begin
        Inc(Hidden);
      end;
    C.OnSessionShown :=
      function(const ASessionId: string): Boolean
      begin
        Result := True;
      end;
    C.Phase := spDialog;
    C.RootPath := Dir;
    C.Mask := '*.txt';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Jobs := PluginJobSnapshot;
    PluginJobAttach(Jobs[0].Id);
    Assert.AreEqual(1, Opened);

    Assert.IsTrue(PluginJobOpen(Jobs[0].Id), 'the chip brings the dialog back');
    Assert.AreEqual(1, Opened, 'the panel that already shows the results is not reopened');
    Assert.IsTrue(PluginJobSnapshot[0].Foreground);

    Assert.IsTrue(PluginJobAttach(Jobs[0].Id), 'the dialog offers the Panel button again');
    Assert.IsFalse(PluginJobSnapshot[0].Foreground, 'the dialog goes');
    Assert.AreEqual(0, Hidden, 'the panel stays');
    Assert.AreEqual(1, C.BackgroundCount);
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestFinishedSearchWithoutHitsLeavesNoJob;
var
  C: TSearchController;
  Dir: string;
  Reported: Integer;
begin
  Dir := MakeTree('MTN2_TestBgNone', ['a.dat']);
  C := MakeController;
  try
    Reported := -1;
    C.OnBackgroundDone :=
      procedure(AFound: Integer)
      begin
        Reported := AFound;
      end;
    StartInBackground(C, Dir, '*.txt');
    WaitWhile(
      function: Boolean
      begin
        Result := Reported < 0;
      end);
    Assert.AreEqual(0, Reported, 'the empty result is reported');
    Assert.AreEqual(0, C.BackgroundCount, 'there is nothing to open');
    Assert.AreEqual(0, Integer(Length(PluginJobSnapshot)), 'no job stays');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestCancellingAFinishedSearchDiscardsIt;
var
  C: TSearchController;
  Dir: string;
  OpenCalls: Integer;
begin
  Dir := MakeTree('MTN2_TestBgDiscard', ['a.txt']);
  C := MakeController;
  try
    OpenCalls := 0;
    C.OnOpenSession :=
      function(var ASessionId: string; const ARoot, AMask: string;
        const AHits: TArray<TFindHit>): Boolean
      begin
        Inc(OpenCalls);
        Result := True;
      end;
    StartInBackground(C, Dir, '*.txt');
    WaitWhile(
      function: Boolean
      begin
        Result := not JobsDone;
      end);
    Assert.IsTrue(PluginJobCancel(PluginJobSnapshot[0].Id), 'the list can cancel it');
    Assert.AreEqual(0, C.BackgroundCount, 'the search is gone');
    Assert.AreEqual(0, OpenCalls, 'nothing opens');
    Assert.AreEqual(0, Integer(Length(PluginJobSnapshot)), 'and so is its job');
  finally
    C.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSearchController.TestLiveResultsKeepPanelWhenDone;
begin
  TestSearchController.TestLiveResultsKeepPanelWhenDone;
end;

procedure TTestSearchController.TestCancelKeepsFoundHitsInPanel;
begin
  TestSearchController.TestCancelKeepsFoundHitsInPanel;
end;

procedure TTestSearchController.TestStartSearchGuards;
begin
  TestSearchController.TestStartSearchGuards;
end;

procedure TTestSearchController.TestDialogFieldEditing;
begin
  TestSearchController.TestDialogFieldEditing;
end;

procedure TTestSearchController.TestRealSearchAndResultsNavigation;
begin
  TestSearchController.TestRealSearchAndResultsNavigation;
end;

procedure TTestSearchController.TestCancelRunningSearch;
begin
  TestSearchController.TestCancelRunningSearch;
end;

procedure TTestSearchController.TestRunningSearchEscAsksOwnerFirst;
begin
  TestSearchController.TestRunningSearchEscAsksOwnerFirst;
end;

procedure TTestSearchController.TestBackgroundSearchesRunAsSeparateJobs;
begin
  TestSearchController.TestBackgroundSearchesRunAsSeparateJobs;
end;

procedure TTestSearchController.TestOpeningTheJobShowsItsOwnHits;
begin
  TestSearchController.TestOpeningTheJobShowsItsOwnHits;
end;

procedure TTestSearchController.TestLeavingTheResultsEndsTheSearch;
begin
  TestSearchController.TestLeavingTheResultsEndsTheSearch;
end;

procedure TTestSearchController.TestFinishedSearchWithoutHitsLeavesNoJob;
begin
  TestSearchController.TestFinishedSearchWithoutHitsLeavesNoJob;
end;

procedure TTestSearchController.TestCancellingAFinishedSearchDiscardsIt;
begin
  TestSearchController.TestCancellingAFinishedSearchDiscardsIt;
end;

procedure TTestSearchController.TestProgressDialogJobMovesTheSearchBetweenForegroundAndBackground;
begin
  TestSearchController.TestProgressDialogJobMovesTheSearchBetweenForegroundAndBackground;
end;

procedure TTestSearchController.TestPanelButtonKeepsTheResultsInThePanel;
begin
  TestSearchController.TestPanelButtonKeepsTheResultsInThePanel;
end;

procedure TTestSearchController.TestOpeningAnAttachedSearchKeepsItsPanel;
begin
  TestSearchController.TestOpeningAnAttachedSearchKeepsItsPanel;
end;

procedure TTestSearchController.TestStartSearchInBackgroundSkipsTheOverlay;
begin
  TestSearchController.TestStartSearchInBackgroundSkipsTheOverlay;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSearchController);

end.
