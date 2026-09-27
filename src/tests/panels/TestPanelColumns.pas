unit TestPanelColumns;

{ Smoke checks for Brief multi-column geometry / hit-test (panel UX 14.1). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelColumns = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestEllipsizeKeepingExt;
    [Test] procedure TestBriefColumns;
    [Test] procedure TestBriefCellAndPage;
    [Test] procedure TestBriefHitAndAlign;
    [Test] procedure TestIconColumn;
    [Test] procedure TestIconVisibility;
    [Test] procedure TestNumericNameSort;
    [Test] procedure TestEnsureCursorVisible;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uDualPanelTypes,
  uPanelColumns;

procedure TestEllipsizeKeepingExt;
var
  Row: TPanelRow;
  Name, LongRu: string;
begin
  Assert.IsTrue(EllipsizeKeepingExt('short.txt', 40) = 'short.txt', 'short kept');
  Assert.IsTrue(EllipsizeKeepingExt('VeryLongFileNameWithoutExt', 12) =
    'VeryLon...xt', 'no-ext mid-ellipsis');
  Assert.IsTrue(EllipsizeKeepingExt('abcdefghijklmnopqrstuvwxyz123', 28) =
    'abcdefghijklmnopqrstuv...123', 'ascii mid-ellipsis');

  LongRu := 'Темы ВКР - Технологии разработки.docx';
  Name := EllipsizeKeepingExt(LongRu, 28);
  Assert.IsTrue(Length(Name) = 28, 'exact width');
  Assert.IsTrue(Copy(Name, Length(Name) - 4, 5) = '.docx', 'keeps .docx');
  Assert.IsTrue(Pos('...', Name) > 0, 'uses three-dot ellipsis');
  Assert.IsTrue(Pos('~', Name) = 0, 'no tilde');
  Assert.IsTrue(Copy(Name, 1, 4) = Copy(LongRu, 1, 4), 'keeps name prefix');

  Row := MakePanelRow('VeryLongDocumentName.docx', False, 10, '10', '',
    'file:///VeryLongDocumentName.docx');
  Name := FormatPanelRowName(Row, 18);
  Assert.IsTrue(Length(Name) = 18, 'row name padded/fit width');
  Assert.IsTrue(Pos('.docx', TrimRight(Name)) > 0, 'row name keeps extension');
  Assert.IsTrue(Pos('...', Name) > 0, 'row name ellipsis');

  // Ext column mode: stem only, end-ellipsis (do not treat dots in stem as ext).
  Row := MakePanelRow('my.dotted.longname.txt', False, 10, '10', '',
    'file:///my.dotted.longname.txt');
  Row.Extension := '.txt';
  Name := FormatPanelRowName(Row, 12, True);
  Assert.IsTrue(Length(Name) = 12, 'stripped name width');
  Assert.IsTrue(Copy(Name, Length(Name) - 2, 3) = '...', 'stripped uses end ellipsis');
  Assert.IsTrue(Pos('.txt', Name) = 0, 'stripped name has no ext');
end;

procedure TestBriefColumns;
begin
  Assert.IsTrue(BriefColumnCount(27) = 1, 'width 27 -> 1 col');
  Assert.IsTrue(BriefColumnCount(28) = 1, 'width 28 -> 1 col (min cell)');
  Assert.IsTrue(BriefColumnCount(55) = 1, 'width 55 -> 1 col');
  Assert.IsTrue(BriefColumnCount(56) = 2, 'width 56 -> 2 cols');
  Assert.IsTrue(BriefColumnCount(84) = 3, 'width 84 -> 3 cols');
  Assert.IsTrue(PanelListColumnCount(pcmBrief, 56) = 2, 'Brief@56 -> 2');
  Assert.IsTrue(PanelListColumnCount(pcmFull, 200) = 1, 'Full always 1 col');
end;

procedure TestBriefCellAndPage;
var
  CellW: Integer;
begin
  CellW := BriefCellWidth(56, 2);
  Assert.IsTrue(CellW = 28, 'cell width 56/2 = 28');
  Assert.IsTrue(BriefPageSize(10, 2) = 20, 'page 10x2 = 20');
  Assert.IsTrue(BriefIndexAt(0, 0, 0, 10) = 0, 'index (0,0,0)');
  Assert.IsTrue(BriefIndexAt(0, 1, 0, 10) = 10, 'index col1 row0');
  Assert.IsTrue(BriefIndexAt(0, 1, 3, 10) = 13, 'index col1 row3');
  Assert.IsTrue(BriefIndexAt(20, 0, 1, 10) = 21, 'index after scroll');
end;

procedure TestBriefHitAndAlign;
var
  CellW: Integer;
begin
  CellW := BriefCellWidth(56, 2);
  Assert.IsTrue(BriefHitIndex(0, 0, 0, 10, CellW, 2, 25) = 0, 'hit left top');
  Assert.IsTrue(BriefHitIndex(0, CellW, 0, 10, CellW, 2, 25) = 10, 'hit right top');
  Assert.IsTrue(BriefHitIndex(0, CellW + 5, 3, 10, CellW, 2, 25) = 13, 'hit right row3');
  Assert.IsTrue(BriefHitIndex(0, 0, 10, 10, CellW, 2, 25) = -1, 'hit below view');
  Assert.IsTrue(BriefHitIndex(0, CellW * 2, 0, 10, CellW, 2, 25) = -1, 'hit past last col');
  Assert.IsTrue(BriefHitIndex(0, 0, 0, 10, CellW, 2, 5) = 0, 'hit in range');
  Assert.IsTrue(BriefHitIndex(0, CellW, 0, 10, CellW, 2, 5) = -1, 'empty cell past count');
  Assert.IsTrue(AlignBriefScroll(0, 10) = 0, 'align 0');
  Assert.IsTrue(AlignBriefScroll(7, 10) = 0, 'align 7 -> 0');
  Assert.IsTrue(AlignBriefScroll(10, 10) = 10, 'align 10');
  Assert.IsTrue(AlignBriefScroll(23, 10) = 20, 'align 23 -> 20');
end;

procedure TestIconColumn;
var
  Row: TPanelRow;
  NameW, MetaW: Integer;
  SortCol: TPanelSortColumn;
  Desc: Boolean;
begin
  Assert.IsTrue(PanelIconColumnWidth = 2, 'icon width 2');
  Assert.IsTrue(PanelIconReserve = 3, 'icon reserve 2+gap');
  Row := MakePanelRow('..', True, -1, '<DIR>', '', 'file:///', True);
  Assert.IsTrue(FormatPanelRowIcon(Row) = '^', 'parent icon');
  Row := MakePanelRow('Docs/', True, -1, '<DIR>', '', 'file:///Docs');
  Assert.IsTrue(FormatPanelRowIcon(Row) = #$25A0, 'dir icon');
  Row := MakePanelRow('a.zip', False, 10, '10', '', 'file:///a.zip');
  Assert.IsTrue(FormatPanelRowIcon(Row) = '#', 'archive icon');
  Row := MakePanelRow('run.exe', False, 10, '10', '', 'file:///run.exe');
  Assert.IsTrue(FormatPanelRowIcon(Row) = '*', 'exe icon');
  Row := MakePanelRow('pic.png', False, 10, '10', '', 'file:///pic.png');
  Assert.IsTrue(FormatPanelRowIcon(Row) = '~', 'media icon');
  Row := MakePanelRow('note.txt', False, 10, '10', '', 'file:///note.txt');
  Assert.IsTrue(FormatPanelRowIcon(Row) = #$00B7, 'doc icon');
  PanelColumnWidths(pcmFull, 80, NameW, MetaW);
  Assert.IsTrue(NameW + MetaW + 1 + PanelIconReserve = 80, 'full width accounts icon');
  Assert.IsTrue(HitPanelSortColumn(pcmFull, 80, 0, SortCol) and (SortCol = pscName),
    'icon click sorts by name');
  Assert.IsTrue(HitPanelSortColumn(pcmFull, 80, PanelIconReserve, SortCol) and
    (SortCol = pscName), 'name click sorts by name');

  Writeln('Header / menu sort cycle');
  SortCol := pscNone;
  Desc := True;
  CycleHeaderSort(SortCol, Desc, pscSize);
  Assert.IsTrue((SortCol = pscSize) and (not Desc), 'header new col is ascending');
  CycleHeaderSort(SortCol, Desc, pscSize);
  Assert.IsTrue((SortCol = pscSize) and Desc, 'header second click is descending');
  CycleHeaderSort(SortCol, Desc, pscSize);
  Assert.IsTrue((SortCol = pscNone) and (not Desc), 'header third click clears');
  SortCol := pscName;
  Desc := False;
  CycleMenuSort(SortCol, Desc, pscSize);
  Assert.IsTrue((SortCol = pscSize) and Desc, 'menu size defaults descending');
  CycleMenuSort(SortCol, Desc, pscSize);
  Assert.IsTrue((SortCol = pscSize) and (not Desc), 'menu same col toggles');
  CycleMenuSort(SortCol, Desc, pscNone);
  Assert.IsTrue((SortCol = pscNone) and (not Desc), 'menu none clears');

  Writeln('FAR sort-mode letter');
  Assert.IsTrue(PanelSortModeLetter(pscNone, False) = 'u', 'unsorted u');
  Assert.IsTrue(PanelSortModeLetter(pscName, False) = 'n', 'name n');
  Assert.IsTrue(PanelSortModeLetter(pscExt, False) = 'x', 'extension x');
  Assert.IsTrue(PanelSortModeLetter(pscModified, False) = 'w', 'write time w');
  Assert.IsTrue(PanelSortModeLetter(pscSize, False) = 's', 'size s');
  Assert.IsTrue(PanelSortModeLetter(pscCreated, False) = 'c', 'created c');
  Assert.IsTrue(PanelSortModeLetter(pscAccessed, False) = 'a', 'accessed a');
  Assert.IsTrue(PanelSortModeLetter(pscAttr, False) = 't', 'attr t');
  Assert.IsTrue(PanelSortModeLetter(pscType, False) = 'y', 'type y');
  Assert.IsTrue(PanelSortModeLetter(pscName, True) = 'N', 'desc name N');
  Assert.IsTrue(PanelSortModeLetter(pscCreated, True) = 'C', 'desc created C');
  Assert.IsTrue(PanelSortModeLetter(pscNone, True) = 'U', 'desc unsorted U');
end;

procedure TestIconVisibility;
var
  NameW, MetaW: Integer;
begin
  GShowPanelIcons := True;
  Assert.IsTrue(PanelIconColumnWidth = 2, 'icons on: width 2');
  Assert.IsTrue(PanelIconReserve = 3, 'icons on: reserve 2+gap');
  GShowPanelIcons := False;
  try
    Assert.IsTrue(PanelIconColumnWidth = 0, 'icons off: width 0');
    Assert.IsTrue(PanelIconReserve = 0, 'icons off: reserve 0');
    PanelColumnWidths(pcmFull, 80, NameW, MetaW);
    Assert.IsTrue(NameW + MetaW + 1 = 80, 'full width without icon column');
  finally
    GShowPanelIcons := True;
  end;
  Assert.IsTrue(PanelIconReserve = 3, 'icons restored');
end;

procedure TestNumericNameSort;
var
  Rows: TPanelRows;
begin
  SetLength(Rows, 5);
  Rows[0] := MakePanelRow('file10.txt', False, 1, '1', '', 'file:///file10.txt');
  Rows[1] := MakePanelRow('dir10/', True, -1, '<DIR>', '', 'file:///dir10');
  Rows[2] := MakePanelRow('file2.txt', False, 1, '1', '', 'file:///file2.txt');
  Rows[3] := MakePanelRow('file1.txt', False, 1, '1', '', 'file:///file1.txt');
  Rows[4] := MakePanelRow('dir2/', True, -1, '<DIR>', '', 'file:///dir2');
  SortPanelRows(Rows, pscName, False);
  Assert.IsTrue(Rows[0].Text = 'dir2/', 'dir2 before dir10 (numeric)');
  Assert.IsTrue(Rows[1].Text = 'dir10/', 'dirs still before files');
  Assert.IsTrue(Rows[2].Text = 'file1.txt', 'file1 before file2');
  Assert.IsTrue(Rows[3].Text = 'file2.txt', 'file2 before file10 (numeric)');
  Assert.IsTrue(Rows[4].Text = 'file10.txt', 'file10 last');
end;

procedure TestEnsureCursorVisible;
var
  Tab: TTab;
begin
  Tab := Default(TTab);
  Tab.CursorIndex := 9;
  Tab.ScrollOffset := 4;
  EnsurePanelCursorVisible(Tab, 0, 5, 1);
  Assert.IsTrue((Tab.CursorIndex = 0) and (Tab.ScrollOffset = 0), 'empty list resets');

  Tab.CursorIndex := 7;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Assert.IsTrue((Tab.CursorIndex = 7) and (Tab.ScrollOffset = 3), 'single col scrolls to cursor');

  Tab.CursorIndex := 1;
  Tab.ScrollOffset := 5;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Assert.IsTrue(Tab.ScrollOffset = 1, 'single col scrolls up to cursor');

  Tab.CursorIndex := 99;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Assert.IsTrue(Tab.CursorIndex = 9, 'cursor clamped to last row');

  Tab.CursorIndex := 25;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 40, 10, 2);
  Assert.IsTrue(Tab.ScrollOffset = 10, 'brief col-major snaps scroll to viewH');
end;

{ TTestPanelColumns }

procedure TTestPanelColumns.SetupFixture;
begin
end;

procedure TTestPanelColumns.TestEllipsizeKeepingExt;
begin
  TestPanelColumns.TestEllipsizeKeepingExt;
end;

procedure TTestPanelColumns.TestBriefColumns;
begin
  TestPanelColumns.TestBriefColumns;
end;

procedure TTestPanelColumns.TestBriefCellAndPage;
begin
  TestPanelColumns.TestBriefCellAndPage;
end;

procedure TTestPanelColumns.TestBriefHitAndAlign;
begin
  TestPanelColumns.TestBriefHitAndAlign;
end;

procedure TTestPanelColumns.TestIconColumn;
begin
  TestPanelColumns.TestIconColumn;
end;

procedure TTestPanelColumns.TestIconVisibility;
begin
  TestPanelColumns.TestIconVisibility;
end;

procedure TTestPanelColumns.TestNumericNameSort;
begin
  TestPanelColumns.TestNumericNameSort;
end;

procedure TTestPanelColumns.TestEnsureCursorVisible;
begin
  TestPanelColumns.TestEnsureCursorVisible;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelColumns);

end.
