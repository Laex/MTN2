unit uDualPanelHistoryPopup;

{ Alt+Left/Right directory-history popup. HistoryBack/HistoryForward already
  navigate on every press; this only visualizes the tab's back/forward list
  and current position while Alt is held, and is closed by the host
  (TDualPanelWindow.SetKeyModifiers) the moment Alt is released. }

interface

uses
  System.SysUtils, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uDualPanelOverlays,
  uDualPanelDrawUtils, uPanelUriLabels;

type
  TPanelBoundsEvent = reference to function(ASide: TPanelSide): TRectI;

  THistoryPopupController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FGetPanelBounds: TPanelBoundsEvent;
    FVisible: Boolean;
    FSide: TPanelSide;
    FItems: TArray<string>;
    FCursorIndex: Integer;
    FScrollOffset: Integer;
    FListTopPad: Integer;
    FBounds: TRectI;
    procedure Layout;
    procedure EnsureView;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AGetPanelBounds: TPanelBoundsEvent);
    procedure SetTheme(const ATheme: IThemeRenderer);
    /// <summary>(Re)shows the popup for ASide with AItems (display labels,
    /// oldest first — same order as TTab.History) and highlights
    /// ACursorIndex. Closes itself when AItems is empty.</summary>
    procedure Show(ASide: TPanelSide; const AItems: TArray<string>;
      ACursorIndex: Integer);
    procedure Close;
    procedure Draw(const AGrid: TTerminalGrid);
    property Visible: Boolean read FVisible;
  end;

implementation

const
  cPreferredViewRows = 21;
  cPreferredWidth = 56;
  cListFg      = TAlphaColor($FFAAAAAA);
  cPanelBg     = TAlphaColor($FF0000AA);
  cCursorFg    = TAlphaColor($FF000000);
  cCursorBg    = TAlphaColor($FF00AAAA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cTitleFg     = TAlphaColor($FFFFFF55);

constructor THistoryPopupController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AGetPanelBounds: TPanelBoundsEvent);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FGetPanelBounds := AGetPanelBounds;
  FVisible := False;
end;

procedure THistoryPopupController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

procedure THistoryPopupController.Close;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  SetLength(FItems, 0);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure THistoryPopupController.EnsureView;
var
  ViewH, MaxOff: Integer;
begin
  ViewH := Max(FBounds.Height - 2, 1);
  if Length(FItems) <= ViewH then
  begin
    FScrollOffset := 0;
    FListTopPad := ViewH div 2 - FCursorIndex;
    if FListTopPad < 0 then
      FListTopPad := 0;
    if FListTopPad + Length(FItems) > ViewH then
      FListTopPad := ViewH - Length(FItems);
    if FListTopPad < 0 then
      FListTopPad := 0;
  end
  else
  begin
    FListTopPad := 0;
    MaxOff := Length(FItems) - ViewH;
    FScrollOffset := FCursorIndex - ViewH div 2;
    if FScrollOffset < 0 then
      FScrollOffset := 0;
    if FScrollOffset > MaxOff then
      FScrollOffset := MaxOff;
  end;
end;

procedure THistoryPopupController.Layout;
var
  PanelBounds, LeftB, RightB: TRectI;
  W, H, MaxList, ViewRows, SharedInner: Integer;
begin
  PanelBounds := FGetPanelBounds(FSide);
  LeftB := FGetPanelBounds(psLeft);
  RightB := FGetPanelBounds(psRight);
  SharedInner := Min(LeftB.Width, RightB.Width);
  // Same width on both sides: do not size from the current panel's labels.
  W := Min(cPreferredWidth, Max(SharedInner - 2, 20));
  if W > PanelBounds.Width - 1 then
    W := Max(PanelBounds.Width - 1, 20);
  MaxList := Max(PanelBounds.Height - 4, 3);
  ViewRows := Min(MaxList, cPreferredViewRows);
  H := ViewRows + 2;
  if H < 4 then
    H := 4;
  if H > PanelBounds.Height - 1 then
    H := Max(PanelBounds.Height - 1, 4);
  FBounds := TRectI.Make(
    PanelBounds.Left + Max((PanelBounds.Width - W) div 2, 1),
    PanelBounds.Top + Max((PanelBounds.Height - H) div 2, 1),
    PanelBounds.Left + Max((PanelBounds.Width - W) div 2, 1) + W - 1,
    PanelBounds.Top + Max((PanelBounds.Height - H) div 2, 1) + H - 1);
  EnsureView;
end;

procedure THistoryPopupController.Show(ASide: TPanelSide;
  const AItems: TArray<string>; ACursorIndex: Integer);
begin
  FSide := ASide;
  FItems := AItems;
  if Length(FItems) = 0 then
  begin
    Close;
    Exit;
  end;
  FCursorIndex := EnsureRange(ACursorIndex, 0, High(FItems));
  FScrollOffset := 0;
  FListTopPad := 0;
  FVisible := True;
  Layout;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure THistoryPopupController.Draw(const AGrid: TTerminalGrid);
var
  R: TRectI;
  I, Y, Idx, InnerW, ListTop, ListBottom, ViewH, ScrollX: Integer;
  Line: string;
  Fg, Bg: TAlphaColor;
begin
  if not FVisible then
    Exit;
  Layout;
  R := FBounds;
  if (R.Width < 12) or (R.Height < 4) then
    Exit;

  DrawHostOverlayFrame(AGrid, FTheme, R, 'History',
    cListFg, cPanelBg, cFrameActive, cTitleFg);

  ListTop := R.Top + 1;
  ListBottom := R.Bottom - 1;
  ViewH := Max(ListBottom - ListTop + 1, 1);
  ScrollX := R.Right - 1;
  InnerW := Max(ScrollX - (R.Left + 1), 8);
  EnsureView;

  for I := 0 to ViewH - 1 do
  begin
    Y := ListTop + I;
    if Y > ListBottom then
      Break;
    if Length(FItems) > ViewH then
      Idx := FScrollOffset + I
    else
      Idx := I - FListTopPad;
    if (Idx >= 0) and (Idx <= High(FItems)) then
    begin
      Line := FitFolderHistoryLabel(FItems[Idx], InnerW);
      if Length(Line) < InnerW then
        Line := Line + StringOfChar(' ', InnerW - Length(Line));
      if Idx = FCursorIndex then
        ResolveOverlayTextColors(FTheme, False, False, True, cCursorFg, cCursorBg, Fg, Bg)
      else
        ResolveOverlayTextColors(FTheme, False, False, False, cListFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
    end
    else
    begin
      ResolveOverlayTextColors(FTheme, False, False, False, cListFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, StringOfChar(' ', InnerW), Fg, Bg);
    end;
  end;

  if (ScrollX > R.Left) and (ListBottom >= ListTop) then
    DrawPanelScrollBar(AGrid, ScrollX, ListTop, ListBottom,
      FScrollOffset, Length(FItems), ViewH, FTheme, not Assigned(FTheme));
end;

end.
