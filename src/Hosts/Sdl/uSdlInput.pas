unit uSdlInput;

{ Turns SDL events into the terminal events the host shell understands
  (uTermInput.TTermEvent): keys, typed text, mouse buttons, movement and
  wheel, dropped files. Typed characters arrive through text input events so
  the keyboard layout and input methods decide what is typed; chords with Ctrl
  or Alt, which have no text, are reported as keys, with letters taken from
  the physical key so shortcuts work in any layout. No SDL library is needed:
  the events are plain bytes (uSdlApi). }

interface

uses
  System.Classes, System.Generics.Collections, System.UITypes,
  uTermInput, uSdlApi;

type
  TSdlInputMapper = class
  strict private
    FCellW, FCellH: Integer;
    FPixelScale: Single;
    FMods: Integer;
    FCol, FRow: Integer;
    FHaveCell: Boolean;
    FInDrop: Boolean;
    FDropBatch: string;
    procedure CellOf(AX, AY: Integer; out ACol, ARow: Integer);
    procedure AddKey(const AEvents: TList<TTermEvent>; AKey: Word; AChar: Char;
      AShift: TShiftState);
    procedure MapKeyDown(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure MapKeyUp(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure MapText(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure MapMotion(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure MapButton(const E: TSDLEvent; APressed: Boolean;
      const AEvents: TList<TTermEvent>);
    procedure MapWheel(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure MapDrop(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    procedure FlushDrop(const AEvents: TList<TTermEvent>);
  public
    constructor Create;
    /// <summary>Size of a character cell in the pixels of the mouse events.</summary>
    procedure SetCellSize(AWidth, AHeight: Integer);
    /// <summary>Pixels of the drawing surface per window unit (HiDPI); mouse
    /// positions are given in window units.</summary>
    procedure SetPixelScale(AScale: Single);
    /// <summary>Appends the terminal events an SDL event stands for.</summary>
    procedure Translate(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
    /// <summary>The modifier keys that are held (SDL_GetModState); mouse and text
    /// events carry none of their own.</summary>
    property Mods: Integer read FMods write FMods;
  end;

/// <summary>Virtual key of a key symbol that is not a typed character; 0 when
/// it has none. The keypad moves the cursor while Num Lock is off.</summary>
function SdlKeyToVirtual(ASym: Integer; ANumLock: Boolean): Word;

/// <summary>Shift, Ctrl and Alt of an SDL modifier mask; AltGr counts as none.</summary>
function SdlModsToShift(AMods: Integer): TShiftState;

implementation

uses
  System.SysUtils, System.Math;

const
  cScancodeMask = $40000000;
  // Scancodes of the keys that are not characters.
  scLCtrl = 224;
  scLShift = 225;
  scLAlt = 226;
  scRCtrl = 228;
  scRShift = 229;
  scRAlt = 230;
  scF1 = 58;
  scPrintScreen = 70;
  scInsert = 73;
  scHome = 74;
  scPageUp = 75;
  scEnd = 77;
  scPageDown = 78;
  scRight = 79;
  scLeft = 80;
  scDown = 81;
  scUp = 82;
  scKpDivide = 84;
  scKpEnter = 88;
  scKp1 = 89;
  scKp0 = 98;
  scKpPeriod = 99;
  scApplication = 101;
  scF13 = 104;
  cMaxWheelSteps = 10;

function IsAltGr(AMods: Integer): Boolean;
begin
  Result := ((AMods and KMOD_MODE) <> 0) or
    (((AMods and KMOD_RALT) <> 0) and ((AMods and KMOD_LCTRL) <> 0));
end;

function SdlModsToShift(AMods: Integer): TShiftState;
begin
  Result := [];
  if (AMods and (KMOD_LSHIFT or KMOD_RSHIFT)) <> 0 then
    Include(Result, ssShift);
  if IsAltGr(AMods) then
    Exit;
  if (AMods and (KMOD_LCTRL or KMOD_RCTRL)) <> 0 then
    Include(Result, ssCtrl);
  if (AMods and (KMOD_LALT or KMOD_RALT)) <> 0 then
    Include(Result, ssAlt);
end;

function ScancodeToVirtual(AScan: Integer): Word;
begin
  Result := 0;
  case AScan of
    4..29: Result := Ord('A') + (AScan - 4);
    30..38: Result := Ord('1') + (AScan - 30);
    39: Result := Ord('0');
    scF1..scF1 + 11: Result := vkF1 + (AScan - scF1);
    scF13..scF13 + 11: Result := vkF1 + 12 + (AScan - scF13);
    scPrintScreen: Result := vkSnapshot;
    scInsert: Result := vkInsert;
    scHome: Result := vkHome;
    scPageUp: Result := vkPrior;
    scEnd: Result := vkEnd;
    scPageDown: Result := vkNext;
    scRight: Result := vkRight;
    scLeft: Result := vkLeft;
    scDown: Result := vkDown;
    scUp: Result := vkUp;
    scApplication: Result := vkApps;
  end;
end;

function SdlKeyToVirtual(ASym: Integer; ANumLock: Boolean): Word;
var
  Scan: Integer;
begin
  case ASym of
    13: Exit(vkReturn);
    27: Exit(vkEscape);
    8: Exit(vkBack);
    9: Exit(vkTab);
    127: Exit(vkDelete);
  end;
  if (ASym and cScancodeMask) <> 0 then
  begin
    Scan := ASym and not cScancodeMask;
    if Scan = scKpEnter then
      Exit(vkReturn);
    if (Scan >= scKp1) and (Scan <= scKp0) and not ANumLock then
      // The keypad moves the cursor while Num Lock is off.
      case Scan of
        scKp1: Exit(vkEnd);
        scKp1 + 1: Exit(vkDown);
        scKp1 + 2: Exit(vkNext);
        scKp1 + 3: Exit(vkLeft);
        scKp1 + 5: Exit(vkRight);
        scKp1 + 6: Exit(vkHome);
        scKp1 + 7: Exit(vkUp);
        scKp1 + 8: Exit(vkPrior);
        scKp0: Exit(vkInsert);
      end;
    if (Scan = scKpPeriod) and not ANumLock then
      Exit(vkDelete);
    Exit(ScancodeToVirtual(Scan));
  end;
  Result := 0;
end;

{ TSdlInputMapper }

constructor TSdlInputMapper.Create;
begin
  inherited Create;
  FCellW := 1;
  FCellH := 1;
  FPixelScale := 1;
end;

procedure TSdlInputMapper.SetCellSize(AWidth, AHeight: Integer);
begin
  FCellW := Max(1, AWidth);
  FCellH := Max(1, AHeight);
end;

procedure TSdlInputMapper.SetPixelScale(AScale: Single);
begin
  if AScale > 0 then
    FPixelScale := AScale;
end;

procedure TSdlInputMapper.CellOf(AX, AY: Integer; out ACol, ARow: Integer);
begin
  ACol := Max(0, Trunc(AX * FPixelScale) div FCellW);
  ARow := Max(0, Trunc(AY * FPixelScale) div FCellH);
end;

procedure TSdlInputMapper.AddKey(const AEvents: TList<TTermEvent>; AKey: Word;
  AChar: Char; AShift: TShiftState);
var
  Ev: TTermEvent;
begin
  Ev := Default(TTermEvent);
  Ev.Kind := tekKey;
  Ev.Key := AKey;
  Ev.KeyChar := AChar;
  Ev.Shift := AShift;
  AEvents.Add(Ev);
end;

procedure TSdlInputMapper.MapKeyDown(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  Sym, Scan, Mods: Integer;
  Vk: Word;
  Shift, Base: TShiftState;
begin
  Scan := SdlEventI32(E, 16);
  Sym := SdlEventI32(E, 20);
  Mods := SdlEventU32(E, 24) and $FFFF;
  FMods := Mods;
  Shift := SdlModsToShift(Mods);
  Vk := SdlKeyToVirtual(Sym, (Mods and KMOD_NUM) <> 0);
  if Vk <> 0 then
  begin
    AddKey(AEvents, Vk, #0, Shift);
    Exit;
  end;
  // Keys that produce text arrive again as text input events; only chords
  // are reported here.
  if not ((ssCtrl in Shift) or (ssAlt in Shift)) then
    Exit;
  if (Scan >= 4) and (Scan <= 39) then
    Vk := ScancodeToVirtual(Scan)
  else if (Sym >= 32) and (Sym < 127) then
  begin
    CharToKey(Char(Sym), Vk, Base);
    Shift := Shift + Base;
  end;
  if Vk <> 0 then
    AddKey(AEvents, Vk, #0, Shift);
end;

procedure TSdlInputMapper.MapKeyUp(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  Scan, Mods, Bit: Integer;
  Ev: TTermEvent;
begin
  Scan := SdlEventI32(E, 16);
  case Scan of
    scLCtrl: Bit := KMOD_LCTRL;
    scLShift: Bit := KMOD_LSHIFT;
    scLAlt: Bit := KMOD_LALT;
    scRCtrl: Bit := KMOD_RCTRL;
    scRShift: Bit := KMOD_RSHIFT;
    scRAlt: Bit := KMOD_RALT;
  else
    Exit;
  end;
  // Whether the mask of a release still holds the key depends on the SDL
  // version, so the key's own bit is cleared.
  Mods := (SdlEventU32(E, 24) and $FFFF) and not Bit;
  FMods := Mods;
  Ev := Default(TTermEvent);
  Ev.Kind := tekModifiers;
  Ev.Shift := SdlModsToShift(Mods);
  AEvents.Add(Ev);
end;

procedure TSdlInputMapper.MapText(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  Text: string;
  Ch: Char;
  Key: Word;
  Base: TShiftState;
begin
  // A chord is reported by its key press; some systems also send text for it.
  if (ssCtrl in SdlModsToShift(FMods)) or (ssAlt in SdlModsToShift(FMods)) then
    Exit;
  Text := SdlEventText(E);
  for Ch in Text do
  begin
    CharToKey(Ch, Key, Base);
    AddKey(AEvents, Key, Ch, Base);
  end;
end;

procedure TSdlInputMapper.MapMotion(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  Col, Row: Integer;
  Ev: TTermEvent;
begin
  CellOf(SdlEventI32(E, 20), SdlEventI32(E, 24), Col, Row);
  if FHaveCell and (Col = FCol) and (Row = FRow) then
    Exit;
  FCol := Col;
  FRow := Row;
  FHaveCell := True;
  Ev := Default(TTermEvent);
  Ev.Kind := tekMouse;
  Ev.MouseAction := tmaMove;
  Ev.Col := Col;
  Ev.Row := Row;
  Ev.Shift := SdlModsToShift(FMods);
  AEvents.Add(Ev);
end;

procedure TSdlInputMapper.MapButton(const E: TSDLEvent; APressed: Boolean;
  const AEvents: TList<TTermEvent>);
var
  Ev: TTermEvent;
begin
  Ev := Default(TTermEvent);
  Ev.Kind := tekMouse;
  case SdlEventU8(E, 16) of
    SDL_BUTTON_LEFT: Ev.Button := TMouseButton.mbLeft;
    SDL_BUTTON_MIDDLE: Ev.Button := TMouseButton.mbMiddle;
    SDL_BUTTON_RIGHT: Ev.Button := TMouseButton.mbRight;
  else
    Exit;
  end;
  if APressed then
    Ev.MouseAction := tmaPress
  else
    Ev.MouseAction := tmaRelease;
  CellOf(SdlEventI32(E, 20), SdlEventI32(E, 24), Ev.Col, Ev.Row);
  FCol := Ev.Col;
  FRow := Ev.Row;
  FHaveCell := True;
  Ev.Shift := SdlModsToShift(FMods);
  AEvents.Add(Ev);
end;

procedure TSdlInputMapper.MapWheel(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  DX, DY, I: Integer;
  Flipped: Boolean;
  Ev: TTermEvent;
begin
  DX := SdlEventI32(E, 16);
  DY := SdlEventI32(E, 20);
  Flipped := SdlEventU32(E, 24) = SDL_MOUSEWHEEL_FLIPPED;
  if Flipped then
  begin
    DX := -DX;
    DY := -DY;
  end;
  Ev := Default(TTermEvent);
  Ev.Kind := tekMouse;
  Ev.Col := FCol;
  Ev.Row := FRow;
  Ev.Shift := SdlModsToShift(FMods);
  for I := 1 to Min(Abs(DY), cMaxWheelSteps) do
  begin
    if DY > 0 then
      Ev.MouseAction := tmaWheelUp
    else
      Ev.MouseAction := tmaWheelDown;
    AEvents.Add(Ev);
  end;
  for I := 1 to Min(Abs(DX), cMaxWheelSteps) do
  begin
    if DX > 0 then
      Ev.MouseAction := tmaWheelRight
    else
      Ev.MouseAction := tmaWheelLeft;
    AEvents.Add(Ev);
  end;
end;

procedure TSdlInputMapper.FlushDrop(const AEvents: TList<TTermEvent>);
var
  Ev: TTermEvent;
begin
  if FDropBatch = '' then
    Exit;
  Ev := Default(TTermEvent);
  Ev.Kind := tekDrop;
  Ev.Text := FDropBatch;
  Ev.Shift := SdlModsToShift(FMods);
  Ev.Col := FCol;
  Ev.Row := FRow;
  FDropBatch := '';
  AEvents.Add(Ev);
end;

procedure TSdlInputMapper.MapDrop(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
var
  Path: string;
begin
  Path := SdlEventDropFile(E);
  if Path = '' then
    Exit;
  if FDropBatch <> '' then
    FDropBatch := FDropBatch + #10;
  FDropBatch := FDropBatch + Path;
  // Between SDL_DROPBEGIN and SDL_DROPCOMPLETE the files are one drop; a
  // lone file event stands for a drop of its own.
  if not FInDrop then
    FlushDrop(AEvents);
end;

procedure TSdlInputMapper.Translate(const E: TSDLEvent; const AEvents: TList<TTermEvent>);
begin
  case SdlEventType(E) of
    SDL_KEYDOWN: MapKeyDown(E, AEvents);
    SDL_KEYUP: MapKeyUp(E, AEvents);
    SDL_TEXTINPUT: MapText(E, AEvents);
    SDL_MOUSEMOTION: MapMotion(E, AEvents);
    SDL_MOUSEBUTTONDOWN: MapButton(E, True, AEvents);
    SDL_MOUSEBUTTONUP: MapButton(E, False, AEvents);
    SDL_MOUSEWHEEL: MapWheel(E, AEvents);
    SDL_DROPFILE: MapDrop(E, AEvents);
    SDL_DROPBEGIN:
      begin
        FInDrop := True;
        FDropBatch := '';
      end;
    SDL_DROPCOMPLETE:
      begin
        FInDrop := False;
        FlushDrop(AEvents);
      end;
  end;
end;

end.
