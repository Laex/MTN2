unit uANSIParser;

{ ANSI / VT100 Escape Sequence Parser and Styled Cell Generator for MTN2.
  Parses SGR (colors: 16-color, 256-color, 24-bit TrueColor; bold/underline/reverse),
  CSI cursor positioning, line/screen erases, and OSC sequence stripping. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, uTerminalTypes;

type
  IANSIParser = interface
    ['{E43B3674-325A-4B6A-B6D7-90C3664C268E}']
    procedure Reset;
    procedure ParseText(const AText: string; AOnCell: TProc<Char, TAlphaColor, TAlphaColor, TCharCellAttributes>;
      AOnNewline: TProc; AOnCarriageReturn: TProc; AOnBackSpace: TProc;
      AOnEraseLine: TProc<Integer>; AOnEraseDisplay: TProc<Integer>;
      AOnCursorPos: TProc<Integer, Integer>; AOnCursorMove: TProc<Char, Integer>;
      AOnCursorSaveRestore: TProc<Boolean>; AOnSetMode: TProc<Integer, Boolean>);
  end;

  TParserState = (psText, psEscape, psCsi, psOsc, psOscEscape);

  TANSIParser = class(TInterfacedObject, IANSIParser)
  private
    FState: TParserState;
    FCsiParams: TArray<Integer>;
    FCsiParamBuf: string;
    FOscLen: Integer;            // guards against unterminated OSC swallowing output
    FCurrentFg: TAlphaColor;
    FCurrentBg: TAlphaColor;
    FCurrentAttrs: TCharCellAttributes;
    FDefaultFg: TAlphaColor;
    FDefaultBg: TAlphaColor;
    procedure ResetState;
    procedure ProcessSgr;
    function ParseParams(const AParamStr: string): TArray<Integer>;
  public
    constructor Create(ADefaultFg: TAlphaColor = TAlphaColor($FFE0E0E0);
      ADefaultBg: TAlphaColor = TAlphaColor($FF000000));
    procedure Reset;
    procedure ParseText(const AText: string; AOnCell: TProc<Char, TAlphaColor, TAlphaColor, TCharCellAttributes>;
      AOnNewline: TProc; AOnCarriageReturn: TProc; AOnBackSpace: TProc;
      AOnEraseLine: TProc<Integer>; AOnEraseDisplay: TProc<Integer>;
      AOnCursorPos: TProc<Integer, Integer>; AOnCursorMove: TProc<Char, Integer>;
      AOnCursorSaveRestore: TProc<Boolean>; AOnSetMode: TProc<Integer, Boolean>);

    class function Ansi256ToAlphaColor(AIndex: Byte): TAlphaColor;
    class function StandardAnsiColor(AIndex: Byte; ABright: Boolean = False): TAlphaColor;

    property CurrentFg: TAlphaColor read FCurrentFg write FCurrentFg;
    property CurrentBg: TAlphaColor read FCurrentBg write FCurrentBg;
    property CurrentAttrs: TCharCellAttributes read FCurrentAttrs write FCurrentAttrs;
  end;

implementation

const
  // OSC payloads (icon titles, hyperlinks) are a few dozen bytes in practice.
  // A megabyte-long OSC is always a missing terminator; abort instead of eating
  // the rest of the stream.
  cMaxOscLen = 4096;

  cAnsiColors: array[0..15] of TAlphaColor = (
    TAlphaColor($FF000000), // 0: Black
    TAlphaColor($FFC00000), // 1: Red
    TAlphaColor($FF00C000), // 2: Green
    TAlphaColor($FFC0C000), // 3: Yellow
    TAlphaColor($FF0000C0), // 4: Blue
    TAlphaColor($FFC000C0), // 5: Magenta
    TAlphaColor($FF00C0C0), // 6: Cyan
    TAlphaColor($FFC0C0C0), // 7: White
    TAlphaColor($FF808080), // 8: Bright Black (Gray)
    TAlphaColor($FFFF5555), // 9: Bright Red
    TAlphaColor($FF55FF55), // 10: Bright Green
    TAlphaColor($FFFFFF55), // 11: Bright Yellow
    TAlphaColor($FF5555FF), // 12: Bright Blue
    TAlphaColor($FFFF55FF), // 13: Bright Magenta
    TAlphaColor($FF55FFFF), // 14: Bright Cyan
    TAlphaColor($FFFFFFFF)  // 15: Bright White
  );

constructor TANSIParser.Create(ADefaultFg, ADefaultBg: TAlphaColor);
begin
  inherited Create;
  FDefaultFg := ADefaultFg;
  FDefaultBg := ADefaultBg;
  Reset;
end;

procedure TANSIParser.ResetState;
begin
  FState := psText;
  FCsiParamBuf := '';
  SetLength(FCsiParams, 0);
  FOscLen := 0;
end;

procedure TANSIParser.Reset;
begin
  ResetState;
  FCurrentFg := FDefaultFg;
  FCurrentBg := FDefaultBg;
  FCurrentAttrs := [];
end;

class function TANSIParser.StandardAnsiColor(AIndex: Byte; ABright: Boolean): TAlphaColor;
begin
  if AIndex > 7 then
    Exit(cAnsiColors[EnsureRange(AIndex, 0, 15)]);
  if ABright then
    Result := cAnsiColors[AIndex + 8]
  else
    Result := cAnsiColors[AIndex];
end;

function MakeColor(R, G, B: Byte; A: Byte = $FF): TAlphaColor;
begin
  Result := (Cardinal(A) shl 24) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

class function TANSIParser.Ansi256ToAlphaColor(AIndex: Byte): TAlphaColor;
var
  R, G, B, V: Byte;
begin
  if AIndex < 16 then
    Exit(cAnsiColors[AIndex]);

  if AIndex >= 232 then
  begin
    // Grayscale ramp (24 steps: 232 = #08, 255 = #EE)
    V := 8 + (AIndex - 232) * 10;
    Exit(MakeColor(V, V, V, $FF));
  end;

  // 6x6x6 Color Cube (16..231)
  AIndex := AIndex - 16;
  R := (AIndex div 36) * 51;
  G := ((AIndex mod 36) div 6) * 51;
  B := (AIndex mod 6) * 51;
  Result := MakeColor(R, G, B, $FF);
end;

function TANSIParser.ParseParams(const AParamStr: string): TArray<Integer>;
var
  Parts: TArray<string>;
  I, Val: Integer;
begin
  if AParamStr = '' then
    Exit(nil);
  Parts := AParamStr.Split([';']);
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do
  begin
    if TryStrToInt(Parts[I], Val) then
      Result[I] := Val
    else
      Result[I] := 0;
  end;
end;

procedure TANSIParser.ProcessSgr;
var
  P, Count, I: Integer;
  R, G, B, ColorIdx: Integer;
begin
  Count := Length(FCsiParams);
  if Count = 0 then
  begin
    // SGR 0 default
    FCurrentFg := FDefaultFg;
    FCurrentBg := FDefaultBg;
    FCurrentAttrs := [];
    Exit;
  end;

  I := 0;
  while I < Count do
  begin
    P := FCsiParams[I];
    case P of
      0:
        begin
          FCurrentFg := FDefaultFg;
          FCurrentBg := FDefaultBg;
          FCurrentAttrs := [];
        end;
      1: Include(FCurrentAttrs, ccaBold);
      2: ; // Faint
      3: Include(FCurrentAttrs, ccaItalic);
      4: Include(FCurrentAttrs, ccaUnderline);
      5, 6: Include(FCurrentAttrs, ccaBlink);
      7: Include(FCurrentAttrs, ccaReverse);
      22: Exclude(FCurrentAttrs, ccaBold);
      23: Exclude(FCurrentAttrs, ccaItalic);
      24: Exclude(FCurrentAttrs, ccaUnderline);
      25: Exclude(FCurrentAttrs, ccaBlink);
      27: Exclude(FCurrentAttrs, ccaReverse);
      30..37: FCurrentFg := StandardAnsiColor(P - 30, ccaBold in FCurrentAttrs);
      39: FCurrentFg := FDefaultFg;
      40..47: FCurrentBg := StandardAnsiColor(P - 40);
      49: FCurrentBg := FDefaultBg;
      90..97: FCurrentFg := StandardAnsiColor(P - 90, True);
      100..107: FCurrentBg := StandardAnsiColor(P - 100, True);
      38:
        begin
          // Extended Fg: 38;5;n or 38;2;r;g;b
          if (I + 1 < Count) and (FCsiParams[I + 1] = 5) and (I + 2 < Count) then
          begin
            ColorIdx := EnsureRange(FCsiParams[I + 2], 0, 255);
            FCurrentFg := Ansi256ToAlphaColor(Byte(ColorIdx));
            Inc(I, 2);
          end
          else if (I + 1 < Count) and (FCsiParams[I + 1] = 2) and (I + 4 < Count) then
          begin
            R := EnsureRange(FCsiParams[I + 2], 0, 255);
            G := EnsureRange(FCsiParams[I + 3], 0, 255);
            B := EnsureRange(FCsiParams[I + 4], 0, 255);
            FCurrentFg := MakeColor(R, G, B, $FF);
            Inc(I, 4);
          end;
        end;
      48:
        begin
          // Extended Bg: 48;5;n or 48;2;r;g;b
          if (I + 1 < Count) and (FCsiParams[I + 1] = 5) and (I + 2 < Count) then
          begin
            ColorIdx := EnsureRange(FCsiParams[I + 2], 0, 255);
            FCurrentBg := Ansi256ToAlphaColor(Byte(ColorIdx));
            Inc(I, 2);
          end
          else if (I + 1 < Count) and (FCsiParams[I + 1] = 2) and (I + 4 < Count) then
          begin
            R := EnsureRange(FCsiParams[I + 2], 0, 255);
            G := EnsureRange(FCsiParams[I + 3], 0, 255);
            B := EnsureRange(FCsiParams[I + 4], 0, 255);
            FCurrentBg := MakeColor(R, G, B, $FF);
            Inc(I, 4);
          end;
        end;
    end;
    Inc(I);
  end;
end;

procedure TANSIParser.ParseText(const AText: string;
  AOnCell: TProc<Char, TAlphaColor, TAlphaColor, TCharCellAttributes>;
  AOnNewline, AOnCarriageReturn, AOnBackSpace: TProc;
  AOnEraseLine: TProc<Integer>; AOnEraseDisplay: TProc<Integer>;
  AOnCursorPos: TProc<Integer, Integer>; AOnCursorMove: TProc<Char, Integer>;
  AOnCursorSaveRestore: TProc<Boolean>; AOnSetMode: TProc<Integer, Boolean>);
var
  I, Len, ElMode, EdMode, Row, Col, N, J: Integer;
  C: Char;
  FinalCmd: Char;
  IsPrivate: Boolean;
begin
  Len := Length(AText);
  if Len = 0 then
    Exit;

  I := 1;
  while I <= Len do
  begin
    C := AText[I];
    case FState of
      psEscape:
        begin
          if C = '[' then
          begin
            FState := psCsi;
            FCsiParamBuf := '';
          end
          else if C = ']' then
          begin
            FState := psOsc;
          end
          else
          begin
            FState := psText;
          end;
        end;

      psCsi:
        begin
          if CharInSet(C, ['0'..'9', ';', '?', ' ']) then
          begin
            FCsiParamBuf := FCsiParamBuf + C;
          end
          else
          begin
            FinalCmd := C;
            IsPrivate := (Length(FCsiParamBuf) > 0) and (FCsiParamBuf[1] = '?');
            if IsPrivate then
              FCsiParams := ParseParams(Copy(FCsiParamBuf, 2, MaxInt))
            else
              FCsiParams := ParseParams(FCsiParamBuf);
            case FinalCmd of
              'm': ProcessSgr;
              'K':
                begin
                  if Length(FCsiParams) = 0 then
                    ElMode := 0
                  else
                    ElMode := FCsiParams[0];
                  if Assigned(AOnEraseLine) then
                    AOnEraseLine(ElMode);
                end;
              'J':
                begin
                  if Length(FCsiParams) = 0 then
                    EdMode := 0
                  else
                    EdMode := FCsiParams[0];
                  if Assigned(AOnEraseDisplay) then AOnEraseDisplay(EdMode);
                end;
              'H', 'f':
                begin
                  if Length(FCsiParams) >= 1 then Row := FCsiParams[0] else Row := 1;
                  if Length(FCsiParams) >= 2 then Col := FCsiParams[1] else Col := 1;
                  if Assigned(AOnCursorPos) then AOnCursorPos(Row - 1, Col - 1);
                end;
              'A', 'B', 'C', 'D':
                begin
                  if Length(FCsiParams) >= 1 then N := Max(FCsiParams[0], 1) else N := 1;
                  if Assigned(AOnCursorMove) then AOnCursorMove(FinalCmd, N);
                end;
              's':
                if (not IsPrivate) and Assigned(AOnCursorSaveRestore) then
                  AOnCursorSaveRestore(True);
              'u':
                if Assigned(AOnCursorSaveRestore) then
                  AOnCursorSaveRestore(False);
              'h', 'l':
                if IsPrivate and Assigned(AOnSetMode) then
                  for J := 0 to High(FCsiParams) do
                    AOnSetMode(FCsiParams[J], FinalCmd = 'h');
            end;
            ResetState;
          end;
        end;

      psOsc:
        begin
          if C = #7 then
            ResetState
          else if C = #27 then
          begin
            FState := psOscEscape;
            Inc(FOscLen);
          end
          else
          begin
            Inc(FOscLen);
            // An OSC without a BEL/ST terminator (broken pipe, an app that emits
            // a stray ESC ]) would otherwise trap the parser in psOsc forever and
            // silently swallow every following byte. Bail out past a sane cap.
            if FOscLen > cMaxOscLen then
              ResetState;
          end;
        end;

      psOscEscape:
        begin
          if C = '\' then
            ResetState
          else
          begin
            FState := psOsc;
            Inc(FOscLen);
            if FOscLen > cMaxOscLen then
              ResetState;
          end;
        end;

      psText:
        begin
          case C of
            #27: FState := psEscape;
            #10: if Assigned(AOnNewline) then AOnNewline();
            #13: if Assigned(AOnCarriageReturn) then AOnCarriageReturn();
            #8, #127: if Assigned(AOnBackSpace) then AOnBackSpace();
            #0, #7: ;
          else
            if Assigned(AOnCell) then
              AOnCell(C, FCurrentFg, FCurrentBg, FCurrentAttrs);
          end;
        end;
    end;
    Inc(I);
  end;
end;

end.
