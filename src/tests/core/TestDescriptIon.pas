unit TestDescriptIon;

{ Descript.ion: the line format, and reading and writing the file. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDescriptIon = class
  public
    [Test] procedure LinesParseWithAndWithoutQuotes;
    [Test] procedure LinesFormatQuotedWhenTheNameHasSpaces;
    [Test] procedure StoreReadReplaceAndRemove;
    [Test] procedure FileNameCaseAndOtherLinesAreKept;
    [Test] procedure Utf8AndAnsiFilesKeepTheirEncoding;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  uDescriptIon;

function NewDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-descr-' + IntToStr(Random(1 shl 24)));
  ForceDirectories(Result);
end;

function DescriptionOf(const ADir, AName: string): string;
var
  Map: TDictionary<string, string>;
begin
  Map := LoadDescriptions(ADir);
  try
    if not Map.TryGetValue(AName, Result) then
      Result := '<none>';
  finally
    Map.Free;
  end;
end;

procedure TTestDescriptIon.LinesParseWithAndWithoutQuotes;
var
  Name, Desc: string;
begin
  Assert.IsTrue(ParseDescriptionLine('readme.txt Read me first', Name, Desc), 'plain');
  Assert.AreEqual('readme.txt', Name);
  Assert.AreEqual('Read me first', Desc);
  Assert.IsTrue(ParseDescriptionLine('"my file.txt" With  spaces ', Name, Desc), 'quoted');
  Assert.AreEqual('my file.txt', Name);
  Assert.AreEqual('With  spaces', Desc, 'the description is trimmed, not reflowed');
  Assert.IsTrue(ParseDescriptionLine('alone.bin', Name, Desc), 'a name without a description');
  Assert.AreEqual('', Desc);
  Assert.IsFalse(ParseDescriptionLine('   ', Name, Desc), 'blank line');
  Assert.IsFalse(ParseDescriptionLine('"unterminated', Name, Desc), 'broken quote');
end;

procedure TTestDescriptIon.LinesFormatQuotedWhenTheNameHasSpaces;
begin
  Assert.AreEqual('a.txt about', FormatDescriptionLine('a.txt', 'about'));
  Assert.AreEqual('"a b.txt" about', FormatDescriptionLine('a b.txt', 'about'));
end;

procedure TTestDescriptIon.StoreReadReplaceAndRemove;
var
  Dir: string;
begin
  Dir := NewDir;
  try
    Assert.AreEqual('<none>', DescriptionOf(Dir, 'a.txt'), 'no file, no description');
    Assert.IsTrue(StoreDescription(Dir, 'a.txt', 'first'), 'store');
    Assert.IsTrue(StoreDescription(Dir, 'my file.txt', 'second'), 'store a name with spaces');
    Assert.AreEqual('first', DescriptionOf(Dir, 'a.txt'));
    Assert.AreEqual('second', DescriptionOf(Dir, 'my file.txt'));
    Assert.IsTrue(StoreDescription(Dir, 'a.txt', 'changed'), 'replace');
    Assert.AreEqual('changed', DescriptionOf(Dir, 'a.txt'));
    Assert.AreEqual('second', DescriptionOf(Dir, 'my file.txt'), 'the other entry is untouched');
    Assert.IsTrue(StoreDescription(Dir, 'a.txt', ''), 'an empty description removes the entry');
    Assert.AreEqual('<none>', DescriptionOf(Dir, 'a.txt'));
    Assert.IsTrue(StoreDescription(Dir, 'my file.txt', ''), 'remove the last one');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dir, 'Descript.ion')),
      'the file goes when nothing is left');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestDescriptIon.FileNameCaseAndOtherLinesAreKept;
var
  Dir: string;
begin
  Dir := NewDir;
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'DESCRIPT.ION'),
      'keep.txt kept'#13#10'"two words.doc" also kept'#13#10, TEncoding.UTF8);
    Assert.AreEqual('kept', DescriptionOf(Dir, 'KEEP.TXT'), 'names compare without case');
    Assert.IsTrue(StoreDescription(Dir, 'new.txt', 'added'));
    Assert.AreEqual('added', DescriptionOf(Dir, 'new.txt'));
    Assert.AreEqual('also kept', DescriptionOf(Dir, 'two words.doc'));
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(Dir))), 'the same file, not a second one');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestDescriptIon.Utf8AndAnsiFilesKeepTheirEncoding;
var
  Dir, Path, Ansi: string;
  Bytes: TBytes;
begin
  Dir := NewDir;
  try
    // A new file is UTF-8 with a BOM.
    Assert.IsTrue(StoreDescription(Dir, 'u.txt', 'caf' + #$00E9));
    Path := TPath.Combine(Dir, 'Descript.ion');
    Bytes := TFile.ReadAllBytes(Path);
    Assert.IsTrue((Length(Bytes) > 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
      'a new file starts with the UTF-8 BOM');
    Assert.AreEqual('caf' + #$00E9, DescriptionOf(Dir, 'u.txt'));
    TFile.Delete(Path);

    // A file in the ANSI code page (byte $E9 alone is not valid UTF-8) is read
    // and written back as ANSI, whichever code page the machine has.
    Ansi := 'caf' + TEncoding.ANSI.GetString(TBytes.Create($E9));
    TFile.WriteAllBytes(Path, TEncoding.ANSI.GetBytes('a.txt caf') + TBytes.Create($E9, 13, 10));
    Assert.AreEqual(Ansi, DescriptionOf(Dir, 'a.txt'), 'read as ANSI');
    Assert.IsTrue(StoreDescription(Dir, 'b.txt', 'plain'));
    Bytes := TFile.ReadAllBytes(Path);
    Assert.IsFalse((Length(Bytes) > 2) and (Bytes[0] = $EF), 'no BOM added to an ANSI file');
    Assert.AreEqual(Ansi, DescriptionOf(Dir, 'a.txt'), 'the old line survives');
    Assert.AreEqual('plain', DescriptionOf(Dir, 'b.txt'));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDescriptIon);

end.
