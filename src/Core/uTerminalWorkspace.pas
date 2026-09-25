unit uTerminalWorkspace;

{ Stage 21 Terminal Workspace: full-area MDI window with its own shell session,
  raw keyboard → pipes, scrollback/selection chrome.
  Inherits buffer, PTY, selection, mouse and clipboard from TBaseConsoleWindow.
  Unique to this class:
    - IsHostPassthrough: blocks host-level hotkeys (Ctrl+Tab, zoom, F10, Alt+X).
    - Full raw PTY passthrough for all printable characters.
    - Profile-specific Backspace (#127 WSL / #8 Windows) and local echo (cmd).
    - Status bar with profile name.
    - Auto-close on process exit (DoCloseWorkspace). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.Rtti,
  Winapi.Windows,
  FMX.Platform,
  uTerminalTypes, uThemeTypes, uTerminalWindow, uConsoleBuffer, uConPty,
  uShellProfiles, uDialogTypes, uDialogHost, uBaseConsoleWindow, uStrings;

type
  TTerminalWorkspaceWindow = class(TBaseConsoleWindow)
  private
    FDragStartRow: Integer;
    FDragStartCol: Integer;
    FCloseOnExit: Boolean;
    procedure DoCloseWorkspace;
    /// <summary>Esc: confirm before killing the shell. Unlike CloseWorkspace
    /// this is asynchronous — the tab dies only once the dialog answers.</summary>
    procedure AskCloseWorkspace;
    procedure CloseConfirmCommand(const AControlId, AValuesJson: string);
    function  IsHostPassthrough(AKey: Word; AShift: TShiftState;
                AKeyChar: Char): Boolean;
  protected
    procedure SyncTitle; override;
    procedure ProcessExited(AExitCode: Cardinal); override;
    procedure AppendOutput(const AText: string); override;
    procedure AppendLocalInput(const AText: string); override;
    function ViewHeight: Integer; override;
    function TextWidth:  Integer; override;
    procedure DrawContent; override;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal);
    function  Start(const AProfileId, ACwd: string): Boolean;
    procedure CloseWorkspace;
    function  HandleInput(var AKey: Word; AShift: TShiftState;
                var AKeyChar: Char): Boolean; override;
    function  HandleClick(ALocalCol, ALocalRow: Integer;
                AShift: TShiftState = []): Boolean;
    function  HandleMouseDown(ALocalCol, ALocalRow: Integer;
                AShift: TShiftState): Boolean;
    function  HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
    function  HandleMouseUp: Boolean;
    // When True (default), the shell exiting closes this tab, matching the
    // longstanding Ctrl+Shift+N terminal-tab behavior. When False, the tab
    // stays open (scrollback + exit status) instead of auto-closing.
    property CloseOnExit: Boolean read FCloseOnExit write FCloseOnExit;
    // Inherited: ProfileId, Running, WorkingDir, OnCloseRequest, OnContentChanged
  end;

implementation

const
  cTextFg   = TAlphaColor($FFE0E0E0);
  cHintFg   = TAlphaColor($FFF0F000);
  cCmdBg    = TAlphaColor($FF000000);
  cSelFg    = TAlphaColor($FF000000);
  cSelBg    = TAlphaColor($FFE8C000);
  cStatusFg = TAlphaColor($FFAAAAAA);

{ Profile-specific helpers live in uShellProfiles. }

function IsAtPromptBoundary(const ALine: string): Boolean;
var
  S: string;
begin
  S      := TrimRight(ALine);
  Result := (S <> '') and CharInSet(S[Length(S)], ['>', '$', '#']);
end;

{ ---- Constructor ----------------------------------------------------------- }

constructor TTerminalWorkspaceWindow.Create(const ATheme: IThemeRenderer;
  AId: Cardinal);
begin
  inherited Create(ATheme, AId, cShellProfileCmd);
  LayoutBottomMargin := 0;
  Title              := T('ui.terminal.title', 'Terminal');
  FCloseOnExit       := True;
end;

{ ---- Title ----------------------------------------------------------------- }

procedure TTerminalWorkspaceWindow.SyncTitle;
begin
  Title := T('ui.window.terminalProfile', 'Terminal — %s', [ShellProfileTitle(ProfileId)]);
  if Running then
    Title := Title + ' ' + T('ui.window.running', '[running]');
end;

{ ---- View geometry --------------------------------------------------------- }

function TTerminalWorkspaceWindow.ViewHeight: Integer;
begin
  // Top border + bottom status row + bottom border.
  Result := Max(Area.Height - 4, 1);
end;

function TTerminalWorkspaceWindow.TextWidth: Integer;
begin
  Result := Max(Area.Width - 3, 4);
end;

{ ---- Output / lifecycle ---------------------------------------------------- }

procedure TTerminalWorkspaceWindow.ProcessExited(AExitCode: Cardinal);
begin
  FRunning := False;
  FHistory.AppendStatus(Format('[MTN2] process exited (%d)', [AExitCode]));
  SyncTitle;
  NotifyHost;
  if FCloseOnExit then
    DoCloseWorkspace;
end;

procedure TTerminalWorkspaceWindow.DoCloseWorkspace;
begin
  if PendingClose then
    Exit;
  PendingClose := True;
  DoClose;
end;

procedure TTerminalWorkspaceWindow.CloseWorkspace;
begin
  DoCloseWorkspace;
end;

procedure TTerminalWorkspaceWindow.AskCloseWorkspace;
begin
  // No dialog host (shouldn't happen) — fall back to the old direct close
  // rather than leaving Esc dead.
  if not Assigned(FDialog) then
  begin
    DoCloseWorkspace;
    Exit;
  end;
  if FDialog.Visible then
    Exit;
  FDialog.Open(BuildConfirmDialog(T('ui.terminal.title', 'Terminal'),
    T('ui.terminal.confirmClose', 'Close console?')),
    CloseConfirmCommand);
  NotifyHost;
end;

procedure TTerminalWorkspaceWindow.CloseConfirmCommand(const AControlId,
  AValuesJson: string);
var
  Confirmed: Boolean;
begin
  // Read the id before Close: it points into FDecl.Controls, which Close
  // releases (see TDialogHost.FireCommand). Harmless now that FireCommand
  // holds its own reference, but keep the safe order explicit.
  Confirmed := DialogCmdIsOk(AControlId);
  if Assigned(FDialog) then
    FDialog.Close;
  if Confirmed then
    // Deferred rather than a direct DoCloseWorkspace: this runs *inside*
    // FDialog.HandleInput/HandleClick, and those callers already turn
    // PendingClose into the real close right after the dialog returns.
    // Tearing the window down mid-callback would unwind under them.
    PendingClose := True
  else
    NotifyHost;
end;

{ ---- Start ----------------------------------------------------------------- }

function TTerminalWorkspaceWindow.Start(const AProfileId, ACwd: string): Boolean;
var
  Gen: Integer;
  OnOut: TConPtyOutputEvent;
  OnExitEvt: TConPtyExitEvent;
begin
  Result     := False;
  FProfileId := NormalizeShellProfileId(AProfileId);
  WorkingDir := Trim(ACwd);

  if not Assigned(FPty) then
    FPty := TConPtySession.Create;
  if FPty.IsRunning then
    FPty.Terminate;

  Inc(FCallbackGen);
  Gen      := FCallbackGen;
  FRunning := True;
  SyncTitle;
  NotifyHost;

  OnOut :=
    procedure(const AChunk: string)
    begin
      if not Alive or (Gen <> FCallbackGen) then
        Exit;
      AppendOutput(AChunk);
    end;
  OnExitEvt :=
    procedure(AExitCode: DWORD)
    begin
      if not Alive or (Gen <> FCallbackGen) then
        Exit;
      ProcessExited(AExitCode);
    end;

  FPty.OnOutput := OnOut;
  FPty.OnExit   := OnExitEvt;
  // Profile selects UTF-8 (ps/pwsh/wsl) vs OEM (cmd) decode + input encoding.
  FPty.ProfileId := FProfileId;
  if not FPty.StartShell(FProfileId, WorkingDir, PtyCols, PtyRows) then
  begin
    FRunning := False;
    if FPty.LastError <> '' then
      FHistory.AppendStatus('[MTN2] ' + FPty.LastError)
    else
      FHistory.AppendStatus('[MTN2] Failed to start shell');
    SyncTitle;
    NotifyHost;
    Exit;
  end;

  SendInitCommand(ProfileInitCommand(FProfileId));
  FHistory.AppendStatus('[MTN2] ' + ShellProfileTitle(FProfileId) + ' ready');
  SyncTitle;
  Result := True;
end;

{ ---- AppendOutput override: follow tail cursor ----------------------------- }

procedure TTerminalWorkspaceWindow.AppendOutput(const AText: string);
var
  Deleted: Integer;
begin
  Deleted := FHistory.AppendOutputEx(AText, PtyCols, PtyRows);
  AdjustSelectionForTrim(Deleted);
  if not AltScreenActive and FHistory.FollowTail then
  begin
    FCursorRow := Max(FHistory.LineCount - 1, 0);
    FCursorCol := Length(FHistory.GetLine(FCursorRow));
  end;
  NotifyHostThrottled;
end;

procedure TTerminalWorkspaceWindow.AppendLocalInput(const AText: string);
var
  Deleted: Integer;
begin
  Deleted := FHistory.AppendLocalInput(AText);
  AdjustSelectionForTrim(Deleted);
  if FHistory.FollowTail then
  begin
    FCursorRow := Max(FHistory.LineCount - 1, 0);
    FCursorCol := Length(FHistory.GetLine(FCursorRow));
  end;
  NotifyHostThrottled;
end;

{ ---- Drawing --------------------------------------------------------------- }

procedure TTerminalWorkspaceWindow.DrawContent;
var
  W, H, ViewH, Total, Top, I, Y, TextW, AbsCol, LineIdx, CurRow, CurCol: Integer;
  Rows: TArray<TConsoleRow>;
  Row: TConsoleRow;
  Cell: TCharCell;
  Ch: Char;
  Fg, Bg, TempColor: TAlphaColor;
  ShowInputCursor: Boolean;
begin
  W := Area.Width;
  H := Area.Height;
  if (W < 8) or (H < 5) then
    Exit;

  ViewH := ViewHeight;
  TextW := TextWidth;

  if AltScreenActive then
  begin
    FillGridRect(Buffer, 1, 1, W - 3, H - 3, ' ', cTextFg, cCmdBg);
    DrawAltScreenGrid(TextW, ViewH);
    if Assigned(FDialog) and FDialog.Visible then
      FDialog.Draw(Buffer, W, H);
    Exit;
  end;

  Rows  := FHistory.GetVisibleRows(ViewH, Total, Top);
  FillGridRect(Buffer, 1, 1, W - 3, H - 3, ' ', cTextFg, cCmdBg);

  CurRow := -1;
  CurCol := 0;
  // Real PTY/grid cursor position (Phase D primary-buffer grid mode), not
  // "end of last visible row" -- the shell prompt can land anywhere on the
  // grid, mirrors TConsoleWindow.DrawContent's cursor handling.
  ShowInputCursor := FCursorVisible and FHistory.GetInputCursor(CurRow, CurCol);

  for I := 0 to High(Rows) do
  begin
    Y := 1 + I;
    if Y > H - 3 then
      Break;
    LineIdx := Top + I;
    Row     := Rows[I];
    for AbsCol := 0 to TextW - 1 do
    begin
      if AbsCol < Length(Row) then
      begin
        Cell := Row[AbsCol];
        Ch   := Cell.CharValue;
        Fg   := Cell.FgColor;
        Bg   := Cell.BgColor;
        if ccaReverse in Cell.Attributes then
        begin
          TempColor := Fg; Fg := Bg; Bg := TempColor;
        end;
      end
      else
      begin
        Ch := ' '; Fg := cTextFg; Bg := cCmdBg;
      end;
      if IsCellSelected(LineIdx, AbsCol) then
      begin
        Fg := cSelFg; Bg := cSelBg;
      end;
      DrawGridChar(Buffer, 1 + AbsCol, Y, Ch, Fg, Bg);
      if ShowInputCursor and (LineIdx = CurRow) and (AbsCol = CurCol) then
        MarkGridInsertCaret(Buffer, 1 + AbsCol, Y);
    end;
  end;

  if Total = 0 then
    PutGridText(Buffer, 1, 1, 'Starting shell…', cHintFg, cCmdBg);

  DrawScrollBar(Total, Top, ViewH, 1, H - 3);
  // Status + hotkey hint moved to the shared Dual Panel status/F-key bars
  // (TDualPanelWindow.BuildPanelStatusSegments / fbcTerminal) when embedded
  // as a workspace tab.

  if Assigned(FDialog) and FDialog.Visible then
    FDialog.Draw(Buffer, W, H);
end;

{ ---- Host-passthrough filter ----------------------------------------------- }

function TTerminalWorkspaceWindow.IsHostPassthrough(AKey: Word;
  AShift: TShiftState; AKeyChar: Char): Boolean;
begin
  Result := False;
  // Ctrl+Tab / Ctrl+Shift+Tab — Dual Panel workspace cycle.
  if (AKey = vkTab) and (ssCtrl in AShift) then
    Exit(True);
  // New terminal / zoom / quit — host or Dual Panel keymap.
  if (ssCtrl in AShift) and (ssShift in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('N')) or (AKey = Ord('n'))) then
    Exit(True);
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = vkAdd) or (AKey = vkSubtract) or (AKey = vkNumpad0) or
      (AKeyChar = '+') or (AKeyChar = '=') or (AKeyChar = '-') or
      (AKeyChar = '0')) then
    Exit(True);
  if AKey = vkF10 then
    Exit(True);
  if (ssAlt in AShift) and ((AKey = Ord('X')) or (AKey = Ord('x'))) then
    Exit(True);
end;

{ ---- Input ----------------------------------------------------------------- }

function TTerminalWorkspaceWindow.HandleInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;

  function GetCharFromVK: Char;
  begin
    Result := #0;
    if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
    begin
      if ssShift in AShift then
        Result := Char(AKey)
      else
        Result := Char(AKey + 32);
    end
    else if (AKey >= Ord('0')) and (AKey <= Ord('9')) then
      Result := Char(AKey)
    else if AKey = 32 then
      Result := ' ';
  end;

var
  ViewH: Integer;
begin
  // Let host handle its own global hotkeys first.
  if IsHostPassthrough(AKey, AShift, AKeyChar) then
    Exit(False);

  Result := True;
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if HandleCmdHistoryFilterInput(AKey, AShift, AKeyChar) then
      Exit(True);
    Result := FDialog.HandleInput(AKey, AShift, AKeyChar);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseWorkspace;
    end;
    Exit(Result);
  end;

  if PendingClose then
  begin
    PendingClose := False;
    DoCloseWorkspace;
    Exit(True);
  end;
  ViewH := ViewHeight;

  // Alt+F8 — command history picker (matches Dual Panel's kaCmdHistory);
  // selecting an entry runs it immediately in this terminal tab.
  if (ssAlt in AShift) and not (ssCtrl in AShift) and not (ssShift in AShift) and
     (AKey = vkF8) then
  begin
    OpenCmdHistoryDialog;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+A — select all.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('A')) or (AKey = Ord('a')) or
      (AKeyChar = 'a') or (AKeyChar = 'A')) then
  begin
    SelectAll;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+C — copy or interrupt.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('C')) or (AKey = Ord('c')) or
      (AKeyChar = 'c') or (AKeyChar = 'C')) then
  begin
    if HasSelection then
      CopySelection
    else if Running then
      Interrupt;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+Insert — copy selection (no interrupt fallback, unlike Ctrl+C).
  if (AKey = vkInsert) and (ssCtrl in AShift) and not (ssShift in AShift) and
     not (ssAlt in AShift) then
  begin
    CopySelection;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+V / Shift+Insert — paste.
  if ((ssCtrl in AShift) and not (ssAlt in AShift) and
      ((AKey = Ord('V')) or (AKey = Ord('v')) or
       (AKeyChar = 'v') or (AKeyChar = 'V'))) or
     ((AKey = vkInsert) and (ssShift in AShift) and not (ssCtrl in AShift) and
      not (ssAlt in AShift)) then
  begin
    PasteClipboard;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Alt-screen (TUI app running): forward navigation keys to the PTY instead
  // of the local-scrollback/selection handling below, which would otherwise
  // steal arrows/PgUp/PgDn away from vim/htop/less.
  if HandleAltScreenNav(AKey, AShift) then
    Exit;

  // Shift+arrows — extend selection (no PTY passthrough).
  if (ssShift in AShift) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    case AKey of
      vkLeft:  begin MoveSelCursor(0, -1, True);     AKey := 0; Exit; end;
      vkRight: begin MoveSelCursor(0,  1, True);     AKey := 0; Exit; end;
      vkUp:    begin MoveSelCursor(-1, 0, True);     AKey := 0; Exit; end;
      vkDown:  begin MoveSelCursor( 1, 0, True);     AKey := 0; Exit; end;
      vkPrior: begin MoveSelCursor(-ViewH, 0, True); AKey := 0; Exit; end;
      vkNext:  begin MoveSelCursor( ViewH, 0, True); AKey := 0; Exit; end;
      vkHome:
        begin SetCursorPos(CursorRow, 0, True); AKey := 0; Exit; end;
      vkEnd:
        begin
          SetCursorPos(CursorRow, Length(FHistory.GetLine(CursorRow)), True);
          AKey := 0; Exit;
        end;
    end;
  end;

  // cmd pipe: local line editing (see HandleLineBufferedPtyInput). Never
  // during alt-screen: a raw full-screen app needs character-at-a-time
  // input, not keystrokes buffered until Enter.
  if not AltScreenActive and HandleLineBufferedPtyInput(AKey, AShift, AKeyChar) then
    Exit;

  // Terminal-specific key bindings (raw PTY profiles).
  case AKey of
    vkEscape:
      begin
        if HasSelection then
        begin
          ClearSelection;
          NotifyHost;
        end
        else
          AskCloseWorkspace;
        AKey := 0;
        Exit;
      end;
    vkReturn:
      begin
        NoteCommandSubmitted(FHistory.GetInputAfterPrompt);
        SendRaw(ProfileReturnSeq(ProfileId));
        AKey := 0; AKeyChar := #0;
        Exit;
      end;
    vkBack:
      begin
        // Only outside alt-screen: a TUI app (vim/htop) manages its own
        // alt-grid via real PTY output and must not have a locally-simulated
        // erase interfering with it.
        if (not AltScreenActive) and ProfileNeedsBackspaceWorkaround(ProfileId) then
        begin
          // Real Windows conhost line-editing erases via CUP, which the
          // primary buffer can't map onto conhost's coordinate system (see
          // uConsoleBuffer.NotePendingLocalBackspace) -- erase locally on
          // keypress and swallow the resulting echo instead.
          AppendLocalInput(#8);
          FHistory.NotePendingLocalBackspace;
        end;
        SendRaw(ProfileBackspaceChar(ProfileId));
        AKey := 0; AKeyChar := #0;
        Exit;
      end;
    vkTab:
      begin
        SendRaw(#9);
        AKey := 0; AKeyChar := #0;
        Exit;
      end;
    vkLeft:
      begin SendRaw(#27'[D'); AKey := 0; Exit; end;
    vkRight:
      begin SendRaw(#27'[C'); AKey := 0; Exit; end;
    vkUp:
      begin
        // Prefer shell history when following tail; else scroll.
        if FHistory.FollowTail and Running then
          SendRaw(#27'[A')
        else
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(-1, ViewH);
          NotifyHost;
        end;
        AKey := 0;
        Exit;
      end;
    vkDown:
      begin
        if FHistory.FollowTail and Running then
          SendRaw(#27'[B')
        else
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(1, ViewH);
          NotifyHost;
        end;
        AKey := 0;
        Exit;
      end;
    vkPrior:
      begin
        FHistory.FollowTail := False;
        FHistory.ScrollBy(-ViewH, ViewH);
        NotifyHost;
        AKey := 0;
        Exit;
      end;
    vkNext:
      begin
        FHistory.FollowTail := False;
        FHistory.ScrollBy(ViewH, ViewH);
        NotifyHost;
        AKey := 0;
        Exit;
      end;
    vkHome:
      begin
        if ssCtrl in AShift then
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollToStart;
          NotifyHost;
        end
        else
          SendRaw(#27'[H');
        AKey := 0;
        Exit;
      end;
    vkEnd:
      begin
        if ssCtrl in AShift then
        begin
          FHistory.ScrollToEnd;
          NotifyHost;
        end
        else
          SendRaw(#27'[F');
        AKey := 0;
        Exit;
      end;
    vkDelete:
      begin SendRaw(#27'[3~'); AKey := 0; Exit; end;
  end;

  // Printable characters → raw PTY.
  if (AKeyChar < ' ') and not (ssCtrl in AShift) and not (ssAlt in AShift) then
    AKeyChar := GetCharFromVK;

  if (AKeyChar >= ' ') and (AKeyChar <> #127) and
     not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    SendRaw(AKeyChar);
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  Result := False;
end;

{ ---- Mouse ----------------------------------------------------------------- }

function TTerminalWorkspaceWindow.HandleClick(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  Row, Col, ViewH, Total, Top: Integer;
begin
  if not Alive or PendingClose then
    Exit(True);

  if Assigned(FDialog) and FDialog.Visible then
  begin
    Result := FDialog.HandleClick(ALocalCol, ALocalRow, AShift);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseWorkspace;
    end;
    Exit(Result);
  end;

  Result := True;
  ViewH  := ViewHeight;
  if ALocalCol = Area.Width - 2 then
  begin
    FHistory.GetScrollMetrics(ViewH, Total, Top);
    if ALocalRow = 1 then
      FHistory.ScrollBy(-1, ViewH)
    else if ALocalRow = Area.Height - 3 then
      FHistory.ScrollBy(1, ViewH);
    FHistory.FollowTail := False;
    NotifyHost;
    Exit;
  end;
  if HitTextCell(ALocalCol, ALocalRow, Row, Col) then
  begin
    ClearSelection;
    FCursorRow := Row;
    FCursorCol := Col;
    FHistory.FollowTail := False;
    NotifyHost;
  end;
end;

function TTerminalWorkspaceWindow.HandleMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
var
  Row, Col: Integer;
begin
  if not Alive or PendingClose then
    Exit(True);

  if Assigned(FDialog) and FDialog.Visible then
  begin
    Result := FDialog.HandleClick(ALocalCol, ALocalRow, AShift);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseWorkspace;
    end;
    Exit(Result);
  end;

  Result := False;
  if not HitTextCell(ALocalCol, ALocalRow, Row, Col) then
    Exit;
  Result          := True;
  if ssShift in AShift then
    FClicks.Reset
  else if FClicks.Hit(ALocalCol, ALocalRow) > 1 then
  begin
    // Double click = word, the next quick click = whole line.
    FMouseSelecting := False;
    SelectClickRange(Row, Col, FClicks.Count = 3);
    Exit;
  end;
  FMouseSelecting := True;
  FDragStartRow   := Row;
  FDragStartCol   := Col;
  FHistory.FollowTail := False;
  if ssShift in AShift then
    SetCursorPos(Row, Col, True)
  else
  begin
    ClearSelection;
    FCursorRow := Row;
    FCursorCol := Col;
    NotifyHost;
  end;
end;

function TTerminalWorkspaceWindow.HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Col: Integer;
begin
  if not Alive or PendingClose then
    Exit(False);
  Result := FMouseSelecting;
  if not FMouseSelecting then
    Exit;
  if HitTextCell(ALocalCol, ALocalRow, Row, Col) then
  begin
    if (Row <> FDragStartRow) or (Col <> FDragStartCol) then
    begin
      if FSelAnchorRow < 0 then
      begin
        FSelAnchorRow := FDragStartRow;
        FSelAnchorCol := FDragStartCol;
      end;
    end;
    FCursorRow := Row;
    FCursorCol := Col;
    NotifyHost;
  end;
end;

function TTerminalWorkspaceWindow.HandleMouseUp: Boolean;
begin
  if not Alive or PendingClose then
    Exit(False);
  Result          := FMouseSelecting;
  FMouseSelecting := False;
end;

end.
