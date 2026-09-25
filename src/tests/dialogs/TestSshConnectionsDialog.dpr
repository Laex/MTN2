program TestSshConnectionsDialog;

{$APPTYPE CONSOLE}
{$R '..\..\MTN2.dres'}

{ Characterization tests for TSshConnectionsDialogController (Ctrl+O-adjacent
  SSH/SFTP saved-connections dialog) -- previously untested. The data layer
  (uSshConnections.pas) already has TestSshConnections.dpr; this covers the
  dialog controller built on top of it. Uses SshConnectionsUsePath to point
  the store at a throwaway temp file, so this run never touches the user's
  real sshconnections.json. }

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils,
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas',
  uDialogResources in '..\..\Core\uDialogResources.pas',
  uDialogHost in '..\..\Core\uDialogHost.pas',
  uDialogRenderer in '..\..\Core\uDialogRenderer.pas',
  uInputLine in '..\..\Core\uInputLine.pas',
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uThemeDrawing in '..\..\Core\uThemeDrawing.pas',
  uFunctionBar in '..\..\Core\uFunctionBar.pas',
  uColorCoding in '..\..\Core\uColorCoding.pas',
  uColorCodingEditHelpers in '..\..\Core\uColorCodingEditHelpers.pas',
  uFileFind in '..\..\Core\uFileFind.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uSshConnections in '..\..\Core\uSshConnections.pas',
  uDualPanelSshConnections in '..\..\Core\uDualPanelSshConnections.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

var
  GNavigateCalled, GOpenTerminalCalled, GUnfocusCalled: Boolean;
  GNavigatedUri, GOpenedTerminalId: string;
  GNotifyCount: Integer;
  GCanStartResult: Boolean;
  GLastKind: THostDialogKind;

function MakeController(ADialog: TDialogHost): TSshConnectionsDialogController;
begin
  GNavigateCalled := False;
  GOpenTerminalCalled := False;
  GUnfocusCalled := False;
  GNavigatedUri := '';
  GOpenedTerminalId := '';
  GNotifyCount := 0;
  GCanStartResult := True;
  GLastKind := hdkNone;
  Result := TSshConnectionsDialogController.Create(ADialog,
    procedure(const AControlId, AValuesJson: string)
    begin
    end,
    procedure(AKind: THostDialogKind)
    begin
      GLastKind := AKind;
    end,
    procedure
    begin
      Inc(GNotifyCount);
    end,
    function: Boolean
    begin
      Result := GCanStartResult;
    end,
    procedure
    begin
    end,
    procedure(const AUri: string)
    begin
      GNavigateCalled := True;
      GNavigatedUri := AUri;
    end,
    procedure(const AConnectionId: string)
    begin
      GOpenTerminalCalled := True;
      GOpenedTerminalId := AConnectionId;
    end,
    procedure
    begin
      GUnfocusCalled := True;
    end);
end;

procedure TestOpenListShellBrowseCancel;
var
  Dialog: TDialogHost;
  C: TSshConnectionsDialogController;
  Web, Db: TSshConnection;
begin
  Writeln('OpenList / Shell / Browse / Cancel');
  Web := SshConnectionAdd('Web', 'web.example.com', 2222, 'deploy', '');
  Db := SshConnectionAdd('DB', 'db.example.com', 0, 'admin', 'C:\keys\id');

  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      GCanStartResult := False;
      C.OpenList;
      Expect(not Dialog.Visible, 'OpenList declines when AOnCanStart returns False');

      GCanStartResult := True;
      C.OpenList;
      Expect(Dialog.Visible, 'OpenList opens once allowed to start');
      Expect(GNotifyCount = 1, 'OpenList notifies the host once');
      Expect(Dialog.GetListSelectedIndex('connections') = 0, 'opens with the first entry selected');

      // Move selection to the second entry (Db), then click "Browse".
      Dialog.SetListItems('connections', ['Web', 'DB'], 1);
      C.DispatchCommand(hdkSshConnections, 'browse');
      Expect(not Dialog.Visible, 'Browse closes the dialog');
      Expect(GNavigateCalled, 'Browse navigates');
      Expect(not GOpenTerminalCalled, 'Browse does not open a terminal');
      Expect(GNavigatedUri = MakeSftpUri(SshConnectionAuthority(Db), '/'),
        'Browse navigates to the sftp:// authority of the selected (not first) entry');

      GNavigateCalled := False;
      C.OpenList;
      Dialog.SetListItems('connections', ['Web', 'DB'], 0);
      C.DispatchCommand(hdkSshConnections, 'ok'); // "Shell" button = accept
      Expect(not Dialog.Visible, 'Shell closes the dialog');
      Expect(GOpenTerminalCalled, 'Shell (accept) opens a terminal');
      Expect(not GNavigateCalled, 'Shell does not navigate');
      Expect(GOpenedTerminalId = Web.Id, 'Shell opens the terminal for the selected entry');

      GOpenTerminalCalled := False;
      C.OpenList;
      Dialog.SetListItems('connections', ['Web', 'DB'], 1);
      C.DispatchCommand(hdkSshConnections, 'cancel');
      Expect(not Dialog.Visible, 'Cancel closes the dialog');
      Expect((not GNavigateCalled) and (not GOpenTerminalCalled),
        'Cancel neither navigates nor opens a terminal');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestHandleListInputShortcuts;
var
  Dialog: TDialogHost;
  C: TSshConnectionsDialogController;
  Conn: TSshConnection;
  Key: Word;
  KeyChar: Char;
begin
  Writeln('HandleListInput: Ins / F2 / Del shortcuts');
  Conn := SshConnectionAdd('Solo', 'solo.example.com', 0, 'root', '');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;

      Key := vkInsert;
      KeyChar := #0;
      Expect(C.HandleListInput(Key, [], KeyChar), 'Insert is consumed');
      Expect(GLastKind = hdkSshConnectionEdit, 'Insert opens the edit dialog');
      Expect(Dialog.GetInputValue('host') = '', 'Insert opens the edit dialog blank (adding, not editing)');
      Expect(GUnfocusCalled, 'Insert unfocuses the command line first');

      C.OpenList;
      Dialog.SetListItems('connections', ['Solo'], 0);
      GUnfocusCalled := False;
      Key := vkF2;
      KeyChar := #0;
      Expect(C.HandleListInput(Key, [], KeyChar), 'F2 is consumed');
      Expect(GLastKind = hdkSshConnectionEdit, 'F2 opens the edit dialog');
      Expect(Dialog.GetInputValue('host') = 'solo.example.com', 'F2 pre-fills the selected entry''s host');

      C.OpenList;
      Dialog.SetListItems('connections', ['Solo'], 0);
      Key := vkDelete;
      KeyChar := #0;
      Expect(C.HandleListInput(Key, [], KeyChar), 'Delete is consumed');
      Expect(GLastKind = hdkSshConnectionConfirm, 'Delete opens the confirm dialog');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestAddConnection;
var
  Dialog: TDialogHost;
  C: TSshConnectionsDialogController;
  All: TArray<TSshConnection>;
begin
  Writeln('Add a connection via the edit dialog');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.BeginAdd;
      Expect(GLastKind = hdkSshConnectionEdit, 'BeginAdd opens the edit dialog');
      Dialog.SetInputValue('name', 'New Box');
      Dialog.SetInputValue('host', '');
      C.DispatchCommand(hdkSshConnectionEdit, 'ok');
      Expect(Length(SshConnectionsGet) = 0, 'accepting with a blank host adds nothing');
      Expect(GLastKind = hdkSshConnections, 'DispatchEditCommand always reopens the list afterwards');

      C.BeginAdd;
      Dialog.SetInputValue('name', 'New Box');
      Dialog.SetInputValue('host', 'newbox.example.com');
      Dialog.SetInputValue('port', '2200');
      Dialog.SetInputValue('user', 'ubuntu');
      Dialog.SetInputValue('identityfile', 'C:\keys\newbox.pem');
      C.DispatchCommand(hdkSshConnectionEdit, 'ok');
      All := SshConnectionsGet;
      Expect(Length(All) = 1, 'accepting with a host adds exactly one connection');
      Expect(All[0].Name = 'New Box', 'added connection has the entered name');
      Expect(All[0].Host = 'newbox.example.com', 'added connection has the entered host');
      Expect(All[0].Port = 2200, 'added connection has the entered port');
      Expect(All[0].User = 'ubuntu', 'added connection has the entered user');
      Expect(All[0].IdentityFile = 'C:\keys\newbox.pem', 'added connection has the entered identity file');

      C.BeginAdd;
      Dialog.SetInputValue('host', 'should-not-be-added.example.com');
      C.DispatchCommand(hdkSshConnectionEdit, 'cancel');
      Expect(Length(SshConnectionsGet) = 1, 'Cancel on the edit dialog adds nothing');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestEditConnection;
var
  Dialog: TDialogHost;
  C: TSshConnectionsDialogController;
  Conn, Fetched: TSshConnection;
begin
  Writeln('Edit an existing connection');
  Conn := SshConnectionAdd('Edit Me', 'old-host.example.com', 22, 'olduser', '');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Dialog.SetListItems('connections', ['Edit Me'], 0);
      C.BeginEdit(0);
      Expect(Dialog.GetInputValue('host') = 'old-host.example.com', 'BeginEdit pre-fills the current host');

      Dialog.SetInputValue('host', 'new-host.example.com');
      Dialog.SetInputValue('user', 'newuser');
      C.DispatchCommand(hdkSshConnectionEdit, 'ok');

      Expect(SshConnectionsFindById(Conn.Id, Fetched), 'the connection still exists after editing');
      Expect(Fetched.Host = 'new-host.example.com', 'editing updates the host');
      Expect(Fetched.User = 'newuser', 'editing updates the user');
      Expect(Fetched.Name = 'Edit Me', 'editing preserves fields left untouched');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TestDeleteConnection;
var
  Dialog: TDialogHost;
  C: TSshConnectionsDialogController;
  Conn: TSshConnection;
  Fetched: TSshConnection;
  Key: Word;
  KeyChar: Char;
begin
  Writeln('Delete: confirm vs reject (via HandleListInput Del)');
  Conn := SshConnectionAdd('Doomed', 'doomed.example.com', 0, '', '');
  Dialog := TDialogHost.Create(nil);
  try
    C := MakeController(Dialog);
    try
      C.OpenList;
      Dialog.SetListItems('connections', ['Doomed'], 0);
      Key := vkDelete;
      KeyChar := #0;
      C.HandleListInput(Key, [], KeyChar);
      Expect(GLastKind = hdkSshConnectionConfirm, 'Delete opens the confirm dialog');

      C.DispatchCommand(hdkSshConnectionConfirm, 'cancel');
      Expect(SshConnectionsFindById(Conn.Id, Fetched), 'rejecting the confirm keeps the connection');

      C.OpenList;
      Dialog.SetListItems('connections', ['Doomed'], 0);
      Key := vkDelete;
      C.HandleListInput(Key, [], KeyChar);
      C.DispatchCommand(hdkSshConnectionConfirm, 'ok');
      Expect(not SshConnectionsFindById(Conn.Id, Fetched), 'accepting the confirm deletes the connection');
    finally
      C.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

var
  TempFile: string;

procedure ResetStore;
begin
  // SshConnectionsResetForTests only clears the in-memory list -- the temp
  // file on disk still holds whatever the previous test's SshConnectionAdd
  // calls persisted (SaveLocked writes on every mutation), so it must be
  // deleted too or the next test's EnsureLoaded would reload those stale rows.
  SshConnectionsResetForTests;
  if TFile.Exists(TempFile) then
    TFile.Delete(TempFile);
  SshConnectionsUsePath(TempFile);
end;

begin
  try
    TempFile := TPath.Combine(TPath.GetTempPath, 'mtn2_test_sshconnectionsdialog.json');
    ResetStore;
    try
      TestOpenListShellBrowseCancel;
      ResetStore;

      TestHandleListInputShortcuts;
      ResetStore;

      TestAddConnection;
      ResetStore;

      TestEditConnection;
      ResetStore;

      TestDeleteConnection;
    finally
      SshConnectionsResetForTests;
      if TFile.Exists(TempFile) then
        TFile.Delete(TempFile);
    end;
    Writeln('All SshConnectionsDialog tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
