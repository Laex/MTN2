unit TestEditorPluginApi;

{ What a plugin sees and changes of the document in the editor / viewer
  (uPluginServices): its description, its text by kind, replacing it as one
  undo step, the host events of opening, saving and closing. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorPluginApi = class
  public
    [Test] procedure TestInfoDescribesTheDocument;
    [Test] procedure TestTextByKind;
    [Test] procedure TestReplaceSelectionLineAndDocument;
    [Test] procedure TestReplaceIsOneUndoStep;
    [Test] procedure TestViewerCannotBeChanged;
    [Test] procedure TestCursorCanBeMoved;
    [Test] procedure TestDocumentEvents;
    [Test] procedure TestSelectionAndLineByIndex;
    [Test] procedure TestChangesAreAnnouncedOncePerCommand;
    [Test] procedure TestHighlightColorsTheCells;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uVfsTypes, uThemeRegistry, uTerminalTypes, uEditorWindow, uPluginServices, uPluginHighlight;

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

function OpenText(const AText: string; AViewOnly: Boolean; out ADir: string): TEditorWindow;
var
  Path: string;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-api-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  TFile.WriteAllText(Path, AText, TEncoding.UTF8);
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Open(PathToFileUri(Path), AViewOnly);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure SendKey(AView: TEditorWindow; AKey: Word; AShift: TShiftState; AChar: Char = #0);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := AChar;
  AView.HandleInput(K, AShift, Ch);
end;

procedure TTestEditorPluginApi.TestInfoDescribesTheDocument;
var
  Dir, Json: string;
  View: TEditorWindow;
begin
  View := OpenText('one' + sLineBreak + 'two', False, Dir);
  try
    Json := View.PluginDocInfoJson;
    Assert.IsTrue(Pos('"canEdit":true', Json) > 0, 'editable: ' + Json);
    Assert.IsTrue(Pos('"viewOnly":false', Json) > 0, 'editor');
    Assert.IsTrue(Pos('"lines":2', Json) > 0, 'two lines');
    Assert.IsTrue(Pos('"dirty":false', Json) > 0, 'untouched');
    Assert.IsTrue(Pos('a.txt', Json) > 0, 'the file');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestTextByKind;
var
  Dir, Text: string;
  View: TEditorWindow;
begin
  View := OpenText('alpha' + sLineBreak + 'beta' + sLineBreak + 'gamma', False, Dir);
  try
    Assert.IsTrue(View.PluginDocGetText(1, Text) and (Text = 'alpha'#10'beta'#10'gamma'), 'whole document with LF: ' + Text);
    Assert.IsTrue(View.PluginDocGetText(2, Text) and (Text = 'alpha'), 'the cursor line');
    Assert.IsTrue(View.PluginDocGetText(0, Text) and (Text = ''), 'an empty selection is empty text, not a failure');
    SendKey(View, vkRight, [ssShift]);
    SendKey(View, vkRight, [ssShift]);
    Assert.IsTrue(View.PluginDocGetText(0, Text) and (Text = 'al'), 'the selection: ' + Text);
    Assert.IsFalse(View.PluginDocGetText(7, Text), 'an unknown kind');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestReplaceSelectionLineAndDocument;
var
  Dir, Text: string;
  View: TEditorWindow;
begin
  View := OpenText('alpha' + sLineBreak + 'beta', False, Dir);
  try
    SendKey(View, vkRight, [ssShift]);
    SendKey(View, vkRight, [ssShift]);
    Assert.IsTrue(View.PluginDocReplace(0, 'AL'), 'selection replaced');
    View.PluginDocGetText(1, Text);
    Assert.AreEqual('ALpha'#10'beta', Text);
    Assert.IsTrue(View.PluginDocReplace(0, '>'), 'no selection: inserted at the cursor');
    View.PluginDocGetText(1, Text);
    Assert.AreEqual('AL>pha'#10'beta', Text);
    Assert.IsTrue(View.PluginDocReplace(2, 'one'#13#10'two'), 'the cursor line, with a line break of its own');
    View.PluginDocGetText(1, Text);
    Assert.AreEqual('one'#10'two'#10'beta', Text);
    Assert.IsTrue(View.PluginDocReplace(1, 'x'#10'y'), 'the whole document');
    View.PluginDocGetText(1, Text);
    Assert.AreEqual('x'#10'y', Text);
    Assert.IsTrue(Pos('"dirty":true', View.PluginDocInfoJson) > 0, 'the document is marked as changed');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestReplaceIsOneUndoStep;
var
  Dir, Text: string;
  View: TEditorWindow;
begin
  View := OpenText('c'#13#10'a'#13#10'b', False, Dir);
  try
    Assert.IsTrue(View.PluginDocReplace(1, 'a'#10'b'#10'c'), 'sorted by a plugin');
    View.UndoEdit;
    View.PluginDocGetText(1, Text);
    Assert.AreEqual('c'#10'a'#10'b', Text, 'one undo restores the document');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestViewerCannotBeChanged;
var
  Dir, Text: string;
  View: TEditorWindow;
begin
  View := OpenText('read only', True, Dir);
  try
    Assert.IsTrue(View.PluginDocGetText(1, Text) and (Text = 'read only'), 'the viewer can be read');
    Assert.IsFalse(View.PluginDocReplace(1, 'changed'), 'but not changed');
    Assert.IsTrue(Pos('"canEdit":false', View.PluginDocInfoJson) > 0, 'info says so');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestCursorCanBeMoved;
var
  Dir, Json: string;
  View: TEditorWindow;
begin
  View := OpenText('abc' + sLineBreak + 'defgh', False, Dir);
  try
    Assert.IsTrue(View.PluginDocSetCursor(1, 3), 'moved');
    Json := View.PluginDocInfoJson;
    Assert.IsTrue((Pos('"row":1', Json) > 0) and (Pos('"col":3', Json) > 0), Json);
    Assert.IsTrue(View.PluginDocSetCursor(50, 50), 'a place past the end is clamped');
    Assert.IsTrue(Pos('"row":1', View.PluginDocInfoJson) > 0, 'clamped to the last line');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestSelectionAndLineByIndex;
var
  Dir, Text: string;
  View: TEditorWindow;
begin
  View := OpenText('alpha' + sLineBreak + 'beta' + sLineBreak + 'gamma', False, Dir);
  try
    Assert.IsTrue(View.PluginDocSetSelection(0, 2, 1, 2), 'selected');
    View.PluginDocGetText(0, Text);
    Assert.AreEqual('pha'#10'be', Text, 'across two lines');
    Assert.IsTrue(View.PluginDocLine(2, Text) and (Text = 'gamma'), 'a line by index');
    Assert.IsFalse(View.PluginDocLine(3, Text), 'past the end');
    Assert.IsFalse(View.PluginDocLine(-1, Text), 'before the start');
    Assert.IsTrue(View.PluginDocSetSelection(0, 99, 99, 99), 'positions are clamped');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestChangesAreAnnouncedOncePerCommand;
var
  Dir, Log: string;
  View: TEditorWindow;
begin
  Log := '';
  PluginSubscribe('t.changes', 'doc.changed',
    procedure(const ATopic, APayload: string)
    begin
      Log := Log + ATopic + ';';
    end);
  try
    View := OpenText('a' + sLineBreak + 'b' + sLineBreak + 'c', False, Dir);
    try
      Log := '';
      View.PluginDocReplace(1, 'x'#10'y'#10'z'#10'w');
      Pump(100);
      Assert.AreEqual('doc.changed;', Log, 'one event for the lines a command changed');
    finally
      View.Free;
      TDirectory.Delete(Dir, True);
    end;
  finally
    PluginEventsUnregister('t.changes');
  end;
end;

function RowString(const AGrid: TTerminalGrid; ARow, AFrom, ALen: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := AFrom to AFrom + ALen - 1 do
    Result := Result + AGrid[ARow][X].CharValue;
end;

procedure TTestEditorPluginApi.TestHighlightColorsTheCells;
var
  Dir: string;
  View: TEditorWindow;
  Grid: TTerminalGrid;
  Y, Row, X: Integer;
  Plain, Colored: TAlphaColor;
begin
  RegisterHighlighter('t.hl', '.txt',
    function(const ALine: string; out ASpans: THighlightSpans): Boolean
    begin
      // The word "key" in a line is a keyword.
      SetLength(ASpans, 0);
      if Pos('key', ALine) > 0 then
      begin
        SetLength(ASpans, 1);
        ASpans[0].Start := Pos('key', ALine) - 1;
        ASpans[0].Len := 3;
        ASpans[0].Kind := cHighlightKeyword;
      end;
      Result := Length(ASpans) > 0;
    end);
  View := OpenText('plain text' + sLineBreak + 'a key here', False, Dir);
  try
    SetLength(Grid, 14);
    for Y := 0 to High(Grid) do
      SetLength(Grid[Y], 60);
    View.PaintEmbedded(Grid, 0, 0, 60, 14, 0, 0);
    Row := -1;
    for Y := 0 to High(Grid) do
      if Pos('a key here', RowString(Grid, Y, 0, 60)) > 0 then
        Row := Y;
    Assert.IsTrue(Row >= 0, 'the line is drawn');
    X := Pos('key', RowString(Grid, Row, 0, 60)) - 1;
    Colored := Grid[Row][X].FgColor;
    Plain := Grid[Row][X - 2].FgColor;
    Assert.AreNotEqual(Plain, Colored, 'the keyword has its own color');
    Assert.AreEqual(Colored, Grid[Row][X + 2].FgColor, 'to its last letter');
    Assert.AreEqual(Plain, Grid[Row][X + 3].FgColor, 'and the text after it is plain again');
  finally
    UnregisterHighlighter('t.hl');
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPluginApi.TestDocumentEvents;
var
  Dir, Log: string;
  View: TEditorWindow;
begin
  Log := '';
  PluginSubscribe('t.events', '*',
    procedure(const ATopic, APayload: string)
    begin
      Log := Log + ATopic + ';';
    end);
  try
    View := OpenText('text', False, Dir);
    try
      Assert.AreEqual('doc.opened;', Log, 'opening is announced once');
      View.PluginDocReplace(1, 'changed');
      SendKey(View, vkF2, []);
      Pump;
      Assert.AreEqual('doc.opened;doc.changed;doc.saved;', Log,
        'the change and then the finished save are announced');
      View.BeginClose;
      Assert.AreEqual('doc.opened;doc.changed;doc.saved;doc.closed;', Log, 'closing is announced');
    finally
      View.Free;
      TDirectory.Delete(Dir, True);
    end;
  finally
    PluginEventsUnregister('t.events');
  end;
end;

end.
