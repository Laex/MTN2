unit uPlatformPaths;

{ File-system queries on a local path (Posix build). The Windows build lives
  in Platform\Windows; each project puts exactly one of the two directories on
  its unit search path. }

interface

/// <summary>True for an existing directory, including a symlink to one.</summary>
function PlatformIsDirectory(const AApiPath: string): Boolean;

/// <summary>True for an existing non-directory.</summary>
function PlatformIsFile(const AApiPath: string): Boolean;

/// <summary>The directory a symlink path finally points at; '' when it cannot
/// be resolved.</summary>
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
  System.SysUtils, Posix.Base, Posix.SysStat;

function realpath(APath, AResolved: MarshaledAString): MarshaledAString; cdecl;
  external libc name 'realpath';

function PlatformPosixPaths: Boolean;
begin
  Result := True;
end;

function PlatformVolumeId(const APath: string): string;
var
  St: _stat;
  P: UTF8String;
  Dir: string;
begin
  Result := '';
  Dir := APath;
  while Dir <> '' do
  begin
    P := UTF8String(Dir);
    if stat(MarshaledAString(P), St) = 0 then
      Exit(IntToStr(Int64(St.st_dev)));
    if (Dir = '/') or (ExtractFileDir(Dir) = Dir) then
      Break;
    Dir := ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
  end;
end;

function StatMode(const AApiPath: string; out AMode: Cardinal): Boolean;
var
  St: _stat;
  P: UTF8String;
begin
  P := UTF8String(AApiPath);
  Result := stat(MarshaledAString(P), St) = 0;
  if Result then
    AMode := St.st_mode;
end;

function PlatformIsDirectory(const AApiPath: string): Boolean;
var
  Mode: Cardinal;
begin
  Result := StatMode(AApiPath, Mode) and ((Mode and S_IFMT) = S_IFDIR);
end;

function PlatformIsFile(const AApiPath: string): Boolean;
var
  Mode: Cardinal;
begin
  Result := StatMode(AApiPath, Mode) and ((Mode and S_IFMT) <> S_IFDIR);
end;

function PlatformFinalDirPath(const AApiPath: string): string;
var
  P: UTF8String;
  Buf: array[0..4096] of AnsiChar;
begin
  Result := '';
  P := UTF8String(AApiPath);
  if realpath(MarshaledAString(P), @Buf[0]) <> nil then
    Result := UTF8ToString(MarshaledAString(@Buf[0]));
end;

end.
