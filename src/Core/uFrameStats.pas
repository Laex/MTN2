unit uFrameStats;

{ --fps: what one second of screen updates cost. MTN2 has no frame loop --
  the window is recomposed and repainted only when something changes (a key,
  console output, the cursor blink) -- so the count alone says little; the
  frame times say how much headroom there is. Three stages are timed:
    compose -- TMainForm.ComposeScene builds the character grid;
    render  -- TTerminalRenderer rasterizes the grid into its frame bitmap
               (Skia or GDI/FMX), usually the expensive one;
    paint   -- TMainForm.FormPaint puts that bitmap on the window canvas
               (GDI/FMX defers the actual blit past OnPaint, so ~0 there).
  The caption is refreshed once a second from a timer, never per frame:
  a caption change does not repaint the client area, so the reading does
  not feed back into what it measures. }

interface

uses
  System.SysUtils, System.Diagnostics;

type
  TFrameStage = (fsCompose, fsRender, fsPaint);

  TStageSummary = record
    Name: string;
    Count: Integer;
    AvgMs, MaxMs: Double;
    class function Make(const AName: string; ACount: Integer;
      AAvgMs, AMaxMs: Double): TStageSummary; static;
  end;

  TFrameStats = record
  private
    FCount: array[TFrameStage] of Integer;
    FTotalTicks: array[TFrameStage] of Int64;
    FMaxTicks: array[TFrameStage] of Int64;
    FWindowStart: Int64;
  public
    /// <summary>Starts a new measuring window now.</summary>
    procedure Reset;
    procedure Add(AStage: TFrameStage; AElapsedTicks: Int64);
    function Count(AStage: TFrameStage): Integer;
    function AvgMs(AStage: TFrameStage): Double;
    function MaxMs(AStage: TFrameStage): Double;
    /// <summary>Caption text for the window since Reset, then Reset.</summary>
    function TakeSummary: string;
  end;

/// <summary>"12 fps  compose 0.6/1.1  render 2.3/5.0  paint 0.4/0.7 ms":
/// frames painted per second, then average/maximum ms per stage; a stage
/// that did not run in the window is left out. Always '.' as the decimal
/// separator.</summary>
function FrameStatsText(AFrames: Integer; AElapsedSec: Double;
  const AStages: array of TStageSummary): string;

implementation

var
  GInvariant: TFormatSettings;

function TicksToMs(ATicks: Int64): Double;
begin
  Result := ATicks * 1000.0 / TStopwatch.Frequency;
end;

class function TStageSummary.Make(const AName: string; ACount: Integer;
  AAvgMs, AMaxMs: Double): TStageSummary;
begin
  Result.Name := AName;
  Result.Count := ACount;
  Result.AvgMs := AAvgMs;
  Result.MaxMs := AMaxMs;
end;

function FrameStatsText(AFrames: Integer; AElapsedSec: Double;
  const AStages: array of TStageSummary): string;
var
  Fps: Double;
  Any: Boolean;
  St: TStageSummary;
begin
  if AElapsedSec > 0 then
    Fps := AFrames / AElapsedSec
  else
    Fps := 0;
  Result := Format('%.0f fps', [Fps], GInvariant);
  Any := False;
  for St in AStages do
    if St.Count > 0 then
    begin
      Result := Result + Format('  %s %.1f/%.1f', [St.Name, St.AvgMs, St.MaxMs],
        GInvariant);
      Any := True;
    end;
  if Any then
    Result := Result + ' ms';
end;

{ TFrameStats }

procedure TFrameStats.Reset;
var
  S: TFrameStage;
begin
  for S := Low(TFrameStage) to High(TFrameStage) do
  begin
    FCount[S] := 0;
    FTotalTicks[S] := 0;
    FMaxTicks[S] := 0;
  end;
  FWindowStart := TStopwatch.GetTimeStamp;
end;

procedure TFrameStats.Add(AStage: TFrameStage; AElapsedTicks: Int64);
begin
  Inc(FCount[AStage]);
  Inc(FTotalTicks[AStage], AElapsedTicks);
  if AElapsedTicks > FMaxTicks[AStage] then
    FMaxTicks[AStage] := AElapsedTicks;
end;

function TFrameStats.Count(AStage: TFrameStage): Integer;
begin
  Result := FCount[AStage];
end;

function TFrameStats.AvgMs(AStage: TFrameStage): Double;
begin
  if FCount[AStage] = 0 then
    Exit(0);
  Result := TicksToMs(FTotalTicks[AStage]) / FCount[AStage];
end;

function TFrameStats.MaxMs(AStage: TFrameStage): Double;
begin
  Result := TicksToMs(FMaxTicks[AStage]);
end;

function TFrameStats.TakeSummary: string;
var
  Elapsed: Double;
begin
  Elapsed := TicksToMs(TStopwatch.GetTimeStamp - FWindowStart) / 1000.0;
  Result := FrameStatsText(Count(fsPaint), Elapsed, [
    TStageSummary.Make('compose', Count(fsCompose), AvgMs(fsCompose), MaxMs(fsCompose)),
    TStageSummary.Make('render', Count(fsRender), AvgMs(fsRender), MaxMs(fsRender)),
    TStageSummary.Make('paint', Count(fsPaint), AvgMs(fsPaint), MaxMs(fsPaint))]);
  Reset;
end;

initialization
  GInvariant := TFormatSettings.Invariant;

end.
