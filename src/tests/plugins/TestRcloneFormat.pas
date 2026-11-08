unit TestRcloneFormat;

{ Addresses, command lines and parsers of the rclone plugin. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRcloneFormat = class
  public
    [Test] procedure TestRootAndRemoteRootParse;
    [Test] procedure TestPathSegmentsAreDecoded;
    [Test] procedure TestForeignSchemeIsRejected;
    [Test] procedure TestUriRoundTripsSlashesAndPercent;
    [Test] procedure TestRemoteSpecJoinsWithColon;
    [Test] procedure TestRemotesLoseTheirColon;
    [Test] procedure TestLsJsonGivesNamesSizesAndKinds;
    [Test] procedure TestNoticesBeforeTheOutputAreIgnored;
    [Test] procedure TestLsJsonSkipsGarbage;
    [Test] procedure TestStampWithNanosecondsAndOffset;
    [Test] procedure TestStatJsonReadsOneEntry;
    [Test] procedure TestAboutJsonGivesFreeAndTotal;
    [Test] procedure TestCatLimitsTheCount;
    [Test] procedure TestCopyAndMoveVerbs;
  end;

implementation

uses
  System.SysUtils, uRcloneFormat;

procedure TTestRcloneFormat.TestRootAndRemoteRootParse;
var
  A: TRcAddr;
begin
  Assert.IsTrue(ParseRcloneUri('rclone:///', A));
  Assert.AreEqual(Ord(rnRoot), Ord(A.Node));
  Assert.IsTrue(ParseRcloneUri('rclone:///gdrive', A));
  Assert.AreEqual(Ord(rnPath), Ord(A.Node));
  Assert.AreEqual('gdrive', A.Remote);
  Assert.AreEqual('', A.Path);
end;

procedure TTestRcloneFormat.TestPathSegmentsAreDecoded;
var
  A: TRcAddr;
begin
  Assert.IsTrue(ParseRcloneUri('rclone:///gdrive/Docs/a%2Fb.txt', A));
  Assert.AreEqual('Docs/a/b.txt', A.Path);
end;

procedure TTestRcloneFormat.TestForeignSchemeIsRejected;
var
  A: TRcAddr;
begin
  Assert.IsFalse(ParseRcloneUri('docker:///x', A));
  Assert.AreEqual(Ord(rnInvalid), Ord(A.Node));
end;

procedure TTestRcloneFormat.TestUriRoundTripsSlashesAndPercent;
var
  A: TRcAddr;
  Uri: string;
begin
  Uri := RcloneUri('s3', 'dir/100%.txt');
  Assert.IsTrue(ParseRcloneUri(Uri, A));
  Assert.AreEqual('s3', A.Remote);
  Assert.AreEqual('dir/100%.txt', A.Path);
  Assert.AreEqual('x%2Fy', RcEncode('x/y'));
end;

procedure TTestRcloneFormat.TestRemoteSpecJoinsWithColon;
var
  A: TRcAddr;
begin
  ParseRcloneUri('rclone:///dbx/My Files/a.txt', A);
  Assert.AreEqual('dbx:My Files/a.txt', RemoteSpec(A));
  ParseRcloneUri('rclone:///dbx', A);
  Assert.AreEqual('dbx:', RemoteSpec(A));
end;

procedure TTestRcloneFormat.TestRemotesLoseTheirColon;
var
  R: TArray<string>;
begin
  R := ParseRemotes('gdrive:' + #13#10 + 'onedrive:' + #10 + #10);
  Assert.AreEqual(2, Integer(Length(R)));
  Assert.AreEqual('gdrive', R[0]);
  Assert.AreEqual('onedrive', R[1]);
end;

procedure TTestRcloneFormat.TestLsJsonGivesNamesSizesAndKinds;
var
  E: TRcEntries;
begin
  E := ParseLsJson('[{"Path":"a","Name":"a.txt","Size":12,"ModTime":"2024-05-01T10:20:30.123456789Z","IsDir":false},' +
    '{"Path":"d","Name":"d","Size":-1,"ModTime":"2024-05-01T10:20:30Z","IsDir":true}]');
  Assert.AreEqual(2, Integer(Length(E)));
  Assert.AreEqual('a.txt', E[0].Name);
  Assert.AreEqual(Int64(12), E[0].Size);
  Assert.IsFalse(E[0].IsDir);
  Assert.IsTrue(E[1].IsDir);
  Assert.AreEqual(Int64(0), E[1].Size, 'an unknown size is not negative');
  Assert.AreEqual(Int64(1714558830), E[0].Modified);
end;

procedure TTestRcloneFormat.TestNoticesBeforeTheOutputAreIgnored;
var
  Notice: string;
  E: TRcEntries;
  Stat: TRcEntry;
begin
  Notice := '2026/11/08 23:14:57 NOTICE: gdrive: shared client_id' + #13#10;
  E := ParseLsJson(Notice + '[' + #13#10 + '{"Path":"a","Name":"a.txt","Size":1,"IsDir":false}' + #13#10 + ']');
  Assert.AreEqual(1, Integer(Length(E)));
  Assert.AreEqual('a.txt', E[0].Name);
  Assert.IsTrue(ParseStatJson(Notice + '{"Name":"x","IsDir":true}', Stat));
  Assert.AreEqual(1, Integer(Length(ParseRemotes(Notice + 'gdrive:' + #10))));
end;

procedure TTestRcloneFormat.TestLsJsonSkipsGarbage;
begin
  Assert.AreEqual(0, Integer(Length(ParseLsJson('not json'))));
  Assert.AreEqual(1, Integer(Length(ParseLsJson('[1,{"Name":"x"},{"Size":3}]'))));
end;

procedure TTestRcloneFormat.TestStampWithNanosecondsAndOffset;
begin
  Assert.AreEqual(Int64(1714558830), ParseRcTime('2024-05-01T10:20:30.999999999Z'));
  Assert.AreEqual(Int64(1714558830), ParseRcTime('2024-05-01T12:20:30+02:00'));
  Assert.AreEqual(Int64(0), ParseRcTime('yesterday'));
  Assert.AreEqual(Int64(0), ParseRcTime(''));
end;

procedure TTestRcloneFormat.TestStatJsonReadsOneEntry;
var
  E: TRcEntry;
begin
  Assert.IsTrue(ParseStatJson('{"Name":"docs","IsDir":true,"Size":-1}', E));
  Assert.IsTrue(E.IsDir);
  Assert.IsFalse(ParseStatJson('null', E));
  // The stat of a folder itself can carry an empty name.
  Assert.IsTrue(ParseStatJson('{"Path":"","Name":"","IsDir":true,"Size":-1}', E));
  Assert.IsTrue(E.IsDir);
  Assert.AreEqual(0, Integer(Length(ParseLsJson('[{"Name":"","IsDir":false}]'))));
end;

procedure TTestRcloneFormat.TestAboutJsonGivesFreeAndTotal;
var
  F, T: Int64;
begin
  Assert.IsTrue(ParseAboutJson('{"total":1000,"used":400,"free":600}', F, T));
  Assert.AreEqual(Int64(600), F);
  Assert.AreEqual(Int64(1000), T);
  Assert.IsFalse(ParseAboutJson('{"used":1}', F, T));
end;

procedure TTestRcloneFormat.TestCatLimitsTheCount;
var
  A: TRcAddr;
  Args: TArray<string>;
begin
  ParseRcloneUri('rclone:///r/f.txt', A);
  Args := CatArgs(A, 100);
  Assert.AreEqual('cat', Args[0]);
  Assert.AreEqual('--count', Args[2]);
  Assert.AreEqual('100', Args[3]);
  Assert.AreEqual('r:f.txt', Args[High(Args)]);
  Assert.AreEqual(3, Integer(Length(CatArgs(A, 0))), 'no limit, no --count');
end;

procedure TTestRcloneFormat.TestCopyAndMoveVerbs;
begin
  Assert.AreEqual('copyto', CopyToArgs('a:x', 'b:y', False)[0]);
  Assert.AreEqual('moveto', CopyToArgs('a:x', 'b:y', True)[0]);
  Assert.AreEqual('b:y', CopyToArgs('a:x', 'b:y', False)[3]);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRcloneFormat);

end.
