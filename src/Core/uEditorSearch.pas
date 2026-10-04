unit uEditorSearch;

{ Editor Search Engine: Isolates string searching and substring replacement logic
  from uEditorWindow.pas. A match never spans a line break. The pattern is a
  plain string, or a regular expression (System.RegularExpressions, PCRE) when
  UseRegex is set; WholeWord requires non-word characters (letters, digits and
  the underscore are word characters) on both sides of the match. }

interface

uses
  System.SysUtils, System.Classes, System.RegularExpressions;

type
  TSearchOptions = record
    MatchCase: Boolean;
    WholeWord: Boolean;
    SearchBackwards: Boolean;
    UseRegex: Boolean;
  end;

  TSearchResult = record
    Found: Boolean;
    LineIndex: Integer;
    ColIndex: Integer;
    /// <summary>Length of the match (differs from the pattern length for a
    /// regular expression and for a case-insensitive plain match).</summary>
    Length: Integer;
  end;

var
  /// <summary>The options the Find and Replace dialogs edit and the editor
  /// uses for F3 / Shift+F3. MatchCase, WholeWord and UseRegex are kept in
  /// session.json; SearchBackwards lasts until the program ends.</summary>
  GEditorSearchOptions: TSearchOptions;

function DefaultSearchOptions: TSearchOptions;

type
  /// <summary>Text search and replace engine for TEditorWindow.</summary>
  TEditorSearchEngine = class
  public
    /// <summary>'' when AQuery can be searched with AOptions; otherwise why
    /// not (the syntax error of a regular expression).</summary>
    class function QueryError(const AQuery: string;
      const AOptions: TSearchOptions): string;
    class function FindInText(const ALines: TArray<string>; const AQuery: string;
      AStartLine, AStartCol: Integer; const AOptions: TSearchOptions): TSearchResult;
    /// <summary>Forward from (AStartLine, AStartCol), then (with AWrap) wrap to
    /// the start of the buffer. Same match rules as FindInText.</summary>
    class function FindNextWrapped(const ALines: TArray<string>;
      const AQuery: string; AStartLine, AStartCol: Integer;
      const AOptions: TSearchOptions; AWrap: Boolean = True): TSearchResult;
    /// <summary>Backward before (AStartLine, AStartColExclusive), then (with AWrap)
    /// wrap to the last match in the buffer. A match found lies entirely
    /// before AStartColExclusive on the start line.</summary>
    class function FindPrevWrapped(const ALines: TArray<string>;
      const AQuery: string; AStartLine, AStartColExclusive: Integer;
      const AOptions: TSearchOptions; AWrap: Boolean = True): TSearchResult;
    /// <summary>First match in ALine that starts at or after AStartCol.</summary>
    class function FindInLine(const ALine, AQuery: string; AStartCol: Integer;
      const AOptions: TSearchOptions; out ACol, ALen: Integer): Boolean;
    /// <summary>Last match in ALine that ends at or before AEndExclusive.</summary>
    class function FindLastInLine(const ALine, AQuery: string;
      AEndExclusive: Integer; const AOptions: TSearchOptions;
      out ACol, ALen: Integer): Boolean;
    /// <summary>Plain replacement of the AQuery-long piece at AColIndex.</summary>
    class function ReplaceInLine(const ALine, AQuery, AReplacement: string;
      AColIndex: Integer; AMatchCase: Boolean): string;
    /// <summary>Replaces the match of ALen characters at ACol. For a regular
    /// expression AReplacement may use $0 (whole match), $1 .. $9 (groups) and
    /// $$ (a dollar sign); the match is made again at ACol so the groups are
    /// known. ANewLen is the length of what was put in.</summary>
    class function ReplaceMatch(const ALine, AQuery, AReplacement: string;
      ACol, ALen: Integer; const AOptions: TSearchOptions;
      out ANewLen: Integer): string;
    /// <summary>Replaces every match in ALine; ACount is how many there were.</summary>
    class function ReplaceAllInLine(const ALine, AQuery, AReplacement: string;
      const AOptions: TSearchOptions; out ACount: Integer): string;
  end;

implementation

uses
  System.Character;

function DefaultSearchOptions: TSearchOptions;
begin
  Result.MatchCase := False;
  Result.WholeWord := False;
  Result.SearchBackwards := False;
  Result.UseRegex := False;
end;

function IsWordCh(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_');
end;

function WordBounded(const ALine: string; ACol, ALen: Integer): Boolean;
begin
  Result := ((ACol = 0) or not IsWordCh(ALine[ACol])) and
    ((ACol + ALen >= Length(ALine)) or not IsWordCh(ALine[ACol + ALen + 1]));
end;

function MakeRegex(const AQuery: string; const AOptions: TSearchOptions): TRegEx;
var
  Pattern: string;
  RxOpts: TRegExOptions;
begin
  Pattern := AQuery;
  if AOptions.WholeWord then
    Pattern := '\b(?:' + Pattern + ')\b';
  RxOpts := [];
  if not AOptions.MatchCase then
    Include(RxOpts, roIgnoreCase);
  Result := TRegEx.Create(Pattern, RxOpts);
end;

// First regular-expression match that starts at or after ACol (0-based) and
// is not empty (an empty match would never advance).
function RegexFirst(const ARx: TRegEx; const ALine: string; ACol: Integer;
  out AMatch: TMatch): Boolean;
var
  Pos: Integer;
begin
  Pos := ACol;
  while Pos <= Length(ALine) do
  begin
    AMatch := ARx.Match(ALine, Pos + 1);
    if not AMatch.Success then
      Exit(False);
    if AMatch.Length > 0 then
      Exit(True);
    Pos := AMatch.Index; // 1-based index of the empty match = 0-based next start
  end;
  Result := False;
end;

class function TEditorSearchEngine.QueryError(const AQuery: string;
  const AOptions: TSearchOptions): string;
begin
  Result := '';
  if not AOptions.UseRegex or (AQuery = '') then
    Exit;
  try
    // A pattern is compiled on first use, so use it once to learn its error.
    MakeRegex(AQuery, AOptions).IsMatch('');
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

class function TEditorSearchEngine.FindInLine(const ALine, AQuery: string;
  AStartCol: Integer; const AOptions: TSearchOptions;
  out ACol, ALen: Integer): Boolean;
var
  Hay, Needle: string;
  P, From: Integer;
  M: TMatch;
begin
  Result := False;
  ACol := -1;
  ALen := 0;
  if (AQuery = '') or (AStartCol > Length(ALine)) then
    Exit;
  if AStartCol < 0 then
    AStartCol := 0;
  if AOptions.UseRegex then
  begin
    try
      if RegexFirst(MakeRegex(AQuery, AOptions), ALine, AStartCol, M) then
      begin
        ACol := M.Index - 1;
        ALen := M.Length;
        Result := True;
      end;
    except
      Result := False;
    end;
    Exit;
  end;
  if AOptions.MatchCase then
  begin
    Hay := ALine;
    Needle := AQuery;
  end
  else
  begin
    Hay := ALine.ToLower;
    Needle := AQuery.ToLower;
  end;
  From := AStartCol;
  while True do
  begin
    P := Pos(Needle, Copy(Hay, From + 1, MaxInt));
    if P = 0 then
      Exit;
    ACol := From + P - 1;
    ALen := Length(AQuery);
    if not AOptions.WholeWord or WordBounded(ALine, ACol, ALen) then
      Exit(True);
    From := ACol + 1;
  end;
end;

class function TEditorSearchEngine.FindLastInLine(const ALine, AQuery: string;
  AEndExclusive: Integer; const AOptions: TSearchOptions;
  out ACol, ALen: Integer): Boolean;
var
  Slice: string;
  C, L, From: Integer;
begin
  Result := False;
  ACol := -1;
  ALen := 0;
  if (AQuery = '') or (AEndExclusive <= 0) then
    Exit;
  Slice := Copy(ALine, 1, AEndExclusive);
  From := 0;
  // Matches of the slice are taken from the left; the last one is the answer.
  // The slice ends where the search began, so a match cannot run past it
  // (a regular expression cannot see text beyond the slice, as intended).
  while FindInLine(Slice, AQuery, From, AOptions, C, L) do
  begin
    Result := True;
    ACol := C;
    ALen := L;
    // Plain matches may overlap ("aa" in "aaa" ends at the last a); regular
    // expression matches follow one another.
    if AOptions.UseRegex then
      From := C + L
    else
      From := C + 1;
  end;
end;

class function TEditorSearchEngine.FindInText(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartCol: Integer;
  const AOptions: TSearchOptions): TSearchResult;
var
  I, C, L, Start: Integer;
begin
  Result.Found := False;
  Result.LineIndex := -1;
  Result.ColIndex := -1;
  Result.Length := Length(AQuery);

  if (Length(ALines) = 0) or (AQuery = '') then
    Exit;

  for I := AStartLine to High(ALines) do
  begin
    if I = AStartLine then
      Start := AStartCol
    else
      Start := 0;
    if FindInLine(ALines[I], AQuery, Start, AOptions, C, L) then
    begin
      Result.Found := True;
      Result.LineIndex := I;
      Result.ColIndex := C;
      Result.Length := L;
      Exit;
    end;
  end;
end;

class function TEditorSearchEngine.FindNextWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartCol: Integer;
  const AOptions: TSearchOptions; AWrap: Boolean): TSearchResult;
begin
  Result := FindInText(ALines, AQuery, AStartLine, AStartCol, AOptions);
  if Result.Found or not AWrap then
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

class function TEditorSearchEngine.FindPrevWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartColExclusive: Integer;
  const AOptions: TSearchOptions; AWrap: Boolean): TSearchResult;
var
  I, Limit, C, L: Integer;
begin
  Result.Found := False;
  Result.LineIndex := -1;
  Result.ColIndex := -1;
  Result.Length := Length(AQuery);
  if (Length(ALines) = 0) or (AQuery = '') then
    Exit;

  I := AStartLine;
  if I > High(ALines) then
    I := High(ALines);
  while I >= 0 do
  begin
    if I = AStartLine then
      Limit := AStartColExclusive
    else
      Limit := Length(ALines[I]);
    if FindLastInLine(ALines[I], AQuery, Limit, AOptions, C, L) then
    begin
      Result.Found := True;
      Result.LineIndex := I;
      Result.ColIndex := C;
      Result.Length := L;
      Exit;
    end;
    Dec(I);
  end;
  if not AWrap then
    Exit;

  for I := High(ALines) downto 0 do
    if FindLastInLine(ALines[I], AQuery, Length(ALines[I]), AOptions, C, L) then
    begin
      Result.Found := True;
      Result.LineIndex := I;
      Result.ColIndex := C;
      Result.Length := L;
      Exit;
    end;
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

// $0 .. $9 and $$ in AReplacement, with the groups of AMatch.
function ExpandReplacement(const AMatch: TMatch; const AReplacement: string): string;
var
  I, N: Integer;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(AReplacement) do
    begin
      if (AReplacement[I] = '$') and (I < Length(AReplacement)) then
      begin
        if AReplacement[I + 1] = '$' then
        begin
          Sb.Append('$');
          Inc(I, 2);
          Continue;
        end;
        if CharInSet(AReplacement[I + 1], ['0'..'9']) then
        begin
          N := Ord(AReplacement[I + 1]) - Ord('0');
          if N < AMatch.Groups.Count then
            Sb.Append(AMatch.Groups[N].Value);
          Inc(I, 2);
          Continue;
        end;
      end;
      Sb.Append(AReplacement[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

class function TEditorSearchEngine.ReplaceMatch(const ALine, AQuery,
  AReplacement: string; ACol, ALen: Integer; const AOptions: TSearchOptions;
  out ANewLen: Integer): string;
var
  M: TMatch;
  Text: string;
begin
  Text := AReplacement;
  if AOptions.UseRegex then
    try
      if RegexFirst(MakeRegex(AQuery, AOptions), ALine, ACol, M) and
         (M.Index - 1 = ACol) then
        Text := ExpandReplacement(M, AReplacement);
    except
      Text := AReplacement;
    end;
  ANewLen := Length(Text);
  Result := Copy(ALine, 1, ACol) + Text + Copy(ALine, ACol + ALen + 1, MaxInt);
end;

class function TEditorSearchEngine.ReplaceAllInLine(const ALine, AQuery,
  AReplacement: string; const AOptions: TSearchOptions;
  out ACount: Integer): string;
var
  C, L, From, NewLen: Integer;
  Line: string;
begin
  ACount := 0;
  Line := ALine;
  From := 0;
  while FindInLine(Line, AQuery, From, AOptions, C, L) do
  begin
    Line := ReplaceMatch(Line, AQuery, AReplacement, C, L, AOptions, NewLen);
    Inc(ACount);
    // Continue after what was put in, so a replacement is never searched again.
    From := C + NewLen;
    if NewLen = 0 then
      Inc(From);
  end;
  Result := Line;
end;

initialization
  GEditorSearchOptions := DefaultSearchOptions;

end.
