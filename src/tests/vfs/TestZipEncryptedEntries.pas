unit TestZipEncryptedEntries;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestZipEncryptedEntries = class
  public
    [Test] procedure ProbeIsSmallestEncryptedFileUnderPath;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  uZipVfs;

// Sets the "encrypted" bit in the central-directory header of each named entry.
procedure MarkEncrypted(const AZipPath: string; const ANames: array of string);
var
  Bytes: TBytes;
  I, J, NameLen: Integer;
  Name: string;
begin
  Bytes := TFile.ReadAllBytes(AZipPath);
  I := 0;
  while I + 46 <= Length(Bytes) do
  begin
    if (Bytes[I] = $50) and (Bytes[I + 1] = $4B) and (Bytes[I + 2] = 1) and
       (Bytes[I + 3] = 2) then
    begin
      NameLen := Bytes[I + 28] or (Bytes[I + 29] shl 8);
      Name := TEncoding.ANSI.GetString(Bytes, I + 46, NameLen);
      for J := 0 to High(ANames) do
        if Name = ANames[J] then
          Bytes[I + 8] := Bytes[I + 8] or 1;
    end;
    Inc(I);
  end;
  TFile.WriteAllBytes(AZipPath, Bytes);
end;

procedure TTestZipEncryptedEntries.ProbeIsSmallestEncryptedFileUnderPath;
var
  Dir, ZipPath, Probe: string;
  Zip: TZipFile;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-zipenc-' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(Dir);
  try
    ZipPath := TPath.Combine(Dir, 'enc.zip');
    Zip := TZipFile.Create;
    try
      Zip.Open(ZipPath, zmWrite);
      Zip.Add(TBytes(TEncoding.UTF8.GetBytes('plain')), 'plain.txt');
      Zip.Add(TBytes(TEncoding.UTF8.GetBytes('0123456789')), 'Sub/Big.txt');
      Zip.Add(TBytes(TEncoding.UTF8.GetBytes('x')), 'Sub/Small.txt');
      Zip.Close;
    finally
      Zip.Free;
    end;
    MarkEncrypted(ZipPath, ['Sub/Big.txt', 'Sub/Small.txt']);

    Assert.IsTrue(ZipFindEncryptedEntry(ZipPath, '', Probe), 'whole archive');
    Assert.AreEqual('Sub/Small.txt', Probe, 'smallest encrypted file');
    Assert.IsTrue(ZipFindEncryptedEntry(ZipPath, 'Sub', Probe), 'folder');
    Assert.AreEqual('Sub/Small.txt', Probe, 'smallest under folder');
    Assert.IsTrue(ZipFindEncryptedEntry(ZipPath, 'Sub/Big.txt', Probe), 'single file');
    Assert.AreEqual('Sub/Big.txt', Probe, 'the file itself');
    Assert.IsFalse(ZipFindEncryptedEntry(ZipPath, 'plain.txt', Probe), 'plain file');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZipEncryptedEntries);

end.
