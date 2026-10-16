unit TestSelfCheck;

{ uSelfCheck (MTN2.exe --self-check) against temp app folders: the embedded
  resources come from the runner's own MTN2.dres, the files from whatever the
  test lays out. sk4d.dll is not copied, so it always reports FAIL here --
  asserted as such rather than faked. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSelfCheck = class
  public
    [Test] procedure TestEmptyFolder;
    [Test] procedure TestCompleteLayout;
    [Test] procedure TestBrokenPlugin;
    [Test] procedure TestLocalePackVersions;
    [Test] procedure TestShippedThemes;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.IOUtils, uSelfCheck, uPlatformInfo, uStrings;

function NewTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-selfcheck-' + TGUID.NewGuid.ToString);
  ForceDirectories(Result);
end;

procedure WriteText(const AFile, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFile));
  TFile.WriteAllText(AFile, AText);
end;

function HasLine(const AReport: TSelfCheckReport; const AStart, APart: string): Boolean;
var
  Line: string;
begin
  for Line in AReport do
    if Line.StartsWith(AStart) and Line.Contains(APart) then
      Exit(True);
  Result := False;
end;

function FailCount(const AReport: TSelfCheckReport): Integer;
var
  Line: string;
begin
  Result := 0;
  for Line in AReport do
    if Line.StartsWith('FAIL') then
      Inc(Result);
end;

/// <summary>A language pack resource\<ALocale> written for pack revision AVersion.</summary>
procedure LayOutPack(const ADir, ALocale: string; AVersion: Integer);
begin
  WriteText(TPath.Combine(ADir, NativePath('resource/' + ALocale + '/locale.json')),
    '{"version":' + IntToStr(AVersion) + '}');
  WriteText(TPath.Combine(ADir, NativePath('resource/' + ALocale + '/strings.json')), '{}');
  WriteText(TPath.Combine(ADir, NativePath('resource/' + ALocale + '/help/index.md')), '# MTN2');
end;

procedure LayOutPackage(const ADir: string);
begin
  WriteText(TPath.Combine(ADir, NativePath('resource/en/help/index.md')), '# MTN2');
  LayOutPack(ADir, 'ru', ResourceVersion);
  LayOutPack(ADir, 'de', ResourceVersion);
  WriteText(TPath.Combine(ADir, NativePath('plugins/mtn.demo/plugin.json')),
    '{"id":"mtn.demo","name":"Demo","version":"0.1.0","abi":1}');
  WriteText(TPath.Combine(ADir, NativePath('plugins/mtn.demo/plugin.wat')), '(module)');
end;

procedure TTestSelfCheck.TestEmptyFolder;
var
  Dir: string;
  Report: TSelfCheckReport;
begin
  Dir := NewTempDir;
  try
    Assert.IsFalse(RunSelfCheck(Dir, Report), 'an empty folder is not a runnable copy');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource MENU_MAIN'), 'embedded menu found');
    Assert.IsTrue(HasLine(Report, 'OK', 'dialog resources'), 'embedded dialogs found');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource RESOURCE_VERSION'), 'embedded pack revision found');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'resource' + PathDelim + 'en' + PathDelim + 'help' + PathDelim + 'index.md'),
      'missing en help reported');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'resource' + PathDelim + ' is missing'), 'missing resource folder reported');
    // Only a program that draws through Skia needs its library.
    Assert.AreEqual(PlatformRenderLibrary <> '', HasLine(Report, 'FAIL', 'sk4d.dll'),
      'missing Skia library reported where it is needed');
    Assert.IsTrue(HasLine(Report, 'WARN', PlatformSharedLibName('wasmtime')), 'missing wasmtime.dll is only a warning');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'plugins' + PathDelim + ' is missing'), 'missing plugins folder reported');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSelfCheck.TestCompleteLayout;
var
  Dir: string;
  Report: TSelfCheckReport;
begin
  Dir := NewTempDir;
  try
    LayOutPackage(Dir);
    RunSelfCheck(Dir, Report);
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'en' + PathDelim + 'help' + PathDelim + 'index.md'), 'en help found');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'ru' + PathDelim + 'locale.json'), 'ru pack version accepted');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'ru' + PathDelim + 'strings.json'), 'ru strings found');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'ru' + PathDelim + 'help' + PathDelim + 'index.md'), 'ru help found');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'de' + PathDelim + 'help' + PathDelim + 'index.md'), 'de help found');
    Assert.IsTrue(HasLine(Report, 'OK', 'plugin mtn.demo'), 'plugin with manifest and module passes');
    // The Skia library, where one is needed, is not copied into the temp folder.
    Assert.AreEqual(Integer(Ord(PlatformRenderLibrary <> '')), Integer(FailCount(Report)),
      'only the Skia library fails: ' + string.Join(' | ', Report));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSelfCheck.TestBrokenPlugin;
var
  Dir: string;
  Report: TSelfCheckReport;
begin
  Dir := NewTempDir;
  try
    LayOutPackage(Dir);
    WriteText(TPath.Combine(Dir, NativePath('plugins/mtn.nomodule/plugin.json')),
      '{"id":"mtn.nomodule","name":"x","version":"0.1.0","abi":1}');
    WriteText(TPath.Combine(Dir, NativePath('plugins/mtn.wrongid/plugin.json')),
      '{"id":"mtn.other","name":"x","version":"0.1.0","abi":1}');
    WriteText(TPath.Combine(Dir, NativePath('plugins/mtn.wrongid/plugin.wat')), '(module)');
    ForceDirectories(TPath.Combine(Dir, NativePath('plugins/mtn.nomanifest')));
    RunSelfCheck(Dir, Report);
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.nomodule' + PathDelim + ' has no module'), 'plugin without a module');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.wrongid' + PathDelim + 'plugin.json names id'), 'manifest id mismatch');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.nomanifest' + PathDelim + 'plugin.json is missing'), 'missing manifest');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSelfCheck.TestLocalePackVersions;
var
  Dir: string;
  Report: TSelfCheckReport;
begin
  Dir := NewTempDir;
  try
    LayOutPackage(Dir);
    LayOutPack(Dir, 'old', ResourceVersion - 1);
    LayOutPack(Dir, 'new', ResourceVersion + 1);
    WriteText(TPath.Combine(Dir, NativePath('resource/nover/strings.json')), '{}');
    RunSelfCheck(Dir, Report);
    Assert.IsTrue(HasLine(Report, 'WARN', 'old' + PathDelim + 'locale.json version'), 'an older pack is only a warning');
    Assert.IsTrue(HasLine(Report, 'OK', 'resource' + PathDelim + 'old' + PathDelim + 'strings.json'), 'an older pack is still checked');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'new' + PathDelim + 'locale.json version'), 'a newer pack fails');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'nover' + PathDelim + 'locale.json is missing'), 'a pack without locale.json fails');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSelfCheck.TestShippedThemes;
var
  Dir: string;
  Report: TSelfCheckReport;
begin
  Dir := NewTempDir;
  try
    LayOutPackage(Dir);
    RunSelfCheck(Dir, Report);
    Assert.IsTrue(HasLine(Report, 'WARN', 'themes' + PathDelim + ' is missing'),
      'no theme folder leaves only the default theme');
    WriteText(TPath.Combine(Dir, NativePath('resource/themes/Good.theme.json')), '{"schema":2,"name":"Good"}');
    WriteText(TPath.Combine(Dir, NativePath('resource/themes/Bad.theme.json')), '{ not json');
    RunSelfCheck(Dir, Report);
    Assert.IsFalse(HasLine(Report, 'FAIL', 'themes' + PathDelim + 'locale.json'), 'the theme folder is not a language pack');
    Assert.IsTrue(HasLine(Report, 'OK', '1 shipped themes'), 'the valid theme counts');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'Bad.theme.json is not a valid theme file'), 'an unparsable theme fails');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelfCheck);

end.
