unit uNativeSurface;

{ Native window for a plugin surface (Windows). The program creates a plain child
  window of its main window and keeps it over the cells the surface covers; the plugin
  draws in it, or hands it to a player as the output window. The windows inside it are
  resized to fill it, so a player's own window follows the area. A click in it never
  takes the keyboard focus from the program: keys reach the plugin through the surface
  key callback like for a drawn surface. }

interface

uses
  Winapi.Windows, Winapi.Messages;

/// <summary>A hidden child window of AParent; 0 when it cannot be made.</summary>
function NativeSurfaceCreate(AParent: HWND): HWND;
/// <summary>Puts the window over a rectangle (pixels of the parent's client area); an
/// invisible one is hidden (a dialog or the menu covers its place, another tab is on screen).</summary>
procedure NativeSurfaceMove(AWindow: HWND; ALeft, ATop, AWidth, AHeight: Integer;
  AVisible: Boolean);
procedure NativeSurfaceDestroy(AWindow: HWND);
/// <summary>Hides the window and takes it off its parent so that the parent can be
/// destroyed without taking it along.</summary>
procedure NativeSurfaceDetach(AWindow: HWND);
/// <summary>Makes the window a child of AParent again (a new window handle of the program's
/// main window); it stays hidden until NativeSurfaceMove shows it.</summary>
procedure NativeSurfaceAttach(AWindow, AParent: HWND);

implementation

const
  cClassName = 'MtnPluginSurface';

var
  GClassRegistered: Boolean;

procedure FitChildren(AWindow: HWND);
var
  Rect: TRect;
  Child: HWND;
begin
  GetClientRect(AWindow, Rect);
  Child := GetWindow(AWindow, GW_CHILD);
  while Child <> 0 do
  begin
    SetWindowPos(Child, 0, 0, 0, Rect.Right, Rect.Bottom, SWP_NOZORDER or SWP_NOACTIVATE);
    Child := GetWindow(Child, GW_HWNDNEXT);
  end;
end;

function SurfaceProc(AWindow: HWND; AMessage: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  Rect: TRect;
begin
  case AMessage of
    WM_ERASEBKGND:
      begin
        GetClientRect(AWindow, Rect);
        FillRect(HDC(AWParam), Rect, GetStockObject(BLACK_BRUSH));
        Exit(1);
      end;
    WM_SIZE:
      FitChildren(AWindow);
    WM_MOUSEACTIVATE:
      Exit(MA_NOACTIVATE);
  end;
  Result := DefWindowProc(AWindow, AMessage, AWParam, ALParam);
end;

function NativeSurfaceCreate(AParent: HWND): HWND;
var
  WC: TWndClass;
begin
  Result := 0;
  if AParent = 0 then
    Exit;
  if not GClassRegistered then
  begin
    FillChar(WC, SizeOf(WC), 0);
    WC.lpfnWndProc := @SurfaceProc;
    WC.hInstance := HInstance;
    WC.hCursor := LoadCursor(0, IDC_ARROW);
    WC.lpszClassName := cClassName;
    GClassRegistered := RegisterClass(WC) <> 0;
    if not GClassRegistered then
      Exit;
  end;
  Result := CreateWindowEx(0, cClassName, '', WS_CHILD or WS_CLIPCHILDREN or WS_CLIPSIBLINGS,
    0, 0, 1, 1, AParent, 0, HInstance, nil);
end;

procedure NativeSurfaceMove(AWindow: HWND; ALeft, ATop, AWidth, AHeight: Integer;
  AVisible: Boolean);
begin
  if (AWindow = 0) or not IsWindow(AWindow) then
    Exit;
  if not AVisible or (AWidth < 1) or (AHeight < 1) then
  begin
    if IsWindowVisible(AWindow) then
      ShowWindow(AWindow, SW_HIDE);
    Exit;
  end;
  SetWindowPos(AWindow, HWND_TOP, ALeft, ATop, AWidth, AHeight, SWP_NOACTIVATE or SWP_SHOWWINDOW);
end;

procedure NativeSurfaceDestroy(AWindow: HWND);
begin
  if (AWindow <> 0) and IsWindow(AWindow) then
    DestroyWindow(AWindow);
end;

procedure NativeSurfaceDetach(AWindow: HWND);
begin
  if (AWindow = 0) or not IsWindow(AWindow) then
    Exit;
  ShowWindow(AWindow, SW_HIDE);
  SetParent(AWindow, 0);
end;

procedure NativeSurfaceAttach(AWindow, AParent: HWND);
begin
  if (AWindow = 0) or (AParent = 0) or not IsWindow(AWindow) then
    Exit;
  SetParent(AWindow, AParent);
end;

end.
