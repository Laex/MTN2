unit uDiffMerge;

{ Side-by-side line diff of two texts with hunk-wise merging.

  The model keeps both texts as lines. A hunk is a run of lines that differ;
  copying a hunk replaces its lines on one side by the other side's lines, so the
  hunk disappears and the rows are rebuilt. Every copy can be undone.
  Splitting and joining keep the line break style and the final line break of
  the file, so a text that was not edited is written back unchanged. }

interface

uses
  System.SysUtils, System.Generics.Collections, uFileCompare;

type
  TDiffRowKind = (drEqual, drChanged, drLeftOnly, drRightOnly);

  TDiffRow = record
    Kind: TDiffRowKind;
    Left, Right: string;
    /// <summary>1-based line numbers; 0 when the side has no line in this row.</summary>
    LeftNo, RightNo: Integer;
    /// <summary>Index into Hunks; -1 for an equal row.</summary>
    Hunk: Integer;
  end;

  THunk = record
    /// <summary>0-based first line and number of lines on each side.</summary>
    LeftStart, LeftCount, RightStart, RightCount: Integer;
    /// <summary>Index of the hunk's first row.</summary>
    FirstRow: Integer;
  end;

  TDiffSnapshot = record
    Left, Right: TArray<string>;
    LeftDirty, RightDirty: Boolean;
  end;

  TDiffMerge = class
  private
    FLeft, FRight: TArray<string>;
    FRows: TArray<TDiffRow>;
    FHunks: TArray<THunk>;
    FUndo: TList<TDiffSnapshot>;
    FLeftDirty, FRightDirty: Boolean;
    procedure Rebuild;
  public
    constructor Create(const ALeft, ARight: TArray<string>);
    destructor Destroy; override;
    property Rows: TArray<TDiffRow> read FRows;
    property Hunks: TArray<THunk> read FHunks;
    property LeftLines: TArray<string> read FLeft;
    property RightLines: TArray<string> read FRight;
    property LeftDirty: Boolean read FLeftDirty;
    property RightDirty: Boolean read FRightDirty;
    function HunkCount: Integer;
    /// <summary>The hunk the row belongs to, -1 for an equal row or a bad index.</summary>
    function HunkOfRow(ARow: Integer): Integer;
    /// <summary>First row of the first hunk that starts after ARow's hunk (or after
    /// ARow itself for an equal row); -1 when there is none.</summary>
    function NextHunkRow(ARow: Integer): Integer;
    /// <summary>First row of the last hunk that starts before ARow's hunk (or before
    /// ARow itself for an equal row); -1 when there is none.</summary>
    function PrevHunkRow(ARow: Integer): Integer;
    /// <summary>Replaces the right lines of the hunk by the left ones (AToRight) or the
    /// other way round. False for a bad hunk index.</summary>
    function CopyHunk(AHunk: Integer; AToRight: Boolean): Boolean;
    function CanUndo: Boolean;
    procedure Undo;
    /// <summary>The saved side counts as unchanged again.</summary>
    procedure MarkSaved(ALeft, ARight: Boolean);
  end;

/// <summary>Lines of AText. AEol is the dominant line break (CR LF when tied) and
/// AFinalEol tells whether the text ends with one; no trailing empty line is made.</summary>
function SplitTextLines(const AText: string; out AEol: string;
  out AFinalEol: Boolean): TArray<string>;
function JoinTextLines(const ALines: TArray<string>; const AEol: string;
  AFinalEol: Boolean): string;

/// <summary>The three cells between the two texts: "|", "~", "<" or ">".</summary>
function DiffRowMarker(AKind: TDiffRowKind): string;
/// <summary>The part of two lines that differs: what is left after the common
/// start and the common end. AStart is 0-based and the same on both sides; the
/// lengths may be 0 (text only inserted on the other side).</summary>
procedure DiffInnerSpan(const ALeft, ARight: string; out AStart, ALeftLen,
  ARightLen: Integer);

implementation

uses
  System.Math;

const
  // Pairing two lines always scores a little, so unrelated lines in the same
  // position still show as one changed row; a similar line elsewhere wins.
  cPairBonus = 0.05;
  // Beyond this many line pairs in one hunk the alignment is positional.
  cMaxAlignCells = 400000;

// Sorted character bigrams of the line without surrounding blanks.
function LineBigrams(const AText: string): TArray<Cardinal>;
var
  T: string;
  I: Integer;
begin
  T := Trim(AText);
  if Length(T) < 2 then
  begin
    SetLength(Result, Length(T));
    if Length(T) = 1 then
      Result[0] := Cardinal(Ord(T[1]));
    Exit;
  end;
  SetLength(Result, Length(T) - 1);
  for I := 1 to Length(T) - 1 do
    Result[I - 1] := (Cardinal(Ord(T[I])) shl 16) or Cardinal(Ord(T[I + 1]));
  TArray.Sort<Cardinal>(Result);
end;

// Dice coefficient of two bigram multisets: 0 (nothing shared) .. 1 (same).
function BigramSimilarity(const A, B: TArray<Cardinal>): Double;
var
  I, J, Common: Integer;
begin
  if (Length(A) = 0) and (Length(B) = 0) then
    Exit(1.0);
  Common := 0;
  I := 0;
  J := 0;
  while (I < Length(A)) and (J < Length(B)) do
    if A[I] = B[J] then
    begin
      Inc(Common);
      Inc(I);
      Inc(J);
    end
    else if A[I] < B[J] then
      Inc(I)
    else
      Inc(J);
  Result := 2 * Common / (Length(A) + Length(B));
end;

// For every deleted line the index of the inserted line shown beside it, or -1.
// The pairs keep their order and maximise the total similarity, so a changed
// line meets its edited version even when other lines were added around it.
function AlignHunkLines(const ADels, AIns: TArray<string>): TArray<Integer>;
var
  N, M, W, I, J: Integer;
  Score: TArray<Double>;
  BA, BB: TArray<TArray<Cardinal>>;
  Diag, Cur: Double;
begin
  N := Length(ADels);
  M := Length(AIns);
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := -1;
  if (N = 0) or (M = 0) then
    Exit;
  if Int64(N) * M > cMaxAlignCells then
  begin
    for I := 0 to Min(N, M) - 1 do
      Result[I] := I;
    Exit;
  end;
  SetLength(BA, N);
  for I := 0 to N - 1 do
    BA[I] := LineBigrams(ADels[I]);
  SetLength(BB, M);
  for J := 0 to M - 1 do
    BB[J] := LineBigrams(AIns[J]);
  W := M + 1;
  SetLength(Score, (N + 1) * W);
  for I := 1 to N do
    for J := 1 to M do
    begin
      Diag := Score[(I - 1) * W + J - 1] + BigramSimilarity(BA[I - 1], BB[J - 1]) +
        cPairBonus;
      Score[I * W + J] := Max(Diag, Max(Score[(I - 1) * W + J], Score[I * W + J - 1]));
    end;
  // Ties walk away from the end, so the earlier lines are the ones that pair.
  I := N;
  J := M;
  while (I > 0) and (J > 0) do
  begin
    Cur := Score[I * W + J];
    if Score[(I - 1) * W + J] = Cur then
      Dec(I)
    else if Score[I * W + J - 1] = Cur then
      Dec(J)
    else
    begin
      Result[I - 1] := J - 1;
      Dec(I);
      Dec(J);
    end;
  end;
end;

constructor TDiffMerge.Create(const ALeft, ARight: TArray<string>);
begin
  inherited Create;
  FUndo := TList<TDiffSnapshot>.Create;
  FLeft := Copy(ALeft);
  FRight := Copy(ARight);
  Rebuild;
end;

destructor TDiffMerge.Destroy;
begin
  FUndo.Free;
  inherited;
end;

procedure TDiffMerge.Rebuild;
var
  Spans: TArray<TDiffSpan>;
  Dels, Ins: TArray<string>;
  I, J, K, LeftPos, RightPos, NextIns, RowCount, Hunk: Integer;
  Match: TArray<Integer>;

  procedure AddRow(AKind: TDiffRowKind; const ALeft, ARight: string;
    ALeftNo, ARightNo, AHunk: Integer);
  begin
    if RowCount = Length(FRows) then
      SetLength(FRows, Max(RowCount * 2, 16));
    FRows[RowCount].Kind := AKind;
    FRows[RowCount].Left := ALeft;
    FRows[RowCount].Right := ARight;
    FRows[RowCount].LeftNo := ALeftNo;
    FRows[RowCount].RightNo := ARightNo;
    FRows[RowCount].Hunk := AHunk;
    Inc(RowCount);
  end;

begin
  Spans := DiffLineSpans(FLeft, FRight);
  SetLength(FRows, 0);
  SetLength(FHunks, 0);
  RowCount := 0;
  LeftPos := 0;
  RightPos := 0;
  I := 0;
  while I <= High(Spans) do
  begin
    if Spans[I].Kind = dkEqual then
    begin
      AddRow(drEqual, Spans[I].Text, Spans[I].Text, LeftPos + 1, RightPos + 1, -1);
      Inc(LeftPos);
      Inc(RightPos);
      Inc(I);
      Continue;
    end;
    SetLength(Dels, 0);
    SetLength(Ins, 0);
    J := I;
    while (J <= High(Spans)) and (Spans[J].Kind <> dkEqual) do
    begin
      if Spans[J].Kind = dkDelete then
      begin
        SetLength(Dels, Length(Dels) + 1);
        Dels[High(Dels)] := Spans[J].Text;
      end
      else
      begin
        SetLength(Ins, Length(Ins) + 1);
        Ins[High(Ins)] := Spans[J].Text;
      end;
      Inc(J);
    end;
    Hunk := Length(FHunks);
    SetLength(FHunks, Hunk + 1);
    FHunks[Hunk].LeftStart := LeftPos;
    FHunks[Hunk].LeftCount := Length(Dels);
    FHunks[Hunk].RightStart := RightPos;
    FHunks[Hunk].RightCount := Length(Ins);
    FHunks[Hunk].FirstRow := RowCount;
    Match := AlignHunkLines(Dels, Ins);
    NextIns := 0;
    for K := 0 to High(Dels) do
      if Match[K] < 0 then
        AddRow(drLeftOnly, Dels[K], '', LeftPos + K + 1, 0, Hunk)
      else
      begin
        while NextIns < Match[K] do
        begin
          AddRow(drRightOnly, '', Ins[NextIns], 0, RightPos + NextIns + 1, Hunk);
          Inc(NextIns);
        end;
        AddRow(drChanged, Dels[K], Ins[NextIns], LeftPos + K + 1,
          RightPos + NextIns + 1, Hunk);
        Inc(NextIns);
      end;
    while NextIns <= High(Ins) do
    begin
      AddRow(drRightOnly, '', Ins[NextIns], 0, RightPos + NextIns + 1, Hunk);
      Inc(NextIns);
    end;
    Inc(LeftPos, Length(Dels));
    Inc(RightPos, Length(Ins));
    I := J;
  end;
  SetLength(FRows, RowCount);
end;

function TDiffMerge.HunkCount: Integer;
begin
  Result := Length(FHunks);
end;

function TDiffMerge.HunkOfRow(ARow: Integer): Integer;
begin
  if (ARow < 0) or (ARow > High(FRows)) then
    Result := -1
  else
    Result := FRows[ARow].Hunk;
end;

function TDiffMerge.NextHunkRow(ARow: Integer): Integer;
var
  H, I: Integer;
begin
  Result := -1;
  H := HunkOfRow(ARow);
  if H >= 0 then
  begin
    if H < High(FHunks) then
      Result := FHunks[H + 1].FirstRow;
    Exit;
  end;
  for I := Max(ARow, -1) + 1 to High(FRows) do
    if FRows[I].Hunk >= 0 then
      Exit(FHunks[FRows[I].Hunk].FirstRow);
end;

function TDiffMerge.PrevHunkRow(ARow: Integer): Integer;
var
  H, I: Integer;
begin
  Result := -1;
  H := HunkOfRow(ARow);
  if H >= 0 then
  begin
    if H > 0 then
      Result := FHunks[H - 1].FirstRow;
    Exit;
  end;
  for I := Min(ARow, Length(FRows)) - 1 downto 0 do
    if FRows[I].Hunk >= 0 then
      Exit(FHunks[FRows[I].Hunk].FirstRow);
end;

function TDiffMerge.CopyHunk(AHunk: Integer; AToRight: Boolean): Boolean;
var
  H: THunk;
  Snap: TDiffSnapshot;
  Source, Target, NewLines: TArray<string>;
  SrcStart, SrcCount, DstStart, DstCount, I: Integer;
begin
  Result := (AHunk >= 0) and (AHunk <= High(FHunks));
  if not Result then
    Exit;
  H := FHunks[AHunk];
  Snap.Left := FLeft;
  Snap.Right := FRight;
  Snap.LeftDirty := FLeftDirty;
  Snap.RightDirty := FRightDirty;
  FUndo.Add(Snap);
  if AToRight then
  begin
    Source := FLeft;
    Target := FRight;
    SrcStart := H.LeftStart;
    SrcCount := H.LeftCount;
    DstStart := H.RightStart;
    DstCount := H.RightCount;
  end
  else
  begin
    Source := FRight;
    Target := FLeft;
    SrcStart := H.RightStart;
    SrcCount := H.RightCount;
    DstStart := H.LeftStart;
    DstCount := H.LeftCount;
  end;
  SetLength(NewLines, Length(Target) - DstCount + SrcCount);
  for I := 0 to DstStart - 1 do
    NewLines[I] := Target[I];
  for I := 0 to SrcCount - 1 do
    NewLines[DstStart + I] := Source[SrcStart + I];
  for I := DstStart + DstCount to High(Target) do
    NewLines[I - DstCount + SrcCount] := Target[I];
  if AToRight then
  begin
    FRight := NewLines;
    FRightDirty := True;
  end
  else
  begin
    FLeft := NewLines;
    FLeftDirty := True;
  end;
  Rebuild;
end;

function TDiffMerge.CanUndo: Boolean;
begin
  Result := FUndo.Count > 0;
end;

procedure TDiffMerge.Undo;
var
  Snap: TDiffSnapshot;
begin
  if FUndo.Count = 0 then
    Exit;
  Snap := FUndo[FUndo.Count - 1];
  FUndo.Delete(FUndo.Count - 1);
  FLeft := Snap.Left;
  FRight := Snap.Right;
  FLeftDirty := Snap.LeftDirty;
  FRightDirty := Snap.RightDirty;
  Rebuild;
end;

procedure TDiffMerge.MarkSaved(ALeft, ARight: Boolean);
var
  I: Integer;
  Snap: TDiffSnapshot;
begin
  if ALeft then
    FLeftDirty := False;
  if ARight then
    FRightDirty := False;
  // A saved side is the new baseline: undoing past the save would make the file
  // and the screen disagree without the side being marked changed.
  for I := 0 to FUndo.Count - 1 do
  begin
    Snap := FUndo[I];
    if ALeft then
      Snap.LeftDirty := True;
    if ARight then
      Snap.RightDirty := True;
    FUndo[I] := Snap;
  end;
end;

function SplitTextLines(const AText: string; out AEol: string;
  out AFinalEol: Boolean): TArray<string>;
var
  I, Start, Count, Crlf, Lf, Cr, N: Integer;
begin
  Crlf := 0;
  Lf := 0;
  Cr := 0;
  N := Length(AText);
  I := 1;
  while I <= N do
  begin
    if AText[I] = #13 then
    begin
      if (I < N) and (AText[I + 1] = #10) then
      begin
        Inc(Crlf);
        Inc(I);
      end
      else
        Inc(Cr);
    end
    else if AText[I] = #10 then
      Inc(Lf);
    Inc(I);
  end;
  if (Crlf >= Lf) and (Crlf >= Cr) and (Crlf > 0) then
    AEol := #13#10
  else if (Lf >= Cr) and (Lf > 0) then
    AEol := #10
  else if Cr > 0 then
    AEol := #13
  else
    AEol := #13#10;
  AFinalEol := (N > 0) and ((AText[N] = #10) or (AText[N] = #13));
  SetLength(Result, 0);
  Count := 0;
  Start := 1;
  I := 1;
  while I <= N do
  begin
    if (AText[I] = #13) or (AText[I] = #10) then
    begin
      SetLength(Result, Count + 1);
      Result[Count] := Copy(AText, Start, I - Start);
      Inc(Count);
      if (AText[I] = #13) and (I < N) and (AText[I + 1] = #10) then
        Inc(I);
      Start := I + 1;
    end;
    Inc(I);
  end;
  if Start <= N then
  begin
    SetLength(Result, Count + 1);
    Result[Count] := Copy(AText, Start, N - Start + 1);
  end;
end;

function JoinTextLines(const ALines: TArray<string>; const AEol: string;
  AFinalEol: Boolean): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ALines) do
  begin
    if I > 0 then
      Result := Result + AEol;
    Result := Result + ALines[I];
  end;
  if AFinalEol and (Length(ALines) > 0) then
    Result := Result + AEol;
end;

function DiffRowMarker(AKind: TDiffRowKind): string;
begin
  case AKind of
    drChanged: Result := ' ~ ';
    drLeftOnly: Result := ' < ';
    drRightOnly: Result := ' > ';
  else
    Result := ' | ';
  end;
end;

procedure DiffInnerSpan(const ALeft, ARight: string; out AStart, ALeftLen,
  ARightLen: Integer);
var
  Common, Tail, MinLen: Integer;
begin
  MinLen := Min(Length(ALeft), Length(ARight));
  Common := 0;
  while (Common < MinLen) and (ALeft[Common + 1] = ARight[Common + 1]) do
    Inc(Common);
  Tail := 0;
  while (Tail < MinLen - Common) and
        (ALeft[Length(ALeft) - Tail] = ARight[Length(ARight) - Tail]) do
    Inc(Tail);
  AStart := Common;
  ALeftLen := Length(ALeft) - Common - Tail;
  ARightLen := Length(ARight) - Common - Tail;
end;

end.
