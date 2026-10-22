unit uInstanceSocket;

{ One window per user for the graphical Linux build (mtn2-sdl <path>). The first
  instance listens on a Unix socket; a later start hands its path over and
  exits, and the first instance opens it in a new tab and raises its window.
  The socket lives in $XDG_RUNTIME_DIR (private to the user) or, without it,
  in /tmp under a name that carries the user id; its mode is 0600, so only the
  same user can connect. A socket file left by a crashed instance is detected
  (nobody answers) and replaced. The Windows build does the same with a named
  mutex and WM_COPYDATA (uSingleInstance). }

interface

uses
  System.SysUtils;

/// <summary>Sends APath ('' = just bring the window up) to the instance that
/// listens under AName and waits for its acknowledgement. False when nobody
/// answers, so the caller starts normally.</summary>
function InstanceTryHandOver(const AName, APath: string): Boolean;

/// <summary>Starts listening under AName; AOnPath runs on the main thread (it
/// needs CheckSynchronize to be called, as the SDL host loop does) for every
/// path a later start hands over. False when the socket cannot be set up.</summary>
function InstanceStartListening(const AName: string;
  const AOnPath: TProc<string>): Boolean;

/// <summary>Stops listening and removes the socket file.</summary>
procedure InstanceStopListening;

/// <summary>The socket path used for AName.</summary>
function InstanceSocketPath(const AName: string): string;

implementation

uses
  System.Classes, Posix.Base, Posix.SysSocket, Posix.SysUn, Posix.Unistd,
  Posix.SysStat;

const
  cPollIn = 1;
  cMaxRequestBytes = 4096;
  cAck: array[0..2] of Byte = (Ord('O'), Ord('K'), 10);
  cHandOverTimeoutMs = 2000;
  cPollMs = 200;

type
  TPollFd = record
    fd: Integer;
    events: SmallInt;
    revents: SmallInt;
  end;

  TListener = class(TThread)
  private
    FSocket: Integer;
    FPath: string;
    FOnPath: TProc<string>;
    procedure Serve(AClient: Integer);
  protected
    procedure Execute; override;
  public
    constructor Create(ASocket: Integer; const APath: string;
      const AOnPath: TProc<string>);
  end;

var
  GListener: TListener;

function InstanceSocketPath(const AName: string): string;
var
  Dir: string;
begin
  Dir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if (Dir <> '') and DirectoryExists(Dir) then
    Result := IncludeTrailingPathDelimiter(Dir) + 'mtn2-' + AName + '.sock'
  else
    Result := '/tmp/mtn2-' + IntToStr(getuid) + '-' + AName + '.sock';
end;

function MakeAddress(const APath: string; out AAddr: sockaddr_un): Boolean;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(APath);
  // sun_path holds 108 bytes including the terminating zero.
  if Length(Bytes) >= SizeOf(AAddr.sun_path) then
    Exit(False);
  FillChar(AAddr, SizeOf(AAddr), 0);
  AAddr.sun_family := AF_UNIX;
  if Length(Bytes) > 0 then
    Move(Bytes[0], AAddr.sun_path[0], Length(Bytes));
  Result := True;
end;

// Waits until AFd is readable; False on timeout or error.
function c_poll(AFds: Pointer; ACount: NativeUInt; ATimeoutMs: Integer): Integer; cdecl;
  external libc name 'poll';

function WaitReadable(AFd, ATimeoutMs: Integer): Boolean;
var
  Fds: TPollFd;
begin
  Fds.fd := AFd;
  Fds.events := cPollIn;
  Fds.revents := 0;
  Result := (c_poll(@Fds, 1, ATimeoutMs) > 0) and ((Fds.revents and cPollIn) <> 0);
end;

function ConnectTo(const APath: string): Integer;
var
  Addr: sockaddr_un;
begin
  Result := socket(AF_UNIX, SOCK_STREAM, 0);
  if Result < 0 then
    Exit(-1);
  if not MakeAddress(APath, Addr) or
     (connect(Result, psockaddr(@Addr)^, SizeOf(Addr)) <> 0) then
  begin
    __close(Result);
    Result := -1;
  end;
end;

function InstanceTryHandOver(const AName, APath: string): Boolean;
var
  Fd: Integer;
  Bytes: TBytes;
  Reply: array[0..7] of Byte;
  Sent, N: NativeInt;
begin
  Result := False;
  Fd := ConnectTo(InstanceSocketPath(AName));
  if Fd < 0 then
    Exit;
  try
    Bytes := TEncoding.UTF8.GetBytes(APath + #10);
    if Length(Bytes) > cMaxRequestBytes then
      Exit;
    Sent := 0;
    while Sent < Length(Bytes) do
    begin
      N := send(Fd, Bytes[Sent], Length(Bytes) - Sent, 0);
      if N <= 0 then
        Exit;
      Inc(Sent, N);
    end;
    // The reply is two bytes; no reply in time means the other side is stuck.
    if not WaitReadable(Fd, cHandOverTimeoutMs) then
      Exit;
    N := recv(Fd, Reply[0], SizeOf(Reply), 0);
    Result := (N >= 2) and (Reply[0] = Ord('O')) and (Reply[1] = Ord('K'));
  finally
    __close(Fd);
  end;
end;

{ TListener }

constructor TListener.Create(ASocket: Integer; const APath: string;
  const AOnPath: TProc<string>);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FSocket := ASocket;
  FPath := APath;
  FOnPath := AOnPath;
end;

procedure TListener.Serve(AClient: Integer);
var
  Buf: array[0..cMaxRequestBytes - 1] of Byte;
  Have, N: NativeInt;
  Line: string;
  Cb: TProc<string>;
  Run: TThreadProcedure;
  Raw: TBytes;
begin
  Have := 0;
  while Have < SizeOf(Buf) do
  begin
    if not WaitReadable(AClient, cHandOverTimeoutMs) then
      Exit;
    N := recv(AClient, Buf[Have], SizeOf(Buf) - Have, 0);
    if N <= 0 then
      Break;
    Inc(Have, N);
    if Buf[Have - 1] = 10 then
      Break;
  end;
  if (Have = 0) or (Buf[Have - 1] <> 10) then
    Exit;
  SetLength(Raw, Have - 1);
  if Length(Raw) > 0 then
    Move(Buf[0], Raw[0], Length(Raw));
  Line := TEncoding.UTF8.GetString(Raw);
  send(AClient, cAck, SizeOf(cAck), 0);
  Cb := FOnPath;
  Run :=
    procedure
    begin
      Cb(Line);
    end;
  TThread.Queue(nil, Run);
end;

procedure TListener.Execute;
var
  Client: Integer;
  Peer: sockaddr;
  PeerLen: socklen_t;
begin
  while not Terminated do
  begin
    if not WaitReadable(FSocket, cPollMs) then
      Continue;
    PeerLen := SizeOf(Peer);
    Client := accept(FSocket, Peer, PeerLen);
    if Client < 0 then
      Continue;
    try
      Serve(Client);
    finally
      __close(Client);
    end;
  end;
end;

function InstanceStartListening(const AName: string;
  const AOnPath: TProc<string>): Boolean;
var
  Path: string;
  Fd: Integer;
  Addr: sockaddr_un;
  Probe: Integer;
begin
  Result := False;
  if GListener <> nil then
    Exit(True);
  Path := InstanceSocketPath(AName);
  if not MakeAddress(Path, Addr) then
    Exit;
  // A socket file that still accepts connections belongs to a live instance.
  Probe := ConnectTo(Path);
  if Probe >= 0 then
  begin
    __close(Probe);
    Exit;
  end;
  unlink(MarshaledAString(UTF8String(Path)));
  Fd := socket(AF_UNIX, SOCK_STREAM, 0);
  if Fd < 0 then
    Exit;
  if (bind(Fd, psockaddr(@Addr)^, SizeOf(Addr)) <> 0) or (listen(Fd, 4) <> 0) then
  begin
    __close(Fd);
    Exit;
  end;
  chmod(MarshaledAString(UTF8String(Path)), S_IRUSR or S_IWUSR);
  GListener := TListener.Create(Fd, Path, AOnPath);
  Result := True;
end;

procedure InstanceStopListening;
var
  L: TListener;
begin
  L := GListener;
  if L = nil then
    Exit;
  GListener := nil;
  L.Terminate;
  L.WaitFor;
  __close(L.FSocket);
  unlink(MarshaledAString(UTF8String(L.FPath)));
  L.Free;
end;

end.
