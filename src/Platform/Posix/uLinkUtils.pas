unit uLinkUtils;

{ Symlink and hardlink creation (POSIX build): symlink() and link(). Junctions
  exist only on Windows. The Windows build lives in Platform\Windows; each
  project puts exactly one of the two directories on its unit search path. }

interface

uses
  System.SysUtils, uVfsTypes;

type
  TLinkKind = (lkSymlinkFile, lkSymlinkDir, lkHardlink, lkJunction);

/// <summary>Creates a link at ALinkPath pointing at ATargetPath. Junctions are
/// reported as not supported.</summary>
function CreateFileLink(const ALinkPath, ATargetPath: string; AKind: TLinkKind;
  out AError: TVfsError): Boolean;

/// <summary>True when this process can create symbolic links (always).</summary>
function CanCreateSymlinks: Boolean;

/// <summary>Index of the "Create link" dropdown entry that fits the target: a
/// symlink to a file or to a folder.</summary>
function SuggestLinkTypeIndex(const ATargetPath, ALinkFolder: string): Integer;

/// <summary>True for a symbolic link whose target text can be read.</summary>
function IsRecreatableLink(const APath: string): Boolean;

/// <summary>Creates at ADst a symbolic link with the same target text as the
/// link at ASrc, replacing an existing node when AOverwrite is set. The target
/// is not followed or copied.</summary>
function CopyLinkNode(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;

/// <summary>Removes the link node at APath itself, not its target.</summary>
function DeleteLinkNode(const APath: string; out AError: TVfsError): Boolean;

implementation

uses
  System.IOUtils, Posix.Base, Posix.SysStat;

function c_symlink(ATarget, ALink: MarshaledAString): Integer; cdecl;
  external libc name 'symlink';
function c_readlink(APath, ABuf: MarshaledAString; ASize: NativeUInt): NativeInt; cdecl;
  external libc name 'readlink';
function c_unlink(APath: MarshaledAString): Integer; cdecl;
  external libc name 'unlink';
function c_link(AExisting, ANew: MarshaledAString): Integer; cdecl;
  external libc name 'link';

function CanCreateSymlinks: Boolean;
begin
  Result := True;
end;

function SuggestLinkTypeIndex(const ATargetPath, ALinkFolder: string): Integer;
begin
  Result := Ord(TDirectory.Exists(ATargetPath));
end;

function CreateFileLink(const ALinkPath, ATargetPath: string; AKind: TLinkKind;
  out AError: TVfsError): Boolean;
var
  Target, Link: UTF8String;
begin
  AError := TVfsError.Ok;
  Target := UTF8String(ATargetPath);
  Link := UTF8String(ALinkPath);
  case AKind of
    lkSymlinkFile, lkSymlinkDir:
      begin
        Result := c_symlink(MarshaledAString(Target), MarshaledAString(Link)) = 0;
        if not Result then
          AError := TVfsError.Make(vecIOError,
            'Cannot create symbolic link: ' + SysErrorMessage(GetLastError),
            PathToFileUri(ALinkPath));
      end;
    lkHardlink:
      begin
        Result := c_link(MarshaledAString(Target), MarshaledAString(Link)) = 0;
        if not Result then
          AError := TVfsError.Make(vecIOError,
            'Cannot create hard link: ' + SysErrorMessage(GetLastError),
            PathToFileUri(ALinkPath));
      end;
  else
    Result := False;
    AError := TVfsError.Make(vecNotSupported, 'Junctions are not supported on this system',
      PathToFileUri(ALinkPath));
  end;
end;

function ReadLinkTarget(const APath: string; out ATarget: string): Boolean;
var
  P: UTF8String;
  Buf: TBytes;
  N: NativeInt;
begin
  ATarget := '';
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  SetLength(Buf, 4096);
  N := c_readlink(MarshaledAString(P), MarshaledAString(@Buf[0]), Length(Buf));
  Result := (N > 0) and (N < Length(Buf));
  if Result then
    ATarget := TEncoding.UTF8.GetString(Buf, 0, N);
end;

function IsRecreatableLink(const APath: string): Boolean;
var
  Target: string;
begin
  Result := (APath <> '') and ReadLinkTarget(APath, Target);
end;

function CopyLinkNode(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;
var
  Target: string;
  St: _stat;
  Dst: UTF8String;
begin
  AError := TVfsError.Ok;
  if not ReadLinkTarget(ASrc, Target) then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot read the link target', PathToFileUri(ASrc));
    Exit(False);
  end;
  Dst := UTF8String(ExcludeTrailingPathDelimiter(ADst));
  if lstat(MarshaledAString(Dst), St) = 0 then
  begin
    if not AOverwrite then
    begin
      AError := TVfsError.Make(vecAlreadyExists, 'Destination already exists',
        PathToFileUri(ADst));
      Exit(False);
    end;
    if c_unlink(MarshaledAString(Dst)) <> 0 then
    begin
      AError := TVfsError.Make(vecIOError, 'Cannot replace the destination: ' +
        SysErrorMessage(GetLastError), PathToFileUri(ADst));
      Exit(False);
    end;
  end;
  Result := CreateFileLink(ADst, Target, lkSymlinkFile, AError);
end;

function DeleteLinkNode(const APath: string; out AError: TVfsError): Boolean;
var
  P: UTF8String;
begin
  AError := TVfsError.Ok;
  P := UTF8String(ExcludeTrailingPathDelimiter(APath));
  Result := c_unlink(MarshaledAString(P)) = 0;
  if not Result then
    AError := TVfsError.Make(vecIOError, 'Cannot remove the link: ' +
      SysErrorMessage(GetLastError), PathToFileUri(APath));
end;

end.
