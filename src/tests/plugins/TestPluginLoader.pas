unit TestPluginLoader;

{ End-to-end test of the real DLL plugin loader: unlike TestPluginHostAbi.pas
  (which calls mtn_host_publish in-process, same binary), this test actually
  LoadLibrary()s a compiled plugin DLL (SamplePlugin.dpr, built next to this
  exe by run-tests.ps1) and verifies its registrations reach the real
  IVfsRegistry/IMenuRegistry/IKeymapRegistry.

  TPluginLoader.LoadPluginsFrom expects one subdirectory per plugin
  (<dir>\<plugin-id>\*.dll - see uPluginLoader.pas), so this test stages
  SamplePlugin.dll into such a layout under a scratch "plugins" folder next
  to the exe before loading it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginLoader = class
  public
    [Test] procedure TestLoadAndResolveSamplePlugin;
    [Test] procedure TestArchiveExtensionsFromManifest;
    [Test] procedure TestUnloadIsIdempotent;
    [Test] procedure TestCatalogLoadsOnDemand;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.TypInfo, System.IOUtils,
  uVfsTypes,
  uTextEncoding,
  uVfsRegistry,
  uPanelModel,
  uPanelPluginRegistry,
  uKeymap,
  uKeymapRegistry,
  uTerminalTypes,
  uThemeTypes,
  uDualPanelTypes,
  uDualPanelOverlays,
  uTopMenuBar,
  uMenuRegistry,
  uMessageBus,
  uPluginHostAbi,
  uVfsCdeclAdapter,
  uPluginLoader;

procedure StageSamplePluginIntoPluginDir(const APluginsRoot: string);
var
  SrcDll, DestDir, DestDll: string;
begin
  SrcDll := TPath.Combine(ExtractFilePath(ParamStr(0)), 'SamplePlugin.dll');
  if not TFile.Exists(SrcDll) then
    raise Exception.CreateFmt('SamplePlugin.dll not found next to the test exe: %s', [SrcDll]);

  DestDir := TPath.Combine(APluginsRoot, 'SamplePlugin');
  TDirectory.CreateDirectory(DestDir);
  DestDll := TPath.Combine(DestDir, 'SamplePlugin.dll');
  TFile.Copy(SrcDll, DestDll, True);
  // No plugin.json shipped with SamplePlugin - write one declaring an
  // archiveExtensions entry so TestArchiveExtensionsFromManifest below can
  // exercise uPluginLoader.RegisterManifestArchiveExtensions end-to-end.
  TFile.WriteAllText(TPath.Combine(DestDir, 'plugin.json'),
    '{"id":"SamplePlugin","abi":1,"archiveExtensions":["samplearchive"],"schemes":["sample"]}',
    TEncoding.UTF8);
end;

procedure TestLoadAndResolveSamplePlugin;
var
  PluginsRoot: string;
  Backend: IVirtualFileSystem;
  Resolved: Boolean;
  Loaded, Failed: Integer;
begin
  Loaded := 0;
  Failed := 0;
  PluginLoader.OnLog :=
    procedure(const AFileName: string; AResult: TPluginLoadResult; const AMessage: string)
    begin
      if AResult = plrLoaded then
        Inc(Loaded)
      else if AResult <> plrSkippedHelperDll then
        Inc(Failed);
      Writeln(Format('  [plugin] %s: %s (%s)', [ExtractFileName(AFileName),
        GetEnumName(TypeInfo(TPluginLoadResult), Ord(AResult)), AMessage]));
    end;

  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  StageSamplePluginIntoPluginDir(PluginsRoot);
  PluginLoader.LoadPluginsFrom(PluginsRoot);

  Assert.IsTrue(Loaded >= 1, 'Expected at least one plugin (SamplePlugin\SamplePlugin.dll) to load successfully');
  Assert.IsTrue(Failed = 0, 'No plugin load attempt should fail');

  Resolved := GlobalVfsRegistry.TryResolve('sample://test-file.txt', Backend);
  Assert.IsTrue(Resolved, 'sample:// should resolve to the plugin-registered VFS backend');
  Assert.IsTrue(Assigned(Backend), 'Resolved backend must not be nil');
  Assert.IsTrue(GlobalVfsRegistry.IsPluginOwned('sample://test-file.txt'),
    'sample:// is plugin-owned while loaded');

end;

procedure TestArchiveExtensionsFromManifest;
var
  Kind: TArchiveExtensionKind;
begin
  Assert.IsTrue(GlobalVfsRegistry.TryResolveArchiveKind('data.samplearchive', Kind),
    'plugin.json archiveExtensions must reach GlobalVfsRegistry on load');
  Assert.IsTrue(Kind = akSevenZip, 'plugin-declared archive extensions register as akSevenZip');
end;

procedure TestUnloadIsIdempotent;
var
  Kind: TArchiveExtensionKind;
begin
  PluginLoader.UnloadAll;
  Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('sample://test-file.txt'),
    'sample:// must not stay plugin-owned after UnloadAll');
  Assert.IsTrue(not GlobalVfsRegistry.TryResolveArchiveKind('data.samplearchive', Kind),
    'unloading the plugin must drop its archive extensions too');
  PluginLoader.UnloadAll; // must not raise on a second call
end;

procedure TestCatalogLoadsOnDemand;
var
  PluginsRoot: string;
  Backend: IVirtualFileSystem;
  Kind: TArchiveExtensionKind;
begin
  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  PluginLoader.CatalogPlugins(PluginsRoot);
  Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 0,
    'catalog must not load the DLL');

  Assert.IsTrue(PluginLoader.EnsureArchiveExtension('data.samplearchive'),
    'archive extension must load the catalogued plugin');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('sample://test-file.txt', Backend),
    'sample:// resolves after the on-demand load');
  Assert.IsTrue(GlobalVfsRegistry.TryResolveArchiveKind('data.samplearchive', Kind),
    'archive extension is registered by the loaded plugin');
  Assert.IsTrue(Kind = akSevenZip, 'on-demand load still registers akSevenZip');

  PluginLoader.UnloadAll;
  PluginLoader.CatalogPlugins(PluginsRoot);
  Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 0,
    'unload drops the module; catalog does not reload it');
  Assert.IsTrue(PluginLoader.EnsureScheme('sample'), 'scheme loads the catalogued plugin');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('sample://x', Backend),
    'sample:// resolves after EnsureScheme');
  PluginLoader.UnloadAll;
end;

{ TTestPluginLoader }

procedure TTestPluginLoader.TestLoadAndResolveSamplePlugin;
begin
  TestPluginLoader.TestLoadAndResolveSamplePlugin;
end;

procedure TTestPluginLoader.TestArchiveExtensionsFromManifest;
begin
  TestPluginLoader.TestArchiveExtensionsFromManifest;
end;

procedure TTestPluginLoader.TestUnloadIsIdempotent;
begin
  TestPluginLoader.TestUnloadIsIdempotent;
end;

procedure TTestPluginLoader.TestCatalogLoadsOnDemand;
begin
  TestPluginLoader.TestCatalogLoadsOnDemand;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginLoader);

end.
