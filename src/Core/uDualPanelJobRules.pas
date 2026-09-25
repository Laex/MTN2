unit uDualPanelJobRules;

{ Pure job-UI predicates and conflict rules. No FMX — used by Dual Panel
  and by console tests. }

interface

uses
  System.SysUtils, System.Math,
  uDualPanelUiTypes, uTerminalTypes, uVfsTypes;

const
  cMaxPanelJobs = 8;

function JobKindTitle(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): string;
function JobOwnsInput(const AJob: TPanelJobState): Boolean;
function JobBlocksPanelInput(const AJob: TPanelJobState): Boolean;
function JobBlocksNewOperation(const AJob: TPanelJobState): Boolean;
function JobShowsOverlay(const AJob: TPanelJobState): Boolean;
function JobWantsProgressDialog(const AJob: TPanelJobState): Boolean;
function JobProgressResourceName(const AJob: TPanelJobState): string;
function FormatJobProgressBar(AWidth, APct: Integer): string;
function JobProgressSrcLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
function JobProgressDstLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
function JobProgressVerb(AKind: TPanelJobKind): string;
function JobProgressCountLine(const ALabel: string; ADone, ATotal: Int64;
  AInnerW: Integer): string;
function JobFilePercent(const AJob: TPanelJobState): Integer;
function JobDeletePercent(const AJob: TPanelJobState): Integer;
function JobIsAskPhase(APhase: TPanelJobPhase): Boolean;
function JobIsBusy(const AJob: TPanelJobState): Boolean;
function JobProgressPercent(const AJob: TPanelJobState): Integer;
function FormatJobProgressLine(const AJob: TPanelJobState): string;
function FormatJobListStatus(ACount: Integer; const ALead: TPanelJobState;
  AHasAsk: Boolean): string;
function FormatJobListLine(const AJob: TPanelJobState): string;

function JobOriginSrcDir(const ASources: TArray<string>): string;
function JobOriginDstDir(const ADestDirURI: string;
  const ADestURIs: TArray<string>): string;
function JobReloadTouchesUri(const APanelUri, AOriginUri: string): Boolean;
function UriIsSameOrAncestor(const AMaybeAncestor, AUri: string): Boolean;

function JobArchiveKey(const AURI: string): string;
function JobSftpAuthority(const AURI: string): string;
function JobUrisOverlap(const A, B: string): Boolean;
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
    Bytes: string;
    TotalBar: string;
  end;

function BuildJobProgressSnapshot(const AJob: TPanelJobState;
  AInnerW: Integer): TJobProgressSnapshot;

implementation

uses
  uDialogTypes, uDialogResources;

function JobKindTitle(AKind: TPanelJobKind; ADeleteToRecycleBin: Boolean): string;
begin
  case AKind of
    pjkCopy: Result := 'Copy';
    pjkMove: Result := 'Move';
    pjkPack: Result := 'Pack';
    pjkUnpack: Result := 'Unpack';
    pjkDelete:
      if ADeleteToRecycleBin then
        Result := 'Recycle'
      else
        Result := 'Delete';
  else
    Result := 'Job';
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

function BuildJobProgressSnapshot(const AJob: TPanelJobState;
  AInnerW: Integer): TJobProgressSnapshot;
var
  FilesDone, FilesTotal: Integer;
  BytesNow, BytesTot: Int64;
  InnerW: Integer;
begin
  InnerW := Max(AInnerW, 8);
  Result := Default(TJobProgressSnapshot);
  Result.Title := JobKindTitle(AJob.Kind, AJob.DeleteToRecycleBin);
  if AJob.Phase = pjpError then
  begin
    Result.IsError := True;
    Result.Message := AJob.Message;
    if Result.Message = '' then
      Result.Message := 'Error';
    Exit;
  end;
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
  Result.Files := JobProgressCountLine('Files:', FilesDone, FilesTotal, InnerW);
  BytesNow := AJob.BytesDoneBase + AJob.ProgressDone;
  BytesTot := AJob.BytesTotal;
  if BytesTot < BytesNow then
    BytesTot := BytesNow;
  Result.Bytes := JobProgressCountLine('Bytes:', BytesNow, BytesTot, InnerW);
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
    pjkMove: Result := 'Moving the file';
    pjkPack: Result := 'Packing';
    pjkUnpack: Result := 'Unpacking';
    pjkDelete: Result := 'Deleting';
  else
    Result := 'Copying the file';
  end;
end;

function JobProgressSrcLine(const AJob: TPanelJobState; AMaxLen: Integer): string;
begin
  Result := AJob.CurrentSrcPath;
  if Result = '' then
    Result := AJob.CurrentName;
  if Result = '' then
    Result := Format('Item %d/%d', [AJob.Index + 1, Length(AJob.Sources)]);
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
  if AJob.ProgressTotal > 0 then
    Result := EnsureRange(Round(100 * AJob.ProgressDone / AJob.ProgressTotal), 0, 100)
  else if AJob.FilesTotal > 0 then
    Result := EnsureRange(Round(100 * (AJob.Index + 1) / AJob.FilesTotal), 0, 100)
  else
    Result := 0;
end;

function JobProgressPercent(const AJob: TPanelJobState): Integer;
var
  Done, Total: Int64;
begin
  Result := 0;
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

function FormatJobProgressLine(const AJob: TPanelJobState): string;
var
  Title: string;
  FilesDone, FilesTotal, Pct: Integer;
begin
  Title := JobKindTitle(AJob.Kind, AJob.DeleteToRecycleBin);
  FilesDone := AJob.FilesDone;
  FilesTotal := AJob.FilesTotal;
  if FilesTotal < 1 then
    FilesTotal := Length(AJob.Sources);
  if FilesTotal < 1 then
    FilesTotal := 1;
  if FilesDone < 0 then
    FilesDone := 0;
  Pct := JobProgressPercent(AJob);
  Result := Format('%s %d/%d · %d%%', [Title, FilesDone, FilesTotal, Pct]);
end;

function FormatJobListStatus(ACount: Integer; const ALead: TPanelJobState;
  AHasAsk: Boolean): string;
begin
  Result := '';
  if ACount <= 0 then
    Exit;
  if ACount = 1 then
    Result := FormatJobProgressLine(ALead)
  else
    Result := Format('%d jobs · %s %d%%', [ACount,
      JobKindTitle(ALead.Kind, ALead.DeleteToRecycleBin),
      JobProgressPercent(ALead)]);
  if AHasAsk then
    Result := Result + ' · Ask';
end;

function FormatJobListLine(const AJob: TPanelJobState): string;
var
  Phase: string;
begin
  case AJob.Phase of
    pjpQueued: Phase := 'queued';
    pjpConfirm: Phase := 'confirm';
    pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk: Phase := 'ask';
    pjpError: Phase := 'error';
    pjpRunning:
      if AJob.Presentation = jpBackground then
        Phase := 'bg'
      else
        Phase := 'fg';
  else
    Phase := '';
  end;
  Result := FormatJobProgressLine(AJob);
  if AJob.CurrentName <> '' then
    Result := Result + '  ' + AJob.CurrentName;
  if Phase <> '' then
    Result := Result + '  [' + Phase + ']';
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
    Base := ArchiveBaseLocalPath(AURI);
    if Base = '' then
      Base := AURI;
    Exit('7z:' + LowerCase(Base));
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

function CollectJobTouchUris(const AJob: TPanelJobState): TArray<string>;
var
  N, I: Integer;
begin
  N := Length(AJob.Sources) + Length(AJob.DestURIs) + 3;
  SetLength(Result, N);
  N := 0;
  for I := 0 to High(AJob.Sources) do
    if AJob.Sources[I] <> '' then
    begin
      Result[N] := AJob.Sources[I];
      Inc(N);
    end;
  for I := 0 to High(AJob.DestURIs) do
    if AJob.DestURIs[I] <> '' then
    begin
      Result[N] := AJob.DestURIs[I];
      Inc(N);
    end;
  if AJob.DestDirURI <> '' then
  begin
    Result[N] := AJob.DestDirURI;
    Inc(N);
  end;
  if AJob.OriginSrcDirURI <> '' then
  begin
    Result[N] := AJob.OriginSrcDirURI;
    Inc(N);
  end;
  if AJob.OriginDstDirURI <> '' then
  begin
    Result[N] := AJob.OriginDstDirURI;
    Inc(N);
  end;
  SetLength(Result, N);
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
