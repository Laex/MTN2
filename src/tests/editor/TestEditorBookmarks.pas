unit TestEditorBookmarks;

{ Editor auto-indent on Enter and line bookmarks (Ctrl+F2 toggles, Ctrl+Shift+F2
  and Ctrl+Alt+F2 walk them). Bookmarks move with the lines around them. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorBookmarks = class
  public
    [Test] procedure TestEnterKeepsTheIndent;
    [Test] procedure TestEnterInsideTheIndentKeepsOnlyTheLeftPart;
    [Test] procedure TestBookmarksWrapInBothDirections;
    [Test] procedure TestBookmarkFollowsInsertedAndDeletedLines;
    [Test] procedure TestBookmarkIsMarkedBesideItsLine;
    [Test] procedure TestAutoIndentCanBeSwitchedOff;
    [Test] procedure TestHotkeyTogglesAutoIndent;
    [Test] procedure TestBookmarkListGoesToTheChosenLine;
    [Test] procedure TestBookmarkListWithoutBookmarksOpensNothing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow, uDisplaySettings;

const
  W = 60;
  H = 12;
  MarkerGlyph = #$25A0;

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
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-bookmark-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure TTestEditorBookmarks.TestEnterKeepsTheIndent;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('  if x then' + sLineBreak + 'end' + sLineBreak, Dir);
  try
    Send(View, vkEnd, []);
    Send(View, vkReturn, []);
    Assert.AreEqual('  ', View.LineText(1), 'new line starts with the indent');
    Assert.AreEqual(1, CursorRow(View));
    Assert.AreEqual(2, CursorCol(View), 'cursor sits after the indent');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestEnterInsideTheIndentKeepsOnlyTheLeftPart;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('    word' + sLineBreak, Dir);
  try
    Send(View, vkRight, []);
    Send(View, vkRight, []);
    Send(View, vkReturn, []);
    Assert.AreEqual('  ', View.LineText(0), 'text left of the cursor stays');
    Assert.AreEqual('    word', View.LineText(1), 'indent taken from the left part, rest follows');
    Assert.AreEqual(2, CursorCol(View));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestBookmarksWrapInBothDirections;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('a' + sLineBreak + 'b' + sLineBreak + 'c' + sLineBreak + 'd' + sLineBreak, Dir);
  try
    Send(View, vkF2, [ssCtrl]);
    Send(View, vkDown, []);
    Send(View, vkDown, []);
    Send(View, vkF2, [ssCtrl]);
    Assert.AreEqual(2, CursorRow(View));

    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(0, CursorRow(View), 'next from the last bookmark wraps to the first');
    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(2, CursorRow(View));
    Send(View, vkF2, [ssCtrl, ssAlt]);
    Assert.AreEqual(0, CursorRow(View));
    Send(View, vkF2, [ssCtrl, ssAlt]);
    Assert.AreEqual(2, CursorRow(View), 'previous from the first bookmark wraps to the last');

    Send(View, vkF2, [ssCtrl]);
    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(0, CursorRow(View), 'a cleared bookmark is gone');
    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(0, CursorRow(View), 'one bookmark left: stays on it');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestBookmarkFollowsInsertedAndDeletedLines;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('a' + sLineBreak + 'b' + sLineBreak + 'c' + sLineBreak, Dir);
  try
    Send(View, vkDown, []);
    Send(View, vkDown, []);
    Send(View, vkF2, [ssCtrl]);
    Send(View, vkHome, [ssCtrl]);
    Send(View, vkReturn, []);
    Send(View, vkHome, [ssCtrl]);
    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(3, CursorRow(View), 'a line inserted above moves the bookmark down');

    Send(View, vkHome, [ssCtrl]);
    Send(View, vkDown, []);
    Send(View, vkEnd, []);
    Send(View, vkDelete, []);
    Send(View, vkHome, [ssCtrl]);
    Send(View, vkF2, [ssCtrl, ssShift]);
    Assert.AreEqual(2, CursorRow(View), 'a line joined above moves the bookmark up');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestBookmarkIsMarkedBesideItsLine;
var
  Dir: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;

  function MarkedRows: Integer;
  var
    Row: Integer;
  begin
    SetLength(Grid, H);
    for Row := 0 to High(Grid) do
      SetLength(Grid[Row], W);
    View.PaintEmbedded(Grid, 0, 0, W, H, 0, 0);
    Result := 0;
    for Row := 0 to High(Grid) do
      if Grid[Row][0].CharValue = MarkerGlyph then
        Inc(Result);
  end;

begin
  View := OpenText('a' + sLineBreak + 'b' + sLineBreak, Dir);
  try
    Assert.AreEqual(0, MarkedRows, 'no bookmark, no marker');
    Send(View, vkF2, [ssCtrl]);
    Assert.AreEqual(1, MarkedRows, 'one marker for one bookmark');
    Send(View, vkF2, [ssCtrl]);
    Assert.AreEqual(0, MarkedRows, 'marker gone with the bookmark');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestAutoIndentCanBeSwitchedOff;
var
  Dir: string;
  View: TEditorWindow;
  Saved: Boolean;
begin
  Saved := GEditorAutoIndent;
  View := OpenText('  if x then' + sLineBreak, Dir);
  try
    GEditorAutoIndent := False;
    Send(View, vkEnd, []);
    Send(View, vkReturn, []);
    Assert.AreEqual('', View.LineText(1), 'no indent while auto-indent is off');
    Assert.AreEqual(0, CursorCol(View));
  finally
    GEditorAutoIndent := Saved;
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestHotkeyTogglesAutoIndent;
var
  Dir: string;
  View: TEditorWindow;
  Saved: Boolean;
begin
  Saved := GEditorAutoIndent;
  View := OpenText('  x' + sLineBreak, Dir);
  try
    GEditorAutoIndent := True;
    Send(View, Ord('I'), [ssCtrl, ssAlt]);
    Assert.IsFalse(GEditorAutoIndent, 'Ctrl+Alt+I switches it off');
    Send(View, vkEnd, []);
    Send(View, vkReturn, []);
    Assert.AreEqual('', View.LineText(1), 'and Enter keeps no indent');
    Send(View, Ord('I'), [ssCtrl, ssAlt]);
    Assert.IsTrue(GEditorAutoIndent, 'Ctrl+Alt+I switches it on again');
  finally
    GEditorAutoIndent := Saved;
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestBookmarkListGoesToTheChosenLine;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('a' + sLineBreak + 'b' + sLineBreak + 'c' + sLineBreak + 'd' + sLineBreak, Dir);
  try
    Send(View, vkF2, [ssCtrl]);
    Send(View, vkDown, []);
    Send(View, vkDown, []);
    Send(View, vkF2, [ssCtrl]);
    Send(View, vkHome, [ssCtrl]);
    Send(View, Ord('B'), [ssCtrl, ssAlt]);
    Assert.IsTrue(View.DialogOpen, 'Ctrl+Alt+B opens the bookmark list');
    Send(View, vkDown, []);
    Send(View, vkReturn, []);
    Pump;
    Assert.IsFalse(View.DialogOpen, 'Enter closes the list');
    Assert.AreEqual(2, CursorRow(View), 'and goes to the second bookmark');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorBookmarks.TestBookmarkListWithoutBookmarksOpensNothing;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('a' + sLineBreak, Dir);
  try
    Send(View, Ord('B'), [ssCtrl, ssAlt]);
    Assert.IsFalse(View.DialogOpen, 'no bookmarks, no dialog');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorBookmarks);

end.
