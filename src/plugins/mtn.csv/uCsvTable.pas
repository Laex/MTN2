unit uCsvTable;

{ Pure helpers of the CSV / TSV table plugin: byte decoding, delimiter
  detection, record parsing (quoted cells, doubled quotes, line breaks inside
  quotes) and the aligned text table. No host calls, so it is covered by
  tests. }

interface

uses
  System.SysUtils;

type
  TCsvRow = TArray<string>;
  TCsvRows = TArray<TCsvRow>;

  TCsvTableInfo = record
    Delimiter: Char;
    Rows: Integer;
    Columns: Integer;
    /// <summary>The text had more records than AMaxRows; the rest is not shown.</summary>
    RowsCut: Boolean;
  end;

/// <summary>The text of a file's bytes: UTF-8 (with or without a BOM) or UTF-16
/// with a BOM; bytes that are not valid UTF-8 are read in the system code
/// page.</summary>
function DecodeCsvBytes(const ABytes: TBytes): string;

/// <summary>The most likely delimiter of the first records of AText: one of
/// comma, semicolon, tab and bar. The one that splits most records into the
/// same number of cells wins; comma when none splits anything.</summary>
function DetectCsvDelimiter(const AText: string): Char;

/// <summary>The records of AText; empty lines are skipped. AMaxRows <= 0 = no
/// limit; ACut tells that the limit stopped the parse.</summary>
function ParseCsv(const AText: string; ADelimiter: Char; AMaxRows: Integer;
  out ACut: Boolean): TCsvRows;

/// <summary>AText as an aligned table: cells separated by " | ", a rule under
/// the first record (the header). Cells longer than AMaxCellWidth are cut with
/// "..."; line breaks and tabs inside a cell become spaces. ADelimiter = #0
/// detects it.</summary>
function RenderCsvTable(const AText: string; ADelimiter: Char; AMaxCellWidth,
  AMaxRows: Integer; out AInfo: TCsvTableInfo): string;

implementation

uses
  System.Classes, System.Math;

const
  cCandidates: array[0..3] of Char = (',', ';', #9, '|');
  cSampleRows = 30;

function DecodeCsvBytes(const ABytes: TBytes): string;
var
  Skip: Integer;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;
  if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Exit(TEncoding.Unicode.GetString(ABytes, 2, Length(ABytes) - 2));
  if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(ABytes, 2, Length(ABytes) - 2));
  Skip := 0;
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Skip := 3;
  try
    Result := TEncoding.UTF8.GetString(ABytes, Skip, Length(ABytes) - Skip);
  except
    // Not valid UTF-8: the file is in the system code page.
    on EEncodingError do
      Result := TEncoding.ANSI.GetString(ABytes, Skip, Length(ABytes) - Skip);
  end;
  // Some builds replace the bad bytes instead of raising.
  if Pos(#$FFFD, Result) > 0 then
    Result := TEncoding.ANSI.GetString(ABytes, Skip, Length(ABytes) - Skip);
end;

function ParseCsv(const AText: string; ADelimiter: Char; AMaxRows: Integer;
  out ACut: Boolean): TCsvRows;
var
  Rows: TCsvRows;
  RowCount: Integer;
  Cells: TCsvRow;
  CellCount: Integer;
  Cell: TStringBuilder;
  I, N: Integer;
  C: Char;
  Quoted, CellHadQuote, Stop: Boolean;

  procedure EndCell;
  begin
    if CellCount = Length(Cells) then
      SetLength(Cells, Max(8, CellCount * 2));
    Cells[CellCount] := Cell.ToString;
    Inc(CellCount);
    Cell.Clear;
    CellHadQuote := False;
  end;

  procedure EndRecord;
  begin
    // A line with nothing on it is not a record.
    if (CellCount = 0) and (Cell.Length = 0) and not CellHadQuote then
      Exit;
    EndCell;
    SetLength(Cells, CellCount);
    if RowCount = Length(Rows) then
      SetLength(Rows, Max(64, RowCount * 2));
    Rows[RowCount] := Cells;
    Inc(RowCount);
    Cells := nil;
    CellCount := 0;
    if (AMaxRows > 0) and (RowCount >= AMaxRows) then
      Stop := True;
  end;

begin
  Rows := nil;
  RowCount := 0;
  Cells := nil;
  CellCount := 0;
  Quoted := False;
  CellHadQuote := False;
  Stop := False;
  ACut := False;
  Cell := TStringBuilder.Create;
  try
    N := Length(AText);
    I := 1;
    while (I <= N) and not Stop do
    begin
      C := AText[I];
      if Quoted then
      begin
        if C = '"' then
        begin
          if (I < N) and (AText[I + 1] = '"') then
          begin
            Cell.Append('"');
            Inc(I);
          end
          else
            Quoted := False;
        end
        else
          Cell.Append(C);
      end
      else if C = '"' then
      begin
        Quoted := True;
        CellHadQuote := True;
      end
      else if C = ADelimiter then
        EndCell
      else if C = #13 then
      begin
        if (I < N) and (AText[I + 1] = #10) then
          Inc(I);
        EndRecord;
      end
      else if C = #10 then
        EndRecord
      else
        Cell.Append(C);
      Inc(I);
    end;
    if not Stop then
      EndRecord
    else
      ACut := I <= N;
  finally
    Cell.Free;
  end;
  SetLength(Rows, RowCount);
  Result := Rows;
end;

function DetectCsvDelimiter(const AText: string): Char;
var
  Cand: Char;
  Sample: TCsvRows;
  Cut: Boolean;
  Counts: array of Integer;
  I, J, Mode, ModeHits, Hits: Integer;
  Score, BestScore: Int64;
begin
  Result := ',';
  BestScore := 0;
  for Cand in cCandidates do
  begin
    Sample := ParseCsv(AText, Cand, cSampleRows, Cut);
    if Length(Sample) = 0 then
      Continue;
    SetLength(Counts, Length(Sample));
    for I := 0 to High(Sample) do
      Counts[I] := Length(Sample[I]);
    // The commonest cell count among the records, and how many have it.
    Mode := 0;
    ModeHits := 0;
    for I := 0 to High(Counts) do
    begin
      Hits := 0;
      for J := 0 to High(Counts) do
        if Counts[J] = Counts[I] then
          Inc(Hits);
      if (Hits > ModeHits) or ((Hits = ModeHits) and (Counts[I] > Mode)) then
      begin
        Mode := Counts[I];
        ModeHits := Hits;
      end;
    end;
    if Mode < 2 then
      Continue;
    Score := Int64(ModeHits) * 1000 + Mode;
    if Score > BestScore then
    begin
      BestScore := Score;
      Result := Cand;
    end;
  end;
end;

function FlatCell(const AValue: string; AMaxWidth: Integer): string;
var
  I: Integer;
begin
  Result := AValue;
  for I := 1 to Length(Result) do
    if CharInSet(Result[I], [#9, #10, #13]) then
      Result[I] := ' ';
  if (AMaxWidth > 3) and (Length(Result) > AMaxWidth) then
    Result := Copy(Result, 1, AMaxWidth - 3) + '...';
end;

function RenderCsvTable(const AText: string; ADelimiter: Char; AMaxCellWidth,
  AMaxRows: Integer; out AInfo: TCsvTableInfo): string;
var
  Rows: TCsvRows;
  Widths: TArray<Integer>;
  Cut: Boolean;
  Out_: TStringBuilder;
  Line: TStringBuilder;
  R, C, Cols: Integer;
  Cell: string;
begin
  AInfo := Default(TCsvTableInfo);
  if ADelimiter = #0 then
    ADelimiter := DetectCsvDelimiter(AText);
  AInfo.Delimiter := ADelimiter;
  Rows := ParseCsv(AText, ADelimiter, AMaxRows, Cut);
  AInfo.Rows := Length(Rows);
  AInfo.RowsCut := Cut;
  Cols := 0;
  for R := 0 to High(Rows) do
    Cols := Max(Cols, Length(Rows[R]));
  AInfo.Columns := Cols;
  SetLength(Widths, Cols);
  for R := 0 to High(Rows) do
    for C := 0 to High(Rows[R]) do
    begin
      Rows[R][C] := FlatCell(Rows[R][C], AMaxCellWidth);
      Widths[C] := Max(Widths[C], Length(Rows[R][C]));
    end;
  Out_ := TStringBuilder.Create;
  Line := TStringBuilder.Create;
  try
    for R := 0 to High(Rows) do
    begin
      Line.Clear;
      // A short record ends at its last cell: no empty columns after it.
      for C := 0 to High(Rows[R]) do
      begin
        Cell := Rows[R][C];
        Line.Append(Cell);
        if C < High(Rows[R]) then
        begin
          Line.Append(StringOfChar(' ', Widths[C] - Length(Cell)));
          Line.Append(' | ');
        end;
      end;
      Out_.Append(Line.ToString.TrimRight).Append(#13#10);
      if R = 0 then
      begin
        Line.Clear;
        for C := 0 to Cols - 1 do
        begin
          Line.Append(StringOfChar('-', Widths[C]));
          if C < Cols - 1 then
            Line.Append('-+-');
        end;
        Out_.Append(Line.ToString).Append(#13#10);
      end;
    end;
    Result := Out_.ToString;
  finally
    Line.Free;
    Out_.Free;
  end;
end;

end.
