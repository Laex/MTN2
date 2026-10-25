unit uSdlHost;

{ The graphical host on SDL2: a window that shows the character grid of the
  host shell (uHostShell) drawn by the pixel renderer, turns SDL input into
  terminal events, and gives the shell the system clipboard. The window owns
  the font and the zoom; the grid is as many cells as fit the window. }

interface

uses
  uStartupTargets;

type
  TSdlHostOptions = record
    FontName: string;
    /// <summary>Glyph height in pixels before zoom; 0 takes the default.</summary>
    FontSize: Integer;
    Cols: Integer;
    Rows: Integer;
    Targets: TStartupTargets;
    /// <summary>Do not hand the path over to a window that is already open (and
    /// do not accept paths from later starts).</summary>
    NewWindow: Boolean;
    /// <summary>When set, one frame is drawn to this PNG file without opening a window.</summary>
    SnapshotFile: string;
  end;

/// <summary>Opens the window and runs until it is closed; the result is the exit code.</summary>
function RunSdlHost(const AOptions: TSdlHostOptions): Integer;

/// <summary>Draws one frame of a new shell into a PNG file and returns the exit code.</summary>
function RunSdlSnapshot(const AOptions: TSdlHostOptions): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils,
  System.Generics.Collections, System.JSON, uTerminalTypes, uTermInput, uClipboardService,
  uCoreTimer, uHostShell, uPlatformInfo, uPlatformFonts, uPlatformProcess,
  uSdlApi, uSdlInput, uGlyphSource, uFreeTypeGlyphs, uPixelGrid, uPixelBlit,
  uPngWriter, uOverlayRenderer, uOverlayModel, uConfigLocation, uSdlClipboard,
  uSdlImage, uShellIcons, uSdlSurfaceMouse, uThemeTypes, uInstanceSocket, uDesktopEntry;

const
  cDefaultFontSize = 16;
  cMinFontSize = 8;
  cMaxFontSize = 64;
  cDefaultCols = 120;
  cDefaultRows = 36;
  cIdleWaitMs = 20;
  cMinFrameMs = 8;
  cBlinkMs = 530;
  cMinWindowW = 320;
  cMinWindowH = 200;

type
  TSdlHost = class
  strict private
    FOptions: TSdlHostOptions;
    FWindow: PSDLWindow;
    FRenderer: PSDLRenderer;
    FTexture: PSDLTexture;
    FTexW, FTexH: Integer;
    FShell: THostShell;
    FSurfaceMouse: TSdlSurfaceMouse;
    FGrid: TPixelGridRenderer;
    FInput: TSdlInputMapper;
    FComposite: TArray<Cardinal>;
    FLastGrid: TTerminalGrid;
    FFontSize: Integer;
    FScale: Single;
    FOutW, FOutH: Integer;
    FEvents: TList<TTermEvent>;
    FBlinkOn: Boolean;
    FLastFrame: UInt64;
    FShownTitle: string;
    FOverlayKey: string;
    FOverlayRect: TRect;
    FMustPresent: Boolean;
    FQuit: Boolean;
    function BuildGlyphs(out AError: string): IGlyphSource;
    procedure ApplyFont;
    procedure PlaceTextInputRect(AWinW, AWinH: Integer);
    procedure FitGrid;
    procedure RecreateTexture;
    procedure HandleSdlEvent(const E: TSDLEvent);
    function HandleZoomKey(const E: TSDLEvent): Boolean;
    procedure Zoom(ADelta: Integer);
    procedure DrawFrame;
    procedure ComposeOverlay(const ADirty: TRect);
    function OverlayRects(out AFitted, AClip: TRect): Boolean;
    procedure Upload(const ARect: TRect);
  public
    constructor Create(const AOptions: TSdlHostOptions);
    function Open(out AError: string): Boolean;
    procedure Run;
    procedure Close;
    /// <summary>A path handed over by a later start: opened in a new tab, the
    /// window brought to the front.</summary>
    /// <summary>ATargets is EncodeStartupTargets text from a later start.</summary>
    procedure OpenRequested(const ATargets: string);
  end;

procedure LogError(const AMessage: string);
begin
  try
    TFile.AppendAllText(TPath.Combine(GetConfigDirectory, 'sdl-error.log'),
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + AMessage + sLineBreak,
      TEncoding.UTF8);
  except
  end;
end;

function DefaultFontName(const AOptions: TSdlHostOptions): string;
begin
  Result := AOptions.FontName;
  if Result = '' then
    Result := PlatformDefaultMonoFont;
end;

function WindowSettingsFile: string;
begin
  Result := TPath.Combine(GetConfigDirectory, 'sdl.json');
end;

/// <summary>Font size saved by the last zoom; 0 when none is saved.</summary>
function LoadSavedFontSize: Integer;
var
  Json: TJSONValue;
begin
  Result := 0;
  try
    if not TFile.Exists(WindowSettingsFile) then
      Exit;
    Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(WindowSettingsFile, TEncoding.UTF8));
    try
      if Json is TJSONObject then
        Result := EnsureRange(TJSONObject(Json).GetValue<Integer>('fontSize', 0), 0, cMaxFontSize);
    finally
      Json.Free;
    end;
  except
    Result := 0;
  end;
  if (Result > 0) and (Result < cMinFontSize) then
    Result := 0;
end;

procedure SaveFontSize(ASize: Integer);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('fontSize', TJSONNumber.Create(ASize));
    try
      ForceDirectories(GetConfigDirectory);
      TFile.WriteAllText(WindowSettingsFile, Obj.ToJSON, TEncoding.UTF8);
    except
      // A settings file that cannot be written only loses the remembered size.
    end;
  finally
    Obj.Free;
  end;
end;

/// <summary>Panel icons come from the icon theme of the desktop, decoded by SDL;
/// without SDL_image only BMP icons load and the rest keep their glyphs.</summary>
procedure EnableShellIcons(AGrid: TPixelGridRenderer);
begin
  GHostShowsIcons := True;
  GHostShowsSurfaces := True;
  ShellIconsSetDecoder(
    function(const APath: string; out AWidth, AHeight: Integer; out APixels: TBytes): Boolean
    begin
      Result := DecodePictureFile(APath, AWidth, AHeight, APixels) = pdOk;
    end);
  AGrid.SetIconSource(ShellIconPixels);
end;

function PluginsDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(PlatformExePath), 'plugins');
end;

{ TSdlHost }

constructor TSdlHost.Create(const AOptions: TSdlHostOptions);
begin
  inherited Create;
  FOptions := AOptions;
end;

function TSdlHost.BuildGlyphs(out AError: string): IGlyphSource;
begin
  Result := CreateFreeTypeGlyphSource(DefaultFontName(FOptions),
    Max(1, Round(FFontSize * FScale)), AError);
end;

procedure TSdlHost.ApplyFont;
var
  Glyphs: IGlyphSource;
  Err: string;
begin
  Glyphs := BuildGlyphs(Err);
  if Glyphs = nil then
    Exit;
  FGrid.SetGlyphSource(Glyphs);
  FInput.SetCellSize(FGrid.CellWidth, FGrid.CellHeight);
  SetOverlayCellMetrics(FGrid.CellWidth, FGrid.CellHeight, 1);
end;

function TSdlHost.Open(out AError: string): Boolean;
var
  Flags: Cardinal;
  Glyphs: IGlyphSource;
  WinW, WinH: Integer;
begin
  Result := False;
  if not LoadSdl(AError) then
    Exit;
  FFontSize := FOptions.FontSize;
  if FFontSize <= 0 then
    FFontSize := LoadSavedFontSize;
  if FFontSize <= 0 then
    FFontSize := cDefaultFontSize;
  FScale := 1;
  // Without this SDL hides the composition of an input method (CJK and others).
  if Assigned(SDL_SetHint) then
  begin
    SDL_SetHint('SDL_IME_SHOW_UI', '1');
    // The window class (X11) and the application id (Wayland) are the id of
    // the menu entry, so the taskbar finds its name and icon.
    SDL_SetHint('SDL_VIDEO_X11_WMCLASS', PAnsiChar(AnsiString(DesktopEntryId(dekSdl))));
    SDL_SetHint('SDL_APP_ID', PAnsiChar(AnsiString(DesktopEntryId(dekSdl))));
  end;
  if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_EVENTS) <> 0 then
  begin
    AError := 'SDL_Init failed: ' + SdlErrorText;
    Exit;
  end;
  Glyphs := CreateFreeTypeGlyphSource(DefaultFontName(FOptions), FFontSize, AError);
  if Glyphs = nil then
    Exit;
  WinW := Max(cMinWindowW,
    Max(20, IfThen(FOptions.Cols > 0, FOptions.Cols, cDefaultCols)) * Glyphs.CellWidth);
  WinH := Max(cMinWindowH,
    Max(6, IfThen(FOptions.Rows > 0, FOptions.Rows, cDefaultRows)) * Glyphs.CellHeight);
  Flags := SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE or SDL_WINDOW_ALLOW_HIGHDPI;
  FWindow := SDL_CreateWindow('MTN2', SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    WinW, WinH, Flags);
  if FWindow = nil then
  begin
    AError := 'SDL_CreateWindow failed: ' + SdlErrorText;
    Exit;
  end;
  FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_ACCELERATED);
  if FRenderer = nil then
    FRenderer := SDL_CreateRenderer(FWindow, -1, SDL_RENDERER_SOFTWARE);
  if FRenderer = nil then
  begin
    AError := 'SDL_CreateRenderer failed: ' + SdlErrorText;
    Exit;
  end;
  SDL_SetWindowMinimumSize(FWindow, cMinWindowW, cMinWindowH);
  SDL_GetRendererOutputSize(FRenderer, FOutW, FOutH);
  SDL_GetWindowSize(FWindow, WinW, WinH);
  if WinW > 0 then
    FScale := FOutW / WinW;
  FGrid := TPixelGridRenderer.Create(Glyphs);
  EnableShellIcons(FGrid);
  FInput := TSdlInputMapper.Create;
  FEvents := TList<TTermEvent>.Create;
  ApplyFont;
  FInput.SetPixelScale(FScale);
  SetClipboardService(TSdlClipboard.Create);
  FShell := THostShell.Create(Max(20, FOutW div FGrid.CellWidth),
    Max(6, FOutH div FGrid.CellHeight));
  FShell.AttachPlugins(PluginsDir);
  FShell.AttachUpdater;
  FSurfaceMouse := TSdlSurfaceMouse.Create(
    function: TArray<Integer>
    begin
      Result := FShell.DualPanel.VisibleSurfaces;
    end,
    function(AHandle: Integer; out AArea: TRect): Boolean
    var
      B: TRectI;
    begin
      Result := FShell.DualPanel.SurfaceViewport(AHandle, B);
      if Result then
        AArea := TRect.Create(B.Left * FGrid.CellWidth, B.Top * FGrid.CellHeight,
          (B.Right + 1) * FGrid.CellWidth, (B.Bottom + 1) * FGrid.CellHeight);
    end);
  FShell.DualPanel.OpenStartupTargets(FOptions.Targets);
  FitGrid;
  SDL_StartTextInput;
  // The first window of a program unpacked from an archive gets its menu entry
  // and icon; a window opened for a test or in a second copy does not.
  if not FOptions.NewWindow then
    EnsureDesktopEntry(dekSdl);
  Result := True;
end;

procedure TSdlHost.Close;
begin
  if Assigned(FShell) then
  begin
    FShell.PersistSession;
    FShell.DetachUpdater;
    FShell.DetachPlugins;
    FreeAndNil(FShell);
  end;
  SetClipboardService(nil);
  ShellIconsSetDecoder(nil);
  FreeAndNil(FSurfaceMouse);
  FreeAndNil(FEvents);
  FreeAndNil(FInput);
  FreeAndNil(FGrid);
  if FTexture <> nil then
    SDL_DestroyTexture(FTexture);
  FTexture := nil;
  if FRenderer <> nil then
    SDL_DestroyRenderer(FRenderer);
  FRenderer := nil;
  if FWindow <> nil then
    SDL_DestroyWindow(FWindow);
  FWindow := nil;
  if SdlLoaded and Assigned(SDL_Quit) then
    SDL_Quit;
end;

// Sizes the grid to the window, and the texture to the grid.
/// <summary>Tells the input method where text is typed: the grid carries no
/// cursor position, so it is the bottom row, where the command line is. The
/// system input method draws its own composition and candidate window there.</summary>
procedure TSdlHost.PlaceTextInputRect(AWinW, AWinH: Integer);
var
  Area: TSDLRect;
  RowH: Integer;
begin
  if not Assigned(SDL_SetTextInputRect) then
    Exit;
  RowH := Max(1, Round(FGrid.CellHeight / Max(FScale, 0.1)));
  Area.X := 0;
  Area.Y := Max(0, AWinH - RowH);
  Area.W := AWinW;
  Area.H := RowH;
  SDL_SetTextInputRect(Area);
end;

procedure TSdlHost.FitGrid;
var
  WinW, WinH: Integer;
  Cells: TSize;
begin
  SDL_GetRendererOutputSize(FRenderer, FOutW, FOutH);
  SDL_GetWindowSize(FWindow, WinW, WinH);
  if WinW > 0 then
  begin
    FScale := FOutW / WinW;
    FInput.SetPixelScale(FScale);
  end;
  PlaceTextInputRect(WinW, WinH);
  Cells := FGrid.GridSizeOf(FOutW, FOutH);
  FShell.Resize(Cells.cx, Cells.cy);
  FGrid.Invalidate;
  FShell.Dirty := True;
  FMustPresent := True;
end;

procedure TSdlHost.RecreateTexture;
var
  Size: TSize;
begin
  Size := FGrid.PixelSizeOf(FGrid.Cols, FGrid.Rows);
  if (FTexture <> nil) and (FTexW = Size.cx) and (FTexH = Size.cy) then
    Exit;
  if FTexture <> nil then
    SDL_DestroyTexture(FTexture);
  FTexW := Size.cx;
  FTexH := Size.cy;
  FTexture := SDL_CreateTexture(FRenderer, SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STREAMING, FTexW, FTexH);
  SetLength(FComposite, FTexW * FTexH);
  FMustPresent := True;
end;

procedure TSdlHost.Zoom(ADelta: Integer);
var
  NewSize: Integer;
begin
  NewSize := EnsureRange(FFontSize + ADelta, cMinFontSize, cMaxFontSize);
  if NewSize = FFontSize then
    Exit;
  FFontSize := NewSize;
  ApplyFont;
  FitGrid;
  SaveFontSize(NewSize);
end;

function TSdlHost.HandleZoomKey(const E: TSDLEvent): Boolean;
var
  Sym, Mods: Integer;
begin
  Result := False;
  if SdlEventType(E) = SDL_MOUSEWHEEL then
  begin
    if (SDL_GetModState and (KMOD_LCTRL or KMOD_RCTRL)) = 0 then
      Exit;
    Zoom(Sign(SdlEventI32(E, 20)));
    Exit(True);
  end;
  if SdlEventType(E) <> SDL_KEYDOWN then
    Exit;
  Mods := SdlEventU32(E, 24);
  if (Mods and (KMOD_LCTRL or KMOD_RCTRL)) = 0 then
    Exit;
  Sym := SdlEventI32(E, 20);
  case Sym of
    Ord('='), Ord('+'), $40000057:
      Zoom(1);
    Ord('-'), $40000056:
      Zoom(-1);
    Ord('0'):
      begin
        FFontSize := IfThen(FOptions.FontSize > 0, FOptions.FontSize, cDefaultFontSize);
        ApplyFont;
        FitGrid;
        SaveFontSize(FFontSize);
      end;
  else
    Exit;
  end;
  Result := True;
end;

procedure TSdlHost.HandleSdlEvent(const E: TSDLEvent);
var
  Kind: Cardinal;
begin
  Kind := SdlEventType(E);
  case Kind of
    SDL_QUITEVENT:
      begin
        FQuit := True;
        LogError('the window was asked to close (SDL_QUIT)');
      end;
    SDL_WINDOWEVENT:
      case SdlEventU8(E, 12) of
        SDL_WINDOWEVENT_SIZE_CHANGED, SDL_WINDOWEVENT_RESIZED:
          FitGrid;
        SDL_WINDOWEVENT_EXPOSED:
          FMustPresent := True;
      end;
  else
    if HandleZoomKey(E) then
      Exit;
    FSurfaceMouse.Scale := FScale;
    if FSurfaceMouse.Handle(E, SDL_GetModState) then
      Exit;
    FInput.Mods := SDL_GetModState;
    FInput.Translate(E, FEvents);
  end;
end;

function TSdlHost.OverlayRects(out AFitted, AClip: TRect): Boolean;
begin
  Result := OverlayFrameRects(OverlayFrame, FGrid.CellWidth, FGrid.CellHeight, FTexW, FTexH,
    AFitted, AClip);
end;

procedure TSdlHost.ComposeOverlay(const ADirty: TRect);
begin
  BlitOverlayFrame(OverlayFrame, FGrid.CellWidth, FGrid.CellHeight, PByte(@FComposite[0]),
    FTexW * 4, FTexW, FTexH, ADirty);
end;

procedure TSdlHost.Upload(const ARect: TRect);
var
  Area: TSDLRect;
begin
  Area.X := ARect.Left;
  Area.Y := ARect.Top;
  Area.W := ARect.Width;
  Area.H := ARect.Height;
  SDL_UpdateTexture(FTexture, @Area, @FComposite[ARect.Top * FTexW + ARect.Left], FTexW * 4);
end;

procedure TSdlHost.DrawFrame;
var
  Changed, HasOverlay, OverlayMoved: Boolean;
  Dirty, Fitted, Clip, Whole: TRect;
  Key: string;
  Frame: TOverlayFrame;
  Y: Integer;
  Title: string;
  Target: TSDLRect;
begin
  if FShell.Dirty then
    FLastGrid := FShell.Compose;
  if Length(FLastGrid) = 0 then
    Exit;
  Changed := FGrid.Render(FLastGrid, FBlinkOn);
  RecreateTexture;
  Frame := OverlayFrame;
  HasOverlay := OverlayRects(Fitted, Clip);
  Key := '';
  if HasOverlay then
    Key := Format('%d|%d,%d,%d,%d|%d,%d,%d,%d|%g', [Frame.Serial, Frame.Bounds.Left,
      Frame.Bounds.Top, Frame.Bounds.Right, Frame.Bounds.Bottom, Frame.Clip.Left,
      Frame.Clip.Top, Frame.Clip.Right, Frame.Clip.Bottom, Frame.ImageScale]);
  OverlayMoved := Key <> FOverlayKey;
  // The pixels the renderer changed and the area the picture covers, or
  // covered before it moved, are copied from the renderer and the picture is
  // laid over them.
  if Changed or OverlayMoved or FMustPresent then
  begin
    Whole := TRect.Create(0, 0, FTexW, FTexH);
    if FMustPresent then
      Dirty := Whole
    else
      Dirty := FGrid.DirtyRect;
    if OverlayMoved then
    begin
      if not FOverlayRect.IsEmpty then
        Dirty.Union(FOverlayRect);
      if HasOverlay then
        Dirty.Union(TRect.Intersect(Clip, Fitted));
    end;
    Dirty := TRect.Intersect(Dirty, Whole);
    if not Dirty.IsEmpty then
    begin
      for Y := Dirty.Top to Dirty.Bottom - 1 do
        Move(FGrid.Pixels[(Y * FTexW + Dirty.Left) * 4], FComposite[Y * FTexW + Dirty.Left],
          Dirty.Width * 4);
      if HasOverlay then
        ComposeOverlay(Dirty);
      Upload(Dirty);
    end;
    FGrid.ClearDirty;
    FOverlayKey := Key;
    if HasOverlay then
      FOverlayRect := TRect.Intersect(Clip, Fitted)
    else
      FOverlayRect := TRect.Empty;
    SDL_SetRenderDrawColor(FRenderer, 0, 0, 0, 255);
    SDL_RenderClear(FRenderer);
    Target.X := 0;
    Target.Y := 0;
    Target.W := FTexW;
    Target.H := FTexH;
    SDL_RenderCopy(FRenderer, FTexture, nil, @Target);
    SDL_RenderPresent(FRenderer);
    FMustPresent := False;
  end;
  Title := FShell.Title;
  if Title <> FShownTitle then
  begin
    FShownTitle := Title;
    SDL_SetWindowTitle(FWindow, PAnsiChar(UTF8String(Title)));
  end;
end;

procedure TSdlHost.OpenRequested(const ATargets: string);
begin
  FShell.DualPanel.OpenStartupTargets(DecodeStartupTargets(ATargets));
  FShell.Dirty := True;
  if Assigned(SDL_RestoreWindow) then
    SDL_RestoreWindow(FWindow);
  if Assigned(SDL_RaiseWindow) then
    SDL_RaiseWindow(FWindow);
end;

procedure TSdlHost.Run;
var
  E: TSDLEvent;
  Ev: TTermEvent;
  WaitMs, NextTimer, Got: Integer;
  Now64: UInt64;
  Phase, BlinkFlipped: Boolean;
begin
  FBlinkOn := True;
  FLastFrame := 0;
  while not FQuit and not FShell.Quit do
  begin
    CheckSynchronize(0);
    ProcessCoreTimers;
    BlinkFlipped := False;
    Now64 := PlatformTickCount64;
    Phase := ((Now64 div cBlinkMs) and 1) = 0;
    if Phase <> FBlinkOn then
    begin
      FBlinkOn := Phase;
      BlinkFlipped := True;
    end;
    if FShell.Dirty then
    begin
      WaitMs := 0;
      if Now64 - FLastFrame < cMinFrameMs then
        WaitMs := Integer(cMinFrameMs - (Now64 - FLastFrame));
    end
    else
    begin
      WaitMs := cIdleWaitMs;
      NextTimer := CoreTimersNextDueMs;
      if (NextTimer >= 0) and (NextTimer < WaitMs) then
        WaitMs := NextTimer;
    end;
    Got := SDL_WaitEventTimeout(E, WaitMs);
    while Got <> 0 do
    begin
      // An event that fails is logged and dropped: the window stays up.
      try
        HandleSdlEvent(E);
      except
        on Ex: Exception do
          LogError('event ' + IntToStr(SdlEventType(E)) + ': ' + Ex.ClassName + ': ' + Ex.Message);
      end;
      Got := SDL_PollEvent(E);
    end;
    for Ev in FEvents do
      try
        FShell.HandleEvent(Ev);
      except
        on Ex: Exception do
          LogError(Ex.ClassName + ': ' + Ex.Message);
      end;
    FEvents.Clear;
    if FShell.Dirty or FMustPresent or BlinkFlipped then
    begin
      FLastFrame := PlatformTickCount64;
      try
        DrawFrame;
        // After the frame, not inside it: a plugin answers with a new picture.
        FSurfaceMouse.ReportSizes;
      except
        on Ex: Exception do
          LogError('frame: ' + Ex.ClassName + ': ' + Ex.Message);
      end;
    end;
  end;
  if FShell.Quit then
    LogError('the program asked to quit (F10, Alt+X or a command)');
end;

function RunSdlHost(const AOptions: TSdlHostOptions): Integer;
var
  Host: TSdlHost;
  Err: string;
begin
  Host := TSdlHost.Create(AOptions);
  try
    if not Host.Open(Err) then
    begin
      PlatformWriteStdOut('mtn2-sdl: ' + Err + #10);
      Host.Close;
      Exit(1);
    end;
    if not AOptions.NewWindow then
      InstanceStartListening('sdl',
        procedure(APath: string)
        begin
          Host.OpenRequested(APath);
        end);
    try
      Host.Run;
    finally
      InstanceStopListening;
      Host.Close;
    end;
    Result := 0;
  finally
    Host.Free;
  end;
end;

function RunSdlSnapshot(const AOptions: TSdlHostOptions): Integer;
var
  Glyphs: IGlyphSource;
  Err: string;
  Shell: THostShell;
  Grid: TPixelGridRenderer;
  I, Cols, Rows: Integer;
  Frame: TOverlayFrame;
  Composite: TArray<Cardinal>;
begin
  Glyphs := CreateFreeTypeGlyphSource(DefaultFontName(AOptions),
    IfThen(AOptions.FontSize > 0, AOptions.FontSize, cDefaultFontSize), Err);
  if Glyphs = nil then
  begin
    PlatformWriteStdOut('mtn2-sdl: ' + Err + #10);
    Exit(1);
  end;
  Cols := Max(20, IfThen(AOptions.Cols > 0, AOptions.Cols, cDefaultCols));
  Rows := Max(6, IfThen(AOptions.Rows > 0, AOptions.Rows, cDefaultRows));
  // The icons and pictures are decoded by SDL even though no window opens.
  if not SdlLoaded then
    LoadSdl(Err);
  Grid := TPixelGridRenderer.Create(Glyphs);
  EnableShellIcons(Grid);
  Shell := THostShell.Create(Cols, Rows);
  try
    Shell.AttachPlugins(PluginsDir);
    Shell.DualPanel.OpenStartupTargets(AOptions.Targets);
    // Let the panels finish reading their folders.
    for I := 1 to 40 do
    begin
      CheckSynchronize(25);
      ProcessCoreTimers;
    end;
    Grid.Render(Shell.Compose, True);
    Frame := OverlayFrame;
    if Frame.Visible then
    begin
      // The picture of a preview is laid over the cells, as the window does.
      SetLength(Composite, Grid.Width * Grid.Height);
      Move(Grid.Pixels^, Composite[0], Length(Composite) * 4);
      BlitOverlayFrame(Frame, Grid.CellWidth, Grid.CellHeight, PByte(@Composite[0]),
        Grid.Stride, Grid.Width, Grid.Height, TRect.Create(0, 0, Grid.Width, Grid.Height));
      SavePixelsAsPng(AOptions.SnapshotFile, PByte(@Composite[0]), Grid.Stride, Grid.Width,
        Grid.Height);
    end
    else
      SavePixelsAsPng(AOptions.SnapshotFile, Grid.Pixels, Grid.Stride, Grid.Width, Grid.Height);
    Result := 0;
  finally
    Shell.DetachPlugins;
    ShellIconsSetDecoder(nil);
    Grid.Free;
    Shell.Free;
  end;
end;

end.
