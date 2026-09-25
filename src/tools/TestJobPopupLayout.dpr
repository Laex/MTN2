program TestJobPopupLayout;

{$APPTYPE CONSOLE}

{ Pure-function checks for TJobPopupRenderer.ComputeLayout (extracted from
  TPanelJobController.LayoutJobPopup — see uJobPopupRenderer.pas). }

uses
  System.SysUtils, System.UITypes,
  uTerminalTypes in '..\Core\uTerminalTypes.pas',
  uThemeTypes in '..\Core\uThemeTypes.pas',
  uThemeDrawing in '..\Core\uThemeDrawing.pas',
  uDualPanelUiTypes in '..\Core\uDualPanelUiTypes.pas',
  uJobPopupRenderer in '..\Core\uJobPopupRenderer.pas',
  uDraculaTheme in '..\Themes\uDraculaTheme.pas',
  uNDNTheme in '..\Themes\uNDNTheme.pas',
  uNordTheme in '..\Themes\uNordTheme.pas',
  uSolarizedDarkTheme in '..\Themes\uSolarizedDarkTheme.pas',
  uHighContrastTheme in '..\Themes\uHighContrastTheme.pas',
  uModernUnicodeTheme in '..\Themes\uModernUnicodeTheme.pas',
  uTotalCommanderTheme in '..\Themes\uTotalCommanderTheme.pas',
  uASCIITheme in '..\Themes\uASCIITheme.pas';

var
  Failed: Integer;

procedure Expect(ACond: Boolean; const AMsg: string);
begin
  if ACond then
    Writeln('  OK  ', AMsg)
  else
  begin
    Inc(Failed);
    Writeln('  FAIL ', AMsg);
  end;
end;

function MakeJob(APhase: TPanelJobPhase; AKind: TPanelJobKind): TPanelJobState;
begin
  Result := Default(TPanelJobState);
  Result.Phase := APhase;
  Result.Kind := AKind;
end;

procedure TestRichModeSelection;
var
  R: TRectI;
begin
  Writeln('Rich vs plain mode selection (13 vs 9 rows tall)');

  // Rich: running + a transfer kind.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkCopy), 120, 40);
  Expect(R.Height = 13, 'Running+Copy -> rich (13 rows)');

  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkMove), 120, 40);
  Expect(R.Height = 13, 'Running+Move -> rich (13 rows)');

  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkPack), 120, 40);
  Expect(R.Height = 13, 'Running+Pack -> rich (13 rows)');

  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkUnpack), 120, 40);
  Expect(R.Height = 13, 'Running+Unpack -> rich (13 rows)');

  // Not rich: right kind but wrong phase.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpConfirm, pjkCopy), 120, 40);
  Expect(R.Height = 9, 'Confirm+Copy -> plain (9 rows), phase gates rich mode');

  // Not rich: running but a non-transfer kind (Delete has no per-file bars).
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkDelete), 120, 40);
  Expect(R.Height = 9, 'Running+Delete -> plain (9 rows), kind gates rich mode');

  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpError, pjkCopy), 120, 40);
  Expect(R.Height = 9, 'Error phase -> plain (9 rows)');
end;

procedure TestSizingOnWidePanel;
var
  R: TRectI;
begin
  Writeln('Sizing on a wide panel (caps at max width, centers)');

  // Rich: W = min(72, max(118,48)) + 2 = 74.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkCopy), 120, 40);
  Expect(R.Width = 74, 'rich width caps at 74 on a 120-wide panel');
  Expect(R.Left = 23, 'rich popup centered horizontally (Left=23)');
  Expect(R.Top = 14, 'rich popup centered vertically (Top=14)');
  Expect(R.Left + R.Width <= 120, 'rich popup stays within panel width');
  Expect(R.Top + R.Height <= 40, 'rich popup stays within panel height');

  // Plain: W = min(44, max(118,24)) + 2 = 46.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpConfirm, pjkDelete), 120, 40);
  Expect(R.Width = 46, 'plain width caps at 46 on a 120-wide panel');
  Expect(R.Left = 37, 'plain popup centered horizontally (Left=37)');
  Expect(R.Top = 16, 'plain popup centered vertically (Top=16)');

  // Running+Delete is its own case: same width cap as Rich (it now shows a
  // full path, needing the room) but Rich's own 13-row height stays gated
  // on Kind (Delete has no per-file/per-byte bars) — see TestSizingByPhaseKind.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkDelete), 120, 40);
  Expect(R.Width = 74, 'running-delete width caps at 74, same as rich');
  Expect(R.Height = 9, 'running-delete stays at plain''s 9 rows');
end;

procedure TestClampingOnNarrowPanel;
var
  R: TRectI;
begin
  Writeln('Clamping on a narrow panel (never runs off top/left)');

  // Plain: W = min(44, max(18,24)) + 2 = 26; naive Left=(20-26)div2=-3 -> clamps to 0.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpConfirm, pjkDelete), 20, 10);
  Expect(R.Left = 0, 'plain popup left-clamped to 0 on a 20-wide panel');
  Expect(R.Top = 1, 'plain popup top-clamped to 1 on a 10-tall panel');
  Expect(R.Width = 26, 'plain width still uses the 24-wide floor + 2');

  // Rich: W = min(72, max(38,48)) + 2 = 50; naive Left=(40-50)div2=-5 -> clamps to 0.
  R := TJobPopupRenderer.ComputeLayout(MakeJob(pjpRunning, pjkCopy), 40, 20);
  Expect(R.Left = 0, 'rich popup left-clamped to 0 on a 40-wide panel');
  Expect(R.Width = 50, 'rich width still uses the 48-wide floor + 2');
end;

function FindTextCell(const AGrid: TTerminalGrid; const ANeedle: string;
  out AX, AY: Integer): Boolean;
var
  X, Y, K: Integer;
  S: string;
begin
  Result := False;
  AX := -1;
  AY := -1;
  for Y := 0 to High(AGrid) do
    for X := 0 to Length(AGrid[Y]) - Length(ANeedle) do
    begin
      S := '';
      for K := 0 to Length(ANeedle) - 1 do
        S := S + AGrid[Y][X + K].CharValue;
      if S = ANeedle then
      begin
        AX := X;
        AY := Y;
        Exit(True);
      end;
    end;
end;

procedure TestThemedTotalAndPercent;
const
  cNdnWhite = TAlphaColor($FFFFFFFF);
  cNdnGray = TAlphaColor($FFAAAAAA);
  cNdnFrameCyan = TAlphaColor($FF55FFFF);
  cDraculaDialogBg = TAlphaColor($FF44475A);
  cDraculaDialogFg = TAlphaColor($FFF8F8F2);
  cDraculaPurple = TAlphaColor($FFBD93F9);
  W = 80;
  H = 25;
var
  Grid: TTerminalGrid;
  Theme: IThemeRenderer;
  Job: TPanelJobState;
  X, Y, PctX: Integer;
  Cell: TCharCell;
begin
  Writeln('Themed Total rule and percent (Dracula, not NDN white/cyan)');
  AllocTerminalGrid(Grid, W, H);
  ClearTerminalGrid(Grid, TAlphaColor($FFAAAAAA), TAlphaColor($FF000000), ' ');
  Theme := TDraculaTheme.Create;
  Job := MakeJob(pjpRunning, pjkCopy);
  Job.Bounds := TJobPopupRenderer.ComputeLayout(Job, W, H);
  Job.FileProgressDone := 42;
  Job.FileProgressTotal := 100;
  Job.ProgressDone := 420;
  Job.BytesTotal := 1000;
  Job.FilesDone := 0;
  Job.FilesTotal := 2;
  TJobPopupRenderer.Draw(Grid, Theme, Job, 'Copy');

  Expect(FindTextCell(Grid, 'Total', X, Y), 'Total caption is drawn');
  if (X >= 0) and (Y >= 0) then
  begin
    Cell := Grid[Y][X];
    Expect(Cell.BgColor = cDraculaDialogBg, 'Total sits on Dracula dialog bg, not NDN white');
    Expect(Cell.FgColor = cDraculaPurple, 'Total uses themed frame accent, not NDN cyan');
    Expect(Cell.FgColor <> cNdnFrameCyan, 'Total fg is not hardcoded NDN frame cyan');
    Expect(Cell.BgColor <> cNdnWhite, 'Total bg is not hardcoded white');
  end;

  Expect(FindTextCell(Grid, '%', PctX, Y) or FindTextCell(Grid, ' 42%', PctX, Y),
    'percent is drawn');
  // Scan the file-progress row (bounds.Top+6) for a '%' cell.
  Y := Job.Bounds.Top + 6;
  PctX := -1;
  if (Y >= 0) and (Y <= High(Grid)) then
    for X := 0 to High(Grid[Y]) do
      if Grid[Y][X].CharValue = '%' then
      begin
        PctX := X;
        Break;
      end;
  Expect(PctX >= 0, 'file-progress percent glyph is on the bar row');
  if PctX >= 0 then
  begin
    Cell := Grid[Y][PctX];
    Expect(Cell.BgColor = cDraculaDialogBg, 'percent sits on Dracula dialog bg');
    Expect(Cell.FgColor = cDraculaDialogFg, 'percent uses Dracula dialog text, not NDN gray');
    Expect(Cell.FgColor <> cNdnGray, 'percent fg is not hardcoded NDN file gray');
    Expect(Cell.BgColor <> cNdnWhite, 'percent bg is not hardcoded white');
  end;

  Y := Job.Bounds.Top + 7;
  Expect((Y >= 0) and (Y <= High(Grid)), 'Total rule row is on the grid');
  if (Y >= 0) and (Y <= High(Grid)) then
  begin
    Expect(Grid[Y][Job.Bounds.Left].CharValue = chBoxVR,
      'Dracula Total left tee is single ├, not double ╟');
    Expect(Grid[Y][Job.Bounds.Right].CharValue = chBoxVL,
      'Dracula Total right tee is single ┤, not double ╢');
    Expect(Grid[Y][Job.Bounds.Left].CharValue <> chDblVSingleHR,
      'Dracula Total does not use NDN mixed double tee');
  end;

  Expect(FindTextCell(Grid, 'Background', X, Y), 'Background button is drawn');
  Expect(Y = Job.Bounds.Top + 11, 'Background sits on the copy action row');
  Expect(JobPopupBackgroundHit(Job.Bounds, pjkCopy, Job.Bounds.Left + 2, Y),
    'left of Background button is a hit');
end;

procedure TestDeleteBackgroundButton;
var
  Grid: TTerminalGrid;
  Theme: IThemeRenderer;
  Job: TPanelJobState;
  X, Y: Integer;
begin
  Writeln('Delete running popup has Background');
  AllocTerminalGrid(Grid, 80, 25);
  ClearTerminalGrid(Grid, TAlphaColor($FFAAAAAA), TAlphaColor($FF000000), ' ');
  Theme := TDraculaTheme.Create;
  Job := MakeJob(pjpRunning, pjkDelete);
  Job.Bounds := TJobPopupRenderer.ComputeLayout(Job, 80, 25);
  TJobPopupRenderer.Draw(Grid, Theme, Job, 'Delete');
  Expect(FindTextCell(Grid, 'Background', X, Y), 'delete Background button is drawn');
  Expect(Y = Job.Bounds.Top + 5, 'delete Background sits on the action row');
end;

procedure RenderRichCopy(const ATheme: IThemeRenderer; var AGrid: TTerminalGrid;
  out AJob: TPanelJobState);
const
  W = 80;
  H = 25;
begin
  AllocTerminalGrid(AGrid, W, H);
  ClearTerminalGrid(AGrid, TAlphaColor($FFAAAAAA), TAlphaColor($FF000000), ' ');
  AJob := MakeJob(pjpRunning, pjkCopy);
  AJob.Bounds := TJobPopupRenderer.ComputeLayout(AJob, W, H);
  AJob.FileProgressDone := 42;
  AJob.FileProgressTotal := 100;
  AJob.ProgressDone := 420;
  AJob.BytesTotal := 1000;
  AJob.FilesDone := 0;
  AJob.FilesTotal := 2;
  TJobPopupRenderer.Draw(AGrid, ATheme, AJob, 'Copy');
end;

procedure TestTotalRuleJoinsDialogFrame;
var
  Grid: TTerminalGrid;
  Job: TPanelJobState;
  Y: Integer;
begin
  Writeln('Total rule T-junctions follow the dialog frame');
  RenderRichCopy(TNDNTheme.Create, Grid, Job);
  Y := Job.Bounds.Top + 7;
  Expect(Grid[Y][Job.Bounds.Left].CharValue = chDblVSingleHR,
    'NDN Total left tee is double-vertical ╟');
  Expect(Grid[Y][Job.Bounds.Right].CharValue = chDblVSingleHL,
    'NDN Total right tee is double-vertical ╢');

  RenderRichCopy(TASCIIOnlyTheme.Create, Grid, Job);
  Y := Job.Bounds.Top + 7;
  Expect(Grid[Y][Job.Bounds.Left].CharValue = '+',
    'ASCII Total left tee is +');
  Expect(Grid[Y][Job.Bounds.Right].CharValue = '+',
    'ASCII Total right tee is +');
end;

function LumaDelta(A, B: TAlphaColor): Integer;
var
  CA: TAlphaColorRec absolute A;
  CB: TAlphaColorRec absolute B;
  LA, LB: Integer;
begin
  LA := (299 * Integer(CA.R) + 587 * Integer(CA.G) + 114 * Integer(CA.B)) div 1000;
  LB := (299 * Integer(CB.R) + 587 * Integer(CB.G) + 114 * Integer(CB.B)) div 1000;
  Result := LA - LB;
  if Result < 0 then
    Result := -Result;
end;

procedure CheckThemeTabClose(const AName: string; const ATheme: IThemeRenderer);
  procedure CheckPart(APart: TPanelChromePart; AActive: Boolean; const ALabel: string);
  var
    TabFg, TabBg, CloseFg, Discard, MarkFg: TAlphaColor;
  begin
    ATheme.ResolvePanelChromeColors(APart, AActive, TabFg, TabBg);
    ATheme.ResolvePanelChromeColors(pcpCloseMark, True, CloseFg, Discard);
    MarkFg := ContrastingGlyphFg(TabBg, CloseFg, TabFg);
    Expect(LumaDelta(MarkFg, TabBg) >= 80, AName + ' ' + ALabel + ' close contrasts');
  end;
begin
  CheckPart(pcpPanelTabActive, True, 'active panel tab');
  CheckPart(pcpPanelTabIdle, True, 'idle panel tab on focused panel');
  CheckPart(pcpPanelTabIdle, False, 'idle panel tab on idle panel');
  CheckPart(pcpWorkspaceTabActive, True, 'active workspace tab');
  CheckPart(pcpWorkspaceTabIdle, False, 'idle workspace tab');
end;

procedure TestTabCloseContrastAcrossThemes;
begin
  Writeln('Tab close mark contrast across themes');
  CheckThemeTabClose('NDN', TNDNTheme.Create);
  CheckThemeTabClose('Dracula', TDraculaTheme.Create);
  CheckThemeTabClose('Nord', TNordTheme.Create);
  CheckThemeTabClose('Solarized', TSolarizedDarkTheme.Create);
  CheckThemeTabClose('HighContrast', THighContrastTheme.Create);
  CheckThemeTabClose('Modern', TModernUnicodeTheme.Create);
  CheckThemeTabClose('TotalCommander', TTotalCommanderTheme.Create);
  CheckThemeTabClose('ASCII', TASCIIOnlyTheme.Create);
end;

begin
  Failed := 0;
  try
    TestRichModeSelection;
    TestSizingOnWidePanel;
    TestDeleteBackgroundButton;
    TestClampingOnNarrowPanel;
    TestThemedTotalAndPercent;
    TestTotalRuleJoinsDialogFrame;
    TestTabCloseContrastAcrossThemes;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.Message);
      Halt(2);
    end;
  end;
  Writeln;
  if Failed = 0 then
  begin
    Writeln('All checks passed.');
    Halt(0);
  end;
  Writeln('Failed: ', Failed);
  Halt(1);
end.
