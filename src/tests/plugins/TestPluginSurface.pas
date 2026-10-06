unit TestPluginSurface;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginSurface = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestNoHostOpensNothing;
    [Test] procedure TestFrameIsCopiedAndChecked;
    [Test] procedure TestTitleAndStatusReachTheTab;
    [Test] procedure TestKeysAreNamedForThePlugin;
    [Test] procedure TestKeyReachesThePluginOnce;
    [Test] procedure TestUserClosingTheTabTellsThePlugin;
    [Test] procedure TestPluginClosingTheTabIsNotTold;
    [Test] procedure TestUnloadedPluginIsNotCalledAgain;
    [Test] procedure TestRefusedTabLeavesNoSurface;
    [Test] procedure TestModesAreChecked;
    [Test] procedure TestFullscreenBelongsToTabs;
    [Test] procedure TestMouseReachesThePlugin;
    [Test] procedure TestAreaSizeIsToldOnlyWhenItChanges;
    [Test] procedure TestNativeSurfaceNeedsTheHooks;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uPluginSurface;

var
  GOpened: Integer;
  GLastHandle: Integer;
  GRepaints: Integer;
  GTabClosedByPlugin: Integer;

procedure InstallHost(AAccept: Boolean);
begin
  GOpened := 0;
  GLastHandle := 0;
  GRepaints := 0;
  GTabClosedByPlugin := 0;
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      Inc(GOpened);
      GLastHandle := AHandle;
      Result := AAccept;
      if AAccept then
        SurfaceAttach(AHandle,
          procedure
          begin
            Inc(GRepaints);
          end,
          procedure
          begin
            Inc(GTabClosedByPlugin);
            SurfaceTabClosed(AHandle);
          end);
    end);
end;

procedure TTestPluginSurface.TearDown;
begin
  SetPluginSurfaceHost(nil);
end;

procedure TTestPluginSurface.TestNoHostOpensNothing;
begin
  SetPluginSurfaceHost(nil);
  Assert.AreEqual(0, PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil), 'no window, no surface');
end;

procedure TTestPluginSurface.TestFrameIsCopiedAndChecked;
var
  H, W, Hgt: Integer;
  Gen: Cardinal;
  Pixels: PByte;
  Data: TBytes;
begin
  InstallHost(True);
  H := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  Assert.IsTrue(H > 0, 'opened');
  Assert.IsFalse(SurfaceFrame(H, W, Hgt, Gen, Pixels), 'no frame yet');
  Data := [1, 2, 3, 255, 4, 5, 6, 255];
  Assert.IsTrue(PluginSurfaceSetFrame(H, 2, 1, @Data[0], 8), 'a 2x1 frame');
  Data[0] := 99;
  Assert.IsTrue(SurfaceFrame(H, W, Hgt, Gen, Pixels), 'the frame is there');
  Assert.AreEqual(2, W, 'width');
  Assert.AreEqual(1, Hgt, 'height');
  Assert.AreEqual(1, Integer(Pixels^), 'the pixels were copied, not referenced');
  Assert.AreEqual(1, GRepaints, 'the tab repaints');
  Assert.IsFalse(PluginSurfaceSetFrame(H, 2, 1, @Data[0], 7), 'short data is refused');
  Assert.IsFalse(PluginSurfaceSetFrame(H, 0, 1, @Data[0], 0), 'an empty picture is refused');
  Assert.IsFalse(PluginSurfaceSetFrame(H, 20000, 1, @Data[0], 80000), 'a huge side is refused');
  Assert.IsFalse(PluginSurfaceSetFrame(H + 100, 2, 1, @Data[0], 8), 'unknown handle');
  PluginSurfaceSetFrame(H, 2, 1, @Data[0], 8);
  Assert.IsTrue(SurfaceFrame(H, W, Hgt, Gen, Pixels) and (Gen = 2), 'every frame bumps the generation');
  SurfaceTabClosed(H);
end;

procedure TTestPluginSurface.TestTitleAndStatusReachTheTab;
var
  H: Integer;
begin
  InstallHost(True);
  H := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  Assert.IsTrue(PluginSurfaceSetInfo(H, 'a.png', '10x20  1/3'), 'info set');
  Assert.AreEqual('a.png', SurfaceTitle(H));
  Assert.AreEqual('10x20  1/3', SurfaceStatus(H));
  Assert.AreEqual(1, GRepaints, 'the tab repaints');
  SurfaceTabClosed(H);
end;

procedure TTestPluginSurface.TestKeysAreNamedForThePlugin;
begin
  Assert.AreEqual('Left', SurfaceKeyName(vkLeft, [], #0));
  Assert.AreEqual('Space', SurfaceKeyName(vkSpace, [], ' '));
  Assert.AreEqual('PageDown', SurfaceKeyName(vkNext, [], #0));
  Assert.AreEqual('F5', SurfaceKeyName(vkF5, [], #0));
  Assert.AreEqual('+', SurfaceKeyName(0, [ssShift], '+'));
  Assert.AreEqual('a', SurfaceKeyName(Ord('A'), [], 'a'));
  Assert.AreEqual('Ctrl+C', SurfaceKeyName(Ord('C'), [ssCtrl], #3));
  Assert.AreEqual('Ctrl+Shift+Left', SurfaceKeyName(vkLeft, [ssShift, ssCtrl], #0));
  Assert.AreEqual('', SurfaceKeyName(vkShift, [ssShift], #0), 'a bare modifier has no name');
end;

procedure TTestPluginSurface.TestKeyReachesThePluginOnce;
var
  H, Calls: Integer;
  Last: string;
begin
  InstallHost(True);
  Calls := 0;
  H := PluginSurfaceOpen('t.surface', 'Pic',
    function(const AKey: string): Boolean
    begin
      Inc(Calls);
      Last := AKey;
      Result := AKey = 'Right';
    end, nil, nil);
  Assert.IsTrue(SurfaceDeliverKey(H, vkRight, [], #0), 'used');
  Assert.IsFalse(SurfaceDeliverKey(H, vkLeft, [], #0), 'not used');
  Assert.IsFalse(SurfaceDeliverKey(H, vkShift, [ssShift], #0), 'a nameless key is not passed on');
  Assert.AreEqual(2, Calls);
  Assert.AreEqual('Left', Last);
  SurfaceTabClosed(H);
end;

procedure TTestPluginSurface.TestUserClosingTheTabTellsThePlugin;
var
  H, Told: Integer;
begin
  InstallHost(True);
  Told := 0;
  H := PluginSurfaceOpen('t.surface', 'Pic', nil, nil,
    procedure
    begin
      Inc(Told);
    end);
  SurfaceTabClosed(H);
  SurfaceTabClosed(H);
  Assert.AreEqual(1, Told, 'told once');
  Assert.IsFalse(SurfaceExists(H), 'the surface is gone');
  Assert.IsFalse(PluginSurfaceSetInfo(H, 'x', 'y'), 'a gone surface takes nothing');
end;

procedure TTestPluginSurface.TestPluginClosingTheTabIsNotTold;
var
  H, Told: Integer;
begin
  InstallHost(True);
  Told := 0;
  H := PluginSurfaceOpen('t.surface', 'Pic', nil, nil,
    procedure
    begin
      Inc(Told);
    end);
  Assert.IsTrue(PluginSurfaceClose(H), 'closed');
  Assert.AreEqual(1, GTabClosedByPlugin, 'the tab was asked to close');
  Assert.AreEqual(0, Told, 'the plugin knows it closed the tab');
  Assert.IsFalse(SurfaceExists(H), 'the surface is gone');
  Assert.IsFalse(PluginSurfaceClose(H), 'closing twice is refused');
end;

procedure TTestPluginSurface.TestUnloadedPluginIsNotCalledAgain;
var
  H1, H2, Calls: Integer;
begin
  InstallHost(True);
  Calls := 0;
  H1 := PluginSurfaceOpen('t.surface', 'A',
    function(const AKey: string): Boolean
    begin
      Inc(Calls);
      Result := True;
    end, nil,
    procedure
    begin
      Inc(Calls);
    end);
  H2 := PluginSurfaceOpen('t.other', 'B', nil, nil, nil);
  PluginSurfaceUnregister('T.Surface');
  Assert.IsFalse(SurfaceExists(H1), 'its tab is closed');
  Assert.IsTrue(SurfaceExists(H2), 'another plugin keeps its tab');
  Assert.AreEqual(0, Calls, 'no callback of the unloaded plugin runs');
  SurfaceTabClosed(H2);
end;

procedure TTestPluginSurface.TestModesAreChecked;
var
  H: Integer;
begin
  InstallHost(True);
  H := PluginSurfaceOpenEx('t.surface', 'A', cSurfaceModePanel, nil, nil, nil, nil);
  Assert.IsTrue(H > 0, 'panel mode');
  Assert.AreEqual(cSurfaceModePanel, SurfaceMode(H), 'the mode is kept');
  SurfaceTabClosed(H);
  Assert.AreEqual(0, PluginSurfaceOpenEx('t.surface', 'B', 3, nil, nil, nil, nil), 'an unknown mode');
  Assert.AreEqual(0, PluginSurfaceOpenEx('t.surface', 'B', -1, nil, nil, nil, nil), 'a negative mode');
  H := PluginSurfaceOpenEx('t.surface', 'C', cSurfaceModeFullscreen, nil, nil, nil, nil);
  Assert.IsTrue(SurfaceFullscreen(H), 'opened full screen');
  SurfaceTabClosed(H);
end;

procedure TTestPluginSurface.TestFullscreenBelongsToTabs;
var
  Tab, PanelSurface: Integer;
begin
  InstallHost(True);
  Tab := PluginSurfaceOpenEx('t.surface', 'T', cSurfaceModeTab, nil, nil, nil, nil);
  Assert.IsFalse(SurfaceFullscreen(Tab), 'a tab starts normal');
  Assert.IsTrue(PluginSurfaceSetFullscreen(Tab, True) and SurfaceFullscreen(Tab), 'switched on');
  Assert.AreEqual(1, GRepaints, 'the tab repaints');
  Assert.IsTrue(PluginSurfaceSetFullscreen(Tab, False) and not SurfaceFullscreen(Tab), 'and off');
  PanelSurface := PluginSurfaceOpenEx('t.surface', 'P', cSurfaceModePanel, nil, nil, nil, nil);
  Assert.IsFalse(PluginSurfaceSetFullscreen(PanelSurface, True), 'the panel cannot go full screen');
  Assert.IsFalse(PluginSurfaceSetFullscreen(Tab + 100, True), 'unknown handle');
  SurfaceTabClosed(Tab);
  SurfaceTabClosed(PanelSurface);
end;

procedure TTestPluginSurface.TestMouseReachesThePlugin;
var
  H, Kind, X, W, Btn, Extra, Shift: Integer;
begin
  InstallHost(True);
  H := PluginSurfaceOpenEx('t.surface', 'M', cSurfaceModeTab, nil, nil, nil,
    function(AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift: Integer): Boolean
    begin
      Kind := AKind;
      X := AX;
      W := AWidth;
      Btn := AButton;
      Extra := AExtra;
      Shift := AShift;
      Result := AKind = 3;
    end);
  Assert.IsTrue(SurfaceDeliverMouse(H, 3, 10, 20, 800, 600, 3, -2, 2), 'a wheel event the plugin used');
  Assert.AreEqual(3, Kind);
  Assert.AreEqual(10, X);
  Assert.AreEqual(800, W);
  Assert.AreEqual(3, Btn);
  Assert.AreEqual(-2, Extra);
  Assert.AreEqual(2, Shift);
  Assert.IsFalse(SurfaceDeliverMouse(H, 0, 1, 1, 800, 600, 1, 0, 0), 'a click it did not');
  Assert.IsFalse(SurfaceDeliverMouse(H + 100, 0, 1, 1, 800, 600, 1, 0, 0), 'unknown handle');
  SurfaceTabClosed(H);
  Assert.IsFalse(SurfaceDeliverMouse(H, 3, 1, 1, 800, 600, 1, 0, 0), 'nothing after the tab closed');
end;

procedure TTestPluginSurface.TestAreaSizeIsToldOnlyWhenItChanges;
var
  H, Told, LastW, LastH: Integer;
begin
  InstallHost(True);
  Told := 0;
  H := PluginSurfaceOpenEx('t.surface', 'S', cSurfaceModeTab, nil, nil, nil,
    function(AKind, AX, AY, AWidth, AHeight, AButton, AExtra, AShift: Integer): Boolean
    begin
      if AKind = 5 then
      begin
        Inc(Told);
        LastW := AWidth;
        LastH := AHeight;
      end;
      Result := True;
    end);
  SurfaceReportSize(H, 800, 600);
  SurfaceReportSize(H, 800, 600);
  Assert.AreEqual(1, Told, 'the same size is told once');
  Assert.IsTrue((LastW = 800) and (LastH = 600), 'with the size');
  SurfaceReportSize(H, 640, 600);
  Assert.AreEqual(2, Told, 'a new size is told');
  SurfaceTabClosed(H);
end;

procedure TTestPluginSurface.TestNativeSurfaceNeedsTheHooks;
var
  H, Destroyed: Integer;
  Created: Integer;
begin
  InstallHost(True);
  SetSurfaceNativeHooks(nil, nil);
  Assert.AreEqual(0, PluginSurfaceOpenEx('t.surface', 'N', cSurfaceNativeFlag, nil, nil, nil, nil),
    'without a way to make windows a native surface is refused');
  Assert.AreEqual(0, GOpened, 'and no tab is opened for it');
  Created := 0;
  Destroyed := 0;
  SetSurfaceNativeHooks(
    function(AHandle: Integer): Int64
    begin
      Inc(Created);
      Result := 12345;
    end,
    procedure(AHandle: Integer; AWindow: Int64)
    begin
      Inc(Destroyed);
      Assert.AreEqual(Int64(12345), AWindow, 'the window that was made is the one dropped');
    end);
  try
    H := PluginSurfaceOpenEx('t.surface', 'N', cSurfaceNativeFlag, nil, nil, nil, nil);
    Assert.IsTrue(H > 0, 'opened');
    Assert.IsTrue(SurfaceIsNative(H), 'native');
    Assert.AreEqual(Int64(12345), PluginSurfaceNativeHandle(H), 'the plugin gets the window');
    Assert.AreEqual(1, Created);
    SurfaceTabClosed(H);
    Assert.AreEqual(1, Destroyed, 'closing the tab drops the window');
    Assert.AreEqual(Int64(0), PluginSurfaceNativeHandle(H), 'and the handle is gone');
    H := PluginSurfaceOpenEx('t.surface', 'D', cSurfaceModeTab, nil, nil, nil, nil);
    Assert.AreEqual(Int64(0), PluginSurfaceNativeHandle(H), 'a drawn surface has no window');
    SurfaceTabClosed(H);
  finally
    SetSurfaceNativeHooks(nil, nil);
  end;
end;

procedure TTestPluginSurface.TestRefusedTabLeavesNoSurface;
begin
  InstallHost(False);
  Assert.AreEqual(0, PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil), 'the host said no');
  Assert.AreEqual(1, GOpened, 'the host was asked');
  Assert.IsFalse(SurfaceExists(GLastHandle), 'nothing is left behind');
end;

end.
