unit TestSdlInput;

{ SDL events become the terminal events of the host shell: typed text from
  text input events, chords from key presses (letters by physical key, so
  they work in any layout), mouse positions as cells, wheel steps and dropped
  files. The events are built byte by byte in the layout of SDL_Event. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSdlInput = class
  public
    [Test] procedure NamedKeysAreKeysWithTheirModifiers;
    [Test] procedure FunctionAndArrowKeysUseTheScancodeRange;
    [Test] procedure TypingWaitsForTheTextEvent;
    [Test] procedure TypedUpperCaseCarriesShift;
    [Test] procedure NonLatinTextHasNoKeyCode;
    [Test] procedure ChordUsesThePhysicalKeyInAnyLayout;
    [Test] procedure AltChordIsAKey;
    [Test] procedure AltGrTextIsNotAChord;
    [Test] procedure TextWithControlHeldIsDropped;
    [Test] procedure KeypadFollowsNumLock;
    [Test] procedure MouseMotionReportsCellChangesOnly;
    [Test] procedure PixelScaleMapsHighDpiPositions;
    [Test] procedure ButtonsMapToMouseButtons;
    [Test] procedure WheelSendsOneEventPerStep;
    [Test] procedure FlippedWheelReverses;
    [Test] procedure DroppedFileIsPastedAsPath;
    [Test] procedure ModifierMaskBecomesShiftState;
    [Test] procedure ReleasingAModifierReportsWhatIsStillHeld;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.UITypes,
  uTermInput, uSdlApi, uSdlInput;

const
  cScancodeBit = $40000000;

function KeyDown(ASym, AScan, AMods: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_KEYDOWN);
  SdlEventSetU32(Result, 16, Cardinal(AScan));
  SdlEventSetU32(Result, 20, Cardinal(ASym));
  SdlEventSetU32(Result, 24, Cardinal(AMods));
end;

function KeyUp(AScan, AMods: Integer): TSDLEvent;
begin
  Result := KeyDown(0, AScan, AMods);
  SdlEventSetU32(Result, 0, SDL_KEYUP);
end;

function TextInput(const AText: string): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_TEXTINPUT);
  SdlEventSetText(Result, AText);
end;

function Motion(AX, AY: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_MOUSEMOTION);
  SdlEventSetU32(Result, 20, Cardinal(AX));
  SdlEventSetU32(Result, 24, Cardinal(AY));
end;

function Button(AType: Cardinal; AButton: Byte; AX, AY: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, AType);
  SdlEventSetU8(Result, 16, AButton);
  SdlEventSetU32(Result, 20, Cardinal(AX));
  SdlEventSetU32(Result, 24, Cardinal(AY));
end;

function Wheel(AX, AY: Integer; AFlipped: Boolean = False): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_MOUSEWHEEL);
  SdlEventSetU32(Result, 16, Cardinal(AX));
  SdlEventSetU32(Result, 20, Cardinal(AY));
  if AFlipped then
    SdlEventSetU32(Result, 24, SDL_MOUSEWHEEL_FLIPPED);
end;

function Translate(AMapper: TSdlInputMapper; const E: TSDLEvent): TArray<TTermEvent>;
var
  List: TList<TTermEvent>;
begin
  List := TList<TTermEvent>.Create;
  try
    AMapper.Translate(E, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function NewMapper: TSdlInputMapper;
begin
  Result := TSdlInputMapper.Create;
  Result.SetCellSize(8, 16);
end;

procedure TTestSdlInput.NamedKeysAreKeysWithTheirModifiers;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, KeyDown(13, 40, 0));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(tekKey), Integer(Ev[0].Kind));
    Assert.AreEqual(Integer(vkReturn), Integer(Ev[0].Key));
    Assert.AreEqual(#0, Ev[0].KeyChar);
    Ev := Translate(M, KeyDown(27, 41, 0));
    Assert.AreEqual(Integer(vkEscape), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(8, 42, 0));
    Assert.AreEqual(Integer(vkBack), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(9, 43, KMOD_LSHIFT));
    Assert.AreEqual(Integer(vkTab), Integer(Ev[0].Key));
    Assert.IsTrue(ssShift in Ev[0].Shift, 'Shift+Tab');
    Ev := Translate(M, KeyDown(127, 76, KMOD_LCTRL));
    Assert.AreEqual(Integer(vkDelete), Integer(Ev[0].Key));
    Assert.IsTrue(ssCtrl in Ev[0].Shift);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.FunctionAndArrowKeysUseTheScancodeRange;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, KeyDown(cScancodeBit or 62, 62, 0));
    Assert.AreEqual(Integer(vkF5), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(cScancodeBit or 67, 67, 0));
    Assert.AreEqual(Integer(vkF10), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(cScancodeBit or 79, 79, KMOD_RSHIFT));
    Assert.AreEqual(Integer(vkRight), Integer(Ev[0].Key));
    Assert.IsTrue(ssShift in Ev[0].Shift);
    Ev := Translate(M, KeyDown(cScancodeBit or 82, 82, 0));
    Assert.AreEqual(Integer(vkUp), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(cScancodeBit or 74, 74, 0));
    Assert.AreEqual(Integer(vkHome), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(cScancodeBit or 78, 78, 0));
    Assert.AreEqual(Integer(vkNext), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(cScancodeBit or 73, 73, 0));
    Assert.AreEqual(Integer(vkInsert), Integer(Ev[0].Key));
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.TypingWaitsForTheTextEvent;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Assert.AreEqual(0, Integer(Length(Translate(M, KeyDown(Ord('a'), 4, 0)))),
      'a letter key alone says nothing');
    Ev := Translate(M, TextInput('a'));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(Ord('A')), Integer(Ev[0].Key), 'the key code of the letter');
    Assert.AreEqual('a', Ev[0].KeyChar);
    Assert.IsTrue(Ev[0].Shift = []);
    Ev := Translate(M, TextInput(' '));
    Assert.AreEqual(Integer(vkSpace), Integer(Ev[0].Key));
    Assert.AreEqual(' ', Ev[0].KeyChar);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.TypedUpperCaseCarriesShift;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, TextInput('Q'));
    Assert.AreEqual(Integer(Ord('Q')), Integer(Ev[0].Key));
    Assert.IsTrue(ssShift in Ev[0].Shift);
    Ev := Translate(M, TextInput('!'));
    Assert.AreEqual('!', Ev[0].KeyChar);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.NonLatinTextHasNoKeyCode;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, TextInput(#$0416#$0443));
    Assert.AreEqual(2, Integer(Length(Ev)), 'one event per character');
    Assert.AreEqual(Integer(0), Integer(Ev[0].Key));
    Assert.AreEqual(#$0416, Ev[0].KeyChar);
    Assert.AreEqual(#$0443, Ev[1].KeyChar);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.ChordUsesThePhysicalKeyInAnyLayout;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    // Ctrl+C on a Russian layout: the symbol is the Cyrillic letter, the
    // scancode is still that of the C key.
    Ev := Translate(M, KeyDown($0441, 6, KMOD_LCTRL));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(Ord('C')), Integer(Ev[0].Key));
    Assert.IsTrue(ssCtrl in Ev[0].Shift);
    Assert.AreEqual(#0, Ev[0].KeyChar);
    Ev := Translate(M, KeyDown(Ord('z'), 29, KMOD_LCTRL or KMOD_LSHIFT));
    Assert.AreEqual(Integer(Ord('Z')), Integer(Ev[0].Key));
    Assert.IsTrue(Ev[0].Shift = [ssCtrl, ssShift]);
    Ev := Translate(M, KeyDown(Ord('5'), 34, KMOD_RCTRL));
    Assert.AreEqual(Integer(Ord('5')), Integer(Ev[0].Key));
    Ev := Translate(M, KeyDown(32, 44, KMOD_LCTRL));
    Assert.AreEqual(Integer(vkSpace), Integer(Ev[0].Key), 'Ctrl+Space');
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.AltChordIsAKey;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, KeyDown(Ord('f'), 9, KMOD_LALT));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(Ord('F')), Integer(Ev[0].Key));
    Assert.IsTrue(Ev[0].Shift = [ssAlt]);
    Ev := Translate(M, KeyDown(cScancodeBit or 59, 59, KMOD_LALT));
    Assert.AreEqual(Integer(vkF2), Integer(Ev[0].Key));
    Assert.IsTrue(ssAlt in Ev[0].Shift);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.AltGrTextIsNotAChord;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Assert.AreEqual(0, Integer(Length(Translate(M, KeyDown(Ord('q'), 20, KMOD_MODE)))));
    M.Mods := KMOD_MODE;
    Ev := Translate(M, TextInput('@'));
    Assert.AreEqual(1, Integer(Length(Ev)), 'the character that AltGr types');
    Assert.AreEqual('@', Ev[0].KeyChar);
    // Left Ctrl with right Alt is how some systems report AltGr.
    Assert.AreEqual(0, Integer(Length(Translate(M, KeyDown(Ord('q'), 20, KMOD_LCTRL or KMOD_RALT)))));
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.ReleasingAModifierReportsWhatIsStillHeld;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    // Left Alt released while Left Ctrl stays down; the mask may or may not
    // still carry the released key.
    Ev := Translate(M, KeyUp(226, KMOD_LCTRL or KMOD_LALT));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Ord(tekModifiers), Ord(Ev[0].Kind));
    Assert.IsTrue(Ev[0].Shift = [ssCtrl], 'ctrl is still held');
    Ev := Translate(M, KeyUp(226, KMOD_LCTRL));
    Assert.IsTrue(Ev[0].Shift = [ssCtrl], 'a mask without the key gives the same');
    Ev := Translate(M, KeyUp(224, KMOD_LCTRL));
    Assert.IsTrue(Ev[0].Shift = [], 'nothing held after the last release');
    // Releasing an ordinary key says nothing.
    Assert.AreEqual(0, Integer(Length(Translate(M, KeyUp(4, 0)))));
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.TextWithControlHeldIsDropped;
var
  M: TSdlInputMapper;
begin
  M := NewMapper;
  try
    Translate(M, KeyDown(Ord('a'), 4, KMOD_LCTRL));
    Assert.AreEqual(0, Integer(Length(Translate(M, TextInput('a')))),
      'the chord was reported by its key press');
    Translate(M, KeyDown(Ord('a'), 4, KMOD_LALT));
    Assert.AreEqual(0, Integer(Length(Translate(M, TextInput('a')))));
    Translate(M, KeyDown(Ord('a'), 4, 0));
    Assert.AreEqual(1, Integer(Length(Translate(M, TextInput('a')))));
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.KeypadFollowsNumLock;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, KeyDown(cScancodeBit or 88, 88, 0));
    Assert.AreEqual(Integer(vkReturn), Integer(Ev[0].Key), 'keypad Enter');
    Ev := Translate(M, KeyDown(cScancodeBit or 96, 96, 0));
    Assert.AreEqual(Integer(vkUp), Integer(Ev[0].Key), 'keypad 8 moves the cursor without Num Lock');
    Assert.AreEqual(0, Integer(Length(Translate(M, KeyDown(cScancodeBit or 96, 96, KMOD_NUM)))),
      'with Num Lock it types a digit through the text event');
    Ev := Translate(M, KeyDown(cScancodeBit or 99, 99, 0));
    Assert.AreEqual(Integer(vkDelete), Integer(Ev[0].Key));
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.MouseMotionReportsCellChangesOnly;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, Motion(17, 33));
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(tekMouse), Integer(Ev[0].Kind));
    Assert.AreEqual(Integer(tmaMove), Integer(Ev[0].MouseAction));
    Assert.AreEqual(2, Ev[0].Col);
    Assert.AreEqual(2, Ev[0].Row);
    Assert.AreEqual(0, Integer(Length(Translate(M, Motion(20, 40)))), 'same cell');
    Assert.AreEqual(1, Integer(Length(Translate(M, Motion(24, 40)))), 'next column');
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.PixelScaleMapsHighDpiPositions;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    M.SetPixelScale(2);
    Ev := Translate(M, Motion(9, 17));
    Assert.AreEqual(2, Ev[0].Col, 'window unit 9 is pixel 18');
    Assert.AreEqual(2, Ev[0].Row);
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.ButtonsMapToMouseButtons;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    M.Mods := KMOD_LSHIFT;
    Ev := Translate(M, Button(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 8, 16));
    Assert.AreEqual(Integer(tmaPress), Integer(Ev[0].MouseAction));
    Assert.AreEqual(Integer(TMouseButton.mbLeft), Integer(Ev[0].Button));
    Assert.AreEqual(1, Ev[0].Col);
    Assert.AreEqual(1, Ev[0].Row);
    Assert.IsTrue(ssShift in Ev[0].Shift);
    Ev := Translate(M, Button(SDL_MOUSEBUTTONUP, SDL_BUTTON_RIGHT, 8, 16));
    Assert.AreEqual(Integer(tmaRelease), Integer(Ev[0].MouseAction));
    Assert.AreEqual(Integer(TMouseButton.mbRight), Integer(Ev[0].Button));
    Ev := Translate(M, Button(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_MIDDLE, 0, 0));
    Assert.AreEqual(Integer(TMouseButton.mbMiddle), Integer(Ev[0].Button));
    Assert.AreEqual(0, Integer(Length(Translate(M, Button(SDL_MOUSEBUTTONDOWN, 4, 0, 0)))),
      'side buttons are not used');
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.WheelSendsOneEventPerStep;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Translate(M, Motion(40, 48));
    Ev := Translate(M, Wheel(0, 3));
    Assert.AreEqual(3, Integer(Length(Ev)));
    Assert.AreEqual(Integer(tmaWheelUp), Integer(Ev[0].MouseAction));
    Assert.AreEqual(5, Ev[0].Col, 'the wheel acts where the pointer is');
    Assert.AreEqual(3, Ev[0].Row);
    Ev := Translate(M, Wheel(0, -1));
    Assert.AreEqual(Integer(tmaWheelDown), Integer(Ev[0].MouseAction));
    Ev := Translate(M, Wheel(2, 0));
    Assert.AreEqual(Integer(tmaWheelRight), Integer(Ev[0].MouseAction));
    Ev := Translate(M, Wheel(-1, 0));
    Assert.AreEqual(Integer(tmaWheelLeft), Integer(Ev[0].MouseAction));
    Assert.AreEqual(10, Integer(Length(Translate(M, Wheel(0, 500)))), 'a burst is capped');
  finally
    M.Free;
  end;
end;

procedure TTestSdlInput.FlippedWheelReverses;
var
  M: TSdlInputMapper;
  Ev: TArray<TTermEvent>;
begin
  M := NewMapper;
  try
    Ev := Translate(M, Wheel(0, 1, True));
    Assert.AreEqual(Integer(tmaWheelDown), Integer(Ev[0].MouseAction));
  finally
    M.Free;
  end;
end;

procedure NoFree(AMemory: Pointer);
begin
end;

procedure TTestSdlInput.DroppedFileIsPastedAsPath;
var
  M: TSdlInputMapper;
  E: TSDLEvent;
  Ev: TArray<TTermEvent>;
  Name: UTF8String;
  Address: NativeUInt;
  I: Integer;
begin
  M := NewMapper;
  SdlDropFree := NoFree;
  try
    E := Default(TSDLEvent);
    SdlEventSetU32(E, 0, SDL_DROPFILE);
    Name := UTF8String('/tmp/my file.txt');
    Address := NativeUInt(PAnsiChar(Name));
    for I := 0 to 7 do
      E.Raw[8 + I] := Byte(Address shr (8 * I));
    Ev := Translate(M, E);
    Assert.AreEqual(1, Integer(Length(Ev)));
    Assert.AreEqual(Integer(tekPaste), Integer(Ev[0].Kind));
    Assert.AreEqual('"/tmp/my file.txt"', Ev[0].Text, 'a name with a space is quoted');
    Name := UTF8String('/tmp/plain.txt');
    Address := NativeUInt(PAnsiChar(Name));
    for I := 0 to 7 do
      E.Raw[8 + I] := Byte(Address shr (8 * I));
    Ev := Translate(M, E);
    Assert.AreEqual('/tmp/plain.txt', Ev[0].Text);
  finally
    SdlDropFree := nil;
    M.Free;
  end;
end;

procedure TTestSdlInput.ModifierMaskBecomesShiftState;
begin
  Assert.IsTrue(SdlModsToShift(0) = []);
  Assert.IsTrue(SdlModsToShift(KMOD_LSHIFT) = [ssShift]);
  Assert.IsTrue(SdlModsToShift(KMOD_RCTRL or KMOD_LALT) = [ssCtrl, ssAlt]);
  Assert.IsTrue(SdlModsToShift(KMOD_MODE or KMOD_LSHIFT) = [ssShift], 'AltGr is not Alt');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSdlInput);

end.
