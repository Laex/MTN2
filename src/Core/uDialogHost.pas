unit uDialogHost;

{ Host-built declarative dialogs (DIALOG_PLUGIN). Draws via IThemeRenderer;
  inputs use TInputLine. In-process - cdecl export comes with DLL stage. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.StrUtils,
  System.Generics.Collections, uTerminalTypes, uThemeTypes, uThemeDrawing, uDialogTypes, uDialogJson, uDialogRenderer,
  uInputLine, uMaskGroups, uFunctionBar, uColorCoding, uDialogHistory, uColorPickerControl, uDatePickerControl,
  uDialogHostKeys, uDialogHostClicks, uDialogTabs;

type
  /// <summary>An open dialog set aside while another one is shown over it.</summary>
  TDialogSnapshot = record
    Decl: TDialogDeclaration;
    FocusIndex: Integer;
    OnCommand: TDialogCommandEvent;
    ListSeen: TArray<TPair<string, Integer>>;
    ListSelId: string;
    ListSelIndex: Integer;
    ListScrollTop: Integer;
    ScrollY: Integer;
    ScrollFollow: Integer;
    Tag: Integer;
  end;

  TDialogHost = class
  private
    /// <summary>Dialogs set aside by PushDialog, the newest last.</summary>
    FStash: TArray<TDialogSnapshot>;
    /// <summary>Set by the owner: true while the mask groups editor may be opened
    /// from a mask field (it is not offered inside the editor itself).</summary>
    FOnMaskGroupsAvailable: TFunc<Boolean>;
    FOnEditMaskGroups: TProc;
    /// <summary>Of the open history list: how many rows are history entries (the
    /// rest are mask groups and the editor row) and whether the last row opens
    /// the mask groups editor.</summary>
    FDropHistoryCount: Integer;
    FDropActionRow: Boolean;
    FTheme: IThemeRenderer;
    FVisible: Boolean;
    FDecl: TDialogDeclaration;
    FBounds: TRectI;
    FControlBounds: TArray<TRectI>;
    FAreaW: Integer;
    FAreaH: Integer;
    FFocusIndex: Integer;
    /// <summary>A dialog taller than the window scrolls: FScrollY is the first row of
    /// the content shown, FContentH the rows the controls need, FScrollFollow the
    /// focus the view last followed (so a wheel or a bar drag is not undone).</summary>
    FScrollY: Integer;
    FContentH: Integer;
    FScrollFollow: Integer;
    FClicks: TMouseClickCounter; // input fields: double = word, triple = all
    /// <summary>Host-side mirror of list selection (avoids dynarray-of-record writeback issues).</summary>
    FListSelId: string;
    FListSelIndex: Integer;
    /// <summary>First visible row for multi-line list (height &gt; 1).</summary>
    FListScrollTop: Integer;
    /// <summary>Open DropDown control index, or -1 when collapsed.</summary>
    FDropOpenIndex: Integer;
    /// <summary>Highlighted item while DropDown popup is open.</summary>
    FDropHover: Integer;
    /// <summary>First visible popup row when items do not fit in the dialog.</summary>
    FDropScrollTop: Integer;
    FOnCommand: TDialogCommandEvent;
    FOnChanged: TNotifyEvent;
    FOnValueChanged: TDialogValueChangedEvent;
    FOnListSelected: TDialogValueChangedEvent;
    // Selected item of each list as last reported to FOnListSelected.
    FListSeen: TArray<TPair<string, Integer>>;
    FCursorVisible: Boolean;
    FUpdateLock: Integer;
    FUpdateDirty: Boolean;
    /// <summary>Button drawn pressed (face one cell right, no shadow), else -1.</summary>
    FPressIndex: Integer;
    /// <summary>Button the left mouse button went down on, else -1. The
    /// command runs on release over the same button.</summary>
    FMouseIndex: Integer;
    /// <summary>Input the left mouse button went down on and is dragging a
    /// selection in, else -1.</summary>
    FDragInput: Integer;
    /// <summary>Keyboard press waiting for the release: runs when the press
    /// timer fires or the next input arrives (FlushDialogButtonPress).</summary>
    FPendingAction: TProc;
    FPendingGen: Cardinal;
    /// <summary>Bumped by Open and Close, so a press queued for one dialog
    /// never runs against the next.</summary>
    FOpenGen: Cardinal;
    FOnDeferredCommand: TNotifyEvent;
    procedure RefreshHistoryDropItems(AControlIndex: Integer);
    function FirstFocusable: Integer;
    /// <summary>Shows page ANew of the tab strip at AStrip. Focus moves to the
    /// strip when its control is on the page that goes away.</summary>
    procedure SelectTab(AStrip, ANew: Integer);
    procedure DrawVerticalTabStrip(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    procedure DrawTabStrip(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    function NextFocusable(AFrom: Integer; AForward: Boolean): Integer;
    /// <summary>Joins full-width separator rules to the dialog frame:
    /// ╟─╢ on a double frame, ├─┤ on a single one, +-+ on an ASCII one.</summary>
    procedure JoinSeparatorsToFrame(const AGrid: TTerminalGrid);
    /// <summary>Vertical rules (VRule labels) with tees into the frame and into the
    /// full-width rule under them.</summary>
    procedure DrawVerticalRules(const AGrid: TTerminalGrid);
    procedure OpenRuleUnderActiveTab(const AGrid: TTerminalGrid);
    function FocusedIsInput: Boolean;
    /// <summary>Fires the first button whose command is Yes (AYes) or No.</summary>
    function TryYesNoButton(AYes: Boolean): Boolean;
    /// <summary>Activates the button, checkbox or radio button whose caption
    /// marks ACh with '&' (HotKeyCharOf): presses the button, toggles the
    /// checkbox, selects the radio button. Captions without a marker have no
    /// hotkey.</summary>
    function TryMnemonic(ACh: Char): Boolean;
    function FocusedIsButton: Boolean;
    function NormalizeAcceptKey(var AKey: Word; var AKeyChar: Char): Boolean;
    procedure NotifyChanged;
    procedure FireCommand(const AId: string);
    /// <summary>Button AIndex's command, after the press animation.</summary>
    procedure PressButton(AIndex: Integer);
    procedure StartPress(AIndex: Integer; const AAction: TProc);
    procedure RunPendingPress;
    procedure DropPress;
    function ButtonIndexById(const AId: string): Integer;
    function CanShiftButton(const R: TRectI): Boolean;
    function MouseCaptureMove(ALocalCol, ALocalRow: Integer): Boolean;
    procedure MouseCaptureRelease(ALocalCol, ALocalRow: Integer);
    procedure FireCancel;
    function FindDefaultButtonIndex: Integer;
    procedure FireDefault;
    procedure FireAccept;
    procedure CaptureListSelection;
    procedure SetListSelectedIndex(AControlIndex, ASelected: Integer);
    function CanFocus(AIndex: Integer): Boolean;
    function SelectedItemText(const C: TDialogControl): string;
    procedure DrawDisabledField(const AGrid: TTerminalGrid; const R: TRectI;
      const AText: string; AWithArrow: Boolean);
    function ListSelectedIndexOf(const AId: string): Integer;
    function ListSelectedTextOf(const AId: string): string;
    function ListViewHeight(AControlIndex: Integer): Integer;
    procedure EnsureListInView(AControlIndex: Integer);
    function FindInputIndexById(const AId: string): Integer;
    function PadGridLine(const AText: string; AWidth: Integer): string;
    /// <summary>Themed vs fallback color for an always-selected row (combo
    /// display, focused/open DropDown field) - FTheme.ResolveDialogRowColors
    /// when themed, else the fixed FAR/NDN black-on-cyan cursor row.</summary>
    procedure ResolveSelectedRowColors(out AFg, ABg: TAlphaColor);
    /// <summary>Checkbox / radio colours where the theme does not draw them
    /// (warning dialogs, no theme): the focused row uses the selection
    /// colours and an underlined hotkey letter, others the label colours and
    /// a yellow letter on the red warning body.</summary>
    procedure ResolveFallbackItemColors(AFocused: Boolean; ALabelFg, ALabelBg: TAlphaColor;
      out AFg, ABg, AHotFg: TAlphaColor; out AHotAttr: TCharCellAttributes);
    /// <summary>Themed vs fallback color for a list row that may or may not
    /// be selected - same rule as ResolveSelectedRowColors, but falls back
    /// to the caller's own ANormalFg/ANormalBg when not selected and no
    /// theme is assigned.</summary>
    procedure ResolveRowHighlight(ASelected: Boolean; ANormalFg, ANormalBg: TAlphaColor;
      out AFg, ABg: TAlphaColor);
    procedure SelectRadio(AControlIndex: Integer);
    procedure NormalizeRadioGroups;
    procedure LayoutIn(AAreaW, AAreaH: Integer);
    /// <summary>Protocol 2 places each control at its own column and row,
    /// inside the frame.</summary>
    procedure LayoutV2Controls;
    /// <summary>Protocol 1 lays controls out in order via LayoutDialogFlow.</summary>
    procedure LayoutFlowControls;
    procedure RebuildControlLayout;
    procedure EnsureLayout;
    procedure CloseDropDown;
    /// <summary>dckInput with a History key: drops its history down like a
    /// dckDropDown (↓ in the last cell).</summary>
    function IsHistoryInput(AControlIndex: Integer): Boolean;
    function IsCancelCommand(const AId: string): Boolean;
    procedure LoadInputHistory;
    procedure SaveInputHistory;
    procedure RemoveDropHoverFromHistory;
    procedure OpenDropDown(AControlIndex: Integer);
    function DropPopupBounds(out ARect: TRectI): Boolean;
    /// <summary>The cells of the open list that show items: the whole block with
    /// the thin outline, the block inside its character frame without it.</summary>
    function DropContentBounds(const APopup: TRectI): TRectI;
    function DropPopupViewHeight: Integer;
    procedure EnsureDropHoverInView;
    procedure DrawDropDownPopup(const AGrid: TTerminalGrid);
    function CommitDropDown: Boolean;
    procedure DrawColorPickButton(const AGrid: TTerminalGrid; ACol, ARow: Integer;
      const AFieldColors: TInputLineColors; const AText: string);
    /// <summary>Foreground, background and text attributes of a color sample,
    /// read from the live source fields on every draw.</summary>
    procedure ResolveColorSample(const C: TDialogControl;
      out AFg, ABg: TAlphaColor; out AAttrs: TCharCellAttributes);
    procedure DrawColorSampleControl(const AGrid: TTerminalGrid; const R: TRectI;
      const C: TDialogControl);
    procedure DrawRadioGroupControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    procedure DrawListControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    /// <summary>↓ of a DropDown / history field, in the field's colors inverted.</summary>
    procedure DrawDropArrow(const AGrid: TTerminalGrid; ACol, ARow: Integer;
      const AFieldColors: TInputLineColors);
    procedure DrawDropDownControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl);
    procedure DrawButtonControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl);
    /// <summary>An input field. A color, date or history field keeps its
    /// button in the last cell; a disabled field is grey text. The edit line
    /// is read from the live control: the copied record can drop it.</summary>
    procedure DrawInputControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl);
    /// <summary>A checkbox. Warning dialogs and dialogs without a theme paint
    /// the box themselves: the theme checkbox is black on white and shows as
    /// a white strip on the red warning fill.</summary>
    procedure DrawCheckboxControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    /// <summary>A radio button. Warning dialogs and dialogs without a theme
    /// paint the mark themselves, for the same reason as a checkbox.</summary>
    procedure DrawRadioControl(const AGrid: TTerminalGrid; const R: TRectI;
      AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    /// <summary>A label or status line. An accent label is bold dark red on a
    /// light dialog and yellow on a dark one; a marked label is bold dark
    /// blue or bright cyan. Accent clips by cell count, marked by character
    /// width, so a wide glyph does not spill into the next control.</summary>
    procedure DrawGroupFrame(const AGrid: TTerminalGrid; const R: TRectI;
      const ATitle: string; AFg, ABg: TAlphaColor);
    procedure DrawLabelControl(const AGrid: TTerminalGrid; const R: TRectI;
      const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
    /// <summary>Half-block shadows of buttons that are not pressed. Painted
    /// after the faces and the separator joins. A shadow that would land on
    /// the frame is skipped: it would replace the border glyph.</summary>
    procedure DrawButtonShadows(const AGrid: TTerminalGrid);
    /// <summary>Dims the scene behind the dialog, then paints the frame, its
    /// shadow and the scrollbar. The dim runs first: a frame painted before
    /// it would be darkened with the scene.</summary>
    procedure DrawDialogChrome(const AGrid: TTerminalGrid);
    /// <summary>Colours of ordinary text on the dialog body: white on the red
    /// warning fill, the theme's row colours, or black on white.</summary>
    procedure ResolveDialogContentColors(out AFg, ABg: TAlphaColor);
    /// <summary>Paints each control that intersects the frame. One outside
    /// the frame is skipped, so a scrolled dialog does not draw into the
    /// rows above and below it.</summary>
    procedure DrawControls(const AGrid: TTerminalGrid; ALabelFg, ALabelBg: TAlphaColor);
    procedure ReportListSelection;
    /// <summary>Routes a click through uDialogHostClicks in fixed priority order.</summary>
    function HandleClickCore(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState): Boolean;
    /// <summary>Routes a key through uDialogHostKeys in fixed priority order.</summary>
    function HandleInputCore(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Method-pointer sink for uDialogHostKeys free functions.</summary>
    function BuildKeyOps: TDialogKeyOps;
    /// <summary>Method-pointer sink for uDialogHostClicks free functions.</summary>
    function BuildClickOps: TDialogClickOps;
    function KeyCursorVisible: Boolean;
    procedure KeyShowCursor;
    procedure KeyCommitDropDown;
    function KeyFocusIndex: Integer;
    procedure KeySetFocusIndex(AValue: Integer);
    function KeyDropOpenIndex: Integer;
    function KeyDropHover: Integer;
    procedure KeySetDropHover(AValue: Integer);
    function KeyControlCount: Integer;
    procedure KeySetControl(AIndex: Integer; const AControl: TDialogControl);
    function ClickBounds: TRectI;
    function ClickControlBounds(AIndex: Integer): TRectI;
    function ClickHasPressTimer: Boolean;
    function ClickHit(ACol, ARow: Integer): Integer;
    procedure ClickResetClicks;
    procedure ClickBeginButtonCapture(AIndex, ALocalCol, ALocalRow: Integer);
    procedure ClickBeginInputDrag(AIndex, ALocalCol, ALocalRow: Integer);
    procedure ClickApplyInputClick(AIndex, ALocalCol, ALocalRow: Integer;
      AExtend: Boolean; AClicks: Integer);
    function ClickDropScrollTop: Integer;
    function ClickListScrollTop: Integer;
    function ClickListSelectedIndexOf(const AId: string): Integer;
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;
    procedure Open(const ADecl: TDialogDeclaration; AOnCommand: TDialogCommandEvent);
    /// <summary>DIALOG_PLUGIN JSON subset. Returns False if parse fails (no open).</summary>
    function OpenJson(const ADeclJson: string; AOnCommand: TDialogCommandEvent): Boolean;
    procedure Close;
    /// <summary>Sets the open dialog aside (ATag is handed back by PopDialog) so the
    /// next Open shows over it. Close forgets whatever was set aside.</summary>
    procedure PushDialog(ATag: Integer);
    /// <summary>Brings back the dialog set aside by PushDialog, with its field
    /// values and focus. False when none was set aside.</summary>
    function PopDialog(out ATag: Integer): Boolean;
    /// <summary>Mask history lists end with a row that calls OnEditMaskGroups; it is
    /// shown while OnMaskGroupsAvailable (when set) answers True.</summary>
    property OnEditMaskGroups: TProc read FOnEditMaskGroups write FOnEditMaskGroups;
    property OnMaskGroupsAvailable: TFunc<Boolean> read FOnMaskGroupsAvailable
      write FOnMaskGroupsAvailable;
    function Visible: Boolean;
    /// <summary>Help topic the open dialog asks F1 to show ('' = none).</summary>
    function HelpTopic: string;
    function GetValuesJson: string;
    function GetInputValue(const AId: string): string;
    /// <summary>True when the open dialog has a control with AId.</summary>
    function HasControl(const AId: string): Boolean;
    /// <summary>"#RRGGBB" the dckColorPicker with AId currently holds ('' if none).</summary>
    function GetColorPickerHex(const AId: string): string;
    /// <summary>The date the dckDatePicker with AId currently shows (0 if none).</summary>
    function GetDatePickerDate(const AId: string): TDateTime;
    /// <summary>Moves the focus to the control with AId (no-op when absent).</summary>
    procedure FocusControlById(const AId: string);
    /// <summary>Live-updates a dckInput's text on the already-open dialog
    /// (cursor moves to the end) - the setter counterpart to GetInputValue,
    /// for cross-field sync (e.g. picking a list preset fills a hex field)
    /// that would be too disruptive to do via the usual close/reopen-with-a
    /// -patched-declaration pattern (that's for committing a whole dialog's
    /// worth of fields, not a value that changes on every arrow key).
    /// No-op if AId isn't a dckInput.</summary>
    procedure SetInputValue(const AId, AValue: string);
    /// <summary>Caret position of a dckInput (0 = before the first character).</summary>
    function GetInputCursor(const AId: string): Integer;
    /// <summary>SetInputValue with the caret at ACursor instead of the end.</summary>
    procedure SetInputValueAt(const AId, AValue: string; ACursor: Integer);
    function GetCheckbox(const AId: string): Boolean;
    /// <summary>0 = "don't care", 1 = unchecked, 2 = checked (see
    /// DialogCheckboxState).</summary>
    function GetCheckboxState(const AId: string): Integer;
    /// <summary>Sets a dckCheckbox of the open dialog; no-op for other ids.</summary>
    procedure SetCheckbox(const AId: string; AChecked: Boolean);
    /// <summary>Greys out (or restores) a checkbox, input or drop-down of the
    /// open dialog: it is skipped by the focus and ignores clicks. A focused
    /// control that gets disabled hands the focus to the next one.</summary>
    procedure SetControlDisabled(const AId: string; ADisabled: Boolean);
    function GetRadio(const AGroupId: string): string;
    /// <summary>Selects the radio AId of group AGroupId on the open dialog.</summary>
    procedure SetRadio(const AGroupId, ASelectedId: string);
    /// <summary>Replaces the captions of an open tab strip (a search narrows them)
    /// and selects one; APages gives the page each caption shows.</summary>
    procedure SetTabItems(const AId: string; const AItems: TArray<string>;
      const APages: TArray<Integer>; ASelectedIndex: Integer);
    /// <summary>Replaces the items of an open drop-down and selects one.</summary>
    procedure SetDropDownItems(const AId: string; const AItems: TArray<string>;
      ASelectedIndex: Integer);
    function GetListSelectedIndex(const AId: string): Integer;
    /// <summary>First visible row of the dialog's list. A reopened dialog starts at
    /// the top; SetListScrollTop restores the position (the next draw keeps the
    /// selected row in view).</summary>
    function GetListScrollTop: Integer;
    procedure SetListScrollTop(ATop: Integer);
    function GetListSelectedText(const AId: string): string;
    procedure SetStatus(const AId, AText: string);
    /// <summary>Live-update a dckLabel or dckStatus caption on the open
    /// dialog. No-op if AId is missing.</summary>
    procedure SetLabelText(const AId, AText: string);
    /// <summary>Coalesce OnChanged across a burst of live setters (progress
    /// labels). Nested; EndUpdate fires at most one notify if anything
    /// changed.</summary>
    procedure BeginUpdate;
    procedure EndUpdate;
    /// <summary>Replace items of an already-open dckList (dirsync preview,
    /// file diff). Resets scroll to the top.</summary>
    procedure SetListItems(const AId: string; const AItems: TArray<string>;
      ASelectedIndex: Integer = 0);
    /// <summary>Replaces the accent-colored stretches of an open dckList.</summary>
    procedure SetListAccents(const AId: string; const AAccents: TArray<TListAccent>);
    /// <summary>Replaces the colored overlays of an open dckList: one per row, row i
    /// takes ASwatches[i].</summary>
    procedure SetListSwatches(const AId: string; const ASwatches: TArray<TListSwatch>);
    procedure Draw(const AGrid: TTerminalGrid; AAreaW, AAreaH: Integer);
    function HandleInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Hit-test buttons/checkboxes; fires command on button click.</summary>
    /// <summary>Shift+click in an input field extends its selection.</summary>
    function HandleClick(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState = []): Boolean;
    /// <summary>True when (ACol,ARow) is inside the dialog frame (after layout).</summary>
    function ContainsLocal(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>Design-time control count (mirrors the open declaration).</summary>
    function ControlCount: Integer;
    /// <summary>Design-time read-only copy of one control.</summary>
    function GetControl(AIndex: Integer): TDialogControl;
    /// <summary>Design-time layout box (grid-absolute, same coordinate space
    /// as HandleClick's col/row) of one control. Empty rect if out of range.</summary>
    function ControlBoundsAt(AIndex: Integer): TRectI;
    /// <summary>Design-time hit test: index of the control under
    /// (ALocalCol, ALocalRow), else -1. Unlike HandleClick this never fires
    /// commands, moves focus, or opens/closes the DropDown popup.</summary>
    function ControlIndexAt(ALocalCol, ALocalRow: Integer): Integer;
    /// <summary>Id of focused button, else default/yes/ok button, else ''.</summary>
    function FocusedOrDefaultButtonId: string;
    /// <summary>Id of whichever control currently has keyboard focus (any
    /// kind), '' when none focused. Unlike FocusedOrDefaultButtonId this
    /// never falls back to a button - for callers that need "the field the
    /// user is on" (e.g. F9 = pick a color for the focused hex
    /// input), a fallback would answer the wrong question.</summary>
    function FocusedControlId: string;
    function ChromeContext: TFunctionBarContext;
    /// <summary>A DropDown / history list is dropped down (it owns Enter).</summary>
    function DropDownOpen: Boolean;
    /// <summary>Adds the history fields to uDialogHistory unless ACommandId
    /// cancels the dialog. FireCommand does it itself; hosts that turn Enter
    /// into a command without going through HandleInput call it.</summary>
    procedure RecordInputHistory(const ACommandId: string);
    procedure SetCursorVisible(AVisible: Boolean);
    /// <summary>Shows the button AId pressed, then runs AAction when it is
    /// released (see GDialogButtonPressStart). Runs AAction at once when
    /// press animation is off or no button has that id. For hosts that pick
    /// a key's command themselves instead of passing the key to HandleInput.</summary>
    procedure PressButtonThen(const AId: string; const AAction: TProc);
    /// <summary>The dialog frame after the last Draw / layout (grid cells).</summary>
    property Bounds: TRectI read FBounds;
    /// <summary>Index of the button drawn pressed, -1 when none.</summary>
    property PressedButton: Integer read FPressIndex;
    property CursorVisible: Boolean read FCursorVisible;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    /// <summary>Fired with the control id when the selected item of a list
    /// changes by keyboard or mouse.</summary>
    property OnListSelected: TDialogValueChangedEvent read FOnListSelected
      write FOnListSelected;
    /// <summary>Fired with the control id when the user picks another item of a
    /// drop-down, by keyboard or mouse.</summary>
    property OnValueChanged: TDialogValueChangedEvent read FOnValueChanged
      write FOnValueChanged;
    /// <summary>After a button command that ran later than the input that
    /// pressed it (mouse release, end of the keyboard press), so the owner
    /// can finish what it does after HandleInput / HandleClick return.</summary>
    property OnDeferredCommand: TNotifyEvent read FOnDeferredCommand write FOnDeferredCommand;
  end;

const
  /// <summary>How long a button stays pressed after a key activates it.</summary>
  cDialogButtonPressMs = 100;

var
  /// <summary>Starts (or restarts) the one-shot press timer, which calls
  /// FlushDialogButtonPress after cDialogButtonPressMs. Set by the main form.
  /// While nil (tests, DialogDesigner) buttons fire on mouse down and on the
  /// key itself, without the press.</summary>
  GDialogButtonPressStart: TProc = nil;
  /// <summary>Set by the main form while it handles the key down of Enter or
  /// Space: a button that key presses stays down until the key goes up
  /// (DialogButtonKeyUp) instead of for cDialogButtonPressMs.</summary>
  GDialogPressHoldKey: Word = 0;

/// <summary>Releases the keyboard-pressed button, if any, and runs its
/// command. The press timer calls it; so does the main form before handling
/// the next key or click, so a fast key never overtakes the command.</summary>
procedure FlushDialogButtonPress;
/// <summary>A button pressed from the keyboard is waiting for its release.</summary>
function DialogButtonPressPending: Boolean;
/// <summary>The key holding a pressed button (GDialogPressHoldKey), 0 when
/// no button is held by a key.</summary>
function DialogButtonHoldKey: Word;
/// <summary>Key up: when AKey holds a button, releases it and runs its command.</summary>
function DialogButtonKeyUp(AKey: Word): Boolean;
/// <summary>The held or keyboard-pressed button goes up without its command.</summary>
procedure CancelDialogButtonPress;
/// <summary>A button holds the mouse (pressed, waiting for the release).</summary>
function DialogButtonCaptured: Boolean;
/// <summary>Main form, before routing a left mouse-down: lifts a button held
/// by a key, completes a timed keyboard press and remembers the screen cell, so
/// a button this click captures maps later moves and the release to the
/// dialog's own coordinates.</summary>
procedure DialogButtonMouseDown(AAbsCol, AAbsRow: Integer);
/// <summary>Mouse moved while captured: the button looks pressed only while
/// the pointer is over it. True when that changed.</summary>
function DialogButtonCaptureMove(AAbsCol, AAbsRow: Integer): Boolean;
/// <summary>Left button released while captured: runs the command when the
/// pointer is still over the button.</summary>
procedure DialogButtonCaptureRelease(AAbsCol, AAbsRow: Integer);

implementation

uses
  System.Character, uStrings, uKeyChord, uDialogLocaleLayout, uCharWidth,
  uDialogValues, uDialogV2Layout, uDialogLayout, uDialogListDraw, uPluginInputChord;

const
  cWarningBodyBg = TAlphaColor($FFAA0000);

var
  GPressHost: TDialogHost = nil;
  GPressHoldKey: Word = 0;
  GCaptureHost: TDialogHost = nil;
  GCaptureDX: Integer = 0;
  GCaptureDY: Integer = 0;
  GMouseDownCol: Integer = 0;
  GMouseDownRow: Integer = 0;

procedure FlushDialogButtonPress;
var
  Host: TDialogHost;
begin
  Host := GPressHost;
  // A held button waits for its key to go up.
  if (Host = nil) or (GPressHoldKey <> 0) then
    Exit;
  GPressHost := nil;
  Host.RunPendingPress;
end;

function DialogButtonPressPending: Boolean;
begin
  Result := GPressHost <> nil;
end;

function DialogButtonHoldKey: Word;
begin
  if GPressHost = nil then
    GPressHoldKey := 0;
  Result := GPressHoldKey;
end;

function DialogButtonKeyUp(AKey: Word): Boolean;
begin
  Result := (DialogButtonHoldKey <> 0) and (AKey = GPressHoldKey);
  if not Result then
    Exit;
  GPressHoldKey := 0;
  FlushDialogButtonPress;
end;

procedure CancelDialogButtonPress;
var
  Host: TDialogHost;
begin
  Host := GPressHost;
  if Host = nil then
    Exit;
  Host.DropPress;
  Host.NotifyChanged;
end;

function DialogButtonCaptured: Boolean;
begin
  Result := GCaptureHost <> nil;
end;

procedure DialogButtonMouseDown(AAbsCol, AAbsRow: Integer);
begin
  // A click lifts a button held by a key; a timed press completes.
  if DialogButtonHoldKey <> 0 then
    CancelDialogButtonPress;
  FlushDialogButtonPress;
  GMouseDownCol := AAbsCol;
  GMouseDownRow := AAbsRow;
end;

function DialogButtonCaptureMove(AAbsCol, AAbsRow: Integer): Boolean;
var
  Was: Integer;
begin
  Result := False;
  if GCaptureHost = nil then
    Exit;
  Was := GCaptureHost.FPressIndex;
  Result := GCaptureHost.MouseCaptureMove(AAbsCol - GCaptureDX, AAbsRow - GCaptureDY);
  Result := Result or ((GCaptureHost <> nil) and (GCaptureHost.FPressIndex <> Was));
end;

procedure DialogButtonCaptureRelease(AAbsCol, AAbsRow: Integer);
var
  Host: TDialogHost;
begin
  Host := GCaptureHost;
  if Host = nil then
    Exit;
  GCaptureHost := nil;
  Host.MouseCaptureRelease(AAbsCol - GCaptureDX, AAbsRow - GCaptureDY);
end;

constructor TDialogHost.Create(const ATheme: IThemeRenderer);
begin
  inherited Create;
  FTheme := ATheme;
  FVisible := False;
  FFocusIndex := -1;
  FListSelId := '';
  FListSelIndex := 0;
  FListScrollTop := 0;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FUpdateLock := 0;
  FUpdateDirty := False;
  FAreaW := 80;
  FAreaH := 25;
  FPressIndex := -1;
  FMouseIndex := -1;
  FDragInput := -1;
  SetLength(FControlBounds, 0);
end;

destructor TDialogHost.Destroy;
begin
  DropPress;
  inherited;
end;

procedure TDialogHost.EnsureLayout;
begin
  if (FAreaW > 0) and (FAreaH > 0) then
    LayoutIn(FAreaW, FAreaH);
end;

procedure TDialogHost.NotifyChanged;
begin
  if FUpdateLock > 0 then
  begin
    FUpdateDirty := True;
    Exit;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TDialogHost.BeginUpdate;
begin
  Inc(FUpdateLock);
end;

procedure TDialogHost.EndUpdate;
begin
  if FUpdateLock <= 0 then
    Exit;
  Dec(FUpdateLock);
  if (FUpdateLock = 0) and FUpdateDirty then
  begin
    FUpdateDirty := False;
    NotifyChanged;
  end;
end;

function TDialogHost.Visible: Boolean;
begin
  Result := FVisible;
end;

function TDialogHost.HelpTopic: string;
begin
  if FVisible then
    Result := FDecl.HelpTopic
  else
    Result := '';
end;

function TDialogHost.CanFocus(AIndex: Integer): Boolean;
begin
  Result := (FDecl.Controls[AIndex].Kind in [dckInput, dckCheckbox, dckRadio,
    dckRadioGroup, dckButton, dckList, dckDropDown, dckColorPicker, dckDatePicker,
    dckTab]) and not DialogControlHiddenByTab(FDecl.Controls, AIndex) and
    not ((FDecl.Controls[AIndex].Kind in [dckCheckbox, dckInput, dckDropDown]) and
      FDecl.Controls[AIndex].Disabled) and
    not ((FDecl.Controls[AIndex].Kind = dckList) and FDecl.Controls[AIndex].Plain);
end;

function TDialogHost.FirstFocusable: Integer;
var
  I: Integer;
begin
  // The strip is reached by Tab; a dialog opens on its first real control.
  for I := 0 to High(FDecl.Controls) do
    if CanFocus(I) and (FDecl.Controls[I].Kind <> dckTab) then
      Exit(I);
  for I := 0 to High(FDecl.Controls) do
    if CanFocus(I) then
      Exit(I);
  Result := -1;
end;

procedure TDialogHost.SelectTab(AStrip, ANew: Integer);
begin
  if (AStrip < 0) or (AStrip > High(FDecl.Controls)) or
     (FDecl.Controls[AStrip].Kind <> dckTab) or
     (Length(FDecl.Controls[AStrip].Items) = 0) then
    Exit;
  DropPress;
  FDecl.Controls[AStrip].SelectedIndex :=
    EnsureRange(ANew, 0, High(FDecl.Controls[AStrip].Items));
  if (FFocusIndex < 0) or (FFocusIndex > High(FDecl.Controls)) or
     DialogControlHiddenByTab(FDecl.Controls, FFocusIndex) then
    FFocusIndex := AStrip;
  FScrollY := 0;
  FScrollFollow := -1;
  NotifyChanged;
end;

function TDialogHost.NextFocusable(AFrom: Integer; AForward: Boolean): Integer;
var
  N, Steps: Integer;
begin
  N := Length(FDecl.Controls);
  if N = 0 then
    Exit(-1);
  Result := AFrom;
  for Steps := 1 to N do
  begin
    if AForward then
      Result := (Result + 1) mod N
    else
      Result := (Result + N - 1) mod N;
    if CanFocus(Result) then
      Exit;
  end;
  Result := AFrom;
end;

function TDialogHost.FocusedIsInput: Boolean;
begin
  Result := (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
    ((FDecl.Controls[FFocusIndex].Kind = dckInput) or
     ((FDecl.Controls[FFocusIndex].Kind = dckColorPicker) and
      (FDecl.Controls[FFocusIndex].Picker.Line = cPickerLineHex)));
end;

function TDialogHost.HasControl(const AId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if SameText(FDecl.Controls[I].Id, AId) then
      Exit(True);
  Result := False;
end;

procedure TDialogHost.FocusControlById(const AId: string);
var
  I, Item: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if SameText(FDecl.Controls[I].Id, AId) then
    begin
      if DialogControlHiddenByTab(FDecl.Controls, I) then
      begin
        Item := DialogTabItemOfPage(FDecl.Controls[DialogTabStripIndex(FDecl.Controls)],
          FDecl.Controls[I].TabPage);
        if Item < 0 then
          Exit;
        FDecl.Controls[DialogTabStripIndex(FDecl.Controls)].SelectedIndex := Item;
      end;
      FFocusIndex := I;
      NotifyChanged;
      Exit;
    end;
end;

function TDialogHost.GetColorPickerHex(const AId: string): string;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckColorPicker) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(ColorPickerHex(FDecl.Controls[I].Picker));
  Result := '';
end;

function TDialogHost.GetDatePickerDate(const AId: string): TDateTime;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckDatePicker) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(DatePickerDate(FDecl.Controls[I].Cal));
  Result := 0;
end;

function TDialogHost.FocusedIsButton: Boolean;
begin
  Result := (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
    (FDecl.Controls[FFocusIndex].Kind = dckButton);
end;

function TDialogHost.NormalizeAcceptKey(var AKey: Word; var AKeyChar: Char): Boolean;
begin
  // FMX/Win: Enter may arrive as vkReturn, raw 13/10, KeyChar-only, or both.
  if (AKeyChar = #13) or (AKeyChar = #10) then
    AKey := vkReturn;
  if (AKey = 10) or (AKey = 13) or (AKey = vkReturn) or (AKey = vkAccept) then
  begin
    AKey := vkReturn;
    AKeyChar := #0;
    Exit(True);
  end;
  Result := False;
end;

procedure TDialogHost.Open(const ADecl: TDialogDeclaration;
  AOnCommand: TDialogCommandEvent);
var
  I: Integer;
begin
  FDecl := ADecl;
  SetLength(FListSeen, 0);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckList) and (FDecl.Controls[I].Id <> '') then
    begin
      SetLength(FListSeen, Length(FListSeen) + 1);
      FListSeen[High(FListSeen)] := TPair<string, Integer>.Create(
        FDecl.Controls[I].Id, FDecl.Controls[I].SelectedIndex);
    end;
  // Captions set after the resource was loaded and fitted (Build* naming a
  // button after the operation, e.g. "Копирование") can outgrow their box.
  FitDialogCaptions(FDecl);
  if FDecl.Width < 28 then
    FDecl.Width := 28;
  if FDecl.Height < 6 then
    FDecl.Height := 6;
  FOnCommand := AOnCommand;
  DropPress;
  Inc(FOpenGen);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FListScrollTop := 0;
  FScrollY := 0;
  FScrollFollow := -1;
  NormalizeRadioGroups;
  LoadInputHistory;
  FFocusIndex := FirstFocusable;
  FCursorVisible := True;
  CaptureListSelection;
  FVisible := True;
  NotifyChanged;
end;

procedure TDialogHost.SetCursorVisible(AVisible: Boolean);
begin
  if FCursorVisible = AVisible then
    Exit;
  FCursorVisible := AVisible;
  NotifyChanged;
end;

function TDialogHost.OpenJson(const ADeclJson: string;
  AOnCommand: TDialogCommandEvent): Boolean;
var
  Decl: TDialogDeclaration;
begin
  Result := TryParseDialogJson(ADeclJson, Decl);
  if not Result then
    Exit;
  Open(Decl, AOnCommand);
end;

procedure TDialogHost.Close;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  FOnCommand := nil;
  SetLength(FStash, 0);
  DropPress;
  Inc(FOpenGen);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FListScrollTop := 0;
  SetLength(FDecl.Controls, 0);
  SetLength(FControlBounds, 0);
  FFocusIndex := -1;
  FListSelId := '';
  FListSelIndex := 0;
  NotifyChanged;
end;

procedure TDialogHost.CloseDropDown;
begin
  if FDropOpenIndex < 0 then
    Exit;
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  NotifyChanged;
end;

function TDialogHost.IsHistoryInput(AControlIndex: Integer): Boolean;
begin
  Result := (AControlIndex >= 0) and (AControlIndex <= High(FDecl.Controls)) and
    (FDecl.Controls[AControlIndex].Kind = dckInput) and
    (FDecl.Controls[AControlIndex].History <> '') and
    not FDecl.Controls[AControlIndex].Password;
end;

function TDialogHost.IsCancelCommand(const AId: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].IsCancel and SameText(FDecl.Controls[I].Id, AId) then
      Exit(True);
  Result := False;
end;

procedure TDialogHost.LoadInputHistory;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if IsHistoryInput(I) then
      FDecl.Controls[I].Items := DialogHistoryItems(FDecl.Controls[I].History);
end;

procedure TDialogHost.SaveInputHistory;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if IsHistoryInput(I) then
      DialogHistoryAdd(FDecl.Controls[I].History, Trim(FDecl.Controls[I].Edit.Text));
end;

function IsMaskHistoryKey(const AKey: string): Boolean;
begin
  Result := SameText(AKey, 'masks') or SameText(AKey, 'findmask');
end;

// The list a history field drops down: its history, then (mask fields) the mask
// groups as @Name and a last row that opens the groups editor.
procedure TDialogHost.RefreshHistoryDropItems(AControlIndex: Integer);
var
  Hist, Items: TArray<string>;
  Name, Ref: string;
begin
  Hist := DialogHistoryItems(FDecl.Controls[AControlIndex].History);
  Items := Hist;
  FDropHistoryCount := Length(Hist);
  FDropActionRow := False;
  if IsMaskHistoryKey(FDecl.Controls[AControlIndex].History) then
  begin
    for Name in MaskGroupNames do
    begin
      Ref := '@' + Name;
      if not MatchText(Ref, Hist) then
        Items := Items + [Ref];
    end;
    FDropActionRow := Assigned(FOnEditMaskGroups) and
      (not Assigned(FOnMaskGroupsAvailable) or FOnMaskGroupsAvailable());
    if FDropActionRow then
      Items := Items + [T('ui.maskGroups.editRow', 'Mask groups...')];
  end;
  FDecl.Controls[AControlIndex].Items := Items;
end;

procedure TDialogHost.PushDialog(ATag: Integer);
var
  S: TDialogSnapshot;
begin
  if not FVisible then
    Exit;
  S.Decl := FDecl;
  S.FocusIndex := FFocusIndex;
  S.OnCommand := FOnCommand;
  S.ListSeen := Copy(FListSeen);
  S.ListSelId := FListSelId;
  S.ListSelIndex := FListSelIndex;
  S.ListScrollTop := FListScrollTop;
  S.ScrollY := FScrollY;
  S.ScrollFollow := FScrollFollow;
  S.Tag := ATag;
  FStash := FStash + [S];
end;

function TDialogHost.PopDialog(out ATag: Integer): Boolean;
var
  S: TDialogSnapshot;
begin
  ATag := 0;
  Result := Length(FStash) > 0;
  if not Result then
    Exit;
  S := FStash[High(FStash)];
  SetLength(FStash, High(FStash));
  FDecl := S.Decl;
  FOnCommand := S.OnCommand;
  FListSeen := S.ListSeen;
  FListSelId := S.ListSelId;
  FListSelIndex := S.ListSelIndex;
  FListScrollTop := S.ListScrollTop;
  FScrollY := S.ScrollY;
  FScrollFollow := S.ScrollFollow;
  FFocusIndex := S.FocusIndex;
  ATag := S.Tag;
  DropPress;
  Inc(FOpenGen);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  FCursorVisible := True;
  FVisible := True;
  EnsureLayout;
  NotifyChanged;
end;

procedure TDialogHost.RemoveDropHoverFromHistory;
var
  C: TDialogControl;
begin
  if not IsHistoryInput(FDropOpenIndex) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  // Mask groups and the editor row are not history entries.
  if (FDropHover < 0) or (FDropHover >= FDropHistoryCount) or
     (FDropHover > High(C.Items)) then
    Exit;
  DialogHistoryRemove(C.History, C.Items[FDropHover]);
  RefreshHistoryDropItems(FDropOpenIndex);
  if Length(FDecl.Controls[FDropOpenIndex].Items) = 0 then
  begin
    CloseDropDown;
    Exit;
  end;
  FDropHover := EnsureRange(FDropHover, 0, High(FDecl.Controls[FDropOpenIndex].Items));
  EnsureDropHoverInView;
  NotifyChanged;
end;

procedure TDialogHost.OpenDropDown(AControlIndex: Integer);
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if (FDecl.Controls[AControlIndex].Kind <> dckDropDown) and
     not IsHistoryInput(AControlIndex) then
    Exit;
  if IsHistoryInput(AControlIndex) then
    RefreshHistoryDropItems(AControlIndex);
  if Length(FDecl.Controls[AControlIndex].Items) = 0 then
    Exit;
  FFocusIndex := AControlIndex;
  FDropOpenIndex := AControlIndex;
  FDropScrollTop := 0;
  if IsHistoryInput(AControlIndex) then
  begin
    // History is ordered by last use; the cursor starts on the newest entry.
    FDropHover := 0;
  end
  else
  begin
    FDropHover := ListSelectedIndexOf(FDecl.Controls[AControlIndex].Id);
    if FDropHover < 0 then
      FDropHover := FDecl.Controls[AControlIndex].SelectedIndex;
  end;
  FDropHover := EnsureRange(FDropHover, 0, High(FDecl.Controls[AControlIndex].Items));
  EnsureLayout;
  EnsureDropHoverInView;
  NotifyChanged;
end;

function TDialogHost.CommitDropDown: Boolean;
var
  OpenEditor: Boolean;
begin
  Result := False;
  if FDropOpenIndex < 0 then
    Exit;
  OpenEditor := False;
  if IsHistoryInput(FDropOpenIndex) then
  begin
    if (FDropHover >= 0) and (FDropHover <= High(FDecl.Controls[FDropOpenIndex].Items)) then
    begin
      if FDropActionRow and (FDropHover = High(FDecl.Controls[FDropOpenIndex].Items)) then
        OpenEditor := True
      else
        InputLineSetText(FDecl.Controls[FDropOpenIndex].Edit,
          FDecl.Controls[FDropOpenIndex].Items[FDropHover]);
    end;
  end
  else
    SetListSelectedIndex(FDropOpenIndex, FDropHover);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  NotifyChanged;
  Result := True;
  if OpenEditor and Assigned(FOnEditMaskGroups) then
    FOnEditMaskGroups();
end;

function TDialogHost.DropPopupBounds(out ARect: TRectI): Boolean;
var
  R: TRectI;
  N, ItemH, SpaceBelow, SpaceAbove: Integer;
  ClientTop, ClientBottom: Integer;
  OpenBelow, CanBelow, CanAbove, FitsBelow, FitsAbove: Boolean;
  Extra: Integer;
begin
  Result := False;
  if (FDropOpenIndex < 0) or (FDropOpenIndex > High(FControlBounds)) then
    Exit;
  R := FControlBounds[FDropOpenIndex];
  N := Length(FDecl.Controls[FDropOpenIndex].Items);
  if N < 1 then
    Exit;
  // The character frame needs one more row, on the side away from the field.
  Extra := 0;
  if not EdgeBordersActive then
    Extra := 1;
  N := N + Extra;
  ClientTop := FBounds.Top + 1;
  ClientBottom := FBounds.Bottom - 1;
  SpaceBelow := ClientBottom - (R.Bottom + 1) + 1;
  SpaceAbove := R.Top - 1 - ClientTop + 1;
  CanBelow := SpaceBelow >= 1;
  CanAbove := SpaceAbove >= 1;
  FitsBelow := SpaceBelow >= N;
  FitsAbove := SpaceAbove >= N;
  // Prefer a side that can show every item; otherwise the side with more room
  // so Size/Zoom lists near the middle of a dialog still have a usable popup.
  if FitsBelow then
    OpenBelow := True
  else if FitsAbove then
    OpenBelow := False
  else if CanBelow and ((not CanAbove) or (SpaceBelow >= SpaceAbove)) then
    OpenBelow := True
  else if CanAbove then
    OpenBelow := False
  else
    OpenBelow := SpaceBelow >= SpaceAbove;
  // The list is a frameless block docked to the field: as wide as the field,
  // one row per visible item, starting on the row next to it.
  if OpenBelow then
  begin
    ItemH := Min(N, Max(SpaceBelow, 1));
    ARect := TRectI.Make(R.Left, R.Bottom + 1, R.Right, R.Bottom + ItemH);
  end
  else
  begin
    ItemH := Min(N, Max(SpaceAbove, 1));
    ARect := TRectI.Make(R.Left, R.Top - ItemH, R.Right, R.Top - 1);
  end;
  // The character frame stands one cell outside the field on each side.
  if Extra > 0 then
  begin
    Dec(ARect.Left);
    Inc(ARect.Right);
  end;
  if ARect.Left < FBounds.Left + 1 then
    ARect.Left := FBounds.Left + 1;
  if ARect.Right > FBounds.Right - 1 then
    ARect.Right := FBounds.Right - 1;
  if ARect.Top < ClientTop then
    ARect.Top := ClientTop;
  if ARect.Bottom > ClientBottom then
    ARect.Bottom := ClientBottom;
  if ARect.Right < ARect.Left then
    ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then
    ARect.Bottom := ARect.Top;
  Result := (ARect.Height >= 1 + Extra) and (ARect.Width >= 3 + 2 * Extra);
end;

function TDialogHost.DropContentBounds(const APopup: TRectI): TRectI;
begin
  Result := APopup;
  if EdgeBordersActive then
    Exit;
  Result.Left := APopup.Left + 1;
  Result.Right := APopup.Right - 1;
  if APopup.Top > FControlBounds[FDropOpenIndex].Bottom then
    Result.Bottom := APopup.Bottom - 1
  else
    Result.Top := APopup.Top + 1;
end;

function TDialogHost.DropPopupViewHeight: Integer;
var
  Frame: TRectI;
begin
  Result := 0;
  if DropPopupBounds(Frame) then
    Result := Max(DropContentBounds(Frame).Height, 0);
end;

procedure TDialogHost.EnsureDropHoverInView;
var
  ViewH, Count, MaxTop: Integer;
begin
  if FDropOpenIndex < 0 then
    Exit;
  ViewH := DropPopupViewHeight;
  Count := Length(FDecl.Controls[FDropOpenIndex].Items);
  if (ViewH <= 0) or (Count <= ViewH) then
  begin
    FDropScrollTop := 0;
    Exit;
  end;
  FDropHover := EnsureRange(FDropHover, 0, Count - 1);
  if FDropHover < FDropScrollTop then
    FDropScrollTop := FDropHover;
  if FDropHover >= FDropScrollTop + ViewH then
    FDropScrollTop := FDropHover - ViewH + 1;
  MaxTop := Count - ViewH;
  FDropScrollTop := EnsureRange(FDropScrollTop, 0, MaxTop);
end;

/// <summary>Single-line frame around a list docked to its field: left and right
/// sides and the side away from the field; the docked side stays open.</summary>
procedure DrawListFrame(const AGrid: TTerminalGrid; const AFrame: TRectI;
  AOpensBelow: Boolean; AFg, ABg: TAlphaColor);
var
  X, Y, FarY, FirstY, LastY: Integer;
begin
  if AOpensBelow then
  begin
    FarY := AFrame.Bottom;
    FirstY := AFrame.Top;
    LastY := AFrame.Bottom - 1;
  end
  else
  begin
    FarY := AFrame.Top;
    FirstY := AFrame.Top + 1;
    LastY := AFrame.Bottom;
  end;
  for Y := FirstY to LastY do
  begin
    PutGridText(AGrid, AFrame.Left, Y, #$2502, AFg, ABg);
    PutGridText(AGrid, AFrame.Right, Y, #$2502, AFg, ABg);
  end;
  for X := AFrame.Left + 1 to AFrame.Right - 1 do
    PutGridText(AGrid, X, FarY, #$2500, AFg, ABg);
  if AOpensBelow then
  begin
    PutGridText(AGrid, AFrame.Left, FarY, #$2514, AFg, ABg);
    PutGridText(AGrid, AFrame.Right, FarY, #$2518, AFg, ABg);
  end
  else
  begin
    PutGridText(AGrid, AFrame.Left, FarY, #$250C, AFg, ABg);
    PutGridText(AGrid, AFrame.Right, FarY, #$2510, AFg, ABg);
  end;
end;

procedure TDialogHost.DrawDropDownPopup(const AGrid: TTerminalGrid);
var
  Frame, Content: TRectI;
  C: TDialogControl;
  J, Idx, ViewH, Count, TextW: Integer;
  Line: string;
  RowFg, RowBg, FrameFg, FrameBg: TAlphaColor;
  NeedBar, Outlined, OpensBelow: Boolean;
  ListBg: TAlphaColor;
begin
  if not DropPopupBounds(Frame) then
    Exit;
  Outlined := EdgeBordersActive;
  OpensBelow := Frame.Top > FControlBounds[FDropOpenIndex].Bottom;
  EnsureDropHoverInView;
  Content := DropContentBounds(Frame);
  if (Content.Right < Content.Left) or (Content.Bottom < Content.Top) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  ViewH := Content.Height;
  Count := Length(C.Items);
  NeedBar := Count > ViewH;
  TextW := Content.Width;
  if NeedBar then
    TextW := Max(Content.Width - 1, 1);
  // The frame takes the theme's dialog body colours; without a theme, white
  // body and black frame.
  if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(False, FrameFg, FrameBg)
  else
  begin
    FrameFg := TAlphaColor($FF000000);
    FrameBg := TAlphaColor($FFFFFFFF);
  end;

  // The shadow separates the block from the dialog body, which has no frame to do so.
  DrawDialogShadow(AGrid, Frame);

  for J := 0 to ViewH - 1 do
  begin
    Idx := FDropScrollTop + J;
    if (Idx < 0) or (Idx > High(C.Items)) then
      Line := ''
    else
      Line := C.Items[Idx];
    // The outline lines run along the outer cell edges, so the text keeps one
    // blank cell away from the left one and, without a scroll bar, the right one.
    if Outlined and (Line <> '') then
      Line := ' ' + Line;
    if Outlined and not NeedBar then
      Line := PadGridLine(Line, Max(TextW - 1, 1)) + ' '
    else
      Line := PadGridLine(Line, Max(TextW, 1));
    ResolveRowHighlight(Idx = FDropHover, FrameFg, FrameBg, RowFg, RowBg);
    // The list background sets the frameless block apart from the dialog body.
    if (Idx <> FDropHover) and Assigned(FTheme) then
      RowBg := FTheme.ResolveDialogListBg;
    PutGridText(AGrid, Content.Left, Content.Top + J, Line, RowFg, RowBg);
  end;
  if NeedBar then
    DrawDialogScrollBar(AGrid, Content.Right, Content.Top, Content.Bottom,
      FDropScrollTop, Count, ViewH);
  if not Outlined then
  begin
    ListBg := FrameBg;
    if Assigned(FTheme) then
      ListBg := FTheme.ResolveDialogListBg;
    DrawListFrame(AGrid, Frame, OpensBelow, FrameFg, ListBg);
  end;
  if Outlined then
  begin
    // Added last: writing text into a cell replaces the cell and its edges.
    for J := Content.Top to Content.Bottom do
    begin
      AddGridEdges(AGrid, Content.Left, J, [ceLeft], FrameFg);
      AddGridEdges(AGrid, Content.Right, J, [ceRight], FrameFg);
    end;
    // The side docked to the field has no line: the field itself bounds the list there.
    for J := Content.Left to Content.Right do
      if OpensBelow then
        AddGridEdges(AGrid, J, Content.Bottom, [ceBottom], FrameFg)
      else
        AddGridEdges(AGrid, J, Content.Top, [ceTop], FrameFg);
  end;
end;

procedure TDialogHost.CaptureListSelection;
var
  I: Integer;
begin
  FListSelId := '';
  FListSelIndex := 0;
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown] then
    begin
      FListSelId := FDecl.Controls[I].Id;
      FListSelIndex := FDecl.Controls[I].SelectedIndex;
      Exit;
    end;
end;

function TDialogHost.ListSelectedIndexOf(const AId: string): Integer;
var
  I: Integer;
begin
  if (FListSelId <> '') and SameText(FListSelId, AId) then
    Exit(FListSelIndex);
  Result := -1;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown]) and
       SameText(FDecl.Controls[I].Id, AId) then
      Exit(FDecl.Controls[I].SelectedIndex);
end;

function TDialogHost.ListSelectedTextOf(const AId: string): string;
var
  I, Idx: Integer;
begin
  Result := '';
  Idx := ListSelectedIndexOf(AId);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckList, dckRadioGroup, dckDropDown]) and
       SameText(FDecl.Controls[I].Id, AId) then
    begin
      if (Idx >= 0) and (Idx <= High(FDecl.Controls[I].Items)) then
        Result := FDecl.Controls[I].Items[Idx];
      Exit;
    end;
end;

function TDialogHost.FindInputIndexById(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AId = '' then
    Exit;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckInput) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(I);
end;

function TDialogHost.PadGridLine(const AText: string; AWidth: Integer): string;
begin
  if AWidth < 1 then
    Exit('');
  // AWidth is in cells: a wide character takes two.
  Result := Copy(AText, 1, TextFitChars(AText, AWidth));
  Result := Result + StringOfChar(' ', AWidth - TextDisplayWidth(Result));
end;

procedure TDialogHost.SelectRadio(AControlIndex: Integer);
var
  G: string;
  I: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if FDecl.Controls[AControlIndex].Kind <> dckRadio then
    Exit;
  G := FDecl.Controls[AControlIndex].Group;
  if G = '' then
    G := FDecl.Controls[AControlIndex].Id;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckRadio) and SameText(FDecl.Controls[I].Group, G) then
      FDecl.Controls[I].Checked := (I = AControlIndex);
end;

procedure TDialogHost.NormalizeRadioGroups;
var
  I, J: Integer;
  G: string;
  Seen: TArray<string>;
  HasChecked: Boolean;

  function GroupSeen(const AGroup: string): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Seen) do
      if SameText(Seen[K], AGroup) then
        Exit(True);
    Result := False;
  end;

begin
  SetLength(Seen, 0);
  for I := 0 to High(FDecl.Controls) do
  begin
    if FDecl.Controls[I].Kind <> dckRadio then
      Continue;
    G := FDecl.Controls[I].Group;
    if G = '' then
      Continue;
    if GroupSeen(G) then
      Continue;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := G;
    HasChecked := False;
    for J := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) and
         FDecl.Controls[J].Checked then
      begin
        HasChecked := True;
        Break;
      end;
    if not HasChecked then
    begin
      for J := 0 to High(FDecl.Controls) do
        if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) then
        begin
          FDecl.Controls[J].Checked := True;
          Break;
        end;
    end
    else
    begin
      // Keep first checked only.
      HasChecked := False;
      for J := 0 to High(FDecl.Controls) do
        if (FDecl.Controls[J].Kind = dckRadio) and SameText(FDecl.Controls[J].Group, G) then
        begin
          if FDecl.Controls[J].Checked and not HasChecked then
            HasChecked := True
          else
            FDecl.Controls[J].Checked := False;
        end;
    end;
  end;
end;

function TDialogHost.GetInputValue(const AId: string): string;
var
  I: Integer;
begin
  Result := '';
  I := FindInputIndexById(AId);
  if I >= 0 then
    Result := FDecl.Controls[I].Edit.Text;
end;

procedure TDialogHost.SetInputValue(const AId, AValue: string);
var
  I: Integer;
begin
  I := FindInputIndexById(AId);
  if I >= 0 then
    InputLineSetText(FDecl.Controls[I].Edit, AValue);
end;

function TDialogHost.GetInputCursor(const AId: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := FindInputIndexById(AId);
  if I >= 0 then
    Result := FDecl.Controls[I].Edit.Cursor;
end;

procedure TDialogHost.SetInputValueAt(const AId, AValue: string; ACursor: Integer);
var
  I: Integer;
begin
  I := FindInputIndexById(AId);
  if I >= 0 then
    InputLineSetTextAt(FDecl.Controls[I].Edit, AValue, ACursor);
end;

function TDialogHost.GetCheckbox(const AId: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckCheckbox) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(FDecl.Controls[I].Checked);
end;

function TDialogHost.GetCheckboxState(const AId: string): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckCheckbox) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(DialogCheckboxState(FDecl.Controls[I]));
end;

procedure TDialogHost.SetControlDisabled(const AId: string; ADisabled: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if SameText(FDecl.Controls[I].Id, AId) and
       (FDecl.Controls[I].Kind in [dckCheckbox, dckInput, dckDropDown]) then
    begin
      FDecl.Controls[I].Disabled := ADisabled;
      if ADisabled and (I = FFocusIndex) then
        FFocusIndex := NextFocusable(I, True);
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetCheckbox(const AId: string; AChecked: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckCheckbox) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      FDecl.Controls[I].Checked := AChecked;
      Exit;
    end;
end;

procedure TDialogHost.SetRadio(const AGroupId, ASelectedId: string);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckRadio) and
       SameText(FDecl.Controls[I].Group, AGroupId) then
      FDecl.Controls[I].Checked := SameText(FDecl.Controls[I].Id, ASelectedId);
  NotifyChanged;
end;

procedure TDialogHost.SetTabItems(const AId: string; const AItems: TArray<string>;
  const APages: TArray<Integer>; ASelectedIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckTab) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      FDecl.Controls[I].Items := Copy(AItems);
      FDecl.Controls[I].TabPages := Copy(APages);
      if Length(AItems) = 0 then
        FDecl.Controls[I].SelectedIndex := 0
      else
        FDecl.Controls[I].SelectedIndex := EnsureRange(ASelectedIndex, 0, High(AItems));
      if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
         DialogControlHiddenByTab(FDecl.Controls, FFocusIndex) then
        FFocusIndex := I;
      FScrollY := 0;
      FScrollFollow := -1;
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetDropDownItems(const AId: string;
  const AItems: TArray<string>; ASelectedIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckDropDown) and
       SameText(FDecl.Controls[I].Id, AId) then
    begin
      FDecl.Controls[I].Items := Copy(AItems);
      FDecl.Controls[I].ItemIds := nil;
      if Length(AItems) = 0 then
        FDecl.Controls[I].SelectedIndex := 0
      else
        FDecl.Controls[I].SelectedIndex := EnsureRange(ASelectedIndex, 0, High(AItems));
      NotifyChanged;
      Exit;
    end;
end;

function TDialogHost.GetRadio(const AGroupId: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FDecl.Controls) do
  begin
    if (FDecl.Controls[I].Kind = dckRadioGroup) and
       SameText(FDecl.Controls[I].Id, AGroupId) then
      Exit(RadioGroupValueOf(FDecl.Controls[I]));
    if (FDecl.Controls[I].Kind = dckRadio) and
       SameText(FDecl.Controls[I].Group, AGroupId) and
       FDecl.Controls[I].Checked then
    begin
      if FDecl.Controls[I].Id <> '' then
        Exit(FDecl.Controls[I].Id);
      Exit(FDecl.Controls[I].Text);
    end;
  end;
end;

function TDialogHost.GetListSelectedIndex(const AId: string): Integer;
begin
  Result := ListSelectedIndexOf(AId);
end;

function TDialogHost.GetListScrollTop: Integer;
begin
  Result := FListScrollTop;
end;

procedure TDialogHost.SetListScrollTop(ATop: Integer);
begin
  FListScrollTop := Max(0, ATop);
end;

function TDialogHost.GetListSelectedText(const AId: string): string;
begin
  Result := ListSelectedTextOf(AId);
end;

function TDialogHost.GetValuesJson: string;
begin
  Result := DialogValuesJson(FDecl.Controls, FListSelId, FListSelIndex);
end;

procedure TDialogHost.SetStatus(const AId, AText: string);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckStatus) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      if FDecl.Controls[I].Text = AText then
        Exit;
      FDecl.Controls[I].Text := AText;
      NotifyChanged;
      Exit;
    end;
  SetLabelText(AId, AText);
end;

procedure TDialogHost.SetLabelText(const AId, AText: string);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind in [dckLabel, dckStatus]) and
       SameText(FDecl.Controls[I].Id, AId) then
    begin
      if FDecl.Controls[I].Text = AText then
        Exit;
      FDecl.Controls[I].Text := AText;
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetListAccents(const AId: string; const AAccents: TArray<TListAccent>);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckList) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      FDecl.Controls[I].ItemAccents := Copy(AAccents);
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetListSwatches(const AId: string; const ASwatches: TArray<TListSwatch>);
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckList) and SameText(FDecl.Controls[I].Id, AId) then
    begin
      FDecl.Controls[I].ItemSwatches := Copy(ASwatches);
      NotifyChanged;
      Exit;
    end;
end;

procedure TDialogHost.SetListItems(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer);
var
  I, Sel: Integer;
  Items: TArray<string>;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    if (FDecl.Controls[I].Kind <> dckList) or not SameText(FDecl.Controls[I].Id, AId) then
      Continue;
    if Length(AItems) = 0 then
    begin
      SetLength(Items, 1);
      Items[0] := '(none)';
    end
    else
      Items := Copy(AItems);
    FDecl.Controls[I].Items := Items;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
    FDecl.Controls[I].SelectedIndex := Sel;
    FListSelId := AId;
    FListSelIndex := Sel;
    FListScrollTop := 0;
    NotifyChanged;
    Exit;
  end;
end;

procedure TDialogHost.FireCommand(const AId: string);
var
  Cmd: TDialogCommandEvent;
  Values, Id: string;
begin
  Cmd := FOnCommand;
  // Own a reference to the id before invoking the handler. Callers pass
  // FDecl.Controls[I].Id, and handlers routinely call Close, which does
  // SetLength(FDecl.Controls, 0) - that drops the last reference and frees the
  // string out from under this `const` (no-refcount) parameter. Any
  // DialogCmdIs* test the handler runs after Close would then read freed
  // memory ("Invalid pointer operation").
  Id := AId;
  RecordInputHistory(Id);
  Values := GetValuesJson;
  if Assigned(Cmd) then
    Cmd(Id, Values);
end;

function TDialogHost.DropDownOpen: Boolean;
begin
  Result := FVisible and (FDropOpenIndex >= 0);
end;

procedure TDialogHost.RecordInputHistory(const ACommandId: string);
begin
  // Whatever the dialog does next, a non-cancel command used the fields.
  if not DialogCmdIsReject(ACommandId) and not IsCancelCommand(ACommandId) then
    SaveInputHistory;
end;

procedure TDialogHost.DropPress;
begin
  if GPressHost = Self then
  begin
    GPressHost := nil;
    GPressHoldKey := 0;
  end;
  if GCaptureHost = Self then
    GCaptureHost := nil;
  FPendingAction := nil;
  FPressIndex := -1;
  FMouseIndex := -1;
  FDragInput := -1;
end;

function TDialogHost.ButtonIndexById(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

function TDialogHost.CanShiftButton(const R: TRectI): Boolean;
begin
  // Same room check as the shadow: the shifted face must not reach the frame.
  Result := R.Right + 1 < FBounds.Right;
end;

procedure TDialogHost.StartPress(AIndex: Integer; const AAction: TProc);
var
  Gen: Cardinal;
begin
  if not Assigned(GDialogButtonPressStart) or not FVisible or
     (AIndex < 0) or (AIndex > High(FDecl.Controls)) then
  begin
    AAction();
    Exit;
  end;
  // A press still showing (another key within the press time) completes first.
  Gen := FOpenGen;
  FlushDialogButtonPress;
  if not FVisible or (FOpenGen <> Gen) then
    Exit;
  FPressIndex := AIndex;
  FPendingAction := AAction;
  FPendingGen := FOpenGen;
  GPressHost := Self;
  NotifyChanged;
  if GDialogPressHoldKey <> 0 then
    GPressHoldKey := GDialogPressHoldKey
  else
    GDialogButtonPressStart();
end;

procedure TDialogHost.PressButton(AIndex: Integer);
var
  Id: string;
begin
  Id := FDecl.Controls[AIndex].Id;
  StartPress(AIndex,
    procedure
    begin
      FireCommand(Id);
    end);
end;

procedure TDialogHost.PressButtonThen(const AId: string; const AAction: TProc);
begin
  StartPress(ButtonIndexById(AId), AAction);
end;

procedure TDialogHost.RunPendingPress;
var
  Action: TProc;
  Done: TNotifyEvent;
begin
  Action := FPendingAction;
  FPendingAction := nil;
  FPressIndex := -1;
  if not Assigned(Action) or not FVisible or (FPendingGen <> FOpenGen) then
  begin
    NotifyChanged;
    Exit;
  end;
  // Read before the command: it may close the dialog or its window.
  Done := FOnDeferredCommand;
  Action();
  if Assigned(Done) then
    Done(Self);
end;

function TDialogHost.MouseCaptureMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Over: Boolean;
  R: TRectI;
  Before: TInputLine;
begin
  Result := False;
  if FDragInput >= 0 then
  begin
    // Dragging a selection: the caret follows the pointer; past either end
    // of the field it steps one cell beyond, which scrolls the text.
    if (FDragInput > High(FControlBounds)) or (FDragInput > High(FDecl.Controls)) then
      Exit;
    R := FControlBounds[FDragInput];
    Before := FDecl.Controls[FDragInput].Edit;
    if (ALocalCol < R.Left) and (FDecl.Controls[FDragInput].Edit.ViewLeft > 0) then
      Dec(FDecl.Controls[FDragInput].Edit.ViewLeft);
    InputLineMouseClick(FDecl.Controls[FDragInput].Edit,
      EnsureRange(ALocalCol - R.Left, -1, R.Width), 1, True);
    Result := (Before.Cursor <> FDecl.Controls[FDragInput].Edit.Cursor) or
      (Before.SelAnchor <> FDecl.Controls[FDragInput].Edit.SelAnchor) or
      (Before.ViewLeft <> FDecl.Controls[FDragInput].Edit.ViewLeft);
    if Result then
      NotifyChanged;
    Exit;
  end;
  if (FMouseIndex < 0) or (FMouseIndex > High(FControlBounds)) then
    Exit;
  Over := FControlBounds[FMouseIndex].Contains(ALocalCol, ALocalRow);
  if Over and (FPressIndex <> FMouseIndex) then
  begin
    FPressIndex := FMouseIndex;
    NotifyChanged;
  end
  else if not Over and (FPressIndex = FMouseIndex) then
  begin
    FPressIndex := -1;
    NotifyChanged;
  end;
end;

procedure TDialogHost.MouseCaptureRelease(ALocalCol, ALocalRow: Integer);
var
  Idx: Integer;
  Id: string;
  Done: TNotifyEvent;
begin
  if FDragInput >= 0 then
  begin
    FDragInput := -1;
    Exit;
  end;
  Idx := FMouseIndex;
  FMouseIndex := -1;
  FPressIndex := -1;
  if not FVisible or (Idx < 0) or (Idx > High(FControlBounds)) or
     (Idx > High(FDecl.Controls)) or
     not FControlBounds[Idx].Contains(ALocalCol, ALocalRow) then
  begin
    NotifyChanged;
    Exit;
  end;
  Id := FDecl.Controls[Idx].Id;
  Done := FOnDeferredCommand;
  FireCommand(Id);
  if Assigned(Done) then
    Done(Self);
end;

procedure TDialogHost.FireCancel;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].IsCancel then
    begin
      FireCommand(FDecl.Controls[I].Id);
      Exit;
    end;
  FireCommand(cDlgCmdCancel);
end;

function TDialogHost.FindDefaultButtonIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and FDecl.Controls[I].IsDefault then
      Exit(I);
  Result := -1;
end;

procedure TDialogHost.FireDefault;
var
  Idx, I: Integer;
begin
  Idx := FindDefaultButtonIndex;
  if Idx < 0 then
    for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckButton) and
         DialogCmdIsAccept(FDecl.Controls[I].Id) then
      begin
        Idx := I;
        Break;
      end;
  if Idx < 0 then
    for I := 0 to High(FDecl.Controls) do
      if (FDecl.Controls[I].Kind = dckButton) and not FDecl.Controls[I].IsCancel then
      begin
        Idx := I;
        Break;
      end;
  if Idx >= 0 then
    PressButton(Idx)
  else
  begin
    // List-only dialogs (e.g. Code page): Enter accepts current selection.
    for I := 0 to High(FDecl.Controls) do
      if FDecl.Controls[I].Kind = dckList then
      begin
        FireCommand(cDlgCmdOk);
        Exit;
      end;
  end;
end;

procedure TDialogHost.FireAccept;
begin
  // Windows-like: Enter on a focused push-button activates that button;
  // otherwise activate the dialog default.
  if FocusedIsButton then
    PressButton(FFocusIndex)
  else
    FireDefault;
end;

procedure TDialogHost.SetListSelectedIndex(AControlIndex, ASelected: Integer);
var
  C: TDialogControl;
  Before: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  C := FDecl.Controls[AControlIndex];
  if not (C.Kind in [dckList, dckRadioGroup, dckDropDown]) then
    Exit;
  Before := ListSelectedIndexOf(C.Id);
  if Length(C.Items) = 0 then
    C.SelectedIndex := 0
  else
    C.SelectedIndex := EnsureRange(ASelected, 0, High(C.Items));
  FDecl.Controls[AControlIndex] := C;
  // Always keep host mirror in sync (source of truth for OK/Enter).
  FListSelId := C.Id;
  FListSelIndex := C.SelectedIndex;
  if C.Kind = dckList then
    EnsureListInView(AControlIndex);
  if (C.Kind = dckDropDown) and (C.SelectedIndex <> Before) and
     Assigned(FOnValueChanged) then
    FOnValueChanged(C.Id);
end;

function TDialogHost.ListViewHeight(AControlIndex: Integer): Integer;
var
  R: TRectI;
  LastInner: Integer;
begin
  Result := 1;
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if Length(FControlBounds) > AControlIndex then
  begin
    R := FControlBounds[AControlIndex];
    Result := Max(R.Height, 1);
    // Last inner cell is FBounds.Bottom - 1 (bottom border occupies Bottom).
    LastInner := FBounds.Bottom - 1;
    if R.Top <= LastInner then
      Result := Max(Min(Result, LastInner - R.Top + 1), 1);
  end
  else if FDecl.Controls[AControlIndex].BoxH > 0 then
    Result := FDecl.Controls[AControlIndex].BoxH
  else
    Result := Max(ControlRowSpan(FDecl.Controls[AControlIndex]), 1);
end;

procedure TDialogHost.EnsureListInView(AControlIndex: Integer);
var
  ViewH, Count, Sel, MaxTop: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if FDecl.Controls[AControlIndex].Kind <> dckList then
    Exit;
  ViewH := ListViewHeight(AControlIndex);
  if ViewH <= 1 then
  begin
    FListScrollTop := 0;
    Exit;
  end;
  Count := Length(FDecl.Controls[AControlIndex].Items);
  Sel := ListSelectedIndexOf(FDecl.Controls[AControlIndex].Id);
  if Sel < 0 then
    Sel := 0;
  if Count <= ViewH then
  begin
    FListScrollTop := 0;
    Exit;
  end;
  if Sel < FListScrollTop then
    FListScrollTop := Sel;
  if Sel >= FListScrollTop + ViewH then
    FListScrollTop := Sel - ViewH + 1;
  MaxTop := Count - ViewH;
  FListScrollTop := EnsureRange(FListScrollTop, 0, MaxTop);
end;

procedure TDialogHost.ResolveSelectedRowColors(out AFg, ABg: TAlphaColor);
begin
  if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(True, AFg, ABg)
  else
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FF00AAAA);
  end;
end;

procedure TDialogHost.ResolveRowHighlight(ASelected: Boolean; ANormalFg, ANormalBg: TAlphaColor;
  out AFg, ABg: TAlphaColor);
begin
  if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(ASelected, AFg, ABg)
  else if ASelected then
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FF00AAAA);
  end
  else
  begin
    AFg := ANormalFg;
    ABg := ANormalBg;
  end;
end;

procedure TDialogHost.LayoutIn(AAreaW, AAreaH: Integer);
var
  W, H: Integer;
begin
  if AAreaW > 0 then
    FAreaW := AAreaW;
  if AAreaH > 0 then
    FAreaH := AAreaH;
  if IsDialogProtocolV2(FDecl.Version) then
  begin
    // Protocol 2.0: author owns dialog size; Host only clamps to the screen.
    W := Max(FDecl.Width, 1);
    H := Max(FDecl.Height, 1);
    if FAreaW > 2 then
      W := Min(W, FAreaW - 2);
    if FAreaH > 2 then
      H := Min(H, FAreaH - 2);
  end
  else
  begin
    W := Min(FDecl.Width, Max(FAreaW - 2, 28));
    H := Min(FDecl.Height, Max(FAreaH - 2, 6));
  end;
  FBounds := TRectI.Make(
    (FAreaW - W) div 2,
    Max((FAreaH - H) div 2, 2),
    (FAreaW - W) div 2 + W - 1,
    Max((FAreaH - H) div 2, 2) + H - 1);
  // Prefer keeping the dialog on-screen; shadow may clip at the edge.
  if FBounds.Right > FAreaW - 1 then
  begin
    FBounds.Right := FAreaW - 1;
    FBounds.Left := Max(FBounds.Right - W + 1, 0);
  end;
  if FBounds.Bottom > FAreaH - 1 then
  begin
    FBounds.Bottom := FAreaH - 1;
    FBounds.Top := Max(FBounds.Bottom - H + 1, 1);
  end;
  RebuildControlLayout;
end;

procedure TDialogHost.LayoutV2Controls;
var
  L: TDialogV2Layout;
begin
  L := LayoutDialogV2(FDecl.Controls, FBounds, FFocusIndex, FScrollY, FScrollFollow);
  FControlBounds := L.Bounds;
  FContentH := L.ContentH;
  FScrollY := L.ScrollY;
  FScrollFollow := L.ScrollFollow;
end;

procedure TDialogHost.LayoutFlowControls;
var
  L: TDialogFlowLayout;
begin
  L := LayoutDialogFlow(FDecl.Controls, FBounds);
  FControlBounds := L.Bounds;
end;

procedure TDialogHost.RebuildControlLayout;
begin
  SetLength(FControlBounds, Length(FDecl.Controls));
  if IsDialogProtocolV2(FDecl.Version) then
    LayoutV2Controls
  else
    LayoutFlowControls;
end;

// "bold+italic" -> attributes; unknown words are ignored.
function StyleAttrsFromText(const AText: string): TCharCellAttributes;
var
  Part: string;
begin
  Result := [];
  for Part in LowerCase(AText).Split(['+', ',', ' ']) do
    if Part = 'bold' then
      Include(Result, ccaBold)
    else if Part = 'italic' then
      Include(Result, ccaItalic)
    else if Part = 'underline' then
      Include(Result, ccaUnderline)
    else if Part = 'strike' then
      Include(Result, ccaStrike);
end;

procedure TDialogHost.ResolveColorSample(const C: TDialogControl;
  out AFg, ABg: TAlphaColor; out AAttrs: TCharCellAttributes);
var
  SrcIdx, I: Integer;
  StyleText: string;
begin
  // Re-resolved every Draw from the live (possibly uncommitted) text
  // of the source input(s) - no rebuild/reopen needed as the user
  // types. Blank/unparsable source text keeps whatever's pre-set
  // below as the fallback for that channel.
  //
  // When C.PanelState names a panel row (color-coding's editor sets
  // this - colorpicker.json's single-channel preview doesn't), an
  // unset channel previews as the THEME's own resolved color for
  // that row/state - the exact same "0 = inherit" meaning
  // TColorCodingColor.Fg/Bg=0 already has, so this shows what the
  // panel would render, not a placeholder. Without a theme
  // or a named state, falls back to fixed black-on-gray (still not
  // white - see dialog body note below).
  AFg := TAlphaColor($FF000000);
  ABg := TAlphaColor($FFC0C0C0); // not white: would blend into this Host's own (white) dialog body, hiding the swatch's extent
  if (C.PanelState <> cspsNone) and Assigned(FTheme) then
    FTheme.ResolveFileRowColors(False, False, False, '',
      C.PanelState = cspsSelected, C.PanelState = cspsCurrent, True,
      AFg, ABg);
  SrcIdx := FindInputIndexById(C.FgSourceId);
  if (SrcIdx < 0) or not HexToColor(FDecl.Controls[SrcIdx].Edit.Text, AFg) then
  begin
    SrcIdx := FindInputIndexById(C.FgFallbackId);
    if SrcIdx >= 0 then
      HexToColor(FDecl.Controls[SrcIdx].Edit.Text, AFg);
  end;
  SrcIdx := FindInputIndexById(C.BgSourceId);
  if (SrcIdx < 0) or not HexToColor(FDecl.Controls[SrcIdx].Edit.Text, ABg) then
  begin
    SrcIdx := FindInputIndexById(C.BgFallbackId);
    if SrcIdx >= 0 then
      HexToColor(FDecl.Controls[SrcIdx].Edit.Text, ABg);
  end;
  // The attributes come from a drop-down's selected item (its id), or BaseStyle
  // while that item has none of its own.
  StyleText := C.BaseStyle;
  if C.StyleSourceId <> '' then
    for I := 0 to High(FDecl.Controls) do
      if SameText(FDecl.Controls[I].Id, C.StyleSourceId) then
      begin
        if (FDecl.Controls[I].SelectedIndex >= 0) and
           (FDecl.Controls[I].SelectedIndex <= High(FDecl.Controls[I].ItemIds)) and
           (FDecl.Controls[I].ItemIds[FDecl.Controls[I].SelectedIndex] <> '') then
          StyleText := FDecl.Controls[I].ItemIds[FDecl.Controls[I].SelectedIndex];
        Break;
      end;
  AAttrs := StyleAttrsFromText(StyleText);
end;

procedure TDialogHost.DrawColorSampleControl(const AGrid: TTerminalGrid;
  const R: TRectI; const C: TDialogControl);
var
  SampleFg, SampleBg: TAlphaColor;
  Attrs: TCharCellAttributes;
begin
  ResolveColorSample(C, SampleFg, SampleBg, Attrs);
  FillGridRect(AGrid, R.Left, R.Top, R.Right, R.Bottom, ' ', SampleFg, SampleBg);
  PutGridText(AGrid, R.Left, R.Top, Copy(C.Text, 1, Max(R.Width, 1)),
    SampleFg, SampleBg, Attrs);
end;

procedure TDialogHost.DrawRadioGroupControl(const AGrid: TTerminalGrid;
  const R: TRectI; AIndex: Integer; const C: TDialogControl;
  ALabelFg, ALabelBg: TAlphaColor);
var
  J, Span, SelIdx: Integer;
  St: TThemeWidgetState;
  ItemFg, ItemBg: TAlphaColor;
begin
  Span := 0;
  SelIdx := ListSelectedIndexOf(C.Id);
  if C.Text <> '' then
  begin
    PutGridTextClipped(AGrid, R.Left, R.Top, R.Right,
      Copy(C.Text, 1, Max(R.Width, 1)), ALabelFg, ALabelBg);
    Span := 1;
  end;
  for J := 0 to High(C.Items) do
  begin
    if R.Top + Span + J >= FBounds.Bottom then
      Break;
    St := [];
    if (AIndex = FFocusIndex) and (J = SelIdx) then
      Include(St, twFocused);
    if Assigned(FTheme) and not FDecl.IsWarning then
      FTheme.DrawRadioBox(AGrid,
        TRectI.Make(R.Left, R.Top + Span + J, R.Right, R.Top + Span + J),
        C.Items[J], J = SelIdx, St)
    else
    begin
      if twFocused in St then
        ResolveSelectedRowColors(ItemFg, ItemBg)
      else
      begin
        ItemFg := ALabelFg;
        ItemBg := ALabelBg;
      end;
      PutGridTextClipped(AGrid, R.Left, R.Top + Span + J, R.Right,
        IfThen(J = SelIdx, '(*) ', '( ) ') + C.Items[J],
        ItemFg, ItemBg);
    end;
  end;
end;

procedure TDialogHost.DrawListControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  Span, SelIdx: Integer;
begin
  Span := ListViewHeight(AIndex);
  SelIdx := ListSelectedIndexOf(C.Id);
  if C.Plain then
    SelIdx := -1;
  if C.Framed and (Span > 1) then
    DrawDialogListFrame(AGrid, R, ALabelFg, ALabelBg);
  if Span <= 1 then
    DrawDialogSingleRowList(AGrid, R, C, FTheme, SelIdx)
  else
  begin
    EnsureListInView(AIndex);
    DrawDialogMultiRowList(AGrid, R, C, FTheme, ALabelFg, ALabelBg,
      Span, SelIdx, FListScrollTop, FBounds.Bottom);
  end;
end;

procedure TDialogHost.DrawDropArrow(const AGrid: TTerminalGrid; ACol, ARow: Integer;
  const AFieldColors: TInputLineColors);
begin
  // Inverse of the field it belongs to: stands out as a button in any theme.
  PutGridText(AGrid, ACol, ARow, WideChar($2193), AFieldColors.Bg, AFieldColors.Fg);
end;

// A swatch of the field's color with an ellipsis; inverse of the field when it holds no color.
procedure TDialogHost.DrawColorPickButton(const AGrid: TTerminalGrid; ACol, ARow: Integer;
  const AFieldColors: TInputLineColors; const AText: string);
var
  Swatch, Mark: TAlphaColor;
begin
  if HexToColor(AText, Swatch) then
  begin
    if (TAlphaColorRec(Swatch).R * 299 + TAlphaColorRec(Swatch).G * 587 +
        TAlphaColorRec(Swatch).B * 114) > 140000 then
      Mark := TAlphaColor($FF000000)
    else
      Mark := TAlphaColor($FFFFFFFF);
    PutGridText(AGrid, ACol, ARow, WideChar($2026), Mark, Swatch);
  end
  else
    PutGridText(AGrid, ACol, ARow, WideChar($2026), AFieldColors.Bg, AFieldColors.Fg);
end;

function TDialogHost.SelectedItemText(const C: TDialogControl): string;
var
  Idx: Integer;
begin
  Idx := ListSelectedIndexOf(C.Id);
  if (Idx >= 0) and (Idx <= High(C.Items)) then
    Result := C.Items[Idx]
  else
    Result := '';
end;

// An input or drop-down field in the colors of an enabled one, lightened.
procedure TDialogHost.DrawDisabledField(const AGrid: TTerminalGrid; const R: TRectI;
  const AText: string; AWithArrow: Boolean);
var
  Colors: TInputLineColors;
  Bg: TAlphaColor;
  Width, Rr, Gg, Bb: Cardinal;
begin
  Colors := InputLineDialogColors(False);
  Rr := (Colors.Bg shr 16) and $FF;
  Gg := (Colors.Bg shr 8) and $FF;
  Bb := Colors.Bg and $FF;
  Rr := Rr + (255 - Rr) * 45 div 100;
  Gg := Gg + (255 - Gg) * 45 div 100;
  Bb := Bb + (255 - Bb) * 45 div 100;
  Bg := TAlphaColor($FF000000 or (Rr shl 16) or (Gg shl 8) or Bb);
  Colors.Bg := Bg;
  Colors.Fg := TAlphaColor($FF505050);
  Width := Max(R.Width, 1);
  PutGridText(AGrid, R.Left, R.Top, PadGridLine(Copy(AText, 1, Width), Width),
    Colors.Fg, Colors.Bg, []);
  if AWithArrow and (R.Width >= 2) then
    DrawDropArrow(AGrid, R.Left + R.Width - 1, R.Top, Colors);
end;

procedure TDialogHost.DrawDropDownControl(const AGrid: TTerminalGrid;
  const R: TRectI; AIndex: Integer; const C: TDialogControl);
var
  Idx: Integer;
  Line: string;
  RowFg, RowBg: TAlphaColor;
  Colors: TInputLineColors;
begin
  Idx := ListSelectedIndexOf(C.Id);
  if (Idx >= 0) and (Idx <= High(C.Items)) then
    Line := C.Items[Idx]
  else
    Line := '';
  Line := PadGridLine(Line, Max(R.Width, 1));
  // Focused / open: black-on-cyan like Sort menu cursor; else cyan field.
  if (AIndex = FFocusIndex) or (FDropOpenIndex = AIndex) then
  begin
    ResolveSelectedRowColors(RowFg, RowBg);
    Colors.Fg := RowFg;
    Colors.Bg := RowBg;
  end
  else
    Colors := InputLineDialogColors(False);
  PutGridText(AGrid, R.Left, R.Top, Line, Colors.Fg, Colors.Bg);
  if R.Width >= 2 then
    DrawDropArrow(AGrid, R.Left + R.Width - 1, R.Top, Colors);
end;

procedure TDialogHost.DrawButtonControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl);
var
  St: TThemeWidgetState;
  Face: TRectI;
begin
  St := [];
  if AIndex = FFocusIndex then
    Include(St, twFocused);
  if C.IsDefault then
    Include(St, twSelected);
  Face := R;
  if AIndex = FPressIndex then
  begin
    Include(St, twPressed);
    // Pressed: the face slides onto its right shadow cell and the shadow
    // row below stays unpainted, so the button looks pushed in.
    if CanShiftButton(R) then
      Face := TRectI.Make(R.Left + 1, R.Top, R.Right + 1, R.Bottom);
  end;
  if Assigned(FTheme) then
    FTheme.DrawButton(AGrid, Face, C.Text, St)
  else if C.IsDefault then
    PutGridText(AGrid, Face.Left, Face.Top, '< ' + C.Text + ' >',
      TAlphaColor($FF000000), TAlphaColor($FF00AAAA))
  else
    PutGridText(AGrid, Face.Left, Face.Top, '[ ' + C.Text + ' ]',
      TAlphaColor($FF000000), TAlphaColor($FF00AAAA));
end;

procedure TDialogHost.ResolveFallbackItemColors(AFocused: Boolean; ALabelFg, ALabelBg: TAlphaColor;
  out AFg, ABg, AHotFg: TAlphaColor; out AHotAttr: TCharCellAttributes);
begin
  if AFocused then
  begin
    ResolveSelectedRowColors(AFg, ABg);
    AHotFg := AFg;
    AHotAttr := [ccaUnderline];
    Exit;
  end;
  AFg := ALabelFg;
  ABg := ALabelBg;
  if ALabelBg = cWarningBodyBg then
  begin
    AHotFg := TAlphaColor($FFFFFF55);
    AHotAttr := [];
  end
  else
  begin
    AHotFg := AFg;
    AHotAttr := [ccaUnderline];
  end;
end;

procedure TDialogHost.DrawInputControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl);
var
  Colors: TInputLineColors;
begin
  Colors := InputLineDialogColors(AIndex = FFocusIndex);
  if C.ColorPick and (R.Width >= 3) then
  begin
    // Last cell: the pick button.
    InputLineDraw(AGrid, R.Left, R.Top, R.Width - 1,
      FDecl.Controls[AIndex].Edit, AIndex = FFocusIndex, Colors, FCursorVisible, False);
    DrawColorPickButton(AGrid, R.Left + R.Width - 1, R.Top, Colors,
      FDecl.Controls[AIndex].Edit.Text);
  end
  else if C.DatePick and (R.Width >= 3) then
  begin
    // Last cell: the pick button.
    InputLineDraw(AGrid, R.Left, R.Top, R.Width - 1,
      FDecl.Controls[AIndex].Edit, AIndex = FFocusIndex, Colors, FCursorVisible, False);
    PutGridText(AGrid, R.Left + R.Width - 1, R.Top, WideChar($2026),
      Colors.Bg, Colors.Fg);
  end
  else if IsHistoryInput(AIndex) and (R.Width >= 3) then
  begin
    // Last cell: ↓ opens the history (like a dckDropDown field).
    InputLineDraw(AGrid, R.Left, R.Top, R.Width - 1,
      FDecl.Controls[AIndex].Edit, AIndex = FFocusIndex, Colors, FCursorVisible, False);
    DrawDropArrow(AGrid, R.Left + R.Width - 1, R.Top, Colors);
  end
  else if C.Disabled then
    DrawDisabledField(AGrid, R, IfThen(C.Password,
      StringOfChar('*', Length(FDecl.Controls[AIndex].Edit.Text)),
      FDecl.Controls[AIndex].Edit.Text), False)
  else
    InputLineDraw(AGrid, R.Left, R.Top, Max(R.Width, 8),
      FDecl.Controls[AIndex].Edit, AIndex = FFocusIndex, Colors, FCursorVisible,
      FDecl.Controls[AIndex].Password);
end;

function CheckboxMark(const AControl: TDialogControl): string;
begin
  case DialogCheckboxState(AControl) of
    0: Result := '[?] ';
    2: Result := '[x] ';
  else
    Result := '[ ] ';
  end;
end;

procedure TDialogHost.DrawCheckboxControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  St: TThemeWidgetState;
  ItemFg, ItemBg, HotFg: TAlphaColor;
  HotAttr: TCharCellAttributes;
  X: Integer;
begin
  if C.Disabled then
  begin
    PutGridText(AGrid, R.Left, R.Top,
      Copy(CheckboxMark(C) + StripHotKeyMarker(C.Text), 1, Max(R.Width, 1)),
      ContrastingGlyphFg(ALabelBg, TAlphaColor($FF808080), TAlphaColor($FF909090)),
      ALabelBg, []);
    Exit;
  end;
  // Warning chrome is red: theme DrawCheckBox paints black-on-white
  // (dialog body), which shows as a white strip on the red fill -
  // worse after translation when the caption (and box) grow.
  if FDecl.IsWarning or not Assigned(FTheme) then
  begin
    ResolveFallbackItemColors(AIndex = FFocusIndex, ALabelFg, ALabelBg,
      ItemFg, ItemBg, HotFg, HotAttr);
    PutGridHotTextClipped(AGrid, R.Left, R.Top, R.Right,
      CheckboxMark(C) + C.Text,
      ItemFg, ItemBg, HotFg, [], HotAttr);
  end
  else
  begin
    St := [];
    if AIndex = FFocusIndex then
      Include(St, twFocused);
    FTheme.DrawCheckBox(AGrid, R, C.Text, C.Checked, St);
    // The theme knows two marks; the "don't care" one is the unchecked mark
    // with its blank cell replaced by '?'.
    if C.Tristate and C.Unknown and (R.Top >= 0) and (R.Top <= High(AGrid)) then
      for X := R.Left + 1 to Min(R.Left + 3, R.Right) do
        if (X <= High(AGrid[R.Top])) and (AGrid[R.Top][X].CharValue = ' ') and
           (AGrid[R.Top][X - 1].CharValue <> ' ') then
        begin
          AGrid[R.Top][X].CharValue := '?';
          Break;
        end;
  end;
end;

procedure TDialogHost.DrawRadioControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  St: TThemeWidgetState;
  ItemFg, ItemBg, HotFg: TAlphaColor;
  HotAttr: TCharCellAttributes;
begin
  if FDecl.IsWarning or not Assigned(FTheme) then
  begin
    ResolveFallbackItemColors(AIndex = FFocusIndex, ALabelFg, ALabelBg,
      ItemFg, ItemBg, HotFg, HotAttr);
    PutGridHotTextClipped(AGrid, R.Left, R.Top, R.Right,
      IfThen(C.Checked, '(*) ', '( ) ') + C.Text,
      ItemFg, ItemBg, HotFg, [], HotAttr);
  end
  else
  begin
    St := [];
    if AIndex = FFocusIndex then
      Include(St, twFocused);
    FTheme.DrawRadioBox(AGrid, R, C.Text, C.Checked, St);
  end;
end;

procedure TDialogHost.DrawGroupFrame(const AGrid: TTerminalGrid; const R: TRectI;
  const ATitle: string; AFg, ABg: TAlphaColor);
var
  Edge, H, V, TL, TR, BL, BR: Char;
  Head: string;
  Y: Integer;
  Ascii: Boolean;
begin
  if (R.Width < 4) or (R.Height < 2) or (R.Top < 0) or (R.Bottom > High(AGrid)) or
     (FBounds.Left < 0) or (FBounds.Left > High(AGrid[R.Top])) then
    Exit;
  Edge := AGrid[R.Top][FBounds.Left].CharValue;
  Ascii := Edge = '|';
  if Ascii then
  begin
    H := '-'; V := '|'; TL := '+'; TR := '+'; BL := '+'; BR := '+';
  end
  else
  begin
    H := chBoxH; V := chBoxV; TL := chBoxTL; TR := chBoxTR; BL := chBoxBL; BR := chBoxBR;
  end;
  Head := TL + H;
  if ATitle <> '' then
    Head := Head + ' ' + Copy(ATitle, 1, Max(R.Width - 6, 0)) + ' ';
  Head := Head + StringOfChar(H, Max(R.Width - Length(Head) - 1, 0)) + TR;
  PutGridText(AGrid, R.Left, R.Top, Head, AFg, ABg);
  for Y := R.Top + 1 to R.Bottom - 1 do
  begin
    PutGridText(AGrid, R.Left, Y, V, AFg, ABg);
    PutGridText(AGrid, R.Right, Y, V, AFg, ABg);
  end;
  PutGridText(AGrid, R.Left, R.Bottom, BL + StringOfChar(H, R.Width - 2) + BR, AFg, ABg);
end;

procedure TDialogHost.DrawLabelControl(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  Colors: TInputLineColors;
  Shown: string;
  Lines: TArray<string>;
  I: Integer;
begin
  if (C.Kind = dckLabel) and C.GroupFrame then
    DrawGroupFrame(AGrid, R, C.Text, ALabelFg, ALabelBg)
  else if (C.Kind = dckLabel) and C.HintArea then
  begin
    if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) then
      Lines := TDialogRenderer.WrapLabelLines(FDecl.Controls[FFocusIndex].Hint, R.Width)
    else
      Lines := nil;
    for I := 0 to R.Height - 1 do
      PutGridText(AGrid, R.Left, R.Top + I,
        PadGridLine(IfThen(I <= High(Lines), Lines[I], ''), R.Width), ALabelFg, ALabelBg);
  end
  else if (C.Kind = dckLabel) and C.Field then
  begin
    Colors := InputLineDialogColors(False);
    Shown := C.Text;
    if (C.FieldCaretId <> '') and (C.FieldCaretId = FocusedControlId) then
      Shown := Shown + '_';
    PutGridText(AGrid, R.Left, R.Top,
      PadGridLine(Copy(Shown, Max(Length(Shown) - R.Width + 1, 1), R.Width), R.Width),
      Colors.Fg, Colors.Bg);
  end
  else if (C.Kind = dckLabel) and C.Accent then
    // Dark red on a light dialog, yellow on a dark one.
    PutGridText(AGrid, R.Left, R.Top, Copy(C.Text, 1, Max(R.Width, 1)),
      ContrastingGlyphFg(ALabelBg, cListAccentFg, TAlphaColor($FFFFFF55)),
      ALabelBg, [ccaBold])
  else if (C.Kind = dckLabel) and C.Marked then
    // Dark blue on a light dialog, bright cyan on a dark one.
    PutGridText(AGrid, R.Left, R.Top, Copy(C.Text, 1, TextFitChars(C.Text, Max(R.Width, 1))),
      ContrastingGlyphFg(ALabelBg, TAlphaColor($FF000080), TAlphaColor($FF55FFFF)),
      ALabelBg, [ccaBold])
  else
    TDialogRenderer.DrawLabel(AGrid, R, C.Text, ALabelFg, ALabelBg);
end;

procedure TDialogHost.DrawButtonShadows(const AGrid: TTerminalGrid);
var
  I: Integer;
  R: TRectI;
begin
  // Half-block button shadows after faces (▄ right, ▀ below).
  for I := 0 to High(FDecl.Controls) do
  begin
    if (I > High(FControlBounds)) then
      Break;
    if (FDecl.Controls[I].Kind <> dckButton) or (I = FPressIndex) then
      Continue;
    R := FControlBounds[I];
    if (R.Top > FBounds.Bottom - 1) or (R.Bottom < FBounds.Top + 1) then
      Continue;
    // ▄ sits at Right+1. Painting it onto the frame glyph replaces the
    // border with a half-block on white and looks like the button lost its
    // cyan. FitDialogToTranslatedText keeps two client cells free for this.
    if R.Right + 1 >= FBounds.Right then
      Continue;
    DrawButtonShadow(AGrid, R);
  end;
end;

procedure TDialogHost.DrawDialogChrome(const AGrid: TTerminalGrid);
begin
  // FAR-style modal dim: darken the already-painted scene, then paint chrome.
  DimGridExcept(AGrid, FBounds, GModalDimPercent);
  if FDecl.IsWarning then
    DrawWarningDialogFrame(AGrid, FBounds, FDecl.Title)
  else if Assigned(FTheme) then
    FTheme.DrawDialogFrame(AGrid, FBounds, FDecl.Title, [twFocused])
  else
    FillGridRect(AGrid, FBounds.Left, FBounds.Top, FBounds.Right, FBounds.Bottom,
      ' ', TAlphaColor($FF000000), TAlphaColor($FFFFFFFF));
  DrawDialogShadow(AGrid, FBounds);
  if FContentH > FBounds.Height - 2 then
    DrawDialogScrollBar(AGrid, FBounds.Right, FBounds.Top + 1, FBounds.Bottom - 1,
      FScrollY, FContentH, FBounds.Height - 2);
end;

procedure TDialogHost.ResolveDialogContentColors(out AFg, ABg: TAlphaColor);
begin
  if FDecl.IsWarning then
  begin
    AFg := TAlphaColor($FFFFFFFF);
    ABg := cWarningBodyBg;
  end
  else if Assigned(FTheme) then
    FTheme.ResolveDialogRowColors(False, AFg, ABg)
  else
  begin
    AFg := TAlphaColor($FF000000);
    ABg := TAlphaColor($FFFFFFFF);
  end;
end;

procedure TDialogHost.DrawControls(const AGrid: TTerminalGrid;
  ALabelFg, ALabelBg: TAlphaColor);
var
  I: Integer;
  C: TDialogControl;
  R: TRectI;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    if (I > High(FControlBounds)) then
      Break;
    R := FControlBounds[I];
    if (R.Top > FBounds.Bottom - 1) or (R.Bottom < FBounds.Top + 1) or
       (R.Left > FBounds.Right - 1) or (R.Right < FBounds.Left + 1) then
      Continue;
    C := FDecl.Controls[I];
    case C.Kind of
      dckLabel, dckStatus:
        DrawLabelControl(AGrid, R, C, ALabelFg, ALabelBg);
      dckColorSample:
        DrawColorSampleControl(AGrid, R, C);
      dckColorPicker:
        ColorPickerDraw(AGrid, R.Left, R.Top, FDecl.Controls[I].Picker,
          I = FFocusIndex, FCursorVisible, ALabelFg, ALabelBg);
      dckDatePicker:
        DatePickerDraw(AGrid, R.Left, R.Top, FDecl.Controls[I].Cal, ALabelFg, ALabelBg);
      dckInput:
        DrawInputControl(AGrid, R, I, C);
      dckCheckbox:
        DrawCheckboxControl(AGrid, R, I, C, ALabelFg, ALabelBg);
      dckRadio:
        DrawRadioControl(AGrid, R, I, C, ALabelFg, ALabelBg);
      dckRadioGroup:
        DrawRadioGroupControl(AGrid, R, I, C, ALabelFg, ALabelBg);
      dckList:
        DrawListControl(AGrid, R, I, C, ALabelFg, ALabelBg);
      dckDropDown:
        if C.Disabled then
          DrawDisabledField(AGrid, R, SelectedItemText(C), True)
        else
          DrawDropDownControl(AGrid, R, I, C);
      dckButton:
        DrawButtonControl(AGrid, R, I, C);
      dckTab:
        DrawTabStrip(AGrid, R, I, C, ALabelFg, ALabelBg);
    end;
  end;
end;

procedure TDialogHost.DrawTabStrip(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  Spans: TArray<TDialogTabSpan>;
  I: Integer;
  Cap: string;
  Fg, Bg: TAlphaColor;
  Colors: TInputLineColors;
begin
  if C.Vertical then
  begin
    DrawVerticalTabStrip(AGrid, R, AIndex, C, ALabelFg, ALabelBg);
    Exit;
  end;
  Spans := DialogTabSpans(C);
  for I := 0 to High(Spans) do
  begin
    if Spans[I].Left >= R.Width then
      Break;
    if I = C.SelectedIndex then
    begin
      if AIndex = FFocusIndex then
        ResolveSelectedRowColors(Fg, Bg)
      else
      begin
        Colors := InputLineDialogColors(False);
        Fg := Colors.Fg;
        Bg := Colors.Bg;
      end;
      Cap := '[ ' + C.Items[I] + ' ]';
      PutGridText(AGrid, R.Left + Spans[I].Left, R.Top,
        Copy(Cap, 1, R.Width - Spans[I].Left), Fg, Bg, [ccaBold]);
    end
    else
    begin
      Cap := '  ' + C.Items[I] + '  ';
      PutGridText(AGrid, R.Left + Spans[I].Left, R.Top,
        Copy(Cap, 1, R.Width - Spans[I].Left), ALabelFg, ALabelBg);
    end;
  end;
end;

procedure TDialogHost.DrawVerticalTabStrip(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  I: Integer;
  Cap: string;
  Fg, Bg: TAlphaColor;
  Colors: TInputLineColors;
begin
  for I := 0 to Min(High(C.Items), R.Height - 1) do
  begin
    Cap := ' ' + C.Items[I];
    if I = C.SelectedIndex then
    begin
      if AIndex = FFocusIndex then
        ResolveSelectedRowColors(Fg, Bg)
      else
      begin
        Colors := InputLineDialogColors(False);
        Fg := Colors.Fg;
        Bg := Colors.Bg;
      end;
      PutGridText(AGrid, R.Left, R.Top + I, PadGridLine(Cap, R.Width), Fg, Bg);
    end
    else
      PutGridText(AGrid, R.Left, R.Top + I, PadGridLine(Cap, R.Width), ALabelFg, ALabelBg);
  end;
end;

procedure TDialogHost.Draw(const AGrid: TTerminalGrid; AAreaW, AAreaH: Integer);
var
  LabelFg, LabelBg: TAlphaColor;
begin
  if not FVisible then
    Exit;
  LayoutIn(AAreaW, AAreaH);
  DrawDialogChrome(AGrid);
  ResolveDialogContentColors(LabelFg, LabelBg);
  DrawControls(AGrid, LabelFg, LabelBg);
  JoinSeparatorsToFrame(AGrid);
  DrawVerticalRules(AGrid);
  OpenRuleUnderActiveTab(AGrid);
  DrawButtonShadows(AGrid);
  DrawDropDownPopup(AGrid);
end;

// The rule under the tab strip is cut out below the selected tab and ends in
// corners there, so the tab reads as part of the page below it.
procedure TDialogHost.OpenRuleUnderActiveTab(const AGrid: TTerminalGrid);
var
  I, X, X0, X1, Y: Integer;
  R: TRectI;
  Spans: TArray<TDialogTabSpan>;
  Line, CornerL, CornerR: Char;
  Cell: TCharCell;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    if (I > High(FControlBounds)) or (FDecl.Controls[I].Kind <> dckTab) or
       FDecl.Controls[I].Vertical or DialogControlHiddenByTab(FDecl.Controls, I) then
      Continue;
    Spans := DialogTabSpans(FDecl.Controls[I]);
    if (FDecl.Controls[I].SelectedIndex < 0) or (FDecl.Controls[I].SelectedIndex > High(Spans)) then
      Continue;
    R := FControlBounds[I];
    Y := R.Top + 1;
    X0 := R.Left + Spans[FDecl.Controls[I].SelectedIndex].Left;
    X1 := X0 + Length(FDecl.Controls[I].Items[FDecl.Controls[I].SelectedIndex]) + 3;
    if (Y < 0) or (Y > High(AGrid)) or (X0 < 1) or (X1 + 1 > High(AGrid[Y])) or
       (X1 > R.Right) then
      Continue;
    if AGrid[Y][X0].CharValue = chBoxH then
    begin
      Line := chBoxH;
      CornerL := chBoxBR;
      CornerR := chBoxBL;
    end
    else if AGrid[Y][X0].CharValue = '-' then
    begin
      Line := '-';
      CornerL := '+';
      CornerR := '+';
    end
    else
      Continue;
    if (AGrid[Y][X1 + 1].CharValue <> Line) or (AGrid[Y][X0 - 1].CharValue <> Line) then
      Continue;
    for X := X0 to X1 do
    begin
      Cell := AGrid[Y][X];
      Cell.CharValue := ' ';
      AGrid[Y][X] := Cell;
    end;
    Cell := AGrid[Y][X0 - 1];
    Cell.CharValue := CornerL;
    AGrid[Y][X0 - 1] := Cell;
    Cell := AGrid[Y][X1 + 1];
    Cell.CharValue := CornerR;
    AGrid[Y][X1 + 1] := Cell;
  end;
end;

procedure TDialogHost.DrawVerticalRules(const AGrid: TTerminalGrid);
var
  I, Y: Integer;
  R: TRectI;
  Edge, LineCh, TopCh, BottomCh: Char;
  Cell: TCharCell;
begin
  for I := 0 to Min(High(FDecl.Controls), High(FControlBounds)) do
  begin
    if (FDecl.Controls[I].Kind <> dckLabel) or not FDecl.Controls[I].VRule then
      Continue;
    R := FControlBounds[I];
    if (R.Left <= FBounds.Left) or (R.Left >= FBounds.Right) or
       (R.Top <= FBounds.Top) or (R.Bottom + 1 >= FBounds.Bottom) or
       (R.Bottom + 1 > High(AGrid)) or (FBounds.Left < 0) or
       (FBounds.Right > High(AGrid[R.Top])) then
      Continue;
    Edge := AGrid[R.Top][FBounds.Left].CharValue;
    if (Edge = chDblV) or (Edge = chBoxV) then
      LineCh := chBoxV
    else if Edge = '|' then
      LineCh := '|'
    else
      Continue;
    for Y := R.Top to R.Bottom do
    begin
      Cell := AGrid[Y][R.Left];
      Cell.CharValue := LineCh;
      AGrid[Y][R.Left] := Cell;
    end;
    // A tee where the divider meets the frame's top edge and the rule under it.
    TopCh := AGrid[FBounds.Top][R.Left].CharValue;
    if TopCh = chDblH then
      TopCh := chDblHSingleHD
    else if TopCh = chBoxH then
      TopCh := chBoxHD
    else if TopCh = '-' then
      TopCh := '+'
    else
      TopCh := #0;
    if TopCh <> #0 then
    begin
      Cell := AGrid[FBounds.Top][R.Left];
      Cell.CharValue := TopCh;
      AGrid[FBounds.Top][R.Left] := Cell;
    end;
    BottomCh := AGrid[R.Bottom + 1][R.Left].CharValue;
    if BottomCh = chBoxH then
      BottomCh := chBoxHU
    else if BottomCh = '-' then
      BottomCh := '+'
    else
      BottomCh := #0;
    if BottomCh <> #0 then
    begin
      Cell := AGrid[R.Bottom + 1][R.Left];
      Cell.CharValue := BottomCh;
      AGrid[R.Bottom + 1][R.Left] := Cell;
    end;
  end;
end;

procedure TDialogHost.JoinSeparatorsToFrame(const AGrid: TTerminalGrid);
var
  I, X, Y: Integer;
  R: TRectI;
  Edge, LeftJoin, RightJoin, LineCh: Char;
  Cell: TCharCell;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    if I > High(FControlBounds) then
      Break;
    if (FDecl.Controls[I].Kind <> dckLabel) or
       not IsHRuleText(FDecl.Controls[I].Text) then
      Continue;
    R := FControlBounds[I];
    Y := R.Top;
    // Only a rule across the whole client area reaches the frame.
    if (R.Left <> FBounds.Left + 1) or (R.Right <> FBounds.Right - 1) or
       (Y <= FBounds.Top) or (Y >= FBounds.Bottom) or
       (Y < 0) or (Y > High(AGrid)) or (FBounds.Left < 0) or
       (FBounds.Right > High(AGrid[Y])) then
      Continue;
    // Match the frame the theme drew on this row.
    Edge := AGrid[Y][FBounds.Left].CharValue;
    if Edge = chDblV then
    begin
      LeftJoin := chDblVSingleHR;
      RightJoin := chDblVSingleHL;
      LineCh := chBoxH;
    end
    else if Edge = chBoxV then
    begin
      LeftJoin := chBoxVR;
      RightJoin := chBoxVL;
      LineCh := chBoxH;
    end
    else if Edge = '|' then
    begin
      LeftJoin := '+';
      RightJoin := '+';
      LineCh := '-';
    end
    else
      Continue;
    for X := R.Left to R.Right do
    begin
      Cell := AGrid[Y][X];
      Cell.CharValue := LineCh;
      AGrid[Y][X] := Cell;
    end;
    Cell := AGrid[Y][FBounds.Left];
    Cell.CharValue := LeftJoin;
    AGrid[Y][FBounds.Left] := Cell;
    Cell := AGrid[Y][FBounds.Right];
    Cell.CharValue := RightJoin;
    AGrid[Y][FBounds.Right] := Cell;
  end;
end;

function TDialogHost.ChromeContext: TFunctionBarContext;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if FDecl.Controls[I].Kind in [dckList, dckDropDown] then
      Exit(fbcDialogList);
  Result := fbcStubEdit;
end;

function TDialogHost.ContainsLocal(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := False;
  if not FVisible then
    Exit;
  EnsureLayout;
  Result := FBounds.Contains(ALocalCol, ALocalRow);
end;

function TDialogHost.ControlCount: Integer;
begin
  Result := Length(FDecl.Controls);
end;

function TDialogHost.GetControl(AIndex: Integer): TDialogControl;
begin
  Result := FDecl.Controls[AIndex];
end;

function TDialogHost.ControlBoundsAt(AIndex: Integer): TRectI;
begin
  EnsureLayout;
  if (AIndex >= 0) and (AIndex <= High(FControlBounds)) then
    Result := FControlBounds[AIndex]
  else
    Result := TRectI.Make(0, 0, -1, -1);
end;

function TDialogHost.ControlIndexAt(ALocalCol, ALocalRow: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  if not FVisible then
    Exit;
  EnsureLayout;
  for I := 0 to High(FDecl.Controls) do
  begin
    if I > High(FControlBounds) then
      Break;
    if FControlBounds[I].Contains(ALocalCol, ALocalRow) then
      Exit(I);
  end;
end;

function TDialogHost.FocusedOrDefaultButtonId: string;
var
  I, Def: Integer;
begin
  Result := '';
  if FocusedIsButton then
    Exit(FDecl.Controls[FFocusIndex].Id);
  Def := FindDefaultButtonIndex;
  if Def >= 0 then
    Exit(FDecl.Controls[Def].Id);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and
       DialogCmdIsAccept(FDecl.Controls[I].Id) then
      Exit(FDecl.Controls[I].Id);
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckButton) and not FDecl.Controls[I].IsCancel then
      Exit(FDecl.Controls[I].Id);
end;

function TDialogHost.FocusedControlId: string;
begin
  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) then
    Result := FDecl.Controls[FFocusIndex].Id
  else
    Result := '';
end;

procedure TDialogHost.ReportListSelection;
var
  I, J: Integer;
  Known: Boolean;
begin
  if not Assigned(FOnListSelected) then
    Exit;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckList) and (FDecl.Controls[I].Id <> '') then
    begin
      Known := False;
      for J := 0 to High(FListSeen) do
        if FListSeen[J].Key = FDecl.Controls[I].Id then
        begin
          Known := True;
          if FListSeen[J].Value <> FDecl.Controls[I].SelectedIndex then
          begin
            FListSeen[J].Value := FDecl.Controls[I].SelectedIndex;
            FOnListSelected(FDecl.Controls[I].Id);
          end;
          Break;
        end;
      if not Known then
      begin
        SetLength(FListSeen, Length(FListSeen) + 1);
        FListSeen[High(FListSeen)] := TPair<string, Integer>.Create(
          FDecl.Controls[I].Id, FDecl.Controls[I].SelectedIndex);
      end;
    end;
end;

function TDialogHost.HandleClick(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
begin
  Result := HandleClickCore(ALocalCol, ALocalRow, AShift);
  ReportListSelection;
end;

function TDialogHost.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := HandleInputCore(AKey, AShift, AKeyChar);
  ReportListSelection;
end;

function TDialogHost.ClickBounds: TRectI;
begin
  Result := FBounds;
end;

function TDialogHost.ClickControlBounds(AIndex: Integer): TRectI;
begin
  if (AIndex < 0) or (AIndex > High(FControlBounds)) then
    Result := TRectI.Make(-1, -1, -2, -2)
  else
    Result := FControlBounds[AIndex];
end;

function TDialogHost.ClickHasPressTimer: Boolean;
begin
  Result := Assigned(GDialogButtonPressStart);
end;

function TDialogHost.ClickHit(ACol, ARow: Integer): Integer;
begin
  Result := FClicks.Hit(ACol, ARow);
end;

procedure TDialogHost.ClickResetClicks;
begin
  FClicks.Reset;
end;

procedure TDialogHost.ClickBeginButtonCapture(AIndex, ALocalCol, ALocalRow: Integer);
begin
  // Pressed until the release; the command runs only if the
  // release is over this button (DialogButtonCaptureRelease).
  DropPress;
  FMouseIndex := AIndex;
  FPressIndex := AIndex;
  GCaptureHost := Self;
  GCaptureDX := GMouseDownCol - ALocalCol;
  GCaptureDY := GMouseDownRow - ALocalRow;
  NotifyChanged;
end;

procedure TDialogHost.ClickBeginInputDrag(AIndex, ALocalCol, ALocalRow: Integer);
begin
  DropPress;
  FDragInput := AIndex;
  GCaptureHost := Self;
  GCaptureDX := GMouseDownCol - ALocalCol;
  GCaptureDY := GMouseDownRow - ALocalRow;
end;

procedure TDialogHost.ClickApplyInputClick(AIndex, ALocalCol, ALocalRow: Integer;
  AExtend: Boolean; AClicks: Integer);
var
  R: TRectI;
begin
  if (AIndex < 0) or (AIndex > High(FDecl.Controls)) or
     (AIndex > High(FControlBounds)) then
    Exit;
  R := FControlBounds[AIndex];
  InputLineMouseClick(FDecl.Controls[AIndex].Edit, ALocalCol - R.Left, AClicks, AExtend);
end;

function TDialogHost.ClickDropScrollTop: Integer;
begin
  Result := FDropScrollTop;
end;

function TDialogHost.ClickListScrollTop: Integer;
begin
  Result := FListScrollTop;
end;

function TDialogHost.ClickListSelectedIndexOf(const AId: string): Integer;
begin
  Result := ListSelectedIndexOf(AId);
end;

function TDialogHost.BuildClickOps: TDialogClickOps;
begin
  Result.Visible := Visible;
  Result.EnsureLayout := EnsureLayout;
  Result.NotifyChanged := NotifyChanged;
  Result.FireAccept := FireAccept;
  Result.FireCancel := FireCancel;
  Result.FireCommand := FireCommand;
  Result.CloseDropDown := CloseDropDown;
  Result.CommitDropDown := KeyCommitDropDown;
  Result.OpenDropDown := OpenDropDown;
  Result.EnsureDropHoverInView := EnsureDropHoverInView;
  Result.IsHistoryInput := IsHistoryInput;
  Result.SelectRadio := SelectRadio;
  Result.EnsureListInView := EnsureListInView;
  Result.SetListSelectedIndex := SetListSelectedIndex;
  Result.ListSelectedIndexOf := ClickListSelectedIndexOf;
  Result.DropPress := DropPress;
  Result.HasPressTimer := ClickHasPressTimer;
  Result.ClickHit := ClickHit;
  Result.ResetClicks := ClickResetClicks;
  Result.BeginButtonCapture := ClickBeginButtonCapture;
  Result.BeginInputDrag := ClickBeginInputDrag;
  Result.ApplyInputClick := ClickApplyInputClick;
  Result.Bounds := ClickBounds;
  Result.ControlBounds := ClickControlBounds;
  Result.DropPopupBounds := DropPopupBounds;
  Result.DropContentBounds := DropContentBounds;
  Result.FocusIndex := KeyFocusIndex;
  Result.SetFocusIndex := KeySetFocusIndex;
  Result.DropOpenIndex := KeyDropOpenIndex;
  Result.DropHover := KeyDropHover;
  Result.SetDropHover := KeySetDropHover;
  Result.DropScrollTop := ClickDropScrollTop;
  Result.ListScrollTop := ClickListScrollTop;
  Result.ControlCount := KeyControlCount;
  Result.GetControl := GetControl;
  Result.SetControl := KeySetControl;
  Result.SelectTab := SelectTab;
end;

function TDialogHost.HandleClickCore(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
begin
  Result := DialogHandleClickCore(BuildClickOps, ALocalCol, ALocalRow, AShift);
end;

function TDialogHost.KeyCursorVisible: Boolean;
begin
  Result := FCursorVisible;
end;

procedure TDialogHost.KeyShowCursor;
begin
  FCursorVisible := True;
  NotifyChanged;
end;

procedure TDialogHost.KeyCommitDropDown;
begin
  CommitDropDown;
end;

function TDialogHost.KeyFocusIndex: Integer;
begin
  Result := FFocusIndex;
end;

procedure TDialogHost.KeySetFocusIndex(AValue: Integer);
begin
  FFocusIndex := AValue;
end;

function TDialogHost.KeyDropOpenIndex: Integer;
begin
  Result := FDropOpenIndex;
end;

function TDialogHost.KeyDropHover: Integer;
begin
  Result := FDropHover;
end;

procedure TDialogHost.KeySetDropHover(AValue: Integer);
begin
  FDropHover := AValue;
end;

function TDialogHost.KeyControlCount: Integer;
begin
  Result := Length(FDecl.Controls);
end;

procedure TDialogHost.KeySetControl(AIndex: Integer; const AControl: TDialogControl);
begin
  if (AIndex >= 0) and (AIndex <= High(FDecl.Controls)) then
    FDecl.Controls[AIndex] := AControl;
end;

function TDialogHost.BuildKeyOps: TDialogKeyOps;
begin
  Result.Visible := Visible;
  Result.CursorVisible := KeyCursorVisible;
  Result.ShowCursor := KeyShowCursor;
  Result.NotifyChanged := NotifyChanged;
  Result.FireAccept := FireAccept;
  Result.FireCancel := FireCancel;
  Result.FireCommand := FireCommand;
  Result.PressButton := PressButton;
  Result.SelectRadio := SelectRadio;
  Result.CommitDropDown := KeyCommitDropDown;
  Result.CloseDropDown := CloseDropDown;
  Result.OpenDropDown := OpenDropDown;
  Result.IsHistoryInput := IsHistoryInput;
  Result.RemoveDropHoverFromHistory := RemoveDropHoverFromHistory;
  Result.EnsureDropHoverInView := EnsureDropHoverInView;
  Result.NormalizeAcceptKey := NormalizeAcceptKey;
  Result.NextFocusable := NextFocusable;
  Result.FocusedIsInput := FocusedIsInput;
  Result.TryYesNoButton := TryYesNoButton;
  Result.TryMnemonic := TryMnemonic;
  Result.ButtonIndexById := ButtonIndexById;
  Result.SetListSelectedIndex := SetListSelectedIndex;
  Result.ListViewHeight := ListViewHeight;
  Result.FocusIndex := KeyFocusIndex;
  Result.SetFocusIndex := KeySetFocusIndex;
  Result.DropOpenIndex := KeyDropOpenIndex;
  Result.DropHover := KeyDropHover;
  Result.SetDropHover := KeySetDropHover;
  Result.DropPopupViewHeight := DropPopupViewHeight;
  Result.ControlCount := KeyControlCount;
  Result.GetControl := GetControl;
  Result.SetControl := KeySetControl;
  Result.SelectTab := SelectTab;
end;

function TDialogHost.TryYesNoButton(AYes: Boolean): Boolean;
var
  I: Integer;
  C: TDialogControl;
begin
  for I := 0 to High(FDecl.Controls) do
  begin
    C := FDecl.Controls[I];
    if (C.Kind = dckButton) and
       ((AYes and DialogCmdIsYes(C.Id)) or (not AYes and DialogCmdIsNo(C.Id))) then
    begin
      PressButton(I);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDialogHost.TryMnemonic(ACh: Char): Boolean;
var
  I, Item: Integer;
  C: TDialogControl;
begin
  if ACh = #0 then
    Exit(False);
  Result := True;
  for I := 0 to High(FDecl.Controls) do
  begin
    C := FDecl.Controls[I];
    if not (C.Kind in [dckButton, dckCheckbox, dckRadio]) or
       ((C.Kind = dckCheckbox) and C.Disabled) or
       (HotKeyCharOf(C.Text) <> ACh) then
      Continue;
    if DialogControlHiddenByTab(FDecl.Controls, I) then
    begin
      Item := DialogTabItemOfPage(FDecl.Controls[DialogTabStripIndex(FDecl.Controls)],
        C.TabPage);
      if Item < 0 then
        Continue;
      FDecl.Controls[DialogTabStripIndex(FDecl.Controls)].SelectedIndex := Item;
      FScrollFollow := -1;
    end;
    FFocusIndex := I;
    case C.Kind of
      dckButton:
        PressButton(I);
      dckCheckbox:
        begin
          DialogToggleCheckbox(FDecl.Controls[I]);
          NotifyChanged;
        end;
      dckRadio:
        begin
          SelectRadio(I);
          NotifyChanged;
        end;
    end;
    Exit;
  end;
  Result := False;
end;

function TDialogHost.HandleInputCore(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := DialogHandleInputCore(BuildKeyOps, AKey, AShift, AKeyChar);
end;

end.
