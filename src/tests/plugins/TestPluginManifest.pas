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

{ TTestPluginManifest }

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
