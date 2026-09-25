program TestEditorLayout;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uEditorLayout in '..\Core\uEditorLayout.pas',
  uEditorHexView in '..\Core\uEditorHexView.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function Lens(const A: TArray<Integer>): TEditorLineLenFn;
begin
  Result := function(AIndex: Integer): Integer
    begin
      Result := A[AIndex];
    end;
end;

procedure TestModeAndEdit;
begin
  Writeln('Mode / CanEdit / dirty name / word char');
  Expect(EditorModeTitle(True, True, True) = 'Hex', 'hex wins over markdown');
  Expect(EditorModeTitle(False, True, True) = 'Markdown', 'markdown over viewer');
  Expect(EditorModeTitle(False, False, True) = 'Viewer', 'viewer');
  Expect(EditorModeTitle(False, False, False) = 'Editor', 'editor');
  Expect(EditorCanEdit(False, False, False, False, True, False, False, False),
    'plain ready editor can edit');
  Expect(not EditorCanEdit(True, False, False, False, True, False, False, False),
    'viewer cannot edit');
  Expect(not EditorCanEdit(False, True, False, False, True, False, False, False),
    'hex cannot text-edit');
  Expect(EditorCanHexEdit(False, True, False, False, False),
    'hex editor can edit');
  Expect(not EditorCanHexEdit(True, True, False, False, False),
    'hex viewer cannot edit');
  Expect(not EditorCanEdit(False, False, False, True, True, False, False, False),
    'binary cannot edit');
  Expect(EditorDirtyName('a.txt', True) = '* a.txt', 'dirty prefix');
  Expect(EditorDirtyName('a.txt', False) = 'a.txt', 'clean name');
  Expect(EditorIsWordChar('A') and EditorIsWordChar('9') and EditorIsWordChar('_'),
    'ascii word chars');
  Expect(not EditorIsWordChar(' '), 'space is not a word char');
  Expect(EditorIsWordChar(WideChar($410)), 'non-ascii letter is a word char');
end;

procedure TestWrap;
var
  LineIdx, Off: Integer;
  L: TArray<Integer>;
begin
  Writeln('Word wrap');
  Expect(WrappedSegCount(0, 10) = 1, 'empty line is one row');
  Expect(WrappedSegCount(10, 10) = 1, 'exact width is one row');
  Expect(WrappedSegCount(11, 10) = 2, 'width+1 wraps');
  Expect(WrappedSegCount(25, 10) = 3, '25/10 = 3 segs');
  Expect(WrappedSegCount(5, 0) = 0, 'zero width');

  L := TArray<Integer>.Create(0, 25, 5);
  Expect(CountWrappedRows(3, 10, Lens(L)) = 1 + 3 + 1, 'total wrapped rows');
  Expect(CountWrappedRows(0, 10, Lens(L)) = 0, 'no lines');
  Expect(MapWrappedDisplayToLine(3, 0, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 0) and (Off = 0), 'row 0 -> line 0');
  Expect(MapWrappedDisplayToLine(3, 1, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 1) and (Off = 0), 'row 1 -> line 1 start');
  Expect(MapWrappedDisplayToLine(3, 3, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 1) and (Off = 20), 'row 3 -> line 1 offset 20');
  Expect(MapWrappedDisplayToLine(3, 4, 10, Lens(L), LineIdx, Off) and
    (LineIdx = 2), 'row 4 -> last line');
  Expect(not MapWrappedDisplayToLine(3, 9, 10, Lens(L), LineIdx, Off),
    'past end is a miss');
  Expect(MapWrappedLineToDisplay(3, 1, 15, 10, Lens(L)) = 1 + 1,
    'line 1 col 15 -> display row 2');
  Expect(MapWrappedLineToDisplay(3, 0, 0, 10, Lens(L)) = 0, 'start of file');
end;

procedure TestStatus;
var
  PosText, LinesText: string;
begin
  Writeln('Status fragments');
  EditorPosAndLinesText(True, False, False, 2, 4, 16, 0, 10, '', PosText, LinesText);
  Expect(PosText = '3:5', 'text pos is 1-based');
  Expect(LinesText = '10 lines', 'line count');
  EditorPosAndLinesText(True, False, True, 1, 2, 16, 100, 0, '', PosText, LinesText);
  Expect(PosText = Format('%.8x', [1 * 16 + 2]), 'hex offset');
  Expect(LinesText = '100 bytes', 'byte count');
  EditorPosAndLinesText(False, True, False, 0, 0, 16, 0, 0, '', PosText, LinesText);
  Expect(PosText = 'loading...', 'loading');
  EditorPosAndLinesText(False, False, False, 0, 0, 16, 0, 0, 'boom', PosText, LinesText);
  Expect((PosText = 'error') and (LinesText = 'boom'), 'error line');
  Expect(EditorStatusFlag(True, True, True, True, True, 'x') = 'Hex', 'hex flag wins');
  Expect(EditorStatusFlag(False, True, True, False, False, '') = 'View [Wrap]', 'wrap view');
  Expect(EditorStatusFlag(False, True, False, False, False, '') = 'View', 'view');
  Expect(EditorStatusFlag(False, False, False, True, False, '') = 'RO', 'readonly');
  Expect(EditorStatusFlag(False, False, False, False, True, '') = 'Saving...', 'saving');
  Expect(EditorStatusFlag(False, False, False, False, False, 'Saved') = 'Saved', 'doc status');
end;

procedure TestCaretDrawCol;
var
  Col: Integer;
begin
  Writeln('Insert caret in wrapped chunk');
  Expect(EditorCaretDrawCol(0, 1, 10, 10, 80, True, Col) and (Col = 0),
    'caret at start of line');
  Expect(EditorCaretDrawCol(3, 1, 10, 10, 80, True, Col) and (Col = 3),
    'caret between chars');
  Expect(EditorCaretDrawCol(10, 1, 10, 10, 80, True, Col) and (Col = 10),
    'caret after last char');
  Expect(EditorCaretDrawCol(12, 11, 20, 25, 80, False, Col) and (Col = 2),
    'caret on second wrap row');
  Expect(not EditorCaretDrawCol(3, 11, 20, 25, 80, False, Col),
    'caret not on later wrap row');
  Expect(EditorCaretDrawCol(0, 1, 0, 0, 80, True, Col) and (Col = 0),
    'empty line caret');
  Expect(EditorCaretDrawCol(7, 1, 5, 5, 80, True, Col) and (Col = 5),
    'source col past stripped heading sits at display end');
end;

procedure TestHexCells;
var
  Row, Col: Integer;
begin
  Writeln('Hex dump cells / SelectAll end');
  Expect(TEditorHexFormatter.HexColStart = 10, 'hex digits start after offset');
  Expect(TEditorHexFormatter.AsciiColStart(16) = 10 + (16 * 3 - 1) + 2,
    'ascii start for 16-byte row');
  Expect(TEditorHexFormatter.AsciiColStart(8) = 10 + (8 * 3 - 1) + 2,
    'ascii start for 8-byte row');
  Expect(TEditorHexFormatter.HexGlyphCol(0) = 10, 'first byte hex glyphs at col 10');
  Expect(TEditorHexFormatter.HexGlyphCol(1) = 13, 'second byte skips the separator');

  TEditorHexFormatter.SelectAllEnd(0, 80, Row, Col);
  Expect((Row = 0) and (Col = 0), 'empty dump cursor at 0,0');
  TEditorHexFormatter.SelectAllEnd(1, 80, Row, Col);
  Expect((Row = 0) and (Col = 0), 'one byte is row 0 col 0');
  TEditorHexFormatter.SelectAllEnd(16, 80, Row, Col);
  Expect((Row = 0) and (Col = 15), 'full first row last byte');
  TEditorHexFormatter.SelectAllEnd(17, 80, Row, Col);
  Expect((Row = 1) and (Col = 0), '17th byte starts row 1');
  Expect(TEditorHexFormatter.HexDigitValue('A') = 10, 'hex A');
  Expect(TEditorHexFormatter.HexDigitValue('g') = -1, 'not a hex digit');
  Expect(TEditorHexFormatter.ApplyNibble($00, $B, True) = $B0, 'high nibble');
  Expect(TEditorHexFormatter.ApplyNibble($B0, $C, False) = $BC, 'low nibble');
  Expect(TEditorHexFormatter.AbsoluteByteIndex(1, 2, 16) = 18, 'byte index');
end;

begin
  try
    TestModeAndEdit;
    TestWrap;
    TestStatus;
    TestCaretDrawCol;
    TestHexCells;
    Writeln('All EditorLayout tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
