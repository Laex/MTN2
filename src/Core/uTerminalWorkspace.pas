unit uTerminalWorkspace;

{ Terminal Workspace: full-area MDI window with its own shell session,
  raw keyboard -> pipes, scrollback/selection chrome.
  Inherits buffer, PTY, selection, mouse and clipboard from TBaseConsoleWindow.
  Unique to this class:
    - IsTerminalHostPassthrough: keeps the keymap's Global keys from the shell.
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
  uShellProfiles, uDialogTypes, uDialogHost, uBaseConsoleWindow, uStrings,
  uKeyChord, uKeymap;

type
  TTerminalWorkspaceWindow = class(TBaseConsoleWindow)
  private
    FDragStartRow: Integer;
    FDragStartCol: Integer;
    FCloseOnExit: Boolean;
    procedure DoCloseWorkspace;
    /// <summary>A dialog button released after the click or key returned:
    /// the close its command asked for, as HandleInput / HandleClick do.</summary>
    procedure DialogDeferredCommand(Sender: TObject);
    /// <summary>Esc: confirm before killing the shell. Unlike CloseWorkspace
    /// this is asynchronous - the tab dies only once the dialog answers.</summary>
    procedure AskCloseWorkspace;
    procedure CloseConfirmCommand(const AControlId, AValuesJson: string);
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
    /// <summary>Types ACommand and Enter into the tab's shell.</summary>
    procedure SendCommand(const ACommand: string);
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

/// <summary>Keys the terminal must not send to the shell: the keymap's Global
/// actions (Ctrl+Tab, Ctrl+Shift+N, Ctrl+0, Alt+X, ...) not bound in the
/// terminal's own contexts. The host runs them before the terminal sees the
/// key; this keeps e.g. Ctrl+Tab from ever reaching the shell as Tab.</summary>
function IsTerminalHostPassthrough(const K: TKeyChord): Boolean;

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
  FDialog.OnDeferredCommand := DialogDeferredCommand;
end;

procedure TTerminalWorkspaceWindow.DialogDeferredCommand(Sender: TObject);
begin
  if PendingClose then
  begin
    PendingClose := False;
    DoCloseWorkspace;
  end;
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
  // No dialog host (shouldn't happen) - close directly rather than leaving
  // Esc dead.
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
begin
  Result     := False;
  FProfileId := NormalizeShellProfileId(AProfileId);
  WorkingDir := Trim(ACwd);

  if not StartShellSession then
    Exit;

  FHistory.AppendStatus('[MTN2] ' + ShellProfileTitle(FProfileId) + ' ready');
  SyncTitle;
  Result := True;
end;

procedure TTerminalWorkspaceWindow.SendCommand(const ACommand: string);
var
  Line, Id: string;
begin
  if (Trim(ACommand) = '') or not Assigned(FPty) or not FPty.IsRunning then
    Exit;
  Line := ACommand;
  Id := NormalizeShellProfileId(FProfileId);
  if (Id = cShellProfilePowerShell) or (Id = cShellProfilePwsh) then
    Line := PsPipeSafeCommand(Line);
  FPty.WriteInput(Line + ProfileReturnSeq(FProfileId));
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
  // Real PTY/grid cursor position (primary-buffer grid mode), not
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

function IsTerminalHostPassthrough(const K: TKeyChord): Boolean;
begin
  Result := MatchGlobalActionIn(ActiveKeymap, [kcTerminal, kcShell], K.Key, K.Ch,
    K.Mods) <> kaNone;
end;

{ ---- Input ----------------------------------------------------------------- }

function TTerminalWorkspaceWindow.HandleInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;

  function GetCharFromVK: Char;
  begin
    Result := #0;
    if (AKey >= vkA) and (AKey <= vkZ) then
    begin
      if ssShift in AShift then
        Result := Char(AKey)
      else
        Result := Char(Ord('a') + AKey - vkA);
    end
    else if (AKey >= vk0) and (AKey <= vk9) then
      Result := Char(AKey)
    else if AKey = vkSpace then
      Result := ' ';
  end;

var
  K: TKeyChord;
  ViewH: Integer;
begin
  K := TKeyChord.Make(AKey, AKeyChar, AShift);
  // Let host handle its own global hotkeys first.
  if IsTerminalHostPassthrough(K) then
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

  // Alt+F8, Ctrl+A, Ctrl+C (copy or interrupt), Ctrl+Insert, Ctrl+V /
  // Shift+Insert.
  if HandleSharedKeys(AKey, AShift, AKeyChar) then
    Exit;

  // Alt-screen (TUI app running): forward navigation keys to the PTY instead
  // of the local-scrollback/selection handling below, which would otherwise
  // steal arrows/PgUp/PgDn away from vim/htop/less.
  if HandleAltScreenNav(AKey, AShift) then
    Exit;

  // Shift+arrows - extend selection (no PTY passthrough).
  if HandleSelectionKeys(AKey, AShift) then
    Exit;

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
        if ssCtrl in K.Mods then
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
        if ssCtrl in K.Mods then
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

  // Printable characters -> raw PTY.
  if K.Mods * [ssCtrl, ssAlt] <> [] then
    Exit(False);
  if AKeyChar < ' ' then
    AKeyChar := GetCharFromVK;
  if (AKeyChar >= ' ') and (AKeyChar <> #127) then
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
