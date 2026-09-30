unit uMarkdownColors;

{ User colors for the Markdown Viewer. Every span kind (heading, bold, code,
  link, ...) can carry a foreground and a background that replace the ones
  the active theme picks (TMarkdownPainter applies them on top of
  IThemeRenderer.ResolveMarkdownStyleColors); an unset channel keeps the
  theme's color. The "text" kind is the document itself: its background
  fills the whole Markdown view and every element without a background of its
  own follows it. Stored in <config>\markdown-colors.json; a missing or
  corrupt file means nothing is overridden.

  The colors can be imported from an Obsidian theme (theme.css): the dark or
  light palette is read from its CSS custom properties (--h1-color,
  --text-normal, --code-normal, --bold-weight, --link-decoration, ...), var() references with fallbacks,
  #hex / rgb() / hsl() values and calc() in hsl() arguments are resolved;
  a value that cannot be resolved leaves that channel unset. }

interface

uses
  System.UITypes,
  uTerminalTypes, uThemeTypes;

type
  TMdImportError = (mieNone, mieNoPath, mieNotFound, mieUnreadable, mieNoColors);

  TMdColorPair = record
    HasFg, HasBg: Boolean;
    Fg, Bg: TAlphaColor;
    /// <summary>A set style replaces the theme's text attributes (bold,
    /// italic, underline, strikethrough); an empty set is plain text.</summary>
    HasStyle: Boolean;
    Style: TCharCellAttributes;
  end;

  TMdColorSet = array[TMdSpanKind] of TMdColorPair;

/// <summary>Key of a span kind in markdown-colors.json ("h1", "inlineCode").</summary>
function MdSpanKindKey(AKind: TMdSpanKind): string;
procedure MdColorSetClear(out ASet: TMdColorSet);
function MdColorSetToJson(const ASet: TMdColorSet): string;
/// <summary>False when AJson is not a JSON object; unknown keys and
/// unparsable colors are skipped.</summary>
function MdColorSetFromJson(const AJson: string; out ASet: TMdColorSet): Boolean;

function DefaultMarkdownColorsFilePath: string;
/// <summary>Process-wide colors, loaded from the default file on first use.</summary>
function GlobalMarkdownColors: TMdColorSet;
/// <summary>Replaces the global colors and writes the default file.</summary>
function SetGlobalMarkdownColors(const ASet: TMdColorSet): Boolean;
/// <summary>The user's colors for AKind (HasFg / HasBg say which are set).</summary>
function MarkdownColorOverride(AKind: TMdSpanKind): TMdColorPair;
/// <summary>Replaces AFg / ABg with the user's colors for AKind, where set.</summary>
procedure ApplyMarkdownColorOverride(AKind: TMdSpanKind; var AFg, ABg: TAlphaColor);
/// <summary>Replaces AAttr with the user's style for AKind, where set.</summary>
procedure ApplyMarkdownStyleOverride(AKind: TMdSpanKind; var AAttr: TCharCellAttributes);

/// <summary>The text styles the dialog offers, index 0 = the theme's own
/// (nothing overridden).</summary>
function MdStyleChoiceCount: Integer;
/// <summary>Index into the choices for what AColors holds (0 when no style is set).</summary>
function MdStyleChoiceOf(const APair: TMdColorPair): Integer;
procedure MdStyleChoiceApply(var APair: TMdColorPair; AChoice: Integer);
/// <summary>Key of a choice in the dialog's translation table ("bold", "boldItalic").</summary>
function MdStyleChoiceKey(AChoice: Integer): string;
/// <summary>The choice's attributes as "bold+italic" (the dialog sample draws
/// with them): '' for the theme's own, "none" for plain.</summary>
function MdStyleChoiceAttrs(AChoice: Integer): string;

/// <summary>Reads the dark (ADark) or light palette of an Obsidian theme's
/// CSS into ASet: colors, and the text styles its weight / style / decoration
/// variables give headings, bold, links, quotes and table headers. False when none of the span kinds got a color.</summary>
function ParseObsidianThemeCss(const ACss: string; ADark: Boolean;
  out ASet: TMdColorSet): Boolean;
/// <summary>ParseObsidianThemeCss on a file; AError says why it failed.</summary>
function LoadObsidianTheme(const APath: string; ADark: Boolean;
  out ASet: TMdColorSet; out AError: TMdImportError): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  System.Generics.Collections, uConfigLocation, uColorCoding;

const
  cSpanKindKeys: array[TMdSpanKind] of string = (
    'text', 'h1', 'h2', 'h3to6', 'bold', 'italic', 'boldItalic', 'strike',
    'inlineCode', 'codeBlock', 'quote', 'listMarker', 'hrule', 'link',
    'imageMarker', 'tableBorder', 'tableHeader');

function MdSpanKindKey(AKind: TMdSpanKind): string;
begin
  Result := cSpanKindKeys[AKind];
end;

const
  cStyleChoiceKeys: array[0..9] of string = ('theme', 'normal', 'bold', 'italic',
    'boldItalic', 'underline', 'strike', 'boldUnderline', 'italicUnderline',
    'boldStrike');

function StyleChoiceSet(AChoice: Integer): TCharCellAttributes;
begin
  case AChoice of
    2: Result := [ccaBold];
    3: Result := [ccaItalic];
    4: Result := [ccaBold, ccaItalic];
    5: Result := [ccaUnderline];
    6: Result := [ccaStrike];
    7: Result := [ccaBold, ccaUnderline];
    8: Result := [ccaItalic, ccaUnderline];
    9: Result := [ccaBold, ccaStrike];
  else
    Result := [];
  end;
end;

function MdStyleChoiceCount: Integer;
begin
  Result := Length(cStyleChoiceKeys);
end;

function MdStyleChoiceAttrs(AChoice: Integer): string;
var
  Attrs: TCharCellAttributes;

  procedure Add(const AName: string);
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + AName;
  end;

begin
  Result := '';
  if AChoice <= 0 then
    Exit;
  Attrs := StyleChoiceSet(AChoice);
  if Attrs = [] then
    Exit('none');
  if ccaBold in Attrs then
    Add('bold');
  if ccaItalic in Attrs then
    Add('italic');
  if ccaUnderline in Attrs then
    Add('underline');
  if ccaStrike in Attrs then
    Add('strike');
end;

function MdStyleChoiceKey(AChoice: Integer): string;
begin
  Result := cStyleChoiceKeys[EnsureRange(AChoice, 0, High(cStyleChoiceKeys))];
end;

function MdStyleChoiceOf(const APair: TMdColorPair): Integer;
var
  I: Integer;
begin
  Result := 0;
  if not APair.HasStyle then
    Exit;
  for I := 1 to High(cStyleChoiceKeys) do
    if StyleChoiceSet(I) = APair.Style then
      Exit(I);
end;

procedure MdStyleChoiceApply(var APair: TMdColorPair; AChoice: Integer);
begin
  APair.HasStyle := AChoice > 0;
  if APair.HasStyle then
    APair.Style := StyleChoiceSet(AChoice)
  else
    APair.Style := [];
end;

function StyleToJson(const AStyle: TCharCellAttributes): TJSONArray;
begin
  Result := TJSONArray.Create;
  if ccaBold in AStyle then
    Result.Add('bold');
  if ccaItalic in AStyle then
    Result.Add('italic');
  if ccaUnderline in AStyle then
    Result.Add('underline');
  if ccaStrike in AStyle then
    Result.Add('strike');
end;

function StyleFromJson(AArr: TJSONArray): TCharCellAttributes;
var
  I: Integer;
  Name: string;
begin
  Result := [];
  for I := 0 to AArr.Count - 1 do
  begin
    Name := LowerCase(AArr.Items[I].Value);
    if Name = 'bold' then
      Include(Result, ccaBold)
    else if Name = 'italic' then
      Include(Result, ccaItalic)
    else if Name = 'underline' then
      Include(Result, ccaUnderline)
    else if Name = 'strike' then
      Include(Result, ccaStrike);
  end;
end;

procedure MdColorSetClear(out ASet: TMdColorSet);
begin
  ASet := Default(TMdColorSet);
end;

function MdColorSetToJson(const ASet: TMdColorSet): string;
var
  Root, Styles, Item: TJSONObject;
  Kind: TMdSpanKind;
begin
  Root := TJSONObject.Create;
  try
    Styles := TJSONObject.Create;
    Root.AddPair('styles', Styles);
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      if not (ASet[Kind].HasFg or ASet[Kind].HasBg or ASet[Kind].HasStyle) then
        Continue;
      Item := TJSONObject.Create;
      if ASet[Kind].HasFg then
        Item.AddPair('fg', ColorToHex(ASet[Kind].Fg));
      if ASet[Kind].HasBg then
        Item.AddPair('bg', ColorToHex(ASet[Kind].Bg));
      if ASet[Kind].HasStyle then
        Item.AddPair('style', StyleToJson(ASet[Kind].Style));
      Styles.AddPair(cSpanKindKeys[Kind], Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function MdColorSetFromJson(const AJson: string; out ASet: TMdColorSet): Boolean;
var
  RootVal, StylesVal, ItemVal, StyleVal: TJSONValue;
  Kind: TMdSpanKind;
  Hex: string;
begin
  MdColorSetClear(ASet);
  Result := False;
  try
    RootVal := TJSONObject.ParseJSONValue(AJson);
  except
    Exit;
  end;
  try
    if not (RootVal is TJSONObject) then
      Exit;
    Result := True;
    StylesVal := TJSONObject(RootVal).Values['styles'];
    if not (StylesVal is TJSONObject) then
      Exit;
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      ItemVal := TJSONObject(StylesVal).Values[cSpanKindKeys[Kind]];
      if not (ItemVal is TJSONObject) then
        Continue;
      if TJSONObject(ItemVal).TryGetValue<string>('fg', Hex) then
        ASet[Kind].HasFg := HexToColor(Hex, ASet[Kind].Fg);
      if TJSONObject(ItemVal).TryGetValue<string>('bg', Hex) then
        ASet[Kind].HasBg := HexToColor(Hex, ASet[Kind].Bg);
      StyleVal := TJSONObject(ItemVal).Values['style'];
      if StyleVal is TJSONArray then
      begin
        ASet[Kind].HasStyle := True;
        ASet[Kind].Style := StyleFromJson(TJSONArray(StyleVal));
      end;
    end;
  finally
    RootVal.Free;
  end;
end;

var
  GLoaded: Boolean;
  GColors: TMdColorSet;

function DefaultMarkdownColorsFilePath: string;
begin
  Result := GetConfigFilePath('markdown-colors.json');
end;

procedure EnsureLoaded;
var
  Path: string;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  MdColorSetClear(GColors);
  Path := DefaultMarkdownColorsFilePath;
  if not TFile.Exists(Path) then
    Exit;
  try
    MdColorSetFromJson(TFile.ReadAllText(Path, TEncoding.UTF8), GColors);
  except
    MdColorSetClear(GColors);
  end;
end;

function GlobalMarkdownColors: TMdColorSet;
begin
  EnsureLoaded;
  Result := GColors;
end;

function SetGlobalMarkdownColors(const ASet: TMdColorSet): Boolean;
var
  Path, Dir: string;
begin
  GLoaded := True;
  GColors := ASet;
  Result := False;
  Path := DefaultMarkdownColorsFilePath;
  try
    Dir := ExtractFilePath(Path);
    if Dir <> '' then
      ForceDirectories(Dir);
    TFile.WriteAllText(Path, MdColorSetToJson(ASet), TEncoding.UTF8);
    Result := True;
  except
    { the colors stay in effect for this session; only persisting failed }
  end;
end;

function MarkdownColorOverride(AKind: TMdSpanKind): TMdColorPair;
begin
  EnsureLoaded;
  Result := GColors[AKind];
end;

procedure ApplyMarkdownColorOverride(AKind: TMdSpanKind; var AFg, ABg: TAlphaColor);
begin
  EnsureLoaded;
  if GColors[AKind].HasFg then
    AFg := GColors[AKind].Fg;
  if GColors[AKind].HasBg then
    ABg := GColors[AKind].Bg;
end;

procedure ApplyMarkdownStyleOverride(AKind: TMdSpanKind; var AAttr: TCharCellAttributes);
begin
  EnsureLoaded;
  if GColors[AKind].HasStyle then
    AAttr := GColors[AKind].Style;
end;

{ ---- Obsidian theme import -------------------------------------------------- }

type
  TCssVars = TDictionary<string, string>;

// Copies ACss without comments; quoted strings are kept as they are.
function StripCssComments(const ACss: string): string;
var
  SB: TStringBuilder;
  I, N: Integer;
  Quote: Char;
begin
  N := Length(ACss);
  SB := TStringBuilder.Create(N);
  try
    I := 1;
    while I <= N do
    begin
      if (ACss[I] = '/') and (I < N) and (ACss[I + 1] = '*') then
      begin
        I := Pos('*/', ACss, I + 2);
        if I = 0 then
          Break;
        Inc(I, 2);
        SB.Append(' ');
        Continue;
      end;
      if (ACss[I] = '"') or (ACss[I] = '''') then
      begin
        Quote := ACss[I];
        SB.Append(Quote);
        Inc(I);
        while (I <= N) and (ACss[I] <> Quote) do
        begin
          if (ACss[I] = '\') and (I < N) then
          begin
            SB.Append(ACss[I]);
            Inc(I);
          end;
          SB.Append(ACss[I]);
          Inc(I);
        end;
        if I <= N then
          SB.Append(Quote);
        Inc(I);
        Continue;
      end;
      SB.Append(ACss[I]);
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Index of the closing quote of the string starting at AStart (or Length(S)).
function SkipQuoted(const S: string; AStart: Integer): Integer;
var
  Quote: Char;
begin
  Quote := S[AStart];
  Result := AStart + 1;
  while (Result <= Length(S)) and (S[Result] <> Quote) do
  begin
    if S[Result] = '\' then
      Inc(Result);
    Inc(Result);
  end;
  if Result > Length(S) then
    Result := Length(S);
end;

// Index of the '}' closing the block whose '{' is at AOpen (Length(S) when unbalanced).
function FindBlockEnd(const S: string; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AOpen;
  while Result <= Length(S) do
  begin
    case S[Result] of
      '"', '''': Result := SkipQuoted(S, Result);
      '{': Inc(Depth);
      '}':
        begin
          Dec(Depth);
          if Depth = 0 then
            Exit;
        end;
    end;
    Inc(Result);
  end;
  Result := Length(S);
end;

// Custom properties ("--name: value") of one declaration block.
procedure ParseDeclarations(const ABody: string; AVars: TCssVars);
var
  I, Start, Depth, Colon, Bang: Integer;
  Decl, Name, Value: string;

  procedure Flush(AEnd: Integer);
  begin
    Decl := Trim(Copy(ABody, Start, AEnd - Start));
    Colon := Pos(':', Decl);
    if (Colon > 3) and (Copy(Decl, 1, 2) = '--') then
    begin
      Name := Trim(Copy(Decl, 1, Colon - 1));
      Value := Trim(Copy(Decl, Colon + 1, MaxInt));
      Bang := Pos('!important', LowerCase(Value));
      if Bang > 0 then
        Value := Trim(Copy(Value, 1, Bang - 1));
      AVars.AddOrSetValue(Name, Value);
    end;
  end;

begin
  Start := 1;
  Depth := 0;
  I := 1;
  while I <= Length(ABody) do
  begin
    case ABody[I] of
      '"', '''': I := SkipQuoted(ABody, I);
      '(': Inc(Depth);
      ')': Dec(Depth);
      ';':
        if Depth <= 0 then
        begin
          Flush(I);
          Start := I + 1;
        end;
    end;
    Inc(I);
  end;
  Flush(Length(ABody) + 1);
end;

// Reads the top-level rules that define the palette: ":root" / "body" / "html"
// (base), ".theme-dark" (palette) and "body.theme-dark" (most specific), in
// that order of precedence. At-rules and every other selector are skipped.
procedure CollectObsidianVars(const ACss: string; ADark: Boolean; AVars: TCssVars);
var
  S, Sel, Item, PalClass: string;
  Items: TArray<string>;
  Layers: array[0..2] of TCssVars;
  I, Open, CloseIdx, L, N: Integer;
  Hit: array[0..2] of Boolean;
  Pair: TPair<string, string>;
begin
  S := StripCssComments(ACss);
  if ADark then
    PalClass := '.theme-dark'
  else
    PalClass := '.theme-light';
  for L := 0 to 2 do
    Layers[L] := TCssVars.Create;
  try
    N := Length(S);
    I := 1;
    while I <= N do
    begin
      Open := I;
      while (Open <= N) and (S[Open] <> '{') do
      begin
        if (S[Open] = '"') or (S[Open] = '''') then
          Open := SkipQuoted(S, Open);
        Inc(Open);
      end;
      if Open > N then
        Break;
      CloseIdx := FindBlockEnd(S, Open);
      Sel := Trim(Copy(S, I, Open - I));
      if (Sel <> '') and (Sel[1] <> '@') then
      begin
        Hit[0] := False;
        Hit[1] := False;
        Hit[2] := False;
        Items := LowerCase(Sel).Split([',']);
        for Item in Items do
          if (Trim(Item) = ':root') or (Trim(Item) = 'body') or (Trim(Item) = 'html') then
            Hit[0] := True
          else if Trim(Item) = PalClass then
            Hit[1] := True
          else if Trim(Item) = 'body' + PalClass then
            Hit[2] := True;
        for L := 0 to 2 do
          if Hit[L] then
            ParseDeclarations(Copy(S, Open + 1, CloseIdx - Open - 1), Layers[L]);
      end;
      I := CloseIdx + 1;
    end;
    for L := 0 to 2 do
      for Pair in Layers[L] do
        AVars.AddOrSetValue(Pair.Key, Pair.Value);
  finally
    for L := 0 to 2 do
      Layers[L].Free;
  end;
end;

type
  TCssColor = record
    Color: TAlphaColor; // opaque RGB
    Alpha: Byte;
  end;

// Replaces every var(--x[, fallback]) in AValue by the variable's value
// (recursively expanded) or the fallback. False when one has neither.
function ExpandCssVars(const AValue: string; AVars: TCssVars; ADepth: Integer;
  out AResult: string): Boolean;
var
  P, I, Depth, Comma: Integer;
  Inner, Name, Fallback, Val, Expanded: string;
begin
  AResult := '';
  Result := False;
  if ADepth > 16 then
    Exit;
  P := 1;
  while P <= Length(AValue) do
  begin
    if (Copy(AValue, P, 4) = 'var(') and ((P = 1) or not CharInSet(AValue[P - 1], ['a'..'z', 'A'..'Z', '-', '_'])) then
    begin
      Depth := 1;
      I := P + 4;
      Comma := 0;
      while (I <= Length(AValue)) and (Depth > 0) do
      begin
        case AValue[I] of
          '(': Inc(Depth);
          ')': Dec(Depth);
          ',': if (Depth = 1) and (Comma = 0) then Comma := I;
        end;
        if Depth > 0 then
          Inc(I);
      end;
      if Depth > 0 then
        Exit;
      Inner := Copy(AValue, P + 4, I - P - 4);
      if Comma > 0 then
      begin
        Name := Trim(Copy(AValue, P + 4, Comma - P - 4));
        Fallback := Trim(Copy(AValue, Comma + 1, I - Comma - 1));
      end
      else
      begin
        Name := Trim(Inner);
        Fallback := '';
      end;
      if AVars.TryGetValue(Name, Val) and ExpandCssVars(Val, AVars, ADepth + 1, Expanded) then
        AResult := AResult + Expanded
      else if (Comma > 0) and ExpandCssVars(Fallback, AVars, ADepth + 1, Expanded) then
        AResult := AResult + Expanded
      else
        Exit;
      P := I + 1;
    end
    else
    begin
      AResult := AResult + AValue[P];
      Inc(P);
    end;
  end;
  Result := True;
end;

// Numeric expression: + - * / ( ) calc( ), numbers with an optional unit (ignored).
type
  TCssNumParser = record
    S: string;
    P: Integer;
    Ok: Boolean;
    function Expr: Double;
    function Term: Double;
    function Factor: Double;
    procedure SkipWs;
  end;

procedure TCssNumParser.SkipWs;
begin
  while (P <= Length(S)) and (S[P] = ' ') do
    Inc(P);
end;

function TCssNumParser.Factor: Double;
var
  Start: Integer;
  Neg: Boolean;
begin
  Result := 0;
  SkipWs;
  Neg := False;
  if (P <= Length(S)) and (S[P] = '-') then
  begin
    Neg := True;
    Inc(P);
    SkipWs;
  end
  else if (P <= Length(S)) and (S[P] = '+') then
  begin
    Inc(P);
    SkipWs;
  end;
  if Copy(S, P, 5) = 'calc(' then
    Inc(P, 4);
  if (P <= Length(S)) and (S[P] = '(') then
  begin
    Inc(P);
    Result := Expr;
    SkipWs;
    if (P <= Length(S)) and (S[P] = ')') then
      Inc(P)
    else
      Ok := False;
  end
  else
  begin
    Start := P;
    while (P <= Length(S)) and CharInSet(S[P], ['0'..'9', '.']) do
      Inc(P);
    if P = Start then
    begin
      Ok := False;
      Exit;
    end;
    Result := StrToFloatDef(Copy(S, Start, P - Start), 0, TFormatSettings.Invariant);
    while (P <= Length(S)) and CharInSet(S[P], ['%', 'a'..'z']) do
      Inc(P);
  end;
  if Neg then
    Result := -Result;
end;

function TCssNumParser.Term: Double;
var
  Rhs: Double;
begin
  Result := Factor;
  while Ok do
  begin
    SkipWs;
    if (P <= Length(S)) and (S[P] = '*') then
    begin
      Inc(P);
      Result := Result * Factor;
    end
    else if (P <= Length(S)) and (S[P] = '/') then
    begin
      Inc(P);
      Rhs := Factor;
      if Rhs = 0 then
        Ok := False
      else
        Result := Result / Rhs;
    end
    else
      Break;
  end;
end;

function TCssNumParser.Expr: Double;
begin
  Result := Term;
  while Ok do
  begin
    SkipWs;
    if (P <= Length(S)) and (S[P] = '+') then
    begin
      Inc(P);
      Result := Result + Term;
    end
    else if (P <= Length(S)) and (S[P] = '-') then
    begin
      Inc(P);
      Result := Result - Term;
    end
    else
      Break;
  end;
end;

function EvalCssNumber(const AText: string; out AValue: Double): Boolean;
var
  Parser: TCssNumParser;
begin
  Parser.S := Trim(AText);
  Parser.P := 1;
  Parser.Ok := True;
  AValue := Parser.Expr;
  Parser.SkipWs;
  Result := Parser.Ok and (Parser.P > Length(Parser.S));
end;

// Top-level arguments of a color function: split at commas, slashes and
// spaces outside nested parentheses.
function SplitCssArgs(const AText: string): TArray<string>;
var
  I, Depth: Integer;
  Cur: string;

  procedure Flush;
  begin
    if Trim(Cur) <> '' then
      Result := Result + [Trim(Cur)];
    Cur := '';
  end;

begin
  SetLength(Result, 0);
  Depth := 0;
  Cur := '';
  for I := 1 to Length(AText) do
  begin
    case AText[I] of
      '(': Inc(Depth);
      ')': Dec(Depth);
    end;
    if (Depth = 0) and CharInSet(AText[I], [',', '/', ' ']) then
      Flush
    else
      Cur := Cur + AText[I];
  end;
  Flush;
end;

function CssAlphaArg(const AArg: string; out AAlpha: Byte): Boolean;
var
  V: Double;
begin
  Result := EvalCssNumber(AArg, V);
  if not Result then
    Exit;
  if Pos('%', AArg) > 0 then
    V := V / 100;
  AAlpha := Round(EnsureRange(V, 0, 1) * 255);
end;

function HslToRgb(AH, ASat, ALight: Double): TAlphaColor;
var
  C, X, M, R, G, B: Double;
  Sector: Integer;
begin
  AH := AH - 360 * Floor(AH / 360);
  ASat := EnsureRange(ASat, 0, 100) / 100;
  ALight := EnsureRange(ALight, 0, 100) / 100;
  C := (1 - Abs(2 * ALight - 1)) * ASat;
  Sector := Trunc(AH / 60) mod 6;
  X := C * (1 - Abs(Frac(AH / 120) * 2 - 1));
  M := ALight - C / 2;
  case Sector of
    0: begin R := C; G := X; B := 0; end;
    1: begin R := X; G := C; B := 0; end;
    2: begin R := 0; G := C; B := X; end;
    3: begin R := 0; G := X; B := C; end;
    4: begin R := X; G := 0; B := C; end;
  else
    begin R := C; G := 0; B := X; end;
  end;
  Result := TAlphaColor($FF000000 or
    (Cardinal(Round((R + M) * 255)) shl 16) or
    (Cardinal(Round((G + M) * 255)) shl 8) or
    Cardinal(Round((B + M) * 255)));
end;

function ParseHexColor(const AText: string; out AColor: TCssColor): Boolean;
var
  H: string;
  R, G, B, A: Integer;
begin
  Result := False;
  H := Copy(AText, 2, MaxInt);
  if not (Length(H) in [3, 4, 6, 8]) then
    Exit;
  try
    if Length(H) <= 4 then
    begin
      R := StrToInt('$' + H[1] + H[1]);
      G := StrToInt('$' + H[2] + H[2]);
      B := StrToInt('$' + H[3] + H[3]);
      if Length(H) = 4 then
        A := StrToInt('$' + H[4] + H[4])
      else
        A := 255;
    end
    else
    begin
      R := StrToInt('$' + Copy(H, 1, 2));
      G := StrToInt('$' + Copy(H, 3, 2));
      B := StrToInt('$' + Copy(H, 5, 2));
      if Length(H) = 8 then
        A := StrToInt('$' + Copy(H, 7, 2))
      else
        A := 255;
    end;
  except
    Exit;
  end;
  AColor.Color := TAlphaColor($FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B));
  AColor.Alpha := A;
  Result := True;
end;

function ParseColorFunction(const AName, AArgs: string; out AColor: TCssColor): Boolean;
var
  Args: TArray<string>;
  V: array[0..2] of Double;
  I: Integer;
  IsHsl: Boolean;
begin
  Result := False;
  IsHsl := (AName = 'hsl') or (AName = 'hsla');
  if not (IsHsl or (AName = 'rgb') or (AName = 'rgba')) then
    Exit;
  Args := SplitCssArgs(AArgs);
  if not (Length(Args) in [3, 4]) then
    Exit;
  for I := 0 to 2 do
    if not EvalCssNumber(Args[I], V[I]) then
      Exit;
  AColor.Alpha := 255;
  if (Length(Args) = 4) and not CssAlphaArg(Args[3], AColor.Alpha) then
    Exit;
  if IsHsl then
    AColor.Color := HslToRgb(V[0], V[1], V[2])
  else
  begin
    for I := 0 to 2 do
      if Pos('%', Args[I]) > 0 then
        V[I] := V[I] * 255 / 100;
    AColor.Color := TAlphaColor($FF000000 or
      (Cardinal(EnsureRange(Round(V[0]), 0, 255)) shl 16) or
      (Cardinal(EnsureRange(Round(V[1]), 0, 255)) shl 8) or
      Cardinal(EnsureRange(Round(V[2]), 0, 255)));
  end;
  Result := True;
end;

function ParseCssColor(const AValue: string; AVars: TCssVars; out AColor: TCssColor): Boolean;
var
  Text, Name: string;
  Paren: Integer;
begin
  Result := False;
  if not ExpandCssVars(AValue, AVars, 0, Text) then
    Exit;
  Text := LowerCase(Trim(Text));
  if Text = '' then
    Exit;
  if Text[1] = '#' then
    Exit(ParseHexColor(Text, AColor));
  if Text = 'white' then
  begin
    AColor.Color := TAlphaColors.White;
    AColor.Alpha := 255;
    Exit(True);
  end;
  if Text = 'black' then
  begin
    AColor.Color := TAlphaColors.Black;
    AColor.Alpha := 255;
    Exit(True);
  end;
  Paren := Pos('(', Text);
  if (Paren < 2) or (Text[Length(Text)] <> ')') then
    Exit;
  Name := Copy(Text, 1, Paren - 1);
  Result := ParseColorFunction(Name, Copy(Text, Paren + 1, Length(Text) - Paren - 1), AColor);
end;

function BlendOver(const AColor: TCssColor; ABase: TAlphaColor): TAlphaColor;
var
  A: Integer;

  function Mix(AFg, ABg: Byte): Cardinal;
  begin
    Result := (AFg * A + ABg * (255 - A)) div 255;
  end;

begin
  if AColor.Alpha = 255 then
    Exit(AColor.Color);
  A := AColor.Alpha;
  Result := TAlphaColor($FF000000 or
    (Mix(TAlphaColorRec(AColor.Color).R, TAlphaColorRec(ABase).R) shl 16) or
    (Mix(TAlphaColorRec(AColor.Color).G, TAlphaColorRec(ABase).G) shl 8) or
    Mix(TAlphaColorRec(AColor.Color).B, TAlphaColorRec(ABase).B));
end;

type
  TObsidianSource = record
    FgVars, BgVars: TArray<string>;
  end;

// Variables tried in order for each span kind; the first that resolves wins.
function ObsidianSource(AKind: TMdSpanKind): TObsidianSource;
begin
  Result := Default(TObsidianSource);
  case AKind of
    mskText:
      begin
        Result.FgVars := ['--text-normal'];
        Result.BgVars := ['--background-primary'];
      end;
    mskH1: Result.FgVars := ['--h1-color'];
    mskH2: Result.FgVars := ['--h2-color'];
    mskH3to6: Result.FgVars := ['--h3-color'];
    mskBold: Result.FgVars := ['--bold-color', '--text-normal'];
    mskItalic: Result.FgVars := ['--italic-color', '--text-normal'];
    mskBoldItalic: Result.FgVars := ['--strong-em-color-1', '--bold-color', '--text-normal'];
    mskStrike: Result.FgVars := ['--text-faint', '--text-muted'];
    mskInlineCode:
      begin
        Result.FgVars := ['--text-color-code', '--code-normal'];
        Result.BgVars := ['--code-background', '--background-code'];
      end;
    mskCodeBlock:
      begin
        Result.FgVars := ['--code-normal', '--text-normal'];
        Result.BgVars := ['--code-background', '--background-code'];
      end;
    mskQuote: Result.FgVars := ['--blockquote-color', '--text-muted'];
    mskListMarker: Result.FgVars := ['--list-marker-color', '--list-ul-disc-color', '--text-accent'];
    mskHRule: Result.FgVars := ['--hr-color', '--background-modifier-border-hr', '--background-modifier-border'];
    mskLink: Result.FgVars := ['--link-color', '--text-accent'];
    mskImageMarker: Result.FgVars := ['--text-muted'];
    mskTableBorder: Result.FgVars := ['--table-border-color', '--background-modifier-border'];
    mskTableHeader: Result.FgVars := ['--table-header-color', '--text-normal'];
  end;
end;

function FirstColor(const ANames: TArray<string>; AVars: TCssVars; ABase: TAlphaColor;
  out AColor: TAlphaColor): Boolean;
var
  Name, Value: string;
  C: TCssColor;
begin
  Result := False;
  for Name in ANames do
    if AVars.TryGetValue(Name, Value) and ParseCssColor(Value, AVars, C) then
    begin
      AColor := BlendOver(C, ABase);
      Exit(True);
    end;
end;

// First of ANames that holds a value, lower-cased with its var() references expanded.
function FirstCssText(const ANames: TArray<string>; AVars: TCssVars; out AText: string): Boolean;
var
  Name, Value: string;
begin
  for Name in ANames do
    if AVars.TryGetValue(Name, Value) and ExpandCssVars(Value, AVars, 0, AText) then
    begin
      AText := LowerCase(Trim(AText));
      Exit(True);
    end;
  Result := False;
end;

function CssWeightIsBold(const AText: string): Boolean;
var
  N: Integer;
begin
  Result := (AText = 'bold') or (AText = 'bolder') or
    (TryStrToInt(AText, N) and (N >= 600));
end;

// Text style an Obsidian theme gives a kind through its weight / style /
// decoration variables; False when it sets none of them.
function ObsidianStyle(AKind: TMdSpanKind; AVars: TCssVars; out AStyle: TCharCellAttributes): Boolean;
var
  Text: string;
  Level: string;
begin
  AStyle := [];
  Result := False;
  case AKind of
    mskH1, mskH2, mskH3to6:
      begin
        case AKind of
          mskH1: Level := '--h1';
          mskH2: Level := '--h2';
        else
          Level := '--h3';
        end;
        if FirstCssText([Level + '-weight'], AVars, Text) then
        begin
          Result := True;
          if CssWeightIsBold(Text) then
            Include(AStyle, ccaBold);
        end;
        if FirstCssText([Level + '-style'], AVars, Text) then
        begin
          Result := True;
          if (Text = 'italic') or (Text = 'oblique') then
            Include(AStyle, ccaItalic);
        end;
      end;
    mskBold:
      if FirstCssText(['--bold-weight', '--font-weight-strong'], AVars, Text) then
      begin
        Result := True;
        if CssWeightIsBold(Text) then
          Include(AStyle, ccaBold);
      end;
    mskTableHeader:
      if FirstCssText(['--table-header-weight'], AVars, Text) then
      begin
        Result := True;
        if CssWeightIsBold(Text) then
          Include(AStyle, ccaBold);
      end;
    mskLink:
      if FirstCssText(['--link-decoration'], AVars, Text) then
      begin
        Result := True;
        if Pos('underline', Text) > 0 then
          Include(AStyle, ccaUnderline);
      end;
    mskQuote:
      if FirstCssText(['--blockquote-font-style'], AVars, Text) then
      begin
        Result := True;
        if (Text = 'italic') or (Text = 'oblique') then
          Include(AStyle, ccaItalic);
      end;
  end;
end;

function ParseObsidianThemeCss(const ACss: string; ADark: Boolean;
  out ASet: TMdColorSet): Boolean;
var
  Vars: TCssVars;
  Kind: TMdSpanKind;
  Src: TObsidianSource;
  Base: TAlphaColor;
  C: TCssColor;
  Value, H, S, L: string;
begin
  MdColorSetClear(ASet);
  Result := False;
  Vars := TCssVars.Create;
  try
    CollectObsidianVars(ACss, ADark, Vars);
    // Obsidian derives its accent from the three HSL parts.
    if not Vars.ContainsKey('--color-accent') and Vars.TryGetValue('--accent-h', H) and
       Vars.TryGetValue('--accent-s', S) and Vars.TryGetValue('--accent-l', L) then
      Vars.Add('--color-accent', 'hsl(' + H + ',' + S + ',' + L + ')');
    // Translucent colors (code background, table borders) are flattened onto
    // the page background.
    if ADark then
      Base := TAlphaColor($FF202020)
    else
      Base := TAlphaColors.White;
    if Vars.TryGetValue('--background-primary', Value) and ParseCssColor(Value, Vars, C) then
      Base := C.Color;
    for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    begin
      Src := ObsidianSource(Kind);
      ASet[Kind].HasFg := FirstColor(Src.FgVars, Vars, Base, ASet[Kind].Fg);
      ASet[Kind].HasBg := FirstColor(Src.BgVars, Vars, Base, ASet[Kind].Bg);
      ASet[Kind].HasStyle := ObsidianStyle(Kind, Vars, ASet[Kind].Style);
      if ASet[Kind].HasFg or ASet[Kind].HasBg or ASet[Kind].HasStyle then
        Result := True;
    end;
  finally
    Vars.Free;
  end;
end;

function LoadObsidianTheme(const APath: string; ADark: Boolean;
  out ASet: TMdColorSet; out AError: TMdImportError): Boolean;
var
  Css: string;
begin
  MdColorSetClear(ASet);
  AError := mieNone;
  Result := False;
  if Trim(APath) = '' then
  begin
    AError := mieNoPath;
    Exit;
  end;
  if not TFile.Exists(APath) then
  begin
    AError := mieNotFound;
    Exit;
  end;
  try
    Css := TFile.ReadAllText(APath, TEncoding.UTF8);
  except
    AError := mieUnreadable;
    Exit;
  end;
  if not ParseObsidianThemeCss(Css, ADark, ASet) then
  begin
    AError := mieNoColors;
    Exit;
  end;
  Result := True;
end;

end.
