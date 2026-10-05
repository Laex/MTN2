unit TestPluginSettings;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginSettings = class
  public
    [Test] procedure TestValuesSurviveANewSession;
    [Test] procedure TestPluginsDoNotSeeEachOther;
    [Test] procedure TestInvalidKeysAndUnwritableFolder;
    [Test] procedure TestConfigureHandlerLifecycle;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uPluginSettings;

function ScratchDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-settings-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Result);
  SetPluginSettingsDirectory(Result);
end;

procedure Finish(const ADir: string);
begin
  SetPluginSettingsDirectory('');
  if TDirectory.Exists(ADir) then
    TDirectory.Delete(ADir, True);
end;

procedure TestValuesSurviveANewSession;
var
  Dir, V: string;
begin
  Dir := ScratchDir;
  try
    Assert.IsTrue(not PluginSettings.TryGetValue('mtn.x', 'mode', V), 'nothing stored yet');
    Assert.IsTrue(PluginSettings.SetValue('mtn.x', 'mode', 'fast'), 'stored');
    Assert.IsTrue(PluginSettings.SetValue('mtn.x', 'text', 'Hello "world" ' + #$43F#$440#$438#$432#$435#$442),
      'any text, quotes and non-ASCII included');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dir, 'plugin-settings-mtn.x.json')), 'one file per plugin');
    // A new session reads the file again.
    SetPluginSettingsDirectory(Dir);
    Assert.IsTrue(PluginSettings.TryGetValue('mtn.x', 'mode', V) and (V = 'fast'), 'value read back');
    Assert.IsTrue(PluginSettings.TryGetValue('MTN.X', 'text', V) and
      (V = 'Hello "world" ' + #$43F#$440#$438#$432#$435#$442),
      'plugin id is case-insensitive, text round-trips');
    Assert.IsTrue(PluginSettings.SetValue('mtn.x', 'mode', 'slow') and
      PluginSettings.TryGetValue('mtn.x', 'mode', V) and (V = 'slow'), 'a value can change');
  finally
    Finish(Dir);
  end;
end;

procedure TestPluginsDoNotSeeEachOther;
var
  Dir, V: string;
begin
  Dir := ScratchDir;
  try
    PluginSettings.SetValue('mtn.a', 'k', 'A');
    PluginSettings.SetValue('mtn.b', 'k', 'B');
    Assert.IsTrue(PluginSettings.TryGetValue('mtn.a', 'k', V) and (V = 'A'), 'first plugin');
    Assert.IsTrue(PluginSettings.TryGetValue('mtn.b', 'k', V) and (V = 'B'), 'second plugin');
    PluginSettings.SetValue('..\evil', 'k', 'x');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dir, 'plugin-settings-.._evil.json')),
      'a plugin id cannot move its file out of the settings folder');
  finally
    Finish(Dir);
  end;
end;

procedure TestInvalidKeysAndUnwritableFolder;
var
  Dir, V: string;
begin
  Dir := ScratchDir;
  Assert.IsTrue(not PluginSettings.SetValue('', 'k', 'x'), 'no plugin id');
  Assert.IsTrue(not PluginSettings.SetValue('mtn.a', '', 'x'), 'no key');
  Finish(Dir);
  // A file where the folder should be: the write fails, the value still holds.
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-settings-file-' + IntToStr(Random(MaxInt)));
  TFile.WriteAllText(Dir, 'x');
  try
    SetPluginSettingsDirectory(TPath.Combine(Dir, 'sub'));
    Assert.IsTrue(not PluginSettings.SetValue('mtn.a', 'k', 'kept'), 'the write is reported as failed');
    Assert.IsTrue(PluginSettings.TryGetValue('mtn.a', 'k', V) and (V = 'kept'),
      'the value holds for this run');
  finally
    SetPluginSettingsDirectory('');
    if TFile.Exists(Dir) then
      TFile.Delete(Dir);
  end;
end;

procedure TestConfigureHandlerLifecycle;
var
  Calls: Integer;
begin
  Calls := 0;
  Assert.IsTrue(not PluginSettings.HasConfigure('mtn.cfg'), 'none yet');
  Assert.IsTrue(not PluginSettings.TryConfigure('mtn.cfg'), 'nothing to run');
  PluginSettings.RegisterConfigure('mtn.cfg', procedure begin Inc(Calls); end);
  PluginSettings.RegisterConfigure('', procedure begin Inc(Calls, 100); end);
  PluginSettings.RegisterConfigure('mtn.nil', nil);
  Assert.IsTrue(PluginSettings.HasConfigure('MTN.CFG') and not PluginSettings.HasConfigure('mtn.nil'),
    'registered, case-insensitive; invalid registrations ignored');
  Assert.IsTrue(PluginSettings.TryConfigure('mtn.cfg') and (Calls = 1), 'the handler runs');
  PluginSettings.RegisterConfigure('mtn.cfg', procedure begin Inc(Calls, 10); end);
  PluginSettings.TryConfigure('mtn.cfg');
  Assert.IsTrue(Calls = 11, 'a second registration replaces the first');
  PluginSettings.RegisterConfigure('mtn.cfg',
    procedure begin raise Exception.Create('plugin failure'); end);
  Assert.IsTrue(not PluginSettings.TryConfigure('mtn.cfg'), 'a handler that raises reports failure');
  PluginSettings.UnregisterPlugin('mtn.cfg');
  Assert.IsTrue(not PluginSettings.HasConfigure('mtn.cfg'), 'unregistered');
end;

{ TTestPluginSettings }

procedure TTestPluginSettings.TestValuesSurviveANewSession;
begin
  TestPluginSettings.TestValuesSurviveANewSession;
end;

procedure TTestPluginSettings.TestPluginsDoNotSeeEachOther;
begin
  TestPluginSettings.TestPluginsDoNotSeeEachOther;
end;

procedure TTestPluginSettings.TestInvalidKeysAndUnwritableFolder;
begin
  TestPluginSettings.TestInvalidKeysAndUnwritableFolder;
end;

procedure TTestPluginSettings.TestConfigureHandlerLifecycle;
begin
  TestPluginSettings.TestConfigureHandlerLifecycle;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginSettings);

end.
