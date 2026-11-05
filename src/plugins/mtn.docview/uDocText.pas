unit uDocText;

{ Plain-text views of document files for the built-in viewer: Office Open XML
  (docx, xlsx, pptx), SVG, SQLite databases and PDF. Every function returns
  '' when the file is not of the expected kind or holds nothing to show, so
  the host falls back to its own viewer. }

interface

uses
  System.SysUtils, System.Classes;

const
  cMaxViewRows = 200;

{ Text of a docx, xlsx or pptx archive; '' for anything else. }
function OfficeText(const APath: string): string;

{ Summary and indented source of an SVG file. }
function SvgText(const AText: string): string;

{ Schema and the first rows of every table of a SQLite database file. }
function SqliteText(const APath: string): string;

{ Text shown by the text operators of the PDF page streams. Fonts with their
  own encodings are not decoded, so such text comes out as it is stored. }
function PdfText(const ABytes: TBytes): string;

{ Helpers shared with the tests. }
function XmlDecode(const S: string): string;
function XmlRunsText(const AXml, ATextTag, AParaTag: string): string;
function ColumnIndexOfRef(const ARef: string): Integer;

implementation

uses
  System.Zip, System.ZLib, System.Math, System.StrUtils, System.Character, System.Generics.Defaults,
  System.Generics.Collections;

const
  cEol = #13#10;
  cIntSizes: array[0..5] of Integer = (1, 2, 3, 4, 6, 8);

{ ---- XML helpers ---- }

function XmlDecode(const S: string): string;
var
  I, J, Code: Integer;
  Ent: string;
begin
  if Pos('&', S) = 0 then
    Exit(S);
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] <> '&' then
    begin
      Result := Result + S[I];
      Inc(I);
      Continue;
    end;
    J := I + 1;
    while (J <= Length(S)) and (J - I <= 10) and (S[J] <> ';') do
      Inc(J);
    if (J > Length(S)) or (S[J] <> ';') then
    begin
      Result := Result + S[I];
      Inc(I);
      Continue;
    end;
    Ent := Copy(S, I + 1, J - I - 1);
    if Ent = 'amp' then Result := Result + '&'
    else if Ent = 'lt' then Result := Result + '<'
    else if Ent = 'gt' then Result := Result + '>'
    else if Ent = 'quot' then Result := Result + '"'
    else if Ent = 'apos' then Result := Result + ''''
    else if (Length(Ent) > 1) and (Ent[1] = '#') then
    begin
      if CharInSet(Ent[2], ['x', 'X']) then
        Code := StrToIntDef('$' + Copy(Ent, 3, MaxInt), -1)
      else
        Code := StrToIntDef(Copy(Ent, 2, MaxInt), -1);
      if (Code > 0) and (Code < $110000) then
        Result := Result + Char.ConvertFromUtf32(Code)
      else
        Result := Result + '&' + Ent + ';';
    end
    else
      Result := Result + '&' + Ent + ';';
    I := J + 1;
  end;
end;

{ Name of the tag that starts at AXml[APos] = '<'; '/name' for a closing tag. }
function TagName(const AXml: string; APos: Integer): string;
var
  J: Integer;
begin
  J := APos + 1;
  while (J <= Length(AXml)) and not CharInSet(AXml[J], [' ', #9, #10, #13, '/', '>']) do
    Inc(J);
  if (J <= Length(AXml)) and (AXml[APos + 1] = '/') then
  begin
    J := APos + 2;
    while (J <= Length(AXml)) and not CharInSet(AXml[J], [' ', #9, #10, #13, '>']) do
      Inc(J);
  end;
  Result := Copy(AXml, APos + 1, J - APos - 1);
end;

function XmlRunsText(const AXml, ATextTag, AParaTag: string): string;
var
  P, Q, E: Integer;
  Name, Closing: string;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    P := 1;
    while True do
    begin
      P := Pos('<', AXml, P);
      if P = 0 then
        Break;
      Q := Pos('>', AXml, P);
      if Q = 0 then
        Break;
      Name := TagName(AXml, P);
      if Name = ATextTag then
      begin
        if AXml[Q - 1] <> '/' then
        begin
          Closing := '</' + ATextTag + '>';
          E := Pos(Closing, AXml, Q);
          if E = 0 then
            Break;
          SB.Append(XmlDecode(Copy(AXml, Q + 1, E - Q - 1)));
          Q := E + Length(Closing) - 1;
        end;
      end
      else if Name = 'w:tab' then
        SB.Append(#9)
      else if (Name = 'w:br') or (Name = 'w:cr') or (Name = 'a:br') then
        SB.Append(cEol)
      else if Name = '/' + AParaTag then
        SB.Append(cEol);
      P := Q + 1;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function AttrValue(const ATag, AName: string): string;
var
  P, Q: Integer;
  Quote: Char;
begin
  Result := '';
  P := Pos(' ' + AName + '=', ATag);
  if P = 0 then
    Exit;
  Inc(P, Length(AName) + 2);
  if P > Length(ATag) then
    Exit;
  Quote := ATag[P];
  Q := Pos(Quote, ATag, P + 1);
  if (Q > 0) and CharInSet(Quote, ['"', '''']) then
    Result := XmlDecode(Copy(ATag, P + 1, Q - P - 1));
end;

{ Next <AName ...>...</AName> or <AName .../> at or after APos: the opening tag
  text and the inner XML; APos moves behind the element. }
function NextElement(const AXml, AName: string; var APos: Integer;
  out ATag, AInner: string): Boolean;
var
  P, Q, E: Integer;
  Closing: string;
begin
  Result := False;
  ATag := '';
  AInner := '';
  P := APos;
  while True do
  begin
    P := Pos('<' + AName, AXml, P);
    if P = 0 then
      Exit;
    if (P + Length(AName) + 1 <= Length(AXml)) and
       CharInSet(AXml[P + Length(AName) + 1], [' ', #9, #10, #13, '>', '/']) then
      Break;
    Inc(P);
  end;
  Q := Pos('>', AXml, P);
  if Q = 0 then
    Exit;
  ATag := Copy(AXml, P, Q - P + 1);
  if AXml[Q - 1] = '/' then
    APos := Q + 1
  else
  begin
    Closing := '</' + AName + '>';
    E := Pos(Closing, AXml, Q);
    if E = 0 then
      Exit;
    AInner := Copy(AXml, Q + 1, E - Q - 1);
    APos := E + Length(Closing);
  end;
  Result := True;
end;

function ColumnIndexOfRef(const ARef: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(ARef) do
    if CharInSet(ARef[I], ['A'..'Z']) then
      Result := Result * 26 + Ord(ARef[I]) - Ord('A') + 1
    else if CharInSet(ARef[I], ['a'..'z']) then
      Result := Result * 26 + Ord(ARef[I]) - Ord('a') + 1
    else
      Break;
  Dec(Result);
end;

{ ---- Office Open XML ---- }

function ReadEntry(AZip: TZipFile; const AName: string): string;
var
  Bytes: TBytes;
begin
  Result := '';
  try
    AZip.Read(AName, Bytes);
    Result := TEncoding.UTF8.GetString(Bytes);
  except
    Result := '';
  end;
end;

function HasEntry(AZip: TZipFile; const AName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to AZip.FileCount - 1 do
    if SameText(AZip.FileName[I], AName) then
      Exit(True);
  Result := False;
end;

type
  TNumberedName = record
    Number: Integer;
    Name: string;
  end;

{ Entries named <APrefix><number>.xml, ordered by the number (sheet2 before sheet10). }
function NumberedEntries(AZip: TZipFile; const APrefix: string): TArray<string>;
var
  I: Integer;
  Items: TList<TNumberedName>;
  Item: TNumberedName;
  Rest: string;
begin
  Items := TList<TNumberedName>.Create;
  try
    for I := 0 to AZip.FileCount - 1 do
    begin
      Item.Name := AZip.FileName[I];
      if not SameText(Copy(Item.Name, 1, Length(APrefix)), APrefix) then
        Continue;
      Rest := Copy(Item.Name, Length(APrefix) + 1, MaxInt);
      if not SameText(ExtractFileExt(Rest), '.xml') then
        Continue;
      Item.Number := StrToIntDef(ChangeFileExt(Rest, ''), -1);
      if Item.Number >= 0 then
        Items.Add(Item);
    end;
    Items.Sort(TComparer<TNumberedName>.Construct(
      function(const L, R: TNumberedName): Integer
      begin
        Result := L.Number - R.Number;
      end));
    SetLength(Result, Items.Count);
    for I := 0 to Items.Count - 1 do
      Result[I] := Items[I].Name;
  finally
    Items.Free;
  end;
end;

function SharedStrings(const AXml: string): TArray<string>;
var
  P: Integer;
  Tag, Inner, Clean: string;
  R1, R2: Integer;
  Items: TList<string>;
begin
  Items := TList<string>.Create;
  try
    P := 1;
    while NextElement(AXml, 'si', P, Tag, Inner) do
    begin
      Clean := Inner;
      repeat
        R1 := Pos('<rPh', Clean);
        if R1 = 0 then
          Break;
        R2 := Pos('</rPh>', Clean, R1);
        if R2 = 0 then
          Break;
        Delete(Clean, R1, R2 + 5 - R1);
      until False;
      Items.Add(XmlRunsText(Clean, 't', 'si'));
    end;
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function SheetNames(const AWorkbookXml: string): TArray<string>;
var
  P: Integer;
  Tag, Inner: string;
  Items: TList<string>;
begin
  Items := TList<string>.Create;
  try
    P := 1;
    while NextElement(AWorkbookXml, 'sheet', P, Tag, Inner) do
      Items.Add(AttrValue(Tag, 'name'));
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function SheetText(const AXml: string; const AShared: TArray<string>; var ARows: Integer): string;
var
  PRow, PCell, Col, Idx, MaxCol: Integer;
  RowTag, RowInner, CellTag, CellInner, Kind, Value, Ref: string;
  PV: Integer;
  VTag, VInner: string;
  Cells: TStringList;
  SB: TStringBuilder;
  Line: string;
begin
  SB := TStringBuilder.Create;
  Cells := TStringList.Create;
  try
    PRow := 1;
    while (ARows < 100000) and NextElement(AXml, 'row', PRow, RowTag, RowInner) do
    begin
      Cells.Clear;
      PCell := 1;
      Col := 0;
      MaxCol := -1;
      while NextElement(RowInner, 'c', PCell, CellTag, CellInner) do
      begin
        Ref := AttrValue(CellTag, 'r');
        if Ref <> '' then
          Col := ColumnIndexOfRef(Ref);
        Kind := AttrValue(CellTag, 't');
        Value := '';
        PV := 1;
        if Kind = 'inlineStr' then
          Value := TrimRight(XmlRunsText(CellInner, 't', 'is'))
        else if NextElement(CellInner, 'v', PV, VTag, VInner) then
        begin
          Value := XmlDecode(VInner);
          if Kind = 's' then
          begin
            Idx := StrToIntDef(Value, -1);
            if (Idx >= 0) and (Idx < Length(AShared)) then
              Value := AShared[Idx];
          end
          else if Kind = 'b' then
            Value := IfThen(Value = '1', 'TRUE', 'FALSE');
        end;
        Value := Value.Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
        while Cells.Count <= Col do
          Cells.Add('');
        Cells[Col] := Value;
        MaxCol := Max(MaxCol, Col);
        Inc(Col);
      end;
      if MaxCol < 0 then
        Continue;
      Line := '';
      for Col := 0 to Cells.Count - 1 do
        Line := Line + IfThen(Col > 0, #9, '') + Cells[Col];
      SB.Append(Line).Append(cEol);
      Inc(ARows);
    end;
    Result := SB.ToString;
  finally
    Cells.Free;
    SB.Free;
  end;
end;

function OfficeText(const APath: string): string;
var
  Zip: TZipFile;
  Ext, Part, Sheet: string;
  Sheets, Slides: TArray<string>;
  Shared: TArray<string>;
  I, Rows: Integer;
  SB: TStringBuilder;
  SheetTitles: TArray<string>;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(APath));
  Zip := TZipFile.Create;
  try
    try
      Zip.Open(APath, zmRead);
    except
      Exit;
    end;
    if Ext = '.docx' then
    begin
      if HasEntry(Zip, 'word/document.xml') then
        Result := XmlRunsText(ReadEntry(Zip, 'word/document.xml'), 'w:t', 'w:p');
    end
    else if Ext = '.pptx' then
    begin
      Slides := NumberedEntries(Zip, 'ppt/slides/slide');
      SB := TStringBuilder.Create;
      try
        for I := 0 to High(Slides) do
        begin
          SB.Append(Format('=== Slide %d ===', [I + 1])).Append(cEol);
          SB.Append(XmlRunsText(ReadEntry(Zip, Slides[I]), 'a:t', 'a:p')).Append(cEol);
        end;
        Result := SB.ToString;
      finally
        SB.Free;
      end;
    end
    else if Ext = '.xlsx' then
    begin
      Shared := nil;
      if HasEntry(Zip, 'xl/sharedStrings.xml') then
        Shared := SharedStrings(ReadEntry(Zip, 'xl/sharedStrings.xml'));
      SheetTitles := SheetNames(ReadEntry(Zip, 'xl/workbook.xml'));
      Sheets := NumberedEntries(Zip, 'xl/worksheets/sheet');
      SB := TStringBuilder.Create;
      try
        for I := 0 to High(Sheets) do
        begin
          if I <= High(SheetTitles) then
            Part := SheetTitles[I]
          else
            Part := Format('Sheet%d', [I + 1]);
          Rows := 0;
          Sheet := SheetText(ReadEntry(Zip, Sheets[I]), Shared, Rows);
          SB.Append('=== ').Append(Part).Append(' ===').Append(cEol).Append(Sheet).Append(cEol);
        end;
        Result := SB.ToString;
      finally
        SB.Free;
      end;
    end;
    if Trim(Result) = '' then
      Result := '';
  finally
    Zip.Free;
  end;
end;

{ ---- SVG ---- }

function CountOf(const AText, ATag: string): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := 1;
  while True do
  begin
    P := Pos('<' + ATag, AText, P);
    if P = 0 then
      Exit;
    if (P + Length(ATag) + 1 <= Length(AText)) and
       CharInSet(AText[P + Length(ATag) + 1], [' ', #9, #10, #13, '>', '/']) then
      Inc(Result);
    Inc(P);
  end;
end;

{ AText with the white space between a '>' and the next '<' removed and line
  breaks inside tags turned into spaces. }
function DropGapsBetweenTags(const AText: string): string;
var
  I, J, N: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    N := Length(AText);
    I := 1;
    while I <= N do
    begin
      if AText[I] = '>' then
      begin
        SB.Append('>');
        J := I + 1;
        while (J <= N) and CharInSet(AText[J], [' ', #9, #10, #13]) do
          Inc(J);
        if (J <= N) and (AText[J] = '<') then
          I := J
        else
          I := I + 1;
        Continue;
      end;
      if CharInSet(AText[I], [#13, #10]) then
        SB.Append(' ')
      else
        SB.Append(AText[I]);
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function PrettyXml(const AText: string): string;
var
  Pieces: TArray<string>;
  Piece, Flat: string;
  Depth, I: Integer;
  SB: TStringBuilder;
begin
  Flat := DropGapsBetweenTags(AText);
  Pieces :=Flat.Replace('><', '>'#1'<').Split([#1]);
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    for I := 0 to High(Pieces) do
    begin
      Piece := Trim(Pieces[I]);
      if Piece = '' then
        Continue;
      if (Copy(Piece, 1, 2) = '</') then
        Depth := Max(0, Depth - 1);
      SB.Append(StringOfChar(' ', Depth * 2)).Append(Piece).Append(cEol);
      if (Copy(Piece, 1, 2) = '</') or (Copy(Piece, 1, 2) = '<?') or
         (Copy(Piece, 1, 2) = '<!') or (Copy(Piece, Length(Piece) - 1, 2) = '/>') or
         (Pos('</', Piece) > 1) then
        // closes itself, is a declaration, or holds its text inline
      else
        Inc(Depth);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function SvgText(const AText: string): string;
const
  cShapes: array[0..10] of string = ('g', 'path', 'rect', 'circle', 'ellipse', 'line',
    'polyline', 'polygon', 'text', 'image', 'use');
var
  P, Q, I, N, MaxLine: Integer;
  Tag, Value, Inner, Dummy, Source: string;
  SB: TStringBuilder;
  Lines: TArray<string>;
  L: string;
begin
  Result := '';
  P := Pos('<svg', AText);
  if P = 0 then
    Exit;
  Q := Pos('>', AText, P);
  if Q = 0 then
    Exit;
  Tag := Copy(AText, P, Q - P + 1);
  SB := TStringBuilder.Create;
  try
    SB.Append('SVG image').Append(cEol);
    for Value in ['width', 'height', 'viewBox'] do
      if AttrValue(Tag, Value) <> '' then
        SB.Append(Format('  %s: %s', [Value, AttrValue(Tag, Value)])).Append(cEol);
    Dummy := '';
    for I := Low(cShapes) to High(cShapes) do
    begin
      N := CountOf(AText, cShapes[I]);
      if N > 0 then
        Dummy := Dummy + Format('%s %d, ', [cShapes[I], N]);
    end;
    if Dummy <> '' then
      SB.Append('  elements: ').Append(Copy(Dummy, 1, Length(Dummy) - 2)).Append(cEol);
    P := 1;
    if NextElement(AText, 'title', P, Tag, Inner) and (Inner <> '') then
      SB.Append('  title: ').Append(XmlDecode(Inner)).Append(cEol);
    P := 1;
    if NextElement(AText, 'desc', P, Tag, Inner) and (Inner <> '') then
      SB.Append('  description: ').Append(XmlDecode(Inner)).Append(cEol);
    Inner := Trim(XmlRunsText(AText, 'text', 'text')).Replace(cEol, ' | ');
    if Inner <> '' then
      SB.Append('  text: ').Append(Copy(Inner, 1, 300)).Append(cEol);
    SB.Append(cEol).Append('--- source ---').Append(cEol);
    Lines := AText.Split([#10]);
    MaxLine := 0;
    for L in Lines do
      MaxLine := Max(MaxLine, Length(L));
    if MaxLine > 300 then
      Source := PrettyXml(AText)
    else
      Source := AText;
    SB.Append(Source);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---- SQLite ---- }

type
  TSqliteFile = class
  private
    FStream: TStream;
    FPageSize: Integer;
    FUsable: Integer;
    FEncoding: Integer;
    FPageCount: Integer;
    function Page(ANo: Integer): TBytes;
    function ReadPayload(const APage: TBytes; AOffset: Integer; APayload: Int64;
      ALeaf: Boolean): TBytes;
  public
    constructor Create(AStream: TStream);
    function Valid: Boolean;
    { Calls AEmit for the first ALimit rows (rowid, payload); returns the total. }
    function Walk(ARoot, ALimit: Integer; AEmit: TProc<Int64, TBytes>): Int64;
    function DecodeText(const ABytes: TBytes): string;
    function Record_(const APayload: TBytes): TArray<string>;
    property PageCount: Integer read FPageCount;
  end;

function BE16(const B: TBytes; O: Integer): Integer;
begin
  Result := (B[O] shl 8) or B[O + 1];
end;

function BE32(const B: TBytes; O: Integer): Cardinal;
begin
  Result := (Cardinal(B[O]) shl 24) or (Cardinal(B[O + 1]) shl 16) or
    (Cardinal(B[O + 2]) shl 8) or Cardinal(B[O + 3]);
end;

{ Variable-length integer at O; moves O behind it. }
function Varint(const B: TBytes; var O: Integer): Int64;
var
  I: Integer;
  V: UInt64;
begin
  V := 0;
  for I := 0 to 7 do
  begin
    if O >= Length(B) then
      Exit(0);
    V := (V shl 7) or (B[O] and $7F);
    Inc(O);
    if B[O - 1] < $80 then
      Exit(Int64(V));
  end;
  if O >= Length(B) then
    Exit(0);
  V := (V shl 8) or B[O];
  Inc(O);
  Result := Int64(V);
end;

constructor TSqliteFile.Create(AStream: TStream);
var
  H: TBytes;
begin
  inherited Create;
  FStream := AStream;
  SetLength(H, 100);
  FPageSize := 0;
  if (AStream.Size >= 512) then
  begin
    AStream.Position := 0;
    AStream.ReadBuffer(H[0], 100);
    if (TEncoding.ASCII.GetString(H, 0, 15) = 'SQLite format 3') and (H[15] = 0) then
    begin
      FPageSize := BE16(H, 16);
      if FPageSize = 1 then
        FPageSize := 65536;
      FUsable := FPageSize - H[20];
      FEncoding := Integer(BE32(H, 56));
      FPageCount := Integer(AStream.Size div Max(FPageSize, 1));
    end;
  end;
end;

function TSqliteFile.Valid: Boolean;
begin
  Result := (FPageSize >= 512) and (FPageSize <= 65536) and
    ((FPageSize and (FPageSize - 1)) = 0) and (FUsable >= 480);
end;

function TSqliteFile.Page(ANo: Integer): TBytes;
begin
  SetLength(Result, 0);
  if (ANo < 1) or (ANo > FPageCount) then
    Exit;
  SetLength(Result, FPageSize);
  FStream.Position := Int64(ANo - 1) * FPageSize;
  FStream.ReadBuffer(Result[0], FPageSize);
end;

{ The payload of a cell that starts at AOffset (after its size and rowid),
  following the overflow chain. }
function TSqliteFile.ReadPayload(const APage: TBytes; AOffset: Integer;
  APayload: Int64; ALeaf: Boolean): TBytes;
var
  X, M, K, Local, Got, Chunk: Integer;
  Next: Cardinal;
  Ov: TBytes;
  Guard: Integer;
begin
  SetLength(Result, 0);
  if (APayload < 0) or (APayload > 64 * 1024 * 1024) then
    Exit;
  X := FUsable - 35;
  if APayload <= X then
    Local := Integer(APayload)
  else
  begin
    M := ((FUsable - 12) * 32 div 255) - 23;
    K := M + Integer((APayload - M) mod (FUsable - 4));
    if K <= X then Local := K else Local := M;
  end;
  if AOffset + Local > Length(APage) then
    Exit;
  SetLength(Result, Integer(APayload));
  Move(APage[AOffset], Result[0], Local);
  Got := Local;
  if Got < APayload then
  begin
    if AOffset + Local + 4 > Length(APage) then
      Exit(nil);
    Next := BE32(APage, AOffset + Local);
    Guard := 0;
    while (Got < APayload) and (Next <> 0) and (Guard < 100000) do
    begin
      Ov := Page(Integer(Next));
      if Length(Ov) = 0 then
        Break;
      Chunk := Min(FUsable - 4, Integer(APayload) - Got);
      Move(Ov[4], Result[Got], Chunk);
      Inc(Got, Chunk);
      Next := BE32(Ov, 0);
      Inc(Guard);
    end;
    if Got < APayload then
      SetLength(Result, Got);
  end;
end;

function TSqliteFile.Walk(ARoot, ALimit: Integer; AEmit: TProc<Int64, TBytes>): Int64;
var
  Emitted: Integer;
  Visited: Integer;

  procedure Visit(APageNo, ADepth: Integer);
  var
    Pg: TBytes;
    Hdr, Cnt, I, Cell, O: Integer;
    Kind: Byte;
    Size, RowId: Int64;
    Child: Cardinal;
  begin
    Inc(Visited);
    if (ADepth > 24) or (Visited > 2000000) then
      Exit;
    Pg := Page(APageNo);
    if Length(Pg) = 0 then
      Exit;
    Hdr := IfThen(APageNo = 1, 100, 0);
    Kind := Pg[Hdr];
    Cnt := BE16(Pg, Hdr + 3);
    if Kind = 13 then
    begin
      for I := 0 to Cnt - 1 do
      begin
        if Hdr + 8 + I * 2 + 2 > Length(Pg) then
          Break;
        Cell := BE16(Pg, Hdr + 8 + I * 2);
        if Emitted < ALimit then
        begin
          O := Cell;
          Size := Varint(Pg, O);
          RowId := Varint(Pg, O);
          AEmit(RowId, ReadPayload(Pg, O, Size, True));
          Inc(Emitted);
        end;
        Inc(Result);
      end;
    end
    else if Kind = 5 then
    begin
      for I := 0 to Cnt - 1 do
      begin
        if Hdr + 12 + I * 2 + 2 > Length(Pg) then
          Break;
        Cell := BE16(Pg, Hdr + 12 + I * 2);
        Child := BE32(Pg, Cell);
        Visit(Integer(Child), ADepth + 1);
        if (Emitted >= ALimit) and (Visited > 2000000) then
          Exit;
      end;
      Visit(Integer(BE32(Pg, Hdr + 8)), ADepth + 1);
    end;
  end;

begin
  Result := 0;
  Emitted := 0;
  Visited := 0;
  Visit(ARoot, 0);
end;

function TSqliteFile.DecodeText(const ABytes: TBytes): string;
begin
  case FEncoding of
    2: Result := TEncoding.Unicode.GetString(ABytes);
    3: Result := TEncoding.BigEndianUnicode.GetString(ABytes);
  else
    Result := TEncoding.UTF8.GetString(ABytes);
  end;
end;

function TSqliteFile.Record_(const APayload: TBytes): TArray<string>;
var
  HdrSize, O, DataO, Cnt, I, N: Integer;
  Types: TArray<Int64>;
  T: Int64;
  Iv: Int64;
  D: Double;
  Bytes: TBytes;
begin
  SetLength(Result, 0);
  if Length(APayload) = 0 then
    Exit;
  O := 0;
  HdrSize := Integer(Varint(APayload, O));
  if (HdrSize <= 0) or (HdrSize > Length(APayload)) then
    Exit;
  Cnt := 0;
  SetLength(Types, 0);
  while O < HdrSize do
  begin
    SetLength(Types, Cnt + 1);
    Types[Cnt] := Varint(APayload, O);
    Inc(Cnt);
  end;
  SetLength(Result, Cnt);
  DataO := HdrSize;
  for I := 0 to Cnt - 1 do
  begin
    T := Types[I];
    case T of
      0: Result[I] := 'NULL';
      1..6:
        begin
          N := cIntSizes[Integer(T) - 1];
          if DataO + N > Length(APayload) then Exit;
          Iv := Int8(APayload[DataO]);
          for O := 1 to N - 1 do
            Iv := (Iv shl 8) or APayload[DataO + O];
          Result[I] := IntToStr(Iv);
          Inc(DataO, N);
        end;
      7:
        begin
          if DataO + 8 > Length(APayload) then Exit;
          Iv := 0;
          for O := 0 to 7 do
            Iv := (Iv shl 8) or APayload[DataO + O];
          Move(Iv, D, 8);
          Result[I] := FloatToStr(D, TFormatSettings.Invariant);
          Inc(DataO, 8);
        end;
      8: Result[I] := '0';
      9: Result[I] := '1';
    else
      if T < 12 then
        Result[I] := '?'
      else
      begin
        N := Integer((T - 12) div 2);
        if DataO + N > Length(APayload) then Exit;
        if Odd(T) then
        begin
          SetLength(Bytes, N);
          if N > 0 then
            Move(APayload[DataO], Bytes[0], N);
          Result[I] := DecodeText(Bytes);
        end
        else
          Result[I] := Format('<blob %d bytes>', [N]);
        Inc(DataO, N);
      end;
    end;
  end;
end;

{ Column names of a CREATE TABLE statement and the index of the column that is
  the rowid alias (INTEGER PRIMARY KEY), -1 when there is none. }
procedure ParseColumns(const ASql: string; out ANames: TArray<string>; out ARowIdCol: Integer);
var
  P1, P2, I, Depth, Start: Integer;
  Body, Def, First: string;
  Parts: TList<string>;
  Names: TList<string>;
  Upper: string;
begin
  SetLength(ANames, 0);
  ARowIdCol := -1;
  P1 := Pos('(', ASql);
  P2 := LastDelimiter(')', ASql);
  if (P1 = 0) or (P2 <= P1) then
    Exit;
  Body := Copy(ASql, P1 + 1, P2 - P1 - 1);
  Parts := TList<string>.Create;
  Names := TList<string>.Create;
  try
    Depth := 0;
    Start := 1;
    for I := 1 to Length(Body) do
    begin
      if Body[I] = '(' then Inc(Depth)
      else if Body[I] = ')' then Dec(Depth)
      else if (Body[I] = ',') and (Depth = 0) then
      begin
        Parts.Add(Trim(Copy(Body, Start, I - Start)));
        Start := I + 1;
      end;
    end;
    Parts.Add(Trim(Copy(Body, Start, MaxInt)));
    for Def in Parts do
    begin
      Upper := UpperCase(Def);
      if (Upper = '') or (Pos('CONSTRAINT ', Upper) = 1) or (Pos('PRIMARY KEY', Upper) = 1) or
         (Pos('UNIQUE', Upper) = 1) or (Pos('CHECK', Upper) = 1) or (Pos('FOREIGN KEY', Upper) = 1) then
        Continue;
      I := 1;
      if CharInSet(Def[1], ['"', '`', '[']) then
      begin
        I := 2;
        while (I <= Length(Def)) and not CharInSet(Def[I], ['"', '`', ']']) do
          Inc(I);
        First := Copy(Def, 2, I - 2);
      end
      else
      begin
        while (I <= Length(Def)) and not CharInSet(Def[I], [' ', #9]) do
          Inc(I);
        First := Copy(Def, 1, I - 1);
      end;
      Names.Add(First);
      if (Pos('INTEGER PRIMARY KEY', Upper) > 0) and (ARowIdCol < 0) then
        ARowIdCol := Names.Count - 1;
    end;
    if Pos('WITHOUT ROWID', UpperCase(ASql)) > 0 then
      ARowIdCol := -1;
    ANames := Names.ToArray;
  finally
    Names.Free;
    Parts.Free;
  end;
end;

function CellText(const S: string): string;
begin
  Result := S.Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
  if Length(Result) > 100 then
    Result := Copy(Result, 1, 97) + '...';
end;

type
  TSchemaEntry = record
    Kind, Name, TableName, Sql: string;
    Root: Integer;
  end;

function SqliteText(const APath: string): string;
var
  Stream: TFileStream;
  Db: TSqliteFile;
  Schema: TList<TSchemaEntry>;
  E: TSchemaEntry;
  SB: TStringBuilder;
  Total: Int64;
  Names: TArray<string>;
  RowIdCol, I: Integer;
begin
  Result := '';
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    Db := TSqliteFile.Create(Stream);
    try
      if not Db.Valid then
        Exit;
      Schema := TList<TSchemaEntry>.Create;
      SB := TStringBuilder.Create;
      try
        Db.Walk(1, MaxInt,
          procedure(ARowId: Int64; APayload: TBytes)
          var
            F: TArray<string>;
            Entry: TSchemaEntry;
          begin
            F := Db.Record_(APayload);
            if Length(F) < 5 then
              Exit;
            Entry.Kind := F[0];
            Entry.Name := F[1];
            Entry.TableName := F[2];
            Entry.Root := StrToIntDef(F[3], 0);
            Entry.Sql := F[4];
            Schema.Add(Entry);
          end);
        if Schema.Count = 0 then
          Exit;
        SB.Append(Format('SQLite database: %d page(s) of %d bytes, %d object(s)',
          [Db.PageCount, Db.FPageSize, Schema.Count])).Append(cEol).Append(cEol);
        for E in Schema do
        begin
          if (E.Kind = 'table') and (Pos('sqlite_', E.Name) <> 1) and (E.Root > 0) then
          begin
            ParseColumns(E.Sql, Names, RowIdCol);
            SB.Append('=== table ').Append(E.Name).Append(' ===').Append(cEol);
            SB.Append(E.Sql).Append(cEol);
            SB.Append(StringOfChar('-', 40)).Append(cEol);
            if Length(Names) > 0 then
            begin
              for I := 0 to High(Names) do
                SB.Append(IfThen(I > 0, #9, '')).Append(Names[I]);
              SB.Append(cEol);
            end;
            Total := Db.Walk(E.Root, cMaxViewRows,
              procedure(ARowId: Int64; APayload: TBytes)
              var
                F: TArray<string>;
                J: Integer;
              begin
                F := Db.Record_(APayload);
                for J := 0 to High(F) do
                begin
                  if J > 0 then
                    SB.Append(#9);
                  if (J = RowIdCol) and (F[J] = 'NULL') then
                    SB.Append(IntToStr(ARowId))
                  else
                    SB.Append(CellText(F[J]));
                end;
                SB.Append(cEol);
              end);
            if Total > cMaxViewRows then
              SB.Append(Format('... %d rows, the first %d are shown', [Total, cMaxViewRows])).Append(cEol)
            else
              SB.Append(Format('(%d rows)', [Total])).Append(cEol);
            SB.Append(cEol);
          end;
        end;
        for E in Schema do
          if (E.Kind <> 'table') and (E.Sql <> '') then
            SB.Append(E.Kind).Append(' ').Append(E.Name).Append(': ').Append(CellText(E.Sql)).Append(cEol);
        Result := SB.ToString;
      finally
        SB.Free;
        Schema.Free;
      end;
    finally
      Db.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{ ---- PDF ---- }

function InflateBytes(const ASrc: TBytes; AStart, ALen: Integer): TBytes;
var
  InS: TBytesStream;
  Z: TZDecompressionStream;
  Buf: array[0..16383] of Byte;
  N: Integer;
  Out_: TBytesStream;
begin
  SetLength(Result, 0);
  InS := TBytesStream.Create;
  Out_ := TBytesStream.Create;
  try
    InS.WriteBuffer(ASrc[AStart], ALen);
    InS.Position := 0;
    Z := TZDecompressionStream.Create(InS);
    try
      try
        repeat
          N := Z.Read(Buf, SizeOf(Buf));
          if N > 0 then
            Out_.WriteBuffer(Buf, N);
        until (N <= 0) or (Out_.Size > 64 * 1024 * 1024);
      except
        // A damaged stream keeps what was read before the error.
      end;
    finally
      Z.Free;
    end;
    Result := Copy(Out_.Bytes, 0, Out_.Size);
  finally
    Out_.Free;
    InS.Free;
  end;
end;

function Latin1(const B: TBytes; AStart, ALen: Integer): string;
var
  I: Integer;
begin
  SetLength(Result, ALen);
  for I := 0 to ALen - 1 do
    Result[I + 1] := Char(B[AStart + I]);
end;

{ Text drawn by the text operators of one content stream. }
function ContentText(const S: string): string;
var
  I, N, Depth, Depth2: Integer;
  SB: TStringBuilder;
  Strs: TStringBuilder;
  Num: array[0..1] of string;
  NumCount: Integer;
  Tok: string;
  InArray: Boolean;
  Ch: Char;
  Hex: string;
  Code: Integer;

  procedure Emit(const AText: string);
  begin
    SB.Append(AText);
  end;

  procedure Newline;
  begin
    if (SB.Length > 0) and (SB.Chars[SB.Length - 1] <> #10) then
      SB.Append(cEol);
  end;

  procedure SpaceIfNeeded;
  begin
    if (SB.Length > 0) and not CharInSet(SB.Chars[SB.Length - 1], [' ', #10]) then
      SB.Append(' ');
  end;

begin
  SB := TStringBuilder.Create;
  Strs := TStringBuilder.Create;
  try
    N := Length(S);
    I := 1;
    NumCount := 0;
    InArray := False;
    while I <= N do
    begin
      Ch := S[I];
      case Ch of
        #0, #9, #10, #12, #13, ' ':
          Inc(I);
        '(':
          begin
            Depth := 1;
            Inc(I);
            while (I <= N) and (Depth > 0) do
            begin
              Ch := S[I];
              if Ch = '\' then
              begin
                Inc(I);
                if I > N then Break;
                case S[I] of
                  'n': Strs.Append(' ');
                  'r', 't', 'b', 'f': Strs.Append(' ');
                  '0'..'7':
                    begin
                      Hex := '';
                      while (I <= N) and (Length(Hex) < 3) and CharInSet(S[I], ['0'..'7']) do
                      begin
                        Hex := Hex + S[I];
                        Inc(I);
                      end;
                      Dec(I);
                      Code := 0;
                      for Depth2 := 1 to Length(Hex) do
                        Code := Code * 8 + Ord(Hex[Depth2]) - Ord('0');
                      Strs.Append(Char(Code and $FF));
                    end;
                  #13, #10: ;
                else
                  Strs.Append(S[I]);
                end;
              end
              else if Ch = '(' then
              begin
                Inc(Depth);
                Strs.Append(Ch);
              end
              else if Ch = ')' then
              begin
                Dec(Depth);
                if Depth > 0 then
                  Strs.Append(Ch);
              end
              else
                Strs.Append(Ch);
              Inc(I);
            end;
          end;
        '<':
          if (I < N) and (S[I + 1] = '<') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Hex := '';
            while (I <= N) and (S[I] <> '>') do
            begin
              if CharInSet(S[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
                Hex := Hex + S[I];
              Inc(I);
            end;
            Inc(I);
            if Odd(Length(Hex)) then
              Hex := Hex + '0';
            Code := 1;
            while Code < Length(Hex) do
            begin
              if StrToInt('$' + Copy(Hex, Code, 2)) >= 32 then
                Strs.Append(Char(StrToInt('$' + Copy(Hex, Code, 2))));
              Inc(Code, 2);
            end;
          end;
        '>':
          Inc(I);
        '[':
          begin
            InArray := True;
            Inc(I);
          end;
        ']':
          begin
            InArray := False;
            Inc(I);
          end;
        '/':
          begin
            Inc(I);
            while (I <= N) and not CharInSet(S[I], [' ', #9, #10, #13, '/', '[', ']', '(', '<', '>']) do
              Inc(I);
            NumCount := 0;
          end;
        '%':
          while (I <= N) and not CharInSet(S[I], [#10, #13]) do
            Inc(I);
        '-', '+', '.', '0'..'9':
          begin
            Tok := '';
            while (I <= N) and CharInSet(S[I], ['-', '+', '.', '0'..'9']) do
            begin
              Tok := Tok + S[I];
              Inc(I);
            end;
            if InArray then
            begin
              if (StrToFloatDef(Tok, 0, TFormatSettings.Invariant) < -200) and (Strs.Length > 0) then
                Strs.Append(' ');
            end
            else
            begin
              Num[0] := Num[1];
              Num[1] := Tok;
              Inc(NumCount);
            end;
          end;
      else
        begin
          Tok := '';
          while (I <= N) and not CharInSet(S[I], [' ', #9, #10, #13, #0, '/', '[', ']', '(', '<', '>', '%']) do
          begin
            Tok := Tok + S[I];
            Inc(I);
          end;
          if Tok = '' then
          begin
            Inc(I);
            Continue;
          end;
          if (Tok = 'Tj') or (Tok = 'TJ') then
          begin
            Emit(Strs.ToString);
            Strs.Clear;
          end
          else if (Tok = '''') or (Tok = '"') then
          begin
            Newline;
            Emit(Strs.ToString);
            Strs.Clear;
          end
          else if (Tok = 'T*') or (Tok = 'Tm') then
          begin
            Newline;
            Strs.Clear;
          end
          else if (Tok = 'Td') or (Tok = 'TD') then
          begin
            if (NumCount >= 2) and (StrToFloatDef(Num[1], 0, TFormatSettings.Invariant) <> 0) then
              Newline
            else
              SpaceIfNeeded;
            Strs.Clear;
          end
          else if Tok = 'ET' then
          begin
            Newline;
            Strs.Clear;
          end
          else
            Strs.Clear;
          NumCount := 0;
        end;
      end;
    end;
    Result := SB.ToString;
  finally
    Strs.Free;
    SB.Free;
  end;
end;

function PdfText(const ABytes: TBytes): string;
var
  Raw: string;
  P, Q, StreamStart, StreamEnd, DictStart: Integer;
  Dict: string;
  Data: TBytes;
  Part: string;
  SB: TStringBuilder;
begin
  Result := '';
  if (Length(ABytes) < 8) or (Latin1(ABytes, 0, 5) <> '%PDF-') then
    Exit;
  Raw := Latin1(ABytes, 0, Length(ABytes));
  SB := TStringBuilder.Create;
  try
    P := 1;
    while True do
    begin
      P := Pos('stream', Raw, P);
      if P = 0 then
        Break;
      if (P > 3) and (Copy(Raw, P - 3, 3) = 'end') then
      begin
        Inc(P, 6);
        Continue;
      end;
      StreamStart := P + 6;
      if (StreamStart <= Length(Raw)) and (Raw[StreamStart] = #13) then Inc(StreamStart);
      if (StreamStart <= Length(Raw)) and (Raw[StreamStart] = #10) then Inc(StreamStart);
      StreamEnd := Pos('endstream', Raw, StreamStart);
      if StreamEnd = 0 then
        Break;
      // The dictionary sits between "obj" and "stream".
      DictStart := P - 1;
      while (DictStart > 3) and (P - DictStart < 4000) and (Copy(Raw, DictStart - 2, 3) <> 'obj') do
        Dec(DictStart);
      Dict := Copy(Raw, DictStart, P - DictStart);
      Q := StreamEnd;
      if (Pos('/Subtype/Image', Dict.Replace(' ', '')) = 0) and
         (Pos('/FontFile', Dict) = 0) and (Pos('/Length1', Dict) = 0) then
      begin
        if Pos('/FlateDecode', Dict) > 0 then
          Data := InflateBytes(ABytes, StreamStart - 1, StreamEnd - StreamStart)
        else
        begin
          SetLength(Data, StreamEnd - StreamStart);
          if Length(Data) > 0 then
            Move(ABytes[StreamStart - 1], Data[0], Length(Data));
        end;
        if (Length(Data) > 0) and (Pos('BT', Latin1(Data, 0, Min(Length(Data), 4000000))) > 0) then
        begin
          Part := ContentText(Latin1(Data, 0, Length(Data)));
          if Trim(Part) <> '' then
            SB.Append(Part).Append(cEol);
        end;
      end;
      P := Q + 9;
    end;
    Result := SB.ToString;
    if Trim(Result) = '' then
      Result := '';
  finally
    SB.Free;
  end;
end;

end.
