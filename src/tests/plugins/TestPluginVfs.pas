unit TestPluginVfs;

{ Permissions of a plugin (uPluginPermissions) and the file system read it unlocks
  (uPluginVfs). }

interface

uses
  System.SysUtils, DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginPermissions = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestManifestListsPermissions;
    [Test] procedure TestAPermissionNeedsTheManifestAndTheGrant;
    [Test] procedure TestUnknownPermissionsAreDropped;
    [Test] procedure TestGrantsAreRemembered;
    [Test] procedure TestGrantAllAndTakeBack;
    [Test] procedure TestMalformedGrantFileGrantsNothing;
  end;

  [TestFixture]
  TTestPluginVfs = class
  private
    FRoot: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestRefusedWithoutThePermission;
    [Test] procedure TestListsAFolder;
    [Test] procedure TestExistsTellsFilesFoldersAndMissing;
    [Test] procedure TestReadsAFile;
    [Test] procedure TestMissingFileReportsNotFound;
    [Test] procedure TestTooLargeFileIsNotRead;
    [Test] procedure TestCallbackComesAfterTheStartCallReturns;
    [Test] procedure TestUnloadedPluginHearsNothing;
    [Test] procedure TestBadArgumentsAreRefused;
  end;

  [TestFixture]
  TTestPluginVfsStream = class
  private
    FRoot: string;
    FData: TBytes;
    function LocalUri: string;
    function OpenAndWait(const AUri: string; out AStatus: Integer): Int64;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestLocalFileReadsInPieces;
    [Test] procedure TestReadsFromSeveralThreadsAtOnce;
    [Test] procedure TestRefusedWithoutThePermission;
    [Test] procedure TestMissingFileReportsNotFound;
    [Test] procedure TestBadArgumentsAreRefused;
    [Test] procedure TestAPluginHoldsAtMostSixteenFiles;
    [Test] procedure TestAnotherPluginCannotUseTheHandle;
    [Test] procedure TestCloseWhileAnotherThreadReadsIsSafe;
    [Test] procedure TestOtherSchemeIsCopiedToATemporaryFile;
    [Test] procedure TestFailedCopyReportsTheStatusAndLeavesNoFile;
    [Test] procedure TestSlowCopyShowsProgressUntilItEnds;
    [Test] procedure TestUnloadClosesTheFiles;
    [Test] procedure TestUnloadDuringACopyDropsTheResult;
    [Test] procedure TestCancelledCopyReportsCancelledAndLeavesNoFile;
    [Test] procedure TestCancelOfALocalOpenDropsTheFile;
    [Test] procedure TestCancelNeedsALiveJobOfTheCaller;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.SyncObjs,
  uPluginManifest, uPluginPermissions, uPluginVfs, uPluginServices, uVfsTypes, uTextEncoding, uNotice;

const
  cId = 't.vfs';

{ TTestPluginPermissions }

procedure TTestPluginPermissions.TearDown;
begin
  ClearPermissionGrants;
  PluginPermissionsDeclare(cId, nil);
end;

procedure TTestPluginPermissions.TestManifestListsPermissions;
var
  M: TPluginManifest;
begin
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"a","permissions":[" VFS.read ","x.y",7]}', M));
  Assert.IsTrue(Length(M.Permissions) = 2, 'strings only');
  Assert.AreEqual('vfs.read', M.Permissions[0], 'trimmed and lower-cased');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"a"}', M));
  Assert.IsTrue(Length(M.Permissions) = 0, 'none by default');
end;

procedure TTestPluginPermissions.TestAPermissionNeedsTheManifestAndTheGrant;
begin
  Assert.IsFalse(PluginHasPermission(cId, cPermVfsRead), 'neither');
  PluginPermissionGrant(cId, cPermVfsRead, True);
  Assert.IsFalse(PluginHasPermission(cId, cPermVfsRead), 'a grant alone is not enough');
  PluginPermissionGrant(cId, cPermVfsRead, False);
  PluginPermissionsDeclare(cId, [cPermVfsRead]);
  Assert.IsFalse(PluginHasPermission(cId, cPermVfsRead), 'asking alone is not enough');
  PluginPermissionGrant(cId, cPermVfsRead, True);
  Assert.IsTrue(PluginHasPermission(cId, cPermVfsRead), 'both');
  Assert.IsTrue(PluginHasPermission('T.VFS', 'VFS.READ'), 'case does not matter');
  PluginPermissionsDeclare(cId, nil);
  Assert.IsFalse(PluginHasPermission(cId, cPermVfsRead), 'a manifest that stops asking drops it');
end;

procedure TTestPluginPermissions.TestUnknownPermissionsAreDropped;
begin
  PluginPermissionsDeclare(cId, ['vfs.read', 'vfs.nuke', '']);
  Assert.IsTrue(Length(PluginPermissionsDeclared(cId)) = 1, 'length');
  PluginPermissionGrant(cId, 'vfs.nuke', True);
  Assert.IsFalse(PluginPermissionGranted(cId, 'vfs.nuke'), 'nothing unknown is granted');
end;

procedure TTestPluginPermissions.TestGrantsAreRemembered;
var
  F: string;
begin
  F := TPath.Combine(TPath.GetTempPath, 'mtn2-perm-' + TPath.GetGUIDFileName(False) + '.json');
  try
    PluginPermissionGrant(cId, cPermVfsRead, True);
    SavePermissionGrants(F);
    ClearPermissionGrants;
    Assert.IsFalse(PluginPermissionGranted(cId, cPermVfsRead), 'cleared');
    LoadPermissionGrants(F);
    Assert.IsTrue(PluginPermissionGranted(cId, cPermVfsRead), 'back from the file');
    PluginPermissionGrant(cId, cPermVfsRead, False);
    SavePermissionGrants(F);
    Assert.IsFalse(TFile.Exists(F), 'no grants, no file');
  finally
    if TFile.Exists(F) then
      TFile.Delete(F);
  end;
end;

procedure TTestPluginPermissions.TestGrantAllAndTakeBack;
begin
  Assert.IsFalse(PluginPermissionsAllGranted(cId), 'nothing asked is not "all granted"');
  PluginPermissionsDeclare(cId, [cPermVfsRead]);
  Assert.IsFalse(PluginPermissionsAllGranted(cId));
  PluginPermissionsGrantAll(cId, True);
  Assert.IsTrue(PluginPermissionsAllGranted(cId));
  PluginPermissionsGrantAll(cId, False);
  Assert.IsFalse(PluginPermissionGranted(cId, cPermVfsRead));
end;

procedure TTestPluginPermissions.TestMalformedGrantFileGrantsNothing;
var
  F: string;
begin
  F := TPath.Combine(TPath.GetTempPath, 'mtn2-perm-' + TPath.GetGUIDFileName(False) + '.json');
  try
    TFile.WriteAllText(F, '{"grant": [1, 2', TEncoding.UTF8);
    PluginPermissionGrant(cId, cPermVfsRead, True);
    LoadPermissionGrants(F);
    Assert.IsFalse(PluginPermissionGranted(cId, cPermVfsRead), 'a broken file leaves no grants');
    TFile.WriteAllText(F, '{"grant": {"t.vfs": ["vfs.read", "vfs.nuke"]}}', TEncoding.UTF8);
    LoadPermissionGrants(F);
    Assert.IsTrue(PluginPermissionGranted(cId, cPermVfsRead));
    Assert.IsFalse(PluginPermissionGranted(cId, 'vfs.nuke'), 'unknown names are ignored');
  finally
    if TFile.Exists(F) then
      TFile.Delete(F);
  end;
end;

{ TTestPluginVfs }

type
  TWaiter = class
    Done: Boolean;
    Status: Integer;
    Text: string;
    Data: TBytes;
    Handle: Int64;
    Calls: Integer;
    procedure Wait;
  end;

procedure TWaiter.Wait;
var
  I: Integer;
begin
  for I := 1 to 200 do
  begin
    if Done then
      Exit;
    CheckSynchronize(25);
  end;
end;

procedure TTestPluginVfs.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-pvfs-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'sub'));
  TFile.WriteAllText(TPath.Combine(FRoot, 'a.txt'), 'hello' + #10 + 'world', TEncoding.ASCII);
  PluginPermissionsDeclare(cId, [cPermVfsRead]);
  PluginPermissionGrant(cId, cPermVfsRead, True);
end;

procedure TTestPluginVfs.TearDown;
begin
  ClearPermissionGrants;
  PluginPermissionsDeclare(cId, nil);
  PluginEventsUnregister(cId);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function FileUriOf(const APath: string): string;
begin
  Result := 'file:///' + StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

procedure TTestPluginVfs.TestRefusedWithoutThePermission;
var
  W: TWaiter;
begin
  W := TWaiter.Create;
  try
    PluginPermissionGrant(cId, cPermVfsRead, False);
    Assert.AreEqual(cPluginVfsNoPermission, PluginVfsList(cId, FileUriOf(FRoot),
      procedure(AStatus: Integer; const AText: string)
      begin
        Inc(W.Calls);
      end), 'list');
    Assert.AreEqual(cPluginVfsNoPermission, PluginVfsExists(cId, FileUriOf(FRoot),
      procedure(AStatus: Integer; const AText: string)
      begin
        Inc(W.Calls);
      end), 'exists');
    Assert.AreEqual(cPluginVfsNoPermission, PluginVfsRead(cId, FileUriOf(TPath.Combine(FRoot, 'a.txt')), 0,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        Inc(W.Calls);
      end), 'read');
    CheckSynchronize(100);
    Assert.AreEqual(0, W.Calls, 'no callback follows a refusal');
    PluginPermissionGrant(cId, cPermVfsRead, True);
    PluginPermissionsDeclare(cId, nil);
    Assert.AreEqual(cPluginVfsNoPermission, PluginVfsExists(cId, FileUriOf(FRoot),
      procedure(AStatus: Integer; const AText: string)
      begin
      end), 'a grant without the manifest is refused too');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestListsAFolder;
var
  W: TWaiter;
  Root: TJSONValue;
  Entries: TJSONArray;
  I: Integer;
  SawFile, SawDir: Boolean;
begin
  W := TWaiter.Create;
  try
    Assert.AreEqual(0, PluginVfsList(cId, FileUriOf(FRoot),
      procedure(AStatus: Integer; const AText: string)
      begin
        W.Status := AStatus;
        W.Text := AText;
        W.Done := True;
      end));
    W.Wait;
    Assert.IsTrue(W.Done, 'the callback came');
    Assert.AreEqual(cPluginVfsOk, W.Status);
    Root := TJSONObject.ParseJSONValue(W.Text);
    try
      Entries := Root.GetValue<TJSONArray>('entries');
      Assert.AreEqual(2, Entries.Count, 'a file and a folder');
      SawFile := False;
      SawDir := False;
      for I := 0 to Entries.Count - 1 do
      begin
        if Entries.Items[I].GetValue<string>('name') = 'a.txt' then
        begin
          SawFile := not Entries.Items[I].GetValue<Boolean>('dir');
          Assert.AreEqual(Int64(11), Entries.Items[I].GetValue<Int64>('size'), 'size in bytes');
          Assert.IsTrue(Pos('a.txt', Entries.Items[I].GetValue<string>('uri')) > 0, 'a URI to pass back');
        end
        else if Entries.Items[I].GetValue<string>('name') = 'sub' then
          SawDir := Entries.Items[I].GetValue<Boolean>('dir');
      end;
      Assert.IsTrue(SawFile and SawDir, 'both are described');
    finally
      Root.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestExistsTellsFilesFoldersAndMissing;
var
  W: TWaiter;

  function Ask(const AUri: string): string;
  begin
    W.Done := False;
    Assert.AreEqual(0, PluginVfsExists(cId, AUri,
      procedure(AStatus: Integer; const AText: string)
      begin
        W.Text := AText;
        W.Done := True;
      end));
    W.Wait;
    Result := W.Text;
  end;

begin
  W := TWaiter.Create;
  try
    Assert.AreEqual('{"exists":true,"dir":true}', Ask(FileUriOf(FRoot)), 'a folder');
    Assert.AreEqual('{"exists":true,"dir":false}', Ask(FileUriOf(TPath.Combine(FRoot, 'a.txt'))), 'a file');
    Assert.AreEqual('{"exists":false,"dir":false}', Ask(FileUriOf(TPath.Combine(FRoot, 'none'))), 'nothing');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestReadsAFile;
var
  W: TWaiter;
begin
  W := TWaiter.Create;
  try
    Assert.AreEqual(0, PluginVfsRead(cId, FileUriOf(TPath.Combine(FRoot, 'a.txt')), 0,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        W.Status := AStatus;
        W.Data := AData;
        W.Done := True;
      end));
    W.Wait;
    Assert.IsTrue(W.Done);
    Assert.AreEqual(cPluginVfsOk, W.Status);
    Assert.AreEqual('hello' + #10 + 'world', TEncoding.UTF8.GetString(W.Data), 'the bytes of the file');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestMissingFileReportsNotFound;
var
  W: TWaiter;
begin
  W := TWaiter.Create;
  try
    PluginVfsRead(cId, FileUriOf(TPath.Combine(FRoot, 'none.txt')), 0,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        W.Status := AStatus;
        W.Done := True;
        Assert.IsTrue(Length(AData) = 0, 'no bytes with an error');
      end);
    W.Wait;
    Assert.AreEqual(cPluginVfsNotFound, W.Status);
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestTooLargeFileIsNotRead;
var
  W: TWaiter;
begin
  W := TWaiter.Create;
  try
    PluginVfsRead(cId, FileUriOf(TPath.Combine(FRoot, 'a.txt')), 5,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        W.Status := AStatus;
        W.Done := True;
      end);
    W.Wait;
    Assert.AreEqual(cPluginVfsNotSupported, W.Status, 'an 11 byte file does not fit 5 bytes');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestCallbackComesAfterTheStartCallReturns;
var
  W: TWaiter;
  Returned: Boolean;
  Early: Boolean;
begin
  W := TWaiter.Create;
  try
    Returned := False;
    Early := False;
    // A scheme nobody serves answers at once; the plugin still hears it after the call returned.
    PluginVfsExists(cId, 'nosuchscheme://x/y',
      procedure(AStatus: Integer; const AText: string)
      begin
        Early := not Returned;
        W.Done := True;
      end);
    Returned := True;
    W.Wait;
    Assert.IsTrue(W.Done, 'the callback came');
    Assert.IsFalse(Early, 'not from inside the start call');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestUnloadedPluginHearsNothing;
var
  W: TWaiter;
begin
  W := TWaiter.Create;
  try
    PluginVfsRead(cId, FileUriOf(TPath.Combine(FRoot, 'a.txt')), 0,
      procedure(AStatus: Integer; const AData: TBytes)
      begin
        Inc(W.Calls);
      end);
    PluginEventsUnregister(cId);
    CheckSynchronize(300);
    Sleep(100);
    CheckSynchronize(300);
    Assert.AreEqual(0, W.Calls, 'the plugin went before the answer');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfs.TestBadArgumentsAreRefused;
begin
  Assert.AreEqual(-1, PluginVfsList('', 'file:///C:/', procedure(S: Integer; const T: string) begin end));
  Assert.AreEqual(-1, PluginVfsList(cId, '', procedure(S: Integer; const T: string) begin end));
  Assert.AreEqual(-1, PluginVfsRead(cId, 'file:///C:/', 0, nil));
end;

{ TTestPluginVfsStream }

type
  /// <summary>Serves any other scheme by "copying" a fixed payload to the target file.</summary>
  TFakeVfs = class(TInterfacedObject, IVirtualFileSystem)
  public
    Payload: TBytes;
    DelayMs: Integer;
    FailCode: TVfsErrorCode;
    Gate: TEvent;
    LastTarget: string;
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

procedure TFakeVfs.ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsListCallback);
begin
end;

procedure TFakeVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback);
begin
end;

procedure TFakeVfs.CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsBoolCallback);
begin
end;

procedure TFakeVfs.CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback; AOverwrite,
  APreserveTimestamps: Boolean);
var
  Target: string;
  Data: TBytes;
  Fail: TVfsErrorCode;
  Delay: Integer;
  GateEvent: TEvent;
begin
  Target := FileUriToPath(AToURI);
  LastTarget := Target;
  Data := Payload;
  Fail := FailCode;
  Delay := DelayMs;
  GateEvent := Gate;
  TThread.CreateAnonymousThread(
    procedure
    begin
      if GateEvent <> nil then
        GateEvent.WaitFor(5000);
      if Delay > 0 then
      begin
        Sleep(Delay);
        if Assigned(AOnProgress) then
          AOnProgress(Length(Data) div 2, Length(Data), 'clip', Length(Data) div 2,
            Length(Data), AFromURI, AToURI);
        Sleep(50);
      end;
      if (ACancel <> nil) and ACancel.IsCancellationRequested then
        AOnDone(False, TVfsError.Make(vecCancelled, 'cancelled', AFromURI))
      else if Fail <> vecOk then
        AOnDone(False, TVfsError.Make(Fail, 'failed', AFromURI))
      else
      begin
        TFile.WriteAllBytes(Target, Data);
        AOnDone(True, TVfsError.Ok);
      end;
    end).Start;
end;

procedure TFakeVfs.MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback; AOverwrite,
  APreserveTimestamps: Boolean);
begin
end;

procedure TFakeVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
end;

procedure TFakeVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
end;

procedure TFakeVfs.WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
end;

procedure TFakeVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
end;

procedure TFakeVfs.GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsFreeSpaceCallback);
begin
end;

var
  GFake: TFakeVfs;
  GFakeRef: IVirtualFileSystem;

procedure Pump(AMs: Integer);
var
  I: Integer;
begin
  for I := 1 to AMs div 25 do
    CheckSynchronize(25);
end;

procedure TTestPluginVfsStream.Setup;
var
  I: Integer;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-pvfs-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FRoot);
  SetLength(FData, 100000);
  for I := 0 to High(FData) do
    FData[I] := Byte((I * 7 + 3) mod 251);
  TFile.WriteAllBytes(TPath.Combine(FRoot, 'big.bin'), FData);
  PluginPermissionsDeclare(cId, [cPermVfsRead]);
  PluginPermissionGrant(cId, cPermVfsRead, True);
  GFake := TFakeVfs.Create;
  GFakeRef := GFake;
  GFake.Payload := FData;
  SetPluginVfs(GFakeRef);
end;

procedure TTestPluginVfsStream.TearDown;
begin
  PluginVfsStreamsRelease(cId);
  Pump(100);
  SetPluginVfs(nil);
  GFakeRef := nil;
  GFake := nil;
  ClearPermissionGrants;
  PluginPermissionsDeclare(cId, nil);
  PluginEventsUnregister(cId);
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

function TTestPluginVfsStream.LocalUri: string;
begin
  Result := FileUriOf(TPath.Combine(FRoot, 'big.bin'));
end;

function TTestPluginVfsStream.OpenAndWait(const AUri: string; out AStatus: Integer): Int64;
var
  W: TWaiter;
  Job: Int64;
begin
  W := TWaiter.Create;
  try
    Job := PluginVfsOpen(cId, AUri,
      procedure(AOpenStatus: Integer; AHandle: Int64)
      begin
        W.Status := AOpenStatus;
        W.Handle := AHandle;
        W.Done := True;
      end);
    Assert.IsTrue(Job > 0, 'started: the number of the job');
    W.Wait;
    Assert.IsTrue(W.Done, 'the callback came');
    AStatus := W.Status;
    Result := W.Handle;
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfsStream.TestLocalFileReadsInPieces;
var
  H: Int64;
  St: Integer;
  Buf: TBytes;
begin
  H := OpenAndWait(LocalUri, St);
  Assert.AreEqual(cPluginVfsOk, St);
  Assert.IsTrue(H > 0, 'a handle');
  Assert.AreEqual(Int64(Length(FData)), PluginVfsSize(cId, H), 'size');
  SetLength(Buf, 100);
  Assert.AreEqual(Int64(100), PluginVfsReadAt(cId, H, 500, @Buf[0], 100), 'a piece from the middle');
  Assert.IsTrue(CompareMem(@Buf[0], @FData[500], 100), 'the bytes of that piece');
  Assert.AreEqual(Int64(10), PluginVfsReadAt(cId, H, Length(FData) - 10, @Buf[0], 100),
    'a short read at the end');
  Assert.IsTrue(CompareMem(@Buf[0], @FData[Length(FData) - 10], 10), 'the last bytes');
  Assert.AreEqual(Int64(0), PluginVfsReadAt(cId, H, Length(FData), @Buf[0], 100), 'at the end');
  Assert.AreEqual(Int64(0), PluginVfsReadAt(cId, H, Length(FData) + 5000, @Buf[0], 100), 'past the end');
  Assert.AreEqual(Int64(0), PluginVfsClose(cId, H), 'closed');
  Assert.AreEqual(Int64(-1), PluginVfsSize(cId, H), 'size of a closed file');
  Assert.AreEqual(Int64(-1), PluginVfsReadAt(cId, H, 0, @Buf[0], 100), 'read of a closed file');
  Assert.AreEqual(Int64(-1), PluginVfsClose(cId, H), 'closed twice');
end;

procedure TTestPluginVfsStream.TestReadsFromSeveralThreadsAtOnce;
const
  cThreads = 4;
  cReads = 300;
var
  H: Int64;
  St, T: Integer;
  Threads: array[0..cThreads - 1] of TThread;
  Failures: Integer;
  Data: TBytes;

  function StartReader(ASeed: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        I, Off: Integer;
        Buf: TBytes;
      begin
        SetLength(Buf, 256);
        for I := 0 to cReads - 1 do
        begin
          Off := (I * 331 + ASeed * 977) mod (Length(Data) - 256);
          if (PluginVfsReadAt(cId, H, Off, @Buf[0], 256) <> 256) or
             not CompareMem(@Buf[0], @Data[Off], 256) then
            TInterlocked.Increment(Failures);
        end;
      end);
    Result.FreeOnTerminate := False;
    Result.Start;
  end;

begin
  Data := FData;
  Failures := 0;
  H := OpenAndWait(LocalUri, St);
  Assert.IsTrue(H > 0);
  for T := 0 to cThreads - 1 do
    Threads[T] := StartReader(T + 1);
  for T := 0 to cThreads - 1 do
  begin
    Threads[T].WaitFor;
    Threads[T].Free;
  end;
  Assert.AreEqual(0, Failures, 'every thread got its own bytes');
  PluginVfsClose(cId, H);
end;

procedure TTestPluginVfsStream.TestRefusedWithoutThePermission;
var
  Calls: Integer;
begin
  Calls := 0;
  PluginPermissionGrant(cId, cPermVfsRead, False);
  Assert.AreEqual(Int64(cPluginVfsNoPermission), PluginVfsOpen(cId, LocalUri,
    procedure(AStatus: Integer; AHandle: Int64)
    begin
      Inc(Calls);
    end));
  Pump(100);
  Assert.AreEqual(0, Calls, 'no callback follows a refusal');
end;

procedure TTestPluginVfsStream.TestMissingFileReportsNotFound;
var
  H: Int64;
  St: Integer;
begin
  H := OpenAndWait(FileUriOf(TPath.Combine(FRoot, 'none.bin')), St);
  Assert.AreEqual(cPluginVfsNotFound, St);
  Assert.AreEqual(Int64(0), H, 'no handle');
end;

procedure TTestPluginVfsStream.TestBadArgumentsAreRefused;
var
  Buf: array[0..3] of Byte;
  H: Int64;
  St: Integer;
begin
  Assert.AreEqual(Int64(-1), PluginVfsOpen('', LocalUri, procedure(S: Integer; H: Int64) begin end));
  Assert.AreEqual(Int64(-1), PluginVfsOpen(cId, '', procedure(S: Integer; H: Int64) begin end));
  Assert.AreEqual(Int64(-1), PluginVfsOpen(cId, LocalUri, nil));
  H := OpenAndWait(LocalUri, St);
  Assert.AreEqual(Int64(-1), PluginVfsReadAt(cId, H, -1, @Buf[0], 4), 'negative offset');
  Assert.AreEqual(Int64(-1), PluginVfsReadAt(cId, H, 0, @Buf[0], -4), 'negative size');
  Assert.AreEqual(Int64(-1), PluginVfsReadAt(cId, H, 0, nil, 4), 'no buffer');
  Assert.AreEqual(Int64(0), PluginVfsReadAt(cId, H, 0, @Buf[0], 0), 'nothing asked');
  Assert.AreEqual(Int64(-1), PluginVfsSize(cId, 12345), 'unknown handle');
  PluginVfsClose(cId, H);
end;

procedure TTestPluginVfsStream.TestAPluginHoldsAtMostSixteenFiles;
var
  Handles: array[0..cPluginVfsMaxOpen - 1] of Int64;
  I, St: Integer;
  Calls: Integer;
begin
  for I := 0 to cPluginVfsMaxOpen - 1 do
    Handles[I] := OpenAndWait(LocalUri, St);
  Calls := 0;
  Assert.AreEqual(Int64(cPluginVfsTooManyOpen), PluginVfsOpen(cId, LocalUri,
    procedure(AStatus: Integer; AHandle: Int64)
    begin
      Inc(Calls);
    end), 'the seventeenth');
  Pump(100);
  Assert.AreEqual(0, Calls, 'no callback follows a refusal');
  PluginVfsClose(cId, Handles[0]);
  Handles[0] := OpenAndWait(LocalUri, St);
  Assert.IsTrue(Handles[0] > 0, 'a closed file frees a place');
  for I := 0 to cPluginVfsMaxOpen - 1 do
    PluginVfsClose(cId, Handles[I]);
end;

procedure TTestPluginVfsStream.TestAnotherPluginCannotUseTheHandle;
var
  H: Int64;
  St: Integer;
  Buf: array[0..3] of Byte;
begin
  H := OpenAndWait(LocalUri, St);
  Assert.AreEqual(Int64(-1), PluginVfsSize('t.other', H), 'size');
  Assert.AreEqual(Int64(-1), PluginVfsReadAt('t.other', H, 0, @Buf[0], 4), 'read');
  Assert.AreEqual(Int64(-1), PluginVfsClose('t.other', H), 'close');
  Assert.AreEqual(Int64(Length(FData)), PluginVfsSize('T.VFS', H), 'the owner, in any case');
  PluginVfsClose(cId, H);
end;

procedure TTestPluginVfsStream.TestCloseWhileAnotherThreadReadsIsSafe;
var
  H: Int64;
  St: Integer;
  Reader: TThread;
  Crashed: Boolean;
  SawClosed: Boolean;
begin
  Crashed := False;
  SawClosed := False;
  H := OpenAndWait(LocalUri, St);
  Reader := TThread.CreateAnonymousThread(
    procedure
    var
      Buf: TBytes;
      I: Integer;
      N: Int64;
    begin
      SetLength(Buf, 4096);
      try
        for I := 1 to 200000 do
        begin
          N := PluginVfsReadAt(cId, H, (I * 4096) mod 90000, @Buf[0], 4096);
          if N < 0 then
          begin
            SawClosed := True;
            Break;
          end;
        end;
      except
        Crashed := True;
      end;
    end);
  Reader.FreeOnTerminate := False;
  Reader.Start;
  Sleep(5);
  Assert.AreEqual(Int64(0), PluginVfsClose(cId, H), 'closed while it reads');
  Reader.WaitFor;
  Reader.Free;
  Assert.IsFalse(Crashed, 'the reader did not fail');
  Assert.IsTrue(SawClosed, 'the reader saw the file go');
end;

procedure TTestPluginVfsStream.TestOtherSchemeIsCopiedToATemporaryFile;
var
  H: Int64;
  St: Integer;
  Target: string;
  Buf: TBytes;
begin
  H := OpenAndWait('fake://host/folder/clip.mp4', St);
  Assert.AreEqual(cPluginVfsOk, St);
  Assert.IsTrue(H > 0, 'a handle');
  Target := GFake.LastTarget;
  Assert.IsTrue(TFile.Exists(Target), 'the copy exists while the file is open');
  Assert.AreEqual('.mp4', ExtractFileExt(Target), 'it keeps the extension');
  Assert.AreEqual(Int64(Length(FData)), PluginVfsSize(cId, H), 'size');
  SetLength(Buf, 64);
  Assert.AreEqual(Int64(64), PluginVfsReadAt(cId, H, 1000, @Buf[0], 64));
  Assert.IsTrue(CompareMem(@Buf[0], @FData[1000], 64), 'the bytes of the source');
  Assert.AreEqual(Int64(0), PluginVfsClose(cId, H));
  Assert.IsFalse(TFile.Exists(Target), 'closing deletes the copy');
end;

procedure TTestPluginVfsStream.TestFailedCopyReportsTheStatusAndLeavesNoFile;
var
  H: Int64;
  St: Integer;
begin
  GFake.FailCode := vecAccessDenied;
  H := OpenAndWait('fake://host/clip.mp4', St);
  Assert.AreEqual(cPluginVfsAccessDenied, St);
  Assert.AreEqual(Int64(0), H, 'no handle');
  Assert.IsFalse(TFile.Exists(GFake.LastTarget), 'nothing left behind');
end;

procedure TTestPluginVfsStream.TestSlowCopyShowsProgressUntilItEnds;
var
  H: Int64;
  St: Integer;
  Shown, Dismissed: string;
begin
  GFake.DelayMs := 450;
  SetNoticeHandler(
    procedure(const ARequest: TNoticeRequest)
    begin
      Shown := Shown + ARequest.Arg + '|';
    end,
    procedure(const ATag: string)
    begin
      Dismissed := Dismissed + ATag + '|';
    end);
  try
    H := OpenAndWait('fake://host/clip.mp4', St);
    Assert.AreEqual(cPluginVfsOk, St);
    Assert.IsTrue(Pos('clip.mp4', Shown) > 0, 'the notice names the file: ' + Shown);
    Assert.IsTrue(Pos('50%', Shown) > 0, 'with the percentage: ' + Shown);
    Assert.IsTrue(Pos('t.vfs:vfs-open-', Dismissed) > 0, 'dismissed when the copy ended');
    PluginVfsClose(cId, H);
  finally
    SetNoticeHandler(nil);
  end;
end;

procedure TTestPluginVfsStream.TestUnloadClosesTheFiles;
var
  A, B: Int64;
  St: Integer;
begin
  A := OpenAndWait(LocalUri, St);
  B := OpenAndWait(LocalUri, St);
  PluginVfsStreamsRelease(cId);
  Assert.AreEqual(Int64(-1), PluginVfsSize(cId, A), 'first');
  Assert.AreEqual(Int64(-1), PluginVfsSize(cId, B), 'second');
end;

procedure TTestPluginVfsStream.TestUnloadDuringACopyDropsTheResult;
var
  Calls: Integer;
  Gate: TEvent;
begin
  Calls := 0;
  Gate := TEvent.Create(nil, True, False, '');
  try
    GFake.Gate := Gate;
    Assert.IsTrue(PluginVfsOpen(cId, 'fake://host/clip.mp4',
      procedure(AStatus: Integer; AHandle: Int64)
      begin
        Inc(Calls);
      end) > 0);
    PluginEventsUnregister(cId);
    PluginVfsStreamsRelease(cId);
    Gate.SetEvent;
    Pump(600);
    Assert.AreEqual(0, Calls, 'the plugin went before the answer');
    Assert.IsFalse(TFile.Exists(GFake.LastTarget), 'the copy is not left behind');
    GFake.Gate := nil;
  finally
    Gate.Free;
  end;
end;

procedure TTestPluginVfsStream.TestCancelledCopyReportsCancelledAndLeavesNoFile;
var
  W: TWaiter;
  Gate: TEvent;
  Job: Int64;
begin
  W := TWaiter.Create;
  Gate := TEvent.Create(nil, True, False, '');
  try
    GFake.Gate := Gate;
    Job := PluginVfsOpen(cId, 'fake://host/clip.mp4',
      procedure(AStatus: Integer; AHandle: Int64)
      begin
        W.Status := AStatus;
        W.Handle := AHandle;
        Inc(W.Calls);
        W.Done := True;
      end);
    Assert.IsTrue(Job > 0);
    Assert.AreEqual(Int64(0), PluginVfsCancel(cId, Job), 'cancelled');
    Gate.SetEvent;
    W.Wait;
    Assert.IsTrue(W.Done, 'the callback still follows');
    Assert.AreEqual(cPluginVfsCancelled, W.Status);
    Assert.AreEqual(Int64(0), W.Handle, 'no handle');
    Pump(100);
    Assert.AreEqual(1, W.Calls, 'once');
    Assert.IsFalse(TFile.Exists(GFake.LastTarget), 'the copy is not left behind');
    Assert.AreEqual(Int64(-1), PluginVfsCancel(cId, Job), 'a finished job is gone');
    GFake.Gate := nil;
  finally
    Gate.Free;
    W.Free;
  end;
end;

procedure TTestPluginVfsStream.TestCancelOfALocalOpenDropsTheFile;
var
  W: TWaiter;
  Job: Int64;
begin
  W := TWaiter.Create;
  try
    Job := PluginVfsOpen(cId, LocalUri,
      procedure(AStatus: Integer; AHandle: Int64)
      begin
        W.Status := AStatus;
        W.Handle := AHandle;
        W.Done := True;
      end);
    Assert.AreEqual(Int64(0), PluginVfsCancel(cId, Job), 'cancelled before the callback');
    W.Wait;
    Assert.AreEqual(cPluginVfsCancelled, W.Status);
    Assert.AreEqual(Int64(0), W.Handle, 'the opened file was dropped');
  finally
    W.Free;
  end;
end;

procedure TTestPluginVfsStream.TestCancelNeedsALiveJobOfTheCaller;
var
  Gate: TEvent;
  Job: Int64;
begin
  Assert.AreEqual(Int64(-1), PluginVfsCancel(cId, 987654), 'unknown job');
  Gate := TEvent.Create(nil, True, False, '');
  try
    GFake.Gate := Gate;
    Job := PluginVfsOpen(cId, 'fake://host/clip.mp4',
      procedure(AStatus: Integer; AHandle: Int64)
      begin
      end);
    Assert.AreEqual(Int64(-1), PluginVfsCancel('t.other', Job), 'another plugin cannot cancel it');
    Gate.SetEvent;
    Pump(300);
    GFake.Gate := nil;
  finally
    Gate.Free;
  end;
end;

end.
