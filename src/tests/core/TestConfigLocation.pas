unit TestConfigLocation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestConfigLocation = class
  public
    [Test] procedure Run;
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

initialization
  TDUnitX.RegisterTestFixture(TTestConfigLocation);

end.
