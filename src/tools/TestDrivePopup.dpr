program TestDrivePopup;

{$APPTYPE CONSOLE}

{ Characterization tests for TDrivePopupController (Alt+F1/F2 Change Drive
  overlay, uDualPanelDrivePopup.pas) — previously untested. Exercises the
  pure controller logic (Layout's width/height clamping, keyboard/mouse
  dispatch, Confirm's navigation) via injected callbacks, without touching
  the FMX grid (Draw is not exercised here).

  The real drive list comes from CachedDriveInfo (actual OS drives), so
  assertions are written to hold regardless of how many drives the test
  machine has — layout tests use panel sizes small/large enough that the
  drive count cannot change the outcome, and shortcut tests only rely on
  ChangeDriveSpecialUris (fixed constants) or the near-universal presence of
  a C: drive on Windows. }

uses
  System.SysUtils, System.UITypes, Winapi.Windows,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uThemeDrawing in '..\Core\uThemeDrawing.pas',
  uVfsTypes in '..\Core\uVfsTypes.pas',
  uDualPanelTypes in '..\Core\uDualPanelTypes.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uDualPanelOverlays in '..\Core\uDualPanelOverlays.pas',
  uDriveInfo in '..\Core\uDriveInfo.pas',
  uDualPanelDrawUtils in '..\Core\uDualPanelDrawUtils.pas',
  uDualPanelDrivePopup in '..\Core\uDualPanelDrivePopup.pas';

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if not ACond then
    raise Exception.Create(AMsg);
  Writeln('  OK  ', AMsg);
end;

var
  GNavCalled: Boolean;
  GNavSide: TPanelSide;
  GNavUri: string;
  GInvalidateCount: Integer;

function MakeController(const APanelBounds: TRectI): TDrivePopupController;
begin
  GNavCalled := False;
  GNavUri := '';
  GInvalidateCount := 0;
  Result := TDrivePopupController.Create(nil,
    procedure
    begin
      Inc(GInvalidateCount);
    end,
    function(ASide: TPanelSide): TRectI
    begin
      Result := APanelBounds;
    end,
    function(ASide: TPanelSide): string
    begin
      Result := '';
    end,
    function(ASide: TPanelSide): TPanelDriveDirs
    begin
      // Left all-empty on purpose: ResolvePanelDriveUri then falls back to
      // the drive's own RootPath, which the letter-shortcut test relies on.
    end,
    procedure(ASide: TPanelSide; const AURI: string)
    begin
      GNavCalled := True;
      GNavSide := ASide;
      GNavUri := AURI;
    end);
end;

procedure TestLayoutTinyPanel;
var
  C: TDrivePopupController;
begin
  Writeln('Layout: tiny panel clamps both width and height');
  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    Expect(C.Visible, 'popup opens');
    Expect(C.Bounds.Left = 1, 'left clamped to 1');
    Expect(C.Bounds.Top = 1, 'top clamped to 1');
    Expect(C.Bounds.Width = 39, 'width narrowed to fit (39)');
    Expect(C.Bounds.Height = 5, 'height clamped to PanelBounds.Height-1 (5)');
  finally
    C.Free;
  end;
end;

procedure TestLayoutWidthClamps;
var
  C: TDrivePopupController;
begin
  Writeln('Layout: width clamps hold regardless of drive count');
  C := MakeController(TRectI.Make(0, 0, 199, 99));
  try
    C.Open(psLeft);
    Expect(C.Bounds.Width = 72, 'wide panel caps popup width at 72');
  finally
    C.Free;
  end;

  C := MakeController(TRectI.Make(0, 0, 29, 50));
  try
    C.Open(psLeft);
    Expect(C.Bounds.Width = 29, 'narrow panel shrinks popup to fit (29)');
  finally
    C.Free;
  end;
end;

procedure TestToggleAndEscape;
var
  C: TDrivePopupController;
  Key: Word;
  KeyChar: Char;
begin
  Writeln('Toggle / Escape');
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    Expect(not C.Visible, 'starts hidden');
    C.Toggle(psLeft);
    Expect(C.Visible, 'toggle opens');
    Expect(C.Side = psLeft, 'opened on the requested side');
    C.Toggle(psLeft);
    Expect(not C.Visible, 'toggle again (same side) closes');

    C.Toggle(psRight);
    Expect(C.Visible and (C.Side = psRight), 'toggle on the other side opens there');

    Key := vkEscape;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Expect(not C.Visible, 'Escape closes the popup');
    Expect(Key = 0, 'Escape consumes the key');
  finally
    C.Free;
  end;
end;

procedure TestDigitShortcuts;
var
  C: TDrivePopupController;
  Key: Word;
  KeyChar: Char;
  I: Integer;
begin
  Writeln('Digit shortcuts 1..4 jump straight to the special items and confirm');
  for I := 0 to ChangeDriveSpecialCount - 1 do
  begin
    C := MakeController(TRectI.Make(0, 0, 79, 24));
    try
      C.Open(psLeft);
      Key := 0;
      KeyChar := Chr(Ord('1') + I);
      C.HandleInput(Key, [], KeyChar);
      Expect(GNavCalled, Format('digit %d triggers navigation', [I + 1]));
      Expect(GNavSide = psLeft, Format('digit %d navigates on the opened side', [I + 1]));
      Expect(GNavUri = ChangeDriveSpecialUris[I],
        Format('digit %d navigates to %s', [I + 1, ChangeDriveSpecialUris[I]]));
      Expect(not C.Visible, Format('digit %d closes the popup', [I + 1]));
    finally
      C.Free;
    end;
  end;
end;

procedure TestLetterShortcut;
var
  C: TDrivePopupController;
  Key: Word;
  KeyChar: Char;
  ExpectedUri: string;
begin
  Writeln('Letter shortcut navigates to the matching drive (assumes C: exists)');
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := 0;
    KeyChar := 'C';
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavCalled, 'C key triggers navigation');
    ExpectedUri := PathToFileUri('C:' + PathDelim);
    Expect(GNavUri = ExpectedUri, 'C key navigates to C:\ as a file URI');
    Expect(not C.Visible, 'C key closes the popup');
  finally
    C.Free;
  end;
end;

procedure TestCursorMovement;
var
  C: TDrivePopupController;
  Key: Word;
  KeyChar: Char;
  Drives: TDriveInfoArray;
  DriveCount, I: Integer;
begin
  Writeln('HandleInput: Home/End/Up-wrap/Down-skip-separator (drive list learned live)');
  Drives := CachedDriveInfo(nil);
  DriveCount := Length(Drives);
  Expect(DriveCount > 0, 'test machine has at least one drive');

  // Home -> first drive in CachedDriveInfo's own order.
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := vkHome;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavCalled, 'Home + Enter navigates');
    Expect(GNavUri = PathToFileUri(Drives[0].RootPath),
      'Home lands on the first drive in CachedDriveInfo''s order');
  finally
    C.Free;
  end;

  // End -> last special item (index Length(Drives) + ChangeDriveSpecialCount).
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := vkEnd;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavCalled, 'End + Enter navigates');
    Expect(GNavUri = ChangeDriveSpecialUris[ChangeDriveSpecialCount - 1],
      'End lands on the last special item');
  finally
    C.Free;
  end;

  // Up from Home (index 0) wraps to the very last item (same spot as End).
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := vkHome;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Key := vkUp;
    C.HandleInput(Key, [], KeyChar);
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavUri = ChangeDriveSpecialUris[ChangeDriveSpecialCount - 1],
      'Up from the first item wraps around to the last item');
  finally
    C.Free;
  end;

  // Down DriveCount times from Home (index 0) must skip the separator line
  // and land exactly on the first special item, regardless of drive count.
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := vkHome;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    for I := 1 to DriveCount do
    begin
      Key := vkDown;
      C.HandleInput(Key, [], KeyChar);
    end;
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavUri = ChangeDriveSpecialUris[0],
      'Down past the last drive skips the separator and lands on the first special item');
  finally
    C.Free;
  end;
end;

procedure TestHandleClickScrollbar;
var
  C: TDrivePopupController;
  Drives: TDriveInfoArray;
  Key: Word;
  KeyChar: Char;
  ListTop, ScrollX: Integer;
begin
  Writeln('HandleClick: scrollbar top arrow moves the cursor like Up/PageUp');
  Drives := CachedDriveInfo(nil);
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    // Home first, then Down once so the top-arrow click has somewhere to go
    // back to (clicking it at index 0 would just stay put, per the "if
    // CursorIndex > 0" guard) -- reuses the already-verified Down semantics.
    Key := vkHome;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Key := vkDown;
    C.HandleInput(Key, [], KeyChar);
    ListTop := C.Bounds.Top + 1;
    ScrollX := C.Bounds.Right - 1;
    C.HandleClick(ScrollX, ListTop);
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Expect(GNavCalled, 'scrollbar top-arrow click, then Enter, navigates');
    Expect(GNavUri = PathToFileUri(Drives[0].RootPath),
      'scrollbar top-arrow click moved the cursor back up one step');
  finally
    C.Free;
  end;
end;

procedure TestHandleClickCloseAndOutside;
var
  C: TDrivePopupController;
begin
  Writeln('HandleClick: close button and clicking outside both close the popup');
  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    // Bounds is (1,1) .. (39,5) per TestLayoutTinyPanel above; the close mark
    // sits at (Right-2 .. Right-1, Top) per WindowFrameCloseHit.
    C.HandleClick(C.Bounds.Right - 2, C.Bounds.Top);
    Expect(not C.Visible, 'clicking the close mark closes the popup');
  finally
    C.Free;
  end;

  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    C.HandleClick(0, 0);
    Expect(not C.Visible, 'clicking outside the popup bounds closes it');
  finally
    C.Free;
  end;
end;

begin
  try
    TestLayoutTinyPanel;
    TestLayoutWidthClamps;
    TestToggleAndEscape;
    TestDigitShortcuts;
    TestLetterShortcut;
    TestCursorMovement;
    TestHandleClickScrollbar;
    TestHandleClickCloseAndOutside;
    // Every Open() above kicked off CachedDriveInfo's real (fire-and-forget)
    // background workers -- one GetVolumeInformation/GetDiskFreeSpaceEx call
    // per drive letter, queued to fire a callback on a controller that may
    // already be freed. They're normally harmless because a GUI's message
    // loop keeps running long after, but this console test exits right after
    // its last assertion; give them a moment to finish before the process
    // tears down under them.
    Sleep(1500);
    Writeln('All DrivePopup tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
