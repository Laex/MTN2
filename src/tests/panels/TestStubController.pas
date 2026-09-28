unit TestStubController;

{ Behavior checks for TStubController (generic shell-info / folder-size
  message overlay). Two asymmetries worth locking down against regression:
  (1) unlike the three menu popups, Open() does NOT lay out Bounds - only
  Layout()/Draw() do, so Bounds is stale/degenerate right after Open();
  (2) HandleInput has no Visible/skNone guard - it's safe (and a no-op past
  the first call) to invoke even when nothing is open.
  Draw() itself is not exercised: the project's test convention (see
  TestPanelColumns.pas, TestSortMenuController.pas, ...) checks logic/state,
  not grid rendering. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStubController = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestVisibilityLifecycle;
    [Test] procedure TestOpenDoesNotLayoutEagerly;
    [Test] procedure TestLayoutSizingAndFloor;
    [Test] procedure TestLayoutNeverGoesNegativeOnTinyPanel;
    [Test] procedure TestLayoutClampsToClientArea;
    [Test] procedure TestHandleInputEscapeAndEnterClose;
    [Test] procedure TestHandleInputOtherKeyStaysOpen;
    [Test] procedure TestHandleInputSafeWhenAlreadyClosed;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Classes,
  uThemeTypes,
  uDualPanelUiTypes,
  uStubController;

type
  TInvalidateSpy = class
    Count: Integer;
    procedure OnInvalidate;
  end;

procedure TInvalidateSpy.OnInvalidate;
begin
  Inc(Count);
end;

procedure TestVisibilityLifecycle;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Assert.IsTrue(not Ctrl.Visible, 'not visible before any Open()');

    Ctrl.Open(skShellInfo, 'Folder size', '12 files, 3.4 MB');
    Assert.IsTrue(Ctrl.Visible, 'Open() makes the stub visible');
    Assert.IsTrue(Ctrl.Text = 'Folder size', 'Open() sets Text');
    Assert.IsTrue(Ctrl.Detail = '12 files, 3.4 MB', 'Open() sets Detail');
    Assert.IsTrue(Inv.Count = 1, 'Open() requests exactly one invalidate');

    Ctrl.Close;
    Assert.IsTrue(not Ctrl.Visible, 'Close() clears visibility');
    Assert.IsTrue(Ctrl.Text = '', 'Close() clears Text');
    Assert.IsTrue(Ctrl.Detail = '', 'Close() clears Detail');
    Assert.IsTrue(Inv.Count = 2, 'Close() requests another invalidate');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestOpenDoesNotLayoutEagerly;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  R: TRectI;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    R := Ctrl.Bounds;
    Assert.IsTrue((R.Left = 0) and (R.Top = 0) and (R.Right = 0) and (R.Bottom = 0),
      'Bounds is still the zero-record right after Open(), before any Layout call');

    Ctrl.Layout(80, 25);
    R := Ctrl.Bounds;
    Assert.IsTrue(R.Width > 1, 'Layout() populates a real Bounds afterwards');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestLayoutSizingAndFloor;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  R: TRectI;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');

    // Wide panel: W = max(80 div 2, 28) = 40.
    Ctrl.Layout(80, 25);
    R := Ctrl.Bounds;
    Assert.IsTrue(R.Width = 40, 'half-width on an 80-wide panel is 40');
    Assert.IsTrue(R.Height = 9, 'stub is always 9 rows tall');
    Assert.IsTrue(R.Left = (80 - 40) div 2, 'centered horizontally on a wide panel');

    // Medium panel: half (25) is below the 28 floor -> floors at 28.
    // (The implementation's second "W > PanelW-2" clamp re-floors to
    // Max(PanelW-2, 28), which is always >= 28 - so 28 is a hard floor
    // that this Layout can never size below, by construction.)
    Ctrl.Layout(50, 25);
    R := Ctrl.Bounds;
    Assert.IsTrue(R.Width = 28, 'half-width below the floor (25 on a 50-wide panel) clamps up to 28');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestLayoutNeverGoesNegativeOnTinyPanel;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  R: TRectI;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');

    // PanelW=10 is narrower than the 28-cell floor: W still floors to 28
    // (wider than the panel itself - accepted overflow, same convention as
    // TJobPopupRenderer.ComputeLayout), but Left must not go negative.
    Ctrl.Layout(10, 20);
    R := Ctrl.Bounds;
    Assert.IsTrue(R.Width = 28, 'width still floors to 28 even though the panel is only 10 wide');
    Assert.IsTrue(R.Left = 0, 'Left clamps to 0 instead of going negative');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestLayoutClampsToClientArea;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  R: TRectI;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Ctrl.Layout(30, 8); // H=9 alone exceeds an 8-row-tall client area
    R := Ctrl.Bounds;
    Assert.IsTrue(R.Top >= 1, 'Top never goes below the 1-row floor');
    Assert.IsTrue(R.Left >= 0, 'Left never goes negative');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestHandleInputEscapeAndEnterClose;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
  Handled: Boolean;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkEscape);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Handled, 'HandleInput always reports the key as handled');
    Assert.IsTrue(not Ctrl.Visible, 'Escape closes the stub');
    Assert.IsTrue(Key = 0, 'Escape consumes AKey (set to 0)');

    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkReturn);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Handled, 'HandleInput always reports the key as handled');
    Assert.IsTrue(not Ctrl.Visible, 'Enter also closes the stub');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestHandleInputOtherKeyStaysOpen;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkUp);
    Ch := 'x';
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Ctrl.Visible, 'an unrelated key does not close the stub');
    Assert.IsTrue(Key = 0, 'the key is still consumed (AKey set to 0)');
    Assert.IsTrue(Ch = #0, 'the char is still consumed (AKeyChar set to #0)');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

procedure TestHandleInputSafeWhenAlreadyClosed;
var
  Ctrl: TStubController;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
  Handled: Boolean;
begin
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Assert.IsTrue(not Ctrl.Visible, 'starts closed');
    Key := Word(vkEscape);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Handled, 'still reports handled even though nothing was open');
    Assert.IsTrue(not Ctrl.Visible, 'stays closed');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

{ TTestStubController }

procedure TTestStubController.SetupFixture;
begin
end;

procedure TTestStubController.TestVisibilityLifecycle;
begin
  TestStubController.TestVisibilityLifecycle;
end;

procedure TTestStubController.TestOpenDoesNotLayoutEagerly;
begin
  TestStubController.TestOpenDoesNotLayoutEagerly;
end;

procedure TTestStubController.TestLayoutSizingAndFloor;
begin
  TestStubController.TestLayoutSizingAndFloor;
end;

procedure TTestStubController.TestLayoutNeverGoesNegativeOnTinyPanel;
begin
  TestStubController.TestLayoutNeverGoesNegativeOnTinyPanel;
end;

procedure TTestStubController.TestLayoutClampsToClientArea;
begin
  TestStubController.TestLayoutClampsToClientArea;
end;

procedure TTestStubController.TestHandleInputEscapeAndEnterClose;
begin
  TestStubController.TestHandleInputEscapeAndEnterClose;
end;

procedure TTestStubController.TestHandleInputOtherKeyStaysOpen;
begin
  TestStubController.TestHandleInputOtherKeyStaysOpen;
end;

procedure TTestStubController.TestHandleInputSafeWhenAlreadyClosed;
begin
  TestStubController.TestHandleInputSafeWhenAlreadyClosed;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStubController);

end.
