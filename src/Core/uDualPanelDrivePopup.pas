unit uDualPanelDrivePopup;

{ Change Drive overlay (Alt+F1/F2). Extracted from TDualPanelWindow. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelOverlays, uDriveInfo, uVfsTypes, uDualPanelDrawUtils;

type
  TPanelBoundsEvent = reference to function(ASide: TPanelSide): TRectI;
  TPanelPathEvent = reference to function(ASide: TPanelSide): string;
  TPanelDriveDirsEvent = reference to function(ASide: TPanelSide): TPanelDriveDirs;
  TPanelNavigateEvent = reference to procedure(ASide: TPanelSide; const AURI: string);

  TDrivePopupController = class
  private
    FTheme: IThemeRenderer;
    FOnInvalidate: TProc;
    FGetPanelBounds: TPanelBoundsEvent;
    FGetCurrentPath: TPanelPathEvent;
    FGetDriveDirs: TPanelDriveDirsEvent;
    FOnNavigate: TPanelNavigateEvent;
    FState: TDrivePopupState;
    procedure HandleDriveInfoRefreshed;
  public
    constructor Create(const ATheme: IThemeRenderer; const AOnInvalidate: TProc;
      const AGetPanelBounds: TPanelBoundsEvent;
      const AGetCurrentPath: TPanelPathEvent;
      const AGetDriveDirs: TPanelDriveDirsEvent;
      const AOnNavigate: TPanelNavigateEvent);
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure Close;
    procedure MoveCursorAndInvalidate;
    procedure EnsureScroll;
    procedure Layout;
    procedure Open(ASide: TPanelSide);
    procedure Toggle(ASide: TPanelSide);
    procedure Confirm;
    procedure Draw(const AGrid: TTerminalGrid);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
    property Visible: Boolean read FState.Visible;
    property Side: TPanelSide read FState.Side;
    property Bounds: TRectI read FState.Bounds;
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

  // Numbered extras below the drive list come from ChangeDriveSpecial* in
  // uDriveInfo so the panel drive bar and this popup stay on one catalog.

constructor TDrivePopupController.Create(const ATheme: IThemeRenderer;
  const AOnInvalidate: TProc; const AGetPanelBounds: TPanelBoundsEvent;
  const AGetCurrentPath: TPanelPathEvent;
  const AGetDriveDirs: TPanelDriveDirsEvent;
  const AOnNavigate: TPanelNavigateEvent);
begin
  inherited Create;
  FTheme := ATheme;
  FOnInvalidate := AOnInvalidate;
  FGetPanelBounds := AGetPanelBounds;
  FGetCurrentPath := AGetCurrentPath;
  FGetDriveDirs := AGetDriveDirs;
  FOnNavigate := AOnNavigate;
  FState.Visible := False;
  FState.ScrollOffset := 0;
end;

procedure TDrivePopupController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

procedure TDrivePopupController.Close;
begin
  if not FState.Visible then
    Exit;
  FState.Visible := False;
  SetLength(FState.Drives, 0);
  FState.ScrollOffset := 0;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

// Shared tail of every cursor-move key in HandleInput: re-clamp the scroll
// window to the new cursor position, then repaint.
procedure TDrivePopupController.MoveCursorAndInvalidate;
begin
  EnsureScroll;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TDrivePopupController.EnsureScroll;
var
  ViewH, TotalItems: Integer;
begin
  ViewH := FState.Bounds.Height - 3;
  if ViewH < 1 then
    ViewH := 1;
  if FState.CursorIndex < FState.ScrollOffset then
    FState.ScrollOffset := FState.CursorIndex;
  if FState.CursorIndex >= FState.ScrollOffset + ViewH then
    FState.ScrollOffset := FState.CursorIndex - ViewH + 1;
  if FState.ScrollOffset < 0 then
    FState.ScrollOffset := 0;
  TotalItems := Length(FState.Drives) + ChangeDriveSpecialCount + 1;
  if (TotalItems > 0) and
     (FState.ScrollOffset > TotalItems - ViewH) then
    FState.ScrollOffset := Max(TotalItems - ViewH, 0);
end;

procedure TDrivePopupController.Layout;
var
  PanelBounds: TRectI;
  W, H, MaxList, Count, TotalItems: Integer;
begin
  PanelBounds := FGetPanelBounds(FState.Side);
  Count := Length(FState.Drives);
  // TotalItems includes drives + 1 separator line + the special items below it
  TotalItems := Count + ChangeDriveSpecialCount + 1;
  W := Min(72, Max(PanelBounds.Width - 2, 40));
  if W > PanelBounds.Width - 1 then
    W := Max(PanelBounds.Width - 1, 24);
  MaxList := Max(PanelBounds.Height - 4, 3);
  H := Min(Max(TotalItems, 1), MaxList) + 3;
  if H < 5 then
    H := 5;
  if H > PanelBounds.Height - 1 then
    H := Max(PanelBounds.Height - 1, 5);
  FState.Bounds := TRectI.Make(
    PanelBounds.Left + Max((PanelBounds.Width - W) div 2, 1),
    PanelBounds.Top + Max((PanelBounds.Height - H) div 2, 1),
    PanelBounds.Left + Max((PanelBounds.Width - W) div 2, 1) + W - 1,
    PanelBounds.Top + Max((PanelBounds.Height - H) div 2, 1) + H - 1);
  EnsureScroll;
end;

procedure TDrivePopupController.HandleDriveInfoRefreshed;
begin
  // A stale callback from a previous Open (popup closed, or reopened for the
  // other side) must not repaint a hidden/unrelated state.
  if not FState.Visible then
    Exit;
  FState.Drives := CachedDriveInfo(nil);
  EnsureScroll;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TDrivePopupController.Open(ASide: TPanelSide);
begin
  FState.Side := ASide;
  // Instant, non-blocking: shows the last-known (or letters-only, on first
  // ever open) info immediately; HandleDriveInfoRefreshed repaints once the
  // background GetVolumeInformation/GetDiskFreeSpaceEx pass lands, instead of
  // freezing the UI thread for however long an unresponsive drive takes.
  FState.Drives := CachedDriveInfo(HandleDriveInfoRefreshed);
  FState.ScrollOffset := 0;
  FState.CursorIndex := DrivePopupCursorIndex(FState.Drives, FGetCurrentPath(ASide));
  FState.Visible := True;
  Layout;
  EnsureScroll;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TDrivePopupController.Toggle(ASide: TPanelSide);
begin
  if FState.Visible and (FState.Side = ASide) then
    Close
  else
    Open(ASide);
end;

procedure TDrivePopupController.Confirm;
var
  Idx: Integer;
  TargetURI: string;
  Side: TPanelSide;
  SpecialIdx: Integer;
begin
  if not FState.Visible then
    Exit;
  Side := FState.Side;
  // If cursor is on one of the special items below the separator line
  // (indices Length(Drives) + 1 .. Length(Drives) + ChangeDriveSpecialCount)
  SpecialIdx := FState.CursorIndex - (Length(FState.Drives) + 1);
  if (SpecialIdx >= 0) and (SpecialIdx < ChangeDriveSpecialCount) then
  begin
    TargetURI := ChangeDriveSpecialUris[SpecialIdx];
    Close;
    if Assigned(FOnNavigate) then
      FOnNavigate(Side, TargetURI);
    Exit;
  end;

  if Length(FState.Drives) = 0 then
  begin
    Close;
    Exit;
  end;
  Idx := EnsureRange(FState.CursorIndex, 0, High(FState.Drives));
  TargetURI := ResolvePanelDriveUri(FGetDriveDirs(Side),
    FState.Drives[Idx].Letter, FState.Drives[Idx].RootPath);
  Close;
  if Assigned(FOnNavigate) then
    FOnNavigate(Side, TargetURI);
end;

procedure TDrivePopupController.Draw(const AGrid: TTerminalGrid);
var
  R: TRectI;
  I, Y, Idx, InnerW, ListTop, ListBottom, ViewH, Count, StatusY, ScrollX: Integer;
  Line, Status: string;
  Fg, Bg: TAlphaColor;
  CurGlyph: Char;
  IsCur: Boolean;
  SpecialIdx: Integer;
begin
  if not FState.Visible then
    Exit;
  Layout;
  R := FState.Bounds;
  if (R.Width < 20) or (R.Height < 5) then
    Exit;

  DrawHostOverlayFrame(AGrid, FTheme, R, T('ui.drivePopup.title', 'Change Drive'),
    cFileFg, cPanelBg, cFrameActive, cCursorFg);

  CurGlyph := DriveBarGlyphFromUri(FGetCurrentPath(FState.Side));

  ListTop := R.Top + 1;
  StatusY := R.Bottom - 1;
  ListBottom := StatusY - 1;
  ViewH := Max(ListBottom - ListTop + 1, 1);
  ScrollX := R.Right - 1;
  InnerW := Max(ScrollX - (R.Left + 1), 16);
  Count := Length(FState.Drives);
  EnsureScroll;

  for I := 0 to ViewH - 1 do
  begin
    Y := ListTop + I;
    if Y > ListBottom then
      Break;
    Idx := FState.ScrollOffset + I;
    if Idx < Length(FState.Drives) then
    begin
      IsCur := FState.Drives[Idx].Letter = CurGlyph;
      Line := FormatDrivePopupLine(FState.Drives[Idx], IsCur, InnerW);
      if Idx = FState.CursorIndex then
        ResolveOverlayTextColors(FTheme, False, False, True, cCursorFg, cCursorBg, Fg, Bg)
      else
        ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
    end
    else if Idx = Length(FState.Drives) then
    begin
      ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
      Line := StringOfChar(chBoxH, InnerW);
      PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
    end
    else if (Idx - (Length(FState.Drives) + 1) >= 0) and
            (Idx - (Length(FState.Drives) + 1) < ChangeDriveSpecialCount) then
    begin
      SpecialIdx := Idx - (Length(FState.Drives) + 1);
      IsCur := CurGlyph = ChangeDriveSpecialGlyph(SpecialIdx);
      if IsCur then
        Line := Format('* %d. %s', [SpecialIdx + 1,
          ChangeDriveSpecialTitle(SpecialIdx)])
      else
        Line := Format('  %d. %s', [SpecialIdx + 1,
          ChangeDriveSpecialTitle(SpecialIdx)]);
      if Length(Line) < InnerW - 1 then
        Line := Line + StringOfChar(' ', (InnerW - 1) - Length(Line));
      Line := Copy(Line, 1, InnerW - 1) + ' ';
      if Idx = FState.CursorIndex then
        ResolveOverlayTextColors(FTheme, False, False, True, cCursorFg, cCursorBg, Fg, Bg)
      else
        ResolveOverlayTextColors(FTheme, True, False, False, cFileFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, Line, Fg, Bg);
    end
    else
    begin
      ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
      PutGridText(AGrid, R.Left + 1, Y, StringOfChar(' ', InnerW), Fg, Bg);
    end;
  end;

  if (ScrollX > R.Left) and (ListBottom >= ListTop) then
    // ADialogStyle forces the white FAR-dialog track only when no theme is
    // assigned; an assigned theme paints its own scrollbar via ATheme.
    DrawPanelScrollBar(AGrid, ScrollX, ListTop, ListBottom,
      FState.ScrollOffset, Count + ChangeDriveSpecialCount + 1, ViewH, FTheme,
      not Assigned(FTheme));

  if Count = 0 then
    Status := '0 / 0'
  else
    Status := Format('%d / %d', [Min(FState.CursorIndex + 1, Count), Count]);
  if Length(Status) > InnerW then
    Status := Copy(Status, 1, InnerW);
  while Length(Status) < InnerW do
    Status := Status + ' ';
  ResolveOverlayTextColors(FTheme, False, False, False, cFileFg, cPanelBg, Fg, Bg);
  PutGridText(AGrid, R.Left + 1, StatusY, Status, Fg, Bg);
  if ScrollX > R.Left then
    DrawGridChar(AGrid, ScrollX, StatusY, ' ', Fg, Bg);
end;

function TDrivePopupController.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Ch: Char;
  I, ViewH: Integer;
begin
  Result := True;
  ViewH := Max(FState.Bounds.Height - 3, 1);

  if AKey = vkEscape then
  begin
    Close;
    AKey := 0;
    Exit;
  end;
  if AKey = vkReturn then
  begin
    Confirm;
    AKey := 0;
    Exit;
  end;
  if AKey = vkUp then
  begin
    if FState.CursorIndex > 0 then
    begin
      Dec(FState.CursorIndex);
      // Skip separator line (index = Length(Drives))
      if FState.CursorIndex = Length(FState.Drives) then
        Dec(FState.CursorIndex);
    end
    else
      // Wrap from the first item to the last (last special item, or last
      // drive when there are no special items to land on).
      FState.CursorIndex := Length(FState.Drives) + ChangeDriveSpecialCount;
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkDown then
  begin
    if FState.CursorIndex < Length(FState.Drives) + ChangeDriveSpecialCount then
    begin
      Inc(FState.CursorIndex);
      // Skip separator line (index = Length(Drives))
      if FState.CursorIndex = Length(FState.Drives) then
        Inc(FState.CursorIndex);
    end
    else
      // Wrap from the last item back to the first.
      FState.CursorIndex := 0;
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkPrior then
  begin
    Dec(FState.CursorIndex, ViewH);
    if FState.CursorIndex < 0 then
      FState.CursorIndex := 0;
    if FState.CursorIndex = Length(FState.Drives) then
      Dec(FState.CursorIndex);
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkNext then
  begin
    Inc(FState.CursorIndex, ViewH);
    if FState.CursorIndex > Length(FState.Drives) + ChangeDriveSpecialCount then
      FState.CursorIndex := Length(FState.Drives) + ChangeDriveSpecialCount;
    if FState.CursorIndex = Length(FState.Drives) then
      Inc(FState.CursorIndex);
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkHome then
  begin
    FState.CursorIndex := 0;
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;
  if AKey = vkEnd then
  begin
    FState.CursorIndex := Length(FState.Drives) + ChangeDriveSpecialCount;
    MoveCursorAndInvalidate;
    AKey := 0;
    Exit;
  end;

  // Digit keys 1..ChangeDriveSpecialCount jump straight to the matching numbered
  // item below the separator and confirm it, mirroring the letter shortcuts
  // for drives below.
  if (AKeyChar >= '1') and (AKeyChar <= Chr(Ord('0') + ChangeDriveSpecialCount)) then
  begin
    FState.CursorIndex := Length(FState.Drives) + 1 + (Ord(AKeyChar) - Ord('1'));
    EnsureScroll;
    Confirm;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;

  Ch := UpCase(AKeyChar);
  if (Ch < 'A') or (Ch > 'Z') then
    if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
      Ch := Char(AKey)
    else if (AKey >= Ord('a')) and (AKey <= Ord('z')) then
      Ch := UpCase(Char(AKey));
  if (Ch >= 'A') and (Ch <= 'Z') then
  begin
    for I := 0 to High(FState.Drives) do
      if FState.Drives[I].Letter = Ch then
      begin
        FState.CursorIndex := I;
        EnsureScroll;
        Confirm;
        AKey := 0;
        AKeyChar := #0;
        Exit;
      end;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
end;

function TDrivePopupController.HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
var
  Idx, ListTop, ListBottom, StatusY, ScrollX, ViewH: Integer;
begin
  Result := True;
  if WindowFrameCloseHit(FState.Bounds, ALocalCol, ALocalRow) then
  begin
    Close;
    Exit;
  end;
  if not FState.Bounds.Contains(ALocalCol, ALocalRow) then
  begin
    Close;
    Exit;
  end;

  ListTop := FState.Bounds.Top + 1;
  StatusY := FState.Bounds.Bottom - 1;
  ListBottom := StatusY - 1;
  ScrollX := FState.Bounds.Right - 1;
  ViewH := Max(ListBottom - ListTop + 1, 1);

  if (ALocalCol = ScrollX) and (ALocalRow >= ListTop) and (ALocalRow <= ListBottom) then
  begin
    if ALocalRow = ListTop then
    begin
      if FState.CursorIndex > 0 then
        Dec(FState.CursorIndex);
    end
    else if ALocalRow = ListBottom then
    begin
      if FState.CursorIndex < High(FState.Drives) then
        Inc(FState.CursorIndex);
    end
    else if ALocalRow < (ListTop + ListBottom) div 2 then
    begin
      Dec(FState.CursorIndex, ViewH);
      if FState.CursorIndex < 0 then
        FState.CursorIndex := 0;
    end
    else
    begin
      Inc(FState.CursorIndex, ViewH);
      if FState.CursorIndex > High(FState.Drives) then
        FState.CursorIndex := Max(High(FState.Drives), 0);
    end;
    MoveCursorAndInvalidate;
    Exit;
  end;

  if (ALocalRow < ListTop) or (ALocalRow >= StatusY) then
    Exit;
  Idx := FState.ScrollOffset + (ALocalRow - ListTop);
  if (Idx >= 0) and (Idx <= Length(FState.Drives) + ChangeDriveSpecialCount) and
     (Idx <> Length(FState.Drives)) then
  begin
    FState.CursorIndex := Idx;
    Confirm;
  end;
end;

end.
