unit uSharkPicture;

{$I sharks.inc}

{ The sharks swimming across a black screen, as a picture that draws into a
  grid of cells: the world, its renderer and the clock that steps them. It
  knows nothing of the program around it, so the screensaver library of the
  sharks and the tests use it the same way. }

interface

{$IFDEF MTN_ASCII_SHARKS}

uses
  uTerminalTypes, uSharkWorld, uSharkRender;

const
  /// <summary>Milliseconds between Advance calls.</summary>
  cSharkTickMs = 90;

type
  /// <summary>The world and its renderer of one running picture; Draw lays the
  /// world out on the first frame and follows the size of the window.</summary>
  TSharkPicture = class
  private
    FWorld: TSharkWorld;
    FRenderer: TSharkRenderer;
    FSeed: Cardinal;
    FAccumulator: Double;
    FCols, FRows: Integer;
    procedure Layout(ACols, ARows: Integer);
  public
    constructor Create(ASeed: Cardinal);
    destructor Destroy; override;
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    procedure Finish;
  end;

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.SysUtils, System.Math, uSharkShapes;

const
  cSimStep = 1 / 60;
  cMaxSteps = 8;

function SharkSpecsFor(ACols: Integer; ARandom: Cardinal): TArray<TSharkSpec>;
const
  cSizes: array[0..3] of Double = (1, 0.7, 0.84, 0.77);
var
  Count, I, K: Integer;
  Kinds: array[0..cSharkKindCount - 1] of Integer;
  State: Cardinal;
begin
  Count := EnsureRange(ACols div 30, 2, 4);
  for I := 0 to High(Kinds) do
    Kinds[I] := I;
  // A different set of kinds every time, drawn without repeats.
  State := ARandom;
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    State := State * 1664525 + 1013904223;
    K := I + Integer((State shr 8) mod Cardinal(Length(Kinds) - I));
    Result[I].Kind := TSharkKind(Kinds[K]);
    Kinds[K] := Kinds[I];
    Result[I].Size := cSizes[I mod Length(cSizes)];
  end;
end;

{ TSharkPicture }

constructor TSharkPicture.Create(ASeed: Cardinal);
begin
  inherited Create;
  FRenderer := TSharkRenderer.Create;
  FSeed := ASeed;
end;

destructor TSharkPicture.Destroy;
begin
  FreeAndNil(FWorld);
  FreeAndNil(FRenderer);
  inherited Destroy;
end;

procedure TSharkPicture.Prepare;
begin
  // The window size is not known yet: the first frame lays the world out.
  FreeAndNil(FWorld);
  FCols := 0;
  FRows := 0;
  FAccumulator := 0;
end;

procedure TSharkPicture.Finish;
begin
  FreeAndNil(FWorld);
end;

procedure TSharkPicture.Layout(ACols, ARows: Integer);
begin
  FCols := ACols;
  FRows := ARows;
  FreeAndNil(FWorld);
  FSeed := FSeed * 1664525 + 1013904223;
  FWorld := TSharkWorld.Create(SharkSpecsFor(ACols, FSeed), FSeed);
  FWorld.Resize(ACols * cSharkCellWidth, ARows * cSharkCellHeight, cSharkCellWidth,
    cSharkCellHeight);
  FRenderer.Resize(ACols, ARows);
  FAccumulator := 0;
end;

procedure TSharkPicture.Advance(ASeconds: Double);
var
  Steps: Integer;
begin
  if FWorld = nil then
    Exit;
  FAccumulator := FAccumulator + Min(0.25, ASeconds);
  Steps := 0;
  while (FAccumulator >= cSimStep) and (Steps < cMaxSteps) do
  begin
    FWorld.Step(cSimStep);
    FAccumulator := FAccumulator - cSimStep;
    Inc(Steps);
  end;
  if Steps = cMaxSteps then
    FAccumulator := 0;
  FRenderer.Render(FWorld, ASeconds);
end;

procedure TSharkPicture.Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
var
  I: Integer;
begin
  if (ACols < 1) or (ARows < 1) then
    Exit;
  if FWorld = nil then
  begin
    Layout(ACols, ARows);
    // Two seconds of swimming first, so the first frame is not the staging.
    for I := 1 to 120 do
      FWorld.Step(cSimStep);
    FRenderer.Render(FWorld, cSharkTickMs / 1000);
  end
  else if (ACols <> FCols) or (ARows <> FRows) then
  begin
    // The window was resized: the same fish and sharks swim on, the fish are
    // kept inside the new edges and the sharks turn back by themselves.
    FCols := ACols;
    FRows := ARows;
    FWorld.Resize(ACols * cSharkCellWidth, ARows * cSharkCellHeight, cSharkCellWidth,
      cSharkCellHeight);
    FRenderer.Resize(ACols, ARows);
    FRenderer.Render(FWorld, cSharkTickMs / 1000);
  end;
  FRenderer.Paint(AGrid, FWorld.Time);
end;

{$ENDIF}

end.
