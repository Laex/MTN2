unit uDualPanelSync;

{ Directory compare for Directory Sync.
  One-way Active -> Inactive (missing | newer).
  Two-way <-> - copy direction follows whichever side is newer;
  conflicts (both sides changed since the last successful sync) stay
  unresolved and are listed for a manual choice. A file the last sync saw on
  both sides and now found on one only counts as deleted on the other.
  Optional content mode (size + byte compare) marks files that
  share a timestamp but differ in bytes. Local file:// only. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Threading,
  System.SyncObjs, uVfsTypes, uSyncIgnore;

type
  TSyncReason = (srMissing, srNewer, srMissingOnSrc, srNewerOnDst, srConflict,
    srContentDiff);

  // saAuto follows Reason, Peer and the sync mode; the other values are a
  // manual choice that overrides them. saDelete removes a file that exists on
  // one side only: the target in one-way mode, either side in two-way.
  TSyncAction = (saAuto, saCopyRight, saCopyLeft, saSkip, saDelete);

  // What the previous sync tells about a file present on one side only: it
  // was on both then, so the missing copy was deleted. peDeletedChanged marks
  // a surviving copy edited since.
  TSyncPeer = (peNone, peDeleted, peDeletedChanged);

  TSyncItem = record
    RelPath: string;
    SrcURI: string;
    DstURI: string;
    Reason: TSyncReason;
    Action: TSyncAction;
    Peer: TSyncPeer;
  end;

  TSyncSnapshotEntry = record
    RelPath: string;
    LeftUtcTicks: Int64;
    RightUtcTicks: Int64;
  end;

  TSyncCompareDone = reference to procedure(const AItems: TArray<TSyncItem>;
    const AError: string);

  TSyncStage = (ssScanning, ssComparing);

  TSyncProgressInfo = record
    Stage: TSyncStage;
    Files, Dirs: Int64;
    /// <summary>Pairs classified so far and the pairs to classify.</summary>
    Done, Total: Int64;
    /// <summary>Bytes read by the content comparison.</summary>
    Bytes: Int64;
    /// <summary>The folder being scanned, or the path being compared.</summary>
    Current: string;
  end;

  /// <summary>Counters and the stop flag shared by a running comparison and
  /// its owner. The counters are written on the worker thread; OnChanged runs
  /// on the main thread, at most a few times a second.</summary>
  ISyncProgress = interface
    ['{6C1D7B52-3F0E-4B7A-9D55-2A8E41C0B9F3}']
    procedure Cancel;
    function Cancelled: Boolean;
    function Snapshot: TSyncProgressInfo;
    procedure NoteDir(const ADir: string);
    procedure NoteFile;
    procedure BeginCompare(ATotal: Int64);
    procedure NoteCompared(const ARel: string);
    procedure NoteBytes(AValue: Int64);
    procedure SetOnChanged(const AValue: TProc);
  end;

function CompareDirsOneWay(const ASrcRoot, ADstRoot: string;
  AByContent: Boolean = False): TArray<TSyncItem>;
procedure CompareDirsOneWayAsync(const ASrcRoot, ADstRoot: string;
  AOnDone: TSyncCompareDone; AByContent: Boolean = False);
function NewSyncProgress: ISyncProgress;
/// <summary>"Scanning: N files in M folders" or "Comparing: N of M files".</summary>
function FormatSyncProgress(const AInfo: TSyncProgressInfo;
  AByContent: Boolean): string;
/// <summary>-1 while the total is not known yet.</summary>
function SyncProgressPercent(const AInfo: TSyncProgressInfo): Integer;
/// <summary>Short chip text: the file count while scanning, then the percentage.</summary>
function SyncProgressBadge(const AInfo: TSyncProgressInfo): string;
/// <summary>A cancelled comparison returns no items.</summary>
function CompareDirsTwoWay(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>;
  AByContent: Boolean = False; const AProgress: ISyncProgress = nil;
  const AFilter: ISyncFilter = nil): TArray<TSyncItem>;
procedure CompareDirsTwoWayAsync(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>; AOnDone: TSyncCompareDone;
  AByContent: Boolean = False; const AProgress: ISyncProgress = nil;
  const AFilter: ISyncFilter = nil);
function CountSyncReasons(const AItems: TArray<TSyncItem>;
  out AMissing, ANewer: Integer): Integer;
function FormatSyncPreviewLines(const AItems: TArray<TSyncItem>;
  AMaxLines: Integer = 12): TArray<string>;
function FormatDirSyncStatus(const AItems: TArray<TSyncItem>): string;
procedure CollectDirSyncJobPairs(const AItems: TArray<TSyncItem>;
  out ASources, ADestURIs: TArray<string>; ATwoWay: Boolean = False;
  AMirror: Boolean = False);
/// <summary>Files to be removed: those only on the target (mirror mode or a
/// manual choice), and in two-way mode also the survivors of a deletion on
/// the other side.</summary>
function CollectDirSyncDeletePaths(const AItems: TArray<TSyncItem>;
  ATwoWay, AMirror: Boolean): TArray<string>;
function DirSyncUrisAreLocalFolders(const ASrcURI, ADstURI: string): Boolean;
function SyncItemCopiesToRight(const AItem: TSyncItem): Boolean;
function SyncItemCopiesToLeft(const AItem: TSyncItem): Boolean;
function SyncItemIsConflict(const AItem: TSyncItem): Boolean;
function SyncItemIsContentDiff(const AItem: TSyncItem): Boolean;
function CountSyncConflicts(const AItems: TArray<TSyncItem>): Integer;
function CountSyncContentDiffs(const AItems: TArray<TSyncItem>): Integer;
function CollectDirSyncConflictRels(const AItems: TArray<TSyncItem>): TArray<string>;
function CollectDirSyncUnresolvedRels(const AItems: TArray<TSyncItem>;
  ATwoWay: Boolean; AMirror: Boolean = False): TArray<string>;
function FilesContentEqual(const ALeft, ARight: string;
  const AProgress: ISyncProgress = nil): Boolean;

function SyncItemLeftURI(const AItem: TSyncItem): string;
function SyncItemRightURI(const AItem: TSyncItem): string;
function EffectiveSyncAction(const AItem: TSyncItem;
  ATwoWay: Boolean; AMirror: Boolean = False): TSyncAction;
function SyncActionAllowed(const AItem: TSyncItem;
  AAction: TSyncAction; ATwoWay: Boolean = False): Boolean;
/// <summary>Sets a manual action; False when the action does not apply to the
/// item (copying from a side where the file does not exist).</summary>
function ApplySyncAction(var AItem: TSyncItem; AAction: TSyncAction;
  ATwoWay: Boolean = False): Boolean;
/// <summary>One list row per item: action glyph, reason tag, relative path.
/// AViewIdx maps rows back to AItems.</summary>
function FormatSyncPlanLines(const AItems: TArray<TSyncItem>;
  ATwoWay, AOnlySkipped: Boolean; out AViewIdx: TArray<Integer>;
  AMirror: Boolean = False): TArray<string>;
function FormatDirSyncPlanStatus(const AItems: TArray<TSyncItem>;
  ATwoWay: Boolean; AMirror: Boolean = False): string;
/// <summary>A path longer than AMaxLen keeps its start and, with more room,
/// its end (the folder names that tell two roots apart); the middle becomes
/// "...".</summary>
function FitSyncPath(const APath: string; AMaxLen: Integer): string;

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
/// <summary>Drops the entries of files that are gone from both sides, so a
/// file that later appears under the same name counts as new.</summary>
procedure PruneDirSyncSnapshotFile(const AFile, ALeftRoot, ARightRoot: string);
procedure PruneDirSyncSnapshot(const ALeftRoot, ARightRoot: string);

implementation

uses
  System.JSON, System.Generics.Collections, System.Generics.Defaults,
  System.Math, uConfigLocation, uStrings;

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

function FilesContentEqual(const ALeft, ARight: string;
  const AProgress: ISyncProgress): Boolean;
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
    SizeL := TFile.GetSize(WinApiPath(ALeft));
    SizeR := TFile.GetSize(WinApiPath(ARight));
    if SizeL <> SizeR then
      Exit;
    if SizeL = 0 then
      Exit(True);
    SL := TFileStream.Create(WinApiPath(ALeft), fmOpenRead or fmShareDenyNone);
    try
      SR := TFileStream.Create(WinApiPath(ARight), fmOpenRead or fmShareDenyNone);
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
          if AProgress <> nil then
          begin
            AProgress.NoteBytes(NL);
            if AProgress.Cancelled then
              Exit(False);
          end;
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
  ATwoWay: Boolean; AMirror: Boolean): TArray<string>;
var
  I, N: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(AItems) do
  begin
    if EffectiveSyncAction(AItems[I], ATwoWay, AMirror) <> saSkip then
      Continue;
    if (AItems[I].Reason in [srConflict, srContentDiff]) or
       (ATwoWay and (AItems[I].Peer = peDeletedChanged)) or
       (AItems[I].Action = saSkip) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := AItems[I].RelPath;
    end;
  end;
end;

function SyncItemLeftURI(const AItem: TSyncItem): string;
begin
  if AItem.Reason in [srMissingOnSrc, srNewerOnDst] then
    Result := AItem.DstURI
  else
    Result := AItem.SrcURI;
end;

function SyncItemRightURI(const AItem: TSyncItem): string;
begin
  if AItem.Reason in [srMissingOnSrc, srNewerOnDst] then
    Result := AItem.SrcURI
  else
    Result := AItem.DstURI;
end;

function TwoWayAutoAction(const AItem: TSyncItem): TSyncAction;
begin
  case AItem.Peer of
    peDeleted: Exit(saDelete);
    peDeletedChanged: Exit(saSkip);
  end;
  case AItem.Reason of
    srMissing, srNewer: Result := saCopyRight;
    srMissingOnSrc, srNewerOnDst: Result := saCopyLeft;
  else
    Result := saSkip;
  end;
end;

function OneWayAutoAction(AReason: TSyncReason; AMirror: Boolean): TSyncAction;
begin
  case AReason of
    srMissing, srNewer, srContentDiff:
      Result := saCopyRight;
    srMissingOnSrc:
      if AMirror then
        Result := saDelete
      else
        Result := saSkip;
  else
    Result := saSkip;
  end;
end;

function EffectiveSyncAction(const AItem: TSyncItem;
  ATwoWay: Boolean; AMirror: Boolean): TSyncAction;
begin
  if AItem.Action = saAuto then
  begin
    if ATwoWay then
      Exit(TwoWayAutoAction(AItem));
    Exit(OneWayAutoAction(AItem.Reason, AMirror));
  end;
  // A deletion chosen in two-way mode may not apply to one-way.
  if (AItem.Action = saDelete) and
     not SyncActionAllowed(AItem, saDelete, ATwoWay) then
    Exit(saSkip);
  Result := AItem.Action;
end;

function SyncActionAllowed(const AItem: TSyncItem;
  AAction: TSyncAction; ATwoWay: Boolean): Boolean;
begin
  case AAction of
    saCopyRight: Result := AItem.Reason <> srMissingOnSrc;
    saCopyLeft: Result := AItem.Reason <> srMissing;
    saDelete: Result := (AItem.Reason = srMissingOnSrc) or
      (ATwoWay and (AItem.Reason = srMissing));
  else
    Result := True;
  end;
end;

function ApplySyncAction(var AItem: TSyncItem; AAction: TSyncAction;
  ATwoWay: Boolean): Boolean;
begin
  Result := SyncActionAllowed(AItem, AAction, ATwoWay);
  if Result then
    AItem.Action := AAction;
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
  APaths: TDictionary<string, string>; const AProgress: ISyncProgress = nil;
  const AFilter: ISyncFilter = nil);
var
  SR: TSearchRec;
  Code: Integer;
  ChildDir, ChildRel: string;
begin
  if AProgress <> nil then
    AProgress.NoteDir(ADir);
  Code := FindFirst(SafeCombinePath(ADir, '*'), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (AProgress <> nil) and AProgress.Cancelled then
        Exit;
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if ARelBase = '' then
          ChildRel := SR.Name
        else
          ChildRel := ARelBase + PathDelim + SR.Name;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          if (AFilter = nil) or not AFilter.Skip(ChildRel, True,
             (SR.Attr and faSymLink) <> 0) then
          begin
            ChildDir := SafeCombinePath(ADir, SR.Name);
            if AFilter <> nil then
              AFilter.EnterDir(ChildRel, ChildDir);
            CollectFiles(ChildDir, ChildRel, APaths, AProgress, AFilter);
          end;
        end
        else if (AFilter = nil) or not AFilter.Skip(ChildRel, False, False) then
        begin
          APaths.AddOrSetValue(ChildRel, SafeCombinePath(ADir, SR.Name));
          if AProgress <> nil then
            AProgress.NoteFile;
        end;
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
  Result.Action := saAuto;
  Result.Peer := peNone;
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

type
  TSyncProgress = class(TInterfacedObject, ISyncProgress)
  private
    FLock: TCriticalSection;
    FInfo: TSyncProgressInfo;
    FCancelled: Integer;
    FQueued: Boolean;
    FLastTick: UInt64;
    FOnChanged: TProc;
    procedure Touch;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Cancel;
    function Cancelled: Boolean;
    function Snapshot: TSyncProgressInfo;
    procedure NoteDir(const ADir: string);
    procedure NoteFile;
    procedure BeginCompare(ATotal: Int64);
    procedure NoteCompared(const ARel: string);
    procedure NoteBytes(AValue: Int64);
    procedure SetOnChanged(const AValue: TProc);
  end;

constructor TSyncProgress.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FInfo := Default(TSyncProgressInfo);
end;

destructor TSyncProgress.Destroy;
begin
  FLock.Free;
  inherited;
end;

// Wakes the owner at most every 150 ms; a wake-up already queued absorbs the
// updates that arrive before it runs.
procedure TSyncProgress.Touch;
var
  Fire: Boolean;
  Keep: ISyncProgress;
begin
  FLock.Enter;
  try
    Fire := Assigned(FOnChanged) and not FQueued and
      (TThread.GetTickCount64 - FLastTick >= 150);
    if Fire then
    begin
      FQueued := True;
      FLastTick := TThread.GetTickCount64;
    end;
  finally
    FLock.Leave;
  end;
  if not Fire then
    Exit;
  Keep := Self;
  TThread.Queue(nil,
    procedure
    var
      Handler: TProc;
    begin
      FLock.Enter;
      try
        FQueued := False;
        Handler := FOnChanged;
      finally
        FLock.Leave;
      end;
      if Assigned(Handler) then
        Handler();
      Keep := nil;
    end);
end;

procedure TSyncProgress.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TSyncProgress.Cancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

function TSyncProgress.Snapshot: TSyncProgressInfo;
begin
  FLock.Enter;
  try
    Result := FInfo;
  finally
    FLock.Leave;
  end;
end;

procedure TSyncProgress.NoteDir(const ADir: string);
begin
  FLock.Enter;
  try
    Inc(FInfo.Dirs);
    FInfo.Current := ADir;
  finally
    FLock.Leave;
  end;
  Touch;
end;

procedure TSyncProgress.NoteFile;
begin
  FLock.Enter;
  try
    Inc(FInfo.Files);
  finally
    FLock.Leave;
  end;
  Touch;
end;

procedure TSyncProgress.BeginCompare(ATotal: Int64);
begin
  FLock.Enter;
  try
    FInfo.Stage := ssComparing;
    FInfo.Total := ATotal;
    FInfo.Done := 0;
  finally
    FLock.Leave;
  end;
  Touch;
end;

procedure TSyncProgress.NoteCompared(const ARel: string);
begin
  FLock.Enter;
  try
    Inc(FInfo.Done);
    FInfo.Current := ARel;
  finally
    FLock.Leave;
  end;
  Touch;
end;

procedure TSyncProgress.NoteBytes(AValue: Int64);
begin
  FLock.Enter;
  try
    Inc(FInfo.Bytes, AValue);
  finally
    FLock.Leave;
  end;
  Touch;
end;

procedure TSyncProgress.SetOnChanged(const AValue: TProc);
begin
  FLock.Enter;
  try
    FOnChanged := AValue;
  finally
    FLock.Leave;
  end;
end;

function NewSyncProgress: ISyncProgress;
begin
  Result := TSyncProgress.Create;
end;

function FormatSyncProgress(const AInfo: TSyncProgressInfo;
  AByContent: Boolean): string;
begin
  if AInfo.Stage = ssScanning then
    Exit(T('ui.dirSync.scanning', 'Scanning: %d files in %d folders',
      [AInfo.Files, AInfo.Dirs]));
  Result := T('ui.dirSync.comparingFiles', 'Comparing: %d of %d files',
    [AInfo.Done, AInfo.Total]);
  if AByContent and (AInfo.Bytes >= 1024 * 1024) then
    Result := Result + T('ui.dirSync.readMb', ' (%d MB read)',
      [AInfo.Bytes div (1024 * 1024)]);
end;

function SyncProgressPercent(const AInfo: TSyncProgressInfo): Integer;
begin
  if (AInfo.Stage <> ssComparing) or (AInfo.Total <= 0) then
    Exit(-1);
  Result := Integer((AInfo.Done * 100) div AInfo.Total);
end;

function SyncProgressBadge(const AInfo: TSyncProgressInfo): string;
begin
  if AInfo.Stage = ssScanning then
    Result := IntToStr(AInfo.Files)
  else
    Result := IntToStr(Max(SyncProgressPercent(AInfo), 0)) + '%';
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
      DstPath := SafeCombinePath(Dst, Rel);
      if not TFile.Exists(DstPath) then
        AppendSyncItem(Result, MakeSyncItem(Rel, SrcPath, DstPath, srMissing))
      else if CompareFileTimes(TFile.GetLastWriteTimeUtc(SrcPath),
        TFile.GetLastWriteTimeUtc(DstPath)) > 0 then
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

// A file present on one side only. ASyncedTicks is its write time at the last
// sync that saw it on both sides, or 0 when no deletion may be inferred. It
// counts as deleted on the other side only if it is not on disk there: a filter
// or a skipped link can hide a file that still exists.
function MakeOneSidedSyncItem(const ARel, AHave, AMissing: string;
  AReason: TSyncReason; ASyncedTicks: Int64): TSyncItem;
begin
  Result := MakeSyncItem(ARel, AHave, AMissing, AReason);
  if (ASyncedTicks = 0) or TFile.Exists(WinApiPath(AMissing)) then
    Exit;
  if FileUtcTicks(AHave) = ASyncedTicks then
    Result.Peer := peDeleted
  else
    Result.Peer := peDeletedChanged;
end;

type
  // How two existing copies of one file relate.
  TPairVerdict = (pvSame, pvLeftNewer, pvRightNewer, pvConflict);

function SnapshotVerdict(const ALeftPath, ARightPath: string;
  const ASnap: TSyncSnapshotEntry): TPairVerdict;
var
  LeftTicks, RightTicks: Int64;
  LeftChanged, RightChanged: Boolean;
begin
  LeftTicks := FileUtcTicks(ALeftPath);
  RightTicks := FileUtcTicks(ARightPath);
  LeftChanged := LeftTicks <> ASnap.LeftUtcTicks;
  RightChanged := RightTicks <> ASnap.RightUtcTicks;
  if LeftChanged and RightChanged and (LeftTicks <> RightTicks) then
    Result := pvConflict
  else if LeftChanged and not RightChanged then
    Result := pvLeftNewer
  else if RightChanged and not LeftChanged then
    Result := pvRightNewer
  else
    Result := pvSame;
end;

function TimeVerdict(const ALeftPath, ARightPath: string): TPairVerdict;
begin
  case CompareFileTimes(TFile.GetLastWriteTimeUtc(ALeftPath),
    TFile.GetLastWriteTimeUtc(ARightPath)) of
    1: Result := pvLeftNewer;
    -1: Result := pvRightNewer;
  else
    Result := pvSame;
  end;
end;

// The surviving side's write time if its absence on the other side may mean a
// deletion, else 0. A side where nothing was found, such as an unmounted
// folder, must not read as a mass deletion.
function SyncedSideTicks(AHasSnap: Boolean; const ASnap: TSyncSnapshotEntry;
  ASideTicks: Int64; AOtherEmpty: Boolean): Int64;
begin
  if AHasSnap and not AOtherEmpty and (ASnap.LeftUtcTicks <> 0) and
     (ASnap.RightUtcTicks <> 0) then
    Result := ASideTicks
  else
    Result := 0;
end;

// One key of CompareDirsTwoWay.
procedure ClassifyTwoWaySyncPair(const ARel, ALeftPath, ARightPath: string;
  ALeftExists, ARightExists, AHasSnap: Boolean; const ASnap: TSyncSnapshotEntry;
  AByContent, ALeftEmpty, ARightEmpty: Boolean;
  var ACopies, AConflicts: TArray<TSyncItem>;
  const AProgress: ISyncProgress = nil);
var
  Item: TSyncItem;
  Verdict: TPairVerdict;
begin
  if not (ALeftExists and ARightExists) then
  begin
    if ALeftExists then
      Item := MakeOneSidedSyncItem(ARel, ALeftPath, ARightPath, srMissing,
        SyncedSideTicks(AHasSnap, ASnap, ASnap.LeftUtcTicks, ARightEmpty))
    else if ARightExists then
      Item := MakeOneSidedSyncItem(ARel, ARightPath, ALeftPath, srMissingOnSrc,
        SyncedSideTicks(AHasSnap, ASnap, ASnap.RightUtcTicks, ALeftEmpty))
    else
      Exit;
    if Item.Peer = peDeletedChanged then
      AppendSyncItem(AConflicts, Item)
    else
      AppendSyncItem(ACopies, Item);
    Exit;
  end;

  if AHasSnap then
    Verdict := SnapshotVerdict(ALeftPath, ARightPath, ASnap)
  else
    Verdict := TimeVerdict(ALeftPath, ARightPath);
  case Verdict of
    pvLeftNewer:
      AppendSyncItem(ACopies, MakeSyncItem(ARel, ALeftPath, ARightPath, srNewer));
    pvRightNewer:
      AppendSyncItem(ACopies,
        MakeSyncItem(ARel, ARightPath, ALeftPath, srNewerOnDst));
    pvConflict:
      AppendSyncItem(AConflicts,
        MakeSyncItem(ARel, ALeftPath, ARightPath, srConflict));
  else
    if AByContent and
       not FilesContentEqual(ALeftPath, ARightPath, AProgress) then
      AppendSyncItem(ACopies,
        MakeSyncItem(ARel, ALeftPath, ARightPath, srContentDiff));
  end;
end;

function CompareDirsTwoWay(const ASrcRoot, ADstRoot: string;
  const ASnapshot: TArray<TSyncSnapshotEntry>;
  AByContent: Boolean; const AProgress: ISyncProgress;
  const AFilter: ISyncFilter): TArray<TSyncItem>;
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
    CollectFiles(Left, '', LeftMap, AProgress, AFilter);
    if (AProgress = nil) or not AProgress.Cancelled then
      if TDirectory.Exists(Right) then
        CollectFiles(Right, '', RightMap, AProgress, AFilter);
    if (AProgress <> nil) and AProgress.Cancelled then
      Exit;
    for Rel in LeftMap.Keys do
      Keys.Add(Rel);
    for Rel in RightMap.Keys do
      Keys.Add(Rel);
    if AProgress <> nil then
      AProgress.BeginCompare(Keys.Count);

    for I := 0 to Keys.Count - 1 do
    begin
      if AProgress <> nil then
      begin
        if AProgress.Cancelled then
          Exit;
        AProgress.NoteCompared(Keys[I]);
      end;
      Rel := Keys[I];
      LeftExists := LeftMap.TryGetValue(Rel, LeftPath);
      RightExists := RightMap.TryGetValue(Rel, RightPath);
      HasSnap := SnapMap.TryGetValue(Rel, Snap);
      if not LeftExists then
        LeftPath := SafeCombinePath(Left, Rel);
      if not RightExists then
        RightPath := SafeCombinePath(Right, Rel);

      ClassifyTwoWaySyncPair(Rel, LeftPath, RightPath, LeftExists, RightExists,
        HasSnap, Snap, AByContent, LeftMap.Count = 0, RightMap.Count = 0,
        Copies, Conflicts, AProgress);
    end;

    if (AProgress <> nil) and AProgress.Cancelled then
      Exit;
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
  AByContent: Boolean; const AProgress: ISyncProgress;
  const AFilter: ISyncFilter);
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
        Items := CompareDirsTwoWay(ASrcRoot, ADstRoot, Snap, AByContent, AProgress,
          AFilter);
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

function FitSyncPath(const APath: string; AMaxLen: Integer): string;
var
  Head, Tail: Integer;
begin
  if (AMaxLen < 8) or (Length(APath) <= AMaxLen) then
  begin
    if AMaxLen < 0 then
      AMaxLen := 0;
    Exit(Copy(APath, 1, AMaxLen));
  end;
  Head := (AMaxLen - 3) div 3;
  Tail := AMaxLen - 3 - Head;
  Result := Copy(APath, 1, Head) + '...' + Copy(APath, Length(APath) - Tail + 1, Tail);
end;

function SyncActionGlyph(AAction: TSyncAction): string;
begin
  case AAction of
    saCopyRight: Result := '->';
    saCopyLeft: Result := '<-';
    saDelete: Result := 'XX';
  else
    Result := '--';
  end;
end;

// In two-way mode a deletion names the side the file is gone from.
function PlanTag(const AItem: TSyncItem; ATwoWay: Boolean): string;
var
  Side: string;
begin
  if not ATwoWay or (AItem.Peer = peNone) then
    Exit(PreviewTag(AItem.Reason));
  if AItem.Reason = srMissing then
    Side := 'R'
  else
    Side := 'L';
  if AItem.Peer = peDeleted then
    Result := '[-' + Side + ']'
  else
    Result := '[!' + Side + ']';
end;

function FormatSyncPlanLines(const AItems: TArray<TSyncItem>;
  ATwoWay, AOnlySkipped: Boolean; out AViewIdx: TArray<Integer>;
  AMirror: Boolean): TArray<string>;
var
  I, N: Integer;
  Action: TSyncAction;
  Mark: string;
begin
  SetLength(Result, 0);
  SetLength(AViewIdx, 0);
  for I := 0 to High(AItems) do
  begin
    Action := EffectiveSyncAction(AItems[I], ATwoWay, AMirror);
    if AOnlySkipped and (Action <> saSkip) then
      Continue;
    if AItems[I].Action = saAuto then
      Mark := ' '
    else
      Mark := '*';
    N := Length(Result);
    SetLength(Result, N + 1);
    SetLength(AViewIdx, N + 1);
    Result[N] := SyncActionGlyph(Action) + Mark +
      PlanTag(AItems[I], ATwoWay) + ' ' + AItems[I].RelPath;
    AViewIdx[N] := I;
  end;
end;

function FormatDirSyncPlanStatus(const AItems: TArray<TSyncItem>;
  ATwoWay: Boolean; AMirror: Boolean): string;
var
  I, ToRight, ToLeft, Skipped, Open, ToDelete: Integer;
begin
  ToRight := 0;
  ToLeft := 0;
  Skipped := 0;
  ToDelete := 0;
  for I := 0 to High(AItems) do
    case EffectiveSyncAction(AItems[I], ATwoWay, AMirror) of
      saCopyRight: Inc(ToRight);
      saCopyLeft: Inc(ToLeft);
      saDelete: Inc(ToDelete);
    else
      Inc(Skipped);
    end;
  Open := Length(CollectDirSyncUnresolvedRels(AItems, ATwoWay, AMirror));
  Result := T('ui.dirSync.status', '%d to copy (%d ->, %d <-), %d skipped',
    [ToRight + ToLeft, ToRight, ToLeft, Skipped]);
  if AMirror or (ToDelete > 0) then
    Result := Result + T('ui.dirSync.statusDelete', ', %d to delete', [ToDelete]);
  if Open > 0 then
    Result := Result + T('ui.dirSync.statusOpen', ', %d unresolved', [Open]);
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
  out ASources, ADestURIs: TArray<string>; ATwoWay: Boolean; AMirror: Boolean);
var
  I, N: Integer;
  Action: TSyncAction;
begin
  SetLength(ASources, 0);
  SetLength(ADestURIs, 0);
  for I := 0 to High(AItems) do
  begin
    Action := EffectiveSyncAction(AItems[I], ATwoWay, AMirror);
    if not (Action in [saCopyRight, saCopyLeft]) or
       not SyncActionAllowed(AItems[I], Action) then
      Continue;
    N := Length(ASources);
    SetLength(ASources, N + 1);
    SetLength(ADestURIs, N + 1);
    if Action = saCopyRight then
    begin
      ASources[N] := SyncItemLeftURI(AItems[I]);
      ADestURIs[N] := SyncItemRightURI(AItems[I]);
    end
    else
    begin
      ASources[N] := SyncItemRightURI(AItems[I]);
      ADestURIs[N] := SyncItemLeftURI(AItems[I]);
    end;
  end;
end;

function CollectDirSyncDeletePaths(const AItems: TArray<TSyncItem>;
  ATwoWay, AMirror: Boolean): TArray<string>;
var
  I, N: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(AItems) do
    if (EffectiveSyncAction(AItems[I], ATwoWay, AMirror) = saDelete) and
       SyncActionAllowed(AItems[I], saDelete, ATwoWay) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      // In a one-sided item the file that exists is the source.
      Result[N] := AItems[I].SrcURI;
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
  I, N: Integer;
  Item: TJSONValue;
  Obj: TJSONObject;
  Ent: TSyncSnapshotEntry;
  LeftTicks, RightTicks: Int64;
begin
  if Arr = nil then
    Exit(nil);
  // One allocation for the snapshot. Growing the list per file stalls
  // reopening a large pair of folders.
  SetLength(Result, Arr.Count);
  N := 0;
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
    Result[N] := Ent;
    Inc(N);
  end;
  SetLength(Result, N);
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
// this (ALeftRoot, ARightRoot) pair into AKept - i.e. every other root-pair's
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

function FileTicksIn(AMap: TDictionary<string, string>;
  const ARel: string): Int64;
var
  Path: string;
begin
  if AMap.TryGetValue(ARel, Path) then
    Result := FileUtcTicks(Path)
  else
    Result := 0;
end;

// A conflict stays as it was, and a deletion not carried out yet keeps the
// entry that tells it apart from a new file.
function KeepsPreviousEntry(const APrev: TSyncSnapshotEntry;
  AIsConflict, AOneSided: Boolean): Boolean;
begin
  Result := AIsConflict or
    (AOneSided and (APrev.LeftUtcTicks <> 0) and (APrev.RightUtcTicks <> 0));
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
      if OldMap.TryGetValue(Rel, Prev) and
         KeepsPreviousEntry(Prev, RelInList(Rel, AConflictRels),
           LeftMap.ContainsKey(Rel) <> RightMap.ContainsKey(Rel)) then
        Ent := Prev
      else
      begin
        Ent.LeftUtcTicks := FileTicksIn(LeftMap, Rel);
        Ent.RightUtcTicks := FileTicksIn(RightMap, Rel);
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

procedure PruneDirSyncSnapshotFile(const AFile, ALeftRoot, ARightRoot: string);
var
  Entries: TArray<TSyncSnapshotEntry>;
  I, N: Integer;
begin
  // An absent root says nothing about the files under it.
  if not TDirectory.Exists(ALeftRoot) or not TDirectory.Exists(ARightRoot) then
    Exit;
  Entries := LoadDirSyncSnapshotFromFile(AFile, ALeftRoot, ARightRoot);
  N := 0;
  for I := 0 to High(Entries) do
    if TFile.Exists(WinApiPath(SafeCombinePath(ALeftRoot, Entries[I].RelPath))) or
       TFile.Exists(WinApiPath(SafeCombinePath(ARightRoot, Entries[I].RelPath))) then
    begin
      Entries[N] := Entries[I];
      Inc(N);
    end;
  if N = Length(Entries) then
    Exit;
  SetLength(Entries, N);
  SaveDirSyncSnapshotToFile(AFile, ALeftRoot, ARightRoot, Entries);
end;

procedure PruneDirSyncSnapshot(const ALeftRoot, ARightRoot: string);
begin
  PruneDirSyncSnapshotFile(DirSyncStateFilePath, ALeftRoot, ARightRoot);
end;

procedure CommitDirSyncSnapshot(const ALeftRoot, ARightRoot: string;
  const AConflictRels: TArray<string>);
begin
  CommitDirSyncSnapshotToFile(DirSyncStateFilePath, ALeftRoot, ARightRoot,
    AConflictRels);
end;

end.
