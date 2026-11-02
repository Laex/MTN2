unit uFindArchive;

{ Archive access for Find. A search runs on a worker thread, while the VFS
  backends answer through callbacks queued to the main thread; the routines
  here start a request and wait for its answer, so the search can walk an
  archive like a folder. Which files are archives is decided by the registry
  (built-in zip family plus the extensions of loaded plugins), on the main
  thread, once per extension. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes;

type
  /// <summary>Maps a local file to the root URI of the archive it opens as,
  /// or '' when it is no archive. Use from the search thread only.</summary>
  TArchiveRootResolver = class
  private
    type
      TKnown = record
        IsArchive: Boolean;
        Scheme: string;
      end;
    var
      FByExtension: TDictionary<string, TKnown>;
  public
    constructor Create;
    destructor Destroy; override;
    function RootUriOf(const AFilePath: string): string;
  end;

  /// <summary>Called for every file inside the archive; False stops the walk.</summary>
  TArchiveEntryVisitor = reference to function(const AEntryUri: string;
    const AEntry: TVfsEntry): Boolean;

/// <summary>The file system that opens archives during a search.</summary>
function CreateArchiveSearchVfs: IVirtualFileSystem;

/// <summary>Visits the files below ARootUri. False when a folder could not be
/// listed (the others are still visited), the search was cancelled or the
/// visitor stopped the walk.</summary>
function WalkArchiveEntries(const AVfs: IVirtualFileSystem; const ARootUri: string;
  ASubdirs: Boolean; ACancel: IJobCancelToken;
  const AVisit: TArchiveEntryVisitor): Boolean;

/// <summary>Reads at most AMaxBytes of one archive entry.</summary>
function ReadArchiveEntry(const AVfs: IVirtualFileSystem; const AEntryUri: string;
  AMaxBytes: Int64; ACancel: IJobCancelToken; out ABytes: TBytes): Boolean;

/// <summary>Splits the URI of a file inside an archive into the local path of
/// the archive and the path inside it; False for anything else.</summary>
function SplitArchiveHit(const AUri: string; out AArchivePath,
  AInnerPath: string): Boolean;

/// <summary>The URI a hit opens as: the entry URI of a file inside an archive,
/// file:// of the local path otherwise.</summary>
function FindHitUri(const APath: string): string;

/// <summary>The text of a hit in the results list: the path below ARoot, and
/// for a file inside an archive "archive : path in the archive".</summary>
function FindHitDisplayName(const ARoot, APath: string): string;

implementation

uses
  System.SyncObjs, System.Diagnostics, uVfsRegistry;

const
  cArchiveWaitMs = 120000;

type
  TSyncBox = class(TInterfacedObject)
  public
    Done: TEvent;
    Items: TArray<TVfsEntry>;
    Bytes: TBytes;
    Err: TVfsError;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TSyncBox.Create;
begin
  inherited Create;
  Done := TEvent.Create(nil, True, False, '');
  Err := TVfsError.Ok;
end;

destructor TSyncBox.Destroy;
begin
  Done.Free;
  inherited;
end;

{ A callback that arrives after the wait gave up still finds its box alive:
  the callback holds a reference to it. }
function WaitForBox(ABox: TSyncBox; ACancel: IJobCancelToken): Boolean;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while ABox.Done.WaitFor(50) <> wrSignaled do
    if JobCancelRequested(ACancel) or (Watch.ElapsedMilliseconds > cArchiveWaitMs) then
      Exit(False);
  Result := True;
end;

function ListSync(const AVfs: IVirtualFileSystem; const AUri: string;
  ACancel: IJobCancelToken; out AItems: TArray<TVfsEntry>): Boolean;
var
  Keep: IInterface;
  Box: TSyncBox;
begin
  Box := TSyncBox.Create;
  Keep := Box;
  AVfs.ListDirectoryAsync(AUri, ACancel,
    procedure(const AList: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      if Keep = nil then
        Exit;
      Box.Items := AList;
      Box.Err := AError;
      Box.Done.SetEvent;
    end);
  Result := WaitForBox(Box, ACancel) and (Box.Err.Code = vecOk);
  if Result then
    AItems := Box.Items
  else
    SetLength(AItems, 0);
end;

function ReadArchiveEntry(const AVfs: IVirtualFileSystem; const AEntryUri: string;
  AMaxBytes: Int64; ACancel: IJobCancelToken; out ABytes: TBytes): Boolean;
var
  Keep: IInterface;
  Box: TSyncBox;
begin
  Box := TSyncBox.Create;
  Keep := Box;
  AVfs.ReadBytesAsync(AEntryUri, AMaxBytes, ACancel,
    procedure(const AData: TBytes; const AError: TVfsError)
    begin
      if Keep = nil then
        Exit;
      Box.Bytes := AData;
      Box.Err := AError;
      Box.Done.SetEvent;
    end);
  Result := WaitForBox(Box, ACancel) and (Box.Err.Code = vecOk);
  if Result then
    ABytes := Box.Bytes
  else
    SetLength(ABytes, 0);
end;

function CreateArchiveSearchVfs: IVirtualFileSystem;
begin
  Result := CreateDefaultVfs;
end;

function WalkArchiveEntries(const AVfs: IVirtualFileSystem; const ARootUri: string;
  ASubdirs: Boolean; ACancel: IJobCancelToken;
  const AVisit: TArchiveEntryVisitor): Boolean;
var
  Pending: TStack<string>;
  Dir, Uri: string;
  Items: TArray<TVfsEntry>;
  E: TVfsEntry;
begin
  Result := True;
  Pending := TStack<string>.Create;
  try
    Pending.Push(ARootUri);
    while Pending.Count > 0 do
    begin
      if JobCancelRequested(ACancel) then
        Exit(False);
      Dir := Pending.Pop;
      if not ListSync(AVfs, Dir, ACancel, Items) then
      begin
        Result := False;
        Continue;
      end;
      for E in Items do
      begin
        if (E.Name = '') or (E.Name = '.') or (E.Name = '..') then
          Continue;
        if E.TargetURI <> '' then
          Uri := E.TargetURI
        else
          Uri := JoinVfsUri(Dir, E.Name);
        if E.IsDirectory then
        begin
          if ASubdirs then
            Pending.Push(Uri);
        end
        else if not AVisit(Uri, E) then
          Exit(False);
        if JobCancelRequested(ACancel) then
          Exit(False);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

function SplitArchiveHit(const AUri: string; out AArchivePath,
  AInnerPath: string): Boolean;
var
  Base: string;
  Segs: TArray<string>;
  I: Integer;
begin
  AArchivePath := '';
  AInnerPath := '';
  // A local path can hold "!/" on a POSIX system; a URI always has "://".
  Result := (Pos('://', AUri) > 0) and HasArchiveChain(AUri) and
    SplitArchiveUri(AUri, Base, Segs) and (Length(Segs) > 0);
  if not Result then
    Exit;
  AArchivePath := ArchiveBaseLocalPath(Base);
  AInnerPath := Segs[0];
  for I := 1 to High(Segs) do
    AInnerPath := AInnerPath + '!/' + Segs[I];
end;

function FindHitUri(const APath: string): string;
var
  Archive, Inner: string;
begin
  if SplitArchiveHit(APath, Archive, Inner) then
    Result := APath
  else
    Result := PathToFileUri(APath);
end;

function LocalHitDisplayName(const ARoot, AFull: string): string;
var
  RootSlash: string;
begin
  RootSlash := IncludeTrailingPathDelimiter(ARoot);
  if AFull.StartsWith(RootSlash, True) then
    Result := Copy(AFull, Length(RootSlash) + 1, MaxInt)
  else if SameText(AFull, ARoot) then
    Result := ExtractFileName(AFull)
  else
    Result := AFull;
  if Result = '' then
    Result := ExtractFileName(AFull);
end;

function FindHitDisplayName(const ARoot, APath: string): string;
var
  Archive, Inner: string;
begin
  if SplitArchiveHit(APath, Archive, Inner) then
    Result := LocalHitDisplayName(ARoot, Archive) + ' : ' + Inner
  else
    Result := LocalHitDisplayName(ARoot, APath);
end;

{ TArchiveRootResolver }

constructor TArchiveRootResolver.Create;
begin
  inherited Create;
  FByExtension := TDictionary<string, TKnown>.Create;
end;

destructor TArchiveRootResolver.Destroy;
begin
  FByExtension.Free;
  inherited;
end;

function TArchiveRootResolver.RootUriOf(const AFilePath: string): string;
var
  Ext: string;
  Known: TKnown;
  Kind: TArchiveExtensionKind;
  Scheme: string;
  Found: Boolean;
begin
  Ext := LowerCase(ExtractFileExt(AFilePath));
  if Ext = '' then
    Exit('');
  if not FByExtension.TryGetValue(Ext, Known) then
  begin
    Found := False;
    Scheme := '';
    Kind := akZipChain;
    // The registry may load a plugin to answer, which belongs on the main thread.
    if TThread.CurrentThread.ThreadID = MainThreadID then
      Found := GlobalVfsRegistry.TryResolveArchive(AFilePath, Kind, Scheme)
    else
      TThread.Synchronize(nil,
        procedure
        begin
          Found := GlobalVfsRegistry.TryResolveArchive(AFilePath, Kind, Scheme);
        end);
    Known.IsArchive := Found;
    if Found and (Kind = akPluginScheme) then
      Known.Scheme := Scheme
    else
      Known.Scheme := '';
    FByExtension.Add(Ext, Known);
  end;
  if not Known.IsArchive then
    Exit('');
  if Known.Scheme <> '' then
    Result := PathToArchiveRootUri(Known.Scheme, AFilePath)
  else
    Result := EnsureArchiveRootUri(PathToFileUri(AFilePath));
end;

end.
