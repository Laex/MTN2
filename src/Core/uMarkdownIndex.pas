unit uMarkdownIndex;

{ Stage 25: lazy fence-state recovery for the Markdown Viewer.

  TMdFenceState (uMarkdownParser) is the only state ParseLine needs carried
  from the start of the document — but the Viewer only ever wants to paint
  the current viewport (a few dozen lines), not the whole file, so it can't
  just replay every line from 0 on every repaint. TMarkdownFenceIndex makes
  "what's the fence state right before line N" cheap by remembering where it
  last left off (FLastLine/FLastState — the common case: sequential
  scrolling never rescans anything) and a sparse list of checkpoints spaced
  cCheckpointStride lines apart recorded along the way, so a later jump
  (Goto, PageDown in bursts, Ctrl+End) only rescans from the nearest
  checkpoint at or before the target instead of from the top of the file.

  Checkpoints, once recorded, stay valid forever: this is a read-only
  Viewer, so line content never changes under the index. Re-scanning always
  goes through TMarkdownParser.ParseLine itself (discarding the TMdLine it
  returns, keeping only the mutated TMdFenceState) so fence-toggle detection
  can never drift from what the Viewer's own per-line parse will compute. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uEditorDoc, uMarkdownParser;

type
  TMarkdownFenceIndex = class
  private
    const
      cCheckpointStride = 500;
    type
      TCheckpoint = record
        Line: Integer;
        State: TMdFenceState;
      end;
    var
      FCheckpoints: TList<TCheckpoint>;
      FLastLine: Integer; // -1 = nothing scanned yet
      FLastState: TMdFenceState;
    function FindCheckpointAtOrBefore(ALineIdx: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Drop all cached state — call when the document is
    /// (re)opened, since a different file's fence layout invalidates
    /// everything remembered so far.</summary>
    procedure Reset;
    /// <summary>Fence state immediately before line ALineIdx (0-based), i.e.
    /// the state ParseLine should be called with to parse that line.</summary>
    function FenceStateBefore(ADoc: TEditorDoc; ALineIdx: Integer): TMdFenceState;
  end;

implementation

constructor TMarkdownFenceIndex.Create;
begin
  inherited Create;
  FCheckpoints := TList<TCheckpoint>.Create;
  FLastLine := -1;
end;

destructor TMarkdownFenceIndex.Destroy;
begin
  FreeAndNil(FCheckpoints);
  inherited Destroy;
end;

procedure TMarkdownFenceIndex.Reset;
begin
  FCheckpoints.Clear;
  FLastLine := -1;
end;

// Checkpoints are always appended in strictly increasing Line order (each
// scan only ever moves forward), so the list stays sorted — binary search
// for the last entry with Line <= ALineIdx.
function TMarkdownFenceIndex.FindCheckpointAtOrBefore(ALineIdx: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Result := -1;
  Lo := 0;
  Hi := FCheckpoints.Count - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if FCheckpoints[Mid].Line <= ALineIdx then
    begin
      Result := Mid;
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
end;

function TMarkdownFenceIndex.FenceStateBefore(ADoc: TEditorDoc; ALineIdx: Integer): TMdFenceState;
var
  StartLine: Integer;
  State: TMdFenceState;
  CpIdx: Integer;
  Cp: TCheckpoint;
begin
  State.InFence := False;
  if ALineIdx <= 0 then
    Exit(State);

  if (FLastLine >= 0) and (ALineIdx = FLastLine) then
    Exit(FLastState);

  StartLine := 0;
  if (FLastLine >= 0) and (FLastLine <= ALineIdx) then
  begin
    StartLine := FLastLine;
    State := FLastState;
  end;

  CpIdx := FindCheckpointAtOrBefore(ALineIdx);
  if CpIdx >= 0 then
  begin
    Cp := FCheckpoints[CpIdx];
    if Cp.Line > StartLine then
    begin
      StartLine := Cp.Line;
      State := Cp.State;
    end;
  end;

  while StartLine < ALineIdx do
  begin
    TMarkdownParser.ParseLine(ADoc.GetLine(StartLine), State);
    Inc(StartLine);
    if (StartLine mod cCheckpointStride = 0) and
       ((FCheckpoints.Count = 0) or (FCheckpoints.Last.Line < StartLine)) then
    begin
      Cp.Line := StartLine;
      Cp.State := State;
      FCheckpoints.Add(Cp);
    end;
  end;

  FLastLine := ALineIdx;
  FLastState := State;
  Result := State;
end;

end.
