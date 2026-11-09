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
    [Test] procedure TestDeclarativeRegistrations;
    [Test] procedure TestConditionsDriveItemsAndDocumentExtensions;
    [Test] procedure TestShippedDeclarationsNameIdsTheSourcesRegister;
    [Test] procedure TestActivationDeclarations;
  end;

implementation

uses
  uTestPaths,
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

procedure TestDeclarativeRegistrations;
var
  M: TPluginManifest;
begin
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x"}', M));
  Assert.IsTrue(not M.Declarative and (Length(M.Commands) = 0) and (Length(M.MenuItems) = 0),
    'a manifest without declarations is not declarative');
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"x","declarative":true,' +
    '"commands":[{"id":"x.run","key":"Ctrl+Alt+J","label":"Run"},{"id":""},{"key":"F5"}],' +
    '"menuItems":[{"id":"x.run","caption":{"en":"Run it","ru":"Run ru"},"priority":50},{"id":"x.two"}]}', M));
  Assert.IsTrue(M.Declarative, 'declarative');
  Assert.IsTrue(Length(M.Commands) = 1, 'entries without an id are dropped');
  Assert.AreEqual('x.run', M.Commands[0].Id);
  Assert.AreEqual('Ctrl+Alt+J', M.Commands[0].Key);
  Assert.AreEqual('Run', LocalizedText(M.Commands[0].LabelLocales, M.Commands[0].LabelTexts, 'de'),
    'a plain label serves every language');
  Assert.IsTrue(Length(M.MenuItems) = 2);
  Assert.IsTrue(M.MenuItems[0].Priority = 50);
  Assert.IsTrue(M.MenuItems[1].Priority = 100, 'default priority');
  Assert.AreEqual('Run ru', LocalizedText(M.MenuItems[0].CaptionLocales, M.MenuItems[0].CaptionTexts, 'ru'));
  Assert.AreEqual('Run it', LocalizedText(M.MenuItems[0].CaptionLocales, M.MenuItems[0].CaptionTexts, 'de'),
    'English is the fallback');
end;

procedure TestConditionsDriveItemsAndDocumentExtensions;
var
  M: TPluginManifest;
  C: TManifestCondition;
begin
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"x","declarative":true,' +
    '"driveItems":[{"id":"d","caption":"D","uri":"d:///","priority":7,"when":{"os":"windows"}},{"id":"nouri"}],' +
    '"menuItems":[{"id":"m","when":{"exe":"tool","env":"HOME","file":"a.cfg"}}],' +
    '"documentExtensions":[".CSV","tsv"]}', M));
  Assert.IsTrue(Length(M.DriveItems) = 1, 'a drive item needs a uri');
  Assert.AreEqual('d:///', M.DriveItems[0].Uri);
  Assert.IsTrue(M.DriveItems[0].Priority = 7);
  Assert.IsTrue(Length(M.DriveItems[0].When.Os) = 1, 'os condition');
  Assert.AreEqual('tool', M.MenuItems[0].When.Exe);
  Assert.AreEqual('HOME', M.MenuItems[0].When.Env);
  Assert.AreEqual('a.cfg', M.MenuItems[0].When.FileName);
  Assert.IsTrue((Length(M.DocumentExtensions) = 2) and (M.DocumentExtensions[0] = 'csv'),
    'extensions are lower case without the dot');

  C := Default(TManifestCondition);
  Assert.IsTrue(ManifestConditionHolds(C), 'no condition always holds');
  C.Os := [CurrentOsName];
  Assert.IsTrue(ManifestConditionHolds(C), 'the current os');
  C.Os := ['no-such-os'];
  Assert.IsTrue(not ManifestConditionHolds(C), 'another os');
  C := Default(TManifestCondition);
  C.Exe := 'mtn-no-such-tool-xyz';
  Assert.IsTrue(not ManifestConditionHolds(C), 'a missing program');
  C := Default(TManifestCondition);
  C.FileName := ParamStr(0);
  Assert.IsTrue(ManifestConditionHolds(C), 'an existing file');
  C.FileName := ParamStr(0) + '.missing';
  Assert.IsTrue(not ManifestConditionHolds(C), 'a missing file');
  C := Default(TManifestCondition);
  C.Env := 'MTN_NO_SUCH_VARIABLE_XYZ';
  Assert.IsTrue(not ManifestConditionHolds(C), 'an unset variable');
  C.Env := 'PATH';
  Assert.IsTrue(ManifestConditionHolds(C), 'a set variable');
end;

procedure TestShippedDeclarationsNameIdsTheSourcesRegister;
var
  Root, Dir, Src, Text, Id: string;
  M: TPluginManifest;
  Checked: Integer;
  Ids: TArray<string>;
  Cmd: TManifestCommand;
  Item: TManifestMenuItem;
  Drive: TManifestDriveItem;
begin
  Root := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)), NativePath('../../plugins')));
  Checked := 0;
  for Dir in TDirectory.GetDirectories(Root) do
  begin
    if not (TryReadPluginManifest(Dir, M) and M.Declarative) then
      Continue;
    Text := '';
    for Src in TDirectory.GetFiles(Dir, '*.*', TSearchOption.soAllDirectories) do
      if SameText(ExtractFileExt(Src), '.dpr') or SameText(ExtractFileExt(Src), '.pas') then
        Text := Text + TFile.ReadAllText(Src, TEncoding.UTF8);
    Ids := [];
    for Cmd in M.Commands do
      Ids := Ids + [Cmd.Id];
    for Item in M.MenuItems do
      Ids := Ids + [Item.Id];
    for Drive in M.DriveItems do
      Ids := Ids + [Drive.Id];
    Assert.IsTrue(Length(Ids) > 0, M.Id + ' declares something');
    for Id in Ids do
      Assert.IsTrue(Text.Contains('''' + Id + ''''),
        M.Id + ' declares ' + Id + ' but its sources never register it');
    Inc(Checked);
  end;
  Assert.IsTrue(Checked >= 2, 'the shipped declarative plugins were found');
end;

procedure TestActivationDeclarations;
var
  M: TPluginManifest;
  C: TManifestCondition;
begin
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"x","startup":true,"startupWhen":{"file":"%config%/macros/*.lua"},' +
    '"openRegistrations":true,"declarative":true,' +
    '"activateOn":[{"event":"Panel.Dir","dirHas":".git"},{"event":""},{"dirHas":"a"},{"event":"language.changed"}],' +
    '"menuItems":[{"id":"a"},{"id":"b","parent":"Macros"}]}', M));
  Assert.IsTrue(M.HasStartupWhen and (M.StartupWhen.FileName = '%config%/macros/*.lua'), 'startupWhen');
  Assert.IsTrue(M.OpenRegistrations, 'openRegistrations');
  Assert.IsTrue(Length(M.ActivateOn) = 2, 'entries without an event are skipped');
  Assert.IsTrue((M.ActivateOn[0].Event = 'panel.dir') and (M.ActivateOn[0].DirHas = '.git'), 'dirHas');
  Assert.IsTrue((M.ActivateOn[1].Event = 'language.changed') and (M.ActivateOn[1].DirHas = ''), 'bare event');
  Assert.IsTrue((M.MenuItems[0].Parent = 'Plugins') and (M.MenuItems[1].Parent = 'Macros'), 'menu parent');

  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","startup":true}', M));
  Assert.IsTrue(not M.HasStartupWhen and not M.OpenRegistrations and (Length(M.ActivateOn) = 0),
    'the activation keys are optional');

  C := Default(TManifestCondition);
  C.FileName := ExtractFilePath(ParamStr(0)) + '*.exe';
  Assert.IsTrue(ManifestConditionHolds(C), 'a wildcard that matches');
  C.FileName := ExtractFilePath(ParamStr(0)) + '*.mtn-no-such-ext';
  Assert.IsTrue(not ManifestConditionHolds(C), 'a wildcard that matches nothing');
  C.FileName := '%config%/mtn-no-such-folder-xyz/*.lua';
  Assert.IsTrue(not ManifestConditionHolds(C), '%config% in a missing folder');
end;

procedure TestShippedSevenZipOffersZipOverride;
var
  Dir: string;
  M: TPluginManifest;
  Ext: string;
  HasZip: Boolean;
begin
  Dir := ExpandFileName(TPath.Combine(ExtractFilePath(ParamStr(0)), NativePath('../../plugins/mtn.7z')));
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
  FileName := TPath.Combine(Dir, NativePath('sub/disabled-plugins.json'));
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
  FileName := TPath.Combine(Dir, NativePath('sub/plugin-order.json'));
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

procedure TTestPluginManifest.TestDeclarativeRegistrations;
begin
  TestPluginManifest.TestDeclarativeRegistrations;
end;

procedure TTestPluginManifest.TestConditionsDriveItemsAndDocumentExtensions;
begin
  TestPluginManifest.TestConditionsDriveItemsAndDocumentExtensions;
end;

procedure TTestPluginManifest.TestShippedDeclarationsNameIdsTheSourcesRegister;
begin
  TestPluginManifest.TestShippedDeclarationsNameIdsTheSourcesRegister;
end;

procedure TTestPluginManifest.TestActivationDeclarations;
begin
  TestPluginManifest.TestActivationDeclarations;
end;

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
