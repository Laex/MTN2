unit uZipVfs;

{ ZIP Nested VFS (Stage 14). Lists / reads / extracts / packs via System.Zip.
  Grammar: file:///…/archive.zip!/path and nested …zip!/inner.zip!/…
  Write/delete supported for outer file-backed ZIP only (not nested layers).
  Listing: CD cached as prefix tree (invalidate on size/mtime and after writes). }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TZipVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
  public
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

/// <summary>Sum files under an archive folder URI (background-safe).</summary>
procedure CalculateZipFolderSize(const AURI: string; ACancel: IJobCancelToken;
  out ABytes: Int64; out AFiles, AFolders: Integer; out AError: TVfsError);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  System.Generics.Collections, System.Generics.Defaults, Winapi.Windows,
  uZipArchiveCache, uZipNames;

{ TZipLayer / TVfsEntryComparer live in uZipArchiveCache (single ownership). }

procedure QueueList(const AOnDone: TVfsListCallback; const AItems: TArray<TVfsEntry>;
  const AError: TVfsError);
var
  Items: TArray<TVfsEntry>;
  Err: TVfsError;
  Cb: TVfsListCallback;
begin
  Items := AItems;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Items, Err);
    end);
end;

procedure QueueBool(const AOnDone: TVfsBoolCallback; AOk: Boolean; const AError: TVfsError);
var
  Ok: Boolean;
  Err: TVfsError;
  Cb: TVfsBoolCallback;
begin
  Ok := AOk;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Ok, Err);
    end);
end;

procedure QueueText(const AOnDone: TVfsTextCallback; const AText: string;
  AEncoding: TTextFileEncoding; const AError: TVfsError);
var
  Text: string;
  Enc: TTextFileEncoding;
  Err: TVfsError;
  Cb: TVfsTextCallback;
begin
  Text := AText;
  Enc := AEncoding;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Text, Enc, Err);
    end);
end;

procedure QueueBytes(const AOnDone: TVfsBytesCallback; const ABytes: TBytes;
  const AError: TVfsError);
var
  Bytes: TBytes;
  Err: TVfsError;
  Cb: TVfsBytesCallback;
begin
  Bytes := ABytes;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Bytes, Err);
    end);
end;

procedure QueueExists(const AOnDone: TVfsExistsCallback; AExists, AIsDir: Boolean;
  const AError: TVfsError);
var
  Ex, IsDir: Boolean;
  Err: TVfsError;
  Cb: TVfsExistsCallback;
begin
  Ex := AExists;
  IsDir := AIsDir;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Ex, IsDir, Err);
    end);
end;

procedure QueueProgress(const AOnProgress: TVfsProgressCallback; ADone, ATotal: Int64;
  const AName: string);
var
  D, T: Int64;
  N: string;
  Cb: TVfsProgressCallback;
begin
  if not Assigned(AOnProgress) then
    Exit;
  D := ADone;
  T := ATotal;
  N := AName;
  Cb := AOnProgress;
  TThread.Queue(nil,
    procedure
    begin
      // Pack/unpack has no reliable per-file byte breakdown here (pack
      // counts files, unpack counts archive-wide bytes) — leave the item
      // fields empty so the job UI falls back to the tree-cumulative
      // ADone/ATotal for its per-file bar, same as before this callback
      // grew the item-level parameters.
      Cb(D, T, N, 0, 0, '', '');
    end);
end;

function FindZipEntryIndex(AZip: TZipFile; const AName: string): Integer;
var
  I: Integer;
  Want, Have: string;
begin
  Want := NormZipName(AName);
  for I := 0 to AZip.FileCount - 1 do
  begin
    Have := NormZipName(AZip.FileNames[I]);
    if SameText(Have, Want) then
      Exit(I);
  end;
  Result := -1;
end;

function EntryIsDirectory(AZip: TZipFile; AIndex: Integer): Boolean;
var
  N: string;
  H: TZipHeader;
begin
  N := AZip.FileNames[AIndex];
  if (Length(N) > 0) and ((N[Length(N)] = '/') or (N[Length(N)] = '\')) then
    Exit(True);
  H := AZip.FileInfo[AIndex];
  Result := (H.ExternalAttributes and $10) <> 0; // DOS dir bit when present
end;

{ Central-directory listing cache: one full CD parse per archive stamp,
  then O(children) lookups by directory prefix. Thread-safe. }

const
  CZipCdCacheMaxEntries = 12;

type
  TZipCdCache = class
    PathKey: string;
    FileSize: Int64;
    FileTime: TDateTime;
    LastUsed: UInt64;
    /// <summary>Lowercase parent prefix ('' = root) → sorted children.</summary>
    Children: TObjectDictionary<string, TList<TVfsEntry>>;
    /// <summary>Lowercase full entry path → is directory (for Exists).</summary>
    Entries: TDictionary<string, Boolean>;
    constructor Create;
    destructor Destroy; override;
  end;

  TZipCdCacheHub = class
  strict private
    class var FLock: TObject;
    class var FMap: TObjectDictionary<string, TZipCdCache>;
    class var FUseTick: UInt64;
    class function NormalizePathKey(const APath: string): string; static;
    class function TryFileStamp(const APath: string; out ASize: Int64;
      out ATime: TDateTime): Boolean; static;
    class function BuildFromZip(AZip: TZipFile; const APathKey: string;
      ASize: Int64; ATime: TDateTime; ACancel: IJobCancelToken;
      out AError: TVfsError): TZipCdCache; static;
    class procedure Touch(ACache: TZipCdCache); static;
    class procedure PruneLocked; static;
  public
    class constructor Create;
    class destructor Destroy;
    class function GetOrBuild(const APath: string; ACancel: IJobCancelToken;
      out ACache: TZipCdCache; out AError: TVfsError): Boolean; static;
    class function ListPrefix(ACache: TZipCdCache; const APrefix: string;
      out AItems: TArray<TVfsEntry>): Boolean; static;
    class function EntryExists(ACache: TZipCdCache; const APath: string;
      out AIsDir: Boolean): Boolean; static;
    /// <summary>List one directory level from a file-backed zip (cached CD tree).</summary>
    class function ListFileZip(const AZipPath, APrefix: string; ACancel: IJobCancelToken;
      out AItems: TArray<TVfsEntry>; out AError: TVfsError): Boolean; static;
    class function ExistsInFileZip(const AZipPath, AInnerPath: string;
      ACancel: IJobCancelToken; out AExists, AIsDir: Boolean;
      out AError: TVfsError): Boolean; static;
    class procedure Invalidate(const AZipPath: string); static;
    class function SumPrefix(ACache: TZipCdCache; const APrefix: string;
      ACancel: IJobCancelToken; out ABytes: Int64; out AFiles, AFolders: Integer;
      out AError: TVfsError): Boolean; static;
  end;

function MakeDirEntry(const AName: string): TVfsEntry;
begin
  Result.Name := AName;
  Result.Extension := '';
  Result.IsDirectory := True;
  Result.IsHidden := False;
  Result.IsReadOnly := False;
  Result.IsSystem := False;
  Result.IsArchive := False;
  Result.IsCompressed := False;
  Result.IsEncrypted := False;
  Result.IsTemporary := False;
  Result.IsOffline := False;
  Result.IsLink := False;
  Result.TargetURI := '';
  Result.Size := -1;
  Result.CreationTime := 0;
  Result.ModificationTime := 0;
  Result.AccessTime := 0;
end;

function MakeFileEntry(const AName: string; const AHeader: TZipHeader): TVfsEntry;
var
  DT: TDateTime;
begin
  Result.Name := AName;
  Result.Extension := LowerCase(TPath.GetExtension(AName));
  Result.IsDirectory := False;
  Result.IsHidden := False;
  Result.IsReadOnly := False;
  Result.IsSystem := False;
  Result.IsArchive := False;
  Result.IsCompressed := False;
  Result.IsEncrypted := False;
  Result.IsTemporary := False;
  Result.IsOffline := False;
  Result.IsLink := False;
  Result.TargetURI := '';
  Result.Size := AHeader.UncompressedSize;
  try
    DT := FileDateToDateTime(LongInt(AHeader.ModifiedDateTime));
  except
    DT := 0;
  end;
  Result.CreationTime := DT;
  Result.ModificationTime := DT;
  Result.AccessTime := DT;
end;

constructor TZipCdCache.Create;
begin
  inherited Create;
  Children := TObjectDictionary<string, TList<TVfsEntry>>.Create([doOwnsValues]);
  Entries := TDictionary<string, Boolean>.Create;
end;

destructor TZipCdCache.Destroy;
begin
  Children.Free;
  Entries.Free;
  inherited Destroy;
end;

class constructor TZipCdCacheHub.Create;
begin
  FLock := TObject.Create;
  FMap := TObjectDictionary<string, TZipCdCache>.Create([doOwnsValues]);
  FUseTick := 0;
end;

class destructor TZipCdCacheHub.Destroy;
begin
  FreeAndNil(FMap);
  FreeAndNil(FLock);
end;

class function TZipCdCacheHub.NormalizePathKey(const APath: string): string;
begin
  Result := AnsiLowerCase(ExcludeTrailingPathDelimiter(ExpandFileName(APath)));
end;

class function TZipCdCacheHub.TryFileStamp(const APath: string; out ASize: Int64;
  out ATime: TDateTime): Boolean;
begin
  Result := False;
  ASize := 0;
  ATime := 0;
  if not TFile.Exists(APath) then
    Exit;
  try
    ASize := TFile.GetSize(APath);
    ATime := TFile.GetLastWriteTime(APath);
    Result := True;
  except
    Result := False;
  end;
end;

class procedure TZipCdCacheHub.Touch(ACache: TZipCdCache);
begin
  Inc(FUseTick);
  ACache.LastUsed := FUseTick;
end;

class procedure TZipCdCacheHub.PruneLocked;
var
  OldestKey: string;
  OldestTick: UInt64;
  Pair: TPair<string, TZipCdCache>;
begin
  while FMap.Count > CZipCdCacheMaxEntries do
  begin
    OldestKey := '';
    OldestTick := High(UInt64);
    for Pair in FMap do
      if Pair.Value.LastUsed < OldestTick then
      begin
        OldestTick := Pair.Value.LastUsed;
        OldestKey := Pair.Key;
      end;
    if OldestKey = '' then
      Break;
    FMap.Remove(OldestKey);
  end;
end;

class function TZipCdCacheHub.BuildFromZip(AZip: TZipFile; const APathKey: string;
  ASize: Int64; ATime: TDateTime; ACancel: IJobCancelToken;
  out AError: TVfsError): TZipCdCache;
var
  I, Slash: Integer;
  Name, Rest, Parent, Child, Full, ParentKey, ChildKey: string;
  IsDir: Boolean;
  H: TZipHeader;
  Seen: TDictionary<string, Boolean>;
  Pair: TPair<string, TList<TVfsEntry>>;

  procedure EnsureDirChild(const AParentKey, AChildName: string);
  var
    L: TList<TVfsEntry>;
    SeenKey: string;
    J: Integer;
  begin
    if AChildName = '' then
      Exit;
    SeenKey := AParentKey + #1 + LowerCase(AChildName);
    if Seen.ContainsKey(SeenKey) then
      Exit;
    Seen.Add(SeenKey, True);
    if not Result.Children.TryGetValue(AParentKey, L) then
    begin
      L := TList<TVfsEntry>.Create;
      Result.Children.Add(AParentKey, L);
    end;
    for J := 0 to L.Count - 1 do
      if SameText(L[J].Name, AChildName) then
        Exit;
    L.Add(MakeDirEntry(AChildName));
    Full := AChildName;
    if AParentKey <> '' then
      Full := AParentKey + '/' + LowerCase(AChildName)
    else
      Full := LowerCase(AChildName);
    Result.Entries.AddOrSetValue(Full, True);
  end;

  procedure AddFileChild(const AParentKey, AChildName: string; const AHeader: TZipHeader);
  var
    L: TList<TVfsEntry>;
    SeenKey, FullPath: string;
    J: Integer;
  begin
    if AChildName = '' then
      Exit;
    SeenKey := AParentKey + #1 + LowerCase(AChildName);
    if Seen.ContainsKey(SeenKey) then
      Exit;
    Seen.Add(SeenKey, True);
    if not Result.Children.TryGetValue(AParentKey, L) then
    begin
      L := TList<TVfsEntry>.Create;
      Result.Children.Add(AParentKey, L);
    end;
    for J := 0 to L.Count - 1 do
      if SameText(L[J].Name, AChildName) then
        Exit;
    L.Add(MakeFileEntry(AChildName, AHeader));
    if AParentKey <> '' then
      FullPath := AParentKey + '/' + LowerCase(AChildName)
    else
      FullPath := LowerCase(AChildName);
    Result.Entries.AddOrSetValue(FullPath, False);
  end;

begin
  AError := TVfsError.Ok;
  Result := TZipCdCache.Create;
  Result.PathKey := APathKey;
  Result.FileSize := ASize;
  Result.FileTime := ATime;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for I := 0 to AZip.FileCount - 1 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
        FreeAndNil(Result);
        Exit;
      end;
      if IsUnsafeZipName(AZip.FileNames[I]) then
        Continue;
      Name := NormZipName(AZip.FileNames[I]);
      if Name = '' then
        Continue;
      IsDir := EntryIsDirectory(AZip, I);
      H := AZip.FileInfo[I];
      Parent := '';
      Rest := Name;
      while Rest <> '' do
      begin
        Slash := Pos('/', Rest);
        if Slash > 0 then
        begin
          Child := Copy(Rest, 1, Slash - 1);
          Rest := Copy(Rest, Slash + 1, MaxInt);
          ParentKey := LowerCase(Parent);
          EnsureDirChild(ParentKey, Child);
          if Parent = '' then
            Parent := Child
          else
            Parent := Parent + '/' + Child;
        end
        else
        begin
          Child := Rest;
          Rest := '';
          ParentKey := LowerCase(Parent);
          if IsDir then
            EnsureDirChild(ParentKey, Child)
          else
            AddFileChild(ParentKey, Child, H);
        end;
      end;
      // Mark full path as present (dirs implied by nested files too).
      ChildKey := LowerCase(Name);
      if not Result.Entries.ContainsKey(ChildKey) then
        Result.Entries.Add(ChildKey, IsDir)
      else if IsDir then
        Result.Entries[ChildKey] := True;
    end;
    for Pair in Result.Children do
      Pair.Value.Sort(TVfsEntryComparer.Create);
  finally
    Seen.Free;
  end;
end;

class function TZipCdCacheHub.GetOrBuild(const APath: string; ACancel: IJobCancelToken;
  out ACache: TZipCdCache; out AError: TVfsError): Boolean;
var
  Key: string;
  Size: Int64;
  Time: TDateTime;
  Existing, Built: TZipCdCache;
  Zip: TZipFile;
begin
  Result := False;
  ACache := nil;
  AError := TVfsError.Ok;
  Key := NormalizePathKey(APath);
  if Key = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid archive path', '');
    Exit;
  end;
  if not TryFileStamp(APath, Size, Time) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Archive not found', PathToFileUri(APath));
    Exit;
  end;
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(APath));
    Exit;
  end;

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(Key, Existing) then
      if (Existing.FileSize = Size) and (Existing.FileTime = Time) then
      begin
        Touch(Existing);
        ACache := Existing;
        Exit(True);
      end
      else
        FMap.Remove(Key);
  finally
    TMonitor.Exit(FLock);
  end;

  Zip := TZipFile.Create;
  try
    try
      Zip.Open(APath, zmRead);
    except
      on E: Exception do
      begin
        AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(APath));
        Exit;
      end;
    end;
    Built := BuildFromZip(Zip, Key, Size, Time, ACancel, AError);
    if Built = nil then
      Exit;
  finally
    Zip.Free;
  end;

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(Key, Existing) then
      if (Existing.FileSize = Size) and (Existing.FileTime = Time) then
      begin
        Built.Free;
        Touch(Existing);
        ACache := Existing;
        Exit(True);
      end
      else
        FMap.Remove(Key);
    Touch(Built);
    FMap.Add(Key, Built);
    PruneLocked;
    ACache := Built;
    Result := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TZipCdCacheHub.ListPrefix(ACache: TZipCdCache; const APrefix: string;
  out AItems: TArray<TVfsEntry>): Boolean;
var
  Key: string;
  List: TList<TVfsEntry>;
begin
  Result := False;
  SetLength(AItems, 0);
  if ACache = nil then
    Exit;
  Key := LowerCase(NormZipName(APrefix));
  TMonitor.Enter(FLock);
  try
    Touch(ACache);
    if not ACache.Children.TryGetValue(Key, List) then
      Exit(True); // empty folder is valid
    AItems := List.ToArray;
    Result := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TZipCdCacheHub.EntryExists(ACache: TZipCdCache; const APath: string;
  out AIsDir: Boolean): Boolean;
var
  Key: string;
begin
  Result := False;
  AIsDir := False;
  if ACache = nil then
    Exit;
  Key := LowerCase(NormZipName(APath));
  if Key = '' then
  begin
    AIsDir := True;
    Exit(True);
  end;
  if ACache.Entries.TryGetValue(Key, AIsDir) then
    Exit(True);
  // Implied directory: has children under this prefix.
  if ACache.Children.ContainsKey(Key) then
  begin
    AIsDir := True;
    Exit(True);
  end;
end;

class function TZipCdCacheHub.ListFileZip(const AZipPath, APrefix: string;
  ACancel: IJobCancelToken; out AItems: TArray<TVfsEntry>;
  out AError: TVfsError): Boolean;
var
  Key, PrefKey: string;
  Size: Int64;
  Time: TDateTime;
  Existing, Built: TZipCdCache;
  Zip: TZipFile;
  List: TList<TVfsEntry>;

  function CopyChildren(ACache: TZipCdCache): Boolean;
  begin
    Touch(ACache);
    if ACache.Children.TryGetValue(PrefKey, List) then
      AItems := List.ToArray
    else
      SetLength(AItems, 0);
    Result := True;
  end;

begin
  Result := False;
  SetLength(AItems, 0);
  AError := TVfsError.Ok;
  Key := NormalizePathKey(AZipPath);
  PrefKey := LowerCase(NormZipName(APrefix));
  if Key = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid archive path', '');
    Exit;
  end;
  if not TryFileStamp(AZipPath, Size, Time) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Archive not found', PathToFileUri(AZipPath));
    Exit;
  end;
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(AZipPath));
    Exit;
  end;

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(Key, Existing) and (Existing.FileSize = Size) and
       (Existing.FileTime = Time) then
      Exit(CopyChildren(Existing));
  finally
    TMonitor.Exit(FLock);
  end;

  Zip := TZipFile.Create;
  try
    try
      Zip.Open(AZipPath, zmRead);
    except
      on E: Exception do
      begin
        AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(AZipPath));
        Exit;
      end;
    end;
    Built := BuildFromZip(Zip, Key, Size, Time, ACancel, AError);
    if Built = nil then
      Exit;
  finally
    Zip.Free;
  end;

  TMonitor.Enter(FLock);
  try
    if FMap.TryGetValue(Key, Existing) and (Existing.FileSize = Size) and
       (Existing.FileTime = Time) then
    begin
      Built.Free;
      Built := nil;
      Result := CopyChildren(Existing);
    end
    else
    begin
      if FMap.ContainsKey(Key) then
        FMap.Remove(Key);
      Touch(Built);
      FMap.Add(Key, Built);
      PruneLocked;
      Result := CopyChildren(Built);
      Built := nil; // owned by map
    end;
  finally
    TMonitor.Exit(FLock);
    Built.Free;
  end;
end;

class function TZipCdCacheHub.ExistsInFileZip(const AZipPath, AInnerPath: string;
  ACancel: IJobCancelToken; out AExists, AIsDir: Boolean;
  out AError: TVfsError): Boolean;
var
  Warm: TArray<TVfsEntry>;
  Key: string;
  Size: Int64;
  Time: TDateTime;
  Cache: TZipCdCache;
begin
  Result := False;
  AExists := False;
  AIsDir := False;
  // Warm / rebuild CD tree (copies root; cheap vs re-open).
  if not ListFileZip(AZipPath, '', ACancel, Warm, AError) then
    Exit;
  Key := NormalizePathKey(AZipPath);
  if not TryFileStamp(AZipPath, Size, Time) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Archive not found', PathToFileUri(AZipPath));
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FMap.TryGetValue(Key, Cache) or (Cache.FileSize <> Size) or
       (Cache.FileTime <> Time) then
    begin
      AError := TVfsError.Make(vecIOError, 'Archive cache miss', PathToFileUri(AZipPath));
      Exit;
    end;
    Touch(Cache);
    AExists := EntryExists(Cache, AInnerPath, AIsDir);
    Result := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TZipCdCacheHub.Invalidate(const AZipPath: string);
var
  Key: string;
begin
  Key := NormalizePathKey(AZipPath);
  if Key = '' then
    Exit;
  TMonitor.Enter(FLock);
  try
    if FMap.ContainsKey(Key) then
      FMap.Remove(Key);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TZipCdCacheHub.SumPrefix(ACache: TZipCdCache; const APrefix: string;
  ACancel: IJobCancelToken; out ABytes: Int64; out AFiles, AFolders: Integer;
  out AError: TVfsError): Boolean;
var
  Stack: TStack<string>;
  Key, ChildKey: string;
  List: TList<TVfsEntry>;
  E: TVfsEntry;
begin
  Result := False;
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  AError := TVfsError.Ok;
  if ACache = nil then
  begin
    AError := TVfsError.Make(vecIOError, 'Archive cache miss', '');
    Exit;
  end;
  Stack := TStack<string>.Create;
  try
    TMonitor.Enter(FLock);
    try
      Touch(ACache);
      Stack.Push(LowerCase(NormZipName(APrefix)));
      while Stack.Count > 0 do
      begin
        if JobCancelRequested(ACancel) then
        begin
          AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
          Exit;
        end;
        Key := Stack.Pop;
        if not ACache.Children.TryGetValue(Key, List) then
          Continue;
        for E in List do
        begin
          if E.IsDirectory then
          begin
            Inc(AFolders);
            if Key = '' then
              ChildKey := LowerCase(E.Name)
            else
              ChildKey := Key + '/' + LowerCase(E.Name);
            Stack.Push(ChildKey);
          end
          else
          begin
            Inc(AFiles);
            if E.Size > 0 then
              Inc(ABytes, E.Size);
          end;
        end;
      end;
      Result := True;
    finally
      TMonitor.Exit(FLock);
    end;
  finally
    Stack.Free;
  end;
end;

procedure FreeZipStack(var AStack: TArray<TZipLayer>);
var
  I: Integer;
begin
  for I := High(AStack) downto 0 do
    AStack[I].Free;
  SetLength(AStack, 0);
end;

function OpenZipStack(const ABasePath: string; const ASegments: TArray<string>;
  ACancel: IJobCancelToken; out AStack: TArray<TZipLayer>;
  out AListPrefix: string; out AError: TVfsError): Boolean;
var
  Layer: TZipLayer;
  I, Idx, LastZipSeg: Integer;
  EntryName: string;
  MS: TMemoryStream;
  Local: TStream;
  LH: TZipHeader;
begin
  Result := False;
  SetLength(AStack, 0);
  AListPrefix := '';
  AError := TVfsError.Ok;
  if ABasePath = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', '');
    Exit;
  end;
  if not TFile.Exists(ABasePath) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Archive not found', PathToFileUri(ABasePath));
    Exit;
  end;
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ABasePath));
    Exit;
  end;

  Layer := TZipLayer.Create;
  try
    Layer.OwnStream := nil;
    Layer.Zip := TZipFile.Create;
    Layer.Zip.Open(ABasePath, zmRead);
  except
    on E: Exception do
    begin
      Layer.Free;
      AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(ABasePath));
      Exit;
    end;
  end;
  SetLength(AStack, 1);
  AStack[0] := Layer;

  // Segments: [0..N-2] are nested zip entry paths; last is path inside innermost.
  // If last is empty → list root of innermost.
  if Length(ASegments) = 0 then
  begin
    AListPrefix := '';
    Exit(True);
  end;

  LastZipSeg := Length(ASegments) - 2; // may be -1 when single segment = path only
  for I := 0 to LastZipSeg do
  begin
    if JobCancelRequested(ACancel) then
    begin
      AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(ABasePath));
      FreeZipStack(AStack);
      Exit;
    end;
    EntryName := ASegments[I];
    if (EntryName = '') or IsUnsafeZipName(EntryName) then
    begin
      AError := TVfsError.Make(vecInvalidURI, 'Invalid archive path', PathToFileUri(ABasePath));
      FreeZipStack(AStack);
      Exit;
    end;
    Idx := FindZipEntryIndex(AStack[High(AStack)].Zip, EntryName);
    if Idx < 0 then
    begin
      AError := TVfsError.Make(vecNotFound, 'Entry not found: ' + EntryName,
        PathToFileUri(ABasePath));
      FreeZipStack(AStack);
      Exit;
    end;
    if EntryIsDirectory(AStack[High(AStack)].Zip, Idx) then
    begin
      AError := TVfsError.Make(vecNotSupported, 'Not a zip entry', PathToFileUri(ABasePath));
      FreeZipStack(AStack);
      Exit;
    end;
    MS := TMemoryStream.Create;
    try
      AStack[High(AStack)].Zip.Read(Idx, Local, LH);
      try
        MS.CopyFrom(Local, 0);
      finally
        Local.Free;
      end;
      MS.Position := 0;
      Layer := TZipLayer.Create;
      Layer.OwnStream := MS;
      MS := nil;
      Layer.Zip := TZipFile.Create;
      try
        Layer.Zip.Open(Layer.OwnStream, zmRead);
      except
        on E: Exception do
        begin
          Layer.Free;
          AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(ABasePath));
          FreeZipStack(AStack);
          Exit;
        end;
      end;
      SetLength(AStack, Length(AStack) + 1);
      AStack[High(AStack)] := Layer;
    finally
      MS.Free;
    end;
  end;

  AListPrefix := NormZipName(ASegments[High(ASegments)]);
  Result := True;
end;

procedure SumZipEntries(AZip: TZipFile; const APrefix: string;
  ACancel: IJobCancelToken; out ABytes: Int64; out AFiles, AFolders: Integer;
  out AError: TVfsError);
var
  Pref, Name, Rest: string;
  I, Slash: Integer;
  Dirs: TDictionary<string, Boolean>;

  procedure MarkDir(const ARel: string);
  var
    S, Seg, Path: string;
    P: Integer;
  begin
    S := NormZipName(ARel);
    if S = '' then
      Exit;
    Path := '';
    while S <> '' do
    begin
      P := Pos('/', S);
      if P > 0 then
      begin
        Seg := Copy(S, 1, P - 1);
        S := Copy(S, P + 1, MaxInt);
      end
      else
      begin
        Seg := S;
        S := '';
      end;
      if Seg = '' then
        Continue;
      if Path = '' then
        Path := LowerCase(Seg)
      else
        Path := Path + '/' + LowerCase(Seg);
      if not Dirs.ContainsKey(Path) then
      begin
        Dirs.Add(Path, True);
        Inc(AFolders);
      end;
    end;
  end;

begin
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  AError := TVfsError.Ok;
  Pref := NormZipName(APrefix);
  if Pref <> '' then
    Pref := Pref + '/';
  Dirs := TDictionary<string, Boolean>.Create;
  try
    for I := 0 to AZip.FileCount - 1 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
        Exit;
      end;
      if IsUnsafeZipName(AZip.FileNames[I]) then
        Continue;
      Name := NormZipName(AZip.FileNames[I]);
      if not ZipRestAfterPrefix(Name, Pref, Rest) then
        Continue;
      if EntryIsDirectory(AZip, I) then
        MarkDir(Rest)
      else
      begin
        Inc(AFiles);
        Inc(ABytes, AZip.FileInfo[I].UncompressedSize);
        Slash := LastDelimiter('/', Rest);
        if Slash > 0 then
          MarkDir(Copy(Rest, 1, Slash - 1));
      end;
    end;
  finally
    Dirs.Free;
  end;
end;

procedure CalculateZipFolderSize(const AURI: string; ACancel: IJobCancelToken;
  out ABytes: Int64; out AFiles, AFolders: Integer; out AError: TVfsError);
var
  Base, Path, Pref: string;
  Segs: TArray<string>;
  Cache: TZipCdCache;
  Stack: TArray<TZipLayer>;
begin
  ABytes := 0;
  AFiles := 0;
  AFolders := 0;
  AError := TVfsError.Ok;
  AError.URI := AURI;
  if not HasArchiveChain(AURI) then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Not an archive URI', AURI);
    Exit;
  end;
  if not SplitArchiveUri(AURI, Base, Segs) then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', AURI);
    Exit;
  end;
  Path := FileUriToPath(Base);
  if Length(Segs) < 2 then
  begin
    if Length(Segs) = 0 then
      Pref := ''
    else
      Pref := Segs[0];
    if not TZipCdCacheHub.GetOrBuild(Path, ACancel, Cache, AError) then
      Exit;
    if not TZipCdCacheHub.SumPrefix(Cache, Pref, ACancel, ABytes, AFiles,
      AFolders, AError) then
      Exit;
    if AError.URI = '' then
      AError.URI := AURI;
    Exit;
  end;
  if not OpenZipStack(Path, Segs, ACancel, Stack, Pref, AError) then
    Exit;
  try
    SumZipEntries(Stack[High(Stack)].Zip, Pref, ACancel, ABytes, AFiles,
      AFolders, AError);
    if AError.URI = '' then
      AError.URI := AURI;
  finally
    FreeZipStack(Stack);
  end;
end;

procedure ListZipPrefix(AZip: TZipFile; const APrefix: string;
  ACancel: IJobCancelToken; out AItems: TArray<TVfsEntry>; out AError: TVfsError);
var
  Pref, Name, Rest, Child: string;
  I, Slash: Integer;
  Dirs: TDictionary<string, Boolean>;
  List: TList<TVfsEntry>;
  E: TVfsEntry;
  H: TZipHeader;
  DT: TDateTime;
begin
  SetLength(AItems, 0);
  AError := TVfsError.Ok;
  Pref := NormZipName(APrefix);
  if Pref <> '' then
    Pref := Pref + '/';

  Dirs := TDictionary<string, Boolean>.Create;
  List := TList<TVfsEntry>.Create;
  try
    for I := 0 to AZip.FileCount - 1 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
        Exit;
      end;
      Name := NormZipName(AZip.FileNames[I]);
      if IsUnsafeZipName(AZip.FileNames[I]) then
        Continue;
      if not ZipRestAfterPrefix(Name, Pref, Rest) then
        Continue;
      Slash := Pos('/', Rest);
      if Slash > 0 then
      begin
        Child := Copy(Rest, 1, Slash - 1);
        if (Child <> '') and not Dirs.ContainsKey(LowerCase(Child)) then
        begin
          Dirs.Add(LowerCase(Child), True);
          E.Name := Child;
          E.IsDirectory := True;
          E.Extension := '';
          E.IsHidden := False;
          E.IsReadOnly := False;
          E.IsSystem := False;
          E.IsArchive := False;
          E.IsCompressed := False;
          E.IsEncrypted := False;
          E.IsTemporary := False;
          E.IsOffline := False;
          E.IsLink := False;
          E.TargetURI := '';
          E.Size := -1;
          E.CreationTime := 0;
          E.ModificationTime := 0;
          E.AccessTime := 0;
          List.Add(E);
        end;
      end
      else if not EntryIsDirectory(AZip, I) then
      begin
        H := AZip.FileInfo[I];
        E.Name := Rest;
        E.Extension := LowerCase(TPath.GetExtension(Rest));
        E.IsDirectory := False;
        E.IsHidden := False;
        E.IsReadOnly := False;
        E.IsSystem := False;
        E.IsArchive := False;
        E.IsCompressed := False;
        E.IsEncrypted := False;
        E.IsTemporary := False;
        E.IsOffline := False;
        E.IsLink := False;
        E.TargetURI := '';
        E.Size := H.UncompressedSize;
        try
          DT := FileDateToDateTime(LongInt(H.ModifiedDateTime));
        except
          DT := 0;
        end;
        E.CreationTime := DT;
        E.ModificationTime := DT;
        E.AccessTime := DT;
        List.Add(E);
      end
      else
      begin
        // Explicit directory entry
        Child := Rest;
        if (Child <> '') and not Dirs.ContainsKey(LowerCase(Child)) then
        begin
          Dirs.Add(LowerCase(Child), True);
          E.Name := Child;
          E.Extension := '';
          E.IsDirectory := True;
          E.IsHidden := False;
          E.IsReadOnly := False;
          E.IsSystem := False;
          E.IsArchive := False;
          E.IsCompressed := False;
          E.IsEncrypted := False;
          E.IsTemporary := False;
          E.IsOffline := False;
          E.IsLink := False;
          E.TargetURI := '';
          E.Size := -1;
          E.CreationTime := 0;
          E.ModificationTime := 0;
          E.AccessTime := 0;
          List.Add(E);
        end;
      end;
    end;
    List.Sort(TVfsEntryComparer.Create);
    AItems := List.ToArray;
  finally
    List.Free;
    Dirs.Free;
  end;
end;

function EntryExists(AZip: TZipFile; const APath: string; out AIsDir: Boolean): Boolean;
var
  Pref, Name: string;
  I: Integer;
begin
  Result := False;
  AIsDir := False;
  Pref := NormZipName(APath);
  if Pref = '' then
  begin
    Result := True;
    AIsDir := True;
    Exit;
  end;
  for I := 0 to AZip.FileCount - 1 do
  begin
    Name := NormZipName(AZip.FileNames[I]);
    if SameText(Name, Pref) then
    begin
      AIsDir := EntryIsDirectory(AZip, I);
      Exit(True);
    end;
  end;
  Pref := Pref + '/';
  for I := 0 to AZip.FileCount - 1 do
  begin
    Name := NormZipName(AZip.FileNames[I]);
    if Name.StartsWith(Pref, True) then
    begin
      AIsDir := True;
      Exit(True);
    end;
  end;
end;

procedure TZipVirtualFileSystem.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsListCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Stack: TArray<TZipLayer>;
      Pref: string;
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      Path: string;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        if not HasArchiveChain(URI) then
          Err := TVfsError.Make(vecInvalidURI, 'Not an archive URI', URI)
        else if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else
        begin
          Path := FileUriToPath(Base);
          // Single-layer (file.zip!/path): cached CD tree. Nested zips still open.
          if Length(Segs) < 2 then
          begin
            if Length(Segs) = 0 then
              Pref := ''
            else
              Pref := Segs[0];
            if not TZipCdCacheHub.ListFileZip(Path, Pref, Cancel, Items, Err) then
              { Err already set }
            else if Err.URI = '' then
              Err.URI := URI;
          end
          else if OpenZipStack(Path, Segs, Cancel, Stack, Pref, Err) then
          try
            ListZipPrefix(Stack[High(Stack)].Zip, Pref, Cancel, Items, Err);
            if Err.URI = '' then
              Err.URI := URI;
          finally
            FreeZipStack(Stack);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueList(OnDone, Items, Err);
    end).Start;
end;

procedure ExtractEntryToFile(AZip: TZipFile; AIndex: Integer; const ADestPath: string;
  ACancel: IJobCancelToken; var AError: TVfsError); forward;

function OpenZipForWrite(const AZipPath: string; out AZip: TZipFile;
  out AError: TVfsError): Boolean;
begin
  Result := False;
  AZip := nil;
  AError := TVfsError.Ok;
  try
    AZip := TZipFile.Create;
    if TFile.Exists(AZipPath) then
      AZip.Open(AZipPath, zmReadWrite)
    else
    begin
      ForceDirectories(TPath.GetDirectoryName(AZipPath));
      AZip.Open(AZipPath, zmWrite);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      FreeAndNil(AZip);
      AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(AZipPath));
    end;
  end;
end;

procedure DeleteZipEntryName(AZip: TZipFile; const AEntry: string);
var
  Idx: Integer;
  Want, Have: string;
begin
  Want := NormZipName(AEntry);
  if Want = '' then
    Exit;
  // Prefer exact name; also try trailing slash for dirs.
  Idx := AZip.IndexOf(Want);
  if Idx < 0 then
    Idx := AZip.IndexOf(Want + '/');
  if Idx < 0 then
  begin
    for Idx := 0 to AZip.FileCount - 1 do
    begin
      Have := NormZipName(AZip.FileNames[Idx]);
      if SameText(Have, Want) then
      begin
        AZip.Delete(Idx);
        Exit;
      end;
    end;
    Exit;
  end;
  AZip.Delete(Idx);
end;

procedure DeleteZipPrefix(AZip: TZipFile; const APrefix: string;
  ACancel: IJobCancelToken; var AError: TVfsError);
var
  Pref: string;
  I: Integer;
  ToDelete: TList<Integer>;
begin
  Pref := NormZipName(APrefix);
  if Pref = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Cannot delete archive root', '');
    Exit;
  end;
  ToDelete := TList<Integer>.Create;
  try
    for I := 0 to AZip.FileCount - 1 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
        Exit;
      end;
      if ZipNameEqualsOrUnder(AZip.FileNames[I], Pref) then
        ToDelete.Add(I);
    end;
    if ToDelete.Count = 0 then
    begin
      AError := TVfsError.Make(vecNotFound, 'Not found', Pref);
      Exit;
    end;
    for I := ToDelete.Count - 1 downto 0 do
      AZip.Delete(ToDelete[I]);
  finally
    ToDelete.Free;
  end;
end;

procedure AddLocalFileToZip(AZip: TZipFile; const ALocalPath, AEntryName: string;
  AOverwrite: Boolean; var AError: TVfsError);
var
  Entry: string;
  Idx: Integer;
begin
  Entry := NormZipName(AEntryName);
  if (Entry = '') or IsUnsafeZipName(Entry) then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid archive entry', AEntryName);
    Exit;
  end;
  Idx := AZip.IndexOf(Entry);
  if Idx < 0 then
    Idx := AZip.IndexOf(StringReplace(Entry, '/', '\', [rfReplaceAll]));
  if Idx >= 0 then
  begin
    if not AOverwrite then
    begin
      AError := TVfsError.Make(vecAlreadyExists, 'Already exists', Entry);
      Exit;
    end;
    AZip.Delete(Idx);
  end;
  AZip.Add(ALocalPath, Entry);
end;

procedure AddLocalTreeToZip(AZip: TZipFile; const ALocalPath, AEntryPrefix: string;
  AOverwrite: Boolean; ACancel: IJobCancelToken; var ADone, ATotal: Int64;
  AOnProgress: TVfsProgressCallback; var AError: TVfsError);
var
  SR: TSearchRec;
  ChildLocal, ChildEntry, Pref: string;
begin
  Pref := NormZipName(AEntryPrefix);
  if JobCancelRequested(ACancel) then
  begin
    AError := TVfsError.Make(vecCancelled, 'Cancelled', ALocalPath);
    Exit;
  end;
  if TFile.Exists(ALocalPath) then
  begin
    if ATotal <= 0 then
      ATotal := 1;
    QueueProgress(AOnProgress, ADone, ATotal, TPath.GetFileName(ALocalPath));
    AddLocalFileToZip(AZip, ALocalPath, Pref, AOverwrite, AError);
    if AError.Code = vecOk then
      Inc(ADone);
    QueueProgress(AOnProgress, ADone, ATotal, TPath.GetFileName(ALocalPath));
    Exit;
  end;
  if not TDirectory.Exists(ALocalPath) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Source not found', ALocalPath);
    Exit;
  end;
  if Pref <> '' then
  try
    AZip.Add(ALocalPath, Pref + '/');
  except
    // Directory marker may already exist.
  end;
  if System.SysUtils.FindFirst(TPath.Combine(ALocalPath, '*'), faAnyFile, SR) = 0 then
  try
    repeat
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', ALocalPath);
        Exit;
      end;
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      ChildLocal := TPath.Combine(ALocalPath, SR.Name);
      if Pref = '' then
        ChildEntry := SR.Name
      else
        ChildEntry := Pref + '/' + SR.Name;
      if (SR.Attr and faDirectory) <> 0 then
        AddLocalTreeToZip(AZip, ChildLocal, ChildEntry, AOverwrite, ACancel,
          ADone, ATotal, AOnProgress, AError)
      else
      begin
        if ATotal <= 0 then
          ATotal := 1;
        QueueProgress(AOnProgress, ADone, ATotal, SR.Name);
        AddLocalFileToZip(AZip, ChildLocal, ChildEntry, AOverwrite, AError);
        if AError.Code = vecOk then
          Inc(ADone);
        QueueProgress(AOnProgress, ADone, ATotal, SR.Name);
      end;
      if AError.Code <> vecOk then
        Exit;
    until System.SysUtils.FindNext(SR) <> 0;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure TZipVirtualFileSystem.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Pref, Path: string;
      Err: TVfsError;
      Zip: TZipFile;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      try
        if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else if not ZipWriteAllowed(Segs) then
          Err := TVfsError.Make(vecNotSupported, 'Cannot modify nested archive', URI)
        else
        begin
          Path := FileUriToPath(Base);
          if Length(Segs) = 0 then
            Pref := ''
          else
            Pref := Segs[0];
          Pref := NormZipName(Pref);
          if Pref = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Cannot delete archive root', URI)
          else if OpenZipForWrite(Path, Zip, Err) then
          try
            DeleteZipPrefix(Zip, Pref, Cancel, Err);
            if Err.URI = '' then
              Err.URI := URI;
          finally
            Zip.Free;
            TZipCdCacheHub.Invalidate(Path);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Pref, Path, Entry: string;
      Err: TVfsError;
      Zip: TZipFile;
      Exists: Boolean;
      I: Integer;
      EmptyBytes: TBytes;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      try
        if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else if not ZipWriteAllowed(Segs) then
          Err := TVfsError.Make(vecNotSupported, 'Cannot modify nested archive', URI)
        else
        begin
          Path := FileUriToPath(Base);
          if Length(Segs) = 0 then
            Pref := ''
          else
            Pref := Segs[0];
          Entry := NormZipName(Pref);
          if Entry = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid folder name', URI)
          else if OpenZipForWrite(Path, Zip, Err) then
          try
            Exists := False;
            for I := 0 to Zip.FileCount - 1 do
              if SameText(NormZipName(Zip.FileNames[I]), Entry) or
                 NormZipName(Zip.FileNames[I]).StartsWith(Entry + '/', True) then
              begin
                Exists := True;
                Break;
              end;
            if Exists then
              Err := TVfsError.Make(vecAlreadyExists, 'Already exists', URI)
            else
            begin
              SetLength(EmptyBytes, 0);
              Zip.Add(EmptyBytes, Entry + '/');
            end;
          finally
            Zip.Free;
            TZipCdCacheHub.Invalidate(Path);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot move inside archive', AFromURI));
end;

procedure TZipVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Cannot write inside archive', AURI));
end;

procedure ExtractEntryToFile(AZip: TZipFile; AIndex: Integer; const ADestPath: string;
  ACancel: IJobCancelToken; var AError: TVfsError);
var
  Local, OutFS: TStream;
  Buf: TBytes;
  Got: Integer;
  LH: TZipHeader;
begin
  ForceDirectories(TPath.GetDirectoryName(ADestPath));
  AZip.Read(AIndex, Local, LH);
  try
    OutFS := TFileStream.Create(ADestPath, fmCreate);
    try
      SetLength(Buf, 64 * 1024);
      while True do
      begin
        if JobCancelRequested(ACancel) then
        begin
          AError := TVfsError.Make(vecCancelled, 'Cancelled', ADestPath);
          Exit;
        end;
        Got := Local.Read(Buf[0], Length(Buf));
        if Got <= 0 then
          Break;
        OutFS.WriteBuffer(Buf[0], Got);
      end;
    finally
      OutFS.Free;
    end;
  finally
    Local.Free;
  end;
end;

procedure CollectExtractJobs(AZip: TZipFile; const APrefix: string;
  const ADestRoot: string; ACancel: IJobCancelToken;
  AJobs: TList<TPair<Integer, string>>; var ATotal: Int64; var AError: TVfsError);
var
  Pref, Name, Rest, Dest: string;
  I: Integer;
  H: TZipHeader;
begin
  Pref := NormZipName(APrefix);
  if Pref = '' then
  begin
    // Extract whole zip content under DestRoot
    for I := 0 to AZip.FileCount - 1 do
    begin
      if JobCancelRequested(ACancel) then
      begin
        AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
        Exit;
      end;
      Name := NormZipName(AZip.FileNames[I]);
      if IsUnsafeZipName(AZip.FileNames[I]) or (Name = '') then
        Continue;
      if EntryIsDirectory(AZip, I) then
        Continue;
      Dest := TPath.Combine(ADestRoot, StringReplace(Name, '/', PathDelim, [rfReplaceAll]));
      AJobs.Add(TPair<Integer, string>.Create(I, Dest));
      H := AZip.FileInfo[I];
      Inc(ATotal, Int64(H.UncompressedSize));
    end;
    Exit;
  end;

  // Single file?
  I := FindZipEntryIndex(AZip, Pref);
  if (I >= 0) and not EntryIsDirectory(AZip, I) then
  begin
    Dest := ADestRoot;
    AJobs.Add(TPair<Integer, string>.Create(I, Dest));
    H := AZip.FileInfo[I];
    Inc(ATotal, Int64(H.UncompressedSize));
    Exit;
  end;

  // Directory prefix
  Pref := Pref + '/';
  for I := 0 to AZip.FileCount - 1 do
  begin
    if JobCancelRequested(ACancel) then
    begin
      AError := TVfsError.Make(vecCancelled, 'Cancelled', '');
      Exit;
    end;
    Name := NormZipName(AZip.FileNames[I]);
    if not ZipRestAfterPrefix(Name, Pref, Rest) then
      Continue;
    if EntryIsDirectory(AZip, I) then
      Continue;
    Dest := TPath.Combine(ADestRoot, StringReplace(Rest, '/', PathDelim, [rfReplaceAll]));
    AJobs.Add(TPair<Integer, string>.Create(I, Dest));
    H := AZip.FileInfo[I];
    Inc(ATotal, Int64(H.UncompressedSize));
  end;
end;

procedure TZipVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  Cancel: IJobCancelToken;
  OnProgress: TVfsProgressCallback;
  OnDone: TVfsBoolCallback;
  DoOverwrite: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;
  DoOverwrite := AOverwrite;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Stack: TArray<TZipLayer>;
      Pref, Path, Dest, LocalSrc, EntryName: string;
      Err: TVfsError;
      Jobs: TList<TPair<Integer, string>>;
      Total, Done: Int64;
      I: Integer;
      Pair: TPair<Integer, string>;
      Zip: TZipFile;
    begin
      Err := TVfsError.Ok;
      Err.URI := FromURI;
      try
        // Disk / file → archive (pack into zip).
        if HasArchiveChain(ToURI) and not HasArchiveChain(FromURI) then
        begin
          if not SplitArchiveUri(ToURI, Base, Segs) then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', ToURI)
          else if not ZipWriteAllowed(Segs) then
            Err := TVfsError.Make(vecNotSupported, 'Cannot modify nested archive', ToURI)
          else
          begin
            Path := FileUriToPath(Base);
            LocalSrc := FileUriToPath(FromURI);
            if LocalSrc = '' then
              Err := TVfsError.Make(vecInvalidURI, 'Invalid source', FromURI)
            else if Length(Segs) = 0 then
              EntryName := TPath.GetFileName(ExcludeTrailingPathDelimiter(LocalSrc))
            else
              EntryName := Segs[0];
            if OpenZipForWrite(Path, Zip, Err) then
            try
              Total := 1;
              Done := 0;
              AddLocalTreeToZip(Zip, LocalSrc, EntryName, DoOverwrite, Cancel,
                Done, Total, OnProgress, Err);
              if Err.URI = '' then
                Err.URI := ToURI;
            finally
              Zip.Free;
              TZipCdCacheHub.Invalidate(Path);
            end;
          end;
        end
        // Archive → disk (extract).
        else if HasArchiveChain(FromURI) and not HasArchiveChain(ToURI) then
        begin
          if not SplitArchiveUri(FromURI, Base, Segs) then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', FromURI)
          else
          begin
            Path := FileUriToPath(Base);
            Dest := FileUriToPath(ToURI);
            if Dest = '' then
              Err := TVfsError.Make(vecInvalidURI, 'Invalid destination', ToURI)
            else if OpenZipStack(Path, Segs, Cancel, Stack, Pref, Err) then
            try
              Jobs := TList<TPair<Integer, string>>.Create;
              try
                Total := 0;
                CollectExtractJobs(Stack[High(Stack)].Zip, Pref, Dest, Cancel, Jobs,
                  Total, Err);
                if Err.Code = vecOk then
                begin
                  if Jobs.Count = 0 then
                    Err := TVfsError.Make(vecNotFound, 'Nothing to extract', FromURI)
                  else
                  begin
                    if Total <= 0 then
                      Total := 1;
                    Done := 0;
                    for I := 0 to Jobs.Count - 1 do
                    begin
                      if JobCancelRequested(Cancel) then
                      begin
                        Err := TVfsError.Make(vecCancelled, 'Cancelled', FromURI);
                        Break;
                      end;
                      Pair := Jobs[I];
                      QueueProgress(OnProgress, Done, Total, TPath.GetFileName(Pair.Value));
                      ExtractEntryToFile(Stack[High(Stack)].Zip, Pair.Key, Pair.Value,
                        Cancel, Err);
                      if Err.Code <> vecOk then
                        Break;
                      Inc(Done, Stack[High(Stack)].Zip.FileInfo[Pair.Key].UncompressedSize);
                      QueueProgress(OnProgress, Done, Total, TPath.GetFileName(Pair.Value));
                    end;
                  end;
                end;
              finally
                Jobs.Free;
              end;
            finally
              FreeZipStack(Stack);
            end;
          end;
        end
        else if HasArchiveChain(FromURI) and HasArchiveChain(ToURI) then
          Err := TVfsError.Make(vecNotSupported, 'Cannot copy between archives', FromURI)
        else
          Err := TVfsError.Make(vecInvalidURI, 'Not an archive copy', FromURI);
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, FromURI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsTextCallback;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  if MaxBytes <= 0 then
    MaxBytes := 2 * 1024 * 1024;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Stack: TArray<TZipLayer>;
      Pref: string;
      Err: TVfsError;
      Path: string;
      Idx, Got: Integer;
      Local: TStream;
      Buf: TBytes;
      Text: string;
      Enc: TTextFileEncoding;
      IsBin: Boolean;
      H, LH: TZipHeader;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Text := '';
      Enc := tfeUtf8;
      try
        if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else
        begin
          Path := FileUriToPath(Base);
          if OpenZipStack(Path, Segs, Cancel, Stack, Pref, Err) then
          try
            if Pref = '' then
              Err := TVfsError.Make(vecNotSupported, 'Not a file', URI)
            else
            begin
              Idx := FindZipEntryIndex(Stack[High(Stack)].Zip, Pref);
              if Idx < 0 then
                Err := TVfsError.Make(vecNotFound, 'Entry not found', URI)
              else if EntryIsDirectory(Stack[High(Stack)].Zip, Idx) then
                Err := TVfsError.Make(vecNotSupported, 'Not a file', URI)
              else
              begin
                H := Stack[High(Stack)].Zip.FileInfo[Idx];
                if Int64(H.UncompressedSize) > MaxBytes then
                  Err := TVfsError.Make(vecNotSupported,
                    Format('File too large (max %d KB).', [MaxBytes div 1024]), URI)
                else
                begin
                  Stack[High(Stack)].Zip.Read(Idx, Local, LH);
                  try
                    SetLength(Buf, H.UncompressedSize);
                    if Length(Buf) > 0 then
                    begin
                      Got := Local.Read(Buf[0], Length(Buf));
                      SetLength(Buf, Got);
                    end;
                    if not DetectAndDecodeText(Buf, Text, Enc, IsBin) then
                    begin
                      if IsBin then
                        Err := TVfsError.Make(vecNotSupported, 'Binary file', URI)
                      else
                        Err := TVfsError.Make(vecIOError, 'Cannot decode text', URI);
                      Text := '';
                    end;
                  finally
                    Local.Free;
                  end;
                end;
              end;
            end;
          finally
            FreeZipStack(Stack);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueText(OnDone, Text, Enc, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  MaxBytes: Int64;
  Cancel: IJobCancelToken;
  OnDone: TVfsBytesCallback;
begin
  URI := AURI;
  MaxBytes := AMaxBytes;
  if MaxBytes <= 0 then
    MaxBytes := 2 * 1024 * 1024;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Stack: TArray<TZipLayer>;
      Pref: string;
      Err: TVfsError;
      Path: string;
      Idx, Got: Integer;
      Local: TStream;
      Buf: TBytes;
      H, LH: TZipHeader;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Buf, 0);
      try
        if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else
        begin
          Path := FileUriToPath(Base);
          if OpenZipStack(Path, Segs, Cancel, Stack, Pref, Err) then
          try
            if Pref = '' then
              Err := TVfsError.Make(vecNotSupported, 'Not a file', URI)
            else
            begin
              Idx := FindZipEntryIndex(Stack[High(Stack)].Zip, Pref);
              if Idx < 0 then
                Err := TVfsError.Make(vecNotFound, 'Entry not found', URI)
              else if EntryIsDirectory(Stack[High(Stack)].Zip, Idx) then
                Err := TVfsError.Make(vecNotSupported, 'Not a file', URI)
              else
              begin
                H := Stack[High(Stack)].Zip.FileInfo[Idx];
                if Int64(H.UncompressedSize) > MaxBytes then
                  Err := TVfsError.Make(vecNotSupported,
                    Format('File too large (max %d KB).', [MaxBytes div 1024]), URI)
                else
                begin
                  Stack[High(Stack)].Zip.Read(Idx, Local, LH);
                  try
                    SetLength(Buf, H.UncompressedSize);
                    if Length(Buf) > 0 then
                    begin
                      Got := Local.Read(Buf[0], Length(Buf));
                      SetLength(Buf, Got);
                    end;
                  finally
                    Local.Free;
                  end;
                end;
              end;
            end;
          finally
            FreeZipStack(Stack);
          end;
        end;
      except
        on E: Exception do
        begin
          Err := TVfsError.Make(vecIOError, E.Message, URI);
          SetLength(Buf, 0);
        end;
      end;
      QueueBytes(OnDone, Buf, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsExistsCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Base: string;
      Segs: TArray<string>;
      Stack: TArray<TZipLayer>;
      Pref: string;
      Err: TVfsError;
      Path: string;
      Exists, IsDir: Boolean;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      Exists := False;
      IsDir := False;
      try
        if not SplitArchiveUri(URI, Base, Segs) then
          Err := TVfsError.Make(vecInvalidURI, 'Invalid archive URI', URI)
        else
        begin
          Path := FileUriToPath(Base);
          if Length(Segs) < 2 then
          begin
            if Length(Segs) = 0 then
              Pref := ''
            else
              Pref := Segs[0];
            if TZipCdCacheHub.ExistsInFileZip(Path, Pref, Cancel, Exists, IsDir, Err) then
            begin
              if not Exists then
                Err := TVfsError.Make(vecNotFound, 'Not found', URI);
            end;
          end
          else if OpenZipStack(Path, Segs, Cancel, Stack, Pref, Err) then
          try
            Exists := EntryExists(Stack[High(Stack)].Zip, Pref, IsDir);
            if not Exists then
              Err := TVfsError.Make(vecNotFound, 'Not found', URI);
          finally
            FreeZipStack(Stack);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;
      QueueExists(OnDone, Exists, IsDir, Err);
    end).Start;
end;

procedure TZipVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  RootURI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsFreeSpaceCallback;
begin
  RootURI := ARootURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Path, Drive: string;
      Err, DoneErr: TVfsError;
      FreeAvail, TotalNum: UInt64;
      FreeB, TotalB, DoneFree, DoneTotal: Int64;
    begin
      Err := TVfsError.Ok;
      Err.URI := RootURI;
      FreeB := -1;
      TotalB := -1;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', RootURI)
        else
        begin
          Path := ArchiveBasePath(RootURI);
          if Path = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Invalid URI', RootURI)
          else
          begin
            Drive := ExtractFileDrive(Path);
            if Drive = '' then
              Err := TVfsError.Make(vecInvalidURI, 'No drive root', RootURI)
            else
            begin
              Drive := IncludeTrailingPathDelimiter(Drive);
              if GetDiskFreeSpaceEx(PChar(Drive), FreeAvail, TotalNum, nil) then
              begin
                FreeB := Int64(FreeAvail);
                TotalB := Int64(TotalNum);
              end
              else
                Err := TVfsError.Make(vecIOError, 'GetDiskFreeSpaceEx failed', RootURI);
            end;
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, RootURI);
      end;
      DoneFree := FreeB;
      DoneTotal := TotalB;
      DoneErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(DoneFree, DoneTotal, DoneErr);
        end);
    end).Start;
end;

end.
