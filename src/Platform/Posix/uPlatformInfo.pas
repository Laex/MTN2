unit uPlatformInfo;

{ Small OS queries that differ per platform (Posix build). The Windows build
  lives in Platform\Windows; each project puts exactly one of the two
  directories on its unit search path. }

interface

/// <summary>Code page of the console's legacy "OEM" encoding (866 on a
/// Russian system); 65001 where there is no such notion.</summary>
function PlatformOemCodePage: Integer;

/// <summary>Languages the user prefers for the OS interface, best first, as
/// BCP 47 style tags ("ru-RU", "zh-Hans-CN"); empty when unknown.</summary>
function PlatformPreferredUiLanguages: TArray<string>;

/// <summary>Maximum delay in milliseconds between the clicks of a double
/// click.</summary>
function PlatformDoubleClickMs: Cardinal;

/// <summary>Shortens APath to at most AMaxLen characters with the platform's
/// own "..." convention (the Windows shell's PathCompactPathEx); '' when the
/// platform has none, so the caller falls back to its own shortening.</summary>
function PlatformCompactPath(const APath: string; AMaxLen: Integer): string;

/// <summary>True when the dynamic library at APath loads.</summary>
function PlatformCanLoadLibrary(const APath: string): Boolean;

/// <summary>Writes UTF-8 text to the process's standard output, attaching to
/// the parent's console when the program has none of its own.</summary>
procedure PlatformWriteStdOut(const AText: string);

/// <summary>File name of a native library called ABaseName: "wasmtime.dll"
/// or "libwasmtime.so".</summary>
function PlatformSharedLibName(const ABaseName: string): string;

/// <summary>Loads a dynamic library; 0 when it cannot be loaded (see
/// PlatformLibraryError).</summary>
function PlatformLoadLibrary(const APath: string): NativeUInt;
procedure PlatformFreeLibrary(AHandle: NativeUInt);
/// <summary>The address of an exported symbol, or nil.</summary>
function PlatformGetProc(AHandle: NativeUInt; const AName: string): Pointer;
/// <summary>Why the last PlatformLoadLibrary failed, as text.</summary>
function PlatformLibraryError: string;

/// <summary>Free bytes available to the caller and total bytes of the volume
/// that holds APath; False when they cannot be determined.</summary>
function PlatformDiskSpace(const APath: string; out AFree, ATotal: Int64): Boolean;

/// <summary>Milliseconds since an arbitrary fixed moment (system start on
/// Windows); only differences are meaningful.</summary>
function PlatformTickCount64: UInt64;

/// <summary>True while the physical key with the given virtual-key code is
/// held down; False where the state cannot be queried.</summary>
function PlatformKeyIsDown(AVirtualKey: Word): Boolean;

/// <summary>Extension of native libraries including the dot: ".dll" or ".so".</summary>
function PlatformSharedLibExt: string;

/// <summary>Changes whenever the contents of the system clipboard change; a
/// constant where the platform cannot tell.</summary>
function PlatformClipboardSequence: Cardinal;

/// <summary>The directory of the user's settings files for a normal
/// (not portable) installation.</summary>
function PlatformConfigDir: string;

/// <summary>Ends the process at once, without finalization sections.</summary>
procedure PlatformTerminateNow(ACode: Integer);

/// <summary>The whole text of a small file, '' when it cannot be read. Reads
/// until end of file, so it also serves the files of /proc, which report a size
/// of zero.</summary>
function PlatformReadTextFile(const APath: string): string;

/// <summary>Compares two runs of text (1-based start, length), ignoring case,
/// the way the system sorts names; -1, 0 or 1. '-' and apostrophes stay
/// significant, so "a-b" and "ab" differ.</summary>
function PlatformCompareTextRun(const ALeft: string; ALeftStart, ALeftLen: Integer;
  const ARight: string; ARightStart, ARightLen: Integer): Integer;

/// <summary>File name of the library the graphical drawing needs next to the
/// program (the Skia library); '' where the program draws nothing itself.</summary>
function PlatformRenderLibrary: string;

implementation

uses
  System.SysUtils, System.IOUtils, System.Diagnostics, Posix.Base, Posix.Dlfcn, Posix.Unistd,
  Posix.SysStatvfs, uSystemClipboard;

function PlatformRenderLibrary: string;
begin
  Result := '';
end;

procedure c_exit(AStatus: Integer); cdecl; external libc name '_exit';
function c_open(APath: MarshaledAString; AFlags: Integer): Integer; cdecl;
  external libc name 'open';
function c_read(AFd: Integer; ABuf: Pointer; ACount: NativeUInt): NativeInt; cdecl;
  external libc name 'read';
function c_close(AFd: Integer): Integer; cdecl; external libc name 'close';

function PlatformCompareTextRun(const ALeft: string; ALeftStart, ALeftLen: Integer;
  const ARight: string; ARightStart, ARightLen: Integer): Integer;
begin
  Result := CompareText(Copy(ALeft, ALeftStart, ALeftLen),
    Copy(ARight, ARightStart, ARightLen), TLocaleOptions.loUserLocale);
  if Result < 0 then
    Result := -1
  else if Result > 0 then
    Result := 1;
end;

function PlatformReadTextFile(const APath: string): string;
var
  Fd: Integer;
  Path: UTF8String;
  Buf: TBytes;
  Chunk: array[0..4095] of Byte;
  N: NativeInt;
  Len: Integer;
begin
  Result := '';
  Path := UTF8String(APath);
  Fd := c_open(MarshaledAString(Path), 0);
  if Fd < 0 then
    Exit;
  try
    Len := 0;
    repeat
      N := c_read(Fd, @Chunk[0], SizeOf(Chunk));
      if N > 0 then
      begin
        SetLength(Buf, Len + N);
        Move(Chunk[0], Buf[Len], N);
        Inc(Len, N);
      end;
    until N <= 0;
  finally
    c_close(Fd);
  end;
  Result := TEncoding.UTF8.GetString(Buf, 0, Len);
end;

procedure PlatformTerminateNow(ACode: Integer);
begin
  c_exit(ACode);
end;

function PlatformConfigDir: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base = '' then
    Base := TPath.Combine(GetEnvironmentVariable('HOME'), '.config');
  Result := TPath.Combine(Base, 'mtn2');
end;

function PlatformClipboardSequence: Cardinal;
begin
  Result := SystemFileClipSignature;
end;

function PlatformSharedLibExt: string;
begin
  Result := '.so';
end;

function PlatformKeyIsDown(AVirtualKey: Word): Boolean;
begin
  Result := False;
end;

function PlatformTickCount64: UInt64;
begin
  Result := UInt64(TStopwatch.GetTimeStamp) * 1000 div UInt64(TStopwatch.Frequency);
end;

function PlatformOemCodePage: Integer;
begin
  Result := 65001;
end;

// LANGUAGE is a colon-separated list; LC_ALL, LC_MESSAGES and LANG hold one
// locale name ("ru_RU.UTF-8", "zh_CN@modifier"). "C" and "POSIX" name no language.
function PlatformPreferredUiLanguages: TArray<string>;
var
  Name, Item, Tag: string;
  Items: TArray<string>;
  Dot: Integer;

  procedure Add(const AValue: string);
  begin
    Tag := AValue;
    Dot := Pos('.', Tag);
    if Dot > 0 then
      Tag := Copy(Tag, 1, Dot - 1);
    Dot := Pos('@', Tag);
    if Dot > 0 then
      Tag := Copy(Tag, 1, Dot - 1);
    Tag := StringReplace(Trim(Tag), '_', '-', [rfReplaceAll]);
    if (Tag = '') or SameText(Tag, 'C') or SameText(Tag, 'POSIX') then
      Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Tag;
  end;

begin
  SetLength(Result, 0);
  Items := GetEnvironmentVariable('LANGUAGE').Split([':']);
  for Item in Items do
    Add(Item);
  for Name in TArray<string>.Create('LC_ALL', 'LC_MESSAGES', 'LANG') do
    Add(GetEnvironmentVariable(Name));
end;

function PlatformDoubleClickMs: Cardinal;
begin
  Result := 500;
end;

function PlatformCompactPath(const APath: string; AMaxLen: Integer): string;
begin
  Result := '';
end;

function PlatformCanLoadLibrary(const APath: string): Boolean;
var
  Handle: NativeUInt;
begin
  Handle := dlopen(MarshaledAString(UTF8String(APath)), RTLD_LAZY);
  Result := Handle <> 0;
  if Result then
    dlclose(Handle);
end;

function PlatformSharedLibName(const ABaseName: string): string;
begin
  Result := 'lib' + ABaseName + '.so';
end;

function PlatformLoadLibrary(const APath: string): NativeUInt;
begin
  Result := dlopen(MarshaledAString(UTF8String(APath)), RTLD_NOW);
end;

procedure PlatformFreeLibrary(AHandle: NativeUInt);
begin
  dlclose(AHandle);
end;

function PlatformGetProc(AHandle: NativeUInt; const AName: string): Pointer;
begin
  Result := dlsym(AHandle, MarshaledAString(UTF8String(AName)));
end;

function PlatformLibraryError: string;
begin
  Result := UTF8ToString(dlerror);
end;

function PlatformDiskSpace(const APath: string; out AFree, ATotal: Int64): Boolean;
var
  St: _statvfs;
  Path: UTF8String;
begin
  AFree := 0;
  ATotal := 0;
  Path := UTF8String(APath);
  Result := statvfs(MarshaledAString(Path), St) = 0;
  if Result then
  begin
    AFree := Int64(St.f_bavail) * Int64(St.f_frsize);
    ATotal := Int64(St.f_blocks) * Int64(St.f_frsize);
  end;
end;

procedure PlatformWriteStdOut(const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > 0 then
    __write(1, @Bytes[0], Length(Bytes));
end;

end.
