unit uNetClientHttp;

{ The HTTP-based clients: WebDAV (PROPFIND / MKCOL / MOVE / COPY / DELETE with
  GET and PUT for the data) and S3 (the REST API of Amazon S3 and compatible
  servers; requests are signed by libcurl with AWS Signature V4).

  Session fields used: Host (S3: the endpoint, with an optional http:// or
  https:// prefix), Endpoint (WebDAV: the base path of the share on the server),
  User / Password (WebDAV login; S3 access key and secret key), Region, PathStyle. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uNetTypes, uNetCurl, uNetCurlApi, uNetListParsers, uNetClient;

type
  /// <summary>A window of a file as a read-only stream (one part of an S3
  /// multipart upload).</summary>
  TFileRangeStream = class(TStream)
  private
    FFile: TFileStream;
    FStart, FLength, FPos: Int64;
  public
    constructor Create(AFile: TFileStream; AStart, ALength: Int64);
    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Write(const ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  TWebDavClient = class(TNetClient)
  private
    function BaseScheme: string;
    function BasePath: string;
    function ServerPath(const APath: string): string;
    function Propfind(const APath: string; ADepth: Integer; const ABody: string;
      AOp: TNetOp; out AXml: string): TNetResult;
    function SimpleRequest(const AMethod, APath: string; AIsDir: Boolean; AOp: TNetOp;
      const AExtraHeaders: array of string): TNetResult;
  protected
    function IsHttpLike: Boolean; override;
    procedure Configure(ACall: TCurlCall); override;
    function ItemUrl(const APath: string; AIsDir: Boolean): string; override;
    function ListRaw(const APath: string; AOp: TNetOp;
      out AEntries: TNetEntries): TNetResult; override;
  public
    function Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult; override;
    function RemoveFile(const APath: string; AOp: TNetOp): TNetResult; override;
    function RemoveDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function MakeDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function Rename(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
    function ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
    function FreeSpace(const APath: string; AOp: TNetOp;
      out AFree, ATotal: Int64): TNetResult; override;
  end;

  TS3Client = class(TNetClient)
  private
    function Region: string;
    function EndpointBase: string;
    procedure SplitPath(const APath: string; out ABucket, AKey: string);
    function BuildUrl(const ABucket, AKey, AQuery: string): string;
    function CopySource(const ABucket, AKey: string): string;
    /// <summary>Runs a request whose answer is small text; fails with the
    /// message of the S3 error document when the status is 4xx / 5xx.</summary>
    function Request(const AMethod, ABucket, AKey, AQuery: string;
      const AHeaders: array of string; const ABody: string; AOp: TNetOp;
      out AAnswer: string; out ACall: TCurlCall): TNetResult;
    function RequestSimple(const AMethod, ABucket, AKey, AQuery: string;
      const AHeaders: array of string; AOp: TNetOp): TNetResult;
    function UploadMultipart(const ALocal, ABucket, AKey: string; ASize: Int64;
      AOp: TNetOp): TNetResult;
  protected
    function IsHttpLike: Boolean; override;
    procedure Configure(ACall: TCurlCall); override;
    function ItemUrl(const APath: string; AIsDir: Boolean): string; override;
    function ListRaw(const APath: string; AOp: TNetOp;
      out AEntries: TNetEntries): TNetResult; override;
  public
    function Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult; override;
    function Upload(const ALocal, ARemote: string; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; override;
    function WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
      AOverwrite: Boolean): TNetResult; override;
    function RemoveFile(const APath: string; AOp: TNetOp): TNetResult; override;
    function RemoveDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function MakeDir(const APath: string; AOp: TNetOp): TNetResult; override;
    function Rename(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
    function ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
      AOp: TNetOp): TNetResult; override;
  end;

const
  /// <summary>Files up to this size go in one PUT; bigger ones in parts.</summary>
  cS3SinglePutLimit = 64 * 1024 * 1024;
  cS3PartSize = 32 * 1024 * 1024;

implementation

uses
  System.IOUtils, System.StrUtils;

{ TFileRangeStream }

constructor TFileRangeStream.Create(AFile: TFileStream; AStart, ALength: Int64);
begin
  inherited Create;
  FFile := AFile;
  FStart := AStart;
  FLength := ALength;
end;

function TFileRangeStream.Read(var ABuffer; ACount: Longint): Longint;
var
  Want: Int64;
begin
  Want := FLength - FPos;
  if Want > ACount then
    Want := ACount;
  if Want <= 0 then
    Exit(0);
  FFile.Position := FStart + FPos;
  Result := FFile.Read(ABuffer, Want);
  Inc(FPos, Result);
end;

function TFileRangeStream.Write(const ABuffer; ACount: Longint): Longint;
begin
  Result := 0;
end;

function TFileRangeStream.Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64;
begin
  case AOrigin of
    soBeginning: FPos := AOffset;
    soCurrent: Inc(FPos, AOffset);
    soEnd: FPos := FLength + AOffset;
  end;
  if FPos < 0 then
    FPos := 0;
  if FPos > FLength then
    FPos := FLength;
  Result := FPos;
end;

function StreamText(AStream: TMemoryStream): string;
var
  Bytes: TBytes;
begin
  SetLength(Bytes, AStream.Size);
  if AStream.Size > 0 then
    Move(AStream.Memory^, Bytes[0], AStream.Size);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

{ TWebDavClient }

function TWebDavClient.IsHttpLike: Boolean;
begin
  Result := True;
end;

function TWebDavClient.BaseScheme: string;
begin
  if FSession.Protocol = npWebDavs then
    Result := 'https'
  else
    Result := 'http';
end;

function TWebDavClient.BasePath: string;
begin
  Result := PosixNormalize(FSession.Endpoint);
  if Result = '/' then
    Result := '';
end;

function TWebDavClient.ServerPath(const APath: string): string;
begin
  Result := BasePath + PosixNormalize(APath);
  if Result = '' then
    Result := '/';
end;

procedure TWebDavClient.Configure(ACall: TCurlCall);
begin
  if FSession.User <> '' then
  begin
    ACall.SetText(CURLOPT_USERNAME, FSession.User);
    ACall.SetText(CURLOPT_PASSWORD, FSession.Password);
    ACall.SetLong(CURLOPT_HTTPAUTH, CURLAUTH_ANY);
  end;
  ACall.SetLong(CURLOPT_FOLLOWLOCATION, 1);
  ACall.SetText(CURLOPT_ACCEPT_ENCODING, '');
  // PUT without waiting for "100 Continue".
  ACall.AddHeader('Expect:');
end;

function TWebDavClient.ItemUrl(const APath: string; AIsDir: Boolean): string;
var
  P: string;
begin
  P := ServerPath(APath);
  Result := BaseScheme + '://' + HostPart + EncodePath(P);
  if AIsDir and (P <> '/') then
    Result := Result + '/';
end;

function TWebDavClient.Propfind(const APath: string; ADepth: Integer; const ABody: string;
  AOp: TNetOp; out AXml: string): TNetResult;
var
  Mem: TMemoryStream;
  Call: TCurlCall;
begin
  AXml := '';
  Mem := TMemoryStream.Create;
  try
    Call := NewCall(AOp, ItemUrl(APath, ADepth = 1));
    try
      Call.Body := Mem;
      Call.SetCustomRequest('PROPFIND');
      Call.AddHeader('Depth: ' + IntToStr(ADepth));
      Call.AddHeader('Content-Type: application/xml; charset=utf-8');
      Call.SetPostBody(ABody);
      Call.SetTimeout(FSession.TimeoutSec * 6);
      Result := Call.Perform;
      if Result = nrOk then
      begin
        if Call.HttpStatus = 207 then
          AXml := StreamText(Mem)
        else
        begin
          Result := MapHttpStatus(Call.HttpStatus);
          if Result = nrOk then
            Result := nrIO;
          if AOp <> nil then
            AOp.ErrorText := 'HTTP ' + IntToStr(Call.HttpStatus);
        end;
      end;
    finally
      Call.Free;
    end;
  finally
    Mem.Free;
  end;
end;

const
  cPropfindAll =
    '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop>' +
    '<resourcetype/><getcontentlength/><getlastmodified/><creationdate/></prop></propfind>';
  cPropfindQuota =
    '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop>' +
    '<quota-available-bytes/><quota-used-bytes/></prop></propfind>';

function TWebDavClient.ListRaw(const APath: string; AOp: TNetOp;
  out AEntries: TNetEntries): TNetResult;
var
  Xml: string;
begin
  SetLength(AEntries, 0);
  Result := Propfind(APath, 1, cPropfindAll, AOp, Xml);
  if Result <> nrOk then
    Exit;
  AEntries := ParseWebDavMultiStatus(Xml, ServerPath(APath));
end;

function TWebDavClient.Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult;
var
  Xml: string;
begin
  AEntry := Default(TNetEntry);
  if PosixNormalize(APath) = '/' then
  begin
    AEntry.IsDir := True;
    Exit(nrOk);
  end;
  Result := Propfind(APath, 0, cPropfindAll, AOp, Xml);
  if Result <> nrOk then
    Exit;
  if not ParseWebDavSelf(Xml, AEntry) then
    Exit(nrIO);
  AEntry.Name := PosixLastSegment(APath);
end;

function TWebDavClient.SimpleRequest(const AMethod, APath: string; AIsDir: Boolean;
  AOp: TNetOp; const AExtraHeaders: array of string): TNetResult;
var
  Call: TCurlCall;
  H: string;
begin
  if not SafeName(APath, AOp) then
    Exit(nrInvalid);
  Call := NewCall(AOp, ItemUrl(APath, AIsDir));
  try
    Call.SetCustomRequest(AMethod);
    for H in AExtraHeaders do
      Call.AddHeader(H);
    Call.SetTimeout(FSession.TimeoutSec * 4);
    Result := Settle(Call, Call.Perform, AOp);
  finally
    Call.Free;
  end;
  InvalidateCache;
end;

function TWebDavClient.RemoveFile(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := SimpleRequest('DELETE', APath, False, AOp, []);
end;

function TWebDavClient.RemoveDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := SimpleRequest('DELETE', APath, True, AOp, []);
end;

function TWebDavClient.MakeDir(const APath: string; AOp: TNetOp): TNetResult;
begin
  Result := SimpleRequest('MKCOL', APath, True, AOp, []);
  // 405 on MKCOL: the name is taken.
  if (Result = nrNotSupported) and (AOp <> nil) then
    Result := nrAlreadyExists;
end;

function TWebDavClient.Rename(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Dest: string;
begin
  Dest := BaseScheme + '://' + HostPart + EncodePath(ServerPath(ATo));
  Result := SimpleRequest('MOVE', AFrom, False, AOp,
    ['Destination: ' + Dest, 'Overwrite: ' + IfThen(AOverwrite, 'T', 'F')]);
end;

function TWebDavClient.ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Dest: string;
begin
  Dest := BaseScheme + '://' + HostPart + EncodePath(ServerPath(ATo));
  Result := SimpleRequest('COPY', AFrom, False, AOp,
    ['Destination: ' + Dest, 'Overwrite: ' + IfThen(AOverwrite, 'T', 'F')]);
end;

function TWebDavClient.FreeSpace(const APath: string; AOp: TNetOp; out AFree, ATotal: Int64): TNetResult;
var
  Xml: string;
  Used: Int64;
begin
  AFree := -1;
  ATotal := -1;
  Result := Propfind(APath, 0, cPropfindQuota, AOp, Xml);
  if Result <> nrOk then
    Exit;
  ParseWebDavQuota(Xml, AFree, Used);
  if (AFree >= 0) and (Used >= 0) then
    ATotal := AFree + Used;
  if AFree < 0 then
    Result := nrNotSupported;
end;

{ TS3Client }

function TS3Client.IsHttpLike: Boolean;
begin
  Result := True;
end;

function TS3Client.Region: string;
begin
  Result := Trim(FSession.Region);
  if Result = '' then
    Result := 'us-east-1';
end;

function TS3Client.EndpointBase: string;
var
  H: string;
begin
  H := Trim(FSession.Host);
  if H = '' then
    H := 's3.' + Region + '.amazonaws.com';
  if (Pos('http://', LowerCase(H)) = 1) or (Pos('https://', LowerCase(H)) = 1) then
  begin
    Result := H;
    while (Result <> '') and (Result[Length(Result)] = '/') do
      Delete(Result, Length(Result), 1);
    Exit;
  end;
  Result := 'https://' + H;
  if (FSession.Port > 0) and (Pos(':', H) = 0) then
    Result := Result + ':' + IntToStr(FSession.Port);
end;

procedure TS3Client.SplitPath(const APath: string; out ABucket, AKey: string);
var
  P: string;
  Slash: Integer;
begin
  P := Copy(PosixNormalize(APath), 2, MaxInt);
  Slash := Pos('/', P);
  if Slash = 0 then
  begin
    ABucket := P;
    AKey := '';
  end
  else
  begin
    ABucket := Copy(P, 1, Slash - 1);
    AKey := Copy(P, Slash + 1, MaxInt);
  end;
end;

function TS3Client.BuildUrl(const ABucket, AKey, AQuery: string): string;
var
  Base, Scheme, HostRest: string;
  P: Integer;
begin
  Base := EndpointBase;
  if ABucket = '' then
    Result := Base + '/'
  else if FSession.PathStyle then
  begin
    Result := Base + '/' + UrlEncodeComponent(ABucket) + '/' + UrlEncodePath(AKey);
    if AKey = '' then
      Result := Base + '/' + UrlEncodeComponent(ABucket);
  end
  else
  begin
    P := Pos('://', Base);
    Scheme := Copy(Base, 1, P + 2);
    HostRest := Copy(Base, P + 3, MaxInt);
    Result := Scheme + ABucket + '.' + HostRest + '/' + UrlEncodePath(AKey);
  end;
  if AQuery <> '' then
    Result := Result + '?' + AQuery;
end;

function TS3Client.ItemUrl(const APath: string; AIsDir: Boolean): string;
var
  Bucket, Key: string;
begin
  SplitPath(APath, Bucket, Key);
  Result := BuildUrl(Bucket, Key, '');
end;

procedure TS3Client.Configure(ACall: TCurlCall);
begin
  ACall.SetText(CURLOPT_USERPWD, FSession.User + ':' + FSession.Password);
  ACall.SetText(CURLOPT_AWS_SIGV4, 'aws:amz:' + Region + ':s3');
  ACall.SetLong(CURLOPT_FOLLOWLOCATION, 0);
  ACall.AddHeader('Expect:');
end;

function TS3Client.CopySource(const ABucket, AKey: string): string;
begin
  Result := '/' + UrlEncodeComponent(ABucket) + '/' + UrlEncodePath(AKey);
end;

function ErrorMessageOf(const AXml: string; AStatus: Integer): string;
var
  Root: TXmlNode;
begin
  Result := '';
  Root := ParseXml(AXml);
  if Root <> nil then
    try
      Result := Root.ChildText('message');
      if Result = '' then
        Result := Root.ChildText('code');
    finally
      Root.Free;
    end;
  if Result = '' then
    Result := 'HTTP ' + IntToStr(AStatus);
end;

function TS3Client.Request(const AMethod, ABucket, AKey, AQuery: string;
  const AHeaders: array of string; const ABody: string; AOp: TNetOp;
  out AAnswer: string; out ACall: TCurlCall): TNetResult;
var
  Mem: TMemoryStream;
  H: string;
begin
  AAnswer := '';
  Mem := TMemoryStream.Create;
  ACall := NewCall(AOp, BuildUrl(ABucket, AKey, AQuery));
  try
    ACall.Body := Mem;
    if AMethod = 'HEAD' then
      ACall.SetNoBody
    else if AMethod <> 'GET' then
      ACall.SetCustomRequest(AMethod);
    for H in AHeaders do
      ACall.AddHeader(H);
    if ABody <> '' then
      ACall.SetPostBody(ABody);
    ACall.SetTimeout(FSession.TimeoutSec * 6);
    Result := ACall.Perform;
    AAnswer := StreamText(Mem);
    if (Result = nrOk) and (ACall.HttpStatus >= 400) then
    begin
      Result := MapHttpStatus(ACall.HttpStatus);
      if Result = nrOk then
        Result := nrIO;
      if AOp <> nil then
        AOp.ErrorText := ErrorMessageOf(AAnswer, ACall.HttpStatus);
    end;
  finally
    Mem.Free;
  end;
end;

function TS3Client.RequestSimple(const AMethod, ABucket, AKey, AQuery: string;
  const AHeaders: array of string; AOp: TNetOp): TNetResult;
var
  Answer: string;
  Call: TCurlCall;
begin
  Result := Request(AMethod, ABucket, AKey, AQuery, AHeaders, '', AOp, Answer, Call);
  Call.Free;
  InvalidateCache;
end;

function TS3Client.ListRaw(const APath: string; AOp: TNetOp;
  out AEntries: TNetEntries): TNetResult;
var
  Bucket, Key, Prefix, Query, Token, Answer, Next: string;
  Page: TNetEntries;
  All: TList<TNetEntry>;
  Call: TCurlCall;
  Truncated: Boolean;
begin
  SetLength(AEntries, 0);
  SplitPath(APath, Bucket, Key);
  if Bucket = '' then
  begin
    Result := Request('GET', '', '', '', [], '', AOp, Answer, Call);
    Call.Free;
    if Result = nrOk then
      AEntries := ParseS3Buckets(Answer);
    Exit;
  end;
  Prefix := Key;
  if Prefix <> '' then
    Prefix := Prefix + '/';
  All := TList<TNetEntry>.Create;
  try
    Token := '';
    repeat
      if NetCancelled(AOp) then
        Exit(nrCancelled);
      Query := '';
      if Token <> '' then
        Query := 'continuation-token=' + UrlEncodeComponent(Token) + '&';
      Query := Query + 'delimiter=%2F&list-type=2&max-keys=1000';
      if Prefix <> '' then
        Query := Query + '&prefix=' + UrlEncodeComponent(Prefix);
      Result := Request('GET', Bucket, '', Query, [], '', AOp, Answer, Call);
      Call.Free;
      if Result <> nrOk then
        Exit;
      Page := ParseS3Objects(Answer, Prefix, Truncated, Next);
      All.AddRange(Page);
      Token := Next;
    until not Truncated or (Token = '');
    AEntries := All.ToArray;
  finally
    All.Free;
  end;
end;

function TS3Client.Stat(const APath: string; AOp: TNetOp; out AEntry: TNetEntry): TNetResult;
var
  Bucket, Key, Answer, Next: string;
  Call: TCurlCall;
  Items: TNetEntries;
  Truncated: Boolean;
begin
  AEntry := Default(TNetEntry);
  SplitPath(APath, Bucket, Key);
  if Bucket = '' then
  begin
    AEntry.IsDir := True;
    Exit(nrOk);
  end;
  if Key = '' then
  begin
    Result := Request('HEAD', Bucket, '', '', [], '', AOp, Answer, Call);
    Call.Free;
    AEntry.Name := Bucket;
    AEntry.IsDir := True;
    Exit;
  end;
  Result := Request('HEAD', Bucket, Key, '', [], '', AOp, Answer, Call);
  try
    if Result = nrOk then
    begin
      AEntry.Name := PosixLastSegment(APath);
      AEntry.Size := Call.ContentLength;
      if AEntry.Size < 0 then
        AEntry.Size := StrToInt64Def(Call.ResponseHeader('Content-Length'), 0);
      AEntry.Modified := ParseHttpDate(Call.ResponseHeader('Last-Modified'));
      Exit(nrOk);
    end;
  finally
    Call.Free;
  end;
  if Result <> nrNotFound then
    Exit;
  // Not an object: a "folder" exists when some key starts with it.
  if AOp <> nil then
    AOp.ErrorText := '';
  Result := Request('GET', Bucket, '', 'delimiter=%2F&list-type=2&max-keys=1&prefix=' +
    UrlEncodeComponent(Key + '/'), [], '', AOp, Answer, Call);
  Call.Free;
  if Result <> nrOk then
    Exit;
  Items := ParseS3Objects(Answer, Key + '/', Truncated, Next);
  if (Length(Items) > 0) or (Pos('<Key>' + Key + '/</Key>', Answer) > 0) then
  begin
    AEntry.Name := PosixLastSegment(APath);
    AEntry.IsDir := True;
    Exit(nrOk);
  end;
  Result := nrNotFound;
end;

function TS3Client.Upload(const ALocal, ARemote: string; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
var
  Bucket, Key: string;
  Stream: TFileStream;
  Call: TCurlCall;
  Entry: TNetEntry;
  Answer: string;
  Mem: TMemoryStream;
begin
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  SplitPath(ARemote, Bucket, Key);
  if (Bucket = '') or (Key = '') then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'Files go into a bucket';
    Exit(nrNotSupported);
  end;
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
    if Stream.Size > cS3SinglePutLimit then
    begin
      Result := UploadMultipart(ALocal, Bucket, Key, Stream.Size, AOp);
      InvalidateCache;
      Exit;
    end;
    Mem := TMemoryStream.Create;
    try
      Call := NewCall(AOp, BuildUrl(Bucket, Key, ''));
      try
        Call.Body := Mem;
        Call.Source := Stream;
        Call.SetUpload(Stream.Size);
        Call.AddHeader('x-amz-content-sha256: UNSIGNED-PAYLOAD');
        Call.ProgressName := PosixLastSegment(ARemote);
        Result := Call.Perform;
        if (Result = nrOk) and (Call.HttpStatus >= 400) then
        begin
          Answer := StreamText(Mem);
          Result := MapHttpStatus(Call.HttpStatus);
          if Result = nrOk then
            Result := nrIO;
          if AOp <> nil then
            AOp.ErrorText := ErrorMessageOf(Answer, Call.HttpStatus);
        end;
      finally
        Call.Free;
      end;
    finally
      Mem.Free;
    end;
  finally
    Stream.Free;
  end;
  InvalidateCache;
end;

function TS3Client.UploadMultipart(const ALocal, ABucket, AKey: string; ASize: Int64;
  AOp: TNetOp): TNetResult;
var
  Answer, UploadId, Etag, CompleteBody: string;
  Call: TCurlCall;
  Root: TXmlNode;
  File_: TFileStream;
  Part: TFileRangeStream;
  Mem: TMemoryStream;
  Offset, Len: Int64;
  N: Integer;
  Etags: TStringList;
  I: Integer;
begin
  Result := Request('POST', ABucket, AKey, 'uploads', [], '', AOp, Answer, Call);
  Call.Free;
  if Result <> nrOk then
    Exit;
  Root := ParseXml(Answer);
  if Root = nil then
    Exit(nrIO);
  try
    UploadId := Trim(Root.ChildText('uploadid'));
  finally
    Root.Free;
  end;
  if UploadId = '' then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'The server did not start a multipart upload';
    Exit(nrIO);
  end;
  Etags := TStringList.Create;
  try
    File_ := TFileStream.Create(ALocal, fmOpenRead or fmShareDenyNone);
    try
      Offset := 0;
      N := 0;
      Result := nrOk;
      while (Offset < ASize) and (Result = nrOk) do
      begin
        Inc(N);
        Len := ASize - Offset;
        if Len > cS3PartSize then
          Len := cS3PartSize;
        Part := TFileRangeStream.Create(File_, Offset, Len);
        Mem := TMemoryStream.Create;
        try
          Call := NewCall(AOp, BuildUrl(ABucket, AKey, 'partNumber=' + IntToStr(N) +
            '&uploadId=' + UrlEncodeComponent(UploadId)));
          try
            Call.Body := Mem;
            Call.Source := Part;
            Call.SetUpload(Len);
            Call.ProgressBase := Offset;
            Call.ProgressTotal := ASize;
            Call.ProgressName := PosixLastSegment(AKey);
            Call.AddHeader('x-amz-content-sha256: UNSIGNED-PAYLOAD');
            Result := Call.Perform;
            if (Result = nrOk) and (Call.HttpStatus >= 400) then
            begin
              Result := MapHttpStatus(Call.HttpStatus);
              if Result = nrOk then
                Result := nrIO;
              if AOp <> nil then
                AOp.ErrorText := ErrorMessageOf(StreamText(Mem), Call.HttpStatus);
            end
            else if Result = nrOk then
            begin
              Etag := Call.ResponseHeader('ETag');
              if Etag = '' then
              begin
                Result := nrIO;
                if AOp <> nil then
                  AOp.ErrorText := 'The server did not return an ETag for part ' + IntToStr(N);
              end
              else
                Etags.Add(Etag);
            end;
          finally
            Call.Free;
          end;
        finally
          Mem.Free;
          Part.Free;
        end;
        Inc(Offset, Len);
      end;
    finally
      File_.Free;
    end;
    if Result = nrOk then
    begin
      CompleteBody := '<CompleteMultipartUpload>';
      for I := 0 to Etags.Count - 1 do
        CompleteBody := CompleteBody + '<Part><PartNumber>' + IntToStr(I + 1) +
          '</PartNumber><ETag>' + Etags[I] + '</ETag></Part>';
      CompleteBody := CompleteBody + '</CompleteMultipartUpload>';
      Result := Request('POST', ABucket, AKey, 'uploadId=' + UrlEncodeComponent(UploadId),
        ['Content-Type: application/xml'], CompleteBody, AOp, Answer, Call);
      Call.Free;
      // A 200 can still carry an error document.
      if (Result = nrOk) and (Pos('<Error>', Answer) > 0) then
      begin
        if AOp <> nil then
          AOp.ErrorText := ErrorMessageOf(Answer, 200);
        Result := nrIO;
      end;
    end;
    if Result <> nrOk then
    begin
      // Parts of an unfinished upload cost storage until aborted.
      Answer := '';
      if AOp <> nil then
        Answer := AOp.ErrorText;
      RequestSimple('DELETE', ABucket, AKey, 'uploadId=' + UrlEncodeComponent(UploadId), [], nil);
      if AOp <> nil then
        AOp.ErrorText := Answer;
    end;
  finally
    Etags.Free;
  end;
end;

function TS3Client.WriteBytes(const ARemote: string; const AData: TBytes; AOp: TNetOp;
  AOverwrite: Boolean): TNetResult;
var
  Bucket, Key, Answer: string;
  Mem: TBytesStream;
  Out_: TMemoryStream;
  Call: TCurlCall;
  Entry: TNetEntry;
begin
  if not SafeName(ARemote, AOp) then
    Exit(nrInvalid);
  SplitPath(ARemote, Bucket, Key);
  if (Bucket = '') or (Key = '') then
    Exit(nrNotSupported);
  if not AOverwrite then
  begin
    Result := Stat(ARemote, nil, Entry);
    if Result = nrOk then
      Exit(nrAlreadyExists);
    if Result <> nrNotFound then
      Exit;
  end;
  Mem := TBytesStream.Create(AData);
  Out_ := TMemoryStream.Create;
  try
    Call := NewCall(AOp, BuildUrl(Bucket, Key, ''));
    try
      Call.Body := Out_;
      Call.Source := Mem;
      Call.SetUpload(Mem.Size);
      Call.AddHeader('x-amz-content-sha256: UNSIGNED-PAYLOAD');
      Result := Call.Perform;
      if (Result = nrOk) and (Call.HttpStatus >= 400) then
      begin
        Answer := StreamText(Out_);
        Result := MapHttpStatus(Call.HttpStatus);
        if Result = nrOk then
          Result := nrIO;
        if AOp <> nil then
          AOp.ErrorText := ErrorMessageOf(Answer, Call.HttpStatus);
      end;
    finally
      Call.Free;
    end;
  finally
    Out_.Free;
    Mem.Free;
  end;
  InvalidateCache;
end;

function TS3Client.RemoveFile(const APath: string; AOp: TNetOp): TNetResult;
var
  Bucket, Key: string;
begin
  SplitPath(APath, Bucket, Key);
  if (Bucket = '') or (Key = '') then
    Exit(nrInvalid);
  Result := RequestSimple('DELETE', Bucket, Key, '', [], AOp);
end;

function TS3Client.RemoveDir(const APath: string; AOp: TNetOp): TNetResult;
var
  Bucket, Key: string;
begin
  SplitPath(APath, Bucket, Key);
  if Bucket = '' then
    Exit(nrInvalid);
  if Key = '' then
    Exit(RequestSimple('DELETE', Bucket, '', '', [], AOp));
  // Folders are only key prefixes; the marker object may or may not exist.
  Result := RequestSimple('DELETE', Bucket, Key + '/', '', [], AOp);
  if Result = nrNotFound then
    Result := nrOk;
end;

function TS3Client.MakeDir(const APath: string; AOp: TNetOp): TNetResult;
var
  Bucket, Key, Body: string;
  Answer: string;
  Call: TCurlCall;
begin
  SplitPath(APath, Bucket, Key);
  if Bucket = '' then
    Exit(nrInvalid);
  if Key = '' then
  begin
    Body := '';
    if Region <> 'us-east-1' then
      Body := '<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
        '<LocationConstraint>' + Region + '</LocationConstraint></CreateBucketConfiguration>';
    Result := Request('PUT', Bucket, '', '', ['Content-Type: application/xml'], Body, AOp, Answer, Call);
    Call.Free;
    InvalidateCache;
    Exit;
  end;
  Result := RequestSimple('PUT', Bucket, Key + '/', '', ['Content-Length: 0'], AOp);
end;

function TS3Client.ServerCopy(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  SB, SK, DB, DK: string;
  Entry: TNetEntry;
begin
  SplitPath(AFrom, SB, SK);
  SplitPath(ATo, DB, DK);
  if (SB = '') or (SK = '') or (DB = '') or (DK = '') then
    Exit(nrNotSupported);
  if not AOverwrite and (Stat(ATo, nil, Entry) = nrOk) then
  begin
    if AOp <> nil then
      AOp.ErrorText := 'Already exists';
    Exit(nrAlreadyExists);
  end;
  Result := RequestSimple('PUT', DB, DK, '', ['x-amz-copy-source: ' + CopySource(SB, SK),
    'Content-Length: 0'], AOp);
end;

function TS3Client.Rename(const AFrom, ATo: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
begin
  if Stat(AFrom, nil, Entry) <> nrOk then
    Exit(nrNotFound);
  if Entry.IsDir then
  begin
    // A prefix is renamed by moving every key under it; the caller does that.
    if AOp <> nil then
      AOp.ErrorText := 'Folders are renamed key by key';
    Exit(nrNotSupported);
  end;
  Result := ServerCopy(AFrom, ATo, AOverwrite, AOp);
  if Result = nrOk then
    Result := RemoveFile(AFrom, AOp);
end;

end.
