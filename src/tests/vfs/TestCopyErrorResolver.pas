unit TestCopyErrorResolver;

{ Regression: one unreadable file inside a copied folder must cost a retry or
  a skip of that file, not the rest of the folder.

  A file that cannot be read (a network share dropping its session, a file
  another process holds exclusively) used to fail the whole recursive copy.
  The job then asked about the top-level item: "Retry" started the entire
  folder over and hit the same file again, "Skip" dropped the whole folder
  including every file not yet copied.

  The copy now retries the file by itself, then asks the token's error
  resolver. Retry repeats that file, Skip leaves it out and carries on. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCopyErrorResolver = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestSkipLeavesOnlyTheFailedFileOut;
    [Test] procedure TestRetryAsksAgainForTheSameFile;
    [Test] procedure TestCancelAnswerFailsTheCopy;
    [Test] procedure TestAutoRetriesComeBeforeTheQuestion;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uFileVfs;

var
  GRoot: string;
  GSavedRetries, GSavedDelay: Integer;

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

function RunCopy(const ASrc, ADst: string; ACancel: IJobCancelToken;
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
    Vfs.CopyAsync(PathToFileUri(ASrc), PathToFileUri(ADst), ACancel,
      procedure(const ADone, ATotal: Int64; const AName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string) begin end,
      procedure(const ASuccess: Boolean; const AErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AErr;
        Ev.SetEvent;
      end, False, False);
    if not WaitEvent(Ev) then
    begin
      Assert.Fail('copy timed out');
      Exit(False);
    end;
    AError := Err;
    Result := Ok;
  finally
    Ev.Free;
  end;
end;

// a_ok.txt, b_locked.bin (held exclusively by the caller), c_after.txt and
// sub\d_nested.txt: the files after the locked one are what must survive.
procedure MakeFixture(const AName: string; out ASrc, ADst: string;
  out AHold: TFileStream);
begin
  ASrc := TPath.Combine(GRoot, AName + '_src');
  ADst := TPath.Combine(GRoot, AName + '_dst');
  TDirectory.CreateDirectory(TPath.Combine(ASrc, 'sub'));
  TFile.WriteAllText(TPath.Combine(ASrc, 'a_ok.txt'), 'a', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ASrc, 'c_after.txt'), 'c', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ASrc, 'sub', 'd_nested.txt'), 'd', TEncoding.ASCII);
  AHold := TFileStream.Create(TPath.Combine(ASrc, 'b_locked.bin'),
    fmCreate or fmShareExclusive);
end;

procedure TTestCopyErrorResolver.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopyErrorResolver');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
  GSavedRetries := CopyAutoRetries;
  GSavedDelay := CopyRetryBaseDelayMs;
  // The waits between automatic retries are not what these tests measure.
  CopyAutoRetries := 0;
  CopyRetryBaseDelayMs := 10;
end;

procedure TTestCopyErrorResolver.TearDownFixture;
begin
  CopyAutoRetries := GSavedRetries;
  CopyRetryBaseDelayMs := GSavedDelay;
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestCopyErrorResolver.TestSkipLeavesOnlyTheFailedFileOut;
var
  Src, Dst: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
  Asked: Integer;
  FailedUri: string;
begin
  MakeFixture('skip', Src, Dst, Hold);
  try
    Asked := 0;
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Inc(Asked);
        FailedUri := AError.URI;
        Result := vcaSkip;
      end;
    Assert.IsTrue(RunCopy(Src, Dst, Token, Err),
      'copy succeeds once the failed file is skipped (' + Err.Message + ')');
    Assert.AreEqual(1, Asked, 'asked once, for the one failed file');
    Assert.IsTrue(Pos('b_locked.bin', FailedUri) > 0,
      'the question names the file that failed (was: ' + FailedUri + ')');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'a_ok.txt')), 'file before it copied');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'c_after.txt')),
      'file after it copied (the reported symptom: the rest stayed uncopied)');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'sub', 'd_nested.txt')),
      'nested file copied');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Dst, 'b_locked.bin')),
      'the skipped file is not at the destination, not even as a fragment');
  finally
    Hold.Free;
  end;
end;

procedure TTestCopyErrorResolver.TestRetryAsksAgainForTheSameFile;
var
  Src, Dst: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
  Asked: Integer;
begin
  MakeFixture('retry', Src, Dst, Hold);
  try
    Asked := 0;
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Inc(Asked);
        // The file is still held, so the retry fails and asks again.
        if Asked = 1 then
          Result := vcaRetry
        else
          Result := vcaSkip;
      end;
    Assert.IsTrue(RunCopy(Src, Dst, Token, Err), 'copy succeeds');
    Assert.AreEqual(2, Asked, 'a retry that fails again asks again');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'c_after.txt')), 'rest copied');
  finally
    Hold.Free;
  end;
end;

procedure TTestCopyErrorResolver.TestCancelAnswerFailsTheCopy;
var
  Src, Dst: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
begin
  MakeFixture('cancel', Src, Dst, Hold);
  try
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Result := vcaCancel;
      end;
    Assert.IsFalse(RunCopy(Src, Dst, Token, Err), 'copy stops on a cancel answer');
    Assert.IsTrue(Err.Code = vecCancelled, 'reported as cancelled');
  finally
    Hold.Free;
  end;
end;

procedure TTestCopyErrorResolver.TestAutoRetriesComeBeforeTheQuestion;
var
  Src, Dst: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
  Retries: Integer;
begin
  MakeFixture('auto', Src, Dst, Hold);
  Retries := CopyAutoRetries;
  CopyAutoRetries := 2;
  try
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        // By now the file was tried 1 + 2 times; free it for the retry.
        Hold.Free;
        Hold := nil;
        Result := vcaRetry;
      end;
    Assert.IsTrue(RunCopy(Src, Dst, Token, Err),
      'once the file is readable again the retry copies it (' + Err.Message + ')');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'b_locked.bin')),
      'the retried file arrived');
  finally
    CopyAutoRetries := Retries;
    Hold.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCopyErrorResolver);

end.
