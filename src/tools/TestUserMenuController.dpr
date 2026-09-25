program TestUserMenuController;

{$APPTYPE CONSOLE}

{ Behavior checks for the F2 user menu: the TUserMenuController popup
  (navigation over separators, submenus, hotkeys in either keyboard layout,
  editing requests, clicks) and the uUserMenu model (JSON round trip, macro
  expansion, prompts). Draw() is not exercised: the project's test
  convention (see TestSortMenuController.dpr, ...) checks logic/state, not
  grid rendering. }

uses
  System.SysUtils, System.UITypes, System.Classes, System.IOUtils,
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uUserMenu in '..\Core\uUserMenu.pas',
  uUserMenuController in '..\Core\uUserMenuController.pas',
  uDualPanelUserMenu in '..\Core\uDualPanelUserMenu.pas',
  uFunctionBar in '..\Core\uFunctionBar.pas';

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

function FixedPanelBounds(ASide: TPanelSide): TRectI;
begin
  Result := TRectI.Make(0, 0, 79, 24); // 80x25, plenty of room for the popup
end;

function ActiveSideLeft: TPanelSide;
begin
  Result := psLeft;
end;

type
  TActionSpy = class
    Count: Integer;
    LastAction: TUserMenuAction;
    LastParent: TUserMenuItem;
    LastIndex: Integer;
    procedure OnAction(AAction: TUserMenuAction; AParent: TUserMenuItem;
      AIndex: Integer);
  end;

procedure TActionSpy.OnAction(AAction: TUserMenuAction; AParent: TUserMenuItem;
  AIndex: Integer);
begin
  Inc(Count);
  LastAction := AAction;
  LastParent := AParent;
  LastIndex := AIndex;
end;

function Item(AKind: TUserMenuKind; const AHot, ACaption, ACommand: string): TUserMenuItem;
begin
  Result := TUserMenuItem.Create(AKind);
  Result.HotKey := AHot;
  Result.Caption := ACaption;
  Result.Command := ACommand;
end;

// 0 B Alpha / 1 ---- / 2 S Sub > (0 X Inner) / 3 (Cyrillic EF) Cyrillic
function SampleMenu: TUserMenuItem;
var
  Sub: TUserMenuItem;
begin
  Result := TUserMenuItem.Create(umkSubmenu);
  Result.Items.Add(Item(umkCommand, 'B', 'Alpha', 'echo a'));
  Result.Items.Add(Item(umkSeparator, '', '', ''));
  Sub := Item(umkSubmenu, 'S', 'Sub', '');
  Sub.Items.Add(Item(umkCommand, 'X', 'Inner', 'echo x'));
  Result.Items.Add(Sub);
  Result.Items.Add(Item(umkCommand, #$0424, 'Cyrillic', 'echo f'));
end;

procedure Press(ACtrl: TUserMenuController; AKey: Word; AChar: Char = #0;
  AShift: TShiftState = []);
var
  Key: Word;
  Ch: Char;
begin
  Key := AKey;
  Ch := AChar;
  ACtrl.HandleInput(Key, AShift, Ch);
end;

procedure TestNavigationAndSubmenus;
var
  Root: TUserMenuItem;
  Spy: TActionSpy;
  Ctrl: TUserMenuController;
begin
  Writeln('Navigation skips separators, Enter/Right/Left/Esc walk submenus');
  Root := SampleMenu;
  Spy := TActionSpy.Create;
  Ctrl := TUserMenuController.Create(nil, nil, Spy.OnAction, FixedPanelBounds,
    ActiveSideLeft);
  try
    Ctrl.Open(Root);
    Expect(Ctrl.Visible and (Ctrl.ItemIndex = 0), 'opens on the first item');
    Press(Ctrl, vkDown);
    Expect(Ctrl.ItemIndex = 2, 'Down skips the separator');
    Press(Ctrl, vkRight);
    Expect(Ctrl.CurrentMenu = Root.Items[2], 'Right enters the submenu');
    Expect(Ctrl.ItemIndex = 0, 'submenu opens on its first item');
    Press(Ctrl, vkLeft);
    Expect((Ctrl.CurrentMenu = Root) and (Ctrl.ItemIndex = 2),
      'Left returns to the parent, cursor on the submenu row');
    Press(Ctrl, vkReturn);
    Expect(Ctrl.CurrentMenu = Root.Items[2], 'Enter on a submenu enters it too');
    Press(Ctrl, vkEscape);
    Expect(Ctrl.Visible and (Ctrl.CurrentMenu = Root), 'Esc in a submenu goes up');
    Press(Ctrl, vkEnd);
    Expect(Ctrl.ItemIndex = 3, 'End goes to the last item');
    Press(Ctrl, vkHome);
    Expect(Ctrl.ItemIndex = 0, 'Home goes to the first item');
    Press(Ctrl, vkNext);
    Expect(Ctrl.ItemIndex = 3, 'PgDn past the end stops on the last item');
    Expect(Spy.Count = 0, 'navigation fires no actions');
    Press(Ctrl, vkEscape);
    Expect(not Ctrl.Visible, 'Esc at top level closes');
  finally
    Ctrl.Free;
    Spy.Free;
    Root.Free;
  end;
end;

procedure TestExecuteAndHotkeys;
var
  Root: TUserMenuItem;
  Spy: TActionSpy;
  Ctrl: TUserMenuController;
begin
  Writeln('Enter / hotkeys run commands and close the popup');
  Root := SampleMenu;
  Spy := TActionSpy.Create;
  Ctrl := TUserMenuController.Create(nil, nil, Spy.OnAction, FixedPanelBounds,
    ActiveSideLeft);
  try
    Ctrl.Open(Root);
    Press(Ctrl, vkReturn);
    Expect((Spy.LastAction = umaExecute) and (Spy.LastParent = Root) and
      (Spy.LastIndex = 0), 'Enter executes the item under the cursor');
    Expect(not Ctrl.Visible, 'executing closes the popup');

    Ctrl.Open(Root);
    Press(Ctrl, 0, 's');
    Expect(Ctrl.CurrentMenu = Root.Items[2], 'lower-case hotkey opens its submenu');
    Press(Ctrl, 0, 'x');
    Expect((Spy.LastAction = umaExecute) and (Spy.LastParent = Root.Items[2]) and
      (Spy.LastIndex = 0), 'hotkey inside a submenu executes its item');

    Ctrl.Open(Root);
    Press(Ctrl, 0, 'b');
    Expect(Spy.LastIndex = 0, 'Latin hotkey runs its item');
    Ctrl.Open(Root);
    // Cyrillic EF sits on the A key of the Latin layout.
    Press(Ctrl, 0, 'a');
    Expect(Spy.LastIndex = 3, 'hotkey fires from the other keyboard layout');
  finally
    Ctrl.Free;
    Spy.Free;
    Root.Free;
  end;
end;

procedure TestEditRequestsAndMove;
var
  Root: TUserMenuItem;
  Spy: TActionSpy;
  Ctrl: TUserMenuController;
  First: TUserMenuItem;
begin
  Writeln('Ins / F4 / Del ask the host; Ctrl+Up/Down reorder in place');
  Root := SampleMenu;
  Spy := TActionSpy.Create;
  Ctrl := TUserMenuController.Create(nil, nil, Spy.OnAction, FixedPanelBounds,
    ActiveSideLeft);
  try
    Ctrl.Open(Root);
    Press(Ctrl, vkInsert);
    Expect((Spy.LastAction = umaInsert) and (Spy.LastIndex = 0), 'Ins inserts before the cursor');
    Press(Ctrl, vkF4);
    Expect((Spy.LastAction = umaEdit) and (Spy.LastIndex = 0), 'F4 edits the cursor item');
    Press(Ctrl, vkDelete);
    Expect((Spy.LastAction = umaDelete) and (Spy.LastIndex = 0), 'Del deletes the cursor item');
    Expect(Ctrl.Visible, 'editing requests keep the popup open');

    First := Root.Items[0];
    Press(Ctrl, vkDown, #0, [ssCtrl]);
    Expect((Root.Items[1] = First) and (Ctrl.ItemIndex = 1), 'Ctrl+Down moves the item down');
    Expect(Spy.LastAction = umaMoved, 'a move asks the host to save');
    Press(Ctrl, vkUp, #0, [ssCtrl]);
    Expect(Root.Items[0] = First, 'Ctrl+Up moves it back');
    Press(Ctrl, vkF2, #0, [ssShift]);
    Expect(Spy.LastAction = umaSwitchMenu, 'Shift+F2 asks for the other menu');
    Press(Ctrl, vkF2);
    Expect(Spy.LastAction = umaSwitchMenu, 'plain F2 is not a menu switch request');

    Root.Items.Clear;
    Ctrl.ItemsChanged(0);
    Press(Ctrl, vkInsert);
    Expect((Spy.LastAction = umaInsert) and (Spy.LastIndex = 0), 'Ins works in an empty menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Root.Free;
  end;
end;

procedure TestClicks;
var
  Root: TUserMenuItem;
  Spy: TActionSpy;
  Ctrl: TUserMenuController;
  B: TRectI;
begin
  Writeln('Clicks: row activates, separator ignored, outside closes');
  Root := SampleMenu;
  Spy := TActionSpy.Create;
  Ctrl := TUserMenuController.Create(nil, nil, Spy.OnAction, FixedPanelBounds,
    ActiveSideLeft);
  try
    Ctrl.Open(Root);
    B := Ctrl.Bounds;
    Ctrl.HandleClick(B.Left + 3, B.Top + 2); // separator row
    Expect(Ctrl.Visible and (Spy.Count = 0), 'click on a separator does nothing');
    Ctrl.HandleClick(B.Left + 3, B.Top + 3); // submenu row
    Expect(Ctrl.CurrentMenu = Root.Items[2], 'click on a submenu row enters it');
    Ctrl.HandleClick(B.Left + 3, B.Top + 1); // first inner item
    Expect((Spy.LastAction = umaExecute) and not Ctrl.Visible,
      'click on a command row runs it and closes');
    Ctrl.Open(Root);
    Ctrl.HandleClick(79, 24);
    Expect(not Ctrl.Visible, 'click outside closes');
  finally
    Ctrl.Free;
    Spy.Free;
    Root.Free;
  end;
end;

procedure TestJsonRoundTrip;
var
  Root, Back: TUserMenuItem;
  Path: string;
begin
  Writeln('usermenu.json round trip');
  Root := SampleMenu;
  try
    Back := UserMenuFromJson(UserMenuToJson(Root));
    try
      Expect(Assigned(Back) and (Back.Items.Count = 4), 'same number of items');
      Expect(Back.Items[1].Kind = umkSeparator, 'separator kept');
      Expect((Back.Items[2].Kind = umkSubmenu) and (Back.Items[2].Items.Count = 1) and
        (Back.Items[2].Items[0].Command = 'echo x'), 'submenu and its items kept');
      Expect(Back.Items[3].HotKey = #$0424, 'non-Latin hotkey kept');
    finally
      Back.Free;
    end;
    Expect(UserMenuFromJson('not json') = nil, 'garbage is rejected');

    Path := TPath.Combine(TPath.GetTempPath, 'mtn2-usermenu-test.json');
    Expect(SaveUserMenu(Path, Root), 'saves to disk');
    Back := LoadUserMenu(Path);
    try
      Expect(Back.Items.Count = 4, 'loads what it saved');
    finally
      Back.Free;
      TFile.Delete(Path);
    end;
    Back := LoadUserMenu(Path);
    try
      Expect(Back.Items.Count > 0, 'missing file gives the built-in examples');
    finally
      Back.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TestMacros;
var
  Ctx: TUserMenuContext;
  Prompts: TArray<TUserMenuPrompt>;
  ListPaths: TArray<string>;
  S: string;
begin
  Writeln('Macro expansion');
  Ctx.Active.Path := 'C:\Work';
  Ctx.Active.CurrentName := 'report.final.txt';
  Ctx.Active.SelectedNames := ['a.txt', 'my file.txt'];
  Ctx.Passive.Path := 'D:\Backup';
  Ctx.Passive.CurrentName := 'old.zip';
  Ctx.Passive.SelectedNames := ['old.zip'];

  Expect(ExpandUserMenuCommand('type !.!', Ctx, nil) = 'type report.final.txt', '!.! = name');
  Expect(ExpandUserMenuCommand('echo !', Ctx, nil) = 'echo report.final', '! = name w/o extension');
  Expect(ExpandUserMenuCommand('!\!.!', Ctx, nil) = 'C:\Work\report.final.txt', '!\ = folder');
  Expect(ExpandUserMenuCommand('!:', Ctx, nil) = 'C:', '!: = drive');
  Expect(ExpandUserMenuCommand('zip !&', Ctx, nil) = 'zip a.txt "my file.txt"',
    '!& lists and quotes the selection');
  Expect(ExpandUserMenuCommand('copy !.! !#!\', Ctx, nil) = 'copy report.final.txt D:\Backup\',
    '!# switches to the passive panel');
  Expect(ExpandUserMenuCommand('!#!.! !^!.!', Ctx, nil) = 'old.zip report.final.txt',
    '!^ switches back to the active panel');
  Expect(ExpandUserMenuCommand('echo hi!!', Ctx, nil) = 'echo hi!', '!! is a literal !');

  S := ExpandUserMenuCommand('7z a x.7z @!@!', Ctx, nil,
    function(const APaths: TArray<string>): string
    begin
      ListPaths := APaths;
      Result := 'LIST';
    end);
  Expect(S = '7z a x.7z @LIST', '!@! is replaced by the list file');
  Expect((Length(ListPaths) = 2) and (ListPaths[1] = 'C:\Work\my file.txt'),
    'list file gets full paths of the selection');

  Prompts := ParseUserMenuPrompts('git commit -m "!?Message?fix!" && echo !?Tag?!');
  Expect((Length(Prompts) = 2) and (Prompts[0].Title = 'Message') and
    (Prompts[0].Default = 'fix') and (Prompts[1].Title = 'Tag'), 'prompts are found in order');
  Expect(ExpandUserMenuCommand('m "!?Message?fix!" !?Tag?!', Ctx, ['hello', 'v1']) =
    'm "hello" v1', 'answers replace the prompts');
  Expect(ExpandUserMenuCommand('m !?Message?fix!', Ctx, nil) = 'm fix',
    'an unanswered prompt uses its default');
  Expect(ExpandUserMenuCommand('m !?broken', Ctx, nil) = 'm !?broken',
    'a malformed prompt is left as typed');
end;

procedure TestFolderMenus;
var
  Base, Sub, Deep, MainPath: string;
  Folder: string;
  Host: TUserMenuDialogController;
  Shown: TUserMenuItem;
  ShownTitle: string;
  Root: TUserMenuItem;
  Hit: TFunctionBarHit;
  Key: Word;
  Ch: Char;
  Shift: TShiftState;
begin
  Writeln('Folder menus: nearest .mtn2menu.json, Shift+F2 switches');
  Base := TPath.Combine(TPath.GetTempPath, 'mtn2-foldermenu-' + TPath.GetGUIDFileName);
  Sub := TPath.Combine(Base, 'proj');
  Deep := TPath.Combine(Sub, 'src');
  ForceDirectories(Deep);
  MainPath := TPath.Combine(Base, 'usermenu.json');
  try
    Expect(FindFolderUserMenu(Deep) = '', 'no folder menu anywhere yet');
    Root := TUserMenuItem.Create(umkSubmenu);
    try
      Root.Items.Add(Item(umkCommand, 'B', 'Build', 'make'));
      SaveUserMenu(FolderUserMenuPath(Sub), Root);
    finally
      Root.Free;
    end;
    Expect(SameText(FindFolderUserMenu(Deep), FolderUserMenuPath(Sub)),
      'a subfolder finds its ancestor''s menu');
    Expect(FindFolderUserMenu('') = '', 'no folder: no menu');
    Root := LoadUserMenu(FolderUserMenuPath(Deep), False);
    try
      Expect(Root.Items.Count = 0, 'missing folder menu loads empty, not the examples');
    finally
      Root.Free;
    end;

    Folder := Deep;
    Host := TUserMenuDialogController.Create(nil, nil, nil, nil, nil, nil,
      procedure(ARoot: TUserMenuItem; const ATitle: string)
      begin
        Shown := ARoot;
        ShownTitle := ATitle;
      end,
      nil,
      function: string
      begin
        Result := Folder;
      end);
    try
      Host.MainFilePath := MainPath;
      Host.OpenMenu;
      Expect((Host.Source = umsFolder) and (Shown.Items.Count = 1) and
        (Shown.Items[0].Caption = 'Build'), 'F2 opens the folder menu when there is one');
      Expect(Pos('proj', ShownTitle) > 0, 'its title names the folder that owns it');
      Host.HandleMenuAction(umaSwitchMenu, Shown, 0);
      Expect((Host.Source = umsMain) and SameText(Host.FilePath, MainPath),
        'Shift+F2 switches to the main menu');
      Host.HandleMenuAction(umaSwitchMenu, Shown, 0);
      Expect(Host.Source = umsFolder, 'and back to the folder menu');

      Folder := Base;
      Host.OpenMenu;
      Expect(Host.Source = umsMain, 'F2 outside the project opens the main menu');
      Host.HandleMenuAction(umaSwitchMenu, Shown, 0);
      Expect((Host.Source = umsFolder) and (Shown.Items.Count = 0) and
        SameText(Host.FilePath, FolderUserMenuPath(Base)),
        'switching where no menu exists shows an empty one for this folder');

      Folder := '';
      Host.OpenMenu;
      Host.HandleMenuAction(umaSwitchMenu, Shown, 0);
      Expect(Host.Source = umsMain, 'a non-local panel has only the main menu');
    finally
      Host.Free;
    end;
  finally
    TDirectory.Delete(Base, True);
  end;

  Hit.Kind := fbhHint;
  Hit.FKeyNum := 0;
  Hit.HintKey := 'Shift+F2';
  Expect(FunctionBarHitToInput(Hit, [], Key, Ch, Shift) and (Key = vkF2) and
    (ssShift in Shift), 'clicking the Shift+F2 hint sends Shift+F2');
end;

begin
  Failed := 0;
  try
    TestNavigationAndSubmenus;
    TestExecuteAndHotkeys;
    TestEditRequestsAndMove;
    TestClicks;
    TestJsonRoundTrip;
    TestMacros;
    TestFolderMenus;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.Message);
      Halt(2);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln(Failed, ' check(s) FAILED.');
  Halt(1);
end.
