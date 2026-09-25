program TestSftpVfs;

uses
  System.SysUtils, System.DateUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uSshConnections in '..\..\Core\uSshConnections.pas',
  uShellProfiles in '..\..\Core\uShellProfiles.pas',
  uSftpVfs in '..\..\Core\uSftpVfs.pas';

procedure TestUriParsing;
begin
  Assert(IsSftpUri('sftp://user@host/path'), 'IsSftpUri should be True for sftp://');
  Assert(not IsSftpUri('file:///C:/x'), 'IsSftpUri should be False for file://');
  Assert(not IsSftpUri('ws:///x'), 'IsSftpUri should be False for ws://');

  Assert(SftpAuthorityOf('sftp://bob@host.example.com:2222/a/b') = 'bob@host.example.com:2222',
    'SftpAuthorityOf mismatch');
  Assert(SftpRemotePathOf('sftp://bob@host.example.com:2222/a/b') = '/a/b',
    'SftpRemotePathOf mismatch');

  Assert(SftpAuthorityOf('sftp://host.example.com') = 'host.example.com',
    'SftpAuthorityOf (no path) mismatch');
  Assert(SftpRemotePathOf('sftp://host.example.com') = '/',
    'SftpRemotePathOf (no path) should default to root');

  Assert(MakeSftpUri('bob@host:2222', '/a/b') = 'sftp://bob@host:2222/a/b',
    'MakeSftpUri mismatch');
  Assert(MakeSftpUri('bob@host:2222', '') = 'sftp://bob@host:2222/',
    'MakeSftpUri should default empty path to root');
  Assert(MakeSftpUri('bob@host:2222', '/a/b/') = 'sftp://bob@host:2222/a/b',
    'MakeSftpUri should strip trailing slash');

  Writeln('OK: TestUriParsing passed');
end;

procedure TestVfsUriIntegration;
var
  Root, Sub, Sub2: string;
begin
  Root := 'sftp://bob@host:2222/';
  Sub := JoinVfsUri(Root, 'docs');
  Assert(Sub = 'sftp://bob@host:2222/docs', 'JoinVfsUri from root mismatch: ' + Sub);

  Sub2 := JoinVfsUri(Sub, 'readme.txt');
  Assert(Sub2 = 'sftp://bob@host:2222/docs/readme.txt', 'JoinVfsUri nested mismatch: ' + Sub2);

  Assert(ParentVfsUri(Sub2) = Sub, 'ParentVfsUri of nested file mismatch');
  Assert(ParentVfsUri(Sub) = Root, 'ParentVfsUri of top-level dir mismatch');
  Assert(ParentVfsUri(Root) = Root, 'ParentVfsUri of root should stay at root');

  Assert(VfsUriTitle(Sub2) = 'readme.txt', 'VfsUriTitle (file) mismatch');
  Assert(VfsUriTitle(Sub) = 'docs', 'VfsUriTitle (dir) mismatch');
  Assert(VfsUriTitle(Root) = 'bob@host:2222', 'VfsUriTitle (root) mismatch');

  Assert(SameVfsUri('sftp://bob@host:2222/docs', 'sftp://bob@host:2222/docs'),
    'SameVfsUri should match identical sftp URIs');
  Assert(not SameVfsUri('sftp://bob@host:2222/docs', 'sftp://bob@host:2222/other'),
    'SameVfsUri should not match different paths');
  Assert(not SameVfsUri('sftp://bob@hostA/docs', 'sftp://bob@hostB/docs'),
    'SameVfsUri should not match different hosts');
  Assert(not SameVfsUri('sftp://bob@host/docs', 'file:///C:/docs'),
    'SameVfsUri should not match across schemes');

  Assert(IsVfsUriNavigationRoot(Root), 'Root should be a navigation root');
  Assert(not IsVfsUriNavigationRoot(Sub), 'Non-root should not be a navigation root');

  Assert(ResolveVfsUri('sftp://bob@host:2222/docs') = 'sftp://bob@host:2222/docs',
    'ResolveVfsUri should pass sftp:// through unchanged');

  Writeln('OK: TestVfsUriIntegration passed');
end;

procedure TestLsLineParsing;
var
  E: TVfsEntry;
begin
  Assert(ParseSftpLsLine(
    '-rw-r--r--    1 user     group         123 Jan 15 10:23 readme.txt', E),
    'Failed to parse plain file line');
  Assert(E.Name = 'readme.txt', 'File name mismatch: ' + E.Name);
  Assert(not E.IsDirectory, 'File should not be flagged as directory');
  Assert(E.Size = 123, 'File size mismatch');
  Assert(not E.IsLink, 'Plain file should not be flagged as link');

  Assert(ParseSftpLsLine(
    'drwxr-xr-x    2 user     group        4096 Jan 15 10:23 sub dir with spaces', E),
    'Failed to parse directory line with spaces in name');
  Assert(E.Name = 'sub dir with spaces', 'Dir name with spaces mismatch: "' + E.Name + '"');
  Assert(E.IsDirectory, 'Should be flagged as directory');

  Assert(ParseSftpLsLine(
    'lrwxrwxrwx    1 user     group          11 Jan 15 10:23 link -> target', E),
    'Failed to parse symlink line');
  Assert(E.Name = 'link', 'Symlink name mismatch: ' + E.Name);
  Assert(E.IsLink, 'Should be flagged as link');

  Assert(ParseSftpLsLine(
    '-rw-r--r--    1 user     group      1048576 Jun  3  2019 old.bin', E),
    'Failed to parse older-than-6-months line (year form)');
  Assert(E.Name = 'old.bin', 'Old-file name mismatch: ' + E.Name);
  Assert(YearOf(E.ModificationTime) = 2019, 'Old-file year mismatch');

  Assert(not ParseSftpLsLine('.', E), '"." must be rejected');
  Assert(not ParseSftpLsLine('..', E), '".." must be rejected');
  Assert(not ParseSftpLsLine('', E), 'blank line must be rejected');
  Assert(not ParseSftpLsLine('sftp> ls -la /', E), 'non-listing line must be rejected');

  Writeln('OK: TestLsLineParsing passed');
end;

procedure TestLsDateParsing;
var
  D: TDateTime;
begin
  D := ParseSftpLsDate('Jan', '15', '10:23');
  Assert(MonthOf(D) = 1, 'Month mismatch (time form)');
  Assert(DayOf(D) = 15, 'Day mismatch (time form)');
  Assert(YearOf(D) = YearOf(Now), 'Year should default to current year (time form)');
  Assert(HourOf(D) = 10, 'Hour mismatch');
  Assert(MinuteOf(D) = 23, 'Minute mismatch');

  D := ParseSftpLsDate('Jun', '3', '2019');
  Assert(MonthOf(D) = 6, 'Month mismatch (year form)');
  Assert(DayOf(D) = 3, 'Day mismatch (year form)');
  Assert(YearOf(D) = 2019, 'Year mismatch (year form)');

  Assert(ParseSftpLsDate('Nope', '1', '10:00') = 0, 'Unknown month should yield 0');

  Writeln('OK: TestLsDateParsing passed');
end;

procedure TestClassifySftpFailure;
var
  E: TVfsError;
begin
  E := ClassifySftpFailure('Permission denied (publickey).', 255, False, False,
    'sftp://u@h/');
  Assert(E.Code = vecAccessDenied, 'publickey should be access denied');
  Assert(Pos('Identity', E.Message) > 0, 'publickey message should mention Identity');

  E := ClassifySftpFailure('Host key verification failed.', 255, False, False,
    'sftp://u@h/');
  Assert(E.Code = vecAccessDenied, 'host key should be access denied');
  Assert(Pos('Ctrl+Shift+N', E.Message) > 0, 'host key should point at SSH console');

  E := ClassifySftpFailure('ssh: Could not resolve hostname no-such-host', 255,
    False, False, 'sftp://no-such-host/');
  Assert(E.Code = vecNotFound, 'unknown host should be not found');

  E := ClassifySftpFailure('connect to host x port 22: Connection refused', 255,
    False, False, 'sftp://x/');
  Assert(E.Code = vecIOError, 'refused should be IO');
  Assert(SftpFailureIsTransient(E), 'refused is retryable');

  E := ClassifySftpFailure('Connection reset by peer', 255, False, False,
    'sftp://x/');
  Assert(SftpFailureIsTransient(E), 'reset is retryable');

  E := ClassifySftpFailure('', 1, True, False, 'sftp://x/');
  Assert(E.Code = vecIOError, 'timeout is IO');
  Assert(SftpFailureIsTransient(E), 'timeout is retryable');
  Assert(Pos('timed out', LowerCase(E.Message)) > 0, 'timeout wording');

  E := ClassifySftpFailure('', 1, False, True, 'sftp://x/');
  Assert(E.Code = vecCancelled, 'cancel flag');
  Assert(not SftpFailureIsTransient(E), 'cancel is not retryable');

  E := ClassifySftpFailure('sftp: no such file', 1, False, False, 'sftp://x/a');
  Assert(E.Code = vecNotFound, 'no such file');
  Assert(not SftpFailureIsTransient(E), 'not-found is not retryable');

  E := ClassifySftpFailure('Permission denied', 1, False, False, 'sftp://x/a');
  Assert(E.Code = vecAccessDenied, 'plain permission denied');
  Assert(E.Message = 'Permission denied', 'plain permission denied keeps raw text');

  E := ClassifySftpFailure('Permission denied (password).', 255, False, False,
    'sftp://u@h/');
  Assert(E.Code = vecAccessDenied, 'password prompt is auth failure');
  Assert(Pos('Identity', E.Message) > 0, 'password auth should mention Identity');

  E := ClassifySftpFailure('Authentication failed.', 255, False, False, 'sftp://u@h/');
  Assert(E.Code = vecAccessDenied, 'authentication failed is access denied');

  Writeln('OK: TestClassifySftpFailure passed');
end;

begin
  try
    Writeln('Running SftpVfs tests...');
    TestUriParsing;
    TestVfsUriIntegration;
    TestLsLineParsing;
    TestLsDateParsing;
    TestClassifySftpFailure;
    Writeln('ALL SftpVfs tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
