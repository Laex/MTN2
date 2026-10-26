unit uDualPanelPaletteDialog;

{ Command palette (Shift+F9): a pick list of the top menu commands that can
  run now. Typing narrows the list, Enter runs the selected command. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uTopMenuBar, uCommandPalette, uHelpContext,
  uDualPanelHistoryDialogs, uKeymap;

type
  TPaletteMenuGetter = reference to function: TTopMenuController;
  /// <summary>Ctrl+K on a command: opens the key list on the command's action.
  /// Called with kaNone for a command that has no key to assign; False when
  /// nothing was opened.</summary>
  TPaletteAssignKey = reference to function(AAction: TKeymapAction): Boolean;
  /// <summary>Runs a panel action that has no menu item, as its key would.</summary>
  TPaletteRunAction = reference to procedure(AAction: TKeymapAction);

  TCommandPaletteDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: THistoryDialogKindSetter;
    FOnNotify: TProc;
    FOnCanStart: THistoryDialogCanStart;
    FOnPrepareUi: THistoryDialogPrepareUi;
    FGetMenu: TPaletteMenuGetter;
    FOnAssignKey: TPaletteAssignKey;
    FOnRunAction: TPaletteRunAction;
    FAll: TArray<TPaletteEntry>;
    /// <summary>The search text and the command the palette had when it was
    /// left for the key list; Resume restores them.</summary>
    FResumeQuery: string;
    FResumeKey: string;
    FShown: TArray<Integer>; // indexes into FAll, in list order
    FQuery: string;
    procedure RefreshList(const ASelectKey: string = '');
    procedure UpdateContext;
    procedure AssignKeyToSelected;
    procedure Start(const AQuery, ASelectKey: string);
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: THistoryDialogKindSetter; const AOnNotify: TProc;
      const AOnCanStart: THistoryDialogCanStart;
      const AOnPrepareUi: THistoryDialogPrepareUi;
      const AGetMenu: TPaletteMenuGetter);
    procedure OpenList;
    /// <summary>Opens the palette again as it was left for the key list: the
    /// same search text, the same command selected, and the shortcut column
    /// read afresh.</summary>
    procedure Resume;
    /// <summary>Typing and Backspace edit the search text; the other keys
    /// are left to the list.</summary>
    function HandleFilterInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(const AControlId: string): Boolean;
    /// <summary>The rows that are listed now (for tests).</summary>
    function RowCount: Integer;
    /// <summary>Help topic of the selected command ('' when nothing is selected).</summary>
    function SelectedHelpTopic: string;
    property OnAssignKey: TPaletteAssignKey read FOnAssignKey write FOnAssignKey;
    /// <summary>Without it the palette lists menu commands only.</summary>
    property OnRunAction: TPaletteRunAction read FOnRunAction write FOnRunAction;
  end;

implementation

uses
  System.Math, uStrings, uKeyChord, uDualPanelKeymapDialog;

const
  cRowWidth = 76;

constructor TCommandPaletteDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: THistoryDialogKindSetter;
  const AOnNotify: TProc; const AOnCanStart: THistoryDialogCanStart;
  const AOnPrepareUi: THistoryDialogPrepareUi; const AGetMenu: TPaletteMenuGetter);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FGetMenu := AGetMenu;
end;

procedure TCommandPaletteDialogController.OpenList;
begin
  Start('', '');
end;

procedure TCommandPaletteDialogController.Resume;
begin
  Start(FResumeQuery, FResumeKey);
end;

procedure TCommandPaletteDialogController.Start(const AQuery, ASelectKey: string);
var
  Menu: TTopMenuController;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  Menu := nil;
  if Assigned(FGetMenu) then
    Menu := FGetMenu();
  if Menu = nil then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  FAll := BuildPaletteEntries(Menu);
  if Assigned(FOnRunAction) then
    AppendKeymapOnlyEntries(Menu, KeymapActionCaption, FAll);
  FQuery := AQuery;
  // The line under the list follows the selected item, keyboard or mouse.
  FDialog.OnListSelected :=
    procedure(const AControlId: string)
    begin
      if AControlId = 'commands' then
        UpdateContext;
    end;
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkCommandPalette);
  RefreshList(ASelectKey);
end;

procedure TCommandPaletteDialogController.RefreshList(const ASelectKey: string);
var
  Rows: TArray<string>;
  Decl: TDialogDeclaration;
  I, Sel: Integer;
begin
  FShown := PaletteRank(FAll, FQuery);
  Sel := 0;
  for I := 0 to High(FShown) do
    if (ASelectKey <> '') and (FAll[FShown[I]].Key = ASelectKey) then
    begin
      Sel := I;
      Break;
    end;
  SetLength(Rows, Length(FShown));
  for I := 0 to High(FShown) do
    Rows[I] := PaletteRowText(FAll[FShown[I]], cRowWidth);
  Decl := BuildCommandPaletteDialog(Rows, Sel, FQuery);
  FDialog.Open(Decl, FOnCommand);
  FDialog.FocusControlById('commands');
  UpdateContext;
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TCommandPaletteDialogController.UpdateContext;
var
  Idx: Integer;
begin
  Idx := FDialog.GetListSelectedIndex('commands');
  if (Idx < 0) or (Idx > High(FShown)) then
    FDialog.SetLabelText('context', '')
  else
    FDialog.SetLabelText('context', PaletteContextText(FAll, FShown[Idx]));
end;

function TCommandPaletteDialogController.HandleFilterInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Chord: TKeyChord;
begin
  Result := False;
  Chord := TKeyChord.Make(AKey, AKeyChar, AShift);
  if Chord.MatchesLetter('K', [ssCtrl]) then
  begin
    AKey := 0;
    AKeyChar := #0;
    AssignKeyToSelected;
    Exit(True);
  end;
  if Chord.IsPrintable and Chord.HasMods([], [ssShift]) then
  begin
    FQuery := FQuery + AKeyChar;
    RefreshList;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkBack then
  begin
    if FQuery <> '' then
    begin
      Delete(FQuery, Length(FQuery), 1);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

// The palette closes first: the key list opens only when no other dialog is up.
procedure TCommandPaletteDialogController.AssignKeyToSelected;
var
  Idx: Integer;
  Action: TKeymapAction;
begin
  if not Assigned(FOnAssignKey) then
    Exit;
  Idx := FDialog.GetListSelectedIndex('commands');
  if (Idx < 0) or (Idx > High(FShown)) then
    Exit;
  Action := FAll[FShown[Idx]].Action;
  if (Action = kaNone) and not FAll[FShown[Idx]].Item.IsPluginItem then
    Action := TopMenuKeymapAction(FAll[FShown[Idx]].Item.Action);
  if Action = kaNone then
  begin
    FOnAssignKey(kaNone);
    Exit;
  end;
  FResumeQuery := FQuery;
  FResumeKey := FAll[FShown[Idx]].Key;
  FDialog.OnListSelected := nil;
  FDialog.Close;
  SetLength(FShown, 0);
  SetLength(FAll, 0);
  FQuery := '';
  FOnAssignKey(Action);
end;

function TCommandPaletteDialogController.RowCount: Integer;
begin
  Result := Length(FShown);
end;

function TCommandPaletteDialogController.SelectedHelpTopic: string;
var
  Idx: Integer;
begin
  Result := '';
  Idx := FDialog.GetListSelectedIndex('commands');
  if (Idx >= 0) and (Idx <= High(FShown)) then
    Result := HelpTopicForMenuAction(FAll[FShown[Idx]].Key);
end;

function TCommandPaletteDialogController.DispatchCommand(
  const AControlId: string): Boolean;
var
  Idx: Integer;
  Accepted: Boolean;
  Entry: TPaletteEntry;
  Menu: TTopMenuController;
begin
  Result := True;
  Idx := FDialog.GetListSelectedIndex('commands');
  Accepted := DialogCmdIsListAccept(AControlId, 'commands');
  FDialog.OnListSelected := nil;
  FDialog.Close;
  Accepted := Accepted and (Idx >= 0) and (Idx <= High(FShown));
  if Accepted then
    Entry := FAll[FShown[Idx]];
  SetLength(FShown, 0);
  SetLength(FAll, 0);
  FQuery := '';
  if not Accepted then
    Exit;
  if Entry.Action <> kaNone then
  begin
    if Assigned(FOnRunAction) then
    begin
      PaletteNoteRun(Entry.Key);
      FOnRunAction(Entry.Action);
    end;
    Exit;
  end;
  Menu := nil;
  if Assigned(FGetMenu) then
    Menu := FGetMenu();
  if (Menu <> nil) and Menu.RunItem(Entry.Item) then
    PaletteNoteRun(Entry.Key);
end;

end.
