unit TestEditorTyping;

{ Editing in the F4 editor: End, a character, Backspace (delivered as FMX
  does - the key, then the #8 character) leave the text as it was and the
  drawn caret right after the last character; Backspace at the start of a
  line joins it to the previous one with the caret at the join. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorTyping = class
  public
    [Test] procedure TestEndTypeBackspace;
    [Test] procedure TestBackspaceJoinsLines;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uNDNTheme, uEditorWindow;

const
  W = 60;
  H = 12;

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

// Column of the insert caret on ARow, -1 when none.
function CaretCol(const AGrid: TTerminalGrid; ARow: Integer): Integer;
var
  X: Integer;
begin
  for X := 0 to High(AGrid[ARow]) do
    if ccaInsertCaret in AGrid[ARow][X].Attributes then
      Exit(X);
  Result := -1;
end;

procedure TTestEditorTyping.TestEndTypeBackspace;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Row, TextStart, Caret: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-typing-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Path := TPath.Combine(Dir, 'a.txt');
  TFile.WriteAllText(Path, 'hello' + sLineBreak + 'world' + sLineBreak, TEncoding.UTF8);
  View := TEditorWindow.Create(TNDNTheme.Create, 1);
  try
    View.Open(PathToFileUri(Path), False);
    Pump;
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := -1;
    for Caret := 0 to High(Grid) do
      if Pos('hello', RowText(Grid, Caret)) > 0 then
      begin
        Row := Caret;
        Break;
      end;
    Assert.IsTrue(Row >= 0, 'first line drawn');
    TextStart := Pos('hello', RowText(Grid, Row)) - 1;

    Send(View, vkEnd, #0);
    Grid := Paint(View);
    Assert.AreEqual(TextStart + 5, CaretCol(Grid, Row), 'End: caret after "hello"');

    Send(View, 0, 'x');
    Grid := Paint(View);
    Assert.IsTrue(Pos('hellox', RowText(Grid, Row)) > 0, 'typed at the end');
    Assert.AreEqual(TextStart + 6, CaretCol(Grid, Row), 'caret after the typed character');

    Send(View, vkBack, #0);
    Send(View, 0, #8);
    Grid := Paint(View);
    Assert.IsTrue(Pos('hello ', RowText(Grid, Row) + ' ') > 0, 'Backspace removed it');
    Assert.IsFalse(Pos('hellox', RowText(Grid, Row)) > 0, 'the character is gone');
    Assert.AreEqual(TextStart + 5, CaretCol(Grid, Row), 'Backspace: caret back after "hello"');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorTyping.TestBackspaceJoinsLines;
var
  Dir, Path: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Row, TextStart, I: Integer;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-typing-' + TPath.GetGUIDFileName(False));
  ForceDirectories(Dir);
  Path := TPath.Combine(Dir, 'b.txt');
  TFile.WriteAllText(Path, 'hello world' + sLineBreak + 'x' + sLineBreak + 'end' + sLineBreak,
    TEncoding.UTF8);
  View := TEditorWindow.Create(TNDNTheme.Create, 1);
  try
    View.Open(PathToFileUri(Path), False);
    Pump;
    Assert.IsTrue(View.DocReady, 'document loaded');
    Grid := Paint(View);
    Row := -1;
    for I := 0 to High(Grid) do
      if Pos('hello world', RowText(Grid, I)) > 0 then
      begin
        Row := I;
        Break;
      end;
    Assert.IsTrue(Row >= 0, 'first line drawn');
    TextStart := Pos('hello world', RowText(Grid, Row)) - 1;

    // Start of the short second line, then Backspace.
    Send(View, vkDown, #0);
    Send(View, vkHome, #0);
    Send(View, vkBack, #0);
    Send(View, 0, #8);
    Grid := Paint(View);
    Assert.AreEqual(TextStart + Length('hello world'), CaretCol(Grid, Row),
      'caret at the join, on the first line');
    Assert.IsTrue(Pos('end', RowText(Grid, Row + 1)) > 0, 'the third line moved up');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorTyping);

end.
