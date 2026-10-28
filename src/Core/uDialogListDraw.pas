unit uDialogListDraw;

{ Drawing a dialog list. The host passes the grid, the box, the selected
  row and how many rows are visible. Scroll is the host's: this unit does
  not move it. }

interface

uses
  System.UITypes, uDialogTypes, uTerminalTypes, uThemeTypes;

const
  /// <summary>Hotkey cells of a list row: the menus' hotkey red.</summary>
  cListAccentFg = TAlphaColor($FFC00000);

procedure DrawDialogListFrame(const AGrid: TTerminalGrid; const R: TRectI;
  AFg, ABg: TAlphaColor);

/// <summary>A one-row list: the selected item and a down arrow in the last
/// cell, like a closed DropDown.</summary>
procedure DrawDialogSingleRowList(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; const ATheme: IThemeRenderer; ASelIdx: Integer);

/// <summary>A multi-row list. The right column is the scrollbar, so item
/// text stops one cell short of it. ASpan is the visible height.</summary>
procedure DrawDialogMultiRowList(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; const ATheme: IThemeRenderer;
  ALabelFg, ALabelBg: TAlphaColor; ASpan, ASelIdx, AScrollTop, AFrameBottom: Integer);

implementation

uses
  System.SysUtils, System.Math, uCharWidth, uThemeDrawing;

function PadListLine(const AText: string; AWidth: Integer): string;
begin
  if AWidth < 1 then
    Exit('');
  // AWidth is in cells: a wide character takes two.
  Result := Copy(AText, 1, TextFitChars(AText, AWidth));
  Result := Result + StringOfChar(' ', AWidth - TextDisplayWidth(Result));
end;

procedure RowColors(const ATheme: IThemeRenderer; ASelected: Boolean;
  ANormalFg, ANormalBg: TAlphaColor; out AFg, ABg: TAlphaColor);
begin
  if Assigned(ATheme) then
    ATheme.ResolveDialogRowColors(ASelected, AFg, ABg)
  else if ASelected then
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FF00AAAA);
  end
  else
  begin
    AFg := ANormalFg;
    ABg := ANormalBg;
  end;
end;

procedure DrawDialogListFrame(const AGrid: TTerminalGrid; const R: TRectI;
  AFg, ABg: TAlphaColor);
var
  X, Y: Integer;
begin
  // A single-line frame one cell outside the list's box.
  for X := R.Left to R.Right do
  begin
    DrawGridChar(AGrid, X, R.Top - 1, chBoxH, AFg, ABg);
    DrawGridChar(AGrid, X, R.Bottom + 1, chBoxH, AFg, ABg);
  end;
  for Y := R.Top to R.Bottom do
  begin
    DrawGridChar(AGrid, R.Left - 1, Y, chBoxV, AFg, ABg);
    DrawGridChar(AGrid, R.Right + 1, Y, chBoxV, AFg, ABg);
  end;
  DrawGridChar(AGrid, R.Left - 1, R.Top - 1, chBoxTL, AFg, ABg);
  DrawGridChar(AGrid, R.Right + 1, R.Top - 1, chBoxTR, AFg, ABg);
  DrawGridChar(AGrid, R.Left - 1, R.Bottom + 1, chBoxBL, AFg, ABg);
  DrawGridChar(AGrid, R.Right + 1, R.Bottom + 1, chBoxBR, AFg, ABg);
end;

procedure DrawDialogSingleRowList(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; const ATheme: IThemeRenderer; ASelIdx: Integer);
var
  Line: string;
  RowFg, RowBg: TAlphaColor;
begin
  // Height 1: combo-style - show selected item (not items[0]).
  if (ASelIdx >= 0) and (ASelIdx <= High(C.Items)) then
    Line := C.Items[ASelIdx]
  else
    Line := '';
  if R.Width >= 2 then
    Line := PadListLine(Line, R.Width - 1) + WideChar($2193)
  else
    Line := PadListLine(Line, Max(R.Width, 1));
  RowColors(ATheme, True, 0, 0, RowFg, RowBg);
  PutGridText(AGrid, R.Left, R.Top, Line, RowFg, RowBg);
end;

procedure DrawDialogMultiRowList(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; const ATheme: IThemeRenderer;
  ALabelFg, ALabelBg: TAlphaColor; ASpan, ASelIdx, AScrollTop, AFrameBottom: Integer);
var
  J, K, Idx, TextW, Count: Integer;
  Line: string;
  RowFg, RowBg, SwFg, SwBg: TAlphaColor;
begin
  TextW := Max(R.Width - 1, 1); // reserve right column for scrollbar
  Count := Length(C.Items);
  for J := 0 to ASpan - 1 do
  begin
    if R.Top + J >= AFrameBottom then
      Break;
    Idx := AScrollTop + J;
    if Idx <= High(C.Items) then
      Line := C.Items[Idx]
    else
      Line := '';
    Line := PadListLine(Line, TextW);
    RowColors(ATheme, Idx = ASelIdx, ALabelFg, ALabelBg, RowFg, RowBg);
    PutGridText(AGrid, R.Left, R.Top + J, Line, RowFg, RowBg);
    if (Idx <= High(C.ItemSwatches)) and (C.ItemSwatches[Idx].Text <> '') and
       (C.ItemSwatches[Idx].Col + Length(C.ItemSwatches[Idx].Text) <= TextW) then
    begin
      // An unset channel shows the theme's own file-row color.
      SwFg := RowFg;
      SwBg := RowBg;
      if Assigned(ATheme) then
        ATheme.ResolveFileRowColors(False, False, False, '', False, False, True,
          SwFg, SwBg);
      if C.ItemSwatches[Idx].Fg <> 0 then
        SwFg := C.ItemSwatches[Idx].Fg;
      if C.ItemSwatches[Idx].Bg <> 0 then
        SwBg := C.ItemSwatches[Idx].Bg;
      PutGridText(AGrid, R.Left + C.ItemSwatches[Idx].Col, R.Top + J,
        C.ItemSwatches[Idx].Text, SwFg, SwBg);
    end;
    // Accent stretches (hotkey cells) keep the row's background.
    for K := 0 to High(C.ItemAccents) do
      if (C.ItemAccents[K].Item = Idx) and (C.ItemAccents[K].Len > 0) and
         (C.ItemAccents[K].Col >= 0) and (C.ItemAccents[K].Col < TextW) then
        PutGridText(AGrid, R.Left + C.ItemAccents[K].Col, R.Top + J,
          Copy(Line, C.ItemAccents[K].Col + 1,
            Min(C.ItemAccents[K].Len, TextW - C.ItemAccents[K].Col)),
          cListAccentFg, RowBg, [ccaBold]);
  end;
  DrawDialogScrollBar(AGrid, R.Right, R.Top, R.Bottom,
    AScrollTop, Count, ASpan);
end;

end.
