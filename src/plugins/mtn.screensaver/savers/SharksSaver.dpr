library SharksSaver;

{ Screensaver module (see uSaverModules for the contract): sharks hunting
  schools of fish on a black screen. Text mode only; the world and its drawing
  are the units of the ascii-sharks folder. }

{$I ..\..\..\ascii-sharks\sharks.inc}

uses
  System.SysUtils, System.UITypes, System.Generics.Collections,
  uPluginHostAbi in '..\..\..\Core\uPluginHostAbi.pas',
  uTerminalTypes in '..\..\..\Core\uTerminalTypes.pas',
  uSharkPicture in '..\..\..\ascii-sharks\uSharkPicture.pas';

const
  cInfoJson = '{"id":"sharks","name":"Sharks","tickMs":90,"modes":["text"]}';

type
  /// <summary>One running picture and the grid it paints before it is copied to cells.</summary>
  TSharkInstance = class
  public
    Picture: TSharkPicture;
    Grid: TTerminalGrid;
    constructor Create(ASeed: Cardinal);
    destructor Destroy; override;
    procedure Draw(ACols, ARows: Integer; ACells: PSaverCell);
  end;

var
  GInstances: TObjectDictionary<Int64, TSharkInstance>;
  GNextHandle: Int64 = 0;

constructor TSharkInstance.Create(ASeed: Cardinal);
begin
  inherited Create;
  Picture := TSharkPicture.Create(ASeed);
  Picture.Prepare;
end;

destructor TSharkInstance.Destroy;
begin
  Picture.Free;
  inherited Destroy;
end;

function AttributeBits(const AAttributes: TCharCellAttributes): UInt32;
begin
  Result := 0;
  if ccaBold in AAttributes then
    Result := Result or cSaverAttrBold;
  if ccaItalic in AAttributes then
    Result := Result or cSaverAttrItalic;
  if ccaUnderline in AAttributes then
    Result := Result or cSaverAttrUnderline;
  if ccaReverse in AAttributes then
    Result := Result or cSaverAttrReverse;
end;

procedure TSharkInstance.Draw(ACols, ARows: Integer; ACells: PSaverCell);
var
  X, Y: Integer;
  Cell: TCharCell;
  Dest: PSaverCell;
begin
  if (Length(Grid) <> ARows) or ((ARows > 0) and (Length(Grid[0]) <> ACols)) then
  begin
    SetLength(Grid, ARows);
    for Y := 0 to ARows - 1 do
      SetLength(Grid[Y], ACols);
  end;
  for Y := 0 to ARows - 1 do
    for X := 0 to ACols - 1 do
      Grid[Y][X] := TCharCell.Make(' ', TAlphaColor($FFFFFFFF), TAlphaColor($FF000000));
  Picture.Draw(Grid, ACols, ARows);
  Dest := ACells;
  for Y := 0 to ARows - 1 do
    for X := 0 to ACols - 1 do
    begin
      Cell := Grid[Y][X];
      if Cell.CharValue = ' ' then
        Dest.CodePoint := 0
      else
        Dest.CodePoint := Ord(Cell.CharValue);
      Dest.Fg := Cell.FgColor;
      Dest.Bg := Cell.BgColor;
      Dest.Attributes := AttributeBits(Cell.Attributes);
      Inc(Dest);
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
  GInstances.Add(Result, TSharkInstance.Create(Cardinal(ASeed)));
end;

procedure mtn_saver_resize(AHandle, ACols, ARows: Int64); cdecl;
begin
  // The picture follows the size it is drawn at.
end;

procedure mtn_saver_advance(AHandle, ADeltaMs: Int64); cdecl;
var
  Instance: TSharkInstance;
begin
  if GInstances.TryGetValue(AHandle, Instance) then
    Instance.Picture.Advance(ADeltaMs / 1000);
end;

function mtn_saver_draw_text(AHandle, ACols, ARows: Int64; ACells: PSaverCell): Int64; cdecl;
var
  Instance: TSharkInstance;
begin
  if (ACells = nil) or (ACols < 1) or (ARows < 1) or not GInstances.TryGetValue(AHandle, Instance) then
    Exit(-1);
  Instance.Draw(Integer(ACols), Integer(ARows), ACells);
  Result := 0;
end;

procedure mtn_saver_destroy(AHandle: Int64); cdecl;
begin
  GInstances.Remove(AHandle);
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
  GInstances := TObjectDictionary<Int64, TSharkInstance>.Create([doOwnsValues]);
end.
