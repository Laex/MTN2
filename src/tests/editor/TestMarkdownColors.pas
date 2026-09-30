unit TestMarkdownColors;

{ uMarkdownColors: the color-set JSON round trip and the import of an Obsidian
  theme's CSS (variable lookup, var() fallbacks, hex / rgb / hsl values, calc()
  in hsl, alpha flattening, dark and light palettes). Source is pure ASCII. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMarkdownColors = class
  public
    [Test] procedure TestJsonRoundTrip;
    [Test] procedure TestJsonSkipsBadEntries;
    [Test] procedure TestStyleChoicesAndJson;
    [Test] procedure TestObsidianHeadingsAndText;
    [Test] procedure TestObsidianPaletteSelection;
    [Test] procedure TestObsidianVarFallbackAndChain;
    [Test] procedure TestObsidianHslCalcAndAccent;
    [Test] procedure TestObsidianAlphaFlattened;
    [Test] procedure TestObsidianIgnoresOtherSelectors;
    [Test] procedure TestObsidianNoColors;
    [Test] procedure TestObsidianStyles;
    [Test] procedure TestDialogHasFieldPerKind;
  end;

implementation

uses
  System.SysUtils, System.UITypes, uTerminalTypes, uThemeTypes, uMarkdownColors, uDialogTypes;

function Rgb(R, G, B: Cardinal): TAlphaColor;
begin
  Result := TAlphaColor($FF000000 or (R shl 16) or (G shl 8) or B);
end;

procedure TTestMarkdownColors.TestJsonRoundTrip;
var
  A, B: TMdColorSet;
begin
  MdColorSetClear(A);
  A[mskH1].HasFg := True;
  A[mskH1].Fg := Rgb($12, $34, $56);
  A[mskInlineCode].HasFg := True;
  A[mskInlineCode].Fg := Rgb($FF, $00, $80);
  A[mskInlineCode].HasBg := True;
  A[mskInlineCode].Bg := Rgb($10, $20, $30);
  Assert.IsTrue(MdColorSetFromJson(MdColorSetToJson(A), B), 'the JSON parses back');
  Assert.IsTrue(B[mskH1].HasFg and (B[mskH1].Fg = A[mskH1].Fg) and not B[mskH1].HasBg,
    'a foreground-only entry keeps its channel');
  Assert.IsTrue(B[mskInlineCode].HasFg and B[mskInlineCode].HasBg and
    (B[mskInlineCode].Fg = A[mskInlineCode].Fg) and (B[mskInlineCode].Bg = A[mskInlineCode].Bg),
    'both channels survive');
  Assert.IsFalse(B[mskLink].HasFg or B[mskLink].HasBg, 'an unset kind stays unset');
end;

procedure TTestMarkdownColors.TestJsonSkipsBadEntries;
var
  S: TMdColorSet;
begin
  Assert.IsFalse(MdColorSetFromJson('not json', S), 'garbage is rejected');
  Assert.IsFalse(MdColorSetFromJson('[1,2]', S), 'a non-object is rejected');
  Assert.IsTrue(MdColorSetFromJson('{"styles":{"h1":{"fg":"zzz"},"bold":{"fg":"#00FF00"},"nope":{"fg":"#000000"}}}', S),
    'an object parses');
  Assert.IsFalse(S[mskH1].HasFg, 'an unparsable color is skipped');
  Assert.IsTrue(S[mskBold].HasFg and (S[mskBold].Fg = Rgb(0, $FF, 0)), 'a valid neighbour is kept');
end;

procedure TTestMarkdownColors.TestStyleChoicesAndJson;
var
  A, B: TMdColorSet;
  I: Integer;
  P: TMdColorPair;
begin
  Assert.AreEqual(0, MdStyleChoiceOf(Default(TMdColorPair)), 'no style is the theme choice');
  for I := 0 to MdStyleChoiceCount - 1 do
  begin
    P := Default(TMdColorPair);
    MdStyleChoiceApply(P, I);
    Assert.AreEqual(I, MdStyleChoiceOf(P), 'choice ' + MdStyleChoiceKey(I) + ' maps back');
    Assert.AreEqual(I > 0, P.HasStyle, 'only the theme choice leaves the style unset');
  end;
  P := Default(TMdColorPair);
  MdStyleChoiceApply(P, 1);
  Assert.IsTrue(P.HasStyle and (P.Style = []), 'plain is an empty but set style');
  MdStyleChoiceApply(P, 4);
  Assert.IsTrue(P.Style = [ccaBold, ccaItalic], 'bold italic');

  MdColorSetClear(A);
  MdStyleChoiceApply(A[mskQuote], 3);
  MdStyleChoiceApply(A[mskLink], 1);
  Assert.IsTrue(MdColorSetFromJson(MdColorSetToJson(A), B), 'the JSON parses back');
  Assert.IsTrue(B[mskQuote].HasStyle and (B[mskQuote].Style = [ccaItalic]), 'italic survives');
  Assert.IsTrue(B[mskLink].HasStyle and (B[mskLink].Style = []), 'plain survives');
  Assert.IsFalse(B[mskBold].HasStyle, 'an unset style stays unset');
end;

procedure TTestMarkdownColors.TestObsidianHeadingsAndText;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --text-normal: #c6c6c6; --h1-color: #ff0000; --h2-color: rgb(0, 255, 0);' +
    ' --h3-color: #00f; --text-muted: #8a8a8a; }', True, S), 'the palette is found');
  Assert.IsTrue(S[mskText].HasFg and (S[mskText].Fg = Rgb($C6, $C6, $C6)), 'text color');
  Assert.IsTrue(S[mskH1].Fg = Rgb($FF, 0, 0), '#rrggbb');
  Assert.IsTrue(S[mskH2].Fg = Rgb(0, $FF, 0), 'rgb()');
  Assert.IsTrue(S[mskH3to6].Fg = Rgb(0, 0, $FF), '#rgb shorthand');
  Assert.IsTrue(S[mskQuote].Fg = Rgb($8A, $8A, $8A), 'quote falls back to the muted text color');
  Assert.IsFalse(S[mskText].HasBg, 'plain text gets no background');
end;

procedure TTestMarkdownColors.TestObsidianPaletteSelection;
const
  Css = '.theme-dark { --h1-color: #111111; } .theme-light { --h1-color: #eeeeee; }';
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(Css, True, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($11, $11, $11), 'dark palette');
  Assert.IsTrue(ParseObsidianThemeCss(Css, False, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($EE, $EE, $EE), 'light palette');
  Assert.IsTrue(ParseObsidianThemeCss(
    'body { --h1-color: #222222; } .theme-dark { --h1-color: #333333; } body.theme-dark { --h1-color: #444444; }',
    True, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($44, $44, $44), 'body.theme-dark wins over .theme-dark and body');
  Assert.IsTrue(ParseObsidianThemeCss(
    'body { --h1-color: #222222; } .theme-dark { --h2-color: #333333; }', True, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($22, $22, $22), 'a base variable is used when the palette lacks it');
end;

procedure TTestMarkdownColors.TestObsidianVarFallbackAndChain;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --a: var(--missing, #0a0b0c); --h1-color: var(--a); --h2-color: var(--print-h2, var(--b));' +
    ' --b: #102030; --h3-color: var(--nothing); --link-color: var(--text-accent); --text-accent: #abcdef; }',
    True, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($0A, $0B, $0C), 'a fallback is used for a missing variable');
  Assert.IsTrue(S[mskH2].Fg = Rgb($10, $20, $30), 'nested var() and fallback');
  Assert.IsFalse(S[mskH3to6].HasFg, 'a variable with no value and no fallback stays unset');
  Assert.IsTrue(S[mskLink].Fg = Rgb($AB, $CD, $EF), 'a variable chain resolves');
end;

procedure TTestMarkdownColors.TestObsidianHslCalcAndAccent;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --h1-color: hsl(0, 100%, 50%); --h2-color: hsl(120 100% 25%);' +
    ' --accent-h: 240; --accent-s: 100%; --accent-l: 50%; --link-color: hsl(var(--accent-h), var(--accent-s), calc(var(--accent-l) * 1));' +
    ' --h3-color: hsl(calc(60 * 2), 100%, 50%); }', True, S));
  Assert.IsTrue(S[mskH1].Fg = Rgb($FF, 0, 0), 'hsl red');
  Assert.IsTrue(S[mskH2].Fg = Rgb(0, $80, 0), 'space separated hsl');
  Assert.IsTrue(S[mskLink].Fg = Rgb(0, 0, $FF), 'hsl from variables with calc()');
  Assert.IsTrue(S[mskH3to6].Fg = Rgb(0, $FF, 0), 'calc() as a hue');
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --accent-h: 240; --accent-s: 100%; --accent-l: 50%; --text-accent: var(--color-accent); }',
    True, S));
  Assert.IsTrue(S[mskLink].Fg = Rgb(0, 0, $FF), 'the accent is derived from its HSL parts');
end;

procedure TTestMarkdownColors.TestObsidianAlphaFlattened;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --background-primary: #000000; --code-normal: #ffffff; --code-background: #ffffff80; }',
    True, S));
  Assert.IsTrue(S[mskCodeBlock].HasBg, 'the code background is found');
  Assert.IsTrue(TAlphaColorRec(S[mskCodeBlock].Bg).A = $FF, 'the result is opaque');
  Assert.IsTrue(Abs(Integer(TAlphaColorRec(S[mskCodeBlock].Bg).R) - $80) <= 1,
    'half transparent white over black is mid gray');
end;

procedure TTestMarkdownColors.TestObsidianIgnoresOtherSelectors;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '/* .theme-dark { --h1-color: #ff0000; } */ @media (min-width: 1px) { .theme-dark { --h1-color: #ff0000; } }' +
    ' .other .theme-dark { --h1-color: #00ff00; } body.some-scheme.theme-dark { --h1-color: #0000ff; }' +
    ' .x, .theme-dark { --h2-color: #123456; content: "}"; --h3-color: #654321; }', True, S));
  Assert.IsFalse(S[mskH1].HasFg, 'comments, at-rules and other selectors do not count');
  Assert.IsTrue(S[mskH2].Fg = Rgb($12, $34, $56), 'a selector list containing .theme-dark counts');
  Assert.IsTrue(S[mskH3to6].Fg = Rgb($65, $43, $21), 'parsing continues after a quoted brace');
end;

procedure TTestMarkdownColors.TestObsidianStyles;
var
  S: TMdColorSet;
begin
  Assert.IsTrue(ParseObsidianThemeCss(
    '.theme-dark { --h1-weight: 700; --h2-weight: 400; --h2-style: italic; --bold-weight: var(--w); --w: bolder;' +
    ' --link-decoration: underline; --blockquote-font-style: italic; --table-header-weight: 600; --text-normal: #ffffff; }',
    True, S));
  Assert.IsTrue(S[mskH1].HasStyle and (S[mskH1].Style = [ccaBold]), 'weight 700 is bold');
  Assert.IsTrue(S[mskH2].HasStyle and (S[mskH2].Style = [ccaItalic]), 'weight 400 is not bold, style italic is');
  Assert.IsFalse(S[mskH3to6].HasStyle, 'a kind with no weight or style variable keeps the theme');
  Assert.IsTrue(S[mskBold].HasStyle and (S[mskBold].Style = [ccaBold]), 'a var() weight resolves');
  Assert.IsTrue(S[mskLink].HasStyle and (S[mskLink].Style = [ccaUnderline]), 'link decoration');
  Assert.IsTrue(S[mskQuote].HasStyle and (S[mskQuote].Style = [ccaItalic]), 'blockquote style');
  Assert.IsTrue(S[mskTableHeader].HasStyle and (S[mskTableHeader].Style = [ccaBold]), 'table header weight');
  Assert.IsTrue(ParseObsidianThemeCss('.theme-dark { --link-decoration: none; --text-normal: #fff; }', True, S));
  Assert.IsTrue(S[mskLink].HasStyle and (S[mskLink].Style = []), 'decoration none is plain');
  Assert.AreEqual('bold+italic', MdStyleChoiceAttrs(4), 'attribute key of bold italic');
  Assert.AreEqual('', MdStyleChoiceAttrs(0), 'the theme choice has no attributes');
  Assert.AreEqual('none', MdStyleChoiceAttrs(1), 'plain is marked none');
end;

procedure TTestMarkdownColors.TestObsidianNoColors;
var
  S: TMdColorSet;
  Failure: TMdImportError;
begin
  Assert.IsFalse(ParseObsidianThemeCss('p { color: red; }', True, S), 'no palette, no colors');
  Assert.IsFalse(LoadObsidianTheme('', True, S, Failure), 'empty path');
  Assert.IsTrue(Failure = mieNoPath);
  Assert.IsFalse(LoadObsidianTheme('Z:\no\such\theme.css', True, S, Failure), 'missing file');
  Assert.IsTrue(Failure = mieNotFound);
end;

procedure TTestMarkdownColors.TestDialogHasFieldPerKind;
var
  Decl: TDialogDeclaration;
  Kind: TMdSpanKind;

  function HasControl(const AId: string): Boolean;
  var
    C: TDialogControl;
  begin
    for C in Decl.Controls do
      if SameText(C.Id, AId) then
        Exit(True);
    Result := False;
  end;

begin
  Decl := BuildMarkdownColorsDialog;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    Assert.IsTrue(HasControl('md_' + MdSpanKindKey(Kind) + '_fg'),
      'foreground input for ' + MdSpanKindKey(Kind));
    Assert.IsTrue(HasControl('md_' + MdSpanKindKey(Kind) + '_bg'),
      'background input for ' + MdSpanKindKey(Kind));
  end;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    if not (Kind in [mskHRule, mskTableBorder]) then
      Assert.IsTrue(HasControl('md_' + MdSpanKindKey(Kind) + '_style'),
        'style list for ' + MdSpanKindKey(Kind));
  Decl := BuildMarkdownImportDialog('C:\x\theme.css', 1);
  Assert.IsTrue(HasControl('obs_path') and HasControl('obs_palette'), 'import dialog fields');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMarkdownColors);

end.
