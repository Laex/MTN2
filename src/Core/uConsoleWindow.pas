unit uConsoleWindow;

{ MDI Console window: scrollback + persistent shell. First command comes from
  the Dual Panel cmdline; further input is typed at the shell prompt in this window.
  Bottom frame sits above the shared F-keys / status (Dual Panel draws those).
  Inherits buffer, PTY, selection, mouse and clipboard from TBaseConsoleWindow.
  Unique to this class:
    - Persistent-shell start via EnsureShell (profile-aware); pre-warmed at
      app launch, so it is usually already running by the time it's shown.
    - OnBackToPanels / OnDismissConsole / OnFocusCommandLine events.
    - Esc → panels (never stops the shell/command — Ctrl+C does that);
      Ctrl+O → panels; F10 → close.
    - DrawAppStatusHint (running indicator). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, Winapi.Windows,
  uTerminalTypes, uThemeTypes, uTerminalWindow, uConsoleBuffer, uConPty, uKeymap,
  uDialogTypes, uDialogHost, uBaseConsoleWindow, uShellProfiles;

type
  TConsoleWindow = class(TBaseConsoleWindow)
  private
    FLastSyncedCwd: string;
    FRestartOnExit: Boolean;
    FOnBackToPanels:     TNotifyEvent;
    FOnDismissConsole:   TNotifyEvent;
    FOnFocusCommandLine: TNotifyEvent;
    FOnSyncDirToPanels:  TNotifyEvent;
    procedure DoCloseConsole;
  protected
    procedure ProcessExited(AExitCode: Cardinal); override;
    procedure SyncTitle; override;
    function ViewHeight: Integer; override;
    function TextWidth:  Integer; override;
    procedure DrawAppStatusHint(AY, AWidth: Integer);
    procedure DrawContent; override;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal;
      const AProfileId: string = '');
    procedure Interrupt; override;
    function  EnsureShell(const ACwd: string): Boolean;
    procedure SyncWorkingDir(const APath: string);
    procedure RunCommand(const ACommand, AWorkingDir: string);
    procedure CloseConsole;
    function  HandleInput(var AKey: Word; AShift: TShiftState;
                var AKeyChar: Char): Boolean; override;
    function  HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
    function  HandleMouseDown(ALocalCol, ALocalRow: Integer;
                AShift: TShiftState): Boolean;
    function  HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
    function  HandleMouseUp: Boolean;
    property OnBackToPanels:     TNotifyEvent read FOnBackToPanels     write FOnBackToPanels;
    property OnDismissConsole:   TNotifyEvent read FOnDismissConsole   write FOnDismissConsole;
    property OnFocusCommandLine: TNotifyEvent read FOnFocusCommandLine write FOnFocusCommandLine;
    // Ctrl+Shift+O: push this console's WorkingDir into the active Dual Panel panel.
    property OnSyncDirToPanels: TNotifyEvent read FOnSyncDirToPanels write FOnSyncDirToPanels;
    // Auto-relaunch the shell (EnsureShell at the last known cwd) when it
    // exits, instead of leaving the console idle. Defaults to True so the
    // always-on background console (Ctrl+O) survives an `exit` or crash.
    property RestartOnExit: Boolean read FRestartOnExit write FRestartOnExit;
    // Inherited: Running, WorkingDir, ProfileId, OnCloseRequest, OnContentChanged
  end;

implementation

uses
  FMX.Platform, uStrings;

const
  cTextFg      = TAlphaColor($FFE0E0E0);
  cHintFg      = TAlphaColor($FFF0F000);
  cCmdBg       = TAlphaColor($FF000000);
  cScrollFg    = TAlphaColor($FFE0E0E0);
  cScrollThumb = TAlphaColor($FF30F0F0);
  cSelFg       = TAlphaColor($FF000000);
  cSelBg       = TAlphaColor($FFE8C000);

function SamePathNorm(const A, B: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(A),
                     ExcludeTrailingPathDelimiter(B));
end;

{ ---- Constructor ----------------------------------------------------------- }

constructor TConsoleWindow.Create(const ATheme: IThemeRenderer; AId: Cardinal;
  const AProfileId: string);
begin
  inherited Create(ATheme, AId, AProfileId);
  FLastSyncedCwd     := '';
  FRestartOnExit     := True;
  LayoutBottomMargin := 2; // shared Dual Panel F-keys / status below (no cmdline)
  Title              := T('ui.window.console', 'Console');
end;

{ ---- Title ----------------------------------------------------------------- }

procedure TConsoleWindow.SyncTitle;
begin
  if Assigned(FPty) and FPty.IsRunning and FPty.Persistent then
    Title := T('ui.window.consoleShell', 'Console [shell]')
  else if Running then
    Title := T('ui.window.consoleRunning', 'Console [running]')
  else
    Title := T('ui.window.console', 'Console');
end;

{ ---- View geometry --------------------------------------------------------- }

function TConsoleWindow.ViewHeight: Integer;
begin
  Result := Max(Area.Height - 3, 1); // top border + bottom border reserved
end;

function TConsoleWindow.TextWidth: Integer;
begin
  Result := Max(Area.Width - 3, 4);
end;

{ ---- Interrupt ------------------------------------------------------------- }

procedure TConsoleWindow.Interrupt;
begin
  if Assigned(FPty) and FPty.IsRunning then
  begin
    FPty.Terminate;
    FHistory.AppendStatus('[MTN2] interrupted');
    WorkingDir := '';
    FLastSyncedCwd := '';
    SyncTitle;
    NotifyHost;
  end;
  FRunning := False;
end;

{ ---- Output / lifecycle ---------------------------------------------------- }

procedure TConsoleWindow.ProcessExited(AExitCode: Cardinal);
var
  Cwd: string;
begin
  if not Alive or not Assigned(FHistory) then
    Exit;
  Cwd := WorkingDir;
  WorkingDir := '';
  FLastSyncedCwd := '';
  FRunning := False;
  FHistory.AppendStatus(Format('[MTN2] process exited with code %d', [AExitCode]));
  if FRestartOnExit then
  begin
    // EnsureShell drives its own SyncTitle/NotifyHost -- no need to repeat
    // them here, and calling it re-enters neither Alive nor Gen checks since
    // it starts a fresh FCallbackGen for the new shell.
    FHistory.AppendStatus('[MTN2] restarting shell...');
    EnsureShell(Cwd);
    Exit;
  end;
  SyncTitle;
  NotifyHost;
end;

procedure TConsoleWindow.DoCloseConsole;
begin
  if PendingClose then
    Exit;
  PendingClose := True;
  DoClose;
end;

procedure TConsoleWindow.CloseConsole;
begin
  DoCloseConsole;
end;

{ ---- Shell management ------------------------------------------------------ }

function TConsoleWindow.EnsureShell(const ACwd: string): Boolean;
var
  Gen: Integer;
  Cwd: string;
  OnOut: TConPtyOutputEvent;
  OnExitEvt: TConPtyExitEvent;
begin
  if not Assigned(FPty) then
    FPty := TConPtySession.Create;

  Cwd := Trim(ACwd);
  if Cwd <> '' then
    WorkingDir := Cwd;

  if FPty.IsRunning and FPty.Persistent then
  begin
    if (Cwd <> '') and not SamePathNorm(Cwd, FLastSyncedCwd) then
    begin
      FPty.WriteInput(BuildCdLineForProfile(ProfileId, Cwd));
      FLastSyncedCwd := Cwd;
    end;
    WorkingDir := Cwd;
    SyncTitle;
    Exit(True);
  end;

  // Drop leftover one-shot before starting a persistent shell.
  if FPty.IsRunning then
    FPty.Terminate;

  Inc(FCallbackGen);
  Gen := FCallbackGen;
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

  // Set callbacks before starting shell.
  FPty.OnOutput := OnOut;
  FPty.OnExit   := OnExitEvt;
  // Profile drives both output decoding and input encoding (cmd=OEM, ps/wsl=UTF-8).
  FPty.ProfileId := ProfileId;
  if not FPty.StartShell(ProfileId, WorkingDir, PtyCols, PtyRows) then
  begin
    FRunning := False;
    if FPty.LastError <> '' then
      FHistory.AppendStatus('[MTN2] ' + FPty.LastError)
    else
      FHistory.AppendStatus('[MTN2] Failed to start shell');
    SyncTitle;
    NotifyHost;
    Exit(False);
  end;

  SendInitCommand(ProfileInitCommand(ProfileId));
  FLastSyncedCwd := WorkingDir;
  SyncTitle;
  Result := True;
end;

procedure TConsoleWindow.SyncWorkingDir(const APath: string);
var
  Path: string;
begin
  Path := Trim(APath);
  if Path = '' then
    Exit;

  if not Assigned(FPty) then
    FPty := TConPtySession.Create;

  if not (FPty.IsRunning and FPty.Persistent) then
  begin
    WorkingDir := Path;
    Exit;
  end;

  if Running and not FPty.Persistent then
  begin
    WorkingDir := Path;
    Exit;
  end;

  if SamePathNorm(Path, FLastSyncedCwd) then
  begin
    WorkingDir := Path;
    Exit;
  end;

  WorkingDir := Path;
  FPty.WriteInput(BuildCdLineForProfile(ProfileId, Path));
  if FPty.LastError <> '' then
  begin
    FHistory.AppendStatus('[MTN2] cwd sync: ' + FPty.LastError);
    NotifyHost;
    Exit;
  end;
  FLastSyncedCwd := Path;
end;

procedure TConsoleWindow.RunCommand(const ACommand, AWorkingDir: string);
var
  Cmd, Line, NormId: string;
begin
  Cmd := Trim(ACommand);
  if Cmd = '' then
    Exit;

  if AWorkingDir <> '' then
    WorkingDir := AWorkingDir;

  if Running and Assigned(FPty) and FPty.IsRunning and not FPty.Persistent then
  begin
    FHistory.AppendStatus('[MTN2] Command still running (Esc to cancel).');
    NotifyHost;
    Exit;
  end;

  ClearSelection;
  // Stage 22: real ConPTY gives the persistent shell a genuine console that
  // echoes the command itself and draws its own prompt -- pre-echoing the
  // command here (a synthetic yellow line, built for the old one-shot pipe
  // era) now races the real async prompt/echo arriving via AppendOutput,
  // corrupting the primary buffer's cursor/line state (confirmed by manual
  // testing: doubled prompt, command detached from the real prompt line,
  // glued-together output lines, prompt not starting on a new line after
  // the command finishes). Let the real shell be the only source of truth,
  // exactly like keystroke-level input already does.

  if not EnsureShell(WorkingDir) then
    Exit;

  Line := Cmd;
  NormId := NormalizeShellProfileId(ProfileId);
  if (NormId = cShellProfilePowerShell) or (NormId = cShellProfilePwsh) then
    Line := PsPipeSafeCommand(Cmd);
  Line := Line + ProfileReturnSeq(ProfileId);

  FPty.WriteInput(Line);
  if FPty.LastError <> '' then
  begin
    FHistory.AppendStatus('[MTN2] ' + FPty.LastError);
    NotifyHost;
    Exit;
  end;

  FRunning := True;
  SyncTitle;
  NotifyHost;
end;

{ ---- Drawing --------------------------------------------------------------- }

procedure TConsoleWindow.DrawAppStatusHint(AY, AWidth: Integer);
var
  Hint: string;
begin
  if Running then
    Hint := ' running '
  else
    Hint := '';
  if Hint <> '' then
    PutGridText(Buffer, Max(AWidth - Length(Hint) - 3, 2), AY, Hint, cHintFg, cCmdBg);
end;

procedure TConsoleWindow.DrawContent;
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
  if (W < 8) or (H < 4) then
    Exit;

  ViewH := ViewHeight;
  TextW := TextWidth;

  if AltScreenActive then
  begin
    FillGridRect(Buffer, 1, 1, W - 3, H - 2, ' ', cTextFg, cCmdBg);
    DrawAltScreenGrid(TextW, ViewH);
    if Assigned(FDialog) and FDialog.Visible then
      FDialog.Draw(Buffer, W, H);
    Exit;
  end;

  Rows  := FHistory.GetVisibleRows(ViewH, Total, Top);

  CurRow := -1;
  CurCol := 0;
  ShowInputCursor := FCursorVisible and FHistory.GetInputCursor(CurRow, CurCol);

  FillGridRect(Buffer, 1, 1, W - 3, H - 2, ' ', cTextFg, cCmdBg);

  for I := 0 to High(Rows) do
  begin
    Y := 1 + I;
    if Y > H - 2 then
      Break;
    LineIdx := Top + I;
    Row := Rows[I];
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
    PutGridText(Buffer, 1, 1, 'No output yet. Type at the shell prompt.',
      cHintFg, cCmdBg);

  DrawScrollBar(Total, Top, ViewH, 1, H - 2);
  DrawAppStatusHint(H - 2, W);

  if Assigned(FDialog) and FDialog.Visible then
    FDialog.Draw(Buffer, W, H);
end;

{ ---- Input ----------------------------------------------------------------- }

function TConsoleWindow.HandleInput(var AKey: Word; AShift: TShiftState;
  var AKeyChar: Char): Boolean;
begin
  if not Alive or PendingClose then
    Exit(True);

  if not FCursorVisible then
    SetCursorVisible(True);

  Result := True;
  if Assigned(FDialog) and FDialog.Visible then
  begin
    if HandleCmdHistoryFilterInput(AKey, AShift, AKeyChar) then
      Exit(True);
    Result := FDialog.HandleInput(AKey, AShift, AKeyChar);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseConsole;
    end;
    Exit(Result);
  end;

  if PendingClose then
  begin
    PendingClose := False;
    DoCloseConsole;
    Exit(True);
  end;

  // Ctrl+Shift+O — sync active panel's directory to this console's cwd
  // (mirror of Dual Panel's kaSyncConsoleDir, other direction).
  if (ssCtrl in AShift) and (ssShift in AShift) and not (ssAlt in AShift) and
     (AKey = kmConsole) then
  begin
    if Assigned(FOnSyncDirToPanels) then
      FOnSyncDirToPanels(Self);
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+O — back to panels.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and not (ssShift in AShift) and
     (AKey = kmConsole) then
  begin
    if Assigned(FOnBackToPanels) then
      FOnBackToPanels(Self);
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+A — select all (handled by base).
  // Ctrl+C — copy if selection; interrupt if running.
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

  // Shift+Insert / Ctrl+V — paste clipboard as input.
  if ((AKey = vkInsert) and (ssShift in AShift) and not (ssCtrl in AShift) and
      not (ssAlt in AShift)) or
     ((ssCtrl in AShift) and not (ssAlt in AShift) and
      ((AKey = Ord('V')) or (AKey = Ord('v')) or
       (AKeyChar = 'v') or (AKeyChar = 'V'))) then
  begin
    PasteClipboard;
    AKey := 0; AKeyChar := #0;
    Exit;
  end;

  // Ctrl+Down — unused (panel cmdline is hidden while console is open).
  if (ssCtrl in AShift) and (AKey = vkDown) then
  begin
    AKey := 0;
    Exit;
  end;

  // Alt-screen (TUI app running): forward navigation keys to the PTY before
  // HandleCommonInput's bare-arrow scroll-interception can steal them.
  if HandleAltScreenNav(AKey, AShift) then
    Exit;

  // Common: Ctrl+A, Shift+arrows, bare navigation.
  if HandleCommonInput(AKey, AShift, AKeyChar) then
    Exit;

  // cmd pipe: edit in buffer only; submit full line on Enter (avoids BS
  // desync). Never during alt-screen: a raw full-screen app (e.g. vim
  // launched from the default cmd profile) needs character-at-a-time input.
  if not AltScreenActive and HandleLineBufferedPtyInput(AKey, AShift, AKeyChar) then
    Exit;

  // Remaining key-specific actions (non-cmd / raw PTY profiles).
  case AKey of
    vkF10:
      begin
        // F10 no longer closes the Panel Console — Esc/Ctrl+O do. Still
        // swallow the key so it doesn't fall through to the global F10 =
        // Quit application binding (uKeymap.kmQuit).
        AKey := 0;
      end;
    vkEscape:
      begin
        if HasSelection then
        begin
          ClearSelection;
          NotifyHost;
        end
        else if Assigned(FOnDismissConsole) then
          FOnDismissConsole(Self)
        else if Assigned(FOnBackToPanels) then
          FOnBackToPanels(Self);
        AKey := 0;
      end;
    vkReturn:
      begin
        NoteCommandSubmitted(FHistory.GetInputAfterPrompt);
        SendRaw(ProfileReturnSeq(ProfileId));
        AKey := 0;
        AKeyChar := #0;
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
        AKey := 0;
        AKeyChar := #0;
      end;
  else
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
       not (ssCtrl in AShift) and not (ssAlt in AShift) then
    begin
      SendRaw(AKeyChar);
      AKey := 0;
      AKeyChar := #0;
    end
    else
      Result := False;
  end;
end;

{ ---- Mouse ----------------------------------------------------------------- }

function TConsoleWindow.HandleClick(ALocalCol, ALocalRow: Integer): Boolean;
begin
  if not Alive or PendingClose then
    Exit(True);
  if Assigned(FDialog) and FDialog.Visible then
  begin
    Result := FDialog.HandleClick(ALocalCol, ALocalRow);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseConsole;
    end;
    Exit(Result);
  end;
  Result := HandleMouseDown(ALocalCol, ALocalRow, []);
end;

function TConsoleWindow.HandleMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState): Boolean;
begin
  if not Alive or PendingClose then
    Exit(True);
  if Assigned(FDialog) and FDialog.Visible then
  begin
    Result := FDialog.HandleClick(ALocalCol, ALocalRow, AShift);
    if PendingClose then
    begin
      PendingClose := False;
      DoCloseConsole;
    end;
    Exit(Result);
  end;
  Result := HandleCommonMouseDown(ALocalCol, ALocalRow, AShift,
    { ScrollTopY } 1, { ScrollBottomY } Area.Height - 2,
    procedure
    begin
      if Assigned(OnCloseRequest) then
        OnCloseRequest(Self);
    end);
end;

function TConsoleWindow.HandleMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
begin
  Result := HandleCommonMouseMove(ALocalCol, ALocalRow);
end;

function TConsoleWindow.HandleMouseUp: Boolean;
begin
  if not Alive or PendingClose then
    Exit(False);
  Result := HandleCommonMouseUp;
end;

end.
