unit uBaseConsoleWindow;

{ Base class for all console/terminal windows (TConsoleWindow, TTerminalWorkspaceWindow).
  Holds the shared PTY session, scroll-back buffer, text selection, mouse handling,
  scrollbar drawing, and clipboard utilities so neither subclass duplicates them.
  Subclasses override:
    DrawContent  — window-specific chrome (frame, status bar, hints)
    HandleInput  — keyboard dispatch (raw PTY vs. scroll-only vs. host shortcuts)
    SyncTitle    — title format specific to window type }

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Math, System.Rtti,
  FMX.Platform,
  Winapi.Windows,
  uTerminalTypes, uThemeTypes, uThemeDrawing, uTerminalWindow, uConsoleBuffer, uConPty,
  uShellProfiles, uDialogTypes, uDialogHost, uInputLine;

type
  TConsoleCommandEvent = reference to procedure(const ACommand: string);
  TConsoleGetHistoryEvent = reference to function: TArray<string>;

  TBaseConsoleWindow = class(TTerminalWindow)
  private
    FWorkingDir:        string;
    FLastNotifyTick:    UInt64;
    FNotifyDirty:       Boolean;
    FNotifyFlushQueued: Boolean;
    FPendingClose:      Boolean;
    FOnCloseRequest:    TNotifyEvent;
    FOnContentChanged:  TNotifyEvent;
    FOnCommandExecuted: TConsoleCommandEvent;
    FOnGetCmdHistory:   TConsoleGetHistoryEvent;
    FCmdHistItems:      TArray<string>;
    /// <summary>Unfiltered Alt+F8 command history, captured when the dialog
    /// opens; FCmdHistItems is re-derived from this as FCmdHistFilter grows.</summary>
    FCmdHistAllItems:   TArray<string>;
    /// <summary>Reverse-search substring typed into the open Alt+F8 dialog
    /// (Stage 38); '' = unfiltered.</summary>
    FCmdHistFilter:     string;
    /// <summary>True while the Alt+F8 command history dialog (specifically)
    /// is the one open in FDialog — distinguishes it from e.g. the
    /// TTerminalWorkspaceWindow close-confirm dialog, which also uses FDialog.</summary>
    FCmdHistDialogOpen: Boolean;
    procedure CmdHistoryDialogCommand(const AControlId, AValuesJson: string);
    procedure RefreshCmdHistoryDialog;
    { Private helpers. }
    procedure DialogChanged(Sender: TObject);
    procedure ClampPos(var ARow, ACol: Integer);
  protected
    FHistory:       TConsoleBuffer;
    // CROSS-PLATFORM (Этап 23): concrete Windows-only class, not the
    // IPtySession interface uConPty.pas already declares for this seam.
    // A POSIX PTY backend needs this typed as IPtySession first.
    FPty:           TConPtySession;
    FDialog:        TDialogHost;
    { Subclass-accessible state. }
    FAlive:         Boolean;
    FRunning:       Boolean;
    FProfileId:     string;
    FCallbackGen:   Integer;
    FCursorRow:     Integer;
    FCursorCol:     Integer;
    FCursorVisible: Boolean;
    FSelAnchorRow:  Integer;
    FSelAnchorCol:  Integer;
    FMouseSelecting: Boolean;
    FClicks: TMouseClickCounter; // double = word, triple = line
    { Selection trim helper — protected so AppendOutput overrides can call it. }
    procedure AdjustSelectionForTrim(ADeleted: Integer);
    { Lifecycle. }
    procedure DoClose; virtual;

    { PTY / output. }
    procedure NotifyHost; virtual;
    procedure NotifyHostThrottled;
    procedure AppendOutput(const AText: string); virtual;
    /// <summary>Local keyboard/paste echo — see TConsoleBuffer.AppendLocalInput.</summary>
    procedure AppendLocalInput(const AText: string); virtual;
    procedure ProcessExited(AExitCode: Cardinal); virtual; abstract;
    procedure SyncTitle; virtual; abstract;

    { PTY sizing — called on resize and after start. }
    function  ViewHeight: Integer; virtual; abstract;
    function  TextWidth:  Integer; virtual; abstract;
    function  PtyCols: Word;
    function  PtyRows: Word;
    procedure SyncPtySize;

    { Alternate screen (Stage 22): TUI apps like vim/htop draw via a fixed
      cursor-addressable grid instead of scrollback; DrawContent/HandleInput
      in each subclass branch on this. }
    function AltScreenActive: Boolean;
    /// <summary>While alt-screen is active, forward arrows/PgUp/PgDn/Home/
    /// End/Delete to the PTY instead of scrolling local history. Returns
    /// True (and consumes AKey) only when it actually forwarded a key.</summary>
    function HandleAltScreenNav(var AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Blit the alt-screen grid directly into Buffer (no scroll
    /// windowing). Shared by both subclasses' DrawContent.</summary>
    procedure DrawAltScreenGrid(ATextW, AViewH: Integer);

    { Scrollback selection helpers. }
    procedure ClearSelection;
    function  HasSelection: Boolean;
    procedure GetSelRange(out ARow1, ACol1, ARow2, ACol2: Integer);
    function  IsCellSelected(ARow, ACol: Integer): Boolean;
    function  SelectedText: string;
    procedure SelectAll;
    procedure EnsureCursorVisible;
    procedure SetCursorPos(ARow, ACol: Integer; AExtendSel: Boolean);
    procedure MoveSelCursor(ARowDelta, AColDelta: Integer; AExtendSel: Boolean);
    function  HitTextCell(ALocalCol, ALocalRow: Integer;
                out ARow, ACol: Integer): Boolean;

    { Clipboard. }
    procedure ClipboardSetText(const AText: string);
    function  ClipboardGetText: string;
    procedure CopySelection;
    /// <summary>Sends clipboard text as input: appended to the local line
    /// buffer for cmd-piped profiles, written straight to the PTY otherwise.</summary>
    procedure PasteClipboard;

    { Raw PTY write (used by TTerminalWorkspaceWindow). }
    procedure SendRaw(const AText: string);
    /// <summary>Sends a profile's silent post-startup setup command (see
    /// ProfileInitCommand) one character at a time, matching how genuine
    /// keystrokes already arrive. Writing the whole string (incl. its own
    /// trailing CRLF) in a single WriteInput call reads to PowerShell's
    /// PSReadLine as a bulk paste; PSReadLine defers treating an embedded
    /// CRLF as "submit" during a detected paste (so a multi-line pasted
    /// script isn't submitted line-by-line), leaving a "&gt;&gt;" line-
    /// continuation prompt sitting in front of the user's real first
    /// command instead of a fresh, ready prompt.</summary>
    procedure SendInitCommand(const AText: string);
    /// <summary>cmd pipe mode: local line editing; whole line sent on Enter only.</summary>
    function HandleLineBufferedPtyInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;

    { Shared command history (Alt+F8): records commands submitted at the shell
      prompt into the host's shared history and lets the user re-run one. }
    /// <summary>Reports ACommand (already trimmed by the caller) to the host
    /// via OnCommandExecuted, unless empty or an alt-screen TUI app (vim/htop)
    /// is running -- an Enter there isn't a shell command.</summary>
    procedure NoteCommandSubmitted(const ACommand: string);
    /// <summary>Writes ACommand + the profile's return sequence straight to
    /// the PTY, as if the user had typed and submitted it, and records it via
    /// NoteCommandSubmitted. Used by the Alt+F8 history picker.</summary>
    procedure ExecuteCommandNow(const ACommand: string);
    /// <summary>Alt+F8: open the shared command-history picker in this
    /// console's own dialog host. Selecting an entry runs it immediately
    /// (there is no editable cmdline here to stage it in first).</summary>
    procedure OpenCmdHistoryDialog;
    /// <summary>Consumes a filter keystroke (printable char / Backspace)
    /// while the Alt+F8 command history dialog is open (Stage 38 reverse-
    /// search). Returns False (key not consumed) for anything else, so the
    /// subclass's own dialog-visible branch falls through to
    /// FDialog.HandleInput as usual. Call this before that fallthrough.</summary>
    function HandleCmdHistoryFilterInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;

    { Scrollbar drawing — delegates to subclass for row bounds. }
    procedure DrawScrollBar(ATotal, ATop, AViewH, ATopY, ABottomY: Integer);

    { Common keyboard block: Ctrl+A/C (select/copy/interrupt), Shift+arrows,
      bare navigation arrows/PgUp/PgDn/Home/End.
      Returns True if the key was consumed. }
    function HandleCommonInput(var AKey: Word; AShift: TShiftState;
      var AKeyChar: Char): Boolean;

    { Common mouse-down skeleton: scrollbar hit, text-cell hit, frame close.
      AScrollTopY / AScrollBottomY: scrollbar track rows inside the window.
      AOnFrameClose: called when the window [x] is clicked. }
    function HandleCommonMouseDown(ALocalCol, ALocalRow: Integer;
      AShift: TShiftState; AScrollTopY, AScrollBottomY: Integer;
      AOnFrameClose: TProc): Boolean;
    function HandleCommonMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
    procedure SelectClickRange(ARow, ACol: Integer; AWholeLine: Boolean);
    function HandleCommonMouseUp: Boolean;

    { Alive / pending-close guards. }
    property Alive:       Boolean read FAlive;
    property PendingClose: Boolean read FPendingClose write FPendingClose;

    { Current selection / cursor — used by subclass DrawContent. }
    property CursorRow: Integer read FCursorRow;
    property CursorCol: Integer read FCursorCol;
    property CursorVisible: Boolean read FCursorVisible;
  public
    constructor Create(const ATheme: IThemeRenderer; AId: Cardinal;
      const AProfileId: string = '');
    destructor Destroy; override;
    procedure Resize(AWidth, AHeight: Integer); override;
    procedure Interrupt; virtual;
    /// <summary>Windows logoff/shutdown: stop PTY without close-request UI.</summary>
    procedure ShutdownForSessionEnd;
    function  IsRunning: Boolean;

    /// <summary>Mouse wheel scrolls local scrollback (never CSI to the shell).</summary>
    function HandleMouseWheel(WheelDelta: Integer): Boolean; virtual;

    procedure SetCursorVisible(AVisible: Boolean);

    property ProfileId:  string read FProfileId;
    property WorkingDir: string read FWorkingDir write FWorkingDir;
    property Running:    Boolean read FRunning;
    property OnCloseRequest:   TNotifyEvent read FOnCloseRequest  write FOnCloseRequest;
    property OnContentChanged: TNotifyEvent read FOnContentChanged write FOnContentChanged;
    /// <summary>Fired for every command submitted at this console's shell
    /// prompt (Enter with non-empty input) or run via the Alt+F8 history
    /// picker -- the host records it into the shared command history.</summary>
    property OnCommandExecuted: TConsoleCommandEvent read FOnCommandExecuted write FOnCommandExecuted;
    /// <summary>Alt+F8: queried for the shared command history (newest
    /// first) when this console opens its own history picker dialog.</summary>
    property OnGetCmdHistory: TConsoleGetHistoryEvent read FOnGetCmdHistory write FOnGetCmdHistory;
  end;

implementation

uses
  uStrings;

{ ---- helpers --------------------------------------------------------------- }

const
  cMinNotifyMs = 50; // ~20 Hz full UI recompose while output streams

{ ---- TBaseConsoleWindow ---------------------------------------------------- }

constructor TBaseConsoleWindow.Create(const ATheme: IThemeRenderer;
  AId: Cardinal; const AProfileId: string);
begin
  inherited Create(ATheme, AId);
  FAlive              := True;
  FHistory            := TConsoleBuffer.Create;
  FPty                := TConPtySession.Create;
  FRunning            := False;
  FProfileId          := NormalizeShellProfileId(
                           AProfileId);
  if FProfileId = '' then
    FProfileId        := cShellProfileCmd;
  FWorkingDir         := '';
  FPendingClose       := False;
  FSelAnchorRow       := -1;
  FSelAnchorCol       := 0;
  FCursorRow          := 0;
  FCursorCol          := 0;
  FCursorVisible      := True;
  FMouseSelecting     := False;
  FNotifyFlushQueued  := False;
  FDialog             := TDialogHost.Create(ATheme);
  FDialog.OnChanged   := DialogChanged;
end;

destructor TBaseConsoleWindow.Destroy;
begin
  FAlive := False;
  Inc(FCallbackGen);
  if Assigned(FPty) then
  begin
    FPty.OnOutput := nil;
    FPty.OnExit := nil;
    FPty.Terminate;
    FreeAndNil(FPty);
  end;
  FreeAndNil(FHistory);
  FreeAndNil(FDialog);
  inherited Destroy;
end;

procedure TBaseConsoleWindow.Resize(AWidth, AHeight: Integer);
begin
  inherited Resize(AWidth, AHeight);
  SyncPtySize;
end;

{ ---- PTY sizing ------------------------------------------------------------- }

function TBaseConsoleWindow.PtyCols: Word;
begin
  Result := Word(Max(Area.Width - 2, 80));
end;

function TBaseConsoleWindow.PtyRows: Word;
begin
  Result := Word(Max(ViewHeight, 5));
end;

procedure TBaseConsoleWindow.SyncPtySize;
begin
  if Assigned(FPty) and FPty.IsRunning then
    FPty.Resize(PtyCols, PtyRows);
  if Assigned(FHistory) and FHistory.AltScreenActive then
    FHistory.ResizeAltScreen(PtyCols, PtyRows);
  if Assigned(FHistory) then
    FHistory.ResizePrimaryScreen(PtyCols, PtyRows);
end;

function TBaseConsoleWindow.AltScreenActive: Boolean;
begin
  Result := Assigned(FHistory) and FHistory.AltScreenActive;
end;

function TBaseConsoleWindow.HandleAltScreenNav(var AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := False;
  if not AltScreenActive then
    Exit;
  if (ssShift in AShift) or (ssAlt in AShift) or (ssCtrl in AShift) then
    Exit;
  case AKey of
    vkLeft:   SendRaw(#27'[D');
    vkRight:  SendRaw(#27'[C');
    vkUp:     SendRaw(#27'[A');
    vkDown:   SendRaw(#27'[B');
    vkPrior:  SendRaw(#27'[5~');
    vkNext:   SendRaw(#27'[6~');
    vkHome:   SendRaw(#27'[H');
    vkEnd:    SendRaw(#27'[F');
    vkDelete: SendRaw(#27'[3~');
  else
    Exit;
  end;
  AKey := 0;
  Result := True;
end;

procedure TBaseConsoleWindow.DrawAltScreenGrid(ATextW, AViewH: Integer);
var
  X, Y, Cols, Rows: Integer;
  Cell: TCharCell;
  Ch: Char;
  Fg, Bg, Tmp: TAlphaColor;
begin
  if not AltScreenActive then
    Exit;
  Cols := Min(FHistory.AltScreen.Cols, ATextW);
  Rows := Min(FHistory.AltScreen.Rows, AViewH);
  for Y := 0 to Rows - 1 do
    for X := 0 to Cols - 1 do
    begin
      Cell := FHistory.AltScreen.Grid[Y][X];
      Ch := Cell.CharValue;
      Fg := Cell.FgColor;
      Bg := Cell.BgColor;
      if ccaReverse in Cell.Attributes then
      begin
        Tmp := Fg; Fg := Bg; Bg := Tmp;
      end;
      DrawGridChar(Buffer, 1 + X, 1 + Y, Ch, Fg, Bg);
      if FCursorVisible and (Y = FHistory.AltScreen.CursorRow) and
         (X = FHistory.AltScreen.CursorCol) then
        MarkGridInsertCaret(Buffer, 1 + X, 1 + Y);
    end;
end;

{ ---- Notify ----------------------------------------------------------------- }

procedure TBaseConsoleWindow.DialogChanged(Sender: TObject);
begin
  NotifyHost;
end;

procedure TBaseConsoleWindow.NotifyHost;
begin
  FNotifyDirty     := False;
  FLastNotifyTick  := GetTickCount64;
  Invalidate;
  if Assigned(FOnContentChanged) then
    FOnContentChanged(Self);
end;

procedure TBaseConsoleWindow.NotifyHostThrottled;
var
  Gen: Integer;
begin
  FNotifyDirty := True;
  if (GetTickCount64 - FLastNotifyTick) >= cMinNotifyMs then
  begin
    NotifyHost;
    Exit;
  end;
  if FNotifyFlushQueued then
    Exit;
  FNotifyFlushQueued := True;
  Gen := FCallbackGen;
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(cMinNotifyMs);
      TThread.Synchronize(nil,
        procedure
        begin
          FNotifyFlushQueued := False;
          if FAlive and (Gen = FCallbackGen) and FNotifyDirty then
            NotifyHost;
        end);
    end).Start;
end;

{ ---- Output ----------------------------------------------------------------- }

procedure TBaseConsoleWindow.AppendOutput(const AText: string);
var
  Deleted: Integer;
begin
  if not FAlive or not Assigned(FHistory) then
    Exit;
  Deleted := FHistory.AppendOutputEx(AText, PtyCols, PtyRows);
  AdjustSelectionForTrim(Deleted);
  NotifyHostThrottled;
end;

procedure TBaseConsoleWindow.AppendLocalInput(const AText: string);
var
  Deleted: Integer;
begin
  if not FAlive or not Assigned(FHistory) then
    Exit;
  Deleted := FHistory.AppendLocalInput(AText);
  AdjustSelectionForTrim(Deleted);
  NotifyHostThrottled;
end;

{ ---- Lifecycle -------------------------------------------------------------- }

procedure TBaseConsoleWindow.DoClose;
var
  Evt: TNotifyEvent;
begin
  if not FAlive then
    Exit;
  FAlive := False;
  // Invalidate every PTY callback captured against the previous generation:
  // pending FlushPendingToUi / QueueExit lambdas guard on Gen = FCallbackGen,
  // so bumping the generation here (not only in Destroy) drops stragglers that
  // would otherwise fire ProcessExited/AppendOutput between DoClose and Free.
  Inc(FCallbackGen);
  Interrupt;
  if Assigned(FPty) then
  begin
    FPty.OnOutput := nil;
    FPty.OnExit := nil;
    FPty.Terminate;
  end;
  FRunning := False;
  Evt := FOnCloseRequest;
  FOnCloseRequest := nil;
  // Drop the content-changed sink too: NotifyHost could still be reached via a
  // queued throttled flush and would otherwise recompose a half-closed window.
  FOnContentChanged := nil;
  if Assigned(Evt) then
    Evt(Self);
end;

procedure TBaseConsoleWindow.Interrupt;
begin
  if Assigned(FPty) and FPty.IsRunning then
    FPty.WriteInput(#3);
end;

procedure TBaseConsoleWindow.ShutdownForSessionEnd;
begin
  if not FAlive then
    Exit;
  FAlive := False;
  Inc(FCallbackGen);
  FPendingClose := True;
  FOnCloseRequest := nil;
  FOnContentChanged := nil;
  if Assigned(FPty) then
  begin
    FPty.OnOutput := nil;
    FPty.OnExit := nil;
    if FPty.IsRunning then
      FPty.Terminate;
  end;
  FRunning := False;
end;

function TBaseConsoleWindow.IsRunning: Boolean;
begin
  Result := FRunning or (Assigned(FPty) and FPty.IsRunning);
end;

{ ---- Selection helpers ------------------------------------------------------ }

procedure TBaseConsoleWindow.SetCursorVisible(AVisible: Boolean);
begin
  if FCursorVisible = AVisible then
    Exit;
  FCursorVisible := AVisible;
  NotifyHost;
end;

procedure TBaseConsoleWindow.ClearSelection;
begin
  FSelAnchorRow := -1;
  FSelAnchorCol := 0;
end;

function TBaseConsoleWindow.HasSelection: Boolean;
begin
  Result := (FSelAnchorRow >= 0) and
    ((FSelAnchorRow <> FCursorRow) or (FSelAnchorCol <> FCursorCol));
end;

procedure TBaseConsoleWindow.GetSelRange(out ARow1, ACol1, ARow2, ACol2: Integer);
begin
  if (FSelAnchorRow < FCursorRow) or
     ((FSelAnchorRow = FCursorRow) and (FSelAnchorCol <= FCursorCol)) then
  begin
    ARow1 := FSelAnchorRow; ACol1 := FSelAnchorCol;
    ARow2 := FCursorRow;    ACol2 := FCursorCol;
  end
  else
  begin
    ARow1 := FCursorRow;    ACol1 := FCursorCol;
    ARow2 := FSelAnchorRow; ACol2 := FSelAnchorCol;
  end;
end;

function TBaseConsoleWindow.IsCellSelected(ARow, ACol: Integer): Boolean;
var
  R1, C1, R2, C2: Integer;
begin
  Result := False;
  if not HasSelection then
    Exit;
  GetSelRange(R1, C1, R2, C2);
  if (ARow < R1) or (ARow > R2) then
    Exit;
  if R1 = R2 then
    Result := (ACol >= C1) and (ACol < C2)
  else if ARow = R1 then
    Result := ACol >= C1
  else if ARow = R2 then
    Result := ACol < C2
  else
    Result := True;
end;

function TBaseConsoleWindow.SelectedText: string;
var
  R1, C1, R2, C2, R: Integer;
  Line: string;
  Parts: TArray<string>;
begin
  Result := '';
  if not HasSelection then
    Exit;
  GetSelRange(R1, C1, R2, C2);
  if R1 = R2 then
  begin
    Line   := FHistory.GetLine(R1);
    Result := Copy(Line, C1 + 1, C2 - C1);
    Exit;
  end;
  SetLength(Parts, R2 - R1 + 1);
  Line    := FHistory.GetLine(R1);
  Parts[0] := Copy(Line, C1 + 1, MaxInt);
  for R := R1 + 1 to R2 - 1 do
    Parts[R - R1] := FHistory.GetLine(R);
  Line              := FHistory.GetLine(R2);
  Parts[R2 - R1]    := Copy(Line, 1, C2);
  Result := string.Join(#10, Parts);
end;

procedure TBaseConsoleWindow.SelectAll;
var
  Last: Integer;
  Line: string;
begin
  Last := Max(FHistory.LineCount - 1, 0);
  Line := FHistory.GetLine(Last);
  FSelAnchorRow := 0;
  FSelAnchorCol := 0;
  FCursorRow    := Last;
  FCursorCol    := Length(Line);
  FHistory.FollowTail := False;
  NotifyHost;
end;

procedure TBaseConsoleWindow.AdjustSelectionForTrim(ADeleted: Integer);
begin
  if ADeleted <= 0 then
    Exit;
  if FSelAnchorRow >= 0 then
  begin
    Dec(FSelAnchorRow, ADeleted);
    if FSelAnchorRow < 0 then
      ClearSelection;
  end;
  Dec(FCursorRow, ADeleted);
  if FCursorRow < 0 then
  begin
    FCursorRow := 0;
    FCursorCol := 0;
    ClearSelection;
  end;
end;

procedure TBaseConsoleWindow.ClampPos(var ARow, ACol: Integer);
var
  N: Integer;
  Line: string;
begin
  N := Max(FHistory.LineCount - 1, 0);
  if ARow < 0 then ARow := 0;
  if ARow > N then ARow := N;
  Line := FHistory.GetLine(ARow);
  if ACol < 0 then            ACol := 0;
  if ACol > Length(Line) then ACol := Length(Line);
end;

procedure TBaseConsoleWindow.EnsureCursorVisible;
var
  ViewH, Total, Top: Integer;
begin
  ViewH := ViewHeight;
  FHistory.GetScrollMetrics(ViewH, Total, Top);
  if FCursorRow < Top then
  begin
    FHistory.FollowTail := False;
    FHistory.ScrollTo(FCursorRow, ViewH);
  end
  else if FCursorRow >= Top + ViewH then
  begin
    FHistory.FollowTail := False;
    FHistory.ScrollTo(FCursorRow - ViewH + 1, ViewH);
  end;
end;

procedure TBaseConsoleWindow.SetCursorPos(ARow, ACol: Integer; AExtendSel: Boolean);
begin
  ClampPos(ARow, ACol);
  if AExtendSel then
  begin
    if FSelAnchorRow < 0 then
    begin
      FSelAnchorRow := FCursorRow;
      FSelAnchorCol := FCursorCol;
    end;
  end
  else
    ClearSelection;
  FCursorRow := ARow;
  FCursorCol := ACol;
  FHistory.FollowTail := False;
  EnsureCursorVisible;
  NotifyHost;
end;

procedure TBaseConsoleWindow.MoveSelCursor(ARowDelta, AColDelta: Integer;
  AExtendSel: Boolean);
var
  Row, Col: Integer;
  Line: string;
begin
  Row := FCursorRow;
  Col := FCursorCol;
  if AColDelta <> 0 then
  begin
    Col := Col + AColDelta;
    Line := FHistory.GetLine(Row);
    if Col < 0 then
    begin
      if Row > 0 then
      begin
        Dec(Row);
        Col := Length(FHistory.GetLine(Row));
      end
      else
        Col := 0;
    end
    else if Col > Length(Line) then
    begin
      if Row < FHistory.LineCount - 1 then
      begin
        Inc(Row);
        Col := 0;
      end
      else
        Col := Length(Line);
    end;
  end;
  if ARowDelta <> 0 then
  begin
    Row := Row + ARowDelta;
    ClampPos(Row, Col);
  end;
  SetCursorPos(Row, Col, AExtendSel);
end;

function TBaseConsoleWindow.HitTextCell(ALocalCol, ALocalRow: Integer;
  out ARow, ACol: Integer): Boolean;
var
  ViewH, Total, Top, TextW: Integer;
begin
  Result := False;
  ARow := 0;
  ACol := 0;
  ViewH := ViewHeight;
  TextW := TextWidth;
  if (ALocalRow < 1) or (ALocalRow > ViewH) then
    Exit;
  if (ALocalCol < 1) or (ALocalCol > TextW) then
    Exit;
  FHistory.GetScrollMetrics(ViewH, Total, Top);
  ARow := Top + (ALocalRow - 1);
  if (ARow < 0) or (ARow >= Total) then
    Exit;
  ACol := ALocalCol - 1;
  ClampPos(ARow, ACol);
  Result := True;
end;

{ ---- Clipboard ------------------------------------------------------------- }

procedure TBaseConsoleWindow.ClipboardSetText(const AText: string);
var
  Svc: IFMXClipboardService;
begin
  if AText = '' then
    Exit;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Svc.SetClipboard(AText);
end;

function TBaseConsoleWindow.ClipboardGetText: string;
var
  Svc: IFMXClipboardService;
  V: TValue;
begin
  Result := '';
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  V := Svc.GetClipboard;
  if not V.IsEmpty and V.IsType<string> then
    Result := V.AsString;
end;

procedure TBaseConsoleWindow.CopySelection;
begin
  if HasSelection then
    ClipboardSetText(SelectedText);
end;

procedure TBaseConsoleWindow.PasteClipboard;
var
  Text: string;
begin
  Text := ClipboardGetText;
  if Text = '' then
    Exit;
  if ProfileUsesLineBufferedInput(ProfileId) then
    AppendLocalInput(Text)
  else
    SendRaw(Text);
end;

{ ---- Raw PTY write --------------------------------------------------------- }

procedure TBaseConsoleWindow.SendRaw(const AText: string);
begin
  if (AText = '') or not Assigned(FPty) then
    Exit;
  FPty.WriteInput(AText);
end;

procedure TBaseConsoleWindow.SendInitCommand(const AText: string);
var
  I: Integer;
begin
  if (AText = '') or not Assigned(FPty) then
    Exit;
  for I := 1 to Length(AText) do
    FPty.WriteInput(AText[I]);
end;

function TBaseConsoleWindow.HandleLineBufferedPtyInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  Cmd: string;
begin
  Result := False;
  if not ProfileUsesLineBufferedInput(ProfileId) then
    Exit;

  case AKey of
    vkReturn:
      begin
        Cmd := Trim(FHistory.GetInputAfterPrompt);
        if Cmd <> '' then
        begin
          // Record the original typed text, not the pipe-safe-transformed
          // variant sent below.
          NoteCommandSubmitted(Cmd);
          if (ProfileId = cShellProfilePowerShell) or (ProfileId = cShellProfilePwsh) then
            Cmd := PsPipeSafeCommand(Cmd);
          SendRaw(Cmd + ProfileReturnSeq(ProfileId));
        end
        else
          SendRaw(ProfileReturnSeq(ProfileId));
        FHistory.CommitInputLine;
        NotifyHostThrottled;
        AKey := 0;
        AKeyChar := #0;
        Result := True;
      end;
    vkBack:
      begin
        AppendLocalInput(ProfileBackspaceChar(ProfileId));
        AKey := 0;
        AKeyChar := #0;
        Result := True;
      end;
  else
    if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
       not (ssCtrl in AShift) and not (ssAlt in AShift) then
    begin
      AppendLocalInput(AKeyChar);
      AKey := 0;
      AKeyChar := #0;
      Result := True;
    end;
  end;
end;

{ ---- Shared command history (Alt+F8) ---------------------------------------- }

procedure TBaseConsoleWindow.NoteCommandSubmitted(const ACommand: string);
var
  Cmd: string;
begin
  Cmd := Trim(ACommand);
  if (Cmd = '') or AltScreenActive then
    Exit;
  if Assigned(FOnCommandExecuted) then
    FOnCommandExecuted(Cmd);
end;

procedure TBaseConsoleWindow.ExecuteCommandNow(const ACommand: string);
var
  Cmd: string;
begin
  Cmd := Trim(ACommand);
  if Cmd = '' then
    Exit;
  SendRaw(Cmd + ProfileReturnSeq(ProfileId));
  NoteCommandSubmitted(Cmd);
end;

procedure TBaseConsoleWindow.OpenCmdHistoryDialog;
begin
  if not Assigned(FDialog) or (FDialog.Visible) then
    Exit;
  if not Assigned(FOnGetCmdHistory) then
    Exit;
  FCmdHistAllItems := FOnGetCmdHistory();
  FCmdHistItems := FCmdHistAllItems;
  FCmdHistFilter := '';
  FCmdHistDialogOpen := True;
  FDialog.Open(BuildCmdHistoryDialog(FCmdHistItems, 0), CmdHistoryDialogCommand);
  NotifyHost;
end;

procedure TBaseConsoleWindow.RefreshCmdHistoryDialog;
var
  Filtered: TArray<string>;
  I, N: Integer;
  Decl: TDialogDeclaration;
begin
  SetLength(Filtered, Length(FCmdHistAllItems));
  N := 0;
  for I := 0 to High(FCmdHistAllItems) do
    if (FCmdHistFilter = '') or
       (Pos(LowerCase(FCmdHistFilter), LowerCase(FCmdHistAllItems[I])) > 0) then
    begin
      Filtered[N] := FCmdHistAllItems[I];
      Inc(N);
    end;
  SetLength(Filtered, N);
  FCmdHistItems := Filtered;
  Decl := BuildCmdHistoryDialog(Filtered, 0);
  if FCmdHistFilter <> '' then
    Decl.Title := T('ui.cmdHistory.filterTitle', 'Command history: %s', [FCmdHistFilter]);
  FDialog.Open(Decl, CmdHistoryDialogCommand);
  NotifyHost;
end;

function TBaseConsoleWindow.HandleCmdHistoryFilterInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
begin
  Result := False;
  if not FCmdHistDialogOpen then
    Exit;
  if (AKeyChar >= ' ') and (Ord(AKeyChar) <> 127) and
     not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    FCmdHistFilter := FCmdHistFilter + AKeyChar;
    RefreshCmdHistoryDialog;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
  if AKey = vkBack then
  begin
    if FCmdHistFilter <> '' then
    begin
      Delete(FCmdHistFilter, Length(FCmdHistFilter), 1);
      RefreshCmdHistoryDialog;
    end;
    AKey := 0;
    AKeyChar := #0;
    Exit(True);
  end;
end;

procedure TBaseConsoleWindow.CmdHistoryDialogCommand(const AControlId,
  AValuesJson: string);
var
  Idx: Integer;
  Accepted: Boolean;
  Cmd: string;
begin
  FCmdHistDialogOpen := False;
  // Snapshot before Close: it releases the declaration AControlId points into.
  Idx := FDialog.GetListSelectedIndex('commands');
  Accepted := DialogCmdIsListAccept(AControlId, 'commands');
  Cmd := '';
  if Accepted and (Idx >= 0) and (Idx <= High(FCmdHistItems)) then
    Cmd := FCmdHistItems[Idx];
  FDialog.Close;
  SetLength(FCmdHistItems, 0);
  SetLength(FCmdHistAllItems, 0);
  FCmdHistFilter := '';
  if Cmd <> '' then
    ExecuteCommandNow(Cmd);
  NotifyHost;
end;

{ ---- Scrollbar drawing ----------------------------------------------------- }

procedure TBaseConsoleWindow.DrawScrollBar(ATotal, ATop, AViewH,
  ATopY, ABottomY: Integer);
var
  Span, ThumbAt, I, MaxTop: Integer;
  AX: Integer;
begin
  AX   := Area.Width - 2;
  Span := ABottomY - ATopY + 1;
  if Span < 2 then
    Exit;
  DrawGridChar(Buffer, AX, ATopY,    #$25B2, TAlphaColor($FFE0E0E0), TAlphaColor($FF000000));
  DrawGridChar(Buffer, AX, ABottomY, #$25BC, TAlphaColor($FFE0E0E0), TAlphaColor($FF000000));
  for I := ATopY + 1 to ABottomY - 1 do
    DrawGridChar(Buffer, AX, I, chShadeLight, TAlphaColor($FFE0E0E0), TAlphaColor($FF000000));
  MaxTop  := Max(ATotal - AViewH, 0);
  ThumbAt := ATopY + 1;
  if (MaxTop > 0) and (Span > 3) then
    Inc(ThumbAt, EnsureRange(Round(ATop * (Span - 3) / MaxTop), 0, Span - 3));
  DrawGridChar(Buffer, AX, ThumbAt, chBlock, TAlphaColor($FF30F0F0), TAlphaColor($FF000000));
end;

{ ---- Common keyboard ------------------------------------------------------- }

function TBaseConsoleWindow.HandleCommonInput(var AKey: Word;
  AShift: TShiftState; var AKeyChar: Char): Boolean;
var
  ViewH: Integer;
begin
  Result := False;
  ViewH  := ViewHeight;

  // Alt+F8 — command history picker (matches Dual Panel's kaCmdHistory);
  // selecting an entry runs it immediately in this console.
  if (ssAlt in AShift) and not (ssCtrl in AShift) and not (ssShift in AShift) and
     (AKey = vkF8) then
  begin
    OpenCmdHistoryDialog;
    AKey := 0; AKeyChar := #0;
    Exit(True);
  end;

  // Ctrl+A — select all.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('A')) or (AKey = Ord('a')) or
      (AKeyChar = 'a') or (AKeyChar = 'A')) then
  begin
    SelectAll;
    AKey := 0; AKeyChar := #0;
    Exit(True);
  end;

  // Ctrl+C — copy selection (if any), handled by caller for interrupt.
  if (ssCtrl in AShift) and not (ssAlt in AShift) and
     ((AKey = Ord('C')) or (AKey = Ord('c')) or
      (AKeyChar = 'c') or (AKeyChar = 'C')) then
  begin
    if HasSelection then
    begin
      CopySelection;
      AKey := 0; AKeyChar := #0;
      Exit(True);
    end;
    // Let caller decide (interrupt vs. send to PTY).
    Exit(False);
  end;

  // Shift+arrows — extend selection.
  if (ssShift in AShift) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    case AKey of
      vkLeft:  begin MoveSelCursor(0, -1, True);     AKey := 0; Exit(True); end;
      vkRight: begin MoveSelCursor(0,  1, True);     AKey := 0; Exit(True); end;
      vkUp:    begin MoveSelCursor(-1, 0, True);     AKey := 0; Exit(True); end;
      vkDown:  begin MoveSelCursor( 1, 0, True);     AKey := 0; Exit(True); end;
      vkPrior: begin MoveSelCursor(-ViewH, 0, True); AKey := 0; Exit(True); end;
      vkNext:  begin MoveSelCursor( ViewH, 0, True); AKey := 0; Exit(True); end;
      vkHome:
        begin
          SetCursorPos(FCursorRow, 0, True);
          AKey := 0; Exit(True);
        end;
      vkEnd:
        begin
          SetCursorPos(FCursorRow, Length(FHistory.GetLine(FCursorRow)), True);
          AKey := 0; Exit(True);
        end;
    end;
  end;

  // Bare navigation (no Shift): scroll the view.
  if not (ssShift in AShift) and not (ssCtrl in AShift) and not (ssAlt in AShift) then
  begin
    case AKey of
      vkUp:
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(-1, ViewH);
          NotifyHost;
          AKey := 0; Exit(True);
        end;
      vkDown:
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(1, ViewH);
          NotifyHost;
          AKey := 0; Exit(True);
        end;
      vkPrior:
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(-ViewH, ViewH);
          NotifyHost;
          AKey := 0; Exit(True);
        end;
      vkNext:
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollBy(ViewH, ViewH);
          NotifyHost;
          AKey := 0; Exit(True);
        end;
      vkHome:
        begin
          FHistory.FollowTail := False;
          FHistory.ScrollToStart;
          NotifyHost;
          AKey := 0; Exit(True);
        end;
      vkEnd:
        begin
          FHistory.ScrollToEnd;
          NotifyHost;
          AKey := 0; Exit(True);
        end;
    end;
  end;
end;

function TBaseConsoleWindow.HandleMouseWheel(WheelDelta: Integer): Boolean;
var
  ViewH, Steps, I: Integer;
begin
  ViewH := ViewHeight;
  Steps := Max(Abs(WheelDelta) div 120, 1);
  FHistory.FollowTail := False;
  if WheelDelta > 0 then
    for I := 1 to Steps do
      FHistory.ScrollBy(-1, ViewH)
  else
    for I := 1 to Steps do
      FHistory.ScrollBy(1, ViewH);
  NotifyHost;
  Result := True;
end;

{ ---- Common mouse ---------------------------------------------------------- }

function TBaseConsoleWindow.HandleCommonMouseDown(ALocalCol, ALocalRow: Integer;
  AShift: TShiftState; AScrollTopY, AScrollBottomY: Integer;
  AOnFrameClose: TProc): Boolean;
var
  W, H, ViewH, Total, Top, MaxTop, TrackH, Row, Col: Integer;
  Frame: TRectI;
begin
  Result := False;
  FMouseSelecting := False;
  W := Area.Width;
  H := Area.Height;
  if (W < 8) or (H < 4) then
    Exit;

  // Window close [x].
  if Assigned(AOnFrameClose) then
  begin
    Frame := TRectI.Make(0, 0, W - 1, H - 1);
    if WindowFrameCloseHit(Frame, ALocalCol, ALocalRow) then
    begin
      AOnFrameClose();
      Exit(True);
    end;
  end;

  // Scrollbar column.
  if ALocalCol = W - 2 then
  begin
    if (ALocalRow < AScrollTopY) or (ALocalRow > AScrollBottomY) then
      Exit;
    ViewH := ViewHeight;
    FHistory.GetScrollMetrics(ViewH, Total, Top);
    MaxTop := Max(Total - ViewH, 0);
    Result := True;
    FHistory.FollowTail := False;
    if ALocalRow = AScrollTopY then
      FHistory.ScrollBy(-1, ViewH)
    else if ALocalRow = AScrollBottomY then
      FHistory.ScrollBy(1, ViewH)
    else if MaxTop > 0 then
    begin
      TrackH := Max(AScrollBottomY - AScrollTopY - 1, 1);
      FHistory.ScrollTo(
        Round((ALocalRow - AScrollTopY - 1) * MaxTop / Max(TrackH - 1, 1)), ViewH);
    end;
    NotifyHost;
    Exit;
  end;

  // Text cell hit.
  if not HitTextCell(ALocalCol, ALocalRow, Row, Col) then
    Exit;
  Result := True;
  if ssShift in AShift then
  begin
    FClicks.Reset;
    SetCursorPos(Row, Col, True);
  end
  else if FClicks.Hit(ALocalCol, ALocalRow) > 1 then
  begin
    // Double click = word, the next quick click = whole line; the range is
    // final, so no drag selection follows.
    SelectClickRange(Row, Col, FClicks.Count = 3);
    if not FCursorVisible then
      SetCursorVisible(True);
    Exit;
  end
  else
  begin
    FSelAnchorRow := Row;
    FSelAnchorCol := Col;
    FCursorRow    := Row;
    FCursorCol    := Col;
    FHistory.FollowTail := False;
    EnsureCursorVisible;
    NotifyHost;
  end;
  FMouseSelecting := True;
  if not FCursorVisible then
    SetCursorVisible(True);
end;

procedure TBaseConsoleWindow.SelectClickRange(ARow, ACol: Integer; AWholeLine: Boolean);
var
  Line: string;
  WStart, WEnd: Integer;
begin
  ClampPos(ARow, ACol);
  Line := FHistory.GetLine(ARow);
  if AWholeLine then
  begin
    WStart := 0;
    WEnd := Length(Line);
  end
  else
    TextWordRangeAt(Line, ACol, WStart, WEnd);
  FSelAnchorRow := ARow;
  FSelAnchorCol := WStart;
  FCursorRow := ARow;
  FCursorCol := WEnd;
  FHistory.FollowTail := False;
  EnsureCursorVisible;
  NotifyHost;
end;

function TBaseConsoleWindow.HandleCommonMouseMove(ALocalCol, ALocalRow: Integer): Boolean;
var
  Row, Col, ViewH: Integer;
begin
  Result := False;
  if not FMouseSelecting then
    Exit;
  Result := True;
  ViewH  := ViewHeight;

  if HitTextCell(ALocalCol, ALocalRow, Row, Col) then
  begin
    if (Row <> FCursorRow) or (Col <> FCursorCol) then
    begin
      if FSelAnchorRow < 0 then
      begin
        FSelAnchorRow := FCursorRow;
        FSelAnchorCol := FCursorCol;
      end;
      FCursorRow := Row;
      FCursorCol := Col;
      EnsureCursorVisible;
      NotifyHost;
    end;
    Exit;
  end;

  // Drag above/below → auto-scroll.
  if ALocalRow < 1 then
  begin
    FHistory.FollowTail := False;
    FHistory.ScrollBy(-1, ViewH);
    if HitTextCell(Max(ALocalCol, 1), 1, Row, Col) then
    begin
      if FSelAnchorRow < 0 then
      begin
        FSelAnchorRow := FCursorRow;
        FSelAnchorCol := FCursorCol;
      end;
      FCursorRow := Row;
      FCursorCol := Col;
    end;
    NotifyHost;
  end
  else if ALocalRow > ViewH then
  begin
    FHistory.FollowTail := False;
    FHistory.ScrollBy(1, ViewH);
    if HitTextCell(Max(ALocalCol, 1), ViewH, Row, Col) then
    begin
      if FSelAnchorRow < 0 then
      begin
        FSelAnchorRow := FCursorRow;
        FSelAnchorCol := FCursorCol;
      end;
      FCursorRow := Row;
      FCursorCol := Col;
    end;
    NotifyHost;
  end;
end;

function TBaseConsoleWindow.HandleCommonMouseUp: Boolean;
begin
  Result          := FMouseSelecting;
  FMouseSelecting := False;
end;

end.
