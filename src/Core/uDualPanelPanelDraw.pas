unit uDualPanelPanelDraw;

{ Panel-frame chrome extracted from TDualPanelWindow.DrawPanel /
  DrawQuickViewContent, plus DrawContent classify/overlay dispatch and
  DrawPanel body classify (info / Quick View / files). Host still owns
  list/headers and the info/quick-view bodies. }

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uVfsTypes,
  uDualPanelTabs, uPanelColumns;

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
  const AFooter: string; AFrame, ABodyBg: TAlphaColor);
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
  AFrame, ABodyBg: TAlphaColor; const AFooter, AInfoLine: string;
  const AResolveChrome: TResolvePanelChromeProc);
procedure DrawPanelDropHighlight(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const ABounds: TRectI;
  AFallbackFg, AFallbackBg: TAlphaColor);
procedure DispatchDrawPanelBody(const AHost: TDualPanelPanelHost;
  const ASnap: TDrawPanelSnapshot);
procedure DispatchPanelSearchFields(const ABounds: TRectI;
  ASide, AActiveSide: TPanelSide; AQuickSearch, AFilter: Boolean;
  const ADrawQuick, ADrawFilter: TDrawBoundsProc);

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
    Frame, BodyBg, DropFg, DropBg: TAlphaColor;
    Count, PageSize: Integer;
    Footer, InfoLine: string;
    HasTheme, ThemeDouble, DropHighlight, QuickSearch, Filter: Boolean;
  end;

  TDualPanelFilesDrawHost = record
    ResolveChrome: TResolvePanelChromeProc;
    DrawDriveLetters: TDrawPanelDriveProc;
    DrawHeaders: TDrawFilesHeadersProc;
    DrawList: TDrawFilesListProc;
    DrawScrollBar: TDrawFilesScrollProc;
    DrawQuickSearch: TDrawBoundsProc;
    DrawFilter: TDrawBoundsProc;
  end;

procedure DispatchDrawPanelFiles(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const AHost: TDualPanelFilesDrawHost;
  const ASnap: TDrawFilesSnapshot);

implementation

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
begin
  if AHasSelection then
    Result := Format(' Selected: %s, files: %d, folders: %d ',
      [FormatSizeShort(ABytes), AFiles, AFolders])
  else
    Result := Format(' Bytes: %s, files: %d, folders: %d ',
      [FormatSizeShort(ABytes), AFiles, AFolders]);
  if Length(Result) > AMaxWidth then
    Result := Copy(Result, 1, AMaxWidth);
end;

function FormatPanelCursorInfoLine(const ARow: TPanelRow; AWidth: Integer): string;
var
  NamePart, MetaPart: string;
  MaxName: Integer;
begin
  NamePart := ARow.Text;
  if ARow.MatchSnippet <> '' then
    MetaPart := Format('L%d: %s', [ARow.MatchLine, ARow.MatchSnippet])
  else
  begin
    MetaPart := ARow.SizeText;
    if ARow.DateText <> '' then
      MetaPart := MetaPart + ' ' + ARow.DateText;
  end;
  MaxName := Max(AWidth - Length(MetaPart) - 1, 4);
  if Length(NamePart) > MaxName then
    NamePart := EllipsizeKeepingExt(NamePart, MaxName);
  if Length(NamePart) < MaxName then
    NamePart := NamePart + StringOfChar(' ', MaxName - Length(NamePart))
  else if Length(NamePart) > MaxName then
    NamePart := Copy(NamePart, 1, MaxName);
  Result := NamePart + ' ' + MetaPart;
  if Length(Result) > AWidth then
    Result := Copy(Result, 1, AWidth);
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
  I, HeadX, TabsRight, TabMaxLen: Integer;
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
    if HeadX + Length(Cap) >= TabsRight then
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
    Inc(HeadX, Length(Cap));
    if (I < High(APanel.Tabs)) and (HeadX < TabsRight) then
    begin
      DrawGridChar(ABuffer, HeadX, ABounds.Top, ASepChar, AFrame, ABodyBg);
      Inc(HeadX);
    end;
  end;
end;

procedure DrawPanelListSeparator(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  AUseDouble: Boolean; AFrame, ABodyBg: TAlphaColor);
var
  X: Integer;
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
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
    DrawGridChar(ABuffer, X, ABounds.Bottom - 2, H, AFrame, ABodyBg);
  DrawGridChar(ABuffer, ABounds.Left, ABounds.Bottom - 2, VR, AFrame, ABodyBg);
  DrawGridChar(ABuffer, ABounds.Right, ABounds.Bottom - 2, VL, AFrame, ABodyBg);
end;

procedure DrawPanelTotalsOnRule(const ABuffer: TTerminalGrid; const ABounds: TRectI;
  const AFooter: string; AFrame, ABodyBg: TAlphaColor);
begin
  if AFooter = '' then
    Exit;
  PutGridText(ABuffer, ABounds.Left + (ABounds.Width - Length(AFooter)) div 2,
    ABounds.Bottom - 2, AFooter, AFrame, ABodyBg);
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
  Result := TRectI.Make(ABounds.Left + 1, ABounds.Bottom - 1,
    ABounds.Right - 2, ABounds.Bottom - 1);
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
  // Rows: 0 menu, 1 Dual Panel Tabs, 2..H-4 panels (no gap under tabs),
  // H-3 cmdline, H-2 F-keys, H-1 status line.
  TopY := 2;
  BottomY := AHeight - 4;
  PanelH := BottomY - TopY + 1;
  if PanelH < 6 then
    PanelH := 6;
  AListTop := TopY + 2;
  AListBottom := TopY + PanelH - 4;

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
  Result := AClientHeight - 2;
end;

function EmbeddedTerminalPaintHeight(AClientHeight: Integer): Integer;
begin
  Result := AClientHeight - 4;
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
begin
  Result := -1;
  if ADragActive and
    (((ASide = psLeft) and (ADragKind = ALeftKind)) or
     ((ASide = psRight) and (ADragKind = ARightKind))) then
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
  AFrame, ABodyBg: TAlphaColor; const AFooter, AInfoLine: string;
  const AResolveChrome: TResolvePanelChromeProc);
var
  InfoBounds: TRectI;
  InfoFg, InfoBg: TAlphaColor;
begin
  DrawPanelListSeparator(ABuffer, ABounds,
    UseDoubleListSeparator(AActive, AHasTheme, AThemeDouble),
    AFrame, ABodyBg);
  DrawPanelTotalsOnRule(ABuffer, ABounds, AFooter, AFrame, ABodyBg);
  InfoBounds := PanelInfoStripBounds(ABounds);
  AResolveChrome(pcpInfoStrip, AActive, InfoFg, InfoBg);
  DrawPanelCursorStrip(ABuffer, InfoBounds, AInfoLine, InfoFg, InfoBg);
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
  ASide, AActiveSide: TPanelSide; AQuickSearch, AFilter: Boolean;
  const ADrawQuick, ADrawFilter: TDrawBoundsProc);
begin
  if AQuickSearch and (ASide = AActiveSide) then
    ADrawQuick(ABounds);
  if AFilter and (ASide = AActiveSide) then
    ADrawFilter(ABounds);
end;

procedure DispatchDrawPanelFiles(const ABuffer: TTerminalGrid;
  const ATheme: IThemeRenderer; const AHost: TDualPanelFilesDrawHost;
  const ASnap: TDrawFilesSnapshot);
begin
  DrawPanelFilesChrome(ABuffer, ASnap.Bounds, ASnap.Active, ASnap.HasTheme,
    ASnap.ThemeDouble, ASnap.Frame, ASnap.BodyBg, ASnap.Footer, ASnap.InfoLine,
    AHost.ResolveChrome);
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
    ASnap.Bounds.Bottom - 3, ASnap.Tab.ScrollOffset, ASnap.Count, ASnap.PageSize);
  DispatchPanelSearchFields(ASnap.Bounds, ASnap.Side, ASnap.ActiveSide,
    ASnap.QuickSearch, ASnap.Filter, AHost.DrawQuickSearch, AHost.DrawFilter);
end;

end.
