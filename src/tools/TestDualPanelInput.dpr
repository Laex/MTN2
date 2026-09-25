program TestDualPanelInput;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap in '..\Core\uKeymap.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelInput in '..\Core\uDualPanelInput.pas',
  uDualPanelSelection in '..\Core\uDualPanelSelection.pas',
  uColorCodingEditHelpers in '..\Core\uColorCodingEditHelpers.pas';

type
  TKeymapSpy = class
  public
    Last: string;
    Side: TPanelSide;
    Job: TPanelJobKind;
    Recycle: Boolean;
    Edit: Boolean;
    Delta: Integer;
    SelectDelta: Integer;
    ExcludeLanding: Boolean;
    CmdHandled: Boolean;
    function ActiveSide: TPanelSide;
    procedure CopyFullPath;
    procedure ShowProperties;
    procedure ExternalView;
    procedure ExternalEdit;
    procedure CompareFolders;
    procedure RequestQuit;
    procedure TogglePanel(ASide: TPanelSide);
    procedure BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean);
    procedure OpenViewOrEdit(AEdit: Boolean);
    procedure MoveCursor(ADelta: Integer);
    procedure MoveCursorWithSelect(ADelta: Integer; AExcludeLanding: Boolean);
    procedure ToggleInsertSelect;
    procedure SubmitCommandLine;
    procedure FocusCommandLine;
    function HandleCmdLineInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
  end;

  TFreeInputSpy = class
  public
    Last: string;
    Delta: Integer;
    MaskUnselect: Boolean;
    GrayCalls: Integer;
    FilterHandled: Boolean;
    PasteOk: Boolean;
    CmdHandled: Boolean;
    PrimaryHandled: Boolean;
    FuncHandled: Boolean;
    HotlistHandled: Boolean;
    QuickHandled: Boolean;
    procedure CancelDrive;
    procedure CloseQV;
    procedure ClearCmd;
    function HandleFilter(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function DispatchPrimary(AAction: TKeymapAction; var AKey: Word;
      var AKeyChar: Char): Boolean;
    procedure Preview(ADelta: Integer);
    procedure NavRoot;
    function Paste: Boolean;
    procedure RestoreGray(var AKey: Word; var AKeyChar: Char);
    procedure SelectMask(AUnselect: Boolean);
    procedure Invert;
    procedure SelectExt(AUnselect: Boolean);
    procedure SelectAllFiles(AUnselect: Boolean);
    procedure SelectByName(AUnselect: Boolean);
    function QuickSearch(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function CmdLine(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    procedure SwitchSide;
    procedure NewTab;
    procedure NewWs;
    procedure NextTab;
    procedure Refresh;
    procedure SelectAll;
    function Hotlist(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function DispatchFunc(AAction: TKeymapAction; var AKey: Word;
      var AKeyChar: Char): Boolean;
    procedure ViewEdit(AEdit: Boolean);
  end;

  TModalSpy = class
  public
    Last: string;
    CmdId: string;
    Hotlist, ColorList, ColorEdit, Filter, Widget: Boolean;
    Synced: Boolean;
    DropOpen: Boolean;
    HistoryFor: string;
    function DropIsOpen: Boolean;
    procedure RecordHistory(const AId: string);
    function FocusedId: string;
    procedure Command(const AId, AJson: string);
    function HotlistIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function ColorIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function EditIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function FilterIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    function WidgetIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
    procedure SyncHex;
  end;

function TKeymapSpy.ActiveSide: TPanelSide;
begin
  Result := psLeft;
end;

procedure TKeymapSpy.CopyFullPath;
begin
  Last := 'copyfull';
end;

procedure TKeymapSpy.ExternalView;
begin
  Last := 'extview';
end;

procedure TKeymapSpy.ExternalEdit;
begin
  Last := 'extedit';
end;

procedure TKeymapSpy.CompareFolders;
begin
  Last := 'comparefolders';
end;

procedure TKeymapSpy.ShowProperties;
begin
  Last := 'properties';
end;

procedure TKeymapSpy.RequestQuit;
begin
  Last := 'quit';
end;

procedure TKeymapSpy.TogglePanel(ASide: TPanelSide);
begin
  Last := 'toggle';
  Side := ASide;
end;

procedure TKeymapSpy.BeginJob(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean);
begin
  Last := 'job';
  Job := AKind;
  Recycle := ADeleteToRecycleBin;
end;

procedure TKeymapSpy.OpenViewOrEdit(AEdit: Boolean);
begin
  Last := 'viewedit';
  Edit := AEdit;
end;

procedure TKeymapSpy.MoveCursor(ADelta: Integer);
begin
  Last := 'move';
  Delta := ADelta;
end;

procedure TKeymapSpy.MoveCursorWithSelect(ADelta: Integer; AExcludeLanding: Boolean);
begin
  Last := 'select';
  SelectDelta := ADelta;
  ExcludeLanding := AExcludeLanding;
end;

procedure TKeymapSpy.ToggleInsertSelect;
begin
  Last := 'insert';
end;

procedure TKeymapSpy.SubmitCommandLine;
begin
  Last := 'submit';
end;

procedure TKeymapSpy.FocusCommandLine;
begin
  Last := 'focus';
end;

function TKeymapSpy.HandleCmdLineInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Last := Last + '+cmd';
  CmdHandled := True;
  Result := True;
end;

procedure BindSpy(var AHost: TDualPanelKeymapHost; ASpy: TKeymapSpy);
begin
  FillChar(AHost, SizeOf(AHost), 0);
  AHost.ActiveSide := ASpy.ActiveSide;
  AHost.CopyFullPathToClipboard := ASpy.CopyFullPath;
  AHost.ShowProperties := ASpy.ShowProperties;
  AHost.ExternalView := ASpy.ExternalView;
  AHost.ExternalEdit := ASpy.ExternalEdit;
  AHost.CompareFolders := ASpy.CompareFolders;
  AHost.RequestQuit := ASpy.RequestQuit;
  AHost.TogglePanelVisible := ASpy.TogglePanel;
  AHost.BeginJob := ASpy.BeginJob;
  AHost.OpenViewOrEdit := ASpy.OpenViewOrEdit;
  AHost.MoveCursor := ASpy.MoveCursor;
  AHost.MoveCursorWithSelect := ASpy.MoveCursorWithSelect;
  AHost.ToggleInsertSelect := ASpy.ToggleInsertSelect;
  AHost.SubmitCommandLine := ASpy.SubmitCommandLine;
  AHost.FocusCommandLine := ASpy.FocusCommandLine;
  AHost.HandleCmdLineInput := ASpy.HandleCmdLineInput;
end;

procedure TestInputTranslation;
var
  LAction: TDualPanelInputAction;
begin
  LAction := TDualPanelInputHandler.TranslateShortcut(vkF5, [], #0);
  Assert(LAction = iaCopy, 'F5 should translate to iaCopy');

  LAction := TDualPanelInputHandler.TranslateShortcut(vkF8, [], #0);
  Assert(LAction = iaDelete, 'F8 should translate to iaDelete');

  LAction := TDualPanelInputHandler.TranslateShortcut(vkO, [ssCtrl], #0);
  Assert(LAction = iaToggleConsole, 'Ctrl+O should translate to iaToggleConsole');

  Assert(TDualPanelInputHandler.IsNavigationKey(vkUp), 'vkUp should be navigation key');
  Assert(not TDualPanelInputHandler.IsNavigationKey(vkF1), 'vkF1 should not be navigation key');

  Writeln('OK: TestInputTranslation passed');
end;

procedure TestKeymapDispatchConsume;
var
  Spy: TKeymapSpy;
  Host: TDualPanelKeymapHost;
  Key: Word;
  KeyChar: Char;
begin
  Spy := TKeymapSpy.Create;
  try
    BindSpy(Host, Spy);

    Key := vkF5;
    KeyChar := 'x';
    Assert(not DispatchKeymapActionPrimary(Host, kaNone, Key, KeyChar),
      'kaNone is not a primary action');
    Assert(Key = vkF5, 'unhandled action must leave AKey');
    Assert(KeyChar = 'x', 'unhandled action must leave AKeyChar');

    Key := vkC;
    KeyChar := 'c';
    Assert(DispatchKeymapActionPrimary(Host, kaCopyFullPath, Key, KeyChar),
      'kaCopyFullPath is primary');
    Assert(Spy.Last = 'copyfull', 'copy-full-path host called');
    Assert(Key = 0, 'copy-full-path consumes AKey');
    Assert(KeyChar = #0, 'copy-full-path consumes AKeyChar');

    // Alt+Enter: Alt quick search (after the primary dispatch) would take
    // it as a search key, so Properties must be primary.
    Spy.Last := '';
    Key := vkReturn;
    KeyChar := #13;
    Assert(DispatchKeymapActionPrimary(Host, kaProperties, Key, KeyChar),
      'kaProperties is primary');
    Assert(Spy.Last = 'properties', 'Properties host called');
    Assert((Key = 0) and (KeyChar = #0), 'Properties consumes the key');
    Assert(IsAltQuickSearchChord(vkReturn, [ssAlt]),
      'Alt+Enter would be quick search if it got that far');

    // Alt+F3 / Alt+F4: the same trap as Alt+Enter.
    Key := vkF3;
    KeyChar := #0;
    Assert(DispatchKeymapActionPrimary(Host, kaExternalView, Key, KeyChar),
      'kaExternalView is primary');
    Assert((Spy.Last = 'extview') and (Key = 0), 'external viewer host called');
    Key := vkF4;
    Assert(DispatchKeymapActionPrimary(Host, kaExternalEdit, Key, KeyChar),
      'kaExternalEdit is primary');
    Assert((Spy.Last = 'extedit') and (Key = 0), 'external editor host called');
    Assert(IsAltQuickSearchChord(vkF4, [ssAlt]),
      'Alt+F4 would be quick search if it got that far');

    Key := vkF10;
    KeyChar := 'X';
    Assert(DispatchKeymapActionPrimary(Host, kaQuit, Key, KeyChar), 'kaQuit is primary');
    Assert(Spy.Last = 'quit', 'quit host called');
    Assert(Key = 0, 'kaQuit consumes AKey');
    Assert(KeyChar = 'X', 'kaQuit must not clear AKeyChar');

    Key := vkF1;
    KeyChar := 'L';
    Assert(DispatchKeymapActionPrimary(Host, kaTogglePanelLeft, Key, KeyChar),
      'kaTogglePanelLeft is primary');
    Assert((Spy.Last = 'toggle') and (Spy.Side = psLeft), 'toggle left host called');
    Assert(Key = 0, 'toggle-panel consumes AKey');
    Assert(KeyChar = 'L', 'toggle-panel must not clear AKeyChar');

    Key := vkF5;
    KeyChar := 'c';
    Assert(DispatchKeymapActionFunctionKeys(Host, kaCopy, Key, KeyChar),
      'kaCopy is a function-key action');
    Assert((Spy.Last = 'job') and (Spy.Job = pjkCopy) and Spy.Recycle,
      'kaCopy begins copy with recycle default');
    Assert(Key = 0, 'kaCopy consumes AKey');
    Assert(KeyChar = 'c', 'kaCopy must not clear AKeyChar');

    Key := vkF8;
    KeyChar := 'w';
    Assert(DispatchKeymapActionFunctionKeys(Host, kaWipe, Key, KeyChar),
      'kaWipe is a function-key action');
    Assert((Spy.Job = pjkDelete) and (not Spy.Recycle), 'kaWipe deletes without recycle');
    Assert(KeyChar = #0, 'kaWipe consumes AKeyChar');

    Key := vkF3;
    KeyChar := 'v';
    Assert(DispatchKeymapActionFunctionKeys(Host, kaView, Key, KeyChar),
      'kaView is a function-key action');
    Assert((Spy.Last = 'viewedit') and (not Spy.Edit), 'kaView opens viewer');
    Assert(KeyChar = #0, 'kaView consumes AKeyChar');

    Key := vkF4;
    KeyChar := 'e';
    Assert(DispatchKeymapActionFunctionKeys(Host, kaEdit, Key, KeyChar),
      'kaEdit is a function-key action');
    Assert(Spy.Edit, 'kaEdit opens editor');
    Assert(KeyChar = 'e', 'kaEdit must not clear AKeyChar');

    Writeln('OK: TestKeymapDispatchConsume passed');
  finally
    Spy.Free;
  end;
end;

procedure TestNavDispatch;
var
  Spy: TKeymapSpy;
  Host: TDualPanelKeymapHost;
  Key: Word;
  KeyChar: Char;
begin
  Spy := TKeymapSpy.Create;
  try
    BindSpy(Host, Spy);

    Key := vkUp;
    KeyChar := #0;
    Assert(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 2, 20), 'Up handled');
    Assert((Spy.Last = 'move') and (Spy.Delta = -1), 'Up moves -1');
    Assert(Key = 0, 'Up consumes AKey');

    Key := vkUp;
    Assert(DispatchPanelNavKeys(Host, Key, [ssShift], KeyChar, 10, 2, 20),
      'Shift+Up handled');
    Assert((Spy.Last = 'select') and (Spy.SelectDelta = -1) and
      (not Spy.ExcludeLanding), 'Shift+Up selects leaving row');
    Assert(Key = 0, 'Shift+Up consumes AKey');

    Key := vkLeft;
    Assert(not DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20),
      'Left with 1 col is unhandled');
    Assert(Key = vkLeft, 'unhandled Left leaves AKey');

    Key := vkLeft;
    Assert(DispatchPanelNavKeys(Host, Key, [ssShift], KeyChar, 10, 2, 20),
      'Shift+Left in brief handled');
    Assert((Spy.Last = 'select') and (Spy.SelectDelta = -10) and
      Spy.ExcludeLanding, 'Shift+Left excludes landing');

    Key := vkInsert;
    Assert(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20), 'Insert handled');
    Assert(Spy.Last = 'insert', 'Insert toggles select');
    Assert(Key = 0, 'Insert consumes AKey');

    Key := vkInsert;
    Assert(not DispatchPanelNavKeys(Host, Key, [ssCtrl], KeyChar, 10, 1, 20),
      'Ctrl+Insert is unhandled');
    Assert(Key = vkInsert, 'Ctrl+Insert leaves AKey');

    Key := vkReturn;
    Assert(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20), 'Return handled');
    Assert(Spy.Last = 'submit', 'Return submits cmdline');
    Assert(Key = 0, 'Return consumes AKey');

    Spy.Last := '';
    Key := vkReturn;
    Assert(not DispatchPanelNavKeys(Host, Key, [ssCtrl, ssAlt], KeyChar, 10, 1, 20),
      'Ctrl+Alt+Enter is not Activate/submit');
    Assert(Spy.Last = '', 'Ctrl+Alt+Enter does not submit cmdline');
    Assert(Key = vkReturn, 'Ctrl+Alt+Enter leaves AKey for panel handler');

    Key := Ord('A');
    KeyChar := 'a';
    Assert(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20),
      'printable goes to cmdline');
    Assert(Spy.Last = 'focus+cmd', 'printable focuses then feeds cmdline');

    Writeln('OK: TestNavDispatch passed');
  finally
    Spy.Free;
  end;
end;

procedure TFreeInputSpy.CancelDrive; begin Last := 'canceldrive'; end;
procedure TFreeInputSpy.CloseQV; begin Last := 'closeqv'; end;
procedure TFreeInputSpy.ClearCmd; begin Last := 'clearcmd'; end;
function TFreeInputSpy.HandleFilter(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Last := 'filter';
  Result := FilterHandled;
end;
function TFreeInputSpy.DispatchPrimary(AAction: TKeymapAction; var AKey: Word;
  var AKeyChar: Char): Boolean;
begin
  Result := PrimaryHandled;
  if Result then
  begin
    Last := 'primary';
    AKey := 0;
  end;
end;
procedure TFreeInputSpy.Preview(ADelta: Integer); begin Last := 'preview'; Delta := ADelta; end;
procedure TFreeInputSpy.NavRoot; begin Last := 'navroot'; end;
function TFreeInputSpy.Paste: Boolean; begin Last := 'paste'; Result := PasteOk; end;
procedure TFreeInputSpy.RestoreGray(var AKey: Word; var AKeyChar: Char);
begin
  Inc(GrayCalls);
  RestoreGrayOpKey(AKey, AKeyChar);
end;
procedure TFreeInputSpy.SelectMask(AUnselect: Boolean); begin Last := 'mask'; MaskUnselect := AUnselect; end;
procedure TFreeInputSpy.Invert; begin Last := 'invert'; end;
procedure TFreeInputSpy.SelectExt(AUnselect: Boolean); begin Last := 'ext'; MaskUnselect := AUnselect; end;
procedure TFreeInputSpy.SelectAllFiles(AUnselect: Boolean); begin Last := 'allfiles'; MaskUnselect := AUnselect; end;
procedure TFreeInputSpy.SelectByName(AUnselect: Boolean); begin Last := 'byname'; MaskUnselect := AUnselect; end;
function TFreeInputSpy.QuickSearch(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Last := 'quick';
  Result := QuickHandled;
end;
function TFreeInputSpy.CmdLine(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Last := 'cmdline';
  Result := CmdHandled;
end;
procedure TFreeInputSpy.SwitchSide; begin Last := 'switch'; end;
procedure TFreeInputSpy.NewTab; begin Last := 'newtab'; end;
procedure TFreeInputSpy.NewWs; begin Last := 'newws'; end;
procedure TFreeInputSpy.NextTab; begin Last := 'nexttab'; end;
procedure TFreeInputSpy.Refresh; begin Last := 'refresh'; end;
procedure TFreeInputSpy.SelectAll; begin Last := 'selectall'; end;
function TFreeInputSpy.Hotlist(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := HotlistHandled;
  if Result then
    Last := 'hotlist';
end;
function TFreeInputSpy.DispatchFunc(AAction: TKeymapAction; var AKey: Word;
  var AKeyChar: Char): Boolean;
begin
  Result := FuncHandled;
  if Result then
  begin
    Last := 'func';
    AKey := 0;
  end;
end;
procedure TFreeInputSpy.ViewEdit(AEdit: Boolean); begin Last := 'view'; end;

procedure BindFree(var AHost: TDualPanelFreeInputHost; ASpy: TFreeInputSpy);
begin
  AHost := Default(TDualPanelFreeInputHost);
  AHost.CancelDrivePreview := ASpy.CancelDrive;
  AHost.CloseQuickView := ASpy.CloseQV;
  AHost.ClearCmdLineOnEsc := ASpy.ClearCmd;
  AHost.HandleFilterInput := ASpy.HandleFilter;
  AHost.DispatchKeymapPrimary := ASpy.DispatchPrimary;
  AHost.PreviewCycleDrive := ASpy.Preview;
  AHost.NavigateActiveToDriveRoot := ASpy.NavRoot;
  AHost.TryPasteClipboard := ASpy.Paste;
  AHost.RestoreGrayOpKey := ASpy.RestoreGray;
  AHost.BeginSelectByMask := ASpy.SelectMask;
  AHost.InvertSelectionActive := ASpy.Invert;
  AHost.ApplySelectByExtension := ASpy.SelectExt;
  AHost.ApplySelectAllFiles := ASpy.SelectAllFiles;
  AHost.ApplySelectByName := ASpy.SelectByName;
  AHost.HandleQuickSearchInput := ASpy.QuickSearch;
  AHost.HandleCmdLineInput := ASpy.CmdLine;
  AHost.SwitchSide := ASpy.SwitchSide;
  AHost.NewPanelTab := ASpy.NewTab;
  AHost.NewWorkspace := ASpy.NewWs;
  AHost.NextPanelTab := ASpy.NextTab;
  AHost.RefreshActive := ASpy.Refresh;
  AHost.SelectAllActive := ASpy.SelectAll;
  AHost.TryHotlistJump := ASpy.Hotlist;
  AHost.DispatchKeymapFunctionKeys := ASpy.DispatchFunc;
  AHost.OpenViewOrEdit := ASpy.ViewEdit;
end;

procedure TestClassifyAndFreeInput;
var
  Spy: TFreeInputSpy;
  NavSpy: TKeymapSpy;
  Host: TDualPanelFreeInputHost;
  Keymap: TDualPanelKeymapHost;
  Snap: TPanelFreeInputSnap;
  Key: Word;
  Ch: Char;
begin
  Key := 0;
  Ch := #9;
  NormalizePanelInputKey(Key, Ch);
  Key := vkTab;
  Ch := #13;
  NormalizePanelInputKey(Key, Ch);
  Assert(Key = vkTab, 'Tab stays Tab despite CR KeyChar');
  Key := 0;
  Ch := #13;
  NormalizePanelInputKey(Key, Ch);
  Assert(Key = vkReturn, 'CR becomes vkReturn');
  Key := 10;
  Ch := #0;
  NormalizePanelInputKey(Key, Ch);
  Assert(Key = vkReturn, 'LF key becomes vkReturn');

  Assert(ShouldOfferTopMenu(wkPanels, False), 'panels offer top menu');
  Assert(ShouldOfferTopMenu(wkDocument, False), 'document offers top menu');
  Assert(ShouldOfferTopMenu(wkTerminal, False), 'terminal offers top menu');
  Assert(not ShouldOfferTopMenu(wkPanels, True), 'dialog hides top menu');
  Assert(not ShouldOfferTopMenu(wkDocument, True), 'dialog hides menu on document');
  Assert(IsWorkspaceCycleChord(vkTab, [ssCtrl], False), 'Ctrl+Tab cycles');
  Assert(IsWorkspaceCycleChord(vkTab, [ssCtrl, ssAlt], False),
    'Ctrl+Tab cycles with leftover Alt');
  Assert(IsWorkspaceCycleChord(vkTab, [ssCtrl, ssShift], False),
    'Ctrl+Shift+Tab cycles');
  Assert(not IsWorkspaceCycleChord(vkTab, [ssCtrl], True), 'dialog blocks cycle');
  Assert(IsConsoleToggleChord(Ord('O'), [ssCtrl], False), 'Ctrl+O console');
  Assert(IsConsoleToggleChord(Ord('o'), [ssCtrl], False), 'ctrl+o lowercase');
  Assert(not IsConsoleToggleChord(vkEscape, [], False), 'Esc is not host Ctrl+O');
  Assert(not IsConsoleToggleChord(Ord('O'), [ssCtrl], True), 'dialog blocks Ctrl+O');
  Assert(not IsConsoleToggleChord(Ord('O'), [ssCtrl, ssShift], False),
    'Ctrl+Shift+O is not console toggle');
  Assert(IsHelpChord(vkF1, [], False), 'F1 help');
  Assert(not IsHelpChord(vkF1, [ssShift], False), 'Shift+F1 is not help');
  Assert(not IsHelpChord(vkF1, [], True), 'dialog blocks F1');
  Assert(IsContextHelpChord(vkF1, [], True, False), 'F1 over the open top menu');
  Assert(IsContextHelpChord(vkF1, [], False, True), 'F1 over a dialog without its own F1');
  Assert(not IsContextHelpChord(vkF1, [], False, False), 'nothing to be context for');
  Assert(not IsContextHelpChord(vkF1, [ssShift], True, True), 'Shift+F1 is not help');
  Assert(not IsContextHelpChord(vkF2, [], True, True), 'only F1');
  Assert(IsNewTerminalChord(Ord('N'), [ssCtrl, ssShift], False), 'Ctrl+Shift+N');
  Assert(not IsNewTerminalChord(Ord('N'), [ssCtrl], False), 'Ctrl+N is not new terminal');
  Assert(not IsNewTerminalChord(Ord('N'), [ssCtrl, ssShift], True),
    'dialog blocks new terminal');
  Assert(IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssAlt], False),
    'Ctrl+Alt+O console profile');
  Assert(IsSelectConsoleProfileChord(Ord('o'), [ssCtrl, ssAlt], False),
    'ctrl+alt+o lowercase');
  Assert(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl], False),
    'Ctrl+O is not console profile');
  Assert(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssShift], False),
    'Ctrl+Shift+O is not console profile');
  Assert(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssAlt], True),
    'dialog blocks console profile');
  Assert(IsAppQuitChord(Ord('X'), [ssAlt], False), 'Alt+X quit');
  Assert(not IsAppQuitChord(vkF10, [], False), 'F10 is not app quit on embed');
  Assert(not IsAppQuitChord(Ord('X'), [ssAlt], True), 'dialog blocks Alt+X');
  Assert(ClassifyEmbeddedInputOwner(wkDocument, False, False) = eioDocument, 'doc owner');
  Assert(ClassifyEmbeddedInputOwner(wkTerminal, False, False) = eioTerminal, 'term owner');
  Assert(ClassifyEmbeddedInputOwner(wkPanels, False, True) = eioConsoleYield, 'console yield');
  Assert(ClassifyEmbeddedInputOwner(wkDocument, True, True) = eioNone, 'dialog wins over embed');
  Assert(IsPasteChord(vkInsert, [ssShift], #0), 'Shift+Ins paste');
  Assert(IsPasteChord(Ord('V'), [ssCtrl], 'v'), 'Ctrl+V paste');
  Assert(not IsPasteChord(Ord('V'), [ssCtrl, ssAlt], 'v'), 'Ctrl+Alt+V is not paste');
  Assert(IsAltQuickSearchChord(Ord('A'), [ssAlt]), 'Alt+A quick search');
  Assert(not IsAltQuickSearchChord(vkF7, [ssAlt]), 'Alt+F7 is not quick search');
  Assert(not IsAltQuickSearchChord(vkAdd, [ssAlt]), 'Alt+Gray+ is not quick search');
  Assert(not IsAltQuickSearchChord(vkSubtract, [ssAlt]), 'Alt+Gray- is not quick search');
  Assert(not IsAltQuickSearchChord(Ord('+'), [ssAlt]), 'Alt+Ord(+) is not quick search');
  Assert(not IsAltQuickSearchChord(Ord('-'), [ssAlt]), 'Alt+Ord(-) is not quick search');

  Spy := TFreeInputSpy.Create;
  NavSpy := TKeymapSpy.Create;
  try
    BindFree(Host, Spy);
    BindSpy(Keymap, NavSpy);
    Snap := Default(TPanelFreeInputSnap);
    Snap.ViewH := 10;
    Snap.Cols := 1;
    Snap.PageSize := 10;

    Snap.DrivePreviewActive := True;
    Key := vkEscape;
    Ch := 'x';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'preview Esc handled');
    Assert(Spy.Last = 'canceldrive', 'preview Esc cancels');
    Assert(Key = 0, 'preview Esc consumes AKey');
    Assert(Ch = 'x', 'preview Esc leaves AKeyChar');

    Snap.DrivePreviewActive := False;
    Snap.QuickViewVisible := True;
    Key := vkEscape;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'QV Esc handled');
    Assert(Spy.Last = 'closeqv', 'QV Esc closes');

    Snap.QuickViewVisible := False;
    Snap.CmdLineHasText := True;
    Key := vkEscape;
    Ch := 'x';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'cmdline Esc handled');
    Assert(Spy.Last = 'clearcmd', 'cmdline Esc clears');
    Assert(Ch = #0, 'cmdline Esc consumes AKeyChar');

    Snap.CmdLineHasText := False;
    Snap.FilterBoxActive := True;
    Spy.FilterHandled := True;
    Key := vkEscape;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'filter handled');
    Assert(Spy.Last = 'filter', 'filter box gets Esc');

    Snap.FilterBoxActive := False;
    Spy.PrimaryHandled := True;
    Key := vkF10;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'primary handled');
    Assert(Spy.Last = 'primary', 'keymap primary wins');

    Spy.PrimaryHandled := False;
    Key := vkLeft;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'Ctrl+Left handled');
    Assert((Spy.Last = 'preview') and (Spy.Delta = -1), 'Ctrl+Left previews prev drive');
    Assert(Key = 0, 'Ctrl+Left consumes AKey');

    Key := vkBackslash;
    Ch := '\';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'Ctrl+\\ handled');
    Assert(Spy.Last = 'navroot', 'Ctrl+\\ goes to drive root');
    Assert(Ch = #0, 'Ctrl+\\ consumes AKeyChar');

    Spy.PasteOk := True;
    Key := Ord('V');
    Ch := 'v';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'paste handled');
    Assert(Spy.Last = 'paste', 'Ctrl+V pastes');

    // Command line focused (Ctrl+Down): - + * are text, not selection keys.
    // HandleInput has already restored '-' to vkSubtract by then.
    Snap.CmdFocused := True;
    Spy.CmdHandled := True;
    Spy.PrimaryHandled := True;
    for Ch in ['-', '+', '*', ' '] do
    begin
      Spy.Last := '';
      case Ch of
        '-': Key := vkSubtract;
        '+': Key := vkAdd;
        '*': Key := vkMultiply;
      else
        Key := 0;
      end;
      Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
        'focused cmdline: char handled');
      Assert(Spy.Last = 'cmdline', 'focused cmdline gets ' + Ch + ' (not the panel binding)');
    end;
    // Not only text: every key, panel bindings and F-keys included.
    Spy.Last := '';
    Key := vkSubtract;
    Ch := '-';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'focused cmdline: Ctrl+- handled');
    Assert(Spy.Last = 'cmdline', 'focused cmdline gets Ctrl+-');
    Spy.Last := '';
    Key := vkF5;
    Ch := #0;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
      'focused cmdline: F5 handled');
    Assert(Spy.Last = 'cmdline', 'focused cmdline gets F5 (no copy)');
    Spy.Last := '';
    Snap.QuickViewVisible := True;
    Key := vkEscape;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
      'focused cmdline: Esc handled');
    Assert(Spy.Last = 'cmdline', 'focused cmdline gets Esc before Quick View');
    Snap.QuickViewVisible := False;
    Spy.PrimaryHandled := False;
    Spy.CmdHandled := False;
    Snap.CmdFocused := False;

    // Panel active (even with text in the command line): '-' deselects.
    Snap.CmdLineHasText := True;
    Spy.Last := '';
    Key := 0;
    Ch := '-';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'panel -: handled');
    Assert((Spy.Last = 'mask') and Spy.MaskUnselect, 'panel -: deselect by mask');
    Snap.CmdLineHasText := False;

    Key := vkAdd;
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Gray+ handled');
    Assert((Spy.Last = 'mask') and (not Spy.MaskUnselect) and (Spy.GrayCalls > 0),
      'Gray+ select mask after restore');
    Assert(Ch = #0, 'Gray+ consumes AKeyChar');

    Key := vkAdd;
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch), 'Alt+Gray+ handled');
    Assert((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Gray+ selects by name stem');
    Assert(Ch = #0, 'Alt+Gray+ consumes AKeyChar');

    Spy.Last := '';
    Key := 0;
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Gray+ as AKey=0 handled');
    Assert((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Gray+ FMX extract selects by name stem');
    Assert(Ch = #0, 'Alt+Gray+ FMX extract consumes AKeyChar');

    Spy.Last := '';
    Key := Ord('+');
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Ord(+) handled');
    Assert((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Ord(+) selects by name stem');

    Spy.Last := '';
    Key := 0;
    Ch := '-';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Gray- as AKey=0 handled');
    Assert((Spy.Last = 'byname') and Spy.MaskUnselect,
      'Alt+Gray- FMX extract unselects by name stem');

    Spy.Last := '';
    Key := vkAdd;
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Gray+ handled');
    Assert((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'Ctrl++ selects by extension');

    Spy.Last := '';
    Key := vkEqual;
    Ch := '=';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+= handled');
    Assert((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'Ctrl+= selects by extension');

    Spy.Last := '';
    Key := vkEqual;
    Ch := '+';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl, ssShift], Ch),
      'Ctrl+Shift+= handled');
    Assert((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'main-keyboard Ctrl++ selects by extension');

    Spy.Last := '';
    Key := vkSubtract;
    Ch := #0;
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Gray- handled');
    Assert((Spy.Last = 'ext') and Spy.MaskUnselect,
      'Ctrl+- unselects by extension');

    Spy.Last := '';
    Key := vkMinus;
    Ch := '-';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Minus handled');
    Assert((Spy.Last = 'ext') and Spy.MaskUnselect,
      'main-keyboard Ctrl+- unselects by extension');

    Spy.Last := '';
    Key := Ord('M');
    Ch := 'm';
    DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch);
    Assert(Spy.Last <> 'ext', 'Ctrl+M is not unselect-by-extension');

    Key := vkInsert;
    Ch := #0;
    RestoreGrayOpKey(Key, Ch);
    Assert(Key = vkInsert, 'RestoreGray leaves Ins (Ord(-) is vkInsert)');
    Key := vkInsert;
    Ch := #0;
    Spy.Last := '';
    NavSpy.Last := '';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Ins handled');
    Assert(NavSpy.Last = 'insert', 'Ins toggles file/dir selection');
    Assert(Spy.Last <> 'mask', 'Ins does not open deselect dialog');
    Assert(Key = 0, 'Ins consumes AKey');

    Key := vkTab;
    Ch := 'x';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Tab handled');
    Assert(Spy.Last = 'switch', 'Tab switches side');
    Assert(Ch = 'x', 'Tab leaves AKeyChar');

    Spy.Last := '';
    Key := vkTab;
    Ch := 'x';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Tab handled');
    Assert(Spy.Last <> 'switch', 'Ctrl+Tab does not switch panel side');
    Assert(Key = 0, 'Ctrl+Tab consumes AKey');

    Key := Ord('T');
    Ch := 't';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl, ssShift], Ch),
      'Ctrl+Shift+T handled');
    Assert(Spy.Last = 'newtab', 'Ctrl+Shift+T new panel tab');

    Key := vkNumpad5;
    Ch := 'x';
    Assert(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Numpad5 handled');
    Assert(Spy.Last = 'view', 'Numpad5 opens viewer');
    Assert(Ch = #0, 'Numpad5 consumes AKeyChar');

    Writeln('OK: TestClassifyAndFreeInput passed');
  finally
    NavSpy.Free;
    Spy.Free;
  end;
end;

function TModalSpy.DropIsOpen: Boolean; begin Result := DropOpen; end;
procedure TModalSpy.RecordHistory(const AId: string); begin HistoryFor := AId; end;
function TModalSpy.FocusedId: string; begin Result := Last; end;
procedure TModalSpy.Command(const AId, AJson: string); begin CmdId := AId; Last := 'cmd'; end;
function TModalSpy.HotlistIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin Result := Hotlist; if Result then Last := 'hotlist'; end;
function TModalSpy.ColorIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin Result := ColorList; if Result then Last := 'color'; end;
function TModalSpy.EditIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin Result := ColorEdit; if Result then Last := 'edit'; end;
function TModalSpy.FilterIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin Result := Filter; if Result then Last := 'filter'; end;
function TModalSpy.WidgetIn(var AKey: Word; AShift: TShiftState; var AKeyChar: Char): Boolean;
begin Result := Widget; Last := 'widget'; end;
procedure TModalSpy.SyncHex; begin Synced := True; end;

procedure TestModalDialogInput;
var
  Spy: TModalSpy;
  Host: TDualPanelModalInputHost;
  Key: Word;
  Ch: Char;
begin
  Spy := TModalSpy.Create;
  try
    Host := Default(TDualPanelModalInputHost);
    Host.FocusedOrDefaultButtonId := Spy.FocusedId;
    Host.DialogCommand := Spy.Command;
    Host.HandleHotlistList := Spy.HotlistIn;
    Host.HandleColorList := Spy.ColorIn;
    Host.HandleColorEdit := Spy.EditIn;
    Host.HandleCmdHistoryFilter := Spy.FilterIn;
    Host.HandleDialogWidget := Spy.WidgetIn;
    Host.SyncColorPickerHex := Spy.SyncHex;
    Host.DialogDropDownOpen := Spy.DropIsOpen;
    Host.RecordDialogHistory := Spy.RecordHistory;

    Spy.Last := '';
    Key := vkReturn;
    Ch := 'x';
    Assert(DispatchModalDialogInput(Host, hdkMkDir, Key, [], Ch), 'Enter handled');
    Assert(Spy.CmdId = 'ok', 'empty focused id falls back to ok');
    Assert(Ch = #0, 'Enter consumes AKeyChar');
    Assert(Spy.HistoryFor = 'ok', 'Enter shortcut records the input history');

    // An open DropDown / history list owns Enter (picks the entry).
    Spy.DropOpen := True;
    Spy.CmdId := '';
    Spy.Widget := True;
    Key := vkReturn;
    Assert(DispatchModalDialogInput(Host, hdkSelectMask, Key, [], Ch), 'Enter with open list');
    Assert((Spy.CmdId = '') and (Spy.Last = 'widget'), 'open list: Enter goes to the dialog, not OK');
    Spy.DropOpen := False;
    Spy.Widget := False;

    Spy.Last := 'delete';
    Key := vkReturn;
    Assert(DispatchModalDialogInput(Host, hdkOverwriteAsk, Key, [], Ch), 'Enter overwrite');
    Assert(Spy.CmdId = 'delete', 'Enter uses focused button id');

    Spy.Hotlist := True;
    Key := vkDelete;
    Assert(DispatchModalDialogInput(Host, hdkFolderHotlist, Key, [], Ch), 'hotlist Del');
    Assert(Spy.Last = 'hotlist', 'hotlist list input wins');

    Spy.Widget := True;
    Key := vkDown;
    Assert(DispatchModalDialogInput(Host, hdkColorPicker, Key, [], Ch), 'picker widget');
    Assert(Spy.Synced, 'picker syncs hex after widget');

    Writeln('OK: TestModalDialogInput passed');
  finally
    Spy.Free;
  end;
end;

procedure TestQuickSearchMatch;
var
  Rows: TPanelRows;
begin
  SetLength(Rows, 3);
  Rows[0].IsParent := True;
  Rows[0].Text := '..';
  Rows[1].Text := 'src/';
  Rows[2].Text := 'readme.md';
  Assert(QuickSearchMatchIndex(Rows, 're') = 2, 'prefix match skips parent and dir slash');
  Assert(QuickSearchMatchIndex(Rows, 'SRC') = 1, 'dir match is case-insensitive');
  Assert(QuickSearchMatchIndex(Rows, 'z') = -1, 'no match');
  Assert(QuickSearchMatchIndex(Rows, '') = -1, 'empty needle');
  Writeln('OK: TestQuickSearchMatch passed');
end;

procedure TestApplyQuickSearchMatch;
var
  Rows: TPanelRows;
  Tab: TTab;
begin
  SetLength(Rows, 3);
  Rows[0].IsParent := True;
  Rows[0].Text := '..';
  Rows[1].Text := 'src/';
  Rows[2].Text := 'readme.md';
  Tab := Default(TTab);
  Tab.CursorIndex := 0;
  Assert(ApplyQuickSearchMatch(Tab, Rows, 're', 5, 1), 'match jumps');
  Assert(Tab.CursorIndex = 2, 'cursor on match');
  Assert(not ApplyQuickSearchMatch(Tab, Rows, 'z', 5, 1), 'miss leaves cursor');
  Assert(Tab.CursorIndex = 2, 'cursor unchanged on miss');
  Assert(not ApplyQuickSearchMatch(Tab, Rows, '', 5, 1), 'empty needle is miss');
  Writeln('OK: TestApplyQuickSearchMatch passed');
end;

procedure TestNeedleBox;
var
  Ch: Char;
  S: string;
begin
  Assert(RecoverPrintableKeyChar(Ord('A'), #0) = 'A', 'Alt letter recovers Key');
  Assert(RecoverPrintableKeyChar(Ord('7'), #0) = '7', 'digit Key recovers');
  Assert(RecoverPrintableKeyChar(vkDown, #0) = #0, 'non-printable stays empty');
  Assert(RecoverPrintableKeyChar(Ord('A'), 'b') = 'b', 'KeyChar wins when printable');

  Assert(ClassifyNeedleBoxKey(vkEscape, 'x', True, Ch) = nbaClear, 'Esc clears search');
  Assert(ClassifyNeedleBoxKey(vkReturn, 'x', True, Ch) = nbaClear, 'Enter clears search');
  Assert(ClassifyNeedleBoxKey(vkReturn, 'x', False, Ch) = nbaConfirm, 'Enter confirms filter');
  Assert(ClassifyNeedleBoxKey(vkEscape, 'x', False, Ch) = nbaClear, 'Esc still clears filter');
  Assert(ClassifyNeedleBoxKey(vkBack, #0, False, Ch) = nbaBackspace, 'Backspace');
  Assert(ClassifyNeedleBoxKey(0, 'a', True, Ch) = nbaAppend, 'printable appends');
  Assert(Ch = 'a', 'append char is recovered');
  Assert(ClassifyNeedleBoxKey(Ord('Z'), #0, True, Ch) = nbaAppend, 'Alt letter appends');
  Assert(Ch = 'Z', 'Alt letter char');
  Assert(ClassifyNeedleBoxKey(vkDown, #0, True, Ch) = nbaUnhandled, 'arrows unhandled');

  S := 'ab';
  Assert(NeedleBackspace(S) and (S = 'a'), 'backspace shortens');
  Assert(NeedleBackspace(S) and (S = ''), 'backspace last char');
  Assert(not NeedleBackspace(S) and (S = ''), 'empty backspace is no-op');
  Writeln('OK: TestNeedleBox passed');
end;

procedure TestPendingSelectMatch;
var
  Rows: TPanelRows;
begin
  SetLength(Rows, 3);
  Rows[0].IsParent := True;
  Rows[0].Text := '..';
  Rows[1].Text := 'src/';
  Rows[2].Text := 'readme.md';
  Assert(PendingSelectMatchIndex(Rows, 'src') = 1, 'strip trailing slash on row');
  Assert(PendingSelectMatchIndex(Rows, 'src/') = 1, 'strip trailing slash on want');
  Assert(PendingSelectMatchIndex(Rows, 'README.md') = 2, 'case-insensitive');
  Assert(PendingSelectMatchIndex(Rows, '..') = -1, 'parent is skipped');
  Assert(PendingSelectMatchIndex(Rows, '') = -1, 'empty want');
  Assert(PendingSelectMatchIndex(Rows, 'missing') = -1, 'no match');
  Writeln('OK: TestPendingSelectMatch passed');
end;

procedure TestRowNameHelpers;
var
  Rows: TPanelRows;
  Names: TArray<string>;
begin
  SetLength(Rows, 3);
  Rows[0].IsParent := True;
  Rows[0].Text := '..';
  Rows[1].Text := 'src/';
  Rows[2].Text := 'readme.md';
  Assert(PendingSelectNameAtCursor(Rows, 1) = 'src', 'cursor name strips slash');
  Assert(PendingSelectNameAtCursor(Rows, 0) = '', 'parent cursor is empty');
  Assert(PendingSelectNameAtCursor(Rows, 9) = '', 'oob cursor is empty');
  Names := CollectVisibleRowNames(Rows);
  Assert(Length(Names) = 2, 'parent skipped');
  Assert(Names[0] = 'src', 'visible dir name');
  Assert(Names[1] = 'readme.md', 'visible file name');
  Writeln('OK: TestRowNameHelpers passed');
end;

begin
  try
    TestInputTranslation;
    TestKeymapDispatchConsume;
    TestNavDispatch;
    TestClassifyAndFreeInput;
    TestModalDialogInput;
    TestQuickSearchMatch;
    TestApplyQuickSearchMatch;
    TestNeedleBox;
    TestPendingSelectMatch;
    TestRowNameHelpers;
    Writeln('All DualPanelInput tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
