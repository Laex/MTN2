program TestPanelViewController;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDualPanelTypes,
  uPanelViewController;

procedure RunTests;
var
  VC: TPanelViewController;
  Rows: TPanelRows;
begin
  Writeln('Testing TPanelViewController...');
  VC := TPanelViewController.Create(psLeft);
  try
    Assert(VC.Side = psLeft, 'Side must be psLeft');
    Assert(not VC.PlainTotals.Valid, 'Totals initially invalid');

    SetLength(Rows, 3);
    Rows[0].IsParent := True;
    Rows[1].IsDirectory := True;
    Rows[1].IsParent := False;
    Rows[2].IsDirectory := False;
    Rows[2].IsParent := False;
    Rows[2].Size := 1024;

    VC.RecalculateTotalsIfNeeded(Rows);
    Assert(VC.PlainTotals.Valid, 'Totals valid after recalc');
    Assert(VC.PlainTotals.Files = 1, 'File count = 1');
    Assert(VC.PlainTotals.Folders = 1, 'Folder count = 1');
    Assert(VC.PlainTotals.Bytes = 1024, 'Bytes = 1024');

    VC.InvalidateTotals;
    Assert(not VC.PlainTotals.Valid, 'Totals invalidated');
  finally
    VC.Free;
  end;
  Writeln('TestPanelViewController passed successfully.');
end;

begin
  try
    RunTests;
  except
    on E: Exception do
    begin
      Writeln('Test failed: ', E.Message);
      Halt(1);
    end;
  end;
end.
