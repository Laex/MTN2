unit uDialogHost;

{ Host-built declarative dialogs (DIALOG_PLUGIN). Draws via IThemeRenderer;
  inputs use TInputLine. In-process - cdecl export comes with DLL stage. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.StrUtils,
  System.Generics.Collections, uTerminalTypes, uThemeTypes, uThemeDrawing, uDialogTypes, uDialogJson, uDialogRenderer,
  uInputLine, uFunctionBar, uColorCoding, uDialogHistory, uColorPickerControl, uDatePickerControl;

type
  TDialogHost = class
  private
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
    function FirstFocusable: Integer;
    function NextFocusable(AFrom: Integer; AForward: Boolean): Integer;
    /// <summary>Joins full-width separator rules to the dialog frame:
    /// ╟─╢ on a double frame, ├─┤ on a single one, +-+ on an ASCII one.</summary>
    procedure JoinSeparatorsToFrame(const AGrid: TTerminalGrid);
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
    /// <summary>Protocol 1 lays controls out in order. Buttons share a row
    /// until one would pass the right edge, then wrap. Anything else takes
    /// the whole width and starts a new row after a button row.</summary>
    procedure LayoutFlowControls;
    /// <summary>One button in the protocol-1 row. A button that would pass
    /// the right edge wraps onto the next row.</summary>
    procedure PlaceFlowButton(AIndex: Integer; const C: TDialogControl;
      AInnerLeft, AInnerRight: Integer; var AY, ABtnX: Integer;
      var AInButtonRow: Boolean);
    /// <summary>A non-button in the protocol-1 flow. It ends a button row,
    /// and a list or radio group takes ControlRowSpan rows.</summary>
    procedure PlaceFlowBlock(AIndex: Integer; const C: TDialogControl;
      AInnerLeft, AInnerRight: Integer; var AY, ABtnX: Integer;
      var AInButtonRow: Boolean);
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
    /// <summary>The frame's close mark and a click outside the dialog both
    /// cancel it. False when the click is inside, so a control can take it.</summary>
    function HandleDialogFrameClick(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>A click while a DropDown popup is open. A click on the popup
    /// or its field is consumed. A click elsewhere closes the popup and
    /// returns False, so the control under the pointer still receives it.
    /// False when no popup is open.</summary>
    function HandleOpenDropDownClick(ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>A click on an input. The last cell of a color, date or history
    /// field opens that popup. A disabled field takes the click and does not
    /// move the caret. The edit line is the live control, not the copy.</summary>
    procedure HandleInputClick(AIndex: Integer; const R: TRectI;
      const C: TDialogControl; ALocalCol, ALocalRow: Integer;
      AShift: TShiftState);
    /// <summary>A click on a list. The right column of a multi-line list is
    /// its scrollbar. A double click on a row accepts the dialog. False when
    /// the point is not a row, so a later control under it can still take
    /// the click.</summary>
    function HandleListClick(AIndex: Integer; const R: TRectI;
      const C: TDialogControl; ALocalCol, ALocalRow: Integer): Boolean;
    /// <summary>A click on a radio-group row. The caption row is not a
    /// choice. False when the point is not an item, so a later control under
    /// it can still take the click.</summary>
    function HandleRadioGroupClick(AIndex: Integer; const R: TRectI;
      const C: TDialogControl; ALocalRow: Integer): Boolean;
    /// <summary>A click on a button. With mouse capture the command waits
    /// for the release and runs only if the pointer is still over it.</summary>
    procedure HandleButtonClick(AIndex: Integer; const C: TDialogControl;
      ALocalCol, ALocalRow: Integer);
    /// <summary>A click toggles a checkbox. A disabled one takes the click
    /// and stays as it is.</summary>
    procedure HandleCheckboxClick(AIndex: Integer);
    /// <summary>A click selects a radio button.</summary>
    procedure HandleRadioClick(AIndex: Integer);
    /// <summary>A click opens a DropDown, or closes it when it is already
    /// open. A disabled one takes the click and stays closed.</summary>
    procedure HandleDropDownFieldClick(AIndex: Integer; const C: TDialogControl);
    /// <summary>A click on a calendar, in the control's own cells.</summary>
    procedure HandleDatePickerClick(AIndex: Integer; const R: TRectI;
      ALocalCol, ALocalRow: Integer);
    /// <summary>A click on a color picker. The click count is passed through,
    /// so a double click inside the picker is not lost.</summary>
    procedure HandleColorPickerClick(AIndex: Integer; const R: TRectI;
      ALocalCol, ALocalRow: Integer);
    function HandleClickCore(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState): Boolean;
    /// <summary>Keys while a DropDown popup is open. Enter and Space commit
    /// the row, Esc and Tab collapse the popup without cancelling the dialog,
    /// Del forgets a history row, arrows move the highlight. Any other key is
    /// consumed too, so it cannot accept or cancel the dialog behind the
    /// popup. False when no popup is open; the key is left unchanged.</summary>
    function HandleOpenDropDownKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Enter accepts the dialog, Esc cancels it, Tab moves focus.
    /// False for every other key, so the focused control still receives it.</summary>
    function HandleDialogNavKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Opens a collapsed history field (Ctrl+Down, Alt+Down) or a
    /// collapsed DropDown (F4, Alt+Down, Space). False when the key does not
    /// open one; the key is left unchanged, so Space on a list still toggles
    /// a row and a letter still reaches a mnemonic.</summary>
    function HandleClosedDropDownKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Space toggles the focused checkbox, selects a radio button,
    /// keeps a radio group's current item and presses a button. False for any
    /// other key or control; the key is left unchanged.</summary>
    function HandleFocusedSpaceKey(var AKey: Word; var AKeyChar: Char): Boolean;
    /// <summary>Yes/No buttons and caption mnemonics. They run for Alt, and
    /// for any key while focus is not in an input. False when nothing
    /// matches; the key is left unchanged, so a list, picker or input still
    /// receives it.</summary>
    function HandleMnemonicKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>A focused date or color picker takes the key. False for every
    /// other control; the key is left unchanged.</summary>
    function HandleFocusedPickerKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Space, Ctrl+Up and Ctrl+Down on a list with key commands fire
    /// toggle, up and down. Plain Del presses the dialog's Delete button when
    /// it has one. False when the list does not take the key; the key is left
    /// unchanged, so arrows can still move the selection.</summary>
    function HandleListCommandKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Up, Down, Home, End, PageUp and PageDown move the selection
    /// of a focused list, radio group or DropDown. The key is taken even when
    /// the control has no items: otherwise Up and Down would also move the
    /// dialog focus. False for every other key or control.</summary>
    function HandleListNavKeys(var AKey: Word): Boolean;
    /// <summary>The focused input takes the key. A password field drops
    /// copy-out, a read-only field drops edits, Enter accepts and Esc cancels.
    /// False when focus is not an input; the key is left unchanged, so arrows
    /// can still move the dialog focus.</summary>
    function HandleFocusedInputKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>Left, Right, Up and Down move the dialog focus when no
    /// control has taken them. False for every other key.</summary>
    function HandleFocusArrowKeys(var AKey: Word): Boolean;
    function HandleInputCore(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
  public
    constructor Create(const ATheme: IThemeRenderer);
    destructor Destroy; override;
    procedure Open(const ADecl: TDialogDeclaration; AOnCommand: TDialogCommandEvent);
    /// <summary>DIALOG_PLUGIN JSON subset. Returns False if parse fails (no open).</summary>
    function OpenJson(const ADeclJson: string; AOnCommand: TDialogCommandEvent): Boolean;
    procedure Close;
    function Visible: Boolean;
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
    function GetCheckbox(const AId: string): Boolean;
    /// <summary>Sets a dckCheckbox of the open dialog; no-op for other ids.</summary>
    procedure SetCheckbox(const AId: string; AChecked: Boolean);
    /// <summary>Greys out (or restores) a checkbox, input or drop-down of the
    /// open dialog: it is skipped by the focus and ignores clicks. A focused
    /// control that gets disabled hands the focus to the next one.</summary>
    procedure SetControlDisabled(const AId: string; ADisabled: Boolean);
    function GetRadio(const AGroupId: string): string;
    function GetListSelectedIndex(const AId: string): Integer;
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
  System.Character, uKeyChord, uDialogLocaleLayout, uCharWidth,
  uDialogValues, uDialogV2Layout, uDialogListDraw;

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

type
  TDialogYesNoAnswer = (dyaNone, dyaYes, dyaNo);

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

function TDialogHost.CanFocus(AIndex: Integer): Boolean;
begin
  Result := (FDecl.Controls[AIndex].Kind in [dckInput, dckCheckbox, dckRadio,
    dckRadioGroup, dckButton, dckList, dckDropDown, dckColorPicker, dckDatePicker]) and
    not ((FDecl.Controls[AIndex].Kind in [dckCheckbox, dckInput, dckDropDown]) and
      FDecl.Controls[AIndex].Disabled);
end;

function TDialogHost.FirstFocusable: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if CanFocus(I) then
      Exit(I);
  Result := -1;
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
  I: Integer;
begin
  for I := 0 to High(FDecl.Controls) do
    if SameText(FDecl.Controls[I].Id, AId) then
    begin
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

procedure TDialogHost.RemoveDropHoverFromHistory;
var
  C: TDialogControl;
begin
  if not IsHistoryInput(FDropOpenIndex) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  if (FDropHover < 0) or (FDropHover > High(C.Items)) then
    Exit;
  DialogHistoryRemove(C.History, C.Items[FDropHover]);
  FDecl.Controls[FDropOpenIndex].Items := DialogHistoryItems(C.History);
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
var
  I: Integer;
begin
  if (AControlIndex < 0) or (AControlIndex > High(FDecl.Controls)) then
    Exit;
  if (FDecl.Controls[AControlIndex].Kind <> dckDropDown) and
     not IsHistoryInput(AControlIndex) then
    Exit;
  if Length(FDecl.Controls[AControlIndex].Items) = 0 then
    Exit;
  FFocusIndex := AControlIndex;
  FDropOpenIndex := AControlIndex;
  FDropScrollTop := 0;
  if IsHistoryInput(AControlIndex) then
  begin
    // Start on the entry the field already holds, else the newest.
    FDropHover := 0;
    for I := 0 to High(FDecl.Controls[AControlIndex].Items) do
      if SameText(FDecl.Controls[AControlIndex].Items[I],
         FDecl.Controls[AControlIndex].Edit.Text) then
      begin
        FDropHover := I;
        Break;
      end;
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
begin
  Result := False;
  if FDropOpenIndex < 0 then
    Exit;
  if IsHistoryInput(FDropOpenIndex) then
  begin
    if (FDropHover >= 0) and (FDropHover <= High(FDecl.Controls[FDropOpenIndex].Items)) then
      InputLineSetText(FDecl.Controls[FDropOpenIndex].Edit,
        FDecl.Controls[FDropOpenIndex].Items[FDropHover]);
  end
  else
    SetListSelectedIndex(FDropOpenIndex, FDropHover);
  FDropOpenIndex := -1;
  FDropHover := 0;
  FDropScrollTop := 0;
  NotifyChanged;
  Result := True;
end;

function TDialogHost.DropPopupBounds(out ARect: TRectI): Boolean;
var
  R: TRectI;
  N, ItemH, FrameH, SpaceBelow, SpaceAbove: Integer;
  ClientTop, ClientBottom: Integer;
  OpenBelow, CanBelow, CanAbove, FitsBelow, FitsAbove: Boolean;
begin
  Result := False;
  if (FDropOpenIndex < 0) or (FDropOpenIndex > High(FControlBounds)) then
    Exit;
  R := FControlBounds[FDropOpenIndex];
  N := Length(FDecl.Controls[FDropOpenIndex].Items);
  if N < 1 then
    Exit;
  ClientTop := FBounds.Top + 1;
  ClientBottom := FBounds.Bottom - 1;
  SpaceBelow := ClientBottom - (R.Bottom + 1) + 1;
  SpaceAbove := R.Top - 1 - ClientTop + 1;
  CanBelow := SpaceBelow >= 3;
  CanAbove := SpaceAbove >= 3;
  FitsBelow := SpaceBelow >= N + 2;
  FitsAbove := SpaceAbove >= N + 2;
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
  // Outer rect includes a single-line box frame (visible items + 2).
  if OpenBelow then
  begin
    ItemH := Min(N, Max(SpaceBelow - 2, 1));
    FrameH := ItemH + 2;
    ARect := TRectI.Make(R.Left, R.Bottom + 1, R.Right, R.Bottom + FrameH);
  end
  else
  begin
    ItemH := Min(N, Max(SpaceAbove - 2, 1));
    FrameH := ItemH + 2;
    ARect := TRectI.Make(R.Left, R.Top - FrameH, R.Right, R.Top - 1);
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
  Result := (ARect.Height >= 3) and (ARect.Width >= 3);
end;

function TDialogHost.DropPopupViewHeight: Integer;
var
  Frame: TRectI;
begin
  Result := 0;
  if DropPopupBounds(Frame) then
    Result := Max(Frame.Height - 2, 0);
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

procedure TDialogHost.DrawDropDownPopup(const AGrid: TTerminalGrid);
var
  Frame, Content: TRectI;
  C: TDialogControl;
  J, Idx, ViewH, Count, TextW: Integer;
  Line: string;
  RowFg, RowBg, FrameFg, FrameBg: TAlphaColor;
  NeedBar: Boolean;
begin
  if not DropPopupBounds(Frame) then
    Exit;
  EnsureDropHoverInView;
  Content := TRectI.Make(Frame.Left + 1, Frame.Top + 1,
    Frame.Right - 1, Frame.Bottom - 1);
  if (Content.Right < Content.Left) or (Content.Bottom < Content.Top) then
    Exit;
  C := FDecl.Controls[FDropOpenIndex];
  ViewH := Content.Height;
  Count := Length(C.Items);
  NeedBar := Count > ViewH;
  TextW := Content.Width;
  if NeedBar then
    TextW := Max(Content.Width - 1, 1);
  // Same chrome as Sort/Column overlay menus: white body, black frame.
  FrameFg := TAlphaColor($FF000000);
  FrameBg := TAlphaColor($FFFFFFFF);

  DrawPanelFrameGlyphs(AGrid, Frame, chBoxTL, chBoxTR, chBoxBL, chBoxBR, chBoxH, chBoxV,
    FrameFg, FrameFg, FrameBg);

  for J := 0 to ViewH - 1 do
  begin
    Idx := FDropScrollTop + J;
    if (Idx < 0) or (Idx > High(C.Items)) then
      Line := ''
    else
      Line := C.Items[Idx];
    Line := PadGridLine(Line, Max(TextW, 1));
    ResolveRowHighlight(Idx = FDropHover, FrameFg, FrameBg, RowFg, RowBg);
    PutGridText(AGrid, Content.Left, Content.Top + J, Line, RowFg, RowBg);
  end;
  if NeedBar then
    DrawDialogScrollBar(AGrid, Content.Right, Content.Top, Content.Bottom,
      FDropScrollTop, Count, ViewH);
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

function TDialogHost.GetCheckbox(const AId: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FDecl.Controls) do
    if (FDecl.Controls[I].Kind = dckCheckbox) and SameText(FDecl.Controls[I].Id, AId) then
      Exit(FDecl.Controls[I].Checked);
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

procedure TDialogHost.PlaceFlowButton(AIndex: Integer; const C: TDialogControl;
  AInnerLeft, AInnerRight: Integer; var AY, ABtnX: Integer;
  var AInButtonRow: Boolean);
var
  BtnW: Integer;
begin
  BtnW := ButtonCellWidth(C);
  if not AInButtonRow then
  begin
    AInButtonRow := True;
    ABtnX := AInnerLeft;
  end
  else if (ABtnX > AInnerLeft) and (ABtnX + BtnW - 1 > AInnerRight) then
  begin
    // Wrap overflowing buttons onto the next row.
    Inc(AY);
    ABtnX := AInnerLeft;
  end;
  FControlBounds[AIndex] := TRectI.Make(ABtnX, AY,
    Min(ABtnX + BtnW - 1, AInnerRight), AY);
  Inc(ABtnX, BtnW + 2);
end;

procedure TDialogHost.PlaceFlowBlock(AIndex: Integer; const C: TDialogControl;
  AInnerLeft, AInnerRight: Integer; var AY, ABtnX: Integer;
  var AInButtonRow: Boolean);
var
  Span: Integer;
begin
  if AInButtonRow then
  begin
    Inc(AY);
    AInButtonRow := False;
    ABtnX := AInnerLeft;
  end;
  // A list and a radio group both occupy ControlRowSpan rows.
  if C.Kind in [dckList, dckRadioGroup] then
  begin
    Span := ControlRowSpan(C);
    FControlBounds[AIndex] := TRectI.Make(AInnerLeft, AY, AInnerRight, AY + Span - 1);
    Inc(AY, Span);
  end
  else
  begin
    FControlBounds[AIndex] := TRectI.Make(AInnerLeft, AY, AInnerRight, AY);
    Inc(AY);
  end;
end;

procedure TDialogHost.LayoutFlowControls;
var
  I, Y, BtnX, InnerLeft, InnerRight: Integer;
  InButtonRow: Boolean;
  C: TDialogControl;
begin
  // Protocol 1.0: sequential flow layout.
  InnerLeft := FBounds.Left + 2;
  InnerRight := FBounds.Right - 2;
  if InnerRight < InnerLeft then
    InnerRight := InnerLeft;
  Y := FBounds.Top + 2;
  BtnX := InnerLeft;
  InButtonRow := False;

  for I := 0 to High(FDecl.Controls) do
  begin
    C := FDecl.Controls[I];
    if C.Kind = dckButton then
      PlaceFlowButton(I, C, InnerLeft, InnerRight, Y, BtnX, InButtonRow)
    else
      PlaceFlowBlock(I, C, InnerLeft, InnerRight, Y, BtnX, InButtonRow);
  end;
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

procedure TDialogHost.DrawCheckboxControl(const AGrid: TTerminalGrid; const R: TRectI;
  AIndex: Integer; const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
var
  St: TThemeWidgetState;
  ItemFg, ItemBg, HotFg: TAlphaColor;
  HotAttr: TCharCellAttributes;
begin
  if C.Disabled then
  begin
    PutGridText(AGrid, R.Left, R.Top,
      Copy(IfThen(C.Checked, '[x] ', '[ ] ') + StripHotKeyMarker(C.Text), 1, Max(R.Width, 1)),
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
      IfThen(C.Checked, '[x] ', '[ ] ') + C.Text,
      ItemFg, ItemBg, HotFg, [], HotAttr);
  end
  else
  begin
    St := [];
    if AIndex = FFocusIndex then
      Include(St, twFocused);
    FTheme.DrawCheckBox(AGrid, R, C.Text, C.Checked, St);
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

procedure TDialogHost.DrawLabelControl(const AGrid: TTerminalGrid; const R: TRectI;
  const C: TDialogControl; ALabelFg, ALabelBg: TAlphaColor);
begin
  if (C.Kind = dckLabel) and C.Accent then
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
    end;
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
  DrawButtonShadows(AGrid);
  DrawDropDownPopup(AGrid);
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

function TDialogHost.HandleDialogFrameClick(ALocalCol, ALocalRow: Integer): Boolean;
begin
  if WindowFrameCloseHit(FBounds, ALocalCol, ALocalRow) then
  begin
    CloseDropDown;
    FireCancel;
    Exit(True);
  end;
  if not FBounds.Contains(ALocalCol, ALocalRow) then
  begin
    CloseDropDown;
    // Outside click = Cancel when a cancel button exists.
    FireCancel;
    Exit(True);
  end;
  Result := False;
end;

function TDialogHost.HandleOpenDropDownClick(ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Idx, Count, ViewH: Integer;
  Popup: TRectI;
  NeedBar: Boolean;
begin
  Result := False;
  if (FDropOpenIndex < 0) or not DropPopupBounds(Popup) then
    Exit;

  // DropDown popup takes priority while open.
  if Popup.Contains(ALocalCol, ALocalRow) then
  begin
    EnsureDropHoverInView;
    Row := ALocalRow - (Popup.Top + 1);
    ViewH := Popup.Height - 2;
    Count := Length(FDecl.Controls[FDropOpenIndex].Items);
    NeedBar := Count > ViewH;
    if NeedBar and (ALocalCol = Popup.Right - 1) and (ViewH > 0) then
    begin
      if ALocalRow = Popup.Top + 1 then
        FDropHover := EnsureRange(FDropHover - 1, 0, Count - 1)
      else if ALocalRow = Popup.Bottom - 1 then
        FDropHover := EnsureRange(FDropHover + 1, 0, Count - 1)
      else
        FDropHover := EnsureRange(
          Round((ALocalRow - Popup.Top - 2) * (Count - 1) / Max(ViewH - 3, 1)),
          0, Count - 1);
      EnsureDropHoverInView;
      NotifyChanged;
      Exit(True);
    end;
    if (ALocalCol > Popup.Left) and
       ((not NeedBar and (ALocalCol < Popup.Right)) or
        (NeedBar and (ALocalCol < Popup.Right - 1))) and
       (Row >= 0) and (Row < ViewH) then
    begin
      Idx := FDropScrollTop + Row;
      if (Idx >= 0) and (Idx <= High(FDecl.Controls[FDropOpenIndex].Items)) then
      begin
        FDropHover := Idx;
        CommitDropDown;
      end;
      Exit(True);
    end;
    Exit(True);
  end;
  // Click outside popup collapses without changing selection.
  if (FDropOpenIndex <= High(FControlBounds)) and
     FControlBounds[FDropOpenIndex].Contains(ALocalCol, ALocalRow) then
  begin
    CloseDropDown;
    Exit(True);
  end;
  CloseDropDown;
  // The control under the pointer still receives this click.
end;

procedure TDialogHost.HandleInputClick(AIndex: Integer; const R: TRectI;
  const C: TDialogControl; ALocalCol, ALocalRow: Integer;
  AShift: TShiftState);
var
  Clicks: Integer;
begin
  if C.Disabled then
    Exit;
  FFocusIndex := AIndex;
  if (C.ColorPick or C.DatePick) and (R.Width >= 3) and
     (ALocalCol = R.Left + R.Width - 1) then
  begin
    NotifyChanged;
    FireCommand(DialogPickCommand(C.Id));
    Exit;
  end;
  if IsHistoryInput(AIndex) and (R.Width >= 3) and
     (ALocalCol = R.Left + R.Width - 1) then
  begin
    OpenDropDown(AIndex);
    NotifyChanged;
    Exit;
  end;
  // Caret to the clicked cell; double click = word, triple = all;
  // Shift+click extends the selection from the current caret.
  if ssShift in AShift then
  begin
    FClicks.Reset;
    InputLineMouseClick(FDecl.Controls[AIndex].Edit, ALocalCol - R.Left, 1, True);
  end
  else
  begin
    Clicks := FClicks.Hit(ALocalCol, ALocalRow);
    InputLineMouseClick(FDecl.Controls[AIndex].Edit, ALocalCol - R.Left, Clicks);
    // A single press starts a drag selection, finished on the release.
    if (Clicks = 1) and Assigned(GDialogButtonPressStart) then
    begin
      DropPress;
      FDragInput := AIndex;
      GCaptureHost := Self;
      GCaptureDX := GMouseDownCol - ALocalCol;
      GCaptureDY := GMouseDownRow - ALocalRow;
    end;
  end;
  NotifyChanged;
end;

function TDialogHost.HandleListClick(AIndex: Integer; const R: TRectI;
  const C: TDialogControl; ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Idx, Count, Span, Clicks: Integer;
begin
  Span := R.Height;
  if (Span > 1) and (ALocalCol = R.Right) then
  begin
    // Scrollbar: ▲ / ▼ / track -> move selection.
    FFocusIndex := AIndex;
    EnsureListInView(AIndex);
    Count := Length(FDecl.Controls[AIndex].Items);
    if Count = 0 then
      Exit(True);
    if ALocalRow = R.Top then
      SetListSelectedIndex(AIndex, ListSelectedIndexOf(C.Id) - 1)
    else if ALocalRow = R.Bottom then
      SetListSelectedIndex(AIndex, ListSelectedIndexOf(C.Id) + 1)
    else if Count > Span then
      SetListSelectedIndex(AIndex,
        EnsureRange(Round((ALocalRow - R.Top - 1) * (Count - 1) /
          Max(Span - 3, 1)), 0, Count - 1))
    else
      SetListSelectedIndex(AIndex, 0);
    NotifyChanged;
    Exit(True);
  end;
  Row := ALocalRow - R.Top;
  if Span > 1 then
  begin
    EnsureListInView(AIndex);
    Idx := FListScrollTop + Row;
  end
  else
    Idx := Row;
  if (Row >= 0) and (Row < Span) and (Idx >= 0) and
     (Idx <= High(FDecl.Controls[AIndex].Items)) then
  begin
    FFocusIndex := AIndex;
    SetListSelectedIndex(AIndex, Idx);
    Clicks := FClicks.Hit(ALocalCol, ALocalRow);
    NotifyChanged;
    // A double click on a row is Enter on it.
    if Clicks = 2 then
      FireAccept;
    Exit(True);
  end;
  Result := False;
end;

function TDialogHost.HandleRadioGroupClick(AIndex: Integer; const R: TRectI;
  const C: TDialogControl; ALocalRow: Integer): Boolean;
var
  Row: Integer;
begin
  Row := ALocalRow - R.Top;
  if C.Text <> '' then
    Dec(Row);
  if (Row >= 0) and (Row <= High(FDecl.Controls[AIndex].Items)) then
  begin
    FFocusIndex := AIndex;
    SetListSelectedIndex(AIndex, Row);
    NotifyChanged;
    Exit(True);
  end;
  Result := False;
end;

procedure TDialogHost.HandleButtonClick(AIndex: Integer; const C: TDialogControl;
  ALocalCol, ALocalRow: Integer);
begin
  FFocusIndex := AIndex;
  if Assigned(GDialogButtonPressStart) then
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
  end
  else
    FireCommand(C.Id);
end;

procedure TDialogHost.HandleCheckboxClick(AIndex: Integer);
begin
  if FDecl.Controls[AIndex].Disabled then
    Exit;
  FFocusIndex := AIndex;
  FDecl.Controls[AIndex].Checked := not FDecl.Controls[AIndex].Checked;
  NotifyChanged;
end;

procedure TDialogHost.HandleRadioClick(AIndex: Integer);
begin
  FFocusIndex := AIndex;
  SelectRadio(AIndex);
  NotifyChanged;
end;

procedure TDialogHost.HandleDropDownFieldClick(AIndex: Integer;
  const C: TDialogControl);
begin
  if C.Disabled then
    Exit;
  FFocusIndex := AIndex;
  if FDropOpenIndex = AIndex then
    CloseDropDown
  else
    OpenDropDown(AIndex);
end;

procedure TDialogHost.HandleDatePickerClick(AIndex: Integer; const R: TRectI;
  ALocalCol, ALocalRow: Integer);
begin
  FFocusIndex := AIndex;
  DatePickerClick(FDecl.Controls[AIndex].Cal, ALocalCol - R.Left, ALocalRow - R.Top);
  NotifyChanged;
end;

procedure TDialogHost.HandleColorPickerClick(AIndex: Integer; const R: TRectI;
  ALocalCol, ALocalRow: Integer);
begin
  FFocusIndex := AIndex;
  ColorPickerClick(FDecl.Controls[AIndex].Picker, ALocalCol - R.Left,
    ALocalRow - R.Top, FClicks.Hit(ALocalCol, ALocalRow));
  NotifyChanged;
end;

function TDialogHost.HandleClickCore(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  I: Integer;
  C: TDialogControl;
  R: TRectI;
begin
  Result := False;
  if not FVisible then
    Exit;
  // Hit-test must use current layout even if Draw has not run yet this frame.
  EnsureLayout;
  if HandleDialogFrameClick(ALocalCol, ALocalRow) then
    Exit(True);
  if HandleOpenDropDownClick(ALocalCol, ALocalRow) then
    Exit(True);

  for I := 0 to High(FDecl.Controls) do
  begin
    if I > High(FControlBounds) then
      Break;
    R := FControlBounds[I];
    if not R.Contains(ALocalCol, ALocalRow) then
      Continue;
    C := FDecl.Controls[I];
    case C.Kind of
      dckButton:
        begin
          HandleButtonClick(I, C, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckCheckbox:
        begin
          HandleCheckboxClick(I);
          Exit(True);
        end;
      dckRadio:
        begin
          HandleRadioClick(I);
          Exit(True);
        end;
      dckInput:
        begin
          HandleInputClick(I, R, C, ALocalCol, ALocalRow, AShift);
          Exit(True);
        end;
      dckDropDown:
        begin
          HandleDropDownFieldClick(I, C);
          Exit(True);
        end;
      dckDatePicker:
        begin
          HandleDatePickerClick(I, R, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckColorPicker:
        begin
          HandleColorPickerClick(I, R, ALocalCol, ALocalRow);
          Exit(True);
        end;
      dckList:
        if HandleListClick(I, R, C, ALocalCol, ALocalRow) then
          Exit(True);
      dckRadioGroup:
        if HandleRadioGroupClick(I, R, C, ALocalRow) then
          Exit(True);
    end;
  end;
  Result := True;
end;

function DialogYesNoAnswer(AKey: Word; AKeyChar: Char): TDialogYesNoAnswer;
begin
  // By meaning first: y / д (Да) = Yes, n / н (Нет) = No, in any case. Then
  // the physical key, for any other layout (the Russian т sits on N and
  // answers No; н sits on Y but its meaning wins).
  case AKeyChar of
    'y', 'Y', #$0434, #$0414: Exit(dyaYes);
    'n', 'N', #$043D, #$041D: Exit(dyaNo);
  end;
  if AKey = vkY then
    Exit(dyaYes);
  if AKey = vkN then
    Exit(dyaNo);
  Result := dyaNone;
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
  I: Integer;
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
    FFocusIndex := I;
    case C.Kind of
      dckButton:
        PressButton(I);
      dckCheckbox:
        begin
          FDecl.Controls[I].Checked := not FDecl.Controls[I].Checked;
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

function TDialogHost.HandleOpenDropDownKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  ViewH, Last: Integer;
begin
  Result := FDropOpenIndex >= 0;
  if not Result then
    Exit;

  // Open DropDown: Enter commits, Esc collapses (does not cancel dialog).
  // Every key is consumed: one that fell through would accept or cancel the
  // dialog behind the popup.
  if NormalizeAcceptKey(AKey, AKeyChar) or (AKey = vkSpace) or (AKeyChar = ' ') then
  begin
    CommitDropDown;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkEscape then
  begin
    CloseDropDown;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  // History list: Del forgets the highlighted entry.
  if (AKey = vkDelete) and IsHistoryInput(FDropOpenIndex) then
  begin
    RemoveDropHoverFromHistory;
    AKey := 0;
    AKeyChar := #0;
    Exit;
  end;
  if AKey = vkTab then
  begin
    CloseDropDown;
    FFocusIndex := NextFocusable(FFocusIndex, not (ssShift in AShift));
    NotifyChanged;
    AKey := 0;
    Exit;
  end;
  if (AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
     (AKey = vkPrior) or (AKey = vkNext) then
  begin
    if Length(FDecl.Controls[FDropOpenIndex].Items) > 0 then
    begin
      Last := High(FDecl.Controls[FDropOpenIndex].Items);
      ViewH := Max(DropPopupViewHeight, 1);
      if AKey = vkUp then
        FDropHover := EnsureRange(FDropHover - 1, 0, Last)
      else if AKey = vkDown then
        FDropHover := EnsureRange(FDropHover + 1, 0, Last)
      else if AKey = vkHome then
        FDropHover := 0
      else if AKey = vkEnd then
        FDropHover := Last
      else if AKey = vkPrior then
        FDropHover := EnsureRange(FDropHover - ViewH, 0, Last)
      else
        FDropHover := EnsureRange(FDropHover + ViewH, 0, Last);
      EnsureDropHoverInView;
      NotifyChanged;
    end;
    AKey := 0;
    Exit;
  end;
  AKey := 0;
  AKeyChar := #0;
end;

function TDialogHost.HandleDialogNavKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if NormalizeAcceptKey(AKey, AKeyChar) then
  begin
    FireAccept;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  if AKey = vkEscape then
  begin
    FireCancel;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  if AKey = vkTab then
  begin
    FFocusIndex := NextFocusable(FFocusIndex, not (ssShift in AShift));
    NotifyChanged;
    AKey := 0;
    Exit(True);
  end;

  Result := False;
end;

function TDialogHost.HandleClosedDropDownKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  K: TKeyChord;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);

  // History input: Ctrl+Down / Alt+Down drop the history down.
  if IsHistoryInput(FFocusIndex) and
     IsHistoryDropDownChord(K) then
  begin
    OpenDropDown(FFocusIndex);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;

  // Open DropDown: Space / Alt+Down / F4. A DropDown key that is none of
  // these falls through, so arrows can still move its selection.
  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
     (FDecl.Controls[FFocusIndex].Kind = dckDropDown) then
  begin
    if (AKey = vkF4) or K.MatchesAny(vkDown, [ssAlt], [ssCtrl, ssShift]) or
       (AKey = vkSpace) or (AKeyChar = ' ') then
    begin
      OpenDropDown(FFocusIndex);
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function TDialogHost.HandleFocusedSpaceKey(var AKey: Word;
  var AKeyChar: Char): Boolean;
begin
  if (FFocusIndex >= 0) and (FFocusIndex <= High(FDecl.Controls)) and
     ((AKey = vkSpace) or (AKeyChar = ' ')) then
  begin
    if FDecl.Controls[FFocusIndex].Kind = dckCheckbox then
    begin
      FDecl.Controls[FFocusIndex].Checked := not FDecl.Controls[FFocusIndex].Checked;
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckRadio then
    begin
      SelectRadio(FFocusIndex);
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckRadioGroup then
    begin
      // Space keeps current selection (already exclusive).
      NotifyChanged;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if FDecl.Controls[FFocusIndex].Kind = dckButton then
    begin
      PressButton(FFocusIndex);
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function TDialogHost.HandleMnemonicKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Ch: Char;
begin
  // Hot-keys run for Alt, and for any key while focus is not in an input.
  // A miss leaves the key alone: zeroing it here would swallow the letter a
  // list, picker or input still has to handle.
  if (ssAlt in AShift) or not FocusedIsInput then
  begin
    case DialogYesNoAnswer(AKey, AKeyChar) of
      dyaYes:
        if TryYesNoButton(True) then
        begin
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
      dyaNo:
        if TryYesNoButton(False) then
        begin
          AKey := 0;
          AKeyChar := #0;
          Exit(True);
        end;
    end;
    // A hotkey matches the typed letter first (any script: &Удалить takes
    // у), then the same key on the other layout (the Latin e on the У key
    // takes &Удалить), then the physical key, so Latin hotkeys also work
    // from a layout other than JCUKEN.
    Ch := #0;
    if AKeyChar.IsLetter then
      Ch := AKeyChar.ToUpper;
    if (Ch <> #0) and (TryMnemonic(Ch) or
       TryMnemonic(TextKeyLayoutAlternate(AKeyChar).ToUpper)) then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    if (AKey >= vkA) and (AKey <= vkZ) and (Char(AKey) <> Ch) and TryMnemonic(Char(AKey)) then
    begin
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
  end;

  Result := False;
end;

function TDialogHost.HandleFocusedPickerKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if (FFocusIndex >= 0) and (FDecl.Controls[FFocusIndex].Kind = dckDatePicker) then
  begin
    DatePickerHandleKey(FDecl.Controls[FFocusIndex].Cal, AKey, AShift, AKeyChar);
    AKey := 0;
    AKeyChar := #0;
    NotifyChanged;
    Exit(True);
  end;

  if (FFocusIndex >= 0) and (FDecl.Controls[FFocusIndex].Kind = dckColorPicker) then
  begin
    ColorPickerHandleKey(FDecl.Controls[FFocusIndex].Picker, AKey, AShift, AKeyChar);
    AKey := 0;
    AKeyChar := #0;
    NotifyChanged;
    Exit(True);
  end;

  Result := False;
end;

function TDialogHost.HandleListCommandKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  K: TKeyChord;
  KeyCmd: string;
  BtnIdx: Integer;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);

  if (FFocusIndex >= 0) and (FDecl.Controls[FFocusIndex].Kind = dckList) and
     FDecl.Controls[FFocusIndex].KeyCommands then
  begin
    KeyCmd := '';
    if (AKey = vkSpace) or (AKeyChar = ' ') then
      KeyCmd := 'toggle'
    else if K.MatchesAny(vkUp, [ssCtrl], [ssShift, ssAlt]) then
      KeyCmd := 'up'
    else if K.MatchesAny(vkDown, [ssCtrl], [ssShift, ssAlt]) then
      KeyCmd := 'down';
    if KeyCmd <> '' then
    begin
      AKey := 0;
      AKeyChar := #0;
      FireCommand(KeyCmd);
      Exit(True);
    end;
  end;

  // Del in a list does what the dialog's Delete button does. Without that
  // button the key is left unchanged.
  if (FFocusIndex >= 0) and (FDecl.Controls[FFocusIndex].Kind = dckList) and
     (AKey = vkDelete) and (AShift * [ssShift, ssCtrl, ssAlt] = []) then
  begin
    BtnIdx := ButtonIndexById(cDlgCmdDelete);
    if BtnIdx >= 0 then
    begin
      AKey := 0;
      AKeyChar := #0;
      PressButton(BtnIdx);
      Exit(True);
    end;
  end;

  Result := False;
end;

function TDialogHost.HandleListNavKeys(var AKey: Word): Boolean;
begin
  if (FFocusIndex >= 0) and
     (FDecl.Controls[FFocusIndex].Kind in [dckList, dckRadioGroup, dckDropDown]) and
     ((AKey = vkUp) or (AKey = vkDown) or (AKey = vkHome) or (AKey = vkEnd) or
      (AKey = vkPrior) or (AKey = vkNext)) then
  begin
    if Length(FDecl.Controls[FFocusIndex].Items) > 0 then
    begin
      if AKey = vkUp then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex - 1)
      else if AKey = vkDown then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex + 1)
      else if AKey = vkHome then
        SetListSelectedIndex(FFocusIndex, 0)
      else if AKey = vkEnd then
        SetListSelectedIndex(FFocusIndex,
          High(FDecl.Controls[FFocusIndex].Items))
      else if (AKey = vkPrior) and
        (FDecl.Controls[FFocusIndex].Kind = dckList) then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex -
            Max(ListViewHeight(FFocusIndex), 1))
      else if (AKey = vkNext) and
        (FDecl.Controls[FFocusIndex].Kind = dckList) then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex +
            Max(ListViewHeight(FFocusIndex), 1))
      else if AKey = vkPrior then
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex - 1)
      else
        SetListSelectedIndex(FFocusIndex,
          FDecl.Controls[FFocusIndex].SelectedIndex + 1);
      NotifyChanged;
    end;
    AKey := 0;
    Exit(True);
  end;

  Result := False;
end;

function TDialogHost.HandleFocusedInputKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  C: TDialogControl;
  LineRes: TInputLineResult;
  K: TKeyChord;
begin
  if not FocusedIsInput then
    Exit(False);

  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  // Copy/writeback: dynarray-of-record field as var can drop edits otherwise.
  C := FDecl.Controls[FFocusIndex];
  // Password inputs: no Ctrl+C / Ctrl+X / Ctrl+Insert copy-out.
  if C.Password and (K.MatchesAny(vkC, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssCtrl], [ssShift, ssAlt])) then
  begin
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  // Read-only inputs: moving, selecting and copying only.
  if C.ReadOnly and (K.IsPrintable or (AKey = vkBack) or (AKey = vkDelete) or
     K.MatchesAny(vkX, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkV, [ssCtrl], [ssShift, ssAlt]) or
     K.MatchesAny(vkInsert, [ssShift], [ssCtrl, ssAlt])) then
  begin
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  LineRes := InputLineHandleInput(C.Edit, AKey, AShift, AKeyChar);
  FDecl.Controls[FFocusIndex] := C;
  case LineRes of
    ilrSubmit:
      FireAccept;
    ilrCancel:
      FireCommand(cDlgCmdCancel);
  else
    NotifyChanged;
  end;
  Result := True;
end;

function TDialogHost.HandleFocusArrowKeys(var AKey: Word): Boolean;
begin
  if (AKey = vkLeft) or (AKey = vkRight) or (AKey = vkUp) or (AKey = vkDown) then
  begin
    FFocusIndex := NextFocusable(FFocusIndex, (AKey = vkRight) or (AKey = vkDown));
    NotifyChanged;
    AKey := 0;
    Exit(True);
  end;
  Result := False;
end;

function TDialogHost.HandleInputCore(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := False;
  if not FVisible then
    Exit;

  if not FCursorVisible then
  begin
    FCursorVisible := True;
    NotifyChanged;
  end;

  Result := True;

  if HandleOpenDropDownKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleDialogNavKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleClosedDropDownKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleFocusedSpaceKey(AKey, AKeyChar) then
    Exit;
  if HandleMnemonicKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleFocusedPickerKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleListCommandKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleListNavKeys(AKey) then
    Exit;
  if HandleFocusedInputKeys(AKey, AShift, AKeyChar) then
    Exit;
  if HandleFocusArrowKeys(AKey) then
    Exit;

  // A key no control took is still consumed, so the window under the dialog
  // does not see it.
  AKey := 0;
  AKeyChar := #0;
end;

end.
