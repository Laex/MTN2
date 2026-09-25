unit uNordTheme;

{ Stage 27: the canonical Nord palette (nordtheme.com) applied to
  IThemeRenderer — cold "polar night" backgrounds, "snow storm" body text,
  "frost" accent hues for chrome/focus, "aurora" hues for file-type colour
  coding. Single-line unicode box-drawing everywhere, like
  uModernUnicodeTheme, and the same 3-cell '[x]' close button geometry every
  theme keeps. }

interface

uses
  System.UITypes, System.SysUtils, System.Math,
  uTerminalTypes, uThemeTypes;

type
  TNordTheme = class(TInterfacedObject, IThemeRenderer)
  public
    function DesktopColor: TAlphaColor;
    procedure DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
    procedure DrawWindowFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; AState: TThemeWidgetState);
    procedure DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; AState: TThemeWidgetState);
    procedure DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AState: TThemeWidgetState);
    procedure DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
    procedure DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
    procedure DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
    procedure DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATabNames: TArray<string>; AActiveTabIndex: Integer;
      AState: TThemeWidgetState; AKind: TTabBarKind = tbkPanel);
    procedure DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AItems: TArray<string>; AState: TThemeWidgetState);
    procedure DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ASegments: TArray<string>; AState: TThemeWidgetState);
    procedure DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AMenuText, AClockText: string; AState: TThemeWidgetState);
    procedure DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      AActive: Boolean; AState: TThemeWidgetState);
    function UsesDoubleLineForActivePanel: Boolean;
    procedure ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
      const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
    procedure ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveMarkdownStyleColors(AKind: TMdSpanKind;
      out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
    procedure ResolveEditorColors(out AColors: TEditorThemeColors);
  end;

implementation

const
  // Nord — https://www.nordtheme.com/docs/colors-and-palettes
  cNord0  = TAlphaColor($FF2E3440); // polar night, darkest
  cNord1  = TAlphaColor($FF3B4252);
  cNord2  = TAlphaColor($FF434C5E);
  cNord3  = TAlphaColor($FF4C566A); // comments
  cNord4  = TAlphaColor($FFD8DEE9); // snow storm, body text
  cNord5  = TAlphaColor($FFE5E9F0);
  cNord6  = TAlphaColor($FFECEFF4); // snow storm, brightest
  cNord7  = TAlphaColor($FF8FBCBB); // frost teal
  cNord8  = TAlphaColor($FF88C0D0); // frost cyan — primary accent
  cNord9  = TAlphaColor($FF81A1C1); // frost blue
  cNord10 = TAlphaColor($FF5E81AC); // frost dark blue
  cNord11 = TAlphaColor($FFBF616A); // aurora red
  cNord12 = TAlphaColor($FFD08770); // aurora orange
  cNord13 = TAlphaColor($FFEBCB8B); // aurora yellow
  cNord14 = TAlphaColor($FFA3BE8C); // aurora green
  cNord15 = TAlphaColor($FFB48EAD); // aurora purple

  cDesktopBg    = cNord0;
  cWindowBg     = cNord0;
  cText         = cNord4;
  cDialogBg     = cNord1;
  cDialogFg     = cNord6;
  cDialogBorder = cNord8;
  cDirFg        = cNord9;
  cBorderFocus  = cNord8;
  cBorderNormal = cNord3;
  cTitleFgFocus = cNord0;
  cTitleBgFocus = cNord8;
  cTitleFgNormal= cNord3;
  cTitleBgNormal= cNord1;
  cBtnFg        = cNord4;
  cBtnBg        = cNord2;
  cBtnFgFocus   = cNord0;
  cBtnBgFocus   = cNord8;
  cStatusFg     = cNord6;
  cStatusBg     = cNord1;
  cToolFg       = cNord4;
  cToolBg       = cNord1;
  cToolKeyFg    = cNord8;
  cTabActiveFg  = cNord0;
  cTabActiveBg  = cNord8;
  cTabNormalFg  = cNord3;
  cTabNormalBg  = cNord1;
  cScrollFg     = cNord3;
  cScrollThumb  = cNord8;
  cSelectedFg   = cNord13;
  cSelectedBg   = cWindowBg;
  cCursorFg     = cNord0;
  cCursorBg     = cNord8;
  cCursorIdleBg = TAlphaColor($FF34394A);
  cCloseAccent  = cNord11;

function TNordTheme.DesktopColor: TAlphaColor;
begin
  Result := cDesktopBg;
end;

procedure TNordTheme.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cText, cDesktopBg);
end;

procedure TNordTheme.DrawWindowFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; AState: TThemeWidgetState);
var
  X, Y, W: Integer;
  Border, TitleBg, TitleFg: TAlphaColor;
  Focused: Boolean;
  Cap: string;
  StartX: Integer;
  Btns: string;
  BtnX: Integer;
begin
  W := ABounds.Width;
  if (W < 2) or (ABounds.Height < 2) then
    Exit;
  Focused := twFocused in AState;
  if Focused then
  begin
    Border := cBorderFocus;
    TitleBg := cTitleBgFocus;
    TitleFg := cTitleFgFocus;
  end
  else
  begin
    Border := cBorderNormal;
    TitleBg := cTitleBgNormal;
    TitleFg := cTitleFgNormal;
  end;

  FillGridRect(AGrid, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', cText, cWindowBg);

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chBoxTL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chBoxTR, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chBoxBL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chBoxBR, Border, cWindowBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chBoxH, Border, cWindowBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chBoxH, Border, cWindowBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chBoxV, Border, cWindowBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chBoxV, Border, cWindowBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, Border, cWindowBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cCloseAccent, cWindowBg);
  end;

  if ATitle <> '' then
  begin
    Cap := ' ' + ATitle + ' ';
    if BtnX < ABounds.Right then
    begin
      if Length(Cap) > BtnX - (ABounds.Left + 1) then
        Cap := Copy(Cap, 1, Max(BtnX - (ABounds.Left + 1), 1));
    end
    else if Length(Cap) > W - 2 then
      Cap := Copy(Cap, 1, Max(W - 2, 1));
    StartX := ABounds.Left + (W - Length(Cap)) div 2;
    if StartX < ABounds.Left + 1 then
      StartX := ABounds.Left + 1;
    if (BtnX < ABounds.Right) and (StartX + Length(Cap) > BtnX) then
      StartX := Max(ABounds.Left + 1, BtnX - Length(Cap));
    PutGridText(AGrid, StartX, ABounds.Top, Cap, TitleFg, TitleBg);
  end;
end;

procedure TNordTheme.DrawDialogFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; AState: TThemeWidgetState);
var
  X, Y, W: Integer;
  Cap: string;
  StartX: Integer;
  Btns: string;
  BtnX: Integer;
begin
  W := ABounds.Width;
  if (W < 2) or (ABounds.Height < 2) then
    Exit;

  FillGridRect(AGrid, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', cDialogFg, cDialogBg);

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chBoxTL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chBoxTR, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chBoxBL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chBoxBR, cDialogBorder, cDialogBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chBoxH, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chBoxH, cDialogBorder, cDialogBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chBoxV, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chBoxV, cDialogBorder, cDialogBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cCloseAccent, cDialogBg);
  end;

  if ATitle <> '' then
  begin
    Cap := ' ' + ATitle + ' ';
    if BtnX < ABounds.Right then
    begin
      if Length(Cap) > BtnX - (ABounds.Left + 1) then
        Cap := Copy(Cap, 1, Max(BtnX - (ABounds.Left + 1), 1));
    end
    else if Length(Cap) > W - 2 then
      Cap := Copy(Cap, 1, Max(W - 2, 1));
    StartX := ABounds.Left + (W - Length(Cap)) div 2;
    if StartX < ABounds.Left + 1 then
      StartX := ABounds.Left + 1;
    if (BtnX < ABounds.Right) and (StartX + Length(Cap) > BtnX) then
      StartX := Max(ABounds.Left + 1, BtnX - Length(Cap));
    PutGridText(AGrid, StartX, ABounds.Top, Cap, cTitleFgFocus, cTitleBgFocus);
  end;
end;

procedure TNordTheme.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AState: TThemeWidgetState);
var
  Fg, Bg: TAlphaColor;
  Cap: string;
  StartX: Integer;
begin
  if twFocused in AState then
  begin
    Fg := cBtnFgFocus;
    Bg := cBtnBgFocus;
  end
  else
  begin
    Fg := cBtnFg;
    Bg := cBtnBg;
  end;
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', Fg, Bg);
  if twSelected in AState then
    Cap := '< ' + AText + ' >'
  else
    Cap := '[ ' + AText + ' ]';
  StartX := ABounds.Left + (ABounds.Width - Length(Cap)) div 2;
  if StartX < ABounds.Left then
    StartX := ABounds.Left;
  PutGridTextClipped(AGrid, StartX, ABounds.Top, ABounds.Right, Cap, Fg, Bg, [ccaBold]);
end;

procedure TNordTheme.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
var
  Fg, Bg: TAlphaColor;
  Mark: string;
begin
  if twFocused in AState then
  begin
    Fg := cCursorFg;
    Bg := cCursorBg;
  end
  else
  begin
    Fg := cDialogFg;
    Bg := cDialogBg;
  end;
  if AChecked then
    Mark := '[x] '
  else
    Mark := '[ ] ';
  PutGridText(AGrid, ABounds.Left, ABounds.Top, Mark + AText, Fg, Bg);
end;

procedure TNordTheme.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
var
  Fg, Bg: TAlphaColor;
  Mark: string;
begin
  if twFocused in AState then
  begin
    Fg := cCursorFg;
    Bg := cCursorBg;
  end
  else
  begin
    Fg := cDialogFg;
    Bg := cDialogBg;
  end;
  if AChecked then
    Mark := '(*) '
  else
    Mark := '( ) ';
  PutGridText(AGrid, ABounds.Left, ABounds.Top, Mark + AText, Fg, Bg);
end;

procedure TNordTheme.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
var
  I, Span, ThumbAt: Integer;
begin
  if AVertical then
  begin
    Span := ABounds.Height;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, #$25B2, cScrollFg, cWindowBg);
    DrawGridChar(AGrid, ABounds.Left, ABounds.Bottom, #$25BC, cScrollFg, cWindowBg);
    for I := ABounds.Top + 1 to ABounds.Bottom - 1 do
      DrawGridChar(AGrid, ABounds.Left, I, chShadeLight, cScrollFg, cWindowBg);
    ThumbAt := ABounds.Top + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ABounds.Left, ThumbAt, chBlock, cScrollThumb, cWindowBg);
  end
  else
  begin
    Span := ABounds.Width;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, #$25C4, cScrollFg, cWindowBg);
    DrawGridChar(AGrid, ABounds.Right, ABounds.Top, #$25BA, cScrollFg, cWindowBg);
    for I := ABounds.Left + 1 to ABounds.Right - 1 do
      DrawGridChar(AGrid, I, ABounds.Top, chShadeLight, cScrollFg, cWindowBg);
    ThumbAt := ABounds.Left + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ThumbAt, ABounds.Top, chBlock, cScrollThumb, cWindowBg);
  end;
end;

procedure TNordTheme.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATabNames: TArray<string>; AActiveTabIndex: Integer;
  AState: TThemeWidgetState; AKind: TTabBarKind);
var
  I, X: Integer;
  Cap: string;
  Fg, Bg, BarBg, ActiveBg, ActiveFg, NormalFg: TAlphaColor;
begin
  if AKind = tbkWorkspace then
  begin
    BarBg := cTabNormalBg;
    ActiveBg := cTabActiveBg;
    ActiveFg := cTabActiveFg;
    NormalFg := cTabNormalFg;
  end
  else
  begin
    BarBg := cWindowBg;
    ActiveBg := cNord8;
    ActiveFg := cNord0;
    NormalFg := cNord3;
  end;

  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', NormalFg, BarBg);
  X := ABounds.Left;
  for I := 0 to High(ATabNames) do
  begin
    if AKind = tbkWorkspace then
      Cap := '[' + ATabNames[I] + ']'
    else
      Cap := ' ' + ATabNames[I] + ' ';
    if I = AActiveTabIndex then
    begin
      Fg := ActiveFg;
      Bg := ActiveBg;
    end
    else
    begin
      Fg := NormalFg;
      Bg := BarBg;
    end;
    if X > ABounds.Right then
      Break;
    PutGridText(AGrid, X, ABounds.Top, Cap, Fg, Bg);
    Inc(X, Length(Cap) + 1);
  end;
end;

procedure TNordTheme.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AItems: TArray<string>; AState: TThemeWidgetState);
var
  I, X, KeyLen: Integer;
  Item, KeyPart: string;
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cToolFg, cToolBg);
  X := ABounds.Left;
  for I := 0 to High(AItems) do
  begin
    Item := AItems[I];
    if X > ABounds.Right then
      Break;
    KeyLen := 0;
    while (KeyLen < Length(Item)) and CharInSet(Item[KeyLen + 1], ['0'..'9']) do
      Inc(KeyLen);
    if KeyLen > 0 then
    begin
      KeyPart := Copy(Item, 1, KeyLen);
      PutGridText(AGrid, X, ABounds.Top, KeyPart, cToolKeyFg, cToolBg, [ccaBold]);
      PutGridText(AGrid, X + KeyLen, ABounds.Top, Copy(Item, KeyLen + 1, MaxInt),
        cToolFg, cToolBg);
    end
    else
      PutGridText(AGrid, X, ABounds.Top, Item, cToolFg, cToolBg);
    Inc(X, Length(Item) + 1);
  end;
end;

procedure TNordTheme.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ASegments: TArray<string>; AState: TThemeWidgetState);
var
  I, X: Integer;
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cStatusFg, cStatusBg);
  X := ABounds.Left + 1;
  for I := 0 to High(ASegments) do
  begin
    if X > ABounds.Right then
      Break;
    PutGridText(AGrid, X, ABounds.Top, ASegments[I], cStatusFg, cStatusBg);
    Inc(X, Length(ASegments[I]));
    if I < High(ASegments) then
    begin
      DrawGridChar(AGrid, X + 1, ABounds.Top, chBoxV, cScrollFg, cStatusBg);
      Inc(X, 3);
    end;
  end;
end;

procedure TNordTheme.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AMenuText, AClockText: string; AState: TThemeWidgetState);
var
  ClockX, HotLen: Integer;
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cStatusFg, cStatusBg);
  if AMenuText <> '' then
  begin
    PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, AMenuText, cStatusFg, cStatusBg);
    HotLen := 1;
    if Length(AMenuText) >= HotLen then
      PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, Copy(AMenuText, 1, HotLen),
        cToolKeyFg, cStatusBg, [ccaBold]);
  end;
  if AClockText <> '' then
  begin
    ClockX := ABounds.Right - Length(AClockText);
    if ClockX < ABounds.Left + 30 then
      ClockX := ABounds.Left + 30;
    if ClockX <= ABounds.Right then
      PutGridText(AGrid, ClockX, ABounds.Top, AClockText, cStatusFg, cStatusBg);
  end;
end;

procedure TNordTheme.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState);
var
  Frame: TAlphaColor;
begin
  if AActive then
    Frame := cBorderFocus
  else
    Frame := cBorderNormal;
  DrawPanelFrameGlyphs(AGrid, ABounds, chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV,
    Frame, cText, cWindowBg);
end;

function TNordTheme.UsesDoubleLineForActivePanel: Boolean;
begin
  Result := False;
end;

procedure TNordTheme.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor);

  function TypeFg: TAlphaColor;
  begin
    if AIsDirectory or AIsParent or SameText(AFileType, 'directory') then
      Result := cDirFg
    else if SameText(AFileType, 'archive') then
      Result := cNord12
    else if SameText(AFileType, 'executable') then
      Result := cNord14
    else if SameText(AFileType, 'media') then
      Result := cNord15
    else
      Result := cText;
    if AIsHidden and not AIsParent then
      Result := cNord3;
  end;

begin
  if ACursor then
  begin
    if ASelected then
    begin
      AFg := cCursorFg;
      ABg := cNord13;
    end
    else if ASideActive then
    begin
      AFg := cCursorFg;
      ABg := cCursorBg;
    end
    else
    begin
      ABg := cCursorIdleBg;
      AFg := TypeFg;
    end;
  end
  else if ASelected then
  begin
    AFg := cSelectedFg;
    ABg := cSelectedBg;
  end
  else
  begin
    ABg := cWindowBg;
    AFg := TypeFg;
  end;
end;

procedure TNordTheme.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
begin
  if ACursor then
  begin
    AFg := cCursorFg;
    ABg := cCursorBg;
  end
  else
  begin
    AFg := cDialogFg;
    ABg := cDialogBg;
  end;
end;

procedure TNordTheme.ResolvePanelChromeColors(APart: TPanelChromePart;
  AActive: Boolean; out AFg, ABg: TAlphaColor);
var
  Pal: TPanelChromePalette;
begin
  Pal.TextFg := cText;
  Pal.WindowBg := cWindowBg;
  Pal.HeaderFg := cNord8;
  Pal.HeaderBg := cWindowBg;
  Pal.PanelTabActiveFg := cNord0;
  Pal.PanelTabActiveBg := cNord8;
  Pal.BorderFocusFg := cBorderFocus;
  Pal.BorderNormalFg := cBorderNormal;
  Pal.WorkspaceTabActiveFg := cTabActiveFg;
  Pal.WorkspaceTabActiveBg := cTabActiveBg;
  Pal.WorkspaceTabIdleFg := cTabNormalFg;
  Pal.WorkspaceTabIdleBg := cTabNormalBg;
  Pal.HotMarkFg := cToolKeyFg;
  Pal.CloseMarkFg := cCloseAccent;
  ResolveStandardPanelChromeColors(APart, AActive, Pal, AFg, ABg);
end;

procedure TNordTheme.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  AAttr := [];
  ABg := cWindowBg;
  case AKind of
    mskH1: begin AFg := cNord8; AAttr := [ccaBold]; end;
    mskH2: begin AFg := cNord13; AAttr := [ccaBold]; end;
    mskH3to6: begin AFg := cNord14; AAttr := [ccaBold]; end;
    mskBold: begin AFg := cNord6; AAttr := [ccaBold]; end;
    mskItalic: AFg := cNord15;
    mskBoldItalic: begin AFg := cNord15; AAttr := [ccaBold]; end;
    mskStrike: AFg := cNord3;
    mskInlineCode: begin AFg := cNord14; ABg := cNord1; end;
    mskCodeBlock: begin AFg := cNord4; ABg := cNord1; end;
    mskQuote: AFg := cNord3;
    mskListMarker: begin AFg := cNord13; AAttr := [ccaBold]; end;
    mskHRule: AFg := cNord3;
    mskLink: AFg := cNord8;
    mskImageMarker: AFg := cNord3;
    mskTableBorder: AFg := cNord3;
    mskTableHeader: begin AFg := cNord13; AAttr := [ccaBold]; end;
  else
    AFg := cText;
  end;
end;

procedure TNordTheme.ResolveEditorColors(out AColors: TEditorThemeColors);
begin
  AColors.BodyFg := cText;
  AColors.BodyBg := cWindowBg;
  AColors.CursorFg := cCursorFg;
  AColors.CursorBg := cCursorBg;
  AColors.SelFg := cCursorFg;
  AColors.SelBg := cCursorBg;
  AColors.HintFg := cToolKeyFg;
  AColors.StatusFg := cStatusFg;
  AColors.StatusBg := cStatusBg;
  AColors.FrameFocus := cBorderFocus;
  AColors.FrameIdle := cBorderNormal;
  AColors.ScrollFg := cScrollFg;
  AColors.ScrollThumb := cScrollThumb;
  AColors.MatchFg := cCursorFg;
  AColors.MatchBg := cCursorBg;
end;

end.
