unit uDualPanelSettingsDialogs;

{ Columns / display / Markdown colors / terminal-profile dialogs. Extracted from
  TDualPanelWindow so the host keeps only thin Open forwards. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDialogBuilders, uDualPanelUiTypes, uDualPanelTypes, uPanelColumns, uPluginColumns,
  uShellProfiles, uEnvProfiles, uScreenSaver, uDisplaySettings, uStrings, uExternalTools, uMarkdownColors, uThemeTypes,
  uSettingsPages;

type
  TSettingsKindSetter = reference to procedure(AKind: THostDialogKind);
  TSettingsCanStart = reference to function: Boolean;
  TSettingsPrepareUi = reference to procedure;
  TSettingsGetLocalPath = reference to function: string;
  TSettingsOpenTerminal = reference to procedure(const AProfileId, ACwd: string);
  /// <summary>Apply the picked profile to the host's persistent background
  /// console (Ctrl+O) -- the Background console dialog.</summary>
  TSettingsSetConsoleProfile = reference to procedure(const AProfileId: string);
  TSettingsGetConsoleProfile = reference to function: string;
  TSettingsShowStub = reference to procedure(const ATitle, ADetail: string);
  TSettingsGetDisplay = reference to function: TDisplaySettings;
  TSettingsApplyDisplay = reference to procedure(const ASettings: TDisplaySettings);
  /// <summary>Section the Settings window opens on.</summary>
  TSettingsStart = (ssDisplay, ssInterface, ssConsole);

  TSettingsDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TSettingsKindSetter;
    FOnNotify: TProc;
    /// <summary>Scheme whose plugin columns the open Columns dialog lists.</summary>
    FColumnsScheme: string;
    FOnCanStart: TSettingsCanStart;
    FOnPrepareUi: TSettingsPrepareUi;
    FOnGetLocalPath: TSettingsGetLocalPath;
    FOnOpenTerminal: TSettingsOpenTerminal;
    FOnSetConsoleProfile: TSettingsSetConsoleProfile;
    FOnGetConsoleProfile: TSettingsGetConsoleProfile;
    FOnGetConsoleStartOnLaunch: TFunc<Boolean>;
    FOnSetConsoleStartOnLaunch: TProc<Boolean>;
    FOnGetConsoleCwdToPanels: TFunc<Boolean>;
    FOnSetConsoleCwdToPanels: TProc<Boolean>;
    FOnGetProgramsInTerminal: TFunc<Boolean>;
    FOnResetKeyHints: TProc;
    FOnColumnsAccepted: TProc<TCustomColumnsConfig>;
    FColumnsConfig: TCustomColumnsConfig;
    FColumnsOpenConfig: TCustomColumnsConfig;
    FColumnsOpenPlugins: string;
    FColumnsLoadedSet: Boolean;
    FOnSetProgramsInTerminal: TProc<Boolean>;
    FOnShowStub: TSettingsShowStub;
    FOnGetDisplay: TSettingsGetDisplay;
    FOnApplyDisplay: TSettingsApplyDisplay;
    FProfileIds: TArray<string>;
    /// <summary>Environment profile list: the shell profile it is for and the
    /// names it offers after its "none" row.</summary>
    FEnvTarget: string;
    FEnvNames: TArray<string>;
    /// <summary>Markdown colors dialog: the edited set while the import
    /// dialog is on top, and the import dialog's last path / palette.</summary>
    FMdWorking: TMdColorSet;
    /// <summary>The set the Markdown dialog opened with; what the user changed
    /// is the difference to it.</summary>
    FMdInitial: TMdColorSet;
    FOnGetMarkdown: TFunc<TMdColorSet>;
    FOnSaveMarkdown: TProc<TMdColorSet, TMdColorSet>;
    FMdImportPath: string;
    FMdImportPalette: Integer;
    /// <summary>Id of the color field the color picker is editing.</summary>
    FMdPickField: string;
    FLanguageCodes: TArray<string>;
    /// <summary>Display and Interface dialogs: the settings they opened with.
    /// OK writes the fields of the open dialog onto this snapshot, so the
    /// other dialog's fields are kept. Also the size it opened with (pixels)
    /// and its list row: OK without touching the size keeps the exact value -- a
    /// size set outside the list (session.json) is not rounded to it.</summary>
    FOpenFontSize: Single;
    FOpenDisplay: TDisplaySettings;
    FOpenFontSizeIdx: Integer;
    /// <summary>Settings window: the merged declaration, the sections of the
    /// full list and the search text that narrows them.</summary>
    FSettingsDecl: TDialogDeclaration;
    FSettingsPages: TSettingsPages;
    FSettingsQuery: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure ShowMarkdownColors(const ASet: TMdColorSet; const AStatus: string;
      const AFocusId: string = '');
    function FindMarkdownColorField(const AFieldId: string; out AKind: TMdSpanKind;
      out AIsBg: Boolean): Boolean;
    procedure BeginMarkdownPicker(const AFieldId: string);
    function ReadMarkdownColorFields(out ASet: TMdColorSet): Boolean;
    function CollectAvailableProfiles(out ATitles, AIds: TArray<string>;
      const APreferId: string; out ASel: Integer): Boolean;
    procedure ShowTerminalProfiles(const ASelectId: string);
    procedure ShowTerminalEnvChoice(const AShellId: string);
    procedure LaunchTerminalProfile(AIndex: Integer);
    function BuildDisplaySource(const ACur: TDisplaySettings): TDialogDeclaration;
    function BuildInterfaceSource(const ACur: TDisplaySettings): TDialogDeclaration;
    procedure ReadDisplayFields(var ADisp: TDisplaySettings);
    procedure ReadInterfaceFields(var ADisp: TDisplaySettings);
    procedure ReadConsoleFields;
    procedure OpenSettings(AStart: TSettingsStart; const AFocusId: string = '');
    procedure ApplySettingsQuery;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TSettingsKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TSettingsCanStart; const AOnPrepareUi: TSettingsPrepareUi;
      const AOnGetLocalPath: TSettingsGetLocalPath;
      const AOnOpenTerminal: TSettingsOpenTerminal;
      const AOnSetConsoleProfile: TSettingsSetConsoleProfile;
      const AOnGetConsoleProfile: TSettingsGetConsoleProfile;
      const AOnShowStub: TSettingsShowStub;
      const AOnGetDisplay: TSettingsGetDisplay;
      const AOnApplyDisplay: TSettingsApplyDisplay);
    /// <summary>AConfig is the choice the dialog starts from.</summary>
    procedure OpenColumns(const AConfig: TCustomColumnsConfig; const AScheme: string = '');
    /// <summary>Lists the mask groups and lets the user add, change and delete them.</summary>
    procedure OpenMaskGroups;
    /// <summary>Opens the editor over the dialog that is open (its mask field asked
    /// for it); closing the editor brings that dialog back.</summary>
    procedure OpenMaskGroupsOver;
    procedure OpenDisplay;
    procedure OpenInterface;
    procedure OpenExternalTools;
    procedure OpenConsoleOptions;
    /// <summary>The fields of the settings window, for the command palette.</summary>
    function SettingFields: TArray<TSettingField>;
    /// <summary>Opens the settings window with the focus on the field AFieldId.</summary>
    procedure OpenSettingField(const AFieldId: string);
    procedure OpenMarkdownColors;
    procedure OpenTerminalProfiles;
    procedure OpenConsoleProfiles;
    /// <summary>The Markdown styles of the active theme, and where the edited
    /// ones go (initial set, edited set).</summary>
    property OnGetMarkdown: TFunc<TMdColorSet> read FOnGetMarkdown write FOnGetMarkdown;
    property OnSaveMarkdown: TProc<TMdColorSet, TMdColorSet>
      read FOnSaveMarkdown write FOnSaveMarkdown;
    property OnGetConsoleStartOnLaunch: TFunc<Boolean>
      read FOnGetConsoleStartOnLaunch write FOnGetConsoleStartOnLaunch;
    property OnSetConsoleStartOnLaunch: TProc<Boolean>
      read FOnSetConsoleStartOnLaunch write FOnSetConsoleStartOnLaunch;
    property OnGetConsoleCwdToPanels: TFunc<Boolean>
      read FOnGetConsoleCwdToPanels write FOnGetConsoleCwdToPanels;
    property OnSetConsoleCwdToPanels: TProc<Boolean>
      read FOnSetConsoleCwdToPanels write FOnSetConsoleCwdToPanels;
    /// <summary>Enter on a console program in a panel runs it in a terminal
    /// tab instead of the background console.</summary>
    /// <summary>The Reset button of the interface dialog: every key hint is
    /// due again.</summary>
    property OnResetKeyHints: TProc read FOnResetKeyHints write FOnResetKeyHints;
    /// <summary>Called after OK in the Columns dialog: the chosen columns show
    /// only in the Custom column mode, so the host switches to it.</summary>
    /// <summary>Called with the columns chosen in the Columns dialog.</summary>
    property OnColumnsAccepted: TProc<TCustomColumnsConfig> read FOnColumnsAccepted write FOnColumnsAccepted;
    property OnGetProgramsInTerminal: TFunc<Boolean>
      read FOnGetProgramsInTerminal write FOnGetProgramsInTerminal;
    property OnSetProgramsInTerminal: TProc<Boolean>
      read FOnSetProgramsInTerminal write FOnSetProgramsInTerminal;
    procedure DispatchColumnsCommand(const AControlId: string);
    function ColumnSetRows: TArray<string>;
    procedure ManageColumnSet(const AControlId: string);
    procedure ShowMaskGroups(const ASelectName, AName, AMasks: string);
    procedure DispatchMaskGroupsCommand(const AControlId: string);
    procedure DispatchDisplayCommand(const AControlId: string);
    procedure DispatchInterfaceCommand(const AControlId: string);
    /// <summary>Type-to-search on the section list of the settings window:
    /// printable keys and Backspace edit the search text.</summary>
    function HandleSettingsFilter(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchExternalToolsCommand(const AControlId: string);
    procedure DispatchMarkdownColorsCommand(const AControlId: string);
    procedure DispatchMarkdownImportCommand(const AControlId: string);
    procedure DispatchMarkdownPickerCommand(const AControlId: string);
    /// <summary>F9 on a color field of the Markdown colors dialog opens the picker.</summary>
    function HandleMarkdownColorsInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchTerminalProfileCommand(const AControlId: string);
    procedure DispatchTerminalEnvCommand(const AControlId: string);
    /// <summary>Quick-launch keys, Ins / Del / Ctrl+Up / Ctrl+Down / F4 / F6 of the
    /// New terminal list.</summary>
    function HandleTerminalProfileInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchConsoleProfileCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  System.Math, uDialogResources, uColorCoding, uColorPickerControl, uConsoleSettings,
  uShellProfileOptions, uColumnSets, uMaskGroups, uDialogTabs, uKeyChord, uToast;

// Drops the controls that only matter when the host draws with a font of its own.
procedure RemoveFontControls(var ADecl: TDialogDeclaration);
const
  cIds: array[0..16] of string = ('grp_text', 'lbl_font', 'fonts', 'lbl_size', 'font_size',
    'lbl_zoom', 'zoom', 'line_spacing', 'snap_font_size', 'lbl_text_contrast',
    'text_contrast', 'lbl_cell_w', 'cell_w', 'lbl_cell_h', 'cell_h',
    'lbl_font_fallback', 'font_fallback');
var
  I, J, N: Integer;
  Hide: Boolean;
begin
  N := 0;
  for I := 0 to High(ADecl.Controls) do
  begin
    Hide := False;
    for J := Low(cIds) to High(cIds) do
      if SameText(ADecl.Controls[I].Id, cIds[J]) then
        Hide := True;
    if not Hide then
    begin
      ADecl.Controls[N] := ADecl.Controls[I];
      Inc(N);
    end;
  end;
  SetLength(ADecl.Controls, N);
end;

constructor TSettingsDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TSettingsKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TSettingsCanStart;
  const AOnPrepareUi: TSettingsPrepareUi;
  const AOnGetLocalPath: TSettingsGetLocalPath;
  const AOnOpenTerminal: TSettingsOpenTerminal;
  const AOnSetConsoleProfile: TSettingsSetConsoleProfile;
  const AOnGetConsoleProfile: TSettingsGetConsoleProfile;
  const AOnShowStub: TSettingsShowStub;
  const AOnGetDisplay: TSettingsGetDisplay;
  const AOnApplyDisplay: TSettingsApplyDisplay);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnGetLocalPath := AOnGetLocalPath;
  FOnOpenTerminal := AOnOpenTerminal;
  FOnSetConsoleProfile := AOnSetConsoleProfile;
  FOnGetConsoleProfile := AOnGetConsoleProfile;
  FOnShowStub := AOnShowStub;
  FOnGetDisplay := AOnGetDisplay;
  FOnApplyDisplay := AOnApplyDisplay;
end;

procedure TSettingsDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TSettingsDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

// The ids of the plugin columns shown for AScheme, as one comparable string.
function ShownPluginSignature(const AScheme: string): string;
var
  C: TPluginColumn;
begin
  Result := '';
  for C in ShownPluginColumns(AScheme) do
    Result := Result + C.Id + #1;
end;

procedure TSettingsDialogController.OpenColumns(const AConfig: TCustomColumnsConfig;
  const AScheme: string);
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  FColumnsScheme := AScheme;
  FColumnsConfig := AConfig;
  FColumnsOpenConfig := AConfig;
  FColumnsOpenPlugins := ShownPluginSignature(AScheme);
  FColumnsLoadedSet := False;
  SetKind(hdkColumnsConfig);
  FDialog.Open(BuildColumnsConfigDialog(
    AConfig.ShowExt, AConfig.ShowSize,
    AConfig.ShowModified, AConfig.ShowCreated,
    AConfig.ShowAccessed, AConfig.ShowType,
    AConfig.ShowAttr, AScheme, ColumnSetRows), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.OpenMaskGroups;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  ShowMaskGroups('', '', '');
end;

procedure TSettingsDialogController.OpenMaskGroupsOver;
begin
  ShowMaskGroups('', '', '');
end;

// Opens (or refreshes) the dialog. The row of ASelectName is selected; AName and
// AMasks fill the edit lines.
procedure TSettingsDialogController.ShowMaskGroups(const ASelectName, AName,
  AMasks: string);
var
  Names, Items: TArray<string>;
  I, Sel, NameW, TagW: Integer;
  Tag: string;
begin
  Names := MaskGroupNames;
  SetLength(Items, Length(Names));
  Sel := 0;
  Tag := T('ui.maskGroups.builtIn', '(built-in)');
  NameW := 0;
  for I := 0 to High(Names) do
    NameW := Max(NameW, Length(Names[I]));
  TagW := Length(Tag);
  // Columns: name, built-in marker, masks.
  for I := 0 to High(Names) do
  begin
    Items[I] := Names[I].PadRight(NameW) + '  ';
    if MaskGroupIsBuiltIn(Names[I]) then
      Items[I] := Items[I] + Tag
    else
      Items[I] := Items[I] + StringOfChar(' ', TagW);
    Items[I] := Items[I] + '  ' + MaskGroupMasks(Names[I]);
    if SameText(Names[I], ASelectName) then
      Sel := I;
  end;
  SetKind(hdkMaskGroups);
  FDialog.Open(BuildMaskGroupsDialog(Items, Sel, AName, AMasks), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.DispatchMaskGroupsCommand(
  const AControlId: string);
var
  Names: TArray<string>;
  Idx: Integer;
  GName, GMasks: string;
  ParentKind: Integer;
begin
  if DialogCmdIsReject(AControlId) then
  begin
    // Opened from a mask field: the dialog it came from returns as it was.
    if FDialog.PopDialog(ParentKind) then
    begin
      SetKind(THostDialogKind(ParentKind));
      Notify;
    end
    else
      FDialog.Close;
    Exit;
  end;
  Names := MaskGroupNames;
  Idx := FDialog.GetListSelectedIndex('groups');
  GName := Trim(FDialog.GetInputValue('gname'));
  GMasks := Trim(FDialog.GetInputValue('gmasks'));
  if DialogCmdIs(AControlId, 'save') then
  begin
    if MaskGroupSave(GName, GMasks) then
      ShowMaskGroups(GName, '', '')
    else
      ShowMaskGroups('', GName, GMasks);
  end
  else if DialogCmdIs(AControlId, 'delete') then
  begin
    if (Idx >= 0) and (Idx <= High(Names)) then
      MaskGroupDelete(Names[Idx]);
    ShowMaskGroups('', '', '');
  end
  else if (Idx >= 0) and (Idx <= High(Names)) then
    ShowMaskGroups(Names[Idx], Names[Idx], MaskGroupMasks(Names[Idx]));
end;

function TSettingsDialogController.BuildDisplaySource(
  const ACur: TDisplaySettings): TDialogDeclaration;
var
  Fonts: TArray<string>;
  ResolvedName, Note: string;
  FontIdx: Integer;
begin
  ResolvedName := ResolveMonospaceFontFamily(ACur.FontName);
  Fonts := EnumerateMonospaceFontFamilies;
  EnsureFontInList(Fonts, ResolvedName);
  FontIdx := IndexOfFontName(Fonts, ResolvedName);
  Note := '';
  if (Trim(ACur.FontName) <> '') and not SameText(ACur.FontName, ResolvedName) then
    Note := Format('Using %s (saved font not found)', [ResolvedName]);
  if not GFontSettingsApply then
    Note := T('ui.display.terminalFont',
      'The terminal sets the font and cell size.');
  FOpenFontSize := ACur.FontSize;
  FOpenFontSizeIdx := IndexOfDisplayFontSize(ACur.FontSize);
  Result := BuildDisplayDialog(Fonts, FontIdx,
    FOpenFontSizeIdx, IndexOfDisplayZoom(ACur.Zoom),
    IndexOfDisplayBlinkMs(ACur.CursorBlinkMs), ACur.CursorBlink,
    ACur.ShowPanelIcons, Note, Ord(ACur.ShadowStyle), ACur.LineSpacing,
    Ord(ACur.MarkedRowStyle), ACur.SnapFontSize, ClampTextContrast(ACur.TextContrast),
    ClampCellExtra(ACur.CellWidthExtra), ClampCellExtra(ACur.CellHeightExtra));
  DialogSetInputValue(Result, 'font_fallback', ACur.FallbackFont);
  if not GFontSettingsApply then
    RemoveFontControls(Result);
  DialogSetCheckbox(Result, 'caret_underline', ACur.CaretUnderline);
  DialogSetCheckbox(Result, 'edge_borders', ACur.EdgeBorders);
end;

function TSettingsDialogController.BuildInterfaceSource(
  const ACur: TDisplaySettings): TDialogDeclaration;
var
  LanguageNames, ToastItems: TArray<string>;
  LanguageIdx, I: Integer;
begin
  FLanguageCodes := DisplayLanguageItems;
  SetLength(LanguageNames, Length(FLanguageCodes));
  for I := 0 to High(FLanguageCodes) do
    LanguageNames[I] := DisplayLanguageName(FLanguageCodes[I]);
  LanguageIdx := IndexOfFontName(FLanguageCodes, ACur.Language);
  Result := BuildInterfaceDialog(LanguageNames, LanguageIdx, ACur.ShowNotifications);
  DialogSetCheckbox(Result, 'key_hints', ACur.ShowKeyHints);
  DialogSetCheckbox(Result, 'show_title_bar', ACur.ShowTitleBar);
  DialogSetCheckbox(Result, 'show_menu_bar', ACur.ShowMenuBar);
  DialogSetCheckbox(Result, 'show_key_bar', ACur.ShowKeyBar);
  DialogSetCheckbox(Result, 'show_status_line', ACur.ShowStatusLine);
  DialogSetCheckbox(Result, 'alt_menu', ACur.AltOpensMenu);
  DialogSetCheckbox(Result, 'file_drag', ACur.FileDrag);
  DialogSetCheckbox(Result, 'select_folders', ACur.SelectFolders);
  DialogSetCheckbox(Result, 'pack_same_panel', ACur.PackInSamePanel);
  DialogSetCheckbox(Result, 'backspace_drive_menu', ACur.BackspaceDriveMenu);
  DialogSetCheckbox(Result, 'drive_other_folder', ACur.DriveToOtherFolder);
  DialogSetCheckbox(Result, 'space_selects', ACur.SpaceSelects);
  DialogSetCheckbox(Result, 'vim_keys', ACur.VimKeys);
  DialogSetCheckbox(Result, 'keep_panel_focus', ACur.KeepPanelFocus);
  DialogSetCheckbox(Result, 'sticky_quick_search', ACur.StickyQuickSearch);
  DialogSetCheckbox(Result, 'quick_search_keep_empty', ACur.QuickSearchKeepEmpty);
  DialogSetCheckbox(Result, 'quick_search_filter', ACur.QuickSearchFilter);
  DialogSetCheckbox(Result, 'quick_search_keep_filter', ACur.QuickSearchKeepFilter);
  DialogSetCheckbox(Result, 'quick_search_fuzzy', ACur.QuickSearchFuzzy);
  DialogSetCheckbox(Result, 'passive_cursor', ACur.PassiveCursor);
  DialogSetCheckbox(Result, 'column_separators', ACur.ColumnSeparators);
  DialogSetCheckbox(Result, 'show_column_headers', ACur.ShowColumnHeaders);
  DialogSetCheckbox(Result, 'show_sort_letter', ACur.ShowSortLetter);
  DialogSetCheckbox(Result, 'editor_autoindent', ACur.EditorAutoIndent);
  DialogSetCheckbox(Result, 'editor_autowrap', ACur.EditorAutoWrap);
  DialogSetInputValue(Result, 'reflow_width', IntToStr(ACur.EditorReflowWidth));
  DialogSetCheckbox(Result, 'exact_sizes', ACur.ExactSelectionSize);
  DialogSetCheckbox(Result, 'dir_slash', ACur.DirSlash);
  DialogSetCheckbox(Result, 'mark_links', ACur.MarkLinks);
  DialogSetCheckbox(Result, 'ndn_footer', ACur.NdnFooter);
  for I := 0 to High(cToastDurationChoices) do
  begin
    SetLength(ToastItems, I + 1);
    ToastItems[I] := FormatFloat('0.#', cToastDurationChoices[I] / 1000) + ' s';
  end;
  DialogSetListItems(Result, 'toast_time', ToastItems, ToastDurationIndexOf(ACur.ToastMs));
  DialogSetListItems(Result, 'scrollback', ScrollbackItems,
    ScrollbackIndexOf(GConsoleSettings.ScrollbackLines));
  DialogSetCheckbox(Result, 'confirm_paste', GConsoleSettings.ConfirmMultiLinePaste);
  DialogSetCheckbox(Result, 'trim_copy', GConsoleSettings.TrimCopiedSpaces);
  DialogSetCheckbox(Result, 'trim_paste', GConsoleSettings.TrimPastedSpaces);
  DialogSetCheckbox(Result, 'return_panels', GConsoleSettings.ReturnToPanels);
  DialogSetListItems(Result, 'bg_show', BackgroundShowItems,
    BackgroundShowIndexOf(GConsoleSettings.BackgroundShowMs));
end;

procedure TSettingsDialogController.ReadConsoleFields;
begin
  GConsoleSettings.ScrollbackLines :=
    ScrollbackAt(FDialog.GetListSelectedIndex('scrollback'));
  GConsoleSettings.ConfirmMultiLinePaste := FDialog.GetCheckbox('confirm_paste');
  GConsoleSettings.TrimCopiedSpaces := FDialog.GetCheckbox('trim_copy');
  GConsoleSettings.TrimPastedSpaces := FDialog.GetCheckbox('trim_paste');
  GConsoleSettings.ReturnToPanels := FDialog.GetCheckbox('return_panels');
  GConsoleSettings.BackgroundShowMs :=
    BackgroundShowAt(FDialog.GetListSelectedIndex('bg_show'));
end;

procedure TSettingsDialogController.OpenSettings(AStart: TSettingsStart;
  const AFocusId: string);
var
  Cur: TDisplaySettings;
  Display, Iface: TDialogDeclaration;
  InterfaceStart, Start, I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  if Assigned(FOnGetDisplay) then
    Cur := FOnGetDisplay()
  else
    Cur := DefaultDisplaySettings;

  SetKind(hdkDisplay);
  FOpenDisplay := Cur;
  Display := BuildDisplaySource(Cur);
  Iface := BuildInterfaceSource(Cur);
  InterfaceStart := Length(Display.Controls[DialogTabStripIndex(Display.Controls)].Items);
  FSettingsDecl := MergeSettingsPages([Display, Iface], [],
    T('ui.settings.title', 'Settings'), FSettingsPages);
  FSettingsDecl.Controls[DialogTabStripIndex(FSettingsDecl.Controls)].Hint :=
    T('ui.settings.sections', 'Up and Down choose a section; typing narrows the list.');
  FSettingsQuery := '';
  FDialog.Open(FSettingsDecl, FOnCommand);
  FDialog.SetLabelText('search_caption', T('ui.settings.search', 'Search'));
  FDialog.SetLabelText(cSettingsQueryId, '');
  Start := -1;
  case AStart of
    // The first section of the Interface source: the pages after Display's own.
    ssInterface:
      for I := 0 to High(FSettingsPages.Pages) do
        if FSettingsPages.Pages[I] > InterfaceStart then
        begin
          Start := I;
          Break;
        end;
    // The Console section is the last page of the Interface source.
    ssConsole:
      Start := High(FSettingsPages.Pages);
  end;
  if Start >= 0 then
    FDialog.SetTabItems(cSettingsStripId, FSettingsPages.Captions,
      FSettingsPages.Pages, Start);
  if AFocusId <> '' then
    FDialog.FocusControlById(AFocusId);
  Notify;
end;

procedure TSettingsDialogController.OpenDisplay;
begin
  OpenSettings(ssDisplay);
end;

procedure TSettingsDialogController.OpenInterface;
begin
  OpenSettings(ssInterface);
end;

procedure TSettingsDialogController.ApplySettingsQuery;
var
  Matches: TSettingsPages;
begin
  SettingsSectionsMatching(FSettingsDecl, FSettingsPages, FSettingsQuery, Matches);
  FDialog.BeginUpdate;
  try
    FDialog.SetTabItems(cSettingsStripId, Matches.Captions, Matches.Pages, 0);
    FDialog.SetLabelText(cSettingsQueryId, FSettingsQuery);
  finally
    FDialog.EndUpdate;
  end;
end;

function TSettingsDialogController.HandleSettingsFilter(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Chord: TKeyChord;
begin
  Result := False;
  if FDialog.FocusedControlId <> cSettingsStripId then
    Exit;
  Chord := TKeyChord.Make(AKey, AKeyChar, AShift);
  if Chord.IsPrintable and Chord.HasMods([], [ssShift]) then
  begin
    FSettingsQuery := FSettingsQuery + AKeyChar;
    ApplySettingsQuery;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (AKey = vkBack) and (FSettingsQuery <> '') then
  begin
    Delete(FSettingsQuery, Length(FSettingsQuery), 1);
    ApplySettingsQuery;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

function TSettingsDialogController.CollectAvailableProfiles(
  out ATitles, AIds: TArray<string>; const APreferId: string;
  out ASel: Integer): Boolean;
var
  Entries: TProfileEntries;
  I: Integer;
  Prefer: string;
begin
  SetLength(ATitles, 0);
  SetLength(AIds, 0);
  ASel := 0;
  Prefer := CanonicalShellProfileId(APreferId);
  if Trim(APreferId) = '' then
    Prefer := cShellProfileCmd;
  Entries := ProfileEntriesOrdered;
  for I := 0 to High(Entries) do
  begin
    ATitles := ATitles + [Format('%-30s [%s]', [Entries[I].Title,
      ProfileKeyModeTitle(Entries[I].KeyMode)])];
    AIds := AIds + [Entries[I].Id];
    if SameText(Entries[I].Id, Prefer) then
      ASel := I;
  end;
  Result := Length(ATitles) > 0;
end;

procedure TSettingsDialogController.ShowTerminalProfiles(const ASelectId: string);
var
  Entries: TProfileEntries;
  Items: TArray<string>;
  Accents: TArray<TListAccent>;
  Accent: TListAccent;
  I, Sel: Integer;
  Hot: string;
  Prefer: string;
begin
  Entries := ProfileEntriesOrdered;
  SetLength(Items, Length(Entries));
  SetLength(FProfileIds, Length(Entries));
  Prefer := ASelectId;
  if Prefer = '' then
    Prefer := cShellProfileCmd;
  Sel := 0;
  for I := 0 to High(Entries) do
  begin
    FProfileIds[I] := Entries[I].Id;
    if ProfileHotkeyChar(I) <> #0 then
    begin
      Hot := ProfileHotkeyChar(I);
      Accent.Item := I;
      Accent.Col := 0;
      Accent.Len := 1;
      Accents := Accents + [Accent];
    end
    else
      Hot := ' ';
    Items[I] := Format('%s  %-30s [%s]', [Hot, Entries[I].Title,
      ProfileKeyModeTitle(Entries[I].KeyMode)]);
    if Entries[I].EnvName <> '' then
      Items[I] := Items[I] + ' +' + Entries[I].EnvName;
    if SameText(Entries[I].Id, Prefer) then
      Sel := I;
  end;
  SetKind(hdkTerminalProfile);
  FDialog.Open(BuildTerminalProfileDialog(Items, Sel, Accents), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.OpenTerminalProfiles;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  if Length(ProfileEntriesOrdered) = 0 then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.terminalProfile.title', 'New terminal'),
        T('ui.shellProfiles.noneAvailable', 'No shell profiles available'));
    Exit;
  end;
  ShowTerminalProfiles('');
end;

procedure TSettingsDialogController.ShowTerminalEnvChoice(const AShellId: string);
var
  Items: TArray<string>;
  Current: string;
  I, Sel: Integer;
begin
  FEnvTarget := AShellId;
  FEnvNames := EnvProfileNames;
  Current := ProfileEnvName(AShellId);
  SetLength(Items, Length(FEnvNames) + 1);
  Items[0] := T('ui.terminalEnv.none', '(none)');
  Sel := 0;
  for I := 0 to High(FEnvNames) do
  begin
    Items[I + 1] := FEnvNames[I];
    if SameText(FEnvNames[I], Current) then
      Sel := I + 1;
  end;
  SetKind(hdkTerminalEnv);
  FDialog.Open(BuildTerminalEnvDialog(Items, Sel), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.DispatchTerminalEnvCommand(
  const AControlId: string);
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  if (DialogCmdIsAccept(AControlId) or DialogCmdIsListAccept(AControlId, 'profiles')) and
     (Idx >= 0) and (Idx <= Length(FEnvNames)) then
  begin
    if Idx = 0 then
      SetProfileEnvName(FEnvTarget, '')
    else
      SetProfileEnvName(FEnvTarget, FEnvNames[Idx - 1]);
  end;
  // Back to the New terminal list, on the shell profile that was edited.
  ShowTerminalProfiles(FEnvTarget);
end;

procedure TSettingsDialogController.LaunchTerminalProfile(AIndex: Integer);
var
  Cwd: string;
begin
  Cwd := '';
  if Assigned(FOnGetLocalPath) then
    Cwd := FOnGetLocalPath();
  FDialog.Close;
  if (AIndex >= 0) and (AIndex <= High(FProfileIds)) and Assigned(FOnOpenTerminal) then
    FOnOpenTerminal(FProfileIds[AIndex], Cwd);
  SetLength(FProfileIds, 0);
end;

function TSettingsDialogController.HandleTerminalProfileInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Idx, HotIdx: Integer;
  Id, NewId: string;
  Ch: Char;

  procedure Consume;
  begin
    AKey := 0;
    AKeyChar := #0;
  end;

begin
  Result := False;
  Idx := FDialog.GetListSelectedIndex('profiles');
  if (Idx < 0) or (Idx > High(FProfileIds)) then
    Exit;
  Id := FProfileIds[Idx];

  if (AKey in [vkUp, vkDown]) and ([ssCtrl] * AShift <> []) and
     ([ssAlt, ssShift] * AShift = []) then
  begin
    if AKey = vkUp then
      ProfileMove(Id, -1)
    else
      ProfileMove(Id, 1);
    ShowTerminalProfiles(Id);
    Consume;
    Exit(True);
  end;
  if AShift * [ssCtrl, ssAlt, ssShift] <> [] then
    Exit;
  case AKey of
    vkInsert:
      begin
        NewId := ProfileCopyAdd(Id);
        ShowTerminalProfiles(NewId);
        Consume;
        Exit(True);
      end;
    vkDelete:
      begin
        if ProfileCopyDelete(Id) then
        begin
          if Idx > 0 then
            ShowTerminalProfiles(FProfileIds[Idx - 1])
          else
            ShowTerminalProfiles('');
        end;
        Consume;
        Exit(True);
      end;
    vkF4:
      begin
        SetProfileKeyMode(Id, NextProfileKeyMode(ProfileKeyMode(Id)));
        ShowTerminalProfiles(Id);
        Consume;
        Exit(True);
      end;
    vkF6:
      begin
        ShowTerminalEnvChoice(Id);
        Consume;
        Exit(True);
      end;
  end;

  // A profile's number or letter starts it at once.
  if (AKey >= vk0) and (AKey <= vk9) then
    Ch := Char(AKey)
  else if (AKey >= vkNumpad0) and (AKey <= vkNumpad9) then
    Ch := Char(Ord('0') + AKey - vkNumpad0)
  else if (AKey >= vkA) and (AKey <= vkZ) then
    Ch := Char(AKey)
  else
    Ch := AKeyChar;
  HotIdx := ProfileHotkeyIndex(Ch);
  if (HotIdx >= 0) and (HotIdx <= High(FProfileIds)) then
  begin
    LaunchTerminalProfile(HotIdx);
    Consume;
    Exit(True);
  end;
end;

procedure TSettingsDialogController.OpenConsoleProfiles;
var
  Titles: TArray<string>;
  Ids: TArray<string>;
  Sel: Integer;
  CurId: string;
  StartOnLaunch, CwdToPanels, ProgramsInTerminal: Boolean;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  if Assigned(FOnGetConsoleProfile) then
    CurId := FOnGetConsoleProfile()
  else
    CurId := '';
  if not CollectAvailableProfiles(Titles, Ids, CurId, Sel) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.consoleProfile.title', 'Background console'),
        T('ui.shellProfiles.noneAvailable', 'No shell profiles available'));
    Exit;
  end;

  StartOnLaunch := False;
  if Assigned(FOnGetConsoleStartOnLaunch) then
    StartOnLaunch := FOnGetConsoleStartOnLaunch();
  CwdToPanels := True;
  if Assigned(FOnGetConsoleCwdToPanels) then
    CwdToPanels := FOnGetConsoleCwdToPanels();
  ProgramsInTerminal := False;
  if Assigned(FOnGetProgramsInTerminal) then
    ProgramsInTerminal := FOnGetProgramsInTerminal();
  FProfileIds := Ids;
  SetKind(hdkConsoleProfile);
  FDialog.Open(BuildConsoleProfileDialog(Titles, Sel, StartOnLaunch, CwdToPanels,
    ProgramsInTerminal),
    FOnCommand);
  Notify;
end;

const
  cPresetModes: array[0..4] of TPanelColumnMode =
    (pcmSize, pcmDate, pcmFull, pcmCreated, pcmTypes);
  cPresetKeys: array[0..4] of string = ('size', 'date', 'full', 'created', 'types');
  cPresetDefaults: array[0..4] of string = ('Size', 'Date', 'Full', 'Created', 'Types');

// Rows of the column sets list: the built-in wide variants (read-only), then
// the stored sets.
function TSettingsDialogController.ColumnSetRows: TArray<string>;
var
  Sets: TArray<TColumnSet>;
  I: Integer;
begin
  Sets := ColumnSets;
  SetLength(Result, Length(cPresetModes) + Length(Sets));
  for I := 0 to High(cPresetModes) do
    Result[I] := StringReplace(
      T('columnModeMenu.' + cPresetKeys[I], cPresetDefaults[I]), '&', '', []);
  for I := 0 to High(Sets) do
    Result[Length(cPresetModes) + I] := Sets[I].Name;
end;

function IdListed(const AIds: TArray<string>; const AId: string): Boolean;
var
  S: string;
begin
  for S in AIds do
    if SameText(S, AId) then
      Exit(True);
  Result := False;
end;

// Edit loads the selected set into the checkboxes and the name field (OK then
// saves it under that name); Rename gives the selected set the name in the field;
// Delete removes it from the file. The dialog stays open.
procedure TSettingsDialogController.ManageColumnSet(const AControlId: string);
var
  Sets: TArray<TColumnSet>;
  Idx: Integer;
  Cur: TColumnSet;
  NewName: string;
  Cols: TPluginColumns;
  SetIds: TArray<string>;
  I: Integer;
begin
  Sets := ColumnSets;
  Idx := FDialog.GetListSelectedIndex('sets');
  if (Idx < 0) or (Idx > High(Sets) + Length(cPresetModes)) then
    Exit;
  if Idx < Length(cPresetModes) then
  begin
    // A built-in variant cannot be renamed or deleted; Edit loads its columns.
    if DialogCmdIs(AControlId, 'set_rename') or DialogCmdIs(AControlId, 'set_delete') then
      Exit;
    Cur := Default(TColumnSet);
    PresetColumnsConfig(cPresetModes[Idx], Cur.Config);
  end
  else
    Cur := Sets[Idx - Length(cPresetModes)];
  if DialogCmdIs(AControlId, 'set_rename') then
  begin
    NewName := Trim(FDialog.GetInputValue('set_name'));
    if ColumnSetRename(Cur.Name, NewName) then
      FDialog.SetListItems('sets', ColumnSetRows, Idx);
  end
  else if DialogCmdIs(AControlId, 'set_delete') then
  begin
    if ColumnSetDelete(Cur.Name) then
      FDialog.SetListItems('sets', ColumnSetRows, Idx);
  end
  else
  begin
    FColumnsLoadedSet := True;
    FDialog.SetCheckbox('col_ext', Cur.Config.ShowExt);
    FDialog.SetCheckbox('col_size', Cur.Config.ShowSize);
    FDialog.SetCheckbox('col_modified', Cur.Config.ShowModified);
    FDialog.SetCheckbox('col_created', Cur.Config.ShowCreated);
    FDialog.SetCheckbox('col_accessed', Cur.Config.ShowAccessed);
    FDialog.SetCheckbox('col_type', Cur.Config.ShowType);
    FDialog.SetCheckbox('col_attr', Cur.Config.ShowAttr);
    if ColumnSetPluginIds(Cur, FColumnsScheme, SetIds) then
    begin
      Cols := SchemePluginColumns(FColumnsScheme);
      for I := 0 to High(Cols) do
        FDialog.SetCheckbox('pcol_' + IntToStr(I), IdListed(SetIds, Cols[I].Id));
    end;
    // A built-in variant is saved only under a name of its own.
    FDialog.SetInputValue('set_name', Cur.Name);
  end;
end;

procedure TSettingsDialogController.DispatchColumnsCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  Cols: TPluginColumns;
  Ids: TArray<string>;
  I: Integer;
  SetPlugins: TArray<TSetPluginColumns>;
  BriefWidth: Integer;
  ColumnsChanged: Boolean;
begin
  if DialogCmdIs(AControlId, 'set_edit') or DialogCmdIs(AControlId, 'sets') or
     DialogCmdIs(AControlId, 'set_rename') or DialogCmdIs(AControlId, 'set_delete') then
  begin
    // The window clears the dialog kind before every command; the dialog stays up.
    SetKind(hdkColumnsConfig);
    ManageColumnSet(AControlId);
    Exit;
  end;
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    // Built-in columns the scheme's plugin excluded have no checkbox: the
    // setting they hold for other folders stays as it is.
    if BuiltinColumnAvailable(FColumnsScheme, 'ext') then
      FColumnsConfig.ShowExt := FDialog.GetCheckbox('col_ext');
    if BuiltinColumnAvailable(FColumnsScheme, 'size') then
      FColumnsConfig.ShowSize := FDialog.GetCheckbox('col_size');
    if BuiltinColumnAvailable(FColumnsScheme, 'modified') then
      FColumnsConfig.ShowModified := FDialog.GetCheckbox('col_modified');
    if BuiltinColumnAvailable(FColumnsScheme, 'created') then
      FColumnsConfig.ShowCreated := FDialog.GetCheckbox('col_created');
    if BuiltinColumnAvailable(FColumnsScheme, 'accessed') then
      FColumnsConfig.ShowAccessed := FDialog.GetCheckbox('col_accessed');
    if BuiltinColumnAvailable(FColumnsScheme, 'type') then
      FColumnsConfig.ShowType := FDialog.GetCheckbox('col_type');
    if BuiltinColumnAvailable(FColumnsScheme, 'attr') then
      FColumnsConfig.ShowAttr := FDialog.GetCheckbox('col_attr');
    Cols := SchemePluginColumns(FColumnsScheme);
    SetPlugins := nil;
    if Length(Cols) > 0 then
    begin
      Ids := nil;
      for I := 0 to High(Cols) do
        if FDialog.GetCheckbox('pcol_' + IntToStr(I)) then
        begin
          SetLength(Ids, Length(Ids) + 1);
          Ids[High(Ids)] := Cols[I].Id;
        end;
      SetSchemeColumnSelection(FColumnsScheme, Ids);
      SetLength(SetPlugins, 1);
      SetPlugins[0].Scheme := LowerCase(Trim(FColumnsScheme));
      SetPlugins[0].Ids := Ids;
    end;
    // An empty or unreadable entry gives the default width; a number outside
    // the range gives the nearest bound.
    if not TryStrToInt(Trim(FDialog.GetInputValue('brief_width')), BriefWidth) then
      BriefWidth := cBriefColumnWidthDefault;
    GBriefColumnWidth := ClampBriefColumnWidth(BriefWidth);
    if Trim(FDialog.GetInputValue('set_name')) <> '' then
      ColumnSetSave(FDialog.GetInputValue('set_name'), FColumnsConfig, SetPlugins);
    // OK on a dialog opened only for the Brief width must not switch the panel
    // to the Wide columns it was never showing.
    ColumnsChanged := FColumnsLoadedSet or
      not SameColumnsConfig(FColumnsConfig, FColumnsOpenConfig) or
      (ShownPluginSignature(FColumnsScheme) <> FColumnsOpenPlugins);
  end
  else
    ColumnsChanged := False;
  FDialog.Close;
  if Accepted then
  begin
    if ColumnsChanged and Assigned(FOnColumnsAccepted) then
      FOnColumnsAccepted(FColumnsConfig);
    Notify;
  end;
end;

procedure TSettingsDialogController.ReadDisplayFields(var ADisp: TDisplaySettings);
var
  Disp: TDisplaySettings;
  ShadowIdx, SizeIdx, MarkedIdx: Integer;
begin
  Disp := ADisp;
  Disp.FontName := FDialog.GetListSelectedText('fonts');
  Disp.FallbackFont := Trim(FDialog.GetInputValue('font_fallback'));
  SizeIdx := FDialog.GetListSelectedIndex('font_size');
  if SizeIdx = FOpenFontSizeIdx then
    Disp.FontSize := FOpenFontSize
  else
    Disp.FontSize := DisplayFontSizeAt(SizeIdx);
  Disp.Zoom := DisplayZoomAt(FDialog.GetListSelectedIndex('zoom'));
  Disp.CursorBlink := FDialog.GetCheckbox('blink');
  Disp.CursorBlinkMs := DisplayBlinkMsAt(FDialog.GetListSelectedIndex('blink_ms'));
  Disp.ShowPanelIcons := FDialog.GetCheckbox('panel_icons');
  Disp.CaretUnderline := FDialog.GetCheckbox('caret_underline');
  Disp.EdgeBorders := FDialog.GetCheckbox('edge_borders');
  Disp.LineSpacing := FDialog.GetCheckbox('line_spacing');
  Disp.SnapFontSize := FDialog.GetCheckbox('snap_font_size');
  Disp.TextContrast := ClampTextContrast(FDialog.GetListSelectedIndex('text_contrast'));
  Disp.CellWidthExtra := ClampCellExtra(FDialog.GetListSelectedIndex('cell_w'));
  Disp.CellHeightExtra := ClampCellExtra(FDialog.GetListSelectedIndex('cell_h'));
  ShadowIdx := FDialog.GetListSelectedIndex('shadows');
  if (ShadowIdx >= Ord(Low(TShadowStyle))) and (ShadowIdx <= Ord(High(TShadowStyle))) then
    Disp.ShadowStyle := TShadowStyle(ShadowIdx);
  MarkedIdx := FDialog.GetListSelectedIndex('marked_rows');
  if (MarkedIdx >= Ord(Low(TMarkedRowStyle))) and (MarkedIdx <= Ord(High(TMarkedRowStyle))) then
    Disp.MarkedRowStyle := TMarkedRowStyle(MarkedIdx);
  if not GFontSettingsApply then
  begin
    Disp.FontName := FOpenDisplay.FontName;
    Disp.FallbackFont := FOpenDisplay.FallbackFont;
    Disp.FontSize := FOpenDisplay.FontSize;
    Disp.Zoom := FOpenDisplay.Zoom;
    Disp.LineSpacing := FOpenDisplay.LineSpacing;
    Disp.SnapFontSize := FOpenDisplay.SnapFontSize;
    Disp.TextContrast := FOpenDisplay.TextContrast;
    Disp.CellWidthExtra := FOpenDisplay.CellWidthExtra;
    Disp.CellHeightExtra := FOpenDisplay.CellHeightExtra;
  end;
  ADisp := Disp;
end;

procedure TSettingsDialogController.ReadInterfaceFields(var ADisp: TDisplaySettings);
var
  Disp: TDisplaySettings;
  LanguageIdx, I: Integer;
begin
  Disp := ADisp;
  Disp.ShowNotifications := FDialog.GetCheckbox('notifications');
  Disp.ShowKeyHints := FDialog.GetCheckbox('key_hints');
  Disp.ShowTitleBar := FDialog.GetCheckbox('show_title_bar');
  Disp.ShowMenuBar := FDialog.GetCheckbox('show_menu_bar');
  Disp.ShowKeyBar := FDialog.GetCheckbox('show_key_bar');
  Disp.ShowStatusLine := FDialog.GetCheckbox('show_status_line');
  Disp.AltOpensMenu := FDialog.GetCheckbox('alt_menu');
  Disp.FileDrag := FDialog.GetCheckbox('file_drag');
  Disp.SelectFolders := FDialog.GetCheckbox('select_folders');
  Disp.PackInSamePanel := FDialog.GetCheckbox('pack_same_panel');
  Disp.BackspaceDriveMenu := FDialog.GetCheckbox('backspace_drive_menu');
  Disp.DriveToOtherFolder := FDialog.GetCheckbox('drive_other_folder');
  Disp.SpaceSelects := FDialog.GetCheckbox('space_selects');
  Disp.VimKeys := FDialog.GetCheckbox('vim_keys');
  Disp.KeepPanelFocus := FDialog.GetCheckbox('keep_panel_focus');
  Disp.StickyQuickSearch := FDialog.GetCheckbox('sticky_quick_search');
  Disp.QuickSearchKeepEmpty := FDialog.GetCheckbox('quick_search_keep_empty');
  Disp.QuickSearchFilter := FDialog.GetCheckbox('quick_search_filter');
  Disp.QuickSearchKeepFilter := FDialog.GetCheckbox('quick_search_keep_filter');
  Disp.QuickSearchFuzzy := FDialog.GetCheckbox('quick_search_fuzzy');
  Disp.PassiveCursor := FDialog.GetCheckbox('passive_cursor');
  Disp.ColumnSeparators := FDialog.GetCheckbox('column_separators');
  Disp.ShowColumnHeaders := FDialog.GetCheckbox('show_column_headers');
  Disp.ShowSortLetter := FDialog.GetCheckbox('show_sort_letter');
  Disp.EditorAutoIndent := FDialog.GetCheckbox('editor_autoindent');
  Disp.EditorAutoWrap := FDialog.GetCheckbox('editor_autowrap');
  Disp.EditorReflowWidth := EnsureRange(StrToIntDef(Trim(FDialog.GetInputValue('reflow_width')),
    FOpenDisplay.EditorReflowWidth), cEditorReflowMin, cEditorReflowMax);
  I := FDialog.GetListSelectedIndex('toast_time');
  if (I >= 0) and (I <= High(cToastDurationChoices)) then
    Disp.ToastMs := cToastDurationChoices[I]
  else
    Disp.ToastMs := FOpenDisplay.ToastMs;
  Disp.ExactSelectionSize := FDialog.GetCheckbox('exact_sizes');
  Disp.DirSlash := FDialog.GetCheckbox('dir_slash');
  Disp.MarkLinks := FDialog.GetCheckbox('mark_links');
  Disp.NdnFooter := FDialog.GetCheckbox('ndn_footer');
  LanguageIdx := FDialog.GetListSelectedIndex('language');
  if (LanguageIdx >= 0) and (LanguageIdx <= High(FLanguageCodes)) then
    Disp.Language := FLanguageCodes[LanguageIdx]
  else
    Disp.Language := '';
  ADisp := Disp;
end;

procedure TSettingsDialogController.DispatchDisplayCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  Disp: TDisplaySettings;
begin
  if AControlId = 'reset_hints' then
  begin
    if Assigned(FOnResetKeyHints) then
      FOnResetKeyHints();
    Exit;
  end;
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    Disp := FOpenDisplay;
    ReadDisplayFields(Disp);
    ReadInterfaceFields(Disp);
    ReadConsoleFields;
    if Assigned(FOnApplyDisplay) then
      FOnApplyDisplay(Disp);
  end;
  FDialog.Close;
  SetLength(FLanguageCodes, 0);
  if Accepted then
    Notify;
end;

procedure TSettingsDialogController.DispatchInterfaceCommand(
  const AControlId: string);
begin
  DispatchDisplayCommand(AControlId);
end;

procedure TSettingsDialogController.OpenExternalTools;
var
  Tools: TExternalTools;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  Tools := GlobalExternalTools;
  SetKind(hdkExternalTools);
  FDialog.Open(BuildExternalToolsDialog(Tools.ViewerCommand, Tools.EditorCommand),
    FOnCommand);
  Notify;
end;

function TSettingsDialogController.SettingFields: TArray<TSettingField>;
var
  Display, Iface, Merged: TDialogDeclaration;
  Pages: TSettingsPages;
begin
  RequireDialogResource(cResDialogDisplay, Display);
  RequireDialogResource(cResDialogInterface, Iface);
  if not GFontSettingsApply then
    RemoveFontControls(Display);
  Merged := MergeSettingsPages([Display, Iface], [], '', Pages);
  Result := SettingsFields(Merged, Pages);
end;

procedure TSettingsDialogController.OpenSettingField(const AFieldId: string);
begin
  OpenSettings(ssDisplay, AFieldId);
end;

procedure TSettingsDialogController.OpenConsoleOptions;
begin
  OpenSettings(ssConsole);
end;

procedure TSettingsDialogController.ShowMarkdownColors(const ASet: TMdColorSet;
  const AStatus: string; const AFocusId: string);
var
  Decl: TDialogDeclaration;
  Kind: TMdSpanKind;
  Key: string;
  Styles, StyleAttrs: TArray<string>;
  I: Integer;
begin
  Decl := BuildMarkdownColorsDialog;
  SetLength(Styles, MdStyleChoiceCount);
  SetLength(StyleAttrs, MdStyleChoiceCount);
  for I := 0 to High(Styles) do
  begin
    Styles[I] := T('ui.markdownColors.style.' + MdStyleChoiceKey(I), MdStyleChoiceKey(I));
    StyleAttrs[I] := MdStyleChoiceAttrs(I);
  end;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    Key := MdSpanKindKey(Kind);
    DialogSetListItems(Decl, 'md_' + Key + '_style', Styles, MdStyleChoiceOf(ASet[Kind]));
    DialogSetListItemIds(Decl, 'md_' + Key + '_style', StyleAttrs);
    if ASet[Kind].HasFg then
      DialogSetInputValue(Decl, 'md_' + Key + '_fg', ColorToHex(ASet[Kind].Fg));
    if ASet[Kind].HasBg then
      DialogSetInputValue(Decl, 'md_' + Key + '_bg', ColorToHex(ASet[Kind].Bg));
  end;
  if AStatus <> '' then
    DialogSetLabelText(Decl, 'status', AStatus);
  SetKind(hdkMarkdownColors);
  FDialog.Open(Decl, FOnCommand);
  if AFocusId <> '' then
    FDialog.FocusControlById(AFocusId);
  Notify;
end;

function TSettingsDialogController.FindMarkdownColorField(const AFieldId: string;
  out AKind: TMdSpanKind; out AIsBg: Boolean): Boolean;
var
  Kind: TMdSpanKind;
begin
  Result := False;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
    if SameText(AFieldId, 'md_' + MdSpanKindKey(Kind) + '_fg') or
       SameText(AFieldId, 'md_' + MdSpanKindKey(Kind) + '_bg') then
    begin
      AKind := Kind;
      AIsBg := SameText(Copy(AFieldId, Length(AFieldId) - 2, 3), '_bg');
      Exit(True);
    end;
end;

procedure TSettingsDialogController.BeginMarkdownPicker(const AFieldId: string);
var
  Kind: TMdSpanKind;
  IsBg: Boolean;
  Start: TAlphaColor;
  Title: string;
begin
  if not FindMarkdownColorField(AFieldId, Kind, IsBg) then
    Exit;
  // Fields that do not parse yet are left unset; the picker only needs the others.
  ReadMarkdownColorFields(FMdWorking);
  FMdPickField := AFieldId;
  Start := cPickerNoColor;
  if IsBg and FMdWorking[Kind].HasBg then
    Start := FMdWorking[Kind].Bg
  else if not IsBg and FMdWorking[Kind].HasFg then
    Start := FMdWorking[Kind].Fg;
  if IsBg then
    Title := T('ui.colorPicker.background', 'Pick background color')
  else
    Title := T('ui.colorPicker.foreground', 'Pick foreground color');
  SetKind(hdkMarkdownPicker);
  FDialog.Open(BuildColorPickerDialog(Title, Start), FOnCommand);
  Notify;
end;

function TSettingsDialogController.HandleMarkdownColorsInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Kind: TMdSpanKind;
  IsBg: Boolean;
begin
  Result := (AKey = vkF9) and
    FindMarkdownColorField(FDialog.FocusedControlId, Kind, IsBg);
  if Result then
  begin
    BeginMarkdownPicker(FDialog.FocusedControlId);
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TSettingsDialogController.DispatchMarkdownPickerCommand(
  const AControlId: string);
var
  Kind: TMdSpanKind;
  IsBg: Boolean;
  Picked: TAlphaColor;
  Clear: Boolean;
begin
  Clear := DialogCmdIs(AControlId, 'clear');
  if (DialogCmdIsAccept(AControlId) or Clear) and
     FindMarkdownColorField(FMdPickField, Kind, IsBg) then
  begin
    if not Clear then
      HexToColor(FDialog.GetColorPickerHex('picker'), Picked);
    if IsBg then
    begin
      FMdWorking[Kind].HasBg := not Clear;
      if not Clear then
        FMdWorking[Kind].Bg := Picked;
    end
    else
    begin
      FMdWorking[Kind].HasFg := not Clear;
      if not Clear then
        FMdWorking[Kind].Fg := Picked;
    end;
  end;
  ShowMarkdownColors(FMdWorking, '', FMdPickField);
end;

// False when a field holds something other than #RRGGBB or blank.
function TSettingsDialogController.ReadMarkdownColorFields(
  out ASet: TMdColorSet): Boolean;
var
  Kind: TMdSpanKind;
  Key, Fg, Bg: string;
begin
  MdColorSetClear(ASet);
  Result := True;
  for Kind := Low(TMdSpanKind) to High(TMdSpanKind) do
  begin
    Key := MdSpanKindKey(Kind);
    Fg := Trim(FDialog.GetInputValue('md_' + Key + '_fg'));
    Bg := Trim(FDialog.GetInputValue('md_' + Key + '_bg'));
    // Kinds without a style list (rules, table borders) keep whatever they had.
    if FDialog.HasControl('md_' + Key + '_style') then
      MdStyleChoiceApply(ASet[Kind], FDialog.GetListSelectedIndex('md_' + Key + '_style'))
    else
      MdStyleChoiceApply(ASet[Kind], 0);
    if Fg <> '' then
    begin
      ASet[Kind].HasFg := HexToColor(Fg, ASet[Kind].Fg);
      if not ASet[Kind].HasFg then
        Result := False;
    end;
    if Bg <> '' then
    begin
      ASet[Kind].HasBg := HexToColor(Bg, ASet[Kind].Bg);
      if not ASet[Kind].HasBg then
        Result := False;
    end;
  end;
end;

procedure TSettingsDialogController.OpenMarkdownColors;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  MdColorSetClear(FMdInitial);
  if Assigned(FOnGetMarkdown) then
    FMdInitial := FOnGetMarkdown();
  ShowMarkdownColors(FMdInitial, '');
end;

procedure TSettingsDialogController.DispatchMarkdownColorsCommand(
  const AControlId: string);
var
  Colors: TMdColorSet;
  BadColors, PickField: string;
begin
  if DialogCmdIsPick(AControlId, PickField) then
  begin
    BeginMarkdownPicker(PickField);
    Exit;
  end;
  if DialogCmdIs(AControlId, 'reset') then
  begin
    MdColorSetClear(Colors);
    ShowMarkdownColors(Colors, '');
    Exit;
  end;
  if DialogCmdIsReject(AControlId) then
  begin
    FDialog.Close;
    Exit;
  end;
  BadColors := T('ui.markdownColors.badColor', 'Colors must be #RRGGBB, or blank.');
  if not ReadMarkdownColorFields(Colors) then
  begin
    FDialog.SetStatus('status', BadColors);
    SetKind(hdkMarkdownColors);
    Notify;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'import') then
  begin
    FMdWorking := Colors;
    SetKind(hdkMarkdownImport);
    FDialog.Open(BuildMarkdownImportDialog(FMdImportPath, FMdImportPalette), FOnCommand);
    Notify;
    Exit;
  end;
  FDialog.Close;
  if Assigned(FOnSaveMarkdown) then
    FOnSaveMarkdown(FMdInitial, Colors);
  Notify;
end;

procedure TSettingsDialogController.DispatchMarkdownImportCommand(
  const AControlId: string);
var
  Colors: TMdColorSet;
  Failure: TMdImportError;
  Path, Msg: string;
  Palette: Integer;
begin
  if DialogCmdIsAccept(AControlId) then
  begin
    Path := Trim(FDialog.GetInputValue('obs_path'));
    Palette := FDialog.GetListSelectedIndex('obs_palette');
    if not LoadObsidianTheme(Path, Palette = 0, Colors, Failure) then
    begin
      case Failure of
        mieNoPath: Msg := T('ui.markdownColors.import.noPath', 'Enter the path to theme.css.');
        mieNotFound: Msg := T('ui.markdownColors.import.notFound', 'File not found.');
        mieUnreadable: Msg := T('ui.markdownColors.import.unreadable', 'Could not read the file.');
      else
        Msg := T('ui.markdownColors.import.noColors', 'No Obsidian colors found in the file.');
      end;
      FDialog.SetStatus('status', Msg);
      SetKind(hdkMarkdownImport);
      Notify;
      Exit;
    end;
    FMdImportPath := Path;
    FMdImportPalette := Palette;
    FMdWorking := Colors;
  end;
  ShowMarkdownColors(FMdWorking, '');
end;

procedure TSettingsDialogController.DispatchExternalToolsCommand(
  const AControlId: string);
var
  Tools: TExternalTools;
  Accepted, Saved: Boolean;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  Saved := True;
  if Accepted then
  begin
    Tools.ViewerCommand := Trim(FDialog.GetInputValue('viewer'));
    Tools.EditorCommand := Trim(FDialog.GetInputValue('editor'));
    Saved := SetGlobalExternalTools(Tools);
  end;
  FDialog.Close;
  // The new commands are in effect either way; only persisting failed.
  if not Saved and Assigned(FOnShowStub) then
    FOnShowStub(T('ui.externalTools.title', 'External viewer/editor'),
      T('ui.externalTools.saveFailed', 'Could not save') + ' ' +
      DefaultExternalToolsFilePath);
  if Accepted then
    Notify;
end;

procedure TSettingsDialogController.DispatchTerminalProfileCommand(
  const AControlId: string);
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  if DialogCmdIsListAccept(AControlId, 'profiles') then
    LaunchTerminalProfile(Idx)
  else
  begin
    FDialog.Close;
    SetLength(FProfileIds, 0);
  end;
end;

procedure TSettingsDialogController.DispatchConsoleProfileCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted, StartOnLaunch, CwdToPanels, ProgramsInTerminal: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  StartOnLaunch := FDialog.GetCheckbox('start_on_launch');
  CwdToPanels := FDialog.GetCheckbox('cwd_to_panels');
  ProgramsInTerminal := FDialog.GetCheckbox('programs_in_terminal');
  Accepted := DialogCmdIsListAccept(AControlId, 'profiles');
  FDialog.Close;
  if Accepted and Assigned(FOnSetConsoleStartOnLaunch) then
    FOnSetConsoleStartOnLaunch(StartOnLaunch);
  if Accepted and Assigned(FOnSetConsoleCwdToPanels) then
    FOnSetConsoleCwdToPanels(CwdToPanels);
  if Accepted and Assigned(FOnSetProgramsInTerminal) then
    FOnSetProgramsInTerminal(ProgramsInTerminal);
  if Accepted and (Idx >= 0) and (Idx <= High(FProfileIds)) and
     Assigned(FOnSetConsoleProfile) then
    FOnSetConsoleProfile(FProfileIds[Idx]);
  SetLength(FProfileIds, 0);
end;

function TSettingsDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkColumnsConfig: DispatchColumnsCommand(AControlId);
    hdkMaskGroups: DispatchMaskGroupsCommand(AControlId);
    hdkDisplay: DispatchDisplayCommand(AControlId);
    hdkInterface: DispatchInterfaceCommand(AControlId);
    hdkExternalTools: DispatchExternalToolsCommand(AControlId);
    hdkMarkdownColors: DispatchMarkdownColorsCommand(AControlId);
    hdkMarkdownImport: DispatchMarkdownImportCommand(AControlId);
    hdkMarkdownPicker: DispatchMarkdownPickerCommand(AControlId);
    hdkTerminalProfile: DispatchTerminalProfileCommand(AControlId);
    hdkTerminalEnv: DispatchTerminalEnvCommand(AControlId);
    hdkConsoleProfile: DispatchConsoleProfileCommand(AControlId);
  else
    { not a settings dialog }
  end;
end;

end.
