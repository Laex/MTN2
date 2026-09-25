program TestConfigLocation;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  uConfigLocation;

procedure RunTests;
var
  Dir, Path: string;
begin
  Writeln('Testing uConfigLocation...');

  Dir := GetConfigDirectory;
  Assert(Dir <> '', 'Config directory should not be empty');
  Assert(DirectoryExists(Dir), 'Config directory should exist or be created');

  Path := GetConfigFilePath('keymap.json');
  Assert(Pos('keymap.json', Path) > 0, 'Config file path should end with keymap.json');

  Path := GetConfigFilePath('session.json');
  Assert(Pos('session.json', Path) > 0, 'Config file path should end with session.json');

  Writeln('TestConfigLocation passed successfully.');
end;

begin
  try
    RunTests;
  except
    on E: Exception do
    begin
      Writeln('Test failed: ', E.Message);
      Halt(1);
    end;
  end;
end.
