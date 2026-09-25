program TestHelpContext;

{$APPTYPE CONSOLE}

{ Context F1: the help topic chosen for what is on screen, and that every
  topic named exists in both shipped languages (bin\help\en, bin\help\ru). }

uses
  System.SysUtils,
  System.IOUtils,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uHelpContext;

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

procedure ExpectTopic(const AScreen: THelpScreen; const ATopic, AMsg: string);
var
  Got: string;
begin
  Got := HelpTopicForScreen(AScreen);
  Expect(Got = ATopic, AMsg + ' -> ' + ATopic + ' (got ' + Got + ')');
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
    '..\..\bin\help\' + ALang));
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

  Expect(DialogKindTakesF1(hdkKeymapEdit), 'keymap key field records F1');
  Expect(not DialogKindTakesF1(hdkSetAttributes), 'ordinary dialog gives F1 to help');
end;

procedure TestEveryTopicExists;
var
  K: THostDialogKind;
  Topic, Lang: string;
  Missing: Integer;
begin
  Missing := 0;
  for Lang in ['en', 'ru'] do
  begin
    Expect(TDirectory.Exists(HelpDir(Lang)), 'help folder ' + HelpDir(Lang));
    for K := Succ(hdkNone) to High(THostDialogKind) do
    begin
      Topic := HelpTopicForDialog(K);
      if Topic = '' then
      begin
        if K <> hdkHelp then
        begin
          Inc(Missing);
          Expect(False, 'dialog kind ' + IntToStr(Ord(K)) + ' has a topic');
        end;
        Continue;
      end;
      if not TFile.Exists(TPath.Combine(HelpDir(Lang), Topic)) then
      begin
        Inc(Missing);
        Expect(False, Lang + '\' + Topic + ' exists');
      end;
    end;
    for Topic in ['panels.md', 'archives.md', 'ssh.md', 'drives.md', 'search.md',
      'workspaces.md', 'cmdline.md', 'usermenu.md', 'view.md', 'jobs.md',
      'viewer.md', 'terminals.md', 'topmenu.md'] do
      if not TFile.Exists(TPath.Combine(HelpDir(Lang), Topic)) then
      begin
        Inc(Missing);
        Expect(False, Lang + '\' + Topic + ' exists');
      end;
  end;
  Expect(Missing = 0, 'every dialog kind (but the built-in help) maps to an existing topic');
end;

begin
  Failed := 0;
  try
    TestScreens;
    TestEveryTopicExists;
    if Failed = 0 then
      Writeln('All HelpContext tests PASSED')
    else
    begin
      Writeln('FAILED: ', Failed, ' check(s)');
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
