unit TestPluginVfs;

{ Permissions of a plugin (uPluginPermissions) and the file system read it unlocks
  (uPluginVfs). }

interface

uses
  DUnitX.TestFramework;

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

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  uPluginManifest, uPluginPermissions, uPluginVfs, uPluginServices;

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

end.
