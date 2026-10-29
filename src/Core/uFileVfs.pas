unit uFileVfs;

{ Local file:// VFS provider. All I/O runs off the UI thread and results are
  marshaled via TThread.Queue. Delete / Copy / Move with progress. }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TFileVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
  public
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.Generics.Defaults, uPlatformInfo, uPlatformFileOps, uFileRecycleBin, uVfsUtils, uPlatformUpdate, uPlatformPaths;

type
  TVfsEntryComparer = class(TComparer<TVfsEntry>)
  public
    function Compare(const Left, Right: TVfsEntry): Integer; override;
  end;

var
  GLastProgressQueueTick: UInt64 = 0;

function TVfsEntryComparer.Compare(const Left, Right: TVfsEntry): Integer;
begin
  if Left.IsDirectory <> Right.IsDirectory then
  begin
    if Left.IsDirectory then
      Exit(-1)
    else
      Exit(1);
  end;
  Result := CompareNaturalText(Left.Name, Right.Name);
end;

procedure QueueBool(AOnDone: TVfsBoolCallback; ASuccess: Boolean; const AError: TVfsError);
var
  Ok: Boolean;
  Err: TVfsError;
  Done: TVfsBoolCallback;
begin
  Ok := ASuccess;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Done) then
        Done(Ok, Err);
    end);
end;

procedure QueueText(AOnDone: TVfsTextCallback; const AText: string;
  AEncoding: TTextFileEncoding; const AError: TVfsError);
var
  Text: string;
  Enc: TTextFileEncoding;
  Err: TVfsError;
  Done: TVfsTextCallback;
begin
  Text := AText;
  Enc := AEncoding;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Done) then
        Done(Text, Enc, Err);
    end);
end;

procedure QueueBytes(AOnDone: TVfsBytesCallback; const ABytes: TBytes;
  const AError: TVfsError);
var
  Bytes: TBytes;
  Err: TVfsError;
  Done: TVfsBytesCallback;
begin
  Bytes := ABytes;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Done) then
        Done(Bytes, Err);
    end);
end;

procedure QueueProgress(AOnProgress: TVfsProgressCallback; ADone, ATotal: Int64;
  const AName: string; AItemDone: Int64 = 0; AItemTotal: Int64 = 0;
  const AItemSrcPath: string = ''; const AItemDstPath: string = '');
const
  cMinQueueMs = 50; // ~20 Hz - avoid flooding the UI with TThread.Queue
var
  D, T, ID, IT: Int64;
  N, ISrc, IDst: string;
  Prog: TVfsProgressCallback;
  NowTick: UInt64;
  Force: Boolean;
begin
  if not Assigned(AOnProgress) then
    Exit;
  D := ADone;
  T := ATotal;
  N := AName;
  ID := AItemDone;
  IT := AItemTotal;
  ISrc := AItemSrcPath;
  IDst := AItemDstPath;
  Prog := AOnProgress;
  // Force through on either the whole-item completion (D>=T) or a single
  // file's own completion (ID>=IT) - without the latter, a fast per-file
  // finish inside a tree copy routinely lands inside the 50ms window and
  // gets dropped, so the per-file bar visibly skips past 100% straight into
  // the next file's low percentage and never appears to finish.
  Force := ((T > 0) and (D >= T)) or ((IT > 0) and (ID >= IT));
  NowTick := PlatformTickCount64;
  if (not Force) and (NowTick - GLastProgressQueueTick < cMinQueueMs) then
    Exit;
  GLastProgressQueueTick := NowTick;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(Prog) then
        Prog(D, T, N, ID, IT, ISrc, IDst);
    end);
end;

procedure CleanupFailedCopy(const ADst: string);
begin
  try
    if LocalPathIsDirectory(ADst) then
      TDirectory.Delete(WinApiPath(ADst), True)
    else if LocalPathIsFile(ADst) or TFile.Exists(WinApiPath(ADst)) then
      TFile.Delete(WinApiPath(ADst));
  except
  end;
end;

procedure EnsureDestParentDir(const ADstPath: string);
var
  Parent: string;
begin
  Parent := ExtractFilePath(ADstPath);
  if (Parent <> '') and not TDirectory.Exists(WinApiPath(Parent)) then
    ForceDirectories(WinApiPath(Parent));
end;

// True when ADst is ASrc itself or a path nested inside it - copying a
// directory into its own subtree would make CopyTree's FindFirst walk over
// ASrc pick up the freshly-created destination and recurse into it forever.
function IsSameOrDescendantPath(const ASrc, ADst: string): Boolean;
var
  NormSrc, NormDst: string;
begin
  NormSrc := IncludeTrailingPathDelimiter(TPath.GetFullPath(ASrc));
  NormDst := IncludeTrailingPathDelimiter(TPath.GetFullPath(ADst));
  Result := SameText(Copy(NormDst, 1, Length(NormSrc)), NormSrc);
end;

procedure VerifyCopiedFile(const ASrc, ADst: string; AExpectedSize: Int64;
  AStrict: Boolean; var AError: TVfsError);
var
  Actual: Int64;
begin
  if AError.Code <> vecOk then
    Exit;
  if not LocalPathIsFile(ADst) then
  begin
    AError := TVfsError.Make(vecIOError,
      'Copy verification failed: destination file missing', PathToFileUri(ADst));
    Exit;
  end;
  // Non-strict: this file may have been left untouched by Skip-mode conflict
  // handling rather than freshly written by us, so a size difference from
  // ASrc is the expected, intentional outcome - only prove it still exists.
  if not AStrict then
    Exit;
  try
    Actual := TFile.GetSize(WinApiPath(ADst));
  except
    on E: Exception do
    begin
      AError := TVfsError.Make(vecIOError,
        'Copy verification failed: ' + E.Message, PathToFileUri(ADst));
      Exit;
    end;
  end;
  if Actual <> AExpectedSize then
    AError := TVfsError.Make(vecIOError,
      Format('Copy verification failed: size mismatch (%d <> %d)',
        [Actual, AExpectedSize]), PathToFileUri(ADst));
end;

// Presence-only walk. Every file this copy wrote was already
// size-verified the moment it was written (CopyFileWithProgress), and files
// left untouched by Skip-mode conflict handling are supposed to differ, so
// re-comparing sizes here adds nothing and actively misfires: a live source
// (a log the owning application keeps appending to) is legitimately larger
// now than the snapshot that was copied, and a "size mismatch" there would
// delete the whole freshly copied destination tree.
procedure VerifyCopiedTree(const ASrc, ADst: string;
  var AError: TVfsError);
var
  SR: TSearchRec;
  Code: Integer;
  ChildSrc, ChildDst: string;
begin
  if AError.Code <> vecOk then
    Exit;
  if not LocalPathIsDirectory(ADst) then
  begin
    AError := TVfsError.Make(vecIOError,
      'Copy verification failed: destination folder missing', PathToFileUri(ADst));
    Exit;
  end;
  Code := FindFirst(WinApiPath(SafeCombinePath(ASrc, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        ChildSrc := SafeCombinePath(ASrc, SR.Name);
        ChildDst := SafeCombinePath(ADst, SR.Name);
        if (SR.Attr and faDirectory) <> 0 then
          VerifyCopiedTree(ChildSrc, ChildDst, AError)
        else
          VerifyCopiedFile(ChildSrc, ChildDst, SR.Size, False, AError);
        if AError.Code <> vecOk then
          Exit;
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure VerifyMoveResult(const ASrc, ADst: string; AWasDirectory: Boolean;
  var AError: TVfsError);
var
  SourceLeft: Boolean;
begin
  if AError.Code <> vecOk then
    Exit;
  if AWasDirectory then
  begin
    if not LocalPathIsDirectory(ADst) then
    begin
      AError := TVfsError.Make(vecIOError,
        'Move verification failed: destination folder missing', PathToFileUri(ADst));
      Exit;
    end;
  end
  else if not LocalPathIsFile(ADst) then
  begin
    AError := TVfsError.Make(vecIOError,
      'Move verification failed: destination file missing', PathToFileUri(ADst));
    Exit;
  end;
  // The usual checks cut a space off the end of a name, and would find the
  // moved item under its new name when only that space was removed.
  if PathHasBlankEndedName(ASrc) then
    SourceLeft := PlatformIsDirectory(WinApiPath(ASrc)) or PlatformIsFile(WinApiPath(ASrc))
  else
    SourceLeft := LocalPathIsFile(ASrc) or LocalPathIsDirectory(ASrc) or
      TFile.Exists(WinApiPath(ASrc)) or TDirectory.Exists(WinApiPath(ASrc));
  if SourceLeft then
    AError := TVfsError.Make(vecIOError,
      'Move verification failed: source still exists', PathToFileUri(ASrc));
end;

procedure PreserveFileTimestamps(const ASrc, ADst: string);
begin
  try
    TFile.SetCreationTime(WinApiPath(ADst), TFile.GetCreationTime(WinApiPath(ASrc)));
    TFile.SetLastWriteTime(WinApiPath(ADst), TFile.GetLastWriteTime(WinApiPath(ASrc)));
    TFile.SetLastAccessTime(WinApiPath(ADst), TFile.GetLastAccessTime(WinApiPath(ASrc)));
  except
    // Best-effort; copy already succeeded.
  end;
end;

procedure PreserveFileAttributes(const ASrc, ADst: string);
begin
  PlatformCopyAttributes(ASrc, ADst);
end;

// Access denied must stay an access-denied error: the job offers an
// administrator pass for it.
function VfsErrorFromException(E: Exception; const AURI: string): TVfsError;
begin
  if PlatformIsAccessDenied(E) then
    Result := TVfsError.Make(vecAccessDenied, E.Message, AURI)
  else
    Result := TVfsError.Make(vecIOError, E.Message, AURI);
end;

procedure CopyFileWithProgress(const ASrc, ADst: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var AError: TVfsError;
  AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False;
  ABaseDoneBytes: Int64 = 0; AItemTotalBytes: Int64 = 0; AAppend: Boolean = False);
var
  Src, Dst: TFileStream;
  Buf: TBytes;
  N, Want: Integer;
  Copied, Total, ReportTotal, NowSize: Int64;
  DstCreated, Raised, Staged: Boolean;
  WritePath, MoveMsg: string;
begin
  Src := nil;
  Dst := nil;
  Copied := 0;
  Total := 0;
  DstCreated := False;
  Raised := False;
  Staged := False;
  WritePath := ADst;
  try
    try
      // fmShareDenyNone, not fmShareDenyWrite: a file another process holds
      // open for writing - an application log, a live SQLite/LevelDB store -
      // is still perfectly readable, and denying writers turned every such
      // file into an EFOpenError that escaped this routine, aborted the whole
      // recursive copy at that point and left the rest of the tree uncopied.
      Src := TFileStream.Create(WinApiPath(ASrc), fmOpenRead or fmShareDenyNone);
      if AAppend and TFile.Exists(WinApiPath(ADst)) then
      begin
        // The existing file is the user's data: it is extended in place and
        // never removed if the copy fails.
        Dst := TFileStream.Create(WinApiPath(ADst), fmOpenWrite or fmShareDenyWrite);
        Dst.Seek(0, soEnd);
      end
      else
      begin
        // A directory occupying the file's name is not a skippable file
        // conflict: treating it as "already exists" made verification look
        // for a file, fail, and delete the whole destination folder.
        if TDirectory.Exists(WinApiPath(ADst)) and not AOverwrite then
        begin
          AError := TVfsError.Make(vecIOError,
            'Cannot replace a directory with a file', PathToFileUri(ADst));
          Exit;
        end;
        if TFile.Exists(WinApiPath(ADst)) and not AOverwrite then
        begin
          AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists', PathToFileUri(ADst));
          Exit;
        end;
        // Overwrite writes beside the destination and swaps only after the
        // bytes are complete, so a failed or cancelled copy leaves the
        // previous file or directory in place.
        if TFile.Exists(WinApiPath(ADst)) or TDirectory.Exists(WinApiPath(ADst)) then
        begin
          WritePath := UnusedSiblingPath(ADst, '.mtnpart');
          if WritePath = '' then
          begin
            AError := TVfsError.Make(vecIOError,
              'Cannot make room to replace the destination', PathToFileUri(ADst));
            Exit;
          end;
          Staged := True;
        end;
        Dst := TFileStream.Create(WinApiPath(WritePath), fmCreate);
        DstCreated := True;
      end;
      Total := Src.Size;
      ReportTotal := AItemTotalBytes;
      if ReportTotal <= 0 then
        ReportTotal := Total;
      SetLength(Buf, 64 * 1024);
      while Copied < Total do
      begin
        if JobCancelRequested(ACancel) then
        begin
          AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
          Break;
        end;
        // Never read past the size sampled when the file was opened: a source
        // an application is still appending to would otherwise keep feeding
        // bytes, and the copy would end up larger than the size everything
        // downstream (progress totals, verification) was computed from.
        Want := Length(Buf);
        if Total - Copied < Want then
          Want := Integer(Total - Copied);
        N := Src.Read(Buf[0], Want);
        // A failed read (an offline cloud placeholder, a drive that went away)
        // reports the system's own reason, not just a short copy.
        if N < 0 then
          RaiseLastOSError;
        if N = 0 then
          Break;
        Dst.WriteBuffer(Buf[0], N);
        Inc(Copied, N);
        // ADone/ATotal stay cumulative across the whole item (base + this
        // file's progress so far), not just this one file's own share - inside
        // a recursive folder copy, ASrc is one of many child files, and the
        // "Total" bar/counter needs the running tree total to move smoothly
        // instead of resetting to a near-zero per-file value on every new
        // child (see CopyTree callers below). AItemDone/AItemTotal/paths carry
        // this file's own progress separately, for the per-file bar.
        QueueProgress(AOnProgress, ABaseDoneBytes + Copied, ReportTotal, SafeFileName(ASrc),
          Copied, Total, ASrc, ADst);
      end;
    except
      // A single unreadable or unwritable file must stay a per-file error
      // carrying its own path, not an exception unwinding out of the caller's
      // whole directory walk and getting reported against the top-level job.
      on E: Exception do
      begin
        Raised := True;
        AError := VfsErrorFromException(E, PathToFileUri(ASrc));
      end;
    end;
  finally
    Src.Free;
    Dst.Free;
  end;
  if Raised then
  begin
    if DstCreated then
      CleanupFailedCopy(WritePath);
    Exit;
  end;
  if AError.Code = vecCancelled then
  begin
    if DstCreated then
      CleanupFailedCopy(WritePath);
    Exit;
  end;
  if AError.Code <> vecOk then
    Exit;
  if Copied <> Total then
  begin
    // Short read: either the source really was truncated under us - in which
    // case Copied is the whole file as it now stands and the copy is complete
    // - or something failed mid-stream and the destination is a fragment.
    NowSize := -1;
    try
      NowSize := TFile.GetSize(WinApiPath(ASrc));
    except
      // Leave NowSize at -1 and report the short copy below.
    end;
    if NowSize = Copied then
      Total := Copied
    else
    begin
      AError := TVfsError.Make(vecIOError,
        Format('Copy incomplete (%d of %d bytes)', [Copied, Total]), PathToFileUri(ASrc));
      if DstCreated then
        CleanupFailedCopy(WritePath);
      Exit;
    end;
  end;
  // An appended file keeps its own timestamps and is larger than the source
  // by design.
  if not DstCreated then
    Exit;
  VerifyCopiedFile(ASrc, WritePath, Total, True, AError);
  if AError.Code <> vecOk then
  begin
    CleanupFailedCopy(WritePath);
    Exit;
  end;
  if Staged then
  begin
    if not ReplacePathWith(WritePath, ADst, MoveMsg) then
    begin
      AError := TVfsError.Make(vecIOError, MoveMsg, PathToFileUri(ADst));
      CleanupFailedCopy(WritePath);
      Exit;
    end;
  end;
  if APreserveTimestamps then
    PreserveFileTimestamps(ASrc, ADst);
  // Attributes (R/H/S/A) are carried over unconditionally, like Explorer/TC
  // do - unrelated to the "preserve timestamps" job option.
  PreserveFileAttributes(ASrc, ADst);
end;

// Asks the job's resolver what to do with a file that already exists at the
// destination. Without a resolver nothing changes and the caller's overwrite
// flag decides. Skip is reported as vecAlreadyExists, which CopyTree counts as
// a skipped item and moves past.
procedure AskFileConflict(const ASrc: string; var ADst: string;
  ACancel: IJobCancelToken; var AOverwrite, AAppend: Boolean;
  var AError: TVfsError);
var
  Resolver: TVfsConflictResolver;
  NewDst: string;
begin
  Resolver := JobConflictResolver(ACancel);
  if not Assigned(Resolver) then
    Exit;
  while TFile.Exists(WinApiPath(ADst)) or TDirectory.Exists(WinApiPath(ADst)) do
  begin
    if JobCancelRequested(ACancel) then
    begin
      AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
      Exit;
    end;
    NewDst := '';
    case Resolver(ASrc, ADst, NewDst) of
      vcaOverwrite:
        begin
          AOverwrite := True;
          Exit;
        end;
      vcaAppend:
        begin
          AAppend := TFile.Exists(WinApiPath(ADst));
          AOverwrite := not AAppend;
          Exit;
        end;
      vcaSkip:
        begin
          AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists',
            PathToFileUri(ADst));
          Exit;
        end;
      vcaRename:
        if NewDst <> '' then
          ADst := NewDst
        else
        begin
          AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
          Exit;
        end;
    else
      AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
      Exit;
    end;
  end;
end;

procedure CopyTree(const ASrc, ADst: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneBytes, ATotalBytes: Int64;
  var AError: TVfsError; var AAnySkipped: Boolean; AOverwrite: Boolean = False;
  APreserveTimestamps: Boolean = False);
var
  SR: TSearchRec;
  Code: Integer;
  ChildSrc, ChildDst: string;
  ChildErr: TVfsError;
  ChildOverwrite, ChildAppend, CreatedHere: Boolean;
  Stage, MoveMsg: string;
begin
  CreatedHere := False;
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
    Exit;
  end;
  if TFile.Exists(WinApiPath(ADst)) then
  begin
    // A file where a directory must go is not a skippable name clash: a skip
    // would later fail verification and delete the destination folder.
    if not AOverwrite then
    begin
      AError := TVfsError.Make(vecIOError,
        'Cannot replace a file with a directory', PathToFileUri(ADst));
      Exit;
    end;
    // Build the tree beside the file, then swap. Deleting the file first
    // would lose it when the copy fails.
    Stage := UnusedSiblingPath(ADst, '.mtnpart');
    if Stage = '' then
    begin
      AError := TVfsError.Make(vecIOError,
        'Cannot make room to replace the destination', PathToFileUri(ADst));
      Exit;
    end;
    CopyTree(ASrc, Stage, ACancel, AOnProgress, ADoneBytes, ATotalBytes, AError,
      AAnySkipped, True, APreserveTimestamps);
    if AError.Code = vecOk then
    begin
      if not ReplacePathWith(Stage, ADst, MoveMsg) then
      begin
        AError := TVfsError.Make(vecIOError, MoveMsg, PathToFileUri(ADst));
        CleanupFailedCopy(Stage);
      end;
    end
    else
      CleanupFailedCopy(Stage);
    Exit;
  end
  else if not TDirectory.Exists(WinApiPath(ADst)) then
  begin
    TDirectory.CreateDirectory(WinApiPath(ADst));
    CreatedHere := True;
  end;
  Code := FindFirst(WinApiPath(SafeCombinePath(ASrc, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
        Exit;
      end;
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        ChildSrc := SafeCombinePath(ASrc, SR.Name);
        ChildDst := SafeCombinePath(ADst, SR.Name);
        ChildErr := TVfsError.Ok;
        if (SR.Attr and faDirectory) <> 0 then
          CopyTree(ChildSrc, ChildDst, ACancel, AOnProgress, ADoneBytes, ATotalBytes,
            ChildErr, AAnySkipped, AOverwrite, APreserveTimestamps)
        else
        begin
          ChildOverwrite := AOverwrite;
          ChildAppend := False;
          if not AOverwrite then
            AskFileConflict(ChildSrc, ChildDst, ACancel, ChildOverwrite,
              ChildAppend, ChildErr);
          if ChildErr.Code = vecOk then
            CopyFileWithProgress(ChildSrc, ChildDst, ACancel, AOnProgress, ChildErr,
              ChildOverwrite, APreserveTimestamps, ADoneBytes, ATotalBytes,
              ChildAppend);
          if ChildErr.Code = vecOk then
          begin
            if SR.Size > 0 then
              Inc(ADoneBytes, SR.Size);
            QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, SR.Name,
              SR.Size, SR.Size, ChildSrc, ChildDst);
          end;
        end;
        // Skip mode (AOverwrite=False): one item already existing at the
        // destination is the expected, common case for a re-run/merge copy -
        // it must not abort the rest of the tree, or nothing past the first
        // pre-existing name would get copied. Real failures and cancellation
        // still stop the walk.
        if (ChildErr.Code = vecAlreadyExists) and not AOverwrite then
        begin
          AAnySkipped := True;
          // A skipped item still needs to nudge progress along - without
          // this, a run of skipped files (Skip-overwrite mode, or Ask+Skip
          // remembered) never advances the per-file bar, the file counter,
          // or the current-name display, and the job looks stalled even
          // though it's actively walking through hundreds of already-
          // existing files. Item bytes stay 0/0 (nothing was transferred),
          // but the path still identifies it as a processed item.
          QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, SR.Name, 0, 0,
            ChildSrc, ChildDst);
        end
        else if ChildErr.Code <> vecOk then
        begin
          AError := ChildErr;
          Exit;
        end;
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
  if AError.Code = vecOk then
  begin
    VerifyCopiedTree(ASrc, ADst, AError);
    // A folder that already existed is a merge target: a failed check must
    // not delete the files that were there before this copy.
    if (AError.Code <> vecOk) and CreatedHere then
      CleanupFailedCopy(ADst)
    else
    begin
      if APreserveTimestamps then
        PreserveFileTimestamps(ASrc, ADst);
      PreserveFileAttributes(ASrc, ADst);
    end;
  end;
end;

// The walks below run before a copy / move / delete starts. They report the
// folder being read (ATotal = -1 marks a scan report) and stop on cancel, so
// a huge tree shows what is happening and can be abandoned.
function EstimateTreeBytes(const APath: string; ACancel: IJobCancelToken = nil;
  AOnProgress: TVfsProgressCallback = nil): Int64;
var
  SR: TSearchRec;
  Code: Integer;
begin
  Result := 0;
  if JobCancelRequested(ACancel) then
    Exit;
  if TFile.Exists(WinApiPath(APath)) and not TDirectory.Exists(WinApiPath(APath)) then
  begin
    Result := TFile.GetSize(WinApiPath(APath));
    Exit;
  end;
  if not TDirectory.Exists(WinApiPath(APath)) then
    Exit;
  QueueProgress(AOnProgress, 0, -1, APath);
  Code := FindFirst(WinApiPath(SafeCombinePath(APath, '*')), faAnyFile, SR);
  try
    while (Code = 0) and not JobCancelRequested(ACancel) do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Inc(Result, EstimateTreeBytes(SafeCombinePath(APath, SR.Name), ACancel,
            AOnProgress))
        else
          Inc(Result, SR.Size);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

// Counts every file plus every directory (including APath itself) that
// DeleteTree below will remove - the denominator for its progress reporting.
// A second walk of the same tree before deletion starts, mirroring
// EstimateTreeBytes above for copy.
function EstimateTreeItemCount(const APath: string; ACancel: IJobCancelToken = nil;
  AOnProgress: TVfsProgressCallback = nil): Int64;
var
  SR: TSearchRec;
  Code: Integer;
begin
  if JobCancelRequested(ACancel) then
    Exit(0);
  if TFile.Exists(WinApiPath(APath)) and not TDirectory.Exists(WinApiPath(APath)) then
    Exit(1);
  if not TDirectory.Exists(WinApiPath(APath)) then
    Exit(0);
  Result := 1; // APath itself
  QueueProgress(AOnProgress, 0, -1, APath);
  Code := FindFirst(WinApiPath(SafeCombinePath(APath, '*')), faAnyFile, SR);
  try
    while (Code = 0) and not JobCancelRequested(ACancel) do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Inc(Result, EstimateTreeItemCount(SafeCombinePath(APath, SR.Name), ACancel,
            AOnProgress))
        else
          Inc(Result);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure DeleteTree(const APath: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneItems: Int64; ATotalItems: Int64;
  var AError: TVfsError);
var
  Path: string;
  SR: TSearchRec;
  Code: Integer;
  Child: string;
  FirstErr, ChildErr: TVfsError;
  HasError: Boolean;
begin
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(APath));
    Exit;
  end;
  Path := ExcludeTrailingPathDelimiter(APath);
  if Path = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid path', PathToFileUri(APath));
    Exit;
  end;
  FirstErr := TVfsError.Ok;
  HasError := False;
  try
    if LocalPathIsDirectory(Path) and not PlatformIsLinkNode(Path) then
    begin
      Code := FindFirst(WinApiPath(SafeCombinePath(Path, '*')), faAnyFile, SR);
      try
        while Code = 0 do
        begin
          if JobCancelRequested(ACancel) then
          begin
            FirstErr := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(Path));
            HasError := True;
            Break;
          end;
          if (SR.Name <> '.') and (SR.Name <> '..') then
          begin
            Child := SafeCombinePath(Path, SR.Name);
            ChildErr := TVfsError.Ok;
            DeleteTree(Child, ACancel, AOnProgress, ADoneItems, ATotalItems, ChildErr);
            if ChildErr.Code <> vecOk then
            begin
              if ChildErr.Code = vecCancelled then
              begin
                FirstErr := ChildErr;
                HasError := True;
                Break;
              end;
              if not HasError then
              begin
                FirstErr := ChildErr;
                HasError := True;
              end;
            end;
          end;
          Code := FindNext(SR);
        end;
      finally
        System.SysUtils.FindClose(SR);
      end;
      if not HasError then
      begin
        if not PlatformDeleteNode(Path, True, FirstErr) then
          HasError := True
        else
        begin
          Inc(ADoneItems);
          QueueProgress(AOnProgress, ADoneItems, ATotalItems,
            SafeFileName(Path), 0, 0, Path, '');
        end;
      end;
    end
    else if LocalPathIsFile(Path) or PlatformIsLinkNode(Path) then
    begin
      if not PlatformDeleteNode(Path, False, FirstErr) then
        HasError := True
      else
      begin
        Inc(ADoneItems);
        QueueProgress(AOnProgress, ADoneItems, ATotalItems,
          SafeFileName(Path), 0, 0, Path, '');
      end;
    end
    else
    begin
      FirstErr := TVfsError.Make(vecNotFound, 'Path not found', PathToFileUri(Path));
      HasError := True;
    end;
  except
    on E: Exception do
    begin
      if Pos('denied', LowerCase(E.Message)) > 0 then
        FirstErr := TVfsError.Make(vecAccessDenied, E.Message, PathToFileUri(Path))
      else
        FirstErr := TVfsError.Make(vecIOError, E.Message, PathToFileUri(Path));
      HasError := True;
    end;
  end;

  if HasError then
    AError := FirstErr
  else
    AError := TVfsError.Ok;
end;

procedure TFileVirtualFileSystem.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsListCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      List: TList<TVfsEntry>;
      SR: TSearchRec;
      Entry: TVfsEntry;
      Code: Integer;
      DoneItems: TArray<TVfsEntry>;
      DoneErr: TVfsError;
//      FullPath: string;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := ResolveLocalDirPath(FileUriToPath(URI));
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else if not LocalPathIsDirectory(Path) then
          begin
            if LocalPathIsFile(Path) then
              Err := TVfsError.Make(vecNotSupported, 'Not a directory', URI)
            else
              Err := TVfsError.Make(vecNotFound, 'Path not found', URI);
          end
          else
          begin
            List := TList<TVfsEntry>.Create;
            try
              Code := FindFirst(WinApiPath(SafeCombinePath(Path, '*')), faAnyFile, SR);
              if PlatformSearchDenied(Code) then
                Err := TVfsError.Make(vecAccessDenied, 'Access denied', URI)
              else if Code = 0 then
              try
                while Code = 0 do
                begin
                  if JobCancelRequested(Cancel) then
                  begin
                    Err := TVfsError.Make(vecCancelled, 'Cancelled', URI);
                    Break;
                  end;
                  if (SR.Name <> '.') and (SR.Name <> '..') then
                  begin
                    Entry.Name := SR.Name;
                    Entry.Extension := LowerCase(SafeExtension(SR.Name));
                    Entry.IsDirectory := (SR.Attr and faDirectory) <> 0;
                    PlatformFillEntry(SR, Entry);
                    Entry.TargetURI := '';
                    if Entry.IsDirectory then
                    begin
                      Entry.Size := -1;
                      Entry.Extension := '';
                    end
                    else
                      Entry.Size := SR.Size;
                    List.Add(Entry);
                  end;
                  Code := FindNext(SR);
                end;
              finally
                System.SysUtils.FindClose(SR);
              end;

              if Err.Code = vecOk then
              begin
                List.Sort(TVfsEntryComparer.Create);
                Items := List.ToArray;
              end
              else
                SetLength(Items, 0);
            finally
              List.Free;
            end;
          end;
        end;
      except
        on E: Exception do
        begin
          if Pos('denied', LowerCase(E.Message)) > 0 then
            Err := TVfsError.Make(vecAccessDenied, E.Message, URI)
          else
            Err := TVfsError.Make(vecIOError, E.Message, URI);
          SetLength(Items, 0);
        end;
      end;

      DoneItems := Items;
      DoneErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(DoneItems, DoneErr);
        end);
    end).Start;
end;

procedure TFileVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  Mode: TVfsDeleteMode;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  Mode := AMode;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err: TVfsError;
      I: Integer;
      DoneItems, TotalItems: Int64;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else if Mode = vdmRecycleBin then
            DeleteToRecycleBin(Path, Err, OnProgress, Cancel)
          else
          begin
            DoneItems := 0;
            TotalItems := EstimateTreeItemCount(Path, Cancel, OnProgress);
            if TotalItems <= 0 then
              TotalItems := 1;
            DeleteTree(Path, Cancel, OnProgress, DoneItems, TotalItems, Err);
            if Err.Code = vecOk then
            begin
              I := 0;
              while (I < 5) and (LocalPathIsFile(Path) or LocalPathIsDirectory(Path)) do
              begin
                Sleep(20 * (I + 1));
                Inc(I);
              end;
              if LocalPathIsFile(Path) or LocalPathIsDirectory(Path) then
                Err := TVfsError.Make(vecIOError,
                  'Delete verification failed: path still exists', URI);
            end;
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path, Parent, Leaf: string;
      Err: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else if LocalPathIsDirectory(Path) or LocalPathIsFile(Path) then
            Err := TVfsError.Make(vecAlreadyExists, 'Already exists', URI)
          else
          begin
            // Create under the resolved parent when the panel URI is a junction.
            Parent := SafeDirectoryName(Path);
            Leaf := SafeFileName(Path);
            if (Parent <> '') and (Leaf <> '') then
            begin
              Parent := ResolveLocalDirPath(Parent);
              if Parent <> '' then
                Path := SafeCombinePath(Parent, Leaf);
            end;
            if LocalPathIsDirectory(Path) or LocalPathIsFile(Path) then
              Err := TVfsError.Make(vecAlreadyExists, 'Already exists', URI)
            else
              TDirectory.CreateDirectory(WinApiPath(Path));
          end;
        end;
      except
        on E: Exception do
          Err := VfsErrorFromException(E, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Overwrite, Preserve: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  Overwrite := AOverwrite;
  Preserve := APreserveTimestamps;
  TThread.CreateAnonymousThread(
    procedure
    var
      Src, Dst: string;
      Err: TVfsError;
      DoneBytes, TotalBytes: Int64;
      AnySkipped, DestWasDir: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := FromURI;
      DoneBytes := 0;
      TotalBytes := 0;
      AnySkipped := False; // Copy never deletes Src, so this result is unused here.
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', FromURI)
        else
        begin
          Src := FileUriToPath(FromURI);
          Dst := FileUriToPath(ToURI);
          if (Src = '') or (Dst = '') then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', FromURI)
          else if not (TFile.Exists(WinApiPath(Src)) or TDirectory.Exists(WinApiPath(Src))) then
            Err := TVfsError.Make(vecNotFound, 'Source not found', FromURI)
          else if TDirectory.Exists(WinApiPath(Src)) and IsSameOrDescendantPath(Src, Dst) then
            Err := TVfsError.Make(vecInvalidURI,
              'Cannot copy a folder into itself or its own subfolder', ToURI)
          else
          begin
            try
              EnsureDestParentDir(Dst);
            except
              on E: Exception do
              begin
                Err := VfsErrorFromException(E, ToURI);
              end;
            end;
            if Err.Code = vecOk then
            begin
              TotalBytes := EstimateTreeBytes(Src, Cancel, OnProgress);
              if TotalBytes <= 0 then
                TotalBytes := 1;
              DestWasDir := TDirectory.Exists(WinApiPath(Dst));
              if TDirectory.Exists(WinApiPath(Src)) then
                CopyTree(Src, Dst, Cancel, OnProgress, DoneBytes, TotalBytes, Err,
                  AnySkipped, Overwrite, Preserve)
              else
              begin
                CopyFileWithProgress(Src, Dst, Cancel, OnProgress, Err, Overwrite, Preserve);
                if Err.Code = vecOk then
                  QueueProgress(OnProgress, TotalBytes, TotalBytes, SafeFileName(Src),
                    TotalBytes, TotalBytes, Src, Dst);
              end;
              if Err.Code = vecOk then
              begin
                if TDirectory.Exists(WinApiPath(Src)) then
                  VerifyCopiedTree(Src, Dst, Err)
                else
                  // Non-strict for the same reason as VerifyCopiedTree: the
                  // strict size check already ran inside the copy itself.
                  VerifyCopiedFile(Src, Dst, TFile.GetSize(WinApiPath(Src)), False, Err);
                // A merge into a folder that was already there must not be
                // deleted when the check fails.
                if (Err.Code <> vecOk) and not DestWasDir then
                  CleanupFailedCopy(Dst);
              end;
            end;
          end;
        end;
      except
        on E: Exception do
          Err := VfsErrorFromException(E, FromURI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Overwrite, Preserve: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  Overwrite := AOverwrite;
  Preserve := APreserveTimestamps;
  TThread.CreateAnonymousThread(
    procedure
    var
      Src, Dst, MoveMsg: string;
      Err: TVfsError;
      DoneBytes, TotalBytes: Int64;
      SameVolume, WasDirectory, AnySkipped, MergeIntoDir, DestWasDir: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := FromURI;
      AnySkipped := False;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', FromURI)
        else
        begin
          Src := FileUriToPath(FromURI);
          Dst := FileUriToPath(ToURI);
          if (Src = '') or (Dst = '') then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', FromURI)
          else if not (TFile.Exists(WinApiPath(Src)) or TDirectory.Exists(WinApiPath(Src))) then
            Err := TVfsError.Make(vecNotFound, 'Source not found', FromURI)
          else if TFile.Exists(WinApiPath(Dst)) and not Overwrite then
            // An existing file is replaced only when overwrite is on, and then
            // by the move or copy below - not deleted before that succeeds.
            Err := TVfsError.Make(vecAlreadyExists, 'Destination already exists', ToURI)
          else if TDirectory.Exists(WinApiPath(Dst)) and
            not TDirectory.Exists(WinApiPath(Src)) and not Overwrite then
            Err := TVfsError.Make(vecAlreadyExists, 'Destination already exists', ToURI);
          // Src and Dst both directories, Dst already exists: not treated as a
          // conflict here. A same-volume rename onto an existing folder fails
          // (native Windows limitation), so an empty Dst is removed and the
          // folder renamed, and a non-empty Dst takes the copy-and-delete
          // path below: CopyTree merges into the existing folder per file,
          // honoring AOverwrite/skip like Copy does.
          MergeIntoDir := (Err.Code = vecOk) and TDirectory.Exists(WinApiPath(Dst)) and
            TDirectory.Exists(WinApiPath(Src));
          if MergeIntoDir and TDirectory.IsEmpty(WinApiPath(Dst)) then
          begin
            try
              TDirectory.Delete(WinApiPath(Dst), False);
              MergeIntoDir := False;
            except
              on E: Exception do
                Err := VfsErrorFromException(E, ToURI);
            end;
          end;
          if Err.Code = vecOk then
          begin
            try
              EnsureDestParentDir(Dst);
            except
              on E: Exception do
                Err := VfsErrorFromException(E, ToURI);
            end;
          end;
          if Err.Code = vecOk then
          begin
            WasDirectory := TDirectory.Exists(WinApiPath(Src));
            // A file and a directory of the same name cannot be renamed over
            // each other; that goes through the copy below, which swaps only
            // after the new tree exists.
            SameVolume := (not MergeIntoDir) and (Length(Src) >= 2) and
              (Length(Dst) >= 2) and
              (UpCase(Src[1]) = UpCase(Dst[1])) and (Src[2] = ':') and (Dst[2] = ':') and
              not (WasDirectory and TFile.Exists(WinApiPath(Dst))) and
              not ((not WasDirectory) and TDirectory.Exists(WinApiPath(Dst)));
            if SameVolume then
            begin
              QueueProgress(OnProgress, 0, 1, SafeFileName(Src), 0, 1, Src, Dst);
              try
                if PathHasBlankEndedName(Src) or PathHasBlankEndedName(Dst) or
                  ((not WasDirectory) and TFile.Exists(WinApiPath(Dst))) then
                begin
                  // TDirectory.Move and TFile.Move cut the space off such a name.
                  // Replace keeps the previous file when the rename itself fails.
                  if not PlatformMoveFile(WinApiPath(Src), WinApiPath(Dst),
                    (not WasDirectory) and TFile.Exists(WinApiPath(Dst)), MoveMsg) then
                    raise EInOutError.Create(MoveMsg);
                end
                else if WasDirectory then
                  TDirectory.Move(WinApiPath(Src), WinApiPath(Dst))
                else
                  TFile.Move(WinApiPath(Src), WinApiPath(Dst));
                QueueProgress(OnProgress, 1, 1, SafeFileName(Dst), 1, 1, Src, Dst);
              except
                on E: Exception do
                  Err := VfsErrorFromException(E, FromURI);
              end;
              if Err.Code = vecOk then
                VerifyMoveResult(Src, Dst, WasDirectory, Err);
            end
            else
            begin
              // Cross-volume, or a file/directory name clash: copy then delete source.
              TotalBytes := EstimateTreeBytes(Src, Cancel, OnProgress);
              if TotalBytes <= 0 then
                TotalBytes := 1;
              DoneBytes := 0;
              DestWasDir := TDirectory.Exists(WinApiPath(Dst));
              if WasDirectory then
                CopyTree(Src, Dst, Cancel, OnProgress, DoneBytes, TotalBytes, Err,
                  AnySkipped, Overwrite, Preserve)
              else
                CopyFileWithProgress(Src, Dst, Cancel, OnProgress, Err, Overwrite, Preserve);
              if Err.Code = vecOk then
              begin
                if WasDirectory then
                  VerifyCopiedTree(Src, Dst, Err)
                else
                  // Non-strict for the same reason as VerifyCopiedTree: the
                  // strict size check already ran inside the copy itself.
                  VerifyCopiedFile(Src, Dst, TFile.GetSize(WinApiPath(Src)), False, Err);
                if (Err.Code <> vecOk) and not DestWasDir then
                  CleanupFailedCopy(Dst)
                // Skip mode left at least one source item untouched at the
                // destination (see CopyTree) - it still exists only in Src,
                // so deleting Src here (the whole point of Move) would lose
                // it. Leave the whole source tree in place instead; the merge
                // itself already succeeded for everything that was copied.
                else if not (WasDirectory and AnySkipped) then
                try
                  if WasDirectory then
                    TDirectory.Delete(WinApiPath(Src), True)
                  else
                    TFile.Delete(WinApiPath(Src));
                except
                  on E: Exception do
                    Err := VfsErrorFromException(E, FromURI);
                end;
              end;
            end;
          end;
        end;
      except
        on E: Exception do
          Err := VfsErrorFromException(E, FromURI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsTextCallback;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  if MaxBytes <= 0 then
    MaxBytes := 2 * 1024 * 1024;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err: TVfsError;
      Text: string;
      FS: TFileStream;
      Size: Int64;
      Buf: TBytes;
      Got: Integer;
      Enc: TTextFileEncoding;
      IsBin: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Text := '';
      Enc := tfeUtf8;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else if not TFile.Exists(WinApiPath(Path)) then
            Err := TVfsError.Make(vecNotFound, 'File not found', URI)
          else
          begin
            Size := TFile.GetSize(WinApiPath(Path));
            if Size > MaxBytes then
              Err := TVfsError.Make(vecNotSupported,
                Format('File too large (max %d KB).',
                  [MaxBytes div 1024]), URI)
            else
            begin
              FS := TFileStream.Create(WinApiPath(Path), fmOpenRead or fmShareDenyNone);
              try
                SetLength(Buf, Size);
                if Size > 0 then
                begin
                  Got := FS.Read(Buf[0], Size);
                  SetLength(Buf, Got);
                end;
                if not DetectAndDecodeText(Buf, Text, Enc, IsBin) then
                begin
                  if IsBin then
                    Err := TVfsError.Make(vecNotSupported, 'Binary file', URI)
                  else
                    Err := TVfsError.Make(vecIOError, 'Cannot decode text', URI);
                  Text := '';
                end;
              finally
                FS.Free;
              end;
            end;
          end;
        end;
      except
        on E: Exception do
        begin
          if Pos('denied', LowerCase(E.Message)) > 0 then
            Err := TVfsError.Make(vecAccessDenied, E.Message, URI)
          else
            Err := TVfsError.Make(vecIOError, E.Message, URI);
          Text := '';
        end;
      end;
      QueueText(OnDone, Text, Enc, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsBytesCallback;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  if MaxBytes <= 0 then
    MaxBytes := 2 * 1024 * 1024;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err: TVfsError;
      FS: TFileStream;
      Size: Int64;
      Buf: TBytes;
      Got: Integer;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Buf, 0);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else if not TFile.Exists(WinApiPath(Path)) then
            Err := TVfsError.Make(vecNotFound, 'File not found', URI)
          else
          begin
            Size := TFile.GetSize(WinApiPath(Path));
            if Size > MaxBytes then
              Err := TVfsError.Make(vecNotSupported,
                Format('File too large (max %d KB).',
                  [MaxBytes div 1024]), URI)
            else
            begin
              FS := TFileStream.Create(WinApiPath(Path), fmOpenRead or fmShareDenyNone);
              try
                SetLength(Buf, Size);
                if Size > 0 then
                begin
                  Got := FS.Read(Buf[0], Size);
                  SetLength(Buf, Got);
                end;
              finally
                FS.Free;
              end;
            end;
          end;
        end;
      except
        on E: Exception do
        begin
          if Pos('denied', LowerCase(E.Message)) > 0 then
            Err := TVfsError.Make(vecAccessDenied, E.Message, URI)
          else
            Err := TVfsError.Make(vecIOError, E.Message, URI);
          SetLength(Buf, 0);
        end;
      end;
      QueueBytes(OnDone, Buf, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI, Text: string;
  Encoding: TTextFileEncoding;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  Text := AText;
  Encoding := AEncoding;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err: TVfsError;
      {$WARN SYMBOL_PLATFORM OFF}
      {$WARN SYMBOL_PLATFORM ON}
      Bytes: TBytes;
      FS: TFileStream;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else
          begin
            if TFile.Exists(WinApiPath(Path)) then
            begin
              if PlatformIsReadOnlyFile(Path) then
                Err := TVfsError.Make(vecAccessDenied, 'File is read-only', URI);
            end;
            if Err.Code = vecOk then
            begin
              Bytes := EncodeTextBytes(Text, Encoding);
              FS := TFileStream.Create(WinApiPath(Path), fmCreate);
              try
                if Length(Bytes) > 0 then
                  FS.WriteBuffer(Bytes[0], Length(Bytes));
              finally
                FS.Free;
              end;
            end;
          end;
        end;
      except
        on E: Exception do
        begin
          if Pos('denied', LowerCase(E.Message)) > 0 then
            Err := TVfsError.Make(vecAccessDenied, E.Message, URI)
          else
            Err := TVfsError.Make(vecIOError, E.Message, URI);
        end;
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TFileVirtualFileSystem.ExistsAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsExistsCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsExistsCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err, DoneErr: TVfsError;
      Ok, IsDir, DoneOk, DoneIsDir: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Ok := False;
      IsDir := False;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else
        begin
          Path := FileUriToPath(URI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid file URI', URI)
          else
          begin
            IsDir := LocalPathIsDirectory(Path);
            Ok := IsDir or LocalPathIsFile(Path);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      DoneOk := Ok and (Err.Code = vecOk);
      DoneIsDir := IsDir;
      DoneErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(DoneOk, DoneIsDir, DoneErr);
        end);
    end).Start;
end;

procedure TFileVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  RootURI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsFreeSpaceCallback;
begin
  RootURI := ARootURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path: string;
      Err, DoneErr: TVfsError;
      FreeB, TotalB, DoneFree, DoneTotal: Int64;
    begin
      Err := TVfsError.Ok;
      Err.URI := RootURI;
      FreeB := -1;
      TotalB := -1;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', RootURI)
        else
        begin
          Path := FileUriToPath(RootURI);
          if not PlatformDiskSpace(Path, FreeB, TotalB) then
          begin
            FreeB := -1;
            TotalB := -1;
            Err := TVfsError.Make(vecIOError, 'Disk space is not available', RootURI);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, RootURI);
      end;
      DoneFree := FreeB;
      DoneTotal := TotalB;
      DoneErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(DoneFree, DoneTotal, DoneErr);
        end);
    end).Start;
end;

end.
