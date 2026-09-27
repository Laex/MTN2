unit TestEditorLayout;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorLayout = class
  public
    [Test] procedure TestModeAndEdit;
    [Test] procedure TestWrap;
    [Test] procedure TestStatus;
    [Test] procedure TestCaretDrawCol;
    [Test] procedure TestHexCells;
  end;

implementation

uses
  System.SysUtils,
  uEditorLayout,
  uEditorHexView;

function Lens(const A: TArray<Integer>): TEditorLineLenFn;
begin
  Result := function(AIndex: Integer): Integer
    begin
      Result := A[AIndex];
    end;
end;

procedure TestModeAndEdit;
begin
  Assert.IsTrue(EditorModeTitle(True, True, True) = 'Hex', 'hex wins over markdown');
  Assert.IsTrue(EditorModeTitle(False, True, True) = 'Markdown', 'markdown over viewer');
  Assert.IsTrue(EditorModeTitle(False, False, True) = 'Viewer', 'viewer');
  Assert.IsTrue(EditorModeTitle(False, False, False) = 'Editor', 'editor');
  Assert.IsTrue(EditorCanEdit(False, False, False, False, True, False, False, False),
    'plain ready editor can edit');
  Assert.IsTrue(not EditorCanEdit(True, False, False, False, True, False, False, False),
    'viewer cannot edit');
  Assert.IsTrue(not EditorCanEdit(False, True, False, False, True, False, False, False),
    'hex cannot text-edit');
  Assert.IsTrue(EditorCanHexEdit(False, True, False, False, False),
    'hex editor can edit');
  Assert.IsTrue(not EditorCanHexEdit(True, True, False, False, False),
    'hex viewer cannot edit');
  Assert.IsTrue(not EditorCanEdit(False, False, False, True, True, False, False, False),
    'binary cannot edit');
  Assert.IsTrue(EditorDirtyName('a.txt', True) = '* a.txt', 'dirty prefix');
  Assert.IsTrue(EditorDirtyName('a.txt', False) = 'a.txt', 'clean name');
  Assert.IsTrue(EditorIsWordChar('A') and EditorIsWordChar('9') and EditorIsWordChar('_'),
    'ascii word chars');
  Assert.IsTrue(not EditorIsWordChar(' '), 'space is not a word char');
  Assert.IsTrue(EditorIsWordChar(WideChar($410)), 'non-ascii letter is a word char');
end;

procedure TestWrap;
var
  LineIdx, Off: Integer;
  L: TArray<Integer>;
begin
  Assert.IsTrue(WrappedSegCount(0, 10) = 1, 'empty line is one row');
  Assert.IsTrue(WrappedSegCount(10, 10) = 1, 'exact width is one row');
  Assert.IsTrue(WrappedSegCount(11, 10) = 2, 'width+1 wraps');
  Assert.IsTrue(WrappedSegCount(25, 10) = 3, '25/10 = 3 segs');
  Assert.IsTrue(WrappedSegCount(5, 0) = 0, 'zero width');

  L := TArray<Integer>.Create(0, 25, 5);
  Assert.IsTrue(CountWrappedRows(3, 10, Lens(L)) = 1 + 3 + 1, 'total wrapped rows');
  Assert.IsTrue(CountWrappedRows(0, 10, Lens(L)) = 0, 'no lines');
  Assert.IsTrue(MapWrappedDisplayToLine(3, 0, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 0) and (Off = 0), 'row 0 -> line 0');
  Assert.IsTrue(MapWrappedDisplayToLine(3, 1, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 1) and (Off = 0), 'row 1 -> line 1 start');
  Assert.IsTrue(MapWrappedDisplayToLine(3, 3, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 1) and (Off = 20), 'row 3 -> line 1 offset 20');
  Assert.IsTrue(MapWrappedDisplayToLine(3, 4, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 2), 'row 4 -> last line');
  Assert.IsTrue(not MapWrappedDisplayToLine(3, 9, 10, Lens(L), LineIdx, Off),
    'past end is a miss');
  Assert.IsTrue(MapWrappedLineToDisplay(3, 1, 15, 10, Lens(L)) = 1 + 1,
    'line 1 col 15 -> display row 2');
  Assert.IsTrue(MapWrappedLineToDisplay(3, 0, 0, 10, Lens(L)) = 0, 'start of file');
end;

procedure TestStatus;
var
  PosText, LinesText: string;
begin
  EditorPosAndLinesText(True, False, False, 2, 4, 16, 0, 10, '', PosText, LinesText);
  Assert.IsTrue(PosText = '3:5', 'text pos is 1-based');
  Assert.IsTrue(LinesText = '10 lines', 'line count');
  EditorPosAndLinesText(True, False, True, 1, 2, 16, 100, 0, '', PosText, LinesText);
  Assert.IsTrue(PosText = Format('%.8x', [1 * 16 + 2]), 'hex offset');
  Assert.IsTrue(LinesText = '100 bytes', 'byte count');
  EditorPosAndLinesText(False, True, False, 0, 0, 16, 0, 0, '', PosText, LinesText);
  Assert.IsTrue(PosText = 'loading...', 'loading');
  EditorPosAndLinesText(False, False, False, 0, 0, 16, 0, 0, 'boom', PosText, LinesText);
  Assert.IsTrue((PosText = 'error') and (LinesText = 'boom'), 'error line');
  Assert.IsTrue(EditorStatusFlag(True, True, True, True, True, 'x') = 'Hex', 'hex flag wins');
  Assert.IsTrue(EditorStatusFlag(False, True, True, False, False, '') = 'View [Wrap]', 'wrap view');
  Assert.IsTrue(EditorStatusFlag(False, True, False, False, False, '') = 'View', 'view');
  Assert.IsTrue(EditorStatusFlag(False, False, False, True, False, '') = 'RO', 'readonly');
  Assert.IsTrue(EditorStatusFlag(False, False, False, False, True, '') = 'Saving...', 'saving');
  Assert.IsTrue(EditorStatusFlag(False, False, False, False, False, 'Saved') = 'Saved', 'doc status');
end;

procedure TestCaretDrawCol;
var
  Col: Integer;
begin
  Assert.IsTrue(EditorCaretDrawCol(0, 1, 10, 10, 80, True, Col) and (Col = 0),
    'caret at start of line');
  Assert.IsTrue(EditorCaretDrawCol(3, 1, 10, 10, 80, True, Col) and (Col = 3),
    'caret between chars');
  Assert.IsTrue(EditorCaretDrawCol(10, 1, 10, 10, 80, True, Col) and (Col = 10),
    'caret after last char');
  Assert.IsTrue(EditorCaretDrawCol(12, 11, 20, 25, 80, False, Col) and (Col = 2),
    'caret on second wrap row');
  Assert.IsTrue(not EditorCaretDrawCol(3, 11, 20, 25, 80, False, Col),
    'caret not on later wrap row');
  Assert.IsTrue(EditorCaretDrawCol(0, 1, 0, 0, 80, True, Col) and (Col = 0),
    'empty line caret');
  Assert.IsTrue(EditorCaretDrawCol(7, 1, 5, 5, 80, True, Col) and (Col = 5),
    'source col past stripped heading sits at display end');
end;

procedure TestHexCells;
var
  Row, Col: Integer;
begin
  Assert.IsTrue(TEditorHexFormatter.HexColStart = 10, 'hex digits start after offset');
  Assert.IsTrue(TEditorHexFormatter.AsciiColStart(16) = 10 + (16 * 3 - 1) + 2,
    'ascii start for 16-byte row');
  Assert.IsTrue(TEditorHexFormatter.AsciiColStart(8) = 10 + (8 * 3 - 1) + 2,
    'ascii start for 8-byte row');
  Assert.IsTrue(TEditorHexFormatter.HexGlyphCol(0) = 10, 'first byte hex glyphs at col 10');
  Assert.IsTrue(TEditorHexFormatter.HexGlyphCol(1) = 13, 'second byte skips the separator');

  TEditorHexFormatter.SelectAllEnd(0, 80, Row, Col);
  Assert.IsTrue((Row = 0) and (Col = 0), 'empty dump cursor at 0,0');
  TEditorHexFormatter.SelectAllEnd(1, 80, Row, Col);
  Assert.IsTrue((Row = 0) and (Col = 0), 'one byte is row 0 col 0');
  TEditorHexFormatter.SelectAllEnd(16, 80, Row, Col);
  Assert.IsTrue((Row = 0) and (Col = 15), 'full first row last byte');
  TEditorHexFormatter.SelectAllEnd(17, 80, Row, Col);
  Assert.IsTrue((Row = 1) and (Col = 0), '17th byte starts row 1');
  Assert.IsTrue(TEditorHexFormatter.HexDigitValue('A') = 10, 'hex A');
  Assert.IsTrue(TEditorHexFormatter.HexDigitValue('g') = -1, 'not a hex digit');
  Assert.IsTrue(TEditorHexFormatter.ApplyNibble($00, $B, True) = $B0, 'high nibble');
  Assert.IsTrue(TEditorHexFormatter.ApplyNibble($B0, $C, False) = $BC, 'low nibble');
  Assert.IsTrue(TEditorHexFormatter.AbsoluteByteIndex(1, 2, 16) = 18, 'byte index');
end;

{ TTestEditorLayout }

procedure TTestEditorLayout.TestModeAndEdit;
begin
  TestEditorLayout.TestModeAndEdit;
end;

procedure TTestEditorLayout.TestWrap;
begin
  TestEditorLayout.TestWrap;
end;

procedure TTestEditorLayout.TestStatus;
begin
  TestEditorLayout.TestStatus;
end;

procedure TTestEditorLayout.TestCaretDrawCol;
begin
  TestEditorLayout.TestCaretDrawCol;
end;

procedure TTestEditorLayout.TestHexCells;
begin
  TestEditorLayout.TestHexCells;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorLayout);

end.
