unit uConfigLocation;

{ Centralized Configuration Directory Resolver for MTN2.
  Supports Standard Mode and Portable Mode (portable.dat).

  The folder of a normal installation is PlatformConfigDir: %APPDATA%\MTN2 on
  Windows, $XDG_CONFIG_HOME/mtn2 (default ~/.config/mtn2) on Linux. }

interface

uses
  System.SysUtils, System.IOUtils;

const
  cPortableMarkerName = 'portable.dat';

function IsPortableMode: Boolean;
/// <summary>The folder of the running program, with a trailing separator.</summary>
function ProgramDirectory: string;
/// <summary>The portable.dat whose presence next to the program switches the
/// settings to the program's own folder.</summary>
function PortableMarkerPath: string;
/// <summary>The settings folder of a normal (not portable) installation;
/// not created.</summary>
function StandardConfigDirectory: string;
/// <summary>True while SetConfigDirectoryOverride redirects the settings.</summary>
function ConfigDirectoryIsOverridden: Boolean;
/// <summary>Points every settings file (keymap.json, session.json, ...) at
/// ADir instead of the user's folder; '' restores the normal choice. The test
/// runner uses it so the tests see the built-in defaults, not a developer's
/// own files.</summary>
procedure SetConfigDirectoryOverride(const ADir: string);
function GetConfigDirectory: string;
function GetConfigFilePath(const AFileName: string): string;

implementation

uses
  uPlatformInfo;

var
  GConfigDirOverride: string;

procedure SetConfigDirectoryOverride(const ADir: string);
begin
  GConfigDirOverride := ADir;
end;

function ProgramDirectory: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function PortableMarkerPath: string;
begin
  Result := TPath.Combine(ProgramDirectory, cPortableMarkerName);
end;

function StandardConfigDirectory: string;
begin
  Result := PlatformConfigDir;
end;

function ConfigDirectoryIsOverridden: Boolean;
begin
  Result := GConfigDirOverride <> '';
end;

function IsPortableMode: Boolean;
begin
  // Only the exe's own folder decides. The current directory is wherever
  // MTN2 happened to be started from (a console, a shortcut's "Start in"),
  // and a portable.dat lying there must not flip an installed copy into
  // writing its settings next to the exe.
  Result := FileExists(PortableMarkerPath);
end;

function GetConfigDirectory: string;
begin
  if GConfigDirOverride <> '' then
  begin
    Result := GConfigDirOverride;
    if not DirectoryExists(Result) then
      ForceDirectories(Result);
  end
  else if IsPortableMode then
  begin
    Result := ExtractFilePath(ParamStr(0));
    if Result = '' then
      Result := GetCurrentDir;
  end
  else
  begin
    Result := PlatformConfigDir;
    if not DirectoryExists(Result) then
      ForceDirectories(Result);
  end;
end;

function GetConfigFilePath(const AFileName: string): string;
begin
  Result := TPath.Combine(GetConfigDirectory, AFileName);
end;

end.
