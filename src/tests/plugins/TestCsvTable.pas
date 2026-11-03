unit TestCsvTable;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCsvTable = class
  public
    [Test] procedure TestAlignsColumnsAndRulesUnderTheHeader;
    [Test] procedure TestDetectsSemicolonTabAndBar;
    [Test] procedure TestQuotedCellsKeepDelimitersAndQuotes;
    [Test] procedure TestLineBreakInsideQuotesStaysInOneRecord;
    [Test] procedure TestEmptyLinesAreSkippedAndShortRowsPadded;
    [Test] procedure TestLongCellsAreCutWithEllipsis;
    [Test] procedure TestRowLimitStopsTheParse;
    [Test] procedure TestDecodeHandlesBomsAndLegacyBytes;
  end;

implementation

uses
  System.SysUtils, uCsvTable;

procedure TTestCsvTable.TestAlignsColumnsAndRulesUnderTheHeader;
var
  Info: TCsvTableInfo;
begin
  Assert.AreEqual('name   | qty' + #13#10 + '-------+----' + #13#10 + 'ap     | 1' + #13#10 +
    'banana | 20' + #13#10,
    RenderCsvTable('name,qty' + #10 + 'ap,1' + #10 + 'banana,20' + #10, #0, 60, 0, Info));
  Assert.AreEqual(3, Info.Rows);
  Assert.AreEqual(2, Info.Columns);
  Assert.AreEqual(',', string(Info.Delimiter));
  Assert.IsFalse(Info.RowsCut);
end;

procedure TTestCsvTable.TestDetectsSemicolonTabAndBar;
begin
  Assert.AreEqual(';', string(DetectCsvDelimiter('a;b;c' + #10 + '1;2;3' + #10)));
  Assert.AreEqual(#9, string(DetectCsvDelimiter('a' + #9 + 'b' + #10 + '1' + #9 + '2' + #10)));
  Assert.AreEqual('|', string(DetectCsvDelimiter('a|b' + #10 + '1|2' + #10)));
  Assert.AreEqual(',', string(DetectCsvDelimiter('just text' + #10 + 'more text' + #10)),
    'no candidate splits anything: comma');
  Assert.AreEqual(';', string(DetectCsvDelimiter('x;"a,b,c";y' + #10 + '1;"2,3,4";5' + #10)),
    'delimiters inside quotes do not count');
end;

procedure TTestCsvTable.TestQuotedCellsKeepDelimitersAndQuotes;
var
  Rows: TCsvRows;
  Cut: Boolean;
begin
  Rows := ParseCsv('a,"b,c","d""e"', ',', 0, Cut);
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.AreEqual(3, Integer(Length(Rows[0])));
  Assert.AreEqual('b,c', Rows[0][1]);
  Assert.AreEqual('d"e', Rows[0][2]);
end;

procedure TTestCsvTable.TestLineBreakInsideQuotesStaysInOneRecord;
var
  Rows: TCsvRows;
  Cut: Boolean;
  Info: TCsvTableInfo;
begin
  Rows := ParseCsv('a,"x' + #13#10 + 'y",c' + #13#10 + '1,2,3', ',', 0, Cut);
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.AreEqual('x' + #13#10 + 'y', Rows[0][1]);
  Assert.AreEqual('a | x y | c', Copy(RenderCsvTable('a,"x' + #10 + 'y",c', ',', 60, 0, Info), 1, 11),
    'a line break in a cell is shown as a space');
end;

procedure TTestCsvTable.TestEmptyLinesAreSkippedAndShortRowsPadded;
var
  Rows: TCsvRows;
  Cut: Boolean;
  Info: TCsvTableInfo;
begin
  Rows := ParseCsv('a,b' + #10 + #10 + '1' + #10 + #13#10 + '2,3', ',', 0, Cut);
  Assert.AreEqual(3, Integer(Length(Rows)));
  Assert.AreEqual('a | b' + #13#10 + '--+--' + #13#10 + '1' + #13#10 + '2 | 3' + #13#10,
    RenderCsvTable('a,b' + #10 + #10 + '1' + #10 + '2,3', ',', 60, 0, Info));
end;

procedure TTestCsvTable.TestLongCellsAreCutWithEllipsis;
var
  Info: TCsvTableInfo;
  Table: string;
begin
  Table := RenderCsvTable('h' + #10 + StringOfChar('x', 30), ',', 10, 0, Info);
  Assert.IsTrue(Pos('xxxxxxx...', Table) > 0, Table);
  Assert.IsTrue(Pos(StringOfChar('x', 11), Table) = 0, 'the cell is no wider than the limit');
end;

procedure TTestCsvTable.TestRowLimitStopsTheParse;
var
  Info: TCsvTableInfo;
begin
  RenderCsvTable('a' + #10 + 'b' + #10 + 'c' + #10 + 'd', ',', 60, 2, Info);
  Assert.AreEqual(2, Info.Rows);
  Assert.IsTrue(Info.RowsCut);
  RenderCsvTable('a' + #10 + 'b', ',', 60, 2, Info);
  Assert.IsFalse(Info.RowsCut, 'all records fit exactly');
end;

procedure TTestCsvTable.TestDecodeHandlesBomsAndLegacyBytes;
var
  Utf8Bom, Utf16, Legacy: TBytes;
begin
  Utf8Bom := [$EF, $BB, $BF, Ord('a'), Ord(',')];
  Assert.AreEqual('a,', DecodeCsvBytes(Utf8Bom));
  Utf16 := [$FF, $FE, Ord('h'), 0, Ord('i'), 0];
  Assert.AreEqual('hi', DecodeCsvBytes(Utf16));
  Assert.AreEqual(#$0416, DecodeCsvBytes(TEncoding.UTF8.GetBytes(#$0416)));
  Legacy := [Ord('a'), $FF, Ord('b')];
  Assert.AreEqual(3, Length(DecodeCsvBytes(Legacy)), 'invalid UTF-8 falls back to the code page');
  Assert.AreEqual('', DecodeCsvBytes(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCsvTable);

end.
