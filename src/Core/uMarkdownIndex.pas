unit uMarkdownIndex;

{ Lazy fence-state recovery for the Markdown Viewer.

  TMdFenceState (uMarkdownParser) is the only state ParseLine needs carried
  from the start of the document - but the Viewer wants only the lines it
  shows, in any order. TMarkdownFenceIndex keeps the state before every line
  scanned so far, one byte per line, and scans on from the last one when asked
  further down. A lookup above that point costs nothing: a table row reads the
  rows around it, so going back must not rescan the document.

  The states stay valid: this is a read-only Viewer, so line content never
  changes under the index. Scanning goes through TMarkdownParser.ParseLine
  itself (discarding the TMdLine it returns, keeping only the mutated
  TMdFenceState) so fence-toggle detection matches the Viewer's own parse. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  uEditorDoc, uMarkdownParser;

type
  TMarkdownFenceIndex = class
  private
    // FStates[N] is the state before line N.
    FStates: TList<Byte>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Drop all cached state - call when the document is
    /// (re)opened, since a different file's fence layout invalidates
    /// everything remembered so far.</summary>
    procedure Reset;
    /// <summary>Fence state immediately before line ALineIdx (0-based), i.e.
    /// the state ParseLine should be called with to parse that line.</summary>
    function FenceStateBefore(ADoc: TEditorDoc; ALineIdx: Integer): TMdFenceState;
  end;

implementation

const
  cInFence = 1;
  cInMath = 2;

constructor TMarkdownFenceIndex.Create;
begin
  inherited Create;
  FStates := TList<Byte>.Create;
end;

destructor TMarkdownFenceIndex.Destroy;
begin
  FreeAndNil(FStates);
  inherited Destroy;
end;

procedure TMarkdownFenceIndex.Reset;
begin
  FStates.Clear;
end;

function TMarkdownFenceIndex.FenceStateBefore(ADoc: TEditorDoc; ALineIdx: Integer): TMdFenceState;
var
  State: TMdFenceState;
  Bits: Byte;
begin
  Result := Default(TMdFenceState);
  if ALineIdx <= 0 then
    Exit;
  if FStates.Count = 0 then
    FStates.Add(0);
  if ALineIdx >= FStates.Count then
  begin
    Bits := FStates.Last;
    State := Default(TMdFenceState);
    State.InFence := Bits and cInFence <> 0;
    State.InMath := Bits and cInMath <> 0;
    while FStates.Count <= ALineIdx do
    begin
      TMarkdownParser.ParseLine(ADoc.GetLine(FStates.Count - 1), State);
      Bits := 0;
      if State.InFence then
        Bits := Bits or cInFence;
      if State.InMath then
        Bits := Bits or cInMath;
      FStates.Add(Bits);
    end;
  end;
  Bits := FStates[ALineIdx];
  Result.InFence := Bits and cInFence <> 0;
  Result.InMath := Bits and cInMath <> 0;
end;

end.
