unit TestCommandPalette;

{ The command palette (Shift+F9): the list of menu commands, the search over
  their captions and aliases, and the dialog that runs the chosen one. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandPalette = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestListsOnlyTheCommandsThatCanRun;
    [Test] procedure TestShellFindsBackgroundConsoleInEveryLanguage;
    [Test] procedure TestEveryWordOfTheQueryMustMatch;
    [Test] procedure TestCaptionStartRanksBeforeInnerMatch;
    [Test] procedure TestInitialsFindACommand;
    [Test] procedure TestWildcardsStandForCharacters;
    [Test] procedure TestMenuJsonAliasesAreSearchWords;
    [Test] procedure TestUserAliasesFileAddsWords;
    [Test] procedure TestContextLineShowsHintOrNeighbours;
    [Test] procedure TestContextLineFollowsTheSelectedItem;
    [Test] procedure TestRecentCommandsComeFirstWithEmptyQuery;
    [Test] procedure TestRowTextFillsTheWidth;
    [Test] procedure TestRunItemRunsOnlyEnabledCommands;
    [Test] procedure TestShiftF9IsBoundToThePalette;
    [Test] procedure TestTypingNarrowsTheListAndEnterRuns;
    [Test] procedure TestEnterOnEmptyResultRunsNothing;
    [Test] procedure TestCtrlKOpensTheKeyListOnTheCommand;
    [Test] procedure TestCtrlKOnACommandWithoutKeyKeepsThePalette;
    [Test] procedure TestResumeKeepsTheSelectedCommand;
    [Test] procedure TestKeysWithoutMenuItemAreListedWithTheirShortcut;
    [Test] procedure TestKeyOnlyCommandRunsItsAction;
    [Test] procedure TestShortcutColumnIsSearched;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uStrings, uKeymap, uCharWidth, uTopMenuBar, uCommandPalette,
  uDialogHost, uDualPanelUiTypes, uDualPanelPaletteDialog, uDualPanelKeymapDialog;

const
  cMenuJson =
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Copy","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"},' +
    '{"isSeparator":true},' +
    '{"caption":"Copy full path","hotChar":"P","shortcut":"","action":"tmaFileCopyPath"},' +
    '{"caption":"Move","hotChar":"M","shortcut":"F6","action":"tmaFileMove","aliases":"transfer, relocate"},' +
    '{"caption":"Delete","hotChar":"D","shortcut":"F8","action":"tmaFileDelete"}' +
    ']}]}';

var
  GExecuted: TTopMenuAction;
  GExecutedCount: Integer;
  GDisabled: TTopMenuAction;

function MakeMenu(const AJson: string = ''): TTopMenuController;
begin
  GExecuted := tmaNone;
  GExecutedCount := 0;
  GDisabled := tmaNone;
  Result := TTopMenuController.Create(nil, nil,
    procedure(AAction: TTopMenuAction)
    begin
      GExecuted := AAction;
      Inc(GExecutedCount);
    end);
  Result.OnIsActionEnabled :=
    function(AAction: TTopMenuAction): Boolean
    begin
      Result := AAction <> GDisabled;
    end;
  if AJson <> '' then
    Assert.IsTrue(Result.LoadMenuFromJson(AJson), 'test menu parses');
end;

function IndexOfKey(const AEntries: TArray<TPaletteEntry>; const AKey: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AEntries) do
    if AEntries[I].Key = AKey then
      Exit(I);
  Result := -1;
end;

function RankedKeys(const AEntries: TArray<TPaletteEntry>; const AQuery: string): TArray<string>;
var
  Ranked: TArray<Integer>;
  I: Integer;
begin
  Ranked := PaletteRank(AEntries, AQuery);
  SetLength(Result, Length(Ranked));
  for I := 0 to High(Ranked) do
    Result[I] := AEntries[Ranked[I]].Key;
end;

function Contains(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  K: string;
begin
  for K in AKeys do
    if K = AKey then
      Exit(True);
  Result := False;
end;

procedure TTestCommandPalette.Setup;
begin
  SetLocale('en');
  PaletteForgetRecent;
end;

procedure TTestCommandPalette.TearDown;
begin
  SetLocale('en');
  PaletteForgetRecent;
end;

procedure TTestCommandPalette.TestListsOnlyTheCommandsThatCanRun;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Assert.AreEqual<Integer>(4, Length(E), 'the separator is not a command');
    Assert.AreEqual('Copy', E[0].Title);
    Assert.AreEqual('Files', E[0].Category);
    Assert.AreEqual('F5', E[0].Shortcut);
    GDisabled := tmaFileMove;
    E := BuildPaletteEntries(M);
    Assert.AreEqual<Integer>(3, Length(E), 'a command that cannot run now is left out');
    Assert.AreEqual<Integer>(-1, IndexOfKey(E, 'tmaFileMove'));
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestShellFindsBackgroundConsoleInEveryLanguage;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu;
  try
    E := BuildPaletteEntries(M);
    Assert.IsTrue(Contains(RankedKeys(E, 'shell'), 'tmaCmdConsoleProfile'),
      'the English alias finds the command in an English menu');
    Assert.IsFalse(Contains(RankedKeys(E, 'оболочка'), 'tmaCmdConsoleProfile'),
      'the Russian words belong to the Russian locale');
    SetLocale('ru');
    M.BuildMenuStructure;
    E := BuildPaletteEntries(M);
    Assert.IsTrue(Contains(RankedKeys(E, 'shell'), 'tmaCmdConsoleProfile'),
      'the English alias finds the command in a Russian menu');
    Assert.IsTrue(Contains(RankedKeys(E, 'оболочка'), 'tmaCmdConsoleProfile'),
      'the Russian alias finds it in a Russian menu');
    Assert.IsTrue(Contains(RankedKeys(E, 'фонов'), 'tmaCmdConsoleProfile'),
      'the translated caption finds it');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestEveryWordOfTheQueryMustMatch;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Keys: TArray<string>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Keys := RankedKeys(E, 'copy path');
    Assert.AreEqual<Integer>(1, Length(Keys));
    Assert.AreEqual('tmaFileCopyPath', Keys[0]);
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'copy zzz')), 'one unmatched word rejects the entry');
    Assert.AreEqual<Integer>(Length(E), Length(RankedKeys(E, '  ')), 'blank text lists everything');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestCaptionStartRanksBeforeInnerMatch;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Keys: TArray<string>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Keys := RankedKeys(E, 'p');
    Assert.AreEqual('tmaFileCopyPath', Keys[0], 'a word that starts with p');
    Keys := RankedKeys(E, 'co');
    Assert.AreEqual('tmaFileCopy', Keys[0], 'ties keep the menu order');
    Assert.AreEqual('tmaFileCopyPath', Keys[1]);
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestInitialsFindACommand;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu;
  try
    E := BuildPaletteEntries(M);
    Assert.IsTrue(Contains(RankedKeys(E, 'bc'), 'tmaCmdConsoleProfile'),
      'the initials of "Background console" find it');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestWildcardsStandForCharacters;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Keys: TArray<string>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Keys := RankedKeys(E, 'c?py');
    Assert.IsTrue(Contains(Keys, 'tmaFileCopy') and Contains(Keys, 'tmaFileCopyPath'),
      '? stands for one character');
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'c?y')), '? is exactly one character');
    Keys := RankedKeys(E, 'mo*e');
    Assert.AreEqual('tmaFileMove', Keys[0], '* stands for a run of characters');
    Keys := RankedKeys(E, 'co*path');
    Assert.AreEqual<Integer>(1, Length(Keys));
    Assert.AreEqual('tmaFileCopyPath', Keys[0], '* crosses the words of a caption');
    Assert.AreEqual<Integer>(Length(E), Length(RankedKeys(E, '*')), 'a lone * matches all');
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'z*')));
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'mo*e copy')),
      'every word still has to match');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestMenuJsonAliasesAreSearchWords;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M, 'no-such-aliases.json');
    Assert.AreEqual('tmaFileMove', RankedKeys(E, 'transfer')[0]);
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'clone')), 'a word nobody lists finds nothing');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestContextLineShowsHintOrNeighbours;
const
  cJson =
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Copy","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"},' +
    '{"caption":"Move","hotChar":"M","shortcut":"F6","action":"tmaFileMove","hint":"Moves the files."},' +
    '{"caption":"Delete","hotChar":"D","shortcut":"F8","action":"tmaFileDelete"}' +
    ']}]}';
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu(cJson);
  try
    E := BuildPaletteEntries(M);
    Assert.AreEqual('Moves the files.', PaletteContextText(E, IndexOfKey(E, 'tmaFileMove')),
      'a command with a hint shows it');
    Assert.AreEqual('Files: [Copy] | Move',
      PaletteContextText(E, IndexOfKey(E, 'tmaFileCopy')),
      'the first command has no previous neighbour');
    Assert.AreEqual('Files: Move | [Delete]',
      PaletteContextText(E, IndexOfKey(E, 'tmaFileDelete')),
      'the last command has no next neighbour');
    Assert.AreEqual('', PaletteContextText(E, -1), 'no selection, no line');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestUserAliasesFileAddsWords;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Path: string;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-test-aliases.json');
  M := MakeMenu(cMenuJson);
  try
    TFile.WriteAllText(Path,
      '{"//": "note", "tmaFileCopy": ["clone", "dup"], "tmaFileDelete": "shred, zap"}',
      TEncoding.UTF8);
    E := BuildPaletteEntries(M, Path);
    Assert.AreEqual('tmaFileCopy', RankedKeys(E, 'clone')[0], 'a list of words');
    Assert.AreEqual('tmaFileDelete', RankedKeys(E, 'zap')[0], 'a comma separated string');
    Assert.AreEqual('tmaFileMove', RankedKeys(E, 'transfer')[0], 'the built-in words stay');
    Assert.AreEqual<Integer>(0, Length(RankedKeys(E, 'note')), 'a "//" key is a comment');

    TFile.WriteAllText(Path, 'not json', TEncoding.UTF8);
    E := BuildPaletteEntries(M, Path);
    Assert.AreEqual<Integer>(4, Length(E), 'a malformed file adds nothing and breaks nothing');
    Assert.AreEqual('tmaFileMove', RankedKeys(E, 'transfer')[0]);
  finally
    TFile.Delete(Path);
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestRecentCommandsComeFirstWithEmptyQuery;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Keys: TArray<string>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Assert.AreEqual('tmaFileCopy', RankedKeys(E, '')[0], 'menu order when nothing was run');
    PaletteNoteRun('tmaFileDelete');
    PaletteNoteRun('tmaFileMove');
    Keys := RankedKeys(E, '');
    Assert.AreEqual('tmaFileMove', Keys[0], 'the newest first');
    Assert.AreEqual('tmaFileDelete', Keys[1]);
    Assert.AreEqual('tmaFileCopy', Keys[2]);
    Assert.AreEqual<Integer>(Length(E), Length(Keys));
    Assert.AreEqual('tmaFileMove', RankedKeys(E, 'm')[0]);
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestRowTextFillsTheWidth;
var
  E: TPaletteEntry;
begin
  E.Title := 'A caption that is much longer than the column it is drawn in, so it is cut';
  E.Category := 'Commands';
  E.Shortcut := 'Ctrl+Alt+O';
  Assert.AreEqual<Integer>(76, TextDisplayWidth(PaletteRowText(E, 76)));
  E.Title := 'Short';
  Assert.AreEqual<Integer>(76, TextDisplayWidth(PaletteRowText(E, 76)));
  E.Title := #$547D#$4EE4#$9762#$677F;
  Assert.AreEqual<Integer>(76, TextDisplayWidth(PaletteRowText(E, 76)), 'wide characters count two cells');
end;

procedure TTestCommandPalette.TestRunItemRunsOnlyEnabledCommands;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    Assert.IsTrue(M.RunItem(E[IndexOfKey(E, 'tmaFileMove')].Item));
    Assert.AreEqual(Ord(tmaFileMove), Ord(GExecuted));
    GDisabled := tmaFileMove;
    GExecuted := tmaNone;
    Assert.IsFalse(M.RunItem(E[IndexOfKey(E, 'tmaFileMove')].Item), 'it became unavailable');
    Assert.AreEqual(Ord(tmaNone), Ord(GExecuted));
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestShiftF9IsBoundToThePalette;
var
  Profile: TKeymapProfile;
begin
  Profile := GetDefaultNDNProfile;
  Assert.AreEqual(Ord(kaCommandPalette),
    Ord(MatchActionIn(Profile, [kcGlobal], vkF9, [ssShift])));
  Assert.AreEqual(Ord(kaTopMenu), Ord(MatchActionIn(Profile, [kcGlobal], vkF9, [])),
    'F9 still opens the menu');
  Assert.AreEqual(Ord(kcGlobal), Ord(KeymapActionContext(kaCommandPalette)));
  Profile := GetDefaultFARProfile;
  Assert.AreEqual(Ord(kaCommandPalette),
    Ord(MatchActionIn(Profile, [kcGlobal], vkF9, [ssShift])));
end;

var
  GKind: THostDialogKind;

function MakePalette(ADialog: TDialogHost; AMenu: TTopMenuController): TCommandPaletteDialogController;
begin
  GKind := hdkNone;
  Result := TCommandPaletteDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string)
    begin
    end,
    procedure(AKind: THostDialogKind)
    begin
      GKind := AKind;
    end,
    procedure
    begin
    end,
    function: Boolean
    begin
      Result := True;
    end,
    procedure
    begin
    end,
    function: TTopMenuController
    begin
      Result := AMenu;
    end);
end;

procedure TTestCommandPalette.TestCtrlKOpensTheKeyListOnTheCommand;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  K: TKeymapDialogController;
  Key: Word;
  Ch: Char;
  Asked: TKeymapAction;
  Sel: Integer;
  I: Integer;
begin
  M := MakeMenu(cMenuJson);
  D := TDialogHost.Create(nil);
  K := nil;
  try
    C := MakePalette(D, M);
    K := TKeymapDialogController.Create(D,
      procedure(const AControlId, AValuesJson: string) begin end,
      procedure(AKind: THostDialogKind) begin end,
      procedure begin end,
      function: Boolean begin Result := True; end,
      procedure begin end);
    try
      Asked := kaNone;
      C.OnAssignKey :=
        function(AAction: TKeymapAction): Boolean
        begin
          Asked := AAction;
          K.OpenList(AAction);
          Result := True;
        end;
      C.OpenList;
      for I := 1 to 4 do
      begin
        Key := 0;
        Ch := 'move'[I];
        C.HandleFilterInput(Key, [], Ch);
      end;
      Key := Ord('K');
      Ch := #0;
      Assert.IsTrue(C.HandleFilterInput(Key, [ssCtrl], Ch), 'Ctrl+K is taken by the palette');
      Assert.AreEqual(Ord(TopMenuKeymapAction(tmaFileMove)), Ord(Asked),
        'the key list is asked for the action of the selected command');
      Assert.AreNotEqual(Ord(kaNone), Ord(Asked));
      Assert.AreEqual<Integer>(0, C.RowCount, 'the palette is closed');
      Sel := D.GetListSelectedIndex('actions');
      Assert.IsTrue(Sel > 1, 'the list is scrolled to the command, not left at the top');
      for I := 0 to D.ControlCount - 1 do
        if D.GetControl(I).Id = 'actions' then
          Assert.IsTrue(Pos(KeymapActionCaption(Asked), D.GetControl(I).Items[Sel]) > 0,
            'the selected row is the command');

      // Closing the key list brings the palette back as it was left.
      K.OnListClosed :=
        procedure
        begin
          C.Resume;
        end;
      GKind := hdkNone;
      K.DispatchCommand(hdkKeymap, 'cancel');
      Assert.AreEqual(Ord(hdkCommandPalette), Ord(GKind), 'the palette is the open dialog again');
      Assert.AreEqual('move', D.GetInputValue('query'), 'the search text is kept');
      Assert.AreEqual<Integer>(1, C.RowCount, 'the same narrowed list');
      Assert.AreEqual<Integer>(0, D.GetListSelectedIndex('commands'), 'the same command is selected');
    finally
      K.Free;
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestResumeKeepsTheSelectedCommand;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Key: Word;
  Ch: Char;
  Before: Integer;
begin
  M := MakeMenu(cMenuJson);
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      C.OnAssignKey :=
        function(AAction: TKeymapAction): Boolean
        begin
          Result := True;
        end;
      C.OpenList;
      Key := vkDown;
      Ch := #0;
      D.HandleInput(Key, [], Ch);
      Key := vkDown;
      D.HandleInput(Key, [], Ch);
      Before := D.GetListSelectedIndex('commands');
      Assert.IsTrue(Before > 0, 'a command below the first is selected');
      Key := Ord('K');
      Ch := #0;
      C.HandleFilterInput(Key, [ssCtrl], Ch);
      Assert.AreEqual<Integer>(0, C.RowCount, 'the palette is left');
      C.Resume;
      Assert.AreEqual<Integer>(Before, D.GetListSelectedIndex('commands'),
        'the same command is selected on return');
    finally
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestCtrlKOnACommandWithoutKeyKeepsThePalette;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Key: Word;
  Ch: Char;
  Asked: TKeymapAction;
  Calls: Integer;
begin
  M := MakeMenu(
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Without key","hotChar":"W","shortcut":"","action":"tmaFileSelectByExt"}]}]}');
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      Assert.AreEqual(Ord(kaNone), Ord(TopMenuKeymapAction(tmaFileSelectByExt)),
        'the test command has no key of its own');
      Asked := kaCopy;
      Calls := 0;
      C.OnAssignKey :=
        function(AAction: TKeymapAction): Boolean
        begin
          Inc(Calls);
          Asked := AAction;
          Result := False;
        end;
      C.OpenList;
      Assert.IsTrue(C.RowCount > 0, 'the command is listed');
      Key := Ord('K');
      Ch := #0;
      Assert.IsTrue(C.HandleFilterInput(Key, [ssCtrl], Ch));
      Assert.AreEqual<Integer>(1, Calls);
      Assert.AreEqual(Ord(kaNone), Ord(Asked), 'a command with no key is reported as such');
      Assert.IsTrue(C.RowCount > 0, 'the palette stays open');
    finally
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestContextLineFollowsTheSelectedItem;
const
  cJson =
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Copy","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"},' +
    '{"caption":"Move","hotChar":"M","shortcut":"F6","action":"tmaFileMove","hint":"Moves the files."}' +
    ']}]}';
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Key: Word;
  Ch: Char;

  function ContextText: string;
  var
    I: Integer;
  begin
    Result := '<none>';
    for I := 0 to D.ControlCount - 1 do
      if D.GetControl(I).Id = 'context' then
        Exit(D.GetControl(I).Text);
  end;

begin
  M := MakeMenu(cJson);
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      C.OpenList;
      Assert.AreEqual('Files: [Copy] | Move', ContextText, 'the first item is selected');
      Key := vkDown;
      Ch := #0;
      D.HandleInput(Key, [], Ch);
      Assert.AreEqual<Integer>(1, D.GetListSelectedIndex('commands'), 'Down moves the list selection');
      Assert.AreEqual('Moves the files.', ContextText, 'moving the selection changes the line');
    finally
      C.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TTestCommandPalette.TestTypingNarrowsTheListAndEnterRuns;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Key: Word;
  Ch: Char;
  I: Integer;
begin
  M := MakeMenu(cMenuJson);
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      C.OpenList;
      Assert.AreEqual(Ord(hdkCommandPalette), Ord(GKind));
      Assert.AreEqual<Integer>(4, C.RowCount);
      Key := 0;
      Ch := 'd';
      Assert.IsTrue(C.HandleFilterInput(Key, [], Ch), 'a letter is consumed');
      Ch := 'e';
      C.HandleFilterInput(Key, [], Ch);
      Ch := 'l';
      C.HandleFilterInput(Key, [], Ch);
      Assert.AreEqual<Integer>(1, C.RowCount, 'only Delete contains del');
      Assert.AreEqual('del', D.GetInputValue('query'), 'the search text is shown in the field');
      Key := vkBack;
      Ch := #0;
      Assert.IsTrue(C.HandleFilterInput(Key, [], Ch));
      Key := vkBack;
      C.HandleFilterInput(Key, [], Ch);
      Key := vkBack;
      C.HandleFilterInput(Key, [], Ch);
      Assert.AreEqual<Integer>(4, C.RowCount, 'Backspace widens the list again');
      Key := 0;
      for I := 1 to 4 do
      begin
        Key := 0;
        Ch := 'move'[I];
        C.HandleFilterInput(Key, [], Ch);
      end;
      C.DispatchCommand('commands');
      Assert.AreEqual(Ord(tmaFileMove), Ord(GExecuted), 'Enter runs the listed command');
      Assert.AreEqual<Integer>(1, GExecutedCount);
      Assert.AreEqual('tmaFileMove', RankedKeys(BuildPaletteEntries(M), '')[0],
        'the command that ran is on top next time');
    finally
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestEnterOnEmptyResultRunsNothing;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Key: Word;
  Ch: Char;
begin
  M := MakeMenu(cMenuJson);
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      C.OpenList;
      Key := 0;
      Ch := 'z';
      C.HandleFilterInput(Key, [], Ch);
      Assert.AreEqual<Integer>(0, C.RowCount);
      C.DispatchCommand('commands');
      Assert.AreEqual<Integer>(0, GExecutedCount);
    finally
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestKeysWithoutMenuItemAreListedWithTheirShortcut;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  I: Integer;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    AppendKeymapOnlyEntries(M, KeymapActionCaption, E);
    I := IndexOfKey(E, 'key:RunInBackground');
    Assert.IsTrue(I >= 0, 'an action no menu item runs is listed');
    Assert.AreEqual(Ord(kaRunInBackground), Ord(E[I].Action));
    Assert.IsTrue(Pos('Enter', E[I].Shortcut) > 0, 'its keys are shown');
    Assert.AreEqual('Keys', E[I].Category);
    Assert.IsTrue(IndexOfKey(E, 'tmaFileCopy') >= 0, 'menu commands stay');
    Assert.IsTrue(IndexOfKey(E, 'key:Copy') < 0, 'an action with a menu item is not listed twice');
    Assert.IsTrue(Contains(RankedKeys(E, 'background'), 'key:RunInBackground'),
      'found by its caption');
  finally
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestKeyOnlyCommandRunsItsAction;
var
  M: TTopMenuController;
  D: TDialogHost;
  C: TCommandPaletteDialogController;
  Ran: TKeymapAction;
  Key: Word;
  Ch: Char;
  S: string;
  I: Integer;
begin
  Ran := kaNone;
  M := MakeMenu(cMenuJson);
  D := TDialogHost.Create(nil);
  try
    C := MakePalette(D, M);
    try
      C.OnRunAction :=
        procedure(AAction: TKeymapAction)
        begin
          Ran := AAction;
        end;
      C.OpenList;
      S := 'in a new tab';
      for I := 1 to Length(S) do
      begin
        Key := 0;
        Ch := S[I];
        C.HandleFilterInput(Key, [], Ch);
      end;
      Assert.IsTrue(C.RowCount >= 1, 'the query finds the action');
      C.DispatchCommand('commands');
      Assert.AreEqual(Ord(kaRunInNewTab), Ord(Ran), 'Enter runs the action of the key');
      Assert.AreEqual<Integer>(0, GExecutedCount, 'no menu command ran');
    finally
      C.Free;
    end;
  finally
    D.Free;
    M.Free;
  end;
end;

procedure TTestCommandPalette.TestShortcutColumnIsSearched;
var
  M: TTopMenuController;
  E: TArray<TPaletteEntry>;
  Keys: TArray<string>;
begin
  M := MakeMenu(cMenuJson);
  try
    E := BuildPaletteEntries(M);
    AppendKeymapOnlyEntries(M, KeymapActionCaption, E);
    Keys := RankedKeys(E, 'f5');
    Assert.IsTrue(Contains(Keys, 'tmaFileCopy'), 'F5 finds the command bound to F5');
    Assert.IsTrue(not Contains(Keys, 'tmaFileMove'), 'F5 does not find the command bound to F6');
    Assert.AreEqual('tmaFileCopy', Keys[0], 'a command bound to the key comes first');
    Assert.IsTrue(Contains(RankedKeys(E, 'F5'), 'tmaFileCopy'), 'the case of the key does not matter');
    Keys := RankedKeys(E, 'shift');
    Assert.IsTrue(Contains(Keys, 'key:RunInBackground'), 'a modifier finds the chords that use it');
    Keys := RankedKeys(E, 'alt+shift+enter');
    Assert.IsTrue(Contains(Keys, 'key:RunInBackground'), 'a whole chord finds its command');
    Assert.IsTrue(not Contains(Keys, 'key:RunInNewTab'), 'another chord is not found');
    Assert.IsTrue(not Contains(RankedKeys(E, 'f'), 'key:RunInBackground'),
      'a letter does not match inside a key name such as Shift');
  finally
    M.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandPalette);

end.
