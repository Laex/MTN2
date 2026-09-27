unit TestEditorPainter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorPainter = class
  public
    [Test] procedure Run;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uEditorPainter;

procedure RunTests;
var
  Row: TTerminalRow;
begin
  SetLength(Row, 40);

  TEditorPainter.DrawTextLine(Row, 0, 20, 'Hello World', 1, TAlphaColors.White, TAlphaColors.Black);
  Assert.IsTrue(Row[0].CharValue = 'H', 'Char[0] should be H');
  Assert.IsTrue(Row[1].CharValue = 'e', 'Char[1] should be e');
  Assert.IsTrue(Row[10].CharValue = 'd', 'Char[10] should be d');
  Assert.IsTrue(Row[11].CharValue = ' ', 'Char[11] should be space');

  Writeln('TestEditorPainter passed successfully.');
end;

{ TTestEditorPainter }

procedure TTestEditorPainter.Run;
begin
  RunTests;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorPainter);

end.
