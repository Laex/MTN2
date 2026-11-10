unit TestSevenZipDllWarning;

{ The startup warning about a missing archive engine: HostSevenZipDllMissing is
  True only when the mtn.7z plugin folder exists and no engine is found (7z.dll
  in it; on POSIX also a 7-Zip program in the search path). Also the first
  start of the plugin host: with fresh settings every plugin is switched on. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSevenZipDllWarning = class
  public
    [Test] procedure MissingOnlyWhenPluginFolderLacksDll;
    [Test] procedure FreshSettingsKeepEveryPluginOn;
    [Test] procedure ExistingSettingsKeepPluginsOn;
    [Test] procedure OffPluginsNeedNoDllAndAreReported;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uPluginHost, uConfigLocation, uPluginManifest,
  uPlatformPaths, uPlatformProcess;

function EngineFileName: string;
begin
  if PlatformPosixPaths then
    Result := '7zz'
  else
    Result := '7z.dll';
end;

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
    Assert.AreEqual(PlatformSevenZipEngine(TPath.Combine(Root, 'mtn.7z')) = '', HostSevenZipDllMissing,
      'plugin folder without an engine');
    TFile.WriteAllText(TPath.Combine(Root, 'mtn.7z' + PathDelim + EngineFileName), 'x');
    Assert.IsFalse(HostSevenZipDllMissing, 'engine present');
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

procedure TTestSevenZipDllWarning.FreshSettingsKeepEveryPluginOn;
var
  Root, Cfg, Prev: string;
begin
  Prev := GetConfigDirectory;
  Root := MakeRoot(['mtn.a', 'mtn.b']);
  Cfg := TPath.Combine(TPath.GetTempPath, 'mtn2-firstrun-cfg-' + TPath.GetGUIDFileName(False));
  try
    SetConfigDirectoryOverride(Cfg);
    StartPluginHost(Root);
    Assert.IsTrue(Pos('[x]', HostPluginRows[0]) > 0, 'the first plugin starts on');
    Assert.IsTrue(Pos('[x]', HostPluginRows[1]) > 0, 'the second plugin starts on');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Cfg, 'disabled-plugins.json')), 'nothing is written');
    StopPluginHost;
    // A later start reads the list of switched-off plugins.
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
    TDirectory.CreateDirectory(Cfg);
    TFile.WriteAllText(TPath.Combine(Cfg, 'disabled-plugins.json'), '{"disabled":["mtn.7z"]}', TEncoding.UTF8);
    StartPluginHost(Root);
    Assert.IsTrue(HostAllPluginsOff, 'every plugin is on the switched-off list');
    Assert.IsFalse(HostSevenZipDllMissing, 'no warning about a dll of a plugin that is off');
    StopPluginHost;
    TFile.WriteAllText(TPath.Combine(Cfg, 'disabled-plugins.json'), '{"disabled":[]}', TEncoding.UTF8);
    StartPluginHost(Root);
    Assert.IsFalse(HostAllPluginsOff, 'switched on again');
    Assert.AreEqual(PlatformSevenZipEngine(TPath.Combine(Root, 'mtn.7z')) = '', HostSevenZipDllMissing,
      'now the missing engine matters');
  finally
    StopPluginHost;
    SetConfigDirectoryOverride(Prev);
    TDirectory.Delete(Root, True);
    if TDirectory.Exists(Cfg) then
      TDirectory.Delete(Cfg, True);
  end;
end;

end.
