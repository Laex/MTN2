unit TestKeymap;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestKeymap = class
  public
    [Test] procedure Run;
    [Test] procedure TestContexts;
    [Test] procedure NoChordIsBoundTwiceInOneContext;
    [Test] procedure OverridesHoldOnlyWhatChanged;
    [Test] procedure ReservedChordsStayFree;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap;

// The app's default profile is the KEYMAP_DEFAULT resource (src\keymap.json),
// not GetDefaultNDNProfile (only its fallback). An action bound in code but
// with no key at all in the resource does nothing in the running app --
// Alt+Enter (Properties) and Alt+F11 (FileHistory) were lost exactly that
// way. Individual extra chords may differ on purpose (code Alt+X = Quit is
// not in the resource: Alt+letter is panel quick search there).
procedure TestResourceMatchesCodeDefaults;
var
  Code, Res: TKeymapProfile;
  A: TKeymapAction;
  K: Word;
begin
  Code := GetDefaultNDNProfile;
  Res := LoadDefaultKeymapProfile;
  for A := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    if Length(Code.Bindings[A]) > 0 then
      Assert.IsTrue(Length(Res.Bindings[A]) > 0, 'resource keymap.json has no key for ' +
        KeymapActionDisplayName(A) + ' (code default: ' + BindingsToStr(Code.Bindings[A]) + ')');
  Assert.IsTrue(MatchAction(Res, vkReturn, [ssAlt]) = kaProperties, 'resource: Alt+Enter = Properties');
  Assert.IsTrue(MatchAction(Res, vkF10, [ssShift]) = kaShellContextMenu,
    'resource: Shift+F10 = ShellContextMenu');
  Assert.IsTrue(MatchAction(Res, vkApps, []) = kaShellContextMenu,
    'resource: Menu key = ShellContextMenu');
  Assert.IsTrue(MatchAction(Res, vkF10, []) = kaQuit, 'resource: plain F10 is still Quit');
  Assert.IsTrue(StringToVK('Apps') = vkApps, 'key name Apps');
  Assert.IsTrue(StringToVK('menu') = vkApps, 'key name Menu, any case');
  Assert.IsTrue(VKToDisplayString(vkApps) = 'Menu', 'Menu key shown as Menu');
  Assert.IsTrue(StringToVK(VKToDisplayString(vkApps)) = vkApps, 'Menu key round-trips');
  Assert.IsTrue(StringToVK('/') = vkSlash, 'slash key name');
  Assert.IsTrue(StringToVK('Slash') = vkSlash, 'slash key word');
  for K in [vkSlash, vkComma, vkPeriod, vkSemicolon, vkQuote, vkEqual, vkMinus] do
    Assert.IsTrue(StringToVK(VKToDisplayString(K)) = K, 'punctuation key round-trips: ' + VKToDisplayString(K));
  Assert.IsTrue(StringToVK('-') = vkSubtract, 'bare minus stays the numpad key');
  Assert.IsTrue(MatchAction(Res, vkF11, [ssAlt]) = kaFileHistory, 'resource: Alt+F11 = FileHistory');
  Assert.IsTrue(MatchAction(Res, vkF3, [ssAlt]) = kaExternalView, 'resource: Alt+F3 = ExternalView');
  Assert.IsTrue(MatchAction(Res, vkF4, [ssAlt]) = kaExternalEdit, 'resource: Alt+F4 = ExternalEdit');
  Assert.IsTrue(MatchAction(Res, Ord('C'), [ssCtrl, ssShift]) = kaCompareFolders,
    'resource: Ctrl+Shift+C = CompareFolders');
  Assert.IsTrue(MatchAction(Res, Ord('C'), [ssCtrl]) <> kaCompareFolders,
    'resource: Ctrl+C stays copy');
  Writeln('Resource default keymap binds every action the code default binds');
end;

procedure RunTests;
var
  Profile: TKeymapProfile;
  Act: TKeymapAction;
  JsonText: string;
  LoadsBefore, LoadsAfter: Integer;
begin

  Profile := GetDefaultNDNProfile;
  Assert.IsTrue(Profile.Name = 'NDN', 'Default profile should be NDN');

  Act := MatchAction(Profile, vkF10, []);
  Assert.IsTrue(Act = kaQuit, 'F10 should match kaQuit');

  Act := MatchAction(Profile, Ord('X'), [ssAlt]);
  Assert.IsTrue(Act = kaAppQuit, 'Alt+X should match kaAppQuit (Global)');

  Act := MatchAction(Profile, Ord('D'), [ssCtrl]);
  Assert.IsTrue(Act = kaFolderHotlist, 'Ctrl+D should match kaFolderHotlist');
  Act := MatchAction(Profile, vkF11, [ssAlt]);
  Assert.IsTrue(Act = kaFileHistory, 'Alt+F11 should match kaFileHistory');
  Act := MatchAction(Profile, vkReturn, [ssAlt]);
  Assert.IsTrue(Act = kaProperties, 'Alt+Enter should match kaProperties');
  Act := MatchAction(Profile, vkReturn, [ssCtrl, ssAlt]);
  Assert.IsTrue(Act <> kaProperties, 'Ctrl+Alt+Enter is not Properties (reveal on the other panel)');
  Assert.IsTrue(TryKeymapActionByName('Properties', Act) and (Act = kaProperties),
    'keymap.json name "Properties"');
  Assert.IsTrue(TryKeymapActionByName('FileHistory', Act) and (Act = kaFileHistory),
    'keymap.json name "FileHistory"');
  Assert.IsTrue(TryKeymapActionByName('CompareFolders', Act) and (Act = kaCompareFolders),
    'keymap.json name "CompareFolders"');
  Assert.IsTrue(TryKeymapActionByName('ExternalView', Act) and (Act = kaExternalView),
    'keymap.json name "ExternalView"');
  Assert.IsTrue(TryKeymapActionByName('ExternalEdit', Act) and (Act = kaExternalEdit),
    'keymap.json name "ExternalEdit"');
  TestResourceMatchesCodeDefaults;
  Act := MatchAction(Profile, Ord('D'), [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaWorkspaceLibrary, 'Ctrl+Shift+D should match kaWorkspaceLibrary');
  Act := MatchAction(Profile, Ord('D'), [ssCtrl, ssAlt, ssShift]);
  Assert.IsTrue(Act = kaWorkspaceSave, 'Ctrl+Alt+Shift+D should match kaWorkspaceSave');
  Act := MatchAction(Profile, vkTab, [ssCtrl]);
  Assert.IsTrue(Act = kaNextPanelTab, 'Ctrl+Tab should match kaNextPanelTab');
  Act := MatchAction(Profile, vkTab, [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaPrevPanelTab, 'Ctrl+Shift+Tab should match kaPrevPanelTab');
  Act := MatchAction(Profile, Ord('T'), [ssCtrl]);
  Assert.IsTrue(Act = kaNewTab, 'Ctrl+T should match kaNewTab');
  Act := MatchAction(Profile, vkNext, [ssCtrl, ssAlt]);
  Assert.IsTrue(Act = kaNextTab, 'Ctrl+Alt+PgDn should match kaNextTab');
  Act := MatchAction(Profile, vkPrior, [ssCtrl, ssAlt]);
  Assert.IsTrue(Act = kaPrevTab, 'Ctrl+Alt+PgUp should match kaPrevTab');
  Act := MatchAction(Profile, Ord('W'), [ssCtrl]);
  Assert.IsTrue(Act = kaCloseTab, 'Ctrl+W should match kaCloseTab');
  Act := MatchAction(Profile, Ord('W'), [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaNewWorkspace, 'Ctrl+Shift+W should match kaNewWorkspace');
  Assert.IsTrue(TryKeymapActionByName('NewWorkspace', Act) and (Act = kaNewWorkspace),
    'keymap.json name "NewWorkspace"');

  Act := MatchAction(Profile, Ord('C'), [ssCtrl]);
  Assert.IsTrue(Act = kaEditCopy, 'Ctrl+C should match kaEditCopy');
  Act := MatchAction(Profile, vkInsert, [ssCtrl]);
  Assert.IsTrue(Act = kaEditCopy, 'Ctrl+Ins should match kaEditCopy');
  Act := MatchAction(Profile, Ord('X'), [ssCtrl]);
  Assert.IsTrue(Act = kaEditCut, 'Ctrl+X should match kaEditCut');
  Act := MatchAction(Profile, vkDelete, [ssCtrl]);
  Assert.IsTrue(Act = kaEditCut, 'Ctrl+Del should match kaEditCut');
  Act := MatchAction(Profile, Ord('V'), [ssCtrl]);
  Assert.IsTrue(Act = kaEditPaste, 'Ctrl+V should match kaEditPaste');
  Act := MatchAction(Profile, vkInsert, [ssShift]);
  Assert.IsTrue(Act = kaEditPaste, 'Shift+Ins should match kaEditPaste');

  // FAR: Alt+Shift+Ins copies the full paths, Ctrl+Shift+Ins the names.
  Act := MatchAction(Profile, vkInsert, [ssAlt, ssShift]);
  Assert.IsTrue(Act = kaCopyFullPath, 'Alt+Shift+Ins should match kaCopyFullPath');
  Act := MatchAction(Profile, vkInsert, [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaCopyItemName, 'Ctrl+Shift+Ins should match kaCopyItemName');
  Act := MatchAction(Profile, Ord('F'), [ssCtrl]);
  Assert.IsTrue(Act = kaInsertItemPath, 'Ctrl+F should match kaInsertItemPath');
  Act := MatchAction(Profile, vkReturn, [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaInsertItemPath, 'Ctrl+Shift+Enter still inserts the path');
  Act := MatchAction(Profile, Ord('M'), [ssCtrl]);
  Assert.IsTrue(Act = kaRestoreSelection, 'Ctrl+M should match kaRestoreSelection');
  Act := MatchAction(Profile, Ord('Z'), [ssCtrl]);
  Assert.IsTrue(Act = kaDescribe, 'Ctrl+Z should match kaDescribe');
  Act := MatchAction(Profile, Ord('P'), [ssCtrl]);
  Assert.IsTrue(Act = kaTogglePassivePanel, 'Ctrl+P should match kaTogglePassivePanel');
  // FAR: Ctrl+A is the file attributes, Shift+Gray + selects all files,
  // Alt+F6 creates a link, Ctrl+I is the panel filter; Gray * inverts.
  Act := MatchAction(Profile, Ord('A'), [ssCtrl]);
  Assert.IsTrue(Act = kaSetAttributes, 'Ctrl+A should match kaSetAttributes');
  Act := MatchAction(Profile, vkAdd, [ssShift]);
  Assert.IsTrue(Act = kaSelectAll, 'Shift+Gray + should match kaSelectAll');
  Act := MatchAction(Profile, vkSubtract, [ssShift]);
  Assert.IsTrue(Act = kaUnselectAll, 'Shift+Gray - should match kaUnselectAll');
  Act := MatchAction(Profile, vkMultiply, []);
  Assert.IsTrue(Act = kaInvertSelection, 'Gray * should match kaInvertSelection');
  Act := MatchAction(Profile, vkAdd, []);
  Assert.IsTrue(Act = kaSelectByMask, 'Gray + still selects by mask');
  Act := MatchAction(Profile, vkF6, [ssAlt]);
  Assert.IsTrue(Act = kaCreateLink, 'Alt+F6 should match kaCreateLink');
  Act := MatchAction(Profile, Ord('I'), [ssCtrl]);
  Assert.IsTrue(Act = kaLiveFilter, 'Ctrl+I should match kaLiveFilter');

  Act := MatchAction(Profile, 221 {vkOemCloseBrackets}, [ssCtrl]);
  Assert.IsTrue(Act = kaEqualizeOtherPanel, 'Ctrl+] should match kaEqualizeOtherPanel');

  Act := MatchAction(Profile, 219 {vkOemOpenBrackets}, [ssCtrl]);
  Assert.IsTrue(Act = kaEqualizeActivePanel, 'Ctrl+[ should match kaEqualizeActivePanel');

  Act := MatchAction(Profile, Ord('N'), [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaNewTerminal, 'Ctrl+Shift+N should match kaNewTerminal');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl, ssAlt]);
  Assert.IsTrue(Act = kaSelectConsoleProfile, 'Ctrl+Alt+O should match kaSelectConsoleProfile');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaSyncConsoleDir, 'Ctrl+Shift+O should match kaSyncConsoleDir');
  Act := MatchAction(Profile, vkNext, [ssCtrl]);
  Assert.IsTrue(Act = kaFolderDown, 'Ctrl+PgDn should match kaFolderDown');
  Act := MatchAction(Profile, vkPrior, [ssCtrl]);
  Assert.IsTrue(Act = kaFolderUp, 'Ctrl+PgUp should match kaFolderUp');
  Act := MatchAction(Profile, vkNext, []);
  Assert.IsTrue(Act = kaNone, 'plain PgDn stays page down');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl]);
  Assert.IsTrue(Act = kaAppConsoleToggle, 'Ctrl+O should match kaAppConsoleToggle (Global)');
  Act := MatchAction(Profile, vkEscape, []);
  Assert.IsTrue(Act = kaConsoleToggle, 'Esc on the panels should match kaConsoleToggle');

  JsonText :=
    '{"profile":"NDN","bindings":{' +
    '"EqualizeOtherPanel":{"key":"]","ctrl":true},' +
    '"EqualizeActivePanel":{"key":"[","ctrl":true}' +
    '}}';
  Assert.IsTrue(ParseKeymapJson(JsonText, Profile), 'Parse Equalize bindings from JSON');
  Act := MatchAction(Profile, 221, [ssCtrl]);
  Assert.IsTrue(Act = kaEqualizeOtherPanel, 'JSON Ctrl+] EqualizeOther');
  Act := MatchAction(Profile, 219, [ssCtrl]);
  Assert.IsTrue(Act = kaEqualizeActivePanel, 'JSON Ctrl+[ EqualizeActive');

  JsonText := '{"profile": "NDN", "bindings": {"Quit": [{"key": "F10"}, {"key": "X", "alt": true}]}}';
  Assert.IsTrue(ParseKeymapJson(JsonText, Profile), 'Parsing JSON array of hotkeys should succeed');

  Act := MatchAction(Profile, vkF10, []);
  Assert.IsTrue(Act = kaQuit, 'F10 from JSON array should match kaQuit');

  Act := MatchAction(Profile, Ord('X'), [ssAlt]);
  Assert.IsTrue(Act = kaQuit, 'Alt+X from JSON array should match kaQuit');

  // Cache: ActiveKeymap / MatchActiveAction must not re-read the file each time.
  ReloadKeymap('');
  LoadsBefore := KeymapFileLoadCount;
  Assert.IsTrue(MatchActiveAction(vkF5, []) = kaCopy, 'Cached F5 = Copy');
  Assert.IsTrue(MatchActiveAction(vkF10, []) = kaQuit, 'Cached F10 = Quit');
  LoadsAfter := KeymapFileLoadCount;
  Assert.IsTrue(LoadsAfter = LoadsBefore,
    Format('ActiveKeymap must not reload file (before=%d after=%d)',
      [LoadsBefore, LoadsAfter]));

  Writeln('TestKeymap passed successfully.');
end;

// One chord, different actions by context; a specific context wins over a
// general one along the chain; the panels never see document actions.
procedure TTestKeymap.TestContexts;
var
  P: TKeymapProfile;
  Act: TKeymapAction;
  K: Word;
  M: Integer;
  S: TShiftState;
begin
  P := GetDefaultNDNProfile;
  Assert.IsTrue(MatchActionIn(P, [kcPanels, kcGlobal], Ord('H'), [ssCtrl]) = kaToggleHidden,
    'Ctrl+H on panels: show hidden files');
  Assert.IsTrue(MatchActionIn(P, [kcViewer, kcDocument], Ord('H'), [ssCtrl]) = kaDocHex,
    'Ctrl+H in a document: hex');
  Assert.IsTrue(MatchActionIn(P, [kcViewer, kcDocument], vkF4, []) = kaDocHex, 'F4 in the viewer: hex');
  Assert.IsTrue(MatchActionIn(P, [kcMarkdown, kcViewer, kcDocument], vkF4, []) = kaMarkdownSource,
    'F4 over rendered Markdown: source (Markdown over Document)');
  Assert.IsTrue(MatchActionIn(P, [kcEditor, kcDocument], vkF7, [ssCtrl]) = kaEditorReplace,
    'Ctrl+F7 in the editor: replace (Editor over Document)');
  Assert.IsTrue(MatchActionIn(P, [kcViewer, kcDocument], vkF7, [ssCtrl]) = kaDocFind,
    'Ctrl+F7 in the viewer: find');
  Assert.IsTrue(MatchActionIn(P, [kcViewer, kcDocument], vkF2, []) = kaViewerWordWrap, 'F2 in the viewer: wrap');
  Assert.IsTrue(MatchActionIn(P, [kcEditor, kcDocument], vkF2, []) = kaEditorSave, 'F2 in the editor: save');
  Assert.IsTrue(MatchActionIn(P, [kcEditor, kcDocument], vkF10, []) = kaDocClose, 'F10 in a document: close');
  Assert.IsTrue(MatchAction(P, vkF10, []) = kaQuit, 'F10 on panels: quit');
  Assert.IsTrue(MatchActionIn(P, [kcEditor, kcDocument], Ord('Z'), [ssCtrl, ssShift]) = kaEditorRedo,
    'Ctrl+Shift+Z: redo');
  Assert.IsTrue(MatchActionIn(P, [kcEditor, kcDocument], Ord('A'), [ssCtrl, ssShift]) = kaNone,
    'modifiers match exactly');

  for K := 1 to 255 do
    for M := 0 to 7 do
    begin
      S := [];
      if M and 1 <> 0 then Include(S, ssShift);
      if M and 2 <> 0 then Include(S, ssCtrl);
      if M and 4 <> 0 then Include(S, ssAlt);
      Act := MatchAction(P, K, S);
      Assert.IsTrue(KeymapActionContext(Act) in [kcPanels, kcGlobal],
        Format('panels matched %s (key %d)', [KeymapActionDisplayName(Act), K]));
    end;

  Assert.IsTrue(MatchActionIn(P, [kcConsole, kcShell], Ord('C'), [ssCtrl, ssShift]) =
    kaShellCopyOrInterrupt, 'Ctrl+Shift+C in the console: copy');
  Assert.IsTrue(MatchActionIn(P, [kcTerminal, kcShell], vkF8, [ssAlt]) = kaShellHistory,
    'Alt+F8 in the terminal: its history');
  Assert.IsTrue(MatchActionIn(P, [kcConsole, kcShell], Ord('O'), [ssCtrl, ssShift]) =
    kaConsoleSyncDir, 'Ctrl+Shift+O in the console: panel follows it');
  Assert.IsTrue(MatchActionIn(P, [kcTerminal, kcShell], Ord('O'), [ssCtrl, ssShift]) = kaNone,
    'no console sync in the terminal');
  Assert.IsTrue(MatchGlobalActionIn(P, [kcTerminal, kcShell], 0, 'x', [ssAlt]) = kaAppQuit,
    'Alt+X from the terminal, typed character only');
  Assert.IsTrue(MatchGlobalActionIn(P, [kcConsole, kcShell], Ord('C'), #0, [ssCtrl]) = kaNone,
    'Ctrl+C is the console''s own');

  Assert.IsTrue(TryKeymapActionByName('DocHex', Act) and (Act = kaDocHex), 'names resolve');
end;

procedure TestNoChordIsBoundTwiceInOneContext;
var
  Profile: TKeymapProfile;
  A, B: TKeymapAction;
  I, J: Integer;
  X, Y: TKeyBinding;
  Clash: string;
begin
  // Two actions on one chord in the same window context: the first one in
  // the action list would take the key and the other could never be pressed.
  // A Global action sits above every window context, so it counts against all.
  Profile := LoadDefaultKeymapProfile;
  Clash := '';
  for A := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    for B := Succ(A) to High(TKeymapAction) do
      if (KeymapActionContext(A) = KeymapActionContext(B)) or
         (KeymapActionContext(A) = kcGlobal) or (KeymapActionContext(B) = kcGlobal) then
        for I := 0 to High(Profile.Bindings[A]) do
          for J := 0 to High(Profile.Bindings[B]) do
          begin
            X := Profile.Bindings[A][I];
            Y := Profile.Bindings[B][J];
            if SameKeyBinding(X, Y) and
               ((KeymapActionContext(A) = KeymapActionContext(B)) or
                (KeymapActionContext(A) = kcGlobal) or (KeymapActionContext(B) = kcGlobal)) then
              Clash := Clash + KeymapActionDisplayName(A) + ' / ' +
                KeymapActionDisplayName(B) + ' on ' + KeyBindingToStr(X) + '; ';
          end;
  Assert.AreEqual('', Clash, 'default keys bound twice');
end;

procedure TestOverridesHoldOnlyWhatChanged;
var
  Profile, Merged: TKeymapProfile;
  Json: string;
begin
  Profile := LoadDefaultKeymapProfile;
  Assert.AreEqual('{"bindings":{}}', KeymapOverridesToJson(Profile),
    'the built-in keymap has nothing to override');

  // One action moved, one left without a key.
  Profile.Bindings[kaMkDir] := [KeyBinding(vkF9, False, True, False)];
  SetLength(Profile.Bindings[kaWipe], 0);
  Json := KeymapOverridesToJson(Profile);
  Assert.IsTrue(Pos('"MkDir"', Json) > 0, 'the moved action is listed');
  Assert.IsTrue(Pos('"Wipe"', Json) > 0, 'the unbound action is listed, with an empty list');
  Assert.IsTrue(Pos('"Copy"', Json) = 0, 'an action left as it was is not');

  // Read back on top of the built-in keymap it gives the same keys.
  Merged := LoadDefaultKeymapProfile;
  Assert.IsTrue(MergeKeymapJson(Json, Merged), 'the overrides parse');
  Assert.IsTrue(MatchAction(Merged, vkF9, [ssAlt]) = kaMkDir, 'the moved key is in force');
  Assert.IsTrue(MatchAction(Merged, vkF5, []) = kaCopy, 'the rest is the built-in keymap');
end;

procedure TestReservedChordsStayFree;
var
  Profile: TKeymapProfile;
begin
  // Kept for what is planned: archive commands, network
  // (UNC) paths and macro recording. No panel or global action takes them.
  Profile := LoadDefaultKeymapProfile;
  Assert.IsTrue(MatchActionIn(Profile, [kcPanels, kcGlobal], vkF3, [ssShift]) = kaNone,
    'Shift+F3 is reserved');
  Assert.IsTrue(MatchActionIn(Profile, [kcPanels, kcGlobal], vkInsert, [ssCtrl, ssAlt]) = kaNone,
    'Ctrl+Alt+Ins is reserved');
  Assert.IsTrue(MatchActionIn(Profile, [kcPanels, kcGlobal], 190 {vkOemPeriod}, [ssCtrl]) = kaNone,
    'Ctrl+. is reserved');
end;

{ TTestKeymap }

procedure TTestKeymap.OverridesHoldOnlyWhatChanged;
begin
  TestOverridesHoldOnlyWhatChanged;
end;

procedure TTestKeymap.ReservedChordsStayFree;
begin
  TestReservedChordsStayFree;
end;

procedure TTestKeymap.NoChordIsBoundTwiceInOneContext;
begin
  TestNoChordIsBoundTwiceInOneContext;
end;

procedure TTestKeymap.Run;
begin
  RunTests;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeymap);

end.
