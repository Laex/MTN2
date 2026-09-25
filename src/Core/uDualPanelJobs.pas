unit uDualPanelJobs;

{ Copy / Move / Delete job overlay. Extracted from TDualPanelWindow. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.IOUtils,
  Winapi.Windows,
  uTerminalTypes, uThemeTypes, uDualPanelTypes, uDualPanelUiTypes,
  uDualPanelOverlays, uDualPanelJobRules, uVfsTypes, uFileFind, uJobPopupRenderer,
  uStrings;

type
  TJobConfirmDialogEvent = reference to procedure(const ATitle, AMessage: string);
  TJobOverwriteAskEvent = reference to procedure(const APath, ANewLine, AExistingLine: string);
  TJobDeleteAskEvent = reference to procedure(const APath, AHeadline, AQuestion,
    AErrorLine: string; AOfferPermanent: Boolean);
  TJobIOErrorAskEvent = reference to procedure(const AHeadline, APath,
    AErrorLine: string);
  TJobFinishedEvent = reference to procedure(ASuccess: Boolean);
  TJobReloadPanelsEvent = reference to procedure(const AOriginSrc,
    AOriginDst: string);
  TJobClearSelectionEvent = reference to procedure(const AOriginSrc: string);

  TPanelJobController = class
  private
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
    FJob: TPanelJobState;
    FAlive: Boolean;
    FLastProgressInvalidateTick: UInt64;
    FProgressInvalidateQueued: Boolean;
    FProgressInvalidateDirty: Boolean;
    /// <summary>Full source path of the file the last progress report was
    /// about — used to detect "file finished, next one started" transitions
    /// inside a recursive tree copy so FJob.FilesDone can count real files
    /// instead of top-level selected items.</summary>
    FLastItemSrcPath: string;
    FExcludeMasks: TArray<string>;
    FExcludeMasksReady: Boolean;
    function JobTitle: string;
    procedure ResetExcludeMasks;
    procedure HandleConfirmKeys(var AKey: Word; var AKeyChar: Char);
    procedure HandleRunningKeys(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char);
    procedure HandleAskEscapeKeys(var AKey: Word; var AKeyChar: Char;
      AOnEscape: TProc);
    procedure HandleErrorKeys(var AKey: Word; var AKeyChar: Char);
    procedure StartJobExecution;
    procedure RunJobItem;
    procedure ProbeJobItemAsync(const ASrcURI, ADstURI: string; AIndex: Integer;
      AKind: TPanelJobKind; AFollowSymlinks, AOnlyNewer, AOverwriteAsk: Boolean);
    function ProbeSkipReparse(AKind: TPanelJobKind; AFollowSymlinks: Boolean;
      const ASrcURI, ASrcPath: string): Boolean;
    function ProbeSkipNewer(AOnlyNewer, ASkipReparse: Boolean;
      const ASrcURI, ADstURI, ASrcPath, ADstPath: string): Boolean;
    procedure ProbeDestOverlap(ASkipReparse, ASkipNewer: Boolean;
      const ASrcURI, ADstURI, ASrcPath, ADstPath: string;
      out ADestExists, ABothDirs: Boolean);
    procedure ContinueJobItemAfterProbe(const ASrcURI, ADstURI: string;
      AIndex: Integer; AKind: TPanelJobKind; ASkipReparse, ASkipNewer,
      ADestExists: Boolean; ABothDirs: Boolean; const ANewLine: string = '';
      const AExistingLine: string = '');
    procedure StartTransferInvalidate(const ASrcURI, ADstURI: string;
      AIndex: Integer; AOverwrite, AAppend: Boolean);
    function TryContinueDirMerge(const ASrcURI, ADstURI: string; AIndex: Integer;
      AIsDirMerge: Boolean): Boolean;
    function TryContinueExistingDest(const ASrcURI, ADstURI: string;
      AIndex: Integer; AIsDirMerge: Boolean; const ANewLine,
      AExistingLine: string): Boolean;
    procedure NotifyProgressUi;
    procedure NoteItemProgress(ADone, ATotal: Int64; const ACurrentName: string;
      AItemDone: Int64 = 0; AItemTotal: Int64 = 0; const AItemSrcPath: string = '';
      const AItemDstPath: string = '');
    procedure BeginItemTotals(const ASrcURI, ADstURI: string);
    procedure CommitItemBytes;
    procedure ExecuteTransfer(const ASrcURI, ADstURI: string; AIndex: Integer;
      AOverwrite, AAppend: Boolean);
    procedure RunAppendCopyThread(const ASrcURI, ADstURI, ASrcPath, ADstPath: string;
      AIndex: Integer; const ACancel: IJobCancelToken);
    procedure AdvanceJobAfterItem(AIndex: Integer);
    procedure HandleTransferFailure(const ASrcURI, ADstURI: string; AIndex: Integer;
      AOverwrite, AAppend: Boolean; const AError: TVfsError);
    procedure FinishJob(ASuccess: Boolean; const AError: TVfsError);
    function JobItemExcluded(const AName: string): Boolean;
    function PathIsReparsePoint(const APath: string): Boolean;
    function FormatConflictFileLine(const ALabel, APath: string): string;
    procedure PromptOverwriteAsk(const ASrcURI, ADstURI: string; AIndex: Integer;
      const ANewLine: string = ''; const AExistingLine: string = '');
    procedure PromptDeleteAsk(const ASrcURI: string; const AError: TVfsError;
      AOfferPermanent: Boolean);
    function FormatJobErrorLine(const AError: TVfsError): string;
    procedure ExecuteDeleteItem(const ASrcURI: string; AIndex: Integer;
      APermanent: Boolean);
    procedure PromptIOErrorAsk(const ASrcURI, ADstURI: string; AIndex: Integer;
      AOverwrite, AAppend: Boolean; const AError: TVfsError);
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
    procedure CloseJobUi;
    procedure LayoutJobPopup(const AClientWidth, AClientHeight: Integer);
    procedure DrawJobPopup(const AGrid: TTerminalGrid;
      AClientWidth, AClientHeight: Integer);
    procedure BeginJob(const ASources: TArray<string>; const ADestDirURI: string;
      AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean = True);
    /// <summary>Copy/move with explicit per-source destinations (Sync).</summary>
    procedure BeginJobPairs(const ASources, ADestURIs: TArray<string>;
      AKind: TPanelJobKind; AAutoStart: Boolean = True);
    procedure ApplyCopyMoveOptions(const ADestDirURI: string;
      AOverwriteMode: TJobOverwriteMode; APreserveTimestamps: Boolean;
      AOnlyNewer: Boolean = False; AFollowSymlinks: Boolean = False;
      ARetryLimit: Integer = 0; const AExcludeMask: string = '');
    procedure ConfirmJob;
    procedure QueueAfterConfirm;
    procedure StartIfQueued;
    procedure BindIdentity(AId: Integer);
    procedure BackgroundJob;
    procedure ForegroundJob;
    function IsForegroundRunning: Boolean;
    /// <summary>Answer for pjpOverwriteAsk. ARenameName used when Action=jcaRename.</summary>
    procedure ResolveOverwriteAsk(AAction: TJobConflictAction; ARemember: Boolean;
      const ARenameName: string = '');
    procedure ResolveDeleteAsk(AAction: TJobDeleteFailAction);
    procedure ResolveIOErrorAsk(AAction: TJobIOErrorAction);
    procedure RequestCancel;
    function HandleJobInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;
    function GetActive: Boolean;
    function Title: string;
    property Phase: TPanelJobPhase read FJob.Phase;
    property Kind: TPanelJobKind read FJob.Kind;
    property State: TPanelJobState read FJob;
    property Bounds: TRectI read FJob.Bounds;
    property Active: Boolean read GetActive;
  end;

implementation

function JobErrorDisplayPath(const AError: TVfsError; const AFallbackURI: string): string;
var
  FailedURI: string;
begin
  FailedURI := AError.URI;
  if FailedURI = '' then
    FailedURI := AFallbackURI;
  Result := FileUriToPath(FailedURI);
  if Result <> '' then
    Exit;
  if FailedURI <> '' then
    Result := FailedURI
  else
    Result := FileUriToPath(AFallbackURI);
end;

constructor TPanelJobController.Create(const ATheme: IThemeRenderer;
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
  FAlive := True;
  FLastProgressInvalidateTick := 0;
  FProgressInvalidateQueued := False;
  FProgressInvalidateDirty := False;
  FJob.Phase := pjpNone;
  FJob.Kind := pjkNone;
  FJob.DeleteToRecycleBin := True;
  FJob.SkipAllDeleteErrors := False;
  FJob.SkipAllIOErrors := False;
  FJob.HasRememberedAction := False;
  FJob.RememberedAction := jcaOverwrite;
  ResetExcludeMasks;
end;

procedure TPanelJobController.ResetExcludeMasks;
begin
  SetLength(FExcludeMasks, 0);
  FExcludeMasksReady := False;
end;

destructor TPanelJobController.Destroy;
begin
  FAlive := False;
  if Assigned(FJob.Cancel) then
    FJob.Cancel.Cancel;
  inherited;
end;

procedure TPanelJobController.SetTheme(const ATheme: IThemeRenderer);
begin
  FTheme := ATheme;
end;

procedure TPanelJobController.SetVfs(const AVfs: IVirtualFileSystem);
begin
  FVfs := AVfs;
end;

function TPanelJobController.GetActive: Boolean;
begin
  Result := FJob.Phase <> pjpNone;
end;

function TPanelJobController.Title: string;
begin
  Result := JobTitle;
end;

function TPanelJobController.JobTitle: string;
begin
  case FJob.Kind of
    pjkCopy: Result := T('ui.job.titleCopy', 'Copy');
    pjkMove: Result := T('ui.job.titleMove', 'Move');
    pjkPack: Result := T('ui.job.titlePack', 'Pack');
    pjkUnpack: Result := T('ui.job.titleUnpack', 'Unpack');
    pjkDelete:
      if FJob.DeleteToRecycleBin then
        Result := T('ui.job.titleRecycle', 'Recycle')
      else
        Result := T('ui.job.titleDelete', 'Delete');
  else
    Result := T('ui.job.titleGeneric', 'Job');
  end;
end;

procedure TPanelJobController.CloseJobUi;
begin
  if Assigned(FJob.Cancel) then
    FJob.Cancel.Cancel;
  FJob.Phase := pjpNone;
  FJob.Kind := pjkNone;
  FJob.Id := 0;
  FJob.Presentation := jpForeground;
  FJob.OriginSrcDirURI := '';
  FJob.OriginDstDirURI := '';
  FJob.DeleteToRecycleBin := True;
  FJob.SkipAllDeleteErrors := False;
  FJob.SkipAllIOErrors := False;
  SetLength(FJob.Sources, 0);
  SetLength(FJob.DestURIs, 0);
  FJob.Cancel := nil;
  FJob.Message := '';
  FJob.PendingErrorMessage := '';
  FJob.CurrentName := '';
  FJob.CurrentSrcPath := '';
  FJob.CurrentDstPath := '';
  FJob.AskPath := '';
  FJob.AskNewLine := '';
  FJob.AskExistingLine := '';
  FJob.AskHeadline := '';
  FJob.AskQuestion := '';
  FJob.AskErrorLine := '';
  FJob.AskOfferPermanent := False;
  FJob.ProgressDone := 0;
  FJob.ProgressTotal := 0;
  FJob.BytesDoneBase := 0;
  FJob.BytesTotal := 0;
  FJob.FilesTotal := 0;
  FJob.FilesDone := 0;
  FLastItemSrcPath := '';
  ResetExcludeMasks;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  if Assigned(FOnAfterClose) then
    FOnAfterClose;
end;

function EstimateLocalUriBytes(const AURI: string; out AFileCount: Integer): Int64;
var
  Path: string;

  function Walk(const APath: string): Int64;
  var
    SR: TSearchRec;
    Code: Integer;
  begin
    Result := 0;
    if TFile.Exists(WinApiPath(APath)) then
    begin
      Inc(AFileCount);
      try
        Result := TFile.GetSize(WinApiPath(APath));
      except
        Result := 0;
      end;
      Exit;
    end;
    if not TDirectory.Exists(WinApiPath(APath)) then
      Exit;
    Code := FindFirst(TPath.Combine(APath, '*'), faAnyFile, SR);
    try
      while Code = 0 do
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          if (SR.Attr and faDirectory) <> 0 then
            Inc(Result, Walk(TPath.Combine(APath, SR.Name)))
          else
          begin
            Inc(AFileCount);
            if SR.Size > 0 then
              Inc(Result, SR.Size);
          end;
        end;
        Code := FindNext(SR);
      end;
    finally
      System.SysUtils.FindClose(SR);
    end;
  end;

begin
  Result := 0;
  AFileCount := 0;
  if HasArchiveChain(AURI) then
    Exit;
  Path := FileUriToPath(AURI);
  if Path = '' then
    Exit;
  Result := Walk(Path);
end;

procedure TPanelJobController.LayoutJobPopup(const AClientWidth,
  AClientHeight: Integer);
begin
  FJob.Bounds := TJobPopupRenderer.ComputeLayout(FJob, AClientWidth, AClientHeight);
end;

procedure TPanelJobController.DrawJobPopup(const AGrid: TTerminalGrid;
  AClientWidth, AClientHeight: Integer);
begin
  if not JobShowsOverlay(FJob) then
    Exit;
  LayoutJobPopup(AClientWidth, AClientHeight);
  TJobPopupRenderer.Draw(AGrid, FTheme, FJob, JobTitle);
end;

procedure TPanelJobController.BeginJob(const ASources: TArray<string>;
  const ADestDirURI: string; AKind: TPanelJobKind;
  ADeleteToRecycleBin: Boolean);
var
  ConfirmMsg: string;
  SrcName: string;
begin
  if FJob.Phase <> pjpNone then
    Exit;
  if Length(ASources) = 0 then
    Exit;

  FJob.Kind := AKind;
  FJob.DeleteToRecycleBin := ADeleteToRecycleBin;
  FJob.SkipAllDeleteErrors := False;
  FJob.SkipAllIOErrors := False;
  FJob.Sources := ASources;
  SetLength(FJob.DestURIs, 0);
  FJob.DestDirURI := ADestDirURI;
  FJob.OverwriteMode := jomAsk;
  FJob.PreserveTimestamps := False;
  FJob.OnlyNewer := False;
  FJob.FollowSymlinks := False;
  FJob.ExcludeMask := '';
  ResetExcludeMasks;
  FJob.RetryLimit := 0;
  FJob.RetryLeft := 0;
  FJob.HasRememberedAction := False;
  FJob.RememberedAction := jcaOverwrite;
  FJob.PendingSrcURI := '';
  FJob.PendingDstURI := '';
  FJob.PendingIndex := 0;
  FJob.PendingBothDirs := False;
  FJob.PendingErrorMessage := '';
  FJob.Index := 0;
  FJob.ProgressDone := 0;
  FJob.ProgressTotal := 0;
  FJob.BytesDoneBase := 0;
  FJob.BytesTotal := 0;
  FJob.FilesTotal := Length(ASources);
  FJob.CurrentName := '';
  FJob.CurrentSrcPath := '';
  FJob.CurrentDstPath := '';
  FJob.Message := '';
  FJob.Cancel := nil;
  FJob.Presentation := jpForeground;
  FJob.OriginSrcDirURI := JobOriginSrcDir(ASources);
  FJob.OriginDstDirURI := JobOriginDstDir(ADestDirURI, nil);

  if AKind = pjkDelete then
  begin
    if ADeleteToRecycleBin then
      ConfirmMsg := T('ui.job.confirmRecycle', 'Move %d item(s) to Recycle Bin?', [Length(ASources)])
    else
      ConfirmMsg := T('ui.job.confirmDeletePermanent', 'Permanently delete %d item(s)?', [Length(ASources)]);
  end
  else if AKind = pjkPack then
  begin
    if Length(ASources) = 1 then
    begin
      SrcName := FileUriTitle(ASources[0]);
      ConfirmMsg := T('ui.job.confirmPackOne', 'Pack `%s` to ZIP:', [SrcName]);
    end
    else
      ConfirmMsg := T('ui.job.confirmPackMany', 'Pack %d item(s) to ZIP:', [Length(ASources)]);
  end
  else if AKind = pjkUnpack then
  begin
    if Length(ASources) = 1 then
    begin
      SrcName := FileUriTitle(ASources[0]);
      ConfirmMsg := T('ui.job.confirmUnpackOne', 'Unpack `%s` to:', [SrcName]);
    end
    else
      ConfirmMsg := T('ui.job.confirmUnpackMany', 'Unpack %d item(s) to:', [Length(ASources)]);
  end
  else if Length(ASources) = 1 then
  begin
    SrcName := FileUriTitle(ASources[0]);
    ConfirmMsg := T('ui.job.confirmCopyMoveOne', '%s `%s` to:', [JobTitle, SrcName]);
  end
  else
    ConfirmMsg := T('ui.job.confirmCopyMoveMany', '%s %d item(s) to:', [JobTitle, Length(ASources)]);

  FJob.Phase := pjpConfirm;
  if Assigned(FOnOpenConfirmDialog) then
    FOnOpenConfirmDialog(JobTitle, ConfirmMsg);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.ApplyCopyMoveOptions(const ADestDirURI: string;
  AOverwriteMode: TJobOverwriteMode; APreserveTimestamps: Boolean;
  AOnlyNewer: Boolean; AFollowSymlinks: Boolean; ARetryLimit: Integer;
  const AExcludeMask: string);
begin
  if FJob.Phase <> pjpConfirm then
    Exit;
  if ADestDirURI <> '' then
  begin
    FJob.DestDirURI := ADestDirURI;
    FJob.OriginDstDirURI := JobOriginDstDir(ADestDirURI, FJob.DestURIs);
  end;
  FJob.OverwriteMode := AOverwriteMode;
  FJob.PreserveTimestamps := APreserveTimestamps;
  FJob.OnlyNewer := AOnlyNewer;
  FJob.FollowSymlinks := AFollowSymlinks;
  if ARetryLimit < 0 then
    FJob.RetryLimit := 0
  else
    FJob.RetryLimit := ARetryLimit;
  FJob.RetryLeft := FJob.RetryLimit;
  FJob.ExcludeMask := Trim(AExcludeMask);
  ResetExcludeMasks;
end;

procedure TPanelJobController.BeginJobPairs(const ASources, ADestURIs: TArray<string>;
  AKind: TPanelJobKind; AAutoStart: Boolean);
begin
  if FJob.Phase <> pjpNone then
    Exit;
  if Length(ASources) = 0 then
    Exit;
  if Length(ADestURIs) <> Length(ASources) then
    Exit;
  if not (AKind in [pjkCopy, pjkMove]) then
    Exit;

  FJob.Kind := AKind;
  FJob.DeleteToRecycleBin := True;
  FJob.SkipAllDeleteErrors := False;
  FJob.SkipAllIOErrors := False;
  FJob.Sources := ASources;
  FJob.DestURIs := ADestURIs;
  FJob.DestDirURI := '';
  FJob.OverwriteMode := jomOverwrite;
  FJob.PreserveTimestamps := True;
  FJob.OnlyNewer := False;
  FJob.FollowSymlinks := False;
  FJob.ExcludeMask := '';
  ResetExcludeMasks;
  FJob.RetryLimit := 1;
  FJob.RetryLeft := 1;
  FJob.HasRememberedAction := False;
  FJob.RememberedAction := jcaOverwrite;
  FJob.PendingSrcURI := '';
  FJob.PendingDstURI := '';
  FJob.PendingIndex := 0;
  FJob.PendingBothDirs := False;
  FJob.PendingErrorMessage := '';
  FJob.Index := 0;
  FJob.ProgressDone := 0;
  FJob.ProgressTotal := 0;
  FJob.BytesDoneBase := 0;
  FJob.BytesTotal := 0;
  FJob.FilesTotal := Length(ASources);
  FJob.CurrentName := '';
  FJob.CurrentSrcPath := '';
  FJob.CurrentDstPath := '';
  FJob.Message := '';
  FJob.Cancel := nil;
  FJob.Presentation := jpForeground;
  FJob.OriginSrcDirURI := JobOriginSrcDir(ASources);
  FJob.OriginDstDirURI := JobOriginDstDir('', ADestURIs);
  if AAutoStart then
    StartJobExecution
  else
  begin
    FJob.Phase := pjpQueued;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
  end;
end;

function TPanelJobController.JobItemExcluded(const AName: string): Boolean;
begin
  Result := False;
  if FJob.ExcludeMask = '' then
    Exit;
  if not FExcludeMasksReady then
  begin
    FExcludeMasks := SplitMasks(FJob.ExcludeMask);
    FExcludeMasksReady := True;
  end;
  Result := NameMatchesAnyMask(AName, FExcludeMasks);
end;

function TPanelJobController.PathIsReparsePoint(const APath: string): Boolean;
var
  Attr: DWORD;
begin
  Result := False;
  if APath = '' then
    Exit;
  Attr := GetFileAttributes(PChar(WinApiPath(APath)));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
    ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

procedure TPanelJobController.AdvanceJobAfterItem(AIndex: Integer);
begin
  CommitItemBytes;
  // Flush the last file of this item into FilesDone — NoteItemProgress only
  // counts on a path *transition*, so the final file of a tree (or the only
  // file of a plain-file item) never gets counted from inside a transition
  // and must be flushed here instead. A skipped item (no transfer ever
  // happened, FLastItemSrcPath still points at whatever finished earlier)
  // must not be double-counted.
  if FLastItemSrcPath <> '' then
  begin
    Inc(FJob.FilesDone);
    FLastItemSrcPath := '';
  end;
  FJob.Index := AIndex + 1;
  FJob.ProgressDone := 0;
  FJob.ProgressTotal := 0;
  FJob.FileProgressDone := 0;
  FJob.FileProgressTotal := 0;
  FJob.RetryLeft := FJob.RetryLimit;
  // Keep the progress dialog live while a run of items is being skipped
  // (excluded mask, reparse/newer skip, Skip overwrite mode) — without this,
  // the bars only redraw once an item actually starts transferring bytes,
  // so they look frozen during a skip streak.
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  RunJobItem;
end;

procedure TPanelJobController.BeginItemTotals(const ASrcURI, ADstURI: string);
var
  SrcPath, DstPath: string;
begin
  SrcPath := FileUriToPath(ASrcURI);
  DstPath := FileUriToPath(ADstURI);
  if SrcPath <> '' then
    FJob.CurrentSrcPath := SrcPath
  else
    FJob.CurrentSrcPath := ASrcURI;
  if DstPath <> '' then
    FJob.CurrentDstPath := DstPath
  else
    FJob.CurrentDstPath := ADstURI;
  FJob.ProgressDone := 0;
  FJob.ProgressTotal := 0;
  FJob.FileProgressDone := 0;
  FJob.FileProgressTotal := 0;
end;

procedure TPanelJobController.CommitItemBytes;
var
  ItemBytes: Int64;
begin
  ItemBytes := FJob.ProgressTotal;
  if ItemBytes < FJob.ProgressDone then
    ItemBytes := FJob.ProgressDone;
  if ItemBytes > 0 then
  begin
    Inc(FJob.BytesDoneBase, ItemBytes);
    if FJob.BytesTotal < FJob.BytesDoneBase then
      FJob.BytesTotal := FJob.BytesDoneBase;
  end;
end;

procedure TPanelJobController.NoteItemProgress(ADone, ATotal: Int64;
  const ACurrentName: string; AItemDone: Int64 = 0; AItemTotal: Int64 = 0;
  const AItemSrcPath: string = ''; const AItemDstPath: string = '');
var
  Need: Int64;
begin
  // ADone/ATotal keep their original meaning unchanged: cumulative bytes for
  // the whole current top-level item (a recursive tree copy reports running
  // totals across all its files here) — this still drives the "Total" bar
  // and the Bytes counter exactly like before.
  FJob.ProgressDone := ADone;
  if ATotal > 0 then
    FJob.ProgressTotal := ATotal;
  if ACurrentName <> '' then
    FJob.CurrentName := ACurrentName;

  // AItemDone/AItemTotal/AItemSrcPath, when the VFS callback knows which
  // file it's on, describe just that one file — used for the per-file bar
  // and the live path display instead of reusing ADone/ATotal (which, for a
  // recursive folder copy, are tree-wide and made the "file" and "total"
  // bars move in lockstep when both read from the same numbers).
  if AItemSrcPath <> '' then
  begin
    FJob.FileProgressDone := AItemDone;
    FJob.FileProgressTotal := AItemTotal;
    FJob.CurrentSrcPath := AItemSrcPath;
    FJob.CurrentDstPath := AItemDstPath;
    // A different source path than the last report means the previous file
    // is done (this one's first report already carries AItemDone=AItemTotal
    // for CopyTree's post-file summary, but chunked in-flight reports for a
    // multi-buffer file keep repeating the same path, so only count on the
    // transition, plus the final flush in AdvanceJobAfterItem for the very
    // last file of an item).
    if (FLastItemSrcPath <> '') and (FLastItemSrcPath <> AItemSrcPath) then
      Inc(FJob.FilesDone);
    FLastItemSrcPath := AItemSrcPath;
  end
  else
  begin
    FJob.FileProgressDone := ADone;
    FJob.FileProgressTotal := ATotal;
  end;

  Need := FJob.BytesDoneBase + FJob.ProgressTotal;
  if Need > FJob.BytesTotal then
    FJob.BytesTotal := Need;
  NotifyProgressUi;
end;

procedure TPanelJobController.HandleTransferFailure(const ASrcURI, ADstURI: string;
  AIndex: Integer; AOverwrite, AAppend: Boolean; const AError: TVfsError);
begin
  if Assigned(FJob.Cancel) and FJob.Cancel.IsCancellationRequested then
  begin
    FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', ASrcURI));
    Exit;
  end;
  if (AError.Code = vecCancelled) then
  begin
    FinishJob(False, AError);
    Exit;
  end;
  if FJob.RetryLeft > 0 then
  begin
    Dec(FJob.RetryLeft);
    ExecuteTransfer(ASrcURI, ADstURI, AIndex, AOverwrite, AAppend);
    Exit;
  end;
  if FJob.SkipAllIOErrors then
  begin
    FJob.Index := AIndex + 1;
    RunJobItem;
    Exit;
  end;
  PromptIOErrorAsk(ASrcURI, ADstURI, AIndex, AOverwrite, AAppend, AError);
end;

procedure TPanelJobController.ConfirmJob;
begin
  if FJob.Phase <> pjpConfirm then
    Exit;
  StartJobExecution;
end;

procedure TPanelJobController.QueueAfterConfirm;
begin
  if FJob.Phase <> pjpConfirm then
    Exit;
  FJob.Phase := pjpQueued;
  FJob.Cancel := nil;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.StartIfQueued;
begin
  if FJob.Phase <> pjpQueued then
    Exit;
  StartJobExecution;
end;

procedure TPanelJobController.BindIdentity(AId: Integer);
begin
  FJob.Id := AId;
end;

procedure TPanelJobController.BackgroundJob;
var
  WasForeground: Boolean;
begin
  if not (FJob.Phase in [pjpRunning, pjpError, pjpQueued]) then
    Exit;
  if FJob.Presentation = jpBackground then
    Exit;
  WasForeground := FJob.Presentation = jpForeground;
  FJob.Presentation := jpBackground;
  // Foreground execution pauses dir-watches. Leaving the progress dialog
  // must re-list both panels so the user sees files already copied and
  // LoadSide → SyncDirWatches arms watches again for the rest of the job.
  if WasForeground and Assigned(FOnReloadPanels) then
    FOnReloadPanels(FJob.OriginSrcDirURI, FJob.OriginDstDirURI);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.ForegroundJob;
begin
  if not (FJob.Phase in [pjpRunning, pjpError, pjpQueued]) then
    Exit;
  if FJob.Presentation = jpForeground then
    Exit;
  FJob.Presentation := jpForeground;
  if Assigned(FOnBeforeExecute) then
    FOnBeforeExecute;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

function TPanelJobController.IsForegroundRunning: Boolean;
begin
  Result := (FJob.Phase = pjpRunning) and (FJob.Presentation = jpForeground);
end;

procedure TPanelJobController.RequestCancel;
begin
  if Assigned(FJob.Cancel) then
    FJob.Cancel.Cancel;
end;

procedure TPanelJobController.StartJobExecution;
var
  CapSources: TArray<string>;
begin
  if Assigned(FOnBeforeExecute) then
    FOnBeforeExecute;
  FJob.Cancel := TJobCancelToken.Create;
  FJob.Phase := pjpRunning;
  FJob.Index := 0;
  FJob.BytesDoneBase := 0;
  FJob.FilesDone := 0;
  FLastItemSrcPath := '';
  if FJob.FilesTotal < 1 then
    FJob.FilesTotal := Length(FJob.Sources);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;

  // Async size estimate for Total bytes (copy/move/pack/unpack of file://).
  // Also counts real files recursively so "Files: N / Total" reflects files
  // inside a folder being copied, not just the number of selected top-level
  // items (which would stay e.g. "1/1" for the whole duration of a single
  // folder copy).
  if FJob.Kind in [pjkCopy, pjkMove, pjkPack, pjkUnpack] then
  begin
    CapSources := Copy(FJob.Sources);
    TThread.CreateAnonymousThread(
      procedure
      var
        I, FileCount, SubCount: Integer;
        Total: Int64;
      begin
        Total := 0;
        FileCount := 0;
        for I := 0 to High(CapSources) do
        begin
          Inc(Total, EstimateLocalUriBytes(CapSources[I], SubCount));
          Inc(FileCount, SubCount);
        end;
        TThread.Queue(nil,
          procedure
          begin
            if not FAlive or (FJob.Phase <> pjpRunning) then
              Exit;
            if Total > FJob.BytesTotal then
              FJob.BytesTotal := Total;
            if FileCount > FJob.FilesTotal then
              FJob.FilesTotal := FileCount;
            NotifyProgressUi;
          end);
      end).Start;
  end;

  // Defer item work so F5/Enter can close the confirm dialog and repaint
  // before sync FS probes (Exists/GetFileAttributes) or a skip-storm run.
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FAlive then
        Exit;
      if FJob.Phase <> pjpRunning then
        Exit;
      RunJobItem;
    end);
end;

procedure TPanelJobController.NotifyProgressUi;
const
  cMinInvalidateMs = 50; // ~20 Hz full Recompose while a transfer runs
begin
  FProgressInvalidateDirty := True;
  if (GetTickCount64 - FLastProgressInvalidateTick) >= cMinInvalidateMs then
  begin
    FProgressInvalidateDirty := False;
    FLastProgressInvalidateTick := GetTickCount64;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    Exit;
  end;
  if FProgressInvalidateQueued then
    Exit;
  FProgressInvalidateQueued := True;
  TThread.ForceQueue(nil,
    procedure
    begin
      FProgressInvalidateQueued := False;
      if not FAlive or not FProgressInvalidateDirty then
        Exit;
      if FJob.Phase <> pjpRunning then
        Exit;
      FProgressInvalidateDirty := False;
      FLastProgressInvalidateTick := GetTickCount64;
      if Assigned(FOnInvalidate) then
        FOnInvalidate;
    end, cMinInvalidateMs);
end;

procedure TPanelJobController.StartTransferInvalidate(const ASrcURI, ADstURI: string;
  AIndex: Integer; AOverwrite, AAppend: Boolean);
begin
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
  ExecuteTransfer(ASrcURI, ADstURI, AIndex, AOverwrite, AAppend);
end;

function TPanelJobController.TryContinueDirMerge(const ASrcURI, ADstURI: string;
  AIndex: Integer; AIsDirMerge: Boolean): Boolean;
begin
  // Folder onto an existing folder is a merge, never a real conflict — the
  // actual overwrite/skip decisions happen one level down, per file, inside
  // CopyTree. Skip/Overwrite mode is handled unconditionally right here. Ask
  // mode still prompts once per folder (matches Explorer/FAR convention, and
  // CopyTree has no way to prompt per file mid-recursion), but the answer
  // must become CopyTree's AOverwrite for a merge — it must never mean
  // "abandon this whole folder". Treating a pre-existing folder as an
  // ordinary conflict is what silently dropped everything missing at the
  // destination under a folder-level "Skip", both from Skip mode directly
  // and from clicking Skip on this exact prompt (reported on
  // P:\_РП_ЛЕНА_2026 -> D:\_РП_ЛЕНА_2026, every nested folder pre-existing).
  Result := False;
  if not AIsDirMerge then
    Exit;
  if FJob.OverwriteMode <> jomAsk then
  begin
    StartTransferInvalidate(ASrcURI, ADstURI, AIndex,
      FJob.OverwriteMode = jomOverwrite, False);
    Exit(True);
  end;
  if FJob.HasRememberedAction then
  begin
    StartTransferInvalidate(ASrcURI, ADstURI, AIndex,
      FJob.RememberedAction <> jcaSkip, FJob.RememberedAction = jcaAppend);
    Exit(True);
  end;
end;

function TPanelJobController.TryContinueExistingDest(const ASrcURI, ADstURI: string;
  AIndex: Integer; AIsDirMerge: Boolean; const ANewLine,
  AExistingLine: string): Boolean;
begin
  Result := False;
  if FJob.OverwriteMode = jomSkip then
  begin
    AdvanceJobAfterItem(AIndex);
    Exit(True);
  end;
  if FJob.OverwriteMode <> jomAsk then
    Exit;
  Result := True;
  if FJob.HasRememberedAction then
  begin
    case FJob.RememberedAction of
      jcaSkip:
        AdvanceJobAfterItem(AIndex);
      jcaAppend:
        StartTransferInvalidate(ASrcURI, ADstURI, AIndex, True, True);
    else
      StartTransferInvalidate(ASrcURI, ADstURI, AIndex, True, False);
    end;
    Exit;
  end;
  // Fresh Ask prompt: IsDirMerge means "folder conflict, no remembered
  // answer yet" — tell ResolveOverwriteAsk so its Skip branch merges
  // instead of abandoning.
  FJob.PendingBothDirs := AIsDirMerge;
  PromptOverwriteAsk(ASrcURI, ADstURI, AIndex, ANewLine, AExistingLine);
end;

procedure TPanelJobController.ContinueJobItemAfterProbe(const ASrcURI, ADstURI: string;
  AIndex: Integer; AKind: TPanelJobKind; ASkipReparse, ASkipNewer,
  ADestExists: Boolean; ABothDirs: Boolean; const ANewLine, AExistingLine: string);
var
  IsDirMerge: Boolean;
begin
  if not FAlive then
    Exit;
  if FJob.Phase <> pjpRunning then
    Exit;
  if FJob.Index <> AIndex then
    Exit;

  if ASkipReparse or ASkipNewer then
  begin
    AdvanceJobAfterItem(AIndex);
    Exit;
  end;

  IsDirMerge := ADestExists and ABothDirs;
  if TryContinueDirMerge(ASrcURI, ADstURI, AIndex, IsDirMerge) then
    Exit;
  if ADestExists and
     TryContinueExistingDest(ASrcURI, ADstURI, AIndex, IsDirMerge, ANewLine,
       AExistingLine) then
    Exit;

  StartTransferInvalidate(ASrcURI, ADstURI, AIndex,
    FJob.OverwriteMode <> jomSkip, False);
end;

procedure TPanelJobController.RunJobItem;
var
  SrcURI, DstURI, Name: string;
  Kind: TPanelJobKind;
  Idx: Integer;
  CapSrc, CapDst: string;
  CapIdx: Integer;
  CapKind: TPanelJobKind;
  CapFollow, CapOnlyNewer, CapOverwriteAsk: Boolean;
begin
  if not FAlive then
    Exit;
  if FJob.Phase <> pjpRunning then
    Exit;
  if (FJob.Index < 0) or (FJob.Index > High(FJob.Sources)) then
  begin
    FinishJob(True, TVfsError.Ok);
    Exit;
  end;

  SrcURI := FJob.Sources[FJob.Index];
  Name := FileUriTitle(SrcURI);
  if (Name <> '') and (Name[Length(Name)] = '/') then
    Delete(Name, Length(Name), 1);
  FJob.CurrentName := Name;
  Kind := FJob.Kind;
  Idx := FJob.Index;
  FJob.RetryLeft := FJob.RetryLimit;

  if Kind = pjkDelete then
  begin
    BeginItemTotals(SrcURI, '');
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    ExecuteDeleteItem(SrcURI, Idx,
      (not FJob.DeleteToRecycleBin) or HasArchiveChain(SrcURI));
    Exit;
  end;

  if JobItemExcluded(Name) then
  begin
    AdvanceJobAfterItem(Idx);
    Exit;
  end;

  if Kind = pjkPack then
  begin
    if IsSevenZipUri(FJob.DestDirURI) then
      DstURI := JoinVfsUri(FJob.DestDirURI, Name)
    else if SameText(ExtractFileExt(FileUriToPath(FJob.DestDirURI)), '.7z') then
      DstURI := JoinVfsUri(PathToSevenZipRootUri(FileUriToPath(FJob.DestDirURI)), Name)
    else
      DstURI := JoinVfsUri(EnsureArchiveRootUri(FJob.DestDirURI), Name);
  end
  else if Kind = pjkUnpack then
  begin
    if HasArchiveChain(SrcURI) then
      DstURI := JoinFileUri(FJob.DestDirURI, Name)
    else if IsZipFileName(Name) then
    begin
      // Whole .zip on disk → extract into Dest\<archiveName>\
      SrcURI := EnsureArchiveRootUri(SrcURI);
      DstURI := JoinFileUri(FJob.DestDirURI, ChangeFileExt(Name, ''));
    end
    else
    begin
      FinishJob(False, TVfsError.Make(vecInvalidURI,
        'Select a ZIP file or items inside an archive', SrcURI));
      Exit;
    end;
  end
  else if (Length(FJob.DestURIs) = Length(FJob.Sources)) and
    (Idx >= 0) and (Idx <= High(FJob.DestURIs)) then
    DstURI := FJob.DestURIs[Idx]
  else
    DstURI := JoinFileUri(FJob.DestDirURI, Name);

  // Pack/Unpack: no local FS probes — start transfer on UI thread.
  if not (Kind in [pjkCopy, pjkMove]) then
  begin
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    ExecuteTransfer(SrcURI, DstURI, Idx, FJob.OverwriteMode <> jomSkip, False);
    Exit;
  end;

  // Copy/Move: Exists/GetFileAttributes/mtime can block on network/OneDrive —
  // keep the progress popup responsive by probing off the UI thread.
  CapSrc := SrcURI;
  CapDst := DstURI;
  CapIdx := Idx;
  CapKind := Kind;
  CapFollow := FJob.FollowSymlinks;
  CapOnlyNewer := FJob.OnlyNewer;
  CapOverwriteAsk := (FJob.OverwriteMode = jomAsk) and not FJob.HasRememberedAction;
  TThread.CreateAnonymousThread(
    procedure
    begin
      ProbeJobItemAsync(CapSrc, CapDst, CapIdx, CapKind, CapFollow, CapOnlyNewer,
        CapOverwriteAsk);
    end).Start;
end;

// Runs off the UI thread (called from the anonymous thread started by
// RunJobItem): Exists/GetFileAttributes/mtime can block on network/OneDrive
// sources, so all pre-transfer probing happens here before hopping back.
function TPanelJobController.ProbeSkipReparse(AKind: TPanelJobKind;
  AFollowSymlinks: Boolean; const ASrcURI, ASrcPath: string): Boolean;
begin
  Result := (AKind in [pjkCopy, pjkMove]) and (not AFollowSymlinks) and
    (not HasArchiveChain(ASrcURI)) and PathIsReparsePoint(ASrcPath);
end;

function TPanelJobController.ProbeSkipNewer(AOnlyNewer, ASkipReparse: Boolean;
  const ASrcURI, ADstURI, ASrcPath, ADstPath: string): Boolean;
begin
  Result := False;
  if (not AOnlyNewer) or ASkipReparse or HasArchiveChain(ASrcURI) or
     HasArchiveChain(ADstURI) then
    Exit;
  if (ASrcPath <> '') and (ADstPath <> '') and TFile.Exists(WinApiPath(ASrcPath)) and
     (not TDirectory.Exists(WinApiPath(ASrcPath))) and TFile.Exists(WinApiPath(ADstPath)) then
    Result := TFile.GetLastWriteTimeUtc(ADstPath) >=
      TFile.GetLastWriteTimeUtc(ASrcPath);
end;

// Probed here, off the UI thread: TDirectory.Exists on a network source
// (P:\) can block for a while.
procedure TPanelJobController.ProbeDestOverlap(ASkipReparse, ASkipNewer: Boolean;
  const ASrcURI, ADstURI, ASrcPath, ADstPath: string;
  out ADestExists, ABothDirs: Boolean);
begin
  ADestExists := False;
  ABothDirs := False;
  if ASkipReparse or ASkipNewer or HasArchiveChain(ADstURI) or (ADstPath = '') then
    Exit;
  ADestExists := TFile.Exists(WinApiPath(ADstPath)) or TDirectory.Exists(WinApiPath(ADstPath));
  ABothDirs := ADestExists and (ASrcPath <> '') and
    TDirectory.Exists(WinApiPath(ASrcPath)) and TDirectory.Exists(WinApiPath(ADstPath)) and
    (not HasArchiveChain(ASrcURI));
end;

procedure TPanelJobController.ProbeJobItemAsync(const ASrcURI, ADstURI: string;
  AIndex: Integer; AKind: TPanelJobKind; AFollowSymlinks, AOnlyNewer,
  AOverwriteAsk: Boolean);
var
  SkipReparse, SkipNewer, DestExists, BothDirs: Boolean;
  SrcPath, DstPath, NewLine, ExistingLine: string;
begin
  SkipReparse := False;
  SkipNewer := False;
  DestExists := False;
  BothDirs := False;
  NewLine := '';
  ExistingLine := '';
  try
    SrcPath := FileUriToPath(ASrcURI);
    DstPath := FileUriToPath(ADstURI);
    SkipReparse := ProbeSkipReparse(AKind, AFollowSymlinks, ASrcURI, SrcPath);
    SkipNewer := ProbeSkipNewer(AOnlyNewer, SkipReparse, ASrcURI, ADstURI, SrcPath, DstPath);
    ProbeDestOverlap(SkipReparse, SkipNewer, ASrcURI, ADstURI, SrcPath, DstPath,
      DestExists, BothDirs);
    if DestExists and AOverwriteAsk then
    begin
      NewLine := FormatConflictFileLine('New', SrcPath);
      ExistingLine := FormatConflictFileLine('Existing', DstPath);
    end;
  except
    // Treat probe failures as "no skip / dest unknown" — transfer will report.
  end;
  TThread.Queue(nil,
    procedure
    begin
      ContinueJobItemAfterProbe(ASrcURI, ADstURI, AIndex, AKind,
        SkipReparse, SkipNewer, DestExists, BothDirs, NewLine, ExistingLine);
    end);
end;

function TPanelJobController.FormatConflictFileLine(const ALabel, APath: string): string;
var
  Sz: Int64;
  Dt: TDateTime;
begin
  Sz := 0;
  Dt := 0;
  try
    if TFile.Exists(WinApiPath(APath)) then
    begin
      Sz := TFile.GetSize(WinApiPath(APath));
      Dt := TFile.GetLastWriteTime(WinApiPath(APath));
    end
    else if TDirectory.Exists(WinApiPath(APath)) then
      Dt := TDirectory.GetLastWriteTime(WinApiPath(APath));
  except
  end;
  if Dt > 0 then
    Result := Format('%-9s %10d  %s', [ALabel, Sz, FormatDateTime('dd.mm.yyyy hh:nn:ss', Dt)])
  else
    Result := Format('%-9s %10d', [ALabel, Sz]);
end;

procedure TPanelJobController.PromptOverwriteAsk(const ASrcURI, ADstURI: string;
  AIndex: Integer; const ANewLine, AExistingLine: string);
var
  SrcPath, DstPath, NewLine, ExistingLine: string;
begin
  FJob.Phase := pjpOverwriteAsk;
  FJob.PendingSrcURI := ASrcURI;
  FJob.PendingDstURI := ADstURI;
  FJob.PendingIndex := AIndex;
  SrcPath := FileUriToPath(ASrcURI);
  DstPath := FileUriToPath(ADstURI);
  NewLine := ANewLine;
  ExistingLine := AExistingLine;
  if (NewLine = '') or (ExistingLine = '') then
  begin
    if NewLine = '' then
      NewLine := FormatConflictFileLine('New', SrcPath);
    if ExistingLine = '' then
      ExistingLine := FormatConflictFileLine('Existing', DstPath);
  end;
  FJob.AskPath := DstPath;
  FJob.AskNewLine := NewLine;
  FJob.AskExistingLine := ExistingLine;
  FJob.AskHeadline := '';
  FJob.AskQuestion := '';
  FJob.AskErrorLine := '';
  FJob.AskOfferPermanent := False;
  if Assigned(FOnOverwriteAsk) then
    FOnOverwriteAsk(DstPath, NewLine, ExistingLine);
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

function TPanelJobController.FormatJobErrorLine(const AError: TVfsError): string;
begin
  Result := Trim(AError.Message);
  if Result = '' then
    case AError.Code of
      vecAccessDenied:
        Result := Format('0x%8.8x - %s', [ERROR_ACCESS_DENIED,
          SysErrorMessage(ERROR_ACCESS_DENIED)]);
      vecNotFound:
        Result := 'Path not found';
      vecCancelled:
        Result := 'Cancelled';
    else
      Result := 'Operation failed';
    end
  else if AError.Code = vecAccessDenied then
  begin
    if Pos('Access denied', Result) = 1 then
      Result := Format('0x%8.8x - %s', [ERROR_ACCESS_DENIED,
        SysErrorMessage(ERROR_ACCESS_DENIED)]);
  end;
end;

procedure TPanelJobController.PromptDeleteAsk(const ASrcURI: string;
  const AError: TVfsError; AOfferPermanent: Boolean);
var
  Path, Headline, Question, ErrLine: string;
  IsDir: Boolean;
begin
  FJob.Phase := pjpDeleteAsk;
  FJob.PendingSrcURI := ASrcURI;
  FJob.PendingIndex := FJob.Index;
  FJob.PendingErrorMessage := AError.Message;
  Path := JobErrorDisplayPath(AError, ASrcURI);
  IsDir := (Path <> '') and TDirectory.Exists(WinApiPath(Path));
  if AOfferPermanent then
  begin
    if IsDir then
      Headline := 'Cannot move folder to the Recycle Bin'
    else
      Headline := 'Cannot move file to the Recycle Bin';
    Question := 'Try to delete it permanently?';
  end
  else
  begin
    if IsDir then
      Headline := 'Cannot delete folder'
    else
      Headline := 'Cannot delete file';
    Question := 'Retry permanent delete?';
  end;
  ErrLine := FormatJobErrorLine(AError);
  FJob.AskPath := Path;
  FJob.AskHeadline := Headline;
  FJob.AskQuestion := Question;
  FJob.AskErrorLine := ErrLine;
  FJob.AskOfferPermanent := AOfferPermanent;
  FJob.AskNewLine := '';
  FJob.AskExistingLine := '';
  if Assigned(FOnDeleteAsk) then
    FOnDeleteAsk(Path, Headline, Question, ErrLine, AOfferPermanent)
  else
  begin
    FinishJob(False, AError);
    Exit;
  end;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.PromptIOErrorAsk(const ASrcURI, ADstURI: string;
  AIndex: Integer; AOverwrite, AAppend: Boolean; const AError: TVfsError);
var
  Path, Headline, ErrLine: string;
begin
  FJob.Phase := pjpIOErrorAsk;
  FJob.PendingSrcURI := ASrcURI;
  FJob.PendingDstURI := ADstURI;
  FJob.PendingIndex := AIndex;
  FJob.PendingTransferOverwrite := AOverwrite;
  FJob.PendingTransferAppend := AAppend;
  FJob.PendingErrorMessage := AError.Message;
  // AError.URI names the file that actually failed (a recursive tree copy
  // means this is rarely the top-level ASrcURI) — show that one, falling
  // back to ASrcURI only if the VFS layer left it blank.
  Path := JobErrorDisplayPath(AError, ASrcURI);
  case FJob.Kind of
    pjkMove: Headline := 'Move failed';
    pjkPack: Headline := 'Pack failed';
    pjkUnpack: Headline := 'Unpack failed';
  else
    Headline := 'Copy failed';
  end;
  ErrLine := FormatJobErrorLine(AError);
  FJob.AskPath := Path;
  FJob.AskHeadline := Headline;
  FJob.AskErrorLine := ErrLine;
  FJob.AskQuestion := '';
  FJob.AskNewLine := '';
  FJob.AskExistingLine := '';
  FJob.AskOfferPermanent := False;
  if Assigned(FOnIOErrorAsk) then
    FOnIOErrorAsk(Headline, Path, ErrLine)
  else
  begin
    FinishJob(False, AError);
    Exit;
  end;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.ExecuteDeleteItem(const ASrcURI: string;
  AIndex: Integer; APermanent: Boolean);
var
  DelMode: TVfsDeleteMode;
  Cancel: IJobCancelToken;
  SrcURI: string;
  Idx: Integer;
begin
  SrcURI := ASrcURI;
  Idx := AIndex;
  Cancel := FJob.Cancel;
  if APermanent then
    DelMode := vdmPermanent
  else
    DelMode := vdmRecycleBin;

  FVfs.DeleteAsync(SrcURI, DelMode, Cancel,
    procedure(const ADone, ATotal: Int64; const ACurrentName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
      if not FAlive or (FJob.Phase <> pjpRunning) then
        Exit;
      NoteItemProgress(ADone, ATotal, ACurrentName, AItemDone, AItemTotal,
        AItemSrcPath, AItemDstPath);
    end,
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      if not FAlive then
        Exit;
      if FJob.Phase <> pjpRunning then
      begin
        if ASuccess and Assigned(FOnReloadPanels) then
          FOnReloadPanels(FJob.OriginSrcDirURI, FJob.OriginDstDirURI);
        if ASuccess and Assigned(FOnInvalidate) then
          FOnInvalidate;
        Exit;
      end;
      if Assigned(FJob.Cancel) and FJob.Cancel.IsCancellationRequested then
      begin
        FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', SrcURI));
        Exit;
      end;
      if not ASuccess then
      begin
        if Assigned(FJob.Cancel) and FJob.Cancel.IsCancellationRequested then
        begin
          FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', SrcURI));
          Exit;
        end;
        if (AError.Code = vecNotFound) or FJob.SkipAllDeleteErrors then
        begin
          FJob.Index := Idx + 1;
          RunJobItem;
          Exit;
        end;
        PromptDeleteAsk(SrcURI, AError, not APermanent);
        Exit;
      end;
      FJob.Index := Idx + 1;
      RunJobItem;
    end);
end;

procedure TPanelJobController.ResolveDeleteAsk(AAction: TJobDeleteFailAction);
var
  SrcURI, RootSrcURI: string;
  Idx: Integer;
begin
  if FJob.Phase <> pjpDeleteAsk then
    Exit;
  SrcURI := FJob.PendingSrcURI;
  Idx := FJob.PendingIndex;
  FJob.PendingErrorMessage := '';

  if (Idx >= 0) and (Idx <= High(FJob.Sources)) then
    RootSrcURI := FJob.Sources[Idx]
  else
    RootSrcURI := SrcURI;

  case AAction of
    jdaPermanent, jdaRetry:
      begin
        FJob.Phase := pjpRunning;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        ExecuteDeleteItem(RootSrcURI, Idx, True);
      end;
    jdaSkip:
      begin
        FJob.Phase := pjpRunning;
        FJob.Index := Idx + 1;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        RunJobItem;
      end;
    jdaSkipAll:
      begin
        FJob.SkipAllDeleteErrors := True;
        FJob.Phase := pjpRunning;
        FJob.Index := Idx + 1;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        RunJobItem;
      end;
  else
    FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', SrcURI));
  end;
end;

procedure TPanelJobController.ResolveIOErrorAsk(AAction: TJobIOErrorAction);
var
  SrcURI, DstURI: string;
  Idx: Integer;
  Overwrite, Append: Boolean;
begin
  if FJob.Phase <> pjpIOErrorAsk then
    Exit;
  SrcURI := FJob.PendingSrcURI;
  DstURI := FJob.PendingDstURI;
  Idx := FJob.PendingIndex;
  Overwrite := FJob.PendingTransferOverwrite;
  Append := FJob.PendingTransferAppend;
  FJob.PendingErrorMessage := '';

  case AAction of
    jioRetry:
      begin
        FJob.Phase := pjpRunning;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        ExecuteTransfer(SrcURI, DstURI, Idx, Overwrite, Append);
      end;
    jioSkip:
      begin
        FJob.Phase := pjpRunning;
        FJob.Index := Idx + 1;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        RunJobItem;
      end;
    jioSkipAll:
      begin
        FJob.SkipAllIOErrors := True;
        FJob.Phase := pjpRunning;
        FJob.Index := Idx + 1;
        if Assigned(FOnInvalidate) then
          FOnInvalidate;
        RunJobItem;
      end;
  else
    FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', SrcURI));
  end;
end;

procedure TPanelJobController.ResolveOverwriteAsk(AAction: TJobConflictAction;
  ARemember: Boolean; const ARenameName: string);
var
  SrcURI, DstURI, NewName, Dir: string;
  Idx: Integer;
begin
  if FJob.Phase <> pjpOverwriteAsk then
    Exit;
  SrcURI := FJob.PendingSrcURI;
  DstURI := FJob.PendingDstURI;
  Idx := FJob.PendingIndex;
  FJob.Phase := pjpRunning;

  if ARemember and (AAction in [jcaOverwrite, jcaSkip, jcaAppend]) then
  begin
    FJob.HasRememberedAction := True;
    FJob.RememberedAction := AAction;
  end;

  case AAction of
    jcaCancel:
      begin
        FinishJob(False, TVfsError.Make(vecCancelled, 'Cancelled', SrcURI));
        Exit;
      end;
    jcaSkip:
      begin
        if FJob.PendingBothDirs then
        begin
          // Folder-vs-folder prompt: "Skip" means "don't overwrite files
          // that conflict inside it", not "abandon the folder" — the whole
          // point of this fix (see ContinueJobItemAfterProbe). Route through
          // ExecuteTransfer/CopyTree exactly like the Skip-mode fast path.
          ExecuteTransfer(SrcURI, DstURI, Idx, False, False);
          Exit;
        end;
        AdvanceJobAfterItem(Idx);
        Exit;
      end;
    jcaRename:
      begin
        NewName := Trim(ARenameName);
        if NewName = '' then
        begin
          PromptOverwriteAsk(SrcURI, DstURI, Idx);
          Exit;
        end;
        Dir := ExtractFilePath(FileUriToPath(DstURI));
        DstURI := PathToFileUri(TPath.Combine(Dir, NewName));
        if TFile.Exists(WinApiPath(FileUriToPath(DstURI))) or
           TDirectory.Exists(WinApiPath(FileUriToPath(DstURI))) then
        begin
          PromptOverwriteAsk(SrcURI, DstURI, Idx);
          Exit;
        end;
        ExecuteTransfer(SrcURI, DstURI, Idx, False, False);
      end;
    jcaAppend:
      ExecuteTransfer(SrcURI, DstURI, Idx, True, True);
    jcaOverwrite:
      ExecuteTransfer(SrcURI, DstURI, Idx, True, False);
  end;
end;

procedure TPanelJobController.ExecuteTransfer(const ASrcURI, ADstURI: string;
  AIndex: Integer; AOverwrite, AAppend: Boolean);
var
  Kind: TPanelJobKind;
  Cancel: IJobCancelToken;
  SrcURI, DstURI, SrcPath, DstPath: string;
  Idx: Integer;
  DoOverwrite: Boolean;
begin
  Kind := FJob.Kind;
  Cancel := FJob.Cancel;
  SrcURI := ASrcURI;
  DstURI := ADstURI;
  Idx := AIndex;
  DoOverwrite := AOverwrite;
  FJob.Phase := pjpRunning;
  BeginItemTotals(SrcURI, DstURI);
  // Parent-directory creation for nested DestURIs runs inside the VFS worker
  // (CopyAsync/MoveAsync), not on the UI thread.

  if AAppend and (Kind = pjkCopy) and not HasArchiveChain(SrcURI) and
     not HasArchiveChain(DstURI) then
  begin
    SrcPath := FileUriToPath(SrcURI);
    DstPath := FileUriToPath(DstURI);
    if TFile.Exists(WinApiPath(SrcPath)) and TFile.Exists(WinApiPath(DstPath)) then
    begin
      RunAppendCopyThread(SrcURI, DstURI, SrcPath, DstPath, Idx, Cancel);
      Exit;
    end;
    DoOverwrite := True;
  end;

  if (Kind = pjkCopy) or (Kind = pjkPack) or (Kind = pjkUnpack) then
    FVfs.CopyAsync(SrcURI, DstURI, Cancel,
      procedure(const ADone, ATotal: Int64; const ACurrentName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
      begin
        if not FAlive or (FJob.Phase <> pjpRunning) then
          Exit;
        NoteItemProgress(ADone, ATotal, ACurrentName, AItemDone, AItemTotal,
          AItemSrcPath, AItemDstPath);
      end,
      procedure(const ASuccess: Boolean; const AError: TVfsError)
      begin
        if not FAlive then
          Exit;
        if FJob.Phase <> pjpRunning then
          Exit;
        if not ASuccess then
        begin
          HandleTransferFailure(SrcURI, DstURI, Idx, DoOverwrite, False, AError);
          Exit;
        end;
        AdvanceJobAfterItem(Idx);
      end, DoOverwrite, FJob.PreserveTimestamps)
  else if Kind = pjkMove then
    FVfs.MoveAsync(SrcURI, DstURI, Cancel,
      procedure(const ADone, ATotal: Int64; const ACurrentName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
      begin
        if not FAlive or (FJob.Phase <> pjpRunning) then
          Exit;
        NoteItemProgress(ADone, ATotal, ACurrentName, AItemDone, AItemTotal,
          AItemSrcPath, AItemDstPath);
      end,
      procedure(const ASuccess: Boolean; const AError: TVfsError)
      begin
        if not FAlive then
          Exit;
        if FJob.Phase <> pjpRunning then
          Exit;
        if not ASuccess then
        begin
          HandleTransferFailure(SrcURI, DstURI, Idx, DoOverwrite, False, AError);
          Exit;
        end;
        AdvanceJobAfterItem(Idx);
      end, DoOverwrite, FJob.PreserveTimestamps);
end;

// Fast path for "append to an existing plain file" (Copy only, no archives):
// a single background thread streams bytes instead of going through the VFS.
procedure TPanelJobController.RunAppendCopyThread(const ASrcURI, ADstURI, ASrcPath,
  ADstPath: string; AIndex: Integer; const ACancel: IJobCancelToken);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Src, Dst: TFileStream;
      Buf: TBytes;
      N: Integer;
      Copied, Total, CapDone, CapTotal: Int64;
      Err, CapErr: TVfsError;
      LastProgTick: UInt64;
    begin
      Err := TVfsError.Ok;
      CapErr := TVfsError.Ok;
      Src := nil;
      Dst := nil;
      Copied := 0;
      CapDone := 0;
      CapTotal := 0;
      LastProgTick := 0;
      try
        Src := TFileStream.Create(ASrcPath, fmOpenRead or fmShareDenyWrite);
        Dst := TFileStream.Create(ADstPath, fmOpenWrite or fmShareDenyWrite);
        Dst.Seek(0, soEnd);
        Total := Src.Size;
        SetLength(Buf, 64 * 1024);
        while True do
        begin
          if Assigned(ACancel) and ACancel.IsCancellationRequested then
          begin
            Err := TVfsError.Make(vecCancelled, 'Cancelled', ASrcURI);
            Break;
          end;
          N := Src.Read(Buf[0], Length(Buf));
          if N <= 0 then
            Break;
          Dst.WriteBuffer(Buf[0], N);
          Inc(Copied, N);
          CapDone := Copied;
          CapTotal := Total;
          if ((Copied >= Total) or (GetTickCount64 - LastProgTick >= 50)) then
          begin
            LastProgTick := GetTickCount64;
            TThread.Queue(nil,
              procedure
              begin
                if not FAlive or (FJob.Phase <> pjpRunning) then
                  Exit;
                NoteItemProgress(CapDone, CapTotal, '', CapDone, CapTotal, ASrcPath, ADstPath);
              end);
          end;
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, ASrcURI);
      end;
      Src.Free;
      Dst.Free;
      CapErr := Err;
      TThread.Queue(nil,
        procedure
        begin
          if not FAlive then
            Exit;
          if FJob.Phase <> pjpRunning then
            Exit;
          if CapErr.Code <> vecOk then
          begin
            HandleTransferFailure(ASrcURI, ADstURI, AIndex, True, True, CapErr);
            Exit;
          end;
          AdvanceJobAfterItem(AIndex);
        end);
    end).Start;
end;

procedure TPanelJobController.FinishJob(ASuccess: Boolean; const AError: TVfsError);
var
  OriginSrc, OriginDst: string;
  Finished: TJobFinishedEvent;
  Invalidate: TProc;
begin
  OriginSrc := FJob.OriginSrcDirURI;
  OriginDst := FJob.OriginDstDirURI;
  // CloseJobUi can drop this controller (idle prune). Keep the callbacks
  // alive on the stack so the calls below do not go through a freed Self.
  Finished := FOnJobFinished;
  Invalidate := FOnInvalidate;
  if ASuccess then
  begin
    if Assigned(FOnClearSelection) then
      FOnClearSelection(OriginSrc);
    if Assigned(FOnReloadPanels) then
      FOnReloadPanels(OriginSrc, OriginDst);
    CloseJobUi;
    if Assigned(Finished) then
      Finished(True);
    if Assigned(Invalidate) then
      Invalidate;
    Exit;
  end;

  if AError.Code = vecCancelled then
  begin
    if Assigned(FOnReloadPanels) then
      FOnReloadPanels(OriginSrc, OriginDst);
    CloseJobUi;
    if Assigned(Finished) then
      Finished(False);
    if Assigned(Invalidate) then
      Invalidate;
    Exit;
  end;

  FJob.Phase := pjpError;
  FJob.Message := AError.Message;
  if FJob.Message = '' then
    case AError.Code of
      vecAlreadyExists: FJob.Message := 'Already exists';
      vecAccessDenied: FJob.Message := 'Access denied';
      vecNotFound: FJob.Message := 'Not found';
    else
      FJob.Message := 'Operation failed';
    end;
  FJob.Cancel := nil;
  if Assigned(FOnInvalidate) then
    FOnInvalidate;
end;

procedure TPanelJobController.HandleConfirmKeys(var AKey: Word; var AKeyChar: Char);
begin
  if AKey = vkReturn then
  begin
    ConfirmJob;
    AKey := 0;
  end
  else if AKey = vkEscape then
  begin
    CloseJobUi;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
  end
  else if (AKeyChar = 'y') or (AKeyChar = 'Y') then
  begin
    ConfirmJob;
    AKey := 0;
    AKeyChar := #0;
  end
  else if (AKeyChar = 'n') or (AKeyChar = 'N') then
  begin
    CloseJobUi;
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
    AKeyChar := #0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TPanelJobController.HandleRunningKeys(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char);
begin
  if (AShift = []) and ((AKeyChar = 'b') or (AKeyChar = 'B')) then
  begin
    BackgroundJob;
    AKey := 0;
    AKeyChar := #0;
  end
  else if AKey = vkEscape then
  begin
    if Assigned(FJob.Cancel) then
      FJob.Cancel.Cancel;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TPanelJobController.HandleAskEscapeKeys(var AKey: Word; var AKeyChar: Char;
  AOnEscape: TProc);
begin
  if AKey = vkEscape then
  begin
    if Assigned(AOnEscape) then
      AOnEscape;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

procedure TPanelJobController.HandleErrorKeys(var AKey: Word; var AKeyChar: Char);
var
  OriginSrc, OriginDst: string;
begin
  if (AKey = vkReturn) or (AKey = vkEscape) then
  begin
    OriginSrc := FJob.OriginSrcDirURI;
    OriginDst := FJob.OriginDstDirURI;
    CloseJobUi;
    if Assigned(FOnReloadPanels) then
      FOnReloadPanels(OriginSrc, OriginDst);
    if Assigned(FOnInvalidate) then
      FOnInvalidate;
    AKey := 0;
  end
  else
  begin
    AKey := 0;
    AKeyChar := #0;
  end;
end;

function TPanelJobController.HandleJobInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  Result := True;
  case FJob.Phase of
    pjpConfirm:
      HandleConfirmKeys(AKey, AKeyChar);
    pjpQueued:
      Result := False;
    pjpRunning:
      begin
        if FJob.Presentation = jpBackground then
          Exit(False);
        HandleRunningKeys(AKey, AShift, AKeyChar);
      end;
    pjpOverwriteAsk:
      // Dialog owns input; Esc cancels the whole job.
      HandleAskEscapeKeys(AKey, AKeyChar,
        procedure
        begin
          ResolveOverwriteAsk(jcaCancel, False);
        end);
    pjpDeleteAsk:
      HandleAskEscapeKeys(AKey, AKeyChar,
        procedure
        begin
          ResolveDeleteAsk(jdaCancel);
        end);
    pjpIOErrorAsk:
      HandleAskEscapeKeys(AKey, AKeyChar,
        procedure
        begin
          ResolveIOErrorAsk(jioCancel);
        end);
    pjpError:
      begin
        if FJob.Presentation = jpBackground then
          Exit(False);
        HandleErrorKeys(AKey, AKeyChar);
      end;
  else
    Result := False;
  end;
end;

end.
