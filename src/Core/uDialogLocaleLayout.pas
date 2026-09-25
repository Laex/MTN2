unit uDialogLocaleLayout;

{ Widen a protocol-2 dialog after translation so captions fit.

  Cells are columns. The frame occupies one cell on each side, so the
  client width is Decl.Width - 2. Each control keeps its row. Controls that
  share a starting column grow by the same amount (the widest caption in
  that column), and every column to the right shifts by the sum of those
  growths. The original gap between columns is therefore unchanged, so a
  longer caption cannot land on the next control. A control that already
  reached the right client edge stretches with the dialog. The dialog width
  grows to cover the new right edge, at least two client cells of right
  padding for button ▄ shadow + gap before the frame (rule labels that
  already spanned the client still stretch flush to both sides), and the
  title plus the frame's close mark. After button widths settle, each row
  of buttons is recentered in the new client width. Width never shrinks. }

interface

uses
  uDialogTypes;

procedure FitDialogToTranslatedText(var ADecl: TDialogDeclaration);

implementation

uses
  System.SysUtils, System.Math, uDialogRenderer;

function ClientWidthOf(AWidth: Integer): Integer;
begin
  Result := AWidth - 2;
  if Result < 1 then
    Result := Max(AWidth, 1);
end;

function LongestLine(const AText: string): Integer;
var
  I, Start, N: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(AText) do
  begin
    Start := I;
    while (I <= Length(AText)) and (AText[I] <> #10) and (AText[I] <> #13) do
      Inc(I);
    N := I - Start;
    if N > Result then
      Result := N;
    if (I <= Length(AText)) and (AText[I] = #13) then
      Inc(I);
    if (I <= Length(AText)) and (AText[I] = #10) then
      Inc(I);
  end;
end;

function IsRuleChar(C: Char): Boolean;
begin
  Result := (C = '-') or (C = '=') or (C = '_') or
    (Ord(C) = $2500) or (Ord(C) = $2501) or (Ord(C) = $2550);
end;

function IsRuleText(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := AText <> '';
  for I := 1 to Length(AText) do
    if not IsRuleChar(AText[I]) then
      Exit(False);
end;

function WidthForLineCount(const AText: string; ALines: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  if ALines < 1 then
    ALines := 1;
  Hi := LongestLine(AText);
  if Hi <= 1 then
    Exit(Max(Hi, 1));
  Lo := 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if Length(TDialogRenderer.WrapLabelLines(AText, Mid)) <= ALines then
      Hi := Mid
    else
      Lo := Mid + 1;
  end;
  Result := Lo;
end;

function MaxItemCells(const AItems: TArray<string>; AExtra: Integer): Integer;
var
  I, N: Integer;
begin
  Result := 1 + AExtra;
  for I := 0 to High(AItems) do
  begin
    N := Length(AItems[I]) + AExtra;
    if N > Result then
      Result := N;
  end;
end;

function CaptionCells(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckButton, dckCheckbox, dckRadio:
      Result := Length(C.Text) + 4;
    dckLabel, dckStatus:
      if IsRuleText(C.Text) then
        Result := Max(C.BoxW, 1)
      else if C.BoxH > 1 then
        Result := WidthForLineCount(C.Text, C.BoxH)
      else
        Result := Max(LongestLine(C.Text), 1);
    dckDropDown, dckList:
      Result := MaxItemCells(C.Items, 1);
    dckRadioGroup:
      Result := Max(MaxItemCells(C.Items, 4), Length(C.Text));
  else
    Result := Max(C.BoxW, 1);
  end;
  if Result < 1 then
    Result := 1;
end;

function TitleMinWidth(const ATitle: string): Integer;
begin
  // ' ' + title + ' ' must sit left of the '[x]' close mark inside the frame.
  if ATitle = '' then
    Result := 1
  else
    Result := Length(ATitle) + 7;
end;

/// <summary>Shift every button row so the group's faces sit in the middle of
/// AClientW, leaving two cells free on the right for ▄ + gap.</summary>
procedure CenterButtonRows(var ADecl: TDialogDeclaration; AClientW: Integer);
var
  Rows: TArray<Integer>;
  I, J, Row, Left, Right, Span, Target, Delta: Integer;
  Found: Boolean;
begin
  if AClientW < 1 then
    Exit;
  SetLength(Rows, 0);
  for I := 0 to High(ADecl.Controls) do
  begin
    if ADecl.Controls[I].Kind <> dckButton then
      Continue;
    Row := ADecl.Controls[I].Row;
    Found := False;
    for J := 0 to High(Rows) do
      if Rows[J] = Row then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      SetLength(Rows, Length(Rows) + 1);
      Rows[High(Rows)] := Row;
    end;
  end;
  for J := 0 to High(Rows) do
  begin
    Row := Rows[J];
    Left := High(Integer);
    Right := 0;
    for I := 0 to High(ADecl.Controls) do
    begin
      if (ADecl.Controls[I].Kind <> dckButton) or
         (ADecl.Controls[I].Row <> Row) then
        Continue;
      if ADecl.Controls[I].Col < Left then
        Left := ADecl.Controls[I].Col;
      if ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1) > Right then
        Right := ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1);
    end;
    if (Left >= Right) or (Left = High(Integer)) then
      Continue;
    Span := Right - Left;
    // Equal margins around the faces; keep two cells after the group.
    Target := (AClientW - Span) div 2;
    if Target + Span + 2 > AClientW then
      Target := AClientW - 2 - Span;
    if Target < 0 then
      Target := 0;
    Delta := Target - Left;
    if Delta = 0 then
      Continue;
    for I := 0 to High(ADecl.Controls) do
      if (ADecl.Controls[I].Kind = dckButton) and
         (ADecl.Controls[I].Row = Row) then
        Inc(ADecl.Controls[I].Col, Delta);
  end;
end;

procedure FitDialogToTranslatedText(var ADecl: TDialogDeclaration);
var
  I, J, ClientW, ContentRight, RightPad, NewClient, NewRight: Integer;
  OrigCol, OrigW, NeedW, NewCol, NewW: TArray<Integer>;
  Stretch, Rule: TArray<Boolean>;
  Cols: TArray<Integer>;
  Extra, Shift: TArray<Integer>;
  Found: Boolean;
begin
  if not IsDialogProtocolV2(ADecl.Version) then
    Exit;
  if Length(ADecl.Controls) = 0 then
  begin
    ADecl.Width := Max(ADecl.Width, TitleMinWidth(ADecl.Title));
    Exit;
  end;

  SetLength(OrigCol, Length(ADecl.Controls));
  SetLength(OrigW, Length(ADecl.Controls));
  SetLength(NeedW, Length(ADecl.Controls));
  SetLength(NewCol, Length(ADecl.Controls));
  SetLength(NewW, Length(ADecl.Controls));
  SetLength(Stretch, Length(ADecl.Controls));
  SetLength(Rule, Length(ADecl.Controls));
  SetLength(Cols, 0);

  ClientW := ClientWidthOf(ADecl.Width);
  ContentRight := 0;
  for I := 0 to High(ADecl.Controls) do
  begin
    OrigCol[I] := ADecl.Controls[I].Col;
    if OrigCol[I] < 0 then
      OrigCol[I] := 0;
    OrigW[I] := ADecl.Controls[I].BoxW;
    if OrigW[I] < 1 then
      OrigW[I] := 1;
    Rule[I] := (ADecl.Controls[I].Kind in [dckLabel, dckStatus]) and
      IsRuleText(ADecl.Controls[I].Text);
    NeedW[I] := Max(OrigW[I], CaptionCells(ADecl.Controls[I]));
    // Buttons keep caption width — do not stretch a rightmost Cancel into
    // a full-width bar when the dialog grows.
    Stretch[I] := (ADecl.Controls[I].Kind <> dckButton) and
      (OrigCol[I] + OrigW[I] >= ClientW - 1);
    if OrigCol[I] + OrigW[I] > ContentRight then
      ContentRight := OrigCol[I] + OrigW[I];
    Found := False;
    for J := 0 to High(Cols) do
      if Cols[J] = OrigCol[I] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      SetLength(Cols, Length(Cols) + 1);
      Cols[High(Cols)] := OrigCol[I];
    end;
  end;
  if ContentRight > ClientW then
    ContentRight := ClientW;
  // At least two client cells past the rightmost control: one for the
  // button's ▄ face shadow (Right+1) and one gap before the frame border.
  RightPad := Max(2, ClientW - ContentRight);

  // Insertion-sort columns so shifts accumulate left to right.
  for I := 1 to High(Cols) do
  begin
    J := I;
    while (J > 0) and (Cols[J] < Cols[J - 1]) do
    begin
      NewRight := Cols[J];
      Cols[J] := Cols[J - 1];
      Cols[J - 1] := NewRight;
      Dec(J);
    end;
  end;

  SetLength(Extra, Length(Cols));
  SetLength(Shift, Length(Cols));
  for I := 0 to High(ADecl.Controls) do
    for J := 0 to High(Cols) do
      if Cols[J] = OrigCol[I] then
      begin
        Extra[J] := Max(Extra[J], NeedW[I] - OrigW[I]);
        Break;
      end;
  for I := 0 to High(Cols) do
  begin
    Shift[I] := 0;
    for J := 0 to I - 1 do
      Inc(Shift[I], Extra[J]);
  end;

  NewRight := 0;
  for I := 0 to High(ADecl.Controls) do
  begin
    NewCol[I] := OrigCol[I];
    NewW[I] := OrigW[I];
    for J := 0 to High(Cols) do
      if Cols[J] = OrigCol[I] then
      begin
        NewCol[I] := OrigCol[I] + Shift[J];
        NewW[I] := OrigW[I] + Extra[J];
        Break;
      end;
    if NewCol[I] + NewW[I] > NewRight then
      NewRight := NewCol[I] + NewW[I];
  end;

  NewClient := Max(ClientW, NewRight + RightPad);
  NewClient := Max(NewClient, TitleMinWidth(ADecl.Title) - 2);

  for I := 0 to High(ADecl.Controls) do
  begin
    if Stretch[I] then
    begin
      // Rules stay flush with both frame sides (same as the source layout).
      // Other stretch controls keep RightPad so a button's ▄ + gap still fit.
      if Rule[I] then
        NewW[I] := Max(NewW[I], NewClient - NewCol[I])
      else
        NewW[I] := Max(NewW[I], NewClient - RightPad - NewCol[I]);
    end;
    if NewW[I] < 1 then
      NewW[I] := 1;
    ADecl.Controls[I].Col := NewCol[I];
    ADecl.Controls[I].BoxW := NewW[I];
    if Rule[I] and (ADecl.Controls[I].Text <> '') then
      ADecl.Controls[I].Text := StringOfChar(ADecl.Controls[I].Text[1], NewW[I]);
  end;
  ADecl.Width := Max(ADecl.Width, NewClient + 2);
  CenterButtonRows(ADecl, ClientWidthOf(ADecl.Width));
end;

end.
