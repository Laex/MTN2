unit uHistoryPopup;

{ Drop-down history list for a one-line field outside dialogs: the panel
  command line, the live filter box, the viewer/editor "Find:" prompt.
  Same look and keys as a dialog DropDown / history input (TDialogHost):
  a frameless block with a shadow, highlighted row, scroll bar; Up/Down/PgUp/PgDn/Home/End move,
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
    FSuggest: Boolean;
    FItems: TArray<string>;
    FHover: Integer;
    FTop: Integer;
    FBounds: TRectI; // frame, grid cells
    FEdges: Boolean;  // outlined by cell edges rather than frame characters
    FHeader: Integer; // frame rows above the entries: 1 with characters, 0 with edges
    FBelow: Boolean;  // opened under the field
    FOnRemove: TProc<string>;
    function ViewHeight: Integer;
    procedure EnsureHoverInView;
    procedure RemoveHovered;
    function HandleSuggestKey(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char; out APicked: string): THistoryPopupKeyResult;
  public
    /// <summary>Opens over / under the field at row AFieldRow, columns
    /// AFieldLeft..AFieldRight, inside an AAreaW x AAreaH grid. Starts on the
    /// entry equal to ACurrent, else the first. No-op with no items.</summary>
    procedure Open(const AItems: TArray<string>; const ACurrent: string;
      AFieldRow, AFieldLeft, AFieldRight, AAreaW, AAreaH: Integer);
    /// <summary>Like Open, but as a suggestion list that does not take the
    /// keys from the field: nothing is highlighted until Up (the entry next
    /// to the field, the last one) or Down moves into it; Enter picks only a
    /// highlighted entry. Every other key goes on to the field and leaves
    /// the list open, so the host re-filters it after the edit. AItems are in
    /// display order, the last one nearest the field.</summary>
    procedure OpenSuggestions(const AItems: TArray<string>;
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
    property Suggesting: Boolean read FSuggest;
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
  // As wide as the field, at least wide enough for the longest entry; the left
  // edge stays at the field (right of the prompt), so a long entry is cut
  // with an ellipsis instead of pushing the block over the prompt.
  MaxLen := 0;
  for I := 0 to High(FItems) do
    MaxLen := Max(MaxLen, Length(FItems[I]));
  // The outline takes the cell left of the field, so the text lines up with
  // the field's own text.
  Left := EnsureRange(AFieldLeft - 1, 0, Max(AAreaW - 3, 0));
  W := Max(AFieldRight - Left + 1, MaxLen + 2 + 1);
  W := Min(W, Max(AAreaW - Left, 3));
  Rows := Min(Length(FItems), cHistoryPopupMaxRows);
  // Outlined by cell edges (left, right and the side away from the field), or,
  // where the host cannot draw them, by a frame row on top and frame cells at
  // the sides. Docked above the field when there is room, else below.
  FEdges := EdgeBordersActive;
  FHeader := Ord(not FEdges);
  if AFieldRow - Rows - FHeader >= 0 then
  begin
    Top := AFieldRow - Rows - FHeader;
    FBelow := False;
  end
  else
  begin
    Top := AFieldRow + 1;
    FBelow := True;
    Rows := Max(Min(Rows, AAreaH - Top - FHeader), 1);
  end;
  FBounds := TRectI.Make(Left, Top, Left + W - 1, Top + Rows - 1 + FHeader);
  FTop := 0;
  FVisible := True;
  EnsureHoverInView;
end;

procedure THistoryPopup.OpenSuggestions(const AItems: TArray<string>;
  AFieldRow, AFieldLeft, AFieldRight, AAreaW, AAreaH: Integer);
begin
  Open(AItems, '', AFieldRow, AFieldLeft, AFieldRight, AAreaW, AAreaH);
  if not FVisible then
    Exit;
  FSuggest := True;
  FHover := -1;
  FTop := Max(Length(FItems) - ViewHeight, 0);
end;

procedure THistoryPopup.Close;
begin
  FVisible := False;
  FSuggest := False;
  SetLength(FItems, 0);
  FHover := 0;
  FTop := 0;
end;

function THistoryPopup.ViewHeight: Integer;
begin
  Result := Max(FBounds.Height - FHeader, 1);
end;

procedure THistoryPopup.EnsureHoverInView;
var
  ViewH: Integer;
begin
  ViewH := ViewHeight;
  if FSuggest and (FHover < 0) then
    FHover := -1
  else
  begin
    FHover := EnsureRange(FHover, 0, Max(High(FItems), 0));
    if FHover < FTop then
      FTop := FHover;
    if FHover >= FTop + ViewH then
      FTop := FHover - ViewH + 1;
  end;
  FTop := EnsureRange(FTop, 0, Max(Length(FItems) - ViewH, 0));
end;

procedure THistoryPopup.RemoveHovered;
var
  Removed: string;
begin
  Removed := FItems[FHover];
  Delete(FItems, FHover, 1);
  if Assigned(FOnRemove) then
    FOnRemove(Removed);
  if Length(FItems) = 0 then
    Close;
end;

function THistoryPopup.HandleSuggestKey(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; out APicked: string): THistoryPopupKeyResult;
begin
  APicked := '';
  // Ctrl/Alt chords (the full-list chord among them) belong to the field.
  if (ssCtrl in AShift) or (ssAlt in AShift) then
    Exit(hpkPassOn);
  Result := hpkHandled;
  case AKey of
    vkUp:
      if FHover < 0 then
        FHover := High(FItems)
      else
        FHover := Max(FHover - 1, 0);
    vkDown:
      if FHover >= High(FItems) then
        FHover := -1
      else if FHover >= 0 then
        Inc(FHover);
    vkPrior:
      if FHover < 0 then
        Exit(hpkPassOn)
      else
        FHover := Max(FHover - ViewHeight, 0);
    vkNext:
      if FHover < 0 then
        Exit(hpkPassOn)
      else
        FHover := Min(FHover + ViewHeight, High(FItems));
    // Home/End edit the field until an entry is highlighted.
    vkHome:
      if FHover < 0 then
        Exit(hpkPassOn)
      else
        FHover := 0;
    vkEnd:
      if FHover < 0 then
        Exit(hpkPassOn)
      else
        FHover := High(FItems);
    vkEscape: Close;
    vkReturn, 0:
      if (AKey = vkReturn) or (AKeyChar = #13) then
      begin
        if FHover < 0 then
          Exit(hpkPassOn);
        APicked := FItems[FHover];
        Close;
        Result := hpkPicked;
      end
      else
        Exit(hpkPassOn);
    vkDelete:
      if FHover >= 0 then
        RemoveHovered
      else
        Exit(hpkPassOn);
  else
    Exit(hpkPassOn);
  end;
  if FVisible then
    EnsureHoverInView;
  AKey := 0;
  AKeyChar := #0;
end;

function THistoryPopup.HandleKey(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char; out APicked: string): THistoryPopupKeyResult;
var
  Last: Integer;
begin
  APicked := '';
  if not FVisible then
    Exit(hpkNotOpen);
  if FSuggest then
    Exit(HandleSuggestKey(AKey, AShift, AKeyChar, APicked));
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
    vkDelete: RemoveHovered;
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
  Idx := FTop + (ARow - FBounds.Top - FHeader);
  if ARow < FBounds.Top + FHeader then
    Exit;
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
  FrameFg, FrameBg, RowFg, RowBg, ListBg: TAlphaColor;
  NeedBar: Boolean;
begin
  if not FVisible then
    Exit;
  // Same chrome as the dialog DropDown popup: the frame takes the theme's
  // dialog body colours; without a theme, white body and black frame.
  if Assigned(ATheme) then
    ATheme.ResolveDialogRowColors(False, FrameFg, FrameBg)
  else
  begin
    FrameFg := TAlphaColor($FF000000);
    FrameBg := TAlphaColor($FFFFFFFF);
  end;
  if Assigned(ATheme) then
    ListBg := ATheme.ResolveDialogListBg
  else
    ListBg := FrameBg;
  DrawDialogShadow(AGrid, FBounds);
  ViewH := ViewHeight;
  NeedBar := Length(FItems) > ViewH;
  // The side cells (frame characters or the blank next to an edge line) take
  // one cell each; the scroll bar replaces the right one.
  TextW := Max(FBounds.Width - 2, 1);
  for J := 0 to ViewH - 1 do
  begin
    Idx := FTop + J;
    if Idx <= High(FItems) then
      Line := FItems[Idx]
    else
      Line := '';
    if Length(Line) > TextW then
      Line := Copy(Line, 1, TextW - 1) + WideChar($2026) // ...
    else
      Line := Line + StringOfChar(' ', TextW - Length(Line));
    if Assigned(ATheme) then
    begin
      ATheme.ResolveDialogRowColors(Idx = FHover, RowFg, RowBg);
      // The list background sets the frameless block apart from the dialog body.
      if Idx <> FHover then
        RowBg := ATheme.ResolveDialogListBg;
    end
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
    PutGridText(AGrid, FBounds.Left + 1, FBounds.Top + FHeader + J, Line, RowFg, RowBg);
    if FEdges then
    begin
      PutGridText(AGrid, FBounds.Left, FBounds.Top + J, ' ', RowFg, RowBg);
      PutGridText(AGrid, FBounds.Right, FBounds.Top + J, ' ', RowFg, RowBg);
    end
    else
    begin
      DrawGridChar(AGrid, FBounds.Left, FBounds.Top + FHeader + J, chDblV, FrameFg, ListBg);
      DrawGridChar(AGrid, FBounds.Right, FBounds.Top + FHeader + J, chDblV, FrameFg, ListBg);
    end;
  end;
  if not FEdges then
  begin
    DrawGridChar(AGrid, FBounds.Left, FBounds.Top, chDblTL, FrameFg, ListBg);
    DrawGridChar(AGrid, FBounds.Right, FBounds.Top, chDblTR, FrameFg, ListBg);
    for J := FBounds.Left + 1 to FBounds.Right - 1 do
      DrawGridChar(AGrid, J, FBounds.Top, chDblH, FrameFg, ListBg);
  end;
  if NeedBar then
    DrawDialogScrollBar(AGrid, FBounds.Right, FBounds.Top + FHeader, FBounds.Bottom,
      FTop, Length(FItems), ViewH);
  if FEdges then
  begin
    // Added last: writing text into a cell replaces the cell and its edges.
    for J := FBounds.Top to FBounds.Bottom do
    begin
      AddGridEdges(AGrid, FBounds.Left, J, [ceLeft], FrameFg);
      AddGridEdges(AGrid, FBounds.Right, J, [ceRight], FrameFg);
    end;
    // The side toward the field has no line: the field bounds the list there.
    for J := FBounds.Left to FBounds.Right do
      if FBelow then
        AddGridEdges(AGrid, J, FBounds.Bottom, [ceBottom], FrameFg)
      else
        AddGridEdges(AGrid, J, FBounds.Top, [ceTop], FrameFg);
  end;
end;

end.
