unit uSftpVfs;

{ Built-in backend for sftp:// (Этап 20 -- Сетевой VFS). One protocol,
  end-to-end, per the SDS: SFTP over the system OpenSSH `sftp.exe` client in
  batch mode -- no bundled network/crypto library, no plugin, same
  ssh/sftp binaries the SSH console profile (uShellProfiles.pas) already
  requires. Cross-platform: `sftp -b -` batch-mode syntax is identical on
  Windows/Linux/macOS OpenSSH builds; only the process-spawn plumbing below
  (Winapi.Windows) is Windows-specific, the same seam uConPty.pas already
  has for a future POSIX build (Этап 23).

  URI: sftp://[user@]host[:port]/remote/path -- see uVfsTypes.pas
  (IsSftpUri/SftpAuthorityOf/SftpRemotePathOf/MakeSftpUri).

  Auth: no passwords handled here. -i <identityFile> is passed when a saved
  uSshConnections.pas entry matches the URI's host/port/user; otherwise
  authentication falls back to ssh-agent / ~/.ssh/config. -oBatchMode=yes
  fails fast instead of hanging. ConnectTimeout + ConnectionAttempts keep a
  dead host from blocking the UI; transfer timeouts are long, list/auth
  timeouts stay short. Cancel tokens kill the child process. Transient
  network errors retry once.

  Copy/Move: file:// <-> sftp://, and sftp:// <-> sftp:// via a local temp
  (OpenSSH batch sftp has no remote-to-remote copy). Same-host Move is
  `rename`. F5 is routed here by ClassifyVfsTransfer (vtrSftp).

  Known limitation: `ls -la` output is parsed heuristically (OpenSSH-server
  long-listing format). Non-OpenSSH SFTP servers with a differently-shaped
  `ls` may not parse cleanly. }

interface

uses
  uVfsTypes, uTextEncoding, uSshConnections;

type
  TSftpVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
  public
    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
        AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

/// <summary>Exposed for tests: parses one `sftp ls -la` output line into a
/// TVfsEntry. Returns False for ".", "..", blank lines, or lines that don't
/// start with a recognizable permissions string.</summary>
function ParseSftpLsLine(const ALine: string; out AEntry: TVfsEntry): Boolean;
function ParseSftpLsDate(const AMonth, ADay, ATimeOrYear: string): TDateTime;
/// <summary>Maps sftp.exe stdout/stderr + spawn outcome to a TVfsError.
/// Exposed for tests — no process is spawned.</summary>
function ClassifySftpFailure(const AOutput: string; AExitCode: Cardinal;
  ATimedOut, ACancelled: Boolean; const AURI: string): TVfsError;
function SftpFailureIsTransient(const AError: TVfsError): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.DateUtils, System.StrUtils, Winapi.Windows, uShellProfiles;

const
  cDefaultSftpPort = 22;
  cConnectTimeoutSec = 15;
  cListTimeoutMs = 20000;
  cTransferTimeoutMs = 30 * 60 * 1000;
  cWaitSliceMs = 400;
  cTransientRetries = 1;
  cDefaultReadMaxBytes = 2 * 1024 * 1024;

{ ---- process spawn + capture --------------------------------------------- }

type
  TSftpSpawnResult = (ssrOk, ssrSpawnFailed, ssrTimeout, ssrCancelled);

  TSftpFailRule = record
    Needle: string;
    Code: TVfsErrorCode;
    Friendly: string;
  end;

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

function QuoteCmdArg(const S: string): string;
begin
  if (S = '') or (Pos(' ', S) > 0) or (Pos('"', S) > 0) or (Pos('&', S) > 0) then
    Result := '"' + StringReplace(S, '"', '', [rfReplaceAll]) + '"'
  else
    Result := S;
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
  Result := QuoteCmdArg(AExe);
  for Arg in AArgs do
    Result := Result + ' ' + QuoteCmdArg(Arg);
  UniqueString(Result);
end;

function WaitCapturedProcess(AProcess: THandle; ATimeoutMs: Cardinal;
  ACancel: IJobCancelToken): TSftpSpawnResult;
var
  WaitRes: DWORD;
  StartTick: UInt64;
begin
  StartTick := GetTickCount64;
  repeat
    WaitRes := WaitForSingleObject(AProcess, cWaitSliceMs);
    if WaitRes = WAIT_OBJECT_0 then
      Exit(ssrOk);
    if JobCancelRequested(ACancel) then
    begin
      TerminateProcess(AProcess, 1);
      Exit(ssrCancelled);
    end;
    if (ATimeoutMs > 0) and (GetTickCount64 - StartTick >= ATimeoutMs) then
    begin
      TerminateProcess(AProcess, 1);
      Exit(ssrTimeout);
    end;
  until False;
end;

/// <summary>Spawns AExe with AArgs, writes AStdIn to its stdin then closes
/// it, captures merged stdout+stderr. ATimeoutMs=0 waits until the process
/// exits or ACancel is signalled. Timeout/cancel kill the child. A nonzero
/// exit code is ssrOk — the caller reads AOutput to explain the failure.</summary>
function RunCapturedProcess(const AExe: string; const AArgs: TArray<string>;
  const AStdIn: string; ATimeoutMs: Cardinal; ACancel: IJobCancelToken;
  out AOutput: string; out AExitCode: Cardinal): TSftpSpawnResult;
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
  Result := ssrSpawnFailed;
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

{ ---- sftp.exe batch-mode wrapper ------------------------------------------ }

function GetSftpExePath(out AExe: string): Boolean;
begin
  Result := FileExistsInPath('sftp.exe');
  if Result then
    AExe := 'sftp.exe'
  else
    AExe := '';
end;

procedure AppendArgPair(var AArgs: TArray<string>; var AN: Integer;
  const ALeft, ARight: string);
begin
  SetLength(AArgs, AN + 2);
  AArgs[AN] := ALeft;
  AArgs[AN + 1] := ARight;
  Inc(AN, 2);
end;

function SftpBaseArgs(const AHost: string; APort: Integer;
  const AUser, AIdentityFile: string): TArray<string>;
var
  N: Integer;
  Target: string;
begin
  SetLength(Result, 0);
  N := 0;
  AppendArgPair(Result, N, '-b', '-');
  AppendArgPair(Result, N, '-o', 'BatchMode=yes');
  AppendArgPair(Result, N, '-o', 'ConnectTimeout=' + IntToStr(cConnectTimeoutSec));
  AppendArgPair(Result, N, '-o', 'ConnectionAttempts=1');
  if (APort <> 0) and (APort <> cDefaultSftpPort) then
    AppendArgPair(Result, N, '-P', IntToStr(APort));
  if AIdentityFile <> '' then
  begin
    AppendArgPair(Result, N, '-i', AIdentityFile);
    AppendArgPair(Result, N, '-o', 'IdentitiesOnly=yes');
  end;
  if AUser <> '' then
    Target := AUser + '@' + AHost
  else
    Target := AHost;
  SetLength(Result, N + 1);
  Result[N] := Target;
end;

/// <summary>Splits "[user@]host[:port]" (uVfsTypes.SftpAuthorityOf) into
/// parts. Port 0 means "use default (22)".</summary>
procedure SplitAuthority(const AAuthority: string; out AUser, AHost: string;
  out APort: Integer);
var
  At, Colon: Integer;
  HostPort: string;
begin
  AUser := '';
  APort := 0;
  At := Pos('@', AAuthority);
  if At > 0 then
  begin
    AUser := Copy(AAuthority, 1, At - 1);
    HostPort := Copy(AAuthority, At + 1, MaxInt);
  end
  else
    HostPort := AAuthority;
  Colon := Pos(':', HostPort);
  if Colon > 0 then
  begin
    AHost := Copy(HostPort, 1, Colon - 1);
    if not TryStrToInt(Copy(HostPort, Colon + 1, MaxInt), APort) then
      APort := 0;
  end
  else
    AHost := HostPort;
end;

function IdentityFileForTarget(const AUser, AHost: string; APort: Integer): string;
var
  Port: Integer;
  Conn: TSshConnection;
begin
  Result := '';
  Port := APort;
  if Port = 0 then
    Port := cDefaultSftpPort;
  if SshConnectionsFindByTarget(AHost, Port, AUser, Conn) then
    Result := Conn.IdentityFile;
end;

function MatchSftpFailRule(const AMsg, AURI: string;
  const ARules: array of TSftpFailRule; out AError: TVfsError): Boolean;
var
  I: Integer;
  Text: string;
begin
  for I := Low(ARules) to High(ARules) do
    if ContainsText(AMsg, ARules[I].Needle) then
    begin
      Text := ARules[I].Friendly;
      if Text = '' then
        Text := AMsg;
      AError := TVfsError.Make(ARules[I].Code, Text, AURI);
      Exit(True);
    end;
  Result := False;
end;

function SftpOutputLooksLikeAuthFailure(const AMsg: string): Boolean;
begin
  Result := ContainsText(AMsg, 'publickey') or
    ContainsText(AMsg, 'authentication failed') or
    (ContainsText(AMsg, 'permission denied') and
      (ContainsText(AMsg, 'password') or ContainsText(AMsg, 'keyboard-interactive')));
end;

function ClassifySftpFailure(const AOutput: string; AExitCode: Cardinal;
  ATimedOut, ACancelled: Boolean; const AURI: string): TVfsError;
const
  cConnectRules: array[0..9] of TSftpFailRule = (
    (Needle: 'host key verification failed'; Code: vecAccessDenied;
      Friendly: 'Host key verification failed. Accept the host once in a Terminal ' +
        'Workspace SSH session (Ctrl+Shift+N).'),
    (Needle: 'could not resolve hostname'; Code: vecNotFound;
      Friendly: 'Unknown SFTP host. Check the address in SSH/SFTP Connections.'),
    (Needle: 'connection refused'; Code: vecIOError;
      Friendly: 'SFTP connection refused. Is the host and port reachable?'),
    (Needle: 'network is unreachable'; Code: vecIOError;
      Friendly: 'SFTP network unreachable. Check the connection and retry.'),
    (Needle: 'no route to host'; Code: vecIOError;
      Friendly: 'SFTP network unreachable. Check the connection and retry.'),
    (Needle: 'connection timed out'; Code: vecIOError;
      Friendly: 'SFTP connection timed out. Check the network and retry.'),
    (Needle: 'connection timedout'; Code: vecIOError;
      Friendly: 'SFTP connection timed out. Check the network and retry.'),
    (Needle: 'connection reset'; Code: vecIOError;
      Friendly: 'SFTP connection dropped. Retry the operation.'),
    (Needle: 'broken pipe'; Code: vecIOError;
      Friendly: 'SFTP connection dropped. Retry the operation.'),
    (Needle: 'connection closed'; Code: vecIOError;
      Friendly: 'SFTP connection dropped. Retry the operation.')
  );
  cPathRules: array[0..1] of TSftpFailRule = (
    (Needle: 'no such file'; Code: vecNotFound; Friendly: ''),
    (Needle: 'permission denied'; Code: vecAccessDenied; Friendly: '')
  );
var
  Msg: string;
begin
  if ACancelled then
    Exit(TVfsError.Make(vecCancelled, 'Cancelled', AURI));
  Msg := Trim(AOutput);
  if MatchSftpFailRule(Msg, AURI, cConnectRules, Result) then
    Exit;
  if SftpOutputLooksLikeAuthFailure(Msg) then
    Exit(TVfsError.Make(vecAccessDenied,
      'SFTP authentication failed. The panel uses a key or ssh-agent ' +
      '(no password). Set Identity file in Commands -> SSH/SFTP Connections...', AURI));
  if MatchSftpFailRule(Msg, AURI, cPathRules, Result) then
    Exit;
  if ATimedOut then
    Exit(TVfsError.Make(vecIOError,
      'SFTP timed out. Check the network and retry.', AURI));
  if Msg = '' then
    Msg := Format('sftp exited with code %d', [AExitCode]);
  Result := TVfsError.Make(vecIOError, Msg, AURI);
end;

function SftpFailureIsTransient(const AError: TVfsError): Boolean;
var
  Msg: string;
begin
  Result := False;
  if AError.Code <> vecIOError then
    Exit;
  Msg := LowerCase(AError.Message);
  Result := ContainsText(Msg, 'timed out') or ContainsText(Msg, 'dropped') or
    ContainsText(Msg, 'unreachable') or ContainsText(Msg, 'refused') or
    ContainsText(Msg, 'did not respond');
end;

function ErrorFromSpawn(ASpawn: TSftpSpawnResult; const AOutput: string;
  AExitCode: Cardinal; const AURI: string; out AError: TVfsError): Boolean;
begin
  Result := False;
  case ASpawn of
    ssrCancelled:
      AError := TVfsError.Make(vecCancelled, 'Cancelled', AURI);
    ssrSpawnFailed:
      AError := TVfsError.Make(vecIOError, 'Cannot start sftp.exe', AURI);
    ssrTimeout:
      AError := ClassifySftpFailure(AOutput, AExitCode, True, False, AURI);
    ssrOk:
      if AExitCode = 0 then
      begin
        AError := TVfsError.Ok;
        Exit(True);
      end
      else
        AError := ClassifySftpFailure(AOutput, AExitCode, False, False, AURI);
  end;
end;

function RunSftpBatch(const AAuthority, ABatchCommands: string;
  ATimeoutMs: Cardinal; ACancel: IJobCancelToken; ARetries: Integer;
  out AOutput: string; out AError: TVfsError): Boolean;
var
  Exe, User, Host, Identity, URI: string;
  Port: Integer;
  Args: TArray<string>;
  ExitCode: Cardinal;
  Attempt: Integer;
begin
  AOutput := '';
  AError := TVfsError.Ok;
  URI := MakeSftpUri(AAuthority, '/');
  if not GetSftpExePath(Exe) then
  begin
    AError := TVfsError.Make(vecIOError,
      'sftp.exe not found in PATH. Install the OpenSSH client.', URI);
    Exit(False);
  end;
  SplitAuthority(AAuthority, User, Host, Port);
  Identity := IdentityFileForTarget(User, Host, Port);
  if (Identity <> '') and (not TFile.Exists(Identity)) then
  begin
    AError := TVfsError.Make(vecAccessDenied,
      'Identity file not found: ' + Identity +
      '. Edit Commands -> SSH/SFTP Connections... or use ssh-agent.', URI);
    Exit(False);
  end;
  Args := SftpBaseArgs(Host, Port, User, Identity);
  Attempt := 0;
  repeat
    if JobCancelRequested(ACancel) then
    begin
      AError := TVfsError.Make(vecCancelled, 'Cancelled', URI);
      Exit(False);
    end;
    if ErrorFromSpawn(RunCapturedProcess(Exe, Args, ABatchCommands, ATimeoutMs,
      ACancel, AOutput, ExitCode), AOutput, ExitCode, URI, AError) then
      Exit(True);
    if (Attempt >= ARetries) or (not SftpFailureIsTransient(AError)) then
      Exit(False);
    Inc(Attempt);
  until False;
end;

function NewTempFileName(const APrefix: string): string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := TPath.Combine(TPath.GetTempPath,
    APrefix + LowerCase(Copy(GUIDToString(G), 2, 36)) + '.tmp');
end;

procedure DeleteLocalTemp(const APath: string);
begin
  if APath = '' then
    Exit;
  if TFile.Exists(APath) then
    TFile.Delete(APath)
  else if TDirectory.Exists(APath) then
    TDirectory.Delete(APath, True);
end;

function QuoteRemotePath(const APath: string): string;
begin
  if Pos(' ', APath) > 0 then
    Result := '"' + StringReplace(APath, '"', '', [rfReplaceAll]) + '"'
  else
    Result := APath;
end;

function RunSftpLine(const AAuthority, ALine: string; ATimeoutMs: Cardinal;
  ACancel: IJobCancelToken; ARetries: Integer; out AOutput: string;
  out AError: TVfsError): Boolean;
begin
  Result := RunSftpBatch(AAuthority, ALine + #10, ATimeoutMs, ACancel, ARetries,
    AOutput, AError);
  if Result then
    AError := TVfsError.Ok;
end;

{ ---- `ls -la` parsing ------------------------------------------------------ }

function SplitLsFields(const ALine: string; out AFields: TArray<string>;
  out ANameStart: Integer): Boolean;
var
  Len, I, FieldStart, FieldCount: Integer;
begin
  Result := False;
  SetLength(AFields, 8);
  Len := Length(ALine);
  I := 1;
  FieldCount := 0;
  while (FieldCount < 8) and (I <= Len) do
  begin
    while (I <= Len) and (ALine[I] = ' ') do
      Inc(I);
    if I > Len then
      Break;
    FieldStart := I;
    while (I <= Len) and (ALine[I] <> ' ') do
      Inc(I);
    AFields[FieldCount] := Copy(ALine, FieldStart, I - FieldStart);
    Inc(FieldCount);
  end;
  if FieldCount < 8 then
    Exit;
  while (I <= Len) and (ALine[I] = ' ') do
    Inc(I);
  ANameStart := I;
  Result := ANameStart <= Len;
end;

function ParseSftpLsDate(const AMonth, ADay, ATimeOrYear: string): TDateTime;
const
  cMonths: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  M, D, Y, HH, MM, ColonPos: Integer;
  I: Integer;
begin
  Result := 0;
  M := 0;
  for I := 1 to 12 do
    if SameText(AMonth, cMonths[I]) then
    begin
      M := I;
      Break;
    end;
  if M = 0 then
    Exit;
  if not TryStrToInt(Trim(ADay), D) then
    Exit;
  ColonPos := Pos(':', ATimeOrYear);
  HH := 0;
  MM := 0;
  if ColonPos > 0 then
  begin
    Y := YearOf(Now);
    TryStrToInt(Copy(ATimeOrYear, 1, ColonPos - 1), HH);
    TryStrToInt(Copy(ATimeOrYear, ColonPos + 1, MaxInt), MM);
  end
  else if not TryStrToInt(Trim(ATimeOrYear), Y) then
    Y := YearOf(Now);
  try
    Result := EncodeDate(Y, M, D) + EncodeTime(HH, MM, 0, 0);
  except
    Result := 0;
  end;
end;

function ParseSftpLsLine(const ALine: string; out AEntry: TVfsEntry): Boolean;
var
  Fields: TArray<string>;
  NameStart: Integer;
  Perms, Name: string;
  ArrowPos: Integer;
  SizeVal: Int64;
begin
  Result := False;
  AEntry := Default(TVfsEntry);
  if not SplitLsFields(ALine, Fields, NameStart) then
    Exit;
  Perms := Fields[0];
  if (Perms = '') or not CharInSet(Perms[1], ['d', '-', 'l', 'b', 'c', 'p', 's']) then
    Exit;
  Name := Copy(ALine, NameStart, MaxInt);
  if Perms[1] = 'l' then
  begin
    ArrowPos := Pos(' -> ', Name);
    if ArrowPos > 0 then
      Name := Copy(Name, 1, ArrowPos - 1);
    AEntry.IsLink := True;
  end;
  Name := Name.TrimRight([#13]);
  if (Name = '.') or (Name = '..') or (Name = '') then
    Exit;
  AEntry.Name := Name;
  AEntry.Extension := Copy(TPath.GetExtension(Name), 2, MaxInt);
  AEntry.IsDirectory := (Perms[1] = 'd');
  if not TryStrToInt64(Fields[4], SizeVal) then
    SizeVal := 0;
  AEntry.Size := SizeVal;
  AEntry.ModificationTime := ParseSftpLsDate(Fields[5], Fields[6], Fields[7]);
  Result := True;
end;

function SftpListEntries(const AAuthority, ARemotePath: string;
  ACancel: IJobCancelToken; out AEntries: TArray<TVfsEntry>;
  out AError: TVfsError): Boolean;
var
  Output: string;
  Lines: TArray<string>;
  Line: string;
  Entry: TVfsEntry;
  Items: TList<TVfsEntry>;
begin
  SetLength(AEntries, 0);
  if not RunSftpLine(AAuthority, 'ls -la ' + QuoteRemotePath(ARemotePath),
    cListTimeoutMs, ACancel, cTransientRetries, Output, AError) then
    Exit(False);
  Items := TList<TVfsEntry>.Create;
  try
    Lines := Output.Split([#10]);
    for Line in Lines do
      if ParseSftpLsLine(Line, Entry) then
        Items.Add(Entry);
    AEntries := Items.ToArray;
  finally
    Items.Free;
  end;
  AError := TVfsError.Ok;
  Result := True;
end;

function SftpExists(const AAuthority, ARemotePath: string;
  ACancel: IJobCancelToken; out AExists, AIsDir: Boolean;
  out AError: TVfsError): Boolean;
var
  Parent, Base: string;
  Entries: TArray<TVfsEntry>;
  E: TVfsEntry;
  Slash: Integer;
begin
  AExists := False;
  AIsDir := False;
  if ARemotePath = '/' then
  begin
    AExists := True;
    AIsDir := True;
    AError := TVfsError.Ok;
    Exit(True);
  end;
  Slash := LastDelimiter('/', ARemotePath);
  if Slash <= 1 then
  begin
    Parent := '/';
    Base := Copy(ARemotePath, 2, MaxInt);
  end
  else
  begin
    Parent := Copy(ARemotePath, 1, Slash - 1);
    Base := Copy(ARemotePath, Slash + 1, MaxInt);
  end;
  if not SftpListEntries(AAuthority, Parent, ACancel, Entries, AError) then
    Exit(False);
  for E in Entries do
    if SameText(E.Name, Base) then
    begin
      AExists := True;
      AIsDir := E.IsDirectory;
      Break;
    end;
  AError := TVfsError.Ok;
  Result := True;
end;

function SftpMkdir(const AAuthority, ARemotePath: string;
  ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Output: string;
begin
  if not RunSftpLine(AAuthority, 'mkdir ' + QuoteRemotePath(ARemotePath),
    cListTimeoutMs, ACancel, 0, Output, AError) then
  begin
    if ContainsText(Output, 'Failure') and ContainsText(Output, 'exist') then
      AError := TVfsError.Make(vecAlreadyExists, Trim(Output),
        MakeSftpUri(AAuthority, ARemotePath));
    Exit(False);
  end;
  AError := TVfsError.Ok;
  Result := True;
end;

function SftpDelete(const AAuthority, ARemotePath: string; AIsDir: Boolean;
  ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Output: string;
begin
  Result := RunSftpLine(AAuthority, IfThen(AIsDir, 'rmdir ', 'rm ') +
    QuoteRemotePath(ARemotePath), cListTimeoutMs, ACancel, cTransientRetries,
    Output, AError);
end;

function SftpGetToLocal(const AAuthority, ARemotePath, ALocalPath: string;
  ARecursive: Boolean; ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Output: string;
begin
  Result := RunSftpLine(AAuthority, IfThen(ARecursive, 'get -r ', 'get ') +
    QuoteRemotePath(ARemotePath) + ' ' + QuoteCmdArg(ALocalPath),
    cTransferTimeoutMs, ACancel, cTransientRetries, Output, AError);
end;

function SftpPutFromLocal(const AAuthority, ALocalPath, ARemotePath: string;
  ARecursive: Boolean; ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Output: string;
begin
  Result := RunSftpLine(AAuthority, IfThen(ARecursive, 'put -r ', 'put ') +
    QuoteCmdArg(ALocalPath) + ' ' + QuoteRemotePath(ARemotePath),
    cTransferTimeoutMs, ACancel, cTransientRetries, Output, AError);
end;

{ ---- TSftpVirtualFileSystem ------------------------------------------------ }

procedure QueueBool(AOnDone: TVfsBoolCallback; ASuccess: Boolean;
  const AError: TVfsError);
var
  Ok: Boolean;
  Err: TVfsError;
  Done: TVfsBoolCallback;
begin
  if not Assigned(AOnDone) then
    Exit;
  Ok := ASuccess;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      Done(Ok, Err);
    end);
end;

procedure QueueList(AOnDone: TVfsListCallback; const AItems: TArray<TVfsEntry>;
  const AError: TVfsError);
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  Done: TVfsListCallback;
begin
  if not Assigned(AOnDone) then
    Exit;
  Items := AItems;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      Done(Items, Err);
    end);
end;

procedure QueueExists(AOnDone: TVfsExistsCallback; AExists, AIsDir: Boolean;
  const AError: TVfsError);
var
  Exists, IsDir: Boolean;
  Err: TVfsError;
  Done: TVfsExistsCallback;
begin
  if not Assigned(AOnDone) then
    Exit;
  Exists := AExists;
  IsDir := AIsDir;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      Done(Exists, IsDir, Err);
    end);
end;

procedure QueueBytes(AOnDone: TVfsBytesCallback; const ABytes: TBytes;
  const AError: TVfsError);
var
  Bytes: TBytes;
  Err: TVfsError;
  Done: TVfsBytesCallback;
begin
  if not Assigned(AOnDone) then
    Exit;
  Bytes := ABytes;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      Done(Bytes, Err);
    end);
end;

procedure StartSftpWork(const AWork: TProc);
begin
  TThread.CreateAnonymousThread(AWork).Start;
end;

procedure QueueSftpProgress(AOnProgress: TVfsProgressCallback;
  ADone, ATotal: Int64; const AName, ASrc, ADst: string);
var
  D, T: Int64;
  N, S, Dest: string;
  Prog: TVfsProgressCallback;
begin
  if not Assigned(AOnProgress) then
    Exit;
  D := ADone;
  T := ATotal;
  N := AName;
  S := ASrc;
  Dest := ADst;
  Prog := AOnProgress;
  TThread.Queue(nil,
    procedure
    begin
      Prog(D, T, N, 0, 0, S, Dest);
    end);
end;

function LocalDestExists(const APath: string): Boolean;
begin
  Result := (APath <> '') and (TFile.Exists(APath) or TDirectory.Exists(APath));
end;

function SftpDestExists(const AAuthority, ARemotePath: string;
  ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Exists, IsDir: Boolean;
begin
  Result := False;
  if not SftpExists(AAuthority, ARemotePath, ACancel, Exists, IsDir, AError) then
    Exit;
  AError := TVfsError.Ok;
  Result := Exists;
end;

function FailTransfer(out AError: TVfsError; ACode: TVfsErrorCode;
  const AMsg, AURI: string): Boolean;
begin
  AError := TVfsError.Make(ACode, AMsg, AURI);
  Result := False;
end;

function EnsureRemoteSource(const AAuthority, ARemotePath, AURI: string;
  ACancel: IJobCancelToken; out AIsDir: Boolean; out AError: TVfsError): Boolean;
var
  Exists: Boolean;
begin
  if not SftpExists(AAuthority, ARemotePath, ACancel, Exists, AIsDir, AError) then
    Exit(False);
  if not Exists then
    Exit(FailTransfer(AError, vecNotFound, 'Not found', AURI));
  Result := True;
end;

function AllowRemoteDest(const AAuthority, ARemotePath, AURI: string;
  AOverwrite: Boolean; ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
begin
  AError := TVfsError.Ok;
  if AOverwrite then
    Exit(True);
  if SftpDestExists(AAuthority, ARemotePath, ACancel, AError) then
  begin
    if AError.Code = vecOk then
      AError := TVfsError.Make(vecAlreadyExists, 'Destination exists', AURI);
    Exit(False);
  end;
  Result := AError.Code = vecOk;
end;

function SftpDownloadToLocal(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOverwrite: Boolean; out AError: TVfsError): Boolean;
var
  FromAuth, FromPath, LocalPath, Name: string;
  IsDir: Boolean;
begin
  Result := False;
  AError := TVfsError.Ok;
  Name := VfsUriTitle(AFromURI);
  FromAuth := SftpAuthorityOf(AFromURI);
  FromPath := SftpRemotePathOf(AFromURI);
  LocalPath := FileUriToPath(AToURI);
  if LocalPath = '' then
    Exit(FailTransfer(AError, vecInvalidURI, 'Invalid destination', AToURI));
  if (not AOverwrite) and LocalDestExists(LocalPath) then
    Exit(FailTransfer(AError, vecAlreadyExists, 'Destination exists', AToURI));
  if not EnsureRemoteSource(FromAuth, FromPath, AFromURI, ACancel, IsDir, AError) then
    Exit;
  QueueSftpProgress(AOnProgress, 0, 1, Name, AFromURI, AToURI);
  Result := SftpGetToLocal(FromAuth, FromPath, LocalPath, IsDir, ACancel, AError);
  if Result then
    QueueSftpProgress(AOnProgress, 1, 1, Name, AFromURI, AToURI);
end;

function SftpUploadFromLocal(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOverwrite: Boolean; out AError: TVfsError): Boolean;
var
  ToAuth, ToPath, LocalPath, Name: string;
begin
  Result := False;
  AError := TVfsError.Ok;
  Name := VfsUriTitle(AFromURI);
  ToAuth := SftpAuthorityOf(AToURI);
  ToPath := SftpRemotePathOf(AToURI);
  LocalPath := FileUriToPath(AFromURI);
  if LocalPath = '' then
    Exit(FailTransfer(AError, vecInvalidURI, 'Invalid source', AFromURI));
  if not AllowRemoteDest(ToAuth, ToPath, AToURI, AOverwrite, ACancel, AError) then
    Exit;
  QueueSftpProgress(AOnProgress, 0, 1, Name, AFromURI, AToURI);
  Result := SftpPutFromLocal(ToAuth, LocalPath, ToPath,
    LocalPathIsDirectory(LocalPath), ACancel, AError);
  if Result then
    QueueSftpProgress(AOnProgress, 1, 1, Name, AFromURI, AToURI);
end;

function SftpCopyViaTemp(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOverwrite: Boolean; out AError: TVfsError): Boolean;
var
  FromAuth, ToAuth, FromPath, ToPath, TempPath, Name: string;
  IsDir: Boolean;
begin
  Result := False;
  AError := TVfsError.Ok;
  Name := VfsUriTitle(AFromURI);
  FromAuth := SftpAuthorityOf(AFromURI);
  FromPath := SftpRemotePathOf(AFromURI);
  ToAuth := SftpAuthorityOf(AToURI);
  ToPath := SftpRemotePathOf(AToURI);
  if not AllowRemoteDest(ToAuth, ToPath, AToURI, AOverwrite, ACancel, AError) then
    Exit;
  if not EnsureRemoteSource(FromAuth, FromPath, AFromURI, ACancel, IsDir, AError) then
    Exit;
  TempPath := NewTempFileName('mtn2sftp_');
  try
    QueueSftpProgress(AOnProgress, 0, 2, Name, AFromURI, AToURI);
    if not SftpGetToLocal(FromAuth, FromPath, TempPath, IsDir, ACancel, AError) then
      Exit;
    QueueSftpProgress(AOnProgress, 1, 2, Name, AFromURI, AToURI);
    if not SftpPutFromLocal(ToAuth, TempPath, ToPath, IsDir, ACancel, AError) then
      Exit;
    QueueSftpProgress(AOnProgress, 2, 2, Name, AFromURI, AToURI);
    Result := True;
  finally
    DeleteLocalTemp(TempPath);
  end;
end;

function SftpTransfer(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;
begin
  AError := TVfsError.Ok;
  if JobCancelRequested(ACancel) then
    Exit(FailTransfer(AError, vecCancelled, 'Cancelled', AFromURI));
  if IsSftpUri(AFromURI) and not IsSftpUri(AToURI) then
    Exit(SftpDownloadToLocal(AFromURI, AToURI, ACancel, AOnProgress, AOverwrite, AError));
  if (not IsSftpUri(AFromURI)) and IsSftpUri(AToURI) then
    Exit(SftpUploadFromLocal(AFromURI, AToURI, ACancel, AOnProgress, AOverwrite, AError));
  if IsSftpUri(AFromURI) and IsSftpUri(AToURI) then
    Exit(SftpCopyViaTemp(AFromURI, AToURI, ACancel, AOnProgress, AOverwrite, AError));
  Result := FailTransfer(AError, vecNotSupported, 'Unsupported SFTP transfer', AFromURI);
end;

function SftpRenameSameHost(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Output: string;
begin
  Result := RunSftpLine(SftpAuthorityOf(AFromURI),
    'rename ' + QuoteRemotePath(SftpRemotePathOf(AFromURI)) + ' ' +
    QuoteRemotePath(SftpRemotePathOf(AToURI)),
    cListTimeoutMs, ACancel, cTransientRetries, Output, AError);
end;

function ReadTempFileCapped(const ATempPath, AURI: string; AMaxBytes: Int64;
  out ABytes: TBytes; out AError: TVfsError): Boolean;
begin
  SetLength(ABytes, 0);
  AError := TVfsError.Ok;
  if not TFile.Exists(ATempPath) then
    Exit(True);
  if TFile.GetSize(ATempPath) > AMaxBytes then
    Exit(FailTransfer(AError, vecNotSupported,
      Format('File too large (max %d KB).', [AMaxBytes div 1024]), AURI));
  ABytes := TFile.ReadAllBytes(ATempPath);
  Result := True;
end;

function SftpReadToBytes(const AAuthority, ARemotePath, AURI: string;
  AMaxBytes: Int64; ACancel: IJobCancelToken; out ABytes: TBytes;
  out AError: TVfsError): Boolean;
var
  TempPath: string;
begin
  SetLength(ABytes, 0);
  if JobCancelRequested(ACancel) then
    Exit(FailTransfer(AError, vecCancelled, 'Cancelled', AURI));
  TempPath := NewTempFileName('mtn2sftp_');
  try
    if not SftpGetToLocal(AAuthority, ARemotePath, TempPath, False, ACancel, AError) then
      Exit(False);
    try
      Result := ReadTempFileCapped(TempPath, AURI, AMaxBytes, ABytes, AError);
    except
      on E: Exception do
        Result := FailTransfer(AError, vecIOError, E.Message, AURI);
    end;
  finally
    DeleteLocalTemp(TempPath);
  end;
end;

function SftpWriteText(const AAuthority, ARemotePath, AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken;
  out AError: TVfsError): Boolean;
var
  TempPath: string;
begin
  Result := False;
  if JobCancelRequested(ACancel) then
    Exit(FailTransfer(AError, vecCancelled, 'Cancelled', AURI));
  TempPath := NewTempFileName('mtn2sftp_');
  try
    TFile.WriteAllBytes(TempPath, EncodeTextBytes(AText, AEncoding));
    Result := SftpPutFromLocal(AAuthority, TempPath, ARemotePath, False, ACancel, AError);
  except
    on E: Exception do
      FailTransfer(AError, vecIOError, E.Message, AURI);
  end;
  DeleteLocalTemp(TempPath);
end;

function DeleteTransferredSource(const AFromURI: string;
  ACancel: IJobCancelToken; out AError: TVfsError): Boolean;
var
  Authority, FromPath: string;
  Exists, IsDir: Boolean;
begin
  Result := False;
  if IsSftpUri(AFromURI) then
  begin
    Authority := SftpAuthorityOf(AFromURI);
    FromPath := SftpRemotePathOf(AFromURI);
    if SftpExists(Authority, FromPath, ACancel, Exists, IsDir, AError) and Exists then
      Result := SftpDelete(Authority, FromPath, IsDir, ACancel, AError)
    else
      Result := AError.Code = vecOk;
    Exit;
  end;
  try
    if LocalPathIsDirectory(FileUriToPath(AFromURI)) then
      TDirectory.Delete(FileUriToPath(AFromURI), True)
    else
      TFile.Delete(FileUriToPath(AFromURI));
    AError := TVfsError.Ok;
    Result := True;
  except
    on E: Exception do
      AError := TVfsError.Make(vecIOError, E.Message, AFromURI);
  end;
end;

procedure TSftpVirtualFileSystem.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  Authority, RemotePath: string;
  OnDone: TVfsListCallback;
  Cancel: IJobCancelToken;
begin
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
    begin
      SftpListEntries(Authority, RemotePath, Cancel, Items, Err);
      QueueList(OnDone, Items, Err);
    end);
end;

procedure TSftpVirtualFileSystem.ExistsAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsExistsCallback);
var
  Authority, RemotePath: string;
  OnDone: TVfsExistsCallback;
  Cancel: IJobCancelToken;
begin
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Exists, IsDir: Boolean;
      Err: TVfsError;
    begin
      SftpExists(Authority, RemotePath, Cancel, Exists, IsDir, Err);
      QueueExists(OnDone, Exists, IsDir, Err);
    end);
end;

procedure TSftpVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  Authority, RemotePath: string;
  OnDone: TVfsBoolCallback;
  Cancel: IJobCancelToken;
begin
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Ok: Boolean;
      Err: TVfsError;
    begin
      Ok := SftpMkdir(Authority, RemotePath, Cancel, Err);
      QueueBool(OnDone, Ok, Err);
    end);
end;

procedure TSftpVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI, Authority, RemotePath: string;
  OnDone: TVfsBoolCallback;
  Cancel: IJobCancelToken;
begin
  URI := AURI;
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Exists, IsDir, Ok: Boolean;
      Err: TVfsError;
    begin
      Ok := False;
      if SftpExists(Authority, RemotePath, Cancel, Exists, IsDir, Err) then
      begin
        if not Exists then
          Err := TVfsError.Make(vecNotFound, 'Not found', URI)
        else
          Ok := SftpDelete(Authority, RemotePath, IsDir, Cancel, Err);
      end;
      QueueBool(OnDone, Ok, Err);
    end);
end;

procedure TSftpVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI, Authority, RemotePath: string;
  MaxBytes: Int64;
  OnDone: TVfsBytesCallback;
  Cancel: IJobCancelToken;
begin
  URI := AURI;
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  MaxBytes := AMaxBytes;
  if MaxBytes <= 0 then
    MaxBytes := cDefaultReadMaxBytes;
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Bytes: TBytes;
      Err: TVfsError;
    begin
      SftpReadToBytes(Authority, RemotePath, URI, MaxBytes, Cancel, Bytes, Err);
      QueueBytes(OnDone, Bytes, Err);
    end);
end;

procedure TSftpVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  OnDone: TVfsTextCallback;
begin
  OnDone := AOnDone;
  ReadBytesAsync(AURI, AMaxBytes, ACancel,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    begin
      if Assigned(OnDone) then
        OnDone(TEncoding.UTF8.GetString(ABytes), tfeUtf8, AError);
    end);
end;

procedure TSftpVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI, Authority, RemotePath, Text: string;
  Encoding: TTextFileEncoding;
  OnDone: TVfsBoolCallback;
  Cancel: IJobCancelToken;
begin
  URI := AURI;
  Authority := SftpAuthorityOf(AURI);
  RemotePath := SftpRemotePathOf(AURI);
  Text := AText;
  Encoding := AEncoding;
  OnDone := AOnDone;
  Cancel := ACancel;
  StartSftpWork(
    procedure
    var
      Ok: Boolean;
      Err: TVfsError;
    begin
      Ok := SftpWriteText(Authority, RemotePath, URI, Text, Encoding, Cancel, Err);
      QueueBool(OnDone, Ok, Err);
    end);
end;

procedure TSftpVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  OnDone: TVfsBoolCallback;
  OnProgress: TVfsProgressCallback;
  Cancel: IJobCancelToken;
  Overwrite: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  OnDone := AOnDone;
  OnProgress := AOnProgress;
  Cancel := ACancel;
  Overwrite := AOverwrite;
  StartSftpWork(
    procedure
    var
      Ok: Boolean;
      Err: TVfsError;
    begin
      Ok := SftpTransfer(FromURI, ToURI, Cancel, OnProgress, Overwrite, Err);
      QueueBool(OnDone, Ok, Err);
    end);
end;

procedure TSftpVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  OnDone: TVfsBoolCallback;
  OnProgress: TVfsProgressCallback;
  Cancel: IJobCancelToken;
  Overwrite: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  OnDone := AOnDone;
  OnProgress := AOnProgress;
  Cancel := ACancel;
  Overwrite := AOverwrite;
  StartSftpWork(
    procedure
    var
      Ok: Boolean;
      Err: TVfsError;
    begin
      Ok := False;
      if IsSftpUri(FromURI) and IsSftpUri(ToURI) and
         SameText(SftpAuthorityOf(FromURI), SftpAuthorityOf(ToURI)) then
        Ok := SftpRenameSameHost(FromURI, ToURI, Cancel, Err)
      else if SftpTransfer(FromURI, ToURI, Cancel, OnProgress, Overwrite, Err) then
        Ok := DeleteTransferredSource(FromURI, Cancel, Err);
      QueueBool(OnDone, Ok, Err);
    end);
end;

procedure TSftpVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  URI: string;
  OnDone: TVfsFreeSpaceCallback;
begin
  URI := ARootURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone(-1, -1, TVfsError.Make(vecNotSupported, 'Not supported', URI));
      end);
end;

end.
