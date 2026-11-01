unit uEditorLineOps;

{ Whole-line text commands of the editor: sort, remove repeated lines, shift
  (indent / outdent), reflow to a width and align. Each function takes the document
  as an array of lines and the inclusive line range to work on, and returns
  the new lines of that range; the caller splices them back. No I/O and no
  editor state, so the rules are testable on their own. }

interface

type
  TLineArray = TArray<string>;

  TCaseMode = (cmUpper, cmLower, cmTitle);
  TAlignMode = (amLeft, amCenter, amRight);
  TBoxStyle = (bsSingle, bsDouble);

const
  /// <summary>Columns one Shift Right / Left step moves a line.</summary>
  cShiftWidth = 4;

/// <summary>Lines AFrom..ATo ordered by text, ignoring case; equal lines keep
/// their relative order. ADescending reverses the order.</summary>
function SortedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  ADescending: Boolean): TLineArray;

/// <summary>Lines AFrom..ATo without repeats: the first copy of each line
/// stays, later copies (adjacent or not) go. Lines compare exactly, case and
/// trailing spaces included.</summary>
function UniqueLines(const ALines: TLineArray; AFrom, ATo: Integer): TLineArray;

/// <summary>Lines AFrom..ATo moved right by cShiftWidth spaces (blank lines
/// stay blank) or left by up to cShiftWidth leading spaces, or by one leading
/// tab.</summary>
function ShiftedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  AToRight: Boolean): TLineArray;

/// <summary>Lines AFrom..ATo as paragraphs filled up to AWidth characters.
/// Blank lines separate paragraphs and are kept. Every line of a paragraph
/// takes the indent of its first line. A word longer than the width stays
/// whole on a line of its own.</summary>
function ReflowedLines(const ALines: TLineArray; AFrom, ATo, AWidth: Integer): TLineArray;

/// <summary>Lines AFrom..ATo with their text flush left, centered or flush
/// right within the width of the widest line of the range (leading and
/// trailing blanks do not count). Blank lines come back empty.</summary>
function AlignedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  AMode: TAlignMode): TLineArray;

/// <summary>AText with the letters in the given case. Title case capitalizes
/// the first letter of each word and lowers the rest; an apostrophe between
/// two letters stays inside the word.</summary>
function ChangedCase(const AText: string; AMode: TCaseMode): string;

/// <summary>The mode that follows the state of AText: mixed text goes to
/// upper case, upper to lower, lower to title, title to upper.</summary>
function NextCaseMode(const AText: string): TCaseMode;

const
  /// <summary>Bits of a box-drawing cell: the sides its line reaches.</summary>
  cBoxUp = 1;
  cBoxDown = 2;
  cBoxLeft = 4;
  cBoxRight = 8;

/// <summary>The sides ACh connects to when it is a single or double
/// box-drawing character, else 0. The straight characters read as full
/// lines (vertical = up + down, horizontal = left + right).</summary>
function BoxMask(ACh: Char): Integer;

/// <summary>The box-drawing character that joins the sides in AMask (a blank
/// for 0).</summary>
function BoxChar(AMask: Integer; AStyle: TBoxStyle): Char;

implementation

uses
  System.SysUtils, System.Character, System.Generics.Collections,
  System.Generics.Defaults;

type
  TIndexedLine = record
    Text: string;
    Index: Integer;
  end;

function SliceLines(const ALines: TLineArray; AFrom, ATo: Integer): TLineArray;
var
  I: Integer;
begin
  if AFrom < 0 then
    AFrom := 0;
  if ATo > High(ALines) then
    ATo := High(ALines);
  if ATo < AFrom then
    Exit(nil);
  SetLength(Result, ATo - AFrom + 1);
  for I := AFrom to ATo do
    Result[I - AFrom] := ALines[I];
end;

function SortedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  ADescending: Boolean): TLineArray;
var
  Items: TArray<TIndexedLine>;
  I: Integer;
begin
  Result := SliceLines(ALines, AFrom, ATo);
  SetLength(Items, Length(Result));
  for I := 0 to High(Result) do
  begin
    Items[I].Text := Result[I];
    Items[I].Index := I;
  end;
  TArray.Sort<TIndexedLine>(Items, TComparer<TIndexedLine>.Construct(
    function(const L, R: TIndexedLine): Integer
    begin
      Result := CompareText(L.Text, R.Text);
      if Result = 0 then
        Result := L.Index - R.Index;
      if ADescending and (CompareText(L.Text, R.Text) <> 0) then
        Result := -Result;
    end));
  for I := 0 to High(Items) do
    Result[I] := Items[I].Text;
end;

function UniqueLines(const ALines: TLineArray; AFrom, ATo: Integer): TLineArray;
var
  Seen: TDictionary<string, Boolean>;
  Src: TLineArray;
  Kept: TList<string>;
  S: string;
begin
  Src := SliceLines(ALines, AFrom, ATo);
  Seen := TDictionary<string, Boolean>.Create;
  Kept := TList<string>.Create;
  try
    for S in Src do
      if not Seen.ContainsKey(S) then
      begin
        Seen.Add(S, True);
        Kept.Add(S);
      end;
    Result := Kept.ToArray;
  finally
    Kept.Free;
    Seen.Free;
  end;
end;

function ShiftedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  AToRight: Boolean): TLineArray;
var
  I, N: Integer;
  S: string;
begin
  Result := SliceLines(ALines, AFrom, ATo);
  for I := 0 to High(Result) do
  begin
    S := Result[I];
    if AToRight then
    begin
      if Trim(S) <> '' then
        Result[I] := StringOfChar(' ', cShiftWidth) + S;
    end
    else if (S <> '') and (S[1] = #9) then
      Result[I] := Copy(S, 2, MaxInt)
    else
    begin
      N := 0;
      while (N < cShiftWidth) and (N < Length(S)) and (S[N + 1] = ' ') do
        Inc(N);
      Result[I] := Copy(S, N + 1, MaxInt);
    end;
  end;
end;

function LeadingWhitespace(const S: string): string;
var
  N: Integer;
begin
  N := 0;
  while (N < Length(S)) and ((S[N + 1] = ' ') or (S[N + 1] = #9)) do
    Inc(N);
  Result := Copy(S, 1, N);
end;

procedure FlushParagraph(const AWords: TList<string>; const AIndent: string;
  AWidth: Integer; AOut: TList<string>);
var
  Line, Word: string;
begin
  if AWords.Count = 0 then
    Exit;
  Line := '';
  for Word in AWords do
  begin
    if Line = '' then
      Line := AIndent + Word
    else if Length(Line) + 1 + Length(Word) <= AWidth then
      Line := Line + ' ' + Word
    else
    begin
      AOut.Add(Line);
      Line := AIndent + Word;
    end;
  end;
  AOut.Add(Line);
  AWords.Clear;
end;

function ReflowedLines(const ALines: TLineArray; AFrom, ATo, AWidth: Integer): TLineArray;
var
  Src: TLineArray;
  Words: TList<string>;
  Outp: TList<string>;
  Indent, S, Part: string;
  Parts: TArray<string>;
begin
  Src := SliceLines(ALines, AFrom, ATo);
  if AWidth < 1 then
    AWidth := 1;
  Words := TList<string>.Create;
  Outp := TList<string>.Create;
  try
    Indent := '';
    for S in Src do
    begin
      if Trim(S) = '' then
      begin
        FlushParagraph(Words, Indent, AWidth, Outp);
        Outp.Add('');
        Continue;
      end;
      if Words.Count = 0 then
        Indent := LeadingWhitespace(S);
      Parts := Trim(S).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      for Part in Parts do
        Words.Add(Part);
    end;
    FlushParagraph(Words, Indent, AWidth, Outp);
    Result := Outp.ToArray;
  finally
    Outp.Free;
    Words.Free;
  end;
end;

function AlignedLines(const ALines: TLineArray; AFrom, ATo: Integer;
  AMode: TAlignMode): TLineArray;
var
  I, Width, Pad: Integer;
  Text: string;
begin
  Result := SliceLines(ALines, AFrom, ATo);
  Width := 0;
  for I := 0 to High(Result) do
  begin
    Result[I] := Trim(Result[I]);
    if Length(Result[I]) > Width then
      Width := Length(Result[I]);
  end;
  for I := 0 to High(Result) do
  begin
    Text := Result[I];
    case AMode of
      amCenter: Pad := (Width - Length(Text)) div 2;
      amRight: Pad := Width - Length(Text);
    else
      Pad := 0;
    end;
    if Text <> '' then
      Result[I] := StringOfChar(' ', Pad) + Text;
  end;
end;

function ChangedCase(const AText: string; AMode: TCaseMode): string;
var
  I: Integer;
  InWord: Boolean;
  Ch: Char;
begin
  case AMode of
    cmUpper:
      Exit(AText.ToUpper);
    cmLower:
      Exit(AText.ToLower);
  end;
  Result := AText;
  InWord := False;
  for I := 1 to Length(Result) do
  begin
    Ch := Result[I];
    if Ch.IsLetterOrDigit then
    begin
      if InWord then
        Result[I] := Ch.ToLower
      else
        Result[I] := Ch.ToUpper;
      InWord := True;
    end
    else
      InWord := InWord and ((Ch = '''') or (Ch = #$2019)) and (I < Length(Result)) and
        Result[I + 1].IsLetter;
  end;
end;

function NextCaseMode(const AText: string): TCaseMode;
begin
  if AText.ToLower = AText.ToUpper then
    Exit(cmUpper);
  if AText = AText.ToUpper then
    Exit(cmLower);
  if AText = AText.ToLower then
    Exit(cmTitle);
  Result := cmUpper;
end;

const
  // Indexed by the side bits; a side seen alone draws the straight piece.
  cSingleBox: array[0..15] of Char = (' ', #$2502, #$2502, #$2502, #$2500,
    #$2518, #$2510, #$2524, #$2500, #$2514, #$250C, #$251C, #$2500, #$2534,
    #$252C, #$253C);
  cDoubleBox: array[0..15] of Char = (' ', #$2551, #$2551, #$2551, #$2550,
    #$255D, #$2557, #$2563, #$2550, #$255A, #$2554, #$2560, #$2550, #$2569,
    #$2566, #$256C);

function BoxMask(ACh: Char): Integer;
var
  I: Integer;
begin
  Result := 0;
  if ACh = ' ' then
    Exit;
  for I := High(cSingleBox) downto 1 do
    if (cSingleBox[I] = ACh) or (cDoubleBox[I] = ACh) then
      Exit(I);
end;

function BoxChar(AMask: Integer; AStyle: TBoxStyle): Char;
begin
  AMask := AMask and 15;
  if AStyle = bsDouble then
    Result := cDoubleBox[AMask]
  else
    Result := cSingleBox[AMask];
end;

end.
