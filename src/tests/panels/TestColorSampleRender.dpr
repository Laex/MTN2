program TestColorSampleRender;

{$APPTYPE CONSOLE}

{ Headless render check for dckColorSample (uDialogHost.pas): parses the real
  colorcodingedit.json (same as TestDialogJson.dpr does — no RCDATA needed,
  this bypasses RequireDialogResource entirely since a console tool has none
  compiled in), sets cc_normal_fg's live text the way a user typing it would,
  opens it on a real TTerminalGrid, calls Draw, then inspects the actual
  cells the three sample swatches landed on — no screenshot needed to tell
  whether the background fill / theme-driven fallback is actually happening. }

uses
  System.SysUtils, System.UITypes, System.IOUtils, System.Types,
  uTerminalTypes in '..\..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\..\Core\uThemeTypes.pas',
  uInputLine in '..\..\Core\uInputLine.pas',
  uDialogTypes in '..\..\Core\uDialogTypes.pas',
  uDialogJson in '..\..\Core\uDialogJson.pas',
  uDialogHost in '..\..\Core\uDialogHost.pas',
  uNDNTheme in '..\..\Themes\uNDNTheme.pas';

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
/// — the three sample swatches (Normal/Selected/Current) draw in that order.</summary>
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
  Writeln('No theme: unset Bg falls back to fixed gray (not white — would blend into the dialog body)');
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), Decl),
    'colorcodingedit.json failed to parse');
  FgIdx := FindControlById(Decl, 'cc_normal_fg');
  Assert(FgIdx >= 0, 'cc_normal_fg not found');
  InputLineSetText(Decl.Controls[FgIdx].Edit, '#FF55FF');

  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    Cells := FindSampleCells(Grid);
    Assert(Length(Cells) = 3, Format('expected 3 sample swatches, found %d', [Length(Cells)]));
    Cell := Grid[Cells[0].Y][Cells[0].X];
    Writeln(Format('  Normal sample: Fg=$%s Bg=$%s', [IntToHex(Cell.FgColor, 8), IntToHex(Cell.BgColor, 8)]));
    if (Cell.FgColor = TAlphaColor($FFFF55FF)) and (Cell.BgColor = TAlphaColor($FFC0C0C0)) then
      Writeln('  OK: magenta text on neutral-gray fallback')
    else
      Writeln('  BUG: expected Fg=$FFFF55FF Bg=$FFC0C0C0');
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
  Writeln('With a theme: unset Bg previews the theme''s ACTUAL row color per panelState (Normal/Selected/Current differ)');
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorcodingedit.json', TEncoding.UTF8), Decl),
    'colorcodingedit.json failed to parse');
  // All 6 Fg/Bg fields left blank — every channel on every row should fall
  // back to that row's theme-resolved color, not the generic gray.

  FillGrid(Grid);
  Theme := TNDNTheme.Create;
  Host := TDialogHost.Create(Theme);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);
    Cells := FindSampleCells(Grid);
    Assert(Length(Cells) = 3, Format('expected 3 sample swatches, found %d', [Length(Cells)]));
    NormalCell := Grid[Cells[0].Y][Cells[0].X];
    SelectedCell := Grid[Cells[1].Y][Cells[1].X];
    CurrentCell := Grid[Cells[2].Y][Cells[2].X];
    Writeln(Format('  Normal:   Fg=$%s Bg=$%s', [IntToHex(NormalCell.FgColor, 8), IntToHex(NormalCell.BgColor, 8)]));
    Writeln(Format('  Selected: Fg=$%s Bg=$%s', [IntToHex(SelectedCell.FgColor, 8), IntToHex(SelectedCell.BgColor, 8)]));
    Writeln(Format('  Current:  Fg=$%s Bg=$%s', [IntToHex(CurrentCell.FgColor, 8), IntToHex(CurrentCell.BgColor, 8)]));

    if NormalCell.BgColor = TAlphaColor($FFC0C0C0) then
      Writeln('  BUG: Normal row still shows the generic gray fallback — theme branch did not fire')
    else
      Writeln('  OK: Normal row shows a theme color, not the generic gray fallback');

    if (SelectedCell.BgColor <> NormalCell.BgColor) or (SelectedCell.FgColor <> NormalCell.FgColor) then
      Writeln('  OK: Selected row differs from Normal row (theme distinguishes row states)')
    else
      Writeln('  BUG: Selected row is identical to Normal row — panelState is not reaching ResolveFileRowColors correctly');

    if (CurrentCell.BgColor <> NormalCell.BgColor) or (CurrentCell.FgColor <> NormalCell.FgColor) then
      Writeln('  OK: Current row differs from Normal row (theme distinguishes row states)')
    else
      Writeln('  BUG: Current row is identical to Normal row — panelState is not reaching ResolveFileRowColors correctly');
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
  Writeln('colorpicker.json: default focus + SetInputValue (the primitives ColorPickerSyncHexFromPreset relies on)');
  Assert(TryParseDialogJson(
    TFile.ReadAllText('..\..\dialogs\colorpicker.json', TEncoding.UTF8), Decl),
    'colorpicker.json failed to parse');

  // Raw parse leaves picker_presets at its JSON placeholder ("(no presets)",
  // one item) — real opens go through BuildColorPickerDialog's
  // DialogSetListItems, which this console tool can't reach (no RCDATA).
  // Fill in a few items by hand so Down-arrow has somewhere to move to.
  Idx0 := FindControlById(Decl, 'picker_presets');
  Assert(Idx0 >= 0, 'picker_presets not found');
  Decl.Controls[Idx0].Items := TArray<string>.Create('Black    #000000', 'Red      #C00000', 'Green    #00C000');
  Decl.Controls[Idx0].SelectedIndex := 0;

  FillGrid(Grid);
  Host := TDialogHost.Create(nil);
  try
    Host.Open(Decl, NoopCommand);
    Host.Draw(Grid, W, H);

    if SameText(Host.FocusedControlId, 'picker_presets') then
      Writeln('  OK: presets list has focus by default when the dialog opens (arrow keys work immediately)')
    else
      Writeln('  BUG: default focus is "' + Host.FocusedControlId + '", expected "picker_presets"');

    Host.SetInputValue('picker_hex', '#123456');
    if Host.GetInputValue('picker_hex') = '#123456' then
      Writeln('  OK: SetInputValue on an already-open dialog is readable back via GetInputValue')
    else
      Writeln('  BUG: GetInputValue after SetInputValue returned "' + Host.GetInputValue('picker_hex') + '"');

    Idx0 := Host.GetListSelectedIndex('picker_presets');
    Key := vkDown;
    Ch := #0;
    Host.HandleInput(Key, [], Ch);
    Idx1 := Host.GetListSelectedIndex('picker_presets');
    if Idx1 = Idx0 + 1 then
      Writeln(Format('  OK: Down arrow moves the presets list selection (%d -> %d)', [Idx0, Idx1]))
    else
      Writeln(Format('  BUG: selection after Down arrow: %d -> %d (expected +1)', [Idx0, Idx1]));
  finally
    Host.Free;
  end;
end;

begin
  try
    TestFixedGrayFallbackNoTheme;
    Writeln;
    TestThemeDrivenFallbackPerRow;
    Writeln;
    TestColorPickerPresetSync;
    Writeln;
    Writeln('All checks passed.');
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;
end.
