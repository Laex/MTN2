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
/// registration: no id, a table without the callbacks its modes need, or a
/// mode mask with neither the text nor the pixel mode.</summary>
function PluginRegisterSaver(const APluginId, AId, ACaption: string; AModes: Int64;
  ACallbacks: PSaverCallbacks; AUserData: Pointer): Boolean;

/// <summary>Writes the user's screensaver choice into ABuf as a UTF-8 JSON
/// object (saverId, minutes, minuteChoices, savers with id and caption) and a
/// NUL; returns the JSON length in bytes, -2 when ABuf (ABufSize bytes) is too
/// small.</summary>
function PluginSaverSettingsJson(ABuf: PAnsiChar; ABufSize: Int64): Int64;

/// <summary>Sets the picture (AId, '' or nil = keep) and the idle minutes
/// (AMinutes, -1 = keep) and whether every start picks a random picture
/// (ARandom: 1 = yes, 0 = no, -1 = keep). 0 = set; -1 = an unknown picture or
/// minutes value, in which case nothing is changed.</summary>
function PluginSaverApplySettings(AId: PAnsiChar; AMinutes, ARandom: Int64): Int64;

/// <summary>Paints the cells of ABuffer (ACols x ARows) onto AGrid; cells outside
/// AGrid are skipped.</summary>
procedure PaintSaverCells(const ABuffer: TArray<TSaverCell>; ACols, ARows: Integer;
  const AGrid: TTerminalGrid);

implementation

uses
  System.Math, System.UITypes, System.JSON;

const
  cMaxSaverCells = 4 * 1024 * 1024;
  cMaxSaverPixels = 8 * 1024 * 1024;

type
  TCdeclSaverEffect = class(TInterfacedObject, ISaverEffect, ISaverPixelEffect)
  private
    FCallbacks: TSaverCallbacks;
    FUserData: Pointer;
    FModes: Int64;
    FBuffer: TArray<TSaverCell>;
    FPixels: TBytes;
    FFailed: Boolean;
    FTickMs: Integer;
  public
    constructor Create(const ACallbacks: TSaverCallbacks; AModes: Int64; AUserData: Pointer);
    function TickMs: Integer;
    procedure Prepare;
    procedure Advance(ASeconds: Double);
    procedure Draw(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    function DrawPixels(AWidth, AHeight: Integer; out APixels: PByte): Boolean;
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

constructor TCdeclSaverEffect.Create(const ACallbacks: TSaverCallbacks; AModes: Int64;
  AUserData: Pointer);
begin
  inherited Create;
  FCallbacks := ACallbacks;
  FModes := AModes;
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
  // A picture with only the pixel mode leaves the blank screen.
  if not FFailed and Assigned(FCallbacks.Draw) then
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

function TCdeclSaverEffect.DrawPixels(AWidth, AHeight: Integer; out APixels: PByte): Boolean;
var
  I: Integer;
begin
  Result := False;
  APixels := nil;
  if FFailed or (FModes and cSaverModePixels = 0) or not Assigned(FCallbacks.DrawPixels) then
    Exit;
  if (AWidth < 1) or (AHeight < 1) or (Int64(AWidth) * AHeight > cMaxSaverPixels) then
    Exit;
  if Length(FPixels) <> AWidth * AHeight * 4 then
    SetLength(FPixels, AWidth * AHeight * 4);
  // Opaque black, B G R A.
  for I := 0 to AWidth * AHeight - 1 do
    PCardinal(@FPixels[I * 4])^ := $FF000000;
  try
    if FCallbacks.DrawPixels(FUserData, AWidth, AHeight, @FPixels[0]) <> 0 then
    begin
      FFailed := True;
      Exit;
    end;
  except
    FFailed := True;
    Exit;
  end;
  APixels := @FPixels[0];
  Result := True;
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
  Modes: Int64;
begin
  Result := False;
  if (ACallbacks = nil) or (APluginId = '') or (Trim(AId) = '') then
    Exit;
  Modes := AModes and (cSaverModeText or cSaverModePixels);
  if Modes = 0 then
    Exit;
  Callbacks := ACallbacks^;
  if not (Assigned(Callbacks.Prepare) and Assigned(Callbacks.Advance) and
          Assigned(Callbacks.Finish)) then
    Exit;
  if (Modes and cSaverModeText <> 0) and not Assigned(Callbacks.Draw) then
    Exit;
  if (Modes and cSaverModePixels <> 0) and not Assigned(Callbacks.DrawPixels) then
    Exit;
  Caption := ACaption;
  if Caption = '' then
    Caption := AId;
  Result := RegisterSaver(AId, Caption, APluginId,
    function: ISaverEffect
    begin
      Result := TCdeclSaverEffect.Create(Callbacks, Modes, AUserData);
    end, Modes);
end;

function PluginSaverSettingsJson(ABuf: PAnsiChar; ABufSize: Int64): Int64;
var
  Root: TJSONObject;
  Choices, List: TJSONArray;
  Item: TJSONObject;
  Info: TSaverInfo;
  Minutes: Integer;
  Bytes: UTF8String;
begin
  try
    Root := TJSONObject.Create;
    try
      Root.AddPair('saverId', GSaverId);
      Root.AddPair('random', TJSONBool.Create(GSaverRandom));
      Root.AddPair('minutes', TJSONNumber.Create(GSaverMinutes));
      Choices := TJSONArray.Create;
      for Minutes in cSaverMinuteChoices do
        Choices.Add(Minutes);
      Root.AddPair('minuteChoices', Choices);
      List := TJSONArray.Create;
      for Info in RegisteredSavers do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('id', Info.Id);
        Item.AddPair('caption', Info.Caption);
        List.AddElement(Item);
      end;
      Root.AddPair('savers', List);
      Bytes := UTF8String(Root.ToJSON);
    finally
      Root.Free;
    end;
    if (ABuf = nil) or (Int64(Length(Bytes)) + 1 > ABufSize) then
      Exit(-2);
    if Length(Bytes) > 0 then
      Move(Bytes[1], ABuf^, Length(Bytes));
    PByte(ABuf)[Length(Bytes)] := 0;
    Result := Length(Bytes);
  except
    Result := -2;
  end;
end;

function PluginSaverApplySettings(AId: PAnsiChar; AMinutes, ARandom: Int64): Int64;
var
  Id: string;
  Info: TSaverInfo;
  Known: Boolean;
  Minutes: Integer;
begin
  try
    if AId = nil then
      Id := ''
    else
      Id := UTF8ToString(AId);
    // Both values are checked before either is applied.
    if Id <> '' then
    begin
      Known := False;
      for Info in RegisteredSavers do
        if SameText(Info.Id, Id) then
        begin
          Id := Info.Id;
          Known := True;
        end;
      if not Known then
        Exit(-1);
    end;
    if AMinutes >= 0 then
    begin
      Known := False;
      for Minutes in cSaverMinuteChoices do
        if Minutes = AMinutes then
          Known := True;
      if not Known then
        Exit(-1);
    end;
    if Id <> '' then
      GSaverId := Id;
    if AMinutes >= 0 then
      GSaverMinutes := Integer(AMinutes);
    if ARandom >= 0 then
      GSaverRandom := ARandom <> 0;
    Result := 0;
  except
    Result := -1;
  end;
end;

end.
