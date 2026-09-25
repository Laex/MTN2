program TestLiveReload;

{ Regression: TEditorDoc's live reload — a local file opened for View/Edit is
  watched (via uDirWatch.TDirectoryWatcher, on its containing directory) and
  silently re-read whenever another process changes it on disk, as long as
  there are no unsaved edits. Also verifies the file is never held with an
  exclusive lock, so an external process can always write to it while it's
  open here — TFileVirtualFileSystem.ReadBytesAsync already opens with
  fmShareDenyNone and closes the handle immediately after each read.

  Source is deliberately pure ASCII, matching the other Stage 24 test files
  in this directory, so this .dpr's own encoding is never the thing under
  test. }

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
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uDirWatch in '..\Core\uDirWatch.pas',
  uEditorDoc in '..\Core\uEditorDoc.pas';

var
  GTempDir: string;
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

function TempPath(const AName: string): string;
begin
  Result := TPath.Combine(GTempDir, AName);
end;

procedure WriteFileText(const APath, AText: string);
begin
  // Explicit bytes (no TEncoding.UTF8 BOM) so re-reads land on the same
  // encoding every time — a BOM appearing/disappearing between writes would
  // be its own (unrelated) source of flaky diffs here.
  TFile.WriteAllText(APath, AText, TEncoding.ASCII);
end;

{ ---- async plumbing --------------------------------------------------------- }

function WaitDoc(ADoc: TEditorDoc): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while ADoc.Loading do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > 60000 then
      Exit(False);
  end;
  CheckSynchronize(0);
  Result := True;
end;

function WaitSaved(ADoc: TEditorDoc): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while ADoc.Saving do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > 60000 then
      Exit(False);
  end;
  CheckSynchronize(0);
  Result := True;
end;

function OpenDoc(const APath: string; AWantEdit: Boolean = False): TEditorDoc;
begin
  Result := TEditorDoc.Create;
  Result.OpenAsync(PathToFileUri(APath), AWantEdit);
  if not WaitDoc(Result) then
  begin
    Writeln('  [FAIL] timeout opening ', APath);
    Inc(GFailures);
  end;
end;

/// <summary>Pumps TThread.Queue-delivered callbacks (the watcher's debounced
/// notification, the background stat, the async reload) for AMs milliseconds
/// regardless of what happens — used where the test asserts something did
/// NOT happen, so it has to wait out the full window either way.</summary>
procedure PumpFor(AMs: Cardinal);
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while GetTickCount - Tick < AMs do
    CheckSynchronize(20);
end;

/// <summary>Pumps until AFn returns True or ATimeoutMs elapses.</summary>
function WaitUntil(const AFn: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  Tick: Cardinal;
begin
  Tick := GetTickCount;
  while not AFn() do
  begin
    CheckSynchronize(20);
    if GetTickCount - Tick > ATimeoutMs then
      Exit(False);
  end;
  Result := True;
end;

const
  // TDirectoryWatcher debounces bursty FS events over a ~300ms quiet window
  // before notifying; give real waits a comfortable margin over that, and
  // negative ("nothing happened") waits enough to be confident it's not
  // just running late.
  cReloadWaitMs = 5000;
  cQuietWaitMs = 1500;

{ ---- tests ------------------------------------------------------------------ }

procedure TestReloadsOnExternalChange;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Writeln('-- live reload: external change is picked up --');
  Path := TempPath('reload_basic.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path);
  try
    Check(Doc.Ready, 'document is ready');
    // A trailing CRLF splits into a trailing empty final line too (2 content
    // lines + '' after the last newline = 3), same convention the fixture's
    // own trailing newline produces after the external rewrite below.
    Check(Doc.LineCount = 3, 'initial line count is 3 (2 content lines + trailing empty line)');
    Check(Doc.GetLine(0) = 'line0', 'initial content matches');

    // Simulates "some other program" editing the file while it's open here
    // — a second, independent handle. If TEditorDoc held an exclusive lock
    // this would itself raise; it must not.
    WriteFileText(Path, 'newline0'#13#10'newline1'#13#10'newline2'#13#10);

    Check(WaitUntil(
      function: Boolean
      begin
        Result := Doc.LineCount = 4;
      end, cReloadWaitMs), 'line count picks up the external change within the wait window');
    Check(Doc.GetLine(0) = 'newline0', 'content reflects the external change');
    Check(Doc.GetLine(2) = 'newline2', 'new line 2 is present');
    Check(not Doc.Dirty, 'a silent reload never marks the document dirty');
  finally
    Doc.Free;
  end;
end;

procedure TestDirtyDocIsNeverClobbered;
var
  Path: string;
  Doc: TEditorDoc;
  GenBefore: Cardinal;
begin
  Writeln('-- live reload: unsaved edits are never silently discarded --');
  Path := TempPath('reload_dirty.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path, True);
  try
    Doc.SetLine(0, 'MY UNSAVED EDIT');
    Check(Doc.Dirty, 'edited document is dirty');
    GenBefore := Doc.ContentGen;

    WriteFileText(Path, 'external0'#13#10'external1'#13#10'external2'#13#10);
    PumpFor(cQuietWaitMs);

    Check(Doc.ContentGen = GenBefore, 'a dirty document is never silently reloaded (ContentGen unchanged)');
    Check(Doc.GetLine(0) = 'MY UNSAVED EDIT', 'the unsaved edit is still there, not overwritten');
    Check(Doc.Dirty, 'still dirty after the external change');
  finally
    Doc.Free;
  end;
end;

procedure TestOwnSaveDoesNotTriggerReload;
var
  Path: string;
  Doc: TEditorDoc;
  GenAfterSave: Cardinal;
begin
  Writeln('-- live reload: saving our own edit does not bounce back as a reload --');
  Path := TempPath('reload_ownsave.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path, True);
  try
    Doc.SetLine(0, 'SAVED EDIT');
    Doc.SaveAsync;
    Check(WaitSaved(Doc), 'save completes');
    Check(not Doc.Dirty, 'clean after save');
    GenAfterSave := Doc.ContentGen;

    // The save itself is a real write to the watched directory, so the
    // watcher WILL fire — the point is that FKnownSize/FKnownWriteTime were
    // updated to match right after saving, so CheckExternalChange sees no
    // difference and never calls ReloadFromDisk.
    PumpFor(cQuietWaitMs);

    Check(Doc.ContentGen = GenAfterSave, 'no reload was triggered by our own save (ContentGen unchanged)');
    Check(Doc.GetLine(0) = 'SAVED EDIT', 'content is still exactly what we saved');
  finally
    Doc.Free;
  end;
end;

procedure TestNewFileNotCreatedUntilSave;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Writeln('-- new file: missing path opens empty and is not created until save --');
  Path := TempPath('newfile_until_save.txt');
  Check(not TFile.Exists(Path), 'path does not exist before open');
  Doc := OpenDoc(Path, True);
  try
    Check(Doc.Ready, 'edit-open of missing path is ready');
    Check(Doc.Error = '', 'no load error');
    Check(not Doc.Dirty, 'empty new buffer is clean');
    Check(not TFile.Exists(Path), 'discard-equivalent: still no file before save');
    Doc.SetLine(0, 'hello');
    Check(Doc.Dirty, 'edit marks dirty');
    Doc.SaveAsync;
    Check(WaitSaved(Doc), 'save completes');
    Check(TFile.Exists(Path), 'file is created on save');
    Check(not Doc.Dirty, 'clean after save');
  finally
    Doc.Free;
  end;
end;

begin
  try
    GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestLiveReload');
    if TDirectory.Exists(GTempDir) then
      TDirectory.Delete(GTempDir, True);
    TDirectory.CreateDirectory(GTempDir);
    Writeln('=== TestLiveReload ===');
    Writeln('temp: ', GTempDir);
    Writeln;

    TestReloadsOnExternalChange;
    TestDirtyDocIsNeverClobbered;
    TestOwnSaveDoesNotTriggerReload;
    TestNewFileNotCreatedUntilSave;

    Writeln;
    try
      if TDirectory.Exists(GTempDir) then
        TDirectory.Delete(GTempDir, True);
    except
      // Cleanup is best-effort; a locked temp file must not fail the run.
    end;

    if GFailures = 0 then
      Writeln('All LiveReload tests PASSED')
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
