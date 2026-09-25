unit uDualPanelColorCoding;

{ Color-coding list / editor / picker dialogs (hdkColorCoding,
  hdkColorCodingEdit, hdkColorPicker). Extracted from TDualPanelWindow so
  the host keeps only a thin OpenColorCodingDialog + dispatch/input forward. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uColorCoding,
  uColorCodingEditHelpers, uFileFind;

type
  TColorCodingKindSetter = reference to procedure(AKind: THostDialogKind);
  TColorCodingCanStart = reference to function: Boolean;
  TColorCodingPrepareUi = reference to procedure;

  TColorCodingDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TColorCodingKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TColorCodingCanStart;
    FOnPrepareUi: TColorCodingPrepareUi;
    FGroups: TArray<TColorCodingGroup>;
    FOriginal: TArray<TColorCodingGroup>;
    FEditIndex: Integer;
    FEditFields: TColorCodingEditFields;
    FPickerFieldId: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TColorCodingKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TColorCodingCanStart;
      const AOnPrepareUi: TColorCodingPrepareUi);
    procedure OpenList;
    procedure RefreshList(ASelectedIndex: Integer = -1);
    procedure BeginAdd;
    procedure BeginEdit(AIndex: Integer);
    procedure DeleteSelected;
    procedure ToggleEnabledSelected;
    procedure MoveSelected(ADelta: Integer);
    function CommitEdit: Boolean;
    procedure SnapshotEditFields;
    procedure ReopenEditFromFields;
    procedure BeginPicker(const AFieldId: string);
    procedure SyncHexFromPreset;
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleEditInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function TryParseColorFields(var G: TColorCodingGroup): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    function DispatchEditCommand(const AControlId: string): Boolean;
    function DispatchPickerCommand(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  uStrings;

constructor TColorCodingDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TColorCodingKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TColorCodingCanStart;
  const AOnPrepareUi: TColorCodingPrepareUi);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FEditIndex := -1;
end;

procedure TColorCodingDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TColorCodingDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TColorCodingDialogController.OpenList;
var
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  FGroups := GetActiveColorCodingGroups;
  FOriginal := Copy(FGroups);
  SetLength(Items, Length(FGroups));
  for I := 0 to High(FGroups) do
    Items[I] := ColorCodingDisplayLabel(FGroups[I]);

  SetKind(hdkColorCoding);
  FDialog.Open(BuildColorCodingDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.RefreshList(ASelectedIndex: Integer);
var
  Items: TArray<string>;
  I, Sel: Integer;
begin
  if not Assigned(FDialog) then
    Exit;
  if ASelectedIndex >= 0 then
    Sel := ASelectedIndex
  else
    Sel := FDialog.GetListSelectedIndex('groups');
  SetLength(Items, Length(FGroups));
  for I := 0 to High(FGroups) do
    Items[I] := ColorCodingDisplayLabel(FGroups[I]);
  if Sel > High(Items) then
    Sel := High(Items);
  if Sel < 0 then
    Sel := 0;
  SetKind(hdkColorCoding);
  FDialog.Open(BuildColorCodingDialog(Items, Sel), FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.BeginAdd;
begin
  FEditIndex := -1;
  SetKind(hdkColorCodingEdit);
  FDialog.Open(BuildColorCodingEditDialog('', '', 0, True, '', '', '', '', '', ''),
    FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.BeginEdit(AIndex: Integer);
var
  G: TColorCodingGroup;
  ApplyToIdx: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FGroups)) then
    Exit;
  G := FGroups[AIndex];
  FEditIndex := AIndex;
  case G.ApplyTo of
    ccaFilesOnly: ApplyToIdx := 1;
    ccaDirsOnly: ApplyToIdx := 2;
  else
    ApplyToIdx := 0;
  end;
  SetKind(hdkColorCodingEdit);
  FDialog.Open(BuildColorCodingEditDialog(G.Name, string.Join(';', G.Masks),
    ApplyToIdx, G.Enabled,
    ColorToHex(G.Colors[ccsNormal].Fg), ColorToHex(G.Colors[ccsNormal].Bg),
    ColorToHex(G.Colors[ccsSelected].Fg), ColorToHex(G.Colors[ccsSelected].Bg),
    ColorToHex(G.Colors[ccsCurrent].Fg), ColorToHex(G.Colors[ccsCurrent].Bg)),
    FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.DeleteSelected;
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('groups');
  if (Idx < 0) or (Idx > High(FGroups)) then
    Exit;
  // A name the dialog opened with can't be removed outright — only ever
  // overridden by MergeColorCodingGroups, never deleted — so soft-disable
  // it instead; a name added this session (not yet saved anywhere) can just
  // go away.
  if ColorCodingNameExistsIn(FOriginal, FGroups[Idx].Name) then
  begin
    FGroups[Idx].Enabled := False;
    RefreshList(Idx);
  end
  else
  begin
    ColorCodingArrayDelete(FGroups, Idx);
    RefreshList(Idx);
  end;
end;

procedure TColorCodingDialogController.ToggleEnabledSelected;
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('groups');
  if (Idx < 0) or (Idx > High(FGroups)) then
    Exit;
  FGroups[Idx].Enabled := not FGroups[Idx].Enabled;
  RefreshList(Idx);
end;

procedure TColorCodingDialogController.MoveSelected(ADelta: Integer);
var
  Idx, NewIdx: Integer;
  Tmp: TColorCodingGroup;
begin
  Idx := FDialog.GetListSelectedIndex('groups');
  if (Idx < 0) or (Idx > High(FGroups)) then
    Exit;
  NewIdx := Idx + ADelta;
  if (NewIdx < 0) or (NewIdx > High(FGroups)) then
    Exit;
  Tmp := FGroups[Idx];
  FGroups[Idx] := FGroups[NewIdx];
  FGroups[NewIdx] := Tmp;
  RefreshList(NewIdx);
end;

function TColorCodingDialogController.TryParseColorFields(
  var G: TColorCodingGroup): Boolean;
begin
  Result :=
    ColorCodingParseHexField(FDialog.GetInputValue('cc_normal_fg'), G.Colors[ccsNormal].Fg) and
    ColorCodingParseHexField(FDialog.GetInputValue('cc_normal_bg'), G.Colors[ccsNormal].Bg) and
    ColorCodingParseHexField(FDialog.GetInputValue('cc_selected_fg'), G.Colors[ccsSelected].Fg) and
    ColorCodingParseHexField(FDialog.GetInputValue('cc_selected_bg'), G.Colors[ccsSelected].Bg) and
    ColorCodingParseHexField(FDialog.GetInputValue('cc_current_fg'), G.Colors[ccsCurrent].Fg) and
    ColorCodingParseHexField(FDialog.GetInputValue('cc_current_bg'), G.Colors[ccsCurrent].Bg);
end;

function TColorCodingDialogController.CommitEdit: Boolean;
var
  G: TColorCodingGroup;
  NameVal, MaskVal: string;
  ApplyToIdx: Integer;
begin
  Result := False;
  MaskVal := Trim(FDialog.GetInputValue('cc_mask'));
  if MaskVal = '' then
  begin
    FDialog.SetStatus('status', 'Mask is required.');
    Exit;
  end;
  NameVal := Trim(FDialog.GetInputValue('cc_name'));
  if NameVal = '' then
    NameVal := MaskVal;
  G.Name := NameVal;
  G.Masks := SplitMasks(MaskVal);
  ApplyToIdx := FDialog.GetListSelectedIndex('cc_applyto');
  case ApplyToIdx of
    1: G.ApplyTo := ccaFilesOnly;
    2: G.ApplyTo := ccaDirsOnly;
  else
    G.ApplyTo := ccaFilesAndDirs;
  end;
  G.Enabled := FDialog.GetCheckbox('cc_enabled');
  if not TryParseColorFields(G) then
  begin
    FDialog.SetStatus('status', 'Colors must be #RRGGBB, or blank.');
    Exit;
  end;
  if FEditIndex < 0 then
    FGroups := FGroups + [G]
  else if FEditIndex <= High(FGroups) then
    FGroups[FEditIndex] := G;
  Result := True;
end;

procedure TColorCodingDialogController.SnapshotEditFields;
begin
  FEditFields.Name := FDialog.GetInputValue('cc_name');
  FEditFields.Mask := FDialog.GetInputValue('cc_mask');
  FEditFields.ApplyToIdx := FDialog.GetListSelectedIndex('cc_applyto');
  FEditFields.Enabled := FDialog.GetCheckbox('cc_enabled');
  FEditFields.NormalFg := FDialog.GetInputValue('cc_normal_fg');
  FEditFields.NormalBg := FDialog.GetInputValue('cc_normal_bg');
  FEditFields.SelectedFg := FDialog.GetInputValue('cc_selected_fg');
  FEditFields.SelectedBg := FDialog.GetInputValue('cc_selected_bg');
  FEditFields.CurrentFg := FDialog.GetInputValue('cc_current_fg');
  FEditFields.CurrentBg := FDialog.GetInputValue('cc_current_bg');
end;

procedure TColorCodingDialogController.ReopenEditFromFields;
begin
  SetKind(hdkColorCodingEdit);
  FDialog.Open(BuildColorCodingEditDialog(FEditFields.Name,
    FEditFields.Mask, FEditFields.ApplyToIdx,
    FEditFields.Enabled,
    FEditFields.NormalFg, FEditFields.NormalBg,
    FEditFields.SelectedFg, FEditFields.SelectedBg,
    FEditFields.CurrentFg, FEditFields.CurrentBg),
    FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.BeginPicker(const AFieldId: string);
var
  CurrentHex, Title: string;
  IsBg: Boolean;
  Labels, Hexes: TArray<string>;
  PresetIdx, I: Integer;
begin
  SnapshotEditFields;
  FPickerFieldId := AFieldId;
  CurrentHex := ColorCodingFieldValue(FEditFields, AFieldId);
  IsBg := ColorCodingFieldIsBg(AFieldId);
  if IsBg then
    Title := T('ui.colorPicker.background', 'Pick background color')
  else
    Title := T('ui.colorPicker.foreground', 'Pick foreground color');
  ColorPickerPresets(Labels, Hexes);
  PresetIdx := 0;
  if CurrentHex <> '' then
    for I := 0 to High(Hexes) do
      if SameText(Hexes[I], CurrentHex) then
      begin
        PresetIdx := I;
        Break;
      end;
  SetKind(hdkColorPicker);
  FDialog.Open(BuildColorPickerDialog(Title, CurrentHex, Labels, PresetIdx, IsBg),
    FOnCommand);
  Notify;
end;

procedure TColorCodingDialogController.SyncHexFromPreset;
var
  Labels, Hexes: TArray<string>;
  Idx: Integer;
begin
  if not SameText(FDialog.FocusedControlId, 'picker_presets') then
    Exit;
  Idx := FDialog.GetListSelectedIndex('picker_presets');
  ColorPickerPresets(Labels, Hexes);
  if (Idx < 0) or (Idx > High(Hexes)) then
    Exit;
  FDialog.SetInputValue('picker_hex', Hexes[Idx]);
  Notify;
end;

function TColorCodingDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if AKey = vkInsert then
  begin
    BeginAdd;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkF4 then
  begin
    BeginEdit(FDialog.GetListSelectedIndex('groups'));
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkDelete then
  begin
    DeleteSelected;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (ssCtrl in AShift) and (AKey = vkSpace) then
  begin
    ToggleEnabledSelected;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (ssCtrl in AShift) and (AKey = vkUp) then
  begin
    MoveSelected(-1);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (ssCtrl in AShift) and (AKey = vkDown) then
  begin
    MoveSelected(1);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

function TColorCodingDialogController.HandleEditInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  FieldId: string;
begin
  Result := False;
  if AKey <> vkF9 then
    Exit;
  FieldId := FDialog.FocusedControlId;
  if not ColorCodingFieldIdIsColorField(FieldId) then
    Exit;
  BeginPicker(FieldId);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

procedure TColorCodingDialogController.DispatchListCommand(
  const AControlId: string);
begin
  if DialogCmdIs(AControlId, 'add') then
    BeginAdd
  else if DialogCmdIs(AControlId, 'edit') then
    BeginEdit(FDialog.GetListSelectedIndex('groups'))
  else if DialogCmdIs(AControlId, 'delete') then
    DeleteSelected
  else if DialogCmdIs(AControlId, 'moveup') then
    MoveSelected(-1)
  else if DialogCmdIs(AControlId, 'movedown') then
    MoveSelected(1)
  else if DialogCmdIsAccept(AControlId) then
  begin
    FDialog.Close;
    // Only touch the theme file if the effective group list actually
    // changed — comparing serialized JSON is simpler and just as
    // correct as a field-by-field diff (uColorCoding.GetActiveThemeFileName).
    if ColorCodingGroupsToJson(FGroups) <> ColorCodingGroupsToJson(FOriginal) then
    begin
      SaveActiveThemeFileColoring(FGroups);
      ReloadColorCoding('');
    end;
    SetLength(FGroups, 0);
    SetLength(FOriginal, 0);
  end
  else
  begin
    // Cancel or dismiss: discard the working copy, nothing is written.
    FDialog.Close;
    SetLength(FGroups, 0);
    SetLength(FOriginal, 0);
  end;
end;

function TColorCodingDialogController.DispatchEditCommand(
  const AControlId: string): Boolean;
var
  SelectAfter: Integer;
begin
  SelectAfter := FEditIndex;
  if DialogCmdIsAccept(AControlId) then
  begin
    if not CommitEdit then
    begin
      // Validation failed (status already set) — stay on the edit
      // dialog rather than falling through to Close/Refresh below.
      SetKind(hdkColorCodingEdit);
      Notify;
      Exit(False);
    end;
    if SelectAfter < 0 then
      SelectAfter := High(FGroups);
  end;
  FDialog.Close;
  RefreshList(SelectAfter);
  Result := True;
end;

function TColorCodingDialogController.DispatchPickerCommand(
  const AControlId: string): Boolean;
var
  PickedHex: string;
  PresetIdx: Integer;
  PresetLabels, PresetHexes: TArray<string>;
  DummyColor: TAlphaColor;
begin
  if DialogCmdIsAccept(AControlId) then
  begin
    PickedHex := Trim(FDialog.GetInputValue('picker_hex'));
    if PickedHex = '' then
    begin
      // Nothing typed — fall back to whichever preset is highlighted.
      PresetIdx := FDialog.GetListSelectedIndex('picker_presets');
      ColorPickerPresets(PresetLabels, PresetHexes);
      if (PresetIdx >= 0) and (PresetIdx <= High(PresetHexes)) then
        PickedHex := PresetHexes[PresetIdx];
    end
    else if not HexToColor(PickedHex, DummyColor) then
    begin
      FDialog.SetStatus('status',
        'Enter a valid #RRGGBB color, or leave blank to use the preset above.');
      SetKind(hdkColorPicker);
      Notify;
      Exit(False);
    end;
    ColorCodingSetFieldValue(FEditFields, FPickerFieldId, PickedHex);
  end;
  FDialog.Close;
  ReopenEditFromFields;
  Result := True;
end;

function TColorCodingDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkColorCoding: DispatchListCommand(AControlId);
    hdkColorCodingEdit: Result := DispatchEditCommand(AControlId);
    hdkColorPicker: Result := DispatchPickerCommand(AControlId);
  else
    { not a color-coding dialog }
  end;
end;

end.
