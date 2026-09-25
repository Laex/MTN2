program TestColumnModeMenuController;

{$APPTYPE CONSOLE}

{ Behavior checks for TColumnModeMenuController (Ctrl+1..6 "Column modes"
  popup) — navigation, numeric/hotkey/Enter/click selection. Draw() is not
  exercised: the project's test convention (see TestPanelColumns.dpr,
  TestSortMenuController.dpr, ...) checks logic/state, not grid rendering. }

uses
  System.SysUtils, System.UITypes, System.Classes,
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\..\Core\uDualPanelUiTypes.pas',
  uColumnModeMenuController in '..\..\Core\uColumnModeMenuController.pas';

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
    LastMode: TPanelColumnMode;
    procedure OnSelect(AMode: TPanelColumnMode);
  end;

procedure TSelectSpy.OnSelect(AMode: TPanelColumnMode);
begin
  Inc(Count);
  LastMode := AMode;
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

procedure TestOpenPicksCurrentModeIndex;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Open() selects the row matching the current column mode');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);

    Ctrl.Open(pcmDate);
    Expect(Ctrl.Visible, 'Open() makes the menu visible');
    Expect(Ctrl.Bounds.Width >= 10, 'Open() lays out a non-degenerate popup');
    Expect(Inv.Count > 0, 'Open() requests an invalidate');

    // Date is the 3rd item (index 2) in BuildColumnModeMenuItems order —
    // confirmed indirectly: pressing Enter immediately must select Date.
    Key := Word(vkReturn);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.Count = 1, 'Enter fires OnColumnModeSelect exactly once');
    Expect(Spy.LastMode = pcmDate, 'Enter selects the mode Open() was given (Date)');
    Expect(not Ctrl.Visible, 'Enter closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestArrowNavigationClampsNoWrap;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Up/Down clamp at the list ends (no wrap-around)');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief); // Brief = index 0, first row

    // AKey is a var param that HandleInput zeroes after consuming it (the
    // "handled, stop dispatching" signal a real key-event loop relies on) —
    // it must be re-armed with the key code before every single press.
    Ch := #0;
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.LastMode = pcmBrief,
      'Up at the top row stays clamped on Brief (no wrap to the last row)');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;

  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmTypes); // Types = index 5, last row

    Ch := #0;
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.LastMode = pcmTypes,
      'Down at the bottom row stays clamped on Types (no wrap to the first row)');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestNumericShortcutSelectsRegardlessOfCursor;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Digit key selects the mode at that 1-based position');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief); // cursor starts on Brief (index 0)

    Key := 0;
    Ch := '3'; // 1-based -> index 2 -> Date
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.Count = 1, '''3'' fires OnColumnModeSelect exactly once');
    Expect(Spy.LastMode = pcmDate, '''3'' selects the 3rd item (Date)');
    Expect(not Ctrl.Visible, 'digit selection closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestHotkeySelectsRegardlessOfCursor;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Letter hotkey selects its mode, independent of cursor position');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief); // cursor starts on Brief (index 0)

    Key := 0;
    Ch := 'f'; // hotkey for "Full", lower-case to check UpCase handling
    Ctrl.HandleInput(Key, [], Ch);
    Expect(Spy.Count = 1, 'hotkey fires OnColumnModeSelect exactly once');
    Expect(Spy.LastMode = pcmFull, 'lower-case ''f'' hotkey selects Full');
    Expect(not Ctrl.Visible, 'hotkey selection closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestEscapeClosesWithoutSelecting;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Writeln('Escape closes without firing OnColumnModeSelect');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmFull);
    Expect(Ctrl.Visible, 'Open() makes the menu visible');

    Key := Word(vkEscape);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Expect(not Ctrl.Visible, 'Escape closes the menu');
    Expect(Spy.Count = 0, 'Escape never calls OnColumnModeSelect');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestClickSelectsRowUnderCursor;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  R: TRectI;
  Handled: Boolean;
begin
  Writeln('Clicking a row selects that row''s mode and closes');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief);
    R := Ctrl.Bounds;

    // Row 1 (0-based index 1, "Size") sits at R.Top + 1 + 1.
    Handled := Ctrl.HandleClick(R.Left + 1, R.Top + 2);
    Expect(Handled, 'click inside the popup is handled');
    Expect(Spy.Count = 1, 'click on a row fires OnColumnModeSelect exactly once');
    Expect(Spy.LastMode = pcmSize, 'click on row index 1 selects Size');
    Expect(not Ctrl.Visible, 'click selection closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestClickCloseMarkDismissesWithoutSelecting;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  R: TRectI;
  BtnX: Integer;
  Handled: Boolean;
begin
  Writeln('Clicking the [x] close mark dismisses without selecting');
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief);
    R := Ctrl.Bounds;
    BtnX := R.Right - 3; // matches WindowFrameCloseHit's own '[x]' math

    Handled := Ctrl.HandleClick(BtnX, R.Top);
    Expect(Handled, 'click on the close mark is handled');
    Expect(Spy.Count = 0, 'close mark never fires OnColumnModeSelect');
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
    TestOpenPicksCurrentModeIndex;
    TestArrowNavigationClampsNoWrap;
    TestNumericShortcutSelectsRegardlessOfCursor;
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
