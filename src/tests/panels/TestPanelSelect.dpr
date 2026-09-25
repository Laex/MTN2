program TestPanelSelect;

{$APPTYPE CONSOLE}

{ Smoke checks: file masks (*.* / * / extensionless) and Shift+nav invert ranges. }

uses
  System.SysUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uFileFind in '..\..\Core\uFileFind.pas',
  uFindSession in '..\..\Core\uFindSession.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas';

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

procedure TestMasks;
var
  NoDot, WithDot: string;
begin
  Writeln('NameMatchesAnyMask');
  NoDot := 'a068ce4bb047c9b425217bd04303dfd9-{87A94AB0-E370-4cde-98D3-ACC110C5967D}';
  WithDot := '3z03p3ja.vgu';
  Expect(NameMatchesAnyMask(NoDot, SplitMasks('*.*')), '*.* matches extensionless');
  Expect(NameMatchesAnyMask(NoDot, SplitMasks('*')), '* matches extensionless');
  Expect(NameMatchesAnyMask(WithDot, SplitMasks('*.*')), '*.* matches dotted name');
  Expect(NameMatchesAnyMask('readme.txt', SplitMasks('*.txt')), '*.txt matches');
  Expect(not NameMatchesAnyMask('readme.md', SplitMasks('*.txt')), '*.txt skips .md');
  Expect(NameMatchesAnyMask('a.b.c', SplitMasks('*.*')), '*.* matches multi-dot');
end;

procedure TestSelectByMaskSkipsFolders;
var
  Tab: TTab;
  Rows: TPanelRows;
begin
  Writeln('TabSelectByMask skips directories');
  Tab := MakeTab(1, 't', 'file:///D:/Temp');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///D:/', True);
  Rows[1] := MakePanelRow('3z03p3ja.vgu/', True, -1, '<DIR>', '',
    'file:///D:/Temp/3z03p3ja.vgu', False);
  Rows[2] := MakePanelRow('hash-guid', False, 10, '10', '',
    'file:///D:/Temp/hash-guid', False);
  TabSelectByMask(Tab, Rows, '*.*');
  Expect(not TabIsSelected(Tab, Rows[1].URI), 'folder not selected by *.*');
  Expect(TabIsSelected(Tab, Rows[2].URI), 'extensionless file selected by *.*');
end;

procedure TestSelectFoldersAndStem;
var
  Tab: TTab;
  Rows: TPanelRows;
begin
  Writeln('Select folders / name stem');
  Tab := MakeTab(1, 't', 'file:///D:/Temp');
  SetLength(Rows, 4);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///D:/', True);
  Rows[1] := MakePanelRow('docs/', True, -1, '<DIR>', '',
    'file:///D:/Temp/docs', False);
  Rows[2] := MakePanelRow('readme.txt', False, 10, '10', '',
    'file:///D:/Temp/readme.txt', False);
  Rows[3] := MakePanelRow('readme.md', False, 4, '4', '',
    'file:///D:/Temp/readme.md', False);
  TabSelectByMask(Tab, Rows, '*', True);
  Expect(not TabIsSelected(Tab, Rows[0].URI), 'parent still skipped');
  Expect(TabIsSelected(Tab, Rows[1].URI), 'folder selected when include-folders');
  Expect(TabIsSelected(Tab, Rows[2].URI), 'file selected with include-folders');
  TabClearSelection(Tab);
  TabSelectByNameStem(Tab, Rows, FileNameStem('readme.txt'), False, False);
  Expect(not TabIsSelected(Tab, Rows[1].URI), 'folder skipped by stem without flag');
  Expect(TabIsSelected(Tab, Rows[2].URI), 'readme.txt selected by stem');
  Expect(TabIsSelected(Tab, Rows[3].URI), 'readme.md selected by stem');
  Expect(FileNameStem('.gitignore') = '.gitignore', 'dotfile stem is the name');
  Expect(FileNameStem('a.b.c') = 'a.b', 'multi-dot stem drops last ext');
  Expect(not TabHasSelectedDirectories(Tab, Rows), 'files-only selection');
  TabSelectByMask(Tab, Rows, '*', True);
  Expect(TabHasSelectedDirectories(Tab, Rows), 'has selected directory');
  TabClearSelection(Tab);
  TabToggleSelected(Tab, 'file:///D:/Temp/docs/');
  Expect(TabIsSelected(Tab, Rows[1].URI), 'dir URI matches with trailing slash');
  Expect(TabHasSelectedDirectories(Tab, Rows), 'selected dir URI form mismatch');
  Rows[1].IsDirectory := False;
  Rows[1].SizeText := '<DIR>';
  Expect(PanelRowIsDirectory(Rows[1]), '<DIR> size text is a directory');
  Rows[1].SizeText := '';
  Rows[1].Text := 'docs/';
  Expect(PanelRowIsDirectory(Rows[1]), 'trailing slash text is a directory');
end;

procedure TestShiftNavRanges;
var
  Lo, Hi: Integer;
begin
  Writeln('ShiftNavInvertRange');
  Expect(ShiftNavInvertRange(5, 6, 1, False, Lo, Hi) and (Lo = 5) and (Hi = 5),
    'Up/Down step inverts leaving only');
  Expect(ShiftNavInvertRange(5, 25, 20, True, Lo, Hi) and (Lo = 5) and (Hi = 24),
    'Brief Right excludes landing (25)');
  Expect(ShiftNavInvertRange(25, 5, -20, True, Lo, Hi) and (Lo = 6) and (Hi = 25),
    'Brief Left excludes landing (5)');
  Expect(ShiftNavInvertRange(5, 5, 20, True, Lo, Hi) and (Lo = 5) and (Hi = 5),
    'Brief at edge inverts current');
  Expect(ShiftNavInvertRange(2, 10, 8, False, Lo, Hi) and (Lo = 2) and (Hi = 10),
    'PgDn inclusive span');
  Expect(ShiftNavInvertRange(10, 2, -8, False, Lo, Hi) and (Lo = 2) and (Hi = 10),
    'PgUp inclusive span');
end;

procedure TestSelectionKeys;
const
  Uris: array[0..9] of string = (
    'file:///D:/Temp/docs',
    'file:///D:/Temp/docs/',
    'file:///d:/temp/DOCS',
    'file:///D:/Temp/My%20File.txt',
    'file:///D:/Temp/My File.txt',
    'file:///D:/Temp/a.zip!/inner/x.txt',
    'file:///D:/Temp/A.ZIP!/Inner/X.txt',
    'file:///D:/Temp/a.zip!/inner',
    'sftp://u@host:22/home/a',
    'sftp://u@HOST:22/home/a');
var
  I, J: Integer;
  Tab, Slow: TTab;
  Rows: TPanelRows;
  Keys: TArray<string>;
begin
  Writeln('VfsUriKey / selection keys');
  for I := Low(Uris) to High(Uris) do
    for J := Low(Uris) to High(Uris) do
      Expect(SameVfsUri(Uris[I], Uris[J]) = (VfsUriKey(Uris[I]) = VfsUriKey(Uris[J])),
        Format('key agrees with SameVfsUri: %d~%d', [I, J]));

  Tab := MakeTab(1, 't', 'file:///D:/Temp');
  SetLength(Rows, 6);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///D:/', True);
  for I := 1 to High(Rows) do
    Rows[I] := MakePanelRow('f' + IntToStr(I), False, I, '', '',
      'file:///D:/Temp/f' + IntToStr(I), False);
  // Pre-select f2 in a different URI spelling; the range toggle must see it.
  TabToggleSelected(Tab, 'file:///d:/temp/F2');
  Slow := Tab;
  TabToggleSelectedRange(Tab, Rows, 0, 3);
  for I := 0 to 3 do
    if not Rows[I].IsParent then
      TabToggleSelected(Slow, Rows[I].URI);
  Keys := TabSelectionKeys(Tab);
  for I := 0 to High(Rows) do
    Expect(SelectionKeysHas(Keys, Rows[I].URI) = TabIsSelected(Slow, Rows[I].URI),
      'range toggle matches per-row toggle: row ' + IntToStr(I));
  Expect(not SelectionKeysHas(Keys, Rows[2].URI), 'f2 (other spelling) unselected');
  Expect(SelectionKeysHas(Keys, Rows[1].URI) and SelectionKeysHas(Keys, Rows[3].URI),
    'f1, f3 selected');
  Expect(Length(Tab.SelectedURIs) = 2, 'no stray entries');
end;

begin
  Failed := 0;
  try
    TestMasks;
    TestSelectByMaskSkipsFolders;
    TestSelectFoldersAndStem;
    TestShiftNavRanges;
    TestSelectionKeys;
  except
    on E: Exception do
    begin
      Inc(Failed);
      Writeln('EXCEPTION ', E.Message);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks OK');
    Halt(0);
  end;
  Writeln('Failed: ', Failed);
  Halt(1);
end.
