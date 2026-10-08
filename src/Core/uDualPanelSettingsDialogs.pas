unit uDualPanelSettingsDialogs;

{ Columns / display / Markdown colors / terminal-profile dialogs. Extracted from
  TDualPanelWindow so the host keeps only thin Open forwards. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uPanelColumns,
  uShellProfiles, uDisplaySettings, uStrings, uExternalTools, uMarkdownColors, uThemeTypes;

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

  TSettingsDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TSettingsKindSetter;
    FOnNotify: TProc;
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
    FOnShowStub: TSettingsShowStub;
    FOnGetDisplay: TSettingsGetDisplay;
    FOnApplyDisplay: TSettingsApplyDisplay;
    FProfileIds: TArray<string>;
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
    /// <summary>Display dialog: the size it opened with (pixels) and its
    /// list row. OK without touching the size keeps the exact value -- a
    /// size set outside the list (session.json) is not rounded to it.</summary>
    FOpenFontSize: Single;
    FOpenFontSizeIdx: Integer;
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
    procedure LaunchTerminalProfile(AIndex: Integer);
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
    procedure OpenColumns;
    procedure OpenDisplay;
    procedure OpenExternalTools;
    procedure OpenConsoleOptions;
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
    procedure DispatchColumnsCommand(const AControlId: string);
    procedure DispatchDisplayCommand(const AControlId: string);
    procedure DispatchExternalToolsCommand(const AControlId: string);
    procedure DispatchConsoleOptionsCommand(const AControlId: string);
    procedure DispatchMarkdownColorsCommand(const AControlId: string);
    procedure DispatchMarkdownImportCommand(const AControlId: string);
    procedure DispatchMarkdownPickerCommand(const AControlId: string);
    /// <summary>F9 on a color field of the Markdown colors dialog opens the picker.</summary>
    function HandleMarkdownColorsInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchTerminalProfileCommand(const AControlId: string);
    /// <summary>Quick-launch keys, Ins / Del / Ctrl+Up / Ctrl+Down / F4 of the
    /// New terminal list.</summary>
    function HandleTerminalProfileInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchConsoleProfileCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  uDialogResources, uColorCoding, uColorPickerControl, uConsoleSettings,
  uShellProfileOptions;

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

procedure TSettingsDialogController.OpenColumns;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  SetKind(hdkColumnsConfig);
  FDialog.Open(BuildColumnsConfigDialog(
    GCustomColumnsConfig.ShowExt, GCustomColumnsConfig.ShowSize,
    GCustomColumnsConfig.ShowModified, GCustomColumnsConfig.ShowCreated,
    GCustomColumnsConfig.ShowAccessed, GCustomColumnsConfig.ShowType,
    GCustomColumnsConfig.ShowAttr), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.OpenDisplay;
var
  Cur: TDisplaySettings;
  Decl: TDialogDeclaration;
  Fonts: TArray<string>;
  ResolvedName, Note: string;
  FontIdx: Integer;
  LanguageNames: TArray<string>;
  LanguageIdx, I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  if Assigned(FOnGetDisplay) then
    Cur := FOnGetDisplay()
  else
    Cur := DefaultDisplaySettings;
  ResolvedName := ResolveMonospaceFontFamily(Cur.FontName);
  Fonts := EnumerateMonospaceFontFamilies;
  EnsureFontInList(Fonts, ResolvedName);
  FontIdx := IndexOfFontName(Fonts, ResolvedName);
  Note := '';
  if (Trim(Cur.FontName) <> '') and not SameText(Cur.FontName, ResolvedName) then
    Note := Format('Using %s (saved font not found)', [ResolvedName]);

  FLanguageCodes := DisplayLanguageItems;
  SetLength(LanguageNames, Length(FLanguageCodes));
  for I := 0 to High(FLanguageCodes) do
    LanguageNames[I] := DisplayLanguageName(FLanguageCodes[I]);
  LanguageIdx := IndexOfFontName(FLanguageCodes, Cur.Language);

  SetKind(hdkDisplay);
  FOpenFontSize := Cur.FontSize;
  FOpenFontSizeIdx := IndexOfDisplayFontSize(Cur.FontSize);
  Decl := BuildDisplayDialog(Fonts, FontIdx,
    FOpenFontSizeIdx, IndexOfDisplayZoom(Cur.Zoom),
    IndexOfDisplayBlinkMs(Cur.CursorBlinkMs), Cur.CursorBlink,
    Cur.ShowPanelIcons, Note, LanguageNames, LanguageIdx,
    Cur.ShowNotifications, Ord(Cur.ShadowStyle), Cur.LineSpacing,
    Ord(Cur.MarkedRowStyle), Cur.SnapFontSize, ClampTextContrast(Cur.TextContrast),
    ClampCellExtra(Cur.CellWidthExtra), ClampCellExtra(Cur.CellHeightExtra));
  DialogSetCheckbox(Decl, 'show_title_bar', Cur.ShowTitleBar);
  DialogSetCheckbox(Decl, 'show_menu_bar', Cur.ShowMenuBar);
  DialogSetCheckbox(Decl, 'file_drag', Cur.FileDrag);
  DialogSetCheckbox(Decl, 'passive_cursor', Cur.PassiveCursor);
  DialogSetCheckbox(Decl, 'show_key_bar', Cur.ShowKeyBar);
  DialogSetCheckbox(Decl, 'show_status_line', Cur.ShowStatusLine);
  DialogSetCheckbox(Decl, 'select_folders', Cur.SelectFolders);
  FDialog.Open(Decl, FOnCommand);
  Notify;
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
    ATitles := ATitles + [Entries[I].Title];
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
  StartOnLaunch, CwdToPanels: Boolean;
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
  FProfileIds := Ids;
  SetKind(hdkConsoleProfile);
  FDialog.Open(BuildConsoleProfileDialog(Titles, Sel, StartOnLaunch, CwdToPanels),
    FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.DispatchColumnsCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    GCustomColumnsConfig.ShowExt := FDialog.GetCheckbox('col_ext');
    GCustomColumnsConfig.ShowSize := FDialog.GetCheckbox('col_size');
    GCustomColumnsConfig.ShowModified := FDialog.GetCheckbox('col_modified');
    GCustomColumnsConfig.ShowCreated := FDialog.GetCheckbox('col_created');
    GCustomColumnsConfig.ShowAccessed := FDialog.GetCheckbox('col_accessed');
    GCustomColumnsConfig.ShowType := FDialog.GetCheckbox('col_type');
    GCustomColumnsConfig.ShowAttr := FDialog.GetCheckbox('col_attr');
  end;
  FDialog.Close;
  if Accepted then
    Notify;
end;

procedure TSettingsDialogController.DispatchDisplayCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  Disp: TDisplaySettings;
  LanguageIdx, ShadowIdx, SizeIdx, MarkedIdx: Integer;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    Disp := DefaultDisplaySettings;
    Disp.FontName := FDialog.GetListSelectedText('fonts');
    SizeIdx := FDialog.GetListSelectedIndex('font_size');
    if SizeIdx = FOpenFontSizeIdx then
      Disp.FontSize := FOpenFontSize
    else
      Disp.FontSize := DisplayFontSizeAt(SizeIdx);
    Disp.Zoom := DisplayZoomAt(FDialog.GetListSelectedIndex('zoom'));
    Disp.CursorBlink := FDialog.GetCheckbox('blink');
    Disp.CursorBlinkMs := DisplayBlinkMsAt(FDialog.GetListSelectedIndex('blink_ms'));
    Disp.ShowPanelIcons := FDialog.GetCheckbox('panel_icons');
    Disp.ShowNotifications := FDialog.GetCheckbox('notifications');
    Disp.ShowTitleBar := FDialog.GetCheckbox('show_title_bar');
    Disp.ShowMenuBar := FDialog.GetCheckbox('show_menu_bar');
    Disp.FileDrag := FDialog.GetCheckbox('file_drag');
    Disp.PassiveCursor := FDialog.GetCheckbox('passive_cursor');
    Disp.ShowKeyBar := FDialog.GetCheckbox('show_key_bar');
    Disp.ShowStatusLine := FDialog.GetCheckbox('show_status_line');
    Disp.LineSpacing := FDialog.GetCheckbox('line_spacing');
    Disp.SnapFontSize := FDialog.GetCheckbox('snap_font_size');
    Disp.TextContrast := ClampTextContrast(FDialog.GetListSelectedIndex('text_contrast'));
    Disp.CellWidthExtra := ClampCellExtra(FDialog.GetListSelectedIndex('cell_w'));
    Disp.CellHeightExtra := ClampCellExtra(FDialog.GetListSelectedIndex('cell_h'));
    Disp.SelectFolders := FDialog.GetCheckbox('select_folders');
    ShadowIdx := FDialog.GetListSelectedIndex('shadows');
    if (ShadowIdx >= Ord(Low(TShadowStyle))) and (ShadowIdx <= Ord(High(TShadowStyle))) then
      Disp.ShadowStyle := TShadowStyle(ShadowIdx);
    MarkedIdx := FDialog.GetListSelectedIndex('marked_rows');
    if (MarkedIdx >= Ord(Low(TMarkedRowStyle))) and (MarkedIdx <= Ord(High(TMarkedRowStyle))) then
      Disp.MarkedRowStyle := TMarkedRowStyle(MarkedIdx);
    LanguageIdx := FDialog.GetListSelectedIndex('language');
    if (LanguageIdx >= 0) and (LanguageIdx <= High(FLanguageCodes)) then
      Disp.Language := FLanguageCodes[LanguageIdx]
    else
      Disp.Language := '';
    if Assigned(FOnApplyDisplay) then
      FOnApplyDisplay(Disp);
  end;
  FDialog.Close;
  SetLength(FLanguageCodes, 0);
  if Accepted then
    Notify;
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

procedure TSettingsDialogController.OpenConsoleOptions;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  SetKind(hdkConsoleOptions);
  FDialog.Open(BuildConsoleOptionsDialog(
    ScrollbackIndexOf(GConsoleSettings.ScrollbackLines),
    GConsoleSettings.ConfirmMultiLinePaste, GConsoleSettings.TrimCopiedSpaces,
    GConsoleSettings.TrimPastedSpaces, GConsoleSettings.ReturnToPanels,
    BackgroundShowIndexOf(GConsoleSettings.BackgroundShowMs)), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.DispatchConsoleOptionsCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
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
  FDialog.Close;
  if Accepted then
    Notify;
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
  Accepted, StartOnLaunch, CwdToPanels: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  StartOnLaunch := FDialog.GetCheckbox('start_on_launch');
  CwdToPanels := FDialog.GetCheckbox('cwd_to_panels');
  Accepted := DialogCmdIsListAccept(AControlId, 'profiles');
  FDialog.Close;
  if Accepted and Assigned(FOnSetConsoleStartOnLaunch) then
    FOnSetConsoleStartOnLaunch(StartOnLaunch);
  if Accepted and Assigned(FOnSetConsoleCwdToPanels) then
    FOnSetConsoleCwdToPanels(CwdToPanels);
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
    hdkDisplay: DispatchDisplayCommand(AControlId);
    hdkExternalTools: DispatchExternalToolsCommand(AControlId);
    hdkConsoleOptions: DispatchConsoleOptionsCommand(AControlId);
    hdkMarkdownColors: DispatchMarkdownColorsCommand(AControlId);
    hdkMarkdownImport: DispatchMarkdownImportCommand(AControlId);
    hdkMarkdownPicker: DispatchMarkdownPickerCommand(AControlId);
    hdkTerminalProfile: DispatchTerminalProfileCommand(AControlId);
    hdkConsoleProfile: DispatchConsoleProfileCommand(AControlId);
  else
    { not a settings dialog }
  end;
end;

end.
