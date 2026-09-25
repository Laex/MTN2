program TestDualPanelJobsManager;

{ TPanelJobList facade: confirm vs overlay, AskJobId, cancel of a queued
  confirm without starting I/O. Conflict/cap math lives in TestDualPanelJobRules. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes in '..\..\Core\uVfsTypes.pas',
  uFileVfs in '..\..\Core\uFileVfs.pas',
  uZipVfs in '..\..\Core\uZipVfs.pas',
  uFindSession in '..\..\Core\uFindSession.pas',
  uFindVfs in '..\..\Core\uFindVfs.pas',
  uVfsRegistry in '..\..\Core\uVfsRegistry.pas',
  uVfsRouter in '..\..\Core\uVfsRouter.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uDualPanelJobRules in '..\..\Core\uDualPanelJobRules.pas',
  uDualPanelJobs in '..\..\Core\uDualPanelJobs.pas',
  uDualPanelJobList in '..\..\Core\uDualPanelJobList.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

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
  Writeln('List facade');
  Jobs := MakeList;
  try
    Expect(Jobs.CanStartAnother, 'empty list can start');
    Expect(Jobs.Phase = pjpNone, 'empty phase');
    Expect(not Jobs.OwnsInput, 'empty does not own input');
    Expect(not Jobs.ShowsOverlay, 'empty has no overlay');
    Expect(not Jobs.BlocksNewOperation, 'empty does not block new op');
    Expect(Jobs.AskJobId = 0, 'no ask id');
    Expect(Jobs.Count = 0, 'empty count');

    Jobs.BeginJob(TArray<string>.Create('file:///C:/src/a.txt'),
      'file:///D:/dst/', pjkCopy);
    Expect(Jobs.Phase = pjpConfirm, 'begin is confirm');
    Expect(Jobs.Kind = pjkCopy, 'confirm kind is copy');
    Expect(Jobs.BlocksNewOperation, 'confirm blocks new op');
    Expect(not Jobs.OwnsInput, 'confirm leaves keys to dialog');
    Expect(not Jobs.ShowsOverlay, 'confirm has no overlay');
    Expect(Jobs.CanStartAnother, 'confirm still under cap');
    Expect(Jobs.Count = 1, 'confirm counts as busy');
    Expect(Jobs.JobIdAt(0) > 0, 'confirm has an id');
    Lines := Jobs.ListLines;
    Expect(Length(Lines) = 1, 'list has one line');

    Jobs.BackgroundJob;
    Expect(Jobs.Phase = pjpConfirm, 'background during confirm is a no-op');

    Jobs.CloseJobUi;
    Expect(Jobs.Phase = pjpNone, 'close returns idle');
    Expect(not Jobs.BlocksNewOperation, 'idle after close');
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
  Writeln('Background reloads panels');
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
    Expect(Jobs.Phase in [pjpRunning, pjpNone, pjpError], 'confirm starts or finishes');
    if Jobs.Phase = pjpRunning then
    begin
      Reloads := 0;
      Jobs.BackgroundJob;
      Expect(Jobs.State.Presentation = jpBackground, 'progress Background goes to bg');
      Expect(Reloads >= 1, 'background from running reloads panels');
      Jobs.RequestCancel;
    end
    else
      Expect(True, 'copy finished before Background; skip live-job assert');
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
  Writeln('Cancel confirm');
  Jobs := MakeList;
  try
    Jobs.BeginJob(TArray<string>.Create('file:///C:/src/b.txt'),
      'file:///D:/dst/', pjkDelete, True);
    Expect(Jobs.Phase = pjpConfirm, 'delete confirm');
    Jobs.CancelJobByIndex(0);
    Expect(Jobs.Phase = pjpNone, 'cancel confirm closes the job');
  finally
    Jobs.Free;
  end;
end;

begin
  try
    Writeln('=== TestDualPanelJobsManager ===');
    TestListFacade;
    TestBackgroundReloadsPanels;
    TestCancelConfirm;
    Writeln('All DualPanelJobsManager tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.Message);
      Halt(1);
    end;
  end;
end.
