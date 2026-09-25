unit uHistoryPopup;

{ Drop-down history list for a one-line field outside dialogs: the panel
  command line, the live filter box, the viewer/editor "Find:" prompt.
  Same look and keys as a dialog DropDown / history input (TDialogHost):
  frame, highlighted row, scroll bar; Up/Down/PgUp/PgDn/Home/End move,
  Enter picks, Del forgets the entry, Esc closes, any other key closes the
  list and still reaches the field. A click on a row picks it, a click
  elsewhere closes.

  Coordinates are the host's grid cells. Open is given the field's row and
  column span; the list opens above the field (below when there is no room
  above). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes;

const
  cHistoryPopupMaxRows = 12;

type
  THistoryPopupKeyResult = (
    /// <summary>Not open: the key is the field's.</summary>
    hpkNotOpen,
    /// <summary>Handled inside the list (moved, deleted, closed by Esc).</summary>
    hpkHandled,
    /// <summary>Enter: APicked holds the entry; the list is closed.</summary>
    hpkPicked,
    /// <summary>Any other key: the list closed, the key goes on to the field.</summary>
    hpkPassOn
  );

  THistoryPopup = class
  private
    FVisible: Boolean;
    FItems: TArray<string>;
    FHover: Integer;
    FTop: Integer;
    FBounds: TRectI; // frame, grid cells
    FOnRemove: TProc<string>;
    function ViewHeight: Integer;
    procedure EnsureHoverInView;
  public
    /// <summary>Opens over / under the field at row AFieldRow, columns
    /// AFieldLeft..AFieldRight, inside an AAreaW x AAreaH grid. Starts on the
    /// entry equal to ACurrent, else the first. No-op with no items.</summary>
    procedure Open(const AItems: TArray<string>; const ACurrent: string;
      AFieldRow, AFieldLeft, AFieldRight, AAreaW, AAreaH: Integer);
    procedure Close;
    function HandleKey(var AKey: Word; AShift: TShiftState; var AKeyChar: Char;
      out APicked: string): THistoryPopupKeyResult;
    /// <summary>True when (ACol, ARow) is on the list: a row click sets
    /// APicked and closes (APickedValid = True). False = outside; the list
    /// is closed and the click belongs to whatever is under it.</summary>
    function HandleClick(ACol, ARow: Integer; out APicked: string;
      out APickedValid: Boolean): Boolean;
    procedure Draw(const AGrid: TTerminalGrid; const ATheme: IThemeRenderer);
    property Visible: Boolean read FVisible;
    property Items: TArray<string> read FItems;
    property Hover: Integer read FHover;
    property Bounds: TRectI read FBounds;
    /// <summary>Del: the host removes the entry from its store; the list
    /// drops it too.</summary>
    property OnRemove: TProc<string> read FOnRemove write FOnRemove;
  end;

implementation

uses
  uThemeDrawing;

procedure THistoryPopup.Open(const AItems: TArray<string>; const ACurrent: string;
  AFieldRow, AFieldLeft, AFieldRight, AAreaW, AAreaH: Integer);
var
  I, Rows, W, Left, Top, MaxLen: Integer;
begin
  Close;
  if Length(AItems) = 0 then
    Exit;
  FItems := Copy(AItems);
  FHover := 0;
  for I := 0 to High(FItems) do
    if SameText(FItems[I], ACurrent) then
    begin
      FHover := I;
      Break;
    end;
  // As wide as the field, at least wide enough for the longest entry that
  // fits the area.
  MaxLen := 0;
  for I := 0 to High(FItems) do
    MaxLen := Max(MaxLen, Length(FItems[I]));
  W := Max(AFieldRight - AFieldLeft + 1, Min(MaxLen + 3, AAreaW));
  W := EnsureRange(W, 10, Max(AAreaW, 10));
  Left := EnsureRange(AFieldLeft, 0, Max(AAreaW - W, 0));
  Rows := Min(Length(FItems), cHistoryPopupMaxRows);
  // Above the field when there is room, else below.
  if AFieldRow - (Rows + 2) >= 0 then
    Top := AFieldRow - (Rows + 2)
  else
  begin
    Top := AFieldRow + 1;
    Rows := Max(Min(Rows, AAreaH - Top - 2), 1);
  end;
  FBounds := TRectI.Make(Left, Top, Left + W - 1, Top + Rows + 1);
  FTop := 0;
  FVisible := True;
  EnsureHoverInView;
end;

procedure THistoryPopup.Close;
begin
  FVisible := False;
  SetLength(FItems, 0);
  FHover := 0;
  FTop := 0;
end;

function THistoryPopup.ViewHeight: Integer;
begin
  Result := Max(FBounds.Height - 2, 1);
end;

procedure THistoryPopup.EnsureHoverInView;
var
  ViewH: Integer;
begin
  ViewH := ViewHeight;
  FHover := EnsureRange(FHover, 0, Max(High(FItems), 0));
  if FHover < FTop then
    FTop := FHover;
  if FHover >= FTop + ViewH then
    FTop := FHover - ViewH + 1;
  FTop := EnsureRange(FTop, 0, Max(Length(FItems) - ViewH, 0));
end;

function THistoryPopup.HandleKey(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; out APicked: string): THistoryPopupKeyResult;
var
  Last: Integer;
  Removed: string;
begin
  APicked := '';
  if not FVisible then
    Exit(hpkNotOpen);
  Result := hpkHandled;
  Last := High(FItems);
  case AKey of
    vkUp: FHover := Max(FHover - 1, 0);
    vkDown:
      if (ssCtrl in AShift) or (ssAlt in AShift) then
        Close // the open chord again closes the list
      else
        FHover := Min(FHover + 1, Last);
    vkPrior: FHover := Max(FHover - ViewHeight, 0);
    vkNext: FHover := Min(FHover + ViewHeight, Last);
    vkHome: FHover := 0;
    vkEnd: FHover := Last;
    vkReturn:
      begin
        APicked := FItems[FHover];
        Close;
        Result := hpkPicked;
      end;
    vkEscape: Close;
    vkDelete:
      begin
        Removed := FItems[FHover];
        Delete(FItems, FHover, 1);
        if Assigned(FOnRemove) then
          FOnRemove(Removed);
        if Length(FItems) = 0 then
          Close;
      end;
  else
    if (AKey = 0) and (AKeyChar = #13) then
    begin
      APicked := FItems[FHover];
      Close;
      Result := hpkPicked;
    end
    else
    begin
      Close;
      Exit(hpkPassOn);
    end;
  end;
  if FVisible then
    EnsureHoverInView;
  AKey := 0;
  AKeyChar := #0;
end;

function THistoryPopup.HandleClick(ACol, ARow: Integer; out APicked: string;
  out APickedValid: Boolean): Boolean;
var
  Idx: Integer;
begin
  APicked := '';
  APickedValid := False;
  if not FVisible then
    Exit(False);
  if not FBounds.Contains(ACol, ARow) then
  begin
    Close;
    Exit(False);
  end;
  Result := True;
  if (ARow <= FBounds.Top) or (ARow >= FBounds.Bottom) then
    Exit; // frame
  Idx := FTop + (ARow - FBounds.Top - 1);
  if (Idx < 0) or (Idx > High(FItems)) then
    Exit;
  APicked := FItems[Idx];
  APickedValid := True;
  Close;
end;

procedure THistoryPopup.Draw(const AGrid: TTerminalGrid; const ATheme: IThemeRenderer);
var
  J, Idx, ViewH, TextW: Integer;
  Line: string;
  FrameFg, FrameBg, RowFg, RowBg: TAlphaColor;
  NeedBar: Boolean;
begin
  if not FVisible then
    Exit;
  // Same chrome as the dialog DropDown popup: white body, black frame.
  FrameFg := TAlphaColor($FF000000);
  FrameBg := TAlphaColor($FFFFFFFF);
  DrawPanelFrameGlyphs(AGrid, FBounds, chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV,
    FrameFg, FrameFg, FrameBg);
  ViewH := ViewHeight;
  NeedBar := Length(FItems) > ViewH;
  TextW := FBounds.Width - 2;
  if NeedBar then
    Dec(TextW);
  TextW := Max(TextW, 1);
  for J := 0 to ViewH - 1 do
  begin
    Idx := FTop + J;
    if Idx <= High(FItems) then
      Line := FItems[Idx]
    else
      Line := '';
    if Length(Line) > TextW then
      Line := Copy(Line, 1, TextW - 1) + WideChar($2026) // …
    else
      Line := Line + StringOfChar(' ', TextW - Length(Line));
    if Assigned(ATheme) then
      ATheme.ResolveDialogRowColors(Idx = FHover, RowFg, RowBg)
    else if Idx = FHover then
    begin
      RowFg := TAlphaColor($FF000000);
      RowBg := TAlphaColor($FF00AAAA);
    end
    else
    begin
      RowFg := FrameFg;
      RowBg := FrameBg;
    end;
    PutGridText(AGrid, FBounds.Left + 1, FBounds.Top + 1 + J, Line, RowFg, RowBg);
  end;
  if NeedBar then
    DrawDialogScrollBar(AGrid, FBounds.Right - 1, FBounds.Top + 1, FBounds.Bottom - 1,
      FTop, Length(FItems), ViewH);
end;

end.
