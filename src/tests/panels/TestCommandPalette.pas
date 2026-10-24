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
    [Test] procedure TestRecentCommandsComeFirstWithEmptyQuery;
    [Test] procedure TestRowTextFillsTheWidth;
    [Test] procedure TestRunItemRunsOnlyEnabledCommands;
    [Test] procedure TestShiftF9IsBoundToThePalette;
    [Test] procedure TestTypingNarrowsTheListAndEnterRuns;
    [Test] procedure TestEnterOnEmptyResultRunsNothing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uStrings, uKeymap, uCharWidth, uTopMenuBar, uCommandPalette,
  uDialogHost, uDualPanelUiTypes, uDualPanelPaletteDialog;

const
  cMenuJson =
    '{"categories":[{"title":"Files","hotChar":"F","items":[' +
    '{"caption":"Copy","hotChar":"C","shortcut":"F5","action":"tmaFileCopy"},' +
    '{"isSeparator":true},' +
    '{"caption":"Copy full path","hotChar":"P","shortcut":"","action":"tmaFileCopyPath"},' +
    '{"caption":"Move","hotChar":"M","shortcut":"F6","action":"tmaFileMove"},' +
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
    Assert.IsTrue(Contains(RankedKeys(E, 'оболочка'), 'tmaCmdConsoleProfile'),
      'the Russian alias finds it in an English menu');
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

initialization
  TDUnitX.RegisterTestFixture(TTestCommandPalette);

end.
