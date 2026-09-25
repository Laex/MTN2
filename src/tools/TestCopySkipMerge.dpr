program TestCopySkipMerge;

{ Regression: recursive copy/move into an already-existing destination folder
  with OverwriteMode=Skip must merge — copy every source file missing at the
  destination and leave existing destination files untouched — instead of
  bailing out at the first "already exists" the way TDualPanelWindow's
  ExecuteTransfer(..., FJob.OverwriteMode <> jomSkip, ...) drives CopyAsync.

  Root cause was in uFileVfs.pas's CopyTree: it treated "destination
  directory already exists" as a hard conflict (same class of check as a
  colliding file), so the very first recursive call — the top-level
  destination folder itself, in the reported scenario — aborted the whole
  tree copy before touching a single file. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas',
  uZipVfs in '..\Core\uZipVfs.pas',
  uFindSession in '..\Core\uFindSession.pas',
  uFindVfs in '..\Core\uFindVfs.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\Core\uVfsRouter.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelJobs in '..\Core\uDualPanelJobs.pas';

var
  GRoot: string;
  GFailures: Integer = 0;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Writeln('  [PASS] ', AWhat)
  else
  begin
    Writeln('  [FAIL] ', AWhat);
    Inc(GFailures);
  end;
end;

procedure WriteTextFile(const APath, AContent: string);
begin
  TFile.WriteAllText(APath, AContent, TEncoding.ASCII);
end;

function ReadTextFile(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath, TEncoding.ASCII);
end;

{ ---- async plumbing -------------------------------------------------------- }

function WaitEvent(AEv: TEvent; ATimeoutMs: Cardinal = 20000): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while AEv.WaitFor(20) <> wrSignaled do
  begin
    CheckSynchronize;
    if GetTickCount - Tick > ATimeoutMs then
      Exit(False);
  end;
  CheckSynchronize;
  Result := True;
end;

function RunCopy(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;
var
  Vfs: IVirtualFileSystem;
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
begin
  Vfs := CreateDefaultVfs;
  Ev := TEvent.Create(nil, True, False, '');
  try
    Ok := False;
    Err := TVfsError.Ok;
    Vfs.CopyAsync(PathToFileUri(ASrc), PathToFileUri(ADst), nil,
      procedure(const ADone, ATotal: Int64; const AName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string) begin end,
      procedure(const ASuccess: Boolean; const AErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AErr;
        Ev.SetEvent;
      end, AOverwrite, False);
    if not WaitEvent(Ev) then
    begin
      Writeln('  [FAIL] copy timed out');
      Inc(GFailures);
      Exit(False);
    end;
    AError := Err;
    Result := Ok;
  finally
    Ev.Free;
  end;
end;

{ ---- fixtures --------------------------------------------------------------- }

/// <summary>The reported scenario: source tree with 3 files, destination tree
/// that already exists and already has 1 of the 3 (with different content,
/// so an accidental overwrite would be detectable) plus one extra file the
/// merge must not touch.</summary>
procedure MakeMergeFixture(out ASrc, ADst: string);
begin
  ASrc := TPath.Combine(GRoot, 'src_tree');
  ADst := TPath.Combine(GRoot, 'dst_tree');
  TDirectory.CreateDirectory(ASrc);
  TDirectory.CreateDirectory(TPath.Combine(ASrc, 'sub'));
  WriteTextFile(TPath.Combine(ASrc, 'a.txt'), 'src-a');
  WriteTextFile(TPath.Combine(ASrc, 'b.txt'), 'src-b');
  WriteTextFile(TPath.Combine(ASrc, 'sub', 'c.txt'), 'src-c');

  // Destination already exists (this is exactly what made CopyTree bail
  // immediately, before the bug fix) and already has 'a.txt' with DIFFERENT
  // content than the source — Skip mode must leave it exactly as-is.
  TDirectory.CreateDirectory(ADst);
  WriteTextFile(TPath.Combine(ADst, 'a.txt'), 'dst-a-preexisting');
  WriteTextFile(TPath.Combine(ADst, 'unrelated.txt'), 'dst-only');
end;

{ ---- tests ------------------------------------------------------------------ }

procedure TestSkipMergesMissingFiles;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestSkipMergesMissingFiles (the reported bug)');
  MakeMergeFixture(Src, Dst);

  Ok := RunCopy(Src, Dst, False, Err);
  Check(Ok, 'copy reports success (not aborted at "already exists")');
  if not Ok then
    Writeln('    error: ', Err.Message);

  Check(TFile.Exists(TPath.Combine(Dst, 'b.txt')),
    'b.txt (missing at destination) was copied');
  Check(TFile.Exists(TPath.Combine(Dst, 'sub', 'c.txt')),
    'sub\c.txt (missing, nested) was copied');
  Check(ReadTextFile(TPath.Combine(Dst, 'b.txt')) = 'src-b',
    'b.txt content matches source');
  Check(ReadTextFile(TPath.Combine(Dst, 'sub', 'c.txt')) = 'src-c',
    'sub\c.txt content matches source');

  Check(ReadTextFile(TPath.Combine(Dst, 'a.txt')) = 'dst-a-preexisting',
    'a.txt (pre-existing, conflicting) was left untouched by Skip');
  Check(TFile.Exists(TPath.Combine(Dst, 'unrelated.txt')),
    'unrelated pre-existing destination file survives the merge');
end;

procedure TestOverwriteReplacesExisting;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestOverwriteReplacesExisting (control: Overwrite=True still overwrites)');
  MakeMergeFixture(Src, Dst);

  Ok := RunCopy(Src, Dst, True, Err);
  Check(Ok, 'copy reports success');

  Check(ReadTextFile(TPath.Combine(Dst, 'a.txt')) = 'src-a',
    'a.txt was overwritten with source content under Overwrite=True');
  Check(TFile.Exists(TPath.Combine(Dst, 'b.txt')) and
        (ReadTextFile(TPath.Combine(Dst, 'b.txt')) = 'src-b'),
    'b.txt copied too');
end;

procedure TestSkipNestedDirAlreadyExists;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestSkipNestedDirAlreadyExists (subdirectory, not just the top folder, already exists)');
  Src := TPath.Combine(GRoot, 'src_nested');
  Dst := TPath.Combine(GRoot, 'dst_nested');
  TDirectory.CreateDirectory(TPath.Combine(Src, 'sub'));
  WriteTextFile(TPath.Combine(Src, 'sub', 'new.txt'), 'fresh');
  WriteTextFile(TPath.Combine(Src, 'sub', 'old.txt'), 'src-old');
  // Dst does NOT exist yet, but its 'sub' equivalent will be created fresh by
  // the copy itself down one level — instead pre-seed a *second* copy run
  // into the same destination to prove re-running Skip against an already-
  // merged tree keeps working (the realistic "re-sync" workflow).
  Ok := RunCopy(Src, Dst, False, Err);
  Check(Ok, 'first pass copies the whole (new) tree');

  // Simulate the destination's copy of old.txt having been edited locally
  // after the first sync, then re-run the same Skip copy — a second pass
  // must still merge in anything new without touching the edited file.
  WriteTextFile(TPath.Combine(Dst, 'sub', 'old.txt'), 'locally-edited');
  WriteTextFile(TPath.Combine(Src, 'sub', 'second.txt'), 'second-pass-new');

  Ok := RunCopy(Src, Dst, False, Err);
  Check(Ok, 'second pass (re-sync into an existing, already-merged tree) succeeds');
  Check(TFile.Exists(TPath.Combine(Dst, 'sub', 'second.txt')),
    'file added to source between passes gets picked up on re-sync');
  Check(ReadTextFile(TPath.Combine(Dst, 'sub', 'old.txt')) = 'locally-edited',
    'locally-edited destination file survives the re-sync untouched');
end;

{ ---- job-controller level (what F5 actually drives) -------------------------- }

/// <summary>Run a real TPanelJobController copy the way the panel does:
/// BeginJob -> ApplyCopyMoveOptions(Skip) -> ConfirmJob, pumping the UI queue
/// until the finish callback fires. This is the layer the reported bug lived
/// in — CopyAsync alone never saw the folder because the controller skipped
/// the whole item before calling it.</summary>
function RunJobCopy(const ASrcDir, ADestParentDir: string;
  AMode: TJobOverwriteMode; out ASuccess: Boolean): Boolean;
var
  Jobs: TPanelJobController;
  Vfs: IVirtualFileSystem;
  Done: Boolean;
  Ok: Boolean;
  Tick: Cardinal;
begin
  Vfs := CreateDefaultVfs;
  Done := False;
  Ok := False;
  Jobs := TPanelJobController.Create(nil, Vfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean)
    begin
      Ok := ASucceeded;
      Done := True;
    end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end,
    nil);
  try
    Jobs.BeginJob(TArray<string>.Create(PathToFileUri(ASrcDir)),
      PathToFileUri(ADestParentDir), pjkCopy);
    Jobs.ApplyCopyMoveOptions(PathToFileUri(ADestParentDir), AMode, False);
    Jobs.ConfirmJob;

    Tick := GetTickCount;
    while not Done do
    begin
      CheckSynchronize(20);
      if GetTickCount - Tick > 30000 then
      begin
        Writeln('  [FAIL] job timed out');
        Inc(GFailures);
        Exit(False);
      end;
    end;
    ASuccess := Ok;
    Result := True;
  finally
    Jobs.Free;
  end;
end;

procedure TestJobLevelSkipMergesNested;
var
  Src, DestParent, Dst: string;
  Ok, Ran: Boolean;
begin
  Writeln('TestJobLevelSkipMergesNested (F5 path: nested folders that already exist)');

  // Mirror of the reported layout: several levels deep, every level already
  // present at the destination, with files missing only in the deepest one.
  Src := TPath.Combine(GRoot, 'job_src');
  DestParent := TPath.Combine(GRoot, 'job_dest');
  Dst := TPath.Combine(DestParent, 'job_src');

  TDirectory.CreateDirectory(TPath.Combine(Src, TPath.Combine('lvl2', 'lvl3')));
  WriteTextFile(TPath.Combine(Src, 'top.txt'), 'src-top');
  WriteTextFile(TPath.Combine(Src, 'lvl2', 'mid.txt'), 'src-mid');
  WriteTextFile(TPath.Combine(Src, 'lvl2', 'lvl3', 'deep-new.txt'), 'src-deep-new');
  WriteTextFile(TPath.Combine(Src, 'lvl2', 'lvl3', 'deep-existing.txt'), 'src-deep');

  // Destination mirrors the folder structure and has ONE of the deep files
  // with different content; everything else is missing and must be copied.
  TDirectory.CreateDirectory(TPath.Combine(Dst, TPath.Combine('lvl2', 'lvl3')));
  WriteTextFile(TPath.Combine(Dst, 'lvl2', 'lvl3', 'deep-existing.txt'), 'dst-deep-preexisting');

  Ran := RunJobCopy(Src, DestParent, jomSkip, Ok);
  Check(Ran and Ok, 'job finished successfully');

  Check(TFile.Exists(TPath.Combine(Dst, 'top.txt')),
    'top-level file copied into the existing destination folder');
  Check(TFile.Exists(TPath.Combine(Dst, 'lvl2', 'mid.txt')),
    'file in existing nested folder copied');
  Check(TFile.Exists(TPath.Combine(Dst, 'lvl2', 'lvl3', 'deep-new.txt')),
    'file in deepest existing folder copied (the reported symptom)');
  Check(ReadTextFile(TPath.Combine(Dst, 'lvl2', 'lvl3', 'deep-existing.txt'))
    = 'dst-deep-preexisting',
    'pre-existing deep file left untouched by Skip');
end;

/// <summary>Ask-mode job, auto-answering every overwrite prompt with "Skip"
/// (ARemember=False, exactly like a user clicking Skip on each popup rather
/// than checking "remember"). Sources are every direct child of ASrcDir,
/// mirroring the reported workflow: select everything *inside* the source
/// folder and copy it onto an existing destination folder, rather than
/// copying the single top folder as one item.</summary>
function RunJobCopyAskAllSkip(const ASrcDir, ADestDir: string;
  out ASuccess: Boolean; out APromptCount: Integer): Boolean;
var
  Jobs: TPanelJobController;
  Vfs: IVirtualFileSystem;
  Done: Boolean;
  Ok: Boolean;
  Tick: Cardinal;
  Sources: TArray<string>;
  SR: TSearchRec;
  Code: Integer;
  N: Integer;
  PromptCount: Integer;
begin
  SetLength(Sources, 0);
  N := 0;
  Code := FindFirst(TPath.Combine(ASrcDir, '*'), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        SetLength(Sources, N + 1);
        Sources[N] := PathToFileUri(TPath.Combine(ASrcDir, SR.Name));
        Inc(N);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;

  Vfs := CreateDefaultVfs;
  Done := False;
  Ok := False;
  PromptCount := 0;
  Jobs := TPanelJobController.Create(nil, Vfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string)
    begin
      // The real popup; simulate the user clicking "Skip" without "remember".
      Inc(PromptCount);
      Jobs.ResolveOverwriteAsk(jcaSkip, False, '');
    end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean)
    begin
      Ok := ASucceeded;
      Done := True;
    end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end,
    nil);
  try
    Jobs.BeginJob(Sources, PathToFileUri(ADestDir), pjkCopy);
    Jobs.ApplyCopyMoveOptions(PathToFileUri(ADestDir), jomAsk, False);
    Jobs.ConfirmJob;

    Tick := GetTickCount;
    while not Done do
    begin
      CheckSynchronize(20);
      if GetTickCount - Tick > 30000 then
      begin
        Writeln('  [FAIL] job timed out');
        Inc(GFailures);
        Exit(False);
      end;
    end;
    ASuccess := Ok;
    APromptCount := PromptCount;
    Result := True;
  finally
    Jobs.Free;
  end;
end;

procedure TestAskModeSkipOnFolderMerges;
var
  Src, Dst: string;
  Ok, Ran: Boolean;
  Prompts: Integer;
begin
  Writeln('TestAskModeSkipOnFolderMerges (exact reported workflow: select everything');
  Writeln('  inside the source folder, Ask mode, click Skip on the folder prompt)');

  // Mirrors "select all files/folders inside P:\_.. and copy to D:\_.." —
  // Src's *children* become FJob.Sources, not Src itself.
  Src := TPath.Combine(GRoot, 'ask_src');
  Dst := TPath.Combine(GRoot, 'ask_dst');
  TDirectory.CreateDirectory(TPath.Combine(Src, TPath.Combine('__2026', 'ZNRM')));
  WriteTextFile(TPath.Combine(Src, '__2026', 'ZNRM', '2024.txt'), 'src-2024');
  WriteTextFile(TPath.Combine(Src, '__2026', 'ZNRM', '2025.txt'), 'src-2025');
  WriteTextFile(TPath.Combine(Src, '__2026', 'ZNRM', '2026_new.txt'), 'src-2026-new');

  // Destination already has the folder tree (from an earlier sync) with the
  // 2024/2025 files but not the newly added 2026 one — exactly the reported
  // state of P:\..\ЗНРМ vs D:\..\ЗНРМ.
  TDirectory.CreateDirectory(TPath.Combine(Dst, TPath.Combine('__2026', 'ZNRM')));
  WriteTextFile(TPath.Combine(Dst, '__2026', 'ZNRM', '2024.txt'), 'src-2024');
  WriteTextFile(TPath.Combine(Dst, '__2026', 'ZNRM', '2025.txt'), 'src-2025');

  Ran := RunJobCopyAskAllSkip(Src, Dst, Ok, Prompts);
  Check(Ran and Ok, 'job finished successfully');
  Check(Prompts > 0, 'at least one overwrite-ask prompt fired (the __2026/ZNRM folder conflict)');

  Check(TFile.Exists(TPath.Combine(Dst, '__2026', 'ZNRM', '2026_new.txt')),
    'new nested file copied despite clicking Skip on the folder-level prompt '
    + '(the exact reported symptom)');
  Check(ReadTextFile(TPath.Combine(Dst, '__2026', 'ZNRM', '2024.txt')) = 'src-2024',
    'pre-existing file untouched');
end;

begin
  try
    GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopySkipMerge');
    if TDirectory.Exists(GRoot) then
      TDirectory.Delete(GRoot, True);
    TDirectory.CreateDirectory(GRoot);
    Writeln('=== TestCopySkipMerge ===');
    Writeln('temp: ', GRoot);
    Writeln;

    TestSkipMergesMissingFiles;
    TestOverwriteReplacesExisting;
    TestSkipNestedDirAlreadyExists;
    TestJobLevelSkipMergesNested;
    TestAskModeSkipOnFolderMerges;

    Writeln;
    try
      if TDirectory.Exists(GRoot) then
        TDirectory.Delete(GRoot, True);
    except
      // best-effort cleanup
    end;

    if GFailures = 0 then
      Writeln('All CopySkipMerge tests PASSED')
    else
    begin
      Writeln(Format('FAILED: %d check(s)', [GFailures]));
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
