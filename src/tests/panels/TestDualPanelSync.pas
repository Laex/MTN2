unit TestDualPanelSync;

{ Stage 35: two-way directory sync - newer side wins; conflicts (both
  sides changed since the last snapshot) stay unresolved.
  Stage 34: content mode marks same-date files whose bytes differ. }

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
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.IOUtils,
  uVfsTypes,
  uConfigLocation,
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

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelSync);

end.
