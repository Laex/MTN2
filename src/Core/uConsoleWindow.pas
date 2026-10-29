unit uConsoleWindow;

{ MDI Console window: scrollback + persistent shell. First command comes from
  the Dual Panel cmdline; further input is typed at the shell prompt in this window.
  Bottom frame sits above the shared F-keys / status (Dual Panel draws those).
  Inherits buffer, PTY, selection, mouse and clipboard from TBaseConsoleWindow.
  Unique to this class:
    - Persistent-shell start via EnsureShell (profile-aware). By default the
      shell is not started until the first Ctrl+O or command-line command;
      "Start shell at program launch" pre-warms it from FormCreate.
    - OnBackToPanels / OnDismissConsole / OnFocusCommandLine events.
    - Esc -> panels (never stops the shell/command - Ctrl+C does that);
      Ctrl+O -> panels; F10 -> close.
    - DrawAppStatusHint (running indicator). }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, uPlatformInfo,
  uTerminalTypes, uThemeTypes, uTerminalWindow, uConsoleBuffer, uConPty, uKeymap,
  uDialogTypes, uDialogHost, uBaseConsoleWindow, uShellProfiles;

type
  TConsoleWindow = class(TBaseConsoleWindow)
  private
    FLastSyncedCwd: string;
    /// <summary>The prompt folder when the first command since the last
    /// TakeCwdChange was submitted; '' = none pending.</summary>
    FCwdBeforeCommand: string;
    FReturnPending: Boolean;
    FPromptsAtStart: Integer;
    /// <summary>A freshly started shell has not drawn its first prompt yet;
    /// FStartupPrompts is the prompt count before it appears.</summary>
    FStartupPending: Boolean;
    FStartupPrompts: Integer;
    /// <summary>Where prompts cannot be recognized: when the last output arrived, and
    /// whether the check for "the command is done" is queued.</summary>
    FLastOutputTick: UInt64;
    FIdleCheckQueued: Boolean;
    FRestartOnExit: Boolean;
    FOnBackToPanels:     TNotifyEvent;
    FOnDismissConsole:   TNotifyEvent;
    FOnFocusCommandLine: TNotifyEvent;
    FOnSyncDirToPanels:  TNotifyEvent;
    function CountPrompts: Integer;
    procedure FinishReturn;
    procedure QueueIdleCheck;
    procedure DoCloseConsole;
    /// <summary>A dialog button released after the click or key returned:
    /// the close its command asked for, as HandleInput / HandleClick do.</summary>
    procedure DialogDeferredCommand(Sender: TObject);
  protected
    procedure ProcessExited(AExitCode: Cardinal); override;
    procedure NoteCommandSubmitted(const ACommand: string); override;
    procedure OutputAppended; override;
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
    /// <summary>An idle persistent shell standing in one of APaths (or below it)
    /// moves to the parent of that folder, so the folder can be deleted or
    /// moved; Windows refuses to touch the current folder of a process. True =
    /// the shell was told to leave.</summary>
    function ReleaseWorkingDirs(const APaths: TArray<string>): Boolean;
    procedure RunCommand(const ACommand, AWorkingDir: string);
    /// <summary>The folder the shell's latest prompt shows ('' when the prompt
    /// is not a recognizable cmd / PowerShell one).</summary>
    function PromptCwd: string;
    /// <summary>True once when commands submitted since the previous call
    /// moved the shell to another folder; APath is that folder.</summary>
    function TakeCwdChange(out APath: string): Boolean;
    /// <summary>Goes back to the panels (OnBackToPanels) as soon as the shell
    /// shows another prompt, i.e. when the command just given has finished.</summary>
    procedure ReturnToPanelsWhenDone;
    /// <summary>A command still runs in the persistent shell (it has a child
    /// process). A shell not started yet is not busy.</summary>
    function ShellBusy: Boolean;
    procedure DropPendingInput;
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
  uStrings, uKeyChord, uChromeRows, uVfsTypes;

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
  Result := SameLocalPath(ExcludeTrailingPathDelimiter(A),
                          ExcludeTrailingPathDelimiter(B));
end;

{ ---- Constructor ----------------------------------------------------------- }

constructor TConsoleWindow.Create(const ATheme: IThemeRenderer; AId: Cardinal;
  const AProfileId: string);
begin
  inherited Create(ATheme, AId, AProfileId);
  FLastSyncedCwd     := '';
  FRestartOnExit     := True;
  LayoutBottomMargin := ChromeBottomRows; // shared Dual Panel F-keys / status below (no cmdline)
  Title              := TitleWithShell(T('ui.window.console', 'Console'), ProfileId);
  FDialog.OnDeferredCommand := DialogDeferredCommand;
end;

procedure TConsoleWindow.DialogDeferredCommand(Sender: TObject);
begin
  if PendingClose then
  begin
    PendingClose := False;
    DoCloseConsole;
  end;
end;

{ ---- Title ----------------------------------------------------------------- }

procedure TConsoleWindow.SyncTitle;
begin
  if Assigned(FPty) and FPty.IsRunning and FPty.Persistent then
    Title := TitleWithShell(T('ui.window.consoleShell', 'Console [shell]'), ProfileId)
  else if Running then
    Title := TitleWithShell(T('ui.window.consoleRunning', 'Console [running]'), ProfileId)
  else
    Title := TitleWithShell(T('ui.window.console', 'Console'), ProfileId);
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
  FReturnPending := False;
  FStartupPending := False;
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
  Cwd: string;
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

  // Drops any leftover one-shot before starting the persistent shell.
  if not StartShellSession then
    Exit(False);

  FLastSyncedCwd := WorkingDir;
  FStartupPrompts := CountPrompts;
  FStartupPending := True;
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
  DropPendingInput;
  FPty.WriteInput(BuildCdLineForProfile(ProfileId, Path));
  if FPty.LastError <> '' then
  begin
    FHistory.AppendStatus('[MTN2] cwd sync: ' + FPty.LastError);
    NotifyHost;
    Exit;
  end;
  FLastSyncedCwd := Path;
end;

function TConsoleWindow.ReleaseWorkingDirs(const APaths: TArray<string>): Boolean;
var
  Cwd, Dir, Parent, Path: string;
begin
  Result := False;
  if not (Assigned(FPty) and FPty.IsRunning and FPty.Persistent) or ShellBusy then
    Exit;
  Cwd := PromptCwd;
  if Cwd = '' then
    Cwd := FLastSyncedCwd;
  if Cwd = '' then
    Exit;
  for Path in APaths do
  begin
    Dir := ExcludeTrailingPathDelimiter(Cwd);
    while Dir <> '' do
    begin
      if SamePathNorm(Dir, Path) then
      begin
        Parent := SafeDirectoryName(ExcludeTrailingPathDelimiter(Path));
        if Parent = '' then
          Exit;
        DropPendingInput;
        FPty.WriteInput(BuildCdLineForProfile(ProfileId, Parent));
        if FPty.LastError = '' then
        begin
          WorkingDir := Parent;
          FLastSyncedCwd := Parent;
          Result := True;
        end;
        Exit;
      end;
      Parent := SafeDirectoryName(Dir);
      if SamePathNorm(Parent, Dir) then
        Break;
      Dir := Parent;
    end;
  end;
end;

function TConsoleWindow.ShellBusy: Boolean;
begin
  Result := Assigned(FPty) and FPty.IsRunning and FPty.HasChildProcess;
end;

// Text left on the shell's input line (a recalled history entry, a
// half-typed command) would be glued to the front of a line written next.
procedure TConsoleWindow.DropPendingInput;
var
  Pending: string;
begin
  Pending := FHistory.GetInputAfterPrompt;
  if (Pending <> '') and not ShellBusy then
    SendRaw(#27'[F' + StringOfChar(ProfileBackspaceChar(ProfileId), Length(Pending)));
end;

function TConsoleWindow.PromptCwd: string;
const
  cScanLines = 60;
var
  I, Last: Integer;
begin
  Result := '';
  Last := FHistory.LineCount - 1;
  // The prompt is the last prompt-looking line; blank grid rows may follow it.
  for I := Last downto Max(0, Last - cScanLines) do
    if ShellCwdFromPrompt(ProfileId, FHistory.GetLine(I), Result) then
      Exit;
  // No recognizable prompt (a Linux shell): ask the system where the shell is.
  if Assigned(FPty) then
    Result := FPty.ShellCwd
  else
    Result := '';
end;

procedure TConsoleWindow.NoteCommandSubmitted(const ACommand: string);
begin
  if FCwdBeforeCommand = '' then
    FCwdBeforeCommand := PromptCwd;
  inherited;
end;

function TConsoleWindow.CountPrompts: Integer;
const
  cScanLines = 400;
var
  I, Last: Integer;
  Path: string;
begin
  Result := 0;
  Last := FHistory.LineCount - 1;
  for I := Max(0, Last - cScanLines) to Last do
    if ShellCwdFromPrompt(ProfileId, FHistory.GetLine(I), Path) then
      Inc(Result);
end;

procedure TConsoleWindow.ReturnToPanelsWhenDone;
begin
  FPromptsAtStart := CountPrompts;
  // The first prompt of a shell that was just started is not the end of
  // the command given to it.
  if FStartupPending then
    Inc(FPromptsAtStart);
  FReturnPending := True;
end;

procedure TConsoleWindow.FinishReturn;
begin
  FReturnPending := False;
  if Assigned(FOnBackToPanels) then
    FOnBackToPanels(Self);
end;

// Without prompts to count, a command is done when the shell is in the
// foreground again and its output has stopped for a moment.
procedure TConsoleWindow.QueueIdleCheck;
const
  cQuietMs = 150;
  cPollMs = 100;
var
  Life: ILifeFlag;
begin
  if FIdleCheckQueued then
    Exit;
  FIdleCheckQueued := True;
  Life := FLife;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not Life.Alive then
        Exit;
      FIdleCheckQueued := False;
      if not FReturnPending then
        Exit;
      if ShellBusy or (TThread.GetTickCount64 - FLastOutputTick < cQuietMs) then
        QueueIdleCheck
      else
        FinishReturn;
    end, cPollMs);
end;

procedure TConsoleWindow.OutputAppended;
begin
  if FStartupPending then
    if ProfilePromptIsParsable(ProfileId) then
      FStartupPending := CountPrompts <= FStartupPrompts
    else
      FStartupPending := False;
  if not FReturnPending then
    Exit;
  if ProfilePromptIsParsable(ProfileId) then
  begin
    if CountPrompts > FPromptsAtStart then
      FinishReturn;
    Exit;
  end;
  FLastOutputTick := TThread.GetTickCount64;
  QueueIdleCheck;
end;

function TConsoleWindow.TakeCwdChange(out APath: string): Boolean;
var
  Before: string;
begin
  Before := FCwdBeforeCommand;
  FCwdBeforeCommand := '';
  APath := PromptCwd;
  Result := (Before <> '') and (APath <> '') and not SamePathNorm(Before, APath);
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
  // Real ConPTY gives the persistent shell a genuine console that
  // echoes the command itself and draws its own prompt. Pre-echoing the
  // command here would race the real async prompt/echo arriving via
  // AppendOutput and corrupt the primary buffer's cursor/line state
  // (doubled prompt, command detached from the prompt line, glued output
  // lines). Let the real shell be the only source of truth,
  // exactly like keystroke-level input already does.

  // Before EnsureShell: its cwd-sync `cd` line would otherwise be glued to
  // the text still sitting on the shell's input line.
  DropPendingInput;

  if not EnsureShell(WorkingDir) then
    Exit;

  Line := Cmd;
  NormId := NormalizeShellProfileId(ProfileId);
  if (NormId = cShellProfilePowerShell) or (NormId = cShellProfilePwsh) then
    Line := PsPipeSafeCommand(Cmd);
  Line := Line + ProfileReturnSeq(ProfileId);

  // The shell was just moved to the panel's folder; that is where the
  // command starts.
  if FCwdBeforeCommand = '' then
    if AWorkingDir <> '' then
      FCwdBeforeCommand := AWorkingDir
    else
      FCwdBeforeCommand := PromptCwd;

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
  Found: TArray<Boolean>;
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
    Found := FoundColumns(LineIdx, TextW);
    for AbsCol := 0 to TextW - 1 do
    begin
      if AbsCol < Length(Row) then
      begin
        Cell := Row[AbsCol];
        if ccaWideTail in Cell.Attributes then
          Continue;
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

      if (AbsCol < Length(Found)) and Found[AbsCol] then
      begin
        Fg := cFindFg; Bg := cFindBg;
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
var
  K: TKeyChord;
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
  K := TKeyChord.Make(AKey, AKeyChar, AShift);

  case MatchActiveActionIn([kcConsole, kcShell, kcGlobal],
    KeymapLookupKey(AKey, AKeyChar), AShift) of
    // Ctrl+Shift+O - the active panel goes to this console's folder (the
    // panels' SyncConsoleDir, the other way round).
    kaConsoleSyncDir:
      begin
        if Assigned(FOnSyncDirToPanels) then
          FOnSyncDirToPanels(Self);
        AKey := 0; AKeyChar := #0;
        Exit;
      end;
    // Ctrl+O (Global AppConsoleToggle) - back to panels.
    kaAppConsoleToggle:
      begin
        if Assigned(FOnBackToPanels) then
          FOnBackToPanels(Self);
        AKey := 0; AKeyChar := #0;
        Exit;
      end;
  end;

  // Alt+F8, Ctrl+A, Ctrl+C (copy or interrupt), Ctrl+Insert, Ctrl+V /
  // Shift+Insert.
  if HandleSharedKeys(AKey, AShift, AKeyChar) then
    Exit;

  // F-keys and Alt / Ctrl combinations of a console in program-keys mode.
  if HandleProgramKey(AKey, AShift, AKeyChar) then
    Exit;

  // Ctrl+Down - unused (panel cmdline is hidden while console is open).
  if K.MatchesAny(vkDown, [ssCtrl], [ssShift, ssAlt]) then
  begin
    AKey := 0;
    Exit;
  end;

  // Alt-screen (TUI app running): forward navigation keys to the PTY before
  // HandleScrollKeys' bare-arrow scroll-interception can steal them.
  if HandleAltScreenNav(AKey, AShift) then
    Exit;

  // At the live bottom the arrows belong to the shell (line editing, command
  // history); scrolled back they scroll.
  if HandleShellNav(AKey, AShift) then
    Exit;

  // Shift+arrows select, bare navigation scrolls.
  if HandleSelectionKeys(AKey, AShift) or HandleScrollKeys(AKey, AShift) then
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
        // F10 does not close the Panel Console - Esc / Ctrl+O do. Swallowed
        // so it never reaches the panels' F10 = Quit.
        AKey := 0;
      end;
    vkEscape:
      begin
        if HasSelection then
        begin
          ClearSelection;
          NotifyHost;
        end
        else if EscGoesToProgram then
          SendRaw(#27)
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
    vkTab:
      begin
        // The shell completes the word before the cursor; a terminal host
        // delivers Tab as a key without a character.
        if not K.HasMods([], []) then
          Exit(False);
        SendRaw(#9);
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
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and K.HasMods([], [ssShift]) then
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
