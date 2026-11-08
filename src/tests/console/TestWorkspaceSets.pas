unit TestWorkspaceSets;

{ Putting found items into the live ws:/// set, a replacement, a new saved set or
  an existing saved one, without losing the set that was live before. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWorkspaceSets = class
  private
    FPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NewSetKeepsTheChangedLiveSet;
    [Test] procedure NewSetTakesAFreeName;
    [Test] procedure SavedSetGetsTheItemsAndStaysSaved;
    [Test] procedure SavedSetOpenedFromAnotherKeepsThatOne;
    [Test] procedure ReplaceDropsOnlyTheLiveLinks;
    [Test] procedure UnknownSavedSetChangesNothing;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes,
  uWorkspaceVfs,
  uWorkspaceLibrary;

// Test paths are written Windows-style; elsewhere they become rooted POSIX paths.
function NativePath(const APath: string): string;
begin
  Result := APath;
{$IFNDEF MSWINDOWS}
  if (Length(Result) > 2) and (Result[2] = ':') then
    Result := '/' + LowerCase(Result[1]) + Copy(Result, 3, MaxInt);
  Result := StringReplace(Result, Char(92), '/', [rfReplaceAll]);
{$ENDIF}
end;

function Target(const APath: string): TWorkspaceLinkNode;
begin
  Result := Default(TWorkspaceLinkNode);
  Result.TargetURI := PathToFileUri(NativePath(APath));
end;

function SnapshotByName(const AName: string; out ASnap: TWorkspaceSnapshot): Boolean;
var
  S: TWorkspaceSnapshot;
begin
  for S in WorkspaceLibraryGet do
    if SameText(S.Name, AName) then
    begin
      ASnap := S;
      Exit(True);
    end;
  Result := False;
end;

procedure TTestWorkspaceSets.Setup;
begin
  FPath := TPath.Combine(TPath.GetTempPath, 'mtn2-ws-sets-test.json');
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
  ClearWorkspaceLinks;
  WorkspaceLibraryUsePath(FPath);
  WorkspaceLibraryResetForTests;
end;

procedure TTestWorkspaceSets.TearDown;
begin
  ClearWorkspaceLinks;
  if TFile.Exists(FPath) then
    TFile.Delete(FPath);
end;

procedure TTestWorkspaceSets.NewSetKeepsTheChangedLiveSet;
var
  Snap: TWorkspaceSnapshot;
begin
  WorkspaceAddTargets([Target('C:\A\one.txt')]);
  Assert.IsTrue(WorkspaceLibrarySaveCurrent('Main'), 'save Main');
  WorkspaceAddTargets([Target('C:\A\two.txt')]);

  Assert.AreEqual('Found', WorkspaceLibraryAddToNew('Found', [Target('C:\B\hit.txt')]));

  Assert.IsTrue(SnapshotByName('Main', Snap), 'Main is still saved');
  Assert.AreEqual(2, Integer(Length(Snap.Nodes)), 'Main kept the link added after saving');
  Assert.IsTrue(SnapshotByName('Found', Snap), 'Found is saved');
  Assert.AreEqual(1, Integer(Length(Snap.Nodes)));
  Assert.AreEqual(1, WorkspaceLinkCount, 'live holds only the new set');
  Assert.AreEqual('Found', WorkspaceLiveName);
end;

procedure TTestWorkspaceSets.NewSetTakesAFreeName;
var
  Snap: TWorkspaceSnapshot;
begin
  Assert.AreEqual('Hits', WorkspaceLibraryAddToNew('Hits', [Target('C:\A\a.txt')]));
  Assert.AreEqual('Hits (2)', WorkspaceLibraryAddToNew('Hits', [Target('C:\A\b.txt')]));
  Assert.IsTrue(SnapshotByName('Hits', Snap), 'first set is not overwritten');
  Assert.IsTrue(Snap.Nodes[0].TargetURI = PathToFileUri(NativePath('C:\A\a.txt')));
  Assert.AreEqual('', WorkspaceLibraryAddToNew('  ', [Target('C:\A\c.txt')]),
    'a blank name is refused');
end;

procedure TTestWorkspaceSets.SavedSetGetsTheItemsAndStaysSaved;
var
  Snap: TWorkspaceSnapshot;
begin
  WorkspaceAddTargets([Target('C:\A\one.txt')]);
  WorkspaceLibrarySaveCurrent('Main');
  Assert.IsTrue(SnapshotByName('Main', Snap));
  Assert.IsTrue(WorkspaceLibraryAddToSaved(Snap.Id, [Target('C:\A\one.txt'), Target('C:\A\new.txt')]));
  Assert.IsTrue(SnapshotByName('Main', Snap));
  Assert.AreEqual(2, Integer(Length(Snap.Nodes)), 'repeat skipped, new one added, saved');
  Assert.IsTrue(not WorkspaceLiveIsDirty, 'the saved set matches the live one');
end;

procedure TTestWorkspaceSets.SavedSetOpenedFromAnotherKeepsThatOne;
var
  Main, Other, Unsaved: TWorkspaceSnapshot;
begin
  WorkspaceAddTargets([Target('C:\A\other.txt')]);
  WorkspaceLibrarySaveCurrent('Other');
  ClearWorkspaceLinks;
  WorkspaceAddTargets([Target('C:\A\main.txt')]);
  WorkspaceLibrarySaveCurrent('Main');
  Assert.IsTrue(SnapshotByName('Other', Other));
  WorkspaceAddTargets([Target('C:\A\draft.txt')]);

  Assert.IsTrue(WorkspaceLibraryAddToSaved(Other.Id, [Target('C:\B\hit.txt')]));

  Assert.IsTrue(SnapshotByName('Main', Main));
  Assert.AreEqual(2, Integer(Length(Main.Nodes)), 'Main kept its unsaved link');
  Assert.IsTrue(SnapshotByName('Other', Other));
  Assert.AreEqual(2, Integer(Length(Other.Nodes)));
  Assert.AreEqual('Other', WorkspaceLiveName);
  Assert.IsTrue(not SnapshotByName('Unsaved', Unsaved), 'no stray set was made');
end;

procedure TTestWorkspaceSets.ReplaceDropsOnlyTheLiveLinks;
var
  Snap: TWorkspaceSnapshot;
begin
  WorkspaceAddTargets([Target('C:\A\one.txt'), Target('C:\A\two.txt')]);
  WorkspaceLibrarySaveCurrent('Main');
  WorkspaceLibraryReplaceLive([Target('C:\B\hit.txt')]);
  Assert.AreEqual(1, WorkspaceLinkCount);
  Assert.IsTrue(SnapshotByName('Main', Snap));
  Assert.AreEqual(2, Integer(Length(Snap.Nodes)), 'the saved copy is untouched');
  Assert.IsTrue(WorkspaceLiveIsDirty, 'the live set differs from the saved one');
end;

procedure TTestWorkspaceSets.UnknownSavedSetChangesNothing;
begin
  WorkspaceAddTargets([Target('C:\A\one.txt')]);
  Assert.IsTrue(not WorkspaceLibraryAddToSaved('no-such-id', [Target('C:\B\hit.txt')]));
  Assert.AreEqual(1, WorkspaceLinkCount);
end;

end.
