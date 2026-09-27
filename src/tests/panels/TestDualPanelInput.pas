unit TestDualPanelInput;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelInput = class
  public
    [Test] procedure TestInputTranslation;
    [Test] procedure TestKeymapDispatchConsume;
    [Test] procedure TestNavDispatch;
    [Test] procedure TestClassifyAndFreeInput;
    [Test] procedure TestModalDialogInput;
    [Test] procedure TestQuickSearchMatch;
    [Test] procedure TestApplyQuickSearchMatch;
    [Test] procedure TestNeedleBox;
    [Test] procedure TestPendingSelectMatch;
    [Test] procedure TestRowNameHelpers;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uKeymap,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelInput,
  uDualPanelSelection,
  uColorCodingEditHelpers;

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
    procedure CopyItemName;
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

procedure TKeymapSpy.CopyItemName;
begin
  Last := 'copyname';
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
  AHost.CopyItemNameToClipboard := ASpy.CopyItemName;
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
  Assert.IsTrue(LAction = iaCopy, 'F5 should translate to iaCopy');

  LAction := TDualPanelInputHandler.TranslateShortcut(vkF8, [], #0);
  Assert.IsTrue(LAction = iaDelete, 'F8 should translate to iaDelete');

  LAction := TDualPanelInputHandler.TranslateShortcut(vkO, [ssCtrl], #0);
  Assert.IsTrue(LAction = iaToggleConsole, 'Ctrl+O should translate to iaToggleConsole');

  Assert.IsTrue(TDualPanelInputHandler.IsNavigationKey(vkUp), 'vkUp should be navigation key');
  Assert.IsTrue(not TDualPanelInputHandler.IsNavigationKey(vkF1), 'vkF1 should not be navigation key');

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
    Assert.IsTrue(not DispatchKeymapActionPrimary(Host, kaNone, Key, KeyChar),
      'kaNone is not a primary action');
    Assert.IsTrue(Key = vkF5, 'unhandled action must leave AKey');
    Assert.IsTrue(KeyChar = 'x', 'unhandled action must leave AKeyChar');

    Key := vkC;
    KeyChar := 'c';
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaCopyFullPath, Key, KeyChar),
      'kaCopyFullPath is primary');
    Assert.IsTrue(Spy.Last = 'copyfull', 'copy-full-path host called');
    Assert.IsTrue(Key = 0, 'copy-full-path consumes AKey');
    Assert.IsTrue(KeyChar = #0, 'copy-full-path consumes AKeyChar');

    Key := vkInsert;
    KeyChar := 'x';
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaCopyItemName, Key, KeyChar),
      'kaCopyItemName is primary');
    Assert.IsTrue(Spy.Last = 'copyname', 'copy-name host called');
    Assert.IsTrue(Key = 0, 'copy-name consumes AKey');
    Assert.IsTrue(KeyChar = #0, 'copy-name consumes AKeyChar');

    // Alt+Enter: Alt quick search (after the primary dispatch) would take
    // it as a search key, so Properties must be primary.
    Spy.Last := '';
    Key := vkReturn;
    KeyChar := #13;
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaProperties, Key, KeyChar),
      'kaProperties is primary');
    Assert.IsTrue(Spy.Last = 'properties', 'Properties host called');
    Assert.IsTrue((Key = 0) and (KeyChar = #0), 'Properties consumes the key');
    Assert.IsTrue(IsAltQuickSearchChord(vkReturn, [ssAlt]),
      'Alt+Enter would be quick search if it got that far');

    // Alt+F3 / Alt+F4: the same trap as Alt+Enter.
    Key := vkF3;
    KeyChar := #0;
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaExternalView, Key, KeyChar),
      'kaExternalView is primary');
    Assert.IsTrue((Spy.Last = 'extview') and (Key = 0), 'external viewer host called');
    Key := vkF4;
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaExternalEdit, Key, KeyChar),
      'kaExternalEdit is primary');
    Assert.IsTrue((Spy.Last = 'extedit') and (Key = 0), 'external editor host called');
    Assert.IsTrue(IsAltQuickSearchChord(vkF4, [ssAlt]),
      'Alt+F4 would be quick search if it got that far');

    Key := vkF10;
    KeyChar := 'X';
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaQuit, Key, KeyChar), 'kaQuit is primary');
    Assert.IsTrue(Spy.Last = 'quit', 'quit host called');
    Assert.IsTrue(Key = 0, 'kaQuit consumes AKey');
    Assert.IsTrue(KeyChar = 'X', 'kaQuit must not clear AKeyChar');

    Key := vkF1;
    KeyChar := 'L';
    Assert.IsTrue(DispatchKeymapActionPrimary(Host, kaTogglePanelLeft, Key, KeyChar),
      'kaTogglePanelLeft is primary');
    Assert.IsTrue((Spy.Last = 'toggle') and (Spy.Side = psLeft), 'toggle left host called');
    Assert.IsTrue(Key = 0, 'toggle-panel consumes AKey');
    Assert.IsTrue(KeyChar = 'L', 'toggle-panel must not clear AKeyChar');

    Key := vkF5;
    KeyChar := 'c';
    Assert.IsTrue(DispatchKeymapActionFunctionKeys(Host, kaCopy, Key, KeyChar),
      'kaCopy is a function-key action');
    Assert.IsTrue((Spy.Last = 'job') and (Spy.Job = pjkCopy) and Spy.Recycle,
      'kaCopy begins copy with recycle default');
    Assert.IsTrue(Key = 0, 'kaCopy consumes AKey');
    Assert.IsTrue(KeyChar = 'c', 'kaCopy must not clear AKeyChar');

    Key := vkF8;
    KeyChar := 'w';
    Assert.IsTrue(DispatchKeymapActionFunctionKeys(Host, kaWipe, Key, KeyChar),
      'kaWipe is a function-key action');
    Assert.IsTrue((Spy.Job = pjkDelete) and (not Spy.Recycle), 'kaWipe deletes without recycle');
    Assert.IsTrue(KeyChar = #0, 'kaWipe consumes AKeyChar');

    Key := vkF3;
    KeyChar := 'v';
    Assert.IsTrue(DispatchKeymapActionFunctionKeys(Host, kaView, Key, KeyChar),
      'kaView is a function-key action');
    Assert.IsTrue((Spy.Last = 'viewedit') and (not Spy.Edit), 'kaView opens viewer');
    Assert.IsTrue(KeyChar = #0, 'kaView consumes AKeyChar');

    Key := vkF4;
    KeyChar := 'e';
    Assert.IsTrue(DispatchKeymapActionFunctionKeys(Host, kaEdit, Key, KeyChar),
      'kaEdit is a function-key action');
    Assert.IsTrue(Spy.Edit, 'kaEdit opens editor');
    Assert.IsTrue(KeyChar = 'e', 'kaEdit must not clear AKeyChar');

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
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 2, 20), 'Up handled');
    Assert.IsTrue((Spy.Last = 'move') and (Spy.Delta = -1), 'Up moves -1');
    Assert.IsTrue(Key = 0, 'Up consumes AKey');

    Key := vkUp;
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [ssShift], KeyChar, 10, 2, 20),
      'Shift+Up handled');
    Assert.IsTrue((Spy.Last = 'select') and (Spy.SelectDelta = -1) and
      (not Spy.ExcludeLanding), 'Shift+Up selects leaving row');
    Assert.IsTrue(Key = 0, 'Shift+Up consumes AKey');

    Key := vkLeft;
    Assert.IsTrue(not DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20),
      'Left with 1 col is unhandled');
    Assert.IsTrue(Key = vkLeft, 'unhandled Left leaves AKey');

    Key := vkLeft;
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [ssShift], KeyChar, 10, 2, 20),
      'Shift+Left in brief handled');
    Assert.IsTrue((Spy.Last = 'select') and (Spy.SelectDelta = -10) and
      Spy.ExcludeLanding, 'Shift+Left excludes landing');

    Key := vkInsert;
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20), 'Insert handled');
    Assert.IsTrue(Spy.Last = 'insert', 'Insert toggles select');
    Assert.IsTrue(Key = 0, 'Insert consumes AKey');

    Key := vkInsert;
    Assert.IsTrue(not DispatchPanelNavKeys(Host, Key, [ssCtrl], KeyChar, 10, 1, 20),
      'Ctrl+Insert is unhandled');
    Assert.IsTrue(Key = vkInsert, 'Ctrl+Insert leaves AKey');

    Key := vkReturn;
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20), 'Return handled');
    Assert.IsTrue(Spy.Last = 'submit', 'Return submits cmdline');
    Assert.IsTrue(Key = 0, 'Return consumes AKey');

    Spy.Last := '';
    Key := vkReturn;
    Assert.IsTrue(not DispatchPanelNavKeys(Host, Key, [ssCtrl, ssAlt], KeyChar, 10, 1, 20),
      'Ctrl+Alt+Enter is not Activate/submit');
    Assert.IsTrue(Spy.Last = '', 'Ctrl+Alt+Enter does not submit cmdline');
    Assert.IsTrue(Key = vkReturn, 'Ctrl+Alt+Enter leaves AKey for panel handler');

    Key := Ord('A');
    KeyChar := 'a';
    Assert.IsTrue(DispatchPanelNavKeys(Host, Key, [], KeyChar, 10, 1, 20),
      'printable goes to cmdline');
    Assert.IsTrue(Spy.Last = 'focus+cmd', 'printable focuses then feeds cmdline');

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
  Assert.IsTrue(Key = vkTab, 'Tab stays Tab despite CR KeyChar');
  Key := 0;
  Ch := #13;
  NormalizePanelInputKey(Key, Ch);
  Assert.IsTrue(Key = vkReturn, 'CR becomes vkReturn');
  Key := 10;
  Ch := #0;
  NormalizePanelInputKey(Key, Ch);
  Assert.IsTrue(Key = vkReturn, 'LF key becomes vkReturn');

  Assert.IsTrue(ShouldOfferTopMenu(wkPanels, False), 'panels offer top menu');
  Assert.IsTrue(ShouldOfferTopMenu(wkDocument, False), 'document offers top menu');
  Assert.IsTrue(ShouldOfferTopMenu(wkTerminal, False), 'terminal offers top menu');
  Assert.IsTrue(not ShouldOfferTopMenu(wkPanels, True), 'dialog hides top menu');
  Assert.IsTrue(not ShouldOfferTopMenu(wkDocument, True), 'dialog hides menu on document');
  Assert.IsTrue(IsWorkspaceCycleChord(vkTab, [ssCtrl], False), 'Ctrl+Tab cycles');
  Assert.IsTrue(IsWorkspaceCycleChord(vkTab, [ssCtrl, ssAlt], False),
    'Ctrl+Tab cycles with leftover Alt');
  Assert.IsTrue(IsWorkspaceCycleChord(vkTab, [ssCtrl, ssShift], False),
    'Ctrl+Shift+Tab cycles');
  Assert.IsTrue(not IsWorkspaceCycleChord(vkTab, [ssCtrl], True), 'dialog blocks cycle');
  Assert.IsTrue(IsConsoleToggleChord(Ord('O'), [ssCtrl], False), 'Ctrl+O console');
  // Ord('o') is vkDivide: Ctrl+Num/ is not Ctrl+O.
  Assert.IsTrue(not IsConsoleToggleChord(Ord('o'), [ssCtrl], False), 'Ctrl+Num/ is not Ctrl+O');
  Assert.IsTrue(not IsConsoleToggleChord(vkEscape, [], False), 'Esc is not host Ctrl+O');
  Assert.IsTrue(not IsConsoleToggleChord(Ord('O'), [ssCtrl], True), 'dialog blocks Ctrl+O');
  Assert.IsTrue(not IsConsoleToggleChord(Ord('O'), [ssCtrl, ssShift], False),
    'Ctrl+Shift+O is not console toggle');
  Assert.IsTrue(IsHelpChord(vkF1, [], False), 'F1 help');
  Assert.IsTrue(not IsHelpChord(vkF1, [ssShift], False), 'Shift+F1 is not help');
  Assert.IsTrue(not IsHelpChord(vkF1, [], True), 'dialog blocks F1');
  Assert.IsTrue(IsContextHelpChord(vkF1, [], True, False), 'F1 over the open top menu');
  Assert.IsTrue(IsContextHelpChord(vkF1, [], False, True), 'F1 over a dialog without its own F1');
  Assert.IsTrue(not IsContextHelpChord(vkF1, [], False, False), 'nothing to be context for');
  Assert.IsTrue(not IsContextHelpChord(vkF1, [ssShift], True, True), 'Shift+F1 is not help');
  Assert.IsTrue(not IsContextHelpChord(vkF2, [], True, True), 'only F1');
  Assert.IsTrue(IsNewTerminalChord(Ord('N'), [ssCtrl, ssShift], False), 'Ctrl+Shift+N');
  Assert.IsTrue(not IsNewTerminalChord(Ord('N'), [ssCtrl], False), 'Ctrl+N is not new terminal');
  Assert.IsTrue(not IsNewTerminalChord(Ord('N'), [ssCtrl, ssShift], True),
    'dialog blocks new terminal');
  Assert.IsTrue(IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssAlt], False),
    'Ctrl+Alt+O console profile');
  Assert.IsTrue(not IsSelectConsoleProfileChord(Ord('o'), [ssCtrl, ssAlt], False),
    'Ctrl+Alt+Num/ is not Ctrl+Alt+O');
  Assert.IsTrue(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl], False),
    'Ctrl+O is not console profile');
  Assert.IsTrue(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssShift], False),
    'Ctrl+Shift+O is not console profile');
  Assert.IsTrue(not IsSelectConsoleProfileChord(Ord('O'), [ssCtrl, ssAlt], True),
    'dialog blocks console profile');
  Assert.IsTrue(IsAppQuitChord(Ord('X'), [ssAlt], False), 'Alt+X quit');
  Assert.IsTrue(not IsAppQuitChord(vkF10, [], False), 'F10 is not app quit on embed');
  Assert.IsTrue(not IsAppQuitChord(Ord('X'), [ssAlt], True), 'dialog blocks Alt+X');
  Assert.IsTrue(ClassifyEmbeddedInputOwner(wkDocument, False, False) = eioDocument, 'doc owner');
  Assert.IsTrue(ClassifyEmbeddedInputOwner(wkTerminal, False, False) = eioTerminal, 'term owner');
  Assert.IsTrue(ClassifyEmbeddedInputOwner(wkPanels, False, True) = eioConsoleYield, 'console yield');
  Assert.IsTrue(ClassifyEmbeddedInputOwner(wkDocument, True, True) = eioNone, 'dialog wins over embed');
  Assert.IsTrue(IsPasteChord(vkInsert, [ssShift], #0), 'Shift+Ins paste');
  Assert.IsTrue(IsPasteChord(Ord('V'), [ssCtrl], 'v'), 'Ctrl+V paste');
  Assert.IsTrue(not IsPasteChord(Ord('V'), [ssCtrl, ssAlt], 'v'), 'Ctrl+Alt+V is not paste');
  Assert.IsTrue(IsAltQuickSearchChord(Ord('A'), [ssAlt]), 'Alt+A quick search');
  Assert.IsTrue(not IsAltQuickSearchChord(vkF7, [ssAlt]), 'Alt+F7 is not quick search');
  Assert.IsTrue(not IsAltQuickSearchChord(vkAdd, [ssAlt]), 'Alt+Gray+ is not quick search');
  Assert.IsTrue(not IsAltQuickSearchChord(vkSubtract, [ssAlt]), 'Alt+Gray- is not quick search');
  Assert.IsTrue(not IsAltQuickSearchChord(Ord('+'), [ssAlt]), 'Alt+Ord(+) is not quick search');
  Assert.IsTrue(not IsAltQuickSearchChord(Ord('-'), [ssAlt]), 'Alt+Ord(-) is not quick search');

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
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'preview Esc handled');
    Assert.IsTrue(Spy.Last = 'canceldrive', 'preview Esc cancels');
    Assert.IsTrue(Key = 0, 'preview Esc consumes AKey');
    Assert.IsTrue(Ch = 'x', 'preview Esc leaves AKeyChar');

    Snap.DrivePreviewActive := False;
    Snap.QuickViewVisible := True;
    Key := vkEscape;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'QV Esc handled');
    Assert.IsTrue(Spy.Last = 'closeqv', 'QV Esc closes');

    Snap.QuickViewVisible := False;
    Snap.CmdLineHasText := True;
    Key := vkEscape;
    Ch := 'x';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'cmdline Esc handled');
    Assert.IsTrue(Spy.Last = 'clearcmd', 'cmdline Esc clears');
    Assert.IsTrue(Ch = #0, 'cmdline Esc consumes AKeyChar');

    Snap.CmdLineHasText := False;
    Snap.FilterBoxActive := True;
    Spy.FilterHandled := True;
    Key := vkEscape;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'filter handled');
    Assert.IsTrue(Spy.Last = 'filter', 'filter box gets Esc');

    Snap.FilterBoxActive := False;
    Spy.PrimaryHandled := True;
    Key := vkF10;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'primary handled');
    Assert.IsTrue(Spy.Last = 'primary', 'keymap primary wins');

    Spy.PrimaryHandled := False;
    Key := vkLeft;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'Ctrl+Left handled');
    Assert.IsTrue((Spy.Last = 'preview') and (Spy.Delta = -1), 'Ctrl+Left previews prev drive');
    Assert.IsTrue(Key = 0, 'Ctrl+Left consumes AKey');

    Key := vkBackslash;
    Ch := '\';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'Ctrl+\\ handled');
    Assert.IsTrue(Spy.Last = 'navroot', 'Ctrl+\\ goes to drive root');
    Assert.IsTrue(Ch = #0, 'Ctrl+\\ consumes AKeyChar');

    Spy.PasteOk := True;
    Key := Ord('V');
    Ch := 'v';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch), 'paste handled');
    Assert.IsTrue(Spy.Last = 'paste', 'Ctrl+V pastes');

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
      Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
        'focused cmdline: char handled');
      Assert.IsTrue(Spy.Last = 'cmdline', 'focused cmdline gets ' + Ch + ' (not the panel binding)');
    end;
    // Not only text: every key, panel bindings and F-keys included.
    Spy.Last := '';
    Key := vkSubtract;
    Ch := '-';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'focused cmdline: Ctrl+- handled');
    Assert.IsTrue(Spy.Last = 'cmdline', 'focused cmdline gets Ctrl+-');
    Spy.Last := '';
    Key := vkF5;
    Ch := #0;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
      'focused cmdline: F5 handled');
    Assert.IsTrue(Spy.Last = 'cmdline', 'focused cmdline gets F5 (no copy)');
    Spy.Last := '';
    Snap.QuickViewVisible := True;
    Key := vkEscape;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch),
      'focused cmdline: Esc handled');
    Assert.IsTrue(Spy.Last = 'cmdline', 'focused cmdline gets Esc before Quick View');
    Snap.QuickViewVisible := False;
    Spy.PrimaryHandled := False;
    Spy.CmdHandled := False;
    Snap.CmdFocused := False;

    // Panel active (even with text in the command line): '-' deselects.
    Snap.CmdLineHasText := True;
    Spy.Last := '';
    Key := 0;
    Ch := '-';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'panel -: handled');
    Assert.IsTrue((Spy.Last = 'mask') and Spy.MaskUnselect, 'panel -: deselect by mask');
    Snap.CmdLineHasText := False;

    Key := vkAdd;
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Gray+ handled');
    Assert.IsTrue((Spy.Last = 'mask') and (not Spy.MaskUnselect) and (Spy.GrayCalls > 0),
      'Gray+ select mask after restore');
    Assert.IsTrue(Ch = #0, 'Gray+ consumes AKeyChar');

    Key := vkAdd;
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch), 'Alt+Gray+ handled');
    Assert.IsTrue((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Gray+ selects by name stem');
    Assert.IsTrue(Ch = #0, 'Alt+Gray+ consumes AKeyChar');

    Spy.Last := '';
    Key := 0;
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Gray+ as AKey=0 handled');
    Assert.IsTrue((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Gray+ FMX extract selects by name stem');
    Assert.IsTrue(Ch = #0, 'Alt+Gray+ FMX extract consumes AKeyChar');

    Spy.Last := '';
    Key := Ord('+');
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Ord(+) handled');
    Assert.IsTrue((Spy.Last = 'byname') and (not Spy.MaskUnselect),
      'Alt+Ord(+) selects by name stem');

    Spy.Last := '';
    Key := 0;
    Ch := '-';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssAlt], Ch),
      'Alt+Gray- as AKey=0 handled');
    Assert.IsTrue((Spy.Last = 'byname') and Spy.MaskUnselect,
      'Alt+Gray- FMX extract unselects by name stem');

    Spy.Last := '';
    Key := vkAdd;
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Gray+ handled');
    Assert.IsTrue((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'Ctrl++ selects by extension');

    Spy.Last := '';
    Key := vkEqual;
    Ch := '=';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+= handled');
    Assert.IsTrue((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'Ctrl+= selects by extension');

    Spy.Last := '';
    Key := vkEqual;
    Ch := '+';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl, ssShift], Ch),
      'Ctrl+Shift+= handled');
    Assert.IsTrue((Spy.Last = 'ext') and (not Spy.MaskUnselect),
      'main-keyboard Ctrl++ selects by extension');

    Spy.Last := '';
    Key := vkSubtract;
    Ch := #0;
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Gray- handled');
    Assert.IsTrue((Spy.Last = 'ext') and Spy.MaskUnselect,
      'Ctrl+- unselects by extension');

    Spy.Last := '';
    Key := vkMinus;
    Ch := '-';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Minus handled');
    Assert.IsTrue((Spy.Last = 'ext') and Spy.MaskUnselect,
      'main-keyboard Ctrl+- unselects by extension');

    Spy.Last := '';
    Key := Ord('M');
    Ch := 'm';
    DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch);
    Assert.IsTrue(Spy.Last <> 'ext', 'Ctrl+M is not unselect-by-extension');

    Key := vkInsert;
    Ch := #0;
    RestoreGrayOpKey(Key, Ch);
    Assert.IsTrue(Key = vkInsert, 'RestoreGray leaves Ins (Ord(-) is vkInsert)');
    Key := vkInsert;
    Ch := #0;
    Spy.Last := '';
    NavSpy.Last := '';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Ins handled');
    Assert.IsTrue(NavSpy.Last = 'insert', 'Ins toggles file/dir selection');
    Assert.IsTrue(Spy.Last <> 'mask', 'Ins does not open deselect dialog');
    Assert.IsTrue(Key = 0, 'Ins consumes AKey');

    Key := vkTab;
    Ch := 'x';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Tab handled');
    Assert.IsTrue(Spy.Last = 'switch', 'Tab switches side');
    Assert.IsTrue(Ch = 'x', 'Tab leaves AKeyChar');

    Spy.Last := '';
    Key := vkTab;
    Ch := 'x';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl], Ch),
      'Ctrl+Tab handled');
    Assert.IsTrue(Spy.Last <> 'switch', 'Ctrl+Tab does not switch panel side');
    Assert.IsTrue(Key = 0, 'Ctrl+Tab consumes AKey');

    Key := Ord('T');
    Ch := 't';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [ssCtrl, ssShift], Ch),
      'Ctrl+Shift+T handled');
    Assert.IsTrue(Spy.Last = 'newtab', 'Ctrl+Shift+T new panel tab');

    Key := vkNumpad5;
    Ch := 'x';
    Assert.IsTrue(DispatchPanelFreeInput(Host, Keymap, Snap, Key, [], Ch), 'Numpad5 handled');
    Assert.IsTrue(Spy.Last = 'view', 'Numpad5 opens viewer');
    Assert.IsTrue(Ch = #0, 'Numpad5 consumes AKeyChar');

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
    Assert.IsTrue(DispatchModalDialogInput(Host, hdkMkDir, Key, [], Ch), 'Enter handled');
    Assert.IsTrue(Spy.CmdId = 'ok', 'empty focused id falls back to ok');
    Assert.IsTrue(Ch = #0, 'Enter consumes AKeyChar');
    Assert.IsTrue(Spy.HistoryFor = 'ok', 'Enter shortcut records the input history');

    // An open DropDown / history list owns Enter (picks the entry).
    Spy.DropOpen := True;
    Spy.CmdId := '';
    Spy.Widget := True;
    Key := vkReturn;
    Assert.IsTrue(DispatchModalDialogInput(Host, hdkSelectMask, Key, [], Ch), 'Enter with open list');
    Assert.IsTrue((Spy.CmdId = '') and (Spy.Last = 'widget'), 'open list: Enter goes to the dialog, not OK');
    Spy.DropOpen := False;
    Spy.Widget := False;

    Spy.Last := 'delete';
    Key := vkReturn;
    Assert.IsTrue(DispatchModalDialogInput(Host, hdkOverwriteAsk, Key, [], Ch), 'Enter overwrite');
    Assert.IsTrue(Spy.CmdId = 'delete', 'Enter uses focused button id');

    Spy.Hotlist := True;
    Key := vkDelete;
    Assert.IsTrue(DispatchModalDialogInput(Host, hdkFolderHotlist, Key, [], Ch), 'hotlist Del');
    Assert.IsTrue(Spy.Last = 'hotlist', 'hotlist list input wins');

    Spy.Widget := True;
    Key := vkDown;
    Assert.IsTrue(DispatchModalDialogInput(Host, hdkColorPicker, Key, [], Ch), 'picker widget');
    Assert.IsTrue(Spy.Synced, 'picker syncs hex after widget');

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
  Assert.IsTrue(QuickSearchMatchIndex(Rows, 're') = 2, 'prefix match skips parent and dir slash');
  Assert.IsTrue(QuickSearchMatchIndex(Rows, 'SRC') = 1, 'dir match is case-insensitive');
  Assert.IsTrue(QuickSearchMatchIndex(Rows, 'z') = -1, 'no match');
  Assert.IsTrue(QuickSearchMatchIndex(Rows, '') = -1, 'empty needle');
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
  Assert.IsTrue(ApplyQuickSearchMatch(Tab, Rows, 're', 5, 1), 'match jumps');
  Assert.IsTrue(Tab.CursorIndex = 2, 'cursor on match');
  Assert.IsTrue(not ApplyQuickSearchMatch(Tab, Rows, 'z', 5, 1), 'miss leaves cursor');
  Assert.IsTrue(Tab.CursorIndex = 2, 'cursor unchanged on miss');
  Assert.IsTrue(not ApplyQuickSearchMatch(Tab, Rows, '', 5, 1), 'empty needle is miss');
  Writeln('OK: TestApplyQuickSearchMatch passed');
end;

procedure TestNeedleBox;
var
  Ch: Char;
  S: string;
begin
  Assert.IsTrue(RecoverPrintableKeyChar(Ord('A'), #0) = 'A', 'Alt letter recovers Key');
  Assert.IsTrue(RecoverPrintableKeyChar(Ord('7'), #0) = '7', 'digit Key recovers');
  Assert.IsTrue(RecoverPrintableKeyChar(vkDown, #0) = #0, 'non-printable stays empty');
  Assert.IsTrue(RecoverPrintableKeyChar(vkF1, #0) = #0, 'F1 (= Ord(''p'')) is not a letter');
  Assert.IsTrue(RecoverPrintableKeyChar(vkNumpad1, #0) = #0, 'Num1 (= Ord(''a'')) is not a letter');
  Assert.IsTrue(RecoverPrintableKeyChar(Ord('A'), 'b') = 'b', 'KeyChar wins when printable');

  Assert.IsTrue(ClassifyNeedleBoxKey(vkEscape, 'x', True, Ch) = nbaClear, 'Esc clears search');
  Assert.IsTrue(ClassifyNeedleBoxKey(vkReturn, 'x', True, Ch) = nbaClear, 'Enter clears search');
  Assert.IsTrue(ClassifyNeedleBoxKey(vkReturn, 'x', False, Ch) = nbaConfirm, 'Enter confirms filter');
  Assert.IsTrue(ClassifyNeedleBoxKey(vkEscape, 'x', False, Ch) = nbaClear, 'Esc still clears filter');
  Assert.IsTrue(ClassifyNeedleBoxKey(vkBack, #0, False, Ch) = nbaBackspace, 'Backspace');
  Assert.IsTrue(ClassifyNeedleBoxKey(0, 'a', True, Ch) = nbaAppend, 'printable appends');
  Assert.IsTrue(Ch = 'a', 'append char is recovered');
  Assert.IsTrue(ClassifyNeedleBoxKey(Ord('Z'), #0, True, Ch) = nbaAppend, 'Alt letter appends');
  Assert.IsTrue(Ch = 'Z', 'Alt letter char');
  Assert.IsTrue(ClassifyNeedleBoxKey(vkDown, #0, True, Ch) = nbaUnhandled, 'arrows unhandled');

  S := 'ab';
  Assert.IsTrue(NeedleBackspace(S) and (S = 'a'), 'backspace shortens');
  Assert.IsTrue(NeedleBackspace(S) and (S = ''), 'backspace last char');
  Assert.IsTrue(not NeedleBackspace(S) and (S = ''), 'empty backspace is no-op');
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
  Assert.IsTrue(PendingSelectMatchIndex(Rows, 'src') = 1, 'strip trailing slash on row');
  Assert.IsTrue(PendingSelectMatchIndex(Rows, 'src/') = 1, 'strip trailing slash on want');
  Assert.IsTrue(PendingSelectMatchIndex(Rows, 'README.md') = 2, 'case-insensitive');
  Assert.IsTrue(PendingSelectMatchIndex(Rows, '..') = -1, 'parent is skipped');
  Assert.IsTrue(PendingSelectMatchIndex(Rows, '') = -1, 'empty want');
  Assert.IsTrue(PendingSelectMatchIndex(Rows, 'missing') = -1, 'no match');
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
  Assert.IsTrue(PendingSelectNameAtCursor(Rows, 1) = 'src', 'cursor name strips slash');
  Assert.IsTrue(PendingSelectNameAtCursor(Rows, 0) = '', 'parent cursor is empty');
  Assert.IsTrue(PendingSelectNameAtCursor(Rows, 9) = '', 'oob cursor is empty');
  Names := CollectVisibleRowNames(Rows);
  Assert.IsTrue(Length(Names) = 2, 'parent skipped');
  Assert.IsTrue(Names[0] = 'src', 'visible dir name');
  Assert.IsTrue(Names[1] = 'readme.md', 'visible file name');
  Writeln('OK: TestRowNameHelpers passed');
end;

{ TTestDualPanelInput }

procedure TTestDualPanelInput.TestInputTranslation;
begin
  TestDualPanelInput.TestInputTranslation;
end;

procedure TTestDualPanelInput.TestKeymapDispatchConsume;
begin
  TestDualPanelInput.TestKeymapDispatchConsume;
end;

procedure TTestDualPanelInput.TestNavDispatch;
begin
  TestDualPanelInput.TestNavDispatch;
end;

procedure TTestDualPanelInput.TestClassifyAndFreeInput;
begin
  TestDualPanelInput.TestClassifyAndFreeInput;
end;

procedure TTestDualPanelInput.TestModalDialogInput;
begin
  TestDualPanelInput.TestModalDialogInput;
end;

procedure TTestDualPanelInput.TestQuickSearchMatch;
begin
  TestDualPanelInput.TestQuickSearchMatch;
end;

procedure TTestDualPanelInput.TestApplyQuickSearchMatch;
begin
  TestDualPanelInput.TestApplyQuickSearchMatch;
end;

procedure TTestDualPanelInput.TestNeedleBox;
begin
  TestDualPanelInput.TestNeedleBox;
end;

procedure TTestDualPanelInput.TestPendingSelectMatch;
begin
  TestDualPanelInput.TestPendingSelectMatch;
end;

procedure TTestDualPanelInput.TestRowNameHelpers;
begin
  TestDualPanelInput.TestRowNameHelpers;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelInput);

end.
