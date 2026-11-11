library StarfieldSaver;

{ Screensaver module (see uSaverModules for the contract): stars flying past
  the viewer on a black screen. Text mode only. }

uses
  System.SysUtils, System.Math, System.Generics.Collections,
  uPluginHostAbi in '..\..\..\Core\uPluginHostAbi.pas';

const
  cStarCount = 220;
  cNear = 0.03;
  cInfoJson = '{"id":"starfield","name":"Starfield","tickMs":50,"modes":["text"]}';

type
  TStar = record
    X, Y, Z: Single;
  end;

  TStarField = class
  private
    FStars: array[0..cStarCount - 1] of TStar;
    FState: Cardinal;
    function NextUnit: Single;
    procedure Respawn(var AStar: TStar; AAnywhere: Boolean);
  public
    constructor Create(ASeed: Cardinal);
    procedure Advance(ADeltaMs: Integer);
    procedure Draw(ACols, ARows: Integer; ACells: PSaverCell);
  end;

var
  GFields: TObjectDictionary<Int64, TStarField>;
  GNextHandle: Int64 = 0;

constructor TStarField.Create(ASeed: Cardinal);
var
  I: Integer;
begin
  inherited Create;
  FState := ASeed or 1;
  for I := 0 to cStarCount - 1 do
    Respawn(FStars[I], True);
end;

function TStarField.NextUnit: Single;
begin
  FState := FState * 1664525 + 1013904223;
  Result := (FState shr 8) / 16777216.0;
end;

procedure TStarField.Respawn(var AStar: TStar; AAnywhere: Boolean);
begin
  AStar.X := NextUnit * 2 - 1;
  AStar.Y := NextUnit * 2 - 1;
  if AAnywhere then
    AStar.Z := cNear + NextUnit * (1 - cNear)
  else
    AStar.Z := 1;
end;

procedure TStarField.Advance(ADeltaMs: Integer);
var
  I: Integer;
  Step: Single;
begin
  Step := ADeltaMs / 1000 * 0.45;
  for I := 0 to cStarCount - 1 do
  begin
    FStars[I].Z := FStars[I].Z - Step;
    if FStars[I].Z < cNear then
      Respawn(FStars[I], False);
  end;
end;

procedure TStarField.Draw(ACols, ARows: Integer; ACells: PSaverCell);
var
  I, Px, Py, Level: Integer;
  S: TStar;
  Cell: PSaverCell;
begin
  for I := 0 to cStarCount - 1 do
  begin
    S := FStars[I];
    Px := Round(ACols / 2 + S.X / S.Z * ACols * 0.18);
    Py := Round(ARows / 2 + S.Y / S.Z * ARows * 0.34);
    if (Px < 0) or (Px >= ACols) or (Py < 0) or (Py >= ARows) then
      Continue;
    Cell := ACells;
    Inc(Cell, Py * ACols + Px);
    Level := 90 + Round((1 - S.Z) * 165);
    Cell.Fg := $FF000000 or (UInt32(Level) shl 16) or (UInt32(Level) shl 8) or UInt32(Level);
    if S.Z > 0.6 then
      Cell.CodePoint := Ord('.')
    else if S.Z > 0.25 then
      Cell.CodePoint := Ord('+')
    else
      Cell.CodePoint := Ord('*');
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

function mtn_saver_create(ACols, ARows, ASeed: Int64): Int64; cdecl;
begin
  Inc(GNextHandle);
  Result := GNextHandle;
  GFields.Add(Result, TStarField.Create(Cardinal(ASeed)));
end;

procedure mtn_saver_resize(AHandle, ACols, ARows: Int64); cdecl;
begin
  // The stars are placed relative to the window each frame.
end;

procedure mtn_saver_advance(AHandle, ADeltaMs: Int64); cdecl;
var
  Field: TStarField;
begin
  if GFields.TryGetValue(AHandle, Field) then
    Field.Advance(Integer(ADeltaMs));
end;

function mtn_saver_draw_text(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
var
  Field: TStarField;
begin
  if (ACells = nil) or (ACols < 1) or (ARows < 1) or not GFields.TryGetValue(AHandle, Field) then
    Exit(-1);
  Field.Draw(Integer(ACols), Integer(ARows), ACells);
  Result := 0;
end;

procedure mtn_saver_destroy(AHandle: Int64); cdecl;
begin
  GFields.Remove(AHandle);
end;

exports
  mtn_saver_get_abi_version,
  mtn_saver_info,
  mtn_saver_create,
  mtn_saver_resize,
  mtn_saver_advance,
  mtn_saver_draw_text,
  mtn_saver_destroy;

begin
  GFields := TObjectDictionary<Int64, TStarField>.Create([doOwnsValues]);
end.
