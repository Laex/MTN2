unit uNetCurl;

{ One libcurl request at a time, and the pool of connections behind a session.

  A TCurlPool keeps easy handles of one server between requests, so FTP and
  SFTP control connections and HTTP keep-alive connections are reused, and
  limits how many requests run at once (servers refuse a flood of logins).
  A TCurlCall is one request: it borrows a handle, applies the session's
  login / TLS / proxy settings, runs the transfer with progress and
  cancellation, and turns curl's outcome into a TNetResult plus a message.

  Everything here is callable from any thread; a call object is used by the
  thread that made it. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uNetCurlApi, uNetTypes;

type
  TCurlPool = class
  private
    FIdle: TList<PCurl>;
    FLock: TCriticalSection;
    FSlots: TSemaphore;
    FClosed: Boolean;
  public
    constructor Create(AMaxParallel: Integer);
    destructor Destroy; override;
    /// <summary>Waits for a free slot, then hands out a handle. False when the
    /// operation is cancelled while waiting or the pool is closed.</summary>
    function Acquire(AOp: TNetOp; out AHandle: PCurl): Boolean;
    procedure Release(AHandle: PCurl; AKeepConnection: Boolean);
    /// <summary>Closes the idle connections and refuses new requests.</summary>
    procedure Close;
  end;

  TCurlCall = class
  private
    FPool: TCurlPool;
    FSession: TNetSession;
    FOp: TNetOp;
    FHandle: PCurl;
    FHeaders: PCurlSlist;
    FQuote: PCurlSlist;
    FPostQuote: PCurlSlist;
    FErrorBuffer: array[0..299] of AnsiChar;
    FPostData: UTF8String;
    FResponseHeaders: TStringList;
    FStarted: Boolean;
    FCancelledByUs: Boolean;
    FSeenHostKey: string;
    FHostKeyProblem: Integer; // 0 none, 1 unknown, 2 changed
    FSshKnownHosts: string;
    procedure Opt(AOption: Integer; const AValue: string); overload;
    procedure Opt(AOption: Integer; AValue: Integer); overload;
    procedure OptPtr(AOption: Integer; AValue: Pointer);
    procedure OptOff(AOption: Integer; AValue: Int64);
    function ErrorMessage(ACode: CURLcode): string;
  public
    /// <summary>Where the body of the answer goes (nil = discarded).</summary>
    Body: TStream;
    /// <summary>The data sent by an upload.</summary>
    Source: TStream;
    /// <summary>Bytes transferred before this request began (a resumed
    /// download); added to the progress it reports.</summary>
    ProgressBase: Int64;
    /// <summary>Name shown with the progress.</summary>
    ProgressName: string;
    /// <summary>Total size when known beforehand (otherwise taken from the answer).</summary>
    ProgressTotal: Int64;
    /// <summary>Cap on the bytes accepted into Body (0 = none); more makes the
    /// call fail with nrIO "too large".</summary>
    BodyLimit: Int64;
    BodyTooLarge: Boolean;
    HttpStatus: Integer;
    FileTime: Int64;
    ContentLength: Int64;
    constructor Create(APool: TCurlPool; const ASession: TNetSession; AOp: TNetOp);
    destructor Destroy; override;
    /// <summary>Takes a handle and applies the options every request shares.
    /// False when no handle could be had (cancelled) - Perform then reports it.</summary>
    function Start(const AUrl: string): Boolean;
    procedure SetCustomRequest(const ARequest: string);
    procedure AddHeader(const AHeader: string);
    procedure AddQuote(const ACommand: string); overload;
    procedure AddQuote(const ACommand: TBytes); overload;
    procedure AddPostQuote(const ACommand: string);
    procedure SetNoBody;
    procedure SetUpload(ASize: Int64);
    procedure SetPostBody(const ABody: string);
    procedure SetRange(AFrom: Int64);
    procedure SetTimeout(ASeconds: Integer);
    /// <summary>Checks the SSH host key against Session.HostKeySha256 (an
    /// empty value makes every key "unknown" so the caller can ask the user);
    /// AKnownHostsFile is an existing, empty file libcurl needs for the check.</summary>
    procedure EnableSshHostKeyCheck(const AKnownHostsFile: string);
    procedure SetLong(AOption, AValue: Integer);
    procedure SetText(AOption: Integer; const AValue: string);
    /// <summary>Runs the request. Returns nrOk or the mapped failure; the
    /// message goes to Op.ErrorText.</summary>
    function Perform: TNetResult;
    function ResponseHeader(const AName: string): string;
    property Session: TNetSession read FSession;
  end;

/// <summary>SHA-256 of an SSH host key as shown by OpenSSH (base64, no padding).</summary>
function HostKeyFingerprint(const AKey: TBytes): string;

/// <summary>Maps a failed transfer to a result. AHttpStatus is 0 for non-HTTP
/// protocols; ATransport tells HTTP-like (True) from FTP/SSH (False).</summary>
function MapCurlCode(ACode: CURLcode; AHttpStatus: Integer; ATransport: TNetProtocol;
  const AMessage: string): TNetResult;
function MapHttpStatus(AStatus: Integer): TNetResult;

implementation

uses
  System.Hash, System.NetEncoding, System.IOUtils;

{ callbacks }

function WriteCallback(ABuffer: Pointer; ASize, ACount: NativeUInt; AUserData: Pointer): NativeUInt; cdecl;
var
  Call: TCurlCall;
  N: NativeUInt;
begin
  N := ASize * ACount;
  Result := N;
  try
    Call := TCurlCall(AUserData);
    if Call.Body = nil then
      Exit;
    if (Call.BodyLimit > 0) and (Call.Body.Size + Int64(N) > Call.BodyLimit) then
    begin
      Call.BodyTooLarge := True;
      Exit(0);
    end;
    if N > 0 then
      Result := NativeUInt(Call.Body.Write(ABuffer^, N));
  except
    Result := 0;
  end;
end;

function ReadCallback(ABuffer: Pointer; ASize, ACount: NativeUInt; AUserData: Pointer): NativeUInt; cdecl;
var
  Call: TCurlCall;
begin
  try
    Call := TCurlCall(AUserData);
    if Call.Source = nil then
      Exit(0);
    Result := NativeUInt(Call.Source.Read(ABuffer^, ASize * ACount));
  except
    Result := CURL_READFUNC_ABORT;
  end;
end;

function SeekCallback(AUserData: Pointer; AOffset: Int64; AOrigin: Integer): Integer; cdecl;
var
  Call: TCurlCall;
  Origin: TSeekOrigin;
begin
  Result := 1; // CURL_SEEKFUNC_FAIL
  try
    Call := TCurlCall(AUserData);
    if Call.Source = nil then
      Exit;
    case AOrigin of
      0: Origin := soBeginning;
      1: Origin := soCurrent;
    else
      Origin := soEnd;
    end;
    // Needed when the server asks to log in after the data has been offered.
    Call.Source.Seek(AOffset, Origin);
    Result := 0;
  except
    Result := 1;
  end;
end;

function HeaderCallback(ABuffer: Pointer; ASize, ACount: NativeUInt; AUserData: Pointer): NativeUInt; cdecl;
var
  Call: TCurlCall;
  Line: UTF8String;
  N: NativeUInt;
begin
  N := ASize * ACount;
  Result := N;
  try
    Call := TCurlCall(AUserData);
    SetString(Line, PAnsiChar(ABuffer), N);
    Call.FResponseHeaders.Add(Trim(string(Line)));
  except
    // A header we cannot keep is not worth failing the transfer.
  end;
end;

function XferInfoCallback(AUserData: Pointer; ADlTotal, ADlNow, AUlTotal, AUlNow: Int64): Integer; cdecl;
var
  Call: TCurlCall;
  Done, Total: Int64;
begin
  Result := 0;
  try
    Call := TCurlCall(AUserData);
    if Call.FOp = nil then
      Exit;
    if Call.FOp.IsCancelled then
    begin
      Call.FCancelledByUs := True;
      Exit(1);
    end;
    if AUlTotal > 0 then
    begin
      Done := AUlNow;
      Total := AUlTotal;
    end
    else
    begin
      Done := ADlNow;
      Total := ADlTotal;
    end;
    if Call.ProgressTotal > 0 then
      Total := Call.ProgressTotal
    else if Total > 0 then
      Total := Total + Call.ProgressBase;
    Call.FOp.Report(Done + Call.ProgressBase, Total, Call.ProgressName);
  except
    Result := 0;
  end;
end;

function SshKeyCallback(AEasy: PCurl; AKnown, AFound: PCurlKhKey; AMatch: Integer;
  AUserData: Pointer): Integer; cdecl;
var
  Call: TCurlCall;
  Raw: TBytes;
begin
  Result := CURLKHSTAT_REJECT;
  try
    Call := TCurlCall(AUserData);
    if (AFound = nil) or (AFound.Key = nil) then
      Exit;
    if AFound.Len = 0 then
      Raw := TNetEncoding.Base64.DecodeStringToBytes(string(AnsiString(AFound.Key)))
    else
    begin
      SetLength(Raw, AFound.Len);
      Move(AFound.Key^, Raw[0], AFound.Len);
    end;
    Call.FSeenHostKey := HostKeyFingerprint(Raw);
    if Call.FSession.HostKeySha256 = '' then
    begin
      Call.FHostKeyProblem := 1;
      Exit(CURLKHSTAT_REJECT);
    end;
    if Call.FSession.HostKeySha256 = Call.FSeenHostKey then
      Exit(CURLKHSTAT_FINE);
    Call.FHostKeyProblem := 2;
  except
    Result := CURLKHSTAT_REJECT;
  end;
end;

{ TCurlPool }

constructor TCurlPool.Create(AMaxParallel: Integer);
begin
  inherited Create;
  if AMaxParallel < 1 then
    AMaxParallel := 1;
  FIdle := TList<PCurl>.Create;
  FLock := TCriticalSection.Create;
  FSlots := TSemaphore.Create(nil, AMaxParallel, AMaxParallel, '');
end;

destructor TCurlPool.Destroy;
begin
  Close;
  FSlots.Free;
  FLock.Free;
  FIdle.Free;
  inherited Destroy;
end;

function TCurlPool.Acquire(AOp: TNetOp; out AHandle: PCurl): Boolean;
begin
  AHandle := nil;
  Result := False;
  if FClosed or not CurlLoaded then
    Exit;
  // Waiting for a slot is a place the user may cancel.
  while FSlots.WaitFor(200) <> wrSignaled do
  begin
    if FClosed or ((AOp <> nil) and AOp.IsCancelled) then
      Exit;
  end;
  FLock.Enter;
  try
    if FIdle.Count > 0 then
    begin
      AHandle := FIdle[FIdle.Count - 1];
      FIdle.Delete(FIdle.Count - 1);
    end;
  finally
    FLock.Leave;
  end;
  if AHandle = nil then
    AHandle := Curl.EasyInit();
  if AHandle = nil then
  begin
    FSlots.Release;
    Exit;
  end;
  Result := True;
end;

procedure TCurlPool.Release(AHandle: PCurl; AKeepConnection: Boolean);
begin
  if AHandle = nil then
    Exit;
  if AKeepConnection and not FClosed then
  begin
    FLock.Enter;
    try
      FIdle.Add(AHandle);
    finally
      FLock.Leave;
    end;
  end
  else
    Curl.EasyCleanup(AHandle);
  FSlots.Release;
end;

procedure TCurlPool.Close;
var
  H: PCurl;
begin
  FClosed := True;
  FLock.Enter;
  try
    for H in FIdle do
      if CurlLoaded then
        Curl.EasyCleanup(H);
    FIdle.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TCurlCall }

constructor TCurlCall.Create(APool: TCurlPool; const ASession: TNetSession; AOp: TNetOp);
begin
  inherited Create;
  FPool := APool;
  FSession := ASession;
  FOp := AOp;
  FResponseHeaders := TStringList.Create;
  ContentLength := -1;
end;

destructor TCurlCall.Destroy;
begin
  if FStarted and (FHandle <> nil) then
  begin
    // The handle goes back with its connection unless the request died on it.
    FPool.Release(FHandle, True);
    FHandle := nil;
  end;
  if FHeaders <> nil then
    Curl.SlistFreeAll(FHeaders);
  if FQuote <> nil then
    Curl.SlistFreeAll(FQuote);
  if FPostQuote <> nil then
    Curl.SlistFreeAll(FPostQuote);
  FResponseHeaders.Free;
  inherited Destroy;
end;

procedure TCurlCall.Opt(AOption: Integer; const AValue: string);
var
  U: UTF8String;
begin
  U := UTF8String(AValue);
  Curl.SetOptPtr(FHandle, AOption, PAnsiChar(U));
end;

procedure TCurlCall.Opt(AOption: Integer; AValue: Integer);
begin
  Curl.SetOptLong(FHandle, AOption, TCurlLong(AValue));
end;

procedure TCurlCall.OptPtr(AOption: Integer; AValue: Pointer);
begin
  Curl.SetOptPtr(FHandle, AOption, AValue);
end;

procedure TCurlCall.OptOff(AOption: Integer; AValue: Int64);
begin
  Curl.SetOptOff(FHandle, AOption, AValue);
end;

function TCurlCall.Start(const AUrl: string): Boolean;
var
  Proxy: string;
begin
  Result := False;
  if not FPool.Acquire(FOp, FHandle) then
    Exit;
  FStarted := True;
  Curl.EasyReset(FHandle);
  FErrorBuffer[0] := #0;
  OptPtr(CURLOPT_ERRORBUFFER, @FErrorBuffer[0]);
  Opt(CURLOPT_URL, AUrl);
  Opt(CURLOPT_NOSIGNAL, 1);
  Opt(CURLOPT_NOPROGRESS, 0);
  OptPtr(CURLOPT_WRITEFUNCTION, @WriteCallback);
  OptPtr(CURLOPT_WRITEDATA, Self);
  OptPtr(CURLOPT_HEADERFUNCTION, @HeaderCallback);
  OptPtr(CURLOPT_HEADERDATA, Self);
  OptPtr(CURLOPT_XFERINFOFUNCTION, @XferInfoCallback);
  OptPtr(CURLOPT_XFERINFODATA, Self);
  Opt(CURLOPT_CONNECTTIMEOUT, FSession.TimeoutSec);
  // A transfer that moves nothing for this long is dead; slow ones are fine.
  Opt(CURLOPT_LOW_SPEED_LIMIT, 1);
  Opt(CURLOPT_LOW_SPEED_TIME, FSession.TimeoutSec * 2);
  Opt(CURLOPT_TCP_KEEPALIVE, 1);
  Opt(CURLOPT_TCP_KEEPIDLE, 60);
  Opt(CURLOPT_TCP_KEEPINTVL, 30);
  Opt(CURLOPT_USERAGENT, 'MTN2');
  // Diagnostics: protocol trace to the console of a host started from one.
  if GetEnvironmentVariable('MTN2_CURL_VERBOSE') <> '' then
    Opt(CURLOPT_VERBOSE, 1);
  if not FSession.VerifyCert then
  begin
    Opt(CURLOPT_SSL_VERIFYPEER, 0);
    Opt(CURLOPT_SSL_VERIFYHOST, 0);
  end
  else
    Opt(CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
  Proxy := Trim(FSession.Proxy);
  if Proxy <> '' then
    Opt(CURLOPT_PROXY, Proxy);
  Result := True;
end;

procedure TCurlCall.SetCustomRequest(const ARequest: string);
begin
  if FHandle <> nil then
    Opt(CURLOPT_CUSTOMREQUEST, ARequest);
end;

procedure TCurlCall.AddHeader(const AHeader: string);
begin
  FHeaders := Curl.SlistAppend(FHeaders, PAnsiChar(UTF8String(AHeader)));
end;

procedure TCurlCall.AddQuote(const ACommand: string);
begin
  FQuote := Curl.SlistAppend(FQuote, PAnsiChar(UTF8String(ACommand)));
end;

procedure TCurlCall.AddQuote(const ACommand: TBytes);
var
  Z: TBytes;
begin
  // The command goes out byte for byte (a server may use another code page).
  Z := Copy(ACommand);
  SetLength(Z, Length(ACommand) + 1);
  Z[Length(ACommand)] := 0;
  FQuote := Curl.SlistAppend(FQuote, PAnsiChar(@Z[0]));
end;

procedure TCurlCall.AddPostQuote(const ACommand: string);
begin
  FPostQuote := Curl.SlistAppend(FPostQuote, PAnsiChar(UTF8String(ACommand)));
end;

procedure TCurlCall.SetNoBody;
begin
  if FHandle <> nil then
    Opt(CURLOPT_NOBODY, 1);
end;

procedure TCurlCall.SetUpload(ASize: Int64);
begin
  if FHandle = nil then
    Exit;
  Opt(CURLOPT_UPLOAD, 1);
  OptOff(CURLOPT_INFILESIZE_LARGE, ASize);
  OptPtr(CURLOPT_READFUNCTION, @ReadCallback);
  OptPtr(CURLOPT_READDATA, Self);
  OptPtr(CURLOPT_SEEKFUNCTION, @SeekCallback);
  OptPtr(CURLOPT_SEEKDATA, Self);
  ProgressTotal := ASize;
end;

procedure TCurlCall.SetPostBody(const ABody: string);
begin
  if FHandle = nil then
    Exit;
  FPostData := UTF8String(ABody);
  OptOff(CURLOPT_POSTFIELDSIZE_LARGE, Length(FPostData));
  OptPtr(CURLOPT_POSTFIELDS, PAnsiChar(FPostData));
end;

procedure TCurlCall.SetRange(AFrom: Int64);
begin
  if (FHandle <> nil) and (AFrom > 0) then
    OptOff(CURLOPT_RESUME_FROM_LARGE, AFrom);
end;

procedure TCurlCall.SetTimeout(ASeconds: Integer);
begin
  if FHandle <> nil then
    Opt(CURLOPT_TIMEOUT, ASeconds);
end;

procedure TCurlCall.EnableSshHostKeyCheck(const AKnownHostsFile: string);
begin
  FSshKnownHosts := AKnownHostsFile;
end;

procedure TCurlCall.SetLong(AOption, AValue: Integer);
begin
  if FHandle <> nil then
    Opt(AOption, AValue);
end;

procedure TCurlCall.SetText(AOption: Integer; const AValue: string);
begin
  if FHandle <> nil then
    Opt(AOption, AValue);
end;

function TCurlCall.ErrorMessage(ACode: CURLcode): string;
var
  Text: string;
begin
  Text := Trim(string(AnsiString(PAnsiChar(@FErrorBuffer[0]))));
  if Text = '' then
    Text := string(AnsiString(Curl.EasyStrError(ACode)));
  Result := Text;
end;

function TCurlCall.ResponseHeader(const AName: string): string;
var
  I: Integer;
  Line: string;
begin
  Result := '';
  for I := FResponseHeaders.Count - 1 downto 0 do
  begin
    Line := FResponseHeaders[I];
    if (Length(Line) > Length(AName) + 1) and SameText(Copy(Line, 1, Length(AName)), AName) and
       (Line[Length(AName) + 1] = ':') then
      Exit(Trim(Copy(Line, Length(AName) + 2, MaxInt)));
  end;
end;

function TCurlCall.Perform: TNetResult;
var
  Code: CURLcode;
  Status: TCurlLong;
  Time: Int64;
  Len: Int64;
  Attempt: Integer;
begin
  if not FStarted then
  begin
    if (FOp <> nil) and FOp.IsCancelled then
      Exit(nrCancelled);
    if FOp <> nil then
      FOp.ErrorText := 'No connection slot is available';
    Exit(nrIO);
  end;
  if FHeaders <> nil then
    OptPtr(CURLOPT_HTTPHEADER, FHeaders);
  if FQuote <> nil then
    OptPtr(CURLOPT_QUOTE, FQuote);
  if FPostQuote <> nil then
    OptPtr(CURLOPT_POSTQUOTE, FPostQuote);
  if FSshKnownHosts <> '' then
  begin
    Opt(CURLOPT_SSH_KNOWNHOSTS, FSshKnownHosts);
    OptPtr(CURLOPT_SSH_KEYFUNCTION, @SshKeyCallback);
    OptPtr(CURLOPT_SSH_KEYDATA, Self);
  end;
  Opt(CURLOPT_FILETIME, 1);
  Attempt := 0;
  repeat
    Inc(Attempt);
    FHostKeyProblem := 0;
    Code := Curl.EasyPerform(FHandle);
    // A failed SSH handshake has transferred nothing, so repeating it is safe;
    // key exchange failures are sometimes transient.
  until ((Code <> CURLE_SSH) and (Code <> CURLE_FAILED_INIT)) or (Attempt >= 3) or (FHostKeyProblem <> 0) or
    (Pos('exchange encryption keys', string(AnsiString(PAnsiChar(@FErrorBuffer[0])))) = 0) or
    ((FOp <> nil) and FOp.IsCancelled);

  Status := 0;
  Curl.GetInfo(FHandle, CURLINFO_RESPONSE_CODE, @Status);
  HttpStatus := Status;
  Time := -1;
  Curl.GetInfo(FHandle, CURLINFO_FILETIME_T, @Time);
  if Time > 0 then
    FileTime := Time;
  Len := -1;
  Curl.GetInfo(FHandle, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, @Len);
  ContentLength := Len;

  if Code = CURLE_OK then
    Exit(nrOk);
  if FOp <> nil then
    FOp.ErrorText := ErrorMessage(Code);
  if FCancelledByUs or ((FOp <> nil) and FOp.IsCancelled) then
    Exit(nrCancelled);
  if BodyTooLarge then
  begin
    if FOp <> nil then
      FOp.ErrorText := 'The file is too large';
    Exit(nrIO);
  end;
  if FHostKeyProblem <> 0 then
  begin
    if FOp <> nil then
      FOp.HostKey := FSeenHostKey;
    if FHostKeyProblem = 1 then
      Exit(nrHostKeyUnknown);
    Exit(nrHostKeyChanged);
  end;
  Result := MapCurlCode(Code, HttpStatus, FSession.Protocol, ErrorMessage(Code));
end;

{ mapping }

function HostKeyFingerprint(const AKey: TBytes): string;
var
  Hash: TBytes;
  Enc: TBase64Encoding;
  H: THashSHA2;
begin
  H := THashSHA2.Create(SHA256);
  H.Update(AKey);
  Hash := H.HashAsBytes;
  Enc := TBase64Encoding.Create(0);
  try
    Result := Enc.EncodeBytesToString(Hash);
  finally
    Enc.Free;
  end;
  while (Result <> '') and (Result[Length(Result)] = '=') do
    Delete(Result, Length(Result), 1);
end;

function MapHttpStatus(AStatus: Integer): TNetResult;
begin
  case AStatus of
    200..299: Result := nrOk;
    401: Result := nrAuthFailed;
    403: Result := nrAccessDenied;
    404, 410: Result := nrNotFound;
    405, 501: Result := nrNotSupported;
    409: Result := nrNotFound;
    412: Result := nrAlreadyExists;
    408, 504: Result := nrTimeout;
  else
    Result := nrIO;
  end;
end;

function MapCurlCode(ACode: CURLcode; AHttpStatus: Integer; ATransport: TNetProtocol;
  const AMessage: string): TNetResult;
var
  Low: string;
begin
  Low := LowerCase(AMessage);
  case ACode of
    CURLE_OK: Result := nrOk;
    CURLE_LOGIN_DENIED: Result := nrAuthFailed;
    CURLE_REMOTE_ACCESS_DENIED: Result := nrAccessDenied;
    CURLE_REMOTE_FILE_NOT_FOUND, CURLE_FTP_COULDNT_RETR_FILE, CURLE_FILE_COULDNT_READ_FILE:
      Result := nrNotFound;
    CURLE_REMOTE_FILE_EXISTS: Result := nrAlreadyExists;
    CURLE_OPERATION_TIMEDOUT: Result := nrTimeout;
    CURLE_PEER_FAILED_VERIFICATION, CURLE_SSL_CACERT_BADFILE, CURLE_SSL_CERTPROBLEM,
    CURLE_SSL_ISSUER_ERROR:
      Result := nrCertUntrusted;
    CURLE_UNSUPPORTED_PROTOCOL: Result := nrNoLibrary;
    CURLE_URL_MALFORMAT: Result := nrInvalid;
    CURLE_ABORTED_BY_CALLBACK: Result := nrCancelled;
    CURLE_HTTP_RETURNED_ERROR:
      begin
        Result := MapHttpStatus(AHttpStatus);
        if Result = nrOk then
          Result := nrIO;
      end;
    CURLE_QUOTE_ERROR, CURLE_FTP_COULDNT_USE_REST, CURLE_UPLOAD_FAILED:
      begin
        if (Pos('no such', Low) > 0) or (Pos('not found', Low) > 0) or (AHttpStatus = 550) and
           (Pos('permission', Low) = 0) and (Pos('denied', Low) = 0) then
          Result := nrNotFound
        else if (Pos('permission', Low) > 0) or (Pos('denied', Low) > 0) then
          Result := nrAccessDenied
        else if Pos('exist', Low) > 0 then
          Result := nrAlreadyExists
        else
          Result := nrIO;
      end;
    CURLE_SSH:
      begin
        if (Pos('no such', Low) > 0) or (Pos('not found', Low) > 0) then
          Result := nrNotFound
        else if (Pos('permission', Low) > 0) or (Pos('denied', Low) > 0) then
          Result := nrAccessDenied
        else if (Pos('authentication', Low) > 0) or (Pos('auth', Low) > 0) then
          Result := nrAuthFailed
        else
          Result := nrIO;
      end;
  else
    Result := nrIO;
  end;
end;

end.
