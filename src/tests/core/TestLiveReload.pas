unit TestLiveReload;

{ Regression: TEditorDoc's live reload — a local file opened for View/Edit is
  watched (via uDirWatch.TDirectoryWatcher, on its containing directory) and
  silently re-read whenever another process changes it on disk, as long as
  there are no unsaved edits. Also verifies the file is never held with an
  exclusive lock, so an external process can always write to it while it's
  open here — TFileVirtualFileSystem.ReadBytesAsync already opens with
  fmShareDenyNone and closes the handle immediately after each read.

  Source is deliberately pure ASCII, matching the other Stage 24 test files
  in this directory, so this unit's own encoding is never the thing under
  test. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLiveReload = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestReloadsOnExternalChange;
    [Test] procedure TestDirtyDocIsNeverClobbered;
    [Test] procedure TestOwnSaveDoesNotTriggerReload;
    [Test] procedure TestNewFileNotCreatedUntilSave;
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
  uTextEncoding,
  uDirWatch,
  uEditorDoc;

var
  GTempDir: string;

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
    Assert.Fail('timeout opening ' + APath);
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
  Path := TempPath('reload_basic.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path);
  try
    Assert.IsTrue(Doc.Ready, 'document is ready');
    // A trailing CRLF splits into a trailing empty final line too (2 content
    // lines + '' after the last newline = 3), same convention the fixture's
    // own trailing newline produces after the external rewrite below.
    Assert.IsTrue(Doc.LineCount = 3, 'initial line count is 3 (2 content lines + trailing empty line)');
    Assert.IsTrue(Doc.GetLine(0) = 'line0', 'initial content matches');

    // Simulates "some other program" editing the file while it's open here
    // — a second, independent handle. If TEditorDoc held an exclusive lock
    // this would itself raise; it must not.
    WriteFileText(Path, 'newline0'#13#10'newline1'#13#10'newline2'#13#10);

    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Doc.LineCount = 4;
      end, cReloadWaitMs), 'line count picks up the external change within the wait window');
    Assert.IsTrue(Doc.GetLine(0) = 'newline0', 'content reflects the external change');
    Assert.IsTrue(Doc.GetLine(2) = 'newline2', 'new line 2 is present');
    Assert.IsTrue(not Doc.Dirty, 'a silent reload never marks the document dirty');
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
  Path := TempPath('reload_dirty.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path, True);
  try
    Doc.SetLine(0, 'MY UNSAVED EDIT');
    Assert.IsTrue(Doc.Dirty, 'edited document is dirty');
    GenBefore := Doc.ContentGen;

    WriteFileText(Path, 'external0'#13#10'external1'#13#10'external2'#13#10);
    PumpFor(cQuietWaitMs);

    Assert.IsTrue(Doc.ContentGen = GenBefore, 'a dirty document is never silently reloaded (ContentGen unchanged)');
    Assert.IsTrue(Doc.GetLine(0) = 'MY UNSAVED EDIT', 'the unsaved edit is still there, not overwritten');
    Assert.IsTrue(Doc.Dirty, 'still dirty after the external change');
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
  Path := TempPath('reload_ownsave.txt');
  WriteFileText(Path, 'line0'#13#10'line1'#13#10);
  Doc := OpenDoc(Path, True);
  try
    Doc.SetLine(0, 'SAVED EDIT');
    Doc.SaveAsync;
    Assert.IsTrue(WaitSaved(Doc), 'save completes');
    Assert.IsTrue(not Doc.Dirty, 'clean after save');
    GenAfterSave := Doc.ContentGen;

    // The save itself is a real write to the watched directory, so the
    // watcher WILL fire — the point is that FKnownSize/FKnownWriteTime were
    // updated to match right after saving, so CheckExternalChange sees no
    // difference and never calls ReloadFromDisk.
    PumpFor(cQuietWaitMs);

    Assert.IsTrue(Doc.ContentGen = GenAfterSave, 'no reload was triggered by our own save (ContentGen unchanged)');
    Assert.IsTrue(Doc.GetLine(0) = 'SAVED EDIT', 'content is still exactly what we saved');
  finally
    Doc.Free;
  end;
end;

procedure TestNewFileNotCreatedUntilSave;
var
  Path: string;
  Doc: TEditorDoc;
begin
  Path := TempPath('newfile_until_save.txt');
  Assert.IsTrue(not TFile.Exists(Path), 'path does not exist before open');
  Doc := OpenDoc(Path, True);
  try
    Assert.IsTrue(Doc.Ready, 'edit-open of missing path is ready');
    Assert.IsTrue(Doc.Error = '', 'no load error');
    Assert.IsTrue(not Doc.Dirty, 'empty new buffer is clean');
    Assert.IsTrue(not TFile.Exists(Path), 'discard-equivalent: still no file before save');
    Doc.SetLine(0, 'hello');
    Assert.IsTrue(Doc.Dirty, 'edit marks dirty');
    Doc.SaveAsync;
    Assert.IsTrue(WaitSaved(Doc), 'save completes');
    Assert.IsTrue(TFile.Exists(Path), 'file is created on save');
    Assert.IsTrue(not Doc.Dirty, 'clean after save');
  finally
    Doc.Free;
  end;
end;

{ TTestLiveReload }

procedure TTestLiveReload.SetupFixture;
begin
  GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestLiveReload');
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
  TDirectory.CreateDirectory(GTempDir);
end;

procedure TTestLiveReload.TearDownFixture;
begin
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
end;

procedure TTestLiveReload.TestReloadsOnExternalChange;
begin
  TestLiveReload.TestReloadsOnExternalChange;
end;

procedure TTestLiveReload.TestDirtyDocIsNeverClobbered;
begin
  TestLiveReload.TestDirtyDocIsNeverClobbered;
end;

procedure TTestLiveReload.TestOwnSaveDoesNotTriggerReload;
begin
  TestLiveReload.TestOwnSaveDoesNotTriggerReload;
end;

procedure TTestLiveReload.TestNewFileNotCreatedUntilSave;
begin
  TestLiveReload.TestNewFileNotCreatedUntilSave;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLiveReload);

end.
