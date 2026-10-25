unit uPlatformFileOps;

{ Local-file operations whose behavior depends on the operating system:
  directory-entry attributes and times, attribute copy, and deletion with
  retry (Windows build). The POSIX build lives in Platform\Posix; each project
  puts exactly one of the two directories on its unit search path. }

interface

uses
  System.SysUtils, uVfsTypes;

/// <summary>Fills the attribute flags and times of AEntry from a directory
/// scan record; Name, Extension, Size and IsDirectory are set by the caller.</summary>
procedure PlatformFillEntry(const SR: TSearchRec; var AEntry: TVfsEntry);

/// <summary>True when a FindFirst result code means "access denied".</summary>
function PlatformSearchDenied(ACode: Integer): Boolean;

/// <summary>True when E reports an access-denied failure of a file operation.</summary>
function PlatformIsAccessDenied(E: Exception): Boolean;

/// <summary>Copies the settable attributes (read-only, hidden, ...) or the
/// permission bits from ASrc to ADst; best effort.</summary>
procedure PlatformCopyAttributes(const ASrc, ADst: string);

/// <summary>Fills the attribute flags of AEntry from the file at APath.</summary>
procedure PlatformFillEntryByPath(const APath: string; var AEntry: TVfsEntry);

/// <summary>True when the file at APath cannot be written to by its attributes.</summary>
function PlatformIsReadOnlyFile(const APath: string): Boolean;

/// <summary>True for a symbolic link, junction or other reparse point: a
/// node whose content lives elsewhere.</summary>
function PlatformIsReparsePoint(const APath: string): Boolean;

/// <summary>Text of the system's "access denied" error.</summary>
function PlatformAccessDeniedText: string;

/// <summary>Removes the read-only attribute (the missing write permission on
/// POSIX) from APath; raises when that is not possible.</summary>
procedure PlatformClearReadOnly(const APath: string);

/// <summary>True for a regular file with an execute permission bit; always
/// False on Windows, where the file kind decides.</summary>
function PlatformIsExecutableFile(const APath: string): Boolean;

/// <summary>True for a symbolic link that must be removed as a single node
/// instead of being walked into.</summary>
function PlatformIsLinkNode(const APath: string): Boolean;

/// <summary>Removes one file or empty directory, retrying while it is briefly
/// locked. A missing node counts as removed.</summary>
function PlatformDeleteNode(const APath: string; AIsDir: Boolean;
  out AError: TVfsError): Boolean;

implementation

uses
  Winapi.Windows;

function FileTimeToLocalDateTime(const AFT: TFileTime): TDateTime;
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

procedure PlatformFillEntry(const SR: TSearchRec; var AEntry: TVfsEntry);
begin
  {$WARN SYMBOL_PLATFORM OFF}
  AEntry.IsHidden := ((SR.Attr and faHidden) <> 0) or
    ((SR.Attr and faSysFile) <> 0);
  AEntry.IsReadOnly := (SR.Attr and faReadOnly) <> 0;
  AEntry.IsSystem := (SR.Attr and faSysFile) <> 0;
  AEntry.IsArchive := (SR.Attr and faArchive) <> 0;
  AEntry.IsCompressed := (SR.Attr and faCompressed) <> 0;
  AEntry.IsEncrypted := (SR.Attr and faEncrypted) <> 0;
  AEntry.IsTemporary := (DWORD(SR.Attr) and FILE_ATTRIBUTE_TEMPORARY) <> 0;
  AEntry.IsOffline := (DWORD(SR.Attr) and FILE_ATTRIBUTE_OFFLINE) <> 0;
  // faSymLink = FILE_ATTRIBUTE_REPARSE_POINT
  AEntry.IsLink := (SR.Attr and faSymLink) <> 0;
  AEntry.ModificationTime := FileTimeToLocalDateTime(SR.FindData.ftLastWriteTime);
  if AEntry.ModificationTime = 0 then
    AEntry.ModificationTime := SR.TimeStamp;
  AEntry.CreationTime := FileTimeToLocalDateTime(SR.FindData.ftCreationTime);
  if AEntry.CreationTime = 0 then
    AEntry.CreationTime := AEntry.ModificationTime;
  AEntry.AccessTime := FileTimeToLocalDateTime(SR.FindData.ftLastAccessTime);
  if AEntry.AccessTime = 0 then
    AEntry.AccessTime := AEntry.ModificationTime;
  {$WARN SYMBOL_PLATFORM ON}
end;

procedure PlatformFillEntryByPath(const APath: string; var AEntry: TVfsEntry);
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
    Exit;
  AEntry.IsHidden := ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0) or
    ((Attr and FILE_ATTRIBUTE_SYSTEM) <> 0);
  AEntry.IsReadOnly := (Attr and FILE_ATTRIBUTE_READONLY) <> 0;
  AEntry.IsSystem := (Attr and FILE_ATTRIBUTE_SYSTEM) <> 0;
  AEntry.IsArchive := (Attr and FILE_ATTRIBUTE_ARCHIVE) <> 0;
  AEntry.IsCompressed := (Attr and FILE_ATTRIBUTE_COMPRESSED) <> 0;
  AEntry.IsEncrypted := (Attr and FILE_ATTRIBUTE_ENCRYPTED) <> 0;
  AEntry.IsTemporary := (Attr and FILE_ATTRIBUTE_TEMPORARY) <> 0;
  AEntry.IsOffline := (Attr and FILE_ATTRIBUTE_OFFLINE) <> 0;
  AEntry.IsLink := (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0;
end;

function PlatformSearchDenied(ACode: Integer): Boolean;
begin
  Result := ACode = ERROR_ACCESS_DENIED;
end;

// A failed create/write/move raises an exception that carries the Win32 error
// only as text ("Cannot create file ...: Access denied").
function PlatformIsAccessDenied(E: Exception): Boolean;
var
  Denied: string;
begin
  Denied := SysErrorMessage(ERROR_ACCESS_DENIED);
  Result := ((E is EOSError) and (EOSError(E).ErrorCode = ERROR_ACCESS_DENIED)) or
    ((Denied <> '') and (Pos(LowerCase(Denied), LowerCase(E.Message)) > 0));
end;

procedure PlatformCopyAttributes(const ASrc, ADst: string);
const
  // Only the bits SetFileAttributes accepts: DIRECTORY, REPARSE_POINT,
  // COMPRESSED, ENCRYPTED etc. cannot be set this way.
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

function PlatformIsReadOnlyFile(const APath: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
    ((Attr and FILE_ATTRIBUTE_READONLY) <> 0);
end;

function PlatformIsExecutableFile(const APath: string): Boolean;
begin
  Result := False;
end;

function PlatformAccessDeniedText: string;
begin
  Result := Format('0x%8.8x - %s', [ERROR_ACCESS_DENIED,
    SysErrorMessage(ERROR_ACCESS_DENIED)]);
end;

procedure PlatformClearReadOnly(const APath: string);
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
    RaiseLastOSError;
  if (Attr and FILE_ATTRIBUTE_READONLY) <> 0 then
    if not SetFileAttributes(PChar(WinApiPath(APath)),
         Attr and not FILE_ATTRIBUTE_READONLY) then
      RaiseLastOSError;
end;

function PlatformIsReparsePoint(const APath: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
    ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

function PlatformIsLinkNode(const APath: string): Boolean;
begin
  Result := False;
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

function PlatformDeleteNode(const APath: string; AIsDir: Boolean;
  out AError: TVfsError): Boolean;
var
  Code: DWORD;
begin
  AError := TVfsError.Ok;
  Code := RetryWin32Delete(APath, AIsDir);
  Result := Code = ERROR_SUCCESS;
  if Result then
    Exit;
  if (Code = ERROR_ACCESS_DENIED) or (Code = ERROR_SHARING_VIOLATION) then
    AError := TVfsError.Make(vecAccessDenied, SysErrorMessage(Code), PathToFileUri(APath))
  else
    AError := TVfsError.Make(vecIOError, SysErrorMessage(Code), PathToFileUri(APath));
end;

end.
