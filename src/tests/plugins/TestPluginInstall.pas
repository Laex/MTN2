unit TestPluginInstall;

{ Installing and removing plugin folders: from a folder or a .zip, id taken from
  plugin.json, replace only on request, archives that leave the plugin folder refused. }

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Zip, uPluginInstall;

type
  [TestFixture]
  TTestPluginInstall = class
  private
    FRoot: string;
    FPlugins: string;
    function MakeSource(const AName, AId: string): string;
    function MakeZip(const ASource: string; const AExtraName: string = ''): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestInstallsFromFolderUnderItsManifestId;
    [Test] procedure TestInstallsFromZipWithTopFolder;
    [Test] procedure TestExistingIdNeedsReplace;
    [Test] procedure TestReplaceSwapsTheFiles;
    [Test] procedure TestZipWithEscapingPathIsRefused;
    [Test] procedure TestSourceWithoutManifestIsRefused;
    [Test] procedure TestUnsafeIdIsRefused;
    [Test] procedure TestMissingSourceIsReported;
    [Test] procedure TestRemoveDeletesTheFolder;
    [Test] procedure TestRemoveOfUnknownIdFails;
  end;

implementation

function TTestPluginInstall.MakeSource(const AName, AId: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TDirectory.CreateDirectory(Result);
  TFile.WriteAllText(TPath.Combine(Result, 'plugin.json'),
    '{"id":"' + AId + '","name":"Demo","version":"1.0"}', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(Result, 'data.txt'), AName, TEncoding.UTF8);
end;

function TTestPluginInstall.MakeZip(const ASource: string; const AExtraName: string): string;
var
  Zip: TZipFile;
  F: string;
begin
  Result := ASource + '.zip';
  Zip := TZipFile.Create;
  try
    Zip.Open(Result, zmWrite);
    for F in TDirectory.GetFiles(ASource) do
      Zip.Add(F, TPath.GetFileName(ASource) + '/' + TPath.GetFileName(F));
    if AExtraName <> '' then
      Zip.Add(TPath.Combine(ASource, 'data.txt'), AExtraName);
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

procedure TTestPluginInstall.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'mtn2-pi-' + TGUID.NewGuid.ToString);
  FPlugins := TPath.Combine(FRoot, 'plugins');
  TDirectory.CreateDirectory(FPlugins);
end;

procedure TTestPluginInstall.TearDown;
begin
  if TDirectory.Exists(FRoot) then
    TDirectory.Delete(FRoot, True);
end;

procedure TTestPluginInstall.TestInstallsFromFolderUnderItsManifestId;
var
  R: TPluginInstallResult;
begin
  R := InstallPlugin(MakeSource('srcname', 'demo.one'), FPlugins, False);
  Assert.AreEqual(Ord(pisOk), Ord(R.Status));
  Assert.AreEqual('demo.one', R.Id);
  Assert.IsFalse(R.Replaced);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FPlugins, 'demo.one\data.txt')));
end;

procedure TTestPluginInstall.TestInstallsFromZipWithTopFolder;
var
  R: TPluginInstallResult;
begin
  R := InstallPlugin(MakeZip(MakeSource('packed', 'demo.zip')), FPlugins, False);
  Assert.AreEqual(Ord(pisOk), Ord(R.Status));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FPlugins, 'demo.zip\plugin.json')));
end;

procedure TTestPluginInstall.TestExistingIdNeedsReplace;
var
  R: TPluginInstallResult;
begin
  InstallPlugin(MakeSource('a', 'same'), FPlugins, False);
  R := InstallPlugin(MakeSource('b', 'same'), FPlugins, False);
  Assert.AreEqual(Ord(pisExists), Ord(R.Status));
  Assert.AreEqual('a', TFile.ReadAllText(TPath.Combine(FPlugins, 'same\data.txt'), TEncoding.UTF8));
end;

procedure TTestPluginInstall.TestReplaceSwapsTheFiles;
var
  R: TPluginInstallResult;
begin
  InstallPlugin(MakeSource('a', 'same'), FPlugins, False);
  R := InstallPlugin(MakeSource('b', 'same'), FPlugins, True);
  Assert.AreEqual(Ord(pisOk), Ord(R.Status));
  Assert.IsTrue(R.Replaced);
  Assert.AreEqual('b', TFile.ReadAllText(TPath.Combine(FPlugins, 'same\data.txt'), TEncoding.UTF8));
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FPlugins, 'same.old')));
end;

procedure TTestPluginInstall.TestZipWithEscapingPathIsRefused;
var
  R: TPluginInstallResult;
begin
  R := InstallPlugin(MakeZip(MakeSource('evil', 'demo.evil'), '../escape.txt'), FPlugins, False);
  Assert.AreEqual(Ord(pisUnsafeArchive), Ord(R.Status));
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FPlugins, 'demo.evil')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, 'escape.txt')));
end;

procedure TTestPluginInstall.TestSourceWithoutManifestIsRefused;
var
  Dir: string;
  R: TPluginInstallResult;
begin
  Dir := TPath.Combine(FRoot, 'empty');
  TDirectory.CreateDirectory(Dir);
  R := InstallPlugin(Dir, FPlugins, False);
  Assert.AreEqual(Ord(pisNoManifest), Ord(R.Status));
end;

procedure TTestPluginInstall.TestUnsafeIdIsRefused;
var
  R: TPluginInstallResult;
begin
  R := InstallPlugin(MakeSource('bad', '..x'), FPlugins, False);
  Assert.AreEqual(Ord(pisBadId), Ord(R.Status));
  Assert.IsFalse(IsSafePluginId('a/b'));
  Assert.IsFalse(IsSafePluginId(''));
  Assert.IsTrue(IsSafePluginId('mtn.lua-2_x'));
end;

procedure TTestPluginInstall.TestMissingSourceIsReported;
var
  R: TPluginInstallResult;
begin
  R := InstallPlugin(TPath.Combine(FRoot, 'nothing'), FPlugins, False);
  Assert.AreEqual(Ord(pisSourceMissing), Ord(R.Status));
end;

procedure TTestPluginInstall.TestRemoveDeletesTheFolder;
var
  Detail: string;
begin
  InstallPlugin(MakeSource('a', 'gone'), FPlugins, False);
  Assert.IsTrue(RemovePluginFolder('gone', FPlugins, Detail));
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FPlugins, 'gone')));
end;

procedure TTestPluginInstall.TestRemoveOfUnknownIdFails;
var
  Detail: string;
begin
  Assert.IsFalse(RemovePluginFolder('nope', FPlugins, Detail));
  Assert.IsFalse(RemovePluginFolder('..', FPlugins, Detail));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginInstall);

end.
