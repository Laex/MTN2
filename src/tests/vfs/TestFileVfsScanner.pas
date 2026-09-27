unit TestFileVfsScanner;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileVfsScanner = class
  public
    [Test] procedure TestScanner;
  end;

implementation

uses
  System.SysUtils,
  uVfsTypes,
  uFileVfsScanner;

procedure TestScanner;
var
  LEntries: TArray<TVfsEntry>;
  LSuccess: Boolean;
begin
  LSuccess := TFileVfsScanner.ScanDirectory('.', LEntries);
  Assert.IsTrue(LSuccess, 'Should scan current directory successfully');
  Assert.IsTrue(Length(LEntries) > 0, 'Current directory should contain entries');

  Writeln('OK: TestScanner passed');
end;

{ TTestFileVfsScanner }

procedure TTestFileVfsScanner.TestScanner;
begin
  TestFileVfsScanner.TestScanner;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileVfsScanner);

end.
