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
    FOnSave: TProc<TArray<TColorCodingGroup>>;
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
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function HandleEditInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function GroupSwatches: TArray<TListSwatch>;
    function TryParseColorFields(var G: TColorCodingGroup): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    function DispatchEditCommand(const AControlId: string): Boolean;
    function DispatchPickerCommand(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
    /// <summary>Receives the edited list when it differs from the active one;
    /// the theme owns where it is stored.</summary>
    property OnSave: TProc<TArray<TColorCodingGroup>> read FOnSave write FOnSave;
  end;

implementation

uses
  uStrings, uKeyChord, uColorPickerControl;

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

// The "Sample" column of the group list: a text cell in each group's normal colors.
function TColorCodingDialogController.GroupSwatches: TArray<TListSwatch>;
var
  I: Integer;
begin
  SetLength(Result, Length(FGroups));
  for I := 0 to High(FGroups) do
  begin
    Result[I].Col := cCCSampleCol;
    Result[I].Text := cCCSampleText;
    Result[I].Fg := FGroups[I].Colors[ccsNormal].Fg;
    Result[I].Bg := FGroups[I].Colors[ccsNormal].Bg;
  end;
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
  FDialog.Open(BuildColorCodingDialog(Items, 0, GroupSwatches), FOnCommand);
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
  FDialog.Open(BuildColorCodingDialog(Items, Sel, GroupSwatches), FOnCommand);
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
    ColorCodingColorText(G.Colors[ccsNormal].Fg, G.Colors[ccsNormal].FgRef),
    ColorCodingColorText(G.Colors[ccsNormal].Bg, G.Colors[ccsNormal].BgRef),
    ColorCodingColorText(G.Colors[ccsSelected].Fg, G.Colors[ccsSelected].FgRef),
    ColorCodingColorText(G.Colors[ccsSelected].Bg, G.Colors[ccsSelected].BgRef),
    ColorCodingColorText(G.Colors[ccsCurrent].Fg, G.Colors[ccsCurrent].FgRef),
    ColorCodingColorText(G.Colors[ccsCurrent].Bg, G.Colors[ccsCurrent].BgRef)),
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
  // A name the dialog opened with can't be removed outright - only ever
  // overridden by MergeColorCodingGroups, never deleted - so soft-disable
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
    ColorCodingParseColorField(FDialog.GetInputValue('cc_normal_fg'),
      G.Colors[ccsNormal].Fg, G.Colors[ccsNormal].FgRef) and
    ColorCodingParseColorField(FDialog.GetInputValue('cc_normal_bg'),
      G.Colors[ccsNormal].Bg, G.Colors[ccsNormal].BgRef) and
    ColorCodingParseColorField(FDialog.GetInputValue('cc_selected_fg'),
      G.Colors[ccsSelected].Fg, G.Colors[ccsSelected].FgRef) and
    ColorCodingParseColorField(FDialog.GetInputValue('cc_selected_bg'),
      G.Colors[ccsSelected].Bg, G.Colors[ccsSelected].BgRef) and
    ColorCodingParseColorField(FDialog.GetInputValue('cc_current_fg'),
      G.Colors[ccsCurrent].Fg, G.Colors[ccsCurrent].FgRef) and
    ColorCodingParseColorField(FDialog.GetInputValue('cc_current_bg'),
      G.Colors[ccsCurrent].Bg, G.Colors[ccsCurrent].BgRef);
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
    FDialog.SetStatus('status', 'Colors must be #RRGGBB, @role or a palette name, or blank.');
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
  Title: string;
  Start: TAlphaColor;
begin
  SnapshotEditFields;
  FPickerFieldId := AFieldId;
  if not HexToColor(ColorCodingFieldValue(FEditFields, AFieldId), Start) then
    Start := cPickerNoColor;
  if ColorCodingFieldIsBg(AFieldId) then
    Title := T('ui.colorPicker.background', 'Pick background color')
  else
    Title := T('ui.colorPicker.foreground', 'Pick foreground color');
  SetKind(hdkColorPicker);
  FDialog.Open(BuildColorPickerDialog(Title, Start), FOnCommand);
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
  if TKeyChord.Make(AKey, AKeyChar, AShift).MatchesAny(vkSpace, [ssCtrl], [ssShift, ssAlt]) then
  begin
    ToggleEnabledSelected;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if TKeyChord.Make(AKey, AKeyChar, AShift).MatchesAny(vkUp, [ssCtrl], [ssShift, ssAlt]) then
  begin
    MoveSelected(-1);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if TKeyChord.Make(AKey, AKeyChar, AShift).MatchesAny(vkDown, [ssCtrl], [ssShift, ssAlt]) then
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
var
  Edited: TArray<TColorCodingGroup>;
  Changed: Boolean;
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
    Edited := Copy(FGroups);
    Changed := ColorCodingGroupsToJson(FGroups) <> ColorCodingGroupsToJson(FOriginal);
    SetLength(FGroups, 0);
    SetLength(FOriginal, 0);
    // Only hand the list over if it changed; comparing the
    // serialized JSON is as exact as a field-by-field diff.
    if Changed and Assigned(FOnSave) then
      FOnSave(Edited);
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
  PickField: string;
begin
  if DialogCmdIsPick(AControlId, PickField) then
  begin
    BeginPicker(PickField);
    Exit(True);
  end;
  SelectAfter := FEditIndex;
  if DialogCmdIsAccept(AControlId) then
  begin
    if not CommitEdit then
    begin
      // Validation failed (status already set) - stay on the edit
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
begin
  if DialogCmdIsAccept(AControlId) then
    ColorCodingSetFieldValue(FEditFields, FPickerFieldId,
      FDialog.GetColorPickerHex('picker'))
  else if DialogCmdIs(AControlId, 'clear') then
    ColorCodingSetFieldValue(FEditFields, FPickerFieldId, '');
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
