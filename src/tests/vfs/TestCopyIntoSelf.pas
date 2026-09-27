unit TestCopyIntoSelf;

{ Regression: TFileVirtualFileSystem.CopyAsync must reject copying a folder
  into itself or into one of its own subfolders. CopyTree (uFileVfs.pas)
  recurses over the source directory's own FindFirst listing — if the
  destination lives inside the source, the freshly-created destination
  folder gets picked up by that same walk and copied into itself again,
  indefinitely. See IsSameOrDescendantPath / the guard in CopyAsync. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCopyIntoSelf = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestCopyIntoOwnSubfolder;
    [Test] procedure TestCopyOntoSelf;
    [Test] procedure TestCopySiblingStillWorks;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes,
  uTextEncoding,
  uFileVfs,
  uZipVfs,
  uFindSession,
  uFindVfs,
  uVfsRegistry,
  uVfsRouter;

var
  GRoot: string;

procedure WriteTextFile(const APath, AContent: string);
begin
  TFile.WriteAllText(APath, AContent, TEncoding.ASCII);
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

function RunCopy(const ASrc, ADst: string; out AError: TVfsError): Boolean;
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
      end, False, False);
    if not WaitEvent(Ev) then
    begin
      Assert.Fail('copy timed out (would indicate the recursion regressed)');
      Exit(False);
    end;
    AError := Err;
    Result := Ok;
  finally
    Ev.Free;
  end;
end;

{ ---- tests ------------------------------------------------------------------ }

procedure TestCopyIntoOwnSubfolder;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Src := TPath.Combine(GRoot, 'tree');
  Dst := TPath.Combine(Src, 'sub');
  TDirectory.CreateDirectory(TPath.Combine(Src, 'sub'));
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Dst, Err);
  Assert.IsTrue(not Ok, 'copy is rejected, not started');
  Assert.IsTrue(Err.Code = vecInvalidURI, 'error code is vecInvalidURI');

  // The whole point: no runaway recursion. If the guard regressed, this
  // count would keep growing (nested sub\sub\sub\... copies of the tree).
  Assert.IsTrue(not TDirectory.Exists(TPath.Combine(Dst, 'sub')),
    'destination was not touched — no nested self-copy was created');
end;

procedure TestCopyOntoSelf;
var
  Src: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Src := TPath.Combine(GRoot, 'same');
  TDirectory.CreateDirectory(Src);
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Src, Err);
  Assert.IsTrue(not Ok, 'copy is rejected, not started');
  Assert.IsTrue(Err.Code = vecInvalidURI, 'error code is vecInvalidURI');
end;

procedure TestCopySiblingStillWorks;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Src := TPath.Combine(GRoot, 'sibling_src');
  Dst := TPath.Combine(GRoot, 'sibling_dst');
  TDirectory.CreateDirectory(Src);
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Dst, Err);
  Assert.IsTrue(Ok, 'copy to a sibling folder still succeeds');
  Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'a.txt')), 'file was actually copied');
end;

{ TTestCopyIntoSelf }

procedure TTestCopyIntoSelf.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopyIntoSelf');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
end;

procedure TTestCopyIntoSelf.TearDownFixture;
begin
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

procedure TTestCopyIntoSelf.TestCopyIntoOwnSubfolder;
begin
  TestCopyIntoSelf.TestCopyIntoOwnSubfolder;
end;

procedure TTestCopyIntoSelf.TestCopyOntoSelf;
begin
  TestCopyIntoSelf.TestCopyOntoSelf;
end;

procedure TTestCopyIntoSelf.TestCopySiblingStillWorks;
begin
  TestCopyIntoSelf.TestCopySiblingStillWorks;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCopyIntoSelf);

end.
