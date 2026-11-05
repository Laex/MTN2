unit TestDocText;

{ Text views of document files: XML text runs, Office archives, SVG summary,
  SQLite tables and PDF page text. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDocText = class
  private
    FDir: string;
    function Zipped(const AName: string; const AParts: array of string): string;
    function SqliteFixture: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestXmlDecodeKnownAndNumericEntities;
    [Test] procedure TestRunsTextBreaksParagraphsAndKeepsTabs;
    [Test] procedure TestColumnIndexOfCellReference;
    [Test] procedure TestDocxBodyText;
    [Test] procedure TestXlsxCellsKeepColumnPositions;
    [Test] procedure TestPptxTextPerSlide;
    [Test] procedure TestBrokenArchiveGivesNothing;
    [Test] procedure TestSvgSummaryListsSizeAndElements;
    [Test] procedure TestSvgOnOneLongLineIsIndented;
    [Test] procedure TestSqliteShowsSchemaAndRows;
    [Test] procedure TestNonSqliteFileGivesNothing;
    [Test] procedure TestPdfPlainAndCompressedStreams;
    [Test] procedure TestPdfEscapesAndArrays;
    [Test] procedure TestNotAPdfGivesNothing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.ZLib,
  System.StrUtils, uDocText;

procedure TTestDocText.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-doctext-' + IntToStr(TThread.CurrentThread.ThreadID));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestDocText.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

{ An archive made of name/content pairs. }
function TTestDocText.Zipped(const AName: string; const AParts: array of string): string;
var
  Zip: TZipFile;
  I: Integer;
  S: TBytesStream;
begin
  Result := TPath.Combine(FDir, AName);
  Zip := TZipFile.Create;
  try
    Zip.Open(Result, zmWrite);
    I := 0;
    while I < High(AParts) do
    begin
      S := TBytesStream.Create(TEncoding.UTF8.GetBytes(AParts[I + 1]));
      try
        Zip.Add(S, AParts[I]);
      finally
        S.Free;
      end;
      Inc(I, 2);
    end;
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

{ A SQLite file of three 512-byte pages: table items(id integer primary key,
  name text, qty real, note blob) with two rows, and an index on name. }
function TTestDocText.SqliteFixture: string;
var
  B: TBytes;

  procedure Put(AOffset: Integer; const AHex: string);
  var
    I: Integer;
  begin
    for I := 0 to Length(AHex) div 2 - 1 do
      B[AOffset + I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
  end;

begin
  SetLength(B, 1536);
  Put(0, '53514c69746520666f726d617420330002000101004020200000000200000003'
    + '00000000000000000000000200000004000000000000000000000001');
  Put(95, '02002e8a140d00000002016a00019d016a');
  Put(362, '3102061711170149696e64657869786974656d730343524541544520494e4445'
    + '58206978206f6e206974656d73286e616d65296101071717170181217461626c'
    + '656974656d736974656d7302435245415445205441424c45206974656d732869'
    + '6420696e7465676572207072696d617279206b65792c206e616d652074657874'
    + '2c20717479207265616c2c206e6f746520626c6f62290d0000000201dc0001ec'
    + '01dc');
  Put(988, '0e02050019011062c3a9746f6e140102120105001707006170706c653ff80000'
    + '000000000a0000000201ec0001f701ec');
  Put(1516, '0a03190162c3a9746f6e02080317096170706c65');
  Result := TPath.Combine(FDir, 'fixture.db');
  TFile.WriteAllBytes(Result, B);
end;

procedure TTestDocText.TestXmlDecodeKnownAndNumericEntities;
begin
  Assert.AreEqual('a & b < c > "d" ''e''', XmlDecode('a &amp; b &lt; c &gt; &quot;d&quot; &apos;e&apos;'));
  Assert.AreEqual('A' + Char($00E9), XmlDecode('&#65;&#xE9;'));
  Assert.AreEqual('x &unknown; y', XmlDecode('x &unknown; y'));
  Assert.AreEqual('fish & chips', XmlDecode('fish & chips'));
end;

procedure TTestDocText.TestRunsTextBreaksParagraphsAndKeepsTabs;
begin
  Assert.AreEqual('one' + #9 + 'two' + #13#10 + 'three&' + #13#10,
    XmlRunsText('<w:p><w:r><w:t>one</w:t></w:r><w:tab/><w:r><w:t xml:space="preserve">two</w:t></w:r></w:p>' +
      '<w:p><w:r><w:t>three&amp;</w:t></w:r></w:p>', 'w:t', 'w:p'));
end;

procedure TTestDocText.TestColumnIndexOfCellReference;
begin
  Assert.AreEqual(0, ColumnIndexOfRef('A1'));
  Assert.AreEqual(1, ColumnIndexOfRef('B22'));
  Assert.AreEqual(26, ColumnIndexOfRef('AA10'));
end;

procedure TTestDocText.TestDocxBodyText;
var
  Path: string;
begin
  Path := Zipped('a.docx', ['word/document.xml',
    '<w:document><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p><w:p><w:r><w:t>World</w:t></w:r></w:p></w:body></w:document>']);
  Assert.AreEqual('Hello' + #13#10 + 'World' + #13#10, OfficeText(Path));
end;

procedure TTestDocText.TestXlsxCellsKeepColumnPositions;
var
  Path: string;
begin
  Path := Zipped('a.xlsx', [
    'xl/workbook.xml', '<workbook><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/sharedStrings.xml', '<sst><si><t>name</t></si><si><r><t>qty</t></r></si><si><t>apple</t></si></sst>',
    'xl/worksheets/sheet1.xml', '<worksheet><sheetData>' +
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' +
      '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>3</v></c></row>' +
      '<row r="3"><c r="C3" t="inlineStr"><is><t>x</t></is></c></row>' +
      '</sheetData></worksheet>']);
  Assert.AreEqual('=== Data ===' + #13#10 + 'name' + #9 + 'qty' + #13#10 + 'apple' + #9 + '3' + #13#10 +
    #9#9 + 'x' + #13#10 + #13#10, OfficeText(Path));
end;

procedure TTestDocText.TestPptxTextPerSlide;
var
  Path, Text: string;
begin
  Path := Zipped('a.pptx', [
    'ppt/slides/slide10.xml', '<p:sld><a:p><a:r><a:t>Ten</a:t></a:r></a:p></p:sld>',
    'ppt/slides/slide2.xml', '<p:sld><a:p><a:r><a:t>Two</a:t></a:r></a:p></p:sld>']);
  Text := OfficeText(Path);
  Assert.IsTrue(Pos('Slide 1 ===' + #13#10 + 'Two', Text) > 0, 'slide2 comes before slide10: ' + Text);
  Assert.IsTrue(Pos('Slide 2 ===' + #13#10 + 'Ten', Text) > 0, Text);
end;

procedure TTestDocText.TestBrokenArchiveGivesNothing;
var
  Path: string;
begin
  Path := TPath.Combine(FDir, 'bad.docx');
  TFile.WriteAllText(Path, 'not a zip');
  Assert.AreEqual('', OfficeText(Path));
end;

procedure TTestDocText.TestSvgSummaryListsSizeAndElements;
var
  Text: string;
begin
  Text := SvgText('<svg width="10" height="20" viewBox="0 0 10 20"><title>Logo</title>' +
    '<rect x="0"/><rect x="1"/><circle r="2"/><text>Hi</text></svg>');
  Assert.IsTrue(Pos('width: 10', Text) > 0, Text);
  Assert.IsTrue(Pos('viewBox: 0 0 10 20', Text) > 0, Text);
  Assert.IsTrue(Pos('rect 2', Text) > 0, Text);
  Assert.IsTrue(Pos('circle 1', Text) > 0, Text);
  Assert.IsTrue(Pos('title: Logo', Text) > 0, Text);
  Assert.IsTrue(Pos('text: Hi', Text) > 0, Text);
  Assert.AreEqual('', SvgText('<html></html>'));
end;

procedure TTestDocText.TestSvgOnOneLongLineIsIndented;
var
  Text: string;
begin
  Text := SvgText('<svg width="1"><g>' + StringOfChar(' ', 310) + '<path d="M0"/></g></svg>');
  Assert.IsTrue(Pos(#13#10 + '  <g>' + #13#10 + '    <path d="M0"/>' + #13#10 + '  </g>', Text) > 0, Text);
end;

procedure TTestDocText.TestSqliteShowsSchemaAndRows;
var
  Text: string;
begin
  Text := SqliteText(SqliteFixture);
  Assert.IsTrue(Pos('=== table items ===', Text) > 0, Text);
  Assert.IsTrue(Pos('id' + #9 + 'name' + #9 + 'qty' + #9 + 'note', Text) > 0, Text);
  Assert.IsTrue(Pos('1' + #9 + 'apple' + #9 + '1.5' + #9 + 'NULL', Text) > 0, 'rowid alias is filled in: ' + Text);
  Assert.IsTrue(Pos('2' + #9 + 'b' + Char($00E9) + 'ton' + #9 + '20' + #9 + '<blob 2 bytes>', Text) > 0, Text);
  Assert.IsTrue(Pos('(2 rows)', Text) > 0, Text);
  Assert.IsTrue(Pos('index ix:', Text) > 0, Text);
end;

procedure TTestDocText.TestNonSqliteFileGivesNothing;
var
  Path: string;
begin
  Path := TPath.Combine(FDir, 'Thumbs.db');
  TFile.WriteAllBytes(Path, TEncoding.ASCII.GetBytes(StringOfChar('x', 2000)));
  Assert.AreEqual('', SqliteText(Path));
  Assert.AreEqual('', SqliteText(TPath.Combine(FDir, 'missing.db')));
end;

function Deflated(const AText: string): TBytes;
var
  Src: TBytesStream;
  Dst: TBytesStream;
  Z: TZCompressionStream;
begin
  Src := TBytesStream.Create(TEncoding.ASCII.GetBytes(AText));
  Dst := TBytesStream.Create;
  try
    Z := TZCompressionStream.Create(Dst);
    try
      Z.CopyFrom(Src, 0);
    finally
      Z.Free;
    end;
    Result := Copy(Dst.Bytes, 0, Dst.Size);
  finally
    Dst.Free;
    Src.Free;
  end;
end;

{ A PDF of the given streams; every second one is marked as compressed. }
function PdfOf(const AParts: array of TBytes): TBytes;
var
  S: TBytesStream;
  I: Integer;

  procedure W(const A: string);
  var
    B: TBytes;
  begin
    B := TEncoding.ASCII.GetBytes(A);
    S.WriteBuffer(B[0], Length(B));
  end;

begin
  S := TBytesStream.Create;
  try
    W('%PDF-1.4' + #10);
    for I := 0 to High(AParts) do
    begin
      W(IntToStr(I + 1) + ' 0 obj' + #10);
      W('<< /Length ' + IntToStr(Length(AParts[I])) + IfThen(I mod 2 = 1, ' /Filter /FlateDecode', '') + ' >>' + #10);
      W('stream' + #10);
      S.WriteBuffer(AParts[I][0], Length(AParts[I]));
      W(#10 + 'endstream' + #10 + 'endobj' + #10);
    end;
    W('%%EOF');
    Result := Copy(S.Bytes, 0, S.Size);
  finally
    S.Free;
  end;
end;

procedure TTestDocText.TestPdfPlainAndCompressedStreams;
var
  Text: string;
begin
  Text := PdfText(PdfOf([
    TEncoding.ASCII.GetBytes('BT /F1 12 Tf 72 700 Td (Hello World) Tj 0 -14 Td (Second line) Tj ET'),
    Deflated('BT 1 0 0 1 72 600 Tm (Packed text) Tj ET')]));
  Assert.IsTrue(Pos('Hello World' + #13#10 + 'Second line', Text) > 0, Text);
  Assert.IsTrue(Pos('Packed text', Text) > 0, Text);
end;

procedure TTestDocText.TestPdfEscapesAndArrays;
var
  Text: string;
begin
  Text := PdfText(PdfOf([
    TEncoding.ASCII.GetBytes('BT [(Ab) -500 (cd) 20 (e\(f\))] TJ ( \101) Tj <4849> Tj ET')]));
  Assert.IsTrue(Pos('Ab cde(f)', Text) > 0, Text);
  Assert.IsTrue(Pos(' A', Text) > 0, Text);
  Assert.IsTrue(Pos('HI', Text) > 0, Text);
end;

procedure TTestDocText.TestNotAPdfGivesNothing;
begin
  Assert.AreEqual('', PdfText(TEncoding.ASCII.GetBytes('hello')));
  Assert.AreEqual('', PdfText(PdfOf([TEncoding.ASCII.GetBytes('q Q')])));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDocText);

end.
