library PlasmaSaver;

{ Screensaver module (see uSaverModules for the contract): a colour plasma
  over the whole window. Pixel mode only, so the text terminal does not offer
  it. }

uses
  System.SysUtils, System.Math, System.Generics.Collections,
  uPluginHostAbi in '..\..\..\Core\uPluginHostAbi.pas';

const
  cInfoJson = '{"id":"plasma","name":"Plasma","tickMs":50,"modes":["pixels"]}';
  cWaveLen = 1024;

type
  TPlasma = class
  private
    FTimeMs: Int64;
    FPhase: Integer;
  public
    procedure Advance(ADeltaMs: Integer);
    procedure Draw(AWidth, AHeight: Integer; APixels: PByte);
  end;

var
  GPlasmas: TObjectDictionary<Int64, TPlasma>;
  GNextHandle: Int64 = 0;
  GWave: array[0..cWaveLen - 1] of Integer;
  GPalette: array[0..255] of Cardinal;

procedure BuildTables;
var
  I: Integer;
  T: Double;
  R, G, B: Integer;
begin
  for I := 0 to cWaveLen - 1 do
    GWave[I] := Round(Sin(2 * Pi * I / cWaveLen) * 64);
  for I := 0 to 255 do
  begin
    T := 2 * Pi * I / 256;
    R := Round(127.5 + 127.5 * Sin(T));
    G := Round(127.5 + 127.5 * Sin(T + 2.094));
    B := Round(127.5 + 127.5 * Sin(T + 4.188));
    GPalette[I] := $FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
  end;
end;

procedure TPlasma.Advance(ADeltaMs: Integer);
begin
  Inc(FTimeMs, ADeltaMs);
  FPhase := Integer(FTimeMs div 8) and (cWaveLen - 1);
end;

procedure TPlasma.Draw(AWidth, AHeight: Integer; APixels: PByte);
var
  X, Y: Integer;
  ColTerm: array of Integer;
  RowTerm: Integer;
  Row: PCardinal;
begin
  SetLength(ColTerm, AWidth);
  for X := 0 to AWidth - 1 do
    ColTerm[X] := GWave[(X * 3 + FPhase) and (cWaveLen - 1)];
  for Y := 0 to AHeight - 1 do
  begin
    RowTerm := GWave[(Y * 4 + FPhase * 2) and (cWaveLen - 1)];
    Row := PCardinal(APixels + Y * AWidth * 4);
    for X := 0 to AWidth - 1 do
    begin
      // Three waves (column, row, diagonal) of about -64..64 each, shifted to 0..255.
      Row^ := GPalette[(ColTerm[X] + RowTerm + GWave[((X + Y) * 2 - FPhase) and (cWaveLen - 1)] + 192) and 255];
      Inc(Row);
    end;
  end;
end;

function mtn_saver_get_abi_version: Int64; cdecl;
begin
  Result := 1;
end;

function mtn_saver_info(ABuf: PAnsiChar; ABufSize: Int64): Int64; cdecl;
var
  Bytes: UTF8String;
begin
  Bytes := UTF8String(cInfoJson);
  if (ABuf = nil) or (Length(Bytes) + 1 > ABufSize) then
    Exit(-1);
  Move(PAnsiChar(Bytes)^, ABuf^, Length(Bytes) + 1);
  Result := Length(Bytes);
end;

function mtn_saver_create(AWidth, AHeight, ASeed: Int64): Int64; cdecl;
begin
  Inc(GNextHandle);
  Result := GNextHandle;
  GPlasmas.Add(Result, TPlasma.Create);
end;

procedure mtn_saver_resize(AHandle, AWidth, AHeight: Int64); cdecl;
begin
  // Every pixel is computed from its position each frame.
end;

procedure mtn_saver_advance(AHandle, ADeltaMs: Int64); cdecl;
var
  Plasma: TPlasma;
begin
  if GPlasmas.TryGetValue(AHandle, Plasma) then
    Plasma.Advance(Integer(ADeltaMs));
end;

function mtn_saver_draw_pixels(AHandle, AWidth, AHeight: Int64; APixels: PByte): Int64; cdecl;
var
  Plasma: TPlasma;
begin
  if (APixels = nil) or (AWidth < 1) or (AHeight < 1) or not GPlasmas.TryGetValue(AHandle, Plasma) then
    Exit(-1);
  Plasma.Draw(Integer(AWidth), Integer(AHeight), APixels);
  Result := 0;
end;

procedure mtn_saver_destroy(AHandle: Int64); cdecl;
begin
  GPlasmas.Remove(AHandle);
end;

exports
  mtn_saver_get_abi_version,
  mtn_saver_info,
  mtn_saver_create,
  mtn_saver_resize,
  mtn_saver_advance,
  mtn_saver_draw_pixels,
  mtn_saver_destroy;

begin
  BuildTables;
  GPlasmas := TObjectDictionary<Int64, TPlasma>.Create([doOwnsValues]);
end.
