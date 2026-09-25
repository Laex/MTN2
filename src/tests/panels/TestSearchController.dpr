program TestSearchController;

{$APPTYPE CONSOLE}

{ Characterization tests for TSearchController (Alt+F7 Find-file overlay,
  uDualPanelSearch.pas) — previously untested. Exercises StartSearch's
  synchronous validation guards directly, then runs one real (async)
  filesystem search against a temp fixture to characterize the spResults
  cursor/navigation behavior in HandleSearchInput, and the spDialog field
  editing. Draw is not exercised (needs a real TTerminalGrid). }

uses
  System.SysUtils, System.UITypes, System.Classes, System.IOUtils,
  System.Generics.Collections, Winapi.Windows,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uDualPanelOverlays in '..\..\Core\uDualPanelOverlays.pas',
  uFileFind in '..\..\Core\uFileFind.pas',
  uFindSession in '..\..\Core\uFindSession.pas',
  uDualPanelSearch in '..\..\Core\uDualPanelSearch.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure WaitWhile(AFunc: TFunc<Boolean>; ATimeoutMs: Cardinal = 20000);
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while AFunc() do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > ATimeoutMs then
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

function MakeController: TSearchController;
begin
  GGotoCalled := False;
  GGotoPath := '';
  GNavigateCalled := False;
  GNavigateHitCount := 0;
  GInvalidateCount := 0;
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
    function(const ARoot, AMask: string; const AHits: TArray<TFindHit>): Boolean
    begin
      // Decline every time -- let the controller show its own spResults UI
      // instead of handing the hits off elsewhere, so HandleSearchInput's
      // results-navigation branch is what gets exercised below.
      GNavigateCalled := True;
      GNavigateHitCount := Length(AHits);
      Result := False;
    end);
end;

procedure TestStartSearchGuards;
var
  C: TSearchController;
  Key: Word;
  KeyChar: Char;
begin
  Writeln('StartSearch: synchronous validation guards');
  C := MakeController;
  try
    C.Phase := spDialog;
    C.RootPath := '';
    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.Phase = spResults, 'empty root path goes straight to spResults');
    Expect(C.Message = 'No search path', 'empty root path message');
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
    Expect(C.Phase = spResults, 'invalid regex goes straight to spResults');
    Expect(Pos('Invalid regex', C.Message) = 1, 'invalid regex message');
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
  Writeln('spDialog: Tab / Backspace / typing / Escape');
  C := MakeController;
  try
    C.Phase := spDialog;
    Expect(C.FocusField = 0, 'starts focused on the mask field');

    Key := vkTab;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.FocusField = 1, 'Tab moves focus to the Subdirs field');
    Key := vkTab; // HandleSearchInput zeroes AKey on the way out -- reset it
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.FocusField = 0, 'Tab again moves focus back');

    C.Mask := '*.*';
    Key := 0;
    KeyChar := 'p';
    C.HandleSearchInput(Key, [], KeyChar);
    KeyChar := 'a';
    C.HandleSearchInput(Key, [], KeyChar);
    KeyChar := 's';
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.Mask = '*.*pas', 'typed characters append to the mask field');

    Key := vkBack;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.Mask = '*.*pa', 'Backspace removes the last mask character');

    // FocusField=1: only Space toggles Subdirs; other keys are swallowed.
    Key := vkTab;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.FocusField = 1, 'focus moved to the Subdirs field');
    Expect(C.Subdirs, 'Subdirs starts True (constructor default)');
    Key := vkSpace;
    KeyChar := ' ';
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(not C.Subdirs, 'Space toggles Subdirs off');
    Key := Ord('X');
    KeyChar := 'x';
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(not C.Subdirs, 'a non-Space key on the Subdirs field changes nothing');

    Key := vkEscape;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.Phase = spNone, 'Escape closes the dialog');
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
  Writeln('Real search against a temp fixture, then spResults navigation');
  TempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestSearchController');
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
  TDirectory.CreateDirectory(TempDir);
  TDirectory.CreateDirectory(TPath.Combine(TempDir, 'sub'));
  TFile.WriteAllText(TPath.Combine(TempDir, 'a.txt'), 'hello');
  TFile.WriteAllText(TPath.Combine(TempDir, 'b.txt'), 'world');
  TFile.WriteAllText(TPath.Combine(TempDir, 'sub\c.txt'), 'nested');
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
    Expect(C.Phase = spRunning, 'Enter in the dialog starts the search');

    WaitWhile(
      function: Boolean
      begin
        Result := C.Phase = spRunning;
      end);

    Expect(GNavigateCalled, 'the navigate-to-find-results callback ran');
    Expect(GNavigateHitCount = 3, 'exactly the 3 .txt files were found (skip.dat excluded)');
    Expect(C.Phase = spResults, 'declining navigation falls back to the results UI');
    Expect(C.FoundCount = 3, 'FoundCount matches the hits');

    SetLength(FoundPaths, Length(C.State.Results));
    for I := 0 to High(C.State.Results) do
      FoundPaths[I] := C.State.Results[I].Path;
    HasAll3 :=
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, 'a.txt')) >= 0) and
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, 'b.txt')) >= 0) and
      (TArray.IndexOf<string>(FoundPaths, TPath.Combine(TempDir, 'sub\c.txt')) >= 0);
    Expect(HasAll3, 'all 3 expected files are present in Results');
    Expect(C.State.Cursor = 0, 'cursor starts at the first result');

    C.LayoutSearchUi(120, 40);

    Key := vkDown;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.State.Cursor = 1, 'Down moves the cursor to the next result');
    Key := vkEnd;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.State.Cursor = 2, 'End moves to the last result');
    Key := vkHome;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.State.Cursor = 0, 'Home moves back to the first result');
    Key := vkUp;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(C.State.Cursor = 0, 'Up at the first result stays put (no wraparound here)');

    Key := Ord('Q');
    KeyChar := 'q';
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(Key = 0, 'an unrelated key is consumed (AKey zeroed)');
    Expect(KeyChar = #0, 'an unrelated key is consumed (AKeyChar zeroed)');
    Expect(C.State.Cursor = 0, 'an unrelated key does not move the cursor');

    Key := vkReturn;
    KeyChar := #0;
    C.HandleSearchInput(Key, [], KeyChar);
    Expect(GGotoCalled, 'Enter on a result triggers the goto callback');
    Expect(GGotoPath = FoundPaths[0], 'goto receives the path at the cursor');
    Expect(C.Phase = spNone, 'goto closes the search UI');
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
  Writeln('Escape during spRunning cancels instead of closing immediately');
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
    Expect(C.Phase = spRunning, 'search started');

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
    Expect(C.Phase = spNone, 'a cancelled search ends up back at spNone');
  finally
    C.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

begin
  try
    TestStartSearchGuards;
    TestDialogFieldEditing;
    TestRealSearchAndResultsNavigation;
    TestCancelRunningSearch;
    Writeln('All SearchController tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
