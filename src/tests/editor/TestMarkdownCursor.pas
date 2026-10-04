unit TestMarkdownCursor;

{ Cursor keys in the Markdown view: Down walks every screen row of a table row
  whose cells wrap (the cursor column is not cut to the length of the source
  line), and a picture is crossed with the text below it kept in view: the
  window scrolls by the height of the picture instead of losing the cursor. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMarkdownCursor = class
  private
    FDir: string;
    FView: TObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestDownWalksRowsOfAWrappedTableRow;
    [Test] procedure TestDownWalksRowsOfAWideTableRow;
    [Test] procedure TestDownKeepsCursorVisibleAcrossAPicture;
    [Test] procedure TestDoubleClickSelectsWordOnWrappedLine;
    [Test] procedure TestSelectedTextIsTheDisplayedText;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  System.UITypes, uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow;

const
  W = 60;
  H = 14;

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

procedure Key(AView: TEditorWindow; AKey: Word; AShift: TShiftState = []);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  AView.HandleInput(K, AShift, Ch);
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

function GridHas(const AGrid: TTerminalGrid; const AText: string): Boolean;
var
  Y: Integer;
begin
  for Y := 0 to High(AGrid) do
    if Pos(AText, RowText(AGrid, Y)) > 0 then
      Exit(True);
  Result := False;
end;

function OpenMarkdown(const ADir, AName, AText: string): TEditorWindow;
var
  Path: string;
begin
  Path := TPath.Combine(ADir, AName);
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), True);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

function CursorOf(AView: TEditorWindow): string;
var
  Top, Row, Col: Integer;
begin
  AView.GetViewPos(Top, Row, Col);
  Result := Format('%d/%d:%d', [Top, Row, Col]);
end;

procedure TTestMarkdownCursor.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-mdcursor-' + TPath.GetGUIDFileName(False));
  ForceDirectories(FDir);
end;

procedure TTestMarkdownCursor.TearDown;
begin
  FreeAndNil(FView);
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

// Position of the cursor as line and column.
procedure Where(AView: TEditorWindow; out ARow, ACol: Integer);
var
  Top: Integer;
begin
  AView.GetViewPos(Top, ARow, ACol);
end;

procedure TTestMarkdownCursor.TestDownWalksRowsOfAWrappedTableRow;
var
  V: TEditorWindow;
  Grid: TTerminalGrid;
  Row, Col, PrevCol, I: Integer;
  Rows: array[0..2] of Integer;
begin
  V := OpenMarkdown(FDir, 't.md',
    'intro' + sLineBreak + sLineBreak +
    '| A | B |' + sLineBreak + '|---|---|' + sLineBreak +
    '| one<br>two<br>three | x |' + sLineBreak + sLineBreak + 'tail' + sLineBreak);
  FView := V;
  Grid := Paint(V);
  // The three lines of the cell are three screen rows, not one.
  for I := 0 to High(Grid) do
  begin
    if Pos('one', RowText(Grid, I)) > 0 then Rows[0] := I;
    if Pos('two', RowText(Grid, I)) > 0 then Rows[1] := I;
    if Pos('three', RowText(Grid, I)) > 0 then Rows[2] := I;
  end;
  Assert.AreEqual(Rows[0] + 1, Rows[1], 'two is under one');
  Assert.AreEqual(Rows[1] + 1, Rows[2], 'three is under two');

  for I := 1 to 4 do
    Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(4, Row, 'the table row after intro, blank, header, separator');
  PrevCol := Col;
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(4, Row, 'second screen row of the same table row');
  Assert.IsTrue(Col > PrevCol, 'the column moved on into the second row');
  PrevCol := Col;
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(4, Row, 'third screen row');
  Assert.IsTrue(Col > PrevCol, 'and into the third');
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(5, Row, 'then the line after the table');
end;

procedure TTestMarkdownCursor.TestDownWalksRowsOfAWideTableRow;
var
  V: TEditorWindow;
  Cell, Text: string;
  I, Row, Col, PrevCol, InRow: Integer;
begin
  Cell := '';
  for I := 1 to 40 do
    Cell := Cell + 'word ';
  Text := '| A | B |' + sLineBreak + '|---|---|' + sLineBreak +
    '| ' + Cell + '| x |' + sLineBreak + sLineBreak + 'tail' + sLineBreak;
  V := OpenMarkdown(FDir, 'w.md', Text);
  FView := V;
  Paint(V);
  Key(V, vkDown);
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(2, Row, 'the wide table row');
  InRow := 1;
  PrevCol := Col;
  for I := 1 to 20 do
  begin
    Key(V, vkDown);
    Where(V, Row, Col);
    if Row <> 2 then
      Break;
    Inc(InRow);
    Assert.IsTrue(Col > PrevCol, 'the column keeps moving down the wrapped cell');
    PrevCol := Col;
  end;
  Assert.AreEqual(3, Row, 'the cursor gets past the table row');
  Assert.IsTrue(InRow >= 3, 'through every screen row of it, not stopped at the source length');
end;

procedure TTestMarkdownCursor.TestDownKeepsCursorVisibleAcrossAPicture;
var
  V: TEditorWindow;
  Grid: TTerminalGrid;
  Row, Col, I: Integer;
begin
  // Not a real picture: an unreadable file is a block of fixed height.
  TFile.WriteAllText(TPath.Combine(FDir, 'pic.png'), 'not a picture');
  V := OpenMarkdown(FDir, 'p.md',
    'line 1' + sLineBreak + 'line 2' + sLineBreak + 'line 3' + sLineBreak +
    'line 4' + sLineBreak + '![[pic.png]]' + sLineBreak +
    'after one' + sLineBreak + 'after two' + sLineBreak + 'after three' + sLineBreak);
  FView := V;
  Paint(V);
  for I := 1 to 4 do
    Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(4, Row, 'on the picture');
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(5, Row, 'one step later, the line after the picture');
  Grid := Paint(V);
  Assert.IsTrue(GridHas(Grid, 'after one'), 'the line after the picture is in view');
  Key(V, vkDown);
  Key(V, vkDown);
  Where(V, Row, Col);
  Assert.AreEqual(7, Row, 'the last line');
  Grid := Paint(V);
  Assert.IsTrue(GridHas(Grid, 'after three'), 'and in view');
  Key(V, vkUp);
  Key(V, vkUp);
  Key(V, vkUp);
  Key(V, vkUp);
  Where(V, Row, Col);
  Assert.AreEqual(3, Row, 'walking back up passes the picture one step too');
  Grid := Paint(V);
  Assert.IsTrue(GridHas(Grid, 'line 4'), 'with the line above it in view');
end;

procedure DoubleClickAt(AView: TEditorWindow; AX, AY: Integer);
begin
  AView.HandleMouseDown(AX, AY, []);
  AView.HandleMouseUp;
  AView.HandleMouseDown(AX, AY, []);
  AView.HandleMouseUp;
end;

// The cell of the first character of AWord on screen: its column and row.
function FindOnScreen(const AGrid: TTerminalGrid; const AWord: string;
  out AX, AY: Integer): Boolean;
var
  Y, P: Integer;
begin
  for Y := 0 to High(AGrid) do
  begin
    P := Pos(AWord, RowText(AGrid, Y));
    if P > 0 then
    begin
      AX := P - 1;
      AY := Y;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TTestMarkdownCursor.TestDoubleClickSelectsWordOnWrappedLine;
var
  V: TEditorWindow;
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  // Marks (** and `) are hidden in the view, so the displayed line is shorter
  // than the source line; the word sits on the second screen row.
  V := OpenMarkdown(FDir, 'd.md',
    '**Bold** and `code` then a long paragraph with several words so that ' +
    'the line wraps around the window width and the target word sits here' +
    sLineBreak);
  FView := V;
  Grid := Paint(V);
  Assert.IsTrue(FindOnScreen(Grid, 'target', X, Y), 'the word is drawn');
  Assert.IsTrue(Y > 1, 'on a wrapped row, below the first');
  DoubleClickAt(V, X + 2, Y);
  Assert.IsTrue(V.HasSelection, 'something is selected');
  Assert.AreEqual('target', V.SelectionText, 'the word under the pointer');
end;

procedure TTestMarkdownCursor.TestSelectedTextIsTheDisplayedText;
var
  V: TEditorWindow;
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  V := OpenMarkdown(FDir, 'e.md', 'see **bold** and `code` here' + sLineBreak);
  FView := V;
  Grid := Paint(V);
  Assert.IsTrue(FindOnScreen(Grid, 'code', X, Y), 'the word is drawn without its marks');
  DoubleClickAt(V, X + 1, Y);
  Assert.AreEqual('code', V.SelectionText, 'a word after hidden marks');
  // Three quick clicks select the whole line: its displayed text (the bold
  // marks are hidden, the code marks stay).
  V.HandleMouseDown(X + 1, Y, []);
  V.HandleMouseUp;
  Assert.AreEqual('see bold and `code` here' + #10, V.SelectionText,
    'the whole displayed line: the bold marks are gone, the line break is included');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkdownCursor);

end.
