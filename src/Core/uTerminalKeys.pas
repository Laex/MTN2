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

/// <summary>A bare navigation key (arrows, Home/End, PgUp/PgDn, Insert,
/// Delete, with or without Shift) stays with the window - scrolls, selects,
/// edits the input line - rather than going to the console. That holds only
/// at a shell prompt: while AProgramRunning (a full-screen or console
/// program is up) the program gets them.</summary>
function WindowKeepsNavKey(AKey: Word; AShift: TShiftState;
  AProgramRunning: Boolean): Boolean;

/// <summary>The report of a mouse event for a program that asked for mouse
/// input. ABase: 0 left, 1 middle, 2 right, 3 no button, 64..67 wheel up,
/// down, left, right. ACol and ARow are one-based. ASgr selects ESC[&lt;b;x;yM
/// (m on release); otherwise the legacy ESC[M form, which cannot address a
/// cell beyond 223 (False is returned then).</summary>
function EncodeMouseReport(ABase: Integer; AShift: TShiftState; AMotion,
  ARelease, ASgr: Boolean; ACol, ARow: Integer; out AReport: string): Boolean;

implementation

uses
  System.SysUtils;

function EncodeMouseReport(ABase: Integer; AShift: TShiftState; AMotion,
  ARelease, ASgr: Boolean; ACol, ARow: Integer; out AReport: string): Boolean;
var
  Code: Integer;
  Final: Char;
begin
  AReport := '';
  Code := ABase;
  if ssShift in AShift then
    Inc(Code, 4);
  if ssAlt in AShift then
    Inc(Code, 8);
  if ssCtrl in AShift then
    Inc(Code, 16);
  if AMotion then
    Inc(Code, 32);
  if ASgr then
  begin
    if ARelease then
      Final := 'm'
    else
      Final := 'M';
    AReport := #27'[<' + IntToStr(Code) + ';' + IntToStr(ACol) + ';' +
      IntToStr(ARow) + Final;
    Exit(True);
  end;
  if (ACol > 223) or (ARow > 223) then
    Exit(False);
  if ARelease then
    Code := (Code and not 3) or 3;
  AReport := #27'[M' + Char(32 + Code) + Char(32 + ACol) + Char(32 + ARow);
  Result := True;
end;

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

function WindowKeepsNavKey(AKey: Word; AShift: TShiftState;
  AProgramRunning: Boolean): Boolean;
begin
  Result := not AProgramRunning and ([ssCtrl, ssAlt] * AShift = []) and
    (AKey in [vkUp, vkDown, vkLeft, vkRight, vkPrior, vkNext, vkHome, vkEnd,
      vkInsert, vkDelete]);
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
