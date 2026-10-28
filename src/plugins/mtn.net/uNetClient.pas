unit uNetClient;

{ A connection to one server: the operations the plugin needs on a remote
  file system (list, stat, download, upload, delete, make folder, rename, set
  permissions), implemented per protocol on top of libcurl. FTP/FTPS and
  SFTP/SCP live here; WebDAV and S3 are in uNetClientHttp.pas.

  A client is shared by every operation on its session and is safe to call from
  several threads at once: each call borrows a pooled handle (uNetCurl.pas).
  Paths are '/'-separated and absolute on the server; names reach the wire in
  the session's code page. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs,
  uNetTypes, uNetCurl, uNetCurlApi, uNetListParsers;

type
  TNetClient = class
  private
    type
      TCachedList = record
        Tick: UInt64;
        Entries: TNetEntries;
      end;
    var
      FCacheLock: TCriticalSection;
      FCache: TDictionary<string, TCachedList>;
  protected
    FSession: TNetSession;
    FPool: TCurlPool;
    FTag: string;
    FRefs: Integer;
    FRetired: Boolean;
    /// <summary>Code page of names on the wire.</summary>
    function WireEncoding: TEncoding;
    function WireBytes(const AText: string): TBytes;
    function DecodeWire(const ABytes: TBytes): string;
    function EncodePath(const APath: string): string;
    /// <summary>[user@]host:port as it goes into a URL.</summary>
    function HostPart: string;
    /// <summary>A call for AUrl with the session's login applied; Start failed
    /// shows up as the result of Perform.</summary>
    function NewCall(AOp: TNetOp; const AUrl: string): TCurlCall;
    procedure Configure(ACall: TCurlCall); virtual;
    function ItemUrl(const APath: string; AIsDir: Boolean): string; virtual; abstract;
    /// <summary>The URL file contents are transferred through (SCP uses its own).</summary>
    function TransferUrl(const APath: string): string; virtual;
    function ListRaw(const APath: string; AOp: TNetOp;
      out AEntries: TNetEntries): TNetResult; virtual; abstract;
    procedure InvalidateCache;
    function SafeName(const APath: string; AOp: TNetOp): Boolean;
    function IsHttpLike: Boolean; virtual;
    /// <summary>Settles the result of a finished call (HTTP status of
    /// HTTP-like protocols included).</summary>
    function Settle(ACall: TCurlCall; AResult: TNetResult; AOp: TNetOp): TNetResult; virtual;
  public
    constructor Create(const ASession: TNetSession); virtual;
    destructor Destroy; override;
    /// <summary>Drops pooled connections; the client keeps working afterwards.</summary>
    procedure Disconnect;
    /// <summary>An operation about to use the client takes a hold on it (returns Self)...</summary>
    function Acquire: TNetClient;
    /// <summary>...and lets go when done; a retired client is freed by the last one to let go.</summary>
    procedure Release;
    /// <summary>Takes the client out of service: freed now when nobody holds it,
    /// otherwise by the last Release.</summary>
    procedure Retire;
    function ListDir(const APath: string; AOp: TNetOp; out AEntries: TNetEntries): TNetResult;
    function Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult; virtual;
    /// <summary>AKnownSize >= 0 spares the lookup of the size (the caller listed the folder).</summary>
    function Download(const ARemote, ALocal: string; AOp: TNetOp;
      AKeepTime: Boolean; AKnownSize: Int64 = -1): TNetResult; virtual;
    function Upload(const ALocal, ARemote: string; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; virtual;
    function ReadBytes(const ARemote: string; AMaxBytes: Int64; AOp: TNetOp;
      out AData: TBytes): TNetResult; virtual;
    function WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; virtual;
    function RemoveFile(const APath: string; AOp: TNetOp): TNetResult; virtual; abstract;
    function RemoveDir(const APath: string; AOp: TNetOp): TNetResult; virtual; abstract;
    function MakeDir(const APath: string; AOp: TNetOp): TNetResult; virtual; abstract;
    function Rename(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; virtual; abstract;
    function SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult; virtual;
    function FreeSpace(const APath: string; AOp: TNetOp;
      out AFree, ATotal: Int64): TNetResult; virtual;
    /// <summary>Copies an item inside the server without moving its data through
    /// through the client; nrNotSupported when the protocol cannot.</summary>
    function ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; virtual;
    /// <summary>Creates AFolder and the missing folders above it.</summary>
    function MakeDirs(const AFolder: string; AOp: TNetOp): TNetResult;
    /// <summary>Removes a file or a folder with everything in it.</summary>
    function RemoveTree(const APath: string; AIsDir: Boolean; AOp: TNetOp): TNetResult;
    /// <summary>Total size and item count of a tree.</summary>
    function TreeSize(const APath: string; AOp: TNetOp; out ABytes: Int64;
      out AFiles: Integer): TNetResult;
    property Session: TNetSession read FSession;
    /// <summary>Free for the owner (the manager keeps the settings the client is made for).</summary>
    property Tag: string read FTag write FTag;
  end;

  TFtpClient = class(TNetClient)
  private
    FMlsd: Integer; // 0 unknown, 1 supported, 2 not supported
    function RunQuote(const ACommands: array of string; const AParentPath: string;
      AOp: TNetOp): TNetResult;
  protected
    procedure Configure(ACall: TCurlCall); override;
    function ItemUrl(const APath: string; AIsDir: Boolean): string; override;
    function ListRaw(const APath: string; AOp: TNetOp;
      out AEntries: TNetEntries): TNetResult; override;
  public
    function Upload(const ALocal, ARemote: string; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; override;
    function WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; override;
    function RemoveFile(const APath: string; AOp: TNetOp): TNetResult; override;
    function RemoveDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function MakeDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function Rename(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
    function SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult; override;
  end;

  TSftpClient = class(TNetClient)
  private
    function RunQuote(const ACommands: array of string; AOp: TNetOp): TNetResult;
    function Quoted(const APath: string): string;
  protected
    procedure Configure(ACall: TCurlCall); override;
    function ItemUrl(const APath: string; AIsDir: Boolean): string; override;
    function TransferUrl(const APath: string): string; override;
    function ListRaw(const APath: string; AOp: TNetOp;
      out AEntries: TNetEntries): TNetResult; override;
  public
    function RemoveFile(const APath: string; AOp: TNetOp): TNetResult; override;
    function RemoveDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function MakeDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function Rename(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
    function SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult; override;
  end;

/// <summary>The client for ASession's protocol.</summary>
function CreateNetClient(const ASession: TNetSession): TNetClient;

/// <summary>A file that exists and is empty, for libcurl's SSH host check.</summary>
function SshKnownHostsStub: string;

implementation

uses
  System.IOUtils, System.DateUtils, uNetClientHttp;

const
  cListCacheMs = 2000;
  cMaxParallel = 3;

var
  GKnownHostsStub: string;

function SshKnownHostsStub: string;
begin
  if (GKnownHostsStub = '') or not FileExists(GKnownHostsStub) then
  begin
    GKnownHostsStub := TPath.Combine(TPath.GetTempPath, 'mtn2-net-known-hosts');
    try
      if not FileExists(GKnownHostsStub) then
        TFile.WriteAllBytes(GKnownHostsStub, nil);
    except
      // libcurl reports the missing file; nothing more to do here.
    end;
  end;
  Result := GKnownHostsStub;
end;

function CreateNetClient(const ASession: TNetSession): TNetClient;
begin
  case ASession.Protocol of
    npFtp, npFtps: Result := TFtpClient.Create(ASession);
    npSftp, npScp: Result := TSftpClient.Create(ASession);
    npWebDav, npWebDavs: Result := TWebDavClient.Create(ASession);
    npS3: Result := TS3Client.Create(ASession);
  else
    Result := nil;
  end;
end;

{ TNetClient }

constructor TNetClient.Create(const ASession: TNetSession);
begin
  inherited Create;
  FSession := ASession;
  if FSession.TimeoutSec < 5 then
    FSession.TimeoutSec := 30;
  FPool := TCurlPool.Create(cMaxParallel);
  FCacheLock := TCriticalSection.Create;
  FCache := TDictionary<string, TCachedList>.Create;
end;

destructor TNetClient.Destroy;
begin
  FPool.Free;
  FCache.Free;
  FCacheLock.Free;
  inherited Destroy;
end;

procedure TNetClient.Disconnect;
begin
  FPool.Close;
end;

function TNetClient.Acquire: TNetClient;
begin
  TInterlocked.Increment(FRefs);
  Result := Self;
end;

procedure TNetClient.Release;
begin
  if (TInterlocked.Decrement(FRefs) = 0) and FRetired then
    Free;
end;

procedure TNetClient.Retire;
begin
  FRetired := True;
  if TInterlocked.CompareExchange(FRefs, 0, 0) = 0 then
    Free;
end;

function TNetClient.WireEncoding: TEncoding;
begin
  Result := TEncoding.UTF8;
  if (FSession.Encoding <> '') and not SameText(FSession.Encoding, 'utf-8') then
    try
      Result := TEncoding.GetEncoding(FSession.Encoding);
    except
      Result := TEncoding.UTF8;
    end;
end;

function TNetClient.WireBytes(const AText: string): TBytes;
var
  Enc: TEncoding;
begin
  Enc := WireEncoding;
  try
    Result := Enc.GetBytes(AText);
  finally
    if not TEncoding.IsStandardEncoding(Enc) then
      Enc.Free;
  end;
end;

function TNetClient.DecodeWire(const ABytes: TBytes): string;
var
  Enc: TEncoding;
begin
  Enc := WireEncoding;
  try
    try
      Result := Enc.GetString(ABytes);
    except
      Result := TEncoding.ANSI.GetString(ABytes);
    end;
  finally
    if not TEncoding.IsStandardEncoding(Enc) then
      Enc.Free;
  end;
end;

function TNetClient.EncodePath(const APath: string): string;
const
  cHex: string = '0123456789ABCDEF';
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  Bytes := WireBytes(APath);
  for B in Bytes do
    if ((B >= Ord('A')) and (B <= Ord('Z'))) or ((B >= Ord('a')) and (B <= Ord('z'))) or
       ((B >= Ord('0')) and (B <= Ord('9'))) or (B = Ord('-')) or (B = Ord('.')) or
       (B = Ord('_')) or (B = Ord('~')) or (B = Ord('/')) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + cHex[(B shr 4) + 1] + cHex[(B and 15) + 1];
end;

function TNetClient.HostPart: string;
begin
  if Pos(':', FSession.Host) > 0 then
    Result := '[' + FSession.Host + ']'
  else
    Result := FSession.Host;
  if FSession.Port > 0 then
    Result := Result + ':' + IntToStr(FSession.Port);
end;

function TNetClient.IsHttpLike: Boolean;
begin
  Result := False;
end;

function TNetClient.NewCall(AOp: TNetOp; const AUrl: string): TCurlCall;
begin
  Result := TCurlCall.Create(FPool, FSession, AOp);
  if Result.Start(AUrl) then
    Configure(Result);
end;

procedure TNetClient.Configure(ACall: TCurlCall);
begin
end;

function TNetClient.TransferUrl(const APath: string): string;
begin
  Result := ItemUrl(APath, False);
end;

procedure TNetClient.InvalidateCache;
begin
  FCacheLock.Enter;
  try
    FCache.Clear;
  finally
    FCacheLock.Leave;
  end;
end;

function TNetClient.SafeName(const APath: string; AOp: TNetOp): Boolean;
var
  C: Char;
begin
  // A control character in a name would end a protocol command and start another.
  for C in APath do
    if C < ' ' then
    begin
      if AOp <> nil then
        AOp.ErrorText := 'The name contains a control character';
      Exit(False);
    end;
  Result := True;
end;

function TNetClient.Settle(ACall: TCurlCall; AResult: TNetResult; AOp: TNetOp): TNetResult;
begin
  Result := AResult;
  if (Result <> nrOk) or not IsHttpLike then
    Exit;
  if ACall.HttpStatus >= 400 then
  begin
    Result := MapHttpStatus(ACall.HttpStatus);
    if Result = nrOk then
      Result := nrIO;
    if (AOp <> nil) and (AOp.ErrorText = '') then
      AOp.ErrorText := 'HTTP ' + IntToStr(ACall.HttpStatus);
  end;
end;

function TNetClient.ListDir(const APath: string; AOp: TNetOp;
  out AEntries: TNetEntries): TNetResult;
var
  Key: string;
  Item: TCachedList;
begin
  SetLength(AEntries, 0);
  if not SafeName(APath, AOp) then
    Exit(nrInvalid);
  Key := PosixNormalize(APath);
  FCacheLock.Enter;
  try
    if FCache.TryGetValue(Key, Item) and (TThread.GetTickCount64 - Item.Tick < cListCacheMs) then
    begin
      AEntries := Copy(Item.Entries);
      Exit(nrOk);
    end;
  finally
    FCacheLock.Leave;
  end;
  Result := ListRaw(Key, AOp, AEntries);
  if Result = nrOk then
  begin
    Item.Tick := TThread.GetTickCount64;
    Item.Entries := Copy(AEntries);
    FCacheLock.Enter;
    try
      FCache.AddOrSetValue(Key, Item);
    finally
      FCacheLock.Leave;
    end;
  end;
end;

function TNetClient.Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult;
var
  Items: TNetEntries;
  E: TNetEntry;
  Name: string;
begin
  AEntry := Default(TNetEntry);
  if PosixNormalize(APath) = '/' then
  begin
    AEntry.IsDir := True;
    Exit(nrOk);
  end;
  Name := PosixLastSegment(APath);
  Result := ListDir(PosixParent(APath), AOp, Items);
  if Result <> nrOk then
    Exit;
  for E in Items do
    if E.Name = Name then
    begin
      AEntry := E;
      Exit(nrOk);
    end;
  Result := nrNotFound;
end;

function PlaceDownloadedFile(const APart, ADest: string; out AError: string): Boolean;
var
  Hold: string;
  N: Integer;
begin
  AError := '';
  if not FileExists(ADest) then
  begin
    TFile.Move(APart, ADest);
    Exit(True);
  end;
  // Move the current file aside and put it back if the new one cannot take
  // the name. Deleting it first loses it when that move fails.
  Hold := ADest + '.mtnhold';
  N := 0;
  while FileExists(Hold) do
  begin
    Inc(N);
    if N > 1000 then
    begin
      AError := 'Cannot make room to replace the destination';
      Exit(False);
    end;
    Hold := ADest + '.mtnhold' + IntToStr(N);
  end;
  TFile.Move(ADest, Hold);
  try
    TFile.Move(APart, ADest);
  except
    on E: Exception do
    begin
      AError := E.Message;
      try
        if not FileExists(ADest) then
          TFile.Move(Hold, ADest);
      except
        on E2: Exception do
          AError := AError + '; restore failed: ' + E2.Message;
      end;
      Exit(False);
    end;
  end;
  TFile.Delete(Hold);
  Result := True;
end;

function TNetClient.Download(const ARemote, ALocal: string; AOp: TNetOp;
  AKeepTime: Boolean; AKnownSize: Int64): TNetResult;
var
  Part, PlaceError: string;
  Stream: TFileStream;
  Call: TCurlCall;
  Total: Int64;
  Entry: TNetEntry;
begin
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  Part := ALocal + '.mtnpart';
  try
    ForceDirectories(ExtractFilePath(ALocal));
    Stream := TFileStream.Create(Part, fmCreate);
  except
    on E: Exception do
    begin
      if AOp <> nil then
        AOp.ErrorText := E.Message;
      Exit(nrAccessDenied);
    end;
  end;
  Total := AKnownSize;
  Entry := Default(TNetEntry);
  if (Total < 0) and (Stat(ARemote, nil, Entry) = nrOk) then
    Total := Entry.Size;
  try
    Call := NewCall(AOp, TransferUrl(ARemote));
    try
      Call.Body := Stream;
      Call.ProgressName := PosixLastSegment(ARemote);
      if Total > 0 then
        Call.ProgressTotal := Total;
      if IsHttpLike then
        Call.SetLong(CURLOPT_FAILONERROR, 1);
      Result := Settle(Call, Call.Perform, AOp);
      if (Result = nrNotFound) and (Call.HttpStatus = 0) and (AOp <> nil) and
         (AOp.ErrorText = '') then
        AOp.ErrorText := 'Not found';
      if (Result = nrOk) and AKeepTime and (Call.FileTime > 0) then
        Entry.Modified := Call.FileTime;
    finally
      Call.Free;
    end;
  finally
    Stream.Free;
  end;
  if Result = nrOk then
  begin
    try
      if not PlaceDownloadedFile(Part, ALocal, PlaceError) then
      begin
        if AOp <> nil then
          AOp.ErrorText := PlaceError;
        Result := nrAccessDenied;
      end
      else if AKeepTime and (Entry.Modified > 0) then
        TFile.SetLastWriteTimeUtc(ALocal, UnixToDateTime(Entry.Modified, True));
    except
      on E: Exception do
      begin
        if AOp <> nil then
          AOp.ErrorText := E.Message;
        Result := nrAccessDenied;
      end;
    end;
  end;
  if Result <> nrOk then
    try
      if FileExists(Part) then
        TFile.Delete(Part);
    except
      // A leftover partial file is only clutter.
    end;
end;

function TNetClient.Upload(const ALocal, ARemote: string; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
var
  Stream: TFileStream;
  Call: TCurlCall;
  Entry: TNetEntry;
begin
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  if not AOverwrite then
  begin
    Result := Stat(ARemote, nil, Entry);
    if Result = nrOk then
    begin
      if AOp <> nil then
        AOp.ErrorText := 'Already exists';
      Exit(nrAlreadyExists);
    end;
    if Result <> nrNotFound then
      Exit;
  end;
  try
    Stream := TFileStream.Create(ALocal, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do
    begin
      if AOp <> nil then
        AOp.ErrorText := E.Message;
      Exit(nrNotFound);
    end;
  end;
  try
    Call := NewCall(AOp, TransferUrl(ARemote));
    try
      Call.Source := Stream;
      Call.SetUpload(Stream.Size);
      Call.ProgressName := PosixLastSegment(ARemote);
      Result := Settle(Call, Call.Perform, AOp);
    finally
      Call.Free;
    end;
  finally
    Stream.Free;
  end;
  InvalidateCache;
end;

function TNetClient.ReadBytes(const ARemote: string; AMaxBytes: Int64; AOp: TNetOp;
  out AData: TBytes): TNetResult;
var
  Mem: TMemoryStream;
  Call: TCurlCall;
begin
  SetLength(AData, 0);
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  Mem := TMemoryStream.Create;
  try
    Call := NewCall(AOp, TransferUrl(ARemote));
    try
      Call.Body := Mem;
      Call.BodyLimit := AMaxBytes;
      Call.ProgressName := PosixLastSegment(ARemote);
      if IsHttpLike then
        Call.SetLong(CURLOPT_FAILONERROR, 1);
      Result := Settle(Call, Call.Perform, AOp);
    finally
      Call.Free;
    end;
    if Result = nrOk then
    begin
      SetLength(AData, Mem.Size);
      if Mem.Size > 0 then
        Move(Mem.Memory^, AData[0], Mem.Size);
    end;
  finally
    Mem.Free;
  end;
end;

function TNetClient.WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
var
  Mem: TBytesStream;
  Call: TCurlCall;
  Entry: TNetEntry;
begin
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  if not AOverwrite then
  begin
    Result := Stat(ARemote, nil, Entry);
    if Result = nrOk then
      Exit(nrAlreadyExists);
    if Result <> nrNotFound then
      Exit;
  end;
  Mem := TBytesStream.Create(AData);
  try
    Call := NewCall(AOp, TransferUrl(ARemote));
    try
      Call.Source := Mem;
      Call.SetUpload(Mem.Size);
      Result := Settle(Call, Call.Perform, AOp);
    finally
      Call.Free;
    end;
  finally
    Mem.Free;
  end;
  InvalidateCache;
end;

function TNetClient.SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult;
begin
  if AOp <> nil then
    AOp.ErrorText := 'Permissions cannot be changed over this protocol';
  Result := nrNotSupported;
end;

function TNetClient.FreeSpace(const APath: string; AOp: TNetOp; out AFree, ATotal: Int64): TNetResult;
begin
  AFree := -1;
  ATotal := -1;
  Result := nrNotSupported;
end;

function TNetClient.ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
begin
  Result := nrNotSupported;
end;

function TNetClient.MakeDirs(const AFolder: string; AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
begin
  Result := Stat(AFolder, nil, Entry);
  if Result = nrOk then
  begin
    if Entry.IsDir then
      Exit(nrOk);
    if AOp <> nil then
      AOp.ErrorText := 'A file with this name exists';
    Exit(nrAlreadyExists);
  end;
  if PosixNormalize(AFolder) = '/' then
    Exit(nrOk);
  Result := MakeDirs(PosixParent(AFolder), AOp);
  if Result <> nrOk then
    Exit;
  Result := MakeDir(AFolder, AOp);
end;

function TNetClient.RemoveTree(const APath: string; AIsDir: Boolean; AOp: TNetOp): TNetResult;
var
  Items: TNetEntries;
  E: TNetEntry;
begin
  if NetCancelled(AOp) then
    Exit(nrCancelled);
  if not AIsDir then
    Exit(RemoveFile(APath, AOp));
  Result := ListDir(APath, AOp, Items);
  if Result <> nrOk then
    Exit;
  for E in Items do
  begin
    // A link is removed as a file, never followed into its target.
    Result := RemoveTree(PosixJoin(APath, E.Name), E.IsDir and not E.IsLink, AOp);
    if Result <> nrOk then
      Exit;
  end;
  Result := RemoveDir(APath, AOp);
end;

function TNetClient.TreeSize(const APath: string; AOp: TNetOp; out ABytes: Int64;
  out AFiles: Integer): TNetResult;
var
  Items: TNetEntries;
  E: TNetEntry;
  SubBytes: Int64;
  SubFiles: Integer;
begin
  ABytes := 0;
  AFiles := 0;
  if NetCancelled(AOp) then
    Exit(nrCancelled);
  Result := ListDir(APath, AOp, Items);
  if Result <> nrOk then
    Exit;
  for E in Items do
    if E.IsDir and not E.IsLink then
    begin
      Result := TreeSize(PosixJoin(APath, E.Name), AOp, SubBytes, SubFiles);
      if Result <> nrOk then
        Exit;
      Inc(ABytes, SubBytes);
      Inc(AFiles, SubFiles);
    end
    else
    begin
      Inc(ABytes, E.Size);
      Inc(AFiles);
    end;
end;

{ TFtpClient }

procedure TFtpClient.Configure(ACall: TCurlCall);
var
  User, Pass: string;
begin
  User := FSession.User;
  Pass := FSession.Password;
  if (FSession.Auth = naAnonymous) or (User = '') then
  begin
    User := 'anonymous';
    Pass := 'anonymous@';
  end;
  ACall.SetText(CURLOPT_USERNAME, User);
  ACall.SetText(CURLOPT_PASSWORD, Pass);
  if (FSession.Protocol = npFtps) and not FSession.ImplicitTls then
    ACall.SetLong(CURLOPT_USE_SSL, CURLUSESSL_ALL);
  if FSession.Passive then
    ACall.SetLong(CURLOPT_FTP_USE_EPSV, 1)
  else
  begin
    ACall.SetLong(CURLOPT_FTP_USE_EPSV, 0);
    ACall.SetText(CURLOPT_FTPPORT, '-');
  end;
  // A server behind NAT often announces its private address in PASV.
  ACall.SetLong(CURLOPT_FTP_SKIP_PASV_IP, 1);
  ACall.SetLong(CURLOPT_FTP_FILEMETHOD, CURLFTPMETHOD_SINGLECWD);
  ACall.SetLong(CURLOPT_FTP_RESPONSE_TIMEOUT, FSession.TimeoutSec);
end;

function TFtpClient.ItemUrl(const APath: string; AIsDir: Boolean): string;
var
  Rel: string;
begin
  Rel := Copy(PosixNormalize(APath), 2, MaxInt);
  if (FSession.Protocol = npFtps) and FSession.ImplicitTls then
    Result := 'ftps://'
  else
    Result := 'ftp://';
  // %2f at the start of the path makes it absolute instead of relative to the login folder.
  Result := Result + HostPart + '/%2f' + EncodePath(Rel);
  if AIsDir and (Rel <> '') then
    Result := Result + '/';
end;

function TFtpClient.ListRaw(const APath: string; AOp: TNetOp;
  out AEntries: TNetEntries): TNetResult;

  function Run(AMlsd: Boolean; out AList: TNetEntries): TNetResult;
  var
    Mem: TMemoryStream;
    Call: TCurlCall;
    Bytes: TBytes;
    Text: string;
  begin
    SetLength(AList, 0);
    Mem := TMemoryStream.Create;
    try
      Call := NewCall(AOp, ItemUrl(APath, True));
      try
        Call.Body := Mem;
        Call.SetTimeout(FSession.TimeoutSec * 6);
        if AMlsd then
          Call.SetCustomRequest('MLSD');
        Result := Call.Perform;
      finally
        Call.Free;
      end;
      if Result <> nrOk then
        Exit;
      SetLength(Bytes, Mem.Size);
      if Mem.Size > 0 then
        Move(Mem.Memory^, Bytes[0], Mem.Size);
      if AMlsd then
        Text := TEncoding.UTF8.GetString(Bytes)
      else
        Text := DecodeWire(Bytes);
      AList := ParseFtpListing(Text, Ord(AMlsd), Now);
    finally
      Mem.Free;
    end;
  end;

var
  First: TNetResult;
begin
  if FMlsd <> 2 then
  begin
    First := Run(True, AEntries);
    if First = nrOk then
    begin
      FMlsd := 1;
      Exit(nrOk);
    end;
    // A real failure (login, network, cancel) is not a reason to try again.
    if (FMlsd = 1) or (First in [nrCancelled, nrAuthFailed, nrTimeout, nrHostKeyUnknown,
         nrHostKeyChanged, nrCertUntrusted, nrNoLibrary]) then
      Exit(First);
    if AOp <> nil then
      AOp.ErrorText := '';
  end;
  Result := Run(False, AEntries);
  if (Result = nrOk) and (FMlsd = 0) then
    FMlsd := 2;
end;

function TFtpClient.RunQuote(const ACommands: array of string; const AParentPath: string;
  AOp: TNetOp): TNetResult;
var
  Call: TCurlCall;
  Cmd: string;
begin
  for Cmd in ACommands do
    if not SafeName(Cmd, AOp) then
      Exit(nrInvalid);
  Call := NewCall(AOp, ItemUrl(AParentPath, True));
  try
    for Cmd in ACommands do
      Call.AddQuote(WireBytes(Cmd));
    Call.SetNoBody;
    Call.SetTimeout(FSession.TimeoutSec * 4);
    Result := Call.Perform;
  finally
    Call.Free;
  end;
  InvalidateCache;
end;

function TFtpClient.Upload(const ALocal, ARemote: string; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
begin
  Result := inherited Upload(ALocal, ARemote, AOp, AOverwrite);
end;

function TFtpClient.WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
begin
  Result := inherited WriteBytes(ARemote, AData, AOp, AOverwrite);
end;

function TFtpClient.RemoveFile(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['DELE ' + PosixNormalize(APath)], PosixParent(APath), AOp);
end;

function TFtpClient.RemoveDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['RMD ' + PosixNormalize(APath)], PosixParent(APath), AOp);
end;

function TFtpClient.MakeDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['MKD ' + PosixNormalize(APath)], PosixParent(APath), AOp);
end;

function TFtpClient.Rename(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
begin
  if not AOverwrite and (Stat(ATo, nil, Entry) = nrOk) then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'Already exists';
    Exit(nrAlreadyExists);
  end;
  Result := RunQuote(['RNFR ' + PosixNormalize(AFrom), 'RNTO ' + PosixNormalize(ATo)],
    PosixParent(AFrom), AOp);
end;

function TFtpClient.SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote([Format('SITE CHMOD %s %s', [IntToStr(((AMode shr 6) and 7) * 100 +
    ((AMode shr 3) and 7) * 10 + (AMode and 7)), PosixNormalize(APath)])],
    PosixParent(APath), AOp);
end;

{ TSftpClient }

procedure TSftpClient.Configure(ACall: TCurlCall);
var
  PubKey: string;
begin
  ACall.SetText(CURLOPT_USERNAME, FSession.User);
  case FSession.Auth of
    naKey:
      begin
        ACall.SetText(CURLOPT_SSH_PRIVATE_KEYFILE, FSession.KeyFile);
        PubKey := FSession.KeyFile + '.pub';
        if FileExists(PubKey) then
          ACall.SetText(CURLOPT_SSH_PUBLIC_KEYFILE, PubKey);
        if FSession.KeyPassphrase <> '' then
          ACall.SetText(CURLOPT_KEYPASSWD, FSession.KeyPassphrase);
        ACall.SetLong(CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PUBLICKEY);
      end;
    naAgent:
      ACall.SetLong(CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_AGENT);
  else
    ACall.SetText(CURLOPT_PASSWORD, FSession.Password);
    ACall.SetLong(CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PASSWORD or CURLSSH_AUTH_KEYBOARD);
  end;
  ACall.EnableSshHostKeyCheck(SshKnownHostsStub);
end;

function TSftpClient.ItemUrl(const APath: string; AIsDir: Boolean): string;
var
  P: string;
begin
  P := PosixNormalize(APath);
  Result := 'sftp://' + HostPart + EncodePath(P);
  if AIsDir and (P <> '/') then
    Result := Result + '/';
end;

function TSftpClient.TransferUrl(const APath: string): string;
begin
  if FSession.Protocol = npScp then
    Result := 'scp://' + HostPart + EncodePath(PosixNormalize(APath))
  else
    Result := ItemUrl(APath, False);
end;

function TSftpClient.ListRaw(const APath: string; AOp: TNetOp;
  out AEntries: TNetEntries): TNetResult;
var
  Mem: TMemoryStream;
  Call: TCurlCall;
  Bytes: TBytes;
  Text: string;
begin
  SetLength(AEntries, 0);
  Mem := TMemoryStream.Create;
  try
    Call := NewCall(AOp, ItemUrl(APath, True));
    try
      Call.Body := Mem;
      Call.SetTimeout(FSession.TimeoutSec * 6);
      Result := Call.Perform;
    finally
      Call.Free;
    end;
    if Result <> nrOk then
      Exit;
    SetLength(Bytes, Mem.Size);
    if Mem.Size > 0 then
      Move(Mem.Memory^, Bytes[0], Mem.Size);
    Text := DecodeWire(Bytes);
    AEntries := ParseFtpListing(Text, 0, Now);
    if (Length(AEntries) = 0) and (Trim(Text) <> '') and not LooksLikeListing(Text) then
    begin
      // The server answered but in a shape this parser does not know.
      if AOp <> nil then
        AOp.ErrorText := 'The listing format of the server is not recognized';
      Result := nrIO;
    end;
  finally
    Mem.Free;
  end;
end;

function TSftpClient.Quoted(const APath: string): string;
begin
  Result := '"' + PosixNormalize(APath).Replace('\', '\\').Replace('"', '\"') + '"';
end;

function TSftpClient.RunQuote(const ACommands: array of string; AOp: TNetOp): TNetResult;
var
  Call: TCurlCall;
  Cmd: string;
begin
  for Cmd in ACommands do
    if not SafeName(Cmd, AOp) then
      Exit(nrInvalid);
  Call := NewCall(AOp, ItemUrl('/', True));
  try
    for Cmd in ACommands do
      Call.AddQuote(WireBytes(Cmd));
    Call.SetNoBody;
    Call.SetTimeout(FSession.TimeoutSec * 4);
    Result := Call.Perform;
  finally
    Call.Free;
  end;
  InvalidateCache;
end;

function TSftpClient.RemoveFile(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['rm ' + Quoted(APath)], AOp);
end;

function TSftpClient.RemoveDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['rmdir ' + Quoted(APath)], AOp);
end;

function TSftpClient.MakeDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote(['mkdir ' + Quoted(APath)], AOp);
end;

function TSftpClient.Rename(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
begin
  if (Stat(ATo, nil, Entry) = nrOk) then
  begin
    if not AOverwrite then
    begin
      if AOp <> nil then
        AOp.ErrorText := 'Already exists';
      Exit(nrAlreadyExists);
    end;
    // SFTP rename does not replace an existing item.
    Result := RunQuote(['rm ' + Quoted(ATo)], AOp);
    if Result <> nrOk then
      Exit;
  end;
  Result := RunQuote(['rename ' + Quoted(AFrom) + ' ' + Quoted(ATo)], AOp);
end;

function TSftpClient.SetMode(const APath: string; AMode: Cardinal; AOp: TNetOp): TNetResult;
begin
  Result := RunQuote([Format('chmod %s %s', [IntToStr(((AMode shr 6) and 7) * 100 +
    ((AMode shr 3) and 7) * 10 + (AMode and 7)), Quoted(APath)])], AOp);
end;

end.
