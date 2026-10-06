unit TestSevenZipDllWarning;

{ The startup warning about a missing 7z.dll: HostSevenZipDllMissing is True
  only when the mtn.7z plugin folder exists without a 7z.dll. Also the first
  start of the plugin host: with fresh settings every plugin is switched off. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipDllWarning = class
  public
    [Test] procedure MissingOnlyWhenPluginFolderLacksDll;
    [Test] procedure FreshSettingsSwitchEveryPluginOff;
    [Test] procedure ExistingSettingsKeepPluginsOn;
    [Test] procedure OffPluginsNeedNoDllAndAreReported;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uPluginHost, uConfigLocation, uPluginManifest;

procedure TTestSevenZipDllWarning.MissingOnlyWhenPluginFolderLacksDll;
var
  Root: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-7z-warning-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Root);
  try
    StartPluginHost(Root);
    Assert.IsFalse(HostSevenZipDllMissing, 'no mtn.7z folder: the plugin is not installed');
    TDirectory.CreateDirectory(TPath.Combine(Root, 'mtn.7z'));
    Assert.IsTrue(HostSevenZipDllMissing, 'plugin folder without 7z.dll');
    TFile.WriteAllText(TPath.Combine(Root, 'mtn.7z' + PathDelim + '7z.dll'), 'x');
    Assert.IsFalse(HostSevenZipDllMissing, '7z.dll present');
  finally
    StopPluginHost;
    TDirectory.Delete(Root, True);
  end;
end;

function MakeRoot(const AIds: array of string): string;
var
  Id: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-firstrun-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Result);
  for Id in AIds do
    TDirectory.CreateDirectory(TPath.Combine(Result, Id));
end;

procedure TTestSevenZipDllWarning.FreshSettingsSwitchEveryPluginOff;
var
  Root, Cfg, Prev: string;
  Ids: TArray<string>;
begin
  Prev := GetConfigDirectory;
  Root := MakeRoot(['mtn.a', 'mtn.b']);
  Cfg := TPath.Combine(TPath.GetTempPath, 'mtn2-firstrun-cfg-' + TPath.GetGUIDFileName(False));
  try
    SetConfigDirectoryOverride(Cfg);
    StartPluginHost(Root);
    Assert.IsTrue(TryReadDisabledPlugins(TPath.Combine(Cfg, 'disabled-plugins.json'), Ids),
      'the list is written at once');
    Assert.IsTrue(Length(Ids) = 2, 'both plugins are on it');
    Assert.IsTrue(Pos('[ ]', HostPluginRows[0]) > 0, 'and shown as switched off');
    StopPluginHost;
    // A second start reads the list instead of switching everything off again.
    TFile.WriteAllText(TPath.Combine(Cfg, 'disabled-plugins.json'), '{"disabled":["mtn.a"]}', TEncoding.UTF8);
    StartPluginHost(Root);
    Assert.IsTrue(Pos('[ ]', HostPluginRows[0]) > 0, 'mtn.a stays off');
    Assert.IsTrue(Pos('[x]', HostPluginRows[1]) > 0, 'mtn.b the user switched on stays on');
  finally
    StopPluginHost;
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Root, True);
    if TDirectory.Exists(Cfg) then
      TDirectory.Delete(Cfg, True);
  end;
end;

procedure TTestSevenZipDllWarning.ExistingSettingsKeepPluginsOn;
var
  Root, Cfg, Prev: string;
begin
  Prev := GetConfigDirectory;
  Root := MakeRoot(['mtn.a']);
  Cfg := TPath.Combine(TPath.GetTempPath, 'mtn2-firstrun-cfg-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Cfg);
  try
    // Settings of an earlier version: a session file, no list of switched-off plugins.
    TFile.WriteAllText(TPath.Combine(Cfg, 'session.json'), '{}', TEncoding.UTF8);
    SetConfigDirectoryOverride(Cfg);
    StartPluginHost(Root);
    Assert.IsTrue(Pos('[x]', HostPluginRows[0]) > 0, 'plugins stay on for an existing installation');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Cfg, 'disabled-plugins.json')), 'nothing is written');
  finally
    StopPluginHost;
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Root, True);
    TDirectory.Delete(Cfg, True);
  end;
end;

procedure TTestSevenZipDllWarning.OffPluginsNeedNoDllAndAreReported;
var
  Root, Cfg, Prev: string;
begin
  Prev := GetConfigDirectory;
  Root := MakeRoot(['mtn.7z']);
  Cfg := TPath.Combine(TPath.GetTempPath, 'mtn2-firstrun-cfg-' + TPath.GetGUIDFileName(False));
  try
    SetConfigDirectoryOverride(Cfg);
    StartPluginHost(Root);
    Assert.IsTrue(HostAllPluginsOff, 'a fresh start: every plugin is off');
    Assert.IsFalse(HostSevenZipDllMissing, 'no warning about a dll of a plugin that is off');
    StopPluginHost;
    TFile.WriteAllText(TPath.Combine(Cfg, 'disabled-plugins.json'), '{"disabled":[]}', TEncoding.UTF8);
    StartPluginHost(Root);
    Assert.IsFalse(HostAllPluginsOff, 'switched on again');
    Assert.IsTrue(HostSevenZipDllMissing, 'now the missing dll matters');
  finally
    StopPluginHost;
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Root, True);
    if TDirectory.Exists(Cfg) then
      TDirectory.Delete(Cfg, True);
  end;
end;

end.
