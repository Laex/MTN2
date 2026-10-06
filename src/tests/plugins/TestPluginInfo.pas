unit TestPluginInfo;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginInfo = class
  public
    [Test] procedure TestManifestDescriptionAndLocales;
    [Test] procedure TestManifestHelpFileStaysInThePluginFolder;
    [Test] procedure TestRegistriesDescribeWhatAPluginRegistered;
    [Test] procedure TestInfoCombinesManifestAndRegistrations;
    [Test] procedure TestWrapKeepsLinesWithinTheWidth;
    [Test] procedure TestInfoLinesForAPluginWithoutAnything;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uPluginManifest, uPluginInfo, uCommandRegistry, uDocumentProviders, uPanelPluginRegistry,
  uMenuRegistry, uPluginChrome, uPluginSettings, uVfsRegistry;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

procedure TestManifestDescriptionAndLocales;
var
  M: TPluginManifest;
begin
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","description":"Plain text"}', M), 'string form');
  Assert.IsTrue(ManifestDescription(M, 'ru') = 'Plain text', 'a plain string serves every language');
  Assert.IsTrue(TryParsePluginManifestJson(
    '{"id":"x","description":{"en":"English","RU":" Russian "},"author":" Me ","homepage":"https://x.test"}', M),
    'per-language form');
  Assert.IsTrue(ManifestDescription(M, 'ru') = 'Russian', 'the user''s language, trimmed, case-insensitive');
  Assert.IsTrue(ManifestDescription(M, 'de') = 'English', 'English is the fallback');
  Assert.IsTrue((M.Author = 'Me') and (M.Homepage = 'https://x.test'), 'author and homepage');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","description":{"fr":"Francais"}}', M), 'only French');
  Assert.IsTrue(ManifestDescription(M, 'ru') = 'Francais', 'any text beats none');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x"}', M), 'no description');
  Assert.IsTrue(ManifestDescription(M, 'en') = '', 'none given');
  Assert.IsTrue(TryParsePluginManifestJson('{"id":"x","description":42,"author":7}', M), 'wrong types');
  Assert.IsTrue((ManifestDescription(M, 'en') = '') and (M.Author = ''), 'wrong types are ignored');
end;

procedure TestManifestHelpFileStaysInThePluginFolder;
var
  Dir: string;
  M: TPluginManifest;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-help-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'help.md'), '# Help');
    TFile.WriteAllText(TPath.Combine(Dir, 'help.ru.md'), '# Справка', TEncoding.UTF8);
    TryParsePluginManifestJson('{"id":"x","help":"help.md"}', M);
    Assert.IsTrue(ManifestHelpFile(M, Dir, 'ru') = TPath.Combine(Dir, 'help.ru.md'), 'the language''s page first');
    Assert.IsTrue(ManifestHelpFile(M, Dir, 'de') = TPath.Combine(Dir, 'help.md'), 'then the page as named');
    Assert.IsTrue(ManifestHelpFile(M, '', 'en') = '', 'no folder');
    TryParsePluginManifestJson('{"id":"x","help":"missing.md"}', M);
    Assert.IsTrue(ManifestHelpFile(M, Dir, 'en') = '', 'a missing page is not offered');
    TryParsePluginManifestJson('{"id":"x","help":"..\\outside.md"}', M);
    Assert.IsTrue(ManifestHelpFile(M, Dir, 'en') = '', 'a path outside the folder is refused');
    TryParsePluginManifestJson('{"id":"x"}', M);
    Assert.IsTrue(ManifestHelpFile(M, Dir, 'en') = '', 'no help named');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure Clean(const AId: string);
begin
  CommandRegistry.UnregisterPlugin(AId);
  DocumentProviders.UnregisterPlugin(AId);
  PanelPluginRegistry.UnregisterPlugin(AId);
  MenuRegistry.UnregisterPlugin(AId);
  PluginChrome.UnregisterPlugin(AId);
  PluginSettings.UnregisterPlugin(AId);
  GlobalVfsRegistry.UnregisterPlugin(AId);
end;

procedure RegisterSomething(const AId: string);
begin
  CommandRegistry.RegisterCommand(AId, 'info.cmd', procedure begin end);
  CommandRegistry.RegisterCommandBinding(AId, 'info.cmd', 'Ctrl+Alt+F9');
  CommandRegistry.SetCommandCaption(AId, 'info.cmd', 'Cap');
  CommandRegistry.RegisterHook(AId, 'Copy', function(const C, O: string): Boolean begin Result := False; end);
  CommandRegistry.RegisterHook(AId, 'Delete', function(const C, O: string): Boolean begin Result := False; end);
  DocumentProviders.RegisterProvider(AId, 'p', '.csv;*', [dmView], function(const U: string; V: Boolean;
    out R: string): TDocumentOpenKind begin Result := dokPass; end);
  PanelPluginRegistry.RegisterActivateHandler(AId, 'tmp',
    function(const P, R: string; D: Boolean): Boolean begin Result := False; end);
  PluginChrome.SetStatusSegment(AId, 's', 'text');
  PluginSettings.RegisterConfigure(AId, procedure begin end);
  GlobalVfsRegistry.RegisterArchiveExtension(AId, '.info', akPluginScheme, 100, 'infoscheme');
end;

procedure TestRegistriesDescribeWhatAPluginRegistered;
var
  Text: string;
begin
  try
    Assert.IsTrue(Length(CommandRegistry.DescribePlugin('t.info')) = 0, 'nothing before registering');
    RegisterSomething('t.info');
    Text := Joined(CommandRegistry.DescribePlugin('t.info'));
    Assert.IsTrue(Pos('Command info.cmd, key Ctrl+Alt+F9, bar label "Cap"', Text) > 0, 'command: ' + Text);
    Assert.IsTrue(Pos('Watches or replaces commands: Copy, Delete', Text) > 0, 'hooks: ' + Text);
    Text := Joined(DocumentProviders.DescribePlugin('t.info'));
    Assert.IsTrue(Pos('Opens files (F3): .csv any file', Text) > 0, 'provider: ' + Text);
    Assert.IsTrue(Pos('tmp://', Joined(PanelPluginRegistry.DescribePlugin('t.info'))) > 0, 'panel activation');
    Assert.IsTrue(Pos('status line', Joined(PluginChrome.DescribePlugin('t.info'))) > 0, 'status text');
    Assert.IsTrue(Pos('.info', Joined(GlobalVfsRegistry.DescribePlugin('t.info'))) > 0, 'archive types');
    Assert.IsTrue(Length(CommandRegistry.DescribePlugin('t.other')) = 0, 'another plugin sees nothing');
  finally
    Clean('t.info');
  end;
end;

procedure TestInfoCombinesManifestAndRegistrations;
var
  Dir: string;
  Info: TPluginInfo;
  Text: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-plugin-info-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'plugin.json'),
      '{"id":"t.info","name":"Info plugin","version":"1.2","description":"Does useful things.",' +
      '"author":"Somebody","help":"help.md"}', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir, 'help.md'), '# Help');
    RegisterSomething('t.info');
    Info := BuildPluginInfo('t.info', Dir);
    Assert.IsTrue((Info.Name = 'Info plugin') and (Info.Version = '1.2'), 'name and version');
    Assert.IsTrue(Info.Description = 'Does useful things.', 'description');
    Assert.IsTrue(Info.HelpFile = TPath.Combine(Dir, 'help.md'), 'help page');
    Assert.IsTrue(Info.HasSettings, 'settings noticed');
    Assert.IsTrue(Length(Info.Provides) >= 6, 'the registrations are listed: ' + Joined(Info.Provides));
    Text := Joined(PluginInfoLines(Info, 60));
    Assert.IsTrue(Pos('Info plugin  1.2', Text) = 1, 'headline first');
    Assert.IsTrue(Pos('Id: t.info', Text) > 0, 'id when the name differs');
    Assert.IsTrue((Pos('Does useful things.', Text) > 0) and (Pos('Author: Somebody', Text) > 0),
      'description and author');
    Assert.IsTrue((Pos('What it adds to MTN2:', Text) > 0) and (Pos('- Command info.cmd', Text) > 0),
      'what it adds');
    Assert.IsTrue(Pos('Help button', Text) > 0, 'help hint');
  finally
    Clean('t.info');
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TestWrapKeepsLinesWithinTheWidth;
var
  Lines: TArray<string>;
  L: string;
begin
  Lines := WrapInfoText('one two three four five six seven eight nine ten', 15, '  ');
  Assert.IsTrue(Length(Lines) > 2, 'wrapped');
  for L in Lines do
    Assert.IsTrue(Length(L) <= 15, 'within the width: "' + L + '"');
  Assert.IsTrue((Pos('  ', Lines[1]) = 1) and (Pos('  ', Lines[0]) <> 1), 'continuation lines are indented');
  Lines := WrapInfoText('abcdefghijklmnopqrstuvwxyz', 10);
  Assert.IsTrue((Length(Lines) = 3) and (Length(Lines[0]) = 10) and (Lines[2] = 'uvwxyz'), 'a long word is cut');
  Assert.IsTrue(Length(WrapInfoText('   ', 20)) = 0, 'blank text has no lines');
  Assert.IsTrue(string.Join('|', WrapInfoText('a b', 20)) = 'a b', 'short text stays on one line');
end;

procedure TestInfoLinesForAPluginWithoutAnything;
var
  Info: TPluginInfo;
  Text: string;
begin
  Info := BuildPluginInfo('t.empty', '');
  Text := Joined(PluginInfoLines(Info, 60));
  Assert.IsTrue(Pos('t.empty', Text) = 1, 'the id stands in for the name');
  Assert.IsTrue(Pos('gives no description', Text) > 0, 'says there is no description');
  Assert.IsTrue(Pos('nothing yet', Text) > 0, 'says nothing is registered');
  Assert.IsTrue(Pos('Help button', Text) = 0, 'no help hint');
end;

{ TTestPluginInfo }

procedure TTestPluginInfo.TestManifestDescriptionAndLocales;
begin
  TestPluginInfo.TestManifestDescriptionAndLocales;
end;

procedure TTestPluginInfo.TestManifestHelpFileStaysInThePluginFolder;
begin
  TestPluginInfo.TestManifestHelpFileStaysInThePluginFolder;
end;

procedure TTestPluginInfo.TestRegistriesDescribeWhatAPluginRegistered;
begin
  TestPluginInfo.TestRegistriesDescribeWhatAPluginRegistered;
end;

procedure TTestPluginInfo.TestInfoCombinesManifestAndRegistrations;
begin
  TestPluginInfo.TestInfoCombinesManifestAndRegistrations;
end;

procedure TTestPluginInfo.TestWrapKeepsLinesWithinTheWidth;
begin
  TestPluginInfo.TestWrapKeepsLinesWithinTheWidth;
end;

procedure TTestPluginInfo.TestInfoLinesForAPluginWithoutAnything;
begin
  TestPluginInfo.TestInfoLinesForAPluginWithoutAnything;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginInfo);

end.
