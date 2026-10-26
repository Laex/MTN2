unit uAnsiFrame;

{ Turns a character grid into the escape sequences that make a text terminal
  show it. Only the cells that differ from the previous frame are written,
  with the colors as 24-bit SGR sequences, and the cursor is moved only where
  a run of changed cells does not continue the previous one. The writer is a
  pure function of the grids it is given, so it can be tested without a
  terminal. }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, uTerminalTypes;

type
  /// <summary>How many colors the terminal shows.</summary>
  TAnsiColorMode = (acmTrueColor, acm256, acm16);

  TAnsiFrameWriter = class
  private
    FPrev: TTerminalGrid;
    FPrevValid: Boolean;
    FCols: Integer;
    FRows: Integer;
    FColorMode: TAnsiColorMode;
    FCursorShown: Boolean;
    FCursorX: Integer;
    FCursorY: Integer;
    function CellChanged(const AGrid: TTerminalGrid; ARow, ACol: Integer): Boolean;
    function FindCaret(const AGrid: TTerminalGrid; out AX, AY: Integer): Boolean;
  public
    constructor Create;
    property ColorMode: TAnsiColorMode read FColorMode write FColorMode;
    /// <summary>The next Render writes every cell.</summary>
    procedure Invalidate;
    /// <summary>Escape sequences that move the terminal from the previous
    /// frame to AGrid, as UTF-8; empty when nothing changed.</summary>
    function Render(const AGrid: TTerminalGrid): TBytes;
  end;

/// <summary>Sequence that sets the colors and attributes of a cell.</summary>
function AnsiSgrFor(AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes;
  AMode: TAnsiColorMode = acmTrueColor): string;

/// <summary>The color mode a terminal announces through its environment:
/// COLORTERM (truecolor, 24bit) or a TERM ending in 256color.</summary>
function DetectColorMode(const AColorTerm, ATerm: string): TAnsiColorMode;

/// <summary>Switch to the alternate screen, hide the cursor, no auto wrap,
/// enable mouse (SGR) and bracketed paste, ask for the kitty keyboard flags
/// and the device attributes.</summary>
function AnsiEnterSequence(AMouse: Boolean): string;
/// <summary>Turns the terminal's mouse reporting on or off (press, drag and
/// release in the SGR format); with it off the terminal selects text itself.</summary>
function AnsiMouseSequence(AOn: Boolean): string;
/// <summary>Undoes AnsiEnterSequence and restores the colors.</summary>
function AnsiLeaveSequence: string;

implementation

function Index256(AColor: TAlphaColor): Integer;
var
  C: TAlphaColorRec;
  R, G, B, Gray: Integer;

  function Level(AValue: Integer): Integer;
  begin
    if AValue < 48 then
      Result := 0
    else if AValue < 115 then
      Result := 1
    else
      Result := (AValue - 35) div 40;
  end;

begin
  C.Color := AColor;
  R := C.R;
  G := C.G;
  B := C.B;
  // Grays use the 24-step ramp when it is closer than the cube's diagonal.
  if (Abs(R - G) < 10) and (Abs(G - B) < 10) then
  begin
    Gray := (R + G + B) div 3;
    if Gray < 5 then
      Exit(16);
    if Gray > 246 then
      Exit(231);
    Exit(232 + Min((Gray - 8) div 10, 23));
  end;
  Result := 16 + 36 * Level(R) + 6 * Level(G) + Level(B);
end;

const
  cAnsi16: array[0..15, 0..2] of Byte = (
    (0, 0, 0), (170, 0, 0), (0, 170, 0), (170, 85, 0), (0, 0, 170), (170, 0, 170),
    (0, 170, 170), (170, 170, 170), (85, 85, 85), (255, 85, 85), (85, 255, 85),
    (255, 255, 85), (85, 85, 255), (255, 85, 255), (85, 255, 255), (255, 255, 255));

function Index16(AColor: TAlphaColor): Integer;
var
  C: TAlphaColorRec;
  I, D, Best, BestD: Integer;
begin
  C.Color := AColor;
  Best := 0;
  BestD := MaxInt;
  for I := 0 to 15 do
  begin
    D := Sqr(C.R - cAnsi16[I, 0]) + Sqr(C.G - cAnsi16[I, 1]) + Sqr(C.B - cAnsi16[I, 2]);
    if D < BestD then
    begin
      BestD := D;
      Best := I;
    end;
  end;
  Result := Best;
end;

function DetectColorMode(const AColorTerm, ATerm: string): TAnsiColorMode;
begin
  if SameText(AColorTerm, 'truecolor') or SameText(AColorTerm, '24bit') then
    Result := acmTrueColor
  else if ATerm.EndsWith('256color', True) or ATerm.EndsWith('direct', True) then
    Result := acm256
  else if SameText(ATerm, 'linux') or SameText(ATerm, 'vt100') or SameText(ATerm, 'ansi') then
    Result := acm16
  else
    Result := acm256;
end;

function AnsiSgrFor(AFg, ABg: TAlphaColor; AAttr: TCharCellAttributes;
  AMode: TAnsiColorMode): string;
var
  F, B: TAlphaColorRec;
  I: Integer;
begin
  F.Color := AFg;
  B.Color := ABg;
  Result := #27'[0';
  if ccaBold in AAttr then
    Result := Result + ';1';
  if ccaItalic in AAttr then
    Result := Result + ';3';
  if ccaUnderline in AAttr then
    Result := Result + ';4';
  if ccaBlink in AAttr then
    Result := Result + ';5';
  if ccaReverse in AAttr then
    Result := Result + ';7';
  if ccaStrike in AAttr then
    Result := Result + ';9';
  case AMode of
    acm256:
      Result := Result + Format(';38;5;%d;48;5;%dm', [Index256(AFg), Index256(ABg)]);
    acm16:
      begin
        I := Index16(AFg);
        if I < 8 then
          Result := Result + Format(';%d', [30 + I])
        else
          Result := Result + Format(';%d', [90 + I - 8]);
        I := Index16(ABg);
        if I < 8 then
          Result := Result + Format(';%dm', [40 + I])
        else
          Result := Result + Format(';%dm', [100 + I - 8]);
      end;
  else
    Result := Result + Format(';38;2;%d;%d;%d;48;2;%d;%d;%dm',
      [F.R, F.G, F.B, B.R, B.G, B.B]);
  end;
end;

function AnsiEnterSequence(AMouse: Boolean): string;
begin
  Result := #27'[?1049h'      // alternate screen
    + #27'[?25l'              // hide the cursor
    + #27'[?7l'               // no auto wrap
    + #27'[?2004h'            // bracketed paste
    + #27'[>5u'               // kitty keyboard: disambiguate + alternate keys
    + #27'[>4;2m'             // xterm modifyOtherKeys 2 for terminals without kitty keys
    + #27'[?u'                // ask for the kitty keyboard flags
    + #27'[c';                // device attributes: ends the query
  if AMouse then
    Result := Result + AnsiMouseSequence(True);
  Result := Result + #27'[2J';
end;

function AnsiMouseSequence(AOn: Boolean): string;
begin
  if AOn then
    Result := #27'[?1000h' + #27'[?1002h' + #27'[?1006h'
  else
    Result := #27'[?1006l' + #27'[?1002l' + #27'[?1000l';
end;

function AnsiLeaveSequence: string;
begin
  Result := #27'[?1006l' + #27'[?1002l' + #27'[?1000l'
    + #27'[<u'                // pop the kitty keyboard flags
    + #27'[>4;0m'             // modifyOtherKeys off
    + #27'[?2004l'
    + #27'[?7h'
    + #27'[0m'
    + #27'[?25h'
    + #27'[?1049l';
end;

{ TAnsiFrameWriter }

constructor TAnsiFrameWriter.Create;
begin
  inherited Create;
  FPrevValid := False;
end;

procedure TAnsiFrameWriter.Invalidate;
begin
  FPrevValid := False;
end;

function TAnsiFrameWriter.CellChanged(const AGrid: TTerminalGrid; ARow,
  ACol: Integer): Boolean;
begin
  Result := not FPrevValid or not SameCharCell(AGrid[ARow][ACol], FPrev[ARow][ACol]);
end;

// The cell that carries the insert caret of an input field, if one does.
function TAnsiFrameWriter.FindCaret(const AGrid: TTerminalGrid; out AX,
  AY: Integer): Boolean;
var
  X, Y: Integer;
begin
  for Y := 0 to High(AGrid) do
    for X := 0 to High(AGrid[Y]) do
      if ccaInsertCaret in AGrid[Y][X].Attributes then
      begin
        AX := X;
        AY := Y;
        Exit(True);
      end;
  AX := -1;
  AY := -1;
  Result := False;
end;

function TAnsiFrameWriter.Render(const AGrid: TTerminalGrid): TBytes;
var
  Rows, Cols, Y, X, RunEnd, K, GapEnd: Integer;
  Out_: TStringBuilder;
  CurFg, CurBg: TAlphaColor;
  CurAttr: TCharCellAttributes;
  HaveSgr: Boolean;
  CursorX, CursorY: Integer;
  Cell: TCharCell;
  CaretX, CaretY: Integer;
  HasCaret: Boolean;
  Tail: string;
  Changed: TArray<Boolean>;
  Attr: TCharCellAttributes;
  Ch: Char;
begin
  Rows := Length(AGrid);
  if Rows = 0 then
    Exit(nil);
  Cols := Length(AGrid[0]);
  if (Rows <> FRows) or (Cols <> FCols) then
  begin
    FRows := Rows;
    FCols := Cols;
    FPrevValid := False;
  end;
  Out_ := TStringBuilder.Create;
  try
    HaveSgr := False;
    CurFg := 0;
    CurBg := 0;
    CurAttr := [];
    CursorX := -1;
    CursorY := -1;
    SetLength(Changed, Cols);
    for Y := 0 to Rows - 1 do
    begin
      if Length(AGrid[Y]) <> Cols then
        Continue;
      // Changed cells of the row; a wide character is rewritten whole.
      for X := 0 to Cols - 1 do
        Changed[X] := CellChanged(AGrid, Y, X);
      for X := 0 to Cols - 1 do
        if Changed[X] then
        begin
          if (ccaWide in AGrid[Y][X].Attributes) and (X < Cols - 1) then
            Changed[X + 1] := True;
          if (ccaWideTail in AGrid[Y][X].Attributes) and (X > 0) then
            Changed[X - 1] := True;
        end;
      X := 0;
      while X < Cols do
      begin
        if not Changed[X] then
        begin
          Inc(X);
          Continue;
        end;
        // A run of changes; a gap of up to three unchanged cells is cheaper
        // to rewrite than to jump over.
        RunEnd := X;
        while RunEnd < Cols do
        begin
          if Changed[RunEnd] then
          begin
            Inc(RunEnd);
            Continue;
          end;
          GapEnd := RunEnd;
          while (GapEnd < Cols) and not Changed[GapEnd] and (GapEnd - RunEnd < 4) do
            Inc(GapEnd);
          if (GapEnd < Cols) and Changed[GapEnd] and (GapEnd - RunEnd <= 3) then
            RunEnd := GapEnd
          else
            Break;
        end;
        if (CursorY <> Y) or (CursorX <> X) then
          Out_.Append(#27'[').Append(Y + 1).Append(';').Append(X + 1).Append('H');
        K := X;
        while K < RunEnd do
        begin
          Cell := AGrid[Y][K];
          if ccaWideTail in Cell.Attributes then
          begin
            // The first half drew both cells.
            Inc(K);
            Continue;
          end;
          Attr := Cell.Attributes * [ccaBold, ccaItalic, ccaUnderline, ccaBlink,
            ccaReverse, ccaStrike];
          if not HaveSgr or (Cell.FgColor <> CurFg) or (Cell.BgColor <> CurBg) or
             (Attr <> CurAttr) then
          begin
            Out_.Append(AnsiSgrFor(Cell.FgColor, Cell.BgColor, Attr, FColorMode));
            CurFg := Cell.FgColor;
            CurBg := Cell.BgColor;
            CurAttr := Attr;
            HaveSgr := True;
          end;
          Ch := Cell.CharValue;
          if (Ch < ' ') or (Ch = #127) then
            Ch := ' ';
          Out_.Append(Ch);
          Inc(K);
        end;
        CursorY := Y;
        CursorX := RunEnd;
        X := RunEnd;
      end;
    end;
    // The insert caret of an input field is the terminal's own cursor.
    HasCaret := FindCaret(AGrid, CaretX, CaretY);
    Tail := '';
    if HasCaret then
    begin
      if (Out_.Length > 0) or not FCursorShown or (CaretX <> FCursorX) or
         (CaretY <> FCursorY) then
        Tail := Format(#27'[%d;%dH'#27'[6 q'#27'[?25h', [CaretY + 1, CaretX + 1]);
    end
    else if FCursorShown then
      Tail := #27'[?25l';
    FCursorShown := HasCaret;
    FCursorX := CaretX;
    FCursorY := CaretY;
    if (Out_.Length = 0) and (Tail = '') then
      Result := nil
    else if Out_.Length = 0 then
      Result := TEncoding.UTF8.GetBytes(Tail)
    else
      Result := TEncoding.UTF8.GetBytes(
        #27'[?2026h'#27'[?25l' + Out_.ToString + Tail + #27'[?2026l');
  finally
    Out_.Free;
  end;
  // Keep a copy of this frame for the next comparison.
  SetLength(FPrev, Rows);
  for Y := 0 to Rows - 1 do
  begin
    SetLength(FPrev[Y], Length(AGrid[Y]));
    if Length(AGrid[Y]) > 0 then
      Move(AGrid[Y][0], FPrev[Y][0], Length(AGrid[Y]) * SizeOf(TCharCell));
  end;
  FPrevValid := True;
end;

end.
