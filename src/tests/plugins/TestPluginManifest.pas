unit TestPluginManifest;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginManifest = class
  public
    [Test] procedure TestParse;
    [Test] procedure TestListLabel;
    [Test] procedure TestOverrides;
    [Test] procedure TestOverrideAllowList;
    [Test] procedure TestDisabledPluginsFile;
    [Test] procedure TestPluginOrderFile;
    [Test] procedure TestShippedSevenZipOffersZipOverride;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uPluginManifest;

procedure TestParse;
var
  M: TPluginManifest;
begin
  Assert.IsTrue(not TryParsePluginManifestJson('', M), 'empty');
  Assert.IsTrue(not TryParsePluginManifestJson('[]', M), 'array');
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"SamplePlugin","name":"Sample","version":"0.1.0","abi":1}', M),
    'full json');
  Assert.IsTrue(M.Id = 'SamplePlugin', 'id');
  Assert.IsTrue(M.Name = 'Sample', 'name');
  Assert.IsTrue(M.Version = '0.1.0', 'version');
  Assert.IsTrue(M.HasAbi and (M.AbiVersion = 1), 'abi');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x"}', M), 'id only');
  Assert.IsTrue(not M.HasAbi, 'abi optional');
  Assert.IsTrue(Length(M.ArchiveExtensions) = 0, 'archiveExtensions optional');

  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"mtn.7z","archiveExtensions":["7z","rar","tar"]}', M),
    'archiveExtensions json');
  Assert.IsTrue(Length(M.ArchiveExtensions) = 3, 'archiveExtensions count');
  Assert.IsTrue(M.ArchiveExtensions[0] = '7z', 'archiveExtensions[0]');
  Assert.IsTrue(M.ArchiveExtensions[1] = 'rar', 'archiveExtensions[1]');
  Assert.IsTrue(M.ArchiveExtensions[2] = 'tar', 'archiveExtensions[2]');
  Assert.IsTrue(Length(M.Schemes) = 0, 'schemes optional');
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"mtn.tmp","schemes":["tmp","TMP"]}', M), 'schemes json');
  Assert.IsTrue(Length(M.Schemes) = 2, 'schemes count');
  Assert.IsTrue(M.Schemes[0] = 'tmp', 'schemes[0]');
  Assert.IsTrue(M.Schemes[1] = 'tmp', 'schemes lowercased');
end;

procedure TestListLabel;
var
  Dir, LabelText: string;
  Man: TPluginManifest;
begin
  LabelText := FormatPluginListLabel('mtn.7z', '7-Zip archives', '0.1.0');
  Assert.IsTrue(Pos('?', LabelText) = 0, 'no placeholder');
  Assert.IsTrue(Pos('mtn.7z', LabelText) = 1, 'id first');
  Assert.IsTrue(Pos('7-Zip archives', LabelText) > 0, 'name');
  Assert.IsTrue(Pos('0.1.0', LabelText) > 0, 'version');

  LabelText := FormatPluginListLabel('mtn.tmp', '', '');
  Assert.IsTrue(Pos('mtn.tmp', LabelText) = 1, 'id only');
  Assert.IsTrue(Pos('loaded', LabelText) > 0, 'status fallback');
  Assert.IsTrue(Pos('?', LabelText) = 0, 'no placeholder without manifest');

  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-label-' +
    IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'plugin.json'),
      '{"id":"mtn.7z","name":"7-Zip archives","version":"0.1.0","abi":1}',
      TEncoding.UTF8);
    Assert.IsTrue(TryReadPluginManifest(Dir, Man), 'read staged manifest');
    LabelText := PluginListDisplayLabel('mtn.7z', Dir);
    Assert.IsTrue(Pos('7-Zip archives', LabelText) > 0, 'label from dir');
    Assert.IsTrue(Pos('0.1.0', LabelText) > 0, 'version from dir');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestOverrides;
var
  M: TPluginManifest;
begin
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x"}', M), 'id only');
  Assert.IsTrue(Length(M.Overrides) = 0, 'overrides optional');
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"mtn.zip","overrides":["SFTP"," .ZIP ","",7]}', M), 'overrides json');
  Assert.IsTrue(Length(M.Overrides) = 2, 'blank and non-string entries dropped');
  Assert.IsTrue(M.Overrides[0] = 'sftp', 'scheme lowercased');
  Assert.IsTrue(M.Overrides[1] = '.zip', 'extension trimmed and lowercased');
  Assert.IsTrue(not M.Startup, 'startup is off by default');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","startup":true}', M), 'startup json');
  Assert.IsTrue(M.Startup, 'startup on');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","startup":"yes"}', M), 'startup non-bool');
  Assert.IsTrue(not M.Startup, 'only a JSON boolean turns startup on');
end;

procedure TestShippedSevenZipOffersZipOverride;
var
  Dir: string;
  M: TPluginManifest;
  Ext: string;
  HasZip: Boolean;
begin
  Dir := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\plugins\mtn.7z'));
  Assert.IsTrue(TryReadPluginManifest(Dir, M), 'the shipped mtn.7z manifest is readable');
  HasZip := False;
  for Ext in M.ArchiveExtensions do
    if SameText(Ext, 'zip') then
      HasZip := True;
  Assert.IsTrue(HasZip, 'mtn.7z can serve .zip archives');
  Assert.IsTrue((Length(M.Overrides) = 1) and (M.Overrides[0] = '.zip'),
    'mtn.7z asks to replace the built-in .zip handling only when the user allows it');
  Assert.IsTrue((Length(M.Schemes) = 1) and (M.Schemes[0] = '7z'), 'its scheme');
end;

procedure TestDisabledPluginsFile;
var
  Dir, FileName: string;
  Ids: TArray<string>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-disabled-' + IntToStr(Random(MaxInt)));
  FileName := TPath.Combine(Dir, 'sub\disabled-plugins.json');
  try
    Assert.IsTrue(not TryReadDisabledPlugins(FileName, Ids) and (Length(Ids) = 0), 'missing file');
    WriteDisabledPlugins(FileName, ['mtn.7z', 'mtn.ws']);
    Assert.IsTrue(TryReadDisabledPlugins(FileName, Ids), 'written file reads back');
    Assert.IsTrue((Length(Ids) = 2) and (Ids[0] = 'mtn.7z') and (Ids[1] = 'mtn.ws'), 'ids round-trip');
    TFile.WriteAllText(FileName, 'not json', TEncoding.UTF8);
    Assert.IsTrue(not TryReadDisabledPlugins(FileName, Ids) and (Length(Ids) = 0), 'invalid file');
    WriteDisabledPlugins(FileName, []);
    Assert.IsTrue(not TFile.Exists(FileName), 'an empty list removes the file');
  finally
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TestPluginOrderFile;
var
  Dir, FileName: string;
  Ids: TArray<string>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-order-file-' + IntToStr(Random(MaxInt)));
  FileName := TPath.Combine(Dir, 'sub\plugin-order.json');
  try
    Assert.IsTrue(not TryReadPluginOrder(FileName, Ids) and (Length(Ids) = 0), 'missing file');
    WritePluginOrder(FileName, ['mtn.ws', 'mtn.7z', 'mtn.tmp']);
    Assert.IsTrue(TryReadPluginOrder(FileName, Ids), 'written file reads back');
    Assert.AreEqual('mtn.ws,mtn.7z,mtn.tmp', string.Join(',', Ids), 'the order round-trips');
    TFile.WriteAllText(FileName, 'not json', TEncoding.UTF8);
    Assert.IsTrue(not TryReadPluginOrder(FileName, Ids) and (Length(Ids) = 0), 'invalid file');
    WritePluginOrder(FileName, []);
    Assert.IsTrue(not TFile.Exists(FileName), 'an empty list removes the file');
  finally
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TestOverrideAllowList;
var
  Dir: string;
  Ids: TArray<string>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-allow-' +
    IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Dir);
  try
    Assert.IsTrue(not TryReadOverrideAllowList(Dir, Ids), 'missing file');
    Assert.IsTrue(Length(Ids) = 0, 'missing file allows nothing');
    TFile.WriteAllText(TPath.Combine(Dir, 'overrides.json'), 'not json', TEncoding.UTF8);
    Assert.IsTrue(not TryReadOverrideAllowList(Dir, Ids), 'invalid file');
    Assert.IsTrue(Length(Ids) = 0, 'invalid file allows nothing');
    TFile.WriteAllText(TPath.Combine(Dir, 'overrides.json'),
      '{"allow":["mtn.zip"," mtn.sftp ",""]}', TEncoding.UTF8);
    Assert.IsTrue(TryReadOverrideAllowList(Dir, Ids), 'valid file');
    Assert.IsTrue(Length(Ids) = 2, 'blank ids dropped');
    Assert.IsTrue(Ids[0] = 'mtn.zip', 'first id');
    Assert.IsTrue(Ids[1] = 'mtn.sftp', 'ids trimmed');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ TTestPluginManifest }

procedure TTestPluginManifest.TestShippedSevenZipOffersZipOverride;
begin
  TestPluginManifest.TestShippedSevenZipOffersZipOverride;
end;

procedure TTestPluginManifest.TestDisabledPluginsFile;
begin
  TestPluginManifest.TestDisabledPluginsFile;
end;

procedure TTestPluginManifest.TestPluginOrderFile;
begin
  TestPluginManifest.TestPluginOrderFile;
end;

procedure TTestPluginManifest.TestOverrides;
begin
  TestPluginManifest.TestOverrides;
end;

procedure TTestPluginManifest.TestOverrideAllowList;
begin
  TestPluginManifest.TestOverrideAllowList;
end;

procedure TTestPluginManifest.TestParse;
begin
  TestPluginManifest.TestParse;
end;

procedure TTestPluginManifest.TestListLabel;
begin
  TestPluginManifest.TestListLabel;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginManifest);

end.
