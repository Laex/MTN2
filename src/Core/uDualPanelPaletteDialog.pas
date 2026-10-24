unit uDualPanelPaletteDialog;

{ Command palette (Shift+F9): a pick list of the top menu commands that can
  run now. Typing narrows the list, Enter runs the selected command. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uTopMenuBar, uCommandPalette,
  uDualPanelHistoryDialogs;

type
  TPaletteMenuGetter = reference to function: TTopMenuController;

  TCommandPaletteDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: THistoryDialogKindSetter;
    FOnNotify: TProc;
    FOnCanStart: THistoryDialogCanStart;
    FOnPrepareUi: THistoryDialogPrepareUi;
    FGetMenu: TPaletteMenuGetter;
    FAll: TArray<TPaletteEntry>;
    FShown: TArray<Integer>; // indexes into FAll, in list order
    FQuery: string;
    procedure RefreshList;
    procedure UpdateContext;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: THistoryDialogKindSetter; const AOnNotify: TProc;
      const AOnCanStart: THistoryDialogCanStart;
      const AOnPrepareUi: THistoryDialogPrepareUi;
      const AGetMenu: TPaletteMenuGetter);
    procedure OpenList;
    /// <summary>Typing and Backspace edit the search text; the other keys
    /// are left to the list.</summary>
    function HandleFilterInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(const AControlId: string): Boolean;
    /// <summary>The rows that are listed now (for tests).</summary>
    function RowCount: Integer;
  end;

implementation

uses
  System.Math, uStrings, uKeyChord;

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
  FQuery := '';
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkCommandPalette);
  RefreshList;
end;

procedure TCommandPaletteDialogController.RefreshList;
var
  Rows: TArray<string>;
  Decl: TDialogDeclaration;
  I: Integer;
begin
  FShown := PaletteRank(FAll, FQuery);
  SetLength(Rows, Length(FShown));
  for I := 0 to High(FShown) do
    Rows[I] := PaletteRowText(FAll[FShown[I]], cRowWidth);
  Decl := BuildCommandPaletteDialog(Rows, 0, FQuery);
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
  // The list moves the selection; the line under it follows.
  if (AKey in [vkUp, vkDown, vkPrior, vkNext, vkHome, vkEnd]) and
     FDialog.Visible and FDialog.HandleInput(AKey, AShift, AKeyChar) then
  begin
    if FDialog.Visible then
    begin
      UpdateContext;
      if Assigned(FOnNotify) then
        FOnNotify();
    end;
    Exit(True);
  end;
end;

function TCommandPaletteDialogController.RowCount: Integer;
begin
  Result := Length(FShown);
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
  FDialog.Close;
  Accepted := Accepted and (Idx >= 0) and (Idx <= High(FShown));
  if Accepted then
    Entry := FAll[FShown[Idx]];
  SetLength(FShown, 0);
  SetLength(FAll, 0);
  FQuery := '';
  if not Accepted then
    Exit;
  Menu := nil;
  if Assigned(FGetMenu) then
    Menu := FGetMenu();
  if (Menu <> nil) and Menu.RunItem(Entry.Item) then
    PaletteNoteRun(Entry.Key);
end;

end.
