unit TestStreamingArchiveViewer;

{ Regression: an archive entry too big for the whole-buffer load
  (cEditorMaxBytes) must still open in F3/F4 via the line-indexed streaming
  path, by extracting to a temp file first (TEditorDoc.
  StartStreamingOpenFromArchive) - mirrors TestStreamingViewer.pas's
  coverage of the plain-local-file streaming path, plus a check that the
  temp file used for extraction doesn't leak past Close/Free. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStreamingArchiveViewer = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestArchiveEntryStreams;
    [Test] procedure TestArchiveTempFileCleanedUpOnClose;
    [Test] procedure TestArchiveSmallEntryUnaffected;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Zip,
  System.Generics.Collections,
  Winapi.Windows,
  uVfsTypes,
  uTextEncoding,
  uFileVfs,
  uZipVfs,
  uFindSession,
  uFindVfs,
  uVfsRegistry,
  uVfsRouter,
  uEditorDoc;

const
  // Cyrillic "Тест" - codepoints, not a literal (avoids depending on this
  // unit's own source encoding - see TestStreamingViewer.pas's header note).
  cCyr = #$0422#$0435#$0441#$0442;

var
  GTempDir: string;

function LineText(AIndex: Integer): string;
begin
  Result := Format('Line %.7d ', [AIndex]) + cCyr + ' abcdefghij 0123456789';
end;

procedure WriteBytesFile(const APath: string; const ABytes: TBytes);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(ABytes) > 0 then
      FS.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    FS.Free;
  end;
end;

{ ---- fixtures --------------------------------------------------------------- }

function TempPath(const AName: string): string;
begin
  Result := TPath.Combine(GTempDir, AName);
end;

/// <summary>Plain UTF-8 text file, no BOM, just over cEditorMaxBytes - same
/// shape as TestStreamingViewer.pas's MakeBigUtf8, kept self-contained here
/// since these standalone harnesses don't share code with each other.</summary>
function MakeBigUtf8File(const APath: string): Integer;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    I := 0;
    while SB.Length < cEditorMaxBytes do
    begin
      SB.Append(LineText(I));
      SB.Append(#13#10);
      Inc(I);
    end;
    WriteBytesFile(APath, TEncoding.UTF8.GetBytes(SB.ToString));
    Result := I;
  finally
    SB.Free;
  end;
end;

/// <summary>Packs ASourcePath into a fresh ZIP at AZipPath under AEntryName
/// (flat, no folder prefix) via the same System.Zip.TZipFile uZipVfs.pas
/// reads with.</summary>
procedure MakeZipWithEntry(const AZipPath, AEntryName, ASourcePath: string);
var
  Zip: TZipFile;
begin
  if TFile.Exists(AZipPath) then
    TFile.Delete(AZipPath);
  Zip := TZipFile.Create;
  try
    Zip.Open(AZipPath, zmWrite);
    try
      Zip.Add(ASourcePath, AEntryName);
    finally
      Zip.Close;
    end;
  finally
    Zip.Free;
  end;
end;

{ ---- async plumbing -------------------------------------------------------- }

/// <summary>OpenAsync completes on the UI thread via TThread.Queue; a console
/// app must pump those itself.</summary>
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

function OpenDocByUri(const AURI: string): TEditorDoc;
begin
  Result := TEditorDoc.Create;
  Result.OpenAsync(AURI);
  if not WaitDoc(Result) then
  begin
    Assert.Fail('timeout opening ' + AURI);
  end;
end;

function SnapshotTempTmpFiles: TArray<string>;
begin
  // TPath.GetTempFileName always creates its placeholder directly under the
  // OS temp root (not GTempDir), so leak detection has to look there too.
  Result := TDirectory.GetFiles(TPath.GetTempPath, '*.tmp');
end;

{ ---- tests ------------------------------------------------------------------ }

procedure TestArchiveEntryStreams;
var
  TxtPath, ZipPath, EntryUri: string;
  Expected, Mid: Integer;
  Doc: TEditorDoc;
begin
  TxtPath := TempPath('big_utf8.txt');
  Expected := MakeBigUtf8File(TxtPath);
  ZipPath := TempPath('big.zip');
  MakeZipWithEntry(ZipPath, 'big.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'big.txt');

  Doc := OpenDocByUri(EntryUri);
  try
    Assert.IsTrue(Doc.Ready, 'document is ready');
    Assert.IsTrue(Doc.Error = '', 'no error: ' + Doc.Error);
    Assert.IsTrue(Doc.Streaming, 'opened in streaming mode (extract-then-stream)');
    Assert.IsTrue(Doc.ReadOnly, 'streaming document is read-only');
    Assert.IsTrue(Doc.Encoding = tfeUtf8, 'encoding detected as UTF-8');
    Assert.IsTrue(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'first line matches exactly');
    Assert.IsTrue(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'last line matches exactly (round-trips non-ASCII content)');

    Mid := Expected div 2;
    Assert.IsTrue(Doc.GetLine(Mid) = LineText(Mid), 'middle line matches');
  finally
    Doc.Free;
  end;
end;

procedure TestArchiveTempFileCleanedUpOnClose;
var
  TxtPath, ZipPath, EntryUri: string;
  Doc: TEditorDoc;
  Before, After: TArray<string>;
  Leaked: TArray<string>;
  S: string;
begin
  TxtPath := TempPath('big_utf8_2.txt');
  MakeBigUtf8File(TxtPath);
  ZipPath := TempPath('big2.zip');
  MakeZipWithEntry(ZipPath, 'big2.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'big2.txt');

  Before := SnapshotTempTmpFiles;
  Doc := OpenDocByUri(EntryUri);
  Assert.IsTrue(Doc.Ready and Doc.Streaming, 'doc opened in streaming mode before checking cleanup');
  Doc.Free; // -> Close, which must delete the extraction temp file

  SetLength(Leaked, 0);
  After := SnapshotTempTmpFiles;
  for S in After do
    if TArray.IndexOf<string>(Before, S) < 0 then
      Leaked := Leaked + [S];
  Assert.IsTrue(Length(Leaked) = 0,
    Format('no new .tmp files left in the OS temp folder after Close (found %d)',
      [Length(Leaked)]));
end;

procedure TestArchiveSmallEntryUnaffected;
var
  TxtPath, ZipPath, EntryUri: string;
  Doc: TEditorDoc;
begin
  TxtPath := TempPath('small.txt');
  WriteBytesFile(TxtPath, TEncoding.UTF8.GetBytes(LineText(0) + #13#10 + LineText(1)));
  ZipPath := TempPath('small.zip');
  MakeZipWithEntry(ZipPath, 'small.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'small.txt');

  Doc := OpenDocByUri(EntryUri);
  try
    Assert.IsTrue(Doc.Ready, 'small archive entry is ready');
    Assert.IsTrue(not Doc.Streaming, 'small archive entry uses the whole-buffer path, not streaming');
    Assert.IsTrue(Doc.LineCount = 2, 'small document line count');
    Assert.IsTrue(Doc.GetLine(0) = LineText(0), 'small document first line matches');
  finally
    Doc.Free;
  end;
end;

{ TTestStreamingArchiveViewer }

procedure TTestStreamingArchiveViewer.SetupFixture;
begin
  GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestStreamingArchiveViewer');
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
  TDirectory.CreateDirectory(GTempDir);
end;

procedure TTestStreamingArchiveViewer.TearDownFixture;
begin
  if TDirectory.Exists(GTempDir) then
    TDirectory.Delete(GTempDir, True);
end;

procedure TTestStreamingArchiveViewer.TestArchiveEntryStreams;
begin
  TestStreamingArchiveViewer.TestArchiveEntryStreams;
end;

procedure TTestStreamingArchiveViewer.TestArchiveTempFileCleanedUpOnClose;
begin
  TestStreamingArchiveViewer.TestArchiveTempFileCleanedUpOnClose;
end;

procedure TTestStreamingArchiveViewer.TestArchiveSmallEntryUnaffected;
begin
  TestStreamingArchiveViewer.TestArchiveSmallEntryUnaffected;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStreamingArchiveViewer);

end.
