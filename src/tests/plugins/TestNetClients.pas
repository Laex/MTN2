unit TestNetClients;

{ The network clients (uNetClient, uNetClientHttp) against real servers run
  locally: FTP, FTPS and SFTP here, WebDAV and S3 in TestNetClientsHttp.
  The tests need the environment described in uNetTestServers.pas and report a
  skip without it. }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, uNetTypes, uNetClient,
  uNetTestServers;

type
  TNetServerFixture = class
  protected
    FSkipReason: string;
    FRoot: string;
    FWork: string;
    FServer: TNetTestServer;
    procedure StartServer; virtual; abstract;
    function MakeSession: TNetSession; virtual; abstract;
    function BasePath: string; virtual;
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
  end;

  [TestFixture]
  TTestNetFtp = class(TNetServerFixture)
  protected
    procedure StartServer; override;
    function MakeSession: TNetSession; override;
  public
    [Test] procedure TestListRootShowsFilesAndFolders;
    [Test] procedure TestListMissingFolderIsNotFound;
    [Test] procedure TestStatTellsFilesFoldersAndMissing;
    [Test] procedure TestDownloadFile;
    [Test] procedure TestUploadAndReadBackBinary;
    [Test] procedure TestUnicodeAndSpacesInNames;
    [Test] procedure TestMakeDirsRenameAndRemoveTree;
    [Test] procedure TestOverwriteFlag;
    [Test] procedure TestCancelStopsTheTransfer;
    [Test] procedure TestWrongPasswordIsAnAuthFailure;
    [Test] procedure TestSmallReadAndWrite;
    [Test] procedure TestAnonymousLoginReadsButCannotWrite;
  end;

  [TestFixture]
  TTestNetFtps = class(TNetServerFixture)
  protected
    procedure StartServer; override;
    function MakeSession: TNetSession; override;
  public
    [Test] procedure TestExplicitTlsListsAndTransfers;
  end;

  [TestFixture]
  TTestNetSftp = class(TNetServerFixture)
  private
    FFingerprint: string;
  protected
    procedure StartServer; override;
    function MakeSession: TNetSession; override;
  public
    [Test] procedure TestUnknownHostKeyIsReportedWithItsFingerprint;
    [Test] procedure TestChangedHostKeyIsRefused;
    [Test] procedure TestListRootShowsFilesAndFolders;
    [Test] procedure TestListMissingFolderIsNotFound;
    [Test] procedure TestStatTellsFilesFoldersAndMissing;
    [Test] procedure TestDownloadFile;
    [Test] procedure TestUploadAndReadBackBinary;
    [Test] procedure TestUnicodeAndSpacesInNames;
    [Test] procedure TestMakeDirsRenameAndRemoveTree;
    [Test] procedure TestOverwriteFlag;
    [Test] procedure TestCancelStopsTheTransfer;
    [Test] procedure TestWrongPasswordIsAnAuthFailure;
    [Test] procedure TestSmallReadAndWrite;
    [Test] procedure TestKeyFileLogin;
    [Test] procedure TestScpTransfersFileData;
  end;

/// <summary>Checks shared by every protocol; ABase is the folder holding the
/// served tree (hello.txt, docs\a.txt, empty\).</summary>
procedure CheckListRoot(AClient: TNetClient; const ABase: string);
procedure CheckListMissing(AClient: TNetClient; const ABase: string);
procedure CheckStat(AClient: TNetClient; const ABase: string);
procedure CheckDownload(AClient: TNetClient; const ABase, AWork: string);
procedure CheckUploadBinary(AClient: TNetClient; const ABase, AWork: string);
procedure CheckUnicodeNames(AClient: TNetClient; const ABase, AWork: string);
procedure CheckDirsRenameRemove(AClient: TNetClient; const ABase: string);
procedure CheckOverwriteFlag(AClient: TNetClient; const ABase, AWork: string);
procedure CheckCancel(AClient: TNetClient; const ABase, AWork: string);
procedure CheckSmallReadWrite(AClient: TNetClient; const ABase: string);

implementation

uses
  System.IOUtils, System.Hash, System.Generics.Collections, uNetCurlApi;

function NewOp: TNetOp;
begin
  Result := TNetOp.Create;
end;

function Find(const AItems: TNetEntries; const AName: string; out AEntry: TNetEntry): Boolean;
var
  E: TNetEntry;
begin
  for E in AItems do
    if E.Name = AName then
    begin
      AEntry := E;
      Exit(True);
    end;
  AEntry := Default(TNetEntry);
  Result := False;
end;

function RandomFile(const APath: string; ASize: Integer): string;
var
  Bytes: TBytes;
  I: Integer;
begin
  SetLength(Bytes, ASize);
  RandSeed := 12345;
  for I := 0 to ASize - 1 do
    Bytes[I] := Random(256);
  TFile.WriteAllBytes(APath, Bytes);
  Result := APath;
end;

function FileHash(const APath: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(APath);
end;

procedure CheckListRoot(AClient: TNetClient; const ABase: string);
var
  Items: TNetEntries;
  Op: TNetOp;
  E: TNetEntry;
begin
  Op := NewOp;
  try
    Assert.IsTrue(AClient.ListDir(ABase, Op, Items) = nrOk, 'listing: ' + Op.ErrorText);
    Assert.IsTrue(Find(Items, 'hello.txt', E), 'hello.txt is listed');
    Assert.IsFalse(E.IsDir);
    Assert.IsTrue(E.Size = Length(TestFixtureText), 'size of hello.txt: ' + IntToStr(E.Size));
    Assert.IsTrue(Find(Items, 'docs', E) and E.IsDir, 'docs is a folder');
    Assert.IsTrue(Find(Items, 'empty', E) and E.IsDir, 'empty is a folder');
    Assert.IsFalse(Find(Items, '.', E) or Find(Items, '..', E), 'no dot entries');
    Assert.IsTrue(AClient.ListDir(PosixJoin(ABase, 'docs'), Op, Items) = nrOk);
    Assert.IsTrue(Length(Items) = 1);
    Assert.AreEqual('a.txt', Items[0].Name);
    Assert.IsTrue(AClient.ListDir(PosixJoin(ABase, 'empty'), Op, Items) = nrOk);
    Assert.IsTrue(Length(Items) = 0, 'an empty folder lists nothing');
  finally
    Op.Free;
  end;
end;

procedure CheckListMissing(AClient: TNetClient; const ABase: string);
var
  Items: TNetEntries;
  Op: TNetOp;
  R: TNetResult;
begin
  Op := NewOp;
  try
    R := AClient.ListDir(PosixJoin(ABase, 'no-such-folder'), Op, Items);
    Assert.IsTrue(R in [nrNotFound, nrAccessDenied], 'missing folder is not found: ' + IntToStr(Ord(R)) + ' ' + Op.ErrorText);
  finally
    Op.Free;
  end;
end;

procedure CheckStat(AClient: TNetClient; const ABase: string);
var
  Op: TNetOp;
  E: TNetEntry;
begin
  Op := NewOp;
  try
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'hello.txt'), Op, E) = nrOk);
    Assert.IsFalse(E.IsDir);
    Assert.IsTrue(E.Size = Length(TestFixtureText));
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'docs'), Op, E) = nrOk);
    Assert.IsTrue(E.IsDir);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'missing.bin'), Op, E) = nrNotFound);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'docs/a.txt'), Op, E) = nrOk);
  finally
    Op.Free;
  end;
end;

procedure CheckDownload(AClient: TNetClient; const ABase, AWork: string);
var
  Op: TNetOp;
  Target: string;
  Seen: Boolean;
begin
  Op := NewOp;
  try
    Seen := False;
    Op.Progress := procedure(ADone, ATotal: Int64; AName: string)
      begin
        Seen := True;
      end;
    Target := TPath.Combine(AWork, 'got-hello.txt');
    Assert.IsTrue(AClient.Download(PosixJoin(ABase, 'hello.txt'), Target, Op, False) = nrOk,
      'download: ' + Op.ErrorText);
    Assert.AreEqual(TestFixtureText, TFile.ReadAllText(Target, TEncoding.ASCII));
    Assert.IsFalse(FileExists(Target + '.mtnpart'), 'no partial file stays');
    Assert.IsTrue(Seen, 'progress was reported');
    Assert.IsTrue(AClient.Download(PosixJoin(ABase, 'missing.bin'), TPath.Combine(AWork, 'x.bin'), Op, False) =
      nrNotFound, 'a missing file is not found');
    Assert.IsFalse(FileExists(TPath.Combine(AWork, 'x.bin')), 'nothing is left of a failed download');
  finally
    Op.Free;
  end;
end;

procedure CheckUploadBinary(AClient: TNetClient; const ABase, AWork: string);
var
  Op: TNetOp;
  Src, Back: string;
  E: TNetEntry;
begin
  Op := NewOp;
  try
    Src := RandomFile(TPath.Combine(AWork, 'big.bin'), 3 * 1024 * 1024 + 17);
    Assert.IsTrue(AClient.MakeDirs(PosixJoin(ABase, 'up'), Op) = nrOk, 'make folder: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'up/big.bin'), Op, True) = nrOk,
      'upload: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'up/big.bin'), Op, E) = nrOk);
    Assert.IsTrue(E.Size = 3 * 1024 * 1024 + 17, 'size on the server: ' + IntToStr(E.Size));
    Back := TPath.Combine(AWork, 'big-back.bin');
    Assert.IsTrue(AClient.Download(PosixJoin(ABase, 'up/big.bin'), Back, Op, False) = nrOk,
      'download back: ' + Op.ErrorText);
    Assert.AreEqual(FileHash(Src), FileHash(Back), 'the bytes survive the round trip');
    AClient.RemoveTree(PosixJoin(ABase, 'up'), True, Op);
  finally
    Op.Free;
  end;
end;

procedure CheckUnicodeNames(AClient: TNetClient; const ABase, AWork: string);
var
  Op: TNetOp;
  Name, Src, Back: string;
  Items: TNetEntries;
  E: TNetEntry;
begin
  Op := NewOp;
  try
    Name := #$0442#$0435#$0441#$0442' '#$0444#$0430#$0439#$043B' #1.txt';
    Src := TPath.Combine(AWork, 'uni.txt');
    TFile.WriteAllText(Src, 'content', TEncoding.UTF8);
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, Name), Op, True) = nrOk, 'upload: ' + Op.ErrorText);
    Assert.IsTrue(AClient.ListDir(ABase, Op, Items) = nrOk);
    Assert.IsTrue(Find(Items, Name, E), 'the name comes back as written');
    Back := TPath.Combine(AWork, 'uni-back.txt');
    Assert.IsTrue(AClient.Download(PosixJoin(ABase, Name), Back, Op, False) = nrOk, 'download: ' + Op.ErrorText);
    Assert.AreEqual('content', TFile.ReadAllText(Back, TEncoding.UTF8));
    Assert.IsTrue(AClient.RemoveFile(PosixJoin(ABase, Name), Op) = nrOk, 'remove: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, Name), Op, E) = nrNotFound);
  finally
    Op.Free;
  end;
end;

procedure CheckDirsRenameRemove(AClient: TNetClient; const ABase: string);
var
  Op: TNetOp;
  E: TNetEntry;
  Src: string;
begin
  Op := NewOp;
  try
    Assert.IsTrue(AClient.MakeDirs(PosixJoin(ABase, 'tree/one/two'), Op) = nrOk, 'make folders: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'tree/one/two'), Op, E) = nrOk);
    Assert.IsTrue(E.IsDir);
    Src := TPath.Combine(TPath.GetTempPath, 'mtn2-net-rn.txt');
    TFile.WriteAllText(Src, 'rename me');
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'tree/one/two/f.txt'), Op, True) = nrOk,
      'upload: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Rename(PosixJoin(ABase, 'tree/one/two/f.txt'), PosixJoin(ABase, 'tree/one/g.txt'),
      True, Op) = nrOk, 'rename: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'tree/one/two/f.txt'), Op, E) = nrNotFound, 'old name gone');
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'tree/one/g.txt'), Op, E) = nrOk, 'new name there');
    Assert.IsTrue(AClient.RemoveTree(PosixJoin(ABase, 'tree'), True, Op) = nrOk, 'remove tree: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Stat(PosixJoin(ABase, 'tree'), Op, E) = nrNotFound, 'the tree is gone');
    TFile.Delete(Src);
  finally
    Op.Free;
  end;
end;

procedure CheckOverwriteFlag(AClient: TNetClient; const ABase, AWork: string);
var
  Op: TNetOp;
  Src: string;
begin
  Op := NewOp;
  try
    Src := TPath.Combine(AWork, 'ow.txt');
    TFile.WriteAllText(Src, 'one');
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'ow.txt'), Op, False) = nrOk, 'first upload: ' + Op.ErrorText);
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'ow.txt'), Op, False) = nrAlreadyExists,
      'without overwrite the second upload is refused');
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'ow.txt'), Op, True) = nrOk, 'with overwrite it passes');
    AClient.RemoveFile(PosixJoin(ABase, 'ow.txt'), Op);
  finally
    Op.Free;
  end;
end;

procedure CheckCancel(AClient: TNetClient; const ABase, AWork: string);
var
  Op: TNetOp;
  Src: string;
  Calls: Integer;
  E: TNetEntry;
begin
  Op := NewOp;
  try
    Src := RandomFile(TPath.Combine(AWork, 'cancel.bin'), 12 * 1024 * 1024);
    Calls := 0;
    Op.Progress := procedure(ADone, ATotal: Int64; AName: string)
      begin
        Inc(Calls);
      end;
    Op.Cancelled := function: Boolean
      begin
        Result := Calls > 0;
      end;
    Assert.IsTrue(AClient.Upload(Src, PosixJoin(ABase, 'cancel.bin'), Op, True) = nrCancelled,
      'the upload was cancelled: ' + Op.ErrorText);
    AClient.RemoveFile(PosixJoin(ABase, 'cancel.bin'), nil);
    Op.Cancelled := nil;
    AClient.Stat(PosixJoin(ABase, 'cancel.bin'), nil, E);
  finally
    Op.Free;
  end;
end;

procedure CheckSmallReadWrite(AClient: TNetClient; const ABase: string);
var
  Op: TNetOp;
  Data: TBytes;
begin
  Op := NewOp;
  try
    Assert.IsTrue(AClient.WriteBytes(PosixJoin(ABase, 'small.txt'), TEncoding.UTF8.GetBytes('abc'), Op, True) = nrOk,
      'write: ' + Op.ErrorText);
    Assert.IsTrue(AClient.ReadBytes(PosixJoin(ABase, 'small.txt'), 1024, Op, Data) = nrOk, 'read: ' + Op.ErrorText);
    Assert.AreEqual('abc', TEncoding.UTF8.GetString(Data));
    Assert.IsTrue(AClient.ReadBytes(PosixJoin(ABase, 'small.txt'), 2, Op, Data) <> nrOk, 'the cap is honoured');
    AClient.RemoveFile(PosixJoin(ABase, 'small.txt'), Op);
  finally
    Op.Free;
  end;
end;

{ TNetServerFixture }

function TNetServerFixture.BasePath: string;
begin
  Result := '/';
end;

procedure TNetServerFixture.SetupFixture;
var
  Err: string;
begin
  FSkipReason := NetTestUnavailable;
  if FSkipReason = '' then
    if not NetTestLoadCurl(Err) then
      FSkipReason := Err;
  if FSkipReason <> '' then
    Exit;
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-nettest-' + TGUID.NewGuid.ToString);
  FWork := TPath.Combine(TPath.GetTempPath, 'mtn2-nettest-work-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  TDirectory.CreateDirectory(FWork);
  BuildServedTree(FRoot);
  try
    StartServer;
  except
    on E: Exception do
      FSkipReason := 'test server did not start: ' + E.Message;
  end;
end;

procedure TNetServerFixture.TearDownFixture;
begin
  FServer.Free;
  FServer := nil;
  try
    if (FRoot <> '') and TDirectory.Exists(FRoot) then
      TDirectory.Delete(FRoot, True);
    if (FWork <> '') and TDirectory.Exists(FWork) then
      TDirectory.Delete(FWork, True);
  except
    // The temp folders are cleaned by the OS later if a file is still locked.
  end;
end;

function SessionFor(AProtocol: TNetProtocol; APort: Integer; const APassword: string): TNetSession;
begin
  Result := DefaultNetSession;
  Result.Name := 'test';
  Result.Protocol := AProtocol;
  Result.Host := '127.0.0.1';
  Result.Port := APort;
  Result.User := 'test';
  Result.Password := APassword;
  Result.VerifyCert := False;
  Result.TimeoutSec := 15;
end;

{ TTestNetFtp }

procedure TTestNetFtp.StartServer;
begin
  FServer := TNetTestServer.Create('serve_ftp.py', [FRoot, '12121'], 12121);
end;

function TTestNetFtp.MakeSession: TNetSession;
begin
  Result := SessionFor(npFtp, 12121, 'secret');
end;

procedure TTestNetFtp.TestListRootShowsFilesAndFolders;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckListRoot(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestListMissingFolderIsNotFound;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckListMissing(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestStatTellsFilesFoldersAndMissing;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckStat(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestDownloadFile;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckDownload(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestUploadAndReadBackBinary;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckUploadBinary(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestUnicodeAndSpacesInNames;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckUnicodeNames(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestMakeDirsRenameAndRemoveTree;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckDirsRenameRemove(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestOverwriteFlag;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckOverwriteFlag(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestCancelStopsTheTransfer;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckCancel(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestWrongPasswordIsAnAuthFailure;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  S: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := MakeSession;
  S.Password := 'wrong';
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrAuthFailed, 'login refused: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetFtp.TestSmallReadAndWrite;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckSmallReadWrite(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetFtp.TestAnonymousLoginReadsButCannotWrite;
var
  C: TNetClient;
  Op: TNetOp;
  S: TNetSession;
  Items: TNetEntries;
  Src: string;
  R: TNetResult;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := MakeSession;
  S.Auth := naAnonymous;
  S.User := '';
  S.Password := '';
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrOk, 'anonymous listing: ' + Op.ErrorText);
    Assert.IsTrue(Length(Items) >= 3);
    Src := TPath.Combine(FWork, 'anon.txt');
    TFile.WriteAllText(Src, 'x');
    R := C.Upload(Src, '/anon.txt', Op, True);
    Assert.IsTrue(R <> nrOk, 'the anonymous account is read only');
  finally
    Op.Free;
    C.Free;
  end;
end;

{ TTestNetFtps }

procedure TTestNetFtps.StartServer;
begin
  FServer := TNetTestServer.Create('serve_ftp.py', [FRoot, '12122', '--tls'], 12122);
end;

function TTestNetFtps.MakeSession: TNetSession;
begin
  Result := SessionFor(npFtps, 12122, 'secret');
end;

procedure TTestNetFtps.TestExplicitTlsListsAndTransfers;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckListRoot(C, '/');
    CheckDownload(C, '/', FWork);
    CheckUploadBinary(C, '/', FWork);
  finally
    C.Free;
  end;
end;

{ TTestNetSftp }

procedure TTestNetSftp.StartServer;
begin
  FServer := TNetTestServer.Create('serve_sftp.py', [FRoot, '12222'], 12222);
end;

function TTestNetSftp.MakeSession: TNetSession;
begin
  Result := SessionFor(npSftp, 12222, 'secret');
  // Learned from the first connection (see TestUnknownHostKey...).
  Result.HostKeySha256 := FFingerprint;
end;

procedure TTestNetSftp.TestUnknownHostKeyIsReportedWithItsFingerprint;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  S: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := MakeSession;
  S.HostKeySha256 := '';
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrHostKeyUnknown, 'a key nobody trusted yet: ' + Op.ErrorText);
    Assert.IsTrue(Length(Op.HostKey) = 43, 'SHA-256 in base64 without padding: ' + Op.HostKey);
    FFingerprint := Op.HostKey;
  finally
    Op.Free;
    C.Free;
  end;
  S.HostKeySha256 := FFingerprint;
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrOk, 'with the key trusted it works: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetSftp.TestChangedHostKeyIsRefused;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  S: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := MakeSession;
  S.HostKeySha256 := 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrHostKeyChanged, 'another key than the trusted one: ' + Op.ErrorText);
    Assert.IsTrue(Op.HostKey <> '', 'the new fingerprint is reported');
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetSftp.TestListRootShowsFilesAndFolders;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckListRoot(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestListMissingFolderIsNotFound;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckListMissing(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestStatTellsFilesFoldersAndMissing;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckStat(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestDownloadFile;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckDownload(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestUploadAndReadBackBinary;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckUploadBinary(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestUnicodeAndSpacesInNames;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckUnicodeNames(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestMakeDirsRenameAndRemoveTree;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckDirsRenameRemove(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestOverwriteFlag;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckOverwriteFlag(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestCancelStopsTheTransfer;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckCancel(C, '/', FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestWrongPasswordIsAnAuthFailure;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  S: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  S := MakeSession;
  S.Password := 'wrong';
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrAuthFailed, 'login refused: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetSftp.TestSmallReadAndWrite;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  C := CreateNetClient(MakeSession);
  try
    CheckSmallReadWrite(C, '/');
  finally
    C.Free;
  end;
end;

procedure TTestNetSftp.TestKeyFileLogin;
var
  Server: TNetTestServer;
  C: TNetClient;
  S: TNetSession;
  Op: TNetOp;
  Items: TNetEntries;
  KeyFile: string;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  KeyFile := TPath.Combine(FWork, 'client_key');
  Server := TNetTestServer.Create('serve_sftp_keys.py', [FRoot, '12223', KeyFile], 12223);
  try
    S := MakeSession;
    S.Port := 12223;
    S.Auth := naKey;
    S.Password := '';
    S.KeyFile := KeyFile;
    S.HostKeySha256 := '';
    C := CreateNetClient(S);
    Op := NewOp;
    try
      // The key of the server is asked about first, as with a password login.
      Assert.IsTrue(C.ListDir('/', Op, Items) = nrHostKeyUnknown, 'unknown key: ' + Op.ErrorText);
      S.HostKeySha256 := Op.HostKey;
    finally
      Op.Free;
      C.Free;
    end;
    C := CreateNetClient(S);
    Op := NewOp;
    try
      Assert.IsTrue(C.ListDir('/', Op, Items) = nrOk, 'key login: ' + Op.ErrorText);
      Assert.IsTrue(Length(Items) >= 3);
    finally
      Op.Free;
      C.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TTestNetSftp.TestScpTransfersFileData;
var
  C: TNetClient;
  S: TNetSession;
  Op: TNetOp;
  Src, Back: string;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  TestUnknownHostKeyIsReportedWithItsFingerprint;
  S := MakeSession;
  S.Protocol := npScp;
  C := CreateNetClient(S);
  Op := NewOp;
  try
    Src := RandomFile(TPath.Combine(FWork, 'scp.bin'), 700 * 1024 + 3);
    Assert.IsTrue(C.Upload(Src, '/scp-up.bin', Op, True) = nrOk, 'scp upload: ' + Op.ErrorText);
    Back := TPath.Combine(FWork, 'scp-back.bin');
    Assert.IsTrue(C.Download('/scp-up.bin', Back, Op, False) = nrOk, 'scp download: ' + Op.ErrorText);
    Assert.AreEqual(FileHash(Src), FileHash(Back));
    Assert.IsTrue(C.RemoveFile('/scp-up.bin', Op) = nrOk, 'the folder side works through SFTP: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetFtp);
  TDUnitX.RegisterTestFixture(TTestNetFtps);
  TDUnitX.RegisterTestFixture(TTestNetSftp);

end.
