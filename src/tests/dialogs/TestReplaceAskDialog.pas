unit TestReplaceAskDialog;

{ The question of a step-by-step replace: the captions say what each line is,
  the values and the match inside the line are drawn in the accent style (bold,
  another color), the rest of the line is plain. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestReplaceAskDialog = class
  public
    [Test] procedure TestCaptionsAndAccentedValues;
    [Test] procedure TestMatchInTheLineIsAccented;
    [Test] procedure TestRussianCaptions;
  end;

implementation

uses
  System.SysUtils, uTerminalTypes, uStrings, uDialogTypes, uDialogHost,
  uThemeRegistry;

function DrawDialog(const ADecl: TDialogDeclaration; out AHost: TDialogHost): TTerminalGrid;
begin
  AHost := TDialogHost.Create(CreateThemeByName('NDN'));
  AHost.Open(ADecl, nil);
  AllocTerminalGrid(Result, 100, 30);
  ClearTerminalGrid(Result, $FFFFFFFF, $FF000080, ' ');
  AHost.Draw(Result, 100, 30);
end;

function RowText(const AGrid: TTerminalGrid; AY: Integer): string;
var
  X: Integer;
begin
  Result := '';
  for X := 0 to High(AGrid[AY]) do
    Result := Result + AGrid[AY][X].CharValue;
end;

// Row and column of the first AText on the grid.
function Find(const AGrid: TTerminalGrid; const AText: string; out AX, AY: Integer): Boolean;
var
  Y, P: Integer;
begin
  for Y := 0 to High(AGrid) do
  begin
    P := Pos(AText, RowText(AGrid, Y));
    if P > 0 then
    begin
      AX := P - 1;
      AY := Y;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TTestReplaceAskDialog.TestCaptionsAndAccentedValues;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  CX, CY, VX, VY: Integer;
begin
  SetLocale('');
  Grid := DrawDialog(BuildReplaceAskDialog('Postgres', '!Postgres', 12,
    'participant DB as ', 'Postgres', 'QL'), Host);
  try
    Assert.IsTrue(Find(Grid, 'Find:', CX, CY), 'caption of the pattern');
    Assert.IsTrue(Find(Grid, 'Replace with:', CX, CY), 'caption of the replacement');
    Assert.IsTrue(Find(Grid, 'Line 12:', CX, CY), 'caption of the line, with its number');
    Assert.IsTrue(Find(Grid, '"Postgres"', VX, VY), 'the pattern is quoted');
    Assert.IsTrue(Find(Grid, '"!Postgres"', VX, VY), 'the replacement is quoted');
    Assert.IsTrue(ccaBold in Grid[VY][VX + 1].Attributes, 'the value is bold');
    Assert.IsTrue(Find(Grid, 'Find:', CX, CY));
    Assert.IsFalse(ccaBold in Grid[CY][CX].Attributes, 'the caption is plain');
    Assert.IsTrue(Grid[VY][VX + 1].FgColor <> Grid[CY][CX].FgColor,
      'the value has its own color');
  finally
    Host.Free;
  end;
end;

procedure TTestReplaceAskDialog.TestMatchInTheLineIsAccented;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  SetLocale('');
  Grid := DrawDialog(BuildReplaceAskDialog('Postgres', 'X', 3,
    'participant DB as ', 'Postgres', 'QL'), Host);
  try
    Assert.IsTrue(Find(Grid, 'participant DB as PostgresQL', X, Y),
      'the three pieces make one line');
    Assert.IsFalse(ccaBold in Grid[Y][X].Attributes, 'the text before the match is plain');
    Assert.IsTrue(ccaBold in Grid[Y][X + Length('participant DB as ')].Attributes,
      'the match is bold');
    Assert.IsTrue(ccaBold in Grid[Y][X + Length('participant DB as Postgres') - 1].Attributes,
      'to its last character');
    Assert.IsFalse(ccaBold in Grid[Y][X + Length('participant DB as Postgres')].Attributes,
      'the text after it is plain');
  finally
    Host.Free;
  end;
end;

procedure TTestReplaceAskDialog.TestRussianCaptions;
var
  Host: TDialogHost;
  Grid: TTerminalGrid;
  X, Y: Integer;
begin
  SetLocale('ru');
  try
    Grid := DrawDialog(BuildReplaceAskDialog('a', 'b', 7, '', 'a', ''), Host);
    try
      Assert.IsTrue(Find(Grid, 'Найти:', X, Y), 'pattern caption in Russian');
      Assert.IsTrue(Find(Grid, 'Заменить на:', X, Y), 'replacement caption in Russian');
      Assert.IsTrue(Find(Grid, 'Строка 7:', X, Y), 'line caption in Russian');
    finally
      Host.Free;
    end;
  finally
    SetLocale('');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestReplaceAskDialog);

end.
