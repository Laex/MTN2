unit uElevatedHelper;

{ The administrator helper: this program started again (--elevated-helper)
  with the UAC prompt, with no window. It serves one client, the program that
  started it, over two named pipes and runs file operations for it with the
  administrator token: copy, move, delete, create folder, write text. Each
  operation is the same code the panels use (TFileVirtualFileSystem), so
  progress and errors look the same in the job window.

  What keeps the helper from being a hole:
  - the pipes can be opened by the account of the program only (DACL), only one
    instance of each name exists, and the helper checks that the client process
    is the program that started it (same process id, same image file);
  - the first message must carry the secret the program passed on the command
    line;
  - only the operations in uElevatedProtocol run, on plain local paths; there
    is no way to start a program;
  - it ends when the connection drops, when the program exits, after a quiet
    period, or on a quit message. }

interface

const
  cElevatedHelperSwitch = '--elevated-helper';
  /// <summary>Seconds without any request after which the helper ends.</summary>
  cElevatedHelperIdleSeconds = 120;

/// <summary>Command line of the helper: pipe name, process id of the program,
/// the SID that may open the pipes, the secret.</summary>
function BuildHelperParams(const APipeName: string; AParentPid: Cardinal;
  const ASid, ANonce: string): string;
/// <summary>True when the process was started as the helper.</summary>
function ElevatedHelperRequested: Boolean;
/// <summary>Runs the helper to its end; the result is the process exit code.</summary>
function RunElevatedHelper: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, uVfsTypes, uTextEncoding, uFileVfs, uElevatedProtocol,
  uElevatedWin;

const
  cExitOk = 0;
  cExitBadArgs = 2;
  cExitRejected = 3;
  cConnectTimeoutMs = 120000;

type
  THelperServer = class
  private
    FReqPipe, FRepPipe: THandle;
    FNonce: string;
    FBackend: IVirtualFileSystem;
    FWriteLock: TCriticalSection;
    FTokens: TDictionary<Integer, IJobCancelToken>;
    FTokensLock: TCriticalSection;
    FActive: Integer;
    FLastActivity: UInt64;
    FStop: Boolean;
    procedure Send(const AReply: TElevatedReply);
    procedure SendDone(AId: Integer; const AError: TVfsError);
    procedure Execute(const ARequest: TElevatedRequest);
    function TakeToken(AId: Integer): IJobCancelToken;
    procedure DropToken(AId: Integer);
    procedure Finished(AId: Integer; const AError: TVfsError);
    procedure Touch;
  public
    constructor Create(AReqPipe, ARepPipe: THandle; const ANonce: string);
    destructor Destroy; override;
    /// <summary>Reads requests until the client leaves.</summary>
    procedure ReadLoop;
    property Stop: Boolean read FStop write FStop;
    property Active: Integer read FActive;
    property LastActivity: UInt64 read FLastActivity;
  end;

  TReaderThread = class(TThread)
  private
    FServer: THelperServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AServer: THelperServer);
  end;

function CancelSynchronousIo(AThread: THandle): BOOL; stdcall;
  external kernel32 name 'CancelSynchronousIo';

var
  GConnected: Boolean = False;

constructor THelperServer.Create(AReqPipe, ARepPipe: THandle; const ANonce: string);
begin
  inherited Create;
  FReqPipe := AReqPipe;
  FRepPipe := ARepPipe;
  FNonce := ANonce;
  FBackend := TFileVirtualFileSystem.Create;
  FWriteLock := TCriticalSection.Create;
  FTokensLock := TCriticalSection.Create;
  FTokens := TDictionary<Integer, IJobCancelToken>.Create;
  Touch;
end;

destructor THelperServer.Destroy;
begin
  FTokens.Free;
  FTokensLock.Free;
  FWriteLock.Free;
  inherited;
end;

procedure THelperServer.Touch;
begin
  FLastActivity := GetTickCount64;
end;

procedure THelperServer.Send(const AReply: TElevatedReply);
begin
  FWriteLock.Enter;
  try
    if not WriteFramedMessage(FRepPipe, EncodeReply(AReply)) then
      FStop := True;
  finally
    FWriteLock.Leave;
  end;
end;

procedure THelperServer.SendDone(AId: Integer; const AError: TVfsError);
var
  R: TElevatedReply;
begin
  R := Default(TElevatedReply);
  R.Id := AId;
  R.Kind := erkDone;
  R.Ok := AError.Code = vecOk;
  R.Code := AError.Code;
  R.Msg := AError.Message;
  R.URI := AError.URI;
  Send(R);
end;

function THelperServer.TakeToken(AId: Integer): IJobCancelToken;
begin
  Result := TJobCancelToken.Create;
  FTokensLock.Enter;
  try
    FTokens.AddOrSetValue(AId, Result);
  finally
    FTokensLock.Leave;
  end;
end;

procedure THelperServer.DropToken(AId: Integer);
begin
  FTokensLock.Enter;
  try
    FTokens.Remove(AId);
  finally
    FTokensLock.Leave;
  end;
end;

procedure THelperServer.Finished(AId: Integer; const AError: TVfsError);
begin
  DropToken(AId);
  SendDone(AId, AError);
  TInterlocked.Decrement(FActive);
  Touch;
end;

procedure THelperServer.Execute(const ARequest: TElevatedRequest);
var
  Id: Integer;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  Enc: TTextFileEncoding;
begin
  Id := ARequest.Id;
  Cancel := TakeToken(Id);
  TInterlocked.Increment(FActive);
  OnProgress :=
    procedure(const ADone, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    var
      R: TElevatedReply;
    begin
      R := Default(TElevatedReply);
      R.Id := Id;
      R.Kind := erkProgress;
      R.Done := ADone;
      R.Total := ATotal;
      R.Name := ACurrentName;
      R.ItemDone := AItemDone;
      R.ItemTotal := AItemTotal;
      R.Src := AItemSrcPath;
      R.Dst := AItemDstPath;
      Send(R);
    end;
  OnDone :=
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Finished(Id, AError);
    end;
  case ARequest.Op of
    eoCopy:
      FBackend.CopyAsync(ARequest.FromURI, ARequest.ToURI, Cancel, OnProgress,
        OnDone, ARequest.Overwrite, ARequest.Preserve);
    eoMove:
      FBackend.MoveAsync(ARequest.FromURI, ARequest.ToURI, Cancel, OnProgress,
        OnDone, ARequest.Overwrite, ARequest.Preserve);
    eoDelete:
      FBackend.DeleteAsync(ARequest.FromURI, ARequest.Mode, Cancel, OnProgress,
        OnDone);
    eoMkDir:
      FBackend.CreateDirectoryAsync(ARequest.FromURI, Cancel, OnDone);
    eoWriteText:
      begin
        if (ARequest.Encoding < Ord(Low(TTextFileEncoding))) or
           (ARequest.Encoding > Ord(High(TTextFileEncoding))) then
          Finished(Id, TVfsError.Make(vecNotSupported, 'Unknown encoding',
            ARequest.FromURI))
        else
        begin
          Enc := TTextFileEncoding(ARequest.Encoding);
          FBackend.WriteTextAsync(ARequest.FromURI, ARequest.Text, Enc, Cancel,
            OnDone);
        end;
      end;
  else
    Finished(Id, TVfsError.Make(vecNotSupported, 'Not supported', ''));
  end;
end;

procedure THelperServer.ReadLoop;
var
  Buffer, Payload: TBytes;
  Req: TElevatedRequest;
  Reason: string;
  Token: IJobCancelToken;
  Hello: TElevatedReply;
begin
  // The first message must be the hello with the secret.
  if not ReadFramedMessage(FReqPipe, Buffer, Payload) or
     not DecodeRequest(Payload, Req) or (Req.Op <> eoHello) or
     (Req.Nonce <> FNonce) then
  begin
    FStop := True;
    Exit;
  end;
  Hello := Default(TElevatedReply);
  Hello.Id := Req.Id;
  Hello.Kind := erkHello;
  Hello.Ok := True;
  Send(Hello);
  while not FStop do
  begin
    if not ReadFramedMessage(FReqPipe, Buffer, Payload) then
      Break;
    Touch;
    if not DecodeRequest(Payload, Req) then
      Break;
    case Req.Op of
      eoQuit:
        Break;
      eoCancel:
        begin
          FTokensLock.Enter;
          try
            if FTokens.TryGetValue(Req.Id, Token) then
              Token.Cancel;
          finally
            FTokensLock.Leave;
          end;
        end;
      eoHello:
        ;
    else
      if ValidateRequest(Req, Reason) then
        Execute(Req)
      else
        SendDone(Req.Id, TVfsError.Make(vecInvalidURI, Reason, Req.FromURI));
    end;
  end;
  FStop := True;
end;

constructor TReaderThread.Create(AServer: THelperServer);
begin
  inherited Create(False);
  FServer := AServer;
end;

procedure TReaderThread.Execute;
begin
  try
    FServer.ReadLoop;
  except
    FServer.Stop := True;
  end;
  FServer.Stop := True;
end;

function BuildHelperParams(const APipeName: string; AParentPid: Cardinal;
  const ASid, ANonce: string): string;
begin
  Result := Format('%s %s %d %s %s', [cElevatedHelperSwitch, APipeName, AParentPid,
    ASid, ANonce]);
end;

function ElevatedHelperRequested: Boolean;
begin
  Result := (ParamCount >= 1) and SameText(ParamStr(1), cElevatedHelperSwitch);
end;

function SamePath(const A, B: string): Boolean;
begin
  Result := (A <> '') and SameText(A, B);
end;

function RunElevatedHelper: Integer;
var
  PipeName, Sid, Nonce: string;
  ParentPid: Cardinal;
  Req, Rep: THandle;
  Parent: THandle;
  Server: THelperServer;
  Reader: TReaderThread;
  Started: UInt64;
  Waited: Integer;
begin
  if (ParamCount < 5) or not TryStrToUInt(ParamStr(3), ParentPid) then
    Exit(cExitBadArgs);
  PipeName := ParamStr(2);
  Sid := ParamStr(4);
  Nonce := ParamStr(5);
  if (PipeName = '') or (Nonce = '') then
    Exit(cExitBadArgs);
  Req := CreateSecuredPipe(ElevatedPipePath(PipeName, False), Sid, False);
  Rep := CreateSecuredPipe(ElevatedPipePath(PipeName, True), Sid, True);
  if (Req = INVALID_HANDLE_VALUE) or (Rep = INVALID_HANDLE_VALUE) then
    Exit(cExitRejected);
  Parent := OpenProcess(SYNCHRONIZE, False, ParentPid);
  if Parent = 0 then
    Exit(cExitRejected);
  // A client that never comes (the program was closed while the prompt was
  // up) must not leave the helper waiting for ever.
  Started := GetTickCount64;
  TThread.CreateAnonymousThread(
    procedure
    begin
      while not GConnected do
      begin
        if (GetTickCount64 - Started > cConnectTimeoutMs) or
           (WaitForSingleObject(Parent, 0) = WAIT_OBJECT_0) then
          ExitProcess(cExitRejected);
        Sleep(250);
      end;
    end).Start;
  if not (ConnectNamedPipe(Req, nil) or (GetLastError = ERROR_PIPE_CONNECTED)) or
     not (ConnectNamedPipe(Rep, nil) or (GetLastError = ERROR_PIPE_CONNECTED)) then
    Exit(cExitRejected);
  GConnected := True;
  // Only the program that started this process may talk to it.
  if (PipeClientPid(Req) <> ParentPid) or (PipeClientPid(Rep) <> ParentPid) or
     not SamePath(ProcessImagePath(ParentPid), ProcessImagePath(GetCurrentProcessId)) then
    Exit(cExitRejected);

  Server := THelperServer.Create(Req, Rep, Nonce);
  Reader := TReaderThread.Create(Server);
  try
    while not Server.Stop do
    begin
      CheckSynchronize(50);
      if WaitForSingleObject(Parent, 0) = WAIT_OBJECT_0 then
        Server.Stop := True;
      if (Server.Active = 0) and
         (GetTickCount64 - Server.LastActivity > cElevatedHelperIdleSeconds * 1000) then
        Server.Stop := True;
    end;
    CheckSynchronize(0);
    // A read that still waits for the client is cancelled; the thread then ends.
    Waited := 0;
    while not Reader.Finished and (Waited < 40) do
    begin
      CancelSynchronousIo(Reader.Handle);
      Sleep(50);
      Inc(Waited);
    end;
    if not Reader.Finished then
      ExitProcess(cExitOk);
  finally
    CloseHandle(Req);
    CloseHandle(Rep);
    Reader.Free;
    Server.Free;
    CloseHandle(Parent);
  end;
  Result := cExitOk;
end;

end.
