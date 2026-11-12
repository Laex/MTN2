unit TestDiskMap;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDiskMap = class
  strict private
    FDir: string;
    procedure MakeFile(const ARelative: string; ASize: Integer);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestTreemapTilesCoverTheAreaWithoutOverlap;
    [Test] procedure TestTreemapAreasFollowTheSizes;
    [Test] procedure TestTreemapGivesNoRoomToEmptySizes;
    [Test] procedure TestTreemapTilesStayCloseToSquares;
    [Test] procedure TestScanSumsFilesAndFoldersLargestFirst;
    [Test] procedure TestScanFoldsSmallFilesIntoOneRestNode;
    [Test] procedure TestScanBelowKeptDepthOnlyAddsToTheParent;
    [Test] procedure TestScanEntryLimitMarksTheResultIncomplete;
    [Test] procedure TestScanStoppedEarlyHasTheCoarseLevelsFirst;
    [Test] procedure TestFormatBytes;
    [Test] procedure TestRasterFillAndFrame;
    [Test] procedure TestBitmapTextDrawsInsideTheClip;
    [Test] procedure TestFitTextShortensWithEllipsis;
    [Test] procedure TestViewArrowsEnterAndBackspaceMoveThroughTheTree;
    [Test] procedure TestViewClickSelectsTheTileUnderThePoint;
    [Test] procedure TestViewGotoNamesTheSelectedPath;
    [Test] procedure TestViewRenderDrawsTilesInsteadOfTheBackground;
    [Test] procedure TestViewNamesWhatItWaitsForWhenThereAreNoTiles;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uTreemap, uDiskMapTree, uDiskMapRaster, uDiskMapView;

function SumSizes(const AArray: TArray<Int64>): Int64;
var
  V: Int64;
begin
  Result := 0;
  for V in AArray do
    Inc(Result, V);
end;

function RectsOverlap(const A, B: TTileRect): Boolean;
begin
  Result := (A.X1 < B.X2) and (B.X1 < A.X2) and (A.Y1 < B.Y2) and (B.Y1 < A.Y2);
end;

procedure TTestDiskMap.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'mtn2-diskmap-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  SetBitmapFontOnly(True);
end;

procedure TTestDiskMap.TearDown;
begin
  SetBitmapFontOnly(False);
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestDiskMap.MakeFile(const ARelative: string; ASize: Integer);
var
  Path: string;
  Bytes: TBytes;
begin
  Path := TPath.Combine(FDir, StringReplace(ARelative, '\', PathDelim, [rfReplaceAll]));
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Path));
  SetLength(Bytes, ASize);
  TFile.WriteAllBytes(Path, Bytes);
end;

procedure TTestDiskMap.TestTreemapTilesCoverTheAreaWithoutOverlap;
var
  Rects: TArray<TTileRect>;
  I, J, Area: Integer;
begin
  Rects := SquarifyLayout([600, 600, 400, 300, 200, 200, 100, 50, 10], 10, 20, 400, 300);
  Area := 0;
  for I := 0 to High(Rects) do
  begin
    Assert.IsFalse(Rects[I].IsEmpty, 'tile ' + IntToStr(I));
    Assert.IsTrue((Rects[I].X1 >= 10) and (Rects[I].Y1 >= 20) and (Rects[I].X2 <= 410) and
      (Rects[I].Y2 <= 320), 'inside the area');
    Inc(Area, Rects[I].Width * Rects[I].Height);
    for J := I + 1 to High(Rects) do
      Assert.IsFalse(RectsOverlap(Rects[I], Rects[J]), Format('%d and %d overlap', [I, J]));
  end;
  Assert.AreEqual(400 * 300, Area, 'the tiles fill the area');
end;

procedure TTestDiskMap.TestTreemapAreasFollowTheSizes;
var
  Rects: TArray<TTileRect>;
begin
  Rects := SquarifyLayout([300, 100], 0, 0, 400, 100);
  Assert.AreEqual(2, Integer(Length(Rects)));
  Assert.AreEqual(30000, Rects[0].Width * Rects[0].Height);
  Assert.AreEqual(10000, Rects[1].Width * Rects[1].Height);
end;

procedure TTestDiskMap.TestTreemapGivesNoRoomToEmptySizes;
var
  Rects: TArray<TTileRect>;
begin
  Rects := SquarifyLayout([50, 0, -5], 0, 0, 100, 100);
  Assert.AreEqual(3, Integer(Length(Rects)));
  Assert.IsFalse(Rects[0].IsEmpty);
  Assert.IsTrue(Rects[1].IsEmpty, 'zero');
  Assert.IsTrue(Rects[2].IsEmpty, 'negative');
  Assert.AreEqual(0, Integer(Length(SquarifyLayout([], 0, 0, 100, 100))));
  Assert.IsTrue(SquarifyLayout([5], 0, 0, 0, 100)[0].IsEmpty, 'no width, no room');
end;

procedure TTestDiskMap.TestTreemapTilesStayCloseToSquares;
var
  Rects: TArray<TTileRect>;
  I: Integer;
  Ratio: Double;
begin
  Rects := SquarifyLayout([100, 100, 100, 100], 0, 0, 800, 800);
  for I := 0 to High(Rects) do
  begin
    Ratio := Rects[I].Width / Rects[I].Height;
    Assert.IsTrue((Ratio > 0.9) and (Ratio < 1.1), Format('tile %d is %dx%d', [I,
      Rects[I].Width, Rects[I].Height]));
  end;
end;

procedure TTestDiskMap.TestScanSumsFilesAndFoldersLargestFirst;
var
  Scan: IDiskScan;
  Root: TDiskNode;
begin
  MakeFile('a.bin', 100);
  MakeFile('sub\b.bin', 300);
  MakeFile('sub\deep\c.bin', 50);
  MakeFile('other\d.bin', 20);
  Scan := TDiskScan.Create(FDir, TDiskLimits.Standard);
  Scan.Scan.RunSync;
  Assert.IsTrue(Scan.Scan.Finished);
  Assert.IsFalse(Scan.Scan.Truncated);
  Root := Scan.Scan.Root;
  Assert.IsTrue(Root.Done);
  Assert.AreEqual(Int64(470), Root.Size);
  Assert.AreEqual(3, Integer(Root.Children.Count));
  Assert.AreEqual('sub', Root.Children[0].Name, 'largest first');
  Assert.AreEqual(Int64(350), Root.Children[0].Size);
  Assert.AreEqual('a.bin', Root.Children[1].Name);
  Assert.AreEqual('other', Root.Children[2].Name);
  Assert.IsTrue(Root.Children[0].Done);
  Assert.IsTrue(Root.Children[0].Parent = Root, 'parent link of a top-level folder');
  Assert.IsTrue(Root.Children[0].Children[0].Parent = Root.Children[0], 'parent link below it');
  Assert.AreEqual(Int64(300), Root.Children[0].Children[0].Size);
end;

procedure TTestDiskMap.TestScanFoldsSmallFilesIntoOneRestNode;
var
  Scan: IDiskScan;
  Limits: TDiskLimits;
  I: Integer;
  Rest: TDiskNode;
  Total: Int64;
  Kid: TDiskNode;
begin
  for I := 1 to 10 do
    MakeFile(Format('f%d.bin', [I]), I * 10);
  Limits := TDiskLimits.Standard;
  Limits.FilesPerDir := 3;
  Scan := TDiskScan.Create(FDir, Limits);
  Scan.Scan.RunSync;
  Assert.AreEqual(4, Integer(Scan.Scan.Root.Children.Count), 'three files and the rest');
  Total := 0;
  Rest := nil;
  for Kid in Scan.Scan.Root.Children do
  begin
    Inc(Total, Kid.Size);
    if Kid.IsRest then
      Rest := Kid;
  end;
  Assert.IsNotNull(Rest);
  Assert.AreEqual(Int64(280), Rest.Size, 'files of 10..70 bytes');
  Assert.AreEqual(Int64(550), Total, 'nothing is lost');
  Assert.AreEqual(Int64(550), Scan.Scan.Root.Size);
end;

procedure TTestDiskMap.TestScanBelowKeptDepthOnlyAddsToTheParent;
var
  Scan: IDiskScan;
  Limits: TDiskLimits;
  Top, Rest: TDiskNode;
begin
  MakeFile('one\two\three\f.bin', 64);
  Limits := TDiskLimits.Standard;
  Limits.KeepDepth := 1;
  Scan := TDiskScan.Create(FDir, Limits);
  Scan.Scan.RunSync;
  Assert.AreEqual(Int64(64), Scan.Scan.Root.Size);
  Top := Scan.Scan.Root.Children[0];
  Assert.AreEqual('one', Top.Name);
  Assert.AreEqual(Int64(64), Top.Size);
  Assert.AreEqual(1, Integer(Top.Children.Count), 'the deeper folders collapse into one node');
  Rest := Top.Children[0];
  Assert.IsTrue(Rest.IsRest);
  Assert.AreEqual(Int64(64), Rest.Size);
end;

procedure TTestDiskMap.TestScanEntryLimitMarksTheResultIncomplete;
var
  Scan: IDiskScan;
  Limits: TDiskLimits;
  I: Integer;
begin
  for I := 1 to 20 do
    MakeFile(Format('f%d.bin', [I]), 10);
  Limits := TDiskLimits.Standard;
  Limits.MaxEntries := 5;
  Scan := TDiskScan.Create(FDir, Limits);
  Scan.Scan.RunSync;
  Assert.IsTrue(Scan.Scan.Finished, 'a stopped scan still finishes');
  Assert.IsTrue(Scan.Scan.Truncated);
  Assert.IsTrue(Scan.Scan.Root.Size < 200);
end;

procedure TTestDiskMap.TestScanStoppedEarlyHasTheCoarseLevelsFirst;
var
  Scan: IDiskScan;
  Limits: TDiskLimits;
  I: Integer;
  Top: TDiskNode;
begin
  for I := 1 to 30 do
  begin
    MakeFile(Format('a\sub\f%d.bin', [I]), 10);
    MakeFile(Format('b\sub\f%d.bin', [I]), 10);
    MakeFile(Format('c\sub\f%d.bin', [I]), 10);
  end;
  Limits := TDiskLimits.Standard;
  Limits.MaxEntries := 12;
  Scan := TDiskScan.Create(FDir, Limits);
  Scan.Scan.RunSync;
  Assert.IsTrue(Scan.Scan.Truncated);
  Assert.AreEqual(3, Integer(Scan.Scan.Root.Children.Count), 'every top-level folder is there');
  for Top in Scan.Scan.Root.Children do
  begin
    Assert.AreEqual(1, Integer(Top.Children.Count), Top.Name + ' lists its subfolder');
    Assert.AreEqual('sub', Top.Children[0].Name);
  end;
end;

procedure TTestDiskMap.TestFormatBytes;
begin
  Assert.AreEqual('0 B', FormatBytes(0));
  Assert.AreEqual('1023 B', FormatBytes(1023));
  Assert.AreEqual('1.0 KB', FormatBytes(1024));
  Assert.AreEqual('1.5 MB', FormatBytes(1536 * 1024));
  Assert.AreEqual('250 GB', FormatBytes(250 * Int64(1024) * 1024 * 1024));
end;

procedure TTestDiskMap.TestRasterFillAndFrame;
var
  R: TRaster;
begin
  R := TRaster.Create(10, 8);
  try
    R.Clear($102030);
    Assert.AreEqual(Cardinal($102030), R.PixelAt(0, 0));
    R.FillRect(2, 2, 6, 5, $FF0000);
    Assert.AreEqual(Cardinal($FF0000), R.PixelAt(2, 2));
    Assert.AreEqual(Cardinal($FF0000), R.PixelAt(5, 4));
    Assert.AreEqual(Cardinal($102030), R.PixelAt(6, 4), 'right edge is exclusive');
    R.FrameRect(0, 0, 10, 8, $00FF00, 1);
    Assert.AreEqual(Cardinal($00FF00), R.PixelAt(9, 7));
    Assert.AreEqual(Cardinal($102030), R.PixelAt(1, 1), 'inside the frame');
    R.FillRect(-5, -5, 100, 100, $0000FF);
    Assert.AreEqual(Cardinal($0000FF), R.PixelAt(9, 7), 'clipped to the buffer');
    Assert.AreEqual(Cardinal(0), R.PixelAt(50, 50), 'outside reads as 0');
    Assert.AreEqual(10 * 8 * 4, Integer(Length(R.Pixels)));
  finally
    R.Free;
  end;
end;

procedure TTestDiskMap.TestBitmapTextDrawsInsideTheClip;
var
  R: TRaster;
  W, X, Y, Lit: Integer;
begin
  R := TRaster.Create(60, 20);
  try
    R.Clear(0);
    W := R.DrawText(2, 2, 'AB', $FFFFFF, 30);
    Assert.AreEqual(12, W, 'two glyphs');
    Lit := 0;
    for Y := 0 to 19 do
      for X := 0 to 59 do
        if R.PixelAt(X, Y) <> 0 then
        begin
          Inc(Lit);
          Assert.IsTrue((X >= 2) and (X < 14), 'inside the text box');
        end;
    Assert.IsTrue(Lit > 10, 'the glyphs have pixels');
    R.Clear(0);
    R.DrawText(2, 2, 'ABCDEFGH', $FFFFFF, 20);
    for Y := 0 to 19 do
      for X := 20 to 59 do
        Assert.AreEqual(Cardinal(0), R.PixelAt(X, Y), 'nothing past the clip');
  finally
    R.Free;
  end;
end;

procedure TTestDiskMap.TestFitTextShortensWithEllipsis;
var
  R: TRaster;
begin
  R := TRaster.Create(10, 10);
  try
    Assert.AreEqual('HELLO', R.FitText('HELLO', 100));
    Assert.AreEqual('HE...', R.FitText('HELLO WORLD', 30));
    Assert.AreEqual('', R.FitText('HELLO', 3), 'not even the dots fit');
    Assert.AreEqual('', R.FitText('', 100));
  finally
    R.Free;
  end;
end;

{ Builds a scanned folder with three top-level tiles and a view over it, drawn
  once so the tiles are known. }
type
  TViewFixture = record
    Scan: IDiskScan;
    View: TDiskMapView;
    Raster: TRaster;
  end;

procedure OpenFixture(const ADir: string; var AFix: TViewFixture);
begin
  AFix.Scan := TDiskScan.Create(ADir, TDiskLimits.Standard);
  AFix.Scan.Scan.RunSync;
  AFix.View := TDiskMapView.Create(AFix.Scan);
  AFix.Raster := TRaster.Create(400, 300);
  AFix.View.Render(AFix.Raster);
end;

procedure CloseFixture(var AFix: TViewFixture);
begin
  AFix.Raster.Free;
  AFix.View.Free;
end;

procedure TTestDiskMap.TestViewArrowsEnterAndBackspaceMoveThroughTheTree;
var
  Fix: TViewFixture;
  Path: string;
  IsFile: Boolean;
begin
  MakeFile('big\x.bin', 5000);
  MakeFile('big\y.bin', 3000);
  MakeFile('mid.bin', 2000);
  MakeFile('small\z.bin', 100);
  OpenFixture(FDir, Fix);
  try
    Assert.AreEqual('', Fix.View.SelectedName, 'nothing selected at first');
    Assert.IsTrue(Fix.View.HandleKey('Right', Path, IsFile) = dkHandled);
    Assert.AreEqual('big', Fix.View.SelectedName, 'the first arrow selects the largest tile');
    Fix.View.Render(Fix.Raster);
    Assert.IsTrue(Fix.View.HandleKey('Enter', Path, IsFile) = dkHandled);
    Assert.AreEqual('', Fix.View.SelectedName, 'zooming in clears the selection');
    Assert.AreEqual(ExcludeTrailingPathDelimiter(FDir) + PathDelim + 'big', Fix.View.ViewRootPath);
    Fix.View.Render(Fix.Raster);
    Assert.IsTrue(Fix.View.HandleKey('Down', Path, IsFile) = dkHandled);
    Assert.AreEqual('x.bin', Fix.View.SelectedName);
    Assert.IsTrue(Fix.View.HandleKey('Backspace', Path, IsFile) = dkHandled);
    Assert.AreEqual('big', Fix.View.SelectedName, 'zooming out selects the folder left');
    Assert.AreEqual(ExcludeTrailingPathDelimiter(FDir), Fix.View.ViewRootPath);
    Assert.IsTrue(Fix.View.HandleKey('F5', Path, IsFile) = dkNone, 'other keys are not taken');
  finally
    CloseFixture(Fix);
  end;
end;

procedure TTestDiskMap.TestViewClickSelectsTheTileUnderThePoint;
var
  Fix: TViewFixture;
begin
  MakeFile('big\x.bin', 5000);
  MakeFile('small\z.bin', 100);
  OpenFixture(FDir, Fix);
  try
    Assert.IsFalse(Fix.View.Click(5000, 5000, False), 'outside every tile');
    Assert.IsTrue(Fix.View.Click(5, 5, False));
    Assert.AreEqual('big', Fix.View.SelectedName, 'the largest tile is laid out first, in the corner');
    Fix.View.Render(Fix.Raster);
    Assert.IsTrue(Fix.View.Click(50, 50, False), 'a nested tile is found before its folder');
    Assert.AreEqual('x.bin', Fix.View.SelectedName);
  finally
    CloseFixture(Fix);
  end;
end;

procedure TTestDiskMap.TestViewGotoNamesTheSelectedPath;
var
  Fix: TViewFixture;
  Path: string;
  IsFile: Boolean;
begin
  MakeFile('big\x.bin', 5000);
  MakeFile('note.txt', 10);
  OpenFixture(FDir, Fix);
  try
    Fix.View.HandleKey('Right', Path, IsFile);
    Assert.IsTrue(Fix.View.HandleKey('g', Path, IsFile) = dkGoto);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(FDir) + PathDelim + 'big', Path);
    Assert.IsFalse(IsFile, 'a folder');
    Fix.View.Render(Fix.Raster);
    Fix.View.HandleKey('Down', Path, IsFile);
    Fix.View.HandleKey('Right', Path, IsFile);
    Assert.AreEqual('note.txt', Fix.View.SelectedName);
    Assert.IsTrue(Fix.View.HandleKey('G', Path, IsFile) = dkGoto);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(FDir) + PathDelim + 'note.txt', Path);
    Assert.IsTrue(IsFile, 'a file');
  finally
    CloseFixture(Fix);
  end;
end;

procedure TTestDiskMap.TestViewRenderDrawsTilesInsteadOfTheBackground;
var
  Fix: TViewFixture;
  X, Y, Plain: Integer;
begin
  MakeFile('a\one.bin', 1000);
  MakeFile('b.bin', 1000);
  OpenFixture(FDir, Fix);
  try
    Plain := 0;
    for Y := 0 to 279 do
      for X := 0 to 399 do
        if Fix.Raster.PixelAt(X, Y) = $1E1E1E then
          Inc(Plain);
    Assert.IsTrue(Plain < 400 * 280 div 10, 'the tiles cover the map area');
    Assert.AreEqual(Cardinal($2B2B2B), Fix.Raster.PixelAt(399, 299), 'the status bar is at the bottom');
  finally
    CloseFixture(Fix);
  end;
end;

procedure TTestDiskMap.TestViewNamesWhatItWaitsForWhenThereAreNoTiles;
var
  Scan: IDiskScan;
  View: TDiskMapView;
  R: TRaster;
  X, Y, Lit: Integer;
begin
  Scan := TDiskScan.Create(FDir, TDiskLimits.Standard);
  View := TDiskMapView.Create(Scan);
  R := TRaster.Create(300, 200);
  try
    View.TextScanning := 'scanning...';
    View.Render(R);
    Lit := 0;
    for Y := 0 to 150 do
      for X := 0 to 299 do
        if R.PixelAt(X, Y) <> R.PixelAt(0, 0) then
          Inc(Lit);
    Assert.IsTrue(Lit > 10, 'a note in the map area before the scan has found anything');
  finally
    R.Free;
    View.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDiskMap);

end.
