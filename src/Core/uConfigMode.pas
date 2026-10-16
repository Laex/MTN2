unit uConfigMode;

{ Switching the settings between the two places MTN2 keeps them (see
  uConfigLocation): the user's settings folder of a normal installation and
  the folder of the program itself, selected by a portable.dat next to the
  exe. Both hold the same layout - the *.json files (session, histories, key
  map, plugin settings ...) and themes\*.json - so a switch is a move of those
  files plus creating or deleting portable.dat, nothing is converted.

  PlanConfigModeSwitch looks at both sides without changing anything and
  reports what would block the switch (the program folder cannot be written,
  both sides are the same folder) and what the user should know first (files
  in the target that get replaced, a Program Files or network folder, nothing
  to move). SwitchConfigMode copies every file, compares the copy byte by byte,
  keeps a replaced file of the target as "<name>.before-switch", and only then
  flips portable.dat, which is the moment the running program starts using the
  new place. A failure before that point removes the copies and puts the
  replaced files back, so the old settings stay in force. The originals are
  deleted last; one that cannot be deleted is only counted. }

interface

type
  TConfigMode = (cmStandard, cmPortable);

  TConfigModeBlocker = (
    /// <summary>SetConfigDirectoryOverride is active (tests, tools).</summary>
    cbOverridden,
    /// <summary>The standard settings folder is the program folder.</summary>
    cbSameFolder,
    /// <summary>portable.dat cannot be created or deleted there.</summary>
    cbProgramFolderReadOnly,
    /// <summary>The folder the settings would move to cannot be written.</summary>
    cbTargetFolderReadOnly,
    /// <summary>The settings to move cannot be listed.</summary>
    cbSourceUnreadable);
  TConfigModeBlockers = set of TConfigModeBlocker;

  TConfigModeWarning = (
    /// <summary>The current place holds no settings files.</summary>
    cwNothingToMove,
    /// <summary>Files of the target place are replaced (kept as .before-switch).</summary>
    cwTargetHasFiles,
    /// <summary>The program lives in Program Files, /usr or /opt.</summary>
    cwSystemProgramFolder,
    /// <summary>The program lives on a network share.</summary>
    cwNetworkProgramFolder);
  TConfigModeWarnings = set of TConfigModeWarning;

  TConfigModePlan = record
    FromMode: TConfigMode;
    ToMode: TConfigMode;
    SourceDir: string;
    TargetDir: string;
    ProgramDir: string;
    /// <summary>Settings files that would move.</summary>
    FileCount: Integer;
    TotalBytes: Int64;
    /// <summary>Of those, how many already exist in the target.</summary>
    ReplacedCount: Integer;
    Blockers: TConfigModeBlockers;
    Warnings: TConfigModeWarnings;
    function CanSwitch: Boolean;
  end;

const
  cBackupSuffix = '.before-switch';

function CurrentConfigMode: TConfigMode;

/// <summary>The plan for the running program: its folder, the standard
/// settings folder and the mode it is in now.</summary>
function PlanConfigModeSwitch: TConfigModePlan;
/// <summary>The plan for any pair of folders (the tests use temporary ones).
/// The mode is taken from ACurrent, not from portable.dat.</summary>
function PlanConfigModeSwitchFor(const AProgramDir, AStandardDir: string;
  ACurrent: TConfigMode): TConfigModePlan;

/// <summary>Moves the settings to the other place and flips portable.dat.
/// ALeftover is the number of originals that could not be deleted. On False
/// AError says why and the current place stays in use.</summary>
function SwitchConfigMode(out ALeftover: Integer; out AError: string): Boolean;
function SwitchConfigModeFor(const AProgramDir, AStandardDir: string;
  ACurrent: TConfigMode; out ALeftover: Integer; out AError: string): Boolean;

const
  /// <summary>The longest summary and its longest line, in cells (the
  /// settings location dialog shows them as they are).</summary>
  cSummaryMaxLines = 8;
  cSummaryMaxWidth = 72;

/// <summary>The text of the settings location dialog for APlan: where the
/// settings are, where they would go, how much moves, then what blocks the
/// switch or deserves a warning. Translated; at most cSummaryMaxLines lines of
/// at most cSummaryMaxWidth cells.</summary>
function ConfigModeSummaryLines(const APlan: TConfigModePlan): TArray<string>;

/// <summary>Names (relative to ADir, with the native separator) of the files
/// a switch moves: the *.json files of the folder itself and of its themes
/// folder.</summary>
function ConfigFilesIn(const ADir: string): TArray<string>;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  uConfigLocation, uStrings, uCharWidth;

const
  cThemesDir = 'themes';
  cSettingsBackup = 'settings-backup.zip';

function TConfigModePlan.CanSwitch: Boolean;
begin
  Result := Blockers = [];
end;

function CurrentConfigMode: TConfigMode;
begin
  if IsPortableMode then
    Result := cmPortable
  else
    Result := cmStandard;
end;

function SamePath(const A, B: string): Boolean;
var
  PA, PB: string;
begin
  PA := ExcludeTrailingPathDelimiter(TPath.GetFullPath(A));
  PB := ExcludeTrailingPathDelimiter(TPath.GetFullPath(B));
{$IFDEF MSWINDOWS}
  Result := SameText(PA, PB);
{$ELSE}
  Result := PA = PB;
{$ENDIF}
end;

function IsConfigFileName(const AName: string): Boolean;
var
  L: string;
begin
  L := LowerCase(AName);
  if L.EndsWith(cBackupSuffix) or (L = cPortableMarkerName) then
    Exit(False);
  Result := L.EndsWith('.json') or (Pos('.json.', L) > 0) or (L = cSettingsBackup);
end;

function ConfigFilesIn(const ADir: string): TArray<string>;
var
  List: TList<string>;
  Path, Name, ThemesDir: string;
begin
  List := TList<string>.Create;
  try
    if TDirectory.Exists(ADir) then
    begin
      for Path in TDirectory.GetFiles(ADir) do
      begin
        Name := ExtractFileName(Path);
        if IsConfigFileName(Name) then
          List.Add(Name);
      end;
      ThemesDir := TPath.Combine(ADir, cThemesDir);
      if TDirectory.Exists(ThemesDir) then
        for Path in TDirectory.GetFiles(ThemesDir, '*.json') do
        begin
          Name := ExtractFileName(Path);
          if not Name.EndsWith(cBackupSuffix, True) then
            List.Add(cThemesDir + PathDelim + Name);
        end;
    end;
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function NearestExistingDir(const ADir: string): string;
var
  Prev: string;
begin
  Result := ExcludeTrailingPathDelimiter(ADir);
  while (Result <> '') and not TDirectory.Exists(Result) do
  begin
    Prev := Result;
    Result := ExtractFileDir(Result);
    if Result = Prev then
      Exit('');
  end;
end;

// A real write: the read-only attribute of a folder says nothing about the
// rights on it.
function CanWriteIn(const ADir: string): Boolean;
var
  Dir, Probe: string;
begin
  Result := False;
  Dir := NearestExistingDir(ADir);
  if Dir = '' then
    Exit;
  Probe := TPath.Combine(Dir, '.mtn2-write-test-' + TGUID.NewGuid.ToString);
  try
    TFile.WriteAllText(Probe, 'x');
    TFile.Delete(Probe);
    Result := True;
  except
    Result := False;
  end;
end;

function IsSystemProgramFolder(const ADir: string): Boolean;
{$IFDEF MSWINDOWS}
const
  cVars: array[0..2] of string = ('ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432');
var
  I: Integer;
  Root: string;
begin
  Result := False;
  for I := 0 to High(cVars) do
  begin
    Root := GetEnvironmentVariable(cVars[I]);
    if (Root <> '') and
       IncludeTrailingPathDelimiter(ADir).StartsWith(IncludeTrailingPathDelimiter(Root), True) then
      Exit(True);
  end;
end;
{$ELSE}
begin
  Result := ADir.StartsWith('/usr/') or ADir.StartsWith('/opt/');
end;
{$ENDIF}

function PlanConfigModeSwitchFor(const AProgramDir, AStandardDir: string;
  ACurrent: TConfigMode): TConfigModePlan;
var
  Files: TArray<string>;
  Rel: string;
begin
  Result := Default(TConfigModePlan);
  Result.FromMode := ACurrent;
  if ACurrent = cmPortable then
    Result.ToMode := cmStandard
  else
    Result.ToMode := cmPortable;
  Result.ProgramDir := IncludeTrailingPathDelimiter(AProgramDir);
  if ACurrent = cmPortable then
  begin
    Result.SourceDir := Result.ProgramDir;
    Result.TargetDir := IncludeTrailingPathDelimiter(AStandardDir);
  end
  else
  begin
    Result.SourceDir := IncludeTrailingPathDelimiter(AStandardDir);
    Result.TargetDir := Result.ProgramDir;
  end;

  if SamePath(AProgramDir, AStandardDir) then
    Include(Result.Blockers, cbSameFolder);
  // portable.dat is created or deleted in the program folder in both directions.
  if not CanWriteIn(Result.ProgramDir) then
    Include(Result.Blockers, cbProgramFolderReadOnly);
  if (Result.ToMode = cmStandard) and not CanWriteIn(Result.TargetDir) then
    Include(Result.Blockers, cbTargetFolderReadOnly);

  try
    Files := ConfigFilesIn(Result.SourceDir);
  except
    Files := nil;
    Include(Result.Blockers, cbSourceUnreadable);
  end;
  for Rel in Files do
  begin
    Inc(Result.FileCount);
    try
      Inc(Result.TotalBytes, TFile.GetSize(TPath.Combine(Result.SourceDir, Rel)));
    except
      Include(Result.Blockers, cbSourceUnreadable);
    end;
    if TFile.Exists(TPath.Combine(Result.TargetDir, Rel)) then
      Inc(Result.ReplacedCount);
  end;

  if Result.FileCount = 0 then
    Include(Result.Warnings, cwNothingToMove);
  if Result.ReplacedCount > 0 then
    Include(Result.Warnings, cwTargetHasFiles);
  if Result.ToMode = cmPortable then
  begin
    if IsSystemProgramFolder(Result.ProgramDir) then
      Include(Result.Warnings, cwSystemProgramFolder);
    if Result.ProgramDir.StartsWith('\\') then
      Include(Result.Warnings, cwNetworkProgramFolder);
  end;
end;

function PlanConfigModeSwitch: TConfigModePlan;
begin
  Result := PlanConfigModeSwitchFor(ProgramDirectory, StandardConfigDirectory,
    CurrentConfigMode);
  if ConfigDirectoryIsOverridden then
    Include(Result.Blockers, cbOverridden);
end;

function FormatSize(ABytes: Int64): string;
begin
  if ABytes < 1024 then
    Result := Format('%d B', [ABytes])
  else if ABytes < 1024 * 1024 then
    Result := Format('%.1f KB', [ABytes / 1024])
  else
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)]);
end;

// A path that does not fit keeps its beginning and its end.
function ShortenPath(const APath: string; AMaxCells: Integer): string;
var
  Keep: Integer;
begin
  Result := ExcludeTrailingPathDelimiter(APath);
  if TextDisplayWidth(Result) <= AMaxCells then
    Exit;
  Keep := (AMaxCells - 3) div 2;
  Result := Copy(Result, 1, Keep) + '...' + Copy(Result, Length(Result) - Keep + 1, Keep);
end;

function ConfigModeSummaryLines(const APlan: TConfigModePlan): TArray<string>;
var
  Lines: TList<string>;
  Indent: string;
begin
  Indent := '  ';
  Lines := TList<string>.Create;
  try
    if APlan.FromMode = cmPortable then
      Lines.Add(T('ui.configMode.nowPortable', 'Now: portable mode - settings are next to the program:'))
    else
      Lines.Add(T('ui.configMode.nowStandard', 'Now: standard mode - settings are in the user folder:'));
    Lines.Add(Indent + ShortenPath(APlan.SourceDir, cSummaryMaxWidth - Length(Indent)));
    if APlan.ToMode = cmPortable then
      Lines.Add(T('ui.configMode.toPortable', 'Switch to portable mode: settings will be moved to:'))
    else
      Lines.Add(T('ui.configMode.toStandard', 'Switch to standard mode: settings will be moved to:'));
    Lines.Add(Indent + ShortenPath(APlan.TargetDir, cSummaryMaxWidth - Length(Indent)));
    if APlan.FileCount = 0 then
      Lines.Add(T('ui.configMode.nothing', 'There are no settings files to move.'))
    else
      Lines.Add(Format(T('ui.configMode.files', '%d files (%s) are moved; the old copies are deleted.'),
        [APlan.FileCount, FormatSize(APlan.TotalBytes)]));

    if cbOverridden in APlan.Blockers then
      Lines.Add(T('ui.configMode.blockOverridden', 'The settings folder is fixed and cannot be changed.'));
    if cbSameFolder in APlan.Blockers then
      Lines.Add(T('ui.configMode.blockSameFolder', 'The program folder is also the standard settings folder.'));
    if cbProgramFolderReadOnly in APlan.Blockers then
      Lines.Add(T('ui.configMode.blockProgramFolder', 'No write access to the program folder (portable.dat).'));
    if cbTargetFolderReadOnly in APlan.Blockers then
      Lines.Add(T('ui.configMode.blockTargetFolder', 'No write access to the folder the settings move to.'));
    if cbSourceUnreadable in APlan.Blockers then
      Lines.Add(T('ui.configMode.blockSource', 'The current settings files cannot be read.'));

    if cwTargetHasFiles in APlan.Warnings then
      Lines.Add(Format(T('ui.configMode.warnReplaced', '%d files there are replaced and kept as *.before-switch.'),
        [APlan.ReplacedCount]));
    if cwSystemProgramFolder in APlan.Warnings then
      Lines.Add(T('ui.configMode.warnSystemFolder', 'The program is in a system folder shared by all users.'));
    if cwNetworkProgramFolder in APlan.Warnings then
      Lines.Add(T('ui.configMode.warnNetwork', 'The program is on a network share: it may be slow.'));

    while Lines.Count > cSummaryMaxLines do
      Lines.Delete(Lines.Count - 1);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function SameBytes(const AFirst, ASecond: string): Boolean;
var
  A, B: TBytes;
begin
  A := TFile.ReadAllBytes(AFirst);
  B := TFile.ReadAllBytes(ASecond);
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure DeleteQuietly(const APath: string);
begin
  try
    if TFile.Exists(APath) then
    begin
      TFile.SetAttributes(APath, []);
      TFile.Delete(APath);
    end;
  except
    // Cleanup after a failure must not hide the failure itself.
  end;
end;

function SwitchConfigModeFor(const AProgramDir, AStandardDir: string;
  ACurrent: TConfigMode; out ALeftover: Integer; out AError: string): Boolean;
var
  Plan: TConfigModePlan;
  Files: TArray<string>;
  Created: TList<string>;
  Backups: TList<TPair<string, string>>;
  Rel, Src, Dst, Bak, Marker: string;
  I: Integer;
begin
  Result := False;
  ALeftover := 0;
  AError := '';
  Plan := PlanConfigModeSwitchFor(AProgramDir, AStandardDir, ACurrent);
  if not Plan.CanSwitch then
  begin
    AError := 'blocked';
    Exit;
  end;
  Marker := TPath.Combine(Plan.ProgramDir, cPortableMarkerName);
  Files := ConfigFilesIn(Plan.SourceDir);
  Created := TList<string>.Create;
  Backups := TList<TPair<string, string>>.Create;
  try
    try
      ForceDirectories(Plan.TargetDir);
      for Rel in Files do
      begin
        Src := TPath.Combine(Plan.SourceDir, Rel);
        Dst := TPath.Combine(Plan.TargetDir, Rel);
        ForceDirectories(ExtractFilePath(Dst));
        if TFile.Exists(Dst) then
        begin
          Bak := Dst + cBackupSuffix;
          DeleteQuietly(Bak);
          TFile.Move(Dst, Bak);
          Backups.Add(TPair<string, string>.Create(Dst, Bak));
        end;
        TFile.Copy(Src, Dst, True);
        Created.Add(Dst);
        if not SameBytes(Src, Dst) then
          raise EInOutError.CreateFmt('The copy of %s differs from the original', [Rel]);
      end;
      // The moment the running program starts using the new place.
      if Plan.ToMode = cmPortable then
        TFile.WriteAllText(Marker, 'MTN2 portable mode' + sLineBreak)
      else
      begin
        TFile.SetAttributes(Marker, []);
        TFile.Delete(Marker);
      end;
    except
      on E: Exception do
      begin
        for I := 0 to Created.Count - 1 do
          DeleteQuietly(Created[I]);
        for I := Backups.Count - 1 downto 0 do
          try
            TFile.Move(Backups[I].Value, Backups[I].Key);
          except
            // Keep going: restore as many of the replaced files as possible.
          end;
        AError := E.Message;
        Exit;
      end;
    end;
  finally
    Created.Free;
    Backups.Free;
  end;

  for Rel in Files do
  begin
    Src := TPath.Combine(Plan.SourceDir, Rel);
    try
      TFile.SetAttributes(Src, []);
      TFile.Delete(Src);
    except
      Inc(ALeftover);
    end;
  end;
  // Folders the move emptied: the themes folder, and the standard settings
  // folder itself when it was the source.
  try
    Dst := TPath.Combine(Plan.SourceDir, cThemesDir);
    if TDirectory.Exists(Dst) and TDirectory.IsEmpty(Dst) then
      TDirectory.Delete(Dst);
    if (Plan.FromMode = cmStandard) and TDirectory.Exists(Plan.SourceDir) and
       TDirectory.IsEmpty(Plan.SourceDir) then
      TDirectory.Delete(Plan.SourceDir);
  except
    // An empty leftover folder is harmless.
  end;
  Result := True;
end;

function SwitchConfigMode(out ALeftover: Integer; out AError: string): Boolean;
begin
  if ConfigDirectoryIsOverridden then
  begin
    ALeftover := 0;
    AError := 'blocked';
    Exit(False);
  end;
  Result := SwitchConfigModeFor(ProgramDirectory, StandardConfigDirectory,
    CurrentConfigMode, ALeftover, AError);
end;

end.
