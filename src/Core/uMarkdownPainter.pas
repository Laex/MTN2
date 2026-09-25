unit uMarkdownPainter;

{ Stage 25: paints one parsed TMdLine (uMarkdownParser) into a TTerminalRow.
  This is the "text + spans -> colored cells" primitive that didn't exist
  anywhere in the codebase before Markdown Viewer — every other renderer
  (TEditorPainter.DrawTextLine, panel row drawing) paints a whole line with
  one uniform Fg/Bg. Mirrors TEditorPainter's shape (class, static
  procedure, writes directly into a var TTerminalRow) so it slots into
  TEditorWindow.DrawContent next to DrawHexContent/DrawTextLine. }

interface

uses
  System.UITypes, System.Math,
  uTerminalTypes, uThemeTypes, uMarkdownParser;

type
  TMarkdownPainter = class
  public
    /// <summary>Paints ALine.DisplayText[AStartCharIndex..AEndCharIndex]
    /// (1-based, inclusive) into AWidth cells from AStartCol — the same
    /// "AStartCharIndex" slicing convention TEditorPainter.DrawTextLine uses
    /// for horizontal scroll, plus an explicit end so a word-wrapped chunk
    /// shorter than AWidth (the common case once wrapping breaks at a space
    /// instead of always at the exact column boundary) pads with blank
    /// cells instead of spilling into the next chunk's text. Default
    /// AEndCharIndex (MaxInt) means "to the end of DisplayText", for callers
    /// that don't slice at all. uEditorWindow.DrawMarkdownContent calls this
    /// once per TMarkdownParser.ComputeWrapStarts chunk.</summary>
    class procedure DrawLine(var ARow: TTerminalRow; AStartCol, AWidth: Integer;
      const ALine: TMdLine; const ATheme: IThemeRenderer; AStartCharIndex: Integer = 1;
      AEndCharIndex: Integer = MaxInt);
  end;

implementation

type
  TResolvedMdStyle = record
    Fg, Bg: TAlphaColor;
    Attr: TCharCellAttributes;
  end;

class procedure TMarkdownPainter.DrawLine(var ARow: TTerminalRow; AStartCol, AWidth: Integer;
  const ALine: TMdLine; const ATheme: IThemeRenderer; AStartCharIndex: Integer;
  AEndCharIndex: Integer);
var
  Styles: array[TMdSpanKind] of TResolvedMdStyle;
  Kinds: TArray<TMdSpanKind>;
  Kind, TrailKind: TMdSpanKind;
  Span: TMdSpan;
  I, ColIdx, CharIdx, N, LastChunkChar: Integer;
  St: TResolvedMdStyle;
  Ch: Char;
begin
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    ATheme.ResolveMarkdownStyleColors(Kind, Styles[Kind].Fg, Styles[Kind].Bg, Styles[Kind].Attr);
  // Links are underlined in every theme (the renderer draws ccaUnderline).
  Include(Styles[mskLink].Attr, ccaUnderline);

  N := Length(ALine.DisplayText);
  SetLength(Kinds, N);
  for I := 0 to N - 1 do
    Kinds[I] := mskText;
  // Spans are non-overlapping by construction (uMarkdownParser); a later
  // span in the array is never expected to cover an earlier one, but the
  // straightforward "overwrite" here is harmless either way.
  for I := 0 to High(ALine.Spans) do
  begin
    Span := ALine.Spans[I];
    for CharIdx := Span.StartCol to Span.StartCol + Span.Len - 1 do
      if (CharIdx >= 1) and (CharIdx <= N) then
        Kinds[CharIdx - 1] := Span.Kind;
  end;

  // Padding past this chunk's last glyph (wrap cutoff or end of DisplayText)
  // fills the rest of the row. Only whole-line kinds (heading / fence /
  // HR) keep their color out to the edge — that's what makes a heading or
  // code block look like a bar. Inline spans (mskInlineCode, bold, link,
  // …) must NOT: a list item that ends with `src/main.cpp` would otherwise
  // paint the code background across the empty tail of the row.
  LastChunkChar := Min(N, AEndCharIndex);
  if LastChunkChar > 0 then
    TrailKind := Kinds[LastChunkChar - 1]
  else
    TrailKind := mskText;
  if not (TrailKind in [mskH1, mskH2, mskH3to6, mskCodeBlock, mskHRule]) then
    TrailKind := mskText;

  ColIdx := AStartCol;
  CharIdx := AStartCharIndex;
  while (ColIdx < AStartCol + AWidth) and (ColIdx <= High(ARow)) do
  begin
    if (CharIdx >= 1) and (CharIdx <= N) and (CharIdx <= AEndCharIndex) then
    begin
      Kind := Kinds[CharIdx - 1];
      St := Styles[Kind];
      // A horizontal rule ('---'/'***'/'___') renders as an actual ruled
      // line, not the literal source characters — the whole span always
      // covers the full line (see uMarkdownParser.ParseLine), so every
      // cell in it gets the box-drawing glyph regardless of what character
      // sits at that column in DisplayText.
      if Kind = mskHRule then
        Ch := chBoxH
      else
        Ch := ALine.DisplayText[CharIdx];
    end
    else
    begin
      St := Styles[TrailKind];
      if TrailKind = mskHRule then
        Ch := chBoxH
      else
        Ch := ' ';
    end;
    ARow[ColIdx].CharValue := Ch;
    ARow[ColIdx].FgColor := St.Fg;
    ARow[ColIdx].BgColor := St.Bg;
    ARow[ColIdx].Attributes := St.Attr;
    Inc(ColIdx);
    Inc(CharIdx);
  end;
end;

end.
