unit TestEditorWideChars;

{ Chinese text in the Editor and Viewer: the caret, horizontal scrolling,
  mouse clicks and word wrap count a wide character as two cells, and a file
  in a legacy Chinese code page opens decoded. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorWideChars = class
  public
    [Test] procedure TestCaretCountsWideCharactersAsTwoCells;
    [Test] procedure TestLongWideLineScrollsByCells;
    [Test] procedure TestClickLandsOnTheCharacterUnderTheCell;
    [Test] procedure TestWordWrapKeepsEveryWideCharacter;
    [Test] procedure TestGbkFileOpensDecoded;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow, uCharWidth;

const
  W = 60;
  H = 12;
  cZhong = #$4E2D;
  cWen = #$6587;
  cSimplified = #$4E2D#$6587#$6D4B#$8BD5#$7F16#$7801;

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

procedure Send(AView: TEditorWindow; AKey: Word; AChar: Char);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := AChar;
  AView.HandleInput(K, [], Ch);
end;

function Paint(AView: TEditorWindow): TTerminalGrid;
var
  Y: Integer;
begin
  SetLength(Result, H);
  for Y := 0 to High(Result) do
    SetLength(Result[Y], W);
  AView.PaintEmbedded(Result, 0, 0, W, H, 0, 0);
end;

function RowText(const AGrid: TTerminalGrid; ARow: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to High(AGrid[ARow]) do
    Result := Result + AGrid[ARow][X].CharValue;
end;

function CaretCol(const AGrid: TTerminalGrid; ARow: Integer): Integer;
var
  X: Integer;
begin
  for X := 0 to High(AGrid[ARow]) do
    if ccaInsertCaret in AGrid[ARow][X].Attributes then
      Exit(X);
  Result := -1;
end;

function RowWith(const AGrid: TTerminalGrid; const AText: string): Integer;
var
  Y: Integer;
begin
  for Y := 0 to High(AGrid) do
    if Pos(AText, RowText(AGrid, Y)) > 0 then
      Exit(Y);
  Result := -1;
end;

function CountChar(const AGrid: TTerminalGrid; ACh: Char): Integer;
var
  Y, X: Integer;
begin
  Result := 0;
  for Y := 0 to High(AGrid) do
    for X := 0 to High(AGrid[Y]) do
      if AGrid[Y][X].CharValue = ACh then
        Inc(Result);
end;

function NewDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-wide-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Result);
end;

function OpenFile(const APath: string; AViewOnly: Boolean): TEditorWindow;
begin
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(APath), AViewOnly);
  Pump;
end;

procedure TTestEditorWideChars.TestCaretCountsWideCharactersAsTwoCells;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Row, TextStart: Integer;
begin
  Dir := NewDir;
  Path := TPath.Combine(Dir, 'a.txt');
  TFile.WriteAllText(Path, cZhong + cWen + 'abc' + sLineBreak, TEncoding.UTF8);
  View := OpenFile(Path, False);
  try
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := RowWith(Grid, cZhong);
    Assert.IsTrue(Row >= 0, 'line drawn');
    TextStart := Pos(cZhong, RowText(Grid, Row)) - 1;

    Send(View, vkEnd, #0);
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 4 + 3, CaretCol(Grid, Row), 'End: after two wide and three narrow characters');

    Send(View, vkHome, #0);
    Send(View, vkRight, #0);
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 2, CaretCol(Grid, Row), 'Right over one wide character');
    Send(View, vkRight, #0);
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 4, CaretCol(Grid, Row), 'Right over the second one');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorWideChars.TestLongWideLineScrollsByCells;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Row: Integer;
begin
  Dir := NewDir;
  Path := TPath.Combine(Dir, 'b.txt');
  TFile.WriteAllText(Path, StringOfChar(cZhong, 100) + sLineBreak, TEncoding.UTF8);
  View := OpenFile(Path, False);
  try
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := RowWith(Grid, cZhong);
    Assert.IsTrue(Row >= 0, 'line drawn');
    // 57 text cells hold 28 wide characters (56 cells); the 29th would be cut.
    Assert.AreEqual(28, CountChar(Grid, cZhong), 'start of the line');

    Send(View, vkEnd, #0);
    Grid := Paint(View);
    Assert.AreEqual(1 + 56, CaretCol(Grid, Row), 'caret after the last character, inside the text area');
    Assert.AreEqual(28, CountChar(Grid, cZhong), 'the line end is scrolled into view');

    Send(View, vkHome, #0);
    Grid := Paint(View);
    Assert.AreEqual(1, CaretCol(Grid, Row), 'Home scrolls back');
    Assert.AreEqual(28, CountChar(Grid, cZhong));
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorWideChars.TestClickLandsOnTheCharacterUnderTheCell;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Row, TextStart: Integer;
begin
  Dir := NewDir;
  Path := TPath.Combine(Dir, 'c.txt');
  TFile.WriteAllText(Path, cZhong + cWen + 'abc' + sLineBreak, TEncoding.UTF8);
  View := OpenFile(Path, False);
  try
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := RowWith(Grid, cZhong);
    Assert.IsTrue(Row >= 0, 'line drawn');
    TextStart := Pos(cZhong, RowText(Grid, Row)) - 1;

    View.HandleMouseDown(TextStart + 4, Row, []);
    View.HandleMouseUp;
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 4, CaretCol(Grid, Row), 'first narrow character');

    View.HandleMouseDown(TextStart + 3, Row, []);
    View.HandleMouseUp;
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 2, CaretCol(Grid, Row), 'second half of the second wide character');

    View.HandleMouseDown(TextStart + 20, Row, []);
    View.HandleMouseUp;
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 4 + 3, CaretCol(Grid, Row), 'past the end of the line');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorWideChars.TestWordWrapKeepsEveryWideCharacter;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
begin
  Dir := NewDir;
  Path := TPath.Combine(Dir, 'd.txt');
  TFile.WriteAllText(Path, StringOfChar(cWen, 70) + sLineBreak + 'tail' + sLineBreak, TEncoding.UTF8);
  View := OpenFile(Path, True);
  try
    Assert.IsTrue(View.DocReady, 'document loaded');
    Send(View, vkF2, #0);
    Grid := Paint(View);
    Assert.AreEqual(70, CountChar(Grid, cWen), 'every character of the long line is on some row');
    Assert.IsTrue(RowWith(Grid, 'tail') >= 0, 'the next line follows the wrapped rows');
    // 57 cells hold 28 characters per row: 28 + 28 + 14.
    Assert.AreEqual(RowWith(Grid, cWen) + 3, RowWith(Grid, 'tail'), 'three rows for the long line');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorWideChars.TestGbkFileOpensDecoded;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Enc: TEncoding;
  Row: Integer;
begin
  Dir := NewDir;
  Path := TPath.Combine(Dir, 'e.txt');
  Enc := TEncoding.GetEncoding(936);
  try
    TFile.WriteAllBytes(Path, Enc.GetBytes(cSimplified + ' ok'));
  finally
    Enc.Free;
  end;
  View := OpenFile(Path, True);
  try
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := RowWith(Grid, cZhong);
    Assert.IsTrue(Row >= 0, 'decoded text drawn');
    Assert.IsTrue(Pos(cSimplified + ' ok', StripWideFillers(RowText(Grid, Row))) > 0,
      'all characters decoded');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorWideChars);

end.
