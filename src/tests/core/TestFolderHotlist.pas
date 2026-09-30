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

end.
