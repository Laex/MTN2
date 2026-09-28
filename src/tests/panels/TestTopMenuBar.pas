unit TestTopMenuBar;

{ Tests for StringToTopMenuAction (uTopMenuBar.pas), which is RTTI-driven
  (GetEnumValue + an exact-case GetEnumName round-trip). This test exercises
  every TTopMenuAction member by name via RTTI itself, so it stays correct
  as menu actions are added. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTopMenuBar = class
  public
    [Test] procedure TestEveryEnumMemberRoundTrips;
    [Test] procedure TestUnknownAndMalformedNames;
    [Test] procedure TestASampleOfKnownMappings;
    [Test] procedure TestHandleClickRouting;
  end;

implementation

uses
  System.SysUtils, System.TypInfo,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uDualPanelTypes,
  uDualPanelOverlays,
  uTopMenuBar;

procedure TestEveryEnumMemberRoundTrips;
var
  A: TTopMenuAction;
  Name: string;
  N: Integer;
begin
  N := 0;
  for A := Low(TTopMenuAction) to High(TTopMenuAction) do
  begin
    Name := GetEnumName(TypeInfo(TTopMenuAction), Ord(A));
    Assert.IsTrue(StringToTopMenuAction(Name) = A,
      Format('%s (ordinal %d) round-trips', [Name, Ord(A)]));
    Inc(N);
  end;
  Writeln('  (', N, ' enum members checked)');
end;

procedure TestUnknownAndMalformedNames;
begin
  Assert.IsTrue(StringToTopMenuAction('') = tmaNone, 'empty string');
  Assert.IsTrue(StringToTopMenuAction('tmaDoesNotExist') = tmaNone, 'a plausible but nonexistent name');
  Assert.IsTrue(StringToTopMenuAction('FileCopy') = tmaNone, 'missing the "tma" prefix');
  Assert.IsTrue(StringToTopMenuAction('tmafilecopy') = tmaNone,
    'wrong case is rejected (exact-case match, not GetEnumValue''s case-insensitive default)');
  Assert.IsTrue(StringToTopMenuAction('TMAFILECOPY') = tmaNone, 'all-caps is rejected');
  Assert.IsTrue(StringToTopMenuAction('tmaFileCopy ') = tmaNone, 'trailing space is rejected');
  Assert.IsTrue(StringToTopMenuAction(' tmaFileCopy') = tmaNone, 'leading space is rejected');
end;

procedure TestASampleOfKnownMappings;
begin
  // Spot-check a few concrete mappings, as a readable cross-check independent of the exhaustive RTTI loop above.
  Writeln('Spot-check known name -> action mappings');
  Assert.IsTrue(StringToTopMenuAction('tmaLeftDrive') = tmaLeftDrive, 'tmaLeftDrive');
  Assert.IsTrue(StringToTopMenuAction('tmaFileMkDir') = tmaFileMkDir, 'tmaFileMkDir');
  Assert.IsTrue(StringToTopMenuAction('tmaCmdSyncConsoleDir') = tmaCmdSyncConsoleDir, 'tmaCmdSyncConsoleDir');
  Assert.IsTrue(StringToTopMenuAction('tmaEditHexToggle') = tmaEditHexToggle, 'tmaEditHexToggle');
  Assert.IsTrue(StringToTopMenuAction('tmaOptResetZoom') = tmaOptResetZoom, 'tmaOptResetZoom');
  Assert.IsTrue(StringToTopMenuAction('tmaQuit') = tmaQuit, 'tmaQuit');
end;

var
  GInvalidateCount: Integer;
  GExecutedAction: TTopMenuAction;
  GExecutedCount: Integer;

function MakeController: TTopMenuController;
begin
  GInvalidateCount := 0;
  GExecutedAction := tmaNone;
  GExecutedCount := 0;
  Result := TTopMenuController.Create(nil,
    procedure
    begin
      Inc(GInvalidateCount);
    end,
    procedure(AAction: TTopMenuAction)
    begin
      GExecutedAction := AAction;
      Inc(GExecutedCount);
    end);
end;

procedure TestHandleClickRouting;
var
  C: TTopMenuController;
begin
  C := MakeController;
  try
    // Row 0, column 1 always lands in the first category's leading space,
    // regardless of that category's actual title text.
    Assert.IsTrue(C.HandleClick(1, 0), 'clicking the first category on the top bar is handled');
    Assert.IsTrue(C.Active, 'that click activates the menu');
    Assert.IsTrue(C.CategoryIndex = 0, 'and selects category 0');
    Assert.IsTrue(C.SubmenuOpen, 'opening a top-bar category also opens its submenu');
    Assert.IsTrue(GInvalidateCount > 0, 'activating invalidates the view');

    // Clicking the same already-open category again toggles it closed
    // (see HandleTopBarClick: FActive and FCategoryIndex=I and FSubmenuOpen).
    Assert.IsTrue(C.HandleClick(1, 0), 'clicking the open category again is handled');
    Assert.IsTrue(not C.Active, 'and closes the menu');

    // A column past every category''s title falls through the whole loop.
    C.ActivateMenu(0, True);
    Assert.IsTrue(C.HandleClick(100000, 0), 'clicking past the last category on the top bar is handled');
    Assert.IsTrue(not C.Active, 'and closes the menu (no category matched)');

    // A click on a submenu row while no menu is active/open is unhandled.
    C.DeactivateMenu;
    Assert.IsTrue(not C.HandleClick(5, 3), 'a non-top-bar click while inactive is unhandled');

    // Once open, a click outside the (never-laid-out, empty) submenu bounds
    // closes the menu -- HandleSubmenuClick's "outside" branch.
    C.ActivateMenu(0, True);
    Assert.IsTrue(C.HandleClick(5, 3), 'a submenu-row click while open is handled');
    Assert.IsTrue(not C.Active, 'clicking outside the submenu''s bounds closes it');
  finally
    C.Free;
  end;
end;

{ TTestTopMenuBar }

procedure TTestTopMenuBar.TestEveryEnumMemberRoundTrips;
begin
  TestTopMenuBar.TestEveryEnumMemberRoundTrips;
end;

procedure TTestTopMenuBar.TestUnknownAndMalformedNames;
begin
  TestTopMenuBar.TestUnknownAndMalformedNames;
end;

procedure TTestTopMenuBar.TestASampleOfKnownMappings;
begin
  TestTopMenuBar.TestASampleOfKnownMappings;
end;

procedure TTestTopMenuBar.TestHandleClickRouting;
begin
  TestTopMenuBar.TestHandleClickRouting;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTopMenuBar);

end.
