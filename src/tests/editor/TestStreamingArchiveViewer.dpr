program TestStreamingArchiveViewer;

{ Regression: an archive entry too big for the whole-buffer load
  (cEditorMaxBytes) must still open in F3/F4 via the line-indexed streaming
  path, by extracting to a temp file first (TEditorDoc.
  StartStreamingOpenFromArchive) — mirrors TestStreamingViewer.dpr's
  coverage of the plain-local-file streaming path, plus a check that the
  temp file used for extraction doesn't leak past Close/Free. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Zip,
  System.Generics.Collections,
  Winapi.Windows,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uTextEncoding in '..\..\Core\uTextEncoding.pas',
  uFileVfs in '..\..\Core\uFileVfs.pas',
  uZipVfs in '..\..\Core\uZipVfs.pas',
  uFindSession in '..\..\Core\uFindSession.pas',
  uFindVfs in '..\..\Core\uFindVfs.pas',
  uVfsRegistry in '..\..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\..\Core\uVfsRouter.pas',
  uEditorDoc in '..\..\Core\uEditorDoc.pas';

const
  // Cyrillic "Тест" — codepoints, not a literal (avoids depending on this
  // .dpr's own source encoding — see TestStreamingViewer.dpr's header note).
  cCyr = #$0422#$0435#$0441#$0442;

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

/// <summary>Plain UTF-8 text file, no BOM, just over cEditorMaxBytes — same
/// shape as TestStreamingViewer.dpr's MakeBigUtf8, kept self-contained here
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
    Writeln('  [FAIL] timeout opening ', AURI);
    Inc(GFailures);
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
  Writeln('TestArchiveEntryStreams (zip entry bigger than cEditorMaxBytes)');
  TxtPath := TempPath('big_utf8.txt');
  Expected := MakeBigUtf8File(TxtPath);
  ZipPath := TempPath('big.zip');
  MakeZipWithEntry(ZipPath, 'big.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'big.txt');

  Doc := OpenDocByUri(EntryUri);
  try
    Check(Doc.Ready, 'document is ready');
    Check(Doc.Error = '', 'no error: ' + Doc.Error);
    Check(Doc.Streaming, 'opened in streaming mode (extract-then-stream)');
    Check(Doc.ReadOnly, 'streaming document is read-only');
    Check(Doc.Encoding = tfeUtf8, 'encoding detected as UTF-8');
    Check(Doc.LineCount = Expected,
      Format('line count %d = expected %d', [Doc.LineCount, Expected]));
    Check(Doc.GetLine(0) = LineText(0), 'first line matches exactly');
    Check(Doc.GetLine(Expected - 1) = LineText(Expected - 1),
      'last line matches exactly (round-trips non-ASCII content)');

    Mid := Expected div 2;
    Check(Doc.GetLine(Mid) = LineText(Mid), 'middle line matches');
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
  Writeln('TestArchiveTempFileCleanedUpOnClose (extraction temp file is not leaked)');
  TxtPath := TempPath('big_utf8_2.txt');
  MakeBigUtf8File(TxtPath);
  ZipPath := TempPath('big2.zip');
  MakeZipWithEntry(ZipPath, 'big2.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'big2.txt');

  Before := SnapshotTempTmpFiles;
  Doc := OpenDocByUri(EntryUri);
  Check(Doc.Ready and Doc.Streaming, 'doc opened in streaming mode before checking cleanup');
  Doc.Free; // -> Close, which must delete the extraction temp file

  SetLength(Leaked, 0);
  After := SnapshotTempTmpFiles;
  for S in After do
    if TArray.IndexOf<string>(Before, S) < 0 then
      Leaked := Leaked + [S];
  Check(Length(Leaked) = 0,
    Format('no new .tmp files left in the OS temp folder after Close (found %d)',
      [Length(Leaked)]));
end;

procedure TestArchiveSmallEntryUnaffected;
var
  TxtPath, ZipPath, EntryUri: string;
  Doc: TEditorDoc;
begin
  Writeln('TestArchiveSmallEntryUnaffected (control: under the limit stays whole-buffer, editable)');
  TxtPath := TempPath('small.txt');
  WriteBytesFile(TxtPath, TEncoding.UTF8.GetBytes(LineText(0) + #13#10 + LineText(1)));
  ZipPath := TempPath('small.zip');
  MakeZipWithEntry(ZipPath, 'small.txt', TxtPath);
  EntryUri := JoinVfsUri(EnsureArchiveRootUri(PathToFileUri(ZipPath)), 'small.txt');

  Doc := OpenDocByUri(EntryUri);
  try
    Check(Doc.Ready, 'small archive entry is ready');
    Check(not Doc.Streaming, 'small archive entry uses the whole-buffer path, not streaming');
    Check(Doc.LineCount = 2, 'small document line count');
    Check(Doc.GetLine(0) = LineText(0), 'small document first line matches');
  finally
    Doc.Free;
  end;
end;

begin
  try
    GTempDir := TPath.Combine(TPath.GetTempPath, 'MTN2_TestStreamingArchiveViewer');
    if TDirectory.Exists(GTempDir) then
      TDirectory.Delete(GTempDir, True);
    TDirectory.CreateDirectory(GTempDir);
    Writeln('=== TestStreamingArchiveViewer ===');
    Writeln('temp: ', GTempDir);
    Writeln;

    TestArchiveEntryStreams;
    TestArchiveTempFileCleanedUpOnClose;
    TestArchiveSmallEntryUnaffected;

    Writeln;
    try
      if TDirectory.Exists(GTempDir) then
        TDirectory.Delete(GTempDir, True);
    except
      // best-effort cleanup
    end;

    if GFailures = 0 then
      Writeln('All StreamingArchiveViewer tests PASSED')
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
