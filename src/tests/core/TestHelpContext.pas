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
  System.TypInfo,
  uTopMenuBar,
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

/// <summary>True when ATopic (file.md or file.md#id) exists in ALang: the file,
/// and for an id a line that starts with the marker for it.</summary>
function TopicExists(const ALang, ATopic: string): Boolean;
var
  P: Integer;
  FileName, Id, Text: string;
begin
  P := Pos('#', ATopic);
  if P > 0 then
  begin
    FileName := Copy(ATopic, 1, P - 1);
    Id := Copy(ATopic, P + 1, MaxInt);
  end
  else
  begin
    FileName := ATopic;
    Id := '';
  end;
  FileName := TPath.Combine(HelpDir(ALang), FileName);
  Result := TFile.Exists(FileName);
  if Result and (Id <> '') then
  begin
    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Result := (Pos('<!--' + Id + '-->', Text) > 0) and
      ((Pos(#10 + '<!--' + Id + '-->', Text) > 0) or (Pos('<!--' + Id + '-->', Text) = 1));
  end;
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
  ExpectTopic(S, 'usermenu.md#item', 'dialog wins over the panel');
  S.DialogKind := hdkSetAttributes;
  S.WorkspaceKind := wkDocument;
  ExpectTopic(S, 'fileops.md#attributes', 'dialog over a document tab');
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
  for Lang in ['en', 'ru', 'de', 'zh'] do
  begin
    Assert.IsTrue(TDirectory.Exists(HelpDir(Lang)), 'help folder ' + HelpDir(Lang));
    for K := Succ(hdkNone) to High(THostDialogKind) do
    begin
      Topic := HelpTopicForDialog(K);
      if Topic = '' then
      begin
        if not (K in [hdkHelp, hdkHost]) then
        begin
          Inc(Missing);
          Assert.IsTrue(False, 'dialog kind ' + IntToStr(Ord(K)) + ' has a topic');
        end;
        Continue;
      end;
      if not TopicExists(Lang, Topic) then
      begin
        Inc(Missing);
        Assert.IsTrue(False, Lang + '\' + Topic + ' exists');
      end;
    end;
    for Topic in ['panels.md', 'archives.md', 'ssh.md', 'drives.md', 'search.md',
      'workspaces.md', 'cmdline.md', 'usermenu.md', 'view.md', 'jobs.md',
      'viewer.md', 'terminals.md', 'topmenu.md', 'environment.md'] do
      if not TopicExists(Lang, Topic) then
      begin
        Inc(Missing);
        Assert.IsTrue(False, Lang + '\' + Topic + ' exists');
      end;
  end;
  Assert.IsTrue(Missing = 0, 'every dialog kind (but the built-in help and host dialogs) maps to an existing topic');
end;

procedure TestMenuActionTopics;
const
  cSamples: array[0..16] of array[0..1] of string = (
    ('tmaFileCopy', 'fileops.md'),
    ('tmaFileSelectAll', 'selection.md'),
    ('tmaFilePack', 'archives.md#pack'),
    ('tmaEditFind', 'text.md'),
    ('tmaLeftSort', 'view.md'),
    ('tmaLeftNewTab', 'panels.md'),
    ('tmaCmdFolderHistory', 'history.md'),
    ('tmaCmdSyncConsoleDir', 'cmdline.md'),
    ('tmaCmdDirSync', 'sync.md#dir-sync'),
    ('tmaOptTheme', 'settings.md#theme'),
    ('plugin:x:Do it', 'topmenu.md'),
    ('tmaCmdPalette', 'topmenu.md'),
    ('tmaFileJobList', 'jobs.md#job-list'),
    ('tmaFileExternalView', 'viewer.md'),
    ('tmaCmdLiveFilter', 'search.md'),
    ('tmaCmdJobList', 'jobs.md#job-list'),
    ('tmaOptEnvironment', 'environment.md'));
var
  I: Integer;
  S: THelpScreen;
  Lang, Name: string;
  A: TTopMenuAction;
begin
  for I := Low(cSamples) to High(cSamples) do
  begin
    Assert.AreEqual(cSamples[I][1], HelpTopicForMenuAction(cSamples[I][0]), cSamples[I][0]);
    for Lang in ['en', 'ru', 'de', 'zh'] do
      Assert.IsTrue(TopicExists(Lang, cSamples[I][1]),
        Lang + '' + cSamples[I][1] + ' exists');
  end;
  for A := Succ(Low(TTopMenuAction)) to High(TTopMenuAction) do
  begin
    Name := GetEnumName(TypeInfo(TTopMenuAction), Ord(A));
    for Lang in ['en', 'ru', 'de', 'zh'] do
      Assert.IsTrue(TopicExists(Lang, HelpTopicForMenuAction(Name)),
        Lang + ' ' + HelpTopicForMenuAction(Name) + ' for ' + Name + ' exists');
  end;
  S := Default(THelpScreen);
  S.DialogKind := hdkCommandPalette;
  ExpectTopic(S, 'topmenu.md', 'the palette without a choice');
  S.DialogTopic := 'fileops.md';
  ExpectTopic(S, 'fileops.md', 'the palette asks for the topic of its command');

  S := Default(THelpScreen);
  S.DialogKind := hdkExternalTools;
  ExpectTopic(S, 'settings.md#external-tools', 'external viewer/editor dialog');
  S.DialogKind := hdkPanelFilter;
  ExpectTopic(S, 'search.md', 'panel filter dialog');
  S.DialogKind := hdkTerminalEnv;
  ExpectTopic(S, 'environment.md#choice', 'environment profile choice');
  S.DialogKind := hdkDisplay;
  ExpectTopic(S, 'settings.md#display', 'display dialog');
  S.DialogKind := hdkHost;
  ExpectTopic(S, '', 'host dialog without a topic');
  S.DialogTopic := 'updates.md';
  ExpectTopic(S, 'updates.md', 'host dialog with the topic its opener named');
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
