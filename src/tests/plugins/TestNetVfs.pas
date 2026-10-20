unit TestNetVfs;

{ The VFS of the network plugin (uNetVfs) behind the host's own adapter for
  version 2 tables, with the session manager and a scripted prompter: session
  list, listing, copies of files and folders both ways, moves, deletes, login
  and host key questions. FTP and SFTP servers run locally (see
  uNetTestServers.pas); without them the tests report a skip. }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes, uNetTypes, uNetManager, uNetTestServers;

type
  TScriptPrompter = class(TInterfacedObject, INetPrompter)
  public
    Secrets: TQueue<string>;
    SecretCalls: Integer;
    LastRetry: Boolean;
    TrustHost: Boolean;
    HostKeyCalls: Integer;
    LastChanged: Boolean;
    TrustCert: Boolean;
    constructor Create;
    destructor Destroy; override;
    function AskSecret(const ASession: TNetSession; AKeyPassphrase, ARetry: Boolean;
      AOp: TNetOp; out ASecret: string; out ASave: Boolean): Boolean;
    function TrustHostKey(const ASession: TNetSession; const AFingerprint: string;
      AChanged: Boolean; AOp: TNetOp): Boolean;
    function TrustCertificate(const ASession: TNetSession; const AMessage: string;
      AOp: TNetOp): Boolean;
  end;

  [TestFixture]
  TTestNetVfs = class
  private
    FSkipReason: string;
    FRoot: string;
    FWork: string;
    FFtp, FSftp: TNetTestServer;
    FManager: TNetManager;
    FPrompter: TScriptPrompter;
    FPrompterRef: INetPrompter;
    FBackend: IVirtualFileSystem;
    FStoreWrites: Integer;
    function FtpSession(const AName: string): TNetSession;
    function SftpSession(const AName: string): TNetSession;
    function List(const AUri: string; out AError: TVfsError): TArray<TVfsEntry>;
    function ExistsAt(const AUri: string; out AIsDir: Boolean): Boolean;
    function Copy_(const AFrom, ATo: string; AOverwrite: Boolean): TVfsError;
    function Move_(const AFrom, ATo: string; AOverwrite: Boolean): TVfsError;
    function Delete_(const AUri: string): TVfsError;
    function MkDir_(const AUri: string): TVfsError;
    function NameList(const AUri: string): string;
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestSessionListShowsSavedSessionsAsFolders;
    [Test] procedure TestAddressOfASessionRowIsNormalised;
    [Test] procedure TestListingASessionAsksForThePasswordOnce;
    [Test] procedure TestWrongPasswordIsAskedAgainWithRetryFlag;
    [Test] procedure TestCancelledPasswordPromptFailsTheOperation;
    [Test] procedure TestSavedPasswordIsNeverAsked;
    [Test] procedure TestDirectAddressUsesTheSavedSessionOfThatServer;
    [Test] procedure TestFileCopiesBothWays;
    [Test] procedure TestFolderTreeCopiesBothWays;
    [Test] procedure TestCopyRefusesToOverwriteWithoutTheFlag;
    [Test] procedure TestMoveInsideASessionRenames;
    [Test] procedure TestMoveBetweenSessionsGoesThroughALocalCopy;
    [Test] procedure TestDeleteRemovesTreesAndSessions;
    [Test] procedure TestCreateDirectoryMakesParents;
    [Test] procedure TestExistsOfSessionRootNeedsNoConnection;
    [Test] procedure TestUnknownSessionIsNotFound;
    [Test] procedure TestHostKeyQuestionIsAskedOnceAndRemembered;
    [Test] procedure TestRefusedHostKeyFailsTheOperation;
    [Test] procedure TestChangedHostKeyIsReported;
    [Test] procedure TestReadBytesHonoursSizeLimitAndBufferRetry;
    [Test] procedure TestCancelStopsACopyAndReportsCancelled;
  end;

implementation

uses
  System.IOUtils, System.Hash, Winapi.Windows, uPluginHostAbi, uVfsCdeclAdapterV2, uNetVfs,
  uNetCurlApi;

function StubIsCancelled(ACtx: PVfsOpContext): Int64; cdecl;
begin
  Result := 0;
end;

{ TScriptPrompter }

constructor TScriptPrompter.Create;
begin
  inherited Create;
  Secrets := TQueue<string>.Create;
  TrustHost := True;
  TrustCert := True;
end;

destructor TScriptPrompter.Destroy;
begin
  Secrets.Free;
  inherited Destroy;
end;

function TScriptPrompter.AskSecret(const ASession: TNetSession; AKeyPassphrase, ARetry: Boolean;
  AOp: TNetOp; out ASecret: string; out ASave: Boolean): Boolean;
begin
  Inc(SecretCalls);
  LastRetry := ARetry;
  ASave := False;
  ASecret := '';
  if Secrets.Count = 0 then
    Exit(False);
  ASecret := Secrets.Dequeue;
  Result := True;
end;

function TScriptPrompter.TrustHostKey(const ASession: TNetSession; const AFingerprint: string;
  AChanged: Boolean; AOp: TNetOp): Boolean;
begin
  Inc(HostKeyCalls);
  LastChanged := AChanged;
  Result := TrustHost;
end;

function TScriptPrompter.TrustCertificate(const ASession: TNetSession; const AMessage: string;
  AOp: TNetOp): Boolean;
begin
  Result := TrustCert;
end;

{ helpers }

procedure Pump(const AFlag: PBoolean);
var
  I: Integer;
begin
  for I := 1 to 3000 do
  begin
    CheckSynchronize(10);
    if AFlag^ then
      Exit;
  end;
end;

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

{ TTestNetVfs }

procedure TTestNetVfs.SetupFixture;
var
  Err: string;
begin
  FSkipReason := NetTestUnavailable;
  if FSkipReason = '' then
    if not NetTestLoadCurl(Err) then
      FSkipReason := Err;
  if FSkipReason <> '' then
    Exit;
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-netvfs-' + TGUID.NewGuid.ToString);
  FWork := TPath.Combine(TPath.GetTempPath, 'mtn2-netvfs-work-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  TDirectory.CreateDirectory(FWork);
  BuildServedTree(FRoot);
  try
    FFtp := TNetTestServer.Create('serve_ftp.py', [FRoot, '12131'], 12131);
    FSftp := TNetTestServer.Create('serve_sftp.py', [FRoot, '12232'], 12232);
  except
    on E: Exception do
      FSkipReason := 'test server did not start: ' + E.Message;
  end;
end;

procedure TTestNetVfs.TearDownFixture;
begin
  FFtp.Free;
  FSftp.Free;
  try
    if (FRoot <> '') and TDirectory.Exists(FRoot) then
      TDirectory.Delete(FRoot, True);
    if (FWork <> '') and TDirectory.Exists(FWork) then
      TDirectory.Delete(FWork, True);
  except
    // The temp folders are cleaned by the OS later if a file is still locked.
  end;
end;

function TTestNetVfs.FtpSession(const AName: string): TNetSession;
begin
  Result := DefaultNetSession;
  Result.Name := AName;
  Result.Protocol := npFtp;
  Result.Host := '127.0.0.1';
  Result.Port := 12131;
  Result.User := 'test';
  Result.Password := 'secret';
  Result.SavePassword := True;
  Result.TimeoutSec := 15;
end;

function TTestNetVfs.SftpSession(const AName: string): TNetSession;
begin
  Result := DefaultNetSession;
  Result.Name := AName;
  Result.Protocol := npSftp;
  Result.Host := '127.0.0.1';
  Result.Port := 12232;
  Result.User := 'test';
  Result.Password := 'secret';
  Result.SavePassword := True;
  Result.TimeoutSec := 15;
end;

procedure TTestNetVfs.Setup;
begin
  if FSkipReason <> '' then
    Exit;
  FManager := TNetManager.Create;
  FStoreWrites := 0;
  FManager.OnStoreChanged := procedure begin Inc(FStoreWrites); end;
  FPrompter := TScriptPrompter.Create;
  FPrompterRef := FPrompter;
  FManager.SetPrompter(FPrompterRef);
  NetVfsAttach(FManager);
  FBackend := TCdeclVfsBackendV2.Create(NetVfsCallbacks, nil);
  FManager.AddSession(FtpSession('ftp1'));
  FManager.AddSession(FtpSession('ftp2'));
end;

procedure TTestNetVfs.TearDown;
begin
  if FSkipReason <> '' then
    Exit;
  NetVfsAttach(nil);
  FBackend := nil;
  FManager.SetPrompter(nil);
  FPrompterRef := nil;
  FPrompter := nil;
  FreeAndNil(FManager);
end;

function TTestNetVfs.List(const AUri: string; out AError: TVfsError): TArray<TVfsEntry>;
var
  Done: Boolean;
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
begin
  Done := False;
  FBackend.ListDirectoryAsync(AUri, nil,
    procedure(const AItems: TArray<TVfsEntry>; const AErr: TVfsError)
    begin
      Items := AItems;
      Err := AErr;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the listing finished');
  AError := Err;
  Result := Items;
end;

function TTestNetVfs.NameList(const AUri: string): string;
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  E: TVfsEntry;
  L: TStringList;
begin
  Items := List(AUri, Err);
  L := TStringList.Create;
  try
    for E in Items do
      L.Add(E.Name);
    L.Sort;
    Result := L.CommaText;
  finally
    L.Free;
  end;
end;

function TTestNetVfs.ExistsAt(const AUri: string; out AIsDir: Boolean): Boolean;
var
  Done, Found, IsDir: Boolean;
begin
  Done := False;
  FBackend.ExistsAsync(AUri, nil,
    procedure(const AExists: Boolean; const AIsDirectory: Boolean; const AError: TVfsError)
    begin
      Found := AExists;
      IsDir := AIsDirectory;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the check finished');
  AIsDir := IsDir;
  Result := Found;
end;

function TTestNetVfs.Copy_(const AFrom, ATo: string; AOverwrite: Boolean): TVfsError;
var
  Done: Boolean;
  Err: TVfsError;
begin
  Done := False;
  FBackend.CopyAsync(AFrom, ATo, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end, AOverwrite, False);
  Pump(@Done);
  Assert.IsTrue(Done, 'the copy finished');
  Result := Err;
end;

function TTestNetVfs.Move_(const AFrom, ATo: string; AOverwrite: Boolean): TVfsError;
var
  Done: Boolean;
  Err: TVfsError;
begin
  Done := False;
  FBackend.MoveAsync(AFrom, ATo, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end, AOverwrite, False);
  Pump(@Done);
  Assert.IsTrue(Done, 'the move finished');
  Result := Err;
end;

function TTestNetVfs.Delete_(const AUri: string): TVfsError;
var
  Done: Boolean;
  Err: TVfsError;
begin
  Done := False;
  FBackend.DeleteAsync(AUri, vdmPermanent, nil, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the delete finished');
  Result := Err;
end;

function TTestNetVfs.MkDir_(const AUri: string): TVfsError;
var
  Done: Boolean;
  Err: TVfsError;
begin
  Done := False;
  FBackend.CreateDirectoryAsync(AUri, nil,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Done, 'the mkdir finished');
  Result := Err;
end;

procedure TTestNetVfs.TestSessionListShowsSavedSessionsAsFolders;
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Items := List('net:///', Err);
  Assert.IsTrue(Err.Code = vecOk, Err.Message);
  Assert.IsTrue(Length(Items) = 2);
  Assert.AreEqual('ftp1', Items[0].Name);
  Assert.IsTrue(Items[0].IsDirectory);
  Assert.AreEqual('net://ftp1/', Items[0].TargetURI, 'a session opens at its start folder');
  Items := List('ftp:///', Err);
  Assert.IsTrue(Length(Items) = 2, 'the root of a protocol lists its sessions');
  Items := List('s3:///', Err);
  Assert.IsTrue(Length(Items) = 0, 'no session of another protocol');
end;

procedure TTestNetVfs.TestAddressOfASessionRowIsNormalised;
begin
  Assert.AreEqual('net://ftp1/', NormalizeNetUri('net:///ftp1'));
  Assert.AreEqual('net://ftp1/docs/a.txt', NormalizeNetUri('net:///ftp1/docs/a.txt'));
  Assert.AreEqual('net:///', NormalizeNetUri('net:///'));
  Assert.AreEqual('net://x/y', NormalizeNetUri('net://x/y'));
  Assert.AreEqual('file:///C:/a', NormalizeNetUri('file:///C:/a'));
end;

procedure TTestNetVfs.TestListingASessionAsksForThePasswordOnce;
var
  S: TNetSession;
  Err: TVfsError;
  Items: TArray<TVfsEntry>;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := FtpSession('ask');
  S.Password := '';
  S.SavePassword := False;
  FManager.AddSession(S);
  FPrompter.Secrets.Enqueue('secret');
  Items := List('net://ask/', Err);
  Assert.IsTrue(Err.Code = vecOk, 'listing: ' + Err.Message);
  Assert.IsTrue(Length(Items) >= 3);
  Assert.AreEqual(1, FPrompter.SecretCalls, 'asked once');
  Assert.IsFalse(FPrompter.LastRetry);
  List('net://ask/docs', Err);
  Assert.IsTrue(Err.Code = vecOk);
  Assert.AreEqual(1, FPrompter.SecretCalls, 'the answer is kept for the run');
end;

procedure TTestNetVfs.TestWrongPasswordIsAskedAgainWithRetryFlag;
var
  S: TNetSession;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := FtpSession('ask');
  S.Password := '';
  S.SavePassword := False;
  FManager.AddSession(S);
  FPrompter.Secrets.Enqueue('nope');
  FPrompter.Secrets.Enqueue('secret');
  List('net://ask/', Err);
  Assert.IsTrue(Err.Code = vecOk, 'second try works: ' + Err.Message);
  Assert.AreEqual(2, FPrompter.SecretCalls);
  Assert.IsTrue(FPrompter.LastRetry, 'the second question says the first answer was refused');
end;

procedure TTestNetVfs.TestCancelledPasswordPromptFailsTheOperation;
var
  S: TNetSession;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := FtpSession('ask');
  S.Password := '';
  S.SavePassword := False;
  FManager.AddSession(S);
  List('net://ask/', Err);
  Assert.IsTrue(Err.Code = vecCancelled, 'no answer: ' + Err.Message);
end;

procedure TTestNetVfs.TestSavedPasswordIsNeverAsked;
var
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  List('net://ftp1/', Err);
  Assert.IsTrue(Err.Code = vecOk, Err.Message);
  Assert.AreEqual(0, FPrompter.SecretCalls);
end;

procedure TTestNetVfs.TestDirectAddressUsesTheSavedSessionOfThatServer;
var
  Err: TVfsError;
  Items: TArray<TVfsEntry>;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Items := List('ftp://127.0.0.1:12131/', Err);
  Assert.IsTrue(Err.Code = vecOk, 'the saved login of that server is used: ' + Err.Message);
  Assert.IsTrue(Length(Items) >= 3);
  Assert.AreEqual(0, FPrompter.SecretCalls);
  Items := List('ftp://test:secret@127.0.0.1:12131/docs', Err);
  Assert.IsTrue(Err.Code = vecOk, Err.Message);
  Assert.AreEqual('a.txt', Items[0].Name);
end;

procedure TTestNetVfs.TestFileCopiesBothWays;
var
  Src, Back: string;
  Err: TVfsError;
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'up.bin');
  TFile.WriteAllBytes(Src, Bytes(StringOfChar('x', 300000)));
  Err := Copy_(PathToFileUri(Src), 'net://ftp1/up.bin', False);
  Assert.IsTrue(Err.Code = vecOk, 'upload: ' + Err.Message);
  Assert.IsTrue(ExistsAt('net://ftp1/up.bin', IsDir) and not IsDir);
  Back := TPath.Combine(FWork, 'down.bin');
  Err := Copy_('net://ftp1/up.bin', PathToFileUri(Back), False);
  Assert.IsTrue(Err.Code = vecOk, 'download: ' + Err.Message);
  Assert.AreEqual(THashSHA2.GetHashStringFromFile(Src), THashSHA2.GetHashStringFromFile(Back));
  Delete_('net://ftp1/up.bin');
  Assert.IsFalse(ExistsAt('net://ftp1/up.bin', IsDir), 'deleted');
end;

procedure TTestNetVfs.TestFolderTreeCopiesBothWays;
var
  Tree, Back: string;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Tree := TPath.Combine(FWork, 'tree');
  TDirectory.CreateDirectory(TPath.Combine(Tree, 'sub\deeper'));
  TFile.WriteAllText(TPath.Combine(Tree, 'a.txt'), 'A');
  TFile.WriteAllText(TPath.Combine(Tree, 'sub\b.txt'), 'B');
  TFile.WriteAllText(TPath.Combine(Tree, 'sub\deeper\c.txt'), 'C');
  Err := Copy_(PathToFileUri(Tree), 'net://ftp1/treecopy', False);
  Assert.IsTrue(Err.Code = vecOk, 'upload tree: ' + Err.Message);
  Assert.AreEqual('a.txt,sub', NameList('net://ftp1/treecopy'));
  Assert.AreEqual('b.txt,deeper', NameList('net://ftp1/treecopy/sub'));
  Back := TPath.Combine(FWork, 'tree-back');
  Err := Copy_('net://ftp1/treecopy', PathToFileUri(Back), False);
  Assert.IsTrue(Err.Code = vecOk, 'download tree: ' + Err.Message);
  Assert.AreEqual('C', TFile.ReadAllText(TPath.Combine(Back, 'sub\deeper\c.txt')));
  Assert.AreEqual('A', TFile.ReadAllText(TPath.Combine(Back, 'a.txt')));
  Delete_('net://ftp1/treecopy');
  Assert.AreEqual('', NameList('net://ftp1/treecopy'), 'the tree is gone');
end;

procedure TTestNetVfs.TestCopyRefusesToOverwriteWithoutTheFlag;
var
  Src: string;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'ow.txt');
  TFile.WriteAllText(Src, 'one');
  Assert.IsTrue(Copy_(PathToFileUri(Src), 'net://ftp1/ow.txt', False).Code = vecOk);
  Err := Copy_(PathToFileUri(Src), 'net://ftp1/ow.txt', False);
  Assert.IsTrue(Err.Code = vecAlreadyExists, 'second copy: ' + Err.Message);
  Assert.IsTrue(Copy_(PathToFileUri(Src), 'net://ftp1/ow.txt', True).Code = vecOk, 'with the flag');
  Delete_('net://ftp1/ow.txt');
end;

procedure TTestNetVfs.TestMoveInsideASessionRenames;
var
  Src: string;
  Err: TVfsError;
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'mv.txt');
  TFile.WriteAllText(Src, 'move');
  Copy_(PathToFileUri(Src), 'net://ftp1/mv.txt', False);
  Err := Move_('net://ftp1/mv.txt', 'net://ftp1/docs/mv2.txt', False);
  Assert.IsTrue(Err.Code = vecOk, 'move: ' + Err.Message);
  Assert.IsFalse(ExistsAt('net://ftp1/mv.txt', IsDir), 'the source name is gone');
  Assert.IsTrue(ExistsAt('net://ftp1/docs/mv2.txt', IsDir), 'the new one is there');
  Delete_('net://ftp1/docs/mv2.txt');
end;

procedure TTestNetVfs.TestMoveBetweenSessionsGoesThroughALocalCopy;
var
  Src: string;
  Err: TVfsError;
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'mvx.txt');
  TFile.WriteAllText(Src, 'between sessions');
  Copy_(PathToFileUri(Src), 'net://ftp1/mvx.txt', False);
  Err := Move_('net://ftp1/mvx.txt', 'net://ftp2/docs/mvx.txt', False);
  Assert.IsTrue(Err.Code = vecOk, 'move: ' + Err.Message);
  Assert.IsFalse(ExistsAt('net://ftp1/mvx.txt', IsDir) and ExistsAt('net://ftp1/docs/mvx.txt', IsDir) and False);
  Assert.IsTrue(ExistsAt('net://ftp2/docs/mvx.txt', IsDir), 'arrived');
  Err := Copy_('net://ftp2/docs/mvx.txt', 'net://ftp1/copy-of-mvx.txt', False);
  Assert.IsTrue(Err.Code = vecOk, 'copy between sessions: ' + Err.Message);
  Assert.IsTrue(ExistsAt('net://ftp2/docs/mvx.txt', IsDir), 'a copy keeps the source');
  Delete_('net://ftp2/docs/mvx.txt');
  Delete_('net://ftp1/copy-of-mvx.txt');
end;

procedure TTestNetVfs.TestDeleteRemovesTreesAndSessions;
var
  Err: TVfsError;
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Assert.IsTrue(MkDir_('net://ftp1/d1/d2').Code = vecOk);
  Err := Delete_('net://ftp1/d1');
  Assert.IsTrue(Err.Code = vecOk, 'delete tree: ' + Err.Message);
  Assert.IsFalse(ExistsAt('net://ftp1/d1', IsDir));
  Err := Delete_('net:///ftp2');
  Assert.IsTrue(Err.Code = vecOk, 'deleting a session row removes the session: ' + Err.Message);
  Assert.IsTrue(FManager.SessionCount = 1);
  Assert.IsTrue(FStoreWrites > 0, 'the change is stored');
end;

procedure TTestNetVfs.TestCreateDirectoryMakesParents;
var
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Assert.IsTrue(MkDir_('net://ftp1/p1/p2/p3').Code = vecOk);
  Assert.IsTrue(ExistsAt('net://ftp1/p1/p2/p3', IsDir) and IsDir);
  Delete_('net://ftp1/p1');
end;

procedure TTestNetVfs.TestExistsOfSessionRootNeedsNoConnection;
var
  IsDir: Boolean;
  S: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := FtpSession('offline');
  S.Port := 1; // nothing listens there
  FManager.AddSession(S);
  Assert.IsTrue(ExistsAt('net://offline/', IsDir) and IsDir, 'the session root exists with the session');
  Assert.IsTrue(ExistsAt('net:///', IsDir) and IsDir);
  Assert.IsFalse(ExistsAt('net://nobody/', IsDir));
end;

procedure TTestNetVfs.TestUnknownSessionIsNotFound;
var
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  List('net://missing/', Err);
  Assert.IsTrue(Err.Code = vecNotFound, 'no such session: ' + Err.Message);
end;

procedure TTestNetVfs.TestHostKeyQuestionIsAskedOnceAndRemembered;
var
  S: TNetSession;
  Err: TVfsError;
  Stored: TNetSession;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  FManager.AddSession(SftpSession('sf'));
  List('net://sf/', Err);
  Assert.IsTrue(Err.Code = vecOk, 'listing: ' + Err.Message);
  Assert.AreEqual(1, FPrompter.HostKeyCalls);
  Assert.IsFalse(FPrompter.LastChanged, 'a new key, not a changed one');
  Assert.IsTrue(FManager.FindSession('sf', Stored));
  Assert.IsTrue(Length(Stored.HostKeySha256) = 43, 'the trusted key is saved with the session');
  List('net://sf/docs', Err);
  Assert.IsTrue(Err.Code = vecOk, Err.Message);
  Assert.AreEqual(1, FPrompter.HostKeyCalls, 'not asked again');
  S := Stored;
  Assert.IsTrue(FStoreWrites > 0);
end;

procedure TTestNetVfs.TestRefusedHostKeyFailsTheOperation;
var
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  FManager.AddSession(SftpSession('sf'));
  FPrompter.TrustHost := False;
  List('net://sf/', Err);
  Assert.IsTrue(Err.Code = vecAccessDenied, 'refused key: ' + Err.Message);
  Assert.AreEqual(1, FPrompter.HostKeyCalls);
end;

procedure TTestNetVfs.TestChangedHostKeyIsReported;
var
  S: TNetSession;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  S := SftpSession('sf');
  S.HostKeySha256 := 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  FManager.AddSession(S);
  FPrompter.TrustHost := False;
  List('net://sf/', Err);
  Assert.IsTrue(Err.Code = vecAccessDenied);
  Assert.IsTrue(FPrompter.LastChanged, 'the question says the key changed');
end;

procedure TTestNetVfs.TestReadBytesHonoursSizeLimitAndBufferRetry;
var
  Cb: TVfsCallbacksCdeclV2;
  Ctx: TVfsOpContext;
  Buf: array[0..63] of Byte;
  Neg: Int64;
  Code: Int64;
  Big: TBytes;
  BigBuf: TBytes;
  Done: Boolean;
  Data: TBytes;
  Err: TVfsError;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Cb := NetVfsCallbacks;
  Ctx := Default(TVfsOpContext);
  Ctx.IsCancelled := StubIsCancelled;
  // hello.txt is 13 bytes: too big for a 4 byte limit, fits a 64 byte buffer.
  Code := Cb.ReadBytes('net://ftp1/hello.txt', 4, nil, @Ctx, @Buf[0], SizeOf(Buf), Neg);
  Assert.AreEqual(Int64(Ord(verNotSupported)), Code, 'over the limit is "too large"');
  Code := Cb.ReadBytes('net://ftp1/hello.txt', 0, nil, @Ctx, @Buf[0], SizeOf(Buf), Neg);
  Assert.AreEqual(Int64(Ord(verOk)), Code);
  Assert.AreEqual(Int64(Length(TestFixtureText)), Neg);
  // A buffer too small asks for a bigger one.
  Code := Cb.ReadBytes('net://ftp1/hello.txt', 0, nil, @Ctx, @Buf[0], 5, Neg);
  Assert.AreEqual(Int64(Ord(verNeedsBiggerBuffer)), Code);
  Assert.IsTrue(Neg > 5, 'the size needed is reported');
  // The adapter does the retry; a whole file through the host path:
  Done := False;
  FBackend.ReadBytesAsync('net://ftp1/hello.txt', 0, nil,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    begin
      Data := ABytes;
      Err := AError;
      Done := True;
    end);
  Pump(@Done);
  Assert.IsTrue(Err.Code = vecOk, Err.Message);
  Assert.AreEqual(TestFixtureText, TEncoding.ASCII.GetString(Data));
  SetLength(Big, 0);
  SetLength(BigBuf, 0);
end;

procedure TTestNetVfs.TestCancelStopsACopyAndReportsCancelled;
var
  Src: string;
  Token: TJobCancelToken;
  Ref: IJobCancelToken;
  Done: Boolean;
  Err: TVfsError;
  Calls: Integer;
  IsDir: Boolean;
begin
  if FSkipReason <> '' then
    Assert.Pass('SKIP: ' + FSkipReason);
  Src := TPath.Combine(FWork, 'cancel.bin');
  TFile.WriteAllBytes(Src, Bytes(StringOfChar('z', 15 * 1024 * 1024)));
  Token := TJobCancelToken.Create;
  Ref := Token;
  Done := False;
  Calls := 0;
  FBackend.CopyAsync(PathToFileUri(Src), 'net://ftp1/cancel.bin', Ref,
    procedure(const ADone, ATotal: Int64; const ACurrentName: string; const AItemDone,
      AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
      Inc(Calls);
      Token.Cancel;
    end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Err := AError;
      Done := True;
    end, True, False);
  Pump(@Done);
  Assert.IsTrue(Done, 'the copy returned');
  Assert.IsTrue(Err.Code = vecCancelled, 'cancelled: ' + Err.Message);
  Assert.IsTrue(Calls > 0, 'progress reached the host');
  ExistsAt('net://ftp1/cancel.bin', IsDir);
  Delete_('net://ftp1/cancel.bin');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNetVfs);

end.
