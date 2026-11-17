unit uBridgeHttp;

{ The HTTP transport of mtn.bridge. A server given by an address is reached through the same
  IChildProcess a program is: every message the bridge writes becomes one POST to the address,
  and every message in the answer (a JSON body, or the events of a text/event-stream) is read
  back as one line. So the handshake, the calls, the deadlines and the cancelling of
  uBridgeServer work unchanged.

  An answer is taken as one JSON message (or a list of them) when its first character is
  "{" or "[", and as a stream of events otherwise; the content type is not consulted. A server
  that sends a session id in the session header gets it back on the next requests.
  A request the server does not answer (a failed connection, an HTTP error without a JSON
  body, an empty body) is answered here with an error, so the call fails at once instead of
  waiting for its deadline. The HTTP client is reached through IBridgeHttpClient, so tests
  drive the transport with a fake that opens no connection. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  uPlatformChild, uBridgeConfig;

const
  cHttpResponseTimeoutMs = 130000;
  cHttpStopWaitMs = 3000;
  cSessionHeader = 'M' + 'cp-Session-Id';

type
  /// <summary>Cuts a text/event-stream into events and returns the data of each complete
  /// one. Lines end with LF, CRLF or CR; comments and fields other than "data" and "event"
  /// are ignored; an event whose name is not "message" is dropped. An event longer than the
  /// limit is dropped as a whole and reported once.</summary>
  TSseParser = class
  private
    FLine: TBytes;
    FLineLen: Integer;
    FLineTooLong: Boolean;
    FData: string;
    FHasData: Boolean;
    FEvent: string;
    FSkipLF: Boolean;
    FOverflowed: Boolean;
    FMax: Integer;
    FReady: TList<string>;
    procedure EndLine;
    procedure Dispatch;
  public
    constructor Create(AMaxEvent: Integer);
    destructor Destroy; override;
    function Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
    /// <summary>At the end of the stream: an event that lacks its closing blank line.</summary>
    function Flush: TArray<string>;
    function TakeOverflow: Boolean;
  end;

  /// <summary>Receives the body of one answer while it arrives and hands each JSON message in
  /// it to AOnMessage, compacted to one line.</summary>
  TBridgeResponseSink = class(TStream)
  private
    type
      TMode = (smUnknown, smJson, smEvents);
  private
    FOnMessage: TProc<string>;
    FMode: TMode;
    FBody: TBytes;
    FBodyLen: Integer;
    FParser: TSseParser;
    FOverflowed: Boolean;
    FDelivered: Integer;
    procedure Deliver(const AText: string);
    procedure DeliverAll(const AEvents: TArray<string>);
  public
    constructor Create(AOnMessage: TProc<string>);
    destructor Destroy; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    /// <summary>Call once the body is complete.</summary>
    procedure Finish;
    /// <summary>How many messages reached AOnMessage.</summary>
    property Delivered: Integer read FDelivered;
    /// <summary>True when a message was too long and was dropped.</summary>
    property Overflowed: Boolean read FOverflowed;
  end;

  TBridgeHttpAnswer = record
    Status: Integer;
    /// <summary>The session header of the answer; '' when it has none.</summary>
    SessionId: string;
  end;

  IBridgeHttpClient = interface
    /// <summary>Posts ABody (JSON) to the address of AServer with its headers and the session
    /// id (when not empty); the body of the answer is written to ASink as it arrives. False
    /// with AError when no answer came.</summary>
    function Post(const AServer: TBridgeServerConfig; const ABody, ASessionId: string;
      ASink: TStream; out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;
    /// <summary>Ends the posts in flight; later ones fail.</summary>
    procedure Abort;
  end;

  TBridgeHttpChild = class(TInterfacedObject, IChildProcess)
  private
    FServer: TBridgeServerConfig;
    FClient: IBridgeHttpClient;
    FLock: TCriticalSection;
    FAvail: TEvent;
    FStopped: TEvent;
    FOut: TQueue<TBytes>;
    FCur: TBytes;
    FCurPos: Integer;
    FIn: TBytes;
    FSession: string;
    FClosed: Boolean;
    FActive: Integer;
    procedure Push(const AJson: string);
    procedure PostLine(const ALine: string);
    procedure Work(const ALine: string; AIsRequest: Boolean; const AId: TObject);
  public
    constructor Create(const AServer: TBridgeServerConfig; AClient: IBridgeHttpClient);
    destructor Destroy; override;
    function Write(const ABuf; ACount: Integer): Boolean;
    function ReadOut(var ABuf; ACount: Integer): Integer;
    function ReadErr(var ABuf; ACount: Integer): Integer;
    procedure CloseInput;
    procedure Kill;
    function WaitExit(ATimeoutMs: Cardinal): Boolean;
    function ExitCode: Cardinal;
  end;

/// <summary>The client that opens real connections.</summary>
function NewBridgeHttpClient: IBridgeHttpClient;

/// <summary>The transport of an address-based server over the real client.</summary>
function StartBridgeHttp(const AServer: TBridgeServerConfig; out AChild: IChildProcess): Boolean;

implementation

uses
  System.JSON, System.Net.HttpClient, System.Net.URLClient, uJsonRpc, uBridgeProtocol;

{ TSseParser }

constructor TSseParser.Create(AMaxEvent: Integer);
begin
  inherited Create;
  FMax := AMaxEvent;
  FReady := TList<string>.Create;
  SetLength(FLine, 4096);
end;

destructor TSseParser.Destroy;
begin
  FReady.Free;
  inherited;
end;

procedure TSseParser.Dispatch;
begin
  if FHasData and ((FEvent = '') or (FEvent = 'message')) then
    FReady.Add(FData);
  FData := '';
  FHasData := False;
  FEvent := '';
end;

procedure TSseParser.EndLine;
var
  Text, Field, Value: string;
  P: Integer;
begin
  if FLineTooLong then
  begin
    // The event this line belongs to is lost with it.
    FOverflowed := True;
    FLineTooLong := False;
    FLineLen := 0;
    FData := '';
    FHasData := False;
    FEvent := '';
    Exit;
  end;
  Text := TEncoding.UTF8.GetString(FLine, 0, FLineLen);
  FLineLen := 0;
  if Text = '' then
  begin
    Dispatch;
    Exit;
  end;
  if Text[1] = ':' then
    Exit;
  P := Pos(':', Text);
  if P = 0 then
  begin
    Field := Text;
    Value := '';
  end
  else
  begin
    Field := Copy(Text, 1, P - 1);
    Value := Copy(Text, P + 1, MaxInt);
    if (Value <> '') and (Value[1] = ' ') then
      Delete(Value, 1, 1);
  end;
  if Field = 'data' then
  begin
    if Length(FData) + Length(Value) + 1 > FMax then
    begin
      FOverflowed := True;
      FData := '';
      FHasData := False;
      Exit;
    end;
    if FHasData then
      FData := FData + #10;
    FData := FData + Value;
    FHasData := True;
  end
  else if Field = 'event' then
    FEvent := Value;
end;

function TSseParser.Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
var
  I: Integer;
  B: Byte;
begin
  for I := 0 to ACount - 1 do
  begin
    B := ABytes[I];
    if FSkipLF then
    begin
      FSkipLF := False;
      if B = 10 then
        Continue;
    end;
    if B = 13 then
    begin
      FSkipLF := True;
      EndLine;
    end
    else if B = 10 then
      EndLine
    else if not FLineTooLong then
    begin
      if FLineLen >= FMax then
        FLineTooLong := True
      else
      begin
        if FLineLen >= Length(FLine) then
          SetLength(FLine, Length(FLine) * 2);
        FLine[FLineLen] := B;
        Inc(FLineLen);
      end;
    end;
  end;
  Result := FReady.ToArray;
  FReady.Clear;
end;

function TSseParser.Flush: TArray<string>;
begin
  if FLineLen > 0 then
    EndLine;
  Dispatch;
  Result := FReady.ToArray;
  FReady.Clear;
end;

function TSseParser.TakeOverflow: Boolean;
begin
  Result := FOverflowed;
  FOverflowed := False;
end;

{ TBridgeResponseSink }

constructor TBridgeResponseSink.Create(AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FParser := TSseParser.Create(cBridgeMaxLine);
end;

destructor TBridgeResponseSink.Destroy;
begin
  FParser.Free;
  inherited;
end;

procedure TBridgeResponseSink.Deliver(const AText: string);
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AText);
  try
    if V is TJSONObject then
    begin
      Inc(FDelivered);
      FOnMessage(V.ToJSON);
    end;
  finally
    V.Free;
  end;
end;

procedure TBridgeResponseSink.DeliverAll(const AEvents: TArray<string>);
var
  E: string;
begin
  for E in AEvents do
    Deliver(E);
end;

function TBridgeResponseSink.Write(const Buffer; Count: Longint): Longint;
var
  Bytes: PByteArray;
  Chunk: TBytes;
  I, Skip, N: Integer;
begin
  Result := Count;
  if Count <= 0 then
    Exit;
  Bytes := PByteArray(@Buffer);
  Skip := 0;
  if FMode = smUnknown then
  begin
    if (Count >= 3) and (Bytes^[0] = $EF) and (Bytes^[1] = $BB) and (Bytes^[2] = $BF) then
      Skip := 3;
    I := Skip;
    while (I < Count) and (Bytes^[I] in [9, 10, 13, 32]) do
      Inc(I);
    // Blanks alone decide nothing yet.
    if I >= Count then
      Exit;
    if Bytes^[I] in [Ord('{'), Ord('[')] then
      FMode := smJson
    else
      FMode := smEvents;
  end;
  N := Count - Skip;
  if FMode = smJson then
  begin
    if FBodyLen + N > cBridgeMaxLine then
    begin
      FOverflowed := True;
      Exit;
    end;
    if FBodyLen + N > Length(FBody) then
      SetLength(FBody, (FBodyLen + N) * 2);
    Move(Bytes^[Skip], FBody[FBodyLen], N);
    Inc(FBodyLen, N);
  end
  else
  begin
    SetLength(Chunk, N);
    Move(Bytes^[Skip], Chunk[0], N);
    DeliverAll(FParser.Feed(Chunk, N));
    if FParser.TakeOverflow then
      FOverflowed := True;
  end;
end;

function TBridgeResponseSink.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TBridgeResponseSink.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

procedure TBridgeResponseSink.Finish;
var
  V: TJSONValue;
  I: Integer;
begin
  if FMode = smEvents then
  begin
    DeliverAll(FParser.Flush);
    Exit;
  end;
  if (FMode <> smJson) or FOverflowed or (FBodyLen = 0) then
    Exit;
  V := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(FBody, 0, FBodyLen));
  try
    if V is TJSONObject then
      Deliver(V.ToJSON)
    else if V is TJSONArray then
      for I := 0 to TJSONArray(V).Count - 1 do
        if TJSONArray(V).Items[I] is TJSONObject then
          Deliver(TJSONArray(V).Items[I].ToJSON);
  finally
    V.Free;
  end;
end;

{ TBridgeHttpChild }

constructor TBridgeHttpChild.Create(const AServer: TBridgeServerConfig; AClient: IBridgeHttpClient);
begin
  inherited Create;
  FServer := AServer;
  FClient := AClient;
  FLock := TCriticalSection.Create;
  FAvail := TEvent.Create(nil, True, False, '');
  FStopped := TEvent.Create(nil, True, False, '');
  FOut := TQueue<TBytes>.Create;
end;

destructor TBridgeHttpChild.Destroy;
begin
  Kill;
  FOut.Free;
  FStopped.Free;
  FAvail.Free;
  FLock.Free;
  inherited;
end;

procedure TBridgeHttpChild.Push(const AJson: string);
begin
  FLock.Enter;
  try
    if FClosed then
      Exit;
    FOut.Enqueue(TEncoding.UTF8.GetBytes(AJson + #10));
    FAvail.SetEvent;
  finally
    FLock.Leave;
  end;
end;

type
  // The id of the request a failure answers, kept in the closure of the worker.
  TIdBox = class
    Id: TRpcId;
  end;

procedure TBridgeHttpChild.Work(const ALine: string; AIsRequest: Boolean; const AId: TObject);
var
  Sink: TBridgeResponseSink;
  Answer: TBridgeHttpAnswer;
  Err, Session: string;
  Ok: Boolean;

  procedure Fail(const AText: string);
  begin
    if AIsRequest then
      Push(BuildRpcError(TIdBox(AId).Id, cRpcInternalError, AText));
  end;

begin
  FLock.Enter;
  try
    Session := FSession;
  finally
    FLock.Leave;
  end;
  Sink := TBridgeResponseSink.Create(
    procedure(AMessage: string)
    begin
      Push(AMessage);
    end);
  try
    Ok := FClient.Post(FServer, ALine, Session, Sink, Answer, Err);
    if FClosed then
      Exit;
    if not Ok then
    begin
      Fail(Err);
      Exit;
    end;
    if Answer.SessionId <> '' then
    begin
      FLock.Enter;
      try
        FSession := Answer.SessionId;
      finally
        FLock.Leave;
      end;
    end;
    Sink.Finish;
    if AIsRequest and (Sink.Delivered = 0) then
    begin
      if Sink.Overflowed then
        Fail('an answer of the server was too long')
      else if (Answer.Status < 200) or (Answer.Status > 299) then
        Fail('HTTP ' + IntToStr(Answer.Status))
      else
        Fail('the server sent no answer');
    end;
  finally
    Sink.Free;
  end;
end;

procedure TBridgeHttpChild.PostLine(const ALine: string);
var
  Msg: TRpcMessage;
  Code: Integer;
  IsRequest: Boolean;
  Box: TIdBox;
begin
  IsRequest := TryParseRpcMessage(ALine, Msg, Code) and (Msg.Kind = rkRequest);
  Box := nil;
  if IsRequest then
  begin
    Box := TIdBox.Create;
    Box.Id := Msg.Id;
  end;
  TInterlocked.Increment(FActive);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        try
          Work(ALine, IsRequest, Box);
        except
          // A failed request is answered by Work; nothing else may leave the thread.
        end;
      finally
        Box.Free;
        TInterlocked.Decrement(FActive);
      end;
    end).Start;
end;

function TBridgeHttpChild.Write(const ABuf; ACount: Integer): Boolean;
var
  Start, I: Integer;
  Line: string;
begin
  Result := False;
  if (ACount <= 0) or FClosed then
    Exit;
  SetLength(FIn, Length(FIn) + ACount);
  Move(ABuf, FIn[Length(FIn) - ACount], ACount);
  Start := 0;
  for I := 0 to High(FIn) do
    if FIn[I] = 10 then
    begin
      Line := Trim(TEncoding.UTF8.GetString(FIn, Start, I - Start));
      Start := I + 1;
      if Line <> '' then
        PostLine(Line);
    end;
  if Start > 0 then
    FIn := Copy(FIn, Start, Length(FIn) - Start);
  Result := True;
end;

function TBridgeHttpChild.ReadOut(var ABuf; ACount: Integer): Integer;
var
  N: Integer;
begin
  Result := 0;
  if ACount <= 0 then
    Exit;
  while True do
  begin
    FLock.Enter;
    try
      if FCurPos >= Length(FCur) then
      begin
        FCur := nil;
        FCurPos := 0;
        if FOut.Count > 0 then
          FCur := FOut.Dequeue;
      end;
      if FCurPos < Length(FCur) then
      begin
        N := Length(FCur) - FCurPos;
        if N > ACount then
          N := ACount;
        Move(FCur[FCurPos], ABuf, N);
        Inc(FCurPos, N);
        Exit(N);
      end;
      if FClosed then
        Exit(0);
      FAvail.ResetEvent;
    finally
      FLock.Leave;
    end;
    FAvail.WaitFor(INFINITE);
  end;
end;

function TBridgeHttpChild.ReadErr(var ABuf; ACount: Integer): Integer;
begin
  // An address has no diagnostics stream: the read waits until the transport ends.
  FStopped.WaitFor(INFINITE);
  Result := 0;
end;

procedure TBridgeHttpChild.CloseInput;
begin
end;

procedure TBridgeHttpChild.Kill;
var
  Waited: Integer;
begin
  FLock.Enter;
  try
    FClosed := True;
    FAvail.SetEvent;
    FStopped.SetEvent;
  finally
    FLock.Leave;
  end;
  FClient.Abort;
  Waited := 0;
  while (TInterlocked.CompareExchange(FActive, 0, 0) > 0) and (Waited < cHttpStopWaitMs) do
  begin
    Sleep(5);
    Inc(Waited, 5);
  end;
end;

function TBridgeHttpChild.WaitExit(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FClosed;
end;

function TBridgeHttpChild.ExitCode: Cardinal;
begin
  Result := 0;
end;

{ The client over System.Net.HttpClient }

type
  TRealHttpClient = class(TInterfacedObject, IBridgeHttpClient)
  private
    FLock: TCriticalSection;
    FRequests: TList<IHTTPRequest>;
    FAborted: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Post(const AServer: TBridgeServerConfig; const ABody, ASessionId: string;
      ASink: TStream; out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;
    procedure Abort;
  end;

constructor TRealHttpClient.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRequests := TList<IHTTPRequest>.Create;
end;

destructor TRealHttpClient.Destroy;
begin
  FRequests.Free;
  FLock.Free;
  inherited;
end;

procedure TRealHttpClient.Abort;
var
  Live: TArray<IHTTPRequest>;
  R: IHTTPRequest;
begin
  FLock.Enter;
  try
    FAborted := True;
    Live := FRequests.ToArray;
  finally
    FLock.Leave;
  end;
  for R in Live do
    try
      R.Cancel;
    except
      // A request that has just finished cannot be cancelled; that is fine.
    end;
end;

function TRealHttpClient.Post(const AServer: TBridgeServerConfig; const ABody, ASessionId: string;
  ASink: TStream; out AAnswer: TBridgeHttpAnswer; out AError: string): Boolean;
var
  Client: THTTPClient;
  Req: IHTTPRequest;
  Resp: IHTTPResponse;
  Source: TStringStream;
  Pair: string;
  P: Integer;
begin
  Result := False;
  AAnswer := Default(TBridgeHttpAnswer);
  AError := '';
  Client := THTTPClient.Create;
  Source := TStringStream.Create(ABody, TEncoding.UTF8, False);
  try
    try
      Client.ConnectionTimeout := AServer.StartTimeoutMs;
      Client.SendTimeout := AServer.StartTimeoutMs;
      Client.ResponseTimeout := cHttpResponseTimeoutMs;
      Client.UserAgent := 'MTN2-bridge';
      Req := Client.GetRequest('POST', AServer.Url);
      Req.AddHeader('Content-Type', 'application/json');
      Req.AddHeader('Accept', 'application/json, text/event-stream');
      Req.AddHeader('M' + 'CP-Protocol-Version', cBridgeProtocolVersion);
      if ASessionId <> '' then
        Req.AddHeader(cSessionHeader, ASessionId);
      for Pair in AServer.Headers do
      begin
        P := Pos('=', Pair);
        if P > 1 then
          Req.AddHeader(Copy(Pair, 1, P - 1), Copy(Pair, P + 1, MaxInt));
      end;
      Req.SourceStream := Source;
      FLock.Enter;
      try
        if FAborted then
        begin
          AError := 'the connection was closed';
          Exit;
        end;
        FRequests.Add(Req);
      finally
        FLock.Leave;
      end;
      try
        Resp := Client.Execute(Req, ASink);
      finally
        FLock.Enter;
        try
          FRequests.Remove(Req);
        finally
          FLock.Leave;
        end;
      end;
      AAnswer.Status := Resp.StatusCode;
      AAnswer.SessionId := Resp.HeaderValue[cSessionHeader];
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        Result := False;
      end;
    end;
  finally
    Resp := nil;
    Req := nil;
    Source.Free;
    Client.Free;
  end;
end;

function NewBridgeHttpClient: IBridgeHttpClient;
begin
  Result := TRealHttpClient.Create;
end;

function StartBridgeHttp(const AServer: TBridgeServerConfig; out AChild: IChildProcess): Boolean;
begin
  AChild := TBridgeHttpChild.Create(AServer, NewBridgeHttpClient);
  Result := True;
end;

end.
