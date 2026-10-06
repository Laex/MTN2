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
    [Test] procedure TestOverridesNeedAllowList;
    [Test] procedure TestCommandApiFromNativePlugin;
    [Test] procedure TestDisabledPluginIsNotLoaded;
    [Test] procedure TestOverridePermissionCanBeChangedAtRuntime;
    [Test] procedure TestLoadOrderFollowsTheUsersList;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.TypInfo, System.IOUtils, System.UITypes,
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
  uCommandRegistry,
  uDocumentProviders,
  uPluginUi,
  uPluginSettings,
  uPluginChrome,
  uDialogTypes,
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
  Assert.IsTrue(Kind = akPluginScheme, 'plugin-declared archive extensions register as akPluginScheme');
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
  Assert.IsTrue(Kind = akPluginScheme, 'on-demand load still registers akPluginScheme');

  PluginLoader.UnloadAll;
  PluginLoader.CatalogPlugins(PluginsRoot);
  Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 0,
    'unload drops the module; catalog does not reload it');
  Assert.IsTrue(PluginLoader.EnsureScheme('sample'), 'scheme loads the catalogued plugin');
  Assert.IsTrue(GlobalVfsRegistry.TryResolve('sample://x', Backend),
    'sample:// resolves after EnsureScheme');
  PluginLoader.UnloadAll;
end;

procedure TestCommandApiFromNativePlugin;
var
  PluginsRoot, Redirect, Answers, Configured, SettingValue, SettingsDir: string;
  Ran: Integer;
  Sub, DialogSub, ConfigSub: ISubscription;
  Pending: TProc<string, string>;
begin
  Ran := 0;
  Answers := '';
  Configured := '';
  SettingsDir := TPath.Combine(TPath.GetTempPath, 'mtn2-loader-settings');
  TDirectory.CreateDirectory(SettingsDir);
  SetPluginSettingsDirectory(SettingsDir);
  ConfigSub := MessageBus.Subscribe('sample.configured',
    procedure(const ATopic: string; const APayload: TObject)
    begin
      Configured := Configured + TPluginPayload(APayload).Json + ';';
    end);
  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  PluginLoader.UnloadAll;
  StageSamplePluginIntoPluginDir(PluginsRoot);
  Sub :=MessageBus.Subscribe('sample.ran',
    procedure(const ATopic: string; const APayload: TObject)
    begin
      Inc(Ran);
    end);
  DialogSub := MessageBus.Subscribe('sample.dialog.answer',
    procedure(const ATopic: string; const APayload: TObject)
    begin
      Answers := Answers + TPluginPayload(APayload).Json + ';';
    end);
  try
    PluginLoader.LoadPluginsFrom(PluginsRoot);
    Assert.IsTrue(CommandRegistry.HasCommand('sample.hello'),
      'plugin command registered over the ABI');
    Assert.IsTrue(CommandRegistry.TryExecute('sample.hello') and (Ran = 1),
      'plugin command runs the plugin callback');
    Assert.IsTrue(TryRunBoundCommand(vkF12, [ssCtrl, ssAlt]) and (Ran = 2),
      'RegisterKeyBinding on a plugin command binds the chord');
    Assert.IsTrue(CommandRegistry.TryIntercept('Wipe', 'key'),
      'hook handles Wipe from the keyboard');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Wipe', 'menu'),
      'hook passes the menu item');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Copy', 'key'),
      'other commands are not hooked');

    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x/a.samplehandled', True, Redirect) =
      dokHandled, 'provider handles a file itself');
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x/a.SAMPLEDOC', True, Redirect) =
      dokRedirect, 'provider redirects the viewer (extension is case-insensitive)');
    Assert.IsTrue(Redirect = 'sample:///redirected.txt', 'redirect URI comes back from the plugin');
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x/a.sampledoc', False, Redirect) = dokPass,
      'the plugin lets the built-in editor have it');
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x/a.txt', True, Redirect) = dokPass,
      'other extensions are not offered');

    Assert.IsTrue(PanelPluginRegistry.TryActivate('sample:///', 'sample:///a.take', False),
      'the plugin takes the activation of its rows');
    Assert.IsTrue(not PanelPluginRegistry.TryActivate('sample:///', 'sample:///a.take', True),
      'the plugin lets a directory row through');
    Assert.IsTrue(not PanelPluginRegistry.TryActivate('file:///C:/', 'file:///C:/a.take', False),
      'the plugin is asked for its own scheme only');
    Assert.IsTrue(PluginFBarLabel(vkF12, [ssCtrl, ssAlt]) = 'Hello',
      'the command caption set over the ABI labels the bound chord');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'sample-status',
      'the status segment set over the ABI');

    Assert.IsTrue(PluginSettings.HasConfigure('SamplePlugin'),
      'the plugin registered a settings handler');
    Assert.IsTrue(PluginSettings.TryConfigure('SamplePlugin') and (Configured = 'fast;'),
      'the handler stored and read a setting over the ABI: ' + Configured);
    Assert.IsTrue(PluginSettings.TryGetValue('SamplePlugin', 'mode', SettingValue) and
      (SettingValue = 'fast'), 'the host holds the value the plugin stored');

    // A plugin dialog: the host stub keeps the answer callback, the user
    // "presses OK" after the plugin command has returned.
    SetPluginDialogHost(
      function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
      begin
        Pending := AOnCommand;
        Result := True;
      end);
    Assert.IsTrue(CommandRegistry.TryExecute('sample.dialog') and Assigned(Pending),
      'the plugin asked the host for a dialog over the ABI');
    Pending('ok', '{}');
    Assert.IsTrue(Answers = 'ok;', 'the answer reaches the plugin callback: ' + Answers);

    PluginLoader.UnloadAll;
    Pending('ok', '{}');
    Assert.IsTrue(Answers = 'ok;', 'an answer after unload does not reach the plugin');
    Assert.IsTrue(DocumentProviders.TryOpen('file:///C:/x/a.samplehandled', True, Redirect) =
      dokPass, 'unload drops the provider');
    Assert.IsTrue(not PanelPluginRegistry.TryActivate('sample:///', 'sample:///a.take', False),
      'unload drops the activation handler');
    Assert.IsTrue(Length(PluginChrome.StatusSegments) = 0, 'unload drops the status segment');
    Assert.IsTrue(PluginFBarLabel(vkF12, [ssCtrl, ssAlt]) = '', 'unload drops the caption');
    Assert.IsTrue(not CommandRegistry.HasCommand('sample.hello'),
      'unload drops the plugin command');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Wipe', 'key'), 'unload drops the hook');
    Assert.IsTrue(not TryRunBoundCommand(vkF12, [ssCtrl, ssAlt]), 'unload drops the chord');
  finally
    SetPluginDialogHost(nil);
    ConfigSub.Unsubscribe;
    SetPluginSettingsDirectory('');
    DialogSub.Unsubscribe;
    Sub.Unsubscribe;
    PluginLoader.UnloadAll;
  end;
end;

procedure TestOverridesNeedAllowList;
var
  PluginsRoot: string;
  Kind: TArchiveExtensionKind;
  Scheme: string;
begin
  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  PluginLoader.UnloadAll;
  StageSamplePluginIntoPluginDir(PluginsRoot);
  TFile.WriteAllText(TPath.Combine(PluginsRoot, 'SamplePlugin\plugin.json'),
    '{"id":"SamplePlugin","abi":1,"archiveExtensions":["samplearchive"],' +
    '"schemes":["sample"],"overrides":["sample",".samplearchive"]}', TEncoding.UTF8);
  try
    PluginLoader.SetOverrideAllowList([]);
    PluginLoader.LoadPluginsFrom(PluginsRoot);
    Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 1, 'plugin loads without a grant');
    Assert.IsTrue(not GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'),
      'manifest overrides stay inert when the plugin is not in the allow list');
    PluginLoader.UnloadAll;

    PluginLoader.SetOverrideAllowList(['SamplePlugin']);
    PluginLoader.LoadPluginsFrom(PluginsRoot);
    Assert.IsTrue(GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'),
      'allowed plugin holds its scheme override');
    Assert.IsTrue(GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', '.samplearchive'),
      'allowed plugin holds its extension override');
    Assert.IsTrue(GlobalVfsRegistry.TryResolveArchive('x.samplearchive', Kind, Scheme) and
      (Kind = akPluginScheme) and (Scheme = 'sample'),
      'archive extension navigates into the first scheme the manifest declares');
    PluginLoader.UnloadAll;
    Assert.IsTrue(not GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'),
      'unload drops the grant');

    PluginLoader.CatalogPlugins(PluginsRoot);
    Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 1,
      'cataloguing loads an allowed override plugin right away');
  finally
    PluginLoader.UnloadAll;
    PluginLoader.SetOverrideAllowList([]);
    StageSamplePluginIntoPluginDir(PluginsRoot);
  end;
end;

procedure TestDisabledPluginIsNotLoaded;
var
  PluginsRoot: string;
begin
  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  PluginLoader.UnloadAll;
  StageSamplePluginIntoPluginDir(PluginsRoot);
  try
    PluginLoader.SetDisabledPlugins(['SamplePlugin']);
    PluginLoader.LoadPluginsFrom(PluginsRoot);
    Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 0, 'a disabled plugin is not loaded');
    PluginLoader.CatalogPlugins(PluginsRoot);
    PluginLoader.EnsureAll;
    Assert.IsTrue(Length(PluginLoader.LoadedPluginIds) = 0, 'nor by the lazy triggers');
    Assert.IsTrue(not PluginLoader.EnsureScheme('sample'), 'its scheme does not load it');
    Assert.IsTrue(PluginLoader.IsPluginDisabled('sampleplugin'), 'disabled, case-insensitive');

    Assert.IsTrue(PluginLoader.SetPluginEnabled('SamplePlugin', True), 'switch on');
    Assert.IsTrue(PluginLoader.IsPluginLoaded('SamplePlugin'), 'switching on loads it now');
    Assert.IsTrue(CommandRegistry.HasCommand('sample.hello'), 'its registrations are live');
    Assert.IsTrue(Length(PluginLoader.DisabledPlugins) = 0, 'the disabled list is empty again');

    Assert.IsTrue(PluginLoader.SetPluginEnabled('SamplePlugin', False), 'switch off');
    Assert.IsTrue(not PluginLoader.IsPluginLoaded('SamplePlugin'), 'switching off unloads it now');
    Assert.IsTrue(not CommandRegistry.HasCommand('sample.hello'), 'its registrations are gone');
    Assert.IsTrue(not GlobalVfsRegistry.IsPluginOwned('sample://x'), 'its scheme is gone');
    Assert.IsTrue(PluginLoader.IsPluginDisabled('SamplePlugin'), 'and it stays off');
    Assert.IsTrue(not PluginLoader.SetPluginEnabled('NoSuchPlugin', True), 'unknown id');
  finally
    PluginLoader.UnloadAll;
    PluginLoader.SetDisabledPlugins([]);
  end;
end;

procedure TestOverridePermissionCanBeChangedAtRuntime;
var
  PluginsRoot: string;
begin
  PluginsRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-test');
  PluginLoader.UnloadAll;
  StageSamplePluginIntoPluginDir(PluginsRoot);
  try
    PluginLoader.SetOverrideAllowList([]);
    PluginLoader.CatalogPlugins(PluginsRoot);
    Assert.IsTrue(Length(PluginLoader.PluginOverrides('SamplePlugin')) = 0,
      'the plain sample manifest asks for no replacement');
    Assert.IsTrue(not PluginLoader.SetPluginOverrideAllowed('SamplePlugin', True),
      'a plugin that asks for nothing cannot be granted anything');

    TFile.WriteAllText(TPath.Combine(PluginsRoot, 'SamplePlugin\plugin.json'),
      '{"id":"SamplePlugin","abi":1,"schemes":["sample"],"overrides":["sample"]}', TEncoding.UTF8);
    PluginLoader.CatalogPlugins(PluginsRoot);
    Assert.IsTrue(PluginLoader.PluginOverrides('SamplePlugin')[0] = 'sample', 'the manifest list');
    Assert.IsTrue(PluginLoader.EnsureScheme('sample'), 'loaded on demand');
    Assert.IsTrue(not GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'), 'no grant yet');

    Assert.IsTrue(PluginLoader.SetPluginOverrideAllowed('SamplePlugin', True), 'grant');
    Assert.IsTrue(PluginLoader.IsPluginLoaded('SamplePlugin'), 'the plugin is reloaded at once');
    Assert.IsTrue(GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'),
      'the reloaded plugin holds the grant');
    Assert.IsTrue((Length(PluginLoader.OverrideAllowList) = 1) and
      PluginLoader.IsOverrideGranted('SamplePlugin'), 'the allow list');

    Assert.IsTrue(PluginLoader.SetPluginOverrideAllowed('SamplePlugin', False), 'take it back');
    Assert.IsTrue(PluginLoader.IsPluginLoaded('SamplePlugin') and
      not GlobalVfsRegistry.IsOverrideGranted('SamplePlugin', 'sample'),
      'reloaded without the grant');
    Assert.IsTrue(Length(PluginLoader.OverrideAllowList) = 0, 'the allow list is empty again');
  finally
    PluginLoader.UnloadAll;
    PluginLoader.SetOverrideAllowList([]);
    StageSamplePluginIntoPluginDir(PluginsRoot);
  end;
end;

{ TTestPluginLoader }

procedure TTestPluginLoader.TestOverridePermissionCanBeChangedAtRuntime;
begin
  TestPluginLoader.TestOverridePermissionCanBeChangedAtRuntime;
end;

procedure TTestPluginLoader.TestDisabledPluginIsNotLoaded;
begin
  TestPluginLoader.TestDisabledPluginIsNotLoaded;
end;

procedure TTestPluginLoader.TestOverridesNeedAllowList;
begin
  TestPluginLoader.TestOverridesNeedAllowList;
end;

procedure TestLoadOrder;
var
  Root, Id: string;
  Ids: TArray<string>;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-order-' + IntToStr(Random(MaxInt)));
  try
    for Id in ['aaa', 'bbb', 'ccc'] do
    begin
      TDirectory.CreateDirectory(TPath.Combine(Root, Id));
      TFile.WriteAllText(TPath.Combine(Root, Id + '\plugin.json'),
        '{"id":"' + Id + '","abi":2}', TEncoding.UTF8);
    end;
    PluginLoader.SetPluginOrder([]);
    PluginLoader.CatalogPlugins(Root);
    Assert.AreEqual('aaa,bbb,ccc', string.Join(',', PluginLoader.CatalogPluginIds), 'folder order by default');

    PluginLoader.SetPluginOrder(['CCC', 'aaa']);
    PluginLoader.CatalogPlugins(Root);
    Assert.AreEqual('ccc,aaa,bbb', string.Join(',', PluginLoader.CatalogPluginIds),
      'listed plugins first (case-insensitive), the rest after them');

    PluginLoader.SetPluginOrder(['gone', 'bbb']);
    PluginLoader.CatalogPlugins(Root);
    Assert.AreEqual('bbb,aaa,ccc', string.Join(',', PluginLoader.CatalogPluginIds),
      'an id with no plugin is ignored');

    Assert.IsTrue(PluginLoader.MovePlugin('aaa', 1), 'moved down');
    Assert.AreEqual('bbb,ccc,aaa', string.Join(',', PluginLoader.CatalogPluginIds), 'the new order');
    Assert.IsFalse(PluginLoader.MovePlugin('aaa', 1), 'the last one cannot go down');
    Assert.IsFalse(PluginLoader.MovePlugin('bbb', -1), 'the first one cannot go up');
    Assert.IsFalse(PluginLoader.MovePlugin('nope', 1), 'an unknown id');
    Assert.IsTrue(PluginLoader.MovePlugin('aaa', -2), 'moved up by two');
    Assert.AreEqual('aaa,bbb,ccc', string.Join(',', PluginLoader.CatalogPluginIds), 'back at the top');

    // The move is what a restart reads back.
    PluginLoader.MovePlugin('aaa', 2);
    Ids := PluginLoader.CatalogPluginIds;
    PluginLoader.SetPluginOrder(Ids);
    PluginLoader.CatalogPlugins(Root);
    Assert.AreEqual('bbb,ccc,aaa', string.Join(',', PluginLoader.CatalogPluginIds), 'the order survives a re-catalog');
  finally
    PluginLoader.SetPluginOrder([]);
    PluginLoader.UnloadAll;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

procedure TTestPluginLoader.TestCommandApiFromNativePlugin;
begin
  TestPluginLoader.TestCommandApiFromNativePlugin;
end;

procedure TTestPluginLoader.TestLoadOrderFollowsTheUsersList;
begin
  TestLoadOrder;
end;

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
