unit TestNetClientsHttp;

{ The WebDAV and S3 clients against local servers (see uNetTestServers.pas for
  what the tests need; without it they report a skip). }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, uNetTypes, uNetClient,
  uNetTestServers, TestNetClients;

type
  [TestFixture]
  TTestNetWebDav = class(TNetServerFixture)
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
    [Test] procedure TestServerSideCopyKeepsTheSource;
  end;

  [TestFixture]
  TTestNetS3 = class(TNetServerFixture)
  protected
    procedure StartServer; override;
    function MakeSession: TNetSession; override;
    function BasePath: string; override;
  public
    [Test] procedure TestBucketsAreTheRootFolders;
    [Test] procedure TestListBucketShowsFilesAndFolders;
    [Test] procedure TestListMissingFolderIsNotFound;
    [Test] procedure TestStatTellsFilesFoldersAndMissing;
    [Test] procedure TestDownloadFile;
    [Test] procedure TestUploadAndReadBackBinary;
    [Test] procedure TestUnicodeAndSpacesInNames;
    [Test] procedure TestMakeDirsRenameAndRemoveTree;
    [Test] procedure TestOverwriteFlag;
    [Test] procedure TestCancelStopsTheTransfer;
    [Test] procedure TestSmallReadAndWrite;
    [Test] procedure TestMultipartUploadOfALargeFile;
    [Test] procedure TestLargeListingContinues;
    [Test] procedure TestServerSideCopyAndRename;
  end;

implementation

uses
  System.IOUtils, System.Hash, uNetCurlApi;

function SessionFor(AProtocol: TNetProtocol; const AHost: string; APort: Integer;
  const AUser, APassword: string): TNetSession;
begin
  Result := DefaultNetSession;
  Result.Name := 'test';
  Result.Protocol := AProtocol;
  Result.Host := AHost;
  Result.Port := APort;
  Result.User := AUser;
  Result.Password := APassword;
  Result.VerifyCert := False;
  Result.TimeoutSec := 15;
end;

{ TTestNetWebDav }

procedure TTestNetWebDav.StartServer;
begin
  FServer := TNetTestServer.Create('serve_dav.py', [FRoot, '18081'], 18081);
end;

function TTestNetWebDav.MakeSession: TNetSession;
begin
  Result := SessionFor(npWebDav, '127.0.0.1', 18081, 'test', 'secret');
end;

procedure TTestNetWebDav.TestListRootShowsFilesAndFolders;
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

procedure TTestNetWebDav.TestListMissingFolderIsNotFound;
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

procedure TTestNetWebDav.TestStatTellsFilesFoldersAndMissing;
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

procedure TTestNetWebDav.TestDownloadFile;
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

procedure TTestNetWebDav.TestUploadAndReadBackBinary;
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

procedure TTestNetWebDav.TestUnicodeAndSpacesInNames;
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

procedure TTestNetWebDav.TestMakeDirsRenameAndRemoveTree;
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

procedure TTestNetWebDav.TestOverwriteFlag;
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

procedure TTestNetWebDav.TestCancelStopsTheTransfer;
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

procedure TTestNetWebDav.TestWrongPasswordIsAnAuthFailure;
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
  Op := TNetOp.Create;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrAuthFailed, 'login refused: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetWebDav.TestSmallReadAndWrite;
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

procedure TTestNetWebDav.TestServerSideCopyKeepsTheSource;
var
  C: TNetClient;
  Op: TNetOp;
  E: TNetEntry;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    Assert.IsTrue(C.ServerCopy('/hello.txt', '/hello-copy.txt', True, Op) = nrOk, 'copy: ' + Op.ErrorText);
    Assert.IsTrue(C.Stat('/hello.txt', Op, E) = nrOk, 'the source stays');
    Assert.IsTrue(C.Stat('/hello-copy.txt', Op, E) = nrOk, 'the copy is there');
    Assert.IsTrue(E.Size = Length(TestFixtureText));
    Assert.IsTrue(C.ServerCopy('/hello.txt', '/hello-copy.txt', False, Op) = nrAlreadyExists,
      'without overwrite an existing target is refused');
    C.RemoveFile('/hello-copy.txt', Op);
  finally
    Op.Free;
    C.Free;
  end;
end;

{ TTestNetS3 }

const
  cBucket = 'testbucket';

function TTestNetS3.BasePath: string;
begin
  Result := '/' + cBucket;
end;

procedure TTestNetS3.StartServer;
var
  C: TNetClient;
  Op: TNetOp;
begin
  FServer := TNetTestServer.Create('serve_s3.py', ['15000'], 15000);
  // The served tree lives in the bucket; build it through the client.
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    if C.MakeDir('/' + cBucket, Op) <> nrOk then
      raise Exception.Create('cannot create the test bucket: ' + Op.ErrorText);
    C.Upload(TPath.Combine(FRoot, 'hello.txt'), '/' + cBucket + '/hello.txt', Op, True);
    C.Upload(TPath.Combine(FRoot, 'docs\a.txt'), '/' + cBucket + '/docs/a.txt', Op, True);
    C.MakeDir('/' + cBucket + '/empty', Op);
  finally
    Op.Free;
    C.Free;
  end;
end;

function TTestNetS3.MakeSession: TNetSession;
begin
  Result := SessionFor(npS3, 'http://127.0.0.1:15000', 0, 'AKIATESTKEY', 'testsecretkey');
  Result.Region := 'us-east-1';
  Result.PathStyle := True;
end;

procedure TTestNetS3.TestBucketsAreTheRootFolders;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  Found: Boolean;
  E: TNetEntry;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    Assert.IsTrue(C.ListDir('/', Op, Items) = nrOk, 'buckets: ' + Op.ErrorText);
    Found := False;
    for E in Items do
      if (E.Name = cBucket) and E.IsDir then
        Found := True;
    Assert.IsTrue(Found, 'the test bucket is listed as a folder');
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetS3.TestListBucketShowsFilesAndFolders;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckListRoot(C, BasePath);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestListMissingFolderIsNotFound;
var
  C: TNetClient;
  Op: TNetOp;
  E: TNetEntry;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    // A prefix with nothing under it is an empty folder to a listing, but Stat knows.
    Assert.IsTrue(C.Stat(BasePath + '/no-such-folder', Op, E) = nrNotFound);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetS3.TestStatTellsFilesFoldersAndMissing;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckStat(C, BasePath);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestDownloadFile;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckDownload(C, BasePath, FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestUploadAndReadBackBinary;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckUploadBinary(C, BasePath, FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestUnicodeAndSpacesInNames;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckUnicodeNames(C, BasePath, FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestMakeDirsRenameAndRemoveTree;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckDirsRenameRemove(C, BasePath);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestOverwriteFlag;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckOverwriteFlag(C, BasePath, FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestCancelStopsTheTransfer;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckCancel(C, BasePath, FWork);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestSmallReadAndWrite;
var
  C: TNetClient;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  try
    CheckSmallReadWrite(C, BasePath);
  finally
    C.Free;
  end;
end;

procedure TTestNetS3.TestMultipartUploadOfALargeFile;
var
  C: TNetClient;
  Op: TNetOp;
  Src, Back: string;
  Stream: TFileStream;
  E: TNetEntry;
  Buf: TBytes;
  I: Integer;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    Src := TPath.Combine(FWork, 'huge.bin');
    // A little more than the single-PUT limit, in four parts of the part size.
    SetLength(Buf, 1024 * 1024);
    RandSeed := 777;
    for I := 0 to High(Buf) do
      Buf[I] := Random(256);
    Stream := TFileStream.Create(Src, fmCreate);
    try
      for I := 1 to 100 do
        Stream.WriteBuffer(Buf[0], Length(Buf));
    finally
      Stream.Free;
    end;
    Assert.IsTrue(C.Upload(Src, BasePath + '/huge.bin', Op, True) = nrOk, 'multipart upload: ' + Op.ErrorText);
    Assert.IsTrue(C.Stat(BasePath + '/huge.bin', Op, E) = nrOk);
    Assert.IsTrue(E.Size = 100 * 1024 * 1024, 'all parts arrived: ' + IntToStr(E.Size));
    Back := TPath.Combine(FWork, 'huge-back.bin');
    Assert.IsTrue(C.Download(BasePath + '/huge.bin', Back, Op, False) = nrOk, 'download: ' + Op.ErrorText);
    Assert.AreEqual(THashSHA2.GetHashStringFromFile(Src), THashSHA2.GetHashStringFromFile(Back));
    C.RemoveFile(BasePath + '/huge.bin', Op);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetS3.TestLargeListingContinues;
var
  C: TNetClient;
  Op: TNetOp;
  Items: TNetEntries;
  I: Integer;
  Src: string;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    Src := TPath.Combine(FWork, 'tiny.txt');
    TFile.WriteAllText(Src, 'x');
    for I := 1 to 1105 do
      Assert.IsTrue(C.Upload(Src, Format('%s/many/f%.4d.txt', [BasePath, I]), Op, True) = nrOk,
        'upload ' + IntToStr(I) + ': ' + Op.ErrorText);
    Assert.IsTrue(C.ListDir(BasePath + '/many', Op, Items) = nrOk, 'list: ' + Op.ErrorText);
    Assert.IsTrue(Length(Items) = 1105, 'every page was read: ' + IntToStr(Length(Items)));
    Assert.IsTrue(C.RemoveTree(BasePath + '/many', True, Op) = nrOk, 'remove: ' + Op.ErrorText);
  finally
    Op.Free;
    C.Free;
  end;
end;

procedure TTestNetS3.TestServerSideCopyAndRename;
var
  C: TNetClient;
  Op: TNetOp;
  E: TNetEntry;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  C := CreateNetClient(MakeSession);
  Op := TNetOp.Create;
  try
    Assert.IsTrue(C.ServerCopy(BasePath + '/hello.txt', BasePath + '/copy of hello.txt', True, Op) = nrOk,
      'copy: ' + Op.ErrorText);
    Assert.IsTrue(C.Stat(BasePath + '/copy of hello.txt', Op, E) = nrOk);
    Assert.IsTrue(E.Size = Length(TestFixtureText));
    Assert.IsTrue(C.Rename(BasePath + '/copy of hello.txt', BasePath + '/renamed.txt', True, Op) = nrOk,
      'rename: ' + Op.ErrorText);
    Assert.IsTrue(C.Stat(BasePath + '/copy of hello.txt', Op, E) = nrNotFound, 'old key gone');
    Assert.IsTrue(C.Stat(BasePath + '/renamed.txt', Op, E) = nrOk, 'new key there');
    C.RemoveFile(BasePath + '/renamed.txt', Op);
  finally
    Op.Free;
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetWebDav);
  TDUnitX.RegisterTestFixture(TTestNetS3);

end.
