unit uVfsTypes;

{ Async VFS contract (SDS §5.1). }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.SyncObjs,
  uTextEncoding;

type
  TVfsEntry = record
    Name: string;
    Extension: string;
    Size: Int64;
    IsDirectory: Boolean;
    IsHidden: Boolean;
    IsReadOnly: Boolean;
    IsSystem: Boolean;
    IsArchive: Boolean;
    IsCompressed: Boolean;
    IsEncrypted: Boolean;
    IsTemporary: Boolean;
    IsOffline: Boolean;
    /// <summary>Symlink / junction / other reparse point.</summary>
    IsLink: Boolean;
    /// <summary>POSIX permission bits (rwx for owner, group, others, with the
    /// setuid, setgid and sticky bits); 0 when the provider has none.</summary>
    UnixMode: Cardinal;
    CreationTime: TDateTime;
    ModificationTime: TDateTime;
    AccessTime: TDateTime;
    /// <summary>When set, panel row URI uses this instead of Join(dir, Name).</summary>
    TargetURI: string;
    /// <summary>Alt+F7 content-search hit info (find:// backend only; 0/''
    /// everywhere else - MatchSnippet is a managed field so it is always
    /// safely '' by default even where nothing sets it explicitly).</summary>
    MatchLine: Integer;
    MatchSnippet: string;
  end;

  TVfsErrorCode = (
    vecOk,
    vecNotFound,
    vecAccessDenied,
    vecAlreadyExists,
    vecNotSupported,
    vecCancelled,
    vecIOError,
    vecInvalidURI
  );

  TVfsError = record
    Code: TVfsErrorCode;
    Message: string;
    URI: string;
    class function Ok: TVfsError; static;
    class function Make(ACode: TVfsErrorCode; const AMessage, AURI: string): TVfsError; static;
  end;

  /// <summary>vdmRecycleBin = Windows Recycle Bin (FOF_ALLOWUNDO); else permanent.</summary>
  TVfsDeleteMode = (vdmRecycleBin, vdmPermanent);

  /// <summary>Liveness flag shared by an object and the closures it queues
  /// to the main thread or hands to worker threads. Such a closure can run
  /// after the object is freed, so it tests the flag (kept alive by the
  /// closure) before touching any field of the object.</summary>
  ILifeFlag = interface
    ['{9D2B6E41-5A07-4C38-B1F6-0E83A7D4C259}']
    function GetAlive: Boolean;
    procedure SetAlive(AValue: Boolean);
    property Alive: Boolean read GetAlive write SetAlive;
  end;

  IJobCancelToken = interface
    ['{C3E1A7D0-2F4B-4A9E-9C11-6B0E8D2A1F40}']
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

  TVfsListCallback = reference to procedure(const AItems: TArray<TVfsEntry>;
    const AError: TVfsError);
  TVfsBoolCallback = reference to procedure(const ASuccess: Boolean; const AError: TVfsError);
  TVfsTextCallback = reference to procedure(const AText: string;
    AEncoding: TTextFileEncoding; const AError: TVfsError);
  TVfsBytesCallback = reference to procedure(const ABytes: TBytes;
    const AError: TVfsError);
  /// <summary>ADone/ATotal: cumulative progress for the whole operation (a
  /// recursive tree copy reports running totals across all its files here).
  /// AItemDone/AItemTotal: byte progress of the single file currently being
  /// transferred (0/0 when no per-file breakdown is available, e.g. archive
  /// pack/unpack). AItemSrcPath/AItemDstPath: full paths of that file ('' when
  /// unavailable) - lets the UI show which file is in flight inside a tree,
  /// not just the top-level source/destination.</summary>
  TVfsProgressCallback = reference to procedure(const ADone, ATotal: Int64;
    const ACurrentName: string; const AItemDone, AItemTotal: Int64;
    const AItemSrcPath, AItemDstPath: string);
  /// <summary>Async existence probe - AIsDirectory meaningful only when AExists.</summary>
  TVfsExistsCallback = reference to procedure(const AExists: Boolean;
    const AIsDirectory: Boolean; const AError: TVfsError);
  TVfsFreeSpaceCallback = reference to procedure(const AFree, ATotal: Int64;
    const AError: TVfsError);

  IVirtualFileSystem = interface
    ['{B18C8B56-B101-44B9-A23F-2621C11F490B}']
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
    // Whole-file text load/save for small Editor buffers.
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

  TJobCancelToken = class(TInterfacedObject, IJobCancelToken)
  private
    FCancelled: Integer; // 0/1 - written from UI, read from workers
  public
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

/// <summary>True when token is assigned and cancellation was requested.</summary>
function JobCancelRequested(const ACancel: IJobCancelToken): Boolean;

function FileUriToPath(const AURI: string): string;
function PathToFileUri(const APath: string): string;
function ParentFileUri(const AURI: string): string;
function FileUriTitle(const AURI: string): string;
function JoinFileUri(const ADirURI, AName: string): string;
function IsFileUriDriveRoot(const AURI: string): Boolean;
// Win32-accurate checks: Delphi DirectoryExists is False for some junctions
// (e.g. C:\Documents and Settings) even when GetFileAttributes sees a directory.
function LocalPathIsDirectory(const APath: string): Boolean;
function LocalPathIsFile(const APath: string): Boolean;
/// <summary>APath as it must be passed to a Win32 / RTL file call: absolute
/// paths of 248+ chars (CreateDirectory's limit, the strictest of MAX_PATH's)
/// get the \\?\ (\\?\UNC\) prefix so they work without longPathAware /
/// LongPathsEnabled; anything shorter, relative or already prefixed is
/// returned unchanged. Apply at the call site only - keep logic, URIs and
/// messages on the plain path. Not for Shell APIs (SHFileOperation,
/// IFileOperation, ShellExecute): they reject the prefix.</summary>
function WinApiPath(const APath: string): string;
/// <summary>TPath.GetFileName that also accepts a name with control
/// characters (valid on Linux, and on NTFS volumes mounted there), where TPath
/// raises.</summary>
function SafeFileName(const APath: string): string;
/// <summary>TPath.GetExtension with the same tolerance.</summary>
function SafeExtension(const APath: string): string;
/// <summary>TPath.GetDirectoryName with the same tolerance.</summary>
function SafeDirectoryName(const APath: string): string;
/// <summary>TPath.Combine that also accepts a name with control characters
/// (valid on Linux), where TPath raises.</summary>
function SafeCombinePath(const ADir, AName: string): string;
function DriveLetterOf(const APath: string): Char;
/// <summary>Local paths compare case-insensitively on Windows, exactly
/// elsewhere.</summary>
function SameLocalPath(const A, B: string): Boolean;
/// <summary>Dictionary key for a local path: lower-cased on Windows, as is
/// elsewhere.</summary>
function LocalPathKey(const APath: string): string;
/// <summary>Root of a local path: the drive ("C:") or UNC share on Windows,
/// "/" on Posix systems; '' for a relative path.</summary>
function LocalPathRootOf(const APath: string): string;
/// <summary>True for a path that starts at a root of the local file system
/// (drive path or UNC share on Windows, leading "/" elsewhere).</summary>
function IsLocalAbsolutePath(const APath: string): Boolean;
/// <summary>Absolute, delimiter-normalized local path. Safe on an
/// unresponsive network drive: a bare drive letter or an already-rooted
/// drive path ("P:", "P:\") is resolved from pure string logic, never via
/// GetFullPathName -- which, for a bare drive letter specifically, resolves
/// relative to that drive's own per-process current directory and can block
/// for a long time if the drive isn't answering. Any other path still goes
/// through TPath.GetFullPath as before.</summary>
function NormalizeLocalPath(const APath: string): string;
// Follow directory junction/symlink to its final path when possible.
function ResolveLocalDirPath(const APath: string): string;
function ResolveFileUri(const AURI: string): string;

/// <summary>True if URI contains archive mount marker '!/'.</summary>
function HasArchiveChain(const AURI: string): Boolean;
/// <summary>
/// Split file:///.../a.zip!/inner.zip!/path into base file URI and inner segments
/// (empty last segment = archive layer root).
/// </summary>
function SplitArchiveUri(const AURI: string; out ABaseFileUri: string;
  out ASegments: TArray<string>): Boolean;
function ArchiveBasePath(const AURI: string): string;
function ArchiveBaseDirUri(const AURI: string): string;
function SameVfsUri(const A, B: string): Boolean;
/// <summary>Normalized form of AURI: SameVfsUri(A, B) holds exactly when
/// VfsUriKey(A) = VfsUriKey(B) (except URIs SameVfsUri never matches, such
/// as a Find URI without a session id - those key to themselves). Lets hot
/// loops compare against many URIs by hashing/sorting instead of O(N*M)
/// SameVfsUri calls.</summary>
function VfsUriKey(const AURI: string): string;
/// <summary>A new flag, already set to alive.</summary>
function NewLifeFlag: ILifeFlag;
function JoinVfsUri(const ADirURI, AName: string): string;
function ParentVfsUri(const AURI: string): string;
function VfsUriTitle(const AURI: string): string;
/// <summary>Panel-tab caption for a filesystem directory: drive letter +
/// full current path (e.g. 'C:\Users\me\Documents'), truncated in the
/// middle - not at an edge - to fit AMaxLen, e.g. 'C:\...\Documents', so the
/// drive and the current folder name stay visible. Falls back to
/// VfsUriTitle's short form for drive roots, archives, Find and System
/// Folders, where a full path isn't meaningful.</summary>
function VfsUriDirTabTitle(const AURI: string; AMaxLen: Integer): string;
function ResolveVfsUri(const AURI: string): string;
function IsVfsUriNavigationRoot(const AURI: string): Boolean;
function EnsureArchiveRootUri(const AZipFileUri: string): string;
function IsZipFileName(const AName: string): Boolean;
/// <summary>The local file starts like a ZIP archive, whatever its name
/// (docx, xlsx, odt, jar are ZIP inside).</summary>
function FileHasZipSignature(const APath: string): Boolean;
/// <summary>APath is a 7z archive for packing: named .7z, or an existing local
/// file that starts with the 7z signature under any other name.</summary>
function IsSevenZipArchivePath(const APath: string): Boolean;
function IsSevenZipFileName(const AName: string): Boolean;
function IsSevenZipUri(const AURI: string): Boolean;
function IsZipArchiveUri(const AURI: string): Boolean;
/// <summary>"&lt;scheme&gt;:///&lt;path&gt;!/" - root of the archive file AArchivePath
/// as served by the plugin owning AScheme. '' when either part is empty.</summary>
function PathToArchiveRootUri(const AScheme, AArchivePath: string): string;
function PathToSevenZipRootUri(const AArchivePath: string): string;
/// <summary>The same entry of an on-disk ZIP addressed through the 7z://
/// backend (file:///C:/a.zip!/dir/f.txt -> 7z:///C:/a.zip!/dir/f.txt). The
/// built-in ZIP layer cannot decrypt AES or unpack some methods; 7z.dll can.
/// '' for anything that is not an entry one level deep in a local ZIP.</summary>
function ZipEntryToSevenZipUri(const AEntryUri: string): string;
function ArchiveBaseLocalPath(const ABaseUri: string): string;
function IsFindUri(const AURI: string): Boolean;
function IsSystemFoldersUri(const AURI: string): Boolean;
function IsRecycleBinUri(const AURI: string): Boolean;
function IsTmpPanelUri(const AURI: string): Boolean;
function IsWorkspaceUri(const AURI: string): Boolean;
function WorkspaceInnerPath(const AURI: string): string;
function MakeWorkspaceUri(const AInner: string): string;
/// <summary>sftp://user@host:port/remote/path -- Authority is "user@host:port"
/// (or "user@host"/"host" if port/user absent), Path is always POSIX-absolute
/// ("/" for root, no trailing slash otherwise). See uSftpVfs.pas.</summary>
function IsSftpUri(const AURI: string): Boolean;
function SftpAuthorityOf(const AURI: string): string;
function SftpRemotePathOf(const AURI: string): string;
function MakeSftpUri(const AAuthority, ARemotePath: string): string;
/// <summary>A URI of a scheme this unit has no rules for, written
/// scheme://authority/path: the scheme of a plugin that serves a folder tree
/// (net://work/dir/a.txt, net:///). The path is POSIX-style, absolute and not
/// percent-encoded; an empty authority names the scheme's root (net:///).
/// URIs with an archive chain (!/) are never generic.</summary>
function IsGenericVfsUri(const AURI: string): Boolean;
function GenericVfsSchemeOf(const AURI: string): string;
function GenericVfsAuthorityOf(const AURI: string): string;
/// <summary>The path of a generic URI: '/' for a root, otherwise starting
/// with '/' and without a trailing one.</summary>
function GenericVfsPathOf(const AURI: string): string;
function MakeGenericVfsUri(const AScheme, AAuthority, APath: string): string;
/// <summary>recycle:// wraps a real filesystem path (the Recycle Bin
/// item's underlying $R<random> path) with the same URI grammar as
/// file:// - these just swap the scheme prefix onto/off FileUriToPath /
/// PathToFileUri rather than duplicating that codec.</summary>
function RecyclePathToUri(const APath: string): string;
function RecycleUriToPath(const AURI: string): string;
function MakeFindSessionUri(const ASessionId: string): string;
function FindSessionIdFromUri(const AURI: string): string;
/// <summary>FAR-style fixed Attr column: RHSAL each letter or '-'.</summary>
function FormatVfsAttrText(AReadOnly, AHidden, ASystem, AArchive,
  ALink: Boolean): string; overload;
function FormatVfsAttrText(const AEntry: TVfsEntry): string; overload;

implementation

uses
  System.StrUtils, System.Math, uCharWidth, uPlatformPaths;

class function TVfsError.Ok: TVfsError;
begin
  Result.Code := vecOk;
  Result.Message := '';
  Result.URI := '';
end;

class function TVfsError.Make(ACode: TVfsErrorCode; const AMessage, AURI: string): TVfsError;
begin
  Result.Code := ACode;
  Result.Message := AMessage;
  Result.URI := AURI;
end;

function TJobCancelToken.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TJobCancelToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function JobCancelRequested(const ACancel: IJobCancelToken): Boolean;
begin
  Result := Assigned(ACancel) and ACancel.IsCancellationRequested;
end;

function IsWindowsDriveRoot(const APath: string): Boolean;
var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(APath);
  Result := (Length(P) = 2) and (UpCase(P[1]) >= 'A') and (UpCase(P[1]) <= 'Z') and
    (P[2] = ':');
end;

// The root of the local file system: a drive root on Windows, "/" elsewhere.
function IsLocalRoot(const APath: string): Boolean;
begin
  if PlatformPosixPaths then
    Result := APath = '/'
  else
    Result := IsWindowsDriveRoot(APath);
end;

// Local paths compare case-insensitively on Windows, exactly elsewhere.
function SameLocalPath(const A, B: string): Boolean;
begin
  if PlatformPosixPaths then
    Result := A = B
  else
    Result := SameText(A, B);
end;

function HasRtlInvalidPathChars(const S: string): Boolean;
var
  C: Char;
begin
  // The characters System.IOUtils.TPath refuses in a path: control characters
  // everywhere, plus the quote, angle brackets and bar on Windows (cloud-drive
  // volumes show such names).
  for C in S do
    if (Ord(C) < 32) or
       (not PlatformPosixPaths and ((C = '"') or (C = '<') or (C = '>') or (C = '|'))) then
      Exit(True);
  Result := False;
end;

function LocalPathKey(const APath: string): string;
begin
  if PlatformPosixPaths then
    Result := APath
  else
    Result := LowerCase(APath);
end;

function DriveRootPath(const ADriveLetter: Char): string;
begin
  Result := UpCase(ADriveLetter) + ':' + PathDelim;
end;

function NormalizeLocalPath(const APath: string): string;
var
  P: string;
begin
  // TPath.GetFullPath raises on control characters, valid in a Linux name and
  // in names on cloud-drive volumes; such a path is kept as is (Trim would eat
  // a trailing line feed that belongs to the name).
  if HasRtlInvalidPathChars(APath) then
  begin
    Result := ExpandFileName(APath);
    if Length(Result) > 1 then
      Result := ExcludeTrailingPathDelimiter(Result);
    Exit;
  end;
  P := Trim(APath);
  if P = '' then
    Exit('');
  if PlatformPosixPaths then
  begin
    Result := TPath.GetFullPath(P);
    if Length(Result) > 1 then
      Result := ExcludeTrailingPathDelimiter(Result);
    Exit;
  end;
  // Bare "C:" means current-dir-on-drive in Windows APIs - force true root.
  if (Length(P) = 2) and (P[2] = ':') and (UpCase(P[1]) >= 'A') and (UpCase(P[1]) <= 'Z') then
    Exit(DriveRootPath(P[1]));
  if IsWindowsDriveRoot(P) then
    Exit(DriveRootPath(P[1]));
  Result := TPath.GetFullPath(P);
  if IsWindowsDriveRoot(Result) then
    Result := DriveRootPath(Result[1])
  else
    Result := ExcludeTrailingPathDelimiter(Result);
end;

function HexNibble(AValue: Integer): Char;
begin
  if AValue < 10 then
    Result := Char(Ord('0') + AValue)
  else
    Result := Char(Ord('A') + AValue - 10);
end;

function PercentEncodeByte(AByte: Byte): string;
begin
  Result := '%' + HexNibble(AByte shr 4) + HexNibble(AByte and $F);
end;

function NeedsFileUriEscape(C: Char): Boolean;
begin
  // Keep RFC 3986 unreserved + path separators and drive colon.
  Result := not (
    ((C >= 'A') and (C <= 'Z')) or
    ((C >= 'a') and (C <= 'z')) or
    ((C >= '0') and (C <= '9')) or
    (C = '-') or (C = '_') or (C = '.') or (C = '~') or
    (C = '/') or (C = ':'));
end;

function EncodeFileUriPath(const ASlashPath: string): string;
var
  I: Integer;
  C: Char;
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  I := 1;
  while I <= Length(ASlashPath) do
  begin
    C := ASlashPath[I];
    if not NeedsFileUriEscape(C) then
      Result := Result + C
    else
    begin
      Bytes := TEncoding.UTF8.GetBytes(string(C));
      for B in Bytes do
        Result := Result + PercentEncodeByte(B);
    end;
    Inc(I);
  end;
end;

function DecodeFileUriPath(const APathPart: string): string;
var
  I, L, Code: Integer;
  Bytes: TList<Byte>;
  Chunk: TBytes;
begin
  // Percent-decode only. Do NOT treat '+' as space (form-urlencoded) -
  // folder names like "Update 1 + Keygen" must stay intact.
  Result := '';
  Bytes := TList<Byte>.Create;
  try
    I := 1;
    L := Length(APathPart);
    while I <= L do
    begin
      if (APathPart[I] = '%') and (I + 2 <= L) and
         CharInSet(APathPart[I + 1], ['0'..'9', 'A'..'F', 'a'..'f']) and
         CharInSet(APathPart[I + 2], ['0'..'9', 'A'..'F', 'a'..'f']) then
      begin
        Code := StrToInt('$' + Copy(APathPart, I + 1, 2));
        Bytes.Add(Byte(Code));
        Inc(I, 3);
      end
      else
      begin
        // Flush pending UTF-8 bytes before appending a raw char.
        if Bytes.Count > 0 then
        begin
          Chunk := Bytes.ToArray;
          Result := Result + TEncoding.UTF8.GetString(Chunk);
          Bytes.Clear;
        end;
        Result := Result + APathPart[I];
        Inc(I);
      end;
    end;
    if Bytes.Count > 0 then
    begin
      Chunk := Bytes.ToArray;
      Result := Result + TEncoding.UTF8.GetString(Chunk);
    end;
  finally
    Bytes.Free;
  end;
end;

function StripExtendedPathPrefix(const APath: string): string;
begin
  if APath.StartsWith('\\?\UNC\', True) then
    // \\?\UNC\server\share -> \\server\share
    Result := '\\' + Copy(APath, Length('\\?\UNC\') + 1, MaxInt)
  else if APath.StartsWith('\\?\', True) then
    Result := Copy(APath, Length('\\?\') + 1, MaxInt)
  else
    Result := APath;
end;

function IsUncPath(const APath: string): Boolean;
begin
  Result := (Length(APath) >= 2) and (APath[1] = '\') and (APath[2] = '\');
end;

function WinApiPath(const APath: string): string;
const
  cMaxPath = 260;
  cLongPathThreshold = cMaxPath - 12;
begin
  Result := APath;
  if PlatformPosixPaths then
    Exit;
  if (Length(Result) < cLongPathThreshold) or Result.StartsWith('\\?\') or
     Result.StartsWith('\\.\') then
    Exit;
  // \\?\ turns off Win32 path normalization, so hand it backslashes only.
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  if (Length(Result) >= 3) and CharInSet(UpCase(Result[1]), ['A'..'Z']) and
     (Result[2] = ':') and (Result[3] = '\') then
    Result := '\\?\' + Result
  else if IsUncPath(Result) then
    Result := '\\?\UNC\' + Copy(Result, 3, MaxInt)
  else
    Result := APath; // relative: leave to normal Win32 resolution
end;

function LocalPathIsDirectory(const APath: string): Boolean;
var
  P: string;
begin
  P := NormalizeLocalPath(APath);
  if P = '' then
    Exit(False);
  Result := PlatformIsDirectory(WinApiPath(P));
end;

function LocalPathIsFile(const APath: string): Boolean;
var
  P: string;
begin
  P := NormalizeLocalPath(APath);
  if P = '' then
    Exit(False);
  Result := PlatformIsFile(WinApiPath(P));
end;

function LastPathSeparator(const S: string): Integer;
begin
  Result := Length(S);
  while (Result > 0) and (S[Result] <> '/') and
        (PlatformPosixPaths or (S[Result] <> PathDelim)) do
    Dec(Result);
end;

function SafeFileName(const APath: string): string;
begin
  if not HasRtlInvalidPathChars(APath) then
    Exit(TPath.GetFileName(APath));
  Result := Copy(APath, LastPathSeparator(APath) + 1, MaxInt);
end;

function SafeExtension(const APath: string): string;
var
  Name: string;
  I: Integer;
begin
  if not HasRtlInvalidPathChars(APath) then
    Exit(TPath.GetExtension(APath));
  Name := SafeFileName(APath);
  I := Length(Name);
  while (I > 0) and (Name[I] <> '.') do
    Dec(I);
  if I > 0 then
    Result := Copy(Name, I, MaxInt)
  else
    Result := '';
end;

function SafeDirectoryName(const APath: string): string;
var
  I: Integer;
begin
  // TPath.GetDirectoryName raises on an empty path; a virtual URI (sys://, tmp://)
  // has no local path and so no directory.
  if Trim(APath) = '' then
    Exit('');
  if not HasRtlInvalidPathChars(APath) then
    Exit(TPath.GetDirectoryName(APath));
  I := LastPathSeparator(APath);
  if I <= 1 then
    Result := Copy(APath, 1, I)
  else
    Result := Copy(APath, 1, I - 1);
end;

function SafeCombinePath(const ADir, AName: string): string;
begin
  if not (HasRtlInvalidPathChars(ADir) or HasRtlInvalidPathChars(AName)) then
    Exit(TPath.Combine(ADir, AName));
  if (ADir = '') or (AName = '') then
    Exit(ADir + AName);
  if (AName[1] = '/') or (not PlatformPosixPaths and (AName[1] = PathDelim)) then
    Exit(AName);
  if (ADir[Length(ADir)] = '/') or (ADir[Length(ADir)] = PathDelim) then
    Result := ADir + AName
  else
    Result := ADir + PathDelim + AName;
end;

function DriveLetterOf(const APath: string): Char;
var
  P: string;
begin
  P := NormalizeLocalPath(APath);
  if (Length(P) >= 2) and (P[2] = ':') and
     (UpCase(P[1]) >= 'A') and (UpCase(P[1]) <= 'Z') then
    Result := UpCase(P[1])
  else
    Result := #0;
end;

function LocalPathRootOf(const APath: string): string;
begin
  if PlatformPosixPaths then
  begin
    if APath.StartsWith('/') then
      Result := '/'
    else
      Result := '';
  end
  else
    Result := ExtractFileDrive(APath);
end;

function IsLocalAbsolutePath(const APath: string): Boolean;
begin
  if PlatformPosixPaths then
    Result := APath.StartsWith('/')
  else
    Result := ((Length(APath) >= 3) and (APath[2] = ':') and (APath[3] = '\')) or
      APath.StartsWith('\\');
end;

function ResolveLocalDirPath(const APath: string): string;
var
  P: string;
  FinalPath: string;
  OrigDrive, FinalDrive: Char;
begin
  P := NormalizeLocalPath(APath);
  Result := P;
  if P = '' then
    Exit;
  // A drive root can't be a symlink/junction, so there's nothing to resolve
  // -- skip straight past every synchronous Win32 call below before even
  // touching the filesystem. LocalPathIsDirectory/CreateFile/
  // GetFinalPathNameByHandle all block for as long as an unresponsive
  // network drive takes to answer (which can be a very long time), and this
  // function runs on the UI thread: it's the first thing NavigateSideTo does
  // (via ResolveVfsUri/ResolveFileUri), on every single navigation --
  // including Change Drive and Ctrl+Left/Right, which always target a drive
  // root. (Keeping mapped drive roots as letters also keeps URI round-trip
  // working: expanding one via GetFinalPathName yields UNC, which fails with
  // "Path not found".)
  if IsWindowsDriveRoot(P) then
    Exit;
  if not LocalPathIsDirectory(P) then
    Exit;
  // Follow junction/symlink (Documents and Settings -> C:\Users).
  FinalPath := PlatformFinalDirPath(WinApiPath(P));
  if FinalPath = '' then
    Exit;
  FinalPath := StripExtendedPathPrefix(FinalPath);
  FinalPath := NormalizeLocalPath(FinalPath);
  if (FinalPath = '') or not LocalPathIsDirectory(FinalPath) then
    Exit;
  // SUBST / mapped drives: GetFinalPathName jumps to another letter or UNC
  // (P:\Folder -> D:\Real\Folder). Keeping that URI makes the panel leave the
  // drive root, so ".." appears after going up - stay on the original drive.
  OrigDrive := DriveLetterOf(P);
  if OrigDrive <> #0 then
  begin
    FinalDrive := DriveLetterOf(FinalPath);
    if (FinalDrive = #0) or (FinalDrive <> OrigDrive) then
      Exit;
  end;
  Result := FinalPath;
end;

function ResolveFileUri(const AURI: string): string;
begin
  Result := PathToFileUri(ResolveLocalDirPath(FileUriToPath(AURI)));
end;

function FileUriToPath(const AURI: string): string;
var
  S, PathPart, Host, Rest: string;
  P: Integer;
begin
  S := Trim(AURI);
  if not S.StartsWith('file:', True) then
  begin
    // tmp:///, 7z:///, sys://... are VFS URIs, not local paths. Treating them as
    // relative names (GetFullPath) made Copy's dest dialog retarget to disk.
    if Pos('://', S) > 0 then
      Exit('');
    Exit(NormalizeLocalPath(S));
  end;

  if PlatformPosixPaths then
  begin
    // file:///path, file://localhost/path, file:/path
    if S.StartsWith('file://', True) then
      PathPart := Copy(S, Length('file://') + 1, MaxInt)
    else
      PathPart := Copy(S, Length('file:') + 1, MaxInt);
    if (PathPart <> '') and (PathPart[1] <> '/') then
    begin
      P := Pos('/', PathPart);
      if P = 0 then
        Exit('');
      Host := DecodeFileUriPath(Copy(PathPart, 1, P - 1));
      if not SameText(Host, 'localhost') then
        Exit('');
      PathPart := Copy(PathPart, P, MaxInt);
    end;
    while PathPart.StartsWith('//') do
      Delete(PathPart, 1, 1);
    PathPart := DecodeFileUriPath(PathPart);
    if PathPart = '' then
      Exit('');
    Exit(NormalizeLocalPath(PathPart));
  end;

  // Legacy / mistaken form: file:////server/share
  if S.StartsWith('file:////', True) then
  begin
    PathPart := Copy(S, Length('file:////') + 1, MaxInt);
    PathPart := DecodeFileUriPath(PathPart);
    PathPart := StringReplace(PathPart, '/', PathDelim, [rfReplaceAll]);
    Exit(NormalizeLocalPath('\\' + PathPart));
  end;

  // file:///C:/x  - local absolute path (three slashes)
  if S.StartsWith('file:///', True) then
  begin
    PathPart := Copy(S, Length('file:///') + 1, MaxInt);
    PathPart := DecodeFileUriPath(PathPart);
    PathPart := StringReplace(PathPart, '/', PathDelim, [rfReplaceAll]);
    Exit(NormalizeLocalPath(PathPart));
  end;

  // file://server/share/path  or  file://localhost/C:/x
  if S.StartsWith('file://', True) then
  begin
    PathPart := Copy(S, Length('file://') + 1, MaxInt);
    P := Pos('/', PathPart);
    if P = 0 then
    begin
      Host := DecodeFileUriPath(PathPart);
      if (Host = '') or SameText(Host, 'localhost') then
        Exit('');
      Exit(NormalizeLocalPath('\\' + Host));
    end;
    Host := DecodeFileUriPath(Copy(PathPart, 1, P - 1));
    Rest := DecodeFileUriPath(Copy(PathPart, P + 1, MaxInt));
    Rest := StringReplace(Rest, '/', PathDelim, [rfReplaceAll]);
    if (Host = '') or SameText(Host, 'localhost') then
      Exit(NormalizeLocalPath(Rest));
    Exit(NormalizeLocalPath('\\' + Host + PathDelim + Rest));
  end;

  if S.StartsWith('file:/', True) then
  begin
    PathPart := Copy(S, Length('file:/') + 1, MaxInt);
    PathPart := DecodeFileUriPath(PathPart);
    PathPart := StringReplace(PathPart, '/', PathDelim, [rfReplaceAll]);
    Exit(NormalizeLocalPath(PathPart));
  end;

  Result := '';
end;

function PathToFileUri(const APath: string): string;
var
  Full, Slash: string;
begin
  Full := NormalizeLocalPath(APath);
  if Full = '' then
    Full := APath;
  if PlatformPosixPaths then
    // file:///home/user; the root is file:///
    Exit('file://' + EncodeFileUriPath(Full));
  if IsWindowsDriveRoot(Full) then
    // Canonical drive root URI: file:///C:/
    Result := 'file:///' + UpCase(Full[1]) + ':/'
  else if IsUncPath(Full) then
  begin
    // \\server\share\dir -> file://server/share/dir
    Full := ExcludeTrailingPathDelimiter(Full);
    Slash := Copy(Full, 3, MaxInt);
    Slash := StringReplace(Slash, PathDelim, '/', [rfReplaceAll]);
    Slash := EncodeFileUriPath(Slash);
    Result := 'file://' + Slash;
  end
  else
  begin
    Full := ExcludeTrailingPathDelimiter(Full);
    Slash := StringReplace(Full, PathDelim, '/', [rfReplaceAll]);
    Slash := EncodeFileUriPath(Slash);
    if (Length(Slash) >= 2) and (Slash[2] = ':') then
      Result := 'file:///' + Slash
    else
      Result := 'file:///' + Slash;
  end;
end;

function ParentFileUri(const AURI: string): string;
begin
  Result := ParentVfsUri(AURI);
end;

function FileUriTitle(const AURI: string): string;
begin
  Result := VfsUriTitle(AURI);
end;

function JoinFileUri(const ADirURI, AName: string): string;
begin
  Result := JoinVfsUri(ADirURI, AName);
end;

function IsFileUriDriveRoot(const AURI: string): Boolean;
begin
  Result := IsVfsUriNavigationRoot(AURI);
end;

function HasArchiveChain(const AURI: string): Boolean;
begin
  Result := Pos('!/', AURI) > 0;
end;

function NormalizeInnerSeg(const ASeg: string): string;
begin
  Result := StringReplace(ASeg, '\', '/', [rfReplaceAll]);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function SplitArchiveUri(const AURI: string; out ABaseFileUri: string;
  out ASegments: TArray<string>): Boolean;
var
  S, Rest, Part: string;
  P, N: Integer;
begin
  Result := False;
  ABaseFileUri := '';
  SetLength(ASegments, 0);
  S := Trim(AURI);
  P := Pos('!/', S);
  if P <= 0 then
    Exit;
  ABaseFileUri := Copy(S, 1, P - 1);
  Rest := Copy(S, P + 2, MaxInt); // after '!/'
  // Collect segments separated by '!/'
  N := 0;
  while Rest <> '' do
  begin
    P := Pos('!/', Rest);
    if P = 0 then
    begin
      Part := Rest;
      Rest := '';
    end
    else
    begin
      Part := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 2, MaxInt);
    end;
    Inc(N);
    SetLength(ASegments, N);
    ASegments[N - 1] := NormalizeInnerSeg(Part);
  end;
  // Trailing '!/' yields an empty final segment (archive layer root),
  // unless the last collected segment is already empty.
  if (Length(S) >= 2) and (Copy(S, Length(S) - 1, 2) = '!/') then
  begin
    if (Length(ASegments) = 0) or (ASegments[High(ASegments)] <> '') then
    begin
      Inc(N);
      SetLength(ASegments, N);
      ASegments[N - 1] := '';
    end;
  end
  else if Length(ASegments) = 0 then
  begin
    SetLength(ASegments, 1);
    ASegments[0] := '';
  end;
  Result := ABaseFileUri <> '';
end;

function ArchiveBasePath(const AURI: string): string;
var
  Base: string;
  Segs: TArray<string>;
begin
  if SplitArchiveUri(AURI, Base, Segs) then
    Result := ArchiveBaseLocalPath(Base)
  else if IsSevenZipUri(AURI) then
    Result := ArchiveBaseLocalPath(AURI)
  else
    Result := FileUriToPath(AURI);
end;

function ArchiveBaseDirUri(const AURI: string): string;
var
  Base: string;
  Segs: TArray<string>;
  Path, Parent: string;
begin
  if SplitArchiveUri(AURI, Base, Segs) then
  begin
    Path := ArchiveBaseLocalPath(Base);
    if Path = '' then
      Exit('');
    Parent := SafeDirectoryName(ExcludeTrailingPathDelimiter(Path));
    if Parent = '' then
      Result := PathToFileUri(Path)
    else
      Result := PathToFileUri(Parent);
  end
  else
    Result := AURI;
end;

function SameVfsUri(const A, B: string): Boolean;
var
  BaseA, BaseB: string;
  SegA, SegB: TArray<string>;
  I: Integer;
  IdA, IdB: string;
begin
  if IsFindUri(A) or IsFindUri(B) then
  begin
    if not (IsFindUri(A) and IsFindUri(B)) then
      Exit(False);
    IdA := FindSessionIdFromUri(A);
    IdB := FindSessionIdFromUri(B);
    Exit((IdA <> '') and SameText(IdA, IdB));
  end;
  if IsRecycleBinUri(A) or IsRecycleBinUri(B) then
  begin
    if not (IsRecycleBinUri(A) and IsRecycleBinUri(B)) then
      Exit(False);
    Exit(SameText(RecycleUriToPath(A), RecycleUriToPath(B)));
  end;
  if IsTmpPanelUri(A) or IsTmpPanelUri(B) then
    Exit(IsTmpPanelUri(A) and IsTmpPanelUri(B));
  if IsWorkspaceUri(A) or IsWorkspaceUri(B) then
    Exit(IsWorkspaceUri(A) and IsWorkspaceUri(B) and
      SameText(WorkspaceInnerPath(A), WorkspaceInnerPath(B)));
  if IsSftpUri(A) or IsSftpUri(B) then
    Exit(IsSftpUri(A) and IsSftpUri(B) and
      SameText(SftpAuthorityOf(A), SftpAuthorityOf(B)) and
      SameText(SftpRemotePathOf(A), SftpRemotePathOf(B)));
  if IsSystemFoldersUri(A) or IsSystemFoldersUri(B) then
    Exit(IsSystemFoldersUri(A) and IsSystemFoldersUri(B));
  if IsGenericVfsUri(A) or IsGenericVfsUri(B) then
    Exit(IsGenericVfsUri(A) and IsGenericVfsUri(B) and
      SameText(GenericVfsSchemeOf(A), GenericVfsSchemeOf(B)) and
      SameText(GenericVfsAuthorityOf(A), GenericVfsAuthorityOf(B)) and
      SameText(GenericVfsPathOf(A), GenericVfsPathOf(B)));
  if not HasArchiveChain(A) and not HasArchiveChain(B) then
    Exit(SameLocalPath(FileUriToPath(A), FileUriToPath(B)));
  if not SplitArchiveUri(A, BaseA, SegA) then
    Exit(False);
  if not SplitArchiveUri(B, BaseB, SegB) then
    Exit(False);
  if not SameLocalPath(ArchiveBaseLocalPath(BaseA), ArchiveBaseLocalPath(BaseB)) then
    Exit(False);
  if Length(SegA) <> Length(SegB) then
    Exit(False);
  for I := 0 to High(SegA) do
    if not SameText(SegA[I], SegB[I]) then
      Exit(False);
  Result := True;
end;

function VfsUriKey(const AURI: string): string;
var
  Base, Id: string;
  Segs: TArray<string>;
  I: Integer;
begin
  // Branch order and folding mirror SameVfsUri (SameText = ASCII-only
  // case-insensitive, same as LowerCase). #0 separates parts; #1 marks URIs
  // SameVfsUri never equates with anything.
  if IsFindUri(AURI) then
  begin
    Id := FindSessionIdFromUri(AURI);
    if Id = '' then
      Exit(#1 + AURI);
    Exit('find'#0 + LowerCase(Id));
  end;
  if IsRecycleBinUri(AURI) then
    Exit('rb'#0 + LowerCase(RecycleUriToPath(AURI)));
  if IsTmpPanelUri(AURI) then
    Exit('tmp'#0);
  if IsWorkspaceUri(AURI) then
    Exit('ws'#0 + LowerCase(WorkspaceInnerPath(AURI)));
  if IsSftpUri(AURI) then
    Exit('sftp'#0 + LowerCase(SftpAuthorityOf(AURI)) + #0 +
      LowerCase(SftpRemotePathOf(AURI)));
  if IsSystemFoldersUri(AURI) then
    Exit('sys'#0);
  if IsGenericVfsUri(AURI) then
    Exit('gen'#0 + GenericVfsSchemeOf(AURI) + #0 +
      LowerCase(GenericVfsAuthorityOf(AURI)) + #0 + LowerCase(GenericVfsPathOf(AURI)));
  if not HasArchiveChain(AURI) then
    Exit('file'#0 + LocalPathKey(FileUriToPath(AURI)));
  if not SplitArchiveUri(AURI, Base, Segs) then
    Exit(#1 + AURI);
  Result := 'arc'#0 + LocalPathKey(ArchiveBaseLocalPath(Base)) + #0 +
    IntToStr(Length(Segs));
  for I := 0 to High(Segs) do
    Result := Result + #0 + LowerCase(Segs[I]);
end;

function IsZipFileName(const AName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(SafeExtension(AName));
  Result := (Ext = '.zip') or (Ext = '.jar') or (Ext = '.apk');
end;

function FileHasZipSignature(const APath: string): Boolean;
var
  S: TFileStream;
  Sig: array[0..3] of Byte;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  try
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if S.Read(Sig, SizeOf(Sig)) <> SizeOf(Sig) then
        Exit;
    finally
      S.Free;
    end;
  except
    Exit;
  end;
  // PK 03 04: a local file header; PK 05 06: an empty archive.
  Result := (Sig[0] = $50) and (Sig[1] = $4B) and
    (((Sig[2] = 3) and (Sig[3] = 4)) or ((Sig[2] = 5) and (Sig[3] = 6)));
end;

function IsSevenZipArchivePath(const APath: string): Boolean;
var
  S: TFileStream;
  Sig: array[0..5] of Byte;
begin
  if SameText(ExtractFileExt(APath), '.7z') then
    Exit(True);
  Result := False;
  if (APath = '') or SameText(ExtractFileExt(APath), '.zip') or not TFile.Exists(APath) then
    Exit;
  try
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if S.Read(Sig, SizeOf(Sig)) <> SizeOf(Sig) then
        Exit;
    finally
      S.Free;
    end;
  except
    Exit;
  end;
  Result := (Sig[0] = $37) and (Sig[1] = $7A) and (Sig[2] = $BC) and
    (Sig[3] = $AF) and (Sig[4] = $27) and (Sig[5] = $1C);
end;

function IsSevenZipFileName(const AName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(SafeExtension(AName));
  Result := (Ext = '.7z') or (Ext = '.rar') or (Ext = '.tar') or
    (Ext = '.gz') or (Ext = '.tgz') or (Ext = '.bz2') or (Ext = '.xz') or
    (Ext = '.iso') or (Ext = '.cab') or (Ext = '.wim');
end;

function IsSevenZipUri(const AURI: string): Boolean;
var
  S: string;
  P: Integer;
begin
  S := Trim(AURI);
  P := Pos('://', S);
  Result := (P > 1) and SameText(Copy(S, 1, P - 1), '7z');
end;

function ArchiveBaseLocalPath(const ABaseUri: string): string;
var
  S: string;
begin
  S := Trim(ABaseUri);
  if PlatformPosixPaths and S.StartsWith('7z://', True) then
    Exit(NormalizeLocalPath(Copy(S, Length('7z://') + 1, MaxInt)));
  if S.StartsWith('7z:///', True) then
  begin
    S := Copy(S, Length('7z:///') + 1, MaxInt);
    S := StringReplace(S, '/', PathDelim, [rfReplaceAll]);
    Exit(NormalizeLocalPath(S));
  end;
  if S.StartsWith('7z://', True) then
  begin
    S := Copy(S, Length('7z://') + 1, MaxInt);
    S := StringReplace(S, '/', PathDelim, [rfReplaceAll]);
    Exit(NormalizeLocalPath(S));
  end;
  Result := FileUriToPath(ABaseUri);
end;

function IsZipArchiveUri(const AURI: string): Boolean;
var
  Base: string;
  Segs: TArray<string>;
begin
  Result := False;
  if not HasArchiveChain(AURI) then
    Exit;
  if not SplitArchiveUri(AURI, Base, Segs) then
    Exit;
  if not Base.StartsWith('file:', True) then
    Exit;
  // By name, or by content for a ZIP under another name opened with
  // Ctrl+PgDn (docx, odt). The content check keeps a folder whose name ends
  // in '!' (D:\Work\Wow!\file.txt) on the file system.
  Result := IsZipFileName(SafeFileName(FileUriToPath(Base))) or
    FileHasZipSignature(FileUriToPath(Base));
end;

function PathToArchiveRootUri(const AScheme, AArchivePath: string): string;
var
  P: string;
begin
  P := ExcludeTrailingPathDelimiter(Trim(AArchivePath));
  if (P = '') or (Trim(AScheme) = '') then
    Exit('');
  if PlatformPosixPaths then
    // 7z:///home/user/a.7z!/ - the path keeps its leading slash.
    Exit(LowerCase(Trim(AScheme)) + '://' + P + '!/');
  P := StringReplace(P, '\', '/', [rfReplaceAll]);
  Result := LowerCase(Trim(AScheme)) + ':///' + P + '!/';
end;

function PathToSevenZipRootUri(const AArchivePath: string): string;
begin
  Result := PathToArchiveRootUri('7z', AArchivePath);
end;

function ZipEntryToSevenZipUri(const AEntryUri: string): string;
var
  Base: string;
  Segs: TArray<string>;
begin
  Result := '';
  if not SplitArchiveUri(AEntryUri, Base, Segs) then
    Exit;
  if not Base.StartsWith('file:', True) or (Length(Segs) <> 1) then
    Exit;
  Result := JoinVfsUri(PathToSevenZipRootUri(FileUriToPath(Base)), Segs[0]);
end;

function FormatVfsAttrText(AReadOnly, AHidden, ASystem, AArchive,
  ALink: Boolean): string;
begin
  Result := '';
  if AReadOnly then
    Result := Result + 'R'
  else
    Result := Result + '-';
  if AHidden then
    Result := Result + 'H'
  else
    Result := Result + '-';
  if ASystem then
    Result := Result + 'S'
  else
    Result := Result + '-';
  if AArchive then
    Result := Result + 'A'
  else
    Result := Result + '-';
  if ALink then
    Result := Result + 'L'
  else
    Result := Result + '-';
end;

function FormatUnixMode(AMode: Cardinal): string;
const
  cTriads = 'rwxrwxrwx';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 8 do
    if (AMode and (Cardinal(1) shl (8 - I))) <> 0 then
      Result := Result + cTriads[I + 1]
    else
      Result := Result + '-';
  // setuid / setgid / sticky replace the execute position.
  if (AMode and $800) <> 0 then
    Result[3] := IfThen((AMode and $40) <> 0, 's', 'S')[1];
  if (AMode and $400) <> 0 then
    Result[6] := IfThen((AMode and $8) <> 0, 's', 'S')[1];
  if (AMode and $200) <> 0 then
    Result[9] := IfThen((AMode and $1) <> 0, 't', 'T')[1];
end;

function FormatVfsAttrText(const AEntry: TVfsEntry): string;
begin
  if AEntry.UnixMode <> 0 then
    Exit(FormatUnixMode(AEntry.UnixMode));
  Result := FormatVfsAttrText(AEntry.IsReadOnly, AEntry.IsHidden, AEntry.IsSystem,
    AEntry.IsArchive, AEntry.IsLink);
end;

function IsFindUri(const AURI: string): Boolean;
begin
  Result := StartsText('find://', Trim(AURI));
end;

function IsSystemFoldersUri(const AURI: string): Boolean;
begin
  Result := SameText(Trim(AURI), 'sys://folders');
end;

function IsRecycleBinUri(const AURI: string): Boolean;
begin
  Result := StartsText('recycle:', Trim(AURI));
end;

function IsTmpPanelUri(const AURI: string): Boolean;
var
  S: string;
  P: Integer;
begin
  S := Trim(AURI);
  P := Pos('://', S);
  Result := (P > 1) and SameText(Copy(S, 1, P - 1), 'tmp');
end;

function IsWorkspaceUri(const AURI: string): Boolean;
var
  S: string;
  P: Integer;
begin
  S := Trim(AURI);
  P := Pos('://', S);
  Result := (P > 1) and SameText(Copy(S, 1, P - 1), 'ws');
end;

function WorkspaceInnerPath(const AURI: string): string;
var
  S: string;
  P: Integer;
begin
  Result := '';
  if not IsWorkspaceUri(AURI) then
    Exit;
  S := Trim(AURI);
  P := Pos('://', S);
  S := Copy(S, P + 3, MaxInt);
  S := StringReplace(S, '\', '/', [rfReplaceAll]);
  while (Length(S) > 0) and (S[1] = '/') do
    Delete(S, 1, 1);
  while (Length(S) > 0) and (S[Length(S)] = '/') do
    Delete(S, Length(S), 1);
  Result := S;
end;

function MakeWorkspaceUri(const AInner: string): string;
var
  Inner: string;
begin
  Inner := StringReplace(Trim(AInner), '\', '/', [rfReplaceAll]);
  while (Length(Inner) > 0) and (Inner[1] = '/') do
    Delete(Inner, 1, 1);
  while (Length(Inner) > 0) and (Inner[Length(Inner)] = '/') do
    Delete(Inner, Length(Inner), 1);
  if Inner = '' then
    Result := 'ws:///'
  else
    Result := 'ws:///' + Inner;
end;

function IsSftpUri(const AURI: string): Boolean;
var
  S: string;
  P: Integer;
begin
  S := Trim(AURI);
  P := Pos('://', S);
  Result := (P > 1) and SameText(Copy(S, 1, P - 1), 'sftp');
end;

function SftpSplitUri(const AURI: string; out AAuthority, APath: string): Boolean;
var
  S, Rest: string;
  P, Slash: Integer;
begin
  AAuthority := '';
  APath := '/';
  Result := False;
  if not IsSftpUri(AURI) then
    Exit;
  S := Trim(AURI);
  P := Pos('://', S);
  Rest := Copy(S, P + 3, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    AAuthority := Rest;
    APath := '/';
  end
  else
  begin
    AAuthority := Copy(Rest, 1, Slash - 1);
    APath := Copy(Rest, Slash, MaxInt);
    while (Length(APath) > 1) and (APath[Length(APath)] = '/') do
      Delete(APath, Length(APath), 1);
    if APath = '' then
      APath := '/';
  end;
  Result := AAuthority <> '';
end;

function SftpAuthorityOf(const AURI: string): string;
var
  Dummy: string;
begin
  if not SftpSplitUri(AURI, Result, Dummy) then
    Result := '';
end;

function SftpRemotePathOf(const AURI: string): string;
var
  Dummy: string;
begin
  if not SftpSplitUri(AURI, Dummy, Result) then
    Result := '/';
end;

function MakeSftpUri(const AAuthority, ARemotePath: string): string;
var
  P: string;
begin
  P := ARemotePath;
  if P = '' then
    P := '/';
  if P[1] <> '/' then
    P := '/' + P;
  while (Length(P) > 1) and (P[Length(P)] = '/') do
    Delete(P, Length(P), 1);
  Result := 'sftp://' + AAuthority + P;
end;

function RecyclePathToUri(const APath: string): string;
begin
  Result := PathToFileUri(APath);
  Result := 'recycle://' + Copy(Result, Length('file://') + 1, MaxInt);
end;

function RecycleUriToPath(const AURI: string): string;
begin
  if not IsRecycleBinUri(AURI) then
    Exit('');
  Result := FileUriToPath('file://' + Copy(AURI, Length('recycle://') + 1, MaxInt));
end;

function MakeFindSessionUri(const ASessionId: string): string;
var
  Id: string;
begin
  Id := Trim(ASessionId);
  if Id = '' then
    Exit('');
  Result := 'find://session/' + Id + '/';
end;

function FindSessionIdFromUri(const AURI: string): string;
var
  S, Rest: string;
  P: Integer;
begin
  Result := '';
  S := Trim(AURI);
  if not StartsText('find://', S) then
    Exit;
  Rest := Copy(S, Length('find://') + 1, MaxInt);
  if StartsText('session/', Rest) then
    Rest := Copy(Rest, Length('session/') + 1, MaxInt);
  P := Pos('/', Rest);
  if P > 0 then
    Result := Copy(Rest, 1, P - 1)
  else
    Result := Rest;
  Result := Trim(Result);
end;

function EnsureArchiveRootUri(const AZipFileUri: string): string;
var
  S: string;
begin
  S := Trim(AZipFileUri);
  if S = '' then
    Exit('');
  if HasArchiveChain(S) then
  begin
    if (Length(S) >= 2) and (Copy(S, Length(S) - 1, 2) = '!/') then
      Result := S
    else
      Result := S + '!/';
  end
  else
    Result := S + '!/';
end;

type
  TLifeFlag = class(TInterfacedObject, ILifeFlag)
  private
    FAlive: Boolean;
    function GetAlive: Boolean;
    procedure SetAlive(AValue: Boolean);
  end;

function TLifeFlag.GetAlive: Boolean;
begin
  Result := FAlive;
end;

procedure TLifeFlag.SetAlive(AValue: Boolean);
begin
  FAlive := AValue;
end;

function NewLifeFlag: ILifeFlag;
begin
  Result := TLifeFlag.Create;
  Result.Alive := True;
end;

const
  cBuiltInUriSchemes: array[0..6] of string =
    ('file', 'sys', 'recycle', 'tmp', 'ws', 'find', 'sftp');

function GenericVfsSplit(const AURI: string; out AScheme, AAuthority,
  APath: string): Boolean;
var
  S, Rest: string;
  P, Slash, I: Integer;
begin
  Result := False;
  AScheme := '';
  AAuthority := '';
  APath := '/';
  S := Trim(AURI);
  P := Pos('://', S);
  if P < 2 then
    Exit;
  AScheme := LowerCase(Copy(S, 1, P - 1));
  for I := 1 to Length(AScheme) do
    if not CharInSet(AScheme[I], ['a'..'z', '0'..'9', '+', '-', '.']) then
      Exit;
  for I := 0 to High(cBuiltInUriSchemes) do
    if AScheme = cBuiltInUriSchemes[I] then
      Exit;
  if HasArchiveChain(S) then
    Exit;
  Rest := Copy(S, P + 3, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    AAuthority := Rest;
    APath := '/';
  end
  else
  begin
    AAuthority := Copy(Rest, 1, Slash - 1);
    APath := Copy(Rest, Slash, MaxInt);
  end;
  while (Length(APath) > 1) and (APath[Length(APath)] = '/') do
    Delete(APath, Length(APath), 1);
  if APath = '' then
    APath := '/';
  Result := True;
end;

function IsGenericVfsUri(const AURI: string): Boolean;
var
  Scheme, Authority, Path: string;
begin
  Result := GenericVfsSplit(AURI, Scheme, Authority, Path);
end;

function GenericVfsSchemeOf(const AURI: string): string;
var
  Authority, Path: string;
begin
  if not GenericVfsSplit(AURI, Result, Authority, Path) then
    Result := '';
end;

function GenericVfsAuthorityOf(const AURI: string): string;
var
  Scheme, Path: string;
begin
  if not GenericVfsSplit(AURI, Scheme, Result, Path) then
    Result := '';
end;

function GenericVfsPathOf(const AURI: string): string;
var
  Scheme, Authority: string;
begin
  if not GenericVfsSplit(AURI, Scheme, Authority, Result) then
    Result := '/';
end;

function MakeGenericVfsUri(const AScheme, AAuthority, APath: string): string;
var
  Path: string;
begin
  Path := APath;
  if (Path = '') or (Path[1] <> '/') then
    Path := '/' + Path;
  Result := LowerCase(AScheme) + '://' + AAuthority + Path;
end;

function ParentVfsUriOfGeneric(const AURI: string): string;
var
  Scheme, Authority, Path: string;
  Slash: Integer;
begin
  if not GenericVfsSplit(AURI, Scheme, Authority, Path) then
    Exit(AURI);
  if Path = '/' then
  begin
    // The root of an authority hangs under the scheme's own root.
    Exit(MakeGenericVfsUri(Scheme, '', '/'));
  end;
  Slash := LastDelimiter('/', Path);
  if Slash <= 1 then
    Result := MakeGenericVfsUri(Scheme, Authority, '/')
  else
    Result := MakeGenericVfsUri(Scheme, Authority, Copy(Path, 1, Slash - 1));
end;

function JoinVfsUriOfGeneric(const ADirURI, AName: string): string;
var
  Scheme, Authority, Path: string;
begin
  if not GenericVfsSplit(ADirURI, Scheme, Authority, Path) then
    Exit(ADirURI);
  if Path = '/' then
    Result := MakeGenericVfsUri(Scheme, Authority, '/' + AName)
  else
    Result := MakeGenericVfsUri(Scheme, Authority, Path + '/' + AName);
end;

function JoinVfsUri(const ADirURI, AName: string): string;
var
  Base, Name, Last: string;
  Segs: TArray<string>;
  I: Integer;
begin
  // Not trimmed: a file name may start with a space.
  Name := AName;
  if Name = '' then
    Exit(ADirURI);
  // A backslash separates only on Windows; elsewhere it is part of a name.
  if not PlatformPosixPaths then
    Name := StringReplace(Name, '\', '/', [rfReplaceAll]);
  while (Length(Name) > 0) and ((Name[1] = '/') or
    (not PlatformPosixPaths and (Name[1] = '\'))) do
    Delete(Name, 1, 1);

  if IsFindUri(ADirURI) then
    Exit(ADirURI);

  // Flat (no subfolders) in v1 - same "no-op join" as find:// above.
  if IsRecycleBinUri(ADirURI) or IsTmpPanelUri(ADirURI) then
    Exit(ADirURI);

  if IsWorkspaceUri(ADirURI) then
  begin
    if WorkspaceInnerPath(ADirURI) = '' then
      Exit(MakeWorkspaceUri(Name));
    Exit(MakeWorkspaceUri(WorkspaceInnerPath(ADirURI) + '/' + Name));
  end;

  if IsSftpUri(ADirURI) then
  begin
    if SftpRemotePathOf(ADirURI) = '/' then
      Exit(MakeSftpUri(SftpAuthorityOf(ADirURI), '/' + Name));
    Exit(MakeSftpUri(SftpAuthorityOf(ADirURI), SftpRemotePathOf(ADirURI) + '/' + Name));
  end;

  if IsGenericVfsUri(ADirURI) then
    Exit(JoinVfsUriOfGeneric(ADirURI, Name));

  if not HasArchiveChain(ADirURI) then
    Exit(PathToFileUri(SafeCombinePath(FileUriToPath(ADirURI),
      StringReplace(Name, '/', PathDelim, [rfReplaceAll]))));

  if not SplitArchiveUri(ADirURI, Base, Segs) then
    Exit(PathToFileUri(SafeCombinePath(FileUriToPath(ADirURI), Name)));

  if Length(Segs) = 0 then
  begin
    SetLength(Segs, 1);
    Segs[0] := Name;
  end
  else
  begin
    Last := Segs[High(Segs)];
    if Last = '' then
      Segs[High(Segs)] := Name
    else
      Segs[High(Segs)] := Last + '/' + Name;
  end;

  Result := Base;
  for I := 0 to High(Segs) do
  begin
    Result := Result + '!/';
    if Segs[I] <> '' then
      Result := Result + Segs[I];
  end;
  // Directory-looking joins keep trailing '!/' only when last seg empty - files stay without.
end;

// Shared by both archive-layer branches of ParentVfsUri: '!/'-joins ASegs
// onto ABase, skipping empty segments' text but keeping their '!/' marker.
function JoinArchiveSegments(const ABase: string; const ASegs: TArray<string>): string;
var
  I: Integer;
begin
  Result := ABase;
  for I := 0 to High(ASegs) do
  begin
    Result := Result + '!/';
    if ASegs[I] <> '' then
      Result := Result + ASegs[I];
  end;
end;

function ParentVfsUriOfWorkspace(const AURI: string): string;
var
  Inner: string;
  Slash: Integer;
begin
  Inner := WorkspaceInnerPath(AURI);
  if Inner = '' then
    Exit('ws:///');
  Slash := LastDelimiter('/', Inner);
  if Slash > 0 then
    Result := MakeWorkspaceUri(Copy(Inner, 1, Slash - 1))
  else
    Result := 'ws:///';
end;

function ParentVfsUriOfSftp(const AURI: string): string;
var
  Inner: string;
  Slash: Integer;
begin
  Inner := SftpRemotePathOf(AURI);
  if Inner = '/' then
    Exit(MakeSftpUri(SftpAuthorityOf(AURI), '/'));
  Slash := LastDelimiter('/', Inner);
  if Slash <= 1 then
    Result := MakeSftpUri(SftpAuthorityOf(AURI), '/')
  else
    Result := MakeSftpUri(SftpAuthorityOf(AURI), Copy(Inner, 1, Slash - 1));
end;

function ParentVfsUriOfLocalPath(const AURI: string): string;
var
  Path, Parent: string;
begin
  Path := FileUriToPath(AURI);
  if IsLocalRoot(Path) then
    Exit(PathToFileUri(Path));
  Parent := SafeDirectoryName(ExcludeTrailingPathDelimiter(Path));
  if (Parent = '') or SameLocalPath(NormalizeLocalPath(Parent), NormalizeLocalPath(Path)) then
    Result := PathToFileUri(Path)
  else
    Result := PathToFileUri(Parent);
end;

// Precondition: SplitArchiveUri(AURI, ABase, ASegs) already succeeded with
// Length(ASegs) > 0 - see the two call sites in ParentVfsUriOfArchive.
function ParentVfsUriOfArchiveSegs(const AURI, ABase: string; ASegs: TArray<string>): string;
var
  Last, ParentSeg: string;
  Slash: Integer;
  Path, Parent: string;
begin
  Last := ASegs[High(ASegs)];
  if Last <> '' then
  begin
    // SysUtils.LastDelimiter is 1-based (Copy/Pos); TStringHelper.LastDelimiter is 0-based.
    Slash := LastDelimiter('/', Last);
    if Slash > 0 then
      ParentSeg := Copy(Last, 1, Slash - 1)
    else
      ParentSeg := ''; // up to this archive layer root
    ASegs[High(ASegs)] := ParentSeg;
    Result := JoinArchiveSegments(ABase, ASegs);
    // Layer root: ensure trailing '!/' when last segment empty.
    if ASegs[High(ASegs)] = '' then
    begin
      if (Length(Result) < 2) or (Copy(Result, Length(Result) - 1, 2) <> '!/') then
        Result := Result + '!/';
    end;
    Exit;
  end;

  // At layer root (empty last segment): peel one archive layer.
  if Length(ASegs) = 1 then
  begin
    // Outer zip root -> directory containing the zip file.
    Path := ArchiveBaseLocalPath(ABase);
    Parent := SafeDirectoryName(ExcludeTrailingPathDelimiter(Path));
    if Parent = '' then
      Result := PathToFileUri(Path)
    else
      Result := PathToFileUri(Parent);
    Exit;
  end;

  // Drop this layer's root marker and re-peel: the new last segment is now
  // the entry name we descended through (e.g. "inner.tar"), and running it
  // back through the Last <> '' branch above lands on THAT entry's own
  // parent directory within the containing layer -- typically layer root,
  // since a nested archive is rarely itself inside a subfolder of its
  // container. A bare "Base!/entry.name" (no trailing '!/') is not a valid
  // listing target -- ListDirectoryAsync would look for a directory prefix
  // that doesn't exist and come back empty, so this must not be returned
  // directly (recursing keeps every returned URI listable, however deep
  // the chain, one peel at a time).
  SetLength(ASegs, Length(ASegs) - 1);
  Result := ParentVfsUriOfArchiveSegs(AURI, ABase, ASegs);
end;

function ParentVfsUriOfArchive(const AURI: string): string;
var
  Base: string;
  Segs: TArray<string>;
begin
  if not SplitArchiveUri(AURI, Base, Segs) then
    Exit(AURI);
  if Length(Segs) = 0 then
    Exit(ArchiveBaseDirUri(AURI));
  Result := ParentVfsUriOfArchiveSegs(AURI, Base, Segs);
end;

function ParentVfsUri(const AURI: string): string;
begin
  if IsFindUri(AURI) or IsSystemFoldersUri(AURI) or IsRecycleBinUri(AURI) or
     IsTmpPanelUri(AURI) then
    Exit(AURI);
  if IsWorkspaceUri(AURI) then
    Exit(ParentVfsUriOfWorkspace(AURI));
  if IsSftpUri(AURI) then
    Exit(ParentVfsUriOfSftp(AURI));
  if IsGenericVfsUri(AURI) then
    Exit(ParentVfsUriOfGeneric(AURI));
  if not HasArchiveChain(AURI) then
    Exit(ParentVfsUriOfLocalPath(AURI));
  Result := ParentVfsUriOfArchive(AURI);
end;

// The path segment after the final '/', or the whole string if there is none.
function LastUriPathSegment(const APath: string): string;
var
  Slash: Integer;
begin
  Slash := LastDelimiter('/', APath);
  if Slash > 0 then
    Result := Copy(APath, Slash + 1, MaxInt)
  else
    Result := APath;
end;

function VfsUriTitle(const AURI: string): string;
var
  Base, Last: string;
  Segs: TArray<string>;
  Path: string;
begin
  if IsSystemFoldersUri(AURI) then
    Exit('System Folders');
  if IsFindUri(AURI) then
  begin
    Result := 'Find';
    Exit;
  end;
  if IsRecycleBinUri(AURI) then
  begin
    Result := 'Recycle Bin';
    Exit;
  end;
  if IsTmpPanelUri(AURI) then
    Exit('Temporary');
  if IsWorkspaceUri(AURI) then
  begin
    Path := WorkspaceInnerPath(AURI);
    if Path = '' then
      Exit('Workspace');
    Exit(LastUriPathSegment(Path));
  end;
  if IsSftpUri(AURI) then
  begin
    Path := SftpRemotePathOf(AURI);
    if Path = '/' then
      Exit(SftpAuthorityOf(AURI));
    Exit(LastUriPathSegment(Path));
  end;
  if IsGenericVfsUri(AURI) then
  begin
    Path := GenericVfsPathOf(AURI);
    if Path = '/' then
    begin
      Result := GenericVfsAuthorityOf(AURI);
      if Result = '' then
        Result := GenericVfsSchemeOf(AURI) + ':';
      Exit;
    end;
    Exit(LastUriPathSegment(Path));
  end;
  if not HasArchiveChain(AURI) then
  begin
    Path := FileUriToPath(AURI);
    if PlatformPosixPaths and (Path = '/') then
      Exit('/');
    if IsWindowsDriveRoot(Path) then
      Exit(UpCase(Path[1]) + ':');
    Path := ExcludeTrailingPathDelimiter(Path);
    Result := SafeFileName(Path);
    if Result = '' then
      Result := Path;
    Exit;
  end;
  if not SplitArchiveUri(AURI, Base, Segs) then
    Exit(AURI);
  if Length(Segs) = 0 then
  begin
    Result := SafeFileName(ArchiveBaseLocalPath(Base));
    Exit;
  end;
  Last := Segs[High(Segs)];
  if Last = '' then
  begin
    if Length(Segs) = 1 then
      Result := SafeFileName(ArchiveBaseLocalPath(Base))
    else
      Result := LastUriPathSegment(Segs[High(Segs) - 1]);
  end
  else
    Result := LastUriPathSegment(Last);
  if Result = '' then
    Result := SafeFileName(ArchiveBaseLocalPath(Base));
end;

// Shortens by characters; VfsUriDirTabTitle then accounts for wide ones.
function VfsUriDirTabTitleChars(const AURI: string; AMaxLen: Integer): string;
var
  Path, Drive, Tail, Full, Rest: string;
  Avail: Integer;
begin
  // Archives, Find sessions and System Folders have no meaningful "current
  // folder inside a drive" - keep VfsUriTitle's short form for them, and
  // for a drive root itself (nothing to show past the letter).
  if IsSystemFoldersUri(AURI) or IsFindUri(AURI) or IsRecycleBinUri(AURI) or
     IsTmpPanelUri(AURI) or IsWorkspaceUri(AURI) or HasArchiveChain(AURI) or
     IsGenericVfsUri(AURI) then
    Exit(VfsUriTitle(AURI));
  Path := FileUriToPath(AURI);
  if PlatformPosixPaths then
  begin
    // The path itself, shortened from the middle to its last folder.
    if (Path = '/') or (AMaxLen < 1) then
      Exit(Copy(Path, 1, Max(AMaxLen, 0)));
    Path := ExcludeTrailingPathDelimiter(Path);
    if Length(Path) <= AMaxLen then
      Exit(Path);
    Tail := SafeFileName(Path);
    if Length(Tail) + 5 <= AMaxLen then
      Exit('/.../' + Tail);
    Exit(Copy(Tail, Max(Length(Tail) - AMaxLen + 1, 1), AMaxLen));
  end;
  if IsWindowsDriveRoot(Path) then
    Exit(UpCase(Path[1]) + ':');
  Path := ExcludeTrailingPathDelimiter(Path);
  if (Length(Path) < 2) or (Path[2] <> ':') then
    Exit(VfsUriTitle(AURI)); // UNC or unexpected shape: the plain URI title
  if AMaxLen < 1 then
    Exit('');

  Drive := UpCase(Path[1]) + ':';
  Full := Drive + Copy(Path, 3, MaxInt);
  if Length(Full) <= AMaxLen then
    Exit(Full);

  // The drive letter always stays, even under extreme truncation - it's
  // the one piece of information this caption exists to surface, so it
  // must survive narrower tabs/panels rather than fall off with the rest.
  if AMaxLen <= Length(Drive) then
    Exit(Copy(Drive, 1, AMaxLen));

  Tail := SafeFileName(Path);
  if Tail = '' then
    Tail := Path;
  Avail := AMaxLen - Length(Drive); // columns left after 'C:'
  if Avail >= Length('\...\') + Length(Tail) then
    Rest := '\...\' + Tail
  else if Avail >= 2 then
    // No room left for the '...' marker on top of the drive - keep the
    // separator and as much of the tail's own END as fits (the part an
    // ellipsis would otherwise be standing in for).
    Rest := '\' + Copy(Tail, Max(Length(Tail) - (Avail - 1) + 1, 1), Avail - 1)
  else
    Rest := Copy('\' + Tail, 1, Avail);
  Result := Drive + Rest;
end;

function VfsUriDirTabTitle(const AURI: string; AMaxLen: Integer): string;
var
  N: Integer;
begin
  Result := VfsUriDirTabTitleChars(AURI, AMaxLen);
  // Wide characters take two cells each: shrink the character budget until
  // the title fits the cells.
  N := AMaxLen;
  while (N > 1) and (TextDisplayWidth(Result) > AMaxLen) do
  begin
    Dec(N);
    Result := VfsUriDirTabTitleChars(AURI, N);
  end;
end;

function ResolveVfsUri(const AURI: string): string;
var
  Base: string;
  Segs: TArray<string>;
  ResolvedBase: string;
  I: Integer;
  Id: string;
begin
  if IsFindUri(AURI) then
  begin
    Id := FindSessionIdFromUri(AURI);
    if Id = '' then
      Exit(AURI);
    Exit(MakeFindSessionUri(Id));
  end;
  if IsSystemFoldersUri(AURI) then
    Exit('sys://folders');
  if IsRecycleBinUri(AURI) then
    Exit('recycle:///'); // canonical root - matches uRecycleBinVfs.cRecycleBinRootUri
  if IsTmpPanelUri(AURI) then
    Exit('tmp:///');
  if IsWorkspaceUri(AURI) then
    Exit(MakeWorkspaceUri(WorkspaceInnerPath(AURI)));
  if not HasArchiveChain(AURI) then
  begin
    if StartsText('file://', Trim(AURI)) or (Pos('://', Trim(AURI)) = 0) then
      Exit(ResolveFileUri(AURI))
    else
      Exit(AURI);
  end;
  if not SplitArchiveUri(AURI, Base, Segs) then
    Exit(AURI);
  if IsSevenZipUri(Base) then
    ResolvedBase := Base
  else
    ResolvedBase := PathToFileUri(FileUriToPath(Base));
  Result := ResolvedBase;
  for I := 0 to High(Segs) do
  begin
    Result := Result + '!/';
    if Segs[I] <> '' then
      Result := Result + Segs[I];
  end;
  if (Length(Segs) > 0) and (Segs[High(Segs)] = '') then
    if (Length(Result) < 2) or (Copy(Result, Length(Result) - 1, 2) <> '!/') then
      Result := Result + '!/';
end;

function IsVfsUriNavigationRoot(const AURI: string): Boolean;
begin
  // Inside archives / find results / system folders always allow '..'. Drive roots hide parent.
  if IsWorkspaceUri(AURI) then
    Exit(WorkspaceInnerPath(AURI) = '');
  if IsSftpUri(AURI) then
    Exit(SftpRemotePathOf(AURI) = '/');
  if IsGenericVfsUri(AURI) then
    Exit((GenericVfsAuthorityOf(AURI) = '') and (GenericVfsPathOf(AURI) = '/'));
  if HasArchiveChain(AURI) or IsFindUri(AURI) or IsSystemFoldersUri(AURI) or
     IsRecycleBinUri(AURI) or IsTmpPanelUri(AURI) then
    Exit(False);
  Result := IsLocalRoot(FileUriToPath(AURI));
end;

end.
