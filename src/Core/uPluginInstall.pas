unit uPluginInstall;

{ Installs a plugin from a folder or a .zip file into the plugins folder and
  removes one again. A plugin is a folder with a plugin.json (at the top of the
  source or in its single subfolder); it is installed as <plugins>\<id>.
  Archive entries that would leave the target folder are refused. }

interface

type
  TPluginInstallStatus = (
    pisOk,
    pisSourceMissing,
    pisNoManifest,
    pisBadId,
    pisExists,
    pisUnsafeArchive,
    pisFailed
  );

  TPluginInstallResult = record
    Status: TPluginInstallStatus;
    /// <summary>The id of the plugin read from its plugin.json (empty before that).</summary>
    Id: string;
    /// <summary>The system's reason for pisFailed.</summary>
    Detail: string;
    /// <summary>A plugin of the same id was there and has been replaced.</summary>
    Replaced: Boolean;
  end;

/// <summary>Letters, digits, '.', '_' and '-', not starting with a dot: a name that
/// is safe as a folder name.</summary>
function IsSafePluginId(const AId: string): Boolean;

/// <summary>Installs the plugin in ASource (folder or .zip) into APluginsDir. An
/// installed plugin of the same id gives pisExists unless AReplace is set.</summary>
function InstallPlugin(const ASource, APluginsDir: string; AReplace: Boolean): TPluginInstallResult;

/// <summary>Deletes the folder of the plugin AId; False when it is missing or a file
/// in it cannot be deleted (a loaded library on Windows).</summary>
function RemovePluginFolder(const AId, APluginsDir: string; out ADetail: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, uPluginManifest;

const
  cMaxArchiveBytes = Int64(512) * 1024 * 1024;

function IsSafePluginId(const AId: string): Boolean;
var
  C: Char;
begin
  Result := (AId <> '') and (Length(AId) <= 64) and (AId[1] <> '.') and (Pos('..', AId) = 0);
  if not Result then
    Exit;
  for C in AId do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-']) then
      Exit(False);
end;

function EntryIsSafe(const AName: string): Boolean;
var
  Part: string;
  Norm: string;
begin
  Norm := StringReplace(AName, '\', '/', [rfReplaceAll]);
  if (Norm = '') or (Norm[1] = '/') or (Pos(':', Norm) > 0) then
    Exit(False);
  for Part in Norm.Split(['/']) do
    if Part = '..' then
      Exit(False);
  Result := True;
end;

{ pisOk on success; the entries go below ADest. }
function ExtractZip(const AZip, ADest: string; out ADetail: string): TPluginInstallStatus;
var
  Zip: TZipFile;
  I: Integer;
  Header: TZipHeader;
  Stream: TStream;
  Out_: TFileStream;
  Name, Target: string;
  Total: Int64;
begin
  Result := pisOk;
  ADetail := '';
  Zip := TZipFile.Create;
  try
    Zip.Open(AZip, zmRead);
    Total := 0;
    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := Zip.FileNames[I];
      if not EntryIsSafe(Name) then
        Exit(pisUnsafeArchive);
      Inc(Total, Zip.FileInfo[I].UncompressedSize);
      if Total > cMaxArchiveBytes then
        Exit(pisUnsafeArchive);
    end;
    for I := 0 to Zip.FileCount - 1 do
    begin
      Name := StringReplace(Zip.FileNames[I], '/', PathDelim, [rfReplaceAll]);
      Target := TPath.Combine(ADest, Name);
      if Zip.FileNames[I].EndsWith('/') then
      begin
        TDirectory.CreateDirectory(Target);
        Continue;
      end;
      TDirectory.CreateDirectory(TPath.GetDirectoryName(Target));
      Zip.Read(I, Stream, Header);
      try
        Out_ := TFileStream.Create(Target, fmCreate);
        try
          Out_.CopyFrom(Stream, 0);
        finally
          Out_.Free;
        end;
      finally
        Stream.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      ADetail := E.Message;
      Result := pisFailed;
    end;
  end;
  Zip.Free;
end;

{ The folder that holds plugin.json: ARoot itself or its only subfolder. }
function FindPluginRoot(const ARoot: string): string;
var
  Dirs: TArray<string>;
begin
  if TFile.Exists(TPath.Combine(ARoot, 'plugin.json')) then
    Exit(ARoot);
  Dirs := TDirectory.GetDirectories(ARoot);
  if (Length(Dirs) = 1) and TFile.Exists(TPath.Combine(Dirs[0], 'plugin.json')) then
    Exit(Dirs[0]);
  Result := '';
end;

function InstallPlugin(const ASource, APluginsDir: string; AReplace: Boolean): TPluginInstallResult;
var
  Source, Temp, Root, Target, Backup: string;
  Manifest: TPluginManifest;
  FromZip: Boolean;
  Status: TPluginInstallStatus;
begin
  Result := Default(TPluginInstallResult);
  Source := Trim(ASource);
  if (Length(Source) >= 2) and (Source[1] = '"') and (Source[Length(Source)] = '"') then
    Source := Copy(Source, 2, Length(Source) - 2);
  FromZip := TFile.Exists(Source) and SameText(TPath.GetExtension(Source), '.zip');
  if not FromZip and not TDirectory.Exists(Source) then
  begin
    Result.Status := pisSourceMissing;
    Exit;
  end;
  Temp := '';
  try
    try
      if FromZip then
      begin
        Temp := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-' + TGUID.NewGuid.ToString);
        TDirectory.CreateDirectory(Temp);
        Status := ExtractZip(Source, Temp, Result.Detail);
        if Status <> pisOk then
        begin
          Result.Status := Status;
          Exit;
        end;
        Root := FindPluginRoot(Temp);
      end
      else
        Root := FindPluginRoot(Source);
      if (Root = '') or not TryReadPluginManifest(Root, Manifest) then
      begin
        Result.Status := pisNoManifest;
        Exit;
      end;
      Result.Id := Manifest.Id;
      if not IsSafePluginId(Manifest.Id) then
      begin
        Result.Status := pisBadId;
        Exit;
      end;
      Target := TPath.Combine(ExcludeTrailingPathDelimiter(APluginsDir), Manifest.Id);
      Backup := '';
      if TDirectory.Exists(Target) then
      begin
        if not AReplace then
        begin
          Result.Status := pisExists;
          Exit;
        end;
        Backup := Target + '.old';
        if TDirectory.Exists(Backup) then
          TDirectory.Delete(Backup, True);
        TDirectory.Move(Target, Backup);
        Result.Replaced := True;
      end;
      try
        TDirectory.CreateDirectory(ExcludeTrailingPathDelimiter(APluginsDir));
        TDirectory.Copy(Root, Target);
      except
        // A failed copy leaves the plugin that was there as it was.
        if TDirectory.Exists(Target) then
          try TDirectory.Delete(Target, True); except end;
        if (Backup <> '') and TDirectory.Exists(Backup) then
          try TDirectory.Move(Backup, Target); except end;
        raise;
      end;
      if Backup <> '' then
        try TDirectory.Delete(Backup, True); except end;
      Result.Status := pisOk;
    except
      on E: Exception do
      begin
        Result.Status := pisFailed;
        Result.Detail := E.Message;
      end;
    end;
  finally
    if Temp <> '' then
      try TDirectory.Delete(Temp, True); except end;
  end;
end;

function RemovePluginFolder(const AId, APluginsDir: string; out ADetail: string): Boolean;
var
  Dir: string;
begin
  ADetail := '';
  Result := False;
  if not IsSafePluginId(AId) then
    Exit;
  Dir := TPath.Combine(ExcludeTrailingPathDelimiter(APluginsDir), AId);
  if not TDirectory.Exists(Dir) then
    Exit;
  try
    TDirectory.Delete(Dir, True);
  except
    on E: Exception do
      ADetail := E.Message;
  end;
  Result := not TDirectory.Exists(Dir);
end;

end.
