program TestSortMenuController;

{$APPTYPE CONSOLE}

{ Behavior checks for TSortMenuController (Ctrl+F3..F9 "Sort by" popup) —
  navigation, hotkey/Enter/click selection, mutual-exclusion-free lifecycle.
  Draw() is not exercised: the project's test convention (see
  TestPanelColumns.dpr, TestDualPanelCmdLine.dpr, ...) checks logic/state,
  not grid rendering. }

uses
  System.SysUtils, System.UITypes, System.Classes,
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uSortMenuController in '..\Core\uSortMenuController.pas';

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

function FixedPanelBounds(ASide: TPanelSide): TRectI;
begin
  Result := TRectI.Make(0, 0, 79, 24); // 80x25, plenty of room for the popup
end;

function ActiveSideLeft: TPanelSide;
begin
  Result := psLeft;
end;

type
  TSelectSpy = class
    Count: Integer;
    LastColumn: TPanelSortColumn;
    procedure OnSelect(AColumn: TPanelSortColumn);
  end;

procedure TSelectSpy.OnSelect(AColumn: TPanelSortColumn);
begin
  Inc(Count);
  LastColumn := AColumn;
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

procedure TestOpenPicksCurrentColumnIndex;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Open() selects the row matching the current sort column');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);

    Ctrl.Open(pscSize, False);
    Expect(Ctrl.Visible, 'Open() makes the menu visible');
    Expect(Ctrl.Bounds.Width >= 10, 'Open() lays out a non-degenerate popup');
    Expect(Inv.Count > 0, 'Open() requests an invalidate');

    // Size is the 4th item (index 3) in BuildSortMenuItems order — confirmed
    // indirectly: pressing Enter immediately must select Size, not Name.
    Key := Word(vkReturn);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.Count = 1, 'Enter fires OnSortSelect exactly once');
    Expect(Spy.LastColumn = pscSize, 'Enter selects the column Open() was given (Size)');
    Expect(not Ctrl.Visible, 'Enter closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestArrowNavigationClampsNoWrap;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Up/Down clamp at the list ends (no wrap-around)');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscName, False); // Name = index 0, first row

    // AKey is a var param that HandleInput zeroes after consuming it (the
    // "handled, stop dispatching" signal a real key-event loop relies on) —
    // it must be re-armed with the key code before every single press.
    Ch := #0;
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.LastColumn = pscName,
      'Up at the top row stays clamped on Name (no wrap to the last row)');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;

  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscType, False); // Type = index 8, last row

    Ch := #0;
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.LastColumn = pscType,
      'Down at the bottom row stays clamped on Type (no wrap to the first row)');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestHotkeySelectsRegardlessOfCursor;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Hotkey selects its column directly, independent of cursor position');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscName, False); // cursor starts on Name (index 0)

    Key := 0;
    Ch := 's'; // hotkey for "Size", lower-case to check UpCase handling
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.Count = 1, 'hotkey fires OnSortSelect exactly once');
    Expect(Spy.LastColumn = pscSize, 'lower-case ''s'' hotkey selects Size');
    Expect(not Ctrl.Visible, 'hotkey selection closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestEscapeClosesWithoutSelecting;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Escape closes without firing OnSortSelect');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscModified, True);
    Expect(Ctrl.Visible, 'Open() makes the menu visible');

    Key := Word(vkEscape);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Expect(not Ctrl.Visible, 'Escape closes the menu');
    Expect(Spy.Count = 0, 'Escape never calls OnSortSelect');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestClickSelectsRowUnderCursor;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  R: TRectI;
  Handled: Boolean;
begin
  Writeln('Clicking a row selects that row''s column and closes');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscName, False);
    R := Ctrl.Bounds;

    // Row 1 (0-based index 1, "Extension") sits at R.Top + 1 + 1.
    Handled := Ctrl.HandleClick(R.Left + 1, R.Top + 2);
    Expect(Handled, 'click inside the popup is handled');
    Expect(Spy.Count = 1, 'click on a row fires OnSortSelect exactly once');
    Expect(Spy.LastColumn = pscExt, 'click on row index 1 selects Extension');
    Expect(not Ctrl.Visible, 'click selection closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestClickCloseMarkDismissesWithoutSelecting;
var
  Ctrl: TSortMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  R: TRectI;
  BtnX: Integer;
  Handled: Boolean;
begin
  Writeln('Clicking the [x] close mark dismisses without selecting');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TSortMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnSortSelect(Spy.OnSelect);
    Ctrl.Open(pscName, False);
    R := Ctrl.Bounds;
    BtnX := R.Right - 3; // matches WindowFrameCloseHit's own '[x]' math

    Handled := Ctrl.HandleClick(BtnX, R.Top);
    Expect(Handled, 'click on the close mark is handled');
    Expect(Spy.Count = 0, 'close mark never fires OnSortSelect');
    Expect(not Ctrl.Visible, 'close mark closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

begin
  Failed := 0;
  try
    TestOpenPicksCurrentColumnIndex;
    TestArrowNavigationClampsNoWrap;
    TestHotkeySelectsRegardlessOfCursor;
    TestEscapeClosesWithoutSelecting;
    TestClickSelectsRowUnderCursor;
    TestClickCloseMarkDismissesWithoutSelecting;
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
