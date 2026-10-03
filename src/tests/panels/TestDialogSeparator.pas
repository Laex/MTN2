unit TestDialogSeparator;

{ Dialog "separator" controls (MakeHRule / JSON "separator"): rendered
  headless from the real display.json, each rule spans the dialog and joins
  the frame the theme drew - ╟─╢ on a double frame, +-+ on an ASCII one. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDialogSeparator = class
  public
    [Test] procedure TestDoubleFrameJoins;
    [Test] procedure TestAsciiFrameJoins;
    [Test] procedure TestJsonRoundTrip;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.IOUtils,
  uTerminalTypes, uThemeTypes, uDialogTypes, uDialogJson, uDialogHost,
  uThemeRegistry;

const
  W = 100;
  H = 40;
  cSeparators = 1;

procedure NoopCommand(const AControlId, AValuesJson: string);
begin
end;

function LoadDisplay: TDialogDeclaration;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\display.json', TEncoding.UTF8), Result),
    'display.json failed to parse');
end;

// Rows drawn as AJoinL, a line of ALine, AJoinR.
function CountJoinedRows(const AGrid: TTerminalGrid; AJoinL, AJoinR,
  ALine: Char): Integer;
var
  X, Y, L, R: Integer;
begin
  Result := 0;
  for Y := 0 to High(AGrid) do
  begin
    L := -1;
    for X := 0 to High(AGrid[Y]) do
      if AGrid[Y][X].CharValue = AJoinL then
      begin
        L := X;
        Break;
      end;
    if L < 0 then
      Continue;
    R := L + 1;
    while (R <= High(AGrid[Y])) and (AGrid[Y][R].CharValue = ALine) do
      Inc(R);
    // A full rule: join, an unbroken line, join. (An ASCII frame's own top
    // edge breaks at the title; its bottom edge counts, hence ">=" there.)
    if (R <= High(AGrid[Y])) and (AGrid[Y][R].CharValue = AJoinR) and (R - L > 20) then
      Inc(Result);
  end;
end;

procedure Render(const ATheme: IThemeRenderer; out AGrid: TTerminalGrid);
var
  Host: TDialogHost;
begin
  AllocTerminalGrid(AGrid, W, H);
  ClearTerminalGrid(AGrid, TAlphaColorRec.White, TAlphaColorRec.Navy, ' ');
  Host := TDialogHost.Create(ATheme);
  try
    Host.Open(LoadDisplay, NoopCommand);
    Host.Draw(AGrid, W, H);
  finally
    Host.Free;
  end;
end;

procedure TTestDialogSeparator.TestDoubleFrameJoins;
var
  Grid: TTerminalGrid;
begin
  Render(CreateThemeByName('NDN'), Grid);
  Assert.IsTrue(CountJoinedRows(Grid, chDblVSingleHR, chDblVSingleHL, chBoxH) = cSeparators,
    'every separator joins the double frame');
end;

procedure TTestDialogSeparator.TestAsciiFrameJoins;
var
  Grid: TTerminalGrid;
begin
  Render(CreateThemeByName('ASCII'), Grid);
  Assert.IsTrue(CountJoinedRows(Grid, '+', '+', '-') >= cSeparators,
    'every separator joins the ASCII frame');
end;

procedure TTestDialogSeparator.TestJsonRoundTrip;
var
  Decl, Back: TDialogDeclaration;
  I, N: Integer;
begin
  Decl := LoadDisplay;
  N := 0;
  for I := 0 to High(Decl.Controls) do
    if (Decl.Controls[I].Kind = dckLabel) and IsHRuleText(Decl.Controls[I].Text) then
      Inc(N);
  Assert.IsTrue(N = cSeparators, Format('%d separators parsed', [N]));
  Assert.IsTrue(TryParseDialogJson(DeclarationToJson(Decl), Back), 're-parse');
  N := 0;
  for I := 0 to High(Back.Controls) do
    if (Back.Controls[I].Kind = dckLabel) and IsHRuleText(Back.Controls[I].Text) then
      Inc(N);
  Assert.IsTrue(N = cSeparators, 'separators survive DeclarationToJson');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDialogSeparator);

end.
