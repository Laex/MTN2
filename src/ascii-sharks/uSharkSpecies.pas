unit uSharkSpecies;

{$I sharks.inc}

{ The kinds of small fish that swim in schools. Different mixes of the
  behaviour weights give different shapes of a school: strong alignment gives
  polarised schools and ribbons, low alignment gives swarms, a tangential pull
  gives a rotating bait ball. }

interface

{$IFDEF MTN_ASCII_SHARKS}

uses
  uSharkMath;

type
  TFishSpecies = record
    Name: string;
    Cruise, MaxSpeed, MinSpeed: Double;
    /// <summary>Relative odds of a new school being this species.</summary>
    Weight: Double;
    SchoolMin, SchoolMax: Integer;
    /// <summary>Personal space in grid cells (x, y), so every fish gets its own glyph.</summary>
    SpacingX, SpacingY: Double;
    Align, Cohesion, Jitter: Double;
    /// <summary>Tangential pull around the local centre: above 0 makes a rotating bait ball.</summary>
    Mill: Double;
    /// <summary>Damps vertical speed; real fish mostly cruise level.</summary>
    VerticalDrag: Double;
  end;

const
  cSpeciesCount = 5;

function FishSpecies(AIndex: Integer): TFishSpecies;
function PickFishSpecies(ARandom: TSharkRandom): Integer;

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

function Make(const AName: string; ACruise, AMax, AMin, AWeight: Double;
  ASchoolMin, ASchoolMax: Integer; ASpaceX, ASpaceY, AAlign, ACohesion, AJitter,
  AMill, ADrag: Double): TFishSpecies;
begin
  Result.Name := AName;
  Result.Cruise := ACruise;
  Result.MaxSpeed := AMax;
  Result.MinSpeed := AMin;
  Result.Weight := AWeight;
  Result.SchoolMin := ASchoolMin;
  Result.SchoolMax := ASchoolMax;
  Result.SpacingX := ASpaceX;
  Result.SpacingY := ASpaceY;
  Result.Align := AAlign;
  Result.Cohesion := ACohesion;
  Result.Jitter := AJitter;
  Result.Mill := AMill;
  Result.VerticalDrag := ADrag;
end;

function FishSpecies(AIndex: Integer): TFishSpecies;
begin
  case AIndex of
    0: Result := Make('sardine', 36, 64, 18, 3, 18, 28, 1.8, 1.1, 1.6, 1.6, 40, 70, 0.5);
    1: Result := Make('anchovy', 46, 78, 22, 3, 20, 32, 1.5, 1, 3.2, 0.45, 30, 0, 1.4);
    2: Result := Make('silverside', 40, 70, 20, 3, 12, 20, 2, 1.1, 2.4, 1.1, 35, 0, 1.6);
    3: Result := Make('mackerel', 32, 60, 16, 2, 5, 9, 2.6, 1.3, 2, 0.9, 25, 0, 2);
  else
    Result := Make('goby', 26, 56, 10, 1, 8, 12, 1.4, 1.1, 0.35, 1.4, 110, 0, 0.3);
  end;
end;

function PickFishSpecies(ARandom: TSharkRandom): Integer;
var
  Total, R: Double;
  I: Integer;
begin
  Total := 0;
  for I := 0 to cSpeciesCount - 1 do
    Total := Total + FishSpecies(I).Weight;
  R := ARandom.Next * Total;
  for I := 0 to cSpeciesCount - 1 do
  begin
    R := R - FishSpecies(I).Weight;
    if R <= 0 then
      Exit(I);
  end;
  Result := 0;
end;

{$ENDIF}

end.
