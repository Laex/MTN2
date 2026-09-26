program TestFrameStats;

{$APPTYPE CONSOLE}

{ uFrameStats (--fps): per-stage counts and times, the caption text. }

uses
  System.SysUtils, System.Diagnostics,
  uFrameStats;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create('FAIL: ' + AMsg);
  Writeln('  OK  ', AMsg);
end;

function MsToTicks(AMs: Double): Int64;
begin
  Result := Round(AMs * TStopwatch.Frequency / 1000.0);
end;

procedure TestText;
begin
  Writeln('FrameStatsText');
  Expect(FrameStatsText(12, 1.0, [
    TStageSummary.Make('compose', 3, 0.6, 1.1),
    TStageSummary.Make('render', 3, 2.34, 5),
    TStageSummary.Make('paint', 12, 0.4, 0.7)]) =
    '12 fps  compose 0.6/1.1  render 2.3/5.0  paint 0.4/0.7 ms',
    'all stages in pipeline order, one decimal, one unit');
  Expect(FrameStatsText(3, 1.5, [
    TStageSummary.Make('compose', 0, 0, 0),
    TStageSummary.Make('paint', 3, 2, 3)]) = '2 fps  paint 2.0/3.0 ms',
    'fps over the real window length; idle stage left out');
  Expect(FrameStatsText(0, 1.0, [TStageSummary.Make('paint', 0, 0, 0)]) = '0 fps',
    'nothing painted: no unit either');
  Expect(FrameStatsText(5, 0, [TStageSummary.Make('paint', 5, 1, 1)]) =
    '0 fps  paint 1.0/1.0 ms', 'zero window -> no division by zero');
end;

procedure TestStats;
var
  S: TFrameStats;
begin
  Writeln('TFrameStats');
  S.Reset;
  Expect((S.Count(fsPaint) = 0) and (S.AvgMs(fsPaint) = 0), 'empty after Reset');
  S.Add(fsPaint, MsToTicks(2));
  S.Add(fsPaint, MsToTicks(6));
  S.Add(fsCompose, MsToTicks(1));
  S.Add(fsRender, MsToTicks(3));
  Expect(S.Count(fsPaint) = 2, 'paint count');
  Expect(Abs(S.AvgMs(fsPaint) - 4) < 0.01, 'paint average');
  Expect(Abs(S.MaxMs(fsPaint) - 6) < 0.01, 'paint maximum');
  Expect(S.Count(fsCompose) = 1, 'compose counted separately');
  Expect(Pos('compose 1.0/1.0  render 3.0/3.0  paint 4.0/6.0 ms', S.TakeSummary) > 0,
    'summary carries every stage');
  Expect((S.Count(fsPaint) = 0) and (S.Count(fsCompose) = 0) and
    (S.Count(fsRender) = 0), 'TakeSummary resets');
end;

begin
  try
    TestText;
    TestStats;
    Writeln('All FrameStats tests PASSED');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      ExitCode := 1;
    end;
  end;
end.
