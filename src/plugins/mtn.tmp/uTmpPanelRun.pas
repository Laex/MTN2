unit uTmpPanelRun;

{ Runs a shell command without a window and returns what it printed. Used by
  "Panelize command output"; runs in a worker thread, so it touches no host
  call. }

interface

type
  TStopCheck = reference to function: Boolean;

/// <summary>Runs ACommand through the command interpreter (cmd.exe, or sh on
/// Linux) in AWorkDir and puts
/// its standard output and standard error text in AOutput. False when the
/// process could not be started, or was stopped after ATimeoutMs (AOutput then
/// holds what it printed so far). AShouldStop (may be nil) is polled while the
/// process runs; when it returns True the process is killed and the result is
/// False.</summary>
function RunCommandCapture(const ACommand, AWorkDir: string; ATimeoutMs: Cardinal;
  out AOutput: string; const AShouldStop: TStopCheck = nil): Boolean;

implementation

{$IFDEF MSWINDOWS}

uses
  Winapi.Windows, System.SysUtils, System.Classes;

// UTF-8 when the bytes are valid UTF-8 (git, rg, most modern tools), else the
// console's OEM code page (dir, findstr).
function DecodeOutput(const ABytes: TBytes): string;
var
  N: Integer;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;
  N := MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, @ABytes[0], Length(ABytes), nil, 0);
  if N > 0 then
  begin
    SetLength(Result, N);
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, @ABytes[0], Length(ABytes), PChar(Result), N);
    Exit;
  end;
  N := MultiByteToWideChar(CP_OEMCP, 0, @ABytes[0], Length(ABytes), nil, 0);
  if N <= 0 then
    Exit;
  SetLength(Result, N);
  MultiByteToWideChar(CP_OEMCP, 0, @ABytes[0], Length(ABytes), PChar(Result), N);
end;

function RunCommandCapture(const ACommand, AWorkDir: string; ATimeoutMs: Cardinal;
  out AOutput: string; const AShouldStop: TStopCheck): Boolean;
var
  Sa: TSecurityAttributes;
  ReadPipe, WritePipe, NulIn: THandle;
  Si: TStartupInfo;
  Pi: TProcessInformation;
  CmdLine, Dir, Shell: string;
  Bytes: TBytes;
  Chunk: array[0..16383] of Byte;
  Avail, Got: DWORD;
  Started: UInt64;
  Done: Boolean;
  WorkDirPtr: PChar;

  procedure Drain;
  begin
    while PeekNamedPipe(ReadPipe, nil, 0, nil, @Avail, nil) and (Avail > 0) do
    begin
      if not ReadFile(ReadPipe, Chunk, SizeOf(Chunk), Got, nil) or (Got = 0) then
        Break;
      SetLength(Bytes, Length(Bytes) + Integer(Got));
      Move(Chunk[0], Bytes[Length(Bytes) - Integer(Got)], Got);
    end;
  end;

begin
  AOutput := '';
  Result := False;
  Sa.nLength := SizeOf(Sa);
  Sa.lpSecurityDescriptor := nil;
  Sa.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Sa, 0) then
    Exit;
  // A command that reads its input finds an empty one instead of waiting.
  NulIn := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Sa,
    OPEN_EXISTING, 0, 0);
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(Si, SizeOf(Si), 0);
    Si.cb := SizeOf(Si);
    Si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Si.wShowWindow := SW_HIDE;
    Si.hStdInput := NulIn;
    Si.hStdOutput := WritePipe;
    Si.hStdError := WritePipe;
    FillChar(Pi, SizeOf(Pi), 0);
    Shell := GetEnvironmentVariable('ComSpec');
    if Shell = '' then
      Shell := 'cmd.exe';
    // /s drops exactly the outer pair of quotes, so the command keeps its own.
    CmdLine := '"' + Shell + '" /d /s /c "' + ACommand + '"';
    UniqueString(CmdLine);
    Dir := AWorkDir;
    if (Dir <> '') and DirectoryExists(Dir) then
      WorkDirPtr := PChar(Dir)
    else
      WorkDirPtr := nil;
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT, nil, WorkDirPtr, Si, Pi) then
      Exit;
    CloseHandle(Pi.hThread);
    // The child owns its copy of the write end; ours must close or ReadFile
    // would never see the end of the output.
    CloseHandle(WritePipe);
    WritePipe := 0;
    try
      Started := GetTickCount64;
      Done := False;
      repeat
        Drain;
        Done := WaitForSingleObject(Pi.hProcess, 25) = WAIT_OBJECT_0;
        if (not Done) and ((GetTickCount64 - Started > ATimeoutMs) or
           (Assigned(AShouldStop) and AShouldStop())) then
        begin
          TerminateProcess(Pi.hProcess, 1);
          Break;
        end;
      until Done;
      Drain;
      AOutput := DecodeOutput(Bytes);
      Result := Done;
    finally
      CloseHandle(Pi.hProcess);
    end;
  finally
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
    if NulIn <> INVALID_HANDLE_VALUE then
      CloseHandle(NulIn);
    CloseHandle(ReadPipe);
  end;
end;

{$ELSE}

uses
  System.SysUtils, uVfsTypes, uPlatformProcess;

type
  TStopCheckToken = class(TInterfacedObject, IJobCancelToken)
  private
    FCheck: TStopCheck;
  public
    constructor Create(const ACheck: TStopCheck);
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

constructor TStopCheckToken.Create(const ACheck: TStopCheck);
begin
  inherited Create;
  FCheck := ACheck;
end;

function TStopCheckToken.IsCancellationRequested: Boolean;
begin
  Result := Assigned(FCheck) and FCheck();
end;

procedure TStopCheckToken.Cancel;
begin
  // The stop check decides.
end;

// Single-quoted for sh: an embedded quote closes the string, is escaped, and
// reopens it.
function ShellQuote(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function RunCommandCapture(const ACommand, AWorkDir: string; ATimeoutMs: Cardinal;
  out AOutput: string; const AShouldStop: TStopCheck): Boolean;
var
  Script: string;
  Code: Cardinal;
begin
  Script := ACommand;
  if (AWorkDir <> '') and DirectoryExists(AWorkDir) then
    Script := 'cd ' + ShellQuote(AWorkDir) + ' && ' + ACommand;
  Result := PlatformRunCaptured('/bin/sh', ['-c', Script], '', ATimeoutMs,
    TStopCheckToken.Create(AShouldStop), AOutput, Code) = srOk;
end;

{$ENDIF}

end.
