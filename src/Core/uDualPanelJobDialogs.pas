unit uDualPanelJobDialogs;

{ Job confirm / overwrite / delete-error dialog dispatch. Extracted from
  TDualPanelWindow so ConfirmJob / VFS transfer stay on TPanelJobController. }

interface

uses
  System.SysUtils,
  uDialogHost, uDialogTypes, uDualPanelUiTypes, uDualPanelJobs,
  uDualPanelJobList, uDualPanelJobRules, uVfsTypes;

const
  /// <summary>Prefix of the plugin secret key that asks for encrypted file names
  /// in a 7z archive about to be created (the rest of the key is its path).</summary>
  cSevenZipHeaderKeyPrefix = 'header-encryption:';
  /// <summary>Prefix of the plugin secret key whose value is the compression
  /// level (0..9) of a 7z archive about to be written (the rest of the key is
  /// its path).</summary>
  cSevenZipLevelKeyPrefix = 'compression-level:';
  cPackTypeZip = 0;
  cPackType7z = 1;

type
  TJobKindSetter = reference to procedure(AKind: THostDialogKind);
  /// <summary>Hands the password, the encrypted-names choice and the compression
  /// level (7-Zip -mx, 0..9) of a 7z archive that a Pack job is about to write
  /// to the plugin that writes it; False when the plugin did not take them, so
  /// the archive must not be written.</summary>
  TPackSecurityEvent = reference to function(const AArchivePath, APassword: string;
    AEncryptNames: Boolean; ALevel: Integer): Boolean;
  TJobRejectEvent = reference to procedure(const ATitle, AMessage: string);

  TJobDialogController = class
  private
    FDialog: TDialogHost;
    FJobs: TPanelJobList;
    FOnCommand: TDialogCommandEvent;
    FOnSetKind: TJobKindSetter;
    FOnPackSecurity: TPackSecurityEvent;
    FOnReject: TJobRejectEvent;
    FPackInitialType: Integer;
    FLastPackType: Integer;
    function ApplyJobConfirmOptions(const AFields: TDialogCommandFields): Boolean;
    procedure RejectJob(const ATitle, AMessage: string);
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
    /// <summary>The archive type the Pack dialog was opened with. The dialog
    /// has no change notification, so a differing selection on confirm means
    /// the user picked a type, and it then overrides the extension typed in the
    /// name field.</summary>
    property PackInitialType: Integer read FPackInitialType write FPackInitialType;
    /// <summary>The archive type chosen in the last confirmed Pack dialog; the
    /// next Pack dialog starts with it.</summary>
    property LastPackType: Integer read FLastPackType;
    property OnPackSecurity: TPackSecurityEvent read FOnPackSecurity write FOnPackSecurity;
    property OnReject: TJobRejectEvent read FOnReject write FOnReject;
    function DispatchCommand(AKind: THostDialogKind; const AControlId: string;
      const AFields: TDialogCommandFields): Boolean;
  end;

function JobOverwriteModeFromIndex(AIdx: Integer): TJobOverwriteMode;
function JobRetryLimitFromIndex(AIdx: Integer): Integer;
/// <summary>For Pack, ATypeIdx is the archive type picked in the dialog and
/// AInitialTypeIdx the one it was opened with: a changed pick replaces the
/// extension of the typed name, otherwise a typed .zip or .7z decides and a
/// name without one gets the picked type's extension. A negative ATypeIdx
/// leaves the type to the typed extension (.zip when there is none).</summary>
function JobConfirmDestUri(AKind: TPanelJobKind; const ADestPath,
  AFallbackUri: string; ATypeIdx: Integer = -1;
  AInitialTypeIdx: Integer = -1): string;
/// <summary>The extension (with the dot) of an archive type of the Pack dialog.</summary>
function JobPackArchiveExt(ATypeIdx: Integer): string;
/// <summary>The 7-Zip level (-mx) of an item of the Pack dialog's compression
/// list: Store, Fastest, Fast, Normal, Maximum, Ultra.</summary>
function JobPackLevelFromIndex(AIdx: Integer): Integer;
/// <summary>The archive type of a name by its extension, or of an existing
/// local file by its 7z signature; -1 when it is neither.</summary>
function JobPackTypeFromPath(const APath: string): Integer;
/// <summary>The destination as the Copy / Move / Pack dialog shows it: a
/// local path for a folder on disk, the URI itself for anything else (an
/// archive, tmp:///), so that JobConfirmDestUri reads it back unchanged.</summary>
function JobConfirmDestText(AKind: TPanelJobKind; const ADestDirURI: string): string;
function JobConflictActionFromCommand(const AControlId: string): TJobConflictAction;
function JobDeleteFailActionFromCommand(const AControlId: string;
  AToRecycleBin: Boolean): TJobDeleteFailAction;
function JobIOErrorActionFromCommand(const AControlId: string): TJobIOErrorAction;
function JobDestRejectedReason(AKind: TPanelJobKind; const ADestURI: string): string;
function JobDestFailTitle(AKind: TPanelJobKind): string;
/// <summary>The default archive name: the name of the folder the sources are in
/// ("archive" when that folder has no name), with the extension of ATypeIdx.</summary>
function SuggestPackArchiveName(const ASources: TArray<string>;
  ATypeIdx: Integer = cPackTypeZip): string;
function SourcesContainArchive(const ASources: TArray<string>): Boolean;
function UnpackSourcesAreValid(const ASources: TArray<string>;
  out AError: string): Boolean;
function BuildJobProgressDialog(const AJob: TPanelJobState): TDialogDeclaration;
/// <summary>Stop question for a running operation. "Continue" is the default
/// and the Esc target, so Esc and Enter keep the operation running.</summary>
function BuildStopConfirmDialog(const AQuestion: string): TDialogDeclaration;
procedure ApplyJobProgressToDecl(var ADecl: TDialogDeclaration;
  const AJob: TPanelJobState);
procedure ApplyJobProgressToDialog(ADialog: TDialogHost;
  const AJob: TPanelJobState);

implementation

uses
  System.IOUtils, uDialogResources, uStrings;

const
  cJobProgressInnerW = 72;
  cPackSecurityFailed = 'The 7z plugin did not accept the password';

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

function BuildStopConfirmDialog(const AQuestion: string): TDialogDeclaration;
begin
  RequireDialogResource(cResDialogStopConfirm, Result);
  Result.IsWarning := True;
  DialogSetLabelText(Result, 'question', AQuestion);
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

function JobPackArchiveExt(ATypeIdx: Integer): string;
begin
  if ATypeIdx = cPackType7z then
    Result := '.7z'
  else
    Result := '.zip';
end;

function JobPackLevelFromIndex(AIdx: Integer): Integer;
const
  Levels: array[0..5] of Integer = (0, 1, 3, 5, 7, 9);
begin
  if (AIdx < 0) or (AIdx > High(Levels)) then
    Result := 5
  else
    Result := Levels[AIdx];
end;

function JobPackTypeFromPath(const APath: string): Integer;
var
  Ext: string;
begin
  Ext := ExtractFileExt(APath);
  if SameText(Ext, '.zip') then
    Result := cPackTypeZip
  else if IsSevenZipArchivePath(APath) then
    Result := cPackType7z
  else
    Result := -1;
end;

function JobConfirmDestUri(AKind: TPanelJobKind; const ADestPath,
  AFallbackUri: string; ATypeIdx: Integer; AInitialTypeIdx: Integer): string;
var
  DestPath: string;
  NameType: Integer;
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
    NameType := JobPackTypeFromPath(DestPath);
    if ATypeIdx < 0 then
    begin
      if NameType < 0 then
        DestPath := DestPath + JobPackArchiveExt(cPackTypeZip);
    end
    else if (NameType < 0) or (ATypeIdx <> AInitialTypeIdx) then
    begin
      if NameType >= 0 then
        DestPath := ChangeFileExt(DestPath, '');
      DestPath := DestPath + JobPackArchiveExt(ATypeIdx);
    end;
  end;
  Result := PathToFileUri(ExcludeTrailingPathDelimiter(DestPath));
end;

function JobConfirmDestText(AKind: TPanelJobKind; const ADestDirURI: string): string;
begin
  // file:///C:/a.zip!/ maps to a path on disk only by dropping the archive
  // marker, which would turn the archive into a folder.
  if HasArchiveChain(ADestDirURI) then
    Exit(ADestDirURI);
  Result := FileUriToPath(ADestDirURI);
  if Result = '' then
    Exit(ADestDirURI);
  if AKind <> pjkPack then
    Result := IncludeTrailingPathDelimiter(Result);
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
  else if DialogCmdIs(AControlId, cDlgCmdElevate) then
    Result := jdaElevate
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
  else if DialogCmdIs(AControlId, cDlgCmdElevate) then
    Result := jioElevate
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

// A .zip file on disk opened one level deep: the built-in ZIP layer adds and
// removes entries there (not inside a nested archive).
function DestIsOuterZip(const ADestURI: string): Boolean;
var
  Base: string;
  Segs: TArray<string>;
begin
  Result := False;
  if not HasArchiveChain(ADestURI) then
    Exit;
  if Length(ADestURI.Split(['!/'])) <> 2 then
    Exit;
  if not SplitArchiveUri(ADestURI, Base, Segs) then
    Exit;
  Result := Base.StartsWith('file:', True) and
    IsZipFileName(SafeFileName(FileUriToPath(Base)));
end;

function JobDestRejectedReason(AKind: TPanelJobKind; const ADestURI: string): string;
begin
  Result := '';
  case AKind of
    pjkDelete: ;
    pjkCopy:
      if (not IsSevenZipUri(ADestURI)) and (not DestIsOuterZip(ADestURI)) and
         DestIsArchiveOrVirtual(ADestURI) then
        Result := 'Opposite panel must be a local folder';
    pjkMove:
      if (not DestIsOuterZip(ADestURI)) and DestIsArchiveOrVirtual(ADestURI) then
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

function SuggestPackArchiveName(const ASources: TArray<string>;
  ATypeIdx: Integer): string;
var
  Path, Dir, Name: string;
begin
  Name := '';
  if Length(ASources) > 0 then
  begin
    Path := FileUriToPath(ASources[0]);
    if Path <> '' then
    begin
      Dir := ExtractFileDir(ExcludeTrailingPathDelimiter(Path));
      Name := ExtractFileName(Dir);
      if Name = '' then
        // A drive root has no folder name: use the drive letter.
        Name := StringReplace(StringReplace(Dir, ':', '', [rfReplaceAll]),
          PathDelim, '', [rfReplaceAll]);
    end;
  end;
  if Name = '' then
    Name := 'archive';
  Result := Name + JobPackArchiveExt(ATypeIdx);
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

function TJobDialogController.ApplyJobConfirmOptions(
  const AFields: TDialogCommandFields): Boolean;
var
  DestURI, ExcludeMask, ArchivePath: string;
  ExistingIdx: Integer;
begin
  Result := True;
  if not Assigned(FJobs) then
    Exit;
  if not (FJobs.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack]) then
    Exit;
  if FJobs.Kind = pjkPack then
    DestURI := JobConfirmDestUri(FJobs.Kind, AFields.DestPath, FJobs.State.DestDirURI,
      AFields.PackTypeIdx, FPackInitialType)
  else
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
  if FJobs.Kind <> pjkPack then
    Exit;
  ArchivePath := FileUriToPath(DestURI);
  if ArchivePath = '' then
    Exit;
  FLastPackType := JobPackTypeFromPath(ArchivePath);
  if (FLastPackType = cPackType7z) and Assigned(FOnPackSecurity) then
    Result := FOnPackSecurity(ArchivePath, AFields.Password, AFields.EncryptNames,
      JobPackLevelFromIndex(AFields.PackLevelIdx));
end;

// The confirm dialog is closed and the job dropped before the message opens, so
// the message does not land on a dialog that is about to close.
procedure TJobDialogController.RejectJob(const ATitle, AMessage: string);
begin
  FDialog.Close;
  if Assigned(FJobs) then
    FJobs.CloseJobUi;
  if Assigned(FOnReject) then
    FOnReject(ATitle, AMessage);
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
    if not ApplyJobConfirmOptions(AFields) then
    begin
      RejectJob(JobDestFailTitle(pjkPack), cPackSecurityFailed);
      Exit;
    end;
    if Assigned(FJobs) then
    begin
      FJobs.ConfirmJob;
      FJobs.BackgroundJob;
    end;
    FDialog.Close;
  end
  else if DialogCmdIsAccept(AControlId) then
  begin
    if not ApplyJobConfirmOptions(AFields) then
    begin
      RejectJob(JobDestFailTitle(pjkPack), cPackSecurityFailed);
      Exit;
    end;
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
