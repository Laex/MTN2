unit uCharWidth;

{ Display width of a character in terminal cells. Chinese, Japanese and Korean
  characters of the Basic Multilingual Plane take two cells; everything else
  takes one. Characters outside the BMP (surrogate pairs), combining marks and
  zero-width characters are not treated specially. }

interface

const
  // First character that can be wide; everything below is one cell.
  cFirstWideChar = #$1100;

/// <summary>2 for a wide (CJK, Hangul, fullwidth) character, 1 otherwise.</summary>
function CharDisplayWidth(ACh: Char): Integer; inline;
function IsWideChar(ACh: Char): Boolean;
/// <summary>Cells AText occupies.</summary>
function TextDisplayWidth(const AText: string): Integer;
/// <summary>How many leading characters of AText fit into AMaxCols cells.</summary>
function TextFitChars(const AText: string; AMaxCols: Integer): Integer;
/// <summary>AText without the filler cell that follows each wide character in
/// a cell-aligned line (one character per cell).</summary>
function StripWideFillers(const AText: string): string;

implementation

type
  TCharRange = record
    First, Last: Char;
  end;

const
  cWideRanges: array[0..11] of TCharRange = (
    (First: #$1100; Last: #$115F),  // Hangul Jamo
    (First: #$2E80; Last: #$303E),  // CJK radicals, Kangxi, CJK symbols and punctuation
    (First: #$3041; Last: #$33FF),  // Hiragana, Katakana, Bopomofo, enclosed and compat CJK
    (First: #$3400; Last: #$4DBF),  // CJK Extension A
    (First: #$4E00; Last: #$9FFF),  // CJK Unified Ideographs
    (First: #$A000; Last: #$A4CF),  // Yi
    (First: #$A960; Last: #$A97F),  // Hangul Jamo Extended-A
    (First: #$AC00; Last: #$D7A3),  // Hangul Syllables
    (First: #$F900; Last: #$FAFF),  // CJK Compatibility Ideographs
    (First: #$FE30; Last: #$FE6B),  // CJK Compatibility and Small Form Variants
    (First: #$FF01; Last: #$FF60),  // Fullwidth forms
    (First: #$FFE0; Last: #$FFE6)); // Fullwidth signs

function IsWideChar(ACh: Char): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  if ACh < cFirstWideChar then
    Exit;
  Lo := 0;
  Hi := High(cWideRanges);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if ACh < cWideRanges[Mid].First then
      Hi := Mid - 1
    else if ACh > cWideRanges[Mid].Last then
      Lo := Mid + 1
    else
      Exit(True);
  end;
end;

function CharDisplayWidth(ACh: Char): Integer;
begin
  if (ACh >= cFirstWideChar) and IsWideChar(ACh) then
    Result := 2
  else
    Result := 1;
end;

function TextDisplayWidth(const AText: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(AText) do
    Inc(Result, CharDisplayWidth(AText[I]));
end;

function TextFitChars(const AText: string; AMaxCols: Integer): Integer;
var
  I, Used, W: Integer;
begin
  Result := 0;
  Used := 0;
  for I := 1 to Length(AText) do
  begin
    W := CharDisplayWidth(AText[I]);
    if Used + W > AMaxCols then
      Exit;
    Inc(Used, W);
    Result := I;
  end;
end;

function StripWideFillers(const AText: string): string;
var
  I, N: Integer;
begin
  SetLength(Result, Length(AText));
  N := 0;
  I := 1;
  while I <= Length(AText) do
  begin
    Inc(N);
    Result[N] := AText[I];
    if (CharDisplayWidth(AText[I]) = 2) and (I < Length(AText)) then
      Inc(I);
    Inc(I);
  end;
  SetLength(Result, N);
end;

end.
