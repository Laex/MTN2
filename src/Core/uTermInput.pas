unit uTermInput;

{ Decoder of the byte stream a text terminal sends for the keyboard and mouse:
  plain UTF-8 text, control characters, the legacy escape sequences of the
  cursor and function keys, the kitty keyboard protocol (CSI u), xterm
  modifyOtherKeys, SGR mouse reports and bracketed paste. The result is the
  same (virtual key, character, shift state) triple the windows get from the
  GUI toolkit, so one set of key bindings serves both.

  The decoder is a pure function of the bytes fed to it. A lone ESC cannot be
  told from the start of a sequence until more bytes arrive; FlushPending
  turns it into an Escape key once the caller has waited long enough. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections;

type
  TTermEventKind = (tekKey, tekMouse, tekPaste, tekCapabilities, tekFocus);

  TTermMouseAction = (tmaPress, tmaRelease, tmaMove, tmaWheelUp, tmaWheelDown,
    tmaWheelLeft, tmaWheelRight);

  TTermEvent = record
    Kind: TTermEventKind;
    /// <summary>tekKey: virtual key code (0 for a character without one).</summary>
    Key: Word;
    /// <summary>tekKey: the typed character, #0 for a chord.</summary>
    KeyChar: Char;
    /// <summary>tekKey, tekMouse: Shift, Alt, Ctrl held.</summary>
    Shift: TShiftState;
    /// <summary>tekMouse: zero-based cell.</summary>
    Col: Integer;
    Row: Integer;
    Button: TMouseButton;
    MouseAction: TTermMouseAction;
    /// <summary>tekPaste: the pasted text.</summary>
    Text: string;
    /// <summary>tekCapabilities: the terminal answered the kitty keyboard
    /// query (True) or only the device attributes query (False).</summary>
    KittyKeyboard: Boolean;
    /// <summary>tekFocus: the terminal window gained (True) or lost focus.</summary>
    FocusGained: Boolean;
  end;

  TTermInputParser = class
  private
    FBuf: TBytes;
    FLen: Integer;
    FInPaste: Boolean;
    FPaste: string;
    procedure Emit(const AEvents: TList<TTermEvent>; const AEvent: TTermEvent);
    procedure EmitKey(const AEvents: TList<TTermEvent>; AKey: Word; AChar: Char;
      AShift: TShiftState);
    procedure EmitChar(const AEvents: TList<TTermEvent>; ACodePoint: Integer;
      AShift: TShiftState);
    function ParseOne(const AEvents: TList<TTermEvent>): Boolean;
    function ParseEscape(const AEvents: TList<TTermEvent>): Boolean;
    function ParseCsi(const AEvents: TList<TTermEvent>; AStart: Integer): Boolean;
    function ParseSs3(const AEvents: TList<TTermEvent>): Boolean;
    function ParseMouse(const AEvents: TList<TTermEvent>; const AParams: string;
      AFinal: Byte): Boolean;
    procedure HandleCsi(const AEvents: TList<TTermEvent>; const AParams: string;
      AFinal: Byte);
    procedure Consume(ACount: Integer);
  public
    /// <summary>Appends AData and decodes every complete event into AEvents;
    /// an incomplete tail stays buffered.</summary>
    procedure Feed(const AData: TBytes; ACount: Integer; const AEvents: TList<TTermEvent>);
    /// <summary>Decodes bytes that are held back only because more might
    /// follow: a lone ESC becomes the Escape key.</summary>
    procedure FlushPending(const AEvents: TList<TTermEvent>);
    /// <summary>True while buffered bytes wait for more input.</summary>
    function HasPending: Boolean;
  end;

/// <summary>The virtual key and shift state of a typed character, as the GUI
/// toolkit reports it: letters and digits carry their key code (an upper-case
/// letter also Shift), punctuation the OEM key code.</summary>
procedure CharToKey(ACh: Char; out AKey: Word; out AShift: TShiftState);

/// <summary>Virtual key of a legacy "CSI n ~" function key number, 0 if unknown.</summary>
function TildeKeyToVk(ANumber: Integer): Word;

implementation

uses
  System.Math;

const
  cEsc = 27;

procedure CharToKey(ACh: Char; out AKey: Word; out AShift: TShiftState);
begin
  AShift := [];
  AKey := 0;
  case ACh of
    'a'..'z':
      AKey := Ord(ACh) - 32;
    'A'..'Z':
      begin
        AKey := Ord(ACh);
        AShift := [ssShift];
      end;
    '0'..'9':
      AKey := Ord(ACh);
    ' ':
      AKey := vkSpace;
    '+':
      AKey := vkAdd;
    '-':
      AKey := vkSubtract;
    '*':
      AKey := vkMultiply;
    '/':
      AKey := vkSlash;
    ',':
      AKey := vkComma;
    '.':
      AKey := vkPeriod;
    ';':
      AKey := vkSemicolon;
    '=':
      AKey := 187;
    '`':
      AKey := 192;
    '[':
      AKey := 219;
    '\':
      AKey := vkBackSlash;
    ']':
      AKey := 221;
    '''':
      AKey := 222;
  end;
end;

function TildeKeyToVk(ANumber: Integer): Word;
begin
  case ANumber of
    1, 7: Result := vkHome;
    2: Result := vkInsert;
    3: Result := vkDelete;
    4, 8: Result := vkEnd;
    5: Result := vkPrior;
    6: Result := vkNext;
    11: Result := vkF1;
    12: Result := vkF2;
    13: Result := vkF3;
    14: Result := vkF4;
    15: Result := vkF5;
    17: Result := vkF6;
    18: Result := vkF7;
    19: Result := vkF8;
    20: Result := vkF9;
    21: Result := vkF10;
    23: Result := vkF11;
    24: Result := vkF12;
  else
    Result := 0;
  end;
end;

// F13..F20 as the VT220 and PuTTY sequences carry them: a terminal that cannot
// report modifiers on function keys sends Shift+F3..Shift+F10 this way
// (Shift+F1 and Shift+F2 arrive as F11 and F12).
function ShiftedTildeKeyToVk(ANumber: Integer): Word;
begin
  case ANumber of
    25: Result := vkF3;
    26: Result := vkF4;
    28: Result := vkF5;
    29: Result := vkF6;
    31: Result := vkF7;
    32: Result := vkF8;
    33: Result := vkF9;
    34: Result := vkF10;
  else
    Result := 0;
  end;
end;

// Shift, Alt, Ctrl of an xterm / kitty modifier parameter (value - 1 is a mask).
function ModsOf(AParam: Integer): TShiftState;
var
  M: Integer;
begin
  Result := [];
  if AParam <= 1 then
    Exit;
  M := AParam - 1;
  if (M and 1) <> 0 then
    Include(Result, ssShift);
  if (M and 2) <> 0 then
    Include(Result, ssAlt);
  if (M and 4) <> 0 then
    Include(Result, ssCtrl);
end;

function SplitInts(const AText: string): TArray<Integer>;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if AText = '' then
    Exit(nil);
  Parts := AText.Split([';']);
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do
    Result[I] := StrToIntDef(Parts[I].Split([':'])[0], 0);
end;

function ParamAt(const AParams: TArray<Integer>; AIndex, ADefault: Integer): Integer;
begin
  if (AIndex < Length(AParams)) and (AParams[AIndex] <> 0) then
    Result := AParams[AIndex]
  else
    Result := ADefault;
end;

{ TTermInputParser }

procedure TTermInputParser.Emit(const AEvents: TList<TTermEvent>;
  const AEvent: TTermEvent);
begin
  AEvents.Add(AEvent);
end;

procedure TTermInputParser.EmitKey(const AEvents: TList<TTermEvent>; AKey: Word;
  AChar: Char; AShift: TShiftState);
var
  E: TTermEvent;
begin
  E := Default(TTermEvent);
  E.Kind := tekKey;
  E.Key := AKey;
  E.KeyChar := AChar;
  E.Shift := AShift;
  Emit(AEvents, E);
end;

procedure TTermInputParser.EmitChar(const AEvents: TList<TTermEvent>;
  ACodePoint: Integer; AShift: TShiftState);
var
  Key: Word;
  Base: TShiftState;
  S: string;
  I: Integer;
begin
  if ACodePoint >= $10000 then
  begin
    // A character outside the BMP arrives as two UTF-16 units.
    SetLength(S, 2);
    Dec(ACodePoint, $10000);
    S[1] := Char($D800 + (ACodePoint shr 10));
    S[2] := Char($DC00 + (ACodePoint and $3FF));
    for I := 1 to 2 do
      EmitKey(AEvents, 0, S[I], AShift);
    Exit;
  end;
  CharToKey(Char(ACodePoint), Key, Base);
  EmitKey(AEvents, Key, Char(ACodePoint), AShift + Base);
end;

procedure TTermInputParser.Consume(ACount: Integer);
begin
  if ACount >= FLen then
    FLen := 0
  else
  begin
    Move(FBuf[ACount], FBuf[0], FLen - ACount);
    Dec(FLen, ACount);
  end;
end;

function TTermInputParser.HasPending: Boolean;
begin
  Result := FLen > 0;
end;

procedure TTermInputParser.Feed(const AData: TBytes; ACount: Integer;
  const AEvents: TList<TTermEvent>);
begin
  if ACount > 0 then
  begin
    if Length(FBuf) < FLen + ACount then
      SetLength(FBuf, Max(FLen + ACount, 256));
    Move(AData[0], FBuf[FLen], ACount);
    Inc(FLen, ACount);
  end;
  while (FLen > 0) and ParseOne(AEvents) do
    ;
end;

procedure TTermInputParser.FlushPending(const AEvents: TList<TTermEvent>);
begin
  if (FLen = 1) and (FBuf[0] = cEsc) then
  begin
    Consume(1);
    EmitKey(AEvents, vkEscape, #0, []);
  end
  else if FLen > 0 then
    // An unfinished sequence that never completes is dropped.
    FLen := 0;
end;

function TTermInputParser.ParseOne(const AEvents: TList<TTermEvent>): Boolean;
var
  B: Byte;
  Need, I, CP: Integer;
  PasteEvent: TTermEvent;
begin
  B := FBuf[0];
  if FInPaste then
  begin
    // Inside a bracketed paste everything up to ESC [ 201 ~ is text.
    for I := 0 to FLen - 6 do
      if (FBuf[I] = cEsc) and (FBuf[I + 1] = Ord('[')) and (FBuf[I + 2] = Ord('2')) and
         (FBuf[I + 3] = Ord('0')) and (FBuf[I + 4] = Ord('1')) and (FBuf[I + 5] = Ord('~')) then
      begin
        FPaste := FPaste + TEncoding.UTF8.GetString(FBuf, 0, I);
        Consume(I + 6);
        FInPaste := False;
        PasteEvent := Default(TTermEvent);
        PasteEvent.Kind := tekPaste;
        PasteEvent.Text := FPaste;
        FPaste := '';
        Emit(AEvents, PasteEvent);
        Exit(True);
      end;
    // Keep a possible partial terminator; the rest is text.
    if FLen > 6 then
    begin
      FPaste := FPaste + TEncoding.UTF8.GetString(FBuf, 0, FLen - 6);
      Consume(FLen - 6);
    end;
    Exit(False);
  end;

  if B = cEsc then
    Exit(ParseEscape(AEvents));

  if B < 32 then
  begin
    Consume(1);
    case B of
      0: EmitKey(AEvents, vkSpace, #0, [ssCtrl]);
      8, 127: EmitKey(AEvents, vkBack, #0, []);
      9: EmitKey(AEvents, vkTab, #0, []);
      10, 13: EmitKey(AEvents, vkReturn, #0, []);
      28: EmitKey(AEvents, vkBackSlash, #0, [ssCtrl]);
      29: EmitKey(AEvents, 221, #0, [ssCtrl]);
      30: EmitKey(AEvents, Ord('6'), #0, [ssCtrl, ssShift]);
      31: EmitKey(AEvents, vkSlash, #0, [ssCtrl]);
    else
      EmitKey(AEvents, Word(B + 64), #0, [ssCtrl]);
    end;
    Exit(True);
  end;
  if B = 127 then
  begin
    Consume(1);
    EmitKey(AEvents, vkBack, #0, []);
    Exit(True);
  end;
  if B < 128 then
  begin
    Consume(1);
    EmitChar(AEvents, B, []);
    Exit(True);
  end;

  // UTF-8 multi-byte sequence.
  if (B and $E0) = $C0 then
  begin
    Need := 2;
    CP := B and $1F;
  end
  else if (B and $F0) = $E0 then
  begin
    Need := 3;
    CP := B and $0F;
  end
  else if (B and $F8) = $F0 then
  begin
    Need := 4;
    CP := B and $07;
  end
  else
  begin
    Consume(1);
    Exit(True);
  end;
  if FLen < Need then
    Exit(False);
  for I := 1 to Need - 1 do
  begin
    if (FBuf[I] and $C0) <> $80 then
    begin
      Consume(I);
      Exit(True);
    end;
    CP := (CP shl 6) or (FBuf[I] and $3F);
  end;
  Consume(Need);
  EmitChar(AEvents, CP, []);
  Result := True;
end;

function TTermInputParser.ParseEscape(const AEvents: TList<TTermEvent>): Boolean;
var
  N: Byte;
  Key: Word;
  Sh: TShiftState;
begin
  if FLen < 2 then
    Exit(False);
  N := FBuf[1];
  if N = Ord('[') then
    Exit(ParseCsi(AEvents, 2));
  if N = Ord('O') then
    Exit(ParseSs3(AEvents));
  if N = cEsc then
  begin
    // ESC ESC: Alt+Escape, or a doubled ESC before a sequence.
    Consume(1);
    EmitKey(AEvents, vkEscape, #0, []);
    Exit(True);
  end;
  // ESC <key>: Alt+key.
  if (N < 32) or (N = 127) then
  begin
    Consume(2);
    case N of
      9: EmitKey(AEvents, vkTab, #0, [ssAlt]);
      10, 13: EmitKey(AEvents, vkReturn, #0, [ssAlt]);
      127, 8: EmitKey(AEvents, vkBack, #0, [ssAlt]);
    else
      EmitKey(AEvents, Word(N + 64), #0, [ssAlt, ssCtrl]);
    end;
    Exit(True);
  end;
  if N < 128 then
  begin
    Consume(2);
    CharToKey(Char(N), Key, Sh);
    EmitKey(AEvents, Key, #0, Sh + [ssAlt]);
    Exit(True);
  end;
  // ESC followed by a multi-byte character: the escape is a lone Escape key.
  Consume(1);
  EmitKey(AEvents, vkEscape, #0, []);
  Result := True;
end;

function TTermInputParser.ParseSs3(const AEvents: TList<TTermEvent>): Boolean;
var
  F: Byte;
  Key: Word;
begin
  if FLen < 3 then
    Exit(False);
  F := FBuf[2];
  Consume(3);
  Key := 0;
  case Char(F) of
    'A': Key := vkUp;
    'B': Key := vkDown;
    'C': Key := vkRight;
    'D': Key := vkLeft;
    'H': Key := vkHome;
    'F': Key := vkEnd;
    'P': Key := vkF1;
    'Q': Key := vkF2;
    'R': Key := vkF3;
    'S': Key := vkF4;
    'M': Key := vkReturn;
    'j': Key := vkMultiply;
    'k': Key := vkAdd;
    'm': Key := vkSubtract;
    'o': Key := vkDivide;
  end;
  if Key <> 0 then
    EmitKey(AEvents, Key, #0, []);
  Result := True;
end;

function TTermInputParser.ParseCsi(const AEvents: TList<TTermEvent>;
  AStart: Integer): Boolean;
var
  I: Integer;
  B: Byte;
  Params: string;
begin
  // Parameters and intermediates are 0x30..0x3F and 0x20..0x2F; a final byte
  // is 0x40..0x7E.
  I := AStart;
  while I < FLen do
  begin
    B := FBuf[I];
    if (B >= $40) and (B <= $7E) then
    begin
      Params := TEncoding.ASCII.GetString(FBuf, AStart, I - AStart);
      Consume(I + 1);
      HandleCsi(AEvents, Params, B);
      Exit(True);
    end;
    if (B < $20) or (B > $3F) then
    begin
      // Malformed: drop what was read.
      Consume(I);
      Exit(True);
    end;
    Inc(I);
  end;
  Result := False;
end;

function TTermInputParser.ParseMouse(const AEvents: TList<TTermEvent>;
  const AParams: string; AFinal: Byte): Boolean;
var
  P: TArray<Integer>;
  Code: Integer;
  E: TTermEvent;
begin
  Result := False;
  P := SplitInts(Copy(AParams, 2, MaxInt));
  if Length(P) < 3 then
    Exit;
  Code := P[0];
  E := Default(TTermEvent);
  E.Kind := tekMouse;
  E.Col := P[1] - 1;
  E.Row := P[2] - 1;
  if (Code and 4) <> 0 then
    Include(E.Shift, ssShift);
  if (Code and 8) <> 0 then
    Include(E.Shift, ssAlt);
  if (Code and 16) <> 0 then
    Include(E.Shift, ssCtrl);
  if (Code and 64) <> 0 then
  begin
    case Code and 3 of
      0: E.MouseAction := tmaWheelUp;
      1: E.MouseAction := tmaWheelDown;
      2: E.MouseAction := tmaWheelLeft;
    else
      E.MouseAction := tmaWheelRight;
    end;
  end
  else
  begin
    case Code and 3 of
      0: E.Button := TMouseButton.mbLeft;
      1: E.Button := TMouseButton.mbMiddle;
    else
      E.Button := TMouseButton.mbRight;
    end;
    if (Code and 32) <> 0 then
      E.MouseAction := tmaMove
    else if AFinal = Ord('m') then
      E.MouseAction := tmaRelease
    else
      E.MouseAction := tmaPress;
  end;
  Emit(AEvents, E);
  Result := True;
end;

procedure TTermInputParser.HandleCsi(const AEvents: TList<TTermEvent>;
  const AParams: string; AFinal: Byte);
var
  P: TArray<Integer>;
  Mods: TShiftState;
  Key: Word;
  E: TTermEvent;
  Fields: TArray<string>;
  Code, Base, ModParam, N: Integer;
  Ch: Char;
  Sh: TShiftState;
  Digits: string;
begin
  // Mouse report: CSI < b ; x ; y M|m
  if (Length(AParams) > 0) and (AParams[1] = '<') and ((AFinal = Ord('M')) or (AFinal = Ord('m'))) then
  begin
    ParseMouse(AEvents, AParams, AFinal);
    Exit;
  end;
  // Answer to the kitty keyboard query: CSI ? flags u ; to device attributes: CSI ? ... c
  if (Length(AParams) > 0) and (AParams[1] = '?') then
  begin
    if AFinal = Ord('u') then
    begin
      E := Default(TTermEvent);
      E.Kind := tekCapabilities;
      E.KittyKeyboard := True;
      Emit(AEvents, E);
    end
    else if AFinal = Ord('c') then
    begin
      E := Default(TTermEvent);
      E.Kind := tekCapabilities;
      Emit(AEvents, E);
    end;
    Exit;
  end;

  P := SplitInts(AParams);
  case Char(AFinal) of
    'I', 'O':
      if AParams = '' then
      begin
        E := Default(TTermEvent);
        E.Kind := tekFocus;
        E.FocusGained := AFinal = Ord('I');
        Emit(AEvents, E);
      end;
    'A', 'B', 'C', 'D', 'H', 'F', 'P', 'Q', 'R', 'S':
      begin
        Mods := ModsOf(ParamAt(P, 1, 1));
        case Char(AFinal) of
          'A': Key := vkUp;
          'B': Key := vkDown;
          'C': Key := vkRight;
          'D': Key := vkLeft;
          'H': Key := vkHome;
          'F': Key := vkEnd;
          'P': Key := vkF1;
          'Q': Key := vkF2;
          'R': Key := vkF3;
        else
          Key := vkF4;
        end;
        // CSI R without parameters is also a cursor position report.
        if (Char(AFinal) = 'R') and (Length(P) = 2) and (ParamAt(P, 0, 0) > 1) and
           (Pos(';', AParams) > 0) and (ParamAt(P, 1, 0) > 8) then
          Exit;
        EmitKey(AEvents, Key, #0, Mods);
      end;
    'Z':
      EmitKey(AEvents, vkTab, #0, [ssShift]);
    '~':
      begin
        N := ParamAt(P, 0, 0);
        if N = 200 then
        begin
          FInPaste := True;
          FPaste := '';
          Exit;
        end;
        if N = 27 then
        begin
          // xterm modifyOtherKeys: CSI 27 ; mods ; code ~
          Mods := ModsOf(ParamAt(P, 1, 1));
          Code := ParamAt(P, 2, 0);
          if Code > 0 then
          begin
            if Code = 13 then
              EmitKey(AEvents, vkReturn, #0, Mods)
            else if Code = 9 then
              EmitKey(AEvents, vkTab, #0, Mods)
            else if Code = 27 then
              EmitKey(AEvents, vkEscape, #0, Mods)
            else if Code = 127 then
              EmitKey(AEvents, vkBack, #0, Mods)
            else
            begin
              CharToKey(Char(Code), Key, Sh);
              if (ssCtrl in Mods) or (ssAlt in Mods) then
                EmitKey(AEvents, Key, #0, Mods + (Sh - [ssShift]))
              else
                EmitKey(AEvents, Key, Char(Code), Mods + Sh);
            end;
          end;
          Exit;
        end;
        Key := TildeKeyToVk(N);
        if Key <> 0 then
          EmitKey(AEvents, Key, #0, ModsOf(ParamAt(P, 1, 1)))
        else
        begin
          Key := ShiftedTildeKeyToVk(N);
          if Key <> 0 then
            EmitKey(AEvents, Key, #0, ModsOf(ParamAt(P, 1, 1)) + [ssShift]);
        end;
      end;
    'u':
      begin
        // Kitty keyboard protocol: CSI code[:shifted[:base]] ; mods[:event] ; text u
        Fields := AParams.Split([';']);
        Digits := Fields[0];
        Code := StrToIntDef(Digits.Split([':'])[0], 0);
        Base := Code;
        if Length(Digits.Split([':'])) >= 3 then
          Base := StrToIntDef(Digits.Split([':'])[2], Code);
        ModParam := 1;
        if Length(Fields) > 1 then
          ModParam := StrToIntDef(Fields[1].Split([':'])[0], 1);
        Mods := ModsOf(ModParam);
        case Code of
          13, 57414: EmitKey(AEvents, vkReturn, #0, Mods);
          9: EmitKey(AEvents, vkTab, #0, Mods);
          27: EmitKey(AEvents, vkEscape, #0, Mods);
          127: EmitKey(AEvents, vkBack, #0, Mods);
          32:
            if (Mods * [ssCtrl, ssAlt]) = [] then
              EmitKey(AEvents, vkSpace, ' ', Mods)
            else
              EmitKey(AEvents, vkSpace, #0, Mods);
          57399..57408: EmitKey(AEvents, Word(vkNumpad0 + Code - 57399), #0, Mods);
          57413: EmitKey(AEvents, vkAdd, #0, Mods);
          57412: EmitKey(AEvents, vkSubtract, #0, Mods);
          57411: EmitKey(AEvents, vkMultiply, #0, Mods);
          57410: EmitKey(AEvents, vkDivide, #0, Mods);
        else
          if (Code >= 32) and (Code < 57344) then
          begin
            // The key of the base layout decides the chord, so Ctrl+D works on
            // a Cyrillic layout too; the typed character is the code itself.
            CharToKey(Char(Base), Key, Sh);
            Ch := Char(Code);
            if (Mods * [ssCtrl, ssAlt]) <> [] then
              EmitKey(AEvents, Key, #0, Mods + (Sh - [ssShift]) * [ssShift])
            else
            begin
              if (Code <> Base) or (Key = 0) then
                CharToKey(Char(Code), Key, Sh);
              EmitKey(AEvents, Key, Ch, Mods + Sh);
            end;
          end;
        end;
      end;
  end;
end;

end.
