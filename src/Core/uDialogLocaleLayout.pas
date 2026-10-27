unit uDialogLocaleLayout;

{ Widen a protocol-2 dialog after translation so captions fit.

  Cells are columns. The frame occupies one cell on each side, so the
  client width is Decl.Width - 2. Each control keeps its row.

  Controls keep their columns: all controls that started in one column
  still start in one column. A control with a neighbour right of it in its
  row (a label and its field) pushes that neighbour's column so the grown
  caption keeps its authored gap. So a longer label moves only the fields
  after it, and they stay aligned under each other; columns that nothing
  pushes stay where they were. A pushed field keeps its right edge and
  narrows while it can. A control with nothing
  to its right (a hint line, a list) grows in place. A control that reached
  the right client edge stretches with the dialog and keeps its right inset.

  Buttons take no part in the column shifts. Each button row is laid out on
  its own: buttons grow to their captions, keep the gaps between them, and
  the row is centered by its faces, one cell clear of the frame on either
  side. The dialog grows to fit all of this and the title plus the frame's
  close mark. Width never shrinks.

  Controls that start in one column stay in one column, buttons included: a
  final pass (KeepAuthoredColumns) takes the columns the controls had before
  the fitting, moves every group to the rightmost column any member reached
  and pushes what that crowds. Nothing moves left. A button row with a button
  that started in the column of another control is not centered, so the
  alignment holds; the dialog widens if the pushed controls no longer fit. }

interface

uses
  uDialogTypes;

procedure FitDialogToTranslatedText(var ADecl: TDialogDeclaration);

/// <summary>A protocol-2 button, checkbox or radio whose caption does not fit
/// its box (caption + 4 cells for the brackets).</summary>
function DialogCaptionsOverflow(const ADecl: TDialogDeclaration): Boolean;

/// <summary>Fits captions set after the dialog was loaded and fitted (a
/// Build* naming a button after the operation). Row-local, unlike
/// FitDialogToTranslatedText: a button, checkbox or radio grows to its
/// caption and pushes the controls after it in the same row right; an
/// input / drop-down / list pushed that way keeps its right edge and
/// narrows instead, down to cMinFieldCells. The dialog widens only if a row
/// still overflows; button rows are recentered. Label text (a path, a file
/// name) never widens the dialog here.</summary>
procedure FitDialogCaptions(var ADecl: TDialogDeclaration);

implementation

uses
  System.SysUtils, System.Math, uThemeTypes, uDialogRenderer, uCharWidth;

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
    N := TextDisplayWidth(Copy(AText, Start, I - Start));
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
    N := TextDisplayWidth(AItems[I]) + AExtra;
    if N > Result then
      Result := N;
  end;
end;

function CaptionCells(const C: TDialogControl): Integer;
begin
  case C.Kind of
    dckButton, dckCheckbox, dckRadio:
      Result := TextDisplayWidth(StripHotKeyMarker(C.Text)) + 4;
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
      Result := Max(MaxItemCells(C.Items, 4), TextDisplayWidth(C.Text));
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
    Result := TextDisplayWidth(ATitle) + 7;
end;

const
  cCaptionKinds = [dckButton, dckCheckbox, dckRadio];
  cFieldKinds = [dckInput, dckDropDown, dckList];
  cMinFieldCells = 8;

/// <summary>The column of every control, as a snapshot taken before a fitting
/// pass: controls that share a value start in one column and are to stay so.</summary>
function SnapshotColumns(const ADecl: TDialogDeclaration): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Length(ADecl.Controls));
  for I := 0 to High(ADecl.Controls) do
    Result[I] := Max(ADecl.Controls[I].Col, 0);
end;

/// <summary>True when another control started in the same column as the control
/// at AIndex in the snapshot AGroupCol.</summary>
function SharesColumn(const AGroupCol: TArray<Integer>; AIndex: Integer): Boolean;
var
  J: Integer;
begin
  Result := False;
  if Length(AGroupCol) = 0 then
    Exit;
  for J := 0 to High(AGroupCol) do
    if (J <> AIndex) and (AGroupCol[J] = AGroupCol[AIndex]) then
      Exit(True);
end;

/// <summary>Moves a control right by ADelta. A field keeps its right edge
/// while it stays at least cMinFieldCells wide; anything else keeps its width.</summary>
procedure MoveControlRight(var AControl: TDialogControl; ADelta: Integer);
begin
  if ADelta <= 0 then
    Exit;
  if (AControl.Kind in cFieldKinds) and (Max(AControl.BoxW, 1) - ADelta >= cMinFieldCells) then
    Dec(AControl.BoxW, ADelta);
  Inc(AControl.Col, ADelta);
end;

/// <summary>Pushes a control right when the one before it in a row reaches it
/// (a button also owns the cell of its shadow). True when something moved.</summary>
function ResolveRowOverlaps(var ADecl: TDialogDeclaration): Boolean;
var
  Row, I, J, K, Tmp, Free, Top, Bottom: Integer;
  Order: TArray<Integer>;
begin
  Result := False;
  Top := High(Integer);
  Bottom := -1;
  for I := 0 to High(ADecl.Controls) do
  begin
    Top := Min(Top, Max(ADecl.Controls[I].Row, 0));
    Bottom := Max(Bottom, Max(ADecl.Controls[I].Row, 0) + Max(ADecl.Controls[I].BoxH, 1) - 1);
  end;
  for Row := Top to Bottom do
  begin
    Order := nil;
    for I := 0 to High(ADecl.Controls) do
      if (Max(ADecl.Controls[I].Row, 0) <= Row) and
         (Row <= Max(ADecl.Controls[I].Row, 0) + Max(ADecl.Controls[I].BoxH, 1) - 1) then
        Order := Order + [I];
    for J := 1 to High(Order) do
    begin
      K := J;
      while (K > 0) and (ADecl.Controls[Order[K]].Col < ADecl.Controls[Order[K - 1]].Col) do
      begin
        Tmp := Order[K];
        Order[K] := Order[K - 1];
        Order[K - 1] := Tmp;
        Dec(K);
      end;
    end;
    Free := 0;
    for J := 0 to High(Order) do
    begin
      I := Order[J];
      if (J > 0) and (ADecl.Controls[I].Col < Free) then
      begin
        MoveControlRight(ADecl.Controls[I], Free - ADecl.Controls[I].Col);
        Result := True;
      end;
      Free := Max(Free, ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1));
      if ADecl.Controls[I].Kind = dckButton then
        Inc(Free);
    end;
  end;
end;

/// <summary>Controls that started in one column (AGroupCol, a SnapshotColumns taken
/// before the pass) stay in one column, whatever the
/// captions, the translation or the neighbours did to their positions and
/// widths: the whole group moves to the rightmost column any of its members
/// reached, and what that crowds is pushed right too. Nothing moves left. The
/// dialog widens when a control no longer fits, and what reached its right
/// edge stretches with it.</summary>
procedure KeepAuthoredColumns(var ADecl: TDialogDeclaration;
  const AGroupCol: TArray<Integer>);
var
  I, J, Pass, Target, Members, OldClient, Over, Extra: Integer;
  Cols: TArray<Integer>;
  Moved, Seen: Boolean;
begin
  if ADecl.NoAutoLayout or not IsDialogProtocolV2(ADecl.Version) or
     (Length(ADecl.Controls) < 2) or (Length(AGroupCol) <> Length(ADecl.Controls)) then
    Exit;
  OldClient := ClientWidthOf(ADecl.Width);
  Cols := nil;
  for I := 0 to High(AGroupCol) do
  begin
    Seen := False;
    for J := 0 to High(Cols) do
      if Cols[J] = AGroupCol[I] then
        Seen := True;
    if not Seen then
      Cols := Cols + [AGroupCol[I]];
  end;

  for Pass := 1 to 32 do
  begin
    Moved := False;
    for J := 0 to High(Cols) do
    begin
      Target := -1;
      Members := 0;
      for I := 0 to High(ADecl.Controls) do
        if AGroupCol[I] = Cols[J] then
        begin
          Inc(Members);
          Target := Max(Target, ADecl.Controls[I].Col);
        end;
      if Members < 2 then
        Continue;
      for I := 0 to High(ADecl.Controls) do
        if (AGroupCol[I] = Cols[J]) and (ADecl.Controls[I].Col < Target) then
        begin
          MoveControlRight(ADecl.Controls[I], Target - ADecl.Controls[I].Col);
          Moved := True;
        end;
    end;
    if ResolveRowOverlaps(ADecl) then
      Moved := True;
    if not Moved then
      Break;
  end;

  // Widen for whatever no longer fits (a button also needs its shadow and a
  // clear cell), and stretch what reached the old right edge.
  Over := 0;
  for I := 0 to High(ADecl.Controls) do
  begin
    Extra := 0;
    if ADecl.Controls[I].Kind = dckButton then
      Extra := 2;
    Over := Max(Over, ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1) + Extra - OldClient);
  end;
  if Over <= 0 then
    Exit;
  for I := 0 to High(ADecl.Controls) do
    if (ADecl.Controls[I].Kind in [dckList, dckInput, dckDropDown, dckLabel]) and
       (OldClient - (ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1)) <= 1) and
       (OldClient - (ADecl.Controls[I].Col + Max(ADecl.Controls[I].BoxW, 1)) >= 0) then
    begin
      Inc(ADecl.Controls[I].BoxW, Over);
      if (ADecl.Controls[I].Kind = dckLabel) and IsRuleText(ADecl.Controls[I].Text) then
        ADecl.Controls[I].Text := StringOfChar(ADecl.Controls[I].Text[1],
          ADecl.Controls[I].BoxW);
    end;
  Inc(ADecl.Width, Over);
end;

/// <summary>Center every button row in AClientW by its faces, not counting the
/// last face's shadow; the row stays one cell clear of the frame on the left
/// and after the shadow on the right when it fits.</summary>
procedure CenterButtonRows(var ADecl: TDialogDeclaration; AClientW: Integer;
  const AGroupCol: TArray<Integer>);
var
  Rows: TArray<Integer>;
  I, J, Row, Left, Right, Span, Target, Delta: Integer;
  Found, Anchored: Boolean;
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
    // Centered by the faces alone; the last one's shadow hangs to the right
    // and must still fit before the frame.
    // A row with a button that started in the column of another control stays
    // there: centering would break that alignment.
    Anchored := False;
    for I := 0 to High(ADecl.Controls) do
      if (ADecl.Controls[I].Kind = dckButton) and (ADecl.Controls[I].Row = Row) and
         SharesColumn(AGroupCol, I) then
        Anchored := True;
    if Anchored then
      Continue;
    Span := Right - Left;
    Target := (AClientW - Span) div 2;
    if Target + Span + 1 > AClientW then
      Target := AClientW - 1 - Span;
    if Target < 1 then
      Target := Min(1, Max(AClientW - Span - 1, 0));
    Delta := Target - Left;
    if Delta = 0 then
      Continue;
    for I := 0 to High(ADecl.Controls) do
      if (ADecl.Controls[I].Kind = dckButton) and
         (ADecl.Controls[I].Row = Row) then
        Inc(ADecl.Controls[I].Col, Delta);
  end;
end;

/// <summary>Buttons of each row grow to their captions and keep the gaps
/// between them, left to right from the row's first column. Returns the
/// client width the widest row needs: faces, the last shadow and one clear
/// cell on each side.</summary>
function PackButtonRows(var ADecl: TDialogDeclaration): Integer;
var
  I, J, K, Tmp, Col, Gap: Integer;
  Order: TArray<Integer>;
  Done: TArray<Boolean>;
begin
  Result := 0;
  SetLength(Done, Length(ADecl.Controls));
  for I := 0 to High(ADecl.Controls) do
  begin
    if (ADecl.Controls[I].Kind <> dckButton) or Done[I] then
      Continue;
    Order := nil;
    for J := I to High(ADecl.Controls) do
      if (ADecl.Controls[J].Kind = dckButton) and
         (ADecl.Controls[J].Row = ADecl.Controls[I].Row) then
      begin
        Order := Order + [J];
        Done[J] := True;
      end;
    for J := 1 to High(Order) do
    begin
      K := J;
      while (K > 0) and (ADecl.Controls[Order[K]].Col < ADecl.Controls[Order[K - 1]].Col) do
      begin
        Tmp := Order[K];
        Order[K] := Order[K - 1];
        Order[K - 1] := Tmp;
        Dec(K);
      end;
    end;
    Col := Max(ADecl.Controls[Order[0]].Col, 0);
    for J := 0 to High(Order) do
    begin
      K := Order[J];
      if J > 0 then
      begin
        // The authored gap to the previous face, at least its shadow and
        // one clear cell.
        Gap := ADecl.Controls[K].Col -
          (ADecl.Controls[Order[J - 1]].Col + Max(ADecl.Controls[Order[J - 1]].BoxW, 1));
        Inc(Col, Max(Gap, 2));
      end;
      Tmp := Max(Max(ADecl.Controls[K].BoxW, 1), CaptionCells(ADecl.Controls[K]));
      ADecl.Controls[K].Col := Col;
      ADecl.Controls[K].BoxW := Tmp;
      Inc(Col, Tmp);
    end;
    // Faces and the last shadow, one clear cell on each side.
    Result := Max(Result, Col - ADecl.Controls[Order[0]].Col + 1 + 2);
  end;
end;

procedure FitDialogToTranslatedText(var ADecl: TDialogDeclaration);
var
  I, J, ClientW, NewClient, Tmp, Lim: Integer;
  OrigCol, OrigW, NeedW, NewCol, NewW, Inset: TArray<Integer>;
  Stretch, Rule: TArray<Boolean>;
  Next, Cols, Pos, GroupCol: TArray<Integer>;

  function IsButton(AIndex: Integer): Boolean;
  begin
    Result := ADecl.Controls[AIndex].Kind = dckButton;
  end;

  function LastRow(AIndex: Integer): Integer;
  begin
    Result := ADecl.Controls[AIndex].Row + Max(ADecl.Controls[AIndex].BoxH, 1) - 1;
  end;

  function ColumnOf(ACol: Integer): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Cols) do
      if Cols[K] = ACol then
        Exit(K);
    Result := -1;
  end;

begin
  if ADecl.NoAutoLayout or not IsDialogProtocolV2(ADecl.Version) then
    Exit;
  if Length(ADecl.Controls) = 0 then
  begin
    ADecl.Width := Max(ADecl.Width, TitleMinWidth(ADecl.Title));
    Exit;
  end;

  GroupCol := SnapshotColumns(ADecl);
  SetLength(OrigCol, Length(ADecl.Controls));
  SetLength(OrigW, Length(ADecl.Controls));
  SetLength(NeedW, Length(ADecl.Controls));
  SetLength(NewCol, Length(ADecl.Controls));
  SetLength(NewW, Length(ADecl.Controls));
  SetLength(Inset, Length(ADecl.Controls));
  SetLength(Stretch, Length(ADecl.Controls));
  SetLength(Rule, Length(ADecl.Controls));
  SetLength(Next, Length(ADecl.Controls));
  Cols := nil;

  ClientW := ClientWidthOf(ADecl.Width);
  for I := 0 to High(ADecl.Controls) do
  begin
    OrigCol[I] := Max(ADecl.Controls[I].Col, 0);
    OrigW[I] := Max(ADecl.Controls[I].BoxW, 1);
    Rule[I] := (ADecl.Controls[I].Kind in [dckLabel, dckStatus]) and
      IsRuleText(ADecl.Controls[I].Text);
    NeedW[I] := Max(OrigW[I], CaptionCells(ADecl.Controls[I]));
    Inset[I] := Max(ClientW - (OrigCol[I] + OrigW[I]), 0);
    Stretch[I] := not IsButton(I) and (Inset[I] <= 1);
    if not IsButton(I) and (ColumnOf(OrigCol[I]) < 0) then
      Cols := Cols + [OrigCol[I]];
  end;

  // Next: the nearest non-button control right of each one in its rows.
  for I := 0 to High(ADecl.Controls) do
  begin
    Next[I] := -1;
    if IsButton(I) then
      Continue;
    for J := 0 to High(ADecl.Controls) do
      if (J <> I) and not IsButton(J) and (OrigCol[J] > OrigCol[I]) and
         (ADecl.Controls[J].Row <= LastRow(I)) and
         (ADecl.Controls[I].Row <= LastRow(J)) and
         ((Next[I] < 0) or (OrigCol[J] < OrigCol[Next[I]])) then
        Next[I] := J;
  end;

  // Insertion-sort columns so shifts accumulate left to right.
  for I := 1 to High(Cols) do
  begin
    J := I;
    while (J > 0) and (Cols[J] < Cols[J - 1]) do
    begin
      Tmp := Cols[J];
      Cols[J] := Cols[J - 1];
      Cols[J - 1] := Tmp;
      Dec(J);
    end;
  end;

  // New column positions, left to right: never left of the authored one,
  // and past every grown control whose right neighbour starts here, by that
  // control's authored gap. Columns of different rows do not push each
  // other: controls on different rows cannot collide.
  SetLength(Pos, Length(Cols));
  for J := 0 to High(Cols) do
  begin
    Pos[J] := Cols[J];
    for I := 0 to High(ADecl.Controls) do
      if not IsButton(I) and (Next[I] >= 0) and (OrigCol[Next[I]] = Cols[J]) then
      begin
        Tmp := Max(Cols[J] - (OrigCol[I] + OrigW[I]), 1);
        Pos[J] := Max(Pos[J], Pos[ColumnOf(OrigCol[I])] + NeedW[I] + Tmp);
      end;
  end;

  NewClient := ClientW;
  for I := 0 to High(ADecl.Controls) do
  begin
    if IsButton(I) then
      Continue;
    NewCol[I] := Pos[ColumnOf(OrigCol[I])];
    NewW[I] := NeedW[I];
    // A field pushed right narrows only if it would pass the frame (its
    // authored inset when it reached the edge, else one clear cell), and not
    // below cMinFieldCells or its longest item.
    if (ADecl.Controls[I].Kind in cFieldKinds) and (NewCol[I] > OrigCol[I]) then
    begin
      Tmp := cMinFieldCells;
      if ADecl.Controls[I].Kind <> dckInput then
        Tmp := Max(Tmp, CaptionCells(ADecl.Controls[I]));
      if Stretch[I] then
        Lim := ClientW - Inset[I] - NewCol[I]
      else
        Lim := ClientW - 1 - NewCol[I];
      NewW[I] := Max(Min(OrigW[I], Lim), Min(Tmp, OrigW[I]));
    end;
    // A control that reached the right edge keeps its inset; any other one
    // needs at least one clear cell before the frame.
    if Stretch[I] then
      NewClient := Max(NewClient, NewCol[I] + NewW[I] + Inset[I])
    else
      NewClient := Max(NewClient, NewCol[I] + NewW[I] + 1);
  end;
  NewClient := Max(NewClient, PackButtonRows(ADecl));
  NewClient := Max(NewClient, TitleMinWidth(ADecl.Title) - 2);

  for I := 0 to High(ADecl.Controls) do
  begin
    if IsButton(I) then
      Continue;
    if Stretch[I] then
    begin
      // A rule keeps the same inset on both sides; any other control keeps
      // its authored right inset.
      if Rule[I] then
        NewW[I] := Max(1, NewClient - 2 * NewCol[I])
      else
        NewW[I] := Max(NewW[I], NewClient - Inset[I] - NewCol[I]);
    end;
    ADecl.Controls[I].Col := NewCol[I];
    ADecl.Controls[I].BoxW := Max(NewW[I], 1);
    if Rule[I] and (ADecl.Controls[I].Text <> '') then
      ADecl.Controls[I].Text := StringOfChar(ADecl.Controls[I].Text[1],
        ADecl.Controls[I].BoxW);
  end;
  ADecl.Width := Max(ADecl.Width, NewClient + 2);
  KeepAuthoredColumns(ADecl, GroupCol);
  CenterButtonRows(ADecl, ClientWidthOf(ADecl.Width), GroupCol);
end;

function DialogCaptionsOverflow(const ADecl: TDialogDeclaration): Boolean;
var
  I: Integer;
begin
  Result := False;
  if ADecl.NoAutoLayout or not IsDialogProtocolV2(ADecl.Version) then
    Exit;
  for I := 0 to High(ADecl.Controls) do
    if (ADecl.Controls[I].Kind in cCaptionKinds) and
       (CaptionCells(ADecl.Controls[I]) > Max(ADecl.Controls[I].BoxW, 1)) then
      Exit(True);
end;

procedure FitDialogCaptions(var ADecl: TDialogDeclaration);
var
  Rows, Order: TArray<Integer>;
  I, J, K, Row, Tmp, Col, OrigCol, W, FreeCol, NewClient, OldClient, Delta: Integer;
  ButtonsGrew, Grew: Boolean;
  GroupCol: TArray<Integer>;
begin
  if not DialogCaptionsOverflow(ADecl) then
    Exit;
  GroupCol := SnapshotColumns(ADecl);
  NewClient := ClientWidthOf(ADecl.Width);
  OldClient := NewClient;
  ButtonsGrew := False;

  Rows := nil;
  for I := 0 to High(ADecl.Controls) do
  begin
    Row := ADecl.Controls[I].Row;
    J := 0;
    while (J <= High(Rows)) and (Rows[J] <> Row) do
      Inc(J);
    if J > High(Rows) then
      Rows := Rows + [Row];
  end;

  for Row in Rows do
  begin
    // This row's controls, left to right.
    Order := nil;
    for I := 0 to High(ADecl.Controls) do
      if ADecl.Controls[I].Row = Row then
        Order := Order + [I];
    for I := 1 to High(Order) do
    begin
      J := I;
      while (J > 0) and (ADecl.Controls[Order[J]].Col < ADecl.Controls[Order[J - 1]].Col) do
      begin
        Tmp := Order[J];
        Order[J] := Order[J - 1];
        Order[J - 1] := Tmp;
        Dec(J);
      end;
    end;

    // FreeCol: first column the next control may start at -- right after
    // the previous one (plus its ▄ shadow for a button), and one blank cell
    // further if it grew, so a longer caption never runs into the next
    // control. Rows where nothing grew keep their authored columns.
    FreeCol := 0;
    for K in Order do
    begin
      OrigCol := Max(ADecl.Controls[K].Col, 0);
      Col := Max(OrigCol, FreeCol);
      W := Max(ADecl.Controls[K].BoxW, 1);
      // A field pushed right keeps its right edge while it can.
      if (Col > OrigCol) and (ADecl.Controls[K].Kind in cFieldKinds) and
         (W - (Col - OrigCol) >= cMinFieldCells) then
        Dec(W, Col - OrigCol);
      Grew := (ADecl.Controls[K].Kind in cCaptionKinds) and
        (CaptionCells(ADecl.Controls[K]) > W);
      if Grew then
      begin
        W := CaptionCells(ADecl.Controls[K]);
        if ADecl.Controls[K].Kind = dckButton then
          ButtonsGrew := True;
      end;
      ADecl.Controls[K].Col := Col;
      ADecl.Controls[K].BoxW := W;
      FreeCol := Col + W;
      if ADecl.Controls[K].Kind = dckButton then
        Inc(FreeCol); // ▄ shadow
      if Grew then
        Inc(FreeCol);
      // Client right edge: a button needs its shadow and a gap before the
      // frame; a grown caption needs one clear cell before it. A control
      // that did not grow keeps its authored edge.
      if ADecl.Controls[K].Kind = dckButton then
        NewClient := Max(NewClient, Col + W + 2)
      else if Grew then
        NewClient := Max(NewClient, Col + W + 1)
      else
        NewClient := Max(NewClient, Col + W);
    end;
  end;

  ADecl.Width := Max(ADecl.Width, NewClient + 2);
  // Lists, fields and rules that reached the right edge stretch with the
  // dialog and keep their inset.
  Delta := ClientWidthOf(ADecl.Width) - OldClient;
  if Delta > 0 then
    for I := 0 to High(ADecl.Controls) do
      if (ADecl.Controls[I].Kind in [dckList, dckInput, dckDropDown, dckLabel]) and
         (OldClient - (ADecl.Controls[I].Col + ADecl.Controls[I].BoxW) <= 1) and
         (OldClient - (ADecl.Controls[I].Col + ADecl.Controls[I].BoxW) >= 0) then
      begin
        Inc(ADecl.Controls[I].BoxW, Delta);
        if (ADecl.Controls[I].Kind = dckLabel) and IsRuleText(ADecl.Controls[I].Text) then
          ADecl.Controls[I].Text := StringOfChar(ADecl.Controls[I].Text[1],
            ADecl.Controls[I].BoxW);
      end;
  OldClient := ClientWidthOf(ADecl.Width);
  KeepAuthoredColumns(ADecl, GroupCol);
  if ButtonsGrew or (Delta > 0) or (ClientWidthOf(ADecl.Width) <> OldClient) then
    CenterButtonRows(ADecl, ClientWidthOf(ADecl.Width), GroupCol);
end;

end.
