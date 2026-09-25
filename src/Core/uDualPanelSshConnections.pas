unit uDualPanelSshConnections;

{ SSH/SFTP saved-connections dialog: list + add/edit/delete, and the two
  entry points both Часть 1 (SSH console) and Часть 2 (sftp:// VFS panel)
  share -- "Shell" opens a ssh:<id> terminal profile (uShellProfiles.pas),
  "Browse" navigates the active panel to sftp://<authority>/. Mirrors
  uDualPanelWorkspaceLibrary.pas's shape (list dialog + a plain-fields
  editor instead of Workspaces' single-field rename/save). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uSshConnections, uVfsTypes, uStrings;

type
  TSshConnKindSetter = reference to procedure(AKind: THostDialogKind);
  TSshConnCanStart = reference to function: Boolean;
  TSshConnPrepareUi = reference to procedure;
  TSshConnNavigate = reference to procedure(const AUri: string);
  TSshConnOpenTerminal = reference to procedure(const AConnectionId: string);
  TSshConnUnfocusCmd = reference to procedure;

  TSshConnectionsDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TSshConnKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TSshConnCanStart;
    FOnPrepareUi: TSshConnPrepareUi;
    FOnNavigate: TSshConnNavigate;
    FOnOpenTerminal: TSshConnOpenTerminal;
    FOnUnfocusCmd: TSshConnUnfocusCmd;
    FEntries: TArray<TSshConnection>;
    FEditId: string; // '' while adding a new connection
    FPendingId: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure BeginDelete(AIndex: Integer);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TSshConnKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TSshConnCanStart; const AOnPrepareUi: TSshConnPrepareUi;
      const AOnNavigate: TSshConnNavigate; const AOnOpenTerminal: TSshConnOpenTerminal;
      const AOnUnfocusCmd: TSshConnUnfocusCmd);
    procedure OpenList;
    procedure RefreshList;
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

constructor TSshConnectionsDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TSshConnKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TSshConnCanStart;
  const AOnPrepareUi: TSshConnPrepareUi; const AOnNavigate: TSshConnNavigate;
  const AOnOpenTerminal: TSshConnOpenTerminal; const AOnUnfocusCmd: TSshConnUnfocusCmd);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnNavigate := AOnNavigate;
  FOnOpenTerminal := AOnOpenTerminal;
  FOnUnfocusCmd := AOnUnfocusCmd;
end;

procedure TSshConnectionsDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TSshConnectionsDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TSshConnectionsDialogController.OpenList;
var
  Entries: TArray<TSshConnection>;
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  Entries := SshConnectionsGet;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := SshConnectionDisplayLabel(Entries[I]);

  SetKind(hdkSshConnections);
  FDialog.Open(BuildSshConnectionsDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TSshConnectionsDialogController.RefreshList;
var
  Entries: TArray<TSshConnection>;
  Items: TArray<string>;
  I, Sel: Integer;
  SelId: string;
begin
  if not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  Sel := FDialog.GetListSelectedIndex('connections');
  SelId := '';
  if (Sel >= 0) and (Sel <= High(FEntries)) then
    SelId := FEntries[Sel].Id;
  Entries := SshConnectionsGet;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := SshConnectionDisplayLabel(Entries[I]);
  if SelId <> '' then
    for I := 0 to High(Entries) do
      if SameText(Entries[I].Id, SelId) then
      begin
        Sel := I;
        Break;
      end;
  SetKind(hdkSshConnections);
  FDialog.Open(BuildSshConnectionsDialog(Items, Sel), FOnCommand);
  Notify;
end;

procedure TSshConnectionsDialogController.BeginAdd;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() and
     not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  if Assigned(FOnUnfocusCmd) then
    FOnUnfocusCmd();
  FEditId := '';
  SetKind(hdkSshConnectionEdit);
  FDialog.Open(BuildSshConnectionEditDialog('', '', 0, '', ''), FOnCommand);
  Notify;
end;

procedure TSshConnectionsDialogController.BeginEdit(AIndex: Integer);
var
  Conn: TSshConnection;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  Conn := FEntries[AIndex];
  FEditId := Conn.Id;
  SetKind(hdkSshConnectionEdit);
  FDialog.Open(BuildSshConnectionEditDialog(Conn.Name, Conn.Host, Conn.Port,
    Conn.User, Conn.IdentityFile), FOnCommand);
  Notify;
end;

procedure TSshConnectionsDialogController.BeginDelete(AIndex: Integer);
var
  Msg: string;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FPendingId := FEntries[AIndex].Id;
  Msg := T('ui.ssh.confirmDelete', 'Delete saved connection "%s"?', [FEntries[AIndex].Name]);
  SetKind(hdkSshConnectionConfirm);
  FDialog.Open(BuildConfirmDialog(T('ui.ssh.dialogTitle', 'SSH/SFTP Connections'), Msg), FOnCommand);
  Notify;
end;

function TSshConnectionsDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if AKey = vkDelete then
  begin
    Idx := FDialog.GetListSelectedIndex('connections');
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
    Idx := FDialog.GetListSelectedIndex('connections');
    BeginEdit(Idx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TSshConnectionsDialogController.DispatchListCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Idx := FDialog.GetListSelectedIndex('connections');
  if DialogCmdIs(AControlId, 'browse') then
  begin
    FDialog.Close;
    if (Idx >= 0) and (Idx <= High(FEntries)) and Assigned(FOnNavigate) then
      FOnNavigate(MakeSftpUri(SshConnectionAuthority(FEntries[Idx]), '/'));
    SetLength(FEntries, 0);
    Exit;
  end;
  Accepted := DialogCmdIsListAccept(AControlId, 'connections');
  FDialog.Close;
  if Accepted and (Idx >= 0) and (Idx <= High(FEntries)) and
     Assigned(FOnOpenTerminal) then
    FOnOpenTerminal(FEntries[Idx].Id);
  SetLength(FEntries, 0);
end;

procedure TSshConnectionsDialogController.DispatchEditCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  Conn: TSshConnection;
  NameVal, HostVal, UserVal, IdentityVal, PortStr: string;
  Port: Integer;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  HostVal := FDialog.GetInputValue('host');
  PortStr := FDialog.GetInputValue('port');
  UserVal := FDialog.GetInputValue('user');
  IdentityVal := FDialog.GetInputValue('identityfile');
  FDialog.Close;
  if Accepted and (Trim(HostVal) <> '') then
  begin
    if not TryStrToInt(Trim(PortStr), Port) then
      Port := 0;
    if FEditId = '' then
      SshConnectionAdd(NameVal, HostVal, Port, UserVal, IdentityVal)
    else if SshConnectionsFindById(FEditId, Conn) then
    begin
      Conn.Name := Trim(NameVal);
      if Conn.Name = '' then
        Conn.Name := Trim(HostVal);
      Conn.Host := Trim(HostVal);
      Conn.Port := Port;
      Conn.User := Trim(UserVal);
      Conn.IdentityFile := Trim(IdentityVal);
      SshConnectionUpdate(Conn);
    end;
  end;
  OpenList;
end;

procedure TSshConnectionsDialogController.DispatchConfirmCommand(
  const AControlId: string);
var
  Accepted: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  FDialog.Close;
  if Accepted then
    SshConnectionDelete(FPendingId);
  OpenList;
end;

function TSshConnectionsDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkSshConnections: DispatchListCommand(AControlId);
    hdkSshConnectionEdit: DispatchEditCommand(AControlId);
    hdkSshConnectionConfirm: DispatchConfirmCommand(AControlId);
  else
    { not an SSH-connections dialog }
  end;
end;

end.
