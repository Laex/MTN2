unit uDualPanelMultiRename;

{ Multi-rename dialog (Ctrl+Alt+N): rules for the new names, a live preview
  of every old -> new pair in columns, and the move job that applies them.
  The naming rules and the conflict checks live in uMultiRename. }

interface

uses
  System.SysUtils,
  uDialogHost, uDialogTypes, uDualPanelTypes, uDualPanelUiTypes, uMultiRename;

type
  TMultiRenameKindSetter = reference to procedure(AKind: THostDialogKind);
  TMultiRenameStubProc = reference to procedure(const ATitle, ADetail: string);
  /// <summary>Applies the renames: ASources[i] is moved to ADests[i].</summary>
  TMultiRenameStartProc = reference to procedure(const ASources, ADests: TArray<string>);
  /// <summary>Columns of the window the dialog opens in.</summary>
  TMultiRenameAreaFn = reference to function: Integer;

  TMultiRenameController = class
  private
    FDialog: TDialogHost;
    FRules: TMultiRenameRules;
    FSources: TArray<string>;
    FNames: TArray<string>;
    FIsDir: TArray<Boolean>;
    FExisting: TArray<string>;
    FDirUri: string;
    FSignature: string;
    FNameCols: Integer;
    FNoteCols: Integer;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TMultiRenameKindSetter;
    FOnPrepare: TProc;
    FOnStub: TMultiRenameStubProc;
    FOnStart: TMultiRenameStartProc;
    FOnNotify: TProc;
    FOnAreaCols: TMultiRenameAreaFn;
    function ReadRules: TMultiRenameRules;
    function RulesSignature(const ARules: TMultiRenameRules): string;
    function ProblemText(AProblem: TRenameProblem): string;
    function Cell(const AText: string; AWidth: Integer): string;
    procedure Refresh;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: TMultiRenameKindSetter; const AOnPrepare: TProc;
      const AOnStub: TMultiRenameStubProc; const AOnStart: TMultiRenameStartProc;
      const AOnNotify: TProc; const AOnAreaCols: TMultiRenameAreaFn);
    /// <summary>Opens the dialog for ASources (URIs of the selected rows of
    /// ARows, or the cursor row).</summary>
    procedure Open(const ASources: TArray<string>; const ARows: TPanelRows);
    /// <summary>Recomputes the preview after a field changed.</summary>
    procedure NotifyDialogChanged;
    function DispatchCommand(const AControlId: string): Boolean;
  end;

implementation

uses
  System.Math, System.StrUtils, uStrings, uVfsTypes;

const
  cMarkCols = 2;     // "! " in front of a row with a problem
  cSepCols = 3;      // " | " between the columns
  cMinDialogCols = 80;
  cDialogMargin = 5; // free columns on each side of the dialog

constructor TMultiRenameController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: TMultiRenameKindSetter;
  const AOnPrepare: TProc; const AOnStub: TMultiRenameStubProc;
  const AOnStart: TMultiRenameStartProc; const AOnNotify: TProc;
  const AOnAreaCols: TMultiRenameAreaFn);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnPrepare := AOnPrepare;
  FOnStub := AOnStub;
  FOnStart := AOnStart;
  FOnNotify := AOnNotify;
  FOnAreaCols := AOnAreaCols;
  FRules := DefaultMultiRenameRules;
end;

function TMultiRenameController.ReadRules: TMultiRenameRules;
begin
  Result.NameMask := FDialog.GetInputValue('name_mask');
  Result.ExtMask := FDialog.GetInputValue('ext_mask');
  Result.Search := FDialog.GetInputValue('search');
  Result.Replace := FDialog.GetInputValue('replace');
  Result.MatchCase := FDialog.GetCheckbox('match_case');
  Result.CounterStart := StrToIntDef(Trim(FDialog.GetInputValue('c_start')), 1);
  Result.CounterStep := StrToIntDef(Trim(FDialog.GetInputValue('c_step')), 1);
  Result.CounterDigits := EnsureRange(StrToIntDef(Trim(FDialog.GetInputValue('c_digits')), 1), 1, 12);
  Result.CaseMode := TRenameCase(EnsureRange(FDialog.GetListSelectedIndex('case_mode'),
    Ord(Low(TRenameCase)), Ord(High(TRenameCase))));
end;

function TMultiRenameController.RulesSignature(const ARules: TMultiRenameRules): string;
begin
  Result := Format('%s|%s|%s|%s|%d|%d|%d|%d|%d',
    [ARules.NameMask, ARules.ExtMask, ARules.Search, ARules.Replace,
     Ord(ARules.MatchCase), ARules.CounterStart, ARules.CounterStep,
     ARules.CounterDigits, Ord(ARules.CaseMode)]);
end;

function TMultiRenameController.ProblemText(AProblem: TRenameProblem): string;
begin
  case AProblem of
    rpEmpty: Result := T('ui.multiRename.problemEmpty', 'empty name');
    rpInvalid: Result := T('ui.multiRename.problemInvalid', 'invalid name');
    rpDuplicate: Result := T('ui.multiRename.problemDuplicate', 'same name twice');
    rpExists: Result := T('ui.multiRename.problemExists', 'name is taken');
  else
    Result := '';
  end;
end;

// The text cut or padded to exactly AWidth cells; a cut name ends in '~'.
function TMultiRenameController.Cell(const AText: string; AWidth: Integer): string;
begin
  if Length(AText) > AWidth then
    Result := Copy(AText, 1, Max(AWidth - 1, 0)) + '~'
  else
    Result := AText + StringOfChar(' ', AWidth - Length(AText));
end;

procedure TMultiRenameController.Refresh;
var
  Rules: TMultiRenameRules;
  Plan: TRenamePlan;
  Lines: TArray<string>;
  Accents: TArray<TListAccent>;
  I, Unchanged, Blocked, Prefix, Suffix, ChangedLen, NewCol, NoteCol, N: Integer;
  OldName, NewName, Note: string;

  procedure AddAccent(AItem, ACol, ALen: Integer);
  begin
    if ALen <= 0 then
      Exit;
    N := Length(Accents);
    SetLength(Accents, N + 1);
    Accents[N].Item := AItem;
    Accents[N].Col := ACol;
    Accents[N].Len := ALen;
  end;

begin
  if not FDialog.Visible then
    Exit;
  Rules := ReadRules;
  if RulesSignature(Rules) = FSignature then
    Exit;
  FSignature := RulesSignature(Rules);
  FRules := Rules;
  Plan := PlanMultiRename(FNames, FIsDir, FExisting, Rules);
  SetLength(Lines, Length(Plan));
  SetLength(Accents, 0);
  Unchanged := 0;
  Blocked := 0;
  NewCol := cMarkCols + FNameCols + cSepCols;
  NoteCol := NewCol + FNameCols + cSepCols;
  for I := 0 to High(Plan) do
  begin
    OldName := Plan[I].OldName;
    NewName := Plan[I].NewName;
    Note := '';
    case Plan[I].Problem of
      rpNone: ;
      rpUnchanged:
        begin
          Inc(Unchanged);
          NewName := '';
        end;
    else
      Note := ProblemText(Plan[I].Problem);
      Inc(Blocked);
    end;
    Lines[I] := Cell(IfThen(Plan[I].Problem in [rpNone, rpUnchanged], '', '!'), cMarkCols) +
      Cell(OldName, FNameCols) + ' | ' + Cell(NewName, FNameCols) + ' | ' +
      Cell(Note, FNoteCols);
    // The stretch of the new name that differs from the original name: what lies
    // between their common beginning and common end.
    if NewName <> '' then
    begin
      Prefix := 0;
      while (Prefix < Length(OldName)) and (Prefix < Length(NewName)) and
            (OldName[Prefix + 1] = NewName[Prefix + 1]) do
        Inc(Prefix);
      Suffix := 0;
      while (Suffix < Length(OldName) - Prefix) and (Suffix < Length(NewName) - Prefix) and
            (OldName[Length(OldName) - Suffix] = NewName[Length(NewName) - Suffix]) do
        Inc(Suffix);
      ChangedLen := Length(NewName) - Prefix - Suffix;
      AddAccent(I, NewCol + Prefix, Min(ChangedLen, FNameCols - Prefix));
    end;
    if Note <> '' then
      AddAccent(I, NoteCol, Min(Length(Note), FNoteCols));
  end;
  FDialog.BeginUpdate;
  try
    FDialog.SetLabelText('status', Format(
      T('ui.multiRename.status', '%d to rename, %d unchanged, %d with a problem'),
      [RenamePlanChangeCount(Plan), Unchanged, Blocked]));
    FDialog.SetListItems('preview', Lines, 0);
    FDialog.SetListAccents('preview', Accents);
  finally
    FDialog.EndUpdate;
  end;
end;

procedure TMultiRenameController.Open(const ASources: TArray<string>;
  const ARows: TPanelRows);
var
  I, J, N, DialogCols: Integer;
  Row: TPanelRow;
  Name: string;
  Found: Boolean;
begin
  if Length(ASources) = 0 then
  begin
    if Assigned(FOnStub) then
      FOnStub(T('ui.multiRename.title', 'Multi-rename'),
        T('ui.multiRename.nothingSelected', 'Select files or folders first'));
    Exit;
  end;
  FDirUri := ParentFileUri(ASources[0]);
  SetLength(FSources, 0);
  SetLength(FNames, 0);
  SetLength(FIsDir, 0);
  for I := 0 to High(ASources) do
  begin
    if ParentFileUri(ASources[I]) <> FDirUri then
    begin
      if Assigned(FOnStub) then
        FOnStub(T('ui.multiRename.title', 'Multi-rename'),
          T('ui.multiRename.oneFolder', 'Select items of one folder'));
      Exit;
    end;
    Found := False;
    for J := 0 to High(ARows) do
      if (not ARows[J].IsParent) and (ARows[J].URI = ASources[I]) then
      begin
        Name := ARows[J].Text;
        if (Name <> '') and (Name[Length(Name)] = '/') then
          Delete(Name, Length(Name), 1);
        N := Length(FSources);
        SetLength(FSources, N + 1);
        SetLength(FNames, N + 1);
        SetLength(FIsDir, N + 1);
        FSources[N] := ASources[I];
        FNames[N] := Name;
        FIsDir[N] := ARows[J].IsDirectory;
        Found := True;
        Break;
      end;
    if not Found then
      Exit;
  end;
  SetLength(FExisting, 0);
  for Row in ARows do
    if not Row.IsParent then
    begin
      Name := Row.Text;
      if (Name <> '') and (Name[Length(Name)] = '/') then
        Delete(Name, Length(Name), 1);
      N := Length(FExisting);
      SetLength(FExisting, N + 1);
      FExisting[N] := Name;
    end;
  // The dialog spans the window minus a margin on each side. The list (the
  // dialog width less 4, one cell of it the scroll bar) is split into the
  // old name, the new name and a note about a problem.
  DialogCols := cMinDialogCols;
  if Assigned(FOnAreaCols) then
    DialogCols := Max(FOnAreaCols() - 2 * cDialogMargin, cMinDialogCols);
  FNoteCols := 20;
  FNameCols := (DialogCols - 4 - 1 - cMarkCols - 2 * cSepCols - FNoteCols) div 2;
  if Assigned(FOnPrepare) then
    FOnPrepare();
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkMultiRename);
  FSignature := '';
  FDialog.Open(BuildMultiRenameDialog(FRules, DialogCols), FOnCommand);
  FDialog.SetLabelText('columns',
    Cell('', cMarkCols) + Cell(T('ui.multiRename.colOld', 'Old name'), FNameCols) + ' | ' +
    Cell(T('ui.multiRename.colNew', 'New name'), FNameCols) + ' | ' +
    T('ui.multiRename.colNote', 'Note'));
  Refresh;
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TMultiRenameController.NotifyDialogChanged;
begin
  Refresh;
end;

function TMultiRenameController.DispatchCommand(const AControlId: string): Boolean;
var
  Plan: TRenamePlan;
  Sources, Dests: TArray<string>;
  I, N: Integer;
begin
  Result := True;
  if DialogCmdIsReject(AControlId) then
  begin
    FDialog.Close;
    Exit;
  end;
  if not DialogCmdIsAccept(AControlId) then
    Exit;
  Plan := PlanMultiRename(FNames, FIsDir, FExisting, ReadRules);
  if RenamePlanBlocked(Plan) then
  begin
    FSignature := '';
    Refresh;
    FDialog.SetLabelText('status',
      T('ui.multiRename.blocked', 'Fix the names marked with ! first'));
    Exit;
  end;
  FDialog.Close;
  SetLength(Sources, 0);
  SetLength(Dests, 0);
  for I := 0 to High(Plan) do
    if Plan[I].Problem = rpNone then
    begin
      N := Length(Sources);
      SetLength(Sources, N + 1);
      SetLength(Dests, N + 1);
      Sources[N] := FSources[I];
      Dests[N] := JoinFileUri(FDirUri, Plan[I].NewName);
    end;
  if (Length(Sources) > 0) and Assigned(FOnStart) then
    FOnStart(Sources, Dests);
end;

end.
