unit uDualPanelKeymapDialog;

{ Keymap hotkey list / editor dialogs (hdkKeymap, hdkKeymapEdit). Lets the
  user rebind any TKeymapAction, warns before silently stealing a hotkey
  from another action, and writes the result to the user's keymap.json
  (uKeymap.SaveKeymapProfile) on Save. Extracted as its own controller so
  TDualPanelWindow keeps only a thin OpenKeymapDialog + dispatch forward,
  mirroring uDualPanelColorCoding.pas. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uKeymap;

type
  TKeymapKindSetter = reference to procedure(AKind: THostDialogKind);
  TKeymapCanStart = reference to function: Boolean;
  TKeymapPrepareUi = reference to procedure;

  TKeymapDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TKeymapKindSetter;
    FOnNotify: TProc;
    FOnCanStart: TKeymapCanStart;
    FOnPrepareUi: TKeymapPrepareUi;
    /// <summary>Working copy the dialogs edit; nothing is written to disk
    /// until Save. Cloned from ActiveKeymap so in-place edits never alias
    /// the shared cache (see uKeymap.CloneKeymapProfile).</summary>
    FProfile: TKeymapProfile;
    /// <summary>Snapshot of FProfile as opened — diffed against FProfile on
    /// Save so a Cancel-only session never touches keymap.json.</summary>
    FOriginal: TKeymapProfile;
    /// <summary>Embedded defaults — source for the per-action / whole-profile
    /// Reset buttons.</summary>
    FDefaults: TKeymapProfile;
    FEditAction: TKeymapAction;
    /// <summary>Set once a conflict warning has been shown for the pending
    /// edit — a second Save press with the same conflicting combo confirms
    /// the reassignment instead of warning again.</summary>
    FConfirmOverwrite: Boolean;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    function ActionCount: Integer;
    function ActionRowLabel(AAction: TKeymapAction): string;
    function BuildRows: TArray<string>;
    /// <summary>Splits AText on ';', parses each token via
    /// uKeymapRegistry.TryParseKeyCombo. Returns False with AError set on the
    /// first unrecognized token.</summary>
    function TryParseKeysField(const AText: string;
      out ABindings: TArray<TKeyBinding>; out AError: string): Boolean;
    /// <summary>Other actions (not AExclude) whose bindings overlap one of
    /// ABindings, in FProfile as it stands right now.</summary>
    function FindConflicts(const ABindings: TArray<TKeyBinding>;
      AExclude: TKeymapAction): TArray<TKeymapAction>;
    /// <summary>Strips every binding in ABindings away from any other action
    /// that currently holds it, then assigns ABindings to FEditAction —
    /// makes each hotkey unambiguous again after a reassignment.</summary>
    procedure ApplyEdit(const ABindings: TArray<TKeyBinding>);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TKeymapKindSetter; const AOnNotify: TProc;
      const AOnCanStart: TKeymapCanStart; const AOnPrepareUi: TKeymapPrepareUi);
    procedure OpenList;
    procedure RefreshList(ASelectedIndex: Integer = -1);
    procedure BeginEdit(AIndex: Integer);
    procedure ResetSelected;
    procedure ResetAll;
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    procedure DispatchListCommand(const AControlId: string);
    function DispatchEditCommand(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind;
      const AControlId: string): Boolean;
  end;

implementation

uses
  uKeymapRegistry;

constructor TKeymapDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TKeymapKindSetter;
  const AOnNotify: TProc; const AOnCanStart: TKeymapCanStart;
  const AOnPrepareUi: TKeymapPrepareUi);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FEditAction := kaNone;
end;

procedure TKeymapDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TKeymapDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TKeymapDialogController.ActionCount: Integer;
begin
  Result := Ord(High(TKeymapAction)); // kaNone = 0, so this is also the count.
end;

function TKeymapDialogController.ActionRowLabel(AAction: TKeymapAction): string;
var
  Name, Keys: string;
begin
  Name := KeymapActionDisplayName(AAction);
  Keys := BindingsToStr(FProfile.Bindings[AAction]);
  if Keys = '' then
    Keys := '(none)';
  Result := Format('%-28s%s', [Name, Keys]);
end;

function TKeymapDialogController.BuildRows: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, ActionCount);
  for I := 0 to ActionCount - 1 do
    Result[I] := ActionRowLabel(TKeymapAction(I + 1));
end;

procedure TKeymapDialogController.OpenList;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  FProfile := CloneKeymapProfile(ActiveKeymap);
  FOriginal := CloneKeymapProfile(FProfile);
  FDefaults := LoadDefaultKeymapProfile;

  SetKind(hdkKeymap);
  FDialog.Open(BuildKeymapDialog(BuildRows, 0), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.RefreshList(ASelectedIndex: Integer);
var
  Sel: Integer;
begin
  if not Assigned(FDialog) then
    Exit;
  if ASelectedIndex >= 0 then
    Sel := ASelectedIndex
  else
    Sel := FDialog.GetListSelectedIndex('actions');
  if Sel > ActionCount - 1 then
    Sel := ActionCount - 1;
  if Sel < 0 then
    Sel := 0;
  SetKind(hdkKeymap);
  FDialog.Open(BuildKeymapDialog(BuildRows, Sel), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.BeginEdit(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > ActionCount - 1) then
    Exit;
  FEditAction := TKeymapAction(AIndex + 1);
  FConfirmOverwrite := False;
  SetKind(hdkKeymapEdit);
  FDialog.Open(BuildKeymapEditDialog(KeymapActionDisplayName(FEditAction),
    BindingsToStr(FProfile.Bindings[FEditAction]), ''), FOnCommand);
  Notify;
end;

procedure TKeymapDialogController.ResetSelected;
var
  Idx: Integer;
  Act: TKeymapAction;
begin
  Idx := FDialog.GetListSelectedIndex('actions');
  if (Idx < 0) or (Idx > ActionCount - 1) then
    Exit;
  Act := TKeymapAction(Idx + 1);
  FProfile.Bindings[Act] := Copy(FDefaults.Bindings[Act]);
  RefreshList(Idx);
end;

procedure TKeymapDialogController.ResetAll;
begin
  FProfile := CloneKeymapProfile(FDefaults);
  RefreshList(0);
end;

function TKeymapDialogController.TryParseKeysField(const AText: string;
  out ABindings: TArray<TKeyBinding>; out AError: string): Boolean;
var
  Tokens: TArray<string>;
  I: Integer;
  Token: string;
  Binding: TKeyBinding;
begin
  SetLength(ABindings, 0);
  AError := '';
  Tokens := AText.Split([';']);
  for I := 0 to High(Tokens) do
  begin
    Token := Trim(Tokens[I]);
    if Token = '' then
      Continue;
    if not TryParseKeyCombo(Token, Binding) then
    begin
      AError := 'Unrecognized key: "' + Token + '".';
      Exit(False);
    end;
    ABindings := ABindings + [Binding];
  end;
  Result := True;
end;

function TKeymapDialogController.FindConflicts(const ABindings: TArray<TKeyBinding>;
  AExclude: TKeymapAction): TArray<TKeymapAction>;
var
  Act: TKeymapAction;
  I, J: Integer;
  Found: Boolean;
begin
  SetLength(Result, 0);
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
  begin
    if Act = AExclude then
      Continue;
    Found := False;
    for I := 0 to High(ABindings) do
      for J := 0 to High(FProfile.Bindings[Act]) do
        if SameKeyBinding(ABindings[I], FProfile.Bindings[Act][J]) then
        begin
          Found := True;
          Break;
        end;
    if Found then
      Result := Result + [Act];
  end;
end;

procedure TKeymapDialogController.ApplyEdit(const ABindings: TArray<TKeyBinding>);
var
  Act: TKeymapAction;
  Kept: TArray<TKeyBinding>;
  I, J: Integer;
  Clash: Boolean;
begin
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
  begin
    if Act = FEditAction then
      Continue;
    SetLength(Kept, 0);
    for I := 0 to High(FProfile.Bindings[Act]) do
    begin
      Clash := False;
      for J := 0 to High(ABindings) do
        if SameKeyBinding(FProfile.Bindings[Act][I], ABindings[J]) then
        begin
          Clash := True;
          Break;
        end;
      if not Clash then
        Kept := Kept + [FProfile.Bindings[Act][I]];
    end;
    if Length(Kept) <> Length(FProfile.Bindings[Act]) then
      FProfile.Bindings[Act] := Kept;
  end;
  FProfile.Bindings[FEditAction] := ABindings;
end;

function TKeymapDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if AKey = vkF4 then
  begin
    BeginEdit(FDialog.GetListSelectedIndex('actions'));
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TKeymapDialogController.DispatchListCommand(const AControlId: string);
begin
  if DialogCmdIs(AControlId, 'edit') then
    BeginEdit(FDialog.GetListSelectedIndex('actions'))
  else if DialogCmdIs(AControlId, 'reset') then
    ResetSelected
  else if DialogCmdIs(AControlId, 'resetall') then
    ResetAll
  else if DialogCmdIsAccept(AControlId) then
  begin
    FDialog.Close;
    // Only touch keymap.json if the effective bindings actually
    // changed — comparing serialized JSON is simpler and just as
    // correct as a field-by-field diff.
    if KeymapProfileToJson(FProfile) <> KeymapProfileToJson(FOriginal) then
    begin
      SaveKeymapProfile(FProfile);
      ReloadKeymap('');
    end;
  end
  else
    // Cancel or dismiss: discard the working copy, nothing is written.
    FDialog.Close;
end;

function TKeymapDialogController.DispatchEditCommand(
  const AControlId: string): Boolean;
var
  SelectAfter: Integer;
  NewBindings: TArray<TKeyBinding>;
  Conflicts: TArray<TKeymapAction>;
  ParseError, Names, Status: string;
  I: Integer;
begin
  SelectAfter := Ord(FEditAction) - 1;
  if DialogCmdIs(AControlId, 'reset') then
  begin
    FDialog.SetInputValue('km_keys', BindingsToStr(FDefaults.Bindings[FEditAction]));
    FDialog.SetStatus('km_status', '');
    FConfirmOverwrite := False;
    Notify;
    Exit(False);
  end;
  if DialogCmdIsAccept(AControlId) then
  begin
    if not TryParseKeysField(FDialog.GetInputValue('km_keys'), NewBindings, ParseError) then
    begin
      FDialog.SetStatus('km_status', ParseError);
      SetKind(hdkKeymapEdit);
      Notify;
      Exit(False);
    end;
    Conflicts := FindConflicts(NewBindings, FEditAction);
    if (Length(Conflicts) > 0) and not FConfirmOverwrite then
    begin
      Names := '';
      for I := 0 to High(Conflicts) do
      begin
        if I > 0 then
          Names := Names + ', ';
        Names := Names + KeymapActionDisplayName(Conflicts[I]);
      end;
      Status := 'Already used by: ' + Names + '. Press OK again to reassign.';
      FDialog.SetStatus('km_status', Status);
      FConfirmOverwrite := True;
      SetKind(hdkKeymapEdit);
      Notify;
      Exit(False);
    end;
    ApplyEdit(NewBindings);
  end;
  FDialog.Close;
  RefreshList(SelectAfter);
  Result := True;
end;

function TKeymapDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string): Boolean;
begin
  Result := True;
  case AKind of
    hdkKeymap: DispatchListCommand(AControlId);
    hdkKeymapEdit: Result := DispatchEditCommand(AControlId);
  else
    { not a keymap dialog }
  end;
end;

end.
