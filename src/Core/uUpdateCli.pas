unit uUpdateCli;

{ `--update [stable|nightly]` on the command line: checks for a newer version,
  downloads and installs it without opening a window, then exits. The channel
  named here is remembered in update.json, so the next start (and a plain
  `--update`) follows the same channel. Steps and checks are those of the
  in-program updater (uUpdater): the package digest is verified, the files are
  swapped with rollback, and a program installed from a package (.deb, .rpm)
  is only checked, because the package manager updates it.

  Exit codes: 0 up to date or updated, 1 the update failed, 2 unknown channel,
  3 a newer version exists but the package manager has to install it. }

interface

const
  cUpdateSwitch = '--update';

type
  TUpdateLineWriter = reference to procedure(const ALine: string);

/// <summary>True for "stable", "nightly" and its older spelling "dev".</summary>
function IsUpdateChannelName(const AName: string): Boolean;

/// <summary>True when the command line asks for an update; AChannel is the
/// channel written after the switch ('' = the remembered one).</summary>
function UpdateRequested(out AChannel: string): Boolean;

/// <summary>Runs the update and writes its progress lines to AWrite; the result
/// is the process exit code.</summary>
function RunUpdateCommand(const AChannel: string; const AWrite: TUpdateLineWriter): Integer;

implementation

uses
  System.SysUtils, System.IOUtils, uUpdater, uPlatformInfo;

const
  cProgressStepMs = 2000;

function IsNightlyName(const AName: string): Boolean;
begin
  Result := SameText(AName, 'nightly') or SameText(AName, 'dev');
end;

function IsUpdateChannelName(const AName: string): Boolean;
begin
  Result := SameText(AName, 'stable') or IsNightlyName(AName);
end;

function UpdateRequested(out AChannel: string): Boolean;
var
  I: Integer;
  Arg: string;
begin
  AChannel := '';
  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if SameText(Arg, cUpdateSwitch) then
    begin
      // A word after the switch is the channel, so a misspelled one is refused
      // instead of updating along the remembered channel.
      if (I < ParamCount) and (Copy(ParamStr(I + 1), 1, 1) <> '-') then
        AChannel := ParamStr(I + 1);
      Exit(True);
    end;
    if SameText(Copy(Arg, 1, Length(cUpdateSwitch) + 1), cUpdateSwitch + '=') then
    begin
      AChannel := Copy(Arg, Length(cUpdateSwitch) + 2, MaxInt);
      Exit(True);
    end;
  end;
  Result := False;
end;

function RunUpdateCommand(const AChannel: string; const AWrite: TUpdateLineWriter): Integer;
var
  Settings: TUpdateSettings;
  Rel: TUpdateRelease;
  Current, Err, Zip, ChannelName: string;
  LastTick: UInt64;
  Ok: Boolean;
begin
  Settings := LoadUpdateSettings;
  if AChannel <> '' then
  begin
    if not IsUpdateChannelName(AChannel) then
    begin
      AWrite('Unknown channel "' + AChannel + '": use stable or nightly.');
      Exit(2);
    end;
    Settings.DevChannel := IsNightlyName(AChannel);
    SaveUpdateSettings(Settings);
  end;
  if Settings.DevChannel then
    ChannelName := 'nightly'
  else
    ChannelName := 'stable';

  Current := AppVersionString;
  AWrite('Installed: ' + Current + ', channel: ' + ChannelName);
  CleanupOldFiles(AppDir);
  AWrite('Checking github.com for the latest version...');
  if not FetchLatestRelease(Settings.DevChannel, Rel, Err) then
  begin
    AWrite('Could not check for updates: ' + Err);
    Exit(1);
  end;
  Settings.LastCheck := Now;
  SaveUpdateSettings(Settings);
  if not IsNewerVersion(Rel.Version, Current) then
  begin
    AWrite('Already up to date (' + Current + ').');
    Exit(0);
  end;
  AWrite('Latest version: ' + Rel.Version);
  if UpdatesManagedByPackage(AppDir) then
  begin
    AWrite('This copy is installed from a package: update it with the package manager.');
    Exit(3);
  end;
  if not CanWriteToDir(AppDir) then
  begin
    AWrite('The program folder is not writable: ' + AppDir);
    Exit(1);
  end;

  Zip := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'MTN2-update'), Rel.AssetName);
  LastTick := PlatformTickCount64;
  AWrite('Downloading ' + Rel.AssetName + '...');
  Ok := DownloadAsset(Rel, Zip,
    function(ADone, ATotal: Int64): Boolean
    begin
      if PlatformTickCount64 - LastTick >= cProgressStepMs then
      begin
        LastTick := PlatformTickCount64;
        AWrite('  ' + DownloadProgressText(ADone, ATotal));
      end;
      Result := True;
    end, Err);
  if Ok then
  begin
    AWrite('Unpacking...');
    Ok := ExtractUpdate(Zip, StagingDir, Err);
  end;
  System.SysUtils.DeleteFile(Zip);
  if Ok then
    Ok := ApplyStagedUpdate(StagingDir, AppDir, Err);
  if not Ok then
  begin
    AWrite('Could not update: ' + Err);
    Exit(1);
  end;
  AWrite('Updated to ' + Rel.Version + '. Start the program again to use it.');
  Result := 0;
end;

end.
