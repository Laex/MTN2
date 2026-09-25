program TestTopMenuBar;

{$APPTYPE CONSOLE}

{ Characterization tests for StringToTopMenuAction (uTopMenuBar.pas) --
  previously untested and, until this refactor, a hand-written ~90-line
  chain of "if AName = 'tmaXxx' then Exit(tmaXxx)" comparisons (one per
  TTopMenuAction member) that could silently drift out of sync with the
  enum. Now RTTI-driven (GetEnumValue + an exact-case GetEnumName
  round-trip) -- this test exercises every enum member by name via RTTI
  itself, so it stays correct even as menu actions are added later. }

uses
  System.SysUtils, System.TypInfo,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uThemeDrawing in '..\..\Core\uThemeDrawing.pas',
  uDualPanelTypes in '..\..\Core\uDualPanelTypes.pas',
  uDualPanelOverlays in '..\..\Core\uDualPanelOverlays.pas',
  uTopMenuBar in '..\..\Core\uTopMenuBar.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

procedure TestEveryEnumMemberRoundTrips;
var
  A: TTopMenuAction;
  Name: string;
  N: Integer;
begin
  Writeln('Every TTopMenuAction member round-trips through its own name');
  N := 0;
  for A := Low(TTopMenuAction) to High(TTopMenuAction) do
  begin
    Name := GetEnumName(TypeInfo(TTopMenuAction), Ord(A));
    Expect(StringToTopMenuAction(Name) = A,
      Format('%s (ordinal %d) round-trips', [Name, Ord(A)]));
    Inc(N);
  end;
  Writeln('  (', N, ' enum members checked)');
end;

procedure TestUnknownAndMalformedNames;
begin
  Writeln('Unknown / malformed names fall back to tmaNone');
  Expect(StringToTopMenuAction('') = tmaNone, 'empty string');
  Expect(StringToTopMenuAction('tmaDoesNotExist') = tmaNone, 'a plausible but nonexistent name');
  Expect(StringToTopMenuAction('FileCopy') = tmaNone, 'missing the "tma" prefix');
  Expect(StringToTopMenuAction('tmafilecopy') = tmaNone,
    'wrong case is rejected (exact-case match, not GetEnumValue''s case-insensitive default)');
  Expect(StringToTopMenuAction('TMAFILECOPY') = tmaNone, 'all-caps is rejected');
  Expect(StringToTopMenuAction('tmaFileCopy ') = tmaNone, 'trailing space is rejected');
  Expect(StringToTopMenuAction(' tmaFileCopy') = tmaNone, 'leading space is rejected');
end;

procedure TestASampleOfKnownMappings;
begin
  // Spot-check a few concrete mappings the old 90-line chain hard-coded,
  // as a readable cross-check independent of the exhaustive RTTI loop above.
  Writeln('Spot-check known name -> action mappings');
  Expect(StringToTopMenuAction('tmaLeftDrive') = tmaLeftDrive, 'tmaLeftDrive');
  Expect(StringToTopMenuAction('tmaFileMkDir') = tmaFileMkDir, 'tmaFileMkDir');
  Expect(StringToTopMenuAction('tmaCmdSyncConsoleDir') = tmaCmdSyncConsoleDir, 'tmaCmdSyncConsoleDir');
  Expect(StringToTopMenuAction('tmaEditHexToggle') = tmaEditHexToggle, 'tmaEditHexToggle');
  Expect(StringToTopMenuAction('tmaOptResetZoom') = tmaOptResetZoom, 'tmaOptResetZoom');
  Expect(StringToTopMenuAction('tmaQuit') = tmaQuit, 'tmaQuit');
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
  Writeln('HandleClick: top-bar row routes by column, submenu row routes by geometry');
  C := MakeController;
  try
    // Row 0, column 1 always lands in the first category's leading space,
    // regardless of that category's actual title text.
    Expect(C.HandleClick(1, 0), 'clicking the first category on the top bar is handled');
    Expect(C.Active, 'that click activates the menu');
    Expect(C.CategoryIndex = 0, 'and selects category 0');
    Expect(C.SubmenuOpen, 'opening a top-bar category also opens its submenu');
    Expect(GInvalidateCount > 0, 'activating invalidates the view');

    // Clicking the same already-open category again toggles it closed
    // (see HandleTopBarClick: FActive and FCategoryIndex=I and FSubmenuOpen).
    Expect(C.HandleClick(1, 0), 'clicking the open category again is handled');
    Expect(not C.Active, 'and closes the menu');

    // A column past every category''s title falls through the whole loop.
    C.ActivateMenu(0, True);
    Expect(C.HandleClick(100000, 0), 'clicking past the last category on the top bar is handled');
    Expect(not C.Active, 'and closes the menu (no category matched)');

    // A click on a submenu row while no menu is active/open is unhandled.
    C.DeactivateMenu;
    Expect(not C.HandleClick(5, 3), 'a non-top-bar click while inactive is unhandled');

    // Once open, a click outside the (never-laid-out, empty) submenu bounds
    // closes the menu -- HandleSubmenuClick's "outside" branch.
    C.ActivateMenu(0, True);
    Expect(C.HandleClick(5, 3), 'a submenu-row click while open is handled');
    Expect(not C.Active, 'clicking outside the submenu''s bounds closes it');
  finally
    C.Free;
  end;
end;

begin
  try
    TestEveryEnumMemberRoundTrips;
    TestUnknownAndMalformedNames;
    TestASampleOfKnownMappings;
    TestHandleClickRouting;
    Writeln('All TopMenuBar tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
