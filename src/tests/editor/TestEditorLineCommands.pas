unit TestEditorLineCommands;

{ The editor's whole-line commands, run through their shortcuts. Sort, remove
  repeated lines and shift act on the selected lines or the whole file, and
  one Ctrl+Z undoes each of them. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorLineCommands = class
  public
    [Test] procedure TestSortWholeFileAndUndo;
    [Test] procedure TestSortDescendingAndUnique;
    [Test] procedure TestShiftMovesTheCursorLine;
    [Test] procedure TestSelectionLimitsTheCommand;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uTerminalTypes, uVfsTypes, uThemeRegistry, uEditorWindow;

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

procedure Send(AView: TEditorWindow; AKey: Word; AShift: TShiftState);
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

// The painted rows that show one of the file's words, in screen order.
function Words(AView: TEditorWindow): string;
var
  Grid: TTerminalGrid;
  I: Integer;
  Text, Word: string;
begin
  Grid := Paint(AView);
  Result := '';
  for I := 0 to High(Grid) do
  begin
    Text := RowText(Grid, I);
    for Word in ['Apple', 'apple', 'banana', 'pear', 'zed'] do
      if Pos(Word, Text) > 0 then
        Result := Result + Word + ' ';
  end;
  Result := Trim(Result);
end;

function OpenText(const AText: string; out ADir: string): TEditorWindow;
var
  Path: string;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-linecmd-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), False);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure TTestEditorLineCommands.TestSortWholeFileAndUndo;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('pear' + sLineBreak + 'Apple' + sLineBreak + 'banana' + sLineBreak +
    'apple' + sLineBreak, Dir);
  try
    Send(View, Ord('S'), [ssCtrl, ssAlt]);
    Assert.AreEqual('Apple apple banana pear', Words(View), 'ascending, case ignored');
    Send(View, Ord('Z'), [ssCtrl]);
    Assert.AreEqual('pear Apple banana apple', Words(View), 'one Ctrl+Z restores the order');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorLineCommands.TestSortDescendingAndUnique;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('pear' + sLineBreak + 'banana' + sLineBreak + 'pear' + sLineBreak +
    'banana' + sLineBreak, Dir);
  try
    Send(View, Ord('U'), [ssCtrl, ssAlt]);
    Assert.AreEqual('pear banana', Words(View), 'repeated lines removed, first copies kept');
    Send(View, Ord('S'), [ssCtrl, ssAlt, ssShift]);
    Assert.AreEqual('pear banana', Words(View), 'already descending');
    Send(View, Ord('S'), [ssCtrl, ssAlt]);
    Assert.AreEqual('banana pear', Words(View), 'ascending after that');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorLineCommands.TestShiftMovesTheCursorLine;
var
  Dir: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  I, Plain, Shifted: Integer;
begin
  View := OpenText('pear' + sLineBreak + 'banana' + sLineBreak, Dir);
  try
    Grid := Paint(View);
    Plain := -1;
    for I := 0 to High(Grid) do
      if Pos('pear', RowText(Grid, I)) > 0 then
        Plain := Pos('pear', RowText(Grid, I));
    Send(View, vkRight, [ssAlt]);
    Grid := Paint(View);
    Shifted := -1;
    for I := 0 to High(Grid) do
      if Pos('pear', RowText(Grid, I)) > 0 then
        Shifted := Pos('pear', RowText(Grid, I));
    Assert.AreEqual(Plain + 4, Shifted, 'Alt+Right indents the cursor line by four columns');
    Send(View, vkLeft, [ssAlt]);
    Grid := Paint(View);
    for I := 0 to High(Grid) do
      if Pos('pear', RowText(Grid, I)) > 0 then
        Shifted := Pos('pear', RowText(Grid, I));
    Assert.AreEqual(Plain, Shifted, 'Alt+Left takes it back');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorLineCommands.TestSelectionLimitsTheCommand;
var
  Dir: string;
  View: TEditorWindow;
begin
  View := OpenText('zed' + sLineBreak + 'pear' + sLineBreak + 'banana' + sLineBreak +
    'Apple' + sLineBreak, Dir);
  try
    Paint(View); // the view needs a size before the cursor keys scroll it
    // Shift+Down twice selects lines 1 and 2 (the cursor ends on line 3, col 0).
    Send(View, vkDown, []);
    Send(View, vkDown, [ssShift]);
    Send(View, vkDown, [ssShift]);
    Send(View, Ord('S'), [ssCtrl, ssAlt]);
    Assert.AreEqual('zed banana pear Apple', Words(View),
      'only the selected lines are sorted; the others stay where they were');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorLineCommands);

end.
