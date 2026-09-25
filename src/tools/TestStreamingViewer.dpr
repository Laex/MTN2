program TestStreamingViewer;

{ Stage 24 regression: the line-indexed (streaming) Viewer path in uEditorDoc,
  plus the UTF-8 sample-trim in uTextEncoding that feeds its encoding sniff.

  Source is deliberately pure ASCII — every non-ASCII test string is built from
  explicit codepoints (#$xxxx). A pasted literal would depend on whether this
  .dpr carries a UTF-8 BOM, which is the exact class of defect that produced
  the mojibake this test guards against. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas',
  uZipVfs in '..\Core\uZipVfs.pas',
  uFindSession in '..\Core\uFindSession.pas',
  uFindVfs in '..\Core\uFindVfs.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\Core\uVfsRouter.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uEditorDoc in '..\Core\uEditorDoc.pas';

const
  // Cyrillic "Тест" — codepoints, not a literal (see header note).
  cCyr = #$0422#$0435#$0441#$0442;
  cNoTrailMarker = 'LAST-LINE-NO-TRAILING-NEWLINE';

var
  GTempDir: string;
  GFailures: Integer = 0;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Writeln('  [PASS] ', AWhat)
  else
  begin
    Writeln('  [FAIL] ', AWhat);
    Inc(GFailures);
  end;
end;

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
    Writeln('  [FAIL] timeout opening ', APath);
    Inc(GFailures);
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
  Writeln('TestSampleTrim (uTextEncoding.TrimUtf8SampleTail)');

  // 'a' + lead byte of a 2-byte sequence, continuation missing.
  Bytes := TBytes.Create(Ord('a'), $D0);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 1, 'dangling 2-byte lead is dropped');
  Check(DetectAndDecodeText(Trimmed, Text, Enc, IsBin) and (Enc = tfeUtf8),
    'trimmed sample still detects as UTF-8');

  // Untrimmed, the same sample is not valid UTF-8 and misdetects.
  Check(not (DetectAndDecodeText(Bytes, Text, Enc, IsBin) and (Enc = tfeUtf8)),
    'untrimmed dangling sample does NOT detect as UTF-8 (the original bug)');

  // Complete 2-byte sequence must survive untouched.
  Bytes := TBytes.Create(Ord('a'), $D0, $A2);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 3, 'complete 2-byte sequence is kept');

  // 3-byte sequence cut after 1 and after 2 bytes.
  Bytes := TBytes.Create(Ord('a'), $E2, $80);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 1, '3-byte sequence missing 1 continuation is dropped');

  Bytes := TBytes.Create(Ord('a'), $E2, $80, $A6);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 4, 'complete 3-byte sequence is kept');

  // Pure ASCII and empty input are untouched.
  Bytes := TBytes.Create(Ord('a'), Ord('b'), Ord('c'));
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 3, 'ASCII tail is untouched');

  SetLength(Bytes, 0);
  Trimmed := Copy(Bytes);
  TrimUtf8SampleTail(Trimmed);
  Check(Length(Trimmed) = 0, 'empty input is safe');
end;

procedure TestStreamingBasics;
var
  Path: string;
  Doc: TEditorDoc;
  Expected: Integer;
  Mid: Integer;
begin
  Writeln('TestStreamingBasics (big UTF-8, trailing newline)');
  Path := TempPath('big_utf8.txt');
  Expected := MakeBigUtf8(Path, True);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'document is ready');
    Check(Doc.Error = '', 'no error: ' + Doc.Error);
    Check(Doc.Streaming, 'opened in streaming mode');
    Check(Doc.ReadOnly, 'streaming document is read-only');
    Check(Doc.Encoding = tfeUtf8, 'encoding detected as UTF-8 (not CP1251/CP866)');
    Check(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(0) = LineText(0), 'first line matches exactly');
    Check(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'last line matches exactly');

    // Random access must not depend on read order.
    Mid := Expected div 2;
    Check(Doc.GetLine(Mid) = LineText(Mid), 'middle line (forward) matches');
    Check(Doc.GetLine(0) = LineText(0), 'first line still matches after seeking');
    Check(Doc.GetLine(Mid) = LineText(Mid), 'middle line re-read from cache matches');

    // Out-of-range access is defined, not a crash.
    Check(Doc.GetLine(-1) = '', 'negative index returns empty');
    Check(Doc.GetLine(Expected) = '', 'index past end returns empty');
    Check(Doc.GetLine(Expected + 1000) = '', 'far past end returns empty');
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
  Writeln('TestCacheEviction (more distinct lines than cStreamCacheCap)');
  Path := TempPath('big_utf8.txt'); // reuse fixture from TestStreamingBasics
  Doc := OpenDoc(Path);
  try
    Count := Doc.LineCount;
    Check(Count > cStreamCacheCap,
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
    Check(Ok, 'every line read while filling/evicting the cache is correct');
    Check(Doc.GetLine(0) = LineText(0), 'line 0 still correct after eviction');
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
  Writeln('TestNoTrailingNewline');
  Path := TempPath('big_notrail.txt');
  Expected := MakeBigUtf8(Path, False);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Check(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(Expected - 1) = cNoTrailMarker,
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
  Writeln('TestSampleStraddle (multi-byte char cut by the 64 KB sniff sample)');
  Path := TempPath('straddle.txt');
  MakeStraddleFile(Path);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Check(Doc.Encoding = tfeUtf8,
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
  Writeln('TestBinaryHex (large binary opens as hex, without crashing)');

  Path := TempPath('big_binary.bin');
  MakeBigBinary(Path);
  Doc := OpenDoc(Path);
  try
    Check(not Doc.Streaming, 'big binary is not streamed');
    Check(Doc.Ready, 'big binary is ready');
    Check(Doc.Binary, 'big binary is hex/binary');
    Check(Doc.Error = '', 'big binary has no error: ' + Doc.Error);
    Check(Pos('Hex', Doc.Status) > 0, 'status mentions Hex: ' + Doc.Status);
  finally
    Doc.Free;
  end;
end;

procedure TestBinaryF4ToText;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Writeln('TestBinaryF4ToText (F4 in Hex viewer force-decodes as text)');

  Path := TempPath('tiny_binary.bin');
  MakeTinyBinary(Path);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'tiny binary is ready');
    Check(Doc.Binary, 'tiny binary opens as hex/binary');
    Check(Doc.ApplyEncoding(Doc.Encoding, True), 'F4 re-decode succeeds');
    Check(not Doc.Binary, 'F4 leaves binary/hex lock');
    Check(Doc.LineCount >= 1, 'F4 text view has at least one line');
    Check(Pos('M', Doc.GetLine(0)) > 0, 'decoded text keeps printable prefix');
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
  Writeln('TestStreamingUtf16 (LE and BE, both bigger than cEditorMaxBytes)');

  // ---- LE: full coverage, including cache eviction (mirrors TestStreamingBasics
  // + TestCacheEviction for the UTF-8 fixture). ----
  Path := TempPath('big_utf16le.txt');
  Expected := MakeBigUtf16(Path, True, True);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'LE: document is ready');
    Check(Doc.Error = '', 'LE: no error: ' + Doc.Error);
    Check(Doc.Streaming, 'LE: opened in streaming mode');
    Check(Doc.ReadOnly, 'LE: streaming document is read-only');
    Check(Doc.Encoding = tfeUtf16LE, 'LE: encoding detected as UTF-16 LE');
    Check(Doc.LineCount = Expected,
      Format('LE: line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(0) = LineText(0),
      'LE: first line matches exactly (no stray BOM/CR/LF folded in)');
    Check(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'LE: last line matches exactly');
    Mid := Expected div 2;
    Check(Doc.GetLine(Mid) = LineText(Mid), 'LE: middle line matches');

    Count := Doc.LineCount;
    Check(Count > cStreamCacheCap,
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
    Check(Ok, 'LE: every line read while filling/evicting the cache is correct');
    Check(Doc.GetLine(0) = LineText(0), 'LE: line 0 still correct after eviction');
  finally
    Doc.Free;
  end;

  // ---- BE: same shape, endianness-specific spot checks. ----
  Path := TempPath('big_utf16be.txt');
  Expected := MakeBigUtf16(Path, False, True);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'BE: document is ready');
    Check(Doc.Streaming, 'BE: opened in streaming mode');
    Check(Doc.ReadOnly, 'BE: streaming document is read-only');
    Check(Doc.Encoding = tfeUtf16BE, 'BE: encoding detected as UTF-16 BE');
    Check(Doc.LineCount = Expected,
      Format('BE: line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(0) = LineText(0), 'BE: first line matches exactly');
    Check(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'BE: last line matches exactly');
    Mid := Expected div 2;
    Check(Doc.GetLine(Mid) = LineText(Mid), 'BE: middle line matches');
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
  Writeln('TestStreamingUtf16NoTrailingNewline');
  Path := TempPath('big_utf16_notrail.txt');
  Expected := MakeBigUtf16(Path, True, False);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready and Doc.Streaming, 'streaming document is ready');
    Check(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(Expected - 1) = cNoTrailMarker,
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
  Writeln('TestStreamingUtf16EncodingSwitchGuard (width-preserving switch allowed, width change refused)');

  Path := TempPath('big_utf16le.txt'); // reuse LE fixture from TestStreamingUtf16
  Doc := OpenDoc(Path);
  try
    LineCountBefore := Doc.LineCount;
    // LE -> BE: same 2-byte width, index stays structurally valid.
    Check(Doc.ApplyEncoding(tfeUtf16BE, True), 'LE -> BE re-decode is allowed');
    Check(Doc.Encoding = tfeUtf16BE, 'encoding now reports BE');
    Check(Doc.LineCount = LineCountBefore, 'line count unaffected by a same-width switch');
  finally
    Doc.Free;
  end;

  Doc := OpenDoc(Path); // fresh doc: back to native LE detection
  try
    LineCountBefore := Doc.LineCount;
    // UTF-16 -> ANSI: crosses the 2-byte/1-byte boundary, must be refused.
    Check(not Doc.ApplyEncoding(tfeAnsi, True), 'UTF-16 -> ANSI re-decode is refused');
    Check(Doc.Encoding = tfeUtf16LE, 'encoding unchanged after the refused switch');
    Check(Doc.LineCount = LineCountBefore, 'line count unchanged after the refused switch');
  finally
    Doc.Free;
  end;
end;

procedure TestSmallFileUnaffected;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Writeln('TestSmallFileUnaffected (under the limit = old whole-buffer path)');
  Path := TempPath('small_utf8.txt');
  MakeSmallUtf8(Path);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'small document is ready');
    Check(not Doc.Streaming, 'small document uses the non-streaming path');
    Check(not Doc.ReadOnly, 'small document stays editable');
    Check(Doc.LineCount >= 100, 'small document line count');
    Check(Doc.GetLine(0) = LineText(0), 'small document first line matches');
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
  Writeln('TestStreamingIsReadOnly (mutators are no-ops, not crashes)');
  Path := TempPath('big_utf8.txt');
  Doc := OpenDoc(Path);
  try
    Before := Doc.LineCount;

    Doc.SetLine(0, 'MUTATED');
    Check(Doc.GetLine(0) = LineText(0), 'SetLine does not modify a streaming doc');

    Doc.InsertLine(0, 'INSERTED');
    Check(Doc.LineCount = Before, 'InsertLine does not change line count');

    Doc.DeleteLine(0);
    Check(Doc.LineCount = Before, 'DeleteLine does not change line count');
    Check(Doc.GetLine(0) = LineText(0), 'line 0 intact after mutation attempts');
    Check(not Doc.Dirty, 'streaming doc never becomes dirty');
  finally
    Doc.Free;
  end;
end;

{ ---- main ------------------------------------------------------------------ }

begin
  try
    GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestStreamingViewer');
    if TDirectory.Exists(GTempDir) then
      TDirectory.Delete(GTempDir, True);
    TDirectory.CreateDirectory(GTempDir);
    Writeln('=== TestStreamingViewer (Stage 24) ===');
    Writeln('temp: ', GTempDir);
    Writeln;

    TestSampleTrim;
    TestStreamingBasics;
    TestCacheEviction;
    TestNoTrailingNewline;
    TestSampleStraddle;
    TestBinaryHex;
    TestBinaryF4ToText;
    TestStreamingUtf16;
    TestStreamingUtf16NoTrailingNewline;
    TestStreamingUtf16EncodingSwitchGuard;
    TestSmallFileUnaffected;
    TestStreamingIsReadOnly;

    Writeln;
    try
      if TDirectory.Exists(GTempDir) then
        TDirectory.Delete(GTempDir, True);
    except
      // Cleanup is best-effort; a locked temp file must not fail the run.
    end;

    if GFailures = 0 then
      Writeln('All StreamingViewer tests PASSED')
    else
    begin
      Writeln(Format('FAILED: %d check(s)', [GFailures]));
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
