program TestMarkdownParser;

{ Stage 25 regression: uMarkdownParser (pure line parsing) and
  uMarkdownIndex.TMarkdownFenceIndex (lazy fence-state recovery for large
  documents). Source is deliberately pure ASCII for the same reason
  TestStreamingViewer.dpr is — no literal non-ASCII, only explicit
  codepoints, so this .dpr's own encoding can never be the thing under test. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.UITypes,
  Winapi.Windows,
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas',
  uZipVfs in '..\Core\uZipVfs.pas',
  uFindSession in '..\Core\uFindSession.pas',
  uFindVfs in '..\Core\uFindVfs.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\Core\uVfsRouter.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uEditorDoc in '..\Core\uEditorDoc.pas',
  uMarkdownParser in '..\Core\uMarkdownParser.pas',
  uMarkdownIndex in '..\Core\uMarkdownIndex.pas',
  uMarkdownPainter in '..\Core\uMarkdownPainter.pas';

var
  GTempDir: string;
  GFailures: Integer = 0;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Writeln('  [PASS] ', AWhat)
  else
  begin
    Writeln('  [FAIL] ', AWhat);
    Inc(GFailures);
  end;
end;

function KindName(AKind: TMdSpanKind): string;
begin
  case AKind of
    mskText: Result := 'Text';
    mskH1: Result := 'H1';
    mskH2: Result := 'H2';
    mskH3to6: Result := 'H3to6';
    mskBold: Result := 'Bold';
    mskItalic: Result := 'Italic';
    mskBoldItalic: Result := 'BoldItalic';
    mskStrike: Result := 'Strike';
    mskInlineCode: Result := 'InlineCode';
    mskCodeBlock: Result := 'CodeBlock';
    mskQuote: Result := 'Quote';
    mskListMarker: Result := 'ListMarker';
    mskHRule: Result := 'HRule';
    mskLink: Result := 'Link';
    mskImageMarker: Result := 'ImageMarker';
    mskTableBorder: Result := 'TableBorder';
    mskTableHeader: Result := 'TableHeader';
  else
    Result := 'Unknown';
  end;
end;

/// <summary>True if ALine has exactly one span of AKind covering the full
/// DisplayText — the shape every whole-line construct (heading/hr/code
/// fence) produces.</summary>
function IsSingleFullSpan(const ALine: TMdLine; AKind: TMdSpanKind): Boolean;
begin
  Result := (Length(ALine.Spans) = 1) and (ALine.Spans[0].Kind = AKind) and
    (ALine.Spans[0].StartCol = 1) and (ALine.Spans[0].Len = Length(ALine.DisplayText));
end;

/// <summary>True if ALine has a span of AKind at [AStart, AStart+ALen).</summary>
function HasSpan(const ALine: TMdLine; AStart, ALen: Integer; AKind: TMdSpanKind): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(ALine.Spans) do
    if (ALine.Spans[I].StartCol = AStart) and (ALine.Spans[I].Len = ALen) and
       (ALine.Spans[I].Kind = AKind) then
      Exit(True);
end;

{ ---- ParseLine: headings ---------------------------------------------------- }

procedure TestHeadings;
var
  State: TMdFenceState;
  L: TMdLine;
begin
  Writeln('-- Headings --');
  State.InFence := False;

  L := TMarkdownParser.ParseLine('# Title', State);
  Check(L.DisplayText = 'Title', 'H1: leading "# " stripped');
  Check(IsSingleFullSpan(L, mskH1), 'H1: single mskH1 span over whole text');

  L := TMarkdownParser.ParseLine('## Sub', State);
  Check(L.DisplayText = 'Sub', 'H2: leading "## " stripped');
  Check(IsSingleFullSpan(L, mskH2), 'H2: single mskH2 span');

  L := TMarkdownParser.ParseLine('### Deep', State);
  Check(IsSingleFullSpan(L, mskH3to6), 'H3: collapses to mskH3to6');

  L := TMarkdownParser.ParseLine('###### Deepest', State);
  Check(IsSingleFullSpan(L, mskH3to6), 'H6: collapses to mskH3to6');

  L := TMarkdownParser.ParseLine('#######  Seven hashes', State);
  Check(not IsSingleFullSpan(L, mskH1) and not IsSingleFullSpan(L, mskH2) and
    not IsSingleFullSpan(L, mskH3to6), '7 leading #''s is not a heading (CommonMark caps at 6)');

  L := TMarkdownParser.ParseLine('#NoSpace', State);
  Check(not State.InFence, 'sanity: fence state unaffected by non-fence lines');
  Check(L.DisplayText = '#NoSpace', '"#NoSpace" (no space after #) is not a heading');

  L := TMarkdownParser.ParseLine('  ## Indented', State);
  Check(L.DisplayText = 'Indented', 'heading detection trims leading indentation first');

  L := TMarkdownParser.ParseLine('## **Основные положения**', State);
  Check(L.DisplayText = 'Основные положения', 'H2: **bold** markers inside a heading stripped');
  Check(IsSingleFullSpan(L, mskH2), 'H2 with inline markup keeps one heading span');

  L := TMarkdownParser.ParseLine('# *Intro* to `code` and [docs](http://x)', State);
  Check(L.DisplayText = 'Intro to `code` and docs',
    'H1: italic stripped, code kept, link reduced to its text');
end;

{ ---- ParseLine: fenced code blocks (state carried across lines) ------------ }

procedure TestFences;
var
  State: TMdFenceState;
  L: TMdLine;
begin
  Writeln('-- Fenced code blocks --');
  State.InFence := False;

  L := TMarkdownParser.ParseLine('```python', State);
  Check(State.InFence, 'opening ``` sets InFence');
  Check(IsSingleFullSpan(L, mskCodeBlock), 'fence-open line itself renders as mskCodeBlock');

  L := TMarkdownParser.ParseLine('def f(): # not a heading in here', State);
  Check(State.InFence, 'still inside fence after one content line');
  Check(IsSingleFullSpan(L, mskCodeBlock), 'fence content line is a single mskCodeBlock span');
  Check(L.DisplayText = 'def f(): # not a heading in here',
    'fence content is verbatim (a leading # is NOT parsed as a heading)');

  L := TMarkdownParser.ParseLine('```', State);
  Check(not State.InFence, 'closing ``` clears InFence');
  Check(IsSingleFullSpan(L, mskCodeBlock), 'closing fence line also renders as mskCodeBlock');

  L := TMarkdownParser.ParseLine('# back to normal', State);
  Check(IsSingleFullSpan(L, mskH1), 'heading parsing resumes once fence is closed');

  // Tilde fences and an unterminated fence running to EOF must not crash.
  State.InFence := False;
  TMarkdownParser.ParseLine('~~~', State);
  Check(State.InFence, '~~~ also opens a fence');
  TMarkdownParser.ParseLine('still open at EOF', State);
  Check(State.InFence, 'unterminated fence stays open (caller just stops calling ParseLine)');
end;

{ ---- ParseLine: blockquote / lists / hr ------------------------------------- }

procedure TestBlockConstructs;
var
  State: TMdFenceState;
  L: TMdLine;
begin
  Writeln('-- Blockquote / lists / hr --');
  State.InFence := False;

  L := TMarkdownParser.ParseLine('> a quote', State);
  Check(HasSpan(L, 1, 1, mskQuote), 'blockquote: leading ">" is a 1-char mskQuote span');
  Check(L.DisplayText = '> a quote', 'blockquote: DisplayText is NOT stripped (unlike headings)');

  L := TMarkdownParser.ParseLine('- item one', State);
  Check(HasSpan(L, 1, 2, mskListMarker), 'bullet "- ": 2-char mskListMarker span');

  L := TMarkdownParser.ParseLine('  * nested-ish', State);
  Check(HasSpan(L, 1, 4, mskListMarker), 'indented bullet: marker span includes the indent');

  L := TMarkdownParser.ParseLine('12. ordered', State);
  Check(HasSpan(L, 1, 4, mskListMarker), 'ordered marker "12. ": 4-char span');

  L := TMarkdownParser.ParseLine('*no space no list', State);
  Check(not HasSpan(L, 1, 2, mskListMarker), '"*" without a following space is not a list marker');

  L := TMarkdownParser.ParseLine('---', State);
  Check(IsSingleFullSpan(L, mskHRule), '"---" is a horizontal rule');
  L := TMarkdownParser.ParseLine('* * *', State);
  Check(IsSingleFullSpan(L, mskHRule), '"* * *" is a horizontal rule (spaces stripped), not a list');
  L := TMarkdownParser.ParseLine('___', State);
  Check(IsSingleFullSpan(L, mskHRule), '"___" is a horizontal rule');
  L := TMarkdownParser.ParseLine('--', State);
  Check(not IsSingleFullSpan(L, mskHRule), '"--" (only 2 chars) is not a horizontal rule');
end;

{ ---- ParseLine: inline emphasis -------------------------------------------- }

procedure TestInline;
var
  State: TMdFenceState;
  L: TMdLine;
begin
  Writeln('-- Inline emphasis --');
  State.InFence := False;

  L := TMarkdownParser.ParseLine('**bold** and *italic* and `code`', State);
  Check(L.DisplayText = 'bold and italic and `code`',
    '**bold**/*italic* delimiters are stripped from DisplayText; `code` delimiters are kept');
  Check(HasSpan(L, 1, 4, mskBold), '**bold** -> 4-char mskBold span over just "bold" (no ** in the span either)');
  Check(HasSpan(L, 10, 6, mskItalic), '*italic* -> 6-char mskItalic span over just "italic" (delimiters stripped)');
  Check(HasSpan(L, 21, 6, mskInlineCode), '`code` -> 6-char mskInlineCode span (delimiters included, not stripped)');

  L := TMarkdownParser.ParseLine('***both***', State);
  Check(L.DisplayText = 'both', '***both*** delimiters are fully stripped, leaving just "both"');
  Check(IsSingleFullSpan(L, mskBoldItalic), '***both*** -> single mskBoldItalic span, not bold+leftover');

  L := TMarkdownParser.ParseLine('~~gone~~', State);
  Check(IsSingleFullSpan(L, mskStrike), '~~gone~~ -> mskStrike');

  L := TMarkdownParser.ParseLine('[text](http://example.com)', State);
  Check(IsSingleFullSpan(L, mskLink), '[text](url) -> single mskLink span covering the whole text');
  Check(L.DisplayText = 'text', '[text](url) shows only the link text');
  Check(L.Spans[0].Target = 'http://example.com', '[text](url) keeps url in Span.Target');

  L := TMarkdownParser.ParseLine('see [Keys](keys.md#top) here', State);
  Check(L.DisplayText = 'see Keys here', 'inline link text replaces the whole [text](url) token');
  Check(HasSpan(L, 5, 4, mskLink) and (L.Spans[0].Target = 'keys.md#top'),
    'inline link span covers "Keys" and carries its target');

  L := TMarkdownParser.ParseLine('**bold** then *italic*', State);
  Check((Length(L.Spans) = 2) and (L.Spans[0].Kind = mskBold) and
    (L.Spans[1].Kind = mskItalic), 'two separate inline spans in one line, in order');

  L := TMarkdownParser.ParseLine('1. **Name** - *used in the repo*', State);
  Check(L.DisplayText = '1. Name - used in the repo',
    'list item strips both **bold** and *italic* markers');

  // Unmatched / malformed markers must not raise or infinite-loop.
  L := TMarkdownParser.ParseLine('a lone * star with no close', State);
  Check(L.DisplayText <> '', 'unterminated "*" does not crash ParseLine');
  L := TMarkdownParser.ParseLine('**unterminated bold', State);
  Check(L.DisplayText = '**unterminated bold', 'unterminated "**" leaves text intact, no exception');

  L := TMarkdownParser.ParseLine('plain paragraph, nothing special.', State);
  Check(Length(L.Spans) = 0, 'plain text line: no spans at all');

  // CommonMark intraword-underscore rule: a single '_' flanked by word
  // characters on both sides (identifiers like WM_COPYDATA) must NOT open
  // an italic span — '*' has no such restriction (kept as-is on purpose).
  L := TMarkdownParser.ParseLine('Handle (WM_COPYDATA) here.', State);
  Check(Length(L.Spans) = 0,
    'a lone intraword "_" in an identifier does not start italic (no matching pair)');

  L := TMarkdownParser.ParseLine('Handle WM_COPYDATA and WM_USER data.', State);
  Check(Length(L.Spans) = 0,
    'two intraword underscores on the same line do NOT pair up into a spurious italic span');

  L := TMarkdownParser.ParseLine('some_snake_case_name here', State);
  Check(Length(L.Spans) = 0, 'multiple intraword underscores in one identifier: still no italic');

  L := TMarkdownParser.ParseLine('This is _actually italic_ text.', State);
  Check(L.DisplayText = 'This is actually italic text.',
    '_italic_ delimiters are stripped like *italic*');
  Check(HasSpan(L, 9, 15, mskItalic),
    '_..._ at real word boundaries (surrounded by spaces) still works as italic');

  L := TMarkdownParser.ParseLine('__bold_word__ stays bold', State);
  Check(HasSpan(L, 1, 9, mskBold),
    '__..__ at word boundaries still works as bold (word-boundary rule applies to __ too)');
end;

{ ---- ParseLine: standalone image lines -------------------------------------- }

procedure TestImages;
var
  State: TMdFenceState;
  L: TMdLine;
begin
  Writeln('-- Standalone image lines --');
  State.InFence := False;

  L := TMarkdownParser.ParseLine('![a cat](images/cat.png)', State);
  Check(L.IsImage, '![alt](path) on its own line is IsImage');
  Check(L.ImageAlt = 'a cat', 'image alt text captured');
  Check(L.ImagePath = 'images/cat.png', 'image path captured');
  Check(L.DisplayText = '[image: a cat]', 'fallback DisplayText uses the alt text');

  L := TMarkdownParser.ParseLine('![](images/cat.png)', State);
  Check(L.IsImage and (L.ImageAlt = ''), 'image with empty alt is still IsImage');
  Check(L.DisplayText = '[image: cat.png]', 'empty-alt fallback falls back to the file name');

  L := TMarkdownParser.ParseLine('Some text ![inline](x.png) more text', State);
  Check(not L.IsImage, 'an image reference NOT alone on its line is not treated as standalone');

  L := TMarkdownParser.ParseLine('not an image at all', State);
  Check(not L.IsImage, 'plain text line is not IsImage');

  L := TMarkdownParser.ParseLine('![[Pasted image 20250312221414.png|wsmall]]', State);
  Check(L.IsImage, 'Obsidian ![[file.png|size]] on its own line is IsImage');
  Check(L.ImagePath = 'Pasted image 20250312221414.png',
    'wiki image drops the |size suffix');
  Check(L.ImageAlt = 'Pasted image 20250312221414',
    'wiki image alt is the file name without extension');

  L := TMarkdownParser.ParseLine('![[cat.png]]', State);
  Check(L.IsImage and (L.ImagePath = 'cat.png'),
    'Obsidian ![[file.png]] without a size suffix is IsImage');

  L := TMarkdownParser.ParseLine('![[OtherNote]]', State);
  Check(not L.IsImage, 'Obsidian note transclusion ![[OtherNote]] is not an image');

  L := TMarkdownParser.ParseLine('see ![[cat.png]] inline', State);
  Check(not L.IsImage, 'wiki image not alone on its line is not standalone');

  L := TMarkdownParser.ParseLine('![Note](<Folder/Attachments/My%20pic (1).png>)', State);
  Check(L.IsImage and (L.ImagePath = 'Folder/Attachments/My%20pic (1).png'),
    '<angle-bracket> destination: brackets stripped, ")" inside kept');

  L := TMarkdownParser.ParseLine('![a](cat.png "The cat")', State);
  Check(L.IsImage and (L.ImagePath = 'cat.png'), 'optional "title" dropped from path');
end;

{ ---- GFM pipe tables -------------------------------------------------------- }

procedure TestTables;
var
  State: TMdFenceState;
  Block: TArray<string>;
  H, S, B, L: TMdLine;
begin
  Writeln('-- GFM pipe tables --');
  State.InFence := False;

  Check(TMarkdownParser.LooksLikePipeTableRow('| a | b |'), 'pipe row is detected');
  Check(TMarkdownParser.LooksLikePipeTableRow('foo | bar'), 'outer pipes are optional');
  Check(TMarkdownParser.IsPipeTableSeparator('| --- | --- |'), 'separator is detected');
  Check(TMarkdownParser.IsPipeTableSeparator('| :--- | ---: | :---: |'),
    'alignment colons still count as a separator');
  Check(not TMarkdownParser.IsPipeTableSeparator('| a | b |'), 'data row is not a separator');
  Check(not TMarkdownParser.IsPipeTableSeparator('| -- | --- |'),
    'a cell with fewer than 3 dashes is not a GFM separator');
  Check(not TMarkdownParser.LooksLikePipeTableRow('plain text'),
    'a line without a pipe is not a table row');
  Check(not TMarkdownParser.LooksLikePipeTableRow('---'),
    'a horizontal rule is not a pipe-table row');

  L := TMarkdownParser.ParseLine('| a | b |', State);
  Check(not L.IsTable, 'ParseLine stays line-oriented; tables need the whole block');

  Block := TArray<string>.Create(
    '| Name | Age |',
    '| ---- | ---: |',
    '| Al | 2 |',
    '| **Bo** | 10 |');
  H := TMarkdownParser.FormatPipeTableLine(Block, 0);
  S := TMarkdownParser.FormatPipeTableLine(Block, 1);
  B := TMarkdownParser.FormatPipeTableLine(Block, 2);
  L := TMarkdownParser.FormatPipeTableLine(Block, 3);
  Check(H.IsTable and S.IsTable and B.IsTable and L.IsTable, 'formatted rows are tables');
  Check(Length(H.DisplayText) = Length(B.DisplayText), 'header and body share one width');
  Check(Length(H.DisplayText) = Length(S.DisplayText), 'separator matches data-row width');
  Check(Pos('Name', H.DisplayText) > 0, 'header keeps cell text');
  Check(Pos('Al', B.DisplayText) > 0, 'body keeps cell text');
  Check(H.DisplayText[1] = chBoxV, 'data row starts with a vertical rule');
  Check(S.DisplayText[1] = chBoxVR, 'separator starts with a left tee');
  Check(S.DisplayText[Length(S.DisplayText)] = chBoxVL, 'separator ends with a right tee');
  Check(Pos(chBoxX, S.DisplayText) > 0, 'separator has a column cross');
  Check(Pos('**', L.DisplayText) = 0, 'bold markers inside a cell are stripped');
  Check(Pos('Bo', L.DisplayText) > 0, 'bold cell text remains');
  Check(B.DisplayText[Length(B.DisplayText) - 2] = '2',
    'right-aligned cell sits against the right rule');

  Block := TArray<string>.Create('| A \| B | C |', '| --- | --- |', '| x | y |');
  H := TMarkdownParser.FormatPipeTableLine(Block, 0);
  Check(Pos('A | B', H.DisplayText) > 0, 'escaped pipe becomes a literal cell pipe');
end;

{ ---- FormatPipeTableLine: width-fit + word-wrap in cells -------------------- }

procedure TestTableWrap;
var
  Block: TArray<string>;
  H, S, B, Wide, Unbounded: TMdLine;
  Starts: TArray<Integer>;
begin
  Writeln('-- GFM pipe tables: fit-to-width + cell word-wrap --');

  // Col 0 ("Name"/"Al", natural width 4) comfortably fits an equal share of
  // 20 columns; col 1 (natural width 19, "This is a long text") does not,
  // so only col 1 should shrink and wrap. Hand-derived expectation: widths
  // come out [4, 9], and "This is a long text" word-wraps at width 9 into
  // "This is " / "a long " / "text" (3 physical rows).
  Block := TArray<string>.Create(
    '| Name | Description |',
    '| --- | --- |',
    '| Al | This is a long text |');
  H := TMarkdownParser.FormatPipeTableLine(Block, 0, 20);
  S := TMarkdownParser.FormatPipeTableLine(Block, 1, 20);
  B := TMarkdownParser.FormatPipeTableLine(Block, 2, 20);

  Check(Length(B.DisplayText) mod 20 = 0,
    'a width-constrained table row is always a whole multiple of the target width');
  Check(Length(B.DisplayText) = 60, 'the wrapped body row needs exactly 3 physical rows of 20 columns');

  Check(B.DisplayText[1] = chBoxV, 'physical row 1 starts with the left rule');
  Check(Copy(B.DisplayText, 3, 4) = 'Al  ', 'col 0 keeps its natural (unshrunk) 4-column width');
  Check(B.DisplayText[8] = chBoxV, 'the column rule sits right after col 0''s unshrunk width');
  Check(Copy(B.DisplayText, 10, 9) = 'This is  ',
    'physical row 1 carries the first word-wrap chunk of col 1, padded to the shrunk 9-column width');
  Check(B.DisplayText[20] = chBoxV, 'physical row 1 ends with the right rule at exactly column 20');

  Check(B.DisplayText[21] = chBoxV, 'physical row 2 starts with the left rule');
  Check(Copy(B.DisplayText, 23, 4) = '    ', 'physical row 2 leaves the already-finished col 0 blank');
  Check(Copy(B.DisplayText, 30, 9) = 'a long   ', 'physical row 2 carries the second word-wrap chunk of col 1');

  Check(B.DisplayText[41] = chBoxV, 'physical row 3 starts with the left rule');
  Check(Copy(B.DisplayText, 43, 4) = '    ', 'physical row 3 also leaves col 0 blank');
  Check(Copy(B.DisplayText, 50, 9) = 'text     ', 'physical row 3 finishes col 1 with its last word-wrap chunk');

  Starts := TMarkdownParser.ComputeHardWrapStarts(B.DisplayText, 20);
  Check((Length(Starts) = 3) and (Starts[0] = 1) and (Starts[1] = 21) and (Starts[2] = 41),
    'the Viewer''s fixed-width hard-wrap slicer lands exactly on the 3 physical-row boundaries built above');

  Check(Length(S.DisplayText) = 20, 'the separator is always exactly one physical row, sized from the shrunk widths');
  Check(Length(H.DisplayText) mod 20 = 0, 'the header row (which also needs to wrap "Description") is a whole multiple of 20 too');

  // A table whose natural width already fits AAvailWidth must render
  // byte-for-byte the same as the unbounded (legacy, AAvailWidth<=0) call —
  // fitting-to-width must never touch a table that didn't need it.
  Wide := TMarkdownParser.FormatPipeTableLine(Block, 2, 100);
  Unbounded := TMarkdownParser.FormatPipeTableLine(Block, 2, 0);
  Check(Wide.DisplayText = Unbounded.DisplayText,
    'a table that already fits the available width is untouched (identical to the unbounded call)');

  // Regression: a table with enough columns that even 1 text column per
  // column plus borders/padding doesn't fit AAvailWidth used to clamp
  // AvailForText up to ColCount anyway, which made the rendered physical
  // row WIDER than AAvailWidth — breaking the "every physical row is
  // exactly AAvailWidth long" invariant ComputeHardWrapStarts's fixed-width
  // slicing depends on, so the Viewer would slice a table's rows at the
  // wrong offsets (garbled/misaligned rendering). 5 columns need at least
  // 3*5+1 + 5 = 21 columns just for 1 char each; AAvailWidth=20 can't do
  // it, so this must fall back to the unbounded natural-width rendering.
  Block := TArray<string>.Create(
    '| A | B | C | D | E |',
    '| --- | --- | --- | --- | --- |',
    '| a | b | c | d | this one cell is much longer than the others by a lot |');
  B := TMarkdownParser.FormatPipeTableLine(Block, 2, 20);
  Unbounded := TMarkdownParser.FormatPipeTableLine(Block, 2, 0);
  Check(B.DisplayText = Unbounded.DisplayText,
    'too many columns to give every one even 1 char at this width falls back to natural widths, not a too-wide shrink');
  S := TMarkdownParser.FormatPipeTableLine(Block, 1, 20);
  Check(Length(S.DisplayText) = Length(Unbounded.DisplayText),
    'the separator falls back consistently with the body row (same natural widths)');
end;

{ ---- FormatPipeTableLine: '<br>' as a forced line break inside a cell ------- }

{ ---- ComputeTableLayout + FormatPipeTableRow = FormatPipeTableLine -------- }

// The Viewer computes a block's layout once and formats each row with it;
// that must give exactly what the whole-block entry point gives, at any
// width (unbounded, shrunk with word-wrap, too narrow to shrink).
procedure TestTableLayoutReuse;
var
  Block: TArray<string>;
  Layout: TMdTableLayout;
  A, B: TMdLine;
  W, I, S: Integer;
  Same: Boolean;
begin
  Writeln('-- GFM pipe tables: layout computed once, reused per row --');
  Block := TArray<string>.Create(
    '| Name | Size | Description |',
    '| :--- | ---: | :---: |',
    '| **a.txt** | 12 | short |',
    '| b.txt | 3456 | a much longer description that has to wrap<br>and a forced break |',
    '| c | | `code` cell |');
  for W in [0, 12, 24, 40, 200] do
  begin
    Layout := TMarkdownParser.ComputeTableLayout(Block, W);
    Same := Layout.ColCount = 3;
    for I := 0 to High(Block) do
    begin
      A := TMarkdownParser.FormatPipeTableLine(Block, I, W);
      B := TMarkdownParser.FormatPipeTableRow(Block[I], I, Layout);
      Same := Same and (A.DisplayText = B.DisplayText) and (A.IsTable = B.IsTable) and
        (Length(A.Spans) = Length(B.Spans));
      if Same then
        for S := 0 to High(A.Spans) do
          Same := Same and (A.Spans[S].StartCol = B.Spans[S].StartCol) and
            (A.Spans[S].Len = B.Spans[S].Len) and (A.Spans[S].Kind = B.Spans[S].Kind);
    end;
    Check(Same, Format('width %d: every row identical to FormatPipeTableLine', [W]));
  end;
  Check(TMarkdownParser.ComputeTableLayout(TArray<string>.Create('| a |'), 0).ColCount = 0,
    'a one-line block has no layout');
  Check(not TMarkdownParser.FormatPipeTableRow('| a |', 0, Default(TMdTableLayout)).IsTable,
    'an empty layout formats nothing');
end;

procedure TestTableBr;
var
  Block: TArray<string>;
  H, B: TMdLine;
begin
  Writeln('-- GFM pipe tables: <br> forces a line break inside a cell --');

  // Unbounded width (no shrink): col 0 ("Name"/"Al") stays natural width 4;
  // col 1's natural width must come from the widest <br>-SEGMENT ("Notes"
  // in the header, 5 chars), not the whole "One<br>Two" cell run together
  // (10 chars) — that's the point of treating <br> as always-multi-line.
  Block := TArray<string>.Create(
    '| Name | Notes |',
    '| --- | --- |',
    '| Al | One<br>Two |');
  H := TMarkdownParser.FormatPipeTableLine(Block, 0, 0);
  B := TMarkdownParser.FormatPipeTableLine(Block, 2, 0);

  Check(Length(B.DisplayText) = 32, '2 physical rows of 16 columns each (col widths 4 and 5)');
  Check(Length(H.DisplayText) = 16, 'header (no <br>) still shares the same one-row width as the body');

  Check(B.DisplayText[1] = chBoxV, 'physical row 1 starts with the left rule');
  Check(Copy(B.DisplayText, 3, 4) = 'Al  ', 'col 0 is unaffected by col 1''s <br>');
  Check(Copy(B.DisplayText, 10, 5) = 'One  ', 'physical row 1 carries the text before <br>');
  Check(B.DisplayText[16] = chBoxV, 'physical row 1 ends with the right rule at column 16');

  Check(B.DisplayText[17] = chBoxV, 'physical row 2 starts with the left rule');
  Check(Copy(B.DisplayText, 19, 4) = '    ', 'physical row 2 leaves the already-finished col 0 blank');
  Check(Copy(B.DisplayText, 26, 5) = 'Two  ', 'physical row 2 carries the text after <br>');

  // <br/> and <br /> must be recognized too, and a <br> at this width that
  // also needs word-wrap must apply both: forced break first, then wrap
  // each resulting segment independently. At width 16 (col 1 shrinks to 8),
  // "one two three" word-wraps to "one two " / "three", and "four five six"
  // to "four " / "five six" — hand-traced via ComputeWrapStarts's own
  // break-selection rule (rightmost break at-or-before the width).
  Block := TArray<string>.Create(
    '| A | B |',
    '| --- | --- |',
    '| x | one two three<br/>four five six |');
  B := TMarkdownParser.FormatPipeTableLine(Block, 2, 16);
  Check(Length(B.DisplayText) mod 16 = 0, 'forced-break + word-wrap combination is still a whole multiple of the target width');
  Check(Pos('one two', B.DisplayText) > 0, 'first <br/> segment''s first word-wrap chunk keeps "one two" together');
  Check(Pos('three', B.DisplayText) > 0, 'first <br/> segment''s remainder ("three") survives on its own row');
  Check(Pos('four', B.DisplayText) > 0, 'second <br/> segment''s first word survives on its own forced-break row');
  Check(Pos('five six', B.DisplayText) > 0, 'second <br/> segment''s word-wrap remainder keeps "five six" together');

  // Inline emphasis must not bleed across a <br> boundary.
  Block := TArray<string>.Create(
    '| A |',
    '| --- |',
    '| **Bold**<br>Plain |');
  B := TMarkdownParser.FormatPipeTableLine(Block, 2, 0);
  Check(Pos('**', B.DisplayText) = 0, 'bold delimiters are still stripped across a <br>-split cell');
  Check(Pos('Bold', B.DisplayText) > 0, 'bold text before <br> survives');
  Check(Pos('Plain', B.DisplayText) > 0, 'plain text after <br> survives');
end;

{ ---- MarkdownResolveImageFile: doc folder then attachments/ ---------------- }

procedure TestImageResolve;
var
  DocDir, AttachDir, DocPath, SamePath, AttachPath, VaultPic, NestedDoc: string;
begin
  Writeln('-- MarkdownResolveImageFile --');
  DocDir := TPath.Combine(GTempDir, 'note-dir');
  AttachDir := TPath.Combine(DocDir, 'attachments');
  TDirectory.CreateDirectory(AttachDir);
  DocPath := TPath.Combine(DocDir, 'note.md');
  TFile.WriteAllText(DocPath, '# x');
  SamePath := TPath.Combine(DocDir, 'same.png');
  TFile.WriteAllText(SamePath, 'x');
  AttachPath := TPath.Combine(AttachDir, 'pasted.png');
  TFile.WriteAllText(AttachPath, 'x');

  Check(SameText(MarkdownResolveImageFile(DocPath, 'same.png'), SamePath),
    'resolves a file sitting next to the document');
  Check(SameText(MarkdownResolveImageFile(DocPath, 'pasted.png'), AttachPath),
    'falls back to attachments\<filename> when the file is not beside the note');
  Check(SameText(MarkdownResolveImageFile(DocPath, 'attachments/pasted.png'), AttachPath),
    'resolves an explicit attachments/ relative path');
  Check(MarkdownResolveImageFile(DocPath, 'missing.png') = '',
    'missing file returns empty (no invented URI)');
  Check(MarkdownResolveImageFile(DocPath, 'https://example.com/x.png') = '',
    'http(s) refs are not resolved');

  // Obsidian: vault-root-relative, percent-encoded, with spaces/Cyrillic.
  VaultPic := TPath.Combine(TPath.Combine(DocDir, 'Attachments'), 'Новая картинка 1.png');
  TFile.WriteAllText(VaultPic, 'x');
  NestedDoc := TPath.Combine(TPath.Combine(DocDir, 'sub'), 'deep.md');
  TDirectory.CreateDirectory(ExtractFileDir(NestedDoc));
  TFile.WriteAllText(NestedDoc, '# y');
  Check(SameText(MarkdownResolveImageFile(DocPath, 'Attachments/Новая%20картинка%201.png'),
    VaultPic), 'percent-encoded path is decoded');
  Check(SameText(MarkdownResolveImageFile(NestedDoc,
    'Attachments/Новая%20картинка%201.png'), VaultPic),
    'path relative to an ancestor (vault root) folder resolves');
  Check(MarkdownResolveImageFile(DocPath, '<bad>|name?.png') = '',
    'invalid path characters return empty instead of raising');
end;

{ ---- TMarkdownParser.ComputeWrapStarts: word-boundary line wrap ------------ }

procedure TestWrapStarts;
var
  Starts: TArray<Integer>;
begin
  Writeln('-- ComputeWrapStarts (word-boundary wrap) --');

  // "one two three" (13 chars) at width 5 breaks after each space, keeping
  // whole words together — not a hard mid-word cut.
  Starts := TMarkdownParser.ComputeWrapStarts('one two three', 5);
  Check((Length(Starts) = 3) and (Starts[0] = 1) and (Starts[1] = 5) and (Starts[2] = 9),
    '"one two three" @5 wraps to rows starting at 1/5/9 (after each space)');

  // A run with no separator anywhere (e.g. a long token/URL) has no word
  // boundary to break at, so it still falls back to a hard cut at the width.
  Starts := TMarkdownParser.ComputeWrapStarts('abcdefghij', 4);
  Check((Length(Starts) = 3) and (Starts[0] = 1) and (Starts[1] = 5) and (Starts[2] = 9),
    'unbroken 10-char run @4 falls back to hard cuts (no space/punctuation to break at)');

  // The key behavior this whole feature is for: a hard character-count cut
  // at width 6 would split "cat dog elephant" into "cat do"/"g elep"/...
  // (mid-word). Word-boundary wrap instead breaks at 1/5/9 — clean "cat "/
  // "dog "/... — only falling back to a mid-word cut for "elephant" itself,
  // since that single word (8 chars) is longer than the width and there's
  // no earlier break point available.
  Starts := TMarkdownParser.ComputeWrapStarts('cat dog elephant', 6);
  Check((Length(Starts) = 4) and (Starts[0] = 1) and (Starts[1] = 5) and
    (Starts[2] = 9) and (Starts[3] = 15),
    '"cat dog elephant" @6 breaks after "cat "/"dog " (word boundaries), not mid-word');

  Starts := TMarkdownParser.ComputeWrapStarts('', 10);
  Check((Length(Starts) = 1) and (Starts[0] = 1), 'empty text still yields one (empty) row');

  Starts := TMarkdownParser.ComputeWrapStarts('abc', 0);
  Check((Length(Starts) = 1) and (Starts[0] = 1), 'AWidth <= 0 degrades to one row, not a crash/loop');

  Starts := TMarkdownParser.ComputeHardWrapStarts('abcdefghij', 4);
  Check((Length(Starts) = 3) and (Starts[0] = 1) and (Starts[1] = 5) and (Starts[2] = 9),
    'hard wrap of 10 chars @4 is 1/5/9 regardless of content');
  Starts := TMarkdownParser.ComputeHardWrapStarts('a b c d e', 4);
  Check((Length(Starts) = 3) and (Starts[0] = 1) and (Starts[1] = 5) and (Starts[2] = 9),
    'hard wrap ignores spaces (unlike ComputeWrapStarts)');
end;

{ ---- TMarkdownPainter: text+spans -> TTerminalRow cells --------------------- }

type
  // Minimal IThemeRenderer stub — every method but ResolveMarkdownStyleColors
  // is a no-op, since DrawLine only ever calls that one. Distinct, made-up
  // colors per TMdSpanKind so a test can tell "which kind painted this cell"
  // back out of the resulting TCharCell.
  TFakeTheme = class(TInterfacedObject, IThemeRenderer)
  public
    function DesktopColor: TAlphaColor;
    procedure DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI);
    procedure DrawWindowFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; AState: TThemeWidgetState);
    procedure DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATitle: string; AState: TThemeWidgetState);
    procedure DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AState: TThemeWidgetState);
    procedure DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
    procedure DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AText: string; AChecked: Boolean; AState: TThemeWidgetState);
    procedure DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState);
    procedure DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ATabNames: TArray<string>; AActiveTabIndex: Integer;
      AState: TThemeWidgetState; AKind: TTabBarKind = tbkPanel);
    procedure DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AItems: TArray<string>; AState: TThemeWidgetState);
    procedure DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const ASegments: TArray<string>; AState: TThemeWidgetState);
    procedure DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
      const AMenuText, AClockText: string; AState: TThemeWidgetState);
    procedure DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
      AActive: Boolean; AState: TThemeWidgetState);
    function UsesDoubleLineForActivePanel: Boolean;
    procedure ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
      const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
    procedure ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
      out AFg, ABg: TAlphaColor);
    procedure ResolveMarkdownStyleColors(AKind: TMdSpanKind;
      out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
    procedure ResolveEditorColors(out AColors: TEditorThemeColors);
  end;

function TFakeTheme.DesktopColor: TAlphaColor; begin Result := 0; end;
procedure TFakeTheme.DrawDesktop(const AGrid: TTerminalGrid; const ABounds: TRectI); begin end;
procedure TFakeTheme.DrawWindowFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawDialogFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATitle: string; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawButton(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawCheckBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawRadioBox(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AText: string; AChecked: Boolean; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawScrollBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  APosition, AMax: Integer; AVertical: Boolean; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawTabBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ATabNames: TArray<string>; AActiveTabIndex: Integer;
  AState: TThemeWidgetState; AKind: TTabBarKind); begin end;
procedure TFakeTheme.DrawToolBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AItems: TArray<string>; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawStatusLine(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const ASegments: TArray<string>; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawMenuBar(const AGrid: TTerminalGrid; const ABounds: TRectI;
  const AMenuText, AClockText: string; AState: TThemeWidgetState); begin end;
procedure TFakeTheme.DrawPanelFrame(const AGrid: TTerminalGrid; const ABounds: TRectI;
  AActive: Boolean; AState: TThemeWidgetState); begin end;
function TFakeTheme.UsesDoubleLineForActivePanel: Boolean; begin Result := False; end;
procedure TFakeTheme.ResolveFileRowColors(AIsDirectory, AIsParent, AIsHidden: Boolean;
  const AFileType: string; ASelected, ACursor, ASideActive: Boolean;
  out AFg, ABg: TAlphaColor); begin AFg := 0; ABg := 0; end;
procedure TFakeTheme.ResolveDialogRowColors(ACursor: Boolean; out AFg, ABg: TAlphaColor);
begin AFg := 0; ABg := 0; end;
procedure TFakeTheme.ResolvePanelChromeColors(APart: TPanelChromePart; AActive: Boolean;
  out AFg, ABg: TAlphaColor); begin AFg := 0; ABg := 0; end;

procedure TFakeTheme.ResolveMarkdownStyleColors(AKind: TMdSpanKind;
  out AFg, ABg: TAlphaColor; out AAttr: TCharCellAttributes);
begin
  // Fg encodes the kind ordinal so a test can recover "which kind painted
  // this cell" from a TCharCell without needing real theme colors.
  AFg := TAlphaColor($FF000000 or (Ord(AKind) and $FF));
  ABg := TAlphaColor($FF101010);
  if AKind in [mskH1, mskH2, mskH3to6, mskBold, mskBoldItalic, mskListMarker, mskTableHeader] then
    AAttr := [ccaBold]
  else
    AAttr := [];
end;

procedure TFakeTheme.ResolveEditorColors(out AColors: TEditorThemeColors);
begin
  // Not exercised by any test below (no TEditorWindow instance here — that
  // needs a live FMX window) — this stub exists only so TFakeTheme still
  // fully implements IThemeRenderer.
  FillChar(AColors, SizeOf(AColors), 0);
end;

// AWidth here is the width passed to DrawLine's AWidth param, painted
// starting at column 1 (AStartCol=1 in every test call below) — the row
// needs AWidth+1 elements (0-based array) so index AWidth itself is valid.
function MakeRow(AWidth: Integer): TTerminalRow;
begin
  SetLength(Result, AWidth + 1);
end;

procedure TestPainter;
var
  State: TMdFenceState;
  L: TMdLine;
  Row: TTerminalRow;
  Theme: IThemeRenderer;
  I: Integer;
  AllHRule: Boolean;
begin
  Writeln('-- TMarkdownPainter --');
  Theme := TFakeTheme.Create;
  State.InFence := False;

  // Horizontal rule renders as an actual ruled line (chBoxH), not the
  // literal '-'/'*'/'_' source characters, across the FULL painted width —
  // including padding past the (short) DisplayText.
  L := TMarkdownParser.ParseLine('---', State);
  Row := MakeRow(12);
  TMarkdownPainter.DrawLine(Row, 1, 12, L, Theme);
  AllHRule := True;
  for I := 1 to 12 do
    if Row[I].CharValue <> chBoxH then
      AllHRule := False;
  Check(AllHRule, 'HR "---" paints chBoxH across the whole width, not literal dashes');

  // Bold: stripped delimiters means the painted characters are "bold", not
  // "**bold**", and they carry ccaBold from the fake theme's rule.
  L := TMarkdownParser.ParseLine('**bold** text', State);
  Row := MakeRow(20);
  TMarkdownPainter.DrawLine(Row, 1, 20, L, Theme);
  Check((Row[1].CharValue = 'b') and (Row[2].CharValue = 'o') and
    (Row[3].CharValue = 'l') and (Row[4].CharValue = 'd'),
    'painted cells 1-4 spell "bold" — no ** delimiters ever reach the grid');
  Check(ccaBold in Row[1].Attributes, 'bold span cells carry ccaBold from the theme');
  Check(not (ccaBold in Row[6].Attributes), 'plain-text cells after the bold word are not bold');

  // Word wrap: the Viewer slices a long line across rows by calling
  // DrawLine once per chunk with an advancing AStartCharIndex; verify two
  // consecutive chunks reassemble the original text.
  L := TMarkdownParser.ParseLine('0123456789ABCDEFGHIJ', State); // 20 chars, plain
  Row := MakeRow(10);
  TMarkdownPainter.DrawLine(Row, 1, 10, L, Theme, 1);
  Check((Row[1].CharValue = '0') and (Row[10].CharValue = '9'),
    'wrap chunk 1 (AStartCharIndex=1) shows the first 10 characters');
  Row := MakeRow(10);
  TMarkdownPainter.DrawLine(Row, 1, 10, L, Theme, 11);
  Check((Row[1].CharValue = 'A') and (Row[10].CharValue = 'J'),
    'wrap chunk 2 (AStartCharIndex=11) shows the next 10 characters');

  // AEndCharIndex: a word-boundary chunk shorter than AWidth must NOT spill
  // the next chunk's characters into this row's remaining cells — they pad
  // with blanks instead. This is exactly what distinguishes word-boundary
  // wrap from the old hard-width slicing (every chunk used to be exactly
  // AWidth long, so there was nothing to spill).
  L := TMarkdownParser.ParseLine('cat dog elephant', State); // "cat " = chars 1..4
  Row := MakeRow(10);
  TMarkdownPainter.DrawLine(Row, 1, 10, L, Theme, 1, 4);
  Check((Row[1].CharValue = 'c') and (Row[2].CharValue = 'a') and
    (Row[3].CharValue = 't') and (Row[4].CharValue = ' '),
    'AEndCharIndex=4 paints exactly "cat "');
  Check((Row[5].CharValue = ' ') and (Row[10].CharValue = ' '),
    'cells past AEndCharIndex are blank padding, not "dog"/"elephant" spilling in');

  // End-of-line inline code must not bleed its style into the padded tail
  // ("- Open `src/main.cpp`" with nothing after the closing backtick).
  L := TMarkdownParser.ParseLine('- Open `src/main.cpp`', State);
  Row := MakeRow(40);
  TMarkdownPainter.DrawLine(Row, 1, 40, L, Theme);
  Check((Row[Length(L.DisplayText)].FgColor and $FF) = Cardinal(Ord(mskInlineCode)),
    'the closing backtick cell is still mskInlineCode');
  Check((Row[Length(L.DisplayText) + 1].FgColor and $FF) = Cardinal(Ord(mskText)),
    'padding after a line that ends on inline code is mskText, not code bg');

  // Headings still shade the rest of the row (whole-line kind).
  L := TMarkdownParser.ParseLine('# Title', State);
  Row := MakeRow(20);
  TMarkdownPainter.DrawLine(Row, 1, 20, L, Theme);
  Check((Row[20].FgColor and $FF) = Cardinal(Ord(mskH1)),
    'heading padding still uses mskH1 out to the painted width');
end;

{ ---- TMarkdownFenceIndex: lazy incremental fence-state recovery ------------ }

/// <summary>Builds a temp .md file: lines 0..9 plain, line 10 opens a fence,
/// lines 11..(AFenceLen+9) are fence content, next line closes it, then a
/// few more plain lines — long enough to cross several checkpoint strides.</summary>
function BuildFenceFixture(const APath: string; AFenceLen: Integer): Integer;
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    SL.LineBreak := #10;
    for I := 0 to 9 do
      SL.Add(Format('plain line %d', [I]));
    SL.Add('```');                          // line 10: fence open
    for I := 0 to AFenceLen - 1 do
      SL.Add(Format('code line %d # not a heading', [I])); // lines 11..
    SL.Add('```');                          // fence close
    for I := 0 to 9 do
      SL.Add(Format('plain again %d', [I]));
    SL.SaveToFile(APath, TEncoding.UTF8);
    Result := SL.Count;
  finally
    SL.Free;
  end;
end;

function WaitDoc(ADoc: TEditorDoc): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while ADoc.Loading do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > 60000 then
      Exit(False);
  end;
  CheckSynchronize(0);
  Result := True;
end;

function OpenDoc(const APath: string): TEditorDoc;
begin
  Result := TEditorDoc.Create;
  Result.OpenAsync(PathToFileUri(APath));
  if not WaitDoc(Result) then
  begin
    Writeln('  [FAIL] timeout opening ', APath);
    Inc(GFailures);
  end;
end;

procedure TestFenceIndex;
var
  Path: string;
  Doc: TEditorDoc;
  Idx: TMarkdownFenceIndex;
  FenceLen, CloseLine, AfterLine: Integer;
begin
  Writeln('-- TMarkdownFenceIndex --');
  FenceLen := 1200; // crosses several 500-line checkpoints
  Path := TPath.Combine(GTempDir, 'fence_fixture.md');
  BuildFenceFixture(Path, FenceLen);
  CloseLine := 10 + FenceLen + 1; // 0-based index of the closing ``` line
  AfterLine := CloseLine + 1;

  Doc := OpenDoc(Path);
  Idx := TMarkdownFenceIndex.Create;
  try
    Check(not Idx.FenceStateBefore(Doc, 0).InFence, 'line 0: not in fence');
    Check(not Idx.FenceStateBefore(Doc, 10).InFence, 'line 10 (fence-open line itself): state BEFORE it is not-in-fence');
    Check(Idx.FenceStateBefore(Doc, 11).InFence, 'line 11 (first content line): in fence');
    Check(Idx.FenceStateBefore(Doc, CloseLine - 1).InFence, 'line just before the close: still in fence');
    Check(Idx.FenceStateBefore(Doc, CloseLine).InFence, 'the closing ``` line itself: state BEFORE it is still in-fence');
    Check(not Idx.FenceStateBefore(Doc, AfterLine).InFence, 'line right after close: not in fence');

    // Jump far forward (forces a long scan + checkpoint creation), then jump
    // back near the start (checkpoints beyond the target are unusable, must
    // fall back to scanning from 0 — still has to give the right answer),
    // then forward again past a checkpoint recorded on the very first scan.
    Check(not Idx.FenceStateBefore(Doc, AfterLine + 5).InFence,
      'far-forward jump lands on the correct (not-in-fence) state');
    Check(not Idx.FenceStateBefore(Doc, 5).InFence,
      'jumping back near the start after a big forward scan is still correct');
    Check(Idx.FenceStateBefore(Doc, CloseLine - 1).InFence,
      'jumping forward again past an earlier checkpoint reuses it correctly');

    Idx.Reset;
    Check(Idx.FenceStateBefore(Doc, 11).InFence, 'after Reset, state is recomputed from scratch and still correct');
  finally
    Idx.Free;
    Doc.Free;
  end;
end;

begin
  try
    GTempDir := TPath.Combine(TPath.GetTempPath, 'mtn2_test_md_' + IntToStr(GetCurrentProcessId));
    if TDirectory.Exists(GTempDir) then
      TDirectory.Delete(GTempDir, True);
    TDirectory.CreateDirectory(GTempDir);
    Writeln('=== TestMarkdownParser (Stage 25) ===');
    Writeln('temp: ', GTempDir);
    Writeln;

    TestHeadings;
    TestFences;
    TestBlockConstructs;
    TestInline;
    TestImages;
    TestImageResolve;
    TestTables;
    TestTableWrap;
    TestTableBr;
    TestTableLayoutReuse;
    TestWrapStarts;
    TestPainter;
    TestFenceIndex;

    Writeln;
    try
      if TDirectory.Exists(GTempDir) then
        TDirectory.Delete(GTempDir, True);
    except
      // Cleanup is best-effort; a locked temp file must not fail the run.
    end;

    if GFailures = 0 then
      Writeln('All MarkdownParser tests PASSED')
    else
    begin
      Writeln(Format('FAILED: %d check(s)', [GFailures]));
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
