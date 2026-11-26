unit uEditorSearch;

{ Editor Search Engine: Isolates string searching and substring replacement logic
  from uEditorWindow.pas. A match never spans a line break. The pattern is a
  plain string, or a regular expression (System.RegularExpressions, PCRE) when
  UseRegex is set; WholeWord requires non-word characters (letters, digits and
  the underscore are word characters) on both sides of the match. }

interface

uses
  System.SysUtils, System.Math, System.Classes, System.RegularExpressions;

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

  /// <summary>A search that looks at one line per Step, so a long one can be
  /// done in portions. Without AWrap it ends at the end (or the beginning) of
  /// the text; with it, it goes on from the other end up to where it began.
  /// Backwards AStartCol is where a match has to end by.</summary>
  TSearchWalk = record
  private
    FQuery: string;
    FOptions: TSearchOptions;
    FStartLine, FStartCol, FLine, FScanned: Integer;
    FForward, FWrap, FWrapped, FStarted: Boolean;
    function InRange(ALineCount: Integer): Boolean;
  public
    /// <summary>The match, once Step has returned True.</summary>
    Hit: TSearchResult;
    class function Create(const AQuery: string; const AOptions: TSearchOptions;
      AStartLine, AStartCol: Integer; AForward, AWrap: Boolean): TSearchWalk; static;
    /// <summary>Looks at the next line; True when the search is over.</summary>
    function Step(ALineCount: Integer; const AGetLine: TFunc<Integer, string>): Boolean;
    /// <summary>Share of the lines to look at that are done, 0..100.</summary>
    function Percent(ALineCount: Integer): Integer;
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

var
  // The last expression compiled: a search runs it on every line of a text.
  // Searches of the editor run on the main thread only.
  GRegexKey: string;
  GRegex: TRegEx;

function MakeRegex(const AQuery: string; const AOptions: TSearchOptions): TRegEx;
var
  Pattern: string;
  RxOpts: TRegExOptions;
  Key: string;
begin
  Pattern := AQuery;
  if AOptions.WholeWord then
    Pattern := '\b(?:' + Pattern + ')\b';
  RxOpts := [];
  if not AOptions.MatchCase then
    Include(RxOpts, roIgnoreCase);
  Key := BoolToStr(AOptions.MatchCase) + '|' + Pattern;
  if Key <> GRegexKey then
  begin
    GRegex := TRegEx.Create(Pattern, RxOpts);
    // A pattern is compiled on first use; a bad one raises here, not cached.
    GRegex.IsMatch('');
    GRegexKey := Key;
  end;
  Result := GRegex;
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
    MakeRegex(AQuery, AOptions);
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
    P := Pos(Needle, Hay, From + 1);
    if P = 0 then
      Exit;
    ACol := P - 1;
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

function RunWalk(AWalk: TSearchWalk; const ALines: TArray<string>): TSearchResult;
var
  Lines: TArray<string>;
begin
  Lines := ALines;
  while not AWalk.Step(Length(Lines),
    function(AIndex: Integer): string
    begin
      Result := Lines[AIndex];
    end) do;
  Result := AWalk.Hit;
end;

class function TEditorSearchEngine.FindNextWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartCol: Integer;
  const AOptions: TSearchOptions; AWrap: Boolean): TSearchResult;
begin
  Result := RunWalk(TSearchWalk.Create(AQuery, AOptions, AStartLine, AStartCol,
    True, AWrap), ALines);
end;

class function TEditorSearchEngine.FindPrevWrapped(const ALines: TArray<string>;
  const AQuery: string; AStartLine, AStartColExclusive: Integer;
  const AOptions: TSearchOptions; AWrap: Boolean): TSearchResult;
begin
  Result := RunWalk(TSearchWalk.Create(AQuery, AOptions, AStartLine,
    AStartColExclusive, False, AWrap), ALines);
end;

class function TSearchWalk.Create(const AQuery: string; const AOptions: TSearchOptions;
  AStartLine, AStartCol: Integer; AForward, AWrap: Boolean): TSearchWalk;
begin
  Result := Default(TSearchWalk);
  Result.FQuery := AQuery;
  Result.FOptions := AOptions;
  Result.FStartLine := AStartLine;
  Result.FStartCol := AStartCol;
  Result.FForward := AForward;
  Result.FWrap := AWrap;
  Result.Hit.LineIndex := -1;
  Result.Hit.ColIndex := -1;
  Result.Hit.Length := Length(AQuery);
end;

// Moves FLine to the other end when the first pass is over; False when there
// is no line left to look at.
function TSearchWalk.InRange(ALineCount: Integer): Boolean;
begin
  if FForward then
  begin
    if FWrapped then
      Exit(FLine <= Min(FStartLine, ALineCount - 1));
    if FLine < ALineCount then
      Exit(True);
    if not FWrap or ((FStartLine <= 0) and (FStartCol <= 0)) then
      Exit(False);
    FLine := 0;
  end
  else
  begin
    if FWrapped then
      Exit(FLine >= Max(Min(FStartLine, ALineCount - 1), 0));
    if FLine >= 0 then
      Exit(True);
    if not FWrap then
      Exit(False);
    FLine := ALineCount - 1;
  end;
  FWrapped := True;
  Result := True;
end;

function TSearchWalk.Step(ALineCount: Integer;
  const AGetLine: TFunc<Integer, string>): Boolean;
var
  Line: string;
  C, L, Limit: Integer;
  Found: Boolean;
begin
  if (ALineCount <= 0) or (FQuery = '') then
    Exit(True);
  if not FStarted then
  begin
    FStarted := True;
    if FForward then
      FLine := Max(FStartLine, 0)
    else
      FLine := Min(FStartLine, ALineCount - 1);
  end;
  if not InRange(ALineCount) then
    Exit(True);
  Line := AGetLine(FLine);
  if FForward then
  begin
    Limit := 0;
    if not FWrapped and (FLine = FStartLine) then
      Limit := FStartCol;
    Found := TEditorSearchEngine.FindInLine(Line, FQuery, Limit, FOptions, C, L);
    // Past the start the wrapped pass meets what the first one looked at.
    if Found and FWrapped and (FLine = FStartLine) and (C >= FStartCol) then
      Exit(True);
  end
  else
  begin
    Limit := Length(Line);
    if not FWrapped and (FLine = FStartLine) then
      Limit := FStartCol;
    Found := TEditorSearchEngine.FindLastInLine(Line, FQuery, Limit, FOptions, C, L);
  end;
  if Found then
  begin
    Hit.Found := True;
    Hit.LineIndex := FLine;
    Hit.ColIndex := C;
    Hit.Length := L;
    Exit(True);
  end;
  Inc(FScanned);
  if FForward then
    Inc(FLine)
  else
    Dec(FLine);
  Result := False;
end;

function TSearchWalk.Percent(ALineCount: Integer): Integer;
var
  Total: Integer;
begin
  if FWrap then
    Total := ALineCount
  else if FForward then
    Total := ALineCount - Max(FStartLine, 0)
  else
    Total := Min(FStartLine, ALineCount - 1) + 1;
  Result := Min(Int64(FScanned) * 100 div Max(Total, 1), 100);
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
