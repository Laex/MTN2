unit TestStreamingViewer;

{ Stage 24 regression: the line-indexed (streaming) Viewer path in uEditorDoc,
  plus the UTF-8 sample-trim in uTextEncoding that feeds its encoding sniff.

  Source is deliberately pure ASCII — every non-ASCII test string is built from
  explicit codepoints (#$xxxx). A pasted literal would depend on whether this
  .pas carries a UTF-8 BOM, which is the exact class of defect that produced
  the mojibake this test guards against. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStreamingViewer = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestSampleTrim;
    [Test] procedure TestStreamingBasics;
    [Test] procedure TestCacheEviction;
    [Test] procedure TestNoTrailingNewline;
    [Test] procedure TestSampleStraddle;
    [Test] procedure TestBinaryHex;
    [Test] procedure TestBinaryF4ToText;
    [Test] procedure TestStreamingUtf16;
    [Test] procedure TestStreamingUtf16NoTrailingNewline;
    [Test] procedure TestStreamingUtf16EncodingSwitchGuard;
    [Test] procedure TestSmallFileUnaffected;
    [Test] procedure TestStreamingIsReadOnly;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileVfs,
  uZipVfs,
  uFindSession,
  uFindVfs,
  uVfsRegistry,
  uVfsRouter,
  uTextEncoding,
  uEditorDoc;

const
  // Cyrillic "Тест" — codepoints, not a literal (see header note).
  cCyr = #$0422#$0435#$0441#$0442;
  cNoTrailMarker = 'LAST-LINE-NO-TRAILING-NEWLINE';

var
  GTempDir: string;

function LineText(AIndex: Integer): string;
begin
  Result := Format('Line %.7d ', [AIndex]) + cCyr + ' abcdefghij 0123456789';
end;

{ ---- fixtures -------------------------------------------------------------- }

function TempPath(const AName: string): string;
begin
  Result := TPath.Combine(GTempDir, AName);
end;

/// <summary>Write AText in AEncoding. TEncoding.UTF8 in Delphi emits a BOM via
/// TStreamWriter, which would change what the sniffer sees, so bytes are
/// produced explicitly instead.</summary>
procedure WriteBytesFile(const APath: string; const ABytes: TBytes);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(ABytes) > 0 then
      FS.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    FS.Free;
  end;
end;

/// <summary>Text file just over cEditorMaxBytes so the whole-buffer read
/// refuses it and the streaming path takes over. Returns the line count.</summary>
function MakeBigUtf8(const APath: string; ATrailingNewline: Boolean): Integer;
var
  SB: TStringBuilder;
  I: Integer;
  Bytes: TBytes;
begin
  SB := TStringBuilder.Create;
  try
    I := 0;
    // Count bytes conservatively via the UTF-16 length; the real byte count is
    // larger (Cyrillic is 2 bytes in UTF-8), so this over-runs the limit safely.
    while SB.Length < cEditorMaxBytes do
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
      Inc(I);
    end;
    if ATrailingNewline then
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
      Inc(I);
    end
    else
    begin
      SB.Append(cNoTrailMarker);
      Inc(I);
    end;
    Bytes := TEncoding.UTF8.GetBytes(SB.ToString);
    WriteBytesFile(APath, Bytes);
    Result := I;
  finally
    SB.Free;
  end;
end;

/// <summary>The regression that produced mojibake: a 2-byte UTF-8 sequence
/// straddling the cStreamSampleBytes cut. Without TrimUtf8SampleTail the
/// sniffer sees a truncated sequence, rejects UTF-8, and falls back to
/// CP1251/CP866 for the whole file.</summary>
procedure MakeStraddleFile(const APath: string);
var
  Head: TBytes;
  Body, All: TBytes;
  SB: TStringBuilder;
  I: Integer;
begin
  // Exactly cStreamSampleBytes-1 ASCII bytes, so the next (2-byte) char has its
  // lead byte inside the sample and its continuation byte outside.
  SetLength(Head, cStreamSampleBytes - 1);
  for I := 0 to High(Head) do
    if (I > 0) and (I mod 64 = 0) then
      Head[I] := 10 // keep it line-structured
    else
      Head[I] := Ord('a');

  SB := TStringBuilder.Create;
  try
    SB.Append(cCyr); // first char lands exactly on the cut
    SB.Append(#10);
    I := 0;
    while SB.Length < cEditorMaxBytes do
    begin
      SB.Append(LineText(I));
      SB.Append(#10);
      Inc(I);
    end;
    Body := TEncoding.UTF8.GetBytes(SB.ToString);
  finally
    SB.Free;
  end;

  SetLength(All, Length(Head) + Length(Body));
  Move(Head[0], All[0], Length(Head));
  Move(Body[0], All[Length(Head)], Length(Body));
  WriteBytesFile(APath, All);
end;

/// <summary>UTF-16 text file (with BOM) just over cEditorMaxBytes, so the
/// whole-buffer read refuses it and the UTF-16 streaming path takes over.
/// AIsLE picks LE (FF FE, TEncoding.Unicode) vs BE (FE FF,
/// TEncoding.BigEndianUnicode). Returns the line count, same contract as
/// MakeBigUtf8.</summary>
function MakeBigUtf16(const APath: string; AIsLE, ATrailingNewline: Boolean): Integer;
var
  SB: TStringBuilder;
  I: Integer;
  Body, Bom, All: TBytes;
  Enc: TEncoding;
begin
  SB := TStringBuilder.Create;
  try
    I := 0;
    while SB.Length * 2 < cEditorMaxBytes do
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
      Inc(I);
    end;
    if ATrailingNewline then
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
      Inc(I);
    end
    else
    begin
      SB.Append(cNoTrailMarker);
      Inc(I);
    end;
    if AIsLE then
      Enc := TEncoding.Unicode
    else
      Enc := TEncoding.BigEndianUnicode;
    Body := Enc.GetBytes(SB.ToString);
  finally
    SB.Free;
  end;
  SetLength(Bom, 2);
  if AIsLE then
  begin
    Bom[0] := $FF;
    Bom[1] := $FE;
  end
  else
  begin
    Bom[0] := $FE;
    Bom[1] := $FF;
  end;
  SetLength(All, Length(Bom) + Length(Body));
  Move(Bom[0], All[0], Length(Bom));
  Move(Body[0], All[Length(Bom)], Length(Body));
  WriteBytesFile(APath, All);
  Result := I;
end;

procedure MakeTinyBinary(const APath: string);
var
  Bytes: TBytes;
begin
  // MZ + NUL so DetectAndDecodeText treats it as binary (Hex viewer).
  Bytes := TBytes.Create(Ord('M'), Ord('Z'), 0, Ord('P'), Ord('E'), 0, 1, 2, 3);
  WriteBytesFile(APath, Bytes);
end;

procedure MakeBigBinary(const APath: string);
var
  Bytes: TBytes;
  I: Integer;
begin
  SetLength(Bytes, cEditorMaxBytes + 65536);
  for I := 0 to High(Bytes) do
    if I mod 137 = 0 then
      Bytes[I] := 0 // NULs make it unambiguously binary
    else
      Bytes[I] := Byte(I mod 251);
  WriteBytesFile(APath, Bytes);
end;

procedure MakeSmallUtf8(const APath: string);
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to 99 do
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
    end;
    WriteBytesFile(APath, TEncoding.UTF8.GetBytes(SB.ToString));
  finally
    SB.Free;
  end;
end;

{ ---- async plumbing -------------------------------------------------------- }

/// <summary>OpenAsync completes on the UI thread via TThread.Queue; a console
/// app must pump those itself.</summary>
function WaitDoc(ADoc: TEditorDoc): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while ADoc.Loading do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > 60000 then
      Exit(False);
  end;
  CheckSynchronize(0);
  Result := True;
end;

function OpenDoc(const APath: string): TEditorDoc;
begin
  Result := TEditorDoc.Create;
  Result.OpenAsync(PathToFileUri(APath));
  if not WaitDoc(Result) then
  begin
    Assert.Fail('timeout opening ' + APath);
  end;
end;

{ ---- tests ----------------------------------------------------------------- }

procedure TestSampleTrim;
var
  Bytes: TBytes;
  Text: string;
  Enc: TTextFileEncoding;
  IsBin: Boolean;
  Trimmed: TBytes;
begin

  // 'a' + lead byte of a 2-byte sequence, continuation missing.
  Bytes := TBytes.Create(Ord('a'), $D0);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 1, 'dangling 2-byte lead is dropped');
  Assert.IsTrue(DetectAndDecodeText(Trimmed, Text, Enc, IsBin) and (Enc = tfeUtf8),
    'trimmed sample still detects as UTF-8');

  // Untrimmed, the same sample is not valid UTF-8 and misdetects.
  Assert.IsTrue(not (DetectAndDecodeText(Bytes, Text, Enc, IsBin) and (Enc = tfeUtf8)),
    'untrimmed dangling sample does NOT detect as UTF-8 (the original bug)');

  // Complete 2-byte sequence must survive untouched.
  Bytes := TBytes.Create(Ord('a'), $D0, $A2);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 3, 'complete 2-byte sequence is kept');

  // 3-byte sequence cut after 1 and after 2 bytes.
  Bytes := TBytes.Create(Ord('a'), $E2, $80);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 1, '3-byte sequence missing 1 continuation is dropped');

  Bytes := TBytes.Create(Ord('a'), $E2, $80, $A6);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 4, 'complete 3-byte sequence is kept');

  // Pure ASCII and empty input are untouched.
  Bytes := TBytes.Create(Ord('a'), Ord('b'), Ord('c'));
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 3, 'ASCII tail is untouched');

  SetLength(Bytes, 0);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Assert.IsTrue(Length(Trimmed) = 0, 'empty input is safe');
end;

procedure TestStreamingBasics;
var
  Path: string;
  Doc: TEditorDoc;
  Expected: Integer;
  Mid: Integer;
begin
  Path := TempPath('big_utf8.txt');
  Expected := MakeBigUtf8(Path, True);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'document is ready');
    Assert.IsTrue(Doc.Error = '', 'no error: ' + Doc.Error);
    Assert.IsTrue(Doc.Streaming, 'opened in streaming mode');
    Assert.IsTrue(Doc.ReadOnly, 'streaming document is read-only');
    Assert.IsTrue(Doc.Encoding = tfeUtf8, 'encoding detected as UTF-8 (not CP1251/CP866)');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'first line matches exactly');
    Assert.IsTrue(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'last line matches exactly');

    // Random access must not depend on read order.
    Mid := Expected div 2;
    Assert.IsTrue(Doc.GetLine(Mid) = LineText(Mid), 'middle line (forward) matches');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'first line still matches after seeking');
    Assert.IsTrue(Doc.GetLine(Mid) = LineText(Mid), 'middle line re-read from cache matches');

    // Out-of-range access is defined, not a crash.
    Assert.IsTrue(Doc.GetLine(-1) = '', 'negative index returns empty');
    Assert.IsTrue(Doc.GetLine(Expected) = '', 'index past end returns empty');
    Assert.IsTrue(Doc.GetLine(Expected + 1000) = '', 'far past end returns empty');
  finally
    Doc.Free;
  end;
end;

procedure TestCacheEviction;
var
  Path: string;
  Doc: TEditorDoc;
  I, Count, Step: Integer;
  Ok: Boolean;
begin
  Path := TempPath('big_utf8.txt'); // reuse fixture from TestStreamingBasics
  Doc := OpenDoc(Path);
  try
    Count := Doc.LineCount;
    Assert.IsTrue(Count > cStreamCacheCap,
      Format('fixture has %d lines > cache cap %d', [Count, cStreamCacheCap]));

    // Walk enough distinct lines to force FIFO eviction, verifying as we go.
    Ok := True;
    Step := 1;
    I := 0;
    while (I < Count) and (I < cStreamCacheCap + 500) do
    begin
      if Doc.GetLine(I) <> LineText(I) then
      begin
        Ok := False;
        Writeln('    mismatch at line ', I);
        Break;
      end;
      Inc(I, Step);
    end;
    Assert.IsTrue(Ok, 'every line read while filling/evicting the cache is correct');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'line 0 still correct after eviction');
  finally
    Doc.Free;
  end;
end;

procedure TestNoTrailingNewline;
var
  Path: string;
  Doc: TEditorDoc;
  Expected: Integer;
begin
  Path := TempPath('big_notrail.txt');
  Expected := MakeBigUtf8(Path, False);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(Expected - 1) = cNoTrailMarker,
      'final line without trailing newline is complete');
  finally
    Doc.Free;
  end;
end;

procedure TestSampleStraddle;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Path := TempPath('straddle.txt');
  MakeStraddleFile(Path);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Assert.IsTrue(Doc.Encoding = tfeUtf8,
      'UTF-8 survives a sample cut mid-sequence (the mojibake regression)');
  finally
    Doc.Free;
  end;
end;

procedure TestBinaryHex;
var
  Path: string;
  Doc: TEditorDoc;
begin

  Path := TempPath('big_binary.bin');
  MakeBigBinary(Path);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(not Doc.Streaming, 'big binary is not streamed');
    Assert.IsTrue(Doc.Ready, 'big binary is ready');
    Assert.IsTrue(Doc.Binary, 'big binary is hex/binary');
    Assert.IsTrue(Doc.Error = '', 'big binary has no error: ' + Doc.Error);
    Assert.IsTrue(Pos('Hex', Doc.Status) > 0, 'status mentions Hex: ' + Doc.Status);
  finally
    Doc.Free;
  end;
end;

procedure TestBinaryF4ToText;
var
  Path: string;
  Doc: TEditorDoc;
begin

  Path := TempPath('tiny_binary.bin');
  MakeTinyBinary(Path);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'tiny binary is ready');
    Assert.IsTrue(Doc.Binary, 'tiny binary opens as hex/binary');
    Assert.IsTrue(Doc.ApplyEncoding(Doc.Encoding, True), 'F4 re-decode succeeds');
    Assert.IsTrue(not Doc.Binary, 'F4 leaves binary/hex lock');
    Assert.IsTrue(Doc.LineCount >= 1, 'F4 text view has at least one line');
    Assert.IsTrue(Pos('M', Doc.GetLine(0)) > 0, 'decoded text keeps printable prefix');
  finally
    Doc.Free;
  end;
end;

procedure TestStreamingUtf16;
var
  Path: string;
  Doc: TEditorDoc;
  Expected, Mid, I, Count, Step: Integer;
  Ok: Boolean;
begin

  // ---- LE: full coverage, including cache eviction (mirrors TestStreamingBasics
  // + TestCacheEviction for the UTF-8 fixture). ----
  Path := TempPath('big_utf16le.txt');
  Expected := MakeBigUtf16(Path, True, True);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'LE: document is ready');
    Assert.IsTrue(Doc.Error = '', 'LE: no error: ' + Doc.Error);
    Assert.IsTrue(Doc.Streaming, 'LE: opened in streaming mode');
    Assert.IsTrue(Doc.ReadOnly, 'LE: streaming document is read-only');
    Assert.IsTrue(Doc.Encoding = tfeUtf16LE, 'LE: encoding detected as UTF-16 LE');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('LE: line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(0) = LineText(0),
      'LE: first line matches exactly (no stray BOM/CR/LF folded in)');
    Assert.IsTrue(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'LE: last line matches exactly');
    Mid := Expected div 2;
    Assert.IsTrue(Doc.GetLine(Mid) = LineText(Mid), 'LE: middle line matches');

    Count := Doc.LineCount;
    Assert.IsTrue(Count > cStreamCacheCap,
      Format('LE: fixture has %d lines > cache cap %d', [Count, cStreamCacheCap]));
    Ok := True;
    Step := 1;
    I := 0;
    while (I < Count) and (I < cStreamCacheCap + 500) do
    begin
      if Doc.GetLine(I) <> LineText(I) then
      begin
        Ok := False;
        Writeln('    LE mismatch at line ', I);
        Break;
      end;
      Inc(I, Step);
    end;
    Assert.IsTrue(Ok, 'LE: every line read while filling/evicting the cache is correct');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'LE: line 0 still correct after eviction');
  finally
    Doc.Free;
  end;

  // ---- BE: same shape, endianness-specific spot checks. ----
  Path := TempPath('big_utf16be.txt');
  Expected := MakeBigUtf16(Path, False, True);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'BE: document is ready');
    Assert.IsTrue(Doc.Streaming, 'BE: opened in streaming mode');
    Assert.IsTrue(Doc.ReadOnly, 'BE: streaming document is read-only');
    Assert.IsTrue(Doc.Encoding = tfeUtf16BE, 'BE: encoding detected as UTF-16 BE');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('BE: line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'BE: first line matches exactly');
    Assert.IsTrue(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'BE: last line matches exactly');
    Mid := Expected div 2;
    Assert.IsTrue(Doc.GetLine(Mid) = LineText(Mid), 'BE: middle line matches');
  finally
    Doc.Free;
  end;
end;

procedure TestStreamingUtf16NoTrailingNewline;
var
  Path: string;
  Doc: TEditorDoc;
  Expected: Integer;
begin
  Path := TempPath('big_utf16_notrail.txt');
  Expected := MakeBigUtf16(Path, True, False);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(Expected - 1) = cNoTrailMarker,
      'final line without trailing newline is complete (2-byte-unit sentinel path)');
  finally
    Doc.Free;
  end;
end;

procedure TestStreamingUtf16EncodingSwitchGuard;
var
  Path: string;
  Doc: TEditorDoc;
  LineCountBefore: Integer;
begin

  Path := TempPath('big_utf16le.txt'); // reuse LE fixture from TestStreamingUtf16
  Doc := OpenDoc(Path);
  try
    LineCountBefore := Doc.LineCount;
    // LE -> BE: same 2-byte width, index stays structurally valid.
    Assert.IsTrue(Doc.ApplyEncoding(tfeUtf16BE, True), 'LE -> BE re-decode is allowed');
    Assert.IsTrue(Doc.Encoding = tfeUtf16BE, 'encoding now reports BE');
    Assert.IsTrue(Doc.LineCount = LineCountBefore, 'line count unaffected by a same-width switch');
  finally
    Doc.Free;
  end;

  Doc := OpenDoc(Path); // fresh doc: back to native LE detection
  try
    LineCountBefore := Doc.LineCount;
    // UTF-16 -> ANSI: crosses the 2-byte/1-byte boundary, must be refused.
    Assert.IsTrue(not Doc.ApplyEncoding(tfeAnsi, True), 'UTF-16 -> ANSI re-decode is refused');
    Assert.IsTrue(Doc.Encoding = tfeUtf16LE, 'encoding unchanged after the refused switch');
    Assert.IsTrue(Doc.LineCount = LineCountBefore, 'line count unchanged after the refused switch');
  finally
    Doc.Free;
  end;
end;

procedure TestSmallFileUnaffected;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Path := TempPath('small_utf8.txt');
  MakeSmallUtf8(Path);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'small document is ready');
    Assert.IsTrue(not Doc.Streaming, 'small document uses the non-streaming path');
    Assert.IsTrue(not Doc.ReadOnly, 'small document stays editable');
    Assert.IsTrue(Doc.LineCount >= 100, 'small document line count');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'small document first line matches');
  finally
    Doc.Free;
  end;
end;

procedure TestStreamingIsReadOnly;
var
  Path: string;
  Doc: TEditorDoc;
  Before: Integer;
begin
  Path := TempPath('big_utf8.txt');
  Doc := OpenDoc(Path);
  try
    Before := Doc.LineCount;

    Doc.SetLine(0, 'MUTATED');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'SetLine does not modify a streaming doc');

    Doc.InsertLine(0, 'INSERTED');
    Assert.IsTrue(Doc.LineCount = Before, 'InsertLine does not change line count');

    Doc.DeleteLine(0);
    Assert.IsTrue(Doc.LineCount = Before, 'DeleteLine does not change line count');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'line 0 intact after mutation attempts');
    Assert.IsTrue(not Doc.Dirty, 'streaming doc never becomes dirty');
  finally
    Doc.Free;
  end;
end;

{ ---- main ------------------------------------------------------------------ }

{ TTestStreamingViewer }

procedure TTestStreamingViewer.SetupFixture;
begin
  GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestStreamingViewer');
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
  TDirectory.CreateDirectory(GTempDir);
end;

procedure TTestStreamingViewer.TearDownFixture;
begin
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
end;

procedure TTestStreamingViewer.TestSampleTrim;
begin
  TestStreamingViewer.TestSampleTrim;
end;

procedure TTestStreamingViewer.TestStreamingBasics;
begin
  TestStreamingViewer.TestStreamingBasics;
end;

procedure TTestStreamingViewer.TestCacheEviction;
begin
  TestStreamingViewer.TestCacheEviction;
end;

procedure TTestStreamingViewer.TestNoTrailingNewline;
begin
  TestStreamingViewer.TestNoTrailingNewline;
end;

procedure TTestStreamingViewer.TestSampleStraddle;
begin
  TestStreamingViewer.TestSampleStraddle;
end;

procedure TTestStreamingViewer.TestBinaryHex;
begin
  TestStreamingViewer.TestBinaryHex;
end;

procedure TTestStreamingViewer.TestBinaryF4ToText;
begin
  TestStreamingViewer.TestBinaryF4ToText;
end;

procedure TTestStreamingViewer.TestStreamingUtf16;
begin
  TestStreamingViewer.TestStreamingUtf16;
end;

procedure TTestStreamingViewer.TestStreamingUtf16NoTrailingNewline;
begin
  TestStreamingViewer.TestStreamingUtf16NoTrailingNewline;
end;

procedure TTestStreamingViewer.TestStreamingUtf16EncodingSwitchGuard;
begin
  TestStreamingViewer.TestStreamingUtf16EncodingSwitchGuard;
end;

procedure TTestStreamingViewer.TestSmallFileUnaffected;
begin
  TestStreamingViewer.TestSmallFileUnaffected;
end;

procedure TTestStreamingViewer.TestStreamingIsReadOnly;
begin
  TestStreamingViewer.TestStreamingIsReadOnly;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStreamingViewer);

end.
