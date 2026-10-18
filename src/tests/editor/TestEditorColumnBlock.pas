unit TestEditorColumnBlock;

{ Rectangular blocks in the editor: Alt+Shift with the cursor keys selects
  the characters between two columns of several rows; Delete, typing, copy
  and paste then act on every row of it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorColumnBlock = class
  public
    [Test] procedure TestAltShiftArrowsSelectARectangle;
    [Test] procedure TestShortLineDoesNotNarrowTheBlock;
    [Test] procedure TestDeleteRemovesTheRectangle;
    [Test] procedure TestTypingGoesIntoEveryRow;
    [Test] procedure TestBackspaceErasesOneCharacterPerRow;
    [Test] procedure TestShiftArrowTurnsTheBlockIntoAStreamSelection;
    [Test] procedure TestPlainCursorKeyDropsTheBlock;
    [Test] procedure TestUndoRestoresAfterDeletingABlock;
    [Test] procedure TestCopiedBlockIsPastedAsABlock;
    [Test] procedure TestCutRemovesTheBlockAndKeepsItForPaste;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uVfsTypes, uThemeRegistry, uEditorWindow;

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

procedure TypeChar(AView: TEditorWindow; ACh: Char);
var
  K: Word;
  Ch: Char;
begin
  K := 0;
  Ch := ACh;
  AView.HandleInput(K, [], Ch);
end;

procedure BlockKey(AView: TEditorWindow; AKey: Word; ATimes: Integer = 1);
var
  I: Integer;
begin
  for I := 1 to ATimes do
    Send(AView, AKey, [ssAlt, ssShift]);
end;

function OpenText(const AText: string; out ADir: string): TEditorWindow;
var
  Path: string;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-colblock-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

const
  Three = 'abcdef' + sLineBreak + 'ghijkl' + sLineBreak + 'mnopqr' + sLineBreak;

procedure TTestEditorColumnBlock.TestAltShiftArrowsSelectARectangle;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 2);
    Assert.IsTrue(View.ColumnBlockActive, 'a block, not a stream selection');
    Assert.AreEqual('bc'#10'hi'#10'no', View.SelectionText);
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestShortLineDoesNotNarrowTheBlock;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('abcdef' + sLineBreak + 'gh' + sLineBreak + 'mnopqr' + sLineBreak, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 3);
    BlockKey(View, vkDown, 2);
    Assert.AreEqual('bcd'#10'h'#10'nop', View.SelectionText,
      'the short line gives what it has, the others keep the width');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestDeleteRemovesTheRectangle;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 2);
    Send(View, vkDelete, []);
    Assert.AreEqual('adef', View.LineText(0));
    Assert.AreEqual('gjkl', View.LineText(1));
    Assert.AreEqual('mpqr', View.LineText(2));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestTypingGoesIntoEveryRow;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 2);
    BlockKey(View, vkDown, 2);
    TypeChar(View, 'X');
    TypeChar(View, 'Y');
    Assert.AreEqual('abXYcdef', View.LineText(0));
    Assert.AreEqual('ghXYijkl', View.LineText(1));
    Assert.AreEqual('mnXYopqr', View.LineText(2));
    Assert.IsTrue(View.ColumnBlockActive, 'the caret stays over all the rows');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestBackspaceErasesOneCharacterPerRow;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 3);
    BlockKey(View, vkDown, 2);
    Send(View, vkBack, []);
    Assert.AreEqual('abdef', View.LineText(0));
    Assert.AreEqual('ghjkl', View.LineText(1));
    Assert.AreEqual('mnpqr', View.LineText(2));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestShiftArrowTurnsTheBlockIntoAStreamSelection;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 1);
    Assert.IsTrue(View.ColumnBlockActive);
    Send(View, vkDown, [ssShift]);
    Assert.IsFalse(View.ColumnBlockActive);
    Assert.IsTrue(View.HasSelection, 'still selected, as a run of text');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestPlainCursorKeyDropsTheBlock;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 1);
    Send(View, vkLeft, []);
    Assert.IsFalse(View.HasSelection);
    Assert.IsFalse(View.ColumnBlockActive);
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestUndoRestoresAfterDeletingABlock;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 2);
    Send(View, vkDelete, []);
    Send(View, Ord('Z'), [ssCtrl]);
    Assert.AreEqual('abcdef', View.LineText(0));
    Assert.AreEqual('ghijkl', View.LineText(1));
    Assert.AreEqual('mnopqr', View.LineText(2));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestCopiedBlockIsPastedAsABlock;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 1);
    BlockKey(View, vkRight, 2);
    BlockKey(View, vkDown, 1);
    Send(View, Ord('C'), [ssCtrl]);
    View.SetViewPos(0, 1, 6);
    Send(View, Ord('V'), [ssCtrl]);
    Assert.AreEqual('abcdef', View.LineText(0));
    Assert.AreEqual('ghijklbc', View.LineText(1), 'the block starts at the cursor column');
    Assert.AreEqual('mnopqrhi', View.LineText(2), 'the next row takes the next piece');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorColumnBlock.TestCutRemovesTheBlockAndKeepsItForPaste;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText(Three, Dir);
  try
    View.SetViewPos(0, 0, 0);
    BlockKey(View, vkRight, 1);
    BlockKey(View, vkDown, 2);
    Send(View, Ord('X'), [ssCtrl]);
    Assert.AreEqual('bcdef', View.LineText(0));
    Assert.AreEqual('hijkl', View.LineText(1));
    Assert.AreEqual('nopqr', View.LineText(2));
    View.SetViewPos(0, 0, 5);
    Send(View, Ord('V'), [ssCtrl]);
    Assert.AreEqual('bcdefa', View.LineText(0));
    Assert.AreEqual('hijklg', View.LineText(1));
    Assert.AreEqual('nopqrm', View.LineText(2));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorColumnBlock);

end.
