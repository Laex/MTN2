unit uMainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.UIConsts, System.Math, System.Generics.Collections, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Menus,
  Winapi.Windows, Winapi.Messages, Winapi.ActiveX, Winapi.MultiMon,
  uTerminalTypes, uThemeTypes, uTerminalWindow, uDualPanelTypes, uDualPanelWindow,
  uEditorWindow, uConsoleWindow, uMdiCompositor, uThemeRegistry, uThemeProxy,
  uTerminalRenderer, uSession, uWinFileDragDrop, uKeymap, uShellProfiles, uShellAssoc,
  uBaseConsoleWindow, uPluginHost, uVfsTypes, uColorCoding, uPanelColumns,
  uDisplaySettings, uStrings, uUpdateController;

type
  TMainForm = class(TForm)
    MainMenu: TMainMenu;
    miHelp: TMenuItem;
    miAbout: TMenuItem;
    miView: TMenuItem;
    miZoomIn: TMenuItem;
    miZoomOut: TMenuItem;
    miZoomReset: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
    procedure FormResize(Sender: TObject);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
  private
    FRenderer: TTerminalRenderer;
    FTheme: IThemeRenderer;
    /// <summary>Same object as FTheme, typed for SetInner — see uThemeProxy.
    /// Every window/dialog/controller holds this one shared IThemeRenderer
    /// reference, so switching FThemeProxy's inner theme repaints all of
    /// them without recreating anything.</summary>
    FThemeProxy: TThemeProxy;
    /// <summary>uThemeRegistry id of the active theme (session.json's
    /// 'theme'); kept in sync with FThemeProxy by SwitchTheme.</summary>
    FThemeName: string;
    FMdi: TMdiCompositor;
    FDualPanel: TDualPanelWindow;
    FConsole: TConsoleWindow;
    FSession: TMtnSession;  // last loaded/saved session (includes BackgroundConsoleProfile)
    FLastScale: Single;
    FNormalLeft: Single;
    FNormalTop: Single;
    FNormalWidth: Single;
    FNormalHeight: Single;
    FRestoringBounds: Boolean;
    FBlinkTimer: TTimer;
    FBlinkPhase: Boolean;   // True = cursor visible
    FCursorBlinkEnabled: Boolean;
    FContextMenuTimer: TTimer;
    /// <summary>Self-update (Help > Updates, quiet check shortly after start).</summary>
    FUpdater: TUpdateController;
    FUpdateTimer: TTimer;
    FAppVersion: string;
    FContextHoldPath: string;
    FContextHoldScreenX: Integer;
    FContextHoldScreenY: Integer;
    FContextHoldShown: Boolean;
    FPrevWndProc: Pointer;
    FSystemShutdown: Boolean;
    procedure PrepareForSystemShutdown;
    procedure ReleaseTaskbarButton;
    procedure BlinkTick(Sender: TObject);
    procedure ContextMenuHoldTick(Sender: TObject);
    procedure CancelContextMenuHold;
    procedure ArmContextMenuHold(const APath: string; AScreenX, AScreenY: Integer);
    function NativeWindowHandle: NativeUInt;
    procedure HandleCtrlTab(AReverse: Boolean);
    /// <summary>Alt+F4 bound in the keymap (default: external editor): run
    /// it instead of letting Windows close the window. False = not bound,
    /// the system closes the window as usual.</summary>
    function TryHandleBoundAltF4: Boolean;
    procedure UpdateBlinkTimer;
    procedure UpdateCaption;
    procedure SyncRenderer;
    procedure ApplyZoomDelta(ADelta: Single);
    function TryHandleZoom(var AKey: Word; var AKeyChar: Char;
      AShift: TShiftState): Boolean;
    procedure ComposeScene(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    function PointToCell(X, Y: Single; out ACol, ARow: Integer): Boolean;
    procedure Recompose;
    procedure EnsureDemoWindows;
    procedure CaptureNormalBounds;
    procedure ApplySessionWindow(const AWindow: TMtnWindowBounds);
    /// <summary>Theme named AThemeName (uThemeRegistry id), or the default
    /// when AThemeName is blank or unrecognized.</summary>
    function CreateTheme(const AThemeName: string): IThemeRenderer;
    /// <summary>Live theme switch (Stage 27): repoints FThemeProxy at a new
    /// concrete theme — every open window/dialog picks it up on its next
    /// repaint, no recreation needed — and remembers AThemeId for
    /// PersistSession. No-op if AThemeId is already active.</summary>
    procedure SwitchTheme(const AThemeId: string);
    /// <summary>FDualPanel.OnThemeSelect handler: the Theme dialog (Options
    /// menu) reports the id the user picked.</summary>
    procedure ThemeSelected(const AThemeId: string);
    /// <summary>FDualPanel.OnGetActiveThemeId: lets the Theme dialog
    /// preselect the currently active theme without owning that state itself.</summary>
    function GetActiveThemeId: string;
    function GetConsoleProfile: string;
    function GetDisplaySettings: TDisplaySettings;
    procedure ApplyDisplaySettings(const ASettings: TDisplaySettings);
    /// <summary>Theme to instantiate (session.json's 'theme') and the
    /// on-disk theme file to load fileColoring/palette overrides from
    /// (session.json's 'themeFile', independent of AThemeName — see
    /// TMtnSession.ThemeFile) for this run. Peeks session.json without
    /// applying the rest of the session (that still happens later, in
    /// TryRestoreSession, once FDualPanel/FRenderer exist).</summary>
    procedure PeekSessionTheme(out AThemeName, AThemeFile: string);
    /// <summary>Same idea as PeekSessionTheme, for the UI locale: the top
    /// menu bar (built once, inside EnsureDemoWindows/TTopMenuController.
    /// Create) needs uStrings already switched before that happens, not
    /// after TryRestoreSession runs.</summary>
    function PeekSessionLanguage: string;
    procedure TryRestoreSession;
    procedure PersistSession;
    procedure DualPanelContentChanged(Sender: TObject);
    procedure DualPanelOpenViewer(const AURI: string);
    procedure DualPanelOpenEditor(const AURI: string);
    procedure DualPanelShowProperties(const APaths: TArray<string>);
    function TryDualPanelQuickViewWheel(AWheelDelta: Integer): Boolean;
    procedure DualPanelQuitRequest(Sender: TObject);
    procedure DualPanelOpenUpdates(Sender: TObject);
    procedure UpdateTimerTick(Sender: TObject);
    procedure CreateUpdater;
    procedure DualPanelRunCommand(const ACommand, AWorkingDir: string);
    procedure DualPanelShellCwdSync(const APath: string);
    procedure DualPanelToggleConsole(Sender: TObject);
    procedure DualPanelOpenTerminal(const AProfileId, ACwd: string);
    function EnsureConsole: TConsoleWindow;
    procedure ShowConsoleMode;
    procedure ShowPanelMode;
    procedure ApplyConsoleLayout;
    procedure ConsoleContentChanged(Sender: TObject);
    procedure ConsoleCloseRequest(Sender: TObject);
    procedure ConsoleBackToPanels(Sender: TObject);
    procedure ConsoleDismiss(Sender: TObject);
    procedure ConsoleFocusCommandLine(Sender: TObject);
    /// <summary>Console-side Ctrl+Shift+O: push this console's WorkingDir
    /// into the Dual Panel's active panel (reverse of DualPanelShellCwdSync).</summary>
    procedure ConsoleSyncDirToPanels(Sender: TObject);
    /// <summary>Console-side Alt+F8: shared command-history source/sink,
    /// bridged to FDualPanel's cmdline history (the console has no cmdline
    /// of its own to own a history store).</summary>
    function ConsoleGetCmdHistory: TArray<string>;
    procedure ConsoleCommandExecuted(const ACommand: string);
    procedure ChangeConsoleProfile(const AProfileId: string);
    function DispatchTerminalKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    /// <summary>One dispatch target DispatchTerminalKey tries in order;
    /// each checks its own guard and, if it applies, forwards the key and
    /// reports whether it was consumed. Factored out so DispatchTerminalKey
    /// itself reads as a flat priority list.</summary>
    function TryDispatchDualPanelDialogKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    function TryDispatchBareEscapeKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    function TryDispatchConsoleScrollKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    function TryDispatchPanelCmdlineKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    function TryDispatchMdiActiveKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    function TryDispatchDualPanelGeneralKey(var Key: Word; var KeyChar: Char;
      Shift: TShiftState): Boolean;
    /// <summary>Common tail of every DispatchTerminalKey branch that
    /// consumed the key: zero it out, repaint, report handled.</summary>
    function ConsumeTerminalKey(var Key: Word; var KeyChar: Char): Boolean;
    /// <summary>True for Esc with no modifiers -- the "restore panels from
    /// ConsoleMode" shortcut's guard, factored out of DispatchTerminalKey's
    /// if-condition so it reads as one named check instead of four.</summary>
    function IsBareEscape(Key: Word; Shift: TShiftState): Boolean;
    /// <summary>True for paging/arrow navigation -- half of
    /// IsConsoleScrollOrSelectionKey.</summary>
    function IsConsoleNavigationKey(Key: Word): Boolean;
    /// <summary>True for Ctrl+C/Ctrl+A (copy/select-all, not Alt-combined)
    /// -- the other half of IsConsoleScrollOrSelectionKey.</summary>
    function IsConsoleCopySelectAllKey(Key: Word; KeyChar: Char;
      Shift: TShiftState): Boolean;
    /// <summary>True for a key DispatchTerminalKey routes to the active
    /// Console window while ConsoleMode owns input: paging/arrow
    /// navigation, or Ctrl+C/Ctrl+A for copy/select-all.</summary>
    function IsConsoleScrollOrSelectionKey(Key: Word; KeyChar: Char;
      Shift: TShiftState): Boolean;
    /// <summary>True while ConsoleMode owns input and the active MDI child
    /// really is FConsole -- the shared guard for routing keys to it.</summary>
    function IsConsoleActiveInConsoleMode: Boolean;
    /// <summary>True for a bare press/release of Alt/Ctrl/Shift (either
    /// side) with no other key -- KeyDown swallows it (F-bar update only,
    /// keeps the menu from stealing Alt) and KeyUp swallows it identically
    /// on release; shared so the two never drift apart.</summary>
    function IsAltGrDown: Boolean;
    function IsModifierOnlyKey(AKey: Word): Boolean;
    /// <summary>Ctrl+Alt+K, any Shift-of-K/k -- the keymap.json hot-reload
    /// shortcut FormKeyDown checks before dispatch (see its call site for
    /// why: the panel/cmdline would otherwise absorb the letter first).</summary>
    function IsReloadKeymapShortcut(AKey: Word; AKeyChar: Char;
      AShift: TShiftState): Boolean;
    procedure SyncKeyModifiers(Shift: TShiftState);
    /// <summary>One dispatch target FormMouseDown tries in order, mirroring
    /// DispatchTerminalKey's Try* pattern: each checks its own hit-test and,
    /// if it applies, forwards the click and reports whether it was
    /// consumed (repaint + Exit is then the caller's job, since FormMouseDown
    /// is a procedure and can't Exit(value) like a function can).</summary>
    function TryDispatchActiveMdiMouseDown(Col, Row: Integer; Shift: TShiftState;
      AButton: TMouseButton): Boolean;
    /// <summary>True when a click at (Col, Row) belongs to the background
    /// console rather than whatever the MDI compositor currently has active
    /// -- factored out of FormMouseDown's if-condition so it reads as one
    /// named check instead of four.</summary>
    function IsConsoleMouseTarget(Col, Row: Integer): Boolean;
    function TryDispatchConsoleMouseDown(Col, Row: Integer; Shift: TShiftState): Boolean;
    /// <summary>Dual Panel's click handling: a right-click arms the context
    /// menu (and reports handled, so FormMouseDown exits); a left-click just
    /// forwards to HandleClick/ArmFileDragFromCursor and lets FormMouseDown
    /// fall through to its own tail (Cancel-on-right-click is a no-op here,
    /// but Recompose still needs to run either way).</summary>
    function TryDispatchDualPanelMouseDown(Col, Row: Integer; Dbl: Boolean;
      Shift: TShiftState; AButton: TMouseButton; const AScreenPt: TPointF): Boolean;
    /// <summary>FormMouseMove's left-button-drag handling for Dual Panel:
    /// forwards the move to it while inside its bounds, and once it (or the
    /// caller) is armed for a file drag, starts the OS OLE drag as soon as
    /// the cursor leaves the panel content. Returns True when it already
    /// did everything the move needed (repaint or drag-start), so
    /// FormMouseMove should not fall through to the active-window dispatch
    /// below.</summary>
    function TryHandleDualPanelDragMove(Shift: TShiftState; X, Y: Single): Boolean;
    /// <summary>The active MDI child's own HandleMouseMove, picked by
    /// runtime type like TryDispatchActiveMdiMouseDown -- returns whether
    /// it reported handled (FormMouseMove repaints only then).</summary>
    function TryDispatchActiveMdiMouseMove(Col, Row: Integer): Boolean;
    function ResolveDropAtScreenPoint(const APoint: TPointF;
      out ADestURI: string; out AMove: Boolean): Boolean;
    procedure StartOleFileDrag(const APaths: TArray<string>);
    procedure EnsureShutdownHook;
    procedure HookProcessWindowsForShutdown;
    /// <summary>Stage 28: decodes the path from a WM_COPYDATA sent by a
    /// delegating second instance, restores/activates this window, and opens
    /// the path (empty path = activate only, no new tab).</summary>
    procedure HandleActivateRequest(ACds: PCopyDataStruct);
    /// <summary>Stage 28: shared by the startup CLI-arg path (FormCreate,
    /// after TryRestoreSession) and HandleActivateRequest — opens APath in a
    /// new tab on the active side. No-op for '' or a path that doesn't
    /// exist.</summary>
    procedure OpenPathFromArgument(const APath: string);
  protected
    procedure CreateHandle; override;
    procedure DestroyHandle; override;
  public
    function CloseQuery: Boolean; override;
    procedure DragOver(const Data: TDragObject; const Point: TPointF;
      var Operation: TDragOperation); override;
    procedure DragDrop(const Data: TDragObject; const Point: TPointF); override;
    procedure DragLeave; override;
    // Intercept Tab/Ctrl+Tab before FMX focus traversal (OnKeyDown is too late).
    procedure KeyDown(var Key: Word; var KeyChar: System.WideChar;
      Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; var KeyChar: System.WideChar;
      Shift: TShiftState); override;
  end;

var
  MainForm: TMainForm;

const
  AppName = 'MTN2';
  AppTitle = 'Modern Terminal Navigator 2';

implementation

{$R *.fmx}

uses
  FMX.Platform.Win, uOverlayRenderer, uSingleInstance, uUpdater, uDialogTypes;

const
  cBlinkIntervalMs = 530;   // standard Windows cursor blink rate
  cContextMenuHoldMs = 1000;

var
  GExtraWndProcs: TDictionary<HWND, Pointer>;

procedure EndProcessForSessionEnd;
begin
  // FMX's application WndProc answers a confirmed WM_ENDSESSION with
  // MainForm.Close and then Halt. Halt runs unit finalization (and
  // sk4d.dll's DLL_PROCESS_DETACH via the normal exit path) while the
  // desktop session is already going away. An access violation there is
  // reported by the RTL as "Runtime error 216/217". The session is ending
  // either way: save state, then leave without finalization or detach.
  try
    if Assigned(MainForm) then
      MainForm.PrepareForSystemShutdown;
  except
    // Persist or shell teardown can fail once the profile is going away.
    // The process is about to exit regardless.
  end;
  TerminateProcess(GetCurrentProcess, 0);
end;

function AllowEndSessionWndProc(AHwnd: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM): LRESULT; stdcall;
var
  Prev: Pointer;
begin
  Prev := nil;
  if Assigned(GExtraWndProcs) then
    GExtraWndProcs.TryGetValue(AHwnd, Prev);

  case AMsg of
    WM_QUERYENDSESSION:
      Exit(1);
    WM_ENDSESSION:
      if AWParam <> 0 then
      begin
        EndProcessForSessionEnd;
        Exit(0);
      end;
    WM_NCDESTROY:
      if Assigned(GExtraWndProcs) then
        GExtraWndProcs.Remove(AHwnd);
  end;

  if Prev <> nil then
    Result := CallWindowProc(Prev, AHwnd, AMsg, AWParam, ALParam)
  else
    Result := DefWindowProc(AHwnd, AMsg, AWParam, ALParam);
end;

procedure HookWindowForShutdown(AHwnd: HWND);
var
  Prev: Pointer;
begin
  if (AHwnd = 0) or not Assigned(GExtraWndProcs) then
    Exit;
  if GExtraWndProcs.ContainsKey(AHwnd) then
    Exit;
  Prev := Pointer(GetWindowLongPtr(AHwnd, GWLP_WNDPROC));
  if (Prev = nil) or (Prev = @AllowEndSessionWndProc) then
    Exit;
  GExtraWndProcs.Add(AHwnd, Prev);
  SetWindowLongPtr(AHwnd, GWLP_WNDPROC, NativeInt(@AllowEndSessionWndProc));
end;

// Restores every window HookWindowForShutdown subclassed. Must run before
// FMX tears down its platform services: TWinSystemAppearanceService and the
// ThreadSync window are freed with DeallocateHWnd, which reads the *current*
// GWLP_WNDPROC and hands it to FreeObjectInstance. Left hooked, that pointer
// is AllowEndSessionWndProc in this exe's code, and FreeObjectInstance writes
// into it -- an access violation in UnregisterCorePlatformServices on exit.
procedure UnhookWindowsForShutdown;
var
  Pair: TPair<HWND, Pointer>;
begin
  if not Assigned(GExtraWndProcs) then
    Exit;
  for Pair in GExtraWndProcs.ToArray do
    if IsWindow(Pair.Key) and
       (Pointer(GetWindowLongPtr(Pair.Key, GWLP_WNDPROC)) = @AllowEndSessionWndProc) then
      SetWindowLongPtr(Pair.Key, GWLP_WNDPROC, NativeInt(Pair.Value));
  FreeAndNil(GExtraWndProcs);
end;

function EnumThreadShutdownWindows(AHwnd: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  Result := True;
  if (AParam <> 0) and (AHwnd = HWND(AParam)) then
    Exit;
  HookWindowForShutdown(AHwnd);
end;

// Alt+Enter as the user means it. Left Alt: Alt down, no Ctrl. Right Alt on
// layouts with AltGr: Windows reports it as Right Alt + a synthetic Left Ctrl,
// so "Right Alt and Left Ctrl, but neither Left Alt nor Right Ctrl" is AltGr,
// not a Ctrl+Alt chord. A real Ctrl+Alt+Enter (reveal the item on the other
// panel) keeps going through FMX as before.
function MainFormWndProc(AHwnd: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM): LRESULT; stdcall;
begin
  if Assigned(MainForm) then
  begin
    case AMsg of
      WM_QUERYENDSESSION:
        begin
          // Return TRUE immediately. QUERYENDSESSION can still be cancelled
          // by another app; cleanup belongs in WM_ENDSESSION. FMX hidden
          // top-level HWNDs must also return TRUE (see
          // HookProcessWindowsForShutdown).
          Result := 1;
          Exit;
        end;
      WM_ENDSESSION:
        begin
          // Do not PostMessage(WM_CLOSE) and do not chain to FMX. FMX closes
          // the form and Halts, which is the Runtime error on logoff/reboot.
          if AWParam <> 0 then
            EndProcessForSessionEnd;
          Result := 0;
          Exit;
        end;
      WM_COPYDATA:
        begin
          MainForm.HandleActivateRequest(PCopyDataStruct(ALParam));
          Result := 1;
          Exit;
        end;
      WM_KEYDOWN, WM_SYSKEYDOWN:
        begin
          // FMX TCommonCustomForm.KeyDown always AdvanceTabFocus on vkTab
          // (Ctrl+Tab included) unless the form override consumes it first.
          // Catch it here, before FMX TranslateMessage / focus traversal.
          if (AWParam = VK_TAB) and (GetKeyState(VK_CONTROL) < 0) then
          begin
            MainForm.HandleCtrlTab(GetKeyState(VK_SHIFT) < 0);
            Result := 0;
            Exit;
          end;
          // FMX passes every WM_SYSKEYDOWN on to DefWindowProc after KeyDown,
          // and DefWindowProc turns Alt+F4 into SC_CLOSE. Not chained at all
          // (chaining too would run the key twice).
          if (AMsg = WM_SYSKEYDOWN) and (AWParam = VK_F4) and
             (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_SHIFT) >= 0) and
             MainForm.TryHandleBoundAltF4 then
          begin
            Result := 0;
            Exit;
          end;
        end;
      WM_MOUSEACTIVATE:
        begin
          // Windows only sends this while the window is still inactive.
          // Without MA_ACTIVATEANDEAT, the same click both activates the
          // window and is delivered as a normal WM_LBUTTONDOWN, which our
          // panel code treats as a real click -- including arming a file
          // drag (TDualPanelWindow.ArmFileDragFromCursor). Ordinary mouse
          // jitter while the user's hand is still moving into a just-
          // focused window is then enough to cross the 1-cell drag
          // threshold, starting a self drag/drop that pops the copy
          // dialog with no copy command ever issued. Eat the activating
          // click so focusing the window never acts on it.
          Result := MA_ACTIVATEANDEAT;
          Exit;
        end;
    end;
  end;
  if Assigned(MainForm) and (MainForm.FPrevWndProc <> nil) then
    Result := CallWindowProc(MainForm.FPrevWndProc, AHwnd, AMsg, AWParam, ALParam)
  else
    Result := DefWindowProc(AHwnd, AMsg, AWParam, ALParam);
end;

function TMainForm.TryHandleBoundAltF4: Boolean;
var
  Key: Word;
  KeyChar: System.WideChar;
begin
  Result := MatchActiveAction(vkF4, [ssAlt]) <> kaNone;
  if not Result then
    Exit;
  Key := vkF4;
  KeyChar := #0;
  KeyDown(Key, KeyChar, [ssAlt]);
end;

procedure TMainForm.HookProcessWindowsForShutdown;
var
  FormHwnd: HWND;
begin
  // FMX.Platform.Win's TWinSystemAppearanceService (and ThreadSync) use
  // AllocateHWnd. Those hidden top-level windows receive WM_QUERYENDSESSION
  // but their WndProc leaves Result=0, which Windows treats as a veto —
  // the form subclass returning TRUE is not enough. Force TRUE on every
  // other top-level HWND of this UI thread.
  if GExtraWndProcs = nil then
    GExtraWndProcs := TDictionary<HWND, Pointer>.Create;
  FormHwnd := HWND(NativeWindowHandle);
  EnumThreadWindows(GetCurrentThreadId, @EnumThreadShutdownWindows, LPARAM(FormHwnd));
  if ApplicationHWND <> FormHwnd then
    HookWindowForShutdown(ApplicationHWND);
end;

procedure TMainForm.EnsureShutdownHook;
var
  H: NativeUInt;
begin
  H := NativeWindowHandle;
  if (H <> 0) and (FPrevWndProc = nil) then
  begin
    FPrevWndProc := Pointer(GetWindowLongPtr(HWND(H), GWLP_WNDPROC));
    SetWindowLongPtr(HWND(H), GWLP_WNDPROC, NativeInt(@MainFormWndProc));
  end;
  HookProcessWindowsForShutdown;
end;

procedure TMainForm.OpenPathFromArgument(const APath: string);
begin
  if (APath = '') or not Assigned(FDualPanel) then
    Exit;
  FDualPanel.OpenPathAsNewTab(APath);
end;

procedure TMainForm.HandleActivateRequest(ACds: PCopyDataStruct);
var
  Path: string;
  H: HWND;
begin
  if ACds = nil then
    Exit;
  if ACds^.cbData >= SizeOf(Char) then
    SetString(Path, PChar(ACds^.lpData), (ACds^.cbData div SizeOf(Char)) - 1)
  else
    Path := '';

  H := HWND(NativeWindowHandle);
  if H <> 0 then
  begin
    if IsIconic(H) then
      ShowWindow(H, SW_RESTORE);
    SetForegroundWindow(H);
  end;

  OpenPathFromArgument(Path);
end;

procedure TMainForm.CreateHandle;
begin
  inherited CreateHandle;
  // FMX recreates the HWND (DPI, fullscreen, style). DestroyHandle already
  // restored FPrevWndProc; reinstall the form subclass and the process-wide
  // QUERYENDSESSION allow-hooks on the new handle.
  EnsureShutdownHook;
end;

procedure TMainForm.DestroyHandle;
var
  H: NativeUInt;
begin
  H := NativeWindowHandle;
  if (H <> 0) and (FPrevWndProc <> nil) then
  begin
    SetWindowLongPtr(HWND(H), GWLP_WNDPROC, NativeInt(FPrevWndProc));
    FPrevWndProc := nil;
  end;
  inherited DestroyHandle;
end;

function TMainForm.CloseQuery: Boolean;
begin
  if FSystemShutdown then
    Exit(True);
  Result := inherited CloseQuery;
end;

procedure TMainForm.PrepareForSystemShutdown;
begin
  if FSystemShutdown then
    Exit;
  FSystemShutdown := True;

  if Assigned(FBlinkTimer) then
    FBlinkTimer.Enabled := False;
  if Assigned(FContextMenuTimer) then
    FContextMenuTimer.Enabled := False;

  PersistSession;

  // FDualPanel owns Terminal Workspace tabs now and shuts them down itself.
  if Assigned(FDualPanel) then
    FDualPanel.PrepareForSystemShutdown;

  if Assigned(FConsole) then
    FConsole.ShutdownForSessionEnd;
end;

procedure TMainForm.BlinkTick(Sender: TObject);
var
  Doc: TEditorWindow;
begin
  if not Assigned(FDualPanel) then
    Exit;
  FBlinkPhase := not FBlinkPhase;

  // 1. Dual Panel command line
  FDualPanel.SetCursorVisible(FBlinkPhase);

  // 2. Active editor / viewer document
  Doc := FDualPanel.ActiveDocument;
  if Assigned(Doc) then
    Doc.SetCursorVisible(FBlinkPhase);

  // 3. Dialog host
  if Assigned(FDualPanel.Dialog) then
    FDualPanel.Dialog.SetCursorVisible(FBlinkPhase);

  // 4. Console input cursor (Dual Panel ConsoleMode)
  if Assigned(FConsole) and FConsole.Visible then
    FConsole.SetCursorVisible(FBlinkPhase);
end;

function TMainForm.NativeWindowHandle: NativeUInt;
begin
  if Handle <> nil then
    Result := NativeUInt(WindowHandleToPlatform(Handle).Wnd)
  else
    Result := 0;
end;

procedure TMainForm.HandleCtrlTab(AReverse: Boolean);
var
  Key: Word;
  Ch: Char;
  Shift: TShiftState;
begin
  if not Assigned(FDualPanel) or not FDualPanel.Visible then
    Exit;
  Key := vkTab;
  Ch := #0;
  Shift := [ssCtrl];
  if AReverse then
    Include(Shift, ssShift);
  if FDualPanel.HandleInput(Key, Shift, Ch) then
    Recompose;
end;

procedure TMainForm.CancelContextMenuHold;
begin
  if Assigned(FContextMenuTimer) then
    FContextMenuTimer.Enabled := False;
  FContextHoldPath := '';
  FContextHoldShown := False;
end;

procedure TMainForm.ArmContextMenuHold(const APath: string; AScreenX, AScreenY: Integer);
begin
  CancelContextMenuHold;
  if Trim(APath) = '' then
    Exit;
  FContextHoldPath := APath;
  FContextHoldScreenX := AScreenX;
  FContextHoldScreenY := AScreenY;
  FContextHoldShown := False;
  FContextMenuTimer.Enabled := True;
end;

procedure TMainForm.ContextMenuHoldTick(Sender: TObject);
var
  Path: string;
  X, Y: Integer;
begin
  FContextMenuTimer.Enabled := False;
  if FContextHoldShown or (FContextHoldPath = '') then
    Exit;
  if GetAsyncKeyState(VK_RBUTTON) >= 0 then
  begin
    CancelContextMenuHold;
    Exit;
  end;
  Path := FContextHoldPath;
  X := FContextHoldScreenX;
  Y := FContextHoldScreenY;
  FContextHoldShown := True;
  FContextHoldPath := '';
  ShellShowContextMenu(Path, X, Y, NativeWindowHandle);
end;

procedure TMainForm.UpdateBlinkTimer;
var
  Doc: TEditorWindow;
  ShouldBlink: Boolean;
begin
  if not Assigned(FBlinkTimer) or not Assigned(FDualPanel) then
    Exit;

  Doc := FDualPanel.ActiveDocument;
  ShouldBlink := FCursorBlinkEnabled and
    (FDualPanel.CmdFocused or FDualPanel.DialogVisible or Assigned(Doc) or
    (Assigned(FConsole) and FConsole.Visible and FDualPanel.ConsoleMode));
  FBlinkTimer.Enabled := ShouldBlink;

  if not FBlinkTimer.Enabled then
  begin
    FBlinkPhase := True;
    FDualPanel.SetCursorVisible(True);
    if Assigned(Doc) then
      Doc.SetCursorVisible(True);
    if Assigned(FDualPanel.Dialog) then
      FDualPanel.Dialog.SetCursorVisible(True);
    if Assigned(FConsole) then
      FConsole.SetCursorVisible(True);
  end;
end;

procedure TMainForm.UpdateCaption;
var
  ActiveTitle: string;
begin
  ActiveTitle := '';
  if Assigned(FMdi) and Assigned(FMdi.Active) then
    ActiveTitle := '  [' + FMdi.Active.Title + ']';
  if Assigned(FRenderer) then
    Caption := Format('%s - %s v%s  [%dx%d  %s %.0f%%%s]',
      [AppTitle, AppName, FAppVersion, FRenderer.Cols, FRenderer.Rows,
       T('ui.window.zoom', 'zoom'), FRenderer.Zoom * 100, ActiveTitle])
  else
    Caption := Format('%s - %s v%s', [AppTitle, AppName, FAppVersion]);
end;

procedure TMainForm.SyncRenderer;
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.Resize(ClientWidth, ClientHeight, Canvas);
  UpdateCaption;
  Invalidate;
end;

procedure TMainForm.ApplyZoomDelta(ADelta: Single);
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.AdjustZoom(ADelta, ClientWidth, ClientHeight, Canvas);
  UpdateCaption;
  Invalidate;
end;

function TMainForm.TryHandleZoom(var AKey: Word; var AKeyChar: Char;
  AShift: TShiftState): Boolean;
begin
  Result := False;
  // Ctrl++ / Ctrl+- select-by-extension on Dual Panel (and must not steal
  // those chords here). Zoom is Ctrl+MouseWheel; Ctrl+0 still resets.
  if not (ssCtrl in AShift) or (ssAlt in AShift) or (ssShift in AShift) then
    Exit;
  if (AKey = vkNumpad0) or (AKey = vk0) or (AKeyChar = '0') then
  begin
    if Assigned(FRenderer) then
    begin
      FRenderer.SetZoom(1.0, ClientWidth, ClientHeight, Canvas);
      UpdateCaption;
      Invalidate;
    end;
  end
  else
    Exit;
  AKey := 0;
  AKeyChar := #0;
  Result := True;
end;

procedure TMainForm.EnsureDemoWindows;
begin
  if not Assigned(FMdi) then
    Exit;
  if FMdi.Windows.Count > 0 then
    Exit;
  FDualPanel := TDualPanelWindow.Create(FTheme, FMdi.AllocId);
  FDualPanel.OnContentChanged := DualPanelContentChanged;
  FDualPanel.OnOpenViewer := DualPanelOpenViewer;
  FDualPanel.OnOpenEditor := DualPanelOpenEditor;
  FDualPanel.OnShowProperties := DualPanelShowProperties;
  FDualPanel.OnQuitRequest := DualPanelQuitRequest;
  FDualPanel.OnOpenUpdates := DualPanelOpenUpdates;
  FDualPanel.OnRunCommand := DualPanelRunCommand;
  FDualPanel.OnShellCwdSync := DualPanelShellCwdSync;
  FDualPanel.OnToggleConsole := DualPanelToggleConsole;
  FDualPanel.OnOpenTerminal := DualPanelOpenTerminal;
  FDualPanel.OnSetConsoleProfile := ChangeConsoleProfile;
  FDualPanel.OnGetConsoleProfile := GetConsoleProfile;
  FDualPanel.OnThemeSelect := ThemeSelected;
  FDualPanel.OnGetActiveThemeId := GetActiveThemeId;
  FDualPanel.OnGetDisplaySettings := GetDisplaySettings;
  FDualPanel.OnApplyDisplaySettings := ApplyDisplaySettings;
  FMdi.AttachWindow(FDualPanel);
end;

/// <summary>Windows monitor device name (e.g. '\\.\DISPLAY1') the given
/// HMONITOR refers to; '' if unavailable.</summary>
function MonitorDeviceName(AMonitor: HMONITOR): string;
var
  Info: TMonitorInfoEx;
begin
  Result := '';
  if AMonitor = 0 then
    Exit;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetMonitorInfo(AMonitor, @Info) then
    Result := Info.szDevice;
end;

type
  TMonitorSearch = record
    Device: string;
    WorkRect: TRect;
    Found: Boolean;
  end;
  PMonitorSearch = ^TMonitorSearch;

function EnumFindMonitorProc(AMonitor: HMONITOR; ADC: HDC; ARect: PRect;
  AData: LPARAM): BOOL; stdcall;
var
  Info: TMonitorInfoEx;
  Search: PMonitorSearch;
begin
  Result := True;
  Search := PMonitorSearch(AData);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetMonitorInfo(AMonitor, @Info) and SameText(Info.szDevice, Search.Device) then
  begin
    Search.WorkRect := Info.rcWork;
    Search.Found := True;
    Result := False; // stop enumeration — found it
  end;
end;

/// <summary>Work-area rect (Windows coords) of the monitor named ADevice,
/// if it is still connected. Used to restore a window onto the same
/// physical display it was closed on, even if the primary monitor or
/// monitor order changed meanwhile.</summary>
function TryFindMonitorWorkRect(const ADevice: string; out ARect: TRectF): Boolean;
var
  Search: TMonitorSearch;
begin
  Result := False;
  if ADevice = '' then
    Exit;
  Search.Device := ADevice;
  Search.Found := False;
  EnumDisplayMonitors(0, nil, @EnumFindMonitorProc, LPARAM(@Search));
  if Search.Found then
  begin
    ARect := RectF(Search.WorkRect.Left, Search.WorkRect.Top,
      Search.WorkRect.Right, Search.WorkRect.Bottom);
    Result := True;
  end;
end;

function EnumUnionMonitorProc(AMonitor: HMONITOR; ADC: HDC; ARect: PRect;
  AData: LPARAM): BOOL; stdcall;
var
  Info: TMonitorInfoEx;
  Union: PRect;
begin
  Result := True;
  Union := PRect(AData);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetMonitorInfo(AMonitor, @Info) then
    Winapi.Windows.UnionRect(Union^, Union^, Info.rcMonitor);
end;

/// <summary>Bounding rect (Windows coords) spanning every connected monitor.</summary>
function VirtualScreenRect: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  EnumDisplayMonitors(0, nil, @EnumUnionMonitorProc, LPARAM(@Result));
end;

/// <summary>True when at least a title-bar-sized chunk of the saved window
/// rect would land on some currently connected monitor — i.e. the position
/// is still sane to restore as-is. False for a rect left entirely off-screen
/// (its monitor unplugged, resolution shrunk, etc.), which should fall back
/// to the default window position instead of being nudged/clamped.</summary>
function IsSavedWindowPositionValid(const AWindow: TMtnWindowBounds): Boolean;
const
  cMinVisibleW = 80;
  cMinVisibleH = 40;
var
  VirtualScreen, WindowRect, Overlap: TRect;
begin
  VirtualScreen := VirtualScreenRect;
  if IsRectEmpty(VirtualScreen) then
    Exit(True); // couldn't enumerate monitors — don't block startup on that
  WindowRect := Rect(Round(AWindow.Left), Round(AWindow.Top),
    Round(AWindow.Left + AWindow.Width), Round(AWindow.Top + AWindow.Height));
  if not IntersectRect(Overlap, WindowRect, VirtualScreen) then
    Exit(False);
  Result := (Overlap.Right - Overlap.Left >= cMinVisibleW) and
    (Overlap.Bottom - Overlap.Top >= cMinVisibleH);
end;

procedure TMainForm.CaptureNormalBounds;
begin
  if FRestoringBounds then
    Exit;
  if WindowState <> System.UITypes.TWindowState.wsNormal then
    Exit;
  FNormalLeft := Left;
  FNormalTop := Top;
  FNormalWidth := Width;
  FNormalHeight := Height;
end;

procedure TMainForm.ApplySessionWindow(const AWindow: TMtnWindowBounds);
var
  L, T, W, H: Single;
  Work: TRectF;
begin
  if not AWindow.Valid then
    Exit;
  if not IsSavedWindowPositionValid(AWindow) then
    Exit; // off-screen on every connected monitor — keep the default position
  // Prefer the monitor the window was actually on last time — Screen.WorkAreaRect
  // alone only clamps against the primary display, which silently relocates a
  // window that was deliberately placed on a secondary monitor whenever monitor
  // order/primary designation changes even though that monitor is still there.
  if not TryFindMonitorWorkRect(AWindow.Display, Work) then
    Work := Screen.WorkAreaRect;
  W := EnsureRange(AWindow.Width, 480, Max(Work.Width, 480));
  H := EnsureRange(AWindow.Height, 320, Max(Work.Height, 320));
  L := AWindow.Left;
  T := AWindow.Top;
  if L + W < Work.Left + 80 then
    L := Work.Left;
  if L > Work.Right - 80 then
    L := Work.Right - Min(W, Work.Width);
  if T < Work.Top then
    T := Work.Top;
  if T > Work.Bottom - 40 then
    T := Max(Work.Top, Work.Bottom - 40);

  FRestoringBounds := True;
  try
    Position := TFormPosition.Designed;
    WindowState := System.UITypes.TWindowState.wsNormal;
    Left := Round(L);
    Top := Round(T);
    Width := Round(W);
    Height := Round(H);
    FNormalLeft := Left;
    FNormalTop := Top;
    FNormalWidth := Width;
    FNormalHeight := Height;
    if AWindow.Maximized then
      WindowState := System.UITypes.TWindowState.wsMaximized;
  finally
    FRestoringBounds := False;
  end;
end;

function TMainForm.CreateTheme(const AThemeName: string): IThemeRenderer;
begin
  Result := uThemeRegistry.CreateThemeByName(AThemeName);
end;

procedure TMainForm.SwitchTheme(const AThemeId: string);
var
  Id: string;
begin
  if not Assigned(FThemeProxy) then
    Exit;
  Id := AThemeId;
  if Id = '' then
    Id := uThemeRegistry.DefaultThemeId;
  if SameText(Id, FThemeName) then
    Exit;
  FThemeProxy.SetInner(CreateTheme(Id));
  FThemeName := Id;
  Recompose;
end;

procedure TMainForm.ThemeSelected(const AThemeId: string);
begin
  SwitchTheme(AThemeId);
end;

function TMainForm.GetActiveThemeId: string;
begin
  Result := FThemeName;
end;

function TMainForm.GetConsoleProfile: string;
begin
  if Assigned(FConsole) then
    Result := FConsole.ProfileId
  else
    Result := FSession.BackgroundConsoleProfile;
  Result := NormalizeShellProfileId(Result);
  if Result = '' then
    Result := cShellProfileCmd;
end;

function TMainForm.GetDisplaySettings: TDisplaySettings;
begin
  Result := DefaultDisplaySettings;
  if Assigned(FRenderer) then
  begin
    Result.FontName := FRenderer.FontName;
    Result.FontSize := FRenderer.BaseFontSize;
    Result.Zoom := FRenderer.Zoom;
  end;
  Result.CursorBlink := FCursorBlinkEnabled;
  if Assigned(FBlinkTimer) then
    Result.CursorBlinkMs := FBlinkTimer.Interval
  else
    Result.CursorBlinkMs := ClampDisplayBlinkMs(FSession.CursorBlinkMs);
  Result.ShowPanelIcons := GShowPanelIcons;
  Result.Language := CurrentLocale;
end;

procedure TMainForm.ApplyDisplaySettings(const ASettings: TDisplaySettings);
var
  LanguageChanged: Boolean;
begin
  FCursorBlinkEnabled := ASettings.CursorBlink;
  FSession.CursorBlink := ASettings.CursorBlink;
  FSession.CursorBlinkMs := ClampDisplayBlinkMs(ASettings.CursorBlinkMs);
  FSession.ShowPanelIcons := ASettings.ShowPanelIcons;
  GShowPanelIcons := ASettings.ShowPanelIcons;
  LanguageChanged := not SameText(CurrentLocale, ASettings.Language) and
    not (SameText(CurrentLocale, 'en') and (Trim(ASettings.Language) = ''));
  FSession.Language := ASettings.Language;
  if LanguageChanged then
  begin
    SetLocale(ASettings.Language);
    if Assigned(FDualPanel) then
      FDualPanel.ReloadMenuStructure;
  end;
  if Assigned(FBlinkTimer) then
    FBlinkTimer.Interval := FSession.CursorBlinkMs;
  if Assigned(FRenderer) then
  begin
    FRenderer.SetFont(ASettings.FontName, ASettings.FontSize,
      ClientWidth, ClientHeight, Canvas);
    FRenderer.SetZoom(ASettings.Zoom, ClientWidth, ClientHeight, Canvas);
    FSession.FontName := FRenderer.FontName;
    FSession.FontSize := FRenderer.BaseFontSize;
  end
  else
  begin
    FSession.FontName := ASettings.FontName;
    FSession.FontSize := ClampDisplayFontSize(ASettings.FontSize);
  end;
  UpdateBlinkTimer;
  UpdateCaption;
  Recompose;
end;

procedure TMainForm.PeekSessionTheme(out AThemeName, AThemeFile: string);
var
  Sess: TMtnSession;
begin
  AThemeName := '';
  AThemeFile := '';
  if TryLoadSession(DefaultSessionFilePath, Sess) then
  begin
    AThemeName := Sess.ThemeName;
    AThemeFile := Sess.ThemeFile;
  end;
end;

function TMainForm.PeekSessionLanguage: string;
var
  Sess: TMtnSession;
begin
  Result := '';
  if TryLoadSession(DefaultSessionFilePath, Sess) then
    Result := Sess.Language;
end;

procedure TMainForm.TryRestoreSession;
var
  Sess: TMtnSession;
begin
  if not Assigned(FDualPanel) or not Assigned(FRenderer) then
    Exit;
  if not TryLoadSession(DefaultSessionFilePath, Sess) then
    Exit;
  FSession := Sess;
  ApplySessionWindow(Sess.Window);
  FDualPanel.ApplySessionState(Sess.Panels);
  FDualPanel.TerminalCloseOnExit := Sess.TerminalCloseOnExit;
  FDualPanel.AutoSyncConsoleCwd := Sess.AutoSyncConsoleCwd;
  if Sess.RestoreWorkspaceOnStart then
    FDualPanel.RestoreWorkspaceLibrary(Sess.LastWorkspaceId);
  GCustomColumnsConfig := Sess.CustomColumns;
  GShowPanelIcons := Sess.ShowPanelIcons;
  FCursorBlinkEnabled := Sess.CursorBlink;
  FRenderer.SetFont(Sess.FontName, Sess.FontSize, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetZoom(Sess.Zoom, ClientWidth, ClientHeight, Canvas);
end;

procedure TMainForm.PersistSession;
var
  Sess: TMtnSession;
begin
  if not Assigned(FDualPanel) then
    Exit;
  CaptureNormalBounds;
  Sess.Version := cSessionVersion;
  if Assigned(FRenderer) then
    Sess.Zoom := FRenderer.Zoom
  else
    Sess.Zoom := 1.0;
  Sess.Window.Left := FNormalLeft;
  Sess.Window.Top := FNormalTop;
  Sess.Window.Width := FNormalWidth;
  Sess.Window.Height := FNormalHeight;
  Sess.Window.Maximized :=
    WindowState = System.UITypes.TWindowState.wsMaximized;
  Sess.Window.Valid := (FNormalWidth >= 200) and (FNormalHeight >= 160);
  Sess.Window.Display := MonitorDeviceName(
    MonitorFromWindow(HWND(NativeWindowHandle), MONITOR_DEFAULTTONEAREST));
  Sess.Panels := FDualPanel.ExportSessionState;
  // Save current background console profile.
  if Assigned(FConsole) then
  begin
    Sess.BackgroundConsoleProfile := FConsole.ProfileId;
    Sess.ConsoleRestartOnExit := FConsole.RestartOnExit;
  end
  else
  begin
    Sess.BackgroundConsoleProfile := FSession.BackgroundConsoleProfile;
    Sess.ConsoleRestartOnExit := FSession.ConsoleRestartOnExit;
  end;
  if Assigned(FDualPanel) then
  begin
    Sess.TerminalCloseOnExit := FDualPanel.TerminalCloseOnExit;
    Sess.AutoSyncConsoleCwd := FDualPanel.AutoSyncConsoleCwd;
  end
  else
  begin
    Sess.TerminalCloseOnExit := FSession.TerminalCloseOnExit;
    Sess.AutoSyncConsoleCwd := FSession.AutoSyncConsoleCwd;
  end;
  // Stage 27: FThemeName is the live theme (switched via the Theme dialog or
  // loaded from session.json at startup) — always the source of truth here.
  // ThemeFile (color-coding overrides) has no live-switch UI yet, so that
  // half keeps preserving whatever session.json had.
  Sess.ThemeName := FThemeName;
  Sess.ThemeFile := FSession.ThemeFile;
  if Assigned(FRenderer) then
  begin
    Sess.FontName := FRenderer.FontName;
    Sess.FontSize := FRenderer.BaseFontSize;
  end
  else
  begin
    Sess.FontName := FSession.FontName;
    Sess.FontSize := FSession.FontSize;
  end;
  Sess.CursorBlink := FCursorBlinkEnabled;
  if Assigned(FBlinkTimer) then
    Sess.CursorBlinkMs := FBlinkTimer.Interval
  else
    Sess.CursorBlinkMs := FSession.CursorBlinkMs;
  Sess.ShowPanelIcons := GShowPanelIcons;
  // Like ThemeName above: uStrings.CurrentLocale is the live, switched-at-
  // runtime value (Display dialog or the startup PeekSessionLanguage/
  // SetLocale call) -- always the source of truth, not whatever
  // session.json happened to have on disk before this save.
  Sess.Language := CurrentLocale;
  Sess.CustomColumns := GCustomColumnsConfig;
  Sess.LastWorkspaceId := FDualPanel.WorkspaceLibraryId;
  Sess.RestoreWorkspaceOnStart := FSession.RestoreWorkspaceOnStart or
    (FSession.Version < 1);
  FSession := Sess;
  SaveSession(DefaultSessionFilePath, Sess);
end;

procedure TMainForm.DualPanelContentChanged(Sender: TObject);
begin
  UpdateBlinkTimer;
  Recompose;
end;

procedure TMainForm.DualPanelQuitRequest(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.DualPanelOpenUpdates(Sender: TObject);
begin
  if Assigned(FUpdater) then
    FUpdater.OpenUpdatesDialog;
end;

procedure TMainForm.UpdateTimerTick(Sender: TObject);
begin
  FUpdateTimer.Enabled := False;
  if Assigned(FUpdater) then
    FUpdater.StartupCheck;
end;

procedure TMainForm.CreateUpdater;
var
  Host: TUpdateHost;
begin
  Host.ShowDialog :=
    function(ADecl: TDialogDeclaration; AOnCommand: TProc<string, string>): Boolean
    begin
      // Only over the panels: never pop up inside an editor, viewer or
      // terminal the user is working in. The controller retries later.
      Result := Assigned(FDualPanel) and Assigned(FMdi) and (FMdi.Active = FDualPanel) and
        FDualPanel.Visible and FDualPanel.ShowHostDialog(ADecl, AOnCommand);
      if Result then
        Recompose;
    end;
  Host.HasBusyJob :=
    function: Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.HasBusyJob;
    end;
  Host.RequestClose :=
    procedure
    begin
      Close;
    end;
  FUpdater := TUpdateController.Create(Host);
  FUpdateTimer := TTimer.Create(Self);
  FUpdateTimer.Interval := 5000;
  FUpdateTimer.OnTimer := UpdateTimerTick;
  FUpdateTimer.Enabled := True;
end;

procedure TMainForm.DualPanelOpenViewer(const AURI: string);
begin
  if (AURI = '') or not Assigned(FDualPanel) then
    Exit;
  FDualPanel.OpenDocument(AURI, True);
  if Assigned(FMdi) then
    FMdi.Activate(FDualPanel);
  Recompose;
end;

// Wheel over the Ctrl+Q text preview scrolls the preview; FMX gives the
// wheel no position, so take the cursor's.
function TMainForm.TryDualPanelQuickViewWheel(AWheelDelta: Integer): Boolean;
var
  P: TPointF;
  Col, Row: Integer;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.QuickViewVisible) then
    Exit;
  P := ScreenToClient(Screen.MousePos);
  if not PointToCell(P.X, P.Y, Col, Row) then
    Exit;
  if not FDualPanel.HitTest(Col, Row) then
    Exit;
  Result := FDualPanel.HandleMouseWheelAt(Col - FDualPanel.Area.Left,
    Row - FDualPanel.Area.Top, AWheelDelta);
end;

procedure TMainForm.DualPanelShowProperties(const APaths: TArray<string>);
begin
  ShellShowProperties(APaths, NativeWindowHandle);
end;

procedure TMainForm.DualPanelOpenEditor(const AURI: string);
begin
  if (AURI = '') or not Assigned(FDualPanel) then
    Exit;
  FDualPanel.OpenDocument(AURI, False);
  if Assigned(FMdi) then
    FMdi.Activate(FDualPanel);
  Recompose;
end;

function TMainForm.EnsureConsole: TConsoleWindow;
var
  ProfileId: string;
begin
  if not Assigned(FConsole) then
  begin
    // Use profile from last saved session; default to cmd.
    ProfileId := FSession.BackgroundConsoleProfile;
    if ProfileId = '' then
      ProfileId := cShellProfileCmd;
    FConsole := TConsoleWindow.Create(FTheme, FMdi.AllocId, ProfileId);
    FConsole.RestartOnExit := FSession.ConsoleRestartOnExit;
    FConsole.OnContentChanged := ConsoleContentChanged;
    FConsole.OnCloseRequest := ConsoleCloseRequest;
    FConsole.OnBackToPanels := ConsoleBackToPanels;
    FConsole.OnDismissConsole := ConsoleDismiss;
    FConsole.OnFocusCommandLine := ConsoleFocusCommandLine;
    FConsole.OnSyncDirToPanels := ConsoleSyncDirToPanels;
    FConsole.OnGetCmdHistory := ConsoleGetCmdHistory;
    FConsole.OnCommandExecuted := ConsoleCommandExecuted;
    // Keep the shared Dual Panel cmdline / F-keys / status visible below.
    FMdi.AttachWindow(FConsole);
    // AttachWindow activates the window; keep it hidden until Ctrl+O / command.
    FConsole.Visible := False;
    if Assigned(FDualPanel) then
      FMdi.Activate(FDualPanel);
  end;
  Result := FConsole;
end;

procedure TMainForm.ChangeConsoleProfile(const AProfileId: string);
var
  ProfileId: string;
  WasVisible: Boolean;
begin
  ProfileId := NormalizeShellProfileId(AProfileId);
  if ProfileId = '' then
    ProfileId := cShellProfileCmd;
  if Assigned(FConsole) and SameText(FConsole.ProfileId, ProfileId) then
    Exit;
  // Save new profile for future sessions.
  FSession.BackgroundConsoleProfile := ProfileId;
  // Restart running console immediately with the new profile. The console is
  // normally hidden (pre-warmed for Ctrl+O), so only bring it back to the
  // foreground if it was already visible when the profile changed.
  WasVisible := Assigned(FConsole) and FConsole.Visible;
  if Assigned(FConsole) then
  begin
    FConsole.OnCloseRequest   := nil;
    FConsole.OnContentChanged := nil;
    FConsole.OnBackToPanels   := nil;
    FConsole.OnDismissConsole := nil;
    FConsole.OnFocusCommandLine := nil;
    FConsole.OnSyncDirToPanels := nil;
    FConsole.OnGetCmdHistory := nil;
    FConsole.OnCommandExecuted := nil;
    FMdi.CloseWindow(FConsole);
    FConsole := nil;
  end;
  if WasVisible then
    ShowConsoleMode
  else
  begin
    // Re-create hidden and pre-warm the shell, exactly like FormCreate does.
    EnsureConsole;
    if Assigned(FConsole) and Assigned(FDualPanel) then
      FConsole.EnsureShell(FDualPanel.ActiveLocalPath);
  end;
  Recompose;
end;

procedure TMainForm.ApplyConsoleLayout;
begin
  // Console sizing is handled by LayoutMaximized via LayoutBottomMargin;
  // run it now so a command started before the next compose sees real bounds.
  if Assigned(FMdi) and Assigned(FRenderer) then
    FMdi.LayoutMaximized(FRenderer.Cols, FRenderer.Rows);
end;

procedure TMainForm.ShowConsoleMode;
begin
  EnsureConsole;
  if Assigned(FDualPanel) then
  begin
    FDualPanel.Visible := True;
    FDualPanel.ConsoleMode := True;
    FDualPanel.CmdFocused := False;
  end;
  FConsole.Visible := True;
  ApplyConsoleLayout;
  FMdi.Activate(FConsole);
  UpdateBlinkTimer;
end;

procedure TMainForm.ShowPanelMode;
begin
  if Assigned(FConsole) then
    FConsole.Visible := False;
  if Assigned(FDualPanel) then
  begin
    FDualPanel.ConsoleMode := False;
    FDualPanel.Visible := True;
    FMdi.Activate(FDualPanel);
  end;
  UpdateBlinkTimer;
end;

procedure TMainForm.DualPanelRunCommand(const ACommand, AWorkingDir: string);
begin
  if not Assigned(FMdi) then
    Exit;
  ShowConsoleMode;
  // Geometry must be applied before shell start (width drives wrapping hints).
  ApplyConsoleLayout;
  FConsole.RunCommand(ACommand, AWorkingDir);
  Recompose;
end;

procedure TMainForm.DualPanelShellCwdSync(const APath: string);
begin
  // Lazy: only push cd into an already-running persistent shell.
  if not Assigned(FConsole) then
    Exit;
  FConsole.SyncWorkingDir(APath);
end;

procedure TMainForm.ConsoleSyncDirToPanels(Sender: TObject);
begin
  if not Assigned(FConsole) or not Assigned(FDualPanel) then
    Exit;
  FDualPanel.SetActivePanelDir(FConsole.WorkingDir);
  Recompose;
end;

function TMainForm.ConsoleGetCmdHistory: TArray<string>;
begin
  if Assigned(FDualPanel) then
    Result := FDualPanel.GetCommandHistoryItems
  else
    SetLength(Result, 0);
end;

procedure TMainForm.ConsoleCommandExecuted(const ACommand: string);
begin
  if Assigned(FDualPanel) then
    FDualPanel.RecordConsoleCommand(ACommand);
end;

procedure TMainForm.DualPanelToggleConsole(Sender: TObject);
begin
  if not Assigned(FMdi) then
    Exit;
  // ConsoleMode: Ctrl+O always restores panels — it must never stop a
  // running command (that's Ctrl+C's job). If the flag is set but the
  // console window is not actually up (menu used to flip the flag only),
  // show the console instead of restoring an already-blank Dual Panel.
  if Assigned(FDualPanel) and FDualPanel.ConsoleMode then
  begin
    if Assigned(FConsole) and FConsole.Visible then
      ShowPanelMode
    else
      ShowConsoleMode;
    Recompose;
    Exit;
  end;
  if Assigned(FConsole) and FConsole.Visible and (FMdi.Active = FConsole) then
    ShowPanelMode
  else
    ShowConsoleMode;
  Recompose;
end;

procedure TMainForm.ConsoleContentChanged(Sender: TObject);
begin
  Recompose;
end;

procedure TMainForm.ConsoleCloseRequest(Sender: TObject);
var
  ConsoleToFree: TConsoleWindow;
begin
  if not (Sender is TConsoleWindow) or not Assigned(FMdi) then
    Exit;
  ConsoleToFree := FConsole;
  FConsole := nil;
  if Assigned(ConsoleToFree) then
  begin
    ConsoleToFree.OnCloseRequest := nil;
    ConsoleToFree.OnContentChanged := nil;
    ConsoleToFree.OnBackToPanels := nil;
    ConsoleToFree.OnDismissConsole := nil;
    ConsoleToFree.OnFocusCommandLine := nil;
    FMdi.CloseWindow(ConsoleToFree);
  end;
  ShowPanelMode;
  Recompose;
end;

procedure TMainForm.ConsoleBackToPanels(Sender: TObject);
begin
  ShowPanelMode;
  Recompose;
end;

procedure TMainForm.ConsoleDismiss(Sender: TObject);
begin
  if not Assigned(FConsole) then
    Exit;
  // Esc must never stop an in-flight command (Ctrl+C does that) — it only
  // restores Dual Panel, whether or not something is still running.
  ShowPanelMode;
  Recompose;
end;

procedure TMainForm.ConsoleFocusCommandLine(Sender: TObject);
begin
  if Assigned(FDualPanel) then
    FDualPanel.FocusCommandLine;
  Recompose;
end;

procedure TMainForm.DualPanelOpenTerminal(const AProfileId, ACwd: string);
begin
  if (AProfileId = '') or not Assigned(FDualPanel) then
    Exit;
  // Leave panel console overlay if open.
  if FDualPanel.ConsoleMode then
    ShowPanelMode;
  FDualPanel.OpenTerminal(AProfileId, ACwd);
  if Assigned(FMdi) then
    FMdi.Activate(FDualPanel);
  Recompose;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  SessionThemeNameValue, SessionThemeFileValue: string;
begin
  // From the exe's version resource (stamped from the release tag), so the
  // caption and the updater agree on what is installed.
  FAppVersion := AppVersionString;
  if FAppVersion = '' then
    FAppVersion := '?';
  FRestoringBounds := False;
  FNormalLeft := Left;
  FNormalTop := Top;
  FNormalWidth := Width;
  FNormalHeight := Height;

  ReloadKeymap('');

  SetLocale(PeekSessionLanguage);
  PeekSessionTheme(SessionThemeNameValue, SessionThemeFileValue);
  uColorCoding.SetActiveThemeFileName(SessionThemeFileValue);
  uColorCoding.ReloadColorCoding('');
  FThemeName := SessionThemeNameValue;
  if FThemeName = '' then
    FThemeName := uThemeRegistry.DefaultThemeId;
  FThemeProxy := TThemeProxy.Create(CreateTheme(FThemeName));
  FTheme := FThemeProxy;
  FMdi := TMdiCompositor.Create(FTheme);
  EnsureDemoWindows;

  StartPluginHost(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins'));

  FRenderer := TTerminalRenderer.Create;
  FRenderer.OnCompose := ComposeScene;
  // Defaults for a missing/unreadable session.json (TryRestoreSession leaves
  // FSession untouched on failure, which would otherwise zero-init to False).
  FSession.ConsoleRestartOnExit := True;
  FSession.TerminalCloseOnExit := True;
  FSession.AutoSyncConsoleCwd := False;
  FSession.RestoreWorkspaceOnStart := True;
  FSession.FontSize := cDisplayDefaultFontSize;
  FSession.CursorBlink := True;
  FSession.CursorBlinkMs := cBlinkIntervalMs;
  FSession.ShowPanelIcons := True;
  FCursorBlinkEnabled := True;
  TryRestoreSession;
  // Stage 28: mtn2 <path> — a brand new tab for the CLI path, restored
  // session tabs are left untouched. Updater switches (--wait-pid) are not paths.
  if StartupPathArgument <> '' then
    OpenPathFromArgument(StartupPathArgument);
  SyncRenderer;

  // Pre-warm the background Dual Panel console so the persistent shell is
  // already running by the time the user hits Ctrl+O or submits the first
  // command, instead of paying shell-startup latency on that first action.
  // Stays hidden — Dual Panel remains the active/visible window.
  EnsureConsole;
  if Assigned(FConsole) and Assigned(FDualPanel) then
    FConsole.EnsureShell(FDualPanel.ActiveLocalPath);

  FBlinkPhase := True;
  FBlinkTimer := TTimer.Create(Self);
  FBlinkTimer.Interval := ClampDisplayBlinkMs(FSession.CursorBlinkMs);
  FBlinkTimer.OnTimer := BlinkTick;
  FBlinkTimer.Enabled := False;

  FContextMenuTimer := TTimer.Create(Self);
  FContextMenuTimer.Interval := cContextMenuHoldMs;
  FContextMenuTimer.OnTimer := ContextMenuHoldTick;
  FContextMenuTimer.Enabled := False;

  CreateUpdater;

  // Stage 24: Quick View decode/error lands async — repaint once it does.
  SetOverlayRepaintHandler(
    procedure
    begin
      if not (csDestroying in ComponentState) then
        Invalidate;
    end);
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  EnsureShutdownHook;
  // Stage 28: only now is the native handle valid for a second instance to
  // find and send WM_COPYDATA to.
  PublishInstanceWindow(HWND(NativeWindowHandle));
end;

procedure TMainForm.ReleaseTaskbarButton;
var
  AppWnd, FormWnd: HWND;
begin
  // FMX creates a zero-size TFMAppClass window with WS_EX_APPWINDOW and owns
  // the real form from it. That owner is the taskbar button. Hiding only the
  // form leaves the button up for as long as process teardown still runs.
  FormWnd := HWND(NativeWindowHandle);
  AppWnd := ApplicationHWND;
  if (AppWnd <> 0) and (AppWnd <> FormWnd) then
    ShowWindow(AppWnd, SW_HIDE);
  if FormWnd <> 0 then
    ShowWindow(FormWnd, SW_HIDE);
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if FSystemShutdown then
    Exit;
  PersistSession;
  ReleaseTaskbarButton;
  // An update the user chose to install "on exit" (or deferred by a busy job).
  if Assigned(FUpdater) then
    FUpdater.BeforeExit;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  // Normal exit only: on session end the process is terminated before any
  // FMX finalization, and the hooks must keep answering WM_ENDSESSION.
  if not FSystemShutdown then
    UnhookWindowsForShutdown;
  if not FSystemShutdown then
    ReleaseTaskbarButton;
  // Before the panel window goes: the updater's dialogs live there.
  FreeAndNil(FUpdateTimer);
  FreeAndNil(FUpdater);
  StopPluginHost;
  FreeAndNil(FBlinkTimer);
  if not FSystemShutdown then
    PersistSession;
  if Assigned(FConsole) then
  begin
    if FSystemShutdown then
      FConsole.ShutdownForSessionEnd
    else
    begin
      FConsole.OnCloseRequest := nil;
      FConsole.OnContentChanged := nil;
      FConsole.OnBackToPanels := nil;
      FConsole.OnDismissConsole := nil;
      FConsole.OnFocusCommandLine := nil;
      FConsole.OnSyncDirToPanels := nil;
      FConsole.OnGetCmdHistory := nil;
      FConsole.OnCommandExecuted := nil;
      FConsole.Interrupt;
    end;
  end;
  // FDualPanel (freed below via FMdi) owns Terminal Workspace tabs and tears
  // them down in its own destructor (PrepareForSystemShutdown already ran
  // ShutdownForSessionEnd on each when FSystemShutdown).
  FreeAndNil(FRenderer);
  FDualPanel := nil;
  FConsole := nil;
  FreeAndNil(FMdi);
  FTheme := nil;
  FThemeProxy := nil;
  ReleaseSingleInstance;
end;

procedure TMainForm.ComposeScene(const AGrid: TTerminalGrid; ACols, ARows: Integer);
begin
  if not Assigned(FMdi) then
    Exit;
  // Console keeps a 2-row bottom margin (LayoutBottomMargin) for shared F-keys / status.
  FMdi.LayoutMaximized(ACols, ARows);
  FMdi.Paint(AGrid, ACols, ARows);
end;

function TMainForm.PointToCell(X, Y: Single; out ACol, ARow: Integer): Boolean;
begin
  ACol := 0;
  ARow := 0;
  Result := Assigned(FRenderer) and (FRenderer.CellWidth > 0) and
    (FRenderer.CellHeight > 0);
  if not Result then
    Exit;
  ACol := Trunc(X / FRenderer.CellWidth);
  ARow := Trunc(Y / FRenderer.CellHeight);
end;

procedure TMainForm.Recompose;
begin
  if (csDestroying in ComponentState) or not Assigned(FRenderer) then
    Exit;
  FRenderer.Recompose;
  UpdateCaption;
  Invalidate;
end;

procedure TMainForm.FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
begin
  if not Assigned(FRenderer) then
    Exit;
  if (Canvas.Scale > 0) and (Canvas.Scale <> FLastScale) then
  begin
    FLastScale := Canvas.Scale;
    FRenderer.SetSceneScale(Canvas.Scale, ClientWidth, ClientHeight, Canvas);
    UpdateCaption;
  end;
  FRenderer.Draw(Canvas, RectF(0, 0, ClientWidth, ClientHeight));
  // Markdown image blocks are sized in cells from the pixel cell aspect;
  // after a font/scale change re-lay out once so the next frame uses it.
  if SetOverlayCellMetrics(FRenderer.CellWidth, FRenderer.CellHeight) then
    TThread.ForceQueue(nil,
      procedure
      begin
        Recompose;
      end);
  // Stage 24: Media Overlay (Ctrl+Q Quick View) — separate canvas pass on
  // top of the grid, per OVERLAY_PLUGIN.md invariant 2 ("not TCharCell").
  // Gated by QuickViewVisible: the overlay's stored bounds only make sense
  // while Dual Panel is showing its wkPanels list, not Console/Viewer/
  // Editor/Terminal, and this Canvas pass has no other way to know that.
  if Assigned(FDualPanel) and FDualPanel.QuickViewVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight)
  // Stage 25: Markdown Viewer image reuses the same Media Overlay singleton.
  // F3 opens the Viewer as a Dual Panel document tab, so FMdi.Active is
  // DualPanel — not TEditorWindow. Check the nested document first; keep
  // the standalone-editor branch for a future MDI editor window.
  else if Assigned(FDualPanel) and FDualPanel.MarkdownImageOverlayVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight)
  else if Assigned(FMdi) and Assigned(FMdi.Active) and (FMdi.Active is TEditorWindow) and
          TEditorWindow(FMdi.Active).MarkdownImageOverlayVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight);
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  CaptureNormalBounds;
  SyncRenderer;
end;

procedure TMainForm.FormMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  K: Word;
  C: Char;
begin
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ApplyZoomDelta(0.1)
    else
      ApplyZoomDelta(-0.1);
    Handled := True;
  end
  else if TryDualPanelQuickViewWheel(WheelDelta) then
  begin
    Recompose;
    Handled := True;
  end
  else if Assigned(FMdi) and Assigned(FMdi.Active) then
  begin
    if (FMdi.Active is TBaseConsoleWindow) and
       TBaseConsoleWindow(FMdi.Active).HandleMouseWheel(WheelDelta) then
    begin
      Recompose;
      Handled := True;
    end
    else
    begin
      if WheelDelta > 0 then
        K := vkUp
      else
        K := vkDown;
      C := #0;
      if FMdi.Active.HandleInput(K, [], C) then
      begin
        Recompose;
        Handled := True;
      end;
    end;
  end;
end;

function TMainForm.TryDispatchActiveMdiMouseDown(Col, Row: Integer;
  Shift: TShiftState; AButton: TMouseButton): Boolean;
var
  LocalCol, LocalRow: Integer;
begin
  Result := False;
  if AButton <> TMouseButton.mbLeft then
    Exit;
  if not (Assigned(FMdi.Active) and FMdi.Active.HitTest(Col, Row)) then
    Exit;
  LocalCol := Col - FMdi.Active.Area.Left;
  LocalRow := Row - FMdi.Active.Area.Top;
  if (FMdi.Active is TDualPanelWindow) and
     TDualPanelWindow(FMdi.Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
    Exit(True);
  if (FMdi.Active is TEditorWindow) and
     TEditorWindow(FMdi.Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
    Exit(True);
  if (FMdi.Active is TConsoleWindow) and
     TConsoleWindow(FMdi.Active).HandleMouseDown(LocalCol, LocalRow, Shift) then
    Exit(True);
end;

function TMainForm.IsConsoleMouseTarget(Col, Row: Integer): Boolean;
begin
  Result := Assigned(FConsole) and FConsole.Visible and FConsole.HitTest(Col, Row) and
    (FMdi.Active <> FConsole);
end;

function TMainForm.TryDispatchConsoleMouseDown(Col, Row: Integer; Shift: TShiftState): Boolean;
var
  LocalCol, LocalRow: Integer;
begin
  Result := False;
  if not IsConsoleMouseTarget(Col, Row) then
    Exit;
  LocalCol := Col - FConsole.Area.Left;
  LocalRow := Row - FConsole.Area.Top;
  Result := FConsole.HandleMouseDown(LocalCol, LocalRow, Shift);
end;

function TMainForm.TryDispatchDualPanelMouseDown(Col, Row: Integer; Dbl: Boolean;
  Shift: TShiftState; AButton: TMouseButton; const AScreenPt: TPointF): Boolean;
var
  LocalCol, LocalRow: Integer;
  Path: string;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.HitTest(Col, Row)) then
    Exit;
  LocalCol := Col - FDualPanel.Area.Left;
  LocalRow := Row - FDualPanel.Area.Top;
  if AButton = TMouseButton.mbRight then
  begin
    CancelContextMenuHold;
    FDualPanel.HandleClick(LocalCol, LocalRow, False, Shift, False);
    if FDualPanel.HitTestListItemLocalPath(LocalCol, LocalRow, Path) then
      ArmContextMenuHold(Path, Round(AScreenPt.X), Round(AScreenPt.Y));
    Exit(True);
  end;
  FDualPanel.HandleClick(LocalCol, LocalRow, Dbl, Shift);
  if (AButton = TMouseButton.mbLeft) and not Dbl then
    FDualPanel.ArmFileDragFromCursor;
end;

procedure TMainForm.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Col, Row: Integer;
  Dbl: Boolean;
begin
  if not Assigned(FMdi) then
    Exit;
  if not PointToCell(X, Y, Col, Row) then
  begin
    if Button = TMouseButton.mbRight then
      CancelContextMenuHold;
    Exit;
  end;
  Dbl := (Button = TMouseButton.mbLeft) and (ssDouble in Shift);
  if Button = TMouseButton.mbLeft then
    CancelContextMenuHold;

  FMdi.ActivateAt(Col, Row);
  if TryDispatchActiveMdiMouseDown(Col, Row, Shift, Button) then
  begin
    Recompose;
    Exit;
  end;

  if TryDispatchConsoleMouseDown(Col, Row, Shift) then
  begin
    Recompose;
    Exit;
  end;

  if TryDispatchDualPanelMouseDown(Col, Row, Dbl, Shift, Button,
     ClientToScreen(TPointF.Create(X, Y))) then
  begin
    Recompose;
    Exit;
  end;

  if Button = TMouseButton.mbRight then
    CancelContextMenuHold;
  Recompose;
end;

function TMainForm.TryHandleDualPanelDragMove(Shift: TShiftState; X, Y: Single): Boolean;
var
  Col, Row, LocalCol, LocalRow: Integer;
  Paths: TArray<string>;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible and (ssLeft in Shift)) then
    Exit;
  if not PointToCell(X, Y, Col, Row) then
    Exit;
  LocalCol := Col - FDualPanel.Area.Left;
  LocalRow := Row - FDualPanel.Area.Top;
  // Inside the panel: try its own move handling (e.g. a selection drag)
  // first. Outside it, or declined -- but still armed from an earlier
  // mouse-down -- start the OS file drag toward wherever the cursor went.
  if FDualPanel.HitTest(Col, Row) and FDualPanel.HandleMouseMove(LocalCol, LocalRow) then
  begin
    Recompose;
    Exit(True);
  end;
  if FDualPanel.TryStartFileDrag(LocalCol, LocalRow, Paths) then
  begin
    StartOleFileDrag(Paths);
    Exit(True);
  end;
end;

function TMainForm.TryDispatchActiveMdiMouseMove(Col, Row: Integer): Boolean;
var
  LocalCol, LocalRow: Integer;
begin
  Result := False;
  if not Assigned(FMdi.Active) then
    Exit;
  LocalCol := Col - FMdi.Active.Area.Left;
  LocalRow := Row - FMdi.Active.Area.Top;
  if FMdi.Active is TDualPanelWindow then
    Result := TDualPanelWindow(FMdi.Active).HandleMouseMove(LocalCol, LocalRow)
  else if FMdi.Active is TEditorWindow then
    Result := TEditorWindow(FMdi.Active).HandleMouseMove(LocalCol, LocalRow)
  else if FMdi.Active is TConsoleWindow then
    Result := TConsoleWindow(FMdi.Active).HandleMouseMove(LocalCol, LocalRow);
end;

procedure TMainForm.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  Col, Row: Integer;
begin
  if not Assigned(FMdi) then
    Exit;

  if TryHandleDualPanelDragMove(Shift, X, Y) then
    Exit;

  if not (ssLeft in Shift) then
    Exit;
  if not PointToCell(X, Y, Col, Row) then
    Exit;
  if TryDispatchActiveMdiMouseMove(Col, Row) then
    Recompose;
end;

procedure TMainForm.StartOleFileDrag(const APaths: TArray<string>);
var
  Effect: LongInt;
begin
  if Length(APaths) = 0 then
    Exit;
  // Release mouse capture so OLE owns the drag.
  ReleaseCapture;
  Effect := OleDragLocalFiles(APaths);
  if Assigned(FDualPanel) then
    FDualPanel.FinishOleFileDrag(Effect);
  Recompose;
end;

function TMainForm.ResolveDropAtScreenPoint(const APoint: TPointF;
  out ADestURI: string; out AMove: Boolean): Boolean;
var
  ClientPt: TPointF;
  Col, Row, LocalCol, LocalRow: Integer;
  Side: TPanelSide;
  HighlightRow: Integer;
begin
  Result := False;
  ADestURI := '';
  // Ctrl = Copy, Shift = Move; default Copy (safe for cross-app drops).
  AMove := (GetAsyncKeyState(VK_SHIFT) < 0) and (GetAsyncKeyState(VK_CONTROL) >= 0);
  if not Assigned(FDualPanel) or not FDualPanel.Visible then
    Exit;
  ClientPt := ScreenToClient(APoint);
  if not PointToCell(ClientPt.X, ClientPt.Y, Col, Row) then
    Exit;
  if not FDualPanel.HitTest(Col, Row) then
    Exit;
  LocalCol := Col - FDualPanel.Area.Left;
  LocalRow := Row - FDualPanel.Area.Top;
  if not FDualPanel.HitTestDropTarget(LocalCol, LocalRow, ADestURI, Side, HighlightRow) then
    Exit;
  FDualPanel.SetDropHighlight(True, Side, ADestURI, HighlightRow);
  Result := True;
end;

procedure TMainForm.DragOver(const Data: TDragObject; const Point: TPointF;
  var Operation: TDragOperation);
var
  DestURI: string;
  MoveOp: Boolean;
begin
  inherited;
  if Length(Data.Files) = 0 then
  begin
    if Assigned(FDualPanel) then
      FDualPanel.SetDropHighlight(False);
    Exit;
  end;
  if ResolveDropAtScreenPoint(Point, DestURI, MoveOp) then
  begin
    if MoveOp then
      Operation := TDragOperation.Move
    else
      Operation := TDragOperation.Copy;
  end
  else
  begin
    Operation := TDragOperation.None;
    if Assigned(FDualPanel) then
      FDualPanel.SetDropHighlight(False);
  end;
end;

procedure TMainForm.DragDrop(const Data: TDragObject; const Point: TPointF);
var
  DestURI: string;
  MoveOp: Boolean;
begin
  if Length(Data.Files) = 0 then
  begin
    inherited;
    Exit;
  end;
  if ResolveDropAtScreenPoint(Point, DestURI, MoveOp) and Assigned(FDualPanel) then
  begin
    FDualPanel.SetDropHighlight(False);
    FDualPanel.AcceptDroppedFiles(Data.Files, DestURI, MoveOp);
    Recompose;
    Exit;
  end;
  if Assigned(FDualPanel) then
    FDualPanel.SetDropHighlight(False);
  inherited;
end;

procedure TMainForm.DragLeave;
begin
  if Assigned(FDualPanel) then
    FDualPanel.SetDropHighlight(False);
  inherited;
end;

procedure TMainForm.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbRight then
  begin
    CancelContextMenuHold;
    Exit;
  end;
  if Button <> TMouseButton.mbLeft then
    Exit;
  if Assigned(FDualPanel) and FDualPanel.Visible then
  begin
    if FDualPanel.HandleMouseUp then
      Recompose;
  end
  else if not Assigned(FMdi) then
    Exit
  else if FMdi.Active is TEditorWindow then
  begin
    if TEditorWindow(FMdi.Active).HandleMouseUp then
      Recompose;
  end
  else if FMdi.Active is TConsoleWindow then
  begin
    if TConsoleWindow(FMdi.Active).HandleMouseUp then
      Recompose;
  end;
end;

function TMainForm.ConsumeTerminalKey(var Key: Word; var KeyChar: Char): Boolean;
begin
  Key := 0;
  KeyChar := #0;
  Recompose;
  Result := True;
end;

function TMainForm.IsBareEscape(Key: Word; Shift: TShiftState): Boolean;
begin
  Result := (Key = vkEscape) and not (ssCtrl in Shift) and not (ssAlt in Shift) and
    not (ssShift in Shift);
end;

function TMainForm.IsConsoleNavigationKey(Key: Word): Boolean;
begin
  Result := (Key = vkPrior) or (Key = vkNext) or (Key = vkHome) or (Key = vkEnd) or
    (Key = vkUp) or (Key = vkDown) or (Key = vkLeft) or (Key = vkRight);
end;

function TMainForm.IsConsoleCopySelectAllKey(Key: Word; KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  // Virtual key codes for letters are always the uppercase ASCII value, so
  // only KeyChar (which does carry case) needs both-case comparison.
  Result := (ssCtrl in Shift) and not (ssAlt in Shift) and
    ((Key = Ord('C')) or (Key = Ord('A')) or (UpCase(KeyChar) = 'C') or (UpCase(KeyChar) = 'A'));
end;

function TMainForm.IsConsoleScrollOrSelectionKey(Key: Word; KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := IsConsoleNavigationKey(Key) or IsConsoleCopySelectAllKey(Key, KeyChar, Shift);
end;

function TMainForm.IsConsoleActiveInConsoleMode: Boolean;
begin
  Result := Assigned(FDualPanel) and FDualPanel.ConsoleMode and Assigned(FMdi) and
    Assigned(FMdi.Active) and (FMdi.Active = FConsole);
end;

// AltGr = Right Alt + the synthetic Left Ctrl Windows adds for it, with no
// Left Alt or Right Ctrl actually held.
function TMainForm.IsAltGrDown: Boolean;
begin
  Result := (GetKeyState(VK_RMENU) < 0) and (GetKeyState(VK_LCONTROL) < 0) and
    (GetKeyState(VK_LMENU) >= 0) and (GetKeyState(VK_RCONTROL) >= 0);
end;

function TMainForm.IsModifierOnlyKey(AKey: Word): Boolean;
begin
  Result := (AKey = vkMenu) or (AKey = vkControl) or (AKey = vkShift) or
    (AKey = vkLShift) or (AKey = vkRShift) or (AKey = vkLControl) or (AKey = vkRControl) or
    (AKey = vkLMenu) or (AKey = vkRMenu);
end;

function TMainForm.IsReloadKeymapShortcut(AKey: Word; AKeyChar: Char;
  AShift: TShiftState): Boolean;
begin
  Result := (ssCtrl in AShift) and (ssAlt in AShift) and not (ssShift in AShift) and
    ((AKey = Ord('K')) or (AKey = Ord('k')) or (AKeyChar = 'k') or (AKeyChar = 'K'));
end;

// Host form dialogs (MkDir/Copy/…) live on Dual Panel — must win over the
// active MDI window (Console/Editor) so Enter reaches the default button.
function TMainForm.TryDispatchDualPanelDialogKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.DialogVisible and
    FDualPanel.HandleInput(Key, Shift, KeyChar);
end;

// Esc in ConsoleMode always restores panels (never stops the running command
// — Ctrl+C does that). Routed through FConsole.HandleInput first so an
// active scrollback selection is cleared before dismissing, same as
// click-away. Routed here because DualPanel.HandleInput exits early while
// ConsoleMode is on, so focus on F-keys / status would otherwise swallow Esc.
function TMainForm.TryDispatchBareEscapeKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := IsBareEscape(Key, Shift) and Assigned(FDualPanel) and FDualPanel.ConsoleMode and
    Assigned(FConsole);
  if Result then
    FConsole.HandleInput(Key, Shift, KeyChar);
end;

// Console scroll / selection while ConsoleMode (cmdline is hidden; input is in Console).
function TMainForm.TryDispatchConsoleScrollKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := IsConsoleActiveInConsoleMode and IsConsoleScrollOrSelectionKey(Key, KeyChar, Shift) and
    FMdi.Active.HandleInput(Key, Shift, KeyChar);
end;

// Panel cmdline owns typing when focused (panel mode only).
function TMainForm.TryDispatchPanelCmdlineKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.CmdFocused and
    not FDualPanel.ConsoleMode and FDualPanel.HandleInput(Key, Shift, KeyChar);
end;

function TMainForm.TryDispatchMdiActiveKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := Assigned(FMdi) and Assigned(FMdi.Active) and
    FMdi.Active.HandleInput(Key, Shift, KeyChar);
end;

function TMainForm.TryDispatchDualPanelGeneralKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := Assigned(FDualPanel) and FDualPanel.Visible and
    FDualPanel.HandleInput(Key, Shift, KeyChar);
end;

function TMainForm.DispatchTerminalKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := False;
  SyncKeyModifiers(Shift);
  // FMX sometimes delivers Tab/Enter only as KeyChar with Key=0.
  if (Key = 0) and (KeyChar = #9) then
    Key := vkTab;
  if Key <> vkTab then
  begin
    if (KeyChar = #13) or (KeyChar = #10) then
      Key := vkReturn;
    if (Key = 10) or (Key = 13) then
      Key := vkReturn;
  end;

  if TryDispatchDualPanelDialogKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));

  if TryDispatchBareEscapeKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));

  if TryDispatchConsoleScrollKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));

  if TryDispatchPanelCmdlineKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));

  if TryDispatchMdiActiveKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));

  if TryDispatchDualPanelGeneralKey(Key, KeyChar, Shift) then
    Exit(ConsumeTerminalKey(Key, KeyChar));
end;

procedure TMainForm.SyncKeyModifiers(Shift: TShiftState);
var
  Changed: Boolean;
begin
  Changed := False;
  // Dual Panel owns shared chrome in ConsoleMode and when panels are active.
  if Assigned(FDualPanel) and FDualPanel.Visible then
    Changed := FDualPanel.SetKeyModifiers(Shift) or Changed;
  // Focused Viewer/Editor draw their own F-bar / status.
  if Assigned(FMdi) and Assigned(FMdi.Active) and (FMdi.Active <> FDualPanel) then
    Changed := FMdi.Active.SetKeyModifiers(Shift) or Changed;
  if Changed then
    Recompose;
end;

procedure TMainForm.KeyDown(var Key: Word; var KeyChar: System.WideChar;
  Shift: TShiftState);
var
  K: Word;
  C: Char;
begin
  SyncKeyModifiers(Shift);
  K := Key;
  C := Char(KeyChar);
  // Modifier-only press: update F-bar and swallow so the menu does not steal Alt.
  if IsModifierOnlyKey(K) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  // Normalize Enter before dispatch (WideChar #13 / raw 13 / vkAccept).
  if (C = #13) or (C = #10) then
  begin
    if K <> vkTab then
      K := vkReturn;
  end;
  if (K <> vkTab) and ((K = 10) or (K = 13) or (K = vkAccept)) then
    K := vkReturn;
  // Right Alt on AltGr layouts arrives as Ctrl+Alt (Windows adds a synthetic
  // Left Ctrl). For Enter the user means Alt+Enter (Properties), not
  // Ctrl+Alt+Enter (reveal on the other panel) -- only a real Ctrl keeps it.
  if (K = vkReturn) and IsAltGrDown then
    Exclude(Shift, ssCtrl);
  if TryHandleZoom(K, C, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if DispatchTerminalKey(K, C, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit; // do not call inherited — prevents FMX Tab focus cycling
  end;
  inherited KeyDown(Key, KeyChar, Shift);
end;

procedure TMainForm.KeyUp(var Key: Word; var KeyChar: System.WideChar;
  Shift: TShiftState);
begin
  SyncKeyModifiers(Shift);
  if IsModifierOnlyKey(Key) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited KeyUp(Key, KeyChar, Shift);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
  Shift: TShiftState);
begin
  // Zoom shortcuts only; Tab/panels handled in KeyDown override (before FMX).
  SyncKeyModifiers(Shift);

  // Ctrl+Alt+K — reload keymap.json from config dir.
  // Checked BEFORE DispatchTerminalKey: the Dual Panel cmdline and panels
  // absorb printable letters (including 'K') as input, which would otherwise
  // swallow the hot-reload shortcut whenever the panel/cmdline had focus.
  if IsReloadKeymapShortcut(Key, KeyChar, Shift) then
  begin
    if ReloadKeymap('') then
      ShowMessage('Keymap reloaded: ' + ActiveKeymap.Name + ' (overrides from user file)' +
        sLineBreak + GetDefaultKeymapPath)
    else
      ShowMessage('No user keymap.json — using embedded default: ' + ActiveKeymap.Name +
        sLineBreak + GetDefaultKeymapPath);
    Key := 0;
    KeyChar := #0;
    Recompose;
    Exit;
  end;

  if TryHandleZoom(Key, KeyChar, Shift) then
    Exit;

  if DispatchTerminalKey(Key, KeyChar, Shift) then
    Exit;
end;

end.
