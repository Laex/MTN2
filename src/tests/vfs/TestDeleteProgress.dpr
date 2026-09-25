program TestDeleteProgress;

{ Regression: F8 (Recycle Bin) / Shift+F8 (permanent) delete of a folder with
  many nested files and subfolders must move the job popup's progress bar,
  instead of sitting still until the whole delete finishes.

  Root cause: IVirtualFileSystem.DeleteAsync had no progress callback at all
  (unlike CopyAsync/MoveAsync) — TPanelJobController.ExecuteDeleteItem's only
  feedback was the top-level item finishing, so a single "delete this one
  folder" job (FJob.FilesTotal=1) rendered as a static 100% bar for the
  entire recursive walk. Fixed on two paths:
    - Permanent delete: uFileVfs.DeleteTree now reports (ADoneItems,
      ATotalItems) — files-plus-folders removed so far vs. a pre-walk count
      from EstimateTreeItemCount — after every individual file/folder it
      actually removes.
    - Recycle Bin delete: uFileRecycleBin.DeleteToRecycleBinIFileOp now
      advises an IFileOperationProgressSink (the recycle runs with
      FOF_SILENT, so nothing else reports progress) and forwards its
      UpdateProgress work-unit counts. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Winapi.Windows,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uFileVfs in '..\..\Core\uFileVfs.pas';

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

{ ---- an independent (from uFileVfs's own EstimateTreeItemCount) recursive
  file+folder counter, so the test validates the reported total against a
  second implementation rather than trivially agreeing with the same code. }
function CountFilesAndFolders(const APath: string): Integer;
var
  SR: TSearchRec;
  Code: Integer;
begin
  Result := 1; // APath itself
  if not TDirectory.Exists(APath) then
    Exit;
  Code := FindFirst(TPath.Combine(APath, '*'), faAnyFile, SR);
  try
    while Code = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if (SR.Attr and faDirectory) <> 0 then
          Inc(Result, CountFilesAndFolders(TPath.Combine(APath, SR.Name)))
        else
          Inc(Result);
      end;
      Code := FindNext(SR);
    end;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

{ ---- async plumbing -------------------------------------------------------- }

type
  TProgressSample = record
    Done, Total: Int64;
    Name, Path: string;
  end;

function WaitEvent(AEv: TEvent; ATimeoutMs: Cardinal = 60000): Boolean;
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

function RunDelete(const APath: string; AMode: TVfsDeleteMode;
  out ASamples: TArray<TProgressSample>; out AError: TVfsError): Boolean;
var
  Vfs: IVirtualFileSystem;
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
  List: TList<TProgressSample>;
  Sample: TProgressSample;
begin
  Vfs := TFileVirtualFileSystem.Create;
  Ev := TEvent.Create(nil, True, False, '');
  List := TList<TProgressSample>.Create;
  try
    Ok := False;
    Err := TVfsError.Ok;
    Vfs.DeleteAsync(PathToFileUri(APath), AMode, nil,
      procedure(const ADone, ATotal: Int64; const AName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
      begin
        Sample.Done := ADone;
        Sample.Total := ATotal;
        Sample.Name := AName;
        Sample.Path := AItemSrcPath;
        List.Add(Sample);
      end,
      procedure(const ASuccess: Boolean; const AErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AErr;
        Ev.SetEvent;
      end);
    if not WaitEvent(Ev) then
    begin
      Writeln('  [FAIL] delete timed out');
      Inc(GFailures);
      Exit(False);
    end;
    ASamples := List.ToArray;
    AError := Err;
    Result := Ok;
  finally
    List.Free;
    Ev.Free;
  end;
end;

{ ---- fixtures --------------------------------------------------------------- }

procedure MakeNestedFixture(const AName: string; out APath: string);
var
  I, J: Integer;
  SubDir: string;
begin
  APath := TPath.Combine(GRoot, AName);
  TDirectory.CreateDirectory(APath);
  for I := 1 to 3 do
  begin
    SubDir := TPath.Combine(APath, Format('sub%d', [I]));
    TDirectory.CreateDirectory(SubDir);
    for J := 1 to 3 do
      WriteTextFile(TPath.Combine(SubDir, Format('f%d.txt', [J])), 'x');
  end;
  WriteTextFile(TPath.Combine(APath, 'top.txt'), 'top');
end;

procedure MakeManyFilesFixture(const AName: string; out APath: string; AFileCount: Integer);
var
  I: Integer;
begin
  APath := TPath.Combine(GRoot, AName);
  TDirectory.CreateDirectory(APath);
  for I := 1 to AFileCount do
    WriteTextFile(TPath.Combine(APath, Format('f%d.txt', [I])), 'x');
end;

{ ---- tests ------------------------------------------------------------------ }

procedure TestPermanentDeleteReportsRealTotal;
var
  Path: string;
  Samples: TArray<TProgressSample>;
  Err: TVfsError;
  Ok: Boolean;
  Expected: Integer;
  MaxTotal: Int64;
  I: Integer;
begin
  Writeln('TestPermanentDeleteReportsRealTotal (Shift+F8, nested folder)');
  MakeNestedFixture('perm_nested', Path);
  Expected := CountFilesAndFolders(Path); // 1 root + 3 subdirs + 9 files + 1 top.txt = 14

  Ok := RunDelete(Path, vdmPermanent, Samples, Err);
  Check(Ok, 'delete reports success');

  Check(Length(Samples) > 0,
    'progress callback fired at least once (used to never fire for delete)');

  MaxTotal := 0;
  for I := 0 to High(Samples) do
    if Samples[I].Total > MaxTotal then
      MaxTotal := Samples[I].Total;
  Check(MaxTotal = Expected,
    Format('reported total matches the real file+folder count (%d, expected %d)',
      [MaxTotal, Expected]));

  if Length(Samples) > 0 then
    Check((Samples[High(Samples)].Done = Samples[High(Samples)].Total) and
      (Samples[High(Samples)].Total = Expected),
      Format('final progress report is complete (%d of %d)',
        [Samples[High(Samples)].Done, Samples[High(Samples)].Total]));

  Check(not TDirectory.Exists(Path), 'the whole tree was actually deleted');

  Check(Pos('file://', LowerCase(Samples[0].Path)) <> 1,
    'the reported item path is a real filesystem path, not a file:// URI (was: '
    + Samples[0].Path + ')');
  Check(SameText(Copy(Samples[0].Path, 1, Length(Path)), Path),
    Format('the reported path is inside the deleted tree (was: %s)', [Samples[0].Path]));
end;

procedure TestPermanentDeleteManyFilesProgressIsMonotonic;
var
  Path: string;
  Samples: TArray<TProgressSample>;
  Err: TVfsError;
  Ok: Boolean;
  Expected: Integer;
  I: Integer;
  Monotonic: Boolean;
begin
  Writeln('TestPermanentDeleteManyFilesProgressIsMonotonic (larger fixture)');
  MakeManyFilesFixture('perm_many', Path, 300);
  Expected := CountFilesAndFolders(Path); // 1 root + 300 files

  Ok := RunDelete(Path, vdmPermanent, Samples, Err);
  Check(Ok, 'delete reports success');
  Check(Length(Samples) > 0, 'progress callback fired');

  Monotonic := True;
  for I := 1 to High(Samples) do
    if Samples[I].Done < Samples[I - 1].Done then
      Monotonic := False;
  Check(Monotonic, 'reported Done never goes backwards across the run');

  if Length(Samples) > 0 then
    Check((Samples[High(Samples)].Done = Expected) and
      (Samples[High(Samples)].Total = Expected),
      Format('final report reaches the true total (%d of %d, expected %d)',
        [Samples[High(Samples)].Done, Samples[High(Samples)].Total, Expected]));

  Writeln(Format('    (%d progress callback(s) observed for %d items)',
    [Length(Samples), Expected]));
end;

procedure TestPermanentDeleteSingleFileStillWorks;
var
  Path, FilePath: string;
  Samples: TArray<TProgressSample>;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestPermanentDeleteSingleFileStillWorks (control: one plain file)');
  Path := TPath.Combine(GRoot, 'perm_single');
  TDirectory.CreateDirectory(Path);
  FilePath := TPath.Combine(Path, 'only.txt');
  WriteTextFile(FilePath, 'x');

  Ok := RunDelete(FilePath, vdmPermanent, Samples, Err);
  Check(Ok, 'delete reports success');
  Check(not TFile.Exists(FilePath), 'the file is gone');
  if Length(Samples) > 0 then
    Check((Samples[High(Samples)].Done = 1) and (Samples[High(Samples)].Total = 1),
      'a single file reports 1 of 1, not some other placeholder total');
end;

procedure TestRecycleBinDeleteReportsProgress;
var
  Path: string;
  Samples: TArray<TProgressSample>;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestRecycleBinDeleteReportsProgress (F8, via the real Shell API)');
  Writeln('  (mirrors TestVfsDelete.dpr: recycles a small scratch fixture and');
  Writeln('   leaves it in the real Recycle Bin, same as an actual F8 would)');
  MakeNestedFixture('recycle_nested', Path);

  Ok := RunDelete(Path, vdmRecycleBin, Samples, Err);
  Check(Ok, 'recycle reports success');
  if not Ok then
    Writeln('    error: ', Err.Message);

  Check(Length(Samples) > 0,
    'IFileOperationProgressSink.UpdateProgress reached our callback at least once');

  if Length(Samples) > 0 then
    Check(Samples[High(Samples)].Total > 0,
      Format('a real (non-zero) work total was reported (%d)',
        [Samples[High(Samples)].Total]));

  Check(not TDirectory.Exists(Path), 'the folder is gone from its original location');

  if Samples[High(Samples)].Path <> '' then
  begin
    Check(Pos('file://', LowerCase(Samples[High(Samples)].Path)) <> 1,
      'the reported item path (from IShellItem.GetDisplayName) is a real path, '
      + 'not a file:// URI (was: ' + Samples[High(Samples)].Path + ')');
    Check(SameText(Copy(Samples[High(Samples)].Path, 1, Length(Path)), Path),
      Format('the reported path is inside the recycled tree (was: %s)',
        [Samples[High(Samples)].Path]));
  end;
end;

begin
  try
    GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestDeleteProgress');
    if TDirectory.Exists(GRoot) then
      TDirectory.Delete(GRoot, True);
    TDirectory.CreateDirectory(GRoot);
    Writeln('=== TestDeleteProgress ===');
    Writeln('temp: ', GRoot);
    Writeln;

    TestPermanentDeleteReportsRealTotal;
    TestPermanentDeleteManyFilesProgressIsMonotonic;
    TestPermanentDeleteSingleFileStillWorks;
    TestRecycleBinDeleteReportsProgress;

    Writeln;
    try
      if TDirectory.Exists(GRoot) then
        TDirectory.Delete(GRoot, True);
    except
      // best-effort cleanup
    end;

    if GFailures = 0 then
      Writeln('All DeleteProgress tests PASSED')
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
