unit TestFolderHotlist;

{ uFolderHotlist: entries keep the order the user arranged, and moving one
  entry keeps its hotkey. The runner points the config folder at a temp
  directory. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFolderHotlist = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure OrderIsInsertionOrderUntilMoved;
    [Test] procedure MoveKeepsHotKeyAndStopsAtEnds;
    [Test] procedure GroupGathersEntriesAndClears;
    [Test] procedure MoveCrossesGroupBorders;
    [Test] procedure SetEntriesRestoresSnapshot;
    [Test] procedure EmptiedGroupStaysUntilRemoved;
    [Test] procedure LastEntryLeavesGroupAtListEnds;
  end;

implementation

uses
  System.SysUtils, uFolderHotlist;

const
  cA = 'file:///C:/hotlist-a';
  cB = 'file:///C:/hotlist-b';
  cC = 'file:///C:/hotlist-c';

function Names: string;
var
  E: TFolderHotlistEntry;
begin
  Result := '';
  for E in FolderHotlistGetEntries do
    Result := Result + E.Name;
end;

procedure TTestFolderHotlist.Setup;
begin
  FolderHotlistClear;
  FolderHotlistAdd('a', cA);
  FolderHotlistAdd('b', cB);
  FolderHotlistAdd('c', cC);
end;

procedure TTestFolderHotlist.TearDown;
begin
  FolderHotlistClear;
end;

procedure TTestFolderHotlist.OrderIsInsertionOrderUntilMoved;
begin
  Assert.AreEqual('abc', Names, 'new entries go to the end');
  FolderHotlistSetHotKeyByUri(cC, 1);
  Assert.AreEqual('abc', Names, 'a hotkey does not reorder the list');
  Assert.IsTrue(FolderHotlistMoveByUri(cC, -2), 'moving up by two');
  Assert.AreEqual('cab', Names, 'c is first now');
  FolderHotlistAdd('b2', cB);
  Assert.AreEqual('cab2', Names, 'adding an existing URI again moves it to the end');
end;

procedure TTestFolderHotlist.MoveKeepsHotKeyAndStopsAtEnds;
begin
  FolderHotlistSetHotKeyByUri(cB, 3);
  Assert.IsTrue(FolderHotlistMoveByUri(cB, 1), 'b moves down');
  Assert.AreEqual('acb', Names);
  Assert.AreEqual(3, FolderHotlistGetEntries[2].HotKey, 'the moved entry keeps its hotkey');
  Assert.IsFalse(FolderHotlistMoveByUri(cB, 1), 'the last entry cannot go further down');
  Assert.IsFalse(FolderHotlistMoveByUri(cA, -1), 'the first entry cannot go further up');
  Assert.IsFalse(FolderHotlistMoveByUri('file:///C:/missing', 1), 'unknown entry');
  Assert.AreEqual('acb', Names, 'failed moves change nothing');
end;

procedure TTestFolderHotlist.GroupGathersEntriesAndClears;
begin
  FolderHotlistSetGroupByUri(cA, 'Work');
  FolderHotlistSetGroupByUri(cC, ' Work ');
  Assert.AreEqual('bac', Names, 'a grouped entry goes to the end, the next joins its group');
  Assert.AreEqual('Work', FolderHotlistGetEntries[2].Group, 'the group name is trimmed');
  FolderHotlistSetGroupByUri(cB, 'Work');
  Assert.AreEqual('acb', Names, 'joins after the last entry of the group');
  FolderHotlistSetGroupByUri(cA, '');
  Assert.AreEqual('cba', Names, 'an ungrouped entry goes to the end');
  Assert.AreEqual('', FolderHotlistGetEntries[2].Group);
end;

procedure TTestFolderHotlist.MoveCrossesGroupBorders;
begin
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetGroupByUri(cB, 'G');
  Assert.AreEqual('cab', Names);
  Assert.IsTrue(FolderHotlistMoveByUri(cB, -1), 'swaps with the neighbour in the group');
  Assert.AreEqual('cba', Names);
  Assert.IsTrue(FolderHotlistMoveByUri(cB, -1), 'the first entry leaves the group upwards');
  Assert.AreEqual('', FolderHotlistGetEntries[1].Group);
  Assert.AreEqual('cba', Names, 'leaving a group keeps the place');
  Assert.IsTrue(FolderHotlistMoveByUri(cB, 1), 'an ungrouped entry joins the group below');
  Assert.AreEqual('G', FolderHotlistGetEntries[1].Group);
  Assert.IsTrue(FolderHotlistMoveByUri(cA, 1), 'the last entry leaves its group at the list end');
  Assert.IsFalse(FolderHotlistMoveByUri(cA, 1), 'an ungrouped entry stops at the list end');
end;

procedure TTestFolderHotlist.SetEntriesRestoresSnapshot;
var
  Snapshot: TArray<TFolderHotlistEntry>;
begin
  Snapshot := FolderHotlistGetEntries;
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetHotKeyByUri(cB, 2);
  FolderHotlistRemoveByUri(cC);
  FolderHotlistSetEntries(Snapshot);
  Assert.AreEqual('abc', Names);
  Assert.AreEqual('', FolderHotlistGetEntries[0].Group);
  Assert.AreEqual(0, FolderHotlistGetEntries[1].HotKey);
end;

function GroupCount(const AGroup: string): Integer;
var
  E: TFolderHotlistEntry;
begin
  Result := 0;
  for E in FolderHotlistGetEntries do
    if E.Group = AGroup then
      Inc(Result);
end;

procedure TTestFolderHotlist.EmptiedGroupStaysUntilRemoved;
begin
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetGroupByUri(cA, '');
  Assert.AreEqual(1, GroupCount('G'), 'regrouping the last entry leaves the empty group');
  Assert.AreEqual('bca', Names, 'the placeholder has no name');
  FolderHotlistSetGroupByUri(cB, 'G');
  Assert.AreEqual(1, GroupCount('G'), 'an entry joining the group replaces the placeholder');
  Assert.IsTrue(FolderHotlistMoveByUri(cB, 1), 'leaves the group downwards');
  Assert.AreEqual(1, GroupCount('G'), 'the group stays after its last entry moved out');
  FolderHotlistRemoveByUri(cC);
  Assert.AreEqual(1, GroupCount('G'), 'removing an ungrouped entry does not touch groups');
  Assert.IsFalse(FolderHotlistRemoveEmptyGroup('missing'));
  Assert.IsTrue(FolderHotlistRemoveEmptyGroup('G'), 'an empty group can be removed');
  Assert.AreEqual(0, GroupCount('G'));
end;

procedure TTestFolderHotlist.LastEntryLeavesGroupAtListEnds;
begin
  // The only entry of a group sitting first in the list moves up out of it.
  FolderHotlistSetGroupByUri(cA, 'G');
  FolderHotlistSetGroupByUri(cB, 'H');
  FolderHotlistSetGroupByUri(cC, 'H');
  Assert.AreEqual('G', FolderHotlistGetEntries[0].Group);
  Assert.IsTrue(FolderHotlistMoveByUri(cA, -1), 'leaves the group at the top of the list');
  Assert.AreEqual(1, GroupCount('G'), 'the emptied group stays');
  Assert.AreEqual('', FolderHotlistGetEntries[FolderHotlistFindByUri(cA)].Group);
  Assert.IsFalse(FolderHotlistMoveByUri(cA, -1), 'an ungrouped entry stops at the top');
  // The last entry of the list moves down out of its group.
  Assert.IsTrue(FolderHotlistMoveByUri(cC, 1), 'leaves the group at the end of the list');
  Assert.AreEqual('', FolderHotlistGetEntries[FolderHotlistFindByUri(cC)].Group);
  Assert.AreEqual(1, GroupCount('H'), 'one entry is left in the group');
end;

end.
