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
    /// <summary>Per list row: index into FEntries, or -1 for a group header.</summary>
    FRowEntry: TArray<Integer>;
    /// <summary>Per list row: the group the row belongs to ('' = ungrouped).</summary>
    FRowGroup: TArray<string>;
    /// <summary>Names of the groups shown folded.</summary>
    FCollapsed: TStringList;
    /// <summary>The list as the dialog opened it (or as last saved); Cancel restores it.</summary>
    FSnapshot: TArray<TFolderHotlistEntry>;
    FInSession: Boolean;
    FRenameUri: string;
    /// <summary>True while the rename input edits the group, not the name.</summary>
    FEditGroup: Boolean;
    /// <summary>The group being renamed by the rename input; '' = an entry is.</summary>
    FRenameGroupOld: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure BuildRows(out AItems: TArray<string>);
    function RowEntry(ARow: Integer): Integer;
    procedure SetGroupFolded(const AGroup: string; AFolded: Boolean);
    /// <summary>Unfolds AGroup and folds every other one.</summary>
    procedure OpenOnly(const AGroup: string);
    procedure NavigateEntry(AEntryIdx: Integer);
    /// <summary>A plain character picks the entry or group whose name
    /// declares it as its key (&x), also from the other keyboard layout.</summary>
    function TryPressKey(AKeyChar: Char): Boolean;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TFolderHotlistKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TFolderHotlistCanStart;
      const AOnPrepareUi: TFolderHotlistPrepareUi;
      const AOnGetActiveUri: TFolderHotlistGetActiveUri;
      const AOnNavigate: TFolderHotlistNavigate;
      const AOnUnfocusCmd: TFolderHotlistUnfocusCmd);
    destructor Destroy; override;
    procedure OpenList;
    /// <summary>Shows the list again within the running edit session (after
    /// the rename / group input), keeping the snapshot taken by OpenList.</summary>
    procedure ReopenList;
    /// <summary>ASelectGroup names a group whose header takes the cursor.</summary>
    procedure RefreshList(const ASelectGroup: string = '');
    procedure BeginAdd;
    procedure BeginRename(AIndex: Integer);
    procedure BeginGroup(AIndex: Integer);
    procedure BeginRenameGroup(const AGroup: string);
    procedure NavigateToHotkey(ADigit: Integer);
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function TryHandleHotkeyJump(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    /// <summary>AIdx is a list row; group headers never navigate.</summary>
    function ShouldNavigateOnAccept(AAccepted: Boolean; AIdx: Integer): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    procedure DispatchAddCommand(const AControlId: string);
    procedure DispatchRenameCommand(const AControlId: string);
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  uNotice, uKeyChord, uKeymap, uInputLine;

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
  FCollapsed := TStringList.Create;
  FCollapsed.CaseSensitive := False;
end;

destructor TFolderHotlistDialogController.Destroy;
begin
  FCollapsed.Free;
  inherited;
end;

procedure TFolderHotlistDialogController.BuildRows(out AItems: TArray<string>);
var
  I, N: Integer;
  Prev: string;
  Folded: Boolean;
begin
  FEntries := FolderHotlistGetEntries;
  SetLength(AItems, Length(FEntries) * 2);
  SetLength(FRowEntry, Length(FEntries) * 2);
  SetLength(FRowGroup, Length(FEntries) * 2);
  N := 0;
  Prev := '';
  for I := 0 to High(FEntries) do
  begin
    if (FEntries[I].Group <> '') and not SameText(FEntries[I].Group, Prev) then
    begin
      AItems[N] := FolderHotlistGroupLabel(FEntries[I].Group,
        FCollapsed.IndexOf(FEntries[I].Group) >= 0);
      FRowEntry[N] := -1;
      FRowGroup[N] := FEntries[I].Group;
      Inc(N);
    end;
    Prev := FEntries[I].Group;
    Folded := (FEntries[I].Group <> '') and (FCollapsed.IndexOf(FEntries[I].Group) >= 0);
    // An empty group is only its header.
    if Folded or (FEntries[I].URI = '') then
      Continue;
    AItems[N] := FolderHotlistDisplayLabel(FEntries[I]);
    FRowEntry[N] := I;
    FRowGroup[N] := FEntries[I].Group;
    Inc(N);
  end;
  SetLength(AItems, N);
  SetLength(FRowEntry, N);
  SetLength(FRowGroup, N);
end;

function TFolderHotlistDialogController.RowEntry(ARow: Integer): Integer;
begin
  if (ARow >= 0) and (ARow <= High(FRowEntry)) then
    Result := FRowEntry[ARow]
  else
    Result := -1;
end;

procedure TFolderHotlistDialogController.SetGroupFolded(const AGroup: string;
  AFolded: Boolean);
var
  I: Integer;
begin
  I := FCollapsed.IndexOf(AGroup);
  if AFolded and (I < 0) then
    FCollapsed.Add(AGroup)
  else if not AFolded and (I >= 0) then
    FCollapsed.Delete(I);
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
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  FSnapshot := FolderHotlistGetEntries;
  FInSession := True;
  ReopenList;
end;

procedure TFolderHotlistDialogController.ReopenList;
var
  Items: TArray<string>;
begin
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  BuildRows(Items);

  SetKind(hdkFolderHotlist);
  FDialog.Open(BuildFolderHotlistDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.RefreshList(const ASelectGroup: string);
var
  Items: TArray<string>;
  I, Sel, E: Integer;
  SelUri, SelGroup: string;
begin
  if not (Assigned(FDialog) and FDialog.Visible) then
    Exit;
  // Moving or deleting an entry changes the row the cursor was on - follow
  // the entry by URI rather than keeping the same numeric row, which would
  // land on whatever unrelated entry sits in that slot now.
  Sel := FDialog.GetListSelectedIndex('hotlist');
  SelUri := '';
  SelGroup := '';
  E := RowEntry(Sel);
  if E >= 0 then
    SelUri := FEntries[E].URI
  else if (Sel >= 0) and (Sel <= High(FRowGroup)) then
    SelGroup := FRowGroup[Sel];
  BuildRows(Items);
  if ASelectGroup <> '' then
  begin
    SelUri := '';
    SelGroup := ASelectGroup;
  end;
  if (SelUri <> '') or (SelGroup <> '') then
    for I := 0 to High(FRowEntry) do
      if ((SelUri <> '') and (FRowEntry[I] >= 0) and
          SameVfsUri(FEntries[FRowEntry[I]].URI, SelUri)) or
         ((SelUri = '') and (FRowEntry[I] < 0) and SameText(FRowGroup[I], SelGroup)) then
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
  FEditGroup := False;
  FRenameGroupOld := '';
  SetKind(hdkFolderHotlistRename);
  FDialog.Open(BuildInputDialog(T('ui.hotlist.renameTitle', 'Rename hotlist entry'),
    T('ui.hotlist.namePrompt', 'Name:'), FEntries[AIndex].Name), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.BeginRenameGroup(const AGroup: string);
begin
  if AGroup = '' then
    Exit;
  FRenameGroupOld := AGroup;
  FEditGroup := False;
  SetKind(hdkFolderHotlistRename);
  FDialog.Open(BuildInputDialog(T('ui.hotlist.groupTitle', 'Hotlist entry group'),
    T('ui.hotlist.groupNamePrompt', 'Group name:'), AGroup), FOnCommand);
  Notify;
end;

procedure TFolderHotlistDialogController.OpenOnly(const AGroup: string);
var
  I: Integer;
begin
  FCollapsed.Clear;
  for I := 0 to High(FEntries) do
    if (FEntries[I].Group <> '') and not SameText(FEntries[I].Group, AGroup) and
       (FCollapsed.IndexOf(FEntries[I].Group) < 0) then
      FCollapsed.Add(FEntries[I].Group);
  RefreshList(AGroup);
end;

procedure TFolderHotlistDialogController.NavigateEntry(AEntryIdx: Integer);
var
  Uri: string;
begin
  Uri := FEntries[AEntryIdx].URI;
  // Like Go: the edits made so far stay.
  FInSession := False;
  SetLength(FSnapshot, 0);
  SetKind(hdkNone);
  FDialog.Close;
  SetLength(FEntries, 0);
  SetLength(FRowEntry, 0);
  SetLength(FRowGroup, 0);
  Notify;
  if (Uri <> '') and Assigned(FOnNavigate) then
    FOnNavigate(Uri);
end;

function TFolderHotlistDialogController.TryPressKey(AKeyChar: Char): Boolean;
var
  Pass, I: Integer;
  Want: Char;
begin
  Result := False;
  if AKeyChar <= ' ' then
    Exit;
  for Pass := 0 to 1 do
  begin
    if Pass = 0 then
      Want := UpCase(AKeyChar)
    else
      Want := UpCase(TextKeyLayoutAlternate(AKeyChar));
    if Want = #0 then
      Continue;
    // Entries on show first, then group headers.
    for I := 0 to High(FRowEntry) do
      if (FRowEntry[I] >= 0) and (HotlistKeyOf(FEntries[FRowEntry[I]].Name) = Want) then
      begin
        NavigateEntry(FRowEntry[I]);
        Exit(True);
      end;
    for I := 0 to High(FRowEntry) do
      if (FRowEntry[I] < 0) and (HotlistKeyOf(FRowGroup[I]) = Want) then
      begin
        OpenOnly(FRowGroup[I]);
        Exit(True);
      end;
  end;
end;

procedure TFolderHotlistDialogController.BeginGroup(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FRenameUri := FEntries[AIndex].URI;
  FEditGroup := True;
  FRenameGroupOld := '';
  SetKind(hdkFolderHotlistRename);
  FDialog.Open(BuildInputDialog(T('ui.hotlist.groupTitle', 'Hotlist entry group'),
    T('ui.hotlist.groupPrompt', 'Group (empty - none):'), FEntries[AIndex].Group),
    FOnCommand);
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
  // (hotkey-sorted) array - those two are different orderings.
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
  HotIdx, Row: Integer;
  HotKeyDigit: Integer;
  Uri: string;
  Moved: TArray<TFolderHotlistEntry>;
begin
  Result := False;
  // Left folds the selected group (its header or any of its entries),
  // Right unfolds it. With Shift, Ctrl or Alt the arrows stay with the list.
  if ((AKey = vkLeft) or (AKey = vkRight)) and
     TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([], [ssShift, ssAlt, ssCtrl]) then
  begin
    Row := FDialog.GetListSelectedIndex('hotlist');
    if (Row >= 0) and (Row <= High(FRowGroup)) and (FRowGroup[Row] <> '') then
    begin
      SetGroupFolded(FRowGroup[Row], AKey = vkLeft);
      // The cursor stays on the group header, as folding hides its entries.
      RefreshList(FRowGroup[Row]);
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkDelete then
  begin
    Row := FDialog.GetListSelectedIndex('hotlist');
    // Del on a group header removes the group when it is empty.
    if (Row >= 0) and (Row <= High(FRowEntry)) and (FRowEntry[Row] < 0) and
       FolderHotlistRemoveEmptyGroup(FRowGroup[Row]) then
    begin
      RefreshList;
      AKey := 0;
      AKeyChar := #0;
      Exit(True);
    end;
    HotIdx := RowEntry(Row);
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
    Row := FDialog.GetListSelectedIndex('hotlist');
    HotIdx := RowEntry(Row);
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
      BeginRename(HotIdx)
    else if (Row >= 0) and (Row <= High(FRowGroup)) then
      BeginRenameGroup(FRowGroup[Row]);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkF4 then
  begin
    HotIdx := RowEntry(FDialog.GetListSelectedIndex('hotlist'));
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
      BeginGroup(HotIdx);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  // Ctrl+Up / Ctrl+Down: move the selected entry one place; at a group
  // border it leaves or enters the group. The cursor follows the entry
  // (RefreshList tracks it by URI); a folded group it joins is unfolded.
  if ((AKey = vkUp) or (AKey = vkDown)) and
     TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([ssCtrl], [ssShift, ssAlt]) then
  begin
    HotIdx := RowEntry(FDialog.GetListSelectedIndex('hotlist'));
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) and
       FolderHotlistMoveByUri(FEntries[HotIdx].URI, Ord(AKey = vkDown) * 2 - 1) then
    begin
      Uri := FEntries[HotIdx].URI;
      Moved := FolderHotlistGetEntries;
      HotIdx := FolderHotlistFindByUri(Uri);
      if (HotIdx >= 0) and (Moved[HotIdx].Group <> '') then
        SetGroupFolded(Moved[HotIdx].Group, False);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  // Ctrl+1..Ctrl+9,Ctrl+0: toggle-assign that hotkey to the selected entry.
  // Pressing the digit already owning it clears it; pressing one owned by
  // another entry steals it (FolderHotlistSetHotKey enforces uniqueness).
  // Checked on AKey, not AKeyChar - Ctrl+digit has no ASCII control-code
  // to reverse-map, so AKeyChar is #0 for it (unlike Ctrl+letter).
  if TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([ssCtrl], [ssShift, ssAlt]) and
     (FolderHotlistKeyFromVKey(AKey) <> 0) then
  begin
    HotIdx := RowEntry(FDialog.GetListSelectedIndex('hotlist'));
    if (HotIdx >= 0) and (HotIdx <= High(FEntries)) then
    begin
      HotKeyDigit := FolderHotlistKeyFromVKey(AKey);
      if FEntries[HotIdx].HotKey = HotKeyDigit then
        FolderHotlistSetHotKeyByUri(FEntries[HotIdx].URI, 0) // already assigned here - toggle off
      else
        FolderHotlistSetHotKeyByUri(FEntries[HotIdx].URI, HotKeyDigit);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (AShift * [ssCtrl, ssAlt] = []) and (AKeyChar > ' ') and TryPressKey(AKeyChar) then
  begin
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
  // not AKeyChar - Ctrl+digit has no ASCII control-code to reverse-map, so
  // AKeyChar is #0 for it (unlike Ctrl+letter).
  if not TKeyChord.Make(AKey, AKeyChar, AShift).HasMods([ssCtrl]) then
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
var
  Idx: Integer;
begin
  Idx := RowEntry(AIdx);
  Result := AAccepted and (Idx >= 0) and
    (FEntries[Idx].URI <> '') and Assigned(FOnNavigate);
end;

procedure TFolderHotlistDialogController.DispatchListCommand(
  const AControlId: string);
var
  Idx: Integer;
  Accepted, Nav: Boolean;
begin
  // Snapshot before Close.
  Idx := FDialog.GetListSelectedIndex('hotlist');
  Accepted := DialogCmdIsListAccept(AControlId, 'hotlist');
  // Save keeps the edits and leaves the list open.
  if DialogCmdIs(AControlId, 'save') then
  begin
    FolderHotlistSave;
    FSnapshot := FolderHotlistGetEntries;
    SetKind(hdkFolderHotlist);
    if (Idx >= 0) and (Idx <= High(FRowEntry)) and (FRowEntry[Idx] < 0) then
      RefreshList(FRowGroup[Idx])
    else
      RefreshList;
    Notice(T('ui.toast.hotlistSaved', 'Folder hotlist saved'));
    Exit;
  end;
  // A double-click on a group header folds / unfolds it instead of closing
  // the list.
  if DialogCmdIs(AControlId, 'hotlist') and (Idx >= 0) and
     (Idx <= High(FRowEntry)) and (FRowEntry[Idx] < 0) then
  begin
    SetGroupFolded(FRowGroup[Idx], FCollapsed.IndexOf(FRowGroup[Idx]) < 0);
    // The host cleared the dialog kind while dispatching this command.
    SetKind(hdkFolderHotlist);
    RefreshList(FRowGroup[Idx]);
    Exit;
  end;
  Nav := ShouldNavigateOnAccept(Accepted, Idx);
  Idx := RowEntry(Idx);
  FDialog.Close;
  // Edits (delete, rename, group, order, hotkeys) apply as they are made;
  // anything but a jump to an entry rolls them back.
  if FInSession and not Accepted then
    FolderHotlistSetEntries(FSnapshot);
  FInSession := False;
  SetLength(FSnapshot, 0);
  if Nav then
    FOnNavigate(FEntries[Idx].URI);
  SetLength(FEntries, 0);
  SetLength(FRowEntry, 0);
  SetLength(FRowGroup, 0);
end;

procedure TFolderHotlistDialogController.DispatchAddCommand(
  const AControlId: string);
var
  Accepted: Boolean;
  NameVal, ActiveUri, Template, Keys: string;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  NameVal := FDialog.GetInputValue('name');
  FDialog.Close;
  ActiveUri := '';
  if Accepted and Assigned(FOnGetActiveUri) and FOnGetActiveUri(ActiveUri) then
  begin
    FolderHotlistAdd(NameVal, ActiveUri);
    if Trim(NameVal) = '' then
      NameVal := VfsUriTitle(ActiveUri);
    // The hint names the key that opens the hotlist in the active keymap,
    // which the user may have rebound.
    Template := T('ui.toast.hotlistAdded', '"%s" added to the folder hotlist');
    Keys := KeymapShortcutText(ActiveKeymap, kaFolderHotlist, 1);
    if Keys <> '' then
      Template := Template + ' (' + Keys + ')';
    Notice(Template, Trim(NameVal));
  end;
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
    if FRenameGroupOld <> '' then
      FolderHotlistRenameGroup(FRenameGroupOld, NameVal)
    else if FEditGroup then
      FolderHotlistSetGroupByUri(FRenameUri, NameVal)
    else
      FolderHotlistRenameByUri(FRenameUri, NameVal);
  // Return to the list dialog so Del/F2 can keep operating on it.
  ReopenList;
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
