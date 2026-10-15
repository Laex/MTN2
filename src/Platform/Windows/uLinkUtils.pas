unit uLinkUtils;

{ Symlink / hardlink / junction creation (Win32 interop - nothing else in the
  codebase creates links; uVfsTypes.TVfsEntry.IsLink only detects them).

  Symlinks/hardlinks use plain kernel32 calls, declared here explicitly
  (rather than relying on Winapi.Windows to have them, which varies by RTL
  version) so this compiles the same way across Delphi releases. Junctions
  have no direct Win32 call - they're implemented, per the standard
  technique, via DeviceIoControl(FSCTL_SET_REPARSE_POINT) with a hand-built
  REPARSE_DATA_BUFFER (MountPointReparseBuffer layout).

  CROSS-PLATFORM: junctions are NTFS/Windows-only, no POSIX
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
/// elevation/Developer Mode and fails the same way if unavailable - the
/// error message surfaces whatever Windows reports rather than crashing.</summary>
function CreateFileLink(const ALinkPath, ATargetPath: string; AKind: TLinkKind;
  out AError: TVfsError): Boolean;

/// <summary>True when this process can create symbolic links: Developer Mode
/// is on, or the token holds SeCreateSymbolicLinkPrivilege (elevated
/// administrator). Junctions and hard links need neither.</summary>
function CanCreateSymlinks: Boolean;

/// <summary>Index of the "Create link" dropdown entry that fits the target:
/// a symlink when the process may create one, otherwise a junction for a
/// folder, or a hard link for a file on the same drive as the link folder.</summary>
function SuggestLinkTypeIndex(const ATargetPath, ALinkFolder: string): Integer;

/// <summary>True for a symbolic link or junction whose target can be read and
/// recreated elsewhere. Other reparse points (cloud placeholders, dedup
/// stubs) are plain content for a copy and report False.</summary>
function IsRecreatableLink(const APath: string): Boolean;

/// <summary>Creates at ADst a link of the same kind and target as the link
/// at ASrc, replacing an existing node when AOverwrite is set. The target is
/// not followed or copied.</summary>
function CopyLinkNode(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;

/// <summary>Removes the link node at APath itself, not its target.</summary>
function DeleteLinkNode(const APath: string; out AError: TVfsError): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils, System.Win.Registry;

const
  SYMBOLIC_LINK_FLAG_DIRECTORY = $1;
  SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = $2;
  FSCTL_SET_REPARSE_POINT = $000900A4;
  FSCTL_GET_REPARSE_POINT = $000900A8;
  IO_REPARSE_TAG_MOUNT_POINT = DWORD($A0000003);
  IO_REPARSE_TAG_SYMLINK = DWORD($A000000C);
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

function DeveloperModeOn: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock') then
      try
        Result := Reg.ValueExists('AllowDevelopmentWithoutDevLicense') and
          (Reg.ReadInteger('AllowDevelopmentWithoutDevLicense') = 1);
      finally
        Reg.CloseKey;
      end;
  except
    Result := False;
  end;
  Reg.Free;
end;

function TokenHasSymlinkPrivilege: Boolean;
var
  Token: THandle;
  Luid: TLargeInteger;
  Size: DWORD;
  Buf: TBytes;
  Privs: PTokenPrivileges;
  I: Integer;
begin
  Result := False;
  if not LookupPrivilegeValue(nil, 'SeCreateSymbolicLinkPrivilege', Luid) then
    Exit;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    Size := 0;
    GetTokenInformation(Token, TokenPrivileges, nil, 0, Size);
    if Size = 0 then
      Exit;
    SetLength(Buf, Size);
    if not GetTokenInformation(Token, TokenPrivileges, @Buf[0], Size, Size) then
      Exit;
    Privs := PTokenPrivileges(@Buf[0]);
    for I := 0 to Integer(Privs^.PrivilegeCount) - 1 do
      if Int64(Privs^.Privileges[I].Luid) = Luid then
        Exit(True);
  finally
    CloseHandle(Token);
  end;
end;

function CanCreateSymlinks: Boolean;
begin
  Result := DeveloperModeOn or TokenHasSymlinkPrivilege;
end;

function SuggestLinkTypeIndex(const ATargetPath, ALinkFolder: string): Integer;
var
  IsDir: Boolean;
begin
  IsDir := TDirectory.Exists(ATargetPath);
  if CanCreateSymlinks then
    Exit(Ord(IsDir));
  if IsDir then
    Exit(Ord(lkJunction));
  if (ALinkFolder <> '') and SameText(TPath.GetPathRoot(ATargetPath),
       TPath.GetPathRoot(ALinkFolder)) then
    Exit(Ord(lkHardlink));
  Result := Ord(lkSymlinkFile);
end;

function DoCreateSymlink(const ALinkPath, ATargetPath: string; ADirectory: Boolean;
  out AError: TVfsError): Boolean;
var
  Flags: DWORD;
  Msg: string;
begin
  Flags := SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
  if ADirectory then
    Flags := Flags or SYMBOLIC_LINK_FLAG_DIRECTORY;
  Result := Win32CreateSymbolicLinkW(PWideChar(ALinkPath), PWideChar(ATargetPath), Flags);
  if not Result then
    // Older Windows without Developer Mode rejects the unprivileged-create
    // flag outright before even trying - retry without it (still needs
    // SeCreateSymbolicLinkPrivilege/elevation on those systems).
    Result := Win32CreateSymbolicLinkW(PWideChar(ALinkPath), PWideChar(ATargetPath),
      Flags and not SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE);
  if not Result then
  begin
    Msg := 'Cannot create symbolic link: ' + LastErrorMessage;
    if GetLastError = ERROR_PRIVILEGE_NOT_HELD then
      Msg := Msg + '. Enable Developer Mode, run as administrator, or use a junction for folders';
    AError := TVfsError.Make(vecIOError, Msg, PathToFileUri(ALinkPath));
  end;
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

// Reads the reparse data of the link node itself (the target is not opened).
// Offsets follow REPARSE_DATA_BUFFER: both the mount point and the symlink
// layout keep four name offset/length words at byte 8; the path buffer starts
// at byte 16 for a junction and at byte 20 for a symlink (after the flags).
function ReadLinkInfo(const APath: string; out ATarget: string;
  out AKind: TLinkKind): Boolean;
var
  Handle: THandle;
  Buf: TBytes;
  Returned, Tag, Attr: DWORD;
  SubOffset, SubLength, PathStart: Integer;
begin
  Result := False;
  ATarget := '';
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if (Attr = INVALID_FILE_ATTRIBUTES) or ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) = 0) then
    Exit;
  Handle := CreateFileW(PWideChar(WinApiPath(APath)), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Handle = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(Buf, cMaxReparseDataSize);
    if not DeviceIoControl(Handle, FSCTL_GET_REPARSE_POINT, nil, 0, @Buf[0],
         Length(Buf), Returned, nil) then
      Exit;
  finally
    CloseHandle(Handle);
  end;
  if Returned < 20 then
    Exit;
  Tag := PDWORD(@Buf[0])^;
  if Tag = IO_REPARSE_TAG_MOUNT_POINT then
  begin
    PathStart := 16;
    AKind := lkJunction;
  end
  else if Tag = IO_REPARSE_TAG_SYMLINK then
  begin
    PathStart := 20;
    if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
      AKind := lkSymlinkDir
    else
      AKind := lkSymlinkFile;
  end
  else
    Exit;
  SubOffset := PWord(@Buf[8])^;
  SubLength := PWord(@Buf[10])^;
  if (SubLength < SizeOf(WideChar)) or
     (PathStart + SubOffset + SubLength > Integer(Returned)) then
    Exit;
  SetString(ATarget, PWideChar(@Buf[PathStart + SubOffset]), SubLength div SizeOf(WideChar));
  // The substitute name of an absolute target carries the NT namespace prefix.
  if ATarget.StartsWith('\??\UNC\', True) then
    ATarget := '\\' + Copy(ATarget, 9, MaxInt)
  else if ATarget.StartsWith('\??\', True) then
    ATarget := Copy(ATarget, 5, MaxInt);
  Result := ATarget <> '';
end;

function IsRecreatableLink(const APath: string): Boolean;
var
  Target: string;
  Kind: TLinkKind;
begin
  Result := (APath <> '') and ReadLinkInfo(APath, Target, Kind);
end;

function CopyLinkNode(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;
var
  Target: string;
  Kind: TLinkKind;
  Attr: DWORD;
  Removed: Boolean;
begin
  AError := TVfsError.Ok;
  if not ReadLinkInfo(ASrc, Target, Kind) then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot read the link target', PathToFileUri(ASrc));
    Exit(False);
  end;
  Attr := GetFileAttributes(PChar(WinApiPath(ADst)));
  if Attr <> INVALID_FILE_ATTRIBUTES then
  begin
    if not AOverwrite then
    begin
      AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists',
        PathToFileUri(ADst));
      Exit(False);
    end;
    if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
      Removed := RemoveDirectory(PChar(WinApiPath(ADst)))
    else
      Removed := Winapi.Windows.DeleteFile(PChar(WinApiPath(ADst)));
    if not Removed then
    begin
      AError := TVfsError.Make(vecIOError, 'Cannot replace the destination: ' +
        LastErrorMessage, PathToFileUri(ADst));
      Exit(False);
    end;
  end;
  Result := CreateFileLink(ADst, Target, Kind, AError);
end;

function DeleteLinkNode(const APath: string; out AError: TVfsError): Boolean;
var
  Attr: DWORD;
begin
  AError := TVfsError.Ok;
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  if Attr = INVALID_FILE_ATTRIBUTES then
    Exit(True);
  if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
    Result := RemoveDirectory(PChar(WinApiPath(APath)))
  else
    Result := Winapi.Windows.DeleteFile(PChar(WinApiPath(APath)));
  if not Result then
    AError := TVfsError.Make(vecIOError, 'Cannot remove the link: ' + LastErrorMessage,
      PathToFileUri(APath));
end;

end.
