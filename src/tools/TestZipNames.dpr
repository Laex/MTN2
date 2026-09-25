program TestZipNames;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uZipNames in '..\Core\uZipNames.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

begin
  try
    Writeln('NormZipName / IsUnsafeZipName / ZipWriteAllowed');
    Expect(NormZipName('\foo\bar\') = 'foo/bar', 'strips slashes and uses /');
    Expect(NormZipName('///a///') = 'a', 'trims leading and trailing slashes');
    Expect(NormZipName('') = '', 'empty stays empty');
    Expect(IsUnsafeZipName(''), 'empty is unsafe');
    Expect(IsUnsafeZipName('../x'), 'parent prefix is unsafe');
    Expect(IsUnsafeZipName('..'), 'dot-dot is unsafe');
    Expect(IsUnsafeZipName('a/../b'), 'embedded parent is unsafe');
    Expect(IsUnsafeZipName('C:evil'), 'drive colon is unsafe');
    Expect(not IsUnsafeZipName('dir/file.txt'), 'normal entry is safe');
    Expect(not IsUnsafeZipName('foo/..'), 'trailing .. without slash is unchanged');
    Expect(ZipWriteAllowed(nil), 'no segments is outer zip');
    Expect(ZipWriteAllowed(TArray<string>.Create('inner.txt')), 'one segment is outer zip');
    Expect(not ZipWriteAllowed(TArray<string>.Create('inner.zip', 'a')),
      'two segments is nested');

    Writeln('Prefix matching');
    var Rest: string;
    Expect(ZipRestAfterPrefix('a/b/c', 'a/', Rest) and (Rest = 'b/c'),
      'rest after a/');
    Expect(not ZipRestAfterPrefix('x/y', 'a/', Rest), 'outside prefix is miss');
    Expect(not ZipRestAfterPrefix('a/', 'a/', Rest), 'exact prefix rest is empty');
    Expect(ZipRestAfterPrefix('file.txt', '', Rest) and (Rest = 'file.txt'),
      'empty prefix keeps name');
    Expect(not ZipRestAfterPrefix('', '', Rest), 'empty name is miss');
    Expect(ZipNameEqualsOrUnder('dir/file', 'dir'), 'child is under dir');
    Expect(ZipNameEqualsOrUnder('dir', 'dir'), 'exact name matches');
    Expect(not ZipNameEqualsOrUnder('dir2/x', 'dir'), 'dir2 is not under dir');
    Expect(not ZipNameEqualsOrUnder('dir', ''), 'empty prefix is not under');

    Writeln('All ZipNames tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
