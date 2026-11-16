unit uDialogBuilders;

{ Factories that load a dialog resource and fill its fields. Types and Make*
  helpers stay in uDialogTypes. }

interface

uses
  System.SysUtils, System.UITypes,
  uDialogTypes, uMultiRename, uListExport, uFileFind;

function BuildConfirmDialog(const ATitle, AMessage: string): TDialogDeclaration;
function BuildDeleteDialog(const ATitle, AMessage, AOkText: string;
  AWarning: Boolean = False): TDialogDeclaration;
/// <summary>The delete confirmation for one item: APrefix, AName (accent
/// color) and ASuffix on three lines; the dialog is as wide as the longest.</summary>
function BuildDeleteNameDialog(const ATitle, APrefix, AName, ASuffix, AOkText: string;
  AWarning: Boolean = False): TDialogDeclaration;
function BuildHelpDialog: TDialogDeclaration;
function BuildInputDialog(const ATitle, APrompt, AValue: string): TDialogDeclaration;
/// <summary>Panel filter: AItems are the ready-made filters (the first one
/// is "no filter"), ACurrentMask goes into the custom mask line.</summary>
function BuildPanelFilterDialog(const AItems: TArray<string>;
  const ACurrentMask: string): TDialogDeclaration;
function BuildSelectMaskDialog(const ATitle, APrompt, AValue: string;
  ASelectFolders: Boolean): TDialogDeclaration;
/// <summary>Mask groups: AItems are the list rows, ASelected the row to select,
/// AName and AMasks fill the two edit lines.</summary>
function BuildMaskGroupsDialog(const AItems: TArray<string>; ASelected: Integer;
  const AName, AMasks: string): TDialogDeclaration;
function BuildArchivePasswordDialog(const AArchiveName, APrompt: string): TDialogDeclaration;
function BuildAskSaveDialog(const AFileName: string): TDialogDeclaration;
function BuildSearchDialog(const AMask, AContaining: string;
  ACaseSensitive, AWholeWords, ASearchFolders, AUseRegex: Boolean;
  const AHex: string; ASubdirs, ASearchArchives: Boolean; AEncodingIdx: Integer;
  const AFilters: TFindFilterText): TDialogDeclaration;
function BuildCopyMoveDialog(const ATitle, APrompt, ADestPath: string;
  AOverwriteIndex: Integer = 0; APreserveTimestamps: Boolean = False;
  AOnlyNewer: Boolean = False; AFollowSymlinks: Boolean = False;
  ARetryIndex: Integer = 1; AFilterEnabled: Boolean = False;
  const AExcludeMask: string = '*.tmp;*.bak;~*'): TDialogDeclaration;
/// <summary>The Pack job's confirm dialog: the Copy / Move one plus the archive
/// type (ATypeIndex: 0 zip, 1 7z), a password and the encrypted-names choice.</summary>
function BuildPackDialog(const ATitle, APrompt, ADestPath: string;
  ATypeIndex: Integer): TDialogDeclaration;
function BuildGotoLineDialog(ALine: Integer): TDialogDeclaration;
function BuildEncodingDialog(ACurrent: string): TDialogDeclaration;
/// <summary>F7 in the editor and viewer: the text to find, its search options
/// (case, whole words, regular expression, reverse direction) and the Word /
/// Selection buttons that fill the field from the text under the cursor.</summary>
function BuildEditFindDialog(const AFind: string; AMatchCase: Boolean = False;
  AWholeWord: Boolean = False; ARegex: Boolean = False;
  AReverse: Boolean = False): TDialogDeclaration;
/// <summary>The question of a step-by-step replace: the text looked for, what
/// it is replaced with (both in the accent style) and the line that holds the
/// match, with the match itself in the accent style (APre + AHit + APost),
/// buttons Replace / All / Skip / Cancel.</summary>
function BuildReplaceAskDialog(const AFind, AReplacement: string; ALineNo: Integer;
  const APre, AHit, APost: string): TDialogDeclaration;
function BuildReplaceDialog(const AFind, AReplace: string; AMatchCase: Boolean = False;
  AWholeWord: Boolean = False; ARegex: Boolean = False;
  AReverse: Boolean = False): TDialogDeclaration;
function BuildOverwriteAskDialog(const APath, ANewLine, AExistingLine: string): TDialogDeclaration;
function BuildDeleteErrorDialog(const AHeadline, APath, AQuestion, AErrorLine: string;
  AOfferPermanent: Boolean; AOfferElevate: Boolean = False): TDialogDeclaration;
function BuildIOErrorDialog(const AHeadline, APath, AErrorLine: string;
  AOfferElevate: Boolean = False): TDialogDeclaration;
function BuildFolderHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildJobListDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildCmdHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>Alt+F11: AItems are "mode mark + path" labels, newest first.</summary>
function BuildFileHistoryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>Shift+F9: AItems are the rows of the matching menu commands, AQuery
/// the search text shown in the field above them.</summary>
function BuildCommandPaletteDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0; const AQuery: string = ''): TDialogDeclaration;
/// <summary>AItems are pre-formatted rows (on/off mark, id, name, version),
/// see HostPluginRows in uPluginHost.pas.</summary>
function BuildPluginListDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
/// <summary>The information dialog of one plugin: ATitle (its name), ALines are the
/// rows of the read-only text; without AHasHelp the Help button is dropped.</summary>
function BuildPluginInfoDialog(const ATitle: string; const ALines: TArray<string>;
  AHasHelp: Boolean): TDialogDeclaration;
/// <summary>What the user may allow a plugin: AOverrideText is the checkbox of replacing
/// built-in handlers (dropped when AHasOverride is False), APermTexts the checkboxes of
/// its permissions (ids perm_0, perm_1, ...; at most two). The checkboxes that stay are
/// packed from the top.</summary>
function BuildPluginPermissionsDialog(const ATitle, AIntro, AOverrideText: string;
  AHasOverride, AOverrideOn: Boolean; const APermTexts: TArray<string>;
  const AGranted: TArray<Boolean>): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels ("Name  -  path" or
/// bare path when unnamed) - see FolderHotlistDisplayLabel.</summary>
function BuildFolderHotlistDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0;
  const AAccents: TArray<TListAccent> = nil): TDialogDeclaration;
function BuildWorkspaceLibraryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const ALiveCaption: string;
  const ATitle: string = ''): TDialogDeclaration;
function BuildCreateLinkDialog(const ALinkName, ATarget: string;
  ALinkTypeIndex: Integer = 0): TDialogDeclaration;
/// <summary>ACreated / AModified / AAccessed: date text for the three time
/// fields ('' = differs between the items / unknown).</summary>
function BuildSetAttributesDialog(const ASummary, AOwnerNow, AOwnerEdit: string;
  const ACreated, AModified, AAccessed: string): TDialogDeclaration;
/// <summary>The permissions dialog (octal mode, owner and group) of POSIX
/// builds; AMode holds the permission bits of the first item and the flags are
/// the chattr flags every item has.</summary>
function BuildSetModeDialog(const ASummary, AOwner, AGroup: string;
  AMode: Integer; AImmutable, AAppendOnly, ANoDump: Boolean): TDialogDeclaration;
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
  AKindIndex: Integer; AReturnModeIndex: Integer = 0): TDialogDeclaration;
function BuildDirSyncDialog(const ASrcPath, ADstPath, AStatus: string;
  const APreview: TArray<string>; ADryRun: Boolean = False;
  ATwoWay: Boolean = False; AByContent: Boolean = False): TDialogDeclaration;
function BuildFileDiffDialog(const ALeftName, ARightName, AStatus: string;
  const ASummary: TArray<string>; const ASwatches: TArray<TListSwatch>;
  const ALines: TArray<string>): TDialogDeclaration;
/// <summary>Group compare result: one row per same-named pair, colored by the
/// swatches; Enter on a row accepts (the list id is "pairs").</summary>
function BuildCompareGroupDialog(const AStatus: string;
  const AItems: TArray<string>; const ASwatches: TArray<TListSwatch>;
  ASelected: Integer): TDialogDeclaration;
/// <summary>Options > Columns... - which fields pcmCustom shows. One
/// checkbox per flag; caller (uDualPanelWindow.OpenColumnsConfigDialog)
/// passes the active panel's current values.</summary>
/// <summary>AScheme is the scheme of the current folder: the built-in columns its
/// plugin excluded (BuiltinColumnAvailable) get no checkbox, and the columns it
/// declared get one each, ids "pcol_0", "pcol_1", ... in declaration order,
/// checked by IsPluginColumnShown. ASetItems are the rows of the column sets
/// list (list id "sets").</summary>
function BuildColumnsConfigDialog(AShowExt, AShowSize, AShowModified,
  AShowCreated, AShowAccessed, AShowType, AShowAttr: Boolean;
  const AScheme: string = '';
  const ASetItems: TArray<string> = nil): TDialogDeclaration;
/// <summary>Files > Export list...: target file, layout and the fields of the
/// saved list, prefilled from AConfig.</summary>
function BuildExportListDialog(const APath: string;
  const AConfig: TListExportConfig): TDialogDeclaration;
function BuildDisplayDialog(const AFontNames: TArray<string>;
  AFontIndex, ASizeIndex, AZoomIndex, ABlinkMsIndex: Integer;
  ABlink, AShowIcons: Boolean; const ANote: string;
  AShadowIndex: Integer = 0;
  ALineSpacing: Boolean = False; AMarkedRowIndex: Integer = 0;
  ASnapFontSize: Boolean = False; ATextContrastIndex: Integer = 0;
  ACellWidthExtra: Integer = 0; ACellHeightExtra: Integer = 0): TDialogDeclaration;
/// <summary>Options > User interface...: language, notifications and the
/// check boxes for the bars, menu, mouse and editor behavior. The check boxes
/// are filled by the caller (DialogSetCheckbox).</summary>
function BuildInterfaceDialog(const ALanguageNames: TArray<string>;
  ALanguageIndex: Integer; AShowNotifications: Boolean = True): TDialogDeclaration;
/// <summary>Options > External viewer/editor...: the Alt+F3 / Alt+F4 command
/// templates (uExternalTools).</summary>
function BuildExternalToolsDialog(const AViewer, AEditor: string): TDialogDeclaration;
/// <summary>Options > Console...: scrollback size (index in
/// uConsoleSettings.ScrollbackItems), paste confirmation, trimming of spaces,
/// return to the panels after a command from the panels' command line.</summary>
function BuildConsoleOptionsDialog(AScrollbackIndex: Integer; AConfirmPaste,
  ATrimCopy, ATrimPaste: Boolean; AReturnToPanels: Boolean = False;
  ABackgroundShowIndex: Integer = 2): TDialogDeclaration;
/// <summary>Export / import of the settings: a path field with a drop-down list
/// of the files used before (input history "settingsfile").</summary>
function BuildSettingsFileDialog(const ATitle, APrompt, APath: string): TDialogDeclaration;
const
  /// <summary>Text lines of the settings location dialog, and the cells each holds.</summary>
  cConfigLocationLines = 8;
  cConfigLocationTextWidth = 72;

/// <summary>Options > Settings location...: up to cConfigLocationLines
/// ready-made text lines (the dialog does not wrap them) and the caption of
/// the default button.</summary>
function BuildConfigLocationDialog(const ATitle: string;
  const ALines: TArray<string>; const AOkText: string): TDialogDeclaration;
/// <summary>Options > Markdown colors...: a foreground / background hex
/// input per Markdown span kind (ids md_<key>_fg / md_<key>_bg, see
/// uMarkdownColors.MdSpanKindKey); the caller fills them in.</summary>
function BuildMarkdownColorsDialog: TDialogDeclaration;
/// <summary>Import of an Obsidian theme into the Markdown colors: path of
/// theme.css and the palette (0 = dark, 1 = light).</summary>
function BuildMarkdownImportDialog(const APath: string; APaletteIndex: Integer): TDialogDeclaration;
/// <summary>Files > Checksums...: algorithm dropdown (index into
/// uChecksums.TChecksumAlgo order: MD5, SHA-1, SHA-256, SHA-512).</summary>
function BuildChecksumOptionsDialog(AAlgoIndex: Integer): TDialogDeclaration;
/// <summary>Commands > Compare folders: what counts as a difference.</summary>
function BuildCompareOptionsDialog(AByTime, ABySize, AByContent: Boolean): TDialogDeclaration;
/// <summary>Files > Multi-rename...: the rule fields filled from ARules, the
/// dialog AWidth cells wide (the fields and the list stretch with it); the
/// preview list is filled by the caller.</summary>
function BuildMultiRenameDialog(const ARules: TMultiRenameRules;
  AWidth: Integer): TDialogDeclaration;
/// <summary>Checksum result list; AVerify drops the Save button (the
/// lines are OK / FAILED marks, not a checksum file).</summary>
function BuildChecksumResultDialog(const ATitle, AStatus: string;
  const ALines: TArray<string>; AVerify: Boolean): TDialogDeclaration;
/// <summary>AAccents: the quick-launch key cells of the rows.</summary>
/// <summary>The list that picks the environment profile (uEnvProfiles) of a
/// shell profile: AItems with the "none" row first, ASelectedIndex the current
/// one.</summary>
function BuildTerminalEnvDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
function BuildTerminalProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer = 0;
  const AAccents: TArray<TListAccent> = nil): TDialogDeclaration;
function BuildConsoleProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer = 0; AStartOnLaunch: Boolean = False;
  ACwdToPanels: Boolean = True;
  AProgramsInTerminal: Boolean = False): TDialogDeclaration;
function BuildAboutDialog: TDialogDeclaration;
/// <summary>Update offer: buttons update / later (Esc) / skip.</summary>
function BuildUpdateOfferDialog(const ANewVersion, ACurrentVersion: string): TDialogDeclaration;
/// <summary>Two-line updater message; buttons ok / cancel (Esc). '' keeps a
/// button's translated resource caption; AShowCancel = False leaves a single
/// OK that Esc also triggers.</summary>
function BuildUpdateMessageDialog(const AMessage, ADetails, AOkText: string;
  AShowCancel: Boolean; const ACancelText: string = ''): TDialogDeclaration;
/// <summary>A notice with three text lines and a "Don't show this again"
/// checkbox (id hide); one OK button that Esc also triggers.</summary>
function BuildHideableMessageDialog(const AMessage, ADetails, AHint: string): TDialogDeclaration;
/// <summary>Help > Updates: installed version, the check_on_start,
/// show_check_notice and dev_channel checkboxes, buttons check / close (Esc).</summary>
function BuildUpdatesDialog(const ACurrentVersion: string;
  ACheckOnStart, AShowCheckNotice, ADevChannel: Boolean): TDialogDeclaration;
/// <summary>AItems are pre-formatted display labels - see
/// ColorCodingDisplayLabel in uColorCodingEditHelpers.pas.</summary>
function BuildColorCodingDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0;
  const ASwatches: TArray<TListSwatch> = nil): TDialogDeclaration;
function BuildColorCodingEditDialog(const AName, AMask: string;
  AApplyToIndex: Integer; AEnabled: Boolean; const APriority, AWhen: string;
  const ANormalFg, ANormalBg, ASelectedFg, ASelectedBg,
  ACurrentFg, ACurrentBg: string): TDialogDeclaration;
/// <summary>The color picker dialog, starting on AColor (which is also what
/// its "was" swatch shows).</summary>
function BuildColorPickerDialog(const ATitle: string; AColor: TAlphaColor): TDialogDeclaration;
/// <summary>The date picker: a calendar on ADate (0 = today) and a time field
/// holding ATime ('' = no time).</summary>
function BuildDatePickerDialog(const ATitle: string; ADate: TDateTime;
  const ATime: string): TDialogDeclaration;
/// <summary>AItems are pre-formatted "Action  Hotkeys" rows - see
/// TKeymapDialogController.ActionRowLabel in uDualPanelKeymapDialog.pas.</summary>
function BuildKeymapDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer = 0): TDialogDeclaration;
function BuildKeymapEditDialog(const AActionName, AKeysText,
  AStatus: string): TDialogDeclaration;

implementation

uses
  System.Math, System.StrUtils,
  uDialogResources, uFileAttrTypes, uDialogLocaleLayout, uDisplaySettings,
  uConsoleSettings, uStrings, uUpdater, uThemeDrawing, uPluginColumns,
  uTextEncoding, uInputLine, uColorPickerControl, uDatePickerControl,
  uTerminalTypes;

function BuildConfirmDialog(const ATitle, AMessage: string): TDialogDeclaration;
var
  I, Delta: Integer;
begin
  RequireDialogResource(cResDialogConfirm, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'message', AMessage);
  // The frame is as wide as the message needs (a translation is longer than
  // the template text); the buttons keep their place relative to the center.
  Delta := Min(Max(0, Length(AMessage) + 4 - Result.Width), 100 - Result.Width);
  if Delta > 0 then
  begin
    Result.Width := Result.Width + Delta;
    for I := 0 to High(Result.Controls) do
      case Result.Controls[I].Kind of
        dckLabel:
          Result.Controls[I].BoxW := Result.Width - 4;
        dckButton:
          Inc(Result.Controls[I].Col, Delta div 2);
      end;
  end;
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

function BuildDeleteNameDialog(const ATitle, APrefix, AName, ASuffix, AOkText: string;
  AWarning: Boolean): TDialogDeclaration;
const
  cMaxName = 90;
var
  I, N, Delta, TextW: Integer;
  Name: string;
begin
  Result := BuildDeleteDialog(ATitle, APrefix, AOkText, AWarning);
  Name := AName;
  if Length(Name) > cMaxName then
    Name := Copy(Name, 1, (cMaxName - 3) div 2) + '...' +
      Copy(Name, Length(Name) - (cMaxName - 3) div 2 + 1, MaxInt);
  TextW := Max(Length(APrefix), Max(Length(Name), Length(ASuffix)));
  Delta := Max(0, TextW + 4 - Result.Width);
  Result.Width := Result.Width + Delta;
  Result.Height := Result.Height + 2;
  for I := 0 to High(Result.Controls) do
    case Result.Controls[I].Kind of
      dckLabel:
        Result.Controls[I].BoxW := Result.Width - 4;
      dckButton:
        begin
          Inc(Result.Controls[I].Row, 2);
          Inc(Result.Controls[I].Col, Delta div 2);
        end;
    end;
  N := Length(Result.Controls);
  SetLength(Result.Controls, N + 2);
  // The client area is two cells narrower than the frame.
  Result.Controls[N] := WithControlBox(MakeLabel(Name, 'name'),
    Max(1, (Result.Width - 2 - Length(Name)) div 2), 2, Min(Length(Name), Result.Width - 4), 1);
  Result.Controls[N].Accent := True;
  Result.Controls[N + 1] := WithControlBox(MakeLabel(ASuffix, 'suffix'), 1, 3,
    Result.Width - 4, 1);
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

function BuildMaskGroupsDialog(const AItems: TArray<string>; ASelected: Integer;
  const AName, AMasks: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogMaskGroups, Result);
  DialogSetListItems(Result, 'groups', AItems, ASelected);
  DialogSetInputValue(Result, 'gname', AName);
  DialogSetInputValue(Result, 'gmasks', AMasks);
end;

function BuildPanelFilterDialog(const AItems: TArray<string>;
  const ACurrentMask: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogPanelFilter, Result);
  DialogSetListItems(Result, 'presets', AItems, 0);
  DialogSetInputValue(Result, 'mask', ACurrentMask);
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
  ACaseSensitive, AWholeWords, ASearchFolders, AUseRegex: Boolean;
  const AHex: string; ASubdirs, ASearchArchives: Boolean; AEncodingIdx: Integer;
  const AFilters: TFindFilterText): TDialogDeclaration;
var
  Items: TArray<string>;
  I: Integer;
begin
  RequireDialogResource(cResDialogSearch, Result);
  DialogSetInputValue(Result, 'search_mask', AMask);
  DialogSetInputValue(Result, 'search_text', AContaining);
  DialogSetCheckbox(Result, 'search_case', ACaseSensitive);
  DialogSetCheckbox(Result, 'search_words', AWholeWords);
  DialogSetCheckbox(Result, 'search_folders', ASearchFolders);
  DialogSetCheckbox(Result, 'search_regex', AUseRegex);
  DialogSetInputValue(Result, 'search_hex', AHex);
  DialogSetCheckbox(Result, 'search_subdirs', ASubdirs);
  DialogSetCheckbox(Result, 'search_archives', ASearchArchives);
  // Item 0 lets the search detect the encoding of every file; the others are
  // the encodings of the editor, in the same order.
  Items := TextEncodingListItems;
  SetLength(Items, Length(Items) + 1);
  for I := High(Items) downto 1 do
    Items[I] := Items[I - 1];
  Items[0] := T('ui.search.encodingAuto', 'Auto-detect');
  DialogSetListItems(Result, 'search_encoding', Items, AEncodingIdx);
  DialogSetInputValue(Result, 'filter_size_min', AFilters.SizeMin);
  DialogSetInputValue(Result, 'filter_size_max', AFilters.SizeMax);
  DialogSetInputValue(Result, 'filter_date_from', AFilters.DateFrom);
  DialogSetInputValue(Result, 'filter_date_to', AFilters.DateTo);
  DialogSetTriState(Result, 'filter_attr_ro', Ord(AFilters.AttrReadOnly));
  DialogSetTriState(Result, 'filter_attr_hidden', Ord(AFilters.AttrHidden));
  DialogSetTriState(Result, 'filter_attr_system', Ord(AFilters.AttrSystem));
  DialogSetTriState(Result, 'filter_attr_archive', Ord(AFilters.AttrArchive));
  DialogSetLabelText(Result, 'lbl_format', Format(T('ui.search.filterFormat',
    'Size: 10K, 1.5M   Date: %s'), [DateToStr(EncodeDate(2026, 10, 27)) + ' [12:00]']));
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

function BuildPackDialog(const ATitle, APrompt, ADestPath: string;
  ATypeIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogPack, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'job_dest', ADestPath);
  DialogSetDropDownSelected(Result, 'pack_type', ATypeIndex);
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

function BuildEditFindDialog(const AFind: string; AMatchCase, AWholeWord, ARegex,
  AReverse: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogEditFind, Result);
  DialogSetInputValue(Result, 'find', AFind);
  DialogSetCheckbox(Result, 'opt_case', AMatchCase);
  DialogSetCheckbox(Result, 'opt_words', AWholeWord);
  DialogSetCheckbox(Result, 'opt_regex', ARegex);
  DialogSetCheckbox(Result, 'opt_reverse', AReverse);
end;

function BuildReplaceAskDialog(const AFind, AReplacement: string; ALineNo: Integer;
  const APre, AHit, APost: string): TDialogDeclaration;
const
  cContextCol = 16;

  procedure Place(const AId, AText: string; ACol: Integer);
  var
    I: Integer;
  begin
    for I := 0 to High(Result.Controls) do
      if SameText(Result.Controls[I].Id, AId) then
      begin
        Result.Controls[I].Text := AText;
        Result.Controls[I].Col := ACol;
        Result.Controls[I].BoxW := Max(Length(AText), 1);
        Break;
      end;
  end;

begin
  RequireDialogResource(cResDialogReplaceAsk, Result);
  DialogSetLabelText(Result, 'cap_find', T('ui.editor.replaceAskFind', 'Find:'));
  DialogSetLabelText(Result, 'val_find', '"' + AFind + '"');
  DialogSetLabelText(Result, 'cap_repl', T('ui.editor.replaceAskWith', 'Replace with:'));
  DialogSetLabelText(Result, 'val_repl', '"' + AReplacement + '"');
  DialogSetLabelText(Result, 'cap_line', T('ui.editor.replaceAskLine', 'Line %d:', [ALineNo]));
  Place('ctx_pre', APre, cContextCol);
  Place('ctx_hit', AHit, cContextCol + Length(APre));
  Place('ctx_post', APost, cContextCol + Length(APre) + Length(AHit));
end;

function BuildReplaceDialog(const AFind, AReplace: string; AMatchCase, AWholeWord,
  ARegex, AReverse: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogReplace, Result);
  DialogSetInputValue(Result, 'find', AFind);
  DialogSetInputValue(Result, 'replace', AReplace);
  DialogSetCheckbox(Result, 'opt_case', AMatchCase);
  DialogSetCheckbox(Result, 'opt_words', AWholeWord);
  DialogSetCheckbox(Result, 'opt_regex', ARegex);
  DialogSetCheckbox(Result, 'opt_reverse', AReverse);
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

// Adds the "Elevate" button after the first button of the dialog's button row
// and spreads the row evenly (the JSON layout has no room for it).
procedure DialogAddElevateButton(var ADecl: TDialogDeclaration);
const
  cGap = 3;
var
  Row, First, I, J, Count, Total, Left: Integer;
  Btn: TDialogControl;
begin
  Row := -1;
  First := -1;
  for I := 0 to High(ADecl.Controls) do
    if ADecl.Controls[I].Kind = dckButton then
    begin
      Row := ADecl.Controls[I].Row;
      First := I;
      Break;
    end;
  if First < 0 then
    Exit;
  Btn := Default(TDialogControl);
  Btn.Kind := dckButton;
  Btn.Id := cDlgCmdElevate;
  Btn.Text := T('ui.job.elevate', '&Elevate');
  Btn.Row := Row;
  Btn.Col := 0;
  Btn.BoxW := Length(Btn.Text) + 4;
  Btn.BoxH := 1;
  SetLength(ADecl.Controls, Length(ADecl.Controls) + 1);
  for J := High(ADecl.Controls) downto First + 2 do
    ADecl.Controls[J] := ADecl.Controls[J - 1];
  ADecl.Controls[First + 1] := Btn;
  Count := 0;
  Total := 0;
  for I := 0 to High(ADecl.Controls) do
    if (ADecl.Controls[I].Kind = dckButton) and (ADecl.Controls[I].Row = Row) then
    begin
      Inc(Count);
      Inc(Total, ADecl.Controls[I].BoxW);
    end;
  Inc(Total, cGap * (Count - 1));
  Left := Max((ADecl.Width - 2 - Total) div 2, 1);
  for I := 0 to High(ADecl.Controls) do
    if (ADecl.Controls[I].Kind = dckButton) and (ADecl.Controls[I].Row = Row) then
    begin
      ADecl.Controls[I].Col := Left;
      Inc(Left, ADecl.Controls[I].BoxW + cGap);
    end;
  // The row grew by a button: widen the frame and center the row again.
  FitDialogToTranslatedText(ADecl);
end;

function BuildDeleteErrorDialog(const AHeadline, APath, AQuestion, AErrorLine: string;
  AOfferPermanent: Boolean; AOfferElevate: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogDeleteError, Result);
  Result.IsWarning := True;
  DialogSetLabelText(Result, 'headline', AHeadline);
  DialogSetLabelText(Result, 'path', APath);
  DialogSetLabelText(Result, 'question', AQuestion);
  DialogSetLabelText(Result, 'error_line', AErrorLine);
  if AOfferPermanent then
    DialogSetButtonText(Result, cDlgCmdDelete, T('ui.deleteError.delete', 'Delete'))
  else
  begin
    DialogSetButtonText(Result, cDlgCmdDelete, T('ui.deleteError.retry', 'Retry'));
    if AQuestion = '' then
      DialogSetLabelText(Result, 'question',
        T('ui.deleteError.retryQuestion', 'Retry permanent delete?'));
  end;
  if AOfferElevate then
    DialogAddElevateButton(Result);
end;

function BuildIOErrorDialog(const AHeadline, APath, AErrorLine: string;
  AOfferElevate: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogIOError, Result);
  Result.IsWarning := True;
  DialogSetLabelText(Result, 'headline', AHeadline);
  DialogSetLabelText(Result, 'path', APath);
  DialogSetLabelText(Result, 'error_line', AErrorLine);
  if AOfferElevate then
    DialogAddElevateButton(Result);
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

function BuildCommandPaletteDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const AQuery: string): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogCommandPalette, Result);
  Items := AItems;
  if Length(Items) = 0 then
    Items := [T('ui.palette.empty', '(no matches)')];
  DialogSetListItems(Result, 'commands', Items,
    EnsureRange(ASelectedIndex, 0, High(Items)));
  DialogSetInputValue(Result, 'query', AQuery);
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
  ASelectedIndex: Integer; const AAccents: TArray<TListAccent>): TDialogDeclaration;
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
  DialogSetListAccents(Result, 'hotlist', AAccents);
end;

function BuildWorkspaceLibraryDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const ALiveCaption: string;
  const ATitle: string): TDialogDeclaration;
var
  Items: TArray<string>;
  Sel: Integer;
  Title: string;
begin
  RequireDialogResource(cResDialogWorkspaces, Result);
  Title := ATitle;
  if Title = '' then
    Title := T('ui.workspaces.dialogTitle', 'Workspaces');
  if ALiveCaption <> '' then
    Title := Title + ' ' + #$2014 + ' ' + ALiveCaption;
  DialogSetTitle(Result, Title);
  // The keys belong to the library list; the pick list (own title) has none.
  if ATitle <> '' then
    DialogSetLabelText(Result, 'wsHint', '');
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
  AKindIndex: Integer; AReturnModeIndex: Integer): TDialogDeclaration;
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
  DialogSetListItems(Result, 'return_mode', [
    T('ui.userMenu.returnDefault', 'As in the console options'),
    T('ui.userMenu.returnPanels', 'Return to the panels'),
    T('ui.userMenu.returnStay', 'Stay in the console')], AReturnModeIndex);
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
  const ACreated, AModified, AAccessed: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSetAttr, Result);
  DialogSetLabelText(Result, 'summary', ASummary);
  DialogSetLabelText(Result, 'owner_now', AOwnerNow);
  DialogSetInputValue(Result, 'owner', AOwnerEdit);
  DialogSetCheckbox(Result, 'change_owner', False);
  DialogSetCheckbox(Result, 'recurse', False);
  DialogSetInputValue(Result, 'date_created', ACreated);
  DialogSetInputValue(Result, 'date_modified', AModified);
  DialogSetInputValue(Result, 'date_accessed', AAccessed);
  DialogSetLabelText(Result, 'date_error', '');
end;

function BuildSetModeDialog(const ASummary, AOwner, AGroup: string;
  AMode: Integer; AImmutable, AAppendOnly, ANoDump: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSetMode, Result);
  DialogSetLabelText(Result, 'summary', ASummary);
  DialogSetInputValue(Result, 'mode', FileModeToOctal(AMode));
  DialogSetLabelText(Result, 'mode_now', FileModeToSymbolic(AMode));
  DialogSetLabelText(Result, 'mode_error', '');
  DialogSetInputValue(Result, 'owner', AOwner);
  DialogSetInputValue(Result, 'group', AGroup);
  DialogSetCheckbox(Result, 'flag_immutable', AImmutable);
  DialogSetCheckbox(Result, 'flag_append', AAppendOnly);
  DialogSetCheckbox(Result, 'flag_nodump', ANoDump);
  DialogSetCheckbox(Result, 'recurse', False);
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
  const ASummary: TArray<string>; const ASwatches: TArray<TListSwatch>;
  const ALines: TArray<string>): TDialogDeclaration;
var
  I, DiffRow, Gap: Integer;
begin
  RequireDialogResource(cResDialogFileDiff, Result);
  DialogSetLabelText(Result, 'left_name', ALeftName);
  DialogSetLabelText(Result, 'right_name', ARightName);
  DialogSetLabelText(Result, 'status', AStatus);
  DialogSetListItems(Result, 'summary', ASummary, 0);
  DialogSetListSwatches(Result, 'summary', ASwatches);
  if Length(ALines) > 0 then
  begin
    DialogSetListItems(Result, 'diff', ALines, 0);
    Exit;
  end;
  // Nothing to list: drop the diff block and pull the footer up.
  I := 0;
  while (I <= High(Result.Controls)) and (Result.Controls[I].Id <> 'diff') do
    Inc(I);
  if I > High(Result.Controls) then
    Exit;
  DiffRow := Result.Controls[I].Row;
  Gap := Result.Controls[I].BoxH;
  Delete(Result.Controls, I, 1);
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Row > DiffRow then
      Dec(Result.Controls[I].Row, Gap);
  Dec(Result.Height, Gap);
end;

function BuildCompareGroupDialog(const AStatus: string;
  const AItems: TArray<string>; const ASwatches: TArray<TListSwatch>;
  ASelected: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogCompareGroup, Result);
  DialogSetLabelText(Result, 'status', AStatus);
  DialogSetListItems(Result, 'pairs', AItems, ASelected);
  DialogSetListSwatches(Result, 'pairs', ASwatches);
end;

function BuildColumnsConfigDialog(AShowExt, AShowSize, AShowModified,
  AShowCreated, AShowAccessed, AShowType, AShowAttr: Boolean;
  const AScheme: string; const ASetItems: TArray<string>): TDialogDeclaration;
const
  // Rows the column sets block on the right uses; the footer starts below it.
  cFooterRow = 9;
var
  Cols: TPluginColumns;
  I, Row, Delta: Integer;
  Box, Tmpl: TDialogControl;
begin
  RequireDialogResource(cResDialogColumnsConfig, Result);
  DialogSetCheckbox(Result, 'col_ext', AShowExt);
  DialogSetCheckbox(Result, 'col_size', AShowSize);
  DialogSetCheckbox(Result, 'col_modified', AShowModified);
  DialogSetCheckbox(Result, 'col_created', AShowCreated);
  DialogSetCheckbox(Result, 'col_accessed', AShowAccessed);
  DialogSetCheckbox(Result, 'col_type', AShowType);
  DialogSetCheckbox(Result, 'col_attr', AShowAttr);
  DialogSetListItems(Result, 'sets', ASetItems, 0);
  Cols := SchemePluginColumns(AScheme);
  Tmpl := Default(TDialogControl);
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Id = 'col_attr' then
      Tmpl := Result.Controls[I];
  // Built-in columns the scheme's plugin excluded are dropped; the checkboxes
  // that remain are numbered from the top again, and the plugin ones follow.
  for I := High(Result.Controls) downto 0 do
    if (Copy(Result.Controls[I].Id, 1, 4) = 'col_') and
       not BuiltinColumnAvailable(AScheme, Copy(Result.Controls[I].Id, 5, MaxInt)) then
      Delete(Result.Controls, I, 1);
  Row := 0;
  for I := 0 to High(Result.Controls) do
    if Copy(Result.Controls[I].Id, 1, 4) = 'col_' then
    begin
      Result.Controls[I].Row := Row;
      Inc(Row);
    end;
  for I := 0 to High(Cols) do
  begin
    Box := Tmpl;
    Box.Id := 'pcol_' + IntToStr(I);
    Box.Text := StringReplace(PluginColumnTitle(Cols[I]), '&', '', [rfReplaceAll]);
    Box.Checked := IsPluginColumnShown(AScheme, Cols[I]);
    Box.Row := Row;
    Inc(Row);
    SetLength(Result.Controls, Length(Result.Controls) + 1);
    Result.Controls[High(Result.Controls)] := Box;
  end;
  // A checkbox column longer than the sets block pushes the footer down; the
  // sets list grows with it and its buttons stay on the last row of the column.
  Delta := Row - cFooterRow;
  if Delta > 0 then
  begin
    for I := 0 to High(Result.Controls) do
      if Result.Controls[I].Row >= cFooterRow then
      begin
        if Copy(Result.Controls[I].Id, 1, 4) <> 'pcol' then
          Inc(Result.Controls[I].Row, Delta);
      end
      else if Result.Controls[I].Id = 'sets' then
        Inc(Result.Controls[I].BoxH, Delta)
      else if Copy(Result.Controls[I].Id, 1, 4) = 'set_' then
        if Result.Controls[I].Kind = dckButton then
          Inc(Result.Controls[I].Row, Delta);
    Inc(Result.Height, Delta);
  end;
end;

function BuildExportListDialog(const APath: string;
  const AConfig: TListExportConfig): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogExportList, Result);
  DialogSetInputValue(Result, 'name', APath);
  case AConfig.Format of
    lefText: DialogSetRadio(Result, 'format', 'fmt_text');
    lefMarkdown: DialogSetRadio(Result, 'format', 'fmt_md');
    lefCsv: DialogSetRadio(Result, 'format', 'fmt_csv');
  else
    DialogSetRadio(Result, 'format', 'fmt_auto');
  end;
  DialogSetCheckbox(Result, 'header', AConfig.Header);
  DialogSetCheckbox(Result, 'f_name', lxfName in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_path', lxfPath in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_ext', lxfExt in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_size', lxfSize in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_modified', lxfModified in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_created', lxfCreated in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_accessed', lxfAccessed in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_type', lxfType in AConfig.Fields);
  DialogSetCheckbox(Result, 'f_attr', lxfAttr in AConfig.Fields);
end;

function BuildMarkdownColorsDialog: TDialogDeclaration;
begin
  RequireDialogResource(cResDialogMarkdownColors, Result);
end;

function BuildMarkdownImportDialog(const APath: string; APaletteIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogMarkdownImport, Result);
  DialogSetInputValue(Result, 'obs_path', APath);
  DialogSetDropDownSelected(Result, 'obs_palette', APaletteIndex);
end;

function BuildChecksumOptionsDialog(AAlgoIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogChecksumOpts, Result);
  DialogSetDropDownSelected(Result, 'algo', AAlgoIndex);
end;

function BuildCompareOptionsDialog(AByTime, ABySize, AByContent: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogCompareOpts, Result);
  DialogSetCheckbox(Result, 'by_time', AByTime);
  DialogSetCheckbox(Result, 'by_size', ABySize);
  DialogSetCheckbox(Result, 'by_content', AByContent);
end;

function BuildMultiRenameDialog(const ARules: TMultiRenameRules;
  AWidth: Integer): TDialogDeclaration;
var
  Half, RightLabel, RightInput, I: Integer;

  procedure Place(const AId: string; ACol, ACells: Integer);
  var
    I: Integer;
  begin
    for I := 0 to High(Result.Controls) do
      if SameText(Result.Controls[I].Id, AId) then
      begin
        Result.Controls[I].Col := ACol;
        Result.Controls[I].BoxW := ACells;
      end;
  end;

begin
  RequireDialogResource(cResDialogMultiRename, Result);
  Result.Width := AWidth;
  Half := (AWidth - 4) div 2;
  RightLabel := Half + 3;
  RightInput := Half + 15;
  Place('name_mask', 16, Half - 17);
  Place('search', 16, Half - 17);
  Place('case_mode', 16, Half - 17);
  Place('lbl_ext_mask', RightLabel, 11);
  Place('lbl_replace', RightLabel, 11);
  Place('ext_mask', RightInput, AWidth - 2 - RightInput);
  Place('replace', RightInput, AWidth - 2 - RightInput);
  Place('match_case', RightLabel, AWidth - 2 - RightLabel);
  Place('use_regex', RightLabel, AWidth - 2 - RightLabel);
  Place('lbl_tokens', 1, AWidth - 4);
  Place('status', 1, AWidth - 4);
  Place('columns', 1, AWidth - 4);
  Place('preview', 1, AWidth - 4);
  Place('ok', AWidth div 2 - 12, 12);
  Place('cancel', AWidth div 2 + 2, 12);
  for I := 0 to High(Result.Controls) do
    if (Result.Controls[I].Kind = dckLabel) and IsHRuleText(Result.Controls[I].Text) then
    begin
      Result.Controls[I].Text := StringOfChar(chBoxH, AWidth - 2);
      Result.Controls[I].BoxW := AWidth - 2;
    end;
  DialogSetInputValue(Result, 'name_mask', ARules.NameMask);
  DialogSetInputValue(Result, 'ext_mask', ARules.ExtMask);
  DialogSetInputValue(Result, 'search', ARules.Search);
  DialogSetInputValue(Result, 'replace', ARules.Replace);
  DialogSetInputValue(Result, 'c_start', IntToStr(ARules.CounterStart));
  DialogSetInputValue(Result, 'c_step', IntToStr(ARules.CounterStep));
  DialogSetInputValue(Result, 'c_digits', IntToStr(ARules.CounterDigits));
  DialogSetCheckbox(Result, 'match_case', ARules.MatchCase);
  DialogSetCheckbox(Result, 'use_regex', ARules.UseRegex);
  DialogSetDropDownSelected(Result, 'case_mode', Ord(ARules.CaseMode));
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

function BuildConsoleOptionsDialog(AScrollbackIndex: Integer; AConfirmPaste,
  ATrimCopy, ATrimPaste: Boolean; AReturnToPanels: Boolean;
  ABackgroundShowIndex: Integer): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogConsoleOptions, Result);
  DialogSetListItems(Result, 'scrollback', ScrollbackItems, AScrollbackIndex);
  DialogSetCheckbox(Result, 'confirm_paste', AConfirmPaste);
  DialogSetCheckbox(Result, 'trim_copy', ATrimCopy);
  DialogSetCheckbox(Result, 'trim_paste', ATrimPaste);
  DialogSetCheckbox(Result, 'return_panels', AReturnToPanels);
  DialogSetListItems(Result, 'bg_show', BackgroundShowItems, ABackgroundShowIndex);
end;

function BuildConfigLocationDialog(const ATitle: string;
  const ALines: TArray<string>; const AOkText: string): TDialogDeclaration;
var
  I, J, Used, Delta, LastRow: Integer;
  Kept: TArray<TDialogControl>;
begin
  RequireDialogResource(cResDialogConfigLocation, Result);
  DialogSetTitle(Result, ATitle);
  Used := Min(Length(ALines), cConfigLocationLines);
  for I := 0 to Used - 1 do
    DialogSetLabelText(Result, 'line' + IntToStr(I + 1), ALines[I]);
  DialogSetButtonText(Result, cDlgCmdOk, AOkText);

  // The text lines that are not needed disappear with their rows: the rule
  // and the buttons move up and the dialog gets shorter.
  Delta := cConfigLocationLines - Used;
  if Delta = 0 then
    Exit;
  LastRow := 0;
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Id = 'line' + IntToStr(cConfigLocationLines) then
      LastRow := Result.Controls[I].Row;
  SetLength(Kept, 0);
  for I := 0 to High(Result.Controls) do
  begin
    J := 0;
    if (Result.Controls[I].Kind = dckLabel) and
       (Copy(Result.Controls[I].Id, 1, 4) = 'line') then
      J := StrToIntDef(Copy(Result.Controls[I].Id, 5, MaxInt), 0);
    if J > Used then
      Continue;
    if Result.Controls[I].Row > LastRow then
      Dec(Result.Controls[I].Row, Delta);
    Kept := Kept + [Result.Controls[I]];
  end;
  Result.Controls := Kept;
  Dec(Result.Height, Delta);
end;

function BuildSettingsFileDialog(const ATitle, APrompt, APath: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogSettingsFile, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'prompt', APrompt);
  DialogSetInputValue(Result, 'name', APath);
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
  AShadowIndex: Integer;
  ALineSpacing: Boolean; AMarkedRowIndex: Integer;
  ASnapFontSize: Boolean; ATextContrastIndex: Integer;
  ACellWidthExtra, ACellHeightExtra: Integer): TDialogDeclaration;
var
  Fonts: TArray<string>;
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
  DialogSetListItems(Result, 'shadows', DisplayShadowItems, AShadowIndex);
  DialogSetListItems(Result, 'marked_rows', DisplayMarkedRowItems, AMarkedRowIndex);
  DialogSetCheckbox(Result, 'line_spacing', ALineSpacing);
  DialogSetCheckbox(Result, 'snap_font_size', ASnapFontSize);
  DialogSetListItems(Result, 'text_contrast', DisplayTextContrastItems, ATextContrastIndex);
  DialogSetListItems(Result, 'cell_w', DisplayCellExtraItems, ACellWidthExtra);
  DialogSetListItems(Result, 'cell_h', DisplayCellExtraItems, ACellHeightExtra);
  DialogSetLabelText(Result, 'font_note', ANote);
end;

function BuildInterfaceDialog(const ALanguageNames: TArray<string>;
  ALanguageIndex: Integer; AShowNotifications: Boolean): TDialogDeclaration;
var
  Languages: TArray<string>;
  Sel: Integer;
begin
  RequireDialogResource(cResDialogInterface, Result);
  DialogSetCheckbox(Result, 'notifications', AShowNotifications);
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

function BuildTerminalEnvDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
begin
  Result := BuildShellProfileListDialog(T('ui.terminalEnv.title', 'Environment profile'),
    AItems, ASelectedIndex);
end;

function BuildTerminalProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer; const AAccents: TArray<TListAccent>): TDialogDeclaration;
const
  cExtraWidth = 12;
var
  I, N: Integer;
begin
  Result := BuildShellProfileListDialog(
    T('ui.terminalProfile.title', 'New terminal'), ATitles, ASelectedIndex);
  // Wider than the shared resource so the key mode at the end of a row is
  // never cut; two hint rows under the rule, the buttons move down for them.
  Result.Width := Result.Width + cExtraWidth;
  Result.Height := Result.Height + 2;
  for I := 0 to High(Result.Controls) do
    case Result.Controls[I].Kind of
      dckList:
        Inc(Result.Controls[I].BoxW, cExtraWidth);
      dckLabel:
        if IsHRuleText(Result.Controls[I].Text) then
          Result.Controls[I] := WithControlBox(
            MakeHRule(Result.Controls[I].BoxW + cExtraWidth),
            Result.Controls[I].Col, Result.Controls[I].Row,
            Result.Controls[I].BoxW + cExtraWidth, 1);
      dckButton:
        begin
          Inc(Result.Controls[I].Row, 2);
          Inc(Result.Controls[I].Col, cExtraWidth div 2);
        end;
    end;
  DialogSetListAccents(Result, 'profiles', AAccents);
  N := Length(Result.Controls);
  SetLength(Result.Controls, N + 2);
  Result.Controls[N] := WithControlBox(
    MakeLabel(T('ui.terminalProfile.hint1', 'Ins - copy profile   Del - delete copy')),
    1, 13, Result.Width - 4, 1);
  Result.Controls[N + 1] := WithControlBox(
    MakeLabel(T('ui.terminalProfile.hint2', 'Ctrl+Up/Down - order  F4 - keys  F6 - env')),
    1, 14, Result.Width - 4, 1);
  FitDialogCaptions(Result);
end;

function BuildConsoleProfileDialog(const ATitles: TArray<string>;
  ASelectedIndex: Integer; AStartOnLaunch, ACwdToPanels,
  AProgramsInTerminal: Boolean): TDialogDeclaration;
var
  I, N, ButtonRow: Integer;
begin
  Result := BuildShellProfileListDialog(
    T('ui.consoleProfile.title', 'Background console'), ATitles, ASelectedIndex);
  // Three checkboxes take the rows under the profile list that hold the rule
  // and the empty row above the buttons; the rule and the buttons move four
  // rows down. The shared terminal-profile resource has no room for it, so
  // only this dialog grows.
  ButtonRow := 0;
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Kind = dckButton then
      ButtonRow := Max(ButtonRow, Result.Controls[I].Row);
  Result.Height := Result.Height + 4;
  for I := 0 to High(Result.Controls) do
    if Result.Controls[I].Row >= ButtonRow - 2 then
      Inc(Result.Controls[I].Row, 4);
  N := Length(Result.Controls);
  SetLength(Result.Controls, N + 3);
  Result.Controls[N] := WithControlBox(
    MakeCheckbox('start_on_launch',
      T('ui.consoleProfile.startOnLaunch', '&Start shell at program launch'),
      AStartOnLaunch),
    1, ButtonRow - 2, Result.Width - 4, 1);
  Result.Controls[N + 1] := WithControlBox(
    MakeCheckbox('cwd_to_panels',
      T('ui.consoleProfile.cwdToPanels', '&Panel follows the console folder after commands'),
      ACwdToPanels),
    1, ButtonRow - 1, Result.Width - 4, 1);
  Result.Controls[N + 2] := WithControlBox(
    MakeCheckbox('programs_in_terminal',
      T('ui.consoleProfile.programsInTerminal', '&Run programs from the panels in a terminal tab'),
      AProgramsInTerminal),
    1, ButtonRow, Result.Width - 4, 1);
  // The checkbox captions are set here, after the resource was fitted.
  FitDialogCaptions(Result);
end;

function BuildPluginListDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer): TDialogDeclaration;
var
  Items: TArray<string>;
begin
  RequireDialogResource(cResDialogPluginList, Result);
  if Length(AItems) = 0 then
  begin
    SetLength(Items, 1);
    Items[0] := '(no plugins)';
  end
  else
    Items := AItems;
  if (ASelectedIndex < 0) or (ASelectedIndex > High(Items)) then
    ASelectedIndex := 0;
  DialogSetListItems(Result, 'plugins', Items, ASelectedIndex);
end;

function BuildPluginPermissionsDialog(const ATitle, AIntro, AOverrideText: string;
  AHasOverride, AOverrideOn: Boolean; const APermTexts: TArray<string>;
  const AGranted: TArray<Boolean>): TDialogDeclaration;
const
  cSlots: array[0..2] of string = ('perm_override', 'perm_0', 'perm_1');
var
  Slot, I, J, Row: Integer;
  Keep: Boolean;
  Text: string;
  On_: Boolean;
begin
  RequireDialogResource(cResDialogPluginPerms, Result);
  if ATitle <> '' then
    DialogSetTitle(Result, ATitle);
  DialogSetLabelText(Result, 'intro', AIntro);
  Row := 3;
  for Slot := 0 to High(cSlots) do
  begin
    Keep := False;
    Text := '';
    On_ := False;
    if Slot = 0 then
    begin
      Keep := AHasOverride;
      Text := AOverrideText;
      On_ := AOverrideOn;
    end
    else if Slot - 1 <= High(APermTexts) then
    begin
      Keep := True;
      Text := APermTexts[Slot - 1];
      if Slot - 1 <= High(AGranted) then
        On_ := AGranted[Slot - 1];
    end;
    for I := High(Result.Controls) downto 0 do
      if SameText(Result.Controls[I].Id, cSlots[Slot]) then
      begin
        if Keep then
        begin
          Result.Controls[I].Text := Text;
          Result.Controls[I].Checked := On_;
          Result.Controls[I].Row := Row;
        end
        else
        begin
          for J := I to High(Result.Controls) - 1 do
            Result.Controls[J] := Result.Controls[J + 1];
          SetLength(Result.Controls, Length(Result.Controls) - 1);
        end;
        Break;
      end;
    if Keep then
      Inc(Row);
  end;
  if not AHasOverride then
    for I := High(Result.Controls) downto 0 do
      if SameText(Result.Controls[I].Id, 'hint') then
      begin
        for J := I to High(Result.Controls) - 1 do
          Result.Controls[J] := Result.Controls[J + 1];
        SetLength(Result.Controls, Length(Result.Controls) - 1);
      end;
end;

function BuildPluginInfoDialog(const ATitle: string; const ALines: TArray<string>;
  AHasHelp: Boolean): TDialogDeclaration;
var
  I, J: Integer;
begin
  RequireDialogResource(cResDialogPluginInfo, Result);
  if ATitle <> '' then
    DialogSetTitle(Result, ATitle);
  DialogSetListItems(Result, 'info', ALines, 0);
  if AHasHelp then
    Exit;
  // No help page: drop the Help button and centre OK.
  for I := High(Result.Controls) downto 0 do
    if SameText(Result.Controls[I].Id, 'help') then
    begin
      for J := I to High(Result.Controls) - 1 do
        Result.Controls[J] := Result.Controls[J + 1];
      SetLength(Result.Controls, Length(Result.Controls) - 1);
    end
    else if SameText(Result.Controls[I].Id, 'ok') then
      Result.Controls[I].Col := (Result.Width - 2 - Result.Controls[I].BoxW) div 2;
end;

function BuildColorCodingDialog(const AItems: TArray<string>;
  ASelectedIndex: Integer; const ASwatches: TArray<TListSwatch>): TDialogDeclaration;
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
  DialogSetListSwatches(Result, 'groups', ASwatches);
end;

function BuildColorCodingEditDialog(const AName, AMask: string;
  AApplyToIndex: Integer; AEnabled: Boolean; const APriority, AWhen: string;
  const ANormalFg, ANormalBg, ASelectedFg, ASelectedBg,
  ACurrentFg, ACurrentBg: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogColorCodingEdit, Result);
  DialogSetInputValue(Result, 'cc_name', AName);
  DialogSetInputValue(Result, 'cc_mask', AMask);
  DialogSetDropDownSelected(Result, 'cc_applyto', AApplyToIndex);
  DialogSetCheckbox(Result, 'cc_enabled', AEnabled);
  DialogSetInputValue(Result, 'cc_priority', APriority);
  DialogSetInputValue(Result, 'cc_when', AWhen);
  DialogSetInputValue(Result, 'cc_normal_fg', ANormalFg);
  DialogSetInputValue(Result, 'cc_normal_bg', ANormalBg);
  DialogSetInputValue(Result, 'cc_selected_fg', ASelectedFg);
  DialogSetInputValue(Result, 'cc_selected_bg', ASelectedBg);
  DialogSetInputValue(Result, 'cc_current_fg', ACurrentFg);
  DialogSetInputValue(Result, 'cc_current_bg', ACurrentBg);
end;

function BuildColorPickerDialog(const ATitle: string; AColor: TAlphaColor): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogColorPicker, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetColorPicker(Result, 'picker', AColor);
end;

function BuildDatePickerDialog(const ATitle: string; ADate: TDateTime;
  const ATime: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogDatePicker, Result);
  DialogSetTitle(Result, ATitle);
  DialogSetDatePicker(Result, 'date', ADate);
  DialogSetInputValue(Result, 'time', ATime);
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

function BuildHideableMessageDialog(const AMessage, ADetails, AHint: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogHideableMsg, Result);
  DialogSetLabelText(Result, 'message', AMessage);
  DialogSetLabelText(Result, 'details', ADetails);
  DialogSetLabelText(Result, 'hint', AHint);
end;

function BuildUpdatesDialog(const ACurrentVersion: string;
  ACheckOnStart, AShowCheckNotice, ADevChannel: Boolean): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogUpdates, Result);
  DialogSetLabelText(Result, 'version', T('ui.update.current', 'Installed version: %s.',
    [ACurrentVersion]));
  DialogSetCheckbox(Result, 'check_on_start', ACheckOnStart);
  DialogSetCheckbox(Result, 'show_check_notice', AShowCheckNotice);
  DialogSetCheckbox(Result, 'dev_channel', ADevChannel);
end;

function BuildAboutDialog: TDialogDeclaration;
var
  Engine, Ver: string;
begin
  RequireDialogResource(cResDialogAbout, Result);

  if Assigned(GGraphicsEngineLabel) then
    Engine := GGraphicsEngineLabel()
  else
    Engine := '';
  DialogSetLabelText(Result, 'lbl_skia', Engine);
{$IFNDEF MSWINDOWS}
  DialogSetLabelText(Result, 'lbl_pty',
    T('ui.about.platformLinux', 'Platform: Linux x64 | PTY Persistent Shell'));
{$ENDIF}

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
  DialogSetLabelText(Result, 'km_action', T('ui.keymap.editAction', 'Action: %s', [AActionName]));
  DialogSetInputValue(Result, 'km_keys', AKeysText);
  DialogSetLabelText(Result, 'km_status', AStatus);
end;

end.
