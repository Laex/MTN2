unit uEditorScan;

{ A long pass over a document (search, replace) run in portions on the main
  thread: the first one inside Start, so a short pass is over before Start
  returns, the rest on a timer, between which the window paints and takes
  input. The document and its line cache are used by one thread only. }

interface

uses
  System.SysUtils, System.Classes, uCoreTimer;

type
  TEditorScanJob = record
    /// <summary>What is looked for, for the progress window.</summary>
    Subject: string;
    /// <summary>The pass replaces what it finds.</summary>
    Replacing: Boolean;
    /// <summary>Does one unit of work (a line, a block of bytes); True when
    /// the pass is over.</summary>
    Step: TFunc<Boolean>;
    /// <summary>0..100.</summary>
    Percent: TFunc<Integer>;
    /// <summary>What to show beside the percentage; may be nil.</summary>
    Note: TFunc<string>;
    /// <summary>Called once the pass is over.</summary>
    Finish: TProc;
    /// <summary>Called when the user stops the pass; may be nil.</summary>
    Cancel: TProc;
  end;

  TEditorScan = class
  private
    FJob: TEditorScanJob;
    FActive: Boolean;
    // Tells a pass from the one that replaced it from inside its own step.
    FSerial: Cardinal;
    FTimer: TCoreTimer;
    FOnProgress: TProc;
    procedure Tick(Sender: TObject);
    procedure Run(ABudgetMs: Cardinal);
  public
    /// <summary>AOnProgress is called after a portion that left work to do and
    /// whenever a pass ends or is dropped (Active is False then).</summary>
    constructor Create(const AOnProgress: TProc);
    destructor Destroy; override;
    /// <summary>Drops the pass in progress and starts AJob.</summary>
    procedure Start(const AJob: TEditorScanJob);
    /// <summary>Stops the pass and calls its Cancel.</summary>
    procedure Cancel;
    /// <summary>Drops the pass without calling its Finish or Cancel.</summary>
    procedure Abort;
    property Active: Boolean read FActive;
    function Percent: Integer;
    function Note: string;
    function Subject: string;
    function Replacing: Boolean;
  end;

var
  /// <summary>How long Start works before it leaves the rest to the timer; a
  /// pass that takes longer shows its progress.</summary>
  GEditorScanFirstMs: Cardinal = 250;
  /// <summary>How long one portion on the timer takes.</summary>
  GEditorScanSliceMs: Cardinal = 40;

implementation

constructor TEditorScan.Create(const AOnProgress: TProc);
begin
  inherited Create;
  FOnProgress := AOnProgress;
  FTimer := TCoreTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 1;
  FTimer.OnTimer := Tick;
end;

destructor TEditorScan.Destroy;
begin
  // The owner is going away: nothing is reported to it.
  FOnProgress := nil;
  Abort;
  FreeAndNil(FTimer);
  inherited Destroy;
end;

procedure TEditorScan.Start(const AJob: TEditorScanJob);
begin
  Abort;
  FJob := AJob;
  FActive := True;
  Run(GEditorScanFirstMs);
end;

procedure TEditorScan.Run(ABudgetMs: Cardinal);
var
  Serial: Cardinal;
  Started: UInt64;
  Done: Boolean;
  Step: TFunc<Boolean>;
  Finish: TProc;
begin
  Serial := FSerial;
  Step := FJob.Step;
  Started := TThread.GetTickCount64;
  try
    repeat
      Done := Step();
      if Serial <> FSerial then
        Exit;
    until Done or (TThread.GetTickCount64 - Started >= ABudgetMs);
  except
    Abort;
    raise;
  end;
  if Done then
  begin
    Finish := FJob.Finish;
    Abort;
    Finish();
    Exit;
  end;
  FTimer.Enabled := True;
  if Assigned(FOnProgress) then
    FOnProgress();
end;

procedure TEditorScan.Tick(Sender: TObject);
begin
  if FActive then
    Run(GEditorScanSliceMs)
  else
    FTimer.Enabled := False;
end;

procedure TEditorScan.Cancel;
var
  OnCancel: TProc;
begin
  if not FActive then
    Exit;
  OnCancel := FJob.Cancel;
  Abort;
  if Assigned(OnCancel) then
    OnCancel();
  if Assigned(FOnProgress) then
    FOnProgress();
end;

procedure TEditorScan.Abort;
var
  WasActive: Boolean;
begin
  WasActive := FActive;
  Inc(FSerial);
  FActive := False;
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  FJob := Default(TEditorScanJob);
  if WasActive and Assigned(FOnProgress) then
    FOnProgress();
end;

function TEditorScan.Percent: Integer;
begin
  Result := 0;
  if FActive and Assigned(FJob.Percent) then
    Result := FJob.Percent();
end;

function TEditorScan.Note: string;
begin
  Result := '';
  if FActive and Assigned(FJob.Note) then
    Result := FJob.Note();
end;

function TEditorScan.Subject: string;
begin
  Result := FJob.Subject;
end;

function TEditorScan.Replacing: Boolean;
begin
  Result := FJob.Replacing;
end;

end.
