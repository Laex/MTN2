unit uMarkdownParser;

{ Stage 25: Markdown Viewer parser. Pure, no I/O — turns one raw source line
  plus carried fence state into a TMdLine (display text + non-overlapping
  style spans). Deliberately line-oriented: one source line always maps to
  one screen line of markdown content (no paragraph reflow/joining) — the
  Viewer wraps a too-long DisplayText across several screen rows itself
  (uEditorWindow.DrawMarkdownContent), it never merges two source lines into
  one.

  DisplayText is not always the raw source line any more: **bold**/__bold__,
  *italic*/_italic_, and ***bold+italic*** have their delimiters stripped
  (just the inner text is kept, styled), since showing literal markers
  around already-colored emphasis reads as noise. [text](url) shows just
  "text" as one mskLink span; the url travels in TMdSpan.Target (the Help
  viewer follows it). `code` and ~~strike~~ keep their delimiters — colored
  as one span covering the whole token — and ATX headings still get their leading #'s + following space
  stripped (a heading is always a single-style whole line, so there's no
  delimiter/content split to preserve). Standalone image lines become a
  "[image: alt]" placeholder,
  also used as the Overlay-failure fallback label by the caller.
  CommonMark `![alt](path)` and Obsidian `![[file.png]]` /
  `![[file.png|size]]` (whole line) both count; wiki embeds of notes
  without an image extension are left as plain text. MarkdownResolveImageFile
  is the only I/O helper here — ParseLine itself stays pure.

  GFM pipe tables (`| a | b |` + `| --- | --- |` + body) are a block
  construct: ParseLine leaves them as ordinary lines so a fenced code block
  can still contain literal pipes. The Viewer collects a contiguous pipe
  block and calls FormatPipeTableLine, which formats one source line
  (header/body with `│` cell rules, the separator as `├─┼─┤`) and aligns
  columns from the whole block. Escaped `\|` is a literal pipe.

  When given a target width that the table's natural (unwrapped) column
  widths don't fit, FormatPipeTableLine shrinks columns to fit it and word-
  wraps each cell's text within its column — so one source line can now
  expand into several physical screen rows. Those rows are still returned
  as a single TMdLine: DisplayText is every physical row concatenated back
  to back, each padded to exactly the target width, with span offsets
  translated into that concatenated string. This keeps the existing
  contract that ComputeHardWrapStarts slices DisplayText into fixed-width
  chunks for the Viewer to draw one at a time (uEditorWindow.
  DrawMarkdownContent) — because every physical row is exactly the target
  width long, that fixed-width slicing always lands exactly on a row
  boundary, never mid-cell.

  A cell may also force its own line breaks with `<br>` (GFM's standard
  workaround since a pipe row can't contain a literal newline) — see
  BuildCellRows: every '<br>'-separated segment gets its own row regardless
  of available width, and is then word-wrapped independently like any other
  cell text. A column's "natural" width is the widest SEGMENT, not the
  whole cell's text run together, since a `<br>`-bearing cell is always
  multi-line by the author's own choice.

  The only state carried across ParseLine calls for one document is whether
  a fenced code block is open — every other construct (heading, quote,
  list, hr, inline emphasis) is fully determined by its own source line, so
  a caller only needs to remember TMdFenceState between successive lines
  (see uMarkdownIndex.TMarkdownFenceIndex for how a Viewer recovers that
  state cheaply when jumping into the middle of a large file). }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uThemeTypes;

type
  TMdSpan = record
    StartCol, Len: Integer; // 1-based, into TMdLine.DisplayText
    Kind: TMdSpanKind;
    Target: string; // mskLink only: the "(url)" part, not shown
  end;

  TMdFenceState = record
    InFence: Boolean;
  end;

  TMdLine = record
    DisplayText: string;
    Spans: TArray<TMdSpan>;
    IsImage: Boolean;
    ImageAlt: string;
    ImagePath: string;
    IsTable: Boolean;
  end;

  TMdTableAlign = (mtaLeft, mtaCenter, mtaRight);

  /// <summary>The part of a pipe-table row's formatting that depends on the
  /// whole block, not the row: column count, alignment and fitted widths.
  /// Measuring every cell of the block is the expensive part, so a caller
  /// that formats many rows of one block (the Viewer, row by row) computes
  /// this once with ComputeTableLayout and passes it to FormatPipeTableRow.
  /// ColCount = 0: not a usable table.</summary>
  TMdTableLayout = record
    ColCount: Integer;
    Aligns: TArray<TMdTableAlign>;
    Widths: TArray<Integer>;
  end;

  TMarkdownParser = class
  public
    class function ParseLine(const ARaw: string; var AState: TMdFenceState): TMdLine; static;
    /// <summary>Word-boundary line-wrap: splits AText into chunks that each
    /// fit within AWidth columns, returning the 1-based start index of every
    /// chunk (chunk N's end is chunk N+1's start minus one, or Length(AText)
    /// for the last chunk). Breaks after the rightmost separator (space,
    /// tab, or common punctuation — see IsWrapBreakChar) at or before the
    /// AWidth boundary, so the separator stays attached to the line it
    /// closes rather than starting the next one; a run with no separator
    /// anywhere in range (e.g. a long URL) falls back to a hard cut at
    /// exactly AWidth. Always returns at least one element (a single [1]
    /// for '' or AWidth &lt;= 0).</summary>
    class function ComputeWrapStarts(const AText: string; AWidth: Integer): TArray<Integer>; static;
    /// <summary>Hard wrap at exactly AWidth (no space/punctuation search).
    /// Table rows pad cells with spaces, so ComputeWrapStarts would split
    /// inside the grid; the Viewer uses this instead.</summary>
    class function ComputeHardWrapStarts(const AText: string; AWidth: Integer): TArray<Integer>; static;
    class function LooksLikePipeTableRow(const ARaw: string): Boolean; static;
    class function IsPipeTableSeparator(const ARaw: string): Boolean; static;
    /// <summary>Format one line of a GFM pipe-table block (header at 0,
    /// separator at 1, body after). ABlock must already be a valid table
    /// (separator on line 1). Column widths come from the whole block.
    /// AAvailWidth &lt;= 0 (the default) means unbounded: columns use their
    /// natural (widest-cell) width, exactly as before. A positive
    /// AAvailWidth that the natural widths don't fit shrinks columns to fit
    /// it and word-wraps cell text within the shrunk width, expanding this
    /// one source line into several physical rows — see the file header
    /// comment for how those rows travel back as a single TMdLine.</summary>
    class function FormatPipeTableLine(const ABlock: TArray<string>;
      AIndexInBlock: Integer; AAvailWidth: Integer = 0): TMdLine; static;
    /// <summary>Block-wide layout for FormatPipeTableRow; same AAvailWidth
    /// meaning as FormatPipeTableLine.</summary>
    class function ComputeTableLayout(const ABlock: TArray<string>;
      AAvailWidth: Integer = 0): TMdTableLayout; static;
    /// <summary>FormatPipeTableLine for one row (ARow = ABlock[AIndexInBlock])
    /// with a layout already computed for its block: costs one row, not a
    /// scan of the whole block.</summary>
    class function FormatPipeTableRow(const ARow: string; AIndexInBlock: Integer;
      const ALayout: TMdTableLayout): TMdLine; static;
  end;

/// <summary>Local file for a Markdown/Obsidian image ref next to ADocPath:
/// the path as written, then `&lt;doc dir&gt;\attachments\&lt;filename&gt;`.
/// Empty if neither exists. HTTP(S) refs are not resolved (no HTTP VFS).</summary>
function MarkdownResolveImageFile(const ADocPath, AImageRef: string): string;

implementation

uses
  System.StrUtils, System.IOUtils, System.Math, uTerminalTypes;

function MakeSpan(AStart, ALen: Integer; AKind: TMdSpanKind): TMdSpan;
begin
  Result.StartCol := AStart;
  Result.Len := ALen;
  Result.Kind := AKind;
  Result.Target := '';
end;

function SingleSpan(AStart, ALen: Integer; AKind: TMdSpanKind): TArray<TMdSpan>;
begin
  SetLength(Result, 1);
  Result[0] := MakeSpan(AStart, ALen, AKind);
end;

function IsFenceMarker(const T: string): Boolean;
begin
  Result := (Length(T) >= 3) and ((Copy(T, 1, 3) = '```') or (Copy(T, 1, 3) = '~~~'));
end;

// Leading '#' count (1..6) followed by a space or end of line; 0 = not a heading.
function AtxHeadingLevel(const T: string): Integer;
var
  N: Integer;
begin
  Result := 0;
  N := Length(T);
  while (Result < N) and (Result < 6) and (T[Result + 1] = '#') do
    Inc(Result);
  if Result = 0 then
    Exit;
  if (Result < N) and (T[Result + 1] <> ' ') then
    Result := 0;
end;

function AtxHeadingText(const T: string; ALevel: Integer): string;
begin
  Result := TrimLeft(Copy(T, ALevel + 1, MaxInt));
end;

// Markdown image paths conventionally use '/' even in a Windows document, so
// plain ExtractFileName (which only recognizes the platform PathDelim, '\'
// on Windows — never '/') would return the whole "dir/name.png" unsplit.
function LastPathSegment(const APath: string): string;
var
  P: Integer;
begin
  P := Length(APath);
  while (P > 0) and not CharInSet(APath[P], ['/', '\']) do
    Dec(P);
  Result := Copy(APath, P + 1, MaxInt);
end;

function HeadingKind(ALevel: Integer): TMdSpanKind;
begin
  case ALevel of
    1: Result := mskH1;
    2: Result := mskH2;
  else
    Result := mskH3to6;
  end;
end;

// '---', '***', '___', '- - -' ... (spaces stripped, 3+ of the same char left).
function IsHRule(const T: string): Boolean;
var
  S: string;
  Ch: Char;
  I: Integer;
begin
  Result := False;
  S := StringReplace(T, ' ', '', [rfReplaceAll]);
  if Length(S) < 3 then
    Exit;
  Ch := S[1];
  if not CharInSet(Ch, ['-', '*', '_']) then
    Exit;
  for I := 2 to Length(S) do
    if S[I] <> Ch then
      Exit;
  Result := True;
end;

function LeadingWhitespaceLen(const S: string): Integer;
var
  N: Integer;
begin
  Result := 0;
  N := Length(S);
  while (Result < N) and CharInSet(S[Result + 1], [' ', #9]) do
    Inc(Result);
end;

// Length of "indent + bullet/ordinal marker + following space" starting
// after AWs leading whitespace chars, or 0 if ARaw isn't a list item line.
function ListMarkerLen(const ARaw: string; AWs: Integer): Integer;
var
  N, P: Integer;
begin
  Result := 0;
  N := Length(ARaw);
  P := AWs + 1;
  if P > N then
    Exit;
  if CharInSet(ARaw[P], ['-', '*', '+']) then
  begin
    if (P + 1 <= N) and (ARaw[P + 1] = ' ') then
      Result := P + 1;
    Exit;
  end;
  if CharInSet(ARaw[P], ['0'..'9']) then
  begin
    while (P <= N) and CharInSet(ARaw[P], ['0'..'9']) do
      Inc(P);
    if (P <= N) and (ARaw[P] = '.') and (P + 1 <= N) and (ARaw[P + 1] = ' ') then
      Result := P + 1;
  end;
end;

function IsMdImageExt(const AExt: string): Boolean;
var
  E: string;
begin
  E := LowerCase(AExt);
  Result := (E = '.png') or (E = '.jpg') or (E = '.jpeg') or (E = '.bmp');
end;

// Whole (trimmed) line is exactly "![alt](path)" — Stage 25 Overlay shape.
// Inline images mid-paragraph stay out of scope (readme.md Этап 25).
function TryParseCommonMarkImage(const T: string; out AAlt, APath: string): Boolean;
var
  N, CloseBracket, CloseParen, Gt, Sp: Integer;
begin
  Result := False;
  AAlt := '';
  APath := '';
  N := Length(T);
  if (N < 5) or (T[1] <> '!') or (T[2] <> '[') then
    Exit;
  CloseBracket := PosEx(']', T, 3);
  if CloseBracket = 0 then
    Exit;
  if (CloseBracket + 2 > N) or (T[CloseBracket + 1] <> '(') then
    Exit;
  if T[CloseBracket + 2] = '<' then
  begin
    // "![alt](<path with spaces>)" — Obsidian writes this form for names with
    // spaces; the path itself may contain ')' so look for '>' first.
    Gt := PosEx('>', T, CloseBracket + 3);
    if Gt = 0 then
      Exit;
    CloseParen := PosEx(')', T, Gt + 1);
    if CloseParen <> N then
      Exit;
    APath := Copy(T, CloseBracket + 3, Gt - CloseBracket - 3);
  end
  else
  begin
    CloseParen := PosEx(')', T, CloseBracket + 2);
    if (CloseParen = 0) or (CloseParen <> N) then
      Exit;
    APath := Trim(Copy(T, CloseBracket + 2, CloseParen - CloseBracket - 2));
    // A bare destination has no spaces; anything after one is the optional
    // "title" (![alt](cat.png "Cat")).
    Sp := Pos(' ', APath);
    if Sp > 0 then
      APath := Copy(APath, 1, Sp - 1);
  end;
  AAlt := Copy(T, 3, CloseBracket - 3);
  Result := True;
end;

// Obsidian embed on its own line: ![[file.png]] or ![[file.png|wsmall]].
// Only image extensions — ![[OtherNote]] is a note transclusion, not Overlay.
function TryParseWikiImage(const T: string; out AAlt, APath: string): Boolean;
var
  N, Pipe: Integer;
  Inner, NamePart: string;
begin
  Result := False;
  AAlt := '';
  APath := '';
  N := Length(T);
  if (N < 8) or (Copy(T, 1, 3) <> '![[') or (Copy(T, N - 1, 2) <> ']]') then
    Exit;
  Inner := Copy(T, 4, N - 5);
  Pipe := Pos('|', Inner);
  if Pipe > 0 then
    NamePart := Trim(Copy(Inner, 1, Pipe - 1))
  else
    NamePart := Trim(Inner);
  if (NamePart = '') or not IsMdImageExt(ExtractFileExt(NamePart)) then
    Exit;
  APath := NamePart;
  AAlt := ChangeFileExt(LastPathSegment(NamePart), '');
  Result := True;
end;

function TryParseStandaloneImage(const ARaw: string; out AAlt, APath: string): Boolean;
var
  T: string;
begin
  T := Trim(ARaw);
  Result := TryParseCommonMarkImage(T, AAlt, APath) or
    TryParseWikiImage(T, AAlt, APath);
end;

// "%20" etc. in a CommonMark destination are percent-encoded UTF-8 bytes.
// Malformed escapes are kept literally.
function PercentDecodeUtf8(const S: string): string;

  function HexVal(C: Char): Integer;
  begin
    case C of
      '0'..'9': Result := Ord(C) - Ord('0');
      'A'..'F': Result := Ord(C) - Ord('A') + 10;
      'a'..'f': Result := Ord(C) - Ord('a') + 10;
    else
      Result := -1;
    end;
  end;

var
  Bytes: TBytes;
  I, J, N, Hi, Lo: Integer;
begin
  if Pos('%', S) = 0 then
    Exit(S);
  SetLength(Bytes, 0);
  N := Length(S);
  I := 1;
  while I <= N do
  begin
    if (S[I] = '%') and (I + 2 <= N) then
    begin
      Hi := HexVal(S[I + 1]);
      Lo := HexVal(S[I + 2]);
      if (Hi >= 0) and (Lo >= 0) then
      begin
        Bytes := Bytes + [Byte(Hi * 16 + Lo)];
        Inc(I, 3);
        Continue;
      end;
    end;
    J := PosEx('%', S, I + 1);
    if J = 0 then
      J := N + 1;
    Bytes := Bytes + TEncoding.UTF8.GetBytes(Copy(S, I, J - I));
    I := J;
  end;
  try
    Result := TEncoding.UTF8.GetString(Bytes);
  except
    Result := S;
  end;
end;

function MarkdownResolveImageFile(const ADocPath, AImageRef: string): string;
const
  // Obsidian links are relative to the vault root, which can be any ancestor
  // of the note's folder; bound the walk up.
  cMaxAncestors = 32;
var
  Dir: string;

  function ExistsFile(const APath: string): Boolean;
  begin
    Result := (APath <> '') and FileExists(APath);
  end;

  function Resolve(const ARel: string): string;
  var
    Rel, Name, Candidate, Up, Parent: string;
    I: Integer;
  begin
    Result := '';
    Rel := StringReplace(ARel, '/', PathDelim, [rfReplaceAll]);
    // '<', '>', '|', '"', '?', '*': TPath raises on them — not a file ref.
    if (Rel = '') or not TPath.HasValidPathChars(Rel, False) then
      Exit;
    if TPath.IsPathRooted(Rel) then
    begin
      if ExistsFile(Rel) then
        Result := Rel;
      Exit;
    end;
    if Dir = '' then
      Exit;
    // Note-relative first, then the same path from each ancestor folder
    // (Obsidian "path from vault root" links).
    Up := Dir;
    for I := 0 to cMaxAncestors do
    begin
      Candidate := TPath.Combine(Up, Rel);
      if ExistsFile(Candidate) then
        Exit(Candidate);
      Parent := ExtractFileDir(Up);
      if (Parent = '') or SameText(Parent, Up) then
        Break;
      Up := Parent;
    end;
    Name := ExtractFileName(Rel);
    if Name = '' then
      Exit;
    Candidate := TPath.Combine(TPath.Combine(Dir, 'attachments'), Name);
    if ExistsFile(Candidate) then
      Result := Candidate;
  end;

var
  Ref, Decoded: string;
begin
  Result := '';
  Ref := Trim(AImageRef);
  if (Ref = '') or (Pos('://', Ref) > 0) then
    Exit;
  // A bad image reference must never break opening the document.
  try
    Dir := ExtractFileDir(ADocPath);
    Result := Resolve(Ref);
    if Result = '' then
    begin
      Decoded := PercentDecodeUtf8(Ref);
      if Decoded <> Ref then
        Result := Resolve(Decoded);
    end;
  except
    Result := '';
  end;
end;

type
  // Inline parsing both re-flows the text (emphasis delimiters are dropped)
  // and produces spans into that new text, so the two have to travel together —
  // a bare TArray<TMdSpan> result is no longer enough on its own.
  TMdInlineResult = record
    Text: string;
    Spans: TArray<TMdSpan>;
  end;

// CommonMark's intraword-underscore rule: '_' inside "WM_COPYDATA" or
// "some_var_name" must NOT be read as an emphasis delimiter (unlike '*',
// which CommonMark does allow intraword) — otherwise a single identifier
// containing an underscore, or worse, two underscored identifiers on the
// same line, would spuriously turn everything between them italic/bold.
function IsWordChar(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Single left-to-right pass: at each position, try each inline construct in
// precedence order (code > ***bold+italic*** > **bold** > __bold__ >
// ~~strike~~ > [link](url) > *italic* > _italic_); first match wins. Bold,
// italic, and bold+italic are STRIPPED (only the inner text is copied to
// the output, the * / ** / *** / _ / __ delimiters are dropped); a link
// keeps only its [text] (the url goes to TMdSpan.Target); every other
// construct is copied through verbatim (delimiters included) and colored as
// one span.
// No nesting (e.g. an *italic* run inside **bold** is not separately
// styled) and an unmatched opening marker is copied through as plain text
// rather than consuming the rest of the line — deliberate MVP
// simplifications for a TUI cell-grid viewer, not a CommonMark-conformant
// inline parser.
function ParseInline(const S: string): TMdInlineResult;
var
  Spans: TList<TMdSpan>;
  Text: string;
  I, N: Integer;

  function TryMarker(const AOpen, AClose: string; AKind: TMdSpanKind;
    AStrip: Boolean; ARequireWordBoundary: Boolean = False): Boolean;
  var
    OpenLen, CloseIdx, SpanStart, CopyFrom, CopyLen, AfterClose: Integer;
  begin
    Result := False;
    OpenLen := Length(AOpen);
    if I + OpenLen - 1 > N then
      Exit;
    if Copy(S, I, OpenLen) <> AOpen then
      Exit;
    // _/__ only count as delimiters at a word boundary: not immediately
    // preceded by a word char on the left...
    if ARequireWordBoundary and (I > 1) and IsWordChar(S[I - 1]) then
      Exit;
    CloseIdx := PosEx(AClose, S, I + OpenLen);
    if CloseIdx = 0 then
      Exit;
    // Adjacent markers ("**unterminated", empty "**") are not a match —
    // otherwise a failed **bold** attempt would let *italic* swallow the
    // two opening stars as an empty span and drop them from DisplayText.
    if CloseIdx <= I + OpenLen then
      Exit;
    // ...and not immediately followed by a word char on the right (e.g.
    // "_foo_bar" — the second '_' abuts "bar", so it can't close either).
    AfterClose := CloseIdx + Length(AClose);
    if ARequireWordBoundary and (AfterClose <= N) and IsWordChar(S[AfterClose]) then
      Exit;
    SpanStart := Length(Text) + 1;
    if AStrip then
    begin
      CopyFrom := I + OpenLen;
      CopyLen := CloseIdx - CopyFrom;
    end
    else
    begin
      CopyFrom := I;
      CopyLen := CloseIdx + Length(AClose) - I;
    end;
    Text := Text + Copy(S, CopyFrom, CopyLen);
    Spans.Add(MakeSpan(SpanStart, Length(Text) - SpanStart + 1, AKind));
    I := CloseIdx + Length(AClose);
    Result := True;
  end;

  function TryLink: Boolean;
  var
    CloseBracket, CloseParen, SpanStart: Integer;
    LinkText, LinkTarget: string;
    Span: TMdSpan;
  begin
    Result := False;
    if S[I] <> '[' then
      Exit;
    CloseBracket := PosEx(']', S, I + 1);
    if CloseBracket = 0 then
      Exit;
    if (CloseBracket + 1 > N) or (S[CloseBracket + 1] <> '(') then
      Exit;
    CloseParen := PosEx(')', S, CloseBracket + 2);
    if CloseParen = 0 then
      Exit;
    LinkText := Copy(S, I + 1, CloseBracket - I - 1);
    LinkTarget := Trim(Copy(S, CloseBracket + 2, CloseParen - CloseBracket - 2));
    if LinkText = '' then
      LinkText := LinkTarget;
    SpanStart := Length(Text) + 1;
    Text := Text + LinkText;
    Span := MakeSpan(SpanStart, Length(LinkText), mskLink);
    Span.Target := LinkTarget;
    Spans.Add(Span);
    I := CloseParen + 1;
    Result := True;
  end;

begin
  Spans := TList<TMdSpan>.Create;
  try
    N := Length(S);
    I := 1;
    Text := '';
    while I <= N do
    begin
      if TryMarker('`', '`', mskInlineCode, False) then Continue;
      if TryMarker('***', '***', mskBoldItalic, True) then Continue;
      if TryMarker('**', '**', mskBold, True) then Continue;
      if TryMarker('__', '__', mskBold, True, True) then Continue;
      if TryMarker('~~', '~~', mskStrike, False) then Continue;
      if TryLink then Continue;
      if TryMarker('*', '*', mskItalic, True) then Continue;
      if TryMarker('_', '_', mskItalic, True, True) then Continue;
      Text := Text + S[I];
      Inc(I);
    end;
    Result.Text := Text;
    Result.Spans := Spans.ToArray;
  finally
    Spans.Free;
  end;
end;

// Blockquote '>' / list marker prefix (copied through verbatim, never
// stripped), followed by the inline-parsed, possibly-reflowed remainder of
// the line (its spans offset past the prefix).
function BuildPrefixedSpans(const ARaw: string; APrefixLen: Integer;
  APrefixKind: TMdSpanKind): TMdInlineResult;
var
  Rest: TMdInlineResult;
  I: Integer;
begin
  Rest := ParseInline(Copy(ARaw, APrefixLen + 1, MaxInt));
  Result.Text := Copy(ARaw, 1, APrefixLen) + Rest.Text;
  SetLength(Result.Spans, Length(Rest.Spans) + 1);
  Result.Spans[0] := MakeSpan(1, APrefixLen, APrefixKind);
  for I := 0 to High(Rest.Spans) do
  begin
    Rest.Spans[I].StartCol := Rest.Spans[I].StartCol + APrefixLen;
    Result.Spans[I + 1] := Rest.Spans[I];
  end;
end;

class function TMarkdownParser.ParseLine(const ARaw: string; var AState: TMdFenceState): TMdLine;
var
  Trimmed: string;
  HeadLevel, Ws, MarkerLen: Integer;
  Alt, Path: string;
  InlineRes: TMdInlineResult;
begin
  Result.DisplayText := ARaw;
  Result.IsImage := False;
  Result.ImageAlt := '';
  Result.ImagePath := '';
  Result.IsTable := False;
  Result.Spans := nil;

  Trimmed := TrimLeft(ARaw);

  // Already inside a fence: whole line is code; a closing marker ends it
  // but the delimiter line itself still renders as code (same as opening).
  if AState.InFence then
  begin
    Result.Spans := SingleSpan(1, Length(ARaw), mskCodeBlock);
    if IsFenceMarker(Trimmed) then
      AState.InFence := False;
    Exit;
  end;

  if IsFenceMarker(Trimmed) then
  begin
    AState.InFence := True;
    Result.Spans := SingleSpan(1, Length(ARaw), mskCodeBlock);
    Exit;
  end;

  if TryParseStandaloneImage(ARaw, Alt, Path) then
  begin
    Result.IsImage := True;
    Result.ImageAlt := Alt;
    Result.ImagePath := Path;
    if Alt <> '' then
      Result.DisplayText := '[image: ' + Alt + ']'
    else
      Result.DisplayText := '[image: ' + LastPathSegment(Path) + ']';
    Result.Spans := SingleSpan(1, Length(Result.DisplayText), mskImageMarker);
    Exit;
  end;

  HeadLevel := AtxHeadingLevel(Trimmed);
  if HeadLevel > 0 then
  begin
    // Inline markup inside the heading ("## **Title**", "# `code` and
    // [link](x)") is stripped the same way as in body text, but the whole
    // line keeps the one heading style — inline spans' colors would
    // override it.
    InlineRes := ParseInline(AtxHeadingText(Trimmed, HeadLevel));
    Result.DisplayText := InlineRes.Text;
    Result.Spans := SingleSpan(1, Length(Result.DisplayText), HeadingKind(HeadLevel));
    Exit;
  end;

  if IsHRule(Trimmed) then
  begin
    Result.Spans := SingleSpan(1, Length(ARaw), mskHRule);
    Exit;
  end;

  Ws := LeadingWhitespaceLen(ARaw);
  if (Ws < Length(ARaw)) and (ARaw[Ws + 1] = '>') then
  begin
    InlineRes := BuildPrefixedSpans(ARaw, Ws + 1, mskQuote);
    Result.DisplayText := InlineRes.Text;
    Result.Spans := InlineRes.Spans;
    Exit;
  end;

  MarkerLen := ListMarkerLen(ARaw, Ws);
  if MarkerLen > 0 then
  begin
    InlineRes := BuildPrefixedSpans(ARaw, MarkerLen, mskListMarker);
    Result.DisplayText := InlineRes.Text;
    Result.Spans := InlineRes.Spans;
    Exit;
  end;

  InlineRes := ParseInline(ARaw);
  Result.DisplayText := InlineRes.Text;
  Result.Spans := InlineRes.Spans;
end;

function UnescapedPipePos(const S: string; AFrom: Integer): Integer;
var
  I, Bs: Integer;
begin
  Result := 0;
  I := AFrom;
  while I <= Length(S) do
  begin
    if S[I] = '|' then
    begin
      Bs := 0;
      while (I - 1 - Bs >= 1) and (S[I - 1 - Bs] = '\') do
        Inc(Bs);
      if Bs mod 2 = 0 then
        Exit(I);
    end;
    Inc(I);
  end;
end;

function TrailingPipeIsUnescaped(const S: string): Boolean;
var
  Bs: Integer;
begin
  Result := False;
  if (S = '') or (S[Length(S)] <> '|') then
    Exit;
  Bs := 0;
  while (Length(S) - 1 - Bs >= 1) and (S[Length(S) - 1 - Bs] = '\') do
    Inc(Bs);
  Result := Bs mod 2 = 0;
end;

function SplitPipeCells(const ARaw: string): TArray<string>;
var
  S: string;
  Cells: TList<string>;
  Start, P: Integer;
begin
  S := Trim(ARaw);
  Cells := TList<string>.Create;
  try
    if (S <> '') and (S[1] = '|') then
      Delete(S, 1, 1);
    if TrailingPipeIsUnescaped(S) then
      Delete(S, Length(S), 1);
    Start := 1;
    while True do
    begin
      P := UnescapedPipePos(S, Start);
      if P = 0 then
      begin
        Cells.Add(StringReplace(Trim(Copy(S, Start, MaxInt)), '\|', '|',
          [rfReplaceAll]));
        Break;
      end;
      Cells.Add(StringReplace(Trim(Copy(S, Start, P - Start)), '\|', '|',
        [rfReplaceAll]));
      Start := P + 1;
    end;
    Result := Cells.ToArray;
  finally
    Cells.Free;
  end;
end;

function IsSeparatorCell(const ACell: string): Boolean;
var
  T: string;
  I, Dash: Integer;
begin
  Result := False;
  T := Trim(ACell);
  if T = '' then
    Exit;
  I := 1;
  if T[I] = ':' then
    Inc(I);
  Dash := 0;
  while (I <= Length(T)) and (T[I] = '-') do
  begin
    Inc(Dash);
    Inc(I);
  end;
  if Dash < 3 then
    Exit;
  if (I <= Length(T)) and (T[I] = ':') then
    Inc(I);
  Result := I > Length(T);
end;

function AlignOfCell(const ACell: string): TMdTableAlign;
var
  T: string;
  LeftColon, RightColon: Boolean;
begin
  T := Trim(ACell);
  LeftColon := (T <> '') and (T[1] = ':');
  RightColon := (T <> '') and (T[Length(T)] = ':');
  if LeftColon and RightColon then
    Result := mtaCenter
  else if RightColon then
    Result := mtaRight
  else
    Result := mtaLeft;
end;

class function TMarkdownParser.LooksLikePipeTableRow(const ARaw: string): Boolean;
var
  Cells: TArray<string>;
begin
  Result := False;
  if UnescapedPipePos(Trim(ARaw), 1) = 0 then
    Exit;
  if IsFenceMarker(TrimLeft(ARaw)) then
    Exit;
  Cells := SplitPipeCells(ARaw);
  Result := Length(Cells) >= 1;
end;

class function TMarkdownParser.IsPipeTableSeparator(const ARaw: string): Boolean;
var
  Cells: TArray<string>;
  I: Integer;
begin
  Result := False;
  if not LooksLikePipeTableRow(ARaw) then
    Exit;
  Cells := SplitPipeCells(ARaw);
  if Length(Cells) = 0 then
    Exit;
  for I := 0 to High(Cells) do
    if not IsSeparatorCell(Cells[I]) then
      Exit;
  Result := True;
end;

// '<br>' variants GFM tables use as the standard way to force a line break
// inside one cell (a literal newline can't appear there, since a pipe row
// is exactly one source line). Case-insensitive; accepts optional
// whitespace and a self-closing '/' but not attributes — same "cell-grid
// viewer, not a CommonMark-conformant parser" scope as the rest of this
// file's inline handling.
function IsBrTag(const S: string; APos: Integer; out ATagLen: Integer): Boolean;
var
  I, N: Integer;
begin
  Result := False;
  ATagLen := 0;
  N := Length(S);
  if (APos + 2 > N) or (S[APos] <> '<') then
    Exit;
  if not (CharInSet(S[APos + 1], ['b', 'B']) and CharInSet(S[APos + 2], ['r', 'R'])) then
    Exit;
  I := APos + 3;
  while (I <= N) and (S[I] = ' ') do
    Inc(I);
  if (I <= N) and (S[I] = '/') then
    Inc(I);
  while (I <= N) and (S[I] = ' ') do
    Inc(I);
  if (I <= N) and (S[I] = '>') then
  begin
    ATagLen := I - APos + 1;
    Result := True;
  end;
end;

// Splits one raw table-cell string on '<br>' tags into forced line segments
// — GFM's standard workaround for a multi-line cell. Always returns at
// least one segment, even with no '<br>' present.
function SplitCellBr(const ARaw: string): TArray<string>;
var
  Segs: TList<string>;
  Start, I, TagLen: Integer;
begin
  Segs := TList<string>.Create;
  try
    Start := 1;
    I := 1;
    while I <= Length(ARaw) do
    begin
      if IsBrTag(ARaw, I, TagLen) then
      begin
        Segs.Add(Copy(ARaw, Start, I - Start));
        Inc(I, TagLen);
        Start := I;
      end
      else
        Inc(I);
    end;
    Segs.Add(Copy(ARaw, Start, MaxInt));
    Result := Segs.ToArray;
  finally
    Segs.Free;
  end;
end;

// Clips ASpans to [AFrom, ATo] (1-based, inclusive, in the coordinate space
// the spans already live in) and translates the surviving pieces to be
// 1-based within just that slice — e.g. turning a table cell's whole-text
// span into one local to a single wrapped physical row of that cell.
function SliceSpans(const ASpans: TArray<TMdSpan>; AFrom, ATo: Integer): TArray<TMdSpan>;
var
  Sliced: TList<TMdSpan>;
  I, SpanFrom, SpanTo: Integer;
  Span: TMdSpan;
begin
  Sliced := TList<TMdSpan>.Create;
  try
    for I := 0 to High(ASpans) do
    begin
      Span := ASpans[I];
      SpanFrom := Max(Span.StartCol, AFrom);
      SpanTo := Min(Span.StartCol + Span.Len - 1, ATo);
      if SpanTo < SpanFrom then
        Continue;
      Sliced.Add(MakeSpan(SpanFrom - AFrom + 1, SpanTo - SpanFrom + 1, Span.Kind));
    end;
    Result := Sliced.ToArray;
  finally
    Sliced.Free;
  end;
end;

// Every physical row one table cell needs at AWidth: '<br>' tags force a
// new row regardless of available width (that's the point of writing one),
// and each resulting segment is then word-wrapped to AWidth like any other
// cell text. Always returns at least one (possibly empty) row.
function BuildCellRows(const ARawCell: string; AWidth: Integer): TArray<TMdInlineResult>;
var
  Segments: TArray<string>;
  S, I, ChunkStart, ChunkEnd: Integer;
  Inner: TMdInlineResult;
  Starts: TArray<Integer>;
  Rows: TList<TMdInlineResult>;
  Row: TMdInlineResult;
begin
  Segments := SplitCellBr(ARawCell);
  Rows := TList<TMdInlineResult>.Create;
  try
    for S := 0 to High(Segments) do
    begin
      Inner := ParseInline(Segments[S]);
      Starts := TMarkdownParser.ComputeWrapStarts(Inner.Text, AWidth);
      for I := 0 to High(Starts) do
      begin
        ChunkStart := Starts[I];
        if I < High(Starts) then
          ChunkEnd := Starts[I + 1] - 1
        else
          ChunkEnd := Length(Inner.Text);
        Row.Text := Copy(Inner.Text, ChunkStart, ChunkEnd - ChunkStart + 1);
        Row.Spans := SliceSpans(Inner.Spans, ChunkStart, ChunkEnd);
        Rows.Add(Row);
      end;
    end;
    Result := Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

procedure FitCell(const AText: string; AWidth: Integer; AAlign: TMdTableAlign;
  out AOut: string; out ALeftPad: Integer);
var
  Core: string;
  Pad, Right: Integer;
begin
  if AWidth < 1 then
    AWidth := 1;
  if Length(AText) > AWidth then
    Core := Copy(AText, 1, AWidth)
  else
    Core := AText;
  Pad := AWidth - Length(Core);
  case AAlign of
    mtaRight:
      begin
        ALeftPad := Pad;
        AOut := StringOfChar(' ', Pad) + Core;
      end;
    mtaCenter:
      begin
        ALeftPad := Pad div 2;
        Right := Pad - ALeftPad;
        AOut := StringOfChar(' ', ALeftPad) + Core + StringOfChar(' ', Right);
      end;
  else
    begin
      ALeftPad := 0;
      AOut := Core + StringOfChar(' ', Pad);
    end;
  end;
end;

const
  // A column shrunk to fit a narrow viewport never goes below this many
  // text columns, unless the viewport is too narrow to give every column
  // even this much (see ComputeTableColumnWidths).
  cMdTableMinColWidth = 3;

// One vertical rule per column plus a leading one (ColCount + 1), plus one
// leading and one trailing padding space around every cell's text
// (ColCount * 2) — the fixed per-table overhead FormatPipeTableLine's
// DisplayText always carries regardless of column widths.
function PipeTableOverhead(AColCount: Integer): Integer;
begin
  Result := 3 * AColCount + 1;
end;

function ArraySum(const AValues: TArray<Integer>): Integer;
var
  V: Integer;
begin
  Result := 0;
  for V in AValues do
    Inc(Result, V);
end;

// Column widths for a table that must fit within AAvailForText columns of
// cell text (i.e. AAvailWidth already stripped of PipeTableOverhead), given
// each column's natural (unwrapped) content width in ANatural. Never widens
// a column past its natural width (no point wrapping a column that already
// fits within an equal share). Columns narrower than their fair share keep
// their natural width; the space that frees up is handed to the columns
// that still need it, in proportion to how much they're still over.
function ComputeTableColumnWidths(const ANatural: TArray<Integer>;
  AAvailForText: Integer): TArray<Integer>;
var
  ColCount, C, MinW, UsedBaseline, Pool, TotalDeficit, Extra, UsedSum, Remainder: Integer;
  Deficit: TArray<Integer>;
begin
  ColCount := Length(ANatural);
  SetLength(Result, ColCount);
  if ColCount = 0 then
    Exit;

  MinW := cMdTableMinColWidth;
  if MinW * ColCount > AAvailForText then
    MinW := Max(1, AAvailForText div ColCount);

  SetLength(Deficit, ColCount);
  UsedBaseline := 0;
  TotalDeficit := 0;
  for C := 0 to ColCount - 1 do
  begin
    Result[C] := Min(ANatural[C], MinW);
    Deficit[C] := Max(ANatural[C] - Result[C], 0);
    Inc(UsedBaseline, Result[C]);
    Inc(TotalDeficit, Deficit[C]);
  end;

  Pool := AAvailForText - UsedBaseline;
  if (Pool <= 0) or (TotalDeficit <= 0) then
    Exit;

  UsedSum := UsedBaseline;
  for C := 0 to ColCount - 1 do
    if Deficit[C] > 0 then
    begin
      Extra := (Deficit[C] * Pool) div TotalDeficit;
      Inc(Result[C], Extra);
      Inc(UsedSum, Extra);
    end;

  // Integer division above can leave a few text columns short of
  // AAvailForText — hand them out one at a time, round-robin, to columns
  // that still have room to grow (TotalDeficit > Pool guarantees at least
  // one such column exists, so this always terminates).
  Remainder := AAvailForText - UsedSum;
  C := 0;
  while Remainder > 0 do
  begin
    if Result[C] < ANatural[C] then
    begin
      Inc(Result[C]);
      Dec(Remainder);
    end;
    C := (C + 1) mod ColCount;
  end;
end;

// Sum of every data row's cell natural widths per column (Rows[1], the
// separator row of dashes/colons, is skipped). A '<br>'-bearing cell always
// renders as separate lines regardless of width, so its "natural" width is
// the widest SEGMENT, not the whole cell's text run together.
function ComputeTableNaturalWidths(const Rows: TArray<TArray<string>>;
  AColCount: Integer): TArray<Integer>;
var
  I, J, C: Integer;
  ScanSegments: TArray<string>;
  ScanInner: TMdInlineResult;
begin
  SetLength(Result, AColCount);
  for C := 0 to AColCount - 1 do
    Result[C] := 1;
  for I := 0 to High(Rows) do
  begin
    if I = 1 then
      Continue;
    for C := 0 to High(Rows[I]) do
    begin
      ScanSegments := SplitCellBr(Rows[I][C]);
      for J := 0 to High(ScanSegments) do
      begin
        ScanInner := ParseInline(ScanSegments[J]);
        if Length(ScanInner.Text) > Result[C] then
          Result[C] := Length(ScanInner.Text);
      end;
    end;
  end;
end;

// The "|---|---|" row between a pipe table's header and body.
function BuildPipeTableSeparatorLine(AColCount: Integer;
  const AWidths: TArray<Integer>): TMdLine;
var
  C: Integer;
begin
  Result.DisplayText := chBoxVR;
  Result.Spans := nil;
  Result.IsImage := False;
  Result.ImageAlt := '';
  Result.ImagePath := '';
  Result.IsTable := True;
  for C := 0 to AColCount - 1 do
  begin
    Result.DisplayText := Result.DisplayText + StringOfChar(chBoxH, AWidths[C] + 2);
    if C < AColCount - 1 then
      Result.DisplayText := Result.DisplayText + chBoxX
    else
      Result.DisplayText := Result.DisplayText + chBoxVL;
  end;
  Result.Spans := SingleSpan(1, Length(Result.DisplayText), mskTableBorder);
end;

class function TMarkdownParser.FormatPipeTableLine(const ABlock: TArray<string>;
  AIndexInBlock: Integer; AAvailWidth: Integer): TMdLine;
begin
  if (Length(ABlock) < 2) or (AIndexInBlock < 0) or (AIndexInBlock > High(ABlock)) then
    Exit(FormatPipeTableRow('', 0, Default(TMdTableLayout)));
  Result := FormatPipeTableRow(ABlock[AIndexInBlock], AIndexInBlock,
    ComputeTableLayout(ABlock, AAvailWidth));
end;

class function TMarkdownParser.ComputeTableLayout(const ABlock: TArray<string>;
  AAvailWidth: Integer): TMdTableLayout;
var
  Rows: TArray<TArray<string>>;
  NaturalWidths: TArray<Integer>;
  ColCount, I, C, AvailForText: Integer;
begin
  Result := Default(TMdTableLayout);
  if Length(ABlock) < 2 then
    Exit;

  SetLength(Rows, Length(ABlock));
  ColCount := 0;
  for I := 0 to High(ABlock) do
  begin
    Rows[I] := SplitPipeCells(ABlock[I]);
    if Length(Rows[I]) > ColCount then
      ColCount := Length(Rows[I]);
  end;
  if ColCount < 1 then
    Exit;

  SetLength(Result.Aligns, ColCount);
  for C := 0 to ColCount - 1 do
    Result.Aligns[C] := mtaLeft;
  if Length(Rows[1]) > 0 then
    for C := 0 to Min(High(Rows[1]), ColCount - 1) do
      Result.Aligns[C] := AlignOfCell(Rows[1][C]);

  NaturalWidths := ComputeTableNaturalWidths(Rows, ColCount);

  AvailForText := AAvailWidth - PipeTableOverhead(ColCount);
  if (AAvailWidth <= 0) or (ArraySum(NaturalWidths) <= AvailForText) then
    Result.Widths := NaturalWidths
  else if AvailForText < ColCount then
    // The viewport can't even fit 1 text column per column plus the
    // borders/padding overhead — shrinking can't help (ComputeTableColumnWidths
    // would have to make a physical row WIDER than AAvailWidth to stay >=1
    // char per column, breaking the "every physical row is exactly AAvailWidth"
    // invariant ComputeHardWrapStarts's fixed-width slicing in the Viewer
    // depends on). Fall back to natural widths — the Viewer's existing
    // fixed-width hard-cut still degrades this gracefully, just densely.
    Result.Widths := NaturalWidths
  else
    Result.Widths := ComputeTableColumnWidths(NaturalWidths, AvailForText);
  Result.ColCount := ColCount;
end;

class function TMarkdownParser.FormatPipeTableRow(const ARow: string;
  AIndexInBlock: Integer; const ALayout: TMdTableLayout): TMdLine;
var
  Cells: TArray<string>;
  Aligns: TArray<TMdTableAlign>;
  Widths: TArray<Integer>;
  ColCount, I, C, R, RowLines, CellStart, LeftPad, OutStart: Integer;
  ColRows: TArray<TArray<TMdInlineResult>>;
  RowContent: TMdInlineResult;
  Padded: string;
  Spans: TList<TMdSpan>;
  IsHeader, IsSep: Boolean;
  Span: TMdSpan;
begin
  Result.DisplayText := '';
  Result.Spans := nil;
  Result.IsImage := False;
  Result.ImageAlt := '';
  Result.ImagePath := '';
  Result.IsTable := False;
  ColCount := ALayout.ColCount;
  if (ColCount < 1) or (AIndexInBlock < 0) then
    Exit;
  Aligns := ALayout.Aligns;
  Widths := ALayout.Widths;
  Cells := SplitPipeCells(ARow);

  IsHeader := AIndexInBlock = 0;
  IsSep := AIndexInBlock = 1;
  if IsSep then
    Exit(BuildPipeTableSeparatorLine(ColCount, Widths));

  Spans := TList<TMdSpan>.Create;
  try
    // Every column's full row list is computed once up front —
    // BuildCellRows already handles both '<br>' forced breaks and
    // width-driven word-wrap, and hands back rows whose spans are already
    // local (1-based within that one row's own text). RowLines (how many
    // physical screen rows this source line needs) is the tallest column's
    // row count, at least 1.
    SetLength(ColRows, ColCount);
    RowLines := 1;
    for C := 0 to ColCount - 1 do
    begin
      if C <= High(Cells) then
        ColRows[C] := BuildCellRows(Cells[C], Widths[C])
      else
        ColRows[C] := BuildCellRows('', Widths[C]);
      if Length(ColRows[C]) > RowLines then
        RowLines := Length(ColRows[C]);
    end;

    for R := 0 to RowLines - 1 do
    begin
      Result.DisplayText := Result.DisplayText + chBoxV;
      Spans.Add(MakeSpan(Length(Result.DisplayText), 1, mskTableBorder));
      for C := 0 to ColCount - 1 do
      begin
        if R < Length(ColRows[C]) then
          RowContent := ColRows[C][R]
        else
        begin
          // This column ran out of rows before RowLines — pad out with a
          // blank cell for the remaining physical rows.
          RowContent.Text := '';
          RowContent.Spans := nil;
        end;
        FitCell(RowContent.Text, Widths[C], Aligns[C], Padded, LeftPad);
        CellStart := Length(Result.DisplayText) + 1;
        Result.DisplayText := Result.DisplayText + ' ' + Padded + ' ' + chBoxV;
        if IsHeader then
          Spans.Add(MakeSpan(CellStart, Length(Padded) + 2, mskTableHeader));
        for I := 0 to High(RowContent.Spans) do
        begin
          Span := RowContent.Spans[I];
          OutStart := CellStart + 1 + LeftPad + Span.StartCol - 1;
          Spans.Add(MakeSpan(OutStart, Span.Len, Span.Kind));
        end;
        Spans.Add(MakeSpan(Length(Result.DisplayText), 1, mskTableBorder));
      end;
    end;
    Result.Spans := Spans.ToArray;
  finally
    Spans.Free;
  end;
  Result.IsTable := True;
end;

// Word-wrap break points: whitespace plus the punctuation a line most
// naturally breaks after. CharInSet's TSysCharSet only covers ordinals
// 0..255, so multi-byte punctuation (em/en dash, curly quotes, CJK
// punctuation) never matches — plain ASCII '-' still does, which covers the
// common markdown/plain-text case.
function IsWrapBreakChar(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, [' ', #9, '.', ',', ';', ':', '!', '?', '-',
    ')', ']', '}', '/', '\']);
end;

class function TMarkdownParser.ComputeWrapStarts(const AText: string; AWidth: Integer): TArray<Integer>;
var
  Starts: TList<Integer>;
  N, LineStart, BestBreak, I: Integer;
begin
  Starts := TList<Integer>.Create;
  try
    N := Length(AText);
    if (N = 0) or (AWidth <= 0) then
    begin
      Starts.Add(1);
      Result := Starts.ToArray;
      Exit;
    end;
    LineStart := 1;
    while LineStart <= N do
    begin
      Starts.Add(LineStart);
      if N - LineStart + 1 <= AWidth then
        Break; // rest of the text fits on this one row — done
      // Rightmost break char within [LineStart+1, LineStart+AWidth-1] — the
      // lower bound excludes LineStart itself so a row can never come out
      // zero-length (which would loop forever).
      BestBreak := 0;
      for I := LineStart + AWidth - 1 downto LineStart + 1 do
        if IsWrapBreakChar(AText[I]) then
        begin
          BestBreak := I;
          Break;
        end;
      if BestBreak = 0 then
        LineStart := LineStart + AWidth // no break char in range — hard cut
      else
        LineStart := BestBreak + 1; // break char stays as this row's last char
    end;
    Result := Starts.ToArray;
  finally
    Starts.Free;
  end;
end;

class function TMarkdownParser.ComputeHardWrapStarts(const AText: string; AWidth: Integer): TArray<Integer>;
var
  Starts: TList<Integer>;
  N, LineStart: Integer;
begin
  Starts := TList<Integer>.Create;
  try
    N := Length(AText);
    if (N = 0) or (AWidth <= 0) then
    begin
      Starts.Add(1);
      Result := Starts.ToArray;
      Exit;
    end;
    LineStart := 1;
    while LineStart <= N do
    begin
      Starts.Add(LineStart);
      if N - LineStart + 1 <= AWidth then
        Break;
      LineStart := LineStart + AWidth;
    end;
    Result := Starts.ToArray;
  finally
    Starts.Free;
  end;
end;

end.
