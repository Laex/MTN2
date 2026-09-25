unit uDialogTypes;

{ Declarative dialog control model (DIALOG_PLUGIN subset, in-process). }

interface

uses
  System.SysUtils, System.Math,
  uInputLine, uTextEncoding, uTerminalTypes;

type
  TDialogControlKind = (dckLabel, dckInput, dckCheckbox, dckButton, dckStatus,
    dckList, dckRadio, dckRadioGroup, dckDropDown, dckColorSample);

  /// <summary>dckColorSample: which panel row visual state an UNSET Fg/Bg
  /// channel should preview as the theme's own resolved color for (matching
  /// color-coding's own "0 = inherit" semantics) instead of falling back to
  /// a fixed placeholder. cspsNone (JSON omits "panelState") keeps the old
  /// fixed black-on-gray fallback — e.g. the color picker's single-channel
  /// preview isn't tied to any one panel row.</summary>
  TColorSamplePanelState = (cspsNone, cspsNormal, cspsSelected, cspsCurrent);

  TDialogControl = record
    Kind: TDialogControlKind;
    Id: string;
    /// <summary>dckColorSample: the sample text drawn inside the swatch
    /// (e.g. "filename.txt"). Unused by other kinds' Text meaning.</summary>
    Text: string;
    /// <summary>For dckRadio: mutual-exclusion group id (values key).</summary>
    Group: string;
    Checked: Boolean;
    IsDefault: Boolean;
    IsCancel: Boolean;
    Edit: TInputLine;
    Items: TArray<string>;
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
    /// <summary>dckColorSample only — see TColorSamplePanelState.</summary>
    PanelState: TColorSamplePanelState;
    /// <summary>dckInput: draw '*' instead of the stored characters.</summary>
    Password: Boolean;
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
    Controls: TDialogControls;
  end;

  TDialogCommandEvent = reference to procedure(const AControlId: string;
    const AValuesJson: string);

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
  cDlgCmdBackground = 'background';
  cDlgCmdForeground = 'foreground';
  cDlgCmdCancelJob = 'canceljob';
  cDlgCmdCancelAll = 'cancelall';

function IsDialogProtocolV2(const AVersion: string): Boolean;
function DialogCmdIs(const AId, AExpected: string): Boolean;
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
function MakeRadio(const AId, AGroup, AText: string;
  AChecked: Boolean = False): TDialogControl;
function MakeRadioGroup(const AId, ACaption: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0;
  const AItemIds: TArray<string> = nil): TDialogControl;
function MakeButton(const AId, AText: string; ADefault: Boolean = False;
  ACancel: Boolean = False): TDialogControl;
function MakeStatus(const AId, AText: string): TDialogControl;
/// <summary>Live color-swatch preview — see TDialogControl.FgSourceId/BgSourceId.</summary>
function MakeColorSample(const AId, AText, AFgSourceId, ABgSourceId: string;
  APanelState: TColorSamplePanelState = cspsNone): TDialogControl;
/// <summary>"normal"/"selected"/"current" -> TColorSamplePanelState; anything
/// else (including '') -> cspsNone.</summary>
function ColorSamplePanelStateFromStr(const AStr: string): TColorSamplePanelState;
function MakeList(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogControl;
/// <summary>Collapsed combo: selected item + popup list (DropDownList).</summary>
function MakeDropDown(const AId: string; const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogControl;
/// <summary>Horizontal rule label (─ × width) for protocol 2.0 separators.</summary>
function MakeHRule(AWidth: Integer): TDialogControl;
/// <summary>Protocol 2.0 helper: set absolute cell box (col/row/w/h).</summary>
function WithControlBox(const ACtrl: TDialogControl; ACol, ARow, AWidth,
  AHeight: Integer): TDialogControl;

function BuildConfirmDialog(const ATitle, AMessage: string): TDialogDeclaration;
function BuildDeleteDialog(const ATitle, AMessage, AOkText: string;
  AWarning: Boolean = False): TDialogDeclaration;
function BuildHelpDialog: TDialogDeclaration;
function BuildInputDialog(const ATitle, APrompt, AValue: string): TDialogDeclaration;
function BuildSelectMaskDialog(const ATitle, APrompt, AValue: string;
  ASelectFolders: Boolean): TDialogDeclaration;
function BuildArchivePasswordDialog(const AArchiveName, APrompt: string): TDialogDeclaration;
function BuildAskSaveDialog(const AFileName: string): TDialogDeclaration;
function BuildSearchDialog(const AMask, AContaining: string;
  ACaseSensitive, AWholeWords, ASearchFolders, AUseRegex, ASubdirs: Boolean): TDialogDeclaration;
function BuildCopyMoveDialog(const ATitle, APrompt, ADestPath: string;
  AOverwriteIndex: Integer = 0; APreserveTimestamps: Boolean = False;
  AOnlyNewer: Boolean = False; AFollowSymlinks: Boolean = False;
  ARetryIndex: Integer = 1; AFilterEnabled: Boolean = False;
  const AExcludeMask: string = '*.tmp;*.bak;~*'): TDialogDeclaration;
function BuildGotoLineDialog(ALine: Integer): TDialogDeclaration;
function BuildEncodingDialog(ACurrent: string): TDialogDeclaration;
function BuildReplaceDialog(const AFind, AReplace: string): TDialogDeclaration;
function BuildOverwriteAskDialog(const APath, ANewLine, AExistingLine: string): TDialogDeclaration;
function BuildDeleteErrorDialog(const AHeadline, APath, AQuestion, AErrorLine: string;
  AOfferPermanent: Boolean): TDialogDeclaration;
function BuildIOErrorDialog(const AHeadline, APath, AErrorLine: string): TDialogDeclaration;
function BuildFolderHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildJobListDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>AItems are display names from uThemeRegistry.GetAvailableThemes,
/// parallel to the ids TDualPanelWindow keeps in FThemeIds.</summary>
function BuildThemeDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildCmdHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>Alt+F11: AItems are "mode mark + path" labels, newest first.</summary>
function BuildFileHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels (id, name, version),
/// see HostPluginListDisplayLabels in uPluginHost.pas.</summary>
function BuildPluginListDialog(const AItems: TArray<string>): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels ("Name  —  path" or
/// bare path when unnamed) — see FolderHotlistDisplayLabel.</summary>
function BuildFolderHotlistDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildWorkspaceLibraryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const ALiveCaption: string): TDialogDeclaration;
function BuildCreateLinkDialog(const ALinkName, ATarget: string;
  ALinkTypeIndex: Integer = 0): TDialogDeclaration;
/// <summary>ACreated / AModified / AAccessed: date text for the three time
/// fields ('' = differs between the items / unknown).</summary>
function BuildSetAttributesDialog(const ASummary, AOwnerNow, AOwnerEdit: string;
  AReadOnlyIdx, AHiddenIdx, AArchiveIdx, ASystemIdx: Integer;
  const ACreated, AModified, AAccessed: string): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels, see SshConnectionDisplayLabel.</summary>
function BuildSshConnectionsDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildSshConnectionEditDialog(const AName, AHost: string; APort: Integer;
  const AUser, AIdentityFile: string): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels, see
/// uUserAssociations.pas / uDualPanelUserAssociations.pas.</summary>
function BuildAssociationsDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildAssociationEditDialog(const AExtension: string; AActionIndex: Integer;
  const ACommand: string): TDialogDeclaration;
/// <summary>User menu (F2) item editor, uDualPanelUserMenu.pas. AKindIndex:
/// 0 command, 1 submenu, 2 separator.</summary>
function BuildUserMenuEditDialog(const AHotKey, ACaption, ACommand: string;
  AKindIndex: Integer): TDialogDeclaration;
function BuildDirSyncDialog(const ASrcPath, ADstPath, AStatus: string;
  const APreview: TArray<string>; ADryRun: Boolean = False;
  ATwoWay: Boolean = False; AByContent: Boolean = False): TDialogDeclaration;
function BuildFileDiffDialog(const ALeftName, ARightName, AStatus: string;
  const ALines: TArray<string>): TDialogDeclaration;
/// <summary>Options > Columns... — which fields pcmCustom shows. One
/// checkbox per flag; caller (uDualPanelWindow.OpenColumnsConfigDialog)
/// passes uPanelColumns.GCustomColumnsConfig's current values.</summary>
function BuildColumnsConfigDialog(AShowExt, AShowSize, AShowModified,
  AShowCreated, AShowAccessed, AShowType, AShowAttr: Boolean): TDialogDeclaration;
function BuildDisplayDialog(const AFontNames: TArray<string>;
  AFontIndex, ASizeIndex, AZoomIndex, ABlinkMsIndex: Integer;
  ABlink, AShowIcons: Boolean; const ANote: string;
  const ALanguageNames: TArray<string>; ALanguageIndex: Integer): TDialogDeclaration;
/// <summary>Options > External viewer/editor...: the Alt+F3 / Alt+F4 command
/// templates (uExternalTools).</summary>
function BuildExternalToolsDialog(const AViewer, AEditor: string): TDialogDeclaration;
/// <summary>Files > Checksums...: algorithm dropdown (index into
/// uChecksums.TChecksumAlgo order: MD5, SHA-1, SHA-256, SHA-512).</summary>
function BuildChecksumOptionsDialog(AAlgoIndex: Integer): TDialogDeclaration;
/// <summary>Checksum result list; AVerify drops the Save button (the
/// lines are OK / FAILED marks, not a checksum file).</summary>
function BuildChecksumResultDialog(const ATitle, AStatus: string;
  const ALines: TArray<string>; AVerify: Boolean): TDialogDeclaration;
function BuildTerminalProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildConsoleProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer = 0; AStartOnLaunch: Boolean = False): TDialogDeclaration;
function BuildAboutDialog: TDialogDeclaration;
/// <summary>Update offer: buttons update / later (Esc) / skip.</summary>
function BuildUpdateOfferDialog(const ANewVersion, ACurrentVersion: string): TDialogDeclaration;
/// <summary>Two-line updater message; buttons ok / cancel (Esc). '' keeps a
/// button's translated resource caption; AShowCancel = False leaves a single
/// OK that Esc also triggers.</summary>
function BuildUpdateMessageDialog(const AMessage, ADetails, AOkText: string;
  AShowCancel: Boolean; const ACancelText: string = ''): TDialogDeclaration;
/// <summary>Help > Updates: installed version, the check_on_start checkbox,
/// buttons check / close (Esc).</summary>
function BuildUpdatesDialog(const ACurrentVersion: string;
  ACheckOnStart: Boolean): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels — see
/// ColorCodingDisplayLabel in uColorCodingEditHelpers.pas.</summary>
function BuildColorCodingDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildColorCodingEditDialog(const AName, AMask: string;
  AApplyToIndex: Integer; AEnabled: Boolean;
  const ANormalFg, ANormalBg, ASelectedFg, ASelectedBg,
  ACurrentFg, ACurrentBg: string): TDialogDeclaration;
/// <summary>APresetLabels are pre-formatted display labels (name + hex —
/// see ColorPickerPresets in uColorCodingEditHelpers.pas); APresetIndex is which one
/// starts selected. AIsBg wires the live preview to show ACurrentHex as the
/// background (picking a Bg field) or foreground (picking a Fg field).</summary>
function BuildColorPickerDialog(const ATitle, ACurrentHex: string;
  const APresetLabels: TArray<string>; APresetIndex: Integer;
  AIsBg: Boolean): TDialogDeclaration;
/// <summary>AItems are pre-formatted "Action  Hotkeys" rows — see
/// TKeymapDialogController.ActionRowLabel in uDualPanelKeymapDialog.pas.</summary>
function BuildKeymapDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildKeymapEditDialog(const AActionName, AKeysText,
  AStatus: string): TDialogDeclaration;

implementation

uses
  uDialogResources, uDialogLocaleLayout, uDisplaySettings, uStrings, uUpdater
  {$IFDEF SKIA}
  , FMX.Skia
  {$ENDIF}
  ;

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

function MakeLabel(const AText: string; const AId: string = ''): TDialogControl;
begin
  Result.Kind := dckLabel;
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
  Result.History := '';
  SetLength(Result.Items, 0);
  SetLength(Result.ItemIds, 0);
  Result.SelectedIndex := 0;
  ClearControlLayout(Result);
end;

function MakeCheckbox(const AId, AText: string; AChecked: Boolean): TDialogControl;
begin
  Result.Kind := dckCheckbox;
  Result.Id := AId;
  Result.Text := AText;
  Result.Group := '';
  Result.Checked := AChecked;
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

function MakeColorSample(const AId, AText, AFgSourceId, ABgSourceId: string;
  APanelState: TColorSamplePanelState): TDialogControl;
begin
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

function BuildConfirmDialog(const ATitle, AMessage: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogConfirm, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'message', AMessage);
end;

function BuildDeleteDialog(const ATitle, AMessage, AOkText: string;
  AWarning: Boolean): TDialogDeclaration;
var
  OkCaption: string;
begin
  if AOkText <> '' then
    OkCaption := AOkText
  else
    OkCaption := T('ui.delete.okDefault', 'Delete');
  RequireDialogResource(cResDialogDelete, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'message', AMessage);
  DialogSetButtonText(Result, cDlgCmdOk, OkCaption);
  Result.IsWarning := AWarning;
end;

function BuildHelpDialog: TDialogDeclaration;
begin
  RequireDialogResource(cResDialogHelp, Result);
end;

function BuildInputDialog(const ATitle, APrompt, AValue: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogInput, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'name', AValue);
end;

function BuildSelectMaskDialog(const ATitle, APrompt, AValue: string;
  ASelectFolders: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSelectMask, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'name', AValue);
  DialogSetCheckbox(Result, 'select_folders', ASelectFolders);
end;

function BuildArchivePasswordDialog(const AArchiveName, APrompt: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogArchivePassword, Result);
  DialogSetLabelText(Result, 'archive', AArchiveName);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'password', '');
end;

function BuildAskSaveDialog(const AFileName: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogAskSave, Result);
  DialogSetLabelText(Result, 'filename', AFileName);
end;

function BuildSearchDialog(const AMask, AContaining: string;
  ACaseSensitive, AWholeWords, ASearchFolders, AUseRegex, ASubdirs: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSearch, Result);
  DialogSetInputValue(Result, 'search_mask', AMask);
  DialogSetInputValue(Result, 'search_text', AContaining);
  DialogSetCheckbox(Result, 'search_case', ACaseSensitive);
  DialogSetCheckbox(Result, 'search_words', AWholeWords);
  DialogSetCheckbox(Result, 'search_folders', ASearchFolders);
  DialogSetCheckbox(Result, 'search_regex', AUseRegex);
  DialogSetCheckbox(Result, 'search_subdirs', ASubdirs);
end;

function BuildCopyMoveDialog(const ATitle, APrompt, ADestPath: string;
  AOverwriteIndex: Integer; APreserveTimestamps: Boolean;
  AOnlyNewer, AFollowSymlinks: Boolean; ARetryIndex: Integer;
  AFilterEnabled: Boolean; const AExcludeMask: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogCopyMove, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'job_dest', ADestPath);
  DialogSetDropDownSelected(Result, 'job_existing', AOverwriteIndex);
  DialogSetDropDownSelected(Result, 'job_retry', ARetryIndex);
  DialogSetCheckbox(Result, 'job_timestamps', APreserveTimestamps);
  DialogSetCheckbox(Result, 'job_only_newer', AOnlyNewer);
  DialogSetCheckbox(Result, 'job_symlinks', AFollowSymlinks);
  DialogSetCheckbox(Result, 'job_filter', AFilterEnabled);
  DialogSetInputValue(Result, 'job_exclude', AExcludeMask);
  DialogSetButtonText(Result, cDlgCmdOk, ATitle);
end;

function BuildGotoLineDialog(ALine: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogGotoLine, Result);
  DialogSetInputValue(Result, 'line', IntToStr(ALine));
end;

function BuildEncodingDialog(ACurrent: string): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel, I: Integer;
begin
  RequireDialogResource(cResDialogEncoding, Result);
  Items := TextEncodingListItems;
  Sel := 0;
  for I := 0 to High(Items) do
    if SameText(Items[I], ACurrent) then
    begin
      Sel := I;
      Break;
    end;
  DialogSetListItems(Result, 'encoding', Items, Sel);
end;

function BuildReplaceDialog(const AFind, AReplace: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogReplace, Result);
  DialogSetInputValue(Result, 'find', AFind);
  DialogSetInputValue(Result, 'replace', AReplace);
end;

function BuildOverwriteAskDialog(const APath, ANewLine, AExistingLine: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogOverwriteAsk, Result);
  Result.IsWarning := True;
  DialogSetLabelText(Result, 'path', APath);
  DialogSetLabelText(Result, 'new_line', ANewLine);
  DialogSetLabelText(Result, 'existing_line', AExistingLine);
  DialogSetCheckbox(Result, 'remember', False);
end;

function BuildDeleteErrorDialog(const AHeadline, APath, AQuestion, AErrorLine: string;
  AOfferPermanent: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogDeleteError, Result);
  Result.IsWarning := True;
  DialogSetTitle(Result, 'Error');
  DialogSetLabelText(Result, 'headline', AHeadline);
  DialogSetLabelText(Result, 'path', APath);
  DialogSetLabelText(Result, 'question', AQuestion);
  DialogSetLabelText(Result, 'error_line', AErrorLine);
  if AOfferPermanent then
    DialogSetButtonText(Result, cDlgCmdDelete, 'Delete')
  else
  begin
    DialogSetButtonText(Result, cDlgCmdDelete, 'Retry');
    if AQuestion = '' then
      DialogSetLabelText(Result, 'question', 'Retry permanent delete?');
  end;
end;

function BuildIOErrorDialog(const AHeadline, APath, AErrorLine: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogIOError, Result);
  Result.IsWarning := True;
  DialogSetLabelText(Result, 'headline', AHeadline);
  DialogSetLabelText(Result, 'path', APath);
  DialogSetLabelText(Result, 'error_line', AErrorLine);
end;

function BuildFolderHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogFolderHistory, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'folders', Items, Sel);
end;

function BuildJobListDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogJobList, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(no jobs)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'jobs', Items, Sel);
end;

function BuildThemeDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Sel: Integer;
begin
  RequireDialogResource(cResDialogTheme, Result);
  Sel := ASelectedIndex;
  if Sel < 0 then
    Sel := 0;
  if Sel > High(AItems) then
    Sel := High(AItems);
  DialogSetListItems(Result, 'themes', AItems, Sel);
end;

function BuildFileHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogFileHistory, Result);
  Items := AItems;
  if Length(Items) = 0 then
    Items := [T('ui.fileHistory.empty', '(empty)')];
  DialogSetListItems(Result, 'files', Items,
    EnsureRange(ASelectedIndex, 0, High(Items)));
end;

function BuildCmdHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogCmdHistory, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'commands', Items, Sel);
end;

function BuildFolderHotlistDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogFolderHotlist, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty - Ctrl+Alt+D adds the current directory)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'hotlist', Items, Sel);
end;

function BuildWorkspaceLibraryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const ALiveCaption: string): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
  Title: string;
begin
  RequireDialogResource(cResDialogWorkspaces, Result);
  Title := T('ui.workspaces.dialogTitle', 'Workspaces');
  if ALiveCaption <> '' then
    Title := Title + ' ' + #$2014 + ' ' + ALiveCaption;
  DialogSetTitle(Result, Title);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty - Ins saves the current workspace)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'workspaces', Items, Sel);
end;

function BuildSshConnectionsDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogSshConnections, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty - Ins adds a connection)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'connections', Items, Sel);
end;

function BuildSshConnectionEditDialog(const AName, AHost: string; APort: Integer;
  const AUser, AIdentityFile: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSshConnectionEdit, Result);
  DialogSetInputValue(Result, 'name', AName);
  DialogSetInputValue(Result, 'host', AHost);
  DialogSetInputValue(Result, 'port', IntToStr(APort));
  DialogSetInputValue(Result, 'user', AUser);
  DialogSetInputValue(Result, 'identityfile', AIdentityFile);
end;

function BuildAssociationsDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogAssociations, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(empty - Ins adds an association)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'associations', Items, Sel);
end;

function BuildAssociationEditDialog(const AExtension: string; AActionIndex: Integer;
  const ACommand: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogAssociationEdit, Result);
  DialogSetInputValue(Result, 'extension', AExtension);
  DialogSetDropDownSelected(Result, 'action', AActionIndex);
  DialogSetInputValue(Result, 'command', ACommand);
end;

function BuildUserMenuEditDialog(const AHotKey, ACaption, ACommand: string;
  AKindIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogUserMenuEdit, Result);
  DialogSetInputValue(Result, 'hotkey', AHotKey);
  DialogSetInputValue(Result, 'caption', ACaption);
  DialogSetInputValue(Result, 'command', ACommand);
  // Dropdown items are user-facing choices, not static captions, so the
  // translation pass skips them; translate here.
  DialogSetListItems(Result, 'kind', [
    T('ui.userMenu.kindCommand', 'Command'),
    T('ui.userMenu.kindSubmenu', 'Submenu'),
    T('ui.userMenu.kindSeparator', 'Separator')], AKindIndex);
end;

function BuildCreateLinkDialog(const ALinkName, ATarget: string;
  ALinkTypeIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogCreateLink, Result);
  DialogSetInputValue(Result, 'link_name', ALinkName);
  DialogSetInputValue(Result, 'target', ATarget);
  DialogSetDropDownSelected(Result, 'link_type', ALinkTypeIndex);
end;

function BuildSetAttributesDialog(const ASummary, AOwnerNow, AOwnerEdit: string;
  AReadOnlyIdx, AHiddenIdx, AArchiveIdx, ASystemIdx: Integer;
  const ACreated, AModified, AAccessed: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSetAttr, Result);
  DialogSetLabelText(Result, 'summary', ASummary);
  DialogSetLabelText(Result, 'owner_now', AOwnerNow);
  DialogSetInputValue(Result, 'owner', AOwnerEdit);
  DialogSetDropDownSelected(Result, 'attr_ro', AReadOnlyIdx);
  DialogSetDropDownSelected(Result, 'attr_h', AHiddenIdx);
  DialogSetDropDownSelected(Result, 'attr_a', AArchiveIdx);
  DialogSetDropDownSelected(Result, 'attr_s', ASystemIdx);
  DialogSetCheckbox(Result, 'change_owner', False);
  DialogSetCheckbox(Result, 'recurse', False);
  DialogSetInputValue(Result, 'date_created', ACreated);
  DialogSetInputValue(Result, 'date_modified', AModified);
  DialogSetInputValue(Result, 'date_accessed', AAccessed);
  DialogSetLabelText(Result, 'date_error', '');
end;

function BuildDirSyncDialog(const ASrcPath, ADstPath, AStatus: string;
  const APreview: TArray<string>; ADryRun: Boolean;
  ATwoWay: Boolean; AByContent: Boolean): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogDirSync, Result);
  DialogSetLabelText(Result, 'src_path', ASrcPath);
  DialogSetLabelText(Result, 'dst_path', ADstPath);
  DialogSetLabelText(Result, 'status', AStatus);
  if Length(APreview) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(none)';
  end
  else
    Items := APreview;
  DialogSetListItems(Result, 'preview', Items, 0);
  DialogSetCheckbox(Result, 'dry_run', ADryRun);
  if ATwoWay then
    DialogSetRadio(Result, 'sync_mode', 'twoway')
  else
    DialogSetRadio(Result, 'sync_mode', 'oneway');
  if AByContent then
    DialogSetRadio(Result, 'compare_by', 'bycontent')
  else
    DialogSetRadio(Result, 'compare_by', 'bydate');
end;

function BuildFileDiffDialog(const ALeftName, ARightName, AStatus: string;
  const ALines: TArray<string>): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogFileDiff, Result);
  DialogSetLabelText(Result, 'left_name', ALeftName);
  DialogSetLabelText(Result, 'right_name', ARightName);
  DialogSetLabelText(Result, 'status', AStatus);
  if Length(ALines) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(none)';
  end
  else
    Items := ALines;
  DialogSetListItems(Result, 'diff', Items, 0);
end;

function BuildColumnsConfigDialog(AShowExt, AShowSize, AShowModified,
  AShowCreated, AShowAccessed, AShowType, AShowAttr: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogColumnsConfig, Result);
  DialogSetCheckbox(Result, 'col_ext', AShowExt);
  DialogSetCheckbox(Result, 'col_size', AShowSize);
  DialogSetCheckbox(Result, 'col_modified', AShowModified);
  DialogSetCheckbox(Result, 'col_created', AShowCreated);
  DialogSetCheckbox(Result, 'col_accessed', AShowAccessed);
  DialogSetCheckbox(Result, 'col_type', AShowType);
  DialogSetCheckbox(Result, 'col_attr', AShowAttr);
end;

function BuildChecksumOptionsDialog(AAlgoIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogChecksumOpts, Result);
  DialogSetDropDownSelected(Result, 'algo', AAlgoIndex);
end;

function BuildChecksumResultDialog(const ATitle, AStatus: string;
  const ALines: TArray<string>; AVerify: Boolean): TDialogDeclaration;
var
  I: Integer;
begin
  RequireDialogResource(cResDialogChecksum, Result);
  DialogSetTitle(Result, ATitle);
  // Padded: the label keeps the width of its first text, and Copy / Save
  // write longer messages into it later.
  DialogSetLabelText(Result, 'status', AStatus + StringOfChar(' ', Max(74 - Length(AStatus), 0)));
  if Length(ALines) = 0 then
    DialogSetListItems(Result, 'lines', ['(none)'], 0)
  else
    DialogSetListItems(Result, 'lines', ALines, 0);
  if AVerify then
    for I := High(Result.Controls) downto 0 do
      if Result.Controls[I].Id = 'save' then
        Delete(Result.Controls, I, 1);
end;

function BuildExternalToolsDialog(const AViewer, AEditor: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogExternalTools, Result);
  DialogSetInputValue(Result, 'viewer', AViewer);
  DialogSetInputValue(Result, 'editor', AEditor);
end;

function BuildDisplayDialog(const AFontNames: TArray<string>;
  AFontIndex, ASizeIndex, AZoomIndex, ABlinkMsIndex: Integer;
  ABlink, AShowIcons: Boolean; const ANote: string;
  const ALanguageNames: TArray<string>; ALanguageIndex: Integer): TDialogDeclaration;
var
  Fonts, Languages: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogDisplay, Result);
  if Length(AFontNames) = 0 then
  begin
    SetLength(Fonts, 1);
    Fonts[0] := 'Consolas';
    Sel := 0;
  end
  else
  begin
    Fonts := AFontNames;
    Sel := AFontIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Fonts) then
      Sel := High(Fonts);
  end;
  DialogSetListItems(Result, 'fonts', Fonts, Sel);
  DialogSetListItems(Result, 'font_size', DisplayFontSizeItems, ASizeIndex);
  DialogSetListItems(Result, 'zoom', DisplayZoomItems, AZoomIndex);
  DialogSetListItems(Result, 'blink_ms', DisplayBlinkMsItems, ABlinkMsIndex);
  DialogSetCheckbox(Result, 'blink', ABlink);
  DialogSetCheckbox(Result, 'panel_icons', AShowIcons);
  DialogSetLabelText(Result, 'font_note', ANote);

  if Length(ALanguageNames) = 0 then
  begin
    SetLength(Languages, 1);
    Languages[0] := 'English';
    Sel := 0;
  end
  else
  begin
    Languages := ALanguageNames;
    Sel := ALanguageIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Languages) then
      Sel := High(Languages);
  end;
  DialogSetListItems(Result, 'language', Languages, Sel);
end;

function BuildShellProfileListDialog(const ATitle: string;
  const ATitles: TArray<string>; ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogTerminalProfile, Result);
  DialogSetTitle(Result, ATitle);
  if Length(ATitles) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(none)';
    Sel := 0;
  end
  else
  begin
    Items := ATitles;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'profiles', Items, Sel);
end;

function BuildTerminalProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
begin
  Result := BuildShellProfileListDialog('New terminal', ATitles, ASelectedIndex);
end;

function BuildConsoleProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer; AStartOnLaunch: Boolean): TDialogDeclaration;
var
  I, N: Integer;
begin
  Result := BuildShellProfileListDialog('Background console', ATitles, ASelectedIndex);
  // Checkbox sits under the profile list; the shared terminal-profile
  // resource has no room for it, so only this dialog grows.
  Result.Height := Result.Height + 2;
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Kind = dckButton then
      Inc(Result.Controls[I].Row, 2);
  N := Length(Result.Controls);
  SetLength(Result.Controls, N + 1);
  Result.Controls[N] := WithControlBox(
    MakeCheckbox('start_on_launch',
      T('ui.consoleProfile.startOnLaunch', 'Start shell at program launch'),
      AStartOnLaunch),
    1, 14, Result.Width - 4, 1);
end;

function BuildPluginListDialog(const AItems: TArray<string>): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogPluginList, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(no plugins loaded)';
  end
  else
    Items := AItems;
  DialogSetListItems(Result, 'plugins', Items, 0);
end;

function BuildColorCodingDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogColorCoding, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(no groups - press Ins to add one)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'groups', Items, Sel);
end;

function BuildColorCodingEditDialog(const AName, AMask: string;
  AApplyToIndex: Integer; AEnabled: Boolean;
  const ANormalFg, ANormalBg, ASelectedFg, ASelectedBg,
  ACurrentFg, ACurrentBg: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogColorCodingEdit, Result);
  DialogSetInputValue(Result, 'cc_name', AName);
  DialogSetInputValue(Result, 'cc_mask', AMask);
  DialogSetDropDownSelected(Result, 'cc_applyto', AApplyToIndex);
  DialogSetCheckbox(Result, 'cc_enabled', AEnabled);
  DialogSetInputValue(Result, 'cc_normal_fg', ANormalFg);
  DialogSetInputValue(Result, 'cc_normal_bg', ANormalBg);
  DialogSetInputValue(Result, 'cc_selected_fg', ASelectedFg);
  DialogSetInputValue(Result, 'cc_selected_bg', ASelectedBg);
  DialogSetInputValue(Result, 'cc_current_fg', ACurrentFg);
  DialogSetInputValue(Result, 'cc_current_bg', ACurrentBg);
end;

function BuildColorPickerDialog(const ATitle, ACurrentHex: string;
  const APresetLabels: TArray<string>; APresetIndex: Integer;
  AIsBg: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogColorPicker, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetListItems(Result, 'picker_presets', APresetLabels, APresetIndex);
  DialogSetInputValue(Result, 'picker_hex', ACurrentHex);
  if AIsBg then
    DialogSetColorSampleSources(Result, 'preview', '', 'picker_hex')
  else
    DialogSetColorSampleSources(Result, 'preview', 'picker_hex', '');
end;

function BuildUpdateOfferDialog(const ANewVersion, ACurrentVersion: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogUpdate, Result);
  DialogSetLabelText(Result, 'message', T('ui.update.offer',
    'Version %s is available (installed: %s).', [ANewVersion, ACurrentVersion]));
  DialogSetLabelText(Result, 'details', T('ui.update.offerDetails', 'Download and install it?'));
end;

function BuildUpdateMessageDialog(const AMessage, ADetails, AOkText: string;
  AShowCancel: Boolean; const ACancelText: string): TDialogDeclaration;
var
  I, J: Integer;
begin
  RequireDialogResource(cResDialogUpdateMsg, Result);
  DialogSetLabelText(Result, 'message', AMessage);
  DialogSetLabelText(Result, 'details', ADetails);
  if AOkText <> '' then
    DialogSetButtonText(Result, cDlgCmdOk, AOkText);
  if AShowCancel then
  begin
    if ACancelText <> '' then
      DialogSetButtonText(Result, cDlgCmdCancel, ACancelText);
    Exit;
  end;
  // Single-button message: drop cancel, centre OK and let Esc close via OK.
  for I := High(Result.Controls) downto 0 do
    if SameText(Result.Controls[I].Id, cDlgCmdCancel) then
    begin
      for J := I to High(Result.Controls) - 1 do
        Result.Controls[J] := Result.Controls[J + 1];
      SetLength(Result.Controls, Length(Result.Controls) - 1);
    end
    else if SameText(Result.Controls[I].Id, cDlgCmdOk) then
    begin
      Result.Controls[I].Col := (Result.Width - 2 - Result.Controls[I].BoxW) div 2;
      Result.Controls[I].IsCancel := True;
    end;
end;

function BuildUpdatesDialog(const ACurrentVersion: string;
  ACheckOnStart: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogUpdates, Result);
  DialogSetLabelText(Result, 'version', T('ui.update.current', 'Installed version: %s.',
    [ACurrentVersion]));
  DialogSetCheckbox(Result, 'check_on_start', ACheckOnStart);
end;

function BuildAboutDialog: TDialogDeclaration;
var
  Engine, Ver: string;
begin
  RequireDialogResource(cResDialogAbout, Result);

  // --no-skia wins even if GlobalUseSkia was already captured by the canvas.
  {$IFDEF SKIA}
  if GlobalUseSkia and not NoSkiaRequested then
    Engine := T('ui.about.engine.skia', 'Graphics Engine: Skia (mono AA + modal dim)')
  else
    Engine := T('ui.about.engine.gdi', 'Graphics Engine: Standard GDI/FMX Renderer');
  {$ELSE}
  Engine := T('ui.about.engine.gdi', 'Graphics Engine: Standard GDI/FMX Renderer');
  {$ENDIF}
  DialogSetLabelText(Result, 'lbl_skia', Engine);

  Ver := AppVersionString;
  if Ver = '' then
    Ver := '?';
  DialogSetLabelText(Result, 'lbl_version', T('ui.about.version', 'Version %s', [Ver]));
  // RequireDialogResource already fitted the English JSON captions. These two
  // lines are longer in translation, so measure them again or the single-row
  // label clips (DrawLabel keeps only the first wrapped line).
  if not SameText(CurrentLocale, 'en') then
    FitDialogToTranslatedText(Result);
end;

function BuildKeymapDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogKeymap, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(no actions)';
    Sel := 0;
  end
  else
  begin
    Items := AItems;
    Sel := ASelectedIndex;
    if Sel < 0 then
      Sel := 0;
    if Sel > High(Items) then
      Sel := High(Items);
  end;
  DialogSetListItems(Result, 'actions', Items, Sel);
end;

function BuildKeymapEditDialog(const AActionName, AKeysText,
  AStatus: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogKeymapEdit, Result);
  DialogSetLabelText(Result, 'km_action', 'Action: ' + AActionName);
  DialogSetInputValue(Result, 'km_keys', AKeysText);
  DialogSetLabelText(Result, 'km_status', AStatus);
end;

end.
