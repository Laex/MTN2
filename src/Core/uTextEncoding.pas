unit uTextEncoding;

{ Detect / decode / encode text for Viewer/Editor VFS load-save.
  Detect: BOM → UTF-8/16; else valid UTF-8; else CP1251 vs CP866 by
  Cyrillic letter hits + scaled score margin (OEM only when clearly ahead).
  F8 cycles encodings; OEM uses the Windows OEM code page. }

interface

uses
  System.SysUtils;

type
  /// <summary>Encoding remembered between Open and Save.</summary>
  TTextFileEncoding = (
    tfeUtf8,      // UTF-8 without BOM
    tfeUtf8Bom,   // UTF-8 with BOM
    tfeUtf16LE,   // UTF-16 LE (BOM on write)
    tfeUtf16BE,   // UTF-16 BE (BOM on write)
    tfeAnsi,      // system ANSI code page (CP1251 on typical RU Windows)
    tfeOem        // system OEM code page (CP866 on typical RU Windows)
  );

function TextEncodingName(AEncoding: TTextFileEncoding): string;
function NextTextEncoding(AEncoding: TTextFileEncoding): TTextFileEncoding;
function TextEncodingListItems: TArray<string>;
function TryTextEncodingFromName(const AName: string;
  out AEncoding: TTextFileEncoding): Boolean;
function TryTextEncodingFromListIndex(AIndex: Integer;
  out AEncoding: TTextFileEncoding): Boolean;
/// <summary>Decode bytes. Returns False when content is treated as binary.</summary>
function DetectAndDecodeText(const ABytes: TBytes; out AText: string;
  out AEncoding: TTextFileEncoding; out AIsBinary: Boolean): Boolean;
/// <summary>Force-decode with a chosen encoding (skips BOM for UTF-8/16 when present).</summary>
function DecodeTextWithEncoding(const ABytes: TBytes;
  AEncoding: TTextFileEncoding): string;
function EncodeTextBytes(const AText: string; AEncoding: TTextFileEncoding): TBytes;
/// <summary>Drop a trailing UTF-8 multi-byte sequence left incomplete by an
/// arbitrary byte-count sample cut (not a real encoding error). Callers that
/// sniff encoding from a prefix of a larger file (Stage 24 streaming Viewer)
/// must trim the sample before IsLikelyUtf8/DetectAndDecodeText, or a cut
/// landing mid-character makes a genuinely UTF-8 file look invalid and
/// misdetects it as CP1251/CP866.</summary>
procedure TrimUtf8SampleTail(var ABytes: TBytes);

implementation

uses
  Winapi.Windows;

function OemEncoding: TEncoding;
begin
  Result := TEncoding.GetEncoding(Integer(GetOEMCP));
end;

{ Byte-for-char fallback when TEncoding cannot map the buffer. }
function BytesAsLatin1(const ABytes: TBytes; AIndex, ACount: Integer): string;
var
  I: Integer;
begin
  if AIndex < 0 then
    AIndex := 0;
  if (ACount <= 0) or (AIndex >= Length(ABytes)) then
    Exit('');
  if AIndex + ACount > Length(ABytes) then
    ACount := Length(ABytes) - AIndex;
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I + 1] := Char(ABytes[AIndex + I]);
end;

{ TEncoding.GetString raises EEncodingError when GetCharCount=0 (message
  "No mapping for the Unicode character..."). Never crash the viewer. }
function SafeGetString(Enc: TEncoding; const ABytes: TBytes;
  AIndex: Integer = 0; ACount: Integer = -1): string;
begin
  if ACount < 0 then
    ACount := Length(ABytes) - AIndex;
  if (ACount <= 0) or (Length(ABytes) = 0) then
    Exit('');
  try
    Result := Enc.GetString(ABytes, AIndex, ACount);
  except
    on E: EEncodingError do
      Result := BytesAsLatin1(ABytes, AIndex, ACount);
  end;
end;

function SafeGetBytes(Enc: TEncoding; const AText: string): TBytes;
var
  I: Integer;
begin
  if AText = '' then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  try
    Result := Enc.GetBytes(AText);
  except
    on E: EEncodingError do
    begin
      SetLength(Result, Length(AText));
      for I := 1 to Length(AText) do
        Result[I - 1] := Byte(Ord(AText[I]) and $FF);
    end;
  end;
end;

function TextEncodingName(AEncoding: TTextFileEncoding): string;
begin
  case AEncoding of
    tfeUtf8:    Result := 'UTF-8';
    tfeUtf8Bom: Result := 'UTF-8 BOM';
    tfeUtf16LE: Result := 'UTF-16 LE';
    tfeUtf16BE: Result := 'UTF-16 BE';
    tfeAnsi:    Result := 'ANSI';
    tfeOem:     Result := 'OEM';
  else
    Result := 'UTF-8';
  end;
end;

function NextTextEncoding(AEncoding: TTextFileEncoding): TTextFileEncoding;
begin
  case AEncoding of
    tfeUtf8:    Result := tfeUtf8Bom;
    tfeUtf8Bom: Result := tfeUtf16LE;
    tfeUtf16LE: Result := tfeUtf16BE;
    tfeUtf16BE: Result := tfeAnsi;
    tfeAnsi:    Result := tfeOem;
    tfeOem:     Result := tfeUtf8;
  else
    Result := tfeUtf8;
  end;
end;

function TextEncodingListItems: TArray<string>;
begin
  Result := TArray<string>.Create(
    'UTF-8', 'UTF-8 BOM', 'UTF-16 LE', 'UTF-16 BE', 'ANSI', 'OEM');
end;

function TryTextEncodingFromName(const AName: string;
  out AEncoding: TTextFileEncoding): Boolean;
var
  Items: TArray<string>;
  I: Integer;
begin
  Items := TextEncodingListItems;
  for I := 0 to High(Items) do
    if SameText(Items[I], Trim(AName)) then
      Exit(TryTextEncodingFromListIndex(I, AEncoding));
  Result := False;
  AEncoding := tfeUtf8;
end;

function TryTextEncodingFromListIndex(AIndex: Integer;
  out AEncoding: TTextFileEncoding): Boolean;
begin
  Result := True;
  case AIndex of
    0: AEncoding := tfeUtf8;
    1: AEncoding := tfeUtf8Bom;
    2: AEncoding := tfeUtf16LE;
    3: AEncoding := tfeUtf16BE;
    4: AEncoding := tfeAnsi;
    5: AEncoding := tfeOem;
  else
    begin
      Result := False;
      AEncoding := tfeUtf8;
    end;
  end;
end;

procedure TrimUtf8SampleTail(var ABytes: TBytes);
var
  N, P, Need, Steps: Integer;
  B: Byte;
begin
  N := Length(ABytes);
  if N = 0 then
    Exit;
  P := N - 1;
  Steps := 0;
  while (P >= 0) and (Steps < 3) do
  begin
    B := ABytes[P];
    if (B and $C0) = $80 then // continuation byte — keep walking back
    begin
      Dec(P);
      Inc(Steps);
      Continue;
    end;
    if B < $80 then
      Exit; // ASCII right before the cut — sample tail is already complete
    if (B and $E0) = $C0 then
      Need := 1
    else if (B and $F0) = $E0 then
      Need := 2
    else if (B and $F8) = $F0 then
      Need := 3
    else
      Exit; // not a valid lead byte either way — let IsLikelyUtf8 judge it
    if (N - 1 - P) < Need then
      SetLength(ABytes, P); // sequence needs more continuation bytes than the sample has
    Exit;
  end;
end;

function IsLikelyUtf8(const ABytes: TBytes): Boolean;
var
  I, N, C, Need: Integer;
begin
  N := Length(ABytes);
  if N = 0 then
    Exit(True);
  I := 0;
  while I < N do
  begin
    C := ABytes[I];
    if C < $80 then
    begin
      Inc(I);
      Continue;
    end;
    if (C and $E0) = $C0 then
      Need := 1
    else if (C and $F0) = $E0 then
      Need := 2
    else if (C and $F8) = $F0 then
      Need := 3
    else
      Exit(False);
    if (C = $C0) or (C = $C1) or (C >= $F5) then
      Exit(False);
    Inc(I);
    while Need > 0 do
    begin
      if (I >= N) or ((ABytes[I] and $C0) <> $80) then
        Exit(False);
      Inc(I);
      Dec(Need);
    end;
  end;
  Result := True;
end;

/// <summary>Number of non-ASCII UTF-8 code points (valid multi-byte sequences).</summary>
function Utf8MultiByteCount(const ABytes: TBytes): Integer;
var
  I, N, C, Need: Integer;
begin
  Result := 0;
  N := Length(ABytes);
  I := 0;
  while I < N do
  begin
    C := ABytes[I];
    if C < $80 then
    begin
      Inc(I);
      Continue;
    end;
    if (C and $E0) = $C0 then
      Need := 1
    else if (C and $F0) = $E0 then
      Need := 2
    else if (C and $F8) = $F0 then
      Need := 3
    else
      Exit;
    Inc(I);
    while Need > 0 do
    begin
      if (I >= N) or ((ABytes[I] and $C0) <> $80) then
        Exit;
      Inc(I);
      Dec(Need);
    end;
    Inc(Result);
  end;
end;

function SampleLen(const ABytes: TBytes): Integer;
const
  cMaxSample = 65536;
begin
  Result := Length(ABytes);
  if Result > cMaxSample then
    Result := cMaxSample;
end;

function IsTextControl(B: Byte): Boolean;
begin
  Result := (B = 9) or (B = 10) or (B = 13);
end;

/// <summary>Score Windows-1251 (CP1251) Cyrillic likelihood from raw bytes.</summary>
function ScoreCp1251(const ABytes: TBytes; out ALetterHits: Integer): Integer;
var
  I, N: Integer;
  B: Byte;
begin
  Result := 0;
  ALetterHits := 0;
  N := SampleLen(ABytes);
  for I := 0 to N - 1 do
  begin
    B := ABytes[I];
    if B < 32 then
    begin
      if not IsTextControl(B) then
        Dec(Result, 3);
      Continue;
    end;
    // Ё ё — distinctive for CP1251
    if (B = $A8) or (B = $B8) then
    begin
      Inc(Result, 4);
      Inc(ALetterHits);
    end
    // А-Я а-я (0xC0-0xFF) — primary CP1251 Cyrillic; rare as letters in CP866
    else if B >= $C0 then
    begin
      Inc(Result, 3);
      Inc(ALetterHits);
    end
    // 0x80-0xBF except Ё/ё: punctuation / rare — weak or slightly negative
    else if B >= $80 then
      Dec(Result);
  end;
end;

/// <summary>Score CP866 (OEM) Cyrillic likelihood from raw bytes.</summary>
function ScoreCp866(const ABytes: TBytes; out ALetterHits: Integer): Integer;
var
  I, N: Integer;
  B: Byte;
begin
  Result := 0;
  ALetterHits := 0;
  N := SampleLen(ABytes);
  for I := 0 to N - 1 do
  begin
    B := ABytes[I];
    if B < 32 then
    begin
      if not IsTextControl(B) then
        Dec(Result, 3);
      Continue;
    end;
    // А-п (0x80-0xAF), р-я/Ё/ё (0xE0-0xF1)
    if ((B >= $80) and (B <= $AF)) or ((B >= $E0) and (B <= $F1)) then
    begin
      Inc(Result, 3);
      Inc(ALetterHits);
    end
    // Box-drawing / fill (0xB0-0xDF) — common in OEM screens, not letters
    else if (B >= $B0) and (B <= $DF) then
      Dec(Result, 2)
    // 0xF2-0xFF in CP866 are rare symbols
    else if B >= $F2 then
      Dec(Result);
  end;
end;

function HasNul(const ABytes: TBytes): Boolean;
var
  B: Byte;
begin
  for B in ABytes do
    if B = 0 then
      Exit(True);
  Result := False;
end;

function DetectAndDecodeText(const ABytes: TBytes; out AText: string;
  out AEncoding: TTextFileEncoding; out AIsBinary: Boolean): Boolean;
var
  N, Mb, ScoreAnsi, ScoreOem, HitsAnsi, HitsOem, Margin: Integer;
  PreferOem: Boolean;
  Enc: TEncoding;
begin
  AText := '';
  AEncoding := tfeUtf8;
  AIsBinary := False;
  N := Length(ABytes);
  if N = 0 then
    Exit(True);

  // BOM first — UTF-16 may contain NUL bytes.
  if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    AEncoding := tfeUtf8Bom;
    AText := SafeGetString(TEncoding.UTF8, ABytes, 3, N - 3);
    Exit(True);
  end;
  if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    AEncoding := tfeUtf16LE;
    AText := SafeGetString(TEncoding.Unicode, ABytes, 2, N - 2);
    Exit(True);
  end;
  if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    AEncoding := tfeUtf16BE;
    AText := SafeGetString(TEncoding.BigEndianUnicode, ABytes, 2, N - 2);
    Exit(True);
  end;

  if HasNul(ABytes) then
  begin
    AIsBinary := True;
    Exit(False);
  end;

  // Structurally valid UTF-8 with real multi-byte chars → strong UTF-8.
  // Pure ASCII is also UTF-8.
  if IsLikelyUtf8(ABytes) then
  begin
    Mb := Utf8MultiByteCount(ABytes);
    if Mb > 0 then
    begin
      AEncoding := tfeUtf8;
      AText := SafeGetString(TEncoding.UTF8, ABytes);
      Exit(True);
    end;
    // ASCII-only: still UTF-8 (compatible with ANSI/OEM for 7-bit).
    AEncoding := tfeUtf8;
    AText := SafeGetString(TEncoding.UTF8, ABytes);
    Exit(True);
  end;

  // Not valid UTF-8 — choose Windows-1251 (ANSI) vs CP866 (OEM) by Cyrillic score.
  ScoreAnsi := ScoreCp1251(ABytes, HitsAnsi);
  ScoreOem := ScoreCp866(ABytes, HitsOem);
  // Base margin scales a little with sample size so short dumps aren't noisy.
  Margin := 8 + SampleLen(ABytes) div 2048;
  // Prefer OEM when clearly ahead, or when OEM letter hits dominate and
  // CP1251-range letters are scarce (typical DOS / console dumps).
  PreferOem := (ScoreOem > ScoreAnsi + Margin) or
    ((ScoreOem > ScoreAnsi) and (HitsOem >= HitsAnsi + 6) and (HitsAnsi < 8));
  if PreferOem then
  begin
    AEncoding := tfeOem;
    Enc := OemEncoding;
    try
      AText := SafeGetString(Enc, ABytes);
    finally
      Enc.Free;
    end;
  end
  else
  begin
    AEncoding := tfeAnsi;
    AText := SafeGetString(TEncoding.Default, ABytes);
  end;
  Result := True;
end;

function DecodeTextWithEncoding(const ABytes: TBytes;
  AEncoding: TTextFileEncoding): string;
var
  N: Integer;
  Enc: TEncoding;
begin
  N := Length(ABytes);
  if N = 0 then
    Exit('');

  case AEncoding of
    tfeUtf8Bom:
      begin
        if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
          Result := SafeGetString(TEncoding.UTF8, ABytes, 3, N - 3)
        else
          Result := SafeGetString(TEncoding.UTF8, ABytes);
      end;
    tfeUtf16LE:
      begin
        if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
          Result := SafeGetString(TEncoding.Unicode, ABytes, 2, N - 2)
        else
          Result := SafeGetString(TEncoding.Unicode, ABytes);
      end;
    tfeUtf16BE:
      begin
        if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
          Result := SafeGetString(TEncoding.BigEndianUnicode, ABytes, 2, N - 2)
        else
          Result := SafeGetString(TEncoding.BigEndianUnicode, ABytes);
      end;
    tfeAnsi:
      Result := SafeGetString(TEncoding.Default, ABytes);
    tfeOem:
      begin
        Enc := OemEncoding;
        try
          Result := SafeGetString(Enc, ABytes);
        finally
          Enc.Free;
        end;
      end;
  else
    // tfeUtf8
    begin
      if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
        Result := SafeGetString(TEncoding.UTF8, ABytes, 3, N - 3)
      else
        Result := SafeGetString(TEncoding.UTF8, ABytes);
    end;
  end;
end;

function EncodeTextBytes(const AText: string; AEncoding: TTextFileEncoding): TBytes;
var
  Body, Bom: TBytes;
  Enc: TEncoding;
begin
  case AEncoding of
    tfeUtf8Bom:
      begin
        Enc := TEncoding.UTF8;
        Bom := Enc.GetPreamble;
        Body := SafeGetBytes(Enc, AText);
      end;
    tfeUtf16LE:
      begin
        Enc := TEncoding.Unicode;
        Bom := Enc.GetPreamble;
        Body := SafeGetBytes(Enc, AText);
      end;
    tfeUtf16BE:
      begin
        Enc := TEncoding.BigEndianUnicode;
        Bom := Enc.GetPreamble;
        Body := SafeGetBytes(Enc, AText);
      end;
    tfeAnsi:
      begin
        SetLength(Bom, 0);
        Body := SafeGetBytes(TEncoding.Default, AText);
      end;
    tfeOem:
      begin
        SetLength(Bom, 0);
        Enc := OemEncoding;
        try
          Body := SafeGetBytes(Enc, AText);
        finally
          Enc.Free;
        end;
      end;
  else
    // tfeUtf8 — no BOM
    begin
      SetLength(Bom, 0);
      Body := SafeGetBytes(TEncoding.UTF8, AText);
    end;
  end;
  if Length(Bom) = 0 then
    Result := Body
  else
  begin
    SetLength(Result, Length(Bom) + Length(Body));
    if Length(Bom) > 0 then
      Move(Bom[0], Result[0], Length(Bom));
    if Length(Body) > 0 then
      Move(Body[0], Result[Length(Bom)], Length(Body));
  end;
end;

end.
