unit uEditorLineOps;

{ Whole-line text commands of the editor: sort, remove repeated lines, shift
  (indent / outdent) and reflow to a width. Each function takes the document
  as an array of lines and the inclusive line range to work on, and returns
  the new lines of that range; the caller splices them back. No I/O and no
  editor state, so the rules are testable on their own. }

interface

type
  TLineArray = TArray<string>;

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

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults;

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

end.
