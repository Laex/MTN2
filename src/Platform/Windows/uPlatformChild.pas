unit uPlatformChild;

{ A child process that stays alive and talks over pipes (Windows build): stdin, stdout and
  stderr are separate pipes, the window is hidden, and the process runs in a job object so
  Kill ends it together with every process it started. The POSIX build lives in
  Platform\Posix; each project puts exactly one of the two directories on its unit
  search path. }

interface

type
  IChildProcess = interface
    /// <summary>Writes all ACount bytes to the child's stdin; False when the pipe is closed.</summary>
    function Write(const ABuf; ACount: Integer): Boolean;
    /// <summary>Waits for output; the number of bytes read, 0 at the end of the stream.</summary>
    function ReadOut(var ABuf; ACount: Integer): Integer;
    function ReadErr(var ABuf; ACount: Integer): Integer;
    /// <summary>Closes stdin so a child that reads it to the end can finish.</summary>
    procedure CloseInput;
    /// <summary>Ends the child and everything it started; safe to call more than once and
    /// from another thread while a read waits.</summary>
    procedure Kill;
    /// <summary>True when the child has exited within ATimeoutMs.</summary>
    function WaitExit(ATimeoutMs: Cardinal): Boolean;
    function ExitCode: Cardinal;
  end;

/// <summary>Starts AExe with AArgs (no shell) in ADir ('' = the current folder). AEnv holds
/// extra "NAME=VALUE" entries added to the environment of this process. False when the
/// program cannot be started.</summary>
function PlatformStartChild(const AExe: string; const AArgs: TArray<string>;
  const ADir: string; const AEnv: TArray<string>; out AChild: IChildProcess): Boolean;

implementation

uses
  System.SysUtils, Winapi.Windows, uPlatformProcess;

type
  TChildProcess = class(TInterfacedObject, IChildProcess)
  private
    FProcess: THandle;
    FJob: THandle;
    FIn, FOut, FErr: THandle;
    FLock: TObject;
    procedure CloseHandleSafe(var AHandle: THandle);
  public
    constructor Create(AProcess, AJob, AIn, AOut, AErr: THandle);
    destructor Destroy; override;
    function Write(const ABuf; ACount: Integer): Boolean;
    function ReadOut(var ABuf; ACount: Integer): Integer;
    function ReadErr(var ABuf; ACount: Integer): Integer;
    procedure CloseInput;
    procedure Kill;
    function WaitExit(ATimeoutMs: Cardinal): Boolean;
    function ExitCode: Cardinal;
  end;

constructor TChildProcess.Create(AProcess, AJob, AIn, AOut, AErr: THandle);
begin
  inherited Create;
  FProcess := AProcess;
  FJob := AJob;
  FIn := AIn;
  FOut := AOut;
  FErr := AErr;
  FLock := TObject.Create;
end;

destructor TChildProcess.Destroy;
begin
  Kill;
  CloseHandleSafe(FIn);
  CloseHandleSafe(FOut);
  CloseHandleSafe(FErr);
  CloseHandleSafe(FProcess);
  CloseHandleSafe(FJob);
  FLock.Free;
  inherited;
end;

procedure TChildProcess.CloseHandleSafe(var AHandle: THandle);
begin
  if AHandle <> 0 then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
end;

function TChildProcess.Write(const ABuf; ACount: Integer): Boolean;
var
  Done, N: DWORD;
  P: PByte;
begin
  Result := False;
  if FIn = 0 then
    Exit;
  P := @ABuf;
  Done := 0;
  while Done < DWORD(ACount) do
  begin
    if not WriteFile(FIn, P[Done], DWORD(ACount) - Done, N, nil) or (N = 0) then
      Exit;
    Inc(Done, N);
  end;
  Result := True;
end;

function TChildProcess.ReadOut(var ABuf; ACount: Integer): Integer;
var
  N: DWORD;
begin
  if (FOut = 0) or not ReadFile(FOut, ABuf, ACount, N, nil) then
    Exit(0);
  Result := N;
end;

function TChildProcess.ReadErr(var ABuf; ACount: Integer): Integer;
var
  N: DWORD;
begin
  if (FErr = 0) or not ReadFile(FErr, ABuf, ACount, N, nil) then
    Exit(0);
  Result := N;
end;

procedure TChildProcess.CloseInput;
begin
  TMonitor.Enter(FLock);
  try
    CloseHandleSafe(FIn);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TChildProcess.Kill;
begin
  TMonitor.Enter(FLock);
  try
    if FJob <> 0 then
      TerminateJobObject(FJob, 1)
    else if FProcess <> 0 then
      TerminateProcess(FProcess, 1);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TChildProcess.WaitExit(ATimeoutMs: Cardinal): Boolean;
begin
  Result := WaitForSingleObject(FProcess, ATimeoutMs) = WAIT_OBJECT_0;
end;

function TChildProcess.ExitCode: Cardinal;
begin
  if not GetExitCodeProcess(FProcess, Result) or (Result = STILL_ACTIVE) then
    Result := Cardinal(-1);
end;

// The environment of this process with the extra entries added; a UTF-16 block of
// NAME=VALUE entries, each ending in #0, the whole block in an extra #0.
function BuildEnvironmentBlock(const AEnv: TArray<string>): string;
var
  Block, P: PChar;
  Entry: string;
begin
  Result := '';
  Block := GetEnvironmentStrings;
  try
    P := Block;
    while P^ <> #0 do
    begin
      Entry := P;
      Result := Result + Entry + #0;
      Inc(P, Length(Entry) + 1);
    end;
  finally
    FreeEnvironmentStrings(Block);
  end;
  for Entry in AEnv do
    Result := Result + Entry + #0;
  Result := Result + #0;
end;

function MakePipe(out AReadEnd, AWriteEnd: THandle; AChildReads: Boolean): Boolean;
var
  Sec: TSecurityAttributes;
begin
  FillChar(Sec, SizeOf(Sec), 0);
  Sec.nLength := SizeOf(Sec);
  Sec.bInheritHandle := True;
  Result := CreatePipe(AReadEnd, AWriteEnd, @Sec, 0);
  if not Result then
    Exit;
  // The end that stays here must not be inherited by the child.
  if AChildReads then
    Result := SetHandleInformation(AWriteEnd, HANDLE_FLAG_INHERIT, 0)
  else
    Result := SetHandleInformation(AReadEnd, HANDLE_FLAG_INHERIT, 0);
end;

function NewKillOnCloseJob: THandle;
var
  Info: TJobObjectExtendedLimitInformation;
begin
  Result := CreateJobObject(nil, nil);
  if Result = 0 then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if not SetInformationJobObject(Result, JobObjectExtendedLimitInformation, @Info, SizeOf(Info)) then
  begin
    CloseHandle(Result);
    Result := 0;
  end;
end;

function PlatformStartChild(const AExe: string; const AArgs: TArray<string>;
  const ADir: string; const AEnv: TArray<string>; out AChild: IChildProcess): Boolean;
var
  InR, InW, OutR, OutW, ErrR, ErrW, Job: THandle;
  Start: TStartupInfo;
  Info: TProcessInformation;
  CmdLine, EnvBlock: string;
  Arg: string;
  DirPtr: PChar;
begin
  Result := False;
  AChild := nil;
  InR := 0; InW := 0; OutR := 0; OutW := 0; ErrR := 0; ErrW := 0;
  if not MakePipe(InR, InW, True) or not MakePipe(OutR, OutW, False) or
     not MakePipe(ErrR, ErrW, False) then
  begin
    CloseHandle(InR); CloseHandle(InW); CloseHandle(OutR); CloseHandle(OutW);
    CloseHandle(ErrR); CloseHandle(ErrW);
    Exit;
  end;

  CmdLine := PlatformQuoteArg(AExe);
  for Arg in AArgs do
    CmdLine := CmdLine + ' ' + PlatformQuoteArg(Arg);
  UniqueString(CmdLine);
  EnvBlock := BuildEnvironmentBlock(AEnv);
  if ADir <> '' then
    DirPtr := PChar(ADir)
  else
    DirPtr := nil;

  FillChar(Start, SizeOf(Start), 0);
  Start.cb := SizeOf(Start);
  Start.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  Start.wShowWindow := SW_HIDE;
  Start.hStdInput := InR;
  Start.hStdOutput := OutW;
  Start.hStdError := ErrW;
  FillChar(Info, SizeOf(Info), 0);

  Job := NewKillOnCloseJob;
  // Suspended, so the process is in the job before it can start another one.
  if CreateProcess(nil, PChar(CmdLine), nil, nil, True,
       CREATE_NO_WINDOW or CREATE_SUSPENDED or CREATE_UNICODE_ENVIRONMENT,
       PChar(EnvBlock), DirPtr, Start, Info) then
  begin
    if Job <> 0 then
      AssignProcessToJobObject(Job, Info.hProcess);
    ResumeThread(Info.hThread);
    CloseHandle(Info.hThread);
    CloseHandle(InR);
    CloseHandle(OutW);
    CloseHandle(ErrW);
    AChild := TChildProcess.Create(Info.hProcess, Job, InW, OutR, ErrR);
    Result := True;
  end
  else
  begin
    CloseHandle(InR); CloseHandle(InW); CloseHandle(OutR); CloseHandle(OutW);
    CloseHandle(ErrR); CloseHandle(ErrW);
    if Job <> 0 then
      CloseHandle(Job);
  end;
end;

end.
