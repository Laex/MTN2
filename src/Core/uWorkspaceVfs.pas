unit uWorkspaceVfs;

{ Built-in backend for ws:/// — a panel of *links* to real files and folders.
  Originals stay on disk. F5 records a reference; F8 drops it. Virtual folders
  (F7) exist only inside the panel. Change Drive 4 is always visible, so this
  lives in core rather than depending on the optional WASM plugin. }

interface

uses
  uVfsTypes, uTextEncoding;

type
  TWorkspaceVirtualFileSystem = class(TInterfacedObject, IVirtualFileSystem)
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

procedure ClearWorkspaceLinks;
/// <summary>If ATargetURI is a workspace directory link, the ws:// URI of the
/// panel folder that holds it (`ws:///` or `ws:///group`). Else ''.</summary>
function WorkspaceParentUriForTarget(const ATargetURI: string): string;
function WorkspaceLinkNameForTarget(const ATargetURI: string): string;
/// <summary>Per-tab: remember how to return to Workspace after Enter on a
/// dir-link. Other tabs at the same disk path keep a normal disk parent.</summary>
procedure UpdateWorkspaceBackMarker(var ABackUri, ABackTarget: string;
  const AFromURI, AToURI: string);

type
  TWorkspaceLinkNode = record
    Path: string;
    TargetURI: string;
    IsDir: Boolean;
    IsVirt: Boolean;
  end;

function WorkspaceExportLinks: TArray<TWorkspaceLinkNode>;
procedure WorkspaceImportLinks(const ANodes: TArray<TWorkspaceLinkNode>);
function WorkspaceLinkCount: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs,
  System.Generics.Collections;

type
  TWsNode = record
    Path: string;
    TargetURI: string;
    IsDir: Boolean;
    IsVirt: Boolean;
  end;

var
  GLock: TCriticalSection;
  GNodes: TList<TWsNode>;

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

procedure QueueExists(const AOnDone: TVfsExistsCallback; AExists, AIsDir: Boolean;
  const AError: TVfsError);
var
  Exists, IsDir: Boolean;
  Err: TVfsError;
  Cb: TVfsExistsCallback;
begin
  Exists := AExists;
  IsDir := AIsDir;
  Err := AError;
  Cb := AOnDone;
  if not Assigned(Cb) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      Cb(Exists, IsDir, Err);
    end);
end;

procedure QueueUnsupported(const AOnDone: TVfsBoolCallback; const AURI: string);
begin
  QueueBool(AOnDone, False,
    TVfsError.Make(vecNotSupported, 'Not supported on workspace', AURI));
end;

function ParentInner(const APath: string): string;
var
  Slash: Integer;
begin
  Slash := LastDelimiter('/', APath);
  if Slash > 0 then
    Result := Copy(APath, 1, Slash - 1)
  else
    Result := '';
end;

function NameInner(const APath: string): string;
var
  Slash: Integer;
begin
  Slash := LastDelimiter('/', APath);
  if Slash > 0 then
    Result := Copy(APath, Slash + 1, MaxInt)
  else
    Result := APath;
end;

function IsDescendant(const APath, ADir: string): Boolean;
begin
  if ADir = '' then
    Exit(APath <> '');
  Result := (Length(APath) > Length(ADir)) and
    SameText(Copy(APath, 1, Length(ADir)), ADir) and
    (APath[Length(ADir) + 1] = '/');
end;

function IndexOfPath(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GNodes.Count - 1 do
    if SameText(GNodes[I].Path, APath) then
      Exit(I);
  Result := -1;
end;

function LeafNameOfUri(const AURI: string): string;
var
  Path, Inner: string;
begin
  if IsWorkspaceUri(AURI) then
  begin
    Inner := WorkspaceInnerPath(AURI);
    Result := NameInner(Inner);
    if Result = '' then
      Result := 'item';
    Exit;
  end;
  Path := FileUriToPath(AURI);
  if Path <> '' then
  begin
    Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(Path));
    if Result = '' then
      Result := 'item';
    Exit;
  end;
  Result := VfsUriTitle(AURI);
  if (Result = '') or SameText(Result, 'Workspace') then
    Result := 'item';
end;

function DestInnerPath(const AFromURI, AToURI: string): string;
var
  Inner, Name: string;
  Idx: Integer;
  Node: TWsNode;
begin
  Inner := WorkspaceInnerPath(AToURI);
  Name := LeafNameOfUri(AFromURI);
  if Inner = '' then
    Exit(Name);
  Idx := IndexOfPath(Inner);
  if Idx >= 0 then
  begin
    Node := GNodes[Idx];
    if Node.IsDir and Node.IsVirt then
      Exit(Inner + '/' + Name);
    Exit(Inner);
  end;
  Result := Inner;
end;

function EnsureParent(const APath: string; out AError: TVfsError): Boolean;
var
  Parent: string;
  Node: TWsNode;
  Idx: Integer;
begin
  Result := True;
  AError := TVfsError.Ok;
  Parent := ParentInner(APath);
  if Parent = '' then
    Exit;
  Idx := IndexOfPath(Parent);
  if Idx >= 0 then
  begin
    if not GNodes[Idx].IsDir then
    begin
      AError := TVfsError.Make(vecIOError, 'Parent is not a folder',
        MakeWorkspaceUri(Parent));
      Exit(False);
    end;
    Exit(True);
  end;
  if not EnsureParent(Parent, AError) then
    Exit(False);
  Node := Default(TWsNode);
  Node.Path := Parent;
  Node.IsDir := True;
  Node.IsVirt := True;
  GNodes.Add(Node);
end;

procedure RemoveTree(const APath: string);
var
  I: Integer;
begin
  for I := GNodes.Count - 1 downto 0 do
    if SameText(GNodes[I].Path, APath) or IsDescendant(GNodes[I].Path, APath) then
      GNodes.Delete(I);
end;

procedure ClearWorkspaceLinks;
begin
  GLock.Acquire;
  try
    GNodes.Clear;
  finally
    GLock.Release;
  end;
end;

function WorkspaceParentUriForTarget(const ATargetURI: string): string;
var
  I: Integer;
begin
  Result := '';
  if ATargetURI = '' then
    Exit;
  GLock.Acquire;
  try
    for I := 0 to GNodes.Count - 1 do
    begin
      if (GNodes[I].TargetURI = '') or not GNodes[I].IsDir then
        Continue;
      if SameVfsUri(GNodes[I].TargetURI, ATargetURI) then
        Exit(MakeWorkspaceUri(ParentInner(GNodes[I].Path)));
    end;
  finally
    GLock.Release;
  end;
end;

function WorkspaceLinkNameForTarget(const ATargetURI: string): string;
var
  I: Integer;
begin
  Result := '';
  if ATargetURI = '' then
    Exit;
  GLock.Acquire;
  try
    for I := 0 to GNodes.Count - 1 do
    begin
      if (GNodes[I].TargetURI = '') or not GNodes[I].IsDir then
        Continue;
      if SameVfsUri(GNodes[I].TargetURI, ATargetURI) then
        Exit(NameInner(GNodes[I].Path));
    end;
  finally
    GLock.Release;
  end;
end;

function FileUriIsSameOrUnder(const AChildURI, AParentURI: string): Boolean;
var
  ChildBase, ChildPath, ParentPath, Prefix: string;
  Segs: TArray<string>;
begin
  Result := False;
  if (AChildURI = '') or (AParentURI = '') then
    Exit;
  if SameVfsUri(AChildURI, AParentURI) then
    Exit(True);
  ChildBase := AChildURI;
  if HasArchiveChain(AChildURI) then
  begin
    if not SplitArchiveUri(AChildURI, ChildBase, Segs) then
      ChildBase := AChildURI;
  end;
  ChildPath := ExcludeTrailingPathDelimiter(FileUriToPath(ChildBase));
  ParentPath := ExcludeTrailingPathDelimiter(FileUriToPath(AParentURI));
  if (ChildPath = '') or (ParentPath = '') then
    Exit;
  if SameText(ChildPath, ParentPath) then
    Exit(True);
  Prefix := IncludeTrailingPathDelimiter(ParentPath);
  Result := SameText(Copy(IncludeTrailingPathDelimiter(ChildPath), 1, Length(Prefix)),
    Prefix);
end;

procedure UpdateWorkspaceBackMarker(var ABackUri, ABackTarget: string;
  const AFromURI, AToURI: string);
begin
  if IsWorkspaceUri(AToURI) then
  begin
    ABackUri := '';
    ABackTarget := '';
    Exit;
  end;
  if IsWorkspaceUri(AFromURI) then
  begin
    if WorkspaceParentUriForTarget(AToURI) <> '' then
    begin
      ABackUri := AFromURI;
      ABackTarget := AToURI;
    end
    else if not IsFindUri(AToURI) then
    begin
      ABackUri := '';
      ABackTarget := '';
    end;
    Exit;
  end;
  if ABackTarget = '' then
    Exit;
  if SameVfsUri(AToURI, ABackTarget) or FileUriIsSameOrUnder(AToURI, ABackTarget) or
     IsFindUri(AToURI) then
    Exit;
  ABackUri := '';
  ABackTarget := '';
end;

function WorkspaceExportLinks: TArray<TWorkspaceLinkNode>;
var
  I: Integer;
begin
  GLock.Acquire;
  try
    SetLength(Result, GNodes.Count);
    for I := 0 to GNodes.Count - 1 do
    begin
      Result[I].Path := GNodes[I].Path;
      Result[I].TargetURI := GNodes[I].TargetURI;
      Result[I].IsDir := GNodes[I].IsDir;
      Result[I].IsVirt := GNodes[I].IsVirt;
    end;
  finally
    GLock.Release;
  end;
end;

procedure WorkspaceImportLinks(const ANodes: TArray<TWorkspaceLinkNode>);
var
  I: Integer;
  Node: TWsNode;
begin
  GLock.Acquire;
  try
    GNodes.Clear;
    for I := 0 to High(ANodes) do
    begin
      Node.Path := Trim(ANodes[I].Path);
      if Node.Path = '' then
        Continue;
      Node.TargetURI := ANodes[I].TargetURI;
      Node.IsDir := ANodes[I].IsDir;
      Node.IsVirt := ANodes[I].IsVirt;
      GNodes.Add(Node);
    end;
  finally
    GLock.Release;
  end;
end;

function WorkspaceLinkCount: Integer;
begin
  GLock.Acquire;
  try
    Result := GNodes.Count;
  finally
    GLock.Release;
  end;
end;

function MakeLinkEntry(const ANode: TWsNode): TVfsEntry;
var
  Name: string;
begin
  Result := Default(TVfsEntry);
  Name := NameInner(ANode.Path);
  Result.Name := Name;
  Result.IsDirectory := ANode.IsDir;
  Result.IsLink := ANode.TargetURI <> '';
  Result.TargetURI := ANode.TargetURI;
  if ANode.IsDir then
    Result.Size := -1
  else
  begin
    Result.Size := 0;
    Result.Extension := LowerCase(TPath.GetExtension(Name));
  end;
end;

procedure TWorkspaceVirtualFileSystem.ListDirectoryAsync(const AURI: string;
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
      Items: TArray<TVfsEntry>;
      Err: TVfsError;
      Parent: string;
      I, N: Integer;
      Node: TWsNode;
    begin
      Err := TVfsError.Ok;
      Err.URI := URI;
      SetLength(Items, 0);
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else if not IsWorkspaceUri(URI) then
          Err := TVfsError.Make(vecInvalidURI, 'Not a workspace URI', URI)
        else
        begin
          Parent := WorkspaceInnerPath(URI);
          GLock.Acquire;
          try
            if Parent <> '' then
            begin
              I := IndexOfPath(Parent);
              if I < 0 then
                Err := TVfsError.Make(vecNotFound, 'Not found', URI)
              else if not GNodes[I].IsDir then
                Err := TVfsError.Make(vecNotSupported, 'Not a directory', URI);
            end;
            if Err.Code = vecOk then
            begin
              N := 0;
              for I := 0 to GNodes.Count - 1 do
              begin
                Node := GNodes[I];
                if not SameText(ParentInner(Node.Path), Parent) then
                  Continue;
                if NameInner(Node.Path) = '' then
                  Continue;
                SetLength(Items, N + 1);
                Items[N] := MakeLinkEntry(Node);
                Inc(N);
              end;
            end;
          finally
            GLock.Release;
          end;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueList(OnDone, Items, Err);
    end).Start;
end;

procedure TWorkspaceVirtualFileSystem.DeleteAsync(const AURI: string;
  AMode: TVfsDeleteMode; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Inner: string;
      I: Integer;
      Any: Boolean;
    begin
      Err := TVfsError.Ok;
      try
        GLock.Acquire;
        try
          if IsWorkspaceUri(URI) then
          begin
            Inner := WorkspaceInnerPath(URI);
            if Inner = '' then
              GNodes.Clear
            else if IndexOfPath(Inner) < 0 then
              Err := TVfsError.Make(vecNotFound, 'Not found', URI)
            else
              RemoveTree(Inner);
          end
          else
          begin
            Any := False;
            I := GNodes.Count - 1;
            while I >= 0 do
            begin
              if SameVfsUri(GNodes[I].TargetURI, URI) then
              begin
                RemoveTree(GNodes[I].Path);
                Any := True;
                I := GNodes.Count - 1;
              end
              else
                Dec(I);
            end;
            if not Any then
              Err := TVfsError.Make(vecNotFound, 'Not found', URI);
          end;
        finally
          GLock.Release;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TWorkspaceVirtualFileSystem.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  URI: string;
  OnDone: TVfsBoolCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Inner: string;
      Node: TWsNode;
    begin
      Err := TVfsError.Ok;
      try
        if not IsWorkspaceUri(URI) then
          Err := TVfsError.Make(vecInvalidURI, 'Not a workspace URI', URI)
        else
        begin
          Inner := WorkspaceInnerPath(URI);
          if Inner = '' then
            Err := TVfsError.Make(vecInvalidURI, 'Cannot mkdir workspace root', URI)
          else
          begin
            GLock.Acquire;
            try
              if IndexOfPath(Inner) >= 0 then
                Err := TVfsError.Make(vecAlreadyExists, 'Already exists', URI)
              else if EnsureParent(Inner, Err) then
              begin
                Node := Default(TWsNode);
                Node.Path := Inner;
                Node.IsDir := True;
                Node.IsVirt := True;
                GNodes.Add(Node);
              end;
            finally
              GLock.Release;
            end;
          end;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TWorkspaceVirtualFileSystem.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  FromURI, ToURI: string;
  OnDone: TVfsBoolCallback;
  Overwrite: Boolean;
begin
  FromURI := AFromURI;
  ToURI := AToURI;
  OnDone := AOnDone;
  Overwrite := AOverwrite;
  TThread.CreateAnonymousThread(
    procedure
    var
      Err: TVfsError;
      Dest, Path, Target: string;
      IsDir, Virt: Boolean;
      Idx: Integer;
      Node: TWsNode;
    begin
      Err := TVfsError.Ok;
      try
        if not IsWorkspaceUri(ToURI) then
          Err := TVfsError.Make(vecInvalidURI, 'Not a workspace URI', ToURI)
        else
        begin
          Path := FileUriToPath(FromURI);
          IsDir := (Path <> '') and LocalPathIsDirectory(Path);
          Target := FromURI;
          Virt := False;
          GLock.Acquire;
          try
            if IsWorkspaceUri(FromURI) then
            begin
              Idx := IndexOfPath(WorkspaceInnerPath(FromURI));
              if Idx < 0 then
                Err := TVfsError.Make(vecNotFound, 'Not found', FromURI)
              else
              begin
                Target := GNodes[Idx].TargetURI;
                IsDir := GNodes[Idx].IsDir;
                Virt := GNodes[Idx].IsVirt;
                if Virt then
                  Target := '';
              end;
            end;
            if Err.Code = vecOk then
            begin
              Dest := DestInnerPath(FromURI, ToURI);
              if Dest = '' then
                Err := TVfsError.Make(vecInvalidURI, 'Invalid workspace dest', ToURI)
              else
              begin
                Idx := IndexOfPath(Dest);
                if Idx >= 0 then
                begin
                  if not Overwrite then
                    Err := TVfsError.Make(vecAlreadyExists, 'Already exists', ToURI)
                  else
                    RemoveTree(Dest);
                end;
                if (Err.Code = vecOk) and EnsureParent(Dest, Err) then
                begin
                  Node := Default(TWsNode);
                  Node.Path := Dest;
                  Node.TargetURI := Target;
                  Node.IsDir := IsDir;
                  Node.IsVirt := Virt and (Target = '');
                  GNodes.Add(Node);
                end;
              end;
            end;
          finally
            GLock.Release;
          end;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, FromURI);
      end;
      QueueBool(OnDone, Err.Code = vecOk, Err);
    end).Start;
end;

procedure TWorkspaceVirtualFileSystem.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
begin
  QueueUnsupported(AOnDone, AFromURI);
end;

procedure TWorkspaceVirtualFileSystem.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
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
        OnDone('', tfeUtf8, TVfsError.Make(vecNotSupported, 'Not a text file', URI));
      end);
end;

procedure TWorkspaceVirtualFileSystem.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
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
        OnDone(nil, TVfsError.Make(vecNotSupported, 'Not a binary file', URI));
      end);
end;

procedure TWorkspaceVirtualFileSystem.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  QueueUnsupported(AOnDone, AURI);
end;

procedure TWorkspaceVirtualFileSystem.ExistsAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsExistsCallback);
var
  URI: string;
  OnDone: TVfsExistsCallback;
begin
  URI := AURI;
  OnDone := AOnDone;
  TThread.CreateAnonymousThread(
    procedure
    var
      Exists, IsDir: Boolean;
      Err: TVfsError;
      Inner: string;
      Idx, I: Integer;
    begin
      Err := TVfsError.Ok;
      Exists := False;
      IsDir := False;
      try
        GLock.Acquire;
        try
          if IsWorkspaceUri(URI) then
          begin
            Inner := WorkspaceInnerPath(URI);
            if Inner = '' then
            begin
              Exists := True;
              IsDir := True;
            end
            else
            begin
              Idx := IndexOfPath(Inner);
              if Idx >= 0 then
              begin
                Exists := True;
                IsDir := GNodes[Idx].IsDir;
              end;
            end;
          end
          else
          begin
            for I := 0 to GNodes.Count - 1 do
              if SameVfsUri(GNodes[I].TargetURI, URI) then
              begin
                Exists := True;
                IsDir := GNodes[I].IsDir;
                Break;
              end;
          end;
        finally
          GLock.Release;
        end;
      except
        on Ex: Exception do
          Err := TVfsError.Make(vecIOError, Ex.Message, URI);
      end;
      QueueExists(OnDone, Exists, IsDir, Err);
    end).Start;
end;

procedure TWorkspaceVirtualFileSystem.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
var
  Cb: TVfsFreeSpaceCallback;
begin
  Cb := AOnDone;
  if Assigned(Cb) then
    TThread.Queue(nil,
      procedure
      begin
        Cb(-1, -1, TVfsError.Ok);
      end);
end;

initialization
  GLock := TCriticalSection.Create;
  GNodes := TList<TWsNode>.Create;

finalization
  FreeAndNil(GNodes);
  FreeAndNil(GLock);

end.
