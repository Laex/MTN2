unit uDualPanelSettingsDialogs;

{ Theme / columns / terminal-profile pick-list dialogs. Extracted from
  TDualPanelWindow so the host keeps only thin Open forwards. }

interface

uses
  System.SysUtils, System.Classes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uThemeRegistry, uPanelColumns,
  uShellProfiles, uDisplaySettings, uStrings, uExternalTools;

type
  TSettingsKindSetter = reference to procedure(AKind: THostDialogKind);
  TSettingsCanStart = reference to function: Boolean;
  TSettingsPrepareUi = reference to procedure;
  TSettingsGetThemeId = reference to function: string;
  TSettingsSelectTheme = reference to procedure(const AThemeId: string);
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
    FOnGetThemeId: TSettingsGetThemeId;
    FOnSelectTheme: TSettingsSelectTheme;
    FOnGetLocalPath: TSettingsGetLocalPath;
    FOnOpenTerminal: TSettingsOpenTerminal;
    FOnSetConsoleProfile: TSettingsSetConsoleProfile;
    FOnGetConsoleProfile: TSettingsGetConsoleProfile;
    FOnShowStub: TSettingsShowStub;
    FOnGetDisplay: TSettingsGetDisplay;
    FOnApplyDisplay: TSettingsApplyDisplay;
    FThemeIds: TArray<string>;
    FProfileIds: TArray<string>;
    FLanguageCodes: TArray<string>;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    function CollectAvailableProfiles(out ATitles, AIds: TArray<string>;
      const APreferId: string; out ASel: Integer): Boolean;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TSettingsKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TSettingsCanStart; const AOnPrepareUi: TSettingsPrepareUi;
      const AOnGetThemeId: TSettingsGetThemeId;
      const AOnSelectTheme: TSettingsSelectTheme;
      const AOnGetLocalPath: TSettingsGetLocalPath;
      const AOnOpenTerminal: TSettingsOpenTerminal;
      const AOnSetConsoleProfile: TSettingsSetConsoleProfile;
      const AOnGetConsoleProfile: TSettingsGetConsoleProfile;
      const AOnShowStub: TSettingsShowStub;
      const AOnGetDisplay: TSettingsGetDisplay;
      const AOnApplyDisplay: TSettingsApplyDisplay);
    procedure OpenTheme;
    procedure OpenColumns;
    procedure OpenDisplay;
    procedure OpenExternalTools;
    procedure OpenTerminalProfiles;
    procedure OpenConsoleProfiles;
    procedure DispatchThemeCommand(const AControlId: string);
    procedure DispatchColumnsCommand(const AControlId: string);
    procedure DispatchDisplayCommand(const AControlId: string);
    procedure DispatchExternalToolsCommand(const AControlId: string);
    procedure DispatchTerminalProfileCommand(const AControlId: string);
    procedure DispatchConsoleProfileCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

constructor TSettingsDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TSettingsKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TSettingsCanStart;
  const AOnPrepareUi: TSettingsPrepareUi; const AOnGetThemeId: TSettingsGetThemeId;
  const AOnSelectTheme: TSettingsSelectTheme;
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
  FOnGetThemeId := AOnGetThemeId;
  FOnSelectTheme := AOnSelectTheme;
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

procedure TSettingsDialogController.OpenTheme;
var
  Infos: TArray<TThemeInfo>;
  Items: TArray<string>;
  I, Sel: Integer;
  CurId: string;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  Infos := uThemeRegistry.GetAvailableThemes;
  if Assigned(FOnGetThemeId) then
    CurId := FOnGetThemeId()
  else
    CurId := '';
  SetLength(Items, Length(Infos));
  SetLength(FThemeIds, Length(Infos));
  Sel := 0;
  for I := 0 to High(Infos) do
  begin
    Items[I] := Infos[I].DisplayName;
    FThemeIds[I] := Infos[I].Id;
    if SameText(Infos[I].Id, CurId) then
      Sel := I;
  end;

  SetKind(hdkTheme);
  FDialog.Open(BuildThemeDialog(Items, Sel), FOnCommand);
  Notify;
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
  FDialog.Open(BuildDisplayDialog(Fonts, FontIdx,
    IndexOfDisplayFontSize(Cur.FontSize), IndexOfDisplayZoom(Cur.Zoom),
    IndexOfDisplayBlinkMs(Cur.CursorBlinkMs), Cur.CursorBlink,
    Cur.ShowPanelIcons, Note, LanguageNames, LanguageIdx), FOnCommand);
  Notify;
end;

function TSettingsDialogController.CollectAvailableProfiles(
  out ATitles, AIds: TArray<string>; const APreferId: string;
  out ASel: Integer): Boolean;
var
  Profiles: TShellProfileArray;
  I: Integer;
  Prefer: string;
  IsPreferredMatch: Boolean;
begin
  SetLength(ATitles, 0);
  SetLength(AIds, 0);
  ASel := 0;
  Prefer := Trim(APreferId);
  Profiles := EnumerateShellProfiles;
  for I := 0 to High(Profiles) do
  begin
    if not Profiles[I].Available then
      Continue;
    ATitles := ATitles + [Profiles[I].Title];
    AIds := AIds + [Profiles[I].Id];
    if Prefer <> '' then
      IsPreferredMatch := SameText(Profiles[I].Id, Prefer)
    else
      IsPreferredMatch := Profiles[I].Id = cShellProfileCmd;
    if IsPreferredMatch then
      ASel := High(ATitles);
  end;
  Result := Length(ATitles) > 0;
end;

procedure TSettingsDialogController.OpenTerminalProfiles;
var
  Titles: TArray<string>;
  Ids: TArray<string>;
  Sel: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  if not CollectAvailableProfiles(Titles, Ids, '', Sel) then
  begin
    if Assigned(FOnShowStub) then
      FOnShowStub(T('ui.terminalProfile.title', 'New terminal'),
        T('ui.shellProfiles.noneAvailable', 'No shell profiles available'));
    Exit;
  end;

  FProfileIds := Ids;
  SetKind(hdkTerminalProfile);
  FDialog.Open(BuildTerminalProfileDialog(Titles, Sel), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.OpenConsoleProfiles;
var
  Titles: TArray<string>;
  Ids: TArray<string>;
  Sel: Integer;
  CurId: string;
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

  FProfileIds := Ids;
  SetKind(hdkConsoleProfile);
  FDialog.Open(BuildConsoleProfileDialog(Titles, Sel), FOnCommand);
  Notify;
end;

procedure TSettingsDialogController.DispatchThemeCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('themes');
  Accepted := DialogCmdIsListAccept(AControlId, 'themes');
  FDialog.Close;
  if Accepted and (Idx >= 0) and (Idx <= High(FThemeIds)) and
     (FThemeIds[Idx] <> '') and Assigned(FOnSelectTheme) then
    FOnSelectTheme(FThemeIds[Idx]);
  SetLength(FThemeIds, 0);
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
  LanguageIdx: Integer;
begin
  Accepted := DialogCmdIsAccept(AControlId);
  if Accepted then
  begin
    Disp := DefaultDisplaySettings;
    Disp.FontName := FDialog.GetListSelectedText('fonts');
    Disp.FontSize := DisplayFontSizeAt(FDialog.GetListSelectedIndex('font_size'));
    Disp.Zoom := DisplayZoomAt(FDialog.GetListSelectedIndex('zoom'));
    Disp.CursorBlink := FDialog.GetCheckbox('blink');
    Disp.CursorBlinkMs := DisplayBlinkMsAt(FDialog.GetListSelectedIndex('blink_ms'));
    Disp.ShowPanelIcons := FDialog.GetCheckbox('panel_icons');
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
  Accepted: Boolean;
  Cwd: string;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  Accepted := DialogCmdIsListAccept(AControlId, 'profiles');
  FDialog.Close;
  Cwd := '';
  if Assigned(FOnGetLocalPath) then
    Cwd := FOnGetLocalPath();
  if Accepted and (Idx >= 0) and (Idx <= High(FProfileIds)) and
     Assigned(FOnOpenTerminal) then
    FOnOpenTerminal(FProfileIds[Idx], Cwd);
  SetLength(FProfileIds, 0);
end;

procedure TSettingsDialogController.DispatchConsoleProfileCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('profiles');
  Accepted := DialogCmdIsListAccept(AControlId, 'profiles');
  FDialog.Close;
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
    hdkTheme: DispatchThemeCommand(AControlId);
    hdkColumnsConfig: DispatchColumnsCommand(AControlId);
    hdkDisplay: DispatchDisplayCommand(AControlId);
    hdkExternalTools: DispatchExternalToolsCommand(AControlId);
    hdkTerminalProfile: DispatchTerminalProfileCommand(AControlId);
    hdkConsoleProfile: DispatchConsoleProfileCommand(AControlId);
  else
    { not a settings dialog }
  end;
end;

end.
