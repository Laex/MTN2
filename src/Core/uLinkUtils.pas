unit uLinkUtils;

{ Symlink / hardlink / junction creation (Win32 interop — nothing else in the
  codebase creates links; uVfsTypes.TVfsEntry.IsLink only detects them).

  Symlinks/hardlinks use plain kernel32 calls, declared here explicitly
  (rather than relying on Winapi.Windows to have them, which varies by RTL
  version) so this compiles the same way across Delphi releases. Junctions
  have no direct Win32 call — they're implemented, per the standard
  technique, via DeviceIoControl(FSCTL_SET_REPARSE_POINT) with a hand-built
  REPARSE_DATA_BUFFER (MountPointReparseBuffer layout).

  CROSS-PLATFORM (Этап 23): junctions are NTFS/Windows-only, no POSIX
  equivalent -- that creation path just won't exist on a POSIX build.
  Symlinks/hardlinks do exist on POSIX (symlink()/link() syscalls) but
  need their own implementation here, not a portable rewrite of the
  kernel32 calls above. }

interface

uses
  System.SysUtils, uVfsTypes;

type
  TLinkKind = (lkSymlinkFile, lkSymlinkDir, lkHardlink, lkJunction);

/// <summary>Create a link at ALinkPath pointing at ATargetPath. Local
/// filesystem only. Symlinks retry without the "unprivileged create" flag
/// on Windows versions that reject it outright; that retry still needs
/// elevation/Developer Mode and fails the same way if unavailable — the
/// error message surfaces whatever Windows reports rather than crashing.</summary>
function CreateFileLink(const ALinkPath, ATargetPath: string; AKind: TLinkKind;
  out AError: TVfsError): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils;

const
  SYMBOLIC_LINK_FLAG_DIRECTORY = $1;
  SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = $2;
  FSCTL_SET_REPARSE_POINT = $000900A4;
  IO_REPARSE_TAG_MOUNT_POINT = DWORD($A0000003);
  cMaxReparseDataSize = 16 * 1024;

function Win32CreateSymbolicLinkW(lpSymlinkFileName, lpTargetFileName: LPCWSTR;
  dwFlags: DWORD): ByteBool; stdcall; external 'kernel32.dll' name 'CreateSymbolicLinkW';

function Win32CreateHardLinkW(lpFileName, lpExistingFileName: LPCWSTR;
  lpSecurityAttributes: Pointer): BOOL; stdcall; external 'kernel32.dll' name 'CreateHardLinkW';

type
  // MountPointReparseBuffer layout (see MSDN REPARSE_DATA_BUFFER / junctions).
  TReparseDataBuffer = packed record
    ReparseTag: DWORD;
    ReparseDataLength: Word;
    Reserved: Word;
    SubstituteNameOffset: Word;
    SubstituteNameLength: Word;
    PrintNameOffset: Word;
    PrintNameLength: Word;
    PathBuffer: array[0..(cMaxReparseDataSize - 20) div 2 - 1] of WideChar;
  end;

function LastErrorMessage: string;
begin
  Result := SysErrorMessage(GetLastError);
end;

function DoCreateSymlink(const ALinkPath, ATargetPath: string; ADirectory: Boolean;
  out AError: TVfsError): Boolean;
var
  Flags: DWORD;
begin
  Flags := SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
  if ADirectory then
    Flags := Flags or SYMBOLIC_LINK_FLAG_DIRECTORY;
  Result := Win32CreateSymbolicLinkW(PWideChar(ALinkPath), PWideChar(ATargetPath), Flags);
  if not Result then
    // Older Windows without Developer Mode rejects the unprivileged-create
    // flag outright before even trying — retry without it (still needs
    // SeCreateSymbolicLinkPrivilege/elevation on those systems).
    Result := Win32CreateSymbolicLinkW(PWideChar(ALinkPath), PWideChar(ATargetPath),
      Flags and not SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE);
  if not Result then
    AError := TVfsError.Make(vecIOError, 'Cannot create symbolic link: ' + LastErrorMessage,
      PathToFileUri(ALinkPath));
end;

function DoCreateHardlink(const ALinkPath, ATargetPath: string;
  out AError: TVfsError): Boolean;
begin
  Result := Win32CreateHardLinkW(PWideChar(ALinkPath), PWideChar(ATargetPath), nil);
  if not Result then
    AError := TVfsError.Make(vecIOError, 'Cannot create hard link: ' + LastErrorMessage,
      PathToFileUri(ALinkPath));
end;

function DoCreateJunction(const ALinkPath, ATargetPath: string;
  out AError: TVfsError): Boolean;
var
  Handle: THandle;
  Buf: TReparseDataBuffer;
  SubstName, PrintName, FullTarget: string;
  SubstLenBytes, PrintLenBytes, ReparseDataLen: Word;
  SubstCharOffset, PrintCharOffset: Integer;
  TotalLen, BytesReturned: DWORD;
  CreatedDir: Boolean;
begin
  Result := False;
  CreatedDir := False;
  if not TDirectory.Exists(WinApiPath(ALinkPath)) then
  begin
    TDirectory.CreateDirectory(ALinkPath);
    CreatedDir := True;
  end;

  FullTarget := ExcludeTrailingPathDelimiter(ATargetPath);
  SubstName := '\??\' + FullTarget;
  PrintName := FullTarget;
  SubstLenBytes := Length(SubstName) * SizeOf(WideChar);
  PrintLenBytes := Length(PrintName) * SizeOf(WideChar);

  FillChar(Buf, SizeOf(Buf), 0);
  Buf.ReparseTag := IO_REPARSE_TAG_MOUNT_POINT;
  Buf.SubstituteNameOffset := 0;
  Buf.SubstituteNameLength := SubstLenBytes;
  Buf.PrintNameOffset := SubstLenBytes + SizeOf(WideChar); // past the null terminator
  Buf.PrintNameLength := PrintLenBytes;

  SubstCharOffset := 0;
  PrintCharOffset := (SubstLenBytes div SizeOf(WideChar)) + 1;
  Move(PWideChar(SubstName)^, Buf.PathBuffer[SubstCharOffset], SubstLenBytes);
  Move(PWideChar(PrintName)^, Buf.PathBuffer[PrintCharOffset], PrintLenBytes);

  ReparseDataLen := SizeOf(Word) * 4 + SubstLenBytes + SizeOf(WideChar) +
    PrintLenBytes + SizeOf(WideChar);
  Buf.ReparseDataLength := ReparseDataLen;
  TotalLen := SizeOf(DWORD) + SizeOf(Word) * 2 + ReparseDataLen;

  Handle := CreateFileW(PWideChar(WinApiPath(ALinkPath)), GENERIC_WRITE, 0, nil, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Handle = INVALID_HANDLE_VALUE then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot open link directory: ' + LastErrorMessage,
      PathToFileUri(ALinkPath));
    if CreatedDir then
      try TDirectory.Delete(WinApiPath(ALinkPath)); except end;
    Exit;
  end;
  try
    Result := DeviceIoControl(Handle, FSCTL_SET_REPARSE_POINT, @Buf, TotalLen,
      nil, 0, BytesReturned, nil);
    if not Result then
      AError := TVfsError.Make(vecIOError, 'Cannot set junction reparse point: ' + LastErrorMessage,
        PathToFileUri(ALinkPath));
  finally
    CloseHandle(Handle);
  end;
  if not Result and CreatedDir then
    try TDirectory.Delete(WinApiPath(ALinkPath)); except end;
end;

function CreateFileLink(const ALinkPath, ATargetPath: string; AKind: TLinkKind;
  out AError: TVfsError): Boolean;
begin
  AError := TVfsError.Ok;
  case AKind of
    lkSymlinkFile: Result := DoCreateSymlink(ALinkPath, ATargetPath, False, AError);
    lkSymlinkDir: Result := DoCreateSymlink(ALinkPath, ATargetPath, True, AError);
    lkHardlink: Result := DoCreateHardlink(ALinkPath, ATargetPath, AError);
    lkJunction: Result := DoCreateJunction(ALinkPath, ATargetPath, AError);
  else
    Result := False;
    AError := TVfsError.Make(vecNotSupported, 'Unknown link kind', PathToFileUri(ALinkPath));
  end;
end;

end.
