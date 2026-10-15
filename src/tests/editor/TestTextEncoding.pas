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
  Assert.IsTrue(Length(Items) = 9, 'nine encodings in the list');
  Assert.IsTrue(TryTextEncodingFromListIndex(6, Enc) and (Enc = tfeGbk), 'index 6');
  Assert.IsTrue(TryTextEncodingFromListIndex(7, Enc) and (Enc = tfeGb18030), 'index 7');
  Assert.IsTrue(TryTextEncodingFromListIndex(8, Enc) and (Enc = tfeBig5), 'index 8');
  Assert.IsFalse(TryTextEncodingFromListIndex(9, Enc), 'no index 9');
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

initialization
  TDUnitX.RegisterTestFixture(TTestTextEncoding);

end.
