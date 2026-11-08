unit uPlatformFileOps;

{ Local-file operations whose behavior depends on the operating system:
  directory-entry attributes and times, attribute copy, and deletion (POSIX
  build). The Windows build lives in Platform\Windows; each project puts
  exactly one of the two directories on its unit search path. }

interface

uses
  System.SysUtils, uVfsTypes;

/// <summary>Fills the attribute flags and times of AEntry from a directory
/// scan record; Name, Extension, Size and IsDirectory are set by the caller.</summary>
procedure PlatformFillEntry(const SR: TSearchRec; var AEntry: TVfsEntry);

/// <summary>Fills the attribute flags of AEntry from the file at APath.</summary>
procedure PlatformFillEntryByPath(const APath: string; var AEntry: TVfsEntry);

/// <summary>True when a FindFirst result code means "access denied".</summary>
function PlatformSearchDenied(ACode: Integer): Boolean;

/// <summary>True when the scan record is a directory symbolic link, which a
/// recursive walk must not enter (it can point back at an ancestor).</summary>
function PlatformIsDirectoryLink(const SR: TSearchRec): Boolean;

/// <summary>True when E reports an access-denied failure of a file operation.</summary>
function PlatformIsAccessDenied(E: Exception): Boolean;

/// <summary>Copies the settable attributes (read-only, hidden, ...) or the
/// permission bits from ASrc to ADst; best effort.</summary>
procedure PlatformCopyAttributes(const ASrc, ADst: string);

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

/// <summary>Removes one file or empty directory. A missing node counts as
/// removed.</summary>
function PlatformDeleteNode(const APath: string; AIsDir: Boolean;
  out AError: TVfsError): Boolean;

implementation

uses
  Posix.Base, Posix.Errno, Posix.SysStat, Posix.Unistd, Posix.Stdio;

function c_rmdir(APath: MarshaledAString): Integer; cdecl;
  external libc name 'rmdir';
function c_unlink(APath: MarshaledAString): Integer; cdecl;
  external libc name 'unlink';

procedure PlatformFillEntry(const SR: TSearchRec; var AEntry: TVfsEntry);
begin
  {$WARN SYMBOL_PLATFORM OFF}
  // Dot-files are the hidden ones.
  AEntry.IsHidden := (Length(SR.Name) > 1) and (SR.Name[1] = '.');
  AEntry.IsReadOnly := (SR.Attr and faReadOnly) <> 0;
  AEntry.IsSystem := False;
  AEntry.IsArchive := False;
  AEntry.IsCompressed := False;
  AEntry.IsEncrypted := False;
  AEntry.IsTemporary := False;
  AEntry.IsOffline := False;
  AEntry.IsLink := (SR.Attr and faSymLink) <> 0;
  {$WARN SYMBOL_PLATFORM ON}
  AEntry.UnixMode := SR.Mode and $FFF;
  AEntry.ModificationTime := SR.TimeStamp;
  AEntry.CreationTime := AEntry.ModificationTime;
  AEntry.AccessTime := AEntry.ModificationTime;
end;

procedure PlatformFillEntryByPath(const APath: string; var AEntry: TVfsEntry);
var
  Attr: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  Attr := FileGetAttr(APath);
  if Attr = -1 then
    Exit;
  AEntry.IsHidden := Copy(ExtractFileName(ExcludeTrailingPathDelimiter(APath)), 1, 1) = '.';
  AEntry.IsReadOnly := (Attr and faReadOnly) <> 0;
  AEntry.IsLink := (Attr and faSymLink) <> 0;
  {$WARN SYMBOL_PLATFORM ON}
end;

function PlatformSearchDenied(ACode: Integer): Boolean;
begin
  Result := (ACode = EACCES) or (ACode = EPERM);
end;

function PlatformIsDirectoryLink(const SR: TSearchRec): Boolean;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  Result := ((SR.Attr and faDirectory) <> 0) and ((SR.Attr and faSymLink) <> 0);
  {$WARN SYMBOL_PLATFORM ON}
end;

function PlatformIsAccessDenied(E: Exception): Boolean;
var
  Denied: string;
begin
  Denied := SysErrorMessage(EACCES);
  Result := ((E is EOSError) and
      ((EOSError(E).ErrorCode = EACCES) or (EOSError(E).ErrorCode = EPERM))) or
    ((Denied <> '') and (Pos(LowerCase(Denied), LowerCase(E.Message)) > 0));
end;

procedure PlatformCopyAttributes(const ASrc, ADst: string);
var
  St: _stat;
  Src, Dst: UTF8String;
begin
  Src := UTF8String(ASrc);
  Dst := UTF8String(ADst);
  if stat(MarshaledAString(Src), St) = 0 then
    chmod(MarshaledAString(Dst), St.st_mode and $FFF);
end;

function PlatformIsReadOnlyFile(const APath: string): Boolean;
var
  Attr: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  Attr := FileGetAttr(APath);
  Result := (Attr <> -1) and ((Attr and faReadOnly) <> 0);
  {$WARN SYMBOL_PLATFORM ON}
end;

procedure PlatformClearReadOnly(const APath: string);
var
  St: _stat;
  P: UTF8String;
begin
  P := UTF8String(APath);
  if stat(MarshaledAString(P), St) <> 0 then
    RaiseLastOSError;
  if chmod(MarshaledAString(P), (St.st_mode and $FFF) or S_IWUSR) <> 0 then
    RaiseLastOSError;
end;

function PlatformIsExecutableFile(const APath: string): Boolean;
var
  St: _stat;
  P: UTF8String;
begin
  P := UTF8String(APath);
  Result := (stat(MarshaledAString(P), St) = 0) and
    ((St.st_mode and S_IFMT) = S_IFREG) and ((St.st_mode and $49) <> 0);
end;

function PlatformAccessDeniedText: string;
begin
  Result := SysErrorMessage(EACCES);
end;

function PlatformIsReparsePoint(const APath: string): Boolean;
begin
  Result := PlatformIsLinkNode(APath);
end;

function PlatformIsLinkNode(const APath: string): Boolean;
var
  St: _stat;
  P: UTF8String;
begin
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  Result := (lstat(MarshaledAString(P), St) = 0) and
    ((St.st_mode and S_IFMT) = S_IFLNK);
end;

function PlatformDeleteNode(const APath: string; AIsDir: Boolean;
  out AError: TVfsError): Boolean;
var
  P: UTF8String;
  R, Code: Integer;
begin
  AError := TVfsError.Ok;
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  if AIsDir then
    R := c_rmdir(MarshaledAString(P))
  else
    R := c_unlink(MarshaledAString(P));
  if R = 0 then
    Exit(True);
  Code := GetLastError;
  if (Code = ENOENT) or (Code = ENOTDIR) then
    Exit(True);
  if (Code = EACCES) or (Code = EPERM) or (Code = EROFS) then
    AError := TVfsError.Make(vecAccessDenied, SysErrorMessage(Code), PathToFileUri(APath))
  else
    AError := TVfsError.Make(vecIOError, SysErrorMessage(Code), PathToFileUri(APath));
  Result := False;
end;

end.
