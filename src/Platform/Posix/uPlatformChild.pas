unit uPlatformChild;

{ A child process that stays alive and talks over pipes (POSIX build): posix_spawnp with
  separate pipes for stdin, stdout and stderr. The child leads its own process group, so
  Kill ends it together with every process it started. The Windows build lives in
  Platform\Windows; each project puts exactly one of the two directories on its unit
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
  System.SysUtils, Posix.Base, Posix.Dlfcn;

const
  cKill = 9;
  cWaitNoHang = 1;
  cSpawnSetPgroup = 2;
  cActionsSize = 512;
  cAttrSize = 512;
  cWaitSliceMs = 10;

type
  PPAnsiChar = ^MarshaledAString;
  PPPAnsiChar = ^PPAnsiChar;
  TAddChdirFn = function(AActions: Pointer; APath: MarshaledAString): Integer; cdecl;

function c_pipe(AFds: PInteger): Integer; cdecl; external libc name 'pipe';
function c_close(AFd: Integer): Integer; cdecl; external libc name 'close';
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
function c_attr_init(AAttr: Pointer): Integer; cdecl; external libc name 'posix_spawnattr_init';
function c_attr_destroy(AAttr: Pointer): Integer; cdecl; external libc name 'posix_spawnattr_destroy';
function c_attr_setflags(AAttr: Pointer; AFlags: SmallInt): Integer; cdecl;
  external libc name 'posix_spawnattr_setflags';
function c_attr_setpgroup(AAttr: Pointer; AGroup: Integer): Integer; cdecl;
  external libc name 'posix_spawnattr_setpgroup';

type
  TChildProcess = class(TInterfacedObject, IChildProcess)
  private
    FPid: Integer;
    FIn, FOut, FErr: Integer;
    FExited: Boolean;
    FStatus: Integer;
    FLock: TObject;
    procedure CloseFd(var AFd: Integer);
    function Reap(AOptions: Integer): Boolean;
  public
    constructor Create(APid, AIn, AOut, AErr: Integer);
    destructor Destroy; override;
    function Write(const ABuf; ACount: Integer): Boolean;
    function ReadOut(var ABuf; ACount: Integer): Integer;
    function ReadErr(var ABuf; ACount: Integer): Integer;
    procedure CloseInput;
    procedure Kill;
    function WaitExit(ATimeoutMs: Cardinal): Boolean;
    function ExitCode: Cardinal;
  end;

constructor TChildProcess.Create(APid, AIn, AOut, AErr: Integer);
begin
  inherited Create;
  FPid := APid;
  FIn := AIn;
  FOut := AOut;
  FErr := AErr;
  FLock := TObject.Create;
end;

destructor TChildProcess.Destroy;
begin
  Kill;
  Reap(0);
  CloseFd(FIn);
  CloseFd(FOut);
  CloseFd(FErr);
  FLock.Free;
  inherited;
end;

procedure TChildProcess.CloseFd(var AFd: Integer);
begin
  if AFd >= 0 then
  begin
    c_close(AFd);
    AFd := -1;
  end;
end;

// waitpid under the lock; True once the child is gone.
function TChildProcess.Reap(AOptions: Integer): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    if not FExited and (c_waitpid(FPid, @FStatus, AOptions) = FPid) then
      FExited := True;
    Result := FExited;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TChildProcess.Write(const ABuf; ACount: Integer): Boolean;
var
  Done: Integer;
  N: NativeInt;
  P: PByte;
begin
  Result := False;
  if FIn < 0 then
    Exit;
  P := @ABuf;
  Done := 0;
  while Done < ACount do
  begin
    N := c_write(FIn, @P[Done], ACount - Done);
    if N <= 0 then
      Exit;
    Inc(Done, N);
  end;
  Result := True;
end;

function TChildProcess.ReadOut(var ABuf; ACount: Integer): Integer;
var
  N: NativeInt;
begin
  if FOut < 0 then
    Exit(0);
  N := c_read(FOut, @ABuf, ACount);
  if N < 0 then
    N := 0;
  Result := N;
end;

function TChildProcess.ReadErr(var ABuf; ACount: Integer): Integer;
var
  N: NativeInt;
begin
  if FErr < 0 then
    Exit(0);
  N := c_read(FErr, @ABuf, ACount);
  if N < 0 then
    N := 0;
  Result := N;
end;

procedure TChildProcess.CloseInput;
begin
  TMonitor.Enter(FLock);
  try
    CloseFd(FIn);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TChildProcess.Kill;
begin
  TMonitor.Enter(FLock);
  try
    if not FExited then
    begin
      // A negative pid addresses the whole process group of the child.
      c_kill(-FPid, cKill);
      c_kill(FPid, cKill);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TChildProcess.WaitExit(ATimeoutMs: Cardinal): Boolean;
var
  Elapsed: Cardinal;
begin
  Elapsed := 0;
  repeat
    if Reap(cWaitNoHang) then
      Exit(True);
    if Elapsed >= ATimeoutMs then
      Exit(False);
    Sleep(cWaitSliceMs);
    Inc(Elapsed, cWaitSliceMs);
  until False;
end;

function TChildProcess.ExitCode: Cardinal;
begin
  if not Reap(cWaitNoHang) then
    Exit(Cardinal(-1));
  if (FStatus and $7F) = 0 then
    Result := Cardinal((FStatus shr 8) and $FF)
  else
    Result := Cardinal(128 + (FStatus and $7F));
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

procedure ClosePair(var APipe: array of Integer);
begin
  if APipe[0] >= 0 then
    c_close(APipe[0]);
  if APipe[1] >= 0 then
    c_close(APipe[1]);
  APipe[0] := -1;
  APipe[1] := -1;
end;

function PlatformStartChild(const AExe: string; const AArgs: TArray<string>;
  const ADir: string; const AEnv: TArray<string>; out AChild: IChildProcess): Boolean;
var
  InP, OutP, ErrP: array[0..1] of Integer;
  Actions: array[0..cActionsSize - 1] of Byte;
  Attr: array[0..cAttrSize - 1] of Byte;
  ArgStore, EnvStore: TArray<UTF8String>;
  Argv, Envp: TArray<MarshaledAString>;
  Cur: PPAnsiChar;
  DirUtf: UTF8String;
  AddChdir: TAddChdirFn;
  Pid, I, N: Integer;
begin
  Result := False;
  AChild := nil;
  Pid := 0;
  InP[0] := -1; InP[1] := -1; OutP[0] := -1; OutP[1] := -1; ErrP[0] := -1; ErrP[1] := -1;
  if (c_pipe(@InP[0]) <> 0) or (c_pipe(@OutP[0]) <> 0) or (c_pipe(@ErrP[0]) <> 0) then
  begin
    ClosePair(InP);
    ClosePair(OutP);
    ClosePair(ErrP);
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

  // The environment of this process followed by the extra entries.
  N := 0;
  Cur := CurrentEnvironment;
  if Cur <> nil then
    while PPAnsiChar(PByte(Cur) + N * SizeOf(Pointer))^ <> nil do
      Inc(N);
  SetLength(EnvStore, Length(AEnv));
  SetLength(Envp, N + Length(AEnv) + 1);
  for I := 0 to N - 1 do
    Envp[I] := PPAnsiChar(PByte(Cur) + I * SizeOf(Pointer))^;
  for I := 0 to High(AEnv) do
  begin
    EnvStore[I] := UTF8String(AEnv[I]);
    Envp[N + I] := MarshaledAString(EnvStore[I]);
  end;
  Envp[High(Envp)] := nil;

  FillChar(Actions, SizeOf(Actions), 0);
  FillChar(Attr, SizeOf(Attr), 0);
  c_actions_init(@Actions[0]);
  c_attr_init(@Attr[0]);
  try
    c_actions_adddup2(@Actions[0], InP[0], 0);
    c_actions_adddup2(@Actions[0], OutP[1], 1);
    c_actions_adddup2(@Actions[0], ErrP[1], 2);
    c_actions_addclose(@Actions[0], InP[1]);
    c_actions_addclose(@Actions[0], OutP[0]);
    c_actions_addclose(@Actions[0], ErrP[0]);
    c_attr_setflags(@Attr[0], cSpawnSetPgroup);
    c_attr_setpgroup(@Attr[0], 0);
    if ADir <> '' then
    begin
      // Not every C library has it; without it the child starts in the current folder
      // only when no folder was asked for.
      AddChdir := TAddChdirFn(dlsym(0, 'posix_spawn_file_actions_addchdir_np'));
      if not Assigned(AddChdir) then
        Exit;
      DirUtf := UTF8String(ADir);
      AddChdir(@Actions[0], MarshaledAString(DirUtf));
    end;
    if c_spawnp(@Pid, MarshaledAString(ArgStore[0]), @Actions[0], @Attr[0],
         PPAnsiChar(@Argv[0]), PPAnsiChar(@Envp[0])) <> 0 then
      Exit;
  finally
    c_attr_destroy(@Attr[0]);
    c_actions_destroy(@Actions[0]);
    if Pid = 0 then
    begin
      ClosePair(InP);
      ClosePair(OutP);
      ClosePair(ErrP);
    end;
  end;

  c_close(InP[0]);
  c_close(OutP[1]);
  c_close(ErrP[1]);
  AChild := TChildProcess.Create(Pid, InP[1], OutP[0], ErrP[0]);
  Result := True;
end;

end.
