unit uBridgeServer;

{ One external service process of mtn.bridge: started from an approved configuration, shaken
  hands with, asked for its tools, then called. A reader thread turns the lines of stdout
  into answers for the waiting calls; a watchdog fails calls that stay unanswered and
  ends the process when it keeps silent. When the process ends, every waiting call fails.
  The process is reached only through IChildProcess, so tests drive the server with a
  fake that needs no program. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  uPlatformChild, uBridgeConfig, uBridgeProtocol;

const
  cBridgeMaxPending = 16;
  cBridgeMaxTools = 200;
  cBridgeMaxToolPages = 20;
  cBridgeCallTimeoutMs = 120000;

type
  TBridgeChildFactory = reference to function(const AServer: TBridgeServerConfig;
    out AChild: IChildProcess): Boolean;

  /// <summary>The answer of a tool call; runs on the reader thread, or on the thread that
  /// stopped the server.</summary>
  TBridgeReplyEvent = reference to procedure(const AReply: TBridgeReply);
  TBridgeProgressEvent = reference to procedure(const AText: string);
  TBridgeLogEvent = reference to procedure(const ALine: string);

  TBridgeServer = class
  private
    type
      TPending = class
        OnRaw: TProc<string>;
        OnProgress: TBridgeProgressEvent;
        Deadline: UInt64;
        TimeoutMs: Cardinal;
      end;
      TReaderThread = class(TThread)
      private
        FOwner: TBridgeServer;
      protected
        procedure Execute; override;
      public
        constructor Create(AOwner: TBridgeServer);
      end;
      TErrThread = class(TThread)
      private
        FOwner: TBridgeServer;
      protected
        procedure Execute; override;
      public
        constructor Create(AOwner: TBridgeServer);
      end;
      TWatchThread = class(TThread)
      private
        FOwner: TBridgeServer;
        FStop: TEvent;
      protected
        procedure Execute; override;
      public
        constructor Create(AOwner: TBridgeServer);
        destructor Destroy; override;
        procedure Finish;
      end;
  private
    FConfig: TBridgeServerConfig;
    FFactory: TBridgeChildFactory;
    FChild: IChildProcess;
    FReader: TReaderThread;
    FErrReader: TErrThread;
    FWatch: TWatchThread;
    FLock: TCriticalSection;
    FWriteLock: TCriticalSection;
    FPending: TObjectDictionary<Integer, TPending>;
    FNextId: Integer;
    FRunning: Boolean;
    FTools: TArray<TBridgeTool>;
    FOnLog: TBridgeLogEvent;
    function NewId: Integer;
    function Send(const AJson: string): Boolean;
    function AddPending(AId: Integer; ATimeoutMs: Cardinal; AOnRaw: TProc<string>;
      AOnProgress: TBridgeProgressEvent): Boolean;
    function TakePending(AId: Integer): TPending;
    procedure FailPending(AId: Integer; ACode: Integer; const AText: string);
    procedure FailAll(const AText: string);
    procedure Dispatch(const ALine: string);
    procedure ReaderEnded;
    procedure CheckDeadlines;
    function RequestSync(ABuild: TFunc<Integer, string>; ATimeoutMs: Cardinal;
      out AMessageJson: string): Boolean;
    function Handshake(out AError: string): Boolean;
    function LoadTools(out AError: string): Boolean;
    procedure Log(const ALine: string);
  public
    constructor Create(const AConfig: TBridgeServerConfig; AFactory: TBridgeChildFactory);
    destructor Destroy; override;
    /// <summary>Starts the process, shakes hands and reads the tools. False with the reason
    /// in AError; the process is ended then.</summary>
    function Start(out AError: string): Boolean;
    /// <summary>Ends the process; every waiting call gets an error.</summary>
    procedure Stop;
    /// <summary>Sends a tool call; AOnReply runs once, with the answer or an error.
    /// False when the server is not running or has too many calls waiting.</summary>
    function Call(const ATool, AArgumentsJson: string; ATimeoutMs: Cardinal;
      AOnReply: TBridgeReplyEvent; AOnProgress: TBridgeProgressEvent; out ACallId: Integer): Boolean;
    /// <summary>Tells the server to stop the call; its reply, if any, is ignored.</summary>
    procedure Cancel(ACallId: Integer);
    property Config: TBridgeServerConfig read FConfig;
    property Running: Boolean read FRunning;
    property Tools: TArray<TBridgeTool> read FTools;
    property OnLog: TBridgeLogEvent read FOnLog write FOnLog;
  end;

/// <summary>The factory that starts the real program.</summary>
function RealBridgeChildFactory: TBridgeChildFactory;

implementation

uses
  uJsonRpc;

const
  cWatchSliceMs = 100;
  cStopWaitMs = 3000;

function RealBridgeChildFactory: TBridgeChildFactory;
begin
  Result := function(const AServer: TBridgeServerConfig; out AChild: IChildProcess): Boolean
    begin
      Result := PlatformStartChild(AServer.Command, AServer.Args, AServer.Dir, AServer.Env, AChild);
    end;
end;

{ TBridgeServer.TReaderThread }

constructor TBridgeServer.TReaderThread.Create(AOwner: TBridgeServer);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TBridgeServer.TReaderThread.Execute;
var
  Buf: TBytes;
  N: Integer;
  Split: TLineSplitter;
  Line: string;
begin
  SetLength(Buf, 8192);
  Split := TLineSplitter.Create;
  try
    repeat
      N := FOwner.FChild.ReadOut(Buf[0], Length(Buf));
      if N <= 0 then
        Break;
      for Line in Split.Feed(Buf, N) do
        FOwner.Dispatch(Line);
      if Split.TakeOverflow then
        FOwner.Log('a message of the service process was too long and was dropped');
    until False;
  finally
    Split.Free;
  end;
  FOwner.ReaderEnded;
end;

{ TBridgeServer.TErrThread }

constructor TBridgeServer.TErrThread.Create(AOwner: TBridgeServer);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TBridgeServer.TErrThread.Execute;
var
  Buf: TBytes;
  N: Integer;
  Split: TLineSplitter;
  Line: string;
begin
  SetLength(Buf, 4096);
  Split := TLineSplitter.Create(65536);
  try
    repeat
      N := FOwner.FChild.ReadErr(Buf[0], Length(Buf));
      if N <= 0 then
        Break;
      for Line in Split.Feed(Buf, N) do
        FOwner.Log(Line);
      Split.TakeOverflow;
    until False;
  finally
    Split.Free;
  end;
end;

{ TBridgeServer.TWatchThread }

constructor TBridgeServer.TWatchThread.Create(AOwner: TBridgeServer);
begin
  FOwner := AOwner;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TBridgeServer.TWatchThread.Destroy;
begin
  FStop.Free;
  inherited;
end;

procedure TBridgeServer.TWatchThread.Execute;
begin
  while FStop.WaitFor(cWatchSliceMs) = wrTimeout do
    FOwner.CheckDeadlines;
end;

procedure TBridgeServer.TWatchThread.Finish;
begin
  FStop.SetEvent;
  WaitFor;
end;

{ TBridgeServer }

constructor TBridgeServer.Create(const AConfig: TBridgeServerConfig; AFactory: TBridgeChildFactory);
begin
  inherited Create;
  FConfig := AConfig;
  FFactory := AFactory;
  FLock := TCriticalSection.Create;
  FWriteLock := TCriticalSection.Create;
  FPending := TObjectDictionary<Integer, TPending>.Create([doOwnsValues]);
end;

destructor TBridgeServer.Destroy;
begin
  Stop;
  FPending.Free;
  FWriteLock.Free;
  FLock.Free;
  inherited;
end;

procedure TBridgeServer.Log(const ALine: string);
var
  Handler: TBridgeLogEvent;
begin
  Handler := FOnLog;
  if Assigned(Handler) then
    Handler(ALine);
end;

function TBridgeServer.NewId: Integer;
begin
  Result := TInterlocked.Increment(FNextId);
end;

function TBridgeServer.Send(const AJson: string): Boolean;
var
  Bytes: TBytes;
begin
  Result := False;
  if FChild = nil then
    Exit;
  Bytes := TEncoding.UTF8.GetBytes(AJson + #10);
  FWriteLock.Enter;
  try
    Result := FChild.Write(Bytes[0], Length(Bytes));
  finally
    FWriteLock.Leave;
  end;
end;

function TBridgeServer.AddPending(AId: Integer; ATimeoutMs: Cardinal; AOnRaw: TProc<string>;
  AOnProgress: TBridgeProgressEvent): Boolean;
var
  P: TPending;
begin
  FLock.Enter;
  try
    Result := FRunning and (FPending.Count < cBridgeMaxPending);
    if not Result then
      Exit;
    P := TPending.Create;
    P.OnRaw := AOnRaw;
    P.OnProgress := AOnProgress;
    P.TimeoutMs := ATimeoutMs;
    P.Deadline := TThread.GetTickCount64 + ATimeoutMs;
    FPending.Add(AId, P);
  finally
    FLock.Leave;
  end;
end;

// Removes the entry from the table and hands it over; nil when it is gone already.
function TBridgeServer.TakePending(AId: Integer): TPending;
begin
  FLock.Enter;
  try
    if FPending.TryGetValue(AId, Result) then
      FPending.ExtractPair(AId)
    else
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TBridgeServer.FailPending(AId: Integer; ACode: Integer; const AText: string);
var
  P: TPending;
begin
  P := TakePending(AId);
  if P = nil then
    Exit;
  try
    P.OnRaw(BuildRpcError(RpcIntId(AId), ACode, AText));
  finally
    P.Free;
  end;
end;

procedure TBridgeServer.FailAll(const AText: string);
var
  Ids: TArray<Integer>;
  Id: Integer;
begin
  FLock.Enter;
  try
    Ids := FPending.Keys.ToArray;
  finally
    FLock.Leave;
  end;
  for Id in Ids do
    FailPending(Id, cRpcInternalError, AText);
end;

procedure TBridgeServer.Dispatch(const ALine: string);
var
  Msg: TRpcMessage;
  Code, Token: Integer;
  Text: string;
  P: TPending;
  OnProgress: TBridgeProgressEvent;
begin
  if not TryParseRpcMessage(ALine, Msg, Code) then
  begin
    Log('not a message: ' + Copy(ALine, 1, 200));
    Exit;
  end;
  case Msg.Kind of
    rkResponse:
      if Msg.Id.Kind = ikInteger then
      begin
        P := TakePending(Msg.Id.IntValue);
        if P <> nil then
          try
            P.OnRaw(ALine);
          finally
            P.Free;
          end;
      end;
    rkNotification:
      if ParseProgressNotification(ALine, Token, Text) then
      begin
        OnProgress := nil;
        FLock.Enter;
        try
          if FPending.TryGetValue(Token, P) then
          begin
            // Progress keeps a long call alive.
            P.Deadline := TThread.GetTickCount64 + P.TimeoutMs;
            OnProgress := P.OnProgress;
          end;
        finally
          FLock.Leave;
        end;
        if Assigned(OnProgress) then
          OnProgress(Text);
      end;
    rkRequest:
      // The bridge offers the server nothing to ask for, but answers a ping.
      if Msg.Method = 'ping' then
        Send(BuildRpcResult(Msg.Id, '{}'))
      else
        Send(BuildRpcError(Msg.Id, cRpcMethodNotFound, 'not supported'));
  end;
end;

procedure TBridgeServer.ReaderEnded;
begin
  FLock.Enter;
  try
    FRunning := False;
  finally
    FLock.Leave;
  end;
  FailAll('the service process ended');
end;

procedure TBridgeServer.CheckDeadlines;
var
  Late: TArray<Integer>;
  Pair: TPair<Integer, TPending>;
  Now: UInt64;
  Id: Integer;
begin
  Now := TThread.GetTickCount64;
  SetLength(Late, 0);
  FLock.Enter;
  try
    for Pair in FPending do
      if Now > Pair.Value.Deadline then
      begin
        SetLength(Late, Length(Late) + 1);
        Late[High(Late)] := Pair.Key;
      end;
  finally
    FLock.Leave;
  end;
  for Id in Late do
  begin
    Send(BuildCancelNotification(Id, 'timeout'));
    FailPending(Id, cRpcTimeout, 'the service process did not answer in time');
  end;
end;

function TBridgeServer.RequestSync(ABuild: TFunc<Integer, string>; ATimeoutMs: Cardinal;
  out AMessageJson: string): Boolean;
var
  Done: TEvent;
  Id: Integer;
  Got: string;
begin
  Result := False;
  AMessageJson := '';
  Done := TEvent.Create(nil, True, False, '');
  try
    Id := NewId;
    Got := '';
    if not AddPending(Id, ATimeoutMs,
         procedure(AJson: string)
         begin
           Got := AJson;
           Done.SetEvent;
         end, nil) then
      Exit;
    if not Send(ABuild(Id)) then
    begin
      FailPending(Id, cRpcInternalError, 'cannot write to the service process');
      Done.WaitFor(1000);
      Exit;
    end;
    // The watchdog ends the wait after the timeout.
    Done.WaitFor(ATimeoutMs + 2000);
    AMessageJson := Got;
    Result := Got <> '';
  finally
    Done.Free;
  end;
end;

function TBridgeServer.Handshake(out AError: string): Boolean;
var
  Json, Version: string;
begin
  Result := False;
  if not RequestSync(
       function(AId: Integer): string
       begin
         Result := BuildInitializeRequest(AId);
       end, FConfig.StartTimeoutMs, Json) then
  begin
    AError := 'the service process did not answer the handshake';
    Exit;
  end;
  if not ParseInitializeResult(Json, Version) then
  begin
    AError := 'the service process speaks a protocol the bridge does not know';
    Exit;
  end;
  Result := Send(BuildInitializedNotification);
  if not Result then
    AError := 'cannot write to the service process';
end;

function TBridgeServer.LoadTools(out AError: string): Boolean;
var
  Cursor, Next, Json: string;
  Page: TArray<TBridgeTool>;
  Tool: TBridgeTool;
  Pages: Integer;
begin
  Result := False;
  SetLength(FTools, 0);
  Cursor := '';
  for Pages := 1 to cBridgeMaxToolPages do
  begin
    if not RequestSync(
         function(AId: Integer): string
         begin
           Result := BuildToolsListRequest(AId, Cursor);
         end, FConfig.StartTimeoutMs, Json) or
       not ParseToolsList(Json, Page, Next) then
    begin
      AError := 'the service process gave no list of tools';
      Exit;
    end;
    for Tool in Page do
      if BridgeToolAllowed(FConfig, Tool.Name) and (Length(FTools) < cBridgeMaxTools) and
         (BridgeServiceName(FConfig.Name, Tool.Name) <> '') then
      begin
        SetLength(FTools, Length(FTools) + 1);
        FTools[High(FTools)] := Tool;
      end;
    if Next = '' then
      Exit(True);
    Cursor := Next;
  end;
  // A server that never ends its list is cut after the page limit.
  Result := True;
end;

function TBridgeServer.Start(out AError: string): Boolean;
begin
  Result := False;
  AError := '';
  if FRunning then
    Exit(True);
  if not FFactory(FConfig, FChild) or (FChild = nil) then
  begin
    AError := 'cannot start "' + FConfig.Command + '"';
    Exit;
  end;
  FLock.Enter;
  try
    FRunning := True;
  finally
    FLock.Leave;
  end;
  FReader := TReaderThread.Create(Self);
  FErrReader := TErrThread.Create(Self);
  FWatch := TWatchThread.Create(Self);
  if Handshake(AError) and LoadTools(AError) then
    Exit(True);
  Stop;
end;

procedure TBridgeServer.Stop;
begin
  if FChild <> nil then
  begin
    FChild.Kill;
    FChild.CloseInput;
  end;
  FLock.Enter;
  try
    FRunning := False;
  finally
    FLock.Leave;
  end;
  if FWatch <> nil then
  begin
    FWatch.Finish;
    FreeAndNil(FWatch);
  end;
  if FReader <> nil then
  begin
    FReader.WaitFor;
    FreeAndNil(FReader);
  end;
  if FErrReader <> nil then
  begin
    FErrReader.WaitFor;
    FreeAndNil(FErrReader);
  end;
  FailAll('the service process was stopped');
  FChild := nil;
end;

function TBridgeServer.Call(const ATool, AArgumentsJson: string; ATimeoutMs: Cardinal;
  AOnReply: TBridgeReplyEvent; AOnProgress: TBridgeProgressEvent; out ACallId: Integer): Boolean;
var
  Id: Integer;
begin
  ACallId := 0;
  if ATimeoutMs = 0 then
    ATimeoutMs := cBridgeCallTimeoutMs;
  Id := NewId;
  Result := AddPending(Id, ATimeoutMs,
    procedure(AJson: string)
    begin
      AOnReply(MapToolResponse(AJson));
    end, AOnProgress);
  if not Result then
    Exit;
  ACallId := Id;
  if not Send(BuildToolCallRequest(Id, ATool, AArgumentsJson)) then
    FailPending(Id, cRpcInternalError, 'cannot write to the service process');
end;

procedure TBridgeServer.Cancel(ACallId: Integer);
var
  P: TPending;
begin
  P := TakePending(ACallId);
  if P = nil then
    Exit;
  P.Free;
  Send(BuildCancelNotification(ACallId, 'cancelled'));
end;

end.
