unit TestDualPanelSync;

{ Two-way directory sync - newer side wins; conflicts (both
  sides changed since the last snapshot) stay unresolved.
  Content mode marks same-date files whose bytes differ. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelSync = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestOneWayStillWorks;
    [Test] procedure TestTwoWayNewerWins;
    [Test] procedure TestTwoWayConflicts;
    [Test] procedure TestCommitKeepsConflicts;
    [Test] procedure TestJobPairDirection;
    [Test] procedure TestContentModeSameDate;
    [Test] procedure TestManualActionOverridesDirection;
    [Test] procedure TestManualSkipStaysUnresolved;
    [Test] procedure TestManualActionRespectsMissingSide;
    [Test] procedure TestPlanLinesFilterAndMap;
    [Test] procedure TestFitSyncPathKeepsBothEnds;
    [Test] procedure TestMirrorDeletesOnlyTargetExtras;
    [Test] procedure TestMirrorPlanShowsDeletions;
    [Test] procedure TestCompareCountsFilesAndFolders;
    [Test] procedure TestCancelledCompareReturnsNothing;
    [Test] procedure TestProgressTextFollowsStage;
    [Test] procedure TestDeletedSideProposesDeletion;
    [Test] procedure TestChangedAfterDeletionStaysUnresolved;
    [Test] procedure TestEmptySideProposesNoDeletion;
    [Test] procedure TestFilteredFileIsNotTakenForDeleted;
    [Test] procedure TestCommitKeepsPendingDeletion;
    [Test] procedure TestPruneForgetsFilesGoneFromBothSides;
    [Test] procedure TestManualDeleteFollowsSyncMode;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.IOUtils,
  uVfsTypes,
  uConfigLocation,
  uSyncIgnore,
  uDualPanelSync;

function FindReason(const AItems: TArray<TSyncItem>; const ARel: string;
  out AReason: TSyncReason): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AItems) do
    if SameText(AItems[I].RelPath, ARel) then
    begin
      AReason := AItems[I].Reason;
      Exit(True);
    end;
  Result := False;
end;

procedure WriteFileUtc(const APath, AText: string; const AUtc: TDateTime);
begin
  ForceDirectories(TPath.GetDirectoryName(APath));
  TFile.WriteAllText(APath, AText, TEncoding.UTF8);
  TFile.SetLastWriteTimeUtc(APath, AUtc);
end;

type
  // Leaves one file out of one of the two scans, as a skipped link does.
  TSkipOnceFilter = class(TInterfacedObject, ISyncFilter)
  private
    FRel: string;
    FSkipped: Boolean;
  public
    constructor Create(const ARel: string);
    function Skip(const ARel: string; AIsDir, AIsLink: Boolean): Boolean;
    procedure EnterDir(const ARel, ADir: string);
  end;

constructor TSkipOnceFilter.Create(const ARel: string);
begin
  inherited Create;
  FRel := ARel;
end;

function TSkipOnceFilter.Skip(const ARel: string; AIsDir, AIsLink: Boolean): Boolean;
begin
  Result := not FSkipped and SameText(ARel, FRel);
  if Result then
    FSkipped := True;
end;

procedure TSkipOnceFilter.EnterDir(const ARel, ADir: string);
begin
end;

// Two folders holding the same a.txt, b.txt and keep.txt, recorded as synced.
procedure MakeSyncedPair(const AName: string; out ALeft, ARight, AState: string);
var
  Root, N: string;
  T0: TDateTime;
begin
  Root := TPath.Combine(TPath.GetTempPath, AName);
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  ALeft := TPath.Combine(Root, 'left');
  ARight := TPath.Combine(Root, 'right');
  AState := TPath.Combine(Root, 'state.json');
  T0 := EncodeDateTime(2020, 1, 1, 12, 0, 0, 0);
  for N in TArray<string>.Create('a.txt', 'b.txt', 'keep.txt') do
  begin
    WriteFileUtc(TPath.Combine(ALeft, N), N, T0);
    WriteFileUtc(TPath.Combine(ARight, N), N, T0);
  end;
  CommitDirSyncSnapshotToFile(AState, ALeft, ARight, nil);
end;

function CompareSynced(const ALeft, ARight, AState: string;
  const AFilter: ISyncFilter = nil): TArray<TSyncItem>;
begin
  Result := CompareDirsTwoWay(ALeft, ARight,
    LoadDirSyncSnapshotFromFile(AState, ALeft, ARight), False, nil, AFilter);
end;

function ItemByRel(const AItems: TArray<TSyncItem>; const ARel: string): TSyncItem;
var
  I: Integer;
begin
  Result := Default(TSyncItem);
  for I := 0 to High(AItems) do
    if SameText(AItems[I].RelPath, ARel) then
      Exit(AItems[I]);
  Assert.Fail(ARel + ' is not listed');
end;

function SamePath(const AUri, APath: string): Boolean;
begin
  Result := SameText(ExpandFileName(FileUriToPath(AUri)), ExpandFileName(APath));
end;

procedure TestDeletedSideProposesDeletion;
var
  Left, Right, State: string;
  Items: TArray<TSyncItem>;
  A, B: TSyncItem;
  Deletes, Sources, Dests: TArray<string>;
begin
  MakeSyncedPair('mtn2-sync-deleted', Left, Right, State);
  TFile.Delete(TPath.Combine(Right, 'a.txt'));
  TFile.Delete(TPath.Combine(Left, 'b.txt'));
  Items := CompareSynced(Left, Right, State);
  Assert.AreEqual(2, Integer(Length(Items)), 'the two deletions are the only differences');
  A := ItemByRel(Items, 'a.txt');
  B := ItemByRel(Items, 'b.txt');
  Assert.IsTrue(A.Peer = peDeleted, 'a.txt was deleted on the right');
  Assert.IsTrue(B.Peer = peDeleted, 'b.txt was deleted on the left');
  Assert.IsTrue(EffectiveSyncAction(A, True) = saDelete, 'the left copy is removed');
  Assert.IsTrue(EffectiveSyncAction(B, True) = saDelete, 'the right copy is removed');
  Assert.IsTrue(EffectiveSyncAction(A, False) = saCopyRight,
    'one-way restores the file on the target');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.AreEqual(0, Integer(Length(Sources)), 'nothing is copied back');
  Deletes := CollectDirSyncDeletePaths(Items, True, False);
  Assert.AreEqual(2, Integer(Length(Deletes)), 'both surviving copies are collected');
  Assert.IsTrue(SamePath(Deletes[0], TPath.Combine(Left, 'a.txt')), 'surviving left copy');
  Assert.IsTrue(SamePath(Deletes[1], TPath.Combine(Right, 'b.txt')), 'surviving right copy');
end;

procedure TestChangedAfterDeletionStaysUnresolved;
var
  Left, Right, State: string;
  Items: TArray<TSyncItem>;
  A: TSyncItem;
begin
  MakeSyncedPair('mtn2-sync-delchanged', Left, Right, State);
  TFile.Delete(TPath.Combine(Right, 'a.txt'));
  WriteFileUtc(TPath.Combine(Left, 'a.txt'), 'edited',
    EncodeDateTime(2021, 1, 1, 12, 0, 0, 0));
  Items := CompareSynced(Left, Right, State);
  A := ItemByRel(Items, 'a.txt');
  Assert.IsTrue(A.Peer = peDeletedChanged, 'deleted on one side, edited on the other');
  Assert.IsTrue(EffectiveSyncAction(A, True) = saSkip, 'waits for a manual choice');
  Assert.AreEqual(1, Integer(Length(CollectDirSyncUnresolvedRels(Items, True))),
    'it is reported as unresolved');
end;

procedure TestEmptySideProposesNoDeletion;
var
  Left, Right, State, N: string;
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
begin
  MakeSyncedPair('mtn2-sync-emptied', Left, Right, State);
  for N in TArray<string>.Create('a.txt', 'b.txt', 'keep.txt') do
    TFile.Delete(TPath.Combine(Right, N));
  Items := CompareSynced(Left, Right, State);
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, True, False))),
    'an empty folder does not empty the other one');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.AreEqual(3, Integer(Length(Sources)), 'the files are copied back');
end;

procedure TestFilteredFileIsNotTakenForDeleted;
var
  Left, Right, State: string;
  Items: TArray<TSyncItem>;
begin
  MakeSyncedPair('mtn2-sync-filtered', Left, Right, State);
  Items := CompareSynced(Left, Right, State, TSkipOnceFilter.Create('a.txt'));
  Assert.IsTrue(ItemByRel(Items, 'a.txt').Peer = peNone,
    'a file that is still on disk was not deleted');
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, True, False))),
    'nothing is removed');
end;

procedure TestCommitKeepsPendingDeletion;
var
  Left, Right, State: string;
begin
  MakeSyncedPair('mtn2-sync-pending', Left, Right, State);
  TFile.Delete(TPath.Combine(Right, 'a.txt'));
  // The removal was declined or has not run yet.
  CommitDirSyncSnapshotToFile(State, Left, Right, nil);
  Assert.IsTrue(ItemByRel(CompareSynced(Left, Right, State), 'a.txt').Peer = peDeleted,
    'the deletion is still known');
end;

procedure TestPruneForgetsFilesGoneFromBothSides;
var
  Left, Right, State: string;
begin
  MakeSyncedPair('mtn2-sync-prune', Left, Right, State);
  TFile.Delete(TPath.Combine(Left, 'a.txt'));
  TFile.Delete(TPath.Combine(Right, 'a.txt'));
  TFile.Delete(TPath.Combine(Right, 'b.txt'));
  PruneDirSyncSnapshotFile(State, Left, Right);
  Assert.AreEqual(2, Integer(Length(LoadDirSyncSnapshotFromFile(State, Left, Right))),
    'only the file gone from both sides is forgotten');
  WriteFileUtc(TPath.Combine(Left, 'a.txt'), 'a.txt',
    EncodeDateTime(2020, 1, 1, 12, 0, 0, 0));
  Assert.IsTrue(ItemByRel(CompareSynced(Left, Right, State), 'a.txt').Peer = peNone,
    'a restored file counts as new');
end;

procedure TestManualDeleteFollowsSyncMode;
var
  Items: TArray<TSyncItem>;
begin
  SetLength(Items, 1);
  Items[0].RelPath := 'a.txt';
  Items[0].SrcURI := 'file:///C:/L/a.txt';
  Items[0].DstURI := 'file:///C:/R/a.txt';
  Items[0].Reason := srMissing;
  Assert.IsFalse(ApplySyncAction(Items[0], saDelete),
    'one-way never deletes from the source');
  Assert.IsTrue(ApplySyncAction(Items[0], saDelete, True),
    'two-way may delete the only copy by hand');
  Assert.AreEqual(1, Integer(Length(CollectDirSyncDeletePaths(Items, True, False))),
    'the chosen deletion is collected');
  Assert.IsTrue(EffectiveSyncAction(Items[0], False) = saSkip,
    'the choice does not carry over to one-way');
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, False, True))),
    'and nothing is deleted there');
end;

procedure TestMirrorDeletesOnlyTargetExtras;
var
  Root, Src, Dst, Extra: string;
  Items: TArray<TSyncItem>;
  Deletes, Sources, Dests: TArray<string>;
  Empty: TArray<TSyncSnapshotEntry>;
  I, Found: Integer;
  T0: TDateTime;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-mirror');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  T0 := EncodeDateTime(2020, 1, 1, 12, 0, 0, 0);
  SetLength(Empty, 0);
  WriteFileUtc(TPath.Combine(Src, 'same.txt'), 'same', T0);
  WriteFileUtc(TPath.Combine(Dst, 'same.txt'), 'same', T0);
  WriteFileUtc(TPath.Combine(Src, 'new.txt'), 'new', T0);
  Extra := TPath.Combine(Dst, 'extra.txt');
  WriteFileUtc(Extra, 'extra', T0);

  Items := CompareDirsTwoWay(Src, Dst, Empty);
  Found := -1;
  for I := 0 to High(Items) do
    if SameText(Items[I].RelPath, 'extra.txt') then
      Found := I;
  Assert.IsTrue(Found >= 0, 'a file only on the target is listed');
  Assert.IsTrue(EffectiveSyncAction(Items[Found], False, False) = saSkip,
    'one-way leaves a target-only file alone');
  Assert.IsTrue(EffectiveSyncAction(Items[Found], False, True) = saDelete,
    'mirror deletes a target-only file');
  Assert.IsTrue(EffectiveSyncAction(Items[Found], True, True) = saCopyLeft,
    'two-way never deletes');
  Assert.IsTrue(SyncActionAllowed(Items[Found], saDelete),
    'a target-only file may be deleted');

  Deletes := CollectDirSyncDeletePaths(Items, False, True);
  Assert.AreEqual(1, Integer(Length(Deletes)), 'one extra file is collected');
  Assert.IsTrue(SameText(ExpandFileName(FileUriToPath(Deletes[0])), ExpandFileName(Extra)),
    'the target copy is the one removed');
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, False, False))),
    'nothing is deleted outside mirror mode');
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, True, True))),
    'nothing is deleted in two-way mode');

  CollectDirSyncJobPairs(Items, Sources, Dests, False, True);
  Assert.AreEqual(1, Integer(Length(Sources)), 'only new.txt is copied');
  Assert.IsTrue(TFile.Exists(Extra), 'planning deletes nothing');

  Items[Found].Action := saSkip;
  Assert.AreEqual(0, Integer(Length(CollectDirSyncDeletePaths(Items, False, True))),
    'a manual skip keeps the file');
  Assert.IsTrue(ApplySyncAction(Items[Found], saDelete),
    'delete can be chosen by hand');
  Assert.AreEqual(1, Integer(Length(CollectDirSyncDeletePaths(Items, False, True))),
    'a chosen delete is collected');
end;

procedure TestCompareCountsFilesAndFolders;
var
  Root, Src, Dst: string;
  Progress: ISyncProgress;
  Items: TArray<TSyncItem>;
  Info: TSyncProgressInfo;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-progress');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  WriteFileUtc(TPath.Combine(Src, 'a.txt'), 'a', Now);
  WriteFileUtc(TPath.Combine(Src, 'sub' + PathDelim + 'b.txt'), 'b', Now);
  WriteFileUtc(TPath.Combine(Dst, 'a.txt'), 'a', Now);
  Progress := NewSyncProgress;
  Items := CompareDirsTwoWay(Src, Dst, nil, False, Progress);
  Info := Progress.Snapshot;
  Assert.AreEqual(Int64(3), Info.Files, 'files seen on both sides');
  Assert.AreEqual(Int64(3), Info.Dirs, 'both roots and the sub folder');
  Assert.AreEqual(Ord(ssComparing), Ord(Info.Stage), 'the scan is over');
  Assert.AreEqual(Int64(2), Info.Total, 'distinct relative paths');
  Assert.AreEqual(Info.Total, Info.Done, 'every path classified');
  Assert.AreEqual(100, SyncProgressPercent(Info));
  Assert.IsTrue(Length(Items) > 0, 'sub/b.txt is missing on the target');
end;

procedure TestCancelledCompareReturnsNothing;
var
  Root, Src, Dst: string;
  Progress: ISyncProgress;
  Items: TArray<TSyncItem>;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-cancel');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  WriteFileUtc(TPath.Combine(Src, 'a.txt'), 'a', Now);
  Progress := NewSyncProgress;
  Progress.Cancel;
  Assert.IsTrue(Progress.Cancelled, 'the stop flag is set');
  Items := CompareDirsTwoWay(Src, Dst, nil, False, Progress);
  Assert.AreEqual(0, Integer(Length(Items)), 'a stopped comparison reports nothing');
end;

procedure TestProgressTextFollowsStage;
var
  Info: TSyncProgressInfo;
begin
  Info := Default(TSyncProgressInfo);
  Info.Files := 12;
  Info.Dirs := 3;
  Assert.AreEqual(-1, SyncProgressPercent(Info), 'unknown while scanning');
  Assert.AreEqual('12', SyncProgressBadge(Info), 'the chip counts files while scanning');
  Assert.IsTrue(Pos('12', FormatSyncProgress(Info, False)) > 0, 'scan text has the count');
  Info.Stage := ssComparing;
  Info.Total := 40;
  Info.Done := 10;
  Assert.AreEqual(25, SyncProgressPercent(Info));
  Assert.AreEqual('25%', SyncProgressBadge(Info));
  Assert.IsTrue(Pos('10', FormatSyncProgress(Info, False)) > 0, 'compare text has the done count');
end;

procedure TestMirrorPlanShowsDeletions;
var
  Items: TArray<TSyncItem>;
  Lines: TArray<string>;
  View: TArray<Integer>;
  I: Integer;
begin
  SetLength(Items, 2);
  Items[0].RelPath := 'a.txt';
  Items[0].SrcURI := 'C:/L/a.txt';
  Items[0].DstURI := 'C:/R/a.txt';
  Items[0].Reason := srMissing;
  Items[1].RelPath := 'x.txt';
  Items[1].SrcURI := 'C:/R/x.txt';
  Items[1].DstURI := 'C:/L/x.txt';
  Items[1].Reason := srMissingOnSrc;
  Assert.IsFalse(SyncActionAllowed(Items[0], saDelete),
    'a file present on the source is never deleted');
  Lines := FormatSyncPlanLines(Items, False, False, View, True);
  Assert.AreEqual(2, Integer(Length(Lines)), 'both rows are listed');
  Assert.IsTrue(Pos('XX', Lines[1]) = 1, 'a deletion has its own glyph');
  Assert.IsTrue(Pos('XX', Lines[0]) = 0, 'a copy keeps its arrow');
  Assert.IsTrue(Pos('1 to delete', FormatDirSyncPlanStatus(Items, False, True)) > 0,
    'the status counts deletions');
  Assert.IsTrue(Pos('to delete', FormatDirSyncPlanStatus(Items, False, False)) = 0,
    'no deletions are announced outside mirror mode');
  for I := 0 to High(Lines) do
    Assert.IsTrue(Lines[I] <> '', 'rows are not empty');
end;

procedure TestOneWayStillWorks;
var
  Root, Src, Dst: string;
  Items: TArray<TSyncItem>;
  Reason: TSyncReason;
  TOld, TNew: TDateTime;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-oneway');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  TOld := EncodeDateTime(2020, 1, 1, 12, 0, 0, 0);
  TNew := EncodeDateTime(2021, 6, 1, 12, 0, 0, 0);
  WriteFileUtc(TPath.Combine(Src, 'only.txt'), 'src-only', TNew);
  WriteFileUtc(TPath.Combine(Src, 'newer.txt'), 'src-newer', TNew);
  WriteFileUtc(TPath.Combine(Dst, 'newer.txt'), 'dst-older', TOld);
  WriteFileUtc(TPath.Combine(Src, 'same.txt'), 'same', TOld);
  WriteFileUtc(TPath.Combine(Dst, 'same.txt'), 'same', TOld);

  Items := CompareDirsOneWay(Src, Dst);
  Assert.IsTrue(FindReason(Items, 'only.txt', Reason) and (Reason = srMissing),
    'missing on dest is srMissing');
  Assert.IsTrue(FindReason(Items, 'newer.txt', Reason) and (Reason = srNewer),
    'newer on src is srNewer');
  Assert.IsTrue(not FindReason(Items, 'same.txt', Reason),
    'identical timestamps are skipped');
  Assert.IsTrue(not FindReason(Items, 'dst-only.txt', Reason),
    'dest-only is ignored in one-way');
end;

procedure TestTwoWayNewerWins;
var
  Root, Left, Right: string;
  Items: TArray<TSyncItem>;
  Reason: TSyncReason;
  Sources, Dests: TArray<string>;
  TOld, TMid, TNew: TDateTime;
  Empty: TArray<TSyncSnapshotEntry>;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-twoway');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Left := TPath.Combine(Root, 'left');
  Right := TPath.Combine(Root, 'right');
  TOld := EncodeDateTime(2020, 1, 1, 8, 0, 0, 0);
  TMid := EncodeDateTime(2021, 1, 1, 8, 0, 0, 0);
  TNew := EncodeDateTime(2022, 1, 1, 8, 0, 0, 0);
  SetLength(Empty, 0);

  WriteFileUtc(TPath.Combine(Left, 'left-newer.txt'), 'L', TNew);
  WriteFileUtc(TPath.Combine(Right, 'left-newer.txt'), 'R', TOld);
  WriteFileUtc(TPath.Combine(Left, 'right-newer.txt'), 'L', TOld);
  WriteFileUtc(TPath.Combine(Right, 'right-newer.txt'), 'R', TNew);
  WriteFileUtc(TPath.Combine(Left, 'only-left.txt'), 'L', TMid);
  WriteFileUtc(TPath.Combine(Right, 'only-right.txt'), 'R', TMid);
  WriteFileUtc(TPath.Combine(Left, 'sub', 'nested.txt'), 'L', TNew);
  WriteFileUtc(TPath.Combine(Right, 'sub', 'nested.txt'), 'R', TOld);

  Items := CompareDirsTwoWay(Left, Right, Empty);
  Assert.IsTrue(FindReason(Items, 'left-newer.txt', Reason) and (Reason = srNewer),
    'left newer copies Active to Inactive');
  Assert.IsTrue(FindReason(Items, 'right-newer.txt', Reason) and (Reason = srNewerOnDst),
    'right newer copies Inactive to Active');
  Assert.IsTrue(FindReason(Items, 'only-left.txt', Reason) and (Reason = srMissing),
    'missing on right copies Active to Inactive');
  Assert.IsTrue(FindReason(Items, 'only-right.txt', Reason) and (Reason = srMissingOnSrc),
    'missing on left copies Inactive to Active');
  Assert.IsTrue(FindReason(Items, 'sub' + PathDelim + 'nested.txt', Reason) and
    (Reason = srNewer), 'nested left-newer is found');
  Assert.IsTrue(CountSyncConflicts(Items) = 0, 'no snapshot → no conflicts');

  CollectDirSyncJobPairs(Items, Sources, Dests, False);
  Assert.IsTrue(Length(Sources) = 3, 'one-way apply copies only → (missing+newer+nested)');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 5, 'two-way apply copies both directions (5 files)');
  Assert.IsTrue(FormatDirSyncStatus(Items) = '5 to copy (3 ->, 2 <-)',
    'status reports both directions and no conflicts');
end;

procedure TestTwoWayConflicts;
var
  Root, Left, Right, StateFile: string;
  Items: TArray<TSyncItem>;
  Reason: TSyncReason;
  Snap: TArray<TSyncSnapshotEntry>;
  Sources, Dests: TArray<string>;
  T0, T1, T2: TDateTime;
  Preview: TArray<string>;
  I: Integer;
  SawConflict: Boolean;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-conflict');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Left := TPath.Combine(Root, 'left');
  Right := TPath.Combine(Root, 'right');
  StateFile := TPath.Combine(Root, 'dirsync-state.json');
  T0 := EncodeDateTime(2020, 1, 1, 10, 0, 0, 0);
  T1 := EncodeDateTime(2021, 1, 1, 10, 0, 0, 0);
  T2 := EncodeDateTime(2022, 1, 1, 10, 0, 0, 0);

  WriteFileUtc(TPath.Combine(Left, 'both.txt'), 'left-v2', T1);
  WriteFileUtc(TPath.Combine(Right, 'both.txt'), 'right-v2', T2);
  WriteFileUtc(TPath.Combine(Left, 'left-only-edit.txt'), 'L2', T1);
  WriteFileUtc(TPath.Combine(Right, 'left-only-edit.txt'), 'same', T0);
  WriteFileUtc(TPath.Combine(Left, 'right-only-edit.txt'), 'same', T0);
  WriteFileUtc(TPath.Combine(Right, 'right-only-edit.txt'), 'R2', T2);

  SetLength(Snap, 3);
  Snap[0].RelPath := 'both.txt';
  Snap[0].LeftUtcTicks := Round(T0 * MSecsPerDay);
  Snap[0].RightUtcTicks := Round(T0 * MSecsPerDay);
  Snap[1].RelPath := 'left-only-edit.txt';
  Snap[1].LeftUtcTicks := Round(T0 * MSecsPerDay);
  Snap[1].RightUtcTicks := Round(T0 * MSecsPerDay);
  Snap[2].RelPath := 'right-only-edit.txt';
  Snap[2].LeftUtcTicks := Round(T0 * MSecsPerDay);
  Snap[2].RightUtcTicks := Round(T0 * MSecsPerDay);

  Items := CompareDirsTwoWay(Left, Right, Snap);
  Assert.IsTrue(FindReason(Items, 'both.txt', Reason) and (Reason = srConflict),
    'both changed is srConflict, not auto-resolved to newer');
  Assert.IsTrue(FindReason(Items, 'left-only-edit.txt', Reason) and (Reason = srNewer),
    'only left changed copies Active to Inactive');
  Assert.IsTrue(FindReason(Items, 'right-only-edit.txt', Reason) and
    (Reason = srNewerOnDst), 'only right changed copies Inactive to Active');
  Assert.IsTrue(CountSyncConflicts(Items) = 1, 'exactly one conflict');

  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 2, 'conflicts are excluded from the copy job');
  Assert.IsTrue(Pos('conflict', FormatDirSyncStatus(Items)) > 0,
    'status names the conflict instead of swallowing it');

  Preview := FormatSyncPreviewLines(Items, 12);
  SawConflict := False;
  for I := 0 to High(Preview) do
    if Pos('[!]', Preview[I]) > 0 then
      SawConflict := True;
  Assert.IsTrue(SawConflict, 'preview lists the conflict with [!]');

  SaveDirSyncSnapshotToFile(StateFile, Left, Right, Snap);
  Snap := LoadDirSyncSnapshotFromFile(StateFile, Left, Right);
  Assert.IsTrue(Length(Snap) = 3, 'snapshot round-trips 3 files');
  Snap := LoadDirSyncSnapshotFromFile(StateFile, Right, Left);
  Assert.IsTrue(Length(Snap) = 3, 'swapped roots still find the pair');
end;

procedure TestCommitKeepsConflicts;
var
  Root, Left, Right, StateFile: string;
  Snap, After: TArray<TSyncSnapshotEntry>;
  T0, T1, T2: TDateTime;
  Conflicts: TArray<string>;
  I: Integer;
  Kept: Boolean;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-commit');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Left := TPath.Combine(Root, 'left');
  Right := TPath.Combine(Root, 'right');
  StateFile := TPath.Combine(Root, 'state.json');
  T0 := EncodeDateTime(2019, 1, 1, 0, 0, 0, 0);
  T1 := EncodeDateTime(2021, 1, 1, 0, 0, 0, 0);
  T2 := EncodeDateTime(2022, 1, 1, 0, 0, 0, 0);
  WriteFileUtc(TPath.Combine(Left, 'conflict.txt'), 'L', T1);
  WriteFileUtc(TPath.Combine(Right, 'conflict.txt'), 'R', T2);
  WriteFileUtc(TPath.Combine(Left, 'ok.txt'), 'ok', T1);
  WriteFileUtc(TPath.Combine(Right, 'ok.txt'), 'ok', T1);

  SetLength(Snap, 1);
  Snap[0].RelPath := 'conflict.txt';
  Snap[0].LeftUtcTicks := Round(T0 * MSecsPerDay);
  Snap[0].RightUtcTicks := Round(T0 * MSecsPerDay);
  SaveDirSyncSnapshotToFile(StateFile, Left, Right, Snap);

  SetLength(Conflicts, 1);
  Conflicts[0] := 'conflict.txt';
  CommitDirSyncSnapshotToFile(StateFile, Left, Right, Conflicts);
  After := LoadDirSyncSnapshotFromFile(StateFile, Left, Right);
  Assert.IsTrue(Length(After) = 2, 'commit records both files');
  Kept := False;
  for I := 0 to High(After) do
    if SameText(After[I].RelPath, 'conflict.txt') then
      Kept := After[I].LeftUtcTicks = Round(T0 * MSecsPerDay);
  Assert.IsTrue(Kept, 'conflict entry keeps the pre-sync ticks');
end;

procedure TestJobPairDirection;
var
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
begin
  SetLength(Items, 3);
  Items[0].RelPath := 'a.txt';
  Items[0].SrcURI := 'file:///C:/L/a.txt';
  Items[0].DstURI := 'file:///C:/R/a.txt';
  Items[0].Reason := srNewer;
  Items[1].RelPath := 'b.txt';
  Items[1].SrcURI := 'file:///C:/R/b.txt';
  Items[1].DstURI := 'file:///C:/L/b.txt';
  Items[1].Reason := srNewerOnDst;
  Items[2].RelPath := 'c.txt';
  Items[2].SrcURI := 'file:///C:/L/c.txt';
  Items[2].DstURI := 'file:///C:/R/c.txt';
  Items[2].Reason := srConflict;

  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 2, 'two-way drops only the conflict');
  Assert.IsTrue(Sources[0] = Items[0].SrcURI, 'L-to-R keeps left as source');
  Assert.IsTrue(Sources[1] = Items[1].SrcURI, 'R-to-L keeps right as source');
  CollectDirSyncJobPairs(Items, Sources, Dests, False);
  Assert.IsTrue(Length(Sources) = 1, 'one-way drops reverse copy and conflict');
  Assert.IsTrue(Sources[0] = Items[0].SrcURI, 'one-way copies only Active to Inactive');
end;

procedure TestContentModeSameDate;
var
  Root, Src, Dst: string;
  Items: TArray<TSyncItem>;
  Reason: TSyncReason;
  Sources, Dests: TArray<string>;
  TSame: TDateTime;
  Preview: TArray<string>;
  I: Integer;
  SawContent: Boolean;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-sync-content');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Src := TPath.Combine(Root, 'src');
  Dst := TPath.Combine(Root, 'dst');
  TSame := EncodeDateTime(2020, 5, 1, 12, 0, 0, 0);
  WriteFileUtc(TPath.Combine(Src, 'same-date.txt'), 'left-bytes', TSame);
  WriteFileUtc(TPath.Combine(Dst, 'same-date.txt'), 'right-bytes', TSame);
  WriteFileUtc(TPath.Combine(Src, 'identical.txt'), 'same', TSame);
  WriteFileUtc(TPath.Combine(Dst, 'identical.txt'), 'same', TSame);

  Items := CompareDirsOneWay(Src, Dst, False);
  Assert.IsTrue(not FindReason(Items, 'same-date.txt', Reason),
    'date mode skips same timestamp even when bytes differ');
  Assert.IsTrue(not FindReason(Items, 'identical.txt', Reason),
    'date mode skips identical files');

  Items := CompareDirsOneWay(Src, Dst, True);
  Assert.IsTrue(FindReason(Items, 'same-date.txt', Reason) and (Reason = srContentDiff),
    'content mode marks same-date different bytes as srContentDiff');
  Assert.IsTrue(not FindReason(Items, 'identical.txt', Reason),
    'content mode skips identical bytes');
  Assert.IsTrue(FilesContentEqual(TPath.Combine(Src, 'identical.txt'),
    TPath.Combine(Dst, 'identical.txt')), 'byte compare of identical files');
  Assert.IsTrue(not FilesContentEqual(TPath.Combine(Src, 'same-date.txt'),
    TPath.Combine(Dst, 'same-date.txt')), 'byte compare of different files');

  CollectDirSyncJobPairs(Items, Sources, Dests, False);
  Assert.IsTrue(Length(Sources) = 1, 'one-way copies the content-diff file');
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 0, 'two-way leaves content-diff for a manual choice');

  Items := CompareDirsTwoWay(Src, Dst, nil, True);
  Assert.IsTrue(FindReason(Items, 'same-date.txt', Reason) and (Reason = srContentDiff),
    'two-way content mode also marks same-date different bytes');

  Preview := FormatSyncPreviewLines(Items, 12);
  SawContent := False;
  for I := 0 to High(Preview) do
    if Pos('[!=]', Preview[I]) > 0 then
      SawContent := True;
  Assert.IsTrue(SawContent, 'preview lists content-diff with [!=]');
  Assert.IsTrue(Pos('content-diff', FormatDirSyncStatus(Items)) > 0,
    'status names the content-diff');
end;

function PlanItems: TArray<TSyncItem>;
begin
  SetLength(Result, 4);
  Result[0].RelPath := 'a.txt';
  Result[0].SrcURI := 'file:///C:/L/a.txt';
  Result[0].DstURI := 'file:///C:/R/a.txt';
  Result[0].Reason := srNewer;
  Result[1].RelPath := 'b.txt';
  Result[1].SrcURI := 'file:///C:/R/b.txt';
  Result[1].DstURI := 'file:///C:/L/b.txt';
  Result[1].Reason := srNewerOnDst;
  Result[2].RelPath := 'c.txt';
  Result[2].SrcURI := 'file:///C:/L/c.txt';
  Result[2].DstURI := 'file:///C:/R/c.txt';
  Result[2].Reason := srConflict;
  Result[3].RelPath := 'd.txt';
  Result[3].SrcURI := 'file:///C:/L/d.txt';
  Result[3].DstURI := 'file:///C:/R/d.txt';
  Result[3].Reason := srMissing;
end;

procedure TestManualActionOverridesDirection;
var
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
begin
  Items := PlanItems;
  Assert.IsTrue(EffectiveSyncAction(Items[2], True) = saSkip,
    'a conflict is skipped until chosen');
  Assert.IsTrue(ApplySyncAction(Items[2], saCopyLeft), 'conflict can go right-to-left');
  Assert.IsTrue(ApplySyncAction(Items[0], saCopyLeft),
    'a newer left file can be overwritten by the right one');
  Assert.IsTrue(ApplySyncAction(Items[1], saSkip), 'a copy can be skipped');

  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(3 = Length(Sources), 'two manual copies plus the automatic one');
  Assert.IsTrue(SyncItemRightURI(Items[0]) = Sources[0], 'overridden copy reads from the right');
  Assert.IsTrue(SyncItemLeftURI(Items[0]) = Dests[0], 'overridden copy writes to the left');
  Assert.IsTrue(SyncItemRightURI(Items[2]) = Sources[1], 'resolved conflict reads from the right');
  Assert.IsTrue(SyncItemLeftURI(Items[3]) = Sources[2], 'automatic copy keeps its direction');

  Items[0].Action := saAuto;
  Assert.IsTrue(EffectiveSyncAction(Items[0], False) = saCopyRight,
    'reset returns to the automatic action');
end;

procedure TestManualSkipStaysUnresolved;
var
  Items: TArray<TSyncItem>;
  Rels: TArray<string>;
begin
  Items := PlanItems;
  Rels := CollectDirSyncUnresolvedRels(Items, True);
  Assert.IsTrue(1 = Length(Rels), 'only the conflict is open at first');
  Assert.IsTrue('c.txt' = Rels[0], 'unexpected value');

  ApplySyncAction(Items[2], saCopyRight);
  ApplySyncAction(Items[3], saSkip);
  Rels := CollectDirSyncUnresolvedRels(Items, True);
  Assert.IsTrue(1 = Length(Rels), 'a resolved conflict leaves the list, a skipped copy joins it');
  Assert.IsTrue('d.txt' = Rels[0], 'unexpected value');

  Items[3].Action := saAuto;
  Assert.IsTrue(Length(CollectDirSyncUnresolvedRels(Items, True)) = 0,
    'nothing is open once every item has an action');
  Assert.IsTrue(Length(CollectDirSyncUnresolvedRels(Items, False)) = 0,
    'one-way mode does not report the reverse copy as open');
end;

procedure TestManualActionRespectsMissingSide;
var
  Items: TArray<TSyncItem>;
  Sources, Dests: TArray<string>;
begin
  Items := PlanItems;
  Assert.IsFalse(ApplySyncAction(Items[3], saCopyLeft),
    'a file missing on the right cannot be copied from the right');
  Assert.IsTrue(Items[3].Action = saAuto, 'a refused action changes nothing');

  Items[3].Action := saCopyLeft;
  CollectDirSyncJobPairs(Items, Sources, Dests, True);
  Assert.IsTrue(Length(Sources) = 2,
    'the impossible action is dropped; a.txt and b.txt remain');
end;

procedure TestPlanLinesFilterAndMap;
var
  Items: TArray<TSyncItem>;
  View: TArray<Integer>;
  Lines: TArray<string>;
begin
  Items := PlanItems;
  Lines := FormatSyncPlanLines(Items, True, False, View);
  Assert.IsTrue(4 = Length(Lines), 'unexpected value');
  Assert.IsTrue(Pos('->', Lines[0]) = 1, 'newer-left copy shows the right arrow');
  Assert.IsTrue(Pos('<-', Lines[1]) = 1, 'newer-right copy shows the left arrow');
  Assert.IsTrue(Pos('--', Lines[2]) = 1, 'conflict shows the skip marker');

  ApplySyncAction(Items[0], saSkip);
  Lines := FormatSyncPlanLines(Items, True, True, View);
  Assert.IsTrue(2 = Length(Lines), 'filter keeps only skipped rows');
  Assert.IsTrue(0 = View[0], 'row 0 maps to a.txt');
  Assert.IsTrue(2 = View[1], 'row 1 maps to c.txt');
  Assert.IsTrue(Pos('*', Lines[0]) = 3, 'a manual choice is marked');
  Assert.IsTrue(Pos('2 skipped', FormatDirSyncPlanStatus(Items, True)) > 0,
    'status counts skipped items');
end;

procedure TestFitSyncPathKeepsBothEnds;
var
  Path, Fit: string;
begin
  Path := 'C:\Very\Long\Folder\Chain\That\Will\Not\Fit\In\The\Label\Width\sync-test\right';
  Assert.IsTrue(FitSyncPath('C:\Short', 40) = 'C:\Short', 'a path that fits is untouched');
  Fit := FitSyncPath(Path, 40);
  Assert.IsTrue(Length(Fit) = 40, 'a long path is cut to the width');
  Assert.IsTrue(Pos('...', Fit) > 0, 'the cut is marked');
  Assert.IsTrue(Copy(Fit, 1, 3) = 'C:\', 'the start survives');
  Assert.IsTrue(Copy(Fit, Length(Fit) - 4, 5) = 'right', 'the last folder survives');
end;

{ TTestDualPanelSync }

procedure TTestDualPanelSync.SetupFixture;
begin
end;

procedure TTestDualPanelSync.TestOneWayStillWorks;
begin
  TestDualPanelSync.TestOneWayStillWorks;
end;

procedure TTestDualPanelSync.TestTwoWayNewerWins;
begin
  TestDualPanelSync.TestTwoWayNewerWins;
end;

procedure TTestDualPanelSync.TestTwoWayConflicts;
begin
  TestDualPanelSync.TestTwoWayConflicts;
end;

procedure TTestDualPanelSync.TestCommitKeepsConflicts;
begin
  TestDualPanelSync.TestCommitKeepsConflicts;
end;

procedure TTestDualPanelSync.TestJobPairDirection;
begin
  TestDualPanelSync.TestJobPairDirection;
end;

procedure TTestDualPanelSync.TestContentModeSameDate;
begin
  TestDualPanelSync.TestContentModeSameDate;
end;

procedure TTestDualPanelSync.TestManualActionOverridesDirection;
begin
  TestDualPanelSync.TestManualActionOverridesDirection;
end;

procedure TTestDualPanelSync.TestManualSkipStaysUnresolved;
begin
  TestDualPanelSync.TestManualSkipStaysUnresolved;
end;

procedure TTestDualPanelSync.TestManualActionRespectsMissingSide;
begin
  TestDualPanelSync.TestManualActionRespectsMissingSide;
end;

procedure TTestDualPanelSync.TestPlanLinesFilterAndMap;
begin
  TestDualPanelSync.TestPlanLinesFilterAndMap;
end;

procedure TTestDualPanelSync.TestMirrorDeletesOnlyTargetExtras;
begin
  TestDualPanelSync.TestMirrorDeletesOnlyTargetExtras;
end;

procedure TTestDualPanelSync.TestMirrorPlanShowsDeletions;
begin
  TestDualPanelSync.TestMirrorPlanShowsDeletions;
end;

procedure TTestDualPanelSync.TestCompareCountsFilesAndFolders;
begin
  TestDualPanelSync.TestCompareCountsFilesAndFolders;
end;

procedure TTestDualPanelSync.TestCancelledCompareReturnsNothing;
begin
  TestDualPanelSync.TestCancelledCompareReturnsNothing;
end;

procedure TTestDualPanelSync.TestProgressTextFollowsStage;
begin
  TestDualPanelSync.TestProgressTextFollowsStage;
end;

procedure TTestDualPanelSync.TestFitSyncPathKeepsBothEnds;
begin
  TestDualPanelSync.TestFitSyncPathKeepsBothEnds;
end;

procedure TTestDualPanelSync.TestDeletedSideProposesDeletion;
begin
  TestDualPanelSync.TestDeletedSideProposesDeletion;
end;

procedure TTestDualPanelSync.TestChangedAfterDeletionStaysUnresolved;
begin
  TestDualPanelSync.TestChangedAfterDeletionStaysUnresolved;
end;

procedure TTestDualPanelSync.TestEmptySideProposesNoDeletion;
begin
  TestDualPanelSync.TestEmptySideProposesNoDeletion;
end;

procedure TTestDualPanelSync.TestFilteredFileIsNotTakenForDeleted;
begin
  TestDualPanelSync.TestFilteredFileIsNotTakenForDeleted;
end;

procedure TTestDualPanelSync.TestCommitKeepsPendingDeletion;
begin
  TestDualPanelSync.TestCommitKeepsPendingDeletion;
end;

procedure TTestDualPanelSync.TestPruneForgetsFilesGoneFromBothSides;
begin
  TestDualPanelSync.TestPruneForgetsFilesGoneFromBothSides;
end;

procedure TTestDualPanelSync.TestManualDeleteFollowsSyncMode;
begin
  TestDualPanelSync.TestManualDeleteFollowsSyncMode;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelSync);

end.
