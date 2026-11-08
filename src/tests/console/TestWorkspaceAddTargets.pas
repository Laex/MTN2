unit TestWorkspaceAddTargets;

{ Adding a list of found files to ws:///: already linked targets are skipped and
  equal names get a numeric suffix before the extension. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWorkspaceAddTargets = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SameNamesGetNumberedLinks;
    [Test] procedure LinkedTargetsAreSkipped;
    [Test] procedure DirectoryFlagIsKept;
    [Test] procedure EmptyTargetIsIgnored;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uWorkspaceVfs;

function Target(const APath: string; AIsDir: Boolean = False): TWorkspaceLinkNode;
begin
  Result := Default(TWorkspaceLinkNode);
  Result.TargetURI := PathToFileUri(APath);
  Result.IsDir := AIsDir;
end;

function HasPath(const ANodes: TArray<TWorkspaceLinkNode>; const APath: string): Boolean;
var
  N: TWorkspaceLinkNode;
begin
  for N in ANodes do
    if SameText(N.Path, APath) then
      Exit(True);
  Result := False;
end;

procedure TTestWorkspaceAddTargets.Setup;
begin
  ClearWorkspaceLinks;
end;

procedure TTestWorkspaceAddTargets.TearDown;
begin
  ClearWorkspaceLinks;
end;

procedure TTestWorkspaceAddTargets.SameNamesGetNumberedLinks;
var
  Nodes: TArray<TWorkspaceLinkNode>;
begin
  Assert.AreEqual(3, WorkspaceAddTargets([
    Target('C:\A\main.pas'), Target('C:\B\main.pas'), Target('C:\C\main.pas')]));
  Nodes := WorkspaceExportLinks;
  Assert.IsTrue(HasPath(Nodes, 'main.pas'), 'first keeps its name');
  Assert.IsTrue(HasPath(Nodes, 'main (2).pas'), 'second gets (2) before the extension');
  Assert.IsTrue(HasPath(Nodes, 'main (3).pas'), 'third gets (3)');
end;

procedure TTestWorkspaceAddTargets.LinkedTargetsAreSkipped;
begin
  Assert.AreEqual(1, WorkspaceAddTargets([Target('C:\A\one.txt')]));
  Assert.AreEqual(1, WorkspaceAddTargets([
    Target('C:\A\one.txt'), Target('C:\A\two.txt'), Target('C:\A\two.txt')]),
    'the linked file and a repeat in the same list are skipped');
  Assert.AreEqual(2, WorkspaceLinkCount);
end;

procedure TTestWorkspaceAddTargets.DirectoryFlagIsKept;
var
  Nodes: TArray<TWorkspaceLinkNode>;
begin
  WorkspaceAddTargets([Target('C:\A\src', True), Target('C:\A\a.txt')]);
  Nodes := WorkspaceExportLinks;
  Assert.AreEqual(2, Integer(Length(Nodes)));
  Assert.IsTrue(Nodes[0].IsDir and not Nodes[1].IsDir, 'IsDir follows the input');
  Assert.IsTrue(not Nodes[0].IsVirt, 'a found folder is a link, not a virtual folder');
end;

procedure TTestWorkspaceAddTargets.EmptyTargetIsIgnored;
var
  Empty: TWorkspaceLinkNode;
begin
  Empty := Default(TWorkspaceLinkNode);
  Assert.AreEqual(0, WorkspaceAddTargets([Empty]));
  Assert.AreEqual(0, WorkspaceLinkCount);
end;

end.
