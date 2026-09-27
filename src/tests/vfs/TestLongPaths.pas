unit TestLongPaths;

{ Smoke checks: file:// VFS operations on paths longer than MAX_PATH.
  Deliberately built WITHOUT a longPathAware manifest, so it only passes when
  WinApiPath's \\?\ prefix does the work (it must not depend on the
  LongPathsEnabled registry switch). Works in a temp folder it removes. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLongPaths = class
  public
    [SetupFixture] procedure SetupFixture;
    [Test] procedure TestWinApiPath;
    [Test] procedure TestVfsOps;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVfsTypes,
  uFileVfs;

var
  Vfs: IVirtualFileSystem;

// VFS callbacks arrive via TThread.Queue; pump them until ADone flips.
procedure WaitFor(var ADone: Boolean);
var
  Deadline: UInt64;
begin
  Deadline := TThread.GetTickCount64 + 30000;
  while not ADone and (TThread.GetTickCount64 < Deadline) do
  begin
    CheckSynchronize(10);
  end;
  if not ADone then
    raise Exception.Create('VFS callback timed out');
end;

function RunBool(const AStart: TProc<TVfsBoolCallback>; out AErr: TVfsError): Boolean;
var
  Done, Ok: Boolean;
  Err: TVfsError;
begin
  Done := False;
  Ok := False;
  AStart(
    procedure(const ASuccess: Boolean; const AError: TVfsError)
    begin
      Ok := ASuccess;
      Err := AError;
      Done := True;
    end);
  WaitFor(Done);
  AErr := Err;
  Result := Ok;
end;

procedure TestWinApiPath;
var
  Long: string;
begin
  Assert.IsTrue(WinApiPath('D:\short\a.txt') = 'D:\short\a.txt', 'short path unchanged');
  Long := 'D:\' + StringOfChar('a', 300);
  Assert.IsTrue(WinApiPath(Long) = '\\?\' + Long, 'long drive path prefixed');
  Assert.IsTrue(WinApiPath('\\srv\share\' + StringOfChar('b', 300)) =
    '\\?\UNC\srv\share\' + StringOfChar('b', 300), 'long UNC path prefixed');
  Assert.IsTrue(WinApiPath('\\?\' + Long) = '\\?\' + Long, 'already prefixed unchanged');
  Assert.IsTrue(WinApiPath(StringOfChar('c', 300)) = StringOfChar('c', 300), 'relative unchanged');
  Assert.IsTrue(WinApiPath('D:/' + StringOfChar('a', 300)) = '\\?\' + Long,
    'forward slashes normalized under prefix');
end;

procedure TestVfsOps;
var
  Root, Deep, SrcDir, DstDir, F, Moved, NewDir: string;
  I: Integer;
  Done: Boolean;
  Items: TArray<TVfsEntry>;
  Bytes: TBytes;
  Err: TVfsError;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-longpath-' + IntToStr(TThread.CurrentThread.ThreadID));
  Deep := Root;
  for I := 1 to 6 do
    Deep := Deep + '\' + StringOfChar(Char(Ord('a') + I), 50);
  SrcDir := Deep + '\src';
  DstDir := Deep + '\dst';
  F := SrcDir + '\file.txt';
  Assert.IsTrue(Length(F) > 300, Format('test path is long (%d chars)', [Length(F)]));

  Assert.IsTrue(RunBool(
    procedure(ACb: TVfsBoolCallback)
    begin
      Vfs.CreateDirectoryAsync(PathToFileUri(Deep), nil, ACb);
    end, Err), 'CreateDirectoryAsync (nested, long): ' + Err.Message);
  // Seed via the prefixed RTL path; the VFS calls below get the plain one.
  TDirectory.CreateDirectory(WinApiPath(SrcDir + '\sub'));
  TFile.WriteAllText(WinApiPath(F), 'hello');
  TFile.WriteAllText(WinApiPath(SrcDir + '\sub\inner.txt'), 'inner');

  Done := False;
  Vfs.ListDirectoryAsync(PathToFileUri(SrcDir), nil,
    procedure(const AItems: TArray<TVfsEntry>; const AError: TVfsError)
    begin
      Items := AItems;
      Err := AError;
      Done := True;
    end);
  WaitFor(Done);
  Assert.IsTrue((Err.Code = vecOk) and (Length(Items) = 2), 'ListDirectoryAsync sees 2 items');

  Done := False;
  Vfs.ReadBytesAsync(PathToFileUri(F), 1024, nil,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    begin
      Bytes := ABytes;
      Err := AError;
      Done := True;
    end);
  WaitFor(Done);
  Assert.IsTrue((Err.Code = vecOk) and (TEncoding.UTF8.GetString(Bytes) = 'hello'),
    'ReadBytesAsync reads the file: ' + Err.Message);

  Assert.IsTrue(RunBool(
    procedure(ACb: TVfsBoolCallback)
    begin
      Vfs.CopyAsync(PathToFileUri(SrcDir), PathToFileUri(DstDir), nil, nil, ACb);
    end, Err), 'CopyAsync tree: ' + Err.Message);
  Assert.IsTrue(LocalPathIsFile(DstDir + '\sub\inner.txt'), 'copied tree has inner file');

  Moved := DstDir + '\moved.txt';
  Assert.IsTrue(RunBool(
    procedure(ACb: TVfsBoolCallback)
    begin
      Vfs.MoveAsync(PathToFileUri(DstDir + '\file.txt'), PathToFileUri(Moved), nil, nil, ACb);
    end, Err), 'MoveAsync file: ' + Err.Message);
  Assert.IsTrue(LocalPathIsFile(Moved) and not LocalPathIsFile(DstDir + '\file.txt'),
    'moved file is at the new name only');

  NewDir := Deep + '\made';
  Assert.IsTrue(RunBool(
    procedure(ACb: TVfsBoolCallback)
    begin
      Vfs.CreateDirectoryAsync(PathToFileUri(NewDir), nil, ACb);
    end, Err), 'CreateDirectoryAsync leaf: ' + Err.Message);
  Assert.IsTrue(LocalPathIsDirectory(NewDir), 'new folder exists');

  Assert.IsTrue(RunBool(
    procedure(ACb: TVfsBoolCallback)
    begin
      Vfs.DeleteAsync(PathToFileUri(Root), vdmPermanent, nil, nil, ACb);
    end, Err), 'DeleteAsync permanent tree: ' + Err.Message);
  Assert.IsTrue(not LocalPathIsDirectory(Root), 'temp tree removed');
  if LocalPathIsDirectory(Root) then
    TDirectory.Delete(WinApiPath(Root), True);
end;

{ TTestLongPaths }

procedure TTestLongPaths.SetupFixture;
begin
  Vfs := TFileVirtualFileSystem.Create;
end;

procedure TTestLongPaths.TestWinApiPath;
begin
  TestLongPaths.TestWinApiPath;
end;

procedure TTestLongPaths.TestVfsOps;
begin
  TestLongPaths.TestVfsOps;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLongPaths);

end.
