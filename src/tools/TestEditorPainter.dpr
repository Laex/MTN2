program TestEditorPainter;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes, uEditorPainter;

procedure RunTests;
var
  Row: TTerminalRow;
begin
  Writeln('Testing TEditorPainter...');
  SetLength(Row, 40);

  TEditorPainter.DrawTextLine(Row, 0, 20, 'Hello World', 1, TAlphaColors.White, TAlphaColors.Black);
  Assert(Row[0].CharValue = 'H', 'Char[0] should be H');
  Assert(Row[1].CharValue = 'e', 'Char[1] should be e');
  Assert(Row[10].CharValue = 'd', 'Char[10] should be d');
  Assert(Row[11].CharValue = ' ', 'Char[11] should be space');

  Writeln('TestEditorPainter passed successfully.');
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
