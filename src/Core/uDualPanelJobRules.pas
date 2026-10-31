unit uDualPanelJobRules;

{ Pure job-UI predicates and conflict rules. No FMX - used by Dual Panel
  and by console tests. }

interface

uses
  System.SysUtils, System.Math,
  uDualPanelUiTypes, uTerminalTypes, uVfsTypes;

const
  cMaxPanelJobs = 8;

function JobKindTitle(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): string;
/// <summary>One cell that tells the operations apart: copy, move, recycle,
/// permanent delete, pack, unpack. Used by the tab bar chips and the job list.</summary>
function JobKindGlyph(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): Char;
function JobOwnsInput(const AJob: TPanelJobState): Boolean;
function JobBlocksPanelInput(const AJob: TPanelJobState): Boolean;
function JobBlocksNewOperation(const AJob: TPanelJobState): Boolean;
function JobShowsOverlay(const AJob: TPanelJobState): Boolean;
function JobWantsProgressDialog(const AJob: TPanelJobState): Boolean;
function JobProgressResourceName(const AJob: TPanelJobState): string;
function FormatJobProgressBar(AWidth, APct: Integer): string;
function JobProgressSrcLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
function JobProgressDstLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
/// <summary>The question for deleting one item split in three: the words
/// before the name, the quoted name, the words after it ("Move file", "name" in
/// quotes, "to Recycle Bin?"). False when ASource has no name.</summary>
function JobDeleteOneParts(const ASource: string; ARecycle: Boolean;
  out APrefix, AName, ASuffix: string): Boolean;
function JobProgressVerb(AKind: TPanelJobKind): string;
function JobProgressCountLine(const ALabel: string; ADone, ATotal: Int64;
  AInnerW: Integer): string;
function JobFilePercent(const AJob: TPanelJobState): Integer;
function JobDeletePercent(const AJob: TPanelJobState): Integer;
function JobIsAskPhase(APhase: TPanelJobPhase): Boolean;
function JobIsBusy(const AJob: TPanelJobState): Boolean;
function JobProgressPercent(const AJob: TPanelJobState): Integer;
function FormatJobProgressLine(const AJob: TPanelJobState): string;

const
  /// <summary>Widths of the job list columns (task, item, files, percent,
  /// state); the dialog's header text in each language pads its titles to the
  /// same widths.</summary>
  cJobListTaskW = 13;
  cJobListItemW = 23;
  cJobListFilesW = 11;
  cJobListPctW = 4;
  cJobListStateW = 12;

/// <summary>One row of the background jobs list: the columns above, one space apart.</summary>
function FormatJobListLine(const AJob: TPanelJobState): string;

type
  TJobTaskbarState = (jtsNone, jtsIndeterminate, jtsNormal, jtsPaused, jtsError);

/// <summary>What the application's taskbar button shows for the jobs in AJobs:
/// a job waiting for an answer is "paused", a failed one "error", running ones
/// "normal" with their mean percent in APercent, queued ones only "indeterminate".
/// Jobs still on their confirm dialog count for nothing.</summary>
function JobTaskbarProgress(const AJobs: TArray<TPanelJobState>;
  out APercent: Integer): TJobTaskbarState;

function JobOriginSrcDir(const ASources: TArray<string>): string;
function JobOriginDstDir(const ADestDirURI: string;
  const ADestURIs: TArray<string>): string;
function JobReloadTouchesUri(const APanelUri, AOriginUri: string): Boolean;
function UriIsSameOrAncestor(const AMaybeAncestor, AUri: string): Boolean;

function JobArchiveKey(const AURI: string): string;
function JobSftpAuthority(const AURI: string): string;
function JobUrisOverlap(const A, B: string): Boolean;
function CollectJobTouchUris(const AJob: TPanelJobState): TArray<string>;
/// <summary>Items the job itself processes (sources and explicit targets),
/// without the panel directories it was started from.</summary>
function CollectJobItemUris(const AJob: TPanelJobState): TArray<string>;
function CanRunParallel(const ANew, AExisting: TPanelJobState): Boolean;

function CanStartAnotherJob(ABusyCount: Integer): Boolean;
function JobConfirmWantsBackground(const AControlId: string): Boolean;

type
  TJobProgressSnapshot = record
    Title: string;
    IsError: Boolean;
    Message: string;
    Verb: string;
    Src: string;
    Dst: string;
    FileBar: string;
    Files: string;
    /// <summary>"Skipped: N" for a copy or move, empty for other jobs.</summary>
    Skipped: string;
    Bytes: string;
    TotalBar: string;
  end;

function BuildJobProgressSnapshot(const AJob: TPanelJobState;
  AInnerW: Integer): TJobProgressSnapshot;

implementation

uses
  System.IOUtils, uDialogTypes, uDialogResources, uStrings;

function JobDeleteOneParts(const ASource: string; ARecycle: Boolean;
  out APrefix, AName, ASuffix: string): Boolean;
var
  Path, Kind, Text, Open, Close: string;
  P: Integer;
begin
  AName := FileUriTitle(ASource);
  if (AName <> '') and (AName[Length(AName)] = '/') then
    Delete(AName, Length(AName), 1);
  APrefix := '';
  ASuffix := '';
  Result := AName <> '';
  if not Result then
    Exit;
  Path := FileUriToPath(ASource);
  if HasArchiveChain(ASource) or (Path = '') then
    Kind := T('ui.job.kindItem', 'item')
  else if TDirectory.Exists(WinApiPath(Path)) then
    Kind := T('ui.job.kindFolder', 'folder')
  else
    Kind := T('ui.job.kindFile', 'file');
  if ARecycle then
    Text := T('ui.job.confirmRecycleOne', 'Move %s "%s" to Recycle Bin?', [Kind, '%s'])
  else
    Text := T('ui.job.confirmDeletePermanentOne', 'Permanently delete %s "%s"?', [Kind, '%s']);
  P := Pos('%s', Text);
  if P = 0 then
  begin
    APrefix := Text;
    Exit;
  end;
  APrefix := Copy(Text, 1, P - 1);
  ASuffix := Copy(Text, P + 2, MaxInt);
  Open := '';
  Close := '';
  if (APrefix <> '') and CharInSet(APrefix[Length(APrefix)], ['"', '`', #$00AB]) then
  begin
    Open := APrefix[Length(APrefix)];
    Delete(APrefix, Length(APrefix), 1);
  end;
  if (ASuffix <> '') and CharInSet(ASuffix[1], ['"', '`', #$00BB]) then
  begin
    Close := ASuffix[1];
    Delete(ASuffix, 1, 1);
  end;
  APrefix := Trim(APrefix);
  ASuffix := Trim(ASuffix);
  AName := Open + AName + Close;
end;

function JobKindTitle(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): string;
begin
  case AKind of
    pjkCopy: Result := T('ui.job.titleCopy', 'Copy');
    pjkMove: Result := T('ui.job.titleMove', 'Move');
    pjkPack: Result := T('ui.job.titlePack', 'Pack');
    pjkUnpack: Result := T('ui.job.titleUnpack', 'Unpack');
    pjkDelete:
      if ADeleteToRecycleBin then
        Result := T('ui.job.titleRecycle', 'Recycle')
      else
        Result := T('ui.job.titleDelete', 'Delete');
  else
    Result := T('ui.job.titleGeneric', 'Job');
  end;
end;

function JobKindGlyph(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): Char;
begin
  case AKind of
    pjkCopy: Result := #$00BB;
    pjkMove: Result := #$25BA;
    pjkPack: Result := #$25A0;
    pjkUnpack: Result := #$25A1;
    pjkDelete:
      if ADeleteToRecycleBin then
        Result := #$25BC
      else
        Result := #$203C;
  else
    Result := '?';
  end;
end;

function JobIsAskPhase(APhase: TPanelJobPhase): Boolean;
begin
  Result := APhase in [pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk];
end;

function JobIsBusy(const AJob: TPanelJobState): Boolean;
begin
  Result := AJob.Phase <> pjpNone;
end;

function JobOwnsInput(const AJob: TPanelJobState): Boolean;
begin
  if JobIsAskPhase(AJob.Phase) then
    Exit(True);
  if AJob.Phase in [pjpRunning, pjpError] then
    Exit(AJob.Presentation = jpForeground);
  Result := False;
end;

function JobBlocksPanelInput(const AJob: TPanelJobState): Boolean;
begin
  Result := JobOwnsInput(AJob);
end;

function JobBlocksNewOperation(const AJob: TPanelJobState): Boolean;
begin
  case AJob.Phase of
    pjpNone, pjpQueued:
      Result := False;
    pjpConfirm:
      Result := True;
    pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk:
      Result := True;
    pjpRunning, pjpError:
      Result := AJob.Presentation = jpForeground;
  else
    Result := True;
  end;
end;

function JobShowsOverlay(const AJob: TPanelJobState): Boolean;
begin
  { Overlay retired: F5/F6/F8 progress is hdkJobProgress (JSON). }
  Result := False;
end;

function JobWantsProgressDialog(const AJob: TPanelJobState): Boolean;
begin
  Result := (AJob.Phase in [pjpRunning, pjpError]) and
    (AJob.Presentation = jpForeground);
end;

function JobProgressResourceName(const AJob: TPanelJobState): string;
begin
  if AJob.Phase = pjpError then
    Result := cResDialogJobProgressError
  else if AJob.Kind = pjkDelete then
    Result := cResDialogJobProgressDelete
  else
    Result := cResDialogJobProgress;
end;

function FormatJobGroupedInt64(AValue: Int64): string;
var
  S: string;
  I, Digits, OutLen, J: Integer;
begin
  if AValue < 0 then
    AValue := 0;
  S := IntToStr(AValue);
  Digits := Length(S);
  OutLen := Digits + (Digits - 1) div 3;
  SetLength(Result, OutLen);
  J := OutLen;
  for I := Digits downto 1 do
  begin
    Result[J] := S[I];
    Dec(J);
    if ((Digits - I + 1) mod 3 = 0) and (I > 1) then
    begin
      Result[J] := ' ';
      Dec(J);
    end;
  end;
end;

// "Preparing to delete... 1:23": the text plus the time spent, once it is
// long enough to matter.
function JobScanVerb(const AText: string; AElapsedSec: Integer): string;
begin
  if AElapsedSec < 1 then
    Result := AText
  else
    Result := Format('%s %d:%.2d', [AText, AElapsedSec div 60, AElapsedSec mod 60]);
end;

function BuildJobProgressSnapshot(const AJob: TPanelJobState;
  AInnerW: Integer): TJobProgressSnapshot;
var
  FilesDone, FilesTotal: Integer;
  BytesNow, BytesTot: Int64;
  InnerW: Integer;
  SkippedLabel, SkippedValue: string;
begin
  InnerW := Max(AInnerW, 8);
  Result := Default(TJobProgressSnapshot);
  Result.Title := JobKindTitle(AJob.Kind, AJob.DeleteToRecycleBin);
  if AJob.Phase = pjpError then
  begin
    Result.IsError := True;
    Result.Message := AJob.Message;
    if Result.Message = '' then
      Result.Message := T('ui.job.error', 'Error');
    Exit;
  end;
  // The worker stops at its next cancellation check, which can take a while
  // on a large file; the dialog says so instead of looking like it still works.
  if Assigned(AJob.Cancel) and AJob.Cancel.IsCancellationRequested then
    Result.Verb := T('ui.job.cancelling', 'Cancelling...')
  else if AJob.Scanning and (AJob.Kind = pjkDelete) and AJob.DeleteToRecycleBin then
    Result.Verb := JobScanVerb(T('ui.job.preparingDelete', 'Preparing to delete...'),
      AJob.ScanElapsedSec)
  else if AJob.Scanning then
    Result.Verb := JobScanVerb(T('ui.job.scanning', 'Scanning the folder'),
      AJob.ScanElapsedSec)
  else
    Result.Verb := JobProgressVerb(AJob.Kind);
  Result.Src := JobProgressSrcLine(AJob, InnerW);
  Result.Dst := JobProgressDstLine(AJob, InnerW);
  if AJob.Kind = pjkDelete then
    Result.FileBar := FormatJobProgressBar(InnerW, JobDeletePercent(AJob))
  else
    Result.FileBar := FormatJobProgressBar(InnerW, JobFilePercent(AJob));
  FilesTotal := AJob.FilesTotal;
  if FilesTotal < 1 then
    FilesTotal := Length(AJob.Sources);
  FilesDone := EnsureRange(AJob.FilesDone, 0, FilesTotal);
  Result.Files := JobProgressCountLine(T('ui.job.filesLabel', 'Files:'), FilesDone, FilesTotal, InnerW);
  if AJob.Kind in [pjkCopy, pjkMove] then
  begin
    SkippedLabel := T('ui.job.skippedLabel', 'Skipped:');
    SkippedValue := FormatJobGroupedInt64(Max(AJob.FilesSkipped, 0));
    Result.Skipped := SkippedLabel + StringOfChar(' ',
      Max(InnerW - Length(SkippedLabel) - Length(SkippedValue), 1)) + SkippedValue;
  end;
  BytesNow := AJob.BytesDoneBase + AJob.ProgressDone;
  BytesTot := AJob.BytesTotal;
  if BytesTot < BytesNow then
    BytesTot := BytesNow;
  Result.Bytes := JobProgressCountLine(T('ui.job.bytesLabel', 'Bytes:'), BytesNow, BytesTot, InnerW);
  Result.TotalBar := FormatJobProgressBar(InnerW, JobProgressPercent(AJob));
end;

function JobEllipsizeLeft(const AText: string; AMaxLen: Integer): string;
begin
  if AMaxLen < 1 then
    Exit('');
  if Length(AText) <= AMaxLen then
    Exit(AText);
  if AMaxLen <= 2 then
    Exit(Copy(AText, 1, AMaxLen));
  Result := '..' + Copy(AText, Length(AText) - (AMaxLen - 2) + 1, AMaxLen - 2);
end;

function FormatJobProgressBar(AWidth, APct: Integer): string;
var
  Pct: Integer;
  PctStr: string;
  BarW, FillW: Integer;
begin
  Pct := EnsureRange(APct, 0, 100);
  PctStr := Format('%3d%%', [Pct]);
  BarW := Max(AWidth - Length(PctStr) - 1, 4);
  FillW := EnsureRange(Round(BarW * Pct / 100), 0, BarW);
  Result := StringOfChar(chBlock, FillW) + StringOfChar(chShadeLight, BarW - FillW) +
    ' ' + PctStr;
end;

function JobProgressVerb(AKind: TPanelJobKind): string;
begin
  case AKind of
    pjkMove: Result := T('ui.job.verbMove', 'Moving the file');
    pjkPack: Result := T('ui.job.verbPack', 'Packing');
    pjkUnpack: Result := T('ui.job.verbUnpack', 'Unpacking');
    pjkDelete: Result := T('ui.job.verbDelete', 'Deleting');
  else
    Result := T('ui.job.verbCopy', 'Copying the file');
  end;
end;

function JobProgressSrcLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
begin
  Result := AJob.CurrentSrcPath;
  if Result = '' then
    Result := AJob.CurrentName;
  if Result = '' then
    Result := Format(T('ui.job.itemOf', 'Item %d/%d'),
      [AJob.Index + 1, Length(AJob.Sources)]);
  Result := JobEllipsizeLeft(Result, AMaxLen);
end;

function JobProgressDstLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
begin
  Result := AJob.CurrentDstPath;
  if Result = '' then
  begin
    Result := FileUriToPath(AJob.DestDirURI);
    if Result = '' then
      Result := VfsUriTitle(AJob.DestDirURI);
  end;
  Result := JobEllipsizeLeft(Result, AMaxLen);
end;

function JobProgressCountLine(const ALabel: string; ADone, ATotal: Int64;
  AInnerW: Integer): string;
var
  Right: string;
begin
  Right := Format('%s / %s', [FormatJobGroupedInt64(ADone), FormatJobGroupedInt64(ATotal)]);
  Result := ALabel + StringOfChar(' ', Max(AInnerW - Length(ALabel) - Length(Right), 1)) +
    Right;
  if Length(Result) > AInnerW then
    Result := Copy(Result, 1, AInnerW);
end;

function JobFilePercent(const AJob: TPanelJobState): Integer;
begin
  if AJob.FileProgressTotal > 0 then
    Result := EnsureRange(Round(100 * AJob.FileProgressDone / AJob.FileProgressTotal), 0, 100)
  else
    Result := 0;
end;

function JobDeletePercent(const AJob: TPanelJobState): Integer;
begin
  // While the next item is being read the item counters still hold the
  // previous item's values; the finished items are all there is to show.
  if (AJob.ProgressTotal > 0) and not AJob.Scanning then
    Result := EnsureRange(Round(100 * AJob.ProgressDone / AJob.ProgressTotal), 0, 100)
  else if AJob.FilesTotal > 0 then
    // Items finished so far: the one being deleted is not done yet.
    Result := EnsureRange(Round(100 * AJob.Index / AJob.FilesTotal), 0, 100)
  else
    Result := 0;
end;

function JobProgressPercent(const AJob: TPanelJobState): Integer;
var
  Done, Total: Int64;
begin
  Result := 0;
  // Delete reports each removed file and folder, not bytes: count those.
  if AJob.Kind = pjkDelete then
  begin
    if AJob.FilesTotal > 0 then
      Result := EnsureRange(Integer(Int64(AJob.FilesDone) * 100 div AJob.FilesTotal), 0, 100);
    Exit;
  end;
  Total := AJob.BytesTotal;
  Done := AJob.BytesDoneBase + AJob.ProgressDone;
  if Total > 0 then
  begin
    if Done < 0 then
      Done := 0;
    if Done > Total then
      Done := Total;
    Result := Integer((Done * 100) div Total);
    Exit;
  end;
  if AJob.FilesTotal > 0 then
  begin
    Done := AJob.FilesDone;
    if Done < 0 then
      Done := 0;
    if Done > AJob.FilesTotal then
      Done := AJob.FilesTotal;
    Result := Integer((Done * 100) div AJob.FilesTotal);
  end;
end;

function JobTaskbarProgress(const AJobs: TArray<TPanelJobState>;
  out APercent: Integer): TJobTaskbarState;
var
  Job: TPanelJobState;
  Running, Sum: Integer;
  HasAsk, HasError, HasQueued: Boolean;
begin
  Running := 0;
  Sum := 0;
  HasAsk := False;
  HasError := False;
  HasQueued := False;
  for Job in AJobs do
    case Job.Phase of
      pjpRunning:
        begin
          Inc(Running);
          Inc(Sum, JobProgressPercent(Job));
        end;
      pjpQueued:
        HasQueued := True;
      pjpError:
        HasError := True;
      pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk:
        HasAsk := True;
    end;
  if Running > 0 then
    APercent := Sum div Running
  else
    APercent := 0;
  if HasAsk then
    Result := jtsPaused
  else if HasError then
    Result := jtsError
  else if Running > 0 then
    Result := jtsNormal
  else if HasQueued then
    Result := jtsIndeterminate
  else
    Result := jtsNone;
end;

procedure JobFileCounts(const AJob: TPanelJobState; out ADone, ATotal: Integer);
begin
  ADone := AJob.FilesDone;
  ATotal := AJob.FilesTotal;
  if ATotal < 1 then
    ATotal := Length(AJob.Sources);
  if ATotal < 1 then
    ATotal := 1;
  if ADone < 0 then
    ADone := 0;
  // Until the background count lands the total is only the selected items;
  // never show more done than there is in all.
  if ADone > ATotal then
    ATotal := ADone;
end;

function FormatJobProgressLine(const AJob: TPanelJobState): string;
var
  FilesDone, FilesTotal: Integer;
begin
  JobFileCounts(AJob, FilesDone, FilesTotal);
  Result := Format('%s %d/%d '#$00B7' %d%%',
    [JobKindTitle(AJob.Kind, AJob.DeleteToRecycleBin), FilesDone, FilesTotal,
     JobProgressPercent(AJob)]);
end;

function JobListCell(const AText: string; AWidth: Integer; ARightAlign: Boolean): string;
var
  Text: string;
begin
  Text := AText;
  if Length(Text) > AWidth then
    Text := Copy(Text, 1, Max(AWidth - 2, 0)) + Copy('..', 1, Min(AWidth, 2));
  if ARightAlign then
    Result := StringOfChar(' ', AWidth - Length(Text)) + Text
  else
    Result := Text + StringOfChar(' ', AWidth - Length(Text));
end;

function JobListStateText(const AJob: TPanelJobState): string;
begin
  case AJob.Phase of
    pjpQueued: Result := T('ui.job.stateQueued', 'queued');
    pjpConfirm: Result := T('ui.job.stateConfirm', 'confirm');
    pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk:
      Result := T('ui.job.stateAsk', 'question');
    pjpError: Result := T('ui.job.stateError', 'error');
    pjpRunning:
      if AJob.Presentation = jpBackground then
        Result := T('ui.job.stateBackground', 'background')
      else
        Result := T('ui.job.stateForeground', 'foreground');
  else
    Result := '';
  end;
end;

function FormatJobListLine(const AJob: TPanelJobState): string;
var
  Item: string;
  FilesDone, FilesTotal: Integer;
begin
  Item := AJob.CurrentName;
  if (Item = '') and (AJob.Index >= 0) and (AJob.Index <= High(AJob.Sources)) then
    Item := FileUriTitle(AJob.Sources[AJob.Index]);
  JobFileCounts(AJob, FilesDone, FilesTotal);
  Result :=
    JobListCell(JobKindGlyph(AJob.Kind, AJob.DeleteToRecycleBin) + ' ' +
      JobKindTitle(AJob.Kind, AJob.DeleteToRecycleBin), cJobListTaskW, False) + ' ' +
    JobListCell(Item, cJobListItemW, False) + ' ' +
    JobListCell(Format('%d/%d', [FilesDone, FilesTotal]), cJobListFilesW, True) + ' ' +
    JobListCell(Format('%d%%', [JobProgressPercent(AJob)]), cJobListPctW, True) + ' ' +
    JobListCell(JobListStateText(AJob), cJobListStateW, False);
end;

function JobOriginSrcDir(const ASources: TArray<string>): string;
begin
  Result := '';
  if Length(ASources) = 0 then
    Exit;
  Result := ParentVfsUri(ASources[0]);
  if Result = '' then
    Result := ASources[0];
end;

function JobOriginDstDir(const ADestDirURI: string;
  const ADestURIs: TArray<string>): string;
begin
  Result := Trim(ADestDirURI);
  if Result <> '' then
    Exit;
  if Length(ADestURIs) = 0 then
    Exit('');
  Result := ParentVfsUri(ADestURIs[0]);
  if Result = '' then
    Result := ADestURIs[0];
end;

function UriIsSameOrAncestor(const AMaybeAncestor, AUri: string): Boolean;
var
  Cur, Prev: string;
begin
  Result := False;
  if (AMaybeAncestor = '') or (AUri = '') then
    Exit;
  if SameVfsUri(AMaybeAncestor, AUri) then
    Exit(True);
  Cur := AUri;
  while True do
  begin
    Prev := Cur;
    Cur := ParentVfsUri(Cur);
    if (Cur = '') or SameVfsUri(Cur, Prev) then
      Exit(False);
    if SameVfsUri(Cur, AMaybeAncestor) then
      Exit(True);
  end;
end;

function JobReloadTouchesUri(const APanelUri, AOriginUri: string): Boolean;
var
  Panel, Origin: string;
begin
  Result := False;
  if (APanelUri = '') or (AOriginUri = '') then
    Exit;
  Panel := ResolveVfsUri(APanelUri);
  Origin := ResolveVfsUri(AOriginUri);
  Result := SameVfsUri(Panel, Origin) or
    UriIsSameOrAncestor(Panel, Origin) or
    UriIsSameOrAncestor(Origin, Panel);
end;

function JobArchiveKey(const AURI: string): string;
var
  Base: string;
  Segs: TArray<string>;
begin
  Result := '';
  if AURI = '' then
    Exit;
  if IsSevenZipUri(AURI) then
  begin
    // Entries of one archive are told apart only after the first '!', so the
    // part before it identifies the archive.
    Base := AURI;
    if Pos('!', Base) > 0 then
      Base := Copy(Base, 1, Pos('!', Base) - 1);
    Exit('7z:' + LowerCase(ArchiveBaseLocalPath(Base)));
  end;
  if HasArchiveChain(AURI) then
  begin
    if SplitArchiveUri(AURI, Base, Segs) and (Base <> '') then
      Exit('zip:' + LowerCase(Base));
    Base := ArchiveBasePath(AURI);
    if Base <> '' then
      Exit('zip:' + LowerCase(Base));
  end;
end;

function JobSftpAuthority(const AURI: string): string;
begin
  if IsSftpUri(AURI) then
    Result := LowerCase(SftpAuthorityOf(AURI))
  else
    Result := '';
end;

function JobUrisOverlap(const A, B: string): Boolean;
begin
  Result := False;
  if (A = '') or (B = '') then
    Exit;
  Result := SameVfsUri(A, B) or UriIsSameOrAncestor(A, B) or
    UriIsSameOrAncestor(B, A);
end;

function CollectJobItemUris(const AJob: TPanelJobState): TArray<string>;
var
  Uri: string;
begin
  Result := nil;
  for Uri in AJob.Sources do
    if Uri <> '' then
      Result := Result + [Uri];
  for Uri in AJob.DestURIs do
    if Uri <> '' then
      Result := Result + [Uri];
end;

function CollectJobTouchUris(const AJob: TPanelJobState): TArray<string>;
begin
  Result := CollectJobItemUris(AJob);
  if AJob.DestDirURI <> '' then
    Result := Result + [AJob.DestDirURI];
end;

function FirstArchiveKey(const AUris: TArray<string>): string;
var
  I: Integer;
begin
  for I := 0 to High(AUris) do
  begin
    Result := JobArchiveKey(AUris[I]);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;

function FirstSftpAuthority(const AUris: TArray<string>): string;
var
  I: Integer;
begin
  for I := 0 to High(AUris) do
  begin
    Result := JobSftpAuthority(AUris[I]);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;

function CanRunParallel(const ANew, AExisting: TPanelJobState): Boolean;
var
  NewUris, OldUris: TArray<string>;
  I, J: Integer;
  NewKey, OldKey, NewAuth, OldAuth: string;
begin
  if not JobIsBusy(AExisting) then
    Exit(True);
  if AExisting.Phase in [pjpNone, pjpConfirm] then
    Exit(True);

  NewUris := CollectJobTouchUris(ANew);
  OldUris := CollectJobTouchUris(AExisting);
  for I := 0 to High(NewUris) do
    for J := 0 to High(OldUris) do
      if JobUrisOverlap(NewUris[I], OldUris[J]) then
        Exit(False);

  NewKey := FirstArchiveKey(NewUris);
  OldKey := FirstArchiveKey(OldUris);
  if (NewKey <> '') and (NewKey = OldKey) then
    Exit(False);

  NewAuth := FirstSftpAuthority(NewUris);
  OldAuth := FirstSftpAuthority(OldUris);
  if (NewAuth <> '') and (NewAuth = OldAuth) then
    Exit(False);

  Result := True;
end;

function CanStartAnotherJob(ABusyCount: Integer): Boolean;
begin
  Result := ABusyCount < cMaxPanelJobs;
end;

function JobConfirmWantsBackground(const AControlId: string): Boolean;
begin
  Result := DialogCmdIs(AControlId, cDlgCmdBackground);
end;

end.
