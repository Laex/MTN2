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
begin
  Code := GetDefaultNDNProfile;
  Res := LoadDefaultKeymapProfile;
  for A := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    if Length(Code.Bindings[A]) > 0 then
      Assert.IsTrue(Length(Res.Bindings[A]) > 0, 'resource keymap.json has no key for ' +
        KeymapActionDisplayName(A) + ' (code default: ' + BindingsToStr(Code.Bindings[A]) + ')');
  Assert.IsTrue(MatchAction(Res, vkReturn, [ssAlt]) = kaProperties, 'resource: Alt+Enter = Properties');
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

  Act := MatchAction(Profile, Ord('A'), [ssCtrl]);
  Assert.IsTrue(Act = kaSelectAll, 'Ctrl+A should match kaSelectAll');
  Act := MatchAction(Profile, Ord('A'), [ssCtrl, ssShift]);
  Assert.IsTrue(Act = kaSetAttributes, 'Ctrl+Shift+A should match kaSetAttributes');

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

  Assert.IsTrue(TryKeymapActionByName('DocHex', Act) and (Act = kaDocHex), 'names resolve');
end;

{ TTestKeymap }

procedure TTestKeymap.Run;
begin
  RunTests;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeymap);

end.
