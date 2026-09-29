unit TestSevenZipOpen;

{ Opening archives through uSevenZipApi, with every 7z.dll found (7-Zip,
  Far ArcLite):
  - an archive with encrypted headers reports 'Encrypted' until the right
    password is set, so the panel asks for it instead of showing the
    archive as unsupported; an archive with plain headers lists without a
    password and needs it only to extract;
  - a file whose extension no format claims opens by content (Ctrl+PgDn),
    and a file that is not an archive reports 'Not a supported archive'. }

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
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uSevenZipApi;

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
    Assert.Pass('SKIP: 7z.dll not found');
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
    Assert.Pass('SKIP: 7z.dll not found');
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
    Assert.Pass('SKIP: 7z.dll not found');
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

initialization
  TDUnitX.RegisterTestFixture(TTestSevenZipOpen);

end.
