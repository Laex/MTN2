unit TestPackEach;

{ uPackEach: one ZIP per item, folder trees with empty folders, free names
  for existing archives, cancel leaves nothing behind. Throw-away files in
  %TEMP%. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPackEach = class
  public
    [SetupFixture] procedure SetupFixture;
    [TearDownFixture] procedure TearDownFixture;
    [Test] procedure TestOneArchivePerItem;
    [Test] procedure TestExistingArchiveIsNotReplaced;
    [Test] procedure TestCancelLeavesNoArchive;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Zip, uArchiveTest, uPackEach;

var
  Root: string;

procedure TTestPackEach.SetupFixture;
begin
  Root := TPath.Combine(TPath.GetTempPath, 'mtn2-packeach');
  if TDirectory.Exists(Root) then
    TDirectory.Delete(Root, True);
  ForceDirectories(Root);
end;

procedure TTestPackEach.TearDownFixture;
begin
  TDirectory.Delete(Root, True);
end;

function Entries(const AZip: string): string;
var
  Z: TZipFile;
  I: Integer;
begin
  Result := '';
  Z := TZipFile.Create;
  try
    Z.Open(AZip, zmRead);
    for I := 0 to Z.FileCount - 1 do
      Result := Result + Z.FileName[I] + ';';
  finally
    Z.Free;
  end;
end;

procedure TTestPackEach.TestOneArchivePerItem;
var
  Src, Dst: string;
  Count: Integer;
  R: TArchiveTestResult;
begin
  Src := TPath.Combine(Root, 'src1');
  Dst := TPath.Combine(Root, 'dst1');
  ForceDirectories(TPath.Combine(Src, 'Docs' + PathDelim + 'Deep'));
  ForceDirectories(TPath.Combine(Src, 'Docs' + PathDelim + 'Empty'));
  TFile.WriteAllText(TPath.Combine(Src, 'note.txt'), 'hello');
  TFile.WriteAllText(TPath.Combine(Src, 'Docs' + PathDelim + 'a.txt'), 'a');
  TFile.WriteAllText(TPath.Combine(Src, 'Docs' + PathDelim + 'Deep' + PathDelim + 'b.txt'), 'b');
  ForceDirectories(Dst);
  Assert.IsTrue(PackEachToZip([TPath.Combine(Src, 'note.txt'), TPath.Combine(Src, 'Docs')],
    Dst, nil, Count), 'finished');
  Assert.AreEqual(2, Count, 'two archives');
  Assert.AreEqual('note.txt;', Entries(TPath.Combine(Dst, 'note.zip')), 'file archive');
  Assert.IsTrue(Entries(TPath.Combine(Dst, 'Docs.zip')).Contains('Docs/Deep/b.txt;'),
    'folder tree is inside');
  Assert.IsTrue(Entries(TPath.Combine(Dst, 'Docs.zip')).Contains('Docs/Empty/;'),
    'empty folder is kept');
  R := TestZipArchive(TPath.Combine(Dst, 'Docs.zip'), nil);
  Assert.AreEqual(0, R.Failed, 'archive is healthy');
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(Dst, '*.tmp'))), 'no temporary files');
end;

procedure TTestPackEach.TestExistingArchiveIsNotReplaced;
var
  Src, Dst: string;
  Count: Integer;
begin
  Src := TPath.Combine(Root, 'src2');
  Dst := TPath.Combine(Root, 'dst2');
  ForceDirectories(Src);
  ForceDirectories(Dst);
  TFile.WriteAllText(TPath.Combine(Src, 'x.txt'), 'x');
  TFile.WriteAllText(TPath.Combine(Dst, 'x.zip'), 'keep me');
  Assert.IsTrue(PackEachToZip([TPath.Combine(Src, 'x.txt')], Dst, nil, Count));
  Assert.AreEqual('keep me', TFile.ReadAllText(TPath.Combine(Dst, 'x.zip')), 'old one untouched');
  Assert.IsTrue(TFile.Exists(TPath.Combine(Dst, 'x (2).zip')), 'new one has a free name');
end;

procedure TTestPackEach.TestCancelLeavesNoArchive;
var
  Src, Dst: string;
  Count: Integer;
begin
  Src := TPath.Combine(Root, 'src3');
  Dst := TPath.Combine(Root, 'dst3');
  ForceDirectories(Src);
  ForceDirectories(Dst);
  TFile.WriteAllText(TPath.Combine(Src, 'y.txt'), 'y');
  Assert.IsFalse(PackEachToZip([TPath.Combine(Src, 'y.txt')], Dst,
    function: Boolean
    begin
      Result := True;
    end, Count), 'cancelled reports False');
  Assert.AreEqual(0, Count, 'nothing created');
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(Dst))), 'folder is empty');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPackEach);

end.
