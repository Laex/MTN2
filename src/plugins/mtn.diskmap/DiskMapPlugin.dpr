library DiskMapPlugin;

{ Native MTN2 plugin: with the cursor on a folder, Quick View (Ctrl+Q) draws a
  treemap of the space its files take. The folder is scanned in a background
  thread a moment after the cursor stops on it; the tiles grow while the scan
  runs. Tab gives the keyboard to the map: arrows move between tiles, Enter
  zooms into a folder, Backspace zooms out, G shows the tile in the file panel.
  Only local folders are scanned; any other folder keeps the plain Quick View. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Diagnostics,
  System.Generics.Collections, System.JSON,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTreemap in 'uTreemap.pas',
  uDiskMapTree in 'uDiskMapTree.pas',
  uDiskMapRaster in 'uDiskMapRaster.pas',
  uDiskMapView in 'uDiskMapView.pas';

const
  cPluginId = 'mtn.diskmap';
  cModeQuick = 4;
  cPriority = 60;
  cSurfacePanel = 2;
  cMouseDown = 0;
  cMouseDouble = 4;
  cMouseSize = 5;
  cSettingEnabled = 'enabled';
  // The scan starts when the cursor has stayed on the folder this long, so
  // scrolling through a list does not scan every folder it passes.
  cStartDelayMs = 150;
  cTickMs = 100;
  // The map is redrawn at most this often while the scan finds new entries.
  cRedrawMs = 250;
  cCacheMax = 12;
  // A finished scan is reused for this long (a day is 1).
  cCacheFresh = 30 / 86400;

type
  TSession = class
    Handle: Int64;
    View: TDiskMapView;
    Scan: IDiskScan;
    Opened: TStopwatch;
    Started: Boolean;
    Finished: Boolean;
    Width, Height: Integer;
    LastEntries: Int64;
    Drawn: Boolean;
    LastDraw: TStopwatch;
    destructor Destroy; override;
  end;

var
  GHostApi: THostApiTable;
  GSessions: TList<TSession>;
  GCache: TList<IDiskScan>;
  GEnabled: Boolean = True;

destructor TSession.Destroy;
begin
  if Assigned(Scan) and not Scan.Scan.Finished then
    Scan.Scan.Cancel;
  View.Free;
  inherited;
end;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..255] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

function GetSettingText(const AKey: string): string;
var
  Id, Key: UTF8String;
  Buf: array[0..63] of AnsiChar;
begin
  Result := '';
  if not Assigned(GHostApi.GetSetting) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Buf[0] := #0;
  if GHostApi.GetSetting(PAnsiChar(Id), PAnsiChar(Key), @Buf[0], SizeOf(Buf)) >= 0 then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure PutSettingText(const AKey, AValue: string);
var
  Id, Key, Value: UTF8String;
begin
  if not Assigned(GHostApi.SetSetting) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Value := UTF8String(AValue);
  GHostApi.SetSetting(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Value));
end;

{ file:///C:/dir/a%20b -> C:\dir\a b (file:///home/a%20b -> /home/a b on Linux);
  '' for any other URI. }
function UriToPath(const AUri: string): string;
begin
  if SameText(Copy(AUri, 1, 8), 'file:///') then
    Result := FileUriToPath(AUri)
  else
    Result := '';
end;

{ Finished scans, newest last. }
function FindCached(const APath: string): IDiskScan;
var
  I: Integer;
  S: TDiskScan;
begin
  Result := nil;
  for I := GCache.Count - 1 downto 0 do
  begin
    S := GCache[I].Scan;
    if Now - S.FinishedAt > cCacheFresh then
      GCache.Delete(I)
    else if SameLocalPath(S.Path, APath) then
      Result := GCache[I];
  end;
end;

procedure Remember(const AScan: IDiskScan);
var
  I: Integer;
begin
  for I := GCache.Count - 1 downto 0 do
    if SameLocalPath(GCache[I].Scan.Path, AScan.Scan.Path) then
      GCache.Delete(I);
  GCache.Add(AScan);
  while GCache.Count > cCacheMax do
    GCache.Delete(0);
end;

procedure Redraw(ACtx: TSession);
var
  R: TRaster;
  Title, Status: UTF8String;
begin
  if (ACtx.Width <= 0) or (ACtx.Height <= 0) then
    Exit;
  R := TRaster.Create(ACtx.Width, ACtx.Height);
  try
    ACtx.View.Render(R);
    GHostApi.SurfaceSetFrame(ACtx.Handle, R.Width, R.Height, @R.Pixels[0], Length(R.Pixels));
    ACtx.Drawn := True;
    ACtx.LastDraw := TStopwatch.StartNew;
  finally
    R.Free;
  end;
  Title := UTF8String(ACtx.View.Title);
  Status := UTF8String(ACtx.View.StatusText);
  GHostApi.SurfaceSetInfo(ACtx.Handle, PAnsiChar(Title), PAnsiChar(Status));
end;

{ Closes the surface from the plugin's side; the host sends no callback then. }
procedure CloseSession(ACtx: TSession);
begin
  GSessions.Remove(ACtx);
  if Assigned(GHostApi.SurfaceClose) then
    GHostApi.SurfaceClose(ACtx.Handle);
  ACtx.Free;
end;

procedure GoToInPanel(const APath: string; AIsFile: Boolean);
var
  Uri: UTF8String;
begin
  Uri := UTF8String(PathToFileUri(APath));
  if AIsFile then
  begin
    if Assigned(GHostApi.PanelSetCursor) then
      GHostApi.PanelSetCursor(-1, PAnsiChar(Uri));
  end
  else if Assigned(GHostApi.PanelGoto) then
    GHostApi.PanelGoto(-1, PAnsiChar(Uri));
end;

function OnSurfaceKey(AUserData: Pointer; AKey: PAnsiChar): Int64; cdecl;
var
  Ctx: TSession;
  Path: string;
  IsFile: Boolean;
begin
  Result := 0;
  try
    Ctx := TSession(AUserData);
    if AKey = nil then
      Exit;
    case Ctx.View.HandleKey(string(AKey), Path, IsFile) of
      dkHandled:
        begin
          Redraw(Ctx);
          Result := 1;
        end;
      dkGoto:
        begin
          GoToInPanel(Path, IsFile);
          CloseSession(Ctx);
          Result := 1;
        end;
    end;
  except
    Result := 0;
  end;
end;

function OnSurfaceMouse(AUserData: Pointer; AKind, AX, AY, AWidth, AHeight,
  AButton, AExtra, AShift: Int64): Int64; cdecl;
var
  Ctx: TSession;
begin
  Result := 0;
  try
    Ctx := TSession(AUserData);
    case AKind of
      cMouseSize:
        begin
          Ctx.Width := Integer(AWidth);
          Ctx.Height := Integer(AHeight);
          Redraw(Ctx);
          Result := 1;
        end;
      cMouseDown:
        begin
          if AButton = 2 then
            Ctx.View.ZoomOut
          else
            Ctx.View.Click(Integer(AX), Integer(AY), False);
          Redraw(Ctx);
          Result := 1;
        end;
      cMouseDouble:
        begin
          Ctx.View.Click(Integer(AX), Integer(AY), True);
          Redraw(Ctx);
          Result := 1;
        end;
    end;
  except
    Result := 0;
  end;
end;

procedure OnSurfaceTick(AUserData: Pointer); cdecl;
var
  Ctx: TSession;
  S: TDiskScan;
begin
  try
    Ctx := TSession(AUserData);
    if not Ctx.Started then
    begin
      if Ctx.Opened.ElapsedMilliseconds < cStartDelayMs then
        Exit;
      Ctx.Started := True;
      Ctx.Scan.Scan.Start;
    end;
    S := Ctx.Scan.Scan;
    if S.Finished then
    begin
      if not Ctx.Finished then
      begin
        Ctx.Finished := True;
        GHostApi.SurfaceSetTimer(Ctx.Handle, 0);
        Remember(Ctx.Scan);
        Redraw(Ctx);
      end;
    end
    else if (Ctx.Width > 0) and (not Ctx.Drawn or ((S.Entries <> Ctx.LastEntries) and
      (Ctx.LastDraw.ElapsedMilliseconds >= cRedrawMs))) then
    begin
      Ctx.LastEntries := S.Entries;
      Redraw(Ctx);
    end;
  except
    // A failed tick is retried by the next one.
  end;
end;

procedure OnSurfaceClosed(AUserData: Pointer); cdecl;
var
  Ctx: TSession;
begin
  Ctx := TSession(AUserData);
  if Assigned(GSessions) then
    GSessions.Remove(Ctx);
  Ctx.Free;
end;

{ Opens the map of APath in the Quick View panel; False when the folder cannot be
  shown (not local, not there, the plugin switched off). }
function OpenFolder(const APath: string): Boolean;
var
  Ctx: TSession;
  Scan: IDiskScan;
  PluginId, Title: UTF8String;
  Cached: Boolean;
begin
  Result := False;
  if not GEnabled or not Assigned(GHostApi.SurfaceOpenEx) or
     not Assigned(GHostApi.SurfaceSetFrame) or not TDirectory.Exists(APath) then
    Exit;
  Scan := FindCached(APath);
  Cached := Scan <> nil;
  if not Cached then
    Scan := TDiskScan.Create(APath, TDiskLimits.Standard);
  Ctx := TSession.Create;
  Ctx.Scan := Scan;
  Ctx.View := TDiskMapView.Create(Scan);
  Ctx.View.TextScanning := Tr('status.scanning', 'scanning...');
  Ctx.View.TextIncomplete := Tr('status.incomplete', 'incomplete (limit reached)');
  Ctx.View.TextRest := Tr('status.rest', 'other files');
  Ctx.View.TextEmpty := Tr('status.empty', 'empty');
  Ctx.View.TextTotal := Tr('status.total', 'total');
  Ctx.Opened := TStopwatch.StartNew;
  Ctx.Started := Cached;
  Ctx.Finished := Cached;
  PluginId := UTF8String(cPluginId);
  Title := UTF8String(Ctx.View.Title);
  Ctx.Handle := GHostApi.SurfaceOpenEx(PAnsiChar(PluginId), PAnsiChar(Title), cSurfacePanel,
    @OnSurfaceKey, @OnSurfaceTick, @OnSurfaceClosed, @OnSurfaceMouse, Ctx);
  if Ctx.Handle <= 0 then
  begin
    Ctx.Free;
    Exit;
  end;
  GSessions.Add(Ctx);
  if not Cached then
    GHostApi.SurfaceSetTimer(Ctx.Handle, cTickMs);
  Result := True;
end;

function OnDocument(AUserData: Pointer; AUri, AMode, ARedirect: PAnsiChar;
  ARedirectCap: Int64): Int64; cdecl;
const
  cFolderSuffix = '#dir';
var
  Uri, Path: string;
begin
  Result := 0;
  try
    if (AUri = nil) or (AMode = nil) or not SameText(string(AMode), 'quick') then
      Exit;
    Uri := UTF8ToString(AUri);
    if not Uri.EndsWith(cFolderSuffix) then
      Exit;
    Path := UriToPath(Copy(Uri, 1, Length(Uri) - Length(cFolderSuffix)));
    if (Path <> '') and OpenFolder(Path) then
      Result := 1;
  except
    // Never let an exception cross into the host; the plain Quick View stays.
    Result := 0;
  end;
end;

procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;
  V: TJSONValue;
begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      V := TJSONObject(Root).GetValue(cSettingEnabled);
      if V is TJSONBool then
        GEnabled := TJSONBool(V).AsBoolean
      else
        GEnabled := (V <> nil) and (SameText(V.Value, 'true') or (V.Value = '1'));
    finally
      Root.Free;
    end;
    if GEnabled then
      PutSettingText(cSettingEnabled, '1')
    else
      PutSettingText(cSettingEnabled, '0');
  except
    // Never let an exception cross into the host.
  end;
end;

procedure AddControl(AChildren: TJSONArray; const AType, AId, AText: string;
  ACol, ARow, AWidth: Integer; AChecked: Boolean = False; ADefault: Boolean = False;
  ACancel: Boolean = False);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.AddPair('type', AType);
  if AId <> '' then
    O.AddPair('id', AId);
  if AText <> '' then
    O.AddPair('text', AText);
  if AType = 'checkbox' then
    O.AddPair('checked', TJSONBool.Create(AChecked));
  if ADefault then
    O.AddPair('default', TJSONBool.Create(True));
  if ACancel then
    O.AddPair('cancel', TJSONBool.Create(True));
  O.AddPair('col', TJSONNumber.Create(ACol));
  O.AddPair('row', TJSONNumber.Create(ARow));
  O.AddPair('width', TJSONNumber.Create(AWidth));
  O.AddPair('height', TJSONNumber.Create(1));
  AChildren.AddElement(O);
end;

{ The "Settings" button of the plugins dialog. }
procedure OnConfigure(AUserData: Pointer); cdecl;
var
  Decl: TJSONObject;
  Kids: TJSONArray;
  Json, Plugin: UTF8String;
begin
  try
    if not Assigned(GHostApi.ShowDialog) then
      Exit;
    Decl := TJSONObject.Create;
    try
      Decl.AddPair('type', 'dialog');
      Decl.AddPair('version', '2.0');
      Decl.AddPair('title', Tr('dlg.title', 'Folder map'));
      Decl.AddPair('width', TJSONNumber.Create(72));
      Decl.AddPair('height', TJSONNumber.Create(9));
      Kids := TJSONArray.Create;
      Decl.AddPair('children', Kids);
      AddControl(Kids, 'checkbox', cSettingEnabled,
        Tr('dlg.enabled', '&Show a map of the folder under the cursor in Quick View'), 3, 2, 66,
        GEnabled);
      AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), 22, 5, 12, False, True);
      AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 37, 5, 12, False,
        False, True);
      Json := UTF8String(Decl.ToJSON);
    finally
      Decl.Free;
    end;
    Plugin := UTF8String(cPluginId);
    GHostApi.ShowDialog(PAnsiChar(Plugin), PAnsiChar(Json), @OnSettingsAnswer, nil);
  except
    // Never let an exception cross into the host.
  end;
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
var
  PluginId, Extensions: UTF8String;
begin
  if (AHostApi = nil) or (AHostApi.AbiVersion < 2) or
     not Assigned(AHostApi.RegisterDocumentProvider) then
    Exit(-1);
  GHostApi := AHostApi^;
  GSessions := TList<TSession>.Create;
  GCache := TList<IDiskScan>.Create;
  GEnabled := GetSettingText(cSettingEnabled) <> '0';
  PluginId := UTF8String(cPluginId);
  if Assigned(GHostApi.RegisterSettings) then
    GHostApi.RegisterSettings(PAnsiChar(PluginId), @OnConfigure, nil);
  Extensions := UTF8String('.mtn-directory');
  Result := GHostApi.RegisterDocumentProvider(PAnsiChar(PluginId), PAnsiChar(Extensions),
    cModeQuick, @OnDocument, nil, cPriority);
end;

procedure mtn_plugin_shutdown; cdecl;
var
  Ctx: TSession;
begin
  if Assigned(GSessions) then
  begin
    for Ctx in GSessions.ToArray do
    begin
      if Assigned(GHostApi.SurfaceClose) then
        GHostApi.SurfaceClose(Ctx.Handle);
      Ctx.Free;
    end;
    FreeAndNil(GSessions);
  end;
  FreeAndNil(GCache);
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
