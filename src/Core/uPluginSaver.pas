unit uPluginSaver;

{ Screensaver pictures that a plugin hands to the host (RegisterSaver of the
  plugin ABI). The plugin gives a table of cdecl callbacks and an opaque
  pointer; the host wraps them in an ISaverEffect and registers it with the
  screensaver registry (uScreenSaver).

  The plugin draws into a cell buffer the host owns: ACols x ARows records of
  TSaverCell, filled with black blanks before every call. The records hold no
  pointers, so the same buffer can be copied in and out of a sandboxed module.
  Every call into the plugin runs under try/except, and a picture whose
  callback raised or reported a failure ends the saver instead of drawing on.
  Main thread only. }

interface

uses
  System.SysUtils, uTerminalTypes, uScreenSaver, uPluginHostAbi;

/// <summary>Registers the picture AId of plugin APluginId. False for a refused
/// registration: no id, a table without the needed callbacks, or a mode mask
/// without the text mode.</summary>
function PluginRegisterSaver(const APluginId, AId, ACaption: string; AModes: Int64;
  ACallbacks: PSaverCallbacks; AUserData: Pointer): Boolean;

/// <summary>Paints the cells of ABuffer (ACols x ARows) onto AGrid; cells outside
/// AGrid are skipped.</summary>
procedure PaintSaverCells(const ABuffer: TArray<TSaverCell>; ACols, ARows: Integer;
  const AGrid: TTerminalGrid);

implementation

uses
  System.Math, System.UITypes;

const
  cMaxSaverCells = 4 * 1024 * 1024;

type
  TCdeclSaverEffect = class(TInterfacedObject, ISaverEffect)
  private
    FCallbacks: TSaverCallbacks;
    FUserData: Pointer;
    FBuffer: TArray<TSaverCell>;
    FFailed: Boolean;
    FTickMs: Integer;
  public
    constructor Create(const ACallbacks: TSaverCallbacks; AUserData: Pointer);
    function TickMs: Integer;
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    procedure Finish;
  end;

function AttributesOf(AFlags: UInt32): TCharCellAttributes;
begin
  Result := [];
  if AFlags and cSaverAttrBold <> 0 then
    Include(Result, ccaBold);
  if AFlags and cSaverAttrItalic <> 0 then
    Include(Result, ccaItalic);
  if AFlags and cSaverAttrUnderline <> 0 then
    Include(Result, ccaUnderline);
  if AFlags and cSaverAttrReverse <> 0 then
    Include(Result, ccaReverse);
end;

procedure PaintSaverCells(const ABuffer: TArray<TSaverCell>; ACols, ARows: Integer;
  const AGrid: TTerminalGrid);
var
  X, Y, W: Integer;
  Cell: TSaverCell;
  Ch: Char;
begin
  for Y := 0 to Min(ARows, Length(AGrid)) - 1 do
  begin
    W := Min(ACols, Length(AGrid[Y]));
    for X := 0 to W - 1 do
    begin
      if Y * ACols + X >= Length(ABuffer) then
        Exit;
      Cell := ABuffer[Y * ACols + X];
      // A code point beyond the basic plane has no single cell character.
      if (Cell.CodePoint = 0) or (Cell.CodePoint > $FFFF) or
         ((Cell.CodePoint >= $D800) and (Cell.CodePoint <= $DFFF)) then
        Ch := ' '
      else
        Ch := Char(Cell.CodePoint);
      AGrid[Y][X] := TCharCell.Make(Ch, TAlphaColor(Cell.Fg), TAlphaColor(Cell.Bg),
        AttributesOf(Cell.Attributes));
    end;
  end;
end;

{ TCdeclSaverEffect }

constructor TCdeclSaverEffect.Create(const ACallbacks: TSaverCallbacks; AUserData: Pointer);
begin
  inherited Create;
  FCallbacks := ACallbacks;
  FUserData := AUserData;
  FTickMs := 90;
  if Assigned(FCallbacks.TickMs) then
    try
      FTickMs := Integer(FCallbacks.TickMs(FUserData));
    except
      FTickMs := 90;
    end;
  if FTickMs < 10 then
    FTickMs := 10;
  if FTickMs > 1000 then
    FTickMs := 1000;
end;

function TCdeclSaverEffect.TickMs: Integer;
begin
  Result := FTickMs;
end;

procedure TCdeclSaverEffect.Prepare;
begin
  FFailed := False;
  try
    if FCallbacks.Prepare(FUserData) <> 0 then
      FFailed := True;
  except
    FFailed := True;
  end;
end;

procedure TCdeclSaverEffect.Advance(ASeconds: Double);
begin
  if FFailed then
    Exit;
  try
    FCallbacks.Advance(FUserData, Round(ASeconds * 1000));
  except
    FFailed := True;
  end;
end;

procedure TCdeclSaverEffect.Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
var
  I, Count: Integer;
  Blank: TSaverCell;
begin
  if (ACols < 1) or (ARows < 1) or (Int64(ACols) * ARows > cMaxSaverCells) then
    Exit;
  Count := ACols * ARows;
  if Length(FBuffer) <> Count then
    SetLength(FBuffer, Count);
  Blank.CodePoint := Ord(' ');
  Blank.Fg := $FFFFFFFF;
  Blank.Bg := $FF000000;
  Blank.Attributes := 0;
  for I := 0 to Count - 1 do
    FBuffer[I] := Blank;
  if not FFailed then
    try
      if FCallbacks.Draw(FUserData, ACols, ARows, @FBuffer[0]) <> 0 then
        FFailed := True;
    except
      FFailed := True;
    end;
  // A failed picture leaves a black screen the next key press ends.
  if FFailed then
    for I := 0 to Count - 1 do
      FBuffer[I] := Blank;
  PaintSaverCells(FBuffer, ACols, ARows, AGrid);
end;

procedure TCdeclSaverEffect.Finish;
begin
  try
    FCallbacks.Finish(FUserData);
  except
    // The picture is dropped right after; nothing more to do for it.
  end;
end;

function PluginRegisterSaver(const APluginId, AId, ACaption: string; AModes: Int64;
  ACallbacks: PSaverCallbacks; AUserData: Pointer): Boolean;
var
  Callbacks: TSaverCallbacks;
  Caption: string;
begin
  Result := False;
  if (ACallbacks = nil) or (APluginId = '') or (Trim(AId) = '') then
    Exit;
  if AModes and cSaverModeText = 0 then
    Exit;
  Callbacks := ACallbacks^;
  if not (Assigned(Callbacks.Prepare) and Assigned(Callbacks.Advance) and
          Assigned(Callbacks.Draw) and Assigned(Callbacks.Finish)) then
    Exit;
  Caption := ACaption;
  if Caption = '' then
    Caption := AId;
  Result := RegisterSaver(AId, Caption, APluginId,
    function: ISaverEffect
    begin
      Result := TCdeclSaverEffect.Create(Callbacks, AUserData);
    end);
end;

end.
