unit uKeyChord;

{ One keystroke as key handlers should test it.

  Commands match the physical key: the virtual key code (vkA..vkZ, vk0..vk9,
  vkF1, ...) plus the Shift/Ctrl/Alt modifiers, which keeps Ctrl+C working in
  any keyboard layout. Letter virtual keys are uppercase only -- the codes of
  lowercase letters are the numpad and F1..F11 keys (Ord('s') = vkF4,
  Ord('k') = vkAdd), so never compare a key code with a lowercase letter
  (TestKeyChord.TestNoLowercaseKeyCodes checks this).

  Text input (typing, quick search, layout-dependent answers like Y/Д) uses
  the typed character Ch instead.

  Modifier matching is explicit: Matches requires exactly the given
  modifiers; the *Any variants take ARequired modifiers that must be held and
  AOptional ones that may be. Anything else held makes the chord not match. }

interface

uses
  System.Classes, System.UITypes;

type
  TKeyChord = record
    Key: Word;
    Ch: Char;
    /// <summary>Shift/Ctrl/Alt only; mouse and other TShiftState flags dropped.</summary>
    Mods: TShiftState;
    class function Make(AKey: Word; AKeyChar: Char;
      AShift: TShiftState): TKeyChord; static;
    /// <summary>ARequired all held, nothing held outside ARequired + AOptional.</summary>
    function HasMods(const ARequired: TShiftState;
      const AOptional: TShiftState = []): Boolean;
    /// <summary>Key AKey with exactly AMods.</summary>
    function Matches(AKey: Word; const AMods: TShiftState = []): Boolean;
    function MatchesAny(AKey: Word; const ARequired,
      AOptional: TShiftState): Boolean;
    /// <summary>Letter command: virtual key Ord(AUpper), or -- when FMX
    /// reports the letter only as a typed character -- Ch equal to AUpper in
    /// either case. AUpper must be an uppercase Latin letter.</summary>
    function MatchesLetter(AUpper: Char; const ARequired: TShiftState;
      const AOptional: TShiftState = []): Boolean;
    /// <summary>Ch is a printable character (not a control char or DEL).</summary>
    function IsPrintable: Boolean;
  end;

const
  cKeyMods = [ssShift, ssCtrl, ssAlt];

/// <summary>Entry-point normalization, applied once before any handler sees
/// the key. Enter arrives as #13/#10, raw 13/10 or vkAccept depending on the
/// source; all become vkReturn (Tab is left alone). Right Alt on AltGr
/// layouts arrives as Ctrl+Alt (Windows adds a synthetic Left Ctrl): with
/// AAltGrDown, Enter drops the Ctrl so AltGr+Enter is Alt+Enter, not
/// Ctrl+Alt+Enter.</summary>
procedure NormalizeKeyInput(var AKey: Word; AKeyChar: Char;
  var AShift: TShiftState; AAltGrDown: Boolean);

implementation

class function TKeyChord.Make(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): TKeyChord;
begin
  Result.Key := AKey;
  Result.Ch := AKeyChar;
  Result.Mods := AShift * cKeyMods;
end;

function TKeyChord.HasMods(const ARequired, AOptional: TShiftState): Boolean;
begin
  Result := (Mods * ARequired = ARequired * cKeyMods) and
    (Mods - ARequired - AOptional = []);
end;

function TKeyChord.Matches(AKey: Word; const AMods: TShiftState): Boolean;
begin
  Result := (Key = AKey) and HasMods(AMods);
end;

function TKeyChord.MatchesAny(AKey: Word; const ARequired,
  AOptional: TShiftState): Boolean;
begin
  Result := (Key = AKey) and HasMods(ARequired, AOptional);
end;

function TKeyChord.MatchesLetter(AUpper: Char; const ARequired,
  AOptional: TShiftState): Boolean;
begin
  Result := HasMods(ARequired, AOptional) and
    ((Key = Ord(AUpper)) or (Ch = AUpper) or (Ord(Ch) = Ord(AUpper) + 32));
end;

function TKeyChord.IsPrintable: Boolean;
begin
  Result := (Ch >= ' ') and (Ch <> #127);
end;

procedure NormalizeKeyInput(var AKey: Word; AKeyChar: Char;
  var AShift: TShiftState; AAltGrDown: Boolean);
begin
  if AKey = vkTab then
    Exit;
  if (AKeyChar = #13) or (AKeyChar = #10) or (AKey = 10) or (AKey = vkAccept) then
    AKey := vkReturn;
  if (AKey = vkReturn) and AAltGrDown then
    Exclude(AShift, ssCtrl);
end;

end.
