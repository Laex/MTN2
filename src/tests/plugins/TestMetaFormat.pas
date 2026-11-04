unit TestMetaFormat;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMetaFormat = class
  public
    [Test] procedure TestPngSize;
    [Test] procedure TestGifSize;
    [Test] procedure TestBmpSize;
    [Test] procedure TestWebpExtendedSize;
    [Test] procedure TestJpegSizeAndExif;
    [Test] procedure TestJpegWithoutExifKeepsTheSize;
    [Test] procedure TestTruncatedAndUnknownDataIsRejected;
    [Test] procedure TestId3v2Frames;
    [Test] procedure TestId3v2TagSizeAndMissingTag;
    [Test] procedure TestId3v1Tag;
    [Test] procedure TestSummaries;
    [Test] procedure TestKindByExtension;
    [Test] procedure TestDescribeFileReadsAFileOnDisk;
    [Test] procedure TestDescribeFileOfAMissingFileIsEmpty;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uMetaFormat, uMetaReader;

procedure Put(var AB: TBytes; const AData: array of Byte);
var
  N, I: Integer;
begin
  N := Length(AB);
  SetLength(AB, N + Length(AData));
  for I := 0 to High(AData) do
    AB[N + I] := AData[I];
end;

procedure PutText(var AB: TBytes; const AText: AnsiString);
var
  N, I: Integer;
begin
  N := Length(AB);
  SetLength(AB, N + Length(AText));
  for I := 1 to Length(AText) do
    AB[N + I - 1] := Byte(AText[I]);
end;

function Padded(const AB: TBytes; ATotal: Integer): TBytes;
begin
  Result := AB;
  if Length(Result) < ATotal then
    SetLength(Result, ATotal);
end;

procedure TTestMetaFormat.TestPngSize;
var
  B: TBytes;
  Info: TImageInfo;
begin
  B := nil;
  Put(B, [$89, $50, $4E, $47, $0D, $0A, $1A, $0A, 0, 0, 0, 13]);
  PutText(B, 'IHDR');
  Put(B, [0, 0, 7, $80, 0, 0, 4, $38, 8, 6]);
  Assert.IsTrue(ParseImageInfo(B, Info));
  Assert.AreEqual('PNG', Info.Format);
  Assert.AreEqual(1920, Info.Width);
  Assert.AreEqual(1080, Info.Height);
end;

procedure TTestMetaFormat.TestGifSize;
var
  B: TBytes;
  Info: TImageInfo;
begin
  B := nil;
  PutText(B, 'GIF89a');
  Put(B, [$40, 1, $F0, 0, 0, 0]);
  Assert.IsTrue(ParseImageInfo(Padded(B, 16), Info));
  Assert.AreEqual('GIF', Info.Format);
  Assert.AreEqual(320, Info.Width);
  Assert.AreEqual(240, Info.Height);
end;

procedure TTestMetaFormat.TestBmpSize;
var
  B: TBytes;
  Info: TImageInfo;
begin
  B := nil;
  PutText(B, 'BM');
  SetLength(B, 18);
  // 100 wide, a top-down bitmap stores a negative height
  Put(B, [100, 0, 0, 0, $CE, $FF, $FF, $FF]);
  Assert.IsTrue(ParseImageInfo(B, Info));
  Assert.AreEqual('BMP', Info.Format);
  Assert.AreEqual(100, Info.Width);
  Assert.AreEqual(50, Info.Height);
end;

procedure TTestMetaFormat.TestWebpExtendedSize;
var
  B: TBytes;
  Info: TImageInfo;
begin
  B := nil;
  PutText(B, 'RIFF');
  Put(B, [0, 0, 0, 0]);
  PutText(B, 'WEBPVP8X');
  Put(B, [10, 0, 0, 0, 0, 0, 0, 0]);
  // width - 1 = 639, height - 1 = 479
  Put(B, [$7F, $02, 0, $DF, $01, 0]);
  Assert.IsTrue(ParseImageInfo(B, Info));
  Assert.AreEqual('WebP', Info.Format);
  Assert.AreEqual(640, Info.Width);
  Assert.AreEqual(480, Info.Height);
end;

function ExifJpeg: TBytes;
var
  Tiff, Seg: TBytes;
  Len: Integer;
begin
  Tiff := nil;
  // little endian header, IFD0 at 8
  Put(Tiff, [Ord('I'), Ord('I'), 42, 0, 8, 0, 0, 0]);
  // IFD0: three entries - Make at 68, Model at 74, the pointer to the Exif IFD at 50
  Put(Tiff, [3, 0]);
  Put(Tiff, [$0F, $01, 2, 0, 6, 0, 0, 0, 68, 0, 0, 0]);
  Put(Tiff, [$10, $01, 2, 0, 7, 0, 0, 0, 74, 0, 0, 0]);
  Put(Tiff, [$69, $87, 4, 0, 1, 0, 0, 0, 50, 0, 0, 0]);
  Put(Tiff, [0, 0, 0, 0]);
  // Exif IFD: DateTimeOriginal at 81
  Put(Tiff, [1, 0]);
  Put(Tiff, [$03, $90, 2, 0, 20, 0, 0, 0, 81, 0, 0, 0]);
  Put(Tiff, [0, 0, 0, 0]);
  PutText(Tiff, 'Canon'#0);
  PutText(Tiff, 'EOS R5'#0);
  PutText(Tiff, '2024:05:01 12:00:03'#0);

  Seg := nil;
  PutText(Seg, 'Exif'#0#0);
  Seg := Seg + Tiff;
  Len := Length(Seg) + 2;

  Result := nil;
  Put(Result, [$FF, $D8, $FF, $E1, Len shr 8, Len and $FF]);
  Result := Result + Seg;
  // SOF0: 3000 high, 4000 wide, one component
  Put(Result, [$FF, $C0, 0, 11, 8, $0B, $B8, $0F, $A0, 1, 1, $11, 0]);
  Put(Result, [$FF, $DA, 0, 2]);
end;

procedure TTestMetaFormat.TestJpegSizeAndExif;
var
  Info: TImageInfo;
begin
  Assert.IsTrue(ParseImageInfo(ExifJpeg, Info));
  Assert.AreEqual('JPEG', Info.Format);
  Assert.AreEqual(4000, Info.Width);
  Assert.AreEqual(3000, Info.Height);
  Assert.AreEqual('Canon EOS R5', Info.Camera);
  Assert.AreEqual('2024-05-01 12:00:03', Info.Taken);
end;

procedure TTestMetaFormat.TestJpegWithoutExifKeepsTheSize;
var
  B: TBytes;
  Info: TImageInfo;
begin
  B := nil;
  Put(B, [$FF, $D8, $FF, $C0, 0, 11, 8, 0, $64, 0, $C8, 1, 1, $11, 0, $FF, $DA, 0, 2]);
  Assert.IsTrue(ParseImageInfo(B, Info));
  Assert.AreEqual(200, Info.Width);
  Assert.AreEqual(100, Info.Height);
  Assert.AreEqual('', Info.Camera);
  Assert.AreEqual('JPEG 200x100', ImageSummary(Info));
end;

procedure TTestMetaFormat.TestTruncatedAndUnknownDataIsRejected;
var
  B, Cut: TBytes;
  Info: TImageInfo;
  N: Integer;
begin
  Assert.IsFalse(ParseImageInfo(nil, Info));
  Assert.IsFalse(ParseImageInfo(Padded(nil, 64), Info), 'zeros are no image');
  // Every prefix of a JPEG with EXIF is safe to parse.
  B := ExifJpeg;
  for N := 0 to Length(B) - 1 do
  begin
    Cut := Copy(B, 0, N);
    ParseImageInfo(Cut, Info);
  end;
  Cut := Copy(B, 0, 30);
  Assert.IsFalse(ParseImageInfo(Cut, Info), 'a JPEG cut before the size has none');
end;

function Id3v23Tag: TBytes;
var
  Body: TBytes;
  procedure Frame(const AId: AnsiString; const AData: TBytes);
  var
    L: Integer;
  begin
    PutText(Body, AId);
    L := Length(AData);
    Put(Body, [0, 0, L shr 8, L and $FF, 0, 0]);
    Body := Body + AData;
  end;
  function Enc0(const AText: AnsiString): TBytes;
  begin
    Result := nil;
    Put(Result, [0]);
    PutText(Result, AText);
  end;
  function Utf8(const AText: string): TBytes;
  begin
    Result := [3] + TEncoding.UTF8.GetBytes(AText);
  end;
var
  Size: Integer;
begin
  Body := nil;
  Frame('TIT2', Enc0('Song'));
  Frame('TPE1', Utf8('Artist ' + #$00E9));
  Frame('TALB', Enc0('Album'));
  Frame('TYER', Enc0('2020'));
  Result := nil;
  PutText(Result, 'ID3');
  Size := Length(Body);
  Put(Result, [3, 0, 0, (Size shr 21) and $7F, (Size shr 14) and $7F, (Size shr 7) and $7F, Size and $7F]);
  Result := Result + Body;
end;

procedure TTestMetaFormat.TestId3v2Frames;
var
  Tags: TAudioTags;
begin
  Assert.IsTrue(ParseId3v2(Id3v23Tag, Tags));
  Assert.AreEqual('Song', Tags.Title);
  Assert.AreEqual('Artist ' + #$00E9, Tags.Artist);
  Assert.AreEqual('Album', Tags.Album);
  Assert.AreEqual('2020', Tags.Year);
end;

procedure TTestMetaFormat.TestId3v2TagSizeAndMissingTag;
var
  T: TBytes;
  Tags: TAudioTags;
begin
  T := Id3v23Tag;
  Assert.AreEqual(Integer(Length(T)), Id3v2TagSize(Copy(T, 0, 10)));
  Assert.AreEqual(0, Id3v2TagSize(Padded(nil, 32)));
  Assert.IsFalse(ParseId3v2(Padded(nil, 32), Tags));
  // A tag cut in the middle of its first frame gives nothing and does not fail.
  Assert.IsFalse(ParseId3v2(Copy(T, 0, 24), Tags));
  Assert.AreEqual('', Tags.Title);
end;

procedure TTestMetaFormat.TestId3v1Tag;
var
  B: TBytes;
  Tags: TAudioTags;
begin
  SetLength(B, 128);
  B[0] := Ord('T');
  B[1] := Ord('A');
  B[2] := Ord('G');
  Move(AnsiString('Old Song')[1], B[3], 8);
  Move(AnsiString('Old Artist')[1], B[33], 10);
  Move(AnsiString('1999')[1], B[93], 4);
  Assert.IsTrue(ParseId3v1(B, Tags));
  Assert.AreEqual('Old Song', Tags.Title);
  Assert.AreEqual('Old Artist', Tags.Artist);
  Assert.AreEqual('1999', Tags.Year);
  Assert.IsFalse(ParseId3v1(Padded(nil, 128), Tags));
end;

procedure TTestMetaFormat.TestSummaries;
var
  Tags: TAudioTags;
  Info: TImageInfo;
begin
  Tags.Artist := 'A';
  Tags.Title := 'T';
  Tags.Album := 'Al';
  Tags.Year := '2001';
  Assert.AreEqual('A - T  |  Al  |  2001', AudioSummary(Tags));
  Tags.Artist := '';
  Assert.AreEqual('T  |  Al  |  2001', AudioSummary(Tags));
  Assert.IsTrue(ParseImageInfo(ExifJpeg, Info));
  Assert.AreEqual('JPEG 4000x3000  |  Canon EOS R5  |  2024-05-01 12:00:03', ImageSummary(Info));
  Assert.AreEqual('', ImageSummary(Default(TImageInfo)));
end;

procedure TTestMetaFormat.TestKindByExtension;
begin
  Assert.AreEqual('image', MetaKindOf('C:\a\Photo.JPG'));
  Assert.AreEqual('image', MetaKindOf('x.webp'));
  Assert.AreEqual('audio', MetaKindOf('x.mp3'));
  Assert.AreEqual('exe', MetaKindOf('x.dll'));
  Assert.AreEqual('', MetaKindOf('x.txt'));
  Assert.AreEqual('', MetaKindOf('noext'));
end;

procedure TTestMetaFormat.TestDescribeFileReadsAFileOnDisk;
var
  Dir, Path: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'MTN2MetaTest_' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(Dir);
  try
    Path := TPath.Combine(Dir, 'p.jpg');
    TFile.WriteAllBytes(Path, ExifJpeg);
    Assert.AreEqual('JPEG 4000x3000  |  Canon EOS R5  |  2024-05-01 12:00:03', DescribeFile(Path));
    Path := TPath.Combine(Dir, 's.mp3');
    TFile.WriteAllBytes(Path, Id3v23Tag + Padded(nil, 100));
    Assert.AreEqual('Artist ' + #$00E9 + ' - Song  |  Album  |  2020', DescribeFile(Path));
    Path := TPath.Combine(Dir, 'n.txt');
    TFile.WriteAllText(Path, 'text');
    Assert.AreEqual('', DescribeFile(Path));
    {$IFDEF MSWINDOWS}
    Assert.AreNotEqual('', DescribeFile(TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\kernel32.dll')),
      'a system library has a version resource');
    {$ENDIF}
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestMetaFormat.TestDescribeFileOfAMissingFileIsEmpty;
begin
  Assert.AreEqual('', DescribeFile(TPath.Combine(TPath.GetTempPath, 'MTN2NoSuchFile.jpg')));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMetaFormat);

end.
