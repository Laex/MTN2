unit uASCIITheme;

{ Stage 27, optional third look: same classic FAR/VGA palette as uNDNTheme,
  but every glyph is plain 7-bit ASCII (+/-/|, ^v&lt;&gt;, #, :) instead of
  Unicode box-drawing/block characters — for terminals or fonts that don't
  carry the box-drawing block. Colours intentionally match uNDNTheme so
  switching between the two is a pure glyph change, not a repaint you'd
  mistake for a different theme. }

interface

uses
  System.UITypes, System.SysUtils, System.Math,
  uTerminalTypes, uThemeTypes;

type
  TASCIIOnlyTheme = class(TInterfacedObject, IThemeRenderer)
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
  // Same VGA approximations as uNDNTheme — only the glyphs differ.
  cBlack        = TAlphaColor($FF000000);
  cBlue         = TAlphaColor($FF0000AA);
  cCyan         = TAlphaColor($FF00AAAA);
  cDarkCyan     = TAlphaColor($FF008888);
  cLightGray    = TAlphaColor($FFAAAAAA);
  cHiddenFg     = TAlphaColor($FF888888);
  cWhite        = TAlphaColor($FFFFFFFF);
  cYellow       = TAlphaColor($FFFFFF55);
  cLightCyan    = TAlphaColor($FF55FFFF);
  cGreen        = TAlphaColor($FF00AA00);
  cLightGreen   = TAlphaColor($FF55FF55);
  cLightMagenta = TAlphaColor($FFFF55FF);

  cDesktopBg    = cBlack;
  cWindowBg     = cBlue;
  cText         = cLightGray;
  cDialogBg     = cWhite;
  cDialogFg     = cBlack;
  cDialogBorder = cBlack;
  cDirFg        = cWhite;
  cBorderFocus  = cLightCyan;
  cBorderNormal = cLightGray;
  cTitleFg      = cBlack;
  cTitleBgFocus = cCyan;
  cTitleBgNormal= cLightGray;
  cBtnFg        = cBlack;
  cBtnBg        = cCyan;
  cBtnFgFocus   = cBlack;
  cBtnBgFocus   = cLightCyan;
  cStatusFg     = cBlack;
  cStatusBg     = cCyan;
  cToolFg       = cLightGray;
  cToolBg       = cWindowBg;
  cToolKeyFg    = cYellow;
  cTabActiveFg  = cBlack;
  cTabActiveBg  = cCyan;
  cTabNormalFg  = cLightGray;
  cTabNormalBg  = cBlack;
  cScrollFg     = cLightGray;
  cScrollThumb  = cCyan;
  cSelectedFg   = cYellow;
  cSelectedBg   = cBlue;
  cCursorFg     = cBlack;
  cCursorBg     = cCyan;
  cCursorIdleBg = TAlphaColor($FF1A3A6A);

  // ASCII-only box/shade glyphs (vs. Unicode chBox*/chDbl*/chShade*/chBlock).
  chAH  = '-';
  chAV  = '|';
  chATL = '+';
  chATR = '+';
  chABL = '+';
  chABR = '+';
  chAShade = ':';
  chABlock = '#';
  chAUp    = '^';
  chADown  = 'v';
  chALeft  = '<';
  chARight = '>';

function TASCIIOnlyTheme.DesktopColor: TAlphaColor;
begin
  Result := cDesktopBg;
end;

procedure TASCIIOnlyTheme.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cText, cDesktopBg);
end;

procedure TASCIIOnlyTheme.DrawWindowFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; AState: TThemeWidgetState);
var
  X, Y, W: Integer;
  Border, TitleBg: TAlphaColor;
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
  end
  else
  begin
    Border := cBorderNormal;
    TitleBg := cTitleBgNormal;
  end;

  FillGridRect(AGrid, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', cText, cWindowBg);

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chATL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chATR, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chABL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chABR, Border, cWindowBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chAH, Border, cWindowBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chAH, Border, cWindowBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chAV, Border, cWindowBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chAV, Border, cWindowBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, Border, cWindowBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cLightMagenta, cWindowBg);
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
    PutGridText(AGrid, StartX, ABounds.Top, Cap, cTitleFg, TitleBg);
  end;
end;

procedure TASCIIOnlyTheme.DrawDialogFrame(const AGrid: TTerminalGrid;
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

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chATL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chATR, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chABL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chABR, cDialogBorder, cDialogBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chAH, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chAH, cDialogBorder, cDialogBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chAV, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chAV, cDialogBorder, cDialogBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cLightMagenta, cDialogBg);
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
    PutGridText(AGrid, StartX, ABounds.Top, Cap, cTitleFg, cTitleBgFocus);
  end;
end;

procedure TASCIIOnlyTheme.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure TASCIIOnlyTheme.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure TASCIIOnlyTheme.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure TASCIIOnlyTheme.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
var
  I, Span, ThumbAt: Integer;
begin
  if AVertical then
  begin
    Span := ABounds.Height;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, chAUp, cScrollFg, cWindowBg);
    DrawGridChar(AGrid, ABounds.Left, ABounds.Bottom, chADown, cScrollFg, cWindowBg);
    for I := ABounds.Top + 1 to ABounds.Bottom - 1 do
      DrawGridChar(AGrid, ABounds.Left, I, chAShade, cScrollFg, cWindowBg);
    ThumbAt := ABounds.Top + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ABounds.Left, ThumbAt, chABlock, cScrollThumb, cWindowBg);
  end
  else
  begin
    Span := ABounds.Width;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, chALeft, cScrollFg, cWindowBg);
    DrawGridChar(AGrid, ABounds.Right, ABounds.Top, chARight, cScrollFg, cWindowBg);
    for I := ABounds.Left + 1 to ABounds.Right - 1 do
      DrawGridChar(AGrid, I, ABounds.Top, chAShade, cScrollFg, cWindowBg);
    ThumbAt := ABounds.Left + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ThumbAt, ABounds.Top, chABlock, cScrollThumb, cWindowBg);
  end;
end;

procedure TASCIIOnlyTheme.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
    BarBg := cBlue;
    ActiveBg := cCyan;
    ActiveFg := cBlack;
    NormalFg := cLightGray;
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

procedure TASCIIOnlyTheme.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure TASCIIOnlyTheme.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
      DrawGridChar(AGrid, X + 1, ABounds.Top, chAV, cStatusFg, cStatusBg);
      Inc(X, 3);
    end;
  end;
end;

procedure TASCIIOnlyTheme.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure TASCIIOnlyTheme.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState);
var
  Frame: TAlphaColor;
begin
  if AActive then
    Frame := cBorderFocus
  else
    Frame := cBorderNormal;
  DrawPanelFrameGlyphs(AGrid, ABounds, chATL, chATR, chABL, chABR, chAH, chAV,
    Frame, cText, cWindowBg);
end;

function TASCIIOnlyTheme.UsesDoubleLineForActivePanel: Boolean;
begin
  // ASCII has only one glyph weight — active/idle differ by colour only.
  Result := False;
end;

procedure TASCIIOnlyTheme.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor);

  function TypeFg: TAlphaColor;
  begin
    if AIsDirectory or AIsParent or SameText(AFileType, 'directory') then
      Result := cDirFg
    else if SameText(AFileType, 'archive') then
      Result := cGreen
    else if SameText(AFileType, 'executable') then
      Result := cLightGreen
    else if SameText(AFileType, 'media') then
      Result := cLightMagenta
    else
      Result := cText;
    if AIsHidden and not AIsParent then
    begin
      if AIsDirectory or AIsParent or SameText(AFileType, 'directory') then
        Result := cLightGray
      else if SameText(AFileType, 'archive') then
        Result := cDarkCyan
      else if SameText(AFileType, 'executable') then
        Result := cGreen
      else if SameText(AFileType, 'media') then
        Result := TAlphaColor($FFAA55AA)
      else
        Result := cHiddenFg;
    end;
  end;

begin
  if ACursor then
  begin
    if ASelected then
    begin
      AFg := cCursorFg;
      ABg := cYellow;
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

procedure TASCIIOnlyTheme.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
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

procedure TASCIIOnlyTheme.ResolvePanelChromeColors(APart: TPanelChromePart;
  AActive: Boolean; out AFg, ABg: TAlphaColor);
var
  Pal: TPanelChromePalette;
begin
  Pal.TextFg := cText;
  Pal.WindowBg := cWindowBg;
  Pal.HeaderFg := cLightCyan;
  Pal.HeaderBg := cWindowBg;
  Pal.PanelTabActiveFg := cBlack;
  Pal.PanelTabActiveBg := cCyan;
  Pal.BorderFocusFg := cBorderFocus;
  Pal.BorderNormalFg := cBorderNormal;
  Pal.WorkspaceTabActiveFg := cTabActiveFg;
  Pal.WorkspaceTabActiveBg := cTabActiveBg;
  Pal.WorkspaceTabIdleFg := cTabNormalFg;
  Pal.WorkspaceTabIdleBg := cTabNormalBg;
  Pal.HotMarkFg := cToolKeyFg;
  Pal.CloseMarkFg := cLightMagenta;
  ResolveStandardPanelChromeColors(APart, AActive, Pal, AFg, ABg);
end;

procedure TASCIIOnlyTheme.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  AAttr := [];
  ABg := cWindowBg;
  case AKind of
    mskH1: begin AFg := cLightCyan; AAttr := [ccaBold]; end;
    mskH2: begin AFg := cYellow; AAttr := [ccaBold]; end;
    mskH3to6: begin AFg := cLightGreen; AAttr := [ccaBold]; end;
    mskBold: begin AFg := cWhite; AAttr := [ccaBold]; end;
    mskItalic: AFg := cLightMagenta;
    mskBoldItalic: begin AFg := cLightMagenta; AAttr := [ccaBold]; end;
    mskStrike: AFg := cHiddenFg;
    mskInlineCode: begin AFg := cLightGreen; ABg := cDarkCyan; end;
    mskCodeBlock: begin AFg := cText; ABg := cDarkCyan; end;
    mskQuote: AFg := cHiddenFg;
    mskListMarker: begin AFg := cYellow; AAttr := [ccaBold]; end;
    mskHRule: AFg := cLightGray;
    mskLink: AFg := cLightCyan;
    mskImageMarker: AFg := cHiddenFg;
    mskTableBorder: AFg := cLightGray;
    mskTableHeader: begin AFg := cYellow; AAttr := [ccaBold]; end;
  else
    AFg := cText;
  end;
end;

procedure TASCIIOnlyTheme.ResolveEditorColors(out AColors: TEditorThemeColors);
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
