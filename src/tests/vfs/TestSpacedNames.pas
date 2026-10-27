unit TestSpacedNames;

{ Names that start or end with a space survive URI joining and splitting, so such a
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
    [Test] procedure FolderWithTrailingSpaceIsReachable;
    [Test] procedure FolderWithTrailingSpaceCanBeRenamed;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.Classes, uVfsTypes, uFileVfs;

// Win32 drops a space at the end of a folder name unless the path starts with
// \\?\, so the folder is made and removed with that prefix.
function ExactPath(const APath: string): string;
begin
{$IFDEF MSWINDOWS}
  Result := '\\?\' + APath;
{$ELSE}
  Result := APath;
{$ENDIF}
end;

procedure MakeDirExact(const APath: string);
begin
{$IFDEF MSWINDOWS}
  Assert.IsTrue(CreateDirectoryW(PChar(ExactPath(APath)), nil), 'folder created');
{$ELSE}
  TDirectory.CreateDirectory(APath);
{$ENDIF}
end;

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

procedure TTestSpacedNames.FolderWithTrailingSpaceIsReachable;
var
  Dir, Sub, SubPath: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-spaced-' + IntToStr(Random(MaxInt)));
  SubPath := Dir + PathDelim + 'trail ';
  TDirectory.CreateDirectory(Dir);
  MakeDirExact(SubPath);
  try
    TFile.WriteAllText(ExactPath(SubPath) + PathDelim + 'a.txt', 'a');
    Sub := NormalizeLocalPath(FileUriToPath(JoinVfsUri(PathToFileUri(Dir), 'trail ')));
    Assert.AreEqual(Dir + PathDelim + 'trail ', Sub, 'the space at the end of the name stays');
    Assert.IsTrue(LocalPathIsDirectory(Sub), 'the folder is found');
    Assert.IsTrue(LocalPathIsFile(Sub + PathDelim + 'a.txt'), 'its content is reachable');
  finally
    TFile.Delete(ExactPath(SubPath) + PathDelim + 'a.txt');
{$IFDEF MSWINDOWS}
    RemoveDirectoryW(PChar(ExactPath(SubPath)));
{$ELSE}
    TDirectory.Delete(SubPath);
{$ENDIF}
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSpacedNames.FolderWithTrailingSpaceCanBeRenamed;
var
  Dir, SubPath: string;
  Vfs: IVirtualFileSystem;
  Done, Ok: Boolean;
  Msg: string;
  Deadline: UInt64;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'mtn2-spaced-' + IntToStr(Random(MaxInt)));
  SubPath := Dir + PathDelim + 'trail ';
  TDirectory.CreateDirectory(Dir);
  MakeDirExact(SubPath);
  try
    Vfs := TFileVirtualFileSystem.Create;
    Done := False;
    Ok := False;
    Vfs.MoveAsync(PathToFileUri(SubPath), PathToFileUri(Dir + PathDelim + 'trail'), nil, nil,
      procedure(const ASuccess: Boolean; const AError: TVfsError)
      begin
        Ok := ASuccess;
        Msg := AError.Message;
        Done := True;
      end);
    Deadline := TThread.GetTickCount64 + 30000;
    while not Done and (TThread.GetTickCount64 < Deadline) do
      CheckSynchronize(10);
    Assert.IsTrue(Ok, 'renamed: ' + Msg);
    Assert.IsTrue(TDirectory.Exists(Dir + PathDelim + 'trail'), 'the folder has the new name');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

end.
