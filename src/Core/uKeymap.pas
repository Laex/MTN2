unit uKeymap;

{ Keymap configuration, profile definitions (NDN / FAR), and JSON file loader.
  Stage 15 (v0.2.1): customizable keybindings with multiple hot-keys per action,
  expanded action set, and dynamic JSON loader. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.JSON, System.IOUtils,
  System.Generics.Collections, Winapi.Windows;

type
  TKeymapAction = (
    kaNone,
    kaHelp,
    kaPack,
    kaUserMenu,
    kaUnpack,
    kaView,
    kaEdit,
    kaCopy,
    kaMove,
    kaRename,
    kaCopyInPlace,          // Shift+F5 — copy file into the same directory under a new name
    kaMkDir,
    kaCreateLink,
    kaCompareFiles,
    kaRecycleBin,
    kaRestore,
    kaDelete,
    kaWipe,
    kaQuit,
    kaFind,
    kaSwapPanels,
    kaEqualizeOtherPanel,   // Ctrl+] — other panel := active URI
    kaEqualizeActivePanel,  // Ctrl+[ — active panel := other URI
    kaInfoPanel,
    kaColumnMode,
    kaSortMenu,
    kaConsoleToggle,
    kaDriveRoot,
    kaDriveLeft,
    kaDriveRight,
    kaRefresh,
    kaSelectAll,
    kaInvertSelection,
    kaHistoryBack,
    kaHistoryForward,
    kaFolderHistory,
    kaFileHistory, // Alt+F11 -- files opened with F3/F4
    kaCmdHistory,
    kaFolderHotlist,
    kaFolderHotlistAdd,
    kaBranchView,
    kaLiveFilter,
    kaTogglePanelLeft,
    kaTogglePanelRight,
    kaSortByName,
    kaSortByExt,
    kaSortByDate,
    kaSortBySize,
    kaSortUnsorted,
    kaSortByCreated,
    kaSortByAccessed,
    kaCopyFullPath,
    kaInsertItemName,
    kaInsertItemPath,
    kaRunDetached,
    kaFocusCmdLine,
    kaNewTab,
    kaCloseTab,
    kaNextTab,
    kaSelectByMask,
    kaUnselectByMask,
    kaDirSync,
    kaJobList,
    kaNewTerminal,
    kaNewFile,
    kaQuickView,
    kaSyncConsoleDir,      // Ctrl+Shift+O — push active panel's dir into the console
    kaSelectConsoleProfile, // Ctrl+Alt+O — pick shell for the Ctrl+O background console
    kaToggleHidden,        // Ctrl+H — show/hide Hidden & System files in panel listing
    // Ctrl+Shift+F1..F6 — jump straight to a column mode, no menu needed
    // (mirrors kaSortByName..kaSortBySize's Ctrl+F3..F6 direct-sort pattern).
    kaColumnBrief,
    kaColumnSize,
    kaColumnDate,
    kaColumnFull,
    kaColumnCreated,
    kaColumnTypes,
    // Ctrl+Shift+F7 — user-configured column set (Options > Columns...).
    kaColumnCustom,
    // Edit menu clipboard (Ctrl+C/X/V): files on panels, text in cmdline.
    kaEditCopy,
    kaEditCut,
    kaEditPaste,
    kaWorkspaceLibrary,
    kaWorkspaceSave,
    kaSetAttributes,
    kaProperties, // Alt+Enter -- OS Properties window
    kaSshConnections,
    kaAssociations,
    kaCompareFolders, // Ctrl+Shift+C -- select what differs between panels
    kaExternalView,   // Alt+F3 -- external viewer
    kaExternalEdit,   // Alt+F4 -- external editor
    kaChecksums       // Ctrl+Alt+H -- calculate / verify checksums
  );

  TKeyBinding = record
    Key: Word;
    Shift: Boolean;
    Alt: Boolean;
    Ctrl: Boolean;
  end;

  TKeymapProfile = record
    Name: string;
    Bindings: array[TKeymapAction] of TArray<TKeyBinding>;
  end;

function KeyBinding(AKey: Word; AShift: Boolean = False; AAlt: Boolean = False; ACtrl: Boolean = False): TKeyBinding;
procedure AddBinding(var AProfile: TKeymapProfile; AAction: TKeymapAction; const ABinding: TKeyBinding);
/// <summary>Parses a single key token ("F1", "Delete", "A", ...) into a VK code.
/// Returns 0 if unrecognized. Exposed for uKeymapRegistry's key-combo parser.</summary>
function StringToVK(const S: string): Word;
/// <summary>Resolves an action name (as used in keymap.json / KEYMAP_ACTION_NAMES,
/// e.g. "Copy", "Delete") to its TKeymapAction. Returns False for kaNone/unknown names.</summary>
function TryKeymapActionByName(const AName: string; out AAction: TKeymapAction): Boolean;
/// <summary>Display name for an action, e.g. kaCopy -> "Copy". See uKeymap.pas's
/// private KEYMAP_ACTION_NAMES for the full table.</summary>
function KeymapActionDisplayName(AAction: TKeymapAction): string;
/// <summary>Inverse of StringToVK — canonical display token for a VK code
/// (e.g. vkF5 -> "F5", Ord('C') -> "C"). Falls back to "Key<code>" for a code
/// StringToVK does not recognize, so round-tripping never silently drops it.</summary>
function VKToDisplayString(AKey: Word): string;
/// <summary>"Ctrl+Shift+F5" style label for one binding.</summary>
function KeyBindingToStr(const ABinding: TKeyBinding): string;
/// <summary>Bindings joined with "; ", e.g. "Ctrl+C; F5". '' for no bindings.</summary>
function BindingsToStr(const ABindings: TArray<TKeyBinding>): string;
function SameKeyBinding(const A, B: TKeyBinding): Boolean;
/// <summary>Independent deep copy. AProfile.Bindings are dynamic arrays, so a
/// plain := only copies the reference — code that builds a working copy to
/// edit (e.g. the Keymap settings dialog) must clone first, or in-place
/// mutation of the copy would corrupt the shared ActiveKeymap cache too.</summary>
function CloneKeymapProfile(const ASrc: TKeymapProfile): TKeymapProfile;

type
  TKeymapOverlayProc = reference to procedure(var AProfile: TKeymapProfile);
var
  /// <summary>Set by uKeymapRegistry at unit init so ReloadKeymap can apply
  /// plugin-registered overrides without a circular unit dependency.</summary>
  GKeymapOverlayHook: TKeymapOverlayProc;

function GetDefaultNDNProfile: TKeymapProfile;
function GetDefaultFARProfile: TKeymapProfile;

function ParseKeymapJson(const AJsonText: string; out AProfile: TKeymapProfile): Boolean;
/// <summary>Overrides hotkeys on top of an already-loaded AProfile — see
/// implementation for details.</summary>
function MergeKeymapJson(const AJsonText: string; var AProfile: TKeymapProfile): Boolean;
function LoadKeymapFromFile(const APath: string = ''): TKeymapProfile;
function GetDefaultKeymapPath: string;
/// <summary>Serializes AProfile's bindings to the same JSON shape ParseKeymapJson /
/// MergeKeymapJson read back (see ApplyBindingsFromRootObj) — the inverse of
/// LoadKeymapFromFile's merge direction.</summary>
function KeymapProfileToJson(const AProfile: TKeymapProfile): string;
/// <summary>Writes KeymapProfileToJson(AProfile) to APath (GetDefaultKeymapPath
/// when blank) as the user's keymap.json override; does not reload the cache
/// (call ReloadKeymap after, if the change should take effect immediately).</summary>
procedure SaveKeymapProfile(const AProfile: TKeymapProfile; const APath: string = '');
/// <summary>Loads the built-in default profile from the KEYMAP_DEFAULT RCDATA
/// resource (config/keymap.json, embedded via MTN2.rc); falls back to the
/// hardcoded GetDefaultNDNProfile if the resource is missing/unparsable.</summary>
function LoadDefaultKeymapProfile: TKeymapProfile;

/// <summary>Cached profile — load once; use ReloadKeymap to refresh.</summary>
function ActiveKeymap: TKeymapProfile;
/// <summary>Force reload: starts from the embedded default (LoadDefaultKeymapProfile),
/// then — if a user keymap.json exists at APath (or the config dir when APath
/// is blank) — overrides hotkeys from that file on top of it. Result = True
/// when such a user file was found and applied.</summary>
function ReloadKeymap(const APath: string = ''): Boolean;
/// <summary>True after at least one successful/failed load into the cache.</summary>
function KeymapCacheLoaded: Boolean;

function MatchAction(const AProfile: TKeymapProfile; AKey: Word; AShiftState: TShiftState): TKeymapAction;
/// <summary>Match against ActiveKeymap (cached).</summary>
function MatchActiveAction(AKey: Word; AShiftState: TShiftState): TKeymapAction;
/// <summary>Diagnostics: times LoadKeymapFromFile was invoked (tests).</summary>
function KeymapFileLoadCount: Integer;

/// <summary>Short F-bar label for an action (empty = not shown on F1–F10 bar).</summary>
function KeymapFBarShortLabel(AAction: TKeymapAction): string;
/// <summary>Overwrite F1–F10 slots from profile bindings that match AMods.</summary>
procedure ApplyKeymapToFBarItems(const AProfile: TKeymapProfile; AMods: TShiftState;
  var AItems: TArray<string>);

const
  // OEM bracket/grave keys (Winapi VK_OEM_4 / VK_OEM_6 / VK_OEM_3); not in System.UITypes.
  vkOemOpenBrackets  = 219; // [
  vkOemCloseBrackets = 221; // ]
  vkOemGrave         = 192; // `

  // Legacy constants retained for compatibility
  kmHelp        = vkF1;
  kmPack        = vkF1;
  kmUserMenu    = vkF2;
  kmUnpack      = vkF2;
  kmView        = vkF3;
  kmEdit        = vkF4;
  kmCopy        = vkF5;
  kmMove        = vkF6;
  kmRename      = vkF6;
  kmMkDir       = vkF7;
  kmDelete      = vkF8;
  kmQuit        = vkF10;
  kmFind        = vkF7;
  kmSwitchSide  = vkTab;
  kmColumnMode  = vkOemGrave;
  kmInfoPanel   = Ord('L');
  kmSwapPanels  = Ord('U');
  kmCmdFocus    = vkDown;
  kmConsole     = Ord('O');

implementation

uses
  uConfigLocation;

function KeyBinding(AKey: Word; AShift: Boolean; AAlt: Boolean; ACtrl: Boolean): TKeyBinding;
begin
  Result.Key := AKey;
  Result.Shift := AShift;
  Result.Alt := AAlt;
  Result.Ctrl := ACtrl;
end;

procedure AddBinding(var AProfile: TKeymapProfile; AAction: TKeymapAction; const ABinding: TKeyBinding);
var
  Len: Integer;
begin
  Len := Length(AProfile.Bindings[AAction]);
  SetLength(AProfile.Bindings[AAction], Len + 1);
  AProfile.Bindings[AAction][Len] := ABinding;
end;

function StringToVK(const S: string): Word;
var
  UpperS: string;
begin
  UpperS := UpperCase(Trim(S));
  if UpperS = 'F1' then Result := vkF1
  else if UpperS = 'F2' then Result := vkF2
  else if UpperS = 'F3' then Result := vkF3
  else if UpperS = 'F4' then Result := vkF4
  else if UpperS = 'F5' then Result := vkF5
  else if UpperS = 'F6' then Result := vkF6
  else if UpperS = 'F7' then Result := vkF7
  else if UpperS = 'F8' then Result := vkF8
  else if UpperS = 'F9' then Result := vkF9
  else if UpperS = 'F10' then Result := vkF10
  else if UpperS = 'F11' then Result := vkF11
  else if UpperS = 'F12' then Result := vkF12
  else if (UpperS = 'ESC') or (UpperS = 'ESCAPE') then Result := vkEscape
  else if (UpperS = 'LEFT') then Result := vkLeft
  else if (UpperS = 'RIGHT') then Result := vkRight
  else if (UpperS = 'UP') then Result := vkUp
  else if (UpperS = 'DOWN') then Result := vkDown
  else if (UpperS = 'BACKSLASH') or (UpperS = '\') then Result := vkBackSlash
  else if (UpperS = '[') or (UpperS = 'OEM4') or (UpperS = 'OPENBRACKET') then
    Result := vkOemOpenBrackets
  else if (UpperS = ']') or (UpperS = 'OEM6') or (UpperS = 'CLOSEBRACKET') then
    Result := vkOemCloseBrackets
  else if (UpperS = '`') or (UpperS = 'OEM3') or (UpperS = 'GRAVE') or (UpperS = 'TILDE') then
    Result := vkOemGrave
  else if (UpperS = 'TAB') then Result := vkTab
  else if (UpperS = 'INSERT') or (UpperS = 'INS') then Result := vkInsert
  else if (UpperS = 'DELETE') or (UpperS = 'DEL') then Result := vkDelete
  else if (UpperS = 'HOME') then Result := vkHome
  else if (UpperS = 'END') then Result := vkEnd
  else if (UpperS = 'PRIOR') or (UpperS = 'PAGEUP') or (UpperS = 'PGUP') then Result := vkPrior
  else if (UpperS = 'NEXT') or (UpperS = 'PAGEDOWN') or (UpperS = 'PGDN') then Result := vkNext
  else if (UpperS = 'ENTER') or (UpperS = 'RETURN') then Result := vkReturn
  else if (UpperS = 'NUMPAD+') or (UpperS = '+') or (UpperS = 'ADD') then Result := vkAdd
  else if (UpperS = 'NUMPAD-') or (UpperS = '-') or (UpperS = 'SUBTRACT') then Result := vkSubtract
  else if (UpperS = 'NUMPAD*') or (UpperS = '*') or (UpperS = 'MULTIPLY') then Result := vkMultiply
  else if Length(UpperS) = 1 then Result := Ord(UpperS[1])
  else Result := 0;
end;

function VKToDisplayString(AKey: Word): string;
begin
  case AKey of
    vkF1: Result := 'F1';
    vkF2: Result := 'F2';
    vkF3: Result := 'F3';
    vkF4: Result := 'F4';
    vkF5: Result := 'F5';
    vkF6: Result := 'F6';
    vkF7: Result := 'F7';
    vkF8: Result := 'F8';
    vkF9: Result := 'F9';
    vkF10: Result := 'F10';
    vkF11: Result := 'F11';
    vkF12: Result := 'F12';
    vkEscape: Result := 'Escape';
    vkLeft: Result := 'Left';
    vkRight: Result := 'Right';
    vkUp: Result := 'Up';
    vkDown: Result := 'Down';
    vkBackSlash: Result := 'Backslash';
    vkOemOpenBrackets: Result := '[';
    vkOemCloseBrackets: Result := ']';
    vkOemGrave: Result := '`';
    vkTab: Result := 'Tab';
    vkInsert: Result := 'Insert';
    vkDelete: Result := 'Delete';
    vkHome: Result := 'Home';
    vkEnd: Result := 'End';
    vkPrior: Result := 'PageUp';
    vkNext: Result := 'PageDown';
    vkReturn: Result := 'Enter';
    vkAdd: Result := '+';
    vkSubtract: Result := '-';
    vkMultiply: Result := '*';
  else
    if (AKey >= Ord('0')) and (AKey <= Ord('9')) then
      Result := Chr(AKey)
    else if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
      Result := Chr(AKey)
    else
      Result := 'Key' + IntToStr(AKey);
  end;
end;

function KeyBindingToStr(const ABinding: TKeyBinding): string;
begin
  Result := '';
  if ABinding.Ctrl then
    Result := Result + 'Ctrl+';
  if ABinding.Alt then
    Result := Result + 'Alt+';
  if ABinding.Shift then
    Result := Result + 'Shift+';
  Result := Result + VKToDisplayString(ABinding.Key);
end;

function BindingsToStr(const ABindings: TArray<TKeyBinding>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ABindings) do
  begin
    if I > 0 then
      Result := Result + '; ';
    Result := Result + KeyBindingToStr(ABindings[I]);
  end;
end;

function SameKeyBinding(const A, B: TKeyBinding): Boolean;
begin
  Result := (A.Key = B.Key) and (A.Shift = B.Shift) and (A.Alt = B.Alt) and (A.Ctrl = B.Ctrl);
end;

function CloneKeymapProfile(const ASrc: TKeymapProfile): TKeymapProfile;
var
  Act: TKeymapAction;
begin
  Result.Name := ASrc.Name;
  for Act := Low(TKeymapAction) to High(TKeymapAction) do
    Result.Bindings[Act] := Copy(ASrc.Bindings[Act]);
end;

function GetDefaultNDNProfile: TKeymapProfile;
var
  Act: TKeymapAction;
begin
  Result.Name := 'NDN';
  for Act := Low(TKeymapAction) to High(TKeymapAction) do
    SetLength(Result.Bindings[Act], 0);

  AddBinding(Result, kaHelp, KeyBinding(vkF1, False, False, False));
  AddBinding(Result, kaPack, KeyBinding(vkF1, True, False, False));
  AddBinding(Result, kaUserMenu, KeyBinding(vkF2, False, False, False));
  AddBinding(Result, kaUnpack, KeyBinding(vkF2, True, False, False));
  AddBinding(Result, kaView, KeyBinding(vkF3, False, False, False));
  AddBinding(Result, kaEdit, KeyBinding(vkF4, False, False, False));
  AddBinding(Result, kaNewFile, KeyBinding(vkF4, True, False, False));
  AddBinding(Result, kaCopy, KeyBinding(vkF5, False, False, False));
  AddBinding(Result, kaMove, KeyBinding(vkF6, False, False, False));
  AddBinding(Result, kaRename, KeyBinding(vkF6, True, False, False));
  AddBinding(Result, kaCopyInPlace, KeyBinding(vkF5, True, False, False));
  AddBinding(Result, kaMkDir, KeyBinding(vkF7, False, False, False));
  AddBinding(Result, kaCreateLink, KeyBinding(vkF7, True, False, False));
  AddBinding(Result, kaCompareFiles, KeyBinding(Ord('C'), False, True, True));
  AddBinding(Result, kaCompareFolders, KeyBinding(Ord('C'), True, False, True));
  AddBinding(Result, kaExternalView, KeyBinding(vkF3, False, True, False));
  AddBinding(Result, kaExternalEdit, KeyBinding(vkF4, False, True, False));
  AddBinding(Result, kaChecksums, KeyBinding(Ord('H'), False, True, True));
  AddBinding(Result, kaRecycleBin, KeyBinding(vkF8, False, True, True));
  AddBinding(Result, kaRestore, KeyBinding(Ord('R'), False, True, True));
  AddBinding(Result, kaDelete, KeyBinding(vkF8, False, False, False));
  AddBinding(Result, kaDelete, KeyBinding(vkDelete, False, False, False));
  AddBinding(Result, kaWipe, KeyBinding(vkF8, True, False, False));
  AddBinding(Result, kaWipe, KeyBinding(vkDelete, True, False, False));
  
  // kaQuit: F10 and Alt+X (NDN/FAR habit)
  AddBinding(Result, kaQuit, KeyBinding(vkF10, False, False, False));
  AddBinding(Result, kaQuit, KeyBinding(Ord('X'), False, True, False));

  AddBinding(Result, kaFind, KeyBinding(vkF7, False, True, False));
  AddBinding(Result, kaColumnMode, KeyBinding(vkOemGrave, False, False, True));
  AddBinding(Result, kaInfoPanel, KeyBinding(Ord('L'), False, False, True));
  AddBinding(Result, kaSwapPanels, KeyBinding(Ord('U'), False, False, True));
  AddBinding(Result, kaEqualizeOtherPanel, KeyBinding(vkOemCloseBrackets, False, False, True));
  AddBinding(Result, kaEqualizeActivePanel, KeyBinding(vkOemOpenBrackets, False, False, True));
  AddBinding(Result, kaSortMenu, KeyBinding(vkF12, False, False, True));
  AddBinding(Result, kaConsoleToggle, KeyBinding(Ord('O'), False, False, True));
  AddBinding(Result, kaConsoleToggle, KeyBinding(vkEscape, False, False, False));
  AddBinding(Result, kaDriveRoot, KeyBinding(vkBackSlash, False, False, True));
  AddBinding(Result, kaDriveLeft, KeyBinding(vkF1, False, True, False));
  AddBinding(Result, kaDriveRight, KeyBinding(vkF2, False, True, False));
  AddBinding(Result, kaRefresh, KeyBinding(Ord('R'), False, False, True));
  AddBinding(Result, kaSelectAll, KeyBinding(Ord('A'), False, False, True));
  AddBinding(Result, kaSetAttributes, KeyBinding(Ord('A'), True, False, True));
  AddBinding(Result, kaProperties, KeyBinding(vkReturn, False, True, False));
  AddBinding(Result, kaInvertSelection, KeyBinding(Ord('I'), False, False, True));
  AddBinding(Result, kaHistoryBack, KeyBinding(vkLeft, False, True, False));
  AddBinding(Result, kaHistoryForward, KeyBinding(vkRight, False, True, False));
  AddBinding(Result, kaFolderHistory, KeyBinding(vkF12, False, True, False));
  AddBinding(Result, kaFileHistory, KeyBinding(vkF11, False, True, False));
  AddBinding(Result, kaCmdHistory, KeyBinding(vkF8, False, True, False));
  AddBinding(Result, kaFolderHotlist, KeyBinding(Ord('D'), False, False, True));
  AddBinding(Result, kaFolderHotlistAdd, KeyBinding(Ord('D'), False, True, True));
  AddBinding(Result, kaWorkspaceLibrary, KeyBinding(Ord('D'), True, False, True));
  AddBinding(Result, kaWorkspaceSave, KeyBinding(Ord('D'), True, True, True));
  AddBinding(Result, kaSshConnections, KeyBinding(Ord('N'), True, True, True));
  AddBinding(Result, kaAssociations, KeyBinding(Ord('A'), True, True, True));
  AddBinding(Result, kaBranchView, KeyBinding(Ord('B'), False, False, True));
  AddBinding(Result, kaLiveFilter, KeyBinding(Ord('F'), False, False, True));
  AddBinding(Result, kaTogglePanelLeft, KeyBinding(vkF1, False, False, True));
  AddBinding(Result, kaTogglePanelRight, KeyBinding(vkF2, False, False, True));

  // Sort actions (Ctrl+F3 .. Ctrl+F9)
  AddBinding(Result, kaSortByName, KeyBinding(vkF3, False, False, True));
  AddBinding(Result, kaSortByExt, KeyBinding(vkF4, False, False, True));
  AddBinding(Result, kaSortByDate, KeyBinding(vkF5, False, False, True));
  AddBinding(Result, kaSortBySize, KeyBinding(vkF6, False, False, True));
  AddBinding(Result, kaSortUnsorted, KeyBinding(vkF7, False, False, True));
  AddBinding(Result, kaSortByCreated, KeyBinding(vkF8, False, False, True));
  AddBinding(Result, kaSortByAccessed, KeyBinding(vkF9, False, False, True));

  // Clipboard & item insertion
  AddBinding(Result, kaCopyFullPath, KeyBinding(vkInsert, False, True, True));
  AddBinding(Result, kaInsertItemName, KeyBinding(vkReturn, False, False, True));
  AddBinding(Result, kaInsertItemPath, KeyBinding(vkReturn, True, False, True));
  AddBinding(Result, kaRunDetached, KeyBinding(vkReturn, True, False, False));
  AddBinding(Result, kaFocusCmdLine, KeyBinding(vkDown, False, False, True));

  // Tab management
  AddBinding(Result, kaNewTab, KeyBinding(Ord('T'), False, False, True));
  AddBinding(Result, kaCloseTab, KeyBinding(Ord('W'), False, False, True));
  AddBinding(Result, kaNextTab, KeyBinding(vkTab, False, False, True));

  // Mask selection
  AddBinding(Result, kaSelectByMask, KeyBinding(vkAdd, False, False, False));
  AddBinding(Result, kaUnselectByMask, KeyBinding(vkSubtract, False, False, False));
  AddBinding(Result, kaDirSync, KeyBinding(Ord('S'), False, True, True));
  AddBinding(Result, kaJobList, KeyBinding(Ord('J'), True, False, True));
  AddBinding(Result, kaNewTerminal, KeyBinding(Ord('N'), True, False, True));

  // Stage 24: Ctrl+Q — Quick View (opposite panel; any file or directory).
  AddBinding(Result, kaQuickView, KeyBinding(Ord('Q'), False, False, True));

  // Ctrl+Shift+O — sync active panel dir <-> background console cwd
  // (direction depends on which side is active; console side is hardcoded
  // in TConsoleWindow.HandleInput, not routed through this keymap).
  AddBinding(Result, kaSyncConsoleDir, KeyBinding(Ord('O'), True, False, True));
  AddBinding(Result, kaSelectConsoleProfile, KeyBinding(Ord('O'), False, True, True));

  // Ctrl+H — show/hide Hidden & System files (Total Commander habit).
  AddBinding(Result, kaToggleHidden, KeyBinding(Ord('H'), False, False, True));

  // Ctrl+Shift+F1..F6 — direct column mode switch, no menu needed.
  AddBinding(Result, kaColumnBrief, KeyBinding(vkF1, True, False, True));
  AddBinding(Result, kaColumnSize, KeyBinding(vkF2, True, False, True));
  AddBinding(Result, kaColumnDate, KeyBinding(vkF3, True, False, True));
  AddBinding(Result, kaColumnFull, KeyBinding(vkF4, True, False, True));
  AddBinding(Result, kaColumnCreated, KeyBinding(vkF5, True, False, True));
  AddBinding(Result, kaColumnTypes, KeyBinding(vkF6, True, False, True));
  AddBinding(Result, kaColumnCustom, KeyBinding(vkF7, True, False, True));

  AddBinding(Result, kaEditCopy, KeyBinding(Ord('C'), False, False, True));
  AddBinding(Result, kaEditCopy, KeyBinding(vkInsert, False, False, True));
  AddBinding(Result, kaEditCut, KeyBinding(Ord('X'), False, False, True));
  AddBinding(Result, kaEditCut, KeyBinding(vkDelete, False, False, True));
  AddBinding(Result, kaEditPaste, KeyBinding(Ord('V'), False, False, True));
  AddBinding(Result, kaEditPaste, KeyBinding(vkInsert, True, False, False));
end;

function GetDefaultFARProfile: TKeymapProfile;
begin
  Result := GetDefaultNDNProfile;
  Result.Name := 'FAR';
  SetLength(Result.Bindings[kaPack], 0);
  AddBinding(Result, kaPack, KeyBinding(vkF7, False, True, False)); // Alt+F7 Find in FAR
end;

function MatchAction(const AProfile: TKeymapProfile; AKey: Word; AShiftState: TShiftState): TKeymapAction;
var
  Act: TKeymapAction;
  B: TKeyBinding;
  I: Integer;
  HasShift, HasAlt, HasCtrl: Boolean;
begin
  Result := kaNone;
  HasShift := ssShift in AShiftState;
  HasAlt := ssAlt in AShiftState;
  HasCtrl := ssCtrl in AShiftState;

  for Act := Low(TKeymapAction) to High(TKeymapAction) do
  begin
    if Act = kaNone then
      Continue;
    for I := 0 to High(AProfile.Bindings[Act]) do
    begin
      B := AProfile.Bindings[Act][I];
      if (B.Key = AKey) and (B.Shift = HasShift) and (B.Alt = HasAlt) and (B.Ctrl = HasCtrl) then
      begin
        Result := Act;
        Exit;
      end;
    end;
  end;
end;

procedure ParseItemObject(const AItemObj: TJSONObject; AAct: TKeymapAction; var AProfile: TKeymapProfile);
var
  KeyStr: string;
  VK: Word;
  ShiftB, AltB, CtrlB: Boolean;
begin
  if (AItemObj <> nil) and (AItemObj.Values['key'] <> nil) then
  begin
    KeyStr := AItemObj.Values['key'].Value;
    VK := StringToVK(KeyStr);
    if VK <> 0 then
    begin
      ShiftB := False;
      AltB := False;
      CtrlB := False;
      if AItemObj.Values['shift'] is TJSONBool then
        ShiftB := TJSONBool(AItemObj.Values['shift']).AsBoolean;
      if AItemObj.Values['alt'] is TJSONBool then
        AltB := TJSONBool(AItemObj.Values['alt']).AsBoolean;
      if AItemObj.Values['ctrl'] is TJSONBool then
        CtrlB := TJSONBool(AItemObj.Values['ctrl']).AsBoolean;
      AddBinding(AProfile, AAct, KeyBinding(VK, ShiftB, AltB, CtrlB));
    end;
  end;
end;

const
  KEYMAP_ACTION_NAMES: array[TKeymapAction] of string = (
    '',                      // kaNone
    'Help',                  // kaHelp
    'Pack',                  // kaPack
    'UserMenu',              // kaUserMenu
    'Unpack',                // kaUnpack
    'View',                  // kaView
    'Edit',                  // kaEdit
    'Copy',                  // kaCopy
    'Move',                  // kaMove
    'Rename',                // kaRename
    'CopyInPlace',           // kaCopyInPlace
    'MkDir',                 // kaMkDir
    'CreateLink',            // kaCreateLink
    'CompareFiles',          // kaCompareFiles
    'RecycleBin',            // kaRecycleBin
    'Restore',               // kaRestore
    'Delete',                // kaDelete
    'Wipe',                  // kaWipe
    'Quit',                  // kaQuit
    'Find',                  // kaFind
    'SwapPanels',            // kaSwapPanels
    'EqualizeOtherPanel',    // kaEqualizeOtherPanel
    'EqualizeActivePanel',   // kaEqualizeActivePanel
    'InfoPanel',             // kaInfoPanel
    'ColumnModes',           // kaColumnMode
    'SortMenu',              // kaSortMenu
    'ConsoleToggle',         // kaConsoleToggle
    'DriveRoot',             // kaDriveRoot
    'DriveLeft',             // kaDriveLeft
    'DriveRight',            // kaDriveRight
    'Refresh',               // kaRefresh
    'SelectAll',             // kaSelectAll
    'InvertSelection',       // kaInvertSelection
    'HistoryBack',           // kaHistoryBack
    'HistoryForward',        // kaHistoryForward
    'FolderHistory',         // kaFolderHistory
    'FileHistory',           // kaFileHistory
    'CmdHistory',            // kaCmdHistory
    'FolderHotlist',         // kaFolderHotlist
    'FolderHotlistAdd',      // kaFolderHotlistAdd
    'BranchView',            // kaBranchView
    'LiveFilter',            // kaLiveFilter
    'TogglePanelLeft',       // kaTogglePanelLeft
    'TogglePanelRight',      // kaTogglePanelRight
    'SortByName',            // kaSortByName
    'SortByExt',             // kaSortByExt
    'SortByDate',            // kaSortByDate
    'SortBySize',            // kaSortBySize
    'SortUnsorted',          // kaSortUnsorted
    'SortByCreated',         // kaSortByCreated
    'SortByAccessed',        // kaSortByAccessed
    'CopyFullPath',          // kaCopyFullPath
    'InsertItemName',        // kaInsertItemName
    'InsertItemPath',        // kaInsertItemPath
    'RunDetached',           // kaRunDetached
    'FocusCmdLine',          // kaFocusCmdLine
    'NewTab',                // kaNewTab
    'CloseTab',              // kaCloseTab
    'NextTab',               // kaNextTab
    'SelectByMask',          // kaSelectByMask
    'UnselectByMask',        // kaUnselectByMask
    'DirSync',               // kaDirSync
    'JobList',               // kaJobList
    'NewTerminal',           // kaNewTerminal
    'NewFile',               // kaNewFile
    'QuickView',             // kaQuickView
    'SyncConsoleDir',        // kaSyncConsoleDir
    'SelectConsoleProfile',  // kaSelectConsoleProfile
    'ToggleHidden',          // kaToggleHidden
    'ColumnBrief',           // kaColumnBrief
    'ColumnSize',            // kaColumnSize
    'ColumnDate',            // kaColumnDate
    'ColumnFull',            // kaColumnFull
    'ColumnCreated',         // kaColumnCreated
    'ColumnTypes',           // kaColumnTypes
    'ColumnCustom',          // kaColumnCustom
    'EditCopy',              // kaEditCopy
    'EditCut',               // kaEditCut
    'EditPaste',             // kaEditPaste
    'WorkspaceLibrary',      // kaWorkspaceLibrary
    'WorkspaceSave',         // kaWorkspaceSave
    'SetAttributes',         // kaSetAttributes
    'Properties',            // kaProperties
    'SshConnections',        // kaSshConnections
    'Associations',          // kaAssociations
    'CompareFolders',        // kaCompareFolders
    'ExternalView',          // kaExternalView
    'ExternalEdit',          // kaExternalEdit
    'Checksums'              // kaChecksums
  );

function TryKeymapActionByName(const AName: string; out AAction: TKeymapAction): Boolean;
var
  Act: TKeymapAction;
begin
  AAction := kaNone;
  Result := False;
  if AName = '' then
    Exit;
  for Act := Low(TKeymapAction) to High(TKeymapAction) do
    if SameText(KEYMAP_ACTION_NAMES[Act], AName) then
    begin
      AAction := Act;
      Exit(Act <> kaNone);
    end;
end;

function KeymapActionDisplayName(AAction: TKeymapAction): string;
begin
  Result := KEYMAP_ACTION_NAMES[AAction];
end;

function KeymapProfileToJson(const AProfile: TKeymapProfile): string;
var
  Root, BindObj: TJSONObject;
  Act: TKeymapAction;
  Arr: TJSONArray;
  I: Integer;
  ItemObj: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    BindObj := TJSONObject.Create;
    Root.AddPair('bindings', BindObj);
    for Act := Low(TKeymapAction) to High(TKeymapAction) do
    begin
      if (Act = kaNone) or (KEYMAP_ACTION_NAMES[Act] = '') then
        Continue;
      Arr := TJSONArray.Create;
      for I := 0 to High(AProfile.Bindings[Act]) do
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.AddPair('key', VKToDisplayString(AProfile.Bindings[Act][I].Key));
        if AProfile.Bindings[Act][I].Ctrl then
          ItemObj.AddPair('ctrl', TJSONBool.Create(True));
        if AProfile.Bindings[Act][I].Alt then
          ItemObj.AddPair('alt', TJSONBool.Create(True));
        if AProfile.Bindings[Act][I].Shift then
          ItemObj.AddPair('shift', TJSONBool.Create(True));
        Arr.AddElement(ItemObj);
      end;
      BindObj.AddPair(KEYMAP_ACTION_NAMES[Act], Arr);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

/// <summary>Applies BindObj's entry for one action (a single binding object,
/// or an array of them) onto AProfile, replacing whatever that action had
/// before. No-op if the action has no JSON name or no entry in BindObj.</summary>
procedure ApplyBindingsForAction(BindObj: TJSONObject; AAct: TKeymapAction;
  var AProfile: TKeymapProfile);
var
  ActName: string;
  KeyVal: TJSONValue;
  ArrVal: TJSONArray;
  I: Integer;
begin
  ActName := KEYMAP_ACTION_NAMES[AAct];
  if ActName = '' then
    Exit;
  KeyVal := BindObj.Values[ActName];
  if KeyVal is TJSONArray then
  begin
    ArrVal := TJSONArray(KeyVal);
    SetLength(AProfile.Bindings[AAct], 0); // Clear default for this action
    for I := 0 to ArrVal.Count - 1 do
      if ArrVal.Items[I] is TJSONObject then
        ParseItemObject(TJSONObject(ArrVal.Items[I]), AAct, AProfile);
  end;
  if KeyVal is TJSONObject then
  begin
    SetLength(AProfile.Bindings[AAct], 0); // Clear default for this action
    ParseItemObject(TJSONObject(KeyVal), AAct, AProfile);
  end;
end;

/// <summary>Adds ABinding to AAction unless a binding with the same Key+Shift
/// is already present (Ctrl/Alt are not compared — matches the two call
/// sites' original hand-rolled checks below).</summary>
procedure EnsureBindingPresent(var AProfile: TKeymapProfile; AAction: TKeymapAction;
  const ABinding: TKeyBinding);
var
  I: Integer;
begin
  for I := 0 to High(AProfile.Bindings[AAction]) do
    if (AProfile.Bindings[AAction][I].Key = ABinding.Key) and
       (AProfile.Bindings[AAction][I].Shift = ABinding.Shift) then
      Exit;
  AddBinding(AProfile, AAction, ABinding);
end;

/// <summary>Applies the "bindings" object of ARootObj onto AProfile in place —
/// only actions present in the JSON are touched; everything else in AProfile
/// (e.g. a resource-loaded default) is left as-is. Shared by ParseKeymapJson
/// (fresh profile) and MergeKeymapJson (override on top of an existing one).</summary>
procedure ApplyBindingsFromRootObj(ARootObj: TJSONObject; var AProfile: TKeymapProfile);
var
  BindVal: TJSONValue;
  BindObj: TJSONObject;
  Act: TKeymapAction;
begin
  BindVal := ARootObj.Values['bindings'];
  if BindVal is TJSONObject then
  begin
    BindObj := TJSONObject(BindVal);
    for Act := Low(TKeymapAction) to High(TKeymapAction) do
      ApplyBindingsForAction(BindObj, Act, AProfile);
  end;

  // Ensure Del / Shift+Del are always available for Delete / Wipe.
  EnsureBindingPresent(AProfile, kaDelete, KeyBinding(vkDelete, False, False, False));
  EnsureBindingPresent(AProfile, kaWipe, KeyBinding(vkDelete, True, False, False));
end;

function ParseKeymapJson(const AJsonText: string; out AProfile: TKeymapProfile): Boolean;
var
  RootVal: TJSONValue;
  RootObj: TJSONObject;
  ProfStr: string;
begin
  Result := False;
  AProfile := GetDefaultNDNProfile;
  if Trim(AJsonText) = '' then
    Exit;

  try
    RootVal := TJSONObject.ParseJSONValue(AJsonText);
    if not (RootVal is TJSONObject) then
    begin
      if Assigned(RootVal) then
        RootVal.Free;
      Exit;
    end;

    RootObj := TJSONObject(RootVal);
    try
      if RootObj.Values['profile'] <> nil then
      begin
        ProfStr := RootObj.Values['profile'].Value;
        if SameText(ProfStr, 'FAR') then
          AProfile := GetDefaultFARProfile;
      end;

      ApplyBindingsFromRootObj(RootObj, AProfile);
      Result := True;
    finally
      RootObj.Free;
    end;
  except
    Result := False;
    AProfile := GetDefaultNDNProfile;
  end;
end;

/// <summary>Overrides hotkeys on top of an already-loaded AProfile — only
/// actions present in AJsonText's "bindings" are replaced; the rest of
/// AProfile (typically the resource-loaded default) is untouched. Used to
/// apply a user's config-dir keymap.json over the embedded default.</summary>
function MergeKeymapJson(const AJsonText: string; var AProfile: TKeymapProfile): Boolean;
var
  RootVal: TJSONValue;
  RootObj: TJSONObject;
begin
  Result := False;
  if Trim(AJsonText) = '' then
    Exit;

  try
    RootVal := TJSONObject.ParseJSONValue(AJsonText);
    if not (RootVal is TJSONObject) then
    begin
      if Assigned(RootVal) then
        RootVal.Free;
      Exit;
    end;

    RootObj := TJSONObject(RootVal);
    try
      ApplyBindingsFromRootObj(RootObj, AProfile);
      Result := True;
    finally
      RootObj.Free;
    end;
  except
    Result := False;
  end;
end;

var
  GKeymapLoaded: Boolean = False;
  GKeymapOk: Boolean = False;
  GKeymapPath: string = '';
  GKeymapProfile: TKeymapProfile;
  GKeymapLoadCount: Integer = 0; // tests / diagnostics

function GetDefaultKeymapPath: string;
begin
  // Canonical location: config dir (AppData or portable exe folder).
  Result := GetConfigFilePath('keymap.json');
end;

procedure SaveKeymapProfile(const AProfile: TKeymapProfile; const APath: string);
var
  ActualPath: string;
begin
  ActualPath := APath;
  if ActualPath = '' then
    ActualPath := GetDefaultKeymapPath;
  TFile.WriteAllText(ActualPath, KeymapProfileToJson(AProfile), TEncoding.UTF8);
end;

const
  cResKeymapDefault = 'KEYMAP_DEFAULT';

/// <summary>Reads KEYMAP_DEFAULT RCDATA (config/keymap.json, embedded via
/// MTN2.rc/MTN2Resource.rc). Mirrors uDialogResources.TryLoadDialogResourceJson.</summary>
function TryLoadKeymapResourceJson(out AJson: string): Boolean;
var
  RS: TResourceStream;
  Bytes: TBytes;
begin
  AJson := '';
  Result := False;
  if FindResource(HInstance, cResKeymapDefault, RT_RCDATA) = 0 then
    Exit;
  try
    RS := TResourceStream.Create(HInstance, cResKeymapDefault, RT_RCDATA);
    try
      SetLength(Bytes, RS.Size);
      if RS.Size > 0 then
        RS.ReadBuffer(Bytes[0], RS.Size);
      AJson := TEncoding.UTF8.GetString(Bytes);
      if (Length(AJson) > 0) and (Ord(AJson[1]) = $FEFF) then
        Delete(AJson, 1, 1);
      Result := Trim(AJson) <> '';
    finally
      RS.Free;
    end;
  except
    AJson := '';
    Result := False;
  end;
end;

function LoadDefaultKeymapProfile: TKeymapProfile;
var
  Json: string;
begin
  if not (TryLoadKeymapResourceJson(Json) and ParseKeymapJson(Json, Result)) then
    Result := GetDefaultNDNProfile;
end;

function LoadKeymapFromFile(const APath: string): TKeymapProfile;
var
  Content: string;
  ActualPath: string;
begin
  Inc(GKeymapLoadCount);
  Result := LoadDefaultKeymapProfile;
  ActualPath := APath;
  if ActualPath = '' then
    ActualPath := GetDefaultKeymapPath;

  // A user keymap.json in the config dir only overrides the hotkeys it
  // mentions — everything else stays on the embedded default above.
  if System.SysUtils.FileExists(ActualPath) then
  begin
    try
      Content := TFile.ReadAllText(ActualPath, TEncoding.UTF8);
      MergeKeymapJson(Content, Result);
    except
      // keep the embedded default profile already in Result
    end;
  end;
end;

function ReloadKeymap(const APath: string): Boolean;
var
  Path: string;
begin
  Path := APath;
  if Path = '' then
    Path := GetDefaultKeymapPath;
  GKeymapProfile := LoadKeymapFromFile(Path);
  GKeymapPath := Path;
  GKeymapLoaded := True;
  // Ok = a user override file was found and applied on top of the embedded default.
  Result := FileExists(Path);
  GKeymapOk := Result;
  if GKeymapProfile.Name = '' then
    GKeymapProfile := GetDefaultNDNProfile;
  if Assigned(GKeymapOverlayHook) then
    GKeymapOverlayHook(GKeymapProfile);
end;

function ActiveKeymap: TKeymapProfile;
begin
  if not GKeymapLoaded then
    ReloadKeymap('');
  Result := GKeymapProfile;
end;

function KeymapCacheLoaded: Boolean;
begin
  Result := GKeymapLoaded;
end;

function MatchActiveAction(AKey: Word; AShiftState: TShiftState): TKeymapAction;
begin
  Result := MatchAction(ActiveKeymap, AKey, AShiftState);
end;

/// <summary>Test helper: how many times LoadKeymapFromFile ran.</summary>
function KeymapFileLoadCount: Integer;
begin
  Result := GKeymapLoadCount;
end;

function KeymapFBarShortLabel(AAction: TKeymapAction): string;
begin
  case AAction of
    kaHelp: Result := 'Help';
    kaPack: Result := 'Pack';
    kaUserMenu: Result := 'Menu';
    kaUnpack: Result := 'Unpk';
    kaView: Result := 'View';
    kaEdit: Result := 'Edit';
    kaCopy: Result := 'Copy';
    kaMove: Result := 'Move';
    kaRename: Result := 'Renam';
    kaCopyInPlace: Result := 'CopyH';
    kaMkDir: Result := 'MkDir';
    kaCreateLink: Result := 'Link';
    kaSetAttributes: Result := 'Attr';
    kaDelete: Result := 'Del';
    kaWipe: Result := 'Wipe';
    kaQuit: Result := 'Quit';
    kaFind: Result := 'Find';
    kaTogglePanelLeft: Result := 'Left';
    kaTogglePanelRight: Result := 'Right';
    kaSortByName: Result := 'Name';
    kaSortByExt: Result := 'Ext';
    kaSortByDate: Result := 'Time';
    kaSortBySize: Result := 'Size';
    kaSortUnsorted: Result := 'Unsrt';
    kaSortByCreated: Result := 'Creat';
    kaSortByAccessed: Result := 'Acces';
    kaExternalView: Result := 'ExtVw';
    kaExternalEdit: Result := 'ExtEd';
  else
    Result := '';
  end;
end;

procedure ApplyKeymapToFBarItems(const AProfile: TKeymapProfile; AMods: TShiftState;
  var AItems: TArray<string>);
var
  Act: TKeymapAction;
  I, FNum: Integer;
  B: TKeyBinding;
  WantShift, WantAlt, WantCtrl: Boolean;
  Lbl, Prefix: string;
begin
  if Length(AItems) < 10 then
    SetLength(AItems, 10);
  WantShift := ssShift in AMods;
  WantAlt := ssAlt in AMods;
  WantCtrl := ssCtrl in AMods;
  for Act := Low(TKeymapAction) to High(TKeymapAction) do
  begin
    Lbl := KeymapFBarShortLabel(Act);
    if Lbl = '' then
      Continue;
    for I := 0 to High(AProfile.Bindings[Act]) do
    begin
      B := AProfile.Bindings[Act][I];
      if (B.Key < vkF1) or (B.Key > vkF10) then
        Continue;
      if (B.Shift <> WantShift) or (B.Alt <> WantAlt) or (B.Ctrl <> WantCtrl) then
        Continue;
      FNum := Integer(B.Key - vkF1) + 1;
      if FNum = 10 then
        Prefix := '10'
      else
        Prefix := IntToStr(FNum);
      AItems[FNum - 1] := Prefix + Lbl;
    end;
  end;
end;

end.
