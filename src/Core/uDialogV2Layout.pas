unit uDialogV2Layout;

{ Protocol 2 dialog layout. The caller supplies the frame, the controls, the
  focus and the scroll it already has. Nothing here writes host fields: a
  wheel drag survives as long as the focus stays the same. }

interface

uses
  System.SysUtils, uDialogTypes, uThemeTypes;

type
  TDialogV2Layout = record
    Bounds: TArray<TRectI>;
    ContentH: Integer;
    ScrollY: Integer;
    ScrollFollow: Integer;
  end;

/// <summary>How many rows a control occupies in a flow or protocol-2 layout.
/// A list is its item count, a radio group adds a row for its caption.</summary>
function ControlRowSpan(const C: TDialogControl): Integer;

/// <summary>Cells a protocol-1 button takes, including the padding around
/// its caption.</summary>
function ButtonCellWidth(const C: TDialogControl): Integer;

/// <summary>Narrowest box a control keeps when a dialog authored wider than the
/// screen is squeezed: its caption or items, or a few cells for a field.</summary>
function ControlMinWidth(const C: TDialogControl): Integer;

/// <summary>Places every control inside AFrame. A control that is not wholly
/// in a scrolling view is given an empty rectangle, except a list or a radio
/// group, which is cut to the view. ScrollY moves only when AFocus differs
/// from AScrollFollow.</summary>
function LayoutDialogV2(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI; AFocus, AScrollY, AScrollFollow: Integer): TDialogV2Layout;

implementation

uses
  System.Math, uCharWidth, uColorPickerControl, uDatePickerControl, uDialogTabs;

function ControlRowSpan(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckList:
      begin
        Result := Length(C.Items);
        if Result < 1 then
          Result := 1;
      end;
    dckRadioGroup:
      begin
        Result := Length(C.Items);
        if C.Text <> '' then
          Inc(Result);
        if Result < 1 then
          Result := 1;
      end;
    dckColorPicker:
      Result := cPickerHeight;
    dckDatePicker:
      Result := cCalendarHeight;
  else
    Result := 1;
  end;
end;

function ButtonCellWidth(const C: TDialogControl): Integer;
begin
  Result := Min(14, Max(TextDisplayWidth(StripHotKeyMarker(C.Text)) + 6, 10));
end;

function DefaultControlWidth(const C: TDialogControl; AClientW: Integer): Integer;
var
  I: Integer;
begin
  case C.Kind of
    dckButton:
      Result := ButtonCellWidth(C);
    dckCheckbox, dckRadio:
      Result := Min(AClientW, Max(TextDisplayWidth(StripHotKeyMarker(C.Text)) + 4, 8));
    dckLabel, dckStatus:
      Result := Min(AClientW, Max(TextDisplayWidth(C.Text), 1));
    dckDropDown:
      begin
        Result := 12;
        for I := 0 to High(C.Items) do
          if TextDisplayWidth(C.Items[I]) + 2 > Result then
            Result := TextDisplayWidth(C.Items[I]) + 2;
        Result := Min(AClientW, Max(Result, 8));
      end;
    dckColorPicker:
      Result := Min(AClientW, cPickerWidth);
    dckDatePicker:
      Result := Min(AClientW, cCalendarWidth);
    dckTab:
      begin
        if C.Vertical then
          Result := DialogTabColumnWidth(C)
        else
        begin
          Result := 0;
          for I := 0 to High(C.Items) do
            Inc(Result, TextDisplayWidth(C.Items[I]) + 4);
        end;
        Result := Min(AClientW, Max(Result, 1));
      end;
  else
    Result := Max(AClientW, 1);
  end;
end;

function DefaultControlHeight(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckList, dckRadioGroup:
      Result := ControlRowSpan(C);
    dckDropDown:
      Result := 1;
    dckTab:
      if C.Vertical then
        Result := Max(Length(C.Items), 1)
      else
        Result := 1;
    dckColorPicker:
      Result := cPickerHeight;
    dckDatePicker:
      Result := cCalendarHeight;
  else
    Result := 1;
  end;
end;

function ControlMinWidth(const C: TDialogControl): Integer;
const
  // A caption longer than this may be cut when the dialog is squeezed.
  cMinLabelCut = 30;
var
  I: Integer;
begin
  Result := C.BoxW;
  case C.Kind of
    dckInput, dckStatus:
      Result := Min(C.BoxW, 8);
    dckList:
      Result := Min(C.BoxW, 10);
    dckLabel:
      if IsHRuleText(C.Text) then
        Result := Min(C.BoxW, 1)
      else
        Result := Min(C.BoxW, Min(Max(TextDisplayWidth(C.Text), 1), cMinLabelCut));
    dckButton:
      Result := Min(C.BoxW, TextDisplayWidth(StripHotKeyMarker(C.Text)) + 4);
    dckCheckbox, dckRadio:
      Result := Min(C.BoxW, Max(TextDisplayWidth(StripHotKeyMarker(C.Text)) + 4, 8));
    dckDropDown:
      begin
        Result := 6;
        for I := 0 to High(C.Items) do
          Result := Max(Result, TextDisplayWidth(C.Items[I]) + 2);
        Result := Min(C.BoxW, Result);
      end;
  end;
end;

// Squeezes the columns of a dialog that is authored wider than its frame by
// dropping single columns. A column may go only while every control that spans
// it still has spare cells (its box minus ControlMinWidth). Columns of fields,
// lists and rules go first, then the spare cells of other boxes, then the gaps
// nothing covers; within a kind the dropped columns are spread out evenly.
// ALefts and AWidths hold each control's column and width in the squeezed
// frame; a row of buttons that was centered stays centered.
procedure SqueezeColumns(const AControls: TArray<TDialogControl>; AClientW: Integer;
  out ALefts, AWidths: TArray<Integer>);
var
  I, X, Lv, K, Extent, Excess, CX, CW, Row, BestX, BestLv, BestDist, Dist: Integer;
  Pass, Hurt, BestHurt, Total, Target: Integer;
  Level, Slack: TArray<Integer>;
  Removed: TArray<Boolean>;
  NewX: TArray<Integer>;
  C: TDialogControl;
  Better, Shown: Boolean;
  MinL, MaxR, Shift: Integer;
begin
  SetLength(ALefts, Length(AControls));
  SetLength(AWidths, Length(AControls));
  SetLength(Slack, Length(AControls));
  Extent := 0;
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    ALefts[I] := Max(C.Col, 0);
    AWidths[I] := C.BoxW;
    Slack[I] := 0;
    if (C.BoxW > 0) and not DialogControlHiddenByTab(AControls, I) then
    begin
      Extent := Max(Extent, ALefts[I] + C.BoxW);
      Slack[I] := Max(C.BoxW - ControlMinWidth(C), 0);
    end;
  end;
  // Text that reaches the last cell is pulled in by one cell later on.
  for I := 0 to High(AControls) do
    if (Slack[I] > 0) and (ALefts[I] + AControls[I].BoxW = Extent) and
       (AControls[I].Kind in [dckLabel, dckCheckbox, dckRadio, dckDropDown]) and
       not ((AControls[I].Kind = dckLabel) and IsHRuleText(AControls[I].Text)) then
      Dec(Slack[I]);
  Excess := Extent - AClientW;
  if Excess <= 0 then
    Exit;

  // 1: spare cells of fields and rules, 2: of other boxes, 3: no control.
  SetLength(Level, Extent);
  for X := 0 to Extent - 1 do
    Level[X] := 3;
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    if (C.BoxW <= 0) or DialogControlHiddenByTab(AControls, I) then
      Continue;
    if C.Kind in [dckInput, dckList, dckStatus, dckLabel] then
      Lv := 1
    else
      Lv := 2;
    for X := ALefts[I] to Min(ALefts[I] + C.BoxW, Extent) - 1 do
      if (Level[X] = 3) or (Lv < Level[X]) then
        Level[X] := Lv;
  end;

  // The first and the last column keep the dialog's margins. When the spare
  // cells run out, the cells go from the columns that hurt the fewest
  // controls, which cuts a caption by a cell or two.
  SetLength(Removed, Extent);
  Total := Excess;
  for Pass := 0 to 1 do
    while Excess > 0 do
    begin
      // The k-th dropped column aims at the middle of the k-th of Total equal
      // stretches, so the cuts spread evenly over the dialog.
      Target := (2 * (Total - Excess) + 1) * Extent div (2 * Total);
      BestX := -1;
      BestLv := MaxInt;
      BestDist := MaxInt;
      BestHurt := MaxInt;
      for X := 1 to Extent - 2 do
      begin
        if Removed[X] then
          Continue;
        Hurt := 0;
        for I := 0 to High(AControls) do
          if (AControls[I].BoxW > 0) and (Slack[I] <= 0) and (ALefts[I] <= X) and
             (X < ALefts[I] + AControls[I].BoxW) and not DialogControlHiddenByTab(AControls, I) then
            Inc(Hurt, 1 - Slack[I]);
        if (Pass = 0) and (Hurt > 0) then
          Continue;
        Dist := Abs(X - Target);
        if Pass = 1 then
          Better := (Hurt < BestHurt) or ((Hurt = BestHurt) and (Level[X] < BestLv)) or
            ((Hurt = BestHurt) and (Level[X] = BestLv) and (Dist < BestDist))
        else
          Better := (Level[X] < BestLv) or ((Level[X] = BestLv) and (Dist < BestDist));
        if Better then
        begin
          BestX := X;
          BestLv := Level[X];
          BestDist := Dist;
          BestHurt := Hurt;
        end;
      end;
      if BestX < 0 then
        Break;
      Removed[BestX] := True;
      Dec(Excess);
      for I := 0 to High(AControls) do
        if (AControls[I].BoxW > 0) and (ALefts[I] <= BestX) and
           (BestX < ALefts[I] + AControls[I].BoxW) and not DialogControlHiddenByTab(AControls, I) then
          Dec(Slack[I]);
    end;

  // NewX[B]: where the boundary in front of column B ends up.
  SetLength(NewX, Extent + 1);
  NewX[0] := 0;
  for X := 0 to Extent - 1 do
    NewX[X + 1] := NewX[X] + Ord(not Removed[X]);
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    if (C.BoxW <= 0) or DialogControlHiddenByTab(AControls, I) then
      Continue;
    CX := ALefts[I];
    CW := C.BoxW;
    ALefts[I] := NewX[Min(CX, Extent)];
    AWidths[I] := Max(NewX[Min(CX + CW, Extent)] - ALefts[I], 1);
  end;

  // A row of buttons that sat in the middle of the wider dialog.
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    if (C.Kind <> dckButton) or DialogControlHiddenByTab(AControls, I) then
      Continue;
    Row := C.Row;
    Shown := True;
    MinL := MaxInt;
    MaxR := 0;
    for K := 0 to High(AControls) do
      if (AControls[K].Row = Row) and not DialogControlHiddenByTab(AControls, K) then
      begin
        if (AControls[K].Kind <> dckButton) or (AControls[K].BoxW <= 0) then
          Shown := False
        else
        begin
          MinL := Min(MinL, Max(AControls[K].Col, 0));
          MaxR := Max(MaxR, Max(AControls[K].Col, 0) + AControls[K].BoxW);
        end;
      end;
    if not Shown then
      Continue;
    // Only the first button of the row moves the row.
    for K := 0 to I - 1 do
      if (AControls[K].Row = Row) and (AControls[K].Kind = dckButton) then
      begin
        Shown := False;
        Break;
      end;
    if not Shown or (Abs(MinL + MaxR - Extent) > 2) then
      Continue;
    MinL := MaxInt;
    MaxR := 0;
    for K := 0 to High(AControls) do
      if (AControls[K].Row = Row) and (AControls[K].Kind = dckButton) and
         not DialogControlHiddenByTab(AControls, K) then
      begin
        MinL := Min(MinL, ALefts[K]);
        MaxR := Max(MaxR, ALefts[K] + AWidths[K]);
      end;
    Shift := (AClientW - (MaxR - MinL)) div 2 - MinL;
    for K := 0 to High(AControls) do
      if (AControls[K].Row = Row) and (AControls[K].Kind = dckButton) and
         not DialogControlHiddenByTab(AControls, K) then
        Inc(ALefts[K], Shift);
  end;
end;

function LayoutDialogV2(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI; AFocus, AScrollY, AScrollFollow: Integer): TDialogV2Layout;
var
  I: Integer;
  Lefts, Widths: TArray<Integer>;
  ClientLeft, ClientTop, ClientRight, ClientBottom, ClientW, ClientH: Integer;
  RowY, RowH: TArray<Integer>;
  C: TDialogControl;
  CX, CY, CW, CH, L, T, Rgt, Bot: Integer;
begin
  // (col,row)=(0,0) is the first cell inside the frame border.
  ClientLeft := AFrame.Left + 1;
  ClientTop := AFrame.Top + 1;
  ClientRight := AFrame.Right - 1;
  ClientBottom := AFrame.Bottom - 1;
  if ClientRight < ClientLeft then
    ClientRight := ClientLeft;
  if ClientBottom < ClientTop then
    ClientBottom := ClientTop;
  ClientW := ClientRight - ClientLeft + 1;
  ClientH := ClientBottom - ClientTop + 1;

  SqueezeColumns(AControls, ClientW, Lefts, Widths);
  SetLength(RowY, Length(AControls));
  SetLength(RowH, Length(AControls));
  Result.ContentH := 0;
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    RowY[I] := Max(C.Row, 0);
    if C.BoxH > 0 then
      RowH[I] := C.BoxH
    else
      RowH[I] := DefaultControlHeight(C);
    // A page that is not shown takes no room, so the dialog scrolls for the
    // shown page only.
    if not DialogControlHiddenByTab(AControls, I) then
      Result.ContentH := Max(Result.ContentH, RowY[I] + RowH[I]);
  end;

  Result.ScrollY := AScrollY;
  Result.ScrollFollow := AScrollFollow;
  if Result.ContentH > ClientH then
  begin
    if AFocus <> Result.ScrollFollow then
    begin
      Result.ScrollFollow := AFocus;
      if (AFocus >= 0) and (AFocus <= High(AControls)) then
      begin
        if RowY[AFocus] < Result.ScrollY then
          Result.ScrollY := RowY[AFocus];
        if RowY[AFocus] + RowH[AFocus] > Result.ScrollY + ClientH then
          Result.ScrollY := RowY[AFocus] + RowH[AFocus] - ClientH;
      end;
    end;
    Result.ScrollY := EnsureRange(Result.ScrollY, 0, Result.ContentH - ClientH);
  end
  else
    Result.ScrollY := 0;

  SetLength(Result.Bounds, Length(AControls));
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    if DialogControlHiddenByTab(AControls, I) then
    begin
      Result.Bounds[I] := TRectI.Make(-1, -1, -2, -2);
      Continue;
    end;
    CX := Lefts[I];
    CY := RowY[I];
    if C.BoxW > 0 then
      CW := Widths[I]
    else
      CW := DefaultControlWidth(C, Max(ClientW - CX, 1));
    CH := RowH[I];
    L := ClientLeft + CX;
    if C.Kind = dckTab then
      T := ClientTop + CY
    else
      T := ClientTop + CY - Result.ScrollY;
    Rgt := L + CW - 1;
    Bot := T + CH - 1;
    // Not wholly in view: drop it. A list or a group of options is cut
    // to the view instead, so its scrollbar stays usable.
    if (C.Kind <> dckTab) and (Result.ContentH > ClientH) and ((T < ClientTop) or (Bot > ClientBottom)) and
       not ((C.Kind in [dckList, dckRadioGroup]) and (Bot >= ClientTop) and
            (T <= ClientBottom)) then
    begin
      Result.Bounds[I] := TRectI.Make(-1, -1, -2, -2);
      Continue;
    end;
    if L < ClientLeft then
      L := ClientLeft;
    if T < ClientTop then
      T := ClientTop;
    if Rgt > ClientRight then
      Rgt := ClientRight;
    // Text that is wider than its box (a longer translation) stops one cell
    // short of the frame border instead of touching it. A separator line
    // reaches the border on purpose, where it joins the frame.
    if (C.Kind in [dckLabel, dckCheckbox, dckRadio, dckDropDown]) and
       not ((C.Kind = dckLabel) and IsHRuleText(C.Text)) and
       (Rgt >= ClientRight) and (L < ClientRight) then
      Rgt := ClientRight - 1;
    if Bot > ClientBottom then
      Bot := ClientBottom;
    if Rgt < L then
      Rgt := L;
    if Bot < T then
      Bot := T;
    Result.Bounds[I] := TRectI.Make(L, T, Rgt, Bot);
  end;
end;

end.
