unit TestWinSysFormat;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWinSysFormat = class
  public
    [Test] procedure TestParseUriSplitsKindAndSegments;
    [Test] procedure TestParseUriRejectsOtherSchemes;
    [Test] procedure TestSegmentEncodingKeepsSlashAndPercentInsideOneName;
    [Test] procedure TestProcessNameCarriesThePid;
    [Test] procedure TestStringValueRoundTrips;
    [Test] procedure TestDwordShowsHexAndDecimalAndParsesBoth;
    [Test] procedure TestDwordOutOfRangeIsRejected;
    [Test] procedure TestQwordRoundTrips;
    [Test] procedure TestMultiStringRoundTripsAsLines;
    [Test] procedure TestTypeLineChangesTheTypeOnWrite;
    [Test] procedure TestBinaryIsShownAsHexDumpAndNotWritable;
    [Test] procedure TestTextWithoutTypeLineUsesTheDefaultType;
    [Test] procedure TestFileTimeConvertsToUnixSeconds;
  end;

implementation

uses
  System.SysUtils, uWinSysFormat;

function Wide(const AText: string): TBytes;
begin
  SetLength(Result, (Length(AText) + 1) * 2);
  if AText <> '' then
    Move(PChar(AText)^, Result[0], Length(AText) * 2);
  Result[High(Result)] := 0;
  Result[High(Result) - 1] := 0;
end;

procedure TTestWinSysFormat.TestParseUriSplitsKindAndSegments;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
begin
  Assert.IsTrue(ParseWinSysUri('reg:///HKEY_CURRENT_USER/Software/A', Kind, Segs));
  Assert.AreEqual(Ord(wkReg), Ord(Kind));
  Assert.AreEqual(3, Integer(Length(Segs)));
  Assert.AreEqual('HKEY_CURRENT_USER', Segs[0]);
  Assert.AreEqual('A', Segs[2]);
  Assert.IsTrue(ParseWinSysUri('svc:///', Kind, Segs));
  Assert.AreEqual(Ord(wkSvc), Ord(Kind));
  Assert.AreEqual(0, Integer(Length(Segs)));
  Assert.IsTrue(ParseWinSysUri('proc:///x.exe (12)', Kind, Segs));
  Assert.AreEqual('x.exe (12)', Segs[0]);
end;

procedure TTestWinSysFormat.TestParseUriRejectsOtherSchemes;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
begin
  Assert.IsFalse(ParseWinSysUri('file:///C:/x', Kind, Segs));
  Assert.IsFalse(ParseWinSysUri('plain', Kind, Segs));
  Assert.AreEqual(Ord(wkNone), Ord(Kind));
end;

procedure TTestWinSysFormat.TestSegmentEncodingKeepsSlashAndPercentInsideOneName;
var
  Kind: TWinSysKind;
  Segs: TArray<string>;
begin
  Assert.AreEqual('a%2Fb%25c', EncodeSegment('a/b%c'));
  Assert.AreEqual('a/b%c', DecodeSegment('a%2Fb%25c'));
  Assert.AreEqual('50%2', DecodeSegment('50%2'), 'a lone percent stays');
  Assert.AreEqual('a%2F', DecodeSegment('a%252F'), 'an encoded percent is not decoded twice');
  Assert.IsTrue(ParseWinSysUri('reg:///HKEY_LOCAL_MACHINE/a%2Fb', Kind, Segs));
  Assert.AreEqual(2, Integer(Length(Segs)));
  Assert.AreEqual('a/b', Segs[1]);
end;

procedure TTestWinSysFormat.TestProcessNameCarriesThePid;
var
  Pid: Cardinal;
begin
  Assert.AreEqual('chrome.exe (4242)', MakeProcessName('chrome.exe', 4242));
  Assert.IsTrue(ParseProcessName('chrome.exe (4242)', Pid));
  Assert.AreEqual(Cardinal(4242), Pid);
  Assert.IsTrue(ParseProcessName('a (b) (7)', Pid));
  Assert.AreEqual(Cardinal(7), Pid);
  Assert.IsFalse(ParseProcessName('chrome.exe', Pid));
  Assert.IsFalse(ParseProcessName('chrome.exe (x)', Pid));
  Assert.IsFalse(ParseProcessName('(5)', Pid));
end;

procedure TTestWinSysFormat.TestStringValueRoundTrips;
var
  Text: string;
  T: Cardinal;
  Data: TBytes;
begin
  Text := FormatRegValue(cRegSz, Wide('C:\Tools'));
  Assert.AreEqual('Type: REG_SZ' + #10#10 + 'C:\Tools', Text);
  Assert.IsTrue(ParseRegValueText(Text + #13#10, cRegSz, T, Data));
  Assert.AreEqual(Cardinal(cRegSz), T);
  Assert.AreEqual(FormatRegValue(cRegSz, Wide('C:\Tools')), FormatRegValue(T, Data));
  Assert.AreEqual(Length(Wide('C:\Tools')), Length(Data), 'one terminating nul');
end;

procedure TTestWinSysFormat.TestDwordShowsHexAndDecimalAndParsesBoth;
var
  Raw, Data: TBytes;
  T: Cardinal;
begin
  SetLength(Raw, 4);
  PCardinal(@Raw[0])^ := 42;
  Assert.AreEqual('Type: REG_DWORD' + #10#10 + '0x0000002A (42)', FormatRegValue(cRegDword, Raw));
  Assert.IsTrue(ParseRegValueText('0x0000002A (42)', cRegDword, T, Data));
  Assert.AreEqual(Cardinal(42), PCardinal(@Data[0])^);
  Assert.IsTrue(ParseRegValueText('Type: REG_DWORD' + #10#10 + '17', cRegSz, T, Data));
  Assert.AreEqual(Cardinal(17), PCardinal(@Data[0])^);
  Assert.AreEqual(4, Integer(Length(Data)));
end;

procedure TTestWinSysFormat.TestDwordOutOfRangeIsRejected;
var
  T: Cardinal;
  Data: TBytes;
begin
  Assert.IsFalse(ParseRegValueText('4294967296', cRegDword, T, Data));
  Assert.IsFalse(ParseRegValueText('abc', cRegDword, T, Data));
  Assert.IsFalse(ParseRegValueText('', cRegDword, T, Data));
end;

procedure TTestWinSysFormat.TestQwordRoundTrips;
var
  Raw, Data: TBytes;
  T: Cardinal;
  V: UInt64;
begin
  V := $123456789A;
  SetLength(Raw, 8);
  Move(V, Raw[0], 8);
  Assert.AreEqual('Type: REG_QWORD' + #10#10 + '0x000000123456789A (78187493530)',
    FormatRegValue(cRegQword, Raw));
  Assert.IsTrue(ParseRegValueText(FormatRegValue(cRegQword, Raw), cRegQword, T, Data));
  Assert.AreEqual(8, Integer(Length(Data)));
  Assert.AreEqual(UInt64($123456789A), PUInt64(@Data[0])^);
end;

procedure TTestWinSysFormat.TestMultiStringRoundTripsAsLines;
var
  Raw, Data: TBytes;
  T: Cardinal;
  Text: string;
begin
  Raw := Wide('one' + #0 + 'two' + #0);
  Text := FormatRegValue(cRegMultiSz, Raw);
  Assert.AreEqual('Type: REG_MULTI_SZ' + #10#10 + 'one' + #10 + 'two', Text);
  Assert.IsTrue(ParseRegValueText(Text + #10, cRegMultiSz, T, Data));
  Assert.AreEqual(FormatRegValue(cRegMultiSz, Raw), FormatRegValue(cRegMultiSz, Data));
  Assert.IsTrue(ParseRegValueText('Type: REG_MULTI_SZ' + #10#10, cRegSz, T, Data));
  Assert.AreEqual(2, Integer(Length(Data)), 'an empty list is one terminator');
end;

procedure TTestWinSysFormat.TestTypeLineChangesTheTypeOnWrite;
var
  T: Cardinal;
  Data: TBytes;
begin
  Assert.IsTrue(ParseRegValueText('Type: REG_EXPAND_SZ' + #10#10 + '%TEMP%', cRegSz, T, Data));
  Assert.AreEqual(Cardinal(cRegExpandSz), T);
  Assert.IsFalse(ParseRegValueText('Type: REG_NOPE' + #10#10 + 'x', cRegSz, T, Data));
end;

procedure TTestWinSysFormat.TestBinaryIsShownAsHexDumpAndNotWritable;
var
  Raw, Data: TBytes;
  T: Cardinal;
begin
  SetLength(Raw, 3);
  Raw[0] := $41;
  Raw[1] := $00;
  Raw[2] := $FF;
  Assert.AreEqual('Type: REG_BINARY' + #10#10 +
    '00000000  41 00 FF ' + StringOfChar(' ', 39) + ' |A..|',
    FormatRegValue(cRegBinary, Raw));
  Assert.IsFalse(IsEditableRegType(cRegBinary));
  Assert.IsFalse(ParseRegValueText('Type: REG_BINARY' + #10#10 + '41', cRegSz, T, Data));
  Assert.IsFalse(ParseRegValueText('41', cRegBinary, T, Data));
end;

procedure TTestWinSysFormat.TestTextWithoutTypeLineUsesTheDefaultType;
var
  T: Cardinal;
  Data: TBytes;
begin
  Assert.IsTrue(ParseRegValueText('plain', cRegExpandSz, T, Data));
  Assert.AreEqual(Cardinal(cRegExpandSz), T);
end;

procedure TTestWinSysFormat.TestFileTimeConvertsToUnixSeconds;
begin
  Assert.AreEqual(Int64(0), FileTimeToUnixSeconds(0));
  Assert.AreEqual(Int64(0), FileTimeToUnixSeconds(116444736000000000));
  Assert.AreEqual(Int64(86400), FileTimeToUnixSeconds(UInt64(116444736000000000) + UInt64(86400) * 10000000));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinSysFormat);

end.
