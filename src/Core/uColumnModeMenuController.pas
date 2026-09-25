unit uColumnModeMenuController;

{ NDN-style "Column modes" (Ctrl+` opens; Ctrl+Shift+F1..F6 jumps directly) popup. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelOverlays;

type
  TColumnModeSelectEvent = reference to procedure(AMode: TPanelColumnMode);
  TMenuPanelBoundsEvent = reference to function(ASide: TPanelSide): TRectI;
  TActiveSideEvent = reference to function: TPanelSide;

  TColumnModeMenuController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FOnColumnModeSelect: TColumnModeSelectEvent;
    FGetActivePanelBounds: TMenuPanelBoundsEvent;
    FGetActiveSide: TActiveSideEvent;
    FVisible: Boolean;
    FItems: TArray<TColumnModeMenuItem>;
    FIndex: Integer;
    FBounds: TRectI;
    FCurrent: TPanelColumnMode;
    procedure BuildItems;
    function IndexOf(AMode: TPanelColumnMode): Integer;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AGetActivePanelBounds: TMenuPanelBoundsEvent;
      const AGetActiveSide: TActiveSideEvent);
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure SetOnColumnModeSelect(const AHandler: TColumnModeSelectEvent);
    procedure Open(ACurrent: TPanelColumnMode);
    procedure Close;
    procedure Layout;
    procedure Draw(const AGrid: TTerminalGrid);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
    property Visible: Boolean read FVisible;
    property Bounds: TRectI read FBounds;
  end;

implementation

uses
  uStrings;

const
  cCursorFg = TAlphaColor($FF000000);
  cCursorBg = TAlphaColor($FF00AAAA);
  cFileFg   = TAlphaColor($FFAAAAAA);
  cPanelBg  = TAlphaColor($FF0000AA);
  cFrameActive = TAlphaColor($FF55FFFF);
  cSortHot  = TAlphaColor($FFFF55FF); // raspberry/magenta — readable on blue

constructor TColumnModeMenuController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AGetActivePanelBounds: TMenuPanelBoundsEvent;
  const AGetActiveSide: TActiveSideEvent);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FGetActivePanelBounds := AGetActivePanelBounds;
  FGetActiveSide := AGetActiveSide;
end;

procedure TColumnModeMenuController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

procedure TColumnModeMenuController.SetOnColumnModeSelect(
  const AHandler: TColumnModeSelectEvent);
begin
  FOnColumnModeSelect := AHandler;
end;

procedure TColumnModeMenuController.BuildItems;

  // AKey: columnModeMenu.<AKey> in strings/<locale>.json; a translation
  // marks its hotkey with '&' (MenuResolveMnemonic).
  procedure Add(const AKey, ACaption: string; AHot: Char; const AShortcut: string;
    AMode: TPanelColumnMode);
  var
    N: Integer;
    Cap: string;
    Hot: Char;
  begin
    N := Length(FItems);
    SetLength(FItems, N + 1);
    Cap := T('columnModeMenu.' + AKey, ACaption);
    Hot := AHot;
    MenuResolveMnemonic(Cap, Hot, FItems[N].HotPos);
    FItems[N].Caption := Cap;
    FItems[N].HotChar := Hot;
    FItems[N].Shortcut := AShortcut;
    FItems[N].Mode := AMode;
  end;

begin
  SetLength(FItems, 0);
  Add('brief', 'Brief', 'B', 'Ctrl+Shift+F1', pcmBrief);
  Add('size', 'Size', 'S', 'Ctrl+Shift+F2', pcmSize);
  Add('date', 'Date', 'D', 'Ctrl+Shift+F3', pcmDate);
  Add('full', 'Full', 'F', 'Ctrl+Shift+F4', pcmFull);
  Add('created', 'Created', 'C', 'Ctrl+Shift+F5', pcmCreated);
  Add('types', 'Types', 'T', 'Ctrl+Shift+F6', pcmTypes);
  Add('custom', 'Custom', 'X', 'Ctrl+Shift+F7', pcmCustom);
end;

function TColumnModeMenuController.IndexOf(AMode: TPanelColumnMode): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].Mode = AMode then
      Exit(I);
  Result := 0;
end;

procedure TColumnModeMenuController.Open(ACurrent: TPanelColumnMode);
begin
  FCurrent := ACurrent;
  BuildItems;
  FIndex := IndexOf(ACurrent);
  FVisible := True;
  Layout;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TColumnModeMenuController.Close;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  SetLength(FItems, 0);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TColumnModeMenuController.Layout;
var
  PanelBounds: TRectI;
  W, H, MaxW, I, RowW: Integer;
begin
  PanelBounds := FGetActivePanelBounds(FGetActiveSide);
  MaxW := Length(T('ui.columnModeMenu.title', 'Column modes')) + 2;
  for I := 0 to High(FItems) do
  begin
    RowW := 2 + Length(FItems[I].Caption) + 2;
    if FItems[I].Shortcut <> '' then
      Inc(RowW, Length(FItems[I].Shortcut) + 2);
    if RowW > MaxW then
      MaxW := RowW;
  end;
  W := MaxW + 2;
  if W > PanelBounds.Width - 1 then
    W := Max(PanelBounds.Width - 1, 24);
  H := Length(FItems) + 2;
  if H > PanelBounds.Height - 1 then
    H := Max(PanelBounds.Height - 1, 3);
  FBounds := TRectI.Make(
    PanelBounds.Left + 2,
    PanelBounds.Top + 2,
    PanelBounds.Left + 2 + W - 1,
    PanelBounds.Top + 2 + H - 1);
end;

procedure TColumnModeMenuController.Draw(const AGrid: TTerminalGrid);
var
  R: TRectI;
  I, Y, InnerW, CapW, HotPos: Integer;
  Mark, Cap, Line, Short: string;
  Fg, Bg, HotFg: TAlphaColor;
  Ch: Char;
begin
  if not FVisible then
    Exit;
  Layout;
  R := FBounds;
  if (R.Width < 10) or (R.Height < 3) then
    Exit;
  DrawHostOverlayFrame(AGrid, FTheme, R, T('ui.columnModeMenu.title', 'Column modes'),
    cFileFg, cPanelBg, cFrameActive, cCursorFg);
  InnerW := R.Width - 2;
  for I := 0 to High(FItems) do
  begin
    Y := R.Top + 1 + I;
    if Y >= R.Bottom then
      Break;
    if FItems[I].Mode = FCurrent then
      Mark := #$25CF // ●
    else
      Mark := ' ';
    Cap := FItems[I].Caption;
    Short := FItems[I].Shortcut;
    CapW := InnerW - 2;
    if Short <> '' then
      CapW := Max(CapW - Length(Short) - 1, 4);
    if Length(Cap) > CapW then
      Cap := Copy(Cap, 1, CapW)
    else
      while Length(Cap) < CapW do
        Cap := Cap + ' ';
    Line := Mark + ' ' + Cap;
    if Short <> '' then
      Line := Line + ' ' + Short;
    if Length(Line) > InnerW then
      Line := Copy(Line, 1, InnerW);
    while Length(Line) < InnerW do
      Line := Line + ' ';

    if I = FIndex then
      ResolveOverlayTextColors(FTheme, False, False, True, cCursorFg, cCursorBg, Fg, Bg)
    else
      ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
    PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);

    // Position resolved once in BuildItems (a '&' can point past an earlier
    // occurrence of the same letter).
    HotPos := FItems[I].HotPos;
    if (HotPos > 0) and (HotPos <= Min(Length(FItems[I].Caption), CapW)) then
    begin
      Ch := FItems[I].Caption[HotPos];
      if I = FIndex then
        HotFg := Fg
      else
        HotFg := cSortHot;
      PutGridText(AGrid, R.Left + 1 + 2 + HotPos - 1, Y, Ch, HotFg, Bg);
    end;
  end;
end;

function TColumnModeMenuController.HandleInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  I: Integer;
  Ch: Char;
  Pass: Boolean;
begin
  Result := True;
  if AKey = vkEscape then
  begin
    Close;
    AKey := 0;
    Exit;
  end;
  if AKey = vkUp then
  begin
    if FIndex > 0 then
      Dec(FIndex);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkDown then
  begin
    if FIndex < High(FItems) then
      Inc(FIndex);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkReturn then
  begin
    if (FIndex >= 0) and (FIndex <= High(FItems)) then
    begin
      if Assigned(FOnColumnModeSelect) then
        FOnColumnModeSelect(FItems[FIndex].Mode);
      Close;
    end;
    AKey := 0;
    Exit;
  end;
  // Ctrl+Shift+F1..Ctrl+Shift+F6: jump straight to that mode. Checked on the
  // raw VK (not AKeyChar) since held modifiers often suppress character
  // translation — same convention as the outer Ctrl+` binding that opens
  // this menu. Ctrl+Alt+F1..F6 was tried first but collides with global
  // hotkeys some terminal emulators (e.g. ConEmu) register system-wide;
  // Ctrl+Shift+F1..F6 is a different chord from that.
  if (ssCtrl in AShift) and (ssShift in AShift) and
     (AKey >= vkF1) and (AKey <= vkF6) then
  begin
    I := AKey - vkF1;
    if (I >= 0) and (I <= High(FItems)) then
    begin
      if Assigned(FOnColumnModeSelect) then
        FOnColumnModeSelect(FItems[I].Mode);
      Close;
      AKey := 0;
      AKeyChar := #0;
      Exit;
    end;
  end;
  Ch := AKeyChar;
  if Ch <> #0 then
  begin
    // Exact letter first, then the same key on the other keyboard layout.
    for Pass := False to True do
      for I := 0 to High(FItems) do
        if MenuHotKeyMatches(FItems[I].HotChar, Ch, Pass) then
        begin
          if Assigned(FOnColumnModeSelect) then
            FOnColumnModeSelect(FItems[I].Mode);
          Close;
          AKey := 0;
          AKeyChar := #0;
          Exit;
        end;
  end;
  AKey := 0;
  AKeyChar := #0;
end;

function TColumnModeMenuController.HandleClick(ALocalCol,
  ALocalRow: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if not FVisible then
    Exit;
  Layout;
  if WindowFrameCloseHit(FBounds, ALocalCol, ALocalRow) then
  begin
    Close;
    Result := True;
    Exit;
  end;
  if FBounds.Contains(ALocalCol, ALocalRow) then
  begin
    Idx := ALocalRow - (FBounds.Top + 1);
    if (Idx >= 0) and (Idx <= High(FItems)) then
    begin
      FIndex := Idx;
      if Assigned(FOnColumnModeSelect) then
        FOnColumnModeSelect(FItems[Idx].Mode);
      Close;
    end;
    Result := True;
    Exit;
  end;
  Close;
  Result := True;
end;

end.
