program TestDualPanelJobRules;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDialogTypes in '..\Core\uDialogTypes.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelJobRules in '..\Core\uDualPanelJobRules.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

function FileJob(const ASrc, ADst: string): TPanelJobState;
begin
  Result := Default(TPanelJobState);
  Result.Phase := pjpRunning;
  Result.Kind := pjkCopy;
  Result.Presentation := jpBackground;
  Result.Sources := TArray<string>.Create(ASrc);
  Result.DestDirURI := ADst;
  Result.OriginSrcDirURI := JobOriginSrcDir(Result.Sources);
  Result.OriginDstDirURI := ADst;
  Result.FilesDone := 2;
  Result.FilesTotal := 5;
  Result.BytesDoneBase := 34;
  Result.BytesTotal := 100;
end;

procedure TestPredicates;
var
  S: TPanelJobState;
begin
  Writeln('Predicates');
  S := Default(TPanelJobState);
  Expect(not JobOwnsInput(S), 'idle does not own input');
  Expect(not JobBlocksNewOperation(S), 'idle does not block new op');
  Expect(not JobShowsOverlay(S), 'idle has no overlay');

  S.Phase := pjpRunning;
  S.Presentation := jpForeground;
  Expect(JobOwnsInput(S), 'fg running owns input');
  Expect(JobBlocksNewOperation(S), 'fg running blocks new op');
  Expect(not JobShowsOverlay(S), 'fg running uses JSON dialog not overlay');
  Expect(JobWantsProgressDialog(S), 'fg running wants progress dialog');
  Expect(JobBlocksPanelInput(S), 'fg running blocks panel clicks');

  S.Presentation := jpBackground;
  Expect(not JobOwnsInput(S), 'bg running does not own input');
  Expect(not JobBlocksNewOperation(S), 'bg running allows new op');
  Expect(not JobShowsOverlay(S), 'bg running hides overlay');
  Expect(not JobWantsProgressDialog(S), 'bg running has no progress dialog');

  S.Phase := pjpOverwriteAsk;
  S.Presentation := jpBackground;
  Expect(JobOwnsInput(S), 'ask owns input even if bg');
  Expect(JobBlocksNewOperation(S), 'ask blocks new op');
  Expect(not JobShowsOverlay(S), 'ask uses dialog not overlay');

  S.Phase := pjpQueued;
  Expect(not JobBlocksNewOperation(S), 'queued does not block new op');
  Expect(not JobOwnsInput(S), 'queued does not own input');

  S.Phase := pjpConfirm;
  Expect(JobBlocksNewOperation(S), 'confirm blocks new op');
  Expect(not JobOwnsInput(S), 'confirm leaves keys to dialog');

  Expect(CanStartAnotherJob(0), 'empty list can start');
  Expect(CanStartAnotherJob(7), '7 jobs can start');
  Expect(not CanStartAnotherJob(8), '8 jobs is the cap');
end;

procedure TestConfirmCommand;
begin
  Writeln('Confirm command');
  Expect(JobConfirmWantsBackground(cDlgCmdBackground), 'background id');
  Expect(not JobConfirmWantsBackground(cDlgCmdOk), 'ok is not background');
  Expect(not JobConfirmWantsBackground(cDlgCmdCancel), 'cancel is not background');
end;

procedure TestParallel;
var
  A, B: TPanelJobState;
begin
  Writeln('CanRunParallel');
  A := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  B := FileJob('file:///E:/other/b.txt', 'file:///F:/out/');
  Expect(CanRunParallel(A, B), 'two disjoint file:// jobs parallel');

  B := FileJob('file:///C:/src/a.txt', 'file:///F:/out/');
  Expect(not CanRunParallel(A, B), 'same source URI queues');

  B := FileJob('file:///C:/src/sub/x.txt', 'file:///F:/out/');
  Expect(not CanRunParallel(A, B), 'source under other src dir queues');

  B := FileJob('file:///E:/other/b.txt', 'file:///D:/dst/');
  Expect(not CanRunParallel(A, B), 'same dest dir queues');

  A := FileJob('file:///C:/pack.zip!/inner/a.txt', 'file:///D:/dst/');
  B := FileJob('file:///C:/pack.zip!/inner/b.txt', 'file:///E:/out/');
  Expect(not CanRunParallel(A, B), 'same zip archive queues');

  A := FileJob('7z:///C:/a.7z!/x', 'file:///D:/dst/');
  B := FileJob('7z:///C:/a.7z!/y', 'file:///E:/out/');
  Expect(not CanRunParallel(A, B), 'same 7z archive queues');

  A := FileJob('sftp://u@h/a', 'file:///D:/dst/');
  B := FileJob('sftp://u@h/b', 'file:///E:/out/');
  Expect(not CanRunParallel(A, B), 'same sftp authority queues');

  B := FileJob('sftp://u@other/b', 'file:///E:/out/');
  Expect(CanRunParallel(A, B), 'different sftp hosts parallel');
end;

procedure TestProgressFields;
var
  S: TPanelJobState;
  Bar: string;
  Snap: TJobProgressSnapshot;
begin
  Writeln('Progress fields');
  S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  S.Presentation := jpForeground;
  S.CurrentSrcPath := 'C:\src\a.txt';
  S.CurrentDstPath := 'D:\dst\a.txt';
  S.FileProgressDone := 50;
  S.FileProgressTotal := 100;
  Expect(JobProgressVerb(pjkCopy) = 'Copying the file', 'copy verb');
  Expect(JobProgressVerb(pjkMove) = 'Moving the file', 'move verb');
  Expect(JobFilePercent(S) = 50, 'file percent');
  Expect(JobProgressPercent(S) = 34, 'total percent from bytes');
  Expect(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESS', 'copy resource');
  Snap := BuildJobProgressSnapshot(S, 72);
  Expect((not Snap.IsError) and (Snap.Verb = 'Copying the file'), 'copy snapshot verb');
  Expect(Pos('50%', Snap.FileBar) > 0, 'snapshot file bar');
  S.Kind := pjkDelete;
  Expect(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESSDELETE', 'delete resource');
  S.Phase := pjpError;
  S.Message := '';
  Expect(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESSERROR', 'error resource');
  Snap := BuildJobProgressSnapshot(S, 72);
  Expect(Snap.IsError and (Snap.Message = 'Error'), 'empty error snapshot');
  Bar := FormatJobProgressBar(20, 50);
  Expect(Pos('50%', Bar) > 0, 'bar shows percent');
  Expect(Length(Bar) = 20, 'bar fills requested width');
  Expect(Pos('1 234 567', JobProgressCountLine('Files:', 1234567, 10000000, 40)) > 0,
    'thousands grouped');
  Expect(Pos('10 000 000', JobProgressCountLine('Files:', 1234567, 10000000, 40)) > 0,
    'ten million grouped');
  Expect(Pos('12 / 34', JobProgressCountLine('Files:', 12, 34, 40)) > 0,
    'small counts ungrouped');
end;

procedure TestStatusAndOrigin;
var
  S: TPanelJobState;
begin
  Writeln('Status / origin');
  S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  Expect(Pos('Copy 2/5', FormatJobProgressLine(S)) > 0, 'progress line has counts');
  Expect(Pos('34%', FormatJobProgressLine(S)) > 0, 'progress line has percent');
  Expect(Pos('2 jobs', FormatJobListStatus(2, S, False)) > 0, 'multi-job status');
  Expect(Pos('Ask', FormatJobListStatus(1, S, True)) > 0, 'ask suffix');
  Expect(JobOriginSrcDir(TArray<string>.Create('file:///C:/src/a.txt')) <> '',
    'origin src from parent');
  Expect(JobReloadTouchesUri('file:///C:/src', 'file:///C:/src'),
    'same URI reloads');
  Expect(JobReloadTouchesUri('file:///C:/src/', 'file:///C:/src'),
    'trailing slash still reloads');
  Expect(JobReloadTouchesUri('file:///C:/src', 'file:///C:/src/file.txt'),
    'panel is parent of origin file');
  Expect(JobReloadTouchesUri('file:///C:/src/sub', 'file:///C:/src'),
    'child of origin reloads');
  Expect(not JobReloadTouchesUri('file:///E:/elsewhere', 'file:///C:/src'),
    'unrelated URI does not reload');
  Expect(not JobReloadTouchesUri('file:///C:/src', ''),
    'empty origin does not match');
end;

begin
  try
    TestPredicates;
    TestConfirmCommand;
    TestProgressFields;
    TestParallel;
    TestStatusAndOrigin;
    Writeln('All DualPanelJobRules tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
