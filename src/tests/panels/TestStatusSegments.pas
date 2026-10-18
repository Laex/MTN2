unit TestStatusSegments;

{ A click on a section of the status line: which section a column falls in,
  what the sections of a panel line are, and that the click reaches the host
  only on the status row with no dialog in the way. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStatusSegments = class
  public
    [Test] procedure ThemedSectionsAreSeparatedByThreeCells;
    [Test] procedure PlainSectionsAreSeparatedByTwoCells;
    [Test] procedure PanelSectionsFollowTheLineLayout;
    [Test] procedure ClickOnTheStatusRowReachesTheHost;
    [Test] procedure ClickIsNotTakenWhileADialogIsOpen;
  end;

implementation

uses
  System.SysUtils, System.Classes, uStatusSegments, uDualPanelClick, uDualPanelUiTypes, uDualPanelTypes, uChromeRows;

type
  TStatusSpy = class
  public
    Col: Integer;
    Calls: Integer;
    function OnStatus(ACol: Integer; AShift: TShiftState): Boolean;
    function OnDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
  end;

function TStatusSpy.OnStatus(ACol: Integer; AShift: TShiftState): Boolean;
begin
  Inc(Calls);
  Col := ACol;
  Result := True;
end;

function TStatusSpy.OnDialog(ACol, ARow: Integer; AShift: TShiftState): Boolean;
begin
  Result := True;
end;

procedure TTestStatusSegments.ThemedSectionsAreSeparatedByThreeCells;
var
  Segs: TArray<string>;
begin
  Segs := ['Left', 'C:\x', '1/3'];
  // 'Left' covers columns 1..4, ' | ' columns 5..7, 'C:\x' columns 8..11.
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 0, True), 'left margin');
  Assert.AreEqual(0, StatusSegmentAt(Segs, 1, True));
  Assert.AreEqual(0, StatusSegmentAt(Segs, 4, True));
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 5, True), 'separator');
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 7, True), 'separator');
  Assert.AreEqual(1, StatusSegmentAt(Segs, 8, True));
  Assert.AreEqual(1, StatusSegmentAt(Segs, 11, True));
  Assert.AreEqual(2, StatusSegmentAt(Segs, 15, True));
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 40, True), 'past the last section');
end;

procedure TTestStatusSegments.PlainSectionsAreSeparatedByTwoCells;
var
  Segs: TArray<string>;
begin
  Segs := ['Left', 'Path'];
  Assert.AreEqual(0, StatusSegmentAt(Segs, 4, False));
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 5, False), 'gap');
  Assert.AreEqual(-1, StatusSegmentAt(Segs, 6, False), 'gap');
  Assert.AreEqual(1, StatusSegmentAt(Segs, 7, False));
end;

procedure TTestStatusSegments.PanelSectionsFollowTheLineLayout;
var
  K: TArray<TStatusSegKind>;
begin
  K := PanelStatusKinds(True, True, False, True, True);
  Assert.AreEqual<Integer>(6, Length(K));
  Assert.IsTrue(K[0] = sskSide);
  Assert.IsTrue(K[1] = sskPath);
  Assert.IsTrue(K[2] = sskPosition);
  Assert.IsTrue(K[3] = sskColumnMode);
  Assert.IsTrue(K[4] = sskItem);
  Assert.IsTrue(K[5] = sskFree);

  K := PanelStatusKinds(False, True, False, False, False);
  Assert.AreEqual<Integer>(3, Length(K), 'no column mode off the panels, no item, no free space');

  K := PanelStatusKinds(True, True, True, True, True);
  Assert.IsTrue(K[4] = sskNone, 'the command line marker replaces the item');
  Assert.IsTrue(K[5] = sskFree);
end;

procedure TTestStatusSegments.ClickOnTheStatusRowReachesTheHost;
var
  Spy: TStatusSpy;
  Host: TDualPanelClickHost;
  Snap: TClickOverlaySnapshot;
  Handled: Boolean;
begin
  Spy := TStatusSpy.Create;
  try
    Host := Default(TDualPanelClickHost);
    Host.HandleStatusLineClick := Spy.OnStatus;
    Snap := Default(TClickOverlaySnapshot);
    Snap.WorkspaceKind := wkPanels;
    Snap.AreaHeight := 24;
    Snap.AreaWidth := 80;
    Assert.IsTrue(DispatchClickOverlays(Host, Snap, 12, StatusLineRow(24), [], False, Handled));
    Assert.AreEqual(1, Spy.Calls);
    Assert.AreEqual(12, Spy.Col);
    Assert.IsTrue(Handled);
  finally
    Spy.Free;
  end;
end;

procedure TTestStatusSegments.ClickIsNotTakenWhileADialogIsOpen;
var
  Spy: TStatusSpy;
  Host: TDualPanelClickHost;
  Snap: TClickOverlaySnapshot;
  Handled: Boolean;
begin
  Spy := TStatusSpy.Create;
  try
    Host := Default(TDualPanelClickHost);
    Host.HandleStatusLineClick := Spy.OnStatus;
    Host.HandleDialogClick := Spy.OnDialog;
    Snap := Default(TClickOverlaySnapshot);
    Snap.WorkspaceKind := wkPanels;
    Snap.AreaHeight := 24;
    Snap.AreaWidth := 80;
    Snap.DialogVisible := True;
    DispatchClickOverlays(Host, Snap, 12, StatusLineRow(24), [], False, Handled);
    Assert.AreEqual(0, Spy.Calls, 'the dialog owns the click');
  finally
    Spy.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStatusSegments);

end.
