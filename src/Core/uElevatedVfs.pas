unit uElevatedVfs;

{ Local file operations run by the administrator helper (uElevatedHelper).
  The panels ask this provider for a copy, move, delete, new folder or text
  save the same way they ask the ordinary one, and get progress and errors
  back the same way; the work itself happens in the helper process.

  The helper is started on the first request: the UAC prompt appears then and
  nowhere else. It is kept for a while for the next request and ends on its
  own after a quiet period (or when the program ends). Reading operations
  (list, read, exists, free space) need no rights and go to the ordinary
  provider. The helper is reached only over pipes the program verified
  (uElevatedWin), and it runs only the operations of uElevatedProtocol. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, uVfsTypes, uTextEncoding, uElevatedProtocol;

type
  /// <summary>Starts the helper with AParams on its command line and returns
  /// the process handle (the caller closes it). The default asks Windows for
  /// administrator rights; a test starts an ordinary process instead.</summary>
  TElevatedLauncher = reference to function(const AParams: string;
    out AProcess: THandle; out AError: TVfsError): Boolean;

  TElevatedFileVfs = class(TInterfacedObject, IVirtualFileSystem)
  private
    type
      TPending = record
        OnProgress: TVfsProgressCallback;
        OnDone: TVfsBoolCallback;
        Cancel: IJobCancelToken;
        CancelSent: Boolean;
        URI: string;
      end;
  private
    FInner: IVirtualFileSystem;
    FConnectLock: TCriticalSection;
    FStateLock: TCriticalSection;
    FSendLock: TCriticalSection;
    FPending: TDictionary<Integer, TPending>;
    FReqPipe, FRepPipe: THandle;
    FConnected: Boolean;
    FActiveFlag: Boolean;
    FLastUse: UInt64;
    FNextId: Integer;
    FReader: TThread;
    FWatcher: TThread;
    FHelloEvent: TEvent;
    FOnActiveChanged: TProc<Boolean>;
    FLauncher: TElevatedLauncher;
    function EnsureConnected(out AError: TVfsError): Boolean;
    function Launch(out AError: TVfsError): Boolean;
    function ConnectPipes(const APipeName: string; AHelperProcess: THandle;
      out AError: TVfsError): Boolean;
    procedure Disconnect(ASendQuit: Boolean);
    procedure SetActive(AActive: Boolean);
    function SendRequest(const ARequest: TElevatedRequest): Boolean;
    procedure ReaderLoop;
    procedure WatchLoop;
    procedure HandleReply(const AReply: TElevatedReply);
    procedure FailAll(const AMessage: string);
    procedure Submit(AOp: TElevatedOp; const AFrom, ATo: string;
      AMode: TVfsDeleteMode; AOverwrite, APreserve: Boolean; const AText: string;
      AEncoding: Integer; const ACancel: IJobCancelToken;
      const AOnProgress: TVfsProgressCallback; const AOnDone: TVfsBoolCallback);
  public
    constructor Create(const AInner: IVirtualFileSystem);
    destructor Destroy; override;
    /// <summary>True while the helper is running and connected.</summary>
    function IsActive: Boolean;
    /// <summary>Ends the helper now.</summary>
    procedure Shutdown;
    /// <summary>Called on the UI thread when the helper starts or ends.</summary>
    property OnActiveChanged: TProc<Boolean> read FOnActiveChanged
      write FOnActiveChanged;
    property Launcher: TElevatedLauncher read FLauncher write FLauncher;

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

implementation

uses
  Winapi.ShellAPI, Winapi.ActiveX, uElevatedHelper, uElevatedWin;

const
  /// <summary>A helper quiet for this long is dropped before the next request
  /// and a fresh one is started. The helper ends on its own at
  /// cElevatedHelperIdleSeconds, and a request must not reach it as it ends.</summary>
  cReuseSeconds = 90;
  cConnectWaitMs = 20000;
  cHelloWaitMs = 10000;

type
  TReaderThread = class(TThread)
  private
    FOwner: TElevatedFileVfs;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TElevatedFileVfs);
  end;

  TWatchThread = class(TThread)
  private
    FOwner: TElevatedFileVfs;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TElevatedFileVfs);
  end;

constructor TReaderThread.Create(AOwner: TElevatedFileVfs);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TReaderThread.Execute;
begin
  FOwner.ReaderLoop;
end;

constructor TWatchThread.Create(AOwner: TElevatedFileVfs);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TWatchThread.Execute;
begin
  FOwner.WatchLoop;
end;

constructor TElevatedFileVfs.Create(const AInner: IVirtualFileSystem);
begin
  inherited Create;
  FInner := AInner;
  FConnectLock := TCriticalSection.Create;
  FStateLock := TCriticalSection.Create;
  FSendLock := TCriticalSection.Create;
  FPending := TDictionary<Integer, TPending>.Create;
  FHelloEvent := TEvent.Create(nil, True, False, '');
  FReqPipe := INVALID_HANDLE_VALUE;
  FRepPipe := INVALID_HANDLE_VALUE;
end;

destructor TElevatedFileVfs.Destroy;
begin
  Disconnect(True);
  FHelloEvent.Free;
  FPending.Free;
  FSendLock.Free;
  FStateLock.Free;
  FConnectLock.Free;
  inherited;
end;

function TElevatedFileVfs.IsActive: Boolean;
begin
  Result := FConnected;
end;

procedure TElevatedFileVfs.Shutdown;
begin
  // The program is ending: pending calls get no answer.
  FStateLock.Enter;
  try
    FPending.Clear;
  finally
    FStateLock.Leave;
  end;
  Disconnect(True);
end;

procedure TElevatedFileVfs.SetActive(AActive: Boolean);
var
  Notify: TProc<Boolean>;
begin
  FStateLock.Enter;
  try
    if FActiveFlag = AActive then
      Exit;
    FActiveFlag := AActive;
  finally
    FStateLock.Leave;
  end;
  Notify := FOnActiveChanged;
  if Assigned(Notify) then
    TThread.Queue(nil,
      procedure
      begin
        Notify(AActive);
      end);
end;

function TElevatedFileVfs.SendRequest(const ARequest: TElevatedRequest): Boolean;
begin
  FSendLock.Enter;
  try
    Result := (FReqPipe <> INVALID_HANDLE_VALUE) and
      WriteFramedMessage(FReqPipe, EncodeRequest(ARequest));
  finally
    FSendLock.Leave;
  end;
end;

function RunAsAdministrator(const AParams: string; out AProcess: THandle;
  out AError: TVfsError): Boolean;
var
  Info: TShellExecuteInfo;
  Inited: HRESULT;
  Code: DWORD;
begin
  AProcess := 0;
  ZeroMemory(@Info, SizeOf(Info));
  Info.cbSize := SizeOf(Info);
  Info.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_NOASYNC;
  Info.lpVerb := 'runas';
  Info.lpFile := PChar(ParamStr(0));
  Info.lpParameters := PChar(AParams);
  Info.lpDirectory := PChar(ExtractFileDir(ParamStr(0)));
  Info.nShow := SW_HIDE;
  Inited := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    Result := ShellExecuteEx(@Info);
    if not Result then
    begin
      Code := GetLastError;
      if Code = ERROR_CANCELLED then
        AError := TVfsError.Make(vecCancelled,
          'Administrator rights were not granted', '')
      else
        AError := TVfsError.Make(vecIOError, SysErrorMessage(Code), '');
    end;
  finally
    if Succeeded(Inited) then
      CoUninitialize;
  end;
  AProcess := Info.hProcess;
end;

function TElevatedFileVfs.Launch(out AError: TVfsError): Boolean;
var
  PipeName, Nonce, Params, Sid: string;
  Process: THandle;
  Hello: TElevatedRequest;
begin
  Result := False;
  Sid := CurrentUserSidText;
  if Sid = '' then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot read the account of the program', '');
    Exit;
  end;
  PipeName := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  Nonce := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  Params := BuildHelperParams(PipeName, GetCurrentProcessId, Sid, Nonce);
  if Assigned(FLauncher) then
  begin
    if not FLauncher(Params, Process, AError) then
      Exit;
  end
  else if not RunAsAdministrator(Params, Process, AError) then
    Exit;
  if Process = 0 then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot verify the helper process', '');
    Exit;
  end;
  try
    Result := ConnectPipes(PipeName, Process, AError);
    if Result then
    begin
      // The hello carries the secret; the reply tells that the helper accepted it.
      FHelloEvent.ResetEvent;
      FReader := TReaderThread.Create(Self);
      Hello := Default(TElevatedRequest);
      Hello.Op := eoHello;
      Hello.Nonce := Nonce;
      if not SendRequest(Hello) then
        Result := False
      else
        Result := FHelloEvent.WaitFor(cHelloWaitMs) = wrSignaled;
      if not Result then
      begin
        AError := TVfsError.Make(vecIOError, 'The administrator helper did not answer', '');
        Disconnect(False);
      end;
    end;
  finally
    CloseHandle(Process);
  end;
end;

function TElevatedFileVfs.ConnectPipes(const APipeName: string;
  AHelperProcess: THandle; out AError: TVfsError): Boolean;
var
  Started: UInt64;
  HelperPid: Cardinal;

  function OpenEnd(AReplies: Boolean): THandle;
  var
    Access: DWORD;
    Path: string;
  begin
    if AReplies then
      Access := GENERIC_READ
    else
      Access := GENERIC_WRITE;
    Path := ElevatedPipePath(APipeName, AReplies);
    while True do
    begin
      Result := CreateFile(PChar(Path), Access, 0, nil, OPEN_EXISTING, 0, 0);
      if Result <> INVALID_HANDLE_VALUE then
        Exit;
      if (GetTickCount64 - Started > cConnectWaitMs) or
         (WaitForSingleObject(AHelperProcess, 0) = WAIT_OBJECT_0) then
        Exit;
      if GetLastError = ERROR_PIPE_BUSY then
        WaitNamedPipe(PChar(Path), 200)
      else
        Sleep(100);
    end;
  end;

begin
  Result := False;
  Started := GetTickCount64;
  HelperPid := GetProcessId(AHelperProcess);
  FReqPipe := OpenEnd(False);
  if FReqPipe <> INVALID_HANDLE_VALUE then
    FRepPipe := OpenEnd(True);
  // The pipes must belong to the process the system just started: a name
  // taken by another program would be answered by that program.
  if (FReqPipe = INVALID_HANDLE_VALUE) or (FRepPipe = INVALID_HANDLE_VALUE) or
     (HelperPid = 0) or (PipeServerPid(FReqPipe) <> HelperPid) or
     (PipeServerPid(FRepPipe) <> HelperPid) then
  begin
    AError := TVfsError.Make(vecIOError, 'Cannot connect to the administrator helper', '');
    Disconnect(False);
    Exit;
  end;
  FConnected := True;
  Result := True;
end;

function TElevatedFileVfs.EnsureConnected(out AError: TVfsError): Boolean;
begin
  FConnectLock.Enter;
  try
    if FConnected and (GetTickCount64 - FLastUse > cReuseSeconds * 1000) and
       (FPending.Count = 0) then
      Disconnect(True);
    if not FConnected then
    begin
      // Threads and handles of a helper that has ended on its own.
      Disconnect(False);
      if not Launch(AError) then
        Exit(False);
      FWatcher := TWatchThread.Create(Self);
      SetActive(True);
    end;
    FLastUse := GetTickCount64;
    Result := True;
  finally
    FConnectLock.Leave;
  end;
end;

procedure TElevatedFileVfs.Disconnect(ASendQuit: Boolean);
var
  Reader, Watcher: TThread;
  Quit: TElevatedRequest;
begin
  FConnected := False;
  if ASendQuit and (FReqPipe <> INVALID_HANDLE_VALUE) then
  begin
    Quit := Default(TElevatedRequest);
    Quit.Op := eoQuit;
    SendRequest(Quit);
  end;
  FSendLock.Enter;
  try
    if FReqPipe <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(FReqPipe);
      FReqPipe := INVALID_HANDLE_VALUE;
    end;
  finally
    FSendLock.Leave;
  end;
  Reader := FReader;
  Watcher := FWatcher;
  FReader := nil;
  FWatcher := nil;
  if FRepPipe <> INVALID_HANDLE_VALUE then
    CancelIoEx(FRepPipe, nil);
  if Assigned(Reader) then
  begin
    Reader.WaitFor;
    Reader.Free;
  end;
  if FRepPipe <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FRepPipe);
    FRepPipe := INVALID_HANDLE_VALUE;
  end;
  if Assigned(Watcher) then
  begin
    Watcher.WaitFor;
    Watcher.Free;
  end;
  FailAll('The administrator helper stopped');
  SetActive(False);
end;

procedure TElevatedFileVfs.ReaderLoop;
var
  Buffer, Payload: TBytes;
  Reply: TElevatedReply;
  Pipe: THandle;
begin
  Pipe := FRepPipe;
  while ReadFramedMessage(Pipe, Buffer, Payload) do
  begin
    if not DecodeReply(Payload, Reply) then
      Break;
    HandleReply(Reply);
  end;
  FConnected := False;
  FHelloEvent.ResetEvent;
  FailAll('The administrator helper stopped');
  SetActive(False);
end;

procedure TElevatedFileVfs.HandleReply(const AReply: TElevatedReply);
var
  P: TPending;
  Found: Boolean;
  Err: TVfsError;
  OnDone: TVfsBoolCallback;
  OnProgress: TVfsProgressCallback;
  R: TElevatedReply;
begin
  if AReply.Kind = erkHello then
  begin
    FHelloEvent.SetEvent;
    Exit;
  end;
  FStateLock.Enter;
  try
    Found := FPending.TryGetValue(AReply.Id, P);
    if Found and (AReply.Kind = erkDone) then
      FPending.Remove(AReply.Id);
  finally
    FStateLock.Leave;
  end;
  if not Found then
    Exit;
  R := AReply;
  FLastUse := GetTickCount64;
  if R.Kind = erkProgress then
  begin
    OnProgress := P.OnProgress;
    if Assigned(OnProgress) then
      TThread.Queue(nil,
        procedure
        begin
          OnProgress(R.Done, R.Total, R.Name, R.ItemDone, R.ItemTotal, R.Src, R.Dst);
        end);
    Exit;
  end;
  if R.Ok then
    Err := TVfsError.Ok
  else
    Err := TVfsError.Make(R.Code, R.Msg, R.URI);
  OnDone := P.OnDone;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(OnDone) then
        OnDone(Err.Code = vecOk, Err);
    end);
end;

procedure QueueFailure(const ADone: TVfsBoolCallback; const AError: TVfsError);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(ADone) then
        ADone(False, AError);
    end);
end;

procedure TElevatedFileVfs.FailAll(const AMessage: string);
var
  Calls: TArray<TPending>;
  I: Integer;
begin
  FStateLock.Enter;
  try
    Calls := FPending.Values.ToArray;
    FPending.Clear;
  finally
    FStateLock.Leave;
  end;
  for I := 0 to High(Calls) do
    QueueFailure(Calls[I].OnDone, TVfsError.Make(vecIOError, AMessage, Calls[I].URI));
end;

procedure TElevatedFileVfs.WatchLoop;
var
  Ids: TArray<Integer>;
  Id: Integer;
  P: TPending;
  Req: TElevatedRequest;
begin
  while FConnected do
  begin
    Sleep(100);
    // A cancelled job tells the helper once, so the operation stops there too.
    FStateLock.Enter;
    try
      Ids := FPending.Keys.ToArray;
      for Id in Ids do
        if FPending.TryGetValue(Id, P) and not P.CancelSent and
           JobCancelRequested(P.Cancel) then
        begin
          P.CancelSent := True;
          FPending.AddOrSetValue(Id, P);
          Req := Default(TElevatedRequest);
          Req.Id := Id;
          Req.Op := eoCancel;
          SendRequest(Req);
        end;
    finally
      FStateLock.Leave;
    end;
  end;
end;

procedure TElevatedFileVfs.Submit(AOp: TElevatedOp; const AFrom, ATo: string;
  AMode: TVfsDeleteMode; AOverwrite, APreserve: Boolean; const AText: string;
  AEncoding: Integer; const ACancel: IJobCancelToken;
  const AOnProgress: TVfsProgressCallback; const AOnDone: TVfsBoolCallback);
var
  Self_: TElevatedFileVfs;
  Req: TElevatedRequest;
begin
  Req := Default(TElevatedRequest);
  Req.Op := AOp;
  Req.FromURI := AFrom;
  Req.ToURI := ATo;
  Req.Mode := AMode;
  Req.Overwrite := AOverwrite;
  Req.Preserve := APreserve;
  Req.Text := AText;
  Req.Encoding := AEncoding;
  Self_ := Self;
  // The UAC prompt blocks, so the connection is made off the UI thread.
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      P: TPending;
      Failed: TVfsBoolCallback;
    begin
      Failed := AOnDone;
      if not Self_.EnsureConnected(Err) then
      begin
        Err.URI := AFrom;
        TThread.Queue(nil,
          procedure
          begin
            if Assigned(Failed) then
              Failed(False, Err);
          end);
        Exit;
      end;
      P.OnProgress := AOnProgress;
      P.OnDone := AOnDone;
      P.Cancel := ACancel;
      P.CancelSent := False;
      P.URI := AFrom;
      Req.Id := TInterlocked.Increment(Self_.FNextId);
      Self_.FStateLock.Enter;
      try
        Self_.FPending.Add(Req.Id, P);
      finally
        Self_.FStateLock.Leave;
      end;
      if not Self_.SendRequest(Req) then
      begin
        Self_.FStateLock.Enter;
        try
          Self_.FPending.Remove(Req.Id);
        finally
          Self_.FStateLock.Leave;
        end;
        Err := TVfsError.Make(vecIOError, 'The administrator helper stopped', AFrom);
        TThread.Queue(nil,
          procedure
          begin
            if Assigned(Failed) then
              Failed(False, Err);
          end);
      end;
    end).Start;
end;

procedure TElevatedFileVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
  Submit(eoDelete, AURI, '', AMode, False, False, '', 0, ACancel, AOnProgress, AOnDone);
end;

procedure TElevatedFileVfs.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  Submit(eoMkDir, AURI, '', vdmPermanent, False, False, '', 0, ACancel, nil, AOnDone);
end;

procedure TElevatedFileVfs.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  Submit(eoCopy, AFromURI, AToURI, vdmPermanent, AOverwrite, APreserveTimestamps,
    '', 0, ACancel, AOnProgress, AOnDone);
end;

procedure TElevatedFileVfs.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  Submit(eoMove, AFromURI, AToURI, vdmPermanent, AOverwrite, APreserveTimestamps,
    '', 0, ACancel, AOnProgress, AOnDone);
end;

procedure TElevatedFileVfs.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  Submit(eoWriteText, AURI, '', vdmPermanent, False, False, AText, Ord(AEncoding),
    ACancel, nil, AOnDone);
end;

procedure TElevatedFileVfs.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
begin
  FInner.ListDirectoryAsync(AURI, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  FInner.ReadTextAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  FInner.ReadBytesAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
  FInner.ExistsAsync(AURI, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
begin
  FInner.GetFreeSpaceAsync(ARootURI, ACancel, AOnDone);
end;

end.
