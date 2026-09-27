unit TestDrivePopup;

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

interface

uses
  DUnitX.TestFramework;

type
  // slow (~20s): waits on drive detail, long on unreachable network drives
  [TestFixture, Category('Manual')]
  TTestDrivePopup = class
  public
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestLayoutTinyPanel;
    [Test] procedure TestLayoutWidthClamps;
    [Test] procedure TestToggleAndEscape;
    [Test] procedure TestDigitShortcuts;
    [Test] procedure TestLetterShortcut;
    [Test] procedure TestCursorMovement;
    [Test] procedure TestHandleClickScrollbar;
    [Test] procedure TestHandleClickCloseAndOutside;
  end;

implementation

uses
  System.SysUtils, System.UITypes, Winapi.Windows,
  uTerminalTypes,
  uThemeTypes,
  uThemeDrawing,
  uVfsTypes,
  uDualPanelTypes,
  uDualPanelUiTypes,
  uDualPanelOverlays,
  uDriveInfo,
  uDualPanelDrawUtils,
  uDualPanelDrivePopup;

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
  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    Assert.IsTrue(C.Visible, 'popup opens');
    Assert.IsTrue(C.Bounds.Left = 1, 'left clamped to 1');
    Assert.IsTrue(C.Bounds.Top = 1, 'top clamped to 1');
    Assert.IsTrue(C.Bounds.Width = 39, 'width narrowed to fit (39)');
    Assert.IsTrue(C.Bounds.Height = 5, 'height clamped to PanelBounds.Height-1 (5)');
  finally
    C.Free;
  end;
end;

procedure TestLayoutWidthClamps;
var
  C: TDrivePopupController;
begin
  C := MakeController(TRectI.Make(0, 0, 199, 99));
  try
    C.Open(psLeft);
    Assert.IsTrue(C.Bounds.Width = 72, 'wide panel caps popup width at 72');
  finally
    C.Free;
  end;

  C := MakeController(TRectI.Make(0, 0, 29, 50));
  try
    C.Open(psLeft);
    Assert.IsTrue(C.Bounds.Width = 29, 'narrow panel shrinks popup to fit (29)');
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
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    Assert.IsTrue(not C.Visible, 'starts hidden');
    C.Toggle(psLeft);
    Assert.IsTrue(C.Visible, 'toggle opens');
    Assert.IsTrue(C.Side = psLeft, 'opened on the requested side');
    C.Toggle(psLeft);
    Assert.IsTrue(not C.Visible, 'toggle again (same side) closes');

    C.Toggle(psRight);
    Assert.IsTrue(C.Visible and (C.Side = psRight), 'toggle on the other side opens there');

    Key := vkEscape;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Assert.IsTrue(not C.Visible, 'Escape closes the popup');
    Assert.IsTrue(Key = 0, 'Escape consumes the key');
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
  for I := 0 to ChangeDriveSpecialCount - 1 do
  begin
    C := MakeController(TRectI.Make(0, 0, 79, 24));
    try
      C.Open(psLeft);
      Key := 0;
      KeyChar := Chr(Ord('1') + I);
      C.HandleInput(Key, [], KeyChar);
      Assert.IsTrue(GNavCalled, Format('digit %d triggers navigation', [I + 1]));
      Assert.IsTrue(GNavSide = psLeft, Format('digit %d navigates on the opened side', [I + 1]));
      Assert.IsTrue(GNavUri = ChangeDriveSpecialUris[I],
        Format('digit %d navigates to %s', [I + 1, ChangeDriveSpecialUris[I]]));
      Assert.IsTrue(not C.Visible, Format('digit %d closes the popup', [I + 1]));
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
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := 0;
    KeyChar := 'C';
    C.HandleInput(Key, [], KeyChar);
    Assert.IsTrue(GNavCalled, 'C key triggers navigation');
    ExpectedUri := PathToFileUri('C:' + PathDelim);
    Assert.IsTrue(GNavUri = ExpectedUri, 'C key navigates to C:\ as a file URI');
    Assert.IsTrue(not C.Visible, 'C key closes the popup');
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
  Drives := CachedDriveInfo(nil);
  DriveCount := Length(Drives);
  Assert.IsTrue(DriveCount > 0, 'test machine has at least one drive');

  // Home -> first drive in CachedDriveInfo's own order.
  C := MakeController(TRectI.Make(0, 0, 79, 24));
  try
    C.Open(psLeft);
    Key := vkHome;
    KeyChar := #0;
    C.HandleInput(Key, [], KeyChar);
    Key := vkReturn;
    C.HandleInput(Key, [], KeyChar);
    Assert.IsTrue(GNavCalled, 'Home + Enter navigates');
    Assert.IsTrue(GNavUri = PathToFileUri(Drives[0].RootPath),
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
    Assert.IsTrue(GNavCalled, 'End + Enter navigates');
    Assert.IsTrue(GNavUri = ChangeDriveSpecialUris[ChangeDriveSpecialCount - 1],
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
    Assert.IsTrue(GNavUri = ChangeDriveSpecialUris[ChangeDriveSpecialCount - 1],
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
    Assert.IsTrue(GNavUri = ChangeDriveSpecialUris[0],
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
    Assert.IsTrue(GNavCalled, 'scrollbar top-arrow click, then Enter, navigates');
    Assert.IsTrue(GNavUri = PathToFileUri(Drives[0].RootPath),
      'scrollbar top-arrow click moved the cursor back up one step');
  finally
    C.Free;
  end;
end;

procedure TestHandleClickCloseAndOutside;
var
  C: TDrivePopupController;
begin
  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    // Bounds is (1,1) .. (39,5) per TestLayoutTinyPanel above; the close mark
    // sits at (Right-2 .. Right-1, Top) per WindowFrameCloseHit.
    C.HandleClick(C.Bounds.Right - 2, C.Bounds.Top);
    Assert.IsTrue(not C.Visible, 'clicking the close mark closes the popup');
  finally
    C.Free;
  end;

  C := MakeController(TRectI.Make(0, 0, 39, 5));
  try
    C.Open(psLeft);
    C.HandleClick(0, 0);
    Assert.IsTrue(not C.Visible, 'clicking outside the popup bounds closes it');
  finally
    C.Free;
  end;
end;

{ TTestDrivePopup }

procedure TTestDrivePopup.TearDownFixture;
begin
  Sleep(1500);
end;

procedure TTestDrivePopup.TestLayoutTinyPanel;
begin
  TestDrivePopup.TestLayoutTinyPanel;
end;

procedure TTestDrivePopup.TestLayoutWidthClamps;
begin
  TestDrivePopup.TestLayoutWidthClamps;
end;

procedure TTestDrivePopup.TestToggleAndEscape;
begin
  TestDrivePopup.TestToggleAndEscape;
end;

procedure TTestDrivePopup.TestDigitShortcuts;
begin
  TestDrivePopup.TestDigitShortcuts;
end;

procedure TTestDrivePopup.TestLetterShortcut;
begin
  TestDrivePopup.TestLetterShortcut;
end;

procedure TTestDrivePopup.TestCursorMovement;
begin
  TestDrivePopup.TestCursorMovement;
end;

procedure TTestDrivePopup.TestHandleClickScrollbar;
begin
  TestDrivePopup.TestHandleClickScrollbar;
end;

procedure TTestDrivePopup.TestHandleClickCloseAndOutside;
begin
  TestDrivePopup.TestHandleClickCloseAndOutside;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDrivePopup);

end.
