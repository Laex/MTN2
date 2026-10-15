unit uPlatformInfo;

{ Small OS queries that differ per platform (Windows build). The Posix build
  lives in Platform\Posix; each project puts exactly one of the two
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
  System.SysUtils, System.IOUtils, Winapi.Windows, Winapi.ShLwApi;

function MtnGetUserPreferredUILanguages(AFlags: DWORD; ANumLanguages: PULONG;
  ALanguagesBuffer: PWideChar; ABufferChars: PULONG): BOOL; stdcall;
  external kernel32 name 'GetUserPreferredUILanguages';

function PlatformPreferredUiLanguages: TArray<string>;
const
  cMuiLanguageName = $8;
var
  Num, Len: ULONG;
  Buf: TArray<WideChar>;
  P: PWideChar;
begin
  SetLength(Result, 0);
  Num := 0;
  Len := 0;
  if not MtnGetUserPreferredUILanguages(cMuiLanguageName, @Num, nil, @Len) or (Len = 0) then
    Exit;
  SetLength(Buf, Len);
  if not MtnGetUserPreferredUILanguages(cMuiLanguageName, @Num, PWideChar(Buf), @Len) then
    Exit;
  // A list of zero-terminated names closed by an empty one.
  P := PWideChar(Buf);
  while P^ <> #0 do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := P;
    Inc(P, StrLen(P) + 1);
  end;
end;

function PlatformCompareTextRun(const ALeft: string; ALeftStart, ALeftLen: Integer;
  const ARight: string; ARightStart, ARightLen: Integer): Integer;
begin
  Result := CompareStringW(LOCALE_USER_DEFAULT, NORM_IGNORECASE or SORT_STRINGSORT,
    PChar(ALeft) + ALeftStart - 1, ALeftLen,
    PChar(ARight) + ARightStart - 1, ARightLen) - CSTR_EQUAL;
  if Result < 0 then
    Result := -1
  else if Result > 0 then
    Result := 1;
end;

function PlatformReadTextFile(const APath: string): string;
begin
  try
    Result := TFile.ReadAllText(APath);
  except
    Result := '';
  end;
end;

function PlatformRenderLibrary: string;
begin
  Result := 'sk4d.dll';
end;

procedure PlatformTerminateNow(ACode: Integer);
begin
  ExitProcess(ACode);
end;

function PlatformConfigDir: string;
var
  AppDataDir: string;
begin
  AppDataDir := GetEnvironmentVariable('APPDATA');
  if AppDataDir = '' then
    AppDataDir := TPath.GetHomePath;
  Result := TPath.Combine(AppDataDir, 'MTN2');
end;

function PlatformClipboardSequence: Cardinal;
begin
  Result := GetClipboardSequenceNumber;
end;

function PlatformSharedLibExt: string;
begin
  Result := '.dll';
end;

function PlatformKeyIsDown(AVirtualKey: Word): Boolean;
begin
  Result := GetAsyncKeyState(AVirtualKey) < 0;
end;

function PlatformTickCount64: UInt64;
begin
  Result := GetTickCount64;
end;

function PlatformOemCodePage: Integer;
begin
  Result := Integer(GetOEMCP);
end;

function PlatformDoubleClickMs: Cardinal;
begin
  Result := GetDoubleClickTime;
end;

function PlatformCompactPath(const APath: string; AMaxLen: Integer): string;
var
  Buf: string;
begin
  Result := '';
  SetLength(Buf, AMaxLen);
  if PathCompactPathEx(PChar(Buf), PChar(APath), Cardinal(AMaxLen) + 1, 0) then
    Result := PChar(Buf);
end;

function PlatformCanLoadLibrary(const APath: string): Boolean;
var
  Handle: HMODULE;
begin
  Handle := LoadLibrary(PChar(APath));
  Result := Handle <> 0;
  if Result then
    FreeLibrary(Handle);
end;

function PlatformSharedLibName(const ABaseName: string): string;
begin
  Result := ABaseName + '.dll';
end;

function PlatformLoadLibrary(const APath: string): NativeUInt;
begin
  Result := LoadLibrary(PChar(APath));
end;

procedure PlatformFreeLibrary(AHandle: NativeUInt);
begin
  FreeLibrary(AHandle);
end;

function PlatformGetProc(AHandle: NativeUInt; const AName: string): Pointer;
begin
  Result := GetProcAddress(AHandle, PChar(AName));
end;

function PlatformLibraryError: string;
begin
  Result := Format('GetLastError=%d', [GetLastError]);
end;

function PlatformDiskSpace(const APath: string; out AFree, ATotal: Int64): Boolean;
var
  Drive: string;
  Avail, Total: UInt64;
begin
  AFree := 0;
  ATotal := 0;
  Drive := ExtractFileDrive(APath);
  if Drive = '' then
    Exit(False);
  Drive := IncludeTrailingPathDelimiter(Drive);
  Result := GetDiskFreeSpaceEx(PChar(Drive), Avail, Total, nil);
  if Result then
  begin
    AFree := Int64(Avail);
    ATotal := Int64(Total);
  end;
end;

procedure PlatformWriteStdOut(const AText: string);
var
  Handle: THandle;
  Bytes: TBytes;
  Written: DWORD;
begin
  // A GUI-subsystem exe has no console of its own: stdout is whatever the
  // caller redirected, else the parent's console if there is one.
  Handle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
  begin
    if not AttachConsole(ATTACH_PARENT_PROCESS) then
      Exit;
    Handle := GetStdHandle(STD_OUTPUT_HANDLE);
    if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
      Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > 0 then
    WriteFile(Handle, Bytes[0], Length(Bytes), Written, nil);
end;

end.
