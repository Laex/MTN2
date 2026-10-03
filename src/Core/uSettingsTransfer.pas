unit uSettingsTransfer;

{ Export and import of the user's settings as one zip file: the settings
  files of the config folder (session.json, keymap.json, usermenu.json, the
  associations, the hotlist, the SSH connection list, the user themes ...) -
  not the histories and not any state that only describes where the user
  last was. A marker entry tells an export from any other zip, and an import
  takes only entries it knows by name, so a foreign or damaged zip cannot
  write anywhere else. }

interface

uses
  System.SysUtils;

const
  cSettingsMarker = 'mtn2-settings.txt';
  cSettingsThemesDir = 'themes';

/// <summary>Names of the settings files that are kept in the config folder
/// itself (the user themes folder is handled separately).</summary>
function SettingsFileNames: TArray<string>;
/// <summary>True for a zip entry name an import accepts: one of
/// SettingsFileNames, or a .json file directly inside themes/.</summary>
function IsImportableEntry(const AEntryName: string): Boolean;

/// <summary>Writes the settings found in ASourceDir to AZipPath. ACount gets
/// the number of settings files written.</summary>
function ExportSettingsFrom(const ASourceDir, AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;
/// <summary>Reads AZipPath and writes its settings into ATargetDir; the files
/// it replaces are first saved as ATargetDir\settings-backup.zip.</summary>
function ImportSettingsInto(const AZipPath, ATargetDir: string; out ACount: Integer;
  out AError: string): Boolean;

/// <summary>The same for the user's config folder (uConfigLocation).</summary>
function ExportSettings(const AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;
function ImportSettings(const AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.Zip, uConfigLocation;

const
  cFileNames: array[0..9] of string = (
    'session.json', 'keymap.json', 'usermenu.json', 'associations.json',
    'externaltools.json', 'markdown-colors.json', 'folderhotlist.json',
    'sshconnections.json', 'workspaces.json', 'hidden-dialogs.json');
  cBackupName = 'settings-backup.zip';

function SettingsFileNames: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(cFileNames));
  for I := 0 to High(cFileNames) do
    Result[I] := cFileNames[I];
end;

function IsImportableEntry(const AEntryName: string): Boolean;
var
  I: Integer;
  Name, Leaf: string;
begin
  Result := False;
  Name := StringReplace(AEntryName, '\', '/', [rfReplaceAll]);
  for I := 0 to High(cFileNames) do
    if SameText(Name, cFileNames[I]) then
      Exit(True);
  if Name.StartsWith(cSettingsThemesDir + '/', True) then
  begin
    Leaf := Copy(Name, Length(cSettingsThemesDir) + 2, MaxInt);
    Result := (Leaf <> '') and (Pos('/', Leaf) = 0) and (Pos(':', Leaf) = 0) and
      (Leaf <> '.') and (Leaf <> '..') and (Pos('..', Leaf) = 0) and
      SameText(ExtractFileExt(Leaf), '.json');
  end;
end;

function ExportSettingsFrom(const ASourceDir, AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;
var
  Zip: TZipFile;
  Marker: TBytesStream;
  Name, Path, ThemesDir: string;
begin
  Result := False;
  ACount := 0;
  AError := '';
  try
    if TFile.Exists(AZipPath) then
      TFile.Delete(AZipPath);
    ForceDirectories(ExtractFilePath(TPath.GetFullPath(AZipPath)));
    Zip := TZipFile.Create;
    try
      Zip.Open(AZipPath, zmWrite);
      for Name in SettingsFileNames do
      begin
        Path := TPath.Combine(ASourceDir, Name);
        if TFile.Exists(Path) then
        begin
          Zip.Add(Path, Name);
          Inc(ACount);
        end;
      end;
      ThemesDir := TPath.Combine(ASourceDir, cSettingsThemesDir);
      if TDirectory.Exists(ThemesDir) then
        for Path in TDirectory.GetFiles(ThemesDir, '*.json') do
        begin
          Name := cSettingsThemesDir + '/' + ExtractFileName(Path);
          if IsImportableEntry(Name) then
          begin
            Zip.Add(Path, Name);
            Inc(ACount);
          end;
        end;
      Marker := TBytesStream.Create(TEncoding.UTF8.GetBytes('MTN2 settings export'#13#10));
      try
        Zip.Add(Marker, cSettingsMarker);
      finally
        Marker.Free;
      end;
    finally
      Zip.Free;
    end;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

function ImportSettingsInto(const AZipPath, ATargetDir: string; out ACount: Integer;
  out AError: string): Boolean;
var
  Zip: TZipFile;
  I, Dummy: Integer;
  Name, Dest, Root, BackupErr: string;
  HasMarker: Boolean;
begin
  Result := False;
  ACount := 0;
  AError := '';
  try
    if not TFile.Exists(AZipPath) then
    begin
      AError := 'File not found';
      Exit;
    end;
    Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(ATargetDir));
    Zip := TZipFile.Create;
    try
      Zip.Open(AZipPath, zmRead);
      HasMarker := False;
      for I := 0 to Zip.FileCount - 1 do
        if SameText(Zip.FileNames[I], cSettingsMarker) then
          HasMarker := True;
      if not HasMarker then
      begin
        AError := 'This is not an MTN2 settings file';
        Exit;
      end;
      // What is replaced is kept: one step back if the import was a mistake.
      // (Not when the zip being imported is that backup itself.)
      if not SameText(TPath.GetFullPath(AZipPath),
         TPath.GetFullPath(TPath.Combine(ATargetDir, cBackupName))) then
        ExportSettingsFrom(ATargetDir, TPath.Combine(ATargetDir, cBackupName), Dummy,
          BackupErr);
      for I := 0 to Zip.FileCount - 1 do
      begin
        Name := StringReplace(Zip.FileNames[I], '\', '/', [rfReplaceAll]);
        if not IsImportableEntry(Name) then
          Continue;
        Dest := TPath.GetFullPath(TPath.Combine(Root, StringReplace(Name, '/', PathDelim,
          [rfReplaceAll])));
        if not Dest.StartsWith(Root, True) then
          Continue;
        ForceDirectories(ExtractFilePath(Dest));
        Zip.Extract(I, ExtractFilePath(Dest), False);
        Inc(ACount);
      end;
    finally
      Zip.Free;
    end;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

function ExportSettings(const AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;
begin
  Result := ExportSettingsFrom(GetConfigDirectory, AZipPath, ACount, AError);
end;

function ImportSettings(const AZipPath: string; out ACount: Integer;
  out AError: string): Boolean;
begin
  Result := ImportSettingsInto(AZipPath, GetConfigDirectory, ACount, AError);
end;

end.
