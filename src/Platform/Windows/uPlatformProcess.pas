unit uPlatformProcess;

{ Runs an external program and captures its output (Windows build): hidden
  window, merged stdout and stderr, input written to stdin. The POSIX build
  lives in Platform\Posix; each project puts exactly one of the two
  directories on its unit search path. }

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

/// <summary>Quotes one argument of a CreateProcess command line so the child's
/// CommandLineToArgvW parsing gives back exactly S.</summary>
function PlatformQuoteArg(const S: string): string;

/// <summary>Spawns AExe with AArgs, writes AStdIn to its stdin then closes it,
/// captures merged stdout and stderr. ATimeoutMs = 0 waits until the process
/// exits or ACancel is signalled. A timeout or cancel kills the child. A
/// nonzero exit code is srOk: the caller reads AOutput to explain it.</summary>
function PlatformRunCaptured(const AExe: string; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out AExitCode: Cardinal): TSpawnResult;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows;

const
  cWaitSliceMs = 400;

type
  TPipeReaderThread = class(TThread)
  private
    FHandle: THandle;
    FBuf: TBytesStream;
  protected
    procedure Execute; override;
  public
    constructor Create(AHandle: THandle);
    destructor Destroy; override;
    property Buf: TBytesStream read FBuf;
  end;

function PlatformSevenZipEngine(const APluginDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(APluginDir) + '7z.dll';
  if not FileExists(Result) then
    Result := '';
end;

function PlatformSevenZipEngineHint: string;
begin
  Result := 'Put 7z.dll into plugins\mtn.7z\ to open such files.';
end;

procedure PlatformSetEnvironment(const AName, AValue: string);
begin
  SetEnvironmentVariable(PChar(AName), PChar(AValue));
end;

function PlatformSftpExeName: string;
begin
  Result := 'sftp.exe';
end;

constructor TPipeReaderThread.Create(AHandle: THandle);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FHandle := AHandle;
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
  N: DWORD;
begin
  while not Terminated do
  begin
    if not ReadFile(FHandle, Chunk, SizeOf(Chunk), N, nil) or (N = 0) then
      Break;
    FBuf.Write(Chunk, N);
  end;
end;

function PlatformQuoteArg(const S: string): string;
var
  I, Slashes: Integer;
  C: Char;
begin
  if (S <> '') and (S.IndexOfAny([' ', #9, #10, #11, '"', '&', '|', '<', '>', '^']) < 0) then
    Exit(S);
  // CommandLineToArgvW rules: backslashes only matter in front of a quote, so
  // they are doubled there (and before the closing quote). Without that a
  // trailing backslash would escape the closing quote and glue the next
  // argument onto this one.
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C = '\' then
      Inc(Slashes)
    else
    begin
      if C = '"' then
        Result := Result + StringOfChar('\', Slashes * 2 + 1)
      else
        Result := Result + StringOfChar('\', Slashes);
      Slashes := 0;
      Result := Result + C;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

procedure CloseHandleIfOpen(var AHandle: THandle);
begin
  if AHandle <> 0 then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
end;

function CreateStdPipes(out AInRead, AInWrite, AOutRead, AOutWrite: THandle): Boolean;
var
  SecAttr: TSecurityAttributes;
begin
  Result := False;
  AInRead := 0;
  AInWrite := 0;
  AOutRead := 0;
  AOutWrite := 0;
  FillChar(SecAttr, SizeOf(SecAttr), 0);
  SecAttr.nLength := SizeOf(SecAttr);
  SecAttr.bInheritHandle := True;
  if not CreatePipe(AInRead, AInWrite, @SecAttr, 0) then
    Exit;
  if not SetHandleInformation(AInWrite, HANDLE_FLAG_INHERIT, 0) then
  begin
    CloseHandleIfOpen(AInRead);
    CloseHandleIfOpen(AInWrite);
    Exit;
  end;
  if not CreatePipe(AOutRead, AOutWrite, @SecAttr, 0) then
  begin
    CloseHandleIfOpen(AInRead);
    CloseHandleIfOpen(AInWrite);
    Exit;
  end;
  if not SetHandleInformation(AOutRead, HANDLE_FLAG_INHERIT, 0) then
  begin
    CloseHandleIfOpen(AInRead);
    CloseHandleIfOpen(AInWrite);
    CloseHandleIfOpen(AOutRead);
    CloseHandleIfOpen(AOutWrite);
    Exit;
  end;
  Result := True;
end;

function BuildCommandLine(const AExe: string; const AArgs: TArray<string>): string;
var
  Arg: string;
begin
  Result := PlatformQuoteArg(AExe);
  for Arg in AArgs do
    Result := Result + ' ' + PlatformQuoteArg(Arg);
  UniqueString(Result);
end;

function WaitCapturedProcess(AProcess: THandle; ATimeoutMs: Cardinal;
  ACancel: IJobCancelToken): TSpawnResult;
var
  WaitRes: DWORD;
  StartTick: UInt64;
begin
  StartTick := GetTickCount64;
  repeat
    WaitRes := WaitForSingleObject(AProcess, cWaitSliceMs);
    if WaitRes = WAIT_OBJECT_0 then
      Exit(srOk);
    if JobCancelRequested(ACancel) then
    begin
      TerminateProcess(AProcess, 1);
      Exit(srCancelled);
    end;
    if (ATimeoutMs > 0) and (GetTickCount64 - StartTick >= ATimeoutMs) then
    begin
      TerminateProcess(AProcess, 1);
      Exit(srTimeout);
    end;
  until False;
end;

/// <summary>Spawns AExe with AArgs, writes AStdIn to its stdin then closes
/// it, captures merged stdout+stderr. ATimeoutMs=0 waits until the process
/// exits or ACancel is signalled. Timeout/cancel kill the child. A nonzero
/// exit code is srOk - the caller reads AOutput to explain the failure.</summary>
function PlatformRunCaptured(const AExe: string; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out AExitCode: Cardinal): TSpawnResult;
var
  StdInRead, StdInWrite, StdOutRead, StdOutWrite: THandle;
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  CmdLine: string;
  Reader: TPipeReaderThread;
  BytesWritten: DWORD;
  InBytes: TBytes;
  OutBytes: TBytes;
begin
  Result := srSpawnFailed;
  AOutput := '';
  AExitCode := Cardinal(-1);
  if not CreateStdPipes(StdInRead, StdInWrite, StdOutRead, StdOutWrite) then
    Exit;

  CmdLine := BuildCommandLine(AExe, AArgs);
  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb := SizeOf(StartInfo);
  StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_HIDE;
  StartInfo.hStdInput := StdInRead;
  StartInfo.hStdOutput := StdOutWrite;
  StartInfo.hStdError := StdOutWrite;
  FillChar(ProcInfo, SizeOf(ProcInfo), 0);

  Reader := TPipeReaderThread.Create(StdOutRead);
  try
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, StartInfo, ProcInfo) then
      Exit;

    CloseHandleIfOpen(StdInRead);
    CloseHandleIfOpen(StdOutWrite);

    if AStdIn <> '' then
    begin
      InBytes := TEncoding.UTF8.GetBytes(AStdIn);
      WriteFile(StdInWrite, InBytes[0], Length(InBytes), BytesWritten, nil);
    end;
    CloseHandleIfOpen(StdInWrite);

    Result := WaitCapturedProcess(ProcInfo.hProcess, ATimeoutMs, ACancel);
    Reader.WaitFor;
    GetExitCodeProcess(ProcInfo.hProcess, AExitCode);
    SetLength(OutBytes, Reader.Buf.Size);
    if Reader.Buf.Size > 0 then
      Move(Reader.Buf.Memory^, OutBytes[0], Reader.Buf.Size);
    AOutput := TEncoding.UTF8.GetString(OutBytes);
    CloseHandle(ProcInfo.hProcess);
    CloseHandle(ProcInfo.hThread);
  finally
    CloseHandleIfOpen(StdInRead);
    CloseHandleIfOpen(StdInWrite);
    CloseHandleIfOpen(StdOutWrite);
    Reader.Free;
    CloseHandleIfOpen(StdOutRead);
  end;
end;

end.
