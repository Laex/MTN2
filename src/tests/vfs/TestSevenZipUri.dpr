program TestSevenZipUri;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
end;

begin
  try
    Expect(IsSevenZipFileName('pack.7z'), '.7z is seven-zip');
    Expect(IsSevenZipFileName('Proxifier4.rar'), '.rar is handled by 7z.dll plugin');
    Expect(not IsSevenZipFileName('pack.zip'), '.zip is not seven-zip');
    Expect(IsSevenZipUri('7z:///C:/a.7z!/'), '7z:/// is seven-zip URI');
    Expect(not IsSevenZipUri('file:///C:/a.7z!/'), 'file:// is not seven-zip URI');
    Expect(IsZipArchiveUri('file:///C:/a.zip!/x'), 'zip chain is core zip');
    Expect(not IsZipArchiveUri('7z:///C:/a.7z!/x'), '7z chain is not core zip');
    Expect(not IsZipArchiveUri('file:///C:/a.7z!/x'), '.7z file:// chain is not core zip');

    Expect(SameText(ArchiveBaseLocalPath('7z:///C:/Work/a.7z'),
      'C:\Work\a.7z'), '7z base path');
    Expect(PathToSevenZipRootUri('C:\Work\a.7z') = '7z:///C:/Work/a.7z!/',
      'root URI');
    Expect(ArchiveBasePath('7z:///C:/Work/a.7z!/dir') = 'C:\Work\a.7z',
      'ArchiveBasePath inner');
    Expect(JoinVfsUri('7z:///C:/Work/a.7z!/', 'readme.txt') =
      '7z:///C:/Work/a.7z!/readme.txt', 'join file at root');
    Expect(ParentVfsUri('7z:///C:/Work/a.7z!/dir/file.txt') =
      '7z:///C:/Work/a.7z!/dir', 'parent inside archive');
    Expect(SameText(FileUriToPath(ParentVfsUri('7z:///C:/Work/a.7z!/')),
      'C:\Work'), 'parent of archive root is folder');
    Expect(VfsUriTitle('7z:///C:/Work/a.7z!/') = 'a.7z', 'title at root');
    Writeln('All SevenZip URI tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
