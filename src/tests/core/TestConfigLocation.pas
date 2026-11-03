unit TestConfigLocation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConfigLocation = class
  public
    [Test] procedure Run;
    [Test] procedure EnvironmentVariableRedirectsSettings;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uConfigLocation;

procedure RunTests;
var
  Dir, Path: string;
begin

  Dir := GetConfigDirectory;
  Assert.IsTrue(Pos('mtn2-tests-', Dir) > 0,
    'the tests read their settings from a folder of their own: ' + Dir);
  Assert.IsFalse(FileExists(GetConfigFilePath('keymap.json')),
    'no keymap.json there, so the built-in keymap is in force');
  Assert.IsTrue(Dir <> '', 'Config directory should not be empty');
  Assert.IsTrue(DirectoryExists(Dir), 'Config directory should exist or be created');

  Path := GetConfigFilePath('keymap.json');
  Assert.IsTrue(Pos('keymap.json', Path) > 0, 'Config file path should end with keymap.json');

  Path := GetConfigFilePath('session.json');
  Assert.IsTrue(Pos('session.json', Path) > 0, 'Config file path should end with session.json');

  Writeln('TestConfigLocation passed successfully.');
end;

{ TTestConfigLocation }

procedure TTestConfigLocation.Run;
begin
  RunTests;
end;

procedure TTestConfigLocation.EnvironmentVariableRedirectsSettings;
var
  Saved, Dir: string;
begin
  Saved := ConfigDirectoryOverride;
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-envdir-test');
  try
    SetConfigDirectoryOverride('');
    ApplyConfigDirectoryEnvironment('   ');
    Assert.IsFalse(ConfigDirectoryIsOverridden, 'a blank value changes nothing');
    ApplyConfigDirectoryEnvironment(Dir + PathDelim);
    Assert.IsTrue(ConfigDirectoryIsOverridden, 'the variable takes the place of the normal choice');
    Assert.AreEqual(Dir, GetConfigDirectory);
    Assert.IsTrue(DirectoryExists(Dir), 'the folder is created on first use');
    Assert.AreEqual(TPath.Combine(Dir, 'keymap.json'), GetConfigFilePath('keymap.json'));
  finally
    SetConfigDirectoryOverride(Saved);
    if DirectoryExists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestConfigLocation);

end.
