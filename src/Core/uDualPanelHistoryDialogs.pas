unit uDualPanelHistoryDialogs;

{ Folder-history (Alt+F12), command-history (Alt+F8) and file-history
  (Alt+F11) pick-list dialogs.
  Extracted from TDualPanelWindow so the host keeps only thin Open forwards. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uFolderHistory, uFileHistory,
  uPanelUriLabels;

type
  THistoryDialogKindSetter = reference to procedure(AKind: THostDialogKind);
  THistoryDialogCanStart = reference to function: Boolean;
  THistoryDialogPrepareUi = reference to procedure;
  THistoryDialogNavigate = reference to procedure(const AUri: string);
  TCmdHistoryTryGetItems = reference to function(out AItems: TArray<string>): Boolean;
  TCmdHistoryApply = reference to procedure(const ACommand: string);
  TFileHistoryOpen = reference to procedure(const AUri: string; AEdit: Boolean);

  TFolderHistoryDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: THistoryDialogKindSetter;
    FOnNotify: TProc;
    FOnCanStart: THistoryDialogCanStart;
    FOnPrepareUi: THistoryDialogPrepareUi;
    FOnNavigate: THistoryDialogNavigate;
    FUris: TArray<string>;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: THistoryDialogKindSetter; const AOnNotify: TProc;
      const AOnCanStart: THistoryDialogCanStart;
      const AOnPrepareUi: THistoryDialogPrepareUi;
      const AOnNavigate: THistoryDialogNavigate);
    procedure OpenList;
    function DispatchCommand(const AControlId: string): Boolean;
    function ShouldNavigateToHistoryUri(AAccepted: Boolean; AIdx: Integer): Boolean;
  end;

  TCmdHistoryDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: THistoryDialogKindSetter;
    FOnNotify: TProc;
    FOnCanStart: THistoryDialogCanStart;
    FOnPrepareUi: THistoryDialogPrepareUi;
    FOnTryGetItems: TCmdHistoryTryGetItems;
    FOnApply: TCmdHistoryApply;
    FItems: TArray<string>;
    FAllItems: TArray<string>;
    FFilter: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure RefreshList;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: THistoryDialogKindSetter; const AOnNotify: TProc;
      const AOnCanStart: THistoryDialogCanStart;
      const AOnPrepareUi: THistoryDialogPrepareUi;
      const AOnTryGetItems: TCmdHistoryTryGetItems;
      const AOnApply: TCmdHistoryApply);
    procedure OpenList;
    function HandleFilterInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(const AControlId: string): Boolean;
    function ShouldApplyHistoryItem(AAccepted: Boolean; AIdx: Integer): Boolean;
  end;

  /// <summary>Alt+F11: files opened with F3/F4, newest first. Enter reopens
  /// in the mode last used, F3/F4 force Viewer/Editor, Ctrl+Enter shows the
  /// file in the active panel, Del forgets it, typing filters the list.</summary>
  TFileHistoryDialogController = class
  private
    FDialog: TDialogHost;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: THistoryDialogKindSetter;
    FOnNotify: TProc;
    FOnCanStart: THistoryDialogCanStart;
    FOnPrepareUi: THistoryDialogPrepareUi;
    FOnOpen: TFileHistoryOpen;
    FOnGoto: THistoryDialogNavigate;
    FAll: TArray<TFileHistoryEntry>;
    FItems: TArray<TFileHistoryEntry>; // FAll narrowed by FFilter
    FFilter: string;
    procedure SetKind(AKind: THostDialogKind);
    procedure Notify;
    procedure RefreshList(ASelected: Integer);
    function SelectedIndex: Integer;
  public
    constructor Create(ADialog: TDialogHost; const AOnCommand: TDialogCommandEvent;
      const AOnSetKind: THistoryDialogKindSetter; const AOnNotify: TProc;
      const AOnCanStart: THistoryDialogCanStart;
      const AOnPrepareUi: THistoryDialogPrepareUi;
      const AOnOpen: TFileHistoryOpen; const AOnGoto: THistoryDialogNavigate);
    procedure OpenList;
    /// <summary>F3/F4/Ctrl+Enter/Del and the filter. Plain Enter is left to
    /// the dialog (list accept -> DispatchCommand).</summary>
    function HandleListInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchCommand(const AControlId: string): Boolean;
  end;

/// <summary>"V  C:\dir\file.txt" / "E  ..." (marks translated).</summary>
function FileHistoryDisplayLabel(const AEntry: TFileHistoryEntry): string;

implementation

uses
  System.Math, uStrings;

const
  // Commands the list keys send through the dialog's OnCommand, so closing
  // follows the same path (FDialogKind reset, NotifyChanged) as Enter/OK.
  cFileHistCmdView = 'view';
  cFileHistCmdEdit = 'edit';
  cFileHistCmdGoto = 'goto';

function FileHistoryDisplayLabel(const AEntry: TFileHistoryEntry): string;
begin
  if AEntry.Edit then
    Result := T('ui.fileHistory.editMark', 'E')
  else
    Result := T('ui.fileHistory.viewMark', 'V');
  Result := Result + '  ' + FolderHistoryDisplayLabel(AEntry.URI);
end;

{ TFolderHistoryDialogController }

constructor TFolderHistoryDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: THistoryDialogKindSetter;
  const AOnNotify: TProc; const AOnCanStart: THistoryDialogCanStart;
  const AOnPrepareUi: THistoryDialogPrepareUi;
  const AOnNavigate: THistoryDialogNavigate);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnNavigate := AOnNavigate;
end;

procedure TFolderHistoryDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TFolderHistoryDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TFolderHistoryDialogController.OpenList;
var
  Uris: TArray<string>;
  Items: TArray<string>;
  I: Integer;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  Uris := FolderHistoryGetUris;
  FUris := Uris;
  SetLength(Items, Length(Uris));
  for I := 0 to High(Uris) do
    Items[I] := FolderHistoryDisplayLabel(Uris[I]);

  SetKind(hdkFolderHistory);
  FDialog.Open(BuildFolderHistoryDialog(Items, 0), FOnCommand);
  Notify;
end;

function TFolderHistoryDialogController.ShouldNavigateToHistoryUri(
  AAccepted: Boolean; AIdx: Integer): Boolean;
begin
  Result := AAccepted and (AIdx >= 0) and (AIdx <= High(FUris)) and
    (FUris[AIdx] <> '') and Assigned(FOnNavigate);
end;

function TFolderHistoryDialogController.DispatchCommand(
  const AControlId: string): Boolean;
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Result := True;
  Idx := FDialog.GetListSelectedIndex('folders');
  Accepted := DialogCmdIsListAccept(AControlId, 'folders');
  FDialog.Close;
  if ShouldNavigateToHistoryUri(Accepted, Idx) then
    FOnNavigate(FUris[Idx]);
  SetLength(FUris, 0);
end;

{ TCmdHistoryDialogController }

constructor TCmdHistoryDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: THistoryDialogKindSetter;
  const AOnNotify: TProc; const AOnCanStart: THistoryDialogCanStart;
  const AOnPrepareUi: THistoryDialogPrepareUi;
  const AOnTryGetItems: TCmdHistoryTryGetItems;
  const AOnApply: TCmdHistoryApply);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnTryGetItems := AOnTryGetItems;
  FOnApply := AOnApply;
end;

procedure TCmdHistoryDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TCmdHistoryDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TCmdHistoryDialogController.OpenList;
var
  Items: TArray<string>;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if not Assigned(FOnTryGetItems) or not FOnTryGetItems(Items) then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();

  FAllItems := Items;
  FItems := Items;
  FFilter := '';

  SetKind(hdkCmdHistory);
  FDialog.Open(BuildCmdHistoryDialog(Items, 0), FOnCommand);
  Notify;
end;

procedure TCmdHistoryDialogController.RefreshList;
var
  Filtered: TArray<string>;
  I, N: Integer;
  Decl: TDialogDeclaration;
begin
  SetLength(Filtered, Length(FAllItems));
  N := 0;
  for I := 0 to High(FAllItems) do
    if (FFilter = '') or
       (Pos(LowerCase(FFilter), LowerCase(FAllItems[I])) > 0) then
    begin
      Filtered[N] := FAllItems[I];
      Inc(N);
    end;
  SetLength(Filtered, N);
  FItems := Filtered;
  Decl := BuildCmdHistoryDialog(Filtered, 0);
  if FFilter <> '' then
    Decl.Title := T('ui.cmdHistory.filterTitle', 'Command history: %s', [FFilter]);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

function TCmdHistoryDialogController.HandleFilterInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
     not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    FFilter := FFilter + AKeyChar;
    RefreshList;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkBack then
  begin
    if FFilter <> '' then
    begin
      Delete(FFilter, Length(FFilter), 1);
      RefreshList;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

function TCmdHistoryDialogController.ShouldApplyHistoryItem(
  AAccepted: Boolean; AIdx: Integer): Boolean;
begin
  Result := AAccepted and (AIdx >= 0) and (AIdx <= High(FItems)) and
    (FItems[AIdx] <> '') and Assigned(FOnApply);
end;

function TCmdHistoryDialogController.DispatchCommand(
  const AControlId: string): Boolean;
var
  Idx: Integer;
  Accepted: Boolean;
begin
  Result := True;
  Idx := FDialog.GetListSelectedIndex('commands');
  Accepted := DialogCmdIsListAccept(AControlId, 'commands');
  FDialog.Close;
  if ShouldApplyHistoryItem(Accepted, Idx) then
    FOnApply(FItems[Idx]);
  SetLength(FItems, 0);
  SetLength(FAllItems, 0);
  FFilter := '';
end;

{ TFileHistoryDialogController }

constructor TFileHistoryDialogController.Create(ADialog: TDialogHost;
  const AOnCommand: TDialogCommandEvent; const AOnSetKind: THistoryDialogKindSetter;
  const AOnNotify: TProc; const AOnCanStart: THistoryDialogCanStart;
  const AOnPrepareUi: THistoryDialogPrepareUi;
  const AOnOpen: TFileHistoryOpen; const AOnGoto: THistoryDialogNavigate);
begin
  inherited Create;
  FDialog := ADialog;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnNotify := AOnNotify;
  FOnCanStart := AOnCanStart;
  FOnPrepareUi := AOnPrepareUi;
  FOnOpen := AOnOpen;
  FOnGoto := AOnGoto;
end;

procedure TFileHistoryDialogController.SetKind(AKind: THostDialogKind);
begin
  if Assigned(FOnSetKind) then
    FOnSetKind(AKind);
end;

procedure TFileHistoryDialogController.Notify;
begin
  if Assigned(FOnNotify) then
    FOnNotify();
end;

procedure TFileHistoryDialogController.OpenList;
begin
  if Assigned(FOnCanStart) and not FOnCanStart() then
    Exit;
  if Assigned(FOnPrepareUi) then
    FOnPrepareUi();
  FAll := FileHistoryGetEntries;
  FFilter := '';
  SetKind(hdkFileHistory);
  RefreshList(0);
end;

procedure TFileHistoryDialogController.RefreshList(ASelected: Integer);
var
  Labels: TArray<string>;
  I, N: Integer;
  Decl: TDialogDeclaration;
  Needle: string;
begin
  Needle := AnsiLowerCase(FFilter);
  SetLength(FItems, Length(FAll));
  SetLength(Labels, Length(FAll));
  N := 0;
  for I := 0 to High(FAll) do
    if (Needle = '') or
       (Pos(Needle, AnsiLowerCase(FolderHistoryDisplayLabel(FAll[I].URI))) > 0) then
    begin
      FItems[N] := FAll[I];
      Labels[N] := FileHistoryDisplayLabel(FAll[I]);
      Inc(N);
    end;
  SetLength(FItems, N);
  SetLength(Labels, N);
  Decl := BuildFileHistoryDialog(Labels, Max(Min(ASelected, N - 1), 0));
  if FFilter <> '' then
    Decl.Title := T('ui.fileHistory.filterTitle', 'File history: %s', [FFilter]);
  FDialog.Open(Decl, FOnCommand);
  Notify;
end;

function TFileHistoryDialogController.SelectedIndex: Integer;
begin
  Result := FDialog.GetListSelectedIndex('files');
  if (Result < 0) or (Result > High(FItems)) then
    Result := -1;
end;

function TFileHistoryDialogController.HandleListInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Mods: TShiftState;
  Idx: Integer;
  Cmd: string;
begin
  Result := False;
  Mods := AShift * [ssShift, ssAlt, ssCtrl];
  Cmd := '';
  if (AKey = vkF3) and (Mods = []) then
    Cmd := cFileHistCmdView
  else if (AKey = vkF4) and (Mods = []) then
    Cmd := cFileHistCmdEdit
  else if (AKey = vkReturn) and (Mods = [ssCtrl]) then
    Cmd := cFileHistCmdGoto;
  if Cmd <> '' then
  begin
    AKey := 0;
    AKeyChar := #0;
    if (SelectedIndex >= 0) and Assigned(FOnCommand) then
      FOnCommand(Cmd, '');
    Exit(True);
  end;
  if (AKey = vkDelete) and (Mods = []) then
  begin
    AKey := 0;
    AKeyChar := #0;
    Idx := SelectedIndex;
    if Idx >= 0 then
    begin
      FileHistoryRemove(FItems[Idx].URI);
      FAll := FileHistoryGetEntries;
      RefreshList(Idx);
    end;
    Exit(True);
  end;
  // Typing narrows the list (substring of the path, any case), like Alt+F8.
  if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
     not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    FFilter := FFilter + AKeyChar;
    RefreshList(0);
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if (AKey = vkBack) and (Mods = []) then
  begin
    if FFilter <> '' then
    begin
      Delete(FFilter, Length(FFilter), 1);
      RefreshList(0);
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

function TFileHistoryDialogController.DispatchCommand(
  const AControlId: string): Boolean;
var
  Idx: Integer;
  Entry: TFileHistoryEntry;
  Accepted, HasEntry: Boolean;
begin
  Result := True;
  Idx := SelectedIndex;
  HasEntry := Idx >= 0;
  if HasEntry then
    Entry := FItems[Idx];
  Accepted := DialogCmdIsListAccept(AControlId, 'files');
  FDialog.Close;
  SetLength(FItems, 0);
  SetLength(FAll, 0);
  FFilter := '';
  if not HasEntry then
    Exit;
  if SameText(AControlId, cFileHistCmdGoto) then
  begin
    if Assigned(FOnGoto) then
      FOnGoto(Entry.URI);
  end
  else if SameText(AControlId, cFileHistCmdView) then
  begin
    if Assigned(FOnOpen) then
      FOnOpen(Entry.URI, False);
  end
  else if SameText(AControlId, cFileHistCmdEdit) then
  begin
    if Assigned(FOnOpen) then
      FOnOpen(Entry.URI, True);
  end
  else if Accepted and Assigned(FOnOpen) then
    FOnOpen(Entry.URI, Entry.Edit);
end;

end.
