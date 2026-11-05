library MetaPlugin;

{ Native MTN2 plugin: a status line segment with the metadata of the file under
  the panel cursor - the size and the camera of an image, the tags of an MP3
  file, the version of an executable. A worker thread reads the file; the
  segment is set on the main thread through PostToMain. }

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uMetaFormat in 'uMetaFormat.pas',
  uMetaReader in 'uMetaReader.pas';

const
  cPluginId = 'mtn.meta';
  cSegmentId = 'meta';
  cPollMs = 400;
  cPanelColumnsAbi = 9;
  // The panel list is read every cListEveryTicks-th tick: it holds every row.
  cListEveryTicks = 3;
  cMaxCellFiles = 2000;
  cCellsPerPost = 100;
  cColumnsJson =
    '[{"id":"dim","title":"Size px","title_key":"ui.col.dim","width":10,"align":"right","default":true,"sortable":true},' +
    '{"id":"camera","title":"Camera","title_key":"ui.col.camera","width":20,"default":true,"sortable":true},' +
    '{"id":"artist","title":"Artist","title_key":"ui.col.artist","width":20,"default":true,"sortable":true},' +
    '{"id":"title","title":"Title","title_key":"ui.col.title","width":24,"default":true,"sortable":true}]';

type
  TMetaWorker = class(TThread)
  private
    FWake: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Wake;
  end;

var
  GHostApi: THostApiTable;
  GLock: TCriticalSection;
  GCursorUri: string;
  GPendingText: string;
  GWorker: TMetaWorker;
  GTick: Integer;
  // The folder of the active panel and its files that have metadata.
  GFolderUri: string;
  GFileNames: TArray<string>;
  // The cells the worker has computed, applied on the main thread.
  GCellsFolder: string;
  GCellsJson: string;

procedure SetSegment(const AText: string);
var
  Id, Seg, Text: UTF8String;
begin
  if not Assigned(GHostApi.SetStatusSegment) then
    Exit;
  Id := UTF8String(cPluginId);
  Seg := UTF8String(cSegmentId);
  Text := UTF8String(AText);
  GHostApi.SetStatusSegment(PAnsiChar(Id), PAnsiChar(Seg), PAnsiChar(Text));
end;

// The address of the row under the cursor in the active panel.
function CursorOf(const APanelInfo: string): string;
var
  Root, Side: TJSONValue;
  Active: string;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(APanelInfo);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if Side is TJSONObject then
      Side.TryGetValue<string>('cursor', Result);
  finally
    Root.Free;
  end;
end;

// The active panel's folder and the names of its rows that can have metadata.
procedure ReadPanelFiles;
var
  Buf: UTF8String;
  Len: Int64;
  Root, Rows: TJSONValue;
  Row: TJSONValue;
  Folder, Name: string;
  Names: TArray<string>;
  IsDir: Boolean;
begin
  if not Assigned(GHostApi.PanelList) then
    Exit;
  Len := GHostApi.PanelList(-1, nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelList(-1, PAnsiChar(Buf), Length(Buf));
  if (Len <= 0) or (Len >= Length(Buf)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(UTF8ToString(PAnsiChar(Buf)));
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('uri', Folder) then
      Exit;
    Names := nil;
    Rows := TJSONObject(Root).GetValue('rows');
    if Rows is TJSONArray then
      for Row in TJSONArray(Rows) do
      begin
        if not (Row is TJSONObject) or not Row.TryGetValue<string>('name', Name) then
          Continue;
        if not Row.TryGetValue<Boolean>('dir', IsDir) then
          IsDir := False;
        if IsDir or (MetaKindOf(Name) = '') or (Length(Names) >= cMaxCellFiles) then
          Continue;
        SetLength(Names, Length(Names) + 1);
        Names[High(Names)] := Name;
      end;
    GLock.Enter;
    try
      GFolderUri := Folder;
      GFileNames := Names;
    finally
      GLock.Leave;
    end;
  finally
    Root.Free;
  end;
end;

{ Main thread: PanelInfo and PanelList are read here only. }
procedure MainTick(AUserData: Pointer); cdecl;
var
  Buf: UTF8String;
  Len: Int64;
  Uri: string;
begin
  try
    if (GHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(GHostApi.SetPanelColumnValues) then
    begin
      Inc(GTick);
      if GTick mod cListEveryTicks = 1 then
        ReadPanelFiles;
    end;
    if not Assigned(GHostApi.PanelInfo) then
      Exit;
    Len := GHostApi.PanelInfo(nil, 0);
    if Len <= 0 then
      Exit;
    SetLength(Buf, Len + 1);
    Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
    if (Len <= 0) or (Len >= Length(Buf)) then
      Exit;
    Uri := CursorOf(UTF8ToString(PAnsiChar(Buf)));
    GLock.Enter;
    try
      GCursorUri := Uri;
    finally
      GLock.Leave;
    end;
  except
  end;
end;

procedure MainApply(AUserData: Pointer); cdecl;
var
  Text: string;
begin
  try
    GLock.Enter;
    try
      Text := GPendingText;
    finally
      GLock.Leave;
    end;
    SetSegment(Text);
  except
  end;
end;

procedure MainApplyCells(AUserData: Pointer); cdecl;
var
  Folder, Json: string;
  Id, FolderU, JsonU: UTF8String;
begin
  try
    GLock.Enter;
    try
      Folder := GCellsFolder;
      Json := GCellsJson;
    finally
      GLock.Leave;
    end;
    if (Folder = '') or not Assigned(GHostApi.SetPanelColumnValues) then
      Exit;
    Id := UTF8String(cPluginId);
    FolderU := UTF8String(Folder);
    JsonU := UTF8String(Json);
    GHostApi.SetPanelColumnValues(PAnsiChar(Id), PAnsiChar(FolderU), PAnsiChar(JsonU));
  except
  end;
end;

procedure PostToMain(ACallback: THostMainCallback);
var
  Id: UTF8String;
begin
  if not Assigned(GHostApi.PostToMain) then
    Exit;
  Id := UTF8String(cPluginId);
  GHostApi.PostToMain(PAnsiChar(Id), ACallback, nil);
end;

constructor TMetaWorker.Create;
begin
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TMetaWorker.Destroy;
begin
  FWake.Free;
  inherited;
end;

procedure TMetaWorker.Wake;
begin
  FWake.SetEvent;
end;

// A key that changes when the folder or the set of files with metadata changes.
function FilesKey(const AFolder: string; const ANames: TArray<string>): string;
var
  Name: string;
begin
  Result := AFolder + '|' + IntToStr(Length(ANames));
  for Name in ANames do
    Result := Result + '|' + Name;
end;

// "1920x1080" as {"t": text, "n": pixel count}: the column sorts by image area.
function DimensionCell(const ADims: string): TJSONObject;
var
  P: Integer;
  W, H: Int64;
begin
  Result := TJSONObject.Create;
  Result.AddPair('t', ADims);
  P := Pos('x', ADims);
  if (P > 1) and TryStrToInt64(Copy(ADims, 1, P - 1), W) and
     TryStrToInt64(Copy(ADims, P + 1, MaxInt), H) then
    Result.AddPair('n', TJSONNumber.Create(W * H));
end;

// Computes the column cells of the active panel's files and hands them to the main
// thread in growing batches. False when the worker was asked to stop.
function ComputeCells(AWorker: TMetaWorker; const AFolder: string;
  const ANames: TArray<string>): Boolean;
var
  Root, Cell: TJSONObject;
  Cells: TMetaCells;
  Name, Path: string;
  I: Integer;
begin
  Result := True;
  if not AFolder.StartsWith('file:', True) then
    Exit;
  Root := TJSONObject.Create;
  try
    for I := 0 to High(ANames) do
    begin
      if AWorker.Terminated then
        Exit(False);
      Name := ANames[I];
      Path := FileUriToPath(AFolder);
      if Path = '' then
        Exit;
      Cells := ReadFileCells(IncludeTrailingPathDelimiter(Path) + Name);
      if (Cells.Dimensions <> '') or (Cells.Camera <> '') or (Cells.Artist <> '') or
         (Cells.Title <> '') then
      begin
        Cell := TJSONObject.Create;
        if Cells.Dimensions <> '' then
          Cell.AddPair('dim', DimensionCell(Cells.Dimensions));
        if Cells.Camera <> '' then
          Cell.AddPair('camera', Cells.Camera);
        if Cells.Artist <> '' then
          Cell.AddPair('artist', Cells.Artist);
        if Cells.Title <> '' then
          Cell.AddPair('title', Cells.Title);
        Root.AddPair(Name, Cell);
      end;
      if ((I + 1) mod cCellsPerPost = 0) or (I = High(ANames)) then
      begin
        GLock.Enter;
        try
          GCellsFolder := AFolder;
          GCellsJson := Root.ToJSON;
        finally
          GLock.Leave;
        end;
        PostToMain(MainApplyCells);
      end;
    end;
  finally
    Root.Free;
  end;
end;

procedure TMetaWorker.Execute;
var
  Uri, LastUri, Path, Text, LastText, Folder, FilesKeyNow, LastFilesKey: string;
  Names: TArray<string>;
begin
  LastUri := #0;
  LastText := #0;
  LastFilesKey := #0;
  while not Terminated do
  begin
    PostToMain(MainTick);
    FWake.WaitFor(cPollMs);
    if Terminated then
      Break;
    if (GHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(GHostApi.SetPanelColumnValues) then
    begin
      GLock.Enter;
      try
        Folder := GFolderUri;
        Names := GFileNames;
      finally
        GLock.Leave;
      end;
      FilesKeyNow := FilesKey(Folder, Names);
      if (Folder <> '') and (FilesKeyNow <> LastFilesKey) then
      begin
        LastFilesKey := FilesKeyNow;
        ComputeCells(Self, Folder, Names);
      end;
    end;
    GLock.Enter;
    try
      Uri := GCursorUri;
    finally
      GLock.Leave;
    end;
    if Uri = LastUri then
      Continue;
    LastUri := Uri;
    Text := '';
    if Uri.StartsWith('file:', True) then
    begin
      Path := FileUriToPath(Uri);
      if Path <> '' then
        Text := DescribeFile(Path);
    end;
    if Terminated then
      Break;
    if Text <> LastText then
    begin
      LastText := Text;
      GLock.Enter;
      try
        GPendingText := Text;
      finally
        GLock.Leave;
      end;
      PostToMain(MainApply);
    end;
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  if AHostApi = nil then
    Exit(-1);
  GHostApi := AHostApi^;
  if not (Assigned(GHostApi.SetStatusSegment) and Assigned(GHostApi.PanelInfo) and
     Assigned(GHostApi.PostToMain)) then
    Exit(-1);
  if (GHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(GHostApi.RegisterPanelColumns) then
    GHostApi.RegisterPanelColumns(PAnsiChar(UTF8String(cPluginId)), 'file',
      PAnsiChar(UTF8String(cColumnsJson)));
  GLock := TCriticalSection.Create;
  GWorker := TMetaWorker.Create;
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  if Assigned(GWorker) then
  begin
    GWorker.Terminate;
    GWorker.Wake;
    GWorker.WaitFor;
    FreeAndNil(GWorker);
  end;
  SetSegment('');
  if (GHostApi.AbiVersion >= cPanelColumnsAbi) and Assigned(GHostApi.RegisterPanelColumns) then
    GHostApi.RegisterPanelColumns(PAnsiChar(UTF8String(cPluginId)), 'file', nil);
  FreeAndNil(GLock);
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
