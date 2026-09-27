unit TestZipNames;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestZipNames = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  uZipNames;

{ TTestZipNames }

procedure TTestZipNames.Run;
begin
  Assert.IsTrue(NormZipName('\foo\bar\') = 'foo/bar', 'strips slashes and uses /');
  Assert.IsTrue(NormZipName('///a///') = 'a', 'trims leading and trailing slashes');
  Assert.IsTrue(NormZipName('') = '', 'empty stays empty');
  Assert.IsTrue(IsUnsafeZipName(''), 'empty is unsafe');
  Assert.IsTrue(IsUnsafeZipName('../x'), 'parent prefix is unsafe');
  Assert.IsTrue(IsUnsafeZipName('..'), 'dot-dot is unsafe');
  Assert.IsTrue(IsUnsafeZipName('a/../b'), 'embedded parent is unsafe');
  Assert.IsTrue(IsUnsafeZipName('C:evil'), 'drive colon is unsafe');
  Assert.IsTrue(not IsUnsafeZipName('dir/file.txt'), 'normal entry is safe');
  Assert.IsTrue(not IsUnsafeZipName('foo/..'), 'trailing .. without slash is unchanged');
  Assert.IsTrue(ZipWriteAllowed(nil), 'no segments is outer zip');
  Assert.IsTrue(ZipWriteAllowed(TArray<string>.Create('inner.txt')), 'one segment is outer zip');
  Assert.IsTrue(not ZipWriteAllowed(TArray<string>.Create('inner.zip', 'a')),
    'two segments is nested');

  System.Writeln('Prefix matching');
  var Rest: string;
  Assert.IsTrue(ZipRestAfterPrefix('a/b/c', 'a/', Rest) and (Rest = 'b/c'),
    'rest after a/');
  Assert.IsTrue(not ZipRestAfterPrefix('x/y', 'a/', Rest), 'outside prefix is miss');
  Assert.IsTrue(not ZipRestAfterPrefix('a/', 'a/', Rest), 'exact prefix rest is empty');
  Assert.IsTrue(ZipRestAfterPrefix('file.txt', '', Rest) and (Rest = 'file.txt'),
    'empty prefix keeps name');
  Assert.IsTrue(not ZipRestAfterPrefix('', '', Rest), 'empty name is miss');
  Assert.IsTrue(ZipNameEqualsOrUnder('dir/file', 'dir'), 'child is under dir');
  Assert.IsTrue(ZipNameEqualsOrUnder('dir', 'dir'), 'exact name matches');
  Assert.IsTrue(not ZipNameEqualsOrUnder('dir2/x', 'dir'), 'dir2 is not under dir');
  Assert.IsTrue(not ZipNameEqualsOrUnder('dir', ''), 'empty prefix is not under');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZipNames);

end.
