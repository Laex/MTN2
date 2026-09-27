unit TestChecksums;

{ uChecksums: known digests, streamed files larger than one block, cancel,
  checksum-line formats, file collection, verification with OK / FAILED /
  MISSING, save file name. Works on throw-away files in %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestChecksums = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestKnownDigests;
    [Test] procedure TestFiles;
    [Test] procedure TestLines;
    [Test] procedure TestCollectAndVerify;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uChecksums;

procedure TestKnownDigests;
var
  Abc: TBytes;
begin
  Abc := TEncoding.ASCII.GetBytes('abc');
  Assert.IsTrue(HashBytesHex(Abc, caMD5) = '900150983cd24fb0d6963f7d28e17f72', 'MD5');
  Assert.IsTrue(HashBytesHex(Abc, caSHA1) = 'a9993e364706816aba3e25717850c26c9cd0d89d', 'SHA-1');
  Assert.IsTrue(HashBytesHex(Abc, caSHA256) =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'SHA-256');
  Assert.IsTrue(HashBytesHex(Abc, caSHA512) =
    'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a' +
    '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f', 'SHA-512');
  Assert.IsTrue(ChecksumHexLength(caSHA256) = 64, 'SHA-256 hex length');
end;

procedure TestFiles(const ADir: string);
var
  Empty, Big: string;
  Data: TBytes;
  I, Calls: Integer;
begin
  Empty := TPath.Combine(ADir, 'empty.bin');
  TFile.WriteAllBytes(Empty, nil);
  Assert.IsTrue(HashFileHex(Empty, caSHA256) =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'empty file SHA-256');

  // 3.5 blocks: the streamed digest must match the in-memory one.
  SetLength(Data, 3 * 1024 * 1024 + 512 * 1024);
  for I := 0 to High(Data) do
    Data[I] := Byte(I * 31 + I shr 8);
  Big := TPath.Combine(ADir, 'big.bin');
  TFile.WriteAllBytes(Big, Data);
  Assert.IsTrue(HashFileHex(Big, caSHA1) = HashBytesHex(Data, caSHA1), 'multi-block file = in-memory');
  Assert.IsTrue(HashFileHex(Big, caMD5) = HashBytesHex(Data, caMD5), 'multi-block MD5');

  Calls := 0;
  Assert.IsTrue(HashFileHex(Big, caSHA256,
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls >= 2;
    end) = '', 'cancel stops between blocks and returns ''''');
end;

procedure TestLines;
var
  H, N: string;
  A: TChecksumAlgo;
begin
  Assert.IsTrue(FormatChecksumLine('abcd', 'dir\a b.txt') = 'abcd *dir\a b.txt', 'format: "hash *name"');
  Assert.IsTrue(ParseChecksumLine('ABCD *dir\a b.txt', H, N) and (H = 'abcd') and (N = 'dir\a b.txt'),
    'parse binary marker, hash lower-cased');
  Assert.IsTrue(ParseChecksumLine('abcd  a b.txt', H, N) and (N = 'a b.txt'), 'parse text mode (two spaces)');
  Assert.IsTrue(ParseChecksumLine('SHA256 (my file.txt) = ABCD', H, N) and (H = 'abcd') and
    (N = 'my file.txt'), 'parse BSD style');
  Assert.IsTrue(not ParseChecksumLine('; comment', H, N), 'comment');
  Assert.IsTrue(not ParseChecksumLine('', H, N), 'blank');
  Assert.IsTrue(not ParseChecksumLine('not-a-hash name', H, N), 'non-hex first word');
  Assert.IsTrue(ChecksumAlgoFromExt('x.SHA256', A) and (A = caSHA256), 'extension -> algorithm');
  Assert.IsTrue(not ChecksumAlgoFromExt('x.txt', A), 'unknown extension');
end;

procedure TestCollectAndVerify(const ADir: string);
var
  Base, Sub, SumFile: string;
  Files: TArray<TChecksumFile>;
  Items: TArray<TChecksumVerifyItem>;
  Lines: TStringList;
  F: TChecksumFile;
  Ok: Boolean;
begin
  Base := TPath.Combine(ADir, 'tree');
  Sub := TPath.Combine(Base, 'sub');
  ForceDirectories(Sub);
  TFile.WriteAllText(TPath.Combine(Base, 'b.txt'), 'bee');
  TFile.WriteAllText(TPath.Combine(Base, 'A.txt'), 'ay');
  TFile.WriteAllText(TPath.Combine(Sub, 'c.txt'), 'see');

  Files := CollectChecksumFiles([TPath.Combine(Base, 'b.txt'), Sub, TPath.Combine(Base, 'A.txt')], Base);
  Assert.IsTrue(Length(Files) = 3, 'file + folder (recursive) + file');
  Assert.IsTrue((Files[0].RelName = 'A.txt') and (Files[1].RelName = 'b.txt') and
    (Files[2].RelName = 'sub\c.txt'), 'relative names, sorted case-insensitively');
  Assert.IsTrue(ChecksumSaveFileName(Files, Base, caSHA256) = TPath.Combine(Base, 'checksums.sha256'),
    'several files -> checksums.sha256 in the folder');
  Assert.IsTrue(ChecksumSaveFileName([Files[0]], Base, caMD5) = Files[0].Path + '.md5',
    'one file -> <file>.md5');

  Lines := TStringList.Create;
  try
    for F in Files do
      Lines.Add(FormatChecksumLine(HashFileHex(F.Path, caSHA256), F.RelName));
    Lines.Add(FormatChecksumLine(StringOfChar('0', 64), 'gone.txt'));
    SumFile := TPath.Combine(Base, 'checksums.sha256');
    Lines.SaveToFile(SumFile, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
  TFile.WriteAllText(TPath.Combine(Base, 'b.txt'), 'changed');

  Ok := VerifyChecksumFile(SumFile, caSHA256, Items);
  Assert.IsTrue(Ok and (Length(Items) = 4), 'every line checked');
  Assert.IsTrue((Items[0].Status = cvsOk) and (Items[2].Status = cvsOk), 'unchanged files OK (incl. subfolder)');
  Assert.IsTrue(Items[1].Status = cvsFailed, 'changed file FAILED');
  Assert.IsTrue(Items[3].Status = cvsMissing, 'absent file MISSING');
  Assert.IsTrue(ChecksumVerifyStatusText(cvsMissing) = 'MISSING', 'status text');
  Assert.IsTrue(not VerifyChecksumFile(SumFile, caSHA256, Items,
    function: Boolean begin Result := True; end), 'cancel -> False');
end;

var
  Dir: string;

{ TTestChecksums }

procedure TTestChecksums.SetupFixture;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-checksums-test');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  ForceDirectories(Dir);
end;

procedure TTestChecksums.TearDownFixture;
begin
  TDirectory.Delete(Dir, True);
end;

procedure TTestChecksums.TestKnownDigests;
begin
  TestChecksums.TestKnownDigests;
end;

procedure TTestChecksums.TestFiles;
begin
  TestChecksums.TestFiles(Dir);
end;

procedure TTestChecksums.TestLines;
begin
  TestChecksums.TestLines;
end;

procedure TTestChecksums.TestCollectAndVerify;
begin
  TestChecksums.TestCollectAndVerify(Dir);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestChecksums);

end.
