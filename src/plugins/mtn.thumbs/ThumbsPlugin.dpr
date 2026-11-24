library ThumbsPlugin;

{ Native MTN2 plugin: a sheet of picture thumbnails for the folder of the active
  panel, drawn on a picture surface. Pictures are decoded on a worker thread,
  one page at a time. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  System.SyncObjs, System.Generics.Collections, System.Generics.Defaults,
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uImageInfo in '..\..\Core\uImageInfo.pas',
  uThumbsLayout,
  uThumbsDecode;

const
  cPluginId = 'mtn.thumbs';
  cCommand = 'thumbs.open';
  cMaxPictures = 20000;

type
  TThumbsContext = class
  private
    FRefs: Integer;
  public
    Files: TArray<string>;
    Model: TThumbsModel;
    Lock: TCriticalSection;
    /// <summary>Pictures shrunk to cell size; guarded by Lock.</summary>
    Images: TArray<TThumbImage>;
    Handle: Int64;
    Closed: Integer;
    Repaint: Integer;
    Generation: Integer;
    constructor Create(const AFiles: TArray<string>);
    destructor Destroy; override;
    procedure AddRef;
    procedure Release;
  end;

var
  GHostApi: PHostApiTable;
  GContext: TThumbsContext;
  GDecoderReady: Boolean;

constructor TThumbsContext.Create(const AFiles: TArray<string>);
begin
  inherited Create;
  FRefs := 1;
  Files := AFiles;
  Model := TThumbsModel.Create(Length(AFiles));
  Lock := TCriticalSection.Create;
  SetLength(Images, Length(AFiles));
end;

destructor TThumbsContext.Destroy;
begin
  Lock.Free;
  Model.Free;
  inherited;
end;

procedure TThumbsContext.AddRef;
begin
  TInterlocked.Increment(FRefs);
end;

procedure TThumbsContext.Release;
begin
  if TInterlocked.Decrement(FRefs) = 0 then
    Free;
end;

function Tr(const AKey, ADefault: string): string;
var
  Id, Key, Def: UTF8String;
  Buf: array[0..511] of AnsiChar;
  Len: Int64;
begin
  Result := ADefault;
  if (GHostApi = nil) or not Assigned(GHostApi.Translate) then
    Exit;
  Id := UTF8String(cPluginId);
  Key := UTF8String(AKey);
  Def := UTF8String(ADefault);
  Len := GHostApi.Translate(PAnsiChar(Id), PAnsiChar(Key), PAnsiChar(Def), @Buf[0], SizeOf(Buf));
  if (Len >= 0) and (Len < SizeOf(Buf)) then
    Result := UTF8ToString(PAnsiChar(@Buf[0]));
end;

procedure ShowNotice(const AText: string; AKind: Int64);
var
  Text: UTF8String;
begin
  if (GHostApi = nil) or not Assigned(GHostApi.ShowMessage) then
    Exit;
  Text := UTF8String(AText);
  GHostApi.ShowMessage(PAnsiChar(Text), AKind);
end;

function ReadPanelInfo: string;
var
  Buf: UTF8String;
  Len: Int64;
begin
  Result := '';
  if (GHostApi = nil) or not Assigned(GHostApi.PanelInfo) then
    Exit;
  Len := GHostApi.PanelInfo(nil, 0);
  if Len <= 0 then
    Exit;
  SetLength(Buf, Len + 1);
  Len := GHostApi.PanelInfo(PAnsiChar(Buf), Length(Buf));
  if (Len > 0) and (Len < Length(Buf)) then
    Result := UTF8ToString(PAnsiChar(Buf));
end;

/// <summary>The folder (a file: URI) and the file under the cursor of the
/// active panel; the cursor is empty when it is on a folder.</summary>
procedure ReadActivePanel(out AFolderUri, ACursorUri: string);
var
  Root, Side: TJSONValue;
  Active: string;
  IsDir: Boolean;
  Json: string;
begin
  AFolderUri := '';
  ACursorUri := '';
  Json := ReadPanelInfo;
  if Json = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(Json);
  try
    if not (Root is TJSONObject) or not Root.TryGetValue<string>('active', Active) then
      Exit;
    Side := Root.GetValue<TJSONValue>(Active, nil);
    if not (Side is TJSONObject) then
      Exit;
    Side.TryGetValue<string>('uri', AFolderUri);
    if Side.TryGetValue<string>('cursor', ACursorUri) then
    begin
      IsDir := False;
      Side.TryGetValue<Boolean>('cursorIsDirectory', IsDir);
      if IsDir then
        ACursorUri := '';
    end;
  finally
    Root.Free;
  end;
end;

function ListPictures(const AFolder: string): TArray<string>;
var
  All: TArray<string>;
  List: TList<string>;
  F: string;
begin
  All := TDirectory.GetFiles(AFolder);
  List := TList<string>.Create;
  try
    for F in All do
      if IsOverlayImageExtension(ExtractFileExt(F)) then
        List.Add(F);
    List.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(ExtractFileName(A), ExtractFileName(B));
      end));
    if List.Count > cMaxPictures then
      List.Count := cMaxPictures;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure PaintContext(ACtx: TThumbsContext);
var
  Frame: TBytes;
  Snapshot: TArray<TThumbImage>;
  Title, Status: UTF8String;
begin
  if (ACtx.Handle = 0) or (GHostApi = nil) then
    Exit;
  ACtx.Lock.Enter;
  try
    Snapshot := Copy(ACtx.Images);
  finally
    ACtx.Lock.Leave;
  end;
  Frame := PaintSheet(ACtx.Model, Snapshot);
  GHostApi.SurfaceSetFrame(ACtx.Handle, ACtx.Model.AreaWidth, ACtx.Model.AreaHeight,
    @Frame[0], Length(Frame));
  if Assigned(GHostApi.SurfaceSetInfo) then
  begin
    Title := UTF8String(Tr('msg.title', 'Thumbnails'));
    if ACtx.Model.Count > 0 then
      Status := UTF8String(ExtractFileName(ACtx.Files[ACtx.Model.Selected]) + '  (' +
        IntToStr(ACtx.Model.Selected + 1) + '/' + IntToStr(ACtx.Model.Count) + ')');
    GHostApi.SurfaceSetInfo(ACtx.Handle, PAnsiChar(Title), PAnsiChar(Status));
  end;
end;

procedure MainRepaint(AUserData: Pointer); cdecl;
var
  Ctx: TThumbsContext;
begin
  Ctx := TThumbsContext(AUserData);
  try
    TInterlocked.Exchange(Ctx.Repaint, 0);
    if (TInterlocked.CompareExchange(Ctx.Closed, 0, 0) = 0) and (Ctx = GContext) then
      PaintContext(Ctx);
  finally
    Ctx.Release;
  end;
end;

procedure RequestRepaint(ACtx: TThumbsContext);
var
  Api: PHostApiTable;
begin
  Api := GHostApi;
  if Api = nil then
    Exit;
  if TInterlocked.Exchange(ACtx.Repaint, 1) <> 0 then
    Exit;
  ACtx.AddRef;
  if Api.PostToMain(PAnsiChar(UTF8String(cPluginId)), MainRepaint, ACtx) <> 0 then
  begin
    TInterlocked.Exchange(ACtx.Repaint, 0);
    ACtx.Release;
  end;
end;

procedure DecodePage(ACtx: TThumbsContext; AGeneration: Integer; AFirst, ALast: Integer);
var
  I, W, H, SW, SH: Integer;
  Pixels: TBytes;
  Img: TThumbImage;
  Todo: Boolean;
begin
  for I := AFirst to ALast do
  begin
    if (TInterlocked.CompareExchange(ACtx.Closed, 0, 0) <> 0) or
       (TInterlocked.CompareExchange(ACtx.Generation, 0, 0) <> AGeneration) then
      Exit;
    ACtx.Lock.Enter;
    try
      Todo := (ACtx.Images[I].Width = 0) and not ACtx.Images[I].Failed;
    finally
      ACtx.Lock.Leave;
    end;
    if not Todo then
      Continue;
    Img := Default(TThumbImage);
    try
      if ThumbsDecodeFile(ACtx.Files[I], W, H, Pixels) then
      begin
        FitInBox(W, H, cCellW - 2 * cCellPad, cCellH - 2 * cCellPad, SW, SH);
        if (SW = W) and (SH = H) then
          Img.Pixels := Pixels
        else
          Img.Pixels := ShrinkPixels(Pixels, W, H, SW, SH);
        Img.Width := SW;
        Img.Height := SH;
      end
      else
        Img.Failed := True;
    except
      Img := Default(TThumbImage);
      Img.Failed := True;
    end;
    ACtx.Lock.Enter;
    try
      ACtx.Images[I] := Img;
    finally
      ACtx.Lock.Leave;
    end;
    RequestRepaint(ACtx);
  end;
end;

procedure StartDecode(ACtx: TThumbsContext);
var
  Gen, First, Last: Integer;
begin
  if not GDecoderReady then
    Exit;
  Gen := TInterlocked.Increment(ACtx.Generation);
  First := ACtx.Model.First;
  Last := Min(First + ACtx.Model.PerPage, ACtx.Model.Count) - 1;
  if Last < First then
    Exit;
  ACtx.AddRef;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        DecodePage(ACtx, Gen, First, Last);
      finally
        ACtx.Release;
      end;
    end).Start;
end;

procedure OpenSelected(ACtx: TThumbsContext);
var
  Uri: UTF8String;
begin
  if (ACtx.Model.Count = 0) or not Assigned(GHostApi.OpenDocument) then
    Exit;
  Uri := UTF8String(PathToFileUri(ACtx.Files[ACtx.Model.Selected]));
  GHostApi.OpenDocument(PAnsiChar(Uri), 0);
end;

procedure Redraw(ACtx: TThumbsContext; ARestartDecode: Boolean);
begin
  PaintContext(ACtx);
  if ARestartDecode then
    StartDecode(ACtx);
end;

function SurfaceKey(AUserData: Pointer; AKey: PAnsiChar): Int64; cdecl;
var
  Ctx: TThumbsContext;
  Key: string;
  OldFirst: Integer;
begin
  Result := 0;
  Ctx := TThumbsContext(AUserData);
  Key := UTF8ToString(AKey);
  if SameText(Key, 'Enter') or SameText(Key, 'Return') then
  begin
    OpenSelected(Ctx);
    Exit(1);
  end;
  OldFirst := Ctx.Model.First;
  if Ctx.Model.HandleKey(Key) then
  begin
    Redraw(Ctx, Ctx.Model.First <> OldFirst);
    Result := 1;
  end;
end;

function SurfaceMouse(AUserData: Pointer; AKind, AX, AY, AWidth, AHeight,
  AButton, AExtra, AShift: Int64): Int64; cdecl;
var
  Ctx: TThumbsContext;
  Hit, OldFirst: Integer;
  Key: string;
begin
  Result := 0;
  Ctx := TThumbsContext(AUserData);
  OldFirst := Ctx.Model.First;
  case AKind of
    5:
      begin
        Ctx.Model.SetArea(Integer(AWidth), Integer(AHeight));
        Redraw(Ctx, True);
        Result := 1;
      end;
    0, 4:
      if AButton = 1 then
      begin
        Hit := Ctx.Model.HitTest(Integer(AX), Integer(AY));
        if Hit >= 0 then
        begin
          Ctx.Model.Select(Hit);
          if AKind = 4 then
            OpenSelected(Ctx)
          else
            Redraw(Ctx, False);
          Result := 1;
        end;
      end;
    3:
      begin
        if AExtra > 0 then
          Key := 'PageUp'
        else
          Key := 'PageDown';
        Ctx.Model.HandleKey(Key);
        Redraw(Ctx, Ctx.Model.First <> OldFirst);
        Result := 1;
      end;
  end;
end;

procedure SurfaceClosed(AUserData: Pointer); cdecl;
var
  Ctx: TThumbsContext;
begin
  Ctx := TThumbsContext(AUserData);
  TInterlocked.Exchange(Ctx.Closed, 1);
  if GContext = Ctx then
    GContext := nil;
  Ctx.Release;
  Ctx.Release;
end;

procedure CloseCurrent;
var
  Ctx: TThumbsContext;
begin
  Ctx := GContext;
  if Ctx = nil then
    Exit;
  GContext := nil;
  TInterlocked.Exchange(Ctx.Closed, 1);
  if Ctx.Handle <> 0 then
    GHostApi.SurfaceClose(Ctx.Handle);
  Ctx.Release;
  Ctx.Release;
end;

procedure CmdOpenThumbs(AUserData: Pointer); cdecl;
var
  FolderUri, CursorUri, Folder, Cursor: string;
  Files: TArray<string>;
  Ctx: TThumbsContext;
  I: Integer;
  Title: UTF8String;
begin
  if not GDecoderReady then
  begin
    ShowNotice(Tr('msg.noDecoder', 'Pictures cannot be decoded here.'), 1);
    Exit;
  end;
  ReadActivePanel(FolderUri, CursorUri);
  Folder := '';
  if FolderUri <> '' then
    Folder := FileUriToPath(FolderUri);
  if (Folder = '') or not TDirectory.Exists(Folder) then
  begin
    ShowNotice(Tr('msg.noFolder', 'Open a folder on disk in the active panel.'), 1);
    Exit;
  end;
  try
    Files := ListPictures(Folder);
  except
    on E: Exception do
    begin
      ShowNotice(E.Message, 2);
      Exit;
    end;
  end;
  if Length(Files) = 0 then
  begin
    ShowNotice(Tr('msg.noPictures', 'There are no pictures in this folder.'), 1);
    Exit;
  end;
  CloseCurrent;
  Ctx := TThumbsContext.Create(Files);
  if CursorUri <> '' then
  begin
    Cursor := FileUriToPath(CursorUri);
    for I := 0 to High(Files) do
      if SameText(Files[I], Cursor) then
      begin
        Ctx.Model.Select(I);
        Break;
      end;
  end;
  Title := UTF8String(Tr('msg.title', 'Thumbnails'));
  Ctx.AddRef;
  Ctx.Handle := GHostApi.SurfaceOpenEx(PAnsiChar(UTF8String(cPluginId)), PAnsiChar(Title), 0,
    SurfaceKey, nil, SurfaceClosed, SurfaceMouse, Ctx);
  if Ctx.Handle <= 0 then
  begin
    Ctx.Handle := 0;
    Ctx.Release;
    Ctx.Release;
    Exit;
  end;
  GContext := Ctx;
  Redraw(Ctx, True);
end;

function mtn_plugin_get_abi_version: Int64; cdecl;
begin
  Result := cPluginAbiVersion;
end;

function mtn_plugin_init(AHostApi: PHostApiTable): Int64; cdecl;
begin
  if AHostApi = nil then
    Exit(-1);
  if not (Assigned(AHostApi.RegisterCommand) and Assigned(AHostApi.SurfaceOpenEx) and
          Assigned(AHostApi.SurfaceSetFrame) and Assigned(AHostApi.SurfaceClose) and
          Assigned(AHostApi.PanelInfo) and Assigned(AHostApi.PostToMain)) then
    Exit(-2);
  GHostApi := AHostApi;
  GDecoderReady := ThumbsDecodeInit;
  AHostApi.RegisterCommand(PAnsiChar(UTF8String(cPluginId)), PAnsiChar(UTF8String(cCommand)),
    @CmdOpenThumbs, nil);
  if Assigned(AHostApi.RegisterMenuItem) then
    AHostApi.RegisterMenuItem(PAnsiChar(UTF8String(cPluginId)), 'Plugins',
      PAnsiChar(UTF8String(cCommand)),
      PAnsiChar(UTF8String(Tr('ui.menu.open', 'Thumbnails of the folder'))),
      @CmdOpenThumbs, nil, 73);
  Result := 0;
end;

procedure mtn_plugin_shutdown; cdecl;
begin
  if GContext <> nil then
  begin
    TInterlocked.Exchange(GContext.Closed, 1);
    GContext := nil;
  end;
  GHostApi := nil;
end;

exports
  mtn_plugin_get_abi_version,
  mtn_plugin_init,
  mtn_plugin_shutdown;

begin
end.
