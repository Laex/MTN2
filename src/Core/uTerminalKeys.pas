unit uTerminalKeys;

{ Keys a full-screen program running in a console receives: xterm byte
  sequences for function, cursor and editing keys with Shift / Alt / Ctrl,
  Alt+character as ESC + character and Ctrl+letter as a control code. }

interface

uses
  System.Classes, System.UITypes;

/// <summary>The bytes the key sends. False for a key with no sequence of its
/// own (plain characters, Enter, Backspace, Esc): the caller handles those.
/// AAppCursor: the program set DECCKM (ESC[?1h), so unmodified arrows and
/// Home/End use ESC O x instead of ESC [ x.</summary>
function EncodeTerminalKey(AKey: Word; AShift: TShiftState; AKeyChar: Char;
  AAppCursor: Boolean; out ASeq: string): Boolean;

implementation

uses
  System.SysUtils;

/// <summary>xterm modifier parameter: 1 + Shift(1) + Alt(2) + Ctrl(4).</summary>
function ModParam(AShift: TShiftState): Integer;
begin
  Result := 1;
  if ssShift in AShift then
    Inc(Result, 1);
  if ssAlt in AShift then
    Inc(Result, 2);
  if ssCtrl in AShift then
    Inc(Result, 4);
end;

function CsiTilde(ACode: Integer; AMod: Integer): string;
begin
  if AMod > 1 then
    Result := #27'[' + IntToStr(ACode) + ';' + IntToStr(AMod) + '~'
  else
    Result := #27'[' + IntToStr(ACode) + '~';
end;

function CsiLetter(AFinal: Char; AMod: Integer; AAppCursor: Boolean): string;
begin
  if AMod > 1 then
    Result := #27'[1;' + IntToStr(AMod) + AFinal
  else if AAppCursor then
    Result := #27'O' + AFinal
  else
    Result := #27'[' + AFinal;
end;

function FunctionKeySeq(AKey: Word; AMod: Integer): string;
begin
  Result := '';
  case AKey of
    vkF1..vkF4:
      begin
        // F1-F4: SS3 P..S, CSI 1;m P..S with modifiers.
        if AMod > 1 then
          Result := #27'[1;' + IntToStr(AMod) + Char(Ord('P') + AKey - vkF1)
        else
          Result := #27'O' + Char(Ord('P') + AKey - vkF1);
      end;
    vkF5:  Result := CsiTilde(15, AMod);
    vkF6:  Result := CsiTilde(17, AMod);
    vkF7:  Result := CsiTilde(18, AMod);
    vkF8:  Result := CsiTilde(19, AMod);
    vkF9:  Result := CsiTilde(20, AMod);
    vkF10: Result := CsiTilde(21, AMod);
    vkF11: Result := CsiTilde(23, AMod);
    vkF12: Result := CsiTilde(24, AMod);
  end;
end;

function EncodeTerminalKey(AKey: Word; AShift: TShiftState; AKeyChar: Char;
  AAppCursor: Boolean; out ASeq: string): Boolean;
var
  M: Integer;
  Ch: Char;
begin
  ASeq := '';
  M := ModParam(AShift - [ssLeft, ssRight, ssMiddle, ssDouble]);
  case AKey of
    vkF1..vkF12:  ASeq := FunctionKeySeq(AKey, M);
    vkUp:         ASeq := CsiLetter('A', M, AAppCursor);
    vkDown:       ASeq := CsiLetter('B', M, AAppCursor);
    vkRight:      ASeq := CsiLetter('C', M, AAppCursor);
    vkLeft:       ASeq := CsiLetter('D', M, AAppCursor);
    vkHome:       ASeq := CsiLetter('H', M, AAppCursor);
    vkEnd:        ASeq := CsiLetter('F', M, AAppCursor);
    vkInsert:     ASeq := CsiTilde(2, M);
    vkDelete:     ASeq := CsiTilde(3, M);
    vkPrior:      ASeq := CsiTilde(5, M);
    vkNext:       ASeq := CsiTilde(6, M);
    vkTab:
      if ssShift in AShift then
        ASeq := #27'[Z';
    vkReturn:
      if ssAlt in AShift then
        ASeq := #27#13;
  end;
  if ASeq <> '' then
    Exit(True);

  // Ctrl+letter is a control code whatever the keyboard layout types; Alt
  // prefixes it (and any other character) with ESC.
  if (ssCtrl in AShift) and (AKey >= vkA) and (AKey <= vkZ) then
  begin
    ASeq := Char(AKey - vkA + 1);
    if ssAlt in AShift then
      ASeq := #27 + ASeq;
    Exit(True);
  end;
  if (ssCtrl in AShift) and (AKey = vkSpace) then
  begin
    ASeq := #0;
    if ssAlt in AShift then
      ASeq := #27 + ASeq;
    Exit(True);
  end;
  if (ssAlt in AShift) and not (ssCtrl in AShift) then
  begin
    Ch := AKeyChar;
    if Ch < ' ' then
    begin
      if (AKey >= vkA) and (AKey <= vkZ) then
      begin
        if ssShift in AShift then
          Ch := Char(AKey)
        else
          Ch := Char(Ord('a') + AKey - vkA);
      end
      else if (AKey >= vk0) and (AKey <= vk9) then
        Ch := Char(AKey)
      else if AKey = vkSpace then
        Ch := ' '
      else
        Ch := #0;
    end;
    if Ch >= ' ' then
    begin
      ASeq := #27 + Ch;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
