unit TestDualPanelCommandRun;

{ The directory a panel command runs in, and which URIs the shell can leave. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDualPanelCommandRun = class
  public
    [Test] procedure AFolderUriIsItsLocalPath;
    [Test] procedure AnArchiveUriUsesTheArchiveFolder;
    [Test] procedure AFindUriUsesTheKnownRoot;
    [Test] procedure AFindUriWithoutARootKeepsItsPath;
    [Test] procedure ShellPathsSkipArchivesAndFindResults;
  end;

implementation

uses
  System.SysUtils,
  uDualPanelCommandRun, uVfsTypes;

procedure TTestDualPanelCommandRun.AFolderUriIsItsLocalPath;
begin
  Assert.AreEqual(FileUriToPath('file:///C:/work'),
    LocalCommandDirectory('file:///C:/work', False, ''));
end;

procedure TTestDualPanelCommandRun.AnArchiveUriUsesTheArchiveFolder;
var
  URI: string;
begin
  URI := 'file:///C:/work/a.zip!/inner';
  Assert.AreEqual(SafeDirectoryName(ArchiveBasePath(URI)),
    LocalCommandDirectory(URI, True, 'D:\data'));
end;

procedure TTestDualPanelCommandRun.AFindUriUsesTheKnownRoot;
begin
  Assert.AreEqual('D:\data',
    LocalCommandDirectory('find://1', True, 'D:\data'));
end;

procedure TTestDualPanelCommandRun.AFindUriWithoutARootKeepsItsPath;
begin
  Assert.AreEqual(FileUriToPath('find://1'),
    LocalCommandDirectory('find://1', False, 'D:\data'));
end;

procedure TTestDualPanelCommandRun.ShellPathsSkipArchivesAndFindResults;
var
  Sources, Paths: TArray<string>;
begin
  SetLength(Sources, 4);
  Sources[0] := 'file:///C:/work/a.zip!/inner';
  Sources[1] := 'find://1';
  Sources[2] := '';
  Sources[3] := 'file:///C:/work/note.txt';
  Paths := LocalShellPaths(Sources);
  Assert.AreEqual<Integer>(1, Length(Paths));
  Assert.AreEqual(FileUriToPath('file:///C:/work/note.txt'), Paths[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDualPanelCommandRun);

end.
