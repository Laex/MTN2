unit uDualPanelFindDialogs;

{ Alt+F7 search dialog and directory-sync preview. Extracted from
  TDualPanelWindow; Find/VFS execution stays on TSearchController / FJobs. }

interface

uses
  System.SysUtils, System.IOUtils,
  uDialogHost, uDialogTypes, uDialogJson, uDualPanelUiTypes, uDualPanelSearch,
  uDualPanelSync, uDualPanelJobs, uDualPanelJobList, uVfsTypes, uFindSession;

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
  public
    constructor Create(ADialog: TDialogHost; ASearch: TSearchController;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TFindKindSetter;
      const AOnBlocked: TFindBlockedFn; const AOnPrepare: TFindPrepareProc;
      const AOnGetUri: TFindGetUriFn; const AOnNotify: TProc);
    procedure Open;
    function DispatchCommand(const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
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

function ResolveSearchRootPath(const ACurrentUri: string): string;
var
  FindData: TFindSessionData;
begin
  if HasArchiveChain(ACurrentUri) then
    Result := TPath.GetDirectoryName(ArchiveBasePath(ACurrentUri))
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
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkSearch);
  if not FDialog.OpenJson(
    DeclarationToJson(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.Subdirs)),
    FOnCommand) then
    FDialog.Open(BuildSearchDialog(Mask, FSearch.ContainingText,
      FSearch.CaseSensitive, FSearch.WholeWords, FSearch.SearchFolders,
      FSearch.UseRegex, FSearch.Subdirs), FOnCommand);
  if Assigned(FOnNotify) then
    FOnNotify();
end;

function TSearchDialogController.DispatchCommand(const AControlId: string;
  const AFields: TDialogCommandFields): Boolean;
begin
  Result := True;
  FDialog.Close;
  if not Assigned(FSearch) then
    Exit;
  if DialogCmdIsOk(AControlId) then
  begin
    FSearch.Mask := AFields.Mask;
    if FSearch.Mask = '' then
      FSearch.Mask := '*.*';
    FSearch.ContainingText := AFields.Containing;
    FSearch.CaseSensitive := AFields.CaseSens;
    FSearch.WholeWords := AFields.WholeWords;
    FSearch.SearchFolders := AFields.SearchFolders;
    FSearch.UseRegex := AFields.UseRegex;
    FSearch.Subdirs := AFields.Subdirs;
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
    FDialog.SetLabelText('status', 'Comparing…')
  else if Assigned(FOnOpenStub) then
    FOnOpenStub('Synchronize', 'Comparing directories… Esc=wait');
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
