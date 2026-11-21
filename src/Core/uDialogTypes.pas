unit uDialogTypes;

{ Declarative dialog control model (DIALOG_PLUGIN subset, in-process). }

interface

uses
  System.SysUtils, System.Math,
  System.UITypes,
  uInputLine, uTerminalTypes, uColorPickerControl, uDatePickerControl;

type
  TDialogControlKind = (dckLabel, dckInput, dckCheckbox, dckButton, dckStatus,
    dckList, dckRadio, dckRadioGroup, dckDropDown, dckColorSample, dckColorPicker, dckDatePicker, dckTab);

  /// <summary>dckColorSample: which panel row visual state an UNSET Fg/Bg
  /// channel should preview as the theme's own resolved color for (matching
  /// color-coding's own "0 = inherit" semantics) instead of falling back to
  /// a fixed placeholder. cspsNone (JSON omits "panelState") keeps a
  /// fixed black-on-gray fallback - e.g. the color picker's single-channel
  /// preview isn't tied to any one panel row.</summary>
  TColorSamplePanelState = (cspsNone, cspsNormal, cspsSelected, cspsCurrent);

  /// <summary>A colored cell drawn over a dckList row at column Col of the
  /// row text; an unset (0) channel keeps the row's own color.</summary>
  TListSwatch = record
    Col: Integer;
    Text: string;
    Fg, Bg: TAlphaColor;
  end;

  /// <summary>An accent-colored stretch of a dckList row: Len cells from
  /// column Col of item Item's text.</summary>
  TListAccent = record
    Item, Col, Len: Integer;
  end;

  TDialogControl = record
    Kind: TDialogControlKind;
    Id: string;
    /// <summary>dckColorSample: the sample text drawn inside the swatch
    /// (e.g. "filename.txt"). Unused by other kinds' Text meaning.</summary>
    Text: string;
    /// <summary>For dckRadio: mutual-exclusion group id (values key).</summary>
    Group: string;
    Checked: Boolean;
    /// <summary>dckCheckbox: three states, "don't care" [?], unchecked [ ] and
    /// checked [x] (JSON "tristate": true). Unknown is the first one and takes
    /// precedence over Checked.</summary>
    Tristate: Boolean;
    Unknown: Boolean;
    IsDefault: Boolean;
    IsCancel: Boolean;
    Edit: TInputLine;
    Items: TArray<string>;
    /// <summary>dckList: one optional swatch per item (same index as Items).</summary>
    ItemSwatches: TArray<TListSwatch>;
    /// <summary>dckList: accent-colored stretches of the rows.</summary>
    ItemAccents: TArray<TListAccent>;
    /// <summary>Optional ids for radio_group items (values use id when set).</summary>
    ItemIds: TArray<string>;
    SelectedIndex: Integer;
    /// <summary>dckColorSample only: id of the dckInput control whose LIVE
    /// (uncommitted, re-read every Draw) text is parsed as "#RRGGBB"/"RRGGBB"
    /// for the sample's foreground. '' = foreground stays at Host's default
    /// (black). Lets a hex color field show what it currently means without
    /// the caller re-rendering the dialog on every keystroke.</summary>
    FgSourceId: string;
    /// <summary>dckColorSample only: same as FgSourceId, for the background.
    /// '' = background stays at Host's default (white).</summary>
    BgSourceId: string;
    /// <summary>dckColorSample only - see TColorSamplePanelState.</summary>
    PanelState: TColorSamplePanelState;
    /// <summary>dckColorSample only: id of a dckDropDown whose selected item's
    /// ItemId ("bold+italic", "none") gives the text attributes the sample is
    /// drawn with; an empty ItemId shows BaseStyle.</summary>
    StyleSourceId: string;
    /// <summary>dckColorSample only: attributes ("bold", "underline") shown
    /// while StyleSourceId selects nothing of its own.</summary>
    BaseStyle: string;
    /// <summary>dckColorSample only: ids of inputs whose color stands in for the
    /// foreground / background while the sample's own source is blank or not a
    /// color (the document colors behind a Markdown element).</summary>
    FgFallbackId, BgFallbackId: string;
    /// <summary>dckColorPicker: the whole picker (uColorPickerControl).</summary>
    Picker: TColorPickerState;
    /// <summary>dckDatePicker: the month calendar (uDatePickerControl).</summary>
    Cal: TDatePickerState;
    /// <summary>dckLabel: drawn in bold with the dialog's accent color, for the
    /// values a caption introduces (JSON "accent": true).</summary>
    Accent: Boolean;
    /// <summary>dckLabel: drawn in bold cyan (dark blue on a light dialog), for
    /// paths and other values that must stand out from the text (JSON "marked": true).</summary>
    Marked: Boolean;
    /// <summary>dckList: a single-line frame is drawn around the list, one cell
    /// outside its box (JSON "frame": true); the author leaves those cells free.</summary>
    Framed: Boolean;
    /// <summary>dckList: read-only text block - no selected-row highlight and
    /// not reachable by focus (JSON "plain": true); ItemSwatches still color it.</summary>
    Plain: Boolean;
    /// <summary>dckList: Space fires the command "toggle", Delete "delete", F2 / F4 / F5
    /// "f2" / "f4" / "f5", Ctrl+Up / Ctrl+Down the
    /// commands "up" / "down" (JSON "keycommands": true), so the owner can act on the
    /// selected row without a button for it.</summary>
    KeyCommands: Boolean;
    /// <summary>dckInput: draw '*' instead of the stored characters.</summary>
    Password: Boolean;
    /// <summary>dckInput: the text can be selected and copied but not changed
    /// (JSON "readonly": true).</summary>
    ReadOnly: Boolean;
    /// <summary>dckInput: a key-capture field (JSON "hotkey": true). While focused,
    /// a keystroke is stored as its chord text ("Ctrl+Shift+F5") instead of being
    /// typed; Backspace / Delete clear it, Tab, Enter and Esc keep their dialog
    /// meaning.</summary>
    HotKey: Boolean;
    /// <summary>dckInput with HotKey (JSON "multi": true): the field holds several
    /// chords separated by "; " in keymap spelling; a pressed chord is appended,
    /// Backspace removes the last one, Delete clears the field.</summary>
    HotKeyMulti: Boolean;
    /// <summary>dckCheckbox, dckInput, dckDropDown: greyed out, skipped by the
    /// focus, ignores clicks and (checkbox) its mnemonic. TDialogHost.
    /// SetControlDisabled flips it while the dialog is open.</summary>
    Disabled: Boolean;
    /// <summary>dckInput holding a "#RRGGBB" color: shows a pick button in its
    /// last cell (filled with the color); clicking it fires the command
    /// DialogPickCommand(Id).</summary>
    ColorPick: Boolean;
    /// <summary>dckInput holding a date: shows a pick button in its last cell;
    /// clicking it fires the command DialogPickCommand(Id).</summary>
    DatePick: Boolean;
    /// <summary>dckInput: uDialogHistory key ('' = none). Such a field shows
    /// ↓ in its last cell and drops down Items (the key's history, filled by
    /// TDialogHost.Open) like a dckDropDown.</summary>
    History: string;
    /// <summary>Protocol 2.0: client-relative cell position (col/row). -1 = unset (v1 flow).</summary>
    Col: Integer;
    Row: Integer;
    /// <summary>Protocol 2.0: cell size. 0 = Host default for the control kind.</summary>
    BoxW: Integer;
    BoxH: Integer;
    /// <summary>Protocol 2.0: the page of the dialog's tab strip (dckTab) this
    /// control sits on, 1-based (JSON "tab": N, 0-based). 0 = shown on every
    /// page. A control of another page has no box and no focus.</summary>
    TabPage: Integer;
  end;

  TDialogControls = TArray<TDialogControl>;

  TDialogDeclaration = record
    /// <summary>"1.0" = flow layout; "2.0" = absolute col/row/width/height.</summary>
    Version: string;
    Title: string;
    Width: Integer;
    Height: Integer;
    /// <summary>True = FAR Warning chrome (red body, white text).</summary>
    IsWarning: Boolean;
    /// <summary>True = the declaration's width and control columns are used
    /// as written: no widening to captions, no column shifts, no button
    /// recentering (JSON "autoLayout": false).</summary>
    NoAutoLayout: Boolean;
    /// <summary>Help topic F1 opens for a dialog a plugin shows: a help page file
    /// (full path) or '' for the host's generic topic.</summary>
    HelpTopic: string;
    Controls: TDialogControls;
  end;

  TDialogCommandEvent = reference to procedure(const AControlId: string;
    const AValuesJson: string);
  TDialogValueChangedEvent = reference to procedure(const AControlId: string);

const
  cDialogProtocolV1 = '1.0';
  cDialogProtocolV2 = '2.0';

  /// <summary>Canonical dialog button / command ids (JSON + Build* patchers).</summary>
  cDlgCmdOk = 'ok';
  cDlgCmdCancel = 'cancel';
  cDlgCmdYes = 'yes';
  cDlgCmdNo = 'no';
  cDlgCmdFilter = 'filter';
  cDlgCmdReplaceOne = 'one';
  cDlgCmdReplaceAll = 'all';
  cDlgCmdOverwrite = 'overwrite';
  cDlgCmdSkip = 'skip';
  cDlgCmdSkipAll = 'skipall';
  cDlgCmdAppend = 'append';
  cDlgCmdRename = 'rename';
  cDlgCmdDelete = 'delete';
  cDlgCmdRetry = 'retry';
  /// <summary>Error prompt: repeat the rest of the job with administrator rights.</summary>
  cDlgCmdElevate = 'elevate';
  cDlgCmdBackground = 'background';
  cDlgCmdForeground = 'foreground';
  /// <summary>Progress dialog of a search: go on in the background and keep the results in the panel.</summary>
  cDlgCmdPanel = 'panel';
  cDlgCmdCancelJob = 'canceljob';
  cDlgCmdCancelAll = 'cancelall';
  cDlgCmdPauseJob = 'pausejob';
  cDlgCmdJobUp = 'jobup';
  cDlgCmdJobDown = 'jobdown';
  cDlgCmdJobSpeed = 'jobspeed';
  cDlgCmdClearFilter = 'clear';
  /// <summary>Suffix of the command a color field's pick button fires.</summary>
  cDlgPickSuffix = ':pick';

function IsDialogProtocolV2(const AVersion: string): Boolean;
function DialogCmdIs(const AId, AExpected: string): Boolean;
/// <summary>The command a pick button on input AFieldId fires.</summary>
function DialogPickCommand(const AFieldId: string): string;
/// <summary>True for a pick-button command; AFieldId is the input it belongs to.</summary>
function DialogCmdIsPick(const AId: string; out AFieldId: string): Boolean;
function DialogCmdIsOk(const AId: string): Boolean;
function DialogCmdIsCancel(const AId: string): Boolean;
function DialogCmdIsYes(const AId: string): Boolean;
function DialogCmdIsNo(const AId: string): Boolean;
/// <summary>Primary accept: ok or yes.</summary>
function DialogCmdIsAccept(const AId: string): Boolean;
/// <summary>Dismiss / negative: cancel or no.</summary>
function DialogCmdIsReject(const AId: string): Boolean;
/// <summary>Accept-style commands on a pick-list dialog: Enter/double-click on
/// the list itself (AListId), or the dialog's own OK/Accept button. Shared by
/// the list+editor dialog controllers (history, hotlist, SSH connections,
/// workspaces, ...).</summary>
function DialogCmdIsListAccept(const AId, AListId: string): Boolean;

function MakeLabel(const AText: string; const AId: string = ''): TDialogControl;
function MakeInput(const AId, AValue: string): TDialogControl;
function MakeCheckbox(const AId, AText: string; AChecked: Boolean): TDialogControl;
/// <summary>The click / Space / mnemonic step of a checkbox. A tri-state one
/// goes "don't care" -> checked -> unchecked -> "don't care".</summary>
procedure DialogToggleCheckbox(var AControl: TDialogControl);
/// <summary>0 = "don't care", 1 = unchecked, 2 = checked; a plain checkbox is
/// 1 or 2.</summary>
function DialogCheckboxState(const AControl: TDialogControl): Integer;
procedure DialogSetCheckboxState(var AControl: TDialogControl; AState: Integer);
function MakeRadio(const AId, AGroup, AText: string;
  AChecked: Boolean = False): TDialogControl;
function MakeRadioGroup(const AId, ACaption: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0;
  const AItemIds: TArray<string> = nil): TDialogControl;
function MakeButton(const AId, AText: string; ADefault: Boolean = False;
  ACancel: Boolean = False): TDialogControl;
function MakeStatus(const AId, AText: string): TDialogControl;
/// <summary>Live color-swatch preview - see TDialogControl.FgSourceId/BgSourceId.</summary>
function MakeColorSample(const AId, AText, AFgSourceId, ABgSourceId: string;
  APanelState: TColorSamplePanelState = cspsNone): TDialogControl;
/// <summary>The color picker control (swatch grid, sliders, hex field).</summary>
function MakeColorPicker(const AId: string): TDialogControl;
/// <summary>The month calendar control.</summary>
function MakeDatePicker(const AId: string): TDialogControl;
/// <summary>"normal"/"selected"/"current" -> TColorSamplePanelState; anything
/// else (including '') -> cspsNone.</summary>
function ColorSamplePanelStateFromStr(const AStr: string): TColorSamplePanelState;
/// <summary>The tab strip: one caption per page in Items, SelectedIndex is the
/// page shown. Controls choose a page with TabPage.</summary>
function MakeTabs(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogControl;
function MakeList(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogControl;
/// <summary>Collapsed combo: selected item + popup list (DropDownList).</summary>
function MakeDropDown(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogControl;
/// <summary>Horizontal rule label (─ x width) for protocol 2.0 separators
/// (JSON "separator"). Spanning the whole client width, TDialogHost joins
/// its ends to the dialog frame.</summary>
function MakeHRule(AWidth: Integer): TDialogControl;
/// <summary>True for a MakeHRule caption (only ─).</summary>
function IsHRuleText(const AText: string): Boolean;
/// <summary>Protocol 2.0 helper: set absolute cell box (col/row/w/h).</summary>
function WithControlBox(const ACtrl: TDialogControl; ACol, ARow, AWidth,
  AHeight: Integer): TDialogControl;

implementation

uses
  uThemeDrawing;

procedure ClearControlLayout(var C: TDialogControl);
begin
  C.Col := -1;
  C.Row := -1;
  C.BoxW := 0;
  C.BoxH := 0;
end;

function IsDialogProtocolV2(const AVersion: string): Boolean;
var
  V: string;
begin
  V := Trim(AVersion);
  Result := SameText(V, cDialogProtocolV2) or SameText(V, '2');
end;

function DialogPickCommand(const AFieldId: string): string;
begin
  Result := AFieldId + cDlgPickSuffix;
end;

function DialogCmdIsPick(const AId: string; out AFieldId: string): Boolean;
begin
  Result := (Length(AId) > Length(cDlgPickSuffix)) and
    SameText(Copy(AId, Length(AId) - Length(cDlgPickSuffix) + 1, MaxInt), cDlgPickSuffix);
  if Result then
    AFieldId := Copy(AId, 1, Length(AId) - Length(cDlgPickSuffix))
  else
    AFieldId := '';
end;

function DialogCmdIs(const AId, AExpected: string): Boolean;
begin
  Result := SameText(Trim(AId), AExpected);
end;

function DialogCmdIsOk(const AId: string): Boolean;
begin
  Result := DialogCmdIs(AId, cDlgCmdOk);
end;

function DialogCmdIsCancel(const AId: string): Boolean;
begin
  Result := DialogCmdIs(AId, cDlgCmdCancel);
end;

function DialogCmdIsYes(const AId: string): Boolean;
begin
  Result := DialogCmdIs(AId, cDlgCmdYes);
end;

function DialogCmdIsNo(const AId: string): Boolean;
begin
  Result := DialogCmdIs(AId, cDlgCmdNo);
end;

function DialogCmdIsAccept(const AId: string): Boolean;
begin
  Result := DialogCmdIsOk(AId) or DialogCmdIsYes(AId);
end;

function DialogCmdIsReject(const AId: string): Boolean;
begin
  Result := DialogCmdIsCancel(AId) or DialogCmdIsNo(AId);
end;

function DialogCmdIsListAccept(const AId, AListId: string): Boolean;
begin
  Result := DialogCmdIsAccept(AId) or DialogCmdIs(AId, AListId) or DialogCmdIsOk(AId);
end;

function WithControlBox(const ACtrl: TDialogControl; ACol, ARow, AWidth,
  AHeight: Integer): TDialogControl;
begin
  Result := ACtrl;
  Result.Col := ACol;
  Result.Row := ARow;
  Result.BoxW := AWidth;
  Result.BoxH := AHeight;
end;

function MakeHRule(AWidth: Integer): TDialogControl;
begin
  Result := MakeLabel(StringOfChar(chBoxH, Max(AWidth, 1)));
end;

function IsHRuleText(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := AText <> '';
  for I := 1 to Length(AText) do
    if AText[I] <> chBoxH then
      Exit(False);
end;

function MakeLabel(const AText: string; const AId: string = ''): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckLabel;
  Result.Accent := False;
  Result.Marked := False;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

function MakeInput(const AId, AValue: string): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckInput;
  Result.Id := AId;
  Result.Text := '';
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  InputLineSetText(Result.Edit, AValue);
  InputLineSelectAll(Result.Edit);
  Result.Password := False;
  Result.ReadOnly := False;
  Result.ColorPick := False;
  Result.DatePick := False;
  Result.History := '';
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

procedure DialogToggleCheckbox(var AControl: TDialogControl);
begin
  if not AControl.Tristate then
    AControl.Checked := not AControl.Checked
  else if AControl.Unknown then
  begin
    AControl.Unknown := False;
    AControl.Checked := True;
  end
  else if AControl.Checked then
    AControl.Checked := False
  else
    AControl.Unknown := True;
end;

function DialogCheckboxState(const AControl: TDialogControl): Integer;
begin
  if AControl.Tristate and AControl.Unknown then
    Result := 0
  else if AControl.Checked then
    Result := 2
  else
    Result := 1;
end;

procedure DialogSetCheckboxState(var AControl: TDialogControl; AState: Integer);
begin
  AControl.Unknown := AControl.Tristate and (AState = 0);
  AControl.Checked := AState = 2;
end;

function MakeCheckbox(const AId, AText: string; AChecked: Boolean): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckCheckbox;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := AChecked;
  Result.Disabled := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

function MakeRadio(const AId, AGroup, AText: string;
  AChecked: Boolean): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckRadio;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := AGroup;
  Result.Checked := AChecked;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

function MakeRadioGroup(const AId, ACaption: string; const AItems: TArray<string>;
  ASelectedIndex: Integer; const AItemIds: TArray<string>): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckRadioGroup;
  Result.Id := AId;
  Result.Text := ACaption;
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  Result.Items := Copy(AItems);
  Result.ItemIds := Copy(AItemIds);
  if Length(Result.Items) = 0 then
    Result.SelectedIndex := 0
  else
    Result.SelectedIndex := EnsureRange(ASelectedIndex, 0, High(Result.Items));
  ClearControlLayout(Result);
end;

function MakeButton(const AId, AText: string; ADefault, ACancel: Boolean): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckButton;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := ADefault;
  Result.IsCancel := ACancel;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

function MakeStatus(const AId, AText: string): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckStatus;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  Result.FgSourceId := '';
  Result.BgSourceId := '';
  ClearControlLayout(Result);
end;

function MakeColorPicker(const AId: string): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckColorPicker;
  Result.Id := AId;
  Result.Text := '';
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  Result.Picker := ColorPickerEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  Result.FgSourceId := '';
  Result.BgSourceId := '';
  Result.PanelState := cspsNone;
  Result.Password := False;
  Result.ReadOnly := False;
  Result.History := '';
  ClearControlLayout(Result);
end;

function MakeDatePicker(const AId: string): TDialogControl;
begin
  Result := MakeColorPicker(AId);
  Result.Kind := dckDatePicker;
  Result.Cal := DatePickerEmpty;
end;

function MakeColorSample(const AId, AText, AFgSourceId, ABgSourceId: string;
  APanelState: TColorSamplePanelState): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckColorSample;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  Result.FgSourceId := AFgSourceId;
  Result.BgSourceId := ABgSourceId;
  Result.PanelState := APanelState;
  ClearControlLayout(Result);
end;

function ColorSamplePanelStateFromStr(const AStr: string): TColorSamplePanelState;
begin
  if SameText(AStr, 'normal') then
    Result := cspsNormal
  else if SameText(AStr, 'selected') then
    Result := cspsSelected
  else if SameText(AStr, 'current') then
    Result := cspsCurrent
  else
    Result := cspsNone;
end;

function MakeList(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckList;
  Result.Id := AId;
  Result.Text := '';
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  Result.Items := Copy(AItems);
  SetLength(Result.ItemIds, 0);
  if Length(Result.Items) = 0 then
    Result.SelectedIndex := 0
  else
    Result.SelectedIndex := EnsureRange(ASelectedIndex, 0, High(Result.Items));
  ClearControlLayout(Result);
end;

function MakeDropDown(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogControl;
begin
  Result := Default(TDialogControl);
  Result.Kind := dckDropDown;
  Result.Id := AId;
  Result.Text := '';
  Result.Group := '';
  Result.Checked := False;
  Result.IsDefault := False;
  Result.IsCancel := False;
  Result.Edit := InputLineEmpty;
  Result.Items := Copy(AItems);
  SetLength(Result.ItemIds, 0);
  if Length(Result.Items) = 0 then
    Result.SelectedIndex := 0
  else
    Result.SelectedIndex := EnsureRange(ASelectedIndex, 0, High(Result.Items));
  ClearControlLayout(Result);
end;

function MakeTabs(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogControl;
begin
  Result := MakeDropDown(AId, AItems, ASelectedIndex);
  Result.Kind := dckTab;
end;

end.
