unit TestPanelCompare;

{ Compare folders (Ctrl+Shift+C): which rows of the two panels get
  selected. Pure row logic -- no files are touched. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelCompare = class
  public
    [Test] procedure Run;
    [Test] procedure OptionsChooseWhatDiffers;
    [Test] procedure MarkedFilePairNeedsExactlyTwoFiles;
    [Test] procedure SummaryShowsSizeDateAndContentVerdicts;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  uDualPanelTypes,
  uPanelCompare;

function Row(const AName: string; ASize: Int64; const ATime: TDateTime;
  AIsDir: Boolean = False; const ASideTag: string = 'L'): TPanelRow;
begin
  Result := MakePanelRow(AName, AIsDir, ASize);
  Result.URI := 'file:///' + ASideTag + '/' + AName;
  Result.ModificationTime := ATime;
end;

function Parent: TPanelRow;
begin
  Result := MakePanelRow('..', True, -1, '', '', 'file:///', True);
end;

function Has(const AList: TArray<string>; const AURI: string): Boolean;
var
  S: string;
begin
  for S in AList do
    if S = AURI then
      Exit(True);
  Result := False;
end;

var
  T0, T1: TDateTime;
  Left, Right: TPanelRows;
  Res: TPanelCompareResult;

{ TTestPanelCompare }

procedure TTestPanelCompare.MarkedFilePairNeedsExactlyTwoFiles;
var
  Rows: TPanelRows;
  Tab: TTab;
  L, R: TPanelRow;
begin
  T0 := EncodeDateTime(2025, 1, 1, 12, 0, 0, 0);
  Rows := [Parent, Row('a.docx', 10, T0), Row('b.docx', 10, T0),
    Row('c.docx', 10, T0), Row('dir', 0, T0, True)];
  Tab := MakeTab(1, 't', 'file:///L/');
  Assert.IsFalse(PickMarkedFilePair(Rows, Tab, L, R), 'nothing marked');
  TabSetSelected(Tab, Rows[2].URI, True);
  Assert.IsFalse(PickMarkedFilePair(Rows, Tab, L, R), 'one marked file is not a pair');
  TabSetSelected(Tab, Rows[1].URI, True);
  Assert.IsTrue(PickMarkedFilePair(Rows, Tab, L, R), 'two marked files form a pair');
  Assert.AreEqual('a.docx', L.Text, 'pair keeps listing order (first)');
  Assert.AreEqual('b.docx', R.Text, 'pair keeps listing order (second)');
  TabSetSelected(Tab, Rows[3].URI, True);
  Assert.IsFalse(PickMarkedFilePair(Rows, Tab, L, R), 'three marked files are ambiguous');
  TabSetSelected(Tab, Rows[3].URI, False);
  TabSetSelected(Tab, Rows[4].URI, True);
  Assert.IsFalse(PickMarkedFilePair(Rows, Tab, L, R), 'a marked folder is not a file');
end;

procedure TTestPanelCompare.SummaryShowsSizeDateAndContentVerdicts;
var
  A, B: TPanelRow;
  Rows: TArray<TCompareSummaryRow>;
begin
  T0 := EncodeDateTime(2025, 1, 1, 12, 0, 0, 0);
  A := Row('x.docx', 48213, T0);
  B := Row('x (1).docx', 48213, IncSecond(T0, 1), False, 'R');
  Assert.AreEqual('48 213 B', FormatExactSize(48213), 'size is grouped by thousands');
  Rows := BuildCompareSummary(A, B, True, -1);
  Assert.IsTrue(Length(Rows) = 3, 'size, modified and content rows');
  Assert.IsTrue(Rows[0].Same and (Pos('48 213 B =  48 213 B', Rows[0].Text) > 0),
    'equal sizes are joined by =');
  Assert.IsTrue(Rows[1].Same, '1 s apart counts as the same time');
  Assert.IsTrue(Rows[2].Same and (Pos('identical', Rows[2].Text) > 0), 'equal content');

  B.Size := 5000;
  B.ModificationTime := IncHour(T0, 1);
  Rows := BuildCompareSummary(A, B, False, 7);
  Assert.IsFalse(Rows[0].Same, 'different sizes');
  Assert.IsTrue(Pos('<>', Rows[0].Text) > 0, 'different sizes are joined by <>');
  Assert.IsFalse(Rows[1].Same, 'different times');
  Assert.IsFalse(Rows[2].Same, 'different content');
  Assert.IsTrue(Pos('differs at byte offset 7', Rows[2].Text) > 0,
    'the offset is reported');
end;

procedure TTestPanelCompare.OptionsChooseWhatDiffers;
var
  L, R: TPanelRows;
  Opt: TPanelCompareOptions;
  Calls: Integer;
  Equal: TPanelContentEqualFn;
begin
  T0 := EncodeDateTime(2025, 1, 1, 12, 0, 0, 0);
  T1 := IncHour(T0, 1);
  L := [Row('newer.txt', 10, T1), Row('resized.txt', 10, T0), Row('same-size.txt', 10, T0)];
  R := [Row('newer.txt', 10, T0, False, 'R'), Row('resized.txt', 20, T0, False, 'R'),
    Row('same-size.txt', 10, T0, False, 'R')];
  Calls := 0;
  Equal :=
    function(const ALeft, ARight: TPanelRow): Boolean
    begin
      Inc(Calls);
      Result := False;
    end;

  Opt := TPanelCompareOptions.Default;
  Opt.ByTime := False;
  Res := ComparePanelRows(L, R, Opt, Equal);
  Assert.IsFalse(Has(Res.LeftUris, 'file:///L/newer.txt'), 'time ignored when off');
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/resized.txt') and
    Has(Res.RightUris, 'file:///R/resized.txt'), 'size still differs');
  Assert.AreEqual(0, Calls, 'content is not read when off');

  Opt := TPanelCompareOptions.Default;
  Opt.BySize := False;
  Res := ComparePanelRows(L, R, Opt, Equal);
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/newer.txt'), 'newer side marked');
  Assert.IsFalse(Has(Res.LeftUris, 'file:///L/resized.txt'), 'size ignored when off');

  Opt.ByContent := True;
  Res := ComparePanelRows(L, R, Opt, Equal);
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/resized.txt'),
    'different sizes differ in content too');
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/same-size.txt') and
    Has(Res.RightUris, 'file:///R/same-size.txt'), 'content check marks both sides');
  Assert.AreEqual(1, Calls, 'content is read only for same-size files with equal time');
end;

procedure TTestPanelCompare.Run;
begin
  T0 := EncodeDateTime(2025, 1, 1, 12, 0, 0, 0);
  T1 := IncHour(T0, 1);

  Left := [Parent,
    Row('only-left.txt', 10, T0),
    Row('newer-left.txt', 10, T1),
    Row('older-left.txt', 10, T0),
    Row('same.txt', 10, T0),
    Row('size-differs.txt', 10, T0),
    Row('fat-time.txt', 10, T0),
    Row('Case.TXT', 10, T0),
    Row('dir-left', -1, T0, True),
    Row('dir-both', -1, T0, True),
    Row('file-vs-dir', 10, T1)];
  Right := [Parent,
    Row('only-right.txt', 10, T0, False, 'R'),
    Row('newer-left.txt', 10, T0, False, 'R'),
    Row('older-left.txt', 10, T1, False, 'R'),
    Row('same.txt', 10, T0, False, 'R'),
    Row('size-differs.txt', 20, T0, False, 'R'),
    Row('fat-time.txt', 10, IncSecond(T0, 2), False, 'R'),
    Row('case.txt', 10, T0, False, 'R'),
    Row('dir-right/', -1, T0, True, 'R'),
    Row('dir-both/', -1, T1, True, 'R'),
    Row('file-vs-dir', -1, T0, True, 'R')];
  Res := ComparePanelRows(Left, Right);

  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/only-left.txt'), 'file only on the left is selected');
  Assert.IsTrue(Has(Res.RightUris, 'file:///R/only-right.txt'), 'file only on the right is selected');
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/newer-left.txt') and
    not Has(Res.RightUris, 'file:///R/newer-left.txt'), 'newer side only');
  Assert.IsTrue(Has(Res.RightUris, 'file:///R/older-left.txt') and
    not Has(Res.LeftUris, 'file:///L/older-left.txt'), 'newer right side only');
  Assert.IsTrue(not Has(Res.LeftUris, 'file:///L/same.txt') and
    not Has(Res.RightUris, 'file:///R/same.txt'), 'equal files are not selected');
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/size-differs.txt') and
    Has(Res.RightUris, 'file:///R/size-differs.txt'), 'same time, other size: both');
  Assert.IsTrue(not Has(Res.LeftUris, 'file:///L/fat-time.txt') and
    not Has(Res.RightUris, 'file:///R/fat-time.txt'), '2 s apart counts as the same time (FAT)');
  Assert.IsTrue(not Has(Res.LeftUris, 'file:///L/Case.TXT') and
    not Has(Res.RightUris, 'file:///R/case.txt'), 'names compare case-insensitively');
  Assert.IsTrue(Has(Res.LeftUris, 'file:///L/dir-left'), 'folder only on the left is selected');
  Assert.IsTrue(Has(Res.RightUris, 'file:///R/dir-right/'), 'folder only on the right (trailing /) is selected');
  Assert.IsTrue(not Has(Res.LeftUris, 'file:///L/dir-both') and
    not Has(Res.RightUris, 'file:///R/dir-both/'), 'folders on both sides: never by time');
  Assert.IsTrue(not Has(Res.LeftUris, 'file:///L/file-vs-dir') and
    not Has(Res.RightUris, 'file:///R/file-vs-dir'), 'file against folder of the same name: left alone');
  Assert.IsTrue(Length(Res.LeftUris) = 4, Format('left count = 4 (%d)', [Length(Res.LeftUris)]));
  Assert.IsTrue(Length(Res.RightUris) = 4, Format('right count = 4 (%d)', [Length(Res.RightUris)]));

  Res := ComparePanelRows([Parent, Row('a.txt', 1, T0)],
    [Parent, Row('a.txt', 1, T0, False, 'R')]);
  Assert.IsTrue((Length(Res.LeftUris) = 0) and (Length(Res.RightUris) = 0),
    'identical folders: nothing selected, ".." never');

  // VFS without times (0): only presence and size count.
  Res := ComparePanelRows([Row('a', 5, 0), Row('b', 5, 0)],
    [Row('a', 5, T1, False, 'R'), Row('b', 6, 0, False, 'R')]);
  Assert.IsTrue((Length(Res.LeftUris) = 1) and Has(Res.LeftUris, 'file:///L/b') and
    Has(Res.RightUris, 'file:///R/b'), 'no time: size decides');

  Res := ComparePanelRows([Row('x', 1, T0), Row('X', 1, T1)], []);
  Assert.IsTrue(Length(Res.LeftUris) = 2, 'same-name duplicates (flat view) are both unique');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelCompare);

end.
