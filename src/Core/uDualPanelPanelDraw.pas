unit uDualPanelPanelDraw;

{ Panel-frame chrome extracted from TDualPanelWindow.DrawPanel /
  DrawQuickViewContent, plus DrawContent classify/overlay dispatch and
  DrawPanel body classify (info / Quick View / files). Host still owns
  list/headers and the info/quick-view bodies. }

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uVfsTypes,
  uDualPanelTabs, uPanelColumns, uCharWidth, uDisplaySettings;

type
  TResolvePanelChromeProc = procedure(APart: TPanelChromePart; AActive: Boolean;
    out AFg, ABg: TAlphaColor) of object;

function PanelModeTitleCaption(AViewKind: TPanelViewKind;
  AIsQuickViewTarget: Boolean): string;
function FormatPanelTotalsFooter(AHasSelection: Boolean; ABytes: Int64;
  AFiles, AFolders: Integer; AMaxWidth: Integer): string;
function FormatPanelCursorInfoLine(const ARow: TPanelRow; AWidth: Integer): string;
function FormatQuickViewPlaceholder(AHasRow: Boolean; const ARow: TPanelRow): string;
function CenteredTextCol(const ABounds: TRectI; const AText: string): Integer;
function PanelSortLetterCol(const ABounds: TRectI): Integer;
function PanelSortLetterRow(const ABounds: TRectI): Integer;

procedure DrawCenteredPanelTitle(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ACaption: string; AFg, ABg: TAlphaColor);
procedure DrawPanelSortLetter(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  ACol: TPanelSortColumn; ADescending, AActive: Boolean;
  const AResolveChrome: TResolvePanelChromeProc);
procedure DrawCenteredPlaceholder(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AMsg: string; AFg, ABg: TAlphaColor);
procedure DrawPanelEmbeddedTabs(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const APanel: TPanelState; AActive: Boolean; ASepChar: Char;
  AFrame, ABodyBg: TAlphaColor; ADragHoverIndex: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
procedure DrawPanelListSeparator(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AUseDouble: Boolean; AFrame, ABodyBg: TAlphaColor);
procedure DrawPanelTotalsOnRule(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AFooter: string; AFooterFg, ABodyBg: TAlphaColor);
procedure DrawPanelNdnFooterRows(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ATotals, AFreeLine: string; AFreeUsedPermille: Integer;
  ATotalsFg, AInfoFg, AInfoBg: TAlphaColor);
procedure DrawPanelCursorStrip(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AInfoLine: string; AFg, ABg: TAlphaColor);
procedure DrawPanelDropBadge(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AFg, ABg: TAlphaColor);

function IsQuickViewTarget(AViewKind: TPanelViewKind;
  ASide, AActiveSide: TPanelSide): Boolean;
procedure PanelFrameGlyphs(AActive: Boolean;
  out ATL, ATR, ABL, ABR, AH, AV: Char);
function UseDoubleListSeparator(AActive, AHasTheme, AThemeUsesDouble: Boolean): Boolean;
function PanelInfoStripBounds(const ABounds: TRectI): TRectI;
function DualPanelChromeFits(AWidth, AHeight: Integer): Boolean;
procedure ComputePanelLayout(AWidth, AHeight: Integer; ALeftOn, ARightOn: Boolean;
  out ALeftBounds, ARightBounds: TRectI; out AListTop, AListBottom: Integer);
function EmbeddedDocumentPaintHeight(AClientHeight: Integer): Integer;
function EmbeddedTerminalPaintHeight(AClientHeight: Integer): Integer;
function CanPaintEmbeddedContent(AHeight: Integer): Boolean;

type
  TDrawContentKind = (dckTooSmall, dckConsole, dckDocument, dckTerminal, dckPanels);
  TDrawProc = procedure of object;
  TDrawWHProc = procedure(AWidth, AHeight: Integer) of object;
  TDrawWProc = procedure(AWidth: Integer) of object;

  TDrawOverlaySnapshot = record
    DialogVisible: Boolean;
    SubmenuOpen: Boolean;
    AreaWidth: Integer;
    AreaHeight: Integer;
  end;

  TDualPanelDrawHost = record
    DrawFolderTree: TDrawProc;
    DrawDrivePopup: TDrawProc;
    DrawHistoryPopup: TDrawProc;
    DrawJobPopup: TDrawProc;
    DrawUserMenu: TDrawProc;
    DrawSortMenu: TDrawProc;
    DrawColumnModeMenu: TDrawProc;
    DrawStub: TDrawProc;
    DrawSearchUi: TDrawProc;
    DrawDialog: TDrawWHProc;
    DrawSubmenu: TDrawWProc;
  end;

function ClassifyDrawContent(AWidth, AHeight: Integer; AConsole: Boolean;
  AKind: TWorkspaceKind): TDrawContentKind;
procedure DispatchDrawOverlays(const AHost: TDualPanelDrawHost;
  const ASnap: TDrawOverlaySnapshot);

type
  TPanelBodyKind = (pbkInfo, pbkQuickView, pbkFiles);
  TDrawPanelBodyProc = procedure(const ABounds: TRectI; ASide: TPanelSide;
    AFrame, ABodyBg: TAlphaColor) of object;
  TDrawPanelDriveProc = procedure(const ABounds: TRectI; const ATab: TTab;
    ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor) of object;
  TDrawPanelFilesProc = procedure(const ABounds: TRectI; const APanel: TPanelState;
    ASide: TPanelSide; AActive: Boolean; AFrame, ABodyBg: TAlphaColor) of object;
  TDrawBoundsProc = procedure(const ABounds: TRectI) of object;

  TDrawPanelSnapshot = record
    Bounds: TRectI;
    Panel: TPanelState;
    Tab: TTab;
    Side: TPanelSide;
    Active: Boolean;
    Frame, BodyBg: TAlphaColor;
    ViewKind: TPanelViewKind;
    IsQuickViewTarget: Boolean;
  end;

  TDualPanelPanelHost = record
    DrawInfo: TDrawPanelBodyProc;
    DrawQuickView: TDrawPanelBodyProc;
    DrawDriveLetters: TDrawPanelDriveProc;
    DrawFiles: TDrawPanelFilesProc;
  end;

function ClassifyPanelBody(AViewKind: TPanelViewKind;
  AIsQuickViewTarget: Boolean): TPanelBodyKind;
function PanelTabDragHoverIndex(ASide: TPanelSide; ADragActive: Boolean;
  ADragKind, ALeftKind, ARightKind, AHover: Integer): Integer;
function IsQuickViewPreviewable(AHasRow, AIsOverlayImage: Boolean;
  const ARow: TPanelRow): Boolean;
function QuickViewInteriorAbsBounds(const APanelBounds, AWindowArea: TRectI): TRectI;
procedure DrawPanelShell(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  const APanel: TPanelState; AActive, AIsQuickViewTarget: Boolean;
  AFrame, ABodyBg, AFileFg: TAlphaColor; ADragHover: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
procedure DrawPanelFilesChrome(const ABuffer: TTerminalGrid;
  const ABounds: TRectI; AActive, AHasTheme, AThemeDouble: Boolean;
  AFrame, ABodyBg, AFooterFg: TAlphaColor; const AFooter, AInfoLine: string;
  const AFreeLine: string; AFreeUsedPermille: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
procedure DrawPanelDropHighlight(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  AFallbackFg, AFallbackBg: TAlphaColor);
procedure DispatchDrawPanelBody(const AHost: TDualPanelPanelHost;
  const ASnap: TDrawPanelSnapshot);
procedure DispatchPanelSearchFields(const ABounds: TRectI;
  ASide, AActiveSide: TPanelSide; AQuickSearch: Boolean;
  const ADrawQuick: TDrawBoundsProc);

type
  TDrawFilesHeadersProc = procedure(const ABounds: TRectI;
    const APanel: TPanelState) of object;
  TDrawFilesListProc = procedure(const AListBounds: TRectI; const ATab: TTab;
    AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide) of object;
  TDrawFilesScrollProc = procedure(AX, ATop, ABottom, APos, ACount,
    AViewH: Integer) of object;

  TDrawFilesSnapshot = record
    Bounds, ListBounds: TRectI;
    Panel: TPanelState;
    Tab: TTab;
    Side, ActiveSide: TPanelSide;
    Active: Boolean;
    Frame, BodyBg, FooterFg, DropFg, DropBg: TAlphaColor;
    Count, PageSize: Integer;
    Footer, InfoLine: string;
    HasTheme, ThemeDouble, DropHighlight, QuickSearch: Boolean;
    /// <summary>Free space line of the NDN footer; '' for a panel whose drive is
    /// unknown.</summary>
    FreeLine: string;
    /// <summary>Used share of that drive in thousandths; the footer shades that
    /// part of the free-space row. 0 draws no bar.</summary>
    FreeUsedPermille: Integer;
  end;

  TDualPanelFilesDrawHost = record
    ResolveChrome: TResolvePanelChromeProc;
    DrawDriveLetters: TDrawPanelDriveProc;
    DrawHeaders: TDrawFilesHeadersProc;
    DrawList: TDrawFilesListProc;
    DrawScrollBar: TDrawFilesScrollProc;
    DrawQuickSearch: TDrawBoundsProc;
  end;

procedure DispatchDrawPanelFiles(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const AHost: TDualPanelFilesDrawHost;
  const ASnap: TDrawFilesSnapshot);

implementation

uses
  uChromeRows, uStrings;

const
  // Free-space bar of the NDN footer: cells left empty at each end, and how much
  // of the text colour is mixed into the used and the free part.
  cFooterBarMargin = 1;
  cFooterBarUsedPct = 32;
  cFooterBarFreePct = 10;

function PanelModeTitleCaption(AViewKind: TPanelViewKind;
  AIsQuickViewTarget: Boolean): string;
begin
  if AViewKind = pvkInfo then
    Result := ' Information '
  else if AIsQuickViewTarget then
    Result := ' Quick View '
  else
    Result := '';
end;

function FormatPanelTotalsFooter(AHasSelection: Boolean; ABytes: Int64;
  AFiles, AFolders: Integer; AMaxWidth: Integer): string;

  function Compose(const ASize: string): string;
  begin
    if AHasSelection then
      Result := ' ' + T('ui.panelTotals.selected', 'Selected: %s, files: %d, folders: %d',
        [ASize, AFiles, AFolders]) + ' '
    else
      Result := ' ' + T('ui.panelTotals.bytes', 'Bytes: %s, files: %d, folders: %d',
        [ASize, AFiles, AFolders]) + ' ';
  end;

begin
  Result := '';
  // The exact size gives way to the short one when the line would not fit.
  if GExactSelectionSize then
  begin
    Result := Compose(FormatSizeExact(ABytes));
    if Length(Result) > AMaxWidth then
      Result := '';
  end;
  if Result = '' then
    Result := Compose(FormatSizeShort(ABytes));
  if Length(Result) > AMaxWidth then
    Result := Copy(Result, 1, AMaxWidth);
end;

// The size shown in the cursor strip: the exact byte count for rows that have a
// number (files, folders with a counted size, not <DIR> or <LINK>) while the
// name keeps at least this many cells.
function CursorInfoSizeText(const ARow: TPanelRow; AWidth: Integer): string;
const
  cExactMinName = 12;
begin
  Result := ARow.SizeText;
  if GExactSelectionSize and (Result <> '') and (Result[1] <> '<') and
     (not ARow.IsParent) and
     (AWidth - TextDisplayWidth(FormatSizeExact(ARow.Size)) - 1 >= cExactMinName) then
    Result := FormatSizeExact(ARow.Size);
end;

// The right-hand part of the cursor strip: a search match, or size and date.
// Size and date are split by a column rule when the name keeps at least
// cRuleMinName cells, else by a plain space.
function CursorInfoMetaText(const ARow: TPanelRow; AWidth: Integer): string;
const
  cMetaRule = ' ' + #$2502 + ' ';
  cRuleMinName = 8;
var
  SizePart: string;
begin
  if (ARow.MatchSnippet <> '') and (ARow.MatchLine <= 0) then
    Exit(ARow.MatchSnippet);
  if ARow.MatchSnippet <> '' then
    Exit(Format('L%d: %s', [ARow.MatchLine, ARow.MatchSnippet]));
  SizePart := CursorInfoSizeText(ARow, AWidth);
  if ARow.DateText = '' then
    Exit(SizePart);
  if SizePart = '' then
    Exit(ARow.DateText);
  Result := SizePart + cMetaRule + ARow.DateText;
  if AWidth - TextDisplayWidth(Result) - 1 < cRuleMinName then
    Result := SizePart + ' ' + ARow.DateText;
end;

function FormatPanelCursorInfoLine(const ARow: TPanelRow; AWidth: Integer): string;
var
  NamePart, MetaPart: string;
  MaxName: Integer;
begin
  NamePart := PanelRowDisplayText(ARow);
  if ARow.DirText <> '' then
    NamePart := IncludeTrailingPathDelimiter(ARow.DirText) + NamePart;
  MetaPart := CursorInfoMetaText(ARow, AWidth);
  MaxName := Max(AWidth - TextDisplayWidth(MetaPart) - 1, 4);
  if TextDisplayWidth(NamePart) > MaxName then
    NamePart := EllipsizeKeepingExt(NamePart, MaxName);
  NamePart := Copy(NamePart, 1, TextFitChars(NamePart, MaxName));
  NamePart := NamePart + StringOfChar(' ', MaxName - TextDisplayWidth(NamePart));
  Result := NamePart + ' ' + MetaPart;
  Result := Copy(Result, 1, TextFitChars(Result, AWidth));
end;

function FormatQuickViewPlaceholder(AHasRow: Boolean; const ARow: TPanelRow): string;
begin
  Result := '';
  if not AHasRow then
    Exit;
  if ARow.IsDirectory or ARow.IsParent then
    Result := '(directory)'
  else if ARow.URI <> '' then
    Result := '(no preview: ' + ARow.Extension + ')';
end;

function CenteredTextCol(const ABounds: TRectI; const AText: string): Integer;
begin
  Result := ABounds.Left + Max((ABounds.Width - Length(AText)) div 2, 1);
  if Result + Length(AText) > ABounds.Right then
    Result := ABounds.Left + 1;
end;

function PanelSortLetterCol(const ABounds: TRectI): Integer;
begin
  Result := ABounds.Left + 1;
end;

function PanelSortLetterRow(const ABounds: TRectI): Integer;
begin
  Result := ABounds.Top + 1;
end;

procedure DrawCenteredPanelTitle(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ACaption: string; AFg, ABg: TAlphaColor);
begin
  if ACaption = '' then
    Exit;
  PutGridText(ABuffer, CenteredTextCol(ABounds, ACaption), ABounds.Top,
    ACaption, AFg, ABg);
end;

procedure DrawPanelSortLetter(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  ACol: TPanelSortColumn; ADescending, AActive: Boolean;
  const AResolveChrome: TResolvePanelChromeProc);
var
  HeadFg, HeadBg, HotFg, Discard, Fg: TAlphaColor;
begin
  if (not Assigned(AResolveChrome)) or (ABounds.Width < 3) or
     (ABounds.Height < 3) then
    Exit;
  AResolveChrome(pcpColumnHeader, AActive, HeadFg, HeadBg);
  AResolveChrome(pcpHotMark, AActive, HotFg, Discard);
  // Theme hot-mark on the header strip; fall back to header text or
  // white/black so the glyph stays readable on every palette.
  Fg := ContrastingGlyphFg(HeadBg, HotFg, HeadFg);
  DrawGridChar(ABuffer, PanelSortLetterCol(ABounds), PanelSortLetterRow(ABounds),
    PanelSortModeLetter(ACol, ADescending), Fg, HeadBg);
end;

procedure DrawCenteredPlaceholder(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AMsg: string; AFg, ABg: TAlphaColor);
begin
  if AMsg = '' then
    Exit;
  PutGridText(ABuffer, CenteredTextCol(ABounds, AMsg),
    (ABounds.Top + ABounds.Bottom) div 2, AMsg, AFg, ABg);
end;

procedure DrawPanelEmbeddedTabs(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const APanel: TPanelState; AActive: Boolean; ASepChar: Char;
  AFrame, ABodyBg: TAlphaColor; ADragHoverIndex: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
var
  I, HeadX, TabsRight, TabMaxLen, PlusCol: Integer;
  Cap: string;
  CloseFg, TabFg, TabBg, Discard: TAlphaColor;
  DragHover: Boolean;
begin
  if not Assigned(AResolveChrome) then
    Exit;
  AResolveChrome(pcpCloseMark, AActive, CloseFg, Discard);
  HeadX := PanelTabHeadX(ABounds);
  // Shared with HitPanelTabAtCol via PanelTabHeadX / ComputePanelTabLayout.
  ComputePanelTabLayout(APanel, ABounds, TabsRight, TabMaxLen);
  for I := 0 to High(APanel.Tabs) do
  begin
    Cap := PanelTabCaption(
      VfsUriDirTabTitle(APanel.Tabs[I].CurrentURI, TabMaxLen),
      Length(APanel.Tabs) > 1);
    if HeadX + TextDisplayWidth(Cap) >= TabsRight then
      Break;
    DragHover := I = ADragHoverIndex;
    if (I = APanel.ActiveTabIndex) or DragHover then
      AResolveChrome(pcpPanelTabActive, AActive, TabFg, TabBg)
    else
      AResolveChrome(pcpPanelTabIdle, AActive, TabFg, TabBg);
    PutGridText(ABuffer, HeadX, ABounds.Top, Cap, TabFg, TabBg);
    if Length(APanel.Tabs) > 1 then
      PaintTabCloseMark(ABuffer, TabCaptionCloseCol(HeadX, Cap, True, True),
        ABounds.Top, ContrastingGlyphFg(TabBg, CloseFg, TabFg), TabBg);
    Inc(HeadX, TextDisplayWidth(Cap));
    if (I < High(APanel.Tabs)) and (HeadX < TabsRight) then
    begin
      DrawGridChar(ABuffer, HeadX, ABounds.Top, ASepChar, AFrame, ABodyBg);
      Inc(HeadX);
    end;
  end;
  PlusCol := PanelTabPlusCol(APanel, ABounds);
  if PlusCol >= 0 then
  begin
    AResolveChrome(pcpPanelTabActive, AActive, TabFg, TabBg);
    PutGridText(ABuffer, PlusCol, ABounds.Top, cPanelTabPlus, TabFg, TabBg);
  end;
end;

procedure DrawPanelListSeparator(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AUseDouble: Boolean; AFrame, ABodyBg: TAlphaColor);
var
  X, Y: Integer;
  H, VR, VL: Char;
begin
  if AUseDouble then
  begin
    H := chDblH;
    VR := chDblVR;
    VL := chDblVL;
  end
  else
  begin
    H := chBoxH;
    VR := chBoxVR;
    VL := chBoxVL;
  end;
  Y := ABounds.Bottom - 1 - PanelFooterRows;
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
    DrawGridChar(ABuffer, X, Y, H, AFrame, ABodyBg);
  DrawGridChar(ABuffer, ABounds.Left, Y, VR, AFrame, ABodyBg);
  DrawGridChar(ABuffer, ABounds.Right, Y, VL, AFrame, ABodyBg);
end;

procedure DrawPanelTotalsOnRule(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AFooter: string; AFooterFg, ABodyBg: TAlphaColor);
begin
  if AFooter = '' then
    Exit;
  PutGridText(ABuffer, ABounds.Left + (ABounds.Width - Length(AFooter)) div 2,
    ABounds.Bottom - 2, AFooter, AFooterFg, ABodyBg);
end;

procedure DrawPanelNdnFooterRows(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const ATotals, AFreeLine: string; AFreeUsedPermille: Integer;
  ATotalsFg, AInfoFg, AInfoBg: TAlphaColor);

  procedure CenterRow(ARow: Integer; const AText: string; AFg: TAlphaColor);
  var
    W: Integer;
    Txt: string;
  begin
    FillGridRect(ABuffer, ABounds.Left + 1, ARow, ABounds.Right - 2, ARow,
      ' ', AFg, AInfoBg);
    W := ABounds.Width - 3;
    Txt := Trim(AText);
    Txt := Copy(Txt, 1, TextFitChars(Txt, W));
    if Txt <> '' then
      PutGridText(ABuffer, ABounds.Left + 1 + (W - TextDisplayWidth(Txt)) div 2,
        ARow, Txt, AFg, AInfoBg);
  end;

  // The volume as a bar behind the free-space text, one cell in from each edge
  // of the row: the used part is shaded stronger than the free rest, so the end
  // of the bar stays visible. The cells keep their glyphs and only change
  // background.
  procedure TintBar(ARow: Integer; AFg: TAlphaColor);
  var
    X, First, BarW, Filled: Integer;
    UsedTint, FreeTint: TAlphaColor;
  begin
    BarW := ABounds.Width - 3 - 2 * cFooterBarMargin;
    if (BarW <= 0) or (ARow < 0) or (ARow >= Length(ABuffer)) then
      Exit;
    Filled := Round(Min(Max(AFreeUsedPermille, 0), 1000) / 1000 * BarW);
    UsedTint := MixTint(AFg, AInfoBg, cFooterBarUsedPct);
    FreeTint := MixTint(AFg, AInfoBg, cFooterBarFreePct);
    First := ABounds.Left + 1 + cFooterBarMargin;
    for X := First to Min(First + BarW - 1, Length(ABuffer[ARow]) - 1) do
      if X - First < Filled then
        ABuffer[ARow][X].BgColor := UsedTint
      else
        ABuffer[ARow][X].BgColor := FreeTint;
  end;

begin
  CenterRow(ABounds.Bottom - 2, ATotals, ATotalsFg);
  CenterRow(ABounds.Bottom - 1, AFreeLine, AInfoFg);
  if AFreeLine <> '' then
    TintBar(ABounds.Bottom - 1, AInfoFg);
end;

procedure DrawPanelCursorStrip(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AInfoLine: string; AFg, ABg: TAlphaColor);
begin
  FillGridRect(ABuffer, ABounds.Left, ABounds.Top,
    ABounds.Right, ABounds.Bottom, ' ', AFg, ABg);
  if AInfoLine <> '' then
    PutGridText(ABuffer, ABounds.Left, ABounds.Top, AInfoLine, AFg, ABg);
end;

procedure DrawPanelDropBadge(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AFg, ABg: TAlphaColor);
begin
  PutGridText(ABuffer, ABounds.Left + 2, ABounds.Top, ' DROP ', AFg, ABg);
end;

function IsQuickViewTarget(AViewKind: TPanelViewKind;
  ASide, AActiveSide: TPanelSide): Boolean;
begin
  Result := (AViewKind = pvkQuickView) and (ASide <> AActiveSide);
end;

procedure PanelFrameGlyphs(AActive: Boolean;
  out ATL, ATR, ABL, ABR, AH, AV: Char);
begin
  if AActive then
  begin
    ATL := chDblTL;
    ATR := chDblTR;
    ABL := chDblBL;
    ABR := chDblBR;
    AH := chDblH;
    AV := chDblV;
  end
  else
  begin
    ATL := chBoxTL;
    ATR := chBoxTR;
    ABL := chBoxBL;
    ABR := chBoxBR;
    AH := chBoxH;
    AV := chBoxV;
  end;
end;

function UseDoubleListSeparator(AActive, AHasTheme, AThemeUsesDouble: Boolean): Boolean;
begin
  Result := AActive and ((not AHasTheme) or AThemeUsesDouble);
end;

function PanelInfoStripBounds(const ABounds: TRectI): TRectI;
begin
  Result := TRectI.Make(ABounds.Left + 1, ABounds.Bottom - PanelFooterRows,
    ABounds.Right - 2, ABounds.Bottom - PanelFooterRows);
end;

function DualPanelChromeFits(AWidth, AHeight: Integer): Boolean;
begin
  Result := (AWidth >= 30) and (AHeight >= 12);
end;

procedure ComputePanelLayout(AWidth, AHeight: Integer; ALeftOn, ARightOn: Boolean;
  out ALeftBounds, ARightBounds: TRectI; out AListTop, AListBottom: Integer);
var
  PanelW, PanelH, TopY, BottomY: Integer;
  LeftOn, RightOn: Boolean;
begin
  // Rows (uChromeRows): menu, Dual Panel Tabs, panels (no gap under the
  // tabs), cmdline, F-keys, status line; the menu, F-keys and status line
  // can be hidden, and the panels take their rows.
  TopY := ContentTopRow;
  BottomY := CmdLineRow(AHeight) - 1;
  PanelH := BottomY - TopY + 1;
  if PanelH < 5 + PanelFooterRows then
    PanelH := 5 + PanelFooterRows;
  AListTop := TopY + 2;
  AListBottom := TopY + PanelH - 3 - PanelFooterRows;

  LeftOn := ALeftOn;
  RightOn := ARightOn;
  if not LeftOn and not RightOn then
  begin
    LeftOn := True;
    RightOn := True;
  end;

  if LeftOn and RightOn then
  begin
    PanelW := AWidth div 2;
    if PanelW < 12 then
      PanelW := Max(AWidth div 2, 10);
    ALeftBounds := TRectI.Make(0, TopY, PanelW - 1, TopY + PanelH - 1);
    ARightBounds := TRectI.Make(PanelW, TopY, AWidth - 1, TopY + PanelH - 1);
  end
  else if LeftOn then
  begin
    ALeftBounds := TRectI.Make(0, TopY, AWidth - 1, TopY + PanelH - 1);
    ARightBounds := TRectI.Make(-1, -1, -1, -1);
  end
  else
  begin
    ALeftBounds := TRectI.Make(-1, -1, -1, -1);
    ARightBounds := TRectI.Make(0, TopY, AWidth - 1, TopY + PanelH - 1);
  end;
end;

function EmbeddedDocumentPaintHeight(AClientHeight: Integer): Integer;
begin
  // The document draws its own F-keys and status line.
  Result := AClientHeight - ContentTopRow;
end;

function EmbeddedTerminalPaintHeight(AClientHeight: Integer): Integer;
begin
  Result := AClientHeight - ContentTopRow - ChromeBottomRows;
end;

function CanPaintEmbeddedContent(AHeight: Integer): Boolean;
begin
  Result := AHeight >= 6;
end;

function ClassifyDrawContent(AWidth, AHeight: Integer; AConsole: Boolean;
  AKind: TWorkspaceKind): TDrawContentKind;
begin
  if not DualPanelChromeFits(AWidth, AHeight) then
    Exit(dckTooSmall);
  if AConsole then
    Exit(dckConsole);
  case AKind of
    wkDocument:
      Result := dckDocument;
    wkTerminal:
      Result := dckTerminal;
  else
    Result := dckPanels;
  end;
end;

procedure DispatchDrawOverlays(const AHost: TDualPanelDrawHost;
  const ASnap: TDrawOverlaySnapshot);
begin
  AHost.DrawFolderTree();
  AHost.DrawDrivePopup();
  AHost.DrawHistoryPopup();
  AHost.DrawJobPopup();
  AHost.DrawUserMenu();
  AHost.DrawSortMenu();
  AHost.DrawColumnModeMenu();
  AHost.DrawSearchUi();
  if ASnap.DialogVisible then
    AHost.DrawDialog(ASnap.AreaWidth, ASnap.AreaHeight);
  AHost.DrawStub();
  if ASnap.SubmenuOpen then
    AHost.DrawSubmenu(ASnap.AreaWidth);
end;

function ClassifyPanelBody(AViewKind: TPanelViewKind;
  AIsQuickViewTarget: Boolean): TPanelBodyKind;
begin
  if AViewKind = pvkInfo then
    Result := pbkInfo
  else if AIsQuickViewTarget then
    Result := pbkQuickView
  else
    Result := pbkFiles;
end;

function PanelTabDragHoverIndex(ASide: TPanelSide; ADragActive: Boolean;
  ADragKind, ALeftKind, ARightKind, AHover: Integer): Integer;
var
  SideKind: Integer;
begin
  Result := -1;
  if not ADragActive then
    Exit;
  if ASide = psLeft then
    SideKind := ALeftKind
  else
    SideKind := ARightKind;
  if ADragKind = SideKind then
    Result := AHover;
end;

function IsQuickViewPreviewable(AHasRow, AIsOverlayImage: Boolean;
  const ARow: TPanelRow): Boolean;
begin
  Result := AHasRow and (not ARow.IsDirectory) and (not ARow.IsParent) and
    (ARow.URI <> '') and AIsOverlayImage;
end;

function QuickViewInteriorAbsBounds(const APanelBounds, AWindowArea: TRectI): TRectI;
begin
  Result := TRectI.Make(
    APanelBounds.Left + 1 + AWindowArea.Left,
    APanelBounds.Top + 1 + AWindowArea.Top,
    APanelBounds.Right - 1 + AWindowArea.Left,
    APanelBounds.Bottom - 1 + AWindowArea.Top);
end;

procedure DrawPanelShell(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  const APanel: TPanelState; AActive, AIsQuickViewTarget: Boolean;
  AFrame, ABodyBg, AFileFg: TAlphaColor; ADragHover: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
var
  TL, TR, BL, BR, H, V: Char;
  Cap: string;
  TabFg, TabBg: TAlphaColor;
begin
  PanelFrameGlyphs(AActive, TL, TR, BL, BR, H, V);
  if Assigned(ATheme) then
    ATheme.DrawPanelFrame(ABuffer, ABounds, AActive, [])
  else
    DrawPanelFrameGlyphs(ABuffer, ABounds, TL, TR, BL, BR, H, V, AFrame, AFileFg, ABodyBg);
  Cap := PanelModeTitleCaption(APanel.ViewKind, AIsQuickViewTarget);
  if Cap <> '' then
  begin
    AResolveChrome(pcpPanelTabActive, AActive, TabFg, TabBg);
    DrawCenteredPanelTitle(ABuffer, ABounds, Cap, TabFg, TabBg);
  end
  else
    DrawPanelEmbeddedTabs(ABuffer, ABounds, APanel, AActive, H, AFrame, ABodyBg,
      ADragHover, AResolveChrome);
end;

procedure DrawPanelFilesChrome(const ABuffer: TTerminalGrid;
  const ABounds: TRectI; AActive, AHasTheme, AThemeDouble: Boolean;
  AFrame, ABodyBg, AFooterFg: TAlphaColor; const AFooter, AInfoLine: string;
  const AFreeLine: string; AFreeUsedPermille: Integer;
  const AResolveChrome: TResolvePanelChromeProc);
var
  InfoBounds: TRectI;
  InfoFg, InfoBg: TAlphaColor;
begin
  DrawPanelListSeparator(ABuffer, ABounds,
    UseDoubleListSeparator(AActive, AHasTheme, AThemeDouble),
    AFrame, ABodyBg);
  InfoBounds := PanelInfoStripBounds(ABounds);
  AResolveChrome(pcpInfoStrip, AActive, InfoFg, InfoBg);
  DrawPanelCursorStrip(ABuffer, InfoBounds, AInfoLine, InfoFg, InfoBg);
  if GNdnFooter then
    DrawPanelNdnFooterRows(ABuffer, ABounds, AFooter, AFreeLine,
      AFreeUsedPermille, AFooterFg, InfoFg, InfoBg)
  else
    DrawPanelTotalsOnRule(ABuffer, ABounds, AFooter, AFooterFg, ABodyBg);
end;

procedure DrawPanelDropHighlight(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  AFallbackFg, AFallbackBg: TAlphaColor);
var
  Fg, Bg: TAlphaColor;
begin
  if Assigned(ATheme) then
    ATheme.ResolveDialogRowColors(True, Fg, Bg)
  else
  begin
    Fg := AFallbackFg;
    Bg := AFallbackBg;
  end;
  DrawPanelDropBadge(ABuffer, ABounds, Fg, Bg);
end;

procedure DispatchDrawPanelBody(const AHost: TDualPanelPanelHost;
  const ASnap: TDrawPanelSnapshot);
begin
  case ClassifyPanelBody(ASnap.ViewKind, ASnap.IsQuickViewTarget) of
    pbkInfo:
      begin
        AHost.DrawInfo(ASnap.Bounds, ASnap.Side, ASnap.Frame, ASnap.BodyBg);
        AHost.DrawDriveLetters(ASnap.Bounds, ASnap.Tab, ASnap.Side,
          ASnap.Frame, ASnap.BodyBg);
      end;
    pbkQuickView:
      AHost.DrawQuickView(ASnap.Bounds, ASnap.Side, ASnap.Frame, ASnap.BodyBg);
  else
    AHost.DrawFiles(ASnap.Bounds, ASnap.Panel, ASnap.Side, ASnap.Active,
      ASnap.Frame, ASnap.BodyBg);
  end;
end;

procedure DispatchPanelSearchFields(const ABounds: TRectI;
  ASide, AActiveSide: TPanelSide; AQuickSearch: Boolean;
  const ADrawQuick: TDrawBoundsProc);
begin
  if AQuickSearch and (ASide = AActiveSide) then
    ADrawQuick(ABounds);
end;

procedure DispatchDrawPanelFiles(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const AHost: TDualPanelFilesDrawHost;
  const ASnap: TDrawFilesSnapshot);
begin
  DrawPanelFilesChrome(ABuffer, ASnap.Bounds, ASnap.Active, ASnap.HasTheme,
    ASnap.ThemeDouble, ASnap.Frame, ASnap.BodyBg, ASnap.FooterFg, ASnap.Footer,
    ASnap.InfoLine, ASnap.FreeLine, ASnap.FreeUsedPermille, AHost.ResolveChrome);
  AHost.DrawDriveLetters(ASnap.Bounds, ASnap.Tab, ASnap.Side, ASnap.Frame,
    ASnap.BodyBg);
  AHost.DrawHeaders(ASnap.Bounds, ASnap.Panel);
  DrawPanelSortLetter(ABuffer, ASnap.Bounds, ASnap.Panel.SortColumn,
    ASnap.Panel.SortDescending, ASnap.Active, AHost.ResolveChrome);
  AHost.DrawList(ASnap.ListBounds, ASnap.Tab, ASnap.Active, ASnap.Panel.ColumnMode,
    ASnap.Side);
  if ASnap.DropHighlight then
    DrawPanelDropHighlight(ABuffer, ATheme, ASnap.Bounds, ASnap.DropFg, ASnap.DropBg);
  AHost.DrawScrollBar(ASnap.Bounds.Right - 1, ASnap.Bounds.Top + 2,
    ASnap.Bounds.Bottom - 2 - PanelFooterRows, ASnap.Tab.ScrollOffset, ASnap.Count, ASnap.PageSize);
  DispatchPanelSearchFields(ASnap.Bounds, ASnap.Side, ASnap.ActiveSide,
    ASnap.QuickSearch, AHost.DrawQuickSearch);
end;

end.
