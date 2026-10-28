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

/// <summary>Places every control inside AFrame. A control that is not wholly
/// in a scrolling view is given an empty rectangle, except a list or a radio
/// group, which is cut to the view. ScrollY moves only when AFocus differs
/// from AScrollFollow.</summary>
function LayoutDialogV2(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI; AFocus, AScrollY, AScrollFollow: Integer): TDialogV2Layout;

implementation

uses
  System.Math, uCharWidth, uColorPickerControl, uDatePickerControl;

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
    dckColorPicker:
      Result := cPickerHeight;
    dckDatePicker:
      Result := cCalendarHeight;
  else
    Result := 1;
  end;
end;

function LayoutDialogV2(const AControls: TArray<TDialogControl>;
  const AFrame: TRectI; AFocus, AScrollY, AScrollFollow: Integer): TDialogV2Layout;
var
  I: Integer;
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
    if C.Col >= 0 then
      CX := C.Col
    else
      CX := 0;
    CY := RowY[I];
    if C.BoxW > 0 then
      CW := C.BoxW
    else
      CW := DefaultControlWidth(C, Max(ClientW - CX, 1));
    CH := RowH[I];
    L := ClientLeft + CX;
    T := ClientTop + CY - Result.ScrollY;
    Rgt := L + CW - 1;
    Bot := T + CH - 1;
    // Not wholly in view: drop it. A list or a group of options is cut
    // to the view instead, so its scrollbar stays usable.
    if (Result.ContentH > ClientH) and ((T < ClientTop) or (Bot > ClientBottom)) and
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
