unit TestDriveUnc;

{ UNC share handling of the Change Drive list: the share root of a path and
  the network entries added after the drives. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDriveUnc = class
  public
    [Test] procedure TestShareRootOfUncPaths;
    [Test] procedure TestShareRootRejectsOtherPaths;
    [Test] procedure TestSharesAreAppendedOnceInOrder;
    [Test] procedure TestMappedShareIsNotListedTwice;
    [Test] procedure TestShareCountIsLimited;
  end;

implementation

uses
  System.SysUtils, uDriveInfo, uDriveTypes;

function MappedDrive(ALetter: Char; const AUnc: string): TDriveInfo;
begin
  Result := Default(TDriveInfo);
  Result.Letter := ALetter;
  Result.RootPath := ALetter + ':\';
  Result.KindLabel := 'Network';
  Result.LabelOrPath := AUnc;
end;

procedure TTestDriveUnc.TestShareRootOfUncPaths;
begin
  Assert.AreEqual('\\srv\data', UncShareRoot('\\srv\data'));
  Assert.AreEqual('\\srv\data', UncShareRoot('\\srv\data\'));
  Assert.AreEqual('\\srv\data', UncShareRoot('\\srv\data\dir\file.txt'));
  Assert.AreEqual('\\srv\data', UncShareRoot('\\?\UNC\srv\data\dir'));
end;

procedure TTestDriveUnc.TestShareRootRejectsOtherPaths;
begin
  Assert.AreEqual('', UncShareRoot(''));
  Assert.AreEqual('', UncShareRoot('C:\Work'));
  Assert.AreEqual('', UncShareRoot('\\srv'));
  Assert.AreEqual('', UncShareRoot('\\srv\'));
  Assert.AreEqual('', UncShareRoot('\\?\C:\Work'));
  Assert.AreEqual('', UncShareRoot('/home/user'));
end;

procedure TTestDriveUnc.TestSharesAreAppendedOnceInOrder;
var
  Drives, Res: TDriveInfoArray;
begin
  SetLength(Drives, 1);
  Drives[0] := MappedDrive('C', 'System');
  Res := AppendUncShares(Drives, ['C:\Work', '\\b\two\x', '\\a\one', '\\B\TWO\y', ''], 8);
  Assert.AreEqual<Integer>(3, Length(Res), 'one drive and two distinct shares');
  Assert.AreEqual('C', string(Res[0].Letter));
  Assert.AreEqual(#0, Res[1].Letter, 'a share has no letter');
  Assert.AreEqual('\\b\two', Res[1].LabelOrPath, 'first seen first');
  Assert.AreEqual('\\b\two\', Res[1].RootPath);
  Assert.AreEqual('\\a\one', Res[2].LabelOrPath);
end;

procedure TTestDriveUnc.TestMappedShareIsNotListedTwice;
var
  Drives, Res: TDriveInfoArray;
begin
  SetLength(Drives, 1);
  Drives[0] := MappedDrive('Z', '\\srv\data');
  Res := AppendUncShares(Drives, ['\\SRV\Data\sub', '\\srv\other'], 8);
  Assert.AreEqual<Integer>(2, Length(Res), 'the mapped share stays behind its letter');
  Assert.AreEqual('\\srv\other', Res[1].LabelOrPath);
end;

procedure TTestDriveUnc.TestShareCountIsLimited;
var
  Res: TDriveInfoArray;
begin
  Res := AppendUncShares(nil, ['\\s\a', '\\s\b', '\\s\c', '\\s\d'], 2);
  Assert.AreEqual<Integer>(2, Length(Res));
  Assert.AreEqual('\\s\a', Res[0].LabelOrPath);
  Assert.AreEqual('\\s\b', Res[1].LabelOrPath);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDriveUnc);

end.
