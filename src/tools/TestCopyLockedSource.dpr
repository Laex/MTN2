program TestCopyLockedSource;

{ Regression: copying a folder that contains files another process holds open
  for writing — an application log, a live SQLite/LevelDB store — must copy
  the whole tree instead of dying partway through.

  Reported as "copying D:\Hiddify to P:\Hiddify shows an error at the end and
  not all files are copied": the running Hiddify keeps app.log, box.log,
  db.sqlite and clash.db open for write, and uFileVfs.CopyFileWithProgress
  opened every source with fmShareDenyWrite. That raised EFOpenError on the
  first such file, and since nothing between there and CopyAsync's outer
  handler caught it, the exception unwound out of the whole recursive
  CopyTree walk: everything after that point in the tree was silently left
  uncopied, and the failure was reported against the top-level job URI rather
  than the file that actually could not be opened.

  Two more failures of the same shape lived downstream: a source still being
  appended to grows past the size that was sampled when it was opened, so the
  strict size checks in the post-copy verification declared a "size mismatch"
  and CleanupFailedCopy deleted the freshly copied destination tree. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uFileVfs in '..\Core\uFileVfs.pas';

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

function RunCopy(const ASrc, ADst: string; AOverwrite: Boolean;
  out AError: TVfsError): Boolean;
var
  Vfs: IVirtualFileSystem;
  Ev: TEvent;
  Ok: Boolean;
  Err: TVfsError;
begin
  Vfs := TFileVirtualFileSystem.Create;
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

{ ---- a source file some other component keeps open ------------------------- }

type
  /// <summary>Holds a file open exactly the way an application's log writer
  /// does: read/write access, readers allowed, other writers denied. That is
  /// what made the old fmShareDenyWrite source open fail — our own request to
  /// deny writers collided with the holder's existing write handle.</summary>
  TLiveWriter = class
  private
    FStream: TFileStream;
    FThread: TThread;
    FStop: Boolean;
  public
    constructor Create(const APath: string; AInitialBytes: Integer);
    destructor Destroy; override;
    procedure StartAppending;
    procedure StopAppending;
    property Stream: TFileStream read FStream;
  end;

constructor TLiveWriter.Create(const APath: string; AInitialBytes: Integer);
var
  Buf: TBytes;
  I: Integer;
begin
  inherited Create;
  FStream := TFileStream.Create(APath, fmCreate or fmShareDenyWrite);
  SetLength(Buf, AInitialBytes);
  for I := 0 to High(Buf) do
    Buf[I] := Byte(Ord('a') + (I mod 26));
  if Length(Buf) > 0 then
    FStream.WriteBuffer(Buf[0], Length(Buf));
end;

destructor TLiveWriter.Destroy;
begin
  StopAppending;
  FStream.Free;
  inherited;
end;

procedure TLiveWriter.StartAppending;
begin
  if Assigned(FThread) then
    Exit;
  FStop := False;
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Chunk: TBytes;
    begin
      SetLength(Chunk, 4096);
      FillChar(Chunk[0], Length(Chunk), Ord('L'));
      while not FStop do
      begin
        try
          FStream.Seek(0, soEnd);
          FStream.WriteBuffer(Chunk[0], Length(Chunk));
        except
          // The writer losing its file is not what this test measures.
        end;
        Sleep(2);
      end;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TLiveWriter.StopAppending;
begin
  if not Assigned(FThread) then
    Exit;
  FStop := True;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

{ ---- fixtures -------------------------------------------------------------- }

/// <summary>Mirror of the reported layout: an ordinary tree with one file an
/// application is holding open (and, when AKeepAppending is set, actively
/// writing to) and a large file after it in enumeration order, so the copy is
/// still running long enough for the live file to grow underneath it.</summary>
procedure MakeLiveFixture(const AName: string; out ASrc, ADst: string;
  out AWriter: TLiveWriter);
var
  Big: TBytes;
begin
  ASrc := TPath.Combine(GRoot, AName + '_src');
  ADst := TPath.Combine(GRoot, AName + '_dst');
  TDirectory.CreateDirectory(TPath.Combine(ASrc, 'sub'));
  WriteTextFile(TPath.Combine(ASrc, 'a_plain.txt'), 'plain');
  WriteTextFile(TPath.Combine(ASrc, 'sub', 'nested.txt'), 'nested');
  AWriter := TLiveWriter.Create(TPath.Combine(ASrc, 'b_live.log'), 64 * 1024);
  // Sorts after b_live.log, so the live file is copied first and keeps
  // growing while this one is still being transferred.
  SetLength(Big, 8 * 1024 * 1024);
  FillChar(Big[0], Length(Big), $5A);
  TFile.WriteAllBytes(TPath.Combine(ASrc, 'z_big.bin'), Big);
end;

{ ---- tests ----------------------------------------------------------------- }

procedure TestCopiesTreeWithFileOpenByAnotherWriter;
var
  Src, Dst: string;
  Writer: TLiveWriter;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestCopiesTreeWithFileOpenByAnotherWriter (the reported bug)');
  MakeLiveFixture('held', Src, Dst, Writer);
  try
    Ok := RunCopy(Src, Dst, False, Err);
    Check(Ok, 'copy reports success instead of aborting on the open file');
    if not Ok then
      Writeln('    error: ', Err.Message, ' @ ', Err.URI);

    Check(TFile.Exists(TPath.Combine(Dst, 'b_live.log')),
      'the file held open by another writer was copied');
    Check(TFile.Exists(TPath.Combine(Dst, 'z_big.bin')),
      'the file enumerated AFTER it was copied too (the reported symptom: '
      + 'everything past the locked file went missing)');
    Check(TFile.Exists(TPath.Combine(Dst, 'sub', 'nested.txt')),
      'nested file copied');
    Check(ReadTextFile(TPath.Combine(Dst, 'a_plain.txt')) = 'plain',
      'ordinary file content matches');
    Check(TFile.GetSize(TPath.Combine(Dst, 'b_live.log')) = 64 * 1024,
      'the open file was copied whole');
  finally
    Writer.Free;
  end;
end;

procedure TestCopiesSourceGrowingDuringCopy;
var
  Src, Dst: string;
  Writer: TLiveWriter;
  Err: TVfsError;
  Ok: Boolean;
  SrcSize, DstSize: Int64;
begin
  Writeln('TestCopiesSourceGrowingDuringCopy (live log still being appended to)');
  MakeLiveFixture('growing', Src, Dst, Writer);
  try
    Writer.StartAppending;
    Ok := RunCopy(Src, Dst, False, Err);
    Writer.StopAppending;

    Check(Ok, 'copy succeeds even though a source file grew while it ran');
    if not Ok then
      Writeln('    error: ', Err.Message, ' @ ', Err.URI);

    Check(TDirectory.Exists(Dst),
      'the destination tree survives verification (a size mismatch against '
      + 'the still-growing source used to delete all of it)');
    Check(TFile.Exists(TPath.Combine(Dst, 'z_big.bin')),
      'files after the growing one were copied');

    if TFile.Exists(TPath.Combine(Dst, 'b_live.log')) then
    begin
      SrcSize := TFile.GetSize(TPath.Combine(Src, 'b_live.log'));
      DstSize := TFile.GetSize(TPath.Combine(Dst, 'b_live.log'));
      Check(SrcSize > 64 * 1024, 'the source really did grow during the copy');
      Check((DstSize >= 64 * 1024) and (DstSize <= SrcSize),
        Format('the copy is a consistent snapshot of it (%d of %d bytes)',
          [DstSize, SrcSize]));
    end
    else
      Check(False, 'the growing file was copied');
  finally
    Writer.Free;
  end;
end;

procedure TestExclusivelyLockedFileReportsItsOwnPath;
var
  Src, Dst, Locked: string;
  Hold: TFileStream;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestExclusivelyLockedFileReportsItsOwnPath (control: a genuinely');
  Writeln('  unreadable file still fails, but says which file)');
  Src := TPath.Combine(GRoot, 'excl_src');
  Dst := TPath.Combine(GRoot, 'excl_dst');
  TDirectory.CreateDirectory(Src);
  WriteTextFile(TPath.Combine(Src, 'a_plain.txt'), 'plain');
  Locked := TPath.Combine(Src, 'b_excl.bin');
  Hold := TFileStream.Create(Locked, fmCreate or fmShareExclusive);
  try
    Err := TVfsError.Ok;
    Ok := RunCopy(Src, Dst, False, Err);
    Check(not Ok, 'copy reports failure');
    Check(Pos('b_excl.bin', Err.URI) > 0,
      'the error identifies the file that could not be read, not the '
      + 'top-level job source (was: ' + Err.URI + ')');
    Check(not TFile.Exists(TPath.Combine(Dst, 'b_excl.bin')),
      'no half-written fragment of it is left at the destination');
  finally
    Hold.Free;
  end;
end;

begin
  try
    GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopyLockedSource');
    if TDirectory.Exists(GRoot) then
      TDirectory.Delete(GRoot, True);
    TDirectory.CreateDirectory(GRoot);
    Writeln('=== TestCopyLockedSource ===');
    Writeln('temp: ', GRoot);
    Writeln;

    TestCopiesTreeWithFileOpenByAnotherWriter;
    TestCopiesSourceGrowingDuringCopy;
    TestExclusivelyLockedFileReportsItsOwnPath;

    Writeln;
    try
      if TDirectory.Exists(GRoot) then
        TDirectory.Delete(GRoot, True);
    except
      // best-effort cleanup
    end;

    if GFailures = 0 then
      Writeln('All CopyLockedSource tests PASSED')
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
