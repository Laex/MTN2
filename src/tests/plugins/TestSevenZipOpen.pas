unit TestSevenZipOpen;

{ Opening archives through uSevenZipApi, with every archive engine found (7z.dll
  of 7-Zip or Far ArcLite; a 7-Zip program on POSIX):
  - an archive with encrypted headers reports 'Encrypted' until the right
    password is set, so the panel asks for it instead of showing the
    archive as unsupported; an archive with plain headers lists without a
    password and needs it only to extract;
  - a file whose extension no format claims opens by content (Ctrl+PgDn),
    and a file that is not an archive reports 'Not a supported archive';
  - the compression level set for an archive decides how small a file packs;
  - packing with a password encrypts the new files, with header encryption
    also their names, and adding to or deleting from such an archive keeps it
    encrypted. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipOpen = class
  public
    [Test] procedure TestEncryptedHeaders;
    [Test] procedure TestEncryptedData;
    [Test] procedure TestUnknownExtensionByContent;
    [Test] procedure TestMisnamedArchiveOpensByContent;
    [Test] procedure TestFolderNameEndingInBang;
    [Test] procedure TestParentSegmentOnlyRejectsRealTraversal;
    [Test] procedure TestPackWithPassword;
    [Test] procedure TestPackWithEncryptedNames;
    [Test] procedure TestPackCompressionLevel;
    [Test] procedure TestExtractFolderInOnePass;
    [Test] procedure TestArchiveIntegrity;
    [Test] procedure TestSplitArchiveVolumes;
    [Test] procedure TestEncryptedArchiveIntegrity;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  uPlatformPaths, uPlatformProcess, uSevenZipApi, uSevenZipVfs;

const
  // 7z a -p1 -mhe=on hdr.7z inner.txt ("secret-payload")
  cHeaderEncrypted =
    '377ABCAF271C00041724E74790000000000000002E000000000000002C86D4A8' +
    '8541B675D2D71FFB56DCEEA1083FAC1ED3F74744B835C933BD6609F0AD9EFCAB' +
    '5444DFBA30F249559B4A0519E9113EFA69C1D1D10FDF819CC4AA06525C994C0E' +
    'C03671D8E6C168DEB2F457FAD3B2E8BA70EF7FE7AD07B0F88EC255D3A1559175' +
    '0BD4F5A7BD541744DF320FC251B9AAAE91938317CE23FA4AB5B21B9B76180840' +
    '3DFAA7B2D9FB986956A4B86CECE6C22417062001097000070B0100012406F107' +
    '0112530F4B96C844D08D9BD9C6F5EE1241CF0E3F0C6A0A014160F14F0000';
  // 7z a -p1 data.7z inner.txt ("secret-payload"), headers not encrypted
  cDataEncrypted =
    '377ABCAF271C0004EBC48B4F20000000000000006A00000000000000F3E2773A' +
    '285726274B837512EA609040688F04AE30B7441F1B0364E37341C99028415FCC' +
    '0104060001092000070B0100022406F1070112530FB0916C5A36DE0702363158' +
    'B92AAB84C92121010001000C130F00080A019A90312400000501190100111500' +
    '69006E006E00650072002E007400780074000000140A01009C6F5918E44FDD01' +
    '15060100200800000000';
  // gzip of inner.txt ("gzip-payload"): a format past 7z and RAR
  cGzip = '1F8B08080000000002FF696E6E65722E747874004BAFCA2CD02D48ACCCC94F4C01001C67F05B0C000000';

function Engines: TArray<string>;
const
  Candidates: array[0..2] of string = (
    'C:\Program Files\7-Zip\7z.dll',
    'C:\Program Files\Far Manager\Plugins\ArcLite\7z.dll',
    'C:\Program Files (x86)\7-Zip\7z.dll'
  );
var
  S: string;
begin
  Result := [];
  if PlatformPosixPaths then
  begin
    S := PlatformSevenZipEngine('');
    if S <> '' then
      Result := [S];
    Exit;
  end;
  S := GetEnvironmentVariable('MTN2_7Z_DLL');
  if (S <> '') and TFile.Exists(S) then
    Result := Result + [S];
  for S in Candidates do
    if TFile.Exists(S) then
      Result := Result + [S];
end;

function WriteFixture(const AName, AHex: string): string;
var
  Bytes: TBytes;
  I: Integer;
begin
  SetLength(Bytes, Length(AHex) div 2);
  for I := 0 to High(Bytes) do
    Bytes[I] := StrToInt('$' + Copy(AHex, I * 2 + 1, 2));
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'mtn2-7z-encrypted'), AName);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllBytes(Result, Bytes);
end;

function Lists(const AArchive: string; out AError: string): Boolean;
var
  Items: TArray<T7zItem>;
  I: Integer;
begin
  Result := SevenZipListArchive(AArchive, Items, AError);
  if not Result then
    Exit;
  for I := 0 to High(Items) do
    if SameText(Items[I].Path, 'inner.txt') then
      Exit(True);
  AError := 'inner.txt not listed';
  Result := False;
end;

procedure TTestSevenZipOpen.TestEncryptedHeaders;
var
  Dll, Arc, Err, Tag: string;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Arc := WriteFixture('hdr.7z', cHeaderEncrypted);
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipClearPassword(Arc);
      Assert.IsFalse(Lists(Arc, Err), Tag + 'no password: not listed');
      Assert.AreEqual('Encrypted', Err, Tag + 'no password: reported as encrypted');
      SevenZipSetPassword(Arc, '2');
      Assert.IsFalse(Lists(Arc, Err), Tag + 'wrong password: not listed');
      Assert.AreEqual('Encrypted', Err, Tag + 'wrong password: reported as encrypted');
      SevenZipSetPassword(Arc, '1');
      Assert.IsTrue(Lists(Arc, Err), Tag + 'right password lists: ' + Err);
    finally
      SevenZipClearPassword(Arc);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestEncryptedData;
var
  Dll, Arc, Err, Tag: string;
  Data: TBytes;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Arc := WriteFixture('data.7z', cDataEncrypted);
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipClearPassword(Arc);
      Assert.IsTrue(Lists(Arc, Err), Tag + 'plain headers list without a password: ' + Err);
      Assert.IsFalse(SevenZipExtractFile(Arc, 'inner.txt', 1 shl 20, Data, Err),
        Tag + 'no password: not extracted');
      Assert.AreEqual('Encrypted', Err, Tag + 'no password: extraction reports encrypted');
      // The panel checks a password by reading the start of a file: a wrong
      // one fails as encrypted, the right one only runs out of room.
      SevenZipSetPassword(Arc, '2');
      Assert.IsFalse(SevenZipExtractFile(Arc, 'inner.txt', 4, Data, Err),
        Tag + 'wrong password: not extracted');
      Assert.AreEqual('Encrypted', Err, Tag + 'wrong password: reported as encrypted');
      SevenZipSetPassword(Arc, '1');
      Assert.IsFalse(SevenZipExtractFile(Arc, 'inner.txt', 4, Data, Err),
        Tag + 'right password, 4 bytes: does not fit');
      Assert.AreEqual('Too large', Err, Tag + 'right password: only too large');
      Assert.IsTrue(SevenZipExtractFile(Arc, 'inner.txt', 1 shl 20, Data, Err),
        Tag + 'right password extracts: ' + Err);
      Assert.IsTrue(TEncoding.ASCII.GetString(Data).StartsWith('secret-payload'),
        Tag + 'payload');
    finally
      SevenZipClearPassword(Arc);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestUnknownExtensionByContent;
var
  Dll, Arc, Plain, Err, Tag: string;
  Items: TArray<T7zItem>;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Arc := WriteFixture('backup.dat', cGzip);
  Plain := TPath.Combine(ExtractFilePath(Arc), 'notes.dat');
  TFile.WriteAllText(Plain, 'just some text, not an archive');
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      Assert.IsTrue(SevenZipListArchive(Arc, Items, Err) and (Length(Items) = 1),
        Tag + 'gzip named .dat lists: ' + Err);
      Assert.IsFalse(Lists(Plain, Err), Tag + 'text is not an archive');
      Assert.AreEqual('Not a supported archive', Err, Tag + 'text: reported as unsupported');
    finally
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestMisnamedArchiveOpensByContent;
var
  Dll, Arc, Err, Tag: string;
  Items: TArray<T7zItem>;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  // A gzip saved as .zip: the ZIP handler refuses it, another format opens it.
  Arc := WriteFixture('misnamed.zip', cGzip);
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      Assert.IsTrue(SevenZipListArchive(Arc, Items, Err) and (Length(Items) = 1),
        Tag + 'gzip named .zip lists: ' + Err);
    finally
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestFolderNameEndingInBang;
var
  Folder, Arc, Uri, ArcPath, Inner: string;
begin
  // "Games!/a.gz" puts a '!/' inside the path; only the one after the
  // existing archive file is the archive marker.
  Folder := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'mtn2-7z-bang'), 'Games!');
  TDirectory.CreateDirectory(Folder);
  Arc := TPath.Combine(Folder, 'a.gz');
  TFile.WriteAllBytes(Arc, [1, 2, 3]);
  Uri := '7z://' + StringReplace(Arc, '\', '/', [rfReplaceAll]);
  if not PlatformPosixPaths then
    Uri := '7z:///' + StringReplace(Arc, '\', '/', [rfReplaceAll]);
  Assert.IsTrue(ParseSevenZipUri(Uri + '!/', ArcPath, Inner), 'root parses');
  Assert.AreEqual(Arc, ArcPath, 'root: archive is the file, not the folder prefix');
  Assert.AreEqual('', Inner, 'root: no inner path');
  Assert.IsTrue(ParseSevenZipUri(Uri + '!/dir/x.txt', ArcPath, Inner), 'inner parses');
  Assert.AreEqual(Arc, ArcPath, 'inner: archive is the file');
  Assert.AreEqual('dir/x.txt', Inner, 'inner: entry path');
end;

procedure TTestSevenZipOpen.TestParentSegmentOnlyRejectsRealTraversal;
begin
  Assert.IsTrue(SevenZipHasParentSegment('..'), 'bare parent');
  Assert.IsTrue(SevenZipHasParentSegment('a/../b'), 'embedded parent');
  Assert.IsTrue(SevenZipHasParentSegment('a/..'), 'trailing parent');
  Assert.IsTrue(SevenZipHasParentSegment('a\..\b'), 'backslash parent');
  Assert.IsFalse(SevenZipHasParentSegment('v1..2.txt'), 'dots inside a name');
  Assert.IsFalse(SevenZipHasParentSegment('dir/..hidden'), 'leading dots in a name');
  Assert.IsFalse(SevenZipHasParentSegment('dir/file.'), 'trailing dot');
end;

function NewPackSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'mtn2-7z-pack'), AName);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, AText);
end;

function NewPackArchive(const AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'mtn2-7z-pack'), AName);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

function ReadsAs(const AArchive, AInner, AText: string): Boolean;
var
  Data: TBytes;
  Err: string;
begin
  Result := SevenZipExtractFile(AArchive, AInner, 1 shl 20, Data, Err) and
    (TEncoding.UTF8.GetString(Data) = AText);
end;

procedure TTestSevenZipOpen.TestPackWithPassword;
var
  Dll, Arc, Src, Err, Tag: string;
  Items: TArray<T7zItem>;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Src := NewPackSource('inner.txt', 'pack-payload');
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Arc := NewPackArchive('data.7z');
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipSetPassword(Arc, 'pw');
      SevenZipSetHeaderEncryption(Arc, False);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, Src, 'inner.txt', True, Err),
        Tag + 'pack with password: ' + Err);
      SevenZipClearPassword(Arc);
      Assert.IsTrue(SevenZipListArchive(Arc, Items, Err) and (Length(Items) = 1),
        Tag + 'names stay readable without header encryption: ' + Err);
      Assert.IsTrue(Items[0].Encrypted, Tag + 'the file is flagged as encrypted');
      Assert.IsFalse(ReadsAs(Arc, 'inner.txt', 'pack-payload'),
        Tag + 'no password: content unreadable');
      SevenZipSetPassword(Arc, 'pw');
      Assert.IsTrue(ReadsAs(Arc, 'inner.txt', 'pack-payload'),
        Tag + 'password: content readable');
    finally
      SevenZipClearPassword(Arc);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestPackWithEncryptedNames;
var
  Dll, Arc, Src, Extra, Err, Tag: string;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Src := NewPackSource('inner.txt', 'pack-payload');
  Extra := NewPackSource('second.txt', 'second-payload');
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Arc := NewPackArchive('hidden.7z');
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipSetPassword(Arc, 'pw');
      SevenZipSetHeaderEncryption(Arc, True);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, Src, 'inner.txt', True, Err),
        Tag + 'pack with encrypted names: ' + Err);
      // Later writes learn that the names are encrypted from the archive itself.
      SevenZipSetHeaderEncryption(Arc, False);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, Extra, 'second.txt', True, Err),
        Tag + 'add to the encrypted archive: ' + Err);
      SevenZipClearPassword(Arc);
      Assert.IsFalse(Lists(Arc, Err), Tag + 'no password: names hidden');
      Assert.AreEqual('Encrypted', Err, Tag + 'no password: reported as encrypted');
      SevenZipSetPassword(Arc, 'pw');
      Assert.IsTrue(Lists(Arc, Err), Tag + 'password lists the first file: ' + Err);
      Assert.IsTrue(ReadsAs(Arc, 'second.txt', 'second-payload'),
        Tag + 'the added file reads back');
      Assert.IsTrue(SevenZipDeleteInner(Arc, 'second.txt', Err),
        Tag + 'delete from the encrypted archive: ' + Err);
      SevenZipClearPassword(Arc);
      Assert.IsFalse(Lists(Arc, Err), Tag + 'after delete: names still hidden');
      SevenZipSetPassword(Arc, 'pw');
      Assert.IsTrue(Lists(Arc, Err), Tag + 'after delete: the first file remains: ' + Err);
      Assert.IsFalse(ReadsAs(Arc, 'second.txt', 'second-payload'),
        Tag + 'the deleted file is gone');
    finally
      SevenZipClearPassword(Arc);
      SevenZipSetHeaderEncryption(Arc, False);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestPackCompressionLevel;
var
  Dll, Arc, Src, Err, Tag: string;
  StoredSize, UltraSize: Int64;
  I: Integer;
  Text: TStringBuilder;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Text := TStringBuilder.Create;
  try
    for I := 1 to 4000 do
      Text.Append('compressible line ').Append(I mod 7).AppendLine;
    Src := NewPackSource('big.txt', Text.ToString);
  finally
    Text.Free;
  end;
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    Arc := NewPackArchive('store.7z');
    try
      SevenZipSetCompressionLevel(Arc, 0);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, Src, 'big.txt', True, Err),
        Tag + 'pack stored: ' + Err);
      StoredSize := TFile.GetSize(Arc);
      SevenZipSetCompressionLevel(Arc, -1);
      Arc := NewPackArchive('ultra.7z');
      SevenZipSetCompressionLevel(Arc, 9);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, Src, 'big.txt', True, Err),
        Tag + 'pack ultra: ' + Err);
      UltraSize := TFile.GetSize(Arc);
      Assert.IsTrue(UltraSize * 4 < StoredSize,
        Tag + 'ultra packs far smaller than store: ' + IntToStr(UltraSize) + ' vs ' +
        IntToStr(StoredSize));
      Assert.IsTrue(ReadsAs(Arc, 'big.txt', TFile.ReadAllText(Src)),
        Tag + 'the ultra archive reads back');
    finally
      SevenZipSetCompressionLevel(Arc, -1);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestExtractFolderInOnePass;
var
  Dll, Arc, SrcDir, Dest, Err, Tag: string;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  SrcDir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-tree-src');
  if TDirectory.Exists(SrcDir) then
    TDirectory.Delete(SrcDir, True);
  TDirectory.CreateDirectory(TPath.Combine(SrcDir, 'sub' + PathDelim + 'deep'));
  TFile.WriteAllText(TPath.Combine(SrcDir, 'a.txt'), 'alpha');
  TFile.WriteAllText(TPath.Combine(SrcDir, 'sub' + PathDelim + 'b.txt'), 'beta');
  TFile.WriteAllText(TPath.Combine(SrcDir, 'sub' + PathDelim + 'deep' + PathDelim + 'c.txt'), 'gamma');
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Arc := NewPackArchive('tree.7z');
    Dest := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-tree-dst');
    if TDirectory.Exists(Dest) then
      TDirectory.Delete(Dest, True);
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      Assert.IsTrue(SevenZipAddLocalPath(Arc, SrcDir, 'pack', True, Err),
        Tag + 'pack the folder: ' + Err);
      Assert.IsTrue(SevenZipExtractTree(Arc, 'pack', Dest, False, Err),
        Tag + 'unpack the folder: ' + Err);
      Assert.AreEqual('alpha', TFile.ReadAllText(TPath.Combine(Dest, 'a.txt')), Tag + 'top file');
      Assert.AreEqual('beta', TFile.ReadAllText(TPath.Combine(Dest, 'sub' + PathDelim + 'b.txt')), Tag + 'nested file');
      Assert.AreEqual('gamma', TFile.ReadAllText(TPath.Combine(Dest, 'sub' + PathDelim + 'deep' + PathDelim + 'c.txt')), Tag + 'deep file');
      Assert.IsFalse(SevenZipExtractTree(Arc, 'pack', Dest, False, Err), Tag + 'existing files');
      Assert.AreEqual('Already exists', Err, Tag + 'existing files error');
      TFile.WriteAllText(TPath.Combine(Dest, 'a.txt'), 'changed');
      Assert.IsTrue(SevenZipExtractTree(Arc, 'pack', Dest, True, Err),
        Tag + 'overwrite: ' + Err);
      Assert.AreEqual('alpha', TFile.ReadAllText(TPath.Combine(Dest, 'a.txt')), Tag + 'overwritten');
      Assert.IsFalse(SevenZipExtractTree(Arc, 'missing', Dest, True, Err), Tag + 'missing folder');
      Assert.AreEqual('Not found', Err, Tag + 'missing folder error');
    finally
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestArchiveIntegrity;
var
  Dll, Arc, SrcDir, Err, Tag, Joined: string;
  Bytes: TBytes;
  R: T7zTestResult;
  E: string;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  SrcDir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-test-src');
  if TDirectory.Exists(SrcDir) then
    TDirectory.Delete(SrcDir, True);
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'first.txt'), StringOfChar('a', 400));
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Arc := NewPackArchive('intact.7z');
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipSetCompressionLevel(Arc, 0);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, TPath.Combine(SrcDir, 'first.txt'), 'first.txt',
        True, Err), Tag + 'pack: ' + Err);
      Assert.IsTrue(SevenZipTestArchive(Arc, nil, R, Err), Tag + 'intact archive: ' + Err);
      Assert.AreEqual(1, R.Checked, Tag + 'checked files');
      Assert.AreEqual(0, R.Failed, Tag + 'intact archive has no failures');
      Bytes := TFile.ReadAllBytes(Arc);
      Bytes[40] := Bytes[40] xor $FF;
      TFile.WriteAllBytes(Arc, Bytes);
      Assert.IsTrue(SevenZipTestArchive(Arc, nil, R, Err), Tag + 'damaged archive is testable: ' + Err);
      Assert.AreEqual(1, R.Failed, Tag + 'damaged file counted');
      Joined := '';
      for E in R.Errors do
        Joined := Joined + E;
      Assert.IsTrue(Joined.Contains('first.txt'), Tag + 'damaged file named: ' + Joined);
      R := Default(T7zTestResult);
      Assert.IsTrue(SevenZipTestArchive(Arc, function: Boolean begin Result := True; end,
        R, Err), Tag + 'cancelled run');
    finally
      SevenZipSetCompressionLevel(Arc, -1);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestSplitArchiveVolumes;
var
  Dll, Arc, Vol, SrcDir, Err, Tag, Names: string;
  Bytes, Part: TBytes;
  Items: TArray<T7zItem>;
  I, N: Integer;
  R: T7zTestResult;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  SrcDir := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-vol-src');
  if TDirectory.Exists(SrcDir) then
    TDirectory.Delete(SrcDir, True);
  TDirectory.CreateDirectory(SrcDir);
  TFile.WriteAllText(TPath.Combine(SrcDir, 'inner.txt'), StringOfChar('v', 3000));
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Arc := NewPackArchive('vol.7z');
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipSetCompressionLevel(Arc, 0);
      Assert.IsTrue(SevenZipAddLocalPath(Arc, TPath.Combine(SrcDir, 'inner.txt'), 'inner.txt',
        True, Err), Tag + 'pack: ' + Err);
      Bytes := TFile.ReadAllBytes(Arc);
      TFile.Delete(Arc);
      // Three volumes cut where it suits: the archive is read across the cuts.
      N := (Length(Bytes) + 2) div 3;
      for I := 0 to 2 do
      begin
        Part := Copy(Bytes, I * N, Min(N, Length(Bytes) - I * N));
        Vol := Arc + '.00' + IntToStr(I + 1);
        TFile.WriteAllBytes(Vol, Part);
      end;
      Vol := Arc + '.001';
      Assert.IsTrue(SevenZipListArchive(Vol, Items, Err), Tag + 'list the volumes: ' + Err);
      Names := '';
      for I := 0 to High(Items) do
        Names := Names + Items[I].Path + ';';
      Assert.IsTrue(Names.Contains('inner.txt') or Names.Contains('vol.7z'),
        Tag + 'volumes list the archive or its content: ' + Names);
      Assert.IsTrue(SevenZipTestArchive(Vol, nil, R, Err), Tag + 'test the volumes: ' + Err);
      Assert.AreEqual(0, R.Failed, Tag + 'volumes are intact');
    finally
      SevenZipSetCompressionLevel(Arc, -1);
      SevenZipUnloadEngine;
    end;
  end;
end;

procedure TTestSevenZipOpen.TestEncryptedArchiveIntegrity;
var
  Dll, Arc, Err, Tag: string;
  R: T7zTestResult;
begin
  if Length(Engines) = 0 then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Arc := WriteFixture('data.7z', cDataEncrypted);
  for Dll in Engines do
  begin
    Tag := Dll + ': ';
    Assert.IsTrue(SevenZipLoadEngine(Dll), Tag + 'load');
    try
      SevenZipClearPassword(Arc);
      Assert.IsFalse(SevenZipTestArchive(Arc, nil, R, Err), Tag + 'no password');
      Assert.AreEqual('Encrypted', Err, Tag + 'no password reported as encrypted');
      SevenZipSetPassword(Arc, '1');
      Assert.IsTrue(SevenZipTestArchive(Arc, nil, R, Err), Tag + 'right password: ' + Err);
      Assert.AreEqual(0, R.Failed, Tag + 'right password has no failures');
    finally
      SevenZipClearPassword(Arc);
      SevenZipUnloadEngine;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSevenZipOpen);

end.
