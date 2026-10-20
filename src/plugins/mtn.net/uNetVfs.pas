unit uNetVfs;

{ The VFS of the network plugin: the version 2 callback table the host calls
  for every net://, ftp://, ftps://, nsftp://, scp://, dav://, davs:// and
  s3:// address. Each callback turns the address into a session and path
  (uNetManager.pas, which also handles the login), runs the operation on the
  client of that session (uNetClient.pas) and maps the outcome to the result
  codes and error text of the plugin ABI.

  net:/// is the list of saved sessions; a session opens at its start folder.
  Copying a folder moves the whole tree; progress counts bytes of the tree and
  cancellation stops the transfer in flight. }

interface

uses
  uPluginHostAbi, uNetManager;

/// <summary>Sets the manager the callbacks work with (nil to detach).</summary>
procedure NetVfsAttach(AManager: TNetManager);
function NetVfsCallbacks: TVfsCallbacksCdeclV2;

/// <summary>net:///Name and net:///Name/dir are written net://Name and
/// net://Name/dir (the host joins a row name onto net:/// that way).</summary>
function NormalizeNetUri(const AUri: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.DateUtils, uVfsTypes, uNetTypes, uNetClient, uNetCurlApi;

const
  cPageEntries = 1500;
  cPageBytes = 3 * 1024 * 1024;
  cListCacheLifeMs = 60000;
  cReadHardCap = 256 * 1024 * 1024;
  cLinkProbes = 10;

type
  TCachedListing = record
    Tick: UInt64;
    Entries: TNetEntries;
    BaseUri: string;
  end;

var
  GManager: TNetManager;
  GCacheLock: TCriticalSection;
  GCache: TDictionary<string, TCachedListing>;

procedure NetVfsAttach(AManager: TNetManager);
begin
  GManager := AManager;
end;

function NormalizeNetUri(const AUri: string): string;
var
  T: TNetTarget;
  Rest: string;
  Slash: Integer;
begin
  Result := AUri;
  if not ParseNetUri(AUri, T) then
    Exit;
  if (T.Scheme = cNetScheme) and (T.Authority = '') and (T.Path <> '/') then
  begin
    Rest := Copy(T.Path, 2, MaxInt);
    Slash := Pos('/', Rest);
    if Slash = 0 then
      Result := MakeNetUri(cNetScheme, Rest, '/')
    else
      Result := MakeNetUri(cNetScheme, Copy(Rest, 1, Slash - 1), Copy(Rest, Slash, MaxInt));
  end;
end;

{ operation bridge }

function MakeOp(ACtx: PVfsOpContext): TNetOp;
var
  Op: TNetOp;
begin
  Op := TNetOp.Create;
  Result := Op;
  if ACtx = nil then
    Exit;
  Op.Cancelled :=
    function: Boolean
    begin
      Result := ACtx^.IsCancelled(ACtx) <> 0;
    end;
  Op.Progress :=
    procedure(ADone, ATotal: Int64; AName: string)
    var
      Name: UTF8String;
      Grand: Int64;
    begin
      Name := UTF8String(AName);
      Grand := Op.GrandTotal;
      if Grand <= 0 then
        Grand := ATotal;
      ACtx^.ReportProgress(ACtx, Op.Base + ADone, Grand, ADone, ATotal, PAnsiChar(Name));
    end;
end;

function ResultCode(R: TNetResult): Int64;
begin
  case R of
    nrOk: Result := Ord(verOk);
    nrNotFound: Result := Ord(verNotFound);
    nrAccessDenied: Result := Ord(verAccessDenied);
    nrAlreadyExists: Result := Ord(verAlreadyExists);
    nrNotSupported, nrNoLibrary: Result := Ord(verNotSupported);
    nrAuthFailed, nrHostKeyUnknown, nrHostKeyChanged, nrCertUntrusted: Result := Ord(verAuthFailed);
    nrCancelled: Result := Ord(verCancelled);
    nrTimeout: Result := Ord(verTimeout);
    nrInvalid: Result := Ord(verInvalidURI);
  else
    Result := Ord(verIOError);
  end;
end;

function DefaultText(R: TNetResult): string;
begin
  case R of
    nrNotFound: Result := 'Not found';
    nrAccessDenied: Result := 'Access denied';
    nrAlreadyExists: Result := 'Already exists';
    nrNotSupported: Result := 'Not supported by this server';
    nrAuthFailed: Result := 'Login failed';
    nrHostKeyUnknown: Result := 'The server key is not trusted';
    nrHostKeyChanged: Result := 'The server key has changed';
    nrCertUntrusted: Result := 'The server certificate is not trusted';
    nrCancelled: Result := 'Cancelled';
    nrTimeout: Result := 'The server did not answer in time';
    nrNoLibrary: Result := 'libcurl was not found next to the plugin';
    nrInvalid: Result := 'Invalid address';
  else
    Result := 'Network error';
  end;
end;

// Frees Op and turns R into the value a callback returns.
function Finish(ACtx: PVfsOpContext; AOp: TNetOp; R: TNetResult): Int64;
var
  Text: UTF8String;
begin
  Result := ResultCode(R);
  if (R <> nrOk) and (ACtx <> nil) and Assigned(ACtx^.SetErrorText) then
  begin
    if AOp.ErrorText <> '' then
      Text := UTF8String(AOp.ErrorText)
    else
      Text := UTF8String(DefaultText(R));
    ACtx^.SetErrorText(ACtx, PAnsiChar(Text));
  end;
  AOp.Free;
end;

procedure PutUtf8(const AText: string; ABuf: PAnsiChar; ABufSize: Int64;
  out ANegotiated: Int64; out AFits: Boolean);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  ANegotiated := Length(Bytes);
  AFits := ANegotiated + 1 <= ABufSize;
  if AFits then
  begin
    if ANegotiated > 0 then
      Move(Bytes[0], ABuf^, ANegotiated);
    ABuf[ANegotiated] := #0;
  end
  else
    ANegotiated := ANegotiated + 1;
end;

{ listing }

function EntryObject(const E: TNetEntry; const ATargetUri: string): TJSONObject;
var
  Ext: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', E.Name);
  Ext := LowerCase(Copy(ExtractFileExt(E.Name), 2, MaxInt));
  if not E.IsDir and (Ext <> '') then
    Result.AddPair('ext', Ext);
  Result.AddPair('size', TJSONNumber.Create(E.Size));
  Result.AddPair('isDir', TJSONBool.Create(E.IsDir));
  Result.AddPair('isLink', TJSONBool.Create(E.IsLink));
  Result.AddPair('isHidden', TJSONBool.Create((E.Name <> '') and (E.Name[1] = '.')));
  if E.Modified > 0 then
    Result.AddPair('modified', TJSONNumber.Create(E.Modified));
  if E.Mode <> 0 then
    Result.AddPair('unixMode', TJSONNumber.Create(Int64(E.Mode)));
  if ATargetUri <> '' then
    Result.AddPair('targetUri', ATargetUri);
end;

function SessionEntries(const AScheme: string): TNetEntries;
var
  I: Integer;
  S: TNetSession;
  E: TNetEntry;
  List: TList<TNetEntry>;
  Proto: TNetProtocol;
  Filter: Boolean;
begin
  Filter := (AScheme <> cNetScheme) and NetSchemeProtocol(AScheme, Proto);
  List := TList<TNetEntry>.Create;
  try
    for I := 0 to GManager.SessionCount - 1 do
    begin
      S := GManager.SessionAt(I);
      if Filter and (S.Protocol <> Proto) then
        Continue;
      E := Default(TNetEntry);
      E.Name := S.Name;
      E.IsDir := True;
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SessionStartUri(const AName: string): string;
var
  S: TNetSession;
  Root: string;
begin
  Root := '/';
  if GManager.FindSession(AName, S) and (S.RootPath <> '') then
    Root := S.RootPath;
  Result := MakeNetUri(cNetScheme, AName, Root);
end;

procedure ResolveLinks(AClient: TNetClient; const APath: string; AOp: TNetOp;
  var AEntries: TNetEntries);
var
  I, Probes: Integer;
  Dummy: TNetEntries;
begin
  Probes := 0;
  for I := 0 to High(AEntries) do
    if AEntries[I].IsLink and not AEntries[I].IsDir and (Probes < cLinkProbes) then
    begin
      Inc(Probes);
      // A link is a folder when it can be listed.
      if AClient.ListDir(PosixJoin(APath, AEntries[I].Name), nil, Dummy) = nrOk then
        AEntries[I].IsDir := True;
    end;
end;

function FetchListing(const AUri: string; AOp: TNetOp; out AEntries: TNetEntries;
  out ABaseUri: string): TNetResult;
var
  T: TNetTarget;
  Items: TNetEntries;
begin
  SetLength(AEntries, 0);
  ABaseUri := AUri;
  if not ParseNetUri(AUri, T) then
    Exit(nrInvalid);
  if T.IsSessionList then
  begin
    AEntries := SessionEntries(T.Scheme);
    Exit(nrOk);
  end;
  Result := GManager.Execute(AUri, AOp,
    function(AClient: TNetClient; const APath: string): TNetResult
    begin
      Result := AClient.ListDir(APath, AOp, Items);
      if Result = nrOk then
        ResolveLinks(AClient, APath, AOp, Items);
    end);
  if Result = nrOk then
    AEntries := Items;
end;

function VfsListDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  AOffset: Int64; ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64;
  out AMore: Int64): Int64; cdecl;
var
  Uri, BaseUri, Json: string;
  Op: TNetOp;
  Entries: TNetEntries;
  Cached: TCachedListing;
  R: TNetResult;
  Arr: TJSONArray;
  I, Last: Integer;
  T: TNetTarget;
  Fits, Hit: Boolean;
  Target: string;
  Key: TPair<string, TCachedListing>;
  Stale: TList<string>;
  K: string;
begin
  ANegotiatedSize := 0;
  AMore := 0;
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(AURI)));
    Hit := False;
    if AOffset > 0 then
    begin
      GCacheLock.Enter;
      try
        Hit := GCache.TryGetValue(Uri, Cached);
      finally
        GCacheLock.Leave;
      end;
    end;
    if Hit then
    begin
      Entries := Cached.Entries;
      BaseUri := Cached.BaseUri;
      R := nrOk;
    end
    else
    begin
      R := FetchListing(Uri, Op, Entries, BaseUri);
      if R = nrOk then
      begin
        Cached.Tick := TThread.GetTickCount64;
        Cached.Entries := Entries;
        Cached.BaseUri := BaseUri;
        GCacheLock.Enter;
        try
          Stale := TList<string>.Create;
          try
            for Key in GCache do
              if Cached.Tick - Key.Value.Tick > cListCacheLifeMs then
                Stale.Add(Key.Key);
            for K in Stale do
              GCache.Remove(K);
          finally
            Stale.Free;
          end;
          GCache.AddOrSetValue(Uri, Cached);
        finally
          GCacheLock.Leave;
        end;
      end;
    end;
    if R <> nrOk then
      Exit(Finish(ACtx, Op, R));
    ParseNetUri(Uri, T);
    Arr := TJSONArray.Create;
    try
      Last := AOffset - 1;
      for I := AOffset to High(Entries) do
      begin
        Target := '';
        if T.IsSessionList then
          Target := SessionStartUri(Entries[I].Name);
        Arr.AddElement(EntryObject(Entries[I], Target));
        Last := I;
        if (Last - AOffset + 1 >= cPageEntries) or (Arr.Count * 160 > cPageBytes) then
          Break;
      end;
      Json := Arr.ToJSON;
    finally
      Arr.Free;
    end;
    if Last < High(Entries) then
      AMore := 1;
    PutUtf8(Json, ABuf, ABufSize, ANegotiatedSize, Fits);
    if not Fits then
    begin
      AMore := 0;
      Op.Free;
      Exit(Ord(verNeedsBiggerBuffer));
    end;
    Result := Finish(ACtx, Op, nrOk);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

{ stat / exists }

function VfsExists(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AIsDirectory: Int64): Int64; cdecl;
var
  Uri: string;
  Op: TNetOp;
  T: TNetTarget;
  R: TNetResult;
  Entry: TNetEntry;
  S: TNetSession;
begin
  AIsDirectory := 0;
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(AURI)));
    if not ParseNetUri(Uri, T) then
      Exit(Finish(ACtx, Op, nrInvalid));
    if T.IsSessionList then
    begin
      AIsDirectory := 1;
      Exit(Finish(ACtx, Op, nrOk));
    end;
    if (not T.IsDirect) and (T.Path = '/') then
    begin
      // The root of a session exists when the session does; no connection needed.
      if GManager.FindSession(T.Authority, S) then
      begin
        AIsDirectory := 1;
        Exit(Finish(ACtx, Op, nrOk));
      end;
      Exit(Finish(ACtx, Op, nrNotFound));
    end;
    R := GManager.Execute(Uri, Op,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := AClient.Stat(APath, Op, Entry);
      end);
    if R = nrOk then
      AIsDirectory := Ord(Entry.IsDir);
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsCreateDirectory(AURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext): Int64; cdecl;
var
  Uri: string;
  Op: TNetOp;
  T: TNetTarget;
  R: TNetResult;
begin
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(AURI)));
    if not ParseNetUri(Uri, T) or T.IsSessionList then
      Exit(Finish(ACtx, Op, nrNotSupported));
    R := GManager.Execute(Uri, Op,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := AClient.MakeDirs(APath, Op);
      end);
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsDelete(AURI: PAnsiChar; AMode: Int64; AUserData: Pointer; ACtx: PVfsOpContext): Int64; cdecl;
var
  Uri: string;
  Op: TNetOp;
  T: TNetTarget;
  R: TNetResult;
begin
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(AURI)));
    if not ParseNetUri(Uri, T) or T.IsSessionList then
      Exit(Finish(ACtx, Op, nrNotSupported));
    if (not T.IsDirect) and (T.Path = '/') then
    begin
      // Deleting a session from the list removes the saved connection only.
      if GManager.DeleteSession(T.Authority) then
        Exit(Finish(ACtx, Op, nrOk));
      Exit(Finish(ACtx, Op, nrNotFound));
    end;
    R := GManager.Execute(Uri, Op,
      function(AClient: TNetClient; const APath: string): TNetResult
      var
        Entry: TNetEntry;
      begin
        Result := AClient.Stat(APath, Op, Entry);
        if Result = nrOk then
          Result := AClient.RemoveTree(APath, Entry.IsDir and not Entry.IsLink, Op);
      end);
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

{ transfers }

function SafeLocalName(const AName: string): string;
var
  I: Integer;
begin
  Result := AName;
  for I := 1 to Length(Result) do
    if (Result[I] < ' ') or CharInSet(Result[I], ['<', '>', ':', '"', '/', '\', '|', '?', '*']) then
      Result[I] := '_';
  while (Result <> '') and CharInSet(Result[Length(Result)], [' ', '.']) do
    Delete(Result, Length(Result), 1);
  if Result = '' then
    Result := '_';
end;

function LocalTreeSize(const APath: string): Int64;
var
  Item: string;
begin
  if TDirectory.Exists(APath) then
  begin
    Result := 0;
    for Item in TDirectory.GetFileSystemEntries(APath) do
      Inc(Result, LocalTreeSize(Item));
  end
  else if TFile.Exists(APath) then
    Result := TFile.GetSize(APath)
  else
    Result := 0;
end;

function UploadChildren(AClient: TNetClient; const ALocal, ARemote: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult; forward;

function UploadFile(AClient: TNetClient; const ALocal, ARemote: string; AOverwrite, ACheckExists: Boolean;
  AOp: TNetOp): TNetResult;
var
  Size: Int64;
  Entry: TNetEntry;
begin
  Size := TFile.GetSize(ALocal);
  if ACheckExists and (not AOverwrite) and (AClient.Stat(ARemote, nil, Entry) = nrOk) then
  begin
    AOp.ErrorText := 'Already exists';
    Exit(nrAlreadyExists);
  end;
  Result := AClient.Upload(ALocal, ARemote, AOp, True);
  if Result = nrOk then
    Inc(AOp.Base, Size);
end;

function UploadNode(AClient: TNetClient; const ALocal, ARemote: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
begin
  if NetCancelled(AOp) then
    Exit(nrCancelled);
  if TDirectory.Exists(ALocal) then
  begin
    Result := AClient.MakeDirs(ARemote, AOp);
    if Result = nrOk then
      Result := UploadChildren(AClient, ALocal, ARemote, AOverwrite, AOp);
    Exit;
  end;
  if not TFile.Exists(ALocal) then
  begin
    AOp.ErrorText := 'The source was not found';
    Exit(nrNotFound);
  end;
  // Servers differ in whether an upload creates the folders above it.
  Result := AClient.MakeDirs(PosixParent(ARemote), AOp);
  if Result = nrOk then
    Result := UploadFile(AClient, ALocal, ARemote, AOverwrite, True, AOp);
end;

// The folder ARemote exists; its names are listed once so files and folders
// below it are checked without a lookup each.
function UploadChildren(AClient: TNetClient; const ALocal, ARemote: string; AOverwrite: Boolean;
  AOp: TNetOp): TNetResult;
var
  Existing: TNetEntries;
  Names: TDictionary<string, TNetEntry>;
  E: TNetEntry;
  Item, Name, Target: string;
begin
  Result := AClient.ListDir(ARemote, AOp, Existing);
  if Result <> nrOk then
    Exit;
  Names := TDictionary<string, TNetEntry>.Create;
  try
    for E in Existing do
      Names.AddOrSetValue(E.Name, E);
    for Item in TDirectory.GetFileSystemEntries(ALocal) do
    begin
      if NetCancelled(AOp) then
        Exit(nrCancelled);
      Name := ExtractFileName(Item);
      Target := PosixJoin(ARemote, Name);
      if TDirectory.Exists(Item) then
      begin
        if not (Names.TryGetValue(Name, E) and E.IsDir) then
          Result := AClient.MakeDir(Target, AOp)
        else
          Result := nrOk;
        if Result = nrOk then
          Result := UploadChildren(AClient, Item, Target, AOverwrite, AOp);
      end
      else
      begin
        if (not AOverwrite) and Names.ContainsKey(Name) then
        begin
          AOp.ErrorText := 'Already exists';
          Exit(nrAlreadyExists);
        end;
        Result := UploadFile(AClient, Item, Target, True, False, AOp);
      end;
      if Result <> nrOk then
        Exit;
    end;
    Result := nrOk;
  finally
    Names.Free;
  end;
end;

function DownloadEntry(AClient: TNetClient; const ARemote, ALocal: string; const AEntry: TNetEntry;
  AOverwrite, AKeepTime: Boolean; AOp: TNetOp): TNetResult;
var
  Items: TNetEntries;
  E: TNetEntry;
begin
  if NetCancelled(AOp) then
    Exit(nrCancelled);
  if AEntry.IsDir then
  begin
    try
      ForceDirectories(ALocal);
    except
      on Ex: Exception do
      begin
        AOp.ErrorText := Ex.Message;
        Exit(nrAccessDenied);
      end;
    end;
    Result := AClient.ListDir(ARemote, AOp, Items);
    if Result <> nrOk then
      Exit;
    for E in Items do
    begin
      // Links are not followed into: a link to a folder could lead back up.
      if E.IsLink and E.IsDir then
        Continue;
      Result := DownloadEntry(AClient, PosixJoin(ARemote, E.Name),
        TPath.Combine(ALocal, SafeLocalName(E.Name)), E, AOverwrite, AKeepTime, AOp);
      if Result <> nrOk then
        Exit;
    end;
    Exit(nrOk);
  end;
  if (not AOverwrite) and TFile.Exists(ALocal) then
  begin
    AOp.ErrorText := 'Already exists';
    Exit(nrAlreadyExists);
  end;
  Result := AClient.Download(ARemote, ALocal, AOp, AKeepTime, AEntry.Size);
  if Result = nrOk then
    Inc(AOp.Base, AEntry.Size);
end;

function DownloadNode(AClient: TNetClient; const ARemote, ALocal: string; AOverwrite, AKeepTime: Boolean;
  AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
begin
  Result := AClient.Stat(ARemote, AOp, Entry);
  if Result = nrOk then
    Result := DownloadEntry(AClient, ARemote, ALocal, Entry, AOverwrite, AKeepTime, AOp);
end;

function IsNetUri(const AUri: string): Boolean;
var
  T: TNetTarget;
begin
  Result := ParseNetUri(AUri, T);
end;

function RemoteSize(const AUri: string; AOp: TNetOp; out ASize: Int64): TNetResult;
var
  Size: Int64;
begin
  Size := 0;
  Result := GManager.Execute(AUri, AOp,
    function(AClient: TNetClient; const APath: string): TNetResult
    var
      Entry: TNetEntry;
      Files: Integer;
    begin
      Result := AClient.Stat(APath, AOp, Entry);
      if (Result = nrOk) then
      begin
        if Entry.IsDir then
          Result := AClient.TreeSize(APath, AOp, Size, Files)
        else
          Size := Entry.Size;
      end;
    end);
  ASize := Size;
end;

function CopyNodeServerSide(AClient: TNetClient; const AFromPath, AToPath: string;
  AOverwrite: Boolean; AOp: TNetOp): TNetResult;
var
  Entry: TNetEntry;
  Items: TNetEntries;
  E: TNetEntry;
begin
  Result := AClient.Stat(AFromPath, AOp, Entry);
  if Result <> nrOk then
    Exit;
  if not Entry.IsDir then
    Exit(AClient.ServerCopy(AFromPath, AToPath, AOverwrite, AOp));
  Result := AClient.MakeDirs(AToPath, AOp);
  if Result <> nrOk then
    Exit;
  Result := AClient.ListDir(AFromPath, AOp, Items);
  if Result <> nrOk then
    Exit;
  for E in Items do
  begin
    Result := CopyNodeServerSide(AClient, PosixJoin(AFromPath, E.Name), PosixJoin(AToPath, E.Name),
      AOverwrite, AOp);
    if Result <> nrOk then
      Exit;
  end;
end;

function CopyRemoteToRemote(const AFrom, ATo: string; AOverwrite, AKeepTime: Boolean; AOp: TNetOp): TNetResult;
var
  SF, ST: TNetSession;
  PF, PT: string;
  Temp: string;
  Size: Int64;
begin
  Result := GManager.Resolve(AFrom, SF, PF);
  if Result <> nrOk then
    Exit;
  Result := GManager.Resolve(ATo, ST, PT);
  if Result <> nrOk then
    Exit;
  if SameText(SF.Name, ST.Name) then
  begin
    // Inside one server: its own copy command when it has one.
    Result := GManager.Execute(AFrom, AOp,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := CopyNodeServerSide(AClient, APath, PT, AOverwrite, AOp);
      end);
    if Result <> nrNotSupported then
      Exit;
    AOp.ErrorText := '';
  end;
  // Through a temporary local folder.
  Result := RemoteSize(AFrom, AOp, Size);
  if Result <> nrOk then
    Exit;
  Temp := TPath.Combine(TPath.GetTempPath, 'mtn2-net-' + TGUID.NewGuid.ToString);
  try
    TDirectory.CreateDirectory(Temp);
    AOp.Base := 0;
    AOp.GrandTotal := Size * 2;
    Result := GManager.Execute(AFrom, AOp,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := DownloadNode(AClient, APath, TPath.Combine(Temp, 'item'), True, AKeepTime, AOp);
      end);
    if Result <> nrOk then
      Exit;
    AOp.Base := Size;
    Result := GManager.Execute(ATo, AOp,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := UploadNode(AClient, TPath.Combine(Temp, 'item'), APath, AOverwrite, AOp);
      end);
  finally
    try
      if TDirectory.Exists(Temp) then
        TDirectory.Delete(Temp, True);
    except
      // The OS clears temp folders sooner or later.
    end;
  end;
end;

function VfsCopyItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  From, To_, LocalPath: string;
  Op: TNetOp;
  R: TNetResult;
  Overwrite, KeepTime: Boolean;
  Size: Int64;
begin
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    From := NormalizeNetUri(string(UTF8String(AFromURI)));
    To_ := NormalizeNetUri(string(UTF8String(AToURI)));
    Overwrite := (AFlags and 1) <> 0;
    KeepTime := (AFlags and 2) <> 0;
    if IsNetUri(From) and IsNetUri(To_) then
      R := CopyRemoteToRemote(From, To_, Overwrite, KeepTime, Op)
    else if IsNetUri(To_) then
    begin
      LocalPath := FileUriToPath(From);
      if LocalPath = '' then
      begin
        Op.ErrorText := 'Only local files can be sent from here';
        R := nrNotSupported;
      end
      else
      begin
        Op.GrandTotal := LocalTreeSize(LocalPath);
        R := GManager.Execute(To_, Op,
          function(AClient: TNetClient; const APath: string): TNetResult
          begin
            Op.Base := 0;
            Result := UploadNode(AClient, LocalPath, APath, Overwrite, Op);
          end);
      end;
    end
    else if IsNetUri(From) then
    begin
      LocalPath := FileUriToPath(To_);
      if LocalPath = '' then
      begin
        Op.ErrorText := 'Only a local folder can receive the files';
        R := nrNotSupported;
      end
      else
      begin
        R := RemoteSize(From, Op, Size);
        if R = nrOk then
        begin
          Op.GrandTotal := Size;
          R := GManager.Execute(From, Op,
            function(AClient: TNetClient; const APath: string): TNetResult
            begin
              Op.Base := 0;
              Result := DownloadNode(AClient, APath, LocalPath, Overwrite, KeepTime, Op);
            end);
        end;
      end;
    end
    else
      R := nrNotSupported;
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsMoveItem(AFromURI, AToURI: PAnsiChar; AFlags: Int64; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  From, To_: string;
  Op: TNetOp;
  R: TNetResult;
  Overwrite: Boolean;
  SF, ST: TNetSession;
  PF, PT: string;
begin
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    From := NormalizeNetUri(string(UTF8String(AFromURI)));
    To_ := NormalizeNetUri(string(UTF8String(AToURI)));
    Overwrite := (AFlags and 1) <> 0;
    R := GManager.Resolve(From, SF, PF);
    if R = nrOk then
      R := GManager.Resolve(To_, ST, PT);
    if R <> nrOk then
      Exit(Finish(ACtx, Op, R));
    R := nrNotSupported;
    if SameText(SF.Name, ST.Name) then
      // One server renames in place; no data moves.
      R := GManager.Execute(From, Op,
        function(AClient: TNetClient; const APath: string): TNetResult
        begin
          Result := AClient.Rename(APath, PT, Overwrite, Op);
        end);
    if R = nrNotSupported then
    begin
      Op.ErrorText := '';
      R := CopyRemoteToRemote(From, To_, Overwrite, True, Op);
      if R = nrOk then
        R := GManager.Execute(From, Op,
          function(AClient: TNetClient; const APath: string): TNetResult
          var
            Entry: TNetEntry;
          begin
            Result := AClient.Stat(APath, Op, Entry);
            if Result = nrOk then
              Result := AClient.RemoveTree(APath, Entry.IsDir and not Entry.IsLink, Op);
          end);
    end;
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

{ reading and writing whole files }

function ReadBody(AUri: PAnsiChar; AMaxBytes: Int64; out AData: TBytes;
  out ANeeded: Int64; ABufSize: Int64; AOp: TNetOp): TNetResult;
var
  Uri: string;
  Cap: Int64;
  Got: TBytes;
  Needed: Int64;
begin
  SetLength(AData, 0);
  Needed := 0;
  Uri := NormalizeNetUri(string(UTF8String(AUri)));
  Cap := AMaxBytes;
  if Cap <= 0 then
    Cap := 2 * 1024 * 1024;
  Result := GManager.Execute(Uri, AOp,
    function(AClient: TNetClient; const APath: string): TNetResult
    var
      Entry: TNetEntry;
    begin
      Needed := 0;
      Result := AClient.Stat(APath, AOp, Entry);
      if Result <> nrOk then
        Exit;
      if Entry.IsDir then
      begin
        AOp.ErrorText := 'This is a folder';
        Exit(nrNotSupported);
      end;
      if Entry.Size > Cap then
      begin
        AOp.ErrorText := Format('File too large (max %d KB).', [Cap div 1024]);
        Exit(nrNotSupported);
      end;
      if Entry.Size > ABufSize then
      begin
        Needed := Entry.Size + 1;
        Exit(nrOk);
      end;
      Result := AClient.ReadBytes(APath, Cap, AOp, Got);
      // A server that reported no size (or a smaller one) can deliver more
      // than the caller's buffer holds: ask for a bigger buffer instead of
      // copying past its end.
      if (Result = nrOk) and (Int64(Length(Got)) + 1 > ABufSize) then
      begin
        Needed := Int64(Length(Got)) + 1;
        SetLength(Got, 0);
      end;
    end);
  ANeeded := Needed;
  if (Result = nrOk) and (Needed = 0) then
    AData := Got;
end;

function VfsReadBytes(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer; ACtx: PVfsOpContext;
  ABuf: PByte; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  Op: TNetOp;
  Data: TBytes;
  Needed: Int64;
  R: TNetResult;
begin
  ANegotiatedSize := 0;
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    R := ReadBody(AURI, AMaxBytes, Data, Needed, ABufSize, Op);
    if R <> nrOk then
      Exit(Finish(ACtx, Op, R));
    if Needed > 0 then
    begin
      ANegotiatedSize := Needed;
      Op.Free;
      Exit(Ord(verNeedsBiggerBuffer));
    end;
    ANegotiatedSize := Length(Data);
    if Length(Data) > 0 then
      Move(Data[0], ABuf^, Length(Data));
    Result := Finish(ACtx, Op, nrOk);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsReadText(AURI: PAnsiChar; AMaxBytes: Int64; AUserData: Pointer; ACtx: PVfsOpContext;
  ABuf: PAnsiChar; ABufSize: Int64; out ANegotiatedSize: Int64): Int64; cdecl;
var
  Op: TNetOp;
  Data: TBytes;
  Needed: Int64;
  R: TNetResult;
begin
  ANegotiatedSize := 0;
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    R := ReadBody(AURI, AMaxBytes, Data, Needed, ABufSize, Op);
    if R <> nrOk then
      Exit(Finish(ACtx, Op, R));
    if Needed > 0 then
    begin
      ANegotiatedSize := Needed;
      Op.Free;
      Exit(Ord(verNeedsBiggerBuffer));
    end;
    ANegotiatedSize := Length(Data);
    if Length(Data) > 0 then
      Move(Data[0], ABuf^, Length(Data));
    if ANegotiatedSize < ABufSize then
      ABuf[ANegotiatedSize] := #0;
    Result := Finish(ACtx, Op, nrOk);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsWriteText(AURI: PAnsiChar; AText: PAnsiChar; AUserData: Pointer;
  ACtx: PVfsOpContext): Int64; cdecl;
var
  Uri: string;
  Op: TNetOp;
  R: TNetResult;
  Bytes: TBytes;
begin
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(AURI)));
    Bytes := TEncoding.UTF8.GetBytes(string(UTF8String(AText)));
    R := GManager.Execute(Uri, Op,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := AClient.WriteBytes(APath, Bytes, Op, True);
      end);
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function VfsGetFreeSpace(ARootURI: PAnsiChar; AUserData: Pointer; ACtx: PVfsOpContext;
  out AFree, ATotal: Int64): Int64; cdecl;
var
  Uri: string;
  Op: TNetOp;
  R: TNetResult;
  Free_, Total_: Int64;
begin
  AFree := -1;
  ATotal := -1;
  Free_ := -1;
  Total_ := -1;
  Op := MakeOp(ACtx);
  try
    if GManager = nil then
      Exit(Finish(ACtx, Op, nrNoLibrary));
    Uri := NormalizeNetUri(string(UTF8String(ARootURI)));
    R := GManager.Execute(Uri, Op,
      function(AClient: TNetClient; const APath: string): TNetResult
      begin
        Result := AClient.FreeSpace(APath, Op, Free_, Total_);
      end);
    AFree := Free_;
    ATotal := Total_;
    Result := Finish(ACtx, Op, R);
  except
    on E: Exception do
    begin
      Op.ErrorText := E.Message;
      Result := Finish(ACtx, Op, nrIO);
    end;
  end;
end;

function NetVfsCallbacks: TVfsCallbacksCdeclV2;
begin
  Result := Default(TVfsCallbacksCdeclV2);
  Result.ListDirectory := VfsListDirectory;
  Result.Delete := VfsDelete;
  Result.CreateDirectory := VfsCreateDirectory;
  Result.CopyItem := VfsCopyItem;
  Result.MoveItem := VfsMoveItem;
  Result.ReadText := VfsReadText;
  Result.ReadBytes := VfsReadBytes;
  Result.WriteText := VfsWriteText;
  Result.Exists := VfsExists;
  Result.GetFreeSpace := VfsGetFreeSpace;
end;

initialization
  GCacheLock := TCriticalSection.Create;
  GCache := TDictionary<string, TCachedListing>.Create;

finalization
  GCache.Free;
  GCacheLock.Free;

end.
