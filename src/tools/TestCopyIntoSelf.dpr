program TestCopyIntoSelf;

{ Regression: TFileVirtualFileSystem.CopyAsync must reject copying a folder
  into itself or into one of its own subfolders. CopyTree (uFileVfs.pas)
  recurses over the source directory's own FindFirst listing — if the
  destination lives inside the source, the freshly-created destination
  folder gets picked up by that same walk and copied into itself again,
  indefinitely. See IsSameOrDescendantPath / the guard in CopyAsync. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uTextEncoding in '..\Core\uTextEncoding.pas',
  uFileVfs in '..\Core\uFileVfs.pas',
  uZipVfs in '..\Core\uZipVfs.pas',
  uFindSession in '..\Core\uFindSession.pas',
  uFindVfs in '..\Core\uFindVfs.pas',
  uVfsRegistry in '..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\Core\uVfsRouter.pas';

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
      Writeln('  [FAIL] copy timed out (would indicate the recursion regressed)');
      Inc(GFailures);
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
  Writeln('TestCopyIntoOwnSubfolder (dst is nested inside src)');
  Src := TPath.Combine(GRoot, 'tree');
  Dst := TPath.Combine(Src, 'sub');
  TDirectory.CreateDirectory(TPath.Combine(Src, 'sub'));
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Dst, Err);
  Check(not Ok, 'copy is rejected, not started');
  Check(Err.Code = vecInvalidURI, 'error code is vecInvalidURI');

  // The whole point: no runaway recursion. If the guard regressed, this
  // count would keep growing (nested sub\sub\sub\... copies of the tree).
  Check(not TDirectory.Exists(TPath.Combine(Dst, 'sub')),
    'destination was not touched — no nested self-copy was created');
end;

procedure TestCopyOntoSelf;
var
  Src: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestCopyOntoSelf (dst equals src)');
  Src := TPath.Combine(GRoot, 'same');
  TDirectory.CreateDirectory(Src);
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Src, Err);
  Check(not Ok, 'copy is rejected, not started');
  Check(Err.Code = vecInvalidURI, 'error code is vecInvalidURI');
end;

procedure TestCopySiblingStillWorks;
var
  Src, Dst: string;
  Err: TVfsError;
  Ok: Boolean;
begin
  Writeln('TestCopySiblingStillWorks (control: unrelated destination is unaffected)');
  Src := TPath.Combine(GRoot, 'sibling_src');
  Dst := TPath.Combine(GRoot, 'sibling_dst');
  TDirectory.CreateDirectory(Src);
  WriteTextFile(TPath.Combine(Src, 'a.txt'), 'a');

  Ok := RunCopy(Src, Dst, Err);
  Check(Ok, 'copy to a sibling folder still succeeds');
  Check(TFile.Exists(TPath.Combine(Dst, 'a.txt')), 'file was actually copied');
end;

begin
  try
    GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestCopyIntoSelf');
    if TDirectory.Exists(GRoot) then
      TDirectory.Delete(GRoot, True);
    TDirectory.CreateDirectory(GRoot);
    Writeln('=== TestCopyIntoSelf ===');
    Writeln('temp: ', GRoot);
    Writeln;

    TestCopyIntoOwnSubfolder;
    TestCopyOntoSelf;
    TestCopySiblingStillWorks;

    Writeln;
    try
      if TDirectory.Exists(GRoot) then
        TDirectory.Delete(GRoot, True);
    except
      // best-effort cleanup
    end;

    if GFailures = 0 then
      Writeln('All CopyIntoSelf tests PASSED')
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
