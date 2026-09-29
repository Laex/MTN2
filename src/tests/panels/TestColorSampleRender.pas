unit TestColorSampleRender;

{ Headless render check for dckColorSample (uDialogHost.pas): parses the real
  colorcodingedit.json (same as TestDialogJson.pas does - no RCDATA needed,
  this bypasses RequireDialogResource entirely since a console tool has none
  compiled in), sets cc_normal_fg's live text the way a user typing it would,
  opens it on a real TTerminalGrid, calls Draw, then inspects the actual
  cells the three sample swatches landed on - no screenshot needed to tell
  whether the background fill / theme-driven fallback is happening. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColorSampleRender = class
  public
    [Test] procedure TestFixedGrayFallbackNoTheme;
    [Test] procedure TestThemeDrivenFallbackPerRow;
    [Test] procedure TestColorPickerPresetSync;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.IOUtils, System.Types,
  uTerminalTypes,
  uThemeTypes,
  uInputLine,
  uDialogTypes,
  uDialogJson,
  uDialogHost,
  uNDNTheme;

const
  W = 80;
  H = 25;

procedure NoopCommand(const AControlId, AValuesJson: string);
begin
end;

function FindControlById(const ADecl: TDialogDeclaration; const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ADecl.Controls) do
    if SameText(ADecl.Controls[I].Id, AId) then
      Exit(I);
  Result := -1;
end;

/// <summary>All (col,row) positions where "filename.t" starts, top to bottom
/// - the three sample swatches (Normal/Selected/Current) draw in that order.</summary>
function FindSampleCells(const AGrid: TTerminalGrid): TArray<TPoint>;
var
  X, Y, K, N: Integer;
  S: string;
begin
  SetLength(Result, 0);
  N := 0;
  for Y := 0 to High(AGrid) do
    for X := 0 to Length(AGrid[Y]) - 10 do
    begin
      S := '';
      for K := 0 to 9 do
        S := S + AGrid[Y][X + K].CharValue;
      if Pos('filename.t', S) = 1 then
      begin
        SetLength(Result, N + 1);
        Result[N] := TPoint.Create(X, Y);
        Inc(N);
      end;
    end;
end;

procedure FillGrid(var AGrid: TTerminalGrid);
var
  X, Y: Integer;
begin
  SetLength(AGrid, H);
  for Y := 0 to H - 1 do
  begin
    SetLength(AGrid[Y], W);
    for X := 0 to W - 1 do
      AGrid[Y][X] := TCharCell.Make(' ', TAlphaColor($FFAAAAAA), TAlphaColor($FF000000));
  end;
end;

procedure TestFixedGrayFallbackNoTheme;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  FgIdx: Integer;
  Cells: TArray<TPoint>;
  Cell: TCharCell;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), Decl),
    'colorcodingedit.json failed to parse');
  FgIdx := FindControlById(Decl, 'cc_normal_fg');
  Assert.IsTrue(FgIdx >= 0, 'cc_normal_fg not found');
  InputLineSetText(Decl.Controls[FgIdx].Edit, '#FF55FF');

  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    Cells := FindSampleCells(Grid);
    Assert.IsTrue(Length(Cells) = 3, Format('expected 3 sample swatches, found %d', [Length(Cells)]));
    Cell := Grid[Cells[0].Y][Cells[0].X];
    Assert.IsTrue((Cell.FgColor = TAlphaColor($FFFF55FF)) and (Cell.BgColor = TAlphaColor($FFC0C0C0)),
      Format('magenta text on the neutral-gray fallback, got Fg=$%s Bg=$%s',
        [IntToHex(Cell.FgColor, 8), IntToHex(Cell.BgColor, 8)]));
  finally
    Host.Free;
  end;
end;

procedure TestThemeDrivenFallbackPerRow;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Theme: IThemeRenderer;
  Cells: TArray<TPoint>;
  NormalCell, SelectedCell, CurrentCell: TCharCell;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), Decl),
    'colorcodingedit.json failed to parse');
  // All 6 Fg/Bg fields left blank - every channel on every row should fall
  // back to that row's theme-resolved color, not the generic gray.

  FillGrid(Grid);
  Theme := TNDNTheme.Create;
  Host := TDialogHost.Create(Theme);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    Cells := FindSampleCells(Grid);
    Assert.IsTrue(Length(Cells) = 3, Format('expected 3 sample swatches, found %d', [Length(Cells)]));
    NormalCell := Grid[Cells[0].Y][Cells[0].X];
    SelectedCell := Grid[Cells[1].Y][Cells[1].X];
    CurrentCell := Grid[Cells[2].Y][Cells[2].X];
    Assert.IsTrue(NormalCell.BgColor <> TAlphaColor($FFC0C0C0),
      'Normal row shows a theme color, not the generic gray fallback');
    Assert.IsTrue((SelectedCell.BgColor <> NormalCell.BgColor) or
      (SelectedCell.FgColor <> NormalCell.FgColor),
      'Selected row differs from Normal (panelState reaches ResolveFileRowColors)');
    Assert.IsTrue((CurrentCell.BgColor <> NormalCell.BgColor) or
      (CurrentCell.FgColor <> NormalCell.FgColor),
      'Current row differs from Normal (panelState reaches ResolveFileRowColors)');
  finally
    Host.Free;
  end;
end;

procedure TestColorPickerPresetSync;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Key: Word;
  Ch: Char;
  Idx0, Idx1: Integer;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorpicker.json', TEncoding.UTF8), Decl),
    'colorpicker.json failed to parse');

  // Raw parse leaves picker_presets at its JSON placeholder ("(no presets)",
  // one item) - real opens go through BuildColorPickerDialog's
  // DialogSetListItems, which this console tool can't reach (no RCDATA).
  // Fill in a few items by hand so Down-arrow has somewhere to move to.
  Idx0 := FindControlById(Decl, 'picker_presets');
  Assert.IsTrue(Idx0 >= 0, 'picker_presets not found');
  Decl.Controls[Idx0].Items := TArray<string>.Create('Black    #000000', 'Red      #C00000', 'Green    #00C000');
  Decl.Controls[Idx0].SelectedIndex := 0;

  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);

    Assert.IsTrue(SameText(Host.FocusedControlId, 'picker_presets'),
      'the presets list has the focus when the dialog opens, got "' + Host.FocusedControlId + '"');

    Host.SetInputValue('picker_hex', '#123456');
    Assert.AreEqual('#123456', Host.GetInputValue('picker_hex'),
      'SetInputValue on an open dialog reads back via GetInputValue');

    Idx0 := Host.GetListSelectedIndex('picker_presets');
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Idx1 := Host.GetListSelectedIndex('picker_presets');
    Assert.AreEqual(Idx0 + 1, Idx1, 'Down arrow moves the presets list selection');
  finally
    Host.Free;
  end;
end;

{ TTestColorSampleRender }

procedure TTestColorSampleRender.TestFixedGrayFallbackNoTheme;
begin
  TestColorSampleRender.TestFixedGrayFallbackNoTheme;
end;

procedure TTestColorSampleRender.TestThemeDrivenFallbackPerRow;
begin
  TestColorSampleRender.TestThemeDrivenFallbackPerRow;
end;

procedure TTestColorSampleRender.TestColorPickerPresetSync;
begin
  TestColorSampleRender.TestColorPickerPresetSync;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColorSampleRender);

end.
