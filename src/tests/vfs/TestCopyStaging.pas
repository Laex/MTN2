unit TestCopyStaging;

{ A copy writes into a sibling "<name>.mtnpart" and gives it the real name only
  when the bytes are complete: while the copy runs, nothing sits under the
  destination's name, and a cancelled copy leaves neither file. The speed limit
  slows the copy so the test can look at the folder while it is in flight. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCopyStaging = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestDestinationNameAppearsOnlyWhenComplete;
    [Test] procedure TestCancelledCopyLeavesNothing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs,
  uVfsTypes, uFileVfs;

const
  cPartSuffix = '.mtnpart';
  cFileBytes = 3 * 1024 * 1024;
  // Slow enough that the copy takes a few seconds, fast enough for the test.
  cSlowKBps = 1024;

var
  GRoot: string;

procedure MakeSourceFile(const APath: string);
var
  Bytes: TBytes;
begin
  SetLength(Bytes, cFileBytes);
  FillChar(Bytes[0], Length(Bytes), Ord('x'));
  TFile.WriteAllBytes(APath, Bytes);
end;

// Starts a slow copy of ASrc to ADst and waits until the part file shows up.
// True when it did; ADone is set when the copy finishes.
function StartSlowCopy(const ASrc, ADst: string; out AToken: IJobCancelToken;
  out ADone: TEvent; out AOk: Boolean): Boolean;
var
  Vfs: IVirtualFileSystem;
  Ok: Boolean;
  Done: TEvent;
  Tick: UInt64;
begin
  AToken := TJobCancelToken.Create;
  (AToken as IJobThrottle).SetLimitKBps(cSlowKBps);
  Done := TEvent.Create(nil, True, False, '');
  ADone := Done;
  Ok := False;
  Vfs := TFileVirtualFileSystem.Create;
  Vfs.CopyAsync(PathToFileUri(ASrc), PathToFileUri(ADst), AToken,
    procedure(const ADoneBytes, ATotal: Int64; const AName: string;
      const AItemDone, AItemTotal: Int64; const AItemSrcPath, AItemDstPath: string)
    begin
    end,
    procedure(const ASuccess: Boolean; const AErr: TVfsError)
    begin
      Ok := ASuccess;
      Done.SetEvent;
    end, False, False);
  Tick := TThread.GetTickCount64;
  Result := False;
  while TThread.GetTickCount64 - Tick < 20000 do
  begin
    if TFile.Exists(ADst + cPartSuffix) then
      Exit(True);
    CheckSynchronize(10);
  end;
  AOk := Ok;
end;

function WaitFor(AEvent: TEvent): Boolean;
var
  Tick: UInt64;
begin
  Tick := TThread.GetTickCount64;
  while AEvent.WaitFor(20) <> wrSignaled do
  begin
    CheckSynchronize;
    if TThread.GetTickCount64 - Tick > 60000 then
      Exit(False);
  end;
  CheckSynchronize;
  Result := True;
end;

procedure TTestCopyStaging.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopyStaging');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestCopyStaging.TearDownFixture;
begin
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestCopyStaging.TestDestinationNameAppearsOnlyWhenComplete;
var
  Src, Dst: string;
  Token: IJobCancelToken;
  Done: TEvent;
  Ok, Started: Boolean;
begin
  Src := TPath.Combine(GRoot, 'whole-src.bin');
  Dst := TPath.Combine(GRoot, 'whole-dst.bin');
  MakeSourceFile(Src);
  Started := StartSlowCopy(Src, Dst, Token, Done, Ok);
  try
    Assert.IsTrue(Started, 'the part file appears while the copy runs');
    Assert.IsFalse(TFile.Exists(Dst), 'nothing under the real name yet');
    (Token as IJobThrottle).SetLimitKBps(0);
    Assert.IsTrue(WaitFor(Done), 'copy finishes');
    Assert.IsTrue(TFile.Exists(Dst));
    Assert.AreEqual(Int64(cFileBytes), TFile.GetSize(Dst));
    Assert.IsFalse(TFile.Exists(Dst + cPartSuffix), 'the part file is gone');
  finally
    (Token as IJobThrottle).SetLimitKBps(0);
    Done.Free;
  end;
end;

procedure TTestCopyStaging.TestCancelledCopyLeavesNothing;
var
  Src, Dst: string;
  Token: IJobCancelToken;
  Done: TEvent;
  Ok, Started: Boolean;
begin
  Src := TPath.Combine(GRoot, 'cancel-src.bin');
  Dst := TPath.Combine(GRoot, 'cancel-dst.bin');
  MakeSourceFile(Src);
  Started := StartSlowCopy(Src, Dst, Token, Done, Ok);
  try
    Assert.IsTrue(Started, 'the part file appears while the copy runs');
    Token.Cancel;
    Assert.IsTrue(WaitFor(Done), 'copy ends after the cancel');
    Assert.IsFalse(TFile.Exists(Dst), 'no destination file');
    Assert.IsFalse(TFile.Exists(Dst + cPartSuffix), 'no part file');
  finally
    (Token as IJobThrottle).SetLimitKBps(0);
    Done.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCopyStaging);

end.
