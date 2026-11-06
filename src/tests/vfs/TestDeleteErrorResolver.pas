unit TestDeleteErrorResolver;

{ A file that cannot be deleted inside a deleted folder is put to the token's
  error resolver on its own: retry repeats that file, skip leaves it (and the
  folders above it) in place and removes everything else, any other answer
  stops the delete. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDeleteErrorResolver = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestSkipLeavesOnlyTheLockedFileAndItsFolders;
    [Test] procedure TestSkipCountsTheSkippedFile;
    [Test] procedure TestRetryAsksAgainForTheSameFile;
    [Test] procedure TestRetrySucceedsOnceTheFileIsFree;
    [Test] procedure TestCancelAnswerStopsTheDelete;
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

function RunDelete(const APath: string; ACancel: IJobCancelToken;
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
    Vfs.DeleteAsync(PathToFileUri(APath), vdmPermanent, ACancel,
      procedure(const ADone, ATotal: Int64; const AName: string;
        const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string) begin end,
      procedure(const ASuccess: Boolean; const AErr: TVfsError)
      begin
        Ok := ASuccess;
        Err := AErr;
        Ev.SetEvent;
      end);
    if not WaitEvent(Ev) then
    begin
      Assert.Fail('delete timed out');
      Exit(False);
    end;
    AError := Err;
    Result := Ok;
  finally
    Ev.Free;
  end;
end;

// a_ok.txt, sub\b_locked.bin (held exclusively by the caller), sub\c_after.txt,
// z_last.txt and other\d_free.txt.
procedure MakeFixture(const AName: string; out ARoot: string; out AHold: TFileStream);
begin
  ARoot := TPath.Combine(GRoot, AName);
  TDirectory.CreateDirectory(TPath.Combine(ARoot, 'sub'));
  TDirectory.CreateDirectory(TPath.Combine(ARoot, 'other'));
  TFile.WriteAllText(TPath.Combine(ARoot, 'a_ok.txt'), 'a', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ARoot, 'sub', 'c_after.txt'), 'c', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ARoot, 'z_last.txt'), 'z', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(ARoot, 'other', 'd_free.txt'), 'd', TEncoding.ASCII);
  AHold := TFileStream.Create(TPath.Combine(ARoot, 'sub', 'b_locked.bin'),
    fmCreate or fmShareExclusive);
end;

procedure TTestDeleteErrorResolver.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestDeleteErrorResolver');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestDeleteErrorResolver.TearDownFixture;
begin
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestDeleteErrorResolver.TestSkipLeavesOnlyTheLockedFileAndItsFolders;
var
  Root: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
  Asked: Integer;
  FailedUri: string;
begin
  MakeFixture('skip', Root, Hold);
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
    Assert.IsTrue(RunDelete(Root, Token, Err),
      'delete succeeds once the locked file is skipped (' + Err.Message + ')');
    Assert.AreEqual(1, Asked, 'asked once: the folders above the skipped file are not tried');
    Assert.IsTrue(Pos('b_locked.bin', FailedUri) > 0,
      'the question names the file that failed (was: ' + FailedUri + ')');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'a_ok.txt')), 'file before it deleted');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'sub', 'c_after.txt')),
      'file next to it deleted');
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'z_last.txt')), 'file after it deleted');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(Root, 'other')),
      'a folder without skipped files is removed');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Root, 'sub', 'b_locked.bin')),
      'the skipped file stays');
  finally
    Hold.Free;
  end;
end;

procedure TTestDeleteErrorResolver.TestSkipCountsTheSkippedFile;
var
  Root: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
begin
  MakeFixture('count', Root, Hold);
  try
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Result := vcaSkip;
      end;
    Assert.IsTrue(RunDelete(Root, Token, Err), 'delete succeeds');
    Assert.AreEqual(1, Token.GetSkippedCount, 'the skipped file is counted');
  finally
    Hold.Free;
  end;
end;

procedure TTestDeleteErrorResolver.TestRetryAsksAgainForTheSameFile;
var
  Root: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
  Asked: Integer;
begin
  MakeFixture('retry', Root, Hold);
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
    Assert.IsTrue(RunDelete(Root, Token, Err), 'delete succeeds');
    Assert.AreEqual(2, Asked, 'a retry that fails again asks again');
  finally
    Hold.Free;
  end;
end;

procedure TTestDeleteErrorResolver.TestRetrySucceedsOnceTheFileIsFree;
var
  Root: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
begin
  MakeFixture('free', Root, Hold);
  try
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Hold.Free;
        Hold := nil;
        Result := vcaRetry;
      end;
    Assert.IsTrue(RunDelete(Root, Token, Err),
      'the retried file goes and the delete completes (' + Err.Message + ')');
    Assert.IsFalse(TDirectory.Exists(Root), 'nothing is left behind');
  finally
    Hold.Free;
  end;
end;

procedure TTestDeleteErrorResolver.TestCancelAnswerStopsTheDelete;
var
  Root: string;
  Hold: TFileStream;
  Token: TJobCancelToken;
  Err: TVfsError;
begin
  MakeFixture('cancel', Root, Hold);
  try
    Token := TJobCancelToken.Create;
    Token.ErrorResolver :=
      function(const AError: TVfsError): TVfsConflictAction
      begin
        Result := vcaCancel;
      end;
    Assert.IsFalse(RunDelete(Root, Token, Err), 'delete stops on a cancel answer');
    Assert.IsTrue(Err.Code = vecCancelled, 'reported as cancelled');
  finally
    Hold.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDeleteErrorResolver);

end.
