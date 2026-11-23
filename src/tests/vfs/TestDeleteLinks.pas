unit TestDeleteLinks;

{ A permanent delete removes a link to a folder as a single node: the folder
  the link points at keeps its files. The same holds for a link met inside a
  deleted tree and for the source tree of a move that is finished by copy and
  delete. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDeleteLinks = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestDeleteLinkKeepsTargetContents;
    [Test] procedure TestDeleteTreeWithLinkKeepsTargetContents;
    [Test] procedure TestReplacedFolderWithLinkKeepsTargetContents;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Diagnostics,
  uVfsTypes,
  uVfsUtils,
  uFileVfs,
  uPlatformPaths,
  uLinkUtils;

var
  GRoot: string;

function LinkKind: TLinkKind;
begin
  if PlatformPosixPaths then
    Result := lkSymlinkDir
  else
    Result := lkJunction;
end;

function RunPermanentDelete(const APath: string; out AError: TVfsError): Boolean;
var
  Vfs: IVirtualFileSystem;
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
  Watch: TStopwatch;
begin
  Vfs := TFileVirtualFileSystem.Create;
  Ev := TEvent.Create(nil, True, False, '');
  try
    Ok := False;
    Err := TVfsError.Ok;
    Vfs.DeleteAsync(PathToFileUri(APath), vdmPermanent, nil, nil,
      procedure(const ASuccess: Boolean; const AErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AErr;
        Ev.SetEvent;
      end);
    Watch := TStopwatch.StartNew;
    while Ev.WaitFor(20) <> wrSignaled do
    begin
      CheckSynchronize;
      if Watch.ElapsedMilliseconds > 60000 then
      begin
        Assert.Fail('delete timed out');
        Exit(False);
      end;
    end;
    CheckSynchronize;
    AError := Err;
    Result := Ok;
  finally
    Ev.Free;
  end;
end;

procedure MakeTarget(const AName: string; out ATarget, AInside: string);
begin
  ATarget := TPath.Combine(GRoot, AName);
  TDirectory.CreateDirectory(ATarget);
  AInside := TPath.Combine(ATarget, 'inside.txt');
  TFile.WriteAllText(AInside, 'keep me');
end;

procedure TTestDeleteLinks.SetupFixture;
begin
  Randomize;
  GRoot := TPath.Combine(TPath.GetTempPath, 'mtn2_testdeletelinks_' + IntToStr(Random(100000)));
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestDeleteLinks.TearDownFixture;
begin
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestDeleteLinks.TestDeleteLinkKeepsTargetContents;
var
  Target, Inside, Link: string;
  Err: TVfsError;
begin
  MakeTarget('target_a', Target, Inside);
  Link := TPath.Combine(GRoot, 'link_a');
  Assert.IsTrue(CreateFileLink(Link, Target, LinkKind, Err), 'link is created');

  Assert.IsTrue(RunPermanentDelete(Link, Err), 'delete of the link succeeds');
  Assert.IsFalse(IsRecreatableLink(Link), 'the link is gone');
  Assert.IsTrue(TFile.Exists(Inside), 'the folder the link pointed at keeps its file');
end;

procedure TTestDeleteLinks.TestDeleteTreeWithLinkKeepsTargetContents;
var
  Target, Inside, Tree, Link: string;
  Err: TVfsError;
begin
  MakeTarget('target_b', Target, Inside);
  Tree := TPath.Combine(GRoot, 'tree_b');
  TDirectory.CreateDirectory(Tree);
  TFile.WriteAllText(TPath.Combine(Tree, 'own.txt'), 'x');
  Link := TPath.Combine(Tree, 'link_b');
  Assert.IsTrue(CreateFileLink(Link, Target, LinkKind, Err), 'link is created');

  Assert.IsTrue(RunPermanentDelete(Tree, Err), 'delete of the tree succeeds');
  Assert.IsFalse(TDirectory.Exists(Tree), 'the tree is gone');
  Assert.IsTrue(TFile.Exists(Inside), 'the folder the inner link pointed at keeps its file');
end;

procedure TTestDeleteLinks.TestReplacedFolderWithLinkKeepsTargetContents;
var
  Target, Inside, Dest, Staged, Msg: string;
  Err: TVfsError;
begin
  MakeTarget('target_c', Target, Inside);
  Dest := TPath.Combine(GRoot, 'dest_c');
  TDirectory.CreateDirectory(Dest);
  Assert.IsTrue(CreateFileLink(TPath.Combine(Dest, 'link_c'), Target, LinkKind, Err),
    'link is created');
  Staged := TPath.Combine(GRoot, 'staged_c');
  TDirectory.CreateDirectory(Staged);

  Assert.IsTrue(ReplacePathWith(Staged, Dest, Msg), 'replace succeeds: ' + Msg);
  Assert.IsTrue(TFile.Exists(Inside), 'the folder the replaced link pointed at keeps its file');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDeleteLinks);

end.
