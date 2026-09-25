unit uDualPanelDrawUtils;

{ Pure rendering helpers for Dual Panel UI elements.
  All procedures accept explicit parameters — no dependency on TDualPanelWindow.
  Extracted from uDualPanelWindow.pas as part of refactoring (high-priority). }

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uVfsTypes, uPanelModel, uPanelColumns,
  uShellIcons, uDriveInfo, uInputLine, uColorCoding;

{ --- Scrollbar ------------------------------------------------------------ }

/// <summary>Draw a vertical scrollbar at column AX, rows ATop..ABottom.
/// Falls back to ASCII art when ATheme is nil (FAR VGA palette).</summary>
procedure DrawPanelScrollBar(const ABuffer: TTerminalGrid; AX, ATop, ABottom, APos,
  ACount, AViewH: Integer; const ATheme: IThemeRenderer; ADialogStyle: Boolean = False);

{ --- Column headers ------------------------------------------------------- }

/// <summary>Draw column name headers inside ABounds (row ABounds.Top+1).
/// Full FAR-style header with sort arrows; fallback palette when ATheme nil.</summary>
procedure DrawPanelColumnHeaders(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AMode: TPanelColumnMode; ASortColumn: TPanelSortColumn; ASortDescending: Boolean;
  const ATheme: IThemeRenderer);

{ --- File list ------------------------------------------------------------ }

/// <summary>Draw the file list inside ABounds from AModel using ATab cursor/scroll.
/// ASideActive = whether this side is currently active (affects cursor colour).
/// AQuickSearchActive / AQuickSearchText: overlay quick-search field on the panel.</summary>
procedure DrawPanelList(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ATab: TTab; ASideActive: Boolean; AColumnMode: TPanelColumnMode;
  const AModel: IPanelModel; const ATheme: IThemeRenderer);
function ColorCodingItemName(const AText: string): string;
procedure FallbackFileRowColors(AIsDirectory, AIsParent, AIsHidden,
  ASelected, AIsCursor, ASideActive: Boolean; out AFg, ABg: TAlphaColor);

{ --- Drive letter bar ----------------------------------------------------- }

/// <summary>Draw Change Drive items on the bottom border of ABounds in NDN
/// style: [ C D E | 1 2 3 ]. Physical drives, then the same numbered specials
/// as Alt+F1/F2. HiGlyph is highlighted (current dest or Ctrl+Left/Right
/// preview). AFrame / ABodyBg come from the caller's ResolveChrome call.</summary>
procedure DrawPanelDriveLetterBar(const ABuffer: TTerminalGrid;
  const ABounds: TRectI; const ATab: TTab; ASide: TPanelSide;
  AFrame, ABodyBg: TAlphaColor;
  ADrivePreviewActive: Boolean; ADrivePreviewSide: TPanelSide;
  ADrivePreviewLetter: Char);
/// <summary>Hit-test twin of DrawPanelDriveLetterBar: True when ACol is a
/// glyph cell in the `[ C D | 1 2 ]` bar on ABounds.Bottom.</summary>
function HitPanelDriveLetterAtCol(const ABounds: TRectI; ACol: Integer;
  out ALetter: Char): Boolean;
/// <summary>Ctrl+Left/Right preview letter on ASide, else the panel's current drive.</summary>
function HighlightDriveLetter(APreviewActive: Boolean; APreviewSide, ASide: TPanelSide;
  APreviewLetter, ACurrentLetter: Char): Char;

{ --- Search / filter info box ---------------------------------------------- }

/// <summary>FAR-style single-line input box on the panel's info-strip row
/// (Quick Search jump-to and Live Filter share this exact chrome — only the
/// prefix label and backing text differ).</summary>
procedure DrawSearchInfoBox(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const APrefix, AText: string; ACursorVisible: Boolean);

implementation

{ FAR VGA fallback palette (used when Theme is nil). }
const
  cCursorFg        = TAlphaColor($FF000000);
  cCursorBg        = TAlphaColor($FF00AAAA);
  cDirFg           = TAlphaColor($FFFFFFFF);
  cFileFg          = TAlphaColor($FFAAAAAA);
  cInactiveCursorBg= TAlphaColor($FF1A3A6A);
  cPanelBg         = TAlphaColor($FF0000AA);
  cSelectedFg      = TAlphaColor($FFFFFF55);
  cSelectedBg      = TAlphaColor($FF0000AA);
  cHeaderFg        = TAlphaColor($FF55FFFF);
  cScrollFg        = TAlphaColor($FFAAAAAA);
  cScrollThumb     = TAlphaColor($FF00AAAA);
  cMenuHot         = TAlphaColor($FFFFFF55);
  cRuleFg          = TAlphaColor($FF00AAAA);
  // Current-drive badge in the drive letter bar: needs to read at a glance
  // against the (typically all-blue) panel chrome, so it gets its own
  // brighter pair rather than reusing the shared cCursorFg/cCursorBg.
  cDriveCurFg      = TAlphaColor($FFFFFF00);
  cDriveCurBg      = TAlphaColor($FF0000FF);

{ =========================================================================
  DrawPanelScrollBar
  ========================================================================= }
procedure DrawPanelScrollBar(const ABuffer: TTerminalGrid; AX, ATop, ABottom, APos,
  ACount, AViewH: Integer; const ATheme: IThemeRenderer; ADialogStyle: Boolean);
var
  Span, ThumbAt, I, ScrollMax: Integer;
  TrackBg, TrackFg, ThumbFg: TAlphaColor;
begin
  Span := ABottom - ATop + 1;
  if Span < 2 then
    Exit;
  if ADialogStyle then
  begin
    // White dialog track (Change Drive / overlays), not panel blue.
    DrawDialogScrollBar(ABuffer, AX, ATop, ABottom, APos, ACount, AViewH);
    Exit;
  end;
  if Assigned(ATheme) then
  begin
    ScrollMax := Max(ACount - AViewH, 0);
    ATheme.DrawScrollBar(ABuffer, TRectI.Make(AX, ATop, AX, ABottom),
      APos, ScrollMax, True, []);
    Exit;
  end;
  TrackFg := cScrollFg;
  TrackBg := cPanelBg;
  ThumbFg := cScrollThumb;
  DrawGridChar(ABuffer, AX, ATop,    #$25B2, TrackFg, TrackBg); // ▲
  DrawGridChar(ABuffer, AX, ABottom, #$25BC, TrackFg, TrackBg); // ▼
  for I := ATop + 1 to ABottom - 1 do
    DrawGridChar(ABuffer, AX, I, chShadeLight, TrackFg, TrackBg);
  ThumbAt := ATop + 1;
  if (ACount > AViewH) and (Span > 3) then
    Inc(ThumbAt, EnsureRange(Round(APos * (Span - 3) / Max(ACount - AViewH, 1)),
      0, Span - 3));
  DrawGridChar(ABuffer, AX, ThumbAt, chBlock, ThumbFg, TrackBg);
end;

{ =========================================================================
  DrawPanelColumnHeaders
  ========================================================================= }
procedure DrawPanelColumnHeaders(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AMode: TPanelColumnMode; ASortColumn: TPanelSortColumn; ASortDescending: Boolean;
  const ATheme: IThemeRenderer);
var
  NameW, MetaW, ListLeft, ListRight, HeaderY, ColLeft, ColW, IconRes, I: Integer;
  HeadFg, HeadBg: TAlphaColor;
  SizeTitle, DateTitle, AttrTitle, ExtTitle, TypeTitle: string;
  ShowSize, ShowDate, ShowAttr, ShowExt, ShowType: Boolean;
  CustomDefs: TCustomColumnDefs;

  procedure PutCentered(AColLeft, AColW: Integer; const ATitle: string;
    ASortCol: TPanelSortColumn);
  var
    X: Integer;
    T, Mark: string;
  begin
    Mark := PanelSortMark((ASortColumn <> pscNone) and (ASortColumn = ASortCol),
      ASortDescending);
    T := ATitle + Mark;
    if Length(T) > AColW then
      T := Copy(T, 1, AColW);
    X := AColLeft + Max((AColW - Length(T)) div 2, 0);
    if X + Length(T) - 1 > ListRight then
      T := Copy(T, 1, Max(ListRight - X + 1, 0));
    if T <> '' then
      PutGridText(ABuffer, X, HeaderY, T, HeadFg, HeadBg);
  end;

begin
  ListLeft  := ABounds.Left + 1;
  ListRight := ABounds.Right - 2;
  HeaderY   := ABounds.Top + 1;
  if ListRight < ListLeft then
    Exit;
  PanelColumnWidths(AMode, ListRight - ListLeft + 1, NameW, MetaW);

  if Assigned(ATheme) then
    ATheme.ResolvePanelChromeColors(pcpColumnHeader, True, HeadFg, HeadBg)
  else
  begin
    HeadFg := cHeaderFg;
    HeadBg := cPanelBg;
  end;

  IconRes := PanelIconReserve;
  FillGridRect(ABuffer, ListLeft, HeaderY, ABounds.Right - 1, HeaderY,
    ' ', HeadFg, HeadBg);

  // Leading icon column: blank header.
  PutCentered(ListLeft + IconRes, NameW, PanelColumnTitle(pscName), pscName);
  ColLeft := ListLeft + IconRes + NameW + 1;

  if AMode = pcmCustom then
  begin
    // Dynamic column list — one header per enabled field, canonical order.
    CustomDefs := BuildCustomColumnDefs(GCustomColumnsConfig);
    for I := 0 to High(CustomDefs) do
    begin
      PutCentered(ColLeft, CustomDefs[I].Width, CustomDefs[I].Title, CustomDefs[I].SortCol);
      Inc(ColLeft, CustomDefs[I].Width + 1);
    end;
    Exit;
  end;

  PanelColumnHeaders(AMode, SizeTitle, DateTitle, AttrTitle, ExtTitle, TypeTitle,
    ShowSize, ShowDate, ShowAttr, ShowExt, ShowType);
  if ShowExt then
  begin
    ColW := 5;
    PutCentered(ColLeft, ColW, ExtTitle, pscExt);
    Inc(ColLeft, ColW + 1);
  end;
  if ShowSize then
  begin
    ColW := 8;
    PutCentered(ColLeft, ColW, SizeTitle, pscSize);
    Inc(ColLeft, ColW + 1);
  end;
  if ShowDate then
  begin
    ColW := 14;
    if AMode = pcmCreated then
      PutCentered(ColLeft, ColW, DateTitle, pscCreated)
    else
      PutCentered(ColLeft, ColW, DateTitle, pscModified);
    Inc(ColLeft, ColW + 1);
  end;
  if ShowType then
  begin
    ColW := 8;
    PutCentered(ColLeft, ColW, TypeTitle, pscType);
    Inc(ColLeft, ColW + 1);
  end;
  if ShowAttr then
  begin
    ColW := 5;
    PutCentered(ColLeft, ColW, AttrTitle, pscAttr);
  end;
end;

function ColorCodingItemName(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) > 0) and (Result[Length(Result)] = '/') then
    Result := Copy(Result, 1, Length(Result) - 1);
end;

procedure FallbackFileRowColors(AIsDirectory, AIsParent, AIsHidden,
  ASelected, AIsCursor, ASideActive: Boolean; out AFg, ABg: TAlphaColor);
begin
  if AIsCursor then
  begin
    if ASelected then
    begin
      AFg := cCursorFg;
      ABg := cMenuHot;
    end
    else if ASideActive then
    begin
      AFg := cCursorFg;
      ABg := cCursorBg;
    end
    else
    begin
      ABg := cInactiveCursorBg;
      if AIsHidden then
        AFg := TAlphaColor($FF888888)
      else if AIsDirectory or AIsParent then
        AFg := cDirFg
      else
        AFg := cFileFg;
    end;
  end
  else if ASelected then
  begin
    AFg := cSelectedFg;
    ABg := cSelectedBg;
  end
  else
  begin
    ABg := cPanelBg;
    if AIsHidden then
      AFg := TAlphaColor($FF888888)
    else if AIsDirectory or AIsParent then
      AFg := cDirFg
    else
      AFg := cFileFg;
  end;
end;

{ =========================================================================
  DrawPanelList
  ========================================================================= }
procedure DrawPanelList(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ATab: TTab; ASideActive: Boolean; AColumnMode: TPanelColumnMode;
  const AModel: IPanelModel; const ATheme: IThemeRenderer);
var
  Y, Col, Idx, ViewH, NameW, MetaW, Count: Integer;
  ColCount, CellW, CellLeft, IconRes, IconId: Integer;
  Row: TPanelRow;
  NamePart, MetaPart: string;
  IconCh: Char;
  Fg, Bg, EmptyFg, EmptyBg: TAlphaColor;
  Selected: Boolean;
  SelKeys: TArray<string>;
  Mode: TPanelColumnMode;

  // Stage 37: FAR-style "file highlighting" groups (uColorCoding), layered
  // on top of the theme's normal per-filetype color. ResolveRowColors calls
  // this last with the row's visual state (Normal/Selected/Current); a
  // group only overrides a state it explicitly sets a color for, so a group
  // that defines just "normal" leaves selection/cursor highlighting exactly
  // as the theme draws it — same precedence Stage 37 shipped with.
  procedure ApplyColorCoding;
  var
    Name: string;
    RuleFg, RuleBg: TAlphaColor;
    State: TColorCodingState;
  begin
    if Row.IsParent then
      Exit;
    if Idx = ATab.CursorIndex then
      State := ccsCurrent
    else if Selected then
      State := ccsSelected
    else
      State := ccsNormal;
    Name := ColorCodingItemName(Row.Text);
    if ColorCodingResolve(Name, Row.IsDirectory, State, RuleFg, RuleBg) then
    begin
      if RuleFg <> 0 then
        Fg := RuleFg;
      if RuleBg <> 0 then
        Bg := RuleBg;
    end;
  end;

  procedure ResolveRowColors;
  begin
    Selected := SelectionKeysHas(SelKeys, Row.URI);
    if Assigned(ATheme) then
      ATheme.ResolveFileRowColors(Row.IsDirectory, Row.IsParent, Row.IsHidden,
        Row.FileType, Selected, Idx = ATab.CursorIndex, ASideActive, Fg, Bg)
    else
      FallbackFileRowColors(Row.IsDirectory, Row.IsParent, Row.IsHidden,
        Selected, Idx = ATab.CursorIndex, ASideActive, Fg, Bg);
    ApplyColorCoding;
  end;

  procedure PaintIconCells(ALeft: Integer);
  var
    J: Integer;
  begin
    IconId := ShellIconIdForRow(Row);
    IconCh := FormatPanelRowIcon(Row);
    DrawGridIcon(ABuffer, ALeft, ABounds.Top + Y, IconId, IconCh, Fg, Bg);
    for J := 1 to IconRes - 1 do
      DrawGridChar(ABuffer, ALeft + J, ABounds.Top + Y, ' ', Fg, Bg);
  end;

begin
  Mode  := AColumnMode;
  ViewH := ABounds.Height;
  PanelColumnWidths(Mode, ABounds.Width, NameW, MetaW);
  IconRes  := PanelIconReserve;
  if Assigned(AModel) then
    Count := AModel.ItemCount
  else
    Count := 0;
  SelKeys := TabSelectionKeys(ATab);

  if Assigned(ATheme) then
    ATheme.ResolvePanelChromeColors(pcpListBody, ASideActive, EmptyFg, EmptyBg)
  else
  begin
    EmptyFg := cFileFg;
    EmptyBg := cPanelBg;
  end;

  ColCount := PanelListColumnCount(Mode, ABounds.Width);

  if (Mode = pcmBrief) and (ColCount > 1) then
  begin
    CellW := BriefCellWidth(ABounds.Width, ColCount);
    FillGridRect(ABuffer, ABounds.Left, ABounds.Top,
      ABounds.Right, ABounds.Bottom, ' ', EmptyFg, EmptyBg);
    for Y := 0 to ViewH - 1 do
      for Col := 0 to ColCount - 1 do
      begin
        Idx := BriefIndexAt(ATab.ScrollOffset, Col, Y, ViewH);
        CellLeft := ABounds.Left + Col * CellW;
        if Col < ColCount - 1 then
          NameW := Max(CellW - 1 - IconRes, 1)
        else
          NameW := Max(Min(CellW, ABounds.Right - CellLeft + 1) - IconRes, 1);
        if (Idx >= 0) and (Idx < Count) then
        begin
          Row := AModel.GetRow(Idx);
          ResolveRowColors;
          FillGridRect(ABuffer, CellLeft, ABounds.Top + Y,
            CellLeft + IconRes + NameW - 1, ABounds.Top + Y, ' ', Fg, Bg);
          if IconRes > 0 then
            PaintIconCells(CellLeft);
          NamePart := FormatPanelRowName(Row, NameW);
          if Length(NamePart) > NameW then
            NamePart := Copy(NamePart, 1, NameW);
          PutGridText(ABuffer, CellLeft + IconRes, ABounds.Top + Y, NamePart, Fg, Bg);
        end;
        // Vertical rule between columns.
        if Col < ColCount - 1 then
          DrawGridChar(ABuffer, CellLeft + CellW - 1, ABounds.Top + Y,
            chBoxV, cRuleFg, EmptyBg);
      end;
    Exit;
  end;

  for Y := 0 to ViewH - 1 do
  begin
    Idx := ATab.ScrollOffset + Y;
    if (Idx < 0) or (Idx >= Count) then
    begin
      FillGridRect(ABuffer, ABounds.Left, ABounds.Top + Y,
        ABounds.Right, ABounds.Top + Y, ' ', EmptyFg, EmptyBg);
      Continue;
    end;
    Row := AModel.GetRow(Idx);
    ResolveRowColors;
    FillGridRect(ABuffer, ABounds.Left, ABounds.Top + Y,
      ABounds.Right, ABounds.Top + Y, ' ', Fg, Bg);
    if IconRes > 0 then
      PaintIconCells(ABounds.Left);
    NamePart := FormatPanelRowName(Row, NameW, (Mode = pcmTypes) or
      ((Mode = pcmCustom) and GCustomColumnsConfig.ShowExt));
    PutGridText(ABuffer, ABounds.Left + IconRes, ABounds.Top + Y, NamePart, Fg, Bg);
    if MetaW > 0 then
    begin
      MetaPart := FormatPanelRowMeta(Mode, Row, MetaW);
      PutGridText(ABuffer, ABounds.Left + IconRes + NameW + 1, ABounds.Top + Y,
        MetaPart, Fg, Bg);
    end;
  end;
end;

{ =========================================================================
  DrawPanelDriveLetterBar
  ========================================================================= }

function DriveBarGlyphColumns(const ABounds: TRectI; out AGlyphs: TArray<Char>;
  out ACols: TArray<Integer>): Boolean;
var
  DriveCount, X, I: Integer;
  ShowSep: Boolean;
begin
  Result := False;
  SetLength(AGlyphs, 0);
  SetLength(ACols, 0);
  if ABounds.Right <= ABounds.Left then
    Exit;
  FitDriveBarGlyphs(ABounds.Right - ABounds.Left - 1, AGlyphs, DriveCount, ShowSep);
  if Length(AGlyphs) = 0 then
    Exit;
  X := ABounds.Left + 1; // '['
  Inc(X);
  SetLength(ACols, Length(AGlyphs));
  for I := 0 to High(AGlyphs) do
  begin
    if ShowSep and (I = DriveCount) then
      Inc(X, 2); // ' |'
    Inc(X); // leading space
    ACols[I] := X;
    Inc(X); // glyph
  end;
  Result := True;
end;

procedure DrawPanelDriveLetterBar(const ABuffer: TTerminalGrid;
  const ABounds: TRectI; const ATab: TTab; ASide: TPanelSide;
  AFrame, ABodyBg: TAlphaColor;
  ADrivePreviewActive: Boolean; ADrivePreviewSide: TPanelSide;
  ADrivePreviewLetter: Char);
var
  Glyphs: TArray<Char>;
  I, X, DriveCount: Integer;
  ShowSep: Boolean;
  HiGlyph: Char;
  Fg, Bg: TAlphaColor;
begin
  HiGlyph := HighlightDriveLetter(ADrivePreviewActive, ADrivePreviewSide, ASide,
    ADrivePreviewLetter, DriveBarGlyphFromUri(ATab.CurrentURI));

  FitDriveBarGlyphs(ABounds.Right - ABounds.Left - 1, Glyphs, DriveCount, ShowSep);
  if Length(Glyphs) = 0 then
    Exit;

  X := ABounds.Left + 1;
  PutGridText(ABuffer, X, ABounds.Bottom, '[', AFrame, ABodyBg);
  Inc(X);
  for I := 0 to High(Glyphs) do
  begin
    if ShowSep and (I = DriveCount) then
    begin
      PutGridText(ABuffer, X, ABounds.Bottom, ' |', AFrame, ABodyBg);
      Inc(X, 2);
    end;
    PutGridText(ABuffer, X, ABounds.Bottom, ' ', AFrame, ABodyBg);
    Inc(X);
    if Glyphs[I] = HiGlyph then
    begin
      Fg := cDriveCurFg;
      Bg := cDriveCurBg;
    end
    else
    begin
      Fg := AFrame;
      Bg := ABodyBg;
    end;
    PutGridText(ABuffer, X, ABounds.Bottom, Glyphs[I], Fg, Bg);
    Inc(X);
  end;
  PutGridText(ABuffer, X, ABounds.Bottom, ' ]', AFrame, ABodyBg);
end;

function HitPanelDriveLetterAtCol(const ABounds: TRectI; ACol: Integer;
  out ALetter: Char): Boolean;
var
  Glyphs: TArray<Char>;
  Cols: TArray<Integer>;
  I: Integer;
begin
  Result := False;
  ALetter := #0;
  if ACol <= ABounds.Left then
    Exit;
  if not DriveBarGlyphColumns(ABounds, Glyphs, Cols) then
    Exit;
  for I := 0 to High(Glyphs) do
    if ACol = Cols[I] then
    begin
      ALetter := Glyphs[I];
      Exit(True);
    end;
end;

function HighlightDriveLetter(APreviewActive: Boolean; APreviewSide, ASide: TPanelSide;
  APreviewLetter, ACurrentLetter: Char): Char;
begin
  if APreviewActive and (APreviewSide = ASide) and (APreviewLetter <> #0) then
    Result := APreviewLetter
  else
    Result := ACurrentLetter;
end;

{ =========================================================================
  DrawSearchInfoBox
  ========================================================================= }
procedure DrawSearchInfoBox(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const APrefix, AText: string; ACursorVisible: Boolean);
var
  Colors: TInputLineColors;
  EditW, X, Y, Right: Integer;
  Line: TInputLine;
const
  // Muted ochre (not FAR hot yellow) — readable without dominating the panel.
  cSearchBoxBg = TAlphaColor($FFB8A040);
begin
  X := ABounds.Left + 1;
  Y := ABounds.Bottom - 1; // info strip row
  Right := ABounds.Right - 2;
  if Right < X then
    Exit;
  Colors.Fg := cCursorFg;
  Colors.Bg := cSearchBoxBg;
  Colors.SelFg := cCursorFg;
  Colors.SelBg := cSearchBoxBg;
  Colors.CaretFg := cSearchBoxBg;
  Colors.CaretBg := cCursorFg;
  FillGridRect(ABuffer, X, Y, Right, Y, ' ', Colors.Fg, Colors.Bg);
  PutGridText(ABuffer, X, Y, APrefix, Colors.Fg, Colors.Bg);
  EditW := Right - X + 1 - Length(APrefix);
  if EditW < 1 then
    Exit;
  Line := InputLineEmpty;
  InputLineSetText(Line, AText, True);
  InputLineDraw(ABuffer, X + Length(APrefix), Y, EditW, Line, True, Colors, ACursorVisible);
end;

end.
