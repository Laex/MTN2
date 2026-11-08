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

var
  /// <summary>A file of a recursive copy that failed with an I/O error is retried
  /// this many times, waiting CopyRetryBaseDelayMs, twice that, four times that
  /// ..., before the job's error resolver is asked. A network share that drops
  /// its session for a moment usually answers again within that time.</summary>
  CopyAutoRetries: Integer = 3;
  CopyRetryBaseDelayMs: Integer = 1000;

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
  var AError: TVfsError; ATolerateMissing: Boolean = False);
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
        begin
          // A folder whose files were all skipped after errors is not created.
          if not ATolerateMissing or LocalPathIsDirectory(ChildDst) then
            VerifyCopiedTree(ChildSrc, ChildDst, AError, ATolerateMissing);
        end
        // A file the user chose to skip after a copy error is legitimately
        // absent from the destination.
        else if not ATolerateMissing or TFile.Exists(WinApiPath(ChildDst)) then
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

// Chooses where the bytes of a new destination file are written: always a
// sibling file (ADst plus ".mtnpart") that takes the real name only after the
// bytes are complete, so a copy that fails, is cancelled or is cut off by a
// crash never leaves a truncated file under the destination's name. An existing
// destination is replaced only with AOverwrite, and a failed or cancelled copy
// then leaves the previous file or directory in place.
function ChooseCopyWritePath(const ADst: string; AOverwrite: Boolean;
  out AWritePath: string; out AStaged: Boolean; var AError: TVfsError): Boolean;
begin
  Result := False;
  AWritePath := ADst;
  AStaged := False;
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
  AWritePath := UnusedSiblingPath(ADst, '.mtnpart');
  if AWritePath = '' then
  begin
    AError := TVfsError.Make(vecIOError,
      'Cannot make room to write the destination', PathToFileUri(ADst));
    Exit;
  end;
  AStaged := True;
  Result := True;
end;

// Streams ATotal bytes of ASrc into ADst and returns how many were copied; a
// cancel is reported in AError. Exceptions go to the caller.
function PumpCopyBytes(ASrcStream, ADstStream: TFileStream; const ASrc, ADst: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; ABaseDoneBytes,
  AReportTotal, ATotal: Int64; var AError: TVfsError): Int64;
var
  Buf: TBytes;
  N, Want: Integer;
begin
  Result := 0;
  // 256 KiB: fewer read/write calls and throttle checks per file than a
  // 64 KiB block, which matters most on network shares and large files.
  SetLength(Buf, 256 * 1024);
  while Result < ATotal do
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
    if ATotal - Result < Want then
      Want := Integer(ATotal - Result);
    N := ASrcStream.Read(Buf[0], Want);
    // A failed read (an offline cloud placeholder, a drive that went away)
    // reports the system's own reason, not just a short copy.
    if N < 0 then
      RaiseLastOSError;
    if N = 0 then
      Break;
    ADstStream.WriteBuffer(Buf[0], N);
    Inc(Result, N);
    // ADone/ATotal stay cumulative across the whole item (base + this file's
    // progress so far), so inside a recursive folder copy the "Total" bar
    // moves smoothly instead of resetting on every child.
    // AItemDone/AItemTotal/paths carry this file's own progress separately,
    // for the per-file bar.
    QueueProgress(AOnProgress, ABaseDoneBytes + Result, AReportTotal, SafeFileName(ASrc),
      Result, ATotal, ASrc, ADst);
    JobThrottle(ACancel, N);
  end;
end;

// Checks and publishes a copied file once its bytes are written. AError holds
// a cancel from the copy loop; a failed check removes the fragment.
procedure FinishCopiedFile(const ASrc, ADst, AWritePath: string; ACopied, ATotal: Int64;
  ADstCreated, AStaged, APreserveTimestamps: Boolean; var AError: TVfsError);
var
  NowSize: Int64;
  MoveMsg: string;
begin
  if AError.Code = vecCancelled then
  begin
    if ADstCreated then
      CleanupFailedCopy(AWritePath);
    Exit;
  end;
  if AError.Code <> vecOk then
    Exit;
  if ACopied <> ATotal then
  begin
    // Short read: either the source really was truncated under us - in which
    // case ACopied is the whole file as it now stands and the copy is complete
    // - or something failed mid-stream and the destination is a fragment.
    NowSize := -1;
    try
      NowSize := TFile.GetSize(WinApiPath(ASrc));
    except
      // Leave NowSize at -1 and report the short copy below.
    end;
    if NowSize <> ACopied then
    begin
      AError := TVfsError.Make(vecIOError,
        Format('Copy incomplete (%d of %d bytes)', [ACopied, ATotal]), PathToFileUri(ASrc));
      if ADstCreated then
        CleanupFailedCopy(AWritePath);
      Exit;
    end;
  end;
  // An appended file keeps its own timestamps and is larger than the source
  // by design.
  if not ADstCreated then
    Exit;
  VerifyCopiedFile(ASrc, AWritePath, ACopied, True, AError);
  if AError.Code <> vecOk then
  begin
    CleanupFailedCopy(AWritePath);
    Exit;
  end;
  if AStaged and not ReplacePathWith(WinApiPath(AWritePath), WinApiPath(ADst), MoveMsg) then
  begin
    AError := TVfsError.Make(vecIOError, MoveMsg, PathToFileUri(ADst));
    CleanupFailedCopy(AWritePath);
    Exit;
  end;
  if APreserveTimestamps then
    PreserveFileTimestamps(ASrc, ADst);
  // Attributes (R/H/S/A) are carried over unconditionally, like Explorer/TC
  // do - unrelated to the "preserve timestamps" job option.
  PreserveFileAttributes(ASrc, ADst);
end;

procedure CopyFileWithProgress(const ASrc, ADst: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var AError: TVfsError;
  AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False;
  ABaseDoneBytes: Int64 = 0; AItemTotalBytes: Int64 = 0; AAppend: Boolean = False);
var
  Src, Dst: TFileStream;
  Copied, Total, ReportTotal: Int64;
  DstCreated, Raised, Staged: Boolean;
  WritePath: string;
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
      // is still readable, and denying writers would turn every such file
      // into an EFOpenError that aborts a recursive copy at that point.
      // A skipped file must cost only this check: opening the source first
      // is slow on network shares and on-demand cloud folders.
      if not AOverwrite and not AAppend and TFile.Exists(WinApiPath(ADst)) then
      begin
        AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists',
          PathToFileUri(ADst));
        Exit;
      end;
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
        if not ChooseCopyWritePath(ADst, AOverwrite, WritePath, Staged, AError) then
          Exit;
        Dst := TFileStream.Create(WinApiPath(WritePath), fmCreate);
        DstCreated := True;
      end;
      Total := Src.Size;
      ReportTotal := AItemTotalBytes;
      if ReportTotal <= 0 then
        ReportTotal := Total;
      Copied := PumpCopyBytes(Src, Dst, ASrc, ADst, ACancel, AOnProgress,
        ABaseDoneBytes, ReportTotal, Total, AError);
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
  // A source that shrank during the copy ends the file where it now ends.
  FinishCopiedFile(ASrc, ADst, WritePath, Copied, Total, DstCreated, Staged,
    APreserveTimestamps, AError);
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

// Waits for AMs milliseconds in short slices so a cancel is noticed promptly.
procedure WaitInterruptible(AMs: Integer; ACancel: IJobCancelToken);
var
  Left: Integer;
begin
  Left := AMs;
  while (Left > 0) and not JobCancelRequested(ACancel) do
  begin
    Sleep(100);
    Dec(Left, 100);
  end;
end;

// Copies one file of a recursive copy. A failure with an I/O error is retried
// on its own, then put to the job's error resolver, so one unreadable file
// costs a retry or a skip of that file and not the rest of the folder.
// Without a resolver the first failure is returned as it always was.
// ASkipped reports that the user skipped the file (AError is then vecOk).
procedure CopyTreeFile(const ASrc, ADst: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var AError: TVfsError; AOverwrite,
  APreserveTimestamps: Boolean; ABaseDoneBytes, AItemTotalBytes: Int64;
  AAppend: Boolean; out ASkipped: Boolean);
var
  Attempt: Integer;
  Resolver: TVfsErrorResolver;
begin
  ASkipped := False;
  Attempt := 0;
  while True do
  begin
    // Each attempt starts clean: a failure of the previous one must not make
    // a successful retry report it again.
    AError := TVfsError.Ok;
    CopyFileWithProgress(ASrc, ADst, ACancel, AOnProgress, AError, AOverwrite,
      APreserveTimestamps, ABaseDoneBytes, AItemTotalBytes, AAppend);
    if AError.Code in [vecOk, vecCancelled, vecAlreadyExists] then
      Exit;
    if JobCancelRequested(ACancel) then
      Exit;
    Resolver := JobErrorResolver(ACancel);
    if not Assigned(Resolver) then
      Exit;
    if (AError.Code = vecIOError) and (Attempt < CopyAutoRetries) then
    begin
      WaitInterruptible(CopyRetryBaseDelayMs shl Attempt, ACancel);
      Inc(Attempt);
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
        Exit;
      end;
      Continue;
    end;
    case Resolver(AError) of
      vcaRetry:
        ;
      vcaSkip:
        begin
          AError := TVfsError.Ok;
          ASkipped := True;
          Exit;
        end;
    else
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
        Exit;
      end;
    end;
  end;
end;

// Copies one file child of a recursive copy and reports its progress. AChildErr
// is vecAlreadyExists when the conflict resolver (or skip mode) left the file
// untouched.
procedure CopyTreeChildFile(const AChildSrc: string; var AChildDst: string;
  const AName: string; ASize: Int64; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneBytes, ATotalBytes: Int64;
  var AAnySkipped: Boolean; var AChildErr: TVfsError; AOverwrite,
  APreserveTimestamps: Boolean);
var
  ChildOverwrite, ChildAppend, ChildSkipped: Boolean;
begin
  ChildOverwrite := AOverwrite;
  ChildAppend := False;
  if not AOverwrite then
    AskFileConflict(AChildSrc, AChildDst, ACancel, ChildOverwrite, ChildAppend,
      AChildErr);
  ChildSkipped := False;
  if AChildErr.Code = vecOk then
    CopyTreeFile(AChildSrc, AChildDst, ACancel, AOnProgress, AChildErr,
      ChildOverwrite, APreserveTimestamps, ADoneBytes, ATotalBytes,
      ChildAppend, ChildSkipped);
  if ChildSkipped then
  begin
    // Skipped after an error: the file stays only in the source, so
    // the tree check and a move's source delete must know about it.
    AAnySkipped := True;
    JobNoteSkipped(ACancel);
    if ASize > 0 then
      Inc(ADoneBytes, ASize);
    QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, AName, 0, 0,
      AChildSrc, AChildDst);
  end
  else if AChildErr.Code = vecOk then
  begin
    if ASize > 0 then
      Inc(ADoneBytes, ASize);
    QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, AName,
      ASize, ASize, AChildSrc, AChildDst);
  end;
end;

// Judges the outcome of one child of a recursive copy. Returns False when the
// walk must stop, with the failure in AError.
//
// Skip mode (AOverwrite=False): one item already existing at the destination
// is the expected, common case for a re-run/merge copy - it must not abort the
// rest of the tree, or nothing past the first pre-existing name would get
// copied. Real failures and cancellation still stop the walk.
function ChildCopyAllowsContinue(const AChildSrc, AChildDst, AName: string;
  AIsDir: Boolean; const AChildErr: TVfsError; AOverwrite: Boolean;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  ADoneBytes, ATotalBytes: Int64; var AAnySkipped: Boolean;
  var AError: TVfsError): Boolean;
begin
  Result := True;
  if (AChildErr.Code = vecAlreadyExists) and not AOverwrite then
  begin
    AAnySkipped := True;
    if not AIsDir then
      JobNoteSkipped(ACancel);
    // A skipped item still needs to nudge progress along - without this, a
    // run of skipped files never advances the per-file bar, the file counter
    // or the current-name display, and the job looks stalled. Item bytes stay
    // 0/0 (nothing was transferred), but the path still identifies it as a
    // processed item.
    QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, AName, 0, 0,
      AChildSrc, AChildDst);
  end
  else if AChildErr.Code <> vecOk then
  begin
    AError := AChildErr;
    Result := False;
  end;
end;

// Checks a finished tree copy. A folder that already existed is a merge
// target: a failed check must not delete the files that were there before.
procedure FinishCopiedTree(const ASrc, ADst: string; ACreatedHere,
  APreserveTimestamps: Boolean; var AAnySkipped: Boolean; var AError: TVfsError);
begin
  VerifyCopiedTree(ASrc, ADst, AError, AAnySkipped);
  if (AError.Code <> vecOk) and ACreatedHere then
    CleanupFailedCopy(ADst)
  else
  begin
    if APreserveTimestamps then
      PreserveFileTimestamps(ASrc, ADst);
    PreserveFileAttributes(ASrc, ADst);
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
  CreatedHere, IsDir: Boolean;
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
  end;
  if not TDirectory.Exists(WinApiPath(ADst)) then
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
        IsDir := (SR.Attr and faDirectory) <> 0;
        if IsDir then
          CopyTree(ChildSrc, ChildDst, ACancel, AOnProgress, ADoneBytes, ATotalBytes,
            ChildErr, AAnySkipped, AOverwrite, APreserveTimestamps)
        else
          CopyTreeChildFile(ChildSrc, ChildDst, SR.Name, SR.Size, ACancel,
            AOnProgress, ADoneBytes, ATotalBytes, AAnySkipped, ChildErr,
            AOverwrite, APreserveTimestamps);
        if not ChildCopyAllowsContinue(ChildSrc, ChildDst, SR.Name, IsDir,
          ChildErr, AOverwrite, ACancel, AOnProgress, ADoneBytes, ATotalBytes,
          AAnySkipped, AError) then
          Exit;
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
  if AError.Code = vecOk then
    FinishCopiedTree(ASrc, ADst, CreatedHere, APreserveTimestamps, AAnySkipped,
      AError);
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

// Removes one file or empty folder. A refusal goes to the job's error resolver
// when it has one: retry repeats the node, skip leaves it in place (ASkipped,
// AError is then vecOk), anything else ends the delete as cancelled.
function DeleteNodeResolved(const APath: string; AIsDir: Boolean;
  ACancel: IJobCancelToken; var AError: TVfsError; out ASkipped: Boolean): Boolean;
var
  Resolver: TVfsErrorResolver;
begin
  ASkipped := False;
  while True do
  begin
    if PlatformDeleteNode(APath, AIsDir, AError) then
      Exit(True);
    Resolver := JobErrorResolver(ACancel);
    if JobCancelRequested(ACancel) or not Assigned(Resolver) or
       (AError.Code = vecNotFound) then
      Exit(False);
    case Resolver(AError) of
      vcaRetry:
        ;
      vcaSkip:
        begin
          AError := TVfsError.Ok;
          ASkipped := True;
          JobNoteSkipped(ACancel);
          Exit(True);
        end;
    else
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(APath));
        Exit(False);
      end;
    end;
  end;
end;

procedure DeleteTree(const APath: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneItems: Int64; ATotalItems: Int64;
  var AError: TVfsError; var ASkipped: Boolean); forward;

// Removes one file or empty folder and counts it in the delete progress.
procedure DeleteCountedNode(const APath: string; AIsDir: Boolean;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  var ADoneItems: Int64; ATotalItems: Int64; var AFirstErr: TVfsError;
  var AHasError, ANodeSkipped: Boolean);
begin
  if not DeleteNodeResolved(APath, AIsDir, ACancel, AFirstErr, ANodeSkipped) then
    AHasError := True
  else if not ANodeSkipped then
  begin
    Inc(ADoneItems);
    QueueProgress(AOnProgress, ADoneItems, ATotalItems,
      SafeFileName(APath), 0, 0, APath, '');
  end;
end;

// Deletes everything inside the folder APath. The first failure is kept in
// AFirstErr; a cancel or an access refusal stops the walk at once.
procedure DeleteTreeChildren(const APath: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneItems: Int64; ATotalItems: Int64;
  var AFirstErr: TVfsError; var AHasError, ANodeSkipped: Boolean);
var
  SR: TSearchRec;
  Code: Integer;
  ChildErr: TVfsError;
  ChildSkipped: Boolean;
begin
  Code := FindFirst(WinApiPath(SafeCombinePath(APath, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AFirstErr := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(APath));
        AHasError := True;
        Break;
      end;
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        ChildErr := TVfsError.Ok;
        ChildSkipped := False;
        DeleteTree(SafeCombinePath(APath, SR.Name), ACancel, AOnProgress,
          ADoneItems, ATotalItems, ChildErr, ChildSkipped);
        if ChildSkipped then
          ANodeSkipped := True;
        if ChildErr.Code <> vecOk then
        begin
          // Without a resolver a refused node means the rest of the tree is
          // refused as well: stopping here lets the administrator offer
          // appear at once.
          if (ChildErr.Code = vecCancelled) or (ChildErr.Code = vecAccessDenied) then
          begin
            AFirstErr := ChildErr;
            AHasError := True;
            Break;
          end;
          if not AHasError then
          begin
            AFirstErr := ChildErr;
            AHasError := True;
          end;
        end;
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

// ASkipped reports that something under APath was left in place after the job's
// error resolver said skip; the folders above it then stay as well.
procedure DeleteTree(const APath: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var ADoneItems: Int64; ATotalItems: Int64;
  var AError: TVfsError; var ASkipped: Boolean);
var
  Path: string;
  FirstErr: TVfsError;
  HasError, NodeSkipped: Boolean;
begin
  NodeSkipped := False;
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
      DeleteTreeChildren(Path, ACancel, AOnProgress, ADoneItems, ATotalItems,
        FirstErr, HasError, NodeSkipped);
      if not HasError and not NodeSkipped then
        DeleteCountedNode(Path, True, ACancel, AOnProgress, ADoneItems,
          ATotalItems, FirstErr, HasError, NodeSkipped);
    end
    else if LocalPathIsFile(Path) or PlatformIsLinkNode(Path) then
      DeleteCountedNode(Path, False, ACancel, AOnProgress, ADoneItems,
        ATotalItems, FirstErr, HasError, NodeSkipped)
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

  ASkipped := NodeSkipped;
  if HasError then
    AError := FirstErr
  else
    AError := TVfsError.Ok;
end;

// Reads the entries of directory APath into AList; a cancel or a refused
// listing is reported in AErr.
procedure CollectDirectoryEntries(const APath, AURI: string; ACancel: IJobCancelToken;
  AList: TList<TVfsEntry>; var AErr: TVfsError);
var
  SR: TSearchRec;
  Entry: TVfsEntry;
  Code: Integer;
begin
  Code := FindFirst(WinApiPath(SafeCombinePath(APath, '*')), faAnyFile, SR);
  if PlatformSearchDenied(Code) then
  begin
    AErr := TVfsError.Make(vecAccessDenied, 'Access denied', AURI);
    Exit;
  end;
  if Code <> 0 then
    Exit;
  try
    while Code = 0 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AErr := TVfsError.Make(vecCancelled, 'Cancelled', AURI);
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
        AList.Add(Entry);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

// Lists the local directory AURI names, sorted; AItems stays empty on failure.
procedure ListLocalDirectory(const AURI: string; ACancel: IJobCancelToken;
  var AItems: TArray<TVfsEntry>; var AErr: TVfsError);
var
  Path: string;
  List: TList<TVfsEntry>;
begin
  SetLength(AItems, 0);
  if JobCancelRequested(ACancel) then
  begin
    AErr := TVfsError.Make(vecCancelled, 'Cancelled', AURI);
    Exit;
  end;
  Path := ResolveLocalDirPath(FileUriToPath(AURI));
  if Path = '' then
  begin
    AErr := TVfsError.Make(vecInvalidURI, 'Invalid file URI', AURI);
    Exit;
  end;
  if not LocalPathIsDirectory(Path) then
  begin
    if LocalPathIsFile(Path) then
      AErr := TVfsError.Make(vecNotSupported, 'Not a directory', AURI)
    else
      AErr := TVfsError.Make(vecNotFound, 'Path not found', AURI);
    Exit;
  end;
  List := TList<TVfsEntry>.Create;
  try
    CollectDirectoryEntries(Path, AURI, ACancel, List, AErr);
    if AErr.Code = vecOk then
    begin
      List.Sort(TVfsEntryComparer.Create);
      AItems := List.ToArray;
    end;
  finally
    List.Free;
  end;
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
      Items, DoneItems: TArray<TVfsEntry>;
      Err, DoneErr: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        ListLocalDirectory(URI, Cancel, Items, Err);
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
      TreeSkipped: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      TreeSkipped := False;
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
            DeleteTree(Path, Cancel, OnProgress, DoneItems, TotalItems, Err, TreeSkipped);
            if (Err.Code = vecOk) and not TreeSkipped then
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
                  VerifyCopiedTree(Src, Dst, Err, AnySkipped)
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

// Validates a move request. ACaseOnly is True when source and destination
// differ only in letter case (one item on Windows, so no clash).
procedure CheckMoveRequest(const ASrc, ADst, AFromURI, AToURI: string;
  AOverwrite, ACaseOnly: Boolean; var AErr: TVfsError);
begin
  if (ASrc = '') or (ADst = '') then
    AErr := TVfsError.Make(vecInvalidURI, 'Invalid file URI', AFromURI)
  else if not (TFile.Exists(WinApiPath(ASrc)) or TDirectory.Exists(WinApiPath(ASrc))) then
    AErr := TVfsError.Make(vecNotFound, 'Source not found', AFromURI)
  else if TFile.Exists(WinApiPath(ADst)) and not AOverwrite and not ACaseOnly then
    // An existing file is replaced only when overwrite is on, and then
    // by the move or copy later - not deleted before that succeeds.
    AErr := TVfsError.Make(vecAlreadyExists, 'Destination already exists', AToURI)
  else if TDirectory.Exists(WinApiPath(ADst)) and not ACaseOnly and
    not TDirectory.Exists(WinApiPath(ASrc)) and not AOverwrite then
    AErr := TVfsError.Make(vecAlreadyExists, 'Destination already exists', AToURI);
end;

// Prepares the destination of a validated move. Src and Dst both directories
// with Dst existing is not a conflict: a same-volume rename onto an existing
// folder fails (native Windows limitation), so an empty Dst is removed and
// the folder renamed, and a non-empty Dst (AMergeIntoDir) takes the
// copy-and-delete path, where CopyTree merges per file honoring
// overwrite/skip like Copy does.
procedure PrepareMoveDestination(const ASrc, ADst, AToURI: string; ACaseOnly: Boolean;
  var AMergeIntoDir: Boolean; var AErr: TVfsError);
begin
  AMergeIntoDir := not ACaseOnly and TDirectory.Exists(WinApiPath(ADst)) and
    TDirectory.Exists(WinApiPath(ASrc));
  try
    if AMergeIntoDir and TDirectory.IsEmpty(WinApiPath(ADst)) then
    begin
      TDirectory.Delete(WinApiPath(ADst), False);
      AMergeIntoDir := False;
    end;
    EnsureDestParentDir(ADst);
  except
    on E: Exception do
      AErr := VfsErrorFromException(E, AToURI);
  end;
end;

// True when a plain rename can do the move: both paths on one drive letter and
// no file/directory name clash (those cannot be renamed over each other and go
// through the copy, which swaps only after the new tree exists).
function CanRenameInPlace(const ASrc, ADst: string; AMergeIntoDir,
  AWasDirectory: Boolean): Boolean;
begin
  Result := (not AMergeIntoDir) and (Length(ASrc) >= 2) and
    (Length(ADst) >= 2) and
    (UpCase(ASrc[1]) = UpCase(ADst[1])) and (ASrc[2] = ':') and (ADst[2] = ':') and
    not (AWasDirectory and TFile.Exists(WinApiPath(ADst))) and
    not ((not AWasDirectory) and TDirectory.Exists(WinApiPath(ADst)));
end;

procedure RenameMove(const ASrc, ADst, AFromURI: string; ACaseOnly, AWasDirectory: Boolean;
  AOnProgress: TVfsProgressCallback; var AErr: TVfsError);
var
  MoveMsg: string;
begin
  QueueProgress(AOnProgress, 0, 1, SafeFileName(ASrc), 0, 1, ASrc, ADst);
  try
    if ACaseOnly or PathHasBlankEndedName(ASrc) or PathHasBlankEndedName(ADst) or
      ((not AWasDirectory) and TFile.Exists(WinApiPath(ADst))) then
    begin
      // TDirectory.Move and TFile.Move cut the space off such a name
      // and refuse an existing destination, which a case-only rename
      // always has.
      // Replace keeps the previous file when the rename itself fails.
      if not PlatformMoveFile(WinApiPath(ASrc), WinApiPath(ADst),
        (not AWasDirectory) and not ACaseOnly and
        TFile.Exists(WinApiPath(ADst)), MoveMsg) then
        raise EInOutError.Create(MoveMsg);
    end
    else if AWasDirectory then
      TDirectory.Move(WinApiPath(ASrc), WinApiPath(ADst))
    else
      TFile.Move(WinApiPath(ASrc), WinApiPath(ADst));
    QueueProgress(AOnProgress, 1, 1, SafeFileName(ADst), 1, 1, ASrc, ADst);
  except
    on E: Exception do
      AErr := VfsErrorFromException(E, AFromURI);
  end;
  // The source name still resolves to the renamed item, so the
  // "source is gone" check does not apply to a case-only rename.
  if (AErr.Code = vecOk) and not ACaseOnly then
    VerifyMoveResult(ASrc, ADst, AWasDirectory, AErr);
end;

// Cross-volume move, or a file/directory name clash: copy, verify, delete source.
procedure CopyDeleteMove(const ASrc, ADst, AFromURI: string; AWasDirectory: Boolean;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOverwrite, APreserve: Boolean; var AErr: TVfsError);
var
  DoneBytes, TotalBytes: Int64;
  AnySkipped, DestWasDir: Boolean;
begin
  AnySkipped := False;
  TotalBytes := EstimateTreeBytes(ASrc, ACancel, AOnProgress);
  if TotalBytes <= 0 then
    TotalBytes := 1;
  DoneBytes := 0;
  DestWasDir := TDirectory.Exists(WinApiPath(ADst));
  if AWasDirectory then
    CopyTree(ASrc, ADst, ACancel, AOnProgress, DoneBytes, TotalBytes, AErr,
      AnySkipped, AOverwrite, APreserve)
  else
    CopyFileWithProgress(ASrc, ADst, ACancel, AOnProgress, AErr, AOverwrite, APreserve);
  if AErr.Code <> vecOk then
    Exit;
  if AWasDirectory then
    VerifyCopiedTree(ASrc, ADst, AErr, AnySkipped)
  else
    // Non-strict for the same reason as VerifyCopiedTree: the
    // strict size check already ran inside the copy itself.
    VerifyCopiedFile(ASrc, ADst, TFile.GetSize(WinApiPath(ASrc)), False, AErr);
  if AErr.Code <> vecOk then
  begin
    if not DestWasDir then
      CleanupFailedCopy(ADst);
    Exit;
  end;
  // Skip mode left at least one source item untouched at the destination (see
  // CopyTree) - it still exists only in Src, so deleting Src here (the whole
  // point of Move) would lose it. Leave the whole source tree in place
  // instead; the merge itself already succeeded for everything copied.
  if AWasDirectory and AnySkipped then
    Exit;
  try
    if AWasDirectory then
      TDirectory.Delete(WinApiPath(ASrc), True)
    else
      TFile.Delete(WinApiPath(ASrc));
  except
    on E: Exception do
      AErr := VfsErrorFromException(E, AFromURI);
  end;
end;

procedure RunMove(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOverwrite, APreserve: Boolean;
  var AErr: TVfsError);
var
  Src, Dst: string;
  WasDirectory, MergeIntoDir, CaseOnly: Boolean;
begin
  if JobCancelRequested(ACancel) then
  begin
    AErr := TVfsError.Make(vecCancelled, 'Cancelled', AFromURI);
    Exit;
  end;
  Src := FileUriToPath(AFromURI);
  Dst := FileUriToPath(AToURI);
  // Windows names that differ only in letter case are one item: the
  // rename is a plain in-place move, not a clash with an existing
  // destination.
{$IFDEF MSWINDOWS}
  CaseOnly := SameText(Src, Dst) and (Src <> Dst);
{$ELSE}
  CaseOnly := False;
{$ENDIF}
  CheckMoveRequest(Src, Dst, AFromURI, AToURI, AOverwrite, CaseOnly, AErr);
  if AErr.Code <> vecOk then
    Exit;
  PrepareMoveDestination(Src, Dst, AToURI, CaseOnly, MergeIntoDir, AErr);
  if AErr.Code <> vecOk then
    Exit;
  WasDirectory := TDirectory.Exists(WinApiPath(Src));
  if CanRenameInPlace(Src, Dst, MergeIntoDir, WasDirectory) then
    RenameMove(Src, Dst, AFromURI, CaseOnly, WasDirectory, AOnProgress, AErr)
  else
    CopyDeleteMove(Src, Dst, AFromURI, WasDirectory, ACancel, AOnProgress,
      AOverwrite, APreserve, AErr);
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
      Err: TVfsError;
    begin
      Err := TVfsError.Ok;
      Err.URI := FromURI;
      try
        RunMove(FromURI, ToURI, Cancel, OnProgress, Overwrite, Preserve, Err);
      except
        on E: Exception do
          Err := VfsErrorFromException(E, FromURI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

// Reads the whole file AURI names into ABuf. A file larger than AMaxBytes is
// refused before any buffer is allocated. Failures other than exceptions are
// reported in AErr; ABuf is empty then.
procedure ReadLocalFileBytes(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; var ABuf: TBytes; var AErr: TVfsError);
var
  Path: string;
  FS: TFileStream;
  Size: Int64;
begin
  SetLength(ABuf, 0);
  if JobCancelRequested(ACancel) then
  begin
    AErr := TVfsError.Make(vecCancelled, 'Cancelled', AURI);
    Exit;
  end;
  Path := FileUriToPath(AURI);
  if Path = '' then
  begin
    AErr := TVfsError.Make(vecInvalidURI, 'Invalid file URI', AURI);
    Exit;
  end;
  if not TFile.Exists(WinApiPath(Path)) then
  begin
    AErr := TVfsError.Make(vecNotFound, 'File not found', AURI);
    Exit;
  end;
  Size := TFile.GetSize(WinApiPath(Path));
  if Size > AMaxBytes then
  begin
    AErr := TVfsError.Make(vecNotSupported,
      Format('File too large (max %d KB).', [AMaxBytes div 1024]), AURI);
    Exit;
  end;
  FS := TFileStream.Create(WinApiPath(Path), fmOpenRead or fmShareDenyNone);
  try
    SetLength(ABuf, Size);
    if Size > 0 then
      SetLength(ABuf, FS.Read(ABuf[0], Size));
  finally
    FS.Free;
  end;
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
      Err: TVfsError;
      Text: string;
      Buf: TBytes;
      Enc: TTextFileEncoding;
      IsBin: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Text := '';
      Enc := tfeUtf8;
      try
        ReadLocalFileBytes(URI, MaxBytes, Cancel, Buf, Err);
        if (Err.Code = vecOk) and not DetectAndDecodeText(Buf, Text, Enc, IsBin) then
        begin
          if IsBin then
            Err := TVfsError.Make(vecNotSupported, 'Binary file', URI)
          else
            Err := TVfsError.Make(vecIOError, 'Cannot decode text', URI);
          Text := '';
        end;
      except
        on E: Exception do
        begin
          Err := VfsErrorFromException(E, URI);
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
      Err: TVfsError;
      Buf: TBytes;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Buf, 0);
      try
        ReadLocalFileBytes(URI, MaxBytes, Cancel, Buf, Err);
      except
        on E: Exception do
        begin
          Err := VfsErrorFromException(E, URI);
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
