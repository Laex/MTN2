unit TestSearchHitsJson;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSearchHitsJson = class
  public
    [Test] procedure TestMessageCarriesPathKindSizeAndTimes;
    [Test] procedure TestMessageCarriesLineAndSnippet;
    [Test] procedure TestRangeSelectsTheBatch;
    [Test] procedure TestFileInfoIsReadFromDisk;
    [Test] procedure TestMissingFileIsReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, uSearchHitsJson;

procedure TTestSearchHitsJson.TestMessageCarriesPathKindSizeAndTimes;
var
  Hits: TArray<TSearchHit>;
begin
  SetLength(Hits, 2);
  Hits[0] := NewSearchHit('C:\Work\a.txt', False);
  Hits[0].Size := 5;
  Hits[0].Modified := '2026-01-02T03:04:05';
  Hits[0].Created := '2025-01-02T03:04:05';
  Hits[0].Accessed := '2026-02-02T03:04:05';
  Hits[0].Attributes := 32;
  Hits[1] := NewSearchHit('C:\Work\Docs', True);
  Hits[1].Size := 99;
  Assert.AreEqual(
    '{"jsonrpc":"2.0","method":"search.hits","params":{"hits":[' +
    '{"path":"C:\\Work\\a.txt","isDir":false,"size":5,"modified":"2026-01-02T03:04:05",' +
    '"created":"2025-01-02T03:04:05","accessed":"2026-02-02T03:04:05","attributes":32},' +
    '{"path":"C:\\Work\\Docs","isDir":true}]}}', BuildSearchHitsMessage(Hits, 0, 2));
end;

procedure TTestSearchHitsJson.TestMessageCarriesLineAndSnippet;
var
  Hits: TArray<TSearchHit>;
begin
  SetLength(Hits, 1);
  Hits[0] := NewSearchHit('C:\Work\a.txt', False);
  Hits[0].Line := 12;
  Hits[0].Snippet := 'the "needle"';
  Assert.AreEqual(
    '{"jsonrpc":"2.0","method":"search.hits","params":{"hits":[' +
    '{"path":"C:\\Work\\a.txt","isDir":false,"line":12,"snippet":"the \"needle\""}]}}',
    BuildSearchHitsMessage(Hits, 0, 1));
end;

procedure TTestSearchHitsJson.TestRangeSelectsTheBatch;
var
  Hits: TArray<TSearchHit>;
begin
  SetLength(Hits, 3);
  Hits[0] := NewSearchHit('A', False);
  Hits[1] := NewSearchHit('B', False);
  Hits[2] := NewSearchHit('C', False);
  Assert.AreEqual(
    '{"jsonrpc":"2.0","method":"search.hits","params":{"hits":[{"path":"B","isDir":false}]}}',
    BuildSearchHitsMessage(Hits, 1, 1));
end;

procedure TTestSearchHitsJson.TestFileInfoIsReadFromDisk;
var
  Path: string;
  Hit: TSearchHit;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'mtn_hits_' + IntToStr(TThread.GetTickCount64) + '.txt');
  TFile.WriteAllText(Path, 'abc');
  try
    Hit := NewSearchHit(Path, False);
    Assert.IsTrue(ReadHitFileInfo(Hit));
    Assert.AreEqual<Int64>(3, Hit.Size);
    Assert.AreEqual(19, Length(Hit.Modified), 'yyyy-mm-ddThh:nn:ss');
  finally
    TFile.Delete(Path);
  end;
end;

procedure TTestSearchHitsJson.TestMissingFileIsReported;
var
  Hit: TSearchHit;
begin
  Hit := NewSearchHit(TPath.Combine(TPath.GetTempPath, 'mtn_missing_file.none'), False);
  Assert.IsFalse(ReadHitFileInfo(Hit));
  Assert.AreEqual<Int64>(-1, Hit.Size);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSearchHitsJson);

end.
