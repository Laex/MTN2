unit TestHelpContext;

{ Context F1: the help topic chosen for what is on screen, and that every
  topic named exists in both shipped languages (bin\win64\resource\en\help, bin\win64\resource\ru\help). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHelpContext = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestScreens;
    [Test] procedure TestEveryTopicExists;
    [Test] procedure TestMenuActionTopics;
  end;

implementation

uses
  uTestPaths,
  System.SysUtils,
  System.IOUtils,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uHelpContext;

procedure ExpectTopic(const AScreen: THelpScreen; const ATopic, AMsg: string);
var
  Got: string;
begin
  Got := HelpTopicForScreen(AScreen);
  Assert.IsTrue(Got = ATopic, AMsg + ' -> ' + ATopic + ' (got ' + Got + ')');
end;

function Panels(const AURI: string): THelpScreen;
begin
  Result := Default(THelpScreen);
  Result.WorkspaceKind := wkPanels;
  Result.PanelURI := AURI;
end;

function HelpDir(const ALang: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    NativePath('../../../bin/win64/resource/') + ALang + NativePath('/help'))); // exe in src\tests\dcu
end;

procedure TestScreens;
var
  S: THelpScreen;
begin
  ExpectTopic(Panels('file:///C:/Work'), 'panels.md', 'plain folder');
  ExpectTopic(Panels('file:///C:/a.zip!/dir'), 'archives.md', 'inside zip');
  ExpectTopic(Panels('7z:///C:/a.7z!/'), 'archives.md', 'inside 7z');
  ExpectTopic(Panels('sftp://host/home'), 'ssh.md', 'SFTP');
  ExpectTopic(Panels('recycle:///'), 'drives.md', 'Recycle Bin');
  ExpectTopic(Panels('sys://folders'), 'drives.md', 'system folders');
  ExpectTopic(Panels('find://1'), 'search.md', 'search results');
  ExpectTopic(Panels('tmp:///'), 'search.md', 'temporary panel');
  ExpectTopic(Panels('ws:///'), 'workspaces.md', 'workspace library');

  S := Panels('file:///C:/');
  S.CmdFocused := True;
  ExpectTopic(S, 'cmdline.md', 'command line focused');
  S := Panels('file:///C:/');
  S.UserMenu := True;
  ExpectTopic(S, 'usermenu.md', 'user menu');
  S := Panels('file:///C:/');
  S.SortMenu := True;
  ExpectTopic(S, 'view.md', 'sort menu');
  S := Panels('file:///C:/');
  S.ColumnModeMenu := True;
  ExpectTopic(S, 'view.md', 'column modes menu');
  S := Panels('file:///C:/');
  S.DrivePopup := True;
  ExpectTopic(S, 'drives.md', 'drive popup');
  S := Panels('file:///C:/');
  S.SearchActive := True;
  ExpectTopic(S, 'search.md', 'search progress');
  S := Panels('file:///C:/');
  S.JobOverlay := True;
  ExpectTopic(S, 'jobs.md', 'job popup');

  S := Default(THelpScreen);
  S.WorkspaceKind := wkDocument;
  ExpectTopic(S, 'viewer.md', 'viewer / editor tab');
  S.WorkspaceKind := wkTerminal;
  ExpectTopic(S, 'terminals.md', 'terminal tab');

  // Priority: console > top menu > dialog > workspace > overlays.
  S := Panels('file:///C:/a.zip!/');
  S.UserMenu := True;
  S.DialogKind := hdkUserMenuEdit;
  S.TopMenuActive := True;
  ExpectTopic(S, 'topmenu.md', 'top menu wins over a dialog');
  S.TopMenuActive := False;
  ExpectTopic(S, 'usermenu.md', 'dialog wins over the panel');
  S.DialogKind := hdkSetAttributes;
  S.WorkspaceKind := wkDocument;
  ExpectTopic(S, 'fileops.md', 'dialog over a document tab');
  S.ConsoleMode := True;
  ExpectTopic(S, 'cmdline.md', 'console mode');

  Assert.IsTrue(DialogKindTakesF1(hdkKeymapEdit), 'keymap key field records F1');
  Assert.IsTrue(not DialogKindTakesF1(hdkSetAttributes), 'ordinary dialog gives F1 to help');
end;

procedure TestEveryTopicExists;
var
  K: THostDialogKind;
  Topic, Lang: string;
  Missing: Integer;
begin
  Missing := 0;
  for Lang in ['en', 'ru', 'de'] do
  begin
    Assert.IsTrue(TDirectory.Exists(HelpDir(Lang)), 'help folder ' + HelpDir(Lang));
    for K := Succ(hdkNone) to High(THostDialogKind) do
    begin
      Topic := HelpTopicForDialog(K);
      if Topic = '' then
      begin
        if K <> hdkHelp then
        begin
          Inc(Missing);
          Assert.IsTrue(False, 'dialog kind ' + IntToStr(Ord(K)) + ' has a topic');
        end;
        Continue;
      end;
      if not TFile.Exists(TPath.Combine(HelpDir(Lang), Topic)) then
      begin
        Inc(Missing);
        Assert.IsTrue(False, Lang + '\' + Topic + ' exists');
      end;
    end;
    for Topic in ['panels.md', 'archives.md', 'ssh.md', 'drives.md', 'search.md',
      'workspaces.md', 'cmdline.md', 'usermenu.md', 'view.md', 'jobs.md',
      'viewer.md', 'terminals.md', 'topmenu.md'] do
      if not TFile.Exists(TPath.Combine(HelpDir(Lang), Topic)) then
      begin
        Inc(Missing);
        Assert.IsTrue(False, Lang + '\' + Topic + ' exists');
      end;
  end;
  Assert.IsTrue(Missing = 0, 'every dialog kind (but the built-in help) maps to an existing topic');
end;

procedure TestMenuActionTopics;
const
  cSamples: array[0..11] of array[0..1] of string = (
    ('tmaFileCopy', 'fileops.md'),
    ('tmaFileSelectAll', 'selection.md'),
    ('tmaFilePack', 'archives.md'),
    ('tmaEditFind', 'text.md'),
    ('tmaLeftSort', 'view.md'),
    ('tmaLeftNewTab', 'panels.md'),
    ('tmaCmdFolderHistory', 'history.md'),
    ('tmaCmdSyncConsoleDir', 'cmdline.md'),
    ('tmaCmdDirSync', 'sync.md'),
    ('tmaOptTheme', 'settings.md'),
    ('plugin:x:Do it', 'topmenu.md'),
    ('tmaCmdPalette', 'topmenu.md'));
var
  I: Integer;
  S: THelpScreen;
  Lang: string;
begin
  for I := Low(cSamples) to High(cSamples) do
  begin
    Assert.AreEqual(cSamples[I][1], HelpTopicForMenuAction(cSamples[I][0]), cSamples[I][0]);
    for Lang in ['en', 'ru', 'de'] do
      Assert.IsTrue(TFile.Exists(TPath.Combine(HelpDir(Lang), cSamples[I][1])),
        Lang + '' + cSamples[I][1] + ' exists');
  end;
  S := Default(THelpScreen);
  S.DialogKind := hdkCommandPalette;
  ExpectTopic(S, 'topmenu.md', 'the palette without a choice');
  S.DialogTopic := 'fileops.md';
  ExpectTopic(S, 'fileops.md', 'the palette asks for the topic of its command');
end;

{ TTestHelpContext }

procedure TTestHelpContext.SetupFixture;
begin
end;

procedure TTestHelpContext.TestScreens;
begin
  TestHelpContext.TestScreens;
end;

procedure TTestHelpContext.TestMenuActionTopics;
begin
  TestHelpContext.TestMenuActionTopics;
end;

procedure TTestHelpContext.TestEveryTopicExists;
begin
  TestHelpContext.TestEveryTopicExists;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHelpContext);

end.
