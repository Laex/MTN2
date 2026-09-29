unit TestFilePositions;

{ Per-file Viewer/Editor positions (uFilePositions): the Viewer's line
  wrapping (F2) is kept with the position, written to fileposition.json,
  and a save from the Editor (fwwKeep) leaves it as the Viewer set it. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFilePositions = class
  public
    [Test] procedure TestWordWrapKept;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uConfigLocation, uFilePositions;

const
  cUri = 'file:///Z:/mtn2-test/wrapped-notes.txt';
  cOther = 'file:///Z:/mtn2-test/never-opened.txt';

procedure TTestFilePositions.TestWordWrapKept;
var
  Path, Original: string;
  HadOriginal: Boolean;
  Pos: TFilePosition;
begin
  Path := GetConfigFilePath('fileposition.json');
  HadOriginal := TFile.Exists(Path);
  if HadOriginal then
    Original := TFile.ReadAllText(Path, TEncoding.UTF8);
  try
    SaveFilePosition(cUri, 10, 0, 12, 3, False, 0, 0, fwwOn);
    Assert.IsTrue(TryGetFilePosition(cUri, Pos), 'saved');
    Assert.IsTrue(Pos.WordWrap = fwwOn, 'Viewer: wrapping on');
    Assert.IsTrue(TFile.ReadAllText(Path, TEncoding.UTF8).Contains('"wordWrap":true'),
      'written to fileposition.json');

    SaveFilePosition(cUri, 40, 0, 45, 1, False, 0, 0);
    Assert.IsTrue(TryGetFilePosition(cUri, Pos), 'saved again');
    Assert.AreEqual(45, Pos.CursorRow, 'Editor: the position moves');
    Assert.IsTrue(Pos.WordWrap = fwwOn, 'Editor: the Viewer''s wrapping stays');

    SaveFilePosition(cUri, 40, 0, 45, 1, False, 0, 0, fwwOff);
    Assert.IsTrue(TryGetFilePosition(cUri, Pos) and (Pos.WordWrap = fwwOff),
      'Viewer: wrapping off');
    Assert.IsTrue(TFile.ReadAllText(Path, TEncoding.UTF8).Contains('"wordWrap":false'),
      'off is written too');

    Assert.IsFalse(TryGetFilePosition(cOther, Pos), 'no entry');
    Assert.IsTrue(Pos.WordWrap = fwwKeep, 'no entry: no saved wrapping');
  finally
    if HadOriginal then
      TFile.WriteAllText(Path, Original, TEncoding.UTF8)
    else if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFilePositions);

end.
