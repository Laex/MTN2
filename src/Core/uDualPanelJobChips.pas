unit uDualPanelJobChips;

{ Background-job indicator at the right end of the workspace tab bar: one chip
  per job (kind glyph plus progress or a state mark) and a button that opens
  the job list. Layout and hit-testing are pure; the window paints the result. }

interface

uses
  System.SysUtils, uDualPanelUiTypes;

type
  TJobChipTone = (jctNormal, jctAsk, jctError);

  TJobChip = record
    JobId: Integer;
    Left: Integer;
    Width: Integer;
    Caption: string;
    Tone: TJobChipTone;
  end;

  TJobStrip = record
    Chips: TArray<TJobChip>;
    ListLeft: Integer;
    /// <summary>0 when there is nothing to show or no room for it.</summary>
    ListWidth: Integer;
    ListCaption: string;
  end;

  TJobStripHit = (jshNone, jshChip, jshList);

/// <summary>True for a job that gets a chip: a queued or waiting one, or one
/// running or failed out of sight. A job with its own progress dialog does not.</summary>
function JobHasChip(const AJob: TPanelJobState): Boolean;
function JobChipTone(const AJob: TPanelJobState): TJobChipTone;
/// <summary>"[glyph 45%]", or "[glyph ..]" queued, "[glyph ?]" waiting for an
/// answer, "[glyph !]" failed.</summary>
function JobChipCaption(const AJob: TPanelJobState): string;
/// <summary>Chips right-aligned before the list button, which ends at the last
/// column of AWidth, in job order. Chips that do not fit are left out, those
/// waiting for an answer or failed last, and the button counts all of them.
/// Nothing is laid out left of AFirstCol.</summary>
function LayoutJobStrip(const AJobs: TArray<TPanelJobState>;
  AFirstCol, AWidth: Integer): TJobStrip;
function HitJobStrip(const AStrip: TJobStrip; ACol: Integer;
  out AJobId: Integer): TJobStripHit;

implementation

uses
  uDualPanelJobRules;

const
  cGlyphList = #$2261;

function JobHasChip(const AJob: TPanelJobState): Boolean;
begin
  case AJob.Phase of
    pjpQueued, pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk:
      Result := True;
    pjpRunning:
      // A job told to stop is only waiting for its worker to notice; it has
      // nothing to show or to open.
      Result := (AJob.Presentation = jpBackground) and
        not (Assigned(AJob.Cancel) and AJob.Cancel.IsCancellationRequested);
    pjpError:
      Result := AJob.Presentation = jpBackground;
  else
    Result := False;
  end;
end;

function JobChipTone(const AJob: TPanelJobState): TJobChipTone;
begin
  if AJob.Phase = pjpError then
    Result := jctError
  else if JobIsAskPhase(AJob.Phase) then
    Result := jctAsk
  else
    Result := jctNormal;
end;

function JobChipCaption(const AJob: TPanelJobState): string;
var
  Mark: string;
begin
  case AJob.Phase of
    pjpQueued: Mark := '..';
    pjpOverwriteAsk, pjpDeleteAsk, pjpIOErrorAsk: Mark := '?';
    pjpError: Mark := '!';
  else
    Mark := IntToStr(JobProgressPercent(AJob)) + '%';
  end;
  Result := '[' + JobKindGlyph(AJob.Kind, AJob.DeleteToRecycleBin) + ' ' + Mark + ']';
end;

function LayoutJobStrip(const AJobs: TArray<TPanelJobState>;
  AFirstCol, AWidth: Integer): TJobStrip;
var
  Shown: TArray<TPanelJobState>;
  Picked: TArray<Boolean>;
  Job: TPanelJobState;
  I, Pass, Used, Room, Count, X: Integer;
begin
  Result := Default(TJobStrip);
  Shown := nil;
  for Job in AJobs do
    if JobHasChip(Job) then
      Shown := Shown + [Job];
  Count := Length(Shown);
  if Count = 0 then
    Exit;
  Result.ListCaption := '[' + cGlyphList + IntToStr(Count) + ']';
  Result.ListLeft := AWidth - Length(Result.ListCaption);
  if Result.ListLeft < AFirstCol then
  begin
    Result.ListCaption := '';
    Exit;
  end;
  Result.ListWidth := Length(Result.ListCaption);

  // Jobs that need an answer or failed claim room first, then the others in
  // job order; each chip takes a spacer column. Chips are placed in job order.
  Room := Result.ListLeft - AFirstCol;
  SetLength(Picked, Length(Shown));
  Used := 0;
  Count := 0;
  for Pass := 0 to 1 do
    for I := 0 to High(Shown) do
      if not Picked[I] and ((JobChipTone(Shown[I]) <> jctNormal) = (Pass = 0)) and
         (Used + Length(JobChipCaption(Shown[I])) + 1 <= Room) then
      begin
        Picked[I] := True;
        Inc(Used, Length(JobChipCaption(Shown[I])) + 1);
        Inc(Count);
      end;
  SetLength(Result.Chips, Count);
  X := Result.ListLeft - Used;
  Count := 0;
  for I := 0 to High(Shown) do
    if Picked[I] then
    begin
      Result.Chips[Count].JobId := Shown[I].Id;
      Result.Chips[Count].Caption := JobChipCaption(Shown[I]);
      Result.Chips[Count].Tone := JobChipTone(Shown[I]);
      Result.Chips[Count].Left := X;
      Result.Chips[Count].Width := Length(Result.Chips[Count].Caption);
      Inc(X, Result.Chips[Count].Width + 1);
      Inc(Count);
    end;
end;

function HitJobStrip(const AStrip: TJobStrip; ACol: Integer;
  out AJobId: Integer): TJobStripHit;
var
  Chip: TJobChip;
begin
  AJobId := 0;
  Result := jshNone;
  if AStrip.ListWidth = 0 then
    Exit;
  if (ACol >= AStrip.ListLeft) and (ACol < AStrip.ListLeft + AStrip.ListWidth) then
    Exit(jshList);
  for Chip in AStrip.Chips do
    if (ACol >= Chip.Left) and (ACol < Chip.Left + Chip.Width) then
    begin
      AJobId := Chip.JobId;
      Exit(jshChip);
    end;
end;

end.
