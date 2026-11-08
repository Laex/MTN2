unit uDualPanelWorkspaceLibrary;

{ Workspaces list / save / rename / delete / restore dialogs. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uWorkspaceLibrary, uWorkspaceVfs,
  uStrings;

type
  TWorkspaceLibKindSetter = reference to procedure(AKind: THostDialogKind);
  TWorkspaceLibCanStart = reference to function: Boolean;
  TWorkspaceLibPrepareUi = reference to procedure;
  TWorkspaceLibNavigate = reference to procedure(const AUri: string);
  TWorkspaceLibUnfocusCmd = reference to procedure;
  TWorkspaceLibEmptySave = reference to procedure;

  TPickKind = (pkAdd, pkReplace, pkNew, pkSaved);

  TWorkspaceLibraryDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TWorkspaceLibKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TWorkspaceLibCanStart;
    FOnPrepareUi: TWorkspaceLibPrepareUi;
    FOnNavigate: TWorkspaceLibNavigate;
    FOnUnfocusCmd: TWorkspaceLibUnfocusCmd;
    FOnEmptySave: TWorkspaceLibEmptySave;
    FEntries: TArray<TWorkspaceSnapshot>;
    FRenameId: string;
    FPendingId: string;
    FConfirmDelete: Boolean;
    // Found items waiting for the choice of the set that takes them.
    FPickMode: Boolean;
    FPickTargets: TArray<TWorkspaceLinkNode>;
    FPickKinds: TArray<TPickKind>;
    FPickIds: TArray<string>;
    FOnFindAdded: TProc;
    procedure OpenPick;
    procedure DispatchPickCommand(const AControlId: string);
    procedure DoPick(AIndex: Integer);
    procedure BeginPickNew;
    procedure FinishPick;
    procedure CancelPick;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure DoRestore(const AId: string);
    procedure BeginDelete(AIndex: Integer);
    procedure BeginDirtyRestore(const AId: string);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TWorkspaceLibKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TWorkspaceLibCanStart;
      const AOnPrepareUi: TWorkspaceLibPrepareUi;
      const AOnNavigate: TWorkspaceLibNavigate;
      const AOnUnfocusCmd: TWorkspaceLibUnfocusCmd;
      const AOnEmptySave: TWorkspaceLibEmptySave);
    procedure OpenList;
    procedure RefreshList;
    /// <summary>Puts the targets into a workspace set: straight into the live
    /// one when nothing is saved or live yet, otherwise after asking which set
    /// (add to the live one, replace it, a new one or a saved one).</summary>
    procedure BeginFindToWorkspace(const ATargets: TArray<TWorkspaceLinkNode>);
    /// <summary>Called once the targets are in a set.</summary>
    property OnFindAdded: TProc read FOnFindAdded write FOnFindAdded;
    procedure BeginSave;
    procedure BeginRename(AIndex: Integer);
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchLibraryCommand(const AControlId: string);
    procedure DispatchSaveCommand(const AControlId: string);
    procedure DispatchRenameCommand(const AControlId: string);
    procedure DispatchConfirmCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

constructor TWorkspaceLibraryDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TWorkspaceLibKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TWorkspaceLibCanStart;
  const AOnPrepareUi: TWorkspaceLibPrepareUi;
  const AOnNavigate: TWorkspaceLibNavigate;
  const AOnUnfocusCmd: TWorkspaceLibUnfocusCmd;
  const AOnEmptySave: TWorkspaceLibEmptySave);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnNavigate := AOnNavigate;
  FOnUnfocusCmd := AOnUnfocusCmd;
  FOnEmptySave := AOnEmptySave;
end;

procedure TWorkspaceLibraryDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TWorkspaceLibraryDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TWorkspaceLibraryDialogController.OpenList;
var
  Entries: TArray<TWorkspaceSnapshot>;
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  CancelPick;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  Entries := WorkspaceLibraryGet;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := WorkspaceSnapshotDisplayLabel(Entries[I]);

  SetKind(hdkWorkspaceLibrary);
  FDialog.Open(BuildWorkspaceLibraryDialog(Items, 0, WorkspaceLiveCaption),
    FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.CancelPick;
begin
  FPickMode := False;
  SetLength(FPickTargets, 0);
  SetLength(FPickKinds, 0);
  SetLength(FPickIds, 0);
end;

procedure TWorkspaceLibraryDialogController.FinishPick;
begin
  CancelPick;
  SetLength(FEntries, 0);
  if Assigned(FOnFindAdded) then
    FOnFindAdded();
end;

procedure TWorkspaceLibraryDialogController.BeginFindToWorkspace(
  const ATargets: TArray<TWorkspaceLinkNode>);
begin
  if Length(ATargets) = 0 then
    Exit;
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  CancelPick;
  FPickTargets := ATargets;
  if not WorkspaceLiveHasLinks and (Length(WorkspaceLibraryGet) = 0) then
  begin
    WorkspaceAddTargets(FPickTargets);
    FinishPick;
    Exit;
  end;
  OpenPick;
end;

procedure TWorkspaceLibraryDialogController.OpenPick;
var
  Entries: TArray<TWorkspaceSnapshot>;
  Items: TArray<string>;
  Targets: TArray<TWorkspaceLinkNode>;
  I: Integer;

  procedure AddRow(AKind: TPickKind; const AId, ALabel: string);
  begin
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := ALabel;
    SetLength(FPickKinds, Length(Items));
    FPickKinds[High(Items)] := AKind;
    SetLength(FPickIds, Length(Items));
    FPickIds[High(Items)] := AId;
  end;

begin
  Targets := FPickTargets;
  CancelPick;
  FPickTargets := Targets;
  Entries := WorkspaceLibraryGet;
  AddRow(pkAdd, '', T('ui.workspace.pickAdd', 'Add to the current set') +
    Format('  (%d)', [WorkspaceLinkCount]));
  if WorkspaceLiveHasLinks then
    AddRow(pkReplace, '', T('ui.workspace.pickReplace', 'Replace the current set'));
  AddRow(pkNew, '', T('ui.workspace.pickNew', 'New set...'));
  for I := 0 to High(Entries) do
    AddRow(pkSaved, Entries[I].Id, T('ui.workspace.pickSaved',
      'Add to the saved set: %s', [WorkspaceSnapshotDisplayLabel(Entries[I])]));
  FPickMode := True;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  SetKind(hdkWorkspaceLibrary);
  FDialog.Open(BuildWorkspaceLibraryDialog(Items, 0, '',
    T('ui.workspace.pickTitle', 'Found items to the workspace')), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.DispatchPickCommand(
  const AControlId: string);
var
  Idx, I: Integer;
  Accepted: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('workspaces');
  Accepted := DialogCmdIsListAccept(AControlId, 'workspaces');
  // The Save button of the list dialog starts a new set here.
  if DialogCmdIs(AControlId, 'save') then
    for I := 0 to High(FPickKinds) do
      if FPickKinds[I] = pkNew then
      begin
        Idx := I;
        Accepted := True;
      end;
  FDialog.Close;
  if Accepted and (Idx >= 0) and (Idx <= High(FPickKinds)) then
    DoPick(Idx)
  else
    CancelPick;
end;

procedure TWorkspaceLibraryDialogController.DoPick(AIndex: Integer);
begin
  case FPickKinds[AIndex] of
    pkAdd:
      begin
        WorkspaceAddTargets(FPickTargets);
        FinishPick;
      end;
    pkReplace:
      begin
        WorkspaceLibraryReplaceLive(FPickTargets);
        FinishPick;
      end;
    pkSaved:
      begin
        WorkspaceLibraryAddToSaved(FPickIds[AIndex], FPickTargets);
        FinishPick;
      end;
    pkNew:
      BeginPickNew;
  end;
end;

procedure TWorkspaceLibraryDialogController.BeginPickNew;
begin
  SetKind(hdkWorkspaceSave);
  FDialog.Open(BuildInputDialog(T('ui.workspace.newSetTitle', 'New workspace set'),
    T('ui.workspace.namePrompt', 'Name:'),
    T('ui.workspace.newSetName', 'Found items')), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.RefreshList;
var
  Entries: TArray<TWorkspaceSnapshot>;
  Items: TArray<string>;
  I, Sel: Integer;
  SelId: string;
begin
  if not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  Sel := FDialog.GetListSelectedIndex('workspaces');
  SelId := '';
  if (Sel >= 0) and (Sel <= High(FEntries)) then
    SelId := FEntries[Sel].Id;
  Entries := WorkspaceLibraryGet;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := WorkspaceSnapshotDisplayLabel(Entries[I]);
  if SelId <> '' then
    for I := 0 to High(Entries) do
      if SameText(Entries[I].Id, SelId) then
      begin
        Sel := I;
        Break;
      end;
  FDialog.Open(BuildWorkspaceLibraryDialog(Items, Sel, WorkspaceLiveCaption),
    FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.BeginSave;
var
  Suggested: string;
begin
  CancelPick;
  if not WorkspaceLiveHasLinks then
  begin
    if Assigned(FOnEmptySave) then
      FOnEmptySave();
    Exit;
  end;
  if (WorkspaceLiveId <> '') and (WorkspaceLiveName <> '') then
  begin
    if WorkspaceLibrarySaveCurrent(WorkspaceLiveName) then
    begin
      if Assigned(FDialog) and FDialog.Visible then
        RefreshList
      else
        OpenList;
    end;
    Exit;
  end;
  if Assigned(FOnCanStart) and not FOnCanStart() and
     not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  if Assigned(FOnUnfocusCmd) then
    FOnUnfocusCmd();
  Suggested := WorkspaceLiveName;
  if Suggested = '' then
    Suggested := 'Workspace';
  SetKind(hdkWorkspaceSave);
  FDialog.Open(BuildInputDialog(T('ui.workspace.saveTitle', 'Save workspace'),
    T('ui.workspace.namePrompt', 'Name:'), Suggested), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.BeginRename(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FRenameId := FEntries[AIndex].Id;
  SetKind(hdkWorkspaceRename);
  FDialog.Open(BuildInputDialog(T('ui.workspace.renameTitle', 'Rename workspace'),
    T('ui.workspace.namePrompt', 'Name:'), FEntries[AIndex].Name), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.BeginDelete(AIndex: Integer);
var
  Msg: string;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FPendingId := FEntries[AIndex].Id;
  FConfirmDelete := True;
  Msg := T('ui.workspace.confirmDelete', 'Delete saved workspace "%s"?', [FEntries[AIndex].Name]);
  SetKind(hdkWorkspaceConfirm);
  FDialog.Open(BuildConfirmDialog(T('ui.workspace.dialogTitle', 'Workspaces'), Msg), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.BeginDirtyRestore(const AId: string);
begin
  FPendingId := AId;
  FConfirmDelete := False;
  SetKind(hdkWorkspaceConfirm);
  FDialog.Open(BuildConfirmDialog(T('ui.workspace.dialogTitle', 'Workspaces'),
    T('ui.workspace.confirmDiscard', 'Discard unsaved workspace changes?')), FOnCommand);
  Notify;
end;

procedure TWorkspaceLibraryDialogController.DoRestore(const AId: string);
begin
  if not WorkspaceLibraryRestore(AId) then
    Exit;
  if Assigned(FOnNavigate) then
    FOnNavigate('ws:///');
end;

function TWorkspaceLibraryDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if FPickMode then
    Exit;
  if AKey = vkDelete then
  begin
    Idx := FDialog.GetListSelectedIndex('workspaces');
    BeginDelete(Idx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkInsert then
  begin
    BeginSave;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkF2 then
  begin
    Idx := FDialog.GetListSelectedIndex('workspaces');
    BeginRename(Idx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TWorkspaceLibraryDialogController.DispatchLibraryCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  if FPickMode then
  begin
    DispatchPickCommand(AControlId);
    Exit;
  end;
  Idx := FDialog.GetListSelectedIndex('workspaces');
  if DialogCmdIs(AControlId, 'save') then
  begin
    BeginSave;
    Exit;
  end;
  Accepted := DialogCmdIsListAccept(AControlId, 'workspaces');
  FDialog.Close;
  if Accepted and (Idx >= 0) and (Idx <= High(FEntries)) then
  begin
    if WorkspaceLiveIsDirty then
      BeginDirtyRestore(FEntries[Idx].Id)
    else
      DoRestore(FEntries[Idx].Id);
  end;
  SetLength(FEntries, 0);
end;

procedure TWorkspaceLibraryDialogController.DispatchSaveCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  if FPickMode then
  begin
    if Accepted and (WorkspaceLibraryAddToNew(NameVal, FPickTargets) <> '') then
      FinishPick
    else
      OpenPick;
    Exit;
  end;
  if Accepted then
    WorkspaceLibrarySaveCurrent(NameVal);
  OpenList;
end;

procedure TWorkspaceLibraryDialogController.DispatchRenameCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  if Accepted then
    WorkspaceLibraryRename(FRenameId, NameVal);
  OpenList;
end;

procedure TWorkspaceLibraryDialogController.DispatchConfirmCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  FDialog.Close;
  if FConfirmDelete then
  begin
    if Accepted then
      WorkspaceLibraryDelete(FPendingId);
    OpenList;
  end
  else if Accepted then
    DoRestore(FPendingId)
  else
    OpenList;
end;

function TWorkspaceLibraryDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkWorkspaceLibrary: DispatchLibraryCommand(AControlId);
    hdkWorkspaceSave: DispatchSaveCommand(AControlId);
    hdkWorkspaceRename: DispatchRenameCommand(AControlId);
    hdkWorkspaceConfirm: DispatchConfirmCommand(AControlId);
  else
    { not a workspace-library dialog }
  end;
end;

end.
