unit uDialogHostClicks;

{ Mouse hit routing for TDialogHost. The host fills TDialogClickOps; the free
  functions below own frame / open-dropdown / per-kind branches so
  HandleClickCore stays a short dispatcher. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogTypes, uThemeTypes;

type
  TDialogClickBoolFn = function: Boolean of object;
  TDialogClickProc = procedure of object;
  TDialogClickIntFn = function: Integer of object;
  TDialogClickSetIntProc = procedure(AValue: Integer) of object;
  TDialogClickIndexFn = function(AIndex: Integer): Boolean of object;
  TDialogClickIndexProc = procedure(AIndex: Integer) of object;
  TDialogClickIdProc = procedure(const AId: string) of object;
  TDialogClickControlFn = function(AIndex: Integer): TDialogControl of object;
  TDialogClickSetControlProc = procedure(AIndex: Integer; const AControl: TDialogControl) of object;
  TDialogClickBoundsFn = function: TRectI of object;
  TDialogClickControlBoundsFn = function(AIndex: Integer): TRectI of object;
  TDialogClickDropPopupFn = function(out ARect: TRectI): Boolean of object;
  TDialogClickDropContentFn = function(const APopup: TRectI): TRectI of object;
  TDialogClickListSelFn = function(const AId: string): Integer of object;
  TDialogClickListSelProc = procedure(AControlIndex, ASelected: Integer) of object;
  TDialogClickHitFn = function(ACol, ARow: Integer): Integer of object;
  TDialogClickCaptureProc = procedure(AIndex, ALocalCol, ALocalRow: Integer) of object;
  TDialogClickInputShiftProc = procedure(AIndex, ALocalCol, ALocalRow: Integer;
    AExtend: Boolean; AClicks: Integer) of object;

  TDialogClickOps = record
    Visible: TDialogClickBoolFn;
    EnsureLayout: TDialogClickProc;
    NotifyChanged: TDialogClickProc;
    FireAccept: TDialogClickProc;
    FireCancel: TDialogClickProc;
    FireCommand: TDialogClickIdProc;
    CloseDropDown: TDialogClickProc;
    CommitDropDown: TDialogClickProc;
    OpenDropDown: TDialogClickIndexProc;
    EnsureDropHoverInView: TDialogClickProc;
    IsHistoryInput: TDialogClickIndexFn;
    SelectRadio: TDialogClickIndexProc;
    EnsureListInView: TDialogClickIndexProc;
    SetListSelectedIndex: TDialogClickListSelProc;
    ListSelectedIndexOf: TDialogClickListSelFn;
    DropPress: TDialogClickProc;
    HasPressTimer: TDialogClickBoolFn;
    ClickHit: TDialogClickHitFn;
    ResetClicks: TDialogClickProc;
    BeginButtonCapture: TDialogClickCaptureProc;
    BeginInputDrag: TDialogClickCaptureProc;
    ApplyInputClick: TDialogClickInputShiftProc;
    Bounds: TDialogClickBoundsFn;
    ControlBounds: TDialogClickControlBoundsFn;
    DropPopupBounds: TDialogClickDropPopupFn;
    DropContentBounds: TDialogClickDropContentFn;
    FocusIndex: TDialogClickIntFn;
    SetFocusIndex: TDialogClickSetIntProc;
    DropOpenIndex: TDialogClickIntFn;
    DropHover: TDialogClickIntFn;
    SetDropHover: TDialogClickSetIntProc;
    DropScrollTop: TDialogClickIntFn;
    ListScrollTop: TDialogClickIntFn;
    ControlCount: TDialogClickIntFn;
    GetControl: TDialogClickControlFn;
    SetControl: TDialogClickSetControlProc;
  end;

function DialogHandleClickCore(const Ops: TDialogClickOps; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;

implementation

uses
  System.Math, uThemeDrawing, uInputLine, uColorPickerControl, uDatePickerControl;

function DialogHandleFrameClick(const Ops: TDialogClickOps; ALocalCol, ALocalRow: Integer): Boolean;
var
  B: TRectI;
begin
  B := Ops.Bounds();
  if WindowFrameCloseHit(B, ALocalCol, ALocalRow) then
  begin
    Ops.CloseDropDown();
    Ops.FireCancel();
    Exit(True);
  end;
  if not B.Contains(ALocalCol, ALocalRow) then
  begin
    Ops.CloseDropDown();
    // Outside click = Cancel when a cancel button exists.
    Ops.FireCancel();
    Exit(True);
  end;
  Result := False;
end;

function DialogHandleOpenDropDownClick(const Ops: TDialogClickOps;
  ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Idx, Count, ViewH, DropIdx: Integer;
  Popup: TRectI;
  NeedBar: Boolean;
  Field: TRectI;
  C: TDialogControl;
begin
  Result := False;
  DropIdx := Ops.DropOpenIndex();
  if (DropIdx < 0) or not Ops.DropPopupBounds(Popup) then
    Exit;

  // DropDown popup takes priority while open.
  if Popup.Contains(ALocalCol, ALocalRow) then
  begin
    Ops.EnsureDropHoverInView();
    Popup := Ops.DropContentBounds(Popup);
    if not Popup.Contains(ALocalCol, ALocalRow) then
      Exit(True);
    Row := ALocalRow - Popup.Top;
    ViewH := Popup.Height;
    C := Ops.GetControl(DropIdx);
    Count := Length(C.Items);
    NeedBar := Count > ViewH;
    if NeedBar and (ALocalCol = Popup.Right) and (ViewH > 0) then
    begin
      if ALocalRow = Popup.Top then
        Ops.SetDropHover(EnsureRange(Ops.DropHover() - 1, 0, Count - 1))
      else if ALocalRow = Popup.Bottom then
        Ops.SetDropHover(EnsureRange(Ops.DropHover() + 1, 0, Count - 1))
      else
        Ops.SetDropHover(EnsureRange(
          Round((ALocalRow - Popup.Top - 1) * (Count - 1) / Max(ViewH - 3, 1)),
          0, Count - 1));
      Ops.EnsureDropHoverInView();
      Ops.NotifyChanged();
      Exit(True);
    end;
    if (ALocalCol >= Popup.Left) and
       ((not NeedBar and (ALocalCol <= Popup.Right)) or
        (NeedBar and (ALocalCol < Popup.Right))) and
       (Row >= 0) and (Row < ViewH) then
    begin
      Idx := Ops.DropScrollTop() + Row;
      if (Idx >= 0) and (Idx <= High(C.Items)) then
      begin
        Ops.SetDropHover(Idx);
        Ops.CommitDropDown();
      end;
      Exit(True);
    end;
    Exit(True);
  end;
  // Click outside popup collapses without changing selection.
  Field := Ops.ControlBounds(DropIdx);
  if Field.Contains(ALocalCol, ALocalRow) then
  begin
    Ops.CloseDropDown();
    Exit(True);
  end;
  Ops.CloseDropDown();
  // The control under the pointer still receives this click.
end;

procedure DialogHandleInputClick(const Ops: TDialogClickOps; AIndex: Integer;
  const R: TRectI; const C: TDialogControl; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState);
var
  Clicks: Integer;
begin
  if C.Disabled then
    Exit;
  Ops.SetFocusIndex(AIndex);
  if (C.ColorPick or C.DatePick) and (R.Width >= 3) and
     (ALocalCol = R.Left + R.Width - 1) then
  begin
    Ops.NotifyChanged();
    Ops.FireCommand(DialogPickCommand(C.Id));
    Exit;
  end;
  if Ops.IsHistoryInput(AIndex) and (R.Width >= 3) and
     (ALocalCol = R.Left + R.Width - 1) then
  begin
    Ops.OpenDropDown(AIndex);
    Ops.NotifyChanged();
    Exit;
  end;
  // Caret to the clicked cell; double click = word, triple = all;
  // Shift+click extends the selection from the current caret.
  if ssShift in AShift then
  begin
    Ops.ResetClicks();
    Ops.ApplyInputClick(AIndex, ALocalCol, ALocalRow, True, 1);
  end
  else
  begin
    Clicks := Ops.ClickHit(ALocalCol, ALocalRow);
    Ops.ApplyInputClick(AIndex, ALocalCol, ALocalRow, False, Clicks);
    // A single press starts a drag selection, finished on the release.
    if (Clicks = 1) and Ops.HasPressTimer() then
      Ops.BeginInputDrag(AIndex, ALocalCol, ALocalRow);
  end;
  Ops.NotifyChanged();
end;

function DialogHandleListClick(const Ops: TDialogClickOps; AIndex: Integer;
  const R: TRectI; const C: TDialogControl; ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Idx, Count, Span, Clicks: Integer;
begin
  Span := R.Height;
  if (Span > 1) and (ALocalCol = R.Right) then
  begin
    // Scrollbar: ▲ / ▼ / track -> move selection.
    Ops.SetFocusIndex(AIndex);
    Ops.EnsureListInView(AIndex);
    Count := Length(Ops.GetControl(AIndex).Items);
    if Count = 0 then
      Exit(True);
    if ALocalRow = R.Top then
      Ops.SetListSelectedIndex(AIndex, Ops.ListSelectedIndexOf(C.Id) - 1)
    else if ALocalRow = R.Bottom then
      Ops.SetListSelectedIndex(AIndex, Ops.ListSelectedIndexOf(C.Id) + 1)
    else if Count > Span then
      Ops.SetListSelectedIndex(AIndex,
        EnsureRange(Round((ALocalRow - R.Top - 1) * (Count - 1) /
          Max(Span - 3, 1)), 0, Count - 1))
    else
      Ops.SetListSelectedIndex(AIndex, 0);
    Ops.NotifyChanged();
    Exit(True);
  end;
  Row := ALocalRow - R.Top;
  if Span > 1 then
  begin
    Ops.EnsureListInView(AIndex);
    Idx := Ops.ListScrollTop() + Row;
  end
  else
    Idx := Row;
  if (Row >= 0) and (Row < Span) and (Idx >= 0) and
     (Idx <= High(Ops.GetControl(AIndex).Items)) then
  begin
    Ops.SetFocusIndex(AIndex);
    Ops.SetListSelectedIndex(AIndex, Idx);
    Clicks := Ops.ClickHit(ALocalCol, ALocalRow);
    Ops.NotifyChanged();
    // A double click on a row is Enter on it.
    if Clicks = 2 then
      Ops.FireAccept();
    Exit(True);
  end;
  Result := False;
end;

function DialogHandleRadioGroupClick(const Ops: TDialogClickOps; AIndex: Integer;
  const R: TRectI; const C: TDialogControl; ALocalRow: Integer): Boolean;
var
  Row: Integer;
begin
  Row := ALocalRow - R.Top;
  if C.Text <> '' then
    Dec(Row);
  if (Row >= 0) and (Row <= High(Ops.GetControl(AIndex).Items)) then
  begin
    Ops.SetFocusIndex(AIndex);
    Ops.SetListSelectedIndex(AIndex, Row);
    Ops.NotifyChanged();
    Exit(True);
  end;
  Result := False;
end;

procedure DialogHandleButtonClick(const Ops: TDialogClickOps; AIndex: Integer;
  const C: TDialogControl; ALocalCol, ALocalRow: Integer);
begin
  Ops.SetFocusIndex(AIndex);
  if Ops.HasPressTimer() then
    Ops.BeginButtonCapture(AIndex, ALocalCol, ALocalRow)
  else
    Ops.FireCommand(C.Id);
end;

procedure DialogHandleCheckboxClick(const Ops: TDialogClickOps; AIndex: Integer);
var
  C: TDialogControl;
begin
  C := Ops.GetControl(AIndex);
  if C.Disabled then
    Exit;
  Ops.SetFocusIndex(AIndex);
  DialogToggleCheckbox(C);
  Ops.SetControl(AIndex, C);
  Ops.NotifyChanged();
end;

procedure DialogHandleRadioClick(const Ops: TDialogClickOps; AIndex: Integer);
begin
  Ops.SetFocusIndex(AIndex);
  Ops.SelectRadio(AIndex);
  Ops.NotifyChanged();
end;

procedure DialogHandleDropDownFieldClick(const Ops: TDialogClickOps; AIndex: Integer;
  const C: TDialogControl);
begin
  if C.Disabled then
    Exit;
  Ops.SetFocusIndex(AIndex);
  if Ops.DropOpenIndex() = AIndex then
    Ops.CloseDropDown()
  else
    Ops.OpenDropDown(AIndex);
end;

procedure DialogHandleDatePickerClick(const Ops: TDialogClickOps; AIndex: Integer;
  const R: TRectI; ALocalCol, ALocalRow: Integer);
var
  C: TDialogControl;
begin
  Ops.SetFocusIndex(AIndex);
  C := Ops.GetControl(AIndex);
  DatePickerClick(C.Cal, ALocalCol - R.Left, ALocalRow - R.Top);
  Ops.SetControl(AIndex, C);
  Ops.NotifyChanged();
end;

procedure DialogHandleColorPickerClick(const Ops: TDialogClickOps; AIndex: Integer;
  const R: TRectI; ALocalCol, ALocalRow: Integer);
var
  C: TDialogControl;
begin
  Ops.SetFocusIndex(AIndex);
  C := Ops.GetControl(AIndex);
  ColorPickerClick(C.Picker, ALocalCol - R.Left, ALocalRow - R.Top,
    Ops.ClickHit(ALocalCol, ALocalRow));
  Ops.SetControl(AIndex, C);
  Ops.NotifyChanged();
end;

function DialogHandleClickCore(const Ops: TDialogClickOps; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  I: Integer;
  C: TDialogControl;
  R: TRectI;
begin
  Result := False;
  if not Ops.Visible() then
    Exit;
  // Hit-test must use current layout even if Draw has not run yet this frame.
  Ops.EnsureLayout();
  if DialogHandleFrameClick(Ops, ALocalCol, ALocalRow) then
    Exit(True);
  if DialogHandleOpenDropDownClick(Ops, ALocalCol, ALocalRow) then
    Exit(True);

  for I := 0 to Ops.ControlCount() - 1 do
  begin
    R := Ops.ControlBounds(I);
    if not R.Contains(ALocalCol, ALocalRow) then
      Continue;
    C := Ops.GetControl(I);
    case C.Kind of
      dckButton:
        begin
          DialogHandleButtonClick(Ops, I, C, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckCheckbox:
        begin
          DialogHandleCheckboxClick(Ops, I);
          Exit(True);
        end;
      dckRadio:
        begin
          DialogHandleRadioClick(Ops, I);
          Exit(True);
        end;
      dckInput:
        begin
          DialogHandleInputClick(Ops, I, R, C, ALocalCol, ALocalRow, AShift);
          Exit(True);
        end;
      dckDropDown:
        begin
          DialogHandleDropDownFieldClick(Ops, I, C);
          Exit(True);
        end;
      dckDatePicker:
        begin
          DialogHandleDatePickerClick(Ops, I, R, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckColorPicker:
        begin
          DialogHandleColorPickerClick(Ops, I, R, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckList:
        if DialogHandleListClick(Ops, I, R, C, ALocalCol, ALocalRow) then
          Exit(True);
      dckRadioGroup:
        if DialogHandleRadioGroupClick(Ops, I, R, C, ALocalRow) then
          Exit(True);
    end;
  end;
  Result := True;
end;

end.
