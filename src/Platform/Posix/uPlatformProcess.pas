unit uPlatformProcess;

{ Runs an external program and captures its output (POSIX build): posix_spawnp
  with pipes for stdin and a merged stdout/stderr. The Windows build lives in
  Platform\Windows; each project puts exactly one of the two directories on
  its unit search path. }

interface

uses
  uVfsTypes;

type
  TSpawnResult = (srOk, srSpawnFailed, srTimeout, srCancelled);

/// <summary>Name of the OpenSSH SFTP client in the search path.</summary>
function PlatformSftpExeName: string;

/// <summary>Full path of the archive engine the 7z plugin uses, searched in
/// APluginDir first; empty when there is none (7z.dll on Windows, a 7-Zip
/// command line program on POSIX).</summary>
function PlatformSevenZipEngine(const APluginDir: string): string;

/// <summary>Sentence telling how to install the missing archive engine.</summary>
function PlatformSevenZipEngineHint: string;

/// <summary>Sets an environment variable of this process; children started
/// afterwards inherit it.</summary>
procedure PlatformSetEnvironment(const AName, AValue: string);

/// <summary>Spawns AExe with AArgs, writes AStdIn to its stdin then closes it,
/// captures merged stdout and stderr. ATimeoutMs = 0 waits until the process
/// exits or ACancel is signalled. A timeout or cancel kills the child. A
/// nonzero exit code is srOk: the caller reads AOutput to explain it.</summary>
function PlatformRunCaptured(const AExe: string; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out AExitCode: Cardinal): TSpawnResult;

/// <summary>Puts the computer to sleep; False when the system refused.</summary>
function PlatformSuspendSystem: Boolean;

/// <summary>Shuts the computer down at once; False when the system refused.</summary>
function PlatformShutdownSystem: Boolean;

implementation

uses
  System.SysUtils, System.Classes, Posix.Base, Posix.Dlfcn;

const
  cWaitSliceMs = 20;
  SIGKILL = 9;
  WNOHANG = 1;
  cActionsSize = 512;

type
  PPAnsiChar = ^MarshaledAString;
  PPPAnsiChar = ^PPAnsiChar;

  TPipeReaderThread = class(TThread)
  private
    FFd: Integer;
    FBuf: TBytesStream;
  protected
    procedure Execute; override;
  public
    constructor Create(AFd: Integer);
    destructor Destroy; override;
    property Buf: TBytesStream read FBuf;
  end;

function c_setenv(AName, AValue: MarshaledAString; AOverwrite: Integer): Integer; cdecl;
  external libc name 'setenv';
function c_pipe(AFds: PInteger): Integer; cdecl; external libc name 'pipe';
function c_close(AFd: Integer): Integer; cdecl; external libc name 'close';
function c_access(APath: MarshaledAString; AMode: Integer): Integer; cdecl; external libc name 'access';
function c_read(AFd: Integer; ABuf: Pointer; ACount: NativeUInt): NativeInt; cdecl;
  external libc name 'read';
function c_write(AFd: Integer; ABuf: Pointer; ACount: NativeUInt): NativeInt; cdecl;
  external libc name 'write';
function c_waitpid(APid: Integer; AStatus: PInteger; AOptions: Integer): Integer; cdecl;
  external libc name 'waitpid';
function c_kill(APid, ASig: Integer): Integer; cdecl; external libc name 'kill';
function c_spawnp(APid: PInteger; AFile: MarshaledAString; AActions, AAttr: Pointer;
  AArgv, AEnvp: PPAnsiChar): Integer; cdecl; external libc name 'posix_spawnp';
function c_actions_init(AActions: Pointer): Integer; cdecl;
  external libc name 'posix_spawn_file_actions_init';
function c_actions_destroy(AActions: Pointer): Integer; cdecl;
  external libc name 'posix_spawn_file_actions_destroy';
function c_actions_adddup2(AActions: Pointer; AFd, ANewFd: Integer): Integer; cdecl;
  external libc name 'posix_spawn_file_actions_adddup2';
function c_actions_addclose(AActions: Pointer; AFd: Integer): Integer; cdecl;
  external libc name 'posix_spawn_file_actions_addclose';

constructor TPipeReaderThread.Create(AFd: Integer);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FFd := AFd;
  FBuf := TBytesStream.Create;
end;

destructor TPipeReaderThread.Destroy;
begin
  FBuf.Free;
  inherited;
end;

procedure TPipeReaderThread.Execute;
var
  Chunk: array[0..4095] of Byte;
  N: NativeInt;
begin
  while not Terminated do
  begin
    N := c_read(FFd, @Chunk[0], SizeOf(Chunk));
    if N <= 0 then
      Break;
    FBuf.Write(Chunk, N);
  end;
end;

function FindInPath(const AName: string): string;
var
  Dir: string;
begin
  for Dir in GetEnvironmentVariable('PATH').Split([':']) do
    if Dir <> '' then
    begin
      Result := IncludeTrailingPathDelimiter(Dir) + AName;
      if FileExists(Result) and (c_access(MarshaledAString(UTF8String(Result)), 1) = 0) then
        Exit;
    end;
  Result := '';
end;

function PlatformSevenZipEngine(const APluginDir: string): string;
const
  cNames: array[0..3] of string = ('7zz', '7z', '7za', '7zr');
var
  Name, Path: string;
begin
  for Name in cNames do
  begin
    Path := IncludeTrailingPathDelimiter(APluginDir) + Name;
    if (APluginDir <> '') and FileExists(Path) then
      Exit(Path);
  end;
  for Name in cNames do
  begin
    Result := FindInPath(Name);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;

function PlatformSevenZipEngineHint: string;
begin
  Result := 'Install 7-Zip (package 7zip or p7zip-full) to open such files.';
end;

procedure PlatformSetEnvironment(const AName, AValue: string);
var
  N, V: UTF8String;
begin
  N := UTF8String(AName);
  V := UTF8String(AValue);
  c_setenv(MarshaledAString(N), MarshaledAString(V), 1);
end;

function RunSystemTool(const AExe: string; const AArgs: TArray<string>): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  Result := (PlatformRunCaptured(AExe, AArgs, '', 20000, nil, Output, Code) = srOk) and
    (Code = 0);
end;

function PlatformSuspendSystem: Boolean;
begin
  Result := RunSystemTool('systemctl', TArray<string>.Create('suspend'));
end;

function PlatformShutdownSystem: Boolean;
begin
  Result := RunSystemTool('systemctl', TArray<string>.Create('poweroff'));
end;

function PlatformSftpExeName: string;
begin
  Result := 'sftp';
end;

procedure CloseFd(var AFd: Integer);
begin
  if AFd >= 0 then
  begin
    c_close(AFd);
    AFd := -1;
  end;
end;

function CurrentEnvironment: PPAnsiChar;
var
  P: PPPAnsiChar;
begin
  P := PPPAnsiChar(dlsym(0, 'environ'));
  if P = nil then
    Result := nil
  else
    Result := P^;
end;

// Exit code from a waitpid status; a signal death is reported as 128 + signal.
function ExitCodeOf(AStatus: Integer): Cardinal;
begin
  if (AStatus and $7F) = 0 then
    Result := Cardinal((AStatus shr 8) and $FF)
  else
    Result := Cardinal(128 + (AStatus and $7F));
end;

function WaitChild(APid: Integer; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AStatus: Integer): TSpawnResult;
var
  Elapsed: Cardinal;
begin
  Elapsed := 0;
  AStatus := 0;
  repeat
    if c_waitpid(APid, @AStatus, WNOHANG) = APid then
      Exit(srOk);
    if JobCancelRequested(ACancel) then
    begin
      c_kill(APid, SIGKILL);
      c_waitpid(APid, @AStatus, 0);
      Exit(srCancelled);
    end;
    if (ATimeoutMs > 0) and (Elapsed >= ATimeoutMs) then
    begin
      c_kill(APid, SIGKILL);
      c_waitpid(APid, @AStatus, 0);
      Exit(srTimeout);
    end;
    Sleep(cWaitSliceMs);
    Inc(Elapsed, cWaitSliceMs);
  until False;
end;

function PlatformRunCaptured(const AExe: string; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out AExitCode: Cardinal): TSpawnResult;
var
  InPipe, OutPipe: array[0..1] of Integer;
  Actions: array[0..cActionsSize - 1] of Byte;
  Argv: TArray<MarshaledAString>;
  ArgStore: TArray<UTF8String>;
  Pid, Status, I: Integer;
  Reader: TPipeReaderThread;
  InBytes: TBytes;
  Written: NativeInt;
  Offset: Integer;
  OutBytes: TBytes;
begin
  Result := srSpawnFailed;
  AOutput := '';
  AExitCode := Cardinal(-1);
  InPipe[0] := -1;
  InPipe[1] := -1;
  OutPipe[0] := -1;
  OutPipe[1] := -1;
  if (c_pipe(@InPipe[0]) <> 0) or (c_pipe(@OutPipe[0]) <> 0) then
  begin
    CloseFd(InPipe[0]);
    CloseFd(InPipe[1]);
    CloseFd(OutPipe[0]);
    CloseFd(OutPipe[1]);
    Exit;
  end;

  SetLength(ArgStore, Length(AArgs) + 1);
  SetLength(Argv, Length(AArgs) + 2);
  ArgStore[0] := UTF8String(AExe);
  Argv[0] := MarshaledAString(ArgStore[0]);
  for I := 0 to High(AArgs) do
  begin
    ArgStore[I + 1] := UTF8String(AArgs[I]);
    Argv[I + 1] := MarshaledAString(ArgStore[I + 1]);
  end;
  Argv[High(Argv)] := nil;

  FillChar(Actions, SizeOf(Actions), 0);
  c_actions_init(@Actions[0]);
  try
    c_actions_adddup2(@Actions[0], InPipe[0], 0);
    c_actions_adddup2(@Actions[0], OutPipe[1], 1);
    c_actions_adddup2(@Actions[0], OutPipe[1], 2);
    c_actions_addclose(@Actions[0], InPipe[1]);
    c_actions_addclose(@Actions[0], OutPipe[0]);
    Pid := 0;
    if c_spawnp(@Pid, MarshaledAString(ArgStore[0]), @Actions[0], nil,
         PPAnsiChar(@Argv[0]), CurrentEnvironment) <> 0 then
    begin
      CloseFd(InPipe[0]);
      CloseFd(InPipe[1]);
      CloseFd(OutPipe[0]);
      CloseFd(OutPipe[1]);
      Exit;
    end;
  finally
    c_actions_destroy(@Actions[0]);
  end;

  // The child owns its ends now.
  CloseFd(InPipe[0]);
  CloseFd(OutPipe[1]);
  Reader := TPipeReaderThread.Create(OutPipe[0]);
  try
    if AStdIn <> '' then
    begin
      InBytes := TEncoding.UTF8.GetBytes(AStdIn);
      Offset := 0;
      while Offset < Length(InBytes) do
      begin
        Written := c_write(InPipe[1], @InBytes[Offset], Length(InBytes) - Offset);
        if Written <= 0 then
          Break;
        Inc(Offset, Written);
      end;
    end;
    CloseFd(InPipe[1]);

    Result := WaitChild(Pid, ATimeoutMs, ACancel, Status);
    Reader.WaitFor;
    AExitCode := ExitCodeOf(Status);
    SetLength(OutBytes, Reader.Buf.Size);
    if Reader.Buf.Size > 0 then
      Move(Reader.Buf.Memory^, OutBytes[0], Reader.Buf.Size);
    AOutput := TEncoding.UTF8.GetString(OutBytes);
  finally
    CloseFd(InPipe[1]);
    Reader.Free;
    CloseFd(OutPipe[0]);
  end;
end;

end.
