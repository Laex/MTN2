program TestPanelColumns;

{$APPTYPE CONSOLE}

{ Smoke checks for Brief multi-column geometry / hit-test (panel UX 14.1). }

uses
  System.SysUtils,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uPanelColumns in '..\Core\uPanelColumns.pas';

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

procedure TestEllipsizeKeepingExt;
var
  Row: TPanelRow;
  Name, LongRu: string;
begin
  Writeln('EllipsizeKeepingExt / FormatPanelRowName');
  Expect(EllipsizeKeepingExt('short.txt', 40) = 'short.txt', 'short kept');
  Expect(EllipsizeKeepingExt('VeryLongFileNameWithoutExt', 12) =
    'VeryLon...xt', 'no-ext mid-ellipsis');
  Expect(EllipsizeKeepingExt('abcdefghijklmnopqrstuvwxyz123', 28) =
    'abcdefghijklmnopqrstuv...123', 'ascii mid-ellipsis');

  LongRu := 'Темы ВКР - Технологии разработки.docx';
  Name := EllipsizeKeepingExt(LongRu, 28);
  Expect(Length(Name) = 28, 'exact width');
  Expect(Copy(Name, Length(Name) - 4, 5) = '.docx', 'keeps .docx');
  Expect(Pos('...', Name) > 0, 'uses three-dot ellipsis');
  Expect(Pos('~', Name) = 0, 'no tilde');
  Expect(Copy(Name, 1, 4) = Copy(LongRu, 1, 4), 'keeps name prefix');

  Row := MakePanelRow('VeryLongDocumentName.docx', False, 10, '10', '',
    'file:///VeryLongDocumentName.docx');
  Name := FormatPanelRowName(Row, 18);
  Expect(Length(Name) = 18, 'row name padded/fit width');
  Expect(Pos('.docx', TrimRight(Name)) > 0, 'row name keeps extension');
  Expect(Pos('...', Name) > 0, 'row name ellipsis');

  // Ext column mode: stem only, end-ellipsis (do not treat dots in stem as ext).
  Row := MakePanelRow('my.dotted.longname.txt', False, 10, '10', '',
    'file:///my.dotted.longname.txt');
  Row.Extension := '.txt';
  Name := FormatPanelRowName(Row, 12, True);
  Expect(Length(Name) = 12, 'stripped name width');
  Expect(Copy(Name, Length(Name) - 2, 3) = '...', 'stripped uses end ellipsis');
  Expect(Pos('.txt', Name) = 0, 'stripped name has no ext');
end;

procedure TestBriefColumns;
begin
  Writeln('BriefColumnCount / PanelListColumnCount');
  Expect(BriefColumnCount(27) = 1, 'width 27 -> 1 col');
  Expect(BriefColumnCount(28) = 1, 'width 28 -> 1 col (min cell)');
  Expect(BriefColumnCount(55) = 1, 'width 55 -> 1 col');
  Expect(BriefColumnCount(56) = 2, 'width 56 -> 2 cols');
  Expect(BriefColumnCount(84) = 3, 'width 84 -> 3 cols');
  Expect(PanelListColumnCount(pcmBrief, 56) = 2, 'Brief@56 -> 2');
  Expect(PanelListColumnCount(pcmFull, 200) = 1, 'Full always 1 col');
end;

procedure TestBriefCellAndPage;
var
  CellW: Integer;
begin
  Writeln('BriefCellWidth / BriefPageSize / BriefIndexAt');
  CellW := BriefCellWidth(56, 2);
  Expect(CellW = 28, 'cell width 56/2 = 28');
  Expect(BriefPageSize(10, 2) = 20, 'page 10x2 = 20');
  Expect(BriefIndexAt(0, 0, 0, 10) = 0, 'index (0,0,0)');
  Expect(BriefIndexAt(0, 1, 0, 10) = 10, 'index col1 row0');
  Expect(BriefIndexAt(0, 1, 3, 10) = 13, 'index col1 row3');
  Expect(BriefIndexAt(20, 0, 1, 10) = 21, 'index after scroll');
end;

procedure TestBriefHitAndAlign;
var
  CellW: Integer;
begin
  Writeln('BriefHitIndex / AlignBriefScroll');
  CellW := BriefCellWidth(56, 2);
  Expect(BriefHitIndex(0, 0, 0, 10, CellW, 2, 25) = 0, 'hit left top');
  Expect(BriefHitIndex(0, CellW, 0, 10, CellW, 2, 25) = 10, 'hit right top');
  Expect(BriefHitIndex(0, CellW + 5, 3, 10, CellW, 2, 25) = 13, 'hit right row3');
  Expect(BriefHitIndex(0, 0, 10, 10, CellW, 2, 25) = -1, 'hit below view');
  Expect(BriefHitIndex(0, CellW * 2, 0, 10, CellW, 2, 25) = -1, 'hit past last col');
  Expect(BriefHitIndex(0, 0, 0, 10, CellW, 2, 5) = 0, 'hit in range');
  Expect(BriefHitIndex(0, CellW, 0, 10, CellW, 2, 5) = -1, 'empty cell past count');
  Expect(AlignBriefScroll(0, 10) = 0, 'align 0');
  Expect(AlignBriefScroll(7, 10) = 0, 'align 7 -> 0');
  Expect(AlignBriefScroll(10, 10) = 10, 'align 10');
  Expect(AlignBriefScroll(23, 10) = 20, 'align 23 -> 20');
end;

procedure TestIconColumn;
var
  Row: TPanelRow;
  NameW, MetaW: Integer;
  SortCol: TPanelSortColumn;
  Desc: Boolean;
begin
  Writeln('Icon column');
  Expect(PanelIconColumnWidth = 2, 'icon width 2');
  Expect(PanelIconReserve = 3, 'icon reserve 2+gap');
  Row := MakePanelRow('..', True, -1, '<DIR>', '', 'file:///', True);
  Expect(FormatPanelRowIcon(Row) = '^', 'parent icon');
  Row := MakePanelRow('Docs/', True, -1, '<DIR>', '', 'file:///Docs');
  Expect(FormatPanelRowIcon(Row) = #$25A0, 'dir icon');
  Row := MakePanelRow('a.zip', False, 10, '10', '', 'file:///a.zip');
  Expect(FormatPanelRowIcon(Row) = '#', 'archive icon');
  Row := MakePanelRow('run.exe', False, 10, '10', '', 'file:///run.exe');
  Expect(FormatPanelRowIcon(Row) = '*', 'exe icon');
  Row := MakePanelRow('pic.png', False, 10, '10', '', 'file:///pic.png');
  Expect(FormatPanelRowIcon(Row) = '~', 'media icon');
  Row := MakePanelRow('note.txt', False, 10, '10', '', 'file:///note.txt');
  Expect(FormatPanelRowIcon(Row) = #$00B7, 'doc icon');
  PanelColumnWidths(pcmFull, 80, NameW, MetaW);
  Expect(NameW + MetaW + 1 + PanelIconReserve = 80, 'full width accounts icon');
  Expect(HitPanelSortColumn(pcmFull, 80, 0, SortCol) and (SortCol = pscName),
    'icon click sorts by name');
  Expect(HitPanelSortColumn(pcmFull, 80, PanelIconReserve, SortCol) and
    (SortCol = pscName), 'name click sorts by name');

  Writeln('Header / menu sort cycle');
  SortCol := pscNone;
  Desc := True;
  CycleHeaderSort(SortCol, Desc, pscSize);
  Expect((SortCol = pscSize) and (not Desc), 'header new col is ascending');
  CycleHeaderSort(SortCol, Desc, pscSize);
  Expect((SortCol = pscSize) and Desc, 'header second click is descending');
  CycleHeaderSort(SortCol, Desc, pscSize);
  Expect((SortCol = pscNone) and (not Desc), 'header third click clears');
  SortCol := pscName;
  Desc := False;
  CycleMenuSort(SortCol, Desc, pscSize);
  Expect((SortCol = pscSize) and Desc, 'menu size defaults descending');
  CycleMenuSort(SortCol, Desc, pscSize);
  Expect((SortCol = pscSize) and (not Desc), 'menu same col toggles');
  CycleMenuSort(SortCol, Desc, pscNone);
  Expect((SortCol = pscNone) and (not Desc), 'menu none clears');

  Writeln('FAR sort-mode letter');
  Expect(PanelSortModeLetter(pscNone, False) = 'u', 'unsorted u');
  Expect(PanelSortModeLetter(pscName, False) = 'n', 'name n');
  Expect(PanelSortModeLetter(pscExt, False) = 'x', 'extension x');
  Expect(PanelSortModeLetter(pscModified, False) = 'w', 'write time w');
  Expect(PanelSortModeLetter(pscSize, False) = 's', 'size s');
  Expect(PanelSortModeLetter(pscCreated, False) = 'c', 'created c');
  Expect(PanelSortModeLetter(pscAccessed, False) = 'a', 'accessed a');
  Expect(PanelSortModeLetter(pscAttr, False) = 't', 'attr t');
  Expect(PanelSortModeLetter(pscType, False) = 'y', 'type y');
  Expect(PanelSortModeLetter(pscName, True) = 'N', 'desc name N');
  Expect(PanelSortModeLetter(pscCreated, True) = 'C', 'desc created C');
  Expect(PanelSortModeLetter(pscNone, True) = 'U', 'desc unsorted U');
end;

procedure TestIconVisibility;
var
  NameW, MetaW: Integer;
begin
  Writeln('Icon visibility toggle');
  GShowPanelIcons := True;
  Expect(PanelIconColumnWidth = 2, 'icons on: width 2');
  Expect(PanelIconReserve = 3, 'icons on: reserve 2+gap');
  GShowPanelIcons := False;
  try
    Expect(PanelIconColumnWidth = 0, 'icons off: width 0');
    Expect(PanelIconReserve = 0, 'icons off: reserve 0');
    PanelColumnWidths(pcmFull, 80, NameW, MetaW);
    Expect(NameW + MetaW + 1 = 80, 'full width without icon column');
  finally
    GShowPanelIcons := True;
  end;
  Expect(PanelIconReserve = 3, 'icons restored');
end;

procedure TestNumericNameSort;
var
  Rows: TPanelRows;
begin
  Writeln('Numeric name sort');
  SetLength(Rows, 5);
  Rows[0] := MakePanelRow('file10.txt', False, 1, '1', '', 'file:///file10.txt');
  Rows[1] := MakePanelRow('dir10/', True, -1, '<DIR>', '', 'file:///dir10');
  Rows[2] := MakePanelRow('file2.txt', False, 1, '1', '', 'file:///file2.txt');
  Rows[3] := MakePanelRow('file1.txt', False, 1, '1', '', 'file:///file1.txt');
  Rows[4] := MakePanelRow('dir2/', True, -1, '<DIR>', '', 'file:///dir2');
  SortPanelRows(Rows, pscName, False);
  Expect(Rows[0].Text = 'dir2/', 'dir2 before dir10 (numeric)');
  Expect(Rows[1].Text = 'dir10/', 'dirs still before files');
  Expect(Rows[2].Text = 'file1.txt', 'file1 before file2');
  Expect(Rows[3].Text = 'file2.txt', 'file2 before file10 (numeric)');
  Expect(Rows[4].Text = 'file10.txt', 'file10 last');
end;

procedure TestEnsureCursorVisible;
var
  Tab: TTab;
begin
  Writeln('EnsurePanelCursorVisible');
  Tab := Default(TTab);
  Tab.CursorIndex := 9;
  Tab.ScrollOffset := 4;
  EnsurePanelCursorVisible(Tab, 0, 5, 1);
  Expect((Tab.CursorIndex = 0) and (Tab.ScrollOffset = 0), 'empty list resets');

  Tab.CursorIndex := 7;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Expect((Tab.CursorIndex = 7) and (Tab.ScrollOffset = 3), 'single col scrolls to cursor');

  Tab.CursorIndex := 1;
  Tab.ScrollOffset := 5;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Expect(Tab.ScrollOffset = 1, 'single col scrolls up to cursor');

  Tab.CursorIndex := 99;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 10, 5, 1);
  Expect(Tab.CursorIndex = 9, 'cursor clamped to last row');

  Tab.CursorIndex := 25;
  Tab.ScrollOffset := 0;
  EnsurePanelCursorVisible(Tab, 40, 10, 2);
  Expect(Tab.ScrollOffset = 10, 'brief col-major snaps scroll to viewH');
end;

begin
  Failed := 0;
  try
    TestEllipsizeKeepingExt;
    TestBriefColumns;
    TestBriefCellAndPage;
    TestBriefHitAndAlign;
    TestIconColumn;
    TestIconVisibility;
    TestNumericNameSort;
    TestEnsureCursorVisible;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.Message);
      Halt(2);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln('Failed: ', Failed);
  Halt(1);
end.
