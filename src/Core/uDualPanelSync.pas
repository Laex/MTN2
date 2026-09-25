unit uDualPanelSync;

{ Directory compare for Directory Sync.
  Stage 19: one-way Active → Inactive (missing | newer).
  Stage 35: two-way ⇄ — copy direction follows whichever side is newer;
  conflicts (both sides changed since the last successful sync) stay
  unresolved and are listed for a manual choice.
  Stage 34: optional content mode (size + byte compare) marks files that
  share a timestamp but differ in bytes. Local file:// only. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Threading,
  uVfsTypes;

type
  TSyncReason = (srMissing, srNewer, srMissingOnSrc, srNewerOnDst, srConflict,
    srContentDiff);

  TSyncItem = record
    RelPath: string;
    SrcURI: string;
    DstURI: string;
    Reason: TSyncReason;
  end;

  TSyncSnapshotEntry = record
    RelPath: string;
    LeftUtcTicks: Int64;
    RightUtcTicks: Int64;
  end;

  TSyncCompareDone = reference to procedure(const AItems: TArray<TSyncItem>;
    const AError: string);

function CompareDirsOneWay(const ASrcRoot, ADstRoot: string;
  AByContent: Boolean = False): TArray<TSyncItem>;
procedure CompareDirsOneWayAsync(const ASrcRoot, ADstRoot: string;
  AOnDone: TSyncCompareDone; AByContent: Boolean = False);
function CompareDirsTwoWay(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>;
  AByContent: Boolean = False): TArray<TSyncItem>;
procedure CompareDirsTwoWayAsync(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>; AOnDone: TSyncCompareDone;
  AByContent: Boolean = False);
function CountSyncReasons(const AItems: TArray<TSyncItem>;
  out AMissing, ANewer: Integer): Integer;
function FormatSyncPreviewLines(const AItems: TArray<TSyncItem>;
  AMaxLines: Integer = 12): TArray<string>;
function FormatDirSyncStatus(const AItems: TArray<TSyncItem>): string;
procedure CollectDirSyncJobPairs(const AItems: TArray<TSyncItem>;
  out ASources, ADestURIs: TArray<string>; ATwoWay: Boolean = False);
function DirSyncUrisAreLocalFolders(const ASrcURI, ADstURI: string): Boolean;
function SyncItemCopiesToRight(const AItem: TSyncItem): Boolean;
function SyncItemCopiesToLeft(const AItem: TSyncItem): Boolean;
function SyncItemIsConflict(const AItem: TSyncItem): Boolean;
function SyncItemIsContentDiff(const AItem: TSyncItem): Boolean;
function CountSyncConflicts(const AItems: TArray<TSyncItem>): Integer;
function CountSyncContentDiffs(const AItems: TArray<TSyncItem>): Integer;
function CollectDirSyncConflictRels(const AItems: TArray<TSyncItem>): TArray<string>;
function CollectDirSyncUnresolvedRels(const AItems: TArray<TSyncItem>;
  ATwoWay: Boolean): TArray<string>;
function FilesContentEqual(const ALeft, ARight: string): Boolean;

function FileUtcTicks(const APath: string): Int64;
function DirSyncStateFilePath: string;
function LoadDirSyncSnapshotFromFile(const AFile, ALeftRoot,
  ARightRoot: string): TArray<TSyncSnapshotEntry>;
procedure SaveDirSyncSnapshotToFile(const AFile, ALeftRoot, ARightRoot: string;
  const AEntries: TArray<TSyncSnapshotEntry>);
function LoadDirSyncSnapshot(const ALeftRoot, ARightRoot: string): TArray<TSyncSnapshotEntry>;
procedure SaveDirSyncSnapshot(const ALeftRoot, ARightRoot: string;
  const AEntries: TArray<TSyncSnapshotEntry>);
procedure CommitDirSyncSnapshotToFile(const AFile, ALeftRoot, ARightRoot: string;
  const AConflictRels: TArray<string>);
procedure CommitDirSyncSnapshot(const ALeftRoot, ARightRoot: string;
  const AConflictRels: TArray<string>);

implementation

uses
  System.JSON, System.Generics.Collections, System.Generics.Defaults,
  uConfigLocation;

const
  cDirSyncStateFile = 'dirsync-state.json';
  cDirSyncStateMaxPairs = 32;

function FileUtcTicks(const APath: string): Int64;
begin
  Result := Round(TFile.GetLastWriteTimeUtc(APath) * MSecsPerDay);
end;

function NormSyncRoot(const ARoot: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(ARoot));
end;

function SameSyncRoot(const A, B: string): Boolean;
begin
  Result := SameText(NormSyncRoot(A), NormSyncRoot(B));
end;

function SyncItemCopiesToRight(const AItem: TSyncItem): Boolean;
begin
  Result := AItem.Reason in [srMissing, srNewer, srContentDiff];
end;

function SyncItemCopiesToLeft(const AItem: TSyncItem): Boolean;
begin
  Result := AItem.Reason in [srMissingOnSrc, srNewerOnDst];
end;

function SyncItemIsConflict(const AItem: TSyncItem): Boolean;
begin
  Result := AItem.Reason = srConflict;
end;

function SyncItemIsContentDiff(const AItem: TSyncItem): Boolean;
begin
  Result := AItem.Reason = srContentDiff;
end;

function CountSyncConflicts(const AItems: TArray<TSyncItem>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AItems) do
    if AItems[I].Reason = srConflict then
      Inc(Result);
end;

function CountSyncContentDiffs(const AItems: TArray<TSyncItem>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AItems) do
    if AItems[I].Reason = srContentDiff then
      Inc(Result);
end;

function FilesContentEqual(const ALeft, ARight: string): Boolean;
const
  cChunk = 64 * 1024;
var
  SL, SR: TFileStream;
  BL, BR: TBytes;
  NL, NR: Integer;
  SizeL, SizeR: Int64;
begin
  Result := False;
  if (ALeft = '') or (ARight = '') then
    Exit;
  if not TFile.Exists(ALeft) or not TFile.Exists(ARight) then
    Exit;
  try
    SizeL := TFile.GetSize(ALeft);
    SizeR := TFile.GetSize(ARight);
    if SizeL <> SizeR then
      Exit;
    if SizeL = 0 then
      Exit(True);
    SL := TFileStream.Create(ALeft, fmOpenRead or fmShareDenyNone);
    try
      SR := TFileStream.Create(ARight, fmOpenRead or fmShareDenyNone);
      try
        SetLength(BL, cChunk);
        SetLength(BR, cChunk);
        repeat
          NL := SL.Read(BL[0], cChunk);
          NR := SR.Read(BR[0], cChunk);
          if NL <> NR then
            Exit(False);
          if NL = 0 then
            Exit(True);
          if not CompareMem(@BL[0], @BR[0], NL) then
            Exit(False);
        until False;
      finally
        SR.Free;
      end;
    finally
      SL.Free;
    end;
  except
    Result := False;
  end;
end;

function CollectDirSyncConflictRels(const AItems: TArray<TSyncItem>): TArray<string>;
var
  I, N: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(AItems) do
    if AItems[I].Reason = srConflict then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := AItems[I].RelPath;
    end;
end;

function CollectDirSyncUnresolvedRels(const AItems: TArray<TSyncItem>;
  ATwoWay: Boolean): TArray<string>;
var
  I, N: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(AItems) do
  begin
    if AItems[I].Reason = srConflict then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := AItems[I].RelPath;
    end
    else if ATwoWay and (AItems[I].Reason = srContentDiff) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := AItems[I].RelPath;
    end;
  end;
end;

function RelInList(const ARel: string; const AList: TArray<string>): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AList) do
    if SameText(AList[I], ARel) then
      Exit(True);
  Result := False;
end;

procedure CollectFiles(const ADir, ARelBase: string;
  APaths: TDictionary<string, string>);
var
  SR: TSearchRec;
  Code: Integer;
  ChildDir, ChildRel: string;
begin
  Code := FindFirst(TPath.Combine(ADir, '*'), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if ARelBase = '' then
          ChildRel := SR.Name
        else
          ChildRel := ARelBase + PathDelim + SR.Name;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          ChildDir := TPath.Combine(ADir, SR.Name);
          CollectFiles(ChildDir, ChildRel, APaths);
        end
        else
          APaths.AddOrSetValue(ChildRel, TPath.Combine(ADir, SR.Name));
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

function MakeSyncItem(const ARel, ASrcPath, ADstPath: string;
  AReason: TSyncReason): TSyncItem;
begin
  Result.RelPath := ARel;
  Result.SrcURI := PathToFileUri(ASrcPath);
  Result.DstURI := PathToFileUri(ADstPath);
  Result.Reason := AReason;
end;

procedure AppendSyncItem(var AItems: TArray<TSyncItem>; const AItem: TSyncItem);
var
  N: Integer;
begin
  N := Length(AItems);
  SetLength(AItems, N + 1);
  AItems[N] := AItem;
end;

function SnapshotByRel(const ASnapshot: TArray<TSyncSnapshotEntry>):
  TDictionary<string, TSyncSnapshotEntry>;
var
  I: Integer;
begin
  Result := TDictionary<string, TSyncSnapshotEntry>.Create(
    TIStringComparer.Ordinal);
  for I := 0 to High(ASnapshot) do
    if ASnapshot[I].RelPath <> '' then
      Result.AddOrSetValue(ASnapshot[I].RelPath, ASnapshot[I]);
end;

function CompareDirsOneWay(const ASrcRoot, ADstRoot: string;
  AByContent: Boolean): TArray<TSyncItem>;
var
  Src, Dst, Rel, SrcPath, DstPath: string;
  SrcMap: TDictionary<string, string>;
  Pair: TPair<string, string>;
begin
  SetLength(Result, 0);
  Src := ExcludeTrailingPathDelimiter(ASrcRoot);
  Dst := ExcludeTrailingPathDelimiter(ADstRoot);
  if (Src = '') or (Dst = '') then
    Exit;
  if not TDirectory.Exists(Src) then
    Exit;
  SrcMap := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    CollectFiles(Src, '', SrcMap);
    for Pair in SrcMap do
    begin
      Rel := Pair.Key;
      SrcPath := Pair.Value;
      DstPath := TPath.Combine(Dst, Rel);
      if not TFile.Exists(DstPath) then
        AppendSyncItem(Result, MakeSyncItem(Rel, SrcPath, DstPath, srMissing))
      else if TFile.GetLastWriteTimeUtc(SrcPath) >
        TFile.GetLastWriteTimeUtc(DstPath) then
        AppendSyncItem(Result, MakeSyncItem(Rel, SrcPath, DstPath, srNewer))
      else if AByContent and not FilesContentEqual(SrcPath, DstPath) then
        AppendSyncItem(Result, MakeSyncItem(Rel, SrcPath, DstPath, srContentDiff));
    end;
  finally
    SrcMap.Free;
  end;
end;

procedure CompareDirsOneWayAsync(const ASrcRoot, ADstRoot: string;
  AOnDone: TSyncCompareDone; AByContent: Boolean);
begin
  if not Assigned(AOnDone) then
    Exit;
  TTask.Run(
    procedure
    var
      Items: TArray<TSyncItem>;
      Err: string;
    begin
      Err := '';
      SetLength(Items, 0);
      try
        Items := CompareDirsOneWay(ASrcRoot, ADstRoot, AByContent);
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          AOnDone(Items, Err);
        end);
    end);
end;

// One key's worth of CompareDirsTwoWay's decision tree (missing on one side /
// snapshot-driven newer-or-conflict / mtime fallback when there's no snapshot).
procedure ClassifyTwoWaySyncPair(const ARel, ALeftPath, ARightPath: string;
  ALeftExists, ARightExists, AHasSnap: Boolean; const ASnap: TSyncSnapshotEntry;
  AByContent: Boolean; var ACopies, AConflicts: TArray<TSyncItem>);
var
  LeftChanged, RightChanged: Boolean;

  procedure MaybeContentDiff;
  begin
    if AByContent and ALeftExists and ARightExists and
       not FilesContentEqual(ALeftPath, ARightPath) then
      AppendSyncItem(ACopies, MakeSyncItem(ARel, ALeftPath, ARightPath, srContentDiff));
  end;

begin
  if ALeftExists and not ARightExists then
  begin
    AppendSyncItem(ACopies, MakeSyncItem(ARel, ALeftPath, ARightPath, srMissing));
    Exit;
  end;
  if ARightExists and not ALeftExists then
  begin
    AppendSyncItem(ACopies, MakeSyncItem(ARel, ARightPath, ALeftPath, srMissingOnSrc));
    Exit;
  end;
  if not (ALeftExists and ARightExists) then
    Exit;

  if AHasSnap then
  begin
    LeftChanged := FileUtcTicks(ALeftPath) <> ASnap.LeftUtcTicks;
    RightChanged := FileUtcTicks(ARightPath) <> ASnap.RightUtcTicks;
    if LeftChanged and RightChanged then
    begin
      if FileUtcTicks(ALeftPath) = FileUtcTicks(ARightPath) then
      begin
        MaybeContentDiff;
        Exit;
      end;
      AppendSyncItem(AConflicts, MakeSyncItem(ARel, ALeftPath, ARightPath, srConflict));
      Exit;
    end;
    if LeftChanged then
    begin
      AppendSyncItem(ACopies, MakeSyncItem(ARel, ALeftPath, ARightPath, srNewer));
      Exit;
    end;
    if RightChanged then
    begin
      AppendSyncItem(ACopies, MakeSyncItem(ARel, ARightPath, ALeftPath, srNewerOnDst));
      Exit;
    end;
    MaybeContentDiff;
    Exit;
  end;

  if TFile.GetLastWriteTimeUtc(ALeftPath) > TFile.GetLastWriteTimeUtc(ARightPath) then
    AppendSyncItem(ACopies, MakeSyncItem(ARel, ALeftPath, ARightPath, srNewer))
  else if TFile.GetLastWriteTimeUtc(ARightPath) > TFile.GetLastWriteTimeUtc(ALeftPath) then
    AppendSyncItem(ACopies, MakeSyncItem(ARel, ARightPath, ALeftPath, srNewerOnDst))
  else
    MaybeContentDiff;
end;

function CompareDirsTwoWay(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>;
  AByContent: Boolean): TArray<TSyncItem>;
var
  Left, Right, Rel, LeftPath, RightPath: string;
  LeftMap, RightMap: TDictionary<string, string>;
  Keys: TStringList;
  SnapMap: TDictionary<string, TSyncSnapshotEntry>;
  Snap: TSyncSnapshotEntry;
  HasSnap, LeftExists, RightExists: Boolean;
  I: Integer;
  Copies, Conflicts: TArray<TSyncItem>;
begin
  SetLength(Result, 0);
  SetLength(Copies, 0);
  SetLength(Conflicts, 0);
  Left := ExcludeTrailingPathDelimiter(ASrcRoot);
  Right := ExcludeTrailingPathDelimiter(ADstRoot);
  if (Left = '') or (Right = '') then
    Exit;
  if not TDirectory.Exists(Left) then
    Exit;

  LeftMap := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  RightMap := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  SnapMap := SnapshotByRel(ASnapshot);
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := False;
    Keys.Duplicates := dupIgnore;
    Keys.Sorted := True;
    CollectFiles(Left, '', LeftMap);
    if TDirectory.Exists(Right) then
      CollectFiles(Right, '', RightMap);
    for Rel in LeftMap.Keys do
      Keys.Add(Rel);
    for Rel in RightMap.Keys do
      Keys.Add(Rel);

    for I := 0 to Keys.Count - 1 do
    begin
      Rel := Keys[I];
      LeftExists := LeftMap.TryGetValue(Rel, LeftPath);
      RightExists := RightMap.TryGetValue(Rel, RightPath);
      HasSnap := SnapMap.TryGetValue(Rel, Snap);
      if not LeftExists then
        LeftPath := TPath.Combine(Left, Rel);
      if not RightExists then
        RightPath := TPath.Combine(Right, Rel);

      ClassifyTwoWaySyncPair(Rel, LeftPath, RightPath, LeftExists, RightExists,
        HasSnap, Snap, AByContent, Copies, Conflicts);
    end;

    SetLength(Result, Length(Copies) + Length(Conflicts));
    for I := 0 to High(Copies) do
      Result[I] := Copies[I];
    for I := 0 to High(Conflicts) do
      Result[Length(Copies) + I] := Conflicts[I];
  finally
    Keys.Free;
    SnapMap.Free;
    RightMap.Free;
    LeftMap.Free;
  end;
end;

procedure CompareDirsTwoWayAsync(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>; AOnDone: TSyncCompareDone;
  AByContent: Boolean);
begin
  if not Assigned(AOnDone) then
    Exit;
  TTask.Run(
    procedure
    var
      Items: TArray<TSyncItem>;
      Err: string;
      Snap: TArray<TSyncSnapshotEntry>;
    begin
      Err := '';
      Snap := Copy(ASnapshot);
      SetLength(Items, 0);
      try
        Items := CompareDirsTwoWay(ASrcRoot, ADstRoot, Snap, AByContent);
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          AOnDone(Items, Err);
        end);
    end);
end;

function CountSyncReasons(const AItems: TArray<TSyncItem>;
  out AMissing, ANewer: Integer): Integer;
var
  I: Integer;
begin
  AMissing := 0;
  ANewer := 0;
  for I := 0 to High(AItems) do
    case AItems[I].Reason of
      srMissing: Inc(AMissing);
      srNewer: Inc(ANewer);
      srMissingOnSrc, srNewerOnDst, srConflict, srContentDiff: ;
    end;
  Result := Length(AItems);
end;

function PreviewTag(AReason: TSyncReason): string;
begin
  case AReason of
    srMissing: Result := '[+]';
    srNewer: Result := '[>]';
    srMissingOnSrc: Result := '[<+]';
    srNewerOnDst: Result := '[<]';
    srConflict: Result := '[!]';
    srContentDiff: Result := '[!=]';
  else
    Result := '[?]';
  end;
end;

function FormatSyncPreviewLines(const AItems: TArray<TSyncItem>;
  AMaxLines: Integer): TArray<string>;
var
  I, N, Cap: Integer;
begin
  if AMaxLines < 1 then
    AMaxLines := 1;
  Cap := Length(AItems);
  if Cap > AMaxLines then
    N := AMaxLines
  else
    N := Cap;
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := PreviewTag(AItems[I].Reason) + ' ' + AItems[I].RelPath;
  if Cap > AMaxLines then
  begin
    SetLength(Result, N + 1);
    Result[N] := Format('… and %d more', [Cap - AMaxLines]);
  end;
end;

function FormatDirSyncStatus(const AItems: TArray<TSyncItem>): string;
var
  I, Missing, Newer, MissingLeft, NewerLeft, Conflicts, ContentDiffs,
    CopyN, ToRight, ToLeft: Integer;
  Extra: string;
begin
  Missing := 0;
  Newer := 0;
  MissingLeft := 0;
  NewerLeft := 0;
  Conflicts := 0;
  ContentDiffs := 0;
  for I := 0 to High(AItems) do
    case AItems[I].Reason of
      srMissing: Inc(Missing);
      srNewer: Inc(Newer);
      srMissingOnSrc: Inc(MissingLeft);
      srNewerOnDst: Inc(NewerLeft);
      srConflict: Inc(Conflicts);
      srContentDiff: Inc(ContentDiffs);
    end;
  ToRight := Missing + Newer;
  ToLeft := MissingLeft + NewerLeft;
  CopyN := ToRight + ToLeft;
  Extra := '';
  if ContentDiffs > 0 then
    Extra := Extra + Format(', %d content-diff', [ContentDiffs]);
  if (ToLeft = 0) and (Conflicts = 0) then
    Result := Format('%d to copy (%d missing, %d newer)',
      [CopyN, Missing, Newer])
  else if Conflicts = 0 then
    Result := Format('%d to copy (%d ->, %d <-)', [CopyN, ToRight, ToLeft])
  else
    Result := Format('%d to copy (%d ->, %d <-), %d conflict(s)',
      [CopyN, ToRight, ToLeft, Conflicts]);
  Result := Result + Extra;
end;

procedure CollectDirSyncJobPairs(const AItems: TArray<TSyncItem>;
  out ASources, ADestURIs: TArray<string>; ATwoWay: Boolean);
var
  I, N: Integer;
begin
  SetLength(ASources, 0);
  SetLength(ADestURIs, 0);
  for I := 0 to High(AItems) do
  begin
    if SyncItemIsConflict(AItems[I]) then
      Continue;
    if (AItems[I].Reason = srContentDiff) and ATwoWay then
      Continue;
    if SyncItemCopiesToLeft(AItems[I]) and not ATwoWay then
      Continue;
    if not (SyncItemCopiesToRight(AItems[I]) or SyncItemCopiesToLeft(AItems[I])) then
      Continue;
    N := Length(ASources);
    SetLength(ASources, N + 1);
    SetLength(ADestURIs, N + 1);
    ASources[N] := AItems[I].SrcURI;
    ADestURIs[N] := AItems[I].DstURI;
  end;
end;

function DirSyncUrisAreLocalFolders(const ASrcURI, ADstURI: string): Boolean;
begin
  Result := not (HasArchiveChain(ASrcURI) or HasArchiveChain(ADstURI) or
    IsFindUri(ASrcURI) or IsFindUri(ADstURI));
end;

function DirSyncStateFilePath: string;
begin
  Result := GetConfigFilePath(cDirSyncStateFile);
end;

function PairMatches(const AObj: TJSONObject; const ALeft, ARight: string;
  out ASwapped: Boolean): Boolean;
var
  StoredLeft, StoredRight: string;
begin
  Result := False;
  ASwapped := False;
  if AObj = nil then
    Exit;
  StoredLeft := AObj.GetValue<string>('left', '');
  StoredRight := AObj.GetValue<string>('right', '');
  if SameSyncRoot(StoredLeft, ALeft) and SameSyncRoot(StoredRight, ARight) then
    Exit(True);
  if SameSyncRoot(StoredLeft, ARight) and SameSyncRoot(StoredRight, ALeft) then
  begin
    ASwapped := True;
    Exit(True);
  end;
end;

function EntriesFromFilesArray(Arr: TJSONArray; ASwapped: Boolean):
  TArray<TSyncSnapshotEntry>;
var
  I: Integer;
  Item: TJSONValue;
  Obj: TJSONObject;
  Ent: TSyncSnapshotEntry;
  LeftTicks, RightTicks: Int64;
begin
  SetLength(Result, 0);
  if Arr = nil then
    Exit;
  for I := 0 to Arr.Count - 1 do
  begin
    Item := Arr.Items[I];
    if not (Item is TJSONObject) then
      Continue;
    Obj := TJSONObject(Item);
    Ent.RelPath := Obj.GetValue<string>('rel', '');
    if Ent.RelPath = '' then
      Continue;
    LeftTicks := Obj.GetValue<Int64>('leftTicks', 0);
    RightTicks := Obj.GetValue<Int64>('rightTicks', 0);
    if ASwapped then
    begin
      Ent.LeftUtcTicks := RightTicks;
      Ent.RightUtcTicks := LeftTicks;
    end
    else
    begin
      Ent.LeftUtcTicks := LeftTicks;
      Ent.RightUtcTicks := RightTicks;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Ent;
  end;
end;

function LoadDirSyncSnapshotFromFile(const AFile, ALeftRoot,
  ARightRoot: string): TArray<TSyncSnapshotEntry>;
var
  Content: string;
  Root: TJSONValue;
  Pairs: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  Swapped: Boolean;
  FilesArr: TJSONArray;
begin
  SetLength(Result, 0);
  if (AFile = '') or not TFile.Exists(AFile) then
    Exit;
  try
    Content := TFile.ReadAllText(AFile, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Content);
    if Root = nil then
      Exit;
    try
      if not (Root is TJSONObject) then
        Exit;
      if not TJSONObject(Root).TryGetValue<TJSONArray>('pairs', Pairs) then
        Exit;
      for I := 0 to Pairs.Count - 1 do
      begin
        if not (Pairs.Items[I] is TJSONObject) then
          Continue;
        Obj := TJSONObject(Pairs.Items[I]);
        if not PairMatches(Obj, ALeftRoot, ARightRoot, Swapped) then
          Continue;
        if Obj.TryGetValue<TJSONArray>('files', FilesArr) then
          Result := EntriesFromFilesArray(FilesArr, Swapped);
        Exit;
      end;
    finally
      Root.Free;
    end;
  except
    SetLength(Result, 0);
  end;
end;

function FilesArrayFromEntries(const AEntries: TArray<TSyncSnapshotEntry>): TJSONArray;
var
  I: Integer;
  Obj: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(AEntries) do
  begin
    if AEntries[I].RelPath = '' then
      Continue;
    Obj := TJSONObject.Create;
    Obj.AddPair('rel', AEntries[I].RelPath);
    Obj.AddPair('leftTicks', TJSONNumber.Create(AEntries[I].LeftUtcTicks));
    Obj.AddPair('rightTicks', TJSONNumber.Create(AEntries[I].RightUtcTicks));
    Result.AddElement(Obj);
  end;
end;

// Reads AFile's existing "pairs" (if any) and clones every entry that is NOT
// this (ALeftRoot, ARightRoot) pair into AKept — i.e. every other root-pair's
// snapshot, kept as-is while this one gets replaced below. Silently gives up
// (AKept left however far it got) on a missing/corrupt file.
procedure LoadKeptSyncPairs(const AFile, ALeftRoot, ARightRoot: string;
  AKept: TList<TJSONValue>);
var
  Content: string;
  Root: TJSONValue;
  Pairs: TJSONArray;
  Obj: TJSONObject;
  Swapped: Boolean;
  I: Integer;
begin
  if (AFile = '') or not TFile.Exists(AFile) then
    Exit;
  try
    Content := TFile.ReadAllText(AFile, TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(Content);
    try
      if not ((Root is TJSONObject) and
              TJSONObject(Root).TryGetValue<TJSONArray>('pairs', Pairs)) then
        Exit;
      for I := 0 to Pairs.Count - 1 do
      begin
        if not (Pairs.Items[I] is TJSONObject) then
          Continue;
        Obj := TJSONObject(Pairs.Items[I]);
        if PairMatches(Obj, ALeftRoot, ARightRoot, Swapped) then
          Continue;
        AKept.Add(TJSONValue(Obj.Clone));
      end;
    finally
      Root.Free;
    end;
  except
  end;
end;

procedure SaveDirSyncSnapshotToFile(const AFile, ALeftRoot, ARightRoot: string;
  const AEntries: TArray<TSyncSnapshotEntry>);
var
  Doc: TJSONObject;
  NewPairs: TJSONArray;
  I, Start: Integer;
  PairObj: TJSONObject;
  Kept: TList<TJSONValue>;
begin
  Doc := nil;
  Kept := TList<TJSONValue>.Create;
  NewPairs := TJSONArray.Create;
  try
    LoadKeptSyncPairs(AFile, ALeftRoot, ARightRoot, Kept);

    Start := 0;
    if Kept.Count + 1 > cDirSyncStateMaxPairs then
      Start := Kept.Count + 1 - cDirSyncStateMaxPairs;
    for I := 0 to Start - 1 do
      Kept[I].Free;
    for I := Start to Kept.Count - 1 do
      NewPairs.AddElement(Kept[I]);
    Kept.Clear;

    PairObj := TJSONObject.Create;
    PairObj.AddPair('left', NormSyncRoot(ALeftRoot));
    PairObj.AddPair('right', NormSyncRoot(ARightRoot));
    PairObj.AddPair('files', FilesArrayFromEntries(AEntries));
    NewPairs.AddElement(PairObj);

    Doc := TJSONObject.Create;
    Doc.AddPair('pairs', NewPairs);
    NewPairs := nil;
    TFile.WriteAllText(AFile, Doc.ToJSON, TEncoding.UTF8);
  finally
    for I := 0 to Kept.Count - 1 do
      Kept[I].Free;
    Kept.Free;
    NewPairs.Free;
    Doc.Free;
  end;
end;

function LoadDirSyncSnapshot(const ALeftRoot, ARightRoot: string): TArray<TSyncSnapshotEntry>;
begin
  Result := LoadDirSyncSnapshotFromFile(DirSyncStateFilePath, ALeftRoot, ARightRoot);
end;

procedure SaveDirSyncSnapshot(const ALeftRoot, ARightRoot: string;
  const AEntries: TArray<TSyncSnapshotEntry>);
begin
  SaveDirSyncSnapshotToFile(DirSyncStateFilePath, ALeftRoot, ARightRoot, AEntries);
end;

procedure CommitDirSyncSnapshotToFile(const AFile, ALeftRoot, ARightRoot: string;
  const AConflictRels: TArray<string>);
var
  Left, Right, Rel: string;
  LeftMap, RightMap: TDictionary<string, string>;
  Old: TArray<TSyncSnapshotEntry>;
  OldMap: TDictionary<string, TSyncSnapshotEntry>;
  Keys: TStringList;
  Entries: TArray<TSyncSnapshotEntry>;
  Ent, Prev: TSyncSnapshotEntry;
  I: Integer;
  LeftPath, RightPath: string;
begin
  Left := ExcludeTrailingPathDelimiter(ALeftRoot);
  Right := ExcludeTrailingPathDelimiter(ARightRoot);
  if (Left = '') or (Right = '') then
    Exit;

  Old := LoadDirSyncSnapshotFromFile(AFile, Left, Right);
  OldMap := SnapshotByRel(Old);
  LeftMap := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  RightMap := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := False;
    Keys.Duplicates := dupIgnore;
    Keys.Sorted := True;
    if TDirectory.Exists(Left) then
      CollectFiles(Left, '', LeftMap);
    if TDirectory.Exists(Right) then
      CollectFiles(Right, '', RightMap);
    for Rel in LeftMap.Keys do
      Keys.Add(Rel);
    for Rel in RightMap.Keys do
      Keys.Add(Rel);

    SetLength(Entries, Keys.Count);
    for I := 0 to Keys.Count - 1 do
    begin
      Rel := Keys[I];
      Ent.RelPath := Rel;
      if RelInList(Rel, AConflictRels) and OldMap.TryGetValue(Rel, Prev) then
        Ent := Prev
      else
      begin
        if LeftMap.TryGetValue(Rel, LeftPath) then
          Ent.LeftUtcTicks := FileUtcTicks(LeftPath)
        else
          Ent.LeftUtcTicks := 0;
        if RightMap.TryGetValue(Rel, RightPath) then
          Ent.RightUtcTicks := FileUtcTicks(RightPath)
        else
          Ent.RightUtcTicks := 0;
      end;
      Entries[I] := Ent;
    end;
    SaveDirSyncSnapshotToFile(AFile, Left, Right, Entries);
  finally
    Keys.Free;
    OldMap.Free;
    RightMap.Free;
    LeftMap.Free;
  end;
end;

procedure CommitDirSyncSnapshot(const ALeftRoot, ARightRoot: string;
  const AConflictRels: TArray<string>);
begin
  CommitDirSyncSnapshotToFile(DirSyncStateFilePath, ALeftRoot, ARightRoot,
    AConflictRels);
end;

end.
