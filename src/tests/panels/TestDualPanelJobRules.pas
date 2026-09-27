unit TestDualPanelJobRules;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelJobRules = class
  public
    [Test] procedure TestPredicates;
    [Test] procedure TestConfirmCommand;
    [Test] procedure TestProgressFields;
    [Test] procedure TestParallel;
    [Test] procedure TestStatusAndOrigin;
  end;

implementation

uses
  System.SysUtils,
  uDialogTypes,
  uVfsTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelJobRules;

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
  S := Default(TPanelJobState);
  Assert.IsTrue(not JobOwnsInput(S), 'idle does not own input');
  Assert.IsTrue(not JobBlocksNewOperation(S), 'idle does not block new op');
  Assert.IsTrue(not JobShowsOverlay(S), 'idle has no overlay');

  S.Phase := pjpRunning;
  S.Presentation := jpForeground;
  Assert.IsTrue(JobOwnsInput(S), 'fg running owns input');
  Assert.IsTrue(JobBlocksNewOperation(S), 'fg running blocks new op');
  Assert.IsTrue(not JobShowsOverlay(S), 'fg running uses JSON dialog not overlay');
  Assert.IsTrue(JobWantsProgressDialog(S), 'fg running wants progress dialog');
  Assert.IsTrue(JobBlocksPanelInput(S), 'fg running blocks panel clicks');

  S.Presentation := jpBackground;
  Assert.IsTrue(not JobOwnsInput(S), 'bg running does not own input');
  Assert.IsTrue(not JobBlocksNewOperation(S), 'bg running allows new op');
  Assert.IsTrue(not JobShowsOverlay(S), 'bg running hides overlay');
  Assert.IsTrue(not JobWantsProgressDialog(S), 'bg running has no progress dialog');

  S.Phase := pjpOverwriteAsk;
  S.Presentation := jpBackground;
  Assert.IsTrue(JobOwnsInput(S), 'ask owns input even if bg');
  Assert.IsTrue(JobBlocksNewOperation(S), 'ask blocks new op');
  Assert.IsTrue(not JobShowsOverlay(S), 'ask uses dialog not overlay');

  S.Phase := pjpQueued;
  Assert.IsTrue(not JobBlocksNewOperation(S), 'queued does not block new op');
  Assert.IsTrue(not JobOwnsInput(S), 'queued does not own input');

  S.Phase := pjpConfirm;
  Assert.IsTrue(JobBlocksNewOperation(S), 'confirm blocks new op');
  Assert.IsTrue(not JobOwnsInput(S), 'confirm leaves keys to dialog');

  Assert.IsTrue(CanStartAnotherJob(0), 'empty list can start');
  Assert.IsTrue(CanStartAnotherJob(7), '7 jobs can start');
  Assert.IsTrue(not CanStartAnotherJob(8), '8 jobs is the cap');
end;

procedure TestConfirmCommand;
begin
  Assert.IsTrue(JobConfirmWantsBackground(cDlgCmdBackground), 'background id');
  Assert.IsTrue(not JobConfirmWantsBackground(cDlgCmdOk), 'ok is not background');
  Assert.IsTrue(not JobConfirmWantsBackground(cDlgCmdCancel), 'cancel is not background');
end;

procedure TestParallel;
var
  A, B: TPanelJobState;
begin
  A := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  B := FileJob('file:///E:/other/b.txt', 'file:///F:/out/');
  Assert.IsTrue(CanRunParallel(A, B), 'two disjoint file:// jobs parallel');

  B := FileJob('file:///C:/src/a.txt', 'file:///F:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'same source URI queues');

  B := FileJob('file:///C:/src/sub/x.txt', 'file:///F:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'source under other src dir queues');

  B := FileJob('file:///E:/other/b.txt', 'file:///D:/dst/');
  Assert.IsTrue(not CanRunParallel(A, B), 'same dest dir queues');

  A := FileJob('file:///C:/pack.zip!/inner/a.txt', 'file:///D:/dst/');
  B := FileJob('file:///C:/pack.zip!/inner/b.txt', 'file:///E:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'same zip archive queues');

  A := FileJob('7z:///C:/a.7z!/x', 'file:///D:/dst/');
  B := FileJob('7z:///C:/a.7z!/y', 'file:///E:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'same 7z archive queues');

  A := FileJob('sftp://u@h/a', 'file:///D:/dst/');
  B := FileJob('sftp://u@h/b', 'file:///E:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'same sftp authority queues');

  B := FileJob('sftp://u@other/b', 'file:///E:/out/');
  Assert.IsTrue(CanRunParallel(A, B), 'different sftp hosts parallel');
end;

procedure TestProgressFields;
var
  S: TPanelJobState;
  Bar: string;
  Snap: TJobProgressSnapshot;
begin
  S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  S.Presentation := jpForeground;
  S.CurrentSrcPath := 'C:\src\a.txt';
  S.CurrentDstPath := 'D:\dst\a.txt';
  S.FileProgressDone := 50;
  S.FileProgressTotal := 100;
  Assert.IsTrue(JobProgressVerb(pjkCopy) = 'Copying the file', 'copy verb');
  Assert.IsTrue(JobProgressVerb(pjkMove) = 'Moving the file', 'move verb');
  Assert.IsTrue(JobFilePercent(S) = 50, 'file percent');
  Assert.IsTrue(JobProgressPercent(S) = 34, 'total percent from bytes');
  Assert.IsTrue(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESS', 'copy resource');
  Snap := BuildJobProgressSnapshot(S, 72);
  Assert.IsTrue((not Snap.IsError) and (Snap.Verb = 'Copying the file'), 'copy snapshot verb');
  Assert.IsTrue(Pos('50%', Snap.FileBar) > 0, 'snapshot file bar');
  S.Kind := pjkDelete;
  Assert.IsTrue(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESSDELETE', 'delete resource');
  S.Phase := pjpError;
  S.Message := '';
  Assert.IsTrue(JobProgressResourceName(S) = 'DIALOG_JOBPROGRESSERROR', 'error resource');
  Snap := BuildJobProgressSnapshot(S, 72);
  Assert.IsTrue(Snap.IsError and (Snap.Message = 'Error'), 'empty error snapshot');
  Bar := FormatJobProgressBar(20, 50);
  Assert.IsTrue(Pos('50%', Bar) > 0, 'bar shows percent');
  Assert.IsTrue(Length(Bar) = 20, 'bar fills requested width');
  Assert.IsTrue(Pos('1 234 567', JobProgressCountLine('Files:', 1234567, 10000000, 40)) > 0,
    'thousands grouped');
  Assert.IsTrue(Pos('10 000 000', JobProgressCountLine('Files:', 1234567, 10000000, 40)) > 0,
    'ten million grouped');
  Assert.IsTrue(Pos('12 / 34', JobProgressCountLine('Files:', 12, 34, 40)) > 0,
    'small counts ungrouped');
end;

procedure TestStatusAndOrigin;
var
  S: TPanelJobState;
begin
  S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  Assert.IsTrue(Pos('Copy 2/5', FormatJobProgressLine(S)) > 0, 'progress line has counts');
  Assert.IsTrue(Pos('34%', FormatJobProgressLine(S)) > 0, 'progress line has percent');
  Assert.IsTrue(Pos('2 jobs', FormatJobListStatus(2, S, False)) > 0, 'multi-job status');
  Assert.IsTrue(Pos('Ask', FormatJobListStatus(1, S, True)) > 0, 'ask suffix');
  Assert.IsTrue(JobOriginSrcDir(TArray<string>.Create('file:///C:/src/a.txt')) <> '',
    'origin src from parent');
  Assert.IsTrue(JobReloadTouchesUri('file:///C:/src', 'file:///C:/src'),
    'same URI reloads');
  Assert.IsTrue(JobReloadTouchesUri('file:///C:/src/', 'file:///C:/src'),
    'trailing slash still reloads');
  Assert.IsTrue(JobReloadTouchesUri('file:///C:/src', 'file:///C:/src/file.txt'),
    'panel is parent of origin file');
  Assert.IsTrue(JobReloadTouchesUri('file:///C:/src/sub', 'file:///C:/src'),
    'child of origin reloads');
  Assert.IsTrue(not JobReloadTouchesUri('file:///E:/elsewhere', 'file:///C:/src'),
    'unrelated URI does not reload');
  Assert.IsTrue(not JobReloadTouchesUri('file:///C:/src', ''),
    'empty origin does not match');
end;

{ TTestDualPanelJobRules }

procedure TTestDualPanelJobRules.TestPredicates;
begin
  TestDualPanelJobRules.TestPredicates;
end;

procedure TTestDualPanelJobRules.TestConfirmCommand;
begin
  TestDualPanelJobRules.TestConfirmCommand;
end;

procedure TTestDualPanelJobRules.TestProgressFields;
begin
  TestDualPanelJobRules.TestProgressFields;
end;

procedure TTestDualPanelJobRules.TestParallel;
begin
  TestDualPanelJobRules.TestParallel;
end;

procedure TTestDualPanelJobRules.TestStatusAndOrigin;
begin
  TestDualPanelJobRules.TestStatusAndOrigin;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelJobRules);

end.
