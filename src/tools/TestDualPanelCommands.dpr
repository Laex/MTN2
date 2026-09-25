program TestDualPanelCommands;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uDualPanelCommands in '..\Core\uDualPanelCommands.pas';

procedure TestCommandHandler;
var
  LSources: TArray<string>;
  LTarget: string;
  LPrompt: string;
begin
  SetLength(LSources, 1);
  LSources[0] := 'file:///C:/test.txt';

  Assert(TDualPanelCommandHandler.ValidateSourceSelection(LSources), 'Should validate non-empty selection');

  LPrompt := TDualPanelCommandHandler.FormatDeletePrompt(LSources);
  Assert(Pos('test.txt', LPrompt) > 0, 'Delete prompt should include file name');

  LTarget := TDualPanelCommandHandler.PrepareCopyMoveTarget('file:///C:/', 'file:///D:/');
  Assert(LTarget = 'file:///D:/', 'Target should prioritize opposite panel URI');

  Writeln('OK: TestCommandHandler passed');
end;

begin
  try
    TestCommandHandler;
    Writeln('All DualPanelCommands tests PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAILED: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
