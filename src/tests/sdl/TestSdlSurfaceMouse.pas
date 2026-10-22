unit TestSdlSurfaceMouse;

{ Mouse input of a plugin's picture tab in the SDL window: a press inside the
  area goes to the plugin in pixels of the area, the moves and the release
  follow it, a press the plugin does not use goes on to the panels, the wheel
  works over the area, and the plugin hears the size of its area. The tab and
  the area are stand-ins; the surface registry is the real one. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSdlSurfaceMouse = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PressMoveAndReleaseGoToThePlugin;
    [Test] procedure PressOutsideTheAreaIsLeftToThePanels;
    [Test] procedure PressThePluginDoesNotUseIsLeftToThePanels;
    [Test] procedure WheelOverTheAreaGoesToThePlugin;
    [Test] procedure PositionsFollowTheWindowScale;
    [Test] procedure PluginHearsTheSizeOfItsAreaOnce;
    [Test] procedure ButtonsAndModifiersUseThePluginNumbering;
  end;

implementation

uses
  System.SysUtils, System.Types, uSdlApi, uSdlSurfaceMouse, uPluginSurface;

type
  TCall = record
    Kind, X, Y, W, H, Button, Extra, Shift: Integer;
  end;

var
  GCalls: TArray<TCall>;
  GUse: Boolean;
  GHandle: Integer;
  GArea: TRect;

function MouseEvent(AType: Cardinal; AButton: Byte; AX, AY: Integer; AClicks: Byte = 1): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, AType);
  SdlEventSetU8(Result, 16, AButton);
  SdlEventSetU8(Result, 18, AClicks);
  SdlEventSetU32(Result, 20, Cardinal(AX));
  SdlEventSetU32(Result, 24, Cardinal(AY));
end;

function WheelEvent(AClicks: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_MOUSEWHEEL);
  SdlEventSetU32(Result, 20, Cardinal(AClicks));
end;

function NewMouse: TSdlSurfaceMouse;
begin
  Result := TSdlSurfaceMouse.Create(
    function: TArray<Integer>
    begin
      Result := TArray<Integer>.Create(GHandle);
    end,
    function(AHandle: Integer; out AArea: TRect): Boolean
    begin
      AArea := GArea;
      Result := AHandle = GHandle;
    end);
end;

procedure TTestSdlSurfaceMouse.Setup;
begin
  GCalls := nil;
  GUse := True;
  GArea := TRect.Create(100, 50, 300, 150);
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      SurfaceAttach(AHandle, procedure begin end, procedure begin SurfaceTabClosed(AHandle); end);
      Result := True;
    end);
  GHandle := PluginSurfaceOpenEx('t.mouse', 'Pic', cSurfaceModeTab, nil, nil, nil,
    function(AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift: Integer): Boolean
    var
      C: TCall;
    begin
      C.Kind := AKind;
      C.X := AX;
      C.Y := AY;
      C.W := AWidth;
      C.H := AHeight;
      C.Button := AButton;
      C.Extra := AExtra;
      C.Shift := AShift;
      GCalls := GCalls + [C];
      Result := GUse;
    end);
end;

procedure TTestSdlSurfaceMouse.TearDown;
begin
  PluginSurfaceUnregister('t.mouse');
  SetPluginSurfaceHost(nil);
end;

procedure TTestSdlSurfaceMouse.PressMoveAndReleaseGoToThePlugin;
var
  M: TSdlSurfaceMouse;
begin
  Assert.IsTrue(GHandle > 0, 'the tab is open');
  M := NewMouse;
  try
    Assert.IsTrue(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 110, 70), 0), 'press taken');
    Assert.AreEqual(1, Integer(Length(GCalls)));
    Assert.AreEqual(0, GCalls[0].Kind, 'button down');
    Assert.AreEqual(10, GCalls[0].X, 'x from the left of the area');
    Assert.AreEqual(20, GCalls[0].Y, 'y from the top of the area');
    Assert.AreEqual(200, GCalls[0].W);
    Assert.AreEqual(100, GCalls[0].H);
    Assert.AreEqual(1, GCalls[0].Button, 'left');
    // A drag goes on outside the area.
    Assert.IsTrue(M.Handle(MouseEvent(SDL_MOUSEMOTION, 0, 20, 400), 0), 'move taken while held');
    Assert.AreEqual(2, GCalls[1].Kind, 'move');
    Assert.AreEqual(-80, GCalls[1].X);
    Assert.IsTrue(M.Handle(MouseEvent(SDL_MOUSEBUTTONUP, SDL_BUTTON_LEFT, 20, 400), 0), 'release taken');
    Assert.AreEqual(1, GCalls[2].Kind, 'button up');
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEMOTION, 0, 120, 80), 0), 'moves after the release are the panels''');
    Assert.AreEqual(3, Integer(Length(GCalls)));
    Assert.IsTrue(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 120, 80, 2), 0));
    Assert.AreEqual(4, GCalls[3].Kind, 'a double click');
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.PressOutsideTheAreaIsLeftToThePanels;
var
  M: TSdlSurfaceMouse;
begin
  M := NewMouse;
  try
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 10, 10), 0));
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 300, 100), 0),
      'the right edge belongs to the next cell');
    Assert.AreEqual(0, Integer(Length(GCalls)), 'the plugin heard nothing');
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEBUTTONUP, SDL_BUTTON_LEFT, 10, 10), 0),
      'a release without a taken press is the panels''');
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.PressThePluginDoesNotUseIsLeftToThePanels;
var
  M: TSdlSurfaceMouse;
begin
  GUse := False;
  M := NewMouse;
  try
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 150, 100), 0));
    Assert.AreEqual(1, Integer(Length(GCalls)), 'the plugin was asked');
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEMOTION, 0, 160, 100), 0), 'no drag was started');
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEBUTTONUP, SDL_BUTTON_LEFT, 160, 100), 0));
    Assert.AreEqual(1, Integer(Length(GCalls)));
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.WheelOverTheAreaGoesToThePlugin;
var
  M: TSdlSurfaceMouse;
begin
  M := NewMouse;
  try
    // The wheel has no position: the last one seen is used.
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEMOTION, 0, 400, 400), 0), 'a move outside');
    Assert.IsFalse(M.Handle(WheelEvent(1), 0), 'the wheel outside the area');
    Assert.IsFalse(M.Handle(MouseEvent(SDL_MOUSEMOTION, 0, 150, 100), 0), 'a move inside, no button');
    Assert.IsTrue(M.Handle(WheelEvent(-3), 0), 'the wheel inside');
    Assert.AreEqual(1, Integer(Length(GCalls)));
    Assert.AreEqual(3, GCalls[0].Kind, 'wheel');
    Assert.AreEqual(-1, GCalls[0].Extra, 'one step toward the user');
    Assert.AreEqual(50, GCalls[0].X);
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.PositionsFollowTheWindowScale;
var
  M: TSdlSurfaceMouse;
begin
  M := NewMouse;
  try
    M.Scale := 2;
    // 60 x 40 window units are 120 x 80 bitmap pixels.
    Assert.IsTrue(M.Handle(MouseEvent(SDL_MOUSEBUTTONDOWN, SDL_BUTTON_LEFT, 60, 40), 0));
    Assert.AreEqual(20, GCalls[0].X);
    Assert.AreEqual(30, GCalls[0].Y);
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.PluginHearsTheSizeOfItsAreaOnce;
var
  M: TSdlSurfaceMouse;
begin
  M := NewMouse;
  try
    M.ReportSizes;
    M.ReportSizes;
    Assert.AreEqual(1, Integer(Length(GCalls)), 'the same size is told once');
    Assert.AreEqual(5, GCalls[0].Kind, 'as a size change');
    Assert.AreEqual(200, GCalls[0].W);
    Assert.AreEqual(100, GCalls[0].H);
    GArea := TRect.Create(0, 0, 80, 40);
    M.ReportSizes;
    Assert.AreEqual(2, Integer(Length(GCalls)));
    Assert.AreEqual(80, GCalls[1].W, 'a new size is told again');
  finally
    M.Free;
  end;
end;

procedure TTestSdlSurfaceMouse.ButtonsAndModifiersUseThePluginNumbering;
begin
  Assert.AreEqual(1, SdlButtonToSurface(SDL_BUTTON_LEFT));
  Assert.AreEqual(2, SdlButtonToSurface(SDL_BUTTON_RIGHT), 'right is 2 for plugins');
  Assert.AreEqual(3, SdlButtonToSurface(SDL_BUTTON_MIDDLE), 'middle is 3 for plugins');
  Assert.AreEqual(0, SdlModsToSurfaceBits(0));
  Assert.AreEqual(1 or 2 or 4, SdlModsToSurfaceBits(KMOD_LSHIFT or KMOD_RCTRL or KMOD_LALT));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSdlSurfaceMouse);

end.
