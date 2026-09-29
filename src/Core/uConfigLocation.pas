unit uConfigLocation;

{ Centralized Configuration Directory Resolver for MTN2.
  Supports Standard Mode (%APPDATA%\MTN2\) and Portable Mode (portable.dat).

  CROSS-PLATFORM: already degrades reasonably on its own --
  GetEnvironmentVariable('APPDATA') is empty on POSIX, so it already falls
  back to TPath.GetHomePath (no crash, no Winapi.* dependency here at all).
  Not yet XDG-correct though: on Linux this lands config files directly in
  $HOME/MTN2/ instead of $XDG_CONFIG_HOME (~/.config/MTN2/); cheap to fix
  when a POSIX build exists -- no reason to do it blind now. }

interface

uses
  System.SysUtils, System.IOUtils;

function IsPortableMode: Boolean;
/// <summary>Points every settings file (keymap.json, session.json, ...) at
/// ADir instead of the user's folder; '' restores the normal choice. The test
/// runner uses it so the tests see the built-in defaults, not a developer's
/// own files.</summary>
procedure SetConfigDirectoryOverride(const ADir: string);
function GetConfigDirectory: string;
function GetConfigFilePath(const AFileName: string): string;

implementation

var
  GConfigDirOverride: string;

procedure SetConfigDirectoryOverride(const ADir: string);
begin
  GConfigDirOverride := ADir;
end;

function IsPortableMode: Boolean;
begin
  // Only the exe's own folder decides. The current directory is wherever
  // MTN2 happened to be started from (a console, a shortcut's "Start in"),
  // and a portable.dat lying there must not flip an installed copy into
  // writing its settings next to the exe.
  Result := FileExists(TPath.Combine(ExtractFilePath(ParamStr(0)), 'portable.dat'));
end;

function GetConfigDirectory: string;
var
  AppDataDir: string;
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
    AppDataDir := GetEnvironmentVariable('APPDATA');
    if AppDataDir = '' then
      AppDataDir := TPath.GetHomePath;
    Result := TPath.Combine(AppDataDir, 'MTN2');
    if not DirectoryExists(Result) then
      ForceDirectories(Result);
  end;
end;

function GetConfigFilePath(const AFileName: string): string;
begin
  Result := TPath.Combine(GetConfigDirectory, AFileName);
end;

end.
