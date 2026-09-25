unit uDualPanelJobList;

{ Multi-job facade: file:// can run in parallel; zip/7z/sftp-authority and
  overlapping URIs queue. Dual Panel talks to this the way it used to talk
  to a single TPanelJobController. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelJobs, uDualPanelJobRules, uVfsTypes;

type
  TPanelJobList = class
  private
    FItems: TObjectList<TPanelJobController>;
    FTheme: IThemeRenderer;
    FVfs: IVirtualFileSystem;
    FOnInvalidate: TProc;
    FOnOpenConfirmDialog: TJobConfirmDialogEvent;
    FOnOverwriteAsk: TJobOverwriteAskEvent;
    FOnDeleteAsk: TJobDeleteAskEvent;
    FOnIOErrorAsk: TJobIOErrorAskEvent;
    FOnJobFinished: TJobFinishedEvent;
    FOnReloadPanels: TJobReloadPanelsEvent;
    FOnClearSelection: TJobClearSelectionEvent;
    FOnAfterClose: TProc;
    FOnBeforeExecute: TProc;
    FNextId: Integer;
    FAskJobId: Integer;
    FPruneQueued: Boolean;
    function BusyCount: Integer;
    function JobById(AId: Integer): TPanelJobController;
    function ActiveJob: TPanelJobController;
    function OverlayJob: TPanelJobController;
    function ConfirmingJob: TPanelJobController;
    function AskJob: TPanelJobController;
    function FirstWaitingAsk: TPanelJobController;
    function SpawnJob: TPanelJobController;
    procedure HookJob(AJob: TPanelJobController);
    procedure OnJobOverwriteAsk(AJob: TPanelJobController; const APath, ANewLine,
      AExistingLine: string);
    procedure OnJobDeleteAsk(AJob: TPanelJobController; const APath, AHeadline,
      AQuestion, AErrorLine: string; AOfferPermanent: Boolean);
    procedure OnJobIOErrorAsk(AJob: TPanelJobController; const AHeadline, APath,
      AErrorLine: string);
    procedure OnJobFinished(AJob: TPanelJobController; ASuccess: Boolean);
    procedure OnJobReload(AJob: TPanelJobController; const AOriginSrc,
      AOriginDst: string);
    procedure OnJobClearSel(AJob: TPanelJobController; const AOriginSrc: string);
    procedure OnJobAfterClose(AJob: TPanelJobController);
    procedure QueuePruneIdle;
    procedure PruneIdleJobs;
    function ConflictsWithRunning(AJob: TPanelJobController): Boolean;
    procedure TryStartQueued;
    function GetPhase: TPanelJobPhase;
    function GetKind: TPanelJobKind;
    function GetState: TPanelJobState;
    function GetBounds: TRectI;
    function GetActive: Boolean;
  public
    constructor Create(const ATheme: IThemeRenderer; const AVfs: IVirtualFileSystem;
      const AOnInvalidate: TProc; const AOnOpenConfirmDialog: TJobConfirmDialogEvent;
      const AOnOverwriteAsk: TJobOverwriteAskEvent;
      const AOnDeleteAsk: TJobDeleteAskEvent;
      const AOnIOErrorAsk: TJobIOErrorAskEvent;
      const AOnJobFinished: TJobFinishedEvent;
      const AOnReloadPanels: TJobReloadPanelsEvent;
      const AOnClearSelection: TJobClearSelectionEvent;
      const AOnAfterClose: TProc = nil;
      const AOnBeforeExecute: TProc = nil);
    destructor Destroy; override;
    procedure SetTheme(const ATheme: IThemeRenderer);
    procedure SetVfs(const AVfs: IVirtualFileSystem);
    function CanStartAnother: Boolean;
    function BlocksNewOperation: Boolean;
    function OwnsInput: Boolean;
    function ShowsOverlay: Boolean;
    function HasBusyJob: Boolean;
    function HasAsk: Boolean;
    function Count: Integer;
    function FormatStatus: string;
    function ListLines: TArray<string>;
    function JobIdAt(AIndex: Integer): Integer;
    procedure TryOpenNextAsk;
    procedure ReplayCurrentAsk;
    procedure CloseJobUi;
    procedure CloseAll;
    procedure LayoutJobPopup(const AClientWidth, AClientHeight: Integer);
    procedure DrawJobPopup(const AGrid: TTerminalGrid;
      AClientWidth, AClientHeight: Integer);
    procedure BeginJob(const ASources: TArray<string>; const ADestDirURI: string;
      AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean = True);
    procedure BeginJobPairs(const ASources, ADestURIs: TArray<string>;
      AKind: TPanelJobKind);
    procedure ApplyCopyMoveOptions(const ADestDirURI: string;
      AOverwriteMode: TJobOverwriteMode; APreserveTimestamps: Boolean;
      AOnlyNewer: Boolean = False; AFollowSymlinks: Boolean = False;
      ARetryLimit: Integer = 0; const AExcludeMask: string = '');
    procedure ConfirmJob;
    procedure BackgroundJob;
    procedure ForegroundJob;
    procedure ForegroundJobByIndex(AIndex: Integer);
    function IsForegroundRunning: Boolean;
    function TryProgressDialogState(out AJob: TPanelJobState): Boolean;
    procedure ResolveOverwriteAsk(AAction: TJobConflictAction; ARemember: Boolean;
      const ARenameName: string = '');
    procedure ResolveDeleteAsk(AAction: TJobDeleteFailAction);
    procedure ResolveIOErrorAsk(AAction: TJobIOErrorAction);
    procedure RequestCancel;
    procedure CancelJobByIndex(AIndex: Integer);
    procedure CancelAll;
    function HandleJobInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function Title: string;
    property Phase: TPanelJobPhase read GetPhase;
    property Kind: TPanelJobKind read GetKind;
    property State: TPanelJobState read GetState;
    property Bounds: TRectI read GetBounds;
    property Active: Boolean read GetActive;
    property AskJobId: Integer read FAskJobId;
  end;

implementation

constructor TPanelJobList.Create(const ATheme: IThemeRenderer;
  const AVfs: IVirtualFileSystem; const AOnInvalidate: TProc;
  const AOnOpenConfirmDialog: TJobConfirmDialogEvent;
  const AOnOverwriteAsk: TJobOverwriteAskEvent;
  const AOnDeleteAsk: TJobDeleteAskEvent;
  const AOnIOErrorAsk: TJobIOErrorAskEvent;
  const AOnJobFinished: TJobFinishedEvent;
  const AOnReloadPanels: TJobReloadPanelsEvent;
  const AOnClearSelection: TJobClearSelectionEvent;
  const AOnAfterClose: TProc;
  const AOnBeforeExecute: TProc);
begin
  inherited Create;
  FTheme := ATheme;
  FVfs := AVfs;
  FOnInvalidate := AOnInvalidate;
  FOnOpenConfirmDialog := AOnOpenConfirmDialog;
  FOnOverwriteAsk := AOnOverwriteAsk;
  FOnDeleteAsk := AOnDeleteAsk;
  FOnIOErrorAsk := AOnIOErrorAsk;
  FOnJobFinished := AOnJobFinished;
  FOnReloadPanels := AOnReloadPanels;
  FOnClearSelection := AOnClearSelection;
  FOnAfterClose := AOnAfterClose;
  FOnBeforeExecute := AOnBeforeExecute;
  FItems := TObjectList<TPanelJobController>.Create(True);
  FNextId := 0;
  FAskJobId := 0;
end;

destructor TPanelJobList.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TPanelJobList.SetTheme(const ATheme: IThemeRenderer);
var
  Job: TPanelJobController;
begin
  FTheme := ATheme;
  for Job in FItems do
    Job.SetTheme(ATheme);
end;

procedure TPanelJobList.SetVfs(const AVfs: IVirtualFileSystem);
var
  Job: TPanelJobController;
begin
  FVfs := AVfs;
  for Job in FItems do
    Job.SetVfs(AVfs);
end;

function TPanelJobList.BusyCount: Integer;
var
  Job: TPanelJobController;
begin
  Result := 0;
  for Job in FItems do
    if JobIsBusy(Job.State) then
      Inc(Result);
end;

function TPanelJobList.CanStartAnother: Boolean;
begin
  Result := CanStartAnotherJob(BusyCount);
end;

function TPanelJobList.BlocksNewOperation: Boolean;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobBlocksNewOperation(Job.State) then
      Exit(True);
  Result := False;
end;

function TPanelJobList.OwnsInput: Boolean;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobOwnsInput(Job.State) then
      Exit(True);
  Result := False;
end;

function TPanelJobList.ShowsOverlay: Boolean;
begin
  Result := OverlayJob <> nil;
end;

function TPanelJobList.HasBusyJob: Boolean;
begin
  Result := BusyCount > 0;
end;

function TPanelJobList.HasAsk: Boolean;
begin
  Result := FirstWaitingAsk <> nil;
end;

function TPanelJobList.Count: Integer;
begin
  Result := BusyCount;
end;

function TPanelJobList.JobById(AId: Integer): TPanelJobController;
var
  Job: TPanelJobController;
begin
  if AId = 0 then
    Exit(nil);
  for Job in FItems do
    if Job.State.Id = AId then
      Exit(Job);
  Result := nil;
end;

function TPanelJobList.ConfirmingJob: TPanelJobController;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if Job.Phase = pjpConfirm then
      Exit(Job);
  Result := nil;
end;

function TPanelJobList.AskJob: TPanelJobController;
begin
  Result := JobById(FAskJobId);
  if (Result <> nil) and not JobIsAskPhase(Result.Phase) then
    Result := nil;
end;

function TPanelJobList.FirstWaitingAsk: TPanelJobController;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobIsAskPhase(Job.Phase) then
      Exit(Job);
  Result := nil;
end;

function TPanelJobList.OverlayJob: TPanelJobController;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobShowsOverlay(Job.State) then
      Exit(Job);
  Result := nil;
end;

function TPanelJobList.ActiveJob: TPanelJobController;
var
  Job: TPanelJobController;
begin
  Result := AskJob;
  if Result <> nil then
    Exit;
  Result := ConfirmingJob;
  if Result <> nil then
    Exit;
  Result := OverlayJob;
  if Result <> nil then
    Exit;
  for Job in FItems do
    if Job.Phase = pjpRunning then
      Exit(Job);
  for Job in FItems do
    if Job.Phase = pjpQueued then
      Exit(Job);
  for Job in FItems do
    if JobIsBusy(Job.State) then
      Exit(Job);
  Result := nil;
end;

function TPanelJobList.GetPhase: TPanelJobPhase;
var
  Job: TPanelJobController;
begin
  Job := ActiveJob;
  if Job = nil then
    Result := pjpNone
  else
    Result := Job.Phase;
end;

function TPanelJobList.GetKind: TPanelJobKind;
var
  Job: TPanelJobController;
begin
  Job := ActiveJob;
  if Job = nil then
    Result := pjkNone
  else
    Result := Job.Kind;
end;

function TPanelJobList.GetState: TPanelJobState;
var
  Job: TPanelJobController;
begin
  Job := ActiveJob;
  if Job = nil then
    Result := Default(TPanelJobState)
  else
    Result := Job.State;
end;

function TPanelJobList.GetBounds: TRectI;
var
  Job: TPanelJobController;
begin
  Job := OverlayJob;
  if Job = nil then
    Result := Default(TRectI)
  else
    Result := Job.Bounds;
end;

function TPanelJobList.GetActive: Boolean;
begin
  Result := HasBusyJob;
end;

function TPanelJobList.Title: string;
var
  Job: TPanelJobController;
begin
  Job := ActiveJob;
  if Job = nil then
    Result := 'Job'
  else
    Result := Job.Title;
end;

function TPanelJobList.FormatStatus: string;
var
  Lead: TPanelJobController;
begin
  Lead := ActiveJob;
  if Lead = nil then
    Exit('');
  Result := FormatJobListStatus(Count, Lead.State, HasAsk);
end;

function TPanelJobList.ListLines: TArray<string>;
var
  Job: TPanelJobController;
  N: Integer;
begin
  SetLength(Result, FItems.Count);
  N := 0;
  for Job in FItems do
    if JobIsBusy(Job.State) then
    begin
      Result[N] := FormatJobListLine(Job.State);
      Inc(N);
    end;
  SetLength(Result, N);
end;

function TPanelJobList.JobIdAt(AIndex: Integer): Integer;
var
  Job: TPanelJobController;
  N: Integer;
begin
  Result := 0;
  N := 0;
  for Job in FItems do
    if JobIsBusy(Job.State) then
    begin
      if N = AIndex then
        Exit(Job.State.Id);
      Inc(N);
    end;
end;

function TPanelJobList.SpawnJob: TPanelJobController;
var
  Job: TPanelJobController;
begin
  Job := nil;
  Job := TPanelJobController.Create(FTheme, FVfs, FOnInvalidate,
    FOnOpenConfirmDialog,
    procedure(const APath, ANewLine, AExistingLine: string)
    begin
      OnJobOverwriteAsk(Job, APath, ANewLine, AExistingLine);
    end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean)
    begin
      OnJobDeleteAsk(Job, APath, AHeadline, AQuestion, AErrorLine,
        AOfferPermanent);
    end,
    procedure(const AHeadline, APath, AErrorLine: string)
    begin
      OnJobIOErrorAsk(Job, AHeadline, APath, AErrorLine);
    end,
    procedure(ASuccess: Boolean)
    begin
      OnJobFinished(Job, ASuccess);
    end,
    procedure(const AOriginSrc, AOriginDst: string)
    begin
      OnJobReload(Job, AOriginSrc, AOriginDst);
    end,
    procedure(const AOriginSrc: string)
    begin
      OnJobClearSel(Job, AOriginSrc);
    end,
    procedure
    begin
      OnJobAfterClose(Job);
    end,
    FOnBeforeExecute);
  Result := Job;
end;

procedure TPanelJobList.HookJob(AJob: TPanelJobController);
begin
  Inc(FNextId);
  AJob.BindIdentity(FNextId);
  FItems.Add(AJob);
end;

function TPanelJobList.ConflictsWithRunning(AJob: TPanelJobController): Boolean;
var
  Other: TPanelJobController;
begin
  Result := False;
  if AJob = nil then
    Exit;
  for Other in FItems do
    if (Other <> AJob) and (Other.Phase in [pjpRunning, pjpOverwriteAsk,
      pjpDeleteAsk, pjpIOErrorAsk, pjpError]) then
      if not CanRunParallel(AJob.State, Other.State) then
        Exit(True);
end;

procedure TPanelJobList.TryStartQueued;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if Job.Phase = pjpQueued then
      if not ConflictsWithRunning(Job) then
      begin
        Job.StartIfQueued;
        Exit;
      end;
end;

procedure TPanelJobList.OnJobOverwriteAsk(AJob: TPanelJobController;
  const APath, ANewLine, AExistingLine: string);
begin
  if (FAskJobId <> 0) and (FAskJobId <> AJob.State.Id) then
    Exit;
  FAskJobId := AJob.State.Id;
  if Assigned(FOnOverwriteAsk) then
    FOnOverwriteAsk(APath, ANewLine, AExistingLine);
end;

procedure TPanelJobList.OnJobDeleteAsk(AJob: TPanelJobController;
  const APath, AHeadline, AQuestion, AErrorLine: string;
  AOfferPermanent: Boolean);
begin
  if (FAskJobId <> 0) and (FAskJobId <> AJob.State.Id) then
    Exit;
  FAskJobId := AJob.State.Id;
  if Assigned(FOnDeleteAsk) then
    FOnDeleteAsk(APath, AHeadline, AQuestion, AErrorLine, AOfferPermanent);
end;

procedure TPanelJobList.OnJobIOErrorAsk(AJob: TPanelJobController;
  const AHeadline, APath, AErrorLine: string);
begin
  if (FAskJobId <> 0) and (FAskJobId <> AJob.State.Id) then
    Exit;
  FAskJobId := AJob.State.Id;
  if Assigned(FOnIOErrorAsk) then
    FOnIOErrorAsk(AHeadline, APath, AErrorLine);
end;

procedure TPanelJobList.OnJobFinished(AJob: TPanelJobController;
  ASuccess: Boolean);
begin
  if Assigned(AJob) and (FAskJobId = AJob.State.Id) then
    FAskJobId := 0;
  if Assigned(FOnJobFinished) then
    FOnJobFinished(ASuccess);
  TryStartQueued;
  TryOpenNextAsk;
end;

procedure TPanelJobList.OnJobReload(AJob: TPanelJobController;
  const AOriginSrc, AOriginDst: string);
begin
  if Assigned(FOnReloadPanels) then
    FOnReloadPanels(AOriginSrc, AOriginDst);
end;

procedure TPanelJobList.OnJobClearSel(AJob: TPanelJobController;
  const AOriginSrc: string);
begin
  if Assigned(FOnClearSelection) then
    FOnClearSelection(AOriginSrc);
end;

procedure TPanelJobList.OnJobAfterClose(AJob: TPanelJobController);
begin
  if Assigned(AJob) and (FAskJobId = AJob.State.Id) then
    FAskJobId := 0;
  QueuePruneIdle;
  if Assigned(FOnAfterClose) then
    FOnAfterClose;
  TryStartQueued;
  TryOpenNextAsk;
end;

procedure TPanelJobList.QueuePruneIdle;
begin
  if FPruneQueued then
    Exit;
  FPruneQueued := True;
  // Queue on the main thread runs the proc before it returns (ForceQueue is
  // what actually defers). Prune frees controllers whose phase is already
  // pjpNone, and CloseJobUi reaches this from inside FinishJob — an immediate
  // free leaves FinishJob calling FOnJobFinished on a dead object
  // (read of FFFFFFFFFFFFFFFF).
  TThread.ForceQueue(nil,
    procedure
    begin
      FPruneQueued := False;
      PruneIdleJobs;
    end);
end;

procedure TPanelJobList.PruneIdleJobs;
var
  I: Integer;
begin
  if FItems = nil then
    Exit;
  for I := FItems.Count - 1 downto 0 do
    if FItems[I].Phase = pjpNone then
      FItems.Delete(I);
end;

procedure TPanelJobList.ReplayCurrentAsk;
var
  Job: TPanelJobController;
  St: TPanelJobState;
begin
  Job := AskJob;
  if Job = nil then
    Job := FirstWaitingAsk;
  if Job = nil then
    Exit;
  FAskJobId := Job.State.Id;
  St := Job.State;
  case St.Phase of
    pjpOverwriteAsk:
      if Assigned(FOnOverwriteAsk) then
        FOnOverwriteAsk(St.AskPath, St.AskNewLine, St.AskExistingLine);
    pjpDeleteAsk:
      if Assigned(FOnDeleteAsk) then
        FOnDeleteAsk(St.AskPath, St.AskHeadline, St.AskQuestion,
          St.AskErrorLine, St.AskOfferPermanent);
    pjpIOErrorAsk:
      if Assigned(FOnIOErrorAsk) then
        FOnIOErrorAsk(St.AskHeadline, St.AskPath, St.AskErrorLine);
  end;
end;

procedure TPanelJobList.TryOpenNextAsk;
var
  Job: TPanelJobController;
  St: TPanelJobState;
begin
  if FAskJobId <> 0 then
  begin
    Job := JobById(FAskJobId);
    if (Job <> nil) and JobIsAskPhase(Job.Phase) then
      Exit;
    FAskJobId := 0;
  end;
  Job := FirstWaitingAsk;
  if Job = nil then
    Exit;
  FAskJobId := Job.State.Id;
  St := Job.State;
  case St.Phase of
    pjpOverwriteAsk:
      if Assigned(FOnOverwriteAsk) then
        FOnOverwriteAsk(St.AskPath, St.AskNewLine, St.AskExistingLine);
    pjpDeleteAsk:
      if Assigned(FOnDeleteAsk) then
        FOnDeleteAsk(St.AskPath, St.AskHeadline, St.AskQuestion,
          St.AskErrorLine, St.AskOfferPermanent);
    pjpIOErrorAsk:
      if Assigned(FOnIOErrorAsk) then
        FOnIOErrorAsk(St.AskHeadline, St.AskPath, St.AskErrorLine);
  end;
end;

procedure TPanelJobList.BeginJob(const ASources: TArray<string>;
  const ADestDirURI: string; AKind: TPanelJobKind;
  ADeleteToRecycleBin: Boolean);
var
  Job: TPanelJobController;
begin
  if not CanStartAnother then
    Exit;
  Job := SpawnJob;
  HookJob(Job);
  Job.BeginJob(ASources, ADestDirURI, AKind, ADeleteToRecycleBin);
  if Job.Phase = pjpNone then
    QueuePruneIdle;
end;

procedure TPanelJobList.BeginJobPairs(const ASources, ADestURIs: TArray<string>;
  AKind: TPanelJobKind);
var
  Job: TPanelJobController;
begin
  if not CanStartAnother then
    Exit;
  Job := SpawnJob;
  HookJob(Job);
  Job.BeginJobPairs(ASources, ADestURIs, AKind, False);
  if Job.Phase = pjpNone then
    QueuePruneIdle
  else if ConflictsWithRunning(Job) then
    { stay queued }
  else
    Job.StartIfQueued;
end;

procedure TPanelJobList.ApplyCopyMoveOptions(const ADestDirURI: string;
  AOverwriteMode: TJobOverwriteMode; APreserveTimestamps: Boolean;
  AOnlyNewer: Boolean; AFollowSymlinks: Boolean; ARetryLimit: Integer;
  const AExcludeMask: string);
var
  Job: TPanelJobController;
begin
  Job := ConfirmingJob;
  if Job = nil then
    Job := ActiveJob;
  if Job <> nil then
    Job.ApplyCopyMoveOptions(ADestDirURI, AOverwriteMode, APreserveTimestamps,
      AOnlyNewer, AFollowSymlinks, ARetryLimit, AExcludeMask);
end;

procedure TPanelJobList.ConfirmJob;
var
  Job: TPanelJobController;
begin
  Job := ConfirmingJob;
  if Job = nil then
    Exit;
  if ConflictsWithRunning(Job) then
    Job.QueueAfterConfirm
  else
    Job.ConfirmJob;
end;

procedure TPanelJobList.BackgroundJob;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobWantsProgressDialog(Job.State) then
    begin
      Job.BackgroundJob;
      Exit;
    end;
  Job := ActiveJob;
  if Job <> nil then
    Job.BackgroundJob;
end;

procedure TPanelJobList.ForegroundJob;
var
  Job: TPanelJobController;
begin
  Job := ActiveJob;
  if Job <> nil then
    Job.ForegroundJob;
end;

procedure TPanelJobList.ForegroundJobByIndex(AIndex: Integer);
var
  Job: TPanelJobController;
begin
  Job := JobById(JobIdAt(AIndex));
  if Job <> nil then
    Job.ForegroundJob;
end;

function TPanelJobList.IsForegroundRunning: Boolean;
var
  Job: TPanelJobState;
begin
  Result := TryProgressDialogState(Job);
end;

function TPanelJobList.TryProgressDialogState(out AJob: TPanelJobState): Boolean;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
    if JobWantsProgressDialog(Job.State) then
    begin
      AJob := Job.State;
      Exit(True);
    end;
  AJob := Default(TPanelJobState);
  Result := False;
end;

procedure TPanelJobList.ResolveOverwriteAsk(AAction: TJobConflictAction;
  ARemember: Boolean; const ARenameName: string);
var
  Job: TPanelJobController;
begin
  Job := AskJob;
  if Job = nil then
    Job := ActiveJob;
  FAskJobId := 0;
  if Job <> nil then
    Job.ResolveOverwriteAsk(AAction, ARemember, ARenameName);
  TryOpenNextAsk;
end;

procedure TPanelJobList.ResolveDeleteAsk(AAction: TJobDeleteFailAction);
var
  Job: TPanelJobController;
begin
  Job := AskJob;
  if Job = nil then
    Job := ActiveJob;
  FAskJobId := 0;
  if Job <> nil then
    Job.ResolveDeleteAsk(AAction);
  TryOpenNextAsk;
end;

procedure TPanelJobList.ResolveIOErrorAsk(AAction: TJobIOErrorAction);
var
  Job: TPanelJobController;
begin
  Job := AskJob;
  if Job = nil then
    Job := ActiveJob;
  FAskJobId := 0;
  if Job <> nil then
    Job.ResolveIOErrorAsk(AAction);
  TryOpenNextAsk;
end;

procedure TPanelJobList.RequestCancel;
var
  Job: TPanelJobController;
begin
  Job := OverlayJob;
  if Job = nil then
    Job := AskJob;
  if Job = nil then
    Job := ActiveJob;
  if Job <> nil then
    Job.RequestCancel;
end;

procedure TPanelJobList.CancelJobByIndex(AIndex: Integer);
var
  Job: TPanelJobController;
begin
  Job := JobById(JobIdAt(AIndex));
  if Job = nil then
    Exit;
  Job.RequestCancel;
  if Job.Phase in [pjpConfirm, pjpQueued, pjpError] then
    Job.CloseJobUi;
end;

procedure TPanelJobList.CancelAll;
var
  Job: TPanelJobController;
begin
  for Job in FItems do
  begin
    Job.RequestCancel;
    if Job.Phase in [pjpConfirm, pjpQueued, pjpError] then
      Job.CloseJobUi;
  end;
end;

procedure TPanelJobList.CloseJobUi;
var
  Job: TPanelJobController;
begin
  Job := ConfirmingJob;
  if Job = nil then
    Job := OverlayJob;
  if Job = nil then
    Job := AskJob;
  if Job = nil then
    Job := ActiveJob;
  if Job <> nil then
    Job.CloseJobUi;
end;

procedure TPanelJobList.CloseAll;
var
  I: Integer;
begin
  for I := FItems.Count - 1 downto 0 do
    FItems[I].CloseJobUi;
  PruneIdleJobs;
end;

procedure TPanelJobList.LayoutJobPopup(const AClientWidth,
  AClientHeight: Integer);
var
  Job: TPanelJobController;
begin
  Job := OverlayJob;
  if Job <> nil then
    Job.LayoutJobPopup(AClientWidth, AClientHeight);
end;

procedure TPanelJobList.DrawJobPopup(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
var
  Job: TPanelJobController;
begin
  Job := OverlayJob;
  if Job <> nil then
    Job.DrawJobPopup(AGrid, AClientWidth, AClientHeight);
end;

function TPanelJobList.HandleJobInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
var
  Job: TPanelJobController;
begin
  Job := OverlayJob;
  if Job = nil then
    Job := AskJob;
  if Job = nil then
    Exit(False);
  Result := Job.HandleJobInput(AKey, AShift, AKeyChar);
end;

end.
