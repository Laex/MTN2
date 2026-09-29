unit TestIOErrorAskDialog;

{ Regression: a copy/move job that hits an I/O error (a file another process
  has locked, disk full, etc.) on one item must offer the user a
  Retry/Skip/Skip all/Cancel choice (TPanelJobController.PromptIOErrorAsk /
  ResolveIOErrorAsk) instead of always aborting the whole job the moment the
  automatic retry budget (RetryLeft, 0 unless the job confirm dialog's Retry
  dropdown was raised) runs out - see HandleTransferFailure.

  Also covers the reason this dialog is useful: PendingSrcURI /
  the "path" shown in the dialog must name the one file that failed (via
  AError.URI), not the top-level job source: CopyFileWithProgress
  (uFileVfs.pas) attributes an I/O error in a recursive tree copy to the
  file it happened on. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIOErrorAskDialog = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestSkipPastLockedFile;
    [Test] procedure TestSkipAllSuppressesFurtherPrompts;
    [Test] procedure TestRetrySucceedsAfterObstructionCleared;
    [Test] procedure TestCancelEndsJobWithoutRollback;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileVfs,
  uZipVfs,
  uFindSession,
  uFindVfs,
  uVfsRegistry,
  uVfsRouter,
  uDualPanelUiTypes,
  uDualPanelJobs;

var
  GRoot: string;

procedure WriteTextFile(const APath, AContent: string);
begin
  TFile.WriteAllText(APath, AContent, TEncoding.ASCII);
end;

function ReadTextFile(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath, TEncoding.ASCII);
end;

{ ---- job-controller level, driven exactly like the panel does (F5) --------- }

type
  /// <summary>Callback invoked synchronously each time PromptIOErrorAsk opens
  /// (the panel's real popup, here simulated) - records what was shown and
  /// decides how to answer it via AJobs.ResolveIOErrorAsk.</summary>
  TIOErrorAskHandler = reference to procedure(AJobs: TPanelJobController;
    const AHeadline, APath, AErrorLine: string);

function RunJobCopy(const ASources: TArray<string>; const ADestDirURI: string;
  const AHandler: TIOErrorAskHandler; out APromptCount: Integer;
  out ALastHeadline, ALastPath, ALastErrorLine: string): Boolean;
var
  Jobs: TPanelJobController;
  Done: Boolean;
  Ok: Boolean;
  Tick: Cardinal;
  PromptCount: Integer;
  LastHeadline, LastPath, LastErrorLine: string;
begin
  Done := False;
  Ok := False;
  PromptCount := 0;
  LastHeadline := '';
  LastPath := '';
  LastErrorLine := '';
  Jobs := TPanelJobController.Create(nil, CreateDefaultVfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string)
    begin
      Inc(PromptCount);
      LastHeadline := AHeadline;
      LastPath := APath;
      LastErrorLine := AErrorLine;
      AHandler(Jobs, AHeadline, APath, AErrorLine);
    end,
    procedure(ASucceeded: Boolean)
    begin
      Ok := ASucceeded;
      Done := True;
    end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end,
    nil);
  try
    Jobs.BeginJob(ASources, ADestDirURI, pjkCopy);
    Jobs.ApplyCopyMoveOptions(ADestDirURI, jomOverwrite, False);
    Jobs.ConfirmJob;

    Tick := GetTickCount;
    while not Done do
    begin
      CheckSynchronize(20);
      if GetTickCount - Tick > 30000 then
      begin
        Assert.Fail('job timed out');
        Exit(False);
      end;
    end;
    APromptCount := PromptCount;
    ALastHeadline := LastHeadline;
    ALastPath := LastPath;
    ALastErrorLine := LastErrorLine;
    Result := Ok;
  finally
    Jobs.Free;
  end;
end;

{ ---- an exclusively-locked source file: deterministic, no timing races ----- }

function LockExclusive(const APath: string): TFileStream;
begin
  // fmOpenRead, not fmCreate - the file already has fixture content; fmCreate
  // would truncate it before CopyFileWithProgress ever gets a chance to fail.
  Result := TFileStream.Create(APath, fmOpenRead or fmShareExclusive);
end;

{ ---- fixtures --------------------------------------------------------------- }

procedure MakeThreeFileFixture(const AName: string; out ASrcDir, ADstDir,
  ALockedPath: string);
begin
  ASrcDir := TPath.Combine(GRoot, AName + '_src');
  ADstDir := TPath.Combine(GRoot, AName + '_dst');
  TDirectory.CreateDirectory(ASrcDir);
  TDirectory.CreateDirectory(ADstDir);
  WriteTextFile(TPath.Combine(ASrcDir, 'a_before.txt'), 'before');
  ALockedPath := TPath.Combine(ASrcDir, 'b_locked.bin');
  WriteTextFile(ALockedPath, 'locked-content');
  WriteTextFile(TPath.Combine(ASrcDir, 'c_after.txt'), 'after');
end;

function SourceUris(const ADir: string; const ANames: array of string): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(ANames));
  for I := 0 to High(ANames) do
    Result[I] := PathToFileUri(TPath.Combine(ADir, ANames[I]));
end;

{ ---- tests ------------------------------------------------------------------ }

procedure TestSkipPastLockedFile;
var
  SrcDir, DstDir, LockedPath: string;
  Hold: TFileStream;
  Ok: Boolean;
  Prompts: Integer;
  Headline, Path, ErrLine: string;
begin
  MakeThreeFileFixture('skip', SrcDir, DstDir, LockedPath);
  Hold := LockExclusive(LockedPath);
  try
    Ok := RunJobCopy(
      SourceUris(SrcDir, ['a_before.txt', 'b_locked.bin', 'c_after.txt']),
      PathToFileUri(DstDir),
      procedure(AJobs: TPanelJobController; const AHeadline, APath, AErrorLine: string)
      begin
        AJobs.ResolveIOErrorAsk(jioSkip);
      end,
      Prompts, Headline, Path, ErrLine);

    Assert.IsTrue(Ok, 'job finishes successfully (not aborted)');
    Assert.IsTrue(Prompts = 1, Format('exactly one prompt fired (was %d)', [Prompts]));
    Assert.IsTrue(Headline = 'Copy failed', 'headline names the operation ("' + Headline + '")');
    Assert.IsTrue(Pos('b_locked.bin', Path) > 0,
      'the dialog names the file that actually failed, not the job''s top-level '
      + 'source (was: ' + Path + ')');
    Assert.IsTrue(ErrLine <> '', 'an error line is shown');

    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'a_before.txt')),
      'item before the failing one was copied');
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'c_after.txt')),
      'item after the failing one was copied too (Skip does not abort the rest)');
    Assert.IsTrue(not TFile.Exists(TPath.Combine(DstDir, 'b_locked.bin')),
      'the skipped file itself was not copied');
  finally
    Hold.Free;
  end;
end;

procedure TestSkipAllSuppressesFurtherPrompts;
var
  SrcDir, DstDir, Locked1, Locked2: string;
  Hold1, Hold2: TFileStream;
  Ok: Boolean;
  Prompts: Integer;
  Headline, Path, ErrLine: string;
begin
  SrcDir := TPath.Combine(GRoot, 'skipall_src');
  DstDir := TPath.Combine(GRoot, 'skipall_dst');
  TDirectory.CreateDirectory(SrcDir);
  TDirectory.CreateDirectory(DstDir);
  Locked1 := TPath.Combine(SrcDir, 'locked1.bin');
  Locked2 := TPath.Combine(SrcDir, 'locked2.bin');
  WriteTextFile(Locked1, 'x');
  WriteTextFile(TPath.Combine(SrcDir, 'x_middle.txt'), 'middle');
  WriteTextFile(Locked2, 'y');
  WriteTextFile(TPath.Combine(SrcDir, 'y_last.txt'), 'last');

  Hold1 := LockExclusive(Locked1);
  Hold2 := LockExclusive(Locked2);
  try
    Ok := RunJobCopy(
      SourceUris(SrcDir, ['locked1.bin', 'x_middle.txt', 'locked2.bin', 'y_last.txt']),
      PathToFileUri(DstDir),
      procedure(AJobs: TPanelJobController; const AHeadline, APath, AErrorLine: string)
      begin
        AJobs.ResolveIOErrorAsk(jioSkipAll);
      end,
      Prompts, Headline, Path, ErrLine);

    Assert.IsTrue(Ok, 'job finishes successfully');
    Assert.IsTrue(Prompts = 1,
      Format('only the first failure prompts — the second locked file is skipped '
        + 'silently (was %d prompts)', [Prompts]));
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'x_middle.txt')),
      'file between the two failures was copied');
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'y_last.txt')),
      'file after both failures was copied');
    Assert.IsTrue(not TFile.Exists(TPath.Combine(DstDir, 'locked1.bin')),
      'first locked file was not copied');
    Assert.IsTrue(not TFile.Exists(TPath.Combine(DstDir, 'locked2.bin')),
      'second locked file was not copied either');
  finally
    Hold1.Free;
    Hold2.Free;
  end;
end;

procedure TestRetrySucceedsAfterObstructionCleared;
var
  SrcDir, DstDir, LockedPath: string;
  Hold: TFileStream;
  Ok: Boolean;
  Prompts: Integer;
  Headline, Path, ErrLine: string;
begin
  MakeThreeFileFixture('retry', SrcDir, DstDir, LockedPath);
  Hold := LockExclusive(LockedPath);
  try
    Ok := RunJobCopy(
      SourceUris(SrcDir, ['a_before.txt', 'b_locked.bin', 'c_after.txt']),
      PathToFileUri(DstDir),
      procedure(AJobs: TPanelJobController; const AHeadline, APath, AErrorLine: string)
      begin
        // Release the lock right before answering Retry - mirrors a user who
        // closed the other program and then clicked Retry.
        FreeAndNil(Hold);
        AJobs.ResolveIOErrorAsk(jioRetry);
      end,
      Prompts, Headline, Path, ErrLine);

    Assert.IsTrue(Ok, 'job finishes successfully after Retry');
    Assert.IsTrue(Prompts = 1, Format('exactly one prompt fired (was %d)', [Prompts]));
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'b_locked.bin')) and
      (ReadTextFile(TPath.Combine(DstDir, 'b_locked.bin')) = 'locked-content'),
      'the retried file was copied once the obstruction was gone');
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'c_after.txt')),
      'the rest of the job continued after the retried item finished');
  finally
    Hold.Free; // no-op if already freed inside the handler
  end;
end;

procedure TestCancelEndsJobWithoutRollback;
var
  SrcDir, DstDir, LockedPath: string;
  Hold: TFileStream;
  Ok: Boolean;
  Prompts: Integer;
  Headline, Path, ErrLine: string;
begin
  MakeThreeFileFixture('cancel', SrcDir, DstDir, LockedPath);
  Hold := LockExclusive(LockedPath);
  try
    Ok := RunJobCopy(
      SourceUris(SrcDir, ['a_before.txt', 'b_locked.bin', 'c_after.txt']),
      PathToFileUri(DstDir),
      procedure(AJobs: TPanelJobController; const AHeadline, APath, AErrorLine: string)
      begin
        AJobs.ResolveIOErrorAsk(jioCancel);
      end,
      Prompts, Headline, Path, ErrLine);

    Assert.IsTrue(not Ok, 'job reports failure (cancelled), not success');
    Assert.IsTrue(Prompts = 1, Format('exactly one prompt fired (was %d)', [Prompts]));
    Assert.IsTrue(TFile.Exists(TPath.Combine(DstDir, 'a_before.txt')),
      'the item already copied before Cancel was pressed is kept, not rolled back');
    Assert.IsTrue(not TFile.Exists(TPath.Combine(DstDir, 'c_after.txt')),
      'the item after the cancelled one was never reached');
  finally
    Hold.Free;
  end;
end;

{ TTestIOErrorAskDialog }

procedure TTestIOErrorAskDialog.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestIOErrorAskDialog');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestIOErrorAskDialog.TearDownFixture;
begin
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestIOErrorAskDialog.TestSkipPastLockedFile;
begin
  TestIOErrorAskDialog.TestSkipPastLockedFile;
end;

procedure TTestIOErrorAskDialog.TestSkipAllSuppressesFurtherPrompts;
begin
  TestIOErrorAskDialog.TestSkipAllSuppressesFurtherPrompts;
end;

procedure TTestIOErrorAskDialog.TestRetrySucceedsAfterObstructionCleared;
begin
  TestIOErrorAskDialog.TestRetrySucceedsAfterObstructionCleared;
end;

procedure TTestIOErrorAskDialog.TestCancelEndsJobWithoutRollback;
begin
  TestIOErrorAskDialog.TestCancelEndsJobWithoutRollback;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIOErrorAskDialog);

end.
