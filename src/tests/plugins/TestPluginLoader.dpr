program TestPluginLoader;

{$APPTYPE CONSOLE}

{ End-to-end test of the real DLL plugin loader: unlike TestPluginHostAbi.dpr
  (which calls mtn_host_publish in-process, same binary), this test actually
  LoadLibrary()s a compiled plugin DLL (SamplePlugin.dpr, built next to this
  exe by run-tests.ps1) and verifies its registrations reach the real
  IVfsRegistry/IMenuRegistry/IKeymapRegistry.

  TPluginLoader.LoadPluginsFrom expects one subdirectory per plugin
  (<dir>\<plugin-id>\*.dll — see uPluginLoader.pas), so this test stages
  SamplePlugin.dll into such a layout under a scratch "plugins" folder next
  to the exe before loading it. }

uses
  System.SysUtils, System.Classes, System.TypInfo, System.IOUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uVfsRegistry in '..\..\Core\uVfsRegistry.pas',
  uPanelModel in '..\..\Core\uPanelModel.pas',
  uPanelPluginRegistry in '..\..\Core\uPanelPluginRegistry.pas',
  uKeymap in '..\..\Core\uKeymap.pas',
  uKeymapRegistry in '..\..\Core\uKeymapRegistry.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelOverlays in '..\..\Core\uDualPanelOverlays.pas',
  uTopMenuBar in '..\..\Core\uTopMenuBar.pas',
  uMenuRegistry in '..\..\Core\uMenuRegistry.pas',
  uMessageBus in '..\..\Core\uMessageBus.pas',
  uPluginHostAbi in '..\..\Core\uPluginHostAbi.pas',
  uVfsCdeclAdapter in '..\..\Core\uVfsCdeclAdapter.pas',
  uPluginLoader in '..\..\Core\uPluginLoader.pas';

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
  // No plugin.json shipped with SamplePlugin — write one declaring an
  // archiveExtensions entry so TestArchiveExtensionsFromManifest below can
  // exercise uPluginLoader.RegisterManifestArchiveExtensions end-to-end.
  TFile.WriteAllText(TPath.Combine(DestDir, 'plugin.json'),
    '{"id":"SamplePlugin","abi":1,"archiveExtensions":["samplearchive"]}',
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

  Assert(Loaded >= 1, 'Expected at least one plugin (SamplePlugin\SamplePlugin.dll) to load successfully');
  Assert(Failed = 0, 'No plugin load attempt should fail');

  Resolved := GlobalVfsRegistry.TryResolve('sample://test-file.txt', Backend);
  Assert(Resolved, 'sample:// should resolve to the plugin-registered VFS backend');
  Assert(Assigned(Backend), 'Resolved backend must not be nil');
  Assert(GlobalVfsRegistry.IsPluginOwned('sample://test-file.txt'),
    'sample:// is plugin-owned while loaded');

  Writeln('OK: TestLoadAndResolveSamplePlugin passed');
end;

procedure TestArchiveExtensionsFromManifest;
var
  Kind: TArchiveExtensionKind;
begin
  Assert(GlobalVfsRegistry.TryResolveArchiveKind('data.samplearchive', Kind),
    'plugin.json archiveExtensions must reach GlobalVfsRegistry on load');
  Assert(Kind = akSevenZip, 'plugin-declared archive extensions register as akSevenZip');
  Writeln('OK: TestArchiveExtensionsFromManifest passed');
end;

procedure TestUnloadIsIdempotent;
var
  Kind: TArchiveExtensionKind;
begin
  PluginLoader.UnloadAll;
  Assert(not GlobalVfsRegistry.IsPluginOwned('sample://test-file.txt'),
    'sample:// must not stay plugin-owned after UnloadAll');
  Assert(not GlobalVfsRegistry.TryResolveArchiveKind('data.samplearchive', Kind),
    'unloading the plugin must drop its archive extensions too');
  PluginLoader.UnloadAll; // must not raise on a second call
  Writeln('OK: TestUnloadIsIdempotent passed');
end;

begin
  try
    TestLoadAndResolveSamplePlugin;
    TestArchiveExtensionsFromManifest;
    TestUnloadIsIdempotent;
    Writeln('All PluginLoader tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
