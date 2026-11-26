unit uDialogV2Layout;

{ Protocol 2 dialog layout. The caller supplies the frame, the controls, the
  focus and the scroll it already has. Nothing here writes host fields: a
  wheel drag survives as long as the focus stays the same.

  A dialog taller than its frame scrolls as a whole. One with a vertical tab
  strip and a vertical rule beside it scrolls its pages only: the strip and the
  rows under the rule stay in place. }

interface

uses
  System.SysUtils, uDialogTypes, uThemeTypes;

type
  TDialogV2Layout = record
    Bounds: TArray<TRectI>;
    ContentH: Integer;
    /// <summary>Rows that scroll, from the top of the client area.</summary>
    ViewH: Integer;
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
/// group (and, with pinned rows, a group frame or the strip), which is cut to
/// the view. ScrollY moves only when AFocus differs from AScrollFollow.</summary>
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

type
  // How the rows of the client area are shared. Split is the first row under the
  // pages of a dialog with pinned rows; 0 when the dialog scrolls as a whole.
  TRowPlan = record
    Split: Integer;
    // Only the first rule and the buttons are left under the pages.
    Compact: Boolean;
    ViewH: Integer;
    ContentH: Integer;
  end;

  // Screen rows of one control.
  TRowSpan = record
    Top, Bottom: Integer;
    Hidden: Boolean;
  end;

// First row under the pages of a dialog with pinned rows, 0 for other dialogs.
function PinnedSplitRow(const AControls: TArray<TDialogControl>): Integer;
var
  I, Strip: Integer;
begin
  Result := 0;
  Strip := DialogTabStripIndex(AControls);
  if (Strip < 0) or not AControls[Strip].Vertical then
    Exit;
  for I := 0 to High(AControls) do
    if (AControls[I].Kind = dckLabel) and AControls[I].VRule and (AControls[I].TabPage = 0) then
      Exit(Max(AControls[I].Row, 0) + Max(AControls[I].BoxH, 1));
end;

procedure MeasureRows(const AControls: TArray<TDialogControl>;
  out ARowY, ARowH: TArray<Integer>);
var
  I: Integer;
begin
  SetLength(ARowY, Length(AControls));
  SetLength(ARowH, Length(AControls));
  for I := 0 to High(AControls) do
  begin
    ARowY[I] := Max(AControls[I].Row, 0);
    if AControls[I].BoxH > 0 then
      ARowH[I] := AControls[I].BoxH
    else
      ARowH[I] := DefaultControlHeight(AControls[I]);
  end;
end;

// Rows down to the last shown control. A page that is not shown takes no room,
// so the dialog scrolls for the shown page only.
function ShownRowCount(const AControls: TArray<TDialogControl>;
  const ARowY, ARowH: TArray<Integer>; APagesOnly: Boolean): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AControls) do
    if (not APagesOnly or (AControls[I].TabPage > 0)) and
       not DialogControlHiddenByTab(AControls, I) then
      Result := Max(Result, ARowY[I] + ARowH[I]);
end;

function PlanRows(const AControls: TArray<TDialogControl>;
  const ARowY, ARowH: TArray<Integer>; AClientH: Integer): TRowPlan;
const
  // Page rows below which the rows under the pages shrink to rule and buttons.
  cMinPageRows = 6;
var
  Split, FooterH: Integer;
begin
  Result.Split := 0;
  Result.Compact := False;
  Result.ViewH := AClientH;
  Result.ContentH := ShownRowCount(AControls, ARowY, ARowH, False);
  Split := PinnedSplitRow(AControls);
  if (Split <= 0) or (Result.ContentH <= AClientH) then
    Exit;
  Result.Split := Split;
  // The rows under the pages, plus one for the shadow of the buttons.
  FooterH := Result.ContentH - Split + 1;
  Result.Compact := AClientH - FooterH < cMinPageRows;
  if Result.Compact then
    FooterH := 3;
  Result.ViewH := Max(AClientH - FooterH, 1);
  Result.ContentH := ShownRowCount(AControls, ARowY, ARowH, True);
end;

// AScrollY moved as little as brings the focused control into view.
function ScrollToFocus(const AControls: TArray<TDialogControl>;
  const ARowY, ARowH: TArray<Integer>; const APlan: TRowPlan;
  AFocus, AScrollY: Integer): Integer;
var
  Above: Integer;
begin
  Result := AScrollY;
  if (AFocus < 0) or (AFocus > High(AControls)) or
     ((APlan.Split > 0) and (AControls[AFocus].TabPage <= 0)) then
    Exit;
  // With pinned rows one row stays above the field: the title of its frame.
  Above := Ord(APlan.Split > 0);
  Result := Min(Result, ARowY[AFocus] - Above);
  Result := Max(Result, ARowY[AFocus] + ARowH[AFocus] - APlan.ViewH);
end;

// A control of a dialog that scrolls as a whole. One that is not wholly in view
// is dropped, except a list or a group of options: it is cut to the view, so its
// scrollbar stays usable.
function ScrollingRows(const C: TDialogControl; ARow, AHeight, AScrollY: Integer;
  const APlan: TRowPlan; AClientTop, AClientBottom: Integer): TRowSpan;
begin
  if C.Kind = dckTab then
    AScrollY := 0;
  Result.Top := AClientTop + ARow - AScrollY;
  Result.Bottom := Result.Top + AHeight - 1;
  Result.Hidden := (C.Kind <> dckTab) and
    (APlan.ContentH > AClientBottom - AClientTop + 1) and
    ((Result.Top < AClientTop) or (Result.Bottom > AClientBottom));
  if Result.Hidden and (C.Kind in [dckList, dckRadioGroup]) then
    Result.Hidden := (Result.Bottom < AClientTop) or (Result.Top > AClientBottom);
end;

// A control of a page between pinned rows. A group frame is cut like a list.
function PageRows(const C: TDialogControl; ARow, AHeight, AScrollY: Integer;
  const APlan: TRowPlan; AClientTop: Integer): TRowSpan;
var
  ViewEnd: Integer;
begin
  ViewEnd := AClientTop + APlan.ViewH - 1;
  if C.Kind = dckTab then
    AScrollY := 0;
  Result.Top := AClientTop + ARow - AScrollY;
  Result.Bottom := Result.Top + AHeight - 1;
  if (C.Kind in [dckList, dckRadioGroup]) or ((C.Kind = dckLabel) and C.GroupFrame) then
    Result.Hidden := (Result.Bottom < AClientTop) or (Result.Top > ViewEnd)
  else
    Result.Hidden := (Result.Top < AClientTop) or (Result.Bottom > ViewEnd);
  Result.Bottom := Min(Result.Bottom, ViewEnd);
end;

// A control outside the pages of a dialog with pinned rows: beside the pages it
// stays in place, cut to the view; under them it follows the end of the view.
function PinnedRows(const C: TDialogControl; ARow, AHeight: Integer;
  const APlan: TRowPlan; AClientTop: Integer): TRowSpan;
var
  ViewEnd: Integer;
begin
  ViewEnd := AClientTop + APlan.ViewH - 1;
  if ARow < APlan.Split then
  begin
    Result.Top := AClientTop + ARow;
    Result.Bottom := Min(Result.Top + AHeight - 1, ViewEnd);
    Result.Hidden := Result.Top > ViewEnd;
    Exit;
  end;
  Result.Top := ViewEnd + 1 + ARow - APlan.Split;
  Result.Hidden := APlan.Compact and (C.Kind <> dckButton) and (ARow > APlan.Split);
  if APlan.Compact and (C.Kind = dckButton) then
    Result.Top := ViewEnd + 2;
  Result.Bottom := Result.Top + AHeight - 1;
end;

function ControlRows(const C: TDialogControl; ARow, AHeight, AScrollY: Integer;
  const APlan: TRowPlan; AClientTop, AClientBottom: Integer): TRowSpan;
begin
  if APlan.Split = 0 then
    Result := ScrollingRows(C, ARow, AHeight, AScrollY, APlan, AClientTop, AClientBottom)
  else if C.TabPage > 0 then
    Result := PageRows(C, ARow, AHeight, AScrollY, APlan, AClientTop)
  else
    Result := PinnedRows(C, ARow, AHeight, APlan, AClientTop);
end;

// Keeps a box inside the client area.
function FitToClient(const C: TDialogControl; const ABox, AClient: TRectI): TRectI;
var
  L, T, Rgt, Bot: Integer;
begin
  L := Max(ABox.Left, AClient.Left);
  T := Max(ABox.Top, AClient.Top);
  Rgt := Min(ABox.Right, AClient.Right);
  // Text that is wider than its box (a longer translation) stops one cell
  // short of the frame border instead of touching it. A separator line
  // reaches the border on purpose, where it joins the frame.
  if (C.Kind in [dckLabel, dckCheckbox, dckRadio, dckDropDown]) and
     not ((C.Kind = dckLabel) and IsHRuleText(C.Text)) and
     (Rgt >= AClient.Right) and (L < AClient.Right) then
    Rgt := AClient.Right - 1;
  Bot := Min(ABox.Bottom, AClient.Bottom);
  Result := TRectI.Make(L, T, Max(Rgt, L), Max(Bot, T));
end;

function LayoutDialogV2(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI; AFocus, AScrollY, AScrollFollow: Integer): TDialogV2Layout;
var
  I, L, W: Integer;
  Lefts, Widths, RowY, RowH: TArray<Integer>;
  Client: TRectI;
  Plan: TRowPlan;
  Rows: TRowSpan;
  C: TDialogControl;
begin
  // (col,row)=(0,0) is the first cell inside the frame border.
  Client := TRectI.Make(AFrame.Left + 1, AFrame.Top + 1,
    Max(AFrame.Right - 1, AFrame.Left + 1), Max(AFrame.Bottom - 1, AFrame.Top + 1));

  SqueezeColumns(AControls, Client.Right - Client.Left + 1, Lefts, Widths);
  MeasureRows(AControls, RowY, RowH);
  Plan := PlanRows(AControls, RowY, RowH, Client.Bottom - Client.Top + 1);
  Result.ContentH := Plan.ContentH;
  Result.ViewH := Plan.ViewH;

  Result.ScrollY := 0;
  Result.ScrollFollow := AScrollFollow;
  if Plan.ContentH > Plan.ViewH then
  begin
    Result.ScrollY := AScrollY;
    if AFocus <> AScrollFollow then
    begin
      Result.ScrollFollow := AFocus;
      Result.ScrollY := ScrollToFocus(AControls, RowY, RowH, Plan, AFocus, AScrollY);
    end;
    Result.ScrollY := EnsureRange(Result.ScrollY, 0, Plan.ContentH - Plan.ViewH);
  end;

  SetLength(Result.Bounds, Length(AControls));
  for I := 0 to High(AControls) do
  begin
    C := AControls[I];
    Result.Bounds[I] := TRectI.Make(-1, -1, -2, -2);
    if DialogControlHiddenByTab(AControls, I) then
      Continue;
    Rows := ControlRows(C, RowY[I], RowH[I], Result.ScrollY, Plan, Client.Top, Client.Bottom);
    if Rows.Hidden then
      Continue;
    if C.BoxW > 0 then
      W := Widths[I]
    else
      W := DefaultControlWidth(C, Max(Client.Right - Client.Left + 1 - Lefts[I], 1));
    L := Client.Left + Lefts[I];
    Result.Bounds[I] := FitToClient(C, TRectI.Make(L, Rows.Top, L + W - 1, Rows.Bottom), Client);
  end;
end;

end.
