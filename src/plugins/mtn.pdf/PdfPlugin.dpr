library PdfPlugin;

{ Native MTN2 plugin: F3 on a .pdf file shows its pages as pictures drawn by
  PDFium in a viewer tab (PgUp/PgDn, arrows, +/-, wheel, drag); Quick View
  (Ctrl+Q) shows the text of the first pages or, by the plugin settings, the
  rendered first page. Without pdfium.dll (libpdfium.so on Linux) next to the
  plugin, or for a file PDFium cannot open (damaged, password protected), the
  plugin steps aside and the next provider or the built-in viewer runs. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  System.Generics.Collections, System.JSON,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uPdfium in 'uPdfium.pas',
  uPdfView in 'uPdfView.pas';

const
  cPluginId = 'mtn.pdf';
  cExtensions = '.pdf';
  cModeView = 1;
  cModeQuick = 4;
  cPriority = 40;
  cQuickMaxBytes = 16 * 1024 * 1024;
  cQuickMaxPages = 300;
  cQuickMaxChars = 2000000;
  cTempFolder = 'mtn2-pdf';
  cSettingAlwaysRender = 'quick.alwaysRender';
  cSettingRenderFallback = 'quick.renderFallback';
  cQuickPictureWidth = 1200;
  cKeepDays = 1;
  cSurfacePanel = 2;
  cMouseWheel = 3;
  cMouseSize = 5;
  cMouseDown = 0;
  cMouseUp = 1;
  cMouseMove = 2;
  cShiftCtrl = 2;

type
  TPdfContext = class
    Doc: TPdfDocument;
    View: TPdfView;
    Handle: Int64;
    Title: string;
    Dragging: Boolean;
    DragX, DragY: Integer;
    destructor Destroy; override;
  end;

var
  GHostApi: THostApiTable;
  GContexts: TList<TPdfContext>;
  // Quick View settings: show the rendered first page always, or only for a
  // document without extractable text (a scan).
  GQuickAlwaysRender: Boolean;
  GQuickRenderFallback: Boolean = True;

destructor TPdfContext.Destroy;
begin
  View.Free;
  Doc.Free;
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

{ file:///C:/dir/a%20b.pdf -> C:\dir\a b.pdf (file:///home/a%20b.pdf -> /home/a b.pdf
  on Linux); '' for any other URI. }
function UriToPath(const AUri: string): string;
begin
  if SameText(Copy(AUri, 1, 8), 'file:///') then
    Result := FileUriToPath(AUri)
  else
    Result := '';
end;

procedure RemoveOldTempFiles;
var
  F: string;
begin
  try
    if not TDirectory.Exists(TPath.Combine(TPath.GetTempPath, cTempFolder)) then
      Exit;
    for F in TDirectory.GetFiles(TPath.Combine(TPath.GetTempPath, cTempFolder)) do
      if Now - TFile.GetLastWriteTime(F) > cKeepDays then
        TFile.Delete(F);
  except
    // A file another program holds open stays for the next time.
  end;
end;

procedure Redraw(ACtx: TPdfContext);
var
  W, H: Double;
  L: TPdfLayout;
  Pixels: TBytes;
  Title, Status: UTF8String;
begin
  if ACtx.View.TakePageChanged then
  begin
    if ACtx.Doc.PageSize(ACtx.View.Page, W, H) then
      ACtx.View.SetPageSize(W, H);
  end;
  L := ACtx.View.Layout;
  Pixels := ACtx.Doc.Render(ACtx.View.Page, L.FrameW, L.FrameH, L.StartX, L.StartY,
    L.ScaledW, L.ScaledH);
  if Length(Pixels) > 0 then
    GHostApi.SurfaceSetFrame(ACtx.Handle, L.FrameW, L.FrameH, @Pixels[0], Length(Pixels));
  Title := UTF8String(ACtx.Title);
  Status := UTF8String(ACtx.View.StatusText(Tr('status.page', 'Page %d / %d, %d%%')));
  GHostApi.SurfaceSetInfo(ACtx.Handle, PAnsiChar(Title), PAnsiChar(Status));
end;

function OnSurfaceKey(AUserData: Pointer; AKey: PAnsiChar): Int64; cdecl;
var
  Ctx: TPdfContext;
begin
  Result := 0;
  try
    Ctx := TPdfContext(AUserData);
    if (AKey <> nil) and Ctx.View.HandleKey(string(AKey)) then
    begin
      Redraw(Ctx);
      Result := 1;
    end;
  except
    Result := 0;
  end;
end;

function OnSurfaceMouse(AUserData: Pointer; AKind, AX, AY, AWidth, AHeight,
  AButton, AExtra, AShift: Int64): Int64; cdecl;
var
  Ctx: TPdfContext;
begin
  Result := 0;
  try
    Ctx := TPdfContext(AUserData);
    case AKind of
      cMouseSize:
        begin
          Ctx.View.SetArea(Integer(AWidth), Integer(AHeight));
          Redraw(Ctx);
          Result := 1;
        end;
      cMouseWheel:
        begin
          Ctx.View.Wheel(Integer(AExtra), (AShift and cShiftCtrl) <> 0);
          Redraw(Ctx);
          Result := 1;
        end;
      cMouseDown:
        if AButton = 1 then
        begin
          Ctx.Dragging := True;
          Ctx.DragX := Integer(AX);
          Ctx.DragY := Integer(AY);
          Result := 1;
        end;
      cMouseMove:
        if Ctx.Dragging then
        begin
          Ctx.View.ScrollBy(Ctx.DragX - Integer(AX), Ctx.DragY - Integer(AY));
          Ctx.DragX := Integer(AX);
          Ctx.DragY := Integer(AY);
          Redraw(Ctx);
          Result := 1;
        end;
      cMouseUp:
        begin
          Ctx.Dragging := False;
          Result := 1;
        end;
    end;
  except
    Result := 0;
  end;
end;

procedure OnSurfaceClosed(AUserData: Pointer); cdecl;
var
  Ctx: TPdfContext;
begin
  Ctx := TPdfContext(AUserData);
  if Assigned(GContexts) then
    GContexts.Remove(Ctx);
  Ctx.Free;
end;

{ Opens the viewer for APath in a tab (AMode 0) or in the Quick View panel
  (AMode 2); False when PDFium cannot show the file. }
function OpenViewer(const APath: string; AMode: Integer): Boolean;
var
  Ctx: TPdfContext;
  PluginId, Title: UTF8String;
  W, H: Double;
begin
  Result := False;
  if not Assigned(GHostApi.SurfaceOpenEx) or not PdfiumAvailable then
    Exit;
  Ctx := TPdfContext.Create;
  try
    Ctx.Doc := TPdfDocument.Create(APath);
    Ctx.View := TPdfView.Create(Ctx.Doc.PageCount);
    Ctx.Title := ExtractFileName(APath);
    if Ctx.Doc.PageSize(0, W, H) then
      Ctx.View.SetPageSize(W, H);
    PluginId := UTF8String(cPluginId);
    Title := UTF8String(Ctx.Title);
    Ctx.Handle := GHostApi.SurfaceOpenEx(PAnsiChar(PluginId), PAnsiChar(Title), AMode,
      @OnSurfaceKey, nil, @OnSurfaceClosed, @OnSurfaceMouse, Ctx);
    if Ctx.Handle <= 0 then
      raise EPdfium.Create('no tab');
  except
    Ctx.Free;
    Exit;
  end;
  GContexts.Add(Ctx);
  // A panel surface gets its real size from the host right after opening; a
  // frame drawn for the default size would flash first.
  if AMode <> cSurfacePanel then
    Redraw(Ctx);
  Result := True;
end;

{ The text of the first pages as a file in the temp folder; '' when there is none. }
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

function BoolText(AValue: Boolean): string;
begin
  if AValue then
    Result := '1'
  else
    Result := '0';
end;

procedure LoadSettings;
begin
  GQuickAlwaysRender := GetSettingText(cSettingAlwaysRender) = '1';
  GQuickRenderFallback := GetSettingText(cSettingRenderFallback) <> '0';
end;

function TempNameFor(const AUri, APath, AExt: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, cTempFolder),
    Format('%s-%s%s', [TPath.GetFileNameWithoutExtension(APath),
      Copy(THashMD5.GetHashString(AUri), 1, 8), AExt]));
end;

{ The first page as a BMP in the temp folder; '' when it cannot be drawn. }
function PictureToTemp(const AUri, APath: string): string;
var
  Doc: TPdfDocument;
  W, H: Double;
  PicW, PicH: Integer;
  Pixels: TBytes;
begin
  Result := '';
  if not PdfiumAvailable then
    Exit;
  TDirectory.CreateDirectory(TPath.Combine(TPath.GetTempPath, cTempFolder));
  Doc := TPdfDocument.Create(APath);
  try
    Result := TempNameFor(AUri, APath, '.bmp');
    if TFile.Exists(Result) and
       (TFile.GetLastWriteTime(Result) >= TFile.GetLastWriteTime(APath)) then
      Exit;
    if not Doc.PageSize(0, W, H) then
      Exit('');
    PicW := cQuickPictureWidth;
    PicH := Round(PicW * H / W);
    if PicH > cQuickPictureWidth * 3 then
      PicH := cQuickPictureWidth * 3;
    Pixels := Doc.Render(0, PicW, PicH, 0, 0, PicW, PicH);
  finally
    Doc.Free;
  end;
  Pixels := BgraToBmp(Pixels, PicW, PicH);
  if Length(Pixels) = 0 then
    Exit('');
  TFile.WriteAllBytes(Result, Pixels);
end;

function TextToTemp(const AUri, APath: string): string;
var
  Doc: TPdfDocument;
  Text, Dir: string;
begin
  Result := '';
  if not PdfiumAvailable then
    Exit;
  Dir := TPath.Combine(TPath.GetTempPath, cTempFolder);
  TDirectory.CreateDirectory(Dir);
  Result := TempNameFor(AUri, APath, '.txt');
  if TFile.Exists(Result) and (TFile.GetLastWriteTime(Result) >= TFile.GetLastWriteTime(APath)) then
    Exit;
  Doc := TPdfDocument.Create(APath);
  try
    Text := PdfDocumentText(Doc, cQuickMaxPages, cQuickMaxChars);
  finally
    Doc.Free;
  end;
  if Trim(Text) = '' then
    Exit('');
  TFile.WriteAllText(Result, Text, TEncoding.UTF8);
end;

function OnDocument(AUserData: Pointer; AUri, AMode, ARedirect: PAnsiChar;
  ARedirectCap: Int64): Int64; cdecl;
var
  Uri, Path, Target, TargetUri, Mode: string;
  Bytes: UTF8String;
  P: Integer;
  Interactive: Boolean;
begin
  Result := 0;
  try
    if (AUri = nil) or (AMode = nil) then
      Exit;
    Mode := string(AMode);
    Uri := UTF8ToString(AUri);
    // Quick View asks for a later page as "<uri>#page=N".
    // "#view" asks for the interactive view in the Quick View panel.
    Interactive := False;
    P := LastDelimiter('#', Uri);
    if (P > 0) and SameText(Copy(Uri, P, MaxInt), '#view') then
    begin
      Interactive := True;
      Uri := Copy(Uri, 1, P - 1);
    end;
    Path := UriToPath(Uri);
    if (Path = '') or not TFile.Exists(Path) then
      Exit;
    if SameText(Mode, 'view') then
    begin
      if OpenViewer(Path, 0) then
        Result := 1;
    end
    else if SameText(Mode, 'quick') and Interactive then
    begin
      if OpenViewer(Path, cSurfacePanel) then
        Result := 1;
    end
    else if SameText(Mode, 'quick') and (ARedirect <> nil) then
    begin
      // Quick View runs while the panel is painted, so a big file waits for F3.
      if TFile.GetSize(Path) > cQuickMaxBytes then
        Exit;
      Target := '';
      if not GQuickAlwaysRender then
        Target := TextToTemp(Uri, Path);
      if (Target = '') and (GQuickAlwaysRender or GQuickRenderFallback) then
        Target := PictureToTemp(Uri, Path);
      if Target = '' then
        Exit;
      TargetUri := PathToFileUri(Target);
      Bytes := UTF8String(TargetUri);
      if Length(Bytes) + 1 > ARedirectCap then
        Exit;
      Move(PAnsiChar(Bytes)^, ARedirect^, Length(Bytes) + 1);
      Result := 2;
    end;
  except
    // Never let an exception cross into the host; the next provider runs.
    Result := 0;
  end;
end;

procedure OnSettingsAnswer(AUserData: Pointer; AControlId, AValuesJson: PAnsiChar); cdecl;
var
  Root: TJSONValue;

  function Flag(const AKey: string): Boolean;
  var
    V: TJSONValue;
  begin
    V := TJSONObject(Root).GetValue(AKey);
    if V is TJSONBool then
      Result := TJSONBool(V).AsBoolean
    else
      Result := (V <> nil) and (SameText(V.Value, 'true') or (V.Value = '1'));
  end;

begin
  try
    if not SameText(string(AControlId), 'ok') then
      Exit;
    Root := TJSONObject.ParseJSONValue(UTF8ToString(AValuesJson));
    try
      if not (Root is TJSONObject) then
        Exit;
      GQuickAlwaysRender := Flag('alwaysRender');
      GQuickRenderFallback := Flag('renderFallback');
    finally
      Root.Free;
    end;
    PutSettingText(cSettingAlwaysRender, BoolText(GQuickAlwaysRender));
    PutSettingText(cSettingRenderFallback, BoolText(GQuickRenderFallback));
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
      Decl.AddPair('title', Tr('dlg.title', 'PDF viewer'));
      Decl.AddPair('width', TJSONNumber.Create(72));
      Decl.AddPair('height', TJSONNumber.Create(11));
      Kids := TJSONArray.Create;
      Decl.AddPair('children', Kids);
      AddControl(Kids, 'label', '', Tr('dlg.quick', 'Quick View (Tab opens the full viewer):'),
        2, 1, 66);
      AddControl(Kids, 'checkbox', 'alwaysRender',
        Tr('dlg.alwaysRender', '&Always show pages as pictures'), 3, 3, 66,
        GQuickAlwaysRender);
      AddControl(Kids, 'checkbox', 'renderFallback',
        Tr('dlg.renderFallback', 'Show pages as pictures if the &text cannot be extracted'),
        3, 4, 66, GQuickRenderFallback);
      AddControl(Kids, 'button', 'ok', Tr('dlg.ok', 'OK'), 22, 7, 12, False, True);
      AddControl(Kids, 'button', 'cancel', Tr('dlg.cancel', 'Cancel'), 37, 7, 12, False,
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
  GContexts := TList<TPdfContext>.Create;
  RemoveOldTempFiles;
  LoadSettings;
  PluginId := UTF8String(cPluginId);
  if Assigned(GHostApi.RegisterSettings) then
    GHostApi.RegisterSettings(PAnsiChar(PluginId), @OnConfigure, nil);
  Extensions := UTF8String(cExtensions);
  Result := GHostApi.RegisterDocumentProvider(PAnsiChar(PluginId), PAnsiChar(Extensions),
    cModeView or cModeQuick, @OnDocument, nil, cPriority);
end;

procedure mtn_plugin_shutdown; cdecl;
var
  Ctx: TPdfContext;
begin
  if Assigned(GContexts) then
  begin
    for Ctx in GContexts.ToArray do
    begin
      if Assigned(GHostApi.SurfaceClose) then
        GHostApi.SurfaceClose(Ctx.Handle);
      Ctx.Free;
    end;
    FreeAndNil(GContexts);
  end;
  PdfiumShutdown;
  FillChar(GHostApi, SizeOf(GHostApi), 0);
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
