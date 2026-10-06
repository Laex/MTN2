unit uPluginSurface;

{ Picture surface for plugins: a plugin opens a viewer tab, hands the host
  frames of BGRA pixels and gets key presses, timer ticks and the close
  notice back. The host draws the frame into the tab body (the same Canvas
  pass as Quick View pictures), fitted to the viewport and centered; the
  plugin never draws anything itself.

  The host window that shows the tab registers itself with
  SetPluginSurfaceHost. Without one (tests, tools) nothing opens and
  PluginSurfaceOpen reports 0.

  A surface lives from PluginSurfaceOpen until the user closes the tab, the
  plugin closes it, or the plugin is unloaded. No callback reaches a plugin
  after that. Main thread only. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.UITypes;

type
  /// <summary>A key pressed on the surface, named like "Left", "Space", "Ctrl+C", "+".
  /// True when the plugin used it.</summary>
  TSurfaceKeyCallback = reference to function(const AKey: string): Boolean;

  /// <summary>Opens the viewer tab of surface AHandle (see SurfaceAttach).
  /// False when no tab can be opened now.</summary>
  TSurfaceOpenHandler = reference to function(AHandle: Integer): Boolean;

  /// <summary>Mouse on the surface: AKind 0 down, 1 up, 2 move while a button is held,
  /// 3 wheel (AExtra = clicks), 4 double click, 5 the area changed size; AX, AY and AWidth, AHeight in pixels of the
  /// picture area; AButton 1 left, 2 right, 3 middle; AShift bits 1 Shift, 2 Ctrl, 4 Alt.
  /// True when the plugin used the event.</summary>
  TSurfaceMouseCallback = reference to function(AKind, AX, AY, AWidth, AHeight, AButton,
    AExtra, AShift: Integer): Boolean;

  /// <summary>Creates the native window of surface AHandle and returns its handle
  /// (0 = could not).</summary>
  TSurfaceNativeCreate = reference to function(AHandle: Integer): Int64;
  TSurfaceNativeDestroy = reference to procedure(AHandle: Integer; AWindow: Int64);

const
  /// <summary>Places of a surface (SurfaceMode).</summary>
  cSurfaceModeTab = 0;
  cSurfaceModeFullscreen = 1;
  cSurfaceModePanel = 2;
  /// <summary>Added to the mode: the host creates a native window instead of showing frames.</summary>
  cSurfaceNativeFlag = 256;
  cSurfaceMaxSide = 16384;
  cSurfaceMaxBytes = 256 * 1024 * 1024;

/// <summary>Registers (or, with nil, removes) the window that shows surface tabs.</summary>
procedure SetPluginSurfaceHost(const AOpen: TSurfaceOpenHandler);

/// <summary>Opens a surface tab titled ATitle for plugin APluginId. AOnKey, AOnTick
/// and AOnClosed are optional. Returns the handle (above 0), or 0 when no tab can
/// be opened.</summary>
function PluginSurfaceOpen(const APluginId, ATitle: string; const AOnKey: TSurfaceKeyCallback;
  const AOnTick, AOnClosed: TProc): Integer;

/// <summary>As PluginSurfaceOpen with a place (cSurfaceMode*, plus cSurfaceNativeFlag)
/// and a mouse handler. Returns 0 for an unknown mode, or a native surface when the
/// program cannot make native windows.</summary>
function PluginSurfaceOpenEx(const APluginId, ATitle: string; AMode: Integer;
  const AOnKey: TSurfaceKeyCallback; const AOnTick, AOnClosed: TProc;
  const AOnMouse: TSurfaceMouseCallback): Integer;

/// <summary>Switches a tab surface between normal and full screen.</summary>
function PluginSurfaceSetFullscreen(AHandle: Integer; AOn: Boolean): Boolean;

/// <summary>Window handle of a native surface, 0 for the others.</summary>
function PluginSurfaceNativeHandle(AHandle: Integer): Int64;

/// <summary>Registers how the program makes and drops native windows (nil removes them).</summary>
procedure SetSurfaceNativeHooks(const ACreate: TSurfaceNativeCreate;
  const ADestroy: TSurfaceNativeDestroy);

/// <summary>Replaces the picture with AWidth x AHeight pixels, 4 bytes each in
/// B, G, R, A order, rows top to bottom without padding. APixels is copied.
/// False for an unknown handle or a size that does not match the data.</summary>
function PluginSurfaceSetFrame(AHandle, AWidth, AHeight: Integer; APixels: PByte;
  ALength: Int64): Boolean;

/// <summary>Sets the tab title and the text of the status line.</summary>
function PluginSurfaceSetInfo(AHandle: Integer; const ATitle, AStatus: string): Boolean;

/// <summary>Calls the plugin's tick callback every AIntervalMs milliseconds while the
/// tab is on screen; 0 stops it.</summary>
function PluginSurfaceSetTimer(AHandle, AIntervalMs: Integer): Boolean;

/// <summary>Closes the tab from the plugin side (its close callback is not called).</summary>
function PluginSurfaceClose(AHandle: Integer): Boolean;

/// <summary>Closes the surfaces of APluginId; none of its callbacks runs afterwards.</summary>
procedure PluginSurfaceUnregister(const APluginId: string);

{ Host side: the tab that shows the surface. }

/// <summary>Binds the tab to the surface: ARepaint runs when a frame or the
/// text changes, AClose when the plugin closes the surface or is unloaded
/// (the tab must close; it then calls SurfaceTabClosed).</summary>
procedure SurfaceAttach(AHandle: Integer; const ARepaint, AClose: TProc);

/// <summary>The tab was closed: tells the plugin (unless it closed the surface
/// itself) and forgets the surface. Safe to call twice.</summary>
procedure SurfaceTabClosed(AHandle: Integer);

function SurfaceMode(AHandle: Integer): Integer;
function SurfaceIsNative(AHandle: Integer): Boolean;
function SurfaceFullscreen(AHandle: Integer): Boolean;
/// <summary>The handles of all open surfaces.</summary>
function SurfaceHandles: TArray<Integer>;

/// <summary>Tells the plugin the size of the area its picture is shown in (pixels), as a
/// mouse event of kind 5; only when it differs from the last one told.</summary>
procedure SurfaceReportSize(AHandle, AWidth, AHeight: Integer);

/// <summary>Hands a mouse event to the plugin; True when it used it.</summary>
function SurfaceDeliverMouse(AHandle, AKind, AX, AY, AWidth, AHeight, AButton, AExtra,
  AShift: Integer): Boolean;

function SurfaceExists(AHandle: Integer): Boolean;
function SurfaceTitle(AHandle: Integer): string;
function SurfaceStatus(AHandle: Integer): string;

/// <summary>The current picture; APixels stays valid until the next frame. AGen
/// grows with every frame. False while the plugin has sent none.</summary>
function SurfaceFrame(AHandle: Integer; out AWidth, AHeight: Integer; out AGen: Cardinal;
  out APixels: PByte): Boolean;

/// <summary>The tab was drawn: keeps the timer running (it pauses once the tab
/// has not been drawn for a second).</summary>
procedure SurfaceSeen(AHandle: Integer);

/// <summary>Name of a key press for the plugin; '' for a key that has none.</summary>
function SurfaceKeyName(AKey: Word; AShift: TShiftState; AKeyChar: Char): string;

/// <summary>Hands a key press to the plugin; True when it used the key.</summary>
function SurfaceDeliverKey(AHandle: Integer; AKey: Word; AShift: TShiftState;
  AKeyChar: Char): Boolean;

implementation

uses
  System.Diagnostics, FMX.Types;

type
  TSurface = class
  public
    Handle: Integer;
    PluginId: string;
    Title, Status: string;
    OnKey: TSurfaceKeyCallback;
    OnTick: TProc;
    OnClosed: TProc;
    OnMouse: TSurfaceMouseCallback;
    Mode: Integer;
    Native: Boolean;
    NativeWindow: Int64;
    Fullscreen: Boolean;
    ReportedWidth, ReportedHeight: Integer;
    Repaint: TProc;
    Close: TProc;
    Pixels: TBytes;
    Width, Height: Integer;
    Gen: Cardinal;
    PluginClosing: Boolean;
    Timer: TTimer;
    LastSeen: Int64;
    procedure Ticked(Sender: TObject);
    destructor Destroy; override;
  end;

var
  GNativeCreate: TSurfaceNativeCreate;
  GNativeDestroy: TSurfaceNativeDestroy;
  GOpen: TSurfaceOpenHandler;
  GSurfaces: TObjectDictionary<Integer, TSurface>;
  GNextHandle: Integer = 0;
  GClock: TStopwatch;

function NowMs: Int64;
begin
  Result := GClock.ElapsedMilliseconds;
end;

function Find(AHandle: Integer): TSurface;
begin
  if not Assigned(GSurfaces) or not GSurfaces.TryGetValue(AHandle, Result) then
    Result := nil;
end;

{ TSurface }

destructor TSurface.Destroy;
begin
  FreeAndNil(Timer);
  inherited Destroy;
end;

procedure TSurface.Ticked(Sender: TObject);
begin
  if not Assigned(OnTick) or (NowMs - LastSeen > 1000) then
    Exit;
  try
    OnTick();
  except
    // A faulty plugin callback must not break the host's timer.
  end;
end;

procedure SetPluginSurfaceHost(const AOpen: TSurfaceOpenHandler);
begin
  GOpen := AOpen;
end;

procedure SetSurfaceNativeHooks(const ACreate: TSurfaceNativeCreate;
  const ADestroy: TSurfaceNativeDestroy);
begin
  GNativeCreate := ACreate;
  GNativeDestroy := ADestroy;
end;

function PluginSurfaceOpen(const APluginId, ATitle: string; const AOnKey: TSurfaceKeyCallback;
  const AOnTick, AOnClosed: TProc): Integer;
begin
  Result := PluginSurfaceOpenEx(APluginId, ATitle, cSurfaceModeTab, AOnKey, AOnTick, AOnClosed, nil);
end;

function PluginSurfaceOpenEx(const APluginId, ATitle: string; AMode: Integer;
  const AOnKey: TSurfaceKeyCallback; const AOnTick, AOnClosed: TProc;
  const AOnMouse: TSurfaceMouseCallback): Integer;
var
  S: TSurface;
  Native: Boolean;
begin
  Result := 0;
  Native := (AMode and cSurfaceNativeFlag) <> 0;
  AMode := AMode and not cSurfaceNativeFlag;
  if (Trim(APluginId) = '') or not Assigned(GOpen) or (AMode < 0) or (AMode > cSurfaceModePanel) then
    Exit;
  if Native and not Assigned(GNativeCreate) then
    Exit;
  Inc(GNextHandle);
  S := TSurface.Create;
  S.Handle := GNextHandle;
  S.PluginId := LowerCase(Trim(APluginId));
  S.Title := ATitle;
  S.OnKey := AOnKey;
  S.OnTick := AOnTick;
  S.OnClosed := AOnClosed;
  S.OnMouse := AOnMouse;
  S.Mode := AMode;
  S.Native := Native;
  S.Fullscreen := AMode = cSurfaceModeFullscreen;
  S.LastSeen := NowMs;
  GSurfaces.Add(S.Handle, S);
  try
    if GOpen(S.Handle) then
    begin
      if Native then
      begin
        S.NativeWindow := GNativeCreate(S.Handle);
        if S.NativeWindow = 0 then
        begin
          // No window to give: the tab goes again and the plugin is not told.
          S.PluginClosing := True;
          if Assigned(S.Close) then
            S.Close()
          else
            GSurfaces.Remove(S.Handle);
          Exit(0);
        end;
      end;
      Exit(S.Handle);
    end;
  except
    // fall through: the surface is dropped
  end;
  // The plugin is not told about a surface that never opened.
  GSurfaces.Remove(S.Handle);
end;

function PluginSurfaceSetFullscreen(AHandle: Integer; AOn: Boolean): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := (S <> nil) and (S.Mode <> cSurfaceModePanel);
  if not Result then
    Exit;
  S.Fullscreen := AOn;
  if Assigned(S.Repaint) then
    S.Repaint();
end;

function PluginSurfaceNativeHandle(AHandle: Integer): Int64;
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S = nil then
    Result := 0
  else
    Result := S.NativeWindow;
end;

function SurfaceMode(AHandle: Integer): Integer;
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S = nil then
    Result := cSurfaceModeTab
  else
    Result := S.Mode;
end;

function SurfaceIsNative(AHandle: Integer): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := (S <> nil) and S.Native;
end;

function SurfaceFullscreen(AHandle: Integer): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := (S <> nil) and S.Fullscreen;
end;

function SurfaceHandles: TArray<Integer>;
begin
  Result := GSurfaces.Keys.ToArray;
end;

procedure SurfaceReportSize(AHandle, AWidth, AHeight: Integer);
var
  S: TSurface;
begin
  S := Find(AHandle);
  if (S = nil) or ((S.ReportedWidth = AWidth) and (S.ReportedHeight = AHeight)) then
    Exit;
  S.ReportedWidth := AWidth;
  S.ReportedHeight := AHeight;
  SurfaceDeliverMouse(AHandle, 5, 0, 0, AWidth, AHeight, 0, 0, 0);
end;

function SurfaceDeliverMouse(AHandle, AKind, AX, AY, AWidth, AHeight, AButton, AExtra,
  AShift: Integer): Boolean;
var
  S: TSurface;
begin
  Result := False;
  S := Find(AHandle);
  if (S = nil) or not Assigned(S.OnMouse) then
    Exit;
  try
    Result := S.OnMouse(AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift);
  except
    Result := False;
  end;
end;

function PluginSurfaceSetFrame(AHandle, AWidth, AHeight: Integer; APixels: PByte;
  ALength: Int64): Boolean;
var
  S: TSurface;
  Size: Int64;
begin
  S := Find(AHandle);
  Result := False;
  if (S = nil) or (APixels = nil) or (AWidth <= 0) or (AHeight <= 0) or
     (AWidth > cSurfaceMaxSide) or (AHeight > cSurfaceMaxSide) then
    Exit;
  Size := Int64(AWidth) * AHeight * 4;
  if (Size <> ALength) or (Size > cSurfaceMaxBytes) then
    Exit;
  if Length(S.Pixels) <> Size then
    SetLength(S.Pixels, Size);
  Move(APixels^, S.Pixels[0], Size);
  S.Width := AWidth;
  S.Height := AHeight;
  Inc(S.Gen);
  if Assigned(S.Repaint) then
    S.Repaint();
  Result := True;
end;

function PluginSurfaceSetInfo(AHandle: Integer; const ATitle, AStatus: string): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := S <> nil;
  if not Result then
    Exit;
  S.Title := ATitle;
  S.Status := AStatus;
  if Assigned(S.Repaint) then
    S.Repaint();
end;

function PluginSurfaceSetTimer(AHandle, AIntervalMs: Integer): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := S <> nil;
  if not Result then
    Exit;
  if AIntervalMs <= 0 then
  begin
    FreeAndNil(S.Timer);
    Exit;
  end;
  if S.Timer = nil then
  begin
    S.Timer := TTimer.Create(nil);
    S.Timer.OnTimer := S.Ticked;
  end;
  S.Timer.Interval := AIntervalMs;
  S.Timer.Enabled := True;
end;

function PluginSurfaceClose(AHandle: Integer): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  Result := S <> nil;
  if not Result then
    Exit;
  S.PluginClosing := True;
  if Assigned(S.Close) then
    S.Close()
  else
    GSurfaces.Remove(AHandle);
end;

procedure PluginSurfaceUnregister(const APluginId: string);
var
  Key: string;
  Handles: TArray<Integer>;
  S: TSurface;
  H: Integer;
begin
  Key := LowerCase(Trim(APluginId));
  if (Key = '') or not Assigned(GSurfaces) then
    Exit;
  Handles := [];
  for S in GSurfaces.Values do
    if S.PluginId = Key then
    begin
      // Nothing of the plugin may run any more.
      S.OnKey := nil;
      S.OnTick := nil;
      S.OnClosed := nil;
      S.OnMouse := nil;
      Handles := Handles + [S.Handle];
    end;
  for H in Handles do
    PluginSurfaceClose(H);
end;

procedure SurfaceAttach(AHandle: Integer; const ARepaint, AClose: TProc);
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S = nil then
    Exit;
  S.Repaint := ARepaint;
  S.Close := AClose;
end;

procedure SurfaceTabClosed(AHandle: Integer);
var
  S: TSurface;
  Notify: TProc;
begin
  S := Find(AHandle);
  if S = nil then
    Exit;
  Notify := nil;
  if not S.PluginClosing then
    Notify := S.OnClosed;
  if (S.NativeWindow <> 0) and Assigned(GNativeDestroy) then
    try
      GNativeDestroy(AHandle, S.NativeWindow);
    except
      // The window is gone or never came up; nothing to do about it.
    end;
  S.NativeWindow := 0;
  S.Repaint := nil;
  S.Close := nil;
  S.OnClosed := nil;
  S.OnTick := nil;
  S.OnKey := nil;
  S.OnMouse := nil;
  GSurfaces.Remove(AHandle);
  if Assigned(Notify) then
    try
      Notify();
    except
      // A faulty plugin callback must not break closing the tab.
    end;
end;

function SurfaceExists(AHandle: Integer): Boolean;
begin
  Result := Find(AHandle) <> nil;
end;

function SurfaceTitle(AHandle: Integer): string;
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S = nil then
    Result := ''
  else
    Result := S.Title;
end;

function SurfaceStatus(AHandle: Integer): string;
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S = nil then
    Result := ''
  else
    Result := S.Status;
end;

function SurfaceFrame(AHandle: Integer; out AWidth, AHeight: Integer; out AGen: Cardinal;
  out APixels: PByte): Boolean;
var
  S: TSurface;
begin
  S := Find(AHandle);
  AWidth := 0;
  AHeight := 0;
  AGen := 0;
  APixels := nil;
  Result := (S <> nil) and (S.Gen > 0);
  if not Result then
    Exit;
  AWidth := S.Width;
  AHeight := S.Height;
  AGen := S.Gen;
  APixels := @S.Pixels[0];
end;

procedure SurfaceSeen(AHandle: Integer);
var
  S: TSurface;
begin
  S := Find(AHandle);
  if S <> nil then
    S.LastSeen := NowMs;
end;

function SurfaceKeyName(AKey: Word; AShift: TShiftState; AKeyChar: Char): string;
var
  Base, Prefix: string;
begin
  Base := '';
  case AKey of
    vkLeft: Base := 'Left';
    vkRight: Base := 'Right';
    vkUp: Base := 'Up';
    vkDown: Base := 'Down';
    vkHome: Base := 'Home';
    vkEnd: Base := 'End';
    vkPrior: Base := 'PageUp';
    vkNext: Base := 'PageDown';
    vkReturn: Base := 'Enter';
    vkSpace: Base := 'Space';
    vkTab: Base := 'Tab';
    vkBack: Base := 'Backspace';
    vkDelete: Base := 'Delete';
    vkInsert: Base := 'Insert';
  end;
  if (Base = '') and (AKey >= vkF1) and (AKey <= vkF12) then
    Base := 'F' + IntToStr(AKey - vkF1 + 1);
  if (Base = '') and (AKeyChar = ' ') then
    Base := 'Space';
  if (Base = '') and (AKeyChar > ' ') and not (ssCtrl in AShift) and not (ssAlt in AShift) then
    Exit(AKeyChar);
  if (Base = '') and (((AKey >= Ord('A')) and (AKey <= Ord('Z'))) or
     ((AKey >= Ord('0')) and (AKey <= Ord('9')))) and ((ssCtrl in AShift) or (ssAlt in AShift)) then
    Base := Chr(AKey);
  if Base = '' then
    Exit('');
  Prefix := '';
  if ssCtrl in AShift then
    Prefix := Prefix + 'Ctrl+';
  if ssAlt in AShift then
    Prefix := Prefix + 'Alt+';
  if ssShift in AShift then
    Prefix := Prefix + 'Shift+';
  Result := Prefix + Base;
end;

function SurfaceDeliverKey(AHandle: Integer; AKey: Word; AShift: TShiftState;
  AKeyChar: Char): Boolean;
var
  S: TSurface;
  Name: string;
begin
  Result := False;
  S := Find(AHandle);
  if (S = nil) or not Assigned(S.OnKey) then
    Exit;
  Name := SurfaceKeyName(AKey, AShift, AKeyChar);
  if Name = '' then
    Exit;
  try
    Result := S.OnKey(Name);
  except
    Result := False;
  end;
end;

initialization
  GSurfaces := TObjectDictionary<Integer, TSurface>.Create([doOwnsValues]);
  GClock := TStopwatch.StartNew;

finalization
  GNativeCreate := nil;
  GNativeDestroy := nil;
  GOpen := nil;
  FreeAndNil(GSurfaces);

end.
