unit uNetManager;

{ Turns an address into a session and a live client, and keeps the login
  going: a password that is not saved is asked for once, a rejected one is
  asked again, an unknown or changed SSH host key and an untrusted certificate
  are put to the user. The questions go through INetPrompter, which the plugin
  implements with dialogs (and the tests with a script).

  Execute is the one entry point operations use; it may block while the
  user answers, so it is called from the worker threads of the VFS, never
  from the main thread. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uNetTypes, uNetSessions, uNetClient;

type
  INetPrompter = interface
    ['{7E9C0A52-33D1-4D7A-A1B2-5C8E6F4A9D01}']
    /// <summary>Asks for the secret of ASession. AKeyPassphrase: the secret is
    /// the passphrase of the key file. ARetry: the last answer is refused. False
    /// when the user cancelled. Called on a worker thread; may block.</summary>
    function AskSecret(const ASession: TNetSession; AKeyPassphrase, ARetry: Boolean;
      AOp: TNetOp; out ASecret: string; out ASave: Boolean): Boolean;
    /// <summary>The server's SSH host key is not trusted yet (AChanged = False)
    /// or differs from the trusted one (AChanged = True). True = trust it.</summary>
    function TrustHostKey(const ASession: TNetSession; const AFingerprint: string;
      AChanged: Boolean; AOp: TNetOp): Boolean;
    /// <summary>The server's TLS certificate is not trusted. True = go on.</summary>
    function TrustCertificate(const ASession: TNetSession; const AMessage: string;
      AOp: TNetOp): Boolean;
  end;

  TNetAction = reference to function(AClient: TNetClient; const APath: string): TNetResult;

  TNetManager = class
  private
    FLock: TCriticalSection;
    FPromptLock: TCriticalSection;
    FStore: TNetSessionStore;
    FLive: TDictionary<string, TNetSession>;
    FClients: TDictionary<string, TNetClient>;
    FPrompter: INetPrompter;
    FOnStoreChanged: TProc;
    function LiveKey(const AName: string): string;
    function ClientKey(const S: TNetSession): string;
    function GetLive(const ASession: TNetSession): TNetSession;
    procedure PutLive(const ASession: TNetSession; ASaveToStore: Boolean);
    function ClientFor(const ASession: TNetSession): TNetClient;
    procedure DropClient(const AName: string);
    function NeedsSecret(const S: TNetSession): Boolean;
    function EnsureSecret(var S: TNetSession; ARetry: Boolean; AOp: TNetOp): TNetResult;
    procedure Changed;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetPrompter(const APrompter: INetPrompter);
    /// <summary>Called (any thread) after the saved sessions changed and must be stored.</summary>
    property OnStoreChanged: TProc read FOnStoreChanged write FOnStoreChanged;
    procedure LoadSessions(const AJson: string);
    function SessionsJson: string;
    function SessionCount: Integer;
    function SessionAt(AIndex: Integer): TNetSession;
    function FindSession(const AName: string; out ASession: TNetSession): Boolean;
    /// <summary>The saved session of the same protocol, host, port and user.</summary>
    function FindServerSession(AProtocol: TNetProtocol; const AHost: string; APort: Integer;
      const AUser: string; out ASession: TNetSession): Boolean;
    function AddSession(const ASession: TNetSession): Boolean;
    function UpdateSession(const AOldName: string; const ASession: TNetSession): Boolean;
    function DeleteSession(const AName: string): Boolean;
    function UniqueSessionName(const ABase: string): string;
    /// <summary>Forgets the connections (all, or those of one session); the
    /// next operation connects again.</summary>
    procedure Disconnect(const AName: string = '');
    /// <summary>The session an address belongs to and the path on the server.
    /// nrNotFound: no saved session of that name; nrInvalid: not our address.</summary>
    function Resolve(const AUri: string; out ASession: TNetSession; out APath: string): TNetResult;
    /// <summary>Runs AAction on the client of the address with the login
    /// handled; see the unit comment.</summary>
    function Execute(const AUri: string; AOp: TNetOp; const AAction: TNetAction): TNetResult;
  end;

implementation

uses
  System.StrUtils, uNetCurlApi;

const
  cMaxAttempts = 5;

// The wording libcurl uses when a connection it kept is found dead.
function LooksLikeConnectionLoss(const AText: string): Boolean;
var
  Low: string;
begin
  Low := LowerCase(AText);
  Result := (Pos('connection died', Low) > 0) or (Pos('connection reset', Low) > 0) or
    (Pos('broken pipe', Low) > 0) or (Pos('send failure', Low) > 0) or
    (Pos('recv failure', Low) > 0) or (Pos('closed the connection', Low) > 0) or
    (Pos('connection was aborted', Low) > 0) or (Pos('unexpected eof', Low) > 0) or
    (Pos('server closed', Low) > 0);
end;

constructor TNetManager.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPromptLock := TCriticalSection.Create;
  FStore := TNetSessionStore.Create;
  FLive := TDictionary<string, TNetSession>.Create;
  FClients := TDictionary<string, TNetClient>.Create;
end;

destructor TNetManager.Destroy;
var
  C: TNetClient;
begin
  for C in FClients.Values do
    C.Retire;
  FClients.Free;
  FLive.Free;
  FStore.Free;
  FPromptLock.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TNetManager.SetPrompter(const APrompter: INetPrompter);
begin
  FPrompter := APrompter;
end;

procedure TNetManager.Changed;
begin
  if Assigned(FOnStoreChanged) then
    FOnStoreChanged();
end;

function TNetManager.LiveKey(const AName: string): string;
begin
  Result := LowerCase(AName);
end;

function TNetManager.ClientKey(const S: TNetSession): string;
begin
  // Anything that changes how the server is reached makes another client.
  Result := Format('%s|%d|%s|%d|%s|%d|%s|%s|%s|%d|%s|%s|%s|%d|%d|%d|%s',
    [LowerCase(S.Name), Ord(S.Protocol), S.Host, S.Port, S.User, Ord(S.Auth), S.Password,
     S.KeyFile, S.KeyPassphrase, Ord(S.VerifyCert), S.Proxy, S.Encoding, S.HostKeySha256,
     Ord(S.Passive), Ord(S.ImplicitTls), S.TimeoutSec, S.Region + '/' + S.Endpoint]);
end;

function TNetManager.GetLive(const ASession: TNetSession): TNetSession;
begin
  FLock.Enter;
  try
    if not FLive.TryGetValue(LiveKey(ASession.Name), Result) then
    begin
      Result := ASession;
      FLive.Add(LiveKey(ASession.Name), Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetManager.PutLive(const ASession: TNetSession; ASaveToStore: Boolean);
var
  Idx: Integer;
  Stored: TNetSession;
begin
  FLock.Enter;
  try
    FLive.AddOrSetValue(LiveKey(ASession.Name), ASession);
    if ASaveToStore then
    begin
      Idx := FStore.IndexOfName(ASession.Name);
      if Idx >= 0 then
      begin
        Stored := FStore[Idx];
        Stored.HostKeySha256 := ASession.HostKeySha256;
        if ASession.SavePassword then
        begin
          Stored.Password := ASession.Password;
          Stored.KeyPassphrase := ASession.KeyPassphrase;
        end;
        Stored.SavePassword := ASession.SavePassword;
        FStore.Update(Stored.Name, Stored);
      end
      else
        ASaveToStore := False;
    end;
  finally
    FLock.Leave;
  end;
  if ASaveToStore then
    Changed;
end;

function TNetManager.ClientFor(const ASession: TNetSession): TNetClient;
var
  Key: string;
  Old: TNetClient;
begin
  Key := LiveKey(ASession.Name);
  FLock.Enter;
  try
    if FClients.TryGetValue(Key, Result) then
    begin
      if Result.Tag = ClientKey(ASession) then
        Exit(Result.Acquire);
      Old := Result;
      FClients.Remove(Key);
      Old.Retire;
    end;
    Result := CreateNetClient(ASession);
    if Result <> nil then
    begin
      Result.Tag := ClientKey(ASession);
      FClients.Add(Key, Result);
      Result.Acquire;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetManager.DropClient(const AName: string);
var
  C: TNetClient;
begin
  FLock.Enter;
  try
    if FClients.TryGetValue(LiveKey(AName), C) then
    begin
      FClients.Remove(LiveKey(AName));
      C.Retire;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetManager.Disconnect(const AName: string);
var
  C: TNetClient;
begin
  FLock.Enter;
  try
    if AName = '' then
    begin
      for C in FClients.Values do
        C.Retire;
      FClients.Clear;
    end
    else if FClients.TryGetValue(LiveKey(AName), C) then
    begin
      FClients.Remove(LiveKey(AName));
      C.Retire;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TNetManager.LoadSessions(const AJson: string);
begin
  FLock.Enter;
  try
    FStore.Load(AJson);
    FLive.Clear;
  finally
    FLock.Leave;
  end;
  Disconnect;
end;

function TNetManager.SessionsJson: string;
begin
  FLock.Enter;
  try
    Result := FStore.ToJson;
  finally
    FLock.Leave;
  end;
end;

function TNetManager.SessionCount: Integer;
begin
  FLock.Enter;
  try
    Result := FStore.Count;
  finally
    FLock.Leave;
  end;
end;

function TNetManager.SessionAt(AIndex: Integer): TNetSession;
begin
  FLock.Enter;
  try
    Result := FStore[AIndex];
  finally
    FLock.Leave;
  end;
end;

function TNetManager.FindSession(const AName: string; out ASession: TNetSession): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.Find(AName, ASession);
  finally
    FLock.Leave;
  end;
end;

function TNetManager.FindServerSession(AProtocol: TNetProtocol; const AHost: string;
  APort: Integer; const AUser: string; out ASession: TNetSession): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.FindForServer(AProtocol, AHost, APort, AUser, ASession);
  finally
    FLock.Leave;
  end;
end;

function TNetManager.AddSession(const ASession: TNetSession): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.Add(ASession);
  finally
    FLock.Leave;
  end;
  if Result then
    Changed;
end;

function TNetManager.UpdateSession(const AOldName: string; const ASession: TNetSession): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.Update(AOldName, ASession);
    if Result then
    begin
      FLive.Remove(LiveKey(AOldName));
      FLive.Remove(LiveKey(ASession.Name));
    end;
  finally
    FLock.Leave;
  end;
  if Result then
  begin
    DropClient(AOldName);
    DropClient(ASession.Name);
    Changed;
  end;
end;

function TNetManager.DeleteSession(const AName: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.Delete(AName);
    if Result then
      FLive.Remove(LiveKey(AName));
  finally
    FLock.Leave;
  end;
  if Result then
  begin
    DropClient(AName);
    Changed;
  end;
end;

function TNetManager.UniqueSessionName(const ABase: string): string;
begin
  FLock.Enter;
  try
    Result := FStore.UniqueName(ABase);
  finally
    FLock.Leave;
  end;
end;

function TNetManager.Resolve(const AUri: string; out ASession: TNetSession;
  out APath: string): TNetResult;
var
  T: TNetTarget;
  Proto: TNetProtocol;
  User, Pass, Host: string;
  Port: Integer;
begin
  ASession := DefaultNetSession;
  APath := '/';
  if not ParseNetUri(AUri, T) then
    Exit(nrInvalid);
  APath := T.Path;
  if not T.IsDirect then
  begin
    if T.Authority = '' then
      Exit(nrInvalid);
    if not FindSession(T.Authority, ASession) then
      Exit(nrNotFound);
    ASession := GetLive(ASession);
    Exit(nrOk);
  end;
  // A direct address: the login of a saved session for that server, or the
  // address itself.
  if T.Authority = '' then
    Exit(nrInvalid);
  NetSchemeProtocol(T.Scheme, Proto);
  if not ParseNetAuthority(T.Authority, User, Pass, Host, Port) then
    Exit(nrInvalid);
  FLock.Enter;
  try
    if FStore.FindForServer(Proto, Host, Port, User, ASession) then
    begin
      // keep the name: the live copy holds what the user entered during this run
    end
    else
    begin
      ASession := DefaultNetSession;
      ASession.Name := T.Authority;
      ASession.Protocol := Proto;
      ASession.Host := Host;
      ASession.Port := Port;
      ASession.User := User;
      ASession.Password := Pass;
      if (User = '') or SameText(User, 'anonymous') then
      begin
        if Proto in [npFtp, npFtps] then
          ASession.Auth := naAnonymous;
      end;
      ASession.RootPath := '/';
    end;
  finally
    FLock.Leave;
  end;
  ASession := GetLive(ASession);
  Result := nrOk;
end;

function TNetManager.NeedsSecret(const S: TNetSession): Boolean;
begin
  Result := (S.Auth = naPassword) and (S.Password = '') and (S.User <> '');
end;

function TNetManager.EnsureSecret(var S: TNetSession; ARetry: Boolean; AOp: TNetOp): TNetResult;
var
  Secret: string;
  Save: Boolean;
  Current: TNetSession;
  AskPass: Boolean;
begin
  Result := nrOk;
  AskPass := ARetry or NeedsSecret(S);
  if not AskPass then
    Exit;
  if FPrompter = nil then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'A password is needed';
    Exit(nrAuthFailed);
  end;
  FPromptLock.Enter;
  try
    // Another operation may have asked while this one waited for the lock.
    Current := GetLive(S);
    if (not ARetry) and not NeedsSecret(Current) then
    begin
      S := Current;
      Exit(nrOk);
    end;
    if ARetry and (Current.Password <> S.Password) then
    begin
      S := Current;
      Exit(nrOk);
    end;
    if not FPrompter.AskSecret(S, S.Auth = naKey, ARetry, AOp, Secret, Save) then
    begin
      if AOp <> nil then
        AOp.ErrorText := 'Cancelled';
      Exit(nrCancelled);
    end;
    if S.Auth = naKey then
      S.KeyPassphrase := Secret
    else
      S.Password := Secret;
    S.SavePassword := Save;
    PutLive(S, True);
  finally
    FPromptLock.Leave;
  end;
end;

function TNetManager.Execute(const AUri: string; AOp: TNetOp; const AAction: TNetAction): TNetResult;
var
  S: TNetSession;
  Path: string;
  Client: TNetClient;
  Attempt: Integer;
  Retry: Boolean;
  Retried: Boolean;
  R: TNetResult;
  PersistKey: Boolean;
begin
  Retried := False;
  R := Resolve(AUri, S, Path);
  if R <> nrOk then
  begin
    if (R = nrNotFound) and (AOp <> nil) then
      AOp.ErrorText := 'There is no saved connection with this name';
    Exit(R);
  end;
  if not CurlLoaded then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'libcurl was not found next to the plugin';
    Exit(nrNoLibrary);
  end;
  Retry := False;
  for Attempt := 1 to cMaxAttempts do
  begin
    if NetCancelled(AOp) then
      Exit(nrCancelled);
    R := EnsureSecret(S, Retry, AOp);
    if R <> nrOk then
      Exit(R);
    Retry := False;
    Client := ClientFor(S);
    if Client = nil then
      Exit(nrNotSupported);
    if AOp <> nil then
    begin
      AOp.ErrorText := '';
      AOp.HostKey := '';
    end;
    try
      R := AAction(Client, Path);
    finally
      Client.Release;
    end;
    // A connection the server closed while it sat idle: connect again once.
    if (R = nrIO) and (not Retried) and (AOp <> nil) and LooksLikeConnectionLoss(AOp.ErrorText) then
    begin
      Retried := True;
      DropClient(S.Name);
      Continue;
    end;
    case R of
      nrAuthFailed:
        begin
          if not (S.Auth in [naPassword, naKey]) or (FPrompter = nil) then
            Exit(R);
          // A rejected login: ask again (for the passphrase of the key file with key logins).
          Retry := True;
          DropClient(S.Name);
          Continue;
        end;
      nrHostKeyUnknown, nrHostKeyChanged:
        begin
          if (FPrompter = nil) or (AOp = nil) or (AOp.HostKey = '') then
            Exit(R);
          if not FPrompter.TrustHostKey(S, AOp.HostKey, R = nrHostKeyChanged, AOp) then
            Exit(R);
          S.HostKeySha256 := AOp.HostKey;
          PersistKey := True;
          PutLive(S, PersistKey);
          DropClient(S.Name);
          Continue;
        end;
      nrCertUntrusted:
        begin
          if (FPrompter = nil) or not S.VerifyCert then
            Exit(R);
          if not FPrompter.TrustCertificate(S, IfThen(AOp <> nil, AOp.ErrorText, ''), AOp) then
            Exit(R);
          S.VerifyCert := False;
          PutLive(S, False);
          DropClient(S.Name);
          Continue;
        end;
    else
      Exit(R);
    end;
  end;
  Result := R;
end;

end.
