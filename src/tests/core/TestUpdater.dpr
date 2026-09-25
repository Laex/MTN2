program TestUpdater;

{$APPTYPE CONSOLE}

{ uUpdater: version compare, GitHub release JSON, sha256, package extraction,
  the rename-to-.old swap with rollback, .old cleanup and the check schedule.
  Everything runs on temp folders; the one live GitHub call SKIPs offline. }

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  uUpdater in '..\..\Core\uUpdater.pas';

var
  GTemp: string;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function ReadText(const AFile: string): string;
begin
  Result := TFile.ReadAllText(AFile);
end;

procedure WriteText(const AFile, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFile));
  TFile.WriteAllText(AFile, AText);
end;

procedure TestVersions;
var
  M, N, P: Integer;
begin
  Writeln('Versions');
  Expect(TryParseVersion('v0.3.1', M, N, P) and (M = 0) and (N = 3) and (P = 1), 'v0.3.1 parses');
  Expect(TryParseVersion('10.20.30', M, N, P) and (P = 30), 'plain 10.20.30 parses');
  Expect(not TryParseVersion('0.3', M, N, P), '0.3 rejected');
  Expect(not TryParseVersion('v0.3.1-beta', M, N, P), 'suffix rejected');
  Expect(not TryParseVersion('', M, N, P), 'empty rejected');
  Expect(CompareVersions('0.3.10', '0.3.9') > 0, '0.3.10 > 0.3.9 (numeric, not text)');
  Expect(CompareVersions('v1.0.0', '0.99.99') > 0, 'major wins');
  Expect(CompareVersions('0.3.1', 'v0.3.1') = 0, 'v prefix ignored');
  Expect(IsNewerVersion('0.3.2', '0.3.1'), '0.3.2 is newer than 0.3.1');
  Expect(not IsNewerVersion('0.3.1', '0.3.1'), 'same version is not newer');
  Expect(not IsNewerVersion('0.3.0', '0.3.1'), 'older is not newer');
  Expect(IsNewerVersion('0.3.1', ''), 'any version beats an unknown current one');
  Expect(not IsNewerVersion('garbage', '0.3.1'), 'unparsable candidate never offered');
end;

const
  cReleaseJson =
    '{"tag_name":"v0.3.2","draft":false,"prerelease":false,' +
    '"html_url":"https://github.com/Laex/MTN2/releases/tag/v0.3.2","assets":[' +
    '{"name":"notes.txt","size":3,"browser_download_url":"https://x/notes.txt"},' +
    '{"name":"MTN2-v0.3.2-win64.zip","size":21874456,' +
    '"digest":"sha256:517ECD50149C1456318F589BD5CD22D7C3226E20507643827E80F6E5072C9AE0",' +
    '"browser_download_url":"https://github.com/Laex/MTN2/releases/download/v0.3.2/MTN2-v0.3.2-win64.zip"}]}';

procedure TestReleaseJson;
var
  R: TUpdateRelease;
begin
  Writeln('GitHub release JSON');
  Expect(ParseLatestReleaseJson(cReleaseJson, cUpdateAssetSuffix, R), 'parses a normal release');
  Expect(R.Version = '0.3.2', 'version from tag');
  Expect(R.AssetName = 'MTN2-v0.3.2-win64.zip', 'picks the -win64.zip asset, not the first one');
  Expect(R.AssetSize = 21874456, 'asset size');
  Expect(R.AssetSha256 = '517ecd50149c1456318f589bd5cd22d7c3226e20507643827e80f6e5072c9ae0',
    'digest lowercased, sha256: prefix stripped');
  Expect(R.HtmlUrl.EndsWith('/v0.3.2'), 'release page url');
  Expect(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '"draft":false', '"draft":true', []),
    cUpdateAssetSuffix, R), 'draft ignored');
  Expect(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '"prerelease":false',
    '"prerelease":true', []), cUpdateAssetSuffix, R), 'prerelease ignored');
  Expect(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '-win64.zip', '-linux.tar.gz',
    [rfReplaceAll]), cUpdateAssetSuffix, R), 'no win64 package -> nothing to offer');
  Expect(not ParseLatestReleaseJson(StringReplace(cReleaseJson, 'v0.3.2"', 'nightly"', []),
    cUpdateAssetSuffix, R), 'non-version tag ignored');
  Expect(not ParseLatestReleaseJson('not json', cUpdateAssetSuffix, R), 'garbage ignored');
end;

procedure TestSha256;
var
  F: string;
begin
  Writeln('sha256');
  F := TPath.Combine(GTemp, 'abc.txt');
  TFile.WriteAllBytes(F, TEncoding.ASCII.GetBytes('abc'));
  Expect(FileSha256(F) = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'sha256("abc") matches the FIPS vector');
end;

procedure MakeZip(const AZip: string; const ANames, ATexts: array of string);
var
  Z: TZipFile;
  I: Integer;
begin
  Z := TZipFile.Create;
  try
    Z.Open(AZip, zmWrite);
    for I := 0 to High(ANames) do
      Z.Add(TEncoding.UTF8.GetBytes(ATexts[I]), ANames[I]);
  finally
    Z.Free;
  end;
end;

procedure TestExtract;
var
  Zip, Stage, Err: string;
begin
  Writeln('ExtractUpdate');
  Zip := TPath.Combine(GTemp, 'pkg.zip');
  Stage := TPath.Combine(GTemp, 'stage');
  MakeZip(Zip, ['MTN2.exe', 'plugins/mtn.ws/plugin.json'], ['new exe', 'new plugin']);
  Expect(ExtractUpdate(Zip, Stage, Err), 'extracts a package: ' + Err);
  Expect(ReadText(TPath.Combine(Stage, 'plugins\mtn.ws\plugin.json')) = 'new plugin',
    'nested files keep their folders');

  MakeZip(Zip, ['readme.txt'], ['x']);
  Expect(not ExtractUpdate(Zip, Stage, Err) and (Pos('MTN2.exe', Err) > 0),
    'package without MTN2.exe rejected');

  MakeZip(Zip, ['MTN2.exe', '../evil.txt'], ['x', 'y']);
  Expect(not ExtractUpdate(Zip, Stage, Err) and (Pos('unsafe', Err) > 0),
    'entry escaping the staging folder rejected');
  Expect(not TFile.Exists(TPath.Combine(GTemp, 'evil.txt')), 'nothing written outside');
end;

procedure PrepareApp(const AApp, AStage: string);
begin
  if TDirectory.Exists(AApp) then
    TDirectory.Delete(AApp, True);
  if TDirectory.Exists(AStage) then
    TDirectory.Delete(AStage, True);
  WriteText(TPath.Combine(AApp, 'MTN2.exe'), 'old exe');
  WriteText(TPath.Combine(AApp, 'plugins\mtn.ws\plugin.json'), 'old plugin');
  WriteText(TPath.Combine(AApp, 'plugins\mtn.7z\7z.dll'), 'user 7z');
  WriteText(TPath.Combine(AApp, 'keymap.json'), 'user keymap');
  WriteText(TPath.Combine(AStage, 'MTN2.exe'), 'new exe');
  WriteText(TPath.Combine(AStage, 'plugins\mtn.ws\plugin.json'), 'new plugin');
  WriteText(TPath.Combine(AStage, 'help\ru\index.md'), 'new help');
end;

procedure TestApply;
var
  App, Stage, Err: string;
begin
  Writeln('ApplyStagedUpdate');
  App := TPath.Combine(GTemp, 'app');
  Stage := TPath.Combine(GTemp, 'stage2');
  PrepareApp(App, Stage);
  Expect(ApplyStagedUpdate(Stage, App, Err), 'applies: ' + Err);
  Expect(ReadText(TPath.Combine(App, 'MTN2.exe')) = 'new exe', 'exe replaced');
  Expect(ReadText(TPath.Combine(App, 'MTN2.exe.old')) = 'old exe', 'old exe kept as .old');
  Expect(ReadText(TPath.Combine(App, 'plugins\mtn.ws\plugin.json')) = 'new plugin', 'nested replaced');
  Expect(ReadText(TPath.Combine(App, 'help\ru\index.md')) = 'new help', 'new file added');
  Expect(ReadText(TPath.Combine(App, 'plugins\mtn.7z\7z.dll')) = 'user 7z', '7z.dll untouched');
  Expect(ReadText(TPath.Combine(App, 'keymap.json')) = 'user keymap', 'user file untouched');
  Expect(not TDirectory.Exists(Stage), 'staging folder removed');

  Writeln('CleanupOldFiles');
  WriteText(TPath.Combine(App, 'notes.old'), 'user notes');
  WriteText(TPath.Combine(App, 'MTN2.exe.old7'), 'older leftover');
  CleanupOldFiles(App);
  Expect(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old')), 'X.old removed when X exists');
  Expect(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old7')), 'X.oldN removed too');
  Expect(not TFile.Exists(TPath.Combine(App, 'plugins\mtn.ws\plugin.json.old')), 'nested .old removed');
  Expect(TFile.Exists(TPath.Combine(App, 'notes.old')), 'unrelated *.old user file kept');
end;

procedure TestRollback;
var
  App, Stage, Err: string;
  Lock: TFileStream;
begin
  Writeln('ApplyStagedUpdate rollback');
  App := TPath.Combine(GTemp, 'app2');
  Stage := TPath.Combine(GTemp, 'stage3');
  PrepareApp(App, Stage);
  // An open handle without FILE_SHARE_DELETE blocks renaming this file.
  Lock := TFileStream.Create(TPath.Combine(App, 'plugins\mtn.ws\plugin.json'),
    fmOpenRead or fmShareDenyWrite);
  try
    Expect(not ApplyStagedUpdate(Stage, App, Err), 'a locked target fails the update: ' + Err);
  finally
    Lock.Free;
  end;
  Expect(ReadText(TPath.Combine(App, 'MTN2.exe')) = 'old exe', 'exe rolled back');
  Expect(ReadText(TPath.Combine(App, 'plugins\mtn.ws\plugin.json')) = 'old plugin', 'locked file intact');
  Expect(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old')), 'no .old left after rollback');
  Expect(not TFile.Exists(TPath.Combine(App, 'help\ru\index.md')), 'added file removed on rollback');
end;

procedure TestSchedule;
var
  S: TUpdateSettings;
  Now_: TDateTime;
begin
  Writeln('Check schedule');
  Now_ := EncodeDateTime(2026, 9, 25, 12, 0, 0, 0);
  S := DefaultUpdateSettings;
  Expect(UpdateCheckDue(S, Now_), 'never checked -> due');
  S.LastCheck := IncHour(Now_, -1);
  Expect(not UpdateCheckDue(S, Now_), 'checked an hour ago -> not due');
  S.LastCheck := IncHour(Now_, -25);
  Expect(UpdateCheckDue(S, Now_), 'checked yesterday -> due');
  S.LastCheck := IncDay(Now_, 3);
  Expect(UpdateCheckDue(S, Now_), 'clock moved back -> due');
  S.CheckOnStart := False;
  Expect(not UpdateCheckDue(S, Now_), 'disabled -> never due');
end;

procedure TestLiveGitHub;
var
  R: TUpdateRelease;
  Err: string;
begin
  Writeln('Live GitHub latest release');
  if not FetchLatestRelease(R, Err) then
  begin
    Writeln('  SKIP  ', Err);
    Exit;
  end;
  Expect(R.Version <> '', 'latest release has a version: ' + R.Tag);
  Expect(R.AssetName.EndsWith(cUpdateAssetSuffix), 'has a win64 package: ' + R.AssetName);
  Expect(Length(R.AssetSha256) = 64, 'GitHub publishes its sha256');
end;

begin
  GTemp := TPath.Combine(TPath.GetTempPath, 'mtn2-updater-test-' + IntToStr(Random(MaxInt)));
  ForceDirectories(GTemp);
  try
    try
      TestVersions;
      TestReleaseJson;
      TestSha256;
      TestExtract;
      TestApply;
      TestRollback;
      TestSchedule;
      TestLiveGitHub;
      Writeln('All Updater tests PASSED');
    except
      on E: Exception do
      begin
        Writeln('FAILED: ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    try
      TDirectory.Delete(GTemp, True);
    except
    end;
  end;
end.
