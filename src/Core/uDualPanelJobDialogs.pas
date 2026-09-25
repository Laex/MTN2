unit uDualPanelJobDialogs;

{ Job confirm / overwrite / delete-error dialog dispatch. Extracted from
  TDualPanelWindow so ConfirmJob / VFS transfer stay on TPanelJobController. }

interface

uses
  System.SysUtils,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uDualPanelJobs,
  uDualPanelJobList, uDualPanelJobRules, uVfsTypes;

type
  TJobKindSetter = reference to procedure(AKind: THostDialogKind);

  TJobDialogController = class
  private
    FDialog: TDialogHost;
    FJobs: TPanelJobList;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TJobKindSetter;
    procedure ApplyJobConfirmOptions(const AFields: TDialogCommandFields);
    procedure HandleOverwriteRenameCmd(const AControlId: string;
      const AFields: TDialogCommandFields);
    procedure HandleOverwriteAskCmd(const AControlId: string;
      const AFields: TDialogCommandFields);
    procedure HandleDeleteErrorCmd(const AControlId: string);
    procedure HandleIOErrorCmd(const AControlId: string);
    procedure HandleJobConfirmCmd(const AControlId: string;
      const AFields: TDialogCommandFields);
    procedure HandleJobListCmd(const AControlId: string);
    procedure HandleJobProgressCmd(const AControlId: string);
  public
    constructor Create(ADialog: TDialogHost; AJobs: TPanelJobList;
      const AOnCommand: TDialogCommandEvent; const AOnSetKind: TJobKindSetter);
    function TryHandleOverwriteRename(const AControlId: string): Boolean;
    function DispatchCommand(AKind: THostDialogKind; const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
  end;

function JobOverwriteModeFromIndex(AIdx: Integer): TJobOverwriteMode;
function JobRetryLimitFromIndex(AIdx: Integer): Integer;
function JobConfirmDestUri(AKind: TPanelJobKind; const ADestPath,
  AFallbackUri: string): string;
function JobConflictActionFromCommand(const AControlId: string): TJobConflictAction;
function JobDeleteFailActionFromCommand(const AControlId: string;
  AToRecycleBin: Boolean): TJobDeleteFailAction;
function JobIOErrorActionFromCommand(const AControlId: string): TJobIOErrorAction;
function JobDestRejectedReason(AKind: TPanelJobKind; const ADestURI: string): string;
function JobDestFailTitle(AKind: TPanelJobKind): string;
function SuggestPackZipName(const ASources: TArray<string>): string;
function SourcesContainArchive(const ASources: TArray<string>): Boolean;
function UnpackSourcesAreValid(const ASources: TArray<string>;
  out AError: string): Boolean;
function BuildJobProgressDialog(const AJob: TPanelJobState): TDialogDeclaration;
procedure ApplyJobProgressToDecl(var ADecl: TDialogDeclaration;
  const AJob: TPanelJobState);
procedure ApplyJobProgressToDialog(ADialog: TDialogHost;
  const AJob: TPanelJobState);

implementation

uses
  uDialogResources, uStrings;

const
  cJobProgressInnerW = 72;

procedure ApplyJobProgressSnapshotToDecl(var ADecl: TDialogDeclaration;
  const ASnap: TJobProgressSnapshot);
begin
  DialogSetTitle(ADecl, ASnap.Title);
  if ASnap.IsError then
  begin
    DialogSetLabelText(ADecl, 'message', ASnap.Message);
    Exit;
  end;
  DialogSetLabelText(ADecl, 'verb', ASnap.Verb);
  DialogSetLabelText(ADecl, 'src', ASnap.Src);
  DialogSetLabelText(ADecl, 'dst', ASnap.Dst);
  DialogSetLabelText(ADecl, 'file_bar', ASnap.FileBar);
  DialogSetLabelText(ADecl, 'files', ASnap.Files);
  DialogSetLabelText(ADecl, 'bytes', ASnap.Bytes);
  DialogSetLabelText(ADecl, 'total_bar', ASnap.TotalBar);
end;

procedure ApplyJobProgressToDecl(var ADecl: TDialogDeclaration;
  const AJob: TPanelJobState);
begin
  ApplyJobProgressSnapshotToDecl(ADecl, BuildJobProgressSnapshot(AJob, cJobProgressInnerW));
end;

procedure ApplyJobProgressToDialog(ADialog: TDialogHost;
  const AJob: TPanelJobState);
var
  Snap: TJobProgressSnapshot;
begin
  if not Assigned(ADialog) then
    Exit;
  Snap := BuildJobProgressSnapshot(AJob, cJobProgressInnerW);
  ADialog.BeginUpdate;
  try
    if Snap.IsError then
      ADialog.SetLabelText('message', Snap.Message)
    else
    begin
      ADialog.SetLabelText('verb', Snap.Verb);
      ADialog.SetLabelText('src', Snap.Src);
      ADialog.SetLabelText('dst', Snap.Dst);
      ADialog.SetLabelText('file_bar', Snap.FileBar);
      ADialog.SetLabelText('files', Snap.Files);
      ADialog.SetLabelText('bytes', Snap.Bytes);
      ADialog.SetLabelText('total_bar', Snap.TotalBar);
    end;
  finally
    ADialog.EndUpdate;
  end;
end;

function BuildJobProgressDialog(const AJob: TPanelJobState): TDialogDeclaration;
begin
  RequireDialogResource(JobProgressResourceName(AJob), Result);
  ApplyJobProgressToDecl(Result, AJob);
end;

function JobOverwriteModeFromIndex(AIdx: Integer): TJobOverwriteMode;
begin
  case AIdx of
    1: Result := jomOverwrite;
    2: Result := jomSkip;
  else
    Result := jomAsk;
  end;
end;

function JobRetryLimitFromIndex(AIdx: Integer): Integer;
begin
  case AIdx of
    0: Result := 0;
    2: Result := 3;
  else
    Result := 1;
  end;
end;

function JobConfirmDestUri(AKind: TPanelJobKind; const ADestPath,
  AFallbackUri: string): string;
var
  DestPath: string;
begin
  DestPath := Trim(ADestPath);
  if DestPath = '' then
    Exit(AFallbackUri);
  // Copy onto tmp:/// (and other VFS dests) shows the URI in the dest field.
  // PathToFileUri would turn that into a bogus file:// path on disk.
  if Pos('://', DestPath) > 1 then
    Exit(DestPath);
  if (AKind = pjkPack) then
  begin
    if SameText(ExtractFileExt(DestPath), '.zip') or
       SameText(ExtractFileExt(DestPath), '.7z') then
      { keep }
    else
      DestPath := DestPath + '.zip';
  end;
  Result := PathToFileUri(ExcludeTrailingPathDelimiter(DestPath));
end;

function JobConflictActionFromCommand(const AControlId: string): TJobConflictAction;
begin
  if DialogCmdIs(AControlId, cDlgCmdOverwrite) then
    Result := jcaOverwrite
  else if DialogCmdIs(AControlId, cDlgCmdSkip) then
    Result := jcaSkip
  else if DialogCmdIs(AControlId, cDlgCmdAppend) then
    Result := jcaAppend
  else
    Result := jcaCancel;
end;

function JobDeleteFailActionFromCommand(const AControlId: string;
  AToRecycleBin: Boolean): TJobDeleteFailAction;
begin
  if DialogCmdIs(AControlId, cDlgCmdDelete) or
     DialogCmdIs(AControlId, cDlgCmdRetry) or
     DialogCmdIsOk(AControlId) then
  begin
    if AToRecycleBin then
      Result := jdaPermanent
    else
      Result := jdaRetry;
  end
  else if DialogCmdIs(AControlId, cDlgCmdSkip) then
    Result := jdaSkip
  else if DialogCmdIs(AControlId, cDlgCmdSkipAll) then
    Result := jdaSkipAll
  else
    Result := jdaCancel;
end;

function JobIOErrorActionFromCommand(const AControlId: string): TJobIOErrorAction;
begin
  if DialogCmdIs(AControlId, cDlgCmdRetry) or DialogCmdIsOk(AControlId) then
    Result := jioRetry
  else if DialogCmdIs(AControlId, cDlgCmdSkip) then
    Result := jioSkip
  else if DialogCmdIs(AControlId, cDlgCmdSkipAll) then
    Result := jioSkipAll
  else
    Result := jioCancel;
end;

function DestIsArchiveOrVirtual(const ADestURI: string): Boolean;
begin
  Result := HasArchiveChain(ADestURI) or IsFindUri(ADestURI) or
    IsSystemFoldersUri(ADestURI);
end;

function JobDestRejectedReason(AKind: TPanelJobKind; const ADestURI: string): string;
begin
  Result := '';
  case AKind of
    pjkDelete: ;
    pjkCopy:
      if (not IsSevenZipUri(ADestURI)) and DestIsArchiveOrVirtual(ADestURI) then
        Result := 'Opposite panel must be a local folder';
    pjkMove:
      if DestIsArchiveOrVirtual(ADestURI) then
        Result := 'Opposite panel must be a local folder';
    pjkPack:
      if (not IsSevenZipUri(ADestURI)) and
         (HasArchiveChain(ADestURI) or IsFindUri(ADestURI) or
          (FileUriToPath(ADestURI) = '')) then
        Result := 'Opposite panel must be a local folder';
    pjkUnpack:
      if HasArchiveChain(ADestURI) or IsFindUri(ADestURI) or
         (FileUriToPath(ADestURI) = '') then
        Result := 'Opposite panel must be a local folder';
  end;
end;

function JobDestFailTitle(AKind: TPanelJobKind): string;
begin
  case AKind of
    pjkMove: Result := 'Move failed';
    pjkPack: Result := 'Pack failed';
    pjkUnpack: Result := 'Unpack failed';
  else
    Result := 'Copy failed';
  end;
end;

function SuggestPackZipName(const ASources: TArray<string>): string;
var
  Suggest: string;
begin
  if Length(ASources) = 1 then
  begin
    Suggest := FileUriTitle(ASources[0]);
    if (Suggest <> '') and (Suggest[Length(Suggest)] = '/') then
      Delete(Suggest, Length(Suggest), 1);
    Result := ChangeFileExt(Suggest, '') + '.zip';
  end
  else
    Result := 'archive.zip';
end;

function SourcesContainArchive(const ASources: TArray<string>): Boolean;
var
  S: string;
begin
  for S in ASources do
    if HasArchiveChain(S) then
      Exit(True);
  Result := False;
end;

function UnpackSourcesAreValid(const ASources: TArray<string>;
  out AError: string): Boolean;
var
  I: Integer;
  Name: string;
  Ok: Boolean;
begin
  AError := '';
  Ok := False;
  for I := 0 to High(ASources) do
  begin
    if HasArchiveChain(ASources[I]) then
      Ok := True
    else
    begin
      Name := FileUriTitle(ASources[I]);
      if IsZipFileName(Name) then
        Ok := True
      else
      begin
        AError := 'Select a ZIP file or items inside an archive';
        Exit(False);
      end;
    end;
  end;
  Result := Ok;
end;

constructor TJobDialogController.Create(ADialog: TDialogHost;
  AJobs: TPanelJobList; const AOnCommand: TDialogCommandEvent;
  const AOnSetKind: TJobKindSetter);
begin
  inherited Create;
  FDialog := ADialog;
  FJobs := AJobs;
  FOnCommand := AOnCommand;
  FOnSetKind := AOnSetKind;
end;

procedure TJobDialogController.ApplyJobConfirmOptions(
  const AFields: TDialogCommandFields);
var
  DestURI, ExcludeMask: string;
  ExistingIdx: Integer;
begin
  if not Assigned(FJobs) then
    Exit;
  if not (FJobs.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack]) then
    Exit;
  DestURI := JobConfirmDestUri(FJobs.Kind, AFields.DestPath, FJobs.State.DestDirURI);
  ExistingIdx := AFields.ExistingIdx;
  if ExistingIdx < 0 then
    ExistingIdx := 0;
  ExcludeMask := AFields.ExcludeMask;
  if not AFields.UseExclude then
    ExcludeMask := '';
  FJobs.ApplyCopyMoveOptions(DestURI, JobOverwriteModeFromIndex(ExistingIdx),
    AFields.PreserveTs, AFields.OnlyNewer, AFields.FollowSymlinks,
    JobRetryLimitFromIndex(AFields.RetryIdx), ExcludeMask);
end;

function TJobDialogController.TryHandleOverwriteRename(
  const AControlId: string): Boolean;
begin
  Result := False;
  if not DialogCmdIs(AControlId, cDlgCmdRename) then
    Exit;
  if not Assigned(FDialog) or not Assigned(FJobs) then
    Exit;
  Result := True;
  FDialog.Close;
  if Assigned(FOnSetKind) then
    FOnSetKind(hdkOverwriteRename);
  FDialog.Open(BuildInputDialog(T('ui.job.renameTitle', 'Rename'),
    T('ui.job.renameNewName', 'New name:'),
    ExtractFileName(FileUriToPath(FJobs.State.PendingDstURI))), FOnCommand);
end;

procedure TJobDialogController.HandleOverwriteRenameCmd(const AControlId: string;
  const AFields: TDialogCommandFields);
var
  Accepted: Boolean;
begin
  Accepted := not DialogCmdIsReject(AControlId);
  FDialog.Close;
  if not Assigned(FJobs) then
    Exit;
  if Accepted then
    FJobs.ResolveOverwriteAsk(jcaRename, False, AFields.Name)
  else
    FJobs.ResolveOverwriteAsk(jcaCancel, False);
end;

procedure TJobDialogController.HandleOverwriteAskCmd(const AControlId: string;
  const AFields: TDialogCommandFields);
begin
  FDialog.Close;
  if Assigned(FJobs) then
    FJobs.ResolveOverwriteAsk(JobConflictActionFromCommand(AControlId),
      AFields.Remember);
end;

procedure TJobDialogController.HandleDeleteErrorCmd(const AControlId: string);
begin
  // Resolve before Close so Close>Notify never sees orphaned pjpDeleteAsk
  // (outside-click path would Cancel the whole multi-file job).
  if Assigned(FJobs) then
    FJobs.ResolveDeleteAsk(JobDeleteFailActionFromCommand(AControlId,
      FJobs.State.DeleteToRecycleBin));
  FDialog.Close;
end;

procedure TJobDialogController.HandleIOErrorCmd(const AControlId: string);
begin
  // Same ordering reason as hdkDeleteError above.
  if Assigned(FJobs) then
    FJobs.ResolveIOErrorAsk(JobIOErrorActionFromCommand(AControlId));
  FDialog.Close;
end;

procedure TJobDialogController.HandleJobConfirmCmd(const AControlId: string;
  const AFields: TDialogCommandFields);
begin
  if JobConfirmWantsBackground(AControlId) then
  begin
    ApplyJobConfirmOptions(AFields);
    if Assigned(FJobs) then
    begin
      FJobs.ConfirmJob;
      FJobs.BackgroundJob;
    end;
    FDialog.Close;
  end
  else if DialogCmdIsAccept(AControlId) then
  begin
    ApplyJobConfirmOptions(AFields);
    // Arm Running before Close so Close>Notify never sees unprotected
    // pjpConfirm (outside-click cancel). Item work is ForceQueued inside
    // ConfirmJob; overwrite Ask opens later on that tick if needed.
    if Assigned(FJobs) then
      FJobs.ConfirmJob;
    FDialog.Close;
  end
  else
  begin
    FDialog.Close;
    if Assigned(FJobs) then
      FJobs.CloseJobUi;
  end;
end;

procedure TJobDialogController.HandleJobListCmd(const AControlId: string);
begin
  if DialogCmdIs(AControlId, cDlgCmdForeground) or DialogCmdIsOk(AControlId) then
  begin
    if Assigned(FJobs) and Assigned(FDialog) then
      FJobs.ForegroundJobByIndex(FDialog.GetListSelectedIndex('jobs'));
  end
  else if DialogCmdIs(AControlId, cDlgCmdCancelJob) then
  begin
    if Assigned(FJobs) and Assigned(FDialog) then
      FJobs.CancelJobByIndex(FDialog.GetListSelectedIndex('jobs'));
  end
  else if DialogCmdIs(AControlId, cDlgCmdCancelAll) then
  begin
    if Assigned(FJobs) then
      FJobs.CancelAll;
  end;
  FDialog.Close;
end;

procedure TJobDialogController.HandleJobProgressCmd(const AControlId: string);
begin
  if JobConfirmWantsBackground(AControlId) then
  begin
    if Assigned(FJobs) then
      FJobs.BackgroundJob;
    FDialog.Close;
  end
  else if Assigned(FJobs) and (FJobs.Phase = pjpError) then
  begin
    FJobs.CloseJobUi;
    FDialog.Close;
  end
  else
  begin
    if Assigned(FJobs) then
      FJobs.RequestCancel;
    if DialogCmdIsAccept(AControlId) then
      FDialog.Close;
  end;
end;

function TJobDialogController.DispatchCommand(AKind: THostDialogKind;
  const AControlId: string; const AFields: TDialogCommandFields): Boolean;
begin
  Result := True;
  case AKind of
    hdkOverwriteRename:
      HandleOverwriteRenameCmd(AControlId, AFields);
    hdkOverwriteAsk:
      begin
        if not Assigned(FJobs) then
        begin
          FDialog.Close;
          Exit(False);
        end;
        HandleOverwriteAskCmd(AControlId, AFields);
      end;
    hdkDeleteError:
      HandleDeleteErrorCmd(AControlId);
    hdkIOError:
      HandleIOErrorCmd(AControlId);
    hdkJobConfirm:
      HandleJobConfirmCmd(AControlId, AFields);
    hdkJobList:
      HandleJobListCmd(AControlId);
    hdkJobProgress:
      HandleJobProgressCmd(AControlId);
  else
    Result := False;
  end;
end;

end.
