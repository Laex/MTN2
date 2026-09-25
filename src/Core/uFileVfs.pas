unit uFileVfs;

{ Local file:// VFS provider. All I/O runs off the UI thread and results are
  marshaled via TThread.Queue. Stage 7: Delete / Copy / Move with progress. }

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
  System.Generics.Defaults, Winapi.Windows, uFileRecycleBin, uVfsUtils;

type
  TVfsEntryComparer = class(TComparer<TVfsEntry>)
  public
    function Compare(const Left, Right: TVfsEntry): Integer; override;
  end;

var
  GLastProgressQueueTick: UInt64 = 0;

function FindDataFileTimeToDateTime(const AFT: TFileTime): TDateTime;
var
  LFT: TFileTime;
  ST: TSystemTime;
begin
  Result := 0;
  if (AFT.dwLowDateTime = 0) and (AFT.dwHighDateTime = 0) then
    Exit;
  if FileTimeToLocalFileTime(AFT, LFT) and FileTimeToSystemTime(LFT, ST) then
    Result := SystemTimeToDateTime(ST);
end;

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
  cMinQueueMs = 50; // ~20 Hz — avoid flooding the UI with TThread.Queue
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
  // file's own completion (ID>=IT) — without the latter, a fast per-file
  // finish inside a tree copy routinely lands inside the 50ms window and
  // gets dropped, so the per-file bar visibly skips past 100% straight into
  // the next file's low percentage and never appears to finish.
  Force := ((T > 0) and (D >= T)) or ((IT > 0) and (ID >= IT));
  NowTick := GetTickCount64;
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

// True when ADst is ASrc itself or a path nested inside it — copying a
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
  // ASrc is the expected, intentional outcome — only prove it still exists.
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

// Presence-only walk. Every file this copy actually wrote was already
// size-verified the moment it was written (CopyFileWithProgress), and files
// left untouched by Skip-mode conflict handling are supposed to differ, so
// re-comparing sizes here adds nothing and actively misfires: a live source
// (a log the owning application keeps appending to) is legitimately larger
// now than the snapshot that was copied, and the resulting "size mismatch"
// used to delete the whole freshly copied destination tree.
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
  Code := FindFirst(WinApiPath(TPath.Combine(ASrc, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        ChildSrc := TPath.Combine(ASrc, SR.Name);
        ChildDst := TPath.Combine(ADst, SR.Name);
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
  if LocalPathIsFile(ASrc) or LocalPathIsDirectory(ASrc) or
     TFile.Exists(WinApiPath(ASrc)) or TDirectory.Exists(WinApiPath(ASrc)) then
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
const
  // Only the bits SetFileAttributes actually accepts (per WinAPI docs) —
  // FILE_ATTRIBUTE_DIRECTORY/REPARSE_POINT/COMPRESSED/ENCRYPTED etc. are not
  // settable this way and would make the call fail or be silently ignored.
  AttrMask = FILE_ATTRIBUTE_READONLY or FILE_ATTRIBUTE_HIDDEN or
    FILE_ATTRIBUTE_SYSTEM or FILE_ATTRIBUTE_ARCHIVE or
    FILE_ATTRIBUTE_NOT_CONTENT_INDEXED or FILE_ATTRIBUTE_TEMPORARY or
    FILE_ATTRIBUTE_OFFLINE;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(ASrc)));
  if Attr <> INVALID_FILE_ATTRIBUTES then
    SetFileAttributes(PChar(WinApiPath(ADst)), Attr and AttrMask);
end;

procedure RemoveExistingPath(const APath: string; var AError: TVfsError);
begin
  try
    if TDirectory.Exists(WinApiPath(APath)) then
      TDirectory.Delete(WinApiPath(APath), True)
    else if TFile.Exists(WinApiPath(APath)) then
      TFile.Delete(WinApiPath(APath));
  except
    on E: Exception do
      AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(APath));
  end;
end;

procedure CopyFileWithProgress(const ASrc, ADst: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; var AError: TVfsError;
  AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False;
  ABaseDoneBytes: Int64 = 0; AItemTotalBytes: Int64 = 0);
var
  Src, Dst: TFileStream;
  Buf: TBytes;
  N, Want: Integer;
  Copied, Total, ReportTotal, NowSize: Int64;
  DstCreated, Raised: Boolean;
begin
  Src := nil;
  Dst := nil;
  Copied := 0;
  Total := 0;
  DstCreated := False;
  Raised := False;
  try
    try
      // fmShareDenyNone, not fmShareDenyWrite: a file another process holds
      // open for writing - an application log, a live SQLite/LevelDB store -
      // is still perfectly readable, and denying writers turned every such
      // file into an EFOpenError that escaped this routine, aborted the whole
      // recursive copy at that point and left the rest of the tree uncopied.
      Src := TFileStream.Create(WinApiPath(ASrc), fmOpenRead or fmShareDenyNone);
      if TFile.Exists(WinApiPath(ADst)) or TDirectory.Exists(WinApiPath(ADst)) then
      begin
        if not AOverwrite then
        begin
          AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists', PathToFileUri(ADst));
          Exit;
        end;
        RemoveExistingPath(ADst, AError);
        if AError.Code <> vecOk then
          Exit;
      end;
      Dst := TFileStream.Create(WinApiPath(ADst), fmCreate);
      DstCreated := True;
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
        if N <= 0 then
          Break;
        Dst.WriteBuffer(Buf[0], N);
        Inc(Copied, N);
        // ADone/ATotal stay cumulative across the whole item (base + this
        // file's progress so far), not just this one file's own share — inside
        // a recursive folder copy, ASrc is one of many child files, and the
        // "Total" bar/counter needs the running tree total to move smoothly
        // instead of resetting to a near-zero per-file value on every new
        // child (see CopyTree callers below). AItemDone/AItemTotal/paths carry
        // this file's own progress separately, for the per-file bar.
        QueueProgress(AOnProgress, ABaseDoneBytes + Copied, ReportTotal, TPath.GetFileName(ASrc),
          Copied, Total, ASrc, ADst);
      end;
    except
      // A single unreadable or unwritable file must stay a per-file error
      // carrying its own path, not an exception unwinding out of the caller's
      // whole directory walk and getting reported against the top-level job.
      on E: Exception do
      begin
        Raised := True;
        AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(ASrc));
      end;
    end;
  finally
    Src.Free;
    Dst.Free;
  end;
  if Raised then
  begin
    if DstCreated then
      CleanupFailedCopy(ADst);
    Exit;
  end;
  if AError.Code = vecCancelled then
  begin
    CleanupFailedCopy(ADst);
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
      CleanupFailedCopy(ADst);
      Exit;
    end;
  end;
  VerifyCopiedFile(ASrc, ADst, Total, True, AError);
  if AError.Code <> vecOk then
  begin
    CleanupFailedCopy(ADst);
    Exit;
  end;
  if APreserveTimestamps then
    PreserveFileTimestamps(ASrc, ADst);
  // Attributes (R/H/S/A) are carried over unconditionally, like Explorer/TC
  // do — unrelated to the "preserve timestamps" job option.
  PreserveFileAttributes(ASrc, ADst);
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
begin
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ASrc));
    Exit;
  end;
  if TFile.Exists(WinApiPath(ADst)) then
  begin
    // A plain file sits where a directory needs to go — a real type
    // conflict (only this and per-file leaf conflicts below respect
    // AOverwrite). A directory already existing at ADst is not a conflict at
    // all: recursive copy into an existing folder is a merge by definition,
    // so it falls through to the else-branch below untouched.
    if not AOverwrite then
    begin
      AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists', PathToFileUri(ADst));
      Exit;
    end;
    RemoveExistingPath(ADst, AError);
    if AError.Code <> vecOk then
      Exit;
    TDirectory.CreateDirectory(WinApiPath(ADst));
  end
  else if not TDirectory.Exists(WinApiPath(ADst)) then
    TDirectory.CreateDirectory(WinApiPath(ADst));
  Code := FindFirst(WinApiPath(TPath.Combine(ASrc, '*')), faAnyFile, SR);
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
        ChildSrc := TPath.Combine(ASrc, SR.Name);
        ChildDst := TPath.Combine(ADst, SR.Name);
        ChildErr := TVfsError.Ok;
        if (SR.Attr and faDirectory) <> 0 then
          CopyTree(ChildSrc, ChildDst, ACancel, AOnProgress, ADoneBytes, ATotalBytes,
            ChildErr, AAnySkipped, AOverwrite, APreserveTimestamps)
        else
        begin
          CopyFileWithProgress(ChildSrc, ChildDst, ACancel, AOnProgress, ChildErr,
            AOverwrite, APreserveTimestamps, ADoneBytes, ATotalBytes);
          if ChildErr.Code = vecOk then
          begin
            if SR.Size > 0 then
              Inc(ADoneBytes, SR.Size);
            QueueProgress(AOnProgress, ADoneBytes, ATotalBytes, SR.Name,
              SR.Size, SR.Size, ChildSrc, ChildDst);
          end;
        end;
        // Skip mode (AOverwrite=False): one item already existing at the
        // destination is the expected, common case for a re-run/merge copy —
        // it must not abort the rest of the tree, or nothing past the first
        // pre-existing name ever gets copied (the reported bug). Real
        // failures and cancellation still stop the walk.
        if (ChildErr.Code = vecAlreadyExists) and not AOverwrite then
        begin
          AAnySkipped := True;
          // A skipped item still needs to nudge progress along — without
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
    if AError.Code <> vecOk then
      CleanupFailedCopy(ADst)
    else
    begin
      if APreserveTimestamps then
        PreserveFileTimestamps(ASrc, ADst);
      PreserveFileAttributes(ASrc, ADst);
    end;
  end;
end;

function EstimateTreeBytes(const APath: string): Int64;
var
  SR: TSearchRec;
  Code: Integer;
begin
  Result := 0;
  if TFile.Exists(WinApiPath(APath)) and not TDirectory.Exists(WinApiPath(APath)) then
  begin
    Result := TFile.GetSize(WinApiPath(APath));
    Exit;
  end;
  if not TDirectory.Exists(WinApiPath(APath)) then
    Exit;
  Code := FindFirst(WinApiPath(TPath.Combine(APath, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Inc(Result, EstimateTreeBytes(TPath.Combine(APath, SR.Name)))
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
// DeleteTree below will remove — the denominator for its progress reporting.
// A second walk of the same tree before deletion starts, mirroring
// EstimateTreeBytes above for copy.
function EstimateTreeItemCount(const APath: string): Int64;
var
  SR: TSearchRec;
  Code: Integer;
begin
  if TFile.Exists(WinApiPath(APath)) and not TDirectory.Exists(WinApiPath(APath)) then
    Exit(1);
  if not TDirectory.Exists(WinApiPath(APath)) then
    Exit(0);
  Result := 1; // APath itself
  Code := FindFirst(WinApiPath(TPath.Combine(APath, '*')), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Inc(Result, EstimateTreeItemCount(TPath.Combine(APath, SR.Name)))
        else
          Inc(Result);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure ClearDeleteBlockingAttr(const APath: string);
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
    Exit;
  if (Attr and (FILE_ATTRIBUTE_READONLY or FILE_ATTRIBUTE_HIDDEN or
      FILE_ATTRIBUTE_SYSTEM)) <> 0 then
    SetFileAttributes(PChar(WinApiPath(APath)), Attr and not
      (FILE_ATTRIBUTE_READONLY or FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_SYSTEM));
end;

function ExtendedWinPath(const APath: string): string;
var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(APath);
  if P.StartsWith('\\?\', True) then
    Exit(P);
  if (Length(P) >= 2) and (P[1] = '\') and (P[2] = '\') then
    Result := '\\?\UNC\' + Copy(P, 3, MaxInt)
  else
    Result := '\\?\' + P;
end;

function RetryWin32Delete(const APath: string; AIsDir: Boolean): DWORD;
const
  cMaxTries = 8;
var
  I: Integer;
  P: string;
  Ok: Boolean;
begin
  P := ExtendedWinPath(APath);
  for I := 1 to cMaxTries do
  begin
    ClearDeleteBlockingAttr(P);
    if AIsDir then
      Ok := RemoveDirectory(PChar(P))
    else
      Ok := DeleteFile(PChar(P));
    if Ok then
      Exit(ERROR_SUCCESS);
    Result := GetLastError;
    if (Result = ERROR_FILE_NOT_FOUND) or (Result = ERROR_PATH_NOT_FOUND) then
      Exit(ERROR_SUCCESS);
    if (I < cMaxTries) and
       ((Result = ERROR_SHARING_VIOLATION) or (Result = ERROR_ACCESS_DENIED) or
        (Result = ERROR_DIR_NOT_EMPTY) or (Result = ERROR_LOCK_VIOLATION)) then
      Sleep(25 * I)
    else
      Break;
  end;
end;

procedure SetWin32DeleteError(const APath: string; ACode: DWORD; var AError: TVfsError);
begin
  if (ACode = ERROR_ACCESS_DENIED) or (ACode = ERROR_SHARING_VIOLATION) then
    AError := TVfsError.Make(vecAccessDenied, SysErrorMessage(ACode), PathToFileUri(APath))
  else
    AError := TVfsError.Make(vecIOError, SysErrorMessage(ACode), PathToFileUri(APath));
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
  WinErr: DWORD;
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
    if LocalPathIsDirectory(Path) then
    begin
      Code := FindFirst(WinApiPath(TPath.Combine(Path, '*')), faAnyFile, SR);
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
            Child := TPath.Combine(Path, SR.Name);
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
        WinErr := RetryWin32Delete(Path, True);
        if WinErr <> ERROR_SUCCESS then
        begin
          SetWin32DeleteError(Path, WinErr, FirstErr);
          HasError := True;
        end
        else
        begin
          Inc(ADoneItems);
          QueueProgress(AOnProgress, ADoneItems, ATotalItems,
            TPath.GetFileName(Path), 0, 0, Path, '');
        end;
      end;
    end
    else if LocalPathIsFile(Path) then
    begin
      WinErr := RetryWin32Delete(Path, False);
      if WinErr <> ERROR_SUCCESS then
      begin
        SetWin32DeleteError(Path, WinErr, FirstErr);
        HasError := True;
      end
      else
      begin
        Inc(ADoneItems);
        QueueProgress(AOnProgress, ADoneItems, ATotalItems,
          TPath.GetFileName(Path), 0, 0, Path, '');
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
              Code := FindFirst(WinApiPath(TPath.Combine(Path, '*')), faAnyFile, SR);
              // 5 = ERROR_ACCESS_DENIED (avoid Winapi.Windows — clashes with FindClose).
              if Code = 5 then
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
                    Entry.Extension := LowerCase(TPath.GetExtension(SR.Name));
                    Entry.IsDirectory := (SR.Attr and faDirectory) <> 0;
                    {$WARN SYMBOL_PLATFORM OFF}
                    Entry.IsHidden := ((SR.Attr and faHidden) <> 0) or
                      ((SR.Attr and faSysFile) <> 0);
                    Entry.IsReadOnly := (SR.Attr and faReadOnly) <> 0;
                    Entry.IsSystem := (SR.Attr and faSysFile) <> 0;
                    Entry.IsArchive := (SR.Attr and faArchive) <> 0;
                    Entry.IsCompressed := (SR.Attr and faCompressed) <> 0;
                    Entry.IsEncrypted := (SR.Attr and faEncrypted) <> 0;
                    Entry.IsTemporary := (DWORD(SR.Attr) and FILE_ATTRIBUTE_TEMPORARY) <> 0;
                    Entry.IsOffline := (DWORD(SR.Attr) and FILE_ATTRIBUTE_OFFLINE) <> 0;
                    // Windows: faSymLink = FILE_ATTRIBUTE_REPARSE_POINT
                    Entry.IsLink := (SR.Attr and faSymLink) <> 0;
                    {$WARN SYMBOL_PLATFORM ON}
                    Entry.TargetURI := '';
                    if Entry.IsDirectory then
                    begin
                      Entry.Size := -1;
                      Entry.Extension := '';
                    end
                    else
                      Entry.Size := SR.Size;
                    Entry.ModificationTime := FindDataFileTimeToDateTime(SR.FindData.ftLastWriteTime);
                    if Entry.ModificationTime = 0 then
                      Entry.ModificationTime := SR.TimeStamp;

                    Entry.CreationTime := FindDataFileTimeToDateTime(SR.FindData.ftCreationTime);
                    if Entry.CreationTime = 0 then
                      Entry.CreationTime := Entry.ModificationTime;

                    Entry.AccessTime := FindDataFileTimeToDateTime(SR.FindData.ftLastAccessTime);
                    if Entry.AccessTime = 0 then
                      Entry.AccessTime := Entry.ModificationTime;
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
            DeleteToRecycleBin(Path, Err, OnProgress)
          else
          begin
            DoneItems := 0;
            TotalItems := EstimateTreeItemCount(Path);
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
            Parent := TPath.GetDirectoryName(Path);
            Leaf := TPath.GetFileName(Path);
            if (Parent <> '') and (Leaf <> '') then
            begin
              Parent := ResolveLocalDirPath(Parent);
              if Parent <> '' then
                Path := TPath.Combine(Parent, Leaf);
            end;
            if LocalPathIsDirectory(Path) or LocalPathIsFile(Path) then
              Err := TVfsError.Make(vecAlreadyExists, 'Already exists', URI)
            else
              TDirectory.CreateDirectory(WinApiPath(Path));
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
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
      AnySkipped: Boolean;
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
                Err := TVfsError.Make(vecIOError, E.Message, ToURI);
              end;
            end;
            if Err.Code = vecOk then
            begin
              TotalBytes := EstimateTreeBytes(Src);
              if TotalBytes <= 0 then
                TotalBytes := 1;
              if TDirectory.Exists(WinApiPath(Src)) then
                CopyTree(Src, Dst, Cancel, OnProgress, DoneBytes, TotalBytes, Err,
                  AnySkipped, Overwrite, Preserve)
              else
              begin
                CopyFileWithProgress(Src, Dst, Cancel, OnProgress, Err, Overwrite, Preserve);
                if Err.Code = vecOk then
                  QueueProgress(OnProgress, TotalBytes, TotalBytes, TPath.GetFileName(Src),
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
                if Err.Code <> vecOk then
                  CleanupFailedCopy(Dst);
              end;
            end;
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, FromURI);
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
      Src, Dst: string;
      Err: TVfsError;
      DoneBytes, TotalBytes: Int64;
      SameVolume, WasDirectory, AnySkipped: Boolean;
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
          else if TFile.Exists(WinApiPath(Dst)) then
          begin
            // Dst is an existing file — a real conflict regardless of Src's kind.
            if not Overwrite then
              Err := TVfsError.Make(vecAlreadyExists, 'Destination already exists', ToURI)
            else
              RemoveExistingPath(Dst, Err);
          end
          else if TDirectory.Exists(WinApiPath(Dst)) and not TDirectory.Exists(WinApiPath(Src)) then
          begin
            // Src is a file but Dst is an existing directory — real type conflict.
            if not Overwrite then
              Err := TVfsError.Make(vecAlreadyExists, 'Destination already exists', ToURI)
            else
              RemoveExistingPath(Dst, Err);
          end;
          // Src and Dst both directories, Dst already exists: not treated as a
          // conflict here. Same-volume TDirectory.Move below fails on its own
          // (native Windows limitation, surfaces as a normal I/O error) —
          // cross-volume falls through to CopyTree, which merges into the
          // existing folder per file, honoring AOverwrite/skip like Copy does.
          if Err.Code = vecOk then
          begin
            try
              EnsureDestParentDir(Dst);
            except
              on E: Exception do
                Err := TVfsError.Make(vecIOError, E.Message, ToURI);
            end;
          end;
          if Err.Code = vecOk then
          begin
            WasDirectory := TDirectory.Exists(WinApiPath(Src));
            SameVolume := (Length(Src) >= 2) and (Length(Dst) >= 2) and
              (UpCase(Src[1]) = UpCase(Dst[1])) and (Src[2] = ':') and (Dst[2] = ':');
            if SameVolume then
            begin
              QueueProgress(OnProgress, 0, 1, TPath.GetFileName(Src), 0, 1, Src, Dst);
              try
                if WasDirectory then
                  TDirectory.Move(WinApiPath(Src), WinApiPath(Dst))
                else
                  TFile.Move(WinApiPath(Src), WinApiPath(Dst));
                QueueProgress(OnProgress, 1, 1, TPath.GetFileName(Dst), 1, 1, Src, Dst);
              except
                on E: Exception do
                  Err := TVfsError.Make(vecIOError, E.Message, FromURI);
              end;
              if Err.Code = vecOk then
                VerifyMoveResult(Src, Dst, WasDirectory, Err);
            end
            else
            begin
              // Cross-volume: copy then delete source.
              TotalBytes := EstimateTreeBytes(Src);
              if TotalBytes <= 0 then
                TotalBytes := 1;
              DoneBytes := 0;
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
                if Err.Code <> vecOk then
                  CleanupFailedCopy(Dst)
                // Skip mode left at least one source item untouched at the
                // destination (see CopyTree) — it still exists only in Src,
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
                    Err := TVfsError.Make(vecIOError, E.Message, FromURI);
                end;
              end;
            end;
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, FromURI);
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
      Attrs: TFileAttributes;
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
              {$WARN SYMBOL_PLATFORM OFF}
              Attrs := TFile.GetAttributes(WinApiPath(Path));
              if TFileAttribute.faReadOnly in Attrs then
                Err := TVfsError.Make(vecAccessDenied, 'File is read-only', URI);
              {$WARN SYMBOL_PLATFORM ON}
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
      Path, Drive: string;
      Err, DoneErr: TVfsError;
      FreeAvail, TotalNum: UInt64;
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
          Drive := ExtractFileDrive(Path);
          if Drive = '' then
            Err := TVfsError.Make(vecInvalidURI, 'No drive root', RootURI)
          else
          begin
            Drive := IncludeTrailingPathDelimiter(Drive);
            if GetDiskFreeSpaceEx(PChar(Drive), FreeAvail, TotalNum, nil) then
            begin
              FreeB := Int64(FreeAvail);
              TotalB := Int64(TotalNum);
            end
            else
              Err := TVfsError.Make(vecIOError, 'GetDiskFreeSpaceEx failed', RootURI);
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
