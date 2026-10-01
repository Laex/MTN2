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
    [Test] procedure TestColorPickerControl;
    [Test] procedure TestColorPickButton;
    [Test] procedure TestSampleStyle;
    [Test] procedure TestSampleFallbackColors;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, System.IOUtils, System.Types,
  uTerminalTypes,
  uThemeTypes,
  uInputLine,
  uDialogTypes,
  uDialogJson,
  uDialogHost,
  uDialogResources,
  uThemeRegistry;

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
  Theme := CreateThemeByName('NDN');
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

procedure TestColorPickerControl;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Key: Word;
  Ch: Char;
  Idx, I: Integer;
  Before, After: string;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorpicker.json', TEncoding.UTF8), Decl),
    'colorpicker.json failed to parse');
  Idx := FindControlById(Decl, 'picker');
  Assert.IsTrue(Idx >= 0, 'picker not found');
  DialogSetColorPicker(Decl, 'picker', TAlphaColor($FF336699));

  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);

    Assert.IsTrue(SameText(Host.FocusedControlId, 'picker'),
      'the picker has the focus when the dialog opens, got "' + Host.FocusedControlId + '"');
    Assert.AreEqual('#336699', Host.GetColorPickerHex('picker'), 'the picker starts on its color');

    // Down walks to the hex line and stops there; three Ups reach the R slider,
    // where Shift+Right raises red by 10.
    Ch := #0;
    for I := 1 to 20 do
    begin
      Key := vkDown;
      Host.HandleInput(Key, [], Ch);
    end;
    Assert.IsTrue(SameText(Host.FocusedControlId, 'picker'), 'Down stays inside the picker');
    for I := 1 to 3 do
    begin
      Key := vkUp;
      Host.HandleInput(Key, [], Ch);
    end;
    Before := Host.GetColorPickerHex('picker');
    Key := vkRight;
    Host.HandleInput(Key, [ssShift], Ch);
    After := Host.GetColorPickerHex('picker');
    // Walking down the grid picks cells, so Before is the gray-ramp cell the walk ended on.
    Assert.AreEqual(Format('#%.2X%s', [StrToInt('$' + Copy(Before, 2, 2)) + 10, Copy(Before, 4, 4)]),
      After, 'Shift+Right on the R slider adds 10 to red (from ' + Before + ')');
  finally
    Host.Free;
  end;
end;

// A color field shows a pick button in its last cell; a click there fires
// the field's pick command, a click elsewhere in the field does not.
procedure TestColorPickButton;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Idx: Integer;
  R: TRectI;
  Fired: string;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\markdowncolors.json', TEncoding.UTF8), Decl),
    'markdowncolors.json failed to parse');
  Idx := FindControlById(Decl, 'md_h1_fg');
  Assert.IsTrue((Idx >= 0) and Decl.Controls[Idx].ColorPick, 'the color field has a pick button');
  Fired := '';
  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl,
      procedure(const AControlId, AValuesJson: string)
      begin
        Fired := AControlId;
      end);
    Host.Draw(Grid, W, H);
    R := Host.ControlBoundsAt(Idx);
    Host.HandleClick(R.Left + 1, R.Top, []);
    Assert.AreEqual('', Fired, 'a click inside the field is not a pick');
    Host.HandleClick(R.Right, R.Top, []);
    Assert.AreEqual('md_h1_fg:pick', Fired, 'a click on the last cell fires the pick command');
  finally
    Host.Free;
  end;
end;

// The Markdown colors sample is drawn with the attributes of the style list's
// selected item, or with its base style while the theme item is selected.
procedure TestSampleStyle;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Smp, Lst: Integer;
  R: TRectI;
  Key: Word;
  Ch: Char;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\markdowncolors.json', TEncoding.UTF8), Decl),
    'markdowncolors.json failed to parse');
  Smp := FindControlById(Decl, 'md_h1_sample');
  Lst := FindControlById(Decl, 'md_h1_style');
  Assert.IsTrue((Smp >= 0) and (Lst >= 0), 'sample and style list exist');
  Assert.AreEqual('md_h1_style', Decl.Controls[Smp].StyleSourceId, 'the sample reads the style list');
  Decl.Controls[Lst].Items := TArray<string>.Create('Theme', 'Plain', 'Italic');
  Decl.Controls[Lst].ItemIds := TArray<string>.Create('', 'none', 'italic');
  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    R := Host.ControlBoundsAt(Smp);
    Assert.IsTrue(Grid[R.Top][R.Left].Attributes = [ccaBold], 'the theme item shows the base style (bold for a heading)');
    Host.FocusControlById('md_h1_style');
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Host.Draw(Grid, W, H);
    Assert.IsTrue(Grid[R.Top][R.Left].Attributes = [], 'plain shows no attributes');
    Key := vkDown;
    Host.HandleInput(Key, [], Ch);
    Host.Draw(Grid, W, H);
    Assert.IsTrue(Grid[R.Top][R.Left].Attributes = [ccaItalic], 'italic shows italic');
  finally
    Host.Free;
  end;
end;

// A sample with no color of its own takes the document colors of the text row.
procedure TestSampleFallbackColors;
var
  Grid: TTerminalGrid;
  Host: TDialogHost;
  Decl: TDialogDeclaration;
  Smp, Txt, TxtBg: Integer;
  R: TRectI;
begin
  Assert.IsTrue(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\markdowncolors.json', TEncoding.UTF8), Decl),
    'markdowncolors.json failed to parse');
  Smp := FindControlById(Decl, 'md_bold_sample');
  Txt := FindControlById(Decl, 'md_text_fg');
  TxtBg := FindControlById(Decl, 'md_text_bg');
  Assert.IsTrue((Smp >= 0) and (Txt >= 0) and (TxtBg >= 0), 'controls exist');
  InputLineSetText(Decl.Controls[Txt].Edit, '#C6C6C6');
  InputLineSetText(Decl.Controls[TxtBg].Edit, '#202020');
  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    R := Host.ControlBoundsAt(Smp);
    Assert.AreEqual(TAlphaColor($FFC6C6C6), Grid[R.Top][R.Left].FgColor, 'text color comes from the text row');
    Assert.AreEqual(TAlphaColor($FF202020), Grid[R.Top][R.Left].BgColor, 'background comes from the text row');
    Host.SetInputValue('md_bold_bg', '#112233');
    Host.Draw(Grid, W, H);
    Assert.AreEqual(TAlphaColor($FF112233), Grid[R.Top][R.Left].BgColor, 'its own color wins');
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

procedure TTestColorSampleRender.TestColorPickerControl;
begin
  TestColorSampleRender.TestColorPickerControl;
end;

procedure TTestColorSampleRender.TestColorPickButton;
begin
  TestColorSampleRender.TestColorPickButton;
end;

procedure TTestColorSampleRender.TestSampleStyle;
begin
  TestColorSampleRender.TestSampleStyle;
end;

procedure TTestColorSampleRender.TestSampleFallbackColors;
begin
  TestColorSampleRender.TestSampleFallbackColors;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestColorSampleRender);

end.
