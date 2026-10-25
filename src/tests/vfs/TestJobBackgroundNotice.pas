unit TestJobBackgroundNotice;

{ A job that ends while it runs in the background raises a notice (toast); a
  job the user watched in the foreground, or one that was only in the
  background for a moment, does not. A failure in the background is always
  announced. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestJobBackgroundNotice = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestForegroundCopyRaisesNoNotice;
    [Test] procedure TestBackgroundCopyRaisesNotice;
    [Test] procedure TestShortBackgroundCopyRaisesNoNotice;
    [Test] procedure TestBackgroundFailureRaisesWarning;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  uVfsTypes,
  uFileVfs,
  uVfsRegistry,
  uVfsRouter,
  uNotice,
  uDualPanelUiTypes,
  uDualPanelJobs;

var
  GRoot: string;
  GNotices: TList<TNoticeRequest>;

procedure TTestJobBackgroundNotice.SetupFixture;
begin
  GRoot := TPath.Combine(TPath.GetTempPath, 'MTN2_TestJobBackgroundNotice');
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
  TDirectory.CreateDirectory(GRoot);
  GNotices := TList<TNoticeRequest>.Create;
end;

procedure TTestJobBackgroundNotice.TearDownFixture;
begin
  SetNoticeHandler(nil);
  FreeAndNil(GNotices);
  if TDirectory.Exists(GRoot) then
    TDirectory.Delete(GRoot, True);
end;

/// <summary>Runs one job of AKind over ASource into ADestDir until it finishes
/// or stops on an error, collecting the notices it raises. ABackground sends
/// it to the background right after it starts.</summary>
procedure RunJob(AKind: TPanelJobKind; const ASource, ADestDir: string;
  ABackground: Boolean; AMinMs: Integer);
var
  Jobs: TPanelJobController;
  Done: Boolean;
  Tick: UInt64;
  SavedMinMs: Integer;
begin
  GNotices.Clear;
  SetNoticeHandler(
    procedure(const ARequest: TNoticeRequest)
    begin
      GNotices.Add(ARequest);
    end);
  SavedMinMs := JobBackgroundToastMinMs;
  JobBackgroundToastMinMs := AMinMs;
  Done := False;
  Jobs := TPanelJobController.Create(nil, CreateDefaultVfs,
    procedure begin end,
    procedure(const ATitle, AMessage: string) begin end,
    procedure(const APath, ANewLine, AExistingLine: string) begin end,
    procedure(const APath, AHeadline, AQuestion, AErrorLine: string;
      AOfferPermanent: Boolean) begin end,
    procedure(const AHeadline, APath, AErrorLine: string) begin end,
    procedure(ASucceeded: Boolean)
    begin
      Done := True;
    end,
    procedure(const AOriginSrc, AOriginDst: string) begin end,
    procedure(const AOriginSrc: string) begin end,
    nil);
  try
    Jobs.BeginJob(TArray<string>.Create(PathToFileUri(ASource)),
      PathToFileUri(ADestDir), AKind);
    Jobs.ApplyCopyMoveOptions(PathToFileUri(ADestDir), jomOverwrite, False);
    Jobs.ConfirmJob;
    if ABackground then
      Jobs.BackgroundJob;
    Tick := TThread.GetTickCount64;
    while not Done and (Jobs.Phase <> pjpError) do
    begin
      CheckSynchronize(20);
      if TThread.GetTickCount64 - Tick > 30000 then
      begin
        Assert.Fail('job timed out');
        Break;
      end;
    end;
  finally
    Jobs.Free;
    JobBackgroundToastMinMs := SavedMinMs;
    SetNoticeHandler(nil);
  end;
end;

function MakeSourceFile(const AName: string): string;
begin
  Result := TPath.Combine(GRoot, AName);
  TFile.WriteAllText(Result, 'data', TEncoding.ASCII);
end;

function MakeDestDir(const AName: string): string;
begin
  Result := TPath.Combine(GRoot, AName);
  TDirectory.CreateDirectory(Result);
end;

procedure TTestJobBackgroundNotice.TestForegroundCopyRaisesNoNotice;
begin
  RunJob(pjkCopy, MakeSourceFile('fg.txt'), MakeDestDir('fg_dest'), False, 0);
  Assert.IsTrue(GNotices.Count = 0, 'a job watched in the foreground raises no notice');
end;

procedure TTestJobBackgroundNotice.TestBackgroundCopyRaisesNotice;
begin
  RunJob(pjkCopy, MakeSourceFile('bg.txt'), MakeDestDir('bg_dest'), True, 0);
  Assert.IsTrue(GNotices.Count = 1, 'a job that ends in the background raises one notice');
  Assert.AreEqual('bg.txt', GNotices[0].Arg, 'the notice names the single source');
  Assert.IsTrue(Pos('%s', GNotices[0].Template) > 0, 'the source name goes into the template');
  Assert.IsTrue(GNotices[0].Kind = tkInfo, 'a success is an info toast');
  Assert.IsTrue(not GNotices[0].Always, 'a success follows the notifications setting');
end;

procedure TTestJobBackgroundNotice.TestShortBackgroundCopyRaisesNoNotice;
begin
  RunJob(pjkCopy, MakeSourceFile('short.txt'), MakeDestDir('short_dest'), True, 600000);
  Assert.IsTrue(GNotices.Count = 0,
    'a job that was in the background only briefly raises no notice');
end;

procedure TTestJobBackgroundNotice.TestBackgroundFailureRaisesWarning;
begin
  // Unpack of a plain text file stops with an error.
  RunJob(pjkUnpack, MakeSourceFile('plain.txt'), MakeDestDir('fail_dest'), True, 0);
  Assert.IsTrue(GNotices.Count = 1, 'a background failure raises one notice');
  Assert.IsTrue(GNotices[0].Kind = tkWarning, 'a failure is a warning');
  Assert.IsTrue(GNotices[0].Always, 'a failure is shown even with notifications off');
  Assert.IsTrue(GNotices[0].Arg <> '', 'the notice carries the error message');
  Assert.IsTrue(GNotices[0].Hint <> '', 'the notice says where to look');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestJobBackgroundNotice);

end.
