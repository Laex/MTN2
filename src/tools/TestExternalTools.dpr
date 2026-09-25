program TestExternalTools;

{$APPTYPE CONSOLE}

{ Alt+F3 / Alt+F4 external viewer / editor: which launch a command template
  resolves to, and externaltools.json round trip. }

uses
  System.SysUtils,
  System.IOUtils,
  uExternalTools;

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

procedure TestResolve;
var
  Tools: TExternalTools;
  L: TExternalLaunch;
begin
  Tools := Default(TExternalTools);
  L := ResolveExternalLaunch(Tools, False, 'C:\a b\x.txt');
  Expect(L.Kind = elkShellOpen, 'empty viewer -> OS open');
  L := ResolveExternalLaunch(Tools, True, 'C:\a b\x.txt');
  Expect(L.Kind = elkShellEdit, 'empty editor -> OS edit / Notepad');

  Tools.ViewerCommand := '  ';
  L := ResolveExternalLaunch(Tools, False, 'C:\x.txt');
  Expect(L.Kind = elkShellOpen, 'blank viewer counts as empty');

  Tools.ViewerCommand := '"C:\Tools\view.exe" /ro %1';
  Tools.EditorCommand := 'code -g';
  L := ResolveExternalLaunch(Tools, False, 'C:\a b\x.txt');
  Expect((L.Kind = elkCommand) and
    (L.CommandLine = '"C:\Tools\view.exe" /ro "C:\a b\x.txt"'), '%1 -> quoted path: ' + L.CommandLine);
  L := ResolveExternalLaunch(Tools, True, 'C:\a b\x.txt');
  Expect((L.Kind = elkCommand) and (L.CommandLine = 'code -g "C:\a b\x.txt"'),
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
  Expect((Back.ViewerCommand = '') and (Back.EditorCommand = ''), 'missing file -> empty');

  Tools.ViewerCommand := 'view.exe "%1"';
  Tools.EditorCommand := 'C:\Программы\ed.exe %1';
  Expect(SaveExternalTools(Path, Tools), 'save creates the folder and file');
  Back := LoadExternalTools(Path);
  Expect(Back.ViewerCommand = Tools.ViewerCommand, 'viewer round trip (quotes)');
  Expect(Back.EditorCommand = Tools.EditorCommand, 'editor round trip (Cyrillic, backslash)');

  TFile.WriteAllText(Path, '{ not json', TEncoding.UTF8);
  Back := LoadExternalTools(Path);
  Expect((Back.ViewerCommand = '') and (Back.EditorCommand = ''), 'corrupt file -> empty');
  TFile.WriteAllText(Path, '[1,2]', TEncoding.UTF8);
  Back := LoadExternalTools(Path);
  Expect(Back.ViewerCommand = '', 'non-object JSON -> empty');

  TDirectory.Delete(Dir, True);
end;

begin
  Failed := 0;
  try
    TestResolve;
    TestPersistence;
    if Failed = 0 then
      Writeln('All ExternalTools tests PASSED')
    else
    begin
      Writeln('FAILED: ', Failed, ' check(s)');
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
