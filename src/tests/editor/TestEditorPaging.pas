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

function OpenLines(ACount: Integer; out ADir: string): TEditorWindow;
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
      Text.Append('line ').Append(I).Append(sLineBreak);
    TFile.WriteAllText(Path, Text.ToString, TEncoding.UTF8);
  finally
    Text.Free;
  end;
  Result := TEditorWindow.Create(CreateThemeByName('NDN'), 1);
  Result.Area := TRectI.Make(0, 0, 80, 30);
  Result.Open(PathToFileUri(Path), False);
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

end.
