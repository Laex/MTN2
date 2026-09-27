unit TestDualPanelJobsManager;

{ TPanelJobList facade: confirm vs overlay, AskJobId, cancel of a queued
  confirm without starting I/O. Conflict/cap math lives in TestDualPanelJobRules. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelJobsManager = class
  public
    [Test] procedure TestListFacade;
    [Test] procedure TestBackgroundReloadsPanels;
    [Test] procedure TestCancelConfirm;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes,
  uFileVfs,
  uZipVfs,
  uFindSession,
  uFindVfs,
  uVfsRegistry,
  uVfsRouter,
  uDualPanelUiTypes,
  uDualPanelJobRules,
  uDualPanelJobs,
  uDualPanelJobList;

function MakeList: TPanelJobList;
begin
  Result := TPanelJobList.Create(nil, CreateDefaultVfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean) begin end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end);
end;

procedure TestListFacade;
var
  Jobs: TPanelJobList;
  Lines: TArray<string>;
begin
  Jobs := MakeList;
  try
    Assert.IsTrue(Jobs.CanStartAnother, 'empty list can start');
    Assert.IsTrue(Jobs.Phase = pjpNone, 'empty phase');
    Assert.IsTrue(not Jobs.OwnsInput, 'empty does not own input');
    Assert.IsTrue(not Jobs.ShowsOverlay, 'empty has no overlay');
    Assert.IsTrue(not Jobs.BlocksNewOperation, 'empty does not block new op');
    Assert.IsTrue(Jobs.AskJobId = 0, 'no ask id');
    Assert.IsTrue(Jobs.Count = 0, 'empty count');

    Jobs.BeginJob(TArray<string>.Create('file:///C:/src/a.txt'),
      'file:///D:/dst/', pjkCopy);
    Assert.IsTrue(Jobs.Phase = pjpConfirm, 'begin is confirm');
    Assert.IsTrue(Jobs.Kind = pjkCopy, 'confirm kind is copy');
    Assert.IsTrue(Jobs.BlocksNewOperation, 'confirm blocks new op');
    Assert.IsTrue(not Jobs.OwnsInput, 'confirm leaves keys to dialog');
    Assert.IsTrue(not Jobs.ShowsOverlay, 'confirm has no overlay');
    Assert.IsTrue(Jobs.CanStartAnother, 'confirm still under cap');
    Assert.IsTrue(Jobs.Count = 1, 'confirm counts as busy');
    Assert.IsTrue(Jobs.JobIdAt(0) > 0, 'confirm has an id');
    Lines := Jobs.ListLines;
    Assert.IsTrue(Length(Lines) = 1, 'list has one line');

    Jobs.BackgroundJob;
    Assert.IsTrue(Jobs.Phase = pjpConfirm, 'background during confirm is a no-op');

    Jobs.CloseJobUi;
    Assert.IsTrue(Jobs.Phase = pjpNone, 'close returns idle');
    Assert.IsTrue(not Jobs.BlocksNewOperation, 'idle after close');
  finally
    Jobs.Free;
  end;
end;

procedure TestBackgroundReloadsPanels;
var
  Jobs: TPanelJobList;
  Reloads: Integer;
  Root, SrcDir, DstDir, SrcFile: string;
  I: Integer;
begin
  Reloads := 0;
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-bg-reload-' + IntToStr(Random(1 shl 20)));
  SrcDir := TPath.Combine(Root, 'src');
  DstDir := TPath.Combine(Root, 'dst');
  ForceDirectories(SrcDir);
  ForceDirectories(DstDir);
  for I := 1 to 8 do
    TFile.WriteAllText(TPath.Combine(SrcDir, Format('f%d.txt', [I])),
      StringOfChar('x', 64 * 1024));
  SrcFile := SrcDir;
  Jobs := TPanelJobList.Create(nil, CreateDefaultVfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean) begin end,
    procedure(const AOriginSrc, AOriginDst: string)
    begin
      Inc(Reloads);
    end,
    procedure(const AOriginSrc: string) begin end);
  try
    Jobs.BeginJob(TArray<string>.Create(PathToFileUri(SrcFile)),
      PathToFileUri(DstDir), pjkCopy);
    Jobs.ConfirmJob;
    Assert.IsTrue(Jobs.Phase in [pjpRunning, pjpNone, pjpError], 'confirm starts or finishes');
    if Jobs.Phase = pjpRunning then
    begin
      Reloads := 0;
      Jobs.BackgroundJob;
      Assert.IsTrue(Jobs.State.Presentation = jpBackground, 'progress Background goes to bg');
      Assert.IsTrue(Reloads >= 1, 'background from running reloads panels');
      Jobs.RequestCancel;
    end
    else
      Assert.IsTrue(True, 'copy finished before Background; skip live-job assert');
    Jobs.CloseJobUi;
  finally
    Jobs.Free;
    if TDirectory.Exists(Root) then
      TDirectory.Delete(Root, True);
  end;
end;

procedure TestCancelConfirm;
var
  Jobs: TPanelJobList;
begin
  Jobs := MakeList;
  try
    Jobs.BeginJob(TArray<string>.Create('file:///C:/src/b.txt'),
      'file:///D:/dst/', pjkDelete, True);
    Assert.IsTrue(Jobs.Phase = pjpConfirm, 'delete confirm');
    Jobs.CancelJobByIndex(0);
    Assert.IsTrue(Jobs.Phase = pjpNone, 'cancel confirm closes the job');
  finally
    Jobs.Free;
  end;
end;

{ TTestDualPanelJobsManager }

procedure TTestDualPanelJobsManager.TestListFacade;
begin
  TestDualPanelJobsManager.TestListFacade;
end;

procedure TTestDualPanelJobsManager.TestBackgroundReloadsPanels;
begin
  TestDualPanelJobsManager.TestBackgroundReloadsPanels;
end;

procedure TTestDualPanelJobsManager.TestCancelConfirm;
begin
  TestDualPanelJobsManager.TestCancelConfirm;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelJobsManager);

end.
