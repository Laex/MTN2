unit TestPanelViewController;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPanelViewController = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelTypes,
  uPanelViewController;

procedure RunTests;
var
  VC: TPanelViewController;
  Rows: TPanelRows;
begin
  VC := TPanelViewController.Create(psLeft);
  try
    Assert.IsTrue(VC.Side = psLeft, 'Side must be psLeft');
    Assert.IsTrue(not VC.PlainTotals.Valid, 'Totals initially invalid');

    SetLength(Rows, 3);
    Rows[0].IsParent := True;
    Rows[1].IsDirectory := True;
    Rows[1].IsParent := False;
    Rows[2].IsDirectory := False;
    Rows[2].IsParent := False;
    Rows[2].Size := 1024;

    VC.RecalculateTotalsIfNeeded(Rows);
    Assert.IsTrue(VC.PlainTotals.Valid, 'Totals valid after recalc');
    Assert.IsTrue(VC.PlainTotals.Files = 1, 'File count = 1');
    Assert.IsTrue(VC.PlainTotals.Folders = 1, 'Folder count = 1');
    Assert.IsTrue(VC.PlainTotals.Bytes = 1024, 'Bytes = 1024');

    VC.InvalidateTotals;
    Assert.IsTrue(not VC.PlainTotals.Valid, 'Totals invalidated');
  finally
    VC.Free;
  end;
  Writeln('TestPanelViewController passed successfully.');
end;

{ TTestPanelViewController }

procedure TTestPanelViewController.Run;
begin
  RunTests;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPanelViewController);

end.
