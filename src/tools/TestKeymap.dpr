program TestKeymap;

{$APPTYPE CONSOLE}
{$R '..\MTN2.dres'} // KEYMAP_DEFAULT -- the default profile the app really uses

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
      Assert(Length(Res.Bindings[A]) > 0, 'resource keymap.json has no key for ' +
        KeymapActionDisplayName(A) + ' (code default: ' + BindingsToStr(Code.Bindings[A]) + ')');
  Assert(MatchAction(Res, vkReturn, [ssAlt]) = kaProperties, 'resource: Alt+Enter = Properties');
  Assert(MatchAction(Res, vkF11, [ssAlt]) = kaFileHistory, 'resource: Alt+F11 = FileHistory');
  Assert(MatchAction(Res, vkF3, [ssAlt]) = kaExternalView, 'resource: Alt+F3 = ExternalView');
  Assert(MatchAction(Res, vkF4, [ssAlt]) = kaExternalEdit, 'resource: Alt+F4 = ExternalEdit');
  Assert(MatchAction(Res, Ord('C'), [ssCtrl, ssShift]) = kaCompareFolders,
    'resource: Ctrl+Shift+C = CompareFolders');
  Assert(MatchAction(Res, Ord('C'), [ssCtrl]) <> kaCompareFolders,
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
  Writeln('Testing uKeymap Stage 15 with cache...');

  Profile := GetDefaultNDNProfile;
  Assert(Profile.Name = 'NDN', 'Default profile should be NDN');

  Act := MatchAction(Profile, vkF10, []);
  Assert(Act = kaQuit, 'F10 should match kaQuit');

  Act := MatchAction(Profile, Ord('X'), [ssAlt]);
  Assert(Act = kaQuit, 'Alt+X should match kaQuit');

  Act := MatchAction(Profile, Ord('D'), [ssCtrl]);
  Assert(Act = kaFolderHotlist, 'Ctrl+D should match kaFolderHotlist');
  Act := MatchAction(Profile, vkF11, [ssAlt]);
  Assert(Act = kaFileHistory, 'Alt+F11 should match kaFileHistory');
  Act := MatchAction(Profile, vkReturn, [ssAlt]);
  Assert(Act = kaProperties, 'Alt+Enter should match kaProperties');
  Act := MatchAction(Profile, vkReturn, [ssCtrl, ssAlt]);
  Assert(Act <> kaProperties, 'Ctrl+Alt+Enter is not Properties (reveal on the other panel)');
  Assert(TryKeymapActionByName('Properties', Act) and (Act = kaProperties),
    'keymap.json name "Properties"');
  Assert(TryKeymapActionByName('FileHistory', Act) and (Act = kaFileHistory),
    'keymap.json name "FileHistory"');
  Assert(TryKeymapActionByName('CompareFolders', Act) and (Act = kaCompareFolders),
    'keymap.json name "CompareFolders"');
  Assert(TryKeymapActionByName('ExternalView', Act) and (Act = kaExternalView),
    'keymap.json name "ExternalView"');
  Assert(TryKeymapActionByName('ExternalEdit', Act) and (Act = kaExternalEdit),
    'keymap.json name "ExternalEdit"');
  TestResourceMatchesCodeDefaults;
  Act := MatchAction(Profile, Ord('D'), [ssCtrl, ssShift]);
  Assert(Act = kaWorkspaceLibrary, 'Ctrl+Shift+D should match kaWorkspaceLibrary');
  Act := MatchAction(Profile, Ord('D'), [ssCtrl, ssAlt, ssShift]);
  Assert(Act = kaWorkspaceSave, 'Ctrl+Alt+Shift+D should match kaWorkspaceSave');

  Act := MatchAction(Profile, Ord('C'), [ssCtrl]);
  Assert(Act = kaEditCopy, 'Ctrl+C should match kaEditCopy');
  Act := MatchAction(Profile, vkInsert, [ssCtrl]);
  Assert(Act = kaEditCopy, 'Ctrl+Ins should match kaEditCopy');
  Act := MatchAction(Profile, Ord('X'), [ssCtrl]);
  Assert(Act = kaEditCut, 'Ctrl+X should match kaEditCut');
  Act := MatchAction(Profile, vkDelete, [ssCtrl]);
  Assert(Act = kaEditCut, 'Ctrl+Del should match kaEditCut');
  Act := MatchAction(Profile, Ord('V'), [ssCtrl]);
  Assert(Act = kaEditPaste, 'Ctrl+V should match kaEditPaste');
  Act := MatchAction(Profile, vkInsert, [ssShift]);
  Assert(Act = kaEditPaste, 'Shift+Ins should match kaEditPaste');

  Act := MatchAction(Profile, Ord('A'), [ssCtrl]);
  Assert(Act = kaSelectAll, 'Ctrl+A should match kaSelectAll');
  Act := MatchAction(Profile, Ord('A'), [ssCtrl, ssShift]);
  Assert(Act = kaSetAttributes, 'Ctrl+Shift+A should match kaSetAttributes');

  Act := MatchAction(Profile, 221 {vkOemCloseBrackets}, [ssCtrl]);
  Assert(Act = kaEqualizeOtherPanel, 'Ctrl+] should match kaEqualizeOtherPanel');

  Act := MatchAction(Profile, 219 {vkOemOpenBrackets}, [ssCtrl]);
  Assert(Act = kaEqualizeActivePanel, 'Ctrl+[ should match kaEqualizeActivePanel');

  Act := MatchAction(Profile, Ord('N'), [ssCtrl, ssShift]);
  Assert(Act = kaNewTerminal, 'Ctrl+Shift+N should match kaNewTerminal');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl, ssAlt]);
  Assert(Act = kaSelectConsoleProfile, 'Ctrl+Alt+O should match kaSelectConsoleProfile');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl, ssShift]);
  Assert(Act = kaSyncConsoleDir, 'Ctrl+Shift+O should match kaSyncConsoleDir');
  Act := MatchAction(Profile, Ord('O'), [ssCtrl]);
  Assert(Act = kaConsoleToggle, 'Ctrl+O should match kaConsoleToggle');

  JsonText :=
    '{"profile":"NDN","bindings":{' +
    '"EqualizeOtherPanel":{"key":"]","ctrl":true},' +
    '"EqualizeActivePanel":{"key":"[","ctrl":true}' +
    '}}';
  Assert(ParseKeymapJson(JsonText, Profile), 'Parse Equalize bindings from JSON');
  Act := MatchAction(Profile, 221, [ssCtrl]);
  Assert(Act = kaEqualizeOtherPanel, 'JSON Ctrl+] EqualizeOther');
  Act := MatchAction(Profile, 219, [ssCtrl]);
  Assert(Act = kaEqualizeActivePanel, 'JSON Ctrl+[ EqualizeActive');

  JsonText := '{"profile": "NDN", "bindings": {"Quit": [{"key": "F10"}, {"key": "X", "alt": true}]}}';
  Assert(ParseKeymapJson(JsonText, Profile), 'Parsing JSON array of hotkeys should succeed');

  Act := MatchAction(Profile, vkF10, []);
  Assert(Act = kaQuit, 'F10 from JSON array should match kaQuit');

  Act := MatchAction(Profile, Ord('X'), [ssAlt]);
  Assert(Act = kaQuit, 'Alt+X from JSON array should match kaQuit');

  // Cache: ActiveKeymap / MatchActiveAction must not re-read the file each time.
  ReloadKeymap('');
  LoadsBefore := KeymapFileLoadCount;
  Assert(MatchActiveAction(vkF5, []) = kaCopy, 'Cached F5 = Copy');
  Assert(MatchActiveAction(vkF10, []) = kaQuit, 'Cached F10 = Quit');
  LoadsAfter := KeymapFileLoadCount;
  Assert(LoadsAfter = LoadsBefore,
    Format('ActiveKeymap must not reload file (before=%d after=%d)',
      [LoadsBefore, LoadsAfter]));

  Writeln('TestKeymap passed successfully.');
end;

begin
  try
    RunTests;
  except
    on E: Exception do
    begin
      Writeln('Test failed: ', E.Message);
      Halt(1);
    end;
  end;
end.
