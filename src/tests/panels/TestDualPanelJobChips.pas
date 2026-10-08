unit TestDualPanelJobChips;

{ Background-job chips on the tab bar: which jobs get one, the glyph and caption
  of each, right-aligned layout with overflow, and hit-testing. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelJobChips = class
  public
    [Test] procedure OnlyJobsOutOfSightGetChips;
    [Test] procedure StoppingJobHasNoChip;
    [Test] procedure EveryOperationHasItsOwnGlyph;
    [Test] procedure CaptionShowsProgressOrState;
    [Test] procedure ToneMarksAskAndError;
    [Test] procedure ChipsEndBeforeListButtonAtRightEdge;
    [Test] procedure ChipsThatDoNotFitAreLeftOut;
    [Test] procedure OverflowKeepsAskAndFailedChips;
    [Test] procedure NoRoomLeavesNoStrip;
    [Test] procedure NothingToShowLeavesNoStrip;
    [Test] procedure HitFindsChipListAndGap;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uDualPanelUiTypes,
  uDualPanelJobRules,
  uDualPanelJobChips;

function MakeJob(AId: Integer; AKind: TPanelJobKind; APhase: TPanelJobPhase;
  APresentation: TJobPresentation = jpBackground;
  ARecycle: Boolean = False): TPanelJobState;
begin
  Result := Default(TPanelJobState);
  Result.Id := AId;
  Result.Kind := AKind;
  Result.Phase := APhase;
  Result.Presentation := APresentation;
  Result.DeleteToRecycleBin := ARecycle;
  Result.FilesTotal := 10;
end;

procedure TTestDualPanelJobChips.OnlyJobsOutOfSightGetChips;
begin
  Assert.IsTrue(JobHasChip(MakeJob(1, pjkCopy, pjpRunning, jpBackground)),
    'background run');
  Assert.IsTrue(JobHasChip(MakeJob(1, pjkCopy, pjpError, jpBackground)),
    'background error');
  Assert.IsTrue(JobHasChip(MakeJob(1, pjkCopy, pjpQueued, jpForeground)),
    'queued');
  Assert.IsTrue(JobHasChip(MakeJob(1, pjkCopy, pjpOverwriteAsk, jpForeground)),
    'waiting for an answer');
  Assert.IsFalse(JobHasChip(MakeJob(1, pjkCopy, pjpRunning, jpForeground)),
    'foreground run has its progress dialog');
  Assert.IsFalse(JobHasChip(MakeJob(1, pjkCopy, pjpError, jpForeground)),
    'foreground error has its dialog');
  Assert.IsFalse(JobHasChip(MakeJob(1, pjkCopy, pjpConfirm, jpBackground)),
    'confirm is a dialog');
  Assert.IsFalse(JobHasChip(MakeJob(1, pjkCopy, pjpNone, jpBackground)), 'idle');
end;

procedure TTestDualPanelJobChips.StoppingJobHasNoChip;
var
  Job: TPanelJobState;
begin
  Job := MakeJob(1, pjkCopy, pjpRunning, jpBackground);
  Job.Cancel := TJobCancelToken.Create;
  Assert.IsTrue(JobHasChip(Job), 'a job nobody asked to stop keeps its chip');
  Job.Cancel.Cancel;
  Assert.IsFalse(JobHasChip(Job), 'a job told to stop drops its chip');
end;

procedure TTestDualPanelJobChips.EveryOperationHasItsOwnGlyph;
var
  Glyphs: array[0..5] of Char;
  I, J: Integer;
begin
  Glyphs[0] := JobKindGlyph(pjkCopy, False);
  Glyphs[1] := JobKindGlyph(pjkMove, False);
  Glyphs[2] := JobKindGlyph(pjkDelete, True);
  Glyphs[3] := JobKindGlyph(pjkDelete, False);
  Glyphs[4] := JobKindGlyph(pjkPack, False);
  Glyphs[5] := JobKindGlyph(pjkUnpack, False);
  for I := 0 to High(Glyphs) do
  begin
    Assert.IsTrue(Glyphs[I] <> '?', 'known operation, glyph ' + IntToStr(I));
    for J := I + 1 to High(Glyphs) do
      Assert.IsTrue(Glyphs[I] <> Glyphs[J], Format('glyphs %d and %d differ', [I, J]));
  end;
  Assert.IsTrue(JobKindGlyph(pjkNone, False) = '?', 'unknown operation');
end;

procedure TTestDualPanelJobChips.CaptionShowsProgressOrState;
var
  Job: TPanelJobState;
  Glyph: string;
begin
  Job := MakeJob(1, pjkCopy, pjpRunning);
  Job.FilesDone := 4;
  Glyph := JobKindGlyph(pjkCopy, False);
  Assert.AreEqual('[' + Glyph + ' 40%]', JobChipCaption(Job), 'running shows percent');
  Job.Phase := pjpQueued;
  Assert.AreEqual('[' + Glyph + ' ..]', JobChipCaption(Job), 'queued');
  Job.Phase := pjpIOErrorAsk;
  Assert.AreEqual('[' + Glyph + ' ?]', JobChipCaption(Job), 'waiting for an answer');
  Job.Phase := pjpError;
  Assert.AreEqual('[' + Glyph + ' !]', JobChipCaption(Job), 'failed');
end;

procedure TTestDualPanelJobChips.ToneMarksAskAndError;
begin
  Assert.IsTrue(JobChipTone(MakeJob(1, pjkCopy, pjpRunning)) = jctNormal, 'running');
  Assert.IsTrue(JobChipTone(MakeJob(1, pjkCopy, pjpQueued)) = jctNormal, 'queued');
  Assert.IsTrue(JobChipTone(MakeJob(1, pjkCopy, pjpDeleteAsk)) = jctAsk, 'ask');
  Assert.IsTrue(JobChipTone(MakeJob(1, pjkCopy, pjpError)) = jctError, 'error');
end;

procedure TTestDualPanelJobChips.ChipsEndBeforeListButtonAtRightEdge;
var
  Strip: TJobStrip;
begin
  Strip := LayoutJobStrip([MakeJob(1, pjkCopy, pjpRunning),
    MakeJob(2, pjkMove, pjpQueued), MakeJob(3, pjkPack, pjpRunning, jpForeground)],
    10, 80);
  Assert.AreEqual(2, Integer(Length(Strip.Chips)), 'the foreground job has no chip');
  Assert.AreEqual(1, Strip.Chips[0].JobId);
  Assert.AreEqual(2, Strip.Chips[1].JobId);
  Assert.AreEqual('[' + #$2261 + '2]', Strip.ListCaption, 'list counts the chips');
  Assert.AreEqual(80, Strip.ListLeft + Strip.ListWidth, 'list ends at the last column');
  Assert.AreEqual(Strip.Chips[0].Left + Strip.Chips[0].Width + 1, Strip.Chips[1].Left,
    'one column between chips');
  Assert.AreEqual(Strip.Chips[1].Left + Strip.Chips[1].Width + 1, Strip.ListLeft,
    'one column before the list button');
end;

procedure TTestDualPanelJobChips.ChipsThatDoNotFitAreLeftOut;
var
  Strip: TJobStrip;
  Jobs: TArray<TPanelJobState>;
  ChipW: Integer;
begin
  Jobs := [MakeJob(1, pjkCopy, pjpRunning), MakeJob(2, pjkCopy, pjpRunning),
    MakeJob(3, pjkCopy, pjpRunning)];
  ChipW := Length(JobChipCaption(Jobs[0]));
  // Room for the list button, a spacer and exactly two chips with spacers.
  Strip := LayoutJobStrip(Jobs, 0, 4 + 1 + 2 * (ChipW + 1));
  Assert.AreEqual(2, Integer(Length(Strip.Chips)), 'two chips fit');
  Assert.AreEqual(1, Strip.Chips[0].JobId, 'earlier jobs are kept');
  Assert.AreEqual(2, Strip.Chips[1].JobId);
  Assert.AreEqual('[' + #$2261 + '3]', Strip.ListCaption,
    'the list button still counts all jobs');
  Assert.IsTrue(Strip.Chips[0].Left >= 0, 'nothing left of the first column');
end;

procedure TTestDualPanelJobChips.OverflowKeepsAskAndFailedChips;
var
  Strip: TJobStrip;
  Jobs: TArray<TPanelJobState>;
  ChipW: Integer;
begin
  Jobs := [MakeJob(1, pjkCopy, pjpRunning), MakeJob(2, pjkCopy, pjpRunning),
    MakeJob(3, pjkCopy, pjpError), MakeJob(4, pjkCopy, pjpOverwriteAsk)];
  ChipW := Length(JobChipCaption(Jobs[0]));
  Strip := LayoutJobStrip(Jobs, 0, 4 + 1 + 3 * (ChipW + 1));
  Assert.AreEqual(3, Integer(Length(Strip.Chips)), 'three chips fit');
  Assert.AreEqual(1, Strip.Chips[0].JobId, 'the first running job takes the spare room');
  Assert.AreEqual(3, Strip.Chips[1].JobId, 'failed job is kept');
  Assert.AreEqual(4, Strip.Chips[2].JobId, 'job waiting for an answer is kept');
  Assert.AreEqual('[' + #$2261 + '4]', Strip.ListCaption, 'button counts all jobs');
  Assert.AreEqual(Strip.Chips[0].Left + Strip.Chips[0].Width + 1, Strip.Chips[1].Left,
    'kept chips stay contiguous');
end;

procedure TTestDualPanelJobChips.NoRoomLeavesNoStrip;
var
  Strip: TJobStrip;
begin
  Strip := LayoutJobStrip([MakeJob(1, pjkCopy, pjpRunning)], 78, 80);
  Assert.AreEqual(0, Strip.ListWidth, 'list button does not fit');
  Assert.AreEqual(0, Integer(Length(Strip.Chips)), 'no chips without the button');
end;

procedure TTestDualPanelJobChips.NothingToShowLeavesNoStrip;
var
  Strip: TJobStrip;
begin
  Strip := LayoutJobStrip(nil, 5, 80);
  Assert.AreEqual(0, Strip.ListWidth, 'no jobs');
  Strip := LayoutJobStrip([MakeJob(1, pjkCopy, pjpRunning, jpForeground),
    MakeJob(2, pjkCopy, pjpConfirm)], 5, 80);
  Assert.AreEqual(0, Strip.ListWidth, 'only jobs with their own dialog');
end;

procedure TTestDualPanelJobChips.HitFindsChipListAndGap;
var
  Strip: TJobStrip;
  Id: Integer;
begin
  Strip := LayoutJobStrip([MakeJob(7, pjkCopy, pjpRunning),
    MakeJob(9, pjkDelete, pjpError)], 0, 60);
  Assert.IsTrue(HitJobStrip(Strip, Strip.Chips[0].Left, Id) = jshChip, 'first chip');
  Assert.AreEqual(7, Id);
  Assert.IsTrue(HitJobStrip(Strip, Strip.Chips[1].Left + Strip.Chips[1].Width - 1, Id) = jshChip,
    'last cell of the second chip');
  Assert.AreEqual(9, Id, 'the click goes to the chip under it');
  Assert.IsTrue(HitJobStrip(Strip, Strip.ListLeft, Id) = jshList, 'list button');
  Assert.AreEqual(0, Id, 'no job for the list button');
  Assert.IsTrue(HitJobStrip(Strip, Strip.Chips[0].Left - 1, Id) = jshNone, 'left of the strip');
  Assert.IsTrue(HitJobStrip(Strip, Strip.Chips[0].Left + Strip.Chips[0].Width, Id) = jshNone,
    'gap between chips');
  Assert.IsTrue(HitJobStrip(Default(TJobStrip), 5, Id) = jshNone, 'empty strip');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelJobChips);

end.
