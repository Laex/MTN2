unit uSharkMath;

{$I sharks.inc}

{ Numbers for the shark simulation: clamping, angles, a hash that gives the
  same texture to the same place, the ocean current and a small random number
  generator that can be seeded. }

interface

{$IFDEF MTN_ASCII_SHARKS}

const
  cTau = 2 * Pi;

type
  /// <summary>Linear congruential generator; the same seed gives the same sequence.</summary>
  TSharkRandom = class
  private
    FState: Cardinal;
  public
    constructor Create(ASeed: Cardinal);
    /// <summary>0 <= value < 1.</summary>
    function Next: Double;
    function Range(ALo, AHi: Double): Double;
    /// <summary>ALo .. AHi, both included.</summary>
    function IntRange(ALo, AHi: Integer): Integer;
  end;

function SharkClamp(AValue, ALo, AHi: Double): Double;
function SmoothStep(AEdge0, AEdge1, AValue: Double): Double;
/// <summary>Shortest signed angle from A to B, in (-Pi, Pi].</summary>
function AngleDiff(A, B: Double): Double;
/// <summary>Whole 32 bits of the hash of three integers; the same input gives
/// the same value on every platform.</summary>
function HashBits(X, Y, Z: Int64): Cardinal;
/// <summary>HashBits scaled to 0 <= value < 1.</summary>
function Hash3(X, Y, Z: Int64): Double;
/// <summary>Divergence-free ocean current at (X, Y) and time T, in pixels per
/// second squared: it moves schools about without bunching them in a corner.</summary>
procedure OceanCurrent(X, Y, T: Double; out AX, AY: Double);

{$ENDIF}

implementation

{$IFDEF MTN_ASCII_SHARKS}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

uses
  System.Math;

const
  cK1 = 1 / 260;
  cK2 = 1 / 310;
  cK3 = 1 / 190;
  cCurrentScale = 3400;

{ TSharkRandom }

constructor TSharkRandom.Create(ASeed: Cardinal);
begin
  inherited Create;
  FState := ASeed;
  if FState = 0 then
    FState := 1;
end;

function TSharkRandom.Next: Double;
begin
  FState := FState * 1664525 + 1013904223;
  Result := (FState shr 8) / 16777216.0;
end;

function TSharkRandom.Range(ALo, AHi: Double): Double;
begin
  Result := ALo + Next * (AHi - ALo);
end;

function TSharkRandom.IntRange(ALo, AHi: Integer): Integer;
begin
  Result := ALo + Integer(Trunc(Next * (AHi - ALo + 1)));
  if Result > AHi then
    Result := AHi;
end;

function SharkClamp(AValue, ALo, AHi: Double): Double;
begin
  if AValue < ALo then
    Result := ALo
  else if AValue > AHi then
    Result := AHi
  else
    Result := AValue;
end;

function SmoothStep(AEdge0, AEdge1, AValue: Double): Double;
var
  T: Double;
begin
  T := SharkClamp((AValue - AEdge0) / (AEdge1 - AEdge0), 0, 1);
  Result := T * T * (3 - 2 * T);
end;

function AngleDiff(A, B: Double): Double;
begin
  Result := B - A;
  // A modulo that keeps the sign, as the original does.
  Result := Result - cTau * Trunc(Result / cTau);
  if Result > Pi then
    Result := Result - cTau;
  if Result < -Pi then
    Result := Result + cTau;
end;

function HashBits(X, Y, Z: Int64): Cardinal;
var
  H: Cardinal;
begin
  H := (Cardinal(X and $FFFFFFFF) * 374761393) xor
    (Cardinal(Y and $FFFFFFFF) * 668265263) xor
    (Cardinal(Z and $FFFFFFFF) * 1442695041);
  H := (H xor (H shr 13)) * 1274126177;
  H := H xor (H shr 16);
  Result := H;
end;

function Hash3(X, Y, Z: Int64): Double;
begin
  Result := HashBits(X, Y, Z) / 4294967296.0;
end;

procedure OceanCurrent(X, Y, T: Double; out AX, AY: Double);
var
  A, B, C: Double;
begin
  A := X * cK1 + T * 0.07;
  B := Y * cK2 - T * 0.05;
  C := (X + Y) * cK3 + T * 0.11;
  // u = d(psi)/dy, v = -d(psi)/dx with psi = sin(a) cos(b) + 0.5 sin(c)
  AX := (-cK2 * Sin(A) * Sin(B) + 0.5 * cK3 * Cos(C)) * cCurrentScale;
  AY := (-cK1 * Cos(A) * Cos(B) - 0.5 * cK3 * Cos(C)) * cCurrentScale;
end;

{$ENDIF}

end.
