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
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  System.UITypes, uTerminalTypes, uTermInput, uHostShell, uSdlApi, uSdlInput,
  uPixelGrid, uFakeGlyphs;

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

initialization
  TDUnitX.RegisterTestFixture(TTestSdlShell);

end.
