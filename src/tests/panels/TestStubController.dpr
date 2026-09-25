program TestStubController;

{$APPTYPE CONSOLE}

{ Behavior checks for TStubController (generic shell-info / folder-size
  message overlay). Two asymmetries worth locking down against regression:
  (1) unlike the three menu popups, Open() does NOT lay out Bounds — only
  Layout()/Draw() do, so Bounds is stale/degenerate right after Open();
  (2) HandleInput has no Visible/skNone guard — it's safe (and a no-op past
  the first call) to invoke even when nothing is open.
  Draw() itself is not exercised: the project's test convention (see
  TestPanelColumns.dpr, TestSortMenuController.dpr, ...) checks logic/state,
  not grid rendering. }

uses
  System.SysUtils, System.UITypes, System.Classes,
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uStubController in '..\..\Core\uStubController.pas';

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

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
  Writeln('Visible tracks Kind across Open/Close');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Expect(not Ctrl.Visible, 'not visible before any Open()');

    Ctrl.Open(skShellInfo, 'Folder size', '12 files, 3.4 MB');
    Expect(Ctrl.Visible, 'Open() makes the stub visible');
    Expect(Ctrl.Text = 'Folder size', 'Open() sets Text');
    Expect(Ctrl.Detail = '12 files, 3.4 MB', 'Open() sets Detail');
    Expect(Inv.Count = 1, 'Open() requests exactly one invalidate');

    Ctrl.Close;
    Expect(not Ctrl.Visible, 'Close() clears visibility');
    Expect(Ctrl.Text = '', 'Close() clears Text');
    Expect(Ctrl.Detail = '', 'Close() clears Detail');
    Expect(Inv.Count = 2, 'Close() requests another invalidate');
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
  Writeln('Open() leaves Bounds untouched — only Layout()/Draw() compute it');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    R := Ctrl.Bounds;
    Expect((R.Left = 0) and (R.Top = 0) and (R.Right = 0) and (R.Bottom = 0),
      'Bounds is still the zero-record right after Open(), before any Layout call');

    Ctrl.Layout(80, 25);
    R := Ctrl.Bounds;
    Expect(R.Width > 1, 'Layout() populates a real Bounds afterwards');
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
  Writeln('Layout() sizes to half the panel width, floored at 28');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');

    // Wide panel: W = max(80 div 2, 28) = 40.
    Ctrl.Layout(80, 25);
    R := Ctrl.Bounds;
    Expect(R.Width = 40, 'half-width on an 80-wide panel is 40');
    Expect(R.Height = 9, 'stub is always 9 rows tall');
    Expect(R.Left = (80 - 40) div 2, 'centered horizontally on a wide panel');

    // Medium panel: half (25) is below the 28 floor -> floors at 28.
    // (The implementation's second "W > PanelW-2" clamp re-floors to
    // Max(PanelW-2, 28), which is always >= 28 — so 28 is a hard floor
    // that this Layout can never size below, by construction.)
    Ctrl.Layout(50, 25);
    R := Ctrl.Bounds;
    Expect(R.Width = 28, 'half-width below the floor (25 on a 50-wide panel) clamps up to 28');
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
  Writeln('On a panel narrower than the 28-cell floor, the popup overflows but Left stays >= 0');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');

    // PanelW=10 is narrower than the 28-cell floor: W still floors to 28
    // (wider than the panel itself — accepted overflow, same convention as
    // TJobPopupRenderer.ComputeLayout), but Left must not go negative.
    Ctrl.Layout(10, 20);
    R := Ctrl.Bounds;
    Expect(R.Width = 28, 'width still floors to 28 even though the panel is only 10 wide');
    Expect(R.Left = 0, 'Left clamps to 0 instead of going negative');
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
  Writeln('Layout() never places the popup off the top/left of a tiny client area');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Ctrl.Layout(30, 8); // H=9 alone exceeds an 8-row-tall client area
    R := Ctrl.Bounds;
    Expect(R.Top >= 1, 'Top never goes below the 1-row floor');
    Expect(R.Left >= 0, 'Left never goes negative');
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
  Writeln('Escape and Enter both close the stub; Result is always True');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkEscape);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Expect(Handled, 'HandleInput always reports the key as handled');
    Expect(not Ctrl.Visible, 'Escape closes the stub');
    Expect(Key = 0, 'Escape consumes AKey (set to 0)');

    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkReturn);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Expect(Handled, 'HandleInput always reports the key as handled');
    Expect(not Ctrl.Visible, 'Enter also closes the stub');
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
  Writeln('Any other key is swallowed (modal) without closing the stub');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Ctrl.Open(skShellInfo, 'Title', 'Detail');
    Key := Word(vkUp);
    Ch := 'x';
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Ctrl.Visible, 'an unrelated key does not close the stub');
    Expect(Key = 0, 'the key is still consumed (AKey set to 0)');
    Expect(Ch = #0, 'the char is still consumed (AKeyChar set to #0)');
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
  Writeln('HandleInput is a safe no-op when nothing is open (no skNone guard, no crash)');
  Inv := TInvalidateSpy.Create;
  Ctrl := TStubController.Create(nil, Inv.OnInvalidate);
  try
    Expect(not Ctrl.Visible, 'starts closed');
    Key := Word(vkEscape);
    Ch := #0;
    Handled := Ctrl.HandleInput(Key, [], Ch);
    Expect(Handled, 'still reports handled even though nothing was open');
    Expect(not Ctrl.Visible, 'stays closed');
  finally
    Ctrl.Free;
    Inv.Free;
  end;
end;

begin
  Failed := 0;
  try
    TestVisibilityLifecycle;
    TestOpenDoesNotLayoutEagerly;
    TestLayoutSizingAndFloor;
    TestLayoutNeverGoesNegativeOnTinyPanel;
    TestLayoutClampsToClientArea;
    TestHandleInputEscapeAndEnterClose;
    TestHandleInputOtherKeyStaysOpen;
    TestHandleInputSafeWhenAlreadyClosed;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.Message);
      Halt(2);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln('Failed: ', Failed);
  Halt(1);
end.
