unit TestPanelSelect;

{ Smoke checks: file masks (*.* / * / extensionless) and Shift+nav invert ranges. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelSelect = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestMasks;
    [Test] procedure TestSelectByMaskSkipsFolders;
    [Test] procedure TestSelectFoldersAndStem;
    [Test] procedure TestShiftNavRanges;
    [Test] procedure TestSelectionKeys;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uFileFind,
  uFindSession,
  uDualPanelTypes;

procedure TestMasks;
var
  NoDot, WithDot: string;
begin
  NoDot := 'a068ce4bb047c9b425217bd04303dfd9-{87A94AB0-E370-4cde-98D3-ACC110C5967D}';
  WithDot := '3z03p3ja.vgu';
  Assert.IsTrue(NameMatchesAnyMask(NoDot, SplitMasks('*.*')), '*.* matches extensionless');
  Assert.IsTrue(NameMatchesAnyMask(NoDot, SplitMasks('*')), '* matches extensionless');
  Assert.IsTrue(NameMatchesAnyMask(WithDot, SplitMasks('*.*')), '*.* matches dotted name');
  Assert.IsTrue(NameMatchesAnyMask('readme.txt', SplitMasks('*.txt')), '*.txt matches');
  Assert.IsTrue(not NameMatchesAnyMask('readme.md', SplitMasks('*.txt')), '*.txt skips .md');
  Assert.IsTrue(NameMatchesAnyMask('a.b.c', SplitMasks('*.*')), '*.* matches multi-dot');
end;

procedure TestSelectByMaskSkipsFolders;
var
  Tab: TTab;
  Rows: TPanelRows;
begin
  Tab := MakeTab(1, 't', 'file:///D:/Temp');
  SetLength(Rows, 3);
  Rows[0] := MakePanelRow('..', True, -1, '', '', 'file:///D:/', True);
  Rows[1] := MakePanelRow('3z03p3ja.vgu/', True, -1, '<DIR>', '',
    'file:///D:/Temp/3z03p3ja.vgu', False);
  Rows[2] := MakePanelRow('hash-guid', False, 10, '10', '',
    'file:///D:/Temp/hash-guid', False);
  TabSelectByMask(Tab, Rows, '*.*');
  Assert.IsTrue(not TabIsSelected(Tab, Rows[1].URI), 'folder not selected by *.*');
  Assert.IsTrue(TabIsSelected(Tab, Rows[2].URI), 'extensionless file selected by *.*');
end;

procedure TestSelectFoldersAndStem;
var
  Tab: TTab;
  Rows: TPanelRows;
begin
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
  Assert.IsTrue(not TabIsSelected(Tab, Rows[0].URI), 'parent still skipped');
  Assert.IsTrue(TabIsSelected(Tab, Rows[1].URI), 'folder selected when include-folders');
  Assert.IsTrue(TabIsSelected(Tab, Rows[2].URI), 'file selected with include-folders');
  TabClearSelection(Tab);
  TabSelectByNameStem(Tab, Rows, FileNameStem('readme.txt'), False, False);
  Assert.IsTrue(not TabIsSelected(Tab, Rows[1].URI), 'folder skipped by stem without flag');
  Assert.IsTrue(TabIsSelected(Tab, Rows[2].URI), 'readme.txt selected by stem');
  Assert.IsTrue(TabIsSelected(Tab, Rows[3].URI), 'readme.md selected by stem');
  Assert.IsTrue(FileNameStem('.gitignore') = '.gitignore', 'dotfile stem is the name');
  Assert.IsTrue(FileNameStem('a.b.c') = 'a.b', 'multi-dot stem drops last ext');
  Assert.IsTrue(not TabHasSelectedDirectories(Tab, Rows), 'files-only selection');
  TabSelectByMask(Tab, Rows, '*', True);
  Assert.IsTrue(TabHasSelectedDirectories(Tab, Rows), 'has selected directory');
  TabClearSelection(Tab);
  TabToggleSelected(Tab, 'file:///D:/Temp/docs/');
  Assert.IsTrue(TabIsSelected(Tab, Rows[1].URI), 'dir URI matches with trailing slash');
  Assert.IsTrue(TabHasSelectedDirectories(Tab, Rows), 'selected dir URI form mismatch');
  Rows[1].IsDirectory := False;
  Rows[1].SizeText := '<DIR>';
  Assert.IsTrue(PanelRowIsDirectory(Rows[1]), '<DIR> size text is a directory');
  Rows[1].SizeText := '';
  Rows[1].Text := 'docs/';
  Assert.IsTrue(PanelRowIsDirectory(Rows[1]), 'trailing slash text is a directory');
end;

procedure TestShiftNavRanges;
var
  Lo, Hi: Integer;
begin
  Assert.IsTrue(ShiftNavInvertRange(5, 6, 1, False, Lo, Hi) and (Lo = 5) and (Hi = 5),
    'Up/Down step inverts leaving only');
  Assert.IsTrue(ShiftNavInvertRange(5, 25, 20, True, Lo, Hi) and (Lo = 5) and (Hi = 24),
    'Brief Right excludes landing (25)');
  Assert.IsTrue(ShiftNavInvertRange(25, 5, -20, True, Lo, Hi) and (Lo = 6) and (Hi = 25),
    'Brief Left excludes landing (5)');
  Assert.IsTrue(ShiftNavInvertRange(5, 5, 20, True, Lo, Hi) and (Lo = 5) and (Hi = 5),
    'Brief at edge inverts current');
  Assert.IsTrue(ShiftNavInvertRange(2, 10, 8, False, Lo, Hi) and (Lo = 2) and (Hi = 10),
    'PgDn inclusive span');
  Assert.IsTrue(ShiftNavInvertRange(10, 2, -8, False, Lo, Hi) and (Lo = 2) and (Hi = 10),
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
  for I := Low(Uris) to High(Uris) do
    for J := Low(Uris) to High(Uris) do
      Assert.IsTrue(SameVfsUri(Uris[I], Uris[J]) = (VfsUriKey(Uris[I]) = VfsUriKey(Uris[J])),
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
    Assert.IsTrue(SelectionKeysHas(Keys, Rows[I].URI) = TabIsSelected(Slow, Rows[I].URI),
      'range toggle matches per-row toggle: row ' + IntToStr(I));
  Assert.IsTrue(not SelectionKeysHas(Keys, Rows[2].URI), 'f2 (other spelling) unselected');
  Assert.IsTrue(SelectionKeysHas(Keys, Rows[1].URI) and SelectionKeysHas(Keys, Rows[3].URI),
    'f1, f3 selected');
  Assert.IsTrue(Length(Tab.SelectedURIs) = 2, 'no stray entries');
end;

{ TTestPanelSelect }

procedure TTestPanelSelect.SetupFixture;
begin
end;

procedure TTestPanelSelect.TestMasks;
begin
  TestPanelSelect.TestMasks;
end;

procedure TTestPanelSelect.TestSelectByMaskSkipsFolders;
begin
  TestPanelSelect.TestSelectByMaskSkipsFolders;
end;

procedure TTestPanelSelect.TestSelectFoldersAndStem;
begin
  TestPanelSelect.TestSelectFoldersAndStem;
end;

procedure TTestPanelSelect.TestShiftNavRanges;
begin
  TestPanelSelect.TestShiftNavRanges;
end;

procedure TTestPanelSelect.TestSelectionKeys;
begin
  TestPanelSelect.TestSelectionKeys;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelSelect);

end.
