unit uNetTypes;

{ Types shared by the network plugin: a saved session (one remote server with
  how to log in), a remote directory entry, the outcome of an operation, and
  the address forms of the plugin.

  Addresses are written scheme://authority/path:
    net://Work/dir/a.txt   a saved session (its name is the authority)
    net:///                the list of saved sessions
    ftp://[user[:pass]@]host[:port]/dir   a direct address of a server
    s3://bucket/key        (the session holds the endpoint and the keys)
  A direct address is matched with a saved session of the same protocol, host
  and user; without one the address itself supplies the login. }

interface

uses
  System.SysUtils, System.Classes;

type
  TNetProtocol = (npFtp, npFtps, npSftp, npScp, npWebDav, npWebDavs, npS3);
  TNetAuth = (naPassword, naKey, naAgent, naAnonymous);

  TNetResult = (nrOk, nrNotFound, nrAccessDenied, nrAlreadyExists, nrNotSupported,
    nrIO, nrAuthFailed, nrCancelled, nrTimeout, nrHostKeyUnknown, nrHostKeyChanged,
    nrCertUntrusted, nrInvalid, nrNoLibrary);

  TNetSession = record
    Name: string;
    Protocol: TNetProtocol;
    Host: string;
    /// <summary>0 = the protocol's default port.</summary>
    Port: Integer;
    User: string;
    Auth: TNetAuth;
    /// <summary>The secret of the login: password, S3 secret key. Held in memory;
    /// uNetSessions stores it protected.</summary>
    Password: string;
    KeyFile: string;
    KeyPassphrase: string;
    /// <summary>Keep Password / KeyPassphrase in the settings (sealed); otherwise
    /// they are asked for once per run.</summary>
    SavePassword: Boolean;
    /// <summary>Folder shown when the session opens ("/" when empty).</summary>
    RootPath: string;
    /// <summary>curl proxy URL ("socks5h://host:1080", "http://host:3128"); '' = none.</summary>
    Proxy: string;
    /// <summary>Code page name of file names on the server (FTP); '' = UTF-8.</summary>
    Encoding: string;
    /// <summary>S3 only.</summary>
    Region: string;
    Endpoint: string;
    PathStyle: Boolean;
    /// <summary>FTP: passive mode (the default); implicit TLS on port 990.</summary>
    Passive: Boolean;
    ImplicitTls: Boolean;
    VerifyCert: Boolean;
    TimeoutSec: Integer;
    /// <summary>SSH host key the user trusted: base64 SHA-256 of the key.</summary>
    HostKeySha256: string;
  end;

  TNetEntry = record
    Name: string;
    IsDir: Boolean;
    IsLink: Boolean;
    Size: Int64;
    /// <summary>Seconds since 1970 (UTC); 0 = unknown.</summary>
    Modified: Int64;
    /// <summary>Permission bits; 0 = unknown.</summary>
    Mode: Cardinal;
  end;
  TNetEntries = TArray<TNetEntry>;

  /// <summary>One address split into its parts.</summary>
  TNetTarget = record
    Scheme: string;
    Authority: string;
    /// <summary>Always starts with '/'; '/' is the root.</summary>
    Path: string;
    function IsSessionList: Boolean;
    function IsDirect: Boolean;
  end;

  /// <summary>What an operation needs from, and gives back to, the caller: the
  /// cancel flag, a progress sink, the message to show with a failure.</summary>
  TNetOp = class
  public
    Cancelled: TFunc<Boolean>;
    /// <summary>done, total (0 = unknown), name of the file in flight.</summary>
    Progress: TProc<Int64, Int64, string>;
    ErrorText: string;
    /// <summary>For nrHostKeyUnknown / nrHostKeyChanged: SHA-256 (base64) of the
    /// key the server presented.</summary>
    HostKey: string;
    /// <summary>For a transfer of several files: the bytes done before the file in
    /// flight, and the size of the whole job (0 = report each file alone).</summary>
    Base: Int64;
    GrandTotal: Int64;
    function IsCancelled: Boolean;
    procedure Report(ADone, ATotal: Int64; const AName: string);
  end;

const
  cNetScheme = 'net';

function NetProtocolScheme(AProtocol: TNetProtocol): string;
function NetSchemeProtocol(const AScheme: string; out AProtocol: TNetProtocol): Boolean;
function NetProtocolCaption(AProtocol: TNetProtocol): string;
function NetDefaultPort(AProtocol: TNetProtocol; AImplicitTls: Boolean = False): Integer;
function NetEffectivePort(const ASession: TNetSession): Integer;
function DefaultNetSession: TNetSession;

function ParseNetUri(const AUri: string; out ATarget: TNetTarget): Boolean;
function MakeNetUri(const AScheme, AAuthority, APath: string): string;
/// <summary>Splits [user[:password]@]host[:port] (IPv6 hosts in brackets).</summary>
function ParseNetAuthority(const AAuthority: string; out AUser, APassword,
  AHost: string; out APort: Integer): Boolean;

function PosixJoin(const ADir, AName: string): string;
function PosixParent(const APath: string): string;
function PosixLastSegment(const APath: string): string;
/// <summary>Path with a leading '/', no trailing '/' (except the root), no '//'.</summary>
function PosixNormalize(const APath: string): string;

function UrlEncodePath(const APath: string): string;
function UrlEncodeComponent(const AText: string): string;
function UrlDecode(const AText: string): string;

/// <summary>AOp.IsCancelled that also accepts nil.</summary>
function NetCancelled(AOp: TNetOp): Boolean;

function UnixToNetTime(AValue: Int64): Int64;

implementation

function TNetTarget.IsSessionList: Boolean;
begin
  Result := (Authority = '') and (Path = '/');
end;

function TNetTarget.IsDirect: Boolean;
begin
  Result := Scheme <> cNetScheme;
end;

function TNetOp.IsCancelled: Boolean;
begin
  Result := Assigned(Cancelled) and Cancelled();
end;

procedure TNetOp.Report(ADone, ATotal: Int64; const AName: string);
begin
  if Assigned(Progress) then
    Progress(ADone, ATotal, AName);
end;

function NetProtocolScheme(AProtocol: TNetProtocol): string;
begin
  case AProtocol of
    npFtp: Result := 'ftp';
    npFtps: Result := 'ftps';
    npSftp: Result := 'nsftp';
    npScp: Result := 'scp';
    npWebDav: Result := 'dav';
    npWebDavs: Result := 'davs';
    npS3: Result := 's3';
  else
    Result := '';
  end;
end;

function NetSchemeProtocol(const AScheme: string; out AProtocol: TNetProtocol): Boolean;
var
  P: TNetProtocol;
begin
  for P := Low(TNetProtocol) to High(TNetProtocol) do
    if SameText(NetProtocolScheme(P), AScheme) then
    begin
      AProtocol := P;
      Exit(True);
    end;
  AProtocol := npFtp;
  Result := False;
end;

function NetProtocolCaption(AProtocol: TNetProtocol): string;
begin
  case AProtocol of
    npFtp: Result := 'FTP';
    npFtps: Result := 'FTPS';
    npSftp: Result := 'SFTP';
    npScp: Result := 'SCP';
    npWebDav: Result := 'WebDAV';
    npWebDavs: Result := 'WebDAV (HTTPS)';
    npS3: Result := 'S3';
  else
    Result := '';
  end;
end;

function NetDefaultPort(AProtocol: TNetProtocol; AImplicitTls: Boolean): Integer;
begin
  case AProtocol of
    npFtp: Result := 21;
    npFtps: if AImplicitTls then Result := 990 else Result := 21;
    npSftp, npScp: Result := 22;
    npWebDav: Result := 80;
    npWebDavs, npS3: Result := 443;
  else
    Result := 0;
  end;
end;

function NetEffectivePort(const ASession: TNetSession): Integer;
begin
  if ASession.Port > 0 then
    Result := ASession.Port
  else
    Result := NetDefaultPort(ASession.Protocol, ASession.ImplicitTls);
end;

function DefaultNetSession: TNetSession;
begin
  Result := Default(TNetSession);
  Result.Protocol := npFtp;
  Result.Auth := naPassword;
  Result.RootPath := '/';
  Result.Passive := True;
  Result.VerifyCert := True;
  Result.TimeoutSec := 30;
  Result.PathStyle := True;
end;

function ParseNetUri(const AUri: string; out ATarget: TNetTarget): Boolean;
var
  S, Rest: string;
  P, Slash: Integer;
  Proto: TNetProtocol;
begin
  ATarget := Default(TNetTarget);
  ATarget.Path := '/';
  S := Trim(AUri);
  P := Pos('://', S);
  if P < 2 then
    Exit(False);
  ATarget.Scheme := LowerCase(Copy(S, 1, P - 1));
  if (ATarget.Scheme <> cNetScheme) and not NetSchemeProtocol(ATarget.Scheme, Proto) then
    Exit(False);
  Rest := Copy(S, P + 3, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
    ATarget.Authority := Rest
  else
  begin
    ATarget.Authority := Copy(Rest, 1, Slash - 1);
    ATarget.Path := PosixNormalize(Copy(Rest, Slash, MaxInt));
  end;
  Result := True;
end;

function MakeNetUri(const AScheme, AAuthority, APath: string): string;
begin
  Result := LowerCase(AScheme) + '://' + AAuthority + PosixNormalize(APath);
end;

function ParseNetAuthority(const AAuthority: string; out AUser, APassword,
  AHost: string; out APort: Integer): Boolean;
var
  S, Cred, HostPort: string;
  At, Colon, Close: Integer;
begin
  AUser := '';
  APassword := '';
  AHost := '';
  APort := 0;
  S := AAuthority;
  At := LastDelimiter('@', S);
  if At > 0 then
  begin
    Cred := Copy(S, 1, At - 1);
    HostPort := Copy(S, At + 1, MaxInt);
    Colon := Pos(':', Cred);
    if Colon > 0 then
    begin
      AUser := UrlDecode(Copy(Cred, 1, Colon - 1));
      APassword := UrlDecode(Copy(Cred, Colon + 1, MaxInt));
    end
    else
      AUser := UrlDecode(Cred);
  end
  else
    HostPort := S;
  if (HostPort <> '') and (HostPort[1] = '[') then
  begin
    Close := Pos(']', HostPort);
    if Close = 0 then
      Exit(False);
    AHost := Copy(HostPort, 2, Close - 2);
    if (Close < Length(HostPort)) and (HostPort[Close + 1] = ':') then
      APort := StrToIntDef(Copy(HostPort, Close + 2, MaxInt), -1);
  end
  else
  begin
    Colon := LastDelimiter(':', HostPort);
    if Colon > 0 then
    begin
      AHost := Copy(HostPort, 1, Colon - 1);
      APort := StrToIntDef(Copy(HostPort, Colon + 1, MaxInt), -1);
    end
    else
      AHost := HostPort;
  end;
  Result := (AHost <> '') and (APort >= 0) and (APort <= 65535);
end;

function PosixNormalize(const APath: string): string;
var
  Parts: TArray<string>;
  Part: string;
begin
  Result := '';
  Parts := APath.Replace('\', '/').Split(['/']);
  for Part in Parts do
    if (Part <> '') and (Part <> '.') then
      Result := Result + '/' + Part;
  if Result = '' then
    Result := '/';
end;

function PosixJoin(const ADir, AName: string): string;
var
  Name: string;
begin
  Name := AName;
  while (Name <> '') and (Name[1] = '/') do
    Delete(Name, 1, 1);
  if Name = '' then
    Exit(PosixNormalize(ADir));
  if (ADir = '') or (ADir = '/') then
    Result := '/' + Name
  else
    Result := PosixNormalize(ADir) + '/' + Name;
end;

function PosixParent(const APath: string): string;
var
  P: string;
  Slash: Integer;
begin
  P := PosixNormalize(APath);
  if P = '/' then
    Exit('/');
  Slash := LastDelimiter('/', P);
  if Slash <= 1 then
    Result := '/'
  else
    Result := Copy(P, 1, Slash - 1);
end;

function PosixLastSegment(const APath: string): string;
var
  P: string;
begin
  P := PosixNormalize(APath);
  if P = '/' then
    Exit('');
  Result := Copy(P, LastDelimiter('/', P) + 1, MaxInt);
end;

function UrlEncodeBytes(const AText: string; AKeepSlash: Boolean): string;
const
  cHex: string = '0123456789ABCDEF';
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(AText);
  for B in Bytes do
    if ((B >= Ord('A')) and (B <= Ord('Z'))) or ((B >= Ord('a')) and (B <= Ord('z'))) or
       ((B >= Ord('0')) and (B <= Ord('9'))) or (B = Ord('-')) or (B = Ord('.')) or
       (B = Ord('_')) or (B = Ord('~')) or (AKeepSlash and (B = Ord('/'))) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + cHex[(B shr 4) + 1] + cHex[(B and 15) + 1];
end;

function UrlEncodePath(const APath: string): string;
begin
  Result := UrlEncodeBytes(APath, True);
end;

function UrlEncodeComponent(const AText: string): string;
begin
  Result := UrlEncodeBytes(AText, False);
end;

function UrlDecode(const AText: string): string;
var
  Bytes: TBytes;
  I, N: Integer;
  Hi, Lo: Integer;

  function HexVal(C: Char): Integer;
  begin
    case C of
      '0'..'9': Result := Ord(C) - Ord('0');
      'a'..'f': Result := Ord(C) - Ord('a') + 10;
      'A'..'F': Result := Ord(C) - Ord('A') + 10;
    else
      Result := -1;
    end;
  end;

  procedure Put(AValue: Byte);
  begin
    if N >= Length(Bytes) then
      SetLength(Bytes, Length(Bytes) * 2 + 16);
    Bytes[N] := AValue;
    Inc(N);
  end;

var
  Utf8: TBytes;
  K: Integer;
begin
  N := 0;
  SetLength(Bytes, Length(AText) * 3 + 16);
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '%') and (I + 2 <= Length(AText)) then
    begin
      Hi := HexVal(AText[I + 1]);
      Lo := HexVal(AText[I + 2]);
      if (Hi >= 0) and (Lo >= 0) then
      begin
        Put(Hi * 16 + Lo);
        Inc(I, 3);
        Continue;
      end;
    end;
    Utf8 := TEncoding.UTF8.GetBytes(AText[I]);
    if (Ord(AText[I]) >= $D800) and (Ord(AText[I]) <= $DBFF) and (I < Length(AText)) then
    begin
      Utf8 := TEncoding.UTF8.GetBytes(Copy(AText, I, 2));
      Inc(I);
    end;
    for K := 0 to High(Utf8) do
      Put(Utf8[K]);
    Inc(I);
  end;
  Result := TEncoding.UTF8.GetString(Bytes, 0, N);
end;

function NetCancelled(AOp: TNetOp): Boolean;
begin
  Result := (AOp <> nil) and AOp.IsCancelled;
end;

function UnixToNetTime(AValue: Int64): Int64;
begin
  if AValue < 0 then
    Result := 0
  else
    Result := AValue;
end;

end.
