unit uConPty;

{ Process bridge for the console windows (POSIX build): a shell or command
  running on a pseudo-terminal made by forkpty. Output is delivered to
  OnOutput on the main thread in UTF-8 decoded chunks, the exit of the child to
  OnExit. The Windows build lives in Platform\Windows; each project puts
  exactly one of the two directories on its unit search path.

  The child is set up before the fork (arguments, environment, working
  directory); between fork and exec only plain libc calls run. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, uShellProfiles;

type
  TConPtyOutputEvent = reference to procedure(const AText: string);
  TConPtyExitEvent = reference to procedure(AExitCode: Cardinal);

  /// <summary>Long-lived panel / workspace shell session.</summary>
  IPtySession = interface
    ['{A7C2E901-4B1D-4F0A-9C3E-2D8F6B1A0E55}']
    function StartShell(const AProfile, ACwd: string; ACols, ARows: Word): Boolean;
    procedure WriteInput(const AText: string);
    procedure Resize(ACols, ARows: Word);
    procedure Terminate;
    function IsRunning: Boolean;
  end;

  TConPtySession = class;

  /// <summary>Link between a session and its reader thread: the thread keeps
  /// the link, the session detaches it on destruction, so a late chunk never
  /// reaches freed session state.</summary>
  TPtyLife = class(TInterfacedObject)
  private
    FLock: TCriticalSection;
    FSession: TConPtySession;
  public
    constructor Create(ASession: TConPtySession);
    destructor Destroy; override;
    procedure Detach;
    procedure Deliver(AEpoch: Integer; const AText: string);
    procedure Flush(AEpoch: Integer);
    procedure NotifyExit(AEpoch: Integer; ACode: Cardinal);
  end;

  TConPtySession = class
  private
    FRunning: Boolean;
    FPersistent: Boolean;
    FLastError: string;
    FMasterFd: Integer;
    FPid: Integer;
    FLife: TPtyLife;
    FLifeRef: IInterface;
    FPendingText: string;
    FFlushQueued: Boolean;
    FEpoch: Integer;
    FProfileId: string;
    FDecodeTail: TBytes;
    FOnOutput: TConPtyOutputEvent;
    FOnExit: TConPtyExitEvent;
    function DecodePtyChunk(const ABuf: TBytes; ACount: Integer): string;
    procedure BeginSession(AOnOutput: TConPtyOutputEvent;
      AOnExit: TConPtyExitEvent; APersistent: Boolean);
    function Launch(const ACmdLine, AWorkingDir: string; ACols, ARows: Word): Boolean;
    procedure StopChild;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>One-shot: runs ACommand through /bin/sh -c.</summary>
    function Start(const ACommand, AWorkingDir: string; ACols, ARows: Word;
      AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
    /// <summary>Persistent interactive shell of a profile.</summary>
    function StartShell(const AProfile, ACwd: string; ACols, ARows: Word): Boolean; overload;
    function StartShell(const ACwd: string; ACols, ARows: Word;
      AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean; overload;
    procedure WriteInput(const AText: string);
    procedure Resize(ACols, ARows: Word);
    procedure Terminate;
    function IsRunning: Boolean;
    /// <summary>The shell has a foreground command running.</summary>
    function HasChildProcess: Boolean;
    /// <summary>Current folder of the shell process (/proc/&lt;pid&gt;/cwd); '' when unknown.</summary>
    function ShellCwd: string;
    property LastError: string read FLastError;
    property Persistent: Boolean read FPersistent;
    property ProfileId: string read FProfileId write FProfileId;
    property OnOutput: TConPtyOutputEvent read FOnOutput write FOnOutput;
    property OnExit: TConPtyExitEvent read FOnExit write FOnExit;
    /// <summary>Decodes one output chunk; an incomplete UTF-8 sequence at its
    /// end is held back for the next chunk.</summary>
    function DecodeOutputChunk(const ABuf: TBytes): string;
  end;

function ConPtyAvailable: Boolean;
function BuildCmdLineForShell(const ACommand: string): string;
function BuildPersistentShellCmdLine(const AProfile: string = ''): string;
function QuoteCmdPath(const APath: string): string;
/// <summary>Always False: there is no WSL launcher on this platform.</summary>
function IsWslCommandString(const ALowerCmd: string): Boolean;

implementation

uses
  System.Math, Posix.Base, Posix.Dlfcn, Posix.Errno;

const
  SIGKILL = 9;
  TIOCSWINSZ = $5414;
  cReadChunk = 8192;

type
  TWinSize = record
    Rows: Word;
    Cols: Word;
    XPixel: Word;
    YPixel: Word;
  end;

  PPAnsiChar = ^MarshaledAString;
  PPPAnsiChar = ^PPAnsiChar;

  TForkPty = function(AMaster: PInteger; AName: MarshaledAString;
    ATermios, AWinSize: Pointer): Integer; cdecl;

  TPtyReaderThread = class(TThread)
  private
    FLife: IInterface;
    FLifeObj: TPtyLife;
    FFd: Integer;
    FPid: Integer;
    FEpoch: Integer;
    FSession: TConPtySession;
  protected
    procedure Execute; override;
  public
    constructor Create(const ALife: IInterface; ALifeObj: TPtyLife; AFd, APid,
      AEpoch: Integer; ASession: TConPtySession);
  end;

var
  GForkPty: TForkPty;
  GForkResolved: Boolean;

function c_read(AFd: Integer; ABuf: Pointer; ACount: NativeUInt): NativeInt; cdecl;
  external libc name 'read';
function c_write(AFd: Integer; ABuf: Pointer; ACount: NativeUInt): NativeInt; cdecl;
  external libc name 'write';
function c_close(AFd: Integer): Integer; cdecl; external libc name 'close';
function c_kill(APid, ASig: Integer): Integer; cdecl; external libc name 'kill';
function c_waitpid(APid: Integer; AStatus: PInteger; AOptions: Integer): Integer; cdecl;
  external libc name 'waitpid';
function c_chdir(APath: MarshaledAString): Integer; cdecl; external libc name 'chdir';
function c_execvpe(AFile: MarshaledAString; AArgv, AEnvp: PPAnsiChar): Integer; cdecl;
  external libc name 'execvpe';
procedure c_exit(AStatus: Integer); cdecl; external libc name '_exit';
function c_ioctl(AFd: Integer; ARequest: NativeUInt; AArg: Pointer): Integer; cdecl;
  external libc name 'ioctl';
function c_tcgetpgrp(AFd: Integer): Integer; cdecl; external libc name 'tcgetpgrp';
function c_readlink(APath, ABuf: MarshaledAString; ASize: NativeUInt): NativeInt; cdecl;
  external libc name 'readlink';

function ResolveForkPty: Boolean;
var
  H: NativeUInt;
  P: Pointer;
begin
  if not GForkResolved then
  begin
    GForkResolved := True;
    P := dlsym(0, 'forkpty');
    if P = nil then
    begin
      H := dlopen('libutil.so.1', RTLD_NOW);
      if H <> 0 then
        P := dlsym(H, 'forkpty');
    end;
    GForkPty := TForkPty(P);
  end;
  Result := Assigned(GForkPty);
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

// Splits a command line made by QuoteArgIfNeeded: arguments separated by
// blanks, double quotes group.
function SplitCmdLine(const ACmdLine: string): TArray<string>;
var
  I: Integer;
  Cur: string;
  InQuote, Has: Boolean;
  List: TArray<string>;

  procedure Push;
  begin
    if Has then
    begin
      SetLength(List, Length(List) + 1);
      List[High(List)] := Cur;
    end;
    Cur := '';
    Has := False;
  end;

begin
  SetLength(List, 0);
  Cur := '';
  InQuote := False;
  Has := False;
  for I := 1 to Length(ACmdLine) do
    if ACmdLine[I] = '"' then
    begin
      InQuote := not InQuote;
      Has := True;
    end
    else if (ACmdLine[I] = ' ') and not InQuote then
      Push
    else
    begin
      Cur := Cur + ACmdLine[I];
      Has := True;
    end;
  Push;
  Result := List;
end;

function ConPtyAvailable: Boolean;
begin
  Result := ResolveForkPty;
end;

function IsWslCommandString(const ALowerCmd: string): Boolean;
begin
  Result := False;
end;

function BuildCmdLineForShell(const ACommand: string): string;
begin
  Result := Trim(ACommand);
end;

function BuildPersistentShellCmdLine(const AProfile: string): string;
var
  Cmd, Cwd: string;
begin
  if ResolveShellCmdLine(AProfile, '', Cmd, Cwd) then
    Result := Cmd
  else
    Result := '/bin/sh -i';
end;

function QuoteCmdPath(const APath: string): string;
begin
  Result := QuoteCmdExePath(APath);
end;

{ TPtyLife }

constructor TPtyLife.Create(ASession: TConPtySession);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSession := ASession;
end;

destructor TPtyLife.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TPtyLife.Detach;
begin
  FLock.Enter;
  try
    FSession := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TPtyLife.Deliver(AEpoch: Integer; const AText: string);
var
  Queue: Boolean;
  Hold: IInterface;
begin
  Queue := False;
  FLock.Enter;
  try
    if (FSession = nil) or (FSession.FEpoch <> AEpoch) then
      Exit;
    FSession.FPendingText := FSession.FPendingText + AText;
    if not FSession.FFlushQueued then
    begin
      FSession.FFlushQueued := True;
      Queue := True;
    end;
  finally
    FLock.Leave;
  end;
  if Queue then
  begin
    // The queued call holds a reference: the link must outlive the session
    // and the reader thread until the main thread has run it.
    Hold := Self;
    TThread.Queue(nil,
      procedure
      begin
        (Hold as TPtyLife).Flush(AEpoch);
      end);
  end;
end;

procedure TPtyLife.Flush(AEpoch: Integer);
var
  Text: string;
  Cb: TConPtyOutputEvent;
begin
  Text := '';
  Cb := nil;
  FLock.Enter;
  try
    if (FSession = nil) or (FSession.FEpoch <> AEpoch) then
      Exit;
    Text := FSession.FPendingText;
    FSession.FPendingText := '';
    FSession.FFlushQueued := False;
    Cb := FSession.FOnOutput;
  finally
    FLock.Leave;
  end;
  if (Text <> '') and Assigned(Cb) then
    Cb(Text);
end;

procedure TPtyLife.NotifyExit(AEpoch: Integer; ACode: Cardinal);
var
  Hold: IInterface;
begin
  Hold := Self;
  TThread.Queue(nil,
    procedure
    var
      Self_: TPtyLife;
      Cb: TConPtyExitEvent;
      Mine: Boolean;
    begin
      Self_ := Hold as TPtyLife;
      Self_.Flush(AEpoch);
      Cb := nil;
      Mine := False;
      Self_.FLock.Enter;
      try
        if (Self_.FSession <> nil) and (Self_.FSession.FEpoch = AEpoch) then
        begin
          Mine := True;
          Self_.FSession.FRunning := False;
          Cb := Self_.FSession.FOnExit;
        end;
      finally
        Self_.FLock.Leave;
      end;
      if Mine and Assigned(Cb) then
        Cb(ACode);
    end);
end;

{ TPtyReaderThread }

constructor TPtyReaderThread.Create(const ALife: IInterface; ALifeObj: TPtyLife;
  AFd, APid, AEpoch: Integer; ASession: TConPtySession);
begin
  FLife := ALife;
  FLifeObj := ALifeObj;
  FFd := AFd;
  FPid := APid;
  FEpoch := AEpoch;
  FSession := ASession;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TPtyReaderThread.Execute;
var
  Buf: TBytes;
  N: NativeInt;
  Status: Integer;
  Code: Cardinal;
  Tail: TBytes;
  Text: string;

  function Decode(ACount: Integer): string;
  var
    Data: TBytes;
    Keep, K: Integer;
    B: Byte;
    Need: Integer;
  begin
    SetLength(Data, Length(Tail) + ACount);
    if Length(Tail) > 0 then
      Move(Tail[0], Data[0], Length(Tail));
    Move(Buf[0], Data[Length(Tail)], ACount);
    Keep := 0;
    for K := 1 to Min(3, Length(Data)) do
    begin
      B := Data[Length(Data) - K];
      if (B and $C0) = $80 then
        Continue;
      if B >= $C0 then
      begin
        if B >= $F0 then
          Need := 4
        else if B >= $E0 then
          Need := 3
        else
          Need := 2;
        if Need > K then
          Keep := K;
      end;
      Break;
    end;
    Tail := Copy(Data, Length(Data) - Keep, Keep);
    Result := TEncoding.UTF8.GetString(Data, 0, Length(Data) - Keep);
  end;

begin
  SetLength(Buf, cReadChunk);
  SetLength(Tail, 0);
  while True do
  begin
    N := c_read(FFd, @Buf[0], Length(Buf));
    if N < 0 then
    begin
      if GetLastError = EINTR then
        Continue;
      Break;
    end;
    if N = 0 then
      Break;
    Text := Decode(Integer(N));
    if Text <> '' then
      FLifeObj.Deliver(FEpoch, Text);
  end;
  c_close(FFd);
  Status := 0;
  c_waitpid(FPid, @Status, 0);
  if (Status and $7F) = 0 then
    Code := Cardinal((Status shr 8) and $FF)
  else
    Code := Cardinal(128 + (Status and $7F));
  FLifeObj.NotifyExit(FEpoch, Code);
  FLife := nil;
end;

{ TConPtySession }

constructor TConPtySession.Create;
begin
  inherited Create;
  FMasterFd := -1;
  FLife := TPtyLife.Create(Self);
  FLifeRef := FLife;
end;

destructor TConPtySession.Destroy;
begin
  FOnOutput := nil;
  FOnExit := nil;
  StopChild;
  FLife.Detach;
  FLifeRef := nil;
  FLife := nil;
  inherited Destroy;
end;

procedure TConPtySession.StopChild;
begin
  Inc(FEpoch);
  FRunning := False;
  FPendingText := '';
  if FPid > 0 then
  begin
    // The child leads its own process group: the whole job ends with it.
    c_kill(-FPid, SIGKILL);
    c_kill(FPid, SIGKILL);
  end;
  FPid := 0;
  FMasterFd := -1;
end;

procedure TConPtySession.BeginSession(AOnOutput: TConPtyOutputEvent;
  AOnExit: TConPtyExitEvent; APersistent: Boolean);
begin
  StopChild;
  SetLength(FDecodeTail, 0);
  FLastError := '';
  FPersistent := APersistent;
  if Assigned(AOnOutput) then
    FOnOutput := AOnOutput;
  if Assigned(AOnExit) then
    FOnExit := AOnExit;
end;

function TConPtySession.Launch(const ACmdLine, AWorkingDir: string;
  ACols, ARows: Word): Boolean;
var
  Args: TArray<string>;
  ArgStore, EnvStore: TArray<UTF8String>;
  Argv, Envp: TArray<MarshaledAString>;
  Cwd: UTF8String;
  CwdPtr: MarshaledAString;
  WS: TWinSize;
  Master, Pid, I, N: Integer;
  Cur: PPAnsiChar;
  HasTerm, HasColor: Boolean;
  Entry: string;
begin
  Result := False;
  if not ResolveForkPty then
  begin
    FLastError := 'forkpty is not available';
    Exit;
  end;
  Args := SplitCmdLine(ACmdLine);
  if Length(Args) = 0 then
  begin
    FLastError := 'Empty command';
    Exit;
  end;

  SetLength(ArgStore, Length(Args));
  SetLength(Argv, Length(Args) + 1);
  for I := 0 to High(Args) do
  begin
    ArgStore[I] := UTF8String(Args[I]);
    Argv[I] := MarshaledAString(ArgStore[I]);
  end;
  Argv[High(Argv)] := nil;

  SetLength(EnvStore, 0);
  HasTerm := False;
  HasColor := False;
  Cur := CurrentEnvironment;
  while (Cur <> nil) and (Cur^ <> nil) do
  begin
    Entry := UTF8ToString(Cur^);
    if Entry.StartsWith('TERM=') then
      HasTerm := True;
    if Entry.StartsWith('COLORTERM=') then
      HasColor := True;
    SetLength(EnvStore, Length(EnvStore) + 1);
    EnvStore[High(EnvStore)] := UTF8String(Entry);
    Inc(Cur);
  end;
  if not HasTerm then
  begin
    SetLength(EnvStore, Length(EnvStore) + 1);
    EnvStore[High(EnvStore)] := 'TERM=xterm-256color';
  end;
  if not HasColor then
  begin
    SetLength(EnvStore, Length(EnvStore) + 1);
    EnvStore[High(EnvStore)] := 'COLORTERM=truecolor';
  end;
  N := Length(EnvStore);
  SetLength(Envp, N + 1);
  for I := 0 to N - 1 do
    Envp[I] := MarshaledAString(EnvStore[I]);
  Envp[N] := nil;

  Cwd := UTF8String(Trim(AWorkingDir));
  if Cwd = '' then
    CwdPtr := nil
  else
    CwdPtr := MarshaledAString(Cwd);

  WS.Rows := Max(ARows, 1);
  WS.Cols := Max(ACols, 1);
  WS.XPixel := 0;
  WS.YPixel := 0;

  Master := -1;
  Pid := GForkPty(@Master, nil, nil, @WS);
  if Pid = 0 then
  begin
    // Child: nothing but libc calls from here to exec.
    if CwdPtr <> nil then
      c_chdir(CwdPtr);
    c_execvpe(Argv[0], PPAnsiChar(@Argv[0]), PPAnsiChar(@Envp[0]));
    c_exit(127);
  end;
  if Pid < 0 then
  begin
    FLastError := SysErrorMessage(GetLastError);
    Exit;
  end;

  FMasterFd := Master;
  FPid := Pid;
  FRunning := True;
  TPtyReaderThread.Create(FLifeRef, FLife, Master, Pid, FEpoch, Self);
  Result := True;
end;

function TConPtySession.Start(const ACommand, AWorkingDir: string; ACols, ARows: Word;
  AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
begin
  BeginSession(AOnOutput, AOnExit, False);
  Result := Launch('/bin/sh -c ' + '"' + StringReplace(ACommand, '"', '', [rfReplaceAll]) + '"',
    AWorkingDir, ACols, ARows);
end;

function TConPtySession.StartShell(const AProfile, ACwd: string; ACols,
  ARows: Word): Boolean;
var
  CmdLine, WorkDir: string;
begin
  BeginSession(nil, nil, True);
  if AProfile <> '' then
    FProfileId := AProfile;
  if not ResolveShellCmdLine(AProfile, ACwd, CmdLine, WorkDir) then
  begin
    FLastError := 'Shell profile is not available: ' + AProfile;
    Exit(False);
  end;
  if WorkDir = '' then
    WorkDir := Trim(ACwd);
  Result := Launch(CmdLine, WorkDir, ACols, ARows);
end;

function TConPtySession.StartShell(const ACwd: string; ACols, ARows: Word;
  AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
begin
  BeginSession(AOnOutput, AOnExit, True);
  Result := Launch(BuildPersistentShellCmdLine(''), ACwd, ACols, ARows);
end;

procedure TConPtySession.WriteInput(const AText: string);
var
  Bytes: TBytes;
  Offset: Integer;
  N: NativeInt;
begin
  if AText = '' then
    Exit;
  if not IsRunning then
  begin
    FLastError := 'Shell is not running';
    Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Offset := 0;
  while Offset < Length(Bytes) do
  begin
    N := c_write(FMasterFd, @Bytes[Offset], Length(Bytes) - Offset);
    if N < 0 then
    begin
      if GetLastError = EINTR then
        Continue;
      Break;
    end;
    Inc(Offset, N);
  end;
end;

procedure TConPtySession.Resize(ACols, ARows: Word);
var
  WS: TWinSize;
begin
  if not IsRunning then
    Exit;
  WS.Rows := Max(ARows, 1);
  WS.Cols := Max(ACols, 1);
  WS.XPixel := 0;
  WS.YPixel := 0;
  c_ioctl(FMasterFd, TIOCSWINSZ, @WS);
end;

procedure TConPtySession.Terminate;
begin
  StopChild;
end;

function TConPtySession.IsRunning: Boolean;
begin
  Result := FRunning and (FPid > 0);
end;

function TConPtySession.ShellCwd: string;
var
  Path: UTF8String;
  Buf: TBytes;
  N: NativeInt;
begin
  Result := '';
  if not IsRunning then
    Exit;
  Path := UTF8String('/proc/' + IntToStr(FPid) + '/cwd');
  SetLength(Buf, 4096);
  N := c_readlink(MarshaledAString(Path), MarshaledAString(@Buf[0]), Length(Buf) - 1);
  if N > 0 then
    Result := TEncoding.UTF8.GetString(Buf, 0, N);
end;

function TConPtySession.HasChildProcess: Boolean;
var
  Fg: Integer;
begin
  Result := False;
  if not IsRunning then
    Exit;
  Fg := c_tcgetpgrp(FMasterFd);
  Result := (Fg > 0) and (Fg <> FPid);
end;

function TConPtySession.DecodePtyChunk(const ABuf: TBytes; ACount: Integer): string;
var
  Data: TBytes;
  Keep, K, Need: Integer;
  B: Byte;
begin
  SetLength(Data, Length(FDecodeTail) + ACount);
  if Length(FDecodeTail) > 0 then
    Move(FDecodeTail[0], Data[0], Length(FDecodeTail));
  if ACount > 0 then
    Move(ABuf[0], Data[Length(FDecodeTail)], ACount);
  Keep := 0;
  for K := 1 to Min(3, Length(Data)) do
  begin
    B := Data[Length(Data) - K];
    if (B and $C0) = $80 then
      Continue;
    if B >= $C0 then
    begin
      if B >= $F0 then
        Need := 4
      else if B >= $E0 then
        Need := 3
      else
        Need := 2;
      if Need > K then
        Keep := K;
    end;
    Break;
  end;
  FDecodeTail := Copy(Data, Length(Data) - Keep, Keep);
  Result := TEncoding.UTF8.GetString(Data, 0, Length(Data) - Keep);
end;

function TConPtySession.DecodeOutputChunk(const ABuf: TBytes): string;
begin
  Result := DecodePtyChunk(ABuf, Length(ABuf));
end;

end.
