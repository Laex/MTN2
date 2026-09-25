unit uConfigLocation;

{ Centralized Configuration Directory Resolver for MTN2.
  Supports Standard Mode (%APPDATA%\MTN2\) and Portable Mode (portable.dat).

  CROSS-PLATFORM (Этап 23): already degrades reasonably on its own --
  GetEnvironmentVariable('APPDATA') is empty on POSIX, so it already falls
  back to TPath.GetHomePath (no crash, no Winapi.* dependency here at all).
  Not yet XDG-correct though: on Linux this lands config files directly in
  $HOME/MTN2/ instead of $XDG_CONFIG_HOME (~/.config/MTN2/); cheap to fix
  when a POSIX build actually exists -- no reason to do it blind now. }

interface

uses
  System.SysUtils, System.IOUtils;

function IsPortableMode: Boolean;
function GetConfigDirectory: string;
function GetConfigFilePath(const AFileName: string): string;

implementation

function IsPortableMode: Boolean;
var
  ExeDir, PortableFile: string;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  PortableFile := TPath.Combine(ExeDir, 'portable.dat');
  if FileExists(PortableFile) then
    Exit(True);

  // Check current directory fallback
  if FileExists('portable.dat') then
    Exit(True);

  Result := False;
end;

function GetConfigDirectory: string;
var
  AppDataDir: string;
begin
  if IsPortableMode then
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
