unit uPlatformUpdate;

{ OS services the self-updater needs (Windows build). The Posix build lives
  in Platform\Posix; each project puts exactly one of the two directories on
  its unit search path. }

interface

/// <summary>Major.Minor.Release[.Build] of the program file; '' when it has no
/// version information. The build number is left out when it is 0.</summary>
function PlatformFileVersion(const AExeFile: string): string;

/// <summary>Ending of the release package name for this platform
/// (-win64.zip, -linux-x64.tar.gz).</summary>
function PlatformUpdateAssetSuffix: string;

/// <summary>Name of the program file a package must hold at its top level.</summary>
function PlatformUpdateMainFile: string;

/// <summary>Unpacks APackage into the existing folder AStagingDir; the top
/// folder of a tar.gz package is dropped. Refuses entries that would land
/// outside AStagingDir.</summary>
function PlatformUnpackPackage(const APackage, AStagingDir: string;
  out AError: string): Boolean;

/// <summary>Renames or moves a file, also across volumes. With AReplace an
/// existing destination is overwritten; without it the move fails instead.</summary>
function PlatformMoveFile(const ASource, ADest: string; AReplace: Boolean;
  out AError: string): Boolean;

/// <summary>True when a file can be created in ADir.</summary>
/// <summary>Windows packages are zip archives the program updates itself: always False.</summary>
function PlatformUpdatesManagedByPackage(const AAppDir: string): Boolean;

function PlatformCanWriteToDir(const ADir: string): Boolean;

function PlatformCurrentProcessId: Cardinal;

/// <summary>Starts AExeFile with AArguments as a separate process in its own
/// folder; it outlives the caller.</summary>
function PlatformStartProcess(const AExeFile, AArguments: string;
  out AError: string): Boolean;

/// <summary>Nothing to do here: the process PlatformStartProcess starts is
/// already running. The POSIX build starts its program from this call.</summary>
procedure PlatformExecPendingStart;

/// <summary>Waits until the process has exited or ATimeoutMs passed.</summary>
procedure PlatformWaitForProcess(APid: Cardinal; ATimeoutMs: Cardinal);

implementation

uses
  System.SysUtils, System.IOUtils, System.Zip, Winapi.Windows;

function PlatformFileVersion(const AExeFile: string): string;
var
  Handle, Size, Len: DWORD;
  Buf: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(AExeFile), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(AExeFile), 0, Size, @Buf[0]) then
    Exit;
  if not VerQueryValue(@Buf[0], '\', Pointer(Info), Len) or (Len < SizeOf(TVSFixedFileInfo)) then
    Exit;
  Result := Format('%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
    HiWord(Info.dwFileVersionLS)]);
  if LoWord(Info.dwFileVersionLS) <> 0 then
    Result := Result + '.' + IntToStr(LoWord(Info.dwFileVersionLS));
end;

function PlatformUpdateAssetSuffix: string;
begin
  Result := '-win64.zip';
end;

function PlatformUpdateMainFile: string;
begin
  Result := 'MTN2.exe';
end;

function PlatformUnpackPackage(const APackage, AStagingDir: string;
  out AError: string): Boolean;
var
  Zip: TZipFile;
  I: Integer;
  Name, Full, Root: string;
begin
  Result := False;
  AError := '';
  try
    Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(AStagingDir));
    Zip := TZipFile.Create;
    try
      Zip.Open(APackage, zmRead);
      for I := 0 to Zip.FileCount - 1 do
      begin
        Name := StringReplace(Zip.FileNames[I], '/', PathDelim, [rfReplaceAll]);
        Full := TPath.GetFullPath(TPath.Combine(Root, Name));
        if not Full.StartsWith(Root, True) then
        begin
          AError := 'unsafe path in package: ' + Zip.FileNames[I];
          Exit;
        end;
      end;
      Zip.ExtractAll(AStagingDir);
    finally
      Zip.Free;
    end;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

function PlatformMoveFile(const ASource, ADest: string; AReplace: Boolean;
  out AError: string): Boolean;
var
  Flags: DWORD;
begin
  AError := '';
  if AReplace then
    Flags := MOVEFILE_REPLACE_EXISTING or MOVEFILE_COPY_ALLOWED
  else
    Flags := 0;
  Result := MoveFileEx(PChar(ASource), PChar(ADest), Flags);
  if not Result then
    AError := SysErrorMessage(GetLastError);
end;

function PlatformUpdatesManagedByPackage(const AAppDir: string): Boolean;
begin
  Result := False;
end;

function PlatformCanWriteToDir(const ADir: string): Boolean;
var
  Probe: string;
  H: THandle;
begin
  Probe := TPath.Combine(ADir, '.mtn2-write-probe-' + IntToStr(GetCurrentProcessId));
  H := CreateFile(PChar(Probe), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY or FILE_FLAG_DELETE_ON_CLOSE, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(H);
end;

function PlatformCurrentProcessId: Cardinal;
begin
  Result := GetCurrentProcessId;
end;

function PlatformStartProcess(const AExeFile, AArguments: string;
  out AError: string): Boolean;
var
  Cmd: string;
  Si: TStartupInfo;
  Pi: TProcessInformation;
begin
  AError := '';
  Cmd := Format('"%s" %s', [AExeFile, AArguments]);
  UniqueString(Cmd);
  ZeroMemory(@Si, SizeOf(Si));
  Si.cb := SizeOf(Si);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil,
    PChar(ExtractFileDir(AExeFile)), Si, Pi);
  if Result then
  begin
    CloseHandle(Pi.hThread);
    CloseHandle(Pi.hProcess);
  end
  else
    AError := SysErrorMessage(GetLastError);
end;

procedure PlatformExecPendingStart;
begin
end;

procedure PlatformWaitForProcess(APid: Cardinal; ATimeoutMs: Cardinal);
var
  H: THandle;
begin
  H := OpenProcess(SYNCHRONIZE, False, APid);
  if H <> 0 then
  begin
    WaitForSingleObject(H, ATimeoutMs);
    CloseHandle(H);
  end;
end;

end.
