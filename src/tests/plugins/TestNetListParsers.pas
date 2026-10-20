unit TestNetListParsers;

{ Listings the network plugin reads from servers (uNetListParsers) and the
  address helpers it uses (uNetTypes). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNetListParsers = class
  public
    [Test] procedure TestUnixLineWithTime;
    [Test] procedure TestUnixLineWithYearAndSpacesInName;
    [Test] procedure TestUnixLineSymlinkKeepsTheLinkName;
    [Test] procedure TestUnixLineWithoutGroupColumn;
    [Test] procedure TestUnixLineIsoDate;
    [Test] procedure TestUnixLineDayBeforeMonth;
    [Test] procedure TestUnixPermissionBits;
    [Test] procedure TestUnixRecentDateInTheFutureBelongsToLastYear;
    [Test] procedure TestUnixLineRejectsJunk;
    [Test] procedure TestDosLines;
    [Test] procedure TestMlsdLine;
    [Test] procedure TestListingSkipsDotsAndTotal;
    [Test] procedure TestMlsdListing;
    [Test] procedure TestXmlTextEntitiesAndCData;
    [Test] procedure TestWebDavMultiStatus;
    [Test] procedure TestWebDavAbsoluteHrefAndEncodedNames;
    [Test] procedure TestWebDavQuota;
    [Test] procedure TestS3Buckets;
    [Test] procedure TestS3ObjectsWithPrefix;
    [Test] procedure TestS3Truncated;
    [Test] procedure TestDates;
  end;

  [TestFixture]
  TTestNetTypes = class
  public
    [Test] procedure TestParseNetUri;
    [Test] procedure TestParseDirectUri;
    [Test] procedure TestAuthority;
    [Test] procedure TestPosixHelpers;
    [Test] procedure TestUrlEncoding;
    [Test] procedure TestProtocolSchemes;
  end;

implementation

uses
  System.SysUtils, System.DateUtils, uNetTypes, uNetListParsers;

var
  GNow: TDateTime;

function Unix(AYear, AMonth, ADay, AHour, AMinute: Integer): Int64;
begin
  Result := DateTimeToUnix(EncodeDateTime(AYear, AMonth, ADay, AHour, AMinute, 0, 0), False);
end;

function UnixUtc(AYear, AMonth, ADay, AHour, AMinute, ASecond: Integer): Int64;
begin
  Result := DateTimeToUnix(EncodeDateTime(AYear, AMonth, ADay, AHour, AMinute, ASecond, 0), True);
end;

procedure TTestNetListParsers.TestUnixLineWithTime;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('-rw-r--r--    1 ftp      ftp          1234 Oct 05 12:30 readme.txt', GNow, E));
  Assert.AreEqual('readme.txt', E.Name);
  Assert.IsTrue(E.Size = 1234);
  Assert.IsFalse(E.IsDir);
  Assert.IsTrue(E.Modified = Unix(2026, 10, 5, 12, 30), 'the digits as printed');
end;

procedure TTestNetListParsers.TestUnixLineWithYearAndSpacesInName;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('drwxr-xr-x   2 root     root         4096 Jan  3  2019 My  Docs', GNow, E));
  Assert.AreEqual('My  Docs', E.Name, 'inner blanks stay');
  Assert.IsTrue(E.IsDir);
  Assert.IsTrue(E.Modified = Unix(2019, 1, 3, 0, 0));
end;

procedure TTestNetListParsers.TestUnixLineSymlinkKeepsTheLinkName;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('lrwxrwxrwx   1 root root 7 Mar 11 10:00 current -> releases/v2', GNow, E));
  Assert.AreEqual('current', E.Name);
  Assert.IsTrue(E.IsLink);
  Assert.IsFalse(E.IsDir);
end;

procedure TTestNetListParsers.TestUnixLineWithoutGroupColumn;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('-rw-r--r-- 1 owner 55 Feb 02 09:15 notes.md', GNow, E));
  Assert.AreEqual('notes.md', E.Name);
  Assert.IsTrue(E.Size = 55);
end;

procedure TTestNetListParsers.TestUnixLineIsoDate;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('-rw-r--r-- 1 u g 99 2025-12-24 18:45 xmas.txt', GNow, E));
  Assert.AreEqual('xmas.txt', E.Name);
  Assert.IsTrue(E.Size = 99);
  Assert.IsTrue(E.Modified = Unix(2025, 12, 24, 18, 45));
end;

procedure TTestNetListParsers.TestUnixLineDayBeforeMonth;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('-rw-r--r--   1 0        0               3 05 Oct 12:30 a b.txt', GNow, E));
  Assert.AreEqual('a b.txt', E.Name);
  Assert.IsTrue(E.Size = 3);
  Assert.IsTrue(E.Modified = Unix(2026, 10, 5, 12, 30));
end;

procedure TTestNetListParsers.TestUnixPermissionBits;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsTrue(ParseUnixListLine('-rwxr-xr-x 1 u g 1 Jan 1 2020 run', GNow, E));
  Assert.IsTrue(E.Mode = 493, 'octal 755');
  Assert.IsTrue(ParseUnixListLine('-rwsr-xr-x 1 u g 1 Jan 1 2020 su', GNow, E));
  Assert.IsTrue(E.Mode = (493 or $800), 'setuid');
  Assert.IsTrue(ParseUnixListLine('drwxrwxrwt 1 u g 1 Jan 1 2020 tmp', GNow, E));
  Assert.IsTrue(E.Mode = (511 or $200), 'sticky');
  Assert.AreEqual('rwxr-xr-x', FormatUnixMode(493));
end;

procedure TTestNetListParsers.TestUnixRecentDateInTheFutureBelongsToLastYear;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 1, 10);
  Assert.IsTrue(ParseUnixListLine('-rw-r--r-- 1 u g 1 Dec 30 22:00 old', GNow, E));
  Assert.IsTrue(E.Modified = Unix(2025, 12, 30, 22, 0), 'December seen in January is last year');
end;

procedure TTestNetListParsers.TestUnixLineRejectsJunk;
var
  E: TNetEntry;
begin
  GNow := EncodeDate(2026, 10, 20);
  Assert.IsFalse(ParseUnixListLine('total 48', GNow, E));
  Assert.IsFalse(ParseUnixListLine('', GNow, E));
  Assert.IsFalse(ParseUnixListLine('226 Transfer complete', GNow, E));
  Assert.IsFalse(ParseUnixListLine('drwxr-xr-x 2 root root 4096 Jan 3 2019 .', GNow, E), 'dot entry');
  Assert.IsFalse(ParseUnixListLine('drwxr-xr-x 2 root root 4096 Jan 3 2019 ..', GNow, E), 'dotdot entry');
end;

procedure TTestNetListParsers.TestDosLines;
var
  E: TNetEntry;
begin
  Assert.IsTrue(ParseDosListLine('10-05-24  02:30PM       <DIR>          Projects', E));
  Assert.AreEqual('Projects', E.Name);
  Assert.IsTrue(E.IsDir);
  Assert.IsTrue(E.Modified = Unix(2024, 10, 5, 14, 30), 'PM is added');
  Assert.IsTrue(ParseDosListLine('01-02-2020 12:05 AM 1,234 report final.doc', E));
  Assert.AreEqual('report final.doc', E.Name);
  Assert.IsTrue(E.Size = 1234);
  Assert.IsTrue(E.Modified = Unix(2020, 1, 2, 0, 5), '12 AM is midnight');
  Assert.IsFalse(ParseDosListLine('drwxr-xr-x 2 u g 1 Jan 1 2020 x', E));
end;

procedure TTestNetListParsers.TestMlsdLine;
var
  E: TNetEntry;
begin
  Assert.IsTrue(ParseMlsdLine('type=file;size=2048;modify=20240105123000;unix.mode=0644; data file.bin', E));
  Assert.AreEqual('data file.bin', E.Name);
  Assert.IsTrue(E.Size = 2048);
  Assert.IsTrue(E.Mode = 420, 'octal 644');
  Assert.IsTrue(E.Modified = UnixUtc(2024, 1, 5, 12, 30, 0), 'MLSD times are UTC');
  Assert.IsTrue(ParseMlsdLine('type=dir;modify=20240105123000; sub', E));
  Assert.IsTrue(E.IsDir);
  Assert.IsFalse(ParseMlsdLine('type=cdir;modify=20240105123000; .', E));
  Assert.IsFalse(ParseMlsdLine('type=pdir;modify=20240105123000; ..', E));
  Assert.IsTrue(ParseMlsdLine('type=OS.unix=symlink;size=4; link', E));
  Assert.IsTrue(E.IsLink);
end;

procedure TTestNetListParsers.TestListingSkipsDotsAndTotal;
var
  Items: TNetEntries;
begin
  GNow := EncodeDate(2026, 10, 20);
  Items := ParseFtpListing(
    'total 12'#13#10 +
    'drwxr-xr-x 2 u g 4096 Jan 1 2020 .'#13#10 +
    'drwxr-xr-x 2 u g 4096 Jan 1 2020 ..'#13#10 +
    'drwxr-xr-x 2 u g 4096 Jan 1 2020 docs'#13#10 +
    '-rw-r--r-- 1 u g 5 Jan 1 2020 a.txt'#13#10, 0, GNow);
  Assert.IsTrue(Length(Items) = 2);
  Assert.AreEqual('docs', Items[0].Name);
  Assert.AreEqual('a.txt', Items[1].Name);
end;

procedure TTestNetListParsers.TestMlsdListing;
var
  Items: TNetEntries;
begin
  Items := ParseFtpListing(
    'type=cdir;modify=20240101000000; .'#13#10 +
    'type=dir;modify=20240101000000; sub'#13#10 +
    'type=file;size=10;modify=20240102000000; f.txt'#13#10, 1, Now);
  Assert.IsTrue(Length(Items) = 2);
  Assert.IsTrue(Items[0].IsDir and (Items[0].Name = 'sub'));
  Assert.IsTrue(Items[1].Size = 10);
end;

procedure TTestNetListParsers.TestXmlTextEntitiesAndCData;
var
  Root: TXmlNode;
begin
  Root := ParseXml('<?xml version="1.0"?><a:root xmlns:a="x"><a:item>R&amp;D &lt;1&gt; &#233;</a:item>' +
    '<item2><![CDATA[<raw>]]></item2><empty/><!-- c --></a:root>');
  try
    Assert.IsTrue(Root <> nil);
    Assert.AreEqual('R&D <1> ' + Char(233), Root.ChildText('item'));
    Assert.AreEqual('<raw>', Root.ChildText('item2'));
    Assert.IsTrue(Root.Find('empty') <> nil);
  finally
    Root.Free;
  end;
  Assert.IsTrue(ParseXml('not xml') = nil);
  Assert.IsTrue(ParseXml('<a><b>') <> nil, 'an unclosed tag is tolerated');
end;

procedure TTestNetListParsers.TestWebDavMultiStatus;
const
  cXml =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<D:multistatus xmlns:D="DAV:">' +
    '<D:response><D:href>/dav/docs/</D:href><D:propstat><D:prop>' +
    '<D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>' +
    '<D:response><D:href>/dav/docs/sub/</D:href><D:propstat><D:prop>' +
    '<D:resourcetype><D:collection/></D:resourcetype>' +
    '<D:getlastmodified>Tue, 05 Mar 2024 10:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response>' +
    '<D:response><D:href>/dav/docs/a.txt</D:href><D:propstat><D:prop>' +
    '<D:resourcetype/><D:getcontentlength>321</D:getcontentlength>' +
    '<D:getlastmodified>Tue, 05 Mar 2024 10:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response>' +
    '</D:multistatus>';
var
  Items: TNetEntries;
begin
  Items := ParseWebDavMultiStatus(cXml, '/dav/docs');
  Assert.IsTrue(Length(Items) = 2, 'the listed folder itself is left out');
  Assert.AreEqual('sub', Items[0].Name);
  Assert.IsTrue(Items[0].IsDir);
  Assert.AreEqual('a.txt', Items[1].Name);
  Assert.IsTrue(Items[1].Size = 321);
  Assert.IsTrue(Items[1].Modified = UnixUtc(2024, 3, 5, 10, 0, 0));
end;

procedure TTestNetListParsers.TestWebDavAbsoluteHrefAndEncodedNames;
const
  cXml =
    '<multistatus xmlns="DAV:">' +
    '<response><href>http://srv:8080/dav/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response>' +
    '<response><href>http://srv:8080/dav/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20mir.txt</href>' +
    '<propstat><prop><getcontentlength>7</getcontentlength></prop></propstat></response>' +
    '</multistatus>';
var
  Items: TNetEntries;
begin
  Items := ParseWebDavMultiStatus(cXml, '/dav');
  Assert.IsTrue(Length(Items) = 1);
  Assert.AreEqual(#$043F#$0440#$0438#$0432#$0435#$0442' mir.txt', Items[0].Name);
end;

procedure TTestNetListParsers.TestWebDavQuota;
var
  Free, Used: Int64;
begin
  ParseWebDavQuota('<multistatus xmlns="DAV:"><response><propstat><prop>' +
    '<quota-available-bytes>1000</quota-available-bytes>' +
    '<quota-used-bytes>24</quota-used-bytes></prop></propstat></response></multistatus>', Free, Used);
  Assert.IsTrue((Free = 1000) and (Used = 24));
  ParseWebDavQuota('<multistatus/>', Free, Used);
  Assert.IsTrue((Free = -1) and (Used = -1));
end;

procedure TTestNetListParsers.TestS3Buckets;
var
  Items: TNetEntries;
begin
  Items := ParseS3Buckets('<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
    '<Owner><ID>x</ID></Owner><Buckets>' +
    '<Bucket><Name>photos</Name><CreationDate>2023-04-01T08:30:00.000Z</CreationDate></Bucket>' +
    '<Bucket><Name>backups</Name><CreationDate>2022-01-01T00:00:00.000Z</CreationDate></Bucket>' +
    '</Buckets></ListAllMyBucketsResult>');
  Assert.IsTrue(Length(Items) = 2);
  Assert.AreEqual('photos', Items[0].Name);
  Assert.IsTrue(Items[0].IsDir);
  Assert.IsTrue(Items[0].Modified = UnixUtc(2023, 4, 1, 8, 30, 0));
end;

procedure TTestNetListParsers.TestS3ObjectsWithPrefix;
var
  Items: TNetEntries;
  Truncated: Boolean;
  Token: string;
begin
  Items := ParseS3Objects('<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
    '<Name>b</Name><Prefix>docs/</Prefix><IsTruncated>false</IsTruncated>' +
    '<Contents><Key>docs/</Key><Size>0</Size></Contents>' +
    '<Contents><Key>docs/a.txt</Key><Size>12</Size><LastModified>2024-02-03T04:05:06.000Z</LastModified></Contents>' +
    '<CommonPrefixes><Prefix>docs/2024/</Prefix></CommonPrefixes>' +
    '</ListBucketResult>', 'docs/', Truncated, Token);
  Assert.IsFalse(Truncated);
  Assert.IsTrue(Length(Items) = 2, 'the folder marker object is left out');
  Assert.AreEqual('2024', Items[0].Name);
  Assert.IsTrue(Items[0].IsDir);
  Assert.AreEqual('a.txt', Items[1].Name);
  Assert.IsTrue(Items[1].Size = 12);
  Assert.IsTrue(Items[1].Modified = UnixUtc(2024, 2, 3, 4, 5, 6));
end;

procedure TTestNetListParsers.TestS3Truncated;
var
  Items: TNetEntries;
  Truncated: Boolean;
  Token: string;
begin
  Items := ParseS3Objects('<ListBucketResult><IsTruncated>true</IsTruncated>' +
    '<NextContinuationToken>abc==</NextContinuationToken>' +
    '<Contents><Key>x</Key><Size>1</Size></Contents></ListBucketResult>', '', Truncated, Token);
  Assert.IsTrue(Truncated);
  Assert.AreEqual('abc==', Token);
  Assert.IsTrue(Length(Items) = 1);
end;

procedure TTestNetListParsers.TestDates;
begin
  Assert.IsTrue(ParseHttpDate('Tue, 05 Mar 2024 10:00:00 GMT') = UnixUtc(2024, 3, 5, 10, 0, 0));
  Assert.IsTrue(ParseHttpDate('garbage') = 0);
  Assert.IsTrue(ParseIso8601('2024-03-05T10:00:00Z') = UnixUtc(2024, 3, 5, 10, 0, 0));
  Assert.IsTrue(ParseIso8601('2024-03-05') = UnixUtc(2024, 3, 5, 0, 0, 0));
  Assert.IsTrue(ParseMlsdTime('20240305100000.123') = UnixUtc(2024, 3, 5, 10, 0, 0));
  Assert.IsTrue(ParseMlsdTime('2024') = 0);
end;

{ TTestNetTypes }

procedure TTestNetTypes.TestParseNetUri;
var
  T: TNetTarget;
begin
  Assert.IsTrue(ParseNetUri('net:///', T));
  Assert.IsTrue(T.IsSessionList);
  Assert.IsFalse(T.IsDirect);
  Assert.IsTrue(ParseNetUri('NET://Work Box/a/b//c/', T));
  Assert.AreEqual('net', T.Scheme);
  Assert.AreEqual('Work Box', T.Authority);
  Assert.AreEqual('/a/b/c', T.Path);
  Assert.IsFalse(ParseNetUri('file:///C:/x', T));
  Assert.IsFalse(ParseNetUri('nothing', T));
end;

procedure TTestNetTypes.TestParseDirectUri;
var
  T: TNetTarget;
begin
  Assert.IsTrue(ParseNetUri('ftp://bob@host:2121/pub', T));
  Assert.IsTrue(T.IsDirect);
  Assert.AreEqual('bob@host:2121', T.Authority);
  Assert.AreEqual('/pub', T.Path);
  Assert.IsTrue(ParseNetUri('s3://bucket', T));
  Assert.AreEqual('/', T.Path);
  Assert.IsTrue(ParseNetUri('nsftp://h/x', T));
end;

procedure TTestNetTypes.TestAuthority;
var
  U, P, H: string;
  Port: Integer;
begin
  Assert.IsTrue(ParseNetAuthority('alice:p%40ss@example.org:2222', U, P, H, Port));
  Assert.AreEqual('alice', U);
  Assert.AreEqual('p@ss', P);
  Assert.AreEqual('example.org', H);
  Assert.AreEqual(2222, Port);
  Assert.IsTrue(ParseNetAuthority('host', U, P, H, Port));
  Assert.AreEqual('', U);
  Assert.AreEqual(0, Port);
  Assert.IsTrue(ParseNetAuthority('u@[::1]:21', U, P, H, Port));
  Assert.AreEqual('::1', H);
  Assert.AreEqual(21, Port);
  Assert.IsFalse(ParseNetAuthority('host:abc', U, P, H, Port));
  Assert.IsFalse(ParseNetAuthority('', U, P, H, Port));
end;

procedure TTestNetTypes.TestPosixHelpers;
begin
  Assert.AreEqual('/', PosixNormalize(''));
  Assert.AreEqual('/a/b', PosixNormalize('a//b/./'));
  Assert.AreEqual('/a/b', PosixJoin('/a', 'b'));
  Assert.AreEqual('/b', PosixJoin('/', '/b'));
  Assert.AreEqual('/a', PosixParent('/a/b'));
  Assert.AreEqual('/', PosixParent('/a'));
  Assert.AreEqual('/', PosixParent('/'));
  Assert.AreEqual('b', PosixLastSegment('/a/b/'));
  Assert.AreEqual('', PosixLastSegment('/'));
end;

procedure TTestNetTypes.TestUrlEncoding;
begin
  Assert.AreEqual('/a%20b/%D1%84.txt', UrlEncodePath('/a b/' + #$0444 + '.txt'));
  Assert.AreEqual('a%2Fb%3F', UrlEncodeComponent('a/b?'));
  Assert.AreEqual('/a b/' + #$0444, UrlDecode('/a%20b/%D1%84'));
  Assert.AreEqual('100%', UrlDecode('100%'), 'a lone percent stays');
end;

procedure TTestNetTypes.TestProtocolSchemes;
var
  P: TNetProtocol;
begin
  Assert.IsTrue(NetSchemeProtocol('FTPS', P) and (P = npFtps));
  Assert.IsTrue(NetSchemeProtocol('nsftp', P) and (P = npSftp));
  Assert.IsTrue(NetSchemeProtocol('davs', P) and (P = npWebDavs));
  Assert.IsFalse(NetSchemeProtocol('sftp', P), 'sftp stays with the built-in provider');
  Assert.AreEqual(990, NetDefaultPort(npFtps, True));
  Assert.AreEqual(21, NetDefaultPort(npFtps, False));
  Assert.AreEqual(443, NetDefaultPort(npS3));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetListParsers);
  TDUnitX.RegisterTestFixture(TTestNetTypes);

end.
