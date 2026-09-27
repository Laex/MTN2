unit TestExternalTools;

{ Alt+F3 / Alt+F4 external viewer / editor: which launch a command template
  resolves to, and externaltools.json round trip. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExternalTools = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestResolve;
    [Test] procedure TestPersistence;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  uExternalTools;

procedure TestResolve;
var
  Tools: TExternalTools;
  L: TExternalLaunch;
begin
  Tools := Default(TExternalTools);
  L := ResolveExternalLaunch(Tools, False, 'C:\a b\x.txt');
  Assert.IsTrue(L.Kind = elkShellOpen, 'empty viewer -> OS open');
  L := ResolveExternalLaunch(Tools, True, 'C:\a b\x.txt');
  Assert.IsTrue(L.Kind = elkShellEdit, 'empty editor -> OS edit / Notepad');

  Tools.ViewerCommand := '  ';
  L := ResolveExternalLaunch(Tools, False, 'C:\x.txt');
  Assert.IsTrue(L.Kind = elkShellOpen, 'blank viewer counts as empty');

  Tools.ViewerCommand := '"C:\Tools\view.exe" /ro %1';
  Tools.EditorCommand := 'code -g';
  L := ResolveExternalLaunch(Tools, False, 'C:\a b\x.txt');
  Assert.IsTrue((L.Kind = elkCommand) and
    (L.CommandLine = '"C:\Tools\view.exe" /ro "C:\a b\x.txt"'), '%1 -> quoted path: ' + L.CommandLine);
  L := ResolveExternalLaunch(Tools, True, 'C:\a b\x.txt');
  Assert.IsTrue((L.Kind = elkCommand) and (L.CommandLine = 'code -g "C:\a b\x.txt"'),
    'no %1 -> path appended: ' + L.CommandLine);
end;

procedure TestPersistence;
var
  Dir, Path: string;
  Tools, Back: TExternalTools;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-exttools-test');
  if TDirectory.Exists(Dir) then
    TDirectory.Delete(Dir, True);
  Path := TPath.Combine(Dir, 'externaltools.json');

  Back := LoadExternalTools(Path);
  Assert.IsTrue((Back.ViewerCommand = '') and (Back.EditorCommand = ''), 'missing file -> empty');

  Tools.ViewerCommand := 'view.exe "%1"';
  Tools.EditorCommand := 'C:\Программы\ed.exe %1';
  Assert.IsTrue(SaveExternalTools(Path, Tools), 'save creates the folder and file');
  Back := LoadExternalTools(Path);
  Assert.IsTrue(Back.ViewerCommand = Tools.ViewerCommand, 'viewer round trip (quotes)');
  Assert.IsTrue(Back.EditorCommand = Tools.EditorCommand, 'editor round trip (Cyrillic, backslash)');

  TFile.WriteAllText(Path, '{ not json', TEncoding.UTF8);
  Back := LoadExternalTools(Path);
  Assert.IsTrue((Back.ViewerCommand = '') and (Back.EditorCommand = ''), 'corrupt file -> empty');
  TFile.WriteAllText(Path, '[1,2]', TEncoding.UTF8);
  Back := LoadExternalTools(Path);
  Assert.IsTrue(Back.ViewerCommand = '', 'non-object JSON -> empty');

  TDirectory.Delete(Dir, True);
end;

{ TTestExternalTools }

procedure TTestExternalTools.SetupFixture;
begin
end;

procedure TTestExternalTools.TestResolve;
begin
  TestExternalTools.TestResolve;
end;

procedure TTestExternalTools.TestPersistence;
begin
  TestExternalTools.TestPersistence;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExternalTools);

end.
