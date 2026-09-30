unit TestSpacedNames;

{ Names that start with a space survive URI joining and splitting, so such a
  folder can be opened and listed. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSpacedNames = class
  public
    [Test] procedure JoinKeepsLeadingSpace;
    [Test] procedure SpacedFolderIsListedFromJoinedUri;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uVfsTypes;

procedure TTestSpacedNames.JoinKeepsLeadingSpace;
var
  Root, Sub: string;
begin
  Root := PathToFileUri(TPath.Combine(TPath.GetTempPath, 'mtn2-spaced'));
  Sub := JoinVfsUri(Root, ' lead');
  Assert.AreEqual(TPath.Combine(TPath.GetTempPath, 'mtn2-spaced') + PathDelim + ' lead',
    FileUriToPath(Sub), 'leading space kept in the joined path');
  Assert.IsTrue(SameVfsUri(ParentVfsUri(Sub), Root), 'parent of the joined URI is the root');
  Assert.AreEqual(Root, JoinVfsUri(Root, ''), 'empty name joins nothing');
end;

procedure TTestSpacedNames.SpacedFolderIsListedFromJoinedUri;
var
  Dir, Sub, SubPath: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-spaced-' + IntToStr(Random(MaxInt)));
  SubPath := WinApiPath(Dir + PathDelim + ' lead');
  TDirectory.CreateDirectory(SubPath);
  try
    TFile.WriteAllText(SubPath + PathDelim + 'a.txt', 'a');
    Sub := FileUriToPath(JoinVfsUri(PathToFileUri(Dir), ' lead'));
    Assert.IsTrue(LocalPathIsDirectory(Sub), 'the joined path is the existing folder');
    Assert.IsTrue(LocalPathIsFile(Sub + PathDelim + 'a.txt'), 'its content is reachable');
  finally
    TDirectory.Delete(WinApiPath(Dir), True);
  end;
end;

end.
