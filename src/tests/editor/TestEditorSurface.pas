unit TestEditorSurface;

{ The viewer tab of a plugin picture (uPluginSurface): the frame goes to the
  Media Overlay over the viewport, the title and status line come from the
  plugin, Esc closes the tab and any other key is the plugin's. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorSurface = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestWaitsForTheFirstFrame;
    [Test] procedure TestFrameGoesToTheOverlay;
    [Test] procedure TestTitleAndStatusLine;
    [Test] procedure TestEscClosesAndOtherKeysGoToThePlugin;
    [Test] procedure TestPluginClosingTheSurfaceClosesTheTab;
    [Test] procedure TestDestroyingTheTabTellsThePlugin;
    [Test] procedure TestFullscreenCoversTheWholeWindow;
    [Test] procedure TestEscLeavesFullscreenBeforeClosing;
    [Test] procedure TestPluginCanTakeEscAndF10;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  uTerminalTypes, uThemeTypes, uThemeRegistry, uEditorWindow, uOverlayRenderer, uPluginSurface;

const
  W = 60;
  H = 14;

var
  GView: TEditorWindow;
  GCloseRequests: Integer;

type
  TCloseCounter = class
    procedure Closed(Sender: TObject);
  end;

procedure TCloseCounter.Closed(Sender: TObject);
begin
  Inc(GCloseRequests);
end;

var
  GCounter: TCloseCounter;

procedure InstallHost;
begin
  GView := nil;
  GCloseRequests := 0;
  SetPluginSurfaceHost(
    function(AHandle: Integer): Boolean
    begin
      GView := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
      GView.Embedded := True;
      GView.OnCloseRequest := GCounter.Closed;
      GView.OpenSurface(AHandle);
      Result := True;
    end);
end;

function Paint(AView: TEditorWindow): TTerminalGrid;
var
  Y: Integer;
begin
  SetLength(Result, H);
  for Y := 0 to High(Result) do
    SetLength(Result[Y], W);
  AView.PaintEmbedded(Result, 0, 0, W, H, 0, 0);
end;

function AllText(const AGrid: TTerminalGrid): string;
var
  X, Y: Integer;
begin
  Result := '';
  for Y := 0 to High(AGrid) do
  begin
    for X := 0 to High(AGrid[Y]) do
      Result := Result + AGrid[Y][X].CharValue;
    Result := Result + #10;
  end;
end;

procedure SendKey(AView: TEditorWindow; AKey: Word; AChar: Char);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := AChar;
  AView.HandleInput(K, [], Ch);
end;

procedure SendRed(AHandle: Integer);
var
  Px: TBytes;
begin
  Px := [0, 0, 255, 255, 0, 0, 255, 255];
  Assert.IsTrue(PluginSurfaceSetFrame(AHandle, 2, 1, @Px[0], 8), 'frame accepted');
end;

procedure TTestEditorSurface.TearDown;
begin
  SetPluginSurfaceHost(nil);
  ClearOverlayPreview;
  FreeAndNil(GView);
end;

procedure TTestEditorSurface.TestWaitsForTheFirstFrame;
var
  Handle: Integer;
  Text: string;
begin
  InstallHost;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  Assert.IsTrue(Handle > 0, 'opened');
  Text := AllText(Paint(GView));
  Assert.IsTrue(Pos('Loading...', Text) > 0, 'a wait note shows before the first frame');
  Assert.IsTrue(Pos('Esc', Text) > 0, 'the function bar offers Esc');
  Assert.IsFalse(GView.MarkdownImageOverlayVisible and OverlayActive, 'nothing to draw yet');
end;

procedure TTestEditorSurface.TestFrameGoesToTheOverlay;
var
  Handle: Integer;
begin
  InstallHost;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  SendRed(Handle);
  Paint(GView);
  Assert.IsTrue(OverlayActive, 'the overlay holds the picture');
  Assert.AreEqual('plugin-surface:' + IntToStr(Handle), OverlayCurrentURI);
  Assert.IsTrue(GView.MarkdownImageOverlayVisible, 'the host paints the overlay for this tab');
  SendRed(Handle);
  Paint(GView);
  Assert.IsTrue(OverlayActive, 'a new frame replaces the old one');
end;

procedure TTestEditorSurface.TestTitleAndStatusLine;
var
  Handle: Integer;
  Text: string;
begin
  InstallHost;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  PluginSurfaceSetInfo(Handle, 'holiday.jpg', '800x600  2/9');
  Assert.AreEqual('holiday.jpg', GView.TabCaption, 'the tab caption');
  Text := AllText(Paint(GView));
  Assert.IsTrue(Pos('holiday.jpg', Text) > 0, 'the title is drawn');
  Assert.IsTrue(Pos('800x600  2/9', Text) > 0, 'the status line is drawn');
end;

procedure TTestEditorSurface.TestEscClosesAndOtherKeysGoToThePlugin;
var
  Handle: Integer;
  Keys: string;
begin
  InstallHost;
  Keys := '';
  Handle := PluginSurfaceOpen('t.surface', 'Pic',
    function(const AKey: string): Boolean
    begin
      Keys := Keys + AKey + ',';
      Result := AKey <> 'Esc';
    end, nil, nil);
  SendKey(GView, vkRight, #0);
  SendKey(GView, vkSpace, ' ');
  SendKey(GView, 0, '+');
  Assert.AreEqual('Right,Space,+,', Keys, 'the plugin gets the keys');
  Assert.AreEqual(0, GCloseRequests, 'they do not close the tab');
  SendKey(GView, vkEscape, #27);
  Assert.AreEqual('Right,Space,+,Esc,', Keys, 'the plugin is offered Esc first');
  Assert.AreEqual(1, GCloseRequests, 'Esc it does not use asks the host to close the tab');
  Assert.IsFalse(SurfaceExists(Handle), 'the surface is gone');
end;

procedure TTestEditorSurface.TestPluginClosingTheSurfaceClosesTheTab;
var
  Handle, Told: Integer;
begin
  InstallHost;
  Told := 0;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil,
    procedure
    begin
      Inc(Told);
    end);
  Assert.IsTrue(PluginSurfaceClose(Handle), 'closed by the plugin');
  Assert.AreEqual(1, GCloseRequests, 'the tab is asked to close');
  Assert.AreEqual(0, Told, 'the plugin is not told about its own close');
end;

procedure TTestEditorSurface.TestFullscreenCoversTheWholeWindow;
var
  Handle: Integer;
  Normal, Full: TRectI;
begin
  InstallHost;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil, nil);
  SendRed(Handle);
  Paint(GView);
  Assert.IsTrue(GView.SurfaceBounds(Normal), 'bounds of the tab');
  PluginSurfaceSetFullscreen(Handle, True);
  Paint(GView);
  Assert.IsTrue(GView.IsSurfaceFullscreen, 'full screen');
  Assert.IsTrue(GView.SurfaceBounds(Full), 'bounds in full screen');
  Assert.IsTrue((Full.Left < Normal.Left) and (Full.Top < Normal.Top) and (Full.Right > Normal.Right) and
    (Full.Bottom > Normal.Bottom), 'the picture area grows to the whole window');
  Assert.IsTrue((Full.Right - Full.Left + 1 = W) and (Full.Bottom - Full.Top + 1 = H), 'exactly the window');
end;

procedure TTestEditorSurface.TestEscLeavesFullscreenBeforeClosing;
var
  Handle: Integer;
begin
  InstallHost;
  Handle := PluginSurfaceOpenEx('t.surface', 'Pic', cSurfaceModeFullscreen, nil, nil, nil, nil);
  Assert.IsTrue(GView.IsSurfaceFullscreen, 'opened full screen');
  SendKey(GView, vkEscape, #27);
  Assert.IsFalse(GView.IsSurfaceFullscreen, 'the first Esc leaves full screen');
  Assert.AreEqual(0, GCloseRequests, 'and does not close the tab');
  SendKey(GView, vkEscape, #27);
  Assert.AreEqual(1, GCloseRequests, 'the second closes it');
  Assert.IsFalse(SurfaceExists(Handle), 'the surface is gone');
end;

procedure TTestEditorSurface.TestPluginCanTakeEscAndF10;
var
  Handle: Integer;
  Keys: string;
begin
  InstallHost;
  Keys := '';
  Handle := PluginSurfaceOpenEx('t.surface', 'Pic', cSurfaceModeFullscreen,
    function(const AKey: string): Boolean
    begin
      Keys := Keys + AKey + ',';
      Result := True;
    end, nil, nil, nil);
  SendKey(GView, vkEscape, #27);
  SendKey(GView, vkF10, #0);
  Assert.AreEqual('Esc,F10,', Keys, 'the plugin gets both keys');
  Assert.IsTrue(GView.IsSurfaceFullscreen, 'full screen stays as it is');
  Assert.AreEqual(0, GCloseRequests, 'the host does not close the tab');
  Assert.IsTrue(SurfaceExists(Handle), 'the surface stays');
end;

procedure TTestEditorSurface.TestDestroyingTheTabTellsThePlugin;
var
  Handle, Told: Integer;
begin
  InstallHost;
  Told := 0;
  Handle := PluginSurfaceOpen('t.surface', 'Pic', nil, nil,
    procedure
    begin
      Inc(Told);
    end);
  FreeAndNil(GView);
  Assert.AreEqual(1, Told, 'the plugin hears that the tab went');
  Assert.IsFalse(SurfaceExists(Handle), 'the surface is gone');
end;

initialization
  GCounter := TCloseCounter.Create;

finalization
  FreeAndNil(GCounter);

end.
