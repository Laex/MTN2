unit TestPicturePreview;

{ Pictures in the character grid: the reader of a converter's colored text
  and, on POSIX, the preview that runs the converter (a stand-in chafa
  script) and writes its cells into the screen. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPicturePreview = class
  private
    FDir: string;
    FOldPath: string;
    procedure InstallFakeChafa;
    function NewPicture: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ParserReadsTrueColorAndRows;
    [Test] procedure ParserReadsPaletteColorsAndReset;
    [Test] procedure ParserSkipsOtherSequences;
    [Test] procedure PreviewWritesConvertedCellsCentered;
    [Test] procedure FinishedPictureIsPaintedWithoutAnotherRequest;
    [Test] procedure PreviewNeedsARequestForEveryFrame;
    [Test] procedure MissingConverterShowsAHint;
    [Test] procedure PictureInsideArchiveIsConverted;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.UITypes, System.Zip,
  uPlatformPaths, uPlatformProcess, uPlatformFileAttr, uFileAttrTypes,
  uTerminalTypes, uThemeTypes, uAnsiPicture, uOverlayRenderer, uVfsTypes;

const
  // Two rows of two upper-half blocks: red over blue, then green over white.
  cFakeChafa =
    '#!/bin/sh'#10 +
    'echo "$@" > "$FAKE_PIC_DIR/args"'#10 +
    'printf ''\033[38;2;255;0;0m\033[48;2;0;0;255m\342\226\200\342\226\200\033[0m\n'''#10 +
    'printf ''\033[38;2;0;255;0m\033[48;2;255;255;255m\342\226\200\342\226\200\033[0m\n'''#10;

function Area(ALeft, ATop, ARight, ABottom: Integer): TRectI;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

procedure TTestPicturePreview.InstallFakeChafa;
var
  Script: string;
  Plan: TFileAttrPlan;
  Err: string;
begin
  Script := TPath.Combine(FDir, 'chafa');
  TFile.WriteAllText(Script, cFakeChafa, TEncoding.ASCII);
  Plan := Default(TFileAttrPlan);
  Plan.ChangeMode := True;
  Plan.Mode := $1ED;
  Assert.IsTrue(ApplyFileAttrOne(Script, Plan, Err), Err);
  // Only the stand-in is on the path: a real chafa of the machine must not win.
  PlatformSetEnvironment('PATH', FDir + ':' + FOldPath);
  PlatformSetEnvironment('FAKE_PIC_DIR', FDir);
end;

function TTestPicturePreview.NewPicture: string;
begin
  Result := TPath.Combine(FDir, TPath.GetGUIDFileName(False) + '.png');
  TFile.WriteAllText(Result, 'not really a picture', TEncoding.ASCII);
end;

procedure TTestPicturePreview.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-pic-' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FDir);
  FOldPath := GetEnvironmentVariable('PATH');
end;

procedure TTestPicturePreview.TearDown;
begin
  ClearOverlayPreview;
  if PlatformPosixPaths then
    PlatformSetEnvironment('PATH', FOldPath);
  TDirectory.Delete(FDir, True);
end;

procedure TTestPicturePreview.ParserReadsTrueColorAndRows;
var
  Pic: TTerminalGrid;
begin
  Pic := ParseAnsiPicture(#27'[38;2;10;20;30m'#27'[48;2;1;2;3mAB'#27'[0m'#10'C'#10#10,
    TAlphaColors.Silver, TAlphaColors.Black);
  Assert.AreEqual(2, Integer(Length(Pic)), 'two rows, the empty tail is dropped');
  Assert.AreEqual(2, AnsiPictureWidth(Pic), 'widest row');
  Assert.AreEqual('A', string(Pic[0][0].CharValue));
  Assert.AreEqual(TAlphaColor($FF0A141E), Pic[0][0].FgColor, 'foreground');
  Assert.AreEqual(TAlphaColor($FF010203), Pic[0][1].BgColor, 'background');
  Assert.AreEqual(' ', string(Pic[1][1].CharValue), 'short row padded');
  Assert.AreEqual(TAlphaColor(TAlphaColors.Black), Pic[1][1].BgColor, 'padding uses the default');
  Assert.AreEqual(TAlphaColor(TAlphaColors.Silver), Pic[1][0].FgColor, 'reset restores the default');
end;

procedure TTestPicturePreview.ParserReadsPaletteColorsAndReset;
var
  Pic: TTerminalGrid;
begin
  Pic := ParseAnsiPicture(#27'[38;5;196mR'#27'[44mB'#27'[39;49mD'#27'[97mW',
    TAlphaColors.Silver, TAlphaColors.Black);
  Assert.AreEqual(TAlphaColor($FFFF0000), Pic[0][0].FgColor, '256-color red');
  Assert.AreEqual(TAlphaColor($FF0000EE), Pic[0][1].BgColor, 'basic blue background');
  Assert.AreEqual(TAlphaColor(TAlphaColors.Silver), Pic[0][2].FgColor, '39 resets the foreground');
  Assert.AreEqual(TAlphaColor(TAlphaColors.Black), Pic[0][2].BgColor, '49 resets the background');
  Assert.AreEqual(TAlphaColor($FFFFFFFF), Pic[0][3].FgColor, 'bright white');
end;

procedure TTestPicturePreview.ParserSkipsOtherSequences;
var
  Pic: TTerminalGrid;
begin
  Pic := ParseAnsiPicture(#27'[?25l'#27'[2K'#27']0;title'#7'x'#13#10, TAlphaColors.Silver,
    TAlphaColors.Black);
  Assert.AreEqual(1, Integer(Length(Pic)), 'one row');
  Assert.AreEqual(1, AnsiPictureWidth(Pic), 'only the text is kept');
  Assert.AreEqual('x', string(Pic[0][0].CharValue));
end;

procedure TTestPicturePreview.PictureInsideArchiveIsConverted;
var
  Grid: TTerminalGrid;
  Zip: TZipFile;
  ZipPath, Args: string;
  I: Integer;
begin
  if not PlatformPosixPaths then
    Exit;
  InstallFakeChafa;
  ZipPath := TPath.Combine(FDir, 'pics.zip');
  Zip := TZipFile.Create;
  try
    Zip.Open(ZipPath, zmWrite);
    Zip.Add(TEncoding.ASCII.GetBytes('not really a picture'), 'inner.png');
    Zip.Close;
  finally
    Zip.Free;
  end;
  AllocTerminalGrid(Grid, 20, 10);
  ClearTerminalGrid(Grid, TAlphaColors.Silver, TAlphaColors.Black);
  for I := 1 to 250 do
  begin
    // The archive answers on the main thread, so the queue is pumped here.
    RequestOverlayPreview(PathToFileUri(ZipPath) + '!/inner.png', Area(2, 2, 9, 5));
    PaintOverlayCells(Grid);
    CheckSynchronize;
    if Grid[3][5].CharValue <> ' ' then
      Break;
    Sleep(20);
  end;
  Assert.AreEqual(#$2580, string(Grid[3][5].CharValue), 'picture from the archive is painted');
  Args := Trim(TFile.ReadAllText(TPath.Combine(FDir, 'args')));
  Assert.IsTrue(Pos('mtn2-pic-', Args) > 0, 'a temporary copy was converted: ' + Args);
  Assert.IsTrue(Pos('.png', Args) > 0, 'the copy keeps the extension: ' + Args);
end;

procedure TTestPicturePreview.PreviewWritesConvertedCellsCentered;
var
  Grid: TTerminalGrid;
  Path, Args: string;
  I: Integer;
begin
  if not PlatformPosixPaths then
    Exit;
  InstallFakeChafa;
  Path := NewPicture;
  AllocTerminalGrid(Grid, 20, 10);
  ClearTerminalGrid(Grid, TAlphaColors.Silver, TAlphaColors.Black);
  for I := 1 to 250 do
  begin
    RequestOverlayPreview(PathToFileUri(Path), Area(2, 2, 9, 5));
    PaintOverlayCells(Grid);
    if Grid[3][5].CharValue <> ' ' then
      Break;
    Sleep(20);
  end;
  // The area is 8 x 4 cells and the picture 2 x 2, so it sits at (5, 3).
  Assert.AreEqual(#$2580, string(Grid[3][5].CharValue), 'first cell');
  Assert.AreEqual(TAlphaColor($FFFF0000), Grid[3][5].FgColor, 'red over');
  Assert.AreEqual(TAlphaColor($FF0000FF), Grid[3][6].BgColor, 'blue under');
  Assert.AreEqual(TAlphaColor($FF00FF00), Grid[4][5].FgColor, 'second row');
  Assert.AreEqual(' ', string(Grid[2][2].CharValue), 'the rest of the area is untouched');
  Args := Trim(TFile.ReadAllText(TPath.Combine(FDir, 'args')));
  Assert.IsTrue(Pos('--size=8x4', Args) > 0, 'asked for the area size: ' + Args);
  Assert.IsTrue(Pos('--format=symbols', Args) > 0, 'text output works in every terminal: ' + Args);
  Assert.IsTrue(Pos(Path, Args) > 0, 'file name passed: ' + Args);
end;

procedure TTestPicturePreview.FinishedPictureIsPaintedWithoutAnotherRequest;
var
  Grid: TTerminalGrid;
  I: Integer;
begin
  if not PlatformPosixPaths then
    Exit;
  InstallFakeChafa;
  AllocTerminalGrid(Grid, 20, 10);
  ClearTerminalGrid(Grid, TAlphaColors.Silver, TAlphaColors.Black);
  RequestOverlayPreview(PathToFileUri(NewPicture), Area(2, 2, 9, 5));
  PaintOverlayCells(Grid);
  // Later frames come from the repaint after the conversion, not from a new request.
  for I := 1 to 250 do
  begin
    Sleep(20);
    PaintOverlayCells(Grid);
    if Grid[3][5].CharValue <> ' ' then
      Break;
  end;
  Assert.AreEqual(#$2580, string(Grid[3][5].CharValue), 'picture appears once converted');
end;

procedure TTestPicturePreview.PreviewNeedsARequestForEveryFrame;
var
  Grid, Later: TTerminalGrid;
  I: Integer;
begin
  if not PlatformPosixPaths then
    Exit;
  InstallFakeChafa;
  AllocTerminalGrid(Grid, 20, 10);
  ClearTerminalGrid(Grid, TAlphaColors.Silver, TAlphaColors.Black);
  RequestOverlayPreview(NewPicture, Area(2, 2, 9, 5));
  for I := 1 to 250 do
  begin
    UpdateOverlayBounds(Area(2, 2, 9, 5));
    PaintOverlayCells(Grid);
    if Grid[3][5].CharValue <> ' ' then
      Break;
    Sleep(20);
  end;
  Assert.AreEqual(#$2580, string(Grid[3][5].CharValue), 'preview shown');
  AllocTerminalGrid(Later, 20, 10);
  ClearTerminalGrid(Later, TAlphaColors.Silver, TAlphaColors.Black);
  PaintOverlayCells(Later);
  Assert.AreEqual(' ', string(Later[3][5].CharValue), 'a frame nobody asked for stays clean');
end;

procedure TTestPicturePreview.MissingConverterShowsAHint;
var
  Grid: TTerminalGrid;
  Line, Path: string;
  I, X: Integer;
begin
  if not PlatformPosixPaths then
    Exit;
  PlatformSetEnvironment('PATH', FDir);
  Path := NewPicture;
  AllocTerminalGrid(Grid, 60, 10);
  ClearTerminalGrid(Grid, TAlphaColors.Silver, TAlphaColors.Black);
  for I := 1 to 250 do
  begin
    RequestOverlayPreview(Path, Area(0, 0, 59, 9));
    PaintOverlayCells(Grid);
    Line := '';
    for X := 0 to High(Grid[4]) do
      Line := Line + Grid[4][X].CharValue;
    if Trim(Line) <> '' then
      Break;
    Sleep(20);
  end;
  Assert.IsTrue(Pos('chafa', Line) > 0, 'tells which package to install: ' + Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPicturePreview);

end.
