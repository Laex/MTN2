unit TestUnpackEach;

{ uUnpackEach: folder names for archives (double extensions, free names) and
  unpacking each archive into its own folder, with the 7-Zip engine when one
  is installed. Throw-away files in %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnpackEach = class
  public
    [Test] procedure TestFolderNameDropsExtension;
    [Test] procedure TestFolderNameDropsTarOfCompressedTar;
    [Test] procedure TestTargetDirIsFree;
    [Test] procedure TestEachArchiveGetsItsOwnFolder;
    [Test] procedure TestBrokenArchiveIsReportedAndLeavesNoFolder;
    [Test] procedure TestCancelLeavesNothing;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  uPlatformPaths, uPlatformProcess, uSevenZipApi, uUnpackEach;

function EnginePath: string;
const
  Candidates: array[0..2] of string = (
    'C:\Program Files\7-Zip\7z.dll',
    'C:\Program Files\Far Manager\Plugins\ArcLite\7z.dll',
    'C:\Program Files (x86)\7-Zip\7z.dll'
  );
var
  S: string;
begin
  Result := '';
  if PlatformPosixPaths then
    Exit(PlatformSevenZipEngine(''));
  S := GetEnvironmentVariable('MTN2_7Z_DLL');
  if (S <> '') and TFile.Exists(S) then
    Exit(S);
  for S in Candidates do
    if TFile.Exists(S) then
      Exit(S);
end;

function NewRoot(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mtn2-unpackeach-' + AName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  ForceDirectories(Result);
end;

procedure MakeZip(const AZip, AEntryName, AText: string);
var
  Z: TZipFile;
  S: TBytesStream;
begin
  Z := TZipFile.Create;
  S := TBytesStream.Create(TEncoding.UTF8.GetBytes(AText));
  try
    Z.Open(AZip, zmWrite);
    Z.Add(S, AEntryName);
    Z.Close;
  finally
    S.Free;
    Z.Free;
  end;
end;

procedure TTestUnpackEach.TestFolderNameDropsExtension;
begin
  Assert.AreEqual('data', UnpackEachFolderName('data.zip'));
  Assert.AreEqual('my.report', UnpackEachFolderName('my.report.7z'));
  Assert.AreEqual('noext', UnpackEachFolderName('noext'));
end;

procedure TTestUnpackEach.TestFolderNameDropsTarOfCompressedTar;
begin
  Assert.AreEqual('src', UnpackEachFolderName('src.tar.gz'));
  Assert.AreEqual('src', UnpackEachFolderName('src.TAR.xz'));
end;

procedure TTestUnpackEach.TestTargetDirIsFree;
var
  Root: string;
begin
  Root := NewRoot('names');
  try
    Assert.AreEqual(TPath.Combine(Root, 'a'), UnpackEachTargetDir(Root, 'a.zip'), 'free name');
    ForceDirectories(TPath.Combine(Root, 'a'));
    Assert.AreEqual(TPath.Combine(Root, 'a (2)'), UnpackEachTargetDir(Root, 'a.zip'), 'folder taken');
    TFile.WriteAllText(TPath.Combine(Root, 'a (2)'), 'x');
    Assert.AreEqual(TPath.Combine(Root, 'a (3)'), UnpackEachTargetDir(Root, 'a.zip'), 'file taken');
  finally
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestUnpackEach.TestEachArchiveGetsItsOwnFolder;
var
  Root, Dst: string;
  Count: Integer;
  Failed: TArray<string>;
begin
  if EnginePath = '' then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Root := NewRoot('own');
  Dst := TPath.Combine(Root, 'dst');
  ForceDirectories(Dst);
  MakeZip(TPath.Combine(Root, 'one.zip'), 'a.txt', 'alpha');
  MakeZip(TPath.Combine(Root, 'two.zip'), 'a.txt', 'beta');
  ForceDirectories(TPath.Combine(Dst, 'one'));
  Assert.IsTrue(SevenZipLoadEngine(EnginePath), 'load engine');
  try
    Assert.IsTrue(UnpackEachArchive([TPath.Combine(Root, 'one.zip'), TPath.Combine(Root, 'two.zip')],
      Dst, nil, Count, Failed), 'finished');
    Assert.AreEqual(2, Count, 'both unpacked');
    Assert.AreEqual(0, Integer(Length(Failed)), 'none failed');
    Assert.AreEqual('alpha', TFile.ReadAllText(TPath.Combine(Dst, 'one (2)' + PathDelim + 'a.txt')),
      'existing folder is not reused');
    Assert.AreEqual('beta', TFile.ReadAllText(TPath.Combine(Dst, 'two' + PathDelim + 'a.txt')),
      'second archive in its own folder');
  finally
    SevenZipUnloadEngine;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestUnpackEach.TestBrokenArchiveIsReportedAndLeavesNoFolder;
var
  Root, Dst: string;
  Count: Integer;
  Failed: TArray<string>;
begin
  if EnginePath = '' then
    Assert.Pass('SKIP: no 7-Zip engine found');
  Root := NewRoot('broken');
  Dst := TPath.Combine(Root, 'dst');
  ForceDirectories(Dst);
  TFile.WriteAllText(TPath.Combine(Root, 'bad.zip'), 'not an archive at all');
  MakeZip(TPath.Combine(Root, 'good.zip'), 'a.txt', 'alpha');
  Assert.IsTrue(SevenZipLoadEngine(EnginePath), 'load engine');
  try
    Assert.IsTrue(UnpackEachArchive([TPath.Combine(Root, 'bad.zip'), TPath.Combine(Root, 'good.zip')],
      Dst, nil, Count, Failed), 'finished');
    Assert.AreEqual(1, Count, 'the good one is unpacked');
    Assert.AreEqual('bad.zip', string.Join(',', Failed), 'the bad one is reported');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(Dst, 'bad')), 'no folder for the bad one');
    Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'good' + PathDelim + 'a.txt')), 'good one is there');
  finally
    SevenZipUnloadEngine;
    TDirectory.Delete(Root, True);
  end;
end;

procedure TTestUnpackEach.TestCancelLeavesNothing;
var
  Root, Dst: string;
  Count: Integer;
  Failed: TArray<string>;
begin
  Root := NewRoot('cancel');
  Dst := TPath.Combine(Root, 'dst');
  ForceDirectories(Dst);
  try
    Assert.IsFalse(UnpackEachArchive([TPath.Combine(Root, 'x.zip')], Dst,
      function: Boolean
      begin
        Result := True;
      end, Count, Failed), 'cancelled reports False');
    Assert.AreEqual(0, Count, 'nothing unpacked');
    Assert.AreEqual(0, Integer(Length(TDirectory.GetDirectories(Dst))), 'destination is empty');
  finally
    TDirectory.Delete(Root, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnpackEach);

end.
