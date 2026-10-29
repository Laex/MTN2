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
    [Test] procedure TestItemUrisIgnorePanelDirs;
    [Test] procedure TestDeletePreparing;
    [Test] procedure TestProgressTextIsTranslated;
    [Test] procedure TestStatusAndOrigin;
    [Test] procedure TestDeleteOneParts;
    [Test] procedure TestTaskbarProgress;
  end;

implementation

uses
  System.SysUtils,
  uStrings,
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

procedure TestItemUrisIgnorePanelDirs;
var
  Del: TPanelJobState;
  Items: TArray<string>;
begin
  Del := FileJob('file:///O:/Old/', '');
  Del.Kind := pjkDelete;
  Assert.IsTrue(Del.OriginSrcDirURI <> '', 'origin dir recorded');
  Items := CollectJobItemUris(Del);
  Assert.AreEqual(1, Integer(Length(Items)), 'only the source is an item');
  Assert.IsTrue(not JobUrisOverlap('file:///O:/Other/', Items[0]),
    'sibling of a deleted folder is not covered by the delete job');
  Assert.IsTrue(JobUrisOverlap('file:///O:/Old/sub/', Items[0]),
    'content of a deleted folder is covered');
end;

procedure TestProgressTextIsTranslated;
var
  S: TPanelJobState;
  Snap: TJobProgressSnapshot;
begin
  SetLocale('ru');
  try
    S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
    S.Presentation := jpForeground;
    Snap := BuildJobProgressSnapshot(S, 72);
    Assert.AreNotEqual('Copy', Snap.Title, 'copy title follows the language');
    Assert.AreEqual(T('ui.job.titleCopy', 'Copy'), Snap.Title, 'copy title is the pack text');
    Assert.AreNotEqual('Copying the file', Snap.Verb, 'copy verb follows the language');
    Assert.AreEqual(T('ui.job.verbCopy', 'Copying the file'), Snap.Verb,
      'copy verb is the pack text');
    Assert.IsTrue(Pos('Files:', Snap.Files) = 0, 'files label follows the language');
    Assert.IsTrue(Pos('Bytes:', Snap.Bytes) = 0, 'bytes label follows the language');
    S.Kind := pjkDelete;
    Assert.AreNotEqual('Recycle', BuildJobProgressSnapshot(S, 72).Title,
      'recycle title follows the language');
    S.Scanning := True;
    Assert.IsTrue(Pos('Preparing', BuildJobProgressSnapshot(S, 72).Verb) = 0,
      'preparing text follows the language');
  finally
    SetLocale('en');
  end;
end;

procedure TestDeletePreparing;
var
  S: TPanelJobState;
  Snap: TJobProgressSnapshot;
begin
  S := FileJob('file:///O:/Old/', '');
  S.Kind := pjkDelete;
  S.Presentation := jpForeground;
  S.FilesTotal := 1;
  S.Index := 0;
  Assert.AreEqual(0, JobDeletePercent(S), 'the only item is not done before it ends');
  S.FilesTotal := 4;
  S.Index := 2;
  Assert.AreEqual(50, JobDeletePercent(S), 'finished items drive the delete bar');
  S.Scanning := True;
  S.CurrentSrcPath := 'O:\Old';
  S.ProgressTotal := 100;
  S.ProgressDone := 100;
  Assert.AreEqual(50, JobDeletePercent(S),
    'while the next item is read the finished items show, not the last item');
  S.Index := 0;
  Assert.AreEqual(0, JobDeletePercent(S), 'nothing finished yet');
  S.ProgressTotal := 0;
  S.ProgressDone := 0;
  S.DeleteToRecycleBin := False;
  Snap := BuildJobProgressSnapshot(S, 72);
  Assert.IsTrue(Pos('Preparing', Snap.Verb) = 0,
    'a permanent delete only counts items, it does not wait for the Shell');
  Assert.IsTrue(Pos(T('ui.job.scanning', 'Scanning the folder'), Snap.Verb) = 1,
    'a permanent delete reads the tree');
  S.DeleteToRecycleBin := True;
  Snap := BuildJobProgressSnapshot(S, 72);
  Assert.IsTrue(Snap.Verb <> JobProgressVerb(pjkDelete), 'preparing replaces the verb');
  Assert.IsTrue(Pos('O:\Old', Snap.Src) > 0, 'the item being prepared is shown');
  Assert.IsTrue(Pos('0:', Snap.Verb) = 0, 'no clock before a second has passed');
  S.ScanElapsedSec := 83;
  Assert.IsTrue(Pos('1:23', BuildJobProgressSnapshot(S, 72).Verb) > 0,
    'the elapsed time shows while preparing');
  S.Scanning := False;
  Assert.AreEqual(JobProgressVerb(pjkDelete), BuildJobProgressSnapshot(S, 72).Verb,
    'the verb returns once progress is reported');
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
  Assert.IsTrue(CanRunParallel(A, B), 'the directory a job was started from is not locked');

  A := FileJob('file:///C:/src/dir/', 'file:///D:/dst/');
  B := FileJob('file:///C:/src/dir/x.txt', 'file:///F:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'source inside the folder of a running job queues');
  B := FileJob('file:///C:/src/', 'file:///F:/out/');
  Assert.IsTrue(not CanRunParallel(A, B), 'folder containing the folder of a running job queues');
  B := FileJob('file:///C:/src/other/', 'file:///F:/out/');
  Assert.IsTrue(CanRunParallel(A, B), 'sibling folder runs in parallel');
  A := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');

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
  S.Cancel := TJobCancelToken.Create;
  Assert.IsTrue(BuildJobProgressSnapshot(S, 72).Verb = 'Copying the file',
    'a job nobody asked to stop keeps its verb');
  S.Cancel.Cancel;
  Snap := BuildJobProgressSnapshot(S, 72);
  Assert.IsTrue((Snap.Verb <> '') and (Snap.Verb <> 'Copying the file'),
    'a stop request replaces the verb until the worker finishes');
  S.Cancel := nil;
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
  Line: string;
begin
  S := FileJob('file:///C:/src/a.txt', 'file:///D:/dst/');
  Assert.IsTrue(Pos('Copy 2/5', FormatJobProgressLine(S)) > 0, 'progress line has counts');
  Assert.IsTrue(Pos('34%', FormatJobProgressLine(S)) > 0, 'progress line has percent');
  Assert.IsTrue(Pos(' '#$00B7' ', FormatJobProgressLine(S)) > 0,
    'the separator is a middle dot, not a mis-decoded byte pair');
  Assert.IsTrue(Pos(JobKindGlyph(pjkCopy, False) + ' Copy ', FormatJobListLine(S)) = 1,
    'list line starts with the operation glyph');
  Line := FormatJobListLine(S);
  Assert.AreEqual(cJobListTaskW + cJobListItemW + cJobListFilesW + cJobListPctW +
    cJobListStateW + 4, Length(Line), 'every list line is as wide as its columns');
  Assert.AreEqual('2/5', Trim(Copy(Line, cJobListTaskW + cJobListItemW + 3,
    cJobListFilesW)), 'files column');
  Assert.AreEqual('34%', Trim(Copy(Line, cJobListTaskW + cJobListItemW +
    cJobListFilesW + 4, cJobListPctW)), 'percent column');
  Assert.AreEqual('a.txt', Trim(Copy(Line, cJobListTaskW + 2, cJobListItemW)),
    'item column shows the source name until a file reports');
  S.CurrentName := StringOfChar('x', 60);
  Assert.AreEqual(Length(Line), Length(FormatJobListLine(S)),
    'a long name is cut to its column');

  // Delete before the background count lands: five removed inside one
  // selected folder never reads "5/1"; the percent counts removed items.
  S := Default(TPanelJobState);
  S.Kind := pjkDelete;
  S.Sources := ['file:///C:/big'];
  S.FilesTotal := 1;
  S.FilesDone := 5;
  S.BytesTotal := 1000;
  Assert.IsTrue(Pos('Delete 5/5', FormatJobProgressLine(S)) > 0,
    'done never above the total: ' + FormatJobProgressLine(S));
  S.FilesTotal := 20;
  Assert.AreEqual(25, JobProgressPercent(S), 'delete percent from items, not bytes');
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

procedure TTestDualPanelJobRules.TestItemUrisIgnorePanelDirs;
begin
  TestDualPanelJobRules.TestItemUrisIgnorePanelDirs;
end;

procedure TTestDualPanelJobRules.TestDeletePreparing;
begin
  TestDualPanelJobRules.TestDeletePreparing;
end;

procedure TTestDualPanelJobRules.TestProgressTextIsTranslated;
begin
  TestDualPanelJobRules.TestProgressTextIsTranslated;
end;

procedure TTestDualPanelJobRules.TestStatusAndOrigin;
begin
  TestDualPanelJobRules.TestStatusAndOrigin;
end;

procedure TTestDualPanelJobRules.TestDeleteOneParts;
var
  Prefix, Name, Suffix: string;
begin
  Assert.IsTrue(JobDeleteOneParts('file:///C:/NoSuchDir/a b.zip', True, Prefix, Name, Suffix));
  Assert.IsTrue(Pos('a b.zip', Name) > 0, 'name line holds the name');
  Assert.IsTrue(Pos('%s', Prefix + Name + Suffix) = 0, 'no placeholder left');
  Assert.IsTrue((Prefix <> '') and (Suffix <> ''), 'words around the name');
  Assert.IsTrue(Pos('a b.zip', Prefix + Suffix) = 0, 'name only on its own line');
  Assert.IsFalse(JobDeleteOneParts('', False, Prefix, Name, Suffix), 'no name');
end;

procedure TTestDualPanelJobRules.TestTaskbarProgress;
var
  Jobs: TArray<TPanelJobState>;
  A, B: TPanelJobState;
  Pct: Integer;
begin
  Assert.IsTrue(JobTaskbarProgress(nil, Pct) = jtsNone, 'no jobs');

  A := FileJob('file:///C:/src/a.txt', 'file:///C:/dst');
  Jobs := [A];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsNormal, 'running job');
  Assert.AreEqual(34, Pct, 'percent of the job');

  B := A;
  B.Id := 2;
  B.BytesDoneBase := 66;
  Jobs := [A, B];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsNormal, 'two running jobs');
  Assert.AreEqual(50, Pct, 'mean percent of running jobs');

  B.Phase := pjpQueued;
  Jobs := [B];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsIndeterminate, 'only queued');

  B.Phase := pjpConfirm;
  Jobs := [B];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsNone, 'confirm dialog only');

  B.Phase := pjpError;
  Jobs := [A, B];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsError, 'failed job');

  B.Phase := pjpOverwriteAsk;
  Jobs := [A, B];
  Assert.IsTrue(JobTaskbarProgress(Jobs, Pct) = jtsPaused, 'waiting for an answer');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelJobRules);

end.
