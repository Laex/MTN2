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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uSelfCheck;

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

procedure LayOutPackage(const ADir: string);
begin
  WriteText(TPath.Combine(ADir, 'help\en\index.md'), '# MTN2');
  WriteText(TPath.Combine(ADir, 'help\ru\index.md'), '# MTN2');
  WriteText(TPath.Combine(ADir, 'plugins\mtn.demo\plugin.json'),
    '{"id":"mtn.demo","name":"Demo","version":"0.1.0","abi":1}');
  WriteText(TPath.Combine(ADir, 'plugins\mtn.demo\plugin.wat'), '(module)');
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
    Assert.IsTrue(HasLine(Report, 'FAIL', 'help\en\index.md'), 'missing en help reported');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'help\ru\index.md'),
      'missing help for the embedded ru locale reported');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'sk4d.dll'), 'missing sk4d.dll reported');
    Assert.IsTrue(HasLine(Report, 'WARN', 'wasmtime.dll'), 'missing wasmtime.dll is only a warning');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'plugins\ is missing'), 'missing plugins folder reported');
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
    Assert.IsTrue(HasLine(Report, 'OK', 'help\ru\index.md'), 'ru help found');
    Assert.IsTrue(HasLine(Report, 'OK', 'plugin mtn.demo'), 'plugin with manifest and module passes');
    Assert.AreEqual(1, FailCount(Report),
      'only sk4d.dll (not copied into the temp folder) fails: ' + string.Join(' | ', Report));
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
    WriteText(TPath.Combine(Dir, 'plugins\mtn.nomodule\plugin.json'),
      '{"id":"mtn.nomodule","name":"x","version":"0.1.0","abi":1}');
    WriteText(TPath.Combine(Dir, 'plugins\mtn.wrongid\plugin.json'),
      '{"id":"mtn.other","name":"x","version":"0.1.0","abi":1}');
    WriteText(TPath.Combine(Dir, 'plugins\mtn.wrongid\plugin.wat'), '(module)');
    ForceDirectories(TPath.Combine(Dir, 'plugins\mtn.nomanifest'));
    RunSelfCheck(Dir, Report);
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.nomodule\ has no module'), 'plugin without a module');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.wrongid\plugin.json names id'), 'manifest id mismatch');
    Assert.IsTrue(HasLine(Report, 'FAIL', 'mtn.nomanifest\plugin.json is missing'), 'missing manifest');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelfCheck);

end.
