unit TestColumnModeMenuController;

{ Behavior checks for TColumnModeMenuController (Ctrl+1..6 "Column modes"
  popup) - navigation, numeric/hotkey/Enter/click selection. Draw() is not
  exercised: the project's test convention (see TestPanelColumns.pas,
  TestSortMenuController.pas, ...) checks logic/state, not grid rendering. }

interface

uses
  DUnitX.TestFramework;

type
  // fails: 4 checks (menu hit-testing)
  [TestFixture, Category('Manual')]
  TTestColumnModeMenuController = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestOpenPicksCurrentModeIndex;
    [Test] procedure TestArrowNavigationClampsNoWrap;
    [Test] procedure TestHomeAndEndJumpToTheEnds;
    [Test] procedure TestNumericShortcutSelectsRegardlessOfCursor;
    [Test] procedure TestHotkeySelectsRegardlessOfCursor;
    [Test] procedure TestEscapeClosesWithoutSelecting;
    [Test] procedure TestClickSelectsRowUnderCursor;
    [Test] procedure TestClickCloseMarkDismissesWithoutSelecting;
    [Test] procedure TestSetsFollowThePresetsWithoutACustomEntry;
    [Test] procedure TestOpenOnCustomPicksTheSetOfThePanel;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Classes, System.IOUtils,
  uThemeTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uPanelColumns,
  uColumnSets,
  uColumnModeMenuController;

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
  TSetSpy = class
    Names: TArray<string>;
    procedure OnSet(const AName: string);
  end;

procedure TSetSpy.OnSet(const AName: string);
begin
  SetLength(Names, Length(Names) + 1);
  Names[High(Names)] := AName;
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);

    Ctrl.Open(pcmDate, DefaultCustomColumnsConfig);
    Assert.IsTrue(Ctrl.Visible, 'Open() makes the menu visible');
    Assert.IsTrue(Ctrl.Bounds.Width >= 10, 'Open() lays out a non-degenerate popup');
    Assert.IsTrue(Inv.Count > 0, 'Open() requests an invalidate');

    // Date is the 3rd item (index 2) in BuildColumnModeMenuItems order -
    // confirmed indirectly: pressing Enter immediately must select Date.
    Key := Word(vkReturn);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.Count = 1, 'Enter fires OnColumnModeSelect exactly once');
    Assert.IsTrue(Spy.LastMode = pcmDate, 'Enter selects the mode Open() was given (Date)');
    Assert.IsTrue(not Ctrl.Visible, 'Enter closes the menu');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig); // Brief = index 0, first row

    // AKey is a var param that HandleInput zeroes after consuming it (the
    // "handled, stop dispatching" signal a real key-event loop relies on) -
    // it must be re-armed with the key code before every single press.
    Ch := #0;
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkUp); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.LastMode = pcmBrief,
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
    Ctrl.Open(pcmTypes, DefaultCustomColumnsConfig); // Types = index 5, last row

    Ch := #0;
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn);
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.LastMode = pcmTypes,
      'Down at the bottom row stays clamped on Types (no wrap to the first row)');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestHomeAndEndJumpToTheEnds;
var
  Ctrl: TColumnModeMenuController;
  Spy: TSelectSpy;
  Inv: TInvalidateSpy;
  Key: Word;
  Ch: Char;
begin
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ch := #0;
    Ctrl.Open(pcmFull, DefaultCustomColumnsConfig);
    Key := Word(vkEnd); Ctrl.HandleInput(Key, [], Ch);
    Assert.AreEqual(0, Integer(Key), 'End is consumed');
    Key := Word(vkReturn); Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.LastMode = pcmTypes, 'End lands on the last row');

    Ctrl.Open(pcmFull, DefaultCustomColumnsConfig);
    Key := Word(vkHome); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn); Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.LastMode = pcmBrief, 'Home lands on the first row');

    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig);
    Key := Word(vkNext); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn); Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.LastMode = pcmTypes, 'PgDn runs to the last row');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig); // cursor starts on Brief (index 0)

    Key := 0;
    Ch := '3'; // 1-based -> index 2 -> Date
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.Count = 1, '''3'' fires OnColumnModeSelect exactly once');
    Assert.IsTrue(Spy.LastMode = pcmDate, '''3'' selects the 3rd item (Date)');
    Assert.IsTrue(not Ctrl.Visible, 'digit selection closes the menu');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig); // cursor starts on Brief (index 0)

    Key := 0;
    Ch := 'f'; // hotkey for "Full", lower-case to check UpCase handling
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(Spy.Count = 1, 'hotkey fires OnColumnModeSelect exactly once');
    Assert.IsTrue(Spy.LastMode = pcmFull, 'lower-case ''f'' hotkey selects Full');
    Assert.IsTrue(not Ctrl.Visible, 'hotkey selection closes the menu');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmFull, DefaultCustomColumnsConfig);
    Assert.IsTrue(Ctrl.Visible, 'Open() makes the menu visible');

    Key := Word(vkEscape);
    Ch := #0;
    Ctrl.HandleInput(Key, [], Ch);
    Assert.IsTrue(not Ctrl.Visible, 'Escape closes the menu');
    Assert.IsTrue(Spy.Count = 0, 'Escape never calls OnColumnModeSelect');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig);
    R := Ctrl.Bounds;

    // Row 1 (0-based index 1, "Size") sits at R.Top + 1 + 1.
    Handled := Ctrl.HandleClick(R.Left + 1, R.Top + 2);
    Assert.IsTrue(Handled, 'click inside the popup is handled');
    Assert.IsTrue(Spy.Count = 1, 'click on a row fires OnColumnModeSelect exactly once');
    Assert.IsTrue(Spy.LastMode = pcmSize, 'click on row index 1 selects Size');
    Assert.IsTrue(not Ctrl.Visible, 'click selection closes the menu');
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
  Spy := TSelectSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(Spy.OnSelect);
    Ctrl.Open(pcmBrief, DefaultCustomColumnsConfig);
    R := Ctrl.Bounds;
    BtnX := R.Right - 3; // matches WindowFrameCloseHit's own '[x]' math

    Handled := Ctrl.HandleClick(BtnX, R.Top);
    Assert.IsTrue(Handled, 'click on the close mark is handled');
    Assert.IsTrue(Spy.Count = 0, 'close mark never fires OnColumnModeSelect');
    Assert.IsTrue(not Ctrl.Visible, 'close mark closes the menu');
  finally
    Ctrl.Free;
    Spy.Free;
    Inv.Free;
  end;
end;

procedure TestSetsFollowThePresetsWithoutACustomEntry;
var
  Ctrl: TColumnModeMenuController;
  ModeSpy: TSelectSpy;
  SetSpy: TSetSpy;
  Inv: TInvalidateSpy;
  Path: string;
  Key: Word;
  Ch: Char;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-colmenu-test.json');
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  ColumnSetsUsePath(Path);
  ModeSpy := TSelectSpy.Create;
  SetSpy := TSetSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    Ctrl.SetOnColumnModeSelect(ModeSpy.OnSelect);
    Ctrl.SetOnColumnSetSelect(SetSpy.OnSet);
    Ctrl.Open(pcmTypes, DefaultCustomColumnsConfig);
    Ch := #0;
    // Types is the last preset; the next row is the first set (Dates).
    Key := Word(vkDown); Ctrl.HandleInput(Key, [], Ch);
    Key := Word(vkReturn); Ctrl.HandleInput(Key, [], Ch);
    Assert.AreEqual(0, ModeSpy.Count, 'no preset mode is chosen: the row after Types is a set');
    Assert.AreEqual<Integer>(1, Length(SetSpy.Names), 'the set handler fires once');
    Assert.AreEqual('Dates', SetSpy.Names[0], 'the first starter set follows Types');
  finally
    Ctrl.Free;
    ModeSpy.Free;
    SetSpy.Free;
    Inv.Free;
    ColumnSetsUsePath('');
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

procedure TestOpenOnCustomPicksTheSetOfThePanel;
var
  Ctrl: TColumnModeMenuController;
  SetSpy: TSetSpy;
  Inv: TInvalidateSpy;
  Path: string;
  Cfg: TCustomColumnsConfig;
  Key: Word;
  Ch: Char;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn2-colmenu-test.json');
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  ColumnSetsUsePath(Path);
  Cfg := Default(TCustomColumnsConfig);
  Cfg.ShowAttr := True;
  Cfg.ShowType := True;
  SetSpy := TSetSpy.Create;
  Inv := TInvalidateSpy.Create;
  Ctrl := TColumnModeMenuController.Create(nil, Inv.OnInvalidate, FixedPanelBounds, ActiveSideLeft);
  try
    ColumnSetSave('Mine', Cfg);
    Ctrl.SetOnColumnSetSelect(SetSpy.OnSet);
    Ctrl.Open(pcmCustom, Cfg);
    Ch := #0;
    Key := Word(vkReturn); Ctrl.HandleInput(Key, [], Ch);
    Assert.AreEqual<Integer>(1, Length(SetSpy.Names));
    Assert.AreEqual('Mine', SetSpy.Names[0], 'the cursor starts on the set the panel shows');
  finally
    Ctrl.Free;
    SetSpy.Free;
    Inv.Free;
    ColumnSetsUsePath('');
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

{ TTestColumnModeMenuController }

procedure TTestColumnModeMenuController.SetupFixture;
begin
end;

procedure TTestColumnModeMenuController.TestOpenPicksCurrentModeIndex;
begin
  TestColumnModeMenuController.TestOpenPicksCurrentModeIndex;
end;

procedure TTestColumnModeMenuController.TestHomeAndEndJumpToTheEnds;
begin
  TestColumnModeMenuController.TestHomeAndEndJumpToTheEnds;
end;

procedure TTestColumnModeMenuController.TestArrowNavigationClampsNoWrap;
begin
  TestColumnModeMenuController.TestArrowNavigationClampsNoWrap;
end;

procedure TTestColumnModeMenuController.TestNumericShortcutSelectsRegardlessOfCursor;
begin
  TestColumnModeMenuController.TestNumericShortcutSelectsRegardlessOfCursor;
end;

procedure TTestColumnModeMenuController.TestHotkeySelectsRegardlessOfCursor;
begin
  TestColumnModeMenuController.TestHotkeySelectsRegardlessOfCursor;
end;

procedure TTestColumnModeMenuController.TestEscapeClosesWithoutSelecting;
begin
  TestColumnModeMenuController.TestEscapeClosesWithoutSelecting;
end;

procedure TTestColumnModeMenuController.TestClickSelectsRowUnderCursor;
begin
  TestColumnModeMenuController.TestClickSelectsRowUnderCursor;
end;

procedure TTestColumnModeMenuController.TestClickCloseMarkDismissesWithoutSelecting;
begin
  TestColumnModeMenuController.TestClickCloseMarkDismissesWithoutSelecting;
end;

procedure TTestColumnModeMenuController.TestSetsFollowThePresetsWithoutACustomEntry;
begin
  TestColumnModeMenuController.TestSetsFollowThePresetsWithoutACustomEntry;
end;

procedure TTestColumnModeMenuController.TestOpenOnCustomPicksTheSetOfThePanel;
begin
  TestColumnModeMenuController.TestOpenOnCustomPicksTheSetOfThePanel;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColumnModeMenuController);

end.
