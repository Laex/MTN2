program TestWorkspaceLibrary;

{$APPTYPE CONSOLE}

{ Named ws:/// snapshots: save, restore, rename, delete. Uses a temp JSON file. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uConfigLocation in '..\..\Core\uConfigLocation.pas',
  uWorkspaceVfs in '..\..\Core\uWorkspaceVfs.pas',
  uWorkspaceLibrary in '..\..\Core\uWorkspaceLibrary.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
end;

var
  Path, Id: string;
  Nodes, Restored: TArray<TWorkspaceLinkNode>;
  Snaps: TArray<TWorkspaceSnapshot>;
begin
  try
    Path := TPath.Combine(TPath.GetTempPath, 'mtn2-ws-library-test.json');
    if TFile.Exists(Path) then
      TFile.Delete(Path);
    ClearWorkspaceLinks;
    WorkspaceLibraryUsePath(Path);
    WorkspaceLibraryResetForTests;

    Expect(not WorkspaceLiveHasLinks, 'live starts empty');
    Expect(not WorkspaceLiveIsDirty, 'empty live is not dirty');
    Expect(not WorkspaceLibrarySaveCurrent('Delphi'), 'refuse empty save');

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
    Expect(WorkspaceLiveHasLinks, 'imported nodes');
    Expect(WorkspaceLiveIsDirty, 'imported live is dirty until save');
    Expect(WorkspaceLibrarySaveCurrent('Delphi'), 'save named snapshot');
    Expect(not WorkspaceLiveIsDirty, 'saved live is clean');
    Expect(WorkspaceLiveName = 'Delphi', 'bound name');
    Id := WorkspaceLiveId;
    Expect(Id <> '', 'bound id');

    ClearWorkspaceLinks;
    Expect(WorkspaceLiveIsDirty, 'clear after save is dirty');
    Expect(WorkspaceLibraryRestore(Id), 'restore by id');
    Restored := WorkspaceExportLinks;
    Expect(Length(Restored) = 2, 'restore node count');
    Expect(SameText(Restored[0].Path, 'work') or SameText(Restored[1].Path, 'work'),
      'restore contains work');
    Expect(not WorkspaceLiveIsDirty, 'restored live is clean');

    WorkspaceLibraryRename(Id, 'Docs');
    Expect(WorkspaceLiveName = 'Docs', 'rename updates bound name');
    Snaps := WorkspaceLibraryGet;
    Expect(Length(Snaps) = 1, 'one snapshot in library');
    Expect(Snaps[0].Name = 'Docs', 'library name after rename');

    WorkspaceLibraryDelete(Id);
    Snaps := WorkspaceLibraryGet;
    Expect(Length(Snaps) = 0, 'library empty after delete');
    Expect(WorkspaceLiveId = '', 'delete unbinds');
    Expect(Length(WorkspaceExportLinks) = 2, 'delete snapshot keeps live links');

    if TFile.Exists(Path) then
      TFile.Delete(Path);
    ClearWorkspaceLinks;
    Writeln('All Workspace library tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
