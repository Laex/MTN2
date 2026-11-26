unit TestEditorScan;

{ Search and replace over a document take portions on the main thread: Esc stops
  them, keys do not edit the text meanwhile and a stopped Replace All changes
  nothing. The portions are cut down to one unit each here, so a short text is
  enough to leave a pass unfinished after the key that started it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorScan = class
  private
    FDir: string;
    FView: TObject;
    FFirstMs, FSliceMs: Cardinal;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestLongFindFinishesInPortions;
    [Test] procedure TestEscStopsFind;
    [Test] procedure TestProgressWindowIsOpenWhileSearching;
    [Test] procedure TestProgressWindowButtonStopsReplace;
    [Test] procedure TestKeysDoNotEditWhileSearching;
    [Test] procedure TestReplaceAllFinishesInPortions;
    [Test] procedure TestCancelledReplaceAllChangesNothing;
    [Test] procedure TestCancelledStepReplaceAllKeepsDone;
    [Test] procedure TestIncSearchRestartsOnNextLetter;
    [Test] procedure TestHexFindFinishesInPortions;
    [Test] procedure TestFindBytesTakesPortionOfTheWalk;
    [Test] procedure TestSearchOfMarkdownTableIsQuick;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uVfsTypes, uThemeRegistry, uCoreTimer, uEditorWindow, uEditorSearch,
  uEditorScan, uEditorHexView;

const
  cLines = 60;
  cNeedleLine = 45;

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
begin
  for I := 1 to Length(AText) do
    Key(AView, 0, [], AText[I]);
end;

// One turn of the host loop: queued calls and due timers.
procedure Turn;
begin
  CheckSynchronize(0);
  Sleep(2);
  ProcessCoreTimers;
end;

procedure RunToEnd(AView: TEditorWindow);
var
  T: UInt64;
begin
  T := TThread.GetTickCount64 + 10000;
  while AView.Searching do
  begin
    Assert.IsTrue(TThread.GetTickCount64 < T, 'the search ends');
    Turn;
  end;
end;

procedure RunTurns(ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to ACount do
    Turn;
end;

function LineOf(AIndex: Integer): string;
begin
  if AIndex = cNeedleLine then
    Result := 'needle two'
  else
    Result := 'line two';
end;

function OpenView(const ADir: string): TEditorWindow;
var
  Path, Text: string;
  I: Integer;
  T: UInt64;
begin
  Text := '';
  for I := 0 to cLines - 1 do
    Text := Text + LineOf(I) + sLineBreak;
  Path := TPath.Combine(ADir, 'f.txt');
  TFile.WriteAllText(Path, Text, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  T := TThread.GetTickCount64 + 10000;
  while not Result.DocReady and (TThread.GetTickCount64 < T) do
    CheckSynchronize(10);
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

procedure StartFind(AView: TEditorWindow; const AText: string);
begin
  Key(AView, vkF7);
  TypeText(AView, AText);
  Key(AView, vkReturn);
end;

procedure StartReplaceAll(AView: TEditorWindow; const AFind, ARepl: string);
begin
  AView.OpenReplaceDialog;
  TypeText(AView, AFind);
  Key(AView, vkTab);
  TypeText(AView, ARepl);
  Key(AView, 0, [ssAlt], 'a');
end;

procedure TTestEditorScan.Setup;
begin
  FFirstMs := GEditorScanFirstMs;
  FSliceMs := GEditorScanSliceMs;
  GEditorScanFirstMs := 0;
  GEditorScanSliceMs := 0;
  GEditorSearchOptions := DefaultSearchOptions;
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-scan-' + TPath.GetGUIDFileName(False));
  ForceDirectories(FDir);
end;

procedure TTestEditorScan.TearDown;
begin
  FreeAndNil(FView);
  GEditorScanFirstMs := FFirstMs;
  GEditorScanSliceMs := FSliceMs;
  GEditorSearchOptions := DefaultSearchOptions;
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestEditorScan.TestLongFindFinishesInPortions;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartFind(V, 'needle');
  Assert.IsTrue(V.Searching, 'the pass is still running');
  CursorIs(V, 0, 0, 'nothing moves before the match is reached');
  RunToEnd(V);
  CursorIs(V, cNeedleLine, 6, 'the match, cursor at its end');
  Assert.IsTrue(V.HasSelection, 'the match is selected');
end;

procedure TTestEditorScan.TestEscStopsFind;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartFind(V, 'needle');
  RunTurns(5);
  Key(V, vkEscape);
  Assert.IsFalse(V.Searching, 'Esc stops the pass');
  RunTurns(cLines);
  CursorIs(V, 0, 0, 'nothing moved');
  Assert.IsFalse(V.HasSelection, 'nothing selected');
end;

procedure TTestEditorScan.TestProgressWindowIsOpenWhileSearching;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartFind(V, 'needle');
  Assert.IsTrue(V.DialogOpen, 'the progress window is up');
  // A click beside it leaves the pass running.
  V.HandleMouseDown(2, 2, []);
  Assert.IsTrue(V.Searching, 'a click outside the window stops nothing');
  RunToEnd(V);
  Assert.IsFalse(V.DialogOpen, 'and the window is gone with the pass');
end;

procedure TTestEditorScan.TestProgressWindowButtonStopsReplace;
var
  V: TEditorWindow;
  I: Integer;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplaceAll(V, 'two', '2');
  Key(V, vkReturn);               // the Cancel button of the progress window
  I := 0;
  while V.Searching and (I < 30) do
  begin
    Turn;
    Inc(I);
  end;
  Assert.IsFalse(V.Searching, 'the button stops the pass');
  Assert.IsFalse(V.DialogOpen, 'the window is closed');
  RunTurns(cLines);
  Assert.AreEqual('line two', V.LineText(0), 'nothing was replaced');
end;

procedure TTestEditorScan.TestKeysDoNotEditWhileSearching;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartFind(V, 'needle');
  TypeText(V, 'x');
  Key(V, vkDelete);
  Assert.IsTrue(V.Searching, 'other keys leave the pass running');
  Assert.AreEqual('line two', V.LineText(0), 'the text is as it was');
  RunToEnd(V);
  CursorIs(V, cNeedleLine, 6, 'and the match is found');
end;

procedure TTestEditorScan.TestReplaceAllFinishesInPortions;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplaceAll(V, 'two', '2');
  Assert.IsTrue(V.Searching, 'the pass is still running');
  Assert.AreEqual('line two', V.LineText(0), 'nothing is changed before the end');
  RunToEnd(V);
  Assert.AreEqual('line 2', V.LineText(0));
  Assert.AreEqual('needle 2', V.LineText(cNeedleLine));
  Assert.AreEqual('line 2', V.LineText(cLines - 1));
end;

procedure TTestEditorScan.TestCancelledReplaceAllChangesNothing;
var
  V: TEditorWindow;
  I: Integer;
begin
  V := OpenView(FDir);
  FView := V;
  StartReplaceAll(V, 'two', '2');
  RunTurns(10);
  Assert.IsTrue(V.Searching, 'the pass is still running');
  Key(V, vkEscape);
  Assert.IsFalse(V.Searching, 'Esc stops the pass');
  RunTurns(cLines);
  for I := 0 to cLines - 1 do
    Assert.AreEqual(LineOf(I), V.LineText(I), 'line ' + IntToStr(I));
end;

procedure TTestEditorScan.TestCancelledStepReplaceAllKeepsDone;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  V.OpenReplaceDialog;
  TypeText(V, 'two');
  Key(V, vkTab);
  TypeText(V, '2');
  Key(V, vkReturn);
  RunToEnd(V);                    // the question about the first match
  Key(V, 0, [ssAlt], 'a');        // All
  RunTurns(10);
  Assert.IsTrue(V.Searching, 'the pass is still running');
  Key(V, vkEscape);
  Assert.IsFalse(V.Searching, 'Esc stops the pass');
  Assert.AreEqual('line 2', V.LineText(0), 'what was replaced stays');
  Assert.AreEqual('line two', V.LineText(cLines - 1), 'the rest is untouched');
  Key(V, Ord('Z'), [ssCtrl]);
  Assert.AreEqual('line two', V.LineText(0), 'one undo step takes it back');
end;

procedure TTestEditorScan.TestIncSearchRestartsOnNextLetter;
var
  V: TEditorWindow;
begin
  V := OpenView(FDir);
  FView := V;
  Key(V, Ord('T'), [ssCtrl, ssAlt]);
  TypeText(V, 'nee');
  RunToEnd(V);
  CursorIs(V, cNeedleLine, 3, 'all typed letters are searched for');
end;

procedure TTestEditorScan.TestHexFindFinishesInPortions;
var
  V: TEditorWindow;
  Path: string;
  Data: TBytes;
  T: UInt64;
begin
  // Longer than one block of start positions.
  SetLength(Data, 200 * 1024);
  FillChar(Data[0], Length(Data), Ord('.'));
  Move(TEncoding.ASCII.GetBytes('needle')[0], Data[150 * 1024], 6);
  Path := TPath.Combine(FDir, 'b.bin');
  TFile.WriteAllBytes(Path, Data);
  V := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  FView := V;
  V.Open(PathToFileUri(Path), False);
  T := TThread.GetTickCount64 + 10000;
  while not V.DocReady and (TThread.GetTickCount64 < T) do
    CheckSynchronize(10);
  Assert.IsTrue(V.DocReady, 'document loaded');
  if not V.HexMode then
    V.ToggleHexMode;
  RunTurns(2);
  StartFind(V, 'needle');
  Assert.IsTrue(V.Searching, 'the pass is still running');
  RunToEnd(V);
  Assert.IsTrue(V.HasSelection, 'the match is selected');
end;

procedure TTestEditorScan.TestFindBytesTakesPortionOfTheWalk;
var
  Data: TBytes;
  Get: TGetByteFunc;

  function Find(AStart: Integer; AForward: Boolean; ASkip, ACount: Integer): Integer;
  begin
    Result := TEditorHexFormatter.FindBytes(Length(Data), Get, [Ord('x')], AStart,
      AForward, False, ASkip, ACount);
  end;

begin
  Data := TEncoding.ASCII.GetBytes('..x....x..');
  Get :=
    function(AIndex: Integer): Byte
    begin
      Result := Data[AIndex];
    end;
  Assert.AreEqual(-1, Find(4, True, 0, 3), 'starts 4..6');
  Assert.AreEqual(7, Find(4, True, 3, 3), 'starts 7..9');
  Assert.AreEqual(2, Find(4, True, 6, 4), 'starts 0..3 after the wrap');
  Assert.AreEqual(-1, Find(2, False, 0, 2), 'starts 1 and 0');
  Assert.AreEqual(7, Find(2, False, 2, 8), 'from the end after the wrap');
  Assert.AreEqual(-1, Find(4, True, 10, 3), 'nothing past the end of the walk');
end;

procedure TTestEditorScan.TestSearchOfMarkdownTableIsQuick;
const
  cRows = 250;
var
  V: TEditorWindow;
  Path, Text: string;
  I: Integer;
  T, Started: UInt64;
begin
  GEditorScanFirstMs := FFirstMs;
  GEditorScanSliceMs := FSliceMs;
  Text := '| N | Name |' + sLineBreak + '|---|---|' + sLineBreak;
  for I := 1 to cRows do
    Text := Text + Format('| %d | work number %d |', [I, I]) + sLineBreak;
  Path := TPath.Combine(FDir, 't.md');
  TFile.WriteAllText(Path, Text, TEncoding.UTF8);
  V := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  FView := V;
  V.Open(PathToFileUri(Path), True);
  T := TThread.GetTickCount64 + 10000;
  while not V.DocReady and (TThread.GetTickCount64 < T) do
    CheckSynchronize(10);
  if not V.MarkdownMode then
    V.ToggleMarkdownMode;
  Started := TThread.GetTickCount64;
  StartFind(V, 'work number 250');
  RunToEnd(V);
  // Reading a table row looks at the rows around it; the whole table has to
  // stay a matter of moments, not of re-reading the document for each row.
  Assert.IsTrue(TThread.GetTickCount64 - Started < 3000, 'searched quickly');
  Assert.IsTrue(V.HasSelection, 'the last row is found');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorScan);

end.
