unit uDataTheme;

{ IThemeRenderer driven by a TThemeSpec: one class draws every theme, the
  spec supplies the colors, glyphs and text attributes. Geometry (title and
  close button placement, scrollbar thumb, tab and toolbar spacing) is the
  same for every theme; a theme can change how it looks, not where widgets
  put their parts. }

interface

uses
  System.UITypes, System.SysUtils, System.Math,
  uTerminalTypes, uThemeTypes, uThemeSpec;

type
  TDataTheme = class(TInterfacedObject, IThemeRenderer)
  private
    FSpec: TThemeSpec;
    function GlyphChar(AGlyph: TThemeGlyph): Char;
    procedure DrawTitledFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; const AFrame: TThemeFrameSet;
      ABodyFg, ABodyBg, ABorder, ATitleFg, ATitleBg: TAlphaColor;
      ATitleAttr: TCharCellAttributes);
    procedure DrawMarkedCaption(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AFg, ABg, AHot: TAlphaColor;
      AAttr, AHotAttr: TCharCellAttributes);
  public
    constructor Create(const ASpec: TThemeSpec);
    property Spec: TThemeSpec read FSpec;

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
    procedure ResolveMarkedRowBand(out AFg, ABg: TAlphaColor);
    procedure ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
    procedure ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveMarkdownStyleColors(AKind: TMdSpanKind;
      out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
    procedure ResolveEditorColors(out AColors: TEditorThemeColors);
  end;

implementation

constructor TDataTheme.Create(const ASpec: TThemeSpec);
begin
  inherited Create;
  FSpec := ASpec;
end;

function TDataTheme.GlyphChar(AGlyph: TThemeGlyph): Char;
begin
  if FSpec.Glyphs[AGlyph] = '' then
    Result := ' '
  else
    Result := FSpec.Glyphs[AGlyph][1];
end;

function TDataTheme.DesktopColor: TAlphaColor;
begin
  Result := FSpec.Colors[trDesktopBg];
end;

procedure TDataTheme.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    GlyphChar(tgDesktopFill), FSpec.Colors[trWindowFg], FSpec.Colors[trDesktopBg]);
end;

procedure TDataTheme.DrawTitledFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; const AFrame: TThemeFrameSet;
  ABodyFg, ABodyBg, ABorder, ATitleFg, ATitleBg: TAlphaColor;
  ATitleAttr: TCharCellAttributes);
var
  X, Y, W: Integer;
  Cap, Btns: string;
  StartX, BtnX: Integer;
begin
  W := ABounds.Width;
  if (W < 2) or (ABounds.Height < 2) then
    Exit;

  FillGridRect(AGrid, ABounds.Left + 1, ABounds.Top + 1,
    ABounds.Right - 1, ABounds.Bottom - 1, ' ', ABodyFg, ABodyBg);

  DrawGridChar(AGrid, ABounds.Left,  ABounds.Top,    AFrame.TL, ABorder, ABodyBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top,    AFrame.TR, ABorder, ABodyBg);
  DrawGridChar(AGrid, ABounds.Left,  ABounds.Bottom, AFrame.BL, ABorder, ABodyBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, AFrame.BR, ABorder, ABodyBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top,    AFrame.H, ABorder, ABodyBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, AFrame.H, ABorder, ABodyBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left,  Y, AFrame.V, ABorder, ABodyBg);
    DrawGridChar(AGrid, ABounds.Right, Y, AFrame.V, ABorder, ABodyBg);
  end;

  // The close button is always 3 cells; the hit test in uThemeDrawing
  // relies on that geometry.
  Btns := GlyphChar(tgCloseLeft) + GlyphChar(tgCloseMark) + GlyphChar(tgCloseRight);
  BtnX := ABounds.Right - Length(Btns);
  if BtnX <= ABounds.Left + 2 then
    BtnX := ABounds.Right;
  if BtnX < ABounds.Right then
  begin
    PutGridText(AGrid, BtnX, ABounds.Top, Btns, ABorder, ABodyBg);
    DrawGridChar(AGrid, BtnX + 1, ABounds.Top, GlyphChar(tgCloseMark),
      FSpec.Colors[trCloseAccent], ABodyBg);
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
    PutGridText(AGrid, StartX, ABounds.Top, Cap, ATitleFg, ATitleBg, ATitleAttr);
  end;
end;

procedure TDataTheme.DrawWindowFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; AState: TThemeWidgetState);
var
  Border, TitleBg, TitleFg: TAlphaColor;
begin
  if twFocused in AState then
  begin
    Border := FSpec.Colors[trBorderFocus];
    TitleBg := FSpec.Colors[trTitleBgFocus];
    TitleFg := FSpec.Colors[trTitleFgFocus];
  end
  else
  begin
    Border := FSpec.Colors[trBorderNormal];
    TitleBg := FSpec.Colors[trTitleBgNormal];
    TitleFg := FSpec.Colors[trTitleFgNormal];
  end;
  DrawTitledFrame(AGrid, ABounds, ATitle, FSpec.Frames[tfsWindow],
    FSpec.Colors[trWindowFg], FSpec.Colors[trWindowBg], Border, TitleFg, TitleBg,
    FSpec.Attrs[tasWindowTitle]);
end;

procedure TDataTheme.DrawDialogFrame(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const ATitle: string; AState: TThemeWidgetState);
begin
  DrawTitledFrame(AGrid, ABounds, ATitle, FSpec.Frames[tfsDialog],
    FSpec.Colors[trDialogFg], FSpec.Colors[trDialogBg], FSpec.Colors[trDialogBorder],
    FSpec.Colors[trDialogTitleFg], FSpec.Colors[trDialogTitleBg],
    FSpec.Attrs[tasDialogTitle]);
end;

procedure TDataTheme.DrawMarkedCaption(const AGrid: TTerminalGrid;
  const ABounds: TRectI; const AText: string; AFg, ABg, AHot: TAlphaColor;
  AAttr, AHotAttr: TCharCellAttributes);
begin
  PutGridHotTextClipped(AGrid, ABounds.Left, ABounds.Top, ABounds.Right,
    AText, AFg, ABg, AHot, AAttr, AHotAttr);
end;

procedure TDataTheme.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AState: TThemeWidgetState);
var
  Fg, Bg, Hot: TAlphaColor;
  HotAttr: TCharCellAttributes;
  Cap: string;
  StartX: Integer;
begin
  if twFocused in AState then
  begin
    Fg := FSpec.Colors[trButtonFocusFg];
    Bg := FSpec.Colors[trButtonFocusBg];
    Hot := FSpec.Colors[trButtonHotFocusFg];
    HotAttr := FSpec.Attrs[tasHotFocus];
  end
  else
  begin
    Fg := FSpec.Colors[trButtonFg];
    Bg := FSpec.Colors[trButtonBg];
    Hot := FSpec.Colors[trButtonHotFg];
    HotAttr := FSpec.Attrs[tasHot];
  end;
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', Fg, Bg);
  // twSelected marks the dialog's default button.
  if twSelected in AState then
    Cap := ThemeApplyTemplate(FSpec.Glyphs[tgButtonDefault], AText)
  else
    Cap := ThemeApplyTemplate(FSpec.Glyphs[tgButtonNormal], AText);
  StartX := ABounds.Left + (ABounds.Width - Length(StripHotKeyMarker(Cap))) div 2;
  if StartX < ABounds.Left then
    StartX := ABounds.Left;
  PutGridHotTextClipped(AGrid, StartX, ABounds.Top, ABounds.Right, Cap, Fg, Bg,
    Hot, FSpec.Attrs[tasButton], HotAttr);
end;

procedure TDataTheme.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
var
  Fg, Bg, Hot: TAlphaColor;
  HotAttr: TCharCellAttributes;
  Mark: string;
begin
  if twFocused in AState then
  begin
    Fg := FSpec.Colors[trCheckFocusFg];
    Bg := FSpec.Colors[trCheckFocusBg];
    Hot := FSpec.Colors[trCheckFocusHotFg];
    HotAttr := FSpec.Attrs[tasHotFocus];
  end
  else
  begin
    Fg := FSpec.Colors[trCheckFg];
    Bg := FSpec.Colors[trCheckBg];
    Hot := FSpec.Colors[trCheckHotFg];
    HotAttr := FSpec.Attrs[tasHot];
  end;
  if AChecked then
    Mark := FSpec.Glyphs[tgCheckOn]
  else
    Mark := FSpec.Glyphs[tgCheckOff];
  DrawMarkedCaption(AGrid, ABounds, Mark + AText, Fg, Bg, Hot,
    FSpec.Attrs[tasCheck], HotAttr);
end;

procedure TDataTheme.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
var
  Fg, Bg, Hot: TAlphaColor;
  HotAttr: TCharCellAttributes;
  Mark: string;
begin
  if twFocused in AState then
  begin
    Fg := FSpec.Colors[trCheckFocusFg];
    Bg := FSpec.Colors[trCheckFocusBg];
    Hot := FSpec.Colors[trCheckFocusHotFg];
    HotAttr := FSpec.Attrs[tasHotFocus];
  end
  else
  begin
    Fg := FSpec.Colors[trCheckFg];
    Bg := FSpec.Colors[trCheckBg];
    Hot := FSpec.Colors[trCheckHotFg];
    HotAttr := FSpec.Attrs[tasHot];
  end;
  if AChecked then
    Mark := FSpec.Glyphs[tgRadioOn]
  else
    Mark := FSpec.Glyphs[tgRadioOff];
  DrawMarkedCaption(AGrid, ABounds, Mark + AText, Fg, Bg, Hot,
    FSpec.Attrs[tasCheck], HotAttr);
end;

procedure TDataTheme.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
var
  I, Span, ThumbAt: Integer;
  Fg, Thumb, Bg: TAlphaColor;
begin
  Fg := FSpec.Colors[trScrollFg];
  Thumb := FSpec.Colors[trScrollThumb];
  Bg := FSpec.Colors[trWindowBg];
  if AVertical then
  begin
    Span := ABounds.Height;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, GlyphChar(tgScrollUp), Fg, Bg);
    DrawGridChar(AGrid, ABounds.Left, ABounds.Bottom, GlyphChar(tgScrollDown), Fg, Bg);
    for I := ABounds.Top + 1 to ABounds.Bottom - 1 do
      DrawGridChar(AGrid, ABounds.Left, I, GlyphChar(tgScrollShade), Fg, Bg);
    ThumbAt := ABounds.Top + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ABounds.Left, ThumbAt, GlyphChar(tgScrollBlock), Thumb, Bg);
  end
  else
  begin
    Span := ABounds.Width;
    if Span < 2 then
      Exit;
    DrawGridChar(AGrid, ABounds.Left, ABounds.Top, GlyphChar(tgScrollLeft), Fg, Bg);
    DrawGridChar(AGrid, ABounds.Right, ABounds.Top, GlyphChar(tgScrollRight), Fg, Bg);
    for I := ABounds.Left + 1 to ABounds.Right - 1 do
      DrawGridChar(AGrid, I, ABounds.Top, GlyphChar(tgScrollShade), Fg, Bg);
    ThumbAt := ABounds.Left + 1;
    if (AMax > 0) and (Span > 3) then
      Inc(ThumbAt, EnsureRange(Round(APosition * (Span - 3) / AMax), 0, Span - 3));
    DrawGridChar(AGrid, ThumbAt, ABounds.Top, GlyphChar(tgScrollBlock), Thumb, Bg);
  end;
end;

procedure TDataTheme.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATabNames: TArray<string>; AActiveTabIndex: Integer;
  AState: TThemeWidgetState; AKind: TTabBarKind);
var
  I, X: Integer;
  Cap: string;
  Fg, Bg, BarBg, ActiveBg, ActiveFg, NormalFg: TAlphaColor;
begin
  if AKind = tbkWorkspace then
  begin
    BarBg := FSpec.Colors[trTabNormalBg];
    ActiveBg := FSpec.Colors[trTabActiveBg];
    ActiveFg := FSpec.Colors[trTabActiveFg];
    NormalFg := FSpec.Colors[trTabNormalFg];
  end
  else
  begin
    BarBg := FSpec.Colors[trPanelTabBarBg];
    ActiveBg := FSpec.Colors[trPanelTabActiveBg];
    ActiveFg := FSpec.Colors[trPanelTabActiveFg];
    NormalFg := FSpec.Colors[trPanelTabNormalFg];
  end;

  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', NormalFg, BarBg);
  X := ABounds.Left;
  for I := 0 to High(ATabNames) do
  begin
    if AKind = tbkWorkspace then
      Cap := ThemeApplyTemplate(FSpec.Glyphs[tgTabWorkspace], ATabNames[I])
    else
      Cap := ThemeApplyTemplate(FSpec.Glyphs[tgTabPanel], ATabNames[I]);
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
    PutGridText(AGrid, X, ABounds.Top, Cap, Fg, Bg, FSpec.Attrs[tasTab]);
    Inc(X, Length(Cap) + 1);
  end;
end;

procedure TDataTheme.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AItems: TArray<string>; AState: TThemeWidgetState);
var
  I, X, KeyLen: Integer;
  Item, KeyPart: string;
  Fg, Bg, KeyFg: TAlphaColor;
begin
  Fg := FSpec.Colors[trToolFg];
  Bg := FSpec.Colors[trToolBg];
  KeyFg := FSpec.Colors[trToolKeyFg];
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', Fg, Bg);
  X := ABounds.Left;
  for I := 0 to High(AItems) do
  begin
    Item := AItems[I];
    if X > ABounds.Right then
      Break;
    // A leading function-key number ("1", "10") gets the key color.
    KeyLen := 0;
    while (KeyLen < Length(Item)) and CharInSet(Item[KeyLen + 1], ['0'..'9']) do
      Inc(KeyLen);
    if KeyLen > 0 then
    begin
      KeyPart := Copy(Item, 1, KeyLen);
      PutGridText(AGrid, X, ABounds.Top, KeyPart, KeyFg, Bg, FSpec.Attrs[tasToolbarKey]);
      PutGridText(AGrid, X + KeyLen, ABounds.Top, Copy(Item, KeyLen + 1, MaxInt),
        Fg, Bg, FSpec.Attrs[tasToolbar]);
    end
    else
      PutGridText(AGrid, X, ABounds.Top, Item, Fg, Bg, FSpec.Attrs[tasToolbar]);
    Inc(X, Length(Item) + 1);
  end;
end;

procedure TDataTheme.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ASegments: TArray<string>; AState: TThemeWidgetState);
var
  I, X: Integer;
  Fg, Bg: TAlphaColor;
begin
  Fg := FSpec.Colors[trStatusFg];
  Bg := FSpec.Colors[trStatusBg];
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', Fg, Bg);
  X := ABounds.Left + 1;
  for I := 0 to High(ASegments) do
  begin
    if X > ABounds.Right then
      Break;
    PutGridText(AGrid, X, ABounds.Top, ASegments[I], Fg, Bg, FSpec.Attrs[tasStatus]);
    Inc(X, Length(ASegments[I]));
    if I < High(ASegments) then
    begin
      DrawGridChar(AGrid, X + 1, ABounds.Top, GlyphChar(tgStatusSeparator),
        FSpec.Colors[trStatusSeparator], Bg);
      Inc(X, 3);
    end;
  end;
end;

procedure TDataTheme.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AMenuText, AClockText: string; AState: TThemeWidgetState);
var
  ClockX, HotLen: Integer;
  Fg, Bg: TAlphaColor;
begin
  Fg := FSpec.Colors[trMenuFg];
  Bg := FSpec.Colors[trMenuBg];
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', Fg, Bg);
  if AMenuText <> '' then
  begin
    PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, AMenuText, Fg, Bg,
      FSpec.Attrs[tasMenu]);
    // The first character is the hot glyph (the menu icon) when present.
    HotLen := 1;
    if Length(AMenuText) >= HotLen then
      PutGridText(AGrid, ABounds.Left + 1, ABounds.Top, Copy(AMenuText, 1, HotLen),
        FSpec.Colors[trMenuHotFg], Bg, FSpec.Attrs[tasMenuHot]);
  end;
  if AClockText <> '' then
  begin
    ClockX := ABounds.Right - Length(AClockText);
    if ClockX < ABounds.Left + 30 then
      ClockX := ABounds.Left + 30;
    if ClockX <= ABounds.Right then
      PutGridText(AGrid, ClockX, ABounds.Top, AClockText,
        FSpec.Colors[trClockFg], Bg, FSpec.Attrs[tasClock]);
  end;
end;

procedure TDataTheme.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState);
var
  Frame: TThemeFrameSet;
  Border: TAlphaColor;
begin
  if AActive then
  begin
    Frame := FSpec.Frames[tfsPanelActive];
    Border := FSpec.Colors[trBorderFocus];
  end
  else
  begin
    Frame := FSpec.Frames[tfsPanelIdle];
    Border := FSpec.Colors[trBorderNormal];
  end;
  DrawPanelFrameGlyphs(AGrid, ABounds, Frame.TL, Frame.TR, Frame.BL, Frame.BR,
    Frame.H, Frame.V, Border, FSpec.Colors[trWindowFg], FSpec.Colors[trWindowBg]);
end;

function TDataTheme.UsesDoubleLineForActivePanel: Boolean;
begin
  Result := FSpec.DoubleActivePanel;
end;

procedure TDataTheme.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor);

  function TypeFg: TAlphaColor;
  var
    Hidden: Boolean;
  begin
    Hidden := AIsHidden and not AIsParent;
    if AIsDirectory or AIsParent or SameText(AFileType, 'directory') then
    begin
      if Hidden then
        Result := FSpec.Colors[trFileHiddenDir]
      else
        Result := FSpec.Colors[trFileDir];
    end
    else if SameText(AFileType, 'archive') then
    begin
      if Hidden then
        Result := FSpec.Colors[trFileHiddenArchive]
      else
        Result := FSpec.Colors[trFileArchive];
    end
    else if SameText(AFileType, 'executable') then
    begin
      if Hidden then
        Result := FSpec.Colors[trFileHiddenExecutable]
      else
        Result := FSpec.Colors[trFileExecutable];
    end
    else if SameText(AFileType, 'media') then
    begin
      if Hidden then
        Result := FSpec.Colors[trFileHiddenMedia]
      else
        Result := FSpec.Colors[trFileMedia];
    end
    else if Hidden then
      Result := FSpec.Colors[trFileHiddenPlain]
    else
      Result := FSpec.Colors[trFilePlain];
  end;

begin
  if ACursor then
  begin
    if ASelected then
    begin
      AFg := FSpec.Colors[trCursorMarkedFg];
      ABg := FSpec.Colors[trCursorMarkedBg];
    end
    else if ASideActive then
    begin
      AFg := FSpec.Colors[trCursorFg];
      ABg := FSpec.Colors[trCursorBg];
    end
    else
    begin
      ABg := FSpec.Colors[trCursorIdleBg];
      AFg := TypeFg;
    end;
  end
  else if ASelected then
  begin
    AFg := FSpec.Colors[trMarkFg];
    ABg := FSpec.Colors[trMarkBg];
  end
  else
  begin
    ABg := FSpec.Colors[trWindowBg];
    AFg := TypeFg;
  end;
end;

procedure TDataTheme.ResolveMarkedRowBand(out AFg, ABg: TAlphaColor);
begin
  AFg := FSpec.Colors[trMarkBandFg];
  ABg := FSpec.Colors[trMarkBandBg];
end;

procedure TDataTheme.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
begin
  if ACursor then
  begin
    AFg := FSpec.Colors[trDialogRowCursorFg];
    ABg := FSpec.Colors[trDialogRowCursorBg];
  end
  else
  begin
    AFg := FSpec.Colors[trDialogRowFg];
    ABg := FSpec.Colors[trDialogRowBg];
  end;
end;

procedure TDataTheme.ResolvePanelChromeColors(APart: TPanelChromePart;
  AActive: Boolean; out AFg, ABg: TAlphaColor);
var
  Pal: TPanelChromePalette;
begin
  Pal.TextFg := FSpec.Colors[trWindowFg];
  Pal.WindowBg := FSpec.Colors[trWindowBg];
  Pal.HeaderFg := FSpec.Colors[trPanelHeaderFg];
  Pal.HeaderBg := FSpec.Colors[trPanelHeaderBg];
  Pal.PanelTabActiveFg := FSpec.Colors[trPanelTabActiveFg];
  Pal.PanelTabActiveBg := FSpec.Colors[trPanelTabActiveBg];
  Pal.BorderFocusFg := FSpec.Colors[trBorderFocus];
  Pal.BorderNormalFg := FSpec.Colors[trBorderNormal];
  Pal.WorkspaceTabActiveFg := FSpec.Colors[trTabActiveFg];
  Pal.WorkspaceTabActiveBg := FSpec.Colors[trTabActiveBg];
  Pal.WorkspaceTabIdleFg := FSpec.Colors[trTabNormalFg];
  Pal.WorkspaceTabIdleBg := FSpec.Colors[trTabNormalBg];
  Pal.HotMarkFg := FSpec.Colors[trPanelHotMark];
  Pal.CloseMarkFg := FSpec.Colors[trPanelCloseMark];
  ResolveStandardPanelChromeColors(APart, AActive, Pal, AFg, ABg);
end;

procedure TDataTheme.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  AFg := FSpec.MdFg[AKind];
  ABg := FSpec.MdBg[AKind];
  AAttr := FSpec.MdAttrs[AKind];
end;

procedure TDataTheme.ResolveEditorColors(out AColors: TEditorThemeColors);
begin
  AColors.BodyFg := FSpec.Colors[trEditorBodyFg];
  AColors.BodyBg := FSpec.Colors[trEditorBodyBg];
  AColors.CursorFg := FSpec.Colors[trEditorCursorFg];
  AColors.CursorBg := FSpec.Colors[trEditorCursorBg];
  AColors.SelFg := FSpec.Colors[trEditorSelFg];
  AColors.SelBg := FSpec.Colors[trEditorSelBg];
  AColors.HintFg := FSpec.Colors[trEditorHintFg];
  AColors.StatusFg := FSpec.Colors[trEditorStatusFg];
  AColors.StatusBg := FSpec.Colors[trEditorStatusBg];
  AColors.FrameFocus := FSpec.Colors[trEditorFrameFocus];
  AColors.FrameIdle := FSpec.Colors[trEditorFrameIdle];
  AColors.ScrollFg := FSpec.Colors[trEditorScrollFg];
  AColors.ScrollThumb := FSpec.Colors[trEditorScrollThumb];
  AColors.MatchFg := FSpec.Colors[trEditorMatchFg];
  AColors.MatchBg := FSpec.Colors[trEditorMatchBg];
end;

end.
