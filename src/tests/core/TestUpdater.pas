unit TestUpdater;

{ uUpdater: version compare, GitHub release JSON, sha256, package extraction,
  the rename-to-.old swap with rollback, .old cleanup and the check schedule.
  Everything runs on temp folders; the one live GitHub call SKIPs offline. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUpdater = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestVersions;
    [Test] procedure TestReleaseJson;
    [Test] procedure TestSha256;
    [Test] procedure TestExtract;
    [Test] procedure TestApply;
    [Test] procedure TestRollback;
    [Test] procedure TestSchedule;
    [Test] procedure TestLiveGitHub;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip, System.DateUtils,
  uUpdater;

var
  GTemp: string;

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
  Assert.IsTrue(TryParseVersion('v0.3.1', M, N, P) and (M = 0) and (N = 3) and (P = 1), 'v0.3.1 parses');
  Assert.IsTrue(TryParseVersion('10.20.30', M, N, P) and (P = 30), 'plain 10.20.30 parses');
  Assert.IsTrue(not TryParseVersion('0.3', M, N, P), '0.3 rejected');
  Assert.IsTrue(not TryParseVersion('v0.3.1-beta', M, N, P), 'suffix rejected');
  Assert.IsTrue(not TryParseVersion('', M, N, P), 'empty rejected');
  Assert.IsTrue(CompareVersions('0.3.10', '0.3.9') > 0, '0.3.10 > 0.3.9 (numeric, not text)');
  Assert.IsTrue(CompareVersions('v1.0.0', '0.99.99') > 0, 'major wins');
  Assert.IsTrue(CompareVersions('0.3.1', 'v0.3.1') = 0, 'v prefix ignored');
  Assert.IsTrue(IsNewerVersion('0.3.2', '0.3.1'), '0.3.2 is newer than 0.3.1');
  Assert.IsTrue(not IsNewerVersion('0.3.1', '0.3.1'), 'same version is not newer');
  Assert.IsTrue(not IsNewerVersion('0.3.0', '0.3.1'), 'older is not newer');
  Assert.IsTrue(IsNewerVersion('0.3.1', ''), 'any version beats an unknown current one');
  Assert.IsTrue(not IsNewerVersion('garbage', '0.3.1'), 'unparsable candidate never offered');
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
  Assert.IsTrue(ParseLatestReleaseJson(cReleaseJson, cUpdateAssetSuffix, R), 'parses a normal release');
  Assert.IsTrue(R.Version = '0.3.2', 'version from tag');
  Assert.IsTrue(R.AssetName = 'MTN2-v0.3.2-win64.zip', 'picks the -win64.zip asset, not the first one');
  Assert.IsTrue(R.AssetSize = 21874456, 'asset size');
  Assert.IsTrue(R.AssetSha256 = '517ecd50149c1456318f589bd5cd22d7c3226e20507643827e80f6e5072c9ae0',
    'digest lowercased, sha256: prefix stripped');
  Assert.IsTrue(R.HtmlUrl.EndsWith('/v0.3.2'), 'release page url');
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '"draft":false', '"draft":true', []),
    cUpdateAssetSuffix, R), 'draft ignored');
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '"prerelease":false',
    '"prerelease":true', []), cUpdateAssetSuffix, R), 'prerelease ignored');
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, '-win64.zip', '-linux.tar.gz',
    [rfReplaceAll]), cUpdateAssetSuffix, R), 'no win64 package -> nothing to offer');
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, 'v0.3.2"', 'nightly"', []),
    cUpdateAssetSuffix, R), 'non-version tag ignored');
  Assert.IsTrue(not ParseLatestReleaseJson('not json', cUpdateAssetSuffix, R), 'garbage ignored');

  // Other packages of the same release, listed first, must not be taken for
  // the regular one -- even one whose name also ends in -win64.zip.
  Assert.IsTrue(ParseLatestReleaseJson(StringReplace(cReleaseJson, '"assets":[',
    '"assets":[{"name":"MTN2-v0.3.2-win64-portable.zip","size":1,' +
    '"browser_download_url":"https://x/portable.zip"},' +
    '{"name":"MTN2-v0.3.2-portable-win64.zip","size":2,' +
    '"browser_download_url":"https://x/portable2.zip"},', []), cUpdateAssetSuffix, R),
    'release with extra packages still parses');
  Assert.IsTrue(R.AssetName = 'MTN2-v0.3.2-win64.zip',
    'picks exactly MTN2-<tag>-win64.zip, not a portable package: ' + R.AssetName);
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, 'MTN2-v0.3.2-win64.zip',
    'MTN2-v0.3.2-portable-win64.zip', [rfReplaceAll]), cUpdateAssetSuffix, R),
    'only a portable package -> nothing to offer');
  Assert.IsTrue(not ParseLatestReleaseJson(StringReplace(cReleaseJson, 'MTN2-v0.3.2-win64.zip',
    'MTN2-v0.3.1-win64.zip', [rfReplaceAll]), cUpdateAssetSuffix, R),
    'a package named for another tag is not this release''s package');
end;

procedure TestSha256;
var
  F: string;
begin
  F := TPath.Combine(GTemp, 'abc.txt');
  TFile.WriteAllBytes(F, TEncoding.ASCII.GetBytes('abc'));
  Assert.IsTrue(FileSha256(F) = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
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
  Zip := TPath.Combine(GTemp, 'pkg.zip');
  Stage := TPath.Combine(GTemp, 'stage');
  MakeZip(Zip, ['MTN2.exe', 'plugins/mtn.ws/plugin.json'], ['new exe', 'new plugin']);
  Assert.IsTrue(ExtractUpdate(Zip, Stage, Err), 'extracts a package: ' + Err);
  Assert.IsTrue(ReadText(TPath.Combine(Stage, 'plugins\mtn.ws\plugin.json')) = 'new plugin',
    'nested files keep their folders');

  MakeZip(Zip, ['readme.txt'], ['x']);
  Assert.IsTrue(not ExtractUpdate(Zip, Stage, Err) and (Pos('MTN2.exe', Err) > 0),
    'package without MTN2.exe rejected');

  MakeZip(Zip, ['MTN2.exe', '../evil.txt'], ['x', 'y']);
  Assert.IsTrue(not ExtractUpdate(Zip, Stage, Err) and (Pos('unsafe', Err) > 0),
    'entry escaping the staging folder rejected');
  Assert.IsTrue(not TFile.Exists(TPath.Combine(GTemp, 'evil.txt')), 'nothing written outside');
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
  App := TPath.Combine(GTemp, 'app');
  Stage := TPath.Combine(GTemp, 'stage2');
  PrepareApp(App, Stage);
  Assert.IsTrue(ApplyStagedUpdate(Stage, App, Err), 'applies: ' + Err);
  Assert.IsTrue(ReadText(TPath.Combine(App, 'MTN2.exe')) = 'new exe', 'exe replaced');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'MTN2.exe.old')) = 'old exe', 'old exe kept as .old');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'plugins\mtn.ws\plugin.json')) = 'new plugin', 'nested replaced');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'help\ru\index.md')) = 'new help', 'new file added');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'plugins\mtn.7z\7z.dll')) = 'user 7z', '7z.dll untouched');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'keymap.json')) = 'user keymap', 'user file untouched');
  Assert.IsTrue(not TDirectory.Exists(Stage), 'staging folder removed');

  Writeln('CleanupOldFiles');
  WriteText(TPath.Combine(App, 'notes.old'), 'user notes');
  WriteText(TPath.Combine(App, 'MTN2.exe.old7'), 'older leftover');
  CleanupOldFiles(App);
  Assert.IsTrue(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old')), 'X.old removed when X exists');
  Assert.IsTrue(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old7')), 'X.oldN removed too');
  Assert.IsTrue(not TFile.Exists(TPath.Combine(App, 'plugins\mtn.ws\plugin.json.old')), 'nested .old removed');
  Assert.IsTrue(TFile.Exists(TPath.Combine(App, 'notes.old')), 'unrelated *.old user file kept');
end;

procedure TestRollback;
var
  App, Stage, Err: string;
  Lock: TFileStream;
begin
  App := TPath.Combine(GTemp, 'app2');
  Stage := TPath.Combine(GTemp, 'stage3');
  PrepareApp(App, Stage);
  // An open handle without FILE_SHARE_DELETE blocks renaming this file.
  Lock := TFileStream.Create(TPath.Combine(App, 'plugins\mtn.ws\plugin.json'),
    fmOpenRead or fmShareDenyWrite);
  try
    Assert.IsTrue(not ApplyStagedUpdate(Stage, App, Err), 'a locked target fails the update: ' + Err);
  finally
    Lock.Free;
  end;
  Assert.IsTrue(ReadText(TPath.Combine(App, 'MTN2.exe')) = 'old exe', 'exe rolled back');
  Assert.IsTrue(ReadText(TPath.Combine(App, 'plugins\mtn.ws\plugin.json')) = 'old plugin', 'locked file intact');
  Assert.IsTrue(not TFile.Exists(TPath.Combine(App, 'MTN2.exe.old')), 'no .old left after rollback');
  Assert.IsTrue(not TFile.Exists(TPath.Combine(App, 'help\ru\index.md')), 'added file removed on rollback');
end;

procedure TestSchedule;
var
  S: TUpdateSettings;
  Now_: TDateTime;
begin
  Now_ := EncodeDateTime(2026, 9, 25, 12, 0, 0, 0);
  S := DefaultUpdateSettings;
  Assert.IsTrue(UpdateCheckDue(S, Now_), 'never checked -> due');
  S.LastCheck := IncHour(Now_, -1);
  Assert.IsTrue(not UpdateCheckDue(S, Now_), 'checked an hour ago -> not due');
  S.LastCheck := IncHour(Now_, -25);
  Assert.IsTrue(UpdateCheckDue(S, Now_), 'checked yesterday -> due');
  S.LastCheck := IncDay(Now_, 3);
  Assert.IsTrue(UpdateCheckDue(S, Now_), 'clock moved back -> due');
  S.CheckOnStart := False;
  Assert.IsTrue(not UpdateCheckDue(S, Now_), 'disabled -> never due');
end;

procedure TestLiveGitHub;
var
  R: TUpdateRelease;
  Err: string;
begin
  if not FetchLatestRelease(R, Err) then
  begin
    Writeln('  SKIP  ', Err);
    Exit;
  end;
  Assert.IsTrue(R.Version <> '', 'latest release has a version: ' + R.Tag);
  Assert.IsTrue(SameText(R.AssetName, cUpdateAssetPrefix + R.Tag + cUpdateAssetSuffix),
    'has the regular win64 package: ' + R.AssetName);
  Assert.IsTrue(Length(R.AssetSha256) = 64, 'GitHub publishes its sha256');
end;

{ TTestUpdater }

procedure TTestUpdater.SetupFixture;
begin
  GTemp := TPath.Combine(TPath.GetTempPath, 'mtn2-updater-test-' + IntToStr(Random(MaxInt)));
  ForceDirectories(GTemp);
end;

procedure TTestUpdater.TearDownFixture;
begin
  try
    TDirectory.Delete(GTemp, True);
  except
  end;
end;

procedure TTestUpdater.TestVersions;
begin
  TestUpdater.TestVersions;
end;

procedure TTestUpdater.TestReleaseJson;
begin
  TestUpdater.TestReleaseJson;
end;

procedure TTestUpdater.TestSha256;
begin
  TestUpdater.TestSha256;
end;

procedure TTestUpdater.TestExtract;
begin
  TestUpdater.TestExtract;
end;

procedure TTestUpdater.TestApply;
begin
  TestUpdater.TestApply;
end;

procedure TTestUpdater.TestRollback;
begin
  TestUpdater.TestRollback;
end;

procedure TTestUpdater.TestSchedule;
begin
  TestUpdater.TestSchedule;
end;

procedure TTestUpdater.TestLiveGitHub;
begin
  TestUpdater.TestLiveGitHub;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUpdater);

end.
