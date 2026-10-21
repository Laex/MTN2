unit uPlatformDrives;

{ Volumes of the machine (Windows build: drive letters). The Posix build lives
  in Platform\Posix; each project puts exactly one of the two directories on
  its unit search path. }

interface

uses
  uDriveTypes;

/// <summary>Letter, root and kind of every volume. Never touches the volume
/// itself, so an unresponsive network share cannot block it.</summary>
function PlatformListDrives: TDriveInfoArray;

/// <summary>Letter, root and kind of the volume with this letter; False when
/// there is none. Same blocking guarantee as PlatformListDrives.</summary>
function PlatformDriveByLetter(ALetter: Char; out AInfo: TDriveInfo): Boolean;

/// <summary>Letter of the volume that holds APath; #0 for a path outside any
/// volume (UNC, relative, empty).</summary>
function PlatformDriveLetterOfPath(const APath: string): Char;

/// <summary>Fills file system, label, serial number and sizes. Queries the
/// volume, so it can block for a long time on an unresponsive network share.</summary>
procedure PlatformFillDriveDetails(var AInfo: TDriveInfo);

/// <summary>Ends the calling thread at once, without any RTL cleanup. For a
/// worker that wakes up after the heap has been finalized.</summary>
procedure PlatformAbandonThread;

/// <summary>True for a volume that can be taken offline from the program: a
/// removable drive, an optical drive or a mapped network drive, never the
/// drive Windows is installed on. Does not touch the volume.</summary>
function PlatformCanDisconnectDrive(const AInfo: TDriveInfo): Boolean;

/// <summary>Takes the volume offline: ejects a removable or optical drive,
/// drops a mapped network drive. Blocks while the system waits for open
/// files, so call it off the UI thread. AError explains a failure.</summary>
function PlatformDisconnectDrive(const AInfo: TDriveInfo; out AError: string): Boolean;

implementation

uses
  System.SysUtils, Winapi.Windows;

function DriveKindLabel(ADriveType: Cardinal): string;
begin
  case ADriveType of
    DRIVE_REMOVABLE: Result := 'Removable';
    DRIVE_FIXED:     Result := 'Hard disk';
    DRIVE_REMOTE:    Result := 'Network';
    DRIVE_CDROM:     Result := 'CD-ROM';
    DRIVE_RAMDISK:   Result := 'RAM';
  else
    Result := '';
  end;
end;

function RemoteConnectionName(const ARoot: string): string;
var
  Buf: array[0..512] of Char;
  Len: DWORD;
begin
  Result := '';
  Len := Length(Buf);
  FillChar(Buf, SizeOf(Buf), 0);
  if WNetGetConnection(PChar(Copy(ARoot, 1, 2)), Buf, Len) = NO_ERROR then
    Result := string(Buf);
end;

procedure ClearInfo(out AInfo: TDriveInfo);
begin
  AInfo.Letter := #0;
  AInfo.RootPath := '';
  AInfo.KindLabel := '';
  AInfo.FsName := '';
  AInfo.LabelOrPath := '';
  AInfo.TotalBytes := 0;
  AInfo.FreeBytes := 0;
  AInfo.SerialNumber := 0;
  AInfo.VolumeFlags := 0;
end;

function PlatformDriveByLetter(ALetter: Char; out AInfo: TDriveInfo): Boolean;
var
  Dt: Cardinal;
begin
  ClearInfo(AInfo);
  AInfo.Letter := UpCase(ALetter);
  AInfo.RootPath := AInfo.Letter + ':' + PathDelim;
  Dt := GetDriveType(PChar(AInfo.RootPath));
  Result := Dt <> DRIVE_NO_ROOT_DIR;
  if Result then
    AInfo.KindLabel := DriveKindLabel(Dt);
end;

function PlatformListDrives: TDriveInfoArray;
var
  Buf: array[0..512] of Char;
  P: PChar;
  Root: string;
  Info: TDriveInfo;
  N: Integer;
begin
  SetLength(Result, 0);
  FillChar(Buf, SizeOf(Buf), 0);
  if GetLogicalDriveStrings(Length(Buf) - 1, Buf) = 0 then
    Exit;
  P := Buf;
  while P^ <> #0 do
  begin
    Root := string(P);
    if (Length(Root) >= 2) and (Root[2] = ':') and
       PlatformDriveByLetter(Root[1], Info) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Info;
    end;
    Inc(P, StrLen(P) + 1);
  end;
end;

function PlatformDriveLetterOfPath(const APath: string): Char;
begin
  if (Length(APath) >= 2) and (APath[2] = ':') then
    Result := UpCase(APath[1])
  else
    Result := #0;
end;

procedure PlatformFillDriveDetails(var AInfo: TDriveInfo);
var
  VolName, FsName: array[0..255] of Char;
  Serial, MaxComp, Flags: DWORD;
  FreeAvail, TotalBytes, TotalFree: Int64;
begin
  FillChar(VolName, SizeOf(VolName), 0);
  FillChar(FsName, SizeOf(FsName), 0);
  Serial := 0;
  MaxComp := 0;
  Flags := 0;
  AInfo.SerialNumber := 0;
  try
    if GetVolumeInformation(PChar(AInfo.RootPath), VolName, Length(VolName),
      @Serial, MaxComp, Flags, FsName, Length(FsName)) then
    begin
      AInfo.FsName := string(FsName);
      AInfo.LabelOrPath := string(VolName);
      AInfo.SerialNumber := Serial;
      AInfo.VolumeFlags := Flags;
    end
    else
    begin
      AInfo.FsName := '';
      AInfo.LabelOrPath := '';
      AInfo.VolumeFlags := 0;
    end;
  except
    AInfo.FsName := '';
    AInfo.LabelOrPath := '';
  end;

  if AInfo.KindLabel = 'Network' then
  begin
    AInfo.LabelOrPath := RemoteConnectionName(AInfo.RootPath);
    if AInfo.LabelOrPath = '' then
      AInfo.LabelOrPath := AInfo.RootPath;
  end;

  AInfo.TotalBytes := 0;
  AInfo.FreeBytes := 0;
  try
    FreeAvail := 0;
    TotalBytes := 0;
    TotalFree := 0;
    if GetDiskFreeSpaceEx(PChar(AInfo.RootPath), FreeAvail, TotalBytes, @TotalFree) then
    begin
      AInfo.TotalBytes := TotalBytes;
      AInfo.FreeBytes := FreeAvail;
    end;
  except
    AInfo.TotalBytes := 0;
    AInfo.FreeBytes := 0;
  end;
end;

procedure PlatformAbandonThread;
begin
  ExitThread(0);
end;

function PlatformCanDisconnectDrive(const AInfo: TDriveInfo): Boolean;
var
  Buf: array[0..MAX_PATH] of Char;
  N: Cardinal;
begin
  Result := False;
  if (AInfo.Letter < 'A') or (AInfo.Letter > 'Z') then
    Exit;
  if (AInfo.KindLabel <> 'Removable') and (AInfo.KindLabel <> 'CD-ROM') and
     (AInfo.KindLabel <> 'Network') then
    Exit;
  N := GetWindowsDirectory(Buf, Length(Buf));
  if (N >= 2) and (UpCase(Buf[0]) = AInfo.Letter) then
    Exit;
  Result := True;
end;

function ErrorTextOf(ACode: Cardinal): string;
begin
  Result := Trim(SysErrorMessage(ACode));
  if Result = '' then
    Result := Format('Error %d', [ACode]);
end;

function DisconnectNetworkDrive(const AInfo: TDriveInfo; out AError: string): Boolean;
var
  Code: Cardinal;
begin
  // Not forced: a drive with open files stays connected and says so.
  Code := WNetCancelConnection2(PChar(AInfo.Letter + ':'), 0, False);
  Result := Code = NO_ERROR;
  if not Result then
    AError := ErrorTextOf(Code);
end;

function EjectVolume(const AInfo: TDriveInfo; out AError: string): Boolean;
const
  cLockVolume = $00090018;
  cDismountVolume = $00090020;
  cStorageMediaRemoval = $002D4804;
  cStorageEjectMedia = $002D4808;
  cLockTries = 5;
  cLockPauseMs = 300;
type
  TPreventRemoval = record
    PreventMediaRemoval: ByteBool;
  end;
var
  H: THandle;
  Bytes: Cardinal;
  Prevent: TPreventRemoval;
  Tries: Integer;
  Locked: Boolean;
  Code: Cardinal;
begin
  Result := False;
  H := CreateFile(PChar('\\.\' + AInfo.Letter + ':'), GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AError := ErrorTextOf(GetLastError);
    Exit;
  end;
  try
    // The lock fails while any program still has a file or folder of the
    // volume open; a few short retries ride out a handle that is closing.
    Locked := False;
    for Tries := 1 to cLockTries do
    begin
      if DeviceIoControl(H, cLockVolume, nil, 0, nil, 0, Bytes, nil) then
      begin
        Locked := True;
        Break;
      end;
      Sleep(cLockPauseMs);
    end;
    if not Locked then
    begin
      AError := ErrorTextOf(GetLastError);
      Exit;
    end;
    if not DeviceIoControl(H, cDismountVolume, nil, 0, nil, 0, Bytes, nil) then
    begin
      AError := ErrorTextOf(GetLastError);
      Exit;
    end;
    Prevent.PreventMediaRemoval := False;
    DeviceIoControl(H, cStorageMediaRemoval, @Prevent, SizeOf(Prevent), nil, 0, Bytes, nil);
    if DeviceIoControl(H, cStorageEjectMedia, nil, 0, nil, 0, Bytes, nil) then
      Exit(True);
    Code := GetLastError;
    // A flash drive has no media to eject: it is dismounted and safe to pull.
    if (Code = ERROR_INVALID_FUNCTION) or (Code = ERROR_NOT_SUPPORTED) then
      Exit(True);
    AError := ErrorTextOf(Code);
  finally
    CloseHandle(H);
  end;
end;

function PlatformDisconnectDrive(const AInfo: TDriveInfo; out AError: string): Boolean;
begin
  AError := '';
  if not PlatformCanDisconnectDrive(AInfo) then
  begin
    AError := 'This drive cannot be disconnected';
    Exit(False);
  end;
  if AInfo.KindLabel = 'Network' then
    Result := DisconnectNetworkDrive(AInfo, AError)
  else
    Result := EjectVolume(AInfo, AError);
end;

end.
