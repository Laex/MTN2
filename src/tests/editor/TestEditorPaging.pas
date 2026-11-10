unit TestEditorPaging;

{ PgUp and PgDn move the view and the cursor one page together, so the cursor
  stays on the same screen row. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorPaging = class
  public
    [Test] procedure TestPageDownKeepsTheCursorOnItsScreenRow;
    [Test] procedure TestPageUpKeepsTheCursorOnItsScreenRow;
    [Test] procedure TestPageDownNearTheEndStopsOnTheLastLine;
    [Test] procedure TestPageDownKeepsTheScreenRowInHex;
    [Test] procedure TestPageDownKeepsTheScreenRowInWrappedView;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  uVfsTypes, uThemeTypes, uThemeRegistry, uEditorWindow;

procedure Pump(AMs: Integer = 600);
var
  T: UInt64;
begin
  T := TThread.GetTickCount64 + UInt64(AMs);
  while TThread.GetTickCount64 < T do
  begin
    CheckSynchronize(10);
    Sleep(5);
  end;
end;

function OpenLines(ACount: Integer; out ADir: string; AViewOnly: Boolean = False;
  const ALine: string = 'line '): TEditorWindow;
var
  Path: string;
  Text: TStringBuilder;
  I: Integer;
begin
  ADir := TPath.Combine(TPath.GetTempPath, 'mtn2-paging-' + TPath.GetGUIDFileName(False));
  ForceDirectories(ADir);
  Path := TPath.Combine(ADir, 'a.txt');
  Text := TStringBuilder.Create;
  try
    for I := 1 to ACount do
      Text.Append(ALine).Append(I).Append(sLineBreak);
    TFile.WriteAllText(Path, Text.ToString, TEncoding.UTF8);
  finally
    Text.Free;
  end;
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Area := TRectI.Make(0, 0, 80, 30);
  Result.Open(PathToFileUri(Path), AViewOnly);
  Pump;
  Assert.IsTrue(Result.DocReady, 'document loaded');
end;

procedure PressPage(AView: TEditorWindow; AKey: Word);
var
  K: Word;
  Ch: Char;
begin
  K := AKey;
  Ch := #0;
  AView.HandleInput(K, [], Ch);
end;

procedure TTestEditorPaging.TestPageDownKeepsTheCursorOnItsScreenRow;
var
  Dir: string;
  View: TEditorWindow;
  Top, Row, Col, ScreenRow: Integer;
begin
  View := OpenLines(500, Dir);
  try
    View.SetViewPos(100, 105, 0);
    ScreenRow := 5;
    PressPage(View, vkNext);
    View.GetViewPos(Top, Row, Col);
    Assert.IsTrue(Row > 105 + 5, 'the cursor went down by a page');
    Assert.AreEqual(ScreenRow, Row - Top, 'same screen row after PgDn');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPaging.TestPageUpKeepsTheCursorOnItsScreenRow;
var
  Dir: string;
  View: TEditorWindow;
  Top, Row, Col, ScreenRow: Integer;
begin
  View := OpenLines(500, Dir);
  try
    View.SetViewPos(300, 310, 0);
    ScreenRow := 10;
    PressPage(View, vkPrior);
    View.GetViewPos(Top, Row, Col);
    Assert.IsTrue(Row < 310 - 5, 'the cursor went up by a page');
    Assert.AreEqual(ScreenRow, Row - Top, 'same screen row after PgUp');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPaging.TestPageDownNearTheEndStopsOnTheLastLine;
var
  Dir: string;
  View: TEditorWindow;
  Top, Row, Col: Integer;
begin
  View := OpenLines(60, Dir);
  try
    View.SetViewPos(40, 50, 0);
    PressPage(View, vkNext);
    PressPage(View, vkNext);
    View.GetViewPos(Top, Row, Col);
    Assert.IsTrue(Row >= 59, 'the cursor reached the end of the file');
    Assert.IsTrue((Row >= Top) and (Row - Top < 30), 'the cursor stays in the view');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPaging.TestPageDownKeepsTheScreenRowInHex;
var
  Dir: string;
  View: TEditorWindow;
  Top, Row, Col, ScreenRow: Integer;
begin
  View := OpenLines(2000, Dir, True);
  try
    View.ToggleHexMode;
    Assert.IsTrue(View.HexMode, 'hex mode on');
    View.SetViewPos(50, 55, 0);
    View.GetViewPos(Top, Row, Col);
    ScreenRow := Row - Top;
    PressPage(View, vkNext);
    View.GetViewPos(Top, Row, Col);
    Assert.IsTrue(Row > 55 + 5, 'the cursor went down by a page');
    Assert.AreEqual(ScreenRow, Row - Top, 'same screen row after PgDn in hex');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestEditorPaging.TestPageDownKeepsTheScreenRowInWrappedView;
var
  Dir: string;
  View: TEditorWindow;
  Top, Row, Col, Top2, Row2: Integer;
begin
  // Every line wraps into several screen rows, so the view's top (a screen
  // row) runs ahead of the cursor's line number.
  View := OpenLines(500, Dir, True, StringOfChar('w', 200) + ' ');
  try
    PressPage(View, vkF2);
    View.SetViewPos(0, 0, 0);
    PressPage(View, vkNext);
    View.GetViewPos(Top, Row, Col);
    Assert.IsTrue(Top >= 20, 'the view went down by a page, the cursor stays on the top row');
    Assert.IsTrue(Row > 0, 'the cursor moved');
    Assert.IsTrue(Top > Row, 'the top is counted in screen rows');
    PressPage(View, vkNext);
    View.GetViewPos(Top2, Row2, Col);
    Assert.IsTrue(Top2 >= Top + 20, 'the view went down by another page');
    Assert.IsTrue(Row2 > Row, 'the cursor moved again');
  finally
    View.Free;
    TDirectory.Delete(Dir, True);
  end;
end;

end.
