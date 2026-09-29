unit TestChromeRows;

{ Hiding the menu bar, the F-key bar and the status line (uChromeRows):
  the rows move and the panels, a terminal or a document take the freed
  rows; clicks and the toast follow the moved rows. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestChromeRows = class
  public
    [TearDown] procedure TearDown;
    [Test] procedure TestAllShown;
    [Test] procedure TestAllHidden;
    [Test] procedure TestStatusLineOnly;
    [Test] procedure TestPanelLayout;
    [Test] procedure TestMouseDownRows;
  end;

implementation

uses
  uThemeTypes, uDualPanelTypes, uDualPanelPanelDraw, uDualPanelDrag, uToast,
  uChromeRows;

const
  H = 30;

procedure SetRows(AMenu, AKeys, AStatus: Boolean);
begin
  GShowMenuBar := AMenu;
  GShowKeyBar := AKeys;
  GShowStatusLine := AStatus;
end;

procedure TTestChromeRows.TearDown;
begin
  SetRows(True, True, True);
end;

procedure TTestChromeRows.TestAllShown;
begin
  SetRows(True, True, True);
  Assert.AreEqual(1, TabBarRow, 'tabs under the menu');
  Assert.AreEqual(2, ContentTopRow, 'content under the tabs');
  Assert.AreEqual(H - 3, CmdLineRow(H), 'command line');
  Assert.AreEqual(H - 2, KeyBarRow(H), 'F-keys');
  Assert.AreEqual(H - 1, StatusLineRow(H), 'status line');
  Assert.AreEqual(H - 4, EmbeddedTerminalPaintHeight(H), 'terminal between tabs and F-keys');
  Assert.AreEqual(H - 2, EmbeddedDocumentPaintHeight(H), 'document draws its own bottom rows');
  Assert.AreEqual(H - 5, ToastBounds(20, 100, H).Bottom, 'toast above the panel frame');
end;

procedure TTestChromeRows.TestAllHidden;
begin
  SetRows(False, False, False);
  Assert.AreEqual(0, TabBarRow, 'tabs on the top row');
  Assert.AreEqual(1, ContentTopRow, 'content right under the tabs');
  Assert.AreEqual(H - 1, CmdLineRow(H), 'command line on the last row');
  Assert.AreEqual(-1, KeyBarRow(H), 'no F-key row');
  Assert.AreEqual(-1, StatusLineRow(H), 'no status row');
  Assert.AreEqual(0, ChromeBottomRows, 'nothing at the bottom');
  Assert.AreEqual(H - 1, EmbeddedTerminalPaintHeight(H), 'terminal down to the last row');
  Assert.AreEqual(H - 3, ToastBounds(20, 100, H).Bottom, 'toast follows the command line');
end;

procedure TTestChromeRows.TestStatusLineOnly;
begin
  SetRows(True, False, True);
  Assert.AreEqual(-1, KeyBarRow(H), 'no F-key row');
  Assert.AreEqual(H - 1, StatusLineRow(H), 'status line stays last');
  Assert.AreEqual(H - 2, CmdLineRow(H), 'command line right above it');
  SetRows(True, True, False);
  Assert.AreEqual(H - 1, KeyBarRow(H), 'F-keys take the last row');
  Assert.AreEqual(H - 2, CmdLineRow(H), 'command line above the F-keys');
end;

procedure TTestChromeRows.TestPanelLayout;
var
  L, R: TRectI;
  ListTop, ListBottom, ShownTop, ShownBottom: Integer;
begin
  SetRows(True, True, True);
  ComputePanelLayout(100, H, True, True, L, R, ShownTop, ShownBottom);
  Assert.AreEqual(2, L.Top, 'panels under the tabs');
  Assert.AreEqual(H - 4, L.Bottom, 'panels above the command line');

  SetRows(False, False, False);
  ComputePanelLayout(100, H, True, True, L, R, ListTop, ListBottom);
  Assert.AreEqual(1, L.Top, 'panels move up by the menu row');
  Assert.AreEqual(H - 2, L.Bottom, 'panels grow down to the command line');
  Assert.AreEqual(L.Bottom, R.Bottom, 'both panels');
  Assert.AreEqual(ShownTop - 1, ListTop, 'file list moves up');
  Assert.AreEqual(ShownBottom + 2, ListBottom, 'and gains the freed bottom rows');
end;

procedure TTestChromeRows.TestMouseDownRows;
begin
  SetRows(True, True, True);
  Assert.IsTrue(ClassifyMouseDown(0, wkTerminal) = mdtTopMenu, 'row 0 is the menu');
  Assert.IsTrue(ClassifyMouseDown(1, wkTerminal) = mdtWorkspaceTab, 'row 1 is the tabs');
  SetRows(False, True, True);
  Assert.IsTrue(ClassifyMouseDown(0, wkTerminal) = mdtWorkspaceTab,
    'without the menu bar row 0 is the tabs');
  Assert.IsTrue(ClassifyMouseDown(1, wkTerminal) = mdtEmbedded,
    'and row 1 the terminal');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestChromeRows);

end.
