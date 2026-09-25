unit uConsoleBuffer;

{ Line-oriented console history with ANSI VT100 parser and TrueColor cell support.
  Accepts raw process output (CR/LF/CRLF, CSI/OSC/SGR) and stores a styled cell
  scrollback (TConsoleRow = TArray<TCharCell>) up to 10 000+ lines. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Math, System.UITypes,
  System.Generics.Collections, uTerminalTypes, uANSIParser, uAltScreenGrid,
  uPrimaryScreenGrid;

type
  TConsoleRow = TArray<TCharCell>;

  TConsoleBuffer = class
  private
    FLock: TCriticalSection;
    FPlainLines: TStringList;
    FCellLines: TList<TConsoleRow>;
    FMaxLines: Integer;
    FFollowTail: Boolean;
    FScroll: Integer;
    FPendingCR: Boolean;
    FPendingEraseToEOL: Boolean;
    FCursorCol: Integer;
    /// <summary>Index of the line CommitInputLine most recently started. Lines
    /// before this are submitted history — GetInputAfterPrompt's upward scan
    /// must never cross it, or it can find an old already-run command (e.g.
    /// "PS ...> ls" still sitting in scrollback) and mistake it for input the
    /// user is currently typing.</summary>
    FInputLineStart: Integer;
    FAnsiParser: TANSIParser;
    FAltGrid: TAltScreenGrid;
    FAltActive: Boolean;
    /// <summary>Set right after a local backspace erase (NotePendingLocalBackspace),
    /// cleared once the matching real-echo suppression window opens or a
    /// newline arrives without one ever starting (stale-guard). See
    /// FSuppressingBackspaceEcho.</summary>
    FPendingLocalBackspace: Boolean;
    /// <summary>True while swallowing the real shell's own CUP-based erase
    /// echo (hide-cursor / CUP / overwrite-with-spaces / CUP / show-cursor)
    /// for a backspace we already applied locally via AppendLocalInput(#8) —
    /// see NotePendingLocalBackspace. Real Windows conhost line-editing
    /// erases via absolute cursor addressing that does not map onto this
    /// buffer's unbounded scrollback coordinates (confirmed empirically),
    /// so the echo is discarded wholesale rather than misapplied.</summary>
    FSuppressingBackspaceEcho: Boolean;
    /// <summary>Latches True on the first real PTY-geometry AppendOutputEx
    /// call (see EnableGridModeLocked) and never reverts, except via a full
    /// Clear(). While True, FActiveGrid (not FPlainLines' bottom line) is
    /// the live, cursor-addressable "active screen"; FPlainLines/FCellLines
    /// become an archive of rows scrolled off its top -- see the unit's
    /// "Единая адресация строк" design (Фаза D).</summary>
    FGridEnabled: Boolean;
    FActiveGrid: TPrimaryScreenGrid;
    procedure EnsureCurrentLineLocked;
    procedure StartNewLineLocked;
    procedure PutCellAtCursorLocked(AChar: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure PutTabAtCursorLocked(AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure TruncateLineToCursorLocked;
    procedure DeleteCharBeforeCursorLocked;
    procedure EraseFromCursorLocked(AElMode: Integer);
    procedure EraseCurrentLineLocked;
    /// <summary>Resets scrollback content and cursor bookkeeping only --
    /// unlike ClearAllLinesLocked, does NOT touch FGridEnabled/FActiveGrid.
    /// Used by EraseDisplayLocked so an in-session ESC[2J (which conhost
    /// sends routinely, not just at session start) resets visible content
    /// without dropping out of grid mode on every clear.</summary>
    procedure ClearContentLocked;
    procedure ClearAllLinesLocked;
    /// <summary>ED (ESC[2J) callback target: always a full reset (matches
    /// legacy; the ED mode argument is intentionally ignored, per Фаза D's
    /// "keep today's full-history-reset behavior" decision), but keeps grid
    /// mode latched if it was already active instead of tearing it down.</summary>
    procedure EraseDisplayLocked(AEdMode: Integer);
    procedure TrimLocked(out ADeleted: Integer);
    function IsBlankLine(AIndex: Integer): Boolean;
    function LineCountLocked: Integer;
    function GetLineLocked(AIndex: Integer): string;
    function GetRowLocked(AIndex: Integer): TConsoleRow;
    /// <summary>One-time grid-mode activation, latched by FGridEnabled. See
    /// AppendOutputEx's "(not FGridEnabled) and (ACols>0) and (ARows>0)" gate.</summary>
    procedure EnableGridModeLocked(ACols, ARows: Integer);
    /// <summary>FActiveGrid.OnArchiveRow target: files a row scrolled off
    /// the grid's top into the permanent FPlainLines/FCellLines archive.</summary>
    procedure ArchiveRowLocked(const ARow: TTerminalRow);
    /// <summary>Единая точка входа операций записи (Фаза D): each dispatches
    /// FGridEnabled ? FActiveGrid.<op> : <untouched legacy Xxx*Locked call>,
    /// called from AppendOutputEx's ANSI-parser callbacks in place of the
    /// direct legacy call, with the callbacks' existing FAltActive /
    /// FSuppressingBackspaceEcho guards left exactly where they are.</summary>
    procedure PutCharLocked(AChar: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure TabLocked(AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
    procedure NewLineLocked2(AFg, ABg: TAlphaColor);
    procedure CarriageReturnLocked;
    /// <summary>AIsLocalInput distinguishes a single synthetic #8 from
    /// NotePendingLocalBackspace (must delete-and-shift, matching legacy
    /// DeleteCharBeforeCursorLocked exactly) from a real PTY-echoed BS byte
    /// (always half of the standard "\b <space> \b" erase idiom -- WSL/bash;
    /// real conhost's own CUP-based idiom is suppressed before reaching
    /// here -- so it must be a non-destructive cursor-only move, or the
    /// idiom's trailing space-overwrite would land on the wrong, already-
    /// shifted cell and corrupt everything right of the cursor).</summary>
    procedure BackspaceEraseLocked(AIsLocalInput: Boolean);
    procedure EraseLineLocked(AElMode: Integer; AFg, ABg: TAlphaColor);
    /// <summary>CUP callback target. Grid-mode-only in effect (legacy has no
    /// row-cursor to address, so the else-branch is a no-op, matching
    /// today's outside-alt-screen behavior).</summary>
    procedure CursorPosLocked(ARow, ACol: Integer);
    /// <summary>CUF/CUB/CUU/CUD callback target. Grid-mode-only in effect,
    /// same as CursorPosLocked (legacy has no row/col cursor to move
    /// relative to).</summary>
    procedure MoveRelLocked(ADir: Char; ACount: Integer);
  public
    constructor Create(AMaxLines: Integer = 10000);
    destructor Destroy; override;
    procedure Clear;
    procedure AppendOutput(const AText: string);
    /// <summary>Local keyboard/paste echo onto the current input line. Unlike
    /// AppendOutput, never reinterprets the text as an incoming shell prompt
    /// (the "looks like a drive path" heuristic is PTY-output-only; a pasted
    /// path starting with "X:\" is not a new prompt).</summary>
    function AppendLocalInput(const AText: string): Integer;
    /// <summary>Call right after locally erasing a character via
    /// AppendLocalInput(#8) (real Windows conhost line-editing profiles
    /// only -- not WSL/bash, which erases via a simple, non-CUP echo that
    /// already works correctly). Primes AppendOutputEx to swallow the real
    /// shell's own CUP-based erase echo when it arrives asynchronously,
    /// instead of double-applying it.</summary>
    procedure NotePendingLocalBackspace;
    procedure AppendCommand(const APrompt: string);
    procedure AppendStatus(const AText: string);
    procedure GetScrollMetrics(AViewH: Integer; out ATotal, ATop: Integer);
    function GetVisibleLines(AViewH: Integer; out ATotal, ATop: Integer): TArray<string>;
    function GetVisibleRows(AViewH: Integer; out ATotal, ATop: Integer): TArray<TConsoleRow>;
    function LineCount: Integer;
    function GetLine(AIndex: Integer): string;
    function GetRow(AIndex: Integer): TConsoleRow;
    /// <summary>Text typed after the shell prompt on a line (for line-buffered cmd input).</summary>
    function GetInputAfterPrompt(AIndex: Integer = -1): string;
    /// <summary>After Enter: close the input line so PTY output starts below.</summary>
    procedure CommitInputLine;
    /// <summary>Write cursor on the active input line. Independent of FollowTail:
    /// a click/scroll that unpins the tail must not hide the PTY caret while
    /// that line is still on screen.</summary>
    function GetInputCursor(out ALineIndex, ACol: Integer): Boolean;
    /// <summary>Append and return how many leading lines were trimmed.
    /// AIsLocalInput suppresses the PTY "incoming prompt" line-split heuristics
    /// (see AppendLocalInput).</summary>
    function AppendOutputEx(const AText: string; ACols: Integer = 0; ARows: Integer = 0;
      AIsLocalInput: Boolean = False): Integer;
    /// <summary>Reflow the alternate screen (if active) to new PTY dimensions.</summary>
    procedure ResizeAltScreen(ACols, ARows: Integer);
    /// <summary>Reflow the primary buffer's active grid (if grid mode is
    /// latched) to new PTY dimensions -- mirrors ResizeAltScreen. A no-op
    /// before grid mode has ever activated (FActiveGrid nil).</summary>
    procedure ResizePrimaryScreen(ACols, ARows: Integer);
    procedure ScrollBy(ADelta, AViewH: Integer);
    procedure ScrollTo(ATop, AViewH: Integer);
    procedure ScrollToStart;
    procedure ScrollToEnd;
    property FollowTail: Boolean read FFollowTail write FFollowTail;
    property AnsiParser: TANSIParser read FAnsiParser;
    property AltScreenActive: Boolean read FAltActive;
    property AltScreen: TAltScreenGrid read FAltGrid;
  end;

implementation

function LooksLikeDrivePrompt(const S: string): Boolean;
var
  Trimmed: string;
begin
  Result := False;
  if Length(S) >= 3 then
  begin
    if CharInSet(S[1], ['A'..'Z', 'a'..'z']) and (S[2] = ':') and (S[3] = '\') then
      Exit(True);
    if (Length(S) >= 6) and (S[1] = 'P') and (S[2] = 'S') and (S[3] = ' ') and
       CharInSet(S[4], ['A'..'Z', 'a'..'z']) and (S[5] = ':') and (S[6] = '\') then
      Exit(True);
    Trimmed := TrimRight(S);
    if (Trimmed <> '') and CharInSet(Trimmed[Length(Trimmed)], ['$', '#']) then
      Exit(True);
  end;
end;

function FindPromptEndIndex(const ALine: string): Integer;
var
  I, Start: Integer;
begin
  Result := 0;
  if ALine = '' then
    Exit;

  Start := 1;
  if (Length(ALine) >= 3) and (ALine[1] = 'P') and (ALine[2] = 'S') and (ALine[3] = ' ') then
  begin
    for I := 4 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  if (Length(ALine) >= Start + 1) and CharInSet(ALine[Start], ['A'..'Z', 'a'..'z']) and
     (ALine[Start + 1] = ':') then
  begin
    for I := Start + 2 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  if (Length(ALine) >= Start + 1) and (ALine[Start] = '\') and (ALine[Start + 1] = '\') then
  begin
    for I := Start + 2 to Length(ALine) do
      if ALine[I] = '>' then
        Exit(I);
    Exit;
  end;

  for I := 1 to Length(ALine) do
    if CharInSet(ALine[I], ['$', '#']) then
      Exit(I);
end;

function FindPromptProtectedEnd(const ALine: string): Integer;
var
  PromptEnd, I: Integer;
begin
  PromptEnd := FindPromptEndIndex(ALine);
  Result := PromptEnd;
  if PromptEnd = 0 then
    Exit;
  I := PromptEnd + 1;
  while (I <= Length(ALine)) and (ALine[I] = ' ') do
    Inc(I);
  Result := I - 1;
end;

/// <summary>Converts one active-grid row to its plain-text representation
/// (TrimRight'd, matching how the archive already stores completed lines --
/// see StartNewLineLocked). Grid cells are never #0 (Alloc/ClearAll/Reflow
/// always fill with ' '), so a straight CharValue read is safe.</summary>
function GridRowToString(const ARow: TTerminalRow): string;
var
  I: Integer;
begin
  SetLength(Result, Length(ARow));
  for I := 0 to High(ARow) do
    Result[I + 1] := ARow[I].CharValue;
  Result := TrimRight(Result);
end;

constructor TConsoleBuffer.Create(AMaxLines: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPlainLines := TStringList.Create;
  FCellLines := TList<TConsoleRow>.Create;
  FAnsiParser := TANSIParser.Create;
  FAltGrid := TAltScreenGrid.Create;
  FAltActive := False;
  FGridEnabled := False;
  FActiveGrid := nil;
  FMaxLines := Max(AMaxLines, 100);
  FFollowTail := True;
  FScroll := 0;
  FPendingCR := False;
  FPendingEraseToEOL := False;
  FCursorCol := 0;
  FInputLineStart := 0;
  FPlainLines.Add('');
  FCellLines.Add(nil);
end;

destructor TConsoleBuffer.Destroy;
begin
  FCellLines.Free;
  FPlainLines.Free;
  FAnsiParser.Free;
  FAltGrid.Free;
  FActiveGrid.Free;
  FLock.Free;
  inherited Destroy;
end;

function TConsoleBuffer.LineCountLocked: Integer;
begin
  Result := FPlainLines.Count;
  if FGridEnabled then
    Inc(Result, FActiveGrid.Rows);
end;

function TConsoleBuffer.GetLineLocked(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FPlainLines.Count) then
    Result := FPlainLines[AIndex]
  else if FGridEnabled and (AIndex >= FPlainLines.Count) and
          (AIndex < FPlainLines.Count + FActiveGrid.Rows) then
    Result := GridRowToString(FActiveGrid.Grid[AIndex - FPlainLines.Count])
  else
    Result := '';
end;

function TConsoleBuffer.GetRowLocked(AIndex: Integer): TConsoleRow;
var
  I: Integer;
  GridRow: TTerminalRow;
begin
  if (AIndex >= 0) and (AIndex < FPlainLines.Count) then
    Result := FCellLines[AIndex]
  else if FGridEnabled and (AIndex >= FPlainLines.Count) and
          (AIndex < FPlainLines.Count + FActiveGrid.Rows) then
  begin
    GridRow := FActiveGrid.Grid[AIndex - FPlainLines.Count];
    SetLength(Result, Length(GridRow));
    for I := 0 to High(GridRow) do
      Result[I] := GridRow[I];
  end
  else
    Result := nil;
end;

function TConsoleBuffer.IsBlankLine(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= LineCountLocked) then
    Exit(True);
  Result := TrimRight(GetLineLocked(AIndex)) = '';
end;

procedure TConsoleBuffer.TrimLocked(out ADeleted: Integer);
begin
  ADeleted := 0;
  while FPlainLines.Count > FMaxLines do
  begin
    FPlainLines.Delete(0);
    FCellLines.Delete(0);
    Inc(ADeleted);
    if not FFollowTail and (FScroll > 0) then
      Dec(FScroll);
  end;
  if ADeleted > 0 then
    FInputLineStart := Max(0, FInputLineStart - ADeleted);
end;

procedure TConsoleBuffer.EnsureCurrentLineLocked;
begin
  // Grid mode owns "the current line" itself (the grid's own cursor row);
  // FPlainLines legitimately starts and can stay empty until the first row
  // scrolls off the grid's top (see EnableGridModeLocked / ArchiveRowLocked).
  // Every other caller of this method is itself legacy-only (only reached
  // from the FGridEnabled=False branch of its own call site), except
  // AppendOutputEx's unconditional call right after grid activation --
  // without this guard that call immediately re-adds the single blank
  // placeholder EnableGridModeLocked had just stripped out.
  if FGridEnabled then
    Exit;
  if FPlainLines.Count = 0 then
  begin
    FPlainLines.Add('');
    FCellLines.Add(nil);
  end;
end;

procedure TConsoleBuffer.StartNewLineLocked;
var
  N: Integer;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count;
  FPlainLines[N - 1] := TrimRight(FPlainLines[N - 1]);

  if (N >= 2) and IsBlankLine(N - 1) and IsBlankLine(N - 2) then
  begin
    // Collapsing into the existing blank line still means "start fresh at
    // column 0" — that line is blank by definition. Skipping this left
    // FCursorCol stale at whatever it held before the call, so the next
    // character wrote mid-string (silently overwriting real content — e.g.
    // corrupting a freshly-printed prompt) instead of appending.
    FCursorCol := 0;
    FPendingEraseToEOL := False;
    Exit;
  end;

  FPlainLines.Add('');
  FCellLines.Add(nil);
  FCursorCol := 0;
  FPendingEraseToEOL := False;
end;

procedure TConsoleBuffer.EraseCurrentLineLocked;
var
  N: Integer;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count - 1;
  FPlainLines[N] := '';
  FCellLines[N] := nil;
  FCursorCol := 0;
end;

procedure TConsoleBuffer.ClearContentLocked;
begin
  FPlainLines.Clear;
  FCellLines.Clear;
  FPlainLines.Add('');
  FCellLines.Add(nil);
  FScroll := 0;
  FFollowTail := True;
  FPendingCR := False;
  FPendingEraseToEOL := False;
  FCursorCol := 0;
  FInputLineStart := 0;
  FPendingLocalBackspace := False;
  FSuppressingBackspaceEcho := False;
  FAnsiParser.Reset;
end;

procedure TConsoleBuffer.ClearAllLinesLocked;
begin
  ClearContentLocked;
  FGridEnabled := False;
  FreeAndNil(FActiveGrid);
end;

procedure TConsoleBuffer.EraseDisplayLocked(AEdMode: Integer);
begin
  if FGridEnabled then
  begin
    ClearContentLocked;
    // ClearContentLocked leaves its usual single blank placeholder line in
    // FPlainLines (needed for legacy mode's "always >= 1 entry" invariant),
    // but grid mode's own invariant allows an empty archive -- drop it, or
    // every ESC[2J leaves a phantom blank archive line permanently ahead of
    // the freshly-cleared grid (same issue EnableGridModeLocked avoids on
    // first activation, just guaranteed-blank here so no IsBlankLine check
    // is needed).
    FPlainLines.Clear;
    FCellLines.Clear;
    FActiveGrid.Alloc(FActiveGrid.Cols, FActiveGrid.Rows, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
    // FGridEnabled stays True: the session continues with a blank screen
    // instead of dropping back to legacy mode on every routine ESC[2J.
  end
  else
    ClearAllLinesLocked;
end;

procedure TConsoleBuffer.EnableGridModeLocked(ACols, ARows: Integer);
begin
  FActiveGrid := TPrimaryScreenGrid.Create;
  FActiveGrid.OnArchiveRow := ArchiveRowLocked;
  FActiveGrid.Alloc(ACols, ARows, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
  FGridEnabled := True;
  // Discard the single untouched placeholder line from Create/
  // ClearContentLocked -- otherwise every grid-mode session starts with one
  // permanent phantom blank archive line ahead of any real output.
  if (FPlainLines.Count = 1) and IsBlankLine(0) then
  begin
    FPlainLines.Clear;
    FCellLines.Clear;
  end;
end;

procedure TConsoleBuffer.ArchiveRowLocked(const ARow: TTerminalRow);
var
  I: Integer;
  Row: TConsoleRow;
begin
  SetLength(Row, Length(ARow));
  for I := 0 to High(ARow) do
    Row[I] := ARow[I];
  FPlainLines.Add(GridRowToString(ARow));
  FCellLines.Add(Row);
end;

procedure TConsoleBuffer.PutCharLocked(AChar: Char; AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
begin
  if FGridEnabled then
    FActiveGrid.PutCell(AChar, AFg, ABg, AAttrs)
  else
    PutCellAtCursorLocked(AChar, AFg, ABg, AAttrs);
end;

procedure TConsoleBuffer.TabLocked(AFg, ABg: TAlphaColor; AAttrs: TCharCellAttributes);
const
  cTabWidth = 8;
var
  Target, Count, I: Integer;
begin
  if FGridEnabled then
  begin
    // Mirrors PutTabAtCursorLocked's own tab-stop math, against the grid's
    // real cursor column; looping PutCell (rather than jumping the cursor
    // directly) reuses its normal auto-wrap/scroll handling for free.
    Target := ((FActiveGrid.CursorCol div cTabWidth) + 1) * cTabWidth;
    Count := Target - FActiveGrid.CursorCol;
    if Count <= 0 then
      Count := 1;
    for I := 1 to Count do
      FActiveGrid.PutCell(' ', AFg, ABg, AAttrs);
  end
  else
    PutTabAtCursorLocked(AFg, ABg, AAttrs);
end;

procedure TConsoleBuffer.NewLineLocked2(AFg, ABg: TAlphaColor);
begin
  if FGridEnabled then
    FActiveGrid.NewLine(AFg, ABg)
  else
    StartNewLineLocked;
end;

procedure TConsoleBuffer.CarriageReturnLocked;
begin
  if FGridEnabled then
    FActiveGrid.CarriageReturn
  else
  begin
    FCursorCol := 0;
    FPendingCR := True;
    FPendingEraseToEOL := False;
  end;
end;

procedure TConsoleBuffer.BackspaceEraseLocked(AIsLocalInput: Boolean);
var
  GuardCol, RowIdx: Integer;
begin
  if FGridEnabled then
  begin
    if AIsLocalInput then
    begin
      RowIdx := FPlainLines.Count + FActiveGrid.CursorRow;
      GuardCol := FindPromptProtectedEnd(GetLineLocked(RowIdx));
      FActiveGrid.DeleteCharBeforeCursor(GuardCol, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
    end
    else
      FActiveGrid.Backspace;
  end
  else
    DeleteCharBeforeCursorLocked;
end;

procedure TConsoleBuffer.EraseLineLocked(AElMode: Integer; AFg, ABg: TAlphaColor);
begin
  if FGridEnabled then
    FActiveGrid.EraseLine(AElMode, AFg, ABg)
  else
    EraseFromCursorLocked(AElMode);
end;

procedure TConsoleBuffer.CursorPosLocked(ARow, ACol: Integer);
begin
  if FGridEnabled then
    FActiveGrid.MoveAbs(ARow, ACol);
  // else: no-op, matches today's outside-alt-screen behavior (legacy has no
  // row-cursor to address).
end;

procedure TConsoleBuffer.MoveRelLocked(ADir: Char; ACount: Integer);
begin
  if FGridEnabled then
    FActiveGrid.MoveRel(ADir, ACount);
  // else: no-op, matches CursorPosLocked's outside-alt-screen behavior.
end;

procedure TConsoleBuffer.TruncateLineToCursorLocked;
var
  N: Integer;
  Row: TConsoleRow;
  LineStr: string;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count - 1;
  LineStr := FPlainLines[N];
  if FCursorCol < Length(LineStr) then
  begin
    LineStr := Copy(LineStr, 1, FCursorCol);
    FPlainLines[N] := LineStr;
    Row := FCellLines[N];
    if FCursorCol < Length(Row) then
    begin
      SetLength(Row, FCursorCol);
      FCellLines[N] := Row;
    end;
  end;
end;

procedure TConsoleBuffer.PutCellAtCursorLocked(AChar: Char; AFg, ABg: TAlphaColor;
  AAttrs: TCharCellAttributes);
var
  N, Len: Integer;
  Row: TConsoleRow;
  Cell: TCharCell;
  LineStr: string;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count - 1;

  if FPendingEraseToEOL then
  begin
    TruncateLineToCursorLocked;
    FPendingEraseToEOL := False;
  end;

  LineStr := FPlainLines[N];
  Len := Length(LineStr);
  if FCursorCol > Len then
    FCursorCol := Len;

  if FCursorCol < Len then
  begin
    LineStr[FCursorCol + 1] := AChar;
    FPlainLines[N] := LineStr;
    Row := FCellLines[N];
    if FCursorCol < Length(Row) then
    begin
      Cell := Row[FCursorCol];
      Cell.CharValue := AChar;
      Cell.FgColor := AFg;
      Cell.BgColor := ABg;
      Cell.Attributes := AAttrs;
      Row[FCursorCol] := Cell;
      FCellLines[N] := Row;
    end;
  end
  else
  begin
    Len := Length(LineStr);
    SetLength(LineStr, Len + 1);
    LineStr[Len + 1] := AChar;
    FPlainLines[N] := LineStr;
    Row := FCellLines[N];
    Len := Length(Row);
    SetLength(Row, Len + 1);
    Cell.CharValue := AChar;
    Cell.FgColor := AFg;
    Cell.BgColor := ABg;
    Cell.Attributes := AAttrs;
    Row[Len] := Cell;
    FCellLines[N] := Row;
  end;
  Inc(FCursorCol);
end;

procedure TConsoleBuffer.PutTabAtCursorLocked(AFg, ABg: TAlphaColor;
  AAttrs: TCharCellAttributes);
const
  cTabWidth = 8;
var
  Target, Count, I: Integer;
begin
  // Advance to the next 8-cell tab stop with space-filled cells so aligned
  // output (dir, ls -la, source code) renders correctly. Treats the cursor
  // column modulo the tab width, matching the conventional terminal behaviour.
  Target := ((FCursorCol div cTabWidth) + 1) * cTabWidth;
  Count := Target - FCursorCol;
  if Count <= 0 then
    Count := 1;            // defensive: always advance at least one cell
  for I := 1 to Count do
    PutCellAtCursorLocked(' ', AFg, ABg, AAttrs);
end;

procedure TConsoleBuffer.DeleteCharBeforeCursorLocked;
var
  N, Len, PromptEnd: Integer;
  Row: TConsoleRow;
  LineStr: string;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count - 1;
  LineStr := FPlainLines[N];
  Len := Length(LineStr);
  if FCursorCol > Len then
    FCursorCol := Len;
  if FCursorCol <= 0 then
    Exit;

  PromptEnd := FindPromptProtectedEnd(LineStr);
  // PromptEnd is 1-based (index of the last prompt char: '>' / '$' / '#');
  // FCursorCol is 0-based and points one past the last typed char. When the
  // cursor sits right at the prompt boundary (FCursorCol = PromptEnd) there is
  // no input to delete, so block; once the user has typed past it the cursor
  // is strictly greater and deletion proceeds. Verified: for "C:\>" the prompt
  // edge is 4, the first typed char lives at FCursorCol=5, and BS is allowed.
  if (PromptEnd > 0) and (FCursorCol <= PromptEnd) then
    Exit;

  Delete(LineStr, FCursorCol, 1);
  FPlainLines[N] := LineStr;
  Row := FCellLines[N];
  Len := Length(Row);
  if (FCursorCol > 0) and (FCursorCol <= Len) then
  begin
    Delete(Row, FCursorCol - 1, 1);
    FCellLines[N] := Row;
  end;
  Dec(FCursorCol);
end;

procedure TConsoleBuffer.EraseFromCursorLocked(AElMode: Integer);
var
  N, Len: Integer;
  Row: TConsoleRow;
  LineStr: string;
begin
  EnsureCurrentLineLocked;
  N := FPlainLines.Count - 1;
  LineStr := FPlainLines[N];
  Len := Length(LineStr);
  if FCursorCol > Len then
    FCursorCol := Len;

  case AElMode of
    1:
      begin
        if FCursorCol > 0 then
        begin
          LineStr := Copy(LineStr, FCursorCol + 1, MaxInt);
          FPlainLines[N] := LineStr;
          Row := FCellLines[N];
          if FCursorCol <= Length(Row) then
          begin
            Delete(Row, 0, FCursorCol);
            FCellLines[N] := Row;
          end;
          FCursorCol := 0;
        end;
      end;
    2:
      EraseCurrentLineLocked;
  else
    if FCursorCol = 0 then
      FPendingEraseToEOL := True
    else if FCursorCol < Len then
    begin
      LineStr := Copy(LineStr, 1, FCursorCol);
      FPlainLines[N] := LineStr;
      Row := FCellLines[N];
      if FCursorCol < Length(Row) then
      begin
        SetLength(Row, FCursorCol);
        FCellLines[N] := Row;
      end;
    end;
  end;
end;

procedure TConsoleBuffer.Clear;
begin
  FLock.Enter;
  try
    ClearAllLinesLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.CommitInputLine;
begin
  FLock.Enter;
  try
    NewLineLocked2(FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
    if FGridEnabled then
      // NewLineLocked2's grid branch is a pure LF (row-advance only, no
      // implicit column reset -- matching real terminal LF semantics, which
      // the ANSI-parser's own separate CR callback relies on for real \r\n
      // PTY bytes). CommitInputLine isn't part of that parser pipeline --
      // it's called directly after Enter -- so unlike a real \r\n it has no
      // paired CR event, and must apply one itself to match legacy's
      // StartNewLineLocked, which always starts a fresh line at column 0.
      FActiveGrid.CarriageReturn;
    // Everything at or above the fresh line is now submitted history;
    // GetInputAfterPrompt must never scan back past it looking for "pending"
    // input (see FInputLineStart). Logical indices survive archiving
    // unchanged (an archived row's own index shrinks by exactly the amount
    // FPlainLines.Count grows), so this stays valid even after later scrolls.
    FInputLineStart := LineCountLocked - 1;
    FFollowTail := True;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.AppendCommand(const APrompt: string);
var
  Deleted: Integer;
  I: Integer;
  PromptFg, PromptBg: TAlphaColor;
begin
  FLock.Enter;
  try
    FPendingCR := False;
    EnsureCurrentLineLocked;
    if not IsBlankLine(FPlainLines.Count - 1) then
      StartNewLineLocked;

    PromptFg := TAlphaColor($FFF0F000); // Yellow prompt
    PromptBg := TAlphaColor($FF000000);
    EraseCurrentLineLocked;
    for I := 1 to Length(APrompt) do
      PutCellAtCursorLocked(APrompt[I], PromptFg, PromptBg, [ccaBold]);

    StartNewLineLocked;
    TrimLocked(Deleted);
    FFollowTail := True;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.AppendStatus(const AText: string);
var
  Deleted: Integer;
  I: Integer;
  StatusFg, StatusBg: TAlphaColor;
begin
  FLock.Enter;
  try
    FPendingCR := False;
    StatusFg := TAlphaColor($FF00FFFF); // Cyan status
    StatusBg := TAlphaColor($FF000000);

    if FGridEnabled then
    begin
      // Grid mode has no single "current open line" the way the legacy
      // scrollback does -- check the grid's real cursor row/col instead of
      // blindly assuming the buffer's bottom line, which need not be where
      // the cursor actually is (e.g. after a mid-screen CUP redraw). This
      // matters here specifically because status messages (process exit,
      // interrupt, cwd-sync failure) can land mid-session, while a real PTY
      // session -- and therefore grid mode -- is active.
      if (FActiveGrid.CursorCol > 0) or
         not IsBlankLine(FPlainLines.Count + FActiveGrid.CursorRow) then
        NewLineLocked2(FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
      FActiveGrid.CarriageReturn;
      for I := 1 to Length(AText) do
        PutCharLocked(AText[I], StatusFg, StatusBg, []);
      NewLineLocked2(StatusFg, StatusBg);
      FActiveGrid.CarriageReturn; // see CommitInputLine: NewLineLocked2 alone doesn't reset column
    end
    else
    begin
      EnsureCurrentLineLocked;
      if not IsBlankLine(FPlainLines.Count - 1) then
        StartNewLineLocked;
      EraseCurrentLineLocked;
      for I := 1 to Length(AText) do
        PutCellAtCursorLocked(AText[I], StatusFg, StatusBg, []);
      StartNewLineLocked;
    end;

    TrimLocked(Deleted);
    FFollowTail := True;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.AppendOutput(const AText: string);
begin
  AppendOutputEx(AText, 0, 0);
end;

function TConsoleBuffer.AppendLocalInput(const AText: string): Integer;
begin
  Result := AppendOutputEx(AText, 0, 0, True);
end;

procedure TConsoleBuffer.NotePendingLocalBackspace;
begin
  FLock.Enter;
  try
    FPendingLocalBackspace := True;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ResizeAltScreen(ACols, ARows: Integer);
begin
  FLock.Enter;
  try
    if FAltActive then
      FAltGrid.Reflow(ACols, ARows);
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ResizePrimaryScreen(ACols, ARows: Integer);
begin
  FLock.Enter;
  try
    if FGridEnabled then
      FActiveGrid.Reflow(ACols, ARows, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
  finally
    FLock.Leave;
  end;
end;

function FixPromptNewlines(const AText: string; APendingRedraw: Boolean): string;
var
  I, Len, PromptStart: Integer;
  Sb: TStringBuilder;
begin
  Len := Length(AText);
  if Len < 4 then
    Exit(AText);
  // A chunk led by CR is a full-line redraw (readline/cmd rewriting the
  // current line from column 0), not two PTY events glued together. Same for
  // a chunk arriving while an erase-to-EOL is still pending (deferred until
  // the redraw's replacement content shows up, possibly in a later chunk
  // with no CR of its own — see PutCellAtCursorLocked). Any "drive:\...>"
  // pattern found in either case is that same redraw's own content
  // re-echoing the prompt, not a new prompt arriving — splitting it here
  // fractures a single redraw into a phantom extra line and drops the prompt
  // prefix (see TestCmdCrPromptRedraw / TestCrElWipesPrompt).
  if (AText[1] = #13) or APendingRedraw then
    Exit(AText);

  Sb := TStringBuilder.Create(Len + 32);
  try
    I := 1;
    while I <= Len do
    begin
      if (I <= Len - 3) and CharInSet(AText[I], ['A'..'Z', 'a'..'z']) and (AText[I + 1] = ':') and (AText[I + 2] = '\') then
      begin
        PromptStart := I;
        Inc(I, 3);
        while (I <= Len) and (AText[I] <> '>') and (AText[I] <> #10) and (AText[I] <> #13) do
          Inc(I);

        if (I <= Len) and (AText[I] = '>') then
        begin
          Sb.Append(Copy(AText, PromptStart, I - PromptStart + 1));
          Inc(I);
          // Only split when real (non-whitespace) content is glued directly
          // onto the prompt — e.g. a second prompt or command text arriving
          // in the same PTY chunk with no newline between them. A prompt's
          // own trailing padding ("PS D:\path> ") has nothing but whitespace
          // after '>' and must stay on the same line: inserting a break here
          // corrupted it (the synthetic CR then reset the write cursor to
          // column 0, so the very next character — that trailing space —
          // overwrote the prompt's first letter instead of being appended).
          if (I <= Len) and not CharInSet(AText[I], [#10, #13]) and
             (Trim(Copy(AText, I, MaxInt)) <> '') then
            Sb.Append(#13#10);
          Continue;
        end
        else
        begin
          I := PromptStart;
        end;
      end;

      Sb.Append(AText[I]);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

/// <summary>True if S has at least one char that is not part of a
/// backspace/erase idiom (BS, DEL, or a plain space used to blank a cell —
/// e.g. "\b\b" or "\b \b", both common single-char-erase echoes). A run of
/// only those is never "glued-on content"; only real text should count.</summary>
function HasPrintableChar(const S: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    if (S[I] >= ' ') and (Ord(S[I]) <> 127) and (S[I] <> ' ') then
      Exit(True);
end;

function LineHasInputAfterPrompt(const ALine: string): Boolean;
var
  PromptEnd: Integer;
begin
  PromptEnd := FindPromptProtectedEnd(ALine);
  Result := (PromptEnd > 0) and (Trim(Copy(ALine, PromptEnd + 1, MaxInt)) <> '');
end;

function TConsoleBuffer.AppendOutputEx(const AText: string; ACols, ARows: Integer;
  AIsLocalInput: Boolean): Integer;
var
  CurrLine, ProcessedText: string;
begin
  Result := 0;
  if AText = '' then
    Exit;

  FLock.Enter;
  try
    // Latches on the first real PTY-geometry call and never reverts (short
    // of a full Clear()) -- see EnableGridModeLocked / FGridEnabled.
    if (not FGridEnabled) and (ACols > 0) and (ARows > 0) then
      EnableGridModeLocked(ACols, ARows)
    else if FGridEnabled and (ACols > 0) and (ARows > 0) and
            ((ACols <> FActiveGrid.Cols) or (ARows <> FActiveGrid.Rows)) then
      // PTY output arrives on the reader thread; ResizePrimaryScreen is
      // called separately from the UI thread's SyncPtySize. If a resized
      // chunk of real output reaches here before that call lands, the grid
      // is still the OLD (narrower) size while conhost is already drawing
      // for the NEW one -- e.g. a 35-char prompt wraps mid-string onto a
      // second row because the grid still thinks it's ~35 cols wide,
      // confirmed via a byte-level trace (grid cursor ends at row+1 col0
      // right where the prompt text ends, with ACols=183 already claimed).
      // Reflowing here, keyed off the size this exact chunk already claims,
      // keeps the grid in sync regardless of which thread wins the race.
      FActiveGrid.Reflow(ACols, ARows, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);

    // Local keyboard/paste echo is never a shell prompt arriving over the PTY —
    // skip the "text looks like an incoming prompt" heuristics below, which
    // would otherwise force e.g. a pasted "D:\some\path" onto a new line just
    // because it happens to start with a drive letter like a real prompt.
    // Read FPendingEraseToEOL before parsing touches (and clears) it.
    // FixPromptNewlines mutates the actual byte stream fed to the parser
    // (it inserts a synthetic CRLF wherever it thinks a prompt has content
    // glued onto it) -- a legacy-only workaround for the old headless-pipe
    // backend's lack of real newlines. Grid mode must never let it run:
    // real conhost always follows a freshly-drawn prompt with an OSC
    // window-title sequence (ESC ]0;...BEL), which this heuristic mistakes
    // for "real command text glued onto the prompt" and splits with a
    // bogus synthetic newline -- confirmed via a byte-level trace: the
    // prompt's own cursor ended one row below where it visually stopped,
    // even though the grid was already the right width (so no wrap could
    // explain it) -- exactly the synthetic-CRLF's LF advancing the row.
    // Grid mode trusts the real byte stream's own CR/LF/CUP; it must not
    // also be fed a stream some other heuristic has silently rewritten.
    if AIsLocalInput or FGridEnabled then
      ProcessedText := AText
    else
      ProcessedText := FixPromptNewlines(AText, FPendingEraseToEOL);

    EnsureCurrentLineLocked;
    // FPlainLines can legitimately be empty in grid mode (nothing archived
    // yet -- see EnsureCurrentLineLocked); guard the index instead of
    // relying on the legacy-only ">= 1 entry" invariant. CurrLine's value
    // only matters below, where both consumers are already gated to
    // "not FGridEnabled" anyway.
    if FPlainLines.Count > 0 then
      CurrLine := TrimRight(FPlainLines[FPlainLines.Count - 1])
    else
      CurrLine := '';
    // Shell may emit "D:\path>next" without a leading newline when the prior
    // line already ends with '>'. FixPromptNewlines splits that case. Do NOT
    // start a new line for ordinary typed characters (local line-buffered echo).
    // Grid mode already tracks real cursor position from the byte stream's
    // own CUP/LF/CR (that's Фаза D's whole point), so these chunk-boundary
    // prompt-guessing heuristics -- built to compensate for the legacy
    // buffer's lack of a cursor -- are legacy-only; run them against a grid
    // session's frozen archive tail and they could force a bogus blank line
    // into history, disconnected from what the live grid actually shows.
    if (not FGridEnabled) and not AIsLocalInput and (CurrLine <> '') and (CurrLine[Length(CurrLine)] = '>') and
       (Length(ProcessedText) > 0) and not CharInSet(ProcessedText[1], [#10, #13]) and
       LooksLikeDrivePrompt(ProcessedText) then
      StartNewLineLocked;

    // PTY output after a submitted "D:\path>cmd" must not append on the same row.
    // Local input never hits this: pasting/typing more onto an already-started
    // command (e.g. "cd " then paste a path) must extend the same line. A pure
    // control-char burst (e.g. "\b\b" from two fast backspaces echoed in one
    // chunk) is never "glued-on content" either — it must edit the existing
    // line in place, not wipe it by forcing a new blank one.
    if (not FGridEnabled) and not AIsLocalInput and (CurrLine <> '') and LineHasInputAfterPrompt(CurrLine) and
       (Length(ProcessedText) > 0) and not CharInSet(ProcessedText[1], [#10, #13]) and
       ((Length(ProcessedText) > 1) or (ProcessedText[1] = ' ')) and
       HasPrintableChar(ProcessedText) then
      StartNewLineLocked;

    FAnsiParser.ParseText(
      ProcessedText,
      procedure(C: Char; Fg, Bg: TAlphaColor; Attrs: TCharCellAttributes)
      begin
        if FAltActive then
        begin
          FAltGrid.PutCell(C, Fg, Bg, Attrs);
          Exit;
        end;
        if FSuppressingBackspaceEcho then
          Exit;
        FPendingCR := False;
        if C = #9 then
          // Expand tabs to the next 8-cell stop; a literal #9 cell renders as a
          // blank and collapses all column-aligned output (dir, ls -la, source).
          TabLocked(Fg, Bg, Attrs)
        else
          PutCharLocked(C, Fg, Bg, Attrs);
      end,
      procedure
      begin
        if FAltActive then
        begin
          FAltGrid.NewLine(FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
          Exit;
        end;
        // Stale-guard: a real newline should never occur mid-erase-pattern;
        // if the expected show-cursor never arrived, drop the suppression
        // rather than let it leak into unrelated later output.
        FSuppressingBackspaceEcho := False;
        NewLineLocked2(FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
        FPendingCR := False;
      end,
      procedure
      begin
        if FAltActive then
        begin
          FAltGrid.CarriageReturn;
          Exit;
        end;
        if FSuppressingBackspaceEcho then
          Exit;
        CarriageReturnLocked;
      end,
      procedure
      begin
        if FAltActive then
        begin
          FAltGrid.Backspace;
          Exit;
        end;
        if FSuppressingBackspaceEcho then
          Exit;
        FPendingCR := False;
        BackspaceEraseLocked(AIsLocalInput);
      end,
      procedure(AElMode: Integer)
      begin
        if FAltActive then
        begin
          FAltGrid.EraseLine(AElMode, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
          Exit;
        end;
        if FSuppressingBackspaceEcho then
          Exit;
        FPendingCR := False;
        EraseLineLocked(AElMode, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
      end,
      procedure(AEdMode: Integer)
      begin
        if FAltActive then
        begin
          FAltGrid.EraseDisplay(AEdMode, FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
          Exit;
        end;
        if FSuppressingBackspaceEcho then
          Exit;
        // Mode is intentionally ignored either way -- ED always means a full
        // reset here (legacy default, and Фаза D's explicit decision to keep
        // it for grid mode too), not partial-ED semantics.
        FPendingCR := False;
        EraseDisplayLocked(AEdMode);
      end,
      procedure(ARow, ACol: Integer)
      begin
        if FAltActive then
        begin
          FAltGrid.MoveAbs(ARow, ACol);
          Exit;
        end;
        // Real cmd's CUP-based backspace-erase (ESC[row;colH, overwrite with
        // spaces, ESC[row;colH back) is swallowed wholesale here so it can't
        // move the grid cursor to the erase pattern's own position -- see
        // NotePendingLocalBackspace / FSuppressingBackspaceEcho.
        if FSuppressingBackspaceEcho then
          Exit;
        FPendingCR := False;
        CursorPosLocked(ARow, ACol);
      end,
      procedure(ADir: Char; ACount: Integer)
      begin
        if FAltActive then
        begin
          FAltGrid.MoveRel(ADir, ACount);
          Exit;
        end;
        FPendingCR := False;
        MoveRelLocked(ADir, ACount);
      end,
      procedure(ASave: Boolean)
      begin
        if FAltActive then
        begin
          if ASave then
            FAltGrid.SaveCursor
          else
            FAltGrid.RestoreCursor;
        end;
      end,
      procedure(AMode: Integer; ASet: Boolean)
      begin
        // The only callback that must act regardless of FAltActive -- it's
        // what flips the flag. 1049 and 47 are treated identically (enter/
        // exit the same grid, no distinct cursor save/restore for 1049) --
        // sufficient for vim/htop/less, the stage's actual target set.
        if (AMode = 1049) or (AMode = 47) then
        begin
          if ASet and not FAltActive then
          begin
            if (ACols > 0) and (ARows > 0) then
            begin
              FAltGrid.Alloc(ACols, ARows);
              FAltGrid.ClearAll(FAnsiParser.CurrentFg, FAnsiParser.CurrentBg);
              FAltActive := True;
            end;
            // else: safe no-op -- caller hasn't wired real geometry yet
            // (AppendOutput/AppendLocalInput's 1-arg wrappers pass 0,0).
          end
          else if (not ASet) and FAltActive then
            FAltActive := False;
          Exit;
        end;
        // Mode 25 (cursor visibility): real conhost line-editing brackets its
        // CUP-based erase echo in hide/show-cursor (ESC[?25l ... ESC[?25h).
        // Outside alt-screen, use that bracket to swallow the echo for a
        // backspace we already applied locally (see NotePendingLocalBackspace);
        // otherwise mode 25 stays a no-op, matching today's behavior.
        if (AMode = 25) and not FAltActive then
        begin
          if (not ASet) and FPendingLocalBackspace then
          begin
            FSuppressingBackspaceEcho := True;
            FPendingLocalBackspace := False;
          end
          else if ASet and FSuppressingBackspaceEcho then
            FSuppressingBackspaceEcho := False;
        end;
        // Mode 1000+ (mouse reporting): no-op for v1, matches "mouse
        // optional/later" from the stage's own checklist.
      end
    );
    TrimLocked(Result);
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.GetScrollMetrics(AViewH: Integer; out ATotal, ATop: Integer);
begin
  FLock.Enter;
  try
    ATotal := LineCountLocked;
    if (ATotal > 0) and IsBlankLine(ATotal - 1) then
      Dec(ATotal);
    if AViewH < 1 then
      AViewH := 1;
    if FFollowTail then
      ATop := Max(ATotal - AViewH, 0)
    else
      ATop := EnsureRange(FScroll, 0, Max(ATotal - AViewH, 0));
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetVisibleLines(AViewH: Integer; out ATotal, ATop: Integer): TArray<string>;
var
  I, Count: Integer;
begin
  FLock.Enter;
  try
    ATotal := LineCountLocked;
    if (ATotal > 0) and IsBlankLine(ATotal - 1) then
      Dec(ATotal);
    if AViewH < 1 then
      AViewH := 1;
    if FFollowTail then
      ATop := Max(ATotal - AViewH, 0)
    else
      ATop := EnsureRange(FScroll, 0, Max(ATotal - AViewH, 0));
    Count := Min(AViewH, Max(ATotal - ATop, 0));
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
      Result[I] := TrimRight(GetLineLocked(ATop + I));
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetVisibleRows(AViewH: Integer; out ATotal, ATop: Integer): TArray<TConsoleRow>;
var
  I, Count: Integer;
begin
  FLock.Enter;
  try
    ATotal := LineCountLocked;
    if (ATotal > 0) and IsBlankLine(ATotal - 1) then
      Dec(ATotal);
    if AViewH < 1 then
      AViewH := 1;
    if FFollowTail then
      ATop := Max(ATotal - AViewH, 0)
    else
      ATop := EnsureRange(FScroll, 0, Max(ATotal - AViewH, 0));
    Count := Min(AViewH, Max(ATotal - ATop, 0));
    SetLength(Result, Count);
    for I := 0 to Count - 1 do
      Result[I] := GetRowLocked(ATop + I);
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.LineCount: Integer;
begin
  FLock.Enter;
  try
    Result := LineCountLocked;
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetLine(AIndex: Integer): string;
begin
  FLock.Enter;
  try
    Result := GetLineLocked(AIndex);
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetRow(AIndex: Integer): TConsoleRow;
begin
  FLock.Enter;
  try
    Result := GetRowLocked(AIndex);
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetInputCursor(out ALineIndex, ACol: Integer): Boolean;
begin
  Result := False;
  ALineIndex := 0;
  ACol := 0;
  FLock.Enter;
  try
    if LineCountLocked = 0 then
      Exit;
    if FGridEnabled then
    begin
      ALineIndex := FPlainLines.Count + FActiveGrid.CursorRow;
      ACol := FActiveGrid.CursorCol;
    end
    else
    begin
      ALineIndex := FPlainLines.Count - 1;
      ACol := FCursorCol;
    end;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TConsoleBuffer.GetInputAfterPrompt(AIndex: Integer): string;
var
  I, PromptEnd, LineIdx, Total: Integer;
  Line, Prev: string;
begin
  Result := '';
  FLock.Enter;
  try
    Total := LineCountLocked;
    if AIndex < 0 then
      LineIdx := Total - 1
    else
      LineIdx := AIndex;
    if (LineIdx < 0) or (LineIdx >= Total) then
      Exit;

    // Text typed on the same line as the prompt (D:\path>dir).
    Line := GetLineLocked(LineIdx);
    PromptEnd := FindPromptProtectedEnd(Line);
    if PromptEnd > 0 then
    begin
      Result := Copy(Line, PromptEnd + 1, MaxInt);
      if Trim(Result) <> '' then
        Exit;
    end;

    // Local echo on the line after a bare prompt (shell emitted "D:\path>" + CRLF).
    if (LineIdx >= 1) and (LineIdx - 1 >= FInputLineStart) then
    begin
      Prev := GetLineLocked(LineIdx - 1);
      PromptEnd := FindPromptProtectedEnd(Prev);
      if (PromptEnd > 0) and (Trim(Copy(Prev, PromptEnd + 1, MaxInt)) = '') then
      begin
        Result := Line;
        Exit;
      end;
    end;

    // Scan upward for any in-progress input after a prompt — never past the
    // last CommitInputLine boundary. Lines before it are submitted history;
    // an old "PS ...> ls" still sitting in scrollback must never be mistaken
    // for input the user is currently typing (see FInputLineStart).
    if AIndex < 0 then
      for I := Total - 1 downto Max(0, FInputLineStart) do
      begin
        Line := GetLineLocked(I);
        PromptEnd := FindPromptProtectedEnd(Line);
        if PromptEnd > 0 then
        begin
          Result := Copy(Line, PromptEnd + 1, MaxInt);
          if Trim(Result) <> '' then
            Exit;
        end;
        if (I >= 1) then
        begin
          Prev := GetLineLocked(I - 1);
          PromptEnd := FindPromptProtectedEnd(Prev);
          if (PromptEnd > 0) and (Trim(Copy(Prev, PromptEnd + 1, MaxInt)) = '') and
             (Trim(Line) <> '') then
          begin
            Result := Line;
            Exit;
          end;
        end;
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ScrollBy(ADelta, AViewH: Integer);
var
  Total, Top: Integer;
begin
  if ADelta = 0 then
    Exit;
  FLock.Enter;
  try
    GetScrollMetrics(AViewH, Total, Top);
    Top := EnsureRange(Top + ADelta, 0, Max(Total - AViewH, 0));
    FScroll := Top;
    FFollowTail := (Top >= Max(Total - AViewH, 0));
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ScrollTo(ATop, AViewH: Integer);
var
  Total, DummyTop: Integer;
begin
  FLock.Enter;
  try
    GetScrollMetrics(AViewH, Total, DummyTop);
    FScroll := EnsureRange(ATop, 0, Max(Total - AViewH, 0));
    FFollowTail := (FScroll >= Max(Total - AViewH, 0));
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ScrollToStart;
begin
  FLock.Enter;
  try
    FScroll := 0;
    FFollowTail := False;
  finally
    FLock.Leave;
  end;
end;

procedure TConsoleBuffer.ScrollToEnd;
begin
  FLock.Enter;
  try
    FFollowTail := True;
  finally
    FLock.Leave;
  end;
end;

end.
