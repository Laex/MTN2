unit TestDualPanelPanelDraw;

{ Pure formatters + chrome helpers extracted from DrawPanel. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelPanelDraw = class
  public
    [Test] procedure TestCaptionsAndFooters;
    [Test] procedure TestSeparatorAndTitle;
    [Test] procedure TestDriveLetterHit;
    [Test] procedure TestDrivePreviewHelpers;
    [Test] procedure TestDriveBarDraw;
    [Test] procedure TestDrawPanelHelpers;
    [Test] procedure TestDrawContentDispatch;
    [Test] procedure TestListRowHelpers;
    [Test] procedure TestDrawPanelDispatch;
    [Test] procedure TestDrawPanelFilesDispatch;
    [Test] procedure TestPanelLayout;
    [Test] procedure TestTabCloseMarkContrast;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uVfsTypes,
  uDualPanelTypes,
  uDriveInfo,
  uDualPanelDrawUtils,
  uDualPanelPanelDraw;

type
  TDrawSpy = class
  public
    Last: string;
    DialogW, DialogH, SubW: Integer;
    procedure Tree;
    procedure Drive;
    procedure History;
    procedure Job;
    procedure UserMenu;
    procedure SortMenu;
    procedure ColumnMode;
    procedure Stub;
    procedure Search;
    procedure Dialog(AWidth, AHeight: Integer);
    procedure Submenu(AWidth: Integer);
  end;

  TPanelSpy = class
  public
    Last: string;
    procedure Info(const ABounds: TRectI; ASide: TPanelSide;
      AFrame, ABodyBg: TAlphaColor);
    procedure QuickView(const ABounds: TRectI; ASide: TPanelSide;
      AFrame, ABodyBg: TAlphaColor);
    procedure DriveLetters(const ABounds: TRectI; const ATab: TTab;
      ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
    procedure Files(const ABounds: TRectI; const APanel: TPanelState;
      ASide: TPanelSide; AActive: Boolean; AFrame, ABodyBg: TAlphaColor);
    procedure QuickSearch(const ABounds: TRectI);
    procedure Filter(const ABounds: TRectI);
    procedure ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
  end;

  TCloseChromeSpy = class
  public
    procedure ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
  end;

  TFilesSpy = class
  public
    Last: string;
    ListSide: TPanelSide;
    ScrollX, ScrollViewH: Integer;
    procedure ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure DriveLetters(const ABounds: TRectI; const ATab: TTab;
      ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
    procedure Headers(const ABounds: TRectI; const APanel: TPanelState);
    procedure List(const AListBounds: TRectI; const ATab: TTab;
      AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide);
    procedure Scroll(AX, ATop, ABottom, APos, ACount, AViewH: Integer);
    procedure Quick(const ABounds: TRectI);
    procedure Filter(const ABounds: TRectI);
  end;

procedure TDrawSpy.Tree;
begin
  Last := Last + 'tree,';
end;

procedure TDrawSpy.Drive;
begin
  Last := Last + 'drive,';
end;

procedure TDrawSpy.History;
begin
  Last := Last + 'history,';
end;

procedure TDrawSpy.Job;
begin
  Last := Last + 'job,';
end;

procedure TDrawSpy.UserMenu;
begin
  Last := Last + 'user,';
end;

procedure TDrawSpy.SortMenu;
begin
  Last := Last + 'sort,';
end;

procedure TDrawSpy.ColumnMode;
begin
  Last := Last + 'cols,';
end;

procedure TDrawSpy.Stub;
begin
  Last := Last + 'stub,';
end;

procedure TDrawSpy.Search;
begin
  Last := Last + 'search,';
end;

procedure TDrawSpy.Dialog(AWidth, AHeight: Integer);
begin
  Last := Last + 'dialog,';
  DialogW := AWidth;
  DialogH := AHeight;
end;

procedure TDrawSpy.Submenu(AWidth: Integer);
begin
  Last := Last + 'sub,';
  SubW := AWidth;
end;

procedure TPanelSpy.Info(const ABounds: TRectI; ASide: TPanelSide;
  AFrame, ABodyBg: TAlphaColor);
begin
  Last := Last + 'info,';
end;

procedure TPanelSpy.QuickView(const ABounds: TRectI; ASide: TPanelSide;
  AFrame, ABodyBg: TAlphaColor);
begin
  Last := Last + 'qv,';
end;

procedure TPanelSpy.DriveLetters(const ABounds: TRectI; const ATab: TTab;
  ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
begin
  Last := Last + 'drive,';
end;

procedure TPanelSpy.Files(const ABounds: TRectI; const APanel: TPanelState;
  ASide: TPanelSide; AActive: Boolean; AFrame, ABodyBg: TAlphaColor);
begin
  Last := Last + 'files,';
end;

procedure TPanelSpy.QuickSearch(const ABounds: TRectI);
begin
  Last := Last + 'quick,';
end;

procedure TPanelSpy.Filter(const ABounds: TRectI);
begin
  Last := Last + 'filter,';
end;

procedure TPanelSpy.ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor);
begin
  AFg := TAlphaColors.Yellow;
  ABg := TAlphaColors.Blue;
end;

procedure TCloseChromeSpy.ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor);
const
  cPink = TAlphaColor($FFFF79C6);
  cPurple = TAlphaColor($FFBD93F9);
  cDark = TAlphaColor($FF282A36);
  cIdleFg = TAlphaColor($FF6272A4);
  cIdleBg = TAlphaColor($FF44475A);
begin
  case APart of
    pcpPanelTabActive:
      begin
        AFg := cDark;
        ABg := cPurple;
      end;
    pcpPanelTabIdle:
      begin
        AFg := cIdleFg;
        ABg := cIdleBg;
      end;
    pcpCloseMark:
      begin
        AFg := cPink;
        ABg := cDark;
      end;
  else
    begin
      AFg := TAlphaColors.Yellow;
      ABg := TAlphaColors.Blue;
    end;
  end;
end;

procedure TFilesSpy.ResolveChrome(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor);
begin
  AFg := TAlphaColors.Yellow;
  ABg := TAlphaColors.Blue;
end;

procedure TFilesSpy.DriveLetters(const ABounds: TRectI; const ATab: TTab;
  ASide: TPanelSide; AFrame, ABodyBg: TAlphaColor);
begin
  Last := Last + 'drive,';
end;

procedure TFilesSpy.Headers(const ABounds: TRectI; const APanel: TPanelState);
begin
  Last := Last + 'headers,';
end;

procedure TFilesSpy.List(const AListBounds: TRectI; const ATab: TTab;
  AActive: Boolean; AMode: TPanelColumnMode; ASide: TPanelSide);
begin
  Last := Last + 'list,';
  ListSide := ASide;
end;

procedure TFilesSpy.Scroll(AX, ATop, ABottom, APos, ACount, AViewH: Integer);
begin
  Last := Last + 'scroll,';
  ScrollX := AX;
  ScrollViewH := AViewH;
end;

procedure TFilesSpy.Quick(const ABounds: TRectI);
begin
  Last := Last + 'quick,';
end;

procedure TFilesSpy.Filter(const ABounds: TRectI);
begin
  Last := Last + 'filter,';
end;

procedure TestCaptionsAndFooters;
var
  Footer, Line: string;
  Row: TPanelRow;
begin
  Assert.IsTrue(PanelModeTitleCaption(pvkInfo, False) = ' Information ', 'info title');
  Assert.IsTrue(PanelModeTitleCaption(pvkQuickView, True) = ' Quick View ', 'quick-view title');
  Assert.IsTrue(PanelModeTitleCaption(pvkFiles, False) = '', 'file panel has no mode title');
  Assert.IsTrue(PanelModeTitleCaption(pvkQuickView, False) = '',
    'quick-view on the active side is not a title');

  Footer := FormatPanelTotalsFooter(False, 1024, 1, 2, 80);
  Assert.IsTrue(Footer = Format(' Bytes: %s, files: %d, folders: %d ',
    [FormatSizeShort(1024), 1, 2]), 'bytes footer');
  Footer := FormatPanelTotalsFooter(True, 10, 3, 4, 80);
  Assert.IsTrue(Pos('Selected:', Footer) = 2, 'selection footer');
  Footer := FormatPanelTotalsFooter(True, 1, 2, 3, 10);
  Assert.IsTrue(Length(Footer) = 10, 'footer truncated to max width');

  Row := Default(TPanelRow);
  Row.Text := 'VeryLongFileName.txt';
  Row.SizeText := '1K';
  Row.DateText := '01.01.20';
  Line := FormatPanelCursorInfoLine(Row, 20);
  Assert.IsTrue(Pos('...', Line) > 0, 'long name mid-ellipsis');
  Assert.IsTrue(Pos('.txt', Line) > 0, 'cursor line keeps extension');
  Assert.IsTrue(Pos('~', Line) = 0, 'no tilde truncation');
  Assert.IsTrue(Length(Line) <= 20, 'cursor line fits width');
  Assert.IsTrue(Pos('1K', Line) > 0, 'size kept in cursor line');

  Row.MatchLine := 12;
  Row.MatchSnippet := 'hello';
  Line := FormatPanelCursorInfoLine(Row, 40);
  Assert.IsTrue(Pos('L12: hello', Line) > 0, 'Alt+F7 snippet in cursor line');

  Row := Default(TPanelRow);
  Assert.IsTrue(FormatQuickViewPlaceholder(False, Row) = '', 'no row -> empty placeholder');
  Row.IsDirectory := True;
  Assert.IsTrue(FormatQuickViewPlaceholder(True, Row) = '(directory)', 'directory placeholder');
  Row := Default(TPanelRow);
  Row.IsParent := True;
  Assert.IsTrue(FormatQuickViewPlaceholder(True, Row) = '(directory)', 'parent placeholder');
  Row := Default(TPanelRow);
  Row.URI := 'file:///C:/a.png';
  Row.Extension := '.png';
  Assert.IsTrue(FormatQuickViewPlaceholder(True, Row) = '(no preview: .png)',
    'file placeholder keeps extension');
  Row.URI := '';
  Assert.IsTrue(FormatQuickViewPlaceholder(True, Row) = '', 'empty URI -> no placeholder');
end;

procedure TestSeparatorAndTitle;
var
  Grid: TTerminalGrid;
  Bounds: TRectI;
  Fg, Bg: TAlphaColor;
begin
  AllocTerminalGrid(Grid, 20, 8);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
  Bounds := TRectI.Make(0, 0, 19, 7);
  Fg := TAlphaColors.Yellow;
  Bg := TAlphaColors.Blue;

  DrawPanelListSeparator(Grid, Bounds, True, Fg, Bg);
  Assert.IsTrue(Grid[5][0].CharValue = chDblVR, 'double separator left joint');
  Assert.IsTrue(Grid[5][19].CharValue = chDblVL, 'double separator right joint');
  Assert.IsTrue(Grid[5][1].CharValue = chDblH, 'double separator rule');

  DrawPanelListSeparator(Grid, Bounds, False, Fg, Bg);
  Assert.IsTrue(Grid[5][0].CharValue = chBoxVR, 'single separator left joint');
  Assert.IsTrue(Grid[5][10].CharValue = chBoxH, 'single separator rule');

  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
  DrawCenteredPanelTitle(Grid, Bounds, ' Information ', Fg, Bg);
  Assert.IsTrue(Grid[0][CenteredTextCol(Bounds, ' Information ')].CharValue = ' ',
    'title starts with padding space');
  Assert.IsTrue(Grid[0][CenteredTextCol(Bounds, ' Information ') + 1].CharValue = 'I',
    'title I is centered');

  DrawPanelDropBadge(Grid, Bounds, Fg, Bg);
  Assert.IsTrue(Grid[0][2].CharValue = ' ', 'drop badge inset');
  Assert.IsTrue(Grid[0][3].CharValue = 'D', 'drop badge D');
end;

procedure TestDriveLetterHit;
var
  Bounds: TRectI;
  Letter: Char;
  Col: Integer;
  Hit: Boolean;
  Found1: Boolean;
begin
  Bounds := TRectI.Make(0, 0, 80, 10);
  Assert.IsTrue(not HitPanelDriveLetterAtCol(Bounds, Bounds.Left, Letter),
    'left frame cell is not a letter');
  Assert.IsTrue(not HitPanelDriveLetterAtCol(Bounds, Bounds.Left + 1, Letter),
    'opening bracket is not a letter');

  Bounds := TRectI.Make(0, 0, 3, 10);
  Assert.IsTrue(not HitPanelDriveLetterAtCol(Bounds, 2, Letter),
    'too-narrow bar has no letters');

  Bounds := TRectI.Make(0, 0, 80, 10);
  Hit := False;
  for Col := Bounds.Left to Bounds.Right do
    if HitPanelDriveLetterAtCol(Bounds, Col, Letter) then
    begin
      Hit := True;
      Assert.IsTrue(((Letter >= 'A') and (Letter <= 'Z')) or
        IsChangeDriveSpecialGlyph(Letter), 'hit glyph is A-Z or special');
      Break;
    end;
  Assert.IsTrue(Hit, 'wide bar has at least one glyph');

  Found1 := False;
  for Col := Bounds.Left to Bounds.Right do
    if HitPanelDriveLetterAtCol(Bounds, Col, Letter) and (Letter = '1') then
    begin
      Found1 := True;
      Break;
    end;
  Assert.IsTrue(Found1, 'Change Drive special 1 is clickable on the bar');
end;

procedure TestDrivePreviewHelpers;
var
  Drives: TDriveInfoArray;
  Glyphs: TArray<Char>;
  DriveCount: Integer;
  ShowSep: Boolean;
  I: Integer;
  HasSpecial: Boolean;
begin
  Assert.IsTrue(DriveLetterFromPath('C:\Work') = 'C', 'path letter');
  Assert.IsTrue(DriveLetterFromPath('c:/tmp') = 'C', 'forward slash still has colon');
  Assert.IsTrue(DriveLetterFromPath('\\server\share') = #0, 'UNC has no letter');
  Assert.IsTrue(DriveLetterFromPath('') = #0, 'empty path');

  Assert.IsTrue(HighlightDriveLetter(True, psLeft, psLeft, 'D', 'C') = 'D',
    'preview on same side');
  Assert.IsTrue(HighlightDriveLetter(True, psRight, psLeft, 'D', 'C') = 'C',
    'preview on other side');
  Assert.IsTrue(HighlightDriveLetter(True, psLeft, psLeft, #0, 'C') = 'C',
    'empty preview letter');
  Assert.IsTrue(HighlightDriveLetter(False, psLeft, psLeft, 'D', 'C') = 'C',
    'inactive preview');
  Assert.IsTrue(HighlightDriveLetter(True, psLeft, psLeft, '3', 'C') = '3',
    'preview special glyph');

  Assert.IsTrue(CycleDriveIndex(3, 2, 1) = 0, 'wrap forward');
  Assert.IsTrue(CycleDriveIndex(3, 0, -1) = 2, 'wrap backward');
  Assert.IsTrue(CycleDriveIndex(3, -1, 1) = 0, 'missing +delta starts at 0');
  Assert.IsTrue(CycleDriveIndex(3, -1, -1) = 2, 'missing -delta starts at last');
  Assert.IsTrue(CycleDriveIndex(3, 1, 0) = 1, 'zero delta keeps index');
  Assert.IsTrue(CycleDriveIndex(0, 1, 1) = 1, 'empty list keeps index');

  SetLength(Drives, 2);
  Drives[0].Letter := 'C';
  Drives[1].Letter := 'D';
  Assert.IsTrue(IndexOfDriveLetter(Drives, 'd') = 1, 'index is case-insensitive');
  Assert.IsTrue(IndexOfDriveLetter(Drives, 'Z') = -1, 'missing letter');

  Assert.IsTrue(DriveBarGlyphFromUri('sys://folders') = '1', 'sys folders glyph');
  Assert.IsTrue(DriveBarGlyphFromUri('recycle:///') = '2', 'recycle glyph');
  Assert.IsTrue(DriveBarGlyphFromUri('recycle://C:/') = '2', 'recycle volume glyph');
  Assert.IsTrue(DriveBarGlyphFromUri('tmp:///') = '3', 'tmp panel glyph');
  Assert.IsTrue(DriveBarGlyphFromUri('ws:///') = '4', 'workspace glyph');
  Assert.IsTrue(DriveBarGlyphFromUri('file:///C:/Work') = 'C', 'file URI drive glyph');

  Assert.IsTrue(DrivePopupCursorIndex(Drives, 'file:///D:/docs') = 1, 'popup cursor on D');
  Assert.IsTrue(DrivePopupCursorIndex(Drives, 'file:///C:/') = 0, 'popup cursor on C');
  Assert.IsTrue(DrivePopupCursorIndex(Drives, 'ws:///') =
    Length(Drives) + 1 + 3, 'popup cursor on Workspace');
  Assert.IsTrue(DrivePopupCursorIndex(Drives, 'sys://folders') =
    Length(Drives) + 1, 'popup cursor on System folders');
  Assert.IsTrue(DrivePopupCursorIndex(Drives, 'tmp:///') =
    Length(Drives) + 1 + 2, 'popup cursor on Temporary');
  Assert.IsTrue(DrivePopupCursorIndex(Drives, '') = 0, 'unknown URI stays on first');

  Glyphs := EnumDriveBarGlyphs;
  Assert.IsTrue(Length(Glyphs) >= ChangeDriveSpecialCount, 'bar lists specials');
  HasSpecial := False;
  for I := 0 to High(Glyphs) do
    if Glyphs[I] = '1' then
      HasSpecial := True;
  Assert.IsTrue(HasSpecial, 'bar glyphs include special 1');
  Assert.IsTrue(IndexOfDriveBarGlyph(Glyphs, '4') = Length(Glyphs) - 1,
    'Workspace is last Change Drive item');
  Assert.IsTrue(IndexOfDriveBarGlyph(Glyphs, '3') = Length(Glyphs) - 2,
    'Temporary is before Workspace');
  Assert.IsTrue(IndexOfDriveBarGlyph(Glyphs, '1') =
    Length(Glyphs) - ChangeDriveSpecialCount, 'System folders follows drives');

  FitDriveBarGlyphs(80, Glyphs, DriveCount, ShowSep);
  Assert.IsTrue(Length(Glyphs) >= ChangeDriveSpecialCount, 'fitted bar keeps specials');
  Assert.IsTrue(ShowSep = (DriveCount > 0), 'separator when drives and specials both show');
  FitDriveBarGlyphs(5, Glyphs, DriveCount, ShowSep);
  Assert.IsTrue((Length(Glyphs) = 1) and (Glyphs[0] = '1') and (not ShowSep),
    'narrow bar keeps first special');
end;

procedure TestDriveBarDraw;
var
  Grid: TTerminalGrid;
  Bounds: TRectI;
  Tab: TTab;
  Row: string;
  Col: Integer;
  Has1, Has2, Has3, Has4: Boolean;
begin
  AllocTerminalGrid(Grid, 52, 8);
  ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
  Bounds := TRectI.Make(0, 0, 51, 7);
  Tab := Default(TTab);
  Tab.CurrentURI := 'tmp:///';
  DrawPanelDriveLetterBar(Grid, Bounds, Tab, psLeft,
    TAlphaColors.Yellow, TAlphaColors.Blue, False, psLeft, #0);
  Row := '';
  Has1 := False;
  Has2 := False;
  Has3 := False;
  Has4 := False;
  for Col := 0 to 51 do
  begin
    Row := Row + Grid[7][Col].CharValue;
    if Grid[7][Col].CharValue = '1' then
      Has1 := True;
    if Grid[7][Col].CharValue = '2' then
      Has2 := True;
    if Grid[7][Col].CharValue = '3' then
      Has3 := True;
    if Grid[7][Col].CharValue = '4' then
      Has4 := True;
  end;
  Assert.IsTrue(Has1 and Has2 and Has3 and Has4, 'bar paints 1 2 3 4 Change Drive extras');
  // Fast (letters only): the full pass waits on every mapped drive and can
  // take minutes when a network drive is unreachable.
  if Length(EnumLogicalDrivesFast) > 0 then
    Assert.IsTrue(Pos('|', Row) > 0, 'bar separator between drives and specials');
end;

procedure TestDrawPanelHelpers;
var
  TL, TR, BL, BR, H, V: Char;
  Bounds, Info: TRectI;
begin
  Assert.IsTrue(IsQuickViewTarget(pvkQuickView, psLeft, psRight), 'idle side is QV target');
  Assert.IsTrue(not IsQuickViewTarget(pvkQuickView, psLeft, psLeft), 'active side is not QV');
  Assert.IsTrue(not IsQuickViewTarget(pvkFiles, psLeft, psRight), 'files is not QV');

  PanelFrameGlyphs(True, TL, TR, BL, BR, H, V);
  Assert.IsTrue((TL = chDblTL) and (H = chDblH), 'active frame is double');
  PanelFrameGlyphs(False, TL, TR, BL, BR, H, V);
  Assert.IsTrue((TL = chBoxTL) and (V = chBoxV), 'idle frame is single');

  Assert.IsTrue(UseDoubleListSeparator(True, False, False), 'no theme: active is double');
  Assert.IsTrue(not UseDoubleListSeparator(False, False, False), 'idle is single');
  Assert.IsTrue(UseDoubleListSeparator(True, True, True), 'theme double');
  Assert.IsTrue(not UseDoubleListSeparator(True, True, False), 'theme single active');

  Bounds := TRectI.Make(0, 2, 40, 20);
  Info := PanelInfoStripBounds(Bounds);
  Assert.IsTrue((Info.Left = 1) and (Info.Right = 38) and (Info.Top = 19) and
    (Info.Bottom = 19), 'info strip inset');

  Assert.IsTrue(not DualPanelChromeFits(29, 20), 'too narrow');
  Assert.IsTrue(not DualPanelChromeFits(80, 11), 'too short');
  Assert.IsTrue(DualPanelChromeFits(30, 12), 'min chrome');
  Assert.IsTrue(EmbeddedDocumentPaintHeight(20) = 18, 'document leaves menu+tabs');
  Assert.IsTrue(EmbeddedTerminalPaintHeight(20) = 16, 'terminal leaves F-bar+status');
  Assert.IsTrue(CanPaintEmbeddedContent(6), 'min embedded');
  Assert.IsTrue(not CanPaintEmbeddedContent(5), 'too small embedded');
end;

procedure TestDrawContentDispatch;
var
  Spy: TDrawSpy;
  Host: TDualPanelDrawHost;
  Snap: TDrawOverlaySnapshot;
begin
  Assert.IsTrue(ClassifyDrawContent(10, 10, False, wkPanels) = dckTooSmall, 'too small');
  Assert.IsTrue(ClassifyDrawContent(80, 24, True, wkPanels) = dckConsole, 'console wins');
  Assert.IsTrue(ClassifyDrawContent(80, 24, False, wkDocument) = dckDocument, 'document');
  Assert.IsTrue(ClassifyDrawContent(80, 24, False, wkTerminal) = dckTerminal, 'terminal');
  Assert.IsTrue(ClassifyDrawContent(80, 24, False, wkPanels) = dckPanels, 'panels');
  Assert.IsTrue(ClassifyDrawContent(80, 24, True, wkDocument) = dckConsole,
    'console before document');

  Spy := TDrawSpy.Create;
  try
    Host := Default(TDualPanelDrawHost);
    Host.DrawFolderTree := Spy.Tree;
    Host.DrawDrivePopup := Spy.Drive;
    Host.DrawHistoryPopup := Spy.History;
    Host.DrawJobPopup := Spy.Job;
    Host.DrawUserMenu := Spy.UserMenu;
    Host.DrawSortMenu := Spy.SortMenu;
    Host.DrawColumnModeMenu := Spy.ColumnMode;
    Host.DrawStub := Spy.Stub;
    Host.DrawSearchUi := Spy.Search;
    Host.DrawDialog := Spy.Dialog;
    Host.DrawSubmenu := Spy.Submenu;
    Snap := Default(TDrawOverlaySnapshot);
    Snap.AreaWidth := 80;
    Snap.AreaHeight := 24;
    DispatchDrawOverlays(Host, Snap);
    Assert.IsTrue(Spy.Last = 'tree,drive,history,job,user,sort,cols,search,stub,',
      'overlay order without dialog');
    Snap.DialogVisible := True;
    Snap.SubmenuOpen := True;
    Spy.Last := '';
    DispatchDrawOverlays(Host, Snap);
    Assert.IsTrue(Spy.Last = 'tree,drive,history,job,user,sort,cols,search,dialog,stub,sub,',
      'dialog then stub then submenu last');
    Assert.IsTrue((Spy.DialogW = 80) and (Spy.DialogH = 24) and (Spy.SubW = 80),
      'dialog/submenu sizes');
  finally
    Spy.Free;
  end;
end;

procedure TestListRowHelpers;
var
  Fg, Bg: TAlphaColor;
begin
  Assert.IsTrue(ColorCodingItemName('Docs/') = 'Docs', 'strip dir slash');
  Assert.IsTrue(ColorCodingItemName('a.txt') = 'a.txt', 'file name kept');
  FallbackFileRowColors(False, False, False, False, True, True, Fg, Bg);
  Assert.IsTrue((Fg = TAlphaColor($FF000000)) and (Bg = TAlphaColor($FF00AAAA)),
    'active cursor');
  FallbackFileRowColors(False, False, False, True, True, True, Fg, Bg);
  Assert.IsTrue(Bg = TAlphaColor($FFFFFF55), 'selected cursor uses hot bg');
  FallbackFileRowColors(True, False, False, False, False, True, Fg, Bg);
  Assert.IsTrue((Fg = TAlphaColor($FFFFFFFF)) and (Bg = TAlphaColor($FF0000AA)),
    'idle dir');
  FallbackFileRowColors(False, False, True, False, False, True, Fg, Bg);
  Assert.IsTrue(Fg = TAlphaColor($FF888888), 'hidden file');
end;

procedure TestDrawPanelDispatch;
var
  Spy: TPanelSpy;
  Host: TDualPanelPanelHost;
  Snap: TDrawPanelSnapshot;
  Row: TPanelRow;
  Panel: TPanelState;
  Bounds, Area, AbsB: TRectI;
  Grid: TTerminalGrid;
begin
  Assert.IsTrue(ClassifyPanelBody(pvkInfo, True) = pbkInfo, 'info wins over QV flag');
  Assert.IsTrue(ClassifyPanelBody(pvkQuickView, True) = pbkQuickView, 'QV target');
  Assert.IsTrue(ClassifyPanelBody(pvkQuickView, False) = pbkFiles, 'QV on active is files');
  Assert.IsTrue(ClassifyPanelBody(pvkFiles, False) = pbkFiles, 'files');

  Assert.IsTrue(PanelTabDragHoverIndex(psLeft, False, 2, 2, 3, 4) = -1, 'no drag');
  Assert.IsTrue(PanelTabDragHoverIndex(psLeft, True, 2, 2, 3, 4) = 4, 'left panel drag');
  Assert.IsTrue(PanelTabDragHoverIndex(psRight, True, 2, 2, 3, 4) = -1, 'left kind on right');
  Assert.IsTrue(PanelTabDragHoverIndex(psRight, True, 3, 2, 3, 7) = 7, 'right panel drag');

  Row := Default(TPanelRow);
  Assert.IsTrue(not IsQuickViewPreviewable(False, True, Row), 'no row');
  Row.IsDirectory := True;
  Row.URI := 'file:///C:/a';
  Assert.IsTrue(not IsQuickViewPreviewable(True, True, Row), 'directory');
  Row := Default(TPanelRow);
  Row.IsParent := True;
  Row.URI := 'file:///C:/';
  Assert.IsTrue(not IsQuickViewPreviewable(True, True, Row), 'parent');
  Row := Default(TPanelRow);
  Assert.IsTrue(not IsQuickViewPreviewable(True, True, Row), 'empty URI');
  Row.URI := 'file:///C:/a.png';
  Assert.IsTrue(not IsQuickViewPreviewable(True, False, Row), 'not overlay image');
  Assert.IsTrue(IsQuickViewPreviewable(True, True, Row), 'previewable image');

  Bounds := TRectI.Make(10, 10, 30, 20);
  Area := TRectI.Make(5, 5, 100, 50);
  AbsB := QuickViewInteriorAbsBounds(Bounds, Area);
  Assert.IsTrue((AbsB.Left = 16) and (AbsB.Top = 16) and (AbsB.Right = 34) and
    (AbsB.Bottom = 24), 'QV interior is window-absolute inset');

  Spy := TPanelSpy.Create;
  try
    Host := Default(TDualPanelPanelHost);
    Host.DrawInfo := Spy.Info;
    Host.DrawQuickView := Spy.QuickView;
    Host.DrawDriveLetters := Spy.DriveLetters;
    Host.DrawFiles := Spy.Files;
    Snap := Default(TDrawPanelSnapshot);
    Snap.ViewKind := pvkInfo;
    DispatchDrawPanelBody(Host, Snap);
    Assert.IsTrue(Spy.Last = 'info,drive,', 'info then drive letters');
    Snap.ViewKind := pvkQuickView;
    Snap.IsQuickViewTarget := True;
    Spy.Last := '';
    DispatchDrawPanelBody(Host, Snap);
    Assert.IsTrue(Spy.Last = 'qv,', 'quick view has no drive bar');
    Snap.ViewKind := pvkFiles;
    Snap.IsQuickViewTarget := False;
    Spy.Last := '';
    DispatchDrawPanelBody(Host, Snap);
    Assert.IsTrue(Spy.Last = 'files,', 'files body');

    Spy.Last := '';
    DispatchPanelSearchFields(Bounds, psLeft, psRight, True, True,
      Spy.QuickSearch, Spy.Filter);
    Assert.IsTrue(Spy.Last = '', 'search fields only on active side');
    DispatchPanelSearchFields(Bounds, psLeft, psLeft, True, True,
      Spy.QuickSearch, Spy.Filter);
    Assert.IsTrue(Spy.Last = 'quick,filter,', 'quick search then filter');

    AllocTerminalGrid(Grid, 20, 8);
    ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
    Panel := Default(TPanelState);
    Panel.ViewKind := pvkInfo;
    Bounds := TRectI.Make(0, 0, 19, 7);
    DrawPanelShell(Grid, nil, Bounds, Panel, True, False,
      TAlphaColors.Yellow, TAlphaColors.Blue, TAlphaColors.White, -1,
      Spy.ResolveChrome);
    Assert.IsTrue(Grid[0][0].CharValue = chDblTL, 'active shell uses double frame');
    Assert.IsTrue(Grid[0][CenteredTextCol(Bounds, ' Information ') + 1].CharValue = 'I',
      'info title on shell');
    Assert.IsTrue(Grid[0][1].CharValue = chDblH, 'info panel keeps frame, no sort letter');

    Panel := Default(TPanelState);
    Panel.ViewKind := pvkFiles;
    Panel.SortColumn := pscName;
    SetLength(Panel.Tabs, 1);
    Panel.Tabs[0].CurrentURI := 'file:///C:/Work';
    ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
    DrawPanelShell(Grid, nil, Bounds, Panel, True, False,
      TAlphaColors.Yellow, TAlphaColors.Blue, TAlphaColors.White, -1,
      Spy.ResolveChrome);
    Assert.IsTrue(Grid[0][0].CharValue = chDblTL, 'files shell keeps corner');
    Assert.IsTrue(Grid[0][1].CharValue = '[', 'tabs start on the top border');
  finally
    Spy.Free;
  end;
end;

procedure TestDrawPanelFilesDispatch;
var
  Spy: TFilesSpy;
  Host: TDualPanelFilesDrawHost;
  Snap: TDrawFilesSnapshot;
  Grid: TTerminalGrid;
begin
  Spy := TFilesSpy.Create;
  try
    Host := Default(TDualPanelFilesDrawHost);
    Host.ResolveChrome := Spy.ResolveChrome;
    Host.DrawDriveLetters := Spy.DriveLetters;
    Host.DrawHeaders := Spy.Headers;
    Host.DrawList := Spy.List;
    Host.DrawScrollBar := Spy.Scroll;
    Host.DrawQuickSearch := Spy.Quick;
    Host.DrawFilter := Spy.Filter;

    AllocTerminalGrid(Grid, 20, 8);
    ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
    Snap := Default(TDrawFilesSnapshot);
    Snap.Bounds := TRectI.Make(0, 0, 19, 7);
    Snap.ListBounds := TRectI.Make(1, 3, 18, 5);
    Snap.Side := psRight;
    Snap.ActiveSide := psLeft;
    Snap.Active := True;
    Snap.Frame := TAlphaColors.Yellow;
    Snap.BodyBg := TAlphaColors.Blue;
    Snap.DropFg := TAlphaColors.White;
    Snap.DropBg := TAlphaColors.Red;
    Snap.Count := 10;
    Snap.PageSize := 4;
    Snap.Tab.ScrollOffset := 2;
    Snap.DropHighlight := True;
    Snap.QuickSearch := True;
    Snap.Filter := True;
    Snap.Panel.SortColumn := pscName;
    Snap.Panel.SortDescending := False;
    DispatchDrawPanelFiles(Grid, nil, Host, Snap);
    Assert.IsTrue(Spy.Last = 'drive,headers,list,scroll,',
      'drive+headers+list+scroll; search only on active side');
    Assert.IsTrue(Spy.ListSide = psRight, 'list uses snapshot side');
    Assert.IsTrue(Spy.ScrollX = 18, 'scrollbar on right edge');
    Assert.IsTrue(Spy.ScrollViewH = 4, 'scrollbar page size');
    Assert.IsTrue(Grid[0][3].CharValue = 'D', 'drop highlight badge');
    Assert.IsTrue(Grid[PanelSortLetterRow(Snap.Bounds)][PanelSortLetterCol(Snap.Bounds)].CharValue = 'n',
      'sort letter is in work-area top-left');
    Assert.IsTrue(Grid[0][1].CharValue <> 'n', 'sort letter is not on the frame');
    Assert.IsTrue(Grid[PanelSortLetterRow(Snap.Bounds)][PanelSortLetterCol(Snap.Bounds)].FgColor <>
      Grid[PanelSortLetterRow(Snap.Bounds)][PanelSortLetterCol(Snap.Bounds)].BgColor,
      'sort letter contrasts with header background');

    Snap.Panel.SortColumn := pscModified;
    Snap.Panel.SortDescending := True;
    DispatchDrawPanelFiles(Grid, nil, Host, Snap);
    Assert.IsTrue(Grid[PanelSortLetterRow(Snap.Bounds)][PanelSortLetterCol(Snap.Bounds)].CharValue = 'W',
      'descending write-time is W in the work area');

    Spy.Last := '';
    Snap.ActiveSide := psRight;
    Snap.DropHighlight := False;
    DispatchDrawPanelFiles(Grid, nil, Host, Snap);
    Assert.IsTrue(Spy.Last = 'drive,headers,list,scroll,quick,filter,',
      'search fields on active side');
  finally
    Spy.Free;
  end;
end;

procedure TestPanelLayout;
var
  LeftB, RightB: TRectI;
  ListTop, ListBottom: Integer;
begin
  ComputePanelLayout(80, 24, True, True, LeftB, RightB, ListTop, ListBottom);
  Assert.IsTrue(LeftB.Left = 0, 'left starts at 0');
  Assert.IsTrue(LeftB.Right = 39, 'left ends at width/2-1');
  Assert.IsTrue(RightB.Left = 40, 'right abuts left');
  Assert.IsTrue(RightB.Right = 79, 'right ends at width-1');
  Assert.IsTrue(LeftB.Top = 2, 'panels start below tabs');
  Assert.IsTrue(ListTop = 4, 'list below title+tabs');
  ComputePanelLayout(80, 24, True, False, LeftB, RightB, ListTop, ListBottom);
  Assert.IsTrue(LeftB.Right = 79, 'solo left is full width');
  Assert.IsTrue(RightB.Left = -1, 'hidden right is sentinel');
  ComputePanelLayout(80, 24, False, False, LeftB, RightB, ListTop, ListBottom);
  Assert.IsTrue((LeftB.Left = 0) and (RightB.Left = 40), 'neither visible still splits both');
end;

procedure TestTabCloseMarkContrast;
const
  cPink = TAlphaColor($FFFF79C6);
  cPurple = TAlphaColor($FFBD93F9);
  cDark = TAlphaColor($FF282A36);
var
  Spy: TCloseChromeSpy;
  Grid: TTerminalGrid;
  Panel: TPanelState;
  Bounds: TRectI;
  X, Found: Integer;
  Cell: TCharCell;
begin
  Assert.IsTrue(ContrastingGlyphFg(cPurple, cPink, cDark) = cDark,
    'pink on purple falls back to tab text');
  Assert.IsTrue(ContrastingGlyphFg(cPurple, cPurple, cDark) = cDark,
    'identical fg/bg falls back to tab text');

  Spy := TCloseChromeSpy.Create;
  try
    AllocTerminalGrid(Grid, 40, 3);
    ClearTerminalGrid(Grid, TAlphaColors.White, TAlphaColors.Black, ' ');
    Panel := Default(TPanelState);
    SetLength(Panel.Tabs, 2);
    Panel.Tabs[0].CurrentURI := 'file:///C:/Left';
    Panel.Tabs[1].CurrentURI := 'file:///C:/Right';
    Panel.ActiveTabIndex := 0;
    Bounds := TRectI.Make(0, 0, 39, 2);
    DrawPanelEmbeddedTabs(Grid, Bounds, Panel, True, ' ',
      TAlphaColors.Yellow, TAlphaColors.Blue, -1, Spy.ResolveChrome);
    Assert.IsTrue(Grid[0][1].CharValue = '[', 'first tab after left frame');
    Found := 0;
    for X := 0 to High(Grid[0]) do
      if Grid[0][X].CharValue = 'x' then
      begin
        Inc(Found);
        Cell := Grid[0][X];
        Assert.IsTrue(Cell.FgColor <> Cell.BgColor, 'close x differs from its tab bg');
        if Cell.BgColor = cPurple then
          Assert.IsTrue(Cell.FgColor <> cPink, 'active tab close is not pink-on-purple');
      end;
    Assert.IsTrue(Found >= 2, 'both tabs paint a close x');
  finally
    Spy.Free;
  end;
end;

{ TTestDualPanelPanelDraw }

procedure TTestDualPanelPanelDraw.TestCaptionsAndFooters;
begin
  TestDualPanelPanelDraw.TestCaptionsAndFooters;
end;

procedure TTestDualPanelPanelDraw.TestSeparatorAndTitle;
begin
  TestDualPanelPanelDraw.TestSeparatorAndTitle;
end;

procedure TTestDualPanelPanelDraw.TestDriveLetterHit;
begin
  TestDualPanelPanelDraw.TestDriveLetterHit;
end;

procedure TTestDualPanelPanelDraw.TestDrivePreviewHelpers;
begin
  TestDualPanelPanelDraw.TestDrivePreviewHelpers;
end;

procedure TTestDualPanelPanelDraw.TestDriveBarDraw;
begin
  TestDualPanelPanelDraw.TestDriveBarDraw;
end;

procedure TTestDualPanelPanelDraw.TestDrawPanelHelpers;
begin
  TestDualPanelPanelDraw.TestDrawPanelHelpers;
end;

procedure TTestDualPanelPanelDraw.TestDrawContentDispatch;
begin
  TestDualPanelPanelDraw.TestDrawContentDispatch;
end;

procedure TTestDualPanelPanelDraw.TestListRowHelpers;
begin
  TestDualPanelPanelDraw.TestListRowHelpers;
end;

procedure TTestDualPanelPanelDraw.TestDrawPanelDispatch;
begin
  TestDualPanelPanelDraw.TestDrawPanelDispatch;
end;

procedure TTestDualPanelPanelDraw.TestDrawPanelFilesDispatch;
begin
  TestDualPanelPanelDraw.TestDrawPanelFilesDispatch;
end;

procedure TTestDualPanelPanelDraw.TestPanelLayout;
begin
  TestDualPanelPanelDraw.TestPanelLayout;
end;

procedure TTestDualPanelPanelDraw.TestTabCloseMarkContrast;
begin
  TestDualPanelPanelDraw.TestTabCloseMarkContrast;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelPanelDraw);

end.
