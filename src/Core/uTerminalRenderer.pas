unit uTerminalRenderer;

interface

uses
  System.Types, System.UITypes, System.SysUtils, System.Classes, System.Math.Vectors,
  System.Generics.Collections,
  FMX.Graphics, FMX.Types,
  uTerminalTypes;

type
  TComposeEvent = reference to procedure(const AGrid: TTerminalGrid;
    ACols, ARows: Integer);

type
  TGlyphKey = record
    Ch: Char;
    FgColor: TAlphaColor;
    Style: TFontStyles;
  end;

  TGlyphCache = class
  private
    FMap: TDictionary<TGlyphKey, TBitmap>;
    FFontName: string;
    FFontSize: Single;
    FCellW: Single;
    FCellH: Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function GetGlyph(const ACh: Char; AFgColor: TAlphaColor; AStyle: TFontStyles;
      ACellW, ACellH: Single; const AFontName: string; AFontSize: Single): TBitmap;
  end;

type
  TTerminalRenderer = class
  private
    // Ping-pong GPU frames: compose into the back page, then flip so OnPaint
    // always blits a complete front frame (no partial-grid flash).
    FFrames: array[0..1] of TBitmap;
    FFrontIndex: Integer;
    FGrid: TTerminalGrid;
    FCols: Integer;
    FRows: Integer;
    FFontName: string;
    FBaseFontSize: Single;
    FZoom: Single;
    FCellWidth: Single;
    FCellHeight: Single;
    FGlyphAdvW: Single;   // natural glyph advance width (logical, pre-snap)
    FGlyphAdvH: Single;   // natural glyph/line height (logical, pre-snap)
    FSceneScale: Single;
    FNeedRebuildBuffer: Boolean;
    FDefaultFg: TAlphaColor;
    FDefaultBg: TAlphaColor;
    FOnCompose: TComposeEvent;
    FXLeft: TArray<Single>;
    FYTop: TArray<Single>;
    FGlyphCache: TGlyphCache;
    procedure CalculateCellMetrics(ACanvas: TCanvas);
    procedure RecalcGridDimensions(AClientWidth, AClientHeight: Single);
    procedure EnsureFrameSize(AWidth, AHeight: Integer);
    function FrontFrame: TBitmap; inline;
    function BackFrame: TBitmap; inline;
    procedure FlipFrames; inline;
    procedure RenderGridToBitmap;
    procedure DrawBoxGlyph(ACanvas: TCanvas; ACol, ARow, N, S, E, W: Integer;
      AColor: TAlphaColor);
    function EffectiveFontSize: Single;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight: Single; ACanvas: TCanvas);
    procedure SetSceneScale(AScale: Single; AClientWidth, AClientHeight: Single; ACanvas: TCanvas);
    procedure SetZoom(AZoom: Single; AClientWidth, AClientHeight: Single; ACanvas: TCanvas);
    procedure SetFont(const AFontName: string; ABaseSize: Single;
      AClientWidth, AClientHeight: Single; ACanvas: TCanvas);
    procedure AdjustZoom(ADelta: Single; AClientWidth, AClientHeight: Single; ACanvas: TCanvas);
    procedure Invalidate;
    /// <summary>Compose grid into the back frame and flip if dirty.</summary>
    procedure Present;
    procedure Recompose;
    procedure Draw(ACanvas: TCanvas; const ADestRect: TRectF);
    procedure FillDemoContent;
    property Grid: TTerminalGrid read FGrid write FGrid;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property Zoom: Single read FZoom;
    property CellWidth: Single read FCellWidth;
    property CellHeight: Single read FCellHeight;
    property FontName: string read FFontName;
    property BaseFontSize: Single read FBaseFontSize;
    // Fired whenever the grid is (re)allocated (resize / zoom / DPI change).
    // The host composes desktop + windows into AGrid. When unset, a built-in
    // demo screen is drawn instead.
    property OnCompose: TComposeEvent read FOnCompose write FOnCompose;
  end;

implementation

uses
  System.Math, FMX.TextLayout, uShellIcons, uPanelColumns, uDisplaySettings;

{ TGlyphCache }

constructor TGlyphCache.Create;
begin
  inherited Create;
  FMap := TDictionary<TGlyphKey, TBitmap>.Create;
  FFontName := '';
  FFontSize := 0;
  FCellW := 0;
  FCellH := 0;
end;

destructor TGlyphCache.Destroy;
begin
  Clear;
  FMap.Free;
  inherited Destroy;
end;

procedure TGlyphCache.Clear;
var
  Pair: TPair<TGlyphKey, TBitmap>;
begin
  for Pair in FMap do
    Pair.Value.Free;
  FMap.Clear;
end;

function TGlyphCache.GetGlyph(const ACh: Char; AFgColor: TAlphaColor; AStyle: TFontStyles;
  ACellW, ACellH: Single; const AFontName: string; AFontSize: Single): TBitmap;
var
  Key: TGlyphKey;
  Bmp: TBitmap;
  W, H: Integer;
  R: TRectF;
begin
  if (FFontName <> AFontName) or (FFontSize <> AFontSize) or
     (FCellW <> ACellW) or (FCellH <> ACellH) then
  begin
    Clear;
    FFontName := AFontName;
    FFontSize := AFontSize;
    FCellW := ACellW;
    FCellH := ACellH;
  end;

  Key.Ch := ACh;
  Key.FgColor := AFgColor;
  Key.Style := AStyle;

  if FMap.TryGetValue(Key, Result) then
    Exit;

  if FMap.Count > 512 then
    Clear;

  W := Max(Round(ACellW), 1);
  H := Max(Round(ACellH), 1);

  Bmp := TBitmap.Create;
  Bmp.SetSize(W, H);
  if Bmp.Canvas.BeginScene then
  begin
    try
      Bmp.Canvas.Clear($00000000);
      Bmp.Canvas.Font.Family := AFontName;
      Bmp.Canvas.Font.Size := AFontSize;
      Bmp.Canvas.Font.Style := AStyle;
      Bmp.Canvas.Fill.Kind := TBrushKind.Solid;
      Bmp.Canvas.Fill.Color := AFgColor;
      R := RectF(0, 0, ACellW, ACellH);
      Bmp.Canvas.FillText(R, string(ACh), False, 1, [], TTextAlign.Center, TTextAlign.Center);
    finally
      Bmp.Canvas.EndScene;
    end;
  end;

  FMap.Add(Key, Bmp);
  Result := Bmp;
end;

function CyrillicPangram: string;
{ Съешь же ещё этих мягких французских булок }
begin
  Result :=
    WideChar($0421) + WideChar($044A) + WideChar($0435) + WideChar($0448) + WideChar($044C) + ' ' +
    WideChar($0436) + WideChar($0435) + ' ' +
    WideChar($0435) + WideChar($0449) + WideChar($0451) + ' ' +
    WideChar($044D) + WideChar($0442) + WideChar($0438) + WideChar($0445) + ' ' +
    WideChar($043C) + WideChar($044F) + WideChar($0433) + WideChar($043A) + WideChar($0438) + WideChar($0445) + ' ' +
    WideChar($0444) + WideChar($0440) + WideChar($0430) + WideChar($043D) + WideChar($0446) +
    WideChar($0443) + WideChar($0437) + WideChar($0441) + WideChar($043A) + WideChar($0438) + WideChar($0445) + ' ' +
    WideChar($0431) + WideChar($0443) + WideChar($043B) + WideChar($043E) + WideChar($043A);
end;

constructor TTerminalRenderer.Create;
begin
  inherited Create;
  FFrames[0] := TBitmap.Create;
  FFrames[1] := TBitmap.Create;
  FFrontIndex := 0;
  FFontName := PreferMonoFontFamily;
  FBaseFontSize := 14;
  FZoom := 1.0;
  FCols := 0;
  FRows := 0;
  FCellWidth := 8;
  FCellHeight := 16;
  FSceneScale := 1.0;
  FDefaultFg := TAlphaColorRec.Lightgray;
  FDefaultBg := $FF000080; // NDN-like deep blue
  FGlyphCache := TGlyphCache.Create;
  FNeedRebuildBuffer := True;
end;

destructor TTerminalRenderer.Destroy;
begin
  FGlyphCache.Free;
  FFrames[0].Free;
  FFrames[1].Free;
  inherited Destroy;
end;

function TTerminalRenderer.FrontFrame: TBitmap;
begin
  Result := FFrames[FFrontIndex];
end;

function TTerminalRenderer.BackFrame: TBitmap;
begin
  Result := FFrames[1 - FFrontIndex];
end;

procedure TTerminalRenderer.FlipFrames;
begin
  FFrontIndex := 1 - FFrontIndex;
end;

procedure TTerminalRenderer.EnsureFrameSize(AWidth, AHeight: Integer);
var
  I: Integer;
  Frame: TBitmap;
begin
  for I := 0 to 1 do
  begin
    Frame := FFrames[I];
    if (Frame.Width <> AWidth) or (Frame.Height <> AHeight) then
    begin
      Frame.SetSize(AWidth, AHeight);
      FNeedRebuildBuffer := True;
    end;
    if Frame.BitmapScale <> FSceneScale then
    begin
      Frame.BitmapScale := FSceneScale;
      FNeedRebuildBuffer := True;
    end;
  end;
end;

function TTerminalRenderer.EffectiveFontSize: Single;
begin
  Result := EnsureRange(FBaseFontSize * FZoom, 8.0, 48.0);
end;

procedure TTerminalRenderer.CalculateCellMetrics(ACanvas: TCanvas);
var
  Layout: TTextLayout;
  R: TRectF;
begin
  Layout := TTextLayoutManager.DefaultTextLayout.Create;
  try
    Layout.BeginUpdate;
    try
      Layout.Font.Family := FFontName;
      Layout.Font.Size := EffectiveFontSize;
      Layout.WordWrap := False;
      Layout.HorizontalAlign := TTextAlign.Leading;
      Layout.VerticalAlign := TTextAlign.Leading;
      Layout.Text := 'W';
    finally
      Layout.EndUpdate;
    end;
    R := Layout.TextRect;
    FCellWidth := Max(R.Width, 1);
    FCellHeight := Max(R.Height, 1);
    // Prefer canvas metrics when available (more accurate on some backends)
    if Assigned(ACanvas) then
    begin
      ACanvas.Font.Family := FFontName;
      ACanvas.Font.Size := EffectiveFontSize;
      FCellWidth := Max(ACanvas.TextWidth('M'), FCellWidth);
      FCellHeight := Max(ACanvas.TextHeight('Wyg'), FCellHeight);
    end;
  finally
    Layout.Free;
  end;
  // Natural glyph advance (before snapping). Box-drawing glyphs fill exactly
  // this advance, which is usually fractional (e.g. 7.7 px).
  FGlyphAdvW := Max(FCellWidth, 1);
  FGlyphAdvH := Max(FCellHeight, 1);

  // Snap cell size to whole DEVICE pixels.
  if FSceneScale <= 0 then
    FSceneScale := 1.0;
  FCellWidth := Max(Round(FCellWidth * FSceneScale), 1) / FSceneScale;
  FCellHeight := Max(Round(FCellHeight * FSceneScale), 1) / FSceneScale;
end;

procedure TTerminalRenderer.RecalcGridDimensions(AClientWidth, AClientHeight: Single);
var
  NewCols, NewRows, I: Integer;
begin
  NewCols := Max(Trunc(AClientWidth / FCellWidth), 1);
  NewRows := Max(Trunc(AClientHeight / FCellHeight), 1);
  if (NewCols <> FCols) or (NewRows <> FRows) or (Length(FGrid) <> NewRows) then
  begin
    FCols := NewCols;
    FRows := NewRows;
    AllocTerminalGrid(FGrid, FCols, FRows);
    ClearTerminalGrid(FGrid, FDefaultFg, FDefaultBg);
    SetLength(FXLeft, FCols + 1);
    for I := 0 to FCols do
      FXLeft[I] := I * FCellWidth;
    SetLength(FYTop, FRows + 1);
    for I := 0 to FRows do
      FYTop[I] := I * FCellHeight;
    if Assigned(FOnCompose) then
      FOnCompose(FGrid, FCols, FRows)
    else
      FillDemoContent;
    FNeedRebuildBuffer := True;
  end;
end;

procedure TTerminalRenderer.Recompose;
begin
  if (FCols < 1) or (FRows < 1) then
    Exit;
  ClearTerminalGrid(FGrid, FDefaultFg, FDefaultBg);
  if Assigned(FOnCompose) then
    FOnCompose(FGrid, FCols, FRows)
  else
    FillDemoContent;
  FNeedRebuildBuffer := True;
  Present;
end;

procedure TTerminalRenderer.Resize(AWidth, AHeight: Single; ACanvas: TCanvas);
var
  BufW, BufH: Integer;
begin
  CalculateCellMetrics(ACanvas);
  RecalcGridDimensions(AWidth, AHeight);
  BufW := Max(Round(AWidth * FSceneScale), 1);
  BufH := Max(Round(AHeight * FSceneScale), 1);
  EnsureFrameSize(BufW, BufH);
  Present;
end;

procedure TTerminalRenderer.SetSceneScale(AScale: Single; AClientWidth, AClientHeight: Single;
  ACanvas: TCanvas);
begin
  if AScale <= 0 then
    AScale := 1.0;
  if SameValue(AScale, FSceneScale) then
    Exit;
  FSceneScale := AScale;
  FCols := 0;
  FRows := 0;
  Resize(AClientWidth, AClientHeight, ACanvas);
end;

procedure TTerminalRenderer.SetZoom(AZoom: Single; AClientWidth, AClientHeight: Single;
  ACanvas: TCanvas);
begin
  FZoom := ClampDisplayZoom(AZoom);
  FCols := 0;
  FRows := 0;
  Resize(AClientWidth, AClientHeight, ACanvas);
end;

procedure TTerminalRenderer.SetFont(const AFontName: string; ABaseSize: Single;
  AClientWidth, AClientHeight: Single; ACanvas: TCanvas);
var
  Name: string;
  Size: Single;
begin
  Name := ResolveMonospaceFontFamily(AFontName);
  Size := ClampDisplayFontSize(ABaseSize);
  if SameText(Name, FFontName) and SameValue(Size, FBaseFontSize) then
    Exit;
  FFontName := Name;
  FBaseFontSize := Size;
  FGlyphCache.Clear;
  FCols := 0;
  FRows := 0;
  Resize(AClientWidth, AClientHeight, ACanvas);
end;

procedure TTerminalRenderer.AdjustZoom(ADelta: Single; AClientWidth, AClientHeight: Single;
  ACanvas: TCanvas);
begin
  SetZoom(FZoom + ADelta, AClientWidth, AClientHeight, ACanvas);
end;

procedure TTerminalRenderer.Invalidate;
begin
  FNeedRebuildBuffer := True;
end;

procedure TTerminalRenderer.Present;
begin
  if FNeedRebuildBuffer then
    RenderGridToBitmap;
end;

procedure TTerminalRenderer.FillDemoContent;
var
  X, Y: Integer;
  Line: string;
  Fg, Bg, Accent, Border: TAlphaColor;
begin
  if (FCols < 2) or (FRows < 2) then
    Exit;

  Fg := FDefaultFg;
  Bg := FDefaultBg;
  Accent := TAlphaColorRec.Yellow;
  Border := TAlphaColorRec.White;
  ClearTerminalGrid(FGrid, Fg, Bg);

  // Unicode double-line box (code points — UTF-8 char literals are string in DCC)
  FGrid[0][0] := TCharCell.Make(WideChar($2554), Border, Bg);
  FGrid[0][FCols - 1] := TCharCell.Make(WideChar($2557), Border, Bg);
  FGrid[FRows - 1][0] := TCharCell.Make(WideChar($255A), Border, Bg);
  FGrid[FRows - 1][FCols - 1] := TCharCell.Make(WideChar($255D), Border, Bg);
  for X := 1 to FCols - 2 do
  begin
    FGrid[0][X] := TCharCell.Make(WideChar($2550), Border, Bg);
    FGrid[FRows - 1][X] := TCharCell.Make(WideChar($2550), Border, Bg);
  end;
  for Y := 1 to FRows - 2 do
  begin
    FGrid[Y][0] := TCharCell.Make(WideChar($2551), Border, Bg);
    FGrid[Y][FCols - 1] := TCharCell.Make(WideChar($2551), Border, Bg);
  end;

  PutTerminalText(FGrid, 2, 1, 'MTN2 Terminal Renderer  v0.1.1', Accent, Bg, [ccaBold]);
  PutTerminalText(FGrid, 2, 3, 'Latin:  The quick brown fox jumps over the lazy dog', Fg, Bg);
  // Built from code points so display does not depend on source ANSI codepage
  PutTerminalText(FGrid, 2, 4, 'Cyrillic: ' + CyrillicPangram, Fg, Bg);
  PutTerminalText(FGrid, 2, 5,
    'ASCII box: +---+---+    Unicode: ' +
    WideChar($250C) + WideChar($2500) + WideChar($252C) + WideChar($2500) + WideChar($2510) + '  ' +
    WideChar($251C) + WideChar($2500) + WideChar($253C) + WideChar($2500) + WideChar($2524) + '  ' +
    WideChar($2514) + WideChar($2500) + WideChar($2534) + WideChar($2500) + WideChar($2518),
    Fg, Bg);
  PutTerminalText(FGrid, 2, 7, Format('Grid: %d x %d cells | Zoom: %.0f%% | Font: %s %.1f',
    [FCols, FRows, FZoom * 100, FFontName, EffectiveFontSize]), Accent, Bg);
  PutTerminalText(FGrid, 2, 9, 'Zoom: Ctrl + MouseWheel   Reset: Ctrl+0', Fg, Bg);
  PutTerminalText(FGrid, 2, 10, 'Resize the window to change Cols x Rows (dynamic grid).', Fg, Bg);

  if FRows > 14 then
  begin
    Line := '';
    for X := 0 to Min(FCols - 5, 62) do
      Line := Line + Char(Ord(' ') + (X mod 95));
    PutTerminalText(FGrid, 2, 12, 'Charset: ' + Line, Fg, Bg);
  end;
end;

// Classify a Unicode box-drawing char into stroke weights per direction.
function ClassifyBoxChar(Ch: Char; out N, S, E, W: Integer): Boolean;
begin
  N := 0; S := 0; E := 0; W := 0;
  case Word(Ch) of
    $2500: begin E := 1; W := 1; end;                     // ─
    $2502: begin N := 1; S := 1; end;                     // │
    $250C: begin S := 1; E := 1; end;                     // ┌
    $2510: begin S := 1; W := 1; end;                     // ┐
    $2514: begin N := 1; E := 1; end;                     // └
    $2518: begin N := 1; W := 1; end;                     // ┘
    $251C: begin N := 1; S := 1; E := 1; end;             // ├
    $2524: begin N := 1; S := 1; W := 1; end;             // ┤
    $252C: begin S := 1; E := 1; W := 1; end;             // ┬
    $2534: begin N := 1; E := 1; W := 1; end;             // ┴
    $253C: begin N := 1; S := 1; E := 1; W := 1; end;     // ┼
    $2550: begin E := 2; W := 2; end;                     // ═
    $2551: begin N := 2; S := 2; end;                     // ║
    $2554: begin S := 2; E := 2; end;                     // ╔
    $2557: begin S := 2; W := 2; end;                     // ╗
    $255A: begin N := 2; E := 2; end;                     // ╚
    $255D: begin N := 2; W := 2; end;                     // ╝
    $255F: begin N := 2; S := 2; E := 1; end;             // ╟
    $2562: begin N := 2; S := 2; W := 1; end;             // ╢
    $2560: begin N := 2; S := 2; E := 2; end;             // ╠
    $2563: begin N := 2; S := 2; W := 2; end;             // ╣
    $2566: begin S := 2; E := 2; W := 2; end;             // ╦
    $2569: begin N := 2; E := 2; W := 2; end;             // ╩
    $256C: begin N := 2; S := 2; E := 2; W := 2; end;     // ╬
  else
    Exit(False);
  end;
  Result := True;
end;

procedure TTerminalRenderer.DrawBoxGlyph(ACanvas: TCanvas; ACol, ARow,
  N, S, E, W: Integer; AColor: TAlphaColor);
var
  Sc: Single;
  L, T, R, B, CXd, CYd: Integer;
  tDev, offDev, half: Integer;
  minCellDev: Single;

  procedure FillDev(l1, t1, r1, b1: Integer);
  begin
    if r1 <= l1 then r1 := l1 + 1;
    if b1 <= t1 then b1 := t1 + 1;
    ACanvas.FillRect(RectF(l1 / Sc, t1 / Sc, r1 / Sc, b1 / Sc), 0, 0, [], 1);
  end;

  procedure StrokeH(x0, x1, cy, weight: Integer);
  begin
    if weight = 1 then
      FillDev(x0, cy - half, x1, cy - half + tDev)
    else if weight = 2 then
    begin
      FillDev(x0, cy - offDev - half, x1, cy - offDev - half + tDev);
      FillDev(x0, cy + offDev - half, x1, cy + offDev - half + tDev);
    end;
  end;

  procedure StrokeV(y0, y1, cx, weight: Integer);
  begin
    if weight = 1 then
      FillDev(cx - half, y0, cx - half + tDev, y1)
    else if weight = 2 then
    begin
      FillDev(cx - offDev - half, y0, cx - offDev - half + tDev, y1);
      FillDev(cx + offDev - half, y0, cx + offDev - half + tDev, y1);
    end;
  end;

begin
  Sc := FSceneScale;
  if Sc <= 0 then
    Sc := 1.0;
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;

  L := Round(ACol * FCellWidth * Sc);
  T := Round(ARow * FCellHeight * Sc);
  R := Round((ACol + 1) * FCellWidth * Sc);
  B := Round((ARow + 1) * FCellHeight * Sc);
  CXd := (L + R) div 2;
  CYd := (T + B) div 2;

  minCellDev := Min(R - L, B - T);
  tDev := Max(1, Round(minCellDev * 0.11));
  half := tDev div 2;
  offDev := tDev;

  if (W > 0) and (E > 0) and (W = E) then
    StrokeH(L, R, CYd, W)
  else
  begin
    if W > 0 then StrokeH(L, CXd + half, CYd, W);
    if E > 0 then StrokeH(CXd - half, R, CYd, E);
  end;

  if (N > 0) and (S > 0) and (N = S) then
    StrokeV(T, B, CXd, N)
  else
  begin
    if N > 0 then StrokeV(T, CYd + half, CXd, N);
    if S > 0 then StrokeV(CYd - half, B, CXd, S);
  end;
end;

procedure TTerminalRenderer.RenderGridToBitmap;
var
  X, Y, RunX, I: Integer;
  Cell, SubCell: TCharCell;
  CellRect: TRectF;
  Target: TBitmap;
  Canvas: TCanvas;
  PrevBg, RunFg: TAlphaColor;
  Ch, RunStr: string;
  SavedMatrix: TMatrix;
  BN, BS, BE, BW: Integer;
  Succeeded: Boolean;
  IconBmp: TBitmap;
  SrcRect: TRectF;
  IconSpan: Integer;
  Sz, PadX, PadY, ReservedW, RowH: Single;
  CurFg: TAlphaColor;
  CurStyle, TargetStyle: TFontStyles;
  RunAttr: TCharCellAttributes;
  GlyphBmp: TBitmap;
  DestRect: TRectF;
  Sc: Single;
  tDev, DevL, DevT, DevB, DevR, ulDev: Integer;
  CaretColor: TAlphaColor;
begin
  Target := BackFrame;
  if (Target.Width < 1) or (Target.Height < 1) then
    Exit;
  if not Target.Canvas.BeginScene then
    Exit;
  Succeeded := False;
  try
    Canvas := Target.Canvas;
    Canvas.Clear(FDefaultBg);
    Canvas.Font.Family := FFontName;
    Canvas.Font.Size := EffectiveFontSize;
    Canvas.Fill.Kind := TBrushKind.Solid;

    // Pass 1: backgrounds, aligned to physical pixels (crisp cell borders).
    for Y := 0 to FRows - 1 do
    begin
      if Y > High(FGrid) then
        Break;
      X := 0;
      while X < FCols do
      begin
        if X > High(FGrid[Y]) then
          Break;
        PrevBg := FGrid[Y][X].BgColor;
        RunX := X;
        while (RunX < FCols) and (RunX <= High(FGrid[Y])) and
          (FGrid[Y][RunX].BgColor = PrevBg) do
          Inc(RunX);
        if (PrevBg <> FDefaultBg) and ((PrevBg and $FF000000) <> 0) then
        begin
          CellRect := RectF(FXLeft[X], FYTop[Y], FXLeft[RunX], FYTop[Y + 1]);
          Canvas.Fill.Color := PrevBg;
          Canvas.FillRect(CellRect, 0, 0, [], 1);
        end;
        X := RunX;
      end;
    end;

    // Pass 2: glyphs and icons. Group contiguous text characters into text runs.
    SavedMatrix := Canvas.Matrix;
    CurFg := $00000000;
    CurStyle := [];
    for Y := 0 to FRows - 1 do
    begin
      if Y > High(FGrid) then
        Break;
      X := 0;
      while X < FCols do
      begin
        if X > High(FGrid[Y]) then
          Break;
        Cell := FGrid[Y][X];

        if Cell.IconId > 0 then
        begin
          IconBmp := ShellIconBitmap(Cell.IconId);
          if IconBmp <> nil then
          begin
            Canvas.SetMatrix(SavedMatrix);
            IconSpan := 1;
            while (X + IconSpan < FCols) and (X + IconSpan <= High(FGrid[Y])) and
                  (IconSpan < cShellIconCells) and
                  (FGrid[Y][X + IconSpan].IconId = 0) and
                  (FGrid[Y][X + IconSpan].CharValue = ' ') and
                  (FGrid[Y][X + IconSpan].BgColor = Cell.BgColor) do
              Inc(IconSpan);

            ReservedW := FXLeft[X + IconSpan] - FXLeft[X];
            RowH := FYTop[Y + 1] - FYTop[Y];

            Sz := Min(ReservedW - 1, RowH - 2);
            if (IconBmp.Width > 0) and (Sz > IconBmp.Width) then
              Sz := Max(IconBmp.Width, RowH - 2);
            if Sz < 4 then
              Sz := RowH;

            PadX := (ReservedW - Sz) * 0.5;
            PadY := (RowH - Sz) * 0.5;
            SrcRect := RectF(0, 0, IconBmp.Width, IconBmp.Height);
            Canvas.DrawBitmap(IconBmp, SrcRect,
              RectF(FXLeft[X] + PadX, FYTop[Y] + PadY,
                FXLeft[X] + PadX + Sz, FYTop[Y] + PadY + Sz),
              1.0, False);
            Inc(X, IconSpan);
            Continue;
          end;
        end;

        Ch := Cell.CharValue;
        if (Ch = '') or (Ch = ' ') then
        begin
          Inc(X);
          Continue;
        end;

        // ▄ / ▀ — fill exact half-cell (button shadows); font glyphs leave gaps.
        if (Length(Ch) = 1) and ((Ch[1] = chLowerHalf) or (Ch[1] = chUpperHalf)) then
        begin
          Canvas.SetMatrix(SavedMatrix);
          Canvas.Fill.Kind := TBrushKind.Solid;
          Canvas.Fill.Color := Cell.FgColor;
          CurFg := Cell.FgColor;
          if Ch[1] = chLowerHalf then
            CellRect := RectF(FXLeft[X], FYTop[Y] + FCellHeight * 0.5,
              FXLeft[X + 1], FYTop[Y + 1])
          else
            CellRect := RectF(FXLeft[X], FYTop[Y],
              FXLeft[X + 1], FYTop[Y] + FCellHeight * 0.5);
          Canvas.FillRect(CellRect, 0, 0, [], 1);
          Inc(X);
          Continue;
        end;

        if (Length(Ch) = 1) and ClassifyBoxChar(Ch[1], BN, BS, BE, BW) then
        begin
          Canvas.SetMatrix(SavedMatrix);
          DrawBoxGlyph(Canvas, X, Y, BN, BS, BE, BW, Cell.FgColor);
          CurFg := Cell.FgColor;
          Inc(X);
          Continue;
        end;

        // Group contiguous text characters of the same color and style into a text run.
        // ccaInsertCaret is a post-glyph overlay and must not split the run.
        RunX := X;
        RunFg := Cell.FgColor;
        RunAttr := Cell.Attributes - [ccaInsertCaret];
        RunStr := '';
        while (RunX < FCols) and (RunX <= High(FGrid[Y])) do
        begin
          SubCell := FGrid[Y][RunX];
          if (SubCell.IconId > 0) or (SubCell.FgColor <> RunFg) or
             ((SubCell.Attributes - [ccaInsertCaret]) <> RunAttr) or
             (Length(SubCell.CharValue) <> 1) or
             (SubCell.CharValue <= #32) or
             (SubCell.CharValue = chLowerHalf) or (SubCell.CharValue = chUpperHalf) or
             ClassifyBoxChar(SubCell.CharValue, BN, BS, BE, BW) then
            Break;
          RunStr := RunStr + SubCell.CharValue;
          Inc(RunX);
        end;

        if RunStr <> '' then
        begin
          if ccaBold in RunAttr then
            TargetStyle := [TFontStyle.fsBold]
          else
            TargetStyle := [];

          for I := 1 to Length(RunStr) do
          begin
            GlyphBmp := FGlyphCache.GetGlyph(RunStr[I], RunFg, TargetStyle,
              FCellWidth, FCellHeight, FFontName, EffectiveFontSize);
            if Assigned(GlyphBmp) and (GlyphBmp.Width > 0) and (GlyphBmp.Height > 0) then
            begin
              SrcRect := RectF(0, 0, GlyphBmp.Width, GlyphBmp.Height);
              DestRect := RectF(FXLeft[X + I - 1], FYTop[Y], FXLeft[X + I], FYTop[Y + 1]);
              Canvas.DrawBitmap(GlyphBmp, SrcRect, DestRect, 1.0, True);
            end;
          end;
          X := RunX;
        end
        else
          Inc(X);
      end;
    end;

    Canvas.SetMatrix(SavedMatrix);

    // Pass 3: insert carets (2 CSS-px bar at the left edge of the marked cell).
    // Drawn after glyphs so space cells still get a caret.
    Sc := FSceneScale;
    if Sc <= 0 then
      Sc := 1.0;
    Canvas.Fill.Kind := TBrushKind.Solid;

    // Underline (Markdown links, ANSI SGR 4): a 1 CSS-px bar in the glyph
    // colour just above the cell's bottom edge, spaces included so a
    // multi-word link reads as one underlined run.
    ulDev := Max(1, Round(Sc));
    for Y := 0 to FRows - 1 do
    begin
      if Y > High(FGrid) then
        Break;
      for X := 0 to FCols - 1 do
      begin
        if X > High(FGrid[Y]) then
          Break;
        if not (ccaUnderline in FGrid[Y][X].Attributes) then
          Continue;
        DevL := Round(FXLeft[X] * Sc);
        DevR := Round(FXLeft[X + 1] * Sc);
        DevB := Round(FYTop[Y + 1] * Sc) - Max(1, Round(FCellHeight * Sc * 0.08));
        Canvas.Fill.Color := FGrid[Y][X].FgColor;
        Canvas.FillRect(RectF(DevL / Sc, (DevB - ulDev) / Sc, DevR / Sc, DevB / Sc),
          0, 0, [], 1);
      end;
    end;

    tDev := Max(2, Round(2 * Sc));
    for Y := 0 to FRows - 1 do
    begin
      if Y > High(FGrid) then
        Break;
      for X := 0 to FCols - 1 do
      begin
        if X > High(FGrid[Y]) then
          Break;
        if not (ccaInsertCaret in FGrid[Y][X].Attributes) then
          Continue;
        CaretColor := InsertCaretColor(FGrid[Y][X].BgColor);
        DevL := Round(FXLeft[X] * Sc);
        DevT := Round(FYTop[Y] * Sc);
        DevB := Round(FYTop[Y + 1] * Sc);
        Canvas.Fill.Color := CaretColor;
        Canvas.FillRect(RectF(DevL / Sc, DevT / Sc, (DevL + tDev) / Sc, DevB / Sc),
          0, 0, [], 1);
      end;
    end;

    Succeeded := True;
  finally
    Target.Canvas.EndScene;
  end;

  if Succeeded then
  begin
    FlipFrames;
    FNeedRebuildBuffer := False;
  end;
end;

procedure TTerminalRenderer.Draw(ACanvas: TCanvas; const ADestRect: TRectF);
var
  Frame: TBitmap;
begin
  if FNeedRebuildBuffer then
    RenderGridToBitmap;
  Frame := FrontFrame;
  if (Frame.Width > 0) and (Frame.Height > 0) then
    ACanvas.DrawBitmap(Frame, RectF(0, 0, Frame.Width, Frame.Height),
      ADestRect, 1, True);
end;

end.
