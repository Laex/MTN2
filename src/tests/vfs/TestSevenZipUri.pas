unit TestSevenZipUri;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipUri = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uTextEncoding;

{ TTestSevenZipUri }

procedure TTestSevenZipUri.Run;
begin
  Assert.IsTrue(IsSevenZipFileName('pack.7z'), '.7z is seven-zip');
  Assert.IsTrue(IsSevenZipFileName('Proxifier4.rar'), '.rar is handled by 7z.dll plugin');
  Assert.IsTrue(not IsSevenZipFileName('pack.zip'), '.zip is not seven-zip');
  Assert.IsTrue(IsSevenZipUri('7z:///C:/a.7z!/'), '7z:/// is seven-zip URI');
  Assert.IsTrue(not IsSevenZipUri('file:///C:/a.7z!/'), 'file:// is not seven-zip URI');
  Assert.IsTrue(IsZipArchiveUri('file:///C:/a.zip!/x'), 'zip chain is core zip');
  Assert.IsTrue(not IsZipArchiveUri('7z:///C:/a.7z!/x'), '7z chain is not core zip');
  Assert.IsTrue(not IsZipArchiveUri('file:///C:/a.7z!/x'), '.7z file:// chain is not core zip');

  Assert.AreEqual('7z:///C:/Work/a.zip!/dir/f.txt',
    ZipEntryToSevenZipUri('file:///C:/Work/a.zip!/dir/f.txt'), 'zip entry through 7z');
  Assert.AreEqual('', ZipEntryToSevenZipUri('file:///C:/Work/plain/f.txt'), 'not an archive entry');
  Assert.AreEqual('', ZipEntryToSevenZipUri('file:///C:/Work/a.zip!/b.zip!/f.txt'),
    'nested archives are not mapped');

  Assert.IsTrue(SameText(ArchiveBaseLocalPath('7z:///C:/Work/a.7z'),
    'C:\Work\a.7z'), '7z base path');
  Assert.IsTrue(PathToSevenZipRootUri('C:\Work\a.7z') = '7z:///C:/Work/a.7z!/',
    'root URI');
  Assert.IsTrue(ArchiveBasePath('7z:///C:/Work/a.7z!/dir') = 'C:\Work\a.7z',
    'ArchiveBasePath inner');
  Assert.IsTrue(JoinVfsUri('7z:///C:/Work/a.7z!/', 'readme.txt') =
    '7z:///C:/Work/a.7z!/readme.txt', 'join file at root');
  Assert.IsTrue(ParentVfsUri('7z:///C:/Work/a.7z!/dir/file.txt') =
    '7z:///C:/Work/a.7z!/dir', 'parent inside archive');
  Assert.IsTrue(SameText(FileUriToPath(ParentVfsUri('7z:///C:/Work/a.7z!/')),
    'C:\Work'), 'parent of archive root is folder');
  Assert.IsTrue(VfsUriTitle('7z:///C:/Work/a.7z!/') = 'a.7z', 'title at root');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSevenZipUri);

end.
