unit uPlatformPaths;

{ File-system queries on a local path (Windows build). The Posix build lives
  in Platform\Posix; each project puts exactly one of the two directories on
  its unit search path. Callers pass the path as it must be handed to the OS
  (see uVfsTypes.WinApiPath). }

interface

/// <summary>True for an existing directory, including a junction or symlink
/// to one (Delphi's DirectoryExists misses some junctions).</summary>
function PlatformIsDirectory(const AApiPath: string): Boolean;

/// <summary>True for an existing non-directory.</summary>
function PlatformIsFile(const AApiPath: string): Boolean;

/// <summary>The directory a junction or symlink path finally points at, in
/// the OS's final-path spelling; '' when it cannot be resolved.</summary>
function PlatformFinalDirPath(const AApiPath: string): string;

/// <summary>True where local paths are POSIX paths: "/" separators, one root,
/// case-sensitive names, no drive letters.</summary>
function PlatformPosixPaths: Boolean;

/// <summary>Identifies the volume a path lives on, so jobs on one disk can queue:
/// the device number of the path or of its nearest existing parent. '' where
/// drive letters tell volumes apart (Windows) or nothing is known.</summary>
function PlatformVolumeId(const APath: string): string;

implementation

uses
  Winapi.Windows;

function PlatformPosixPaths: Boolean;
begin
  Result := False;
end;

function PlatformVolumeId(const APath: string): string;
begin
  Result := '';
end;

function PlatformIsDirectory(const AApiPath: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(AApiPath));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
    ((Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0);
end;

function PlatformIsFile(const AApiPath: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(AApiPath));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
    ((Attr and FILE_ATTRIBUTE_DIRECTORY) = 0);
end;

function PlatformFinalDirPath(const AApiPath: string): string;
var
  H: THandle;
  Buf: array[0..4095] of Char;
  N: DWORD;
begin
  Result := '';
  // FILE_FLAG_BACKUP_SEMANTICS without OPEN_REPARSE_POINT follows the target.
  H := CreateFile(PChar(AApiPath), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    FillChar(Buf[0], SizeOf(Buf), 0);
    {$WARN SYMBOL_PLATFORM OFF}
    N := GetFinalPathNameByHandle(H, Buf, Length(Buf), FILE_NAME_NORMALIZED);
    {$WARN SYMBOL_PLATFORM ON}
    if N > 0 then
      Result := Copy(string(Buf), 1, N);
  finally
    CloseHandle(H);
  end;
end;

end.
