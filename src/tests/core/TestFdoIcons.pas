unit TestFdoIcons;

{ File type icons from freedesktop data: the MIME type of a name comes from the
  glob list, the icon names from the generic-icons list, and the icon file from
  the first theme that has it. The data is a small set of files in a temporary
  folder. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFdoIcons = class
  private
    FDir: string;
    procedure Touch(const ARelative: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MimeComesFromExtensionAndWholeName;
    [Test] procedure LongestSuffixWins;
    [Test] procedure IconNamesGoFromSpecificToGeneric;
    [Test] procedure IconFileIsTakenFromTheFirstThemeThatHasIt;
    [Test] procedure ScalableIconIsUsedWhenNoBitmapExists;
    [Test] procedure MissingIconGivesEmptyPath;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.IOUtils, uFdoIcons;

procedure TTestFdoIcons.Touch(const ARelative: string);
var
  Path: string;
begin
  Path := TPath.Combine(FDir, NativePath(ARelative));
  TDirectory.CreateDirectory(ExtractFilePath(Path));
  TFile.WriteAllText(Path, 'x', TEncoding.ASCII);
end;

procedure TTestFdoIcons.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-fdo-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FDir);
  TFile.WriteAllText(TPath.Combine(FDir, 'globs2'),
    '# comment'#10 +
    '50:text/x-python:*.py'#10 +
    '50:application/x-compressed-tar:*.tar.gz'#10 +
    '50:application/gzip:*.gz'#10 +
    '50:text/x-makefile:Makefile'#10 +
    '50:image/png:*.PNG:cs'#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(FDir, 'generic-icons'),
    'text/x-python:text-x-script'#10 +
    'application/gzip:package-x-generic'#10, TEncoding.ASCII);
  FdoSetSources(TPath.Combine(FDir, 'globs2'), TPath.Combine(FDir, 'generic-icons'),
    [TPath.Combine(FDir, 'icons')], ['Mine', 'Other']);
end;

procedure TTestFdoIcons.TearDown;
begin
  FdoUseSystemSources;
  TDirectory.Delete(FDir, True);
end;

procedure TTestFdoIcons.MimeComesFromExtensionAndWholeName;
begin
  Assert.AreEqual('text/x-python', FdoMimeForFileName('run.PY'), 'extension, any case');
  Assert.AreEqual('text/x-makefile', FdoMimeForFileName('makefile'), 'whole name');
  Assert.AreEqual('image/png', FdoMimeForFileName('a.png'));
  Assert.AreEqual('', FdoMimeForFileName('notes.unknown'));
  Assert.AreEqual('', FdoMimeForFileName('noextension'));
end;

procedure TTestFdoIcons.LongestSuffixWins;
begin
  Assert.AreEqual('application/x-compressed-tar', FdoMimeForFileName('a.tar.gz'));
  Assert.AreEqual('application/gzip', FdoMimeForFileName('a.gz'));
end;

procedure TTestFdoIcons.IconNamesGoFromSpecificToGeneric;
var
  Names: TArray<string>;
begin
  Names := FdoIconNamesForMime('text/x-python');
  Assert.AreEqual('text-x-python', Names[0]);
  Assert.AreEqual('text-x-script', Names[1], 'generic icon of the type');
  Assert.AreEqual('text-x-generic', Names[2], 'media type icon');
  Names := FdoIconNamesForMime('');
  Assert.AreEqual(1, Integer(Length(Names)), 'unknown type');
  Assert.AreEqual('text-x-generic', Names[0]);
end;

procedure TTestFdoIcons.IconFileIsTakenFromTheFirstThemeThatHasIt;
var
  Found: string;
begin
  Touch('icons/Other/32x32/mimetypes/text-x-python.png');
  Found := FdoFindIcon('mimetypes', 'text-x-python');
  Assert.IsTrue(Found.EndsWith('text-x-python.png') and (Pos('Other', Found) > 0), Found);
  Touch('icons/Mine/16/mimetypes/text-x-python.svg');
  FdoSetSources(TPath.Combine(FDir, 'globs2'), TPath.Combine(FDir, 'generic-icons'),
    [TPath.Combine(FDir, 'icons')], ['Mine', 'Other']);
  Found := FdoFindIcon('mimetypes', 'text-x-python');
  Assert.IsTrue(Pos('Mine', Found) > 0, 'the preferred theme wins over a larger icon: ' + Found);
end;

procedure TTestFdoIcons.ScalableIconIsUsedWhenNoBitmapExists;
var
  Found: string;
begin
  Touch('icons/Mine/scalable/places/folder.svg');
  Found := FdoFindIcon('places', 'folder');
  Assert.IsTrue(Found.EndsWith('folder.svg'), Found);
end;

procedure TTestFdoIcons.MissingIconGivesEmptyPath;
begin
  Assert.AreEqual('', FdoFindIcon('mimetypes', 'no-such-icon'));
  Assert.AreEqual('', FdoFindIcon('mimetypes', 'no-such-icon'), 'the answer is cached');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFdoIcons);

end.
