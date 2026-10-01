unit TestDualPanelCommands;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelCommands = class
  public
    [Test] procedure TestCommandHandler;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelCommands;

procedure TestCommandHandler;
var
  LSources: TArray<string>;
  LTarget: string;
  LPrompt: string;
begin
  SetLength(LSources, 1);
  LSources[0] := 'file:///C:/test.txt';

  Assert.IsTrue(TDualPanelCommandHandler.ValidateSourceSelection(LSources), 'Should validate non-empty selection');

  LPrompt := TDualPanelCommandHandler.FormatDeletePrompt(LSources);
  Assert.IsTrue(Pos('test.txt', LPrompt) > 0, 'Delete prompt should include file name');

  LTarget := TDualPanelCommandHandler.PrepareCopyMoveTarget('file:///C:/', 'file:///D:/');
  Assert.IsTrue(LTarget = 'file:///D:/', 'Target should prioritize opposite panel URI');

end;

{ TTestDualPanelCommands }

procedure TTestDualPanelCommands.TestCommandHandler;
begin
  TestDualPanelCommands.TestCommandHandler;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelCommands);

end.
