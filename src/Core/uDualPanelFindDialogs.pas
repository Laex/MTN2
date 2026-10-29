unit uDualPanelFindDialogs;

{ Alt+F7 search dialog and directory-sync preview. Extracted from
  TDualPanelWindow; Find/VFS execution stays on TSearchController / FJobs. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uDialogHost, uDialogTypes, uDialogJson, uDualPanelUiTypes, uDualPanelSearch,
  uDualPanelSync, uDualPanelJobs, uDualPanelJobList, uVfsTypes, uFindSession, uDialogHistory;

type
  TFindKindSetter = reference to procedure(AKind: THostDialogKind);
  TFindBlockedFn = reference to function: Boolean;
  TFindPrepareProc = reference to procedure;
  TFindGetUriFn = reference to function: string;
  TFindStubProc = reference to procedure(const ATitle, ADetail: string);
  TFindAliveFn = reference to function: Boolean;

  TSearchDialogController = class
  private
    FDialog: TDialogHost;
    FSearch: TSearchController;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFindKindSetter;
    FOnBlocked: TFindBlockedFn;
    FOnPrepare: TFindPrepareProc;
    FOnGetUri: TFindGetUriFn;
    FOnNotify: TProc;
    FPickField: string;
    FSyncing: Boolean;
    FHexMode: Boolean;
    FLastText: string;
    FLastHex: string;
    function ReadDialogFields: TDialogCommandFields;
    procedure ApplyFields(const AFields: TDialogCommandFields);
    procedure BeginDatePick(const AFieldId: string);
  public
    constructor Create(ADialog: TDialogHost; ASearch: TSearchController;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFindKindSetter;
      const AOnBlocked: TFindBlockedFn; const AOnPrepare: TFindPrepareProc;
      const AOnGetUri: TFindGetUriFn; const AOnNotify: TProc);
    procedure Open;
    /// <summary>Keeps the text and hex fields in step while either is edited:
    /// text shows its UTF-8 bytes; bytes that spell text show it; bytes typed
    /// by hand are searched instead of the text.</summary>
    procedure SyncHexField;
    function DispatchCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    /// <summary>F9 on a date field opens the calendar.</summary>
    function HandleEditInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function DispatchDatePickerCommand(const AControlId: string): Boolean;
  end;

  TDirSyncDialogController = class
  private
    FDialog: TDialogHost;
    FJobs: TPanelJobList;
    FItems: TArray<TSyncItem>;
    FBusy: Boolean;
    FSrcRoot: string;
    FDstRoot: string;
    FSnapshotPending: Boolean;
    FPendingConflictRels: TArray<string>;
    FByContent: Boolean;
    FComparedByContent: Boolean;
    FCompareGen: Integer;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TFindKindSetter;
    FOnPrepare: TFindPrepareProc;
    FOnOpenStub: TFindStubProc;
    FOnCloseStub: TProc;
    FOnNotify: TProc;
    FOnAlive: TFindAliveFn;
    procedure StartCompare;
    procedure ApplyCompareResult(const AItems: TArray<TSyncItem>;
      const AError: string; AByContent: Boolean; AGen: Integer);
  public
    constructor Create(ADialog: TDialogHost; AJobs: TPanelJobList;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFindKindSetter;
      const AOnPrepare: TFindPrepareProc; const AOnOpenStub: TFindStubProc;
      const AOnCloseStub, AOnNotify: TProc; const AOnAlive: TFindAliveFn);
    procedure Open(const ASrcURI, ADstURI: string);
    function DispatchCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
    procedure NotifyJobFinished(ASuccess: Boolean);
    procedure NotifyDialogChanged;
    property Busy: Boolean read FBusy;
  end;

function ResolveSearchRootPath(const ACurrentUri: string): string;

implementation

uses
  System.DateUtils, uFileFind, uStrings;

function ResolveSearchRootPath(const ACurrentUri: string): string;
var
  FindData: TFindSessionData;
begin
  if HasArchiveChain(ACurrentUri) then
    Result := SafeDirectoryName(ArchiveBasePath(ACurrentUri))
  else if IsFindUri(ACurrentUri) then
  begin
    if TryGetFindSessionFromUri(ACurrentUri, FindData) then
      Result := FindData.RootPath
    else
      Result := '';
  end
  else
    Result := FileUriToPath(ACurrentUri);
  if (Result <> '') and (Length(Result) = 2) and (Result[2] = ':') then
    Result := Result + PathDelim;
end;

constructor TSearchDialogController.Create(ADialog: TDialogHost;
  ASearch: TSearchController; const AOnCommand: TDialogCommandEvent;
  const AOnSetKind: TFindKindSetter; const AOnBlocked: TFindBlockedFn;
  const AOnPrepare: TFindPrepareProc; const AOnGetUri: TFindGetUriFn;
  const AOnNotify: TProc);
begin
  inherited Create;
  FDialog := ADialog;
  FSearch := ASearch;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnBlocked := AOnBlocked;
  FOnPrepare := AOnPrepare;
  FOnGetUri := AOnGetUri;
  FOnNotify := AOnNotify;
end;

procedure TSearchDialogController.Open;
var
  Mask, Uri: string;
begin
  if not Assigned(FSearch) or not Assigned(FDialog) then
    Exit;
  if FSearch.Phase = spResults then
    FSearch.CloseSearchUi;
  if FSearch.Phase <> spNone then
    Exit;
  if Assigned(FOnBlocked) and FOnBlocked() then
    Exit;
  if Assigned(FOnPrepare) then
    FOnPrepare();

  Uri := '';
  if Assigned(FOnGetUri) then
    Uri := FOnGetUri();
  FSearch.RootPath := ResolveSearchRootPath(Uri);
  Mask := FSearch.Mask;
  if Mask = '' then
    Mask := '*.*';
  FSearch.FocusField := 0;
  FSearch.Phase := spNone;
  if not FSearch.HexMode then
    FSearch.HexText := TextToHexString(FSearch.ContainingText);
  FHexMode := FSearch.HexMode;
  FLastText := FSearch.ContainingText;
  FLastHex := FSearch.HexText;
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkSearch);
  if not FDialog.OpenJson(
    DeclarationToJson(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.HexText, FSearch.Subdirs, FSearch.Filters)),
    FOnCommand) then
    FDialog.Open(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.HexText, FSearch.Subdirs, FSearch.Filters), FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.ReadDialogFields: TDialogCommandFields;
begin
  Result := Default(TDialogCommandFields);
  Result.Mask := FDialog.GetInputValue('search_mask');
  Result.Containing := FDialog.GetInputValue('search_text');
  Result.Subdirs := FDialog.GetCheckbox('search_subdirs');
  Result.CaseSens := FDialog.GetCheckbox('search_case');
  Result.WholeWords := FDialog.GetCheckbox('search_words');
  Result.SearchFolders := FDialog.GetCheckbox('search_folders');
  Result.UseRegex := FDialog.GetCheckbox('search_regex');
  Result.HexText := FDialog.GetInputValue('search_hex');
  Result.Filters.SizeMin := FDialog.GetInputValue('filter_size_min');
  Result.Filters.SizeMax := FDialog.GetInputValue('filter_size_max');
  Result.Filters.DateFrom := FDialog.GetInputValue('filter_date_from');
  Result.Filters.DateTo := FDialog.GetInputValue('filter_date_to');
  Result.Filters.AttrReadOnly := FDialog.GetCheckbox('filter_attr_ro');
  Result.Filters.AttrHidden := FDialog.GetCheckbox('filter_attr_hidden');
  Result.Filters.AttrSystem := FDialog.GetCheckbox('filter_attr_system');
  Result.Filters.AttrArchive := FDialog.GetCheckbox('filter_attr_archive');
end;

procedure TSearchDialogController.SyncHexField;
var
  Text, Hex, NewHex, NewText: string;
  Cursor, NewCursor: Integer;
begin
  if FSyncing or not Assigned(FDialog) then
    Exit;
  FSyncing := True;
  try
    Text := FDialog.GetInputValue('search_text');
    Hex := FDialog.GetInputValue('search_hex');
    if Text <> FLastText then
    begin
      FHexMode := False;
      NewHex := TextToHexString(Text);
      if NewHex <> Hex then
        FDialog.SetInputValue('search_hex', NewHex);
      FLastText := Text;
      FLastHex := NewHex;
    end
    else if Hex <> FLastHex then
    begin
      Cursor := FDialog.GetInputCursor('search_hex');
      EditHexField(FLastHex, Hex, Cursor, NewHex, NewCursor);
      if (NewHex <> Hex) or (NewCursor <> Cursor) then
        FDialog.SetInputValueAt('search_hex', NewHex, NewCursor);
      if NewHex <> FLastHex then
      begin
        FHexMode := True;
        FLastHex := NewHex;
        if TryHexToText(NewHex, NewText) and (NewText <> Text) then
        begin
          FDialog.SetInputValue('search_text', NewText);
          FLastText := NewText;
        end;
      end;
    end;
  finally
    FSyncing := False;
  end;
end;

procedure TSearchDialogController.ApplyFields(const AFields: TDialogCommandFields);
begin
  FSearch.Mask := AFields.Mask;
  if FSearch.Mask = '' then
    FSearch.Mask := '*.*';
  FSearch.ContainingText := AFields.Containing;
  FSearch.CaseSensitive := AFields.CaseSens;
  FSearch.WholeWords := AFields.WholeWords;
  FSearch.SearchFolders := AFields.SearchFolders;
  FSearch.UseRegex := AFields.UseRegex;
  FSearch.HexText := AFields.HexText;
  FSearch.HexMode := FHexMode;
  FSearch.Subdirs := AFields.Subdirs;
  FSearch.Filters := AFields.Filters;
end;

procedure TSearchDialogController.BeginDatePick(const AFieldId: string);
var
  Fields: TDialogCommandFields;
  Filters: TFindFilterText;
  Text, TimeText: string;
  Stamp: TDateTime;
begin
  Fields := ReadDialogFields;
  ApplyFields(Fields);
  FPickField := AFieldId;
  Filters := FSearch.Filters;
  if SameText(AFieldId, 'filter_date_to') then
    Text := Filters.DateTo
  else
    Text := Filters.DateFrom;
  Stamp := 0;
  TimeText := '';
  // The same reading as the search itself, so a weekday in the short date
  // opens the calendar on that day instead of today.
  if not TryParseFindDate(Text, False, Stamp) then
    Stamp := 0;
  if (Stamp <> 0) and (Frac(Stamp) <> 0) then
    TimeText := FormatDateTime('hh:nn', Stamp);
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkDatePicker);
  FDialog.Open(BuildDatePickerDialog(T('ui.datePicker.title', 'Pick date'),
    Stamp, TimeText), FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.HandleEditInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Id: string;
begin
  Result := False;
  if AKey <> vkF9 then
    Exit;
  Id := FDialog.FocusedControlId;
  if not (SameText(Id, 'filter_date_from') or SameText(Id, 'filter_date_to')) then
    Exit;
  BeginDatePick(Id);
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

function TSearchDialogController.DispatchDatePickerCommand(
  const AControlId: string): Boolean;
var
  Value, TimeText: string;
  Stamp: TDateTime;
  Filters: TFindFilterText;
begin
  Result := True;
  Value := '';
  if DialogCmdIsAccept(AControlId) then
  begin
    TimeText := Trim(FDialog.GetInputValue('time'));
    Value := DateToStr(FDialog.GetDatePickerDate('date'));
    // A time that is not a time of day is left out rather than guessed.
    if (TimeText <> '') and TryStrToTime(TimeText, Stamp) then
      Value := Value + ' ' + FormatDateTime('hh:nn', Stamp);
  end
  else if not DialogCmdIs(AControlId, 'clear') then
    Value := #0;
  FDialog.Close;
  if Assigned(FSearch) then
  begin
    Filters := FSearch.Filters;
    if Value <> #0 then
      if SameText(FPickField, 'filter_date_to') then
        Filters.DateTo := Value
      else
        Filters.DateFrom := Value;
    FSearch.Filters := Filters;
  end;
  Open;
end;

function TSearchDialogController.DispatchCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  PickField: string;
begin
  Result := True;
  if DialogCmdIsPick(AControlId, PickField) then
  begin
    BeginDatePick(PickField);
    Exit;
  end;
  FDialog.Close;
  if not Assigned(FSearch) then
    Exit;
  if DialogCmdIsOk(AControlId) then
  begin
    ApplyFields(AFields);
    // The editor's F7 starts from this text (a regex is not a plain needle).
    if not (AFields.UseRegex or FHexMode) then
      DialogHistoryAdd('editfind', Trim(AFields.Containing));
    FSearch.StartSearch;
  end
  else
    FSearch.CloseSearchUi;
end;

constructor TDirSyncDialogController.Create(ADialog: TDialogHost;
  AJobs: TPanelJobList; const AOnCommand: TDialogCommandEvent;
  const AOnSetKind: TFindKindSetter; const AOnPrepare: TFindPrepareProc;
  const AOnOpenStub: TFindStubProc; const AOnCloseStub, AOnNotify: TProc;
  const AOnAlive: TFindAliveFn);
begin
  inherited Create;
  FDialog := ADialog;
  FJobs := AJobs;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
  FOnPrepare := AOnPrepare;
  FOnOpenStub := AOnOpenStub;
  FOnCloseStub := AOnCloseStub;
  FOnNotify := AOnNotify;
  FOnAlive := AOnAlive;
  FBusy := False;
  FSnapshotPending := False;
  FSrcRoot := '';
  FDstRoot := '';
  FByContent := False;
  FComparedByContent := False;
  FCompareGen := 0;
  SetLength(FItems, 0);
  SetLength(FPendingConflictRels, 0);
end;

procedure TDirSyncDialogController.Open(const ASrcURI, ADstURI: string);
var
  SrcPath, DstPath: string;
begin
  if FBusy then
    Exit;
  if Assigned(FOnPrepare) then
    FOnPrepare();

  if not DirSyncUrisAreLocalFolders(ASrcURI, ADstURI) then
  begin
    if Assigned(FOnOpenStub) then
      FOnOpenStub('Synchronize', 'Only local folders (file://) are supported');
    Exit;
  end;
  SrcPath := FileUriToPath(ASrcURI);
  DstPath := FileUriToPath(ADstURI);
  if (SrcPath = '') or (DstPath = '') or not TDirectory.Exists(SrcPath) then
  begin
    if Assigned(FOnOpenStub) then
      FOnOpenStub('Synchronize', 'Active panel must be a local folder');
    Exit;
  end;

  FSrcRoot := SrcPath;
  FDstRoot := DstPath;
  FSnapshotPending := False;
  FByContent := False;
  FComparedByContent := False;
  SetLength(FPendingConflictRels, 0);
  StartCompare;
end;

procedure TDirSyncDialogController.StartCompare;
var
  Snap: TArray<TSyncSnapshotEntry>;
  Gen: Integer;
  ByContent: Boolean;
begin
  if FBusy then
    Exit;
  FBusy := True;
  Inc(FCompareGen);
  Gen := FCompareGen;
  ByContent := FByContent;
  if Assigned(FDialog) and FDialog.Visible then
    FDialog.SetLabelText('status', 'Comparing...')
  else if Assigned(FOnOpenStub) then
    FOnOpenStub('Synchronize', 'Comparing directories... Esc=wait');
  Snap := LoadDirSyncSnapshot(FSrcRoot, FDstRoot);
  CompareDirsTwoWayAsync(FSrcRoot, FDstRoot, Snap,
    procedure(const AItems: TArray<TSyncItem>; const AError: string)
    begin
      ApplyCompareResult(AItems, AError, ByContent, Gen);
    end, ByContent);
end;

procedure TDirSyncDialogController.ApplyCompareResult(
  const AItems: TArray<TSyncItem>; const AError: string;
  AByContent: Boolean; AGen: Integer);
var
  Preview: TArray<string>;
begin
  if AGen <> FCompareGen then
    Exit;
  FBusy := False;
  if Assigned(FOnAlive) and not FOnAlive() then
    Exit;
  if AError <> '' then
  begin
    if Assigned(FOnCloseStub) then
      FOnCloseStub();
    if Assigned(FOnOpenStub) then
      FOnOpenStub('Synchronize failed', AError);
    Exit;
  end;
  FItems := AItems;
  FComparedByContent := AByContent;
  Preview := FormatSyncPreviewLines(AItems, 12);
  if Assigned(FDialog) and FDialog.Visible then
  begin
    FDialog.SetLabelText('status', FormatDirSyncStatus(AItems));
    FDialog.SetListItems('preview', Preview, 0);
  end
  else
  begin
    if Assigned(FOnCloseStub) then
      FOnCloseStub();
    if Assigned(FOnSetKind) then
      FOnSetKind(hdkDirSync);
    FDialog.Open(BuildDirSyncDialog(FSrcRoot, FDstRoot,
      FormatDirSyncStatus(AItems), Preview, False, False, AByContent),
      FOnCommand);
  end;
  if Assigned(FOnNotify) then
    FOnNotify();
  if Assigned(FDialog) and FDialog.Visible then
  begin
    FByContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
    if FByContent <> FComparedByContent then
      StartCompare;
  end;
end;

procedure TDirSyncDialogController.NotifyDialogChanged;
var
  WantContent: Boolean;
begin
  if FBusy then
    Exit;
  if not Assigned(FDialog) or not FDialog.Visible then
    Exit;
  WantContent := SameText(FDialog.GetRadio('compare_by'), 'bycontent');
  if WantContent = FComparedByContent then
    Exit;
  FByContent := WantContent;
  StartCompare;
end;

function TDirSyncDialogController.DispatchCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
var
  Accepted: Boolean;
  Sources, DestURIs: TArray<string>;
  Conflicts: Integer;
  CopyCount: Integer;
  Msg: string;
begin
  Result := True;
  Accepted := DialogCmdIsAccept(AControlId);
  FDialog.Close;
  if Accepted then
  begin
    CollectDirSyncJobPairs(FItems, Sources, DestURIs, AFields.SyncTwoWay);
    CopyCount := Length(Sources);
    Conflicts := CountSyncConflicts(FItems);
    if AFields.DryRun then
    begin
      if Conflicts > 0 then
        Msg := Format('Would copy %d file(s); %d conflict(s) left unresolved',
          [CopyCount, Conflicts])
      else
        Msg := Format('Would copy %d file(s)', [CopyCount]);
      if Assigned(FOnOpenStub) then
        FOnOpenStub('Synchronize', Msg);
    end
    else if CopyCount = 0 then
    begin
      if Conflicts > 0 then
        Msg := Format('Nothing to copy; %d conflict(s) need a manual choice',
          [Conflicts])
      else
        Msg := 'Nothing to copy';
      if Assigned(FOnOpenStub) then
        FOnOpenStub('Synchronize', Msg);
      try
        CommitDirSyncSnapshot(FSrcRoot, FDstRoot,
          CollectDirSyncUnresolvedRels(FItems, AFields.SyncTwoWay));
      except
      end;
    end
    else if Assigned(FJobs) and FJobs.CanStartAnother then
    begin
      FPendingConflictRels := CollectDirSyncUnresolvedRels(FItems,
        AFields.SyncTwoWay);
      FSnapshotPending := True;
      FJobs.BeginJobPairs(Sources, DestURIs, pjkCopy);
    end;
  end;
  SetLength(FItems, 0);
end;

procedure TDirSyncDialogController.NotifyJobFinished(ASuccess: Boolean);
begin
  if not FSnapshotPending then
    Exit;
  FSnapshotPending := False;
  if not ASuccess then
  begin
    SetLength(FPendingConflictRels, 0);
    Exit;
  end;
  try
    CommitDirSyncSnapshot(FSrcRoot, FDstRoot, FPendingConflictRels);
  except
  end;
  SetLength(FPendingConflictRels, 0);
end;

end.
