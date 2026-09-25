unit uHighContrastTheme;

{ Stage 27: accessibility theme — pure black background, pure white/yellow
  text, fully saturated file-type colours, no dimmed/muted tones anywhere
  (a "hidden file" or "idle panel" still has to be legible, not merely
  present) and double-line box-drawing everywhere for maximum edge
  visibility. Same IThemeRenderer contract and the same 3-cell '[x]' close
  button geometry every theme keeps. }

interface

uses
  System.UITypes, System.SysUtils, System.Math,
  uTerminalTypes, uThemeTypes;

type
  THighContrastTheme = class(TInterfacedObject, IThemeRenderer)
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
  cBlack   = TAlphaColor($FF000000);
  cWhite   = TAlphaColor($FFFFFFFF);
  cYellow  = TAlphaColor($FFFFFF00);
  cCyan    = TAlphaColor($FF00FFFF);
  cGreen   = TAlphaColor($FF00FF00);
  cMagenta = TAlphaColor($FFFF00FF);
  cOrange  = TAlphaColor($FFFF8000);
  cRed     = TAlphaColor($FFFF0000);
  // Idle-panel/hidden-file tone: clearly distinguishable from pure black,
  // but never so dark it stops being a deliberate colour choice.
  cGreyPanel = TAlphaColor($FF303030);
  cGreyFg    = TAlphaColor($FFC0C0C0);

  cDesktopBg    = cBlack;
  cWindowBg     = cBlack;
  cText         = cWhite;
  cDialogBg     = cBlack;
  cDialogFg     = cYellow;
  cDialogBorder = cYellow;
  cDirFg        = cCyan;
  cBorderFocus  = cYellow;
  cBorderNormal = cWhite;
  cTitleFgFocus = cBlack;
  cTitleBgFocus = cYellow;
  cTitleFgNormal= cBlack;
  cTitleBgNormal= cWhite;
  cBtnFg        = cBlack;
  cBtnBg        = cWhite;
  cBtnFgFocus   = cBlack;
  cBtnBgFocus   = cYellow;
  cStatusFg     = cBlack;
  cStatusBg     = cYellow;
  cToolFg       = cWhite;
  cToolBg       = cWindowBg;
  cToolKeyFg    = cYellow;
  cTabActiveFg  = cBlack;
  cTabActiveBg  = cYellow;
  cTabNormalFg  = cWhite;
  cTabNormalBg  = cBlack;
  cScrollFg     = cWhite;
  cScrollThumb  = cYellow;
  cSelectedFg   = cYellow;
  cSelectedBg   = cWindowBg;
  cCursorFg     = cBlack;
  cCursorBg     = cYellow;
  cCursorIdleBg = cGreyPanel;

function THighContrastTheme.DesktopColor: TAlphaColor;
begin
  Result := cDesktopBg;
end;

procedure THighContrastTheme.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cText, cDesktopBg);
end;

procedure THighContrastTheme.DrawWindowFrame(const AGrid: TTerminalGrid;
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

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chDblTL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chDblTR, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chDblBL, Border, cWindowBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chDblBR, Border, cWindowBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chDblH, Border, cWindowBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chDblH, Border, cWindowBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chDblV, Border, cWindowBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chDblV, Border, cWindowBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, Border, cWindowBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cRed, cWindowBg);
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
    PutGridText(AGrid, StartX, ABounds.Top, Cap, TitleFg, TitleBg, [ccaBold]);
  end;
end;

procedure THighContrastTheme.DrawDialogFrame(const AGrid: TTerminalGrid;
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

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    chDblTL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    chDblTR, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, chDblBL, cDialogBorder, cDialogBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, chDblBR, cDialogBorder, cDialogBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    chDblH, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, chDblH, cDialogBorder, cDialogBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, chDblV, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, ABounds.Right, Y, chDblV, cDialogBorder, cDialogBg);
  end;

  Btns := '[x]';
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, cDialogBorder, cDialogBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, 'x', cRed, cDialogBg);
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
    PutGridText(AGrid, StartX, ABounds.Top, Cap, cTitleFgFocus, cTitleBgFocus, [ccaBold]);
  end;
end;

procedure THighContrastTheme.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure THighContrastTheme.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
  PutGridText(AGrid, ABounds.Left, ABounds.Top, Mark + AText, Fg, Bg, [ccaBold]);
end;

procedure THighContrastTheme.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
  PutGridText(AGrid, ABounds.Left, ABounds.Top, Mark + AText, Fg, Bg, [ccaBold]);
end;

procedure THighContrastTheme.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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

procedure THighContrastTheme.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
    ActiveBg := cYellow;
    ActiveFg := cBlack;
    NormalFg := cWhite;
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
    PutGridText(AGrid, X, ABounds.Top, Cap, Fg, Bg, [ccaBold]);
    Inc(X, Length(Cap) + 1);
  end;
end;

procedure THighContrastTheme.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
        cToolFg, cToolBg, [ccaBold]);
    end
    else
      PutGridText(AGrid, X, ABounds.Top, Item, cToolFg, cToolBg, [ccaBold]);
    Inc(X, Length(Item) + 1);
  end;
end;

procedure THighContrastTheme.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
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
    PutGridText(AGrid, X, ABounds.Top, ASegments[I], cStatusFg, cStatusBg, [ccaBold]);
    Inc(X, Length(ASegments[I]));
    if I < High(ASegments) then
    begin
      DrawGridChar(AGrid, X + 1, ABounds.Top, chDblV, cStatusFg, cStatusBg);
      Inc(X, 3);
    end;
  end;
end;

procedure THighContrastTheme.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AMenuText, AClockText: string; AState: TThemeWidgetState);
var
  ClockX, HotLen: Integer;
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', cStatusFg, cStatusBg);
  if AMenuText <> '' then
  begin
    PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, AMenuText, cStatusFg, cStatusBg, [ccaBold]);
    HotLen := 1;
    if Length(AMenuText) >= HotLen then
      PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, Copy(AMenuText, 1, HotLen),
        cRed, cStatusBg, [ccaBold]);
  end;
  if AClockText <> '' then
  begin
    ClockX := ABounds.Right - Length(AClockText);
    if ClockX < ABounds.Left + 30 then
      ClockX := ABounds.Left + 30;
    if ClockX <= ABounds.Right then
      PutGridText(AGrid, ClockX, ABounds.Top, AClockText, cStatusFg, cStatusBg, [ccaBold]);
  end;
end;

procedure THighContrastTheme.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState);
var
  Frame: TAlphaColor;
begin
  if AActive then
  begin
    Frame := cBorderFocus;
    DrawPanelFrameGlyphs(AGrid, ABounds, chDblTL, chDblTR, chDblBL, chDblBR, chDblH, chDblV,
      Frame, cText, cWindowBg);
  end
  else
  begin
    Frame := cBorderNormal;
    DrawPanelFrameGlyphs(AGrid, ABounds, chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV,
      Frame, cText, cWindowBg);
  end;
end;

function THighContrastTheme.UsesDoubleLineForActivePanel: Boolean;
begin
  Result := True;
end;

procedure THighContrastTheme.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor);

  function TypeFg: TAlphaColor;
  begin
    if AIsDirectory or AIsParent or SameText(AFileType, 'directory') then
      Result := cDirFg
    else if SameText(AFileType, 'archive') then
      Result := cOrange
    else if SameText(AFileType, 'executable') then
      Result := cGreen
    else if SameText(AFileType, 'media') then
      Result := cMagenta
    else
      Result := cText;
    // Hidden files stay legible on purpose — accessibility, not decoration —
    // just a distinct light grey instead of the file type's usual colour.
    if AIsHidden and not AIsParent then
      Result := cGreyFg;
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

procedure THighContrastTheme.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
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

procedure THighContrastTheme.ResolvePanelChromeColors(APart: TPanelChromePart;
  AActive: Boolean; out AFg, ABg: TAlphaColor);
var
  Pal: TPanelChromePalette;
begin
  Pal.TextFg := cText;
  Pal.WindowBg := cWindowBg;
  Pal.HeaderFg := cYellow;
  Pal.HeaderBg := cWindowBg;
  Pal.PanelTabActiveFg := cBlack;
  Pal.PanelTabActiveBg := cYellow;
  Pal.BorderFocusFg := cBorderFocus;
  Pal.BorderNormalFg := cBorderNormal;
  Pal.WorkspaceTabActiveFg := cTabActiveFg;
  Pal.WorkspaceTabActiveBg := cTabActiveBg;
  Pal.WorkspaceTabIdleFg := cTabNormalFg;
  Pal.WorkspaceTabIdleBg := cTabNormalBg;
  Pal.HotMarkFg := cToolKeyFg;
  Pal.CloseMarkFg := cRed;
  ResolveStandardPanelChromeColors(APart, AActive, Pal, AFg, ABg);
end;

procedure THighContrastTheme.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  AAttr := [];
  ABg := cWindowBg;
  case AKind of
    mskH1: begin AFg := cYellow; AAttr := [ccaBold]; end;
    mskH2: begin AFg := cCyan; AAttr := [ccaBold]; end;
    mskH3to6: begin AFg := cGreen; AAttr := [ccaBold]; end;
    mskBold: begin AFg := cWhite; AAttr := [ccaBold]; end;
    mskItalic: AFg := cMagenta;
    mskBoldItalic: begin AFg := cMagenta; AAttr := [ccaBold]; end;
    mskStrike: AFg := cGreyFg;
    mskInlineCode: begin AFg := cGreen; ABg := cGreyPanel; end;
    mskCodeBlock: begin AFg := cWhite; ABg := cGreyPanel; end;
    mskQuote: AFg := cGreyFg;
    mskListMarker: begin AFg := cYellow; AAttr := [ccaBold]; end;
    mskHRule: AFg := cGreyFg;
    mskLink: AFg := cCyan;
    mskImageMarker: AFg := cGreyFg;
    mskTableBorder: AFg := cGreyFg;
    mskTableHeader: begin AFg := cCyan; AAttr := [ccaBold]; end;
  else
    AFg := cText;
  end;
end;

procedure THighContrastTheme.ResolveEditorColors(out AColors: TEditorThemeColors);
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
