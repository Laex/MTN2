unit uWorkspaceLibrary;

{ Named snapshots of the live ws:/// link store. One live workspace plus a
  JSON library (workspaces.json). Restore replaces the live set. }

interface

uses
  System.SysUtils, System.Classes, uWorkspaceVfs;

type
  TWorkspaceSnapshot = record
    Id: string;
    Name: string;
    Nodes: TArray<TWorkspaceLinkNode>;
  end;

procedure WorkspaceLibraryUsePath(const APath: string);
procedure WorkspaceLibraryResetForTests;
function WorkspaceLibraryGet: TArray<TWorkspaceSnapshot>;
function WorkspaceLibraryFindById(const AId: string): Integer;
function WorkspaceLibraryFindByName(const AName: string): Boolean;
function WorkspaceLibrarySaveCurrent(const AName: string): Boolean;
function WorkspaceLibraryRestore(const AId: string): Boolean;
procedure WorkspaceLibraryDelete(const AId: string);
procedure WorkspaceLibraryRename(const AId, ANewName: string);
function WorkspaceLiveId: string;
function WorkspaceLiveName: string;
function WorkspaceLiveHasLinks: Boolean;
function WorkspaceLiveIsDirty: Boolean;
function WorkspaceLiveCaption: string;
function WorkspaceSnapshotDisplayLabel(const ASnap: TWorkspaceSnapshot): string;

implementation

uses
  System.IOUtils, System.JSON, System.Generics.Collections,
  System.Generics.Defaults, uConfigLocation;

const
  cFileName = 'workspaces.json';

var
  GLoaded: Boolean = False;
  GItems: TList<TWorkspaceSnapshot>;
  GStoragePathOverride: string;
  GBoundId: string;
  GBoundName: string;
  GBoundFingerprint: string;

function StoragePath: string;
begin
  if GStoragePathOverride <> '' then
    Exit(GStoragePathOverride);
  Result := GetConfigFilePath(cFileName);
end;

function FingerprintOf(const ANodes: TArray<TWorkspaceLinkNode>): string;
var
  CopyNodes: TArray<TWorkspaceLinkNode>;
  I: Integer;
  Parts: TStringBuilder;
begin
  CopyNodes := Copy(ANodes);
  TArray.Sort<TWorkspaceLinkNode>(CopyNodes,
    TComparer<TWorkspaceLinkNode>.Construct(
      function(const A, B: TWorkspaceLinkNode): Integer
      begin
        Result := CompareText(A.Path, B.Path);
      end));
  Parts := TStringBuilder.Create;
  try
    for I := 0 to High(CopyNodes) do
    begin
      if I > 0 then
        Parts.Append(#10);
      Parts.Append(CopyNodes[I].Path).Append(#1)
        .Append(CopyNodes[I].TargetURI).Append(#1);
      if CopyNodes[I].IsDir then
        Parts.Append('1')
      else
        Parts.Append('0');
      Parts.Append(#1);
      if CopyNodes[I].IsVirt then
        Parts.Append('1')
      else
        Parts.Append('0');
    end;
    Result := Parts.ToString;
  finally
    Parts.Free;
  end;
end;

function NodeFromJson(Obj: TJSONObject): TWorkspaceLinkNode;
var
  DirVal, VirtVal: Boolean;
begin
  Result := Default(TWorkspaceLinkNode);
  if Obj = nil then
    Exit;
  if not Obj.TryGetValue<string>('path', Result.Path) then
    Result.Path := '';
  Result.Path := Trim(Result.Path);
  if not Obj.TryGetValue<string>('target', Result.TargetURI) then
    Result.TargetURI := '';
  if not Obj.TryGetValue<Boolean>('dir', DirVal) then
    DirVal := False;
  if not Obj.TryGetValue<Boolean>('virt', VirtVal) then
    VirtVal := False;
  Result.IsDir := DirVal;
  Result.IsVirt := VirtVal;
end;

function NodeToJson(const ANode: TWorkspaceLinkNode): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('path', ANode.Path);
  if ANode.TargetURI <> '' then
    Result.AddPair('target', ANode.TargetURI);
  if ANode.IsDir then
    Result.AddPair('dir', TJSONBool.Create(True));
  if ANode.IsVirt then
    Result.AddPair('virt', TJSONBool.Create(True));
end;

procedure BindLive(const AId, AName: string);
begin
  GBoundId := AId;
  GBoundName := AName;
  GBoundFingerprint := FingerprintOf(WorkspaceExportLinks);
end;

procedure EnsureList;
begin
  if GItems = nil then
    GItems := TList<TWorkspaceSnapshot>.Create;
end;

procedure SaveLocked;
var
  Path: string;
  Root, Obj: TJSONObject;
  Arr, Nodes: TJSONArray;
  I, J: Integer;
begin
  if GItems = nil then
    Exit;
  Path := StoragePath;
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('items', Arr);
    for I := 0 to GItems.Count - 1 do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', GItems[I].Id);
      Obj.AddPair('name', GItems[I].Name);
      Nodes := TJSONArray.Create;
      Obj.AddPair('nodes', Nodes);
      for J := 0 to High(GItems[I].Nodes) do
        Nodes.AddElement(NodeToJson(GItems[I].Nodes[J]));
      Arr.AddElement(Obj);
    end;
    ForceDirectories(ExtractFilePath(Path));
    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

procedure EnsureLoaded;
var
  Path, Content: string;
  RootVal: TJSONValue;
  Root, Obj, NodeObj: TJSONObject;
  Arr, Nodes: TJSONArray;
  I, J: Integer;
  Snap: TWorkspaceSnapshot;
  Item: TJSONValue;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  EnsureList;
  GItems.Clear;
  Path := StoragePath;
  if not TFile.Exists(Path) then
    Exit;
  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    RootVal := TJSONObject.ParseJSONValue(Content);
    if not (RootVal is TJSONObject) then
    begin
      RootVal.Free;
      Exit;
    end;
    Root := TJSONObject(RootVal);
    try
      if not Root.TryGetValue<TJSONArray>('items', Arr) then
        Exit;
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I];
        if not (Item is TJSONObject) then
          Continue;
        Obj := TJSONObject(Item);
        Snap := Default(TWorkspaceSnapshot);
        if not Obj.TryGetValue<string>('id', Snap.Id) then
          Continue;
        Snap.Id := Trim(Snap.Id);
        if Snap.Id = '' then
          Continue;
        if not Obj.TryGetValue<string>('name', Snap.Name) then
          Snap.Name := Snap.Id;
        Snap.Name := Trim(Snap.Name);
        if Obj.TryGetValue<TJSONArray>('nodes', Nodes) then
        begin
          SetLength(Snap.Nodes, Nodes.Count);
          for J := 0 to Nodes.Count - 1 do
            if Nodes.Items[J] is TJSONObject then
            begin
              NodeObj := TJSONObject(Nodes.Items[J]);
              Snap.Nodes[J] := NodeFromJson(NodeObj);
            end;
        end;
        GItems.Add(Snap);
      end;
    finally
      Root.Free;
    end;
  except
    GItems.Clear;
  end;
end;

function NewSnapshotId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(Copy(GUIDToString(G), 2, 36));
end;

procedure WorkspaceLibraryUsePath(const APath: string);
begin
  GStoragePathOverride := APath;
  GLoaded := False;
  GBoundId := '';
  GBoundName := '';
  GBoundFingerprint := '';
end;

procedure WorkspaceLibraryResetForTests;
begin
  GLoaded := True;
  EnsureList;
  GItems.Clear;
  GBoundId := '';
  GBoundName := '';
  GBoundFingerprint := FingerprintOf(WorkspaceExportLinks);
end;

function WorkspaceLibraryGet: TArray<TWorkspaceSnapshot>;
var
  I: Integer;
begin
  EnsureLoaded;
  SetLength(Result, GItems.Count);
  for I := 0 to GItems.Count - 1 do
    Result[I] := GItems[I];
  TArray.Sort<TWorkspaceSnapshot>(Result,
    TComparer<TWorkspaceSnapshot>.Construct(
      function(const A, B: TWorkspaceSnapshot): Integer
      begin
        Result := CompareText(A.Name, B.Name);
        if Result = 0 then
          Result := CompareText(A.Id, B.Id);
      end));
end;

function WorkspaceLibraryFindById(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AId = '' then
    Exit;
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Id, AId) then
      Exit(I);
end;

function WorkspaceLibraryFindByName(const AName: string): Boolean;
var
  I: Integer;
  N: string;
begin
  Result := False;
  N := Trim(AName);
  if N = '' then
    Exit;
  EnsureLoaded;
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Name, N) then
      Exit(True);
end;

function WorkspaceLibrarySaveCurrent(const AName: string): Boolean;
var
  N: string;
  Nodes: TArray<TWorkspaceLinkNode>;
  I: Integer;
  Snap: TWorkspaceSnapshot;
  Id: string;
begin
  Result := False;
  N := Trim(AName);
  if N = '' then
    Exit;
  Nodes := WorkspaceExportLinks;
  if Length(Nodes) = 0 then
    Exit;
  EnsureLoaded;
  Id := '';
  for I := 0 to GItems.Count - 1 do
    if SameText(GItems[I].Name, N) then
    begin
      Id := GItems[I].Id;
      Break;
    end;
  if (Id = '') and (GBoundId <> '') and SameText(GBoundName, N) then
    Id := GBoundId;
  if Id = '' then
    Id := NewSnapshotId;
  Snap.Id := Id;
  Snap.Name := N;
  Snap.Nodes := Nodes;
  I := WorkspaceLibraryFindById(Id);
  if I >= 0 then
    GItems[I] := Snap
  else
    GItems.Add(Snap);
  try
    SaveLocked;
  except
    Exit;
  end;
  BindLive(Id, N);
  Result := True;
end;

function WorkspaceLibraryRestore(const AId: string): Boolean;
var
  I: Integer;
  Snap: TWorkspaceSnapshot;
begin
  Result := False;
  EnsureLoaded;
  I := WorkspaceLibraryFindById(AId);
  if I < 0 then
    Exit;
  Snap := GItems[I];
  WorkspaceImportLinks(Snap.Nodes);
  BindLive(Snap.Id, Snap.Name);
  Result := True;
end;

procedure WorkspaceLibraryDelete(const AId: string);
var
  I: Integer;
begin
  EnsureLoaded;
  I := WorkspaceLibraryFindById(AId);
  if I < 0 then
    Exit;
  GItems.Delete(I);
  if SameText(GBoundId, AId) then
  begin
    GBoundId := '';
    GBoundName := '';
    GBoundFingerprint := '';
  end;
  try
    SaveLocked;
  except
  end;
end;

procedure WorkspaceLibraryRename(const AId, ANewName: string);
var
  I: Integer;
  Snap: TWorkspaceSnapshot;
  N: string;
begin
  N := Trim(ANewName);
  if N = '' then
    Exit;
  EnsureLoaded;
  I := WorkspaceLibraryFindById(AId);
  if I < 0 then
    Exit;
  Snap := GItems[I];
  Snap.Name := N;
  GItems[I] := Snap;
  if SameText(GBoundId, AId) then
    GBoundName := N;
  try
    SaveLocked;
  except
  end;
end;

function WorkspaceLiveId: string;
begin
  Result := GBoundId;
end;

function WorkspaceLiveName: string;
begin
  Result := GBoundName;
end;

function WorkspaceLiveHasLinks: Boolean;
begin
  Result := WorkspaceLinkCount > 0;
end;

function WorkspaceLiveIsDirty: Boolean;
begin
  Result := FingerprintOf(WorkspaceExportLinks) <> GBoundFingerprint;
end;

function WorkspaceLiveCaption: string;
begin
  if GBoundName = '' then
    Result := '(unsaved)'
  else
    Result := GBoundName;
  if WorkspaceLiveIsDirty then
    Result := Result + '*';
end;

function WorkspaceSnapshotDisplayLabel(const ASnap: TWorkspaceSnapshot): string;
begin
  Result := ASnap.Name;
  if SameText(ASnap.Id, GBoundId) then
    Result := Result + '  [current]';
  Result := Result + Format('  (%d)', [Length(ASnap.Nodes)]);
end;

initialization

finalization
  FreeAndNil(GItems);

end.
