unit uMetaFormat;

{ File metadata read from the first bytes of a file: the size of an image and the
  camera data of a photo, the tags of an MP3 file. The parsers work on byte
  arrays and never read past their end; a damaged file gives False. }

interface

uses
  System.SysUtils;

type
  TImageInfo = record
    /// <summary>"PNG", "JPEG", "GIF", "BMP" or "WebP".</summary>
    Format: string;
    Width: Integer;
    Height: Integer;
    /// <summary>Camera make and model from the EXIF block.</summary>
    Camera: string;
    /// <summary>"YYYY-MM-DD HH:MM:SS" from the EXIF block.</summary>
    Taken: string;
  end;

  TAudioTags = record
    Title: string;
    Artist: string;
    Album: string;
    Year: string;
  end;

const
  /// <summary>How many leading bytes of an image file the parser needs.</summary>
  cImageHeadBytes = 256 * 1024;
  /// <summary>The biggest ID3v2 tag that is read.</summary>
  cMaxId3Bytes = 1024 * 1024;
  cId3v1Bytes = 128;

function ParseImageInfo(const ABytes: TBytes; out AInfo: TImageInfo): Boolean;

/// <summary>The size of the ID3v2 tag at the start of the file including its header
/// (0 when there is none).</summary>
function Id3v2TagSize(const AHead: TBytes): Integer;

function ParseId3v2(const ABytes: TBytes; out ATags: TAudioTags): Boolean;
function ParseId3v1(const ABytes: TBytes; out ATags: TAudioTags): Boolean;

/// <summary>The one-line description for the status line; '' when there is nothing to say.</summary>
function ImageSummary(const AInfo: TImageInfo): string;
function AudioSummary(const ATags: TAudioTags): string;

/// <summary>Kind of a file by its extension: 'image', 'audio', 'exe' or ''.</summary>
function MetaKindOf(const AFileName: string): string;

implementation

function Be16(const B: TBytes; P: Integer): Integer;
begin
  Result := (B[P] shl 8) or B[P + 1];
end;

function Le16(const B: TBytes; P: Integer): Integer;
begin
  Result := B[P] or (B[P + 1] shl 8);
end;

function Be32(const B: TBytes; P: Integer): Cardinal;
begin
  Result := (Cardinal(B[P]) shl 24) or (Cardinal(B[P + 1]) shl 16) or (Cardinal(B[P + 2]) shl 8) or B[P + 3];
end;

function Le32(const B: TBytes; P: Integer): Cardinal;
begin
  Result := Cardinal(B[P]) or (Cardinal(B[P + 1]) shl 8) or (Cardinal(B[P + 2]) shl 16) or (Cardinal(B[P + 3]) shl 24);
end;

function HasAscii(const B: TBytes; P: Integer; const AText: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := P + Length(AText) <= Length(B);
  if not Result then
    Exit;
  for I := 1 to Length(AText) do
    if B[P + I - 1] <> Byte(AText[I]) then
      Exit(False);
end;

function AsciiAt(const B: TBytes; P, ALen: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := P to P + ALen - 1 do
  begin
    if (I >= Length(B)) or (B[I] = 0) then
      Break;
    Result := Result + Char(B[I]);
  end;
  Result := Trim(Result);
end;

{ EXIF }

type
  TTiff = record
    Bytes: TBytes;
    Start: Integer;
    Big: Boolean;
  end;

function TiffU16(const T: TTiff; P: Integer): Integer;
begin
  if T.Big then
    Result := Be16(T.Bytes, T.Start + P)
  else
    Result := Le16(T.Bytes, T.Start + P);
end;

function TiffU32(const T: TTiff; P: Integer): Cardinal;
begin
  if T.Big then
    Result := Be32(T.Bytes, T.Start + P)
  else
    Result := Le32(T.Bytes, T.Start + P);
end;

function TiffInside(const T: TTiff; P, ALen: Int64): Boolean;
begin
  Result := (P >= 0) and (ALen >= 0) and (T.Start + P + ALen <= Length(T.Bytes));
end;

// The text value of an ASCII entry whose 12 bytes start at AEntry.
function TiffAscii(const T: TTiff; AEntry: Integer): string;
var
  Count: Cardinal;
  At: Int64;
begin
  Result := '';
  Count := TiffU32(T, AEntry + 4);
  if (Count = 0) or (Count > 256) then
    Exit;
  if Count <= 4 then
    At := AEntry + 8
  else
    At := TiffU32(T, AEntry + 8);
  if TiffInside(T, At, Count) then
    Result := AsciiAt(T.Bytes, T.Start + Integer(At), Integer(Count));
end;

// Walks one IFD; AWanted = tags to read, results go to ATexts by tag. A pointer to
// the Exif IFD is returned in AExifIfd.
procedure ReadIfd(const T: TTiff; AOffset: Cardinal; var AMake, AModel, ATaken: string;
  out AExifIfd: Cardinal);
var
  Count, I, Entry, Tag: Integer;
begin
  AExifIfd := 0;
  if not TiffInside(T, AOffset, 2) then
    Exit;
  Count := TiffU16(T, AOffset);
  if Count > 512 then
    Exit;
  for I := 0 to Count - 1 do
  begin
    Entry := Integer(AOffset) + 2 + I * 12;
    if not TiffInside(T, Entry, 12) then
      Exit;
    Tag := TiffU16(T, Entry);
    case Tag of
      $010F: AMake := TiffAscii(T, Entry);
      $0110: AModel := TiffAscii(T, Entry);
      $8769: AExifIfd := TiffU32(T, Entry + 8);
      $9003: ATaken := TiffAscii(T, Entry);
    end;
  end;
end;

// "2024:05:01 12:00:03" -> "2024-05-01 12:00:03"
function ExifDate(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 10) and (Result[5] = ':') and (Result[8] = ':') then
  begin
    Result[5] := '-';
    Result[8] := '-';
  end;
  if Result.StartsWith('0000') then
    Result := '';
end;

procedure ParseExif(const ABytes: TBytes; AStart: Integer; var AInfo: TImageInfo);
var
  T: TTiff;
  Make, Model, Taken: string;
  Ifd0, ExifIfd, Ignore: Cardinal;
begin
  T.Bytes := ABytes;
  T.Start := AStart;
  if AStart + 8 > Length(ABytes) then
    Exit;
  if HasAscii(ABytes, AStart, 'II') then
    T.Big := False
  else if HasAscii(ABytes, AStart, 'MM') then
    T.Big := True
  else
    Exit;
  if TiffU16(T, 2) <> 42 then
    Exit;
  Ifd0 := TiffU32(T, 4);
  ReadIfd(T, Ifd0, Make, Model, Taken, ExifIfd);
  if ExifIfd <> 0 then
    ReadIfd(T, ExifIfd, Make, Model, Taken, Ignore);
  if Model <> '' then
  begin
    if (Make <> '') and not Model.StartsWith(Make, True) then
      AInfo.Camera := Make + ' ' + Model
    else
      AInfo.Camera := Model;
  end
  else
    AInfo.Camera := Make;
  AInfo.Taken := ExifDate(Taken);
end;

{ images }

function ParseJpeg(const B: TBytes; var AInfo: TImageInfo): Boolean;
var
  P, Len: Integer;
  Marker: Byte;
  GotSize: Boolean;
begin
  AInfo.Format := 'JPEG';
  GotSize := False;
  P := 2;
  while P + 4 <= Length(B) do
  begin
    if B[P] <> $FF then
      Break;
    while (P < Length(B)) and (B[P] = $FF) do
      Inc(P);
    if P >= Length(B) then
      Break;
    Marker := B[P];
    Inc(P);
    if (Marker = $D8) or (Marker = $01) or ((Marker >= $D0) and (Marker <= $D7)) then
      Continue;
    if (Marker = $D9) or (Marker = $DA) or (P + 2 > Length(B)) then
      Break;
    Len := Be16(B, P);
    if Len < 2 then
      Break;
    if (Marker = $E1) and HasAscii(B, P + 2, 'Exif') and (P + 2 + 6 <= Length(B)) then
      ParseExif(B, P + 2 + 6, AInfo)
    else if (Marker in [$C0..$C3, $C5..$C7, $C9..$CB, $CD..$CF]) and (P + 7 <= Length(B)) then
    begin
      AInfo.Height := Be16(B, P + 3);
      AInfo.Width := Be16(B, P + 5);
      GotSize := True;
    end;
    Inc(P, Len);
  end;
  Result := GotSize;
end;

function ParseWebp(const B: TBytes; var AInfo: TImageInfo): Boolean;
var
  Bits: Cardinal;
begin
  AInfo.Format := 'WebP';
  Result := False;
  if HasAscii(B, 12, 'VP8X') and (Length(B) >= 30) then
  begin
    AInfo.Width := 1 + (B[24] or (B[25] shl 8) or (B[26] shl 16));
    AInfo.Height := 1 + (B[27] or (B[28] shl 8) or (B[29] shl 16));
    Result := True;
  end
  else if HasAscii(B, 12, 'VP8L') and (Length(B) >= 25) and (B[20] = $2F) then
  begin
    Bits := Le32(B, 21);
    AInfo.Width := 1 + Integer(Bits and $3FFF);
    AInfo.Height := 1 + Integer((Bits shr 14) and $3FFF);
    Result := True;
  end
  else if HasAscii(B, 12, 'VP8 ') and (Length(B) >= 30) then
  begin
    AInfo.Width := Le16(B, 26) and $3FFF;
    AInfo.Height := Le16(B, 28) and $3FFF;
    Result := True;
  end;
end;

function ParseImageInfo(const ABytes: TBytes; out AInfo: TImageInfo): Boolean;
begin
  AInfo := Default(TImageInfo);
  Result := False;
  if Length(ABytes) < 16 then
    Exit;
  if HasAscii(ABytes, 0, #$89'PNG') and (Length(ABytes) >= 24) then
  begin
    AInfo.Format := 'PNG';
    AInfo.Width := Integer(Be32(ABytes, 16));
    AInfo.Height := Integer(Be32(ABytes, 20));
    Result := True;
  end
  else if HasAscii(ABytes, 0, 'GIF8') then
  begin
    AInfo.Format := 'GIF';
    AInfo.Width := Le16(ABytes, 6);
    AInfo.Height := Le16(ABytes, 8);
    Result := True;
  end
  else if HasAscii(ABytes, 0, 'BM') and (Length(ABytes) >= 26) then
  begin
    AInfo.Format := 'BMP';
    AInfo.Width := Integer(Le32(ABytes, 18));
    AInfo.Height := Abs(Integer(Le32(ABytes, 22)));
    Result := True;
  end
  else if HasAscii(ABytes, 0, 'RIFF') and HasAscii(ABytes, 8, 'WEBP') then
    Result := ParseWebp(ABytes, AInfo)
  else if (ABytes[0] = $FF) and (ABytes[1] = $D8) then
    Result := ParseJpeg(ABytes, AInfo);
  if Result and ((AInfo.Width <= 0) or (AInfo.Height <= 0)) then
    Result := False;
end;

{ ID3 }

function SyncSafe(const B: TBytes; P: Integer): Integer;
begin
  Result := (B[P] shl 21) or (B[P + 1] shl 14) or (B[P + 2] shl 7) or B[P + 3];
end;

function Id3v2TagSize(const AHead: TBytes): Integer;
begin
  Result := 0;
  if (Length(AHead) >= 10) and HasAscii(AHead, 0, 'ID3') and (AHead[3] in [2..4]) then
    Result := 10 + SyncSafe(AHead, 6);
end;

// The text of a text frame body: the first byte names the encoding.
function FrameText(const B: TBytes; AStart, ALen: Integer): string;
var
  Enc: TEncoding;
  Body: TBytes;
  Skip, I: Integer;
begin
  Result := '';
  if (ALen < 2) or (AStart + ALen > Length(B)) then
    Exit;
  Skip := 1;
  case B[AStart] of
    0:
      begin
        // ISO-8859-1: every byte is the code point of the same number.
        for I := AStart + 1 to AStart + ALen - 1 do
          Result := Result + Char(B[I]);
        Exit(Trim(Result).Replace(#0, ''));
      end;
    1:
      begin
        // The byte order mark decides little or big endian.
        if (ALen >= 3) and (B[AStart + 1] = $FE) and (B[AStart + 2] = $FF) then
          Enc := TEncoding.BigEndianUnicode
        else
          Enc := TEncoding.Unicode;
        if ALen >= 3 then
          Skip := 3;
      end;
    2: Enc := TEncoding.BigEndianUnicode;
    3: Enc := TEncoding.UTF8;
  else
    Exit;
  end;
  Body := Copy(B, AStart + Skip, ALen - Skip);
  Result := Trim(Enc.GetString(Body)).Replace(#0, '');
end;

procedure StoreFrame(const AId, AText: string; var ATags: TAudioTags);
begin
  if (AId = 'TIT2') or (AId = 'TT2') then
    ATags.Title := AText
  else if (AId = 'TPE1') or (AId = 'TP1') then
    ATags.Artist := AText
  else if (AId = 'TALB') or (AId = 'TAL') then
    ATags.Album := AText
  else if (AId = 'TDRC') or (AId = 'TYER') or (AId = 'TYE') then
  begin
    if ATags.Year = '' then
      ATags.Year := Copy(AText, 1, 4);
  end;
end;

function ParseId3v2(const ABytes: TBytes; out ATags: TAudioTags): Boolean;
var
  Version, IdLen, HeaderLen, P, Size, Total: Integer;
  Id: string;
begin
  ATags := Default(TAudioTags);
  Total := Id3v2TagSize(ABytes);
  if Total = 0 then
    Exit(False);
  if Total > Length(ABytes) then
    Total := Length(ABytes);
  Version := ABytes[3];
  if Version = 2 then
  begin
    IdLen := 3;
    HeaderLen := 6;
  end
  else
  begin
    IdLen := 4;
    HeaderLen := 10;
  end;
  P := 10;
  // An extended header comes first in a version 3 and 4 tag.
  if (Version >= 3) and ((ABytes[5] and $40) <> 0) and (P + 4 <= Total) then
  begin
    if Version = 4 then
      Inc(P, SyncSafe(ABytes, P))
    else
      Inc(P, 4 + Integer(Be32(ABytes, P)));
  end;
  while P + HeaderLen <= Total do
  begin
    if ABytes[P] = 0 then
      Break;
    Id := AsciiAt(ABytes, P, IdLen);
    if Version = 2 then
      Size := (ABytes[P + 3] shl 16) or (ABytes[P + 4] shl 8) or ABytes[P + 5]
    else if Version = 4 then
      Size := SyncSafe(ABytes, P + 4)
    else
      Size := Integer(Be32(ABytes, P + 4));
    if (Size < 0) or (P + HeaderLen + Size > Total) then
      Break;
    if (Id <> '') and (Id[1] = 'T') then
      StoreFrame(Id, FrameText(ABytes, P + HeaderLen, Size), ATags);
    Inc(P, HeaderLen + Size);
  end;
  Result := (ATags.Title <> '') or (ATags.Artist <> '') or (ATags.Album <> '');
end;

function ParseId3v1(const ABytes: TBytes; out ATags: TAudioTags): Boolean;
begin
  ATags := Default(TAudioTags);
  Result := (Length(ABytes) >= cId3v1Bytes) and HasAscii(ABytes, 0, 'TAG');
  if not Result then
    Exit;
  ATags.Title := AsciiAt(ABytes, 3, 30);
  ATags.Artist := AsciiAt(ABytes, 33, 30);
  ATags.Album := AsciiAt(ABytes, 63, 30);
  ATags.Year := AsciiAt(ABytes, 93, 4);
  Result := (ATags.Title <> '') or (ATags.Artist <> '') or (ATags.Album <> '');
end;

{ summaries }

procedure AddPart(var AText: string; const APart: string);
begin
  if APart = '' then
    Exit;
  if AText <> '' then
    AText := AText + '  |  ';
  AText := AText + APart;
end;

function ImageSummary(const AInfo: TImageInfo): string;
begin
  Result := '';
  if AInfo.Format = '' then
    Exit;
  AddPart(Result, Format('%s %dx%d', [AInfo.Format, AInfo.Width, AInfo.Height]));
  AddPart(Result, AInfo.Camera);
  AddPart(Result, AInfo.Taken);
end;

function AudioSummary(const ATags: TAudioTags): string;
var
  Name: string;
begin
  Result := '';
  Name := ATags.Title;
  if (ATags.Artist <> '') and (Name <> '') then
    Name := ATags.Artist + ' - ' + Name
  else if Name = '' then
    Name := ATags.Artist;
  AddPart(Result, Name);
  AddPart(Result, ATags.Album);
  AddPart(Result, ATags.Year);
end;

function MetaKindOf(const AFileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.png') or (Ext = '.gif') or (Ext = '.bmp') or
     (Ext = '.webp') then
    Result := 'image'
  else if Ext = '.mp3' then
    Result := 'audio'
  else if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.sys') or (Ext = '.ocx') or (Ext = '.scr') then
    Result := 'exe'
  else
    Result := '';
end;

end.
