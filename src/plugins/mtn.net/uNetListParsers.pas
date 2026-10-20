unit uNetListParsers;

{ Parsers of what servers send back when a folder is listed: FTP LIST output
  (Unix and DOS styles) and MLSD, the long names an SFTP server gives, WebDAV
  PROPFIND answers and S3 list results. Pure functions on text, no I/O.

  Times without a zone (ls, DOS) are kept as the digits the server printed:
  they are stored so that the host, which converts to local time for display,
  shows the same digits. Times with a zone (MLSD, HTTP dates, ISO 8601) are
  converted properly. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, uNetTypes;

type
  /// <summary>Element tree of a small XML document: names are local names
  /// (prefix dropped) in lower case, Text is the text directly inside.</summary>
  TXmlNode = class
  public
    Name: string;
    Text: string;
    Children: TObjectList<TXmlNode>;
    constructor Create(const AName: string);
    destructor Destroy; override;
    function Find(const AName: string): TXmlNode;
    function ChildText(const AName: string): string;
    procedure FindAll(const AName: string; AList: TList<TXmlNode>);
  end;

/// <summary>Parses AXml; nil when it is not well formed enough to read.</summary>
function ParseXml(const AXml: string): TXmlNode;

function ParseUnixListLine(const ALine: string; ANow: TDateTime;
  out AEntry: TNetEntry): Boolean;
function ParseDosListLine(const ALine: string; out AEntry: TNetEntry): Boolean;
function ParseMlsdLine(const ALine: string; out AEntry: TNetEntry): Boolean;
/// <summary>Entries of an FTP / SFTP listing text; AFormat: 0 = detect each line
/// (Unix or DOS), 1 = MLSD.</summary>
function ParseFtpListing(const AText: string; AFormat: Integer; ANow: TDateTime): TNetEntries;
/// <summary>True when some line has the permission column of an ls listing
/// (so a listing with no entries - only "." and ".." - is still a listing).</summary>
function LooksLikeListing(const AText: string): Boolean;

/// <summary>Entries of a PROPFIND answer. ABasePath is the folder being
/// listed (percent-decoded, '/'-separated); its own entry is left out.</summary>
function ParseWebDavMultiStatus(const AXml, ABasePath: string): TNetEntries;
/// <summary>The first entry of a PROPFIND answer (a Depth 0 request for one item).</summary>
function ParseWebDavSelf(const AXml: string; out AEntry: TNetEntry): Boolean;
/// <summary>Quota figures of a PROPFIND answer (RFC 4331); -1 when absent.</summary>
procedure ParseWebDavQuota(const AXml: string; out AFree, AUsed: Int64);

function ParseS3Buckets(const AXml: string): TNetEntries;
/// <summary>Entries of a ListObjectsV2 answer for the given prefix ("dir/" or
/// ''); common prefixes become folders. The marker object of the folder itself
/// (the key equal to the prefix) is left out.</summary>
function ParseS3Objects(const AXml, APrefix: string; out ATruncated: Boolean;
  out ANextToken: string): TNetEntries;

function ParseHttpDate(const AText: string): Int64;
function ParseIso8601(const AText: string): Int64;
function ParseMlsdTime(const AText: string): Int64;
function UnixModeFromText(const APerms: string): Cardinal;
function FormatUnixMode(AMode: Cardinal): string;

implementation

uses
  System.DateUtils, System.Character;

const
  cMonths: array[1..12] of string =
    ('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec');

{ TXmlNode }

constructor TXmlNode.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Children := TObjectList<TXmlNode>.Create(True);
end;

destructor TXmlNode.Destroy;
begin
  Children.Free;
  inherited Destroy;
end;

function TXmlNode.Find(const AName: string): TXmlNode;
var
  C, Hit: TXmlNode;
begin
  for C in Children do
    if C.Name = AName then
      Exit(C);
  for C in Children do
  begin
    Hit := C.Find(AName);
    if Hit <> nil then
      Exit(Hit);
  end;
  Result := nil;
end;

function TXmlNode.ChildText(const AName: string): string;
var
  C: TXmlNode;
begin
  C := Find(AName);
  if C = nil then
    Result := ''
  else
    Result := C.Text;
end;

procedure TXmlNode.FindAll(const AName: string; AList: TList<TXmlNode>);
var
  C: TXmlNode;
begin
  for C in Children do
  begin
    if C.Name = AName then
      AList.Add(C);
    C.FindAll(AName, AList);
  end;
end;

function DecodeEntities(const AText: string): string;
var
  I, Semi, Code: Integer;
  Ent: string;
begin
  if Pos('&', AText) = 0 then
    Exit(AText);
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if AText[I] = '&' then
    begin
      Semi := Pos(';', AText, I);
      if (Semi > I) and (Semi - I <= 10) then
      begin
        Ent := Copy(AText, I + 1, Semi - I - 1);
        if Ent = 'amp' then Result := Result + '&'
        else if Ent = 'lt' then Result := Result + '<'
        else if Ent = 'gt' then Result := Result + '>'
        else if Ent = 'quot' then Result := Result + '"'
        else if Ent = 'apos' then Result := Result + ''''
        else if (Length(Ent) > 1) and (Ent[1] = '#') then
        begin
          if (Ent[2] = 'x') or (Ent[2] = 'X') then
            Code := StrToIntDef('$' + Copy(Ent, 3, MaxInt), -1)
          else
            Code := StrToIntDef(Copy(Ent, 2, MaxInt), -1);
          if (Code > 0) and (Code <= $10FFFF) then
            Result := Result + Char.ConvertFromUtf32(Code)
          else
            Result := Result + Copy(AText, I, Semi - I + 1);
        end
        else
          Result := Result + Copy(AText, I, Semi - I + 1);
        I := Semi + 1;
        Continue;
      end;
    end;
    Result := Result + AText[I];
    Inc(I);
  end;
end;

function LocalXmlName(const ATag: string): string;
var
  Colon: Integer;
begin
  Colon := LastDelimiter(':', ATag);
  if Colon > 0 then
    Result := LowerCase(Copy(ATag, Colon + 1, MaxInt))
  else
    Result := LowerCase(ATag);
end;

function ParseXml(const AXml: string): TXmlNode;
var
  Root, Cur, Child: TXmlNode;
  Stack: TList<TXmlNode>;
  I, N, J: Integer;
  Tag, Body: string;
  SelfClose, Closing: Boolean;
begin
  Result := nil;
  Root := TXmlNode.Create('#root');
  Stack := TList<TXmlNode>.Create;
  try
    Stack.Add(Root);
    I := 1;
    N := Length(AXml);
    while I <= N do
    begin
      if AXml[I] <> '<' then
      begin
        J := Pos('<', AXml, I);
        if J = 0 then
          J := N + 1;
        Cur := Stack[Stack.Count - 1];
        Cur.Text := Cur.Text + DecodeEntities(Copy(AXml, I, J - I));
        I := J;
        Continue;
      end;
      if Copy(AXml, I, 4) = '<!--' then
      begin
        J := Pos('-->', AXml, I + 4);
        if J = 0 then
          Exit;
        I := J + 3;
        Continue;
      end;
      if Copy(AXml, I, 9) = '<![CDATA[' then
      begin
        J := Pos(']]>', AXml, I + 9);
        if J = 0 then
          Exit;
        Cur := Stack[Stack.Count - 1];
        Cur.Text := Cur.Text + Copy(AXml, I + 9, J - I - 9);
        I := J + 3;
        Continue;
      end;
      if (Copy(AXml, I, 2) = '<?') then
      begin
        J := Pos('?>', AXml, I + 2);
        if J = 0 then
          Exit;
        I := J + 2;
        Continue;
      end;
      if Copy(AXml, I, 2) = '<!' then
      begin
        J := Pos('>', AXml, I + 2);
        if J = 0 then
          Exit;
        I := J + 1;
        Continue;
      end;
      J := Pos('>', AXml, I + 1);
      if J = 0 then
        Exit;
      Body := Copy(AXml, I + 1, J - I - 1);
      I := J + 1;
      Closing := (Body <> '') and (Body[1] = '/');
      SelfClose := (Body <> '') and (Body[Length(Body)] = '/');
      if Closing then
        Body := Copy(Body, 2, MaxInt);
      if SelfClose then
        Body := Copy(Body, 1, Length(Body) - 1);
      Body := Trim(Body);
      J := 1;
      while (J <= Length(Body)) and not Body[J].IsWhiteSpace do
        Inc(J);
      Tag := Copy(Body, 1, J - 1);
      if Tag = '' then
        Exit;
      if Closing then
      begin
        if Stack.Count > 1 then
          Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      Child := TXmlNode.Create(LocalXmlName(Tag));
      Stack[Stack.Count - 1].Children.Add(Child);
      if not SelfClose then
        Stack.Add(Child);
    end;
    if Root.Children.Count = 0 then
      Exit;
    Result := Root;
    Root := nil;
  finally
    Stack.Free;
    Root.Free;
  end;
end;

{ Times }

function MonthNumber(const AText: string): Integer;
var
  I: Integer;
  S: string;
begin
  S := LowerCase(AText);
  for I := 1 to 12 do
    if S = cMonths[I] then
      Exit(I);
  Result := 0;
end;

function ToUnixLocalDigits(const AValue: TDateTime): Int64;
begin
  // The digits as printed: the host converts to local time for display, so the
  // value is made from the digits taken as local time.
  Result := DateTimeToUnix(AValue, False);
end;

function TryMakeDate(AYear, AMonth, ADay, AHour, AMinute, ASecond: Integer;
  out AValue: TDateTime): Boolean;
begin
  Result := TryEncodeDateTime(AYear, AMonth, ADay, AHour, AMinute, ASecond, 0, AValue);
end;

function ParseMlsdTime(const AText: string): Int64;
var
  Y, Mo, D, H, Mi, S: Integer;
  Dt: TDateTime;
begin
  Result := 0;
  if Length(AText) < 8 then
    Exit;
  Y := StrToIntDef(Copy(AText, 1, 4), -1);
  Mo := StrToIntDef(Copy(AText, 5, 2), -1);
  D := StrToIntDef(Copy(AText, 7, 2), -1);
  H := 0;
  Mi := 0;
  S := 0;
  if Length(AText) >= 14 then
  begin
    H := StrToIntDef(Copy(AText, 9, 2), 0);
    Mi := StrToIntDef(Copy(AText, 11, 2), 0);
    S := StrToIntDef(Copy(AText, 13, 2), 0);
  end;
  if TryMakeDate(Y, Mo, D, H, Mi, S, Dt) then
    // MLSD times are UTC: converted like any time with a zone.
    Result := DateTimeToUnix(Dt, True);
end;

function ParseHttpDate(const AText: string): Int64;
var
  Parts: TArray<string>;
  Y, Mo, D, H, Mi, S: Integer;
  Dt: TDateTime;
  Time: TArray<string>;
  Start: Integer;
begin
  Result := 0;
  // "Mon, 02 Jan 2006 15:04:05 GMT"
  Parts := Trim(AText).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Start := 0;
  if (Length(Parts) > 0) and (Pos(',', Parts[0]) > 0) then
    Start := 1;
  if Length(Parts) < Start + 4 then
    Exit;
  D := StrToIntDef(Parts[Start], -1);
  Mo := MonthNumber(Parts[Start + 1]);
  Y := StrToIntDef(Parts[Start + 2], -1);
  Time := Parts[Start + 3].Split([':']);
  if (Length(Time) < 2) or (Mo = 0) then
    Exit;
  H := StrToIntDef(Time[0], 0);
  Mi := StrToIntDef(Time[1], 0);
  if Length(Time) > 2 then
    S := StrToIntDef(Time[2], 0)
  else
    S := 0;
  if TryMakeDate(Y, Mo, D, H, Mi, S, Dt) then
    Result := DateTimeToUnix(Dt, True);
end;

function ParseIso8601(const AText: string): Int64;
var
  S: string;
  Y, Mo, D, H, Mi, Sec: Integer;
  Dt: TDateTime;
  T: Integer;
begin
  Result := 0;
  S := Trim(AText);
  if Length(S) < 10 then
    Exit;
  Y := StrToIntDef(Copy(S, 1, 4), -1);
  Mo := StrToIntDef(Copy(S, 6, 2), -1);
  D := StrToIntDef(Copy(S, 9, 2), -1);
  H := 0;
  Mi := 0;
  Sec := 0;
  T := Pos('T', S);
  if (T > 0) and (Length(S) >= T + 5) then
  begin
    H := StrToIntDef(Copy(S, T + 1, 2), 0);
    Mi := StrToIntDef(Copy(S, T + 4, 2), 0);
    if (Length(S) >= T + 8) and (S[T + 6] = ':') then
      Sec := StrToIntDef(Copy(S, T + 7, 2), 0);
  end;
  if TryMakeDate(Y, Mo, D, H, Mi, Sec, Dt) then
    Result := DateTimeToUnix(Dt, True);
end;

{ Permissions }

function UnixModeFromText(const APerms: string): Cardinal;
const
  cBits: array[0..8] of Cardinal = ($100, $80, $40, $20, $10, $8, $4, $2, $1);
var
  I: Integer;
  C: Char;
begin
  Result := 0;
  if Length(APerms) < 10 then
    Exit;
  for I := 0 to 8 do
  begin
    C := APerms[I + 2];
    if (C <> '-') and (C <> 'S') and (C <> 'T') and (C <> '?') then
      Result := Result or cBits[I];
  end;
  if (APerms[4] = 's') or (APerms[4] = 'S') then
    Result := Result or $800;
  if (APerms[7] = 's') or (APerms[7] = 'S') then
    Result := Result or $400;
  if (APerms[10] = 't') or (APerms[10] = 'T') then
    Result := Result or $200;
end;

function FormatUnixMode(AMode: Cardinal): string;
const
  cLetters = 'rwxrwxrwx';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 8 do
    if (AMode and (Cardinal($100) shr I)) <> 0 then
      Result := Result + cLetters[I + 1]
    else
      Result := Result + '-';
end;

{ Text listings }

function IsDigits(const AText: string): Boolean;
var
  C: Char;
begin
  Result := AText <> '';
  for C in AText do
    if (C < '0') or (C > '9') then
      Exit(False);
end;

function SplitLineTokens(const ALine: string; out ATokens: TArray<string>;
  out AStarts: TArray<Integer>): Integer;
var
  I, Start: Integer;
begin
  SetLength(ATokens, 0);
  SetLength(AStarts, 0);
  I := 1;
  while I <= Length(ALine) do
  begin
    while (I <= Length(ALine)) and ((ALine[I] = ' ') or (ALine[I] = #9)) do
      Inc(I);
    if I > Length(ALine) then
      Break;
    Start := I;
    while (I <= Length(ALine)) and (ALine[I] <> ' ') and (ALine[I] <> #9) do
      Inc(I);
    SetLength(ATokens, Length(ATokens) + 1);
    SetLength(AStarts, Length(AStarts) + 1);
    ATokens[High(ATokens)] := Copy(ALine, Start, I - Start);
    AStarts[High(AStarts)] := Start;
  end;
  Result := Length(ATokens);
end;

// "12:34" or "2024" in the third field of the date.
function ParseUnixDate(const AMonth, ADay, ATimeOrYear: string; ANow: TDateTime;
  out AValue: Int64): Boolean;
var
  Mo, D, Y, H, Mi, Colon: Integer;
  Dt: TDateTime;
begin
  Result := False;
  AValue := 0;
  Mo := MonthNumber(AMonth);
  D := StrToIntDef(ADay, -1);
  if (Mo = 0) or (D < 1) or (D > 31) then
    Exit;
  Colon := Pos(':', ATimeOrYear);
  if Colon > 0 then
  begin
    H := StrToIntDef(Copy(ATimeOrYear, 1, Colon - 1), -1);
    Mi := StrToIntDef(Copy(ATimeOrYear, Colon + 1, 2), -1);
    if (H < 0) or (Mi < 0) then
      Exit;
    Y := YearOf(ANow);
    if not TryMakeDate(Y, Mo, D, H, Mi, 0, Dt) then
      Exit;
    // A month still to come belongs to the year before.
    if Dt > ANow + 1 then
      if not TryMakeDate(Y - 1, Mo, D, H, Mi, 0, Dt) then
        Exit;
  end
  else
  begin
    Y := StrToIntDef(ATimeOrYear, -1);
    if (Y < 1900) or (Y > 2200) then
      Exit;
    if not TryMakeDate(Y, Mo, D, 0, 0, 0, Dt) then
      Exit;
  end;
  AValue := ToUnixLocalDigits(Dt);
  Result := True;
end;

function ParseUnixListLine(const ALine: string; ANow: TDateTime;
  out AEntry: TNetEntry): Boolean;
var
  Tokens: TArray<string>;
  Starts: TArray<Integer>;
  I, Idx, NameStart: Integer;
  Name, Perms: string;
  DayFirst: Boolean;
  Arrow: Integer;
  Year, Mo, D: Integer;
  Dt: TDateTime;
  When: Int64;
begin
  AEntry := Default(TNetEntry);
  Result := False;
  if (Length(ALine) < 11) or not CharInSet(ALine[1], ['-', 'd', 'l', 'b', 'c', 'p', 's', 'D']) then
    Exit;
  Perms := Copy(ALine, 1, 10);
  SplitLineTokens(ALine, Tokens, Starts);
  if Length(Tokens) < 6 then
    Exit;
  Idx := -1;
  DayFirst := False;
  // Month name day time|year, preceded by the size.
  for I := 4 to Length(Tokens) - 3 do
    if (MonthNumber(Tokens[I]) > 0) and IsDigits(Tokens[I - 1]) and
       IsDigits(Tokens[I + 1]) and (Length(Tokens[I + 1]) <= 2) then
    begin
      if ParseUnixDate(Tokens[I], Tokens[I + 1], Tokens[I + 2], ANow, When) then
      begin
        Idx := I;
        Break;
      end;
    end;
  if Idx < 0 then
    // Some servers write the day first: size day Month time|year.
    for I := 5 to Length(Tokens) - 2 do
      if (MonthNumber(Tokens[I]) > 0) and IsDigits(Tokens[I - 1]) and (Length(Tokens[I - 1]) <= 2) and
         IsDigits(Tokens[I - 2]) then
      begin
        if ParseUnixDate(Tokens[I], Tokens[I - 1], Tokens[I + 1], ANow, When) then
        begin
          Idx := I;
          DayFirst := True;
          Break;
        end;
      end;
  if Idx > 0 then
  begin
    if DayFirst then
    begin
      AEntry.Size := StrToInt64Def(Tokens[Idx - 2], 0);
      NameStart := Starts[Idx + 1] + Length(Tokens[Idx + 1]);
    end
    else
    begin
      AEntry.Size := StrToInt64Def(Tokens[Idx - 1], 0);
      NameStart := Starts[Idx + 2] + Length(Tokens[Idx + 2]);
    end;
    AEntry.Modified := When;
  end
  else
  begin
    // ISO style: size yyyy-mm-dd hh:mm name.
    for I := 4 to Length(Tokens) - 3 do
      if (Length(Tokens[I]) = 10) and (Tokens[I][5] = '-') and (Tokens[I][8] = '-') and
         IsDigits(Tokens[I - 1]) and (Pos(':', Tokens[I + 1]) > 0) then
      begin
        Year := StrToIntDef(Copy(Tokens[I], 1, 4), -1);
        Mo := StrToIntDef(Copy(Tokens[I], 6, 2), -1);
        D := StrToIntDef(Copy(Tokens[I], 9, 2), -1);
        if TryMakeDate(Year, Mo, D, StrToIntDef(Copy(Tokens[I + 1], 1, 2), 0),
             StrToIntDef(Copy(Tokens[I + 1], 4, 2), 0), 0, Dt) then
        begin
          Idx := I;
          AEntry.Size := StrToInt64Def(Tokens[I - 1], 0);
          AEntry.Modified := ToUnixLocalDigits(Dt);
          Break;
        end;
      end;
    if Idx < 0 then
      Exit;
    NameStart := Starts[Idx + 1] + Length(Tokens[Idx + 1]);
  end;
  Name := Copy(ALine, NameStart + 1, MaxInt);
  // One separating blank; further leading blanks are part of the name.
  if (Name <> '') and (Name[1] = ' ') then
    Delete(Name, 1, 1);
  Name := Name.TrimRight([#13, #10]);
  AEntry.IsDir := Perms[1] = 'd';
  AEntry.IsLink := Perms[1] = 'l';
  AEntry.Mode := UnixModeFromText(Perms);
  if AEntry.IsLink then
  begin
    Arrow := Pos(' -> ', Name);
    if Arrow > 0 then
      Name := Copy(Name, 1, Arrow - 1);
  end;
  if (Name = '') or (Name = '.') or (Name = '..') then
    Exit;
  AEntry.Name := Name;
  Result := True;
end;

function ParseDosListLine(const ALine: string; out AEntry: TNetEntry): Boolean;
var
  Tokens: TArray<string>;
  Starts: TArray<Integer>;
  DateParts: TArray<string>;
  Y, Mo, D, H, Mi, Next: Integer;
  TimeText, Size: string;
  Dt: TDateTime;
  Pm, Am: Boolean;
begin
  AEntry := Default(TNetEntry);
  Result := False;
  SplitLineTokens(ALine, Tokens, Starts);
  if Length(Tokens) < 4 then
    Exit;
  DateParts := Tokens[0].Split(['-', '/']);
  if (Length(DateParts) <> 3) or not IsDigits(DateParts[0]) or not IsDigits(DateParts[1]) or
     not IsDigits(DateParts[2]) then
    Exit;
  Mo := StrToInt(DateParts[0]);
  D := StrToInt(DateParts[1]);
  Y := StrToInt(DateParts[2]);
  if Y < 100 then
    if Y < 70 then Inc(Y, 2000) else Inc(Y, 1900);
  TimeText := Tokens[1];
  Next := 2;
  Am := False;
  Pm := False;
  if (Length(TimeText) > 2) and (UpCase(TimeText[Length(TimeText)]) = 'M') then
  begin
    Pm := UpCase(TimeText[Length(TimeText) - 1]) = 'P';
    Am := not Pm;
    TimeText := Copy(TimeText, 1, Length(TimeText) - 2);
  end
  else if (Length(Tokens) > 3) and ((UpperCase(Tokens[2]) = 'AM') or (UpperCase(Tokens[2]) = 'PM')) then
  begin
    Pm := UpperCase(Tokens[2]) = 'PM';
    Am := not Pm;
    Next := 3;
  end;
  H := StrToIntDef(Copy(TimeText, 1, Pos(':', TimeText) - 1), -1);
  Mi := StrToIntDef(Copy(TimeText, Pos(':', TimeText) + 1, 2), -1);
  if (H < 0) or (Mi < 0) then
    Exit;
  if Pm and (H < 12) then
    Inc(H, 12);
  if Am and (H = 12) then
    H := 0;
  if not TryMakeDate(Y, Mo, D, H, Mi, 0, Dt) then
    Exit;
  AEntry.Modified := ToUnixLocalDigits(Dt);
  if Next >= Length(Tokens) then
    Exit;
  Size := Tokens[Next];
  if SameText(Size, '<DIR>') then
    AEntry.IsDir := True
  else if IsDigits(StringReplace(Size, ',', '', [rfReplaceAll])) then
    AEntry.Size := StrToInt64Def(StringReplace(Size, ',', '', [rfReplaceAll]), 0)
  else
    Exit;
  if Next + 1 >= Length(Tokens) then
    Exit;
  AEntry.Name := Copy(ALine, Starts[Next + 1], MaxInt).TrimRight([#13, #10]);
  Result := (AEntry.Name <> '') and (AEntry.Name <> '.') and (AEntry.Name <> '..');
end;

function OctalToMode(const AText: string): Cardinal;
var
  C: Char;
begin
  Result := 0;
  for C in AText do
    if (C >= '0') and (C <= '7') then
      Result := Result * 8 + Cardinal(Ord(C) - Ord('0'))
    else
      Exit(0);
  Result := Result and $FFF;
end;

function ParseMlsdLine(const ALine: string; out AEntry: TNetEntry): Boolean;
var
  Sp: Integer;
  Facts, Name, Fact, Key, Value, KindText: string;
  Parts: TArray<string>;
  Eq: Integer;
begin
  AEntry := Default(TNetEntry);
  Result := False;
  // "fact=value;fact=value; name" - the name follows the first blank.
  Sp := Pos(' ', ALine);
  if Sp = 0 then
    Exit;
  Facts := Copy(ALine, 1, Sp - 1);
  Name := Copy(ALine, Sp + 1, MaxInt).TrimRight([#13, #10]);
  if (Name = '') or (Name = '.') or (Name = '..') then
    Exit;
  KindText := '';
  Parts := Facts.Split([';']);
  for Fact in Parts do
  begin
    Eq := Pos('=', Fact);
    if Eq = 0 then
      Continue;
    Key := LowerCase(Copy(Fact, 1, Eq - 1));
    Value := Copy(Fact, Eq + 1, MaxInt);
    if Key = 'type' then
      KindText := LowerCase(Value)
    else if (Key = 'size') or (Key = 'sizd') then
      AEntry.Size := StrToInt64Def(Value, 0)
    else if Key = 'modify' then
      AEntry.Modified := ParseMlsdTime(Value)
    else if Key = 'unix.mode' then
      AEntry.Mode := OctalToMode(Value);
  end;
  if (KindText = 'cdir') or (KindText = 'pdir') then
    Exit;
  AEntry.IsDir := KindText = 'dir';
  AEntry.IsLink := Pos('symlink', KindText) > 0;
  AEntry.Name := Name;
  Result := True;
end;

function ParseFtpListing(const AText: string; AFormat: Integer; ANow: TDateTime): TNetEntries;
var
  Lines: TArray<string>;
  Line: string;
  E: TNetEntry;
  List: TList<TNetEntry>;
begin
  List := TList<TNetEntry>.Create;
  try
    Lines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    for Line in Lines do
    begin
      if Trim(Line) = '' then
        Continue;
      if AFormat = 1 then
      begin
        if ParseMlsdLine(Line, E) then
          List.Add(E);
      end
      else if ParseUnixListLine(Line, ANow, E) or ParseDosListLine(Line, E) then
        List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function LooksLikeListing(const AText: string): Boolean;
var
  Line: string;
  I: Integer;
  Ok: Boolean;
begin
  for Line in AText.Replace(#13#10, #10).Split([#10]) do
  begin
    if (Length(Line) < 10) or not CharInSet(Line[1], ['-', 'd', 'l', 'b', 'c', 'p', 's']) then
      Continue;
    Ok := True;
    for I := 2 to 10 do
      if not CharInSet(Line[I], ['r', 'w', 'x', '-', 's', 'S', 't', 'T', '?']) then
      begin
        Ok := False;
        Break;
      end;
    if Ok then
      Exit(True);
  end;
  Result := False;
end;

{ WebDAV }

function ParseWebDavMultiStatus(const AXml, ABasePath: string): TNetEntries;
var
  Root: TXmlNode;
  Responses: TList<TXmlNode>;
  Resp, Type_: TXmlNode;
  List: TList<TNetEntry>;
  Href, Path, Base: string;
  E: TNetEntry;
  Slash: Integer;
begin
  SetLength(Result, 0);
  Root := ParseXml(AXml);
  if Root = nil then
    Exit;
  Responses := TList<TXmlNode>.Create;
  List := TList<TNetEntry>.Create;
  try
    Root.FindAll('response', Responses);
    Base := PosixNormalize(ABasePath);
    for Resp in Responses do
    begin
      Href := Trim(Resp.ChildText('href'));
      // An absolute URL carries scheme and host before the path.
      Slash := Pos('://', Href);
      if Slash > 0 then
      begin
        Href := Copy(Href, Slash + 3, MaxInt);
        Slash := Pos('/', Href);
        if Slash > 0 then
          Href := Copy(Href, Slash, MaxInt)
        else
          Href := '/';
      end;
      Path := PosixNormalize(UrlDecode(Href));
      if SameText(Path, Base) then
        Continue;
      E := Default(TNetEntry);
      E.Name := PosixLastSegment(Path);
      if E.Name = '' then
        Continue;
      Type_ := Resp.Find('resourcetype');
      E.IsDir := (Type_ <> nil) and (Type_.Find('collection') <> nil);
      E.Size := StrToInt64Def(Trim(Resp.ChildText('getcontentlength')), 0);
      E.Modified := ParseHttpDate(Resp.ChildText('getlastmodified'));
      if (E.Modified = 0) and (Resp.ChildText('creationdate') <> '') then
        E.Modified := ParseIso8601(Resp.ChildText('creationdate'));
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Responses.Free;
    Root.Free;
  end;
end;

function ParseWebDavSelf(const AXml: string; out AEntry: TNetEntry): Boolean;
var
  Root: TXmlNode;
  Resp, Type_: TXmlNode;
  Href: string;
begin
  AEntry := Default(TNetEntry);
  Result := False;
  Root := ParseXml(AXml);
  if Root = nil then
    Exit;
  try
    Resp := Root.Find('response');
    if Resp = nil then
      Exit;
    Href := UrlDecode(Trim(Resp.ChildText('href')));
    AEntry.Name := PosixLastSegment(PosixNormalize(Href));
    Type_ := Resp.Find('resourcetype');
    AEntry.IsDir := (Type_ <> nil) and (Type_.Find('collection') <> nil);
    AEntry.Size := StrToInt64Def(Trim(Resp.ChildText('getcontentlength')), 0);
    AEntry.Modified := ParseHttpDate(Resp.ChildText('getlastmodified'));
    Result := True;
  finally
    Root.Free;
  end;
end;

procedure ParseWebDavQuota(const AXml: string; out AFree, AUsed: Int64);
var
  Root: TXmlNode;
begin
  AFree := -1;
  AUsed := -1;
  Root := ParseXml(AXml);
  if Root = nil then
    Exit;
  try
    AFree := StrToInt64Def(Trim(Root.ChildText('quota-available-bytes')), -1);
    AUsed := StrToInt64Def(Trim(Root.ChildText('quota-used-bytes')), -1);
  finally
    Root.Free;
  end;
end;

{ S3 }

function ParseS3Buckets(const AXml: string): TNetEntries;
var
  Root: TXmlNode;
  Buckets: TList<TXmlNode>;
  B: TXmlNode;
  List: TList<TNetEntry>;
  E: TNetEntry;
begin
  SetLength(Result, 0);
  Root := ParseXml(AXml);
  if Root = nil then
    Exit;
  Buckets := TList<TXmlNode>.Create;
  List := TList<TNetEntry>.Create;
  try
    Root.FindAll('bucket', Buckets);
    for B in Buckets do
    begin
      E := Default(TNetEntry);
      E.Name := B.ChildText('name');
      if E.Name = '' then
        Continue;
      E.IsDir := True;
      E.Modified := ParseIso8601(B.ChildText('creationdate'));
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Buckets.Free;
    Root.Free;
  end;
end;

function ParseS3Objects(const AXml, APrefix: string; out ATruncated: Boolean;
  out ANextToken: string): TNetEntries;
var
  Root: TXmlNode;
  Nodes: TList<TXmlNode>;
  N: TXmlNode;
  List: TList<TNetEntry>;
  E: TNetEntry;
  Key, Prefix: string;
begin
  SetLength(Result, 0);
  ATruncated := False;
  ANextToken := '';
  Root := ParseXml(AXml);
  if Root = nil then
    Exit;
  Nodes := TList<TXmlNode>.Create;
  List := TList<TNetEntry>.Create;
  try
    ATruncated := SameText(Trim(Root.ChildText('istruncated')), 'true');
    ANextToken := Trim(Root.ChildText('nextcontinuationtoken'));
    Root.FindAll('commonprefixes', Nodes);
    for N in Nodes do
    begin
      Prefix := N.ChildText('prefix');
      if Copy(Prefix, 1, Length(APrefix)) <> APrefix then
        Continue;
      Key := Copy(Prefix, Length(APrefix) + 1, MaxInt);
      if (Key <> '') and (Key[Length(Key)] = '/') then
        Delete(Key, Length(Key), 1);
      if Key = '' then
        Continue;
      E := Default(TNetEntry);
      E.Name := Key;
      E.IsDir := True;
      List.Add(E);
    end;
    Nodes.Clear;
    Root.FindAll('contents', Nodes);
    for N in Nodes do
    begin
      Key := N.ChildText('key');
      if Copy(Key, 1, Length(APrefix)) <> APrefix then
        Continue;
      Key := Copy(Key, Length(APrefix) + 1, MaxInt);
      if (Key = '') or (Key[Length(Key)] = '/') then
        Continue;
      E := Default(TNetEntry);
      E.Name := Key;
      E.Size := StrToInt64Def(Trim(N.ChildText('size')), 0);
      E.Modified := ParseIso8601(N.ChildText('lastmodified'));
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Nodes.Free;
    Root.Free;
  end;
end;

end.
