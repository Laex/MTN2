unit uDualPanelFolderHotlist;

{ Directory hotlist list / add / rename dialogs (hdkFolderHotlist,
  hdkFolderHotlistAdd, hdkFolderHotlistRename). Extracted from
  TDualPanelWindow so the host keeps only thin Open/Begin/Navigate forwards. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uFolderHotlist, uVfsTypes,
  uPanelUriLabels, uStrings;

type
  TFolderHotlistKindSetter = reference to procedure(AKind: THostDialogKind);
  TFolderHotlistCanStart = reference to function: Boolean;
  TFolderHotlistPrepareUi = reference to procedure;
  TFolderHotlistGetActiveUri = reference to function(out AUri: string): Boolean;
  TFolderHotlistNavigate = reference to procedure(const AUri: string);
  TFolderHotlistUnfocusCmd = reference to procedure;

  TFolderHotlistDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFolderHotlistKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TFolderHotlistCanStart;
    FOnPrepareUi: TFolderHotlistPrepareUi;
    FOnGetActiveUri: TFolderHotlistGetActiveUri;
    FOnNavigate: TFolderHotlistNavigate;
    FOnUnfocusCmd: TFolderHotlistUnfocusCmd;
    FEntries: TArray<TFolderHotlistEntry>;
    FRenameUri: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TFolderHotlistKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TFolderHotlistCanStart;
      const AOnPrepareUi: TFolderHotlistPrepareUi;
      const AOnGetActiveUri: TFolderHotlistGetActiveUri;
      const AOnNavigate: TFolderHotlistNavigate;
      const AOnUnfocusCmd: TFolderHotlistUnfocusCmd);
    procedure OpenList;
    procedure RefreshList;
    procedure BeginAdd;
    procedure BeginRename(AIndex: Integer);
    procedure NavigateToHotkey(ADigit: Integer);
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function TryHandleHotkeyJump(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function ShouldNavigateOnAccept(AAccepted: Boolean; AIdx: Integer): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    procedure DispatchAddCommand(const AControlId: string);
    procedure DispatchRenameCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

constructor TFolderHotlistDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFolderHotlistKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TFolderHotlistCanStart;
  const AOnPrepareUi: TFolderHotlistPrepareUi;
  const AOnGetActiveUri: TFolderHotlistGetActiveUri;
  const AOnNavigate: TFolderHotlistNavigate;
  const AOnUnfocusCmd: TFolderHotlistUnfocusCmd);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnGetActiveUri := AOnGetActiveUri;
  FOnNavigate := AOnNavigate;
  FOnUnfocusCmd := AOnUnfocusCmd;
end;

procedure TFolderHotlistDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TFolderHotlistDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TFolderHotlistDialogController.OpenList;
var
  Entries: TArray<TFolderHotlistEntry>;
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  Entries := FolderHotlistGetEntries;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := FolderHotlistDisplayLabel(Entries[I]);

  SetKind(hdkFolderHotlist);
  FDialog.Open(BuildFolderHotlistDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.RefreshList;
var
  Entries: TArray<TFolderHotlistEntry>;
  Items: TArray<string>;
  I, Sel: Integer;
  SelUri: string;
begin
  if not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  // Re-sorting (FolderHotlistGetEntries orders by hotkey) can move the
  // entry the cursor was on to a different row — follow it by URI rather
  // than keeping the same numeric row, which would land on whatever
  // unrelated entry happens to sort into that slot now.
  Sel := FDialog.GetListSelectedIndex('hotlist');
  SelUri := '';
  if (Sel >= 0) and (Sel <= High(FEntries)) then
    SelUri := FEntries[Sel].URI;
  Entries := FolderHotlistGetEntries;
  FEntries := Entries;
  SetLength(Items, Length(Entries));
  for I := 0 to High(Entries) do
    Items[I] := FolderHotlistDisplayLabel(Entries[I]);
  if SelUri <> '' then
    for I := 0 to High(Entries) do
      if SameVfsUri(Entries[I].URI, SelUri) then
      begin
        Sel := I;
        Break;
      end;
  FDialog.Open(BuildFolderHotlistDialog(Items, Sel), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.BeginAdd;
var
  CurURI, Suggested: string;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  CurURI := '';
  if not Assigned(FOnGetActiveUri) or not FOnGetActiveUri(CurURI) then
    Exit;
  Suggested := VfsUriTitle(CurURI);
  if Assigned(FOnUnfocusCmd) then
    FOnUnfocusCmd();
  SetKind(hdkFolderHotlistAdd);
  FDialog.Open(BuildInputDialog(T('ui.hotlist.addTitle', 'Add to hotlist'),
    T('ui.hotlist.namePrompt', 'Name:'), Suggested), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.BeginRename(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FRenameUri := FEntries[AIndex].URI;
  SetKind(hdkFolderHotlistRename);
  FDialog.Open(BuildInputDialog(T('ui.hotlist.renameTitle', 'Rename hotlist entry'),
    T('ui.hotlist.namePrompt', 'Name:'), FEntries[AIndex].Name), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.NavigateToHotkey(ADigit: Integer);
var
  I: Integer;
  Entries: TArray<TFolderHotlistEntry>;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  // Search the entries themselves for the matching HotKey rather than
  // combining FolderHotlistFindByHotKey's raw-storage index with this
  // (hotkey-sorted) array — those two are different orderings.
  Entries := FolderHotlistGetEntries;
  for I := 0 to High(Entries) do
    if Entries[I].HotKey = ADigit then
    begin
      if (Entries[I].URI <> '') and Assigned(FOnNavigate) then
        FOnNavigate(Entries[I].URI);
      Exit;
    end;
end;

function TFolderHotlistDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  HotIdx: Integer;
  HotKeyDigit: Integer;
begin
  Result := False;
  if AKey = vkDelete then
  begin
    HotIdx := FDialog.GetListSelectedIndex('hotlist');
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
    begin
      FolderHotlistRemoveByUri(FEntries[HotIdx].URI);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkF2 then
  begin
    HotIdx := FDialog.GetListSelectedIndex('hotlist');
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
      BeginRename(HotIdx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  // Ctrl+1..Ctrl+9,Ctrl+0: toggle-assign that hotkey to the selected entry.
  // Pressing the digit already owning it clears it; pressing one owned by
  // another entry steals it (FolderHotlistSetHotKey enforces uniqueness).
  // Checked on AKey, not AKeyChar — Ctrl+digit has no ASCII control-code
  // to reverse-map, so AKeyChar is #0 for it (unlike Ctrl+letter).
  if (ssCtrl in AShift) and (FolderHotlistKeyFromVKey(AKey) <> 0) then
  begin
    HotIdx := FDialog.GetListSelectedIndex('hotlist');
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
    begin
      HotKeyDigit := FolderHotlistKeyFromVKey(AKey);
      if FEntries[HotIdx].HotKey = HotKeyDigit then
        FolderHotlistSetHotKeyByUri(FEntries[HotIdx].URI, 0) // already assigned here — toggle off
      else
        FolderHotlistSetHotKeyByUri(FEntries[HotIdx].URI, HotKeyDigit);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

function TFolderHotlistDialogController.TryHandleHotkeyJump(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  HotKeyDigit: Integer;
begin
  Result := False;
  // Ctrl+1..Ctrl+9,Ctrl+0: jump straight to a directory hotlist entry with
  // that hotkey assigned (Ctrl+D dialog). No-op if nothing is bound to it.
  // Ctrl+Alt+1..6 is a separate namespace (column modes, see
  // uColumnModeMenuController), so Alt must be off here. Checked on AKey,
  // not AKeyChar — Ctrl+digit has no ASCII control-code to reverse-map, so
  // AKeyChar is #0 for it (unlike Ctrl+letter).
  if not ((ssCtrl in AShift) and not (ssShift in AShift) and not (ssAlt in AShift)) then
    Exit;
  HotKeyDigit := FolderHotlistKeyFromVKey(AKey);
  if HotKeyDigit = 0 then
    Exit;
  NavigateToHotkey(HotKeyDigit);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function TFolderHotlistDialogController.ShouldNavigateOnAccept(
  AAccepted: Boolean; AIdx: Integer): Boolean;
begin
  Result := AAccepted and (AIdx >= 0) and (AIdx <= High(FEntries)) and
    (FEntries[AIdx].URI <> '') and Assigned(FOnNavigate);
end;

procedure TFolderHotlistDialogController.DispatchListCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted: Boolean;
begin
  // Snapshot before Close.
  Idx := FDialog.GetListSelectedIndex('hotlist');
  Accepted := DialogCmdIsListAccept(AControlId, 'hotlist');
  FDialog.Close;
  if ShouldNavigateOnAccept(Accepted, Idx) then
    FOnNavigate(FEntries[Idx].URI);
  SetLength(FEntries, 0);
end;

procedure TFolderHotlistDialogController.DispatchAddCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal, ActiveUri: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  ActiveUri := '';
  if Accepted and Assigned(FOnGetActiveUri) and FOnGetActiveUri(ActiveUri) then
    FolderHotlistAdd(NameVal, ActiveUri);
end;

procedure TFolderHotlistDialogController.DispatchRenameCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  if Accepted then
    FolderHotlistRenameByUri(FRenameUri, NameVal);
  // Return to the list dialog so Del/F2 can keep operating on it.
  OpenList;
end;

function TFolderHotlistDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkFolderHotlist: DispatchListCommand(AControlId);
    hdkFolderHotlistAdd: DispatchAddCommand(AControlId);
    hdkFolderHotlistRename: DispatchRenameCommand(AControlId);
  else
    { not a folder-hotlist dialog }
  end;
end;

end.
