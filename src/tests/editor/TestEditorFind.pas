unit TestEditorFind;

{ F7 / F3 / Shift+F3 and the Replace dialog in a loaded editor: the Find dialog
  takes the text and its options, a found match is selected with the cursor at
  its end, and Replace uses the same options (regular expressions with groups,
  whole words, case). Replace asks about each match (Replace / All / Skip /
  Cancel), goes on to the next one after every answer, offers to continue from
  the other end of the text and puts the cursor back where it was. Keys go
  through HandleInput as typed. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorFind = class
  private
    FDir: string;
    FView: TObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestFindSelectsMatchAndContinues;
    [Test] procedure TestFindBackwardWithShiftF3;
    [Test] procedure TestRegexSelectsWholeMatch;
    [Test] procedure TestWholeWordAndCase;
    [Test] procedure TestWordButtonFillsFindField;
    [Test] procedure TestReplaceOneWithGroups;
    [Test] procedure TestReplaceAllCountsMatches;
    [Test] procedure TestStepReplaceAnswers;
    [Test] procedure TestStepReplaceAllAnswer;
    [Test] procedure TestStepReplaceCancelKeepsDone;
    [Test] procedure TestStepReplaceWrapsFromTheMiddle;
    [Test] procedure TestStepReplaceDeclinedWrap;
    [Test] procedure TestStepReplaceBackward;
    [Test] procedure TestBadRegexIsReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow, uEditorSearch;

const
  cText = 'alpha one two' + sLineBreak + 'beta Two three' + sLineBreak +
    'gamma TWO four' + sLineBreak + 'cat concat cat' + sLineBreak;

procedure Pump(AMs: Integer = 600);
var
  T: UInt64;
begin
  T := TThread.GetTickCount64 + UInt64(AMs);
  while TThread.GetTickCount64 < T do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

procedure Key(AView: TEditorWindow; AKey: Word; AShift: TShiftState = [];
  AChar: Char = #0);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := AChar;
  AView.HandleInput(K, AShift, Ch);
end;

procedure TypeText(AView: TEditorWindow; const AText: string);
var
  I: Integer;
  K: Word;
  Ch: Char;
begin
  for I := 1 to Length(AText) do
  begin
    K := 0;
    Ch := AText[I];
    AView.HandleInput(K, [], Ch);
  end;
end;

function OpenView(const ADir: string): TEditorWindow;
var
  Path: string;
begin
  Path := TPath.Combine(ADir, 'f.txt');
  TFile.WriteAllText(Path, cText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure CursorIs(AView: TEditorWindow; ARow, ACol: Integer; const AMsg: string);
var
  Top, Row, Col: Integer;
begin
  AView.GetViewPos(Top, Row, Col);
  Assert.AreEqual(ARow, Row, AMsg + ': row');
  Assert.AreEqual(ACol, Col, AMsg + ': column');
end;

procedure TTestEditorFind.Setup;
begin
  GEditorSearchOptions := DefaultSearchOptions;
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-find-' + TPath.GetGUIDFileName(False));
  ForceDirectories(FDir);
end;

procedure TTestEditorFind.TearDown;
begin
  FreeAndNil(FView);
  GEditorSearchOptions := DefaultSearchOptions;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestEditorFind.TestFindSelectsMatchAndContinues;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, 'two');
  Key(V, vkReturn);
  CursorIs(V, 0, 13, 'first match, cursor at its end');
  Assert.IsTrue(V.HasSelection, 'the match is selected');
  Key(V, vkF3);
  CursorIs(V, 1, 8, 'F3 goes on to the next line (case-insensitive)');
  Key(V, vkF3);
  CursorIs(V, 2, 9, 'F3 again');
end;

procedure TTestEditorFind.TestFindBackwardWithShiftF3;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, 'two');
  Key(V, vkReturn);
  Key(V, vkF3);
  CursorIs(V, 1, 8, 'second match');
  Key(V, vkF3, [ssShift]);
  CursorIs(V, 0, 13, 'Shift+F3 goes back to the first match');
end;

procedure TTestEditorFind.TestRegexSelectsWholeMatch;
var
  V: TEditorWindow;
begin
  GEditorSearchOptions.UseRegex := True;
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, 't\w+ \w+');
  Key(V, vkReturn);
  // Line 0 has no "t<word> <word>"; line 1 has "ta Two" (columns 2 to 8).
  CursorIs(V, 1, 8, 'the whole regular-expression match is selected');
  Assert.IsTrue(V.HasSelection, 'and it is selected');
end;

procedure TTestEditorFind.TestWholeWordAndCase;
var
  V: TEditorWindow;
begin
  GEditorSearchOptions.WholeWord := True;
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, 'cat');
  Key(V, vkReturn);
  CursorIs(V, 3, 3, 'the first whole word cat (not the one inside concat)');
  Key(V, vkF3);
  CursorIs(V, 3, 14, 'next whole word');
  GEditorSearchOptions.MatchCase := True;
  GEditorSearchOptions.WholeWord := False;
  FreeAndNil(FView);
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, 'TWO');
  Key(V, vkReturn);
  CursorIs(V, 2, 9, 'case-sensitive: only the upper-case TWO');
end;

procedure TTestEditorFind.TestWordButtonFillsFindField;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, vkDown);
  Key(V, vkHome);
  Key(V, vkF7);
  // Alt+R is the hot key of the Word button: the word under the cursor
  // (beta) lands in the field and the dialog stays open, with the focus on
  // the button; Shift+Tab goes back to Search.
  Key(V, 0, [ssAlt], 'r');
  Key(V, vkTab, [ssShift]);
  Key(V, vkReturn);
  CursorIs(V, 1, 4, 'the word under the cursor was searched for');
end;

procedure TTestEditorFind.TestReplaceOneWithGroups;
var
  V: TEditorWindow;
begin
  GEditorSearchOptions.UseRegex := True;
  V := OpenView(FDir);
  FView := V;
  V.OpenReplaceDialog;
  TypeText(V, '(\w+) one');
  Key(V, vkTab);
  TypeText(V, '$1 uno');
  Key(V, vkReturn);
  // The Replace button asks about the match; Enter answers Replace.
  Key(V, vkReturn);
  Assert.AreEqual('alpha uno two', V.LineText(0), 'the group was put back');
  CursorIs(V, 0, 0, 'the cursor is back where it was');
end;

procedure TTestEditorFind.TestReplaceAllCountsMatches;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  V.OpenReplaceDialog;
  TypeText(V, 'two');
  Key(V, vkTab);
  TypeText(V, '2');
  Key(V, 0, [ssAlt], 'a');
  Assert.AreEqual('alpha one 2', V.LineText(0));
  Assert.AreEqual('beta 2 three', V.LineText(1), 'case-insensitive');
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  Assert.AreEqual('cat concat cat', V.LineText(3), 'untouched');
end;

procedure TTestEditorFind.TestBadRegexIsReported;
var
  V: TEditorWindow;
begin
  GEditorSearchOptions.UseRegex := True;
  V := OpenView(FDir);
  FView := V;
  Key(V, vkF7);
  TypeText(V, '(');
  Key(V, vkReturn);
  CursorIs(V, 0, 0, 'a bad pattern moves nothing');
  Assert.IsFalse(V.HasSelection, 'and selects nothing');
end;

// Opens the Replace dialog, types the texts and presses the Replace button.
procedure StartReplace(AView: TEditorWindow; const AFind, ARepl: string);
begin
  AView.OpenReplaceDialog;
  TypeText(AView, AFind);
  Key(AView, vkTab);
  TypeText(AView, ARepl);
  Key(AView, vkReturn);
end;

procedure TTestEditorFind.TestStepReplaceAnswers;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplace(V, 'two', '2');
  Key(V, vkReturn);               // Replace: line 0
  Assert.AreEqual('alpha one 2', V.LineText(0));
  Key(V, 0, [ssAlt], 's');        // Skip: line 1
  Assert.AreEqual('beta Two three', V.LineText(1), 'skipped');
  Key(V, vkReturn);               // Replace: line 2
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  CursorIs(V, 0, 0, 'after the last answer the cursor is back');
  Assert.IsFalse(V.HasSelection, 'and nothing is selected');
end;

procedure TTestEditorFind.TestStepReplaceAllAnswer;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplace(V, 'two', '2');
  Key(V, 0, [ssAlt], 's');        // Skip line 0
  Key(V, 0, [ssAlt], 'a');        // All: the rest without asking
  Assert.AreEqual('alpha one two', V.LineText(0), 'skipped');
  Assert.AreEqual('beta 2 three', V.LineText(1));
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  // The wrap question comes next: the start was line 0, column 0, so there is
  // nothing before it and the summary is what is shown.
  CursorIs(V, 0, 0, 'the cursor is back');
end;

procedure TTestEditorFind.TestStepReplaceCancelKeepsDone;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplace(V, 'two', '2');
  Key(V, vkReturn);               // Replace line 0
  Key(V, vkEscape);               // Cancel at line 1
  Assert.AreEqual('alpha one 2', V.LineText(0), 'what was answered stays');
  Assert.AreEqual('beta Two three', V.LineText(1), 'the rest is untouched');
  CursorIs(V, 0, 0, 'Cancel puts the cursor back too');
end;

procedure TTestEditorFind.TestStepReplaceWrapsFromTheMiddle;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, vkDown);
  Key(V, vkDown);                 // line 2, column 0
  StartReplace(V, 'two', '2');
  Key(V, vkReturn);               // Replace line 2
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  Key(V, vkReturn);               // Continue from the beginning: OK
  Key(V, vkReturn);               // Replace line 0
  Key(V, vkReturn);               // Replace line 1
  Assert.AreEqual('alpha one 2', V.LineText(0));
  Assert.AreEqual('beta 2 three', V.LineText(1));
  CursorIs(V, 2, 0, 'the cursor is back on the line where it was');
end;

procedure TTestEditorFind.TestStepReplaceDeclinedWrap;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, vkDown);
  Key(V, vkDown);
  StartReplace(V, 'two', '2');
  Key(V, vkReturn);               // Replace line 2
  Key(V, vkEscape);               // do not continue from the beginning
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  Assert.AreEqual('alpha one two', V.LineText(0), 'the part before the start is left alone');
  CursorIs(V, 2, 0, 'the cursor is back');
end;

procedure TTestEditorFind.TestStepReplaceBackward;
var
  V: TEditorWindow;
begin
  GEditorSearchOptions.SearchBackwards := True;
  V := OpenView(FDir);
  FView := V;
  Key(V, vkEnd, [ssCtrl]);
  StartReplace(V, 'two', '2');
  Key(V, vkReturn);               // the last match first: line 2
  Assert.AreEqual('gamma 2 four', V.LineText(2));
  Key(V, vkReturn);               // line 1
  Key(V, vkReturn);               // line 0
  Assert.AreEqual('beta 2 three', V.LineText(1));
  Assert.AreEqual('alpha one 2', V.LineText(0));
  CursorIs(V, 4, 0, 'the cursor is back at the end of the text');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorFind);

end.
