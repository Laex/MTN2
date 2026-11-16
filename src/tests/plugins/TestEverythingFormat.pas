unit TestEverythingFormat;

{ Addresses, the query message and the result list reader of the Everything plugin. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEverythingFormat = class
  public
    [Test] procedure TestUriRoundTripsSlashesAndPercent;
    [Test] procedure TestForeignSchemeIsRejected;
    [Test] procedure TestItemPathJoinsWithBackslash;
    [Test] procedure TestQueryMessageHoldsHeaderAndTerminatedText;
    [Test] procedure TestListReaderGivesNamesFoldersAndKinds;
    [Test] procedure TestListWithOffsetOutsideTheBlockIsRejected;
    [Test] procedure TestShortBlockIsRejected;
    [Test] procedure TestRequestReadsEveryParameter;
    [Test] procedure TestRequestDefaultsAndRejections;
    [Test] procedure TestQueryScopesFilesUnderTheRoot;
    [Test] procedure TestQueryGroupsSeveralMasks;
    [Test] procedure TestQueryMatchesPlainNameAsWholeName;
    [Test] procedure TestQueryAllNamesHasNoMaskTerm;
    [Test] procedure TestQuerySwitchesFollowTheRequest;
    [Test] procedure TestBoundsCheckSizeAndDate;
  end;

implementation

uses
  System.SysUtils, uSearchRequest, uEverythingFormat;

procedure TTestEverythingFormat.TestUriRoundTripsSlashesAndPercent;
var
  Query: string;
begin
  Assert.AreEqual('everything:///a%2Fb%25c d', EverythingUri('a/b%c d'));
  Assert.IsTrue(ParseEverythingUri(EverythingUri('ext:pdf path:"C:/Work" 100%'), Query));
  Assert.AreEqual('ext:pdf path:"C:/Work" 100%', Query);
end;

procedure TTestEverythingFormat.TestForeignSchemeIsRejected;
var
  Query: string;
begin
  Assert.IsFalse(ParseEverythingUri('rclone:///x', Query));
  Assert.AreEqual('', Query);
end;

procedure TTestEverythingFormat.TestItemPathJoinsWithBackslash;
var
  Item: TEvItem;
begin
  Item.Name := 'a.txt';
  Item.IsDir := False;
  Item.Dir := 'C:\Work';
  Assert.AreEqual('C:\Work\a.txt', ItemPath(Item));
  Item.Dir := 'C:\';
  Assert.AreEqual('C:\a.txt', ItemPath(Item));
  Item.Dir := '';
  Assert.AreEqual('a.txt', ItemPath(Item));
end;

procedure TTestEverythingFormat.TestQueryMessageHoldsHeaderAndTerminatedText;
var
  Bytes: TArray<Byte>;
  Wnd, Msg, Max: Cardinal;
begin
  Bytes := BuildIpcQuery(7, 3, 100, 'ab');
  // Five 32-bit fields, then "ab" and the terminator in UTF-16.
  Assert.AreEqual(26, Integer(Length(Bytes)));
  Move(Bytes[0], Wnd, 4);
  Move(Bytes[4], Msg, 4);
  Move(Bytes[16], Max, 4);
  Assert.AreEqual(Cardinal(7), Wnd);
  Assert.AreEqual(Cardinal(3), Msg);
  Assert.AreEqual(Cardinal(100), Max);
  Assert.AreEqual(Byte(Ord('a')), Bytes[20]);
  Assert.AreEqual(Byte(Ord('b')), Bytes[22]);
  Assert.AreEqual(Byte(0), Bytes[24]);
  Assert.AreEqual(Byte(0), Bytes[25]);
end;

// A list block as Everything sends it: the header, the item table, then the strings.
function MakeList(const ANames, ADirs: array of string; const AFolders: array of Boolean;
  ABreakOffset: Boolean): TBytes;
var
  Count, I, Pos: Integer;
  Cursor: Cardinal;
  Strings: TBytes;
  Table: array of Cardinal;
  Head: array[0..6] of Cardinal;

  function Put(const AText: string): Cardinal;
  var
    Raw: TBytes;
  begin
    Result := Cardinal(28 + Count * 12 + Length(Strings));
    Raw := TEncoding.Unicode.GetBytes(AText + #0);
    Pos := Length(Strings);
    SetLength(Strings, Pos + Length(Raw));
    Move(Raw[0], Strings[Pos], Length(Raw));
  end;

begin
  Count := Length(ANames);
  SetLength(Table, Count * 3);
  for I := 0 to Count - 1 do
  begin
    Table[I * 3] := Ord(AFolders[I]);
    Table[I * 3 + 1] := Put(ANames[I]);
    Table[I * 3 + 2] := Put(ADirs[I]);
  end;
  if ABreakOffset then
    Table[1] := 100000;
  FillChar(Head, SizeOf(Head), 0);
  Head[2] := Cardinal(Count);
  Head[5] := Cardinal(Count);
  Cursor := 0;
  SetLength(Result, 28 + Count * 12 + Length(Strings));
  Move(Head[0], Result[0], 28);
  Move(Table[0], Result[28], Count * 12);
  Move(Strings[0], Result[28 + Count * 12], Length(Strings));
end;

procedure TTestEverythingFormat.TestListReaderGivesNamesFoldersAndKinds;
var
  Block: TBytes;
  Items: TEvItems;
begin
  Block := MakeList(['a.txt', 'Docs'], ['C:\Work', 'C:\'], [False, True], False);
  Assert.IsTrue(ParseIpcList(@Block[0], Length(Block), Items));
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('a.txt', Items[0].Name);
  Assert.AreEqual('C:\Work', Items[0].Dir);
  Assert.IsFalse(Items[0].IsDir);
  Assert.AreEqual('Docs', Items[1].Name);
  Assert.IsTrue(Items[1].IsDir);
end;

procedure TTestEverythingFormat.TestListWithOffsetOutsideTheBlockIsRejected;
var
  Block: TBytes;
  Items: TEvItems;
begin
  Block := MakeList(['a.txt'], ['C:\Work'], [False], True);
  Assert.IsFalse(ParseIpcList(@Block[0], Length(Block), Items));
  Assert.AreEqual(0, Integer(Length(Items)));
end;

procedure TTestEverythingFormat.TestShortBlockIsRejected;
var
  Block: TBytes;
  Items: TEvItems;
begin
  SetLength(Block, 10);
  Assert.IsFalse(ParseIpcList(@Block[0], Length(Block), Items));
  Assert.IsFalse(ParseIpcList(nil, 0, Items));
end;

const
  cRequest =
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"root":"C:\\Work","mask":"*.txt;*.md",' +
    '"subdirs":false,"caseSensitive":true,"wholeWords":true,"includeFolders":true,' +
    '"minSize":10,"maxSize":2000,"modifiedFrom":"2026-01-01T00:00:00","maxResults":7}}';

function DefaultRequest: TSearchRequest;
begin
  Assert.IsTrue(ParseSearchRequest('{"params":{"root":"C:\\Work","mask":"*.txt"}}', Result));
end;

procedure TTestEverythingFormat.TestRequestReadsEveryParameter;
var
  R: TSearchRequest;
begin
  Assert.IsTrue(ParseSearchRequest(cRequest, R));
  Assert.AreEqual('C:\Work', R.Root);
  Assert.AreEqual('*.txt;*.md', R.Mask);
  Assert.IsFalse(R.Subdirs);
  Assert.IsTrue(R.CaseSensitive);
  Assert.IsTrue(R.WholeWords);
  Assert.IsTrue(R.IncludeFolders);
  Assert.AreEqual<Int64>(10, R.MinSize);
  Assert.AreEqual<Int64>(2000, R.MaxSize);
  Assert.AreEqual('2026-01-01T00:00:00', R.ModifiedFrom);
  Assert.AreEqual('', R.ModifiedTo);
  Assert.AreEqual(7, R.MaxResults);
end;

procedure TTestEverythingFormat.TestRequestDefaultsAndRejections;
var
  R: TSearchRequest;
begin
  R := DefaultRequest;
  Assert.IsTrue(R.Subdirs, 'subfolders are searched unless switched off');
  Assert.IsFalse(R.IncludeFolders);
  Assert.AreEqual<Int64>(-1, R.MinSize);
  Assert.IsFalse(SearchRequestHasBounds(R));
  Assert.IsFalse(ParseSearchRequest('{"params":{"mask":"*.txt"}}', R), 'no root');
  Assert.IsFalse(ParseSearchRequest('{"id":1}', R), 'no params');
  Assert.IsFalse(ParseSearchRequest('not json', R));
end;

procedure TTestEverythingFormat.TestQueryScopesFilesUnderTheRoot;
begin
  Assert.AreEqual('file: "C:\Work\" *.txt', BuildEverythingQuery(DefaultRequest));
end;

procedure TTestEverythingFormat.TestQueryGroupsSeveralMasks;
var
  R: TSearchRequest;
begin
  R := DefaultRequest;
  R.Mask := '*.txt;*.md';
  Assert.AreEqual('file: "C:\Work\" <*.txt|*.md>', BuildEverythingQuery(R));
end;

procedure TTestEverythingFormat.TestQueryMatchesPlainNameAsWholeName;
var
  R: TSearchRequest;
begin
  R := DefaultRequest;
  R.Mask := 'readme.md';
  Assert.AreEqual('file: "C:\Work\" wfn:"readme.md"', BuildEverythingQuery(R));
end;

procedure TTestEverythingFormat.TestQueryAllNamesHasNoMaskTerm;
var
  R: TSearchRequest;
begin
  R := DefaultRequest;
  R.Mask := '*.*';
  Assert.AreEqual('file: "C:\Work\"', BuildEverythingQuery(R));
end;

procedure TTestEverythingFormat.TestQuerySwitchesFollowTheRequest;
var
  R: TSearchRequest;
begin
  Assert.IsTrue(ParseSearchRequest(cRequest, R));
  Assert.AreEqual('ww: case: parent:"C:\Work" <*.txt|*.md>', BuildEverythingQuery(R));
end;

procedure TTestEverythingFormat.TestBoundsCheckSizeAndDate;
var
  R: TSearchRequest;
begin
  Assert.IsTrue(ParseSearchRequest(cRequest, R));
  Assert.IsTrue(SearchRequestHasBounds(R));
  Assert.IsTrue(SearchRequestBoundsPass(R, False, 500, '2026-03-01T10:00:00'));
  Assert.IsFalse(SearchRequestBoundsPass(R, False, 5, '2026-03-01T10:00:00'), 'below the minimum');
  Assert.IsFalse(SearchRequestBoundsPass(R, False, 5000, '2026-03-01T10:00:00'), 'above the maximum');
  Assert.IsFalse(SearchRequestBoundsPass(R, False, 500, '2025-12-31T23:59:59'), 'before the start date');
  Assert.IsTrue(SearchRequestBoundsPass(R, True, 0, '2026-03-01T10:00:00'), 'size bounds skip folders');
end;

end.
