unit uDualPanelUserAssociations;

{ File associations dialog: list + add/edit/delete of user-defined Enter
  overrides (uUserAssociations.pas). Mirrors uDualPanelSshConnections.pas's
  shape (list dialog + a plain-fields editor) -- Ins/F2/Del on the list add,
  edit, and delete a rule, same as the hotlist/workspaces/SSH dialogs. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uUserAssociations, uStrings;

type
  TUserAssocKindSetter = reference to procedure(AKind: THostDialogKind);
  TUserAssocCanStart = reference to function: Boolean;
  TUserAssocPrepareUi = reference to procedure;
  TUserAssocUnfocusCmd = reference to procedure;

  TUserAssociationsDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TUserAssocKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TUserAssocCanStart;
    FOnPrepareUi: TUserAssocPrepareUi;
    FOnUnfocusCmd: TUserAssocUnfocusCmd;
    FRules: TArray<TUserAssocRule>;
    FEditExtension: string; // '' while adding a new rule
    FPendingExtension: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure BeginDelete(AIndex: Integer);
    procedure SaveAndReload;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TUserAssocKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TUserAssocCanStart; const AOnPrepareUi: TUserAssocPrepareUi;
      const AOnUnfocusCmd: TUserAssocUnfocusCmd);
    procedure OpenList;
    procedure BeginAdd;
    procedure BeginEdit(AIndex: Integer);
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    procedure DispatchEditCommand(const AControlId: string);
    procedure DispatchConfirmCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

function ActionToDropdownIndex(AAction: TUserAssocAction): Integer;
begin
  case AAction of
    uaaView: Result := 0;
    uaaEdit: Result := 1;
    uaaShell: Result := 2;
    uaaCommand: Result := 3;
  else
    Result := 0;
  end;
end;

function DropdownIndexToAction(AIndex: Integer): TUserAssocAction;
begin
  case AIndex of
    0: Result := uaaView;
    1: Result := uaaEdit;
    2: Result := uaaShell;
    3: Result := uaaCommand;
  else
    Result := uaaView;
  end;
end;

constructor TUserAssociationsDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TUserAssocKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TUserAssocCanStart;
  const AOnPrepareUi: TUserAssocPrepareUi; const AOnUnfocusCmd: TUserAssocUnfocusCmd);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnUnfocusCmd := AOnUnfocusCmd;
end;

procedure TUserAssociationsDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TUserAssociationsDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TUserAssociationsDialogController.SaveAndReload;
begin
  SaveUserAssociations(DefaultUserAssociationsFilePath, GlobalUserAssociations);
end;

procedure TUserAssociationsDialogController.OpenList;
var
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  SetLength(FRules, GlobalUserAssociations.Count);
  for I := 0 to High(FRules) do
    FRules[I] := GlobalUserAssociations.GetRule(I);
  SetLength(Items, Length(FRules));
  for I := 0 to High(FRules) do
    Items[I] := UserAssocRuleDisplayLabel(FRules[I]);

  SetKind(hdkAssociations);
  FDialog.Open(BuildAssociationsDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TUserAssociationsDialogController.BeginAdd;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() and
     not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  if Assigned(FOnUnfocusCmd) then
    FOnUnfocusCmd();
  FEditExtension := '';
  SetKind(hdkAssociationEdit);
  FDialog.Open(BuildAssociationEditDialog('', 0, ''), FOnCommand);
  Notify;
end;

procedure TUserAssociationsDialogController.BeginEdit(AIndex: Integer);
var
  Rule: TUserAssocRule;
begin
  if (AIndex < 0) or (AIndex > High(FRules)) then
    Exit;
  Rule := FRules[AIndex];
  FEditExtension := Rule.Extension;
  SetKind(hdkAssociationEdit);
  FDialog.Open(BuildAssociationEditDialog(Rule.Extension,
    ActionToDropdownIndex(Rule.Action), Rule.Command), FOnCommand);
  Notify;
end;

procedure TUserAssociationsDialogController.BeginDelete(AIndex: Integer);
var
  Msg: string;
begin
  if (AIndex < 0) or (AIndex > High(FRules)) then
    Exit;
  FPendingExtension := FRules[AIndex].Extension;
  Msg := T('ui.associations.confirmDelete', 'Delete association for "%s"?', [FRules[AIndex].Extension]);
  SetKind(hdkAssociationConfirm);
  FDialog.Open(BuildConfirmDialog(T('ui.associations.dialogTitle', 'File Associations'), Msg), FOnCommand);
  Notify;
end;

function TUserAssociationsDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if AKey = vkDelete then
  begin
    Idx := FDialog.GetListSelectedIndex('associations');
    BeginDelete(Idx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkInsert then
  begin
    BeginAdd;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkF2 then
  begin
    Idx := FDialog.GetListSelectedIndex('associations');
    BeginEdit(Idx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TUserAssociationsDialogController.DispatchListCommand(
  const AControlId: string);
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('associations');
  if DialogCmdIs(AControlId, 'add') then
  begin
    BeginAdd;
    Exit;
  end;
  if DialogCmdIs(AControlId, 'cancel') then
  begin
    FDialog.Close;
    SetLength(FRules, 0);
    Exit;
  end;
  // Enter on the list row, or the "Edit" button.
  if (Idx >= 0) and (Idx <= High(FRules)) then
    BeginEdit(Idx)
  else
  begin
    FDialog.Close;
    SetLength(FRules, 0);
  end;
end;

procedure TUserAssociationsDialogController.DispatchEditCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  ExtVal, CmdVal: string;
  ActionIdx: Integer;
  Rule: TUserAssocRule;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  ExtVal := Trim(FDialog.GetInputValue('extension'));
  ActionIdx := FDialog.GetListSelectedIndex('action');
  CmdVal := FDialog.GetInputValue('command');
  FDialog.Close;
  if Accepted and (ExtVal <> '') then
  begin
    // Renaming the extension while editing: drop the old row first so
    // the upsert below does not leave a stale duplicate behind.
    if (FEditExtension <> '') and
       not SameText(NormalizeAssocExtension(ExtVal), FEditExtension) then
      GlobalUserAssociations.DeleteRule(
        GlobalUserAssociations.IndexOfExtension(FEditExtension));
    Rule.Extension := ExtVal;
    Rule.Action := DropdownIndexToAction(ActionIdx);
    Rule.Command := CmdVal;
    GlobalUserAssociations.SetRuleForExtension(Rule);
    SaveAndReload;
  end;
  OpenList;
end;

procedure TUserAssociationsDialogController.DispatchConfirmCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  FDialog.Close;
  if Accepted then
  begin
    GlobalUserAssociations.DeleteRule(
      GlobalUserAssociations.IndexOfExtension(FPendingExtension));
    SaveAndReload;
  end;
  OpenList;
end;

function TUserAssociationsDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkAssociations: DispatchListCommand(AControlId);
    hdkAssociationEdit: DispatchEditCommand(AControlId);
    hdkAssociationConfirm: DispatchConfirmCommand(AControlId);
  else
    { not a File-associations dialog }
  end;
end;

end.
