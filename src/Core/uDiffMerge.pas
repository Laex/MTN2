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

type
  /// <summary>Column layout of a side-by-side row.</summary>
  TDiffRowLayout = record
    NumCols: Integer;   // width of a line number
    CellCols: Integer;  // width of one text cell
  end;

/// <summary>Cells that fit a text cell when the list is AListCols wide.</summary>
function DiffRowLayout(AListCols: Integer): TDiffRowLayout;
/// <summary>"  12 left text  | marker |  12 right text ", exactly the layout's width.</summary>
function FormatDiffRow(const ARow: TDiffRow; const ALayout: TDiffRowLayout): string;
/// <summary>The three cells between the two texts: "|", "~", "<" or ">".</summary>
function DiffRowMarker(AKind: TDiffRowKind): string;
/// <summary>Column in a formatted row where the marker starts.</summary>
function DiffMarkerCol(const ALayout: TDiffRowLayout): Integer;

implementation

uses
  System.Math;

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
  I, J, K, LeftPos, RightPos, Paired, RowCount, Hunk: Integer;

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
    Paired := Min(Length(Dels), Length(Ins));
    for K := 0 to Paired - 1 do
      AddRow(drChanged, Dels[K], Ins[K], LeftPos + K + 1, RightPos + K + 1, Hunk);
    for K := Paired to High(Dels) do
      AddRow(drLeftOnly, Dels[K], '', LeftPos + K + 1, 0, Hunk);
    for K := Paired to High(Ins) do
      AddRow(drRightOnly, '', Ins[K], 0, RightPos + K + 1, Hunk);
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

const
  cNumCols = 5;
  cMarkerCols = 3;

function DiffRowLayout(AListCols: Integer): TDiffRowLayout;
begin
  Result.NumCols := cNumCols;
  // number + space, text cell, marker, number + space, text cell
  Result.CellCols := Max((AListCols - 2 * (cNumCols + 1) - cMarkerCols) div 2, 4);
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

function DiffMarkerCol(const ALayout: TDiffRowLayout): Integer;
begin
  Result := ALayout.NumCols + 1 + ALayout.CellCols;
end;

// Control characters would break the grid; a tab takes one cell like any other.
function FitCell(const AText: string; AWidth: Integer): string;
var
  I: Integer;
begin
  Result := Copy(AText, 1, AWidth);
  for I := 1 to Length(Result) do
    if Result[I] < ' ' then
      Result[I] := ' ';
  if Length(Result) < AWidth then
    Result := Result + StringOfChar(' ', AWidth - Length(Result));
end;

function NumCell(ANo, AWidth: Integer): string;
begin
  if ANo <= 0 then
    Result := StringOfChar(' ', AWidth)
  else
  begin
    Result := IntToStr(ANo);
    if Length(Result) > AWidth then
      Result := Copy(Result, Length(Result) - AWidth + 1, AWidth)
    else
      Result := StringOfChar(' ', AWidth - Length(Result)) + Result;
  end;
end;

function FormatDiffRow(const ARow: TDiffRow; const ALayout: TDiffRowLayout): string;
begin
  Result := NumCell(ARow.LeftNo, ALayout.NumCols) + ' ' +
    FitCell(ARow.Left, ALayout.CellCols) + DiffRowMarker(ARow.Kind) +
    NumCell(ARow.RightNo, ALayout.NumCols) + ' ' +
    FitCell(ARow.Right, ALayout.CellCols);
end;

end.
