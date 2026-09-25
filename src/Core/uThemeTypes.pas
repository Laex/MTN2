unit uThemeTypes;

interface

uses
  System.UITypes,
  uTerminalTypes;

type
  // Cell rectangle in grid coordinates. Left/Top/Right/Bottom are INCLUSIVE
  // cell indices, so a 1x1 window has Left = Right and Width = 1.
  TRectI = record
    Left, Top, Right, Bottom: Integer;
    function Width: Integer;
    function Height: Integer;
    function Contains(AX, AY: Integer): Boolean;
    class function Make(ALeft, ATop, ARight, ABottom: Integer): TRectI; static;
  end;

  TWindowState = (wsNormal, wsMaximized, wsMinimized);

  TThemeWidgetFlag = (twFocused, twPressed, twHovered, twDisabled, twSelected);
  TThemeWidgetState = set of TThemeWidgetFlag;

  // Dual Panel Tabs (workspace) vs Panel Tabs (per side) — same widget, different chrome.
  TTabBarKind = (tbkWorkspace, tbkPanel);

  /// <summary>Panel-interior chrome parts Host paints after DrawPanelFrame.</summary>
  TPanelChromePart = (
    pcpListBody,
    pcpColumnHeader,
    pcpInfoStrip,
    pcpPanelTabActive,
    pcpPanelTabIdle,
    pcpWorkspaceTabActive,
    pcpWorkspaceTabIdle,
    pcpHotMark,
    pcpCloseMark,
    pcpFrameActive,
    pcpFrameIdle
  );

  /// <summary>Every field ResolveStandardPanelChromeColors needs to answer a
  /// TPanelChromePart query. Every IThemeRenderer implementer's
  /// ResolvePanelChromeColors had the exact same case statement,
  /// differing only in which of its own private color constants filled each
  /// role — so the branching now lives once here (same "shared here, no
  /// uses-clause churn" reasoning as TMdSpanKind above) and each theme just
  /// fills a palette from its own constants.</summary>
  TPanelChromePalette = record
    TextFg, WindowBg: TAlphaColor;                           // pcpListBody/InfoStrip + fallback
    HeaderFg, HeaderBg: TAlphaColor;                          // pcpColumnHeader
    PanelTabActiveFg, PanelTabActiveBg: TAlphaColor;          // pcpPanelTabActive
    BorderFocusFg, BorderNormalFg: TAlphaColor;               // pcpPanelTabIdle, pcpFrameActive/Idle
    WorkspaceTabActiveFg, WorkspaceTabActiveBg: TAlphaColor;  // pcpWorkspaceTabActive
    WorkspaceTabIdleFg, WorkspaceTabIdleBg: TAlphaColor;      // pcpWorkspaceTabIdle
    HotMarkFg: TAlphaColor;                                   // pcpHotMark
    CloseMarkFg: TAlphaColor;                                 // pcpCloseMark (tab/window 'x')
  end;

  /// <summary>Stage 25: logical style categories a Markdown Viewer span can
  /// carry. Lives here (not in uMarkdownParser) so every IThemeRenderer
  /// implementer already has it in scope via the uThemeTypes they use for
  /// the interface itself — no extra uses-clause churn across the 8 theme
  /// units. mskH3to6 collapses H3..H6 into one visual tier (cell-grid TUI,
  /// not enough palette headroom for 6 distinct heading weights).</summary>
  TMdSpanKind = (
    mskText,
    mskH1,
    mskH2,
    mskH3to6,
    mskBold,
    mskItalic,
    mskBoldItalic,
    mskStrike,
    mskInlineCode,
    mskCodeBlock,
    mskQuote,
    mskListMarker,
    mskHRule,
    mskLink,
    mskImageMarker,
    mskTableBorder,
    mskTableHeader
  );

  /// <summary>Bug fix: TEditorWindow (F3 Viewer / F4 Editor) drew its whole
  /// body — text, cursor, selection, status line, frame, scrollbar, find
  /// highlight — with a fixed hard-coded NDN-blue palette, so switching the
  /// active theme changed the window frame (via DrawWindowFrame) but never
  /// the content inside it. Every field here mirrors a color TEditorWindow
  /// used to hard-code locally; each implementer just re-exposes consts it
  /// already declares for the equivalent panel/chrome concept (cText/
  /// cWindowBg, cCursorFg/cCursorBg, cStatusFg/cStatusBg, cBorderFocus/
  /// cBorderNormal, cScrollFg/cScrollThumb, cToolKeyFg). SelFg/SelBg fill
  /// F3/F4 text selection and must contrast BodyBg — not the panel file-mark
  /// pair (cSelected* is often yellow on the same blue as the body). MatchFg/
  /// MatchBg is the Find prompt selection on the status line; same constraint.</summary>
  TEditorThemeColors = record
    BodyFg, BodyBg: TAlphaColor;
    CursorFg, CursorBg: TAlphaColor;
    SelFg, SelBg: TAlphaColor;
    HintFg: TAlphaColor;
    StatusFg, StatusBg: TAlphaColor;
    FrameFocus, FrameIdle: TAlphaColor;
    ScrollFg, ScrollThumb: TAlphaColor;
    MatchFg, MatchBg: TAlphaColor;
  end;

  // Visual style of widgets rendered into a text grid. The Core (Host) owns
  // layout and compositing; the theme only decides how cells look.
  IThemeRenderer = interface
    ['{8A5D3F6A-4E2B-4A1C-8DF0-DF29D55C7B7E}']
    // Background colour of the compositor desktop behind all windows.
    function DesktopColor: TAlphaColor;
    // Fills the compositor desktop area (dotted NDN-style background).
    procedure DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);

    procedure DrawWindowFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; AState: TThemeWidgetState);

    /// <summary>Modal dialogs / Host overlays: white body, black text (FAR-style).</summary>
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

    /// <summary>Top menu strip with hotkeys (e.g. Left/Files/Commands… + clock).</summary>
    procedure DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AMenuText, AClockText: string; AState: TThemeWidgetState);

    // Dual Panel chrome (Host still owns layout; theme owns cell style).
    procedure DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      AActive: Boolean; AState: TThemeWidgetState);
    /// <summary>True if DrawPanelFrame draws the active panel's border with
    /// double-line glyphs (FAR/NDN convention: active = double, idle =
    /// single); False if active/idle share one glyph weight and differ by
    /// colour only. Host-drawn dividers inside the panel body (e.g. the
    /// totals rule above the info strip) match this so they don't clash
    /// with the panel's own border weight.</summary>
    function UsesDoubleLineForActivePanel: Boolean;
    procedure ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
      const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
    procedure ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    /// <summary>Stage 25 Markdown Viewer: color/attribute for one span kind.
    /// AAttr should only ever contain ccaBold in practice — the terminal
    /// renderer (uTerminalRenderer.TTerminalRenderer) paints ccaBold,
    /// ccaUnderline and ccaInsertCaret; ccaItalic has no visual effect, so
    /// implementers should lean on AFg/ABg (and ccaBold) to convey style.
    /// TMarkdownPainter adds ccaUnderline to mskLink itself.</summary>
    procedure ResolveMarkdownStyleColors(AKind: TMdSpanKind;
      out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
    /// <summary>TEditorWindow (F3/F4) body chrome — see TEditorThemeColors.</summary>
    procedure ResolveEditorColors(out AColors: TEditorThemeColors);
  end;

/// <summary>Shared body for every IThemeRenderer.ResolvePanelChromeColors
/// implementation (and TDualPanelWindow.ResolveChrome's Theme=nil
/// fallback) — see TPanelChromePalette.</summary>
procedure ResolveStandardPanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
  const APalette: TPanelChromePalette; out AFg, ABg: TAlphaColor);

/// <summary>Fills ABounds and draws a box-drawing border on top of it —
/// the "fill body, then paint 4 corners + 2 edge loops" shape every
/// IThemeRenderer.DrawPanelFrame implementation had (and the Theme=nil /
/// fallback frame draws in uDualPanelWindow.pas, uDialogHost.pas and
/// uDualPanelOverlays.pas), differing only in which glyphs and colors were
/// passed in. ATL/ATR/ABL/ABR/AH/AV are the corner/edge glyphs (single-line
/// chBoxXX or double-line chDblXX, per caller); AFrameColor paints them and
/// the fill uses AFillFg/AFillBg (border cells sit on AFillBg too).</summary>
procedure DrawPanelFrameGlyphs(const AGrid: TTerminalGrid; const ABounds: TRectI;
  ATL, ATR, ABL, ABR, AH, AV: Char; AFrameColor, AFillFg, AFillBg: TAlphaColor);

implementation

procedure DrawPanelFrameGlyphs(const AGrid: TTerminalGrid; const ABounds: TRectI;
  ATL, ATR, ABL, ABR, AH, AV: Char; AFrameColor, AFillFg, AFillBg: TAlphaColor);
var
  X, Y: Integer;
begin
  FillGridRect(AGrid, ABounds.Left, ABounds.Top, ABounds.Right, ABounds.Bottom,
    ' ', AFillFg, AFillBg);
  DrawGridChar(AGrid, ABounds.Left, ABounds.Top, ATL, AFrameColor, AFillBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Top, ATR, AFrameColor, AFillBg);
  DrawGridChar(AGrid, ABounds.Left, ABounds.Bottom, ABL, AFrameColor, AFillBg);
  DrawGridChar(AGrid, ABounds.Right, ABounds.Bottom, ABR, AFrameColor, AFillBg);
  for X := ABounds.Left + 1 to ABounds.Right - 1 do
  begin
    DrawGridChar(AGrid, X, ABounds.Top, AH, AFrameColor, AFillBg);
    DrawGridChar(AGrid, X, ABounds.Bottom, AH, AFrameColor, AFillBg);
  end;
  for Y := ABounds.Top + 1 to ABounds.Bottom - 1 do
  begin
    DrawGridChar(AGrid, ABounds.Left, Y, AV, AFrameColor, AFillBg);
    DrawGridChar(AGrid, ABounds.Right, Y, AV, AFrameColor, AFillBg);
  end;
end;

procedure ResolveStandardPanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
  const APalette: TPanelChromePalette; out AFg, ABg: TAlphaColor);
begin
  case APart of
    pcpListBody, pcpInfoStrip:
      begin
        AFg := APalette.TextFg;
        ABg := APalette.WindowBg;
      end;
    pcpColumnHeader:
      begin
        AFg := APalette.HeaderFg;
        ABg := APalette.HeaderBg;
      end;
    pcpPanelTabActive:
      begin
        AFg := APalette.PanelTabActiveFg;
        ABg := APalette.PanelTabActiveBg;
      end;
    pcpPanelTabIdle:
      begin
        if AActive then
          AFg := APalette.BorderFocusFg
        else
          AFg := APalette.BorderNormalFg;
        ABg := APalette.WindowBg;
      end;
    pcpWorkspaceTabActive:
      begin
        AFg := APalette.WorkspaceTabActiveFg;
        ABg := APalette.WorkspaceTabActiveBg;
      end;
    pcpWorkspaceTabIdle:
      begin
        AFg := APalette.WorkspaceTabIdleFg;
        ABg := APalette.WorkspaceTabIdleBg;
      end;
    pcpHotMark:
      begin
        AFg := APalette.HotMarkFg;
        ABg := APalette.WindowBg;
      end;
    pcpCloseMark:
      begin
        AFg := APalette.CloseMarkFg;
        ABg := APalette.WindowBg;
      end;
    pcpFrameActive:
      begin
        AFg := APalette.BorderFocusFg;
        ABg := APalette.WindowBg;
      end;
    pcpFrameIdle:
      begin
        AFg := APalette.BorderNormalFg;
        ABg := APalette.WindowBg;
      end;
  else
    begin
      AFg := APalette.TextFg;
      ABg := APalette.WindowBg;
    end;
  end;
end;

{ TRectI }

function TRectI.Width: Integer;
begin
  Result := Right - Left + 1;
end;

function TRectI.Height: Integer;
begin
  Result := Bottom - Top + 1;
end;

function TRectI.Contains(AX, AY: Integer): Boolean;
begin
  Result := (AX >= Left) and (AX <= Right) and (AY >= Top) and (AY <= Bottom);
end;

class function TRectI.Make(ALeft, ATop, ARight, ABottom: Integer): TRectI;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

end.
