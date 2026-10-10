unit uMainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.UIConsts, System.Math, System.Generics.Collections, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Menus,
  Winapi.Windows, Winapi.Messages, Winapi.ActiveX, Winapi.MultiMon,
  uTerminalTypes, uThemeTypes, uTerminalWindow, uDualPanelTypes, uDualPanelWindow,
  uEditorWindow, uConsoleWindow, uMdiCompositor, uThemeRegistry, uThemeSpec, uThemeProxy,
  uTerminalRenderer, uSession, uWinFileDragDrop, uKeymap, uShellProfiles, uShellAssoc,
  uBaseConsoleWindow, uPluginHost, uVfsTypes, uColorCoding, uPanelColumns,
  uDisplaySettings, uConsoleSettings, uEditorSearch, uSettingsTransfer, uElevation, uStrings, uUpdateController, uToast, uFrameStats, uThemeDrawing, uChromeRows, uDualPanelDrag,
  uDialogHost, uConsoleLaunch, uWindowChrome, uNotice, uHiddenDialogs, uPluginUi, uPluginChrome,
  uPluginSurface, uPluginServices;

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
    /// <summary>Same object as FTheme, typed for SetInner - see uThemeProxy.
    /// Every window/dialog/controller holds this one shared IThemeRenderer
    /// reference, so switching FThemeProxy's inner theme repaints all of
    /// them without recreating anything.</summary>
    FThemeProxy: TThemeProxy;
    /// <summary>uThemeRegistry id of the active theme (session.json's
    /// 'theme'); kept in sync with FThemeProxy by SwitchTheme.</summary>
    FThemeName: string;
    /// <summary>Id of the session's theme that could not be loaded at start
    /// ('' = it loaded); reported once the window exists.</summary>
    FMissingThemeId: string;
    FMdi: TMdiCompositor;
    FDualPanel: TDualPanelWindow;
    FConsole: TConsoleWindow;
    FSession: TMtnSession;  // last loaded/saved session (includes BackgroundConsoleProfile)
    FLastScale: Single;
    // Surface that holds the mouse while a button is down on it (0 = none).
    FSurfaceMouseHandle: Integer;
    FTrackingMouseLeave: Boolean;
    /// <summary>Set by a window command or a size change: no button is lit
    /// until the mouse moves, even if the cursor rests over one.</summary>
    FHoverSuppressed: Boolean;
    FPaintCount: Integer;
    /// <summary>A window command waits for the released button to be painted.</summary>
    FChromeCommandPending: Boolean;
    FGridSnapDone: Boolean;
    FWasMaximized: Boolean;
    FNormalLeft: Single;
    FNormalTop: Single;
    FNormalWidth: Single;
    FNormalHeight: Single;
    FRestoringBounds: Boolean;
    FBlinkTimer: TTimer;
    FBlinkPhase: Boolean;   // True = cursor visible
    FCursorBlinkEnabled: Boolean;
    FContextMenuTimer: TTimer;
    /// <summary>One-shot, cDialogButtonPressMs: releases a dialog button
    /// pressed from the keyboard (uDialogHost.GDialogButtonPressStart).</summary>
    FButtonPressTimer: TTimer;
    /// <summary>Polls a dialog button held by Enter or Space: lifts it (running
    /// its command) once GetKeyState shows the key up, whatever KeyUp delivered.</summary>
    FButtonHoldTimer: TTimer;
    /// <summary>Self-update (Help > Updates, quiet check shortly after start).</summary>
    FUpdater: TUpdateController;
    FUpdateTimer: TTimer;
    /// <summary>One-shot: warns shortly after start when 7z.dll is missing.</summary>
    FSevenZipTimer: TTimer;
    /// <summary>Alt went down on its own and nothing else happened since: releasing it
    /// opens the menu. The form gets no key-up for Alt, so FAltTimer watches the key.</summary>
    FAltArmed: Boolean;
    FAltTimer: TTimer;
    /// <summary>Runs out when a command started in the background has been
    /// shown long enough; a key before that keeps the console.</summary>
    FPeekTimer: TTimer;
    FAppVersion: string;
    /// <summary>--fps only (nil otherwise): once a second moves FFpsStats
    /// into FFpsText, which UpdateCaption appends to the caption.</summary>
    FFpsTimer: TTimer;
    FFpsStats: TFrameStats;
    FFpsText: string;
    FContextHoldPath: string;
    FContextHoldScreenX: Integer;
    FContextHoldScreenY: Integer;
    FContextHoldShown: Boolean;
    FPrevWndProc: Pointer;
    FSystemShutdown: Boolean;
    /// <summary>Settings were imported: PersistSession keeps the imported files.</summary>
    FSettingsImported: Boolean;
    procedure PrepareForSystemShutdown;
    procedure ReleaseTaskbarButton;
    procedure BlinkTick(Sender: TObject);
    procedure ButtonPressTick(Sender: TObject);
    procedure ButtonHoldTick(Sender: TObject);
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
    /// <summary>Applies the "Show window title bar" setting: with the native
    /// title bar hidden the client area covers the whole window and the
    /// character grid draws its own window buttons and drag zones.</summary>
    procedure ApplyTitleBar(AVisible: Boolean);
    procedure RefreshNativeFrame;
    procedure HandleWindowCommand(AButton: TWindowButton);
    /// <summary>WM_NCHITTEST answer while the native title bar is hidden: the
    /// window edges resize, the free part of the menu / tab bar rows drags.</summary>
    function NcHitTest(AHwnd: HWND; ALParam: LPARAM): LRESULT;
    /// <summary>Right click on the caption zone of the window without its
    /// native title bar: the top menu instead of the system menu.</summary>
    function HandleCaptionRightClick(AHwnd: HWND; ALParam: LPARAM): Boolean;
    procedure ClearChromeHover;
    function SyncChromeHover: Boolean;
    /// <summary>Paints the pending frame at once instead of on the next idle
    /// pass, so a change shows before what follows it (a window command).</summary>
    procedure PaintNow;
    /// <summary>Runs AProc once the form has painted a frame after this call
    /// (or after a short wait), so what was just composed is on screen first.</summary>
    procedure RunAfterPaint(const AProc: TProc);
    /// <summary>After the window is restored or maximized: the frame is
    /// composed again, since FMX may not repaint a window whose size did
    /// not change.</summary>
    procedure RedrawAfterSizeChange;
    /// <summary>Cell size in device pixels (fractional).</summary>
    function CellPixels(out ACellW, ACellH: Double): Boolean;
    /// <summary>WM_SIZING: the window is resized in whole character cells.</summary>
    function HandleSizing(AHwnd: HWND; AEdge: WPARAM; ARect: PRect): Boolean;
    /// <summary>Trims the window to a whole number of cells (not maximized).</summary>
    procedure SnapWindowToGrid;
    procedure SyncRenderer;
    procedure ApplyZoomDelta(ADelta: Single);
    function TryHandleFullscreen(var AKey: Word; var AKeyChar: Char;
      AShift: TShiftState): Boolean;
    function TryHandleZoom(var AKey: Word; var AKeyChar: Char;
      AShift: TShiftState): Boolean;
    procedure ComposeScene(const AGrid: TTerminalGrid; ACols, ARows: Integer);
    /// <summary>FormPaint's body; split out so --fps can time it whole.</summary>
    procedure PaintFrame(Canvas: TCanvas);
    procedure PaintSurfaceFullscreenFrame(Canvas: TCanvas);
    function PointToCell(X, Y: Single; out ACol, ARow: Integer): Boolean;
    procedure Recompose;
    procedure EnsureDemoWindows;
    procedure CaptureNormalBounds;
    procedure ApplySessionWindow(const AWindow: TMtnWindowBounds);
    /// <summary>Loads the session's theme (uThemeRegistry id) at startup.
    /// A missing theme falls back to the default one and is remembered in
    /// FMissingThemeId; the coloring and Markdown color files of earlier
    /// versions are imported as a user theme first.</summary>
    procedure LoadStartupTheme(const AThemeId, ALegacyThemeFile: string);
    /// <summary>Points FThemeProxy at ASpec and hands its file coloring to
    /// the panels.</summary>
    procedure ApplyThemeSpec(const ASpec: TThemeSpec);
    /// <summary>Live theme switch: repoints FThemeProxy at the theme
    /// AThemeId - every open window/dialog picks it up on its next repaint,
    /// no recreation needed - and remembers it for PersistSession. An
    /// unknown id selects the default theme.</summary>
    procedure SwitchTheme(const AThemeId: string);
    /// <summary>FDualPanel.OnThemeSelect handler: the Theme dialog (Options
    /// menu) reports the id the user picked.</summary>
    procedure ThemeSelected(const AThemeId: string);
    /// <summary>FDualPanel.OnThemePreview handler: shows ASpec without
    /// changing the selected theme.</summary>
    procedure ThemePreview(const ASpec: TThemeSpec);
    /// <summary>FDualPanel.OnGetActiveThemeId: lets the Theme dialog
    /// preselect the currently active theme without owning that state itself.</summary>
    function GetActiveThemeId: string;
    function GetConsoleProfile: string;
    function GetConsoleStartOnLaunch: Boolean;
    procedure SetConsoleStartOnLaunch(AValue: Boolean);
    function GetConsoleCwdToPanels: Boolean;
    procedure SetConsoleCwdToPanels(AValue: Boolean);
    function GetDisplaySettings: TDisplaySettings;
    procedure ApplyDisplaySettings(const ASettings: TDisplaySettings);
    /// <summary>Theme to instantiate (session.json's 'theme') and the
    /// legacy coloring file (session.json's 'themeFile') for this run.
    /// Peeks session.json without applying the rest of the session (that
    /// still happens later, in TryRestoreSession, once FDualPanel/FRenderer
    /// exist).</summary>
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
    procedure DualPanelShellContextMenu(const APaths: TArray<string>;
      ALocalCol, ALocalRow: Integer);
    function TryDualPanelOverlayWheel(AWheelDelta: Integer): Boolean;
    procedure DualPanelQuitRequest(Sender: TObject);
    procedure DualPanelOpenUpdates(Sender: TObject);
    procedure UpdateTimerTick(Sender: TObject);
    procedure SevenZipTimerTick(Sender: TObject);
    procedure AltTimerTick(Sender: TObject);
    procedure FpsTimerTick(Sender: TObject);
    procedure CreateUpdater;
    function PluginServicesOfPanels: TPluginHostServices;
    /// <summary>Hands a mouse event on a plugin surface to the plugin (positions in device
    /// pixels of its area); True when the plugin used it.</summary>
    function TrySurfaceMouse(AKind: Integer; X, Y: Single; AButton: TMouseButton;
      AExtra: Integer; Shift: TShiftState): Boolean;
    /// <summary>Keeps the native windows of plugin surfaces over their areas.</summary>
    procedure SyncNativeSurfaces;
    procedure QueueSurfaceSize(AHandle, AWidth, AHeight: Integer);
    /// <summary>The area of a plugin surface in canvas units: its cells, or the whole
    /// client area while the picture is full screen.</summary>
    function SurfaceCanvasRect(AHandle: Integer; const ABounds: TRectI): TRectF;
    procedure DualPanelRunCommand(const ACommand, AWorkingDir: string);
    procedure DualPanelReturnWhenDone(Sender: TObject);
    procedure DualPanelRunInBackground(Sender: TObject);
    procedure PeekTimerTick(Sender: TObject);
    procedure DualPanelShellCwdSync(const APath: string);
    function DualPanelSaveConsoleOutput(const APath: string; out AError: string): Boolean;
    procedure DualPanelClearConsoleBuffer(Sender: TObject);
    procedure DualPanelHelperActiveChanged(Sender: TObject);
    function DualPanelExportSettings(const APath: string; out AError: string): Boolean;
    function DualPanelImportSettings(const APath: string; out AError: string): Boolean;
    procedure DualPanelToggleConsole(Sender: TObject);
    procedure DualPanelOpenTerminal(const AProfileId, ACwd: string);
    procedure DualPanelOpenTerminalWith(const AProfileId, ACwd, ACommand: string);
    function EnsureConsole: TConsoleWindow;
    /// <summary>A hidden console is not laid out with the visible windows; it
    /// takes the size it will have once shown, so a shell started in the
    /// background begins at the right size and is not resized on first show.</summary>
    procedure SyncHiddenConsoleArea(ACols, ARows: Integer);
    function DualPanelLaunchConsoleFile(const APath: string): Boolean;
    procedure ShowConsoleMode;
    procedure ShowPanelMode;
    procedure ApplyConsoleLayout;
    /// <summary>Shows or hides the menu bar, the F-key bar and the status
    /// line (uChromeRows) and resizes the console to match.</summary>
    procedure ApplyChromeRows(AMenuBar, AKeyBar, AStatusLine: Boolean);
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
    /// <summary>A click on the function bar while the console covers the panels
    /// acts as the key it shows (Esc:Panels), through the keyboard path. The
    /// bar belongs to Dual Panel, which ignores keys in console mode, so the
    /// click would hide the console and leave the panels unpainted.</summary>
    function TryDispatchConsoleFunctionBarClick(Col, Row: Integer;
      Shift: TShiftState): Boolean;
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
    /// <summary>Decodes the path from a WM_COPYDATA sent by a
    /// delegating second instance, restores/activates this window, and opens
    /// the path (empty path = activate only, no new tab).</summary>
    procedure HandleActivateRequest(ACds: PCopyDataStruct);
    /// <summary>Shared by the startup CLI-arg path (FormCreate,
    /// after TryRestoreSession) and HandleActivateRequest - opens APath in a
    /// new tab on the active side. No-op for '' or a path that doesn't
    /// exist.</summary>
    procedure OpenPathFromArgument(const APath: string);
  protected
    procedure CreateHandle; override;
    procedure DestroyHandle; override;
    procedure DetachSurfaceWindows;
    procedure AttachSurfaceWindows;
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
  System.Diagnostics,
  FMX.Platform.Win, uOverlayRenderer, uNativeSurface, uSingleInstance, uUpdater, uDialogTypes,
  uKeyChord, uFileRecycleBin;

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

/// <summary>Shift / Ctrl / Alt as they are down now.</summary>
function KeyboardShiftState: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
    Include(Result, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then
    Include(Result, ssCtrl);
  if GetKeyState(VK_MENU) < 0 then
    Include(Result, ssAlt);
end;

type
  TGetDpiForWindowFn = function(AHwnd: HWND): UINT; stdcall;
  TGetSystemMetricsForDpiFn = function(AIndex: Integer; ADpi: UINT): Integer; stdcall;

const
  cSmPaddedBorder = 92;
  /// <summary>Width of the resize band along the window edges while the native
  /// title bar (and with it the frame) is hidden, in 96 dpi pixels.</summary>
  cResizeBorder = 5;

/// <summary>Thickness of the sizing frame Windows gives a maximized window on
/// its monitor, horizontally or vertically.</summary>
function WindowFrameSize(AHwnd: HWND; AHorizontal: Boolean): Integer;
var
  User32: HMODULE;
  GetDpi: TGetDpiForWindowFn;
  GetMetric: TGetSystemMetricsForDpiFn;
  Frame: Integer;
  Dpi: UINT;
begin
  if AHorizontal then
    Frame := SM_CXFRAME
  else
    Frame := SM_CYFRAME;
  User32 := GetModuleHandle('user32.dll');
  @GetDpi := GetProcAddress(User32, 'GetDpiForWindow');
  @GetMetric := GetProcAddress(User32, 'GetSystemMetricsForDpi');
  if Assigned(GetDpi) and Assigned(GetMetric) then
  begin
    Dpi := GetDpi(AHwnd);
    Result := GetMetric(Frame, Dpi) + GetMetric(cSmPaddedBorder, Dpi);
  end
  else
    Result := GetSystemMetrics(Frame) + GetSystemMetrics(cSmPaddedBorder);
end;

procedure InsetMaximizedRect(AHwnd: HWND; var ARect: TRect);
begin
  InflateRect(ARect, -WindowFrameSize(AHwnd, True), -WindowFrameSize(AHwnd, False));
end;

procedure TrackLeave(AHwnd: HWND);
var
  Track: TTrackMouseEvent;
begin
  Track.cbSize := SizeOf(Track);
  Track.dwFlags := TME_LEAVE;
  Track.hwndTrack := AHwnd;
  Track.dwHoverTime := 0;
  TrackMouseEvent(Track);
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
      WM_SYSKEYUP:
        // FMX never calls KeyUp for a released Alt: with no main menu it
        // enters its menu loop instead, and the F-bar would stay on the Alt
        // actions. The form has no menu to open, so the release only
        // updates the modifiers. Not chained.
        if AWParam = VK_MENU then
        begin
          MainForm.SyncKeyModifiers(KeyboardShiftState);
          Result := 0;
          Exit;
        end;
      WM_ACTIVATE:
        // A modifier released in another window never reaches this one:
        // take the keyboard state as it is on activation and deactivation.
        begin
          if MainForm.FPrevWndProc <> nil then
            Result := CallWindowProc(MainForm.FPrevWndProc, AHwnd, AMsg, AWParam, ALParam)
          else
            Result := DefWindowProc(AHwnd, AMsg, AWParam, ALParam);
          if LOWORD(AWParam) = WA_INACTIVE then
          begin
            MainForm.SyncKeyModifiers([]);
            MainForm.ClearChromeHover;
          end
          else
            MainForm.SyncKeyModifiers(KeyboardShiftState);
          Exit;
        end;
      WM_SIZE:
        begin
          if MainForm.FPrevWndProc <> nil then
            Result := CallWindowProc(MainForm.FPrevWndProc, AHwnd, AMsg, AWParam, ALParam)
          else
            Result := DefWindowProc(AHwnd, AMsg, AWParam, ALParam);
          if (AWParam = SIZE_RESTORED) or (AWParam = SIZE_MAXIMIZED) then
            MainForm.RedrawAfterSizeChange;
          Exit;
        end;
      WM_NCCALCSIZE:
        // Without the native title bar the client area is the whole window;
        // maximized, it stops short of the overhang Windows gives the frame.
        if (not GShowTitleBar) and (AWParam <> 0) then
        begin
          if IsZoomed(AHwnd) then
            InsetMaximizedRect(AHwnd, PNCCalcSizeParams(ALParam)^.rgrc[0]);
          Result := 0;
          Exit;
        end;
      WM_NCHITTEST:
        if not GShowTitleBar then
        begin
          Result := MainForm.NcHitTest(AHwnd, ALParam);
          Exit;
        end;
      WM_NCRBUTTONUP:
        if (not GShowTitleBar) and (AWParam = HTCAPTION) and
           MainForm.HandleCaptionRightClick(AHwnd, ALParam) then
        begin
          Result := 0;
          Exit;
        end;
      WM_SIZING:
        if MainForm.HandleSizing(AHwnd, AWParam, PRect(ALParam)) then
        begin
          Result := 1;
          Exit;
        end;
      WM_MOUSEMOVE:
        if not MainForm.FTrackingMouseLeave then
        begin
          MainForm.FTrackingMouseLeave := True;
          TrackLeave(AHwnd);
        end;
      WM_MOUSELEAVE:
        begin
          MainForm.FTrackingMouseLeave := False;
          MainForm.ClearChromeHover;
        end;
      WM_MOUSEACTIVATE:
        // Without the native title bar a click on the caption zone or a window
        // edge is a normal one, so the window can be dragged or resized while
        // inactive; only client clicks are eaten.
        if GShowTitleBar or (LOWORD(ALParam) = HTCLIENT) then
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
  // but their WndProc leaves Result=0, which Windows treats as a veto -
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
  // A handle made while the title bar is hidden starts with the default frame.
  if not GShowTitleBar then
    RefreshNativeFrame;
end;

procedure TMainForm.RefreshNativeFrame;
var
  H: NativeUInt;
begin
  H := NativeWindowHandle;
  if H <> 0 then
    SetWindowPos(HWND(H), 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
      SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;

procedure TMainForm.ApplyTitleBar(AVisible: Boolean);
begin
  if GShowTitleBar = AVisible then
    Exit;
  GShowTitleBar := AVisible;
  RefreshNativeFrame;
  if Assigned(FMdi) and Assigned(FRenderer) then
    Recompose;
end;

function TMainForm.CellPixels(out ACellW, ACellH: Double): Boolean;
var
  Scale: Single;
begin
  ACellW := 0;
  ACellH := 0;
  Result := Assigned(FRenderer) and (FRenderer.CellWidth > 0) and
    (FRenderer.CellHeight > 0);
  if not Result then
    Exit;
  Scale := 1;
  if FLastScale > 0 then
    Scale := FLastScale;
  ACellW := FRenderer.CellWidth * Scale;
  ACellH := FRenderer.CellHeight * Scale;
end;

function TMainForm.HandleSizing(AHwnd: HWND; AEdge: WPARAM; ARect: PRect): Boolean;
var
  Win, Client: TRect;
  CellW, CellH: Double;
begin
  Result := False;
  if (ARect = nil) or IsZoomed(AHwnd) or not CellPixels(CellW, CellH) then
    Exit;
  if not (GetWindowRect(AHwnd, Win) and GetClientRect(AHwnd, Client)) then
    Exit;
  SnapSizingRect(Integer(AEdge), ARect^,
    (Win.Right - Win.Left) - Client.Right, (Win.Bottom - Win.Top) - Client.Bottom,
    CellW, CellH);
  Result := True;
end;

procedure TMainForm.SnapWindowToGrid;
var
  H: NativeUInt;
  Win, Client: TRect;
  CellW, CellH: Double;
  NcW, NcH, NewW, NewH: Integer;
begin
  H := NativeWindowHandle;
  if (H = 0) or IsZoomed(HWND(H)) or IsIconic(HWND(H)) or not CellPixels(CellW, CellH) then
    Exit;
  if not (GetWindowRect(HWND(H), Win) and GetClientRect(HWND(H), Client)) then
    Exit;
  NcW := (Win.Right - Win.Left) - Client.Right;
  NcH := (Win.Bottom - Win.Top) - Client.Bottom;
  NewW := GridClientExtent(Client.Right, CellW, cMinGridCols, False) + NcW;
  NewH := GridClientExtent(Client.Bottom, CellH, cMinGridRows, False) + NcH;
  if (NewW <> Win.Right - Win.Left) or (NewH <> Win.Bottom - Win.Top) then
    SetWindowPos(HWND(H), 0, 0, 0, NewW, NewH, SWP_NOMOVE or SWP_NOZORDER or
      SWP_NOACTIVATE);
end;

procedure TMainForm.HandleWindowCommand(AButton: TWindowButton);
begin
  case AButton of
    wbMinimize:
      WindowState := System.UITypes.TWindowState.wsMinimized;
    wbMaximize:
      if WindowState = System.UITypes.TWindowState.wsMaximized then
        WindowState := System.UITypes.TWindowState.wsNormal
      else
        WindowState := System.UITypes.TWindowState.wsMaximized;
    wbClose:
      Close;
  end;
  // The window changed under a resting mouse: no button is lit until it moves.
  FHoverSuppressed := True;
  ClearChromeHover;
end;

function TMainForm.NcHitTest(AHwnd: HWND; ALParam: LPARAM): LRESULT;
var
  R: TRect;
  Pt: TPoint;
  B, Col, Row: Integer;
  Scale: Single;
  OnLeft, OnRight, OnTop, OnBottom: Boolean;
begin
  Pt := Point(SmallInt(LOWORD(ALParam)), SmallInt(HIWORD(ALParam)));
  Scale := 1;
  if FLastScale > 1 then
    Scale := FLastScale;
  if (not IsZoomed(AHwnd)) and GetWindowRect(AHwnd, R) then
  begin
    B := Round(cResizeBorder * Scale);
    OnLeft := Pt.X < R.Left + B;
    OnRight := Pt.X >= R.Right - B;
    OnTop := Pt.Y < R.Top + B;
    OnBottom := Pt.Y >= R.Bottom - B;
    if OnTop and OnLeft then
      Exit(HTTOPLEFT);
    if OnTop and OnRight then
      Exit(HTTOPRIGHT);
    if OnBottom and OnLeft then
      Exit(HTBOTTOMLEFT);
    if OnBottom and OnRight then
      Exit(HTBOTTOMRIGHT);
    if OnLeft then
      Exit(HTLEFT);
    if OnRight then
      Exit(HTRIGHT);
    if OnTop then
      Exit(HTTOP);
    if OnBottom then
      Exit(HTBOTTOM);
  end;
  Result := HTCLIENT;
  if not (Assigned(FDualPanel) and FDualPanel.Visible) then
    Exit;
  Winapi.Windows.ScreenToClient(AHwnd, Pt);
  if PointToCell(Pt.X / Scale, Pt.Y / Scale, Col, Row) and
     FDualPanel.IsWindowDragZone(Col - FDualPanel.Area.Left, Row - FDualPanel.Area.Top) then
    Result := HTCAPTION;
end;

function TMainForm.SyncChromeHover: Boolean;
var
  Pt: TPoint;
  H: HWND;
  Col, Row: Integer;
  Scale: Single;
begin
  Result := False;
  if not Assigned(FDualPanel) then
    Exit;
  // The highlight follows where the cursor is, not the last mouse event:
  // a window minimized, restored or resized under the mouse sends none.
  Col := -1;
  Row := -1;
  H := HWND(NativeWindowHandle);
  if (not FHoverSuppressed) and (H <> 0) and (not IsIconic(H)) and GetCursorPos(Pt) and
     (WindowFromPoint(Pt) = H) then
  begin
    Winapi.Windows.ScreenToClient(H, Pt);
    Scale := 1;
    if FLastScale > 1 then
      Scale := FLastScale;
    if PointToCell(Pt.X / Scale, Pt.Y / Scale, Col, Row) then
    begin
      Dec(Col, FDualPanel.Area.Left);
      Dec(Row, FDualPanel.Area.Top);
    end
    else
    begin
      Col := -1;
      Row := -1;
    end;
  end;
  Result := FDualPanel.UpdateChromeHover(Col, Row);
end;

procedure TMainForm.PaintNow;
var
  H: NativeUInt;
begin
  Invalidate;
  H := NativeWindowHandle;
  if H <> 0 then
    UpdateWindow(HWND(H));
end;

procedure TMainForm.RunAfterPaint(const AProc: TProc);
const
  cPollMs = 15;
  cMaxPolls = 20;
var
  Start: Integer;
  Poll: TProc<Integer>;
begin
  Start := FPaintCount;
  PaintNow;
  Poll :=
    procedure(APolls: Integer)
    begin
      if csDestroying in ComponentState then
        Exit;
      if (FPaintCount <> Start) or (APolls >= cMaxPolls) then
        AProc()
      else
        TThread.ForceQueue(nil,
          procedure
          begin
            Poll(APolls + 1);
          end, cPollMs);
    end;
  TThread.ForceQueue(nil,
    procedure
    begin
      Poll(0);
    end, cPollMs);
end;

procedure TMainForm.RedrawAfterSizeChange;
begin
  if (csDestroying in ComponentState) or not Assigned(FRenderer) then
    Exit;
  FHoverSuppressed := True;
  SyncChromeHover;
  Recompose;
  PaintNow;
  // Once more when the layout has settled.
  TThread.ForceQueue(nil,
    procedure
    begin
      if csDestroying in ComponentState then
        Exit;
      SyncChromeHover;
      Recompose;
    end);
end;

function TMainForm.HandleCaptionRightClick(AHwnd: HWND; ALParam: LPARAM): Boolean;
var
  Pt: TPoint;
  Col, Row: Integer;
  Scale: Single;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible) then
    Exit;
  Pt := Point(SmallInt(LOWORD(ALParam)), SmallInt(HIWORD(ALParam)));
  Winapi.Windows.ScreenToClient(AHwnd, Pt);
  Scale := 1;
  if FLastScale > 1 then
    Scale := FLastScale;
  if not PointToCell(Pt.X / Scale, Pt.Y / Scale, Col, Row) then
    Exit;
  if FDualPanel.IsWindowDragZone(Col - FDualPanel.Area.Left, Row - FDualPanel.Area.Top) and
     FDualPanel.ToggleTopMenuFromTitle then
  begin
    Recompose;
    Result := True;
  end;
end;

procedure TMainForm.ClearChromeHover;
begin
  if SyncChromeHover then
    Recompose;
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
  AttachSurfaceWindows;
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
  DetachSurfaceWindows;
  inherited DestroyHandle;
end;

procedure TMainForm.DetachSurfaceWindows;
var
  Surface: Integer;
begin
  // The windows of plugin surfaces are children of the form's window and would be
  // destroyed with it; they wait unparented until the new window exists.
  for Surface in SurfaceHandles do
    NativeSurfaceDetach(HWND(PluginSurfaceNativeHandle(Surface)));
end;

procedure TMainForm.AttachSurfaceWindows;
var
  Surface: Integer;
  Wnd: HWND;
begin
  Wnd := HWND(NativeWindowHandle);
  for Surface in SurfaceHandles do
    NativeSurfaceAttach(HWND(PluginSurfaceNativeHandle(Surface)), Wnd);
  if Assigned(FDualPanel) then
    Invalidate;
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

procedure TMainForm.ButtonPressTick(Sender: TObject);
begin
  FButtonPressTimer.Enabled := False;
  FlushDialogButtonPress;
  Recompose;
end;

procedure TMainForm.ButtonHoldTick(Sender: TObject);
var
  Hold: Word;
begin
  Hold := DialogButtonHoldKey;
  if Hold = 0 then
  begin
    FButtonHoldTimer.Enabled := False;
    Exit;
  end;
  if GetKeyState(Hold) >= 0 then
  begin
    FButtonHoldTimer.Enabled := False;
    DialogButtonKeyUp(Hold);
    Recompose;
  end;
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
begin
  if not Assigned(FDualPanel) or not FDualPanel.Visible then
    Exit;
  FDualPanel.CycleTab(AReverse);
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
  Parts: TWindowTitleParts;
begin
  Parts := Default(TWindowTitleParts);
  Parts.FullName := AppTitle;
  Parts.ShortName := AppName;
  Parts.Version := 'v' + FAppVersion;
  if Assigned(FRenderer) then
  begin
    Parts.SizeText := Format('%dx%d', [FRenderer.Cols, FRenderer.Rows]);
    Parts.ZoomText := Format('%s %.0f%%', [T('ui.window.zoom', 'zoom'), FRenderer.Zoom * 100]);
    if Assigned(FMdi) and Assigned(FMdi.Active) then
      Parts.TabText := '[' + FMdi.Active.Title + ']';
  end;
  Parts.FpsText := FFpsText;
  if IsProcessElevated then
    Parts.RightsText := T('ui.window.admin', 'Administrator')
  else if Assigned(FDualPanel) and FDualPanel.HelperActive then
    Parts.RightsText := T('ui.window.adminHelper', 'Admin helper');
  Caption := ComposeTitle(Parts, MaxInt);
  // The frame rate is a native title bar detail; the grid title leaves it out.
  Parts.FpsText := '';
  if Assigned(FDualPanel) then
    FDualPanel.WindowTitleParts := Parts;
end;

procedure TMainForm.FpsTimerTick(Sender: TObject);
begin
  FFpsText := FFpsStats.TakeSummary;
  UpdateCaption;
end;

procedure TMainForm.SyncRenderer;
begin
  if not Assigned(FRenderer) then
    Exit;
  FRenderer.Resize(ClientWidth, ClientHeight, Canvas);
  UpdateCaption;
  // The title and the maximize glyph live in the grid while the native
  // title bar is hidden.
  if Assigned(FDualPanel) and not GShowTitleBar then
  begin
    FDualPanel.WindowMaximized := WindowState = System.UITypes.TWindowState.wsMaximized;
    SyncChromeHover;
    Recompose;
  end;
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

/// <summary>The ToggleFullscreen key (F11 by default) puts the window to full screen and back,
/// checked above every window like the zoom reset.</summary>
function TMainForm.TryHandleFullscreen(var AKey: Word; var AKeyChar: Char;
  AShift: TShiftState): Boolean;
begin
  Result := MatchActionIn(ActiveKeymap, [kcGlobal], KeymapLookupKey(AKey, AKeyChar),
    AShift) = kaToggleFullscreen;
  if not Result then
    Exit;
  FullScreen := not FullScreen;
  AKey := 0;
  AKeyChar := #0;
end;

function TMainForm.TryHandleZoom(var AKey: Word; var AKeyChar: Char;
  AShift: TShiftState): Boolean;
begin
  // Ctrl++ / Ctrl+- select-by-extension on Dual Panel (and must not steal
  // those chords here). Zoom is Ctrl+MouseWheel; the keymap's ZoomReset
  // (Ctrl+0) resets it. Checked above every window, like ReloadKeymap.
  Result := MatchActionIn(ActiveKeymap, [kcGlobal], KeymapLookupKey(AKey, AKeyChar),
    AShift) = kaZoomReset;
  // A console that hands every key to its program keeps Ctrl+0 for it.
  if Result and Assigned(FDualPanel) and FDualPanel.ProgramCapturesKeys then
    Result := False;
  if not Result then
    Exit;
  if Assigned(FRenderer) then
  begin
    FRenderer.SetZoom(1.0, ClientWidth, ClientHeight, Canvas);
    UpdateCaption;
    Invalidate;
  end;
  AKey := 0;
  AKeyChar := #0;
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
  FDualPanel.OnShellContextMenu := DualPanelShellContextMenu;
  FDualPanel.OnQuitRequest := DualPanelQuitRequest;
  FDualPanel.OnOpenUpdates := DualPanelOpenUpdates;
  FDualPanel.OnRunCommand := DualPanelRunCommand;
  FDualPanel.OnReturnWhenDone := DualPanelReturnWhenDone;
  FDualPanel.OnRunInBackground := DualPanelRunInBackground;
  FDualPanel.OnShellCwdSync := DualPanelShellCwdSync;
  FDualPanel.OnSaveConsoleOutput := DualPanelSaveConsoleOutput;
  FDualPanel.OnClearConsoleBuffer := DualPanelClearConsoleBuffer;
  FDualPanel.OnHelperActiveChanged := DualPanelHelperActiveChanged;
  FDualPanel.OnExportSettings := DualPanelExportSettings;
  FDualPanel.OnImportSettings := DualPanelImportSettings;
  FDualPanel.OnToggleConsole := DualPanelToggleConsole;
  FDualPanel.OnOpenTerminal := DualPanelOpenTerminal;
  FDualPanel.OnQueryConsoleKeyCapture :=
    function: Boolean
    begin
      Result := IsConsoleActiveInConsoleMode and Assigned(FConsole) and
        FConsole.KeysToProgram;
    end;
  FDualPanel.OnLaunchConsoleFile := DualPanelLaunchConsoleFile;
  FDualPanel.OnSetConsoleProfile := ChangeConsoleProfile;
  FDualPanel.OnGetConsoleProfile := GetConsoleProfile;
  FDualPanel.OnGetConsoleStartOnLaunch := GetConsoleStartOnLaunch;
  FDualPanel.OnSetConsoleStartOnLaunch := SetConsoleStartOnLaunch;
  FDualPanel.OnGetConsoleCwdToPanels := GetConsoleCwdToPanels;
  FDualPanel.OnSetConsoleCwdToPanels := SetConsoleCwdToPanels;
  FDualPanel.OnThemeSelect := ThemeSelected;
  FDualPanel.OnThemePreview := ThemePreview;
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
    Result := False; // stop enumeration - found it
  end;
end;

/// <summary>Work-area rect (Windows coords) of the monitor named ADevice,
/// if it is still connected. For restoring a window onto the same
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
/// rect would land on some currently connected monitor - i.e. the position
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
    Exit(True); // couldn't enumerate monitors - don't block startup on that
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
  if (WindowState <> System.UITypes.TWindowState.wsNormal) or FullScreen then
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
    Exit; // off-screen on every connected monitor - keep the default position
  // Prefer the monitor the window was on last time - Screen.WorkAreaRect
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
  FGridSnapDone := False;
end;

procedure TMainForm.ApplyThemeSpec(const ASpec: TThemeSpec);
begin
  FThemeProxy.SetInner(uThemeRegistry.CreateThemeFromSpec(ASpec));
  uColorCoding.SetActiveColorCodingGroups(ASpec.FileColoring);
end;

procedure TMainForm.LoadStartupTheme(const AThemeId, ALegacyThemeFile: string);
var
  Id, ImportedId: string;
  Spec: TThemeSpec;
begin
  Id := AThemeId;
  if Id = '' then
    Id := uThemeRegistry.DefaultThemeId;
  if uThemeRegistry.ImportLegacyFiles(Id, ALegacyThemeFile, ImportedId) then
    Id := ImportedId;
  FMissingThemeId := '';
  if not uThemeRegistry.TryLoadThemeSpec(Id, Spec) then
  begin
    FMissingThemeId := Id;
    Id := uThemeRegistry.DefaultThemeId;
    if not uThemeRegistry.TryLoadThemeSpec(Id, Spec) then
      Spec := ResolveThemeSpec(nil);
  end;
  FThemeName := Id;
  FThemeProxy := TThemeProxy.Create(uThemeRegistry.CreateThemeFromSpec(Spec));
  uColorCoding.SetActiveColorCodingGroups(Spec.FileColoring);
end;

procedure TMainForm.SwitchTheme(const AThemeId: string);
var
  Id: string;
  Spec: TThemeSpec;
begin
  if not Assigned(FThemeProxy) then
    Exit;
  Id := AThemeId;
  if not uThemeRegistry.TryLoadThemeSpec(Id, Spec) then
  begin
    Id := uThemeRegistry.DefaultThemeId;
    if not uThemeRegistry.TryLoadThemeSpec(Id, Spec) then
      Exit;
  end;
  ApplyThemeSpec(Spec);
  FThemeName := Id;
  Recompose;
end;

procedure TMainForm.ThemePreview(const ASpec: TThemeSpec);
begin
  if not Assigned(FThemeProxy) then
    Exit;
  ApplyThemeSpec(ASpec);
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
  Result := CanonicalShellProfileId(Result);
  if Result = '' then
    Result := cShellProfileCmd;
end;

function TMainForm.GetConsoleStartOnLaunch: Boolean;
begin
  Result := FSession.ConsoleStartOnLaunch;
end;

procedure TMainForm.SetConsoleStartOnLaunch(AValue: Boolean);
begin
  FSession.ConsoleStartOnLaunch := AValue;
end;

function TMainForm.GetConsoleCwdToPanels: Boolean;
begin
  Result := FSession.ConsoleCwdToPanels;
end;

procedure TMainForm.SetConsoleCwdToPanels(AValue: Boolean);
begin
  FSession.ConsoleCwdToPanels := AValue;
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
  Result.ShowNotifications := GShowToasts;
  Result.ShowTitleBar := GShowTitleBar;
  Result.ShowMenuBar := GShowMenuBar;
  Result.FileDrag := GFileDragEnabled;
  Result.PassiveCursor := GShowPassiveCursor;
  Result.ShowKeyBar := GShowKeyBar;
  Result.ShowStatusLine := GShowStatusLine;
  Result.ShadowStyle := GShadowStyle;
  Result.MarkedRowStyle := GMarkedRowStyle;
  Result.LineSpacing := FSession.LineSpacing;
  Result.SnapFontSize := FSession.SnapFontSize;
  Result.TextContrast := ClampTextContrast(FSession.TextContrast);
  Result.CellWidthExtra := ClampCellExtra(FSession.CellWidthExtra);
  Result.CellHeightExtra := ClampCellExtra(FSession.CellHeightExtra);
  Result.SelectFolders := FDualPanel.SelectFolders;
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
  FSession.ShowNotifications := ASettings.ShowNotifications;
  GShowToasts := ASettings.ShowNotifications;
  FSession.ShowTitleBar := ASettings.ShowTitleBar;
  FSession.ShowMenuBar := ASettings.ShowMenuBar;
  FSession.FileDrag := ASettings.FileDrag;
  GFileDragEnabled := ASettings.FileDrag;
  FSession.PassiveCursor := ASettings.PassiveCursor;
  GShowPassiveCursor := ASettings.PassiveCursor;
  FSession.ShowKeyBar := ASettings.ShowKeyBar;
  FSession.ShowStatusLine := ASettings.ShowStatusLine;
  ApplyChromeRows(ASettings.ShowMenuBar, ASettings.ShowKeyBar, ASettings.ShowStatusLine);
  ApplyTitleBar(ASettings.ShowTitleBar);
  FSession.ShadowStyle := ShadowStyleId(ASettings.ShadowStyle);
  FSession.LineSpacing := ASettings.LineSpacing;
  FSession.SnapFontSize := ASettings.SnapFontSize;
  FSession.TextContrast := ClampTextContrast(ASettings.TextContrast);
  FSession.CellWidthExtra := ClampCellExtra(ASettings.CellWidthExtra);
  FSession.CellHeightExtra := ClampCellExtra(ASettings.CellHeightExtra);
  FSession.SelectFolders := ASettings.SelectFolders;
  FDualPanel.SelectFolders := ASettings.SelectFolders;
  GShadowStyle := ASettings.ShadowStyle;
  FSession.MarkedRows := MarkedRowStyleId(ASettings.MarkedRowStyle);
  GMarkedRowStyle := ASettings.MarkedRowStyle;
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
    FRenderer.SetLineSpacing(ASettings.LineSpacing, ClientWidth, ClientHeight, Canvas);
    FRenderer.SetSnapFontSize(ASettings.SnapFontSize, ClientWidth, ClientHeight, Canvas);
    FRenderer.SetTextContrast(ASettings.TextContrast, ClientWidth, ClientHeight, Canvas);
    FRenderer.SetCellExtra(ASettings.CellWidthExtra, ASettings.CellHeightExtra,
      ClientWidth, ClientHeight, Canvas);
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
  FDualPanel.SelectFolders := Sess.SelectFolders;
  if Sess.RestoreWorkspaceOnStart then
    FDualPanel.RestoreWorkspaceLibrary(Sess.LastWorkspaceId);
  GCustomColumnsConfig := Sess.CustomColumns;
  GShowPanelIcons := Sess.ShowPanelIcons;
  GShowToasts := Sess.ShowNotifications;
  GFileDragEnabled := Sess.FileDrag;
  GShowPassiveCursor := Sess.PassiveCursor;
  ApplyChromeRows(Sess.ShowMenuBar, Sess.ShowKeyBar, Sess.ShowStatusLine);
  ApplyTitleBar(Sess.ShowTitleBar);
  GShadowStyle := ShadowStyleFromId(Sess.ShadowStyle);
  GMarkedRowStyle := MarkedRowStyleFromId(Sess.MarkedRows);
  FCursorBlinkEnabled := Sess.CursorBlink;
  FRenderer.SetFont(Sess.FontName, Sess.FontSize, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetZoom(Sess.Zoom, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetLineSpacing(Sess.LineSpacing, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetSnapFontSize(Sess.SnapFontSize, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetTextContrast(Sess.TextContrast, ClientWidth, ClientHeight, Canvas);
  FRenderer.SetCellExtra(Sess.CellWidthExtra, Sess.CellHeightExtra, ClientWidth,
    ClientHeight, Canvas);
  GConsoleSettings.ScrollbackLines := ClampScrollbackLines(Sess.ConsoleScrollback);
  GConsoleSettings.ConfirmMultiLinePaste := Sess.ConsoleConfirmPaste;
  GConsoleSettings.TrimCopiedSpaces := Sess.ConsoleTrimCopy;
  GConsoleSettings.TrimPastedSpaces := Sess.ConsoleTrimPaste;
  GConsoleSettings.ReturnToPanels := Sess.ConsoleReturnToPanels;
  GConsoleSettings.BackgroundShowMs := ClampBackgroundShowMs(Sess.ConsoleBackgroundShowMs);
  GEditorSearchOptions.MatchCase := Sess.EditorSearchCase;
  GEditorSearchOptions.WholeWord := Sess.EditorSearchWords;
  GEditorSearchOptions.UseRegex := Sess.EditorSearchRegex;
end;

procedure TMainForm.PersistSession;
var
  Sess: TMtnSession;
begin
  if not Assigned(FDualPanel) or FSettingsImported then
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
  Sess.ConsoleStartOnLaunch := FSession.ConsoleStartOnLaunch;
  Sess.ConsoleCwdToPanels := FSession.ConsoleCwdToPanels;
  // FThemeName is the live theme (switched via the Theme dialog or
  // loaded from session.json at startup) - always the source of truth here.
  Sess.ThemeName := FThemeName;
  Sess.ThemeFile := '';
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
  Sess.ShowNotifications := GShowToasts;
  Sess.ShowTitleBar := GShowTitleBar;
  Sess.ShowMenuBar := GShowMenuBar;
  Sess.FileDrag := GFileDragEnabled;
  Sess.PassiveCursor := GShowPassiveCursor;
  Sess.ShowKeyBar := GShowKeyBar;
  Sess.ShowStatusLine := GShowStatusLine;
  Sess.ShadowStyle := ShadowStyleId(GShadowStyle);
  Sess.MarkedRows := MarkedRowStyleId(GMarkedRowStyle);
  Sess.LineSpacing := FSession.LineSpacing;
  Sess.SnapFontSize := FSession.SnapFontSize;
  Sess.TextContrast := ClampTextContrast(FSession.TextContrast);
  Sess.CellWidthExtra := ClampCellExtra(FSession.CellWidthExtra);
  Sess.CellHeightExtra := ClampCellExtra(FSession.CellHeightExtra);
  Sess.ConsoleScrollback := GConsoleSettings.ScrollbackLines;
  Sess.ConsoleConfirmPaste := GConsoleSettings.ConfirmMultiLinePaste;
  Sess.ConsoleTrimCopy := GConsoleSettings.TrimCopiedSpaces;
  Sess.ConsoleTrimPaste := GConsoleSettings.TrimPastedSpaces;
  Sess.ConsoleReturnToPanels := GConsoleSettings.ReturnToPanels;
  Sess.ConsoleBackgroundShowMs := GConsoleSettings.BackgroundShowMs;
  Sess.EditorSearchCase := GEditorSearchOptions.MatchCase;
  Sess.EditorSearchWords := GEditorSearchOptions.WholeWord;
  Sess.EditorSearchRegex := GEditorSearchOptions.UseRegex;
  Sess.SelectFolders := FDualPanel.SelectFolders;
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

procedure TMainForm.AltTimerTick(Sender: TObject);
var
  Key: Word;
  KeyChar: Char;
begin
  if not FAltArmed then
  begin
    FAltTimer.Enabled := False;
    Exit;
  end;
  // Still held: wait.
  if (GetAsyncKeyState(VK_MENU) and $8000) <> 0 then
    Exit;
  FAltTimer.Enabled := False;
  FAltArmed := False;
  // Released while another window had the focus (Alt+Tab): not ours.
  if not Active then
    Exit;
  Key := 0;
  KeyChar := #0;
  DispatchTerminalKey(Key, KeyChar, [ssAlt]);
  Recompose;
end;

procedure TMainForm.SevenZipTimerTick(Sender: TObject);
const
  cHideId = 'sevenzip-missing';
  cOffId = 'plugins-off';
var
  Decl: TDialogDeclaration;
  HideId: string;
begin
  // One start-up hint at a time: that every plugin is off (a fresh install), else
  // that 7z.dll is missing for a plugin that is on.
  if HostAllPluginsOff and not DialogHidden(cOffId) then
  begin
    HideId := cOffId;
    Decl := BuildHideableMessageDialog(
      T('ui.pluginsOff.title', 'Plugins are switched off.'),
      T('ui.pluginsOff.details', '7z archives, workspaces and other extras are off.'),
      T('ui.pluginsOff.hint', 'Switch them on: Options - Plugins...'));
  end
  else if HostSevenZipDllMissing and not DialogHidden(cHideId) then
  begin
    HideId := cHideId;
    Decl := BuildHideableMessageDialog(
      T('ui.sevenZip.missing', '7z.dll not found.'),
      T('ui.sevenZip.missingDetails', '7z, RAR and encrypted ZIP archives cannot be opened.'),
      T('ui.sevenZip.missingHint', 'Copy 7z.dll to plugins\mtn.7z\ next to MTN2.exe'));
  end
  else
  begin
    FSevenZipTimer.Enabled := False;
    Exit;
  end;
  // Only over the panels; while another dialog is up or an editor is in
  // front the next tick tries again.
  if Assigned(FDualPanel) and Assigned(FMdi) and (FMdi.Active = FDualPanel) and
     FDualPanel.Visible and
     FDualPanel.ShowHostDialog(Decl,
       procedure(ACmd, AValues: string)
       begin
         if DialogValuesChecked(AValues, 'hide') then
           HideDialog(HideId);
       end) then
  begin
    FSevenZipTimer.Enabled := False;
    Recompose;
  end;
end;

function SurfaceShiftBits(Shift: TShiftState): Integer;
begin
  Result := 0;
  if ssShift in Shift then
    Result := Result or 1;
  if ssCtrl in Shift then
    Result := Result or 2;
  if ssAlt in Shift then
    Result := Result or 4;
end;

function TMainForm.TrySurfaceMouse(AKind: Integer; X, Y: Single; AButton: TMouseButton;
  AExtra: Integer; Shift: TShiftState): Boolean;
var
  H, Btn, Cand: Integer;
  B: TRectI;
  Area: TRectF;
  Left, Top, Right, Bottom, Scale: Single;
begin
  Result := False;
  if not Assigned(FDualPanel) or not Assigned(FRenderer) or (FRenderer.CellWidth <= 0) or
     (FRenderer.CellHeight <= 0) then
    Exit;
  Scale := FLastScale;
  if Scale <= 0 then
    Scale := 1;
  H := FSurfaceMouseHandle;
  if H = 0 then
    for Cand in FDualPanel.VisibleSurfaces do
    begin
      if not FDualPanel.SurfaceViewport(Cand, B) then
        Continue;
      Area := SurfaceCanvasRect(Cand, B);
      Left := Area.Left;
      Top := Area.Top;
      Right := Area.Right;
      Bottom := Area.Bottom;
      if (X >= Left) and (X < Right) and (Y >= Top) and (Y < Bottom) then
      begin
        H := Cand;
        Break;
      end;
    end;
  if (H = 0) or not FDualPanel.SurfaceViewport(H, B) or SurfaceIsNative(H) then
  begin
    FSurfaceMouseHandle := 0;
    Exit;
  end;
  Area := SurfaceCanvasRect(H, B);
  Left := Area.Left;
  Top := Area.Top;
  Right := Area.Right;
  Bottom := Area.Bottom;
  case AButton of
    TMouseButton.mbRight: Btn := 2;
    TMouseButton.mbMiddle: Btn := 3;
  else
    Btn := 1;
  end;
  Result := SurfaceDeliverMouse(H, AKind, Round((X - Left) * Scale), Round((Y - Top) * Scale),
    Round((Right - Left) * Scale), Round((Bottom - Top) * Scale), Btn, AExtra,
    SurfaceShiftBits(Shift));
  if (AKind = 0) or (AKind = 4) then
  begin
    if Result then
      FSurfaceMouseHandle := H;
  end
  else if AKind = 1 then
    FSurfaceMouseHandle := 0;
end;

procedure TMainForm.QueueSurfaceSize(AHandle, AWidth, AHeight: Integer);
begin
  if (AWidth < 1) or (AHeight < 1) then
    Exit;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not (csDestroying in ComponentState) then
        SurfaceReportSize(AHandle, AWidth, AHeight);
    end);
end;

function TMainForm.SurfaceCanvasRect(AHandle: Integer; const ABounds: TRectI): TRectF;
begin
  if (SurfaceMode(AHandle) <> cSurfaceModePanel) and SurfaceFullscreen(AHandle) then
    Result := RectF(0, 0, ClientWidth, ClientHeight)
  else
    Result := RectF(ABounds.Left * FRenderer.CellWidth, ABounds.Top * FRenderer.CellHeight,
      (ABounds.Right + 1) * FRenderer.CellWidth, (ABounds.Bottom + 1) * FRenderer.CellHeight);
end;

procedure TMainForm.SyncNativeSurfaces;
var
  H: Integer;
  B: TRectI;
  Area: TRectF;
  Scale: Single;
  Wnd: HWND;
  Visible: Boolean;
begin
  if not Assigned(FDualPanel) or not Assigned(FRenderer) then
    Exit;
  Scale := FLastScale;
  if Scale <= 0 then
    Scale := 1;
  for H in SurfaceHandles do
  begin
    Visible := FDualPanel.Visible and FDualPanel.SurfaceViewport(H, B);
    Area := RectF(0, 0, 0, 0);
    if Visible then
    begin
      Area := SurfaceCanvasRect(H, B);
      // The plugin learns the size of its area (a drawn picture is sized to it). Not from
      // inside the paint: the plugin answers with a new frame, which repaints.
      QueueSurfaceSize(H, Round(Area.Width * Scale), Round(Area.Height * Scale));
    end;
    if not SurfaceIsNative(H) then
      Continue;
    Wnd := HWND(PluginSurfaceNativeHandle(H));
    if Visible then
      NativeSurfaceMove(Wnd, Round(Area.Left * Scale), Round(Area.Top * Scale),
        Round(Area.Width * Scale), Round(Area.Height * Scale), True)
    else
      NativeSurfaceMove(Wnd, 0, 0, 0, 0, False);
  end;
end;

function TMainForm.PluginServicesOfPanels: TPluginHostServices;
begin
  Result := Default(TPluginHostServices);
  Result.DocInfo :=
    function: string
    begin
      if Assigned(FDualPanel) and (Assigned(FMdi) and (FMdi.Active = FDualPanel)) then
        Result := FDualPanel.PluginDocInfoJson
      else
        Result := '';
    end;
  Result.DocGetText :=
    function(AWhat: Integer; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(FDualPanel) and FDualPanel.PluginDocGetText(AWhat, AText);
    end;
  Result.DocReplace :=
    function(AWhat: Integer; const AText: string): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginDocReplace(AWhat, AText);
      if Result then
        Recompose;
    end;
  Result.DocSetCursor :=
    function(ARow, ACol: Integer): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginDocSetCursor(ARow, ACol);
      if Result then
        Recompose;
    end;
  Result.PanelInfo :=
    function: string
    begin
      if Assigned(FDualPanel) then
        Result := FDualPanel.PluginPanelInfoJson
      else
        Result := '';
    end;
  Result.PanelGoto :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginPanelGoto(ASide, AURI);
      if Result then
        Recompose;
    end;
  Result.PanelRefresh :=
    procedure
    begin
      if Assigned(FDualPanel) then
      begin
        FDualPanel.PluginPanelRefresh;
        Recompose;
      end;
    end;
  Result.PanelList :=
    function(ASide: Integer): string
    begin
      if Assigned(FDualPanel) then
        Result := FDualPanel.PluginPanelListJson(ASide)
      else
        Result := '';
    end;
  Result.PanelSetCursor :=
    function(ASide: Integer; const AURI: string): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginPanelSetCursor(ASide, AURI);
      if Result then
        Recompose;
    end;
  Result.PanelSelect :=
    function(ASide, AMode: Integer; const AArg: string): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginPanelSelect(ASide, AMode, AArg);
      if Result then
        Recompose;
    end;
  Result.DocSetSelection :=
    function(ARow1, ACol1, ARow2, ACol2: Integer): Boolean
    begin
      Result := Assigned(FDualPanel) and FDualPanel.PluginDocSetSelection(ARow1, ACol1, ARow2, ACol2);
      if Result then
        Recompose;
    end;
  Result.DocLine :=
    function(AIndex: Integer; out AText: string): Boolean
    begin
      AText := '';
      Result := Assigned(FDualPanel) and FDualPanel.PluginDocLine(AIndex, AText);
    end;
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
  Host.OpenFile :=
    procedure(APath: string)
    begin
      DualPanelOpenViewer(PathToFileUri(APath));
    end;
  FUpdater := TUpdateController.Create(Host);
  FUpdateTimer := TTimer.Create(Self);
  FUpdateTimer.Interval := 5000;
  FUpdateTimer.OnTimer := UpdateTimerTick;
  FUpdateTimer.Enabled := True;
  // Before the update check's own notice (5 s), so the two do not replace
  // each other.
  FPeekTimer := TTimer.Create(Self);
  FPeekTimer.Enabled := False;
  FPeekTimer.OnTimer := PeekTimerTick;
  FAltTimer := TTimer.Create(Self);
  FAltTimer.Interval := 30;
  FAltTimer.Enabled := False;
  FAltTimer.OnTimer := AltTimerTick;
  FSevenZipTimer := TTimer.Create(Self);
  FSevenZipTimer.Interval := 1500;
  FSevenZipTimer.OnTimer := SevenZipTimerTick;
  FSevenZipTimer.Enabled := True;
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

// Wheel over the Ctrl+Q text preview or the Alt+F10 folder tree scrolls it;
// FMX gives the wheel no position, so take the cursor's.
function TMainForm.TryDualPanelOverlayWheel(AWheelDelta: Integer): Boolean;
var
  P: TPointF;
  Col, Row: Integer;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible) then
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

procedure TMainForm.DualPanelShellContextMenu(const APaths: TArray<string>;
  ALocalCol, ALocalRow: Integer);
var
  Pt: TPointF;
begin
  if not Assigned(FDualPanel) or not Assigned(FRenderer) or
     (FRenderer.CellWidth <= 0) or (FRenderer.CellHeight <= 0) then
    Exit;
  // Just below the start of the cursor row, like Explorer's Shift+F10:
  // the reverse of the pixel -> cell mapping the mouse path uses.
  Pt := ClientToScreen(TPointF.Create(
    (FDualPanel.Area.Left + ALocalCol) * FRenderer.CellWidth,
    (FDualPanel.Area.Top + ALocalRow + 1) * FRenderer.CellHeight));
  ShellShowContextMenuFor(APaths, Round(Pt.X), Round(Pt.Y), NativeWindowHandle);
  Recompose;
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
    if Assigned(FRenderer) then
      SyncHiddenConsoleArea(FRenderer.Cols, FRenderer.Rows);
  end;
  Result := FConsole;
end;

procedure TMainForm.SyncHiddenConsoleArea(ACols, ARows: Integer);
begin
  if Assigned(FConsole) and not FConsole.Visible and (ACols > 0) and (ARows > 1) then
    FConsole.Area := TRectI.Make(0, 0, ACols - 1, Max(ARows - 1 - ChromeBottomRows, 1));
end;

procedure TMainForm.ChangeConsoleProfile(const AProfileId: string);
var
  ProfileId: string;
  WasVisible, HadConsole: Boolean;
begin
  ProfileId := CanonicalShellProfileId(AProfileId);
  if ProfileId = '' then
    ProfileId := cShellProfileCmd;
  FSession.BackgroundConsoleProfile := ProfileId;
  HadConsole := Assigned(FConsole);
  if HadConsole and SameText(FConsole.ProfileId, ProfileId) then
    Exit;
  // No shell yet: remember the profile. The first Ctrl+O or command starts it.
  if not HadConsole then
    Exit;
  // Restart a shell that is already up. Bring the console forward only when
  // it was visible; a hidden one stays hidden.
  WasVisible := FConsole.Visible;
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
  if WasVisible then
    ShowConsoleMode
  else
  begin
    EnsureConsole;
    if Assigned(FConsole) and Assigned(FDualPanel) then
      FConsole.EnsureShell(FDualPanel.ActiveLocalPath);
  end;
  Recompose;
end;

procedure TMainForm.ApplyChromeRows(AMenuBar, AKeyBar, AStatusLine: Boolean);
begin
  GShowMenuBar := AMenuBar;
  GShowKeyBar := AKeyBar;
  GShowStatusLine := AStatusLine;
  // The console sits right above the shared F-keys / status line.
  if Assigned(FConsole) then
    FConsole.LayoutBottomMargin := ChromeBottomRows;
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
  // First Ctrl+O (and Esc-to-console) pays shell startup here. A shell that
  // is already running is left alone - EnsureShell would cd to the panel.
  if not FConsole.Running then
  begin
    if Assigned(FDualPanel) then
      FConsole.EnsureShell(FDualPanel.ActiveLocalPath)
    else
      FConsole.EnsureShell('');
  end;
  FMdi.Activate(FConsole);
  UpdateBlinkTimer;
end;

procedure TMainForm.ShowPanelMode;
var
  Cwd: string;
begin
  // Commands run in the console (a user-menu command, a typed cd) can leave
  // the shell in another folder; the active panel follows it.
  if Assigned(FConsole) and Assigned(FDualPanel) and FSession.ConsoleCwdToPanels and
     FConsole.TakeCwdChange(Cwd) then
    FDualPanel.SetActivePanelDir(Cwd);
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

procedure TMainForm.DualPanelRunInBackground(Sender: TObject);
begin
  FPeekTimer.Enabled := False;
  FPeekTimer.Interval := ClampBackgroundShowMs(GConsoleSettings.BackgroundShowMs);
  FPeekTimer.Enabled := True;
end;

procedure TMainForm.PeekTimerTick(Sender: TObject);
begin
  FPeekTimer.Enabled := False;
  if IsConsoleActiveInConsoleMode then
    ConsoleBackToPanels(Self);
end;

procedure TMainForm.DualPanelReturnWhenDone(Sender: TObject);
begin
  if Assigned(FConsole) then
    FConsole.ReturnToPanelsWhenDone;
end;

procedure TMainForm.DualPanelShellCwdSync(const APath: string);
begin
  // Lazy: only push cd into an already-running persistent shell.
  if not Assigned(FConsole) then
    Exit;
  FConsole.SyncWorkingDir(APath);
end;

function TMainForm.DualPanelSaveConsoleOutput(const APath: string;
  out AError: string): Boolean;
begin
  if not Assigned(FConsole) then
  begin
    AError := T('ui.toast.noConsole', 'The background console has not been started yet');
    Exit(False);
  end;
  Result := FConsole.SaveOutputToFile(APath, AError);
end;

procedure TMainForm.DualPanelHelperActiveChanged(Sender: TObject);
begin
  UpdateCaption;
end;

function TMainForm.DualPanelExportSettings(const APath: string;
  out AError: string): Boolean;
var
  Count: Integer;
begin
  // The session file is what the settings dialogs changed since start.
  PersistSession;
  Result := ExportSettings(APath, Count, AError);
end;

function TMainForm.DualPanelImportSettings(const APath: string;
  out AError: string): Boolean;
var
  Count: Integer;
begin
  Result := ImportSettings(APath, Count, AError);
  // The imported session.json must not be overwritten by the running state
  // when the program closes: the new settings take effect at the next start.
  if Result then
    FSettingsImported := True;
end;

procedure TMainForm.DualPanelClearConsoleBuffer(Sender: TObject);
begin
  if not Assigned(FConsole) then
    Exit;
  FConsole.ClearOutputBuffer;
  Recompose;
end;

procedure TMainForm.ConsoleSyncDirToPanels(Sender: TObject);
var
  Cwd: string;
begin
  if not Assigned(FConsole) or not Assigned(FDualPanel) then
    Exit;
  Cwd := FConsole.PromptCwd;
  if Cwd = '' then
    Cwd := FConsole.WorkingDir;
  FDualPanel.SetActivePanelDir(Cwd);
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
  // ConsoleMode: Ctrl+O always restores panels - it must never stop a
  // running command (that's Ctrl+C's job). If the flag is set but the
  // console window is not up, show the console instead of restoring an already-blank Dual Panel.
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
  // Esc must never stop an in-flight command (Ctrl+C does that) - it only
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

function TMainForm.DualPanelLaunchConsoleFile(const APath: string): Boolean;
var
  Kind: TLaunchFileKind;
  Cwd, Profile: string;
begin
  Kind := DetectLaunchFileKind(APath);
  Result := Kind <> lfkOther;
  if not Result then
    Exit;
  Cwd := ExtractFileDir(APath);
  Profile := GetConsoleProfile;
  case ChooseConsoleLaunch(Kind, Profile, Assigned(FConsole) and FConsole.ShellBusy) of
    cltConsole:
      DualPanelRunCommand(BuildConsoleLaunchLine(APath, Kind, Profile), Cwd);
    cltTerminal:
      begin
        Profile := TerminalProfileForLaunch(Kind);
        DualPanelOpenTerminalWith(Profile, Cwd, BuildConsoleLaunchLine(APath, Kind, Profile));
      end;
  else
    Result := False;
  end;
end;

procedure TMainForm.DualPanelOpenTerminal(const AProfileId, ACwd: string);
begin
  DualPanelOpenTerminalWith(AProfileId, ACwd, '');
end;

procedure TMainForm.DualPanelOpenTerminalWith(const AProfileId, ACwd, ACommand: string);
begin
  if (AProfileId = '') or not Assigned(FDualPanel) then
    Exit;
  // Leave panel console overlay if open.
  if FDualPanel.ConsoleMode then
    ShowPanelMode;
  FDualPanel.OpenTerminal(AProfileId, ACwd, ACommand);
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
  if FpsRequested then
  begin
    FFpsStats.Reset;
    FFpsTimer := TTimer.Create(Self);
    FFpsTimer.Interval := 1000;
    FFpsTimer.OnTimer := FpsTimerTick;
    FFpsTimer.Enabled := True;
  end;
  FRestoringBounds := False;
  FNormalLeft := Left;
  FNormalTop := Top;
  FNormalWidth := Width;
  FNormalHeight := Height;

  ReloadKeymap('');

  SetLocale(PeekSessionLanguage);
  PeekSessionTheme(SessionThemeNameValue, SessionThemeFileValue);
  LoadStartupTheme(SessionThemeNameValue, SessionThemeFileValue);
  FTheme := FThemeProxy;
  FMdi := TMdiCompositor.Create(FTheme);
  EnsureDemoWindows;

  StartPluginHost(TPath.Combine(ExtractFilePath(ParamStr(0)), 'plugins'));

  FRenderer := TTerminalRenderer.Create;
  FRenderer.OnCompose := ComposeScene;
  if Assigned(FFpsTimer) then
    FRenderer.OnRasterized :=
      procedure(AElapsedTicks: Int64)
      begin
        FFpsStats.Add(fsRender, AElapsedTicks);
      end;
  // Defaults for a missing/unreadable session.json (TryRestoreSession leaves
  // FSession untouched on failure, which would otherwise zero-init to False).
  FSession.ConsoleRestartOnExit := True;
  FSession.TerminalCloseOnExit := True;
  FSession.AutoSyncConsoleCwd := False;
  FSession.ConsoleCwdToPanels := True;
  FSession.ConsoleStartOnLaunch := False;
  FSession.RestoreWorkspaceOnStart := True;
  FSession.FontSize := cDisplayDefaultFontSize;
  FSession.CursorBlink := True;
  FSession.CursorBlinkMs := cBlinkIntervalMs;
  FSession.ShowPanelIcons := True;
  FSession.ShowNotifications := True;
  FSession.ShowTitleBar := True;
  FSession.ShowMenuBar := True;
  FSession.FileDrag := True;
  FSession.PassiveCursor := True;
  FSession.ShowKeyBar := True;
  FSession.ShowStatusLine := True;
  FSession.ShadowStyle := ShadowStyleId(ssClassic);
  FSession.MarkedRows := MarkedRowStyleId(mrsText);
  FCursorBlinkEnabled := True;
  TryRestoreSession;
  // Mtn2 <path> - a brand new tab for the CLI path, restored
  // session tabs are left untouched. Updater switches (--wait-pid) are not paths.
  if StartupPathArgument <> '' then
    OpenPathFromArgument(StartupPathArgument);
  SyncRenderer;
  if (FMissingThemeId <> '') and Assigned(FDualPanel) then
    FDualPanel.ShowInfo(T('ui.theme.title', 'Theme'),
      Format(T('ui.theme.notFound',
        'Theme "%s" was not found; the classic Far theme is used.'),
        [FMissingThemeId]));

  // Optional pre-warm (Commands -> Background console, "Start shell at
  // program launch"). Off by default: the shell starts on the first Ctrl+O
  // or the first command from the command line.
  if FSession.ConsoleStartOnLaunch then
  begin
    EnsureConsole;
    if Assigned(FConsole) and Assigned(FDualPanel) then
      FConsole.EnsureShell(FDualPanel.ActiveLocalPath);
  end;

  FBlinkPhase := True;
  FBlinkTimer := TTimer.Create(Self);
  FBlinkTimer.Interval := ClampDisplayBlinkMs(FSession.CursorBlinkMs);
  FBlinkTimer.OnTimer := BlinkTick;
  FBlinkTimer.Enabled := False;
  FButtonPressTimer := TTimer.Create(Self);
  FButtonPressTimer.Interval := cDialogButtonPressMs;
  FButtonPressTimer.OnTimer := ButtonPressTick;
  FButtonPressTimer.Enabled := False;
  FButtonHoldTimer := TTimer.Create(Self);
  FButtonHoldTimer.Interval := 30;
  FButtonHoldTimer.OnTimer := ButtonHoldTick;
  FButtonHoldTimer.Enabled := False;
  GDialogButtonPressStart :=
    procedure
    begin
      FButtonPressTimer.Enabled := False;
      FButtonPressTimer.Enabled := True;
    end;

  FContextMenuTimer := TTimer.Create(Self);
  FContextMenuTimer.Interval := cContextMenuHoldMs;
  FContextMenuTimer.OnTimer := ContextMenuHoldTick;
  FContextMenuTimer.Enabled := False;

  CreateUpdater;

  // Dialogs a plugin asks for: only over the panels, like the updater's, so a
  // plugin never pops one up inside an editor, viewer or terminal.
  SetPluginDialogHost(
    function(const ADecl: TDialogDeclaration; const AOnCommand: TProc<string, string>): Boolean
    begin
      Result := Assigned(FDualPanel) and Assigned(FMdi) and (FMdi.Active = FDualPanel) and
        FDualPanel.Visible and FDualPanel.ShowHostDialog(ADecl, AOnCommand);
      if Result then
        Recompose;
    end);

  // Picture tabs a plugin opens (uPluginSurface): like dialogs, only from the panels.
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      Result := Assigned(FDualPanel) and Assigned(FMdi) and (FMdi.Active = FDualPanel) and
        FDualPanel.Visible and FDualPanel.OpenSurfaceTab(AHandle);
      if Result then
        Recompose;
    end);

  // Native windows for plugin surfaces: children of this window kept over their cells.
  SetSurfaceNativeHooks(
    function(AHandle: Integer): Int64
    begin
      Result := Int64(NativeSurfaceCreate(WindowHandleToPlatform(Handle).Wnd));
    end,
    procedure(AHandle: Integer; AWindow: Int64)
    begin
      NativeSurfaceDestroy(HWND(AWindow));
    end);

  // What plugins may ask of the documents and panels on screen.
  SetPluginHostServices(PluginServicesOfPanels);

  // A plugin changing its status-line text repaints the panels.
  SetPluginChromeChanged(
    procedure
    begin
      TThread.Queue(nil,
        procedure
        begin
          if not (csDestroying in ComponentState) then
            Recompose;
        end);
    end);

  // Quick View decode/error lands async - repaint once it does.
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
  // Only now is the native handle valid for a second instance to
  // find and send WM_COPYDATA to.
  PublishInstanceWindow(HWND(NativeWindowHandle));
  GRecycleOwnerWindow := NativeUInt(NativeWindowHandle);
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
  FreeAndNil(FAltTimer);
  FreeAndNil(FSevenZipTimer);
  FreeAndNil(FFpsTimer);
  FreeAndNil(FUpdater);
  SetPluginDialogHost(nil);
  SetPluginSurfaceHost(nil);
  SetSurfaceNativeHooks(nil, nil);
  SetPluginHostServices(Default(TPluginHostServices));
  SetPluginChromeChanged(nil);
  StopPluginHost;
  FreeAndNil(FBlinkTimer);
  GDialogButtonPressStart := nil;
  FreeAndNil(FButtonPressTimer);
  FreeAndNil(FButtonHoldTimer);
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
var
  T0: Int64;
begin
  if not Assigned(FMdi) then
    Exit;
  T0 := TStopwatch.GetTimeStamp;
  // Console keeps a bottom margin (LayoutBottomMargin) for the shared F-keys / status line.
  FMdi.LayoutMaximized(ACols, ARows);
  SyncHiddenConsoleArea(ACols, ARows);
  FMdi.Paint(AGrid, ACols, ARows);
  // The console frame is painted above the panel window: the window buttons go over it.
  if Assigned(FDualPanel) then
    FDualPanel.PaintConsoleWindowButtons(AGrid, ACols);
  if Assigned(FFpsTimer) then
    FFpsStats.Add(fsCompose, TStopwatch.GetTimeStamp - T0);
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
  SyncChromeHover;
  UpdateCaption;
  FRenderer.Recompose;
  Invalidate;
end;

procedure TMainForm.FormPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
var
  T0: Int64;
begin
  if not Assigned(FRenderer) then
    Exit;
  Inc(FPaintCount);
  T0 := TStopwatch.GetTimeStamp;
  try
    PaintFrame(Canvas);
  finally
    if Assigned(FFpsTimer) then
      FFpsStats.Add(fsPaint, TStopwatch.GetTimeStamp - T0);
  end;
  SyncNativeSurfaces;
  // Cell metrics are known after the first frame: fit the window to the grid.
  if not FGridSnapDone then
  begin
    FGridSnapDone := True;
    TThread.ForceQueue(nil, SnapWindowToGrid);
  end;
end;

/// <summary>A full-screen plugin picture covers the pixels the whole cells leave over at the right
/// and bottom edge: they get the picture's background, and the overlay is painted over the
/// whole client area.</summary>
procedure TMainForm.PaintSurfaceFullscreenFrame(Canvas: TCanvas);
var
  Background: TAlphaColor;
  GridW, GridH: Single;
begin
  if not (Assigned(FDualPanel) and FDualPanel.SurfaceFullscreenBackground(Background)) then
  begin
    ClearOverlayPixelArea;
    Exit;
  end;
  GridW := FRenderer.Cols * FRenderer.CellWidth;
  GridH := FRenderer.Rows * FRenderer.CellHeight;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := Background;
  if GridW < ClientWidth then
    Canvas.FillRect(RectF(GridW, 0, ClientWidth, ClientHeight), 0, 0, [], 1);
  if GridH < ClientHeight then
    Canvas.FillRect(RectF(0, GridH, ClientWidth, ClientHeight), 0, 0, [], 1);
  SetOverlayPixelArea(RectF(0, 0, ClientWidth, ClientHeight));
end;

procedure TMainForm.PaintFrame(Canvas: TCanvas);
begin
  if (Canvas.Scale > 0) and (Canvas.Scale <> FLastScale) then
  begin
    FLastScale := Canvas.Scale;
    FRenderer.SetSceneScale(Canvas.Scale, ClientWidth, ClientHeight, Canvas);
    UpdateCaption;
  end;
  FRenderer.Draw(Canvas, RectF(0, 0, ClientWidth, ClientHeight));
  PaintSurfaceFullscreenFrame(Canvas);
  // Markdown image blocks are sized in cells from the pixel cell aspect;
  // after a font/scale change re-lay out once so the next frame uses it.
  if SetOverlayCellMetrics(FRenderer.CellWidth, FRenderer.CellHeight, FLastScale) then
    TThread.ForceQueue(nil,
      procedure
      begin
        Recompose;
      end);
  // Media Overlay (Ctrl+Q Quick View) - separate canvas pass on
  // top of the grid, per OVERLAY_PLUGIN.md invariant 2 ("not TCharCell").
  // Gated by QuickViewVisible: the overlay's stored bounds only make sense
  // while Dual Panel is showing its wkPanels list, not Console/Viewer/
  // Editor/Terminal, and this Canvas pass has no other way to know that.
  if Assigned(FDualPanel) and FDualPanel.QuickViewVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight)
  // Markdown Viewer image reuses the same Media Overlay singleton.
  // F3 opens the Viewer as a Dual Panel document tab, so FMdi.Active is
  // DualPanel - not TEditorWindow. Check the nested document first; keep
  // the standalone-editor branch for a future MDI editor window.
  else if Assigned(FDualPanel) and FDualPanel.MarkdownImageOverlayVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight)
  else if Assigned(FMdi) and Assigned(FMdi.Active) and (FMdi.Active is TEditorWindow) and
          TEditorWindow(FMdi.Active).MarkdownImageOverlayVisible then
    DrawOverlayPreview(Canvas, FRenderer.CellWidth, FRenderer.CellHeight);
end;

procedure TMainForm.FormResize(Sender: TObject);
var
  Maximized: Boolean;
begin
  CaptureNormalBounds;
  // A window restored from full screen is trimmed to whole cells on the next paint.
  Maximized := (WindowState = System.UITypes.TWindowState.wsMaximized) or FullScreen;
  if FWasMaximized and not Maximized then
    FGridSnapDone := False;
  FWasMaximized := Maximized;
  SyncRenderer;
end;

procedure TMainForm.FormMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  K: Word;
  C: Char;
  P: TPointF;
begin
  // The wheel over a plugin surface is the plugin's (clicks, away from the user positive).
  P := ScreenToClient(Screen.MousePos);
  if TrySurfaceMouse(3, P.X, P.Y, TMouseButton.mbMiddle, WheelDelta div 120, Shift) then
  begin
    Recompose;
    Handled := True;
    Exit;
  end;
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ApplyZoomDelta(0.1)
    else
      ApplyZoomDelta(-0.1);
    Handled := True;
  end
  else if TryDualPanelOverlayWheel(WheelDelta) then
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

function TMainForm.TryDispatchConsoleFunctionBarClick(Col, Row: Integer;
  Shift: TShiftState): Boolean;
var
  Key: Word;
  KeyChar: Char;
  KeyShift: TShiftState;
begin
  Result := False;
  if not (Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.ConsoleMode and
          Assigned(FConsole) and FConsole.Visible and FDualPanel.HitTest(Col, Row)) then
    Exit;
  if not FDualPanel.FunctionBarClickKey(Col - FDualPanel.Area.Left,
       Row - FDualPanel.Area.Top, Shift, Key, KeyChar, KeyShift) then
    Exit;
  Result := DispatchTerminalKey(Key, KeyChar, KeyShift);
end;

function TMainForm.TryDispatchDualPanelMouseDown(Col, Row: Integer; Dbl: Boolean;
  Shift: TShiftState; AButton: TMouseButton; const AScreenPt: TPointF): Boolean;
var
  LocalCol, LocalRow: Integer;
  Path: string;
  MenuClick: Boolean;
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
  // A click on the menu bar, inside an open menu or on a dialog never starts a file
  // drag (the drop would copy the cursor file).
  MenuClick := FDualPanel.TopMenuOpen or (LocalRow = 0) or FDualPanel.HasOpenDialog;
  FDualPanel.HandleClick(LocalCol, LocalRow, Dbl, Shift);
  // Only a press on a file row can become a drag: not one that closed a dialog or hit
  // the menu, the tab row, the key bar or empty space.
  if (AButton = TMouseButton.mbLeft) and not Dbl and not MenuClick and
     FDualPanel.HitTestListItemLocalPath(LocalCol, LocalRow, Path) then
    FDualPanel.ArmFileDragFromCursor;
end;

procedure TMainForm.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Col, Row: Integer;
  Dbl: Boolean;
begin
  FAltArmed := False;
  // A click, like a key, takes the console over from a background command.
  FPeekTimer.Enabled := False;
  if not Assigned(FMdi) then
    Exit;
  if TrySurfaceMouse(IfThen((Button = TMouseButton.mbLeft) and (ssDouble in Shift), 4, 0), X, Y,
       Button, 0, Shift) then
  begin
    Recompose;
    Exit;
  end;
  if not PointToCell(X, Y, Col, Row) then
  begin
    if Button = TMouseButton.mbRight then
      CancelContextMenuHold;
    Exit;
  end;
  // The window buttons on the console frame sit above the console, which
  // would take the click otherwise.
  if (Button = TMouseButton.mbLeft) and Assigned(FDualPanel) and
     FDualPanel.HandleConsoleFrameClick(Col - FDualPanel.Area.Left,
       Row - FDualPanel.Area.Top) then
  begin
    Recompose;
    Exit;
  end;
  Dbl := (Button = TMouseButton.mbLeft) and (ssDouble in Shift);
  if Button = TMouseButton.mbLeft then
  begin
    CancelContextMenuHold;
    DialogButtonMouseDown(Col, Row);
  end
  else
  begin
    if DialogButtonHoldKey <> 0 then
      CancelDialogButtonPress;
    FlushDialogButtonPress;
  end;

  // Before ActivateAt: the bar is Dual Panel's, and activating it while the
  // console shows would hide the console and leave the panels blank.
  if (Button = TMouseButton.mbLeft) and TryDispatchConsoleFunctionBarClick(Col, Row, Shift) then
  begin
    Recompose;
    Exit;
  end;
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
  // Dragging through an open menu moves its selection; no file drag starts.
  if FDualPanel.TopMenuOpen then
  begin
    if FDualPanel.HandleMouseMove(LocalCol, LocalRow) then
      Recompose;
    Exit(True);
  end;
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
  Btn: TMouseButton;
begin
  if not Assigned(FMdi) then
    Exit;
  // A plugin surface sees the moves of a button held on it.
  if FSurfaceMouseHandle <> 0 then
  begin
    if ssRight in Shift then
      Btn := TMouseButton.mbRight
    else if ssMiddle in Shift then
      Btn := TMouseButton.mbMiddle
    else
      Btn := TMouseButton.mbLeft;
    if TrySurfaceMouse(2, X, Y, Btn, 0, Shift) then
      Recompose;
    Exit;
  end;

  if not FChromeCommandPending then
    FHoverSuppressed := False;
  if Assigned(FDualPanel) and (not FChromeCommandPending) and PointToCell(X, Y, Col, Row) and
     FDualPanel.UpdateChromeHover(Col - FDualPanel.Area.Left, Row - FDualPanel.Area.Top) then
    Recompose;

  if DialogButtonCaptured then
  begin
    if PointToCell(X, Y, Col, Row) and DialogButtonCaptureMove(Col, Row) then
      Recompose;
    Exit;
  end;

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
var
  Col, Row: Integer;
  Btn: TWindowButton;
  Acts: Boolean;
begin
  if FSurfaceMouseHandle <> 0 then
  begin
    TrySurfaceMouse(1, X, Y, Button, 0, Shift);
    FSurfaceMouseHandle := 0;
    Recompose;
    Exit;
  end;
  if Button = TMouseButton.mbRight then
  begin
    CancelContextMenuHold;
    Exit;
  end;
  if Button <> TMouseButton.mbLeft then
    Exit;
  // A window button acts on release; outside the window it is cancelled.
  if Assigned(FDualPanel) then
  begin
    if not PointToCell(X, Y, Col, Row) then
    begin
      Col := -1;
      Row := -1;
    end
    else
    begin
      Dec(Col, FDualPanel.Area.Left);
      Dec(Row, FDualPanel.Area.Top);
    end;
    if FDualPanel.HandleMenuMouseUp(Col, Row) then
    begin
      Recompose;
      Exit;
    end;
    if FDualPanel.ReleaseChromeButton(Col, Row, Btn, Acts) then
    begin
      // The button is drawn released first, then its command runs.
      Recompose;
      if Acts then
      begin
        FChromeCommandPending := True;
        RunAfterPaint(
          procedure
          begin
            FChromeCommandPending := False;
            HandleWindowCommand(Btn);
          end);
      end
      else
        PaintNow;
      Exit;
    end;
  end;
  if DialogButtonCaptured then
  begin
    if not PointToCell(X, Y, Col, Row) then
    begin
      Col := -1;
      Row := -1;
    end;
    DialogButtonCaptureRelease(Col, Row);
    Recompose;
    Exit;
  end;
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
  Result := TKeyChord.Make(Key, #0, Shift).Matches(vkEscape);
end;

function TMainForm.IsConsoleNavigationKey(Key: Word): Boolean;
begin
  Result := (Key = vkPrior) or (Key = vkNext) or (Key = vkHome) or (Key = vkEnd) or
    (Key = vkUp) or (Key = vkDown) or (Key = vkLeft) or (Key = vkRight);
end;

function TMainForm.IsConsoleCopySelectAllKey(Key: Word; KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := TKeyChord.Make(Key, KeyChar, Shift).MatchesLetter('C', [ssCtrl], [ssShift]) or
    TKeyChord.Make(Key, KeyChar, Shift).MatchesLetter('A', [ssCtrl], [ssShift]);
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
// Left Alt or Right Ctrl held.
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
  Result := MatchActionIn(ActiveKeymap, [kcGlobal], KeymapLookupKey(AKey, AKeyChar),
    AShift) = kaReloadKeymap;
end;

// Host form dialogs (MkDir/Copy/...) live on Dual Panel - must win over the
// active MDI window (Console/Editor) so Enter reaches the default button.
function TMainForm.TryDispatchDualPanelDialogKey(var Key: Word; var KeyChar: Char;
  Shift: TShiftState): Boolean;
begin
  Result := Assigned(FDualPanel) and FDualPanel.Visible and FDualPanel.DialogVisible and
    FDualPanel.HandleInput(Key, Shift, KeyChar);
end;

// Esc in ConsoleMode always restores panels (never stops the running command
// - Ctrl+C does that). Routed through FConsole.HandleInput first so an
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
  Handled: Boolean;
begin
  SyncKeyModifiers(Shift);
  K := Key;
  C := Char(KeyChar);
  // Modifier-only press: update F-bar and swallow so the menu does not steal Alt.
  if IsModifierOnlyKey(K) then
  begin
    // Alt alone arms the menu; Ctrl or Shift joining it (AltGr, a layout switch)
    // disarms it, like any other key below.
    FAltArmed := ((K = vkMenu) or (K = vkLMenu)) and ([ssCtrl, ssShift] * Shift = []) and
      not (Assigned(FDualPanel) and FDualPanel.ProgramCapturesKeys);
    FAltTimer.Enabled := FAltArmed;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  FAltArmed := False;
  // Enter variants -> vkReturn; AltGr+Enter -> Alt+Enter (Properties), not
  // Ctrl+Alt+Enter (reveal on the other panel). See uKeyChord.
  NormalizeKeyInput(K, C, Shift, IsAltGrDown);
  // A button held by Enter or Space: Esc lifts it without the command, other
  // keys (autorepeat, the WM_CHAR twin) are swallowed. A key up lost to
  // another window (GetKeyState says the key is up) lifts it too.
  if DialogButtonHoldKey <> 0 then
  begin
    if (GetKeyState(DialogButtonHoldKey) >= 0) or (K = vkEscape) then
    begin
      CancelDialogButtonPress;
      Recompose;
    end;
    if (DialogButtonHoldKey <> 0) or (K = vkEscape) then
    begin
      Key := 0;
      KeyChar := #0;
      Exit;
    end;
  end;
  // A dialog button still showing its keyboard press runs its command
  // before this key is handled.
  if DialogButtonPressPending then
  begin
    FlushDialogButtonPress;
    Recompose;
  end;
  if TryHandleZoom(K, C, Shift) or TryHandleFullscreen(K, C, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  // Plain Enter / Space that presses a dialog button holds it until key up.
  if Shift * [ssCtrl, ssAlt] <> [] then
    GDialogPressHoldKey := 0
  else if K = vkReturn then
    GDialogPressHoldKey := vkReturn
  else if (K = vkSpace) or ((K = 0) and (C = ' ')) then
    GDialogPressHoldKey := vkSpace
  else
    GDialogPressHoldKey := 0;
  try
    Handled := DispatchTerminalKey(K, C, Shift);
  finally
    GDialogPressHoldKey := 0;
  end;
  if DialogButtonHoldKey <> 0 then
    FButtonHoldTimer.Enabled := True;
  if Handled then
  begin
    Key := 0;
    KeyChar := #0;
    Exit; // do not call inherited - prevents FMX Tab focus cycling
  end;
  inherited KeyDown(Key, KeyChar, Shift);
end;

procedure TMainForm.KeyUp(var Key: Word; var KeyChar: System.WideChar;
  Shift: TShiftState);
var
  K: Word;
  C: Char;
begin
  SyncKeyModifiers(Shift);
  if IsModifierOnlyKey(Key) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  // The same key mapping as KeyDown, so the release matches the key that
  // pressed the button (Space may arrive with no virtual code, only as a space char).
  K := Key;
  C := Char(KeyChar);
  NormalizeKeyInput(K, C, Shift, IsAltGrDown);
  if (K = 0) and (C = ' ') then
    K := vkSpace;
  if DialogButtonKeyUp(K) then
  begin
    Recompose;
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
  // Typing takes the console over: a command started in the background no
  // longer sends the program back to the panels.
  if (Key <> vkShift) and (Key <> vkControl) and (Key <> vkMenu) then
    FPeekTimer.Enabled := False;

  // ReloadKeymap (Ctrl+Alt+K) - reload keymap.json from config dir.
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

  if TryHandleZoom(Key, KeyChar, Shift) or TryHandleFullscreen(Key, KeyChar, Shift) then
    Exit;

  if DispatchTerminalKey(Key, KeyChar, Shift) then
    Exit;
end;

end.
