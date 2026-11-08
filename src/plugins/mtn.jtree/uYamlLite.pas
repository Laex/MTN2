unit uYamlLite;

{ A reader for the common subset of YAML, producing a JSON value tree.

  Supported: block mappings and sequences (also a sequence at the indent of its key),
  plain / single-quoted / double-quoted scalars, flow sequences and mappings on one
  line, literal (|) and folded (>) block scalars, comments, the first document of a
  stream. Plain scalars become null, boolean or number when they look like one.
  Not supported: anchors, aliases, tags, multi-line flow collections, multi-line plain
  or quoted scalars, complex keys. Such input raises EYamlError with the line number. }

interface

uses
  System.SysUtils, System.JSON;

type
  EYamlError = class(Exception);

/// <summary>The value tree of the first document; the caller frees it.</summary>
function ParseYaml(const AText: string): TJSONValue;

implementation

uses
  System.Classes, System.Generics.Collections, System.StrUtils;

type
  TLine = record
    Indent: Integer;   // -1 for a blank or comment-only line
    Text: string;      // the content without indent, comment and trailing blanks
    Raw: string;       // the line as written, for block scalars
    No: Integer;
  end;

  TYamlReader = class
  private
    FLines: TList<TLine>;
    FPos: Integer;
    function SkipBlank: Boolean;
    function Fail(ANo: Integer; const AMsg: string): EYamlError;
    function ParseBlock(AIndent: Integer): TJSONValue;
    function ParseSequence(AIndent: Integer): TJSONValue;
    function ParseMapping(AIndent: Integer): TJSONValue;
    function ParseValueAfter(const ARest: string; AParentIndent: Integer; ANo: Integer): TJSONValue;
    function ParseBlockScalar(const AHeader: string; AParentIndent: Integer): TJSONValue;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Run: TJSONValue;
  end;

  TFlowReader = class
  private
    FText: string;
    FPos: Integer;
    FNo: Integer;
    procedure SkipBlanks;
    function Fail(const AMsg: string): EYamlError;
    function ReadValue: TJSONValue;
    function ReadQuoted: string;
    function ReadPlain(const AStops: string): string;
  public
    constructor Create(const AText: string; ANo: Integer);
    function Run: TJSONValue;
  end;

function PlainScalar(const AText: string): TJSONValue;
var
  S: string;
  I: Int64;
  D: Double;
begin
  S := AText;
  if (S = '') or (S = '~') or SameText(S, 'null') then
    Exit(TJSONNull.Create);
  if (S = 'true') or (S = 'True') or (S = 'TRUE') then
    Exit(TJSONBool.Create(True));
  if (S = 'false') or (S = 'False') or (S = 'FALSE') then
    Exit(TJSONBool.Create(False));
  if TryStrToInt64(S, I) and not ((Length(S) > 1) and (S[1] = '0')) then
    Exit(TJSONNumber.Create(I));
  if (Pos('.', S) > 0) and TryStrToFloat(S, D, TFormatSettings.Invariant) and
     CharInSet(S[Length(S)], ['0'..'9']) then
    Exit(TJSONNumber.Create(D));
  Result := TJSONString.Create(S);
end;

function UnescapeDouble(const AInner: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  I := 1;
  while I <= Length(AInner) do
  begin
    C := AInner[I];
    if (C = '\') and (I < Length(AInner)) then
    begin
      Inc(I);
      case AInner[I] of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
        '0': Result := Result + #0;
        'u':
          if I + 4 <= Length(AInner) then
          begin
            Result := Result + Char(StrToIntDef('$' + Copy(AInner, I + 1, 4), 63));
            Inc(I, 4);
          end;
      else
        Result := Result + AInner[I];
      end;
    end
    else
      Result := Result + C;
    Inc(I);
  end;
end;

// The position of the closing quote of the string that opens at AStart, or 0.
function QuoteEnd(const AText: string; AStart: Integer): Integer;
var
  Q: Char;
  I: Integer;
begin
  Q := AText[AStart];
  I := AStart + 1;
  while I <= Length(AText) do
  begin
    if (Q = '"') and (AText[I] = '\') then
      Inc(I)
    else if AText[I] = Q then
    begin
      if (Q = '''') and (I < Length(AText)) and (AText[I + 1] = '''') then
        Inc(I)
      else
        Exit(I);
    end;
    Inc(I);
  end;
  Result := 0;
end;

function StripComment(const AText: string): string;
var
  I: Integer;
begin
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '"') or (AText[I] = '''') then
    begin
      // A quote inside a plain scalar ("it's") does not open a string.
      if (I = 1) or CharInSet(AText[I - 1], [' ', '[', '{', ',', ':', '-']) then
      begin
        I := QuoteEnd(AText, I);
        if I = 0 then
          Break;
      end;
    end
    else if (AText[I] = '#') and ((I = 1) or (AText[I - 1] = ' ')) then
      Exit(TrimRight(Copy(AText, 1, I - 1)));
    Inc(I);
  end;
  Result := TrimRight(AText);
end;

// The position of the colon that ends the name of a mapping entry (with or without a value), or 0.
function KeyColon(const AText: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  if AText = '' then
    Exit;
  I := 1;
  if (AText[1] = '"') or (AText[1] = '''') then
  begin
    I := QuoteEnd(AText, 1);
    if I = 0 then
      Exit;
    Inc(I);
    if (I <= Length(AText)) and (AText[I] = ':') and
       ((I = Length(AText)) or (AText[I + 1] = ' ')) then
      Result := I;
    Exit;
  end;
  if CharInSet(AText[1], ['[', '{']) then
    Exit;
  while I <= Length(AText) do
  begin
    if (AText[I] = ':') and ((I = Length(AText)) or (AText[I + 1] = ' ')) then
      Exit(I);
    Inc(I);
  end;
end;

function UnquoteKey(const AKey: string): string;
begin
  Result := Trim(AKey);
  if (Length(Result) >= 2) and (Result[1] = '"') then
    Result := UnescapeDouble(Copy(Result, 2, Length(Result) - 2))
  else if (Length(Result) >= 2) and (Result[1] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
end;

{ TFlowReader }

constructor TFlowReader.Create(const AText: string; ANo: Integer);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FNo := ANo;
end;

function TFlowReader.Fail(const AMsg: string): EYamlError;
begin
  Result := EYamlError.CreateFmt('Line %d: %s', [FNo, AMsg]);
end;

procedure TFlowReader.SkipBlanks;
begin
  while (FPos <= Length(FText)) and (FText[FPos] = ' ') do
    Inc(FPos);
end;

function TFlowReader.ReadQuoted: string;
var
  E: Integer;
begin
  E := QuoteEnd(FText, FPos);
  if E = 0 then
    raise Fail('unterminated string');
  if FText[FPos] = '"' then
    Result := UnescapeDouble(Copy(FText, FPos + 1, E - FPos - 1))
  else
    Result := Copy(FText, FPos + 1, E - FPos - 1).Replace('''''', '''');
  FPos := E + 1;
end;

function TFlowReader.ReadPlain(const AStops: string): string;
var
  Start: Integer;
begin
  Start := FPos;
  while (FPos <= Length(FText)) and (Pos(FText[FPos], AStops) = 0) do
    Inc(FPos);
  Result := Trim(Copy(FText, Start, FPos - Start));
end;

function TFlowReader.ReadValue: TJSONValue;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  Key: string;
begin
  SkipBlanks;
  if FPos > Length(FText) then
    raise Fail('value expected');
  case FText[FPos] of
    '[':
      begin
        Inc(FPos);
        Arr := TJSONArray.Create;
        try
          SkipBlanks;
          if (FPos <= Length(FText)) and (FText[FPos] = ']') then
          begin
            Inc(FPos);
            Exit(Arr);
          end;
          while True do
          begin
            Arr.AddElement(ReadValue);
            SkipBlanks;
            if FPos > Length(FText) then
              raise Fail('"]" expected');
            if FText[FPos] = ',' then
              Inc(FPos)
            else if FText[FPos] = ']' then
            begin
              Inc(FPos);
              Exit(Arr);
            end
            else
              raise Fail('"," or "]" expected');
          end;
        except
          Arr.Free;
          raise;
        end;
      end;
    '{':
      begin
        Inc(FPos);
        Obj := TJSONObject.Create;
        try
          SkipBlanks;
          if (FPos <= Length(FText)) and (FText[FPos] = '}') then
          begin
            Inc(FPos);
            Exit(Obj);
          end;
          while True do
          begin
            SkipBlanks;
            if (FPos <= Length(FText)) and CharInSet(FText[FPos], ['"', '''']) then
              Key := ReadQuoted
            else
              Key := ReadPlain(':,}');
            SkipBlanks;
            if (FPos > Length(FText)) or (FText[FPos] <> ':') then
              raise Fail('":" expected');
            Inc(FPos);
            Obj.AddPair(Key, ReadValue);
            SkipBlanks;
            if FPos > Length(FText) then
              raise Fail('"}" expected');
            if FText[FPos] = ',' then
              Inc(FPos)
            else if FText[FPos] = '}' then
            begin
              Inc(FPos);
              Exit(Obj);
            end
            else
              raise Fail('"," or "}" expected');
          end;
        except
          Obj.Free;
          raise;
        end;
      end;
    '"', '''':
      Result := TJSONString.Create(ReadQuoted);
  else
    Result := PlainScalar(ReadPlain(',]}'));
  end;
end;

function TFlowReader.Run: TJSONValue;
begin
  Result := ReadValue;
  SkipBlanks;
  if FPos <= Length(FText) then
  begin
    Result.Free;
    raise Fail('unexpected text after the value');
  end;
end;

{ TYamlReader }

constructor TYamlReader.Create(const AText: string);
var
  Src: TStringList;
  I, N, Indent: Integer;
  L: TLine;
  S, Body: string;
begin
  inherited Create;
  FLines := TList<TLine>.Create;
  Src := TStringList.Create;
  try
    Src.Text := AText;
    N := 0;
    for I := 0 to Src.Count - 1 do
    begin
      S := Src[I];
      if (I = 0) and (S <> '') and (S[1] = #$FEFF) then
        S := Copy(S, 2, MaxInt);
      L := Default(TLine);
      L.No := I + 1;
      L.Raw := S;
      Indent := 0;
      while (Indent < Length(S)) and (S[Indent + 1] = ' ') do
        Inc(Indent);
      Body := Copy(S, Indent + 1, MaxInt);
      if (Body <> '') and (Body[1] = #9) then
        raise Fail(L.No, 'a tab cannot indent a line');
      if (Indent = 0) and ((Body = '---') or StartsStr('--- ', Body)) then
      begin
        Inc(N);
        if N > 1 then
          Break;
        Continue;
      end;
      if (Indent = 0) and (Body = '...') then
        Break;
      Body := StripComment(Body);
      if Body = '' then
        L.Indent := -1
      else
      begin
        L.Indent := Indent;
        L.Text := Body;
      end;
      FLines.Add(L);
    end;
  finally
    Src.Free;
  end;
end;

destructor TYamlReader.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TYamlReader.Fail(ANo: Integer; const AMsg: string): EYamlError;
begin
  Result := EYamlError.CreateFmt('Line %d: %s', [ANo, AMsg]);
end;

// Moves past blank lines; False at the end of the text.
function TYamlReader.SkipBlank: Boolean;
begin
  while (FPos < FLines.Count) and (FLines[FPos].Indent < 0) do
    Inc(FPos);
  Result := FPos < FLines.Count;
end;

function TYamlReader.Run: TJSONValue;
begin
  if not SkipBlank then
    Exit(TJSONNull.Create);
  Result := ParseBlock(FLines[FPos].Indent);
  if SkipBlank then
  begin
    Result.Free;
    raise Fail(FLines[FPos].No, 'unexpected indentation');
  end;
end;

function TYamlReader.ParseBlock(AIndent: Integer): TJSONValue;
var
  L: TLine;
begin
  L := FLines[FPos];
  if (L.Text = '-') or StartsStr('- ', L.Text) then
    Exit(ParseSequence(AIndent));
  if KeyColon(L.Text) > 0 then
    Exit(ParseMapping(AIndent));
  Inc(FPos);
  Result := ParseValueAfter(L.Text, AIndent - 1, L.No);
end;

function TYamlReader.ParseSequence(AIndent: Integer): TJSONValue;
var
  Arr: TJSONArray;
  L: TLine;
  Rest: string;
  Offset: Integer;
begin
  Arr := TJSONArray.Create;
  try
    while SkipBlank and (FLines[FPos].Indent = AIndent) and
          ((FLines[FPos].Text = '-') or StartsStr('- ', FLines[FPos].Text)) do
    begin
      L := FLines[FPos];
      Rest := Trim(Copy(L.Text, 2, MaxInt));
      if Rest = '' then
      begin
        Inc(FPos);
        if SkipBlank and (FLines[FPos].Indent > AIndent) then
          Arr.AddElement(ParseBlock(FLines[FPos].Indent))
        else
          Arr.AddElement(TJSONNull.Create);
      end
      else if (KeyColon(Rest) > 0) or (Rest = '-') or StartsStr('- ', Rest) then
      begin
        // A mapping entry after the dash: the rest of the line starts a block of its own, indented past the dash.
        Offset := Length(L.Text) - Length(Rest);
        L.Indent := AIndent + Offset;
        L.Text := Rest;
        FLines[FPos] := L;
        Arr.AddElement(ParseBlock(L.Indent));
      end
      else
      begin
        Inc(FPos);
        Arr.AddElement(ParseValueAfter(Rest, AIndent, L.No));
      end;
    end;
    Result := Arr;
  except
    Arr.Free;
    raise;
  end;
end;

function TYamlReader.ParseMapping(AIndent: Integer): TJSONValue;
var
  Obj: TJSONObject;
  L: TLine;
  C: Integer;
  Key, Rest: string;
begin
  Obj := TJSONObject.Create;
  try
    while SkipBlank and (FLines[FPos].Indent = AIndent) do
    begin
      L := FLines[FPos];
      C := KeyColon(L.Text);
      if C = 0 then
        raise Fail(L.No, 'a "key: value" line expected');
      Key := UnquoteKey(Copy(L.Text, 1, C - 1));
      Rest := Trim(Copy(L.Text, C + 1, MaxInt));
      Inc(FPos);
      if Rest = '' then
      begin
        if SkipBlank and (FLines[FPos].Indent > AIndent) then
          Obj.AddPair(Key, ParseBlock(FLines[FPos].Indent))
        else if SkipBlank and (FLines[FPos].Indent = AIndent) and
                ((FLines[FPos].Text = '-') or StartsStr('- ', FLines[FPos].Text)) then
          Obj.AddPair(Key, ParseSequence(AIndent))
        else
          Obj.AddPair(Key, TJSONNull.Create);
      end
      else
        Obj.AddPair(Key, ParseValueAfter(Rest, AIndent, L.No));
    end;
    if SkipBlank and (FLines[FPos].Indent > AIndent) then
      raise Fail(FLines[FPos].No, 'unexpected indentation');
    Result := Obj;
  except
    Obj.Free;
    raise;
  end;
end;

function TYamlReader.ParseValueAfter(const ARest: string; AParentIndent: Integer;
  ANo: Integer): TJSONValue;
var
  Flow: TFlowReader;
  E: Integer;
begin
  if (ARest[1] = '|') or (ARest[1] = '>') then
    Exit(ParseBlockScalar(ARest, AParentIndent));
  if CharInSet(ARest[1], ['[', '{']) then
  begin
    Flow := TFlowReader.Create(ARest, ANo);
    try
      Exit(Flow.Run);
    finally
      Flow.Free;
    end;
  end;
  if CharInSet(ARest[1], ['"', '''']) then
  begin
    E := QuoteEnd(ARest, 1);
    if (E = 0) or (E <> Length(ARest)) then
      raise Fail(ANo, 'unterminated or multi-line string');
    Flow := TFlowReader.Create(ARest, ANo);
    try
      Exit(Flow.Run);
    finally
      Flow.Free;
    end;
  end;
  if CharInSet(ARest[1], ['&', '*', '!']) then
    raise Fail(ANo, 'anchors, aliases and tags are not supported');
  Result := PlainScalar(ARest);
end;

function TYamlReader.ParseBlockScalar(const AHeader: string; AParentIndent: Integer): TJSONValue;
var
  Folded, Strip, Keep: Boolean;
  Lines: TStringList;
  BlockIndent, I: Integer;
  Text, S: string;
begin
  Folded := AHeader[1] = '>';
  Strip := Pos('-', AHeader) > 0;
  Keep := Pos('+', AHeader) > 0;
  BlockIndent := -1;
  Lines := TStringList.Create;
  try
    while FPos < FLines.Count do
    begin
      if FLines[FPos].Indent < 0 then
        Lines.Add('')
      else if FLines[FPos].Indent > AParentIndent then
      begin
        if BlockIndent < 0 then
          BlockIndent := FLines[FPos].Indent;
        if FLines[FPos].Indent < BlockIndent then
          Break;
        // The raw line keeps a "#" that StripComment would cut.
        Lines.Add(Copy(FLines[FPos].Raw, BlockIndent + 1, MaxInt));
      end
      else
        Break;
      Inc(FPos);
    end;
    // Blank lines after the content are trailing, not content.
    while (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') do
      Lines.Delete(Lines.Count - 1);
    Text := '';
    for I := 0 to Lines.Count - 1 do
    begin
      S := Lines[I];
      if I = 0 then
        Text := S
      else if Folded and (S <> '') and (Lines[I - 1] <> '') then
        Text := Text + ' ' + S
      else
        Text := Text + #10 + S;
    end;
    if not Strip and (Text <> '') then
      Text := Text + #10;
    if Keep and (Text = '') then
      Text := '';
    Result := TJSONString.Create(Text);
  finally
    Lines.Free;
  end;
end;

function ParseYaml(const AText: string): TJSONValue;
var
  Reader: TYamlReader;
begin
  Reader := TYamlReader.Create(AText);
  try
    Result := Reader.Run;
  finally
    Reader.Free;
  end;
end;

end.
