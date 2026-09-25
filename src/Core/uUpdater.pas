unit uUpdater;

{ Self-update from GitHub Releases, without UI (uUpdateController drives it).

  Flow: FetchLatestRelease (GitHub API, latest non-draft/non-prerelease) ->
  IsNewerVersion against the exe's own version resource -> DownloadAsset
  (sha256 checked against the asset digest GitHub publishes) -> ExtractUpdate
  into <appdir>\.update-staging -> ApplyStagedUpdate -> RestartApplication.

  Files cannot be overwritten while MTN2.exe and its DLLs are loaded, but they
  can be renamed: ApplyStagedUpdate renames every file the package replaces
  to <name>.old, moves the new one in, and rolls everything back on the first
  failure. The restarted process (--wait-pid) runs CleanupOldFiles once the
  old one has exited. Only files present in the package are touched -- user
  config, 7z.dll and anything else in the app folder stay as they are.

  CROSS-PLATFORM: Windows-only (MoveFileEx, CreateProcess, version resource). }

interface

uses
  System.SysUtils, System.Classes;

const
  cUpdateRepo = 'Laex/MTN2';
  cUpdateAssetSuffix = '-win64.zip';
  cUpdateStagingDir = '.update-staging';
  cUpdateWaitPidSwitch = '--wait-pid';
  cUpdateCheckIntervalHours = 24;

type
  TUpdateRelease = record
    Tag: string;            // 'v0.3.2'
    Version: string;        // '0.3.2'
    HtmlUrl: string;        // release page
    AssetName: string;
    AssetUrl: string;
    AssetSize: Int64;
    AssetSha256: string;    // lowercase hex, '' when GitHub gave no digest
  end;

  TUpdateSettings = record
    CheckOnStart: Boolean;
    LastCheck: TDateTime;   // 0 = never
    SkipVersion: string;    // '' = none
  end;

  /// <summary>Progress/abort hook for DownloadAsset: return False to abort.</summary>
  TUpdateProgress = reference to function(ADone, ATotal: Int64): Boolean;

/// <summary>'v1.2.3' / '1.2.3' -> 1,2,3. False for anything else.</summary>
function TryParseVersion(const AText: string; out AMajor, AMinor, APatch: Integer): Boolean;
/// <summary>-1 / 0 / 1 like CompareStr. Unparsable sorts lowest.</summary>
function CompareVersions(const A, B: string): Integer;
function IsNewerVersion(const ACandidate, ACurrent: string): Boolean;

/// <summary>Major.Minor.Release of AExeFile's version resource ('' if none).</summary>
function FileVersionString(const AExeFile: string): string;
function AppVersionString: string;

/// <summary>Parses a GitHub "get latest release" response. False for drafts,
/// prereleases, a malformed tag or no asset ending in AAssetSuffix.</summary>
function ParseLatestReleaseJson(const AJson, AAssetSuffix: string;
  out ARelease: TUpdateRelease): Boolean;
function FetchLatestRelease(out ARelease: TUpdateRelease; out AError: string): Boolean;

function FileSha256(const AFileName: string): string;
function DownloadAsset(const ARelease: TUpdateRelease; const ADestFile: string;
  const AProgress: TUpdateProgress; out AError: string): Boolean;

/// <summary>Unzips AZipFile into AStagingDir (recreated). Requires MTN2.exe at
/// the package root and rejects entries escaping the folder.</summary>
function ExtractUpdate(const AZipFile, AStagingDir: string; out AError: string): Boolean;
/// <summary>Moves every file under AStagingDir into AAppDir (same relative
/// path), renaming each replaced file to *.old first. All-or-nothing.</summary>
function ApplyStagedUpdate(const AStagingDir, AAppDir: string; out AError: string): Boolean;
/// <summary>Deletes X.old / X.oldNNN left by ApplyStagedUpdate where X exists,
/// and a leftover staging folder. Locked files are skipped silently.</summary>
procedure CleanupOldFiles(const AAppDir: string);
function CanWriteToDir(const ADir: string): Boolean;

function AppDir: string;
function StagingDir: string;
/// <summary>Starts AExeFile with --wait-pid <this process>; the new process
/// waits for this one to exit before taking the single-instance lock.</summary>
function RestartApplication(const AExeFile: string; out AError: string): Boolean;
/// <summary>Called first thing in the dpr: honours --wait-pid.</summary>
procedure WaitForPreviousInstanceFromCommandLine;
/// <summary>First command-line argument that is not an updater switch.</summary>
function StartupPathArgument: string;

function DefaultUpdateSettings: TUpdateSettings;
function LoadUpdateSettings: TUpdateSettings;
procedure SaveUpdateSettings(const ASettings: TUpdateSettings);
function UpdateCheckDue(const ASettings: TUpdateSettings; ANow: TDateTime): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils, System.JSON, System.Hash, System.Generics.Collections,
  System.Zip, System.DateUtils, System.Net.HttpClient, System.Net.URLClient,
  uSession;

function TryParseVersion(const AText: string; out AMajor, AMinor, APatch: Integer): Boolean;
var
  S: string;
  Parts: TArray<string>;
begin
  AMajor := 0;
  AMinor := 0;
  APatch := 0;
  S := Trim(AText);
  if (S <> '') and CharInSet(S[1], ['v', 'V']) then
    Delete(S, 1, 1);
  Parts := S.Split(['.']);
  Result := (Length(Parts) = 3) and TryStrToInt(Parts[0], AMajor) and
    TryStrToInt(Parts[1], AMinor) and TryStrToInt(Parts[2], APatch) and
    (AMajor >= 0) and (AMinor >= 0) and (APatch >= 0);
end;

function CompareVersions(const A, B: string): Integer;
var
  A1, A2, A3, B1, B2, B3: Integer;
  OkA, OkB: Boolean;
begin
  OkA := TryParseVersion(A, A1, A2, A3);
  OkB := TryParseVersion(B, B1, B2, B3);
  if not OkA or not OkB then
    Exit(Ord(OkA) - Ord(OkB));
  if A1 <> B1 then Exit(Ord(A1 > B1) * 2 - 1);
  if A2 <> B2 then Exit(Ord(A2 > B2) * 2 - 1);
  if A3 <> B3 then Exit(Ord(A3 > B3) * 2 - 1);
  Result := 0;
end;

function IsNewerVersion(const ACandidate, ACurrent: string): Boolean;
var
  M, N, P: Integer;
begin
  Result := TryParseVersion(ACandidate, M, N, P) and
    (CompareVersions(ACandidate, ACurrent) > 0);
end;

function FileVersionString(const AExeFile: string): string;
var
  Handle, Size, Len: DWORD;
  Buf: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(AExeFile), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(AExeFile), 0, Size, @Buf[0]) then
    Exit;
  if not VerQueryValue(@Buf[0], '\', Pointer(Info), Len) or (Len < SizeOf(TVSFixedFileInfo)) then
    Exit;
  Result := Format('%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
    HiWord(Info.dwFileVersionLS)]);
end;

function AppVersionString: string;
begin
  Result := FileVersionString(ParamStr(0));
end;

function ParseLatestReleaseJson(const AJson, AAssetSuffix: string;
  out ARelease: TUpdateRelease): Boolean;
var
  Val: TJSONValue;
  Root, Asset: TJSONObject;
  Assets: TJSONArray;
  I, M, N, P: Integer;
  Digest: string;
begin
  Result := False;
  ARelease := Default(TUpdateRelease);
  Val := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Val is TJSONObject) then
      Exit;
    Root := TJSONObject(Val);
    if Root.GetValue<Boolean>('draft', False) or Root.GetValue<Boolean>('prerelease', False) then
      Exit;
    ARelease.Tag := Root.GetValue<string>('tag_name', '');
    if not TryParseVersion(ARelease.Tag, M, N, P) then
      Exit;
    ARelease.Version := Format('%d.%d.%d', [M, N, P]);
    ARelease.HtmlUrl := Root.GetValue<string>('html_url', '');
    if not Root.TryGetValue<TJSONArray>('assets', Assets) then
      Exit;
    for I := 0 to Assets.Count - 1 do
    begin
      if not (Assets.Items[I] is TJSONObject) then
        Continue;
      Asset := TJSONObject(Assets.Items[I]);
      if not Asset.GetValue<string>('name', '').EndsWith(AAssetSuffix, True) then
        Continue;
      ARelease.AssetName := Asset.GetValue<string>('name', '');
      ARelease.AssetUrl := Asset.GetValue<string>('browser_download_url', '');
      ARelease.AssetSize := Asset.GetValue<Int64>('size', 0);
      Digest := Asset.GetValue<string>('digest', '');
      if Digest.StartsWith('sha256:', True) then
        ARelease.AssetSha256 := LowerCase(Copy(Digest, 8, MaxInt));
      Exit(ARelease.AssetUrl <> '');
    end;
  finally
    Val.Free;
  end;
end;

function NewHttpClient(AResponseTimeoutMs: Integer): THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.UserAgent := 'MTN2-updater/' + AppVersionString;
  Result.ConnectionTimeout := 15000;
  Result.ResponseTimeout := AResponseTimeoutMs;
  Result.HandleRedirects := True;
end;

function FetchLatestRelease(out ARelease: TUpdateRelease; out AError: string): Boolean;
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
begin
  Result := False;
  AError := '';
  ARelease := Default(TUpdateRelease);
  Http := NewHttpClient(20000);
  try
    try
      Resp := Http.Get(Format('https://api.github.com/repos/%s/releases/latest', [cUpdateRepo]),
        nil, [TNetHeader.Create('Accept', 'application/vnd.github+json')]);
      if Resp.StatusCode <> 200 then
      begin
        AError := Format('GitHub: HTTP %d', [Resp.StatusCode]);
        Exit;
      end;
      Result := ParseLatestReleaseJson(Resp.ContentAsString(TEncoding.UTF8),
        cUpdateAssetSuffix, ARelease);
      if not Result then
        AError := 'GitHub: no suitable release package';
    except
      on E: Exception do
        AError := E.Message;
    end;
  finally
    Http.Free;
  end;
end;

function FileSha256(const AFileName: string): string;
begin
  Result := LowerCase(THashSHA2.GetHashStringFromFile(AFileName, SHA256));
end;

function DownloadAsset(const ARelease: TUpdateRelease; const ADestFile: string;
  const AProgress: TUpdateProgress; out AError: string): Boolean;
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  Stream: TFileStream;
  Aborted: Boolean;
  Actual: string;
begin
  AError := '';
  Aborted := False;
  ForceDirectories(ExtractFileDir(ADestFile));
  Http := NewHttpClient(60000);
  try
    Http.ReceiveDataCallBack :=
      procedure(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean)
      begin
        if Assigned(AProgress) and not AProgress(AReadCount, AContentLength) then
        begin
          Aborted := True;
          AAbort := True;
        end;
      end;
    Stream := TFileStream.Create(ADestFile, fmCreate);
    try
      try
        Resp := Http.Get(ARelease.AssetUrl, Stream);
        if Aborted then
          AError := 'cancelled'
        else if Resp.StatusCode <> 200 then
          AError := Format('HTTP %d', [Resp.StatusCode]);
      except
        on E: Exception do
          if Aborted then
            AError := 'cancelled'
          else
            AError := E.Message;
      end;
    finally
      Stream.Free;
    end;
  finally
    Http.Free;
  end;
  if AError = '' then
  begin
    Actual := FileSha256(ADestFile);
    if (ARelease.AssetSha256 <> '') and not SameText(Actual, ARelease.AssetSha256) then
      AError := 'sha256 mismatch'
    else if (ARelease.AssetSize > 0) and (TFile.GetSize(ADestFile) <> ARelease.AssetSize) then
      AError := 'size mismatch';
  end;
  Result := AError = '';
  if not Result then
    System.SysUtils.DeleteFile(ADestFile);
end;

function ExtractUpdate(const AZipFile, AStagingDir: string; out AError: string): Boolean;
var
  Zip: TZipFile;
  I: Integer;
  Name, Full, Root: string;
begin
  Result := False;
  AError := '';
  try
    if TDirectory.Exists(AStagingDir) then
      TDirectory.Delete(AStagingDir, True);
    ForceDirectories(AStagingDir);
    Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(AStagingDir));
    Zip := TZipFile.Create;
    try
      Zip.Open(AZipFile, zmRead);
      for I := 0 to Zip.FileCount - 1 do
      begin
        Name := StringReplace(Zip.FileNames[I], '/', PathDelim, [rfReplaceAll]);
        Full := TPath.GetFullPath(TPath.Combine(Root, Name));
        if not Full.StartsWith(Root, True) then
        begin
          AError := 'unsafe path in package: ' + Zip.FileNames[I];
          Exit;
        end;
      end;
      Zip.ExtractAll(AStagingDir);
    finally
      Zip.Free;
    end;
    if not TFile.Exists(TPath.Combine(AStagingDir, 'MTN2.exe')) then
    begin
      AError := 'package has no MTN2.exe';
      Exit;
    end;
    Result := True;
  except
    on E: Exception do
      AError := E.Message;
  end;
end;

type
  TAppliedFile = record
    Target: string;
    Backup: string;  // '' when the target did not exist before
  end;

function FreeBackupName(const ATarget: string): string;
var
  N: Integer;
begin
  Result := ATarget + '.old';
  if not FileExists(Result) or System.SysUtils.DeleteFile(Result) then
    Exit;
  // A previous .old is still locked (the process that loaded it is alive).
  for N := 1 to 999 do
  begin
    Result := ATarget + '.old' + IntToStr(N);
    if not FileExists(Result) or System.SysUtils.DeleteFile(Result) then
      Exit;
  end;
  Result := '';
end;

function ApplyStagedUpdate(const AStagingDir, AAppDir: string; out AError: string): Boolean;
var
  Files: TArray<string>;
  Done: TArray<TAppliedFile>;
  Src, Rel, Root: string;
  Item: TAppliedFile;
  I: Integer;
begin
  Result := False;
  AError := '';
  Root := IncludeTrailingPathDelimiter(TPath.GetFullPath(AStagingDir));
  Files := TDirectory.GetFiles(AStagingDir, '*', TSearchOption.soAllDirectories);
  SetLength(Done, 0);
  try
    for Src in Files do
    begin
      Rel := Copy(TPath.GetFullPath(Src), Length(Root) + 1, MaxInt);
      Item.Target := TPath.Combine(AAppDir, Rel);
      Item.Backup := '';
      ForceDirectories(ExtractFileDir(Item.Target));
      if FileExists(Item.Target) then
      begin
        Item.Backup := FreeBackupName(Item.Target);
        if (Item.Backup = '') or not MoveFileEx(PChar(Item.Target), PChar(Item.Backup), 0) then
        begin
          AError := Format('%s: %s', [Rel, SysErrorMessage(GetLastError)]);
          Exit;
        end;
      end;
      if not MoveFileEx(PChar(Src), PChar(Item.Target),
        MOVEFILE_REPLACE_EXISTING or MOVEFILE_COPY_ALLOWED) then
      begin
        AError := Format('%s: %s', [Rel, SysErrorMessage(GetLastError)]);
        if Item.Backup <> '' then
          MoveFileEx(PChar(Item.Backup), PChar(Item.Target), 0);
        Exit;
      end;
      SetLength(Done, Length(Done) + 1);
      Done[High(Done)] := Item;
    end;
    Result := True;
  finally
    if not Result then
      // Roll back in reverse: drop the new file, put the old one back.
      for I := High(Done) downto 0 do
      begin
        System.SysUtils.DeleteFile(Done[I].Target);
        if Done[I].Backup <> '' then
          MoveFileEx(PChar(Done[I].Backup), PChar(Done[I].Target), 0);
      end
    else
      try
        TDirectory.Delete(AStagingDir, True);
      except
        // harmless leftover; CleanupOldFiles retries on the next start
      end;
  end;
end;

procedure CleanupOldFiles(const AAppDir: string);
var
  F, Suffix: string;
  P, N: Integer;
begin
  if not TDirectory.Exists(AAppDir) then
    Exit;
  try
    for F in TDirectory.GetFiles(AAppDir, '*.old*', TSearchOption.soAllDirectories) do
    begin
      P := F.LastIndexOf('.old'); // 0-based: F[1..P] is the original name
      if P <= 0 then
        Continue;
      // Only X.old / X.old<digits>, and only while X itself exists: never
      // touch an unrelated user file that merely ends in .old.
      Suffix := Copy(F, P + 5, MaxInt);
      if (Suffix <> '') and not TryStrToInt(Suffix, N) then
        Continue;
      if FileExists(Copy(F, 1, P)) then
        System.SysUtils.DeleteFile(F);
    end;
    if TDirectory.Exists(TPath.Combine(AAppDir, cUpdateStagingDir)) then
      TDirectory.Delete(TPath.Combine(AAppDir, cUpdateStagingDir), True);
  except
    // best effort
  end;
end;

function CanWriteToDir(const ADir: string): Boolean;
var
  Probe: string;
  H: THandle;
begin
  Probe := TPath.Combine(ADir, '.mtn2-write-probe-' + IntToStr(GetCurrentProcessId));
  H := CreateFile(PChar(Probe), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_TEMPORARY or FILE_FLAG_DELETE_ON_CLOSE, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if Result then
    CloseHandle(H);
end;

function AppDir: string;
begin
  Result := ExtractFileDir(ParamStr(0));
end;

function StagingDir: string;
begin
  Result := TPath.Combine(AppDir, cUpdateStagingDir);
end;

function RestartApplication(const AExeFile: string; out AError: string): Boolean;
var
  Cmd: string;
  Si: TStartupInfo;
  Pi: TProcessInformation;
begin
  AError := '';
  Cmd := Format('"%s" %s %d', [AExeFile, cUpdateWaitPidSwitch, GetCurrentProcessId]);
  UniqueString(Cmd);
  ZeroMemory(@Si, SizeOf(Si));
  Si.cb := SizeOf(Si);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil,
    PChar(ExtractFileDir(AExeFile)), Si, Pi);
  if Result then
  begin
    CloseHandle(Pi.hThread);
    CloseHandle(Pi.hProcess);
  end
  else
    AError := SysErrorMessage(GetLastError);
end;

procedure WaitForPreviousInstanceFromCommandLine;
var
  I: Integer;
  Pid: Cardinal;
  H: THandle;
begin
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), cUpdateWaitPidSwitch) and
       TryStrToUInt(ParamStr(I + 1), Pid) then
    begin
      H := OpenProcess(SYNCHRONIZE, False, Pid);
      if H <> 0 then
      begin
        WaitForSingleObject(H, 30000);
        CloseHandle(H);
      end;
      Exit;
    end;
end;

function StartupPathArgument: string;
var
  I: Integer;
begin
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), cUpdateWaitPidSwitch) then
      Inc(I, 2)
    else
      Exit(ParamStr(I));
  end;
  Result := '';
end;

function UpdateSettingsFile: string;
begin
  Result := TPath.Combine(ExtractFileDir(DefaultSessionFilePath), 'update.json');
end;

function DefaultUpdateSettings: TUpdateSettings;
begin
  Result.CheckOnStart := True;
  Result.LastCheck := 0;
  Result.SkipVersion := '';
end;

function LoadUpdateSettings: TUpdateSettings;
var
  Val: TJSONValue;
  Root: TJSONObject;
  S: string;
begin
  Result := DefaultUpdateSettings;
  try
    if not TFile.Exists(UpdateSettingsFile) then
      Exit;
    Val := TJSONObject.ParseJSONValue(TFile.ReadAllText(UpdateSettingsFile, TEncoding.UTF8));
    try
      if not (Val is TJSONObject) then
        Exit;
      Root := TJSONObject(Val);
      Result.CheckOnStart := Root.GetValue<Boolean>('checkOnStart', True);
      Result.SkipVersion := Root.GetValue<string>('skipVersion', '');
      S := Root.GetValue<string>('lastCheck', '');
      if S <> '' then
        Result.LastCheck := ISO8601ToDate(S, False);
    finally
      Val.Free;
    end;
  except
    Result := DefaultUpdateSettings;
  end;
end;

procedure SaveUpdateSettings(const ASettings: TUpdateSettings);
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('checkOnStart', TJSONBool.Create(ASettings.CheckOnStart));
    if ASettings.LastCheck > 0 then
      Root.AddPair('lastCheck', DateToISO8601(ASettings.LastCheck, False));
    if ASettings.SkipVersion <> '' then
      Root.AddPair('skipVersion', ASettings.SkipVersion);
    try
      ForceDirectories(ExtractFileDir(UpdateSettingsFile));
      TFile.WriteAllText(UpdateSettingsFile, Root.ToJSON, TEncoding.UTF8);
    except
      // settings are a convenience; never fail the caller over them
    end;
  finally
    Root.Free;
  end;
end;

function UpdateCheckDue(const ASettings: TUpdateSettings; ANow: TDateTime): Boolean;
begin
  Result := ASettings.CheckOnStart and
    ((ASettings.LastCheck <= 0) or (ASettings.LastCheck > ANow) or
     (HoursBetween(ANow, ASettings.LastCheck) >= cUpdateCheckIntervalHours));
end;

end.
