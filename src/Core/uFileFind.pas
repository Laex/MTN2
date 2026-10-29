unit uFileFind;

{ Async file-name / content search. Walks the local filesystem off
  the UI thread and reports progress / results via TThread.Queue. }

interface

uses
  System.SysUtils, System.Classes,
  uVfsTypes, uTextEncoding;

const
  cFindMaxResults = 5000;
  cFindMaxContentBytes = 4 * 1024 * 1024;

type
  TFindOptions = record
    RootPath: string;
    Mask: string;              // one or several masks: *.pas;*.dfm
    ContainingText: string;    // empty = name/mask only
    Subdirs: Boolean;
    CaseSensitive: Boolean;
    WholeWords: Boolean;
    SearchFolders: Boolean;    // include matching directories in results
    UseRegex: Boolean;         // ContainingText is a regex pattern, not plain text
    HexBytes: string;          // byte sequence ("4D 5A ?? 90") the file must contain; empty = none
    MinSize: Int64;            // bytes; -1 = no lower bound (files only)
    MaxSize: Int64;            // bytes; -1 = no upper bound (files only)
    ModifiedFrom: TDateTime;   // 0 = no lower bound
    ModifiedTo: TDateTime;     // 0 = no upper bound
    RequireAttr: Integer;      // fa* bits an entry must all have; 0 = any
  end;

  /// <summary>The filter fields of the Find dialog as typed: sizes such as
  /// "10", "512K", "1.5M", dates in the locale's short format, optionally with
  /// a time.</summary>
  TFindFilterText = record
    SizeMin, SizeMax, DateFrom, DateTo: string;
    AttrReadOnly, AttrHidden, AttrSystem, AttrArchive: Boolean;
  end;

  /// <summary>One search hit. Line/Snippet are 0/'' unless ContainingText was
  /// set - then they point at the first matching line (1-based).</summary>
  TFindHit = record
    Path: string;
    Line: Integer;
    Snippet: string;
  end;

  TFindProgressCallback = reference to procedure(AFoundCount: Integer;
    const ACurrentDir: string);
  TFindDoneCallback = reference to procedure(const AHits: TArray<TFindHit>;
    const AError: TVfsError);

function DefaultFindOptions(const ARootPath, AMask: string;
  ASubdirs: Boolean = True): TFindOptions;

/// <summary>A size with an optional K, M, G or T suffix (powers of 1024, a
/// trailing B allowed); '' gives True with -1 (no bound).</summary>
function TryParseFindSize(const AText: string; out ABytes: Int64): Boolean;
/// <summary>A date (locale short format) with an optional time; '' gives True
/// with 0. A leading weekday, as in a short format that prints one, is
/// ignored. A date without a time is the start of that day, or its last
/// moment when AEndOfDay.</summary>
function TryParseFindDate(const AText: string; AEndOfDay: Boolean;
  out ATime: TDateTime): Boolean;
/// <summary>Copies the typed filters into AOptions; False with AError naming
/// the field that cannot be read.</summary>
function ApplyFindFilterText(var AOptions: TFindOptions;
  const AText: TFindFilterText; out AError: string): Boolean;
/// <summary>True when an entry passes the size, date and attribute filters.
/// Size bounds do not apply to folders, and a folder is dropped while one is
/// set.</summary>
function FindEntryPassesFilters(const AOptions: TFindOptions; AIsDir: Boolean;
  ASize: Int64; AModified: TDateTime; AAttr: Integer): Boolean;

/// <summary>Split `*.pas;*.dfm` / comma-separated masks (empty -> `*.*`).</summary>
function SplitMasks(const AMask: string): TArray<string>;
/// <summary>True if AName matches any mask from SplitMasks / System.Masks.</summary>
function NameMatchesAnyMask(const AName: string;
  const AMasks: TArray<string>): Boolean;
/// <summary>Compiles APattern as a regex just to check it's well-formed;
/// AError carries the exception message on failure. Call before starting an
/// AUseRegex search so a bad pattern is reported instantly instead of
/// failing file-by-file mid-walk.</summary>
function ValidateRegexPattern(const APattern: string; out AError: string): Boolean;

/// <summary>Reads a byte sequence typed as hex: pairs of digits, optionally
/// separated by spaces or commas and prefixed with 0x; "??" matches any byte.
/// Each APattern item is 0..255, or -1 for "??". AError says what is wrong.</summary>
function TryParseHexPattern(const AText: string; out APattern: TArray<Integer>;
  out AError: string): Boolean;

/// <summary>The UTF-8 bytes of AText as hex pairs ("48 65 6C").</summary>
function TextToHexString(const AText: string): string;

/// <summary>The text AHex spells when it is plain UTF-8 without "??"; False
/// for anything else (odd digits, wildcards, bytes that are not UTF-8).</summary>
function TryHexToText(const AHex: string; out AText: string): Boolean;

/// <summary>Applies an edit of the hex field. AOld is the field as last shown
/// (pairs of digits separated by single spaces), ANew what the edit left and
/// ACursor the caret in it (0-based, as in the input line). The result is
/// again pairs of upper-case digits; the spaces are not editable. A digit
/// typed between the two digits of a byte replaces the second one; typed
/// anywhere else among the bytes it inserts a new byte (the other nibble is 0,
/// "?" for a wildcard), so the following bytes keep their pairing; typed at
/// the end it appends a digit. Deleting one digit of a byte turns it into 0
/// (the bytes after it keep their pairing); a byte that becomes 00 is removed,
/// as is a lone digit at the end. Deleting a space does nothing.</summary>
procedure EditHexField(const AOld, ANew: string; ACursor: Integer;
  out AText: string; out ACursor2: Integer);

/// <summary>Scans the whole file in pieces for APattern; AOffset is the
/// position of the first match.</summary>
function FileHexMatch(const APath: string; const APattern: TArray<Integer>;
  out AOffset: Int64): Boolean;

/// <summary>Whether one file passes the content conditions (text and/or hex
/// bytes); ALine / ASnippet describe the first hit. No condition matches
/// every file.</summary>
function FindContentMatch(const AFilePath: string; const AOptions: TFindOptions;
  out ALine: Integer; out ASnippet: string): Boolean;

procedure FindFilesAsync(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback);

implementation

uses
  System.IOUtils, System.Masks, System.Math, System.Generics.Collections,
  System.RegularExpressions;

function DefaultFindOptions(const ARootPath, AMask: string;
  ASubdirs: Boolean): TFindOptions;
begin
  Result.RootPath := ARootPath;
  Result.Mask := AMask;
  Result.ContainingText := '';
  Result.Subdirs := ASubdirs;
  Result.CaseSensitive := False;
  Result.WholeWords := False;
  Result.SearchFolders := False;
  Result.UseRegex := False;
  Result.HexBytes := '';
  Result.MinSize := -1;
  Result.MaxSize := -1;
  Result.ModifiedFrom := 0;
  Result.ModifiedTo := 0;
  Result.RequireAttr := 0;
end;

function TryParseFindSize(const AText: string; out ABytes: Int64): Boolean;
var
  S: string;
  Mult: Int64;
  Num, Product: Double;
begin
  ABytes := -1;
  S := Trim(AText);
  if S = '' then
    Exit(True);
  Result := False;
  if (S <> '') and CharInSet(UpCase(S[Length(S)]), ['B']) then
    Delete(S, Length(S), 1);
  Mult := 1;
  if S <> '' then
    case UpCase(S[Length(S)]) of
      'K': Mult := Int64(1) shl 10;
      'M': Mult := Int64(1) shl 20;
      'G': Mult := Int64(1) shl 30;
      'T': Mult := Int64(1) shl 40;
    end;
  if Mult > 1 then
    Delete(S, Length(S), 1);
  S := Trim(S);
  if (S = '') or not TryStrToFloat(S, Num) or (Num < 0) then
    Exit;
  Product := Num * Mult;
  // NaN compares unequal to itself. Past the Int64 range Round wraps to a
  // negative value, and a negative bound is read as "no bound", so the
  // search would ignore the typed size.
  if (Product <> Product) or (Product >= 9223372036854775808.0) then
    Exit;
  ABytes := Round(Product);
  if ABytes < 0 then
    Exit;
  Result := True;
end;

function TryParseFindDate(const AText: string; AEndOfDay: Boolean;
  out ATime: TDateTime): Boolean;
var
  S: string;
  Cut: Integer;
begin
  ATime := 0;
  S := Trim(AText);
  if S = '' then
    Exit(True);
  Result := TryStrToDateTime(S, ATime);
  if (not Result) and not CharInSet(S[1], ['0'..'9']) then
  begin
    // A short date format may lead with the day of week ("Mon 27.10.26").
    // The weekday is derived from the date, so it is dropped.
    Cut := 1;
    while (Cut <= Length(S)) and not CharInSet(S[Cut], ['0'..'9']) do
      Inc(Cut);
    Result := TryStrToDateTime(Copy(S, Cut, MaxInt), ATime);
  end;
  if not Result then
    Exit;
  if AEndOfDay and (Frac(ATime) = 0) then
    ATime := ATime + 1 - 1 / MSecsPerDay;
end;

function ApplyFindFilterText(var AOptions: TFindOptions;
  const AText: TFindFilterText; out AError: string): Boolean;
begin
  AError := '';
  Result := False;
  if not TryParseFindSize(AText.SizeMin, AOptions.MinSize) then
    AError := 'Invalid size: ' + AText.SizeMin
  else if not TryParseFindSize(AText.SizeMax, AOptions.MaxSize) then
    AError := 'Invalid size: ' + AText.SizeMax
  else if not TryParseFindDate(AText.DateFrom, False, AOptions.ModifiedFrom) then
    AError := 'Invalid date: ' + AText.DateFrom
  else if not TryParseFindDate(AText.DateTo, True, AOptions.ModifiedTo) then
    AError := 'Invalid date: ' + AText.DateTo;
  if AError <> '' then
    Exit;
  // The fa* constants are the bits TSearchRec.Attr reports.
  {$WARN SYMBOL_PLATFORM OFF}
  AOptions.RequireAttr := 0;
  if AText.AttrReadOnly then
    AOptions.RequireAttr := AOptions.RequireAttr or faReadOnly;
  if AText.AttrHidden then
    AOptions.RequireAttr := AOptions.RequireAttr or faHidden;
  if AText.AttrSystem then
    AOptions.RequireAttr := AOptions.RequireAttr or faSysFile;
  if AText.AttrArchive then
    AOptions.RequireAttr := AOptions.RequireAttr or faArchive;
  {$WARN SYMBOL_PLATFORM ON}
  Result := True;
end;

function FindEntryPassesFilters(const AOptions: TFindOptions; AIsDir: Boolean;
  ASize: Int64; AModified: TDateTime; AAttr: Integer): Boolean;
begin
  Result := False;
  if (AOptions.RequireAttr <> 0) and
     ((AAttr and AOptions.RequireAttr) <> AOptions.RequireAttr) then
    Exit;
  if (AOptions.ModifiedFrom <> 0) and (AModified < AOptions.ModifiedFrom) then
    Exit;
  if (AOptions.ModifiedTo <> 0) and (AModified > AOptions.ModifiedTo) then
    Exit;
  if (AOptions.MinSize >= 0) or (AOptions.MaxSize >= 0) then
  begin
    if AIsDir then
      Exit;
    if (AOptions.MinSize >= 0) and (ASize < AOptions.MinSize) then
      Exit;
    if (AOptions.MaxSize >= 0) and (ASize > AOptions.MaxSize) then
      Exit;
  end;
  Result := True;
end;

function SplitMasks(const AMask: string): TArray<string>;
var
  S, Part: string;
  I, Start, N: Integer;
begin
  S := Trim(AMask);
  if S = '' then
    S := '*.*';
  SetLength(Result, 0);
  Start := 1;
  N := 0;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ';') or (S[I] = ',') then
    begin
      Part := Trim(Copy(S, Start, I - Start));
      if Part <> '' then
      begin
        Inc(N);
        SetLength(Result, N);
        Result[N - 1] := Part;
      end;
      Start := I + 1;
    end;
  if Length(Result) = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := '*.*';
  end;
end;

function NameMatchesAnyMask(const AName: string;
  const AMasks: TArray<string>): Boolean;
var
  M: string;
begin
  for M in AMasks do
  begin
    // FAR / Win32: * and *.* match every name, including names without a dot.
    // System.Masks treats '.' as literal, so bare MatchesMask(Name, '*.*') would
    // skip extensionless files like hash-{GUID} temp names.
    if SameText(M, '*') or SameText(M, '*.*') then
      Exit(True);
    if MatchesMask(AName, M) then
      Exit(True);
  end;
  Result := False;
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := ((C >= '0') and (C <= '9')) or
    ((C >= 'A') and (C <= 'Z')) or
    ((C >= 'a') and (C <= 'z')) or
    (C = '_') or (Ord(C) > 127);
end;

function TextContainsAbs(const AHaystack, ANeedle: string; ACaseSensitive,
  AWholeWords: Boolean): Boolean;
var
  H, N: string;
  I, L: Integer;
  BeforeOk, AfterOk: Boolean;
begin
  if ANeedle = '' then
    Exit(True);
  if ACaseSensitive then
  begin
    H := AHaystack;
    N := ANeedle;
  end
  else
  begin
    H := AnsiLowerCase(AHaystack);
    N := AnsiLowerCase(ANeedle);
  end;
  L := Length(N);
  if L = 0 then
    Exit(True);
  if not AWholeWords then
    Exit(Pos(N, H) > 0);
  I := 1;
  while I <= Length(H) - L + 1 do
  begin
    if Copy(H, I, L) = N then
    begin
      BeforeOk := (I = 1) or not IsWordChar(H[I - 1]);
      AfterOk := (I + L > Length(H)) or not IsWordChar(H[I + L]);
      if BeforeOk and AfterOk then
        Exit(True);
    end;
    Inc(I);
  end;
  Result := False;
end;

function ValidateRegexPattern(const APattern: string; out AError: string): Boolean;
var
  Re: TRegEx;
begin
  AError := '';
  try
    // TRegEx.Create alone does not compile the pattern - it stays lazy until
    // the first IsMatch/Match call, so a malformed pattern only raises there.
    // Force that now so a bad pattern is caught here, not mid-walk.
    Re := TRegEx.Create(APattern);
    Re.IsMatch('');
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TryParseHexPattern(const AText: string; out APattern: TArray<Integer>;
  out AError: string): Boolean;
var
  Digits, Token: string;
  I: Integer;
  Hi, Lo: Char;

  function HexValue(C: Char): Integer;
  begin
    case C of
      '0'..'9': Result := Ord(C) - Ord('0');
      'a'..'f': Result := Ord(C) - Ord('a') + 10;
      'A'..'F': Result := Ord(C) - Ord('A') + 10;
    else
      Result := -1;
    end;
  end;

begin
  APattern := nil;
  AError := '';
  Digits := '';
  for Token in AText.Split([' ', ',', ';', #9]) do
    if (Length(Token) > 2) and (Token[1] = '0') and ((Token[2] = 'x') or (Token[2] = 'X')) then
      Digits := Digits + Copy(Token, 3, MaxInt)
    else
      Digits := Digits + Token;
  if Digits = '' then
  begin
    AError := 'No bytes';
    Exit(False);
  end;
  if Odd(Length(Digits)) then
  begin
    AError := 'Odd number of hex digits';
    Exit(False);
  end;
  SetLength(APattern, Length(Digits) div 2);
  for I := 0 to High(APattern) do
  begin
    Hi := Digits[I * 2 + 1];
    Lo := Digits[I * 2 + 2];
    if (Hi = '?') and (Lo = '?') then
      APattern[I] := -1
    else if (HexValue(Hi) >= 0) and (HexValue(Lo) >= 0) then
      APattern[I] := HexValue(Hi) * 16 + HexValue(Lo)
    else
    begin
      AError := 'Not a hex byte: ' + Hi + Lo;
      APattern := nil;
      Exit(False);
    end;
  end;
  Result := True;
end;

function TextToHexString(const AText: string): string;
var
  Bytes: TBytes;
  I: Integer;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Result := '';
  for I := 0 to High(Bytes) do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(Bytes[I], 2);
  end;
end;

function TryHexToText(const AHex: string; out AText: string): Boolean;
var
  Pattern: TArray<Integer>;
  Error: string;
  Bytes, Back: TBytes;
  I: Integer;
begin
  AText := '';
  if not TryParseHexPattern(AHex, Pattern, Error) then
    Exit(False);
  SetLength(Bytes, Length(Pattern));
  for I := 0 to High(Pattern) do
  begin
    if Pattern[I] < 0 then
      Exit(False);
    Bytes[I] := Pattern[I];
  end;
  try
    AText := TEncoding.UTF8.GetString(Bytes);
  except
    on EEncodingError do
      Exit(False);
  end;
  // Overlong forms decode without an error; the round trip rejects them.
  Back := TEncoding.UTF8.GetBytes(AText);
  if Length(Back) <> Length(Bytes) then
    Exit(False);
  for I := 0 to High(Bytes) do
    if Back[I] <> Bytes[I] then
      Exit(False);
  Result := True;
end;

function IsHexFieldChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F', '?']);
end;

// Digits and "?" of AText upper-cased; "0x" prefixes of pasted bytes dropped.
function HexFieldDigits(const AText: string): string;
var
  I: Integer;
  S: string;
begin
  S := AText.Replace('0x', '', [rfReplaceAll, rfIgnoreCase]);
  Result := '';
  for I := 1 to Length(S) do
    if IsHexFieldChar(S[I]) then
      Result := Result + UpCase(S[I]);
end;

procedure EditHexField(const AOld, ANew: string; ACursor: Integer;
  out AText: string; out ACursor2: Integer);
var
  Pos, N, I, R, S: Integer;
  Left, Digits, Fill: string;
  Ch, Prev: Char;
begin
  // One character typed among the existing bytes.
  if (Length(ANew) = Length(AOld) + 1) and (ACursor >= 1) and
     (ACursor <= Length(ANew)) and (ACursor <= Length(AOld)) and
     (Copy(ANew, 1, ACursor - 1) + Copy(ANew, ACursor + 1, MaxInt) = AOld) then
  begin
    Pos := ACursor;
    Ch := UpCase(ANew[Pos]);
    AText := AOld;
    ACursor2 := ACursor - 1;
    if not IsHexFieldChar(Ch) then
      Exit;
    if Pos > 1 then
      Prev := AOld[Pos - 1]
    else
      Prev := ' ';
    if Ch = '?' then
      Fill := '?'
    else
      Fill := '0';
    if (Prev <> ' ') and (AOld[Pos] <> ' ') then
    begin
      AText[Pos] := Ch;
      ACursor2 := Pos;
    end
    else if AOld[Pos] = ' ' then
    begin
      AText := Copy(AOld, 1, Pos - 1) + ' ' + Ch + Fill + Copy(AOld, Pos, MaxInt);
      ACursor2 := Pos + 1;
    end
    else
    begin
      AText := Copy(AOld, 1, Pos - 1) + Ch + Fill + ' ' + Copy(AOld, Pos, MaxInt);
      ACursor2 := Pos;
    end;
    Exit;
  end;
  // One character deleted (Backspace or Delete leave the caret at the same place).
  if (Length(ANew) = Length(AOld) - 1) and (ACursor >= 0) and
     (ACursor < Length(AOld)) and
     (Copy(AOld, 1, ACursor) + Copy(AOld, ACursor + 2, MaxInt) = ANew) then
  begin
    R := ACursor + 1;
    AText := AOld;
    ACursor2 := ACursor;
    if AOld[R] = ' ' then
      Exit;
    if (R > 1) and (AOld[R - 1] <> ' ') then
      S := R - 1
    else
      S := R;
    if (S = R) and ((R = Length(AOld)) or (AOld[R + 1] = ' ')) then
    begin
      AText := Copy(AOld, 1, R - 1);
      if (AText <> '') and (AText[Length(AText)] = ' ') then
        SetLength(AText, Length(AText) - 1);
      ACursor2 := Min(ACursor, Length(AText));
      Exit;
    end;
    AText[R] := '0';
    if (AText[S] = '0') and (AText[S + 1] = '0') then
    begin
      if S + 2 <= Length(AText) then
      begin
        Delete(AText, S, 3);
        ACursor2 := S - 1;
      end
      else if S > 1 then
      begin
        Delete(AText, S - 1, 3);
        ACursor2 := Length(AText);
      end
      else
      begin
        AText := '';
        ACursor2 := 0;
      end;
    end;
    Exit;
  end;
  // Typing at the end, paste, selection delete: regroup what is left.
  Left := HexFieldDigits(Copy(ANew, 1, ACursor));
  Digits := Left + HexFieldDigits(Copy(ANew, ACursor + 1, MaxInt));
  AText := '';
  for I := 1 to Length(Digits) do
  begin
    if (I > 1) and Odd(I) then
      AText := AText + ' ';
    AText := AText + Digits[I];
  end;
  N := Length(Left);
  if N > 0 then
    ACursor2 := N + (N - 1) div 2
  else
    ACursor2 := 0;
end;

function FileHexMatch(const APath: string; const APattern: TArray<Integer>;
  out AOffset: Int64): Boolean;
const
  cChunk = 1024 * 1024;
var
  FS: TFileStream;
  Buf: TBytes;
  M, Have, Got, Keep, I, J: Integer;
  Base: Int64;
begin
  AOffset := -1;
  M := Length(APattern);
  if M = 0 then
    Exit(False);
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Buf, cChunk + M);
      Have := 0;
      Base := 0;
      repeat
        Got := FS.Read(Buf[Have], cChunk);
        if Got <= 0 then
          Break;
        Inc(Have, Got);
        for I := 0 to Have - M do
        begin
          J := 0;
          while (J < M) and ((APattern[J] < 0) or (Buf[I + J] = APattern[J])) do
            Inc(J);
          if J = M then
          begin
            AOffset := Base + I;
            Exit(True);
          end;
        end;
        // The next window starts where the last complete one ended, so a match
        // that straddles two reads is still seen.
        Keep := Min(M - 1, Have);
        if Keep > 0 then
          Move(Buf[Have - Keep], Buf[0], Keep);
        Inc(Base, Have - Keep);
        Have := Keep;
      until False;
    finally
      FS.Free;
    end;
  except
    Exit(False);
  end;
  Result := False;
end;

const
  cFindSnippetMaxLen = 200;

function TrimSnippet(const ALine: string): string;
begin
  Result := Trim(ALine);
  if Length(Result) > cFindSnippetMaxLen then
    Result := Copy(Result, 1, cFindSnippetMaxLen) + #$2026;
end;

/// <summary>Reads APath (size-capped) and scans
/// it line by line for ANeedle - plain substring/whole-word, or (AUseRegex)
/// a compiled regex. Returns the first matching line (1-based) and a
/// trimmed copy of it. A malformed regex is caught per-file (defensive:
/// callers should already have validated the pattern once via
/// ValidateRegexPattern before starting the walk) and just means no match,
/// not a crashed job.</summary>
function FileContentMatch(const APath, ANeedle: string; ACaseSensitive,
  AWholeWords, AUseRegex: Boolean; out ALine: Integer; out ASnippet: string): Boolean;
var
  Bytes: TBytes;
  Text: string;
  Enc: TTextFileEncoding;
  IsBinary: Boolean;
  FS: TFileStream;
  Lines: TArray<string>;
  Opts: TRegExOptions;
  I: Integer;
begin
  ALine := 0;
  ASnippet := '';
  if ANeedle = '' then
    Exit(True);
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if (FS.Size <= 0) or (FS.Size > cFindMaxContentBytes) then
        Exit(False);
      SetLength(Bytes, FS.Size);
      FS.ReadBuffer(Bytes[0], FS.Size);
    finally
      FS.Free;
    end;
    // BOM, UTF-8, UTF-16, ANSI/OEM and CJK code pages are detected like in
    // the viewer; binary content still gets a single-byte decode so ASCII
    // needles are found in it.
    if not DetectAndDecodeText(Bytes, Text, Enc, IsBinary) or IsBinary then
      Text := TEncoding.ANSI.GetString(Bytes);
    Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    if AUseRegex then
    begin
      Opts := [roNotEmpty];
      if not ACaseSensitive then
        Opts := Opts + [roIgnoreCase];
      for I := 0 to High(Lines) do
        try
          if TRegEx.IsMatch(Lines[I], ANeedle, Opts) then
          begin
            ALine := I + 1;
            ASnippet := TrimSnippet(Lines[I]);
            Exit(True);
          end;
        except
          // Malformed pattern reaching here despite upfront validation -
          // treat as no match on this line rather than aborting the job.
        end;
    end
    else
      for I := 0 to High(Lines) do
        if TextContainsAbs(Lines[I], ANeedle, ACaseSensitive, AWholeWords) then
        begin
          ALine := I + 1;
          ASnippet := TrimSnippet(Lines[I]);
          Exit(True);
        end;
    Result := False;
  except
    Result := False;
  end;
end;

procedure QueueFindProgress(const AOnProgress: TFindProgressCallback;
  ACount: Integer; const ADir: string);
begin
  if not Assigned(AOnProgress) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      AOnProgress(ACount, ADir);
    end);
end;

{ Name-only searches (empty ContainingText) match every file. }
function FindContentMatch(const AFilePath: string; const AOptions: TFindOptions;
  out ALine: Integer; out ASnippet: string): Boolean;
var
  Pattern: TArray<Integer>;
  Offset: Int64;
  Error: string;
begin
  ALine := 0;
  ASnippet := '';
  if (AOptions.ContainingText = '') and (Trim(AOptions.HexBytes) = '') then
    Exit(True);
  // Both fields filled: the file has to satisfy both. The text hit supplies
  // the line; with bytes only, the hit shows the offset.
  if Trim(AOptions.HexBytes) <> '' then
  begin
    if not TryParseHexPattern(AOptions.HexBytes, Pattern, Error) or
       not FileHexMatch(AFilePath, Pattern, Offset) then
      Exit(False);
    ASnippet := Format('@ 0x%.8X', [Offset]);
  end;
  if AOptions.ContainingText = '' then
    Exit(True);
  Result := FileContentMatch(AFilePath, AOptions.ContainingText,
    AOptions.CaseSensitive, AOptions.WholeWords, AOptions.UseRegex, ALine,
    ASnippet);
end;

procedure FindFilesAsync(const AOptions: TFindOptions; ACancel: IJobCancelToken;
  AOnProgress: TFindProgressCallback; AOnDone: TFindDoneCallback);
var
  Opts: TFindOptions;
  Cancel: IJobCancelToken;
  OnProgress: TFindProgressCallback;
  OnDone: TFindDoneCallback;
  Masks: TArray<string>;
begin
  Opts := AOptions;
  Opts.RootPath := ExcludeTrailingPathDelimiter(Trim(Opts.RootPath));
  if (Length(Opts.RootPath) = 2) and (Opts.RootPath[2] = ':') then
    Opts.RootPath := Opts.RootPath + PathDelim;
  if Trim(Opts.Mask) = '' then
    Opts.Mask := '*.*';
  Masks := SplitMasks(Opts.Mask);
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;

  TThread.CreateAnonymousThread(
    procedure
    var
      List: TList<TFindHit>;
      Err: TVfsError;
      LastProgressTick: Cardinal;
      Hits: TArray<TFindHit>;
      Stack: TStack<string>;
      Dir, Full, Name: string;
      SR: TSearchRec;
      Code: Integer;
      IsDir: Boolean;
      Needle: string;
      Hit: TFindHit;
      HitLine: Integer;
      HitSnippet: string;

    begin
      Err := TVfsError.Ok;
      List := TList<TFindHit>.Create;
      Stack := TStack<string>.Create;
      LastProgressTick := 0;
      Needle := Opts.ContainingText;
      try
        try
          if JobCancelRequested(Cancel) then
            Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath)
          else if not TDirectory.Exists(Opts.RootPath) then
            Err := TVfsError.Make(vecNotFound, 'Path not found', Opts.RootPath)
          else
          begin
            Stack.Push(Opts.RootPath);
            while (Stack.Count > 0) and not JobCancelRequested(Cancel) and
              (List.Count < cFindMaxResults) do
            begin
              Dir := Stack.Pop;
              if (LastProgressTick = 0) or
                 (TThread.GetTickCount - LastProgressTick >= 80) then
              begin
                LastProgressTick := TThread.GetTickCount;
                QueueFindProgress(OnProgress, List.Count, Dir);
              end;

              Code := FindFirst(SafeCombinePath(Dir, '*'), faAnyFile, SR);
              try
                while Code = 0 do
                begin
                  if JobCancelRequested(Cancel) or (List.Count >= cFindMaxResults) then
                    Break;
                  Name := SR.Name;
                  if (Name <> '.') and (Name <> '..') then
                  begin
                    Full := SafeCombinePath(Dir, Name);
                    IsDir := (SR.Attr and faDirectory) <> 0;
                    if IsDir then
                    begin
                      if Opts.SearchFolders and NameMatchesAnyMask(Name, Masks) and
                         (Needle = '') and (Trim(Opts.HexBytes) = '') and
                         FindEntryPassesFilters(Opts, True, 0, SR.TimeStamp, SR.Attr) then
                      begin
                        Hit.Path := Full;
                        Hit.Line := 0;
                        Hit.Snippet := '';
                        List.Add(Hit);
                      end;
                      if Opts.Subdirs then
                        Stack.Push(Full);
                    end
                    else if NameMatchesAnyMask(Name, Masks) and
                            FindEntryPassesFilters(Opts, False, SR.Size, SR.TimeStamp,
                              SR.Attr) then
                    begin
                      if FindContentMatch(Full, Opts, HitLine, HitSnippet) then
                      begin
                        Hit.Path := Full;
                        Hit.Line := HitLine;
                        Hit.Snippet := HitSnippet;
                        List.Add(Hit);
                      end;
                    end;
                  end;
                  Code := FindNext(SR);
                end;
              finally
                FindClose(SR);
              end;
            end;

            if JobCancelRequested(Cancel) then
              Err := TVfsError.Make(vecCancelled, 'Cancelled', Opts.RootPath);
          end;
        except
          on E: Exception do
            Err := TVfsError.Make(vecIOError, E.Message, Opts.RootPath);
        end;
        Hits := List.ToArray;
      finally
        Stack.Free;
        List.Free;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnDone) then
            OnDone(Hits, Err);
        end);
    end).Start;
end;

end.
