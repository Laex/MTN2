unit TestMovedPlugins;

{ Loads the libraries of the plugins that took their features out of the core
  (checksums, split, archive tools, multi-rename, list export, descriptions,
  thumbnails) through the real loader, with their own plugin.json, and checks
  that init and shutdown work and a second load after an unload works too. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMovedPlugins = class
  public
    [TearDown] procedure TearDown;
    [Test]
    [TestCase('checksums', 'mtn.checksums,ChecksumsPlugin')]
    [TestCase('splitfile', 'mtn.splitfile,SplitFilePlugin')]
    [TestCase('archivetools', 'mtn.archivetools,ArchiveToolsPlugin')]
    [TestCase('multirename', 'mtn.multirename,MultiRenamePlugin')]
    [TestCase('exportlist', 'mtn.exportlist,ExportListPlugin')]
    [TestCase('describe', 'mtn.describe,DescribePlugin')]
    [TestCase('thumbs', 'mtn.thumbs,ThumbsPlugin')]
    procedure TestPluginLoadsUnloadsAndLoadsAgain(const AId, ALibrary: string);
  end;

implementation

uses
  uTestPaths,
  System.SysUtils, System.Classes, System.IOUtils,
  uPlatformInfo, uPluginLoader;

function ManifestOf(const AId: string): string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../plugins/' + AId + '/plugin.json'));
  Result := ExpandFileName(Result);
end;

procedure TTestMovedPlugins.TearDown;
begin
  PluginLoader.OnLog := nil;
  PluginLoader.UnloadAll;
end;

procedure TTestMovedPlugins.TestPluginLoadsUnloadsAndLoadsAgain(const AId, ALibrary: string);
var
  Dll, Manifest, Root, Dir: string;
  Failed, Pass: Integer;
begin
  Dll := TPath.Combine(ExtractFilePath(ParamStr(0)), PlatformSharedLibName(ALibrary));
  Manifest := ManifestOf(AId);
  Assert.IsTrue(TFile.Exists(Dll), 'the plugin library is built next to the tests: ' + Dll);
  Assert.IsTrue(TFile.Exists(Manifest), 'the plugin manifest exists: ' + Manifest);

  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-moved-' + AId);
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  Dir := TPath.Combine(Root, AId);
  TDirectory.CreateDirectory(Dir);
  TFile.Copy(Dll, TPath.Combine(Dir, PlatformSharedLibName(ALibrary)), True);
  TFile.Copy(Manifest, TPath.Combine(Dir, 'plugin.json'), True);

  Failed := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      if not (AResult in [plrLoaded, plrSkippedHelperDll]) then
        Inc(Failed);
    end;

  for Pass := 1 to 2 do
  begin
    PluginLoader.LoadPluginsFrom(Root);
    Assert.IsTrue(PluginLoader.IsPluginLoaded(AId), AId + ' is loaded, pass ' + IntToStr(Pass));
    Assert.AreEqual(0, Failed, 'the loader reports no failure, pass ' + IntToStr(Pass));
    PluginLoader.UnloadAll;
    Assert.IsFalse(PluginLoader.IsPluginLoaded(AId), AId + ' is unloaded, pass ' + IntToStr(Pass));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMovedPlugins);

end.
