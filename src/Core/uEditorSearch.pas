unit uEditorSearch;

{ Editor Search Engine: Isolates string searching and substring replacement logic
  from uEditorWindow.pas. }

interface

uses
  System.SysUtils, System.Classes;

type
  TSearchOptions = record
    MatchCase: Boolean;
    WholeWord: Boolean;
    SearchBackwards: Boolean;
  end;

  TSearchResult = record
    Found: Boolean;
    LineIndex: Integer;
    ColIndex: Integer;
    Length: Integer;
  end;

  /// <summary>Text search and replace engine for TEditorWindow.</summary>
  TEditorSearchEngine = class
  public
    class function FindInText(const ALines: TArray<string>; const AQuery: string;
      AStartLine, AStartCol: Integer; const AOptions: TSearchOptions): TSearchResult;
    /// <summary>Forward from (AStartLine, AStartCol), then wrap to the start
    /// of the buffer. Same match rules as FindInText.</summary>
    class function FindNextWrapped(const ALines: TArray<string>;
      const AQuery: string; AStartLine, AStartCol: Integer;
      const AOptions: TSearchOptions): TSearchResult;
    /// <summary>Backward before (AStartLine, AStartColExclusive), then wrap
    /// to the last match in the buffer.</summary>
    class function FindPrevWrapped(const ALines: TArray<string>;
      const AQuery: string; AStartLine, AStartColExclusive: Integer;
      const AOptions: TSearchOptions): TSearchResult;
    class function ReplaceInLine(const ALine, AQuery, AReplacement: string;
      AColIndex: Integer; AMatchCase: Boolean): string;
  end;

implementation

class function TEditorSearchEngine.FindInText(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartCol: Integer;
  const AOptions: TSearchOptions): TSearchResult;
var
  LFoundPos: Integer;
  LLineText: string;
  LTargetQuery: string;
  I: Integer;
begin
  Result.Found := False;
  Result.LineIndex := -1;
  Result.ColIndex := -1;
  Result.Length := Length(AQuery);

  if (Length(ALines) = 0) or (AQuery = '') then
    Exit;

  if AOptions.MatchCase then
    LTargetQuery := AQuery
  else
    LTargetQuery := AQuery.ToLower;

  for I := AStartLine to High(ALines) do
  begin
    if AOptions.MatchCase then
      LLineText := ALines[I]
    else
      LLineText := ALines[I].ToLower;

    if I = AStartLine then
      LFoundPos := Pos(LTargetQuery, Copy(LLineText, AStartCol + 1, MaxInt))
    else
      LFoundPos := Pos(LTargetQuery, LLineText);

    if LFoundPos > 0 then
    begin
      Result.Found := True;
      Result.LineIndex := I;
      if I = AStartLine then
        Result.ColIndex := AStartCol + LFoundPos - 1
      else
        Result.ColIndex := LFoundPos - 1;
      Exit;
    end;
  end;
end;

class function TEditorSearchEngine.FindNextWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartCol: Integer;
  const AOptions: TSearchOptions): TSearchResult;
begin
  Result := FindInText(ALines, AQuery, AStartLine, AStartCol, AOptions);
  if Result.Found then
    Exit;
  if (AStartLine <= 0) and (AStartCol <= 0) then
    Exit;
  Result := FindInText(ALines, AQuery, 0, 0, AOptions);
  if Result.Found and
     ((Result.LineIndex > AStartLine) or
      ((Result.LineIndex = AStartLine) and (Result.ColIndex >= AStartCol))) then
  begin
    Result.Found := False;
    Result.LineIndex := -1;
    Result.ColIndex := -1;
  end;
end;

function LastIndexBefore(const AHay, ANeedle: string;
  AEndExclusive: Integer): Integer;
var
  Slice: string;
  P, Base: Integer;
begin
  Result := -1;
  if (ANeedle = '') or (AEndExclusive <= 0) then
    Exit;
  Slice := Copy(AHay, 1, AEndExclusive);
  Base := 0;
  repeat
    P := Pos(ANeedle, Copy(Slice, Base + 1, MaxInt));
    if P = 0 then
      Break;
    Result := Base + P - 1;
    Base := Result + 1;
  until Base >= Length(Slice);
end;

class function TEditorSearchEngine.FindPrevWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartColExclusive: Integer;
  const AOptions: TSearchOptions): TSearchResult;
var
  Query, Line: string;
  I, Limit, Idx, Last: Integer;
begin
  Result.Found := False;
  Result.LineIndex := -1;
  Result.ColIndex := -1;
  Result.Length := Length(AQuery);
  if (Length(ALines) = 0) or (AQuery = '') then
    Exit;
  if AOptions.MatchCase then
    Query := AQuery
  else
    Query := AQuery.ToLower;

  I := AStartLine;
  if I > High(ALines) then
    I := High(ALines);
  while I >= 0 do
  begin
    if AOptions.MatchCase then
      Line := ALines[I]
    else
      Line := ALines[I].ToLower;
    if I = AStartLine then
      Limit := AStartColExclusive
    else
      Limit := Length(Line);
    Idx := LastIndexBefore(Line, Query, Limit);
    if Idx >= 0 then
    begin
      Result.Found := True;
      Result.LineIndex := I;
      Result.ColIndex := Idx;
      Exit;
    end;
    Dec(I);
  end;

  Last := High(ALines);
  if AOptions.MatchCase then
    Line := ALines[Last]
  else
    Line := ALines[Last].ToLower;
  Idx := LastIndexBefore(Line, Query, Length(Line));
  I := Last;
  while (Idx < 0) and (I > 0) do
  begin
    Dec(I);
    if AOptions.MatchCase then
      Line := ALines[I]
    else
      Line := ALines[I].ToLower;
    Idx := LastIndexBefore(Line, Query, Length(Line));
  end;
  if Idx < 0 then
    Exit;
  Result.Found := True;
  Result.LineIndex := I;
  Result.ColIndex := Idx;
end;

class function TEditorSearchEngine.ReplaceInLine(const ALine, AQuery, AReplacement: string;
  AColIndex: Integer; AMatchCase: Boolean): string;
var
  LPrefix, LSuffix: string;
begin
  LPrefix := Copy(ALine, 1, AColIndex);
  LSuffix := Copy(ALine, AColIndex + Length(AQuery) + 1, MaxInt);
  Result := LPrefix + AReplacement + LSuffix;
end;

end.
