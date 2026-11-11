unit uSharkSaver;

{$I sharks.inc}

{ Screensaver picture: sharks swimming across a black screen. It registers
  itself with the screensaver registry (uScreenSaver) under the id 'sharks'.

  This is the only unit of the subsystem (folder ascii-sharks) the rest of the
  program uses. Without MTN_ASCII_SHARKS (see sharks.inc) nothing is
  registered, so no other unit needs to know whether the subsystem is built. }

interface

const
  /// <summary>The sharks are part of this build.</summary>
{$IFDEF MTN_ASCII_SHARKS}
  SharksBuiltIn = True;
{$ELSE}
  SharksBuiltIn = False;
{$ENDIF}
  cSharkTickMs = 90;
  cSharkSaverId = 'sharks';

implementation

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.SysUtils, System.Math, uTerminalTypes, uScreenSaver, uPlatformInfo, uSharkShapes,
  uSharkWorld, uSharkRender;

const
  cSimStep = 1 / 60;
  cMaxSteps = 8;

type
  /// <summary>The world and its renderer of one running saver.</summary>
  TSharkEffect = class(TInterfacedObject, ISaverEffect)
  private
    FWorld: TSharkWorld;
    FRenderer: TSharkRenderer;
    FSeed: Cardinal;
    FAccumulator: Double;
    FCols, FRows: Integer;
    procedure Layout(ACols, ARows: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function TickMs: Integer;
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    procedure Finish;
  end;

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

{ TSharkEffect }

constructor TSharkEffect.Create;
begin
  inherited Create;
  FRenderer := TSharkRenderer.Create;
  FSeed := Cardinal(PlatformTickCount64);
end;

destructor TSharkEffect.Destroy;
begin
  FreeAndNil(FWorld);
  FreeAndNil(FRenderer);
  inherited Destroy;
end;

function TSharkEffect.TickMs: Integer;
begin
  Result := cSharkTickMs;
end;

procedure TSharkEffect.Prepare;
begin
  // The window size is not known yet: the first frame lays the world out.
  FreeAndNil(FWorld);
  FCols := 0;
  FRows := 0;
  FAccumulator := 0;
end;

procedure TSharkEffect.Finish;
begin
  FreeAndNil(FWorld);
end;

procedure TSharkEffect.Layout(ACols, ARows: Integer);
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

procedure TSharkEffect.Advance(ASeconds: Double);
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

procedure TSharkEffect.Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
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

initialization
  RegisterSaver(cSharkSaverId, 'Sharks', '',
    function: ISaverEffect
    begin
      Result := TSharkEffect.Create;
    end);

{$ENDIF}

end.
