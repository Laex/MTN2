unit uPluginInputChord;

{ Keystrokes as plugins write them: "F5", "Ctrl+Shift+K", "a", "Alt+Enter".
  A plugin sends such a chord to the focused window (SendKey) and is told the
  chords the user types (the "input.key" event); this unit turns one form into
  the other. }

interface

uses
  System.SysUtils, System.Classes;

/// <summary>Splits AChord into the (Key, KeyChar, Shift) triple a window's
/// HandleInput takes. A single character is typed as that character; a chord
/// without Ctrl and Alt on a letter, digit or Space also carries its character.
/// False for text that is no key.</summary>
function TryParseInputChord(const AChord: string; out AKey: Word; out AKeyChar: Char;
  out AShift: TShiftState): Boolean;

/// <summary>The chord text of a keystroke, the inverse of TryParseInputChord: the
/// character itself for printable text without Ctrl and Alt, else "Ctrl+Alt+Shift+Name".
/// '' when the keystroke names nothing (a modifier alone).</summary>
function InputChordText(AKey: Word; AKeyChar: Char; AShift: TShiftState): string;

/// <summary>The keymap spelling of a keystroke ("Ctrl+Shift+F5"); '' for a modifier
/// alone. Unlike InputChordText a printable key keeps its key name ("A", "Shift+A"),
/// which is what TryParseKeyCombo reads back.</summary>
function KeystrokeBindingText(AKey: Word; AKeyChar: Char; AShift: TShiftState): string;

/// <summary>The first chord bound to the keymap action AName ("Copy"), as chord text;
/// '' when the name is unknown or the action has no key.</summary>
function ActionChordText(const AName: string): string;

/// <summary>What already owns the chord AChord: the display name of the keymap
/// action bound to it, else the id of the plugin command bound to it; '' when
/// the chord is free or is no key.</summary>
function ChordOwnerName(const AChord: string): string;

implementation

uses
  System.UITypes, uKeymap, uKeymapRegistry, uCommandRegistry;

function IsCharKey(AVk: Word): Boolean;
begin
  Result := ((AVk >= Ord('A')) and (AVk <= Ord('Z'))) or
    ((AVk >= Ord('0')) and (AVk <= Ord('9'))) or (AVk = vkSpace);
end;

function TryParseInputChord(const AChord: string; out AKey: Word; out AKeyChar: Char;
  out AShift: TShiftState): Boolean;
var
  Binding: TKeyBinding;
begin
  AKey := 0;
  AKeyChar := #0;
  AShift := [];
  Result := False;
  if AChord = '' then
    Exit;
  if (Length(AChord) = 1) and (AChord[1] > ' ') then
  begin
    AKeyChar := AChord[1];
    AKey := KeymapLookupKey(0, AKeyChar);
    if AKeyChar <> LowerCase(AKeyChar) then
      AShift := [ssShift];
    Exit(True);
  end;
  if not TryParseKeyCombo(AChord, Binding) then
    Exit;
  AKey := Binding.Key;
  if Binding.Ctrl then
    Include(AShift, ssCtrl);
  if Binding.Alt then
    Include(AShift, ssAlt);
  if Binding.Shift then
    Include(AShift, ssShift);
  if (AShift * [ssCtrl, ssAlt] = []) and IsCharKey(AKey) then
  begin
    if AKey = vkSpace then
      AKeyChar := ' '
    else if (AKey >= Ord('A')) and (AKey <= Ord('Z')) and not (ssShift in AShift) then
      AKeyChar := Chr(AKey + 32)
    else
      AKeyChar := Chr(AKey);
  end;
  Result := True;
end;

function InputChordText(AKey: Word; AKeyChar: Char; AShift: TShiftState): string;
var
  Vk: Word;
begin
  Result := '';
  if (AShift * [ssCtrl, ssAlt] = []) and (AKeyChar > ' ') then
    Exit(AKeyChar);
  Vk := KeymapLookupKey(AKey, AKeyChar);
  if (Vk = 0) or (Vk = vkShift) or (Vk = vkControl) or (Vk = vkMenu) then
    Exit;
  Result := KeyBindingToStr(KeyBinding(Vk, ssShift in AShift, ssAlt in AShift,
    ssCtrl in AShift));
end;

function KeystrokeBindingText(AKey: Word; AKeyChar: Char; AShift: TShiftState): string;
var
  Vk: Word;
begin
  Result := '';
  Vk := KeymapLookupKey(AKey, AKeyChar);
  if (Vk = 0) or (Vk = vkShift) or (Vk = vkControl) or (Vk = vkMenu) then
    Exit;
  Result := KeyBindingToStr(KeyBinding(Vk, ssShift in AShift, ssAlt in AShift,
    ssCtrl in AShift));
end;

function ActionChordText(const AName: string): string;
var
  Act: TKeymapAction;
  Bindings: TArray<TKeyBinding>;
begin
  Result := '';
  if not TryKeymapActionByName(AName, Act) then
    Exit;
  Bindings := ActiveKeymap.Bindings[Act];
  if Length(Bindings) > 0 then
    Result := KeyBindingToStr(Bindings[0]);
end;

function ChordOwnerName(const AChord: string): string;
var
  Key: Word;
  KeyChar: Char;
  Shift: TShiftState;
  Binding: TKeyBinding;
  Act: TKeymapAction;
  I: Integer;
  CommandId: string;
begin
  Result := '';
  if not TryParseInputChord(AChord, Key, KeyChar, Shift) then
    Exit;
  Binding := KeyBinding(Key, ssShift in Shift, ssAlt in Shift, ssCtrl in Shift);
  for Act := Succ(Low(TKeymapAction)) to High(TKeymapAction) do
    for I := 0 to High(ActiveKeymap.Bindings[Act]) do
      if SameKeyBinding(Binding, ActiveKeymap.Bindings[Act][I]) then
        Exit(KeymapActionDisplayName(Act));
  if CommandRegistry.TryMatchBinding(Key, Shift, CommandId) then
    Result := CommandId;
end;

end.
