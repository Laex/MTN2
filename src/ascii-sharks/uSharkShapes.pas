unit uSharkShapes;

{$I sharks.inc}

{ Outline and fin layout of each kind of shark. All distances are fractions of
  the shark's length; S runs from 0 at the snout to 1 at the tail. }

interface

{$IFDEF MTN_ASCII_SHARKS}

type
  TSharkKind = (skClassic, skHammerhead, skTiger, skZebra, skGreatHammer, skMako,
    skThresher, skNurse);

  TSharkShape = record
    /// <summary>Pectoral fin: leading root, trailing root, tip position along the body, reach.</summary>
    Pectoral: array[0..3] of Double;
    /// <summary>Notched trailing edge on the pectorals.</summary>
    Falcate: Boolean;
    /// <summary>Pelvic fins: leading root, trailing root, tip, reach.</summary>
    Pelvic: array[0..3] of Double;
    /// <summary>Reach of the forked tail fin; 0 when the tail is a ribbon.</summary>
    Caudal: Double;
    Dorsal: array[0..1] of Double;
    SecondDorsal: array[0..1] of Double;
    /// <summary>Hammerhead's wing across the snout: half span, how far its tips
    /// sweep back, its depth, the notch in the middle of its front edge.</summary>
    HasHead: Boolean;
    HeadSpan, HeadSweep, HeadDepth, HeadNotch: Double;
    /// <summary>Where the eye sits along the body; HasEye is False for hammerheads.</summary>
    HasEye: Boolean;
    Eye: array[0..1] of Double;
    Gills: array[0..1] of Double;
    /// <summary>Skin colour multipliers (r, g, b).</summary>
    Tint: array[0..2] of Double;
  end;

const
  cSharkKindCount = 8;

function SharkShapeOf(AKind: TSharkKind): TSharkShape;
/// <summary>Half the width of the body at S, as a fraction of its length.</summary>
function SharkHalfWidth(AKind: TSharkKind; S: Double): Double;

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

uses
  System.Math, uSharkMath;

function ClassicHalfWidth(S: Double): Double;
var
  K: Double;
begin
  if S < 0.13 then
    Exit(0.09 * Power(Sin((S / 0.13) * Pi / 2), 0.95));
  if S < 0.3 then
    Exit(0.09 + 0.016 * SmoothStep(0.13, 0.3, S));
  if S < 0.84 then
    Exit(0.019 + 0.087 * Power(1 - (S - 0.3) / 0.54, 1.25));
  K := (S - 0.84) / 0.16;
  Result := 0.019 * (1 - K) + 0.012 * Sin(K * Pi);
end;

function SharkHalfWidth(AKind: TSharkKind; S: Double): Double;
var
  K: Double;
begin
  case AKind of
    skHammerhead:
      begin
        if S < 0.06 then
          Exit(0.045);
        if S < 0.3 then
          Exit(0.045 + 0.061 * SmoothStep(0.06, 0.3, S));
        Result := ClassicHalfWidth(S) * 0.92;
      end;
    skTiger:
      begin
        if S < 0.13 then
          Exit(0.1 * Power(Sin((S / 0.13) * Pi / 2), 0.45));
        if S < 0.3 then
          Exit(0.1 + 0.014 * SmoothStep(0.13, 0.3, S));
        if S < 0.84 then
          Exit(0.019 + 0.095 * Power(1 - (S - 0.3) / 0.54, 1.2));
        K := (S - 0.84) / 0.16;
        Result := 0.019 * (1 - K) + 0.012 * Sin(K * Pi);
      end;
    skZebra:
      begin
        if S < 0.1 then
          Exit(0.075 * Power(Sin((S / 0.1) * Pi / 2), 0.7));
        if S < 0.28 then
          Exit(0.075 + 0.025 * SmoothStep(0.1, 0.28, S));
        if S < 0.55 then
          Exit(0.022 + 0.078 * Power(1 - (S - 0.28) / 0.27, 1.1));
        K := (S - 0.55) / 0.45;
        Result := 0.022 * (1 - K * K) + 0.012 * Sin(K * Pi);
      end;
    skGreatHammer:
      begin
        if S < 0.05 then
          Exit(0.04);
        if S < 0.3 then
          Exit(0.04 + 0.07 * SmoothStep(0.05, 0.3, S));
        Result := ClassicHalfWidth(S) * 0.95;
      end;
    skMako:
      begin
        if S < 0.17 then
          Exit(0.088 * Power(Sin((S / 0.17) * Pi / 2), 1.5));
        if S < 0.32 then
          Exit(0.088 + 0.012 * SmoothStep(0.17, 0.32, S));
        if S < 0.86 then
          Exit(0.014 + 0.086 * Power(1 - (S - 0.32) / 0.54, 1.45));
        K := (S - 0.86) / 0.14;
        Result := 0.014 * (1 - K) + 0.01 * Sin(K * Pi);
      end;
    skThresher:
      begin
        if S < 0.08 then
          Exit(0.07 * Power(Sin((S / 0.08) * Pi / 2), 0.75));
        if S < 0.2 then
          Exit(0.07 + 0.02 * SmoothStep(0.08, 0.2, S));
        if S < 0.48 then
          Exit(0.012 + 0.078 * Power(1 - (S - 0.2) / 0.28, 1.3));
        // The whip: thin, with a slight sickle swell before it tapers out.
        K := (S - 0.48) / 0.52;
        Result := 0.012 * (1 - K) + 0.006 * Sin(K * Pi * 0.9) + 0.002;
      end;
    skNurse:
      begin
        if S < 0.08 then
          Exit(0.085 * Power(Sin((S / 0.08) * Pi / 2), 0.4));
        if S < 0.3 then
          Exit(0.085 + 0.02 * SmoothStep(0.08, 0.3, S));
        if S < 0.72 then
          Exit(0.022 + 0.083 * Power(1 - (S - 0.3) / 0.42, 1.1));
        K := (S - 0.72) / 0.28;
        Result := 0.022 * (1 - K * K) + 0.014 * Sin(K * Pi);
      end;
  else
    Result := ClassicHalfWidth(S);
  end;
end;

procedure SetArr4(var A: array of Double; V0, V1, V2, V3: Double);
begin
  A[0] := V0;
  A[1] := V1;
  A[2] := V2;
  A[3] := V3;
end;

function Shape(const APec, APel: array of Double; AFalcate: Boolean; ACaudal,
  ADorsal0, ADorsal1, ASecond0, ASecond1: Double; AHasEye: Boolean; AEye0, AEye1,
  AGill0, AGill1, ATintR, ATintG, ATintB: Double): TSharkShape;
begin
  Result := Default(TSharkShape);
  SetArr4(Result.Pectoral, APec[0], APec[1], APec[2], APec[3]);
  Result.Falcate := AFalcate;
  SetArr4(Result.Pelvic, APel[0], APel[1], APel[2], APel[3]);
  Result.Caudal := ACaudal;
  Result.Dorsal[0] := ADorsal0;
  Result.Dorsal[1] := ADorsal1;
  Result.SecondDorsal[0] := ASecond0;
  Result.SecondDorsal[1] := ASecond1;
  Result.HasEye := AHasEye;
  Result.Eye[0] := AEye0;
  Result.Eye[1] := AEye1;
  Result.Gills[0] := AGill0;
  Result.Gills[1] := AGill1;
  Result.Tint[0] := ATintR;
  Result.Tint[1] := ATintG;
  Result.Tint[2] := ATintB;
end;

function SharkShapeOf(AKind: TSharkKind): TSharkShape;
begin
  case AKind of
    skHammerhead:
      begin
        // Slim neck under a wide, swept-back wing, tall first dorsal, long
        // upper tail lobe. Bronze-olive grey.
        Result := Shape([0.17, 0.4, 0.5, 0.22], [0.56, 0.63, 0.67, 0.075], True, 0.11,
          0.28, 0.44, 0.7, 0.74, False, 0, 0, 0.16, 0.26, 0.96, 0.98, 0.9);
        Result.HasHead := True;
        Result.HeadSpan := 0.17;
        Result.HeadSweep := 0.035;
        Result.HeadDepth := 0.09;
        Result.HeadNotch := 0;
      end;
    skTiger:
      // Blunt, square snout on a heavy body; barred back. Warm grey-brown.
      Result := Shape([0.15, 0.42, 0.53, 0.25], [0.57, 0.65, 0.69, 0.085], True, 0.095,
        0.33, 0.46, 0.71, 0.75, True, 0.08, 0.12, 0.19, 0.28, 1.02, 0.95, 0.84);
    skZebra:
      // Short rounded head, body done by half-length, then a long ribbon of a
      // tail fin. Broad rounded pectorals, spotted sandy skin.
      Result := Shape([0.12, 0.3, 0.36, 0.19], [0.42, 0.48, 0.51, 0.065], False, 0,
        0.36, 0.44, 0.49, 0.53, True, 0.06, 0.09, 0.13, 0.2, 1.08, 0.97, 0.74);
    skGreatHammer:
      begin
        // A broader, nearly straight-edged wing with a notch at the centre, a
        // towering first dorsal and a cooler slate skin.
        Result := Shape([0.16, 0.38, 0.49, 0.24], [0.55, 0.62, 0.67, 0.085], True, 0.13,
          0.24, 0.45, 0.68, 0.74, False, 0, 0, 0.15, 0.25, 0.86, 0.93, 1.02);
        Result.HasHead := True;
        Result.HeadSpan := 0.21;
        Result.HeadSweep := 0.006;
        Result.HeadDepth := 0.085;
        Result.HeadNotch := 0.014;
      end;
    skMako:
      // A long conical snout, a torpedo body that narrows hard to the tail
      // stalk, a tall crescent tail. Metallic indigo back.
      Result := Shape([0.18, 0.4, 0.5, 0.21], [0.58, 0.64, 0.68, 0.06], True, 0.13,
        0.34, 0.45, 0.76, 0.79, True, 0.11, 0.15, 0.2, 0.3, 0.78, 0.9, 1.2);
    skThresher:
      // A compact body over the front half, then the upper tail lobe as a long
      // whip as long as the shark itself. Bronze-violet skin.
      Result := Shape([0.12, 0.27, 0.36, 0.2], [0.37, 0.41, 0.44, 0.045], True, 0,
        0.24, 0.32, 0.45, 0.47, True, 0.05, 0.1, 0.11, 0.18, 1, 0.9, 1.08);
    skNurse:
      // A blunt, broad head, a heavy flattened body with both dorsals set far
      // back, rounded paddle pectorals, a long low tail. Tawny brown.
      Result := Shape([0.16, 0.34, 0.4, 0.17], [0.45, 0.52, 0.55, 0.075], False, 0,
        0.5, 0.58, 0.63, 0.69, True, 0.05, 0.075, 0.14, 0.22, 1.1, 0.96, 0.76);
  else
    Result := Shape([0.15, 0.43, 0.55, 0.26], [0.57, 0.65, 0.69, 0.085], True, 0.085,
      0.33, 0.47, 0.71, 0.76, True, 0.1, 0.14, 0.19, 0.29, 0.92, 0.97, 1.05);
  end;
end;

{$ENDIF}

end.
