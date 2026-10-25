unit TestSdlShell;

{ The whole path of the graphical host without a window: SDL events go
  through the input mapper into the host shell, the shell composes the grid
  and the pixel renderer draws it. The glyph source is a fixed pattern. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSdlShell = class
  public
    [Test] procedure FunctionKeyOpensADialogThatIsDrawn;
    [Test] procedure EscapeClosesTheDialog;
    [Test] procedure TypedTextReachesTheCommandLine;
    [Test] procedure MouseClickInTheMenuBarOpensAMenu;
    [Test] procedure QuitKeyEndsTheLoop;
    [Test] procedure ChangedCellsAreTheOnesTheShellRedraws;
    [Test] procedure PluginPictureTabOpensAndGetsKeys;
    [Test] procedure DragToTheOtherPanelCopiesTheFile;
    [Test] procedure DragWithShiftMovesTheFile;
    [Test] procedure DragBackOntoTheSameFolderChangesNothing;
    [Test] procedure SeveralStartupFoldersOpenSeveralTabs;
    [Test] procedure StartupViewTargetOpensTheFileInTheViewer;
    [Test] procedure StartupEditTargetOpensTheFileInTheEditor;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  System.UITypes, uTerminalTypes, uTermInput, uHostShell, uSdlApi, uSdlInput,
  uPixelGrid, uFakeGlyphs, System.IOUtils, uPluginSurface, uStartupTargets;

const
  cScancodeBit = $40000000;

type
  THostRig = class
  strict private
    FShell: THostShell;
    FMapper: TSdlInputMapper;
    FGrid: TPixelGridRenderer;
    FEvents: TList<TTermEvent>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Send(const E: TSDLEvent);
    function Screen: string;
    procedure Draw;
    procedure SetMods(AMods: Integer);
    property Shell: THostShell read FShell;
    property Renderer: TPixelGridRenderer read FGrid;
  end;

constructor THostRig.Create;
begin
  inherited Create;
  // Without a saved session a shell follows the OS language; the checks read English text.
  FShell := THostShell.Create(100, 30, 'en');
  FMapper := TSdlInputMapper.Create;
  FGrid := TPixelGridRenderer.Create(TFakeGlyphs.Create);
  FMapper.SetCellSize(FGrid.CellWidth, FGrid.CellHeight);
  FEvents := TList<TTermEvent>.Create;
end;

destructor THostRig.Destroy;
begin
  FEvents.Free;
  FGrid.Free;
  FMapper.Free;
  FShell.Free;
  inherited;
end;

procedure THostRig.Send(const E: TSDLEvent);
var
  Ev: TTermEvent;
begin
  FEvents.Clear;
  FMapper.Translate(E, FEvents);
  for Ev in FEvents do
    FShell.HandleEvent(Ev);
end;

procedure THostRig.SetMods(AMods: Integer);
begin
  FMapper.Mods := AMods;
end;

procedure THostRig.Draw;
begin
  FGrid.Render(FShell.Compose);
end;

function THostRig.Screen: string;
var
  Grid: TTerminalGrid;
  Y, X: Integer;
begin
  Grid := FShell.Compose;
  Result := '';
  for Y := 0 to High(Grid) do
  begin
    for X := 0 to High(Grid[Y]) do
      Result := Result + Grid[Y][X].CharValue;
    Result := Result + #10;
  end;
  FGrid.Render(Grid);
end;

function Key(ASym, AScan, AMods: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_KEYDOWN);
  SdlEventSetU32(Result, 16, Cardinal(AScan));
  SdlEventSetU32(Result, 20, Cardinal(ASym));
  SdlEventSetU32(Result, 24, Cardinal(AMods));
end;

function Text(const AText: string): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, SDL_TEXTINPUT);
  SdlEventSetText(Result, AText);
end;

function Click(AType: Cardinal; AX, AY: Integer): TSDLEvent;
begin
  Result := Default(TSDLEvent);
  SdlEventSetU32(Result, 0, AType);
  SdlEventSetU8(Result, 16, SDL_BUTTON_LEFT);
  SdlEventSetU32(Result, 20, Cardinal(AX));
  SdlEventSetU32(Result, 24, Cardinal(AY));
end;

procedure TTestSdlShell.FunctionKeyOpensADialogThatIsDrawn;
var
  Rig: THostRig;
begin
  Rig := THostRig.Create;
  try
    Rig.Screen;
    // F7 is the scancode 64.
    Rig.Send(Key(cScancodeBit or 64, 64, 0));
    Assert.IsTrue(Rig.Screen.Contains('Make directory'));
    Assert.IsTrue(Rig.Renderer.Width > 0, 'and the renderer has a bitmap for it');
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.EscapeClosesTheDialog;
var
  Rig: THostRig;
begin
  Rig := THostRig.Create;
  try
    Rig.Send(Key(cScancodeBit or 64, 64, 0));
    Assert.IsTrue(Rig.Screen.Contains('Make directory'));
    Rig.Send(Key(27, 41, 0));
    Assert.IsFalse(Rig.Screen.Contains('Make directory'));
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.TypedTextReachesTheCommandLine;
var
  Rig: THostRig;
begin
  Rig := THostRig.Create;
  try
    Rig.Send(Key(Ord('x'), 27, 0));
    Rig.Send(Text('x'));
    Rig.Send(Key(Ord('y'), 28, 0));
    Rig.Send(Text('y'));
    Rig.Send(Key(Ord('z'), 29, 0));
    Rig.Send(Text('z'));
    Assert.IsTrue(Rig.Screen.Contains('xyz'), 'the letters typed so far');
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.MouseClickInTheMenuBarOpensAMenu;
var
  Rig: THostRig;
  Before: string;
begin
  Rig := THostRig.Create;
  try
    Before := Rig.Screen;
    // The cell of the first menu title, from pixels: cell 8 x 16, row 0.
    Rig.Send(Click(SDL_MOUSEBUTTONDOWN, 6 * 8 + 3, 5));
    Rig.Send(Click(SDL_MOUSEBUTTONUP, 6 * 8 + 3, 5));
    Assert.IsTrue(Rig.Shell.Dirty, 'the click asks for a new frame');
    Assert.AreNotEqual(Before, Rig.Screen, 'a menu is open');
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.QuitKeyEndsTheLoop;
var
  Rig: THostRig;
begin
  Rig := THostRig.Create;
  try
    Assert.IsFalse(Rig.Shell.Quit);
    Rig.Send(Key(cScancodeBit or 67, 67, 0));
    Assert.IsTrue(Rig.Shell.Quit, 'F10');
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.ChangedCellsAreTheOnesTheShellRedraws;
var
  Rig: THostRig;
begin
  Rig := THostRig.Create;
  try
    Rig.Draw;
    Rig.Renderer.ClearDirty;
    Rig.Draw;
    Assert.IsTrue(Rig.Renderer.DirtyRect.IsEmpty, 'a frame like the last one paints nothing');
    Rig.Send(Text('x'));
    Rig.Draw;
    Assert.IsFalse(Rig.Renderer.DirtyRect.IsEmpty, 'the typed letter changed some pixels');
  finally
    Rig.Free;
  end;
end;

procedure TTestSdlShell.PluginPictureTabOpensAndGetsKeys;
var
  Rig: THostRig;
  Dir, KeyName: string;
  H: Integer;
  Pixels: TBytes;
  Closed: Boolean;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-surface-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Dir);
  GHostShowsSurfaces := True;
  Rig := THostRig.Create;
  try
    Rig.Shell.AttachPlugins(Dir);
    KeyName := '';
    Closed := False;
    H := PluginSurfaceOpen('t.surface', 'Pic',
      function(const AKey: string): Boolean
      begin
        KeyName := AKey;
        Result := AKey = 'Right';
      end,
      nil,
      procedure
      begin
        Closed := True;
      end);
    Assert.IsTrue(H > 0, 'the host opens a picture tab');
    SetLength(Pixels, 4 * 4 * 4);
    FillChar(Pixels[0], Length(Pixels), $FF);
    Assert.IsTrue(PluginSurfaceSetFrame(H, 4, 4, @Pixels[0], Length(Pixels)));
    Rig.Screen;
    Assert.IsTrue(SurfaceExists(H), 'the tab holds the surface');
    Rig.Send(Key(cScancodeBit or 79, 79, 0));
    Assert.AreEqual('Right', KeyName, 'the key reaches the plugin');
    Rig.Send(Key(27, 41, 0));
    Rig.Screen;
    Assert.IsTrue(Closed, 'closing the tab tells the plugin');
  finally
    Rig.Shell.DetachPlugins;
    Rig.Free;
    GHostShowsSurfaces := False;
    TDirectory.Delete(Dir, True);
  end;
end;

type
  TDragRig = record
    Rig: THostRig;
    Left, Right: string;
    FileCol, FileRow: Integer;
  end;

// The grid cell where "text" starts, -1 when it is not on the screen.
function FindOnScreen(ARig: THostRig; const AText: string; out ACol, ARow: Integer): Boolean;
var
  Lines: TArray<string>;
  Line: string;
  P, Y: Integer;
begin
  Lines := ARig.Screen.Split([#10]);
  Y := 0;
  for Line in Lines do
  begin
    P := Pos(AText, Line);
    if P > 0 then
    begin
      ACol := P - 1;
      ARow := Y;
      Exit(True);
    end;
    Inc(Y);
  end;
  Result := False;
  ACol := -1;
  ARow := -1;
end;

procedure PumpMain(AMilliseconds: Integer);
var
  Waited: Integer;
begin
  Waited := 0;
  while Waited < AMilliseconds do
  begin
    CheckSynchronize(20);
    Inc(Waited, 20);
  end;
end;

function Pixel(ACell, ASize: Integer): Integer;
begin
  Result := ACell * ASize + ASize div 2;
end;

procedure PrepareDrag(var ADrag: TDragRig);
var
  Root: string;
  I: Integer;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-panel-drag-' + TPath.GetGUIDFileName(False));
  ADrag.Left := TPath.Combine(Root, 'left');
  ADrag.Right := TPath.Combine(Root, 'right');
  TDirectory.CreateDirectory(ADrag.Left);
  TDirectory.CreateDirectory(ADrag.Right);
  TFile.WriteAllText(TPath.Combine(ADrag.Left, 'dragme.txt'), 'x', TEncoding.UTF8);
  ADrag.Rig := THostRig.Create;
  ADrag.Rig.Shell.DualPanel.OpenPathAsNewTab(ADrag.Left);
  // Tab moves to the right panel.
  ADrag.Rig.Send(Key(9, 43, 0));
  ADrag.Rig.Shell.DualPanel.OpenPathAsNewTab(ADrag.Right);
  ADrag.Rig.Send(Key(9, 43, 0));
  for I := 1 to 50 do
  begin
    PumpMain(40);
    if FindOnScreen(ADrag.Rig, 'dragme.txt', ADrag.FileCol, ADrag.FileRow) then
      Break;
  end;
end;

procedure DragFileToTheRightPanel(const ADrag: TDragRig; AMods: Integer);
var
  Step: Integer;
  Ev: TSDLEvent;
begin
  ADrag.Rig.SetMods(0);
  ADrag.Rig.Send(Click(SDL_MOUSEBUTTONDOWN, Pixel(ADrag.FileCol + 2, 8), Pixel(ADrag.FileRow, 16)));
  for Step := 1 to 8 do
  begin
    Ev := Default(TSDLEvent);
    SdlEventSetU32(Ev, 0, SDL_MOUSEMOTION);
    SdlEventSetU32(Ev, 16, 1);
    SdlEventSetU32(Ev, 20, Cardinal(Pixel(ADrag.FileCol + 2, 8) + Step * 40));
    SdlEventSetU32(Ev, 24, Cardinal(Pixel(ADrag.FileRow, 16) + Step * 8));
    ADrag.Rig.Send(Ev);
  end;
  ADrag.Rig.SetMods(AMods);
  ADrag.Rig.Send(Click(SDL_MOUSEBUTTONUP, Pixel(75, 8), Pixel(14, 16)));
  ADrag.Rig.SetMods(0);
end;

function WaitForFile(const APath: string; AShouldExist: Boolean): Boolean;
var
  I: Integer;
begin
  for I := 1 to 100 do
  begin
    PumpMain(30);
    if TFile.Exists(APath) = AShouldExist then
      Exit(True);
  end;
  Result := TFile.Exists(APath) = AShouldExist;
end;

procedure FinishDrag(var ADrag: TDragRig);
begin
  ADrag.Rig.Free;
  TDirectory.Delete(TPath.GetDirectoryName(ADrag.Left), True);
end;

procedure TTestSdlShell.DragToTheOtherPanelCopiesTheFile;
var
  D: TDragRig;
begin
  PrepareDrag(D);
  try
    Assert.IsTrue(D.FileCol >= 0, 'the file is on the screen');
    DragFileToTheRightPanel(D, 0);
    // The drop opens the same confirmation as F5, aimed at the other folder.
    Assert.IsTrue(D.Rig.Screen.Contains('Copy `dragme.txt` to:'), 'the copy dialog opens');
    Assert.IsTrue(D.Rig.Screen.Contains(PathDelim + 'right' + PathDelim), 'and names the other panel');
    D.Rig.Send(Key(13, 40, 0));
    Assert.IsTrue(WaitForFile(TPath.Combine(D.Right, 'dragme.txt'), True), 'the file arrived');
    Assert.IsTrue(TFile.Exists(TPath.Combine(D.Left, 'dragme.txt')), 'and is still where it was');
  finally
    FinishDrag(D);
  end;
end;

procedure TTestSdlShell.DragWithShiftMovesTheFile;
var
  D: TDragRig;
begin
  PrepareDrag(D);
  try
    Assert.IsTrue(D.FileCol >= 0, 'the file is on the screen');
    DragFileToTheRightPanel(D, KMOD_LSHIFT);
    Assert.IsTrue(D.Rig.Screen.Contains('Move `dragme.txt` to:') or D.Rig.Screen.Contains('Rename/Move'),
      'the move dialog opens'#10 + D.Rig.Screen);
    D.Rig.Send(Key(13, 40, 0));
    Assert.IsTrue(WaitForFile(TPath.Combine(D.Right, 'dragme.txt'), True), 'the file arrived');
    Assert.IsTrue(WaitForFile(TPath.Combine(D.Left, 'dragme.txt'), False), 'and left the first folder');
  finally
    FinishDrag(D);
  end;
end;

procedure TTestSdlShell.DragBackOntoTheSameFolderChangesNothing;
var
  D: TDragRig;
  Step: Integer;
  Ev: TSDLEvent;
begin
  PrepareDrag(D);
  try
    Assert.IsTrue(D.FileCol >= 0, 'the file is on the screen');
    D.Rig.Send(Click(SDL_MOUSEBUTTONDOWN, Pixel(D.FileCol + 2, 8), Pixel(D.FileRow, 16)));
    for Step := 1 to 6 do
    begin
      Ev := Default(TSDLEvent);
      SdlEventSetU32(Ev, 0, SDL_MOUSEMOTION);
      SdlEventSetU32(Ev, 16, 1);
      SdlEventSetU32(Ev, 20, Cardinal(Pixel(D.FileCol + 2, 8) + Step * 8));
      SdlEventSetU32(Ev, 24, Cardinal(Pixel(D.FileRow, 16) + Step * 20));
      D.Rig.Send(Ev);
    end;
    D.Rig.Send(Click(SDL_MOUSEBUTTONUP, Pixel(10, 8), Pixel(14, 16)));
    PumpMain(400);
    Assert.IsTrue(TFile.Exists(TPath.Combine(D.Left, 'dragme.txt')), 'the file stays');
    Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(D.Right))), 'the other folder is empty');
    Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(D.Left))), 'no copy appeared next to it');
  finally
    FinishDrag(D);
  end;
end;

// Runs the panel window until AText is on the screen or the time is up.
function WaitForScreenText(ARig: THostRig; const AText: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to 50 do
  begin
    PumpMain(40);
    if ARig.Screen.Contains(AText) then
      Exit(True);
  end;
  Result := False;
end;

function StartupTarget(const APath: string; AMode: TStartupMode): TStartupTarget;
begin
  Result.Path := APath;
  Result.Mode := AMode;
end;

procedure TTestSdlShell.SeveralStartupFoldersOpenSeveralTabs;
var
  Rig: THostRig;
  Root, One, Two: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-startup-' + TPath.GetGUIDFileName(False));
  One := TPath.Combine(Root, 'one');
  Two := TPath.Combine(Root, 'two');
  TDirectory.CreateDirectory(One);
  TDirectory.CreateDirectory(Two);
  TFile.WriteAllText(TPath.Combine(One, 'inone.txt'), 'x', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(Two, 'intwo.txt'), 'x', TEncoding.UTF8);
  Rig := THostRig.Create;
  try
    Rig.Shell.DualPanel.OpenStartupTargets([StartupTarget(One, smOpen), StartupTarget(Two, smOpen)]);
    Assert.IsTrue(WaitForScreenText(Rig, 'intwo.txt'), 'the last folder is shown'#10 + Rig.Screen);
    Assert.IsTrue(Rig.Screen.Contains('one x'), 'the first folder keeps its tab'#10 + Rig.Screen);
  finally
    Rig.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestSdlShell.StartupViewTargetOpensTheFileInTheViewer;
var
  Rig: THostRig;
  Root, FileName: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-startup-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Root);
  FileName := TPath.Combine(Root, 'viewme.txt');
  TFile.WriteAllText(FileName, 'startup-view-marker', TEncoding.UTF8);
  Rig := THostRig.Create;
  try
    Rig.Shell.DualPanel.OpenStartupTargets([StartupTarget(FileName, smView)]);
    Assert.IsTrue(WaitForScreenText(Rig, 'startup-view-marker'), 'the viewer shows the text'#10 + Rig.Screen);
  finally
    Rig.Free;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestSdlShell.StartupEditTargetOpensTheFileInTheEditor;
var
  Rig: THostRig;
  Root, FileName: string;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-startup-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(Root);
  FileName := TPath.Combine(Root, 'editme.txt');
  TFile.WriteAllText(FileName, 'startup-edit-marker', TEncoding.UTF8);
  Rig := THostRig.Create;
  try
    Rig.Shell.DualPanel.OpenStartupTargets([StartupTarget(FileName, smEdit)]);
    Assert.IsTrue(WaitForScreenText(Rig, 'startup-edit-marker'), 'the editor shows the text'#10 + Rig.Screen);
    // A name that does not exist yet opens an empty buffer in an existing folder.
    Rig.Shell.DualPanel.OpenStartupTargets([StartupTarget(TPath.Combine(Root, 'fresh.txt'), smEdit)]);
    Assert.IsFalse(TFile.Exists(TPath.Combine(Root, 'fresh.txt')), 'nothing is written before a save');
  finally
    Rig.Free;
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSdlShell);

end.
