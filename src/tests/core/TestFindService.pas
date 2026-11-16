unit TestFindService;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFindService = class
  public
    [Test] procedure TestServableOptions;
    [Test] procedure TestNeedsGrowWithTheRequest;
    [Test] procedure TestRequestCarriesTheOptions;
    [Test] procedure TestHitsAreRead;
    [Test] procedure TestOtherMessagesAreNotHits;
    [Test] procedure TestFinalResult;
    [Test] procedure TestBounds;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils, uFileFind, uFindService, uJsonRpc;

function Opts: TFindOptions;
begin
  Result := DefaultFindOptions('C:\Work', '*.pas', True);
end;

function Has(const AWords: TArray<string>; const AWord: string): Boolean;
var
  W: string;
begin
  for W in AWords do
    if W = AWord then
      Exit(True);
  Result := False;
end;

procedure TTestFindService.TestServableOptions;
var
  O: TFindOptions;
begin
  Assert.IsTrue(FindOptionsServable(Opts), 'a plain name search');
  O := Opts;
  O.HexBytes := '4D 5A';
  Assert.IsFalse(FindOptionsServable(O), 'a byte pattern');
  O := Opts;
  O.SearchArchives := True;
  Assert.IsFalse(FindOptionsServable(O), 'inside archives');
  O := Opts;
  O.RequireAttr := 1;
  Assert.IsFalse(FindOptionsServable(O), 'attribute filter');
  O := Opts;
  O.ForbidAttr := 2;
  Assert.IsFalse(FindOptionsServable(O), 'attribute filter');
  O := Opts;
  O.RootPath := 'sftp://host/dir';
  Assert.IsFalse(FindOptionsServable(O), 'not a local root');
  O := Opts;
  O.RootPath := '';
  Assert.IsFalse(FindOptionsServable(O), 'no root');
end;

procedure TTestFindService.TestNeedsGrowWithTheRequest;
var
  O: TFindOptions;
  W: TArray<string>;
begin
  W := FindServiceNeeds(Opts);
  Assert.AreEqual<Integer>(2, Length(W), 'name and mask only');
  Assert.IsTrue(Has(W, 'name') and Has(W, 'mask'));

  O := Opts;
  O.Subdirs := False;
  O.SearchFolders := True;
  W := FindServiceNeeds(O);
  Assert.IsTrue(Has(W, 'subdirs') and Has(W, 'folders'));
  Assert.IsFalse(Has(W, 'content'));

  O := Opts;
  O.ContainingText := 'x';
  O.CaseSensitive := True;
  O.WholeWords := True;
  O.UseRegex := True;
  O.ForceEncoding := True;
  W := FindServiceNeeds(O);
  Assert.IsTrue(Has(W, 'content') and Has(W, 'case') and Has(W, 'words') and
    Has(W, 'regex') and Has(W, 'encoding'));

  O := Opts;
  O.CaseSensitive := True;
  Assert.IsFalse(Has(FindServiceNeeds(O), 'case'), 'case matters for content only');
  O := Opts;
  O.MinSize := 10;
  Assert.IsFalse(Has(FindServiceNeeds(O), 'size'), 'bounds are applied by the host');
end;

procedure TTestFindService.TestRequestCarriesTheOptions;
var
  O: TFindOptions;
  Msg: TRpcMessage;
  Err: Integer;
  P: TJSONObject;
  Text: string;
  Flag: Boolean;
begin
  O := Opts;
  O.RootPath := 'C:\Work\';
  O.ContainingText := 'needle';
  O.MinSize := 100;
  O.ModifiedFrom := EncodeDateTime(2026, 1, 2, 3, 4, 5, 0);
  O.MaxResults := 7;
  O.Subdirs := False;
  Assert.IsTrue(TryParseRpcMessage(BuildSearchFilesRequest(O, 5), Msg, Err));
  Assert.IsTrue(Msg.Kind = rkRequest);
  Assert.AreEqual('search.files', Msg.Method);
  P := TJSONObject.ParseJSONValue(Msg.ParamsJson) as TJSONObject;
  try
    Assert.IsTrue(P.TryGetValue<string>('root', Text));
    Assert.AreEqual('C:\Work', Text, 'no trailing separator');
    Assert.AreEqual('*.pas', P.GetValue<string>('mask'));
    Assert.AreEqual('needle', P.GetValue<string>('text'));
    Assert.IsTrue(P.TryGetValue<Boolean>('subdirs', Flag) and not Flag);
    Assert.AreEqual<Integer>(100, P.GetValue<Integer>('minSize'));
    Assert.AreEqual<Integer>(7, P.GetValue<Integer>('maxResults'));
    Assert.AreEqual('2026-01-02T03:04:05', P.GetValue<string>('modifiedFrom'));
    Assert.IsNull(P.GetValue('maxSize'), 'an absent bound is not sent');
    Assert.IsNull(P.GetValue('encoding'));
  finally
    P.Free;
  end;
end;

procedure TTestFindService.TestHitsAreRead;
var
  Hits: TArray<TFindHit>;
begin
  Assert.IsTrue(TryParseSearchHits(
    '{"jsonrpc":"2.0","method":"search.hits","params":{"progressToken":"1","hits":[' +
    '{"path":"C:\\Work\\a.txt","isDir":false,"size":120,"modified":"2026-01-02T03:04:05"},' +
    '{"path":"C:\\Work\\sub","isDir":true},{"size":5},{"path":""},7]}}', Hits), 'parsed');
  Assert.AreEqual<Integer>(2, Length(Hits), 'entries without a path are dropped');
  Assert.AreEqual('C:\Work\a.txt', Hits[0].Path);
  Assert.AreEqual('a.txt', Hits[0].Entry.Name);
  Assert.AreEqual('.txt', Hits[0].Entry.Extension);
  Assert.AreEqual<Int64>(120, Hits[0].Entry.Size);
  Assert.IsTrue(Hits[0].HasEntry, 'has entry');
  Assert.IsTrue(Abs(Hits[0].Entry.ModificationTime - EncodeDateTime(2026, 1, 2, 3, 4, 5, 0)) < 1E-6, 'modified');
  Assert.IsTrue(Hits[1].Entry.IsDirectory, 'folder');
  Assert.AreEqual<Int64>(-1, Hits[1].Entry.Size, 'a folder has no size');
  Assert.AreEqual<Integer>(0, Hits[0].Line);
end;

procedure TTestFindService.TestOtherMessagesAreNotHits;
var
  Hits: TArray<TFindHit>;
begin
  Assert.IsFalse(TryParseSearchHits('{"jsonrpc":"2.0","method":"notifications/progress","params":{}}', Hits));
  Assert.IsFalse(TryParseSearchHits('{"jsonrpc":"2.0","method":"search.hits","params":{"hits":5}}', Hits));
  Assert.IsFalse(TryParseSearchHits('{"jsonrpc":"2.0","id":1,"result":{}}', Hits));
  Assert.IsFalse(TryParseSearchHits('nonsense', Hits));
  Assert.AreEqual<Integer>(0, Length(Hits));
end;

procedure TTestFindService.TestFinalResult;
var
  R: TSearchFilesResult;
begin
  R := ParseSearchFilesResult(
    '{"jsonrpc":"2.0","id":1,"result":{"content":[],"structuredContent":{"count":12,"truncated":true}}}');
  Assert.IsFalse(R.Failed);
  Assert.AreEqual<Integer>(12, R.Count);
  Assert.IsTrue(R.Truncated);

  R := ParseSearchFilesResult('{"jsonrpc":"2.0","id":1,"result":{}}');
  Assert.IsFalse(R.Failed);
  Assert.AreEqual<Integer>(0, R.Count);

  R := ParseSearchFilesResult('{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"not running"}}');
  Assert.IsTrue(R.Failed);
  Assert.AreEqual<Integer>(-32002, R.ErrorCode);
  Assert.AreEqual('not running', R.ErrorText);

  R := ParseSearchFilesResult('{"jsonrpc":"2.0","id":1,"result":{"isError":true}}');
  Assert.IsTrue(R.Failed, 'isError ends the search as a failure');

  Assert.IsTrue(ParseSearchFilesResult('garbage').Failed);
end;

procedure TTestFindService.TestBounds;
var
  O: TFindOptions;
  H: TFindHit;
begin
  Assert.IsFalse(FindHitNeedsBoundCheck(Opts));
  O := Opts;
  O.MinSize := 10;
  O.MaxSize := 100;
  O.ModifiedFrom := EncodeDate(2026, 1, 1);
  Assert.IsTrue(FindHitNeedsBoundCheck(O));

  H := Default(TFindHit);
  H.HasEntry := True;
  H.Entry.Size := 50;
  H.Entry.ModificationTime := EncodeDate(2026, 2, 1);
  Assert.IsTrue(FindHitWithinBounds(O, H));
  H.Entry.Size := 5;
  Assert.IsFalse(FindHitWithinBounds(O, H), 'below the size bound');
  H.Entry.Size := 500;
  Assert.IsFalse(FindHitWithinBounds(O, H), 'above the size bound');
  H.Entry.Size := 50;
  H.Entry.ModificationTime := EncodeDate(2025, 12, 31);
  Assert.IsFalse(FindHitWithinBounds(O, H), 'before the date bound');
  H.Entry.ModificationTime := 0;
  Assert.IsTrue(FindHitWithinBounds(O, H), 'no date known: passed');
  H.Entry.Size := -1;
  Assert.IsTrue(FindHitWithinBounds(O, H), 'no size known: passed');
  H.Entry.IsDirectory := True;
  H.Entry.Size := 5;
  Assert.IsTrue(FindHitWithinBounds(O, H), 'size bounds do not apply to folders');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFindService);

end.
