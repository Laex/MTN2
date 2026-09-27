unit TestFrameStats;

{ uFrameStats (--fps): per-stage counts and times, the caption text. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFrameStats = class
  public
    [Test] procedure TestText;
    [Test] procedure TestStats;
  end;

implementation

uses
  System.SysUtils, System.Diagnostics,
  uFrameStats;

function MsToTicks(AMs: Double): Int64;
begin
  Result := Round(AMs * TStopwatch.Frequency / 1000.0);
end;

procedure TestText;
begin
  Assert.IsTrue(FrameStatsText(12, 1.0, [
    TStageSummary.Make('compose', 3, 0.6, 1.1),
    TStageSummary.Make('render', 3, 2.34, 5),
    TStageSummary.Make('paint', 12, 0.4, 0.7)]) =
    '12 fps  compose 0.6/1.1  render 2.3/5.0  paint 0.4/0.7 ms',
    'all stages in pipeline order, one decimal, one unit');
  Assert.IsTrue(FrameStatsText(3, 1.5, [
    TStageSummary.Make('compose', 0, 0, 0),
    TStageSummary.Make('paint', 3, 2, 3)]) = '2 fps  paint 2.0/3.0 ms',
    'fps over the real window length; idle stage left out');
  Assert.IsTrue(FrameStatsText(0, 1.0, [TStageSummary.Make('paint', 0, 0, 0)]) = '0 fps',
    'nothing painted: no unit either');
  Assert.IsTrue(FrameStatsText(5, 0, [TStageSummary.Make('paint', 5, 1, 1)]) =
    '0 fps  paint 1.0/1.0 ms', 'zero window -> no division by zero');
end;

procedure TestStats;
var
  S: TFrameStats;
begin
  S.Reset;
  Assert.IsTrue((S.Count(fsPaint) = 0) and (S.AvgMs(fsPaint) = 0), 'empty after Reset');
  S.Add(fsPaint, MsToTicks(2));
  S.Add(fsPaint, MsToTicks(6));
  S.Add(fsCompose, MsToTicks(1));
  S.Add(fsRender, MsToTicks(3));
  Assert.IsTrue(S.Count(fsPaint) = 2, 'paint count');
  Assert.IsTrue(Abs(S.AvgMs(fsPaint) - 4) < 0.01, 'paint average');
  Assert.IsTrue(Abs(S.MaxMs(fsPaint) - 6) < 0.01, 'paint maximum');
  Assert.IsTrue(S.Count(fsCompose) = 1, 'compose counted separately');
  Assert.IsTrue(Pos('compose 1.0/1.0  render 3.0/3.0  paint 4.0/6.0 ms', S.TakeSummary) > 0,
    'summary carries every stage');
  Assert.IsTrue((S.Count(fsPaint) = 0) and (S.Count(fsCompose) = 0) and
    (S.Count(fsRender) = 0), 'TakeSummary resets');
end;

{ TTestFrameStats }

procedure TTestFrameStats.TestText;
begin
  TestFrameStats.TestText;
end;

procedure TTestFrameStats.TestStats;
begin
  TestFrameStats.TestStats;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameStats);

end.
