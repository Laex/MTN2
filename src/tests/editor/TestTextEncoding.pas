unit TestTextEncoding;

{ uTextEncoding: GBK, GB18030 and Big5 as selectable and detected encodings,
  without mistaking Cyrillic or Latin-1 text for Chinese. The input bytes come
  from the platform's own converters. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTextEncoding = class
  public
    [Test] procedure TestNamesAndListIndexes;
    [Test] procedure TestCycleVisitsEveryEncoding;
    [Test] procedure TestRoundTrip;
    [Test] procedure TestGbkDetected;
    [Test] procedure TestBig5Detected;
    [Test] procedure TestGb18030FourByteDetected;
    [Test] procedure TestSampleCutInsideCharacter;
    [Test] procedure TestCyrillicIsNotChinese;
    [Test] procedure TestLatinSymbolsAreNotChinese;
    [Test] procedure TestUtf8StillWins;
    [Test] procedure TestUtf7KnownVectors;
    [Test] procedure TestUtf7RoundTrip;
    [Test] procedure TestUtf7IsNeverDetected;
    [Test] procedure TestUpperCaseCyrillicSingleByteDetected;
  end;

implementation

uses
  System.SysUtils, uTextEncoding;

const
  // Simplified: zhong wen ce shi bian ma jian ce.
  cSimplified = #$4E2D#$6587#$6D4B#$8BD5#$7F16#$7801#$68C0#$6D4B;
  // Traditional: fan ti zhong wen ce shi bian ma jian ce.
  cTraditional = #$7E41#$9AD4#$4E2D#$6587#$6E2C#$8A66#$7DE8#$78BC#$6AA2#$6E2C;
  // A supplementary-plane ideograph (U+20000) takes four bytes in GB18030.
  cExtB = #$D840#$DC00;
  cPrivet = #$041F#$0440#$0438#$0432#$0435#$0442;
  cSentence = #$041F#$0440#$0438#$0432#$0435#$0442 + ', ' + #$043C#$0438#$0440 +
    '! ' + #$042D#$0442#$043E + ' ' + #$0442#$0435#$0441#$0442 + '.';
  cCpGbk = 936;
  cCpBig5 = 950;
  cCpGb18030 = 54936;

function BytesIn(const AText: string; ACodePage: Integer): TBytes;
var
  Enc: TEncoding;
begin
  Enc := TEncoding.GetEncoding(ACodePage);
  try
    Result := Enc.GetBytes(AText);
  finally
    Enc.Free;
  end;
end;

function IsChinese(AEncoding: TTextFileEncoding): Boolean;
begin
  Result := AEncoding in [tfeGbk, tfeGb18030, tfeBig5];
end;

procedure TTestTextEncoding.TestNamesAndListIndexes;
var
  Items: TArray<string>;
  Enc: TTextFileEncoding;
begin
  Assert.AreEqual('GBK', TextEncodingName(tfeGbk));
  Assert.AreEqual('GB18030', TextEncodingName(tfeGb18030));
  Assert.AreEqual('Big5', TextEncodingName(tfeBig5));
  Items := TextEncodingListItems;
  Assert.IsTrue(Length(Items) = 10, 'ten encodings in the list');
  Assert.IsTrue(TryTextEncodingFromListIndex(6, Enc) and (Enc = tfeGbk), 'index 6');
  Assert.IsTrue(TryTextEncodingFromListIndex(7, Enc) and (Enc = tfeGb18030), 'index 7');
  Assert.IsTrue(TryTextEncodingFromListIndex(8, Enc) and (Enc = tfeBig5), 'index 8');
  Assert.IsTrue(TryTextEncodingFromListIndex(9, Enc) and (Enc = tfeUtf7), 'index 9');
  Assert.IsFalse(TryTextEncodingFromListIndex(10, Enc), 'no index 10');
  Assert.IsTrue(TryTextEncodingFromName('utf-7', Enc) and (Enc = tfeUtf7), 'UTF-7 by name');
  Assert.IsTrue(TryTextEncodingFromName('big5', Enc) and (Enc = tfeBig5), 'name is case-insensitive');
  Assert.IsTrue(TryTextEncodingFromName(' gb18030 ', Enc) and (Enc = tfeGb18030), 'name is trimmed');
  Assert.IsTrue(TryTextEncodingFromName('GBK', Enc) and (Enc = tfeGbk));
end;

procedure TTestTextEncoding.TestCycleVisitsEveryEncoding;
var
  Seen: set of TTextFileEncoding;
  Enc: TTextFileEncoding;
  I: Integer;
begin
  Seen := [];
  Enc := tfeUtf8;
  for I := 0 to Ord(High(TTextFileEncoding)) do
  begin
    Include(Seen, Enc);
    Enc := NextTextEncoding(Enc);
  end;
  Assert.IsTrue(Enc = tfeUtf8, 'the cycle closes after one full turn');
  for Enc := Low(TTextFileEncoding) to High(TTextFileEncoding) do
    Assert.IsTrue(Enc in Seen, TextEncodingName(Enc) + ' is reachable with F8');
end;

procedure TTestTextEncoding.TestRoundTrip;
begin
  Assert.AreEqual(cSimplified, DecodeTextWithEncoding(
    EncodeTextBytes(cSimplified, tfeGbk), tfeGbk), 'GBK');
  Assert.AreEqual(cTraditional, DecodeTextWithEncoding(
    EncodeTextBytes(cTraditional, tfeBig5), tfeBig5), 'Big5');
  Assert.AreEqual(cSimplified + cExtB, DecodeTextWithEncoding(
    EncodeTextBytes(cSimplified + cExtB, tfeGb18030), tfeGb18030), 'GB18030');
  Assert.IsTrue(Length(EncodeTextBytes(cSimplified, tfeGbk)) = Length(BytesIn(cSimplified, cCpGbk)),
    'same bytes as the platform converter, no byte order mark');
  Assert.IsTrue(Length(EncodeTextBytes(cSimplified, tfeGbk)) = 2 * Length(cSimplified),
    'two bytes per character');
end;

procedure TTestTextEncoding.TestGbkDetected;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cSimplified + ' ok 123', cCpGbk), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeGbk, 'encoding');
  Assert.IsFalse(IsBin);
  Assert.AreEqual(cSimplified + ' ok 123', Text);
end;

procedure TTestTextEncoding.TestBig5Detected;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cTraditional + ' ok 123', cCpBig5), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeBig5, 'encoding');
  Assert.AreEqual(cTraditional + ' ok 123', Text);
end;

procedure TTestTextEncoding.TestGb18030FourByteDetected;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cSimplified + cExtB + cSimplified, cCpGb18030),
    Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeGb18030, 'encoding');
  Assert.AreEqual(cSimplified + cExtB + cSimplified, Text);
end;

procedure TTestTextEncoding.TestSampleCutInsideCharacter;
var
  Bytes: TBytes;
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Bytes := BytesIn(cSimplified, cCpGbk);
  SetLength(Bytes, Length(Bytes) - 1);
  Assert.IsTrue(DetectAndDecodeText(Bytes, Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeGbk, 'a cut in the middle of the last character does not matter');
end;

procedure TTestTextEncoding.TestCyrillicIsNotChinese;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cSentence, 1251), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'CP1251 sentence');
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cSentence, 866), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'CP866 sentence');
  // One word whose letters all pair up into valid double-byte sequences.
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cPrivet, 1251), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'CP1251 single word');
  Assert.IsTrue(DetectAndDecodeText(BytesIn(cPrivet, 866), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'CP866 single word');
end;

procedure TTestTextEncoding.TestLatinSymbolsAreNotChinese;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  // Degree signs followed by a letter are valid lead/trail pairs byte for byte.
  Assert.IsTrue(DetectAndDecodeText(BytesIn('20' + #$00B0 + 'C 22' + #$00B0 + 'C 25' + #$00B0 + 'C',
    1252), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'degree signs');
  Assert.IsTrue(DetectAndDecodeText(BytesIn('caf' + #$00E9 + 'x na' + #$00EF + 've', 1252),
    Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'accented Latin letters');
end;

procedure TTestTextEncoding.TestUtf8StillWins;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  Assert.IsTrue(DetectAndDecodeText(TEncoding.UTF8.GetBytes(cSimplified), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeUtf8, 'valid UTF-8 is not taken for a legacy encoding');
  Assert.AreEqual(cSimplified, Text);
  Assert.IsTrue(DetectAndDecodeText(TEncoding.UTF8.GetBytes('plain ascii'), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeUtf8, 'ASCII stays UTF-8');
end;

function AsciiBytes(const AText: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(AText));
  for I := 1 to Length(AText) do
    Result[I - 1] := Byte(Ord(AText[I]));
end;

procedure TTestTextEncoding.TestUtf7KnownVectors;
begin
  // Vectors from RFC 2152.
  Assert.AreEqual('A' + #$2262 + #$0391 + '.',
    DecodeTextWithEncoding(AsciiBytes('A+ImIDkQ.'), tfeUtf7), 'A<NOT IDENTICAL TO><ALPHA>.');
  Assert.AreEqual('Hi Mom -' + #$263A + '-!',
    DecodeTextWithEncoding(AsciiBytes('Hi Mom -+Jjo--!'), tfeUtf7), 'smiley');
  Assert.AreEqual(#$65E5#$672C#$8A9E,
    DecodeTextWithEncoding(AsciiBytes('+ZeVnLIqe-'), tfeUtf7), 'nihongo');
  Assert.AreEqual('1+1=2', DecodeTextWithEncoding(AsciiBytes('1+-1=2'), tfeUtf7), 'plus sign');
  Assert.AreEqual('+ZeVnLIqe-', TEncoding.ASCII.GetString(
    EncodeTextBytes(#$65E5#$672C#$8A9E, tfeUtf7)), 'encoder output');
end;

procedure TTestTextEncoding.TestUtf7RoundTrip;
var
  Text: string;
begin
  Text := 'a+b ' + cSentence + ' ' + cSimplified + #13#10 + 'end-';
  Assert.AreEqual(Text, DecodeTextWithEncoding(EncodeTextBytes(Text, tfeUtf7), tfeUtf7));
  Assert.IsTrue(Length(EncodeTextBytes(Text, tfeUtf7)) > 0);
  Assert.IsFalse(EncodeTextBytes(Text, tfeUtf7)[0] > 127, 'seven-bit output');
end;

procedure TTestTextEncoding.TestUtf7IsNeverDetected;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
begin
  // UTF-7 text is plain ASCII to a detector, so it has to be chosen by hand.
  Assert.IsTrue(DetectAndDecodeText(EncodeTextBytes(cSentence, tfeUtf7), Text, Enc, IsBin));
  Assert.IsTrue(Enc <> tfeUtf7);
end;

procedure TTestTextEncoding.TestUpperCaseCyrillicSingleByteDetected;
var
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
  Caps: string;
begin
  Caps := UpperCase(cSentence);
  Assert.IsTrue(DetectAndDecodeText(BytesIn(Caps, 1251), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeAnsi, 'CP1251 capitals: ' + TextEncodingName(Enc));
  Assert.IsTrue(DetectAndDecodeText(BytesIn(Caps, 866), Text, Enc, IsBin));
  Assert.IsTrue(Enc = tfeOem, 'CP866 capitals: ' + TextEncodingName(Enc));
  Assert.IsTrue(DetectAndDecodeText(BytesIn(UpperCase(cPrivet), 1251), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'one CP1251 capitals word');
  Assert.IsTrue(DetectAndDecodeText(BytesIn(UpperCase(cPrivet), 866), Text, Enc, IsBin));
  Assert.IsFalse(IsChinese(Enc), 'one CP866 capitals word');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTextEncoding);

end.
