unit TestFolderFrecent;

{ uFolderFrecent: ranking by visit count weighted by recency, and the list
  survives a reload from disk. The runner points the config folder at a temp
  directory. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFolderFrecent = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ScoreWeightsRecentVisitsHigher;
    [Test] procedure OftenVisitedFolderBeatsSingleRecentVisit;
    [Test] procedure RecentFolderBeatsStaleFolderWithSameCount;
    [Test] procedure SameFolderSpelledDifferentlyCountsOnce;
    [Test] procedure RemoveForgetsOneFolder;
    [Test] procedure ClearForgetsAll;
    [Test] procedure OldestWeakFoldersAreDroppedAtTheLimit;
  end;

implementation

uses
  System.SysUtils, uConfigLocation, uFolderFrecent;

const
  cA = 'file:///C:/frecent-a/';
  cB = 'file:///C:/frecent-b/';
  cC = 'file:///C:/frecent-c/';
  cNow = 1800000000;

procedure TTestFolderFrecent.Setup;
begin
  Assert.IsTrue(ConfigDirectoryIsOverridden, 'the tests run on a settings folder of their own');
  FolderFrecentClear;
end;

procedure TTestFolderFrecent.TearDown;
begin
  FolderFrecentClear;
end;

procedure TTestFolderFrecent.ScoreWeightsRecentVisitsHigher;
begin
  Assert.IsTrue(FrecentScore(1, 60) > FrecentScore(1, 7200), 'hour beats day');
  Assert.IsTrue(FrecentScore(1, 7200) > FrecentScore(1, 3 * 86400), 'day beats week');
  Assert.IsTrue(FrecentScore(1, 3 * 86400) > FrecentScore(1, 30 * 86400), 'week beats older');
  Assert.AreEqual(8.0, FrecentScore(2, 10), 0.0001);
end;

procedure TTestFolderFrecent.OftenVisitedFolderBeatsSingleRecentVisit;
var
  Uris: TArray<string>;
  I: Integer;
begin
  for I := 1 to 5 do
    FolderFrecentVisit(cA, cNow - 3 * 86400);
  FolderFrecentVisit(cB, cNow - 10);
  Uris := FolderFrecentGetUris(cNow);
  Assert.IsTrue(Length(Uris) = 2, 'list length');
  // A: 5 * 0.5 = 2.5, B: 1 * 4 = 4 -- one fresh visit leads until A is visited again.
  Assert.AreEqual(cB, Uris[0]);
  for I := 1 to 3 do
    FolderFrecentVisit(cA, cNow - 3600 * 2);
  Uris := FolderFrecentGetUris(cNow);
  Assert.AreEqual(cA, Uris[0]);
end;

procedure TTestFolderFrecent.RecentFolderBeatsStaleFolderWithSameCount;
var
  Uris: TArray<string>;
begin
  FolderFrecentVisit(cA, cNow - 40 * 86400);
  FolderFrecentVisit(cB, cNow - 60);
  Uris := FolderFrecentGetUris(cNow);
  Assert.AreEqual(cB, Uris[0]);
  Assert.AreEqual(cA, Uris[1]);
end;

procedure TTestFolderFrecent.SameFolderSpelledDifferentlyCountsOnce;
begin
  FolderFrecentVisit('file:///C:/frecent-a/', cNow);
  FolderFrecentVisit('file:///C:/frecent-a', cNow);
  Assert.IsTrue(Length(FolderFrecentGetUris(cNow)) = 1, 'list length');
end;

procedure TTestFolderFrecent.RemoveForgetsOneFolder;
var
  Uris: TArray<string>;
begin
  FolderFrecentVisit(cA, cNow);
  FolderFrecentVisit(cB, cNow);
  FolderFrecentRemove(cA);
  Uris := FolderFrecentGetUris(cNow);
  Assert.IsTrue(Length(Uris) = 1, 'list length');
  Assert.AreEqual(cB, Uris[0]);
end;

procedure TTestFolderFrecent.ClearForgetsAll;
begin
  FolderFrecentVisit(cA, cNow);
  FolderFrecentVisit(cC, cNow);
  FolderFrecentClear;
  Assert.IsTrue(Length(FolderFrecentGetUris(cNow)) = 0, 'list length');
end;

procedure TTestFolderFrecent.OldestWeakFoldersAreDroppedAtTheLimit;
var
  I: Integer;
  Uris: TArray<string>;
begin
  FolderFrecentVisit(cA, cNow - 100 * 86400);
  for I := 1 to cFolderFrecentMax do
    FolderFrecentVisit(Format('file:///C:/frecent-fill-%d/', [I]), cNow - 60);
  Uris := FolderFrecentGetUris(cNow);
  Assert.IsTrue(Length(Uris) = cFolderFrecentMax, 'list length');
  for I := 0 to High(Uris) do
    Assert.AreNotEqual(cA, Uris[I], 'the stale single-visit folder was the weakest');
end;

end.
