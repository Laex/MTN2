unit TestSftpVfs;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSftpVfs = class
  public
    [Test] procedure TestUriParsing;
    [Test] procedure TestVfsUriIntegration;
    [Test] procedure TestLsLineParsing;
    [Test] procedure TestLsDateParsing;
    [Test] procedure TestClassifySftpFailure;
  end;

implementation

uses
  System.SysUtils, System.DateUtils,
  uVfsTypes,
  uTextEncoding,
  uSshConnections,
  uShellProfiles,
  uSftpVfs;

procedure TestUriParsing;
begin
  Assert.IsTrue(IsSftpUri('sftp://user@host/path'), 'IsSftpUri should be True for sftp://');
  Assert.IsTrue(not IsSftpUri('file:///C:/x'), 'IsSftpUri should be False for file://');
  Assert.IsTrue(not IsSftpUri('ws:///x'), 'IsSftpUri should be False for ws://');

  Assert.IsTrue(SftpAuthorityOf('sftp://bob@host.example.com:2222/a/b') = 'bob@host.example.com:2222',
    'SftpAuthorityOf mismatch');
  Assert.IsTrue(SftpRemotePathOf('sftp://bob@host.example.com:2222/a/b') = '/a/b',
    'SftpRemotePathOf mismatch');

  Assert.IsTrue(SftpAuthorityOf('sftp://host.example.com') = 'host.example.com',
    'SftpAuthorityOf (no path) mismatch');
  Assert.IsTrue(SftpRemotePathOf('sftp://host.example.com') = '/',
    'SftpRemotePathOf (no path) should default to root');

  Assert.IsTrue(MakeSftpUri('bob@host:2222', '/a/b') = 'sftp://bob@host:2222/a/b',
    'MakeSftpUri mismatch');
  Assert.IsTrue(MakeSftpUri('bob@host:2222', '') = 'sftp://bob@host:2222/',
    'MakeSftpUri should default empty path to root');
  Assert.IsTrue(MakeSftpUri('bob@host:2222', '/a/b/') = 'sftp://bob@host:2222/a/b',
    'MakeSftpUri should strip trailing slash');

  Writeln('OK: TestUriParsing passed');
end;

procedure TestVfsUriIntegration;
var
  Root, Sub, Sub2: string;
begin
  Root := 'sftp://bob@host:2222/';
  Sub := JoinVfsUri(Root, 'docs');
  Assert.IsTrue(Sub = 'sftp://bob@host:2222/docs', 'JoinVfsUri from root mismatch: ' + Sub);

  Sub2 := JoinVfsUri(Sub, 'readme.txt');
  Assert.IsTrue(Sub2 = 'sftp://bob@host:2222/docs/readme.txt', 'JoinVfsUri nested mismatch: ' + Sub2);

  Assert.IsTrue(ParentVfsUri(Sub2) = Sub, 'ParentVfsUri of nested file mismatch');
  Assert.IsTrue(ParentVfsUri(Sub) = Root, 'ParentVfsUri of top-level dir mismatch');
  Assert.IsTrue(ParentVfsUri(Root) = Root, 'ParentVfsUri of root should stay at root');

  Assert.IsTrue(VfsUriTitle(Sub2) = 'readme.txt', 'VfsUriTitle (file) mismatch');
  Assert.IsTrue(VfsUriTitle(Sub) = 'docs', 'VfsUriTitle (dir) mismatch');
  Assert.IsTrue(VfsUriTitle(Root) = 'bob@host:2222', 'VfsUriTitle (root) mismatch');

  Assert.IsTrue(SameVfsUri('sftp://bob@host:2222/docs', 'sftp://bob@host:2222/docs'),
    'SameVfsUri should match identical sftp URIs');
  Assert.IsTrue(not SameVfsUri('sftp://bob@host:2222/docs', 'sftp://bob@host:2222/other'),
    'SameVfsUri should not match different paths');
  Assert.IsTrue(not SameVfsUri('sftp://bob@hostA/docs', 'sftp://bob@hostB/docs'),
    'SameVfsUri should not match different hosts');
  Assert.IsTrue(not SameVfsUri('sftp://bob@host/docs', 'file:///C:/docs'),
    'SameVfsUri should not match across schemes');

  Assert.IsTrue(IsVfsUriNavigationRoot(Root), 'Root should be a navigation root');
  Assert.IsTrue(not IsVfsUriNavigationRoot(Sub), 'Non-root should not be a navigation root');

  Assert.IsTrue(ResolveVfsUri('sftp://bob@host:2222/docs') = 'sftp://bob@host:2222/docs',
    'ResolveVfsUri should pass sftp:// through unchanged');

  Writeln('OK: TestVfsUriIntegration passed');
end;

procedure TestLsLineParsing;
var
  E: TVfsEntry;
begin
  Assert.IsTrue(ParseSftpLsLine(
    '-rw-r--r--    1 user     group         123 Jan 15 10:23 readme.txt', E),
    'Failed to parse plain file line');
  Assert.IsTrue(E.Name = 'readme.txt', 'File name mismatch: ' + E.Name);
  Assert.IsTrue(not E.IsDirectory, 'File should not be flagged as directory');
  Assert.IsTrue(E.Size = 123, 'File size mismatch');
  Assert.IsTrue(not E.IsLink, 'Plain file should not be flagged as link');

  Assert.IsTrue(ParseSftpLsLine(
    'drwxr-xr-x    2 user     group        4096 Jan 15 10:23 sub dir with spaces', E),
    'Failed to parse directory line with spaces in name');
  Assert.IsTrue(E.Name = 'sub dir with spaces', 'Dir name with spaces mismatch: "' + E.Name + '"');
  Assert.IsTrue(E.IsDirectory, 'Should be flagged as directory');

  Assert.IsTrue(ParseSftpLsLine(
    'lrwxrwxrwx    1 user     group          11 Jan 15 10:23 link -> target', E),
    'Failed to parse symlink line');
  Assert.IsTrue(E.Name = 'link', 'Symlink name mismatch: ' + E.Name);
  Assert.IsTrue(E.IsLink, 'Should be flagged as link');

  Assert.IsTrue(ParseSftpLsLine(
    '-rw-r--r--    1 user     group      1048576 Jun  3  2019 old.bin', E),
    'Failed to parse older-than-6-months line (year form)');
  Assert.IsTrue(E.Name = 'old.bin', 'Old-file name mismatch: ' + E.Name);
  Assert.IsTrue(YearOf(E.ModificationTime) = 2019, 'Old-file year mismatch');

  Assert.IsTrue(not ParseSftpLsLine('.', E), '"." must be rejected');
  Assert.IsTrue(not ParseSftpLsLine('..', E), '".." must be rejected');
  Assert.IsTrue(not ParseSftpLsLine('', E), 'blank line must be rejected');
  Assert.IsTrue(not ParseSftpLsLine('sftp> ls -la /', E), 'non-listing line must be rejected');

  Writeln('OK: TestLsLineParsing passed');
end;

procedure TestLsDateParsing;
var
  D: TDateTime;
begin
  D := ParseSftpLsDate('Jan', '15', '10:23');
  Assert.IsTrue(MonthOf(D) = 1, 'Month mismatch (time form)');
  Assert.IsTrue(DayOf(D) = 15, 'Day mismatch (time form)');
  Assert.IsTrue(YearOf(D) = YearOf(Now), 'Year should default to current year (time form)');
  Assert.IsTrue(HourOf(D) = 10, 'Hour mismatch');
  Assert.IsTrue(MinuteOf(D) = 23, 'Minute mismatch');

  D := ParseSftpLsDate('Jun', '3', '2019');
  Assert.IsTrue(MonthOf(D) = 6, 'Month mismatch (year form)');
  Assert.IsTrue(DayOf(D) = 3, 'Day mismatch (year form)');
  Assert.IsTrue(YearOf(D) = 2019, 'Year mismatch (year form)');

  Assert.IsTrue(ParseSftpLsDate('Nope', '1', '10:00') = 0, 'Unknown month should yield 0');

  Writeln('OK: TestLsDateParsing passed');
end;

procedure TestClassifySftpFailure;
var
  E: TVfsError;
begin
  E := ClassifySftpFailure('Permission denied (publickey).', 255, False, False,
    'sftp://u@h/');
  Assert.IsTrue(E.Code = vecAccessDenied, 'publickey should be access denied');
  Assert.IsTrue(Pos('Identity', E.Message) > 0, 'publickey message should mention Identity');

  E := ClassifySftpFailure('Host key verification failed.', 255, False, False,
    'sftp://u@h/');
  Assert.IsTrue(E.Code = vecAccessDenied, 'host key should be access denied');
  Assert.IsTrue(Pos('Ctrl+Shift+N', E.Message) > 0, 'host key should point at SSH console');

  E := ClassifySftpFailure('ssh: Could not resolve hostname no-such-host', 255,
    False, False, 'sftp://no-such-host/');
  Assert.IsTrue(E.Code = vecNotFound, 'unknown host should be not found');

  E := ClassifySftpFailure('connect to host x port 22: Connection refused', 255,
    False, False, 'sftp://x/');
  Assert.IsTrue(E.Code = vecIOError, 'refused should be IO');
  Assert.IsTrue(SftpFailureIsTransient(E), 'refused is retryable');

  E := ClassifySftpFailure('Connection reset by peer', 255, False, False,
    'sftp://x/');
  Assert.IsTrue(SftpFailureIsTransient(E), 'reset is retryable');

  E := ClassifySftpFailure('', 1, True, False, 'sftp://x/');
  Assert.IsTrue(E.Code = vecIOError, 'timeout is IO');
  Assert.IsTrue(SftpFailureIsTransient(E), 'timeout is retryable');
  Assert.IsTrue(Pos('timed out', LowerCase(E.Message)) > 0, 'timeout wording');

  E := ClassifySftpFailure('', 1, False, True, 'sftp://x/');
  Assert.IsTrue(E.Code = vecCancelled, 'cancel flag');
  Assert.IsTrue(not SftpFailureIsTransient(E), 'cancel is not retryable');

  E := ClassifySftpFailure('sftp: no such file', 1, False, False, 'sftp://x/a');
  Assert.IsTrue(E.Code = vecNotFound, 'no such file');
  Assert.IsTrue(not SftpFailureIsTransient(E), 'not-found is not retryable');

  E := ClassifySftpFailure('Permission denied', 1, False, False, 'sftp://x/a');
  Assert.IsTrue(E.Code = vecAccessDenied, 'plain permission denied');
  Assert.IsTrue(E.Message = 'Permission denied', 'plain permission denied keeps raw text');

  E := ClassifySftpFailure('Permission denied (password).', 255, False, False,
    'sftp://u@h/');
  Assert.IsTrue(E.Code = vecAccessDenied, 'password prompt is auth failure');
  Assert.IsTrue(Pos('Identity', E.Message) > 0, 'password auth should mention Identity');

  E := ClassifySftpFailure('Authentication failed.', 255, False, False, 'sftp://u@h/');
  Assert.IsTrue(E.Code = vecAccessDenied, 'authentication failed is access denied');

  Writeln('OK: TestClassifySftpFailure passed');
end;

{ TTestSftpVfs }

procedure TTestSftpVfs.TestUriParsing;
begin
  TestSftpVfs.TestUriParsing;
end;

procedure TTestSftpVfs.TestVfsUriIntegration;
begin
  TestSftpVfs.TestVfsUriIntegration;
end;

procedure TTestSftpVfs.TestLsLineParsing;
begin
  TestSftpVfs.TestLsLineParsing;
end;

procedure TTestSftpVfs.TestLsDateParsing;
begin
  TestSftpVfs.TestLsDateParsing;
end;

procedure TTestSftpVfs.TestClassifySftpFailure;
begin
  TestSftpVfs.TestClassifySftpFailure;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSftpVfs);

end.
