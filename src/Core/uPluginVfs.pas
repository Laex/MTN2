unit uPluginVfs;

{ Read access to the virtual file system for plugins (permission "vfs.read").
  The calls are asynchronous: the plugin starts one and its callback runs once on
  the main thread, with a status and the result. A plugin that was unloaded in
  the meantime hears nothing. The plugin passes any URI the program understands
  (file:///, archives, sftp://, a scheme another plugin serves). }

interface

uses
  System.SysUtils;

const
  cPluginVfsOk: Integer = 0;
  cPluginVfsNotFound: Integer = 1;
  cPluginVfsAccessDenied: Integer = 2;
  cPluginVfsNotSupported: Integer = 3;
  cPluginVfsCancelled: Integer = 4;
  cPluginVfsIoError: Integer = 5;
  cPluginVfsInvalidUri: Integer = 6;
  /// <summary>Returned by the start calls (no callback follows): the plugin has
  /// not been granted "vfs.read".</summary>
  cPluginVfsNoPermission: Integer = -2;
  /// <summary>Largest read the host does for a plugin.</summary>
  cPluginVfsMaxRead = 64 * 1024 * 1024;
  cPluginVfsDefaultRead = 2 * 1024 * 1024;
  cPluginVfsMaxEntries = 100000;
  /// <summary>Returned by PluginVfsOpen (no callback follows): the plugin already
  /// holds or is opening cPluginVfsMaxOpen files.</summary>
  cPluginVfsTooManyOpen: Integer = -3;
  cPluginVfsMaxOpen = 16;

type
  TPluginVfsTextDone = reference to procedure(AStatus: Integer; const AText: string);
  TPluginVfsDataDone = reference to procedure(AStatus: Integer; const AData: TBytes);
  /// <summary>AHandle is above 0 when AStatus is 0.</summary>
  TPluginVfsOpenDone = reference to procedure(AStatus: Integer; AHandle: Int64);

/// <summary>Lists a folder. The text is JSON: uri, and entries of name, uri, dir,
/// size and modified (seconds since 1970, local time). 0 = started,
/// cPluginVfsNoPermission, -1 = bad arguments.</summary>
function PluginVfsList(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
/// <summary>Whether the URI exists. The text is JSON: exists and dir.</summary>
function PluginVfsExists(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
/// <summary>Reads a whole file; AMaxBytes of 0 or less means the default of 2 MB, the
/// most is 64 MB. A larger file ends with cPluginVfsNotSupported.</summary>
function PluginVfsRead(const APluginId, AUri: string; AMaxBytes: Int64;
  const ADone: TPluginVfsDataDone): Integer;

/// <summary>Opens a file for reading in pieces. Main thread; the callback follows on the
/// main thread with a status and a handle. A local file is opened in place; any other
/// URI (archive, sftp://, a plugin scheme) is first copied to a temporary file, and a
/// progress notice shows while that takes a while. Returns the number of the job (above 0;
/// the callback follows), or cPluginVfsNoPermission, cPluginVfsTooManyOpen, -1 = bad
/// arguments.</summary>
function PluginVfsOpen(const APluginId, AUri: string; const ADone: TPluginVfsOpenDone): Int64;
/// <summary>Cancels an opening that has not finished (main thread; AOwnerId '' skips the owner
/// check). Its callback still follows once, with cPluginVfsCancelled. 0 = cancelled,
/// -1 = no such job (unknown, finished or another plugin's).</summary>
function PluginVfsCancel(const AOwnerId: string; AJob: Int64): Int64;
/// <summary>Size of an open file in bytes; -1 for an unknown handle. Any thread. AOwnerId is
/// the plugin that opened it; '' skips the check.</summary>
function PluginVfsSize(const AOwnerId: string; AHandle: Int64): Int64;
/// <summary>Reads up to ASize bytes from AOffset into ABuf. Returns the number of bytes
/// read, 0 at the end of the file, -1 for a bad handle or arguments, -5 for an I/O
/// error. Blocks the calling thread only; any thread.</summary>
function PluginVfsReadAt(const AOwnerId: string; AHandle, AOffset: Int64; ABuf: Pointer;
  ASize: Int64): Int64;
/// <summary>Closes the file (a temporary copy is deleted). 0 = closed, -1 = unknown
/// handle. Any thread; a read in progress finishes first.</summary>
function PluginVfsClose(const AOwnerId: string; AHandle: Int64): Int64;
/// <summary>Cancels the openings of a plugin and closes its files. Main thread; called when
/// the plugin is unloaded.</summary>
procedure PluginVfsStreamsRelease(const APluginId: string);

/// <summary>Replaces the file system the calls use (tests); nil restores the default.</summary>
procedure SetPluginVfs(const AVfs: IInterface);

implementation

uses
  System.Classes, System.JSON, System.DateUtils, System.SyncObjs, System.IOUtils,
  System.Diagnostics, System.Math, System.Generics.Collections,
  uVfsTypes, uVfsRegistry, uPluginPermissions, uPluginServices, uStrings;

var
  GVfs: IVirtualFileSystem;

procedure SetPluginVfs(const AVfs: IInterface);
begin
  if AVfs = nil then
    GVfs := nil
  else
    Supports(AVfs, IVirtualFileSystem, GVfs);
end;

function Vfs: IVirtualFileSystem;
begin
  if GVfs = nil then
    GVfs := CreateDefaultVfs;
  Result := GVfs;
end;

function StatusOf(const AError: TVfsError): Integer;
begin
  case AError.Code of
    vecOk: Result := cPluginVfsOk;
    vecNotFound: Result := cPluginVfsNotFound;
    vecAccessDenied: Result := cPluginVfsAccessDenied;
    vecNotSupported, vecAlreadyExists: Result := cPluginVfsNotSupported;
    vecCancelled: Result := cPluginVfsCancelled;
    vecInvalidURI: Result := cPluginVfsInvalidUri;
  else
    Result := cPluginVfsIoError;
  end;
end;

/// <summary>Runs ABody on the main thread on a later pass of the message loop (so the
/// plugin always gets its callback after the start call returned), unless the plugin
/// was unloaded since AGen was read.</summary>
procedure DeliverLater(const AId: string; AGen: Integer; const ABody: TProc);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      if PluginGenerationOf(AId) <> AGen then
        Exit;
      try
        ABody();
      except
        // A faulty plugin callback must not break the message loop.
      end;
    end);
end;

function Allowed(const APluginId, AUri: string): Boolean;
begin
  Result := (Trim(APluginId) <> '') and (Trim(AUri) <> '');
end;

function ListToJson(const AUri: string; const AItems: TArray<TVfsEntry>): string;
var
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  E: TVfsEntry;
  Count: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('uri', AUri);
    Arr := TJSONArray.Create;
    Root.AddPair('entries', Arr);
    Count := 0;
    for E in AItems do
    begin
      if Count >= cPluginVfsMaxEntries then
        Break;
      Item := TJSONObject.Create;
      Item.AddPair('name', E.Name);
      if E.TargetURI <> '' then
        Item.AddPair('uri', E.TargetURI)
      else
        Item.AddPair('uri', JoinVfsUri(AUri, E.Name));
      Item.AddPair('dir', TJSONBool.Create(E.IsDirectory));
      Item.AddPair('size', TJSONNumber.Create(E.Size));
      Item.AddPair('modified', TJSONNumber.Create(DateTimeToUnix(E.ModificationTime, False)));
      Arr.AddElement(Item);
      Inc(Count);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function PluginVfsList(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
var
  Id: string;
  Gen: Integer;
  Uri: string;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  Id := APluginId;
  Uri := Trim(AUri);
  Gen := PluginGenerationOf(Id);
  Vfs.ListDirectoryAsync(Uri, nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    var
      Status: Integer;
      Json: string;
    begin
      Status := StatusOf(AError);
      Json := '';
      if Status = cPluginVfsOk then
        Json := ListToJson(Uri, AItems);
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Json);
        end);
    end);
  Result := 0;
end;

function PluginVfsExists(const APluginId, AUri: string; const ADone: TPluginVfsTextDone): Integer;
var
  Id: string;
  Gen: Integer;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  Id := APluginId;
  Gen := PluginGenerationOf(Id);
  Vfs.ExistsAsync(Trim(AUri), nil,
    procedure(const AExists, AIsDirectory: Boolean; const AError: TVfsError)
    var
      Obj: TJSONObject;
      Status: Integer;
      Json: string;
    begin
      Status := StatusOf(AError);
      Json := '';
      if Status = cPluginVfsOk then
      begin
        Obj := TJSONObject.Create;
        try
          Obj.AddPair('exists', TJSONBool.Create(AExists));
          Obj.AddPair('dir', TJSONBool.Create(AExists and AIsDirectory));
          Json := Obj.ToJSON;
        finally
          Obj.Free;
        end;
      end;
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Json);
        end);
    end);
  Result := 0;
end;

function PluginVfsRead(const APluginId, AUri: string; AMaxBytes: Int64;
  const ADone: TPluginVfsDataDone): Integer;
var
  Id: string;
  Gen: Integer;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  if AMaxBytes <= 0 then
    AMaxBytes := cPluginVfsDefaultRead;
  if AMaxBytes > cPluginVfsMaxRead then
    AMaxBytes := cPluginVfsMaxRead;
  Id := APluginId;
  Gen := PluginGenerationOf(Id);
  Vfs.ReadBytesAsync(Trim(AUri), AMaxBytes, nil,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Status: Integer;
      Bytes: TBytes;
    begin
      Status := StatusOf(AError);
      Bytes := nil;
      if Status = cPluginVfsOk then
        Bytes := ABytes;
      DeliverLater(Id, Gen,
        procedure
        begin
          ADone(Status, Bytes);
        end);
    end);
  Result := 0;
end;

type
  /// <summary>An open file. FRefs counts the table and every call in progress, so a
  /// close during a read frees the file only after the read returns.</summary>
  TStreamEntry = class
  private
    FRefs: Integer;
  public
    OwnerKey: string;
    Stream: TFileStream;
    TempPath: string;
    Lock: TCriticalSection;
    constructor Create(const AOwnerKey: string; AStream: TFileStream; const ATempPath: string);
    function AddRef: TStreamEntry;
    procedure Release;
  end;

  TPendingOpen = record
    OwnerKey: string;
    /// <summary>Stops the copy of a file that is not local; nil for a local file.</summary>
    Cancel: TProc;
    Cancelled: Boolean;
  end;

const
  cOpenShowAfterMs = 400;
  cOpenProgressStepMs = 200;
  cStaleTempDays = 1;

var
  GStreams: TDictionary<Int64, TStreamEntry>;
  GStreamLock: TCriticalSection;
  // Main thread only.
  GPending: TDictionary<Int64, TPendingOpen>;
  GNextJob: Int64;
  GTempDir: string;

constructor TStreamEntry.Create(const AOwnerKey: string; AStream: TFileStream;
  const ATempPath: string);
begin
  inherited Create;
  FRefs := 1;
  OwnerKey := AOwnerKey;
  Stream := AStream;
  TempPath := ATempPath;
  Lock := TCriticalSection.Create;
end;

function TStreamEntry.AddRef: TStreamEntry;
begin
  TInterlocked.Increment(FRefs);
  Result := Self;
end;

procedure TStreamEntry.Release;
begin
  if TInterlocked.Decrement(FRefs) <> 0 then
    Exit;
  Stream.Free;
  if TempPath <> '' then
    try
      TFile.Delete(TempPath);
    except
      // A temporary copy that cannot be deleted now goes with the folder later.
    end;
  Lock.Free;
  Free;
end;

function OwnerKeyOf(const APluginId: string): string;
begin
  Result := LowerCase(Trim(APluginId));
end;

function Acquire(const AOwnerId: string; AHandle: Int64): TStreamEntry;
var
  E: TStreamEntry;
begin
  Result := nil;
  GStreamLock.Enter;
  try
    if GStreams.TryGetValue(AHandle, E) and
       ((AOwnerId = '') or (E.OwnerKey = OwnerKeyOf(AOwnerId))) then
      Result := E.AddRef;
  finally
    GStreamLock.Leave;
  end;
end;

/// <summary>Adds the file to the table. Handles are random and fit 32 bits (WASM guests
/// take them as i32); a plugin that guesses another plugin's handle is still refused
/// when the host knows the caller.</summary>
function RegisterEntry(AEntry: TStreamEntry): Int64;
begin
  GStreamLock.Enter;
  try
    repeat
      Result := 1048576 + Random(1000000000);
    until not GStreams.ContainsKey(Result);
    GStreams.Add(Result, AEntry);
  finally
    GStreamLock.Leave;
  end;
end;

function OpenCountOf(const AOwnerKey: string): Integer;
var
  E: TStreamEntry;
  P: TPendingOpen;
begin
  Result := 0;
  GStreamLock.Enter;
  try
    for E in GStreams.Values do
      if E.OwnerKey = AOwnerKey then
        Inc(Result);
  finally
    GStreamLock.Leave;
  end;
  for P in GPending.Values do
    if P.OwnerKey = AOwnerKey then
      Inc(Result);
end;

procedure RemoveStaleTempDirs(const ARoot: string);
var
  Dir: string;
begin
  try
    for Dir in TDirectory.GetDirectories(ARoot) do
      if TDirectory.GetCreationTime(Dir) < Now - cStaleTempDays then
        try
          TDirectory.Delete(Dir, True);
        except
          // In use by another instance or locked: left for a later start.
        end;
  except
    // No temp root yet.
  end;
end;

function NewTempPath(const AUri: string): string;
var
  Root, Ext: string;
begin
  if GTempDir = '' then
  begin
    Root := TPath.Combine(TPath.GetTempPath, 'mtn2-pvfs');
    RemoveStaleTempDirs(Root);
    GTempDir := TPath.Combine(Root, TPath.GetGUIDFileName(False));
  end;
  ForceDirectories(GTempDir);
  Ext := ExtractFileExt(Trim(AUri));
  if (Length(Ext) > 12) or (Pos('?', Ext) > 0) or (Pos('/', Ext) > 0) or (Pos('\', Ext) > 0) then
    Ext := '';
  Result := TPath.Combine(GTempDir, TPath.GetGUIDFileName(False) + Ext);
end;

/// <summary>Hands the opened file (or the failure) to the plugin on the main thread; a plugin
/// unloaded in the meantime gets nothing and the file is closed.</summary>
procedure FinishOpen(const AId: string; AJob: Int64; AGen: Integer; AStatus: Integer;
  AEntry: TStreamEntry; const ADone: TPluginVfsOpenDone);
begin
  TThread.ForceQueue(nil,
    procedure
    var
      Handle: Int64;
      Status: Integer;
      Pending: TPendingOpen;
    begin
      Status := AStatus;
      if GPending.TryGetValue(AJob, Pending) and Pending.Cancelled then
      begin
        if AEntry <> nil then
          AEntry.Release;
        AEntry := nil;
        Status := cPluginVfsCancelled;
      end;
      GPending.Remove(AJob);
      if PluginGenerationOf(AId) <> AGen then
      begin
        if AEntry <> nil then
          AEntry.Release;
        Exit;
      end;
      Handle := 0;
      if AEntry <> nil then
        Handle := RegisterEntry(AEntry);
      try
        ADone(Status, Handle);
      except
        // A faulty plugin callback must not break the message loop.
      end;
    end);
end;

procedure OpenLocalFile(const AId, AOwnerKey: string; AJob: Int64; AGen: Integer;
  const APath: string; const ADone: TPluginVfsOpenDone);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      S: TFileStream;
      E: TStreamEntry;
      Status: Integer;
    begin
      E := nil;
      Status := cPluginVfsOk;
      try
        S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
        E := TStreamEntry.Create(AOwnerKey, S, '');
      except
        if TFile.Exists(APath) then
          Status := cPluginVfsIoError
        else
          Status := cPluginVfsNotFound;
      end;
      FinishOpen(AId, AJob, AGen, Status, E, ADone);
    end).Start;
end;

procedure OpenCopiedFile(const AId, AOwnerKey: string; AJob: Int64; AGen: Integer;
  const AUri: string; const ADone: TPluginVfsOpenDone);
var
  Job: Int64;
  Temp, ProgId, Title: string;
  Token: TJobCancelToken;
  TokenRef: IJobCancelToken;
  Pending: TPendingOpen;
  Watch: TStopwatch;
  LastShown: Int64;
begin
  Job := AJob;
  Temp := NewTempPath(AUri);
  ProgId := 'vfs-open-' + IntToStr(Job);
  Title := FileUriTitle(AUri);
  if Title = '' then
    Title := Copy(AUri, LastDelimiter('/', AUri) + 1, MaxInt);
  Token := TJobCancelToken.Create;
  TokenRef := Token;
  Pending := GPending[Job];
  Pending.Cancel :=
    procedure
    begin
      // Referencing TokenRef keeps the token object alive while Cancel can run.
      if TokenRef <> nil then
        Token.Cancel;
    end;
  GPending[Job] := Pending;
  Watch := TStopwatch.StartNew;
  LastShown := -cOpenProgressStepMs;
  Vfs.CopyAsync(AUri, PathToFileUri(Temp), TokenRef,
    procedure(const ADoneBytes, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrc, AItemDst: string)
    var
      Pct: Integer;
      Elapsed: Int64;
    begin
      Elapsed := Watch.ElapsedMilliseconds;
      if (Elapsed < cOpenShowAfterMs) or (Elapsed - LastShown < cOpenProgressStepMs) then
        Exit;
      LastShown := Elapsed;
      if AItemTotal > 0 then
        Pct := Integer(Min(100, AItemDone * 100 div AItemTotal))
      else if ATotal > 0 then
        Pct := Integer(Min(100, ADoneBytes * 100 div ATotal))
      else
        Pct := -1;
      TThread.Queue(nil,
        procedure
        begin
          if GPending.ContainsKey(Job) then
            PluginProgressSet(AId, ProgId,
              T('ui.plugin.vfsOpenProgress', 'Reading %s', [Title]), Pct);
        end);
    end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    var
      Status: Integer;
    begin
      Status := StatusOf(AError);
      TThread.ForceQueue(nil,
        procedure
        var
          S: TFileStream;
          E: TStreamEntry;
        begin
          PluginProgressEnd(AId, ProgId);
          E := nil;
          if ASuccess then
          begin
            try
              S := TFileStream.Create(Temp, fmOpenRead or fmShareDenyNone);
              E := TStreamEntry.Create(AOwnerKey, S, Temp);
              Status := cPluginVfsOk;
            except
              Status := cPluginVfsIoError;
            end;
          end
          else if Status = cPluginVfsOk then
            Status := cPluginVfsIoError;
          if E = nil then
            try
              TFile.Delete(Temp);
            except
              // Nothing was copied, or the file is already gone.
            end;
          FinishOpen(AId, Job, AGen, Status, E, ADone);
        end);
    end,
    True);
end;

function PluginVfsOpen(const APluginId, AUri: string; const ADone: TPluginVfsOpenDone): Int64;
var
  Id, Uri, Key: string;
  Gen: Integer;
  Pending: TPendingOpen;
begin
  if not Allowed(APluginId, AUri) or not Assigned(ADone) then
    Exit(-1);
  if not PluginHasPermission(APluginId, cPermVfsRead) then
    Exit(cPluginVfsNoPermission);
  Id := APluginId;
  Key := OwnerKeyOf(Id);
  if OpenCountOf(Key) >= cPluginVfsMaxOpen then
    Exit(cPluginVfsTooManyOpen);
  Uri := Trim(AUri);
  Gen := PluginGenerationOf(Id);
  Inc(GNextJob);
  Result := GNextJob;
  Pending := Default(TPendingOpen);
  Pending.OwnerKey := Key;
  GPending.Add(Result, Pending);
  if SameText(Copy(Uri, 1, 5), 'file:') then
    OpenLocalFile(Id, Key, Result, Gen, FileUriToPath(Uri), ADone)
  else
    OpenCopiedFile(Id, Key, Result, Gen, Uri, ADone);
end;

function PluginVfsCancel(const AOwnerId: string; AJob: Int64): Int64;
var
  Pending: TPendingOpen;
begin
  if not GPending.TryGetValue(AJob, Pending) or
     ((AOwnerId <> '') and (Pending.OwnerKey <> OwnerKeyOf(AOwnerId))) then
    Exit(-1);
  if not Pending.Cancelled then
  begin
    Pending.Cancelled := True;
    GPending[AJob] := Pending;
    if Assigned(Pending.Cancel) then
      Pending.Cancel();
  end;
  Result := 0;
end;

function PluginVfsSize(const AOwnerId: string; AHandle: Int64): Int64;
var
  E: TStreamEntry;
begin
  E := Acquire(AOwnerId, AHandle);
  if E = nil then
    Exit(-1);
  try
    E.Lock.Enter;
    try
      try
        Result := E.Stream.Size;
      except
        Result := -1;
      end;
    finally
      E.Lock.Leave;
    end;
  finally
    E.Release;
  end;
end;

function PluginVfsReadAt(const AOwnerId: string; AHandle, AOffset: Int64; ABuf: Pointer;
  ASize: Int64): Int64;
var
  E: TStreamEntry;
begin
  if (ABuf = nil) or (AOffset < 0) or (ASize < 0) then
    Exit(-1);
  E := Acquire(AOwnerId, AHandle);
  if E = nil then
    Exit(-1);
  try
    if ASize = 0 then
      Exit(0);
    E.Lock.Enter;
    try
      try
        if AOffset >= E.Stream.Size then
          Exit(0);
        E.Stream.Seek(AOffset, soBeginning);
        Result := E.Stream.Read(ABuf^, Integer(Min(ASize, High(Integer))));
      except
        Result := -5;
      end;
    finally
      E.Lock.Leave;
    end;
  finally
    E.Release;
  end;
end;

function PluginVfsClose(const AOwnerId: string; AHandle: Int64): Int64;
var
  E: TStreamEntry;
begin
  E := nil;
  GStreamLock.Enter;
  try
    if GStreams.TryGetValue(AHandle, E) and
       ((AOwnerId <> '') and (E.OwnerKey <> OwnerKeyOf(AOwnerId))) then
      E := nil;
    if E <> nil then
      GStreams.Remove(AHandle);
  finally
    GStreamLock.Leave;
  end;
  if E = nil then
    Exit(-1);
  E.Release;
  Result := 0;
end;

procedure PluginVfsStreamsRelease(const APluginId: string);
var
  Key: string;
  Handles: TArray<Int64>;
  P: TPair<Int64, TStreamEntry>;
  Q: TPair<Int64, TPendingOpen>;
  H, Job: Int64;
  Jobs: TArray<Int64>;
begin
  Key := OwnerKeyOf(APluginId);
  for Q in GPending do
    if Q.Value.OwnerKey = Key then
      Jobs := Jobs + [Q.Key];
  for Job in Jobs do
    PluginVfsCancel(Key, Job);
  GStreamLock.Enter;
  try
    for P in GStreams do
      if P.Value.OwnerKey = Key then
        Handles := Handles + [P.Key];
  finally
    GStreamLock.Leave;
  end;
  for H in Handles do
    PluginVfsClose('', H);
end;

procedure ReleaseAllStreams;
var
  Handles: TArray<Int64>;
  H: Int64;
begin
  GStreamLock.Enter;
  try
    Handles := GStreams.Keys.ToArray;
  finally
    GStreamLock.Leave;
  end;
  for H in Handles do
    PluginVfsClose('', H);
  if GTempDir <> '' then
    try
      TDirectory.Delete(GTempDir, True);
    except
      // Removed with the stale folders at a later start.
    end;
end;

initialization
  Randomize;
  GStreams := TDictionary<Int64, TStreamEntry>.Create;
  GStreamLock := TCriticalSection.Create;
  GPending := TDictionary<Int64, TPendingOpen>.Create;

finalization
  ReleaseAllStreams;
  GPending.Free;
  GStreamLock.Free;
  GStreams.Free;

end.
