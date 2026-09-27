unit TestWorkspaceLibrary;

{ Named ws:/// snapshots: save, restore, rename, delete. Uses a temp JSON file. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWorkspaceLibrary = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes,
  uTextEncoding,
  uConfigLocation,
  uWorkspaceVfs,
  uWorkspaceLibrary;

var
  Path, Id: string;
  Nodes, Restored: TArray<TWorkspaceLinkNode>;
  Snaps: TArray<TWorkspaceSnapshot>;

{ TTestWorkspaceLibrary }

procedure TTestWorkspaceLibrary.Run;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-ws-library-test.json');
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  ClearWorkspaceLinks;
  WorkspaceLibraryUsePath(Path);
  WorkspaceLibraryResetForTests;

  Assert.IsTrue(not WorkspaceLiveHasLinks, 'live starts empty');
  Assert.IsTrue(not WorkspaceLiveIsDirty, 'empty live is not dirty');
  Assert.IsTrue(not WorkspaceLibrarySaveCurrent('Delphi'), 'refuse empty save');

  SetLength(Nodes, 2);
  Nodes[0].Path := 'work';
  Nodes[0].TargetURI := PathToFileUri('C:\Work');
  Nodes[0].IsDir := True;
  Nodes[0].IsVirt := False;
  Nodes[1].Path := 'group';
  Nodes[1].TargetURI := '';
  Nodes[1].IsDir := True;
  Nodes[1].IsVirt := True;
  WorkspaceImportLinks(Nodes);
  Assert.IsTrue(WorkspaceLiveHasLinks, 'imported nodes');
  Assert.IsTrue(WorkspaceLiveIsDirty, 'imported live is dirty until save');
  Assert.IsTrue(WorkspaceLibrarySaveCurrent('Delphi'), 'save named snapshot');
  Assert.IsTrue(not WorkspaceLiveIsDirty, 'saved live is clean');
  Assert.IsTrue(WorkspaceLiveName = 'Delphi', 'bound name');
  Id := WorkspaceLiveId;
  Assert.IsTrue(Id <> '', 'bound id');

  ClearWorkspaceLinks;
  Assert.IsTrue(WorkspaceLiveIsDirty, 'clear after save is dirty');
  Assert.IsTrue(WorkspaceLibraryRestore(Id), 'restore by id');
  Restored := WorkspaceExportLinks;
  Assert.IsTrue(Length(Restored) = 2, 'restore node count');
  Assert.IsTrue(SameText(Restored[0].Path, 'work') or SameText(Restored[1].Path, 'work'),
    'restore contains work');
  Assert.IsTrue(not WorkspaceLiveIsDirty, 'restored live is clean');

  WorkspaceLibraryRename(Id, 'Docs');
  Assert.IsTrue(WorkspaceLiveName = 'Docs', 'rename updates bound name');
  Snaps := WorkspaceLibraryGet;
  Assert.IsTrue(Length(Snaps) = 1, 'one snapshot in library');
  Assert.IsTrue(Snaps[0].Name = 'Docs', 'library name after rename');

  WorkspaceLibraryDelete(Id);
  Snaps := WorkspaceLibraryGet;
  Assert.IsTrue(Length(Snaps) = 0, 'library empty after delete');
  Assert.IsTrue(WorkspaceLiveId = '', 'delete unbinds');
  Assert.IsTrue(Length(WorkspaceExportLinks) = 2, 'delete snapshot keeps live links');

  if TFile.Exists(Path) then
    TFile.Delete(Path);
  ClearWorkspaceLinks;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWorkspaceLibrary);

end.
