unit TestSamplePlugins;

{ Loads the demo plugins of samples\plugins (built by samples\build-samples.ps1
  into samples\.build) through the real loader and checks what they register.
  A sample that has not been built is skipped, so the group still runs on a
  machine without the C++, Rust, Go or Delphi toolchain. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSamplePlugins = class
  public
    [Test] procedure TestCppOperationCounter;
    [Test] procedure TestRustCsvViewer;
    [Test] procedure TestGoJsonViewer;
    [Test] procedure TestGoWasmSafeDelete;
    [Test] procedure TestDelphiNotes;
    [Test] procedure TestWatCounter;
    [Test] procedure TestWasiIsOptIn;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  Winapi.Windows,
  uCommandRegistry, uDocumentProviders, uPluginChrome, uPluginUi, uDialogTypes,
  uPluginLoader, uPluginSettings, uWasmPluginHost;

var
  GPending: TProc<string, string>;
  GDialogTitle: string;

function BuiltSample(const AId: string): string;
begin
  Result := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\samples\.build\' + AId));
end;

procedure InstallDialogHost;
begin
  GPending := nil;
  GDialogTitle := '';
  SetPluginDialogHost(
    function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
    begin
      GDialogTitle := ADecl.Title;
      GPending := AOnCommand;
      Result := True;
    end);
end;

function StageAndLoad(const AId: string): Boolean;
var
  Dir, Root, Target: string;
  F: string;
begin
  Result := False;
  Dir := BuiltSample(AId);
  if not TDirectory.Exists(Dir) then
    Exit;
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-' + AId);
  if TDirectory.Exists(Root) then
    try
      TDirectory.Delete(Root, True);
    except
      // A module that cannot be unloaded (Go) keeps its folder busy.
    end;
  Target := TPath.Combine(Root, AId);
  TDirectory.CreateDirectory(Target);
  for F in TDirectory.GetFiles(Dir) do
    try
      TFile.Copy(F, TPath.Combine(Target, ExtractFileName(F)), True);
    except
      // Already in place and mapped by a previous test.
    end;
  PluginLoader.UnloadAll;
  PluginLoader.LoadPluginsFrom(Root);
  Result := PluginLoader.IsPluginLoaded(AId);
end;

// A fresh folder for the settings files of a test, so a developer's own
// plugin settings never leak into the checks.
function ScratchSettings(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-settings-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
end;

function WriteTemp(const AName, AText: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-' + AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function FileUri(const APath: string): string;
begin
  Result := 'file:///' + StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

procedure TTestSamplePlugins.TestCppOperationCounter;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.cpp')) then
    Assert.Pass('SKIP: mtn.demo.cpp is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.cpp'), 'the C++ plugin loads');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Copy', 'key'),
      'the hook only observes: the built-in Copy still runs');
    CommandRegistry.TryIntercept('Delete', 'menu');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Ops: 2',
      'the status segment counts the commands: ' + string.Join(',', PluginChrome.StatusSegments));
    Assert.IsTrue(PluginFBarLabel(vkF10, [ssCtrl, ssAlt]) = 'Stats', 'the bar caption');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.cpp.stats') and (GDialogTitle = 'Operations'),
      'the stats command shows its dialog');
  finally
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestRustCsvViewer;
var
  Csv, Redirect, Text: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.rs')) then
    Assert.Pass('SKIP: mtn.demo.rs is not built (run samples\build-samples.ps1)');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.rs'), 'the Rust plugin loads');
    Csv := WriteTemp('table.csv', 'name;qty'#13#10'ap;1'#13#10'banana;20'#13#10);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Csv), True, Redirect) = dokRedirect,
      'F3 on a .csv is redirected');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('banana | 20', Text) > 0, 'the table is aligned: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Csv), False, Redirect) = dokPass,
      'F4 is left to the built-in editor');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('plain.txt', 'x')), True, Redirect) = dokPass,
      'other files are not offered');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestGoJsonViewer;
var
  Json, Redirect, Text: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go')) then
    Assert.Pass('SKIP: mtn.demo.go is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  SetPluginSettingsDirectory(ScratchSettings('go'));
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.go'), 'the Go plugin loads');
    Json := WriteTemp('data.json', '{"a":1,"b":[true,null]}');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Json), True, Redirect) = dokRedirect,
      'F3 on a .json is redirected');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('  "a": 1,', Text) > 0, 'the JSON is indented: ' + Text);
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(WriteTemp('bad.json', '{oops')), True, Redirect) = dokPass,
      'invalid JSON is left to the built-in viewer');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.go.info') and (GDialogTitle = 'Go plugin'),
      'the info command shows its dialog');
    // Settings: the indent width.
    Assert.IsTrue(PluginSettings.HasConfigure('mtn.demo.go'), 'the plugin has settings');
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.go') and
      (GDialogTitle = 'JSON viewer settings'), 'the settings dialog opens');
    GPending('ok', '{"indent":"4"}');
    Assert.IsTrue(DocumentProviders.TryOpen(FileUri(Json), True, Redirect) = dokRedirect, 'redirect again');
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('    "a": 1,', Text) > 0, 'the stored indent applies: ' + Text);
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.go'), 'a second settings dialog');
    GPending('ok', '{"indent":"99"}');
    DocumentProviders.TryOpen(FileUri(Json), True, Redirect);
    Text := TFile.ReadAllText(StringReplace(Copy(Redirect, 9, MaxInt), '/', '\', [rfReplaceAll]),
      TEncoding.UTF8);
    Assert.IsTrue(Pos('    "a": 1,', Text) > 0, 'an out-of-range value is not stored');
    Assert.IsTrue(Pos('Go: go', string.Join(',', PluginChrome.StatusSegments)) = 1,
      'the Go runtime version in the status line');
    // The runtime cannot be torn down: switching the plugin off keeps the module.
    PluginLoader.UnloadAll;
    Assert.IsTrue(not CommandRegistry.HasCommand('demo.go.info'), 'registrations are gone after unload');
    Assert.IsTrue(StageAndLoad('mtn.demo.go') and CommandRegistry.HasCommand('demo.go.info'),
      'the plugin loads again after being unloaded');
  finally
    SetPluginSettingsDirectory('');
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestGoWasmSafeDelete;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go.wasm')) then
    Assert.Pass('SKIP: mtn.demo.go.wasm is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  InstallDialogHost;
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.go.wasm'), 'the Go WASM plugin loads with WASI');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Safe delete: on', 'status segment');
    Assert.IsTrue(CommandRegistry.TryIntercept('DeletePermanent', 'key'),
      'permanent delete is blocked');
    Assert.IsTrue(GDialogTitle = 'Safe delete', 'and the plugin explains why');
    GDialogTitle := '';
    Assert.IsTrue(CommandRegistry.TryIntercept('Wipe', 'menu'), 'Wipe is blocked too');
    Assert.IsTrue(not CommandRegistry.TryIntercept('Delete', 'key'), 'the recycle-bin Delete is not');
    GPending('ok', '{}');
    Assert.IsTrue(CommandRegistry.TryIntercept('Wipe', 'key'),
      'the guest is still alive after the answer reached it');
  finally
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestDelphiNotes;
var
  Home, OldHome, NotesPath, OtherFile: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.pas')) then
    Assert.Pass('SKIP: mtn.demo.pas is not built (run samples\build-samples.ps1)');
  InstallDialogHost;
  OldHome := GetEnvironmentVariable('USERPROFILE');
  Home := TPath.Combine(TPath.GetTempPath, 'mtn2-sample-home');
  TDirectory.CreateDirectory(Home);
  NotesPath := TPath.Combine(Home, 'mtn2-notes.txt');
  if TFile.Exists(NotesPath) then
    TFile.Delete(NotesPath);
  SetEnvironmentVariable('USERPROFILE', PChar(Home));
  SetPluginSettingsDirectory(ScratchSettings('pas'));
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.pas'), 'the Delphi plugin loads');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 0', 'no notes yet');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note') and (GDialogTitle = 'Quick note'),
      'the note command shows its dialog');
    GPending('ok', '{"note":"buy milk"}');
    Assert.IsTrue(TFile.Exists(NotesPath) and (Pos('buy milk', TFile.ReadAllText(NotesPath)) > 0),
      'the typed note is written to the notes file');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 1', 'the count follows');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note'), 'a second dialog');
    GPending('cancel', '{"note":"ignored"}');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 1', 'Cancel adds nothing');

    // Settings: another notes file.
    Assert.IsTrue(PluginSettings.HasConfigure('mtn.demo.pas'), 'the plugin has settings');
    Assert.IsTrue(PluginSettings.TryConfigure('mtn.demo.pas') and (GDialogTitle = 'Notes settings'),
      'the settings dialog opens');
    OtherFile := TPath.Combine(Home, 'other-notes.txt');
    if TFile.Exists(OtherFile) then
      TFile.Delete(OtherFile);
    GPending('ok', '{"file":"' + StringReplace(OtherFile, '\', '\\', [rfReplaceAll]) + '"}');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Notes: 0',
      'the count follows the chosen file');
    Assert.IsTrue(CommandRegistry.TryExecute('demo.pas.note'), 'a note dialog');
    GPending('ok', '{"note":"to the other file"}');
    Assert.IsTrue(TFile.Exists(OtherFile) and (Pos('to the other file', TFile.ReadAllText(OtherFile)) > 0),
      'the note goes to the chosen file');
  finally
    SetPluginSettingsDirectory('');
    SetEnvironmentVariable('USERPROFILE', PChar(OldHome));
    SetPluginDialogHost(nil);
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestWatCounter;
var
  Id: string;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.wat')) then
    Assert.Pass('SKIP: mtn.demo.wat is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  try
    Assert.IsTrue(StageAndLoad('mtn.demo.wat'), 'the WAT plugin loads');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 0', 'initial status');
    Assert.IsTrue(CommandRegistry.TryMatchBinding(vkF7, [ssCtrl, ssAlt], Id) and (Id = 'demo.wat.count'),
      'the guest bound its chord');
    Assert.IsTrue(PluginFBarLabel(vkF7, [ssCtrl, ssAlt]) = 'Count', 'the bar caption');
    Assert.IsTrue(TryRunBoundCommand(vkF7, [ssCtrl, ssAlt]) and TryRunBoundCommand(vkF7, [ssCtrl, ssAlt]),
      'the chord runs the command');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 2', 'the counter counts');
    CommandRegistry.TryExecute('demo.wat.count');
    Assert.IsTrue(string.Join(',', PluginChrome.StatusSegments) = 'Count: 3', 'also from ExecuteCommand');
  finally
    PluginLoader.UnloadAll;
  end;
end;

procedure TTestSamplePlugins.TestWasiIsOptIn;
begin
  if not TDirectory.Exists(BuiltSample('mtn.demo.go.wasm')) then
    Assert.Pass('SKIP: mtn.demo.go.wasm is not built (run samples\build-samples.ps1)');
  if not WasmEngineAvailable then
    Assert.Pass('SKIP: wasmtime.dll not found');
  try
    // The same module with the manifest line removed must not load: WASI is
    // available only to a plugin that asks for it.
    TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi\mtn.demo.go.wasm'));
    TFile.Copy(TPath.Combine(BuiltSample('mtn.demo.go.wasm'), 'plugin.wasm'),
      TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi\mtn.demo.go.wasm\plugin.wasm'), True);
    TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),
      'plugins-sample-nowasi\mtn.demo.go.wasm\plugin.json'),
      '{"id":"mtn.demo.go.wasm","abi":2}', TEncoding.UTF8);
    PluginLoader.UnloadAll;
    PluginLoader.LoadPluginsFrom(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins-sample-nowasi'));
    Assert.IsTrue(not PluginLoader.IsPluginLoaded('mtn.demo.go.wasm'),
      'a module that imports WASI does not load without "wasi": true');
  finally
    PluginLoader.UnloadAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSamplePlugins);

end.
