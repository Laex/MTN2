unit TestEditorTextTools;

{ Editor text tools: change case, align, auto-wrap, incremental search and
  line drawing. The pure helpers are tested on strings; the commands through
  their Ctrl+Alt hotkeys in an open document. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorTextTools = class
  public
    [Test] procedure TestChangedCaseModes;
    [Test] procedure TestTitleCaseKeepsApostropheInsideWord;
    [Test] procedure TestNextCaseModeFollowsTheState;
    [Test] procedure TestAlignedLinesLeftCenterRight;
    [Test] procedure TestBoxMaskReadsStraightPiecesAsFullLines;
    [Test] procedure TestBoxCharJoinsSides;
    [Test] procedure TestChangeCaseCyclesTheWordUnderTheCursor;
    [Test] procedure TestChangeCaseOnSelectionKeepsTheSelection;
    [Test] procedure TestAlignCentersTheParagraphAroundTheCursor;
    [Test] procedure TestAutoWrapBreaksAtTheLastSpace;
    [Test] procedure TestAutoWrapOffKeepsTheLongLine;
    [Test] procedure TestIncSearchSelectsTheMatchWhileTyping;
    [Test] procedure TestIncSearchDownGoesToTheNextMatch;
    [Test] procedure TestIncSearchEscapeReturnsToTheStart;
    [Test] procedure TestIncSearchEnterKeepsTheMatch;
    [Test] procedure TestDrawLinesJoinsCorners;
    [Test] procedure TestDrawLinesIsOneUndoStep;
    [Test] procedure TestDrawLinesHotkeyCyclesToOff;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow, uEditorLineOps;

const
  Horiz = #$2500;
  Vert = #$2502;
  TeeDown = #$252C;
  HorizDouble = #$2550;

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

procedure Send(AView: TEditorWindow; AKey: Word; AShift: TShiftState);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  AView.HandleInput(K, AShift, Ch);
end;

procedure TypeText(AView: TEditorWindow; const AText: string);
var
  C: Char;
  K: Word;
  Ch: Char;
begin
  for C in AText do
  begin
    K := 0;
    Ch := C;
    AView.HandleInput(K, [], Ch);
  end;
end;

function CursorRow(AView: TEditorWindow): Integer;
var
  Top, Row, Col: Integer;
begin
  AView.GetViewPos(Top, Row, Col);
  Result := Row;
end;

function CursorCol(AView: TEditorWindow): Integer;
var
  Top, Row, Col: Integer;
begin
  AView.GetViewPos(Top, Row, Col);
  Result := Col;
end;

function OpenText(const AText: string; out ADir: string): TEditorWindow;
var
  Path: string;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-texttools-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure Done(AView: TEditorWindow; const ADir: string);
begin
  AView.Free;
  TDirectory.Delete(ADir, True);
end;

function Join(const ALines: TArray<string>): string;
var
  S: string;
begin
  Result := '';
  for S in ALines do
    Result := Result + '[' + S + ']';
end;

procedure TTestEditorTextTools.TestChangedCaseModes;
begin
  Assert.AreEqual('HELLO WORLD 1', ChangedCase('hello World 1', cmUpper));
  Assert.AreEqual('hello world', ChangedCase('HeLLo WORLD', cmLower));
  Assert.AreEqual('Hello World', ChangedCase('hELLO wORLD', cmTitle));
end;

procedure TTestEditorTextTools.TestTitleCaseKeepsApostropheInsideWord;
begin
  Assert.AreEqual('Don''t Stop', ChangedCase('dON''T sTOP', cmTitle));
end;

procedure TTestEditorTextTools.TestNextCaseModeFollowsTheState;
begin
  Assert.AreEqual(Ord(cmUpper), Ord(NextCaseMode('123')), 'no letters');
  Assert.AreEqual(Ord(cmLower), Ord(NextCaseMode('ABC')), 'upper -> lower');
  Assert.AreEqual(Ord(cmTitle), Ord(NextCaseMode('abc')), 'lower -> title');
  Assert.AreEqual(Ord(cmUpper), Ord(NextCaseMode('Abc dEf')), 'mixed -> upper');
end;

procedure TTestEditorTextTools.TestAlignedLinesLeftCenterRight;
const
  Src: array[0..2] of string = ('  a  ', 'bbbb', '   ');
var
  L: TArray<string>;
begin
  L := TArray<string>.Create(Src[0], Src[1], Src[2]);
  Assert.AreEqual('[a][bbbb][]', Join(AlignedLines(L, 0, 2, amLeft)));
  Assert.AreEqual('[ a][bbbb][]', Join(AlignedLines(L, 0, 2, amCenter)));
  Assert.AreEqual('[   a][bbbb][]', Join(AlignedLines(L, 0, 2, amRight)));
end;

procedure TTestEditorTextTools.TestBoxMaskReadsStraightPiecesAsFullLines;
begin
  Assert.AreEqual(cBoxUp or cBoxDown, BoxMask(Vert));
  Assert.AreEqual(cBoxLeft or cBoxRight, BoxMask(Horiz));
  Assert.AreEqual(cBoxLeft or cBoxRight, BoxMask(HorizDouble));
  Assert.AreEqual(0, BoxMask('x'));
end;

procedure TTestEditorTextTools.TestBoxCharJoinsSides;
begin
  Assert.AreEqual(Horiz, BoxChar(cBoxLeft or cBoxRight, bsSingle));
  Assert.AreEqual(HorizDouble, BoxChar(cBoxLeft or cBoxRight, bsDouble));
  Assert.AreEqual(TeeDown, BoxChar(cBoxLeft or cBoxRight or cBoxDown, bsSingle));
  Assert.AreEqual(Horiz, BoxChar(cBoxRight, bsSingle), 'a single side is a straight piece');
  Assert.AreEqual(' ', BoxChar(0, bsSingle));
end;

procedure TTestEditorTextTools.TestChangeCaseCyclesTheWordUnderTheCursor;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('hello world' + sLineBreak, Dir);
  try
    Send(View, vkHome, []);
    Send(View, vkRight, []);
    Send(View, vkRight, []);
    Send(View, Ord('C'), [ssCtrl, ssAlt]);
    Assert.AreEqual('Hello world', View.LineText(0), 'lower -> title');
    Send(View, Ord('C'), [ssCtrl, ssAlt]);
    Assert.AreEqual('HELLO world', View.LineText(0), 'title -> upper');
    Send(View, Ord('C'), [ssCtrl, ssAlt]);
    Assert.AreEqual('hello world', View.LineText(0), 'upper -> lower');
    Assert.AreEqual(2, CursorCol(View), 'the cursor stays');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestChangeCaseOnSelectionKeepsTheSelection;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('abc def' + sLineBreak, Dir);
  try
    Send(View, vkHome, []);
    Send(View, vkEnd, [ssShift]);
    Send(View, Ord('C'), [ssCtrl, ssAlt]);
    Assert.AreEqual('Abc Def', View.LineText(0));
    Send(View, Ord('C'), [ssCtrl, ssAlt]);
    Assert.AreEqual('ABC DEF', View.LineText(0), 'the selection survived for the next step');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestAlignCentersTheParagraphAroundTheCursor;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('a' + sLineBreak + 'bbbb' + sLineBreak + sLineBreak + 'c' + sLineBreak, Dir);
  try
    Send(View, vkHome, [ssCtrl]);
    Send(View, Ord('E'), [ssCtrl, ssAlt]);
    Assert.AreEqual(' a', View.LineText(0));
    Assert.AreEqual('bbbb', View.LineText(1));
    Assert.AreEqual('c', View.LineText(3), 'the next paragraph is untouched');
    Send(View, Ord('R'), [ssCtrl, ssAlt]);
    Assert.AreEqual('   a', View.LineText(0));
    Send(View, Ord('L'), [ssCtrl, ssAlt]);
    Assert.AreEqual('a', View.LineText(0));
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestAutoWrapBreaksAtTheLastSpace;
var
  Dir: string;
  View: TEditorWindow;
  SavedWrap: Boolean;
  SavedWidth: Integer;
begin
  SavedWrap := GEditorAutoWrap;
  SavedWidth := GEditorReflowWidth;
  View := OpenText('', Dir);
  try
    GEditorAutoWrap := False;
    GEditorReflowWidth := 10;
    Send(View, Ord('W'), [ssCtrl, ssAlt]);
    Assert.IsTrue(GEditorAutoWrap, 'Ctrl+Alt+W switches it on');
    TypeText(View, 'aaaa bbbb cccc');
    Assert.AreEqual('aaaa bbbb', View.LineText(0));
    Assert.AreEqual('cccc', View.LineText(1));
    Assert.AreEqual(1, CursorRow(View));
    Assert.AreEqual(4, CursorCol(View));
  finally
    GEditorAutoWrap := SavedWrap;
    GEditorReflowWidth := SavedWidth;
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestAutoWrapOffKeepsTheLongLine;
var
  Dir: string;
  View: TEditorWindow;
  SavedWrap: Boolean;
  SavedWidth: Integer;
begin
  SavedWrap := GEditorAutoWrap;
  SavedWidth := GEditorReflowWidth;
  View := OpenText('', Dir);
  try
    GEditorAutoWrap := False;
    GEditorReflowWidth := 10;
    TypeText(View, 'aaaa bbbb cccc');
    Assert.AreEqual('aaaa bbbb cccc', View.LineText(0));
  finally
    GEditorAutoWrap := SavedWrap;
    GEditorReflowWidth := SavedWidth;
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestIncSearchSelectsTheMatchWhileTyping;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('one two three two' + sLineBreak, Dir);
  try
    Send(View, Ord('T'), [ssCtrl, ssAlt]);
    TypeText(View, 'tw');
    Assert.AreEqual(6, CursorCol(View), 'cursor after the first "tw"');
    Assert.AreEqual('one two three two', View.LineText(0), 'typed letters are not inserted');
    Send(View, vkBack, []);
    Assert.AreEqual(5, CursorCol(View), 'one letter left: the match is "t"');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestIncSearchDownGoesToTheNextMatch;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('one two three two' + sLineBreak, Dir);
  try
    Send(View, Ord('T'), [ssCtrl, ssAlt]);
    TypeText(View, 'two');
    Assert.AreEqual(7, CursorCol(View));
    Send(View, vkDown, []);
    Assert.AreEqual(17, CursorCol(View), 'second "two"');
    Send(View, vkUp, []);
    Assert.AreEqual(7, CursorCol(View), 'and back');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestIncSearchEscapeReturnsToTheStart;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('one two three' + sLineBreak, Dir);
  try
    Send(View, vkRight, []);
    Send(View, Ord('T'), [ssCtrl, ssAlt]);
    TypeText(View, 'three');
    Assert.AreEqual(13, CursorCol(View));
    Send(View, vkEscape, []);
    Assert.AreEqual(1, CursorCol(View), 'Esc returns to where the search began');
    TypeText(View, 'x');
    Assert.AreEqual('oxne two three', View.LineText(0), 'typing works again');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestIncSearchEnterKeepsTheMatch;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('one two three' + sLineBreak, Dir);
  try
    Send(View, Ord('T'), [ssCtrl, ssAlt]);
    TypeText(View, 'two');
    Send(View, vkReturn, []);
    Assert.AreEqual(7, CursorCol(View));
    Assert.AreEqual('one two three', View.LineText(0), 'Enter does not break the line');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestDrawLinesJoinsCorners;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('' + sLineBreak, Dir);
  try
    Send(View, Ord('D'), [ssCtrl, ssAlt]);
    Send(View, vkRight, []);
    Send(View, vkDown, []);
    Assert.AreEqual(Horiz + TeeDown, View.LineText(0), 'the turn joins into a tee');
    Assert.AreEqual(' ' + Vert, View.LineText(1));
    Send(View, vkEscape, []);
    Send(View, vkRight, []);
    Assert.AreEqual(' ' + Vert, View.LineText(1), 'after Esc the arrows only move');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestDrawLinesIsOneUndoStep;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('' + sLineBreak, Dir);
  try
    Send(View, Ord('D'), [ssCtrl, ssAlt]);
    Send(View, vkRight, []);
    Send(View, vkRight, []);
    Send(View, vkDown, []);
    Send(View, vkEscape, []);
    Send(View, Ord('Z'), [ssCtrl]);
    Assert.AreEqual('', View.LineText(0), 'one Ctrl+Z takes the whole drawing back');
  finally
    Done(View, Dir);
  end;
end;

procedure TTestEditorTextTools.TestDrawLinesHotkeyCyclesToOff;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('' + sLineBreak, Dir);
  try
    Send(View, Ord('D'), [ssCtrl, ssAlt]);
    Send(View, Ord('D'), [ssCtrl, ssAlt]);
    Send(View, vkRight, []);
    Assert.AreEqual(HorizDouble + HorizDouble, View.LineText(0), 'second step draws double lines');
    Send(View, Ord('D'), [ssCtrl, ssAlt]);
    Send(View, vkRight, []);
    Assert.AreEqual(HorizDouble + HorizDouble, View.LineText(0), 'third step is off: nothing more drawn');
    Assert.AreEqual(2, CursorCol(View));
  finally
    Done(View, Dir);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorTextTools);

end.
