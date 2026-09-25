unit uSingleInstance;

{ Stage 28: single-instance IPC (mtn2 <path>). A named mutex detects whether
  another MTN2 instance already holds it; the first instance publishes its
  own window handle into a small named file mapping (not FindWindow by class
  or caption -- FMX's window class name isn't a stable contract to hardcode
  against, and the caption is dynamic/path-dependent) so a second instance
  can read it directly and forward its path via WM_COPYDATA before exiting
  without ever creating a UI. Both names are Local\ (per-desktop-session),
  not Global\ -- this is a per-user desktop app, not a Terminal-Services-
  shared one. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils;

/// <summary>Creates (or opens) the well-known mutex. Result is False only on
/// an unexpected OS failure (AAlreadyRunning is meaningless then); otherwise
/// True with AAlreadyRunning reporting whether another instance already held
/// it. The mutex handle is held for the process lifetime (leaked
/// deliberately -- Windows reclaims it on exit; ReleaseSingleInstance closes
/// it explicitly for hygiene, see unit comment).</summary>
function TryAcquireSingleInstance(out AAlreadyRunning: Boolean): Boolean;

/// <summary>Closes the mutex/file-mapping handles. Not required for
/// correctness (process exit reclaims them regardless) -- called on clean
/// shutdown to match this codebase's explicit-cleanup habit.</summary>
procedure ReleaseSingleInstance;

/// <summary>Publishes AHwnd into the file mapping so a second instance can
/// find this window. Call once the native window handle is valid (first
/// FormShow, alongside the existing EnsureShutdownHook).</summary>
procedure PublishInstanceWindow(AHwnd: HWND);

/// <summary>Reads the published HWND and validates it with IsWindow --
/// returns False (not just an invalid handle) if the first instance hasn't
/// published yet (narrow startup race) or the mapping doesn't exist, so
/// callers can fall back to a normal start instead of silently dropping the
/// user's path.</summary>
function TryFindExistingInstanceWindow(out AHwnd: HWND): Boolean;

/// <summary>Sends APath to AHwnd via a blocking WM_COPYDATA -- delivery is
/// confirmed before the caller (the delegating second instance) exits.</summary>
procedure SendActivateRequest(AHwnd: HWND; const APath: string);

implementation

const
  cMutexName = 'Local\MTN2_SingleInstance_Mutex_7F3E9B2A-8C41-4B0D-9E5A-2D6F1A9C3B7E';
  cMapName   = 'Local\MTN2_SingleInstance_Hwnd_7F3E9B2A-8C41-4B0D-9E5A-2D6F1A9C3B7E';

type
  PHWND = ^HWND;

var
  GMutex: THandle = 0;
  GMap: THandle = 0;

function TryAcquireSingleInstance(out AAlreadyRunning: Boolean): Boolean;
begin
  AAlreadyRunning := False;
  GMutex := CreateMutex(nil, False, cMutexName);
  if GMutex = 0 then
    Exit(False);
  AAlreadyRunning := GetLastError = ERROR_ALREADY_EXISTS;
  Result := True;
end;

procedure ReleaseSingleInstance;
begin
  if GMap <> 0 then
  begin
    CloseHandle(GMap);
    GMap := 0;
  end;
  if GMutex <> 0 then
  begin
    CloseHandle(GMutex);
    GMutex := 0;
  end;
end;

procedure PublishInstanceWindow(AHwnd: HWND);
var
  P: PHWND;
begin
  if GMap = 0 then
    GMap := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0,
      SizeOf(HWND), cMapName);
  if GMap = 0 then
    Exit;
  P := MapViewOfFile(GMap, FILE_MAP_WRITE, 0, 0, SizeOf(HWND));
  if P = nil then
    Exit;
  try
    P^ := AHwnd;
  finally
    UnmapViewOfFile(P);
  end;
end;

function TryFindExistingInstanceWindow(out AHwnd: HWND): Boolean;
var
  Map: THandle;
  P: PHWND;
begin
  AHwnd := 0;
  Result := False;
  Map := OpenFileMapping(FILE_MAP_READ, False, cMapName);
  if Map = 0 then
    Exit;
  try
    P := MapViewOfFile(Map, FILE_MAP_READ, 0, 0, SizeOf(HWND));
    if P = nil then
      Exit;
    try
      AHwnd := P^;
    finally
      UnmapViewOfFile(P);
    end;
  finally
    CloseHandle(Map);
  end;
  Result := (AHwnd <> 0) and IsWindow(AHwnd);
end;

procedure SendActivateRequest(AHwnd: HWND; const APath: string);
var
  Cds: TCopyDataStruct;
begin
  Cds.dwData := 0;
  Cds.cbData := (Length(APath) + 1) * SizeOf(Char);
  Cds.lpData := PChar(APath);
  SendMessage(AHwnd, WM_COPYDATA, 0, LPARAM(@Cds));
end;

end.
