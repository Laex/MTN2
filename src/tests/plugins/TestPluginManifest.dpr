program TestPluginManifest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  uPluginManifest in '..\..\Core\uPluginManifest.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
end;

procedure TestParse;
var
  M: TPluginManifest;
begin
  Expect(not TryParsePluginManifestJson('', M), 'empty');
  Expect(not TryParsePluginManifestJson('[]', M), 'array');
  Expect(TryParsePluginManifestJson(
    '{"id":"SamplePlugin","name":"Sample","version":"0.1.0","abi":1}', M),
    'full json');
  Expect(M.Id = 'SamplePlugin', 'id');
  Expect(M.Name = 'Sample', 'name');
  Expect(M.Version = '0.1.0', 'version');
  Expect(M.HasAbi and (M.AbiVersion = 1), 'abi');
  Expect(TryParsePluginManifestJson('{"id":"x"}', M), 'id only');
  Expect(not M.HasAbi, 'abi optional');
  Expect(Length(M.ArchiveExtensions) = 0, 'archiveExtensions optional');

  Expect(TryParsePluginManifestJson(
    '{"id":"mtn.7z","archiveExtensions":["7z","rar","tar"]}', M),
    'archiveExtensions json');
  Expect(Length(M.ArchiveExtensions) = 3, 'archiveExtensions count');
  Expect(M.ArchiveExtensions[0] = '7z', 'archiveExtensions[0]');
  Expect(M.ArchiveExtensions[1] = 'rar', 'archiveExtensions[1]');
  Expect(M.ArchiveExtensions[2] = 'tar', 'archiveExtensions[2]');
  Expect(Length(M.Schemes) = 0, 'schemes optional');
  Expect(TryParsePluginManifestJson(
    '{"id":"mtn.tmp","schemes":["tmp","TMP"]}', M), 'schemes json');
  Expect(Length(M.Schemes) = 2, 'schemes count');
  Expect(M.Schemes[0] = 'tmp', 'schemes[0]');
  Expect(M.Schemes[1] = 'tmp', 'schemes lowercased');
  Writeln('OK: TestParse');
end;

procedure TestListLabel;
var
  Dir, LabelText: string;
  Man: TPluginManifest;
begin
  LabelText := FormatPluginListLabel('mtn.7z', '7-Zip archives', '0.1.0');
  Expect(Pos('?', LabelText) = 0, 'no placeholder');
  Expect(Pos('mtn.7z', LabelText) = 1, 'id first');
  Expect(Pos('7-Zip archives', LabelText) > 0, 'name');
  Expect(Pos('0.1.0', LabelText) > 0, 'version');

  LabelText := FormatPluginListLabel('mtn.tmp', '', '');
  Expect(Pos('mtn.tmp', LabelText) = 1, 'id only');
  Expect(Pos('loaded', LabelText) > 0, 'status fallback');
  Expect(Pos('?', LabelText) = 0, 'no placeholder without manifest');

  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-label-' +
    IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'plugin.json'),
      '{"id":"mtn.7z","name":"7-Zip archives","version":"0.1.0","abi":1}',
      TEncoding.UTF8);
    Expect(TryReadPluginManifest(Dir, Man), 'read staged manifest');
    LabelText := PluginListDisplayLabel('mtn.7z', Dir);
    Expect(Pos('7-Zip archives', LabelText) > 0, 'label from dir');
    Expect(Pos('0.1.0', LabelText) > 0, 'version from dir');
  finally
    TDirectory.Delete(Dir, True);
  end;
  Writeln('OK: TestListLabel');
end;

begin
  try
    TestParse;
    TestListLabel;
    Writeln('All PluginManifest tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
