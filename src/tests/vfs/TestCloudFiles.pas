unit TestCloudFiles;

{ uCloudFiles: counting of cloud-only files in files and folder trees, the
  entry budget, and the neutral result of the platform check on ordinary
  files. Throw-away files in %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCloudFiles = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestCountsMarkedFilesInTrees;
    [Test] procedure TestBudgetStopsTheWalk;
    [Test] procedure TestOrdinaryFilesAreNotCloudOnly;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uCloudFiles, uPlatformFileOps;

var
  Root: string;

procedure Touch(const APath: string);
begin
  ForceDirectories(ExtractFilePath(APath));
  TFile.WriteAllText(APath, 'x');
end;

procedure TTestCloudFiles.SetupFixture;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-cloudfiles');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  ForceDirectories(Root);
  Touch(TPath.Combine(Root, 'a.cloud'));
  Touch(TPath.Combine(Root, 'b.txt'));
  Touch(TPath.Combine(Root, 'sub' + PathDelim + 'c.cloud'));
  Touch(TPath.Combine(Root, 'sub' + PathDelim + 'deep' + PathDelim + 'd.cloud'));
  Touch(TPath.Combine(Root, 'sub' + PathDelim + 'deep' + PathDelim + 'e.txt'));
end;

procedure TTestCloudFiles.TearDownFixture;
begin
  TDirectory.Delete(Root, True);
end;

procedure TTestCloudFiles.TestCountsMarkedFilesInTrees;
var
  IsCloud: TIsCloudOnly;
begin
  IsCloud := function(const APath: string): Boolean
    begin
      Result := APath.EndsWith('.cloud');
    end;
  Assert.AreEqual(3, CountCloudOnlyFiles([Root], IsCloud), 'folder walked recursively');
  Assert.AreEqual(1, CountCloudOnlyFiles([TPath.Combine(Root, 'a.cloud'),
    TPath.Combine(Root, 'b.txt')], IsCloud), 'plain file paths');
  Assert.AreEqual(0, CountCloudOnlyFiles([], IsCloud), 'nothing selected');
end;

procedure TTestCloudFiles.TestBudgetStopsTheWalk;
var
  Calls: Integer;
  IsCloud: TIsCloudOnly;
begin
  Calls := 0;
  IsCloud := function(const APath: string): Boolean
    begin
      Inc(Calls);
      Result := True;
    end;
  CountCloudOnlyFiles([Root], IsCloud, 2);
  Assert.IsTrue(Calls <= 2, 'at most the budget of entries is looked at');
end;

procedure TTestCloudFiles.TestOrdinaryFilesAreNotCloudOnly;
begin
  Assert.IsFalse(PlatformIsCloudOnlyFile(TPath.Combine(Root, 'b.txt')), 'ordinary file');
  Assert.IsFalse(PlatformIsCloudOnlyFile(Root), 'folder');
  Assert.IsFalse(PlatformIsCloudOnlyFile(TPath.Combine(Root, 'missing.bin')), 'missing file');
  Assert.AreEqual(0, CountCloudOnlyFiles([Root]), 'platform check on a plain tree');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCloudFiles);

end.
