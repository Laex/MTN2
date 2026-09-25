unit uThemeProxy;

{ Stage 27: live theme switching. Every window/dialog/controller receives an
  IThemeRenderer once at construction time and stores that exact interface
  reference for its whole lifetime (constructor injection, never re-queried —
  see uMdiCompositor/uDualPanelWindow/uTopMenuBar/etc.). Recreating dozens of
  live windows just to change which theme they point at isn't an option, so
  TMainForm hands out this proxy instead of a concrete theme: everyone ends up
  holding a reference to the SAME TThemeProxy object, and SetInner silently
  redirects every one of them to a new concrete IThemeRenderer at once, with
  no cascade of per-object SetTheme calls to keep in sync. }

interface

uses
  System.UITypes,
  uTerminalTypes, uThemeTypes;

type
  TThemeProxy = class(TInterfacedObject, IThemeRenderer)
  private
    FInner: IThemeRenderer;
  public
    constructor Create(const AInner: IThemeRenderer);
    procedure SetInner(const AInner: IThemeRenderer);

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

constructor TThemeProxy.Create(const AInner: IThemeRenderer);
begin
  inherited Create;
  FInner := AInner;
end;

procedure TThemeProxy.SetInner(const AInner: IThemeRenderer);
begin
  FInner := AInner;
end;

function TThemeProxy.DesktopColor: TAlphaColor;
begin
  Result := FInner.DesktopColor;
end;

procedure TThemeProxy.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
begin
  FInner.DrawDesktop(AGrid, ABounds);
end;

procedure TThemeProxy.DrawWindowFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string; AState: TThemeWidgetState);
begin
  FInner.DrawWindowFrame(AGrid, ABounds, ATitle, AState);
end;

procedure TThemeProxy.DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string; AState: TThemeWidgetState);
begin
  FInner.DrawDialogFrame(AGrid, ABounds, ATitle, AState);
end;

procedure TThemeProxy.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AState: TThemeWidgetState);
begin
  FInner.DrawButton(AGrid, ABounds, AText, AState);
end;

procedure TThemeProxy.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
begin
  FInner.DrawCheckBox(AGrid, ABounds, AText, AChecked, AState);
end;

procedure TThemeProxy.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
begin
  FInner.DrawRadioBox(AGrid, ABounds, AText, AChecked, AState);
end;

procedure TThemeProxy.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
begin
  FInner.DrawScrollBar(AGrid, ABounds, APosition, AMax, AVertical, AState);
end;

procedure TThemeProxy.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATabNames: TArray<string>; AActiveTabIndex: Integer;
  AState: TThemeWidgetState; AKind: TTabBarKind);
begin
  FInner.DrawTabBar(AGrid, ABounds, ATabNames, AActiveTabIndex, AState, AKind);
end;

procedure TThemeProxy.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AItems: TArray<string>; AState: TThemeWidgetState);
begin
  FInner.DrawToolBar(AGrid, ABounds, AItems, AState);
end;

procedure TThemeProxy.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ASegments: TArray<string>; AState: TThemeWidgetState);
begin
  FInner.DrawStatusLine(AGrid, ABounds, ASegments, AState);
end;

procedure TThemeProxy.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AMenuText, AClockText: string; AState: TThemeWidgetState);
begin
  FInner.DrawMenuBar(AGrid, ABounds, AMenuText, AClockText, AState);
end;

procedure TThemeProxy.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState);
begin
  FInner.DrawPanelFrame(AGrid, ABounds, AActive, AState);
end;

function TThemeProxy.UsesDoubleLineForActivePanel: Boolean;
begin
  Result := FInner.UsesDoubleLineForActivePanel;
end;

procedure TThemeProxy.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor);
begin
  FInner.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden, AFileType,
    ASelected, ACursor, ASideActive, AFg, ABg);
end;

procedure TThemeProxy.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
begin
  FInner.ResolveDialogRowColors(ACursor, AFg, ABg);
end;

procedure TThemeProxy.ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor);
begin
  FInner.ResolvePanelChromeColors(APart, AActive, AFg, ABg);
end;

procedure TThemeProxy.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  FInner.ResolveMarkdownStyleColors(AKind, AFg, ABg, AAttr);
end;

procedure TThemeProxy.ResolveEditorColors(out AColors: TEditorThemeColors);
begin
  FInner.ResolveEditorColors(AColors);
end;

end.
