unit uConPty;

{ Process bridge for Panel Console.
  Stage 13: one-shot cmd /c via redirected pipes.
  Stage 16: persistent cmd.exe session (StartShell + WriteInput).
  Stage 22 prep: real Windows ConPTY (CreatePseudoConsole) backend.

  CROSS-PLATFORM (Этап 23, roadmap §7): this unit is the Windows-only PTY
  backend (ConPTY via uConPtyApi.pas). IPtySession below is the intended
  swap seam for a future POSIX backend (forkpty/termios) -- but callers
  (TBaseConsoleWindow.FPty in uBaseConsoleWindow.pas) reference the concrete
  TConPtySession class directly, not IPtySession, so the seam isn't wired
  yet. Making FPty: IPtySession there is the first step of a POSIX port. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows,
  uShellProfiles, uConPtyApi;

type
  TConPtyOutputEvent = reference to procedure(const AText: string);
  TConPtyExitEvent = reference to procedure(AExitCode: DWORD);

  /// <summary>Long-lived panel / workspace shell session (SDS §5.4).
  /// Concrete Stage 16 impl: TConPtySession (pipes). ConPTY — Stage 17.</summary>
  IPtySession = interface
    ['{A7C2E901-4B1D-4F0A-9C3E-2D8F6B1A0E55}']
    function StartShell(const AProfile, ACwd: string; ACols, ARows: Word): Boolean;
    procedure WriteInput(const AText: string);
    procedure Resize(ACols, ARows: Word);
    procedure Terminate;
    function IsRunning: Boolean;
  end;

type
  TConPtySession = class;

  /// <summary>Lifetime link between a session and its exit-watcher threads.
  /// A watcher sleeps in WaitForSingleObject on the child process and can
  /// wake after the session was freed (Destroy -> Terminate kills the child,
  /// which is exactly what wakes it). It holds this ref-counted link instead
  /// of the session, and Destroy detaches the session under the link's lock
  /// first, so a late watcher never touches freed session state.</summary>
  IConPtySessionLife = interface
    ['{5B0E7D2C-3A41-4E8F-9D17-6C2A8F4B1E03}']
    procedure Detach;
    procedure NotifyProcessExit(AHpc: HPCON; AWatchEpoch: Integer);
  end;

  TPtyReaderThread = class(TThread)
  private
    FSession: TConPtySession;
  protected
    procedure Execute; override;
  public
    constructor Create(ASession: TConPtySession);
  end;

  TConPtySession = class
  private
    FRunning: Boolean;
    FPersistent: Boolean;
    FLastError: string;
    FPipeOutRead: THandle;
    FStdInWrite: THandle;
    FProcess: THandle;
    FThread: THandle;
    FHPC: HPCON;
    FReader: TThread;
    FLife: IConPtySessionLife;
    FIoLock: TCriticalSection;
    FPendingLock: TCriticalSection;
    FPendingText: string;
    FFlushQueued: Boolean;
    FEpoch: Integer;
    FProfileId: string;       // drives per-profile output/input encoding (cmd=OEM, ps/wsl=UTF-8)
    FDecodeTail: TBytes;      // pending UTF-8 multibyte tail spanning ReadFile boundaries
    FOnOutput: TConPtyOutputEvent;
    FOnExit: TConPtyExitEvent;
    FAlive: Boolean;
    procedure CleanupHandles;
    procedure ReaderLoop;
    function DecodePtyChunk(const ABuf: TBytes; ACount: Integer): string;
    procedure BumpEpoch;
    procedure QueuePendingLocked;
    procedure FlushPendingToUi(AEpoch: Integer);
    procedure QueueExit(ACode: DWORD; AEpoch: Integer);
    function LaunchProcess(const ACmdLine, AWorkingDir: string;
      AKeepStdIn: Boolean; ACols, ARows: Word): Boolean;
    /// <summary>Natural process exit (the shell just runs `exit`) leaves the
    /// ConPTY pseudoconsole -- and so the output pipe's write end -- open, so
    /// the reader thread's blocking ReadFile never observes EOF/broken-pipe
    /// on its own (unlike Terminate, which forces that via TerminateProcess +
    /// ClosePseudoConsole). This watcher waits on its own duplicate of the
    /// process handle and closes the pseudoconsole once the process is
    /// actually gone, unblocking ReadFile so ReaderLoop's normal exit path
    /// (and QueueExit/OnExit) fires.</summary>
    procedure StartExitWatcher(AProcess: THandle; AHpc: HPCON; AWatchEpoch: Integer);
    /// <summary>Watcher side of a natural exit, called via FLife with the
    /// session guaranteed alive: claims the pseudoconsole (0 if a newer
    /// generation or Terminate owns it). The caller closes it.</summary>
    function ClaimWatchedHpc(AHpc: HPCON; AWatchEpoch: Integer): HPCON;
    procedure BeginSession(AOnOutput: TConPtyOutputEvent;
      AOnExit: TConPtyExitEvent; APersistent: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>One-shot: cmd /c &lt;command&gt; (fallback when shell unavailable).</summary>
    function Start(const ACommand, AWorkingDir: string; ACols, ARows: Word;
      AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
    /// <summary>Persistent cmd.exe /d /q; keep stdin open for WriteInput.</summary>
    function StartShell(const AProfile, ACwd: string; ACols, ARows: Word): Boolean; overload;
    function StartShell(const ACwd: string; ACols, ARows: Word;
      AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean; overload;
    procedure WriteInput(const AText: string);
    procedure Resize(ACols, ARows: Word);
    procedure Terminate;
    function IsRunning: Boolean;
    property LastError: string read FLastError;
    property Persistent: Boolean read FPersistent;
    property ProfileId: string read FProfileId write FProfileId;
    property OnOutput: TConPtyOutputEvent read FOnOutput write FOnOutput;
    property OnExit: TConPtyExitEvent read FOnExit write FOnExit;
    /// <summary>Decode one PTY output chunk (for unit tests of split UTF-8/OEM).</summary>
    function DecodeOutputChunk(const ABuf: TBytes): string;
  end;

function ConPtyAvailable: Boolean;
function BuildCmdLineForShell(const ACommand: string): string;
function BuildPersistentShellCmdLine(const AProfile: string = ''): string;
function QuoteCmdPath(const APath: string): string;
/// <summary>True for "wsl", "wsl.exe", or either with a trailing space/colon
/// (a WSL invocation to route through wsl.exe rather than cmd.exe).</summary>
function IsWslCommandString(const ALowerCmd: string): Boolean;

implementation

var
  GOemEncoding: TEncoding;

function ConPtyAvailable: Boolean;
begin
  // Pipe capture works on all supported Windows hosts.
  Result := True;
end;

function IsWslCommandString(const ALowerCmd: string): Boolean;
begin
  Result := (ALowerCmd = 'wsl') or (ALowerCmd = 'wsl.exe') or
    ALowerCmd.StartsWith('wsl ') or ALowerCmd.StartsWith('wsl.exe ') or
    ALowerCmd.StartsWith('wsl:');
end;

function BuildCmdLineForShell(const ACommand: string): string;
var
  Cmd, WslCmd, LowerCmd: string;
begin
  Cmd := Trim(ACommand);
  LowerCmd := LowerCase(Cmd);

  if IsWslCommandString(LowerCmd) then
  begin
    if BuildWslCommandLine(Cmd, '', WslCmd) then
      Exit(WslCmd);
  end;

  // cmd /s /c: outer quotes are stripped; inner quotes must be doubled so
  // paths/args like "C:\Program Files\app.exe" survive intact.
  Result := 'cmd.exe /d /s /c "' +
    StringReplace(Cmd, '"', '""', [rfReplaceAll]) + '"';
end;

function BuildPersistentShellCmdLine(const AProfile: string): string;
var
  Cmd, Cwd: string;
begin
  if ResolveShellCmdLine(AProfile, '', Cmd, Cwd) then
    Result := Cmd
  else
    // Fallback keeps panel console usable even if profile probe fails.
    Result := 'cmd.exe /d /q /k';
end;

function QuoteCmdPath(const APath: string): string;
begin
  Result := QuoteCmdExePath(APath);
end;

function LooksLikeUtf16Le(const Buf: TBytes; ACount: Integer): Boolean;
var
  I, NulOdd: Integer;
begin
  Result := False;
  if (ACount < 4) or ((ACount and 1) <> 0) then
    Exit;
  NulOdd := 0;
  I := 1;
  while I < ACount do
  begin
    if Buf[I] = 0 then
      Inc(NulOdd);
    Inc(I, 2);
  end;
  Result := NulOdd >= (ACount div 4);
end;

function OemEncoding: TEncoding;
begin
  if GOemEncoding = nil then
    GOemEncoding := TEncoding.GetEncoding(866);
  Result := GOemEncoding;
end;

function ConsoleCodePage: Cardinal;
begin
  Result := 866;
end;

function StringToOemBytes(const AText: string): TBytes;
var
  Len: Integer;
  Cp: Cardinal;
begin
  if AText = '' then
    Exit(nil);
  Cp := 866;
  Len := WideCharToMultiByte(Cp, 0, PChar(AText), Length(AText), nil, 0, nil, nil);
  if Len <= 0 then
    Exit(nil);
  SetLength(Result, Len);
  WideCharToMultiByte(Cp, 0, PChar(AText), Length(AText), PAnsiChar(@Result[0]), Len, nil, nil);
end;

function OemBytesToString(const Buf: TBytes; ACount: Integer): string;
var
  Len: Integer;
  Cp: Cardinal;
begin
  if ACount <= 0 then
    Exit('');
  Cp := 866;
  Len := MultiByteToWideChar(Cp, 0, PAnsiChar(@Buf[0]), ACount, nil, 0);
  if Len <= 0 then
    Exit('');
  SetLength(Result, Len);
  MultiByteToWideChar(Cp, 0, PAnsiChar(@Buf[0]), ACount, PChar(Result), Len);
end;

function AcpBytesToString(const Buf: TBytes; ACount: Integer): string;
var
  Len: Integer;
  Cp: Cardinal;
begin
  if ACount <= 0 then
    Exit('');
  Cp := GetACP;
  if Cp = 0 then
    Exit(OemBytesToString(Buf, ACount));
  Len := MultiByteToWideChar(Cp, 0, PAnsiChar(@Buf[0]), ACount, nil, 0);
  if Len <= 0 then
    Exit('');
  SetLength(Result, Len);
  MultiByteToWideChar(Cp, 0, PAnsiChar(@Buf[0]), ACount, PChar(Result), Len);
end;

function CountCyrillicLetters(const S: string): Integer;
var
  I: Integer;
  Ch: Char;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if (Ch >= #$0400) and (Ch <= #$04FF) then
      Inc(Result);
  end;
end;

function CountBoxDrawingChars(const S: string): Integer;
var
  I: Integer;
  Ch: Char;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if (Ch >= #$2500) and (Ch <= #$257F) then
      Inc(Result);
  end;
end;

function PreferAcpOverOemDecode(const Oem, Ansi: string): Boolean;
begin
  // find.exe / xcopy.exe emit ACP (1251) on RU Windows while cmd uses OEM866.
  // OEM-decoding ACP bytes yields box-drawing (U+2500) mixed with stray Cyrillic.
  Result := (CountBoxDrawingChars(Oem) > 0) and
            (CountCyrillicLetters(Ansi) >= CountCyrillicLetters(Oem)) and
            (CountBoxDrawingChars(Ansi) = 0);
  if not Result then
    Result := (CountCyrillicLetters(Ansi) > CountCyrillicLetters(Oem)) and
              (CountBoxDrawingChars(Oem) > CountBoxDrawingChars(Ansi));
end;

// Consumes ANeedBytes UTF-8 continuation bytes (10xxxxxx) starting at I,
// advancing I past each one consumed. False (with I left mid-sequence) the
// moment one is missing (ran off the end of Buf) or malformed.
function ConsumeUtf8ContinuationBytes(const Buf: TBytes; ACount: Integer;
  var I: Integer; ANeedBytes: Integer): Boolean;
begin
  while ANeedBytes > 0 do
  begin
    if (I >= ACount) or ((Buf[I] and $C0) <> $80) then
      Exit(False);
    Inc(I);
    Dec(ANeedBytes);
  end;
  Result := True;
end;

function IsValidUtf8(const Buf: TBytes; ACount: Integer; out AHasMultibyte: Boolean): Boolean;
var
  I: Integer;
  B: Byte;
begin
  Result := True;
  AHasMultibyte := False;
  I := 0;
  while I < ACount do
  begin
    B := Buf[I];
    if (B and $80) = 0 then
    begin
      Inc(I);
    end
    else if (B and $E0) = $C0 then
    begin
      if (B and $FE) = $C0 then Exit(False);
      AHasMultibyte := True;
      Inc(I);
      if not ConsumeUtf8ContinuationBytes(Buf, ACount, I, 1) then Exit(False);
    end
    else if (B and $F0) = $E0 then
    begin
      AHasMultibyte := True;
      Inc(I);
      if not ConsumeUtf8ContinuationBytes(Buf, ACount, I, 2) then Exit(False);
    end
    else if (B and $F8) = $F0 then
    begin
      AHasMultibyte := True;
      Inc(I);
      if not ConsumeUtf8ContinuationBytes(Buf, ACount, I, 3) then Exit(False);
    end
    else
    begin
      Exit(False);
    end;
  end;
end;

function IsCp866CyrillicByte(B: Byte): Boolean;
begin
  Result := ((B >= $80) and (B <= $AF)) or ((B >= $E0) and (B <= $F1)) or (B = $FF);
end;

function IsCp866(const Buf: TBytes; ACount: Integer): Boolean;
var
  I, Score: Integer;
begin
  Score := 0;
  for I := 0 to ACount - 1 do
    if IsCp866CyrillicByte(Buf[I]) then
      Inc(Score);
  Result := Score > 0;
end;

function LooksLikeGoodOemCyrillic(const Oem: string): Boolean;
begin
  // When OEM decode already looks like good Cyrillic, do not override with UTF-8.
  Result := (CountCyrillicLetters(Oem) > 0) and (CountBoxDrawingChars(Oem) = 0);
end;

function DecodeCmdOutputChunk(const ABuf: TBytes; ACount: Integer): string;
begin
  Result := OemBytesToString(ABuf, ACount);
end;

// Length of an incomplete UTF-8 multibyte sequence at the end of [0..ACount).
// Returns 0 when the tail is a complete sequence (or pure ASCII).
function Utf8TrailingBytes(const Buf: TBytes; ACount: Integer): Integer;
var
  I, Need, Seen: Integer;
  B: Byte;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  // Walk the last up-to-3 bytes and find a leading byte whose continuation
  // run is not satisfied before the buffer ends.
  I := ACount - 1;
  Need := 0;
  while (I >= 0) and (I >= ACount - 3) do
  begin
    B := Buf[I];
    if (B and $80) = 0 then
      Break;                       // ASCII lead: sequence complete
    if (B and $C0) = $80 then
    begin
      Inc(Need);                   // continuation byte going backwards
      Dec(I);
      Continue;
    end;
    // Leading byte: 2-byte => 1 cont, 3-byte => 2 cont, 4-byte => 3 cont.
    if (B and $E0) = $C0 then
      Seen := 1
    else if (B and $F0) = $E0 then
      Seen := 2
    else if (B and $F8) = $F0 then
      Seen := 3
    else
      Break;                       // stray continuation with no lead in range
    if Need < Seen then
      Result := Need + 1           // leading byte itself + missing continuations
    else
      Result := 0;                 // complete
    Exit;
  end;
end;

function FormatLastError: string;
var
  Code: DWORD;
begin
  Code := GetLastError;
  Result := Format('[%d] %s', [Code, SysErrorMessage(Code)]);
end;

function TConPtySession.DecodePtyChunk(const ABuf: TBytes; ACount: Integer): string;
var
  Combined: TBytes;
  TailLen, CombinedCount: Integer;
  IsUtf8Profile: Boolean;
begin
  Result := '';
  if ACount <= 0 then
    Exit;

  // UTF-16 LE is only expected from exotic tools; keep the fast detection first.
  if (Length(FDecodeTail) = 0) and LooksLikeUtf16Le(ABuf, ACount) then
    Exit(TEncoding.Unicode.GetString(ABuf, 0, ACount));

  IsUtf8Profile := ProfileOutputEncoding(FProfileId);

  if IsUtf8Profile then
  begin
    // Deterministic UTF-8: never fall back to CP866, because CP866 Cyrillic
    // (e.g. 0xD0 0xB1) is spuriously valid UTF-8 and would corrupt cmd-style
    // bytes — but UTF-8 profiles never emit CP866, so the heuristic is safe.
    TailLen := Length(FDecodeTail);
    if TailLen > 0 then
    begin
      SetLength(Combined, TailLen + ACount);
      if TailLen > 0 then
        Move(FDecodeTail[0], Combined[0], TailLen);
      Move(ABuf[0], Combined[TailLen], ACount);
      FDecodeTail := nil;
    end
    else
    begin
      Combined := ABuf;
      SetLength(Combined, ACount);
    end;
    CombinedCount := TailLen + ACount;

    // Split off an incomplete multibyte tail to rejoin on the next chunk.
    TailLen := Utf8TrailingBytes(Combined, CombinedCount);
    if TailLen > 0 then
    begin
      SetLength(FDecodeTail, TailLen);
      Move(Combined[CombinedCount - TailLen], FDecodeTail[0], TailLen);
      Dec(CombinedCount, TailLen);
    end;
    if CombinedCount <= 0 then
      Exit;
    // Replace any invalid bytes inside the consumed range with U+FFFD via TEncoding.
    Exit(TEncoding.UTF8.GetString(Combined, 0, CombinedCount));
  end;

  // OEM / cmd profile: cmd.exe banner is OEM866; legacy tools (find, xcopy) often
  // emit ACP/1251 on Russian Windows — see DecodeCmdOutputChunk.
  Result := DecodeCmdOutputChunk(ABuf, ACount);
end;

constructor TPtyReaderThread.Create(ASession: TConPtySession);
begin
  inherited Create(True);
  FSession := ASession;
  FreeOnTerminate := False;
end;

procedure TPtyReaderThread.Execute;
begin
  if Assigned(FSession) then
    FSession.ReaderLoop;
end;

type
  TConPtySessionLife = class(TInterfacedObject, IConPtySessionLife)
  private
    FLock: TCriticalSection;
    FSession: TConPtySession;
  public
    constructor Create(ASession: TConPtySession);
    destructor Destroy; override;
    procedure Detach;
    procedure NotifyProcessExit(AHpc: HPCON; AWatchEpoch: Integer);
  end;

constructor TConPtySessionLife.Create(ASession: TConPtySession);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSession := ASession;
end;

destructor TConPtySessionLife.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TConPtySessionLife.Detach;
begin
  // Waits out a watcher that is inside NotifyProcessExit right now.
  FLock.Enter;
  try
    FSession := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TConPtySessionLife.NotifyProcessExit(AHpc: HPCON; AWatchEpoch: Integer);
var
  Hpc: HPCON;
begin
  Hpc := 0;
  FLock.Enter;
  try
    if Assigned(FSession) then
      Hpc := FSession.ClaimWatchedHpc(AHpc, AWatchEpoch);
  finally
    FLock.Leave;
  end;
  // Outside the lock: ClosePseudoConsole can block for seconds, and
  // Destroy's Detach must not wait on it.
  if Hpc <> 0 then
    ClosePseudoConsole(Hpc);
end;

constructor TConPtySession.Create;
begin
  inherited Create;
  FLife := TConPtySessionLife.Create(Self);
  FIoLock := TCriticalSection.Create;
  FPendingLock := TCriticalSection.Create;
  FAlive := True;
  FPipeOutRead := INVALID_HANDLE_VALUE;
  FStdInWrite := INVALID_HANDLE_VALUE;
  FProcess := 0;
  FThread := 0;
  FHPC := 0;
  FFlushQueued := False;
  FEpoch := 0;
  FPersistent := False;
end;

destructor TConPtySession.Destroy;
begin
  // Before anything is torn down: from here on a waking exit watcher finds
  // no session to touch (see IConPtySessionLife).
  FLife.Detach;
  FAlive := False;
  Terminate;
  FPendingLock.Free;
  FIoLock.Free;
  inherited Destroy;
end;

procedure TConPtySession.BumpEpoch;
begin
  TInterlocked.Increment(FEpoch);
end;

function WaitForThreadExit(AThread: TThread; ATimeoutMs: Cardinal): TWaitResult;
var
  Deadline: UInt64;
begin
  if AThread = nil then
    Exit(wrSignaled);
  Deadline := GetTickCount64 + UInt64(ATimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    if AThread.Finished then
      Exit(wrSignaled);
    Sleep(10);
  end;
  if AThread.Finished then
    Result := wrSignaled
  else
    Result := wrTimeout;
end;

procedure TConPtySession.CleanupHandles;
var
  ReaderThread: TThread;
begin
  // Invoked from LaunchProcess finally on the error path. If the reader thread
  // was already started before the failure, detach and join it first so it does
  // not outlive this session (leak + reads from closed handles).
  ReaderThread := FReader;
  FReader := nil;
  if Assigned(ReaderThread) then
  begin
    if WaitForThreadExit(ReaderThread, 2000) = wrSignaled then
      FreeAndNil(ReaderThread)
    else
      ReaderThread.FreeOnTerminate := True;   // orphan: see Terminate for rationale
  end;

  if FProcess <> 0 then
    TerminateProcess(FProcess, 1);

  if FHPC <> 0 then
  begin
    ClosePseudoConsole(FHPC);
    FHPC := 0;
  end;

  FIoLock.Enter;
  try
    if FPipeOutRead <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(FPipeOutRead);
      FPipeOutRead := INVALID_HANDLE_VALUE;
    end;
    if FStdInWrite <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(FStdInWrite);
      FStdInWrite := INVALID_HANDLE_VALUE;
    end;
  finally
    FIoLock.Leave;
  end;
  if FThread <> 0 then
  begin
    CloseHandle(FThread);
    FThread := 0;
  end;
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
    FProcess := 0;
  end;
  FRunning := False;
  FPersistent := False;
end;

procedure TConPtySession.Resize(ACols, ARows: Word);
var
  Size: TCoord;
begin
  if (ACols = 0) or (ARows = 0) or (FHPC = 0) then
    Exit;
  Size.X := SmallInt(ACols);
  Size.Y := SmallInt(ARows);
  ResizePseudoConsole(FHPC, Size);
end;

function TConPtySession.IsRunning: Boolean;
var
  Code: DWORD;
begin
  Result := False;
  if not FRunning then
    Exit;
  if FProcess = 0 then
    Exit(FRunning);
  if GetExitCodeProcess(FProcess, Code) then
    Result := Code = STILL_ACTIVE
  else
    Result := FRunning;
end;

procedure TConPtySession.QueuePendingLocked;
var
  Epoch: Integer;
begin
  // Caller holds FPendingLock. At most one UI flush is queued.
  if FFlushQueued or (FPendingText = '') then
    Exit;
  FFlushQueued := True;
  Epoch := FEpoch;
  TThread.Queue(nil,
    procedure
    begin
      FlushPendingToUi(Epoch);
    end);
end;

procedure TConPtySession.FlushPendingToUi(AEpoch: Integer);
var
  Chunk: string;
  OnOut: TConPtyOutputEvent;
begin
  // Drop callbacks from a previous Start/Terminate generation (Queue(nil) is
  // not cleared by RemoveQueuedEvents on the reader thread).
  Chunk := '';
  OnOut := nil;
  FPendingLock.Enter;
  try
    if AEpoch <> FEpoch then
    begin
      FFlushQueued := False;
      Exit;
    end;
    Chunk := FPendingText;
    FPendingText := '';
    FFlushQueued := False;
    OnOut := FOnOutput;
  finally
    FPendingLock.Leave;
  end;

  if AEpoch <> FEpoch then
    Exit;

  if (Chunk <> '') and Assigned(OnOut) then
    OnOut(Chunk);

  if AEpoch <> FEpoch then
    Exit;

  FPendingLock.Enter;
  try
    if AEpoch = FEpoch then
      QueuePendingLocked;
  finally
    FPendingLock.Leave;
  end;
end;

procedure TConPtySession.QueueExit(ACode: DWORD; AEpoch: Integer);
var
  OnExit: TConPtyExitEvent;
  Code: DWORD;
  Epoch: Integer;
begin
  OnExit := FOnExit;
  Code := ACode;
  Epoch := AEpoch;
  TThread.Queue(nil,
    procedure
    begin
      if Epoch <> FEpoch then
        Exit;
      if Assigned(OnExit) then
        OnExit(Code);
    end);
end;

function TConPtySession.DecodeOutputChunk(const ABuf: TBytes): string;
begin
  Result := DecodePtyChunk(ABuf, Length(ABuf));
end;

procedure ReleasePseudoConsole(AHpc: HPCON);
var
  Hpc: HPCON;
  Thread: TThread;
begin
  if AHpc = 0 then
    Exit;
  // Captured by the anonymous method (hoisted to the heap). ClosePseudoConsole
  // blocks the caller for about 5 seconds while conhost tears the session
  // down — long enough for Windows to ghost the window and leave the taskbar
  // button up after F10. The UI thread must not wait for it.
  Hpc := AHpc;
  Thread := TThread.CreateAnonymousThread(
    procedure
    begin
      ClosePseudoConsole(Hpc);
    end);
  Thread.FreeOnTerminate := True;
  Thread.Start;
end;

procedure TConPtySession.Terminate;
const
  cReaderJoinTimeoutMs = 300;   // CancelIoEx should already have unblocked the read
var
  OutRead, InWrite: THandle;
  Proc, Thr: THandle;
  Hpc: HPCON;
  ReaderThread: TThread;
  ReaderDone: Boolean;
begin
  FAlive := False;
  BumpEpoch;
  FOnOutput := nil;
  FOnExit := nil;

  ReaderThread := FReader;
  FReader := nil;

  FPendingLock.Enter;
  try
    FPendingText := '';
    FFlushQueued := False;
  finally
    FPendingLock.Leave;
  end;

  // 1. Close stdin first so the child sees EOF; for a non-respawning shell
  //    this is the graceful path that lets bash/cmd write trap/history output.
  FIoLock.Enter;
  try
    InWrite := FStdInWrite;
    FStdInWrite := INVALID_HANDLE_VALUE;
    OutRead := FPipeOutRead;
    Proc := FProcess;
    Thr := FThread;
  finally
    FIoLock.Leave;
  end;
  if InWrite <> INVALID_HANDLE_VALUE then
  begin
    CancelIoEx(InWrite, nil);
    CloseHandle(InWrite);
  end;

  // 2. Kill the process. Closing stdin alone may not unblock a long-running
  //    child. Do not call ClosePseudoConsole here: with a ReadFile still
  //    pending it blocks this thread for about 5 seconds.
  if Proc <> 0 then
    TerminateProcess(Proc, 1);

  // 3. Unblock the reader's ReadFile, then join it, before anyone closes the
  //    read handle. CancelIoEx is what releases the pending read; the
  //    pseudoconsole is closed afterwards, off this thread.
  if OutRead <> INVALID_HANDLE_VALUE then
    CancelIoEx(OutRead, nil);

  ReaderDone := not Assigned(ReaderThread);
  if Assigned(ReaderThread) then
  begin
    if WaitForThreadExit(ReaderThread, cReaderJoinTimeoutMs) = wrSignaled then
    begin
      FreeAndNil(ReaderThread);
      ReaderDone := True;
    end
    else
    begin
      // Reader did not exit in time (process refused TerminateProcess, driver
      // stuck). Rather than block the UI forever in TThread.Destroy.WaitFor,
      // orphan the thread object: it will be released by the OS when the
      // process finally exits. Leaking one thread is strictly better than a
      // deadlocked UI, and this path should be extremely rare.
      // Leave OutRead open: closing it under a pending ReadFile is undefined.
      ReaderThread.FreeOnTerminate := True;
    end;
  end;

  if ReaderDone and (OutRead <> INVALID_HANDLE_VALUE) then
    CloseHandle(OutRead);

  // 4. Drop our HPCON so the exit watcher (epoch already bumped) cannot close
  //    it too, then release it on a background thread.
  FIoLock.Enter;
  try
    Hpc := FHPC;
    FHPC := 0;
  finally
    FIoLock.Leave;
  end;
  ReleasePseudoConsole(Hpc);

  if Proc <> 0 then
    CloseHandle(Proc);
  if Thr <> 0 then
    CloseHandle(Thr);

  FIoLock.Enter;
  try
    if FPipeOutRead = OutRead then
      FPipeOutRead := INVALID_HANDLE_VALUE;
    if FProcess = Proc then
      FProcess := 0;
    if FThread = Thr then
      FThread := 0;
  finally
    FIoLock.Leave;
  end;

  FRunning := False;
  FPersistent := False;
end;

procedure TConPtySession.ReaderLoop;
const
  cMaxPendingChars = 256 * 1024;
var
  Buf: TBytes;
  N: DWORD;
  Text: string;
  ExitCode: DWORD;
  OutRead, Proc: THandle;
  Epoch: Integer;
  SignalExit: Boolean;
begin
  SetLength(Buf, 65536);
  Epoch := FEpoch;
  SignalExit := False;
  ExitCode := 1;
  try
    while FAlive and not TThread.CurrentThread.CheckTerminated do
    begin
      FIoLock.Enter;
      try
        OutRead := FPipeOutRead;
      finally
        FIoLock.Leave;
      end;
      if OutRead = INVALID_HANDLE_VALUE then
        Break;

      if not ReadFile(OutRead, Buf[0], Length(Buf), N, nil) then
      begin
        // ERROR_OPERATION_ABORTED: Terminate cancelled this read. Do not
        // retry — the handle may be closed as soon as we leave the loop.
        if (GetLastError = ERROR_BROKEN_PIPE) or
           (GetLastError = ERROR_OPERATION_ABORTED) then
          Break;
        FIoLock.Enter;
        try
          Proc := FProcess;
        finally
          FIoLock.Leave;
        end;
        if (Proc <> 0) and GetExitCodeProcess(Proc, ExitCode) and (ExitCode = STILL_ACTIVE) then
        begin
          Sleep(50);
          Continue;
        end;
        Break;
      end;
      if N = 0 then
        Break;

      Text := DecodePtyChunk(Buf, Integer(N));
      if Text = '' then
        Continue;

      FPendingLock.Enter;
      try
        if not FAlive then
          Exit;
        FPendingText := FPendingText + Text;
        QueuePendingLocked;
        // Never block the read loop waiting for UI flush: a full pipe stalls the
        // child on WriteFile and PowerShell/cmd exit once the buffer (~4 KB) fills.
        if Length(FPendingText) > cMaxPendingChars then
        begin
          QueuePendingLocked;
          Delete(FPendingText, 1, Length(FPendingText) - (cMaxPendingChars div 2));
        end;
      finally
        FPendingLock.Leave;
      end;
    end;
  finally
    if FAlive and (Epoch = FEpoch) then
    begin
      FPendingLock.Enter;
      try
        QueuePendingLocked;
      finally
        FPendingLock.Leave;
      end;

      FIoLock.Enter;
      try
        Proc := FProcess;
      finally
        FIoLock.Leave;
      end;

      if Proc <> 0 then
      begin
        WaitForSingleObject(Proc, 1000);
        if not GetExitCodeProcess(Proc, ExitCode) then
          ExitCode := 1
        else if ExitCode <> STILL_ACTIVE then
          SignalExit := True;
      end
      else
        SignalExit := True;

      if SignalExit then
      begin
        FRunning := False;
        FPersistent := False;
        QueueExit(ExitCode, Epoch);
      end;
    end
    else
    begin
      FRunning := False;
      FPersistent := False;
    end;
  end;
end;

procedure TConPtySession.BeginSession(AOnOutput: TConPtyOutputEvent;
  AOnExit: TConPtyExitEvent; APersistent: Boolean);
var
  OutEvt: TConPtyOutputEvent;
  ExitEvt: TConPtyExitEvent;
begin
  OutEvt := AOnOutput;
  ExitEvt := AOnExit;

  Terminate;

  FAlive := True;
  FOnOutput := OutEvt;
  FOnExit := ExitEvt;
  FPersistent := APersistent;

  // A pending UTF-8 multibyte tail from a previous session must not bleed into
  // the new process output; reset the decoder state explicitly.
  FDecodeTail := nil;

  FPendingLock.Enter;
  try
    FPendingText := '';
    FFlushQueued := False;
  finally
    FPendingLock.Leave;
  end;
end;

function TConPtySession.LaunchProcess(const ACmdLine, AWorkingDir: string;
  AKeepStdIn: Boolean; ACols, ARows: Word): Boolean;
var
  PtyInRead, PtyOutWrite: THandle;
  Sa: TSecurityAttributes;
  Si: TStartupInfoExW;
  Pi: TProcessInformation;
  CmdLine: UnicodeString;
  CwdStr: UnicodeString;
  Cwd: PWideChar;
  Ok: Boolean;
  Size: TCoord;
  AttrListSize: SIZE_T;
  AttrListInitialized: Boolean;
begin
  Result := False;
  FLastError := '';

  PtyInRead := INVALID_HANDLE_VALUE;
  PtyOutWrite := INVALID_HANDLE_VALUE;
  ZeroMemory(@Si, SizeOf(Si));
  ZeroMemory(@Pi, SizeOf(Pi));
  Ok := False;

  // None of the four pipe ends need to be inherited by the child: ConPTY
  // connects the child via the proc-thread-attribute below, not via the
  // legacy STARTF_USESTDHANDLES inheritance path.
  Sa.nLength := SizeOf(Sa);
  Sa.lpSecurityDescriptor := nil;
  Sa.bInheritHandle := False;

  // Pipe pair 1: we write keystrokes into FStdInWrite; ConPTY reads them from
  // PtyInRead (handed to CreatePseudoConsole as hInput, then closed on our side).
  if not CreatePipe(PtyInRead, FStdInWrite, @Sa, 0) then
  begin
    FLastError := 'CreatePipe#1: ' + FormatLastError;
    Exit;
  end;

  // Pipe pair 2: ConPTY writes child output into PtyOutWrite (hOutput); we
  // read it back from FPipeOutRead.
  if not CreatePipe(FPipeOutRead, PtyOutWrite, @Sa, 0) then
  begin
    FLastError := 'CreatePipe#2: ' + FormatLastError;
    CloseHandle(PtyInRead);
    CloseHandle(FStdInWrite);
    FStdInWrite := INVALID_HANDLE_VALUE;
    Exit;
  end;

  if ACols = 0 then Size.X := 80 else Size.X := SmallInt(ACols);
  if ARows = 0 then Size.Y := 25 else Size.Y := SmallInt(ARows);

  if CreatePseudoConsole(Size, PtyInRead, PtyOutWrite, 0, FHPC) <> S_OK then
  begin
    FLastError := 'CreatePseudoConsole failed: ' + FormatLastError;
    CloseHandle(PtyInRead);
    CloseHandle(PtyOutWrite);
    CloseHandle(FStdInWrite);
    FStdInWrite := INVALID_HANDLE_VALUE;
    CloseHandle(FPipeOutRead);
    FPipeOutRead := INVALID_HANDLE_VALUE;
    FHPC := 0;
    Exit;
  end;

  // ConPTY duplicated what it needs internally; our copies are no longer needed.
  CloseHandle(PtyInRead);
  CloseHandle(PtyOutWrite);

  AttrListInitialized := False;
  try
    AttrListSize := 0;
    InitializeProcThreadAttributeList(nil, 1, 0, AttrListSize);
    GetMem(Si.lpAttributeList, AttrListSize);
    if not InitializeProcThreadAttributeList(Si.lpAttributeList, 1, 0, AttrListSize) then
    begin
      FLastError := 'InitializeProcThreadAttributeList: ' + FormatLastError;
      Exit;
    end;
    AttrListInitialized := True;
    // lpValue is the HPCON handle value itself (cast to Pointer), not the
    // address of the FHPC variable -- matches Microsoft's ConPTY sample.
    // lpReturnSize must be a true NULL (uConPtyApi's PSIZE_T-based
    // declaration), not the RTL's non-nilable var NativeUInt -- kernel32
    // rejects this attribute with ERROR_INVALID_PARAMETER otherwise.
    if not UpdateProcThreadAttribute(Si.lpAttributeList, 0,
      PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, Pointer(FHPC), SizeOf(FHPC), nil,
      nil) then
    begin
      FLastError := 'UpdateProcThreadAttribute: ' + FormatLastError;
      Exit;
    end;

    // cb must be sizeof(STARTUPINFOEXW) -- the full extended struct including
    // lpAttributeList -- not sizeof(STARTUPINFOW); otherwise CreateProcessW
    // doesn't know to read the trailing attribute-list pointer and fails
    // with ERROR_INVALID_PARAMETER (confirmed empirically; matches
    // Microsoft's own ConPTY sample, which sets cb = sizeof(STARTUPINFOEX)).
    Si.StartupInfo.cb := SizeOf(Si);

    CmdLine := ACmdLine;
    UniqueString(CmdLine);
    if AWorkingDir <> '' then
    begin
      CwdStr := AWorkingDir;
      Cwd := PWideChar(CwdStr);
    end
    else
      Cwd := nil;

    if not CreateProcessW(nil, PWideChar(CmdLine), nil, nil, False,
      CREATE_UNICODE_ENVIRONMENT or EXTENDED_STARTUPINFO_PRESENT,
      nil, Cwd, Si.StartupInfo, Pi) then
    begin
      FLastError := 'CreateProcessW failed: ' + FormatLastError;
      Exit;
    end;

    FProcess := Pi.hProcess;
    FThread := Pi.hThread;
    FRunning := True;

    if not AKeepStdIn then
    begin
      // One-shot Start(): matches the old pipe path's immediate-EOF behavior;
      // WriteInput correctly reports "stdin closed" afterward.
      CloseHandle(FStdInWrite);
      FStdInWrite := INVALID_HANDLE_VALUE;
    end;

    FReader := TPtyReaderThread.Create(Self);
    FReader.Start;
    StartExitWatcher(Pi.hProcess, FHPC, FEpoch);
    Ok := True;
    Result := True;
  finally
    if Assigned(Si.lpAttributeList) then
    begin
      if AttrListInitialized then
        DeleteProcThreadAttributeList(Si.lpAttributeList);
      FreeMem(Si.lpAttributeList);
    end;
    if not Ok then
      CleanupHandles;
  end;
end;

procedure TConPtySession.StartExitWatcher(AProcess: THandle; AHpc: HPCON;
  AWatchEpoch: Integer);
var
  DupProcess: THandle;
  Life: IConPtySessionLife;
  Watcher: TThread;
begin
  DupProcess := 0;
  // Own duplicate: outlives whatever Terminate/CleanupHandles do to FProcess,
  // so this thread never waits on (or races to close) a handle another
  // thread might close out from under it.
  if not DuplicateHandle(GetCurrentProcess, AProcess, GetCurrentProcess,
    @DupProcess, 0, False, DUPLICATE_SAME_ACCESS) then
    Exit; // best-effort: natural-exit detection just won't fire early

  // Captures only the life link and its own handle -- never Self: the
  // session may be freed while this thread is still waiting.
  Life := FLife;
  Watcher := TThread.CreateAnonymousThread(
    procedure
    begin
      WaitForSingleObject(DupProcess, INFINITE);
      CloseHandle(DupProcess);
      Life.NotifyProcessExit(AHpc, AWatchEpoch);
    end);
  Watcher.FreeOnTerminate := True;
  Watcher.Start;
end;

function TConPtySession.ClaimWatchedHpc(AHpc: HPCON; AWatchEpoch: Integer): HPCON;
begin
  Result := 0;
  FIoLock.Enter;
  try
    // Epoch/handle-identity guard: a stale watcher from a prior
    // Start/Terminate generation must not touch the current session's
    // (possibly already-replaced) pseudoconsole.
    if (FEpoch = AWatchEpoch) and (FHPC = AHpc) and (FHPC <> 0) then
    begin
      Result := FHPC;
      FHPC := 0;
    end;
  finally
    FIoLock.Leave;
  end;
end;

function TConPtySession.Start(const ACommand, AWorkingDir: string; ACols, ARows: Word;
  AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
begin
  Result := False;
  if Trim(ACommand) = '' then
  begin
    FLastError := 'Empty command';
    Exit;
  end;
  BeginSession(AOnOutput, AOnExit, False);
  Result := LaunchProcess(BuildCmdLineForShell(ACommand), AWorkingDir, False, ACols, ARows);
end;

function TConPtySession.StartShell(const AProfile, ACwd: string;
  ACols, ARows: Word): Boolean;
var
  Cmd, Cwd: string;
begin
  BeginSession(FOnOutput, FOnExit, True);
  FProfileId := NormalizeShellProfileId(AProfile);
  if not ResolveShellCmdLine(AProfile, ACwd, Cmd, Cwd) then
  begin
    FLastError := 'Shell profile unavailable: ' + AProfile;
    FRunning := False;
    FPersistent := False;
    Exit(False);
  end;
  Result := LaunchProcess(Cmd, Cwd, True, ACols, ARows);
end;

function TConPtySession.StartShell(const ACwd: string; ACols, ARows: Word;
  AOnOutput: TConPtyOutputEvent; AOnExit: TConPtyExitEvent): Boolean;
begin
  BeginSession(AOnOutput, AOnExit, True);
  FProfileId := cShellProfileCmd;
  Result := LaunchProcess(BuildPersistentShellCmdLine('cmd'), ACwd, True, ACols, ARows);
end;

procedure TConPtySession.WriteInput(const AText: string);
var
  Bytes: TBytes;
  InWrite: THandle;
  Written: DWORD;
  Offset: Integer;
begin
  if AText = '' then
    Exit;
  if not IsRunning then
  begin
    FLastError := 'Shell is not running';
    Exit;
  end;

  // Input encoding mirrors output: cmd expects OEM/console CP, PowerShell/pwsh/WSL
  // expect UTF-8. Sending CP866 bytes to bash turns Cyrillic into mojibake.
  if ProfileOutputEncoding(FProfileId) then
    Bytes := TEncoding.UTF8.GetBytes(AText)
  else
    Bytes := StringToOemBytes(AText);
  if Length(Bytes) = 0 then
    Exit;

  FIoLock.Enter;
  try
    InWrite := FStdInWrite;
  finally
    FIoLock.Leave;
  end;
  if InWrite = INVALID_HANDLE_VALUE then
  begin
    FLastError := 'Shell stdin is closed';
    Exit;
  end;

  Offset := 0;
  while Offset < Length(Bytes) do
  begin
    if not WriteFile(InWrite, Bytes[Offset], DWORD(Length(Bytes) - Offset),
      Written, nil) then
    begin
      FLastError := FormatLastError;
      Exit;
    end;
    if Written = 0 then
    begin
      FLastError := 'WriteFile returned 0';
      Exit;
    end;
    Inc(Offset, Integer(Written));
  end;
  FLastError := '';
end;

initialization

finalization
  FreeAndNil(GOemEncoding);

end.
