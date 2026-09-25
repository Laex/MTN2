unit uVfsRegistry;

{ Scheme / predicate → IVirtualFileSystem registry (SDS §5 / Plugin prep).
  Host uses CreateDefaultVfs; extra backends register without Dual Panel edits. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uVfsTypes, uTextEncoding;

type
  TVfsUriPredicate = reference to function(const AURI: string): Boolean;

  /// <summary>Which URI shape Enter should build to navigate into a file
  /// registered via RegisterArchiveExtension. akZipChain appends "!/" to the
  /// file:// URI (built-in zip backend, priority 20 in GlobalVfsRegistry);
  /// akSevenZip rewrites it to "7z:///&lt;path&gt;!/" (mtn.7z-style plugin
  /// scheme, declared by the plugin's manifest, see uPluginManifest.pas).</summary>
  TArchiveExtensionKind = (akZipChain, akSevenZip);

  /// <summary>How TVfsRegistryRoot should dispatch Copy/Move. Pure function
  /// of URIs + plugin-ownership flags so tests do not need a live VFS.</summary>
  TVfsTransferRoute = (vtrNotSupported, vtrFile, vtrZip, vtrSftp,
    vtrPluginBackend, vtrPluginDest, vtrPluginExtract);

  IVfsRegistry = interface
    ['{A1B2C3D4-E5F6-4789-A012-3456789ABCDE}']
    procedure Register(const AId: string; APred: TVfsUriPredicate;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    procedure RegisterScheme(const AScheme: string;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    /// <summary>Like RegisterScheme, tagged with APluginId so UnloadAll can
    /// drop the entry before FreeLibrary. Built-in schemes must not use this.</summary>
    procedure RegisterPluginScheme(const APluginId, AScheme: string;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    /// <summary>Declares that a file name extension (".7z", ".zip", ...)
    /// should navigate as an archive on Enter. APluginId '' marks a built-in,
    /// permanent entry; a non-empty id is dropped by UnregisterPlugin, so a
    /// plugin that fails to load (or is unloaded) stops claiming its
    /// extensions instead of leaving a stale hardcoded association.</summary>
    procedure RegisterArchiveExtension(const APluginId, AExtension: string;
      AKind: TArchiveExtensionKind; APriority: Integer = 100);
    procedure UnregisterPlugin(const APluginId: string);
    function IsPluginOwned(const AURI: string): Boolean;
    function Resolve(const AURI: string): IVirtualFileSystem;
    function TryResolve(const AURI: string; out ABackend: IVirtualFileSystem): Boolean;
    /// <summary>True when AFileName's extension was registered via
    /// RegisterArchiveExtension (built-in or a currently-loaded plugin).</summary>
    function TryResolveArchiveKind(const AFileName: string;
      out AKind: TArchiveExtensionKind): Boolean;
  end;

  TVfsRegistry = class(TInterfacedObject, IVfsRegistry)
  private
    type
      TEntry = record
        Id: string;
        PluginId: string;
        Pred: TVfsUriPredicate;
        Backend: IVirtualFileSystem;
        Priority: Integer;
      end;
      TArchiveExtEntry = record
        PluginId: string;
        Extension: string;
        Kind: TArchiveExtensionKind;
        Priority: Integer;
      end;
    var
      FEntries: TList<TEntry>;
      FArchiveExts: TList<TArchiveExtEntry>;
    procedure SortByPriority;
    procedure SortArchiveExtsByPriority;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Register(const AId: string; APred: TVfsUriPredicate;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    procedure RegisterScheme(const AScheme: string;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    procedure RegisterPluginScheme(const APluginId, AScheme: string;
      const ABackend: IVirtualFileSystem; APriority: Integer = 100);
    procedure RegisterArchiveExtension(const APluginId, AExtension: string;
      AKind: TArchiveExtensionKind; APriority: Integer = 100);
    procedure UnregisterPlugin(const APluginId: string);
    function IsPluginOwned(const AURI: string): Boolean;
    function Resolve(const AURI: string): IVirtualFileSystem;
    function TryResolve(const AURI: string; out ABackend: IVirtualFileSystem): Boolean;
    function TryResolveArchiveKind(const AFileName: string;
      out AKind: TArchiveExtensionKind): Boolean;
  end;

  /// <summary>Composite IVirtualFileSystem rooted on a registry (Copy/Move rules included).</summary>
  TVfsRegistryRoot = class(TInterfacedObject, IVirtualFileSystem)
  private
    FRegistry: IVfsRegistry;
    FFile: IVirtualFileSystem;
    FZip: IVirtualFileSystem;
    function BackendFor(const AURI: string): IVirtualFileSystem;
    function BackendForSftp(const AFromURI, AToURI: string): IVirtualFileSystem;
    function ResolveTransfer(const AFromURI, AToURI: string; AIsMove: Boolean;
      out AReason: string): TVfsTransferRoute;
    /// <summary>Host copy-bridge: ReadBytes from a plugin-owned source and
    /// write a local file:// dest. Plugin CopyItem stays unused (ABI v1).</summary>
    procedure CopyPluginExtract(const AFromURI, AToURI: string;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback; AOverwrite: Boolean);
  public
    constructor Create(const ARegistry: IVfsRegistry;
      const AFileBackend, AZipBackend: IVirtualFileSystem);
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

/// <summary>Default in-process stack: find://, archive !/, file://.</summary>
function CreateDefaultVfs: IVirtualFileSystem;
function CreateDefaultVfsRegistry: IVfsRegistry;
function UriSchemeOf(const AURI: string): string;

function ClassifyVfsTransfer(const AFromURI, AToURI: string; AIsMove: Boolean;
  APluginOwnedFrom, APluginOwnedTo, ASamePluginBackend: Boolean;
  out AReason: string): TVfsTransferRoute;

/// <summary>Process-wide default registry (lazily built by
/// CreateDefaultVfsRegistry/CreateDefaultVfs on first use). uPluginLoader.pas
/// registers plugin-supplied VFS backends into this instance, so they show
/// up for every FVfs obtained via CreateDefaultVfs across the app.</summary>
function GlobalVfsRegistry: IVfsRegistry;

/// <summary>Optional hooks so a missing scheme or archive extension can load
/// its plugin before resolve fails. uPluginHost registers these; the registry
/// does not depend on the loader (that unit already uses this one).</summary>
type
  TVfsLazyLoadFunc = function(const AKey: string): Boolean;

procedure SetVfsLazyLoad(AEnsureScheme, AEnsureArchiveExt: TVfsLazyLoadFunc);

implementation

uses
  System.IOUtils, System.SyncObjs,
  uFileVfs, uZipVfs, uFindVfs, uSysFoldersVfs, uRecycleBinVfs, uWorkspaceVfs,
  uSftpVfs;

var
  GEnsureScheme: TVfsLazyLoadFunc;
  GEnsureArchiveExt: TVfsLazyLoadFunc;

procedure SetVfsLazyLoad(AEnsureScheme, AEnsureArchiveExt: TVfsLazyLoadFunc);
begin
  GEnsureScheme := AEnsureScheme;
  GEnsureArchiveExt := AEnsureArchiveExt;
end;

function UriSchemeOf(const AURI: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(AURI);
  P := Pos('://', S);
  if P > 1 then
    Result := LowerCase(Copy(S, 1, P - 1))
  else
    Result := '';
end;

type
  /// <summary>Unknown named scheme (tmp:// without its plugin, etc.). File VFS
  /// used to catch these via default-file and show "Invalid path".</summary>
  TMissingSchemeVfs = class(TInterfacedObject, IVirtualFileSystem)
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

var
  GMissingSchemeVfs: IVirtualFileSystem;

function MissingSchemeError(const AURI: string): TVfsError;
begin
  Result := TVfsError.Make(vecNotFound, 'No VFS backend for this URI', AURI);
end;

procedure QueueVfsBool(AOnDone: TVfsBoolCallback; AOk: Boolean; const AError: TVfsError);
var
  Ok: Boolean;
  Err: TVfsError;
  Done: TVfsBoolCallback;
begin
  if not Assigned(AOnDone) then
    Exit;
  Ok := AOk;
  Err := AError;
  Done := AOnDone;
  TThread.Queue(nil,
    procedure
    begin
      Done(Ok, Err);
    end);
end;

procedure QueueVfsNotSupported(AOnDone: TVfsBoolCallback;
  const AFromURI, AReason: string);
begin
  QueueVfsBool(AOnDone, False, TVfsError.Make(vecNotSupported, AReason, AFromURI));
end;

procedure TMissingSchemeVfs.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
var
  URI: string;
  OnDone: TVfsListCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone(nil, MissingSchemeError(URI));
      end);
end;

procedure TMissingSchemeVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
  QueueVfsBool(AOnDone, False, MissingSchemeError(AURI));
end;

procedure TMissingSchemeVfs.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueVfsBool(AOnDone, False, MissingSchemeError(AURI));
end;

procedure TMissingSchemeVfs.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueVfsBool(AOnDone, False, MissingSchemeError(AFromURI));
end;

procedure TMissingSchemeVfs.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueVfsBool(AOnDone, False, MissingSchemeError(AFromURI));
end;

procedure TMissingSchemeVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
var
  URI: string;
  OnDone: TVfsTextCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone('', tfeUtf8, MissingSchemeError(URI));
      end);
end;

procedure TMissingSchemeVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
var
  URI: string;
  OnDone: TVfsBytesCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone(nil, MissingSchemeError(URI));
      end);
end;

procedure TMissingSchemeVfs.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueVfsBool(AOnDone, False, MissingSchemeError(AURI));
end;

procedure TMissingSchemeVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
var
  URI: string;
  OnDone: TVfsExistsCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone(False, False, MissingSchemeError(URI));
      end);
end;

procedure TMissingSchemeVfs.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  URI: string;
  OnDone: TVfsFreeSpaceCallback;
begin
  URI := ARootURI;
  OnDone := AOnDone;
  if Assigned(OnDone) then
    TThread.Queue(nil,
      procedure
      begin
        OnDone(-1, -1, MissingSchemeError(URI));
      end);
end;

function MissingSchemeBackend: IVirtualFileSystem;
begin
  if GMissingSchemeVfs = nil then
    GMissingSchemeVfs := TMissingSchemeVfs.Create;
  Result := GMissingSchemeVfs;
end;

function TransferInvolvesArchive(const AFromURI, AToURI: string): Boolean;
begin
  Result := HasArchiveChain(AFromURI) or HasArchiveChain(AToURI) or
    IsZipArchiveUri(AFromURI) or IsZipArchiveUri(AToURI);
end;

function ClassifyPluginTransfer(AIsMove, APluginOwnedFrom, APluginOwnedTo,
  ASamePluginBackend: Boolean; out AReason: string): TVfsTransferRoute;
begin
  AReason := '';
  if ASamePluginBackend then
    Exit(vtrPluginBackend);
  if APluginOwnedTo and (not APluginOwnedFrom) and (not AIsMove) then
    Exit(vtrPluginDest);
  if APluginOwnedFrom and (not APluginOwnedTo) and (not AIsMove) then
    Exit(vtrPluginExtract);
  AReason := 'Cross-scheme plugin transfer is not supported';
  Result := vtrNotSupported;
end;

function ClassifySftpTransfer(const AFromURI, AToURI: string;
  out AReason: string): TVfsTransferRoute;
begin
  if TransferInvolvesArchive(AFromURI, AToURI) then
  begin
    AReason := 'Cannot copy/move between archive and SFTP';
    Exit(vtrNotSupported);
  end;
  AReason := '';
  Result := vtrSftp;
end;

function EitherIsZip(const AFromURI, AToURI: string): Boolean;
begin
  Result := IsZipArchiveUri(AFromURI) or IsZipArchiveUri(AToURI);
end;

function EitherHasArchiveChain(const AFromURI, AToURI: string): Boolean;
begin
  Result := HasArchiveChain(AFromURI) or HasArchiveChain(AToURI);
end;

function RejectTransfer(out AReason: string; const AMessage: string): TVfsTransferRoute;
begin
  AReason := AMessage;
  Result := vtrNotSupported;
end;

function ClassifyLocalTransfer(const AFromURI, AToURI: string; AIsMove: Boolean;
  out AReason: string): TVfsTransferRoute;
begin
  AReason := '';
  if AIsMove then
  begin
    if EitherIsZip(AFromURI, AToURI) then
      Exit(RejectTransfer(AReason, 'Cannot move involving archive/find'));
    if EitherHasArchiveChain(AFromURI, AToURI) then
      Exit(RejectTransfer(AReason, 'Cannot move involving archive'));
    Exit(vtrFile);
  end;
  if EitherIsZip(AFromURI, AToURI) then
    Exit(vtrZip);
  if EitherHasArchiveChain(AFromURI, AToURI) then
    Exit(RejectTransfer(AReason, 'Archive scheme has no core backend'));
  Result := vtrFile;
end;

function ClassifyVfsTransfer(const AFromURI, AToURI: string; AIsMove: Boolean;
  APluginOwnedFrom, APluginOwnedTo, ASamePluginBackend: Boolean;
  out AReason: string): TVfsTransferRoute;
begin
  AReason := '';
  if IsFindUri(AFromURI) or IsFindUri(AToURI) then
  begin
    Result := vtrNotSupported;
    AReason := 'Cannot copy/move find:// session';
    Exit;
  end;
  if IsWorkspaceUri(AToURI) then
  begin
    if AIsMove then
    begin
      Result := vtrNotSupported;
      AReason := 'Cannot move onto workspace';
      Exit;
    end;
    Result := vtrPluginDest;
    Exit;
  end;
  if APluginOwnedFrom or APluginOwnedTo then
    Exit(ClassifyPluginTransfer(AIsMove, APluginOwnedFrom, APluginOwnedTo,
      ASamePluginBackend, AReason));
  if IsSftpUri(AFromURI) or IsSftpUri(AToURI) then
    Exit(ClassifySftpTransfer(AFromURI, AToURI, AReason));
  Result := ClassifyLocalTransfer(AFromURI, AToURI, AIsMove, AReason);
end;

constructor TVfsRegistry.Create;
begin
  inherited Create;
  FEntries := TList<TEntry>.Create;
  FArchiveExts := TList<TArchiveExtEntry>.Create;
end;

destructor TVfsRegistry.Destroy;
begin
  FreeAndNil(FEntries);
  FreeAndNil(FArchiveExts);
  inherited Destroy;
end;

procedure TVfsRegistry.SortByPriority;
var
  I, J: Integer;
  Tmp: TEntry;
begin
  // Lower Priority number = earlier match (stable insertion sort).
  for I := 1 to FEntries.Count - 1 do
  begin
    Tmp := FEntries[I];
    J := I - 1;
    while (J >= 0) and (FEntries[J].Priority > Tmp.Priority) do
    begin
      FEntries[J + 1] := FEntries[J];
      Dec(J);
    end;
    FEntries[J + 1] := Tmp;
  end;
end;

procedure TVfsRegistry.SortArchiveExtsByPriority;
var
  I, J: Integer;
  Tmp: TArchiveExtEntry;
begin
  // Lower Priority number = earlier match (stable insertion sort) —
  // mirrors SortByPriority above.
  for I := 1 to FArchiveExts.Count - 1 do
  begin
    Tmp := FArchiveExts[I];
    J := I - 1;
    while (J >= 0) and (FArchiveExts[J].Priority > Tmp.Priority) do
    begin
      FArchiveExts[J + 1] := FArchiveExts[J];
      Dec(J);
    end;
    FArchiveExts[J + 1] := Tmp;
  end;
end;

procedure TVfsRegistry.Register(const AId: string; APred: TVfsUriPredicate;
  const ABackend: IVirtualFileSystem; APriority: Integer);
var
  E: TEntry;
begin
  if not Assigned(APred) or not Assigned(ABackend) then
    Exit;
  E.Id := AId;
  E.PluginId := '';
  E.Pred := APred;
  E.Backend := ABackend;
  E.Priority := APriority;
  FEntries.Add(E);
  SortByPriority;
end;

procedure TVfsRegistry.RegisterScheme(const AScheme: string;
  const ABackend: IVirtualFileSystem; APriority: Integer);
var
  Scheme: string;
begin
  Scheme := LowerCase(Trim(AScheme));
  if Scheme = '' then
    Exit;
  Register('scheme:' + Scheme,
    function(const AURI: string): Boolean
    begin
      Result := UriSchemeOf(AURI) = Scheme;
    end,
    ABackend, APriority);
end;

procedure TVfsRegistry.RegisterPluginScheme(const APluginId, AScheme: string;
  const ABackend: IVirtualFileSystem; APriority: Integer);
var
  Scheme, PluginId: string;
  E: TEntry;
begin
  PluginId := Trim(APluginId);
  Scheme := LowerCase(Trim(AScheme));
  if (PluginId = '') or (Scheme = '') or not Assigned(ABackend) then
    Exit;
  E.Id := 'plugin:' + PluginId + ':scheme:' + Scheme;
  E.PluginId := PluginId;
  E.Pred :=
    function(const AURI: string): Boolean
    begin
      Result := UriSchemeOf(AURI) = Scheme;
    end;
  E.Backend := ABackend;
  E.Priority := APriority;
  FEntries.Add(E);
  SortByPriority;
end;

procedure TVfsRegistry.RegisterArchiveExtension(const APluginId, AExtension: string;
  AKind: TArchiveExtensionKind; APriority: Integer);
var
  Ext: string;
  E: TArchiveExtEntry;
begin
  Ext := LowerCase(Trim(AExtension));
  if (Ext <> '') and (Ext[1] <> '.') then
    Ext := '.' + Ext;
  if Ext = '' then
    Exit;
  E.PluginId := Trim(APluginId);
  E.Extension := Ext;
  E.Kind := AKind;
  E.Priority := APriority;
  FArchiveExts.Add(E);
  SortArchiveExtsByPriority;
end;

function TVfsRegistry.TryResolveArchiveKind(const AFileName: string;
  out AKind: TArchiveExtensionKind): Boolean;

  function Match: Boolean;
  var
    Ext: string;
    I: Integer;
  begin
    AKind := akZipChain;
    Ext := LowerCase(TPath.GetExtension(AFileName));
    if Ext = '' then
      Exit(False);
    for I := 0 to FArchiveExts.Count - 1 do
      if FArchiveExts[I].Extension = Ext then
      begin
        AKind := FArchiveExts[I].Kind;
        Exit(True);
      end;
    Result := False;
  end;

begin
  if Match then
    Exit(True);
  // Extension is known from plugin.json before the DLL is loaded. Enter on
  // a .7z (etc.) loads that plugin, which then registers the extension.
  if Assigned(GEnsureArchiveExt) and GEnsureArchiveExt(AFileName) and Match then
    Exit(True);
  Result := False;
end;

procedure TVfsRegistry.UnregisterPlugin(const APluginId: string);
var
  I: Integer;
begin
  if Trim(APluginId) = '' then
    Exit;
  for I := FEntries.Count - 1 downto 0 do
    if SameText(FEntries[I].PluginId, APluginId) then
      FEntries.Delete(I);
  for I := FArchiveExts.Count - 1 downto 0 do
    if SameText(FArchiveExts[I].PluginId, APluginId) then
      FArchiveExts.Delete(I);
end;

function TVfsRegistry.IsPluginOwned(const AURI: string): Boolean;
var
  I: Integer;
  E: TEntry;
begin
  for I := 0 to FEntries.Count - 1 do
  begin
    E := FEntries[I];
    if E.Pred(AURI) then
      Exit(E.PluginId <> '');
  end;
  Result := False;
end;

function TVfsRegistry.TryResolve(const AURI: string;
  out ABackend: IVirtualFileSystem): Boolean;

  function Match: Boolean;
  var
    I: Integer;
    E: TEntry;
  begin
    ABackend := nil;
    for I := 0 to FEntries.Count - 1 do
    begin
      E := FEntries[I];
      if E.Pred(AURI) then
      begin
        ABackend := E.Backend;
        Exit(True);
      end;
    end;
    Result := False;
  end;

var
  Scheme: string;
begin
  if Match then
    Exit(True);
  Scheme := UriSchemeOf(AURI);
  if (Scheme <> '') and Assigned(GEnsureScheme) and GEnsureScheme(Scheme) and Match then
    Exit(True);
  Result := False;
end;

function TVfsRegistry.Resolve(const AURI: string): IVirtualFileSystem;
begin
  if not TryResolve(AURI, Result) then
    raise EArgumentException.CreateFmt('No VFS backend for URI: %s', [AURI]);
end;

constructor TVfsRegistryRoot.Create(const ARegistry: IVfsRegistry;
  const AFileBackend, AZipBackend: IVirtualFileSystem);
begin
  inherited Create;
  FRegistry := ARegistry;
  FFile := AFileBackend;
  FZip := AZipBackend;
end;

function TVfsRegistryRoot.BackendFor(const AURI: string): IVirtualFileSystem;
var
  Scheme: string;
begin
  if FRegistry.TryResolve(AURI, Result) then
    Exit;
  Scheme := UriSchemeOf(AURI);
  if (Scheme <> '') and (Scheme <> 'file') then
    Result := MissingSchemeBackend
  else
    Result := FFile;
end;

function TVfsRegistryRoot.BackendForSftp(const AFromURI, AToURI: string): IVirtualFileSystem;
begin
  if IsSftpUri(AFromURI) then
    Result := BackendFor(AFromURI)
  else
    Result := BackendFor(AToURI);
end;

function TVfsRegistryRoot.ResolveTransfer(const AFromURI, AToURI: string;
  AIsMove: Boolean; out AReason: string): TVfsTransferRoute;
var
  FromPlug, ToPlug, SamePlug: Boolean;
  FromB, ToB: IVirtualFileSystem;
begin
  FromPlug := FRegistry.IsPluginOwned(AFromURI);
  ToPlug := FRegistry.IsPluginOwned(AToURI);
  SamePlug := False;
  if FromPlug and ToPlug then
  begin
    FromB := BackendFor(AFromURI);
    ToB := BackendFor(AToURI);
    SamePlug := Assigned(FromB) and (FromB = ToB);
  end;
  Result := ClassifyVfsTransfer(AFromURI, AToURI, AIsMove, FromPlug, ToPlug,
    SamePlug, AReason);
end;

procedure TVfsRegistryRoot.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
begin
  BackendFor(AURI).ListDirectoryAsync(AURI, ACancel, AOnDone);
end;

procedure TVfsRegistryRoot.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
begin
  BackendFor(AURI).DeleteAsync(AURI, AMode, ACancel, AOnProgress, AOnDone);
end;

procedure TVfsRegistryRoot.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  BackendFor(AURI).CreateDirectoryAsync(AURI, ACancel, AOnDone);
end;

type
  TPluginExtractOp = class
  private
    FBackend: IVirtualFileSystem;
    FFromURI, FToURI: string;
    FCancel: IJobCancelToken;
    FOverwrite: Boolean;
    FErr: TVfsError;
    function WaitExists(const AURI: string; out AExists, AIsDir: Boolean): Boolean;
    function WaitList(const AURI: string; out AItems: TArray<TVfsEntry>): Boolean;
    function WaitBytes(const AURI: string; out AData: TBytes): Boolean;
    function ExtractNode(const ASrcURI, ADestPath: string): Boolean;
  public
    constructor Create(const ABackend: IVirtualFileSystem;
      const AFromURI, AToURI: string; ACancel: IJobCancelToken; AOverwrite: Boolean);
    function Run: TVfsError;
  end;

constructor TPluginExtractOp.Create(const ABackend: IVirtualFileSystem;
  const AFromURI, AToURI: string; ACancel: IJobCancelToken; AOverwrite: Boolean);
begin
  inherited Create;
  FBackend := ABackend;
  FFromURI := AFromURI;
  FToURI := AToURI;
  FCancel := ACancel;
  FOverwrite := AOverwrite;
  FErr := TVfsError.Ok;
  FErr.URI := AFromURI;
end;

function TPluginExtractOp.WaitExists(const AURI: string;
  out AExists, AIsDir: Boolean): Boolean;
const
  cWaitMs = 30000;
var
  Ev: TEvent;
  Ok, IsDir: Boolean;
  WaitErr: TVfsError;
begin
  Result := False;
  AExists := False;
  AIsDir := False;
  Ev := TEvent.Create(nil, True, False, '');
  try
    FBackend.ExistsAsync(AURI, FCancel,
      procedure(const AEx, ADir: Boolean; const AErr: TVfsError)
      begin
        Ok := AEx;
        IsDir := ADir;
        WaitErr := AErr;
        Ev.SetEvent;
      end);
    if Ev.WaitFor(cWaitMs) <> wrSignaled then
    begin
      FErr := TVfsError.Make(vecIOError, 'Exists timed out', AURI);
      Exit;
    end;
    FErr := WaitErr;
    if FErr.Code <> vecOk then
      Exit;
    AExists := Ok;
    AIsDir := IsDir;
    Result := True;
  finally
    Ev.Free;
  end;
end;

function TPluginExtractOp.WaitList(const AURI: string;
  out AItems: TArray<TVfsEntry>): Boolean;
const
  cWaitMs = 30000;
var
  Ev: TEvent;
  Items: TArray<TVfsEntry>;
  WaitErr: TVfsError;
begin
  Result := False;
  SetLength(AItems, 0);
  Ev := TEvent.Create(nil, True, False, '');
  try
    FBackend.ListDirectoryAsync(AURI, FCancel,
      procedure(const AList: TArray<TVfsEntry>; const AErr: TVfsError)
      begin
        Items := AList;
        WaitErr := AErr;
        Ev.SetEvent;
      end);
    if Ev.WaitFor(cWaitMs) <> wrSignaled then
    begin
      FErr := TVfsError.Make(vecIOError, 'List timed out', AURI);
      Exit;
    end;
    FErr := WaitErr;
    if FErr.Code <> vecOk then
      Exit;
    AItems := Items;
    Result := True;
  finally
    Ev.Free;
  end;
end;

function TPluginExtractOp.WaitBytes(const AURI: string; out AData: TBytes): Boolean;
const
  cWaitMs = 30000;
var
  Ev: TEvent;
  Data: TBytes;
  WaitErr: TVfsError;
begin
  Result := False;
  SetLength(AData, 0);
  Ev := TEvent.Create(nil, True, False, '');
  try
    FBackend.ReadBytesAsync(AURI, 0, FCancel,
      procedure(const ARead: TBytes; const AErr: TVfsError)
      begin
        Data := ARead;
        WaitErr := AErr;
        Ev.SetEvent;
      end);
    if Ev.WaitFor(cWaitMs) <> wrSignaled then
    begin
      FErr := TVfsError.Make(vecIOError, 'Read timed out', AURI);
      Exit;
    end;
    FErr := WaitErr;
    if FErr.Code <> vecOk then
      Exit;
    AData := Data;
    Result := True;
  finally
    Ev.Free;
  end;
end;

function TPluginExtractOp.ExtractNode(const ASrcURI, ADestPath: string): Boolean;
var
  Exists, IsDir: Boolean;
  Items: TArray<TVfsEntry>;
  Data: TBytes;
  I: Integer;
  Name, ChildUri, ChildDest, ParentDir: string;
begin
  Result := False;
  if JobCancelRequested(FCancel) then
  begin
    FErr := TVfsError.Make(vecCancelled, 'Cancelled', ASrcURI);
    Exit;
  end;
  if not WaitExists(ASrcURI, Exists, IsDir) then
    Exit;
  if not Exists then
  begin
    FErr := TVfsError.Make(vecNotFound, 'Source not found', ASrcURI);
    Exit;
  end;
  if IsDir then
  begin
    try
      TDirectory.CreateDirectory(ADestPath);
    except
      on E: Exception do
      begin
        FErr := TVfsError.Make(vecIOError, E.Message, ASrcURI);
        Exit;
      end;
    end;
    if not WaitList(ASrcURI, Items) then
      Exit;
    for I := 0 to High(Items) do
    begin
      Name := Items[I].Name;
      if (Name = '') or (Name = '.') or (Name = '..') then
        Continue;
      ChildUri := JoinVfsUri(ASrcURI, Name);
      ChildDest := TPath.Combine(ADestPath, Name);
      if not ExtractNode(ChildUri, ChildDest) then
        Exit;
    end;
    Result := True;
    Exit;
  end;
  if (not FOverwrite) and TFile.Exists(ADestPath) then
  begin
    FErr := TVfsError.Make(vecAlreadyExists, 'Already exists', FToURI);
    Exit;
  end;
  if not WaitBytes(ASrcURI, Data) then
    Exit;
  try
    ParentDir := ExtractFilePath(ADestPath);
    if ParentDir <> '' then
      TDirectory.CreateDirectory(ParentDir);
    TFile.WriteAllBytes(ADestPath, Data);
  except
    on E: Exception do
    begin
      FErr := TVfsError.Make(vecIOError, E.Message, FToURI);
      Exit;
    end;
  end;
  Result := True;
end;

function TPluginExtractOp.Run: TVfsError;
var
  DestPath: string;
begin
  DestPath := FileUriToPath(FToURI);
  if not Assigned(FBackend) then
    FErr := TVfsError.Make(vecNotSupported, 'No plugin backend', FFromURI)
  else if HasArchiveChain(FToURI) or (DestPath = '') then
    FErr := TVfsError.Make(vecNotSupported,
      'Plugin extract destination must be a local file', FToURI)
  else
    ExtractNode(FFromURI, DestPath);
  Result := FErr;
end;

procedure TVfsRegistryRoot.CopyPluginExtract(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite: Boolean);
var
  FromURI, ToURI: string;
  Cancel: IJobCancelToken;
  OnDone: TVfsBoolCallback;
  Overwrite: Boolean;
  Backend: IVirtualFileSystem;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  Cancel := ACancel;
  OnDone := AOnDone;
  Overwrite := AOverwrite;
  Backend := BackendFor(FromURI);
  TThread.CreateAnonymousThread(
    procedure
    var
      Op: TPluginExtractOp;
      Err: TVfsError;
    begin
      Op := TPluginExtractOp.Create(Backend, FromURI, ToURI, Cancel, Overwrite);
      try
        Err := Op.Run;
      finally
        Op.Free;
      end;
      QueueVfsBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TVfsRegistryRoot.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  Route: TVfsTransferRoute;
  Reason: string;
begin
  Route := ResolveTransfer(AFromURI, AToURI, False, Reason);
  case Route of
    vtrNotSupported:
      QueueVfsNotSupported(AOnDone, AFromURI, Reason);
    vtrZip:
      FZip.CopyAsync(AFromURI, AToURI, ACancel, AOnProgress, AOnDone,
        AOverwrite, APreserveTimestamps);
    vtrSftp:
      BackendForSftp(AFromURI, AToURI).CopyAsync(AFromURI, AToURI, ACancel,
        AOnProgress, AOnDone, AOverwrite, APreserveTimestamps);
    vtrFile:
      FFile.CopyAsync(AFromURI, AToURI, ACancel, AOnProgress, AOnDone,
        AOverwrite, APreserveTimestamps);
    vtrPluginBackend:
      BackendFor(AFromURI).CopyAsync(AFromURI, AToURI, ACancel, AOnProgress,
        AOnDone, AOverwrite, APreserveTimestamps);
    vtrPluginDest:
      BackendFor(AToURI).CopyAsync(AFromURI, AToURI, ACancel, AOnProgress,
        AOnDone, AOverwrite, APreserveTimestamps);
    vtrPluginExtract:
      CopyPluginExtract(AFromURI, AToURI, ACancel, AOnProgress, AOnDone,
        AOverwrite);
  else
    QueueVfsNotSupported(AOnDone, AFromURI, Reason);
  end;
end;

procedure TVfsRegistryRoot.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  AOverwrite: Boolean; APreserveTimestamps: Boolean);
var
  Route: TVfsTransferRoute;
  Reason: string;
begin
  Route := ResolveTransfer(AFromURI, AToURI, True, Reason);
  case Route of
    vtrNotSupported, vtrZip:
      QueueVfsNotSupported(AOnDone, AFromURI, Reason);
    vtrFile:
      FFile.MoveAsync(AFromURI, AToURI, ACancel, AOnProgress, AOnDone,
        AOverwrite, APreserveTimestamps);
    vtrSftp:
      BackendForSftp(AFromURI, AToURI).MoveAsync(AFromURI, AToURI, ACancel,
        AOnProgress, AOnDone, AOverwrite, APreserveTimestamps);
    vtrPluginBackend:
      BackendFor(AFromURI).MoveAsync(AFromURI, AToURI, ACancel, AOnProgress,
        AOnDone, AOverwrite, APreserveTimestamps);
  else
    QueueVfsNotSupported(AOnDone, AFromURI, Reason);
  end;
end;

procedure TVfsRegistryRoot.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  BackendFor(AURI).ReadTextAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TVfsRegistryRoot.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  BackendFor(AURI).ReadBytesAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TVfsRegistryRoot.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  BackendFor(AURI).WriteTextAsync(AURI, AText, AEncoding, ACancel, AOnDone);
end;

procedure TVfsRegistryRoot.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
  BackendFor(AURI).ExistsAsync(AURI, ACancel, AOnDone);
end;

procedure TVfsRegistryRoot.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
begin
  BackendFor(ARootURI).GetFreeSpaceAsync(ARootURI, ACancel, AOnDone);
end;

var
  GGlobalVfsRegistry: IVfsRegistry;
  GGlobalFileVfs: IVirtualFileSystem;
  GGlobalZipVfs: IVirtualFileSystem;

function GlobalVfsRegistry: IVfsRegistry;
var
  Reg: TVfsRegistry;
  FindVfs: IVirtualFileSystem;
begin
  if GGlobalVfsRegistry = nil then
  begin
    GGlobalFileVfs := TFileVirtualFileSystem.Create;
    GGlobalZipVfs := TZipVirtualFileSystem.Create;
    FindVfs := TFindVirtualFileSystem.Create;
    Reg := TVfsRegistry.Create;
    // Lower priority number wins.
    Reg.Register('find',
      function(const AURI: string): Boolean
      begin
        Result := IsFindUri(AURI);
      end,
      FindVfs, 10);
    Reg.RegisterScheme('sys', TSysFoldersVirtualFileSystem.Create, 15);
    Reg.RegisterScheme('recycle', TRecycleBinVirtualFileSystem.Create, 15);
    Reg.RegisterScheme('ws', TWorkspaceVirtualFileSystem.Create, 15);
    Reg.RegisterScheme('sftp', TSftpVirtualFileSystem.Create, 15);
    Reg.Register('archive',
      function(const AURI: string): Boolean
      begin
        Result := IsZipArchiveUri(AURI);
      end,
      GGlobalZipVfs, 20);
    Reg.RegisterScheme('file', GGlobalFileVfs, 100);
    // Built-in archive extensions (PluginId '' so UnregisterPlugin never
    // drops them). 7z/rar/tar/... are registered by uPluginLoader.pas when
    // mtn.7z's manifest declares them (see uPluginManifest.pas) — not here,
    // so a missing/failed plugin load stops those extensions from claiming
    // to be navigable instead of leaving a stale hardcoded association.
    Reg.RegisterArchiveExtension('', '.zip', akZipChain, 50);
    Reg.RegisterArchiveExtension('', '.jar', akZipChain, 50);
    Reg.RegisterArchiveExtension('', '.apk', akZipChain, 50);
    Reg.Register('default-file',
      function(const AURI: string): Boolean
      var
        Scheme: string;
      begin
        Scheme := UriSchemeOf(AURI);
        Result := (Scheme = '') or (Scheme = 'file');
      end,
      GGlobalFileVfs, 1000);
    GGlobalVfsRegistry := Reg;
  end;
  Result := GGlobalVfsRegistry;
end;

function CreateDefaultVfsRegistry: IVfsRegistry;
begin
  Result := GlobalVfsRegistry;
end;

function CreateDefaultVfs: IVirtualFileSystem;
begin
  GlobalVfsRegistry; // ensures GGlobalFileVfs/GGlobalZipVfs are populated
  Result := TVfsRegistryRoot.Create(GGlobalVfsRegistry, GGlobalFileVfs, GGlobalZipVfs);
end;

end.
